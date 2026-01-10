# ============================================================================
# SAFETY GUARDRAILS & SIMULATION ENGINE
# Prevents accidental damage to healthy systems
# ============================================================================

# Set strict mode for safety
Set-StrictMode -Version Latest

# Repair Modes
enum RepairMode {
    DIAGNOSE_ONLY    # Read-only, no writes
    REPAIR_SAFE      # Limited writes, reversible only
    REPAIR_FORCE     # Destructive allowed (WinRE/WinPE only)
}

function Get-RepairMode {
    <#
    .SYNOPSIS
    Determines the appropriate repair mode based on environment and user preferences.
    
    .PARAMETER AllowOnlineRepair
    Allow REPAIR_SAFE mode in full Windows (not recommended)
    
    .PARAMETER ForceMode
    Force a specific mode (for testing)
    
    .OUTPUTS
    RepairMode enum value
    #>
    
    param(
        [switch]$AllowOnlineRepair,
        [string]$ForceMode = $null
    )
    
    if ($ForceMode) {
        switch ($ForceMode.ToUpper()) {
            "DIAGNOSE_ONLY" { return [RepairMode]::DIAGNOSE_ONLY }
            "REPAIR_SAFE" { return [RepairMode]::REPAIR_SAFE }
            "REPAIR_FORCE" { return [RepairMode]::REPAIR_FORCE }
            default { return [RepairMode]::DIAGNOSE_ONLY }
        }
    }
    
    $envCheck = Test-EnvironmentSafety
    
    # In WinRE/WinPE, allow REPAIR_FORCE
    if ($envCheck.IsSafe) {
        return [RepairMode]::REPAIR_FORCE
    }
    
    # In full Windows, default to DIAGNOSE_ONLY
    if ($envCheck.Environment -eq "FullOS") {
        if ($AllowOnlineRepair) {
            return [RepairMode]::REPAIR_SAFE
        } else {
            return [RepairMode]::DIAGNOSE_ONLY
        }
    }
    
    # Default to safest mode
    return [RepairMode]::DIAGNOSE_ONLY
}

function Test-CommandAllowed {
    <#
    .SYNOPSIS
    Checks if a command is allowed in the current repair mode.
    
    .PARAMETER Command
    Command name or description
    
    .PARAMETER IsDestructive
    Whether the command modifies the system
    
    .PARAMETER CurrentMode
    Current repair mode
    
    .OUTPUTS
    Boolean - true if allowed, false if blocked
    #>
    
    param(
        [string]$Command,
        [bool]$IsDestructive = $true,
        [RepairMode]$CurrentMode = [RepairMode]::DIAGNOSE_ONLY
    )
    
    # Read-only commands always allowed
    if (-not $IsDestructive) {
        return $true
    }
    
    # Destructive commands blocked in DIAGNOSE_ONLY
    if ($CurrentMode -eq [RepairMode]::DIAGNOSE_ONLY) {
        return $false
    }
    
    # Highly destructive commands only in REPAIR_FORCE
    $highlyDestructive = @(
        "diskpart clean",
        "format",
        "bcdboot targeting different disk",
        "bootrec writes",
        "changing firmware boot entries",
        "deleting/renaming BCD",
        "wiping EFI\Microsoft\Boot"
    )
    
    foreach ($destructive in $highlyDestructive) {
        if ($Command -match $destructive) {
            if ($CurrentMode -ne [RepairMode]::REPAIR_FORCE) {
                return $false
            }
        }
    }
    
    # REPAIR_SAFE allows reversible operations
    if ($CurrentMode -eq [RepairMode]::REPAIR_SAFE) {
        # Allow: mount ESP, read BCD, copy files if missing
        # Block: format, delete, rewrite BCD
        if ($Command -match "format|delete|rewrite|clean") {
            return $false
        }
    }
    
    return $true
}

