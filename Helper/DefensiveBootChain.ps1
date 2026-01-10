# ============================================================================
# DEFENSIVE BOOT-CHAIN LOGIC
# Professional-grade automated repair engine with comprehensive verification
# ============================================================================

function Get-TargetOSDrive {
    <#
    .SYNOPSIS
    Discovers the true Windows installation drive by scanning for registry hives.
    Does not assume C: - handles drive letter shifts in PE environments.
    
    .DESCRIPTION
    Iterates through all available volumes to find the actual Windows directory
    by looking for \Windows\System32\config\SYSTEM registry hive.
    
    .OUTPUTS
    PSCustomObject with properties:
    - DriveLetter: The drive letter (e.g., "C")
    - WindowsPath: Full path to Windows directory
    - SystemHivePath: Path to SYSTEM registry hive
    - IsCurrentOS: Boolean indicating if this is the currently running OS
    - Confidence: Confidence level (High/Medium/Low)
    #>
    
    $result = @{
        DriveLetter = $null
        WindowsPath = $null
        SystemHivePath = $null
        IsCurrentOS = $false
        Confidence = "Low"
        AllFound = @()
    }
    
    try {
        # Get all available volumes
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
        
        foreach ($volume in $volumes) {
            $driveLetter = $volume.DriveLetter
            $systemHive = "$driveLetter`:\Windows\System32\config\SYSTEM"
            
            # Check for SYSTEM registry hive (definitive Windows indicator)
            if (Test-Path $systemHive) {
                $windowsPath = "$driveLetter`:\Windows"
                $kernelPath = "$driveLetter`:\Windows\System32\ntoskrnl.exe"
                
                # Additional verification: check for kernel
                $hasKernel = Test-Path $kernelPath
                
                $confidence = if ($hasKernel) { "High" } else { "Medium" }
                
                $osInfo = [PSCustomObject]@{
                    DriveLetter = $driveLetter
                    WindowsPath = $windowsPath
                    SystemHivePath = $systemHive
                    HasKernel = $hasKernel
                    Confidence = $confidence
                    IsCurrentOS = ($env:SystemDrive -eq "$driveLetter`:")
                }
                
                $result.AllFound += $osInfo
                
                # Prefer current OS if available
                if ($osInfo.IsCurrentOS) {
                    $result.DriveLetter = $driveLetter
                    $result.WindowsPath = $windowsPath
                    $result.SystemHivePath = $systemHive
                    $result.IsCurrentOS = $true
                    $result.Confidence = $confidence
                } elseif (-not $result.DriveLetter) {
                    # Use first found if current OS not found
                    $result.DriveLetter = $driveLetter
                    $result.WindowsPath = $windowsPath
                    $result.SystemHivePath = $systemHive
                    $result.Confidence = $confidence
                }
            }
        }
        
        if (-not $result.DriveLetter) {
            throw "No Windows installation found. Scanned all available volumes for \Windows\System32\config\SYSTEM"
        }
        
    } catch {
        throw "Error discovering target OS drive: $_"
    }
    
    return $result
}

