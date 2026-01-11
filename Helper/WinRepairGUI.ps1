<#
    MIRACLE BOOT – WPF GRAPHICAL USER INTERFACE (GUI)
    ==================================================

    This module defines the **WPF desktop UI** for Miracle Boot. It is only
    available when running in a full Windows desktop with WPF/.NET available.
    All heavy lifting is delegated to the core engine in `Helper\WinRepairCore.ps1`.

    TABLE OF CONTENTS (HIGH‑LEVEL)
    ------------------------------
   1. WPF Window Definition (XAML)
       - Toolbar: utilities, network, ChatGPT help, environment indicators
       - Tabs:
           - Volumes & Health
           - BCD Editor
           - Boot Repair & Diagnostics
           - System File / Disk Repair
           - Drivers & Porting
           - In-Place Upgrade / Readiness
           - Logs & Install Failure Analysis
    2. Code‑Behind Wiring (`Start-GUI`)
       - XAML loading and window creation
       - Control lookups (`FindName`) and event wiring
       - Status bar and progress updates
    3. Command Handlers (By Area)
       - Volume refresh, BCD actions, boot repair commands
       - SFC/DISM/CHKDSK repair flows with progress callbacks
       - Driver export/porting/injection
       - Install failure analysis and log viewers
       - Repair-Install Readiness UX
       - Network enablement, diagnostics, and ChatGPT help
       - System restore point creation/listing
       - Keyboard symbol helper integration

    ENVIRONMENT MAPPING – WHEN THIS GUI RUNS
    ----------------------------------------
    - **FullOS (Windows 10/11 desktop) ONLY**
        - Launched by `MiracleBoot.ps1` when:
            - `Get-EnvironmentType` returns `FullOS`, and
            - WPF assemblies (`PresentationFramework`) load successfully.
        - Assumes:
            - A logged‑in interactive user session.
            - Sufficient .NET / WPF support.

    - **NOT USED in WinRE / WinPE / Shift+F10**
        - In those environments, `MiracleBoot.ps1` falls back to `Start-TUI`.

    FLOW MAPPING – HOW USER ACTIONS REACH THE ENGINE
    ------------------------------------------------
    1. `MiracleBoot.ps1` detects `FullOS` and dot‑sources:
         - `Helper\WinRepairCore.ps1`  → core engine
         - `Helper\WinRepairGUI.ps1`   → this file

    2. `Start-GUI` is invoked:
         - Loads XAML into a `Window`.
         - Looks up key UI elements (buttons, text boxes, list views).
         - Attaches event handlers for each button/menu item.

    3. Event handlers call into **engine functions** in `WinRepairCore.ps1`, e.g.:
         - `Get-WindowsVolumes`, `Get-BCDEntries*`
         - `Start-SystemFileRepair`, `Start-DiskRepair`, `Start-CompleteSystemRepair`
         - `Start-RepairInstallReadiness`
         - `Get-BootChainAnalysis`, `Get-BootLogAnalysis`
         - `Generate-SaveMeTxt`, driver export/porting helpers
         - `Create-SystemRestorePoint`, `Get-SystemRestorePoints`
         - Network diagnostics and ChatGPT helpers

    4. Real‑time progress is surfaced by:
         - Passing `ProgressCallback` scriptblocks into engine functions.
         - Updating:
             - Status bar text
             - Progress bar controls
             - Rich text / log output panes

    QUICK ORIENTATION
    -----------------
    - **New to the project?**  
        → Skim this file to see which **buttons and tabs** exist and then jump
          into `WinRepairCore.ps1` to see what work each action performs.

    - **Adding a new GUI feature?**  
        1. Extend the XAML (new button/tab/section).
        2. Wire up an event handler in `Start-GUI`.
        3. Call into an existing or new core function in `WinRepairCore.ps1`.

    - **Need environment‑specific behavior?**  
        → Use the environment status labels (`EnvStatus`, `NetworkStatus`) and
          gate actions if certain capabilities are missing (e.g. network, browser).
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# ==============================================================================
# HELPER FUNCTIONS FOR BOOT REPAIR
# ==============================================================================

# Test Mode Function: Simulate boot failures safely by renaming (not deleting) critical files
function Invoke-TestModeBootFailure {
    param(
        [string]$Drive = "C",
        [string]$EfiDrive = $null,
        [scriptblock]$WriteLogFunction = { param($msg) Write-Host $msg }
    )
    
    try {
        & $WriteLogFunction "==============================================================="
        & $WriteLogFunction "TEST MODE: Simulating Boot Failure"
        & $WriteLogFunction "==============================================================="
        & $WriteLogFunction "This will rename (not delete) critical boot files for testing."
        & $WriteLogFunction ""
        
        $errors = @()
        
        # 1. Break winload.efi in System32
        $winloadPath = "$Drive`:\Windows\System32\winload.efi"
        if (Test-Path $winloadPath) {
            & $WriteLogFunction "[TEST] Breaking winload.efi in System32..."
            $ownershipResult = Set-FileOwnershipAndPermissions -FilePath $winloadPath -WriteLogFunction $WriteLogFunction
            if ($ownershipResult.Success) {
                try {
                    Rename-Item -Path $winloadPath -NewName "winload.efi.testing" -Force -ErrorAction Stop
                    & $WriteLogFunction "[OK] winload.efi renamed to winload.efi.testing"
                } catch {
                    $errors += "Failed to rename winload.efi: $_"
                    & $WriteLogFunction "[ERROR] $($errors[-1])"
                }
            } else {
                $errors += "Could not take ownership of winload.efi: $($ownershipResult.Message)"
                & $WriteLogFunction "[ERROR] $($errors[-1])"
            }
        } else {
            & $WriteLogFunction "[INFO] winload.efi not found at $winloadPath (may already be broken)"
        }
        
        # 2. Break BCD in EFI partition
        if ($EfiDrive) {
            $bcdPath = "$EfiDrive`:\EFI\Microsoft\Boot\BCD"
            if (Test-Path $bcdPath) {
                & $WriteLogFunction "[TEST] Breaking BCD in EFI partition..."
                try {
                    Rename-Item -Path $bcdPath -NewName "BCD.testing" -Force -ErrorAction Stop
                    & $WriteLogFunction "[OK] BCD renamed to BCD.testing"
                } catch {
                    $errors += "Failed to rename BCD: $_"
                    & $WriteLogFunction "[ERROR] $($errors[-1])"
                }
            } else {
                & $WriteLogFunction "[INFO] BCD not found at $bcdPath (may already be broken)"
            }
        } else {
            & $WriteLogFunction "[WARNING] EFI partition not mounted - cannot break EFI BCD"
        }
        
        # 3. Delete current boot entry (if accessible)
        try {
            & $WriteLogFunction "[TEST] Attempting to delete current boot entry..."
            $deleteOutput = & bcdedit /delete "{current}" 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                & $WriteLogFunction "[OK] Current boot entry deleted"
            } else {
                & $WriteLogFunction "[INFO] Could not delete boot entry (may not be accessible): $deleteOutput"
            }
        } catch {
            & $WriteLogFunction "[INFO] Boot entry deletion skipped: $_"
        }
        
        & $WriteLogFunction ""
        if ($errors.Count -eq 0) {
            & $WriteLogFunction "[SUCCESS] Test mode boot failure simulation completed"
            & $WriteLogFunction "You can now test the repair logic. Files are renamed (not deleted) for safety."
            return @{ Success = $true; Message = "Boot failure simulated successfully" }
        } else {
            & $WriteLogFunction "[PARTIAL] Test mode completed with $($errors.Count) error(s)"
            return @{ Success = $false; Message = "Some operations failed: $($errors -join '; ')" }
        }
    } catch {
        & $WriteLogFunction "[ERROR] Test mode failed: $_"
        return @{ Success = $false; Message = "Exception: $_" }
    }
}

# Helper function to take ownership and grant permissions for TrustedInstaller-protected files
function Set-FileOwnershipAndPermissions {
    param(
        [string]$FilePath,
        [scriptblock]$WriteLogFunction = { param($msg) Write-Host $msg }
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            & $WriteLogFunction "[WARNING] File does not exist: $FilePath"
            return @{ Success = $false; Message = "File not found" }
        }
        
        & $WriteLogFunction "[INFO] Taking ownership of $FilePath from TrustedInstaller..."
        
        # Take ownership for Administrators group
        $takeownOutput = & takeown /f $FilePath /a 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            if ($takeownOutput -match "access is denied|Access is denied|elevated|administrator") {
                & $WriteLogFunction "[ERROR] Access Denied: This operation requires Administrator privileges."
                & $WriteLogFunction "[ERROR] Please ensure PowerShell is running 'As Administrator' or UAC is properly elevated."
                return @{ Success = $false; Message = "Access Denied - Administrator privileges required" }
            } else {
                & $WriteLogFunction "[WARNING] takeown failed: $takeownOutput"
                return @{ Success = $false; Message = "takeown failed: $takeownOutput" }
            }
        }
        
        & $WriteLogFunction "[INFO] Granting Full Control to Administrators group..."
        
        # Grant Full Control to Administrators
        $icaclsOutput = & icacls $FilePath /grant Administrators:F 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            & $WriteLogFunction "[WARNING] icacls failed: $icaclsOutput"
            return @{ Success = $false; Message = "icacls failed: $icaclsOutput" }
        }
        
        & $WriteLogFunction "[SUCCESS] Ownership and permissions set successfully"
        return @{ Success = $true; Message = "Ownership and permissions set" }
    } catch {
        & $WriteLogFunction "[ERROR] Failed to set ownership/permissions: $_"
        return @{ Success = $false; Message = "Exception: $_" }
    }
}

# Helper function to check if BCD exists and recreate if missing
function Test-AndRecreateBCD {
    param(
        [string]$Drive = "C",
        [string]$EfiDrive = $null,
        [scriptblock]$WriteLogFunction = { param($msg) Write-Host $msg },
        [int]$TimeoutSeconds = 10
    )
    
    try {
        # First, check if BCD file exists physically (faster than bcdedit)
        # Use timeout wrapper to prevent Test-Path from hanging on locked volumes
        $bcdFilePaths = @(
            "$env:SystemRoot\Boot\BCD",  # Legacy BIOS
            "$env:SystemDrive\Boot\BCD",  # Legacy BIOS alternative
            "$Drive`:\Boot\BCD",          # Explicit drive check (WinPE/shifted roots)
            "$env:SystemRoot\EFI\Microsoft\Boot\BCD"  # UEFI (if mounted)
        )
        
        $bcdFileExists = $false
        foreach ($bcdPath in $bcdFilePaths) {
            # Use job-based timeout for Test-Path to prevent hanging
            $testPathJob = Start-Job -ScriptBlock {
                param($path)
                Test-Path $path -ErrorAction SilentlyContinue
            } -ArgumentList $bcdPath
            
            $testResult = Wait-Job -Job $testPathJob -Timeout 2 | Receive-Job
            Stop-Job -Job $testPathJob -ErrorAction SilentlyContinue
            Remove-Job -Job $testPathJob -ErrorAction SilentlyContinue
            
            if ($testResult -eq $true) {
                $bcdFileExists = $true
                & $WriteLogFunction "[INFO] BCD file found at: $bcdPath"
                break
            }
        }
        
        # If BCD file doesn't exist physically, skip bcdedit check (it will hang) and go straight to recreation
        if (-not $bcdFileExists) {
            & $WriteLogFunction "[INFO] BCD file not found in standard locations - BCD is missing"
            & $WriteLogFunction "Skipping bcdedit check (would hang) and proceeding directly to recreation..."
            # Set bcdTest to indicate missing so recreation logic triggers
            $bcdTest = "BCD_FILE_NOT_FOUND"
        } else {
            # BCD file exists, but check if it's accessible (with timeout to prevent hanging)
            # Use shorter timeout (5 seconds) to fail fast if BCD is locked
            $quickTimeout = [Math]::Min(5, $TimeoutSeconds)
            & $WriteLogFunction "Checking BCD accessibility (with $quickTimeout second timeout - fast fail)..."
            $bcdTest = $null
            $bcdJob = Start-Job -ScriptBlock {
                bcdedit /enum "{bootmgr}" 2>&1 | Out-String
            }
            
            # Use shorter timeout to fail fast
            $bcdTest = Wait-Job -Job $bcdJob -Timeout $quickTimeout | Receive-Job
            Stop-Job -Job $bcdJob -ErrorAction SilentlyContinue
            Remove-Job -Job $bcdJob -ErrorAction SilentlyContinue
            
            if ($null -eq $bcdTest) {
                & $WriteLogFunction "[WARNING] BCD check timed out after $quickTimeout seconds - BCD may be locked or corrupted"
                # Treat timeout as missing/corrupted - don't wait longer
                $bcdTest = "TIMEOUT - BCD check exceeded $quickTimeout seconds"
            }
        }
        
        # Check for common BCD missing/corrupted errors
        # If BCD file doesn't exist OR bcdedit reports errors, attempt recreation
        if (-not $bcdFileExists -or 
            ($bcdTest -and ($bcdTest -match "BCD_FILE_NOT_FOUND" -or
            $bcdTest -match "The boot configuration data store could not be opened" -or
            $bcdTest -match "The system cannot find the file specified" -or
            $bcdTest -match "The system cannot find the path specified" -or
            $bcdTest -match "TIMEOUT" -or
            $LASTEXITCODE -ne 0))) {
            
            & $WriteLogFunction "[WARNING] BCD file is missing or corrupted"
            & $WriteLogFunction "Attempting to recreate BCD using bcdboot..."
            
            # Determine EFI drive if not provided
            if (-not $EfiDrive) {
                # Try to find EFI partition
                try {
                    $efiMount = Mount-EFIPartition -WindowsDrive $Drive -PreferredLetter "S"
                    if ($efiMount.Success) {
                        $EfiDrive = $efiMount.DriveLetter
                        & $WriteLogFunction "[OK] EFI partition mounted as $EfiDrive`:"
                    } else {
                        # Try mountvol as fallback
                        $mountvolOutput = mountvol /S 2>&1 | Out-String
                        if ($mountvolOutput -match "\\\\\?\\Volume\{[a-f0-9\-]+\}") {
                            # Find which drive letter was assigned
                            $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemType -eq "FAT32" }
                            if ($volumes) {
                                $EfiDrive = $volumes[0].DriveLetter
                                & $WriteLogFunction "[OK] EFI partition found at $EfiDrive`:"
                            }
                        }
                    }
                } catch {
                    & $WriteLogFunction "[WARNING] Could not auto-mount EFI partition: $_"
                }
            }
            
            if ($EfiDrive) {
                # Recreate BCD using bcdboot (UEFI path)
                & $WriteLogFunction "Running: bcdboot $Drive`:\Windows /s $EfiDrive`: /f UEFI"
                $bcdbootOutput = & bcdboot "$Drive`:\Windows" /s "$EfiDrive`:" /f UEFI 2>&1 | Out-String
                & $WriteLogFunction "bcdboot Output: $bcdbootOutput"
                
                if ($LASTEXITCODE -eq 0 -or $bcdbootOutput -match "Boot files successfully created") {
                    & $WriteLogFunction "[SUCCESS] BCD recreated successfully"
                    Start-Sleep -Seconds 2  # Give system time to flush
                    
                    # Verify BCD is now accessible (with timeout to prevent hanging)
                    & $WriteLogFunction "Verifying BCD accessibility (with 10 second timeout)..."
                    $verifyBcd = $null
                    $verifyJob = Start-Job -ScriptBlock {
                        bcdedit /enum "{bootmgr}" 2>&1 | Out-String
                    }
                    
                    $verifyBcd = Wait-Job -Job $verifyJob -Timeout 10 | Receive-Job
                    Stop-Job -Job $verifyJob -ErrorAction SilentlyContinue
                    Remove-Job -Job $verifyJob -ErrorAction SilentlyContinue
                    
                    if ($null -eq $verifyBcd) {
                        & $WriteLogFunction "[WARNING] BCD verification timed out - may still be initializing"
                        return @{ Success = $true; Message = "BCD recreated (verification timeout - may be initializing)" }
                    } elseif ($verifyBcd -notmatch "could not be opened" -and $LASTEXITCODE -eq 0) {
                        & $WriteLogFunction "[OK] BCD verification successful"
                        return @{ Success = $true; Message = "BCD recreated successfully" }
                    } else {
                        & $WriteLogFunction "[WARNING] BCD recreated but verification failed"
                        return @{ Success = $false; Message = "BCD recreated but not accessible" }
                    }
                } else {
                    & $WriteLogFunction "[ERROR] bcdboot failed to recreate BCD"
                    return @{ Success = $false; Message = "bcdboot failed: $bcdbootOutput" }
                }
            } else {
                & $WriteLogFunction "[WARNING] EFI partition not accessible. Attempting legacy BIOS BCD creation on $Drive`:\\Boot..."
                try {
                    $legacyPath = "$Drive`:\Boot"
                    if (-not (Test-Path $legacyPath)) {
                        New-Item -ItemType Directory -Path $legacyPath -Force | Out-Null
                    }
                    & $WriteLogFunction "Running: bcdboot $Drive`:\Windows /s $Drive`: /f BIOS"
                    $biosBcdOutput = & bcdboot "$Drive`:\Windows" /s "$Drive`:" /f BIOS 2>&1 | Out-String
                    & $WriteLogFunction "bcdboot (BIOS) Output: $biosBcdOutput"
                    
                    if ($LASTEXITCODE -eq 0 -or $biosBcdOutput -match "Boot files successfully created") {
                        & $WriteLogFunction "[SUCCESS] Legacy BCD created at $legacyPath"
                        return @{ Success = $true; Message = "BCD recreated in legacy mode (BIOS fallback)" }
                    } else {
                        & $WriteLogFunction "[ERROR] Legacy BCD creation failed"
                        return @{ Success = $false; Message = "Legacy bcdboot failed: $biosBcdOutput" }
                    }
                } catch {
                    & $WriteLogFunction "[ERROR] Cannot recreate BCD: EFI partition not accessible and legacy fallback failed: $_"
                    return @{ Success = $false; Message = "EFI partition not accessible; legacy fallback failed" }
                }
            }
        } else {
            # BCD is accessible
            return @{ Success = $true; Message = "BCD is accessible" }
        }
    } catch {
        & $WriteLogFunction "[ERROR] BCD check/recreate failed: $_"
        return @{ Success = $false; Message = "BCD check failed: $_" }
    }
}

# Helper function for bcdboot repair with fallback logic
function Invoke-BcdbootRepairWithFallback {
    param(
        [string]$Drive,
        [string]$EfiDrive,
        $VmdIssue,
        [scriptblock]$WriteLogFunction
    )
    
    try {
        $bcdbootCmd = "bcdboot $Drive`:\Windows /s $EfiDrive`: /f UEFI /v"
        & $WriteLogFunction "Step 3c: Running: $bcdbootCmd"
        $bcdbootOutput = & bcdboot "$Drive`:\Windows" /s "$EfiDrive`:" /f UEFI /v 2>&1 | Out-String
        & $WriteLogFunction "bcdboot Output: $bcdbootOutput"
        
        # Check for false positive - bcdboot may report success but not actually copy files
        $bcdbootSuccess = ($LASTEXITCODE -eq 0 -or $bcdbootOutput -match "Boot files successfully created")
        
        # Verify winload.efi was ACTUALLY copied (not just BCD updated)
        $winloadEfiPath = "$EfiDrive`:\EFI\Microsoft\Boot\winload.efi"
        $winloadActuallyCopied = Test-Path $winloadEfiPath
        
        if ($bcdbootSuccess -and $winloadActuallyCopied) {
            & $WriteLogFunction "[SUCCESS] Boot files repaired successfully using bcdboot"
            & $WriteLogFunction "[SUCCESS] Verified: winload.efi is now present in EFI partition"
            
            # Step 3d: Fix BCD drive IDs explicitly (prevents "unknown" partition errors)
            & $WriteLogFunction "Step 3d: Fixing BCD drive identifiers..."
            try {
                # First, ensure BCD exists
                $bcdCheck = Test-AndRecreateBCD -Drive $Drive -EfiDrive $EfiDrive -WriteLogFunction $WriteLogFunction
                if (-not $bcdCheck.Success) {
                    & $WriteLogFunction "[WARNING] BCD may not be accessible, skipping drive ID fix"
                    return
                }
                
                # Get the default boot entry GUID
                $bcdEnum = bcdedit /enum "{default}" 2>&1 | Out-String
                if ($bcdEnum -match "could not be opened|The system cannot find") {
                    & $WriteLogFunction "[WARNING] BCD is not accessible, cannot fix drive IDs"
                    return
                }
                
                if ($bcdEnum -match '{([a-f0-9\-]{36})}') {
                    $defaultGuid = $matches[1]
                    
                    # Set device and osdevice explicitly to C: partition
                    $deviceCmd = "bcdedit /set `"{$defaultGuid}`" device partition=$Drive`:"
                    $osdeviceCmd = "bcdedit /set `"{$defaultGuid}`" osdevice partition=$Drive`:"
                    
                    & $WriteLogFunction "Running: $deviceCmd"
                    $deviceOutput = & bcdedit /set "{$defaultGuid}" device "partition=$Drive`:" 2>&1 | Out-String
                    & $WriteLogFunction "Device Output: $deviceOutput"
                    
                    & $WriteLogFunction "Running: $osdeviceCmd"
                    $osdeviceOutput = & bcdedit /set "{$defaultGuid}" osdevice "partition=$Drive`:" 2>&1 | Out-String
                    & $WriteLogFunction "OSDevice Output: $osdeviceOutput"
                    
                    & $WriteLogFunction "[OK] BCD drive identifiers fixed"
                } else {
                    & $WriteLogFunction "[INFO] Could not find default boot entry GUID, skipping drive ID fix"
                }
            } catch {
                & $WriteLogFunction "[WARNING] Could not fix BCD drive IDs: $_"
            }
        } elseif ($bcdbootSuccess -and -not $winloadActuallyCopied) {
            & $WriteLogFunction "[WARNING] FALSE POSITIVE: bcdboot reported success but winload.efi was NOT copied!"
            & $WriteLogFunction "This indicates a write failure (possibly VMD, read-only EFI, or drive access issue)"
            
            # Check if VMD is the issue
            if ($VmdIssue -and $VmdIssue.VMDDetected -and -not $VmdIssue.DriverLoaded) {
                & $WriteLogFunction "[CRITICAL] Intel VMD driver not loaded - this is likely the cause!"
                & $WriteLogFunction "bcdboot cannot write to NVMe drive without VMD driver."
            }
            
            # Proceed to Force Wipe mode
            & $WriteLogFunction "Proceeding to Force Wipe mode..."
            Invoke-ForceWipeMode -Drive $Drive -EfiDrive $EfiDrive -WinloadEfiPath $winloadEfiPath -VmdIssue $VmdIssue -WriteLogFunction $WriteLogFunction
        } else {
            & $WriteLogFunction "[WARNING] bcdboot reported issues. Check output above."
            Invoke-EfiPartitionHealthCheck -Drive $Drive -EfiDrive $EfiDrive -WinloadEfiPath $winloadEfiPath -WriteLogFunction $WriteLogFunction
        }
    } catch {
        & $WriteLogFunction "[ERROR] bcdboot failed: $_"
    }
}

function Invoke-ForceWipeMode {
    param(
        [string]$Drive,
        [string]$EfiDrive,
        [string]$WinloadEfiPath,
        $VmdIssue,
        [scriptblock]$WriteLogFunction
    )
    
    # Step 4: FORCE WIPE MODE - Aggressive EFI Partition Repair
    & $WriteLogFunction "==============================================================="
    & $WriteLogFunction "FORCE WIPE MODE - Aggressive EFI Partition Repair"
    & $WriteLogFunction "==============================================================="
    & $WriteLogFunction ""
    
    # Step 4a: Delete old BCD and winload.efi manually
    & $WriteLogFunction "Step 4a: Manually deleting old BCD and winload.efi from EFI partition..."
    try {
        $oldBcdPath = "$EfiDrive`:\EFI\Microsoft\Boot\BCD"
        $oldWinloadPath = "$EfiDrive`:\EFI\Microsoft\Boot\winload.efi"
        
        if (Test-Path $oldBcdPath) {
            Remove-Item $oldBcdPath -Force -ErrorAction SilentlyContinue
            & $WriteLogFunction "[OK] Deleted old BCD file"
        }
        if (Test-Path $oldWinloadPath) {
            Remove-Item $oldWinloadPath -Force -ErrorAction SilentlyContinue
            & $WriteLogFunction "[OK] Deleted old winload.efi file"
        }
    } catch {
        & $WriteLogFunction "[WARNING] Could not delete old files: $_"
    }
    
    # Step 4b: Format EFI partition using diskpart (more reliable than format command)
    & $WriteLogFunction "Step 4b: Formatting EFI partition using diskpart..."
    & $WriteLogFunction "WARNING: This will completely wipe the EFI partition (safe if Windows partition is intact)"
    
    try {
        # Get partition number for diskpart
        $efiPartition = Get-Partition -DriveLetter $EfiDrive -ErrorAction SilentlyContinue
        if ($efiPartition) {
            $diskNumber = $efiPartition.DiskNumber
            $partitionNumber = $efiPartition.PartitionNumber
            
            # Create diskpart script
            $diskpartScript = @"
select disk $diskNumber
select partition $partitionNumber
format fs=fat32 quick label="System"
active
exit
"@
            
            & $WriteLogFunction "Running diskpart format..."
            $formatOutput = $diskpartScript | diskpart 2>&1 | Out-String
            & $WriteLogFunction "Diskpart Output: $formatOutput"
            
            Start-Sleep -Seconds 3
            
            # Step 4c: Retry bcdboot with /addlast flag
            & $WriteLogFunction "Step 4c: Retrying bcdboot with /addlast flag after format..."
            $bcdbootRetryCmd = "bcdboot $Drive`:\Windows /s $EfiDrive`: /f UEFI /v /addlast"
            & $WriteLogFunction "Running: $bcdbootRetryCmd"
            $bcdbootRetry = & bcdboot "$Drive`:\Windows" /s "$EfiDrive`:" /f UEFI /v /addlast 2>&1 | Out-String
            & $WriteLogFunction "bcdboot Retry Output: $bcdbootRetry"
            
            # Verify again
            Start-Sleep -Seconds 2
            if (Test-Path $WinloadEfiPath) {
                & $WriteLogFunction "[SUCCESS] winload.efi copied to EFI partition after Force Wipe"
                
                # Fix BCD drive IDs after Force Wipe
                & $WriteLogFunction "Fixing BCD drive identifiers after Force Wipe..."
                try {
                    # Ensure BCD exists after force wipe
                    $bcdCheck = Test-AndRecreateBCD -Drive $Drive -EfiDrive $EfiDrive -WriteLogFunction $WriteLogFunction
                    if (-not $bcdCheck.Success) {
                        & $WriteLogFunction "[WARNING] BCD may not be accessible after Force Wipe"
                    }
                    
                    $bcdEnum = bcdedit /enum "{default}" 2>&1 | Out-String
                    if ($bcdEnum -match "could not be opened|The system cannot find") {
                        & $WriteLogFunction "[WARNING] BCD is not accessible, cannot fix drive IDs"
                        return
                    }
                    
                    if ($bcdEnum -match '{([a-f0-9\-]{36})}') {
                        $defaultGuid = $matches[1]
                        & bcdedit /set "{$defaultGuid}" device "partition=$Drive`:" 2>&1 | Out-Null
                        & bcdedit /set "{$defaultGuid}" osdevice "partition=$Drive`:" 2>&1 | Out-Null
                        & $WriteLogFunction "[OK] BCD drive identifiers fixed after Force Wipe"
                    }
                } catch {
                    & $WriteLogFunction "[WARNING] Could not fix BCD drive IDs: $_"
                }
            } else {
                & $WriteLogFunction "[ERROR] winload.efi STILL missing after Force Wipe!"
                & $WriteLogFunction ""
                & $WriteLogFunction "CRITICAL: This indicates a deeper issue:"
                & $WriteLogFunction "  1. Source template missing: C:\Windows\System32\Boot\winload.efi"
                & $WriteLogFunction "  2. Intel VMD driver not loaded (check BIOS)"
                & $WriteLogFunction "  3. Multiple boot drives causing conflicts"
                & $WriteLogFunction "  4. Hardware failure or drive corruption"
                & $WriteLogFunction ""
                & $WriteLogFunction "MANUAL LAST RESORT COMMANDS:"
                & $WriteLogFunction "  # 1. Mount EFI"
                & $WriteLogFunction "  mountvol S: /S"
                & $WriteLogFunction ""
                & $WriteLogFunction "  # 2. Clear old BCD and Winload info"
                & $WriteLogFunction "  del S:\EFI\Microsoft\Boot\BCD /f"
                & $WriteLogFunction "  del S:\EFI\Microsoft\Boot\winload.efi /f"
                & $WriteLogFunction ""
                & $WriteLogFunction "  # 3. Force rebuild from local Windows source"
                & $WriteLogFunction "  bcdboot C:\Windows /s S: /f UEFI /addlast"
                & $WriteLogFunction ""
                
                # Check for VMD issue
                if ($VmdIssue -and $VmdIssue.VMDDetected -and -not $VmdIssue.DriverLoaded) {
                    & $WriteLogFunction "[CRITICAL] Intel VMD driver issue confirmed!"
                    & $WriteLogFunction "  - VMD is enabled in BIOS but driver not loaded in WinPE"
                    & $WriteLogFunction "  - bcdboot cannot write to NVMe drive"
                    & $WriteLogFunction "  - SOLUTION: Load VMD driver or disable VMD in BIOS"
                }
            }
        } else {
            & $WriteLogFunction "[ERROR] Could not get partition info for diskpart"
        }
    } catch {
        & $WriteLogFunction "[ERROR] Force Wipe mode failed: $_"
    }
}

function Invoke-EfiPartitionHealthCheck {
    param(
        [string]$Drive,
        [string]$EfiDrive,
        [string]$WinloadEfiPath,
        [scriptblock]$WriteLogFunction
    )
    
    # Step 4: Force Clean EFI Partition (if bcdboot failed)
    & $WriteLogFunction "Step 4: Checking EFI partition health (write-protection, space, corruption)..."
    try {
        $efiVolume = Get-Volume -DriveLetter $EfiDrive -ErrorAction SilentlyContinue
        $efiPartition = Get-Partition -DriveLetter $EfiDrive -ErrorAction SilentlyContinue
        
        $needsFormat = $false
        $formatReason = ""
        
        if ($efiVolume) {
            # Check filesystem type
            if ($efiVolume.FileSystemType -eq "RAW" -or [string]::IsNullOrWhiteSpace($efiVolume.FileSystemType)) {
                $needsFormat = $true
                $formatReason = "EFI partition has no filesystem (RAW)"
            }
            
            # Check health status
            if ($efiVolume.HealthStatus -ne "Healthy") {
                $needsFormat = $true
                $formatReason = "EFI partition health is not optimal: $($efiVolume.HealthStatus)"
            }
            
            # Check free space (EFI partition should have at least 10MB free)
            if ($efiVolume.SizeRemaining -lt 10MB) {
                $needsFormat = $true
                $formatReason = "EFI partition is out of space (only $([math]::Round($efiVolume.SizeRemaining/1MB, 2)) MB free)"
            }
        }
        
        # Check if partition is read-only
        if ($efiPartition -and $efiPartition.IsReadOnly) {
            $needsFormat = $true
            $formatReason = "EFI partition is read-only (write-protected)"
        }
        
        # If bcdboot failed, the EFI partition may be corrupted
        if (-not $needsFormat) {
            $needsFormat = $true
            $formatReason = "bcdboot failed - EFI partition may be corrupted or write-protected"
        }
        
        if ($needsFormat) {
            & $WriteLogFunction "[WARNING] EFI partition needs formatting: $formatReason"
            & $WriteLogFunction "Step 4: Formatting EFI partition $EfiDrive`: as FAT32 (quick format)..."
            & $WriteLogFunction "WARNING: This will wipe the EFI partition (safe if Windows partition is intact)"
            
            $formatOutput = & format "$EfiDrive`:" /fs:FAT32 /q /y 2>&1 | Out-String
            & $WriteLogFunction "Format Output: $formatOutput"
            
            Start-Sleep -Seconds 2
            
            # Retry bcdboot after format
            & $WriteLogFunction "Retrying bcdboot after EFI partition format..."
            $bcdbootRetry = & bcdboot "$Drive`:\Windows" /s "$EfiDrive`:" /f UEFI 2>&1 | Out-String
            & $WriteLogFunction "bcdboot Retry Output: $bcdbootRetry"
            
            # Verify winload.efi was copied
            if (Test-Path $WinloadEfiPath) {
                & $WriteLogFunction "[SUCCESS] winload.efi copied to EFI partition after format"
            } else {
                & $WriteLogFunction "[ERROR] winload.efi still missing after format and retry."
                & $WriteLogFunction "The source template (C:\Windows\System32\Boot\winload.efi) may be missing."
                & $WriteLogFunction "Step 5: Manual extraction from Windows installation media (install.wim/install.esd) is required."
            }
        } else {
            & $WriteLogFunction "[WARNING] EFI partition appears healthy, but bcdboot failed."
            & $WriteLogFunction "The issue may be that the source template (C:\Windows\System32\Boot\winload.efi) is missing."
            & $WriteLogFunction "Step 5: Manual extraction from Windows installation media may be required."
        }
    } catch {
        & $WriteLogFunction "[ERROR] EFI partition check/format failed: $_"
    }
}

# ==============================================================================

# Load centralized logging system
try {
    # Determine script root safely
    if ($PSScriptRoot) {
        $scriptRoot = $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path) {
        $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        # Fallback: try to get from current location
        $scriptRoot = if (Test-Path "Helper\ErrorLogging.ps1") { "Helper" } else { Get-Location }
    }
    
    if ($scriptRoot -and (Test-Path "$scriptRoot\ErrorLogging.ps1")) {
        . "$scriptRoot\ErrorLogging.ps1" -ErrorAction SilentlyContinue
        $null = Initialize-ErrorLogging -ScriptRoot $scriptRoot -RetentionDays 7 -ErrorAction SilentlyContinue
        Add-MiracleBootLog -Level "INFO" -Message "WinRepairGUI.ps1 loaded" -Location "WinRepairGUI.ps1" -ErrorAction SilentlyContinue
    }
    
    # Load Advanced Boot Troubleshooting module
    if ($scriptRoot -and (Test-Path "$scriptRoot\AdvancedBootTroubleshooting.ps1")) {
        . "$scriptRoot\AdvancedBootTroubleshooting.ps1" -ErrorAction SilentlyContinue
    }
} catch {
    # Silently continue if logging fails - don't block GUI launch
}

# Helper function to safely get controls with null checking
# Note: This will be defined inside Start-GUI to access $W directly

# Helper function to safely get count from any object (prevents Count property errors)
function Get-SafeCount {
    <#
    .SYNOPSIS
    Safely gets the count of an object, handling null, empty, and non-array cases.
    
    .PARAMETER Object
    The object to get the count from.
    
    .OUTPUTS
    Integer count (0 if object is null or doesn't have a Count property)
    #>
    param(
        [Parameter(Mandatory=$false)]
        [object]$Object
    )
    
    if ($null -eq $Object) {
        return 0
    }
    
    # Ensure it's an array
    $array = @($Object)
    
    # Try to get count
    try {
        return $array.Count
    } catch {
        return 0
    }
}

function Start-GUI {
    # XAML definition for the main window
    $XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Miracle Boot v7.2.0 - Advanced Recovery (Cursor)"
 Width="1200" Height="850" WindowStartupLocation="CenterScreen" Background="#F0F0F0">
<Grid>
    <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    
    <!-- Utility Toolbar -->
    <StackPanel Grid.Row="0" Orientation="Horizontal" Background="#E5E5E5" Margin="10,5">
        <TextBlock Text="Utilities:" VerticalAlignment="Center" Margin="5,0,10,0" FontWeight="Bold"/>
        <Button Content="Notepad" Name="BtnNotepad" Width="80" Height="25" Margin="2" ToolTip="Open Notepad"/>
        <Button Content="Registry" Name="BtnRegistry" Width="80" Height="25" Margin="2" ToolTip="Open Registry Editor"/>
        <Button Content="PowerShell" Name="BtnPowerShell" Width="90" Height="25" Margin="2" ToolTip="Open PowerShell"/>
        <Button Name="BtnCommandPrompt" Width="90" Height="25" Margin="2" ToolTip="Open Command Prompt (CMD) as Administrator">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="CMD" VerticalAlignment="Center" Margin="0,0,5,0"/>
                <TextBlock Text="⚡" FontSize="14" VerticalAlignment="Center"/>
            </StackPanel>
        </Button>
        <Button Content="System Restore" Name="BtnRestore" Width="110" Height="25" Margin="2" ToolTip="Open System Restore Points"/>
        <Button Content="Disk Management" Name="BtnDiskManagement" Width="130" Height="25" Margin="2" ToolTip="Open Disk Management"/>
        <Button Content="Restart Explorer" Name="BtnRestartExplorer" Width="130" Height="25" Margin="2" ToolTip="Restart Windows Explorer if it crashed"/>
        <Separator Margin="10,0"/>
        <Button Content="Enable Network" Name="BtnEnableNetwork" Width="110" Height="25" Margin="2" ToolTip="Enable network adapters and test internet"/>
        <Button Content="Network Diagnostics" Name="BtnNetworkDiagnostics" Width="150" Height="25" Margin="2" ToolTip="Comprehensive network diagnostics and driver management"/>
        <Button Content="Keyboard Symbols" Name="BtnKeyboardSymbols" Width="130" Height="25" Margin="2" ToolTip="Keyboard symbol helper and ALT code reference"/>
        <Button Content="ChatGPT Help" Name="BtnChatGPT" Width="100" Height="25" Margin="2" ToolTip="Open ChatGPT for boot assistance help"/>
        <Button Name="BtnSwitchToTUI" Width="35" Height="25" Margin="2" ToolTip="Switch to Command Line Mode (TUI)" Background="#2D2D30" Foreground="White" FontFamily="Consolas" FontSize="12" Padding="0">
            <TextBlock Text="&gt;_" VerticalAlignment="Center" HorizontalAlignment="Center"/>
        </Button>
        <Separator Margin="10,0"/>
        <TextBlock Name="NetworkStatus" Text="Network: Unknown" VerticalAlignment="Center" Margin="5,0" Foreground="Gray"/>
        <TextBlock Name="EnvStatus" Text="Environment: Detecting..." VerticalAlignment="Center" Margin="10,0" Foreground="Gray"/>
</StackPanel>
    
    <TabControl Grid.Row="1" Margin="10">
        <TabItem Header="Volumes &amp; Health">
            <DockPanel Margin="10">
                <Button DockPanel.Dock="Top" Content="Refresh Volume List" Height="35" Name="BtnVol" Background="#0078D7" Foreground="White" FontWeight="Bold"/>
                <ListView Name="VolList" Margin="0,10,0,0">
                    <ListView.View>
                        <GridView>
                            <GridViewColumn Header="Letter" DisplayMemberBinding="{Binding DriveLetter}" Width="50"/>
                            <GridViewColumn Header="Label" DisplayMemberBinding="{Binding FileSystemLabel}" Width="150"/>
                            <GridViewColumn Header="Size" DisplayMemberBinding="{Binding Size}" Width="100"/>
                            <GridViewColumn Header="Status" DisplayMemberBinding="{Binding HealthStatus}" Width="100"/>
                        </GridView>
                    </ListView.View>
                </ListView>
            </DockPanel>
</TabItem>

<TabItem Header="BCD Editor">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <!-- Toolbar -->
                <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                    <Button Content="Load/Refresh BCD" Height="35" Name="BtnBCD" Background="#0078D7" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <Button Content="Create Backup" Height="35" Name="BtnBCDBackup" Background="#28a745" Foreground="White" Width="130" Margin="0,0,10,0"/>
                    <Button Content="Fix Duplicates" Height="35" Name="BtnFixDuplicates" Background="#ffc107" Foreground="Black" Width="130" Margin="0,0,10,0"/>
                    <Button Content="Sync to All EFI Partitions" Height="35" Name="BtnSyncBCD" Background="#6f42c1" Foreground="White" Width="200" Margin="0,0,10,0"/>
                    <Button Content="Boot Diagnosis" Height="35" Name="BtnBootDiagnosisBCD" Background="#17a2b8" Foreground="White" Width="150"/>
</StackPanel>
                
                <!-- Main Content with Tabs -->
                <TabControl Grid.Row="1" Name="BCDTabControl">
                    <TabItem Header="Basic Editor">
                        <Grid Margin="5">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="2*"/>
                                <ColumnDefinition Width="1*"/>
                            </Grid.ColumnDefinitions>
                            
                            <StackPanel Grid.Column="0" Margin="5">
                                <TextBlock Text="BCD Boot Entries" FontWeight="Bold" Margin="0,0,0,5"/>
                                <ListBox Name="BCDList" Height="350" Margin="0,0,0,10">
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <StackPanel>
                                                <TextBlock Text="{Binding DisplayText}" FontWeight="Bold">
                                                    <TextBlock.Style>
                                                        <Style TargetType="TextBlock">
                                                            <Setter Property="Foreground" Value="#0078D7"/>
                                                            <Style.Triggers>
                                                                <DataTrigger Binding="{Binding IsDefault}" Value="True">
                                                                    <Setter Property="Foreground" Value="#28a745"/>
                                                                </DataTrigger>
                                                            </Style.Triggers>
                                                        </Style>
                                                    </TextBlock.Style>
                                                </TextBlock>
                                                <TextBlock Text="{Binding Id}" FontSize="10" Foreground="Gray"/>
                                            </StackPanel>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                                <TextBox Name="BCDBox" AcceptsReturn="True" Height="150" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" IsReadOnly="True" Background="#222" Foreground="#00FF00"/>
                            </StackPanel>

                            <StackPanel Grid.Column="1" Margin="5" Background="#E5E5E5">
                                <TextBlock Text="Edit Selected Entry" FontWeight="Bold" Margin="5"/>
                                <TextBlock Text="Identifier (GUID):" Margin="5,5,0,0"/>
                                <TextBox Name="EditId" Margin="5" IsReadOnly="True" Background="#DDD"/>
                                <TextBlock Text="Description:" Margin="5,5,0,0"/>
                                <TextBox Name="EditDescription" Margin="5"/>
                                <TextBlock Text="New Friendly Name:" Margin="5,5,0,0"/>
                                <TextBox Name="EditName" Margin="5"/>
                                <Button Content="Update Description" Name="BtnUpdateBcd" Margin="5" Height="25"/>
                                <Button Content="Set as Default Boot" Name="BtnSetDefault" Margin="5" Height="25" Background="#D78700" Foreground="White"/>
                                <Separator Margin="5,10"/>
                                <TextBlock Text="Boot Timeout (Seconds):" Margin="5"/>
                                <TextBox Name="TxtTimeout" Margin="5"/>
                                <Button Content="Save Timeout" Name="BtnTimeout" Margin="5" Height="25"/>
                            </StackPanel>
                        </Grid>
</TabItem>

                    <TabItem Header="Advanced Properties">
                        <Grid Margin="5">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            
                            <TextBlock Grid.Row="0" Text="Select an entry from Basic Editor to edit all properties" FontStyle="Italic" Margin="5" Foreground="Gray"/>
                            
                            <DataGrid Grid.Row="1" Name="BCDPropertiesGrid" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="False" Margin="5">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Property" Binding="{Binding Name}" Width="200" IsReadOnly="True"/>
                                    <DataGridTextColumn Header="Value" Binding="{Binding Value}" Width="*"/>
                                </DataGrid.Columns>
                            </DataGrid>
                            
                            <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Bottom" Margin="5">
                                <Button Content="Save Changes" Name="BtnSaveProperties" Height="30" Width="120" Background="#28a745" Foreground="White" Margin="5,0"/>
                                <Button Content="Reset" Name="BtnResetProperties" Height="30" Width="80" Margin="5,0"/>
                            </StackPanel>
                        </Grid>
                    </TabItem>
                </TabControl>
            </Grid>
        </TabItem>

        <TabItem Header="Boot Menu Simulator">
            <StackPanel Background="#003366" Margin="10">
                <TextBlock Text="Windows Boot Manager" Foreground="White" FontSize="22" HorizontalAlignment="Center" Margin="20"/>
                <TextBlock Text="Choose an operating system to start:" Foreground="White" Margin="40,0,0,10"/>
                <ListBox Name="SimList" Height="200" Width="500" Background="#003366" Foreground="White" BorderThickness="0" FontSize="18" Padding="20">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <TextBlock Text="{Binding}"/>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
                <TextBlock Name="SimTimeout" Text="Seconds until auto-start: 30" Foreground="White" HorizontalAlignment="Center" Margin="20"/>
                <TextBlock Text="Use the BCD Editor tab to modify these entries." Foreground="#CCC" FontSize="10" HorizontalAlignment="Center"/>
</StackPanel>
</TabItem>

        <TabItem Header="Driver Diagnostics">
            <DockPanel Margin="10">
                <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
                    <Button Content="Scan for Driver Errors" Height="35" Name="BtnDetect" Background="#dc3545" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Scan for Missing Drivers" Height="35" Name="BtnScanDrivers" Background="#28a745" Foreground="White" Width="200" Margin="0,0,10,0"/>
                    <Button Content="Scan All Drivers" Height="35" Name="BtnScanAllDrivers" Background="#17a2b8" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <ComboBox Name="DriveCombo" Width="100" Height="35" VerticalContentAlignment="Center"/>
                    <Button Content="Install Drivers" Height="35" Name="BtnInstallDrivers" Background="#6c757d" Foreground="White" Width="120" Margin="10,0,0,0" IsEnabled="False"/>
                </StackPanel>
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <TextBox Name="DrvBox" AcceptsReturn="True" VerticalScrollBarVisibility="Disabled" FontFamily="Consolas" Background="White" Foreground="Black" TextWrapping="Wrap" IsReadOnly="True"/>
                </ScrollViewer>
            </DockPanel>
        </TabItem>

        <TabItem Header="Boot Fixer">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- One-Click Repair Button -->
                <Border Grid.Row="0" Margin="0,0,0,15" Background="#E8F5E9" BorderBrush="#4CAF50" BorderThickness="2">
                    <StackPanel Margin="15">
                        <TextBlock Text="🚀 ONE-CLICK REPAIR" FontSize="18" FontWeight="Bold" Foreground="#2E7D32" Margin="0,0,0,5"/>
                        <TextBlock Text="Automatically diagnose and repair common boot issues. Perfect for non-technical users." TextWrapping="Wrap" Foreground="#333333" FontSize="12" Margin="0,0,0,10"/>
                        <Button Content="REPAIR MY PC" Name="BtnOneClickRepair" Height="50" Background="#4CAF50" Foreground="White" FontSize="16" FontWeight="Bold" Cursor="Hand" Margin="0,5"/>
                        <TextBlock Name="TxtOneClickStatus" Text="Click the button above to start automated repair" TextWrapping="Wrap" Foreground="#555555" FontSize="11" Margin="0,5,0,0" FontStyle="Italic"/>
                    </StackPanel>
                </Border>
                
                <StackPanel Grid.Row="1" Margin="0,0,0,15">
                    <CheckBox Name="ChkTestMode" Content="Test Mode (Preview commands only - will not execute)" IsChecked="True" FontWeight="Bold" Foreground="#B8860B" FontSize="12" Margin="5,5,5,8" VerticalContentAlignment="Center"/>
                    <TextBlock Text="When Test Mode is enabled, commands are displayed but not executed. Uncheck to apply fixes." Foreground="#666666" FontSize="11" Margin="5,0,5,5" TextWrapping="Wrap" LineHeight="16"/>
                </StackPanel>
                
                <GroupBox Grid.Row="2" Header="Boot Repair Operations" Margin="5,0,5,10">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
<StackPanel Margin="10">
                            <Button Content="1. Rebuild BCD from Windows Installation" Height="40" Name="BtnRebuildBCD" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,5"/>
                            <TextBlock Name="TxtRebuildBCD" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="2. Fix Boot Files (bootrec /fixboot)" Height="40" Name="BtnFixBoot" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtFixBoot" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="3. Scan for Windows Installations" Height="40" Name="BtnScanWindows" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtScanWindows" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="4. Rebuild BCD (bootrec /rebuildbcd)" Height="40" Name="BtnRebuildBCD2" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtRebuildBCD2" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="5. Set Default Boot Entry" Height="40" Name="BtnSetDefaultBoot" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtSetDefault" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="6. Boot Diagnosis" Height="40" Name="BtnBootDiagnosis" Background="#28a745" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtBootDiagnosis" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to run comprehensive boot diagnosis"/>
                            
                            <Button Content="7. Precision Detection &amp; Repair (ordered plan)" Height="40" Name="BtnPrecisionScan" Background="#d78700" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtPrecisionScan" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="DIAGNOSE-ONLY MODE (Default): Runs precision detection with dry-run preview. Shows what's broken without fixing. Uncheck Test Mode checkbox to apply fixes. Location: Boot Fixer tab → Button 7."/>
                            <Button Content="8. ONE-CLICK PRECISION FIXER" Height="40" Name="BtnOneClickPrecisionFix" Background="#28a745" Foreground="White" FontWeight="Bold" Margin="0,10,0,5" ToolTip="Automatically fixes all detected issues. For extreme cases, offers repair install with clear warnings."/>
                            <TextBlock Name="TxtOneClickPrecisionFix" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Fully automated: scans, fixes, verifies, and offers repair install for critical issues. No user intervention needed - just click and Windows will be fixed."/>
</StackPanel>
                    </ScrollViewer>
                </GroupBox>
                
                <GroupBox Grid.Row="3" Header="Command Output" Margin="5,10,5,5">
                    <ScrollViewer Height="150" VerticalScrollBarVisibility="Auto">
                        <TextBox Name="FixerOutput" AcceptsReturn="True" FontFamily="Consolas" Background="#222" Foreground="#00FF00" IsReadOnly="True" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </GroupBox>
            </Grid>
</TabItem>

        <TabItem Header="Diagnostics">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                    <TextBlock Text="Target Drive:" VerticalAlignment="Center" Margin="0,0,10,0" FontWeight="Bold"/>
                    <ComboBox Name="DiagDriveCombo" Width="120" Height="30" VerticalContentAlignment="Center" Margin="0,0,20,0"/>
                    <TextBlock Name="CurrentOSLabel" Text="" VerticalAlignment="Center" Foreground="#28a745" FontWeight="Bold" Margin="0,0,10,0"/>
                </StackPanel>
                
                <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
                    <Button Content="Check System Restore" Height="35" Name="BtnCheckRestore" Background="#28a745" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Create Restore Point" Height="35" Name="BtnCreateRestorePoint" Background="#6f42c1" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="List Restore Points" Height="35" Name="BtnListRestorePoints" Background="#17a2b8" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Check Reagentc Health" Height="35" Name="BtnCheckReagentc" Background="#0078D7" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Get OS Information" Height="35" Name="BtnGetOSInfo" Background="#6f42c1" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Install Failure Analysis" Height="35" Name="BtnInstallFailure" Background="#dc3545" Foreground="White" Width="200"/>
</StackPanel>
                
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                    <TextBox Name="DiagBox" AcceptsReturn="True" VerticalScrollBarVisibility="Disabled" FontFamily="Consolas" Background="White" Foreground="Black" TextWrapping="Wrap" IsReadOnly="True" Padding="10"/>
                </ScrollViewer>
            </Grid>
</TabItem>

        <TabItem Header="Diagnostics &amp; Logs">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Margin="0,0,0,10">
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                        <TextBlock Text="Target Drive:" VerticalAlignment="Center" Margin="0,0,10,0" FontWeight="Bold"/>
                        <ComboBox Name="LogDriveCombo" Width="120" Height="30" VerticalContentAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <Button Content="Driver Forensics" Height="35" Name="BtnDriverForensics" Background="#dc3545" Foreground="White" Width="150" Margin="0,0,10,0"/>
                        <Button Content="Analyze Boot Log" Height="35" Name="BtnAnalyzeBootLog" Background="#dc3545" Foreground="White" Width="150" Margin="0,0,10,0"/>
                        <Button Content="Analyze Event Logs" Height="35" Name="BtnAnalyzeEventLogs" Background="#17a2b8" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <Button Content="Boot Diagnosis &amp; Repair" Height="35" Name="BtnFullBootDiagnosis" Background="#28a745" Foreground="White" Width="200" Margin="0,0,10,0" ToolTip="Diagnose boot issues with 3 modes: Diagnosis Only, Diagnosis + Fix, or Diagnosis Then Ask"/>
                    <Button Content="Hardware Support" Height="35" Name="BtnHardwareSupport" Background="#6f42c1" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <Button Content="Unofficial Repair Tips" Height="35" Name="BtnRepairTips" Background="#ffc107" Foreground="Black" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Generate Registry Override Script" Height="35" Name="BtnGenRegScript" Background="#dc3545" Foreground="White" Width="220" Margin="0,0,10,0"/>
                    <Button Content="One-Click Registry Fixes" Height="35" Name="BtnOneClickFix" Background="#28a745" Foreground="White" Width="200" Margin="0,0,10,0"/>
                    <Button Content="Filter Driver Forensics" Height="35" Name="BtnFilterForensics" Background="#17a2b8" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Recommended Tools" Height="35" Name="BtnRecommendedTools" Background="#6c757d" Foreground="White" Width="160" Margin="0,0,10,0"/>
                        <Button Content="Export In-Use Drivers" Height="35" Name="BtnExportDrivers" Background="#28a745" Foreground="White" Width="180" Margin="0,0,10,0"/>
                        <Button Content="Generate Cleanup Script" Height="35" Name="BtnGenCleanupScript" Background="#ffc107" Foreground="Black" Width="180" Margin="0,0,10,0"/>
                        <Button Content="In-Place Upgrade Readiness" Height="35" Name="BtnInPlaceReadiness" Background="#dc3545" Foreground="White" Width="200" Margin="0,0,10,0"/>
                        <Button Content="Ensure Repair-Install Ready" Height="35" Name="BtnRepairInstallReady" Background="#dc3545" Foreground="White" Width="220" Margin="0,0,10,0"/>
                        <Button Content="Repair Templates" Height="35" Name="BtnRepairTemplates" Background="#6f42c1" Foreground="White" Width="180"/>
                        <Button Content="Precision Parity (CLI vs GUI/TUI)" Height="35" Name="BtnPrecisionParity" Background="#d78700" Foreground="White" Width="230" Margin="10,0,0,0" ToolTip="Run precision scan baseline and compare outputs for parity (TC-010)"/>
                        <Button Content="Export Precision Scan (JSON)" Height="35" Name="BtnPrecisionJson" Background="#2d7dd2" Foreground="White" Width="200" Margin="10,0,0,0" ToolTip="Run precision scan and export results as JSON for logs/automation"/>
                        <Button Content="Save Precision JSON to File" Height="35" Name="BtnPrecisionJsonSave" Background="#1b4f72" Foreground="White" Width="210" Margin="10,0,0,0" ToolTip="Run precision scan and save JSON to a file (includes bugcheck)"/>
                        <Button Content="Save Parity JSON to File" Height="35" Name="BtnPrecisionParitySave" Background="#5a2a83" Foreground="White" Width="200" Margin="10,0,0,0" ToolTip="Run parity harness and save JSON (TC-010 evidence)"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
                        <Button Content="Comprehensive Log Analysis" Height="35" Name="BtnComprehensiveLogAnalysis" Background="#dc3545" Foreground="White" Width="250" Margin="0,0,10,0" FontWeight="Bold" ToolTip="Gather and analyze all important logs from all tiers"/>
                        <Button Content="Open Event Viewer" Height="35" Name="BtnOpenEventViewer" Background="#17a2b8" Foreground="White" Width="180" Margin="0,0,10,0" ToolTip="Open Windows Event Viewer"/>
                        <Button Content="Crash Dump Analyzer" Height="35" Name="BtnCrashDumpAnalyzer" Background="#6f42c1" Foreground="White" Width="200" Margin="0,0,10,0" ToolTip="Launch crashanalyze.exe to analyze crash dumps"/>
                    </StackPanel>
                </StackPanel>
                
                <TextBlock Grid.Row="1" Text="Offline log analysis from target Windows drive. Driver Forensics identifies missing storage drivers and required INF files. Hardware Support shows manufacturer links and driver update alerts." 
                           FontStyle="Italic" Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,10"/>
                
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                    <TextBox Name="LogAnalysisBox" AcceptsReturn="True" VerticalScrollBarVisibility="Disabled" FontFamily="Consolas" Background="White" Foreground="Black" TextWrapping="Wrap" IsReadOnly="True" Padding="10"/>
                </ScrollViewer>
            </Grid>
        </TabItem>
        
        <TabItem Header="Repair Install Forcer">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Margin="0,0,0,10">
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                        <TextBlock Text="Force Windows to perform a repair-only in-place upgrade from ISO" FontWeight="Bold" FontSize="14" VerticalAlignment="Center"/>
                        <Button Name="BtnRepairInstallInfo" Content="ⓘ" FontSize="16" FontWeight="Bold" Foreground="#0078D7" Background="Transparent" BorderThickness="0" Cursor="Hand" Width="30" Height="30" Margin="10,0,0,0" ToolTip="Click for detailed information about Repair Install Forcer"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                        <RadioButton Name="RbOnlineMode" Content="Online Mode (Running Windows)" IsChecked="True" Margin="0,0,20,0"/>
                        <RadioButton Name="RbOfflineMode" Content="Offline Mode (Non-Booting PC - WinPE/WinRE)" Foreground="#d78700"/>
                    </StackPanel>
                    <TextBlock Name="RepairModeDescription" Text="This forces Setup to reinstall system files while keeping apps and data. Requires same edition, architecture, and build family. Must run from inside Windows." 
                               Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,10"/>
                </StackPanel>
                
                <GroupBox Grid.Row="1" Header="ISO Selection &amp; Options" Margin="5">
                    <StackPanel Margin="10">
                        <StackPanel Orientation="Horizontal" Margin="0,5" Name="OfflineDrivePanel" Visibility="Collapsed">
                            <TextBlock Text="Offline Windows Drive:" VerticalAlignment="Center" Width="180" Margin="0,0,10,0"/>
                            <ComboBox Name="RepairOfflineDrive" Width="100" Height="25" VerticalContentAlignment="Center" Margin="0,0,10,0"/>
                            <TextBlock Text="(Drive letter where Windows is installed)" Foreground="Gray" VerticalAlignment="Center" FontStyle="Italic"/>
                        </StackPanel>
                        
                        <StackPanel Orientation="Horizontal" Margin="0,5">
                            <TextBlock Text="ISO/Mounted Folder Path:" VerticalAlignment="Center" Width="180" Margin="0,0,10,0"/>
                            <TextBox Name="RepairISOPath" Width="400" Height="25" VerticalContentAlignment="Center" Margin="0,0,10,0"/>
                            <Button Content="Browse..." Name="BtnBrowseISO" Width="80" Height="25"/>
                        </StackPanel>
                        
                        <StackPanel Orientation="Horizontal" Margin="0,10,0,5">
                            <CheckBox Name="ChkSkipCompat" Content="Skip Compatibility Checks" IsChecked="True" Margin="0,0,20,0"/>
                            <CheckBox Name="ChkDisableDynamicUpdate" Content="Disable Dynamic Update" IsChecked="True" Margin="0,0,20,0"/>
                            <CheckBox Name="ChkForceEdition" Content="Force Edition Alignment" IsChecked="False"/>
                        </StackPanel>
                        
                        <StackPanel Orientation="Horizontal" Margin="0,10,0,5">
                            <Button Content="Check Prerequisites" Name="BtnCheckPrereq" Background="#17a2b8" Foreground="White" Width="150" Height="35" Margin="0,0,10,0"/>
                            <Button Content="Show Instructions" Name="BtnShowInstructions" Background="#6c757d" Foreground="White" Width="150" Height="35" Margin="0,0,10,0"/>
                            <Button Content="Start Repair Install" Name="BtnStartRepair" Background="#28a745" Foreground="White" Width="150" Height="35" FontWeight="Bold"/>
                        </StackPanel>
                    </StackPanel>
                </GroupBox>
                
                <GroupBox Grid.Row="2" Header="Status &amp; Output" Margin="5,10,5,5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <TextBox Name="RepairInstallOutput" AcceptsReturn="True" FontFamily="Consolas" Background="#222" Foreground="#00FF00" IsReadOnly="True" TextWrapping="Wrap" Padding="10"/>
                    </ScrollViewer>
                </GroupBox>
                
                <TextBlock Grid.Row="3" Text="Note: This will launch Windows Setup and restart your system. Ensure you have backups and BitLocker recovery key if applicable." 
                           Foreground="#d78700" FontStyle="Italic" TextWrapping="Wrap" Margin="5,10,5,0"/>
            </Grid>
        </TabItem>
        
        <TabItem Header="Summary">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Margin="0,0,0,10">
                    <TextBlock Text="Windows Boot Health &amp; Update Eligibility Summary" FontWeight="Bold" FontSize="14" Margin="0,0,0,10"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                        <TextBlock Text="Target Drive:" VerticalAlignment="Center" Width="100" Margin="0,0,10,0"/>
                        <ComboBox Name="SummaryDriveCombo" Width="100" Height="25" VerticalContentAlignment="Center" Margin="0,0,10,0"/>
                        <Button Content="Refresh Summary" Name="BtnRefreshSummary" Background="#0078D7" Foreground="White" Width="150" Height="35" FontWeight="Bold"/>
                    </StackPanel>
                </StackPanel>
                
                <TabControl Grid.Row="1" Name="SummaryTabControl">
                    <TabItem Header="Boot Health">
                        <Grid Margin="5">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            
                            <StackPanel Grid.Row="0" Margin="0,0,0,10">
                                <TextBlock Text="Boot Health Overview" FontWeight="Bold" FontSize="12" Margin="0,0,0,5"/>
                                <TextBlock Name="BootHealthStatus" Text="Click 'Refresh Summary' to analyze boot health" 
                                           FontSize="11" Foreground="Gray" TextWrapping="Wrap"/>
                            </StackPanel>
                            
                            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                                <TextBox Name="BootHealthBox" AcceptsReturn="True" VerticalScrollBarVisibility="Disabled" 
                                         FontFamily="Consolas" Background="White" Foreground="Black" 
                                         TextWrapping="Wrap" IsReadOnly="True" Padding="10"/>
                            </ScrollViewer>
                        </Grid>
                    </TabItem>
                    
                    <TabItem Header="Windows Update Eligibility">
                        <Grid Margin="5">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            
                            <StackPanel Grid.Row="0" Margin="0,0,0,10">
                                <TextBlock Text="In-Place Repair Upgrade Eligibility" FontWeight="Bold" FontSize="12" Margin="0,0,0,5"/>
                                <TextBlock Name="UpdateEligibilityStatus" Text="Click 'Refresh Summary' to check Windows Update eligibility" 
                                           FontSize="11" Foreground="Gray" TextWrapping="Wrap"/>
                            </StackPanel>
                            
                            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                                <TextBox Name="UpdateEligibilityBox" AcceptsReturn="True" VerticalScrollBarVisibility="Disabled" 
                                         FontFamily="Consolas" Background="White" Foreground="Black" 
                                         TextWrapping="Wrap" IsReadOnly="True" Padding="10"/>
                            </ScrollViewer>
                        </Grid>
                    </TabItem>
                </TabControl>
            </Grid>
        </TabItem>
        
        <TabItem Header="Settings">
            <Grid Margin="20">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <!-- Interface Scale Section -->
                <GroupBox Grid.Row="0" Header="Interface Scale" Margin="0,0,0,20" Padding="15">
                    <StackPanel>
                        <TextBlock Text="Make interface elements bigger or smaller" 
                                   FontSize="12" Foreground="Gray" Margin="0,0,0,15"/>
                        
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="Small" VerticalAlignment="Center" Margin="0,0,15,0" FontSize="11"/>
                            <Slider Name="InterfaceScaleSlider" 
                                    Width="400" 
                                    Height="25" 
                                    Minimum="0.75" 
                                    Maximum="1.5" 
                                    Value="1.0" 
                                    TickFrequency="0.05" 
                                    IsSnapToTickEnabled="True"
                                    VerticalAlignment="Center"
                                    Margin="0,0,15,0"/>
                            <TextBlock Text="Big" VerticalAlignment="Center" FontSize="11"/>
                            <Button Name="BtnResetScale" Content="Reset" Width="80" Height="30" Margin="20,0,0,0" 
                                    ToolTip="Reset interface scale to default (100%)"/>
                        </StackPanel>
                        
                        <TextBlock Name="ScaleValueText" 
                                   Text="Current scale: 100%" 
                                   FontSize="11" 
                                   Foreground="#0078D7" 
                                   FontWeight="SemiBold" 
                                   Margin="0,10,0,0"/>
                    </StackPanel>
                </GroupBox>
                
                <!-- Additional Settings Section (placeholder for future settings) -->
                <GroupBox Grid.Row="1" Header="Additional Settings" Margin="0,0,0,20" Padding="15" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="More settings will be added here in future updates." 
                                   FontSize="11" Foreground="Gray"/>
                    </StackPanel>
                </GroupBox>
            </Grid>
        </TabItem>
</TabControl>
    
    <!-- Status Bar -->
    <StatusBar Grid.Row="2" Background="#E5E5E5" Height="25">
        <StatusBar.ItemsPanel>
            <ItemsPanelTemplate>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                </Grid>
            </ItemsPanelTemplate>
        </StatusBar.ItemsPanel>
        <StatusBarItem Grid.Column="0">
            <TextBlock Name="StatusBarText" Text="Ready" VerticalAlignment="Center" Margin="5,0"/>
        </StatusBarItem>
        <StatusBarItem Grid.Column="1">
            <StackPanel Orientation="Horizontal" Margin="5,0">
                <TextBlock Name="StatusBarProgress" Text="" VerticalAlignment="Center" Margin="0,0,10,0" Foreground="#0078D7" FontWeight="Bold"/>
                <ProgressBar Name="StatusBarProgressBar" Width="100" Height="15" Visibility="Collapsed" IsIndeterminate="True"/>
            </StackPanel>
        </StatusBarItem>
    </StatusBar>
</Grid>
</Window>
"@

# #region agent log
try {
    $logPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".cursor\debug.log"
    $logEntry = @{
        sessionId = "debug-session"
        runId = "gui-launch-1"
        hypothesisId = "A"
        location = "WinRepairGUI.ps1:469"
        message = "XAML parsing start"
        data = @{ xamlLength = $XAML.Length }
        timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Compress
    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
} catch {}
# #endregion agent log

try {
    # #region agent log
    try {
        $logPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".cursor\debug.log"
        $logEntry = @{
            sessionId = "debug-session"
            runId = "gui-launch-verify"
            hypothesisId = "XAML-PARSE"
            location = "WinRepairGUI.ps1:before-parse"
            message = "About to parse XAML"
            data = @{ xamlLength = $XAML.Length; xamlPreview = $XAML.Substring(0, [Math]::Min(200, $XAML.Length)) }
            timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    # #endregion agent log
    
    # First validate XML structure
    try {
        $xmlDoc = [xml]$XAML
        # #region agent log
        try {
            $logEntry = @{
                sessionId = "debug-session"
                runId = "gui-launch-verify"
                hypothesisId = "XAML-PARSE"
                location = "WinRepairGUI.ps1:xml-validated"
                message = "XML structure validated"
                data = @{ rootElement = $xmlDoc.DocumentElement.Name }
                timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            } | ConvertTo-Json -Compress
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
        } catch {}
        # #endregion agent log
    } catch {
        # #region agent log
        try {
            $logEntry = @{
                sessionId = "debug-session"
                runId = "gui-launch-verify"
                hypothesisId = "XAML-PARSE"
                location = "WinRepairGUI.ps1:xml-validation-failed"
                message = "XML validation failed"
                data = @{ error = $_.Exception.Message; innerException = $_.Exception.InnerException.Message }
                timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            } | ConvertTo-Json -Compress
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
        } catch {}
        # #endregion agent log
        throw "XAML XML structure is invalid: $_"
    }
    
    # Parse XAML with enhanced error handling and stack overflow protection
    try {
        # Validate XAML size to prevent stack overflow (10MB limit)
        $xamlSizeBytes = [System.Text.Encoding]::UTF8.GetByteCount($XAML)
        $xamlSizeMB = [math]::Round($xamlSizeBytes / 1MB, 2)
        
        if ($xamlSizeMB -gt 10) {
            throw "XAML is too large ($xamlSizeMB MB). This may cause stack overflow. Maximum recommended size: 10 MB."
        }
        
        Write-Host "Parsing XAML ($xamlSizeMB MB)..." -ForegroundColor Gray
        
        # Use direct parsing with proper resource cleanup
        # Note: WPF requires STA mode, so we cannot use jobs for XAML parsing
        $xmlReader = $null
        try {
            # Ensure we have the XML document (already validated above)
            if (-not $xmlDoc) {
                $xmlDoc = [xml]$XAML
            }
            
            $xmlReader = New-Object System.Xml.XmlNodeReader($xmlDoc)
            
            # Attempt XAML load with error context
            Write-Host "Loading XAML into WPF window object..." -ForegroundColor Gray
            $W = [Windows.Markup.XamlReader]::Load($xmlReader)
            
            if ($null -eq $W) {
                throw "XAML parsing returned null window object"
            }
            
            Write-Host "XAML parsed successfully. Window object created." -ForegroundColor Green
            Write-Host ""
            Write-Host "Initializing GUI components..." -ForegroundColor Yellow
            Write-Host "This may take 30-60 seconds. Please wait..." -ForegroundColor Yellow
            Write-Host ""
        } catch {
            $errorMsg = $_.Exception.Message
            $innerError = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $null }
            
            # Check for stack overflow indicators
            if ($errorMsg -match 'stack|overflow|buffer|memory|0xC0000409|-1073740771|STATUS_STACK_BUFFER_OVERRUN') {
                throw "CRITICAL: Stack buffer overrun detected during XAML parsing. This indicates the XAML is too complex, has circular references, or exceeds system limits. Error: $errorMsg" + $(if ($innerError) { " (Inner: $innerError)" } else { "" })
            }
            
            throw "Failed to parse XAML: $errorMsg" + $(if ($innerError) { " (Inner: $innerError)" } else { "" })
        } finally {
            # Clean up XML reader
            if ($xmlReader) {
                try {
                    $xmlReader.Close()
                    $xmlReader.Dispose()
                } catch {
                    # Ignore cleanup errors
                }
            }
        }
    } catch {
        $errorMsg = $_.Exception.Message
        throw "XAML parsing failed: $errorMsg"
    }
    
    # #region agent log
    try {
        $logEntry = @{
            sessionId = "debug-session"
            runId = "gui-launch-verify"
            hypothesisId = "XAML-PARSE"
            location = "WinRepairGUI.ps1:parse-success"
            message = "XAML parsing success"
            data = @{ windowType = $W.GetType().FullName; windowNotNull = ($null -ne $W) }
            timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    # #endregion agent log
} catch {
    # #region agent log
    try {
        $logPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".cursor\debug.log"
        $logEntry = @{
            sessionId = "debug-session"
            runId = "gui-launch-verify"
            hypothesisId = "XAML-PARSE"
            location = "WinRepairGUI.ps1:parse-failed"
            message = "XAML parsing failed"
            data = @{ 
                error = $_.Exception.Message
                innerException = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $null }
                stackTrace = $_.ScriptStackTrace
            }
            timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    # #endregion agent log
    throw "Failed to parse XAML: $_"
}

# Helper function to safely get controls with null checking
# MUST be defined here (right after $W is created) because it's called during event handler setup
function Get-Control {
    param([string]$Name, [switch]$Silent)  # Silent flag to suppress logging for optional controls
    if (-not $W) {
        if (-not $Silent) {
            Add-MiracleBootLog -Level "WARNING" -Message "Window object not available" -Location "Get-Control" -NoConsole
        }
        return $null
    }
    $control = $W.FindName($Name)
    if (-not $control) {
        if (-not $Silent) {
            Add-MiracleBootLog -Level "WARNING" -Message "Control '$Name' not found in XAML" -Location "Get-Control" -Data @{ControlName=$Name} -NoConsole
        }
    }
    return $control
}

# Helper function to safely wire up event handlers with null checking
function Connect-EventHandler {
    param(
        [string]$ControlName,
        [string]$EventName,
        [scriptblock]$Handler
    )
    $control = Get-Control -Name $ControlName
    if ($control) {
        try {
            $control.$EventName.Add($Handler)
        } catch {
            Write-Warning "Failed to wire up $EventName event for '$ControlName': $_"
        }
    } else {
        Write-Warning "Skipping event handler for '$ControlName' - control not found in XAML"
    }
}

# Load LogAnalysis module (with safe path resolution)
try {
    # Determine script root safely
    $guiScriptRoot = if ($PSScriptRoot) { 
        $PSScriptRoot 
    } elseif ($MyInvocation.MyCommand.Path) { 
        Split-Path -Parent $MyInvocation.MyCommand.Path 
    } else {
        # Fallback: try common locations
        if (Test-Path "Helper\LogAnalysis.ps1") { 
            "Helper" 
        } elseif (Test-Path "$(Get-Location)\Helper\LogAnalysis.ps1") {
            Join-Path (Get-Location) "Helper"
        } else {
            $null
        }
    }
    
    if ($guiScriptRoot) {
        $logAnalysisPath = Join-Path $guiScriptRoot "LogAnalysis.ps1"
        if (Test-Path $logAnalysisPath) {
            . $logAnalysisPath -ErrorAction SilentlyContinue
        }
    }
} catch {
    # Silently continue if LogAnalysis fails to load - don't block GUI launch
    Write-Warning "Failed to load LogAnalysis module: $_" -ErrorAction SilentlyContinue
}

# Detect environment
$envType = "FullOS"
if (Test-Path 'HKLM:\System\CurrentControlSet\Control\MiniNT') { $envType = "WinRE" }
if ($env:SystemDrive -eq 'X:') { $envType = "WinRE" }

# #region agent log
try {
    $logEntry = @{
        sessionId = "debug-session"
        runId = "gui-launch-1"
        hypothesisId = "B"
        location = "WinRepairGUI.ps1:475"
        message = "Before FindName EnvStatus"
        data = @{ envType = $envType; windowNotNull = ($null -ne $W) }
        timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Compress
    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
} catch {}
# #endregion agent log

$envStatusControl = $W.FindName("EnvStatus")

# #region agent log
try {
    $logEntry = @{
        sessionId = "debug-session"
        runId = "gui-launch-1"
        hypothesisId = "B"
        location = "WinRepairGUI.ps1:477"
        message = "After FindName EnvStatus"
        data = @{ controlIsNull = ($null -eq $envStatusControl); controlType = if ($envStatusControl) { $envStatusControl.GetType().FullName } else { "null" } }
        timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Compress
    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
} catch {}
# #endregion agent log

if ($envStatusControl) {
    $envStatusControl.Text = "Environment: $envType"
} else {
    Write-Warning "EnvStatus control not found in XAML"
}

# Utility buttons (with null checks)
$btnNotepad = $W.FindName("BtnNotepad")
if ($btnNotepad) {
    $btnNotepad.Add_Click({
        try {
            Start-Process notepad.exe -ErrorAction SilentlyContinue
        } catch {
            [System.Windows.MessageBox]::Show("Notepad not available in this environment.", "Warning", "OK", "Warning")
        }
    })
} else {
    Write-Warning "BtnNotepad control not found in XAML"
}

$btnRegistry = $W.FindName("BtnRegistry")
if ($btnRegistry) {
    $btnRegistry.Add_Click({
        try {
            Start-Process regedit.exe -ErrorAction SilentlyContinue
        } catch {
            [System.Windows.MessageBox]::Show("Registry Editor not available in this environment.", "Warning", "OK", "Warning")
        }
    })
} else {
    Write-Warning "BtnRegistry control not found in XAML"
}

$btnPowerShell = $W.FindName("BtnPowerShell")
if ($btnPowerShell) {
    $btnPowerShell.Add_Click({
        try {
            Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle = 'MiracleBoot - PowerShell'" -ErrorAction SilentlyContinue
        } catch {
            [System.Windows.MessageBox]::Show("PowerShell not available.", "Error", "OK", "Error")
        }
    })
} else {
    Write-Warning "BtnPowerShell control not found in XAML"
}

$btnCommandPrompt = $W.FindName("BtnCommandPrompt")
if ($btnCommandPrompt) {
    $btnCommandPrompt.Add_Click({
        try {
            # Launch CMD as Administrator
            Start-Process cmd.exe -Verb RunAs -ArgumentList "/k", "title MiracleBoot - Command Prompt" -ErrorAction SilentlyContinue
        } catch {
            # If RunAs fails, try without elevation
            try {
                Start-Process cmd.exe -ArgumentList "/k", "title MiracleBoot - Command Prompt" -ErrorAction SilentlyContinue
            } catch {
                [System.Windows.MessageBox]::Show("Command Prompt not available.", "Error", "OK", "Error")
            }
        }
    })
} else {
    Write-Warning "BtnCommandPrompt control not found in XAML"
}

$btnDiskManagement = $W.FindName("BtnDiskManagement")
if ($btnDiskManagement) {
    $btnDiskManagement.Add_Click({
        try {
            Start-Process diskmgmt.msc -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Disk Management not available in this environment.", "Warning", "OK", "Warning")
        }
    })
} else {
    Write-Warning "BtnDiskManagement control not found in XAML"
}

$btnRestartExplorer = $W.FindName("BtnRestartExplorer")
if ($btnRestartExplorer) {
    $btnRestartExplorer.Add_Click({
        try {
            $result = Restart-WindowsExplorer
            if ($result.Success) {
                [System.Windows.MessageBox]::Show("Windows Explorer restarted successfully.`n`n$($result.Message)", "Explorer Restarted", "OK", "Information")
            } else {
                [System.Windows.MessageBox]::Show("Failed to restart Windows Explorer:`n`n$($result.Message)", "Error", "OK", "Error")
            }
        } catch {
            [System.Windows.MessageBox]::Show("Error restarting Windows Explorer: $_", "Error", "OK", "Error")
        }
    })
} else {
    Write-Warning "BtnRestartExplorer control not found in XAML"
}

$btnRestore = $W.FindName("BtnRestore")
if ($btnRestore) {
    $btnRestore.Add_Click({
        # Switch to Diagnostics tab and run System Restore check
        try {
            $grid = $W.Content
            $tabControl = $grid.Children | Where-Object { $_.GetType().Name -eq 'TabControl' } | Select-Object -First 1
            
            if ($tabControl) {
                $diagTab = $tabControl.Items | Where-Object { $_.Header -eq "Diagnostics" }
                if ($diagTab) {
                    $tabControl.SelectedItem = $diagTab
                    # Use dispatcher to ensure UI is updated before triggering button
                    $W.Dispatcher.Invoke([action]{
                        $btnCheckRestore = $W.FindName("BtnCheckRestore")
                        if ($btnCheckRestore) {
                            $btnCheckRestore.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                        }
                    }, [System.Windows.Threading.DispatcherPriority]::Input)
                }
            }
        } catch {
            # Fallback: show message directing user to Diagnostics tab
            [System.Windows.MessageBox]::Show("Please navigate to the Diagnostics tab and click 'Check System Restore' to view restore points.", "Info", "OK", "Information")
        }
    })
} else {
    Write-Warning "BtnRestore control not found in XAML"
}

# Network enablement button
$btnEnableNetwork = $W.FindName("BtnEnableNetwork")
if ($btnEnableNetwork) {
    $btnEnableNetwork.Add_Click({
        try {
            Update-StatusBar -Message "Enabling network adapters..." -ShowProgress
            $result = Enable-NetworkWinRE
            
            $networkStatusControl = Get-Control "NetworkStatus"
            if ($result.Success) {
                if ($networkStatusControl) {
                    $networkStatusControl.Text = "Network: Enabled"
                    $networkStatusControl.Foreground = "Green"
                }
                
                # Test internet connectivity
                Update-StatusBar -Message "Testing internet connectivity..." -ShowProgress
                $internetTest = Test-InternetConnectivity
                
                if ($internetTest.Connected) {
                    if ($networkStatusControl) {
                        $networkStatusControl.Text = "Network: Connected"
                    }
                    [System.Windows.MessageBox]::Show("Network enabled successfully!`n`n$($result.Message)`n`n$($internetTest.Message)", "Network Enabled", "OK", "Information")
                } else {
                    if ($networkStatusControl) {
                        $networkStatusControl.Text = "Network: No Internet"
                        $networkStatusControl.Foreground = "Orange"
                    }
                    [System.Windows.MessageBox]::Show("Network adapters enabled, but no internet connectivity detected.`n`n$($result.Message)`n`n$($internetTest.Message)", "Network Enabled (No Internet)", "OK", "Warning")
                }
            } else {
                if ($networkStatusControl) {
                    $networkStatusControl.Text = "Network: Failed"
                    $networkStatusControl.Foreground = "Red"
                }
                [System.Windows.MessageBox]::Show("Failed to enable network:`n`n$($result.Message)", "Network Error", "OK", "Error")
            }
            Update-StatusBar -Message "Network operation complete" -HideProgress
        } catch {
            Update-StatusBar -Message "Network operation failed: $_" -HideProgress
            [System.Windows.MessageBox]::Show("Error enabling network: $_", "Error", "OK", "Error")
        }
    })
} else {
    Write-Warning "BtnEnableNetwork control not found in XAML"
}

# ChatGPT Help button
$btnNetworkDiagnostics = Get-Control -Name "BtnNetworkDiagnostics"
if ($btnNetworkDiagnostics) {
    $btnNetworkDiagnostics.Add_Click({
    try {
        if (Get-Command Invoke-NetworkDiagnostics -ErrorAction SilentlyContinue) {
            Update-StatusBar -Message "Running network diagnostics..." -ShowProgress
            
            # Switch to Diagnostics tab if available
            $grid = $W.Content
            $tabControl = $grid.Children | Where-Object { $_.GetType().Name -eq 'TabControl' } | Select-Object -First 1
            
            if ($tabControl) {
                $diagTab = $tabControl.Items | Where-Object { $_.Header -eq "Diagnostics" }
                if ($diagTab) {
                    $tabControl.SelectedItem = $diagTab
                }
            }
            
            $result = Invoke-NetworkDiagnostics
            $diagBox = Get-Control "DiagBox"
            if ($diagBox) {
                $diagBox.Text = $result.Report
            }
            Update-StatusBar -Message "Network diagnostics complete" -HideProgress
        } else {
            [System.Windows.MessageBox]::Show(
                "Network Diagnostics module not available.`n`nThis feature requires NetworkDiagnostics.ps1 to be loaded.",
                "Module Not Available",
                "OK",
                "Warning"
            )
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error running network diagnostics: $_", "Error", "OK", "Error")
        Update-StatusBar -Message "Network diagnostics failed" -HideProgress
    }
    })
}

$btnKeyboardSymbols = Get-Control -Name "BtnKeyboardSymbols"
if ($btnKeyboardSymbols) {
    $btnKeyboardSymbols.Add_Click({
    try {
        if (Get-Command Show-SymbolHelperGUI -ErrorAction SilentlyContinue) {
            Show-SymbolHelperGUI
        } elseif (Get-Command Show-SymbolHelper -ErrorAction SilentlyContinue) {
            # Fallback to console version
            Show-SymbolHelper
        } else {
            [System.Windows.MessageBox]::Show(
                "Keyboard Symbol Helper not available.`n`nThis feature requires KeyboardSymbols.ps1 to be loaded.",
                "Module Not Available",
                "OK",
                "Warning"
            )
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error launching keyboard symbol helper: $_", "Error", "OK", "Error")
    }
    })
}

$btnChatGPT = Get-Control -Name "BtnChatGPT"
if ($btnChatGPT) {
    $btnChatGPT.Add_Click({
    try {
        Update-StatusBar -Message "Opening ChatGPT help..." -ShowProgress
        $result = Open-ChatGPTHelp
        
        if ($result.Success) {
            Update-StatusBar -Message $result.Message -HideProgress
            [System.Windows.MessageBox]::Show($result.Message, "ChatGPT Help", "OK", "Information")
        } else {
            Update-StatusBar -Message "Browser not available" -HideProgress
            # Show instructions in a message box
            $instructionsWindow = New-Object System.Windows.Window
            $instructionsWindow.Title = "ChatGPT Help - Instructions"
            $instructionsWindow.Width = 600
            $instructionsWindow.Height = 500
            $instructionsWindow.WindowStartupLocation = "CenterScreen"
            
            $textBlock = New-Object System.Windows.Controls.TextBlock
            $textBlock.Text = $result.Instructions
            $textBlock.TextWrapping = "Wrap"
            $textBlock.Margin = "10"
            $textBlock.FontFamily = "Consolas"
            $textBlock.FontSize = "11"
            
            $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
            $scrollViewer.Content = $textBlock
            $scrollViewer.VerticalScrollBarVisibility = "Auto"
            
            $instructionsWindow.Content = $scrollViewer
            $instructionsWindow.ShowDialog() | Out-Null
        }
    } catch {
        Update-StatusBar -Message "Error opening ChatGPT: $_" -HideProgress
        [System.Windows.MessageBox]::Show("Error opening ChatGPT help: $_", "Error", "OK", "Error")
    }
    })
}

$btnSwitchToTUI = Get-Control -Name "BtnSwitchToTUI"
if ($btnSwitchToTUI) {
    $btnSwitchToTUI.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Switch to Command Line Mode (TUI)?`n`nThis will close the GUI and open the text-based interface.`n`nContinue?",
        "Switch to Command Line Mode",
        "YesNo",
        "Question"
    )
    
    if ($result -eq "Yes") {
        try {
            Update-StatusBar -Message "Switching to command line mode..." -ShowProgress
            $W.Close()
            
            # Load TUI module and start it
            $tuiPath = Join-Path $PSScriptRoot "WinRepairTUI.ps1"
            if (Test-Path $tuiPath) {
                . $tuiPath
                Start-TUI
            } else {
                Write-Host "Error: WinRepairTUI.ps1 not found at $tuiPath" -ForegroundColor Red
                Write-Host "Please run MiracleBoot.ps1 to access TUI mode." -ForegroundColor Yellow
            }
        } catch {
            [System.Windows.MessageBox]::Show(
                "Error switching to command line mode: $_`n`nYou can manually run MiracleBoot.ps1 to access TUI mode.",
                "Error",
                "OK",
                "Error"
            )
        }
    }
    })
}

# Interface Scale Controls
$interfaceScaleSlider = Get-Control -Name "InterfaceScaleSlider"
$scaleValueText = Get-Control -Name "ScaleValueText"
$btnResetScale = Get-Control -Name "BtnResetScale"

# Function to apply interface scale
function Set-InterfaceScale {
    param([double]$Scale)
    
    if ($Scale -lt 0.75 -or $Scale -gt 1.5) {
        return
    }
    
    try {
        # Apply scale to the main grid (window content) using LayoutTransform
        $mainGrid = $W.Content
        if ($mainGrid) {
            $mainGrid.LayoutTransform = [System.Windows.Media.ScaleTransform]::new($Scale, $Scale)
        }
        
        # Update scale value text
        if ($scaleValueText) {
            $scaleValueText.Text = "Current scale: $([math]::Round($Scale * 100))%"
        }
        
        # Save scale preference to registry
        try {
            $regPath = "HKCU:\Software\MiracleBoot"
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name "InterfaceScale" -Value $Scale -Type Double -ErrorAction SilentlyContinue
        } catch {
            # Silently fail if registry write fails
        }
    } catch {
        Write-Warning "Failed to apply interface scale: $_"
    }
}

# Load saved scale preference
$savedScale = 1.0
try {
    $regPath = "HKCU:\Software\MiracleBoot"
    if (Test-Path $regPath) {
        $saved = Get-ItemProperty -Path $regPath -Name "InterfaceScale" -ErrorAction SilentlyContinue
        if ($saved -and $saved.InterfaceScale -ge 0.75 -and $saved.InterfaceScale -le 1.5) {
            $savedScale = $saved.InterfaceScale
        }
    }
} catch {
    # Use default if registry read fails
}

if ($interfaceScaleSlider) {
    # Set initial value from saved preference
    $interfaceScaleSlider.Value = $savedScale
    Set-InterfaceScale -Scale $savedScale
    
    # Handle slider value change
    $interfaceScaleSlider.Add_ValueChanged({
        $newScale = $interfaceScaleSlider.Value
        Set-InterfaceScale -Scale $newScale
    })
} else {
    Write-Warning "InterfaceScaleSlider control not found in XAML"
}

if ($btnResetScale) {
    $btnResetScale.Add_Click({
        try {
            $defaultScale = 1.0
            if ($interfaceScaleSlider) {
                $interfaceScaleSlider.Value = $defaultScale
            }
            Set-InterfaceScale -Scale $defaultScale
        } catch {
            [System.Windows.MessageBox]::Show("Failed to reset interface scale: $_", "Error", "OK", "Error")
        }
    })
} else {
    Write-Warning "BtnResetScale control not found in XAML"
}

# Initialize network status (with improved detection)
try {
    $networkStatusControl = Get-Control "NetworkStatus"
    if ($networkStatusControl) {
        try {
            # Step 1: Check if network adapters exist (even if not connected)
            $adaptersAvailable = $false
            $adaptersConnected = $false
            $hasInternet = $false
            
            # Try multiple methods to detect network adapters
            try {
                $netAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Hidden' })
                if ((Get-SafeCount $netAdapters) -gt 0) {
                    $adaptersAvailable = $true
                    $connectedAdapters = @($netAdapters | Where-Object { $_.Status -eq 'Up' -or $_.Status -eq 'Connected' })
                    if ((Get-SafeCount $connectedAdapters) -gt 0) {
                        $adaptersConnected = $true
                    }
                }
            } catch {
                # Fallback: Check with netsh
                try {
                    $netshOutput = netsh interface show interface 2>&1
                    if ($netshOutput -match 'connected|disconnected|enabled|disabled') {
                        $adaptersAvailable = $true
                        if ($netshOutput -match 'connected') {
                            $adaptersConnected = $true
                        }
                    }
                } catch {
                    # Try Get-NetworkAdapterStatus if NetworkDiagnostics is loaded
                    if (Get-Command Get-NetworkAdapterStatus -ErrorAction SilentlyContinue) {
                        try {
                            $adapterStatus = @(Get-NetworkAdapterStatus -ErrorAction SilentlyContinue)
                            if ((Get-SafeCount $adapterStatus) -gt 0) {
                                $adaptersAvailable = $true
                                $connectedAdapters = @($adapterStatus | Where-Object { $_.Connected -eq $true })
                                if ((Get-SafeCount $connectedAdapters) -gt 0) {
                                    $adaptersConnected = $true
                                }
                            }
                        } catch {
                            # Continue with other checks
                        }
                    }
                }
            }
            
            # Step 2: If adapters are connected, test internet connectivity
            if ($adaptersConnected) {
                try {
                    $internetTest = Test-InternetConnectivity -TimeoutSeconds 3 -ErrorAction SilentlyContinue
                    if ($internetTest -and $internetTest.Connected) {
                        $hasInternet = $true
                    }
                } catch {
                    # Internet test failed, but adapter is connected
                }
            }
            
            # Step 3: Set status based on findings
            if ($hasInternet) {
                $networkStatusControl.Text = "Network: Connected"
                $networkStatusControl.Foreground = "Green"
            } elseif ($adaptersConnected) {
                $networkStatusControl.Text = "Network: Connected (No Internet)"
                $networkStatusControl.Foreground = "Orange"
            } elseif ($adaptersAvailable) {
                $networkStatusControl.Text = "Network: Available"
                $networkStatusControl.Foreground = "Yellow"
            } else {
                $networkStatusControl.Text = "Network: Not Found"
                $networkStatusControl.Foreground = "Gray"
            }
        } catch {
            $networkStatusControl.Text = "Network: Unknown"
            $networkStatusControl.Foreground = "Gray"
        }
    } else {
        Write-Warning "NetworkStatus control not found in XAML"
    }
} catch {
    Write-Warning "Error initializing network status: $_"
}

# Populate drive combo (with null checks)
try {
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemLabel } | Sort-Object DriveLetter
    $driveCombo = Get-Control "DriveCombo"
    if ($driveCombo) {
        $driveCombo.Items.Clear()
        $driveCombo.Items.Add("Auto-detect")
        foreach ($vol in $volumes) {
            $driveCombo.Items.Add("$($vol.DriveLetter): - $($vol.FileSystemLabel)")
        }
        $driveCombo.SelectedIndex = 0
    }
    
    # Populate log drive combo (for Diagnostics & Logs tab)
    $logDriveCombo = Get-Control "LogDriveCombo"
    if ($logDriveCombo) {
        $logDriveCombo.Items.Clear()
        $logDriveCombo.Items.Add("C:")
        foreach ($vol in $volumes) {
            if ($vol.DriveLetter -ne "C") {
                $logDriveCombo.Items.Add("$($vol.DriveLetter):")
            }
        }
        $logDriveCombo.SelectedIndex = 0
    }
    
    # Populate Diagnostics drive combo
    $currentSystemDrive = $env:SystemDrive.TrimEnd(':')
    $diagDriveCombo = Get-Control "DiagDriveCombo"
    if ($diagDriveCombo) {
        $diagDriveCombo.Items.Clear()
        $diagDriveCombo.Items.Add("$currentSystemDrive`: (Current OS)")
        foreach ($vol in $volumes) {
            if ($vol.DriveLetter -ne $currentSystemDrive) {
                $diagDriveCombo.Items.Add("$($vol.DriveLetter):")
            }
        }
        $diagDriveCombo.SelectedIndex = 0
    }
    
    # Populate Summary drive combo
    $summaryDriveCombo = Get-Control "SummaryDriveCombo"
    if ($summaryDriveCombo) {
        $summaryDriveCombo.Items.Clear()
        $summaryDriveCombo.Items.Add("$currentSystemDrive`: (Current OS)")
        foreach ($vol in $volumes) {
            if ($vol.DriveLetter -ne $currentSystemDrive) {
                $summaryDriveCombo.Items.Add("$($vol.DriveLetter):")
            }
        }
        $summaryDriveCombo.SelectedIndex = 0
    }
    
    # Update current OS label
    function Update-CurrentOSLabel {
        try {
            $diagDriveCombo = Get-Control "DiagDriveCombo"
            if ($diagDriveCombo -and $diagDriveCombo.SelectedItem) {
                $selected = $diagDriveCombo.SelectedItem
                $drive = $currentSystemDrive
                if ($selected) {
                    if ($selected -match '^([A-Z]):') {
                        $drive = $matches[1]
                    }
                }
                $currentOSLabel = Get-Control "CurrentOSLabel"
                if ($currentOSLabel) {
                    if ($drive -eq $currentSystemDrive) {
                        $currentOSLabel.Text = "[OK] This is the CURRENT OS (running from $currentSystemDrive`:)"
                    } else {
                        $currentOSLabel.Text = "[OFFLINE] This is an OFFLINE OS (not currently running)"
                    }
                }
            }
        } catch {
            Write-Warning "Error in Update-CurrentOSLabel: $_"
        }
    }
    Update-CurrentOSLabel
    if ($diagDriveCombo) {
        $diagDriveCombo.Add_SelectionChanged({ Update-CurrentOSLabel })
    }
    
    # Logic for Volumes
    $btnVol = Get-Control "BtnVol"
    if ($btnVol) {
        $btnVol.Add_Click({
            $vols = Get-WindowsVolumes
            $volList = Get-Control "VolList"
            if ($volList) {
                $volList.ItemsSource = $vols
            }
        })
    }
    
    # Logic for Summary Tab
    $btnRefreshSummary = Get-Control "BtnRefreshSummary"
    if ($btnRefreshSummary) {
        $btnRefreshSummary.Add_Click({
            try {
                Update-StatusBar -Message "Analyzing boot health and Windows Update eligibility..." -ShowProgress
                
                # Get selected drive
                $summaryDriveCombo = Get-Control "SummaryDriveCombo"
                $selectedDrive = $currentSystemDrive
                if ($summaryDriveCombo -and $summaryDriveCombo.SelectedItem) {
                    $selected = $summaryDriveCombo.SelectedItem
                    if ($selected -match '^([A-Z]):') {
                        $selectedDrive = $matches[1]
                    }
                }
                
                # Get Boot Health Summary
                $bootHealthStatus = Get-Control "BootHealthStatus"
                $bootHealthBox = Get-Control "BootHealthBox"
                if ($bootHealthStatus) {
                    $bootHealthStatus.Text = "Analyzing boot health for drive $selectedDrive`:..."
                }
                
                $bootHealth = Get-BootHealthSummary -TargetDrive $selectedDrive
                
                if ($bootHealthBox) {
                    $bootHealthBox.Text = $bootHealth.Report
                }
                if ($bootHealthStatus) {
                    $statusText = "Boot Health Score: $($bootHealth.BootHealthScore)/$($bootHealth.MaxScore) - Status: $($bootHealth.OverallStatus)"
                    $bootHealthStatus.Text = $statusText
                    if ($bootHealth.BootHealthScore -ge 80) {
                        $bootHealthStatus.Foreground = "Green"
                    } elseif ($bootHealth.BootHealthScore -ge 60) {
                        $bootHealthStatus.Foreground = "Orange"
                    } else {
                        $bootHealthStatus.Foreground = "Red"
                    }
                }
                
                # Get Windows Update Eligibility
                $updateEligibilityStatus = Get-Control "UpdateEligibilityStatus"
                $updateEligibilityBox = Get-Control "UpdateEligibilityBox"
                if ($updateEligibilityStatus) {
                    $updateEligibilityStatus.Text = "Checking Windows Update eligibility for drive $selectedDrive`:..."
                }
                
                $updateEligibility = Get-WindowsUpdateEligibility -TargetDrive $selectedDrive
                
                if ($updateEligibilityBox) {
                    $updateEligibilityBox.Text = $updateEligibility.Report
                }
                if ($updateEligibilityStatus) {
                    $statusText = "Readiness Score: $($updateEligibility.ReadinessScore)/$($updateEligibility.MaxScore) - Status: $($updateEligibility.Status)"
                    $updateEligibilityStatus.Text = $statusText
                    if ($updateEligibility.ReadinessScore -ge 80 -and (Get-SafeCount $updateEligibility.Blockers) -eq 0) {
                        $updateEligibilityStatus.Foreground = "Green"
                    } elseif ($updateEligibility.ReadinessScore -ge 60) {
                        $updateEligibilityStatus.Foreground = "Orange"
                    } else {
                        $updateEligibilityStatus.Foreground = "Red"
                    }
                }
                
                Update-StatusBar -Message "Summary analysis complete" -HideProgress
            } catch {
                Update-StatusBar -Message "Error analyzing summary: $_" -HideProgress
                [System.Windows.MessageBox]::Show("Error analyzing summary: $_", "Error", "OK", "Error")
            }
        })
    }
} catch {
    Write-Warning "Error initializing drive combo boxes: $_"
}

# Store BCD entries globally for real-time updates
$script:BCDEntriesCache = $null

# Helper function to update status bar with enhanced progress tracking
# Global status bar state for elapsed time tracking
$script:StatusBarStartTime = $null
$script:StatusBarElapsedTimer = $null

function Update-StatusBar {
    param(
        [string]$Message = "Ready",
        [switch]$ShowProgress,
        [switch]$HideProgress,
        [int]$Percentage = -1,
        [string]$Stage = "",
        [string]$CurrentOperation = "",
        [Nullable[TimeSpan]]$EstimatedTimeRemaining = $null
    )
    
    # Start elapsed time tracking when progress begins
    if ($ShowProgress -and -not $script:StatusBarStartTime) {
        $script:StatusBarStartTime = Get-Date
        # Clear any existing timer
        if ($script:StatusBarElapsedTimer) {
            $script:StatusBarElapsedTimer.Stop()
            # DispatcherTimer doesn't have Dispose() - just stop and null it
            $script:StatusBarElapsedTimer = $null
        }
        # Create timer for periodic updates
        $script:StatusBarElapsedTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:StatusBarElapsedTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:StatusBarElapsedTimer.Add_Tick({
            if ($script:StatusBarStartTime -and $W) {
                $elapsed = (Get-Date) - $script:StatusBarStartTime
                $minutes = [math]::Floor($elapsed.TotalMinutes)
                $seconds = [math]::Floor($elapsed.TotalSeconds % 60)
                $W.Dispatcher.Invoke([action]{
                    $statusBarControl = Get-Control "StatusBarText"
                    if ($statusBarControl) {
                        $currentText = $statusBarControl.Text
                        # Update elapsed time if message hasn't changed
                        if ($currentText -match "Elapsed:") {
                            $statusBarControl.Text = $currentText -replace "Elapsed: \d+m \d+s", "Elapsed: ${minutes}m ${seconds}s"
                        } elseif ($currentText -notmatch "Elapsed:") {
                            $statusBarControl.Text = "$currentText | Elapsed: ${minutes}m ${seconds}s"
                        }
                    }
                }, [System.Windows.Threading.DispatcherPriority]::Background)
            }
        })
        $script:StatusBarElapsedTimer.Start()
    }
    
    # Stop elapsed time tracking when progress ends
    if ($HideProgress) {
        if ($script:StatusBarElapsedTimer) {
            $script:StatusBarElapsedTimer.Stop()
            # DispatcherTimer doesn't have Dispose() - just stop and null it
            $script:StatusBarElapsedTimer = $null
        }
        $script:StatusBarStartTime = $null
    }
    
    # Use dispatcher to ensure UI updates on UI thread
    $W.Dispatcher.Invoke([action]{
        $statusBarControl = Get-Control "StatusBarText"
        if ($statusBarControl) {
            # Add elapsed time if progress is active
            if ($ShowProgress -and $script:StatusBarStartTime) {
                $elapsed = (Get-Date) - $script:StatusBarStartTime
                $minutes = [math]::Floor($elapsed.TotalMinutes)
                $seconds = [math]::Floor($elapsed.TotalSeconds % 60)
                $statusBarControl.Text = "$Message | Elapsed: ${minutes}m ${seconds}s"
            } else {
                $statusBarControl.Text = $Message
            }
        }
        
        $progressBar = Get-Control "StatusBarProgressBar"
        $progressText = Get-Control "StatusBarProgress"
        
        if ($ShowProgress -and $progressBar -and $progressText) {
            $progressBar.Visibility = "Visible"
            
            # If percentage is provided, use determinate progress bar
            if ($Percentage -ge 0) {
                $progressBar.IsIndeterminate = $false
                $progressBar.Value = $Percentage
                $progressBar.Maximum = 100
                
                # Build progress text
                $progressTextParts = @()
                if ($Percentage -ge 0) {
                    $progressTextParts += "$Percentage%"
                }
                if ($Stage) {
                    $progressTextParts += "($Stage)"
                }
                if ($CurrentOperation) {
                    $progressTextParts += "- $CurrentOperation"
                }
                if ($EstimatedTimeRemaining -and $EstimatedTimeRemaining.TotalSeconds -gt 0) {
                    $minutes = [math]::Floor($EstimatedTimeRemaining.TotalMinutes)
                    $seconds = [math]::Floor($EstimatedTimeRemaining.TotalSeconds % 60)
                    if ($minutes -gt 0) {
                        $progressTextParts += "~${minutes}m ${seconds}s remaining"
                    } else {
                        $progressTextParts += "~${seconds}s remaining"
                    }
                }
                
                if ($progressText) {
                    $progressText.Text = $progressTextParts -join " "
                }
            } else {
                # No percentage available, use indeterminate progress bar
                if ($progressBar) {
                    $progressBar.IsIndeterminate = $true
                }
                if ($progressText) {
                    $progressText.Text = "Working..."
                }
            }
        } elseif ($HideProgress -and $progressBar -and $progressText) {
            $progressBar.Visibility = "Collapsed"
            $progressBar.IsIndeterminate = $true
            $progressBar.Value = 0
            $progressText.Text = ""
        }
    }, [System.Windows.Threading.DispatcherPriority]::Render)
    
    # Force UI update
    [System.Windows.Forms.Application]::DoEvents()
}

# Helper function to wrap long operations with heartbeat updates
function Start-OperationWithHeartbeat {
    <#
    .SYNOPSIS
        Wraps a long-running operation with periodic heartbeat updates to prevent UI from appearing frozen.
    
    .DESCRIPTION
        Executes a scriptblock in a background runspace and provides periodic "Still working..." updates
        every few seconds to keep the UI responsive and inform users the operation is still running.
    
    .PARAMETER ScriptBlock
        The operation to execute
    
    .PARAMETER OperationName
        Display name for the operation
    
    .PARAMETER HeartbeatInterval
        Seconds between heartbeat updates (default: 5)
    
    .EXAMPLE
        Start-OperationWithHeartbeat -ScriptBlock { Start-Sleep -Seconds 30 } -OperationName "Disk Check"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory=$true)]
        [string]$OperationName,
        
        [int]$HeartbeatInterval = 5
    )
    
    $startTime = Get-Date
    $lastHeartbeat = Get-Date
    
    # Create runspace for background execution
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()
    
    # Create PowerShell instance
    $psInstance = [PowerShell]::Create()
    $psInstance.Runspace = $runspace
    
    # Add the scriptblock
    $null = $psInstance.AddScript($ScriptBlock)
    
    # Start operation asynchronously
    $asyncResult = $psInstance.BeginInvoke()
    
    # Monitor and provide heartbeat updates
    while (-not $asyncResult.IsCompleted) {
        Start-Sleep -Milliseconds 500
        
        $elapsed = (Get-Date) - $startTime
        $minutes = [math]::Floor($elapsed.TotalMinutes)
        $seconds = [math]::Floor($elapsed.TotalSeconds % 60)
        
        # Send heartbeat every N seconds
        if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge $HeartbeatInterval) {
            $heartbeatMsg = "Still working on: $OperationName... (${minutes}m ${seconds}s elapsed)"
            $W.Dispatcher.Invoke([action]{
                Update-StatusBar -Message $heartbeatMsg -ShowProgress
            }, [System.Windows.Threading.DispatcherPriority]::Background)
            $lastHeartbeat = Get-Date
        }
        
        # Allow UI to process events
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    # Get result
    $result = $psInstance.EndInvoke($asyncResult)
    
    # Cleanup
    $psInstance.Dispose()
    $runspace.Close()
    $runspace.Dispose()
    
    return $result
}

# Helper function to create progress callback for repair operations
function New-ProgressCallback {
    <#
    .SYNOPSIS
    Creates a progress callback scriptblock that updates the GUI status bar with progress information.
    
    .DESCRIPTION
    Returns a scriptblock that can be passed to repair functions like Start-SystemFileRepair,
    Start-DiskRepair, etc. The callback receives a progress object with Percentage, Stage,
    CurrentOperation, and EstimatedTimeRemaining properties.
    #>
    param(
        [string]$OperationName = "Operation"
    )
    
    return {
        param($progress)
        
        # Handle both progress object format and simple string messages
        if ($progress -is [hashtable] -or $progress -is [PSCustomObject]) {
            $percentage = if ($progress.Percentage) { $progress.Percentage } else { -1 }
            $stage = if ($progress.Stage) { $progress.Stage } else { "" }
            $currentOp = if ($progress.CurrentOperation) { $progress.CurrentOperation } else { "" }
            $estimatedTime = if ($progress.EstimatedTimeRemaining) { $progress.EstimatedTimeRemaining } else { $null }
            
            $message = if ($progress.CurrentOperation) {
                "${OperationName}: $($progress.CurrentOperation)"
            } else {
                "${OperationName}: $($progress.Stage)"
            }
            
            if ($percentage -ge 0) {
                Update-StatusBar -Message $message -ShowProgress -Percentage $percentage -Stage $stage -CurrentOperation $currentOp -EstimatedTimeRemaining $estimatedTime
            } else {
                Update-StatusBar -Message $message -ShowProgress -Stage $stage -CurrentOperation $currentOp
            }
        } else {
            # Simple string message
            Update-StatusBar -Message "${OperationName}: $progress" -ShowProgress
        }
    }
}

# Helper function to get default boot entry GUID
function Get-BCDDefaultEntryId {
    try {
        # First check if BCD file exists physically (faster than bcdedit)
        $bcdFilePaths = @(
            "$env:SystemRoot\Boot\BCD",
            "$env:SystemDrive\Boot\BCD",
            "$env:SystemRoot\EFI\Microsoft\Boot\BCD"
        )
        
        $bcdFileExists = $false
        foreach ($bcdPath in $bcdFilePaths) {
            if (Test-Path $bcdPath -ErrorAction SilentlyContinue) {
                $bcdFileExists = $true
                break
            }
        }
        
        if (-not $bcdFileExists) {
            # BCD file doesn't exist - try to recreate it
            Write-Warning "BCD file is missing, attempting to recreate..."
            $bcdCheck = Test-AndRecreateBCD -WriteLogFunction { param($msg) Write-Warning $msg } -TimeoutSeconds 10
            if (-not $bcdCheck.Success) {
                return $null
            }
            # Wait for BCD to be available after recreation
            Start-Sleep -Seconds 2
        }
        
        # Check BCD accessibility with timeout (10 seconds)
        $bcdTest = $null
        $bcdJob = Start-Job -ScriptBlock {
            bcdedit /enum "{bootmgr}" 2>&1 | Out-String
        }
        
        $bcdTest = Wait-Job -Job $bcdJob -Timeout 10 | Receive-Job
        Stop-Job -Job $bcdJob -ErrorAction SilentlyContinue
        Remove-Job -Job $bcdJob -ErrorAction SilentlyContinue
        
        if ($null -eq $bcdTest -or $bcdTest -match "could not be opened|The system cannot find") {
            return $null
        }
        
        # Get the default entry from Windows Boot Manager (with timeout)
        $bootMgrOutput = $null
        $bootMgrJob = Start-Job -ScriptBlock {
            bcdedit /enum "{bootmgr}" 2>&1
        }
        
        $bootMgrOutput = Wait-Job -Job $bootMgrJob -Timeout 10 | Receive-Job
        Stop-Job -Job $bootMgrJob -ErrorAction SilentlyContinue
        Remove-Job -Job $bootMgrJob -ErrorAction SilentlyContinue
        
        if ($bootMgrOutput -and $bootMgrOutput -match 'default\s+(\{[0-9A-F-]+\})') {
            return $matches[1]
        }
        
        # Alternative: check for {default} identifier directly in enum output (with timeout)
        $enumOutput = $null
        $enumJob = Start-Job -ScriptBlock {
            bcdedit /enum 2>&1
        }
        
        $enumOutput = Wait-Job -Job $enumJob -Timeout 10 | Receive-Job
        Stop-Job -Job $enumJob -ErrorAction SilentlyContinue
        Remove-Job -Job $enumJob -ErrorAction SilentlyContinue
        
        if ($enumOutput -and $enumOutput -match 'identifier\s+(\{default\})') {
            return "{default}"
        }
        return $null
    } catch {
        return $null
    }
}

# Logic for BCD - Enhanced parser with duplicate detection
$btnBCD = Get-Control "BtnBCD"
if ($btnBCD) {
    $btnBCD.Add_Click({
        try {
            # Check for administrator privileges first
            $isAdmin = $false
            try {
                $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            } catch {
                # If we can't check, assume not admin and let bcdedit fail gracefully
                $isAdmin = $false
            }
            
            if (-not $isAdmin) {
                $result = [System.Windows.MessageBox]::Show(
                    "BCD operations require administrator privileges.`n`n" +
                    "Current session is NOT running as Administrator.`n`n" +
                    "To fix this:`n" +
                    "1. Close Miracle Boot`n" +
                    "2. Right-click PowerShell or the shortcut`n" +
                    "3. Select 'Run as Administrator'`n" +
                    "4. Launch Miracle Boot again`n`n" +
                    "Would you like to see instructions for running as Administrator?",
                    "Administrator Privileges Required",
                    "YesNo",
                    "Warning"
                )
                if ($result -eq "Yes") {
                    $instructions = @"
HOW TO RUN MIRACLE BOOT AS ADMINISTRATOR
========================================

Method 1: From PowerShell
--------------------------
1. Close this application
2. Open PowerShell as Administrator:
   - Press Windows Key + X
   - Select 'Windows PowerShell (Admin)' or 'Terminal (Admin)'
3. Navigate to the Miracle Boot folder
4. Run: .\MiracleBoot.ps1

Method 2: From File Explorer
------------------------------
1. Close this application
2. Navigate to the Miracle Boot folder in File Explorer
3. Right-click on 'RunMiracleBoot.cmd' or 'MiracleBoot.ps1'
4. Select 'Run as Administrator'
5. Click 'Yes' on the UAC prompt

Method 3: Create a Shortcut
----------------------------
1. Right-click on 'RunMiracleBoot.cmd'
2. Select 'Create Shortcut'
3. Right-click the shortcut and select 'Properties'
4. Click 'Advanced' button
5. Check 'Run as administrator'
6. Click OK twice
7. Use this shortcut to launch Miracle Boot

NOTE: BCD (Boot Configuration Data) operations require administrator
privileges because they modify critical boot settings that affect system startup.
"@
                    $instructionsWindow = New-Object System.Windows.Window
                    $instructionsWindow.Title = "Run as Administrator - Instructions"
                    $instructionsWindow.Width = 600
                    $instructionsWindow.Height = 500
                    $instructionsWindow.WindowStartupLocation = "CenterScreen"
                    
                    $textBlock = New-Object System.Windows.Controls.TextBlock
                    $textBlock.Text = $instructions
                    $textBlock.TextWrapping = "Wrap"
                    $textBlock.Margin = "10"
                    $textBlock.FontFamily = "Consolas"
                    $textBlock.FontSize = "11"
                    
                    $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
                    $scrollViewer.Content = $textBlock
                    $scrollViewer.VerticalScrollBarVisibility = "Auto"
                    
                    $instructionsWindow.Content = $scrollViewer
                    $instructionsWindow.ShowDialog() | Out-Null
                }
                Update-StatusBar -Message "BCD operation requires administrator privileges" -HideProgress
                return
            }
            
            # Force UI update immediately
            $W.Dispatcher.Invoke([action]{
                Update-StatusBar -Message "Loading BCD Entries..." -ShowProgress
            }, [System.Windows.Threading.DispatcherPriority]::Render)
            [System.Windows.Forms.Application]::DoEvents()
            
            # Try to get raw BCD output with error handling
            try {
                # First check if BCD exists and recreate if missing
                $bcdCheckResult = Test-AndRecreateBCD -WriteLogFunction { param($msg) Write-Host $msg }
                if (-not $bcdCheckResult.Success) {
                    $result = [System.Windows.MessageBox]::Show(
                        "BCD file is missing or corrupted.`n`n" +
                        "Attempted to recreate but failed: $($bcdCheckResult.Message)`n`n" +
                        "Would you like to try manual recovery?",
                        "BCD Missing",
                        "YesNo",
                        "Warning"
                    )
                    if ($result -eq "No") {
                        return
                    }
                }
                
                $rawBcd = bcdedit /enum 2>&1
                # Check for access denied in output
                if ($rawBcd -match "access is denied|Access is denied") {
                    throw "Access Denied: The boot configuration data store could not be opened.`n`nThis operation requires administrator privileges."
                }
                # Check for missing BCD file
                if ($rawBcd -match "could not be opened|The system cannot find|The system cannot find the path") {
                    $result = [System.Windows.MessageBox]::Show(
                        "BCD file is missing or corrupted.`n`n" +
                        "Would you like to recreate it using bcdboot?`n`n" +
                        "This requires the Windows installation drive and EFI partition to be accessible.",
                        "BCD Missing",
                        "YesNo",
                        "Warning"
                    )
                    if ($result -eq "Yes") {
                        # Try to recreate BCD
                        $bcdCheckResult = Test-AndRecreateBCD -WriteLogFunction { param($msg) Write-Host $msg }
                        if ($bcdCheckResult.Success) {
                            [System.Windows.MessageBox]::Show(
                                "BCD recreated successfully.`n`n" +
                                "Please click 'Load/Refresh BCD' again to view entries.",
                                "BCD Recreated",
                                "OK",
                                "Information"
                            )
                            return
                        } else {
                            [System.Windows.MessageBox]::Show(
                                "Failed to recreate BCD: $($bcdCheckResult.Message)`n`n" +
                                "Please ensure you are running from WinRE/WinPE or have access to the EFI partition.",
                                "BCD Recreation Failed",
                                "OK",
                                "Error"
                            )
                            return
                        }
                    } else {
                        return
                    }
                }
                $bcdBox = Get-Control "BCDBox"
                if ($bcdBox) {
                    $bcdBox.Text = $rawBcd
                }
            } catch {
                Update-StatusBar -Message "Error accessing BCD: $_" -HideProgress
                [System.Windows.MessageBox]::Show(
                    "Error accessing BCD: $_`n`n" +
                    "Please ensure you are running as Administrator.",
                    "BCD Access Error",
                    "OK",
                    "Error"
                )
                return
            }
            
            $W.Dispatcher.Invoke([action]{
                Update-StatusBar -Message "Parsing BCD entries..." -ShowProgress
            }, [System.Windows.Threading.DispatcherPriority]::Render)
            [System.Windows.Forms.Application]::DoEvents()
            
            # Get default boot entry ID
            $defaultEntryId = Get-BCDDefaultEntryId
            
            # Parse BCD entries with full properties
            $entries = Get-BCDEntriesParsed
            $script:BCDEntriesCache = $entries
            
            $W.Dispatcher.Invoke([action]{
                Update-StatusBar -Message "Processing boot entries..." -ShowProgress
            }, [System.Windows.Threading.DispatcherPriority]::Render)
            [System.Windows.Forms.Application]::DoEvents()
            
            $bcdItems = @()
            foreach ($entry in $entries) {
                $displayText = if ($entry.Description) { $entry.Description } else { $entry.Id }
                
                # Mark default entry
                $isDefault = $false
                if ($defaultEntryId) {
                    # Check if this entry's ID matches the default (handle both GUID and {default})
                    if ($entry.Id -eq $defaultEntryId -or 
                        ($defaultEntryId -eq "{default}" -and $entry.Id -match '\{default\}')) {
                        $isDefault = $true
                        $displayText = "[DEFAULT] $displayText"
                    }
                }
                
                $bcdItems += [PSCustomObject]@{
                    Id = $entry.Id
                    Description = $entry.Description
                    DisplayText = $displayText
                    Device = $entry.Device
                    Path = $entry.Path
                    EntryObject = $entry
                    IsDefault = $isDefault
                }
            }
            
            $W.Dispatcher.Invoke([action]{
                Update-StatusBar -Message "Updating BCD list..." -ShowProgress
            }, [System.Windows.Threading.DispatcherPriority]::Render)
            [System.Windows.Forms.Application]::DoEvents()
            
            $bcdList = Get-Control "BCDList"
            if ($bcdList) {
                $bcdList.ItemsSource = $bcdItems
            }
            
            # Update Simulator in real-time
            Update-BootMenuSimulator $bcdItems
            
            $timeout = Get-BCDTimeout
            $txtTimeout = Get-Control "TxtTimeout"
            $simTimeout = Get-Control "SimTimeout"
            if ($txtTimeout) { $txtTimeout.Text = $timeout }
            if ($simTimeout) { $simTimeout.Text = "Seconds until auto-start: $timeout" }
            
            $W.Dispatcher.Invoke([action]{
                Update-StatusBar -Message "Checking for duplicate entries..." -ShowProgress
            }, [System.Windows.Threading.DispatcherPriority]::Render)
            [System.Windows.Forms.Application]::DoEvents()
            
            # Check for duplicates
            $duplicates = Find-DuplicateBCEEntries
            if ($duplicates) {
                $dupNames = ($duplicates | ForEach-Object { "'$($_.Name)'" }) -join ", "
                $result = [System.Windows.MessageBox]::Show(
                    "Found duplicate boot entry names: $dupNames`n`nWould you like to automatically rename them by appending volume labels?",
                    "Duplicate Entries Detected",
                    "YesNo",
                    "Question"
                )
                if ($result -eq "Yes") {
                    $fixed = Fix-DuplicateBCEEntries -AppendVolumeLabels
                    if ((Get-SafeCount $fixed) -gt 0) {
                        [System.Windows.MessageBox]::Show("Fixed $(Get-SafeCount $fixed) duplicate entry name(s).", "Success", "OK", "Information")
                        # Reload BCD
                        $btnBCD.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                        return
                    }
                }
            }
            
            $defaultCount = ($bcdItems | Where-Object { $_.IsDefault }).Count
            $statusMsg = "Loaded $($bcdItems.Count) BCD entries"
            if ($defaultCount -gt 0) {
                $statusMsg += " (1 default entry marked)"
            }
            Update-StatusBar -Message $statusMsg -HideProgress
            
            if (-not $duplicates) {
                [System.Windows.MessageBox]::Show("Loaded $($bcdItems.Count) BCD entries." + $(if ($defaultCount -gt 0) { "`n`nDefault boot entry is marked with [DEFAULT]." } else { "" }), "Success", "OK", "Information")
            }
        } catch {
            Update-StatusBar -Message "Error loading BCD: $_" -HideProgress
            
            # Enhanced error message for access denied
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "access is denied|Access is denied|could not be opened|Access Denied") {
                $result = [System.Windows.MessageBox]::Show(
                    "BCD Access Denied: The boot configuration data store could not be opened.`n`n" +
                    "This operation requires administrator privileges.`n`n" +
                    "Please run Miracle Boot as Administrator.`n`n" +
                    "Would you like to see instructions?",
                    "Administrator Privileges Required",
                    "YesNo",
                    "Warning"
                )
                if ($result -eq "Yes") {
                    $instructions = @"
HOW TO RUN MIRACLE BOOT AS ADMINISTRATOR
========================================

Method 1: From PowerShell
--------------------------
1. Close this application
2. Open PowerShell as Administrator:
   - Press Windows Key + X
   - Select 'Windows PowerShell (Admin)' or 'Terminal (Admin)'
3. Navigate to the Miracle Boot folder
4. Run: .\MiracleBoot.ps1

Method 2: From File Explorer
------------------------------
1. Close this application
2. Navigate to the Miracle Boot folder in File Explorer
3. Right-click on 'RunMiracleBoot.cmd' or 'MiracleBoot.ps1'
4. Select 'Run as Administrator'
5. Click 'Yes' on the UAC prompt

NOTE: BCD operations require administrator privileges because they
modify critical boot settings that affect system startup.
"@
                    $instructionsWindow = New-Object System.Windows.Window
                    $instructionsWindow.Title = "Run as Administrator - Instructions"
                    $instructionsWindow.Width = 600
                    $instructionsWindow.Height = 450
                    $instructionsWindow.WindowStartupLocation = "CenterScreen"
                    
                    $textBlock = New-Object System.Windows.Controls.TextBlock
                    $textBlock.Text = $instructions
                    $textBlock.TextWrapping = "Wrap"
                    $textBlock.Margin = "10"
                    $textBlock.FontFamily = "Consolas"
                    $textBlock.FontSize = "11"
                    
                    $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
                    $scrollViewer.Content = $textBlock
                    $scrollViewer.VerticalScrollBarVisibility = "Auto"
                    
                    $instructionsWindow.Content = $scrollViewer
                    $instructionsWindow.ShowDialog() | Out-Null
                }
            } else {
                [System.Windows.MessageBox]::Show("Error loading BCD: $errorMsg", "Error", "OK", "Error")
            }
        }
    })
} else {
    Write-Warning "BtnBCD control not found in XAML"
}

# Helper function to update Boot Menu Simulator
function Update-BootMenuSimulator {
    param($Items)
    $simListControl = Get-Control "SimList"
    if ($simListControl) {
        $simListControl.Items.Clear()
        foreach ($item in $Items) {
            if ($item.Description) {
                $simListControl.Items.Add($item.Description)
            }
        }
    }
}

# BCD List selection - populate both basic and advanced editors
$bcdListControl = Get-Control "BCDList"
if ($bcdListControl) {
    $bcdListControl.Add_SelectionChanged({
        $selected = $bcdListControl.SelectedItem
        if ($selected) {
            $editIdControl = Get-Control "EditId"
            $editDescControl = Get-Control "EditDescription"
            $editNameControl = Get-Control "EditName"
            
            if ($editIdControl) { $editIdControl.Text = $selected.Id }
            if ($editDescControl) { $editDescControl.Text = $selected.Description }
            if ($editNameControl) { $editNameControl.Text = $selected.Description }
            
            # Populate Advanced Properties Grid
            if ($selected.EntryObject) {
                $properties = @()
                foreach ($key in $selected.EntryObject.Keys) {
                    if ($key -ne 'Id' -and $key -ne 'EntryType') {
                        $properties += [PSCustomObject]@{
                            Name = $key
                            Value = $selected.EntryObject[$key]
                        }
                    }
                }
                $propsGridControl = Get-Control "BCDPropertiesGrid"
                if ($propsGridControl) {
                    $propsGridControl.ItemsSource = $properties
                }
            }
        }
    })
}

# BCD Backup button
$btnBCDBackup = Get-Control -Name "BtnBCDBackup"
if ($btnBCDBackup) {
    $btnBCDBackup.Add_Click({
        try {
            $backup = Export-BCDBackup
            if ($backup.Success) {
                [System.Windows.MessageBox]::Show("BCD backup created successfully!`n`nLocation: $($backup.Path)", "Backup Complete", "OK", "Information")
            } else {
                [System.Windows.MessageBox]::Show("Failed to create backup: $($backup.Error)", "Error", "OK", "Error")
            }
        } catch {
            [System.Windows.MessageBox]::Show("Error creating backup: $_", "Error", "OK", "Error")
        }
    })
}

# Fix Duplicates button
$btnFixDuplicates = Get-Control -Name "BtnFixDuplicates"
if ($btnFixDuplicates) {
    $btnFixDuplicates.Add_Click({
    $duplicates = Find-DuplicateBCEEntries
    if ($duplicates -and (Get-SafeCount $duplicates) -gt 0) {
        $dupList = ""
        foreach ($dup in $duplicates) {
            $dupList += "`n- '$($dup.Name)' (appears $($dup.Count) times)"
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Found duplicate boot entry names:$dupList`n`nHow would you like to fix them?`n`nYes = Append Volume Labels (Recommended)`nNo = Append Entry Numbers`nCancel = Skip",
            "Fix Duplicate Entries",
            "YesNoCancel",
            "Question"
        )
        if ($result -eq "Yes") {
            $fixed = Fix-DuplicateBCEEntries -AppendVolumeLabels
                    if ((Get-SafeCount $fixed) -gt 0) {
                        [System.Windows.MessageBox]::Show("Fixed $(Get-SafeCount $fixed) duplicate entry name(s).", "Success", "OK", "Information")
                $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            }
        } elseif ($result -eq "No") {
            $fixed = Fix-DuplicateBCEEntries
                    if ((Get-SafeCount $fixed) -gt 0) {
                        [System.Windows.MessageBox]::Show("Fixed $(Get-SafeCount $fixed) duplicate entry name(s).", "Success", "OK", "Information")
                $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            }
        }
    } else {
        [System.Windows.MessageBox]::Show(
            "No duplicate boot entry names found.`n`nAll Windows Boot Loader entries have unique names.`n`n(Note: System entries like 'Windows Boot Manager' are excluded from duplicate checking.)",
            "No Duplicates",
            "OK",
            "Information"
        )
    }
    })
}

# Sync BCD to All EFI Partitions
$btnSyncBCD = Get-Control -Name "BtnSyncBCD"
if ($btnSyncBCD) {
    $btnSyncBCD.Add_Click({
        $driveCombo = Get-Control -Name "DriveCombo"
        $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
    $drive = "C"
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $result = [System.Windows.MessageBox]::Show(
        "This will synchronize the BCD configuration to ALL EFI System Partitions on all drives.`n`nThis ensures the same boot menu appears regardless of which drive the BIOS boots from.`n`nSource: $drive`:\Windows`n`nContinue?",
        "Synchronize BCD to All EFI Partitions",
        "YesNo",
        "Question"
    )
    
        if ($result -eq "Yes") {
            try {
                $fixerOutput = Get-Control -Name "FixerOutput"
                if ($fixerOutput) {
                    $fixerOutput.Text = "Synchronizing BCD to all EFI partitions...`n"
                }
                $syncResult = Sync-BCDToAllEFIPartitions -SourceWindowsDrive $drive
                
                $output = "Synchronization Complete`n"
                $output += "===============================================================`n"
                $output += "$($syncResult.Message)`n`n"
                
                foreach ($res in $syncResult.Results) {
                    if ($res.Success) {
                        $output += "[SUCCESS] Drive $($res.Drive): Synced successfully`n"
                    } else {
                        $output += "[FAILED] Drive $($res.Drive): $($res.Error)`n"
                    }
                }
                
                if ($fixerOutput) {
                    $fixerOutput.Text = $output
                }
                [System.Windows.MessageBox]::Show($syncResult.Message, "Synchronization Complete", "OK", "Information")
            } catch {
                [System.Windows.MessageBox]::Show("Error during synchronization: $_", "Error", "OK", "Error")
            }
        }
    })
}

# Boot Diagnosis button (Boot Fixer tab)
$btnBootDiagnosis = Get-Control -Name "BtnBootDiagnosis"
if ($btnBootDiagnosis) {
    $btnBootDiagnosis.Add_Click({
        $driveCombo = Get-Control -Name "DriveCombo"
        $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        $diagnosis = Get-BootDiagnosis -TargetDrive $drive
        $fixerOutput = Get-Control -Name "FixerOutput"
        if ($fixerOutput) {
            $fixerOutput.Text = $diagnosis
        }
        
        # Switch to Boot Fixer tab to show the output
        $tabControl = Get-Control -Name "TabControl"
        if ($tabControl) {
            $bootFixerTab = $tabControl.Items | Where-Object { $_.Header -eq "Boot Fixer" }
            if ($bootFixerTab) {
                $tabControl.SelectedItem = $bootFixerTab
            }
        }
        
        [System.Windows.MessageBox]::Show(
            "Boot diagnosis complete.`n`nResults are displayed in the 'Boot Fixer' tab below.`n`nScroll down in the output box to see the full diagnosis report.",
            "Diagnosis Complete",
            "OK",
            "Information"
        )
    })
}

# Precision Detection & Repair (ordered plan)
$btnPrecisionScan = Get-Control -Name "BtnPrecisionScan"
if ($btnPrecisionScan) {
    $btnPrecisionScan.Add_Click({
        $fixerOutput = Get-Control -Name "FixerOutput"
        $txtPrecisionScan = Get-Control -Name "TxtPrecisionScan"
        $chkTestMode = Get-Control -Name "ChkTestMode"

        # Ensure core is loaded (idempotent)
        try {
            . "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop
        } catch {
            if ($fixerOutput) { $fixerOutput.Text = "Failed to load core engine: $_" }
            [System.Windows.MessageBox]::Show("Failed to load core engine: $_","Error","OK","Error") | Out-Null
            return
        }

        $apply = -not ($chkTestMode -and $chkTestMode.IsChecked)

        $winDrive = [Microsoft.VisualBasic.Interaction]::InputBox("Target Windows drive letter (e.g. C):","Precision Scan","C")
        if ([string]::IsNullOrWhiteSpace($winDrive)) { $winDrive = "C" }
        $winDrive = $winDrive.TrimEnd(':').ToUpper()
        $windowsRoot = "$winDrive`:\Windows"

        $espLetter = [Microsoft.VisualBasic.Interaction]::InputBox("EFI System Partition letter (default Z):","Precision Scan","Z")
        if ([string]::IsNullOrWhiteSpace($espLetter)) { $espLetter = "Z" }
        $espLetter = $espLetter.TrimEnd(':').ToUpper()

        $askLogsPrompt = [System.Windows.MessageBox]::Show(
            "Offer to open logs after scan (SrtTrail, ntbtlog, CBS, DISM)?",
            "Precision Scan",
            "YesNo",
            "Question"
        )
        $askLogs = ($askLogsPrompt -eq "Yes")

        try {
            Update-StatusBar -Message "Running precision scan..." -ShowProgress
            $result = Start-PrecisionScan -WindowsRoot $windowsRoot -EspDriveLetter $espLetter -Apply:$apply -AskOpenLogs:$askLogs -PassThru -ActionLogPath "$env:TEMP\precision-actions.log" -ErrorAction Stop

            $summary = "PRECISION SCAN (" + ($(if ($apply) { "APPLY" } else { "DRY-RUN" })) + ")`n"
            $summary += "===============================================================`n"
            $summary += "Windows: $windowsRoot  ESP: $espLetter`n`n"

            if ($result -and $result.Detections -and (Get-SafeCount $result.Detections) -gt 0) {
                foreach ($det in $result.Detections) {
                    $summary += "[$($det.Id)] $($det.Title)  (Category: $($det.Category))`n"
                    foreach ($ev in $det.Evidence) { $summary += "  Evidence: $ev`n" }
                    if ($det.Remediate) {
                        $summary += "  Commands:`n"
                        foreach ($cmd in $det.Remediate) { $summary += "    - $cmd`n" }
                    }
                    $summary += "`n"
                }
            } else {
                $summary += "No issues detected by precision scan.`n"
            }

            if ($fixerOutput) {
                $fixerOutput.Text = $summary
                $fixerOutput.ScrollToEnd()
            }
            if ($txtPrecisionScan) {
                $txtPrecisionScan.Text = "Last run: $(Get-Date -Format 'HH:mm:ss') on $windowsRoot (ESP $espLetter). Mode: " + ($(if ($apply) { "Apply" } else { "Dry-run" }))
            }

            Update-StatusBar -Message "Precision scan completed" -HideProgress
        } catch {
            if ($fixerOutput) { $fixerOutput.Text = "Precision scan failed: $_`n" }
            Update-StatusBar -Message "Precision scan failed" -HideProgress
            [System.Windows.MessageBox]::Show("Precision scan failed: $_","Error","OK","Error") | Out-Null
        }
    })
}

# One-Click Precision Fixer button
$btnOneClickPrecisionFix = Get-Control -Name "BtnOneClickPrecisionFix"
if ($btnOneClickPrecisionFix) {
    $btnOneClickPrecisionFix.Add_Click({
        $fixerOutput = Get-Control -Name "FixerOutput"
        $txtOneClickPrecisionFix = Get-Control -Name "TxtOneClickPrecisionFix"

        # Ensure core is loaded (idempotent)
        try {
            . "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop
        } catch {
            if ($fixerOutput) { $fixerOutput.Text = "Failed to load core engine: $_" }
            [System.Windows.MessageBox]::Show("Failed to load core engine: $_","Error","OK","Error") | Out-Null
            return
        }

        $winDrive = [Microsoft.VisualBasic.Interaction]::InputBox("Target Windows drive letter (e.g. C):","One-Click Precision Fixer","C")
        if ([string]::IsNullOrWhiteSpace($winDrive)) { $winDrive = "C" }
        $winDrive = $winDrive.TrimEnd(':').ToUpper()
        $windowsRoot = "$winDrive`:\Windows"

        $espLetter = [Microsoft.VisualBasic.Interaction]::InputBox("EFI System Partition letter (default Z):","One-Click Precision Fixer","Z")
        if ([string]::IsNullOrWhiteSpace($espLetter)) { $espLetter = "Z" }
        $espLetter = $espLetter.TrimEnd(':').ToUpper()

        try {
            Update-StatusBar -Message "Running one-click precision fixer..." -ShowProgress
            if ($fixerOutput) {
                $fixerOutput.Text = "ONE-CLICK PRECISION FIXER`n===============================================================`n`nStarting automated repair process...`n`n"
            }

            # Run in background job to prevent GUI freeze
            $corePath = Join-Path $scriptRoot "WinRepairCore.ps1"
            $job = Start-Job -ScriptBlock {
                param($WindowsRoot, $EspDriveLetter, $ActionLogPath, $CorePath)
                . $CorePath
                $result = Start-OneClickPrecisionFix -WindowsRoot $WindowsRoot -EspDriveLetter $EspDriveLetter -PassThru -ActionLogPath $ActionLogPath
                return $result
            } -ArgumentList $windowsRoot, $espLetter, "$env:TEMP\precision-actions.log", $corePath

            # Monitor job progress
            while ($job.State -eq 'Running') {
                Start-Sleep -Milliseconds 500
                [System.Windows.Forms.Application]::DoEvents()
            }

            # Check for job errors
            if ($job.State -eq 'Failed') {
                $errorMsg = Receive-Job -Job $job -Error
                Remove-Job -Job $job
                if ($fixerOutput) {
                    $fixerOutput.Text = "ONE-CLICK PRECISION FIXER FAILED`n===============================================================`n`nError: $errorMsg`n"
                }
                Update-StatusBar -Message "One-click precision fixer failed" -HideProgress
                [System.Windows.MessageBox]::Show("One-click precision fixer failed: $errorMsg","Error","OK","Error") | Out-Null
                return
            }

            $result = Receive-Job -Job $job
            Remove-Job -Job $job

            # Check if result is null
            if ($null -eq $result) {
                if ($fixerOutput) {
                    $fixerOutput.Text = "ONE-CLICK PRECISION FIXER`n===============================================================`n`nError: Function returned no result. Scan may have been aborted.`n"
                }
                Update-StatusBar -Message "One-click precision fixer completed with no result" -HideProgress
                return
            }

            $summary = "ONE-CLICK PRECISION FIXER RESULTS`n"
            $summary += "===============================================================`n"
            $summary += "Windows: $windowsRoot  ESP: $espLetter`n`n"

            if ($result.Success) {
                $summary += "[SUCCESS] $($result.Message)`n`n"
            } else {
                $summary += "[PARTIAL/FAILED] $($result.Message)`n`n"
            }

            if ($result.FixedIssues -and (Get-SafeCount $result.FixedIssues) -gt 0) {
                $summary += "FIXED ISSUES ($(Get-SafeCount $result.FixedIssues)):`n"
                foreach ($issue in $result.FixedIssues) {
                    $issueId = $issue.Id
                    $issueTitle = $issue.Title
                    $issueCategory = $issue.Category
                    $summary += "  [OK] [$issueId] $issueTitle (Category: $issueCategory)`n"
                }
                $summary += "`n"
            }

            if ($result.RemainingIssues -and (Get-SafeCount $result.RemainingIssues) -gt 0) {
                $summary += "REMAINING ISSUES ($(Get-SafeCount $result.RemainingIssues)):`n"
                foreach ($issue in $result.RemainingIssues) {
                    $issueId = $issue.Id
                    $issueTitle = $issue.Title
                    $issueCategory = $issue.Category
                    $summary += "  [WARN] [$issueId] $issueTitle (Category: $issueCategory)`n"
                }
                $summary += "`n"
            }

            if ($result.RequiresRepairInstall) {
                $summary += "[WARN] REPAIR INSTALL RECOMMENDED [WARN]`n"
                $summary += "===============================================================`n"
                $summary += "Reason: $($result.RepairInstallReason)`n`n"
                $summary += "Critical issues detected that cannot be fixed automatically.`n"
                $summary += "A repair install (in-place upgrade) is recommended.`n`n"
                $summary += "WHAT GETS KEPT:`n"
                $summary += "  [OK] Your files (Documents, Pictures, Videos, etc.)`n"
                $summary += "  [OK] Your installed programs`n"
                $summary += "  [OK] Your user profiles and settings`n`n"
                $summary += "WHAT YOU NEED:`n"
                $summary += "  - Windows ISO matching your current edition and build family`n"
                $summary += "  - Same architecture (x64/x86) and language`n`n"
                $summary += "Use the 'Repair Install Forcer' tab to proceed.`n"

                # Show dialog with repair install recommendation
                $response = [System.Windows.MessageBox]::Show(
                    "Critical issues detected that require repair install.`n`n" +
                    "Your files and programs will be preserved.`n`n" +
                    "Would you like to open the Repair Install Forcer tab?",
                    "Repair Install Recommended",
                    "YesNo",
                    "Warning"
                )
                if ($response -eq "Yes") {
                    # Switch to Repair Install Forcer tab
                    $repairInstallTab = $W.FindName("RepairInstallForcerTab")
                    if ($repairInstallTab) {
                        $repairInstallTab.IsSelected = $true
                    }
                }
            }

            if ($fixerOutput) {
                $fixerOutput.Text = $summary
                $fixerOutput.ScrollToEnd()
            }
            if ($txtOneClickPrecisionFix) {
                $txtOneClickPrecisionFix.Text = "Last run: $(Get-Date -Format 'HH:mm:ss') on $windowsRoot (ESP $espLetter). Result: $($result.Message)"
            }

            Update-StatusBar -Message "One-click precision fixer completed" -HideProgress
        } catch {
            if ($fixerOutput) { $fixerOutput.Text = "One-click precision fixer failed: $_`n" }
            Update-StatusBar -Message "One-click precision fixer failed" -HideProgress
            [System.Windows.MessageBox]::Show("One-click precision fixer failed: $_","Error","OK","Error") | Out-Null
        }
    })
}

# Boot Diagnosis button (BCD Editor tab)
$btnBootDiagnosisBCD = Get-Control -Name "BtnBootDiagnosisBCD"
if ($btnBootDiagnosisBCD) {
    $btnBootDiagnosisBCD.Add_Click({
        $driveCombo = Get-Control -Name "DriveCombo"
        $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        $diagnosis = Get-BootDiagnosis -TargetDrive $drive
        $bcdBox = Get-Control -Name "BCDBox"
        if ($bcdBox) {
            $bcdBox.Text = $diagnosis
        }
        
        [System.Windows.MessageBox]::Show(
            "Boot diagnosis complete.`n`nResults are displayed in the BCD output box below.",
            "Diagnosis Complete",
            "OK",
            "Information"
        )
    })
}

# Update BCD Description with backup and BitLocker check
$btnUpdateBcd = Get-Control -Name "BtnUpdateBcd"
if ($btnUpdateBcd) {
    $btnUpdateBcd.Add_Click({
        $editId = Get-Control -Name "EditId"
        $editName = Get-Control -Name "EditName"
        $id = if ($editId) { $editId.Text } else { "" }
        $name = if ($editName) { $editName.Text } else { "" }
    if ($id -and $name) {
        # Show comprehensive warning
        $warningInfo = Show-CommandWarning -CommandKey "bcd_description" -Command "Set-BCDDescription $id $name" -Description "Change BCD entry description" -IsGUI
        
        $warningMsg = "$($warningInfo.Message)`n`nDo you want to proceed?"
        $result = [System.Windows.MessageBox]::Show(
            $warningMsg,
            $warningInfo.Title,
            "YesNo",
            $(if ($warningInfo.RiskLevel -eq "Critical") { "Error" } elseif ($warningInfo.RiskLevel -eq "High") { "Warning" } else { "Question" })
        )
        
        if ($result -eq "No") {
            return
        }
        
        # BitLocker Safety Check
        $bitlocker = Test-BitLockerStatus -TargetDrive "C"
        if ($bitlocker.IsEncrypted) {
            $result = [System.Windows.MessageBox]::Show(
                "$($bitlocker.Warning)`n`nNOTE: Boot recovery operations may take longer on BitLocker-encrypted drives. This is normal - please be patient.`n`nDo you have your BitLocker recovery key available?`n`nClick 'Yes' to proceed anyway, or 'No' to cancel.",
                "BitLocker Encryption Detected",
                "YesNo",
                "Warning"
            )
            if ($result -eq "No") {
                return
            }
        }
        
        # Create backup first
        $backup = Export-BCDBackup
        if ($backup.Success) {
            Set-BCDDescription $id $name
            [System.Windows.MessageBox]::Show("Entry Updated!`n`nBackup saved to: $($backup.Path)", "Success", "OK", "Information")
            
            # Update simulator in real-time
            $bcdList = Get-Control -Name "BCDList"
            $selected = if ($bcdList) { $bcdList.SelectedItem } else { $null }
            if ($selected) {
                $selected.Description = $name
                $selected.DisplayText = $name
                if ($bcdList) {
                    $bcdList.Items.Refresh()
                    Update-BootMenuSimulator ($bcdList.ItemsSource)
                }
            }
            
            $btnBCD = Get-Control -Name "BtnBCD"
            if ($btnBCD) {
                $btnBCD.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            }
        } else {
            [System.Windows.MessageBox]::Show("Failed to create backup. Update cancelled for safety.", "Error", "OK", "Error")
        }
    }
    })
}

# Save Advanced Properties
$btnSaveProperties = Get-Control -Name "BtnSaveProperties"
if ($btnSaveProperties) {
    $btnSaveProperties.Add_Click({

    $bcdList = Get-Control -Name "BCDList"
    $selected = if ($bcdList) { $bcdList.SelectedItem } else { $null }
    if (-not $selected) {
        [System.Windows.MessageBox]::Show("Please select a BCD entry first.", "Warning", "OK", "Warning")
        return
    }
    
    $bcdPropertiesGrid = Get-Control -Name "BCDPropertiesGrid"
    $properties = if ($bcdPropertiesGrid) { $bcdPropertiesGrid.ItemsSource } else { $null }
    if (-not $properties) { return }
    
    # Create backup first
    $backup = Export-BCDBackup
    if (-not $backup.Success) {
        [System.Windows.MessageBox]::Show("Failed to create backup. Changes cancelled for safety.", "Error", "OK", "Error")
        return
    }
    
    try {
        foreach ($prop in $properties) {
            if ($prop.Name -and $prop.Value) {
                # Validate path/device if applicable
                if ($prop.Name -match 'path|device' -and $prop.Value) {
                    $isValid = Test-BCDPath -Path $prop.Value -Device $selected.Device
                    if (-not $isValid -and $prop.Name -eq 'path') {
                        $result = [System.Windows.MessageBox]::Show(
                            "Warning: The path '$($prop.Value)' may not exist. Continue anyway?",
                            "Path Validation",
                            "YesNo",
                            "Warning"
                        )
                        if ($result -eq "No") { continue }
                    }
                }
                
                Set-BCDProperty -Id $selected.Id -Property $prop.Name -Value $prop.Value
            }
        }
        
        [System.Windows.MessageBox]::Show("Properties updated!`n`nBackup saved to: $($backup.Path)", "Success", "OK", "Information")
        $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    } catch {
        [System.Windows.MessageBox]::Show("Error updating properties: $_", "Error", "OK", "Error")
    }
    })
}

$btnSetDefault = Get-Control -Name "BtnSetDefault"
if ($btnSetDefault) {
    $btnSetDefault.Add_Click({
        $editId = Get-Control -Name "EditId"
        $id = if ($editId) { $editId.Text } else { "" }
        
        if ($id) {
            $command = "bcdedit /default $id"
            $testMode = Show-CommandPreview $command $null "Set Default Boot Entry"
            
            if ($testMode) {
                Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
                return
            }
            
            try {
                Update-StatusBar -Message "Setting default boot entry..." -ShowProgress
                Set-BCDDefaultEntry $id
                Update-StatusBar -Message "Default boot entry set - refreshing list..." -ShowProgress
                
                # Refresh BCD list to show the new default
                $btnBCD = Get-Control -Name "BtnBCD"
                if ($btnBCD) {
                    $btnBCD.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                }
                
                Update-StatusBar -Message "Default boot entry updated" -HideProgress
                [System.Windows.MessageBox]::Show("Default Boot Set to $id`n`nThe list has been refreshed to show the new default entry.", "Success", "OK", "Information")
            } catch {
                Update-StatusBar -Message "Failed to set default boot entry: $_" -HideProgress
                [System.Windows.MessageBox]::Show("Error setting default boot entry: $_", "Error", "OK", "Error")
            }
        }
    })
}

$btnTimeout = Get-Control -Name "BtnTimeout"
if ($btnTimeout) {
    $btnTimeout.Add_Click({

    $t = $W.FindName("TxtTimeout").Text
    bcdedit /timeout $t
    [System.Windows.MessageBox]::Show("Timeout updated to $t seconds.", "Success", "OK", "Information")
    })
}

# Driver Diagnostics
$btnDetect = Get-Control -Name "BtnDetect"
if ($btnDetect) {
    $btnDetect.Add_Click({
        $drvBox = Get-Control -Name "DrvBox"
        if ($drvBox) {
            $drvBox.Text = "Scanning for storage driver errors...`n`n"
        }
        $result = Get-MissingStorageDevices
        if ($drvBox) {
            $drvBox.Text = $result
        }
    })
}

$btnScanDrivers = Get-Control -Name "BtnScanDrivers"
if ($btnScanDrivers) {
    $btnScanDrivers.Add_Click({
        $driveCombo = Get-Control -Name "DriveCombo"
        $drvBox = Get-Control -Name "DrvBox"
        
        $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
        $drive = $null
        
        if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1] + ":"
            }
        }
        
        if ($drvBox) {
            $drvBox.Text = "Scanning for MISSING storage drivers...`n`n"
            $drvBox.Text += "Checking for problematic storage controllers first...`n"
        }
        
        $scanResult = Scan-ForDrivers -SourceDrive $drive
        
        if ($scanResult.Found) {
            $output = "`n[SUCCESS] SCAN COMPLETE`n"
            $output += "===============================================================`n"
            $output += "$($scanResult.Message)`n"
            $output += "Source Location: $($scanResult.SearchPath)`n"
            $output += "`nFound Drivers (matching missing devices):`n"
            $output += "---------------------------------------------------------------`n"
            
            $num = 1
            foreach ($driver in $scanResult.Drivers) {
                $output += "$num. $($driver.Name)`n"
                $output += "   Path: $($driver.Path)`n"
                $output += "   Type: $($driver.Type)`n`n"
                $num++
            }
            
            if ($drvBox) {
                $drvBox.Text = $output
            }
        } else {
            if ($drvBox) {
                $drvBox.Text = "`n[INFO] SCAN RESULTS`n`n$($scanResult.Message)"
            }
        }
    })
}

$btnScanAllDrivers = Get-Control -Name "BtnScanAllDrivers"
if ($btnScanAllDrivers) {
    $btnScanAllDrivers.Add_Click({
        $driveCombo = Get-Control -Name "DriveCombo"
        $drvBox = Get-Control -Name "DrvBox"
        
        $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
        $drive = $null
        
        if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1] + ":"
            }
        }
        
        if ($drvBox) {
            $drvBox.Text = "Scanning for ALL available storage drivers...`n`n"
            $drvBox.Text += "This may take a moment...`n"
        }
        
        $scanResult = Scan-ForDrivers -SourceDrive $drive -ShowAll
        
        if ($scanResult.Found) {
            $output = "`n[SUCCESS] SCAN COMPLETE`n"
            $output += "===============================================================`n"
            $output += "$($scanResult.Message)`n"
            $output += "Source Location: $($scanResult.SearchPath)`n"
            $output += "`nFound Drivers (ALL storage drivers):`n"
            $output += "---------------------------------------------------------------`n"
            
            $num = 1
            foreach ($driver in $scanResult.Drivers) {
                $output += "$num. $($driver.Name)`n"
                $output += "   Path: $($driver.Path)`n"
                $output += "   Type: $($driver.Type)`n`n"
                $num++
            }
            
            if ($drvBox) {
                $drvBox.Text = $output
            }
        } else {
            if ($drvBox) {
                $drvBox.Text = "`n[FAILED] SCAN FAILED`n`n$($scanResult.Message)"
            }
        }
    })
}

# Advanced Driver Tools (2025+ Systems) - Handler for advanced storage controller detection
# Note: Add button to XAML with Name="BtnAdvancedControllerDetection" to enable
if ($W.FindName("BtnAdvancedControllerDetection")) {
    $btnAdvancedControllerDetection = Get-Control -Name "BtnAdvancedControllerDetection"
    if ($btnAdvancedControllerDetection) {
        $btnAdvancedControllerDetection.Add_Click({

        $drvBox = Get-Control -Name "DrvBox"
        if ($drvBox) {
            $drvBox.Text = "Advanced Storage Controller Detection (2025+ Systems)`n"
            $drvBox.Text += "===============================================================`n"
            $drvBox.Text += "Detecting storage controllers using WMI, Registry, and PCI enumeration...`n`n"
        }
        
        Update-StatusBar -Message "Detecting storage controllers..." -ShowProgress
        
        try {
            $controllers = Get-AdvancedStorageControllerInfo -IncludeNonCritical -Detailed
            
            if ($controllers.Count -eq 0) {
                if ($drvBox) {
                    $drvBox.Text += "No storage controllers detected.`n"
                }
            } else {
                $output = "Found $($controllers.Count) storage controller(s):`n`n"
                
                foreach ($controller in $controllers) {
                    $statusColor = if ($controller.HasDriver) { "[OK]" } else { "[MISSING]" }
                    $criticalMark = if ($controller.IsBootCritical) { " [BOOT-CRITICAL]" } else { "" }
                    
                    $output += "Controller: $($controller.Name)$criticalMark`n"
                    $output += "  Type: $($controller.ControllerType)`n"
                    $output += "  Vendor: $($controller.Vendor)`n"
                    $output += "  Status: $($controller.Status) $statusColor`n"
                    $output += "  Has Driver: $($controller.HasDriver)`n"
                    $output += "  Needs Driver: $($controller.NeedsDriver)`n"
                    $output += "  Required INF: $($controller.RequiredInf)`n"
                    if ($controller.HardwareIDs -and $controller.HardwareIDs.Count -gt 0) {
                        $output += "  Hardware ID: $($controller.HardwareIDs[0])`n"
                    }
                    $output += "`n"
                }
                
                $needsDriver = ($controllers | Where-Object { $_.NeedsDriver }).Count
                $bootCritical = ($controllers | Where-Object { $_.IsBootCritical }).Count
                
                $output += "Summary:`n"
                $output += "  Total Controllers: $($controllers.Count)`n"
                $output += "  Boot-Critical: $bootCritical`n"
                $output += "  Need Drivers: $needsDriver`n"
                
                if ($drvBox) {
                    $drvBox.Text += $output
                }
            }
            
            Update-StatusBar -Message "Storage controller detection complete" -HideProgress
        } catch {
            if ($drvBox) {
                $drvBox.Text += "Error: $_`n"
            }
            Update-StatusBar -Message "Error detecting storage controllers: $_" -HideProgress
        }
        })
    }
}

# Advanced Driver Matching & Injection - Handler
# Note: Add button to XAML with Name="BtnAdvancedDriverInjection" to enable
if ($W.FindName("BtnAdvancedDriverInjection")) {
    $btnAdvancedDriverInjection = Get-Control -Name "BtnAdvancedDriverInjection"
    if ($btnAdvancedDriverInjection) {
        $btnAdvancedDriverInjection.Add_Click({

        $driveCombo = Get-Control -Name "DriveCombo"
        $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        # Show dialog for driver path
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select folder containing driver INF files"
        $folderDialog.ShowNewFolderButton = $false
        
        if ($folderDialog.ShowDialog() -eq "OK") {
            $driverPath = $folderDialog.SelectedPath
            
            $drvBox = Get-Control -Name "DrvBox"
            if ($drvBox) {
                $drvBox.Text = "Advanced Driver Matching & Injection`n"
                $drvBox.Text += "===============================================================`n"
                $drvBox.Text += "Target: $drive`: | Source: $driverPath`n`n"
            }
            
            Update-StatusBar -Message "Detecting storage controllers..." -ShowProgress
            
            try {
                $controllers = Get-AdvancedStorageControllerInfo -IncludeNonCritical
                
                $progressCallback = {
                    param($message, $percent)
                    $W.Dispatcher.Invoke([action]{
                        $drvBoxInner = Get-Control -Name "DrvBox"
                        if ($drvBoxInner) {
                            $drvBoxInner.Text += "$message ($percent%)`n"
                            $drvBoxInner.ScrollToEnd()
                        }
                        Update-StatusBar -Message $message -ShowProgress
                    }, [System.Windows.Threading.DispatcherPriority]::Input)
                }
                
                $result = Start-AdvancedDriverInjection -WindowsDrive $drive -DriverPath $driverPath -ControllerInfo $controllers -ProgressCallback $progressCallback
                
                if ($drvBox) {
                    $drvBox.Text += "`n$($result.Report)`n"
                }
                
                if ($result.Success) {
                    Update-StatusBar -Message "Driver injection completed successfully" -HideProgress
                    [System.Windows.MessageBox]::Show("Successfully injected $($result.DriversInjected.Count) driver(s).", "Success", "OK", "Information")
                } else {
                    Update-StatusBar -Message "Driver injection completed with errors" -HideProgress
                    [System.Windows.MessageBox]::Show("Driver injection completed with $($result.DriversFailed.Count) error(s). Check the output for details.", "Warning", "OK", "Warning")
                }
            } catch {
                if ($drvBox) {
                    $drvBox.Text += "Error: $_`n"
                }
                Update-StatusBar -Message "Error: $_" -HideProgress
                [System.Windows.MessageBox]::Show("Error during driver injection: $_", "Error", "OK", "Error")
            }
        }
        })
    }
}

# Find Matching Drivers - Handler
# Note: Add button to XAML with Name="BtnFindMatchingDrivers" to enable
if ($W.FindName("BtnFindMatchingDrivers")) {
    $btnFindMatchingDrivers = Get-Control -Name "BtnFindMatchingDrivers"
    if ($btnFindMatchingDrivers) {
        $btnFindMatchingDrivers.Add_Click({

        $driveCombo = Get-Control -Name "DriveCombo"
        $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
        $drive = $null
        
        if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        $drvBox = Get-Control -Name "DrvBox"
        if ($drvBox) {
            $drvBox.Text = "Find Matching Drivers for Controllers`n"
            $drvBox.Text += "===============================================================`n"
            $drvBox.Text += "Detecting storage controllers...`n`n"
        }
        
        Update-StatusBar -Message "Detecting storage controllers..." -ShowProgress
        
        try {
            $controllers = Get-AdvancedStorageControllerInfo -IncludeNonCritical
            
            if ($controllers.Count -eq 0) {
                if ($drvBox) {
                    $drvBox.Text += "No storage controllers detected.`n"
                }
                Update-StatusBar -Message "No controllers found" -HideProgress
                return
            }
            
            # Show dialog for additional search paths
            $searchPaths = @()
            $addMore = [System.Windows.MessageBox]::Show("Add additional driver search paths?", "Search Paths", "YesNo", "Question")
            
            while ($addMore -eq "Yes") {
                $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
                $folderDialog.Description = "Select additional driver search folder (or Cancel to finish)"
                if ($folderDialog.ShowDialog() -eq "OK") {
                    $searchPaths += $folderDialog.SelectedPath
                    $addMore = [System.Windows.MessageBox]::Show("Add another search path?", "Search Paths", "YesNo", "Question")
                } else {
                    $addMore = "No"
                }
            }
            
            if ($drvBox) {
                $drvBox.Text += "Searching for matching drivers...`n`n"
            }
            Update-StatusBar -Message "Searching for matching drivers..." -ShowProgress
            
            $driverMatches = Find-MatchingDrivers -ControllerInfo $controllers -SearchPaths $searchPaths -WindowsDrive $drive
            
            $output = "Driver Matching Results:`n"
            $output += "===============================================================`n`n"
            
            foreach ($match in $driverMatches) {
                $output += "Controller: $($match.Controller)`n"
                $output += "  Type: $($match.ControllerType)`n"
                $output += "  Hardware ID: $($match.HardwareID)`n"
                $output += "  Required INF: $($match.RequiredInf)`n"
                $output += "  Matches Found: $($match.MatchesFound)`n"
                
                if ($match.BestMatches.Count -gt 0) {
                    $output += "`n  Best Matches:`n"
                    foreach ($bestMatch in $match.BestMatches) {
                        $output += "    - $($bestMatch.DriverName)`n"
                        $output += "      Source: $($bestMatch.Source)`n"
                        $output += "      Match: $($bestMatch.MatchType) (Score: $($bestMatch.MatchScore))`n"
                        $output += "      Signed: $($bestMatch.IsSigned)`n"
                    }
                } else {
                    $output += "  No matching drivers found.`n"
                    $output += "  Recommendation: Download $($match.RequiredInf) from manufacturer`n"
                }
                $output += "`n"
            }
            
            if ($drvBox) {
                $drvBox.Text += $output
            }
            Update-StatusBar -Message "Driver matching complete" -HideProgress
        } catch {
            if ($drvBox) {
                $drvBox.Text += "Error: $_`n"
            }
            Update-StatusBar -Message "Error: $_" -HideProgress
        }
        })
    }
}

# One-Click Repair Handler
# FLAW-007 FIX: Mutual exclusion for repair operations
# Static variable to track if repair is in progress (prevents race conditions)
# Initialize unconditionally to prevent "variable not set" errors
$script:repairInProgress = $false

$btnOneClickRepair = Get-Control -Name "BtnOneClickRepair"
if ($btnOneClickRepair) {
    $btnOneClickRepair.Add_Click({
        # FLAW-007 FIX: Check if repair is already in progress
        if ($script:repairInProgress) {
            [System.Windows.MessageBox]::Show(
                "A repair operation is already in progress.`n`nPlease wait for the current repair to complete before starting another one.`n`nThis prevents conflicts and potential BCD corruption.",
                "Repair Already In Progress",
                "OK",
                "Warning"
            )
            return
        }
        
        # Set flag to prevent concurrent repairs
        $script:repairInProgress = $true
        
        # Initialize variables that helper functions need
        $txtOneClickStatus = $null
        $fixerOutput = $null
        $chkTestMode = $null
        $testMode = $false
        $logFile = $null
        $logContent = $null
        $targetDrive = $null
        $drive = $null
        $repairReport = $null
        
        try {
            $txtOneClickStatus = Get-Control -Name "TxtOneClickStatus"
            $fixerOutput = Get-Control -Name "FixerOutput"
            $chkTestMode = Get-Control -Name "ChkTestMode"
            
            # Check test mode
            if ($chkTestMode) {
                $testMode = $chkTestMode.IsChecked
            }
            
            # Create log file
            $logFile = Join-Path $env:TEMP "OneClickRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            $logContent = New-Object System.Text.StringBuilder
            
            # Determine target drive (will be updated after user selection)
            $targetDrive = $env:SystemDrive.TrimEnd(':')
            $drive = $targetDrive  # Initialize $drive early for use in diagnostic mode
            
            # Load report generator module
            $reportGeneratorPath = Join-Path $scriptRoot "RepairReportGenerator.ps1"
            if (Test-Path $reportGeneratorPath) {
                try {
                    . $reportGeneratorPath
                    $repairReport = New-RepairReport -TargetDrive $targetDrive -ReportPath "$env:TEMP\BootRepairReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                } catch {
                    Write-Warning "Could not load report generator: $_"
                    $repairReport = $null
                }
            } else {
                $repairReport = $null
            }
            
            # Define Write-Log function (must be accessible to helper functions)
            function Write-Log {
                param([string]$Message)
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $logEntry = "[$timestamp] $Message"
                $logContent.AppendLine($logEntry) | Out-Null
                if ($fixerOutput) {
                    $fixerOutput.Text += "$logEntry`n"
                    $fixerOutput.ScrollToEnd()
                }
            }
            
            function Write-CommandLog {
                param(
                    [string]$Command, 
                    [string]$Description, 
                    [switch]$IsRepairCommand,
                    [string]$Output = "",
                    [int]$ExitCode = 0,
                    [string]$ErrorMessage = ""
                )
                
                $success = ($ExitCode -eq 0 -and -not $ErrorMessage)
                
                # Track in report generator if available
                if ($repairReport) {
                    try {
                        Add-RepairCommand -Report $repairReport -Command $Command -Description $Description -Output $Output -ExitCode $ExitCode -Success $success -Error $Error -IsRepairCommand $IsRepairCommand | Out-Null
                    } catch {
                        # Silently fail if report tracking fails
                    }
                }
                
                if ($IsRepairCommand) {
                    # Repair commands (write operations) - skip in test mode
                    if ($testMode) {
                        Write-Log "[TEST MODE] Would execute repair: $Command"
                        Write-Log "  Description: $Description"
                        Write-Log "  Status: SKIPPED (Test Mode Active - this would modify system)"
                    } else {
                        Write-Log "[EXECUTING REPAIR] Command: $Command"
                        Write-Log "  Description: $Description"
                        if ($Output) {
                            Write-Log "  Output: $($Output.Substring(0, [Math]::Min(200, $Output.Length)))..."
                        }
                        if (-not $success) {
                            Write-Log "  [FAILED] Exit Code: $ExitCode"
                            if ($Error) {
                                Write-Log "  Error: $Error"
                            }
                        }
                    }
                } else {
                    # Diagnostic commands (read-only) - always run
                    Write-Log "[DIAGNOSTIC] Running: $Command"
                    Write-Log "  Description: $Description (read-only check)"
                    if ($Output -and $Output.Length -gt 0) {
                        Write-Log "  Output: $($Output.Substring(0, [Math]::Min(200, $Output.Length)))..."
                    }
                }
            }
            
            function Invoke-TrackedCommand {
                <#
                .SYNOPSIS
                Executes a command and automatically tracks it in the repair report.
                #>
                param(
                    [Parameter(Mandatory=$true)]
                    [string]$Command,
                    [string]$Description = "",
                    [switch]$IsRepairCommand,
                    [scriptblock]$ScriptBlock
                )
                
                Write-CommandLog -Command $Command -Description $Description -IsRepairCommand:$IsRepairCommand
                
                if ($IsRepairCommand -and $testMode) {
                    Write-Log "  [SKIPPED] Command not executed (Test Mode Active)"
                    return @{
                        Success = $true
                        Output = ""
                        ExitCode = 0
                        ErrorMessage = ""
                    }
                }
                
                $output = ""
                $errorMsg = ""
                $exitCode = 0
                $success = $false
                
                try {
                    if ($ScriptBlock) {
                        $output = & $ScriptBlock 2>&1 | Out-String
                        $exitCode = $LASTEXITCODE
                        $success = ($exitCode -eq 0)
                    } else {
                        # Execute as string command
                        $output = Invoke-Expression $Command 2>&1 | Out-String
                        $exitCode = $LASTEXITCODE
                        $success = ($exitCode -eq 0)
                    }
                } catch {
                    $errorMsg = $_.Exception.Message
                    $output = $_.Exception.ToString()
                    $success = $false
                }
                
                # Update command log with results
                Write-CommandLog -Command $Command -Description $Description -IsRepairCommand:$IsRepairCommand -Output $output -ExitCode $exitCode -ErrorMessage $errorMsg
                
                return @{
                    Success = $success
                    Output = $output
                    ExitCode = $exitCode
                    ErrorMessage = $errorMsg
                }
            }
        } catch {
            Write-Warning "Failed to initialize One-Click Repair controls: $_"
            [System.Windows.MessageBox]::Show("Failed to initialize repair interface: $_", "Initialization Error", "OK", "Error")
            $script:repairInProgress = $false
            $btnOneClickRepair.IsEnabled = $true
            return
        }
        
        # Disable button during repair
        $btnOneClickRepair.IsEnabled = $false
        
        try {
            Write-Log "==============================================================="
            Write-Log "ONE-CLICK REPAIR - AUTOMATED DIAGNOSIS AND REPAIR"
            Write-Log "==============================================================="
            Write-Log "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Write-Log "Test Mode: $(if ($testMode) { 'ENABLED (Commands will NOT be executed)' } else { 'DISABLED (Commands WILL be executed)' })"
            Write-Log "Target Drive: $($env:SystemDrive)"
            Write-Log ""
            
            # Update status
            if ($txtOneClickStatus) {
                $txtOneClickStatus.Text = if ($testMode) { "Starting automated repair (TEST MODE)... Please wait." } else { "Starting automated repair... Please wait." }
            }
            Update-StatusBar -Message "One-Click Repair: Starting diagnostics..." -ShowProgress
            
            # Step 1: Hardware Diagnostics
            if ($txtOneClickStatus) {
                $txtOneClickStatus.Text = "Step 1/5: Running hardware diagnostics (S.M.A.R.T., disk health)..."
            }
            Update-StatusBar -Message "One-Click Repair: Checking hardware health..." -ShowProgress
            
            # Use module-level $scriptRoot (defined at top of file) or resolve safely
            if (-not $scriptRoot) {
                # Fallback: Safe path resolution (same pattern as used elsewhere)
                if ($PSScriptRoot) {
                    $scriptRoot = $PSScriptRoot
                } elseif ($MyInvocation.MyCommand.Path) {
                    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
                } else {
                    # Final fallback: try common locations
                    $scriptRoot = if (Test-Path "Helper\WinRepairCore.ps1") { 
                        "Helper" 
                    } elseif (Test-Path "$(Get-Location)\Helper\WinRepairCore.ps1") {
                        Join-Path (Get-Location) "Helper"
                    } else {
                        throw "Cannot determine script root. WinRepairCore.ps1 not found."
                    }
                }
            }
            
            # Verify script root is valid
            if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
                throw "Script root is null or empty. Cannot load WinRepairCore.ps1."
            }
            
            $corePath = Join-Path $scriptRoot "WinRepairCore.ps1"
            if (-not (Test-Path $corePath)) {
                throw "WinRepairCore.ps1 not found at: $corePath"
            }
            
            . $corePath -ErrorAction Stop
            
            # Load defensive boot-chain module if available
            $defensiveBootChainPath = Join-Path $scriptRoot "DefensiveBootChain.ps1"
            if (Test-Path $defensiveBootChainPath) {
                try {
                    . $defensiveBootChainPath -ErrorAction SilentlyContinue
                } catch {
                    Write-Log "[INFO] Defensive Boot-Chain module not available, using standard repair"
                }
            }
            
            # Load boot viability engine if available
            $bootViabilityPath = Join-Path $scriptRoot "BootViabilityEngine.ps1"
            if (Test-Path $bootViabilityPath) {
                try {
                    . $bootViabilityPath -ErrorAction SilentlyContinue
                } catch {
                    Write-Log "[INFO] Boot Viability Engine not available"
                }
            }
            
            # Load safety guardrails if available
            $safetyGuardrailsPath = Join-Path $scriptRoot "SafetyGuardrails.ps1"
            if (Test-Path $safetyGuardrailsPath) {
                try {
                    . $safetyGuardrailsPath -ErrorAction SilentlyContinue
                } catch {
                    Write-Log "[INFO] Safety Guardrails not available"
                }
            }
            
            # Load simulation harness if available
            $simulationHarnessPath = Join-Path $scriptRoot "SimulationHarness.ps1"
            if (Test-Path $simulationHarnessPath) {
                try {
                    . $simulationHarnessPath -ErrorAction SilentlyContinue
                } catch {
                    Write-Log "[INFO] Simulation Harness not available"
                }
            }
            
            # Determine Repair Mode
            $repairMode = "DIAGNOSE_ONLY"
            if (Get-Command "Get-RepairMode" -ErrorAction SilentlyContinue) {
                $currentMode = Get-RepairMode
                $repairMode = $currentMode.ToString()
                
                Write-Log "Repair Mode: $repairMode" | Out-Null
                
                if ($currentMode -eq [RepairMode]::DIAGNOSE_ONLY) {
                    Write-Log "[INFO] Running in DIAGNOSE_ONLY mode (read-only)" | Out-Null
                } elseif ($currentMode -eq [RepairMode]::REPAIR_SAFE) {
                    Write-Log "[INFO] Running in REPAIR_SAFE mode (limited writes, reversible only)" | Out-Null
                } elseif ($currentMode -eq [RepairMode]::REPAIR_FORCE) {
                    Write-Log "[INFO] Running in REPAIR_FORCE mode (destructive allowed)" | Out-Null
                }
            }
            
            # Environment Safety Check (Prevents bricking healthy systems)
            Write-Log "==============================================================="
            Write-Log "ENVIRONMENT SAFETY CHECK"
            Write-Log "==============================================================="
            Write-Log ""
            
            if (Get-Command "Test-EnvironmentSafety" -ErrorAction SilentlyContinue) {
                $envCheck = Test-EnvironmentSafety
                Write-Log "Environment: $($envCheck.Environment)"
                Write-Log "System Drive: $($envCheck.SystemDrive)"
                Write-Log "Safe for Repairs: $($envCheck.IsSafe)"
                Write-Log "Status: $($envCheck.SafetyMessage)"
                Write-Log ""
                
                if (-not $envCheck.IsSafe) {
                    Write-Log "[BLOCKED] Destructive repairs are DISABLED because you are in a live Windows session."
                    Write-Log ""
                    Write-Log "REASON:"
                    Write-Log "  - Running from $($envCheck.SystemDrive) in full Windows OS"
                    Write-Log "  - Destructive commands (format, bcdboot) could damage the active system"
                    Write-Log ""
                    Write-Log "SOLUTION:"
                    foreach ($rec in $envCheck.Recommendations) {
                        Write-Log "  - $rec"
                    }
                    Write-Log ""
                    Write-Log "Switching to READ-ONLY DIAGNOSTIC MODE..."
                    Write-Log ""
                    
                    # Set drive to system drive if not already set (for FullOS mode)
                    if (-not $drive) {
                        $drive = $env:SystemDrive.TrimEnd(':')
                        Write-Log "[INFO] Using system drive: $drive`:"
                    }
                    
                    # Generate diagnostic state
                    if (Get-Command "Get-RepairState" -ErrorAction SilentlyContinue) {
                        $diagnosticState = Get-RepairState -TargetDrive $drive
                        Write-Log $diagnosticState
                    }
                    
                    if ($txtOneClickStatus) {
                        $txtOneClickStatus.Text = "[BLOCKED] Live Windows detected. Boot from Recovery USB to repair."
                    }
                    if ($fixerOutput) {
                        $fixerOutput.Text += "`n[BLOCKED] $($envCheck.SafetyMessage)`n"
                    }
                    
                    Update-StatusBar -Message "One-Click Repair: BLOCKED - Live Windows detected" -HideProgress
                    
                    # Save log and exit
                    try {
                        $logContent.ToString() | Out-File -FilePath $logFile -Encoding UTF8 -Force
                        Start-Process notepad.exe -ArgumentList $logFile -ErrorAction SilentlyContinue
                    } catch {
                        # Ignore log save errors
                    }
                    
                    return  # STOP - Do not proceed with repairs
                }
            } else {
                Write-Log "[INFO] Environment safety check not available, proceeding with caution"
                Write-Log ""
            }
            
            # Check for Simulation Mode (WhatIf)
            if ($ChkTestMode -and $ChkTestMode.IsChecked) {
                Write-Log "[SIMULATION MODE] All destructive commands will be simulated (not executed)"
                Write-Log ""
            }
            
            # Pre-flight checks: BitLocker and drive accessibility
            Write-Log "==============================================================="
            Write-Log "PRE-FLIGHT CHECKS"
            Write-Log "==============================================================="
            Write-Log ""
            
            # CRITICAL PRE-FLIGHT: Check if BitLocker is LOCKED (blocks all repairs)
            Write-Log "Checking BitLocker status..."
            try {
                $bitlockerStatus = manage-bde -status "$drive`:" 2>&1 | Out-String
                if ($bitlockerStatus -match "Lock Status:\s+Locked") {
                    Write-Log "[BLOCKED] BitLocker is LOCKED on drive $drive`:"
                    Write-Log ""
                    Write-Log "CRITICAL: Drive is encrypted and LOCKED."
                    Write-Log "Repairs cannot proceed until drive is unlocked."
                    Write-Log ""
                    Write-Log "REASON:"
                    Write-Log "  - bcdboot will 'succeed' but write to RAM Disk (X:) or temporary partition"
                    Write-Log "  - Actual Windows drive remains untouched"
                    Write-Log "  - This causes 'False Success' - repairs appear to work but don't"
                    Write-Log ""
                    Write-Log "SOLUTION:"
                    Write-Log "  You MUST unlock the drive with your recovery key before repairing."
                    Write-Log ""
                    Write-Log "Command to unlock:"
                    Write-Log "  manage-bde -unlock $drive`: -RecoveryPassword <YOUR_48_DIGIT_KEY>"
                    Write-Log ""
                    Write-Log "After unlocking, run this repair again."
                    Write-Log ""
                    
                    if ($txtOneClickStatus) {
                        $txtOneClickStatus.Text = "BLOCKED: BitLocker is LOCKED. Unlock drive first."
                    }
                    if ($fixerOutput) {
                        $fixerOutput.Text += "`n[BLOCKED] BitLocker is LOCKED. Drive must be unlocked before repairs.`n"
                        $fixerOutput.Text += "Command: manage-bde -unlock $drive`: -RecoveryPassword <YOUR_KEY>`n"
                    }
                    
                    Update-StatusBar -Message "One-Click Repair: BLOCKED - BitLocker locked" -HideProgress
                    
                    # Save log and exit
                    try {
                        $logContent.ToString() | Out-File -FilePath $logFile -Encoding UTF8 -Force
                        Start-Process notepad.exe -ArgumentList $logFile -ErrorAction SilentlyContinue
                    } catch {
                        # Ignore log save errors
                    }
                    
                    return  # STOP - Do not proceed with repairs
                } else {
                    Write-Log "[OK] BitLocker is unlocked or not enabled"
                }
            } catch {
                # manage-bde might not be available or drive might not be encrypted
                Write-Log "[INFO] Could not check BitLocker status (drive may not be encrypted)"
            }
            Write-Log ""
            
            # Prompt user to select target Windows drive (exclude X: WinPE drive)
            Write-Log "Detecting Windows installations..."
            $installations = @(Get-WindowsInstallations | Where-Object { $_.DriveLetter -ne 'X' } | Sort-Object { if ($_.IsCurrentOS) { 0 } else { 1 } }, DriveLetter)
            
            # Always prompt user for drive selection (even if only one found)
            # This ensures user confirms the correct drive and prevents targeting wrong drive
            if ($installations.Count -eq 0) {
                # Fallback: Allow manual drive entry
                Write-Log "[WARNING] No Windows installations detected automatically."
                Write-Log "Please enter the drive letter manually."
                $manualDrive = [Microsoft.VisualBasic.Interaction]::InputBox(
                    "No Windows installations were automatically detected.`n`n" +
                    "Please enter the drive letter of your Windows installation (e.g., C):",
                    "Manual Drive Selection",
                    "C"
                )
                if ([string]::IsNullOrWhiteSpace($manualDrive)) {
                    Write-Log "[ERROR] No drive selected. Aborting."
                    throw "No target drive selected."
                }
                $drive = $manualDrive.TrimEnd(':').ToUpper()
                $targetDrive = $drive  # Update targetDrive when drive is set
                Write-Log "Using manually specified drive: $drive`:"
            } elseif ($installations.Count -eq 1) {
                # Only one installation found, but still prompt user to confirm
                $selectedInst = $installations[0]
                $confirmMsg = "One Windows installation detected:`n`n" +
                             "Drive: $($selectedInst.Drive)`n" +
                             "Volume Label: $($selectedInst.VolumeLabel)`n" +
                             "OS: $($selectedInst.OSVersion) Build $($selectedInst.OSBuild)`n" +
                             "Size: $([math]::Round($selectedInst.SizeGB, 1)) GB`n" +
                             "Free: $([math]::Round($selectedInst.FreeGB, 1)) GB`n" +
                             "Health: $($selectedInst.HealthStatus)`n`n" +
                             "Use this drive for repair? (Click OK to use, Cancel to enter manually)"
                $confirm = [System.Windows.MessageBox]::Show(
                    $confirmMsg,
                    "Confirm Windows Installation",
                    "OKCancel",
                    "Question"
                )
                if ($confirm -eq "OK") {
                    $drive = $selectedInst.DriveLetter
                    $targetDrive = $drive  # Update targetDrive when drive is set
                    Write-Log "Confirmed Windows installation: $($selectedInst.DisplayName)"
                } else {
                    # User cancelled, allow manual entry
                    $manualDrive = [Microsoft.VisualBasic.Interaction]::InputBox(
                        "Please enter the drive letter of your Windows installation (e.g., C):",
                        "Manual Drive Selection",
                        $selectedInst.DriveLetter
                    )
                    if ([string]::IsNullOrWhiteSpace($manualDrive)) {
                        Write-Log "[ERROR] No drive selected. Aborting."
                        throw "No target drive selected."
                    }
                    $drive = $manualDrive.TrimEnd(':').ToUpper()
                    Write-Log "Using manually specified drive: $drive`:"
                }
            } else {
                # Multiple installations - show selection dialog
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                
                $form = New-Object System.Windows.Forms.Form
                $form.Text = "Select Windows Installation"
                $form.Size = New-Object System.Drawing.Size(700, 500)
                $form.StartPosition = "CenterScreen"
                $form.FormBorderStyle = "FixedDialog"
                $form.MaximizeBox = $false
                $form.MinimizeBox = $false
                
                $label = New-Object System.Windows.Forms.Label
                $label.Location = New-Object System.Drawing.Point(10, 10)
                $label.Size = New-Object System.Drawing.Size(660, 30)
                $label.Text = "Multiple Windows installations detected. Please select the target drive:"
                $form.Controls.Add($label)
                
                $listView = New-Object System.Windows.Forms.ListView
                $listView.Location = New-Object System.Drawing.Point(10, 50)
                $listView.Size = New-Object System.Drawing.Size(660, 350)
                $listView.View = [System.Windows.Forms.View]::Details
                $listView.FullRowSelect = $true
                $listView.GridLines = $true
                $listView.Columns.Add("Drive", 60) | Out-Null
                $listView.Columns.Add("Volume Label", 120) | Out-Null
                $listView.Columns.Add("OS Version", 150) | Out-Null
                $listView.Columns.Add("Size", 80) | Out-Null
                $listView.Columns.Add("Free", 80) | Out-Null
                $listView.Columns.Add("Used %", 70) | Out-Null
                $listView.Columns.Add("Health", 80) | Out-Null
                $listView.Columns.Add("Boot Type", 80) | Out-Null
                
                foreach ($inst in $installations) {
                    $item = New-Object System.Windows.Forms.ListViewItem($inst.Drive)
                    $item.SubItems.Add($inst.VolumeLabel) | Out-Null
                    $item.SubItems.Add("$($inst.OSVersion) Build $($inst.OSBuild)") | Out-Null
                    $item.SubItems.Add("$([math]::Round($inst.SizeGB, 1)) GB") | Out-Null
                    $item.SubItems.Add("$([math]::Round($inst.FreeGB, 1)) GB") | Out-Null
                    $item.SubItems.Add("$($inst.UsedPercent)%") | Out-Null
                    $item.SubItems.Add($inst.HealthStatus) | Out-Null
                    $item.SubItems.Add($inst.BootType) | Out-Null
                    $item.Tag = $inst.DriveLetter
                    if ($inst.IsCurrentOS) {
                        $item.BackColor = [System.Drawing.Color]::LightGreen
                        $item.Text += " (Current OS)"
                    }
                    $listView.Items.Add($item) | Out-Null
                }
                
                # Select first item (usually current OS)
                if ($listView.Items.Count -gt 0) {
                    $listView.Items[0].Selected = $true
                    $listView.Items[0].Focused = $true
                }
                
                $form.Controls.Add($listView)
                
                $btnRefresh = New-Object System.Windows.Forms.Button
                $btnRefresh.Text = "Refresh List"
                $btnRefresh.Location = New-Object System.Drawing.Point(10, 410)
                $btnRefresh.Size = New-Object System.Drawing.Size(100, 30)
                $btnRefresh.Add_Click({
                    $listView.Items.Clear()
                    $refreshed = @(Get-WindowsInstallations | Where-Object { $_.DriveLetter -ne 'X' } | Sort-Object { if ($_.IsCurrentOS) { 0 } else { 1 } }, DriveLetter)
                    foreach ($inst in $refreshed) {
                        $item = New-Object System.Windows.Forms.ListViewItem($inst.Drive)
                        $item.SubItems.Add($inst.VolumeLabel) | Out-Null
                        $item.SubItems.Add("$($inst.OSVersion) Build $($inst.OSBuild)") | Out-Null
                        $item.SubItems.Add("$([math]::Round($inst.SizeGB, 1)) GB") | Out-Null
                        $item.SubItems.Add("$([math]::Round($inst.FreeGB, 1)) GB") | Out-Null
                        $item.SubItems.Add("$($inst.UsedPercent)%") | Out-Null
                        $item.SubItems.Add($inst.HealthStatus) | Out-Null
                        $item.SubItems.Add($inst.BootType) | Out-Null
                        $item.Tag = $inst.DriveLetter
                        if ($inst.IsCurrentOS) {
                            $item.BackColor = [System.Drawing.Color]::LightGreen
                            $item.Text += " (Current OS)"
                        }
                        $listView.Items.Add($item) | Out-Null
                    }
                })
                $form.Controls.Add($btnRefresh)
                
                $btnManual = New-Object System.Windows.Forms.Button
                $btnManual.Text = "Manual Entry"
                $btnManual.Location = New-Object System.Drawing.Point(120, 410)
                $btnManual.Size = New-Object System.Drawing.Size(100, 30)
                $btnManual.Add_Click({
                    $manualDrive = [Microsoft.VisualBasic.Interaction]::InputBox(
                        "Enter the drive letter of your Windows installation (e.g., C):",
                        "Manual Drive Selection",
                        "C"
                    )
                    if (-not [string]::IsNullOrWhiteSpace($manualDrive)) {
                        $script:selectedDrive = $manualDrive.TrimEnd(':').ToUpper()
                        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                        $form.Close()
                    }
                })
                $form.Controls.Add($btnManual)
                
                $btnOK = New-Object System.Windows.Forms.Button
                $btnOK.Text = "OK"
                $btnOK.Location = New-Object System.Drawing.Point(550, 410)
                $btnOK.Size = New-Object System.Drawing.Size(60, 30)
                $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $form.AcceptButton = $btnOK
                $form.Controls.Add($btnOK)
                
                $btnCancel = New-Object System.Windows.Forms.Button
                $btnCancel.Text = "Cancel"
                $btnCancel.Location = New-Object System.Drawing.Point(620, 410)
                $btnCancel.Size = New-Object System.Drawing.Size(60, 30)
                $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                $form.CancelButton = $btnCancel
                $form.Controls.Add($btnCancel)
                
                $script:selectedDrive = $null
                if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    if ($script:selectedDrive) {
                        $drive = $script:selectedDrive
                        $targetDrive = $drive  # Update targetDrive when drive is set
                        Write-Log "Using manually entered drive: $drive`:"
                    } elseif ($listView.SelectedItems.Count -gt 0) {
                        $drive = $listView.SelectedItems[0].Tag
                        $targetDrive = $drive  # Update targetDrive when drive is set
                        $selectedInst = $installations | Where-Object { $_.DriveLetter -eq $drive } | Select-Object -First 1
                        Write-Log "Selected: $($selectedInst.DisplayName)"
                    } else {
                        Write-Log "[ERROR] No drive selected. Aborting."
                        throw "No target drive selected."
                    }
                } else {
                    Write-Log "[ERROR] Drive selection cancelled. Aborting."
                    throw "Drive selection cancelled by user."
                }
            }
            
            Write-Log "Target Drive: $drive`:"
            Write-Log ""
            
            # Check drive accessibility
            Write-Log "Checking drive accessibility..."
            $driveAccessible = $false
            $testPaths = @(
                "$drive`:\Windows",
                "$drive`:\Windows\System32",
                "$drive`:\Windows\System32\ntoskrnl.exe"
            )
            foreach ($testPath in $testPaths) {
                if (Test-Path $testPath) {
                    $driveAccessible = $true
                    Write-Log "[OK] Drive accessible: $testPath"
                    break
                }
            }
            
            # Check BitLocker status and drive accessibility BEFORE repairs
            Write-Log "Checking BitLocker encryption status and drive accessibility..."
            $bitlockerStatus = Test-BitLockerStatus -TargetDrive $drive -TimeoutSeconds 5
            
            # Check if drive is locked (requires recovery key)
            $driveLocked = $false
            if ($bitlockerStatus.VolumeStatus -eq "Locked" -or -not $driveAccessible) {
                $driveLocked = $true
                Write-Log "[WARNING] Drive $drive`: appears to be LOCKED (BitLocker encrypted and requires recovery key)"
                Write-Log ""
                Write-Log "The drive is encrypted and locked. You need your BitLocker recovery key to unlock it."
                Write-Log ""
                Write-Log "Recovery key format: 48 digits (can include dashes)"
                Write-Log "Example: 12345678-12345678-12345678-12345678-12345678-12345678"
                Write-Log ""
                Write-Log "Recovery key locations:"
                Write-Log "  - Microsoft Account: https://account.microsoft.com/devices/recoverykey"
                Write-Log "  - Azure AD: https://aka.ms/aadrecoverykey"
                Write-Log "  - Printed or saved copies"
                Write-Log ""
                
                if (-not $testMode) {
                    # Prompt user for recovery key
                    $recoveryKeyPrompt = [Microsoft.VisualBasic.Interaction]::InputBox(
                        "⚠️ BITLOCKER DRIVE LOCKED`n`n" +
                        "Drive $drive`: is encrypted and locked.`n`n" +
                        "Please enter your 48-digit BitLocker recovery key:`n`n" +
                        "Format: XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX`n" +
                        "(You can enter with or without dashes)`n`n" +
                        "If you don't have the key, click Cancel to retrieve it first.",
                        "BitLocker Recovery Key Required",
                        ""
                    )
                    
                    if ([string]::IsNullOrWhiteSpace($recoveryKeyPrompt)) {
                        Write-Log "[ABORTED] User cancelled recovery key entry."
                        throw "Operation cancelled. Drive requires BitLocker recovery key to proceed."
                    }
                    
                    # Attempt to unlock with recovery key
                    Write-Log "Attempting to unlock drive $drive`: with provided recovery key..."
                    $unlockResult = Unlock-BitLockerDrive -TargetDrive $drive -RecoveryKey $recoveryKeyPrompt
                    
                    if ($unlockResult.Success) {
                        Write-Log "[SUCCESS] $($unlockResult.Message)"
                        Write-Log "Drive is now unlocked and accessible."
                        $driveAccessible = $true
                    } else {
                        Write-Log "[ERROR] $($unlockResult.Message)"
                        Write-Log ""
                        Write-Log "The recovery key you entered is incorrect or unlock failed."
                        Write-Log "Please verify your recovery key and try again."
                        
                        $retry = [System.Windows.MessageBox]::Show(
                            "❌ UNLOCK FAILED`n`n" +
                            "$($unlockResult.Message)`n`n" +
                            "Would you like to try entering the recovery key again?`n`n" +
                            "Click YES to retry, NO to abort.",
                            "BitLocker Unlock Failed",
                            "YesNo",
                            "Error"
                        )
                        
                        if ($retry -eq "Yes") {
                            # Retry once
                            $recoveryKeyRetry = [Microsoft.VisualBasic.Interaction]::InputBox(
                                "Please enter your 48-digit BitLocker recovery key again:",
                                "BitLocker Recovery Key (Retry)",
                                ""
                            )
                            
                            if (-not [string]::IsNullOrWhiteSpace($recoveryKeyRetry)) {
                                $unlockResult = Unlock-BitLockerDrive -TargetDrive $drive -RecoveryKey $recoveryKeyRetry
                                if ($unlockResult.Success) {
                                    Write-Log "[SUCCESS] Drive unlocked on retry: $($unlockResult.Message)"
                                    $driveAccessible = $true
                                } else {
                                    Write-Log "[ERROR] Unlock failed on retry: $($unlockResult.Message)"
                                    throw "Could not unlock BitLocker drive. Please verify your recovery key and try again later."
                                }
                            } else {
                                throw "Recovery key entry cancelled. Cannot proceed without unlocking drive."
                            }
                        } else {
                            throw "BitLocker unlock cancelled. Cannot proceed without unlocking drive."
                        }
                    }
                    Write-Log ""
                } else {
                    Write-Log "[TEST MODE] Drive appears locked but test mode active - would prompt for recovery key"
                }
            }
            
            # Verify drive is accessible after unlock attempt
            if (-not $driveAccessible) {
                $testPaths = @(
                    "$drive`:\Windows",
                    "$drive`:\Windows\System32",
                    "$drive`:\Windows\System32\ntoskrnl.exe"
                )
                foreach ($testPath in $testPaths) {
                    if (Test-Path $testPath) {
                        $driveAccessible = $true
                        Write-Log "[OK] Drive accessible: $testPath"
                        break
                    }
                }
            }
            
            if (-not $driveAccessible) {
                Write-Log "[ERROR] Drive $drive`: is not accessible or does not contain Windows."
                if ($bitlockerStatus.IsEncrypted) {
                    Write-Log "Drive is BitLocker encrypted. If it's locked, you need to unlock it with your recovery key first."
                }
                throw "Drive $drive`: is not accessible. Cannot proceed with repairs."
            }
            Write-Log ""
            
            # Check BitLocker status for warnings (even if drive is unlocked)
            if ($bitlockerStatus.IsEncrypted -or ($bitlockerStatus.Warning -and -not $driveLocked)) {
                Write-Log "[INFO] BITLOCKER ENCRYPTION DETECTED"
                Write-Log "Drive: $drive`:"
                if ($bitlockerStatus.IsEncrypted) {
                    Write-Log "Status: ENCRYPTED (Protection: $($bitlockerStatus.ProtectionStatus))"
                    Write-Log "Encryption: $($bitlockerStatus.EncryptionPercentage)%"
                }
                if ($bitlockerStatus.Warning) {
                    Write-Log "Note: $($bitlockerStatus.Warning)"
                }
                Write-Log ""
                Write-Log "⚠️  IMPORTANT: Modifying boot files on a BitLocker-encrypted drive may trigger"
                Write-Log "   a recovery key prompt on next boot. Ensure you have your 48-digit"
                Write-Log "   BitLocker recovery key saved before proceeding!"
                Write-Log ""
                
                if (-not $testMode -and -not $driveLocked) {
                    $bitlockerConfirm = [System.Windows.MessageBox]::Show(
                        "⚠️ BITLOCKER ENCRYPTION DETECTED`n`n" +
                        "Modifying boot files may require your BitLocker recovery key on next boot.`n`n" +
                        "Do you have your 48-digit BitLocker recovery key saved?`n`n" +
                        "If YES: Click OK to continue.`n" +
                        "If NO: Click Cancel to retrieve your key first.",
                        "BitLocker Warning",
                        "OKCancel",
                        "Warning"
                    )
                    if ($bitlockerConfirm -ne "OK") {
                        Write-Log "[ABORTED] User cancelled due to BitLocker concerns."
                        throw "Operation cancelled by user due to BitLocker encryption."
                    }
                } else {
                    Write-Log "[TEST MODE] BitLocker warning acknowledged (no actual changes will be made)"
                }
                Write-Log ""
            } else {
                Write-Log "[OK] Drive is not BitLocker encrypted (or status check unavailable)"
                Write-Log ""
            }
            
            Write-Log "==============================================================="
            Write-Log "STARTING REPAIR OPERATIONS"
            Write-Log "==============================================================="
            Write-Log ""
            
            # Step 1: Hardware Diagnostics
            Write-Log "Step 1: Hardware Diagnostics"
            Write-Log "---------------------------------------------------------------"
            Write-CommandLog -Command "Test-DiskHealth -TargetDrive $drive" -Description "Check disk health and file system status" -IsRepairCommand:$false
            
            # Diagnostic commands are read-only, so run them even in test mode
            $diskHealth = Test-DiskHealth -TargetDrive $drive
            
            # Test-DiskHealth returns: FileSystemHealthy, HasBadSectors, NeedsRepair, Warnings, Recommendations
            # Determine if disk is healthy and if we can proceed
            $isDiskHealthy = $diskHealth.FileSystemHealthy
            $hasBadSectors = $diskHealth.HasBadSectors
            $needsRepair = $diskHealth.NeedsRepair
            
            # Can proceed with software repair UNLESS:
            # 1. Disk has bad sectors (physical hardware failure)
            # 2. Disk health status is not Healthy (physical hardware failure)
            # 3. Disk is read-only (hardware issue)
            $canProceed = $true
            $criticalHardwareFailure = $false
            
            if ($hasBadSectors) {
                $canProceed = $false
                $criticalHardwareFailure = $true
            }
            
            if (-not $isDiskHealthy) {
                # Check if it's just file system corruption (can be fixed) vs hardware failure
                # If volume is null or disk health status is not Healthy, it's likely hardware
                try {
                    $partition = Get-Partition -DriveLetter $drive -ErrorAction SilentlyContinue
                    if ($partition) {
                        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction SilentlyContinue
                        if ($disk) {
                            # Check actual disk health status
                            if ($disk.HealthStatus -ne 'Healthy') {
                                $canProceed = $false
                                $criticalHardwareFailure = $true
                            }
                            if ($disk.IsReadOnly) {
                                $canProceed = $false
                                $criticalHardwareFailure = $true
                            }
                        }
                    }
                } catch {
                    # If we can't check, assume it's safe to proceed (don't block on errors)
                }
            }
            
            if ($isDiskHealthy -and -not $hasBadSectors -and -not $needsRepair) {
                Write-Log "[OK] Disk health check passed"
                Write-Log "  File System: $($diskHealth.FileSystem)"
                Write-Log "  Health Status: Healthy"
            } else {
                Write-Log "[WARNING] Disk health issues detected:"
                
                if (-not $isDiskHealthy) {
                    Write-Log "  - File system health status: Not Healthy"
                }
                if ($hasBadSectors) {
                    Write-Log "  - Bad sectors detected (physical disk failure)"
                }
                if ($needsRepair) {
                    Write-Log "  - File system marked as dirty (needs chkdsk)"
                }
                if ($diskHealth.BitLockerEncrypted) {
                    Write-Log "  - BitLocker encrypted (ensure recovery key available)"
                }
                
                # Show warnings and recommendations
                if ($diskHealth.Warnings -and (Get-SafeCount $diskHealth.Warnings) -gt 0) {
                    foreach ($warning in $diskHealth.Warnings) {
                        Write-Log "  - $warning"
                    }
                }
                if ($diskHealth.Recommendations -and (Get-SafeCount $diskHealth.Recommendations) -gt 0) {
                    foreach ($rec in $diskHealth.Recommendations) {
                        Write-Log "  Recommendation: $rec"
                    }
                }
                
                # Only show CRITICAL hardware failure if it's actually hardware failure
                if ($criticalHardwareFailure) {
                    Write-Log ""
                    Write-Log "[CRITICAL] Hardware failure detected. Software repairs NOT recommended."
                    Write-Log "Please backup data and replace hardware before continuing."
                    if ($txtOneClickStatus) {
                        $txtOneClickStatus.Text = "CRITICAL: Hardware failure detected. Backup data immediately!"
                    }
                    Update-StatusBar -Message "One-Click Repair: Hardware failure detected - STOPPED" -HideProgress
                    
                    # Save log and exit
                    try {
                        $logContent.ToString() | Out-File -FilePath $logFile -Encoding UTF8 -Force
                        Start-Process notepad.exe -ArgumentList $logFile -ErrorAction SilentlyContinue
                    } catch { }
                    $btnOneClickRepair.IsEnabled = $true
                    return
                } elseif (-not $canProceed) {
                    # Less critical but still can't proceed
                    Write-Log ""
                    Write-Log "[WARNING] Disk issues detected. Software repairs may not be effective."
                    Write-Log "Consider running chkdsk first, or backup data before proceeding."
                }
            }
            Write-Log ""
            
            # Step 2: Check for missing storage drivers
            if ($txtOneClickStatus) {
                $txtOneClickStatus.Text = "Step 2/5: Checking for missing storage drivers..."
            }
            Update-StatusBar -Message "One-Click Repair: Checking storage drivers..." -ShowProgress
            
            Write-Log "Step 2: Storage Driver Check"
            Write-Log "---------------------------------------------------------------"
            Write-CommandLog -Command "Get-MissingStorageDevices" -Description "Check for missing or errored storage controller drivers" -IsRepairCommand:$false
            
            # Diagnostic commands are read-only, so run them even in test mode
            $missingDevices = Get-MissingStorageDevices
            $missingDrivers = @()
            if ($missingDevices -and $missingDevices -ne "No missing or errored storage drivers detected.`n`nNote: Devices with non-zero error codes that are not error codes 1, 3, or 28 (missing driver codes) are excluded to reduce false positives.") {
                # Parse the missing devices string to count them
                $missingDrivers = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
                    ($_.ConfigManagerErrorCode -eq 28 -or $_.ConfigManagerErrorCode -eq 1 -or $_.ConfigManagerErrorCode -eq 3) -and
                    ($_.Class -match 'SCSI|Storage|System|DiskDrive' -or $_.FriendlyName -match 'VMD|RAID|NVMe|Storage|Controller')
                })
            }
            
            if ((Get-SafeCount $missingDrivers) -eq 0) {
                Write-Log "[OK] All storage drivers are loaded"
            } else {
                Write-Log "[WARNING] Missing storage drivers detected:"
                foreach ($device in $missingDrivers) {
                    $hwid = "Unknown"
                    if ($device.HardwareID) {
                        $hwidArray = @($device.HardwareID)
                        if ((Get-SafeCount $hwidArray) -gt 0) {
                            $hwid = $hwidArray[0]
                        }
                    }
                    Write-Log "  - $($device.FriendlyName) (Error Code: $($device.ConfigManagerErrorCode), Hardware ID: $hwid)"
                }
                Write-Log ""
                Write-Log "Note: Driver injection may be needed if boot fails."
            }
            Write-Log ""
            
            # Step 3: BCD Integrity Check
            if ($txtOneClickStatus) {
                $txtOneClickStatus.Text = "Step 3/5: Checking Boot Configuration Data (BCD)..."
            }
            Update-StatusBar -Message "One-Click Repair: Checking BCD integrity..." -ShowProgress
            
            Write-Log "Step 3: BCD Integrity Check"
            Write-Log "---------------------------------------------------------------"
            Write-CommandLog -Command "bcdedit /enum all" -Description "Check BCD integrity and accessibility" -IsRepairCommand:$false
            
            # Diagnostic commands are read-only, so run them even in test mode
            try {
                # First, check if BCD exists and recreate if missing (with short timeout to prevent hanging)
                Write-Log "Checking if BCD file exists and is accessible..."
                # Use shorter timeout (5 seconds) to fail fast
                $bcdCheckResult = Test-AndRecreateBCD -Drive $drive -WriteLogFunction ${function:Write-Log} -TimeoutSeconds 5
                
                # If BCD was recreated, wait a moment for it to be available
                if ($bcdCheckResult.Success -and $bcdCheckResult.Message -match "recreated") {
                    Write-Log "[INFO] BCD was recreated, waiting for system to flush..."
                    Start-Sleep -Seconds 2
                }
                
                # Handle different BCD check results
                if (-not $bcdCheckResult.Success) {
                    # BCD check failed or BCD doesn't exist - need to recreate
                    Write-Log "[INFO] BCD check failed or BCD is missing - will attempt recreation"
                    $bcdCheck = "BCD_MISSING_OR_INACCESSIBLE"
                } elseif ($bcdCheckResult.Message -match "recreated") {
                    # BCD was just recreated - skip detailed check
                    Write-Log "[INFO] BCD was just recreated - skipping detailed check"
                    $bcdCheck = "SKIPPED - BCD was just recreated"
                } elseif ($bcdCheckResult.Message -match "BCD is accessible") {
                    # BCD exists and is accessible - run detailed check
                    Write-Log "Running bcdedit /enum all (with 5 second timeout - fast fail)..."
                    $bcdCheck = $null
                    $bcdJob = Start-Job -ScriptBlock {
                        param($drive)
                        bcdedit /enum all 2>&1 | Out-String
                    } -ArgumentList $drive
                    
                    $bcdCheck = Wait-Job -Job $bcdJob -Timeout 5 | Receive-Job
                    Stop-Job -Job $bcdJob -ErrorAction SilentlyContinue
                    Remove-Job -Job $bcdJob -ErrorAction SilentlyContinue
                    
                    if ($null -eq $bcdCheck) {
                        Write-Log "[WARNING] BCD check timed out after 5 seconds - BCD may be locked or corrupted"
                        Write-Log "Skipping detailed BCD check and proceeding to boot file verification"
                        $bcdCheck = "TIMEOUT - BCD check exceeded 5 seconds"
                    } else {
                        Write-Log "BCD Check Output: $($bcdCheck.Substring(0, [Math]::Min(200, $bcdCheck.Length)))..."
                    }
                } else {
                    # Unknown state - treat as missing
                    Write-Log "[WARNING] BCD state unclear - treating as missing"
                    $bcdCheck = "BCD_STATE_UNKNOWN"
                }
                
                # Check if BCD needs to be rebuilt
                if ($bcdCheck -match "BCD_MISSING_OR_INACCESSIBLE" -or
                    $bcdCheck -match "BCD_STATE_UNKNOWN" -or
                    $bcdCheck -match "The boot configuration data store could not be opened" -or
                    $bcdCheck -match "The system cannot find the file specified" -or
                    $bcdCheck -match "The system cannot find the path specified" -or
                    $bcdCheck -match "TIMEOUT") {
                    
                    # Determine if this is a missing BCD or corrupted BCD
                    if ($bcdCheck -match "BCD_MISSING_OR_INACCESSIBLE" -or $bcdCheck -match "BCD_STATE_UNKNOWN") {
                        Write-Log "[INFO] BCD file is missing - attempting to create new BCD using bcdboot..."
                    } else {
                        Write-Log "[ERROR] BCD is corrupted or inaccessible"
                        Write-Log "Action: Attempting to rebuild BCD using bcdboot..."
                    }
                    
                    # Attempt BCD rebuild using bcdboot (more reliable than bootrec for UEFI)
                    if ($txtOneClickStatus) {
                        $txtOneClickStatus.Text = "Step 3/5: Rebuilding BCD..."
                    }
                    Update-StatusBar -Message "One-Click Repair: Rebuilding BCD..." -ShowProgress
                    
                    # Try to mount EFI partition and use bcdboot
                    $efiDrive = $null
                    try {
                        $efiMount = Mount-EFIPartition -WindowsDrive $drive -PreferredLetter "S"
                        if ($efiMount.Success) {
                            $efiDrive = $efiMount.DriveLetter
                            Write-Log "[OK] EFI partition mounted as $efiDrive`:"
                            
                            $command = "bcdboot $drive`:\Windows /s $efiDrive`: /f UEFI"
                            Write-CommandLog -Command $command -Description "Rebuild Boot Configuration Data using bcdboot" -IsRepairCommand:$true
                            
                            if (-not $testMode) {
                                try {
                                    $bcdRebuild = & bcdboot "$drive`:\Windows" /s "$efiDrive`:" /f UEFI 2>&1 | Out-String
                                    Write-Log "BCD Rebuild Output: $bcdRebuild"
                                    
                                    if ($LASTEXITCODE -eq 0 -or $bcdRebuild -match "Boot files successfully created") {
                                        Write-Log "[SUCCESS] BCD rebuilt successfully using bcdboot"
                                    } else {
                                        Write-Log "[WARNING] bcdboot reported issues: $bcdRebuild"
                                    }
                                } catch {
                                    Write-Log "[WARNING] BCD rebuild failed: $_"
                                }
                            } else {
                                Write-Log "  [SKIPPED] Repair command not executed (Test Mode Active)"
                            }
                        } else {
                            Write-Log "[WARNING] Could not mount EFI partition: $($efiMount.Message)"
                        }
                    } catch {
                        Write-Log "[WARNING] EFI partition mount failed: $_"
                    }
                    
                    # Fallback: Check if bootrec.exe is available (only in WinRE/WinPE)
                    if (-not $efiDrive) {
                        $bootrecPath = $null
                        $bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
                        if ($bootrecCmd) {
                            $bootrecPath = $bootrecCmd.Source
                        } else {
                            # Try common WinRE paths
                            $possiblePaths = @(
                                "$env:SystemRoot\System32\bootrec.exe",
                                "X:\Windows\System32\bootrec.exe",
                                "C:\Windows\System32\Recovery\bootrec.exe"
                            )
                            foreach ($path in $possiblePaths) {
                                if (Test-Path $path) {
                                    $bootrecPath = $path
                                    break
                                }
                            }
                        }
                        
                        if ($bootrecPath) {
                            $command = "$bootrecPath /rebuildbcd"
                            Write-CommandLog -Command $command -Description "Rebuild Boot Configuration Data using bootrec" -IsRepairCommand:$true
                            
                            if (-not $testMode) {
                                try {
                                    $bcdRebuild = & $bootrecPath /rebuildbcd 2>&1 | Out-String
                                    Write-Log "BCD Rebuild Output: $bcdRebuild"
                                } catch {
                                    Write-Log "[WARNING] BCD rebuild failed: $_"
                                    Write-Log "Note: bootrec.exe may not be available in this environment."
                                    Write-Log "Consider using bcdboot.exe or running from WinRE instead."
                                }
                            } else {
                                Write-Log "  [SKIPPED] Repair command not executed (Test Mode Active)"
                            }
                        } else {
                            Write-Log "[INFO] bootrec.exe not available in this environment."
                            Write-Log "This is normal in a regular Windows session. bootrec.exe is only available in WinRE/WinPE."
                            Write-Log "Alternative command: bcdboot $drive`:\Windows /s <ESP_DRIVE>:"
                        }
                    }
                } else {
                    Write-Log "[OK] BCD is accessible and appears healthy"
                }
                Write-Log ""
            } catch {
                Write-Log "[WARNING] Could not verify BCD: $_"
                Write-Log ""
            }
            
            # Step 4: Boot File Check
            if ($txtOneClickStatus) {
                $txtOneClickStatus.Text = "Step 4/5: Checking boot files..."
            }
            Update-StatusBar -Message "One-Click Repair: Checking boot files..." -ShowProgress
            
            Write-Log "Step 4: Boot File Check"
            Write-Log "---------------------------------------------------------------"
            Write-CommandLog -Command "Test-Path (boot files)" -Description "Check for critical boot files (bootmgfw.efi, winload.efi, winload.exe)" -IsRepairCommand:$false
            
            # Diagnostic commands are read-only, so run them even in test mode
            # Check boot files in both EFI partition and Windows directory
            $bootFiles = @(
                @{Name="bootmgfw.efi"; EFIPath="\EFI\Microsoft\Boot\bootmgfw.efi"; WinPath="\Windows\System32\bootmgfw.efi"},
                @{Name="winload.efi"; EFIPath="\EFI\Microsoft\Boot\winload.efi"; WinPath="\Windows\System32\winload.efi"},
                @{Name="winload.exe"; EFIPath="\EFI\Microsoft\Boot\winload.exe"; WinPath="\Windows\System32\winload.exe"}
            )
            
            $missingFiles = @()
            $fileLocations = @{}
            
            # First, try to find EFI partition
            $efiDrive = $null
            try {
                $efiMount = Mount-EFIPartition -WindowsDrive $drive -PreferredLetter "S"
                if ($efiMount.Success) {
                    $efiDrive = $efiMount.DriveLetter
                    Write-Log "[OK] EFI partition mounted as $efiDrive`:"
                } else {
                    Write-Log "[INFO] Could not auto-mount EFI partition: $($efiMount.Message)"
                    Write-Log "Will check Windows directory for boot files instead."
                }
            } catch {
                Write-Log "[INFO] EFI partition mount check failed: $_"
            }
            
            foreach ($file in $bootFiles) {
                $found = $false
                $location = ""
                
                # Check EFI partition first (if mounted)
                if ($efiDrive) {
                    $efiPath = "$efiDrive`:$($file.EFIPath)"
                    if (Test-Path $efiPath) {
                        $found = $true
                        $location = "EFI partition ($efiDrive`:)"
                    }
                }
                
                # Check Windows directory
                if (-not $found) {
                    $winPath = "$drive`:$($file.WinPath)"
                    if (Test-Path $winPath) {
                        $found = $true
                        $location = "Windows directory ($drive`:)"
                    }
                }
                
                if (-not $found) {
                    $missingFiles += $file.Name
                    Write-Log "[MISSING] $($file.Name) - not found in EFI partition or Windows directory"
                } else {
                    Write-Log "[OK] $($file.Name) found in $location"
                    $fileLocations[$file.Name] = $location
                }
            }
            
            if ((Get-SafeCount $missingFiles) -eq 0) {
                Write-Log "[OK] All critical boot files are present"
            } else {
                Write-Log "[WARNING] Missing boot files:"
                foreach ($file in $missingFiles) {
                    Write-Log "  - $file"
                }
                Write-Log "Action: Attempting to repair boot files..."
                
                # Attempt boot file repair
                if ($txtOneClickStatus) {
                    $txtOneClickStatus.Text = "Step 4/5: Repairing boot files..."
                }
                Update-StatusBar -Message "One-Click Repair: Repairing boot files..." -ShowProgress
                
                # Use bcdboot to repair boot files (more reliable than bootrec for UEFI)
                # First ensure EFI partition is mounted - CRITICAL STEP
                if (-not $efiDrive) {
                    Write-Log "==============================================================="
                    Write-Log "CRITICAL: EFI partition must be mounted for boot file repair"
                    Write-Log "==============================================================="
                    Write-Log "Attempting to mount EFI partition..."
                    
                    # Method 1: Try Mount-EFIPartition function
                    $efiMount = Mount-EFIPartition -WindowsDrive $drive -PreferredLetter "S"
                    if ($efiMount.Success) {
                        $efiDrive = $efiMount.DriveLetter
                        Write-Log "[SUCCESS] EFI partition mounted as $efiDrive`: (Method 1: Set-Partition/diskpart)"
                    } else {
                        Write-Log "[WARNING] Method 1 failed: $($efiMount.Message)"
                        Write-Log "Trying Method 2: mountvol /S (Windows system EFI mount)..."
                        
                        # Method 2: Try mountvol /S (mounts system EFI partition)
                        try {
                            $mountvolOutput = & mountvol S: /S 2>&1 | Out-String
                            Start-Sleep -Seconds 1
                            
                            # Verify S: is now the EFI partition
                            if (Test-Path "S:\EFI\Microsoft\Boot") {
                                $efiDrive = "S"
                                Write-Log "[SUCCESS] EFI partition mounted as S`: (Method 2: mountvol /S)"
                            } else {
                                Write-Log "[WARNING] mountvol /S succeeded but EFI path not found"
                                
                                # Method 3: Try to find EFI partition manually and assign letter
                                Write-Log "Trying Method 3: Manual EFI partition detection and mount..."
                                try {
                                    # Get Windows partition to find disk
                                    $winPartition = Get-Partition -DriveLetter $drive -ErrorAction SilentlyContinue
                                    if ($winPartition) {
                                        $diskNumber = $winPartition.DiskNumber
                                        
                                        # Find EFI partition on same disk
                                        $efiPartitions = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue | Where-Object {
                                            $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
                                        }
                                        
                                        if ($efiPartitions -and $efiPartitions.Count -gt 0) {
                                            $efiPart = $efiPartitions[0]
                                            Write-Log "Found EFI partition: Disk $diskNumber, Partition $($efiPart.PartitionNumber)"
                                            
                                            # Try to assign drive letter using diskpart
                                            $partNumber = $efiPart.PartitionNumber
                                            $diskpartScript = @"
select disk $diskNumber
select partition $partNumber
assign letter=S
active
exit
"@
                                            $scriptPath = Join-Path $env:TEMP "mount_efi_force.txt"
                                            $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
                                            
                                            Write-Log "Running diskpart to assign drive letter S: to EFI partition..."
                                            $diskpartOutput = diskpart /s $scriptPath 2>&1 | Out-String
                                            Remove-Item $scriptPath -ErrorAction SilentlyContinue
                                            Write-Log "Diskpart Output: $diskpartOutput"
                                            
                                            Start-Sleep -Seconds 2
                                            
                                            # Verify mount
                                            if (Test-Path "S:\EFI\Microsoft\Boot") {
                                                $efiDrive = "S"
                                                Write-Log "[SUCCESS] EFI partition mounted as S`: (Method 3: diskpart manual mount)"
                                            } else {
                                                Write-Log "[ERROR] diskpart succeeded but EFI path still not accessible"
                                            }
                                        } else {
                                            Write-Log "[ERROR] Could not find EFI partition on disk $diskNumber"
                                        }
                                    } else {
                                        Write-Log "[ERROR] Could not get partition info for Windows drive $drive`:"
                                    }
                                } catch {
                                    Write-Log "[ERROR] Method 3 failed: $_"
                                }
                            }
                        } catch {
                            Write-Log "[ERROR] mountvol /S failed: $_"
                        }
                    }
                    
                    # Final check - if still not mounted, we cannot proceed
                    if (-not $efiDrive) {
                        Write-Log ""
                        Write-Log "==============================================================="
                        Write-Log "CRITICAL ERROR: EFI PARTITION CANNOT BE MOUNTED"
                        Write-Log "==============================================================="
                        Write-Log ""
                        Write-Log "Boot file repair CANNOT proceed without a mounted EFI partition."
                        Write-Log "bcdboot requires a drive letter to write boot files."
                        Write-Log ""
                        Write-Log "MANUAL FIX REQUIRED:"
                        Write-Log "  1. Open Command Prompt as Administrator"
                        Write-Log "  2. Run: mountvol S: /S"
                        Write-Log "  3. Verify: dir S:\EFI\Microsoft\Boot"
                        Write-Log "  4. If that fails, use diskpart:"
                        Write-Log "     diskpart"
                        Write-Log "     list disk"
                        Write-Log "     select disk X (where X is your Windows disk)"
                        Write-Log "     list partition"
                        Write-Log "     select partition Y (find the ~100MB EFI partition)"
                        Write-Log "     assign letter=S"
                        Write-Log "     exit"
                        Write-Log ""
                        Write-Log "After mounting, re-run One-Click Repair."
                        Write-Log ""
                        
                        # Add to repair report
                        if ($repairReport) {
                            Add-RepairIssue -Report $repairReport -Issue "EFI partition cannot be mounted" -Severity "Critical" -Details "All mount methods failed. Manual mount required before repair can proceed."
                            Add-Recommendation -Report $repairReport -Recommendation "Run 'mountvol S: /S' in Administrator Command Prompt, then re-run repair"
                        }
                        
                        throw "EFI partition mount failed - cannot proceed with boot file repair"
                    }
                }
                
                Write-Log "[OK] EFI partition is mounted and ready: $efiDrive`:"
                Write-Log ""
                
                if ($efiDrive) {
                    # Use Defensive Boot-Chain Logic if available, otherwise fallback to standard repair
                    $useDefensiveLogic = $false
                    if (Get-Command "Invoke-DefensiveBootRepair" -ErrorAction SilentlyContinue) {
                        try {
                            Write-Log "Using Defensive Boot-Chain Logic for professional-grade repair..."
                            $defensiveResult = Invoke-DefensiveBootRepair -PreferredDrive $drive
                            
                            if ($defensiveResult.Success) {
                                Write-Log "[SUCCESS] Defensive Boot-Chain Repair completed successfully"
                                Write-Log $defensiveResult.Report
                                
                                # Update verification status
                                if ($defensiveResult.Verification.WinloadExists) {
                                    Write-Log "[OK] winload.efi verified in Windows directory"
                                }
                                if ($defensiveResult.Verification.BCDValid) {
                                    Write-Log "[OK] BCD verified and valid"
                                }
                                
                                # Show warnings if any
                                foreach ($warning in $defensiveResult.Warnings) {
                                    Write-Log "[WARNING] $warning"
                                }
                                
                                $useDefensiveLogic = $true
                            } else {
                                Write-Log "[WARNING] Defensive Boot-Chain Repair completed with errors"
                                Write-Log $defensiveResult.Report
                                
                                # Show errors
                                foreach ($errorItem in $defensiveResult.Errors) {
                                    Write-Log "[ERROR] $errorItem"
                                }
                                
                                # If blocked by BitLocker, stop here
                                if ($defensiveResult.Errors | Where-Object { $_ -match "BitLocker LOCKED" }) {
                                    Write-Log "[BLOCKED] Cannot proceed - drive is BitLocker locked"
                                    throw "Drive is BitLocker locked. Unlock drive before repairs."
                                }
                                
                                # Continue with fallback repair if not blocked
                                Write-Log "Falling back to standard repair method..."
                            }
                        } catch {
                            Write-Log "[WARNING] Defensive Boot-Chain Logic failed: $_"
                            Write-Log "Falling back to standard repair method..."
                        }
                    }
                    
                    # Standard repair method (fallback or if defensive logic not available)
                    if (-not $useDefensiveLogic) {
                        # CRITICAL: Restore winload.efi in Windows directory FIRST (before bcdboot)
                        Write-Log "==============================================================="
                        Write-Log "STEP 1: RESTORE WINLOAD.EFI IN WINDOWS DIRECTORY"
                        Write-Log "==============================================================="
                        Write-Log "bcdboot requires winload.efi to exist in Windows directory before it can copy to EFI partition."
                        Write-Log ""
                        
                        $winloadWindowsPath = "$drive`:\Windows\System32\winload.efi"
                        $winloadBootPath = "$drive`:\Windows\System32\Boot\winload.efi"
                        $winloadMissing = -not (Test-Path $winloadWindowsPath)
                    
                        if ($winloadMissing) {
                            Write-Log "[CRITICAL] winload.efi is missing from Windows directory: $winloadWindowsPath"
                            Write-Log "This MUST be fixed before bcdboot can copy it to EFI partition."
                            Write-Log ""
                            
                            # Step 1a: Check source template folder first (fastest method)
                            Write-Log "Step 1a: Checking source template folder ($winloadBootPath)..."
                            
                            # Check the "Source" folder - bcdboot works by copying files from C:\Windows\System32\Boot
                            if (Test-Path $winloadBootPath) {
                            Write-Log "[INFO] Source template found in Boot folder: $winloadBootPath"
                            Write-Log "Copying from Boot folder to System32..."
                            if (-not $testMode) {
                                try {
                                    # If destination exists and is protected by TrustedInstaller, take ownership first
                                    if (Test-Path $winloadWindowsPath) {
                                        Write-Log "[INFO] Destination file exists - checking if ownership/permissions need adjustment..."
                                        $ownershipResult = Set-FileOwnershipAndPermissions -FilePath $winloadWindowsPath -WriteLogFunction ${function:Write-Log}
                                        if (-not $ownershipResult.Success) {
                                            Write-Log "[WARNING] Could not set ownership/permissions: $($ownershipResult.Message)"
                                            Write-Log "[WARNING] Attempting copy anyway (may fail if protected)..."
                                        }
                                    }
                                    
                                    Copy-Item $winloadBootPath $winloadWindowsPath -Force -ErrorAction Stop
                                    if (Test-Path $winloadWindowsPath) {
                                        Write-Log "[SUCCESS] winload.efi copied from Boot folder to System32"
                                    }
                                } catch {
                                    Write-Log "[WARNING] Failed to copy from Boot folder: $_"
                                    Write-Log "The issue may be that the destination is protected by TrustedInstaller or write-protected."
                                    Write-Log "Attempting to take ownership and retry..."
                                    
                                    # Retry with ownership/permissions
                                    $ownershipResult = Set-FileOwnershipAndPermissions -FilePath $winloadWindowsPath -WriteLogFunction ${function:Write-Log}
                                    if ($ownershipResult.Success) {
                                        try {
                                            Copy-Item $winloadBootPath $winloadWindowsPath -Force -ErrorAction Stop
                                            Write-Log "[SUCCESS] winload.efi copied after taking ownership"
                                        } catch {
                                            Write-Log "[ERROR] Copy still failed after taking ownership: $_"
                                        }
                                    }
                                }
                            } else {
                                Write-CommandLog -Command "Copy-Item $winloadBootPath $winloadWindowsPath" -Description "Copy winload.efi from Boot folder to System32" -IsRepairCommand:$true
                            }
                        } else {
                            Write-Log "[WARNING] Source template missing from Boot folder: $winloadBootPath"
                            Write-Log "The 'template' is gone. Attempting to restore winload.efi from Windows Component Store..."
                            
                            if (-not $testMode) {
                                try {
                                    # Try to restore winload.efi using DISM
                                    Write-Log "Running: DISM /Image:$drive`: /RestoreHealth"
                                    $dismOutput = & dism /Image:"$drive`:" /RestoreHealth 2>&1 | Out-String
                                    Write-Log "DISM Output: $dismOutput"
                                    
                                    # Also try SFC to restore system files
                                    Write-Log "Running: SFC /ScanNow /OffBootDir=$drive`: /OffWinDir=$drive`:\Windows"
                                    $sfcOutput = & sfc /ScanNow /OffBootDir="$drive`:" /OffWinDir="$drive`:\Windows" 2>&1 | Out-String
                                    Write-Log "SFC Output: $sfcOutput"
                                    
                                    # Check if winload.efi was restored
                                    Start-Sleep -Seconds 2
                                    if (Test-Path $winloadWindowsPath) {
                                        Write-Log "[SUCCESS] winload.efi restored to Windows directory"
                                    } else {
                                        Write-Log "[WARNING] winload.efi still missing after DISM/SFC."
                                        Write-Log "Step 5: Attempting manual extraction from Windows installation media (install.wim/install.esd)..."
                                        
                                        # Step 5: Manual Extraction (The "Infallible" Fix)
                                        # Search for install.wim or install.esd in common locations
                                        $installMediaPaths = @(
                                            "X:\sources\install.wim",
                                            "X:\sources\install.esd",
                                            "D:\sources\install.wim",
                                            "D:\sources\install.esd",
                                            "E:\sources\install.wim",
                                            "E:\sources\install.esd"
                                        )
                                        
                                        $foundMedia = $false
                                        foreach ($mediaPath in $installMediaPaths) {
                                            if (Test-Path $mediaPath) {
                                                Write-Log "[INFO] Found Windows installation media: $mediaPath"
                                                Write-Log "Attempting to extract winload.efi using DISM..."
                                                
                                                # Get WIM info to find the correct index
                                                $wimInfo = & dism /Get-WimInfo /WimFile:$mediaPath 2>&1 | Out-String
                                                Write-Log "WIM Info: $wimInfo"
                                                
                                                # Try index 1 (usually Windows Pro/Home)
                                                $extractCmd = "dism /Image:$drive`: /RestoreHealth /Source:$mediaPath`:1"
                                                Write-Log "Running: $extractCmd"
                                                $extractOutput = & dism /Image:"$drive`:" /RestoreHealth /Source:"$mediaPath`:1" 2>&1 | Out-String
                                                Write-Log "Extract Output: $extractOutput"
                                                
                                                Start-Sleep -Seconds 2
                                                if (Test-Path $winloadWindowsPath) {
                                                    Write-Log "[SUCCESS] winload.efi extracted from installation media"
                                                    $foundMedia = $true
                                                    break
                                                }
                                            }
                                        }
                                        
                                        if (-not $foundMedia) {
                                            Write-Log "[ERROR] Could not find Windows installation media (install.wim/install.esd)"
                                            Write-Log "Please attach Windows ISO/USB and ensure it's accessible, then retry."
                                        }
                                    }
                                } catch {
                                    Write-Log "[ERROR] Failed to restore winload.efi: $_"
                                }
                            } else {
                                Write-CommandLog -Command "DISM /Image:$drive`: /RestoreHealth" -Description "Restore winload.efi from Component Store" -IsRepairCommand:$true
                                Write-CommandLog -Command "SFC /ScanNow /OffBootDir=$drive`: /OffWinDir=$drive`:\Windows" -Description "Restore system files using SFC" -IsRepairCommand:$true
                                Write-Log "  [SKIPPED] winload.efi restore not executed (Test Mode Active)"
                            }
                        }
                        
                        # CRITICAL: Verify winload.efi exists before proceeding to bcdboot
                        Write-Log ""
                        Write-Log "Verifying winload.efi exists in Windows directory..."
                        if (-not (Test-Path $winloadWindowsPath)) {
                            Write-Log ""
                            Write-Log "==============================================================="
                            Write-Log "CRITICAL ERROR: WINLOAD.EFI STILL MISSING"
                            Write-Log "==============================================================="
                            Write-Log "Cannot proceed with bcdboot - source file does not exist."
                            Write-Log "Location checked: $winloadWindowsPath"
                            Write-Log ""
                            Write-Log "All restoration methods have been attempted."
                            Write-Log "Manual intervention required - see error details above."
                            Write-Log ""
                            
                            # Add to repair report
                            if ($repairReport) {
                                Add-RepairIssue -Report $repairReport -Issue "winload.efi missing from Windows directory" -Severity "Critical" -Details "File not found at $winloadWindowsPath. All restoration methods failed."
                                Add-Recommendation -Report $repairReport -Recommendation "Extract winload.efi from Windows installation media using DISM or manually copy from working system"
                            }
                            
                            throw "winload.efi missing from Windows directory - cannot proceed with boot file repair"
                        } else {
                            Write-Log "[SUCCESS] winload.efi verified in Windows directory: $winloadWindowsPath"
                        }
                    }
                    
                    # Final verification before proceeding
                    Write-Log ""
                    if (Test-Path $winloadWindowsPath) {
                        Write-Log "[OK] winload.efi verified - ready for bcdboot"
                    } else {
                        Write-Log "[ERROR] winload.efi verification failed - cannot proceed"
                        throw "winload.efi verification failed"
                    }
                    Write-Log ""
                    }  # End of if ($winloadMissing) block
                    
                    # Step 2: Verify file attributes (clear hidden/system if needed)
                    if (Test-Path $winloadWindowsPath) {
                        Write-Log "Step 2: Verifying file attributes..."
                        if (-not $testMode) {
                            try {
                                # First ensure we have ownership/permissions
                                $ownershipResult = Set-FileOwnershipAndPermissions -FilePath $winloadWindowsPath -WriteLogFunction ${function:Write-Log}
                                if (-not $ownershipResult.Success) {
                                    Write-Log "[WARNING] Could not set ownership/permissions: $($ownershipResult.Message)"
                                }
                                
                                # Clear any problematic attributes using attrib
                                $attribResult = & attrib -s -h -r $winloadWindowsPath 2>&1 | Out-String
                                if ($LASTEXITCODE -ne 0) {
                                    # Fallback: Use Set-ItemProperty if attrib fails
                                    Write-Log "[INFO] attrib failed, trying Set-ItemProperty fallback..."
                                    try {
                                        Set-ItemProperty -Path $winloadWindowsPath -Name IsReadOnly -Value $false -ErrorAction Stop
                                        Write-Log "[OK] File attributes verified (using Set-ItemProperty)"
                                    } catch {
                                        Write-Log "[WARNING] Could not modify file attributes: $_"
                                    }
                                } else {
                                    Write-Log "[OK] File attributes verified"
                                }
                            } catch {
                                Write-Log "[WARNING] Could not modify file attributes: $_"
                            }
                        }
                    }
                    
                    # Step 3: Clear read-only attributes on EFI boot files BEFORE bcdboot
                    Write-Log "Step 3a: Clearing read-only attributes on EFI boot files..."
                    if (-not $testMode) {
                        try {
                            $efiBootPath = "$efiDrive`:\EFI\Microsoft\Boot"
                            if (Test-Path $efiBootPath) {
                                # Clear attributes on all boot files using attrib
                                $attribOutput = & attrib -r -s -h "$efiBootPath\*.*" 2>&1 | Out-String
                                if ($LASTEXITCODE -ne 0) {
                                    # Fallback: Use Set-ItemProperty if attrib fails
                                    Write-Log "[INFO] attrib failed, trying Set-ItemProperty fallback for EFI files..."
                                    try {
                                        Get-ChildItem -Path $efiBootPath -File | ForEach-Object {
                                            try {
                                                Set-ItemProperty -Path $_.FullName -Name IsReadOnly -Value $false -ErrorAction Stop
                                            } catch {
                                                Write-Log "[WARNING] Could not clear read-only on $($_.Name): $_"
                                            }
                                        }
                                        Write-Log "[OK] Read-only attributes cleared on EFI boot files (using Set-ItemProperty)"
                                    } catch {
                                        Write-Log "[WARNING] Set-ItemProperty fallback also failed: $_"
                                    }
                                } else {
                                    Write-Log "Attrib Output: $attribOutput"
                                    Write-Log "[OK] Read-only attributes cleared on EFI boot files"
                                }
                            }
                        } catch {
                            Write-Log "[WARNING] Could not clear attributes: $_"
                        }
                    } else {
                        Write-CommandLog -Command "attrib -r -s -h $efiDrive`:\EFI\Microsoft\Boot\*.*" -Description "Clear read-only attributes on EFI boot files" -IsRepairCommand:$true
                    }
                    
                    # Step 3b: Check for Intel VMD before attempting write operations
                    Write-Log "Step 3b: Checking for Intel VMD driver issues..."
                    $vmdIssue = $null
                    if (Get-Command "Test-VMDDriverIssue" -ErrorAction SilentlyContinue) {
                        $vmdIssue = Test-VMDDriverIssue
                        if ($vmdIssue.VMDDetected -and -not $vmdIssue.DriverLoaded) {
                            Write-Log "[CRITICAL] Intel VMD detected without driver!"
                            Write-Log "  Hardware ID: $($vmdIssue.HardwareID)"
                            Write-Log "  This may prevent bcdboot from writing to the NVMe drive."
                            Write-Log ""
                            Write-Log "RECOMMENDATION:"
                            Write-Log "  1. Check BIOS -> Storage Configuration -> Intel VMD"
                            Write-Log "  2. If VMD is enabled, either:"
                            Write-Log "     a) Disable VMD in BIOS (may require reinstall if originally installed with VMD on)"
                            Write-Log "     b) Load VMD driver in WinPE: drvload [path]\iaStorVD.inf"
                            if ($vmdIssue.DriverPath) {
                                Write-Log "     Driver found at: $($vmdIssue.DriverPath)"
                            }
                            Write-Log ""
                            
                            # Show warning to user
                            if ($txtOneClickStatus) {
                                $txtOneClickStatus.Text = "WARNING: Intel VMD detected - boot repair may fail"
                            }
                        } else {
                            Write-Log "[OK] VMD status: $($vmdIssue.Recommendation)"
                        }
                    }
                    
                    # Step 3c: Use bcdboot to repair boot files (copies from Windows to EFI)
                    $bcdbootCmd = "bcdboot $drive`:\Windows /s $efiDrive`: /f UEFI /v"
                    Write-CommandLog -Command $bcdbootCmd -Description "Repair boot files using bcdboot (copies winload.efi and other boot files to EFI partition) - VERBOSE MODE" -IsRepairCommand:$true
                    
                    if (-not $testMode) {
                        Invoke-BcdbootRepairWithFallback -Drive $drive -EfiDrive $efiDrive -VmdIssue $vmdIssue -WriteLogFunction ${function:Write-Log}
                    } else {
                        Write-Log "  [SKIPPED] Repair command not executed (Test Mode Active)"
                        Write-CommandLog -Command "bcdboot $drive`:\Windows /s $efiDrive`: /f UEFI /v" -Description "bcdboot command (TEST MODE)" -IsRepairCommand:$true
                    }
                    }  # End of if (-not $useDefensiveLogic) block
                } else {
                    try {
                        # Fallback: EFI partition not mounted - try bootrec if available
                        $bootrecPath = $null
                        $bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
                        if ($bootrecCmd) {
                            $bootrecPath = $bootrecCmd.Source
                        } else {
                            $possiblePaths = @(
                                "$env:SystemRoot\System32\bootrec.exe",
                                "X:\Windows\System32\bootrec.exe",
                                "C:\Windows\System32\Recovery\bootrec.exe"
                            )
                            foreach ($path in $possiblePaths) {
                                if (Test-Path $path) {
                                    $bootrecPath = $path
                                    break
                                }
                            }
                        }
                        
                        if ($bootrecPath) {
                            $command = "$bootrecPath /fixboot"
                            Write-CommandLog -Command $command -Description "Fix boot sector (fallback method)" -IsRepairCommand:$true
                            
                            if (-not $testMode) {
                                try {
                                    $bootFix = & $bootrecPath /fixboot 2>&1 | Out-String
                                    Write-Log "Boot File Repair Output: $bootFix"
                                } catch {
                                    Write-Log "[WARNING] Boot file repair failed: $_"
                                }
                            } else {
                                Write-Log "  [SKIPPED] Repair command not executed (Test Mode Active)"
                            }
                        } else {
                            Write-Log "[INFO] bootrec.exe not available and EFI partition could not be mounted."
                            Write-Log "Manual repair required:"
                            Write-Log "  1. Mount EFI partition using diskpart"
                            Write-Log "  2. Run: bcdboot $drive`:\Windows /s <ESP_DRIVE>: /f UEFI"
                        }
                    } catch {
                        Write-Log "[ERROR] Fallback boot repair (bootrec) failed: $_"
                        Write-Log "[INFO] Manual repair required:"
                        Write-Log "  1. Mount EFI partition using diskpart"
                        Write-Log "  2. Run: bcdboot $drive`:\Windows /s <ESP_DRIVE>: /f UEFI"
                    }
                }  # End of else block (EFI partition not mounted)
            Write-Log ""
            
            # Step 5: Final Summary
            if ($txtOneClickStatus) {
                $txtOneClickStatus.Text = "Step 5/5: Generating repair summary..."
            }
            Update-StatusBar -Message "One-Click Repair: Generating summary..." -ShowProgress
            
            Write-Log ""
            Write-Log "==============================================================="
            Write-Log "REPAIR SUMMARY"
            Write-Log "==============================================================="
            Write-Log ""
            
            $issuesFound = 0
            if (-not $diskHealth.FileSystemHealthy) { $issuesFound++ }
            if ((Get-SafeCount $missingDrivers) -gt 0) { $issuesFound++ }
            if ((Get-SafeCount $missingFiles) -gt 0) { $issuesFound++ }
            
            if ($testMode) {
                Write-Log "[TEST MODE] Summary of issues that would be repaired:"
                Write-Log "  - Disk Health: $(if ($diskHealth.FileSystemHealthy) { 'OK' } else { 'NEEDS REPAIR' })"
                Write-Log "  - Storage Drivers: $(if ((Get-SafeCount $missingDrivers) -gt 0) { "$(Get-SafeCount $missingDrivers) missing" } else { 'OK' })"
                Write-Log "  - Boot Files: $(if ((Get-SafeCount $missingFiles) -gt 0) { "$(Get-SafeCount $missingFiles) missing" } else { 'OK' })"
                Write-Log ""
                Write-Log "  (In TEST MODE - no repairs were actually executed)"
                if ($txtOneClickStatus) {
                    $txtOneClickStatus.Text = "✅ Test complete! Found $issuesFound issue(s) that would be repaired. (TEST MODE)"
                }
            } else {
                # POST-REPAIR VERIFICATION: Re-check to see if issues were fixed
                Write-Log "==============================================================="
                Write-Log "POST-REPAIR VERIFICATION"
                Write-Log "==============================================================="
                Write-Log ""
                
                # CRITICAL: Wait for file system caches to update after repairs
                Write-Log "[INFO] Waiting for file system caches to update after repairs..."
                Write-Log "This ensures newly created files are visible to verification checks."
                Start-Sleep -Seconds 3
                
                # Ensure EFI partition is still mounted for verification
                if (-not $efiDrive) {
                    Write-Log "[INFO] Re-mounting EFI partition for verification..."
                    $efiMount = Mount-EFIPartition -WindowsDrive $drive -PreferredLetter "S"
                    if ($efiMount.Success) {
                        $efiDrive = $efiMount.DriveLetter
                        Write-Log "[OK] EFI partition mounted as $efiDrive`: for verification"
                    } else {
                        Write-Log "[WARNING] Could not mount EFI partition for verification: $($efiMount.Message)"
                    }
                }
                
                Write-Log "Re-checking system to verify repairs..."
                
                $remainingIssues = 0
                $verificationResults = @()
                
                # Re-check boot files
                Write-Log "Re-checking boot files..."
                $stillMissingFiles = @()
                if ($efiDrive) {
                    foreach ($file in $bootFiles) {
                        $efiPath = "$efiDrive`:$($file.EFIPath)"
                        $winPath = "$drive`:$($file.WinPath)"
                        # For boot files, EFI partition location is primary, Windows directory is secondary
                        # winload.efi MUST be in EFI partition for booting, but can also be in Windows directory
                        if ($file.Name -eq "winload.efi") {
                            # winload.efi must be in EFI partition for UEFI boot
                            if (-not (Test-Path $efiPath)) {
                                $stillMissingFiles += $file.Name
                                Write-Log "[CHECK] winload.efi not found in EFI partition: $efiPath"
                            } else {
                                Write-Log "[OK] winload.efi found in EFI partition: $efiPath"
                            }
                        } else {
                            # Other boot files can be in either location
                            if (-not (Test-Path $efiPath) -and -not (Test-Path $winPath)) {
                                $stillMissingFiles += $file.Name
                            }
                        }
                    }
                } else {
                    # Re-mount EFI to check
                    $efiMount = Mount-EFIPartition -WindowsDrive $drive -PreferredLetter "S"
                    if ($efiMount.Success) {
                        $efiDrive = $efiMount.DriveLetter
                        foreach ($file in $bootFiles) {
                            $efiPath = "$efiDrive`:$($file.EFIPath)"
                            $winPath = "$drive`:$($file.WinPath)"
                            if ($file.Name -eq "winload.efi") {
                                if (-not (Test-Path $efiPath)) {
                                    $stillMissingFiles += $file.Name
                                }
                            } else {
                                if (-not (Test-Path $efiPath) -and -not (Test-Path $winPath)) {
                                    $stillMissingFiles += $file.Name
                                }
                            }
                        }
                    }
                }
                
                if ((Get-SafeCount $stillMissingFiles) -eq 0) {
                    Write-Log "[✅ FIXED] All boot files are now present"
                    $verificationResults += "Boot Files: FIXED"
                } else {
                    Write-Log "[❌ STILL MISSING] Boot files: $($stillMissingFiles -join ', ')"
                    Write-Log "[INFO] Re-checking after additional delay for file system cache..."
                    Start-Sleep -Seconds 2
                    
                    # Re-check with fresh cache
                    $stillMissingFilesRetry = @()
                    if ($efiDrive) {
                        foreach ($file in $bootFiles) {
                            $efiPath = "$efiDrive`:$($file.EFIPath)"
                            $winPath = "$drive`:$($file.WinPath)"
                            if ($file.Name -eq "winload.efi") {
                                if (-not (Test-Path $efiPath)) {
                                    $stillMissingFilesRetry += $file.Name
                                }
                            } else {
                                if (-not (Test-Path $efiPath) -and -not (Test-Path $winPath)) {
                                    $stillMissingFilesRetry += $file.Name
                                }
                            }
                        }
                    }
                    
                    if ((Get-SafeCount $stillMissingFilesRetry) -eq 0) {
                        Write-Log "[✅ FIXED] All boot files are now present (after cache refresh)"
                        $verificationResults += "Boot Files: FIXED"
                    } else {
                        $remainingIssues++
                        $verificationResults += "Boot Files: STILL MISSING ($(Get-SafeCount $stillMissingFilesRetry) files)"
                    }
                }
                
                # Re-check BCD
                Write-Log "Re-checking BCD..."
                try {
                    # First check if BCD file exists physically in EFI partition
                    $bcdFileExists = $false
                    $bcdAccessible = $false
                    $bcdCheckOutput = $null
                    if ($efiDrive) {
                        $efiBcdPath = "$efiDrive`:\EFI\Microsoft\Boot\BCD"
                        $bcdFileExists = Test-Path $efiBcdPath
                        if ($bcdFileExists) {
                            Write-Log "[OK] BCD file found in EFI partition: $efiBcdPath"
                        } else {
                            Write-Log "[CHECK] BCD file not found in EFI partition: $efiBcdPath"
                        }
                    }
                    
                    # Also check legacy BCD locations
                    $legacyBcdPaths = @(
                        "$env:SystemRoot\Boot\BCD",
                        "$env:SystemDrive\Boot\BCD"
                    )
                    foreach ($legacyPath in $legacyBcdPaths) {
                        if (Test-Path $legacyPath) {
                            $bcdFileExists = $true
                            Write-Log "[OK] BCD file found in legacy location: $legacyPath"
                            break
                        }
                    }
                    
                    # Always run bcdedit accessibility check (captures hidden/permissioned stores)
                    Write-Log "Checking BCD accessibility (with 5 second timeout - fast fail)..."
                    $bcdJob = Start-Job -ScriptBlock {
                        bcdedit /enum all 2>&1 | Out-String
                    }
                    $bcdCheckOutput = Wait-Job -Job $bcdJob -Timeout 5 | Receive-Job
                    Stop-Job -Job $bcdJob -ErrorAction SilentlyContinue
                    Remove-Job -Job $bcdJob -ErrorAction SilentlyContinue
                    
                    if ($null -eq $bcdCheckOutput) {
                        Write-Log "[⚠️  TIMEOUT] BCD check timed out - may still be initializing"
                        if ($bcdFileExists) {
                            Write-Log "[INFO] BCD file exists, but accessibility check timed out. This may be normal if BCD was just recreated."
                            $verificationResults += "BCD: EXISTS (accessibility check timeout - may be normal)"
                        } else {
                            Write-Log "[INFO] BCD file not observed via Test-Path and accessibility timed out. Treating BCD state as uncertain."
                            $verificationResults += "BCD: UNCERTAIN (timeout, file not observed)"
                            $remainingIssues++
                        }
                    } elseif ($bcdCheckOutput -match "The boot configuration data store could not be opened" -or
                        $bcdCheckOutput -match "The system cannot find the file specified" -or
                        $bcdCheckOutput -match "The system cannot find the path specified") {
                        Write-Log "[❌ STILL CORRUPTED] BCD appears inaccessible: $($bcdCheckOutput.Substring(0, [Math]::Min(100, $bcdCheckOutput.Length)))"
                        $remainingIssues++
                        $verificationResults += "BCD: STILL CORRUPTED"
                    } else {
                        $bcdAccessible = $true
                        if (-not $bcdFileExists) {
                            Write-Log "[INFO] BCD not located via Test-Path, but bcdedit succeeded. Treating BCD as accessible (likely hidden/permissioned store)."
                        }
                        Write-Log "[✅ FIXED] BCD is accessible and appears healthy"
                        
                        # Enhanced verification: Check that BCD path entry points to correct winload.efi
                        if ($efiDrive) {
                            Write-Log "Verifying BCD path entry points to correct winload.efi..."
                            try {
                                $bcdStorePath = "$efiDrive`:\EFI\Microsoft\Boot\BCD"
                                if (Test-Path $bcdStorePath) {
                                    $bcdPathCheck = $null
                                    $bcdPathJob = Start-Job -ScriptBlock {
                                        param($storePath)
                                        bcdedit /store $storePath /enum "{default}" 2>&1 | Out-String
                                    } -ArgumentList $bcdStorePath
                                    
                                    $bcdPathCheck = Wait-Job -Job $bcdPathJob -Timeout 10 | Receive-Job
                                    Stop-Job -Job $bcdPathJob -ErrorAction SilentlyContinue
                                    Remove-Job -Job $bcdPathJob -ErrorAction SilentlyContinue
                                    
                                    if ($bcdPathCheck -and $bcdPathCheck -match 'path\s+(.+winload\.efi)') {
                                        $bcdPath = $matches[1].Trim()
                                        Write-Log "[OK] BCD path entry verified: $bcdPath"
                                        
                                        # Verify the path actually exists
                                        $expectedPath = "$drive`:\Windows\System32\winload.efi"
                                        if ($bcdPath -match '\\Windows\\system32\\winload\.efi' -or $bcdPath -eq '\Windows\system32\winload.efi') {
                                            if (Test-Path $expectedPath) {
                                                Write-Log "[OK] BCD path points to existing winload.efi"
                                            } else {
                                                Write-Log "[WARNING] BCD path entry exists but winload.efi not found at expected location"
                                                $remainingIssues++
                                                $verificationResults += "BCD: PATH MISMATCH (winload.efi missing)"
                                            }
                                        }
                                    } else {
                                        Write-Log "[INFO] Could not verify BCD path entry (may be normal for some configurations)"
                                    }
                                }
                            } catch {
                                Write-Log "[INFO] BCD path verification skipped: $_"
                            }
                        }
                        
                        $verificationResults += "BCD: FIXED"
                    }
                    
                    if (-not $bcdAccessible -and -not $bcdFileExists -and $null -eq $bcdCheckOutput) {
                        Write-Log "[❌ STILL MISSING] BCD file not found in any standard location and accessibility could not be confirmed"
                        $remainingIssues++
                        $verificationResults += "BCD: STILL MISSING"
                    }
                } catch {
                    Write-Log "[⚠️  UNCERTAIN] Could not verify BCD status: $_"
                    $verificationResults += "BCD: UNCERTAIN"
                }
                
                Write-Log ""
                Write-Log "==============================================================="
                Write-Log "VERIFICATION RESULTS"
                Write-Log "==============================================================="
                foreach ($result in $verificationResults) {
                    Write-Log "  $result"
                }
                Write-Log ""
                
                if ($remainingIssues -eq 0) {
                    Write-Log "[✅ SUCCESS] All detected issues have been FIXED!"
                } else {
                    Write-Log "[⚠️  PARTIAL SUCCESS] Some issues remain ($remainingIssues issue(s) still present)"
                }
                
                Write-Log ""
                Write-Log "==============================================================="
                Write-Log "POST-REPAIR TRUTH ENGINE - BOOT VIABILITY ASSESSMENT"
                Write-Log "==============================================================="
                Write-Log ""
                Write-Log "Switching to FORENSIC MODE (read-only verification)..."
                Write-Log ""
                
                # Run Boot Viability Engine
                if (Get-Command "Test-BootViability" -ErrorAction SilentlyContinue) {
                    try {
                        if ($txtOneClickStatus) {
                            $txtOneClickStatus.Text = "Running boot viability assessment..."
                        }
                        Update-StatusBar -Message "One-Click Repair: Assessing boot viability..." -ShowProgress
                        
                        # Pass EFI drive letter if available to help with verification
                        $viabilityResult = Test-BootViability -TargetDrive $drive
                        
                        # Append viability report to log
                        Write-Log $viabilityResult.Report
                        Write-Log ""
                        
                        # Display verdict prominently
                        Write-Log "==============================================================="
                        Write-Log "FINAL BOOT VERDICT"
                        Write-Log "==============================================================="
                        Write-Log $viabilityResult.UserMessage
                        Write-Log ""
                        Write-Log "Confidence: $($viabilityResult.Confidence)%"
                        Write-Log "Checks Passed: $($viabilityResult.Checks.EFIBootFiles.Count + $($viabilityResult.Checks.BCDRealityMatch.Count) + $($viabilityResult.Checks.WinloadReality.Count) + $($viabilityResult.Checks.BootCriticalDrivers.Count) + $($viabilityResult.Checks.BootHandoffChain.Count)) / 5"
                        Write-Log ""
                        
                        if ($viabilityResult.WillBoot) {
                            Write-Log "==============================================================="
                            Write-Log "WILL IT BOOT: YES"
                            Write-Log "==============================================================="
                            Write-Log ""
                            Write-Log "Feedback: All critical boot files verified and BCD is correctly mapped."
                            Write-Log ""
                            Write-Log "Your boot system is repaired and verified. Next steps:"
                            Write-Log "  1. Restart your computer"
                            Write-Log "  2. If BitLocker prompts for recovery key, enter your 48-digit key"
                            Write-Log "  3. Windows should boot normally"
                            
                            if ($txtOneClickStatus) {
                                $txtOneClickStatus.Text = "[YES] BOOTABLE! System verified. Ready to reboot."
                            }
                            if ($fixerOutput) {
                                $fixerOutput.Text += "`n`n===============================================================`n"
                                $fixerOutput.Text += "WILL IT BOOT: YES`n"
                                $fixerOutput.Text += "===============================================================`n"
                                $fixerOutput.Text += "`n$($viabilityResult.UserMessage)`n"
                            }
                        } else {
                            Write-Log "==============================================================="
                            Write-Log "WILL IT BOOT: NO"
                            Write-Log "==============================================================="
                            Write-Log ""
                            Write-Log "REASON(S) FOR FAILURE:"
                            Write-Log ""
                            
                            # Display critical failures with specific fixes
                            if ($viabilityResult.Evidence.CheckC -and -not $viabilityResult.Evidence.CheckC.Passed) {
                                Write-Log "  [!] PHYSICAL MISSING: winload.efi is still missing from the source folder."
                                Write-Log "      Fix: Source template is corrupted. Needs DISM extraction from ISO."
                                Write-Log "      Command: DISM /apply-image /imagefile:<ISO_PATH>\sources\install.wim /index:1 /applydir:$drive`:"
                                Write-Log ""
                            }
                            
                            if ($viabilityResult.Evidence.CheckB -and -not $viabilityResult.Evidence.CheckB.Passed) {
                                Write-Log "  [!] BCD MISMATCH: The boot configuration is pointing to the wrong file/path."
                                Write-Log "      Fix: Run 'bcdedit /set {default} path \Windows\system32\winload.efi'"
                                Write-Log ""
                            }
                            
                            # Check for BitLocker locked (from diagnostic payload)
                            if ($viabilityResult.DiagnosticPayload -and $viabilityResult.DiagnosticPayload.blocking_issue -match "BitLocker") {
                                Write-Log "  [!] BITLOCKER LOCKED: The drive is encrypted and 'bcdboot' could not write to it."
                                Write-Log "      Fix: You MUST unlock the drive with your recovery key before repairing."
                                Write-Log "      Command: manage-bde -unlock $drive`: -RecoveryPassword <YOUR_48_DIGIT_KEY>"
                                Write-Log ""
                            }
                            
                            Write-Log "See detailed report above for complete analysis."
                            
                            if ($txtOneClickStatus) {
                                $txtOneClickStatus.Text = "[NO] NOT BOOTABLE: See log for reasons"
                            }
                            if ($fixerOutput) {
                                $fixerOutput.Text += "`n`n===============================================================`n"
                                $fixerOutput.Text += "WILL IT BOOT: NO`n"
                                $fixerOutput.Text += "===============================================================`n"
                                $fixerOutput.Text += "`n$($viabilityResult.UserMessage)`n"
                            }
                        }
                        
                        # Save diagnostic payload to separate file
                        if ($viabilityResult.DiagnosticPayload) {
                            $diagnosticFile = "$env:TEMP\BootViability_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                            try {
                                $viabilityResult.DiagnosticPayload | ConvertTo-Json -Depth 10 | Out-File -FilePath $diagnosticFile -Encoding UTF8 -Force
                                Write-Log ""
                                Write-Log "[INFO] Diagnostic payload saved to: $diagnosticFile"
                            } catch {
                                Write-Log "[WARNING] Could not save diagnostic payload: $_"
                            }
                        }
                        
                    } catch {
                        Write-Log "[WARNING] Boot viability assessment failed: $_"
                        Write-Log "Falling back to basic verification results above."
                    }
                } else {
                    Write-Log "[INFO] Boot Viability Engine not available, using basic verification"
                    Write-Log ""
                    
                    if ($remainingIssues -eq 0) {
                        Write-Log "Your boot system appears to be repaired. Next steps:"
                        Write-Log "  1. Restart your computer"
                        Write-Log "  2. If BitLocker prompts for recovery key, enter your 48-digit key"
                        Write-Log "  3. Windows should boot normally"
                        if ($txtOneClickStatus) {
                            $txtOneClickStatus.Text = "✅ SUCCESS! All issues fixed. Ready to reboot."
                        }
                    } else {
                        Write-Log "NEXT STEPS:"
                        Write-Log "1. Restart your computer and test if it boots"
                        Write-Log "2. If BitLocker prompts for recovery key, enter your 48-digit key"
                        Write-Log "3. If problems persist, consider:"
                        Write-Log "   - Running an in-place repair installation"
                        Write-Log "   - Checking hardware health"
                        Write-Log "   - Injecting missing storage drivers"
                        if ($txtOneClickStatus) {
                            $txtOneClickStatus.Text = "⚠️  Partial success: $remainingIssues issue(s) remain. Check log for details."
                        }
                    }
                }
            }
            
            Write-Log ""
            Write-Log "==============================================================="
            Write-Log "REPAIR STATE DIAGNOSTIC (Copy for troubleshooting)"
            Write-Log "==============================================================="
            Write-Log ""
            
            # Generate and display repair state diagnostic
            if (Get-Command "Get-RepairState" -ErrorAction SilentlyContinue) {
                $repairState = Get-RepairState -TargetDrive $drive
                Write-Log $repairState
                Write-Log ""
            } else {
                Write-Log "[INFO] Repair state diagnostic not available"
                Write-Log ""
            }
            
            Write-Log "==============================================================="
            Write-Log "END OF ONE-CLICK REPAIR"
            Write-Log "End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Write-Log "Log File: $logFile"
            Write-Log "==============================================================="
            
            # Save log file
            try {
                $logContent.ToString() | Out-File -FilePath $logFile -Encoding UTF8 -Force
                Write-Log ""
                Write-Log "[INFO] Log file saved to: $logFile"
            } catch {
                Write-Log "[WARNING] Could not save log file: $_"
            }
            
            # Generate comprehensive repair report
            if ($repairReport) {
                try {
                    # Update target drive if it was changed during repair
                    if (Get-Variable -Name "drive" -ErrorAction SilentlyContinue) {
                        $targetDrive = $drive.TrimEnd(':')
                        $repairReport.TargetDrive = $targetDrive
                    }
                    
                    # Add remaining issues to report
                    if ($remainingIssues -gt 0) {
                        # Re-check what's still wrong
                        Write-Log ""
                        Write-Log "Performing post-repair verification..."
                        
                        # Wait for file system cache to update
                        Start-Sleep -Seconds 3
                        
                        # Check winload.efi - must be in EFI partition for UEFI boot
                        $winloadFound = $false
                        $winloadEfiPath = $null
                        $winloadWindowsPath = "$targetDrive`:\Windows\System32\winload.efi"
                        
                        # Try to find EFI partition
                        $efiDriveForCheck = $null
                        if (Get-Variable -Name "efiDrive" -ErrorAction SilentlyContinue) {
                            $efiDriveForCheck = $efiDrive
                        } else {
                            $efiMount = Mount-EFIPartition -WindowsDrive $targetDrive -PreferredLetter "S"
                            if ($efiMount.Success) {
                                $efiDriveForCheck = $efiMount.DriveLetter
                            }
                        }
                        
                        if ($efiDriveForCheck) {
                            $winloadEfiPath = "$efiDriveForCheck`:\EFI\Microsoft\Boot\winload.efi"
                            if (Test-Path $winloadEfiPath) {
                                $winloadFound = $true
                            }
                        }
                        
                        # winload.efi in Windows directory is good but not sufficient for UEFI boot
                        if (-not $winloadFound -and (Test-Path $winloadWindowsPath)) {
                            # File exists in Windows but not in EFI - this is a problem for UEFI boot
                            Add-RepairIssue -Report $repairReport -Issue "winload.efi exists in Windows directory but not in EFI partition (required for UEFI boot)" -Category "Boot Files" -Fixed $false | Out-Null
                        } elseif (-not $winloadFound) {
                            Add-RepairIssue -Report $repairReport -Issue "winload.efi is still missing from EFI partition" -Category "Boot Files" -Fixed $false | Out-Null
                        }
                        
                        # Check BCD
                        try {
                            # First check if BCD file exists physically
                            $bcdFileExists = $false
                            $bcdAccessible = $false
                            $bcdCheckOutput = $null
                            if ($efiDriveForCheck) {
                                $efiBcdPath = "$efiDriveForCheck`:\EFI\Microsoft\Boot\BCD"
                                $bcdFileExists = Test-Path $efiBcdPath
                            }
                            
                            if (-not $bcdFileExists) {
                                # Check legacy locations
                                $legacyBcdPaths = @(
                                    "$env:SystemRoot\Boot\BCD",
                                    "$env:SystemDrive\Boot\BCD"
                                )
                                foreach ($legacyPath in $legacyBcdPaths) {
                                    if (Test-Path $legacyPath) {
                                        $bcdFileExists = $true
                                        break
                                    }
                                }
                            }
                            
                            # Always run bcdedit to capture accessibility even if Test-Path fails
                            $bcdJob = Start-Job -ScriptBlock {
                                bcdedit /enum all 2>&1 | Out-String
                            }
                            $bcdCheckOutput = Wait-Job -Job $bcdJob -Timeout 5 | Receive-Job
                            Stop-Job -Job $bcdJob -ErrorAction SilentlyContinue
                            Remove-Job -Job $bcdJob -ErrorAction SilentlyContinue
                            
                            if ($null -eq $bcdCheckOutput) {
                                if (-not $bcdFileExists) {
                                    Add-RepairIssue -Report $repairReport -Issue "BCD file not observed and accessibility check timed out" -Category "BCD" -Fixed $false | Out-Null
                                }
                                # If file exists but timed out, treat as initializing and do not add issue
                            } elseif ($bcdCheckOutput -match "The boot configuration data store could not be opened" -or
                                $bcdCheckOutput -match "The system cannot find the file specified" -or
                                $bcdCheckOutput -match "The system cannot find the path specified") {
                                Add-RepairIssue -Report $repairReport -Issue "BCD file exists but is inaccessible or corrupted" -Category "BCD" -Fixed $false | Out-Null
                            } else {
                                $bcdAccessible = $true
                            }
                            
                            if (-not $bcdAccessible -and -not $bcdFileExists -and $null -ne $bcdCheckOutput) {
                                # bcdedit returned something but indicated missing paths
                                Add-RepairIssue -Report $repairReport -Issue "BCD file missing from EFI partition and legacy locations" -Category "BCD" -Fixed $false | Out-Null
                            }
                        } catch {
                            Add-RepairIssue -Report $repairReport -Issue "BCD verification failed: $_" -Category "BCD" -Fixed $false | Out-Null
                        }
                    }
                    
                    # Set post-repair verification
                    $verificationText = "Post-repair verification completed.`n"
                    if ($remainingIssues -eq 0) {
                        $verificationText += "All issues appear to be resolved.`n"
                    } else {
                        $verificationText += "$remainingIssues issue(s) still remain.`n"
                    }
                    if ($repairReport.PostRepairVerification) {
                        $verificationText += $repairReport.PostRepairVerification
                    }
                    Set-PostRepairVerification -Report $repairReport -VerificationResult $verificationText | Out-Null
                    
                    # Export report
                    $reportPath = Export-RepairReport -Report $repairReport -OpenInNotepad:$true
                    Write-Log ""
                    Write-Log "[INFO] Comprehensive repair report generated: $reportPath"
                    Write-Log "[INFO] Report opened in Notepad"
                    
                    # If there are remaining issues, offer to fix them and generate failure report
                    if ((Get-SafeCount $repairReport.IssuesRemaining) -gt 0) {
                        Write-Log ""
                        Write-Log "[WARNING] Some issues could not be fixed automatically."
                        
                        # Run advanced diagnostics
                        Write-Log "[INFO] Running advanced boot diagnostics..."
                        try {
                            if (Get-Command "Start-AdvancedBootDiagnostics" -ErrorAction SilentlyContinue) {
                                $advancedDiag = Start-AdvancedBootDiagnostics -WindowsDrive $drive
                                $diagFile = Join-Path $env:TEMP "AdvancedBootDiagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                                $advancedDiag | Out-File -FilePath $diagFile -Encoding UTF8 -Force
                                Write-Log "[INFO] Advanced diagnostics report saved: $diagFile"
                            }
                        } catch {
                            Write-Log "[WARNING] Could not run advanced diagnostics: $_"
                        }
                        
                        $fixAgain = [System.Windows.MessageBox]::Show(
                            "Some issues could not be fixed automatically.`n`n" +
                            "Remaining issues: $($repairReport.IssuesRemaining.Count)`n`n" +
                            "Advanced diagnostics have been run to identify root causes.`n`n" +
                            "Would you like to attempt additional repair steps?`n`n" +
                            "Yes = Try additional fixes`n" +
                            "No = View failure report with manual commands",
                            "Additional Repair Needed",
                            "YesNo",
                            "Question"
                        )
                        
                        if ($fixAgain -eq "Yes") {
                            Write-Log "User requested additional repair attempts..."
                            # TODO: Implement additional repair logic here
                            Write-Log "[INFO] Additional repair logic not yet implemented. Please see failure report for manual commands."
                        }
                        
                        # Generate failure report with alternative commands
                        $failureReportPath = Export-FailureReport -Report $repairReport -TargetDrive $targetDrive -OpenInNotepad:$true
                        Write-Log "[INFO] Failure report generated: $failureReportPath"
                        Write-Log "[INFO] Failure report opened in Notepad with alternative commands to try"
                        
                        # Offer to open advanced diagnostics
                        if (Test-Path $diagFile) {
                            $openDiag = [System.Windows.MessageBox]::Show(
                                "Advanced boot diagnostics have been generated.`n`n" +
                                "This report includes checks for:`n" +
                                "- Intel VMD driver issues (Z790 boards)`n" +
                                "- Multiple boot drive conflicts`n" +
                                "- Pending Windows updates`n" +
                                "- Read-only drive issues`n" +
                                "- MBR/GPT corruption`n" +
                                "- BIOS/firmware recommendations`n`n" +
                                "Would you like to open the diagnostics report?",
                                "Advanced Diagnostics Available",
                                "YesNo",
                                "Question"
                            )
                            if ($openDiag -eq "Yes") {
                                Start-Process notepad.exe -ArgumentList $diagFile -ErrorAction SilentlyContinue
                            }
                        }
                    }
                } catch {
                    Write-Log "[WARNING] Could not generate comprehensive report: $_"
                    # Fall back to opening basic log file
                    Start-Process notepad.exe -ArgumentList $logFile -ErrorAction SilentlyContinue
                }
            } else {
                # Fall back to opening basic log file if report generator not available
                Start-Process notepad.exe -ArgumentList $logFile -ErrorAction SilentlyContinue
                Write-Log "[INFO] Log file opened in Notepad"
            }
            
            Update-StatusBar -Message "One-Click Repair: Complete" -HideProgress
            
        } catch {  # End of try block started at line 3419
            Write-Log ""
            Write-Log "==============================================================="
            Write-Log "[ERROR] One-Click Repair failed"
            Write-Log "Error: $($_.Exception.Message)"
            Write-Log "Stack trace: $($_.ScriptStackTrace)"
            Write-Log "==============================================================="
            
            # Run advanced diagnostics when repair fails
            Write-Log "[INFO] Running advanced boot diagnostics to identify root cause..."
            $diagFile = $null
            try {
                # Ensure drive is set before running diagnostics
                if (-not $drive) {
                    $drive = $env:SystemDrive.TrimEnd(':')
                    Write-Log "[INFO] Using system drive for diagnostics: $drive`:"
                }
                
                if (Get-Command "Start-AdvancedBootDiagnostics" -ErrorAction SilentlyContinue) {
                    $advancedDiag = Start-AdvancedBootDiagnostics -WindowsDrive $drive
                    $diagFile = Join-Path $env:TEMP "AdvancedBootDiagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                    $advancedDiag | Out-File -FilePath $diagFile -Encoding UTF8 -Force
                    Write-Log "[INFO] Advanced diagnostics report saved: $diagFile"
                }
            } catch {
                Write-Log "[WARNING] Could not run advanced diagnostics: $_"
            }
            
            # Save log file even on error
            try {
                $logContent.ToString() | Out-File -FilePath $logFile -Encoding UTF8 -Force
                Start-Process notepad.exe -ArgumentList $logFile -ErrorAction SilentlyContinue
            } catch {
                # Ignore log save errors
            }
            
            if ($txtOneClickStatus) {
                $txtOneClickStatus.Text = "❌ Error: $($_.Exception.Message)"
            }
            if ($fixerOutput) {
                $fixerOutput.Text += "`n[ERROR] One-Click Repair failed: $_`n"
                $fixerOutput.Text += "Stack trace: $($_.ScriptStackTrace)`n"
                $fixerOutput.Text += "`nLog file: $logFile`n"
            }
            Update-StatusBar -Message "One-Click Repair: Failed - $($_.Exception.Message)" -HideProgress
            
            # Offer to open advanced diagnostics
            if ($diagFile -and (Test-Path $diagFile)) {
                $openDiag = [System.Windows.MessageBox]::Show(
                    "One-Click Repair failed. Advanced boot diagnostics have been generated.`n`n" +
                    "This report checks for complex issues beyond simple file corruption:`n" +
                    "- Intel VMD driver issues (Z790 boards)`n" +
                    "- Multiple boot drive conflicts`n" +
                    "- Pending Windows updates blocking repair`n" +
                    "- Read-only drive issues`n" +
                    "- MBR/GPT corruption`n" +
                    "- BIOS/firmware configuration issues`n`n" +
                    "Would you like to open the advanced diagnostics report?",
                    "Advanced Diagnostics Available",
                    "YesNo",
                    "Question"
                )
                if ($openDiag -eq "Yes") {
                    Start-Process notepad.exe -ArgumentList $diagFile -ErrorAction SilentlyContinue
                }
            }
        }
        finally {
            # FLAW-007 FIX: Always reset repair flag, even on error
            $script:repairInProgress = $false
            # Re-enable button
            $btnOneClickRepair.IsEnabled = $true
        }
    })
}

# Boot Fixer Functions - Enhanced with detailed command info
function Show-CommandPreview {
    param($Command, $Key, $Description)
    $testMode = $W.FindName("ChkTestMode").IsChecked
    $cmdInfo = Get-DetailedCommandInfo $Key
    
    $output = ">>> ANALYSIS REPORT`n"
    $output += "===============================================================`n"
    $output += "Time: $([DateTime]::Now.ToString('HH:mm:ss'))`n"
    $output += "Command: $Command`n"
    $output += "Description: $Description`n`n"
    
    if ($cmdInfo) {
        $output += "WHY USE THIS:`n"
        $output += "  $($cmdInfo.Why)`n`n"
        $output += "TECHNICAL ACTION:`n"
        $output += "  $($cmdInfo.What)`n`n"
    }
    
    if ($testMode) {
        $output += "--- [TEST MODE ACTIVE: NO CHANGES WILL BE MADE] ---`n"
        $output += "Uncheck 'Test Mode' to execute this command.`n"
    } else {
        $output += "--- [EXECUTING COMMAND] ---`n"
    }
    
    $fixerOutput = Get-Control -Name "FixerOutput"
    if ($fixerOutput) {
        $fixerOutput.Text = $output
        $fixerOutput.ScrollToEnd()
    }
    
    return $testMode
}

$btnRebuildBCD = Get-Control -Name "BtnRebuildBCD"
if ($btnRebuildBCD) {
    $btnRebuildBCD.Add_Click({
        $driveCombo = Get-Control -Name "DriveCombo"
        $fixerOutput = Get-Control -Name "FixerOutput"
        $txtRebuildBCD = Get-Control -Name "TxtRebuildBCD"
        
        $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        $command = "bcdboot $drive`:\Windows"
        $explanation = Get-CommandExplanation "bcdboot"
        $cmdInfo = Get-DetailedCommandInfo "bcdboot"
        
        $displayText = "COMMAND: $command`n`n"
        if ($cmdInfo) {
            $displayText += "WHY USE THIS:`n$($cmdInfo.Why)`n`n"
            $displayText += "TECHNICAL ACTION:`n$($cmdInfo.What)`n"
        } else {
            $displayText += "EXPLANATION:`n$explanation"
        }
        if ($txtRebuildBCD) {
            $txtRebuildBCD.Text = $displayText
        }
        
        $testMode = Show-CommandPreview $command "bcdboot" "Rebuild BCD from Windows Installation"
        
        if (-not $testMode) {
            # Show comprehensive warning
            $warningInfo = Show-CommandWarning -CommandKey "bcdboot" -Command $command -Description "Rebuild BCD from Windows Installation" -IsGUI
            
            $warningMsg = "$($warningInfo.Message)`n`nDo you want to proceed?"
            $result = [System.Windows.MessageBox]::Show(
                $warningMsg,
                $warningInfo.Title,
                "YesNo",
                "Warning"
            )
            
            if ($result -eq "No") {
                if ($fixerOutput) {
                    $fixerOutput.Text += "`nOperation cancelled by user.`n"
                }
                Update-StatusBar -Message "Operation cancelled" -HideProgress
                return
            }
            
            # BitLocker Safety Check
            $bitlocker = Test-BitLockerStatus -TargetDrive $drive
            if ($bitlocker.IsEncrypted) {
                $result = [System.Windows.MessageBox]::Show(
                    "$($bitlocker.Warning)`n`nNOTE: Boot recovery operations may take longer on BitLocker-encrypted drives. This is normal - please be patient.`n`nDo you have your BitLocker recovery key available?`n`nClick 'Yes' to proceed anyway, or 'No' to cancel.",
                    "BitLocker Encryption Detected",
                    "YesNo",
                    "Warning"
                )
                if ($result -eq "No") {
                    if ($fixerOutput) {
                        $fixerOutput.Text += "`nOperation cancelled due to BitLocker encryption.`n"
                    }
                    Update-StatusBar -Message "Operation cancelled" -HideProgress
                    return
                }
            }
            
            try {
                Update-StatusBar -Message "Executing BCD rebuild..." -ShowProgress
                $result = Invoke-Expression $command 2>&1
                if ($fixerOutput) {
                    $fixerOutput.Text += "`nOutput: $result`n"
                }
                Update-StatusBar -Message "BCD rebuild completed" -HideProgress
            } catch {
                if ($fixerOutput) {
                    $fixerOutput.Text += "`nError: $_`n"
                }
                Update-StatusBar -Message "BCD rebuild failed: $_" -HideProgress
            }
        } else {
            Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
        }
    })
}

$btnFixBoot = Get-Control -Name "BtnFixBoot"
if ($btnFixBoot) {
    $btnFixBoot.Add_Click({

    $driveCombo = Get-Control -Name "DriveCombo"
    $selectedDrive = if ($driveCombo) { $driveCombo.SelectedItem } else { $null }
    $drive = "C"
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $command = "bootrec /fixboot"
    $cmdInfo = Get-DetailedCommandInfo "fixboot"
    
    $displayText = "COMMAND: $command`nAlso runs: bootrec /fixmbr`nAlso runs: bootrec /rebuildbcd`n`n"
    if ($cmdInfo) {
        $displayText += "WHY USE THIS:`n$($cmdInfo.Why)`n`n"
        $displayText += "TECHNICAL ACTION:`n$($cmdInfo.What)`n"
    }
    $TxtFixBoot = Get-Control -Name "TxtFixBoot"
    if ($TxtFixBoot) {
        $TxtFixBoot.Text = $displayText
    }
    
    $testMode = Show-CommandPreview $command "fixboot" "Fix Boot Files (bootrec)"
    
    if (-not $testMode) {
        # Show comprehensive warning
        $warningInfo = Show-CommandWarning -CommandKey "bootrec_fixboot" -Command $command -Description "Fix Boot Files (bootrec)" -IsGUI
        
        $warningMsg = "$($warningInfo.Message)`n`nDo you want to proceed?"
        $result = [System.Windows.MessageBox]::Show(
            $warningMsg,
            $warningInfo.Title,
            "YesNo",
            "Warning"
        )
        
        $fixerOutput = Get-Control -Name "FixerOutput"
        if ($result -eq "No") {
            if ($fixerOutput) {
                $fixerOutput.Text += "`nOperation cancelled by user.`n"
            }
            Update-StatusBar -Message "Operation cancelled" -HideProgress
            return
        }
        
        # BitLocker Safety Check
        $bitlocker = Test-BitLockerStatus -TargetDrive $drive
        if ($bitlocker.IsEncrypted) {
            $result = [System.Windows.MessageBox]::Show(
                "$($bitlocker.Warning)`n`nNOTE: Boot recovery operations may take longer on BitLocker-encrypted drives. This is normal - please be patient.`n`nDo you have your BitLocker recovery key available?`n`nClick 'Yes' to proceed anyway, or 'No' to cancel.",
                "BitLocker Encryption Detected",
                "YesNo",
                "Warning"
            )
            if ($result -eq "No") {
                if ($fixerOutput) {
                    $fixerOutput.Text += "`nOperation cancelled due to BitLocker encryption.`n"
                }
                Update-StatusBar -Message "Operation cancelled" -HideProgress
                return
            }
        }
        
        try {
            Update-StatusBar -Message "Executing boot fix commands..." -ShowProgress
            
            # Find bootrec.exe path (required for proper execution)
            $bootrecPath = $null
            $bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
            if ($bootrecCmd) {
                $bootrecPath = $bootrecCmd.Source
            } else {
                # Try common WinRE/WinPE paths
                $possiblePaths = @(
                    "$env:SystemRoot\System32\bootrec.exe",
                    "X:\Windows\System32\bootrec.exe",
                    "C:\Windows\System32\Recovery\bootrec.exe"
                )
                foreach ($path in $possiblePaths) {
                    if (Test-Path $path) {
                        $bootrecPath = $path
                        break
                    }
                }
            }
            
            if (-not $bootrecPath) {
                throw "bootrec.exe not found. This tool is only available in WinRE/WinPE environments."
            }
            
            # Execute bootrec commands with full path and proper error handling
            $results = @()
            
            # bootrec /fixboot
            Write-Log "Executing: $bootrecPath /fixboot"
            try {
                $result1 = & $bootrecPath /fixboot 2>&1 | Out-String
                $results += "bootrec /fixboot:`n$result1"
                if ($result1 -match "Access is denied|access denied") {
                    Write-Log "[WARNING] bootrec /fixboot returned 'Access is denied'. This may be normal if boot files are already correct or if running from FullOS."
                    $results += "`n[NOTE] Access denied may indicate the boot sector is already correct or the command requires different privileges."
                }
            } catch {
                Write-Log "[WARNING] bootrec /fixboot failed: $_"
                $results += "bootrec /fixboot ERROR: $_"
            }
            
            # bootrec /fixmbr (only for legacy BIOS systems)
            Write-Log "Executing: $bootrecPath /fixmbr"
            try {
                $result2 = & $bootrecPath /fixmbr 2>&1 | Out-String
                $results += "`n`nbootrec /fixmbr:`n$result2"
                if ($result2 -match "Access is denied|access denied") {
                    Write-Log "[WARNING] bootrec /fixmbr returned 'Access is denied'. This is normal for UEFI systems."
                    $results += "`n[NOTE] Access denied is normal for UEFI systems (MBR is not used)."
                }
            } catch {
                Write-Log "[WARNING] bootrec /fixmbr failed: $_"
                $results += "`n`nbootrec /fixmbr ERROR: $_"
            }
            
            # bootrec /rebuildbcd
            Write-Log "Executing: $bootrecPath /rebuildbcd"
            try {
                $result3 = & $bootrecPath /rebuildbcd 2>&1 | Out-String
                $results += "`n`nbootrec /rebuildbcd:`n$result3"
                if ($result3 -match "Access is denied|access denied") {
                    Write-Log "[WARNING] bootrec /rebuildbcd returned 'Access is denied'. Trying alternative method with bcdboot..."
                    $results += "`n[NOTE] Access denied on rebuildbcd. Consider using bcdboot as alternative."
                }
            } catch {
                Write-Log "[WARNING] bootrec /rebuildbcd failed: $_"
                $results += "`n`nbootrec /rebuildbcd ERROR: $_"
            }
            
            if ($fixerOutput) {
                $fixerOutput.Text += "`nOutput:`n$($results -join "`n")`n"
            }
            
            # Check if any command succeeded
            $hasSuccess = $results -match "successfully|completed successfully|The operation completed successfully"
            if ($hasSuccess) {
                Update-StatusBar -Message "Boot fix completed (some commands may have warnings)" -HideProgress
            } else {
                Update-StatusBar -Message "Boot fix completed with warnings (see output)" -HideProgress
            }
        } catch {
            if ($fixerOutput) {
                $fixerOutput.Text += "`nError: $_`n"
            }
            Write-Log "[ERROR] Boot fix operation failed: $_"
            Update-StatusBar -Message "Boot fix failed: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
    })
}

$btnScanWindows = Get-Control -Name "BtnScanWindows"
if ($btnScanWindows) {
    $btnScanWindows.Add_Click({

    $command = "bootrec /scanos"
    $cmdInfo = Get-DetailedCommandInfo "scanos"
    
    $displayText = "COMMAND: $command`n`n"
    if ($cmdInfo) {
        $displayText += "WHY USE THIS:`n$($cmdInfo.Why)`n`n"
        $displayText += "TECHNICAL ACTION:`n$($cmdInfo.What)`n"
    }
    $TxtScanWindows = Get-Control -Name "TxtScanWindows"
    if ($TxtScanWindows) {
        $TxtScanWindows.Text = $displayText
    }
    
    $testMode = Show-CommandPreview $command "scanos" "Scan for Windows Installations"
    
    if (-not $testMode) {
        $fixerOutput = Get-Control -Name "FixerOutput"
        try {
            Update-StatusBar -Message "Scanning for Windows installations..." -ShowProgress
            
            # Find bootrec.exe path
            $bootrecPath = $null
            $bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
            if ($bootrecCmd) {
                $bootrecPath = $bootrecCmd.Source
            } else {
                $possiblePaths = @(
                    "$env:SystemRoot\System32\bootrec.exe",
                    "X:\Windows\System32\bootrec.exe",
                    "C:\Windows\System32\Recovery\bootrec.exe"
                )
                foreach ($path in $possiblePaths) {
                    if (Test-Path $path) {
                        $bootrecPath = $path
                        break
                    }
                }
            }
            
            if (-not $bootrecPath) {
                throw "bootrec.exe not found. This tool is only available in WinRE/WinPE environments."
            }
            
            Write-Log "Executing: $bootrecPath /scanos"
            $result = & $bootrecPath /scanos 2>&1 | Out-String
            
            if ($result -match "Access is denied|access denied") {
                Write-Log "[WARNING] bootrec /scanos returned 'Access is denied'"
                $result += "`n[NOTE] Access denied may indicate insufficient privileges or the command is not available in this environment."
            }
            
            if ($fixerOutput) {
                $fixerOutput.Text += "`nOutput: $result`n"
            }
            Update-StatusBar -Message "Windows scan completed" -HideProgress
        } catch {
            if ($fixerOutput) {
                $fixerOutput.Text += "`nError: $_`n"
            }
            Write-Log "[ERROR] Windows scan failed: $_"
            Update-StatusBar -Message "Windows scan failed: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
    })
}

$btnRebuildBCD2 = Get-Control -Name "BtnRebuildBCD2"
if ($btnRebuildBCD2) {
    $btnRebuildBCD2.Add_Click({

    $command = "bootrec /rebuildbcd"
    $cmdInfo = Get-DetailedCommandInfo "rebuildbcd"
    
    $displayText = "COMMAND: $command`n`n"
    if ($cmdInfo) {
        $displayText += "WHY USE THIS:`n$($cmdInfo.Why)`n`n"
        $displayText += "TECHNICAL ACTION:`n$($cmdInfo.What)`n"
    }
    $TxtRebuildBCD2 = Get-Control -Name "TxtRebuildBCD2"
    if ($TxtRebuildBCD2) {
        $TxtRebuildBCD2.Text = $displayText
    }
    
    $testMode = Show-CommandPreview $command "rebuildbcd" "Rebuild BCD (bootrec)"
    
    if (-not $testMode) {
        $fixerOutput = Get-Control -Name "FixerOutput"
        try {
            Update-StatusBar -Message "Rebuilding BCD..." -ShowProgress
            
            # Find bootrec.exe path
            $bootrecPath = $null
            $bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
            if ($bootrecCmd) {
                $bootrecPath = $bootrecCmd.Source
            } else {
                $possiblePaths = @(
                    "$env:SystemRoot\System32\bootrec.exe",
                    "X:\Windows\System32\bootrec.exe",
                    "C:\Windows\System32\Recovery\bootrec.exe"
                )
                foreach ($path in $possiblePaths) {
                    if (Test-Path $path) {
                        $bootrecPath = $path
                        break
                    }
                }
            }
            
            if (-not $bootrecPath) {
                throw "bootrec.exe not found. This tool is only available in WinRE/WinPE environments."
            }
            
            Write-Log "Executing: $bootrecPath /rebuildbcd"
            $result = & $bootrecPath /rebuildbcd 2>&1 | Out-String
            
            if ($result -match "Access is denied|access denied") {
                Write-Log "[WARNING] bootrec /rebuildbcd returned 'Access is denied'. This may require elevated privileges or alternative method."
                $result += "`n[NOTE] If access denied persists, try using bcdboot as an alternative method."
            }
            
            if ($fixerOutput) {
                $fixerOutput.Text += "`nOutput: $result`n"
            }
            Update-StatusBar -Message "BCD rebuild completed" -HideProgress
        } catch {
            if ($fixerOutput) {
                $fixerOutput.Text += "`nError: $_`n"
            }
            Write-Log "[ERROR] BCD rebuild failed: $_"
            Update-StatusBar -Message "BCD rebuild failed: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
    })
}

$btnSetDefaultBoot = Get-Control -Name "BtnSetDefaultBoot"
if ($btnSetDefaultBoot) {
    $btnSetDefaultBoot.Add_Click({

    $bcdList = Get-Control -Name "BCDList"
    $selected = if ($bcdList) { $bcdList.SelectedItem } else { $null }
    if (-not $selected) {
        [System.Windows.MessageBox]::Show("Please select a BCD entry first in the BCD Editor tab.", "Warning", "OK", "Warning")
        return
    }
    
    $command = "bcdedit /default $($selected.Id)"
    $TxtSetDefault = Get-Control -Name "TxtSetDefault"
    if ($TxtSetDefault) {
        $TxtSetDefault.Text = "COMMAND: $command`n"
    }
    
    $testMode = Show-CommandPreview $command $null "Set Default Boot Entry"
    
    if (-not $testMode) {
        $fixerOutput = Get-Control -Name "FixerOutput"
        $btnBCD = Get-Control -Name "BtnBCD"
        try {
            Set-BCDDefaultEntry $selected.Id
            if ($fixerOutput) {
                $fixerOutput.Text += "Default boot entry set successfully.`n"
            }
            Update-StatusBar -Message "Default boot entry set successfully - refreshing list..." -ShowProgress
            
            # Refresh BCD list to show the new default
            if ($btnBCD) {
                $btnBCD.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            }
            
            Update-StatusBar -Message "Default boot entry updated" -HideProgress
        } catch {
            if ($fixerOutput) {
                $fixerOutput.Text += "Error: $_`n"
            }
            Update-StatusBar -Message "Failed to set default boot entry: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
    })
}

# Diagnostics Tab Handlers
$btnCheckRestore = Get-Control -Name "BtnCheckRestore"
if ($btnCheckRestore) {
    $btnCheckRestore.Add_Click({

    $diagDriveCombo = Get-Control -Name "DiagDriveCombo"
    $selectedDrive = if ($diagDriveCombo) { $diagDriveCombo.SelectedItem } else { $null }
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $diagBox = Get-Control -Name "DiagBox"
    if ($diagBox) {
        $diagBox.Text = "Checking System Restore status for drive $drive`:...`n`n"
    }
    $restoreInfo = Get-SystemRestoreInfo -TargetDrive $drive
    
    $output = "SYSTEM RESTORE DIAGNOSTICS`n"
    $output += "===============================================================`n`n"
    $output += "Status: $($restoreInfo.Message)`n`n"
    
    if ($restoreInfo.Enabled -and $restoreInfo.RestorePoints.Count -gt 0) {
        $output += "RESTORE POINTS:`n"
        $output += "---------------------------------------------------------------`n"
        $num = 1
        foreach ($point in $restoreInfo.RestorePoints) {
            $output += "$num. $($point.Description)`n"
            $output += "   Created: $($point.CreationTime)`n"
            $output += "   Type: $($point.RestorePointType)`n"
            $output += "   Sequence: $($point.SequenceNumber)`n`n"
            $num++
            if ($num -gt 20) { break } # Limit to 20 most recent
        }
    } else {
        $output += "No restore points found.`n"
        $output += "`nTo enable System Restore:`n"
        $output += "1. Open System Properties`n"
        $output += "2. Go to System Protection tab`n"
        $output += "3. Select your drive and click Configure`n"
        $output += "4. Enable System Protection`n"
    }
    
    if ($diagBox) {
        $diagBox.Text = $output
    }
    })
}

$btnCreateRestorePoint = Get-Control -Name "BtnCreateRestorePoint"
if ($btnCreateRestorePoint) {
    $btnCreateRestorePoint.Add_Click({

    # Use a simple input dialog
    $description = "Miracle Boot Manual Restore Point - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $userInput = [Microsoft.VisualBasic.Interaction]::InputBox(
            "Enter description for restore point:",
            "Create System Restore Point",
            $description
        )
        if (-not [string]::IsNullOrWhiteSpace($userInput)) {
            $description = $userInput
        }
    } catch {
        # If InputBox fails, use default description
        Write-Warning "Could not show input dialog, using default description"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($description)) {
        $diagBox = Get-Control -Name "DiagBox"
        Update-StatusBar -Message "Creating restore point..." -ShowProgress
        if ($diagBox) {
            $diagBox.Text = "Creating system restore point...`n`nPlease wait...`n"
        }
        
        $result = Create-SystemRestorePoint -Description $description -OperationType "Manual"
        
        $output = "RESTORE POINT CREATION`n"
        $output += "===============================================================`n`n"
        
        if ($result.Success) {
            $output += "[SUCCESS] Restore point created successfully!`n`n"
            $output += "Description: $description`n"
            if ($result.RestorePointID) {
                $output += "Restore Point ID: $($result.RestorePointID)`n"
            }
            if ($result.RestorePointPath) {
                $output += "Path: $($result.RestorePointPath)`n"
            }
            Update-StatusBar -Message "Restore point created successfully" -HideProgress
        } else {
            $output += "[ERROR] Failed to create restore point`n`n"
            $output += "Message: $($result.Message)`n"
            if ($result.Error) {
                $output += "Error: $($result.Error)`n"
            }
            Update-StatusBar -Message "Failed to create restore point" -HideProgress
        }
        
        if ($diagBox) {
            $diagBox.Text = $output
        }
    }
    })
}

$btnListRestorePoints = Get-Control -Name "BtnListRestorePoints"
if ($btnListRestorePoints) {
    $btnListRestorePoints.Add_Click({

    $diagDriveCombo = Get-Control -Name "DiagDriveCombo"
    $selectedDrive = if ($diagDriveCombo) { $diagDriveCombo.SelectedItem } else { $null }
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $diagBox = Get-Control -Name "DiagBox"
    Update-StatusBar -Message "Retrieving restore points..." -ShowProgress
    if ($diagBox) {
        $diagBox.Text = "Retrieving restore points for drive $drive`:...`n`n"
    }
    
    $restorePoints = Get-SystemRestorePoints -Limit 50
    
    $output = "SYSTEM RESTORE POINTS`n"
    $output += "===============================================================`n`n"
    
    if ($restorePoints.Count -gt 0) {
        $output += "Found $($restorePoints.Count) restore point(s):`n`n"
        $num = 1
        foreach ($point in $restorePoints) {
            $output += "$num. ID: $($point.SequenceNumber)`n"
            $output += "   Description: $($point.Description)`n"
            $output += "   Created: $($point.CreationTime)`n"
            $output += "   Type: $($point.RestorePointType)`n"
            $output += "   Event: $($point.EventType)`n`n"
            $num++
        }
        Update-StatusBar -Message "Found $($restorePoints.Count) restore points" -HideProgress
    } else {
        $output += "[INFO] No restore points found.`n`n"
        $output += "System Restore may be disabled or no restore points have been created.`n"
        Update-StatusBar -Message "No restore points found" -HideProgress
    }
    
    if ($diagBox) {
        $diagBox.Text = $output
    }
    })
}

$btnCheckReagentc = Get-Control -Name "BtnCheckReagentc"
if ($btnCheckReagentc) {
    $btnCheckReagentc.Add_Click({

    $diagBox = Get-Control -Name "DiagBox"
    if ($diagBox) {
        $diagBox.Text = "Checking Reagentc (Windows Recovery Environment) health...`n`n"
    }
    $reagentcHealth = Get-ReagentcHealth
    
    $output = "REAGENTC HEALTH CHECK`n"
    $output += "===============================================================`n`n"
    $output += "$($reagentcHealth.Message)`n`n"
    
    if ($reagentcHealth.WinRELocation) {
        $output += "WinRE Location: $($reagentcHealth.WinRELocation)`n`n"
    }
    
    $output += "DETAILED OUTPUT:`n"
    $output += "---------------------------------------------------------------`n"
    foreach ($line in $reagentcHealth.Details) {
        $output += "$line`n"
    }
    
    $output += "`n`nRECOMMENDATIONS:`n"
    $output += "---------------------------------------------------------------`n"
    if ($reagentcHealth.Status -eq "Disabled") {
        $output += "To enable WinRE, run: reagentc /enable`n"
        $output += "To set WinRE location: reagentc /setreimage /path [path]`n"
    } else {
        $output += "WinRE appears to be properly configured.`n"
    }
    
    if ($diagBox) {
        $diagBox.Text = $output
    }
    })
}

$btnGetOSInfo = Get-Control "BtnGetOSInfo"
if ($btnGetOSInfo) {
    $btnGetOSInfo.Add_Click({
        $diagDriveCombo = Get-Control "DiagDriveCombo"
        $selectedDrive = if ($diagDriveCombo) { $diagDriveCombo.SelectedItem } else { $null }
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $diagBox = Get-Control "DiagBox"
    if ($diagBox) {
        $diagBox.Text = "Gathering Operating System information for drive $drive`:...`n`n"
    }
    
    # #region agent log
    try {
        $logPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".cursor\debug.log"
        $logEntry = @{
            sessionId = "debug-session"
            runId = "gui-osinfo"
            hypothesisId = "OSINFO-NULL"
            location = "WinRepairGUI.ps1:before-Get-OSInfo"
            message = "About to call Get-OSInfo"
            data = @{ drive = $drive }
            timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    # #endregion agent log
    
    try {
        $osInfo = Get-OSInfo -TargetDrive $drive
    } catch {
        # #region agent log
        try {
            $logEntry = @{
                sessionId = "debug-session"
                runId = "gui-osinfo"
                hypothesisId = "OSINFO-NULL"
                location = "WinRepairGUI.ps1:Get-OSInfo-exception"
                message = "Get-OSInfo threw exception"
                data = @{ error = $_.Exception.Message; drive = $drive }
                timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            } | ConvertTo-Json -Compress
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
        } catch {}
        # #endregion agent log
        $osInfo = @{
            ErrorMessage = "Failed to retrieve OS information: $($_.Exception.Message)"
            IsCurrentOS = $false
        }
    }
    
    # #region agent log
    try {
        $logEntry = @{
            sessionId = "debug-session"
            runId = "gui-osinfo"
            hypothesisId = "OSINFO-NULL"
            location = "WinRepairGUI.ps1:after-Get-OSInfo"
            message = "Get-OSInfo returned"
            data = @{ osInfoIsNull = ($null -eq $osInfo); hasError = if ($osInfo) { ($null -ne $osInfo.ErrorMessage) } else { $false }; hasIsCurrentOS = if ($osInfo) { ($null -ne $osInfo.IsCurrentOS) } else { $false } }
            timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    # #endregion agent log
    
    $output = "OPERATING SYSTEM INFORMATION`n"
    $output += "===============================================================`n`n"
    
    # Check if osInfo is null
    if ($null -eq $osInfo) {
        $output += "[ERROR] Failed to retrieve OS information. Get-OSInfo returned null.`n"
        $output += "Drive: $drive`:`n`n"
        if ($diagBox) {
            $diagBox.Text = $output
        }
        return
    }
    
    # Show current OS indicator (safe property access)
    if ($osInfo.PSObject.Properties.Name -contains 'IsCurrentOS' -and $osInfo.IsCurrentOS) {
        $output += "[CURRENT OS] This is the operating system you are currently running from.`n"
        $output += "Drive: $drive`: (System Drive: $($env:SystemDrive))`n`n"
    } else {
        $output += "[OFFLINE OS] This is an offline Windows installation.`n"
        $output += "Drive: $drive`: (Not currently running)`n`n"
    }
    
    # Check for error property safely
    if ($osInfo.PSObject.Properties.Name -contains 'Error' -and $osInfo.Error) {
        $output += "[ERROR] $($osInfo.Error)`n"
    } else {
        if ($osInfo.PSObject.Properties.Name -contains 'OSName') {
            $output += "OS Name: $($osInfo.OSName)`n"
        }
        if ($osInfo.PSObject.Properties.Name -contains 'Version') {
            $output += "Version: $($osInfo.Version)`n"
        }
        if ($osInfo.PSObject.Properties.Name -contains 'BuildNumber' -and $osInfo.BuildNumber) {
            $output += "Build Number: $($osInfo.BuildNumber)`n"
        }
        if ($osInfo.PSObject.Properties.Name -contains 'UBR' -and $osInfo.UBR) {
            $output += "Update Build Revision (UBR): $($osInfo.UBR)`n"
        }
        if ($osInfo.PSObject.Properties.Name -contains 'ReleaseId' -and $osInfo.ReleaseId) {
            $output += "Release ID: $($osInfo.ReleaseId)`n"
        }
        if ($osInfo.PSObject.Properties.Name -contains 'EditionID' -and $osInfo.EditionID) {
            $output += "Edition: $($osInfo.EditionID)`n"
        }
        if ($osInfo.PSObject.Properties.Name -contains 'Architecture' -and $osInfo.Architecture) {
            $output += "Architecture: $($osInfo.Architecture)`n"
        }
        if ($osInfo.PSObject.Properties.Name -contains 'Language' -and $osInfo.Language) {
            $output += "Language: $($osInfo.Language)"
            if ($osInfo.PSObject.Properties.Name -contains 'LanguageCode' -and $osInfo.LanguageCode) {
                $output += " (Code: $($osInfo.LanguageCode))"
            }
        }
        $output += "`n"
        
        # Show Insider build info
        if ($osInfo.PSObject.Properties.Name -contains 'IsInsider' -and $osInfo.IsInsider) {
            $output += "`n[INSIDER BUILD DETECTED]`n"
            $output += "This is a Windows Insider Preview build.`n"
            if ($osInfo.PSObject.Properties.Name -contains 'InsiderChannel' -and $osInfo.InsiderChannel) {
                $output += "Channel: $($osInfo.InsiderChannel)`n"
            }
            $output += "`nINSIDER ISO DOWNLOAD LINKS:`n"
            $output += "---------------------------------------------------------------`n"
            $output += "Official Insider ISO Downloads:`n"
            if ($osInfo.PSObject.Properties.Name -contains 'InsiderLinks' -and $osInfo.InsiderLinks -and $osInfo.InsiderLinks.DevChannel) {
                $output += "  $($osInfo.InsiderLinks.DevChannel)`n`n"
            }
            $output += "UUP Dump (Community ISO Builder):`n"
            if ($osInfo.PSObject.Properties.Name -contains 'InsiderLinks' -and $osInfo.InsiderLinks -and $osInfo.InsiderLinks.UUP) {
                $output += "  $($osInfo.InsiderLinks.UUP)`n"
            }
            if ($osInfo.PSObject.Properties.Name -contains 'BuildNumber' -and $osInfo.BuildNumber) {
                $output += "  (Search for build $($osInfo.BuildNumber) to find matching ISO)`n`n"
            }
        }
        
        if ($osInfo.PSObject.Properties.Name -contains 'InstallDate' -and $osInfo.InstallDate) {
            $output += "Install Date: $($osInfo.InstallDate)`n"
        }
        if ($osInfo.PSObject.Properties.Name -contains 'SerialNumber' -and $osInfo.SerialNumber) {
            $output += "Serial Number: $($osInfo.SerialNumber)`n"
        }
        
        # Show recommended ISO (only if not insider, or show both)
        if ($osInfo.PSObject.Properties.Name -contains 'IsInsider' -and -not $osInfo.IsInsider) {
            $output += "`n`nRECOMMENDED RECOVERY ISO:`n"
            $output += "===============================================================`n"
            $output += "To create a compatible recovery ISO, you need:`n`n"
            if ($osInfo.PSObject.Properties.Name -contains 'RecommendedISO' -and $osInfo.RecommendedISO) {
                if ($osInfo.RecommendedISO.Architecture) {
                    $output += "Architecture: $($osInfo.RecommendedISO.Architecture)`n"
                }
                if ($osInfo.RecommendedISO.Language) {
                    $lang = if ($osInfo.PSObject.Properties.Name -contains 'Language' -and $osInfo.Language) { $osInfo.Language } else { "" }
                    $output += "Language: $($osInfo.RecommendedISO.Language) ($lang)`n"
                }
                if ($osInfo.RecommendedISO.Version) {
                    $output += "Version: $($osInfo.RecommendedISO.Version)`n`n"
                }
            }
            $output += "Download from:`n"
            if ($osInfo.PSObject.Properties.Name -contains 'RecommendedISO' -and $osInfo.RecommendedISO -and $osInfo.RecommendedISO.Version -match "11") {
                $output += "  https://www.microsoft.com/software-download/windows11`n"
            } else {
                $output += "  https://www.microsoft.com/software-download/windows10`n"
            }
            $output += "`nMake sure to select:`n"
            if ($osInfo.PSObject.Properties.Name -contains 'RecommendedISO' -and $osInfo.RecommendedISO -and $osInfo.RecommendedISO.Architecture) {
                $output += "- $($osInfo.RecommendedISO.Architecture) architecture`n"
            }
            if ($osInfo.PSObject.Properties.Name -contains 'Language' -and $osInfo.Language) {
                $output += "- $($osInfo.Language) language`n"
            }
            $output += "- The same or newer version than your current installation`n"
        } else {
            $output += "`n`nNOTE: For Insider builds, use the Insider ISO links above.`n"
            $output += "Standard Windows 10/11 ISOs may not be compatible with Insider builds.`n"
        }
    }
    
    if ($diagBox) {
        $diagBox.Text = $output
    }
    })
} else {
    Write-Warning "BtnGetOSInfo control not found in XAML"
}

# Install Failure Analysis button
$btnInstallFailure = Get-Control -Name "BtnInstallFailure"
if ($btnInstallFailure) {
    $btnInstallFailure.Add_Click({

    $diagDriveCombo = Get-Control -Name "DiagDriveCombo"
    $selectedDrive = if ($diagDriveCombo) { $diagDriveCombo.SelectedItem } else { $null }
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $diagBox = Get-Control -Name "DiagBox"
    Update-StatusBar -Message "Analyzing Windows installation failure reasons..." -ShowProgress
    if ($diagBox) {
        $diagBox.Text = "Analyzing Windows installation failure reasons for drive $drive`:...`n`nPlease wait...`n"
    }
    
    $analysis = Get-WindowsInstallFailureReasons -TargetDrive $drive
    if ($DiagBox) {
        $DiagBox.Text = $analysis.Report
    }
    Update-StatusBar -Message "Install failure analysis complete" -HideProgress
    
    if ($analysis.FailureReasons.Count -gt 0) {
        [System.Windows.MessageBox]::Show(
            "Installation failure analysis complete.`n`nFound $($analysis.FailureReasons.Count) potential failure reason(s).`n`nSee the Diagnostics tab for full details and recommendations.",
            "Analysis Complete",
            "OK",
            "Warning"
        )
    } else {
        [System.Windows.MessageBox]::Show(
            "Installation failure analysis complete.`n`nNo obvious failure reasons detected. Review the log files manually for details.",
            "Analysis Complete",
            "OK",
            "Information"
        )
    }
    })
}

# Diagnostics & Logs Tab Handlers
$btnDriverForensics = Get-Control -Name "BtnDriverForensics"
if ($btnDriverForensics) {
    $btnDriverForensics.Add_Click({
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "Running storage driver forensics analysis...`n`nScanning for missing devices and matching to INF files...`n"
        }
        
        $forensics = Get-MissingDriverForensics
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $forensics
        }
    })
}

$btnAnalyzeBootLog = Get-Control -Name "BtnAnalyzeBootLog"
if ($btnAnalyzeBootLog) {
    $btnAnalyzeBootLog.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "Analyzing boot log from $drive`:...`n`n"
        }
        
        $bootLog = Get-BootLogAnalysis -TargetDrive $drive
        
        $output = $bootLog.Summary
        
        if ($bootLog.Found) {
            $output += "`n`nDETAILED DRIVER FAILURES:`n"
            $output += "---------------------------------------------------------------`n"
            if ($bootLog.FailedDrivers.Count -gt 0) {
                $num = 1
                foreach ($driver in $bootLog.FailedDrivers | Select-Object -First 20) {
                    $output += "$num. $driver`n"
                    $num++
                }
            } else {
                $output += "No driver failures recorded.`n"
            }
        }
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $output
        }
    })
}

$btnAnalyzeEventLogs = Get-Control -Name "BtnAnalyzeEventLogs"
if ($btnAnalyzeEventLogs) {
    $btnAnalyzeEventLogs.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "Analyzing event logs from $drive`:...`n`nThis may take a moment...`n"
        }
        
        $eventLogs = Get-OfflineEventLogs -TargetDrive $drive
        
        if ($logAnalysisBox) {
            if ($eventLogs.Success) {
                $logAnalysisBox.Text = $eventLogs.Summary
            } else {
                $logAnalysisBox.Text = $eventLogs.Summary
            }
        }
    })
}

# Comprehensive Log Analysis button
$btnComprehensiveLogAnalysis = Get-Control -Name "BtnComprehensiveLogAnalysis"
if ($btnComprehensiveLogAnalysis) {
    $btnComprehensiveLogAnalysis.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        # Disable button during analysis
        if ($btnComprehensiveLogAnalysis) {
            $btnComprehensiveLogAnalysis.IsEnabled = $false
        }
        
        # Progress steps for status updates
        $progressSteps = @(
            "Step 1/4: Gathering Tier 1 logs (crash dumps, memory dumps)...",
            "Step 2/4: Gathering Tier 2 logs (boot pipeline, setup logs)...",
            "Step 3/4: Gathering Tier 3 logs (system events, SRT trail)...",
            "Step 4/4: Analyzing logs and generating report..."
        )
        
        Update-StatusBar -Message $progressSteps[0] -ShowProgress
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "COMPREHENSIVE LOG ANALYSIS`n" +
                                                "===============================================================`n" +
                                                "Target Drive: $drive`:`n`n" +
                                                $progressSteps[0] + "`n" +
                                                "This may take several moments...`n`n" +
                                                "Please wait..."
        }
        
        try {
            # Run analysis in background job to keep UI responsive
            # Use module-level $scriptRoot or resolve safely
            if (-not $scriptRoot) {
                if ($PSScriptRoot) {
                    $scriptRoot = $PSScriptRoot
                } elseif ($MyInvocation.MyCommand.Path) {
                    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
                } else {
                    $scriptRoot = if (Test-Path "Helper\LogAnalysis.ps1") { "Helper" } else { Get-Location }
                }
            }
            $analysisJob = Start-Job -ScriptBlock {
                param($Drive, $ScriptRoot)
                Set-Location $ScriptRoot
                $logAnalysisPath = Join-Path $ScriptRoot "Helper\LogAnalysis.ps1"
                if (-not (Test-Path $logAnalysisPath)) {
                    $logAnalysisPath = Join-Path $ScriptRoot "LogAnalysis.ps1"
                }
                if (Test-Path $logAnalysisPath) {
                    . $logAnalysisPath
                }
                Get-ComprehensiveLogAnalysis -TargetDrive $Drive
            } -ArgumentList $drive, $scriptRoot
            
            # Update status bar while job is running (simulate progress)
            $stepIndex = 0
            $lastUpdate = Get-Date
            while ($analysisJob.State -eq 'Running') {
                Start-Sleep -Milliseconds 500
                
                # Update status every 3 seconds to show progress
                if (((Get-Date) - $lastUpdate).TotalSeconds -ge 3 -and $stepIndex -lt $progressSteps.Count - 1) {
                    $stepIndex++
                    $lastUpdate = Get-Date
                    $W.Dispatcher.Invoke([action]{
                        Update-StatusBar -Message $progressSteps[$stepIndex] -ShowProgress
                        if ($logAnalysisBox) {
                            $currentText = $logAnalysisBox.Text
                            # Update the step in the text box
                            $newText = $currentText -replace "Step \d+/4:.*", $progressSteps[$stepIndex]
                            if ($newText -ne $currentText) {
                                $logAnalysisBox.Text = $newText
                                $logAnalysisBox.ScrollToEnd()
                            }
                        }
                    }, [System.Windows.Threading.DispatcherPriority]::Background)
                }
            }
            
            # Get results
            $analysis = Receive-Job -Job $analysisJob -Wait
            Remove-Job -Job $analysisJob -Force
            
            if ($analysis.Success) {
                $output = $analysis.Report
                if ($analysis.RootCauseSummary) {
                    $output += "`n`n" + $analysis.RootCauseSummary
                }
                if ($analysis.Recommendations.Count -gt 0) {
                    $output += "`n`nRECOMMENDATIONS:`n"
                    $output += "-" * 80 + "`n"
                    $counter = 1
                    foreach ($rec in $analysis.Recommendations) {
                        $output += "$counter. $rec`n"
                        $counter++
                    }
                }
                if ($logAnalysisBox) {
                    $logAnalysisBox.Text = $output
                }
                Update-StatusBar -Message "[SUCCESS] Comprehensive log analysis complete - $($analysis.Tier1.LogFilesFound.Count + $analysis.Tier2.LogFilesFound.Count + $analysis.Tier3.LogFilesFound.Count) log files analyzed" -HideProgress
            } else {
                if ($logAnalysisBox) {
                    $logAnalysisBox.Text = "Analysis completed with errors.`n`n$($analysis.Report)"
                }
                Update-StatusBar -Message "[WARNING] Log analysis completed with errors - check output for details" -HideProgress
            }
        } catch {
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = "ERROR: Failed to perform comprehensive log analysis`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)"
            }
            Update-StatusBar -Message "[ERROR] Log analysis failed - see error details above" -HideProgress
        } finally {
            # Re-enable button
            if ($btnComprehensiveLogAnalysis) {
                $btnComprehensiveLogAnalysis.IsEnabled = $true
            }
            # Clean up job if it still exists
            if ($analysisJob) {
                Remove-Job -Job $analysisJob -Force -ErrorAction SilentlyContinue
            }
        }
    })
}

# Open Event Viewer button
$btnOpenEventViewer = Get-Control -Name "BtnOpenEventViewer"
if ($btnOpenEventViewer) {
    $btnOpenEventViewer.Add_Click({
        try {
            $result = Open-EventViewer
            if ($result.Success) {
                Update-StatusBar -Message "Event Viewer opened" -HideProgress
            } else {
                [System.Windows.MessageBox]::Show(
                    "Failed to open Event Viewer: $($result.Message)",
                    "Error",
                    "OK",
                    "Error"
                )
            }
        } catch {
            [System.Windows.MessageBox]::Show(
                "Failed to open Event Viewer: $_",
                "Error",
                "OK",
                "Error"
            )
        }
    })
}

# Crash Dump Analyzer button
$btnCrashDumpAnalyzer = Get-Control -Name "BtnCrashDumpAnalyzer"
if ($btnCrashDumpAnalyzer) {
    $btnCrashDumpAnalyzer.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        # Check for MEMORY.DMP first
        $memoryDump = "$drive`:\Windows\MEMORY.DMP"
        $dumpPath = ""
        
        if (Test-Path $memoryDump) {
            $result = [System.Windows.MessageBox]::Show(
                "MEMORY.DMP found at:`n$memoryDump`n`nDo you want to analyze this dump file?`n`n(Click No to open Crash Analyzer without a file)",
                "Crash Dump Found",
                "YesNo",
                "Question"
            )
            if ($result -eq "Yes") {
                $dumpPath = $memoryDump
            }
        }
        
        try {
            $result = Start-CrashAnalyzer -DumpPath $dumpPath
            if ($result.Success) {
                Update-StatusBar -Message $result.Message -HideProgress
            } else {
                # Show alternatives if crashanalyze.exe failed
                $altMethods = if ($result.AlternativeMethods) { "`n`nAlternative Methods:`n" + ($result.AlternativeMethods -join "`n") } else { "" }
                [System.Windows.MessageBox]::Show(
                    "$($result.Message)$altMethods",
                    "Crash Analyzer - Alternative Methods Available",
                    "OK",
                    "Information"
                )
            }
        } catch {
            [System.Windows.MessageBox]::Show(
                "Failed to launch Crash Analyzer: $_`n`nAlternative: Install WinDbg from Windows SDK or use Event Viewer for .evtx files.",
                "Error",
                "OK",
                "Error"
            )
        }
    })
}

# Safe event handler wiring for BtnLookupErrorCode (optional control - use Silent flag)
$btnLookupErrorCode = Get-Control -Name "BtnLookupErrorCode" -Silent
if ($btnLookupErrorCode) {
    $btnLookupErrorCode.Add_Click({
        # Ensure core (precision helpers) is loaded
        try {
            . "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load core engine: $_","Error","OK","Error") | Out-Null
            return
        }

        $errorCodeInput = Get-Control -Name "ErrorCodeInput"
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        if (-not $errorCodeInput -or -not $logAnalysisBox) {
            [System.Windows.MessageBox]::Show(
                "Required controls not found in XAML. Error code lookup feature unavailable.",
                "Feature Unavailable",
                "OK",
                "Warning"
            )
            return
        }
        
        $errorCode = $errorCodeInput.Text.Trim()
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($errorCode) -or $errorCode -eq "0x") {
            [System.Windows.MessageBox]::Show(
                "Please enter an error code to look up.`n`nExamples:`n- 0xc000000e`n- 0x80070002`n- 0x0000007B",
                "No Error Code Entered",
                "OK",
                "Warning"
            )
            return
        }
        
        $logAnalysisBox.Text = "Looking up error code: $errorCode`n`nPlease wait...`n"
        
        try {
            $errorInfo = Get-WindowsErrorCodeInfo -ErrorCode $errorCode -TargetDrive $drive
            $report = ""
            if ($errorInfo) { $report = $errorInfo.Report }

            # Precision mapping
            $prec = Search-PrecisionErrorCode -Code $errorCode
            if ($prec) {
                $report += "`n`nPRECISION MAPPING: $($prec.SuggestedTC)`nNotes: $($prec.Notes)`n"
            }

            # Minidump summary for quick triage
            $dumps = Get-PrecisionDumpSummary -WindowsRoot "$drive`:\Windows" -Max 3
            if ($dumps -and $dumps.Count -gt 0) {
                $report += "`nRecent minidumps on $drive`::`n"
                foreach ($d in $dumps) {
                    $report += "  $($d.LastWriteTime)  $($d.SizeMB) MB  $($d.Path)`n"
                }
            }

            # Recent BugCheck from System.evtx (offline-safe)
            $bug = Get-PrecisionRecentBugcheck -WindowsRoot "$drive`:\Windows"
            if ($bug -and $bug.Code) {
                $hex = ("0x{0:X}" -f $bug.Code)
                $report += "`nRecent BugCheck (System.evtx): $hex  Params: $($bug.Params -join ', ')`n"
                $report += "Time: $($bug.TimeCreated)`n"
            }

            if (-not $report) { $report = "No data for error code $errorCode." }
            $logAnalysisBox.Text = $report
        } catch {
            $logAnalysisBox.Text = "Error looking up error code: $_`n`nPlease verify the error code format and try again."
        }
    })
}

$btnPrecisionParity = Get-Control -Name "BtnPrecisionParity" -Silent
if ($btnPrecisionParity) {
    $btnPrecisionParity.Add_Click({
        # Ensure core loaded
        try {
            . "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load core engine: $_","Error","OK","Error") | Out-Null
            return
        }

        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        $drive = "C"
        if ($logDriveCombo) {
            $sel = $logDriveCombo.SelectedItem
            if ($sel -and $sel -match '^([A-Z]):') { $drive = $matches[1] }
        }
        $windowsRoot = "$drive`:\Windows"

        try {
            $logAnalysisBox.Text = "Running precision parity harness for $windowsRoot (ESP Z)...`n`n"
            $parity = Invoke-PrecisionParityHarness -WindowsRoot $windowsRoot -EspDriveLetter "Z" -ActionLogPath "$env:TEMP\precision-actions.log"
            $report = "PRECISION PARITY (TC-010)`n"
            $report += "=====================================`n"
            $report += "CLI detections: $($parity.Cli.Detections.Count)`n"
            if ($parity.Parity.Matches) {
                $report += "Parity: MATCH (CLI vs GUI/TUI)`n"
            } else {
                $report += "Parity: DIFFERENCES`n"
                $parity.Parity.Differences | ForEach-Object { $report += " - $_`n" }
            }
            if ($parity.Cli.Detections) {
                $report += "`nDetections:`n"
                foreach ($d in $parity.Cli.Detections) {
                    $report += "[$($d.Id)] $($d.Title) (Cat: $($d.Category))`n"
                }
            }
            $logAnalysisBox.Text = $report
        } catch {
            $logAnalysisBox.Text = "Precision parity harness failed: $_"
        }
    })
}

$btnPrecisionParitySave = Get-Control -Name "BtnPrecisionParitySave" -Silent
if ($btnPrecisionParitySave) {
    $btnPrecisionParitySave.Add_Click({
        try {
            . "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load core engine: $_","Error","OK","Error") | Out-Null
            return
        }

        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $drive = "C"
        if ($logDriveCombo) {
            $sel = $logDriveCombo.SelectedItem
            if ($sel -and $sel -match '^([A-Z]):') { $drive = $matches[1] }
        }
        $windowsRoot = "$drive`:\Windows"

        $defaultPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "precision-parity.json"
        $saveDlg = New-Object Microsoft.Win32.SaveFileDialog
        $saveDlg.FileName = "precision-parity"
        $saveDlg.DefaultExt = ".json"
        $saveDlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $saveDlg.InitialDirectory = Split-Path $defaultPath -Parent
        $saveDlg.ShowDialog() | Out-Null
        if (-not $saveDlg.FileName) { return }

        try {
            $null = Invoke-PrecisionParityHarness -WindowsRoot $windowsRoot -EspDriveLetter "Z" -AsJson -OutFile $saveDlg.FileName -ActionLogPath "$env:TEMP\precision-actions.log"
            [System.Windows.MessageBox]::Show("Precision parity JSON saved to:`n$($saveDlg.FileName)","Parity JSON Saved","OK","Information") | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Precision parity JSON save failed: $_","Error","OK","Error") | Out-Null
        }
    })
}

$btnPrecisionJson = Get-Control -Name "BtnPrecisionJson" -Silent
if ($btnPrecisionJson) {
    $btnPrecisionJson.Add_Click({
        try {
            . "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load core engine: $_","Error","OK","Error") | Out-Null
            return
        }

        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        $drive = "C"
        if ($logDriveCombo) {
            $sel = $logDriveCombo.SelectedItem
            if ($sel -and $sel -match '^([A-Z]):') { $drive = $matches[1] }
        }
        $windowsRoot = "$drive`:\Windows"

        try {
            $json = Invoke-PrecisionQuickScan -WindowsRoot $windowsRoot -EspDriveLetter "Z" -AsJson -IncludeBugcheck -ActionLogPath "$env:TEMP\precision-actions.log"
            $logAnalysisBox.Text = $json
        } catch {
            $logAnalysisBox.Text = "Precision JSON export failed: $_"
        }
    })
}

$btnPrecisionJsonSave = Get-Control -Name "BtnPrecisionJsonSave" -Silent
if ($btnPrecisionJsonSave) {
    $btnPrecisionJsonSave.Add_Click({
        try {
            . "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load core engine: $_","Error","OK","Error") | Out-Null
            return
        }

        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $drive = "C"
        if ($logDriveCombo) {
            $sel = $logDriveCombo.SelectedItem
            if ($sel -and $sel -match '^([A-Z]):') { $drive = $matches[1] }
        }
        $windowsRoot = "$drive`:\Windows"

        $defaultPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "precision-scan.json"
        $saveDlg = New-Object Microsoft.Win32.SaveFileDialog
        $saveDlg.FileName = "precision-scan"
        $saveDlg.DefaultExt = ".json"
        $saveDlg.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $saveDlg.InitialDirectory = Split-Path $defaultPath -Parent
        $saveDlg.ShowDialog() | Out-Null
        if (-not $saveDlg.FileName) { return }

        try {
            $null = Invoke-PrecisionQuickScan -WindowsRoot $windowsRoot -EspDriveLetter "Z" -AsJson -IncludeBugcheck -OutFile $saveDlg.FileName
            [System.Windows.MessageBox]::Show("Precision scan JSON saved to:`n$($saveDlg.FileName)","Precision JSON Saved","OK","Information") | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Precision JSON save failed: $_","Error","OK","Error") | Out-Null
        }
    })
}

$btnBootChainAnalysis = Get-Control -Name "BtnBootChainAnalysis" -Silent
if ($btnBootChainAnalysis) {
    $btnBootChainAnalysis.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "Analyzing boot chain for drive $drive`:...`n`nThis will identify where Windows failed in the boot process...`n`nPlease wait...`n"
        }
        
        try {
            $chainAnalysis = Get-BootChainAnalysis -TargetDrive $drive
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = $chainAnalysis.Report
            }
        } catch {
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = "Error analyzing boot chain: $_"
            }
        }
    })
}

$btnFullBootDiagnosis = Get-Control -Name "BtnFullBootDiagnosis"
if ($btnFullBootDiagnosis) {
    $btnFullBootDiagnosis.Add_Click({
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        # Ensure core is loaded (idempotent)
        try {
            . "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load core engine: $_","Error","OK","Error") | Out-Null
            return
        }
        
        # Scan for Windows installations
        try {
            Update-StatusBar -Message "Scanning for Windows installations..." -ShowProgress
            $installations = @(Get-WindowsInstallations)
            
            if ($installations.Count -eq 0) {
                [System.Windows.MessageBox]::Show(
                    "No Windows installations found.`n`nPlease ensure you have access to Windows drives and try again.",
                    "No Windows Found",
                    "OK",
                    "Warning"
                ) | Out-Null
                Update-StatusBar -Message "No Windows installations found" -HideProgress
                return
            }
            
            # Create drive selection dialog
            $driveSelection = New-Object System.Windows.Forms.Form
            $driveSelection.Text = "Select Windows Installation"
            $driveSelection.Size = New-Object System.Drawing.Size(700, 500)
            $driveSelection.StartPosition = "CenterScreen"
            $driveSelection.FormBorderStyle = "FixedDialog"
            $driveSelection.MaximizeBox = $false
            $driveSelection.MinimizeBox = $false
            
            $label = New-Object System.Windows.Forms.Label
            $label.Location = New-Object System.Drawing.Point(10, 10)
            $label.Size = New-Object System.Drawing.Size(660, 30)
            $label.Text = "Select the Windows installation to diagnose:"
            $driveSelection.Controls.Add($label)
            
            $listView = New-Object System.Windows.Forms.ListView
            $listView.Location = New-Object System.Drawing.Point(10, 40)
            $listView.Size = New-Object System.Drawing.Size(660, 350)
            $listView.View = [System.Windows.Forms.View]::Details
            $listView.FullRowSelect = $true
            $listView.GridLines = $true
            $listView.MultiSelect = $false
            
            # Add columns
            $listView.Columns.Add("Drive", 60) | Out-Null
            $listView.Columns.Add("Label", 120) | Out-Null
            $listView.Columns.Add("OS Version", 150) | Out-Null
            $listView.Columns.Add("Size", 80) | Out-Null
            $listView.Columns.Add("Free", 80) | Out-Null
            $listView.Columns.Add("Used %", 70) | Out-Null
            $listView.Columns.Add("Health", 80) | Out-Null
            $listView.Columns.Add("Boot Type", 100) | Out-Null
            
            # Add installations to list
            foreach ($inst in $installations) {
                $item = New-Object System.Windows.Forms.ListViewItem($inst.Drive)
                $item.SubItems.Add($inst.VolumeLabel) | Out-Null
                $item.SubItems.Add("$($inst.OSVersion) Build $($inst.OSBuild)") | Out-Null
                $item.SubItems.Add("$($inst.SizeGB) GB") | Out-Null
                $item.SubItems.Add("$($inst.FreeGB) GB") | Out-Null
                $item.SubItems.Add("$($inst.UsedPercent)%") | Out-Null
                $item.SubItems.Add($inst.HealthStatus) | Out-Null
                $item.SubItems.Add($inst.BootType) | Out-Null
                $item.Tag = $inst
                
                # Highlight current OS
                if ($inst.IsCurrentOS) {
                    $item.BackColor = [System.Drawing.Color]::LightGreen
                    $item.Selected = $true
                }
                
                $listView.Items.Add($item) | Out-Null
            }
            
            $driveSelection.Controls.Add($listView)
            
            $okButton = New-Object System.Windows.Forms.Button
            $okButton.Text = "OK"
            $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $okButton.Location = New-Object System.Drawing.Point(500, 400)
            $okButton.Size = New-Object System.Drawing.Size(80, 30)
            $driveSelection.Controls.Add($okButton)
            $driveSelection.AcceptButton = $okButton
            
            $cancelButton = New-Object System.Windows.Forms.Button
            $cancelButton.Text = "Cancel"
            $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $cancelButton.Location = New-Object System.Drawing.Point(590, 400)
            $cancelButton.Size = New-Object System.Drawing.Size(80, 30)
            $driveSelection.Controls.Add($cancelButton)
            $driveSelection.CancelButton = $cancelButton
            
            # Show dialog
            $result = $driveSelection.ShowDialog()
            
            if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $listView.SelectedItems.Count -gt 0) {
                $selectedInst = $listView.SelectedItems[0].Tag
                $drive = $selectedInst.DriveLetter
            } else {
                Update-StatusBar -Message "Drive selection cancelled" -HideProgress
                return
            }
            
            $driveSelection.Dispose()
        } catch {
            [System.Windows.MessageBox]::Show(
                "Error scanning for Windows installations: $_`n`nFalling back to default drive C:",
                "Scan Error",
                "OK",
                "Warning"
            ) | Out-Null
            $drive = "C"
        }
        
        Update-StatusBar -Message "Selected: $drive`:" -HideProgress
        
        # Ask user for operation mode
        $modeResponse = [System.Windows.MessageBox]::Show(
            "BOOT DIAGNOSIS AND REPAIR`n`n" +
            "This will analyze 8 phases of the boot process:`n" +
            "1. UEFI/GPT Integrity Check`n" +
            "2. BCD File & Integrity`n" +
            "3. BCD Entries Validation`n" +
            "4. WinRE Access`n" +
            "5. Driver Matching`n" +
            "6. Windows Kernel`n" +
            "7. Boot Log Analysis`n" +
            "8. Event Log Analysis`n`n" +
            "Select operation mode:`n`n" +
            "Yes = DIAGNOSIS + FIX (automatically fixes issues)`n" +
            "No = DIAGNOSIS ONLY (find what's broken, no fixes)`n`n" +
            "Cancel = DIAGNOSIS THEN ASK (diagnose first, then ask about fixes)",
            "Boot Diagnosis Mode",
            "YesNoCancel",
            "Question"
        )
        
        $mode = switch ($modeResponse) {
            "Yes" { "DiagnosisAndFix" }
            "No" { "DiagnosisOnly" }
            "Cancel" { "DiagnosisThenAsk" }
            default { "DiagnosisOnly" }
        }
        
        # Ask user for verbose mode
        $verboseResponse = [System.Windows.MessageBox]::Show(
            "Would you like to run in VERBOSE mode?`n`n" +
            "Yes = Verbose (detailed command logging, opens Notepad)`n" +
            "No = Regular (standard analysis)`n`n" +
            "Estimated time: 2-5 minutes (Regular) or 5-10 minutes (Verbose)",
            "Verbose Mode",
            "YesNo",
            "Question"
        )
        $verbose = ($verboseResponse -eq "Yes")
        
        # Create log file for command tracking
        $logFile = "$env:TEMP\BootDiagnosis_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        if ($verbose) {
            try {
                "BOOT DIAGNOSIS COMMAND LOG`n" +
                "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" +
                "Mode: VERBOSE`n" +
                "Target Drive: $drive`:`n" +
                "===============================================================`n`n" | Out-File $logFile -Encoding UTF8
            } catch {
                $logFile = $null
            }
        }
        
        if ($logAnalysisBox) {
            $modeText = if ($verbose) { "VERBOSE MODE" } else { "REGULAR MODE" }
            $logAnalysisBox.Text = "FULL BOOT DIAGNOSIS - $modeText`n" +
                                   "===============================================================`n" +
                                   "Target: $drive`:\Windows`n" +
                                   "Total Phases: 8`n`n" +
                                   "BOOT DIAGNOSIS PROCESS:`n" +
                                   "1. UEFI/GPT Integrity Check - Checking EFI partition, format (FAT32), and Microsoft Boot folder structure`n" +
                                   "2. BCD File & Integrity - Locating and validating Boot Configuration Data file accessibility`n" +
                                   "3. BCD Entries Validation - Verifying boot manager and default boot entries exist`n" +
                                   "4. WinRE Access - Checking Windows Recovery Environment availability and accessibility`n" +
                                   "5. Driver Matching - Scanning for missing or errored storage controller drivers (VMD, RAID, NVMe)`n" +
                                   "6. Windows Kernel - Verifying critical system files (ntoskrnl.exe) exist`n" +
                                   "7. Boot Log Analysis - Checking for boot log files (ntbtlog.txt) for driver loading issues`n" +
                                   "8. Event Log Analysis - Validating system event logs for crash and error information`n`n" +
                                   "===============================================================`n" +
                                   "Starting analysis...`n`n"
            if ($verbose -and $logFile) {
                $logAnalysisBox.Text += "Command log file: $logFile`n"
                $logAnalysisBox.Text += "Notepad will open automatically to show real-time updates.`n`n"
            }
        }
        
        # Define the 8 actual phases (matching Run-BootDiagnosis)
        $bootPhases = @(
            @{ Number = 1; Name = "Phase 1: UEFI/GPT Integrity Check"; Description = "Checking EFI partition, format (FAT32), and Microsoft Boot folder structure" },
            @{ Number = 2; Name = "Phase 2: BCD File & Integrity"; Description = "Locating and validating Boot Configuration Data file accessibility" },
            @{ Number = 3; Name = "Phase 3: BCD Entries Validation"; Description = "Verifying boot manager and default boot entries exist" },
            @{ Number = 4; Name = "Phase 4: WinRE Access"; Description = "Checking Windows Recovery Environment availability and accessibility" },
            @{ Number = 5; Name = "Phase 5: Driver Matching"; Description = "Scanning for missing or errored storage controller drivers (VMD, RAID, NVMe)" },
            @{ Number = 6; Name = "Phase 6: Windows Kernel"; Description = "Verifying critical system files (ntoskrnl.exe) exist" },
            @{ Number = 7; Name = "Phase 7: Boot Log Analysis"; Description = "Checking for boot log files (ntbtlog.txt) for driver loading issues" },
            @{ Number = 8; Name = "Phase 8: Event Log Analysis"; Description = "Validating system event logs for crash and error information" }
        )
        
        # Show initial boot stack
        $bootStackText = "`n═══════════════════════════════════════════════════════════`n"
        $bootStackText += "                    BOOT STACK ANALYSIS`n"
        $bootStackText += "═══════════════════════════════════════════════════════════`n`n"
        foreach ($phase in $bootPhases) {
            $bootStackText += "  [  ] $($phase.Name)`n"
            $bootStackText += "      -> $($phase.Description)`n`n"
        }
        $bootStackText += "═══════════════════════════════════════════════════════════`n`n"
        $bootStackText += "Analyzing boot process...`n`n"
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $bootStackText
            $logAnalysisBox.ScrollToEnd()
        }
        
        # Progress callback for boot diagnosis with real-time updates
        $progressCallback = {
            param($progress)
            if ($logAnalysisBox) {
                $phaseNum = if ($progress.Phase) { $progress.Phase } else { 0 }
                $percentage = if ($progress.Percentage) { $progress.Percentage } else { 0 }
                $message = if ($progress.Message) { $progress.Message } else { "" }
                $command = if ($progress.Command) { $progress.Command } else { "" }
                $elapsed = if ($progress.Elapsed) { $progress.Elapsed } else { [TimeSpan]::Zero }
                
                # Update boot stack visualization with real progress
                $bootStackText = "FULL BOOT DIAGNOSIS - $(if ($verbose) { 'VERBOSE MODE' } else { 'REGULAR MODE' })`n"
                $bootStackText += "===============================================================`n"
                $bootStackText += "Target: $drive`:\Windows`n"
                $bootStackText += "Progress: $percentage% | Elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) minutes`n"
                $bootStackText += "===============================================================`n`n"
                
                for ($i = 0; $i -lt $bootPhases.Count; $i++) {
                    $phase = $bootPhases[$i]
                    $status = "[  ]"
                    $statusText = "PENDING"
                    
                    if ($phase.Number -lt $phaseNum) {
                        $status = "[OK]"
                        $statusText = "COMPLETE"
                    } elseif ($phase.Number -eq $phaseNum) {
                        $status = "[>>]"
                        $statusText = "IN PROGRESS"
                    }
                    
                    $bootStackText += "  $status $($phase.Name) - $statusText`n"
                    $bootStackText += "      -> $($phase.Description)`n"
                    if ($phase.Number -eq $phaseNum -and $message) {
                        $bootStackText += "      Current: $message`n"
                    }
                    if ($phase.Number -eq $phaseNum -and $command -and $verbose) {
                        $bootStackText += "      Command: $command`n"
                    }
                    $bootStackText += "`n"
                }
                
                $bootStackText += "===============================================================`n"
                if ($logFile -and $verbose) {
                    $bootStackText += "Command log: $logFile (open in Notepad to see updates)`n"
                }
                $bootStackText += "===============================================================`n"
                
                $logAnalysisBox.Dispatcher.Invoke([action]{
                    $logAnalysisBox.Text = $bootStackText
                    $logAnalysisBox.ScrollToEnd()
                }, [System.Windows.Threading.DispatcherPriority]::Render)
            }
        }
        
        # Run enhanced automated diagnosis with progress
        Update-StatusBar -Message "Initializing boot diagnosis..." -ShowProgress -Percentage 1 -Stage "Initializing"
        
        # Run diagnosis and repair in background job
        $diagnosisJob = Start-Job -ScriptBlock {
            param($drive, $scriptRoot, $mode, $verbose, $logFile)
            Set-Location $scriptRoot
            . "$scriptRoot\Helper\WinRepairCore.ps1"
            
            # Create progress callback that writes to log file
            $progressCallback = {
                param($progress)
                if ($logFile) {
                    $logEntry = "[$(Get-Date -Format 'HH:mm:ss')] Phase $($progress.Phase): $($progress.Message)"
                    if ($progress.Command) {
                        $logEntry += " | Command: $($progress.Command)"
                    }
                    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
                }
            }
            
            Start-BootDiagnosisAndRepair -Drive $drive -Mode $mode -Verbose:$verbose -ProgressCallback $progressCallback -LogFile $logFile
        } -ArgumentList $drive, $PSScriptRoot, $mode, $verbose, $logFile
        
        # Give job a moment to start
        Start-Sleep -Milliseconds 500
        Update-StatusBar -Message "Boot diagnosis started..." -ShowProgress -Percentage 5 -Stage "Starting"
        
        # Monitor progress with real-time updates from job
        $lastPhase = 0
        $startTime = Get-Date
        while ($diagnosisJob.State -eq "Running") {
            Start-Sleep -Milliseconds 1000
            
            # Read log file to get latest progress (if verbose)
            if ($verbose -and $logFile -and (Test-Path $logFile)) {
                try {
                    $logContent = Get-Content $logFile -Tail 5 -ErrorAction SilentlyContinue
                    if ($logContent) {
                        $latestLine = $logContent[-1]
                        if ($latestLine -match "Phase (\d+)") {
                            $currentPhase = [int]$matches[1]
                            if ($currentPhase -ne $lastPhase) {
                                $lastPhase = $currentPhase
                                $elapsed = (Get-Date) - $startTime
                                $percentage = [math]::Round(($currentPhase / $bootPhases.Count) * 100)
                                
                                $phase = $bootPhases | Where-Object { $_.Number -eq $currentPhase }
                                $progress = @{
                                    Phase = $currentPhase
                                    PhaseName = if ($phase) { $phase.Name } else { "Unknown" }
                                    Percentage = $percentage
                                    Message = if ($phase) { $phase.Description } else { "" }
                                    Command = if ($latestLine -match "Command: (.+)") { $matches[1] } else { "" }
                                    Elapsed = $elapsed
                                }
                                & $progressCallback $progress
                                
                                Update-StatusBar -Message "Phase $currentPhase/$($bootPhases.Count): $($phase.Name) | Elapsed: $([math]::Round($elapsed.TotalMinutes, 1))m" -ShowProgress -Percentage $percentage -Stage $currentPhase
                            }
                        }
                    }
                } catch {
                    # Ignore log read errors
                }
            } else {
                # Regular mode - estimate progress based on time (fallback)
                $elapsed = (Get-Date) - $startTime
                $estimatedPhase = [math]::Min([math]::Floor($elapsed.TotalSeconds / 30) + 1, $bootPhases.Count)
                if ($estimatedPhase -ne $lastPhase) {
                    $lastPhase = $estimatedPhase
                    $percentage = [math]::Round(($estimatedPhase / $bootPhases.Count) * 100)
                    $phase = $bootPhases | Where-Object { $_.Number -eq $estimatedPhase }
                    $progress = @{
                        Phase = $estimatedPhase
                        PhaseName = if ($phase) { $phase.Name } else { "Unknown" }
                        Percentage = $percentage
                        Message = if ($phase) { $phase.Description } else { "" }
                        Elapsed = $elapsed
                    }
                    & $progressCallback $progress
                    Update-StatusBar -Message "Phase $estimatedPhase/$($bootPhases.Count): $($phase.Name) | Elapsed: $([math]::Round($elapsed.TotalMinutes, 1))m" -ShowProgress -Percentage $percentage -Stage $estimatedPhase
                }
            }
            
            [System.Windows.Forms.Application]::DoEvents()
        }
        
        # Get diagnosis and repair results
        $result = Receive-Job $diagnosisJob -ErrorAction SilentlyContinue
        Remove-Job $diagnosisJob -ErrorAction SilentlyContinue
        
        # Show final boot stack with all phases checked
        $elapsed = (Get-Date) - $startTime
        $finalProgress = @{
            Phase = $bootPhases.Count
            PhaseName = "Analysis Complete"
            Percentage = 100
            Message = "All phases completed"
            Elapsed = $elapsed
        }
        & $progressCallback $finalProgress
        
        # Handle DiagnosisThenAsk mode
        if ($result -and $result.AskForFix) {
            $fixResponse = [System.Windows.MessageBox]::Show(
                "Diagnosis found $($result.IssuesFound) issue(s).`n`n" +
                "Would you like to automatically fix these issues?`n`n" +
                "Yes = Run automated boot repair`n" +
                "No = Show diagnosis report only",
                "Apply Fixes?",
                "YesNo",
                "Question"
            )
            
            if ($fixResponse -eq "Yes") {
                # Run repair
                Update-StatusBar -Message "Running automated boot repair..." -ShowProgress
                $repairJob = Start-Job -ScriptBlock {
                    param($drive, $scriptRoot)
                    Set-Location $scriptRoot
                    . "$scriptRoot\Helper\WinRepairCore.ps1"
                    Start-AutomatedBootRepair -TargetDrive $drive -SkipConfirmation:$false -CreateRestorePoint:$true
                } -ArgumentList $drive, $PSScriptRoot
                
                while ($repairJob.State -eq "Running") {
                    Start-Sleep -Milliseconds 500
                    [System.Windows.Forms.Application]::DoEvents()
                }
                
                $repair = Receive-Job $repairJob -ErrorAction SilentlyContinue
                Remove-Job $repairJob -ErrorAction SilentlyContinue
                
                $result.Repair = $repair
                $result.Report += "`n`n" + $repair.Report
                $result.Success = $repair.Success
            }
        }
        
        # Ensure report is available
        if (-not $result) {
            $output = "Diagnosis failed: No result returned. Please check logs for errors."
        } elseif (-not $result.Report -or [string]::IsNullOrWhiteSpace($result.Report)) {
            # Build report from diagnosis if available
            if ($result.Diagnosis -and $result.Diagnosis.Report) {
                $output = $result.Diagnosis.Report
            } else {
                $output = "Diagnosis completed but report generation failed.`n`n"
                if ($result.Diagnosis) {
                    $output += "Issues Found: $($result.Diagnosis.Issues.Count)`n"
                    if ($result.Diagnosis.Issues.Count -gt 0) {
                        $output += "`nIssues:`n"
                        foreach ($issue in $result.Diagnosis.Issues) {
                            $output += "  - [$($issue.Severity)] $($issue.Type): $($issue.Description)`n"
                        }
                    }
                } else {
                    $output += "No diagnosis data available."
                }
            }
        } else {
            $output = $result.Report
        }
        
        # Add summary
        if ($result) {
            $output += "`n`n===============================================================`n"
            $output += "SUMMARY`n"
            $output += "===============================================================`n"
            $output += "Mode: $($result.Mode)`n"
            $output += "Issues Found: $($result.IssuesFound)`n"
            if ($result.IssuesFixed) {
                $output += "Issues Fixed: $($result.IssuesFixed)`n"
            }
            $output += "Success: $(if ($result.Success) { 'Yes' } else { 'No' })`n"
            if ($result.Diagnosis -and $result.Diagnosis.ElapsedTime) {
                $output += "Total Time: $([math]::Round($result.Diagnosis.ElapsedTime.TotalMinutes, 2)) minutes`n"
            }
        }
        
        # Add boot log summary if available
        $bootLog = Get-BootLogAnalysis -TargetDrive $drive
        if ($bootLog.Found) {
            $output += "`n`n"
            $output += "===============================================================`n"
            $output += "BOOT LOG SUMMARY`n"
            $output += "===============================================================`n"
            $output += "Boot log found. Critical missing drivers: $($bootLog.MissingDrivers.Count)`n"
            if ($bootLog.MissingDrivers.Count -gt 0) {
                $output += "Critical drivers that failed to load:`n"
                foreach ($driver in $bootLog.MissingDrivers) {
                    $output += "  - $driver`n"
                }
            }
        }
        
        # Add event log summary if available
        $eventLogs = Get-OfflineEventLogs -TargetDrive $drive
        if ($eventLogs.Success) {
            $output += "`n`n"
            $output += "===============================================================`n"
            $output += "EVENT LOG SUMMARY`n"
            $output += "===============================================================`n"
            $output += "Recent shutdowns: $($eventLogs.ShutdownEvents.Count)`n"
            $output += "BSOD events: $($eventLogs.BSODInfo.Count)`n"
            $output += "Recent errors: $($eventLogs.RecentErrors.Count)`n"
            if ($eventLogs.BSODInfo.Count -gt 0) {
                $output += "`nMost recent BSOD:`n"
                $latestBSOD = $eventLogs.BSODInfo | Sort-Object Time -Descending | Select-Object -First 1
                $output += "  Stop Code: $($latestBSOD.StopCode)`n"
                $output += "  $($latestBSOD.Explanation)`n"
            }
        }
        
        # Show critical issues warning if found
        if ($diagnosis.HasCriticalIssues) {
            $output += "`n`n"
            $output += "===============================================================`n"
            $output += "[WARN] CRITICAL ISSUES DETECTED - IMMEDIATE ACTION REQUIRED`n"
            $output += "===============================================================`n"
            $output += "Review the issues above and follow the recommended actions.`n"
            $output += "Use the Boot Fixer tab to apply repairs.`n"
        }
        
        # Extract and save errors to file
        $errorLines = @()
        $errorPatterns = @(
            "\[ERROR\]", "\[WARN\]", "\[CRITICAL\]", "\[FAIL\]",
            "Failed", "Error:", "Exception", "Cannot", "Missing",
            "Corrupted", "Not found", "Access denied", "Permission denied",
            "Invalid", "Unable to", "Could not", "Does not exist"
        )
        $outputLines = $output -split "`n"
        
        foreach ($line in $outputLines) {
            $trimmedLine = $line.Trim()
            if ($trimmedLine.Length -eq 0) { continue }
            
            # Skip header lines and separators
            if ($trimmedLine -match "^=+$" -or $trimmedLine -match "^BOOT STACK" -or $trimmedLine -match "^Progress:") {
                continue
            }
            
            foreach ($pattern in $errorPatterns) {
                if ($trimmedLine -match $pattern -and $trimmedLine -notmatch "^\s*#") {
                    $errorLines += $trimmedLine
                    break
                }
            }
        }
        
        # Remove duplicates while preserving order
        $errorLines = $errorLines | Select-Object -Unique
        
        # Save errors to file if any found
        $errorFilePath = $null
        if ($errorLines.Count -gt 0) {
            try {
                # Create Logs directory if it doesn't exist
                $logsDir = Join-Path $PSScriptRoot "Logs"
                if (-not (Test-Path $logsDir)) {
                    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
                }
                
                # Create error log file with timestamp
                $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
                $errorFileName = "BootDiagnosis_Errors_$timestamp.txt"
                $errorFilePath = Join-Path $logsDir $errorFileName
                
                # Create error report
                $errorReport = "BOOT DIAGNOSIS ERROR REPORT`n"
                $errorReport += "===============================================================`n"
                $errorReport += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
                $errorReport += "Target Drive: $drive`:`n"
                $errorReport += "Total Errors Found: $($errorLines.Count)`n"
                $errorReport += "===============================================================`n`n"
                $errorReport += "ERRORS DETECTED:`n"
                $errorReport += "===============================================================`n`n"
                
                $errorNumber = 1
                foreach ($errorLine in $errorLines) {
                    $errorReport += "$errorNumber. $errorLine`n`n"
                    $errorNumber++
                }
                
                $errorReport += "`n`n===============================================================`n"
                $errorReport += "FULL DIAGNOSIS OUTPUT:`n"
                $errorReport += "===============================================================`n`n"
                $errorReport += $output
                
                # Save to file
                Set-Content -Path $errorFilePath -Value $errorReport -Encoding UTF8
                
                # Add message to output showing where errors were saved
                $output += "`n`n"
                $output += "═══════════════════════════════════════════════════════════`n"
                $output += "                    ERROR LOG SAVED`n"
                $output += "═══════════════════════════════════════════════════════════`n"
                $output += "`n$($errorLines.Count) error(s) detected and saved to:`n`n"
                $output += "File: $errorFilePath`n`n"
                $output += "The error log contains:`n"
                $output += "  • All detected errors and warnings`n"
                $output += "  • Full diagnosis output for reference`n"
                $output += "  • Timestamp and target drive information`n`n"
                $output += "You will be prompted to open this file after this message.`n"
                
            } catch {
                $output += "`n`n[WARNING] Could not save error log: $_`n"
            }
        }
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $output
            $logAnalysisBox.ScrollToEnd()
        }
        
        # Show message box with error count and file path
        if ($errorLines.Count -gt 0 -and $errorFilePath) {
            $message = "$($errorLines.Count) ERROR(S) DETECTED`n`n"
            $message += "Error log has been saved to:`n`n"
            $message += "File: $errorFilePath`n`n"
            $message += "The error log file contains:`n"
            $message += "  • All detected errors and warnings`n"
            $message += "  • Full diagnosis output`n"
            $message += "  • Timestamp and drive information`n`n"
            $message += "Would you like to open the error log file now?"
            
            $result = [System.Windows.MessageBox]::Show(
                $message,
                "Errors Detected - Log File Saved",
                "YesNo",
                "Question"
            )
            
            if ($result -eq "Yes") {
                try {
                    Start-Process notepad.exe -ArgumentList "`"$errorFilePath`""
                } catch {
                    try {
                        Start-Process $errorFilePath
                    } catch {
                        [System.Windows.MessageBox]::Show(
                            "Could not open error log file. Please open it manually:`n$errorFilePath",
                            "Error",
                            "OK",
                            "Error"
                        )
                    }
                }
            }
        }
    })
}

$btnHardwareSupport = Get-Control -Name "BtnHardwareSupport"
if ($btnHardwareSupport) {
    $btnHardwareSupport.Add_Click({
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "Gathering hardware information and support links...`n`n"
        }
    
    $hwInfo = Get-HardwareSupportInfo
    
    $output = "HARDWARE SUPPORT INFORMATION`n"
    $output += "===============================================================`n`n"
    
    if ($hwInfo.Error) {
        $output += "[ERROR] $($hwInfo.Error)`n"
    } else {
        $output += "MOTHERBOARD:`n"
        $output += "---------------------------------------------------------------`n"
        if ($hwInfo.Motherboard) {
            $output += "$($hwInfo.Motherboard)`n`n"
        } else {
            $output += "Information not available`n`n"
        }
        
        $output += "GRAPHICS CARDS:`n"
        $output += "---------------------------------------------------------------`n"
        if ($hwInfo.GPUs.Count -gt 0) {
            foreach ($gpu in $hwInfo.GPUs) {
                $output += "$($gpu.Name)`n"
                $output += "  Driver Version: $($gpu.DriverVersion)`n"
                if ($gpu.DriverDate) {
                    $output += "  Driver Date: $($gpu.DriverDate)`n"
                }
                if ($gpu.SupportLink) {
                    $output += "  Support: $($gpu.SupportLink)`n"
                }
                $output += "`n"
            }
        } else {
            $output += "No dedicated graphics cards detected`n`n"
        }
        
        $output += "SUPPORT LINKS:`n"
        $output += "---------------------------------------------------------------`n"
        if ($hwInfo.SupportLinks.Count -gt 0) {
            foreach ($link in $hwInfo.SupportLinks) {
                $output += "$($link.Name) ($($link.Type)):`n"
                $output += "  $($link.URL)`n`n"
            }
        } else {
            $output += "No manufacturer support links available`n`n"
        }
        
        if ($hwInfo.DriverAlerts.Count -gt 0) {
            $output += "DRIVER UPDATE ALERTS:`n"
            $output += "---------------------------------------------------------------`n"
            foreach ($alert in $hwInfo.DriverAlerts) {
                $output += "[!] $alert`n"
            }
            $output += "`n"
        }
        
        $output += "NOTE: Click the links above to download the latest drivers from manufacturer websites.`n"
        $output += "For storage drivers (VMD/RAID), use the 'Driver Forensics' button to identify required INF files.`n"
    }
    
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $output
        }
    })
}

$btnRepairTips = Get-Control -Name "BtnRepairTips"
if ($btnRepairTips) {
    $btnRepairTips.Add_Click({
        $tips = Get-UnofficialRepairTips
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $tips
        }
    })
}

$btnGenRegScript = Get-Control -Name "BtnGenRegScript"
if ($btnGenRegScript) {
    $btnGenRegScript.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $script = Get-RegistryEditionOverride -TargetDrive $drive
    
    # Save script to file
    $scriptPath = "$env:TEMP\RegistryEditionOverride_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    $script | Out-File -FilePath $scriptPath -Encoding UTF8
    
    $output = "REGISTRY EDITIONID OVERRIDE SCRIPT GENERATED`n"
    $output += "===============================================================`n`n"
    $output += "Script saved to: $scriptPath`n`n"
    $output += "===============================================================`n"
    $output += "INSTRUCTIONS:`n"
    $output += "===============================================================`n"
    $output += "1. Run this script as Administrator BEFORE launching setup.exe`n"
    $output += "2. The script will backup your registry first`n"
    $output += "3. It will modify EditionID to 'Professional' for compatibility`n"
    $output += "4. IMMEDIATELY run setup.exe from your Windows ISO (do NOT reboot)`n"
    $output += "5. To restore original values later, use the backup file`n`n"
    $output += "[WARN] WARNING: This modifies system registry. Use at your own risk.`n`n"
    $output += "===============================================================`n"
    $output += "SCRIPT PREVIEW:`n"
    $output += "===============================================================`n`n"
    $output += $script
    
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $output
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Script generated successfully!`n`nLocation: $scriptPath`n`nWould you like to open the script file location?",
            "Script Generated",
            "YesNo",
            "Information"
        )
        
        if ($result -eq "Yes") {
            try {
                Start-Process explorer.exe -ArgumentList "/select,`"$scriptPath`""
            } catch {
                [System.Windows.MessageBox]::Show("Could not open file location.", "Error", "OK", "Error")
            }
        }
    })
}

$btnOneClickFix = Get-Control -Name "BtnOneClickFix"
if ($btnOneClickFix) {
    $btnOneClickFix.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "This will apply ALL registry overrides to enable In-Place Upgrade compatibility:`n`n" +
            "- EditionID → Professional`n" +
            "- InstallLanguage → 0409 (US English)`n" +
            "- ProgramFilesDir → Reset to $drive`:\Program Files`n`n" +
            "A full registry backup will be created first.`n`n" +
            "Continue?",
            "One-Click Registry Fixes",
            "YesNo",
            "Question"
        )
        
        if ($result -eq "Yes") {
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = "Applying one-click registry fixes...`n`nPlease wait...`n"
            }
        
        $fixResults = Apply-OneClickRegistryFixes -TargetDrive $drive
        
        $output = "ONE-CLICK REGISTRY FIXES RESULTS`n"
        $output += "===============================================================`n`n"
        
        if ($fixResults.Success) {
            $output += "[SUCCESS] Registry fixes applied successfully!`n`n"
        } else {
            $output += "[PARTIAL] Some fixes applied, but some failed.`n`n"
        }
        
        $output += "APPLIED FIXES:`n"
        $output += "---------------------------------------------------------------`n"
        if ($fixResults.Applied.Count -gt 0) {
            foreach ($fix in $fixResults.Applied) {
                $output += "[OK] $fix`n"
            }
        } else {
            $output += "No changes were needed (values already correct).`n"
        }
        
        if ($fixResults.Failed.Count -gt 0) {
            $output += "`nFAILED FIXES:`n"
            $output += "---------------------------------------------------------------`n"
            foreach ($fail in $fixResults.Failed) {
                $output += "[FAIL] $fail`n"
            }
        }
        
        if ($fixResults.Warnings.Count -gt 0) {
            $output += "`nWARNINGS:`n"
            $output += "---------------------------------------------------------------`n"
            foreach ($warn in $fixResults.Warnings) {
                $output += "[WARN] $warn`n"
            }
        }
        
        $output += "`n`nNEXT STEPS:`n"
        $output += "---------------------------------------------------------------`n"
        $output += "1. IMMEDIATELY run setup.exe from your Windows ISO`n"
        $output += "2. Do NOT reboot before running setup.exe`n"
        $output += "3. The 'Keep personal files and apps' option should now be available`n"
            $output += "`nBackup location: $($fixResults.BackupPath)`n"
            
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = $output
            }
            
            if ($fixResults.Success) {
                [System.Windows.MessageBox]::Show(
                    "Registry fixes applied successfully!`n`nNow run setup.exe from your Windows ISO IMMEDIATELY (do not reboot).",
                    "Success",
                    "OK",
                    "Information"
                )
            } else {
                [System.Windows.MessageBox]::Show(
                    "Some fixes failed. See the output for details.",
                    "Partial Success",
                    "OK",
                    "Warning"
                )
            }
        }
    })
}

$btnFilterForensics = Get-Control -Name "BtnFilterForensics"
if ($btnFilterForensics) {
    $btnFilterForensics.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "Analyzing filter drivers in SYSTEM registry hive...`n`nThis may take a moment...`n"
        }
        
        $forensics = Get-FilterDriverForensics -TargetDrive $drive
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $forensics.Summary
        }
    })
}

$btnRecommendedTools = Get-Control -Name "BtnRecommendedTools"
if ($btnRecommendedTools) {
    $btnRecommendedTools.Add_Click({
        $tools = Get-RecommendedTools
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $tools
        }
    })
}

$btnExportDrivers = Get-Control -Name "BtnExportDrivers"
if ($btnExportDrivers) {
    $btnExportDrivers.Add_Click({
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "Exporting in-use drivers list...`n`nThis may take a moment...`n"
        }
        
        # Let user choose save location
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
        $saveDialog.FileName = "In-Use_Drivers_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $saveDialog.InitialDirectory = $env:USERPROFILE + "\Desktop"
        $saveDialog.Title = "Save In-Use Drivers Export"
        
        $result = $saveDialog.ShowDialog()
        
        if ($result -eq "OK") {
            $exportResult = Export-InUseDrivers -OutputPath $saveDialog.FileName
            
            if ($exportResult.Success) {
                $output = "IN-USE DRIVERS EXPORT COMPLETE`n"
                $output += "===============================================================`n`n"
                $output += "[SUCCESS] Driver list exported successfully!`n`n"
                $output += "File Location: $($exportResult.Path)`n`n"
                $output += "Export Statistics:`n"
                $output += "  Total Devices: $($exportResult.DeviceCount)`n"
                $output += "  Device Classes: $($exportResult.ClassCount)`n`n"
                $output += "===============================================================`n"
                $output += "WHAT'S IN THE FILE:`n"
                $output += "===============================================================`n"
                $output += "The exported file contains:`n`n"
                $output += "1. All currently working (in-use) drivers from your PC`n"
                $output += "2. Device names and hardware IDs`n"
                $output += "3. Driver INF file paths and locations`n"
                $output += "4. Driver versions and providers`n"
                $output += "5. Organized by device class (Storage, Display, Network, etc.)`n`n"
                $output += "===============================================================`n"
                $output += "HOW TO USE:`n"
                $output += "===============================================================`n"
                $output += "1. Take this file to your installer/recovery environment`n"
                $output += "2. Use the INF file paths to locate drivers in DriverStore`n"
                $output += "3. Copy the driver folders to your recovery USB/ISO`n"
                $output += "4. Use Hardware IDs to match drivers to devices`n`n"
                $output += "TIP: Focus on critical drivers (Storage, Network, Display)`n"
                $output += "     These are most likely needed for recovery operations.`n"
                
                if ($logAnalysisBox) {
                    $logAnalysisBox.Text = $output
                }
                
                $msgResult = [System.Windows.MessageBox]::Show(
                    "Driver export complete!`n`nFile saved to:`n$($exportResult.Path)`n`nWould you like to open the file location?",
                    "Export Complete",
                    "YesNo",
                    "Information"
                )
                
                if ($msgResult -eq "Yes") {
                    try {
                        Start-Process explorer.exe -ArgumentList "/select,`"$($exportResult.Path)`""
                    } catch {
                        [System.Windows.MessageBox]::Show("Could not open file location.", "Error", "OK", "Error")
                    }
                }
            } else {
                $output = "EXPORT FAILED`n"
                $output += "===============================================================`n`n"
                $output += "[ERROR] Failed to export drivers: $($exportResult.Error)`n`n"
                $output += "Please ensure you have write permissions to the selected location.`n"
                
                if ($logAnalysisBox) {
                    $logAnalysisBox.Text = $output
                }
                [System.Windows.MessageBox]::Show(
                    "Failed to export drivers.`n`nError: $($exportResult.Error)",
                    "Export Failed",
                    "OK",
                    "Error"
                )
            }
        } else {
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = "Export cancelled by user."
            }
        }
    })
}

$btnGenCleanupScript = Get-Control -Name "BtnGenCleanupScript"
if ($btnGenCleanupScript) {
    $btnGenCleanupScript.Add_Click({

    $logDriveCombo = Get-Control -Name "LogDriveCombo"
    $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $script = Get-CleanupScript -TargetDrive $drive
    
    # Save script to file
    $scriptPath = "$env:TEMP\WindowsOldCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    $script | Out-File -FilePath $scriptPath -Encoding UTF8
    
    $output = "WINDOWS.OLD CLEANUP SCRIPT GENERATED`n"
    $output += "===============================================================`n`n"
    $output += "Script saved to: $scriptPath`n`n"
    $output += "===============================================================`n"
    $output += "INSTRUCTIONS:`n"
    $output += "===============================================================`n"
    $output += "1. Run this script AFTER a successful In-Place Upgrade`n"
    $output += "2. It will remove the Windows.old folder to reclaim disk space`n"
    $output += "3. The script will show the size before deletion`n"
    $output += "4. You will be prompted to confirm before deletion`n`n"
    $output += "[WARNING] This permanently deletes Windows.old. Only run this`n"
    $output += "   after you're certain the repair was successful!`n`n"
    $output += "===============================================================`n"
    $output += "SCRIPT PREVIEW:`n"
    $output += "===============================================================`n`n"
    $output += $script
    
    if ($logAnalysisBox) {
        $logAnalysisBox.Text = $output
    }
    
    $result = [System.Windows.MessageBox]::Show(
        "Cleanup script generated successfully!`n`nLocation: $scriptPath`n`nWould you like to open the script file location?",
        "Script Generated",
        "YesNo",
        "Information"
    )
    
    if ($result -eq "Yes") {
        try {
            Start-Process explorer.exe -ArgumentList "/select,`"$scriptPath`""
        } catch {
            [System.Windows.MessageBox]::Show("Could not open file location.", "Error", "OK", "Error")
        }
    }
    })
}

$btnInPlaceReadiness = Get-Control -Name "BtnInPlaceReadiness"
if ($btnInPlaceReadiness) {
    $btnInPlaceReadiness.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        Update-StatusBar -Message "Running in-place upgrade readiness check..." -ShowProgress
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "Running comprehensive in-place upgrade readiness check...`n`n"
            $logAnalysisBox.Text += "Analyzing:`n"
            $logAnalysisBox.Text += "  - Boot log (nbtlog.txt)`n"
            $logAnalysisBox.Text += "  - Windows installation files (`$WINDOWS.~BT, `$Windows.~WS)`n"
            $logAnalysisBox.Text += "  - CBS logs and component store`n"
            $logAnalysisBox.Text += "  - Registry health`n"
            $logAnalysisBox.Text += "  - Setup logs`n"
            $logAnalysisBox.Text += "  - System file health`n`n"
            $logAnalysisBox.Text += "This may take a few minutes...`n`n"
        }
    
    try {
        $readiness = Get-InPlaceUpgradeReadiness -TargetDrive $drive
        
        $output = $readiness.Report
        
        # Add visual status indicator
        $output += "`n`n"
        $output += "=" * 80 + "`n"
        if ($readiness.ReadyForInPlaceUpgrade) {
            $output += "STATUS: [OK] READY FOR IN-PLACE UPGRADE`n"
        } else {
            $output += "STATUS: [BLOCKED] NOT READY FOR IN-PLACE UPGRADE`n"
            $output += "BLOCKERS FOUND: $($readiness.Blockers.Count)`n"
        }
        $output += "=" * 80 + "`n"
        
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = $output
        }
        
        if ($readiness.ReadyForInPlaceUpgrade) {
            Update-StatusBar -Message "System is ready for in-place upgrade" -HideProgress
            [System.Windows.MessageBox]::Show(
                "System appears ready for in-place upgrade!`n`nNo critical blockers detected.`n`nReview the detailed report for any warnings.",
                "Ready for In-Place Upgrade",
                "OK",
                "Information"
            )
        } else {
            Update-StatusBar -Message "System is NOT ready - $($readiness.Blockers.Count) blocker(s) found" -HideProgress
            $blockerList = $readiness.Blockers -join "`n  - "
            [System.Windows.MessageBox]::Show(
                "System is NOT ready for in-place upgrade.`n`nBLOCKERS:`n  - $blockerList`n`nReview the detailed report for recommendations.",
                "Blockers Detected",
                "OK",
                "Warning"
            )
        }
    } catch {
        Update-StatusBar -Message "Error during readiness check: $_" -HideProgress
        if ($logAnalysisBox) {
            $logAnalysisBox.Text = "ERROR: Failed to run in-place upgrade readiness check:`n`n$_"
        }
        [System.Windows.MessageBox]::Show(
            "Error running readiness check: $_",
            "Error",
            "OK",
            "Error"
        )
    }
    })
}

$btnRepairInstallReady = Get-Control -Name "BtnRepairInstallReady"
if ($btnRepairInstallReady) {
    $btnRepairInstallReady.Add_Click({
        $logDriveCombo = Get-Control -Name "LogDriveCombo"
        $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
        
        $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
        $drive = "C"
        
        if ($selectedDrive) {
            if ($selectedDrive -match '^([A-Z]):') {
                $drive = $matches[1]
            }
        }
        
        # Confirm action
        $confirmMsg = "REPAIR-INSTALL READINESS ENGINE`n`n"
        $confirmMsg += "This will:`n"
        $confirmMsg += "  - Test eligibility for in-place upgrade (Keep apps + files)`n"
        $confirmMsg += "  - Clear CBS blockers (pending reboots, component store issues)`n"
        $confirmMsg += "  - Normalize setup state (registry keys, edition compatibility)`n"
        $confirmMsg += "  - Repair WinRE registration`n`n"
        $confirmMsg += "Target Drive: $drive`:`n`n"
        $confirmMsg += "Continue?"
        
        $result = [System.Windows.MessageBox]::Show(
            $confirmMsg,
            "Repair-Install Readiness",
            "YesNo",
            "Question"
        )
        
        if ($result -eq "Yes") {
            Update-StatusBar -Message "Running repair-install readiness engine..." -ShowProgress
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = "REPAIR-INSTALL READINESS ENGINE`n"
                $logAnalysisBox.Text += "=" * 80 + "`n`n"
                $logAnalysisBox.Text += "Target Drive: $drive`:`n"
                $logAnalysisBox.Text += "Mode: $(if ((Get-EnvironmentType) -eq 'FullOS') { 'Online' } else { 'Offline' })`n`n"
                $logAnalysisBox.Text += "Running comprehensive checks and fixes...`n`n"
                $logAnalysisBox.Text += "This may take several minutes...`n`n"
            }
        
        try {
            # Progress callback for status updates
            $progressCallback = {
                param($message)
                $W.Dispatcher.Invoke([action]{
                    $logBox = Get-Control -Name "LogAnalysisBox"
                    if ($logBox) {
                        $logBox.Text += "$message`n"
                        $logBox.ScrollToEnd()
                    }
                    Update-StatusBar -Message $message -ShowProgress
                }, [System.Windows.Threading.DispatcherPriority]::Input)
            }
            
            $readinessResult = Start-RepairInstallReadiness -TargetDrive $drive -FixBlockers -ProgressCallback $progressCallback
            
            $output = $readinessResult.Report
            
            # Add visual summary
            $output += "`n`n"
            $output += "=" * 80 + "`n"
            $output += "SUMMARY`n"
            $output += "=" * 80 + "`n"
            $output += "Readiness Score: $($readinessResult.ReadinessScore)/100`n"
            $output += "Eligible: $(if ($readinessResult.Eligible) { 'YES [OK]' } else { 'NO [X]' })`n"
            $output += "Actions Taken: $($readinessResult.ActionsTaken.Count)`n"
            $output += "Blockers Remaining: $($readinessResult.Blockers.Count)`n"
            $output += "Warnings: $($readinessResult.Warnings.Count)`n`n"
            
            if ($readinessResult.Eligible) {
                $output += "[OK] SYSTEM IS READY FOR REPAIR INSTALL`n`n"
                $output += "You can now run:`n"
                $output += "  setup.exe /auto upgrade /quiet`n`n"
                $output += "Or use Windows Setup GUI and select 'Keep apps + files'`n"
            } else {
                $output += "[X] SYSTEM IS NOT FULLY READY`n`n"
                if ($readinessResult.Blockers.Count -gt 0) {
                    $output += "Blockers must be resolved:`n"
                    foreach ($blocker in $readinessResult.Blockers) {
                        $output += "  - $blocker`n"
                    }
                }
            }
            
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = $output
                $logAnalysisBox.ScrollToEnd()
            }
            
            # Show result dialog
            if ($readinessResult.Eligible) {
                [System.Windows.MessageBox]::Show(
                    "System is ready for repair install!`n`n" +
                    "Readiness Score: $($readinessResult.ReadinessScore)/100`n`n" +
                    "You can now run setup.exe with 'Keep apps + files' option.",
                    "Ready for Repair Install",
                    "OK",
                    "Information"
                )
            } else {
                [System.Windows.MessageBox]::Show(
                    "System may not be fully ready.`n`n" +
                    "Readiness Score: $($readinessResult.ReadinessScore)/100`n`n" +
                    "Review the report for blockers and warnings.",
                    "Repair-Install Readiness",
                    "OK",
                    "Warning"
                )
            }
            
            Update-StatusBar -Message "Repair-install readiness check complete" -HideProgress
        } catch {
            if ($logAnalysisBox) {
                $logAnalysisBox.Text += "`n`n[ERROR] Failed: $_`n"
            }
            Update-StatusBar -Message "Repair-install readiness check failed" -HideProgress
            [System.Windows.MessageBox]::Show(
                "Error running repair-install readiness check:`n`n$_",
                "Error",
                "OK",
                "Error"
            )
        }
        } else {
            Update-StatusBar -Message "Repair-install readiness check cancelled" -HideProgress
        }
    })
}

$btnRepairTemplates = Get-Control -Name "BtnRepairTemplates"
if ($btnRepairTemplates) {
    $btnRepairTemplates.Add_Click({
    if (-not (Get-Command Get-RepairTemplates -ErrorAction SilentlyContinue)) {
        [System.Windows.MessageBox]::Show(
            "Repair Templates feature not available.`n`nThis feature requires WinRepairCore.ps1 to be loaded.",
            "Feature Not Available",
            "OK",
            "Warning"
        )
        return
    }
    
    $templates = Get-RepairTemplates
    
    # Create template selection window
    $templateWindow = New-Object System.Windows.Window
    $templateWindow.Title = "Repair Templates - One-Click Fixes"
    $templateWindow.Width = 700
    $templateWindow.Height = 500
    $templateWindow.WindowStartupLocation = "CenterScreen"
    
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = "10"
    
    # ListBox for templates
    $listBox = New-Object System.Windows.Controls.ListBox
    $listBox.Margin = "0,0,0,10"
    
    foreach ($template in $templates) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $stackPanel = New-Object System.Windows.Controls.StackPanel
        $stackPanel.Margin = "5"
        
        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $template.Name
        $nameBlock.FontWeight = "Bold"
        $nameBlock.FontSize = "14"
        $stackPanel.Children.Add($nameBlock) | Out-Null
        
        $descBlock = New-Object System.Windows.Controls.TextBlock
        $descBlock.Text = $template.Description
        $descBlock.Foreground = "Gray"
        $descBlock.Margin = "0,5,0,0"
        $descBlock.TextWrapping = "Wrap"
        $stackPanel.Children.Add($descBlock) | Out-Null
        
        $infoBlock = New-Object System.Windows.Controls.TextBlock
        $infoBlock.Text = "Time: $($template.EstimatedTime) | Risk: $($template.RiskLevel)"
        $infoBlock.Foreground = "DarkOrange"
        $infoBlock.Margin = "0,5,0,0"
        $stackPanel.Children.Add($infoBlock) | Out-Null
        
        $item.Content = $stackPanel
        $item.Tag = $template.Id
        $listBox.Items.Add($item) | Out-Null
    }
    
    # Buttons
    $buttonPanel = New-Object System.Windows.Controls.StackPanel
    $buttonPanel.Orientation = "Horizontal"
    $buttonPanel.HorizontalAlignment = "Right"
    
    $executeBtn = New-Object System.Windows.Controls.Button
    $executeBtn.Content = "Execute Template"
    $executeBtn.Width = "150"
    $executeBtn.Height = "30"
    $executeBtn.Margin = "0,0,10,0"
    $executeBtn.IsEnabled = $false
    
    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Width = "100"
    $cancelBtn.Height = "30"
    
    $buttonPanel.Children.Add($executeBtn) | Out-Null
    $buttonPanel.Children.Add($cancelBtn) | Out-Null
    
    # Enable execute button when template is selected
    $listBox.Add_SelectionChanged({
        $executeBtn.IsEnabled = ($null -ne $listBox.SelectedItem)
    })
    
    # Execute button handler
    $executeBtn.Add_Click({
        if ($listBox.SelectedItem) {
            $templateId = $listBox.SelectedItem.Tag
            $templateWindow.DialogResult = $true
            $templateWindow.Close()
            
            # Get drive
            $logDriveCombo = Get-Control -Name "LogDriveCombo"
    $selectedDrive = if ($logDriveCombo) { $logDriveCombo.SelectedItem } else { $null }
            $drive = "C"
            if ($selectedDrive) {
                if ($selectedDrive -match '^([A-Z]):') {
                    $drive = $matches[1]
                }
            }
            
            # Execute template
            Update-StatusBar -Message "Executing repair template..." -ShowProgress
            $logAnalysisBox = Get-Control -Name "LogAnalysisBox"
            if ($logAnalysisBox) {
                $logAnalysisBox.Text = "Executing repair template...`n`n"
            }
            
            $progressCallback = {
                param($message)
                $W.Dispatcher.Invoke([action]{
                    $logBox = Get-Control -Name "LogAnalysisBox"
                    if ($logBox) {
                        $logBox.Text += "$message`n"
                        $logBox.ScrollToEnd()
                    }
                    Update-StatusBar -Message $message -ShowProgress
                }, [System.Windows.Threading.DispatcherPriority]::Input)
            }
            
            try {
                $result = Start-RepairTemplate -TemplateId $templateId -TargetDrive $drive -SkipConfirmation -ProgressCallback $progressCallback
                
                if ($logAnalysisBox) {
                    $logAnalysisBox.Text = $result.Report
                    $logAnalysisBox.ScrollToEnd()
                }
                
                if ($result.Success) {
                    [System.Windows.MessageBox]::Show(
                        "Template execution completed successfully!`n`n" +
                        "Steps completed: $($result.StepsCompleted.Count)",
                        "Template Complete",
                        "OK",
                        "Information"
                    )
                } else {
                    [System.Windows.MessageBox]::Show(
                        "Template execution completed with warnings.`n`n" +
                        "Steps completed: $($result.StepsCompleted.Count)`n" +
                        "Steps failed: $($result.StepsFailed.Count)",
                        "Template Complete",
                        "OK",
                        "Warning"
                    )
                }
                
                Update-StatusBar -Message "Template execution complete" -HideProgress
            } catch {
                $W.FindName("LogAnalysisBox").Text += "`n`n[ERROR] Failed: $_`n"
                Update-StatusBar -Message "Template execution failed" -HideProgress
                [System.Windows.MessageBox]::Show(
                    "Error executing template:`n`n$_",
                    "Error",
                    "OK",
                    "Error"
                )
            }
        }
    })
    
    $cancelBtn.Add_Click({
        $templateWindow.DialogResult = $false
        $templateWindow.Close()
    })
    
    $grid.Children.Add($listBox) | Out-Null
    $grid.Children.Add($buttonPanel) | Out-Null
    
    $templateWindow.Content = $grid
    $templateWindow.ShowDialog() | Out-Null
    })
}

# Repair Install Forcer Handlers
# Information button handler
$btnRepairInstallInfo = Get-Control -Name "BtnRepairInstallInfo"
if ($btnRepairInstallInfo) {
    $btnRepairInstallInfo.Add_Click({
        try {
            # Get current mode
            $isOfflineMode = $W.FindName("RbOfflineMode").IsChecked
            
            # Get appropriate instructions
            if ($isOfflineMode) {
                $instructions = Get-OfflineRepairInstallInstructions
                $title = "Offline Repair Install Forcer - Detailed Information"
            } else {
                $instructions = Get-RepairInstallInstructions
                $title = "Repair Install Forcer - Detailed Information"
            }
            
            # Create information window
            $infoWindow = New-Object System.Windows.Window
            $infoWindow.Title = $title
            $infoWindow.Width = 900
            $infoWindow.Height = 700
            $infoWindow.WindowStartupLocation = "CenterOwner"
            $infoWindow.Owner = $W
            $infoWindow.ResizeMode = "CanResize"
            
            # Create content
            $grid = New-Object System.Windows.Controls.Grid
            $grid.Margin = New-Object System.Windows.Thickness(10)
            
            $rowDef1 = New-Object System.Windows.Controls.RowDefinition
            $rowDef1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $rowDef2 = New-Object System.Windows.Controls.RowDefinition
            $rowDef2.Height = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Auto)
            
            $grid.RowDefinitions.Add($rowDef1)
            $grid.RowDefinitions.Add($rowDef2)
            
            # Text box for instructions
            $textBox = New-Object System.Windows.Controls.TextBox
            $textBox.Text = $instructions
            $textBox.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
            $textBox.FontSize = 11
            $textBox.IsReadOnly = $true
            $textBox.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $textBox.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
            $textBox.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
            $textBox.Background = [System.Windows.Media.Brushes]::White
            $textBox.Foreground = [System.Windows.Media.Brushes]::Black
            $textBox.Padding = New-Object System.Windows.Thickness(10)
            $textBox.Margin = New-Object System.Windows.Thickness(0,0,0,10)
            [System.Windows.Controls.Grid]::SetRow($textBox, 0)
            $grid.Children.Add($textBox)
            
            # Close button
            $closeBtn = New-Object System.Windows.Controls.Button
            $closeBtn.Content = "Close"
            $closeBtn.Width = 100
            $closeBtn.Height = 30
            $closeBtn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
            $closeBtn.Margin = New-Object System.Windows.Thickness(0,0,0,0)
            [System.Windows.Controls.Grid]::SetRow($closeBtn, 1)
            $closeBtn.Add_Click({
                $infoWindow.Close()
            })
            $grid.Children.Add($closeBtn)
            
            $infoWindow.Content = $grid
            $infoWindow.ShowDialog() | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show(
                "Error displaying information: $_",
                "Error",
                "OK",
                "Error"
            )
        }
    })
}

# Update mode description when radio buttons change
$W.FindName("RbOnlineMode").Add_Checked({
    if ($W.FindName("RbOnlineMode").IsChecked) {
        $W.FindName("RepairModeDescription").Text = "This forces Setup to reinstall system files while keeping apps and data. Requires same edition, architecture, and build family. Must run from inside Windows."
        $W.FindName("OfflineDrivePanel").Visibility = "Collapsed"
    }
})

$W.FindName("RbOfflineMode").Add_Checked({
    if ($W.FindName("RbOfflineMode").IsChecked) {
        $W.FindName("RepairModeDescription").Text = "[WARNING] ADVANCED/HACKY METHOD: Forces Setup on non-booting PC by manipulating offline registry hives. Requires WinPE/WinRE environment. This tricks Setup into thinking it's upgrading a running OS. Use with caution."
        $W.FindName("OfflineDrivePanel").Visibility = "Visible"
        
        # Populate offline drive combo
        $W.FindName("RepairOfflineDrive").Items.Clear()
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemLabel } | Sort-Object DriveLetter
        foreach ($vol in $volumes) {
            if ($vol.DriveLetter -ne "X") {
                $testPath = "$($vol.DriveLetter):\Windows"
                if (Test-Path $testPath) {
                    $W.FindName("RepairOfflineDrive").Items.Add("$($vol.DriveLetter):")
                }
            }
        }
        if ($W.FindName("RepairOfflineDrive").Items.Count -gt 0) {
            $W.FindName("RepairOfflineDrive").SelectedIndex = 0
        }
    }
})

$btnBrowseISO = Get-Control -Name "BtnBrowseISO"
if ($btnBrowseISO) {
    $btnBrowseISO.Add_Click({

    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select mounted ISO drive or extracted ISO folder"
    $folderDialog.RootFolder = "MyComputer"
    
    $result = $folderDialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $W.FindName("RepairISOPath").Text = $folderDialog.SelectedPath
    }
    })
}

$btnShowInstructions = Get-Control -Name "BtnShowInstructions"
if ($btnShowInstructions) {
    $btnShowInstructions.Add_Click({
        $repairInstallOutput = Get-Control -Name "RepairInstallOutput"
        $instructions = Get-RepairInstallInstructions
        if ($repairInstallOutput) {
            $repairInstallOutput.Text = $instructions
            $repairInstallOutput.ScrollToEnd()
        }
    })
}

$btnCheckPrereq = Get-Control -Name "BtnCheckPrereq"
if ($btnCheckPrereq) {
    $btnCheckPrereq.Add_Click({
        $repairISOPath = Get-Control -Name "RepairISOPath"
        $rbOfflineMode = Get-Control -Name "RbOfflineMode"
        $repairOfflineDrive = Get-Control -Name "RepairOfflineDrive"
        $repairInstallOutput = Get-Control -Name "RepairInstallOutput"
        
        Update-StatusBar -Message "Checking prerequisites..." -ShowProgress
        $isoPath = if ($repairISOPath) { $repairISOPath.Text } else { "" }
        $isOffline = if ($rbOfflineMode) { $rbOfflineMode.IsChecked } else { $false }
        
        if ([string]::IsNullOrWhiteSpace($isoPath)) {
            if ($repairInstallOutput) {
                $repairInstallOutput.Text = "[ERROR] Please specify ISO path first.`n`nClick 'Browse...' to select mounted ISO drive or folder."
            }
            Update-StatusBar -Message "ISO path required" -HideProgress
            return
        }
        
        if ($isOffline) {
            $offlineDrive = if ($repairOfflineDrive) { $repairOfflineDrive.SelectedItem } else { $null }
            if (-not $offlineDrive) {
                if ($repairInstallOutput) {
                    $repairInstallOutput.Text = "[ERROR] Please select offline Windows drive first."
                }
                Update-StatusBar -Message "Offline drive required" -HideProgress
                return
            }
            if ($offlineDrive -match '^([A-Z]):') {
                $offlineDrive = $matches[1]
            }
            $prereq = Test-OfflineRepairInstallPrerequisites -ISOPath $isoPath -OfflineWindowsDrive $offlineDrive
        } else {
            $prereq = Test-RepairInstallPrerequisites -ISOPath $isoPath
        }
        
        $output = "PREREQUISITE CHECK RESULTS`n"
        $output += "===============================================================`n`n"
        $output += "ISO Path: $isoPath`n`n"
        
        if ($isOffline) {
            $output += "OFFLINE OS INFORMATION:`n"
            $output += "---------------------------------------------------------------`n"
            $offlineDriveItem = if ($repairOfflineDrive) { $repairOfflineDrive.SelectedItem } else { "N/A" }
            $output += "Offline Drive: $offlineDriveItem`n"
            $output += "Edition: $($prereq.OfflineOS.EditionID)`n"
            $output += "Architecture: $($prereq.OfflineOS.Architecture)`n"
            $output += "Build Number: $($prereq.OfflineOS.BuildNumber)`n"
            $output += "Version: $($prereq.OfflineOS.Version)`n"
            $output += "Language: $($prereq.OfflineOS.Language)`n`n"
        } else {
            $output += "CURRENT OS INFORMATION:`n"
            $output += "---------------------------------------------------------------`n"
            $output += "Edition: $($prereq.CurrentOS.EditionID)`n"
            $output += "Architecture: $($prereq.CurrentOS.Architecture)`n"
            $output += "Build Number: $($prereq.CurrentOS.BuildNumber)`n"
            $output += "Version: $($prereq.CurrentOS.Version)`n"
            $output += "Language: $($prereq.CurrentOS.Language)`n`n"
        }
        
        if ($prereq.CanProceed) {
            $output += "[SUCCESS] Prerequisites check PASSED`n"
            $output += "===============================================================`n`n"
            $output += "You can proceed with repair install.`n`n"
        } else {
            $output += "[FAILED] Prerequisites check FAILED`n"
            $output += "===============================================================`n`n"
            $output += "BLOCKING ISSUES:`n"
            foreach ($issue in $prereq.Issues) {
                $output += "  - $issue`n"
            }
            $output += "`n"
        }
        
        if ($prereq.Warnings.Count -gt 0) {
            $output += "WARNINGS:`n"
            foreach ($warn in $prereq.Warnings) {
                $output += "  [WARN] $warn`n"
            }
            $output += "`n"
        }
        
        if ($prereq.Recommendations.Count -gt 0) {
            $output += "RECOMMENDATIONS:`n"
            foreach ($rec in $prereq.Recommendations) {
                $output += "  - $rec`n"
            }
            $output += "`n"
        }
        
        if ($repairInstallOutput) {
            $repairInstallOutput.Text = $output
            $repairInstallOutput.ScrollToEnd()
        }
        Update-StatusBar -Message "Prerequisites check complete" -HideProgress
    })
}

$btnStartRepair = Get-Control -Name "BtnStartRepair"
if ($btnStartRepair) {
    $btnStartRepair.Add_Click({
        $repairISOPath = Get-Control -Name "RepairISOPath"
        $rbOfflineMode = Get-Control -Name "RbOfflineMode"
        $repairOfflineDrive = Get-Control -Name "RepairOfflineDrive"
        $chkSkipCompat = Get-Control -Name "ChkSkipCompat"
        $chkDisableDynamicUpdate = Get-Control -Name "ChkDisableDynamicUpdate"
        $chkForceEdition = Get-Control -Name "ChkForceEdition"
        $repairInstallOutput = Get-Control -Name "RepairInstallOutput"
        
        $isoPath = if ($repairISOPath) { $repairISOPath.Text } else { "" }
        $isOffline = if ($rbOfflineMode) { $rbOfflineMode.IsChecked } else { $false }
        
        if ([string]::IsNullOrWhiteSpace($isoPath)) {
            [System.Windows.MessageBox]::Show(
                "Please specify ISO path first.`n`nClick 'Browse...' to select mounted ISO drive or folder.",
                "ISO Path Required",
                "OK",
                "Warning"
            )
            return
        }
        
        if ($isOffline) {
            $offlineDrive = if ($repairOfflineDrive) { $repairOfflineDrive.SelectedItem } else { $null }
            if (-not $offlineDrive) {
                [System.Windows.MessageBox]::Show(
                    "Please select offline Windows drive first.",
                    "Offline Drive Required",
                    "OK",
                    "Warning"
                )
                return
            }
            if ($offlineDrive -match '^([A-Z]):') {
                $offlineDrive = $matches[1]
            }
        }
        
        # Check prerequisites first
        Update-StatusBar -Message "Checking prerequisites..." -ShowProgress
        if ($isOffline) {
            $prereq = Test-OfflineRepairInstallPrerequisites -ISOPath $isoPath -OfflineWindowsDrive $offlineDrive
        } else {
            $prereq = Test-RepairInstallPrerequisites -ISOPath $isoPath
        }
        
        if (-not $prereq.CanProceed) {
            if ($repairInstallOutput) {
                $repairInstallOutput.Text = "PREREQUISITE CHECK FAILED`n" +
                                          "===============================================================`n`n" +
                                          "Cannot proceed with repair install:`n`n" +
                                          ($prereq.Issues -join "`n") +
                                          "`n`nPlease fix these issues and try again."
            }
            Update-StatusBar -Message "Prerequisites check failed" -HideProgress
            return
        }
        
        # Get options
        $skipCompat = if ($chkSkipCompat) { $chkSkipCompat.IsChecked } else { $false }
        $disableUpdate = if ($chkDisableDynamicUpdate) { $chkDisableDynamicUpdate.IsChecked } else { $false }
        $forceEdition = if ($chkForceEdition) { $chkForceEdition.IsChecked } else { $false }
        
        # Prepare repair install
        Update-StatusBar -Message "Preparing repair install..." -ShowProgress
        if ($isOffline) {
            $repairResult = Start-OfflineRepairInstall -ISOPath $isoPath -OfflineWindowsDrive $offlineDrive -SkipCompatibility:$skipCompat -DisableDynamicUpdate:$disableUpdate
        } else {
            $repairResult = Start-RepairInstall -ISOPath $isoPath -SkipCompatibility:$skipCompat -DisableDynamicUpdate:$disableUpdate -ForceEdition:$forceEdition
        }
        
        if (-not $repairResult.Success) {
            if ($repairInstallOutput) {
                $repairInstallOutput.Text = $repairResult.Output
            }
            Update-StatusBar -Message "Failed to prepare repair install" -HideProgress
            return
        }
        
        # Show confirmation
        $modeText = if ($isOffline) { "OFFLINE" } else { "ONLINE" }
        $confirmMsg = "$modeText REPAIR INSTALL READY`n`n" +
                     "Command: $($repairResult.Command)`n`n"
        
        if ($isOffline) {
        $confirmMsg += "This will:`n" +
                      "  - Manipulate offline registry hives`n" +
                      "  - Launch Windows Setup against offline OS`n" +
                      "  - Restart and begin repair process`n`n" +
                      "Registry backups saved to:`n"
        foreach ($backup in $repairResult.RegistryBackups) {
            $confirmMsg += "  - $backup`n"
        }
        $confirmMsg += "`n"
    } else {
        $confirmMsg += "This will:`n" +
                      "  - Launch Windows Setup`n" +
                      "  - Restart your system`n" +
                      "  - Begin repair process`n`n"
    }
    
    $confirmMsg += "Monitor progress at: $($repairResult.LogPath)`n`n" +
                  "Do you want to proceed?"
    
    $result = [System.Windows.MessageBox]::Show(
        $confirmMsg,
        "Confirm Repair Install",
        "YesNo",
        "Question"
    )
    
    if ($result -eq "Yes") {
        Update-StatusBar -Message "Starting repair install..." -ShowProgress
        
        $output = "STARTING REPAIR INSTALL`n"
        $output += "===============================================================`n`n"
        $output += $repairResult.Output
        $output += "`n`n[INFO] Launching Windows Setup...`n"
        $output += "System will restart shortly.`n"
        $output += "`nMonitor progress at: $($repairResult.LogPath)`n"
        
        if ($repairInstallOutput) {
            $repairInstallOutput.Text = $output
        }
        
        try {
            # Execute the setup command
            $commandParts = $repairResult.Command.Split(' ', 2)
            $exePath = $commandParts[0].Trim('"', '''')
            $arguments = if ($commandParts.Count -gt 1) { $commandParts[1] } else { "" }
            Start-Process -FilePath $exePath -ArgumentList $arguments -NoNewWindow -Wait:$false
            
            Update-StatusBar -Message "Repair install started - system will restart" -HideProgress
            
            [System.Windows.MessageBox]::Show(
                "Repair install has been started.`n`nWindows Setup will launch and your system will restart.`n`nMonitor progress at:`n$($repairResult.LogPath)",
                "Repair Install Started",
                "OK",
                "Information"
            )
        } catch {
            $repairInstallOutput = Get-Control -Name "RepairInstallOutput"
            if ($repairInstallOutput) {
                $repairInstallOutput.Text += "`n`n[ERROR] Failed to start repair install: $_`n"
            }
            Update-StatusBar -Message "Failed to start repair install" -HideProgress
        }
        } else {
            Update-StatusBar -Message "Repair install cancelled" -HideProgress
        }
    })
}

# #region agent log
try {
    $logPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".cursor\debug.log"
    $logEntry = @{
        sessionId = "debug-session"
        runId = "gui-launch-verify"
        hypothesisId = "VERIFY"
        location = "WinRepairGUI.ps1:ShowDialog"
        message = "About to show GUI window"
        data = @{ windowNotNull = ($null -ne $W) }
        timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Compress
    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
} catch {}
# #endregion agent log

# Wrap ShowDialog in comprehensive error handling to catch stack overflow
try {
    Write-Host "Showing GUI window..." -ForegroundColor Gray
    
    # Verify window is valid before showing
    if ($null -eq $W) {
        throw "Window object is null - cannot show dialog"
    }
    
    # Check window type
    if (-not ($W -is [System.Windows.Window])) {
        throw "Window object is not a valid WPF Window type: $($W.GetType().FullName)"
    }
    
    # Show dialog with error handling
    $W.ShowDialog() | Out-Null
    
    # #region agent log
    try {
        $logPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".cursor\debug.log"
        $logEntry = @{
            sessionId = "debug-session"
            runId = "gui-launch-verify"
            hypothesisId = "VERIFY"
            location = "WinRepairGUI.ps1:ShowDialog-complete"
            message = "GUI window closed by user"
            data = @{ success = $true }
            timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    # #endregion agent log
    
    Write-Host "GUI window closed successfully." -ForegroundColor Green
} catch {
    $errorMsg = $_.Exception.Message
    $errorCode = if ($_.Exception.HResult) { "0x$($_.Exception.HResult.ToString('X8'))" } else { "Unknown" }
    
    # Check for stack overflow
    if ($errorMsg -match 'stack|overflow|buffer|0xC0000409|-1073740771|STATUS_STACK_BUFFER_OVERRUN' -or 
        $errorCode -eq '0xC0000409') {
        $criticalError = "CRITICAL: Stack buffer overrun detected during ShowDialog().`n`n" +
                        "This indicates a memory corruption or stack overflow issue.`n`n" +
                        "Error: $errorMsg`n" +
                        "Error Code: $errorCode`n`n" +
                        "Possible causes:`n" +
                        "  - Too many event handlers causing stack overflow`n" +
                        "  - Memory exhaustion during window initialization`n" +
                        "  - Circular references in event handlers`n" +
                        "  - PowerShell Editor Services memory limits exceeded"
        
        Write-Host $criticalError -ForegroundColor Red
        
        # Log to file
        try {
            $errorLogPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "MiracleBoot_GUI_Error.log"
            Add-Content -Path $errorLogPath -Value "`n$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): STACK BUFFER OVERRUN DETECTED" -ErrorAction SilentlyContinue
            Add-Content -Path $errorLogPath -Value "Error: $errorMsg" -ErrorAction SilentlyContinue
            Add-Content -Path $errorLogPath -Value "Error Code: $errorCode" -ErrorAction SilentlyContinue
            Add-Content -Path $errorLogPath -Value "Stack Trace: $($_.ScriptStackTrace)" -ErrorAction SilentlyContinue
        } catch {}
        
        throw $criticalError
    }
    
    # #region agent log
    try {
        $logPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".cursor\debug.log"
        $logEntry = @{
            sessionId = "debug-session"
            runId = "gui-launch-verify"
            hypothesisId = "VERIFY"
            location = "WinRepairGUI.ps1:ShowDialog-error"
            message = "Error showing GUI window"
            data = @{ 
                error = $errorMsg
                errorCode = $errorCode
                stackTrace = $_.ScriptStackTrace
            }
            timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    # #endregion agent log
    
    throw "Failed to show GUI window: $errorMsg"
}
} # End of Start-GUI function