function Test-EnvironmentSafety {
    <#
    .SYNOPSIS
    Detects if tool is running in safe environment (WinRE/WinPE) or live Windows.
    
    .DESCRIPTION
    Checks if destructive repairs are safe to run:
    - WinRE/WinPE (X: drive) = SAFE (destructive repairs allowed)
    - Full Windows OS (C: drive) = UNSAFE (read-only diagnostic mode)
    
    .OUTPUTS
    PSCustomObject with properties:
    - IsSafe: Boolean (true if safe for destructive repairs)
    - Environment: "WinRE", "WinPE", "FullOS", or "Unknown"
    - SystemDrive: Current system drive letter
    - SafetyMessage: Human-readable safety status
    #>
    
    $result = @{
        IsSafe = $false
        Environment = "Unknown"
        SystemDrive = $env:SystemDrive
        SafetyMessage = ""
        Recommendations = @()
    }
    
    try {
        # Check if running from X: (WinPE/WinRE RAM disk)
        $currentDrive = (Get-Location).Drive.Name
        $systemDrive = $env:SystemDrive.TrimEnd(':')
        
        # Check for WinPE/WinRE indicators
        $isWinPE = $false
        $isWinRE = $false
        
        # Method 1: Check if running from X: drive
        if ($currentDrive -eq "X" -or $systemDrive -eq "X") {
            $isWinPE = $true
            $result.Environment = "WinPE"
            $result.IsSafe = $true
            $result.SafetyMessage = "Running in Windows Preinstallation Environment (WinPE) - Safe for destructive repairs"
        }
        
        # Method 2: Check for WinRE registry key
        try {
            $winrePath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SystemStartOptions" -ErrorAction SilentlyContinue).SystemStartOptions
            if ($winrePath -match "WINRE") {
                $isWinRE = $true
                $result.Environment = "WinRE"
                $result.IsSafe = $true
                $result.SafetyMessage = "Running in Windows Recovery Environment (WinRE) - Safe for destructive repairs"
            }
        } catch {
            # Registry check failed, continue with other methods
        }
        
        # Method 3: Check for WinPE environment variables
        if ($env:_SMSTSBootPEID -or $env:SYSTEMROOT -eq "X:\Windows") {
            $isWinPE = $true
            $result.Environment = "WinPE"
            $result.IsSafe = $true
            $result.SafetyMessage = "Running in Windows Preinstallation Environment (WinPE) - Safe for destructive repairs"
        }
        
        # Method 4: Check if Windows directory is on different drive than system drive
        # In WinPE, Windows is typically on X:, but target OS is on C:, D:, etc.
        if (-not $isWinPE -and -not $isWinRE) {
            $windowsPath = "$env:SystemRoot"
            $windowsDrive = (Split-Path -Qualifier $windowsPath).TrimEnd(':')
            
            if ($windowsDrive -eq "X") {
                $result.Environment = "WinPE"
                $result.IsSafe = $true
                $result.SafetyMessage = "Running in Windows Preinstallation Environment (WinPE) - Safe for destructive repairs"
            } elseif ($systemDrive -eq "C" -and $windowsDrive -eq "C") {
                # Running in full Windows OS
                $result.Environment = "FullOS"
                $result.IsSafe = $false
                $result.SafetyMessage = "Running in LIVE Windows OS - Destructive repairs are DISABLED"
                $result.Recommendations += "Boot from Windows Recovery USB/DVD to apply fixes"
                $result.Recommendations += "Or use 'Read-Only Diagnostic Mode' to analyze issues"
            } else {
                $result.Environment = "Unknown"
                $result.IsSafe = $false
                $result.SafetyMessage = "Environment detection uncertain - Proceeding with caution"
                $result.Recommendations += "Verify you are in WinRE/WinPE before running repairs"
            }
        }
        
    } catch {
        $result.Environment = "Unknown"
        $result.IsSafe = $false
        $result.SafetyMessage = "Environment detection failed: $_"
        $result.Recommendations += "Manually verify environment before proceeding"
    }
    
    return $result
}