function Test-BitLockerGatekeeper {
    <#
    .SYNOPSIS
    BitLocker "Gatekeeper" - Checks encryption status before repairs.
    Prevents repair attempts on locked drives that will fail.
    
    .DESCRIPTION
    Checks if the target drive is BitLocker encrypted and locked.
    If locked, repairs will fail because bcdboot cannot read/write.
    
    .PARAMETER TargetDrive
    Drive letter to check (e.g., "C")
    
    .OUTPUTS
    PSCustomObject with properties:
    - IsEncrypted: Boolean
    - IsLocked: Boolean
    - CanProceed: Boolean (true if not locked)
    - Status: Status message
    - RequiresUnlock: Boolean
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetDrive
    )
    
    $result = @{
        IsEncrypted = $false
        IsLocked = $false
        CanProceed = $true
        Status = "Not Encrypted"
        RequiresUnlock = $false
        ProtectionStatus = "Unknown"
    }
    
    try {
        $targetDrive = $TargetDrive.TrimEnd(':').ToUpper()
        $drivePath = "${targetDrive}:"
        
        # Check if manage-bde is available
        $bitlockerCmd = Get-Command "manage-bde" -ErrorAction SilentlyContinue
        if (-not $bitlockerCmd) {
            # In WinPE, BitLocker tools may not be available
            # Assume drive may be encrypted and proceed with caution
            $result.Status = "BitLocker status unknown (tools not available)"
            $result.CanProceed = $true  # Don't block, but warn
            return $result
        }
        
        # Get BitLocker status with timeout
        $job = Start-Job -ScriptBlock {
            param($drivePath)
            manage-bde -status $drivePath 2>&1
        } -ArgumentList $drivePath
        
        $bdeStatus = $null
        $jobCompleted = Wait-Job -Job $job -Timeout 5
        
        if ($jobCompleted) {
            $bdeStatus = Receive-Job -Job $job
            Remove-Job -Job $job -Force
        } else {
            Stop-Job -Job $job -Force
            Remove-Job -Job $job -Force
            $result.Status = "BitLocker status check timed out"
            $result.CanProceed = $true  # Don't block on timeout
            return $result
        }
        
        # Parse status
        if ($bdeStatus -match "Conversion Status:\s*(\w+)") {
            $conversionStatus = $matches[1]
            if ($conversionStatus -ne "FullyDecrypted") {
                $result.IsEncrypted = $true
                $result.ProtectionStatus = $conversionStatus
            }
        }
        
        if ($bdeStatus -match "Lock Status:\s*(\w+)") {
            $lockStatus = $matches[1]
            if ($lockStatus -eq "Locked") {
                $result.IsLocked = $true
                $result.CanProceed = $false
                $result.RequiresUnlock = $true
                $result.Status = "BitLocker LOCKED - Drive requires unlock before repairs"
            } elseif ($result.IsEncrypted) {
                $result.Status = "BitLocker Encrypted (Unlocked) - Proceed with caution"
                $result.CanProceed = $true
            }
        }
        
        if (-not $result.IsEncrypted) {
            $result.Status = "Not Encrypted - Safe to proceed"
        }
        
    } catch {
        $result.Status = "BitLocker check failed: $_"
        $result.CanProceed = $true  # Don't block on error
    }
    
    return $result
}

function Get-EFIPartitionHealth {
    <#
    .SYNOPSIS
    Locates and checks the health of the EFI System Partition (ESP).
    
    .DESCRIPTION
    Finds the hidden EFI System Partition (usually small FAT32 partition ~100MB-500MB).
    Checks if it's healthy, has filesystem, and is accessible.
    
    .PARAMETER TargetOSDrive
    Drive letter of the Windows installation
    
    .OUTPUTS
    PSCustomObject with properties:
    - Found: Boolean
    - DriveLetter: Assigned drive letter (or null)
    - HealthStatus: Healthy/Unhealthy/RAW/NoFilesystem
    - FileSystem: FAT32/NTFS/RAW
    - Size: Size in bytes
    - NeedsFormat: Boolean
    - EFIPath: Path to EFI partition root
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetOSDrive
    )
    
    $result = @{
        Found = $false
        DriveLetter = $null
        HealthStatus = "Unknown"
        FileSystem = "Unknown"
        Size = 0
        NeedsFormat = $false
        EFIPath = $null
        Message = ""
    }
    
    try {
        $targetDrive = $TargetOSDrive.TrimEnd(':').ToUpper()
        
        # Get partition info for Windows drive
        $partition = Get-Partition -DriveLetter $targetDrive -ErrorAction SilentlyContinue
        if (-not $partition) {
            $result.Message = "Windows drive $targetDrive`: not found"
            return $result
        }
        
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction SilentlyContinue
        if (-not $disk) {
            $result.Message = "Could not get disk information"
            return $result
        }
        
        # Find EFI partition on the same disk
        $efiPartitions = Get-Partition -DiskNumber $disk.Number | Where-Object { 
            $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' 
        }
        
        if (-not $efiPartitions -or $efiPartitions.Count -eq 0) {
            $result.Message = "No EFI System Partition found on disk $($disk.Number). This may be a legacy BIOS system."
            return $result
        }
        
        $efiPartition = $efiPartitions[0]
        $result.Found = $true
        $result.Size = $efiPartition.Size
        
        # Check if EFI partition has a drive letter
        if ($efiPartition.DriveLetter) {
            $efiLetter = $efiPartition.DriveLetter
            $result.DriveLetter = $efiLetter
            $result.EFIPath = "$efiLetter`:"
        } else {
            # Try to assign a drive letter
            $preferredLetters = @("S", "T", "U", "V", "W", "Y", "Z")
            foreach ($letter in $preferredLetters) {
                $existingDrive = Get-PSDrive -Name $letter -ErrorAction SilentlyContinue
                if (-not $existingDrive) {
                    try {
                        $efiPartition | Set-Partition -NewDriveLetter $letter -ErrorAction Stop
                        Start-Sleep -Milliseconds 500
                        $result.DriveLetter = $letter
                        $result.EFIPath = "$letter`:"
                        break
                    } catch {
                        continue
                    }
                }
            }
        }
        
        if ($result.DriveLetter) {
            # Check filesystem health
            $efiVolume = Get-Volume -DriveLetter $result.DriveLetter -ErrorAction SilentlyContinue
            if ($efiVolume) {
                $result.FileSystem = $efiVolume.FileSystemType
                $result.HealthStatus = $efiVolume.HealthStatus
                
                # Check if filesystem is RAW or missing
                if ($result.FileSystem -eq "RAW" -or [string]::IsNullOrWhiteSpace($result.FileSystem)) {
                    $result.NeedsFormat = $true
                    $result.Message = "EFI partition has no filesystem (RAW) - needs format"
                } elseif ($result.HealthStatus -ne "Healthy") {
                    $result.NeedsFormat = $true
                    $result.Message = "EFI partition health is not optimal - may need format"
                } else {
                    # Verify EFI structure exists
                    $efiBootPath = "$($result.DriveLetter):\EFI\Microsoft\Boot"
                    if (-not (Test-Path $efiBootPath)) {
                        $result.Message = "EFI partition mounted but boot structure missing"
                    } else {
                        $result.Message = "EFI partition is healthy"
                    }
                }
            } else {
                $result.Message = "Could not get volume information for EFI partition"
            }
        } else {
            $result.Message = "Could not assign drive letter to EFI partition"
        }
        
    } catch {
        $result.Message = "Error checking EFI partition: $_"
    }
    
    return $result
}