function Test-CommandSafety {
    <#
    .SYNOPSIS
    Checks if a command is safe to execute in current environment.
    
    .PARAMETER Command
    The command name or path to check
    
    .PARAMETER IsDestructive
    Whether the command modifies the system (true) or is read-only (false)
    
    .OUTPUTS
    Boolean - true if safe to execute, false if blocked
    #>
    
    param(
        [string]$Command,
        [bool]$IsDestructive = $true
    )
    
    $envCheck = Test-EnvironmentSafety
    
    # Read-only commands are always safe
    if (-not $IsDestructive) {
        return $true
    }
    
    # Destructive commands are only safe in WinRE/WinPE
    if ($envCheck.IsSafe) {
        return $true
    }
    
    # Block destructive commands in live Windows
    return $false
}

function Get-RepairState {
    <#
    .SYNOPSIS
    Generates internal state debug output for diagnostics.
    
    .DESCRIPTION
    Creates a clean text block with complete repair state information
    that can be copied and shared for troubleshooting.
    
    .PARAMETER TargetDrive
    Target Windows drive letter (optional, will auto-detect)
    
    .OUTPUTS
    String containing formatted diagnostic state
    #>
    
    param(
        [string]$TargetDrive = $null
    )
    
    $output = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $output.AppendLine($separator) | Out-Null
    $output.AppendLine("REPAIR STATE DIAGNOSTIC OUTPUT") | Out-Null
    $output.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $output.AppendLine($separator) | Out-Null
    $output.AppendLine("") | Out-Null
    
    # Environment Detection
    $output.AppendLine("ENVIRONMENT DETECTION:") | Out-Null
    $envCheck = Test-EnvironmentSafety
    $output.AppendLine("  Environment: $($envCheck.Environment)") | Out-Null
    $output.AppendLine("  System Drive: $($envCheck.SystemDrive)") | Out-Null
    $output.AppendLine("  Safe for Repairs: $($envCheck.IsSafe)") | Out-Null
    $output.AppendLine("  Status: $($envCheck.SafetyMessage)") | Out-Null
    if ($envCheck.Recommendations.Count -gt 0) {
        $output.AppendLine("  Recommendations:") | Out-Null
        foreach ($rec in $envCheck.Recommendations) {
            $output.AppendLine("    - $rec") | Out-Null
        }
    }
    $output.AppendLine("") | Out-Null
    
    # Detect Windows installations
    $output.AppendLine("DETECTED DRIVES:") | Out-Null
    if ($TargetDrive) {
        $targetOS = $TargetDrive.TrimEnd(':')
    } else {
        # Auto-detect
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
        $targetOS = $null
        
        foreach ($vol in $volumes) {
            $drive = $vol.DriveLetter
            $systemHive = "$drive`:\Windows\System32\config\SYSTEM"
            if (Test-Path $systemHive) {
                $targetOS = $drive
                break
            }
        }
        
        if (-not $targetOS) {
            $targetOS = "C"
        }
    }
    
    $output.AppendLine("  OS Partition: ${targetOS}:") | Out-Null
    
    # Detect EFI partition
    $efiPartitions = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
    if ($efiPartitions) {
        $efiPartition = $efiPartitions[0]
        if ($efiPartition.DriveLetter) {
            $output.AppendLine("  EFI Partition: $($efiPartition.DriveLetter):") | Out-Null
        } else {
            $output.AppendLine("  EFI Partition: Found but not mounted (no drive letter)") | Out-Null
        }
    } else {
        $output.AppendLine("  EFI Partition: Not found (may be Legacy BIOS)") | Out-Null
    }
    $output.AppendLine("") | Out-Null
    
    # File Verification
    $output.AppendLine("FILE VERIFICATION:") | Out-Null
    $winloadPath = "${targetOS}:\Windows\System32\winload.efi"
    $winloadExists = Test-Path $winloadPath
    $output.AppendLine("  winload.efi Path: $winloadPath") | Out-Null
    $output.AppendLine("  winload.efi Exists: $winloadExists") | Out-Null
    
    if ($winloadExists) {
        try {
            $fileSize = (Get-Item $winloadPath -ErrorAction Stop).Length
            $output.AppendLine("  winload.efi Size: $fileSize bytes") | Out-Null
        } catch {
            $output.AppendLine("  winload.efi Access: DENIED or ERROR - $_") | Out-Null
        }
    }
    
    # Check winload.exe for legacy
    $winloadExePath = "${targetOS}:\Windows\System32\winload.exe"
    $winloadExeExists = Test-Path $winloadExePath
    $output.AppendLine("  winload.exe Exists: $winloadExeExists") | Out-Null
    $output.AppendLine("") | Out-Null
    
    # BCD Entry Path
    $output.AppendLine("BCD ENTRY PATH:") | Out-Null
    try {
        # Use cmd /c to properly execute bcdedit
        $bcdEnum = cmd /c "bcdedit /enum {default}" 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $bcdEnum -notmatch "Invalid command|parameter is incorrect") {
            $bcdPathMatch = $bcdEnum | Select-String "path\s+(.+)"
            if ($bcdPathMatch) {
                $bcdPath = $bcdPathMatch.Matches[0].Groups[1].Value.Trim()
                $output.AppendLine("  Current BCD Path: $bcdPath") | Out-Null
                
                if ($bcdPath -match "winload\.efi") {
                    $output.AppendLine("  BCD Points to: winload.efi (UEFI)") | Out-Null
                } elseif ($bcdPath -match "winload\.exe") {
                    $output.AppendLine("  BCD Points to: winload.exe (Legacy BIOS)") | Out-Null
                } else {
                    $output.AppendLine("  BCD Points to: Unknown/Other") | Out-Null
                }
            } else {
                $output.AppendLine("  BCD Path: Could not parse from bcdedit output") | Out-Null
            }
            
            # Check for Unknown device/osdevice
            if ($bcdEnum -match "device\s+Unknown" -or $bcdEnum -match "osdevice\s+Unknown") {
                $output.AppendLine("  WARNING: BCD shows 'Unknown' device/osdevice") | Out-Null
            }
        } else {
            $output.AppendLine("  BCD Status: ERROR - Could not read BCD store") | Out-Null
            if ($bcdEnum) {
                $errorMsg = ($bcdEnum -split "`n" | Where-Object { $_ -notmatch "Invalid command|parameter is incorrect" } | Select-Object -First 3) -join " "
                if ($errorMsg) {
                    $output.AppendLine("  Error: $errorMsg") | Out-Null
                }
            }
        }
    } catch {
        $output.AppendLine("  BCD Status: EXCEPTION - $_") | Out-Null
    }
    $output.AppendLine("") | Out-Null
    
    # BitLocker Status
    $output.AppendLine("BITLOCKER STATUS:") | Out-Null
    try {
        $bitlockerStatus = manage-bde -status "${targetOS}:" 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $lockStatusMatch = $bitlockerStatus | Select-String "Lock Status:\s+(.+)"
            if ($lockStatusMatch) {
                $lockStatus = $lockStatusMatch.Matches[0].Groups[1].Value.Trim()
                $output.AppendLine("  Lock Status: $lockStatus") | Out-Null
                
                $protectionMatch = $bitlockerStatus | Select-String "Protection Status:\s+(.+)"
                if ($protectionMatch) {
                    $protectionStatus = $protectionMatch.Matches[0].Groups[1].Value.Trim()
                    $output.AppendLine("  Protection Status: $protectionStatus") | Out-Null
                }
            } else {
                $output.AppendLine("  Status: BitLocker not enabled or status unavailable") | Out-Null
            }
        } else {
            $output.AppendLine("  Status: ERROR - Could not check BitLocker status") | Out-Null
            $output.AppendLine("  Error: $bitlockerStatus") | Out-Null
        }
    } catch {
        $output.AppendLine("  Status: EXCEPTION - $_") | Out-Null
        $output.AppendLine("  Note: manage-bde may not be available in this environment") | Out-Null
    }
    $output.AppendLine("") | Out-Null
    
    # Final Verdict
    $output.AppendLine("FINAL VERDICT:") | Out-Null
    if ($winloadExists -and $bcdPathMatch) {
        $output.AppendLine("  Will it boot? YES (winload.efi exists and BCD path is correct)") | Out-Null
    } elseif (-not $winloadExists) {
        $output.AppendLine("  Will it boot? NO (winload.efi is missing)") | Out-Null
    } elseif (-not $bcdPathMatch) {
        $output.AppendLine("  Will it boot? NO (BCD path is incorrect)") | Out-Null
    } else {
        $output.AppendLine("  Will it boot? UNKNOWN (insufficient information)") | Out-Null
    }
    $output.AppendLine("") | Out-Null
    
    $output.AppendLine($separator) | Out-Null
    $output.AppendLine("END OF REPAIR STATE DIAGNOSTIC") | Out-Null
    $output.AppendLine($separator) | Out-Null
    
    return $output.ToString()
}