function Invoke-DefensiveBootRepair {
    <#
    .SYNOPSIS
    Defensive Boot-Chain Logic - Professional-grade automated repair with verification.
    
    .DESCRIPTION
    Implements the complete defensive boot-chain repair sequence:
    1. Discovery: Find true Windows drive (not assume C:)
    2. Security: Check BitLocker status (gatekeeper)
    3. ESP Prep: Mount and verify EFI partition health
    4. The Fix: Execute bcdboot with verification
    5. Post-Check: Verify winload.efi and BCD mapping
    6. Reporting: Provide actionable failure notifications
    
    .PARAMETER PreferredDrive
    Preferred drive letter (optional, will auto-detect if not provided)
    
    .OUTPUTS
    PSCustomObject with detailed repair results and verification status
    #>
    
    param(
        [string]$PreferredDrive = $null
    )
    
    $result = @{
        Success = $false
        Steps = @()
        Errors = @()
        Warnings = @()
        TargetOSDrive = $null
        EFIDrive = $null
        Verification = @{
            WinloadExists = $false
            BCDValid = $false
            BCDPathCorrect = $false
        }
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("DEFENSIVE BOOT-CHAIN REPAIR") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    try {
        # STEP 1: Discovery - Find True Windows Drive
        $report.AppendLine("STEP 1: DISCOVERY - Finding True Windows Drive") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        if ($PreferredDrive) {
            $targetOS = Get-TargetOSDrive
            # Verify preferred drive is valid
            $preferredValid = $targetOS.AllFound | Where-Object { $_.DriveLetter -eq $PreferredDrive.TrimEnd(':').ToUpper() }
            if ($preferredValid) {
                $targetOS.DriveLetter = $PreferredDrive.TrimEnd(':').ToUpper()
                $targetOS.WindowsPath = "$($targetOS.DriveLetter):\Windows"
                $targetOS.SystemHivePath = "$($targetOS.DriveLetter):\Windows\System32\config\SYSTEM"
            }
        } else {
            $targetOS = Get-TargetOSDrive
        }
        
        $result.TargetOSDrive = $targetOS.DriveLetter
        $result.Steps += "Discovery: Found Windows on $($targetOS.DriveLetter):"
        
        $report.AppendLine("[OK] Windows installation found on drive $($targetOS.DriveLetter):") | Out-Null
        $report.AppendLine("  Windows Path: $($targetOS.WindowsPath)") | Out-Null
        $report.AppendLine("  System Hive: $($targetOS.SystemHivePath)") | Out-Null
        $report.AppendLine("  Confidence: $($targetOS.Confidence)") | Out-Null
        $report.AppendLine("  Is Current OS: $($targetOS.IsCurrentOS)") | Out-Null
        $report.AppendLine("") | Out-Null
        
        # STEP 2: Security - BitLocker Gatekeeper
        $report.AppendLine("STEP 2: SECURITY - BitLocker Gatekeeper Check") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        $bitlockerCheck = Test-BitLockerGatekeeper -TargetDrive $targetOS.DriveLetter
        $result.Steps += "Security: BitLocker status = $($bitlockerCheck.Status)"
        
        $report.AppendLine("Status: $($bitlockerCheck.Status)") | Out-Null
        
        if ($bitlockerCheck.RequiresUnlock) {
            $errorMsg = "CRITICAL: Drive $($targetOS.DriveLetter): is BitLocker LOCKED.`n" +
                       "Repairs cannot proceed until drive is unlocked.`n" +
                       "Run: manage-bde -unlock $($targetOS.DriveLetter): -RecoveryPassword <YOUR_KEY>"
            $result.Errors += $errorMsg
            $report.AppendLine("[BLOCKED] $errorMsg") | Out-Null
            $report.AppendLine("") | Out-Null
            $result.Report = $report.ToString()
            return $result
        }
        
        if ($bitlockerCheck.IsEncrypted -and -not $bitlockerCheck.IsLocked) {
            $warningMsg = "WARNING: Drive is BitLocker encrypted (unlocked).`n" +
                         "Modifying boot files may trigger recovery key prompt on next boot."
            $result.Warnings += $warningMsg
            $report.AppendLine("[WARNING] $warningMsg") | Out-Null
        }
        
        $report.AppendLine("[OK] Security check passed - can proceed with repairs") | Out-Null
        $report.AppendLine("") | Out-Null
        
        # STEP 3: ESP Prep - Mount and Verify EFI Partition
        $report.AppendLine("STEP 3: ESP PREP - Mounting and Verifying EFI Partition") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        $efiHealth = Get-EFIPartitionHealth -TargetOSDrive $targetOS.DriveLetter
        
        if (-not $efiHealth.Found) {
            $errorMsg = "CRITICAL: EFI System Partition not found. This may be a legacy BIOS system."
            $result.Errors += $errorMsg
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $report.AppendLine("") | Out-Null
            $result.Report = $report.ToString()
            return $result
        }
        
        $report.AppendLine("EFI Partition Status:") | Out-Null
        $report.AppendLine("  Found: $($efiHealth.Found)") | Out-Null
        $report.AppendLine("  Drive Letter: $($efiHealth.DriveLetter)") | Out-Null
        $report.AppendLine("  File System: $($efiHealth.FileSystem)") | Out-Null
        $report.AppendLine("  Health Status: $($efiHealth.HealthStatus)") | Out-Null
        $report.AppendLine("  Size: $([math]::Round($efiHealth.Size / 1MB, 2)) MB") | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($efiHealth.NeedsFormat) {
            $report.AppendLine("[WARNING] EFI partition needs format: $($efiHealth.Message)") | Out-Null
            $report.AppendLine("Formatting EFI partition as FAT32...") | Out-Null
            
            try {
                $formatOutput = & format "$($efiHealth.DriveLetter):" /fs:FAT32 /q /y 2>&1 | Out-String
                $report.AppendLine("Format Output: $formatOutput") | Out-Null
                $result.Steps += "ESP Prep: Formatted EFI partition"
            } catch {
                $errorMsg = "Failed to format EFI partition: $_"
                $result.Errors += $errorMsg
                $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            }
        }
        
        if (-not $efiHealth.DriveLetter) {
            $errorMsg = "CRITICAL: Could not assign drive letter to EFI partition"
            $result.Errors += $errorMsg
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $report.AppendLine("") | Out-Null
            $result.Report = $report.ToString()
            return $result
        }
        
        $result.EFIDrive = $efiHealth.DriveLetter
        $result.Steps += "ESP Prep: EFI partition mounted as $($efiHealth.DriveLetter):"
        $report.AppendLine("[OK] EFI partition ready: $($efiHealth.DriveLetter):") | Out-Null
        $report.AppendLine("") | Out-Null
        
        # STEP 4: The Fix - Execute bcdboot with Verification
        $report.AppendLine("STEP 4: THE FIX - Executing bcdboot") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        $bcdbootCmd = "bcdboot $($targetOS.WindowsPath) /s $($efiHealth.DriveLetter): /f UEFI"
        $report.AppendLine("Command: $bcdbootCmd") | Out-Null
        
        try {
            $bcdbootOutput = & bcdboot $targetOS.WindowsPath /s "$($efiHealth.DriveLetter):" /f UEFI 2>&1 | Out-String
            $report.AppendLine("Output: $bcdbootOutput") | Out-Null
            
            if ($LASTEXITCODE -eq 0 -or $bcdbootOutput -match "Boot files successfully created") {
                $result.Steps += "Fix: bcdboot executed successfully"
                $report.AppendLine("[SUCCESS] bcdboot completed successfully") | Out-Null
            } else {
                $errorMsg = "bcdboot reported issues. Check output above."
                $result.Errors += $errorMsg
                $report.AppendLine("[WARNING] $errorMsg") | Out-Null
            }
        } catch {
            $errorMsg = "bcdboot failed: $_"
            $result.Errors += $errorMsg
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        }
        
        $report.AppendLine("") | Out-Null
        
        # STEP 5: Post-Check - Verify winload.efi and BCD
        $report.AppendLine("STEP 5: POST-CHECK - Verification") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        # 5A: Verify winload.efi exists
        $winloadPath = "$($targetOS.WindowsPath)\System32\winload.efi"
        $winloadExists = Test-Path $winloadPath
        
        $result.Verification.WinloadExists = $winloadExists
        $result.Steps += "Verification: winload.efi exists = $winloadExists"
        
        if ($winloadExists) {
            $fileSize = (Get-Item $winloadPath -ErrorAction SilentlyContinue).Length
            $report.AppendLine("[OK] winload.efi found in Windows directory") | Out-Null
            $report.AppendLine("  Path: $winloadPath") | Out-Null
            $report.AppendLine("  Size: $fileSize bytes") | Out-Null
        } else {
            $errorMsg = "CRITICAL: winload.efi missing from Windows directory: $winloadPath`n" +
                       "Source files are missing from your Windows installation.`n" +
                       "Please attach a Windows ISO for manual file injection."
            $result.Errors += $errorMsg
            $report.AppendLine("[FAILED] $errorMsg") | Out-Null
        }
        
        $report.AppendLine("") | Out-Null
        
        # 5B: Verify BCD and check path
        $bcdPath = "$($efiHealth.DriveLetter):\EFI\Microsoft\Boot\BCD"
        if (Test-Path $bcdPath) {
            try {
                $bcdEnum = & bcdedit /store $bcdPath /enum {default} 2>&1 | Out-String
                
                if ($bcdEnum -match "path\s+(.+)") {
                    $bcdPathValue = $matches[1].Trim()
                    $result.Verification.BCDValid = $true
                    
                    if ($bcdPathValue -match "winload\.efi") {
                        $result.Verification.BCDPathCorrect = $true
                        $result.Steps += "Verification: BCD path correct = \Windows\system32\winload.efi"
                        $report.AppendLine("[OK] BCD path is correct: $bcdPathValue") | Out-Null
                    } elseif ($bcdPathValue -match "winload\.exe") {
                        $warningMsg = "BCD Path Mismatch detected: points to winload.exe instead of winload.efi`n" +
                                     "Attempting manual path correction..."
                        $result.Warnings += $warningMsg
                        $report.AppendLine("[WARNING] $warningMsg") | Out-Null
                        
                        # Fix BCD path
                        try {
                            $bcdEditOutput = & bcdedit /store $bcdPath /set {default} path \Windows\system32\winload.efi 2>&1 | Out-String
                            $report.AppendLine("bcdedit Output: $bcdEditOutput") | Out-Null
                            $result.Steps += "Verification: BCD path corrected to winload.efi"
                            $report.AppendLine("[OK] BCD path corrected") | Out-Null
                        } catch {
                            $errorMsg = "Failed to correct BCD path: $_"
                            $result.Errors += $errorMsg
                            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
                        }
                    } else {
                        $report.AppendLine("[INFO] BCD path: $bcdPathValue") | Out-Null
                    }
                    
                    # Check for "Unknown" device/osdevice (Disk Signature mismatch)
                    if ($bcdEnum -match "device\s+Unknown" -or $bcdEnum -match "osdevice\s+Unknown") {
                        $warningMsg = "WARNING: BCD shows 'Unknown' device/osdevice.`n" +
                                     "This indicates a Disk Signature mismatch.`n" +
                                     "The partition may have been moved or cloned."
                        $result.Warnings += $warningMsg
                        $report.AppendLine("[WARNING] $warningMsg") | Out-Null
                    }
                } else {
                    $report.AppendLine("[WARNING] Could not parse BCD path from bcdedit output") | Out-Null
                }
            } catch {
                $errorMsg = "Failed to verify BCD: $_"
                $result.Errors += $errorMsg
                $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            }
        } else {
            $errorMsg = "BCD file not found at: $bcdPath"
            $result.Errors += $errorMsg
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        }
        
        $report.AppendLine("") | Out-Null
        
        # STEP 6: Final Status
        $report.AppendLine("STEP 6: FINAL STATUS") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        if ($result.Errors.Count -eq 0 -and $result.Verification.WinloadExists -and $result.Verification.BCDValid) {
            $result.Success = $true
            $report.AppendLine("[SUCCESS] Defensive Boot-Chain Repair completed successfully") | Out-Null
            $report.AppendLine("  - Target OS Drive: $($result.TargetOSDrive):") | Out-Null
            $report.AppendLine("  - EFI Drive: $($result.EFIDrive):") | Out-Null
            $report.AppendLine("  - winload.efi: Verified") | Out-Null
            $report.AppendLine("  - BCD: Valid") | Out-Null
        } else {
            $result.Success = $false
            $report.AppendLine("[FAILED] Defensive Boot-Chain Repair completed with errors") | Out-Null
            $report.AppendLine("  Errors: $($result.Errors.Count)") | Out-Null
            $report.AppendLine("  Warnings: $($result.Warnings.Count)") | Out-Null
        }
        
        $report.AppendLine("") | Out-Null
        $report.AppendLine($separator) | Out-Null
        
    } catch {
        $errorMsg = "Defensive Boot-Chain Repair failed: $_"
        $result.Errors += $errorMsg
        $report.AppendLine("[CRITICAL ERROR] $errorMsg") | Out-Null
        $report.AppendLine($separator) | Out-Null
    }
    
    $result.Report = $report.ToString()
    return $result
}