function Invoke-SafeCommand {
    <#
    .SYNOPSIS
    Safely executes a command with error handling and simulation support.
    
    .PARAMETER Command
    Command to execute (as string or scriptblock)
    
    .PARAMETER Arguments
    Arguments to pass to command
    
    .PARAMETER WhatIf
    If true, only simulates the command without executing
    
    .PARAMETER IsDestructive
    Whether this command modifies the system
    
    .OUTPUTS
    PSCustomObject with properties:
    - Success: Boolean
    - Output: Command output
    - Error: Error message if failed
    - Simulated: Boolean (true if WhatIf was used)
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [string[]]$Arguments = @(),
        
        [switch]$WhatIf,
        
        [bool]$IsDestructive = $true
    )
    
    $result = @{
        Success = $false
        Output = ""
        Error = ""
        Simulated = $false
        Command = $Command
        Arguments = $Arguments
    }
    
    # Check environment safety for destructive commands
    if ($IsDestructive -and -not $WhatIf) {
        $envCheck = Test-EnvironmentSafety
        if (-not $envCheck.IsSafe) {
            $result.Error = "Command blocked: Running in live Windows OS. Destructive repairs are disabled. $($envCheck.SafetyMessage)"
            $result.Output = "[BLOCKED] $Command $($Arguments -join ' ')"
            return $result
        }
    }
    
    # Simulation mode
    if ($WhatIf) {
        $result.Simulated = $true
        $result.Success = $true
        $result.Output = "[SIMULATION] Would execute: $Command $($Arguments -join ' ')"
        return $result
    }
    
    # Execute command with error handling
    try {
        $errorOutput = $null
        $stdOutput = & $Command $Arguments 2>&1 | Tee-Object -Variable errorOutput
        
        if ($LASTEXITCODE -eq 0) {
            $result.Success = $true
            $result.Output = $stdOutput | Out-String
        } else {
            $result.Error = "Command failed with exit code $LASTEXITCODE"
            $result.Output = $errorOutput | Out-String
            
            # Translate common errors to plain English
            if ($errorOutput -match "The boot configuration data store could not be opened") {
                $result.Error = "BCD Store is corrupted or inaccessible"
            } elseif ($errorOutput -match "Access is denied") {
                $result.Error = "Access Denied - Insufficient permissions. Run as Administrator."
            } elseif ($errorOutput -match "The system cannot find the file specified") {
                $result.Error = "File not found - Source files may be missing or path is incorrect"
            }
        }
    } catch {
        $result.Error = "Exception: $($_.Exception.Message)"
        $result.Output = $_.Exception.ToString()
    }
    
    return $result
}
function New-PasteBackBundle {
    <#
    .SYNOPSIS
    Generates a paste-back bundle for review and troubleshooting.
    #>
    
    param(
        [string]$ToolVersion = 'v7.1.1',
        [string]$Mode = 'DIAGNOSE_ONLY',
        [string]$Environment = 'Unknown',
        [string]$TargetDrive = 'C',
        $ViabilityResult = $null
    )
    
    $bundle = New-Object System.Text.StringBuilder
    $separator = '=' * 80
    
    $bundle.AppendLine($separator) | Out-Null
    $bundle.AppendLine('BOOTFIX PASTE-BACK BUNDLE BEGIN') | Out-Null
    $bundle.AppendLine($separator) | Out-Null
    $bundle.AppendLine('ToolVersion: ' + $ToolVersion) | Out-Null
    $bundle.AppendLine('Mode: ' + $Mode) | Out-Null
    $bundle.AppendLine('Environment: ' + $Environment) | Out-Null
    $bundle.AppendLine('Timestamp: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-Null
    $bundle.AppendLine('') | Out-Null
    
    # Environment Detection
    $envCheck = Test-EnvironmentSafety
    $bundle.AppendLine('EnvironmentDetails:') | Out-Null
    $bundle.AppendLine('  SystemDrive: ' + $envCheck.SystemDrive) | Out-Null
    $bundle.AppendLine('  IsSafe: ' + $envCheck.IsSafe) | Out-Null
    $bundle.AppendLine('  SafetyMessage: ' + $envCheck.SafetyMessage) | Out-Null
    $bundle.AppendLine('') | Out-Null
    
    # Firmware & Disk Layout
    $firmwareType = 'Unknown'
    $diskLayout = 'Unknown'
    
    try {
        $efiPartitions = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
        if ($efiPartitions) {
            $firmwareType = 'UEFI'
            $diskLayout = 'GPT'
        } else {
            $disks = Get-Disk | Select-Object -First 1
            if ($disks -and $disks.PartitionStyle -eq 'MBR') {
                $firmwareType = 'Legacy BIOS'
                $diskLayout = 'MBR'
            }
        }
    } catch {
        # Detection failed
    }
    
    $bundle.AppendLine('Firmware: ' + $firmwareType) | Out-Null
    $bundle.AppendLine('DiskLayout: ' + $diskLayout) | Out-Null
    $bundle.AppendLine('') | Out-Null
    
    # Selected Windows
    $bundle.AppendLine('SelectedWindows:') | Out-Null
    $bundle.AppendLine('  Drive: ' + $TargetDrive + ':') | Out-Null
    $bundle.AppendLine('  Path: ' + $TargetDrive + ':\Windows') | Out-Null
    $bundle.AppendLine('') | Out-Null
    
    # Windows Files
    $bundle.AppendLine('WindowsFiles:') | Out-Null
    $winloadPath = $TargetDrive + ':\Windows\System32\winload.efi'
    $kernelPath = $TargetDrive + ':\Windows\System32\ntoskrnl.exe'
    
    $bundle.AppendLine('  winload.efi: ' + (if (Test-Path $winloadPath) { 'present' } else { 'missing' })) | Out-Null
    $bundle.AppendLine('  ntoskrnl.exe: ' + (if (Test-Path $kernelPath) { 'present' } else { 'missing' })) | Out-Null
    $bundle.AppendLine('') | Out-Null
    
    # Final Verdict
    $bundle.AppendLine('Final:') | Out-Null
    $winloadExists = Test-Path ($TargetDrive + ':\Windows\System32\winload.efi')
    $kernelExists = Test-Path ($TargetDrive + ':\Windows\System32\ntoskrnl.exe')
    
    if ($winloadExists -and $kernelExists) {
        $bundle.AppendLine('  BootVerdict: YES') | Out-Null
        $bundle.AppendLine('  Confidence: MEDIUM') | Out-Null
        $bundle.AppendLine('  Blocker: (none)') | Out-Null
        $bundle.AppendLine('  NextStep: Reboot and test') | Out-Null
    } else {
        $bundle.AppendLine('  BootVerdict: NO') | Out-Null
        $bundle.AppendLine('  Confidence: HIGH') | Out-Null
        if (-not $winloadExists) {
            $bundle.AppendLine('  Blocker: winload.efi missing') | Out-Null
            $bundle.AppendLine('  NextStep: Extract winload.efi from installation media') | Out-Null
        } else {
            $bundle.AppendLine('  Blocker: ntoskrnl.exe missing') | Out-Null
            $bundle.AppendLine('  NextStep: Windows installation appears corrupted') | Out-Null
        }
    }
    $bundle.AppendLine('') | Out-Null
    
    $bundle.AppendLine($separator) | Out-Null
    $bundle.AppendLine('BOOTFIX PASTE-BACK BUNDLE END') | Out-Null
    $bundle.AppendLine($separator) | Out-Null
    
    return $bundle.ToString()
}
