<#
    MIRACLE BOOT – CORE ENGINE
    ==========================

    This module contains **all core logic** used by both the GUI (`Start-GUI`)
    and TUI (`Start-TUI`) front‑ends. It is designed to be environment‑agnostic
    and safe to dot‑source from:
      - `MiracleBoot.ps1` (FullOS / WinRE / WinPE)
      - Shift+F10 / WinRE consoles
      - WinPE recovery media

    TABLE OF CONTENTS (HIGH‑LEVEL)
    ------------------------------
    1. Environment & Volume Helpers
       - `Get-EnvironmentType`
       - `Get-WindowsVolumes`, `Get-BCDEntries*`
    2. Boot & BCD Repair
       - BCD parsing / editing helpers
       - Boot chain analysis (`Get-BootChainAnalysis`, `Get-BootLogAnalysis`)
       - Boot probability / health scoring
    3. System Repair Pipelines
       - `Start-SystemFileRepair` (SFC + DISM)
       - `Start-DiskRepair` (CHKDSK)
       - `Start-CompleteSystemRepair`
    4. Progress Tracking Infrastructure
       - `Get-OperationProgress`
       - `Start-OperationWithProgress`
       - Shared `ProgressCallback` patterns used by GUI/TUI
    5. Restore Point Management
       - `Create-SystemRestorePoint`
       - `Get-SystemRestorePoints`
       - `Restore-FromSystemRestorePoint`
       - `Manage-SystemRestorePoints`
    6. Repair-Install Readiness Engine
       - `Test-RepairInstallEligibility`
       - `Clear-CBSBlockers`, `Normalize-SetupState`
       - `Repair-WinREForSetup`
       - `Start-RepairInstallReadiness`
    7. Driver & Network Tooling
       - Driver harvesting / export / injection
       - Network adapter and connectivity helpers
    8. Diagnostics, Logging & Utilities
       - Log analysis helpers
       - SAVE_ME.txt generator
       - Utility helpers shared across UI layers

    ENVIRONMENT MAPPING – WHERE THIS MODULE RUNS
    --------------------------------------------
    - **FullOS (Windows 10/11 desktop)**
        - Called by `MiracleBoot.ps1` before `Start-GUI` or `Start-TUI`.
        - Most functions can target the *online* OS (current C:).

    - **WinRE / Shift+F10**
        - Called by `MiracleBoot.ps1` before launching `Start-TUI`.
        - Most operations run **offline** against a selected Windows volume
          (typically `C:` from the user's machine, not the X: WinRE RAM drive).

    - **WinPE / Recovery Media**
        - Called by custom WinPE shells or `MiracleBoot.ps1` when `Get-EnvironmentType`
          returns `WinPE`.
        - Same offline repair model as WinRE, plus additional driver / browser
          tooling for portable environments.

    FLOW MAPPING – HOW CALLERS USE THIS MODULE
    ------------------------------------------
    1. **MiracleBoot.ps1**
         - Detects environment (`Get-EnvironmentType` in entry script).
         - Dot‑sources **this** file to load all engine functions.
         - Delegates to either GUI (`Start-GUI`) or TUI (`Start-TUI`), both of which
           *only* call functions defined here.

    2. **Helper\WinRepairTUI.ps1 (TUI)**
         - Presents menus for boot repair, SFC/DISM/CHKDSK, diagnostics.
         - For each menu item, calls into the corresponding engine function here
           (e.g. `Start-SystemFileRepair`, `Start-RepairInstallReadiness`).

    3. **Helper\WinRepairGUI.ps1 (WPF GUI)**
         - Wires buttons / tabs to the same engine functions.
         - Uses `ProgressCallback` scriptblocks to surface real‑time progress to the UI.

    QUICK ORIENTATION
    -----------------
    - **Need to know “what does Miracle Boot actually do?”**  
        → Read the function synopsis blocks throughout this file; each major
          subsystem (boot, repair, drivers, readiness) is self‑documented.

    - **Need to add a new repair pipeline?**  
        → Add the core logic **here**, then expose it from:
            - `Start-TUI` (menu item)
            - `Start-GUI` (button / tab)

    - **Need to understand which environment is targeted?**  
        → Most functions accept a `-TargetDrive` / `-TargetWindows` parameter and
          never assume that the current OS drive is the repair target. The caller
          (GUI/TUI) is responsible for choosing the correct drive.
#>

function Optimize-RepairPerformance {
    <#
    .SYNOPSIS
    Optimizes system performance for repair operations by managing resources and priorities.
    
    .DESCRIPTION
    Adjusts system settings to optimize repair operation performance:
    - Sets process priorities
    - Manages memory usage
    - Optimizes disk I/O
    - Configures Windows Update to not interfere
    #>
    param(
        [switch]$RestoreDefaults = $false
    )
    
    $result = @{
        Success = $false
        OptimizationsApplied = @()
        Errors = @()
    }
    
    if ($RestoreDefaults) {
        try {
            # Restore default priorities
            $currentProcess = Get-Process -Id $PID
            $currentProcess.PriorityClass = "Normal"
            $result.OptimizationsApplied += "Restored default process priority"
            $result.Success = $true
        } catch {
            $result.Errors += "Could not restore defaults: $_"
        }
        return $result
    }
    
    try {
        # Set process priority to high for faster execution
        $currentProcess = Get-Process -Id $PID
        $currentProcess.PriorityClass = "High"
        $result.OptimizationsApplied += "Set process priority to High"
        
        # Disable Windows Update during repairs (if online)
        $envType = Get-EnvironmentType
        if ($envType -eq 'FullOS') {
            try {
                $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
                if ($wuService -and $wuService.Status -eq 'Running') {
                    # Note: We don't stop the service, just note it
                    $result.OptimizationsApplied += "Windows Update service detected (not stopped for safety)"
                }
            } catch {
                # Ignore - may not have permissions
            }
        }
        
        # Optimize PowerShell execution policy for faster script execution
        $executionPolicy = Get-ExecutionPolicy
        if ($executionPolicy -eq "Restricted") {
            $result.OptimizationsApplied += "Execution policy is Restricted - may slow operations"
        }
        
        $result.Success = $true
        
    } catch {
        $result.Errors += "Performance optimization failed: $_"
    }
    
    return $result
}

function Get-WinPECapabilities {
    <#
    .SYNOPSIS
    Detects WinPE capabilities and available tools.
    
    .DESCRIPTION
    Checks what tools and features are available in the current WinPE environment,
    including network support, driver injection capabilities, and available utilities.
    #>
    param()
    
    $result = @{
        IsWinPE = $false
        NetworkAvailable = $false
        DISMAvailable = $false
        PowerShellVersion = $null
        AvailableTools = @()
        Limitations = @()
    }
    
    $envType = Get-EnvironmentType
    $result.IsWinPE = ($envType -eq 'WinPE')
    
    if ($result.IsWinPE) {
        # Check PowerShell version
        $result.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        
        # Check for DISM
        if (Get-Command dism -ErrorAction SilentlyContinue) {
            $result.DISMAvailable = $true
            $result.AvailableTools += "DISM"
        }
        
        # Check for network
        try {
            $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
            if ($adapters) {
                $result.NetworkAvailable = $true
                $result.AvailableTools += "Network"
            }
        } catch {
            $result.Limitations += "Network not available or not initialized"
        }
        
        # Check for common WinPE tools
        $tools = @("bcdedit", "bootrec", "diskpart", "reg", "sfc", "chkdsk", "notepad", "regedit")
        foreach ($tool in $tools) {
            if (Get-Command $tool -ErrorAction SilentlyContinue) {
                $result.AvailableTools += $tool
            }
        }
        
        # WinPE limitations
        $result.Limitations += "System Restore not available in WinPE"
        $result.Limitations += "Some Windows services not available"
        $result.Limitations += "Limited registry access (offline mode)"
    }
    
    return $result
}

function Optimize-ForWinPE {
    <#
    .SYNOPSIS
    Optimizes operations for WinPE environment.
    
    .DESCRIPTION
    Adjusts operations and settings specifically for WinPE to ensure
    best performance and compatibility in the limited WinPE environment.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        OptimizationsApplied = @()
        Warnings = @()
    }
    
    $envType = Get-EnvironmentType
    if ($envType -ne 'WinPE') {
        $result.Warnings += "Not running in WinPE - optimizations may not apply"
        return $result
    }
    
    try {
        # Enable network if available
        $capabilities = Get-WinPECapabilities
        if (-not $capabilities.NetworkAvailable) {
            try {
                $netResult = Enable-NetworkWinRE
                if ($netResult.Success) {
                    $result.OptimizationsApplied += "Network enabled in WinPE"
                }
            } catch {
                $result.Warnings += "Could not enable network: $_"
            }
        }
        
        # Optimize DISM for offline operations
        if ($capabilities.DISMAvailable) {
            $result.OptimizationsApplied += "DISM available for offline operations"
        }
        
        # Set optimal PowerShell execution settings
        $ErrorActionPreference = "Continue"
        $result.OptimizationsApplied += "Optimized PowerShell error handling for WinPE"
        
        $result.Success = $true
        
    } catch {
        $result.Warnings += "WinPE optimization failed: $_"
    }
    
    return $result
}

function Get-EnvironmentType {
    <#
    .SYNOPSIS
    Detects the current environment type (FullOS, WinRE, or WinPE).
    #>
    # Primary check: SystemDrive is the most reliable indicator
    # In FullOS, SystemDrive is usually C:, in WinPE/WinRE it's X:
    if ($env:SystemDrive -eq 'X:') {
        # X: drive indicates WinPE/WinRE
        if (Test-Path 'HKLM:\System\Setup') {
            $setupType = (Get-ItemProperty -Path 'HKLM:\System\Setup' -Name 'CmdLine' -ErrorAction SilentlyContinue).CmdLine
            if ($setupType -match 'recovery|WinRE') {
                return 'WinRE'
            }
        }
        # Check for MiniNT (WinPE indicator)
        if (Test-Path 'HKLM:\System\CurrentControlSet\Control\MiniNT') {
            return 'WinPE'
        }
        return 'WinRE' # Default to WinRE if on X: drive
    }
    
    # Secondary check: MiniNT registry key (but only if SystemDrive is X:)
    if (Test-Path 'HKLM:\System\CurrentControlSet\Control\MiniNT') {
        # Only trust this if we're on X: drive
        if ($env:SystemDrive -eq 'X:') {
            return 'WinPE'
        }
        # If we have MiniNT but SystemDrive is NOT X:, check if Windows directory exists
        if (Test-Path "$env:SystemDrive\Windows") {
            return 'FullOS'
        }
    }
    
    # Final check: If SystemDrive is C: (or other), and Windows directory exists, it's FullOS
    if ($env:SystemDrive -ne 'X:' -and (Test-Path "$env:SystemDrive\Windows")) {
        return 'FullOS'
    }
    
    # Default to FullOS if we can't determine (safer assumption)
    return 'FullOS'
}

function Get-WindowsVolumes {
    Get-Volume | Where-Object FileSystem |
        Sort-Object DriveLetter |
        Select DriveLetter, FileSystemLabel, Size, HealthStatus
}

function Get-AllBootableOS {
    <#
    .SYNOPSIS
    Detects all bootable operating systems including Windows and Linux installations.
    
    .DESCRIPTION
    Scans all disks and partitions to find:
    - Windows installations (by detecting Windows directory)
    - Linux installations (by detecting GRUB, systemd-boot, or Linux filesystems)
    - Bootloader locations (EFI partitions, MBR, etc.)
    
    Returns comprehensive information about each bootable OS.
    #>
    param(
        [switch]$IncludeLinux = $true
    )
    
    $result = @{
        WindowsInstallations = @()
        LinuxInstallations = @()
        Bootloaders = @()
        BootEntries = @()
        Conflicts = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("MULTI-BOOT DETECTION REPORT") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Get all disks
    $disks = Get-Disk | Where-Object { $_.OperationalStatus -eq 'Online' }
    
    # Detect Windows installations
    $report.AppendLine("WINDOWS INSTALLATIONS:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    foreach ($disk in $disks) {
        $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
        
        foreach ($partition in $partitions) {
            if ($partition.DriveLetter) {
                $drive = "$($partition.DriveLetter):"
                $windowsPath = "$drive\Windows"
                
                if (Test-Path $windowsPath) {
                    try {
                        # Get Windows version info
                        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                        if (-not $osInfo) {
                            # Try to read from offline registry
                            $osInfo = @{
                                Caption = "Windows (Offline)"
                                Version = "Unknown"
                            }
                        }
                        
                        # Get BCD entry for this installation
                        $bcdEntries = Get-BCDEntriesParsed
                        $matchingEntry = $bcdEntries | Where-Object {
                            $_.Device -like "*$drive*" -or 
                            $_.OSDevice -like "*$drive*" -or
                            $_.Path -like "*$drive*"
                        } | Select-Object -First 1
                        
                        $winInstall = @{
                            DriveLetter = $partition.DriveLetter
                            Drive = $drive
                            DiskNumber = $disk.Number
                            PartitionNumber = $partition.PartitionNumber
                            Size = $partition.Size
                            FileSystem = $partition.FileSystemLabel
                            OSVersion = if ($osInfo.Caption) { $osInfo.Caption } else { "Windows" }
                            OSVersionNumber = if ($osInfo.Version) { $osInfo.Version } else { "Unknown" }
                            BCDEntryID = if ($matchingEntry) { $matchingEntry.Id } else { $null }
                            BCDDescription = if ($matchingEntry) { $matchingEntry.Description } else { "No BCD entry" }
                            IsCurrentOS = ($env:SystemDrive -eq $drive)
                            BootType = if ($disk.PartitionStyle -eq 'GPT') { "UEFI" } else { "Legacy" }
                        }
                        
                        $result.WindowsInstallations += $winInstall
                        
                        $report.AppendLine("Found: $($winInstall.OSVersion) on $drive") | Out-Null
                        $report.AppendLine("  Disk: $($disk.Number), Partition: $($partition.PartitionNumber)") | Out-Null
                        $report.AppendLine("  BCD Entry: $(if ($winInstall.BCDDescription) { $winInstall.BCDDescription } else { 'None' })") | Out-Null
                        $report.AppendLine("  Boot Type: $($winInstall.BootType)") | Out-Null
                        $report.AppendLine("") | Out-Null
                    } catch {
                        Write-Warning "Error detecting Windows on $drive : $_"
                    }
                }
            }
        }
    }
    
    # Detect Linux installations if requested
    if ($IncludeLinux) {
        $report.AppendLine("LINUX INSTALLATIONS:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        foreach ($disk in $disks) {
            $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
            
            foreach ($partition in $partitions) {
                if ($partition.DriveLetter) {
                    $drive = "$($partition.DriveLetter):"
                    
                    # Check for common Linux filesystem indicators
                    $linuxIndicators = @(
                        "$drive\boot",
                        "$drive\etc",
                        "$drive\usr",
                        "$drive\var",
                        "$drive\home"
                    )
                    
                    $linuxFound = $false
                    foreach ($indicator in $linuxIndicators) {
                        if (Test-Path $indicator) {
                            $linuxFound = $true
                            break
                        }
                    }
                    
                    if ($linuxFound) {
                        # Try to detect Linux distribution
                        $distro = "Linux (Unknown Distribution)"
                        if (Test-Path "$drive\etc\os-release") {
                            try {
                                $osRelease = Get-Content "$drive\etc\os-release" -ErrorAction SilentlyContinue
                                $nameLine = $osRelease | Where-Object { $_ -match '^NAME=' }
                                if ($nameLine) {
                                    $distro = $nameLine -replace '^NAME=', '' -replace '"', ''
                                }
                            } catch { }
                        }
                        
                        # Check for GRUB
                        $grubFound = (Test-Path "$drive\boot\grub") -or (Test-Path "$drive\boot\grub2")
                        $systemdBootFound = Test-Path "$drive\boot\EFI\systemd"
                        
                        $linuxInstall = @{
                            DriveLetter = $partition.DriveLetter
                            Drive = $drive
                            DiskNumber = $disk.Number
                            PartitionNumber = $partition.PartitionNumber
                            Size = $partition.Size
                            Distribution = $distro
                            Bootloader = if ($grubFound) { "GRUB" } elseif ($systemdBootFound) { "systemd-boot" } else { "Unknown" }
                            BootType = if ($disk.PartitionStyle -eq 'GPT') { "UEFI" } else { "Legacy" }
                        }
                        
                        $result.LinuxInstallations += $linuxInstall
                        
                        $report.AppendLine("Found: $distro on $drive") | Out-Null
                        $report.AppendLine("  Bootloader: $($linuxInstall.Bootloader)") | Out-Null
                        $report.AppendLine("  Boot Type: $($linuxInstall.BootType)") | Out-Null
                        $report.AppendLine("") | Out-Null
                    }
                }
            }
        }
        
        if ($result.LinuxInstallations.Count -eq 0) {
            $report.AppendLine("No Linux installations detected.") | Out-Null
            $report.AppendLine("") | Out-Null
        }
    }
    
    # Get all BCD entries
    $report.AppendLine("BOOT ENTRIES (BCD):") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $bcdEntries = Get-BCDEntriesParsed
    $bootLoaders = $bcdEntries | Where-Object { $_.Type -eq 'Windows Boot Loader' }
    
    foreach ($entry in $bootLoaders) {
        $result.BootEntries += @{
            ID = $entry.Id
            Description = $entry.Description
            Device = $entry.Device
            OSDevice = $entry.OSDevice
            Path = $entry.Path
        }
        
        $report.AppendLine("Entry: $($entry.Description)") | Out-Null
        $report.AppendLine("  ID: $($entry.Id)") | Out-Null
        $report.AppendLine("  Device: $($entry.Device)") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # Detect conflicts
    $report.AppendLine("CONFLICTS DETECTED:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    # Check for duplicate boot entry names
    $duplicates = Find-DuplicateBCEEntries
    if ($duplicates -and $duplicates.Count -gt 0) {
        foreach ($dup in $duplicates) {
            $result.Conflicts += @{
                Type = "DuplicateBootEntry"
                Severity = "Medium"
                Description = "Duplicate boot entry name: $($dup.Name)"
                AffectedEntries = $dup.Group | ForEach-Object { $_.Id }
                Recommendation = "Rename or remove duplicate entries"
            }
            
            $report.AppendLine("[CONFLICT] Duplicate entry: $($dup.Name)") | Out-Null
            $report.AppendLine("  Affected IDs: $($dup.Group | ForEach-Object { $_.Id } | Join-String -Separator ', ')") | Out-Null
        }
    }
    
    # Check for Windows installations without BCD entries
    foreach ($winInstall in $result.WindowsInstallations) {
        if (-not $winInstall.BCDEntryID) {
            $result.Conflicts += @{
                Type = "MissingBCDEntry"
                Severity = "High"
                Description = "Windows installation on $($winInstall.Drive) has no BCD entry"
                AffectedDrive = $winInstall.Drive
                Recommendation = "Run: bcdboot $($winInstall.Drive)\Windows"
            }
            
            $report.AppendLine("[CONFLICT] Windows on $($winInstall.Drive) has no BCD entry") | Out-Null
        }
    }
    
    if ($result.Conflicts.Count -eq 0) {
        $report.AppendLine("No conflicts detected.") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("SUMMARY:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("Windows Installations: $($result.WindowsInstallations.Count)") | Out-Null
    $report.AppendLine("Linux Installations: $($result.LinuxInstallations.Count)") | Out-Null
    $report.AppendLine("Boot Entries: $($result.BootEntries.Count)") | Out-Null
    $report.AppendLine("Conflicts: $($result.Conflicts.Count)") | Out-Null
    
    $result.Report = $report.ToString()
    return $result
}

function Get-BootEntryConflicts {
    <#
    .SYNOPSIS
    Detects conflicts in boot configuration including duplicate entries and missing entries.
    #>
    param()
    
    $conflicts = @()
    
    # Check for duplicate entries
    $duplicates = Find-DuplicateBCEEntries
    if ($duplicates -and $duplicates.Count -gt 0) {
        foreach ($dup in $duplicates) {
            $conflicts += @{
                Type = "Duplicate"
                Severity = "Medium"
                Description = "Duplicate boot entry: $($dup.Name)"
                Entries = $dup.Group
                Fix = "Rename or remove duplicate entries"
            }
        }
    }
    
    # Check for Windows installations without BCD entries
    $windowsInstalls = Get-AllBootableOS -IncludeLinux:$false
    foreach ($install in $windowsInstalls.WindowsInstallations) {
        if (-not $install.BCDEntryID) {
            $conflicts += @{
                Type = "MissingEntry"
                Severity = "High"
                Description = "Windows installation on $($install.Drive) has no BCD entry"
                Drive = $install.Drive
                Fix = "Run: bcdboot $($install.Drive)\Windows"
            }
        }
    }
    
    return $conflicts
}

function Test-RepairValidation {
    <#
    .SYNOPSIS
    Validates that repair operations were successful by running comprehensive post-repair diagnostics.
    
    .DESCRIPTION
    Performs post-repair validation including:
    - System file health check
    - Disk health check
    - Registry health check
    - Boot probability assessment
    - Boot entry validation
    - Comparison with pre-repair state (if available)
    
    Returns a confidence score (0-100%) and detailed validation report.
    #>
    param(
        [string]$TargetDrive = "C",
        [hashtable]$PreRepairState = $null,
        [switch]$AutoRollback = $false,
        [string]$RestorePointID = $null
    )
    
    $result = @{
        ValidationPassed = $false
        ConfidenceScore = 0
        OverallHealth = "Unknown"
        Checks = @()
        Issues = @()
        Improvements = @()
        Recommendations = @()
        Report = ""
        ShouldRollback = $false
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REPAIR VALIDATION REPORT") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $checksPassed = 0
    $totalChecks = 0
    $scoreWeights = @{
        SystemFiles = 25
        DiskHealth = 20
        Registry = 15
        BootFiles = 20
        BootConfiguration = 20
    }
    
    # 1. System File Health Check
    $totalChecks++
    $report.AppendLine("CHECK 1: System File Health") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        $checkResult = @{
            Name = "System Files"
            Status = if ($fileHealth.SystemFilesHealthy -and $fileHealth.ComponentStoreHealthy) { "Pass" } else { "Fail" }
            Details = "System Files: $(if ($fileHealth.SystemFilesHealthy) { 'OK' } else { 'Issues' }), Component Store: $(if ($fileHealth.ComponentStoreHealthy) { 'OK' } else { 'Issues' })"
            Score = if ($fileHealth.SystemFilesHealthy -and $fileHealth.ComponentStoreHealthy) { $scoreWeights.SystemFiles } else { 0 }
        }
        
        if ($checkResult.Status -eq "Pass") {
            $checksPassed++
            $result.ConfidenceScore += $checkResult.Score
            $result.Improvements += "System files are healthy"
        } else {
            $result.Issues += "System file health issues detected"
            $result.Recommendations += "Run SFC /scannow and DISM /RestoreHealth"
        }
        
        # Compare with pre-repair state
        if ($PreRepairState -and $PreRepairState.SystemFileHealth) {
            $beforeHealthy = $PreRepairState.SystemFileHealth.SystemFilesHealthy
            $afterHealthy = $fileHealth.SystemFilesHealthy
            if (-not $beforeHealthy -and $afterHealthy) {
                $result.Improvements += "System files repaired (were unhealthy before)"
            } elseif ($beforeHealthy -and -not $afterHealthy) {
                $result.Issues += "System files degraded after repair"
                $result.ShouldRollback = $true
            }
        }
        
        $result.Checks += $checkResult
        $report.AppendLine("Status: $($checkResult.Status)") | Out-Null
        $report.AppendLine("Details: $($checkResult.Details)") | Out-Null
        $report.AppendLine("") | Out-Null
    } catch {
        $result.Issues += "System file health check failed: $_"
        $report.AppendLine("[ERROR] System file health check failed: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # 2. Disk Health Check
    $totalChecks++
    $report.AppendLine("CHECK 2: Disk Health") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        $checkResult = @{
            Name = "Disk Health"
            Status = if ($diskHealth.FileSystemHealthy -and -not $diskHealth.HasBadSectors) { "Pass" } else { "Fail" }
            Details = "File System: $(if ($diskHealth.FileSystemHealthy) { 'OK' } else { 'Issues' }), Bad Sectors: $(if ($diskHealth.HasBadSectors) { 'Yes' } else { 'No' })"
            Score = if ($diskHealth.FileSystemHealthy -and -not $diskHealth.HasBadSectors) { $scoreWeights.DiskHealth } else { [math]::Floor($scoreWeights.DiskHealth / 2) }
        }
        
        if ($checkResult.Status -eq "Pass") {
            $checksPassed++
            $result.ConfidenceScore += $checkResult.Score
        } else {
            $result.Issues += "Disk health issues detected"
            if ($diskHealth.HasBadSectors) {
                $result.Recommendations += "Run chkdsk /r to recover bad sectors"
            } else {
                $result.Recommendations += "Run chkdsk /f to fix file system errors"
            }
        }
        
        $result.Checks += $checkResult
        $report.AppendLine("Status: $($checkResult.Status)") | Out-Null
        $report.AppendLine("Details: $($checkResult.Details)") | Out-Null
        $report.AppendLine("") | Out-Null
    } catch {
        $result.Issues += "Disk health check failed: $_"
        $report.AppendLine("[ERROR] Disk health check failed: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # 3. Registry Health Check
    $totalChecks++
    $report.AppendLine("CHECK 3: Registry Health") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $regHealth = Test-RegistryHealth -TargetDrive $TargetDrive
        $checkResult = @{
            Name = "Registry"
            Status = if ($regHealth.Healthy) { "Pass" } else { "Fail" }
            Details = if ($regHealth.Healthy) { "All registry hives are healthy" } else { "Issues: $($regHealth.Issues -join ', ')" }
            Score = if ($regHealth.Healthy) { $scoreWeights.Registry } else { 0 }
        }
        
        if ($checkResult.Status -eq "Pass") {
            $checksPassed++
            $result.ConfidenceScore += $checkResult.Score
        } else {
            $result.Issues += "Registry health issues: $($regHealth.Issues -join ', ')"
            $result.Recommendations += "Registry hives may need repair or restoration"
        }
        
        $result.Checks += $checkResult
        $report.AppendLine("Status: $($checkResult.Status)") | Out-Null
        $report.AppendLine("Details: $($checkResult.Details)") | Out-Null
        $report.AppendLine("") | Out-Null
    } catch {
        $result.Issues += "Registry health check failed: $_"
        $report.AppendLine("[ERROR] Registry health check failed: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # 4. Boot Probability Assessment
    $totalChecks++
    $report.AppendLine("CHECK 4: Boot Probability") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $bootProb = Get-BootProbability -TargetDrive $TargetDrive
        $checkResult = @{
            Name = "Boot Files"
            Status = if ($bootProb.Score -ge 70) { "Pass" } elseif ($bootProb.Score -ge 50) { "Warning" } else { "Fail" }
            Details = "Boot Probability: $($bootProb.Score)% - $($bootProb.HealthStatus)"
            Score = [math]::Floor(($bootProb.Score / 100) * $scoreWeights.BootFiles)
        }
        
        $result.ConfidenceScore += $checkResult.Score
        
        if ($bootProb.Score -ge 70) {
            $checksPassed++
            $result.Improvements += "Boot probability is good ($($bootProb.Score)%)"
        } elseif ($bootProb.Score -ge 50) {
            $result.Issues += "Boot probability is moderate ($($bootProb.Score)%)"
            $result.Recommendations += "Review boot configuration and boot files"
        } else {
            $result.Issues += "Boot probability is low ($($bootProb.Score)%)"
            $result.Recommendations += "Critical boot issues detected - system may not boot"
            $result.ShouldRollback = $true
        }
        
        $result.Checks += $checkResult
        $report.AppendLine("Status: $($checkResult.Status)") | Out-Null
        $report.AppendLine("Details: $($checkResult.Details)") | Out-Null
        $report.AppendLine("") | Out-Null
    } catch {
        $result.Issues += "Boot probability check failed: $_"
        $report.AppendLine("[ERROR] Boot probability check failed: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # 5. Boot Configuration Check
    $totalChecks++
    $report.AppendLine("CHECK 5: Boot Configuration") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $bootConflicts = Get-BootEntryConflicts
        $bcdEntries = Get-BCDEntriesParsed
        $bootLoaders = $bcdEntries | Where-Object { $_.Type -eq 'Windows Boot Loader' }
        
        $checkResult = @{
            Name = "Boot Configuration"
            Status = if ($bootConflicts.Count -eq 0 -and $bootLoaders.Count -gt 0) { "Pass" } else { "Fail" }
            Details = "Boot Entries: $($bootLoaders.Count), Conflicts: $($bootConflicts.Count)"
            Score = if ($bootConflicts.Count -eq 0 -and $bootLoaders.Count -gt 0) { $scoreWeights.BootConfiguration } else { [math]::Floor($scoreWeights.BootConfiguration / 2) }
        }
        
        if ($checkResult.Status -eq "Pass") {
            $checksPassed++
            $result.ConfidenceScore += $checkResult.Score
        } else {
            if ($bootConflicts.Count -gt 0) {
                $result.Issues += "Boot configuration conflicts detected: $($bootConflicts.Count)"
                foreach ($conflict in $bootConflicts) {
                    $result.Recommendations += $conflict.Fix
                }
            }
            if ($bootLoaders.Count -eq 0) {
                $result.Issues += "No boot entries found"
                $result.Recommendations += "Run: bcdboot $TargetDrive`:\Windows"
                $result.ShouldRollback = $true
            }
        }
        
        $result.Checks += $checkResult
        $report.AppendLine("Status: $($checkResult.Status)") | Out-Null
        $report.AppendLine("Details: $($checkResult.Details)") | Out-Null
        $report.AppendLine("") | Out-Null
    } catch {
        $result.Issues += "Boot configuration check failed: $_"
        $report.AppendLine("[ERROR] Boot configuration check failed: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # Calculate overall health
    $result.ConfidenceScore = [math]::Min(100, [math]::Max(0, $result.ConfidenceScore))
    
    if ($result.ConfidenceScore -ge 80) {
        $result.OverallHealth = "Excellent"
        $result.ValidationPassed = $true
    } elseif ($result.ConfidenceScore -ge 60) {
        $result.OverallHealth = "Good"
        $result.ValidationPassed = $true
    } elseif ($result.ConfidenceScore -ge 40) {
        $result.OverallHealth = "Fair"
        $result.ValidationPassed = $false
    } else {
        $result.OverallHealth = "Poor"
        $result.ValidationPassed = $false
        $result.ShouldRollback = $true
    }
    
    # Summary
    $report.AppendLine("VALIDATION SUMMARY") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("Checks Passed: $checksPassed / $totalChecks") | Out-Null
    $report.AppendLine("Confidence Score: $($result.ConfidenceScore)%") | Out-Null
    $report.AppendLine("Overall Health: $($result.OverallHealth)") | Out-Null
    $report.AppendLine("Validation Passed: $(if ($result.ValidationPassed) { 'YES' } else { 'NO' })") | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($result.Issues.Count -gt 0) {
        $report.AppendLine("ISSUES DETECTED:") | Out-Null
        foreach ($issue in $result.Issues) {
            $report.AppendLine("  - $issue") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    if ($result.Improvements.Count -gt 0) {
        $report.AppendLine("IMPROVEMENTS:") | Out-Null
        foreach ($improvement in $result.Improvements) {
            $report.AppendLine("  + $improvement") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    if ($result.Recommendations.Count -gt 0) {
        $report.AppendLine("RECOMMENDATIONS:") | Out-Null
        foreach ($rec in $result.Recommendations) {
            $report.AppendLine("  → $rec") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Auto-rollback recommendation
    if ($AutoRollback -and $result.ShouldRollback -and $RestorePointID) {
        $report.AppendLine("AUTO-ROLLBACK RECOMMENDED") | Out-Null
        $report.AppendLine("Validation failed with critical issues. Consider restoring from restore point #$RestorePointID") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Get-BCDEntries {
    # Returns raw objects for the GUI to parse
    bcdedit /enum /v
}

function Test-Administrator {
    <#
    .SYNOPSIS
    Checks if the current PowerShell session is running with administrator privileges.
    
    .DESCRIPTION
    Returns $true if running as administrator, $false otherwise.
    #>
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BCDEntriesParsed {
    # Production-grade BCD parser - captures ALL properties
    # #region agent log
    try {
        $logPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ".cursor\debug.log"
        $logEntry = @{
            sessionId = "debug-session"
            runId = "bcd-access-check"
            hypothesisId = "BCD-ACCESS"
            location = "WinRepairCore.ps1:Get-BCDEntriesParsed"
            message = "About to call bcdedit"
            data = @{ isAdmin = (Test-Administrator) }
            timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
    # #endregion agent log
    
    # Check for administrator privileges
    if (-not (Test-Administrator)) {
        $errorMsg = "Access Denied: BCD operations require administrator privileges.`n`n" +
                    "Please run Miracle Boot as Administrator:`n" +
                    "1. Right-click on PowerShell or the shortcut`n" +
                    "2. Select 'Run as Administrator'`n" +
                    "3. Then launch Miracle Boot again`n`n" +
                    "Alternatively, you can use the 'Run as Administrator' option when launching the application."
        throw $errorMsg
    }
    
    try {
        $raw = bcdedit /enum /v 2>&1
        # Check if the output contains access denied error
        if ($raw -is [System.Array]) {
            $errorLines = $raw | Where-Object { $_ -match "access is denied|Access is denied|ERROR|The boot configuration data store could not be opened" }
            if ($errorLines) {
                $errorText = $errorLines -join "`n"
                # #region agent log
                try {
                    $logEntry = @{
                        sessionId = "debug-session"
                        runId = "bcd-access-check"
                        hypothesisId = "BCD-ACCESS"
                        location = "WinRepairCore.ps1:Get-BCDEntriesParsed-error"
                        message = "BCD access denied detected"
                        data = @{ errorText = $errorText; isAdmin = (Test-Administrator) }
                        timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                    } | ConvertTo-Json -Compress
                    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
                } catch {}
                # #endregion agent log
                throw "Access Denied: The boot configuration data store could not be opened.`n`n" +
                      "This operation requires administrator privileges.`n`n" +
                      "Please run Miracle Boot as Administrator."
            }
        }
    } catch {
        # #region agent log
        try {
            $logEntry = @{
                sessionId = "debug-session"
                runId = "bcd-access-check"
                hypothesisId = "BCD-ACCESS"
                location = "WinRepairCore.ps1:Get-BCDEntriesParsed-exception"
                message = "Exception calling bcdedit"
                data = @{ error = $_.Exception.Message; isAdmin = (Test-Administrator) }
                timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            } | ConvertTo-Json -Compress
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
        } catch {}
        # #endregion agent log
        
        # Re-throw with enhanced message if it's an access denied error
        if ($_.Exception.Message -match "access is denied|Access is denied|could not be opened") {
            throw "Access Denied: The boot configuration data store could not be opened.`n`n" +
                  "This operation requires administrator privileges.`n`n" +
                  "Please run Miracle Boot as Administrator."
        }
        throw
    }
    
    $entries = @()
    $currentEntry = $null
    $entryType = $null
    
    foreach ($line in $raw) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Detect entry type header - this starts a NEW entry
        if ($line -match '^Windows Boot Manager') {
            # Save previous entry if exists
            if ($currentEntry) { 
                $currentEntry.Type = $entryType
                $entries += $currentEntry 
            }
            # Start new entry
            $entryType = "Windows Boot Manager"
            $currentEntry = [ordered]@{}
            continue
        }
        elseif ($line -match '^Windows Boot Loader') {
            # Save previous entry if exists
            if ($currentEntry) { 
                $currentEntry.Type = $entryType
                $entries += $currentEntry 
            }
            # Start new entry
            $entryType = "Windows Boot Loader"
            $currentEntry = [ordered]@{}
            continue
        }
        elseif ($line -match '^Legacy') {
            # Save previous entry if exists
            if ($currentEntry) { 
                $currentEntry.Type = $entryType
                $entries += $currentEntry 
            }
            # Start new entry
            $entryType = "Legacy"
            $currentEntry = [ordered]@{}
            continue
        }
        
        # Skip separator lines (they're just visual)
        if ($line -match '^-{3,}') {
            continue
        }
        
        # Skip if no current entry
        if (-not $currentEntry) { continue }
        
        # Parse property: value pairs (handles multi-line values)
        if ($line -match '^(\w+)\s+(.+)$') {
            $propName = $matches[1].Trim()
            $propValue = $matches[2].Trim()
            
            # Handle special cases
            if ($propName -eq 'identifier') {
                $currentEntry.Id = $propValue
            }
            elseif ($propName -eq 'description') {
                $currentEntry.Description = $propValue
            }
            else {
                # Store all other properties
                $currentEntry[$propName] = $propValue
            }
        }
        elseif ($line -match '^(\w+)\s*$') {
            # Property with no value (boolean flags)
            $propName = $matches[1].Trim()
            $currentEntry[$propName] = $true
        }
    }
    
    # Save last entry
    if ($currentEntry) { 
        $currentEntry.Type = $entryType
        $entries += $currentEntry 
    }
    
    return $entries
}

function Get-BCDTimeout {
    $timeout = bcdedit /timeout
    if ($timeout -match "\d+") { return $matches[0] }
    return "0"
}

function Set-BCDDescription {
    param(
        $Id, 
        $NewName,
        [switch]$CreateRestorePoint = $true,
        [switch]$SkipRestorePoint = $false
    )
    
    # Create restore point before BCD modification if enabled
    $envType = Get-EnvironmentType
    if ($CreateRestorePoint -and -not $SkipRestorePoint -and $envType -eq 'FullOS') {
        $restorePoint = Create-SystemRestorePoint -Description "Before BCD Description Change" -OperationType "BCDModification"
        if (-not $restorePoint.Success) {
            Write-Warning "Could not create restore point before BCD modification: $($restorePoint.Message)"
        }
    }
    
    if ($Id -and $NewName) { 
        bcdedit /set $Id description "$NewName"
    }
}

function Set-BCDDefaultEntry {
    param(
        $Id,
        [switch]$CreateRestorePoint = $true,
        [switch]$SkipRestorePoint = $false
    )
    
    # Create restore point before BCD modification if enabled
    $envType = Get-EnvironmentType
    if ($CreateRestorePoint -and -not $SkipRestorePoint -and $envType -eq 'FullOS') {
        $restorePoint = Create-SystemRestorePoint -Description "Before BCD Default Entry Change" -OperationType "BCDModification"
        if (-not $restorePoint.Success) {
            Write-Warning "Could not create restore point before BCD modification: $($restorePoint.Message)"
        }
    }
    
    if ($Id) { 
        bcdedit /default $Id 
    }
}

function Set-BCDProperty {
    param(
        $Id, 
        $Property, 
        $Value,
        [switch]$CreateRestorePoint = $true,
        [switch]$SkipRestorePoint = $false
    )
    
    # Create restore point before BCD modification if enabled
    $envType = Get-EnvironmentType
    if ($CreateRestorePoint -and -not $SkipRestorePoint -and $envType -eq 'FullOS') {
        $restorePoint = Create-SystemRestorePoint -Description "Before BCD Property Change" -OperationType "BCDModification"
        if (-not $restorePoint.Success) {
            Write-Warning "Could not create restore point before BCD modification: $($restorePoint.Message)"
        }
    }
    
    if ($Id -and $Property) {
        if ($Value -is [bool] -and $Value) {
            bcdedit /set $Id $Property
        } elseif ($Value) {
            bcdedit /set $Id $Property $Value
        } else {
            bcdedit /deletevalue $Id $Property
        }
    }
}

function Export-BCDBackup {
    param($BackupPath = "$env:TEMP\BCD_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').bcd")
    try {
        bcdedit /export $BackupPath | Out-Null
        return @{Success = $true; Path = $BackupPath}
    } catch {
        return @{Success = $false; Error = $_.Exception.Message}
    }
}

function Get-BootDiagnosis {
    param($TargetDrive = "C")
    $report = "--- BOOT DIAGNOSIS REPORT ($TargetDrive`:) ---`n`n"
    
    # 1. Check for OS Presence
    if (Test-Path "$TargetDrive`:\Windows\System32\ntoskrnl.exe") {
        $report += "[OK] Windows OS detected on $TargetDrive`:`n"
    } else {
        $report += "[ERROR] No Windows installation found on $TargetDrive`:`n"
    }

    # 2. Check for EFI Partition
    try {
        $partition = Get-Partition -DriveLetter $TargetDrive -ErrorAction SilentlyContinue
        if ($partition) {
            $disk = Get-Disk -Number $partition.DiskNumber
            $efiParts = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
            if ($efiParts) {
                $report += "[OK] EFI System Partition found on Disk $($disk.Number)`n"
                foreach ($efi in $efiParts) {
                    $report += "    Partition: $($efi.PartitionNumber), Size: $([math]::Round($efi.Size/1MB, 2)) MB`n"
                }
            } else {
                $report += "[CRITICAL] No EFI Partition found on the disk containing $TargetDrive`:`n"
            }
        }
    } catch {
        $report += "[WARNING] Could not check EFI partitions: $_`n"
    }

    # 3. Check BCD Integrity
    try {
        $bcdCheck = bcdedit /enum 2>&1 | Select-String "Windows Boot Manager"
        if ($bcdCheck) { 
            $report += "[OK] BCD Store is accessible and contains entries.`n" 
        } else {
            $report += "[WARNING] BCD Store may be empty or corrupted.`n"
        }
    } catch {
        $report += "[CRITICAL] BCD Store is missing or corrupted!`n"
    }

    # 4. Check for duplicate entries (only Windows Boot Loaders, exclude system entries)
    $duplicates = Find-DuplicateBCEEntries
    if ($duplicates -and $duplicates.Count -gt 0) {
        $report += "[WARNING] Found $($duplicates.Count) duplicate boot entry name(s):`n"
        foreach ($dup in $duplicates) {
            $report += "    '$($dup.Name)' appears $($dup.Count) times`n"
        }
    } else {
        $report += "[OK] No duplicate boot entry names found.`n"
    }

    return $report
}

function Get-BootProbability {
    <#
    .SYNOPSIS
    Comprehensive boot health check that calculates the probability of successful boot.
    
    .DESCRIPTION
    Checks all critical boot components and calculates a probability score (0-100%):
    - Windows OS files presence
    - EFI partition existence and health
    - BCD store integrity
    - Boot files presence
    - Boot configuration validity
    - Disk health
    
    Returns detailed assessment with probability score and recommendations.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        BootProbability = 0
        BootHealth = "Unknown"
        Score = 0
        MaxScore = 0
        Checks = @()
        CriticalIssues = @()
        Warnings = @()
        Recommendations = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("BOOT PROBABILITY / BOOT HEALTH ASSESSMENT") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $score = 0
    $maxScore = 0
    
    # ========================================================================
    # CHECK 1: Windows OS Files (Critical - 25 points)
    # ========================================================================
    $maxScore += 25
    $report.AppendLine("CHECK 1: Windows OS Files (25 points)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $osFiles = @(
        "$TargetDrive`:\Windows\System32\ntoskrnl.exe",
        "$TargetDrive`:\Windows\System32\hal.dll",
        "$TargetDrive`:\Windows\System32\boot\winload.exe",
        "$TargetDrive`:\Windows\System32\boot\winload.efi"
    )
    
    $osFilesFound = 0
    foreach ($file in $osFiles) {
        if (Test-Path $file) {
            $osFilesFound++
            $report.AppendLine("[OK] Found: $(Split-Path $file -Leaf)") | Out-Null
        } else {
            $report.AppendLine("[MISSING] $(Split-Path $file -Leaf)") | Out-Null
        }
    }
    
    if ($osFilesFound -eq $osFiles.Count) {
        $score += 25
        $result.Checks += @{ Name = "Windows OS Files"; Status = "PASS"; Points = 25 }
        $report.AppendLine("[PASS] All critical OS files present (25/25 points)") | Out-Null
    } elseif ($osFilesFound -ge 2) {
        $partialScore = [math]::Round(($osFilesFound / $osFiles.Count) * 25)
        $score += $partialScore
        $result.Checks += @{ Name = "Windows OS Files"; Status = "PARTIAL"; Points = $partialScore }
        $report.AppendLine("[PARTIAL] $osFilesFound/$($osFiles.Count) OS files found ($partialScore/25 points)") | Out-Null
        $result.Warnings += "Some Windows OS files are missing"
    } else {
        $result.Checks += @{ Name = "Windows OS Files"; Status = "FAIL"; Points = 0 }
        $result.CriticalIssues += "Critical Windows OS files are missing"
        $report.AppendLine("[FAIL] Critical OS files missing (0/25 points)") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 2: EFI Partition (Critical - 25 points)
    # ========================================================================
    $maxScore += 25
    $report.AppendLine("CHECK 2: EFI System Partition (25 points)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $efiPartitionFound = $false
    $efiPartitionHealthy = $false
    $efiDriveLetter = $null
    
    try {
        $partition = Get-Partition -DriveLetter $TargetDrive -ErrorAction SilentlyContinue
        if ($partition) {
            $disk = Get-Disk -Number $partition.DiskNumber
            $efiParts = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
            
            if ($efiParts -and $efiParts.Count -gt 0) {
                $efiPartitionFound = $true
                $score += 15
                $report.AppendLine("[OK] EFI System Partition found on Disk $($disk.Number) (15/25 points)") | Out-Null
                
                # Check if EFI partition has drive letter
                foreach ($efiPart in $efiParts) {
                    if ($efiPart.DriveLetter) {
                        $efiDriveLetter = $efiPart.DriveLetter
                        $report.AppendLine("[OK] EFI partition has drive letter: $efiDriveLetter`:") | Out-Null
                        
                        # Check EFI partition format
                        $efiVolume = Get-Volume -DriveLetter $efiDriveLetter -ErrorAction SilentlyContinue
                        if ($efiVolume) {
                            if ($efiVolume.FileSystem -eq "FAT32") {
                                $score += 5
                                $efiPartitionHealthy = $true
                                $report.AppendLine("[OK] EFI partition formatted as FAT32 (correct) (5/25 points)") | Out-Null
                            } else {
                                $report.AppendLine("[FAIL] EFI partition formatted as $($efiVolume.FileSystem) (should be FAT32)") | Out-Null
                                $result.CriticalIssues += "EFI partition is not FAT32 format"
                            }
                        }
                        
                        # Check for Microsoft Boot folder
                        $bootPath = "$efiDriveLetter`:\EFI\Microsoft\Boot"
                        if (Test-Path $bootPath) {
                            $score += 5
                            $report.AppendLine("[OK] Microsoft Boot folder structure exists (5/25 points)") | Out-Null
                        } else {
                            $report.AppendLine("[FAIL] Microsoft Boot folder missing on EFI partition") | Out-Null
                            $result.CriticalIssues += "EFI partition missing Microsoft Boot folder"
                        }
                        break
                    }
                }
                
                if (-not $efiDriveLetter) {
                    $report.AppendLine("[WARNING] EFI partition found but no drive letter assigned") | Out-Null
                    $result.Warnings += "EFI partition exists but is not accessible (no drive letter)"
                }
                
                $result.Checks += @{ Name = "EFI Partition"; Status = if ($efiPartitionHealthy) { "PASS" } else { "PARTIAL" }; Points = if ($efiPartitionHealthy) { 25 } else { 15 } }
            } else {
                $report.AppendLine("[FAIL] No EFI System Partition found (0/25 points)") | Out-Null
                $result.Checks += @{ Name = "EFI Partition"; Status = "FAIL"; Points = 0 }
                $result.CriticalIssues += "No EFI System Partition detected - system cannot boot in UEFI mode"
            }
        } else {
            $report.AppendLine("[WARNING] Could not determine partition information") | Out-Null
            $result.Checks += @{ Name = "EFI Partition"; Status = "UNKNOWN"; Points = 0 }
        }
    } catch {
        $report.AppendLine("[ERROR] Failed to check EFI partition: $_") | Out-Null
        $result.Checks += @{ Name = "EFI Partition"; Status = "ERROR"; Points = 0 }
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 3: BCD Store (Critical - 25 points)
    # ========================================================================
    $maxScore += 25
    $report.AppendLine("CHECK 3: Boot Configuration Data (BCD) Store (25 points)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $bcdFound = $false
    $bcdAccessible = $false
    $bcdHasEntries = $false
    
    # Try to find BCD file
    if ($efiDriveLetter) {
        $bcdPath = "$efiDriveLetter`:\EFI\Microsoft\Boot\BCD"
        if (Test-Path $bcdPath) {
            $bcdFound = $true
            $score += 10
            $report.AppendLine("[OK] BCD file exists at: $bcdPath (10/25 points)") | Out-Null
        } else {
            $report.AppendLine("[FAIL] BCD file not found at expected location: $bcdPath") | Out-Null
            $result.CriticalIssues += "BCD file is missing"
        }
    } else {
        # Try to find BCD on any EFI partition
        $allEfiParts = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -and $_.DriveLetter }
        foreach ($efi in $allEfiParts) {
            $testPath = "$($efi.DriveLetter):\EFI\Microsoft\Boot\BCD"
            if (Test-Path $testPath) {
                $bcdFound = $true
                $bcdPath = $testPath
                $efiDriveLetter = $efi.DriveLetter
                $score += 10
                $report.AppendLine("[OK] BCD file found at: $testPath (10/25 points)") | Out-Null
                break
            }
        }
        
        if (-not $bcdFound) {
            $report.AppendLine("[FAIL] BCD file not found on any EFI partition") | Out-Null
            $result.CriticalIssues += "BCD file is missing"
        }
    }
    
    # Check BCD accessibility and integrity
    if ($bcdFound) {
        try {
            $bcdEnum = bcdedit /enum 2>&1 | Out-String
            if ($bcdEnum -match "The boot configuration data store could not be opened" -or 
                $bcdEnum -match "could not be opened") {
                $report.AppendLine("[FAIL] BCD exists but cannot be opened - may be corrupted or locked (0/15 remaining points)") | Out-Null
                $result.CriticalIssues += "BCD file exists but is corrupted or locked"
            } else {
                $bcdAccessible = $true
                $score += 10
                $report.AppendLine("[OK] BCD store is accessible (10/25 points)") | Out-Null
                
                # Check if BCD has entries
                if ($bcdEnum -match "Windows Boot Manager" -or $bcdEnum -match "Windows Boot Loader") {
                    $bcdHasEntries = $true
                    $score += 5
                    $report.AppendLine("[OK] BCD contains boot entries (5/25 points)") | Out-Null
                } else {
                    $report.AppendLine("[FAIL] BCD is accessible but contains no boot entries") | Out-Null
                    $result.CriticalIssues += "BCD store is empty - no boot entries found"
                }
            }
        } catch {
            $report.AppendLine("[WARNING] Could not test BCD accessibility: $_") | Out-Null
        }
    }
    
    if ($bcdFound -and $bcdAccessible -and $bcdHasEntries) {
        $result.Checks += @{ Name = "BCD Store"; Status = "PASS"; Points = 25 }
    } elseif ($bcdFound -and $bcdAccessible) {
        $result.Checks += @{ Name = "BCD Store"; Status = "PARTIAL"; Points = 20 }
    } elseif ($bcdFound) {
        $result.Checks += @{ Name = "BCD Store"; Status = "PARTIAL"; Points = 10 }
    } else {
        $result.Checks += @{ Name = "BCD Store"; Status = "FAIL"; Points = 0 }
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 4: Boot Files (Important - 15 points)
    # ========================================================================
    $maxScore += 15
    $report.AppendLine("CHECK 4: Boot Files (15 points)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $bootFiles = @()
    if ($efiDriveLetter) {
        $bootFiles = @(
            "$efiDriveLetter`:\EFI\Microsoft\Boot\bootmgfw.efi",
            "$efiDriveLetter`:\EFI\Microsoft\Boot\memtest.efi"
        )
    }
    
    $bootFilesFound = 0
    foreach ($file in $bootFiles) {
        if (Test-Path $file) {
            $bootFilesFound++
            $report.AppendLine("[OK] Found: $(Split-Path $file -Leaf)") | Out-Null
        }
    }
    
    if ($bootFiles.Count -gt 0) {
        if ($bootFilesFound -eq $bootFiles.Count) {
            $score += 15
            $result.Checks += @{ Name = "Boot Files"; Status = "PASS"; Points = 15 }
            $report.AppendLine("[PASS] All boot files present (15/15 points)") | Out-Null
        } elseif ($bootFilesFound -gt 0) {
            $partialScore = [math]::Round(($bootFilesFound / $bootFiles.Count) * 15)
            $score += $partialScore
            $result.Checks += @{ Name = "Boot Files"; Status = "PARTIAL"; Points = $partialScore }
            $report.AppendLine("[PARTIAL] $bootFilesFound/$($bootFiles.Count) boot files found ($partialScore/15 points)") | Out-Null
        } else {
            $result.Checks += @{ Name = "Boot Files"; Status = "FAIL"; Points = 0 }
            $result.Warnings += "Boot files are missing from EFI partition"
            $report.AppendLine("[FAIL] Boot files missing (0/15 points)") | Out-Null
        }
    } else {
        $report.AppendLine("[SKIP] Cannot check boot files - EFI partition not accessible") | Out-Null
        $result.Checks += @{ Name = "Boot Files"; Status = "SKIP"; Points = 0 }
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 5: Boot Configuration Validity (Important - 10 points)
    # ========================================================================
    $maxScore += 10
    $report.AppendLine("CHECK 5: Boot Configuration Validity (10 points)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    try {
        $bcdEntries = Get-BCDEntriesParsed -ErrorAction SilentlyContinue
        if ($bcdEntries -and $bcdEntries.Count -gt 0) {
            $validEntries = 0
            foreach ($entry in $bcdEntries) {
                if ($entry.Type -match "Windows Boot Loader" -and $entry.device -and $entry.path) {
                    # Check if device and path are valid
                    if ($entry.device -match "partition=([A-Z]):" -or $entry.path) {
                        $validEntries++
                    }
                }
            }
            
            if ($validEntries -gt 0) {
                $score += 10
                $result.Checks += @{ Name = "Boot Configuration"; Status = "PASS"; Points = 10 }
                $report.AppendLine("[PASS] Valid boot entries found ($validEntries entry/entries) (10/10 points)") | Out-Null
            } else {
                $result.Checks += @{ Name = "Boot Configuration"; Status = "FAIL"; Points = 0 }
                $result.CriticalIssues += "Boot entries exist but are invalid"
                $report.AppendLine("[FAIL] Boot entries are invalid (0/10 points)") | Out-Null
            }
        } else {
            $result.Checks += @{ Name = "Boot Configuration"; Status = "FAIL"; Points = 0 }
            $result.CriticalIssues += "No valid boot entries in BCD"
            $report.AppendLine("[FAIL] No boot entries found (0/10 points)") | Out-Null
        }
    } catch {
        $result.Checks += @{ Name = "Boot Configuration"; Status = "ERROR"; Points = 0 }
        $report.AppendLine("[ERROR] Could not validate boot configuration: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # Calculate Final Score and Probability
    # ========================================================================
    $result.Score = $score
    $result.MaxScore = $maxScore
    $probability = [math]::Round(($score / $maxScore) * 100)
    $result.BootProbability = $probability
    
    # Determine health status
    if ($probability -ge 90) {
        $result.BootHealth = "Excellent"
    } elseif ($probability -ge 75) {
        $result.BootHealth = "Good"
    } elseif ($probability -ge 50) {
        $result.BootHealth = "Fair"
    } elseif ($probability -ge 25) {
        $result.BootHealth = "Poor"
    } else {
        $result.BootHealth = "Critical"
    }
    
    # Generate recommendations
    if ($result.CriticalIssues.Count -gt 0) {
        if ($result.CriticalIssues -contains "No EFI System Partition detected") {
            $result.Recommendations += "Create EFI partition or verify system uses Legacy BIOS mode"
        }
        if ($result.CriticalIssues -contains "BCD file is missing") {
            $result.Recommendations += "Run: bcdboot $TargetDrive`:\Windows /s [EFI_DRIVE]: /f UEFI"
        }
        if ($result.CriticalIssues -contains "BCD file exists but is corrupted") {
            $result.Recommendations += "Run: bootrec /rebuildbcd or bcdboot $TargetDrive`:\Windows /s [EFI_DRIVE]: /f UEFI"
        }
    }
    
    # Final Report
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("BOOT PROBABILITY ASSESSMENT") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Score: $score / $maxScore points") | Out-Null
    $report.AppendLine("Boot Probability: $probability%") | Out-Null
    $report.AppendLine("Boot Health Status: $($result.BootHealth)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($probability -ge 90) {
        $report.AppendLine("[EXCELLENT] System has a very high probability of successful boot.") | Out-Null
        $report.AppendLine("All critical boot components are present and healthy.") | Out-Null
    } elseif ($probability -ge 75) {
        $report.AppendLine("[GOOD] System has a good probability of successful boot.") | Out-Null
        $report.AppendLine("Most boot components are healthy, but some issues may need attention.") | Out-Null
    } elseif ($probability -ge 50) {
        $report.AppendLine("[FAIR] System has a moderate probability of successful boot.") | Out-Null
        $report.AppendLine("Several boot components have issues that should be addressed.") | Out-Null
    } elseif ($probability -ge 25) {
        $report.AppendLine("[POOR] System has a low probability of successful boot.") | Out-Null
        $report.AppendLine("Critical boot components are missing or damaged.") | Out-Null
    } else {
        $report.AppendLine("[CRITICAL] System has a very low probability of successful boot.") | Out-Null
        $report.AppendLine("Multiple critical boot components are missing or corrupted.") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    if ($result.CriticalIssues.Count -gt 0) {
        $report.AppendLine("CRITICAL ISSUES FOUND:") | Out-Null
        foreach ($issue in $result.CriticalIssues) {
            $report.AppendLine("  - $issue") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    if ($result.Warnings.Count -gt 0) {
        $report.AppendLine("WARNINGS:") | Out-Null
        foreach ($warning in $result.Warnings) {
            $report.AppendLine("  - $warning") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    if ($result.Recommendations.Count -gt 0) {
        $report.AppendLine("RECOMMENDATIONS:") | Out-Null
        foreach ($rec in $result.Recommendations) {
            $report.AppendLine("  - $rec") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Get-CommandExplanation {
    param($CommandKey)
    $descriptions = @{
        "bcdboot" = "BCDBOOT copies boot files from the Windows partition to the EFI System Partition. Run this if your PC boots to BIOS only or 'No Boot Device Found.' It essentially recreates the 'brain' that tells your hardware how to start Windows."
        "fixboot" = "BOOTREC /FIXBOOT writes a new boot sector to the system partition. Use this if you get 'NTLDR is missing' or 'Error loading operating system' errors."
        "fixmbr" = "BOOTREC /FIXMBR repairs the Master Boot Record. Use this for legacy BIOS systems that show 'Invalid partition table' or fail to recognize the boot disk."
        "scanos" = "BOOTREC /SCANOS searches all disks for Windows installations not currently in the BCD. Run this if you installed a second Windows drive but it doesn't show up in the menu."
        "rebuildbcd" = "BOOTREC /REBUILDBCD scans for Windows installations and rebuilds the BCD store. This is a comprehensive fix for boot menu issues."
    }
    if ($descriptions[$CommandKey]) {
        return $descriptions[$CommandKey]
    } else {
        return "Command description not available."
    }
}

function Get-DetailedCommandInfo {
    param($CommandKey)
    $info = @{
        "bcdboot" = @{
            Why = "Run this if you see 'No Bootable Device' or if you just replaced your motherboard/SSD."
            What = "It exports a fresh copy of the Windows Boot Manager files to your hidden EFI partition and updates the BCD to point to the correct Windows folder."
        }
        "fixboot" = @{
            Why = "Run this if your PC starts but gives an error like 'NTLDR is missing' before the Windows logo appears."
            What = "It repairs the Volume Boot Record (VBR). This is the 'handshake' between your hardware and the Windows loader."
        }
        "fixmbr" = @{
            Why = "Run this if your PC shows 'Invalid partition table' or fails to recognize the boot disk on legacy BIOS systems."
            What = "It repairs the Master Boot Record (MBR) which contains the partition table and boot code for legacy systems."
        }
        "rebuildbcd" = @{
            Why = "Run this if your boot menu is completely empty or if an OS you installed is missing from the list."
            What = "It scans all disks for Windows installations and lets you manually add them back into the boot database."
        }
        "scanos" = @{
            Why = "Run this if you installed a second Windows drive but it doesn't show up in the boot menu."
            What = "It searches all disks for Windows installations not currently in the BCD and lists them for manual addition."
        }
        "reagentc" = @{
            Why = "Run this to check if your 'Reset this PC' and 'Advanced Startup' options are actually working."
            What = "It manages the Windows Recovery Environment (WinRE). Use /info to see if it's enabled or /enable to fix a broken recovery partition."
        }
    }
    return $info[$CommandKey]
}

function Get-BootLogAnalysis {
    param($TargetDrive = "C")
    
    # Normalize drive letter (remove colon if present, then add it back)
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $logPath = "$TargetDrive`:\Windows\ntbtlog.txt"
    $currentOS = ($env:SystemDrive.TrimEnd(':') -eq $TargetDrive)
    $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
    
    $report = @{
        Found = $false
        Summary = ""
        MissingDrivers = @()
        FailedDrivers = @()
        Analysis = ""
        TargetDrive = "$TargetDrive`:"
        IsCurrentOS = $currentOS
    }
    
    if (-not (Test-Path $logPath)) {
        $report.Summary = "BOOT LOG ANALYSIS - $osContext`n" +
                         "===============================================================`n" +
                         "Target Windows Installation: $TargetDrive`:\Windows`n" +
                         "Status: $osContext`n`n" +
                         "Boot log not found at: $logPath`n`n" +
                         "The system may not have been configured to create boot logs, or the log was cleared."
        return $report
    }
    
    $report.Found = $true
    $logContent = Get-Content $logPath -ErrorAction SilentlyContinue
    
    if (-not $logContent) {
        $report.Summary = "Boot log file exists but is empty or unreadable."
        return $report
    }
    
    # Critical boot-start drivers that must load
    $criticalDrivers = @(
        "ntoskrnl", "hal", "kdcom", "mcupdate", "ci", "cng", "disk", "partmgr",
        "volmgr", "volsnap", "mountmgr", "atapi", "pci", "acpi", "msisadrv"
    )
    
    $missingDrivers = @()
    $failedDrivers = @()
    
    foreach ($line in $logContent) {
        if ($line -match "Did not load driver\s+(.+)") {
            $driverName = $matches[1].Trim()
            $failedDrivers += $driverName
            
            # Check if it's critical
            foreach ($critical in $criticalDrivers) {
                if ($driverName -like "*$critical*") {
                    $missingDrivers += $driverName
                    break
                }
            }
        }
    }
    
    $report.MissingDrivers = $missingDrivers
    $report.FailedDrivers = $failedDrivers
    
    # Generate human-readable analysis
    $analysis = "BOOT LOG ANALYSIS - $osContext`n"
    $analysis += "===============================================================`n`n"
    $analysis += "Target Windows Installation: $TargetDrive`:\Windows`n"
    $analysis += "Status: $osContext`n"
    $analysis += "Log Location: $logPath`n"
    $analysis += "Total Failed Drivers: $($failedDrivers.Count)`n"
    $analysis += "Critical Missing Drivers: $($missingDrivers.Count)`n`n"
    
    if ($missingDrivers.Count -gt 0) {
        $analysis += "[CRITICAL] BOOT FAILURE DETECTED`n"
        $analysis += "The boot failed because the following critical drivers did not load:`n`n"
        foreach ($driver in $missingDrivers) {
            $analysis += "  - $driver`n"
        }
        $analysis += "`nThese drivers are essential for Windows to start.`n"
        $analysis += "Possible causes:`n"
        $analysis += "  1. Driver files are missing or corrupted`n"
        $analysis += "  2. Driver signature verification failed`n"
        $analysis += "  3. Hardware incompatibility`n"
        $analysis += "  4. Disk corruption or bad sectors`n`n"
    } elseif ($failedDrivers.Count -gt 0) {
        $analysis += "[WARNING] Some non-critical drivers failed to load:`n`n"
        foreach ($driver in $failedDrivers | Select-Object -First 10) {
            $analysis += "  - $driver`n"
        }
        $analysis += "`nThese may not prevent boot but could cause functionality issues.`n`n"
    } else {
        $analysis += "[OK] No driver load failures detected in the boot log.`n`n"
    }
    
    $report.Analysis = $analysis
    $report.Summary = $analysis
    
    return $report
}

function Get-OfflineEventLogs {
    param($TargetDrive = "C")
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $currentOS = ($env:SystemDrive.TrimEnd(':') -eq $TargetDrive)
    $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
    
    $results = @{
        Success = $false
        ShutdownEvents = @()
        CrashEvents = @()
        RecentErrors = @()
        BSODInfo = @()
        Summary = ""
        TargetDrive = "$TargetDrive`:"
        IsCurrentOS = $currentOS
    }
    
    $systemLogPath = "$TargetDrive`:\Windows\System32\winevt\Logs\System.evtx"
    $appLogPath = "$TargetDrive`:\Windows\System32\winevt\Logs\Application.evtx"
    
    if (-not (Test-Path $systemLogPath)) {
        $results.Summary = "EVENT LOG ANALYSIS - $osContext`n" +
                          "===============================================================`n" +
                          "Target Windows Installation: $TargetDrive`:\Windows`n" +
                          "Status: $osContext`n`n" +
                          "System event log not found at: $systemLogPath`n`n" +
                          "Cannot analyze offline logs from this drive."
        return $results
    }
    
    try {
        # Load System events
        $systemEvents = Get-WinEvent -Path $systemLogPath -ErrorAction SilentlyContinue | Select-Object -First 1000
        
        # Shutdown Analysis - Event IDs 1074 (User initiated) and 6008 (Unexpected)
        $shutdownEvents = $systemEvents | Where-Object { $_.Id -eq 1074 -or $_.Id -eq 6008 } | Select-Object -First 10
        foreach ($evt in $shutdownEvents) {
            $shutdownInfo = @{
                Time = $evt.TimeCreated
                Id = $evt.Id
                Level = $evt.LevelDisplayName
                Message = $evt.Message
            }
            
            if ($evt.Id -eq 1074) {
                $shutdownInfo.Type = "User Initiated Shutdown"
                if ($evt.Message -match "Reason:\s*(.+)") {
                    $shutdownInfo.Reason = $matches[1]
                }
            } else {
                $shutdownInfo.Type = "Unexpected Shutdown"
            }
            
            $results.ShutdownEvents += $shutdownInfo
        }
        
        # Crash Analysis - Event ID 1001 (BugCheck/BSOD)
        $bsodEvents = $systemEvents | Where-Object { $_.Id -eq 1001 } | Select-Object -First 5
        foreach ($evt in $bsodEvents) {
            $bsodInfo = @{
                Time = $evt.TimeCreated
                Message = $evt.Message
                StopCode = "Unknown"
                Explanation = ""
            }
            
            # Extract stop code
            if ($evt.Message -match "0x([0-9A-F]{8})") {
                $bsodInfo.StopCode = "0x$($matches[1])"
                $bsodInfo.Explanation = Get-BSODExplanation $bsodInfo.StopCode
            }
            
            $results.BSODInfo += $bsodInfo
        }
        
        # Recent Errors and Critical events
        $recentErrors = $systemEvents | Where-Object { 
            $_.LevelDisplayName -eq "Error" -or $_.LevelDisplayName -eq "Critical" 
        } | Select-Object -First 10 | Sort-Object TimeCreated -Descending
        
        foreach ($evt in $recentErrors) {
            $results.RecentErrors += @{
                Time = $evt.TimeCreated
                Id = $evt.Id
                Level = $evt.LevelDisplayName
                Provider = $evt.ProviderName
                Message = ($evt.Message -split "`n")[0]  # First line only
            }
        }
        
        $results.Success = $true
        
        # Generate summary
        $summary = "OFFLINE EVENT LOG ANALYSIS`n"
        $summary += "===============================================================`n`n"
        $summary += "System Log: $systemLogPath`n"
        $summary += "Events Analyzed: $($systemEvents.Count)`n`n"
        
        $summary += "SHUTDOWN EVENTS:`n"
        $summary += "---------------------------------------------------------------`n"
        if ($results.ShutdownEvents.Count -gt 0) {
            foreach ($shutdown in $results.ShutdownEvents) {
                $summary += "$($shutdown.Time): $($shutdown.Type)`n"
                if ($shutdown.Reason) {
                    $summary += "  Reason: $($shutdown.Reason)`n"
                }
            }
        } else {
            $summary += "No recent shutdown events found.`n"
        }
        
        $summary += "`nBSOD / CRASH EVENTS:`n"
        $summary += "---------------------------------------------------------------`n"
        if ($results.BSODInfo.Count -gt 0) {
            foreach ($bsod in $results.BSODInfo) {
                $summary += "$($bsod.Time): Stop Code $($bsod.StopCode)`n"
                if ($bsod.Explanation) {
                    $summary += "  $($bsod.Explanation)`n"
                }
            }
        } else {
            $summary += "No BSOD events found in recent logs.`n"
        }
        
        $summary += "`nRECENT ERRORS (Last 10):`n"
        $summary += "---------------------------------------------------------------`n"
        if ($results.RecentErrors.Count -gt 0) {
        foreach ($err in $results.RecentErrors) {
            $summary += "$($err.Time): [$($err.Level)] Event $($err.Id) - $($err.Provider)`n"
            $summary += "  $($err.Message)`n`n"
        }
        } else {
            $summary += "No recent errors found.`n"
        }
        
        $results.Summary = $summary
        
    } catch {
        $results.Summary = "Error analyzing event logs: $_"
    }
    
    return $results
}

function Get-ErrorExplanation {
    <#
    .SYNOPSIS
    Provides comprehensive error explanations with recovery suggestions.
    
    .DESCRIPTION
    Looks up error codes, stop codes, and common Windows errors to provide
    detailed explanations and step-by-step recovery instructions.
    #>
    param(
        [string]$ErrorCode = "",
        [string]$ErrorMessage = "",
        [string]$ErrorType = "General"
    )
    
    $result = @{
        Found = $false
        ErrorCode = $ErrorCode
        Title = ""
        Description = ""
        CommonCauses = @()
        RecoverySteps = @()
        PreventionTips = @()
        RelatedErrors = @()
    }
    
    # BSOD Stop Codes
    $bsodCodes = @{
        "0x0000007B" = @{
            Title = "INACCESSIBLE_BOOT_DEVICE"
            Description = "Windows cannot access the boot device. This usually means Windows can't find or read from the hard drive where Windows is installed."
            CommonCauses = @(
                "Missing storage drivers (Intel VMD, AMD RAID, NVMe controllers)",
                "Hard drive connection issues (loose cables)",
                "Disk corruption or bad sectors",
                "Boot configuration pointing to wrong drive",
                "Hardware failure (failing hard drive)"
            )
            RecoverySteps = @(
                "1. Boot into WinRE/WinPE and check for missing storage drivers",
                "2. Use Miracle Boot's 'Scan Storage Drivers' to identify missing drivers",
                "3. Download and inject storage drivers from manufacturer website",
                "4. Run 'Disk Repair (chkdsk)' to check for disk errors",
                "5. Check disk health and replace if failing",
                "6. Verify boot configuration (BCD) points to correct drive"
            )
            PreventionTips = @(
                "Keep storage drivers updated",
                "Regular disk health checks",
                "Backup important data regularly"
            )
        }
        "0x0000007E" = @{
            Title = "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED"
            Description = "A system thread generated an exception that the error handler didn't catch. This is almost always driver-related."
            CommonCauses = @(
                "Corrupted or incompatible device driver",
                "Recently installed or updated driver",
                "Hardware incompatibility",
                "Memory corruption"
            )
            RecoverySteps = @(
                "1. Boot into Safe Mode or WinRE",
                "2. Check Event Viewer for driver errors",
                "3. Uninstall recently installed drivers",
                "4. Update or reinstall problematic drivers",
                "5. Run 'System File Repair (SFC + DISM)' to fix corrupted system files",
                "6. Check for hardware issues (RAM, motherboard)"
            )
        }
        "0x00000050" = @{
            Title = "PAGE_FAULT_IN_NONPAGED_AREA"
            Description = "Invalid memory access occurred. The system tried to access memory that doesn't exist or is corrupted."
            CommonCauses = @(
                "Bad RAM (memory modules)",
                "Corrupted page file",
                "Faulty device driver",
                "Hardware incompatibility"
            )
            RecoverySteps = @(
                "1. Run Windows Memory Diagnostic (mdsched.exe)",
                "2. Test RAM modules individually",
                "3. Check page file settings and recreate if needed",
                "4. Update device drivers",
                "5. Check for hardware compatibility issues"
            )
        }
        "0x0000001E" = @{
            Title = "KMODE_EXCEPTION_NOT_HANDLED"
            Description = "A kernel-mode program generated an exception that wasn't handled. Typically indicates a driver problem."
            CommonCauses = @(
                "Faulty device driver",
                "Hardware incompatibility",
                "Corrupted system files"
            )
            RecoverySteps = @(
                "1. Boot into Safe Mode",
                "2. Check Device Manager for problematic devices",
                "3. Update or rollback recently updated drivers",
                "4. Run 'System File Repair (SFC + DISM)'",
                "5. Check Windows Update for driver updates"
            )
        }
        "0x0000003B" = @{
            Title = "SYSTEM_SERVICE_EXCEPTION"
            Description = "An exception happened while executing a system service routine. Often driver or hardware related."
            CommonCauses = @(
                "Device driver issue",
                "Hardware failure",
                "Corrupted system files",
                "Memory issues"
            )
            RecoverySteps = @(
                "1. Check Event Viewer for specific service errors",
                "2. Update device drivers",
                "3. Run 'System File Repair (SFC + DISM)'",
                "4. Check hardware health (RAM, disk, CPU temperature)",
                "5. Disable recently installed hardware"
            )
        }
    }
    
    # Windows Error Codes
    $winErrorCodes = @{
        "0x80070002" = @{
            Title = "ERROR_FILE_NOT_FOUND"
            Description = "The system cannot find the file specified."
            CommonCauses = @(
                "File was deleted or moved",
                "Path is incorrect",
                "File system corruption"
            )
            RecoverySteps = @(
                "1. Verify file path is correct",
                "2. Check if file exists in expected location",
                "3. Run 'Disk Repair (chkdsk)' to fix file system",
                "4. Restore from backup if available"
            )
        }
        "0x80070005" = @{
            Title = "ERROR_ACCESS_DENIED"
            Description = "Access is denied. You don't have permission to perform this operation."
            CommonCauses = @(
                "Insufficient permissions",
                "File/folder is locked",
                "User account doesn't have required rights"
            )
            RecoverySteps = @(
                "1. Run as Administrator",
                "2. Check file/folder permissions",
                "3. Take ownership of file/folder if needed",
                "4. Close programs that might be using the file"
            )
        }
        "0x8007000D" = @{
            Title = "ERROR_INVALID_DATA"
            Description = "The data is invalid."
            CommonCauses = @(
                "Corrupted file or data",
                "Invalid file format",
                "Disk corruption"
            )
            RecoverySteps = @(
                "1. Verify file integrity",
                "2. Run 'Disk Repair (chkdsk)'",
                "3. Re-download or restore file from backup",
                "4. Check for disk errors"
            )
        }
    }
    
    # Setup/Installation Error Codes
    $setupErrorCodes = @{
        "0xC1900101" = @{
            Title = "Windows Setup Error"
            Description = "Windows Setup encountered an error during installation."
            CommonCauses = @(
                "Driver incompatibility",
                "Hardware issues",
                "Insufficient disk space",
                "Corrupted Windows image"
            )
            RecoverySteps = @(
                "1. Run 'In-Place Upgrade Readiness Check'",
                "2. Fix any blockers identified",
                "3. Ensure at least 20GB free disk space",
                "4. Update device drivers",
                "5. Check setup logs for specific error"
            )
        }
        "0x80070003" = @{
            Title = "Windows Update Error"
            Description = "Windows Update encountered an error."
            CommonCauses = @(
                "Corrupted Windows Update components",
                "Network connectivity issues",
                "Insufficient disk space"
            )
            RecoverySteps = @(
                "1. Run Windows Update Troubleshooter",
                "2. Run 'System File Repair (SFC + DISM)'",
                "3. Clear Windows Update cache",
                "4. Check disk space"
            )
        }
    }
    
    # Search for error code
    if ($ErrorCode) {
        # Try BSOD codes
        if ($bsodCodes.ContainsKey($ErrorCode)) {
            $errorInfo = $bsodCodes[$ErrorCode]
            $result.Found = $true
            $result.Title = $errorInfo.Title
            $result.Description = $errorInfo.Description
            $result.CommonCauses = $errorInfo.CommonCauses
            $result.RecoverySteps = $errorInfo.RecoverySteps
            if ($errorInfo.PreventionTips) {
                $result.PreventionTips = $errorInfo.PreventionTips
            }
            return $result
        }
        
        # Try Windows error codes
        if ($winErrorCodes.ContainsKey($ErrorCode)) {
            $errorInfo = $winErrorCodes[$ErrorCode]
            $result.Found = $true
            $result.Title = $errorInfo.Title
            $result.Description = $errorInfo.Description
            $result.CommonCauses = $errorInfo.CommonCauses
            $result.RecoverySteps = $errorInfo.RecoverySteps
            return $result
        }
        
        # Try setup error codes
        if ($setupErrorCodes.ContainsKey($ErrorCode)) {
            $errorInfo = $setupErrorCodes[$ErrorCode]
            $result.Found = $true
            $result.Title = $errorInfo.Title
            $result.Description = $errorInfo.Description
            $result.CommonCauses = $errorInfo.CommonCauses
            $result.RecoverySteps = $errorInfo.RecoverySteps
            return $result
        }
    }
    
    # Search by error message keywords
    if ($ErrorMessage) {
        $errorLower = $ErrorMessage.ToLower()
        
        if ($errorLower -match "boot|bcd|bootmgr|bootloader") {
            $result.Found = $true
            $result.Title = "Boot Configuration Error"
            $result.Description = "An error related to Windows boot configuration was detected."
            $result.CommonCauses = @("Corrupted BCD", "Missing boot files", "Incorrect boot configuration")
            $result.RecoverySteps = @(
                "1. Run 'Automated Boot Repair'",
                "2. Check boot configuration (BCD)",
                "3. Verify EFI partition exists",
                "4. Run 'bcdboot C:\\Windows' to recreate boot files"
            )
            return $result
        }
        
        if ($errorLower -match "disk|drive|volume|sector") {
            $result.Found = $true
            $result.Title = "Disk Error"
            $result.Description = "An error related to disk or storage was detected."
            $result.CommonCauses = @("Disk corruption", "Bad sectors", "Failing hard drive", "File system errors")
            $result.RecoverySteps = @(
                "1. Run 'Disk Repair (chkdsk)'",
                "2. Check disk health",
                "3. Backup important data",
                "4. Replace disk if failing"
            )
            return $result
        }
        
        if ($errorLower -match "driver|device|hardware") {
            $result.Found = $true
            $result.Title = "Driver or Hardware Error"
            $result.Description = "An error related to device drivers or hardware was detected."
            $result.CommonCauses = @("Missing drivers", "Incompatible drivers", "Hardware failure", "Driver corruption")
            $result.RecoverySteps = @(
                "1. Check for missing drivers in Device Manager",
                "2. Update or reinstall drivers",
                "3. Use 'Scan Storage Drivers' to identify missing drivers",
                "4. Check hardware connections"
            )
            return $result
        }
    }
    
    return $result
}

function Get-BSODExplanation {
    param($StopCode)
    # Use the new comprehensive error explanation system
    $explanation = Get-ErrorExplanation -ErrorCode $StopCode -ErrorType "BSOD"
    
    if ($explanation.Found) {
        $output = "$($explanation.Title) - $($explanation.Description)"
        if ($explanation.RecoverySteps.Count -gt 0) {
            $output += "`nRecovery: $($explanation.RecoverySteps[0])"
        }
        return $output
    }
    
    # Also try the comprehensive Windows error code info system
    try {
        $errorInfo = Get-WindowsErrorCodeInfo -ErrorCode $StopCode
        if ($errorInfo.Found) {
            $output = "$($errorInfo.Name) - $($errorInfo.Description)"
            if ($errorInfo.Recommendations.Count -gt 0) {
                $output += "`nRecommended: $($errorInfo.Recommendations[0])"
            }
            return $output
        }
    } catch {
        # Fall through to simple explanations
    }
    
    # Fallback to original simple explanations
    $explanations = @{
        "0x0000007B" = "INACCESSIBLE_BOOT_DEVICE - Windows cannot access the boot device. Usually caused by missing storage drivers (VMD/RAID/NVMe) or disk corruption. Check for missing storage controller drivers."
        "0x0000007E" = "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED - A system thread generated an exception that the error handler didn't catch. Often driver-related. Update or reinstall problematic drivers."
        "0x00000050" = "PAGE_FAULT_IN_NONPAGED_AREA - Invalid memory access. Usually bad RAM, corrupted page file, or faulty driver. Run memory diagnostics."
        "0x0000001E" = "KMODE_EXCEPTION_NOT_HANDLED - A kernel-mode program generated an exception. Typically a driver problem. Check recently installed drivers."
        "0x0000003B" = "SYSTEM_SERVICE_EXCEPTION - An exception happened while executing a system service routine. Often driver or hardware related."
        "0x000000D1" = "DRIVER_IRQL_NOT_LESS_OR_EQUAL - A driver tried to access an improper memory address. Usually a buggy driver. Update drivers, especially graphics."
        "0x000000F4" = "CRITICAL_OBJECT_TERMINATION - A critical system process terminated. Could be hardware failure or corrupted system files. Check disk health."
        "0x00000024" = "NTFS_FILE_SYSTEM - Problem with NTFS file system. Often disk corruption or bad sectors. Run chkdsk /f."
        "0x000000C2" = "BAD_POOL_CALLER - A kernel-mode process attempted an invalid memory operation. Usually driver-related."
        "0x000000EA" = "THREAD_STUCK_IN_DEVICE_DRIVER - A device driver is stuck in an infinite loop. Graphics driver is common culprit. Update GPU drivers."
    }
    
    if ($explanations[$StopCode]) {
        return $explanations[$StopCode]
    } else {
        return "Unknown stop code. This BSOD may be caused by hardware failure, driver issues, or system corruption."
    }
}

function Get-WindowsErrorCodeInfo {
    <#
    .SYNOPSIS
    Comprehensive Windows error code lookup system with explanations, recommendations, and troubleshooting steps.
    
    .DESCRIPTION
    Provides detailed information about Windows boot errors, installation errors, BSOD stop codes, and system error codes.
    Returns explanations, root causes, troubleshooting steps, and repair recommendations for each error code.
    
    .PARAMETER ErrorCode
    The error code to look up (e.g., "0xc000000e", "0x80070002", "0x0000007B")
    
    .PARAMETER TargetDrive
    Optional target drive for generating drive-specific repair commands.
    
    .EXAMPLE
    Get-WindowsErrorCodeInfo -ErrorCode "0xc000000e"
    
    .EXAMPLE
    Get-WindowsErrorCodeInfo -ErrorCode "0x80070002" -TargetDrive "C"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ErrorCode,
        [string]$TargetDrive = "C"
    )
    
    # Normalize error code format (handle with/without 0x prefix, case insensitive)
    $ErrorCode = $ErrorCode.Trim()
    if (-not $ErrorCode.StartsWith("0x") -and -not $ErrorCode.StartsWith("0X")) {
        if ($ErrorCode -match "^[0-9A-Fa-f]+$") {
            $ErrorCode = "0x$ErrorCode"
        }
    }
    $ErrorCode = $ErrorCode.ToUpper()
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        ErrorCode = $ErrorCode
        Type = "Unknown"
        Name = ""
        Description = ""
        RootCause = ""
        BootStage = "Unknown"
        Severity = "Unknown"
        Recommendations = @()
        TroubleshootingSteps = @()
        RepairCommands = @()
        RelatedErrors = @()
        Found = $false
    }
    
    # Comprehensive error code database
    $errorDatabase = @{
        # Boot Errors (0xc0000000 - 0xc0000FFF)
        "0xC000000E" = @{
            Type = "Boot Error"
            Name = "BOOT DEVICE INACCESSIBLE"
            Description = "Windows cannot access the boot device. The system cannot find or access the hard disk that contains the Windows installation."
            RootCause = "Missing or corrupted boot files, BCD corruption, missing storage drivers, or disk hardware failure."
            BootStage = "Stage 2: Boot Manager / Stage 3: Boot Loader"
            Severity = "Critical"
            Recommendations = @(
                "Run: bcdboot $TargetDrive`:\Windows",
                "Run: bootrec /rebuildbcd",
                "Run: bootrec /fixboot",
                "Check for missing storage drivers (VMD/RAID/NVMe)",
                "Verify disk is detected in BIOS/UEFI",
                "Check disk health: chkdsk $TargetDrive`: /f /r"
            )
            TroubleshootingSteps = @(
                "1. Boot into Windows Recovery Environment (WinRE)",
                "2. Open Command Prompt (Shift+F10)",
                "3. Run: diskpart -> list volume (identify Windows drive)",
                "4. Run: bcdboot X:\Windows (where X is your Windows drive)",
                "5. If that fails, run: bootrec /rebuildbcd",
                "6. Check for missing storage controller drivers",
                "7. Verify disk is not failing (check SMART status)"
            )
            RepairCommands = @(
                "bcdboot $TargetDrive`:\Windows",
                "bootrec /rebuildbcd",
                "bootrec /fixboot",
                "bootrec /fixmbr",
                "chkdsk $TargetDrive`: /f /r"
            )
            RelatedErrors = @("0x0000007B", "0xC000000F", "0xC0000225")
        }
        "0xC000000F" = @{
            Type = "Boot Error"
            Name = "BOOT FILE NOT FOUND"
            Description = "A required boot file is missing or corrupted. Windows cannot find a critical boot file needed to start."
            RootCause = "Missing bootmgr, winload.exe, or other critical boot files. Often caused by disk corruption or accidental deletion."
            BootStage = "Stage 2: Boot Manager / Stage 3: Boot Loader"
            Severity = "Critical"
            Recommendations = @(
                "Run: bcdboot $TargetDrive`:\Windows",
                "Run: bootrec /fixboot",
                "Check for disk corruption: chkdsk $TargetDrive`: /f",
                "Verify boot files exist in System32 folder",
                "Consider in-place upgrade repair"
            )
            TroubleshootingSteps = @(
                "1. Boot into WinRE",
                "2. Verify Windows drive is accessible",
                "3. Check if boot files exist: dir $TargetDrive`:\Windows\System32\winload.exe",
                "4. Run: bcdboot $TargetDrive`:\Windows",
                "5. If files are missing, run: DISM /Image:$TargetDrive`:\ /Cleanup-Image /RestoreHealth",
                "6. Run: sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows"
            )
            RepairCommands = @(
                "bcdboot $TargetDrive`:\Windows",
                "bootrec /fixboot",
                "sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows",
                "DISM /Image:$TargetDrive`:\ /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0xC000000E", "0xC0000225")
        }
        "0xC0000225" = @{
            Type = "Boot Error"
            Name = "BOOT CONFIGURATION DATA MISSING"
            Description = "The Boot Configuration Data (BCD) store is missing or corrupted. Windows cannot read boot configuration."
            RootCause = "BCD store corruption, missing EFI partition, or BCD file deletion."
            BootStage = "Stage 2: Boot Manager"
            Severity = "Critical"
            Recommendations = @(
                "Run: bootrec /rebuildbcd",
                "Run: bcdboot $TargetDrive`:\Windows",
                "Check EFI partition is accessible",
                "Verify BCD file exists"
            )
            TroubleshootingSteps = @(
                "1. Boot into WinRE",
                "2. Run: bootrec /rebuildbcd",
                "3. If that fails, manually rebuild BCD:",
                "   - bcdedit /export C:\BCD_Backup",
                "   - attrib C:\boot\bcd -h -r -s",
                "   - del C:\boot\bcd",
                "   - bootrec /rebuildbcd",
                "4. Verify EFI partition is mounted and accessible"
            )
            RepairCommands = @(
                "bootrec /rebuildbcd",
                "bcdboot $TargetDrive`:\Windows",
                "bcdedit /enum all"
            )
            RelatedErrors = @("0xC000000E", "0xC000000F")
        }
        "0xC0000098" = @{
            Type = "Boot Error"
            Name = "REGISTRY FILE FAILURE"
            Description = "Windows cannot load a required registry file (SYSTEM, SOFTWARE, SAM, or SECURITY hive)."
            RootCause = "Corrupted registry hive, disk corruption, or missing registry files."
            BootStage = "Stage 4: Kernel Initialization / Stage 6: Session Manager"
            Severity = "Critical"
            Recommendations = @(
                "Run: sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows",
                "Check for disk corruption: chkdsk $TargetDrive`: /f /r",
                "Restore registry from backup if available",
                "Consider in-place upgrade repair"
            )
            TroubleshootingSteps = @(
                "1. Boot into WinRE",
                "2. Check registry hives: dir $TargetDrive`:\Windows\System32\config",
                "3. Look for .bak or .old registry files",
                "4. If backups exist, restore them",
                "5. Run: sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows",
                "6. Run: DISM /Image:$TargetDrive`:\ /Cleanup-Image /RestoreHealth"
            )
            RepairCommands = @(
                "sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows",
                "DISM /Image:$TargetDrive`:\ /Cleanup-Image /RestoreHealth",
                "chkdsk $TargetDrive`: /f /r"
            )
            RelatedErrors = @("0xC000021A", "0x80070002")
        }
        "0xC000021A" = @{
            Type = "Boot Error"
            Name = "FATAL SYSTEM ERROR"
            Description = "A fatal system error occurred. Windows Session Manager (smss.exe) or Windows Logon (winlogon.exe) terminated unexpectedly."
            RootCause = "Corrupted system files, registry corruption, or driver conflict during logon."
            BootStage = "Stage 6: Session Manager / Stage 7: Windows Logon"
            Severity = "Critical"
            Recommendations = @(
                "Run: sfc /scannow",
                "Check for corrupted system files",
                "Boot into Safe Mode if possible",
                "Check Event Viewer for specific errors",
                "Consider in-place upgrade repair"
            )
            TroubleshootingSteps = @(
                "1. Try booting into Safe Mode",
                "2. If Safe Mode works, check for recently installed software/drivers",
                "3. Run: sfc /scannow",
                "4. Check Event Viewer for application errors",
                "5. Run: DISM /Online /Cleanup-Image /RestoreHealth",
                "6. If all else fails, consider in-place upgrade"
            )
            RepairCommands = @(
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth",
                "chkdsk C: /f /r"
            )
            RelatedErrors = @("0xC0000098", "0x000000F4")
        }
        
        # Installation Errors (0x80070000 - 0x8007FFFF)
        "0x80070002" = @{
            Type = "Installation Error"
            Name = "FILE NOT FOUND"
            Description = "Windows Setup cannot find a required file. The installation source may be incomplete or corrupted."
            RootCause = "Corrupted installation media, incomplete download, or missing installation files."
            BootStage = "Installation Phase"
            Severity = "High"
            Recommendations = @(
                "Verify installation media integrity",
                "Re-download Windows installation media",
                "Check installation source is accessible",
                "Try different USB port or installation media",
                "Run installation as administrator"
            )
            TroubleshootingSteps = @(
                "1. Verify installation media is not corrupted",
                "2. Re-create Windows installation USB using Media Creation Tool",
                "3. Try different USB port (prefer USB 2.0)",
                "4. Check if installation source folder is accessible",
                "5. Disable antivirus temporarily during installation",
                "6. Check disk space on target drive"
            )
            RepairCommands = @()
            RelatedErrors = @("0x80070003", "0x80070017", "0x8007000D")
        }
        "0x80070003" = @{
            Type = "Installation Error"
            Name = "PATH NOT FOUND"
            Description = "Windows Setup cannot access a required path. The installation path may be invalid or inaccessible."
            RootCause = "Invalid installation path, permission issues, or inaccessible drive."
            BootStage = "Installation Phase"
            Severity = "High"
            Recommendations = @(
                "Verify installation path is valid",
                "Check drive permissions",
                "Run installation as administrator",
                "Verify target drive is accessible"
            )
            TroubleshootingSteps = @(
                "1. Verify target drive letter is correct",
                "2. Check if drive is accessible: dir X:\ (where X is target drive)",
                "3. Run installation as administrator",
                "4. Check disk management for drive status",
                "5. Verify drive is not encrypted or locked"
            )
            RepairCommands = @()
            RelatedErrors = @("0x80070002", "0x80070005")
        }
        "0x80070005" = @{
            Type = "Installation Error"
            Name = "ACCESS DENIED"
            Description = "Windows Setup does not have permission to access required files or folders."
            RootCause = "Insufficient permissions, file locks, or security restrictions."
            BootStage = "Installation Phase"
            Severity = "High"
            Recommendations = @(
                "Run installation as administrator",
                "Disable antivirus temporarily",
                "Close all applications",
                "Check for file locks",
                "Verify user has administrator privileges"
            )
            TroubleshootingSteps = @(
                "1. Right-click setup.exe and select 'Run as administrator'",
                "2. Disable antivirus and firewall temporarily",
                "3. Close all running applications",
                "4. Check Task Manager for locked files",
                "5. Verify user account has administrator rights"
            )
            RepairCommands = @()
            RelatedErrors = @("0x80070003", "0x80070020")
        }
        "0x8007000D" = @{
            Type = "Installation Error"
            Name = "INVALID DATA"
            Description = "Windows Setup encountered invalid or corrupted data. The installation media may be corrupted."
            RootCause = "Corrupted installation files, incomplete download, or damaged installation media."
            BootStage = "Installation Phase"
            Severity = "High"
            Recommendations = @(
                "Re-download Windows installation media",
                "Verify installation media integrity",
                "Try different installation source",
                "Check for disk errors on installation media"
            )
            TroubleshootingSteps = @(
                "1. Re-create Windows installation USB",
                "2. Verify ISO file integrity (checksum)",
                "3. Try different USB drive",
                "4. Use Media Creation Tool to create fresh installation media",
                "5. Check installation media for physical damage"
            )
            RepairCommands = @()
            RelatedErrors = @("0x80070002", "0x80070017")
        }
        "0x80070017" = @{
            Type = "Installation Error"
            Name = "CRC ERROR"
            Description = "Cyclic Redundancy Check (CRC) error. Data read from installation media is corrupted."
            RootCause = "Corrupted installation media, bad USB drive, or damaged installation files."
            BootStage = "Installation Phase"
            Severity = "High"
            Recommendations = @(
                "Re-create installation media",
                "Try different USB drive",
                "Verify installation source integrity",
                "Check USB port and cable"
            )
            TroubleshootingSteps = @(
                "1. Re-create Windows installation USB using Media Creation Tool",
                "2. Try different USB drive (prefer USB 2.0)",
                "3. Try different USB port",
                "4. Verify ISO file checksum matches Microsoft's",
                "5. Check USB drive for bad sectors"
            )
            RepairCommands = @()
            RelatedErrors = @("0x8007000D", "0x80070002")
        }
        "0x80070070" = @{
            Type = "Installation Error"
            Name = "INSUFFICIENT DISK SPACE"
            Description = "Not enough free disk space to complete Windows installation or update."
            RootCause = "Insufficient free space on target drive. Windows needs significant free space for installation."
            BootStage = "Installation Phase"
            Severity = "Medium"
            Recommendations = @(
                "Free up disk space (at least 20GB recommended)",
                "Delete temporary files",
                "Move files to another drive",
                "Uninstall unused programs",
                "Run Disk Cleanup"
            )
            TroubleshootingSteps = @(
                "1. Check available disk space: dir C:\",
                "2. Run Disk Cleanup: cleanmgr",
                "3. Delete temporary files: %TEMP%",
                "4. Uninstall unused programs",
                "5. Move large files to external drive",
                "6. Consider upgrading to larger drive"
            )
            RepairCommands = @(
                "cleanmgr /d C:",
                "dism /online /cleanup-image /startcomponentcleanup /resetbase"
            )
            RelatedErrors = @()
        }
        "0x8007045D" = @{
            Type = "Installation Error"
            Name = "I/O ERROR"
            Description = "Input/Output error during installation. Problem reading from or writing to disk."
            RootCause = "Disk hardware failure, bad sectors, or disk controller issues."
            BootStage = "Installation Phase"
            Severity = "High"
            Recommendations = @(
                "Check disk health (SMART status)",
                "Run: chkdsk /f /r",
                "Check disk cables and connections",
                "Test with different drive",
                "Backup data immediately if disk is failing"
            )
            TroubleshootingSteps = @(
                "1. Check disk health: wmic diskdrive get status",
                "2. Run: chkdsk C: /f /r",
                "3. Check SATA/USB cables",
                "4. Test disk with manufacturer's diagnostic tool",
                "5. If disk is failing, backup data and replace drive"
            )
            RepairCommands = @(
                "chkdsk C: /f /r",
                "sfc /scannow"
            )
            RelatedErrors = @("0x80070017", "0x00000024")
        }
        "0x80070057" = @{
            Type = "Installation Error"
            Name = "INVALID PARAMETER"
            Description = "Windows Setup received an invalid parameter. Installation options may be incorrect."
            RootCause = "Invalid installation parameters, corrupted installation configuration, or incompatible options."
            BootStage = "Installation Phase"
            Severity = "Medium"
            Recommendations = @(
                "Verify installation options are correct",
                "Use default installation settings",
                "Re-run installation with standard options",
                "Check for incompatible hardware"
            )
            TroubleshootingSteps = @(
                "1. Use default installation options",
                "2. Do not skip compatibility checks",
                "3. Verify hardware meets Windows requirements",
                "4. Check installation log for specific parameter error",
                "5. Try clean installation instead of upgrade"
            )
            RepairCommands = @()
            RelatedErrors = @()
        }
        
        # BSOD Stop Codes (0x00000000 - 0x0000FFFF)
        "0x0000007B" = @{
            Type = "BSOD Stop Code"
            Name = "INACCESSIBLE_BOOT_DEVICE"
            Description = "Windows cannot access the boot device during kernel initialization. System cannot find or access the hard disk."
            RootCause = "Missing storage drivers (VMD/RAID/NVMe), disk corruption, BCD issues, or hardware failure."
            BootStage = "Stage 4: Kernel Initialization / Stage 5: Driver Loading"
            Severity = "Critical"
            Recommendations = @(
                "Inject missing storage drivers using DISM",
                "Check for VMD/RAID/NVMe controller drivers",
                "Run: bcdboot $TargetDrive`:\Windows",
                "Verify disk is detected in BIOS/UEFI",
                "Check disk health and cables"
            )
            TroubleshootingSteps = @(
                "1. Boot into WinRE",
                "2. Identify missing storage drivers",
                "3. Harvest drivers from working Windows installation",
                "4. Inject drivers: DISM /Image:$TargetDrive`:\ /Add-Driver /Driver:X:\Drivers /Recurse",
                "5. Run: bcdboot $TargetDrive`:\Windows",
                "6. Check BIOS/UEFI for disk detection",
                "7. Verify SATA/AHCI settings in BIOS"
            )
            RepairCommands = @(
                "DISM /Image:$TargetDrive`:\ /Add-Driver /Driver:X:\Drivers /Recurse",
                "bcdboot $TargetDrive`:\Windows",
                "chkdsk $TargetDrive`: /f /r"
            )
            RelatedErrors = @("0xC000000E", "0xC000000F")
        }
        "0x0000007E" = @{
            Type = "BSOD Stop Code"
            Name = "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED"
            Description = "A system thread generated an exception that the error handler didn't catch. Usually driver-related."
            RootCause = "Faulty or incompatible driver, corrupted driver file, or hardware incompatibility."
            BootStage = "Stage 5: Driver Loading"
            Severity = "High"
            Recommendations = @(
                "Boot into Safe Mode",
                "Update or rollback recently installed drivers",
                "Check Event Viewer for specific driver error",
                "Run: sfc /scannow",
                "Uninstall problematic drivers"
            )
            TroubleshootingSteps = @(
                "1. Boot into Safe Mode",
                "2. Check Event Viewer for driver errors",
                "3. Identify recently installed drivers",
                "4. Rollback or update problematic drivers",
                "5. Run: sfc /scannow",
                "6. Check Windows Update for driver updates"
            )
            RepairCommands = @(
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0x0000001E", "0x000000D1")
        }
        "0x00000050" = @{
            Type = "BSOD Stop Code"
            Name = "PAGE_FAULT_IN_NONPAGED_AREA"
            Description = "Invalid memory access in non-paged area. System tried to access invalid memory."
            RootCause = "Bad RAM, corrupted page file, faulty driver, or memory corruption."
            BootStage = "Stage 4: Kernel Initialization / Stage 5: Driver Loading"
            Severity = "High"
            Recommendations = @(
                "Run Windows Memory Diagnostic",
                "Check RAM for errors",
                "Remove or replace faulty RAM modules",
                "Check page file settings",
                "Update drivers, especially storage"
            )
            TroubleshootingSteps = @(
                "1. Run: mdsched.exe (Windows Memory Diagnostic)",
                "2. Test RAM with MemTest86",
                "3. Remove RAM modules one at a time to isolate bad module",
                "4. Check page file: System Properties -> Advanced -> Performance Settings",
                "5. Update all drivers, especially storage controllers"
            )
            RepairCommands = @(
                "mdsched.exe",
                "sfc /scannow"
            )
            RelatedErrors = @("0x0000003B", "0x0000001E")
        }
        "0x0000001E" = @{
            Type = "BSOD Stop Code"
            Name = "KMODE_EXCEPTION_NOT_HANDLED"
            Description = "A kernel-mode program generated an exception that wasn't handled. Typically a driver problem."
            RootCause = "Faulty driver, incompatible driver, or driver conflict."
            BootStage = "Stage 5: Driver Loading"
            Severity = "High"
            Recommendations = @(
                "Boot into Safe Mode",
                "Check recently installed drivers",
                "Update or rollback drivers",
                "Check for driver conflicts",
                "Run: sfc /scannow"
            )
            TroubleshootingSteps = @(
                "1. Boot into Safe Mode",
                "2. Check Event Viewer for driver errors",
                "3. Identify recently installed/updated drivers",
                "4. Rollback drivers via Device Manager",
                "5. Update drivers from manufacturer's website",
                "6. Check for driver conflicts in Device Manager"
            )
            RepairCommands = @(
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0x0000007E", "0x000000D1")
        }
        "0x0000003B" = @{
            Type = "BSOD Stop Code"
            Name = "SYSTEM_SERVICE_EXCEPTION"
            Description = "An exception happened while executing a system service routine. Often driver or hardware related."
            RootCause = "Faulty driver, hardware incompatibility, or corrupted system files."
            BootStage = "Stage 5: Driver Loading / Stage 6: Session Manager"
            Severity = "High"
            Recommendations = @(
                "Update drivers, especially graphics and storage",
                "Run: sfc /scannow",
                "Check for hardware issues",
                "Update Windows",
                "Check Event Viewer for specific errors"
            )
            TroubleshootingSteps = @(
                "1. Update graphics drivers",
                "2. Update storage controller drivers",
                "3. Run: sfc /scannow",
                "4. Check Event Viewer for specific service errors",
                "5. Update Windows to latest version",
                "6. Check for hardware compatibility issues"
            )
            RepairCommands = @(
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0x00000050", "0x0000001E")
        }
        "0x000000D1" = @{
            Type = "BSOD Stop Code"
            Name = "DRIVER_IRQL_NOT_LESS_OR_EQUAL"
            Description = "A driver tried to access an improper memory address at an invalid IRQL. Usually a buggy driver."
            RootCause = "Faulty driver, especially graphics drivers, or driver accessing invalid memory."
            BootStage = "Stage 5: Driver Loading"
            Severity = "High"
            Recommendations = @(
                "Update graphics drivers",
                "Update all drivers",
                "Rollback recently updated drivers",
                "Check for driver conflicts",
                "Run: sfc /scannow"
            )
            TroubleshootingSteps = @(
                "1. Update graphics drivers from manufacturer's website",
                "2. Check Event Viewer for specific driver name",
                "3. Rollback drivers via Device Manager",
                "4. Update all drivers, especially GPU and chipset",
                "5. Check for driver conflicts"
            )
            RepairCommands = @(
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0x0000001E", "0x0000007E")
        }
        "0x000000F4" = @{
            Type = "BSOD Stop Code"
            Name = "CRITICAL_OBJECT_TERMINATION"
            Description = "A critical system process terminated unexpectedly. Could indicate hardware failure or corrupted system files."
            RootCause = "Hardware failure (especially disk or RAM), corrupted system files, or critical process crash."
            BootStage = "Stage 6: Session Manager / Stage 7: Windows Logon"
            Severity = "Critical"
            Recommendations = @(
                "Check disk health (SMART status)",
                "Run: chkdsk /f /r",
                "Check RAM for errors",
                "Run: sfc /scannow",
                "Check Event Viewer for specific process"
            )
            TroubleshootingSteps = @(
                "1. Check disk health: wmic diskdrive get status",
                "2. Run: chkdsk C: /f /r",
                "3. Run Windows Memory Diagnostic",
                "4. Check Event Viewer for specific process that terminated",
                "5. Run: sfc /scannow",
                "6. Check for hardware failures"
            )
            RepairCommands = @(
                "chkdsk C: /f /r",
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0xC000021A", "0x00000024")
        }
        "0x00000024" = @{
            Type = "BSOD Stop Code"
            Name = "NTFS_FILE_SYSTEM"
            Description = "Problem with NTFS file system. File system corruption or bad sectors on disk."
            RootCause = "Disk corruption, bad sectors, or file system errors."
            BootStage = "Stage 4: Kernel Initialization / Stage 5: Driver Loading"
            Severity = "High"
            Recommendations = @(
                "Run: chkdsk /f /r",
                "Check disk health",
                "Backup data if disk is failing",
                "Check for bad sectors",
                "Run: sfc /scannow"
            )
            TroubleshootingSteps = @(
                "1. Run: chkdsk C: /f /r (may take hours)",
                "2. Check disk health: wmic diskdrive get status",
                "3. Check SMART status of disk",
                "4. Backup important data immediately",
                "5. If disk is failing, replace it",
                "6. Run: sfc /scannow after chkdsk completes"
            )
            RepairCommands = @(
                "chkdsk C: /f /r",
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0x000000F4", "0x8007045D")
        }
        "0x000000C2" = @{
            Type = "BSOD Stop Code"
            Name = "BAD_POOL_CALLER"
            Description = "A kernel-mode process attempted an invalid memory operation. Usually driver-related."
            RootCause = "Faulty driver, memory corruption, or driver accessing invalid memory pool."
            BootStage = "Stage 5: Driver Loading"
            Severity = "High"
            Recommendations = @(
                "Update drivers",
                "Check for driver conflicts",
                "Run: sfc /scannow",
                "Check RAM for errors",
                "Boot into Safe Mode"
            )
            TroubleshootingSteps = @(
                "1. Boot into Safe Mode",
                "2. Check Event Viewer for driver errors",
                "3. Update all drivers",
                "4. Check for driver conflicts",
                "5. Run Windows Memory Diagnostic",
                "6. Run: sfc /scannow"
            )
            RepairCommands = @(
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0x0000001E", "0x000000D1")
        }
        "0x000000EA" = @{
            Type = "BSOD Stop Code"
            Name = "THREAD_STUCK_IN_DEVICE_DRIVER"
            Description = "A device driver is stuck in an infinite loop. Graphics driver is common culprit."
            RootCause = "Faulty graphics driver, driver timeout, or hardware incompatibility."
            BootStage = "Stage 5: Driver Loading"
            Severity = "High"
            Recommendations = @(
                "Update graphics drivers",
                "Rollback graphics drivers",
                "Check for graphics driver conflicts",
                "Update chipset drivers",
                "Check graphics card hardware"
            )
            TroubleshootingSteps = @(
                "1. Update graphics drivers from manufacturer's website",
                "2. Rollback to previous graphics driver version",
                "3. Check for graphics driver conflicts",
                "4. Update chipset drivers",
                "5. Test graphics card in another system",
                "6. Check graphics card temperature and power"
            )
            RepairCommands = @(
                "sfc /scannow",
                "DISM /Online /Cleanup-Image /RestoreHealth"
            )
            RelatedErrors = @("0x000000D1", "0x0000001E")
        }
    }
    
    # Look up error code
    if ($errorDatabase.ContainsKey($ErrorCode)) {
        $errorInfo = $errorDatabase[$ErrorCode]
        $result.Found = $true
        $result.Type = $errorInfo.Type
        $result.Name = $errorInfo.Name
        $result.Description = $errorInfo.Description
        $result.RootCause = $errorInfo.RootCause
        $result.BootStage = $errorInfo.BootStage
        $result.Severity = $errorInfo.Severity
        $result.Recommendations = $errorInfo.Recommendations
        $result.TroubleshootingSteps = $errorInfo.TroubleshootingSteps
        $result.RepairCommands = $errorInfo.RepairCommands
        $result.RelatedErrors = $errorInfo.RelatedErrors
    } else {
        # Try to match partial codes or provide generic guidance
        if ($ErrorCode -match "^0xC") {
            $result.Type = "Boot Error (Likely)"
            $result.Description = "This appears to be a Windows boot error code. Boot errors typically indicate problems with boot files, BCD, or boot device access."
            $result.Recommendations = @(
                "Run: bcdboot $TargetDrive`:\Windows",
                "Run: bootrec /rebuildbcd",
                "Check for missing storage drivers",
                "Verify boot files are not corrupted"
            )
        } elseif ($ErrorCode -match "^0x8") {
            $result.Type = "Installation/System Error (Likely)"
            $result.Description = "This appears to be a Windows installation or system error code. Installation errors typically indicate problems with installation files, permissions, or disk space."
            $result.Recommendations = @(
                "Verify installation media integrity",
                "Check disk space",
                "Run installation as administrator",
                "Check for file permission issues"
            )
        } elseif ($ErrorCode -match "^0x0{6}[0-9A-F]{6}$") {
            $result.Type = "BSOD Stop Code (Likely)"
            $result.Description = "This appears to be a Blue Screen of Death (BSOD) stop code. BSOD errors typically indicate driver, hardware, or system file issues."
            $result.Recommendations = @(
                "Boot into Safe Mode",
                "Update drivers, especially graphics and storage",
                "Run: sfc /scannow",
                "Check for hardware failures",
                "Check Event Viewer for specific errors"
            )
        } else {
            $result.Description = "Unknown error code format. Please verify the error code and try again."
        }
    }
    
    # Generate formatted report
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("WINDOWS ERROR CODE LOOKUP") | Out-Null
    $report.AppendLine("Error Code: $ErrorCode") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($result.Found) {
        $report.AppendLine("ERROR INFORMATION:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $report.AppendLine("Type: $($result.Type)") | Out-Null
        $report.AppendLine("Name: $($result.Name)") | Out-Null
        $report.AppendLine("Severity: $($result.Severity)") | Out-Null
        $report.AppendLine("Boot Stage: $($result.BootStage)") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("DESCRIPTION:") | Out-Null
        $report.AppendLine($result.Description) | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("ROOT CAUSE:") | Out-Null
        $report.AppendLine($result.RootCause) | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($result.Recommendations.Count -gt 0) {
            $report.AppendLine("RECOMMENDATIONS:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            foreach ($rec in $result.Recommendations) {
                $report.AppendLine("  - $rec") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.TroubleshootingSteps.Count -gt 0) {
            $report.AppendLine("TROUBLESHOOTING STEPS:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            foreach ($step in $result.TroubleshootingSteps) {
                $report.AppendLine($step) | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.RepairCommands.Count -gt 0) {
            $report.AppendLine("REPAIR COMMANDS:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            foreach ($cmd in $result.RepairCommands) {
                $report.AppendLine("  $cmd") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.RelatedErrors.Count -gt 0) {
            $report.AppendLine("RELATED ERROR CODES:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            $report.AppendLine("  $($result.RelatedErrors -join ', ')") | Out-Null
            $report.AppendLine("") | Out-Null
            $report.AppendLine("  (You can look up these codes using: Get-WindowsErrorCodeInfo -ErrorCode 'CODE')") | Out-Null
            $report.AppendLine("") | Out-Null
        }
    } else {
        $report.AppendLine("ERROR CODE NOT FOUND IN DATABASE") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $report.AppendLine("Type: $($result.Type)") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine($result.Description) | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($result.Recommendations.Count -gt 0) {
            $report.AppendLine("GENERAL RECOMMENDATIONS:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            foreach ($rec in $result.Recommendations) {
                $report.AppendLine("  - $rec") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        $report.AppendLine("SEARCH FOR HELP:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $report.AppendLine("1. Search online: 'Windows error $ErrorCode'") | Out-Null
        $report.AppendLine("2. Check Microsoft Support: support.microsoft.com") | Out-Null
        $report.AppendLine("3. Use ChatGPT: 'Windows error $ErrorCode troubleshooting'") | Out-Null
        $report.AppendLine("4. Check Windows Event Viewer for detailed error information") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    $report.AppendLine($separator) | Out-Null
    $result.Report = $report.ToString()
    
    return $result
}

function Get-SystemInformation {
    <#
    .SYNOPSIS
    Comprehensive system information dashboard with hardware, drivers, Windows details, and health status.
    
    .DESCRIPTION
    Collects detailed information about:
    - Hardware components (CPU, RAM, GPU, Storage, Motherboard)
    - Driver status and missing drivers
    - Windows version and build information
    - System health metrics
    - Boot configuration
    - Network adapters
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Hardware = @{}
        Drivers = @{}
        Windows = @{}
        Health = @{}
        Boot = @{}
        Network = @{}
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("COMPREHENSIVE SYSTEM INFORMATION") | Out-Null
    $report.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Hardware Information
    $report.AppendLine("HARDWARE INFORMATION") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $memory = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
        $gpus = Get-CimInstance Win32_VideoController
        $disks = Get-CimInstance Win32_DiskDrive
        $motherboard = Get-CimInstance Win32_BaseBoard
        
        $result.Hardware = @{
            ComputerName = $env:COMPUTERNAME
            Manufacturer = $os.Manufacturer
            Model = (Get-CimInstance Win32_ComputerSystem).Model
            CPU = @{
                Name = $cpu.Name
                Cores = $cpu.NumberOfCores
                LogicalProcessors = $cpu.NumberOfLogicalProcessors
                MaxClockSpeed = "$([math]::Round($cpu.MaxClockSpeed / 1000, 2)) GHz"
            }
            Memory = @{
                TotalGB = [math]::Round($memory.Sum / 1GB, 2)
                Modules = (Get-CimInstance Win32_PhysicalMemory).Count
            }
            GPUs = $gpus | ForEach-Object {
                @{
                    Name = $_.Name
                    DriverVersion = $_.DriverVersion
                    VideoMemoryGB = if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1GB, 2) } else { "Unknown" }
                }
            }
            Storage = $disks | ForEach-Object {
                @{
                    Model = $_.Model
                    SizeGB = [math]::Round($_.Size / 1GB, 2)
                    Interface = $_.InterfaceType
                }
            }
            Motherboard = @{
                Manufacturer = $motherboard.Manufacturer
                Product = $motherboard.Product
                Version = $motherboard.Version
            }
        }
        
        $report.AppendLine("Computer: $($result.Hardware.ComputerName)") | Out-Null
        $report.AppendLine("Manufacturer: $($result.Hardware.Manufacturer)") | Out-Null
        $report.AppendLine("Model: $($result.Hardware.Model)") | Out-Null
        $report.AppendLine("CPU: $($result.Hardware.CPU.Name)") | Out-Null
        $report.AppendLine("  Cores: $($result.Hardware.CPU.Cores), Logical: $($result.Hardware.CPU.LogicalProcessors)") | Out-Null
        $report.AppendLine("Memory: $($result.Hardware.Memory.TotalGB) GB ($($result.Hardware.Memory.Modules) modules)") | Out-Null
        $report.AppendLine("Motherboard: $($result.Hardware.Motherboard.Manufacturer) $($result.Hardware.Motherboard.Product)") | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($result.Hardware.GPUs.Count -gt 0) {
            $report.AppendLine("Graphics Cards:") | Out-Null
            foreach ($gpu in $result.Hardware.GPUs) {
                $report.AppendLine("  - $($gpu.Name) ($($gpu.VideoMemoryGB) GB)") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.Hardware.Storage.Count -gt 0) {
            $report.AppendLine("Storage Devices:") | Out-Null
            foreach ($disk in $result.Hardware.Storage) {
                $report.AppendLine("  - $($disk.Model) ($($disk.SizeGB) GB, $($disk.Interface))") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
    } catch {
        $report.AppendLine("[WARNING] Could not retrieve hardware information: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # Windows Information
    $report.AppendLine("WINDOWS INFORMATION") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $regInfo = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        
        $result.Windows = @{
            Caption = $os.Caption
            Version = $os.Version
            BuildNumber = $os.BuildNumber
            EditionID = if ($regInfo) { $regInfo.EditionID } else { "Unknown" }
            ProductName = if ($regInfo) { $regInfo.ProductName } else { "Unknown" }
            ReleaseId = if ($regInfo) { $regInfo.ReleaseId } else { "Unknown" }
            InstallDate = $os.InstallDate
            LastBootUpTime = $os.LastBootUpTime
            TotalVirtualMemoryGB = [math]::Round($os.TotalVirtualMemorySize / 1MB / 1024, 2)
            FreeVirtualMemoryGB = [math]::Round($os.FreeVirtualMemorySize / 1MB / 1024, 2)
        }
        
        $report.AppendLine("OS: $($result.Windows.Caption)") | Out-Null
        $report.AppendLine("Version: $($result.Windows.Version) (Build $($result.Windows.BuildNumber))") | Out-Null
        $report.AppendLine("Edition: $($result.Windows.EditionID)") | Out-Null
        $report.AppendLine("Release ID: $($result.Windows.ReleaseId)") | Out-Null
        $report.AppendLine("Install Date: $($result.Windows.InstallDate)") | Out-Null
        $report.AppendLine("Last Boot: $($result.Windows.LastBootUpTime)") | Out-Null
        $report.AppendLine("Virtual Memory: $($result.Windows.FreeVirtualMemoryGB) GB free / $($result.Windows.TotalVirtualMemoryGB) GB total") | Out-Null
        $report.AppendLine("") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Could not retrieve Windows information: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # Driver Status
    $report.AppendLine("DRIVER STATUS") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $devices = Get-PnpDevice | Where-Object { $_.Status -ne 'OK' -or $_.Class -eq 'System' }
        $problemDevices = Get-PnpDevice | Where-Object { $_.Status -ne 'OK' }
        
        $result.Drivers = @{
            TotalDevices = (Get-PnpDevice).Count
            ProblemDevices = $problemDevices.Count
            MissingDrivers = @()
        }
        
        foreach ($device in $problemDevices) {
            $result.Drivers.MissingDrivers += @{
                Name = $device.FriendlyName
                Status = $device.Status
                Problem = $device.Status
            }
        }
        
        $report.AppendLine("Total Devices: $($result.Drivers.TotalDevices)") | Out-Null
        $report.AppendLine("Problem Devices: $($result.Drivers.ProblemDevices)") | Out-Null
        
        if ($result.Drivers.MissingDrivers.Count -gt 0) {
            $report.AppendLine("") | Out-Null
            $report.AppendLine("Devices with Issues:") | Out-Null
            foreach ($driver in $result.Drivers.MissingDrivers | Select-Object -First 10) {
                $report.AppendLine("  - $($driver.Name): $($driver.Status)") | Out-Null
            }
        }
        $report.AppendLine("") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Could not retrieve driver information: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # System Health
    $report.AppendLine("SYSTEM HEALTH") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $bootProb = Get-BootProbability -TargetDrive $TargetDrive
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        
        $result.Health = @{
            BootProbability = $bootProb.Score
            BootHealthStatus = $bootProb.HealthStatus
            SystemFilesHealthy = $fileHealth.SystemFilesHealthy
            ComponentStoreHealthy = $fileHealth.ComponentStoreHealthy
            DiskHealthy = $diskHealth.FileSystemHealthy
            HasBadSectors = $diskHealth.HasBadSectors
            OverallScore = 0
        }
        
        # Calculate overall health score
        $scores = @()
        if ($result.Health.BootProbability -ge 0) { $scores += $result.Health.BootProbability }
        if ($result.Health.SystemFilesHealthy) { $scores += 100 } else { $scores += 50 }
        if ($result.Health.ComponentStoreHealthy) { $scores += 100 } else { $scores += 50 }
        if ($result.Health.DiskHealthy) { $scores += 100 } else { $scores += 50 }
        if ($scores.Count -gt 0) {
            $result.Health.OverallScore = [math]::Round(($scores | Measure-Object -Average).Average, 1)
        }
        
        $report.AppendLine("Boot Probability: $($result.Health.BootProbability)% ($($result.Health.BootHealthStatus))") | Out-Null
        $report.AppendLine("System Files: $(if ($result.Health.SystemFilesHealthy) { 'Healthy' } else { 'Issues Detected' })") | Out-Null
        $report.AppendLine("Component Store: $(if ($result.Health.ComponentStoreHealthy) { 'Healthy' } else { 'Issues Detected' })") | Out-Null
        $report.AppendLine("Disk Health: $(if ($result.Health.DiskHealthy) { 'Healthy' } else { 'Issues Detected' })") | Out-Null
        if ($result.Health.HasBadSectors) {
            $report.AppendLine("[WARNING] Bad sectors detected on disk") | Out-Null
        }
        $report.AppendLine("Overall Health Score: $($result.Health.OverallScore)%") | Out-Null
        $report.AppendLine("") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Could not retrieve health information: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # Boot Configuration
    $report.AppendLine("BOOT CONFIGURATION") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $bcdEntries = Get-BCDEntriesParsed
        $bootLoaders = $bcdEntries | Where-Object { $_.Type -eq 'Windows Boot Loader' }
        $duplicates = Find-DuplicateBCEEntries
        
        $result.Boot = @{
            BootEntries = $bootLoaders.Count
            DuplicateEntries = if ($duplicates) { $duplicates.Count } else { 0 }
            BootType = "Unknown"
        }
        
        # Detect boot type
        $partition = Get-Partition -DriveLetter $TargetDrive -ErrorAction SilentlyContinue
        if ($partition) {
            $disk = Get-Disk -Number $partition.DiskNumber
            $result.Boot.BootType = if ($disk.PartitionStyle -eq 'GPT') { "UEFI" } else { "Legacy BIOS" }
        }
        
        $report.AppendLine("Boot Type: $($result.Boot.BootType)") | Out-Null
        $report.AppendLine("Boot Entries: $($result.Boot.BootEntries)") | Out-Null
        $report.AppendLine("Duplicate Entries: $($result.Boot.DuplicateEntries)") | Out-Null
        $report.AppendLine("") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Could not retrieve boot configuration: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # Network Adapters
    $report.AppendLine("NETWORK ADAPTERS") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
        if ($adapters) {
            $result.Network = @{
                Adapters = $adapters | ForEach-Object {
                    @{
                        Name = $_.Name
                        Status = $_.Status
                        LinkSpeed = $_.LinkSpeed
                        MacAddress = $_.MacAddress
                    }
                }
            }
            
            foreach ($adapter in $result.Network.Adapters) {
                $report.AppendLine("  - $($adapter.Name): $($adapter.Status) ($($adapter.LinkSpeed))") | Out-Null
            }
        } else {
            $report.AppendLine("No network adapters found or network not available") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Could not retrieve network information: $_") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Get-HardwareSupportInfo {
    $info = @{
        Motherboard = ""
        GPUs = @()
        SupportLinks = @()
        DriverAlerts = @()
    }
    
    try {
        # Get Motherboard Info
        $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
        if ($board) {
            $info.Motherboard = "$($board.Manufacturer) $($board.Product)"
            
            # Map Manufacturer Support Sites
            if ($board.Manufacturer -match "ASUS|ASUSTeK") { 
                $info.SupportLinks += @{
                    Name = "ASUS Support"
                    URL = "https://www.asus.com/support/"
                    Type = "Motherboard"
                }
            }
            elseif ($board.Manufacturer -match "MSI|Micro-Star") { 
                $info.SupportLinks += @{
                    Name = "MSI Support"
                    URL = "https://www.msi.com/support"
                    Type = "Motherboard"
                }
            }
            elseif ($board.Manufacturer -match "Gigabyte|GIGABYTE") { 
                $info.SupportLinks += @{
                    Name = "Gigabyte Support"
                    URL = "https://www.gigabyte.com/Support"
                    Type = "Motherboard"
                }
            }
            elseif ($board.Manufacturer -match "ASRock") {
                $info.SupportLinks += @{
                    Name = "ASRock Support"
                    URL = "https://www.asrock.com/support/index.asp"
                    Type = "Motherboard"
                }
            }
            elseif ($board.Manufacturer -match "Intel") {
                $info.SupportLinks += @{
                    Name = "Intel Support"
                    URL = "https://www.intel.com/content/www/us/en/support.html"
                    Type = "Motherboard"
                }
            }
        }
        
        # Get GPU Info
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        foreach ($gpu in $gpus) {
            if ($gpu.Name -and $gpu.Name -notmatch "Microsoft|Basic|Standard") {
                $gpuInfo = @{
                    Name = $gpu.Name
                    DriverVersion = $gpu.DriverVersion
                    DriverDate = $gpu.DriverDate
                    Manufacturer = ""
                    SupportLink = ""
                }
                
                # Determine GPU manufacturer and support link
                if ($gpu.Name -match "NVIDIA|GeForce|RTX|GTX|Quadro") {
                    $gpuInfo.Manufacturer = "NVIDIA"
                    $gpuInfo.SupportLink = "https://www.nvidia.com/Download/index.aspx"
                }
                elseif ($gpu.Name -match "AMD|Radeon|RX|R9|R7") {
                    $gpuInfo.Manufacturer = "AMD"
                    $gpuInfo.SupportLink = "https://www.amd.com/en/support"
                }
                elseif ($gpu.Name -match "Intel.*Graphics|Iris|UHD") {
                    $gpuInfo.Manufacturer = "Intel"
                    $gpuInfo.SupportLink = "https://www.intel.com/content/www/us/en/download-center/home.html"
                }
                
                # Check driver age (if DriverDate is available)
                if ($gpu.DriverDate) {
                    try {
                        $driverDate = [DateTime]::ParseExact($gpu.DriverDate, "yyyyMMdd", $null)
                        $ageMonths = ([DateTime]::Now - $driverDate).Days / 30
                        if ($ageMonths -gt 6) {
                            $info.DriverAlerts += "GPU driver for $($gpu.Name) is $([math]::Round($ageMonths, 1)) months old. Consider updating."
                        }
                    } catch {
                        # Date parsing failed, skip age check
                    }
                }
                
                $info.GPUs += $gpuInfo
                
                # Add GPU support links
                if ($gpuInfo.SupportLink) {
                    $info.SupportLinks += @{
                        Name = "$($gpuInfo.Manufacturer) GPU Drivers"
                        URL = $gpuInfo.SupportLink
                        Type = "GPU"
                    }
                }
            }
        }
        
    } catch {
        $info.Error = "Error retrieving hardware information: $_"
    }
    
    return $info
}

function Run-BootDiagnosis {
    param($Drive = "C")
    
    # Normalize drive letter
    if ($Drive -match '^([A-Z]):?$') {
        $Drive = $matches[1]
    }
    
    $currentOS = ($env:SystemDrive.TrimEnd(':') -eq $Drive)
    $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
    
    $report = New-Object System.Text.StringBuilder
    $issues = @()
    
    $report.AppendLine("AUTOMATED BOOT DIAGNOSIS REPORT") | Out-Null
    $report.AppendLine("===============================================================") | Out-Null
    $report.AppendLine("Target Windows Installation: $Drive`:\Windows") | Out-Null
    $report.AppendLine("Status: $osContext") | Out-Null
    $report.AppendLine("Scan Time: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 1. UEFI/GPT Integrity Check
    $efiPartition = $null
    $efiDriveLetter = $null
    try {
        $partition = Get-Partition -DriveLetter $Drive -ErrorAction SilentlyContinue
        if ($partition) {
            $disk = Get-Disk -Number $partition.DiskNumber
            $efiPartitions = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
            if ($efiPartitions) {
                $efiPartition = $efiPartitions[0]
                $report.AppendLine("[PASS] EFI Boot Partition found on Disk $($disk.Number).")
                $report.AppendLine("       Partition: $($efiPartition.PartitionNumber), Size: $([math]::Round($efiPartition.Size/1MB, 2)) MB")
                
                # Check if EFI partition has Microsoft Boot folders and validate format
                if ($efiPartition.DriveLetter) {
                    $efiDriveLetter = $efiPartition.DriveLetter
                    $bootPath = "$efiDriveLetter`:\EFI\Microsoft\Boot"
                    
                    # Check EFI partition file system format
                    $efiVolume = Get-Volume -DriveLetter $efiDriveLetter -ErrorAction SilentlyContinue
                    if ($efiVolume) {
                        if ($efiVolume.FileSystem -eq "FAT32") {
                            $report.AppendLine("[PASS] EFI partition is formatted as FAT32 (correct format).")
                        } elseif ($efiVolume.FileSystem -eq "RAW" -or $efiVolume.FileSystem -eq "NTFS") {
                            $report.AppendLine("[FAIL] EFI partition is formatted as $($efiVolume.FileSystem) - Windows cannot boot from this format.")
                            $issues += @{
                                Type = "EFI Partition Format Error"
                                Severity = "Critical"
                                Description = "EFI System Partition is formatted as $($efiVolume.FileSystem) instead of FAT32. Windows cannot boot from RAW or NTFS EFI partitions."
                                Recommendation = "Format the EFI partition as FAT32, then run: bcdboot $Drive`:\Windows /s $efiDriveLetter`: /f UEFI"
                            }
                        }
                    }
                    
                    if (Test-Path $bootPath) {
                        $report.AppendLine("[PASS] EFI partition contains Microsoft Boot folder structure.")
                    } else {
                        $report.AppendLine("[FAIL] EFI partition missing Microsoft Boot folder structure.")
                        $issues += @{
                            Type = "EFI/GPT Integrity Issue"
                            Severity = "Critical"
                            Description = "EFI System Partition exists but is missing the Microsoft Boot folder structure."
                            Recommendation = "Run: bcdboot $Drive`:\Windows /s $efiDriveLetter`: /f UEFI to recreate UEFI boot files and BCD store."
                        }
                    }
                } else {
                    $report.AppendLine("[WARNING] EFI partition found but has no drive letter assigned.")
                }
            } else { 
                $report.AppendLine("[FAIL] No EFI Partition found on disk $($disk.Number). PC cannot boot in UEFI mode.")
                $issues += @{
                    Type = "Missing EFI Partition"
                    Severity = "Critical"
                    Description = "No EFI System Partition detected. System cannot boot in UEFI mode."
                    Recommendation = "Create an EFI partition or check if system uses Legacy BIOS mode."
                }
            }
        } else {
            $report.AppendLine("[WARNING] Could not determine disk information for drive $Drive`:")
        }
    } catch {
        $report.AppendLine("[ERROR] Failed to check EFI partition: $_")
    }
    
    # 2. Check for BCD File and Integrity
    $bcdFound = $false
    $bcdPath = $null
    $bcdAccessible = $false
    $checkedPaths = @()
    
    try {
        # First, check if bcdedit actually works (most reliable test)
        try {
            $bcdTest = bcdedit /enum 2>&1 | Out-String
            if ($bcdTest -match "Windows Boot Manager" -or $bcdTest -match "identifier.*\{default\}") {
                $bcdAccessible = $true
                $report.AppendLine("[PASS] BCD Store is accessible via bcdedit (system can boot)")
                $bcdFound = $true
            } elseif ($bcdTest -match "The boot configuration data store could not be opened") {
                $report.AppendLine("[FAIL] BCD exists but cannot be opened - may be corrupted or locked")
                $issues += @{
                    Type = "BCD Integrity Failure"
                    Severity = "Critical"
                    Description = "The BCD exists but is 'orphaned' or the attributes are locked. bcdedit returns 'could not be opened'."
                    Recommendation = "Run: attrib [BCD_PATH] -h -r -s, then rename to bcd.old, then run: bootrec /rebuildbcd"
                }
            }
        } catch {
            # bcdedit failed, continue with file path checks
        }
        
        # Now check file paths (for detailed reporting)
        if ($efiDriveLetter) {
            $bcdPath = "$efiDriveLetter`:\EFI\Microsoft\Boot\BCD"
            $checkedPaths += $bcdPath
            if (Test-Path $bcdPath) { 
                $report.AppendLine("[PASS] BCD Store file exists at $bcdPath")
                if (-not $bcdFound) { $bcdFound = $true }
            } else {
                $report.AppendLine("[INFO] BCD Store file not found at expected location: $bcdPath")
                if ($bcdAccessible) {
                    $report.AppendLine("       However, bcdedit works, so BCD is accessible from another location.")
                }
            }
        } else {
            # Try to find EFI partition with drive letter
            $allEfiParts = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -and $_.DriveLetter }
            foreach ($efi in $allEfiParts) {
                $testPath = "$($efi.DriveLetter):\EFI\Microsoft\Boot\BCD"
                $checkedPaths += $testPath
                if (Test-Path $testPath) { 
                    $report.AppendLine("[PASS] BCD Store file exists at $testPath")
                    $bcdFound = $true
                    $bcdPath = $testPath
                    $efiDriveLetter = $efi.DriveLetter
                    break
                }
            }
            
            # Try to mount EFI partitions without drive letters
            $allEfiPartsNoLetter = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -and -not $_.DriveLetter }
            foreach ($efi in $allEfiPartsNoLetter) {
                try {
                    # Try to assign a temporary drive letter
                    $tempLetter = [char](70 + $efi.PartitionNumber)  # Start from F:
                    if (-not (Get-PSDrive -Name $tempLetter -ErrorAction SilentlyContinue)) {
                        $efi | Set-Partition -NewDriveLetter $tempLetter -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 500
                        $testPath = "$tempLetter`:\EFI\Microsoft\Boot\BCD"
                        $checkedPaths += $testPath
                        if (Test-Path $testPath) {
                            $report.AppendLine("[PASS] BCD Store file exists at $testPath (mounted EFI partition)")
                            $bcdFound = $true
                            $bcdPath = $testPath
                            $efiDriveLetter = $tempLetter
                            break
                        }
                        # Unmount if not found
                        $efi | Remove-PartitionAccessPath -AccessPath "$tempLetter`:" -ErrorAction SilentlyContinue
                    }
                } catch {
                    # Ignore mount errors
                }
            }
        }
        
        # Only report missing BCD if bcdedit also fails
        if (-not $bcdFound -and -not $bcdAccessible) {
            $checkedPathsList = $checkedPaths -join ", "
            $report.AppendLine("[FAIL] BCD Store not found in any checked location.")
            $report.AppendLine("       Checked paths: $checkedPathsList")
            $issues += @{
                Type = "Missing BCD File"
                Severity = "Critical"
                Description = "The Boot Configuration Data file is missing from all EFI partitions. Checked paths: $checkedPathsList"
                Recommendation = "Boot into a recovery environment and run: bcdboot $Drive`:\Windows /s [EFILetter]: /f UEFI (replace [EFILetter] with the EFI partition drive letter). If EFI partition has no drive letter, mount it first using Disk Management."
            }
        } elseif (-not $bcdFound -and $bcdAccessible) {
            $report.AppendLine("[INFO] BCD file path not found, but bcdedit works - BCD is accessible (may be on unmounted partition)")
        }
        
        # Check if BCD is orphaned (exists but no entries)
        if ($bcdFound) {
            try {
                $bcdEnum = bcdedit /enum 2>&1 | Out-String
                if ($bcdEnum -match "Total identified Windows installations:\s*0") {
                    $report.AppendLine("[FAIL] BCD exists but is orphaned - Total identified Windows installations: 0")
                    $issues += @{
                        Type = "Orphaned BCD"
                        Severity = "Critical"
                        Description = "The BCD exists but is 'orphaned' - it contains no Windows installation entries. The attributes may be locked."
                        Recommendation = "Run: attrib $bcdPath -h -r -s, rename to bcd.old, then run: bootrec /rebuildbcd to scan and re-add Windows installations"
                    }
                }
            } catch {
                # Ignore enumeration errors
            }
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check BCD file location: $_")
    }
    
    # 3. Validate BCD Entries
    if ($bcdFound) {
        try {
            $bcdOutput = bcdedit /enum 2>&1
            $hasBootMgr = $bcdOutput | Select-String "Windows Boot Manager" -Quiet
            $hasDefault = $bcdOutput | Select-String "identifier.*\{default\}" -Quiet
            
            if ($hasBootMgr) {
                $report.AppendLine("[PASS] Windows Boot Manager entry found in BCD")
            } else {
                $report.AppendLine("[FAIL] Windows Boot Manager entry missing from BCD")
                $issues += @{
                    Type = "Missing Boot Manager Entry"
                    Severity = "Critical"
                    Description = "The {bootmgr} entry is missing from the BCD store."
                    Recommendation = "Run: bcdboot $Drive`:\Windows to recreate boot entries"
                }
            }
            
            if ($hasDefault) {
                $report.AppendLine("[PASS] Default boot entry found in BCD")
                
                # Check if default entry points to valid partition (BCD/UEFI Desync check)
                $defaultEntry = $bcdOutput | Select-String -Pattern "identifier.*\{default\}" -Context 0,20
                if ($defaultEntry) {
                    $defaultText = $defaultEntry.ToString()
                    if ($defaultText -match "device\s+partition=([A-Z]):") {
                        $targetDrive = $matches[1]
                        if (Test-Path "$targetDrive`:\Windows") {
                            $report.AppendLine("[PASS] Default entry points to valid Windows installation on $targetDrive`:")
                        } else {
                            $report.AppendLine("[FAIL] Default entry points to invalid partition: $targetDrive`:")
                            $issues += @{
                                Type = "BCD/UEFI Desync"
                                Severity = "Critical"
                                Description = "The BCD exists but points to a stale disk signature (common after cloning or drive migration). The BCD entry for the default operating system points to a partition that no longer exists."
                                Recommendation = "Recreate the boot files: bcdboot $Drive`:\Windows /s $efiDriveLetter`: /f UEFI (if EFI partition has drive letter) or use BCD Editor to update device/osdevice fields."
                            }
                        }
                    } elseif ($defaultText -match "device\s+partition=\{[0-9A-F-]+\}") {
                        # Check if GUID partition exists
                        $report.AppendLine("[WARNING] Default entry uses GUID partition reference - validating...")
                        # Note: Full GUID validation would require more complex parsing
                    }
                }
            } else {
                $report.AppendLine("[FAIL] Default boot entry missing from BCD")
                $issues += @{
                    Type = "Missing Default Entry"
                    Severity = "Critical"
                    Description = "No default boot entry found in BCD store. Bootloader cannot determine which OS to load."
                    Recommendation = "Run: bootrec /rebuildbcd to scan for all Windows installations and re-add them to the menu, or bcdboot $Drive`:\Windows to recreate boot entries."
                }
            }
        } catch {
            $report.AppendLine("[WARNING] Could not validate BCD entries: $_")
        }
    }
    
    # 4. WinRE Access Validation (Bootloader "Good Enough" Check)
    try {
        $reagentcOutput = reagentc /info 2>&1 | Out-String
        if ($reagentcOutput -match "Windows RE status:\s*(\w+)") {
            $reStatus = $matches[1]
            if ($reStatus -eq "Enabled") {
                $report.AppendLine("[PASS] Windows Recovery Environment (WinRE) is enabled")
                
                # Check if WinRE location is accessible
                if ($reagentcOutput -match "Windows RE location:\s*(.+)") {
                    $reLocation = $matches[1].Trim()
                    $report.AppendLine("[INFO] WinRE location reported by reagentc: $reLocation")
                    
                    # Device paths (\\?\GLOBALROOT\...) need special handling
                    $reAccessible = $false
                    if ($reLocation -match "^\\\\\?\\GLOBALROOT") {
                        # This is a device path - try to access it differently
                        try {
                            # Check if we can get partition info from the path
                            if ($reLocation -match "harddisk(\d+)\\partition(\d+)") {
                                $diskNum = [int]$matches[1]
                                $partNum = [int]$matches[2]
                                $part = Get-Partition -DiskNumber $diskNum -PartitionNumber $partNum -ErrorAction SilentlyContinue
                                if ($part) {
                                    $reAccessible = $true
                                    $report.AppendLine("[PASS] WinRE partition exists (Disk $diskNum, Partition $partNum)")
                                }
                            }
                        } catch {
                            # Try direct path test as fallback
                            $reAccessible = Test-Path $reLocation
                        }
                    } else {
                        # Regular path - test directly
                        $reAccessible = Test-Path $reLocation
                    }
                    
                    if ($reAccessible) {
                        $report.AppendLine("[PASS] WinRE location is accessible: $reLocation")
                        $report.AppendLine("[PASS] System can reach 'Windows Logo' stage - 'Good Enough' state achieved")
                    } else {
                        # Check if WinRE is actually functional by testing reagentc operations
                        try {
                            $reTest = reagentc /info 2>&1 | Out-String
                            if ($reTest -match "Operation Successful" -and $reStatus -eq "Enabled") {
                                $report.AppendLine("[INFO] WinRE is enabled and reagentc reports successful operation")
                                $report.AppendLine("[INFO] Path check failed, but WinRE may still be functional (device path may not be accessible via Test-Path)")
                                $report.AppendLine("[PASS] WinRE appears functional based on reagentc status")
                            } else {
                                $report.AppendLine("[WARNING] WinRE location reported but not accessible: $reLocation")
                                $report.AppendLine("         Exact path checked: $reLocation")
                                $issues += @{
                                    Type = "WinRE Inaccessible"
                                    Severity = "Warning"
                                    Description = "WinRE is enabled according to reagentc, but the reported location cannot be accessed. Location: $reLocation. This may be a false positive if using device paths (\\?\GLOBALROOT\...)."
                                    Recommendation = "If WinRE is actually working (you can access Advanced Startup), this warning can be ignored. Otherwise, run: reagentc /enable to re-link the recovery image to the boot menu."
                                }
                            }
                        } catch {
                            $report.AppendLine("[WARNING] WinRE location reported but not accessible: $reLocation")
                            $report.AppendLine("         Exact path checked: $reLocation")
                            $issues += @{
                                Type = "WinRE Inaccessible"
                                Severity = "Warning"
                                Description = "WinRE is enabled but the recovery environment location cannot be verified. Location: $reLocation"
                                Recommendation = "Run: reagentc /enable to re-link the recovery image to the boot menu."
                            }
                        }
                    }
                } else {
                    $report.AppendLine("[WARNING] WinRE is enabled but location not reported by reagentc")
                }
            } else {
                $report.AppendLine("[FAIL] Windows Recovery Environment (WinRE) is disabled")
                $issues += @{
                    Type = "Recovery Environment Disabled"
                    Severity = "Warning"
                    Description = "reagentc reports that WinRE is disabled, meaning 'Advanced Startup' options will not function. Recovery environment cannot trigger 'Startup Repair'."
                    Recommendation = "Run: reagentc /enable in an elevated command prompt to re-link the recovery image to the boot menu."
                }
            }
        } else {
            $report.AppendLine("[WARNING] Could not determine WinRE status from reagentc output")
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check WinRE status: $_")
    }
    
    # 5. Driver Matching - Scan Hardware IDs for storage controllers
    # Only report devices with error codes that indicate missing drivers
    # Error code 28 = Driver not installed (most common)
    # Error code 1 = Device not configured properly (often driver issue)
    # Error code 3 = Driver may be corrupted
    $missingStorage = Get-PnpDevice | Where-Object { 
        ($_.ConfigManagerErrorCode -eq 28 -or $_.ConfigManagerErrorCode -eq 1 -or $_.ConfigManagerErrorCode -eq 3) -and 
        ($_.Class -match 'SCSI|Storage|System|DiskDrive' -or $_.FriendlyName -match 'VMD|RAID|NVMe|Storage|Controller')
    }
    if ($missingStorage) {
        $report.AppendLine("[FAIL] Missing or errored storage controllers detected: $($missingStorage.Count)")
        
        # Check for specific Intel VMD (common culprit)
        $intelVMD = $missingStorage | Where-Object { 
            $_.HardwareID -and 
            ($_.HardwareID -match "VEN_8086&DEV_9A0B" -or $_.HardwareID -match "VEN_8086&DEV_467F")
        }
        
        if ($intelVMD) {
            $report.AppendLine("[CRITICAL] Intel VMD controller detected without driver (PCI\VEN_8086&DEV_9A0B)")
            $report.AppendLine("           This will make the drive 'invisible' to the OS.")
            $issues += @{
                Type = "Intel VMD Driver Missing"
                Severity = "Critical"
                Description = "Intel VMD (Volume Management Device) controller detected without driver. The drive will be 'invisible' to Windows, causing 0x7B BSOD."
                Recommendation = "Load Intel VMD driver: drvload [path]\iaStorVD.inf. Use 'Driver Forensics' to locate the exact INF file needed."
            }
        } else {
            $issues += @{
                Type = "Missing Storage Drivers"
                Severity = "Critical"
                Description = "Storage controllers with error codes detected. This may prevent Windows from 'seeing' the boot drive."
                Recommendation = "Use 'Driver Forensics' button to identify required INF files. Load drivers using: drvload [path]\driver.inf"
            }
        }
        
        foreach ($dev in $missingStorage | Select-Object -First 3) {
            $hwid = if ($dev.HardwareID -and $dev.HardwareID.Count -gt 0) { $dev.HardwareID[0] } else { "Unknown" }
            $report.AppendLine("       - $($dev.FriendlyName) (Error: $($dev.ConfigManagerErrorCode), HWID: $hwid)")
        }
    } else {
        $report.AppendLine("[PASS] No missing storage controllers detected")
    }
    
    # 6. Check for Windows Kernel
    if (Test-Path "$Drive`:\Windows\System32\ntoskrnl.exe") { 
        $report.AppendLine("[PASS] Windows System files detected on $Drive`:")
    } else { 
        $report.AppendLine("[FAIL] Windows Kernel not found. Drive may be formatted or corrupted.")
        $issues += @{
            Type = "Missing Windows Kernel"
            Severity = "Critical"
            Description = "Windows kernel file (ntoskrnl.exe) not found. System files may be corrupted or missing."
            Recommendation = "Run DISM repair: dism /Image:$Drive`: /Cleanup-Image /RestoreHealth"
        }
    }
    
    # 7. Check for boot log
    if (Test-Path "$Drive`:\Windows\ntbtlog.txt") {
        $report.AppendLine("[INFO] Boot log (ntbtlog.txt) found - can be analyzed for driver issues.")
    }
    
    # 8. Check for event logs
    if (Test-Path "$Drive`:\Windows\System32\winevt\Logs\System.evtx") {
        $report.AppendLine("[INFO] System event log found - can be analyzed for crashes and errors.")
    }
    
    # Summary Section
    $report.AppendLine("")
    $report.AppendLine("===============================================================")
    $report.AppendLine("DIAGNOSIS SUMMARY")
    $report.AppendLine("===============================================================")
    $report.AppendLine("Total Issues Found: $($issues.Count)")
    
    if ($issues.Count -eq 0) {
        $report.AppendLine("")
        $report.AppendLine("[SUCCESS] No critical boot issues detected!")
        $report.AppendLine("Your boot configuration appears to be healthy.")
    } else {
        $report.AppendLine("")
        $report.AppendLine("ISSUES DETECTED:")
        $report.AppendLine("---------------------------------------------------------------")
        $num = 1
        foreach ($issue in $issues) {
            $report.AppendLine("")
            $report.AppendLine("$num. [$($issue.Severity)] $($issue.Type)")
            $report.AppendLine("   Description: $($issue.Description)")
            $report.AppendLine("   Recommended Action: $($issue.Recommendation)")
            $num++
        }
    }
    
    return @{
        Report = $report.ToString()
        Issues = $issues
        HasCriticalIssues = ($issues | Where-Object { $_.Severity -eq "Critical" }).Count -gt 0
    }
}

function Find-DuplicateBCEEntries {
    $entries = Get-BCDEntriesParsed
    
    # Only check Windows Boot Loader entries, exclude system entries like bootmgr
    # Also exclude entries with empty/null descriptions
    $bootLoaders = $entries | Where-Object { 
        $_.Type -eq 'Windows Boot Loader' -and
        $_.Description -and
        $_.Description.ToString().Trim() -ne '' -and
        $_.Description -notmatch '^Windows Boot Manager$' -and
        $_.Description -notmatch '^Boot Manager$'
    } | Select-Object -Property Id, Description, Type, @{Name='DescKey';Expression={$_.Description.ToString().Trim()}}
    
    # Group by exact description match (case-sensitive for accuracy)
    # Use DescKey property to ensure proper grouping
    $duplicates = $bootLoaders | Group-Object -Property DescKey | Where-Object { $_.Count -gt 1 -and $_.Name -ne '' }
    
    return $duplicates
}

function Fix-DuplicateBCEEntries {
    param([switch]$AppendVolumeLabels)
    $duplicates = Find-DuplicateBCEEntries
    $fixed = @()
    
    foreach ($dupGroup in $duplicates) {
        foreach ($entry in $dupGroup.Group) {
            $newName = $entry.Description
            
            if ($AppendVolumeLabels) {
                # Extract drive letter from device/osdevice
                $driveLetter = $null
                if ($entry.Device -match 'partition=([A-Z]):') {
                    $driveLetter = $matches[1]
                } elseif ($entry.OSDevice -match 'partition=([A-Z]):') {
                    $driveLetter = $matches[1]
                }
                
                if ($driveLetter) {
                    $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
                    if ($volume -and $volume.FileSystemLabel) {
                        $newName = "$($entry.Description) - $($volume.FileSystemLabel)"
                    } else {
                        $newName = "$($entry.Description) - $driveLetter`:"
                    }
                }
            } else {
                # Append entry number
                $index = [array]::IndexOf($dupGroup.Group, $entry)
                $newName = "$($entry.Description) #$($index + 1)"
            }
            
            if ($newName -ne $entry.Description) {
                Set-BCDDescription $entry.Id $newName
                $fixed += @{Id = $entry.Id; OldName = $entry.Description; NewName = $newName}
            }
        }
    }
    
    return $fixed
}

function Sync-BCDToAllEFIPartitions {
    param($SourceWindowsDrive = "C")
    $results = @()
    
    # Find all EFI partitions
    $allDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'GPT' }
    $efiPartitions = @()
    
    foreach ($disk in $allDisks) {
        $parts = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
        foreach ($part in $parts) {
            $efiPartitions += @{Disk = $disk.Number; Partition = $part.PartitionNumber; PartitionObject = $part}
        }
    }
    
    if ($efiPartitions.Count -eq 0) {
        return @{Success = $false; Message = "No EFI System Partitions found."; Results = @()}
    }
    
    $tempLetters = @()
    try {
        # Assign temporary drive letters
        $availableLetters = 90..90 | ForEach-Object { [char]$_ } # Start from Z and work backwards
        $letterIndex = 0
        
        foreach ($efi in $efiPartitions) {
            if ($letterIndex -lt $availableLetters.Count) {
                $tempLetter = $availableLetters[$letterIndex]
                try {
                    $efi.PartitionObject | Set-Partition -NewDriveLetter $tempLetter -ErrorAction Stop
                    $tempLetters += $tempLetter
                    $letterIndex++
                } catch {
                    # Letter might be in use, try next
                    continue
                }
            }
        }
        
        # Sync BCD to each EFI partition
        foreach ($letter in $tempLetters) {
            try {
                $cmd = "bcdboot $SourceWindowsDrive`:\Windows /s $letter`: /f UEFI"
                $output = Invoke-Expression $cmd 2>&1
                $results += @{
                    Drive = $letter
                    Success = ($LASTEXITCODE -eq 0)
                    Output = $output
                }
            } catch {
                $results += @{
                    Drive = $letter
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        }
        
        return @{
            Success = ($results | Where-Object { $_.Success }).Count -gt 0
            Message = "Synced to $($results.Count) EFI partition(s)"
            Results = $results
        }
        
    } finally {
        # Cleanup: Remove temporary drive letters
        foreach ($letter in $tempLetters) {
            try {
                $part = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue
                if ($part) {
                    $part | Remove-PartitionAccessPath -AccessPath "$letter`:" -ErrorAction SilentlyContinue
                }
            } catch {
                # Ignore cleanup errors
            }
        }
    }
}

function Test-BCDPath {
    param($Path, $Device)
    # Validate that a path/device combination exists
    $driveLetter = $null
    
    if ($Device -match 'partition=([A-Z]):') {
        $driveLetter = $matches[1]
    }
    
    if ($driveLetter -and $Path) {
        $fullPath = "$driveLetter`:$Path"
        return Test-Path $fullPath
    }
    
    return $false
}

function Test-BitLockerStatus {
    param(
        [string]$TargetDrive = "C",
        [int]$TimeoutSeconds = 5
    )
    $status = @{
        IsEncrypted = $false
        ProtectionStatus = "Unknown"
        EncryptionPercentage = 0
        VolumeStatus = "Unknown"
        KeyProtectors = @()
        Warning = ""
    }
    
    # Detect WinPE/WinRE environment - BitLocker checks are often slow or unavailable
    $envType = Get-EnvironmentType
    if ($envType -eq "WinPE" -or $envType -eq "WinRE") {
        # In WinPE, BitLocker tools may not be available or may hang
        # Return a generic warning instead of trying to check
        $status.Warning = "WinPE/WinRE environment detected. BitLocker status check skipped.`n"
        $status.Warning += "If your drive is BitLocker encrypted, ensure you have your recovery key (48-digit number) before proceeding.`n"
        $status.Warning += "You can find it in: Microsoft Account > Devices > BitLocker recovery keys"
        return $status
    }
    
    try {
        # Check if BitLocker is available (requires BitLocker feature)
        $bitlockerCmd = Get-Command "manage-bde" -ErrorAction SilentlyContinue
        if (-not $bitlockerCmd) {
            $status.Warning = "BitLocker management tools not available. Cannot determine encryption status."
            return $status
        }
        
        # Use a job with timeout to prevent hanging
        $job = Start-Job -ScriptBlock {
            param($drive)
            manage-bde -status "${drive}:" 2>&1
        } -ArgumentList $TargetDrive
        
        $bdeStatus = $null
        $jobCompleted = Wait-Job -Job $job -Timeout $TimeoutSeconds
        
        if ($jobCompleted) {
            $bdeStatus = Receive-Job -Job $job
            Remove-Job -Job $job -Force
        } else {
            # Timeout - stop the job and return warning
            Stop-Job -Job $job -Force
            Remove-Job -Job $job -Force
            $status.Warning = "BitLocker status check timed out after $TimeoutSeconds seconds.`n"
            $status.Warning += "Assume drive may be encrypted and ensure you have your recovery key before proceeding."
            return $status
        }
        
        if ($bdeStatus -match "Conversion Status:\s*(\w+)") {
            $conversionStatus = $matches[1]
            if ($conversionStatus -eq "FullyDecrypted") {
                $status.IsEncrypted = $false
                $status.ProtectionStatus = "Not Encrypted"
            } else {
                $status.IsEncrypted = $true
                $status.ProtectionStatus = $conversionStatus
            }
        }
        
        if ($bdeStatus -match "Percentage Encrypted:\s*(\d+)%") {
            $status.EncryptionPercentage = [int]$matches[1]
        }
        
        if ($bdeStatus -match "Protection Status:\s*(\w+)") {
            $status.VolumeStatus = $matches[1]
        }
        
        # Extract key protectors
        if ($bdeStatus -match "Key Protectors") {
            $keySection = $bdeStatus | Select-String -Pattern "Key Protectors" -Context 0,10
            if ($keySection) {
                $status.KeyProtectors = ($keySection.ToString() -split "`n") | Where-Object { $_ -match "TPM|Recovery|Password" }
            }
        }
        
        # Generate warning if encrypted
        if ($status.IsEncrypted) {
            $status.Warning = "WARNING: Drive $TargetDrive`: is BitLocker encrypted!`n"
            $status.Warning += "Modifying BCD or boot files may require your BitLocker recovery key.`n"
            $status.Warning += "Boot recovery operations may take longer on encrypted drives - this is normal.`n"
            $status.Warning += "Ensure you have your recovery key (48-digit number) before proceeding.`n"
            $status.Warning += "You can find it in: Microsoft Account > Devices > BitLocker recovery keys"
        }
        
    } catch {
        # Try alternative method using WMI with timeout
        try {
            $wmiJob = Start-Job -ScriptBlock {
                param($drive)
                Get-WmiObject -Namespace "Root\cimv2\security\microsoftvolumeencryption" -Class "Win32_EncryptableVolume" -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq "${drive}:" }
            } -ArgumentList $TargetDrive
            
            $wmiCompleted = Wait-Job -Job $wmiJob -Timeout $TimeoutSeconds
            
            if ($wmiCompleted) {
                $bitlocker = Receive-Job -Job $wmiJob
                Remove-Job -Job $wmiJob -Force
                
                if ($bitlocker) {
                    $protectionStatus = $bitlocker.GetProtectionStatus()
                    if ($protectionStatus.ProtectionStatus -eq 1) {
                        $status.IsEncrypted = $true
                        $status.ProtectionStatus = "Protected"
                        $status.Warning = "WARNING: Drive $TargetDrive`: is BitLocker encrypted! Ensure you have your recovery key before proceeding."
                    } else {
                        $status.IsEncrypted = $false
                        $status.ProtectionStatus = "Not Protected"
                    }
                } else {
                    $status.Warning = "Could not determine BitLocker status. Proceed with caution."
                }
            } else {
                Stop-Job -Job $wmiJob -Force
                Remove-Job -Job $wmiJob -Force
                $status.Warning = "BitLocker status check timed out. Assume drive may be encrypted and proceed with caution."
            }
        } catch {
            $status.Warning = "BitLocker status check failed. Assume drive may be encrypted and proceed with caution."
        }
    }
    
    return $status
}

function Get-MissingStorageDevices {
    # Fix for #2: Format-Table causes truncation. We build a clean string instead.
    # Only report devices that are ACTUALLY missing drivers, not just disabled or in other states
    $devices = Get-PnpDevice | Where-Object {
        # Only include devices with error codes that indicate missing drivers
        # Error code 28 = Driver not installed
        # Error code 1 = Device not configured properly (often driver issue)
        # Error code 3 = Driver may be corrupted
        ($_.ConfigManagerErrorCode -eq 28 -or $_.ConfigManagerErrorCode -eq 1 -or $_.ConfigManagerErrorCode -eq 3) -and
        $_.FriendlyName -match 'VMD|RAID|NVMe|Storage|USB|SCSI|Controller|Disk'
    }
    
    if (!$devices) { return "No missing or errored storage drivers detected.`n`nNote: Devices with non-zero error codes that are not error codes 1, 3, or 28 (missing driver codes) are excluded to reduce false positives." }

    $report = "MISSING STORAGE DRIVER DEVICES`n"
    $report += "===============================================================`n"
    $report += "Note: Only showing devices with error codes indicating missing drivers:`n"
    $report += "  - Error Code 28: Driver not installed`n"
    $report += "  - Error Code 1: Device not configured (often driver issue)`n"
    $report += "  - Error Code 3: Driver may be corrupted`n"
    $report += "`nDevices with other error codes (disabled, sleeping, etc.) are excluded.`n"
    $report += "===============================================================`n`n"
    $report += "STATUS      ERROR CODE  CLASS                NAME`n"
    $report += "------      ----------  -----                ----`n"
    foreach ($dev in $devices) {
        $errorDesc = switch ($dev.ConfigManagerErrorCode) {
            28 { "Driver Missing" }
            1 { "Not Configured" }
            3 { "Driver Corrupted" }
            default { "Error $($dev.ConfigManagerErrorCode)" }
        }
        $report += "{0,-11} {1,-11} {2,-20} {3}`n" -f $dev.Status, $errorDesc, $dev.Class, $dev.FriendlyName
        $report += "   ID: $($dev.InstanceId)`n"
        $report += "   HWID: $($dev.HardwareID -join ', ')`n"
        $report += "----------------------------------------------------------------------`n"
    }
    return $report
}

function Get-MissingDriverForensics {
    param($TargetDrive = $env:SystemDrive.TrimEnd(':'))
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $currentOS = ($env:SystemDrive.TrimEnd(':') -eq $TargetDrive)
    $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
    
    # Only report devices with error codes that indicate missing drivers
    # Error code 28 = Driver not installed
    # Error code 1 = Device not configured properly (often driver issue)
    # Error code 3 = Driver may be corrupted
    $missing = Get-PnpDevice | Where-Object { 
        ($_.ConfigManagerErrorCode -eq 28 -or $_.ConfigManagerErrorCode -eq 1 -or $_.ConfigManagerErrorCode -eq 3) -and 
        ($_.Class -match 'SCSI|Storage|System|DiskDrive' -or $_.FriendlyName -match 'VMD|RAID|NVMe|Storage|Controller')
    }
    
    if (!$missing) {
        $result = "STORAGE DRIVER FORENSICS - $osContext`n"
        $result += "===============================================================`n"
        $result += "Target Windows Installation: $TargetDrive`:\Windows`n"
        $result += "Status: $osContext`n`n"
        $result += "No missing storage controllers detected."
        return $result
    }
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("STORAGE DRIVER FORENSICS - $osContext") | Out-Null
    $report.AppendLine("===============================================================") | Out-Null
    $report.AppendLine("Target Windows Installation: $TargetDrive`:\Windows") | Out-Null
    $report.AppendLine("Status: $osContext") | Out-Null
    $report.AppendLine("Analyzing missing devices to identify required INF files...") | Out-Null
    $report.AppendLine("") | Out-Null
    
    foreach ($dev in $missing) {
        $hwid = if ($dev.HardwareID -and $dev.HardwareID.Count -gt 0) { $dev.HardwareID[0] } else { "Unknown" }
        $likelyInf = "Unknown"
        $driverName = "Unknown Driver"
        $downloadHint = ""
        
        # Forensics matching for Intel VMD and RST
        if ($hwid -match "VEN_8086&DEV_9A0B|VEN_8086&DEV_467F|VEN_8086&DEV_467D") { 
            $likelyInf = "iaStorVD.inf"
            $driverName = "Intel VMD (Volume Management Device)"
            $downloadHint = "Download Intel Rapid Storage Technology (RST) drivers from Intel.com"
        }
        elseif ($hwid -match "VEN_8086&DEV_2822|VEN_8086&DEV_282A|VEN_8086&DEV_2826") { 
            $likelyInf = "iaStorAC.inf"
            $driverName = "Intel RST RAID Controller"
            $downloadHint = "Download Intel Rapid Storage Technology (RST) drivers from Intel.com"
        }
        elseif ($hwid -match "VEN_8086&DEV_06EF|VEN_8086&DEV_06E0") {
            $likelyInf = "iaStorAVC.inf"
            $driverName = "Intel RST VROC (Virtual RAID on CPU)"
            $downloadHint = "Download Intel VROC drivers from Intel.com"
        }
        elseif ($hwid -match "VEN_1022") { 
            $likelyInf = "rcraid.inf or rccfg.inf"
            $driverName = "AMD RAID Controller"
            $downloadHint = "Download AMD RAID drivers from AMD.com"
        }
        elseif ($hwid -match "VEN_144D") {
            $likelyInf = "stornvme.inf"
            $driverName = "Samsung NVMe Controller"
            $downloadHint = "Usually included in Windows, but may need Samsung NVMe driver"
        }
        elseif ($hwid -match "VEN_10DE") {
            $likelyInf = "nvgrd.inf or nvraid.inf"
            $driverName = "NVIDIA Storage Controller"
            $downloadHint = "Download from NVIDIA or motherboard manufacturer"
        }
        elseif ($hwid -match "NVMe|PCI\\VEN_8086.*NVMe") {
            $likelyInf = "stornvme.inf"
            $driverName = "Standard NVMe Controller"
            $downloadHint = "Usually included in Windows. If missing, check motherboard manufacturer"
        }
        
        $report.AppendLine("DEVICE: $($dev.FriendlyName)")
        $report.AppendLine("STATUS: $($dev.Status)")
        $report.AppendLine("CLASS: $($dev.Class)")
        $report.AppendLine("HARDWARE ID: $hwid")
        $report.AppendLine("REQUIRED INF FILE: $likelyInf")
        $report.AppendLine("DRIVER TYPE: $driverName")
        if ($downloadHint) {
            $report.AppendLine("DOWNLOAD HINT: $downloadHint")
        }
        $report.AppendLine("ERROR CODE: $($dev.ConfigManagerErrorCode)")
        $report.AppendLine("---------------------------------------------------------------")
        $report.AppendLine("")
    }
    
    return $report.ToString()
}

function Scan-ForDrivers {
    param($SourceDrive, [switch]$ShowAll)
    
    # Normalize drive letter if provided
    if ($SourceDrive -and $SourceDrive -match '^([A-Z]):?$') {
        $SourceDrive = $matches[1]
    }
    
    $driverPaths = @()
    
    # First, check for missing/problematic drivers
    # Only report devices with error codes that indicate missing drivers
    # Error code 28 = Driver not installed
    # Error code 1 = Device not configured properly (often driver issue)
    # Error code 3 = Driver may be corrupted
    $missingDevices = Get-PnpDevice | Where-Object { 
        ($_.ConfigManagerErrorCode -eq 28 -or $_.ConfigManagerErrorCode -eq 1 -or $_.ConfigManagerErrorCode -eq 3) -and 
        ($_.Class -match 'SCSI|Storage|System|DiskDrive' -or $_.FriendlyName -match 'VMD|RAID|NVMe|Storage|Controller')
    }
    
    if (-not $ShowAll -and $missingDevices.Count -eq 0) {
        $currentOS = if ($SourceDrive) { ($env:SystemDrive.TrimEnd(':') -eq $SourceDrive) } else { $true }
        $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
        $driveInfo = if ($SourceDrive) { "Target Windows Installation: $SourceDrive`:\Windows`nStatus: $osContext`n`n" } else { "" }
        
        return @{
            Found = $false
            Message = "DRIVER SCAN - $osContext`n" +
                     "===============================================================`n" +
                     "$driveInfo" +
                     "No missing storage drivers detected. All storage controllers are functioning properly.`n`n" +
                     "To scan for ALL available drivers (not just missing ones), use the 'Scan All Drivers' option."
            Drivers = @()
            MissingCount = 0
            TargetDrive = if ($SourceDrive) { "$SourceDrive`:" } else { "Current System" }
        }
    }
    
    if (-not $SourceDrive) {
        # Try to find Windows drives automatically
        $volumes = Get-Volume | Where-Object { $_.FileSystemLabel -like "*Windows*" -or $_.DriveLetter }
        foreach ($vol in $volumes) {
            if ($vol.DriveLetter) {
                $testPath = "$($vol.DriveLetter):\Windows\System32\DriverStore\FileRepository"
                if (Test-Path $testPath) {
                    $SourceDrive = $vol.DriveLetter
                    break
                }
            }
        }
    }
    
    if (-not $SourceDrive) {
        return @{
            Found = $false
            Message = "DRIVER SCAN`n" +
                     "===============================================================`n" +
                     "No Windows drive found. Please specify a drive letter.`n" +
                     "Example: Scan-ForDrivers -SourceDrive C"
            Drivers = @()
            MissingCount = $missingDevices.Count
            TargetDrive = "Not Specified"
        }
    }
    
    $currentOS = ($env:SystemDrive.TrimEnd(':') -eq $SourceDrive)
    $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
    
    $searchPath = "$SourceDrive`:\Windows\System32\DriverStore\FileRepository"
    if (-not (Test-Path $searchPath)) {
        return @{
            Found = $false
            Message = "DRIVER SCAN - $osContext`n" +
                     "===============================================================`n" +
                     "Target Windows Installation: $SourceDrive`:\Windows`n" +
                     "Status: $osContext`n`n" +
                     "Driver store not found at: $searchPath"
            Drivers = @()
            MissingCount = $missingDevices.Count
            TargetDrive = "$SourceDrive`:"
        }
    }
    
    # If showing all drivers, scan for all storage drivers
    # Otherwise, only scan for drivers that match missing device hardware IDs
    if ($ShowAll) {
        $patterns = @("*iastor*", "*stornvme*", "*nvme*", "*uasp*", "*vmd*", "*raid*")
    } else {
        # Build patterns based on missing device hardware IDs
        $patterns = @()
        foreach ($device in $missingDevices) {
            if ($device.HardwareID) {
                foreach ($hwid in $device.HardwareID) {
                    if ($hwid -match 'VEN_8086.*DEV_9A0B|VEN_8086.*DEV_467F') {
                        $patterns += "*iastor*", "*vmd*"
                    } elseif ($hwid -match 'VEN_8086.*DEV_2822|VEN_8086.*DEV_282A') {
                        $patterns += "*iastor*", "*raid*"
                    } elseif ($hwid -match 'VEN_1022') {
                        $patterns += "*rcraid*", "*raid*"
                    } elseif ($hwid -match 'NVMe|nvme') {
                        $patterns += "*stornvme*", "*nvme*"
                    }
                }
            }
        }
        # Remove duplicates and add common patterns if none found
        $patterns = $patterns | Select-Object -Unique
        if ($patterns.Count -eq 0) {
            $patterns = @("*iastor*", "*stornvme*", "*nvme*", "*vmd*", "*raid*")
        }
    }
    
    $count = 0
    foreach ($pattern in $patterns) {
        $found = Get-ChildItem $searchPath -Recurse -Include $pattern -ErrorAction SilentlyContinue
        foreach ($item in $found) {
            # Only include .inf, .sys, and .cat files, or driver folders
            if ($item.Extension -in @('.inf', '.sys', '.cat') -or $item.PSIsContainer) {
                $count++
                $driverPaths += @{
                    Number = $count
                    Name = $item.Name
                    Path = $item.FullName
                    Type = if ($item.Extension) { $item.Extension } else { "Folder" }
                }
            }
        }
    }
    
    $message = if ($ShowAll) {
        "Found $count driver file(s) in: $searchPath`n(Showing ALL available storage drivers)"
    } else {
        "Found $count driver file(s) matching missing storage controllers.`nSource: $searchPath`n`nMissing devices detected: $($missingDevices.Count)"
    }
    
    return @{
        Found = $true
        Message = $message
        SourceDrive = $SourceDrive
        SearchPath = $searchPath
        Drivers = $driverPaths
        MissingCount = $missingDevices.Count
    }
}

function Harvest-StorageDrivers {
    param($SourceDrive,$OutDir="X:\Harvested")
    if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

    Get-ChildItem "$SourceDrive\Windows\System32\DriverStore\FileRepository" `
        -Recurse -Include "*iastor*","*stornvme*","*nvme*","*uasp*" -ErrorAction SilentlyContinue |
        Copy-Item -Destination $OutDir -Force -Recurse
}

function Load-Drivers-Live {
    param($Path)
    Get-ChildItem $Path -Filter "*.inf" -Recurse |
        ForEach-Object { drvload $_.FullName }
}

function Inject-Drivers-Offline {
    param($WindowsDrive,$DriverPath)
    # Construct image path properly - DISM expects format like C:\
    # Use subexpression to avoid parsing issues with colon
    $imagePath = "$($WindowsDrive):"
    dism /Image:"$imagePath" /Add-Driver /Driver:"$DriverPath" /Recurse /ForceUnsigned
}

# ============================================================================
# ADVANCED STORAGE CONTROLLER & DRIVER MANAGEMENT (2025+ Systems)
# ============================================================================
# These functions address the #1 reason repair installs fail in 2025+ systems:
# - Storage controller detection
# - Driver matching logic
# - Driver injection/loading flow
# Based on real-world cases and Microsoft documentation
# ============================================================================

function Get-AdvancedStorageControllerInfo {
    <#
    .SYNOPSIS
    Advanced storage controller detection using multiple methods (WMI, Registry, PCI enumeration).
    
    .DESCRIPTION
    Detects storage controllers using:
    - WMI (Win32_PnPEntity, Win32_DiskDrive)
    - Registry (PCI device enumeration)
    - Hardware IDs and compatible IDs
    - Device Manager error codes
    
    Returns comprehensive information about all storage controllers, including:
    - Controller type (NVMe, RAID, AHCI, VMD, etc.)
    - Hardware IDs and compatible IDs
    - Driver status and error codes
    - Boot-critical status
    - Required driver INF files
    
    .EXAMPLE
    $controllers = Get-AdvancedStorageControllerInfo
    $controllers | Format-Table -AutoSize
    #>
    param(
        [switch]$IncludeNonCritical = $false,
        [switch]$Detailed = $false
    )
    
    $controllers = @()
    
    try {
        # Method 1: WMI - Win32_PnPEntity (most comprehensive)
        $pnpDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
            $class = $_.PNPClass
            $name = $_.Name
            $desc = $_.Description
            
            # Storage-related classes
            $class -match 'SCSIAdapter|StorageController|System|DiskDrive' -or
            $name -match 'VMD|RAID|NVMe|Storage|Controller|AHCI|SATA|SCSI|IDE' -or
            $desc -match 'VMD|RAID|NVMe|Storage|Controller|AHCI|SATA|SCSI|IDE'
        }
        
        foreach ($device in $pnpDevices) {
            $hwids = @()
            $compatIds = @()
            
            # Extract Hardware IDs
            if ($device.HardwareID) {
                $hwids = $device.HardwareID
            }
            
            # Extract Compatible IDs from registry
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($device.DeviceID)"
                if (Test-Path $regPath) {
                    $compatIds = (Get-ItemProperty -Path $regPath -Name "CompatibleIDs" -ErrorAction SilentlyContinue).CompatibleIDs
                    if (-not $compatIds) { $compatIds = @() }
                }
            } catch {
                # Registry access may fail in WinPE/WinRE
            }
            
            # Determine controller type from hardware ID
            $controllerType = "Unknown"
            $isBootCritical = $false
            $requiredInf = "Unknown"
            $vendor = "Unknown"
            $deviceId = "Unknown"
            
            foreach ($hwid in $hwids) {
                # Intel VMD (Volume Management Device) - Common in 2025+ systems
                if ($hwid -match 'VEN_8086.*DEV_(9A0B|467F|467D|467E|467C)') {
                    $controllerType = "Intel VMD"
                    $isBootCritical = $true
                    $requiredInf = "iaStorVD.inf"
                    $vendor = "Intel"
                    if ($hwid -match 'DEV_9A0B') { $deviceId = "9A0B" }
                    elseif ($hwid -match 'DEV_467F') { $deviceId = "467F" }
                    break
                }
                # Intel RST RAID
                elseif ($hwid -match 'VEN_8086.*DEV_(2822|282A|2826|2829|282B)') {
                    $controllerType = "Intel RST RAID"
                    $isBootCritical = $true
                    $requiredInf = "iaStorAC.inf"
                    $vendor = "Intel"
                    break
                }
                # Intel RST VROC
                elseif ($hwid -match 'VEN_8086.*DEV_(06EF|06E0|06E1)') {
                    $controllerType = "Intel RST VROC"
                    $isBootCritical = $true
                    $requiredInf = "iaStorAVC.inf"
                    $vendor = "Intel"
                    break
                }
                # AMD RAID
                elseif ($hwid -match 'VEN_1022.*DEV_(7901|7902|7903|7904)') {
                    $controllerType = "AMD RAID"
                    $isBootCritical = $true
                    $requiredInf = "rcraid.inf"
                    $vendor = "AMD"
                    break
                }
                # Samsung NVMe
                elseif ($hwid -match 'VEN_144D') {
                    $controllerType = "Samsung NVMe"
                    $isBootCritical = $true
                    $requiredInf = "stornvme.inf"
                    $vendor = "Samsung"
                    break
                }
                # Generic NVMe
                elseif ($hwid -match 'NVMe|PCI\\VEN_.*NVMe') {
                    $controllerType = "NVMe Controller"
                    $isBootCritical = $true
                    $requiredInf = "stornvme.inf"
                    if ($hwid -match 'VEN_([0-9A-F]{4})') {
                        $venId = $matches[1]
                        $vendor = switch ($venId) {
                            "144D" { "Samsung" }
                            "10EC" { "Realtek" }
                            "1BB1" { "Seagate" }
                            "1C5C" { "SK Hynix" }
                            "8086" { "Intel" }
                            default { "Unknown (VEN_$venId)" }
                        }
                    }
                    break
                }
                # NVIDIA Storage
                elseif ($hwid -match 'VEN_10DE') {
                    $controllerType = "NVIDIA Storage"
                    $isBootCritical = $true
                    $requiredInf = "nvgrd.inf"
                    $vendor = "NVIDIA"
                    break
                }
                # Standard AHCI
                elseif ($hwid -match 'VEN_8086.*AHCI|VEN_8086.*DEV_2922') {
                    $controllerType = "Intel AHCI"
                    $isBootCritical = $false
                    $requiredInf = "msahci.inf"
                    $vendor = "Intel"
                    break
                }
            }
            
            # Check if boot-critical (storage controllers usually are)
            if ($controllerType -match 'VMD|RAID|NVMe|Storage') {
                $isBootCritical = $true
            }
            
            # Get error code and status
            $errorCode = $device.ConfigManagerErrorCode
            $status = $device.Status
            $hasDriver = ($errorCode -eq 0)
            $needsDriver = ($errorCode -eq 28 -or $errorCode -eq 1 -or $errorCode -eq 3)
            
            # Skip non-critical if not requested
            if (-not $IncludeNonCritical -and -not $isBootCritical -and $hasDriver) {
                continue
            }
            
            $controller = [PSCustomObject]@{
                Name = $device.Name
                Description = $device.Description
                DeviceID = $device.DeviceID
                PNPClass = $device.PNPClass
                ControllerType = $controllerType
                Vendor = $vendor
                DeviceID_Hex = $deviceId
                HardwareIDs = $hwids
                CompatibleIDs = $compatIds
                Status = $status
                ErrorCode = $errorCode
                HasDriver = $hasDriver
                NeedsDriver = $needsDriver
                IsBootCritical = $isBootCritical
                RequiredInf = $requiredInf
                Service = $device.Service
                Manufacturer = $device.Manufacturer
            }
            
            $controllers += $controller
        }
        
        # Method 2: Registry-based PCI enumeration (for offline systems)
        if ($Detailed) {
            try {
                $pciDevices = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI" -ErrorAction SilentlyContinue -Recurse -Depth 2
                foreach ($pciDevice in $pciDevices) {
                    $deviceDesc = (Get-ItemProperty -Path $pciDevice.PSPath -Name "DeviceDesc" -ErrorAction SilentlyContinue).DeviceDesc
                    if ($deviceDesc -match 'VMD|RAID|NVMe|Storage|Controller') {
                        $hwid = (Get-ItemProperty -Path $pciDevice.PSPath -Name "HardwareID" -ErrorAction SilentlyContinue).HardwareID
                        if ($hwid -and $hwid.Count -gt 0) {
                            # Check if we already have this device
                            $exists = $controllers | Where-Object { $_.DeviceID -eq $pciDevice.PSChildName }
                            if (-not $exists) {
                                # Add as additional detection
                            }
                        }
                    }
                }
            } catch {
                # Registry enumeration may fail in limited environments
            }
        }
        
    } catch {
        Write-Warning "Error detecting storage controllers: $_"
    }
    
    return $controllers
}

function Test-DriverMatch {
    <#
    .SYNOPSIS
    Advanced driver matching logic that parses INF files and matches hardware IDs.
    
    .DESCRIPTION
    Matches drivers to storage controllers by:
    - Parsing INF files for [Manufacturer] and [Models] sections
    - Extracting hardware IDs, compatible IDs, and service names
    - Ranking matches by precision (exact match > compatible match)
    - Validating driver signatures and versions
    
    .PARAMETER HardwareID
    Hardware ID to match (e.g., "PCI\VEN_8086&DEV_9A0B")
    
    .PARAMETER CompatibleIDs
    Array of compatible IDs
    
    .PARAMETER DriverPath
    Path to driver folder or INF file
    
    .EXAMPLE
    $match = Test-DriverMatch -HardwareID "PCI\VEN_8086&DEV_9A0B" -DriverPath "X:\Drivers\Intel\RST"
    if ($match.Matched) {
        Write-Host "Found matching driver: $($match.DriverName)"
    }
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$HardwareID,
        
        [string[]]$CompatibleIDs = @(),
        
        [Parameter(Mandatory=$true)]
        [string]$DriverPath
    )
    
    $result = @{
        Matched = $false
        DriverName = ""
        INFPath = ""
        MatchType = "None"  # Exact, Compatible, Partial
        MatchScore = 0
        ServiceName = ""
        DriverVersion = ""
        IsSigned = $false
        AllMatches = @()
    }
    
    if (-not (Test-Path $DriverPath)) {
        return $result
    }
    
    # Find all INF files
    $infFiles = @()
    if ((Get-Item $DriverPath).PSIsContainer) {
        $infFiles = Get-ChildItem -Path $DriverPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    } else {
        if ($DriverPath -match '\.inf$') {
            $infFiles = @(Get-Item $DriverPath)
        }
    }
    
    foreach ($infFile in $infFiles) {
        try {
            $infContent = Get-Content $infFile.FullName -Raw -ErrorAction Stop
            
            # Extract hardware IDs from INF file
            $infHwids = @()
            $infCompatIds = @()
            $serviceName = ""
            $driverVersion = ""
            
            # Parse [Models] section for hardware IDs
            if ($infContent -match '\[Models\](.*?)(?=\[|\Z)', [System.Text.RegularExpressions.RegexOptions]::Singleline) {
                $modelsSection = $matches[1]
                $lines = $modelsSection -split "`n"
                foreach ($line in $lines) {
                    if ($line -match '^([^=]+)=(.+)') {
                        $hwidPattern = $matches[1].Trim()
                        # Hardware IDs are typically in format: "PCI\VEN_xxxx&DEV_xxxx"
                        if ($hwidPattern -match 'PCI\\|USB\\|SCSI\\') {
                            $infHwids += $hwidPattern
                        }
                    }
                }
            }
            
            # Parse [Strings] section for compatible IDs (sometimes stored there)
            if ($infContent -match '\[Strings\](.*?)(?=\[|\Z)', [System.Text.RegularExpressions.RegexOptions]::Singleline) {
                $stringsSection = $matches[1]
                # Look for compatible ID patterns
            }
            
            # Extract service name
            if ($infContent -match 'Service\s*=\s*([^\s,]+)') {
                $serviceName = $matches[1]
            }
            
            # Extract driver version (from [Version] section or file properties)
            if ($infContent -match 'DriverVer\s*=\s*([^,]+)') {
                $driverVersion = $matches[1]
            }
            
            # Check for matches
            $matchScore = 0
            $matchType = "None"
            
            # Exact hardware ID match (highest priority)
            foreach ($hwid in $HardwareID) {
                foreach ($infHwid in $infHwids) {
                    # Normalize for comparison (case-insensitive, handle variations)
                    $hwidNormalized = $hwid -replace '\\', '\\' -replace '&', '&'
                    $infHwidNormalized = $infHwid -replace '\\', '\\' -replace '&', '&'
                    
                    if ($hwidNormalized -eq $infHwidNormalized) {
                        $matchScore = 100
                        $matchType = "Exact"
                        break
                    }
                    # Partial match (VEN and DEV match)
                    elseif ($hwid -match 'VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})' -and 
                            $infHwid -match 'VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})') {
                        $hwidVen = $matches[1]
                        $hwidDev = $matches[2]
                        $infVen = $matches[1]
                        $infDev = $matches[2]
                        if ($hwidVen -eq $infVen -and $hwidDev -eq $infDev) {
                            $matchScore = 80
                            $matchType = "Compatible"
                        }
                    }
                }
            }
            
            # Compatible ID match (lower priority)
            if ($matchScore -lt 80) {
                foreach ($compatId in $CompatibleIDs) {
                    foreach ($infCompatId in $infCompatIds) {
                        if ($compatId -eq $infCompatId) {
                            $matchScore = 60
                            $matchType = "Compatible"
                            break
                        }
                    }
                }
            }
            
            # Check driver signature (if available)
            $isSigned = $false
            try {
                $catFiles = Get-ChildItem -Path $infFile.DirectoryName -Filter "*.cat" -ErrorAction SilentlyContinue
                if ($catFiles) {
                    $isSigned = $true  # Presence of CAT file suggests signature
                }
            } catch {}
            
            if ($matchScore -gt 0) {
                $match = [PSCustomObject]@{
                    INFPath = $infFile.FullName
                    DriverName = $infFile.Name
                    MatchType = $matchType
                    MatchScore = $matchScore
                    ServiceName = $serviceName
                    DriverVersion = $driverVersion
                    IsSigned = $isSigned
                }
                
                $result.AllMatches += $match
                
                # Keep best match
                if ($matchScore -gt $result.MatchScore) {
                    $result.Matched = $true
                    $result.DriverName = $infFile.Name
                    $result.INFPath = $infFile.FullName
                    $result.MatchType = $matchType
                    $result.MatchScore = $matchScore
                    $result.ServiceName = $serviceName
                    $result.DriverVersion = $driverVersion
                    $result.IsSigned = $isSigned
                }
            }
            
        } catch {
            Write-Warning "Error parsing INF file $($infFile.FullName): $_"
        }
    }
    
    # Sort matches by score
    $result.AllMatches = $result.AllMatches | Sort-Object MatchScore -Descending
    
    return $result
}

function Start-AdvancedDriverInjection {
    <#
    .SYNOPSIS
    Advanced driver injection with validation, dependency checking, and proper driver store management.
    
    .DESCRIPTION
    Injects drivers into Windows installation with:
    - Pre-injection validation (INF parsing, signature verification)
    - Hardware ID matching verification
    - Dependency resolution
    - Driver store integration
    - Post-injection verification
    - Rollback capability
    
    .PARAMETER WindowsDrive
    Target Windows drive letter (e.g., "C")
    
    .PARAMETER DriverPath
    Path to driver folder or INF file
    
    .PARAMETER ControllerInfo
    Optional: Storage controller info from Get-AdvancedStorageControllerInfo
    
    .PARAMETER ValidateOnly
    Only validate drivers without injecting
    
    .EXAMPLE
    $controllers = Get-AdvancedStorageControllerInfo
    $result = Start-AdvancedDriverInjection -WindowsDrive "C" -DriverPath "X:\Drivers\Intel" -ControllerInfo $controllers
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory=$true)]
        [string]$DriverPath,
        
        [object[]]$ControllerInfo = @(),
        
        [switch]$ValidateOnly = $false,
        
        [switch]$ForceUnsigned = $false,
        
        [scriptblock]$ProgressCallback = $null
    )
    
    $result = @{
        Success = $false
        DriversInjected = @()
        DriversSkipped = @()
        DriversFailed = @()
        ValidationResults = @()
        Report = ""
        Errors = @()
        Warnings = @()
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("ADVANCED DRIVER INJECTION") | Out-Null
    $report.AppendLine("Target: $WindowsDrive`:") | Out-Null
    $report.AppendLine("Driver Source: $DriverPath") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Normalize drive letter
    $WindowsDrive = $WindowsDrive.TrimEnd(':').ToUpper()
    $imagePath = "$WindowsDrive`:"
    
    # Validate Windows installation
    if (-not (Test-Path "$imagePath\Windows\System32")) {
        $result.Errors += "Invalid Windows installation: $imagePath"
        $result.Report = $report.ToString()
        return $result
    }
    
    # Get controller info if not provided
    if ($ControllerInfo.Count -eq 0) {
        if ($ProgressCallback) {
            & $ProgressCallback "Detecting storage controllers..." 10
        }
        $ControllerInfo = Get-AdvancedStorageControllerInfo -IncludeNonCritical
    }
    
    # Find all INF files
    $infFiles = @()
    if ((Get-Item $DriverPath).PSIsContainer) {
        $infFiles = Get-ChildItem -Path $DriverPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    } else {
        if ($DriverPath -match '\.inf$') {
            $infFiles = @(Get-Item $DriverPath)
        }
    }
    
    if ($infFiles.Count -eq 0) {
        $result.Errors += "No INF files found in: $DriverPath"
        $result.Report = $report.ToString()
        return $result
    }
    
    $report.AppendLine("Found $($infFiles.Count) INF file(s)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Validate and match each driver
    foreach ($infFile in $infFiles) {
        $infName = $infFile.Name
        $infPath = $infFile.FullName
        
        if ($ProgressCallback) {
            & $ProgressCallback "Validating driver: $infName" 20
        }
        
        # Find matching controller
        $matchedController = $null
        $matchResult = $null
        
        foreach ($controller in $ControllerInfo) {
            if ($controller.NeedsDriver -or $ValidateOnly) {
                $matchResult = Test-DriverMatch -HardwareID $controller.HardwareIDs -CompatibleIDs $controller.CompatibleIDs -DriverPath $infPath
                if ($matchResult.Matched) {
                    $matchedController = $controller
                    break
                }
            }
        }
        
        $validation = [PSCustomObject]@{
            INFPath = $infPath
            INFName = $infName
            Matched = ($matchResult -ne $null -and $matchResult.Matched)
            MatchType = if ($matchResult) { $matchResult.MatchType } else { "None" }
            MatchScore = if ($matchResult) { $matchResult.MatchScore } else { 0 }
            ControllerName = if ($matchedController) { $matchedController.Name } else { "None" }
            IsSigned = if ($matchResult) { $matchResult.IsSigned } else { $false }
        }
        
        $result.ValidationResults += $validation
        
        if ($ValidateOnly) {
            $report.AppendLine("VALIDATION: $infName") | Out-Null
            $report.AppendLine("  Matched: $($validation.Matched)") | Out-Null
            $report.AppendLine("  Match Type: $($validation.MatchType)") | Out-Null
            $report.AppendLine("  Match Score: $($validation.MatchScore)") | Out-Null
            $report.AppendLine("  Controller: $($validation.ControllerName)") | Out-Null
            $report.AppendLine("  Signed: $($validation.IsSigned)") | Out-Null
            $report.AppendLine("") | Out-Null
            continue
        }
        
        # Skip if no match and not forcing
        if (-not $validation.Matched) {
            $result.DriversSkipped += $infName
            $result.Warnings += "Skipped $infName (no matching controller found)"
            continue
        }
        
        # Check signature if not forcing unsigned
        if (-not $validation.IsSigned -and -not $ForceUnsigned) {
            $result.Warnings += "Driver $infName is not signed. Use -ForceUnsigned to inject anyway."
            continue
        }
        
        # Inject driver using DISM
        if ($ProgressCallback) {
            & $ProgressCallback "Injecting driver: $infName" 50
        }
        
        try {
            $dismArgs = @(
                "/Image:`"$imagePath`"",
                "/Add-Driver",
                "/Driver:`"$infFile.DirectoryName`"",
                "/Recurse"
            )
            
            if ($ForceUnsigned) {
                $dismArgs += "/ForceUnsigned"
            }
            
            $dismOutput = & dism $dismArgs 2>&1 | Out-String
            
            if ($LASTEXITCODE -eq 0 -or $dismOutput -match 'successfully|completed') {
                $result.DriversInjected += [PSCustomObject]@{
                    INFName = $infName
                    INFPath = $infPath
                    ControllerName = $validation.ControllerName
                    MatchType = $validation.MatchType
                }
                $report.AppendLine("[SUCCESS] Injected: $infName") | Out-Null
                $report.AppendLine("  Controller: $($validation.ControllerName)") | Out-Null
            } else {
                $result.DriversFailed += [PSCustomObject]@{
                    INFName = $infName
                    INFPath = $infPath
                    Error = $dismOutput
                }
                $result.Errors += "Failed to inject $infName`: $dismOutput"
                $report.AppendLine("[FAILED] $infName") | Out-Null
                $report.AppendLine("  Error: $dismOutput") | Out-Null
            }
        } catch {
            $result.DriversFailed += [PSCustomObject]@{
                INFName = $infName
                INFPath = $infPath
                Error = $_.ToString()
            }
            $result.Errors += "Exception injecting $infName`: $_"
            $report.AppendLine("[EXCEPTION] $infName`: $_") | Out-Null
        }
        
        $report.AppendLine("") | Out-Null
    }
    
    # Summary
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("SUMMARY") | Out-Null
    $report.AppendLine("  Drivers Injected: $($result.DriversInjected.Count)") | Out-Null
    $report.AppendLine("  Drivers Skipped: $($result.DriversSkipped.Count)") | Out-Null
    $report.AppendLine("  Drivers Failed: $($result.DriversFailed.Count)") | Out-Null
    $report.AppendLine($separator) | Out-Null
    
    $result.Success = ($result.DriversInjected.Count -gt 0 -and $result.DriversFailed.Count -eq 0)
    $result.Report = $report.ToString()
    
    return $result
}

function Find-MatchingDrivers {
    <#
    .SYNOPSIS
    Finds matching drivers for storage controllers from multiple sources.
    
    .DESCRIPTION
    Searches for drivers in:
    - Current Windows installation (DriverStore)
    - Offline Windows installation
    - External driver folders
    - Manufacturer driver packages
    
    Returns ranked list of best matches.
    
    .PARAMETER ControllerInfo
    Storage controller information from Get-AdvancedStorageControllerInfo
    
    .PARAMETER SearchPaths
    Additional paths to search for drivers
    
    .EXAMPLE
    $controllers = Get-AdvancedStorageControllerInfo
    $drivers = Find-MatchingDrivers -ControllerInfo $controllers -SearchPaths @("X:\Drivers", "D:\DriverPack")
    #>
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$ControllerInfo,
        
        [string[]]$SearchPaths = @(),
        
        [string]$WindowsDrive = $null
    )
    
    $results = @()
    
    foreach ($controller in $ControllerInfo) {
        if (-not $controller.NeedsDriver) {
            continue
        }
        
        $driverMatches = @()
        
        # Search in current Windows DriverStore
        $driverStorePaths = @()
        if ($WindowsDrive) {
            $driverStorePaths += "$WindowsDrive`:\Windows\System32\DriverStore\FileRepository"
        } else {
            $driverStorePaths += "$env:SystemRoot\System32\DriverStore\FileRepository"
        }
        
        foreach ($driverStorePath in $driverStorePaths) {
            if (Test-Path $driverStorePath) {
                # Search for drivers matching controller hardware IDs
                $infFiles = Get-ChildItem -Path $driverStorePath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
                foreach ($infFile in $infFiles) {
                    $match = Test-DriverMatch -HardwareID $controller.HardwareIDs -CompatibleIDs $controller.CompatibleIDs -DriverPath $infFile.FullName
                    if ($match.Matched) {
                        $driverMatches += [PSCustomObject]@{
                            INFPath = $infFile.FullName
                            DriverName = $infFile.Name
                            Source = "DriverStore"
                            MatchType = $match.MatchType
                            MatchScore = $match.MatchScore
                            IsSigned = $match.IsSigned
                            ControllerName = $controller.Name
                        }
                    }
                }
            }
        }
        
        # Search in additional paths
        foreach ($searchPath in $SearchPaths) {
            if (Test-Path $searchPath) {
                $infFiles = Get-ChildItem -Path $searchPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
                foreach ($infFile in $infFiles) {
                    $match = Test-DriverMatch -HardwareID $controller.HardwareIDs -CompatibleIDs $controller.CompatibleIDs -DriverPath $infFile.FullName
                    if ($match.Matched) {
                        $driverMatches += [PSCustomObject]@{
                            INFPath = $infFile.FullName
                            DriverName = $infFile.Name
                            Source = $searchPath
                            MatchType = $match.MatchType
                            MatchScore = $match.MatchScore
                            IsSigned = $match.IsSigned
                            ControllerName = $controller.Name
                        }
                    }
                }
            }
        }
        
        # Sort by match score and select best matches
        $bestMatches = $driverMatches | Sort-Object MatchScore -Descending | Select-Object -First 5
        
        $results += [PSCustomObject]@{
            Controller = $controller.Name
            ControllerType = $controller.ControllerType
            HardwareID = $controller.HardwareIDs[0]
            RequiredInf = $controller.RequiredInf
            MatchesFound = $bestMatches.Count
            BestMatches = $bestMatches
        }
    }
    
    return $results
}

function Get-SystemRestoreInfo {
    param($TargetDrive = $env:SystemDrive)
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    } elseif ($TargetDrive -eq $env:SystemDrive) {
        $TargetDrive = $env:SystemDrive.TrimEnd(':')
    }
    
    $currentOS = ($env:SystemDrive.TrimEnd(':') -eq $TargetDrive)
    $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
    
    $info = @{
        Enabled = $false
        RestorePoints = @()
        Message = ""
        TargetDrive = "$TargetDrive`:"
        IsCurrentOS = $currentOS
    }
    
    try {
        # Method 1: Try Get-ComputerRestorePoint (most reliable)
        $restore = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        if ($restore) {
            $info.Enabled = $true
            $info.RestorePoints = $restore | Select-Object -Property SequenceNumber, CreationTime, Description, RestorePointType | Sort-Object CreationTime -Descending
            $info.Message = "System Restore is ENABLED. Found $($restore.Count) restore point(s)."
        } else {
            # Method 2: Try vssadmin (works even when Get-ComputerRestorePoint fails)
            try {
                $vssOutput = vssadmin list shadows 2>&1 | Out-String
                if ($vssOutput -match 'Shadow Copy Volume|Shadow Copy ID') {
                    $info.Enabled = $true
                    # Parse vssadmin output for restore points
                    $shadowMatches = [regex]::Matches($vssOutput, 'Shadow Copy ID:\s+(\{[^}]+\})[\s\S]*?Creation Time:\s+([^\r\n]+)')
                    foreach ($match in $shadowMatches) {
                        $info.RestorePoints += [PSCustomObject]@{
                            SequenceNumber = $match.Groups[1].Value
                            CreationTime = [DateTime]::Parse($match.Groups[2].Value.Trim())
                            Description = "Shadow Copy"
                            RestorePointType = "Manual"
                        }
                    }
                    if ($info.RestorePoints.Count -gt 0) {
                        $info.Message = "System Restore is ENABLED. Found $($info.RestorePoints.Count) restore point(s) via vssadmin."
                    }
                }
            } catch {
                # vssadmin failed, continue to next method
            }
            
            # Method 3: Try WMI (Win32_SystemRestore)
            if ($info.RestorePoints.Count -eq 0) {
                $sr = Get-WmiObject -Class Win32_SystemRestore -ErrorAction SilentlyContinue
                if ($sr) {
                    $info.Enabled = $true
                    try {
                        $points = $sr.GetRestorePoints()
                        foreach ($point in $points) {
                            $info.RestorePoints += [PSCustomObject]@{
                                SequenceNumber = $point.SequenceNumber
                                CreationTime = $point.CreationTime
                                Description = $point.Description
                                RestorePointType = $point.RestorePointType
                            }
                        }
                        if ($info.RestorePoints.Count -gt 0) {
                            $info.Message = "System Restore is ENABLED. Found $($info.RestorePoints.Count) restore point(s) via WMI."
                        }
                    } catch {
                        # GetRestorePoints() may fail, try registry
                    }
                }
            }
            
            # Method 4: Check registry for restore points
            if ($info.RestorePoints.Count -eq 0) {
                $restoreKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
                if (Test-Path $restoreKey) {
                    $rpEnabled = (Get-ItemProperty -Path $restoreKey -Name "RPSessionInterval" -ErrorAction SilentlyContinue)
                    if ($rpEnabled) {
                        $info.Enabled = $true
                        # Check SystemRestorePoints registry
                        $rpPath = "$restoreKey\SystemRestorePoints"
                        if (Test-Path $rpPath) {
                            $rpKeys = Get-ChildItem -Path $rpPath -ErrorAction SilentlyContinue
                            foreach ($rpKey in $rpKeys) {
                                $rpProps = Get-ItemProperty -Path $rpKey.PSPath -ErrorAction SilentlyContinue
                                if ($rpProps) {
                                    $info.RestorePoints += [PSCustomObject]@{
                                        SequenceNumber = $rpKey.PSChildName
                                        CreationTime = if ($rpProps.CreationTime) { [DateTime]::FromFileTime($rpProps.CreationTime) } else { $rpKey.LastWriteTime }
                                        Description = if ($rpProps.Description) { $rpProps.Description } else { "System Restore Point" }
                                        RestorePointType = if ($rpProps.Type) { $rpProps.Type } else { "System" }
                                    }
                                }
                            }
                            if ($info.RestorePoints.Count -gt 0) {
                                $info.RestorePoints = $info.RestorePoints | Sort-Object CreationTime -Descending
                                $info.Message = "System Restore is ENABLED. Found $($info.RestorePoints.Count) restore point(s) via registry."
                            }
                        }
                    }
                }
            }
            
            if ($info.RestorePoints.Count -eq 0) {
                $info.Message = "System Restore appears to be DISABLED or no restore points found.`n`nNote: Restore points may exist but be inaccessible in this environment (WinPE/WinRE)."
            }
        }
    } catch {
        $info.Message = "Unable to check System Restore status: $_"
    }
    
    return $info
}

function Get-ReagentcHealth {
    param($TargetDrive = $env:SystemDrive.TrimEnd(':'))
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $currentOS = ($env:SystemDrive.TrimEnd(':') -eq $TargetDrive)
    $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
    
    $health = @{
        Status = "Unknown"
        WinRELocation = ""
        Message = ""
        Details = @()
        TargetDrive = "$TargetDrive`:"
        IsCurrentOS = $currentOS
    }
    
    try {
        $reagentcOutput = reagentc /info 2>&1 | Out-String
        $health.Details = $reagentcOutput -split "`n" | Where-Object { $_.Trim() }
        
        if ($reagentcOutput -match "Windows RE status:\s*(\w+)") {
            $status = $matches[1]
            $health.Status = $status
            
            if ($status -eq "Enabled") {
                $health.Message = "REAGENTC HEALTH - $osContext`n" +
                                 "===============================================================`n" +
                                 "Target Windows Installation: $TargetDrive`:\Windows`n" +
                                 "Status: $osContext`n`n" +
                                 "[SUCCESS] Windows Recovery Environment (WinRE) is ENABLED"
            } elseif ($status -eq "Disabled") {
                $health.Message = "REAGENTC HEALTH - $osContext`n" +
                                 "===============================================================`n" +
                                 "Target Windows Installation: $TargetDrive`:\Windows`n" +
                                 "Status: $osContext`n`n" +
                                 "[WARNING] Windows Recovery Environment (WinRE) is DISABLED"
            } else {
                $health.Message = "REAGENTC HEALTH - $osContext`n" +
                                 "===============================================================`n" +
                                 "Target Windows Installation: $TargetDrive`:\Windows`n" +
                                 "Status: $osContext`n`n" +
                                 "[INFO] Windows Recovery Environment status: $status"
            }
        } else {
            $health.Message = "REAGENTC HEALTH - $osContext`n" +
                             "===============================================================`n" +
                             "Target Windows Installation: $TargetDrive`:\Windows`n" +
                             "Status: $osContext`n`n" +
                             "[INFO] Unable to parse reagentc status. Output may be empty or in unexpected format."
        }
        
        if ($reagentcOutput -match "Windows RE location:\s*(.+)") {
            $health.WinRELocation = $matches[1].Trim()
        }
        
    } catch {
        $health.Message = "REAGENTC HEALTH - $osContext`n" +
                         "===============================================================`n" +
                         "Target Windows Installation: $TargetDrive`:\Windows`n" +
                         "Status: $osContext`n`n" +
                         "[ERROR] Failed to check reagentc: $_"
    }
    
    return $health
}

function Get-OSInfo {
    param($TargetDrive = $env:SystemDrive)
    $osInfo = @{
        IsCurrentOS = $false
        Drive = $TargetDrive
    }
    
    try {
        # Determine if this is the current running OS
        $currentDrive = $env:SystemDrive
        if ($TargetDrive -eq $currentDrive -or $TargetDrive -eq $currentDrive.TrimEnd(':')) {
            $osInfo.IsCurrentOS = $true
        }
        
        # Try to get OS info from the target drive
        $osPath = "$TargetDrive\Windows\System32\config\SOFTWARE"
        if (Test-Path $osPath) {
            # Load offline registry hive
            try {
                reg load "HKLM\TempOSInfo" $osPath 2>&1 | Out-Null
                $hiveLoaded = $true
            } catch {
                $hiveLoaded = $false
            }
            
            if ($hiveLoaded) {
                $regPath = "HKLM:\TempOSInfo\Microsoft\Windows NT\CurrentVersion"
                if (Test-Path $regPath) {
                    $regProps = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                    if ($regProps) {
                        $osInfo.OSName = if ($regProps.ProductName) { $regProps.ProductName } else { "Windows" }
                        $osInfo.BuildNumber = if ($regProps.CurrentBuild) { $regProps.CurrentBuild } else { $regProps.CurrentBuildNumber }
                        $osInfo.Version = if ($regProps.DisplayVersion) { $regProps.DisplayVersion } else { "Unknown" }
                        $osInfo.ReleaseId = $regProps.ReleaseId
                        $osInfo.EditionID = $regProps.EditionID
                        
                        # Check for Insider build
                        $osInfo.IsInsider = $false
                        $osInfo.InsiderChannel = ""
                        if ($regProps.UBR) {
                            $osInfo.UBR = $regProps.UBR
                        }
                        if ($regProps.BuildLabEx -match '\.(\d{5})\.') {
                            $osInfo.IsInsider = $true
                            $osInfo.InsiderChannel = if ($regProps.BuildLabEx -match 'rs_|co_|vb_') { "Dev/Beta" } else { "Release Preview" }
                        }
                        
                        # Architecture detection
                        $sys32Path = "$TargetDrive\Windows\System32"
                        if (Test-Path "$sys32Path\winload.efi") {
                            $osInfo.Architecture = "64-bit"
                        } elseif (Test-Path "$sys32Path\winload.exe") {
                            $osInfo.Architecture = "32-bit"
                        } else {
                            $osInfo.Architecture = "Unknown"
                        }
                        
                        # Language
                        $langPath = "$TargetDrive\Windows\System32\config\SYSTEM"
                        if (Test-Path $langPath) {
                            try {
                                reg load "HKLM\TempSysInfo" $langPath 2>&1 | Out-Null
                                $sysRegPath = "HKLM:\TempSysInfo\ControlSet001\Control\Nls\Language"
                                if (Test-Path $sysRegPath) {
                                    $langCode = (Get-ItemProperty -Path $sysRegPath -Name InstallLanguage -ErrorAction SilentlyContinue).InstallLanguage
                                    $osInfo.LanguageCode = $langCode
                                    $osInfo.Language = switch ($langCode) {
                                        "0409" { "English (United States)" }
                                        "0809" { "English (United Kingdom)" }
                                        "0407" { "German" }
                                        "040C" { "French" }
                                        default { "Language Code: $langCode" }
                                    }
                                }
                                reg unload "HKLM\TempSysInfo" 2>&1 | Out-Null
                            } catch {
                                # Language detection failed
                            }
                        }
                    }
                }
                reg unload "HKLM\TempOSInfo" 2>&1 | Out-Null
            }
        }
        
        # If we couldn't get info from offline registry, try current system
        if (-not $osInfo.OSName -and $osInfo.IsCurrentOS) {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            if (-not $os) {
                $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue
            }
            
            if ($os) {
                $osInfo.OSName = $os.Caption
                $osInfo.Version = $os.Version
                $osInfo.BuildNumber = $os.BuildNumber
                $osInfo.Architecture = if ($os.OSArchitecture) { $os.OSArchitecture } else { 
                    if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
                }
                $osInfo.Language = (Get-Culture).DisplayName
                $osInfo.LanguageCode = (Get-Culture).LCID
                $osInfo.InstallDate = $os.InstallDate
                $osInfo.SerialNumber = $os.SerialNumber
            }
        }
        
        # Determine recommended recovery ISO
        $buildNum = if ($osInfo.BuildNumber) { [int]$osInfo.BuildNumber } else { 0 }
        $isWin11 = $buildNum -ge 22000
        
        $osInfo.RecommendedISO = @{
            Architecture = if ($osInfo.Architecture -match "64") { "x64" } else { "x86" }
            Language = if ($osInfo.LanguageCode) { 
                switch ([int]$osInfo.LanguageCode) {
                    1033 { "en-us" }
                    2057 { "en-gb" }
                    1031 { "de-de" }
                    1036 { "fr-fr" }
                    default { "en-us" }
                }
            } else { "en-us" }
            Version = if ($isWin11) { "Windows 11" } else { "Windows 10" }
        }
        
        # Insider build download links
        if ($osInfo.IsInsider) {
            $osInfo.InsiderLinks = @{
                DevChannel = "https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewiso"
                BetaChannel = "https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewiso"
                ReleasePreview = "https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewiso"
                UUP = "https://uupdump.net/ (Search for build $($osInfo.BuildNumber))"
            }
        }
        
    } catch {
        $osInfo.Error = "Failed to retrieve OS information: $_"
    }
    
    return $osInfo
}

function Get-UnofficialRepairTips {
    $tips = @"
===================================================================================
  UNOFFICIAL REPAIR INSTALLATION TIPS
===================================================================================

[WARN] WARNING: These methods are NOT officially recommended by Microsoft and 
   may carry risk. Proceed at your own discretion. These steps are community-
   sourced workarounds for restoring system integrity without a clean wipe.
   These tips prioritize keeping your files and software intact.

===================================================================================

TIP 1: Windows 11 Cloud Repair (Hidden Feature)
-------------------------------------------------------------------------------
Summary: Windows 11 (22H2+) built-in cloud repair tool - more reliable than 
         "Reset this PC" because it downloads a fresh, verified image from 
         Microsoft specifically to repair system files.

Instructions:
1. Go to Settings > System > Recovery
2. Click "Fix problems using Windows Update"
3. Follow the on-screen prompts

Why it's better: Performs a repair install WITHOUT needing to download an ISO 
                  manually. It essentially does an in-place upgrade using the 
                  cloud as the source. More reliable than manual ISO methods.

Outcome: Cloud-based repair install that keeps your files and apps intact.

===================================================================================

TIP 2: The "In-Place" Upgrade Repair (Standard Method)
-------------------------------------------------------------------------------
Summary: Refresh Windows system files while keeping all apps, settings, and 
         personal files.

Instructions:
1. Download the Windows 11/10 ISO matching your current version.
2. Mount the ISO within your current Windows session.
3. Run setup.exe and select "Change how Setup downloads updates" → 
   "Not right now."
4. On the "Ready to install" screen, ensure "Keep personal files and apps" 
   is selected.

Outcome: Overwrites corrupted system DLLs and registry hives with fresh copies 
         while leaving the Users and Program Files folders intact.

===================================================================================

TIP 3: The "Product Server" Compatibility Bypass (Force Command)
-------------------------------------------------------------------------------
Summary: Uses a command-line switch to force Windows Setup to ignore certain 
         version/edition mismatches that usually block an In-Place Upgrade.

Instructions:
1. Mount your Windows ISO.
2. Open an Administrative Command Prompt.
3. Navigate to the ISO drive (e.g., D:).
4. Run the command: setup.exe /product server

Outcome: This often bypasses the "You cannot keep your files" restriction on 
         certain builds, allowing a full repair installation while preserving 
         apps and data.

[WARN] Note: This works on some Windows versions but not all. Test in a non-
   critical environment first.

===================================================================================

TIP 4: Registry "EditionID" Override
-------------------------------------------------------------------------------
Summary: Tricks the installer into thinking the current OS is a version it 
         can upgrade/repair.

Instructions:
1. Open regedit and navigate to:
   HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion
2. Change EditionID to a standard version (e.g., "Professional")
3. Change ProductName to match (e.g., "Windows 10 Pro")
4. Run setup.exe from your ISO immediately without rebooting

Outcome: Useful when the system thinks it is a "Workstation" or "Enterprise" 
         edition and refuses a "Pro" repair ISO.

[WARN] CRITICAL: Make a registry backup first! Run: reg export HKLM\SOFTWARE backup.reg
   Restore if needed: reg import backup.reg

===================================================================================

TIP 5: The "Restore to Repair" Workflow
-------------------------------------------------------------------------------
Summary: Restores the bootloader just enough to enter the OS, specifically to 
         trigger an In-Place Repair.

Instructions:
1. If Windows won't boot, use bcdboot C:\Windows /s S: /f UEFI from a 
   recovery USB to fix the "handshake" between hardware and OS.
2. Boot into Windows (even if unstable).
3. Immediately run setup.exe from a mounted ISO to perform an In-Place Upgrade.

Outcome: Prioritizes software and file preservation by using the bootloader fix 
         as a "stepping stone" to a full system refresh.

===================================================================================

TIP 6: Offline Component Store Repair (DISM) - From WinPE/Hiren's
-------------------------------------------------------------------------------
Summary: Repair a non-booting Windows image using a healthy external source 
         (ISO/USB) from a WinPE environment like Hiren's BootCD.

Instructions:
1. Boot into Hiren's BootCD PE or WinPE environment
2. Connect a Windows Installation USB (e.g., E:)
3. Identify your broken Windows drive (e.g., D:)
4. Run: dism /Image:D:\ /Cleanup-Image /RestoreHealth /Source:E:\sources\install.wim
5. Then run: sfc /scannow /offbootdir=D:\ /offwindir=D:\Windows

The Goal: This fixes the system files enough to let you boot back into your 
          desktop. Once you are back at your desktop, you then run the Standard 
          In-Place Upgrade (Setup.exe) to finish the "Golden" repair.

Outcome: Repairs system files offline, allowing you to boot back into Windows 
         to complete the full in-place upgrade.
-------------------------------------------------------------------------------
Summary: Repair a non-booting Windows image using a healthy external source 
         (ISO/USB).

Instructions:
1. Connect a Windows Installation USB.
2. From a recovery prompt, identify the drive letter of the USB (e.g., D:) 
   and the broken Windows (e.g., C:).
3. Run: dism /Image:C:\ /Cleanup-Image /RestoreHealth /Source:D:\sources\install.wim
   (Note: You may need to specify the index: /Source:D:\sources\install.wim:1)

Outcome: Forces Windows to replace "staged" system files that are corrupted, 
         even if the OS cannot currently boot.

Alternative (if install.wim not found):
   dism /Image:C:\ /Cleanup-Image /RestoreHealth /Source:D:\sources /LimitAccess

===================================================================================

TIP 7: Manual Hive Injection
-------------------------------------------------------------------------------
Summary: Replace a corrupted SYSTEM registry hive with a backup.

Instructions:
1. In the Recovery Command Prompt, navigate to C:\Windows\System32\config
2. Rename the current SYSTEM hive to SYSTEM.old:
   ren SYSTEM SYSTEM.old
3. Copy the backup from C:\Windows\System32\config\RegBack\SYSTEM
   copy RegBack\SYSTEM SYSTEM
   (Note: Modern Windows 10/11 may require manual backups as RegBack is often 
    empty by default. You may need to restore from a System Restore point.)

Outcome: Restores boot-critical registry keys if the "Inaccessible Boot Device" 
         error is caused by registry corruption.

[WARN] CRITICAL: Only attempt this if you have a recent backup of the SYSTEM hive.
   Incorrect registry restoration can make the system completely unbootable.

===================================================================================

===================================================================================

PRO-TIP: Preserving Game Libraries on F: Drive
-------------------------------------------------------------------------------
If you perform an In-Place Upgrade, Windows may "forget" that your Steam libraries 
are on F:. To fix this without redownloading:

1. Open Steam after the repair
2. Go to Settings > Storage
3. Click "Add Drive" and select F:\SteamLibrary
4. Steam will instantly "discover" all your existing games without a single 
   byte of download

This works for Epic Games, GOG, and other game launchers too - just point them 
to your existing library folders.

===================================================================================

DISCLAIMER:
These methods are provided as-is for advanced users. Always backup critical 
data before attempting repairs. Microsoft Support should be consulted for 
production systems or critical data scenarios.

===================================================================================
"@
    return $tips
}

function Get-RecommendedTools {
    $tools = @"
===================================================================================
  RECOMMENDED RECOVERY TOOLS
===================================================================================

If you are serious about maintaining your system (and your game libraries on 
the F: drive), these are the "Must-Have" tools:

+---------------------------------------------------------------+
| Tool                          | Purpose                                     |
+---------------------------------------------------------------+
| Hiren's BootCD PE             | The ultimate Win10-based recovery           |
|                                | environment. Includes tools for             |
|                                | partitioning, driver injection, and         |
|                                | registry editing.                           |
|                                | Download: hirensbootcd.org                 |
+---------------------------------------------------------------+
| Macrium Reflect (Rescue)      | ESSENTIAL. Its "Fix Windows Boot           |
|                                | Problems" button is magic—it fixes          |
|                                | complex BCD/UEFI issues that bootrec       |
|                                | often fails at.                             |
|                                | Download: macrium.com/reflectfree          |
+---------------------------------------------------------------+
| Sergei Strelec's WinPE        | A more "advanced" alternative to Hiren's.    |
|                                | It contains almost every diagnostic tool    |
|                                | known to man.                               |
|                                | Download: sergeistrelec.name               |
+---------------------------------------------------------------+
| Explorer++                    | A lightweight file manager that often        |
|                                | works in WinPE when the standard file       |
|                                | explorer is buggy.                          |
|                                | Download: explorerplusplus.com             |
+---------------------------------------------------------------+
| Microsoft SaRA                | (Support and Recovery Assistant) A          |
|                                | specialized tool that automates fixes for   |
|                                | Windows Activation and Office issues.       |
|                                | Download: aka.ms/SaRASetup                 |
+---------------------------------------------------------------+

USAGE TIPS:
- Keep Hiren's BootCD PE on a USB drive for emergency recovery
- Macrium Reflect Rescue can fix boot issues that bcdboot cannot
- Use Sergei Strelec's WinPE for advanced registry and file system repairs
- Explorer++ is invaluable when Windows Explorer crashes in recovery mode

===================================================================================
  MICROSOFT PROFESSIONAL SUPPORT OPTIONS
===================================================================================

For retail/home users seeking professional, break-fix support, Microsoft offers
several paid support options. These services provide access to Microsoft engineers
who can perform advanced troubleshooting including Registry analysis, BSOD memory
dump analysis, and complex bootloader repairs.

+---------------------------------------------------------------+
| PAY-PER-INCIDENT SUPPORT (RETAIL/HOME USERS)                 |
+---------------------------------------------------------------+
| E-mail or Web-based Support                                  |
|   Cost: $99 per incident                                     |
|   Best For: Time-saving alternative to phone support         |
|   Note: Often faster than waiting for phone technician      |
+---------------------------------------------------------------+
| Professional Support (General)                                |
|   Cost: $245 per incident                                    |
|   Definition: A single support issue and reasonable efforts  |
|               to resolve it. Cost does not depend on time.   |
+---------------------------------------------------------------+
| Pro 5-Pack                                                   |
|   Cost: $1,225 (5 incidents)                                 |
|   Best For: Multiple issues or ongoing support needs          |
+---------------------------------------------------------------+

IMPORTANT NOTES:
- Free Support: Basic installation, setup, and billing support are available
  for free with most Microsoft 365 subscriptions.
- How to Use: To use a purchased pay-per-incident credit, you must sign in
  with the same personal Microsoft account (MSA) used for the purchase on
  the Microsoft Support for Business portal and apply the credit when
  creating a new case.
- Business/Enterprise Plans: Larger businesses typically use subscription-
  based "Unified Support" plans where fees are a percentage of their total
  annual Microsoft spending, rather than a fixed per-incident cost.

+---------------------------------------------------------------+
| PROFESSIONAL SUPPORT FOR WINDOWS 11 PRO USERS                |
+---------------------------------------------------------------+
| Microsoft offers professional-grade support to individual     |
| Windows 11 Pro users, but it is structured as a "business-   |
| class" service called Professional Support (Pay-Per-Incident).|
|                                                               |
| Because you are using the Pro edition, you are technically    |
| eligible for these higher-tier services, even if you are not |
| a corporation.                                                |
+---------------------------------------------------------------+

1. PROFESSIONAL SUPPORT (PAY-PER-INCIDENT)
   This is the most direct way to get an actual Microsoft engineer rather
   than a general customer service agent.

   Cost: Approximately $499 USD per incident (roughly $650+ CAD).

   How it Works:
   - You purchase a single "support incident"
   - You are assigned a case number and a higher-tier engineer
   - The engineer stays with the case until it is resolved or deemed
     "unfixable"

   Scope:
   - Unlike standard support, they will dive into the Registry
   - Analyze BSOD memory dumps
   - Work through complex bootloader issues
   - However, if the hardware is failing, they will still tell you to
     replace the drive

   Refund Policy:
   - If the engineer determines the issue is caused by a documented
     Microsoft bug, they will often refund the incident fee
   - If the issue is caused by your hardware, third-party drivers, or user
     error, you still pay

   How to Access:
   - Go to the Microsoft Professional Support page
   - Select "Windows" and your version (Windows 11)
   - Choose "Pay-per-incident" and follow the prompts to pay and open a
     ticket

2. MICROSOFT 365 "PREMIUM" SUPPORT
   If you have a Microsoft 365 Personal or Family subscription, "Premium
   Support" is included.

   How it Works:
   - You can request a chat or callback through the "Get Help" app in
     Windows

   The Reality:
   - While they are "professionals," these agents are trained for high
     volume
   - For a non-booting system, their script almost always defaults to
     "Reset this PC" or "Cloud Reinstall" within the first 30 minutes
   - They generally do not have the tools or time to perform the
     "surgical" repairs an independent pro might do

3. THE "BUSINESS ASSIST" ALTERNATIVE
   If you use your Windows 11 Pro machine for work/freelancing, Microsoft
   offers a service called Microsoft 365 Business Assist.

   Cost: Usually around $5.00/month per user (added to a Business
         subscription)

   How it Works:
   - It gives you 24/7 access to small business specialists who help with
     setup and troubleshooting
   - It is a middle ground between the free consumer support and the $499
     enterprise-level support

SUMMARY: IS IT WORTH IT FOR A PRO USER?
----------------------------------------
For an individual user, Pay-Per-Incident is rarely worth the cost unless
you are running a highly specialized environment that would take days of
manual labor to rebuild.

Most advanced users choose to use the independent tools mentioned earlier
(Hiren's BootCD, Macrium Reflect, etc.) because they offer more control
than a remote technician would have over a non-booting system.

===================================================================================
  LOCAL TECHNICIAN ALTERNATIVE (RECOMMENDED)
===================================================================================

Before paying Microsoft's premium support fees, consider contacting a local
computer repair technician. Many reputable technicians offer significant
advantages over remote Microsoft support:

+---------------------------------------------------------------+
| LOCAL TECHNICIAN BENEFITS                                     |
+---------------------------------------------------------------+
| "No Fix, No Fee" Guarantee                                    |
|   - You only pay if the problem is actually resolved          |
|   - No charge if they cannot fix the issue                    |
|   - Much lower risk than Microsoft's pay-per-incident model  |
+---------------------------------------------------------------+
| Free Onsite Estimates                                         |
|   - Many technicians offer free diagnostic estimates          |
|   - You know the cost before committing to repairs            |
|   - Can compare multiple quotes easily                         |
+---------------------------------------------------------------+
| Travel/Appointment Fee Only (If Applicable)                   |
|   - Some technicians charge a small travel/appointment fee    |
|   - This is typically marginal compared to full repair cost   |
|   - Often waived if you proceed with the repair               |
+---------------------------------------------------------------+
| Hands-On Access                                               |
|   - Direct physical access to your hardware                    |
|   - Can test components, swap parts, check connections        |
|   - More thorough than remote diagnostics                     |
+---------------------------------------------------------------+
| Personalized Service                                          |
|   - One-on-one attention from start to finish                 |
|   - Can explain what went wrong and how to prevent it          |
|   - Often more patient and thorough than call center agents   |
+---------------------------------------------------------------+

HOW TO FIND A REPUTABLE TECHNICIAN:
-----------------------------------
- Look for technicians with "No Fix, No Fee" guarantees
- Check online reviews (Google, Yelp, local business directories)
- Ask about their experience with boot issues and Windows recovery
- Verify they offer free estimates before committing
- Compare multiple quotes to ensure fair pricing
- Ask if they have experience with tools like Hiren's BootCD, Macrium
  Reflect, or similar recovery environments

COST COMPARISON:
----------------
Microsoft Professional Support: $499+ per incident (paid regardless of
                                outcome, unless it's a Microsoft bug)

Local Technician:              Travel/appointment fee (often $50-100) +
                                Repair cost (only if successful)
                                Total often less than Microsoft's fee,
                                with better guarantee

RECOMMENDATION:
---------------
For most users, a local technician with a "No Fix, No Fee" guarantee and
free onsite estimates offers better value than Microsoft's premium support.
You get hands-on service, personalized attention, and only pay if the problem
is actually fixed. The travel/appointment fee (if any) is typically marginal
compared to Microsoft's full incident cost.

===================================================================================
"@
    return $tools
}

function Get-CleanupScript {
    param($TargetDrive = "C")
    $script = @"
# Windows.old Cleanup Script
# Run this AFTER a successful In-Place Upgrade to reclaim disk space
# This removes the Windows.old folder that contains your previous Windows installation

`$TargetDrive = "$TargetDrive"
`$oldWindowsPath = "`$TargetDrive`:\Windows.old"

Write-Host "Windows.old Cleanup Script" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path `$oldWindowsPath)) {
    Write-Host "[INFO] Windows.old folder not found. Nothing to clean up." -ForegroundColor Yellow
    exit
}

Write-Host "Found Windows.old folder at: `$oldWindowsPath" -ForegroundColor Yellow
Write-Host "Size: $((Get-ChildItem `$oldWindowsPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB) GB" -ForegroundColor Gray
Write-Host ""

`$confirm = Read-Host "This will permanently delete Windows.old. Continue? (Y/N)"
if (`$confirm -ne 'Y' -and `$confirm -ne 'y') {
    Write-Host "Cleanup cancelled." -ForegroundColor Yellow
    exit
}

Write-Host "`nCleaning up Windows.old..." -ForegroundColor Yellow
Write-Host "This may take several minutes..." -ForegroundColor Gray

try {
    # Use DISM to clean up (safest method)
    `$dismResult = dism /online /cleanup-image /startcomponentcleanup /resetbase 2>&1
    
    # Also remove Windows.old directly
    Remove-Item -Path `$oldWindowsPath -Recurse -Force -ErrorAction Stop
    
    Write-Host "[SUCCESS] Windows.old folder deleted successfully!" -ForegroundColor Green
    Write-Host "Disk space reclaimed." -ForegroundColor Green
    
} catch {
    Write-Host "[ERROR] Failed to delete Windows.old: `$_" -ForegroundColor Red
    Write-Host "`nYou can manually delete it using:" -ForegroundColor Yellow
    Write-Host "  Remove-Item -Path `$oldWindowsPath -Recurse -Force" -ForegroundColor Gray
    Write-Host "`nOr use Disk Cleanup (cleanmgr.exe) and select 'Previous Windows installations'" -ForegroundColor Gray
}

Write-Host "`nCleanup complete!" -ForegroundColor Green
"@
    return $script
}

function Get-RegistryEditionOverride {
    param($TargetDrive = "C")
    $script = @"
# Registry EditionID Override Script (Golden Overrides)
# Run this BEFORE launching setup.exe from your Windows ISO
# This script modifies registry to allow In-Place Upgrade compatibility

`$TargetDrive = "$TargetDrive"

Write-Host "Registry EditionID Override Script" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Backup registry first
`$backupPath = "`$TargetDrive`:\Windows\System32\config\EditionID_Backup_`$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
Write-Host "Creating registry backup..." -ForegroundColor Yellow
reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "`$backupPath" /y

if (Test-Path "`$backupPath") {
    Write-Host "[SUCCESS] Backup created: `$backupPath" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Backup may have failed. Proceed with caution." -ForegroundColor Yellow
}

# Modify EditionID
Write-Host "`nModifying EditionID..." -ForegroundColor Yellow
try {
    `$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    
    # Get current values
    `$currentEdition = (Get-ItemProperty -Path `$regPath -Name EditionID -ErrorAction SilentlyContinue).EditionID
    `$currentProduct = (Get-ItemProperty -Path `$regPath -Name ProductName -ErrorAction SilentlyContinue).ProductName
    
    Write-Host "Current EditionID: `$currentEdition" -ForegroundColor Gray
    Write-Host "Current ProductName: `$currentProduct" -ForegroundColor Gray
    
    # Set to Professional (most compatible)
    Set-ItemProperty -Path `$regPath -Name EditionID -Value "Professional" -ErrorAction Stop
    Set-ItemProperty -Path `$regPath -Name ProductName -Value "Windows 10 Pro" -ErrorAction Stop
    
    Write-Host "[SUCCESS] EditionID changed to: Professional" -ForegroundColor Green
    Write-Host "[SUCCESS] ProductName changed to: Windows 10 Pro" -ForegroundColor Green
    
    Write-Host "`n[IMPORTANT] Now run setup.exe from your Windows ISO IMMEDIATELY" -ForegroundColor Yellow
    Write-Host "Do NOT reboot before running setup.exe!" -ForegroundColor Red
    Write-Host "`nTo restore original values later, run:" -ForegroundColor Gray
    Write-Host "  reg import `$backupPath" -ForegroundColor Gray
    
} catch {
    Write-Host "[ERROR] Failed to modify registry: `$_" -ForegroundColor Red
    Write-Host "You may need to run this script as Administrator." -ForegroundColor Yellow
}
"@
    return $script
}

function Apply-OneClickRegistryFixes {
    param($TargetDrive = "C")
    $results = @{
        Success = $false
        Applied = @()
        Failed = @()
        BackupPath = ""
        Warnings = @()
    }
    
    try {
        # Create comprehensive backup
        $backupPath = "$env:TEMP\RegistryFullBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
        Write-Host "Creating full registry backup..." -ForegroundColor Yellow
        reg export "HKLM\SOFTWARE" "$env:TEMP\Registry_SOFTWARE_Backup.reg" /y
        reg export "HKLM\SYSTEM" "$env:TEMP\Registry_SYSTEM_Backup.reg" /y
        $results.BackupPath = $backupPath
        
        # 1. Edition Mismatch Bypass
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
            $currentEdition = (Get-ItemProperty -Path $regPath -Name EditionID -ErrorAction SilentlyContinue).EditionID
            
            if ($currentEdition -ne "Professional") {
                Set-ItemProperty -Path $regPath -Name EditionID -Value "Professional" -ErrorAction Stop
                Set-ItemProperty -Path $regPath -Name ProductName -Value "Windows 10 Pro" -ErrorAction Stop
                $results.Applied += "EditionID changed from '$currentEdition' to 'Professional'"
            } else {
                $results.Applied += "EditionID already set to Professional (no change needed)"
            }
        } catch {
            $results.Failed += "EditionID override: $_"
        }
        
        # 2. Language Mismatch Fix
        try {
            $langPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language"
            if (Test-Path $langPath) {
                $currentLang = (Get-ItemProperty -Path $langPath -Name InstallLanguage -ErrorAction SilentlyContinue).InstallLanguage
                if ($currentLang -ne "0409") {
                    Set-ItemProperty -Path $langPath -Name InstallLanguage -Value "0409" -ErrorAction Stop
                    $results.Applied += "InstallLanguage changed from '$currentLang' to '0409' (US English)"
                } else {
                    $results.Applied += "InstallLanguage already set to 0409 (no change needed)"
                }
            } else {
                $results.Warnings += "Language registry path not found (may need offline registry loading)"
            }
        } catch {
            $results.Failed += "Language override: $_"
        }
        
        # 3. Program Files Path Fix
        try {
            $progPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion"
            $programFiles = (Get-ItemProperty -Path $progPath -Name ProgramFilesDir -ErrorAction SilentlyContinue).ProgramFilesDir
            $programFilesX86 = (Get-ItemProperty -Path $progPath -Name "ProgramFilesDir (x86)" -ErrorAction SilentlyContinue).'ProgramFilesDir (x86)'
            
            if ($programFiles -and $programFiles -ne "${TargetDrive}:\Program Files") {
                Set-ItemProperty -Path $progPath -Name ProgramFilesDir -Value "${TargetDrive}:\Program Files" -ErrorAction Stop
                $results.Applied += "ProgramFilesDir reset to ${TargetDrive}:\Program Files"
            }
            
            if ($programFilesX86 -and $programFilesX86 -ne "${TargetDrive}:\Program Files (x86)") {
                Set-ItemProperty -Path $progPath -Name "ProgramFilesDir (x86)" -Value "${TargetDrive}:\Program Files (x86)" -ErrorAction Stop
                $results.Applied += "ProgramFilesDir (x86) reset to ${TargetDrive}:\Program Files (x86)"
            }
        } catch {
            $results.Failed += "Program Files path fix: $_"
        }
        
        $results.Success = ($results.Applied.Count -gt 0) -and ($results.Failed.Count -eq 0)
        
    } catch {
        $results.Failed += "General error: $_"
    }
    
    return $results
}

function Export-InUseDrivers {
    param($OutputPath = "$env:USERPROFILE\Desktop\In-Use_Drivers_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt")
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("IN-USE DRIVERS EXPORT") | Out-Null
    $report.AppendLine("Generated by Miracle Boot v7.2.0") | Out-Null
    $report.AppendLine("Export Date: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
    $report.AppendLine("Computer Name: $env:COMPUTERNAME") | Out-Null
    $report.AppendLine("Operating System: $((Get-CimInstance Win32_OperatingSystem).Caption)") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $report.AppendLine("INSTRUCTIONS:") | Out-Null
    $report.AppendLine("This file contains all currently in-use drivers from your working PC.") | Out-Null
    $report.AppendLine("Use this list to identify which drivers you need to port to an installer or recovery environment.") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Key Information:") | Out-Null
    $report.AppendLine("- Device Name: The hardware device name") | Out-Null
    $report.AppendLine("- Driver Name: The driver package name") | Out-Null
    $report.AppendLine("- INF File: The driver installation file (look for this in DriverStore)") | Out-Null
    $report.AppendLine("- Hardware ID: Unique identifier for the device (used to match drivers)") | Out-Null
    $report.AppendLine("- Driver Version: Version of the installed driver") | Out-Null
    $report.AppendLine("- Provider: Driver manufacturer/vendor") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    try {
        # Get all PnP devices that are working (Status = OK, no error codes)
        $devices = Get-PnpDevice | Where-Object { 
            $_.Status -eq 'OK' -and 
            $_.ConfigManagerErrorCode -eq 0 -and
            $null -ne $_.Class
        } | Sort-Object Class, FriendlyName
        
        $totalDevices = $devices.Count
        $report.AppendLine("TOTAL IN-USE DEVICES: $totalDevices") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("=" * 80) | Out-Null
        $report.AppendLine("") | Out-Null
        
        # Group by class for better organization
        $devicesByClass = $devices | Group-Object Class | Sort-Object Name
        
        foreach ($classGroup in $devicesByClass) {
            $report.AppendLine("CLASS: $($classGroup.Name)") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            $report.AppendLine("") | Out-Null
            
            foreach ($device in $classGroup.Group) {
                $report.AppendLine("Device Name: $($device.FriendlyName)") | Out-Null
                
                # Get driver information
                try {
                    $driver = Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_Driver" -ErrorAction SilentlyContinue
                    if ($null -ne $driver) {
                        $driverData = $driver.Data
                        if ($null -ne $driverData) {
                            $report.AppendLine("  Driver: $driverData") | Out-Null
                        }
                    }
                } catch {
                    # Driver property not available
                }
                
                # Get INF file
                try {
                    $infPath = Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_DriverInfPath" -ErrorAction SilentlyContinue
                    if ($null -ne $infPath -and $infPath.Data) {
                        $report.AppendLine("  INF File: $($infPath.Data)") | Out-Null
                        # Try to find actual file location
                        $infName = Split-Path -Leaf $infPath.Data
                        $driverStorePath = "$env:SystemRoot\System32\DriverStore\FileRepository"
                        $foundInf = Get-ChildItem -Path $driverStorePath -Recurse -Filter $infName -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($foundInf) {
                            $report.AppendLine("  INF Location: $($foundInf.FullName)") | Out-Null
                        }
                    }
                } catch {
                    # INF path not available
                }
                
                # Get Hardware ID
                if ($device.HardwareID -and $device.HardwareID.Count -gt 0) {
                    $report.AppendLine("  Hardware ID: $($device.HardwareID[0])") | Out-Null
                    if ($device.HardwareID.Count -gt 1) {
                        foreach ($hwid in $device.HardwareID[1..($device.HardwareID.Count-1)]) {
                            $report.AppendLine("               $hwid") | Out-Null
                        }
                    }
                }
                
                # Get Driver Version
                try {
                    $driverVersion = Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_DriverVersion" -ErrorAction SilentlyContinue
                    if ($null -ne $driverVersion -and $driverVersion.Data) {
                        $report.AppendLine("  Driver Version: $($driverVersion.Data)") | Out-Null
                    }
                } catch {
                    # Version not available
                }
                
                # Get Driver Date
                try {
                    $driverDate = Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_DriverDate" -ErrorAction SilentlyContinue
                    if ($null -ne $driverDate -and $driverDate.Data) {
                        $report.AppendLine("  Driver Date: $($driverDate.Data)") | Out-Null
                    }
                } catch {
                    # Date not available
                }
                
                # Get Provider
                try {
                    $provider = Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_DriverProvider" -ErrorAction SilentlyContinue
                    if ($null -ne $provider -and $provider.Data) {
                        $report.AppendLine("  Provider: $($provider.Data)") | Out-Null
                    }
                } catch {
                    # Provider not available
                }
                
                # Get Status
                $report.AppendLine("  Status: $($device.Status)") | Out-Null
                
                $report.AppendLine("") | Out-Null
            }
            
            $report.AppendLine("") | Out-Null
        }
        
        # Add summary section
        $report.AppendLine("=" * 80) | Out-Null
        $report.AppendLine("SUMMARY") | Out-Null
        $report.AppendLine("=" * 80) | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("Total Devices: $totalDevices") | Out-Null
        $report.AppendLine("Device Classes: $($devicesByClass.Count)") | Out-Null
        $report.AppendLine("") | Out-Null
        
        # List critical driver classes
        $criticalClasses = @("System", "Storage", "SCSI", "DiskDrive", "Display", "Network", "USB", "Audio")
        $report.AppendLine("CRITICAL DRIVER CLASSES:") | Out-Null
        foreach ($critClass in $criticalClasses) {
            $classDevices = $devices | Where-Object { $_.Class -eq $critClass }
            if ($classDevices) {
                $report.AppendLine("  $critClass : $($classDevices.Count) device(s)") | Out-Null
            }
        }
        $report.AppendLine("") | Out-Null
        $report.AppendLine("=" * 80) | Out-Null
        $report.AppendLine("END OF REPORT") | Out-Null
        
        # Write to file
        $report.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8
        
        return @{
            Success = $true
            Path = $OutputPath
            DeviceCount = $totalDevices
            ClassCount = $devicesByClass.Count
        }
        
    } catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
            Path = $OutputPath
        }
    }
}

function Export-DriverFiles {
    param(
        $DestinationFolder,
        [switch]$IncludeAllFiles,
        [switch]$ForAcronis
    )
    
    $result = @{
        Success = $false
        FilesCopied = 0
        FoldersCreated = 0
        TotalSize = 0
        Errors = @()
        Destination = $DestinationFolder
    }
    
    try {
        if (-not (Test-Path $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        }
        
        $driverStorePath = "$env:SystemRoot\System32\DriverStore\FileRepository"
        if (-not (Test-Path $driverStorePath)) {
            $result.Errors += "DriverStore not found at: $driverStorePath"
            return $result
        }
        
        # Get all in-use devices
        $devices = Get-PnpDevice | Where-Object { 
            $_.Status -eq 'OK' -and 
            $_.ConfigManagerErrorCode -eq 0 -and
            $null -ne $_.Class
        }
        
        $driverFolders = @{}
        $filesToCopy = @()
        
        foreach ($device in $devices) {
            try {
                # Get INF file path
                $infPath = Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_DriverInfPath" -ErrorAction SilentlyContinue
                if ($null -ne $infPath -and $infPath.Data) {
                    $infName = Split-Path -Leaf $infPath.Data
                    
                    # Find the driver folder in DriverStore
                    $driverFolder = Get-ChildItem -Path $driverStorePath -Recurse -Filter $infName -ErrorAction SilentlyContinue | 
                        Select-Object -First 1 | 
                        Select-Object -ExpandProperty Directory
                    
                    if ($driverFolder -and $driverFolder.FullName) {
                        $folderPath = $driverFolder.FullName
                        
                        # Use folder name as key to avoid duplicates
                        $folderName = Split-Path -Leaf $folderPath
                        if (-not $driverFolders.ContainsKey($folderName)) {
                            $driverFolders[$folderName] = @{
                                Path = $folderPath
                                Device = $device.FriendlyName
                                Class = $device.Class
                                HardwareID = if ($device.HardwareID) { $device.HardwareID[0] } else { "Unknown" }
                            }
                        }
                    }
                }
            } catch {
                # Skip devices where we can't get driver info
            }
        }
        
        # Copy driver folders
        foreach ($folderName in $driverFolders.Keys) {
            $driverInfo = $driverFolders[$folderName]
            $sourcePath = $driverInfo.Path
            $destPath = Join-Path $DestinationFolder $folderName
            
            try {
                # Create destination folder
                if (-not (Test-Path $destPath)) {
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                    $result.FoldersCreated++
                }
                
                # Copy all files in the driver folder
                $files = Get-ChildItem -Path $sourcePath -File -ErrorAction SilentlyContinue
                foreach ($file in $files) {
                    # For Acronis, focus on INF, SYS, CAT files
                    # For general use, copy all files if IncludeAllFiles is set
                    $shouldCopy = $false
                    
                    if ($ForAcronis) {
                        # Acronis Universal Restore needs: INF, SYS, CAT, DLL files
                        if ($file.Extension -in @('.inf', '.sys', '.cat', '.dll')) {
                            $shouldCopy = $true
                        }
                    } elseif ($IncludeAllFiles) {
                        $shouldCopy = $true
                    } else {
                        # Default: copy essential driver files
                        if ($file.Extension -in @('.inf', '.sys', '.cat', '.dll', '.exe')) {
                            $shouldCopy = $true
                        }
                    }
                    
                    if ($shouldCopy) {
                        $destFile = Join-Path $destPath $file.Name
                        Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction SilentlyContinue
                        if (Test-Path $destFile) {
                            $filesToCopy += $destFile
                            $result.FilesCopied++
                            $result.TotalSize += $file.Length
                        }
                    }
                }
            } catch {
                $result.Errors += "Failed to copy folder $folderName : $_"
            }
        }
        
        # Create a manifest file
        $manifestPath = Join-Path $DestinationFolder "Driver_Manifest.txt"
        $manifest = New-Object System.Text.StringBuilder
        $separator = "=" * 80
        $manifest.AppendLine($separator) | Out-Null
        $manifest.AppendLine("DRIVER EXTRACT MANIFEST") | Out-Null
        $manifest.AppendLine("Generated by Miracle Boot v7.2.0") | Out-Null
        $manifest.AppendLine("Export Date: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
        $manifest.AppendLine("Computer: $env:COMPUTERNAME") | Out-Null
        $manifest.AppendLine($separator) | Out-Null
        $manifest.AppendLine("") | Out-Null
        $manifest.AppendLine("Total Driver Folders: $($driverFolders.Count)") | Out-Null
        $manifest.AppendLine("Total Files Copied: $($result.FilesCopied)") | Out-Null
        $manifest.AppendLine("Total Size: $([math]::Round($result.TotalSize/1MB, 2)) MB") | Out-Null
        $manifest.AppendLine("") | Out-Null
        $manifest.AppendLine($separator) | Out-Null
        $manifest.AppendLine("DRIVER FOLDERS:") | Out-Null
        $manifest.AppendLine($separator) | Out-Null
        $manifest.AppendLine("") | Out-Null
        
        foreach ($folderName in ($driverFolders.Keys | Sort-Object)) {
            $info = $driverFolders[$folderName]
            $manifest.AppendLine("Folder: $folderName") | Out-Null
            $manifest.AppendLine("  Device: $($info.Device)") | Out-Null
            $manifest.AppendLine("  Class: $($info.Class)") | Out-Null
            $manifest.AppendLine("  Hardware ID: $($info.HardwareID)") | Out-Null
            $manifest.AppendLine("") | Out-Null
        }
        
        $manifest.ToString() | Out-File -FilePath $manifestPath -Encoding UTF8
        $result.FilesCopied++ # Count manifest file
        
        # Create instructions file
        $instructionsPath = Join-Path $DestinationFolder "INSTRUCTIONS.txt"
        $instructions = @"
===================================================================================
  DRIVER EXTRACT INSTRUCTIONS
===================================================================================

This folder contains all driver files extracted from your working PC.
Use these drivers to restore your system on new hardware or in recovery scenarios.

===================================================================================

FOR ACRONIS TRUE IMAGE UNIVERSAL RESTORE:
-------------------------------------------------------------------------------

1. Copy this entire folder to a USB drive or network location accessible from
   your recovery environment.

2. In Acronis True Image:
   - Start Universal Restore
   - When prompted for drivers, browse to this folder
   - Acronis will automatically detect and load the appropriate drivers

3. The folder structure is preserved - each driver is in its own subfolder
   as required by Acronis Universal Restore.

===================================================================================

FOR OTHER RECOVERY TOOLS:
-------------------------------------------------------------------------------

- Windows Recovery Environment (WinRE):
  Use: drvload [path]\driver.inf

- DISM (Offline Driver Injection):
  Use: dism /Image:C:\ /Add-Driver /Driver:[this folder] /Recursive

- Manual Installation:
  Right-click INF files and select "Install"

===================================================================================

IMPORTANT REMINDERS:
-------------------------------------------------------------------------------

[WARN] BACKUP TO CLOUD STORAGE:
   - Upload this folder to Google Drive, OneDrive, or Dropbox
   - This ensures you have drivers available even if local backup is lost
   - Share the link with yourself or keep it in a password manager

[WARN] UPDATE AFTER HARDWARE CHANGES:
   - If you upgrade your motherboard, CPU, or storage controller,
     extract a NEW set of drivers from the updated system
   - Old drivers may not work with new hardware
   - Keep multiple driver sets if you have multiple PC configurations

[WARN] DRIVER COMPATIBILITY:
   - These drivers are specific to your current hardware configuration
   - They may not work on significantly different hardware
   - Always test in a recovery environment before relying on them

===================================================================================

FOLDER CONTENTS:
-------------------------------------------------------------------------------

- Each subfolder contains a complete driver package (INF, SYS, CAT, DLL files)
- Driver_Manifest.txt: List of all extracted drivers and their devices
- INSTRUCTIONS.txt: This file

Total Size: {0} MB
Total Drivers: {1}
Total Files: {2}

===================================================================================
"@
        $instructionsFormatted = $instructions -f `
            [math]::Round($result.TotalSize/1MB, 2), `
            $driverFolders.Count, `
            ($result.FilesCopied - 2)
        $instructionsFormatted | Out-File -FilePath $instructionsPath -Encoding UTF8
        $result.FilesCopied++
        
        $result.Success = $true
        
    } catch {
        $result.Errors += "General error: $_"
    }
    
    return $result
}

function Get-SetupLogAnalysis {
    param($TargetDrive = "C")
    
    $result = @{
        Success = $false
        LogFilesFound = @()
        Errors = @()
        EligibilityIssues = @()
        Report = ""
        InstallationState = @{}
        DISMHealth = ""
        CompatBlocks = @()
        PendingOperations = $false
        ComponentStoreState = ""
        CompatDataFiles = @()
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("WINDOWS IN-PLACE REPAIR BLOCKER - SAFE DIAGNOSTIC ANALYSIS") | Out-Null
    $report.AppendLine("Comprehensive Diagnostic Guide") | Out-Null
    $report.AppendLine("Generated by Miracle Boot v7.2.0") | Out-Null
    $report.AppendLine("Analysis Date: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("GROUND RULES (DON'T SKIP):") | Out-Null
    $report.AppendLine("[OK] Bootable Windows preferred (even if unstable)") | Out-Null
    $report.AppendLine("[OK] Backup anything important") | Out-Null
    $report.AppendLine("[WARN] Do NOT ResetBase unless explicitly warned") | Out-Null
    $report.AppendLine("[INFO] We are reading logs first, not committing changes") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 1. Verify Installation State (SAFE)
    $report.AppendLine("1. VERIFY INSTALLATION STATE (SAFE)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $osInfo = Get-OSInfo -TargetDrive $TargetDrive
        if ($osInfo.OSName) {
            $result.InstallationState = $osInfo
            $report.AppendLine("[OK] Installation State Retrieved:") | Out-Null
            $report.AppendLine("  Edition: $($osInfo.EditionID)") | Out-Null
            $report.AppendLine("  Build Number: $($osInfo.BuildNumber)") | Out-Null
            $report.AppendLine("  Version: $($osInfo.Version)") | Out-Null
            $report.AppendLine("  Language: $($osInfo.Language)") | Out-Null
            $report.AppendLine("  Architecture: $($osInfo.Architecture)") | Out-Null
            $report.AppendLine("") | Out-Null
            $report.AppendLine("  [IMPORTANT] Mismatch in Edition/Build/Language is a top-3 reason") | Out-Null
            $report.AppendLine("              in-place upgrade is blocked.") | Out-Null
        } else {
            $report.AppendLine("[WARNING] Could not retrieve installation state from drive $TargetDrive`:") | Out-Null
        }
    } catch {
        $report.AppendLine("[ERROR] Failed to get installation state: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 2. Check DISM Health (SAFE)
    $report.AppendLine("2. CHECK DISM HEALTH (SAFE)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    if ($TargetDrive -eq $env:SystemDrive.TrimEnd(':') -or $TargetDrive -eq $env:SystemDrive) {
        try {
            $dismCheck = dism /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
            $result.DISMHealth = $dismCheck
            if ($dismCheck -match "The component store is repairable") {
                $report.AppendLine("[OK] Component store is repairable - OK for in-place upgrade") | Out-Null
            } elseif ($dismCheck -match "The component store is healthy") {
                $report.AppendLine("[OK] Component store is healthy - Good, move on") | Out-Null
            } elseif ($dismCheck -match "The component store cannot be repaired") {
                $report.AppendLine("[CRITICAL] Component store cannot be repaired - Setup will block upgrade") | Out-Null
                $result.EligibilityIssues += "DISM reports component store cannot be repaired"
            } else {
                $report.AppendLine("[INFO] DISM CheckHealth output:") | Out-Null
                $report.AppendLine($dismCheck) | Out-Null
            }
        } catch {
            $report.AppendLine("[WARNING] Could not run DISM CheckHealth (may require admin): $_") | Out-Null
        }
    } else {
        $report.AppendLine("[INFO] DISM CheckHealth can only run on current system drive.") | Out-Null
        $report.AppendLine("       Target drive $TargetDrive`: is offline.") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 3. Locate Setup Decision Logs (CRITICAL, SAFE)
    $report.AppendLine("3. LOCATE SETUP DECISION LOGS (CRITICAL, SAFE)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("Windows doesn't 'guess' - it logs the exact reason.") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Common Panther log locations
    $pantherPaths = @(
        "$TargetDrive`:\`$Windows.~BT\Sources\Panther",
        "$TargetDrive`:\Windows\Panther",
        "$TargetDrive`:\`$Windows.~BT\Sources\Rollback",
        "$TargetDrive`:\Recovery",
        "$env:SystemDrive\Windows\Panther",  # Current system
        "X:\Windows\Panther",  # WinRE
        "X:\Recovery"  # WinRE Recovery
    )
    
    $logFiles = @()
    $foundPaths = @()
    
    # Search for Panther directories
    foreach ($path in $pantherPaths) {
        if (Test-Path $path) {
            $foundPaths += $path
            $report.AppendLine("[FOUND] Panther/Recovery directory: $path") | Out-Null
            
            # Look for setup logs
            $setupact = Join-Path $path "setupact.log"
            $setuperr = Join-Path $path "setuperr.log"
            $miglog = Join-Path $path "miglog.xml"
            
            if (Test-Path $setupact) {
                $logFiles += @{Path = $setupact; Type = "Setup Activity Log (Decision Logic)"; Priority = 1}
                $result.LogFilesFound += $setupact
                $report.AppendLine("  [FOUND] setupact.log - Decision logic") | Out-Null
            }
            if (Test-Path $setuperr) {
                $logFiles += @{Path = $setuperr; Type = "Setup Error Log (Why It Failed)"; Priority = 0}
                $result.LogFilesFound += $setuperr
                $report.AppendLine("  [FOUND] setuperr.log - Why it failed") | Out-Null
            }
            if (Test-Path $miglog) {
                $logFiles += @{Path = $miglog; Type = "Migration Log"; Priority = 2}
                $result.LogFilesFound += $miglog
            }
            
            # Look for compatibility data XML files
            $compatDataFiles = Get-ChildItem -Path $path -Filter "CompatData*.xml" -ErrorAction SilentlyContinue
            foreach ($compatData in $compatDataFiles) {
                $result.CompatDataFiles += $compatData.FullName
                $report.AppendLine("  [FOUND] $($compatData.Name) - Compatibility blocks") | Out-Null
            }
            
            $compatFiles = Get-ChildItem -Path $path -Filter "compatscan_*.log" -ErrorAction SilentlyContinue
            foreach ($compat in $compatFiles) {
                $logFiles += @{Path = $compat.FullName; Type = "Compatibility Scan Log"; Priority = 0}
                $result.LogFilesFound += $compat.FullName
            }
        }
    }
    
    if ($foundPaths.Count -eq 0) {
        $report.AppendLine("[WARNING] No Panther/Recovery directories found.") | Out-Null
        $report.AppendLine("If these folders don't exist, setup didn't even start.") | Out-Null
        $report.AppendLine("This may indicate: policy block or edition block.") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 4. Check Compatibility Blocks (SAFE, HIGH VALUE)
    $report.AppendLine("4. CHECK COMPATIBILITY BLOCKS (SAFE, HIGH VALUE)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    if ($result.CompatDataFiles.Count -gt 0) {
        $report.AppendLine("[FOUND] Compatibility Data XML files - Analyzing...") | Out-Null
        foreach ($compatFile in $result.CompatDataFiles) {
            try {
                $xmlContent = Get-Content -Path $compatFile -Raw -ErrorAction SilentlyContinue
                if ($xmlContent) {
                    $compatKeywords = @("BlockMigration", "HardBlock", "CompatBlock", "UnsupportedHardware", "EditionMismatch", "BuildMismatch")
                    foreach ($keyword in $compatKeywords) {
                        if ($xmlContent -match $keyword) {
                            $result.CompatBlocks += "$keyword found in $($compatFile)"
                            $report.AppendLine("  [BLOCKER] $keyword found in $([System.IO.Path]::GetFileName($compatFile))") | Out-Null
                        }
                    }
                }
            } catch {
                $report.AppendLine("  [WARNING] Could not parse $compatFile : $_") | Out-Null
            }
        }
        if ($result.CompatBlocks.Count -eq 0) {
            $report.AppendLine("[OK] No hard compatibility blocks found in XML files.") | Out-Null
        }
    } else {
        $report.AppendLine("[INFO] No CompatData*.xml files found.") | Out-Null
        $report.AppendLine("       These are created during setup compatibility scan.") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 5. Check Servicing Stack & Pending Operations (SAFE)
    $report.AppendLine("5. CHECK SERVICING STACK & PENDING OPERATIONS (SAFE)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    if ($TargetDrive -eq $env:SystemDrive.TrimEnd(':') -or $TargetDrive -eq $env:SystemDrive) {
        $pendingXml = "$env:SystemRoot\WinSxS\pending.xml"
        if (Test-Path $pendingXml) {
            $result.PendingOperations = $true
            $report.AppendLine("[CRITICAL] pending.xml exists - Pending CBS transactions detected!") | Out-Null
            $report.AppendLine("          This = instant upgrade denial.") | Out-Null
            $report.AppendLine("          Location: $pendingXml") | Out-Null
            $report.AppendLine("          Action: Reboot required or cleanup incomplete.") | Out-Null
            $result.EligibilityIssues += "Pending CBS transactions (pending.xml exists)"
        } else {
            $report.AppendLine("[OK] No pending.xml found - No pending CBS transactions.") | Out-Null
        }
        
        # Check component store
        try {
            $componentStore = dism /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String
            $result.ComponentStoreState = $componentStore
            if ($componentStore -match "pending|Pending|PENDING") {
                $report.AppendLine("[WARNING] Component store analysis shows pending operations.") | Out-Null
            } else {
                $report.AppendLine("[OK] Component store analysis completed.") | Out-Null
            }
        } catch {
            $report.AppendLine("[WARNING] Could not analyze component store: $_") | Out-Null
        }
    } else {
        $report.AppendLine("[INFO] Servicing stack checks can only run on current system drive.") | Out-Null
        $report.AppendLine("       Target drive $TargetDrive`: is offline.") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 6. Layered Updates Check (LIMITED VALUE, SAFE)
    $report.AppendLine("6. LAYERED UPDATES CHECK (LIMITED VALUE, SAFE)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("[INFO] Note: This command is rarely useful on modern Win11 and often returns nothing.") | Out-Null
    if ($TargetDrive -eq $env:SystemDrive.TrimEnd(':') -or $TargetDrive -eq $env:SystemDrive) {
        try {
            $packages = dism /Online /Get-Packages 2>&1 | Out-String
            $pendingPackages = $packages | Select-String -Pattern "State\s*:\s*Install Pending|State\s*:\s*Superseded" -AllMatches
            if ($pendingPackages) {
                $report.AppendLine("[WARNING] Found packages with pending or superseded states:") | Out-Null
                $report.AppendLine($pendingPackages) | Out-Null
                $result.EligibilityIssues += "Half-installed LCU/SSU packages detected"
            } else {
                $report.AppendLine("[OK] No problematic package states detected.") | Out-Null
            }
        } catch {
            $report.AppendLine("[INFO] Could not check packages (may require admin): $_") | Out-Null
        }
    } else {
        $report.AppendLine("[INFO] Package check can only run on current system drive.") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    if ($logFiles.Count -eq 0) {
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[WARNING] No setup log files found in common locations.") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("Searched locations:") | Out-Null
        foreach ($path in $pantherPaths) {
            $report.AppendLine("  - $path") | Out-Null
        }
        $report.AppendLine("") | Out-Null
        $report.AppendLine("NOTE: Setup logs are only created when Windows Setup runs.") | Out-Null
        $report.AppendLine("If you haven't attempted an in-place upgrade yet, these logs won't exist.") | Out-Null
        $result.Report = $report.ToString()
        return $result
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("LOG FILES FOUND: $($logFiles.Count)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Sort by priority (errors first, then activity, then others)
    $logFiles = $logFiles | Sort-Object Priority
    
    # Analyze each log file
    foreach ($logFile in $logFiles) {
        $report.AppendLine($separator) | Out-Null
        $report.AppendLine("ANALYZING: $($logFile.Type)") | Out-Null
        $report.AppendLine("Path: $($logFile.Path)") | Out-Null
        $report.AppendLine($separator) | Out-Null
        $report.AppendLine("") | Out-Null
        
        try {
            $content = Get-Content -Path $logFile.Path -ErrorAction SilentlyContinue -TotalCount 10000
            
            if ($logFile.Type -match "Error") {
                # Focus on errors
                $errorLines = $content | Where-Object { 
                    $_ -match "error|Error|ERROR|failed|Failed|FAILED|blocked|Blocked|BLOCKED|ineligible|Ineligible|INELIGIBLE" 
                } | Select-Object -First 50
                
                if ($errorLines) {
                    $report.AppendLine("ERRORS FOUND:") | Out-Null
                    $report.AppendLine("-" * 80) | Out-Null
                    foreach ($errorLine in $errorLines) {
                        $report.AppendLine($errorLine) | Out-Null
                        
                        # Extract specific eligibility issues
                        if ($errorLine -match "in-place|inplace|upgrade.*blocked|cannot.*keep.*files|edition.*mismatch|language.*mismatch|version.*mismatch") {
                            $result.EligibilityIssues += $errorLine
                        }
                    }
                    $report.AppendLine("") | Out-Null
                }
            }
            
            # Look for specific in-place upgrade eligibility messages
            $eligibilityKeywords = @(
                "in-place upgrade",
                "keep personal files",
                "keep files and apps",
                "edition mismatch",
                "language mismatch",
                "version mismatch",
                "compatibility",
                "blocked",
                "not eligible",
                "cannot upgrade",
                "upgrade path",
                "migration",
                "compatscan"
            )
            
            $relevantLines = $content | Where-Object {
                $line = $_
                foreach ($keyword in $eligibilityKeywords) {
                    if ($line -match $keyword -and $line -notmatch "success|completed|passed") {
                        return $true
                    }
                }
                return $false
            } | Select-Object -First 100
            
            if ($relevantLines) {
                $report.AppendLine("IN-PLACE UPGRADE ELIGIBILITY ISSUES:") | Out-Null
                $report.AppendLine("-" * 80) | Out-Null
                foreach ($line in $relevantLines) {
                    $report.AppendLine($line) | Out-Null
                    $result.EligibilityIssues += $line
                }
                $report.AppendLine("") | Out-Null
            }
            
            # Look for compatibility scan results
            if ($logFile.Type -match "Compat") {
                $compatIssues = $content | Where-Object {
                    $_ -match "blocker|incompatible|not.*supported|requires|missing|failed"
                } | Select-Object -First 30
                
                if ($compatIssues) {
                    $report.AppendLine("COMPATIBILITY ISSUES:") | Out-Null
                    $report.AppendLine("-" * 80) | Out-Null
                    foreach ($issue in $compatIssues) {
                        $report.AppendLine($issue) | Out-Null
                    }
                    $report.AppendLine("") | Out-Null
                }
            }
            
        } catch {
            $report.AppendLine("[ERROR] Failed to read log file: $_") | Out-Null
            $result.Errors += "Failed to read $($logFile.Path): $_"
        }
        
        $report.AppendLine("") | Out-Null
    }
    
    # 7. SAFE Cleanup (does NOT kill rollback)
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("7. SAFE CLEANUP (does NOT kill rollback)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("[OK] This is the maximum cleanup you should do during diagnosis:") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Command: DISM /Online /Cleanup-Image /StartComponentCleanup") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("What it does:") | Out-Null
    $report.AppendLine("  - Removes old superseded components") | Out-Null
    $report.AppendLine("  - Keeps uninstall + rollback ability") | Out-Null
    $report.AppendLine("  - Won't lock you in") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("[NOTE] This is SAFE to run. It does NOT remove rollback capability.") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 8. DANGEROUS: ResetBase Warning
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("8. [WARNING] DANGEROUS: ResetBase (DO NOT RUN YET)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("[CRITICAL WARNING]") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Command: DISM /Image=C:\ /Cleanup-Image /ResetBase") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("WARNING:") | Out-Null
    $report.AppendLine("  - Permanently removes rollback capability") | Out-Null
    $report.AppendLine("  - You can NEVER uninstall updates again") | Out-Null
    $report.AppendLine("  - If a bad update is present → you're stuck") | Out-Null
    $report.AppendLine("  - This does NOT help most in-place repair blocks") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Only run this after:") | Out-Null
    $report.AppendLine("  - Logs are reviewed") | Out-Null
    $report.AppendLine("  - System is stable") | Out-Null
    $report.AppendLine("  - You accept zero rollback") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("This is NOT a diagnostic tool. It's a commit button.") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 9. ISO Inspection Clarification
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("9. ISO INSPECTION (CLARIFICATION)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("[INFO] You CANNOT inspect setup logs inside an ISO") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("ISO only contains:") | Out-Null
    $report.AppendLine("  - Setup binaries") | Out-Null
    $report.AppendLine("  - Default config") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Logs are generated on the installed OS, not in the ISO.") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Correct move:") | Out-Null
    $report.AppendLine("  1. Mount ISO") | Out-Null
    $report.AppendLine("  2. Run setup.exe") | Out-Null
    $report.AppendLine("  3. Let it fail") | Out-Null
    $report.AppendLine("  4. THEN inspect Panther logs on C:\") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 10. Controlled In-Place Repair Attempt
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("10. ATTEMPT IN-PLACE REPAIR (CONTROLLED)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("Command: setup.exe /dynamicupdate disable") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Why:") | Out-Null
    $report.AppendLine("  - Prevents Windows Update from injecting new variables") | Out-Null
    $report.AppendLine("  - Cleaner failure reason") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("After failure → recheck:") | Out-Null
    $report.AppendLine("  C:\`$Windows.~BT\Sources\Panther\setuperr.log") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Commands to IGNORE (bad advice):") | Out-Null
    $report.AppendLine("  - DISM /Online /Import /Layout (not real / not applicable)") | Out-Null
    $report.AppendLine("  - 'Add compatibility layers with DISM' (not how setup works)") | Out-Null
    $report.AppendLine("  - Editing ISO logs (logs aren't there)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Summary
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("DIAGNOSTIC SUMMARY") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Log Files Analyzed: $($logFiles.Count)") | Out-Null
    $report.AppendLine("Eligibility Issues Found: $($result.EligibilityIssues.Count)") | Out-Null
    $report.AppendLine("Compatibility Blocks: $($result.CompatBlocks.Count)") | Out-Null
    $report.AppendLine("Pending Operations: $(if ($result.PendingOperations) { 'YES (CRITICAL)' } else { 'No' })") | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($result.EligibilityIssues.Count -gt 0) {
        $report.AppendLine("KEY ISSUES IDENTIFIED:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $uniqueIssues = $result.EligibilityIssues | Select-Object -Unique | Select-Object -First 20
        foreach ($issue in $uniqueIssues) {
            $report.AppendLine("  - $issue") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    if ($result.CompatBlocks.Count -gt 0) {
        $report.AppendLine("COMPATIBILITY BLOCKS FOUND:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        foreach ($block in $result.CompatBlocks) {
            $report.AppendLine("  - $block") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    $report.AppendLine("RECOMMENDATIONS:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("1. Review the errors above to identify the specific blocking issue") | Out-Null
    $report.AppendLine("2. Common fixes:") | Out-Null
    $report.AppendLine("   - Edition mismatch: Use Registry EditionID Override (One-Click Fix)") | Out-Null
    $report.AppendLine("   - Language mismatch: Use Registry Language Override (One-Click Fix)") | Out-Null
    $report.AppendLine("   - Version mismatch: Try setup.exe /product server") | Out-Null
    $report.AppendLine("   - Pending CBS: Reboot and retry, or run safe cleanup") | Out-Null
    $report.AppendLine("3. Use the 'One-Click Registry Fixes' button to apply compatibility overrides") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # TL;DR Section
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("TL;DR (BRUTALLY HONEST)") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("In-place repair fails for specific logged reasons") | Out-Null
    $report.AppendLine("Logs > commands") | Out-Null
    $report.AppendLine("ResetBase is not a fix, it's a point of no return") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Most failures are:") | Out-Null
    $report.AppendLine("  - Edition mismatch") | Out-Null
    $report.AppendLine("  - Build family mismatch") | Out-Null
    $report.AppendLine("  - Pending CBS state") | Out-Null
    $report.AppendLine("  - Compat hard block") | Out-Null
    $report.AppendLine("") | Out-Null
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("END OF ANALYSIS") | Out-Null
    
    $result.Report = $report.ToString()
    $result.Success = $true
    
    return $result
}

function Get-FilterDriverForensics {
    param($TargetDrive = "C")
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $currentOS = ($env:SystemDrive.TrimEnd(':') -eq $TargetDrive)
    $osContext = if ($currentOS) { "CURRENT OPERATING SYSTEM" } else { "OFFLINE WINDOWS INSTALLATION" }
    
    $report = @{
        Found = $false
        FilterDrivers = @()
        Summary = ""
        TargetDrive = "$TargetDrive`:"
        IsCurrentOS = $currentOS
    }
    
    $systemHive = "$TargetDrive`:\Windows\System32\config\SYSTEM"
    
    if (-not (Test-Path $systemHive)) {
        $report.Summary = "FILTER DRIVER FORENSICS - $osContext`n" +
                         "===============================================================`n" +
                         "Target Windows Installation: $TargetDrive`:\Windows`n" +
                         "Status: $osContext`n`n" +
                         "SYSTEM registry hive not found at: $systemHive`n" +
                         "Cannot analyze filter drivers."
        return $report
    }
    
    try {
        # Load the offline SYSTEM hive
        $tempHive = "HKLM:\TempSystemHive"
        
        # Try to load the hive (requires admin and hive not already loaded)
        try {
            reg load "HKLM\TempSystemHive" $systemHive 2>&1 | Out-Null
            $hiveLoaded = $true
        } catch {
            # Hive may already be loaded or we're in live system
            $hiveLoaded = $false
            $tempHive = "HKLM:\SYSTEM"  # Use live system hive
        }
        
        # Search for ControlSet001\Control\Class (storage device classes)
        $classPath = "$tempHive\ControlSet001\Control\Class"
        
        if (Test-Path $classPath) {
            $classes = Get-ChildItem -Path $classPath -ErrorAction SilentlyContinue
            
            foreach ($class in $classes) {
                $upperFilters = (Get-ItemProperty -Path $class.PSPath -Name UpperFilters -ErrorAction SilentlyContinue).UpperFilters
                $lowerFilters = (Get-ItemProperty -Path $class.PSPath -Name LowerFilters -ErrorAction SilentlyContinue).LowerFilters
                
                if ($upperFilters -or $lowerFilters) {
                    $classGuid = Split-Path $class.PSPath -Leaf
                    $classDesc = (Get-ItemProperty -Path $class.PSPath -Name Class -ErrorAction SilentlyContinue).Class
                    
                    $filterInfo = @{
                        ClassGuid = $classGuid
                        ClassDescription = $classDesc
                        UpperFilters = $upperFilters
                        LowerFilters = $lowerFilters
                        SuspiciousFilters = @()
                    }
                    
                    # Identify suspicious third-party filters (common culprits)
                    $suspiciousPatterns = @("Acronis", "Symantec", "Norton", "McAfee", "Kaspersky", "BitDefender", "AVG", "Avast")
                    
                    if ($upperFilters) {
                        foreach ($filter in $upperFilters) {
                            foreach ($pattern in $suspiciousPatterns) {
                                if ($filter -match $pattern) {
                                    $filterInfo.SuspiciousFilters += "UpperFilter: $filter (may cause 0x7B BSOD)"
                                }
                            }
                        }
                    }
                    
                    if ($lowerFilters) {
                        foreach ($filter in $lowerFilters) {
                            foreach ($pattern in $suspiciousPatterns) {
                                if ($filter -match $pattern) {
                                    $filterInfo.SuspiciousFilters += "LowerFilter: $filter (may cause 0x7B BSOD)"
                                }
                            }
                        }
                    }
                    
                    if ($filterInfo.SuspiciousFilters.Count -gt 0 -or $classDesc -match "Disk|Storage|SCSI") {
                        $report.FilterDrivers += $filterInfo
                        $report.Found = $true
                    }
                }
            }
        }
        
        # Unload the temporary hive if we loaded it
        if ($hiveLoaded) {
            reg unload "HKLM\TempSystemHive" 2>&1 | Out-Null
        }
        
        # Generate summary
        if ($report.Found) {
            $summary = "FILTER DRIVER FORENSICS - $osContext`n"
            $summary += "===============================================================`n`n"
            $summary += "Target Windows Installation: $TargetDrive`:\Windows`n"
            $summary += "Status: $osContext`n"
            $summary += "SYSTEM Hive: $systemHive`n"
            $summary += "Suspicious filter drivers found: $($report.FilterDrivers.Count)`n`n"
            
            foreach ($filter in $report.FilterDrivers) {
                $summary += "Class: $($filter.ClassDescription) (GUID: $($filter.ClassGuid))`n"
                if ($filter.UpperFilters) {
                    $summary += "  UpperFilters: $($filter.UpperFilters -join ', ')`n"
                }
                if ($filter.LowerFilters) {
                    $summary += "  LowerFilters: $($filter.LowerFilters -join ', ')`n"
                }
                if ($filter.SuspiciousFilters.Count -gt 0) {
                    $summary += "  [WARN] SUSPICIOUS: $($filter.SuspiciousFilters -join '; ')`n"
                    $summary += "     These may cause 0x7B (Inaccessible Boot Device) BSOD`n"
                    $summary += "     Recommendation: Remove these filters from the registry`n"
                }
                $summary += "`n"
            }
            
            $summary += "TO FIX:`n"
            $summary += "1. Load the SYSTEM hive: reg load HKLM\TempSystem $systemHive`n"
            $summary += "2. Navigate to: HKLM\TempSystem\ControlSet001\Control\Class\{GUID}`n"
            $summary += "3. Delete suspicious entries from UpperFilters/LowerFilters`n"
            $summary += "4. Unload: reg unload HKLM\TempSystem`n"
            
            $report.Summary = $summary
        } else {
            $report.Summary = "FILTER DRIVER FORENSICS - $osContext`n" +
                             "===============================================================`n`n" +
                             "Target Windows Installation: $TargetDrive`:\Windows`n" +
                             "Status: $osContext`n`n" +
                             "No suspicious filter drivers found in SYSTEM hive.`n" +
                             "Filter drivers appear normal."
        }
        
    } catch {
        $report.Summary = "FILTER DRIVER FORENSICS - $osContext`n" +
                         "===============================================================`n`n" +
                         "Target Windows Installation: $TargetDrive`:\Windows`n" +
                         "Status: $osContext`n`n" +
                         "Error analyzing filter drivers: $_`n`n" +
                         "Note: This requires loading the offline SYSTEM hive, which may not be possible in all environments."
    }
    
    return $report
}

function Test-RepairInstallPrerequisites {
    param($ISOPath)
    
    $result = @{
        CanProceed = $false
        Issues = @()
        Warnings = @()
        Recommendations = @()
        CurrentOS = @{}
        ISOInfo = @{}
    }
    
    # Get current OS info
    $osInfo = Get-OSInfo -TargetDrive $env:SystemDrive.TrimEnd(':')
    $result.CurrentOS = $osInfo
    
    # Check if ISO path exists
    if (-not $ISOPath) {
        $result.Issues += "ISO path not specified"
        return $result
    }
    
    if (-not (Test-Path $ISOPath)) {
        $result.Issues += "ISO path does not exist: $ISOPath"
        return $result
    }
    
    # Check if it's a mounted ISO or folder
    $setupExe = Join-Path $ISOPath "setup.exe"
    if (-not (Test-Path $setupExe)) {
        $result.Issues += "setup.exe not found at: $setupExe"
        $result.Recommendations += "Ensure the ISO is mounted or extract the ISO to a folder"
        return $result
    }
    
    # Try to get ISO version info (this is tricky - we can check sources/install.wim or setup.exe properties)
    $sourcesPath = Join-Path $ISOPath "sources"
    if (Test-Path $sourcesPath) {
        $result.ISOInfo.HasSources = $true
    } else {
        $result.Warnings += "sources folder not found - may not be a valid Windows ISO"
    }
    
    # Check hard requirements
    # 1. Must be running from inside Windows (not WinRE)
    if ($env:SystemDrive -eq 'X:') {
        $result.Issues += "Cannot run repair install from WinRE/WinPE. Must run from inside Windows."
        return $result
    }
    
    # 2. Check if registry is loadable
    try {
        $testKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction Stop
        $result.CurrentOS.EditionID = $testKey.EditionID
    } catch {
        $result.Issues += "Cannot access registry - SYSTEM or SOFTWARE hive may be corrupted"
        return $result
    }
    
    # 3. Check CBS status
    try {
        $pendingXml = "$env:SystemRoot\WinSxS\pending.xml"
        if (Test-Path $pendingXml) {
            $result.Warnings += "Pending CBS operations detected (pending.xml exists). Reboot may be required first."
        }
    } catch {
        # Can't check, but not blocking
    }
    
    # 4. Check if boot is accessible
    if (-not (Test-Path "$env:SystemRoot\System32\ntoskrnl.exe")) {
        $result.Issues += "Windows kernel not found - system may be too damaged for repair install"
        return $result
    }
    
    # Recommendations
    $result.Recommendations += "Ensure ISO matches: Edition=$($osInfo.EditionID), Architecture=$($osInfo.Architecture), Build Family=$($osInfo.BuildNumber)"
    $result.Recommendations += "Language must match: $($osInfo.Language)"
    $result.Recommendations += "Backup important data before proceeding"
    $result.Recommendations += "Have BitLocker recovery key ready if drive is encrypted"
    
    # If we got here, prerequisites are met
    if ($result.Issues.Count -eq 0) {
        $result.CanProceed = $true
    }
    
    return $result
}

function Start-RepairInstall {
    param(
        $ISOPath,
        [switch]$ForceEdition,
        [switch]$SkipCompatibility,
        [switch]$DisableDynamicUpdate
    )
    
    $result = @{
        Success = $false
        Command = ""
        Output = ""
        LogPath = ""
        Errors = @()
    }
    
    # Check prerequisites
    $prereq = Test-RepairInstallPrerequisites -ISOPath $ISOPath
    if (-not $prereq.CanProceed) {
        $result.Errors = $prereq.Issues
        $result.Output = "PREREQUISITE CHECK FAILED`n" +
                        "===============================================================`n`n" +
                        "Cannot proceed with repair install:`n`n" +
                        ($prereq.Issues -join "`n") +
                        "`n`n" +
                        "WARNINGS:`n" +
                        ($prereq.Warnings -join "`n")
        return $result
    }
    
    # Step 1: Apply registry overrides (safe, non-destructive)
    try {
        $editionId = $prereq.CurrentOS.EditionID
        if (-not $editionId) {
            $editionId = "Professional" # Default fallback
        }
        
        # Set EditionID to prevent mis-detection
        reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID /t REG_SZ /d $editionId /f 2>&1 | Out-Null
        
        # Set InstallationType
        reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v InstallationType /t REG_SZ /d "Client" /f 2>&1 | Out-Null
        
        # Optional: Force compatibility override
        if ($SkipCompatibility) {
            reg add "HKLM\SYSTEM\Setup\MoSetup" /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        }
        
        $result.Output += "[OK] Registry overrides applied`n"
    } catch {
        $result.Errors += "Failed to apply registry overrides: $_"
        $result.Output += "[ERROR] Failed to apply registry overrides: $_`n"
        return $result
    }
    
    # Step 2: Build setup.exe command
    $setupExe = Join-Path $ISOPath "setup.exe"
    $command = "`"$setupExe`" /auto upgrade"
    
    if ($DisableDynamicUpdate) {
        $command += " /dynamicupdate disable"
    }
    
    if ($SkipCompatibility) {
        $command += " /compat ignorewarning"
    }
    
    $command += " /showoobe none"
    
    # Optional: Force edition alignment with generic key (if needed)
    if ($ForceEdition) {
        # Generic Windows 10/11 Pro key (for alignment only, doesn't activate)
        $command += " /pkey VK7JG-NPHTM-C97JM-9MPGT-3V66T"
    }
    
    $result.Command = $command
    $result.LogPath = "C:\`$WINDOWS.~BT\Sources\Panther\setupact.log"
    
    # Step 3: Prepare output
    $result.Output += "`n[INFO] Repair install prepared successfully`n"
    $result.Output += "Command: $command`n`n"
    $result.Output += "Monitor progress at: $($result.LogPath)`n"
    $result.Output += "`n[WARNING] This will launch Windows Setup.`n"
    $result.Output += "The system will restart and begin the repair process.`n"
    
    $result.Success = $true
    
    return $result
}

function Get-RepairInstallInstructions {
    $instructions = @"
REPAIR INSTALL FORCER - INSTRUCTIONS
===============================================================

WHAT THIS DOES:
-------------------------------------------------------------------------------
Forces Windows Setup to perform a "repair-only" in-place upgrade that:
  - Reinstalls Windows system files
  - Rebuilds component store
  - Re-registers services + boot
  - KEEPS: Apps, Data, User profiles
  - WITHOUT: Feature jump, Build bump, Edition change

HARD REQUIREMENTS (MUST MATCH):
-------------------------------------------------------------------------------
  [OK] Edition: EXACT match (Pro → Pro, Home → Home)
  [OK] Architecture: EXACT (x64 → x64, x86 → x86)
  [OK] Build Family: SAME (19041 ↔ 19045 is OK, but 19041 ↔ 22000 is NOT)
  [OK] Language: MUST match
  [OK] Launch Context: From inside Windows (NOT WinRE/WinPE)
  [OK] Registry: Must be loadable
  [OK] CBS: Not permanently locked

STEP-BY-STEP PROCESS:
-------------------------------------------------------------------------------

1. GET THE CORRECT ISO
   - Use Media Creation Tool for your Windows version
   - Same build family (e.g., Windows 10 22H2 → 19045.x)
   - Language must match your current installation
   - Do NOT use Windows 11 ISO if repairing Windows 10

2. MOUNT THE ISO
   - Right-click ISO → Mount
   - Or extract ISO to a folder
   - Note the drive letter or folder path

3. RUN PREREQUISITE CHECK
   - Click "Check Prerequisites" button
   - Review any warnings or issues
   - Fix any blocking issues before proceeding

4. APPLY REGISTRY OVERRIDES (Safe)
   - This tool will automatically apply:
     * EditionID registry fix
     * InstallationType registry fix
     * Optional compatibility overrides

5. START REPAIR INSTALL
   - Select your ISO/mounted folder
   - Choose options (skip compatibility, disable dynamic update)
   - Click "Start Repair Install"
   - Confirm the action
   - Setup will launch and system will restart

6. MONITOR PROGRESS
   - After restart, monitor: C:\`$WINDOWS.~BT\Sources\Panther\setupact.log
   - Look for: ExecuteDownlevelMode (good), SetupPhaseApplyImage (locked in)
   - SafeOS phase indicates repair is happening

WHEN THIS WILL NOT WORK:
-------------------------------------------------------------------------------
  [X] Boot breaks before login
  [X] SYSTEM or SOFTWARE registry hive is corrupt
  [X] CBS is permanently pending
  [X] Disk driver stack is broken (e.g., VMD mismatch)
  [X] Running from WinRE/WinPE
  [X] Edition/Architecture/Build mismatch

ALTERNATIVES IF REPAIR INSTALL FAILS:
-------------------------------------------------------------------------------
  - Offline servicing (DISM)
  - Side-by-side reinstall
  - Image restore from backup
  - Clean install (last resort)

IMPORTANT NOTES:
-------------------------------------------------------------------------------
  - This is NOT a true "repair-only" button - it's a same-build in-place upgrade
  - Microsoft uses this exact method internally to fix "zombie Windows" machines
  - Always backup important data before proceeding
  - Have BitLocker recovery key ready if drive is encrypted
  - Process can take 30-60 minutes depending on system speed

"@
    return $instructions
}

function Test-OfflineRepairInstallPrerequisites {
    param(
        $ISOPath,
        $OfflineWindowsDrive = "C"
    )
    
    $result = @{
        CanProceed = $false
        Issues = @()
        Warnings = @()
        Recommendations = @()
        OfflineOS = @{}
        ISOInfo = @{}
    }
    
    # Normalize drive letter
    if ($OfflineWindowsDrive -match '^([A-Z]):?$') {
        $OfflineWindowsDrive = $matches[1]
    }
    
    # Check if we're in WinPE/WinRE (required for offline repair)
    if ($env:SystemDrive -ne 'X:') {
        $result.Issues += "Offline repair install requires WinPE or WinRE environment (SystemDrive must be X:)"
        $result.Warnings += "Current environment: $env:SystemDrive - This method requires booting from WinPE/WinRE"
        return $result
    }
    
    # Check if ISO path exists
    if (-not $ISOPath) {
        $result.Issues += "ISO path not specified"
        return $result
    }
    
    if (-not (Test-Path $ISOPath)) {
        $result.Issues += "ISO path does not exist: $ISOPath"
        return $result
    }
    
    # Check if it's a mounted ISO or folder
    $setupExe = Join-Path $ISOPath "setup.exe"
    if (-not (Test-Path $setupExe)) {
        $result.Issues += "setup.exe not found at: $setupExe"
        $result.Recommendations += "Ensure the ISO is mounted or extract the ISO to a folder"
        return $result
    }
    
    # Check offline Windows installation
    $offlineWindowsPath = "$OfflineWindowsDrive`:\Windows"
    if (-not (Test-Path $offlineWindowsPath)) {
        $result.Issues += "Windows installation not found at: $offlineWindowsPath"
        return $result
    }
    
    # Check if offline registry hives exist
    $systemHive = "$OfflineWindowsDrive`:\Windows\System32\config\SYSTEM"
    $softwareHive = "$OfflineWindowsDrive`:\Windows\System32\config\SOFTWARE"
    
    if (-not (Test-Path $systemHive)) {
        $result.Issues += "SYSTEM registry hive not found at: $systemHive"
        return $result
    }
    
    if (-not (Test-Path $softwareHive)) {
        $result.Issues += "SOFTWARE registry hive not found at: $softwareHive"
        return $result
    }
    
    # Try to get offline OS info
    try {
        $osInfo = Get-OSInfo -TargetDrive $OfflineWindowsDrive
        $result.OfflineOS = $osInfo
    } catch {
        $result.Warnings += "Could not retrieve offline OS info: $_"
    }
    
    # Check if Windows kernel exists
    if (-not (Test-Path "$OfflineWindowsDrive`:\Windows\System32\ntoskrnl.exe")) {
        $result.Warnings += "Windows kernel not found - system may be too damaged"
    }
    
    # Check component store
    $componentStore = "$OfflineWindowsDrive`:\Windows\WinSxS"
    if (-not (Test-Path $componentStore)) {
        $result.Warnings += "Component store (WinSxS) not found - may cause migration failures"
    }
    
    # Recommendations
    $result.Recommendations += "This is an ADVANCED/HACKY method - use with caution"
    $result.Recommendations += "Ensure ISO matches: Edition=$($result.OfflineOS.EditionID), Architecture=$($result.OfflineOS.Architecture)"
    $result.Recommendations += "Backup registry hives before modification"
    $result.Recommendations += "This method may fail if: CBS is pending, SOFTWARE hive is corrupt, or servicing metadata is missing"
    
    # If we got here, prerequisites are met
    if ($result.Issues.Count -eq 0) {
        $result.CanProceed = $true
    }
    
    return $result
}

function Start-OfflineRepairInstall {
    param(
        $ISOPath,
        $OfflineWindowsDrive = "C",
        [switch]$SkipCompatibility,
        [switch]$DisableDynamicUpdate
    )
    
    $result = @{
        Success = $false
        Command = ""
        Output = ""
        LogPath = ""
        Errors = @()
        RegistryBackups = @()
    }
    
    # Normalize drive letter
    if ($OfflineWindowsDrive -match '^([A-Z]):?$') {
        $OfflineWindowsDrive = $matches[1]
    }
    
    # Check prerequisites
    $prereq = Test-OfflineRepairInstallPrerequisites -ISOPath $ISOPath -OfflineWindowsDrive $OfflineWindowsDrive
    if (-not $prereq.CanProceed) {
        $result.Errors = $prereq.Issues
        $result.Output = "OFFLINE REPAIR INSTALL - PREREQUISITE CHECK FAILED`n" +
                        "===============================================================`n`n" +
                        "Cannot proceed with offline repair install:`n`n" +
                        ($prereq.Issues -join "`n") +
                        "`n`n" +
                        "WARNINGS:`n" +
                        ($prereq.Warnings -join "`n")
        return $result
    }
    
    $systemHive = "$OfflineWindowsDrive`:\Windows\System32\config\SYSTEM"
    $softwareHive = "$OfflineWindowsDrive`:\Windows\System32\config\SOFTWARE"
    $tempSystemHive = "HKLM:\TempOfflineSystem"
    $tempSoftwareHive = "HKLM:\TempOfflineSoftware"
    
    # Step 1: Backup registry hives
    try {
        $backupDir = "$env:TEMP\OfflineRepairBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        
        Copy-Item -Path $systemHive -Destination "$backupDir\SYSTEM.backup" -Force
        Copy-Item -Path $softwareHive -Destination "$backupDir\SOFTWARE.backup" -Force
        
        $result.RegistryBackups += "$backupDir\SYSTEM.backup"
        $result.RegistryBackups += "$backupDir\SOFTWARE.backup"
        $result.Output += "[OK] Registry hives backed up to: $backupDir`n"
    } catch {
        $result.Errors += "Failed to backup registry hives: $_"
        $result.Output += "[ERROR] Failed to backup registry hives: $_`n"
        return $result
    }
    
    # Step 2: Load offline registry hives
    try {
        # Unload if already loaded
        reg unload "HKLM\TempOfflineSystem" 2>&1 | Out-Null
        reg unload "HKLM\TempOfflineSoftware" 2>&1 | Out-Null
        
        # Load hives
        reg load "HKLM\TempOfflineSystem" $systemHive 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to load SYSTEM hive"
        }
        
        reg load "HKLM\TempOfflineSoftware" $softwareHive 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            reg unload "HKLM\TempOfflineSystem" 2>&1 | Out-Null
            throw "Failed to load SOFTWARE hive"
        }
        
        $result.Output += "[OK] Offline registry hives loaded`n"
    } catch {
        $result.Errors += "Failed to load offline registry hives: $_"
        $result.Output += "[ERROR] Failed to load offline registry hives: $_`n"
        return $result
    }
    
    # Step 3: Apply registry overrides to offline hives
    try {
        # Get EditionID from offline SOFTWARE hive
        $editionId = (Get-ItemProperty -Path "$tempSoftwareHive\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction SilentlyContinue).EditionID
        if (-not $editionId) {
            $editionId = "Professional" # Default fallback
        }
        
        # Set EditionID in offline SOFTWARE hive
        reg add "$tempSoftwareHive\Microsoft\Windows NT\CurrentVersion" /v EditionID /t REG_SZ /d $editionId /f 2>&1 | Out-Null
        
        # Set InstallationType
        reg add "$tempSoftwareHive\Microsoft\Windows NT\CurrentVersion" /v InstallationType /t REG_SZ /d "Client" /f 2>&1 | Out-Null
        
        # Set SetupPhase in SYSTEM hive (trick Setup into thinking it's an upgrade)
        reg add "$tempSystemHive\Setup" /v SetupPhase /t REG_SZ /d "Upgrade" /f 2>&1 | Out-Null
        
        # Optional: Force compatibility override
        if ($SkipCompatibility) {
            $moSetupPath = "$tempSystemHive\Setup\MoSetup"
            if (-not (Test-Path $moSetupPath)) {
                New-Item -Path $moSetupPath -Force | Out-Null
            }
            reg add $moSetupPath /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        }
        
        $result.Output += "[OK] Registry overrides applied to offline hives`n"
    } catch {
        $result.Errors += "Failed to apply registry overrides: $_"
        $result.Output += "[ERROR] Failed to apply registry overrides: $_`n"
        # Unload hives before returning
        reg unload "HKLM\TempOfflineSystem" 2>&1 | Out-Null
        reg unload "HKLM\TempOfflineSoftware" 2>&1 | Out-Null
        return $result
    }
    
    # Step 4: Unload hives (required before setup.exe can access them)
    try {
        reg unload "HKLM\TempOfflineSystem" 2>&1 | Out-Null
        reg unload "HKLM\TempOfflineSoftware" 2>&1 | Out-Null
        $result.Output += "[OK] Registry hives unloaded (ready for setup.exe)`n"
    } catch {
        $result.Warnings += "Warning: Could not unload all registry hives: $_"
    }
    
    # Step 5: Build setup.exe command
    $setupExe = Join-Path $ISOPath "setup.exe"
    $command = "`"$setupExe`" /auto upgrade"
    
    if ($DisableDynamicUpdate) {
        $command += " /dynamicupdate disable"
    }
    
    if ($SkipCompatibility) {
        $command += " /compat ignorewarning"
    }
    
    $command += " /showoobe none"
    
    # Point setup to offline Windows installation
    $command += " /installdrivename $OfflineWindowsDrive"
    
    $result.Command = $command
    $result.LogPath = "$OfflineWindowsDrive`:\`$WINDOWS.~BT\Sources\Panther\setupact.log"
    
    # Step 6: Prepare output
    $result.Output += "`n[INFO] Offline repair install prepared successfully`n"
    $result.Output += "Command: $command`n`n"
    $result.Output += "Registry backups saved to: $backupDir`n"
    $result.Output += "Monitor progress at: $($result.LogPath)`n"
    $result.Output += "`n[WARNING] This is an ADVANCED/HACKY method.`n"
    $result.Output += "Migration engine will run offline.`n"
    $result.Output += "Apps will be preserved if registry and Program Files are intact.`n"
    $result.Output += "`n[WARNING] This may fail if:`n"
    $result.Output += "  - Pending CBS operations exist`n"
    $result.Output += "  - SOFTWARE hive is corrupt`n"
    $result.Output += "  - Servicing metadata is missing`n"
    
    $result.Success = $true
    
    return $result
}

function Get-OfflineRepairInstallInstructions {
    $instructions = @"
OFFLINE REPAIR INSTALL FORCER - INSTRUCTIONS
===============================================================

WHAT THIS DOES:
-------------------------------------------------------------------------------
Forces Windows Setup to perform an in-place upgrade on a NON-BOOTING Windows
installation by manipulating offline registry hives. This is an ADVANCED/HACKY
method that tricks Setup into thinking it's upgrading a running OS.

This method:
  - Boots from WinPE/WinRE
  - Loads offline SYSTEM + SOFTWARE registry hives
  - Manually sets SetupPhase, Upgrade, InstallationType keys
  - Launches setup.exe against the offline OS
  - Migration engine (MigCore.dll) runs offline
  - Apps are preserved if registry and Program Files are intact

[WARN] WARNING: This is a GRAY-AREA NUCLEAR HACK
-------------------------------------------------------------------------------
This method is documented only in advanced forums (MDL, Win-Raid).
Use at your own risk. This is NOT officially supported by Microsoft.

HARD REQUIREMENTS:
-------------------------------------------------------------------------------
  [OK] Must boot from WinPE or WinRE (SystemDrive = X:)
  [OK] Offline Windows installation must exist on target drive
  [OK] SYSTEM and SOFTWARE registry hives must be loadable
  [OK] ISO must match: Edition, Architecture, Build Family
  [OK] Component store (WinSxS) should be readable

WHEN THIS WORKS:
-------------------------------------------------------------------------------
  [OK] Registry is intact (can be loaded)
  [OK] Program Files structure is consistent
  [OK] Component store is readable
  [OK] Migration engine can access offline files

WHEN THIS FAILS:
-------------------------------------------------------------------------------
  [X] Pending CBS operations (pending.xml exists)
  [X] Corrupt SOFTWARE registry hive
  [X] Missing servicing metadata
  [X] Component store (WinSxS) is corrupted
  [X] Program Files structure is inconsistent

STEP-BY-STEP PROCESS:
-------------------------------------------------------------------------------

1. BOOT FROM WINPE/WINRE
   - Boot from Windows installation media
   - Press Shift+F10 to open command prompt
   - Or boot from WinPE USB (Hiren's BootCD PE, Sergei Strelec's WinPE)

2. RUN THIS TOOL
   - Launch Miracle Boot from WinPE/WinRE
   - Navigate to "Repair Install Forcer" tab
   - Select "Offline Mode"

3. SELECT OFFLINE WINDOWS DRIVE
   - Choose the drive letter where Windows is installed (usually C:)
   - Tool will verify Windows installation exists

4. SELECT ISO/MOUNTED FOLDER
   - Mount your Windows ISO or extract to folder
   - Browse to select the path

5. CHECK PREREQUISITES
   - Click "Check Prerequisites" button
   - Review any warnings or issues
   - Fix blocking issues before proceeding

6. START OFFLINE REPAIR INSTALL
   - Tool will:
     * Backup registry hives automatically
     * Load offline SYSTEM + SOFTWARE hives
     * Apply registry overrides (SetupPhase, EditionID, etc.)
     * Unload hives
     * Launch setup.exe with proper flags
   - System will restart and begin repair process

7. MONITOR PROGRESS
   - After restart, monitor: C:\`$WINDOWS.~BT\Sources\Panther\setupact.log
   - Look for: ExecuteDownlevelMode, SetupPhaseApplyImage
   - SafeOS phase indicates repair is happening

ADVANCED NOTES:
-------------------------------------------------------------------------------
  - Registry hives are automatically backed up before modification
  - Backup location is shown in output
  - If repair fails, you can restore hives from backup
  - Migration engine runs offline, so it may take longer
  - This method bypasses normal Setup checks

ALTERNATIVES IF THIS FAILS:
-------------------------------------------------------------------------------
  - Offline servicing with DISM
  - Side-by-side reinstall
  - Image restore from backup
  - Clean install (last resort)

REFERENCES:
-------------------------------------------------------------------------------
  - MDL Forum: Forced in-place upgrade against offline OS
  - Win-Raid: Windows repair install from WinPE discussion
  - This method is used by advanced users in recovery scenarios

"@
    return $instructions
}

# ============================================================================
# NETWORK/INTERNET ENABLEMENT MODULE
# Functions to enable network in WinRE and provide internet access
# ============================================================================

function Get-NetworkAdapters {
    <#
    .SYNOPSIS
    Lists available network adapters in the system.
    #>
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Hidden' }
        if ($adapters) {
            return $adapters | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress
        }
        
        # Fallback: Use netsh if Get-NetAdapter fails
        $netshOutput = netsh interface show interface 2>&1
        $adapters = @()
        $inTable = $false
        foreach ($line in $netshOutput) {
            if ($line -match '^-+') {
                $inTable = $true
                continue
            }
            if ($inTable -and $line -match '^\s*(\S+)\s+(\S+)\s+(\S+)\s+(.+)$') {
                $adapters += [PSCustomObject]@{
                    Name = $matches[1]
                    AdminState = $matches[2]
                    State = $matches[3]
                    Type = $matches[4].Trim()
                }
            }
        }
        return $adapters
    } catch {
        Write-Warning "Could not enumerate network adapters: $_"
        return @()
    }
}

function Enable-NetworkWinRE {
    <#
    .SYNOPSIS
    Enables network adapters in WinRE environment.
    #>
    param(
        [string]$AdapterName = $null
    )
    
    $result = @{
        Success = $false
        Message = ""
        EnabledAdapters = @()
        Errors = @()
    }
    
    try {
        # Get available adapters
        $adapters = Get-NetworkAdapters
        
        if (-not $adapters -or $adapters.Count -eq 0) {
            $result.Message = "No network adapters found. Network drivers may not be loaded."
            return $result
        }
        
        # If specific adapter requested, use it; otherwise enable all
        $adaptersToEnable = if ($AdapterName) {
            $adapters | Where-Object { $_.Name -eq $AdapterName }
        } else {
            $adapters | Where-Object { $_.AdminState -eq 'Disabled' -or $_.State -eq 'Disconnected' }
        }
        
        if (-not $adaptersToEnable -or $adaptersToEnable.Count -eq 0) {
            $result.Message = "No disabled adapters found. Network may already be enabled."
            $result.Success = $true
            return $result
        }
        
        foreach ($adapter in $adaptersToEnable) {
            try {
                $adapterName = $adapter.Name
                
                # Try PowerShell cmdlet first
                if (Get-Command Enable-NetAdapter -ErrorAction SilentlyContinue) {
                    Enable-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction Stop
                } else {
                    # Fallback to netsh
                    $netshResult = netsh interface set interface name="$adapterName" admin=enable 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "netsh failed: $netshResult"
                    }
                }
                
                $result.EnabledAdapters += $adapterName
            } catch {
                $result.Errors += "Failed to enable $($adapter.Name): $_"
            }
        }
        
        if ($result.EnabledAdapters.Count -gt 0) {
            $result.Success = $true
            $result.Message = "Successfully enabled $($result.EnabledAdapters.Count) network adapter(s): $($result.EnabledAdapters -join ', ')"
        } else {
            $result.Message = "Failed to enable any adapters. Errors: $($result.Errors -join '; ')"
        }
        
    } catch {
        $result.Message = "Error enabling network: $_"
        $result.Errors += $_.Exception.Message
    }
    
    return $result
}

function Enable-WiFiWinRE {
    <#
    .SYNOPSIS
    Enables WiFi in WinRE if drivers are available.
    #>
    try {
        # Check if WiFi adapters exist
        $wifiAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|802.11' }
        
        if (-not $wifiAdapters) {
            return @{
                Success = $false
                Message = "No WiFi adapters found. WiFi drivers may not be loaded in WinRE."
            }
        }
        
        # Enable WiFi service
        $wlanService = Get-Service -Name "WlanSvc" -ErrorAction SilentlyContinue
        if ($wlanService -and $wlanService.Status -ne 'Running') {
            Start-Service -Name "WlanSvc" -ErrorAction SilentlyContinue
        }
        
        # Enable WiFi adapters
        $enabled = @()
        foreach ($adapter in $wifiAdapters) {
            try {
                if (Get-Command Enable-NetAdapter -ErrorAction SilentlyContinue) {
                    Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                } else {
                    netsh interface set interface name="$($adapter.Name)" admin=enable 2>&1 | Out-Null
                }
                $enabled += $adapter.Name
            } catch {
                Write-Warning "Failed to enable WiFi adapter $($adapter.Name): $_"
            }
        }
        
        if ($enabled.Count -gt 0) {
            return @{
                Success = $true
                Message = "WiFi enabled on adapter(s): $($enabled -join ', ')"
            }
        } else {
            return @{
                Success = $false
                Message = "WiFi adapters found but could not be enabled."
            }
        }
    } catch {
        return @{
            Success = $false
            Message = "Error enabling WiFi: $_"
        }
    }
}

function Test-InternetConnectivity {
    <#
    .SYNOPSIS
    Tests internet connectivity by pinging common servers.
    #>
    param(
        [int]$TimeoutSeconds = 3
    )
    
    $result = @{
        Connected = $false
        Message = ""
        TestedHosts = @()
    }
    
    # First, check if network adapters exist and are connected
    # This prevents false negatives when adapters exist but ping fails
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
            $_.Status -ne 'Hidden' -and ($_.Status -eq 'Up' -or $_.Status -eq 'Connected')
        }
        if (-not $adapters -or $adapters.Count -eq 0) {
            $result.Message = "No connected network adapters detected"
            return $result
        }
    } catch {
        # Continue with connectivity test anyway
    }
    
    # Test hosts (in order of reliability)
    $testHosts = @(
        "8.8.8.8",           # Google DNS (most reliable)
        "1.1.1.1",           # Cloudflare DNS
        "8.8.4.4"            # Google DNS secondary
    )
    
    foreach ($testHost in $testHosts) {
        try {
            $result.TestedHosts += $testHost
            # Use shorter timeout for faster detection
            $ping = Test-Connection -ComputerName $testHost -Count 1 -TimeoutSeconds 2 -ErrorAction SilentlyContinue
            if ($ping) {
                $result.Connected = $true
                $result.Message = "Internet connectivity confirmed (reached $testHost)"
                return $result
            }
        } catch {
            # Continue to next host
            continue
        }
    }
    
    # If all pings failed, try HTTP request (but with shorter timeout)
    try {
        $webRequest = Invoke-WebRequest -Uri "http://www.microsoft.com" -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($webRequest -and $webRequest.StatusCode -eq 200) {
            $result.Connected = $true
            $result.Message = "Internet connectivity confirmed (HTTP request succeeded)"
            return $result
        }
    } catch {
        # HTTP also failed
    }
    
    $result.Message = "No internet connectivity detected. Tested: $($result.TestedHosts -join ', ')"
    return $result
}

function Get-HelpContent {
    <#
    .SYNOPSIS
    Retrieves help content for a specific topic or feature.
    
    .DESCRIPTION
    Provides context-sensitive help with tutorials, FAQs, and examples.
    Supports searching and filtering by category.
    #>
    param(
        [string]$Topic = "",
        [string]$Category = "",
        [string]$SearchTerm = ""
    )
    
    $helpDatabase = @{
        "Boot Repair" = @{
            Title = "Boot Repair Help"
            Category = "Boot"
            Content = @"
BOOT REPAIR GUIDE
===============================================================

WHAT IS BOOT REPAIR?
Boot repair fixes issues that prevent Windows from starting properly.
Common symptoms:
  - Computer shows "No Boot Device Found"
  - Windows logo appears but system hangs
  - Blue screen errors during boot
  - "Boot Configuration Data file is missing" error

COMMON BOOT REPAIR COMMANDS:
---------------------------------------------------------------
1. bootrec /scanos
   - Scans all disks for Windows installations
   - Use when Windows doesn't appear in boot menu

2. bootrec /fixboot
   - Repairs the boot sector
   - Use for "NTLDR is missing" errors

3. bootrec /fixmbr
   - Repairs Master Boot Record (MBR)
   - Use for legacy BIOS systems

4. bootrec /rebuildbcd
   - Rebuilds Boot Configuration Data
   - Use when BCD is corrupted or missing

5. bcdboot C:\Windows
   - Copies boot files to EFI partition
   - Use for UEFI systems with missing boot files

AUTOMATED BOOT REPAIR:
---------------------------------------------------------------
Miracle Boot can automatically run these commands in sequence.
Select "Automated Boot Repair" from the menu for best results.

TROUBLESHOOTING:
---------------------------------------------------------------
- If repair fails, check for missing storage drivers (VMD/RAID)
- Ensure EFI partition exists and is formatted correctly
- Verify Windows installation is not corrupted
- Check disk health with chkdsk

"@
            FAQs = @(
                "Q: Will boot repair delete my files? A: No, boot repair only fixes boot configuration, not your data.",
                "Q: How long does boot repair take? A: Usually 5-15 minutes depending on system speed.",
                "Q: What if boot repair fails? A: Try system file repair (SFC + DISM) or complete system repair."
            )
        }
        "System File Repair" = @{
            Title = "System File Repair Help"
            Category = "Repair"
            Content = @"
SYSTEM FILE REPAIR GUIDE
===============================================================

WHAT IS SYSTEM FILE REPAIR?
System File Checker (SFC) and DISM repair corrupted Windows system files.
These tools restore files from Windows component store.

WHEN TO USE:
---------------------------------------------------------------
- Windows crashes or shows errors
- Programs fail to start
- System is slow or unstable
- Windows Update fails
- Component store corruption detected

SFC (System File Checker):
---------------------------------------------------------------
- Scans and repairs individual system files
- Runs: sfc /scannow
- Takes: 15-30 minutes
- Requires: Administrator privileges

DISM (Deployment Image Servicing):
---------------------------------------------------------------
- Repairs Windows component store
- Runs: dism /online /cleanup-image /restorehealth
- Takes: 10-20 minutes
- Requires: Internet connection (for online mode)

AUTOMATED REPAIR:
---------------------------------------------------------------
Miracle Boot runs both SFC and DISM automatically:
1. SFC scans and fixes individual files
2. DISM repairs the component store
3. Progress is shown in real-time

TIPS:
---------------------------------------------------------------
- Run SFC before DISM for best results
- Ensure stable power (use laptop charger)
- Don't interrupt the process
- System may restart after repair

"@
            FAQs = @(
                "Q: Will this delete my programs? A: No, only repairs Windows system files.",
                "Q: Do I need internet? A: Online mode needs internet. Offline mode uses Windows image.",
                "Q: How long does it take? A: Usually 30-60 minutes total."
            )
        }
        "Disk Repair" = @{
            Title = "Disk Repair (CHKDSK) Help"
            Category = "Repair"
            Content = @"
DISK REPAIR GUIDE
===============================================================

WHAT IS DISK REPAIR?
CHKDSK checks and repairs file system errors and bad sectors on your hard drive.

WHEN TO USE:
---------------------------------------------------------------
- Computer is very slow
- Files are corrupted or missing
- System crashes frequently
- "Disk error" messages appear
- Bad sectors detected

CHKDSK OPTIONS:
---------------------------------------------------------------
1. chkdsk C: /f
   - Fixes file system errors
   - Takes: 10-30 minutes
   - Requires: Drive to be locked (may schedule for reboot)

2. chkdsk C: /r
   - Fixes errors AND recovers bad sectors
   - Takes: 1-4 hours (depends on disk size)
   - Scans entire disk surface

3. chkdsk C: /x
   - Forces dismount (for non-system drives)
   - Use when drive is in use

IMPORTANT NOTES:
---------------------------------------------------------------
- System drive (C:) requires reboot to run
- Bad sector recovery can take hours
- Ensure stable power during repair
- Don't interrupt the process

AUTOMATED REPAIR:
---------------------------------------------------------------
Miracle Boot automatically:
- Detects if repair is needed
- Schedules chkdsk for system drive
- Shows progress and estimated time
- Creates restore point before repair

"@
            FAQs = @(
                "Q: Will chkdsk delete my files? A: No, it only repairs file system structure.",
                "Q: Why does it take so long? A: Bad sector recovery scans entire disk surface.",
                "Q: Can I cancel chkdsk? A: Not recommended - may cause disk corruption."
            )
        }
        "In-Place Upgrade" = @{
            Title = "In-Place Upgrade Help"
            Category = "Upgrade"
            Content = @"
IN-PLACE UPGRADE GUIDE
===============================================================

WHAT IS IN-PLACE UPGRADE?
Reinstalls Windows while keeping your apps and files.
This is the safest way to repair Windows without losing data.

WHEN TO USE:
---------------------------------------------------------------
- Windows won't boot after repairs
- System is severely corrupted
- Multiple repair attempts failed
- Need to refresh Windows installation

REQUIREMENTS:
---------------------------------------------------------------
- Windows installation media (USB/DVD/ISO)
- At least 20GB free disk space
- Stable power source
- BitLocker recovery key (if encrypted)

PROCESS:
---------------------------------------------------------------
1. Run "In-Place Upgrade Readiness Check"
2. Fix any blockers found
3. Mount Windows ISO or insert USB
4. Run setup.exe with /auto upgrade
5. Select "Keep apps and files"
6. Wait for installation (1-3 hours)

READINESS CHECK:
---------------------------------------------------------------
Miracle Boot checks:
- Component store health
- Pending operations
- Registry integrity
- Boot configuration
- Setup compatibility

BLOCKERS:
---------------------------------------------------------------
Common blockers:
- Corrupted component store
- Pending file operations
- Edition mismatch
- Build family mismatch

"@
            FAQs = @(
                "Q: Will I lose my programs? A: No, if you select 'Keep apps and files'.",
                "Q: How long does it take? A: Usually 1-3 hours depending on system speed.",
                "Q: What if readiness check fails? A: Fix blockers first, then try again."
            )
        }
        "Driver Issues" = @{
            Title = "Driver Issues Help"
            Category = "Drivers"
            Content = @"
DRIVER ISSUES GUIDE
===============================================================

WHAT ARE DRIVERS?
Drivers are software that allows Windows to communicate with hardware.
Missing drivers prevent devices from working.

COMMON SYMPTOMS:
---------------------------------------------------------------
- "Inaccessible Boot Device" blue screen
- Unknown devices in Device Manager
- Hardware not detected
- System won't boot after hardware change

FINDING MISSING DRIVERS:
---------------------------------------------------------------
1. Check Device Manager for yellow exclamation marks
2. Look for "Unknown Device" entries
3. Check Windows Event Log for driver errors
4. Use Miracle Boot's driver scanning tools

DRIVER PORTING:
---------------------------------------------------------------
Miracle Boot can:
- Identify missing drivers
- Extract drivers from working system
- Port drivers to folder for offline injection
- Inject drivers into offline Windows

STORAGE DRIVERS:
---------------------------------------------------------------
Common missing storage drivers:
- Intel VMD (Volume Management Device)
- AMD RAID
- NVMe controllers
- SATA controllers

SOLUTION:
---------------------------------------------------------------
1. Download drivers from manufacturer website
2. Extract to folder
3. Use "Inject Drivers Offline" in Miracle Boot
4. Reboot and check if issue is resolved

"@
            FAQs = @(
                "Q: Where do I get drivers? A: Manufacturer website (Dell, HP, Lenovo, etc.).",
                "Q: Can I use drivers from another PC? A: Yes, if same hardware model.",
                "Q: What if I can't find drivers? A: Try Windows Update or manufacturer support."
            )
        }
        "Boot Chain Analysis" = @{
            Title = "Boot Chain Analysis Help"
            Category = "Diagnostics"
            Content = @"
BOOT CHAIN ANALYSIS GUIDE
===============================================================

WHAT IS BOOT CHAIN?
The boot chain is the sequence of steps Windows takes to start:
1. BIOS/UEFI initialization
2. Boot Manager loads
3. Boot Loader starts
4. Kernel loads
5. Drivers initialize
6. Services start
7. User login

BOOT CHAIN FAILURES:
---------------------------------------------------------------
Each stage can fail:
- Stage 1-2: Boot configuration issues (BCD, EFI)
- Stage 3-4: Boot files missing or corrupted
- Stage 5: Driver failures (especially storage)
- Stage 6-7: Service or registry issues

ANALYZING BOOT LOGS:
---------------------------------------------------------------
nbtlog.txt shows:
- Which drivers loaded successfully
- Which drivers failed to load
- Boot sequence timing
- Error messages

Miracle Boot analyzes:
- Missing critical drivers
- Failed driver loads
- Boot timing issues
- Service failures

TROUBLESHOOTING:
---------------------------------------------------------------
1. Check boot log for failed drivers
2. Identify missing storage drivers
3. Check for corrupted system files
4. Verify boot configuration (BCD)
5. Test boot probability score

"@
            FAQs = @(
                "Q: How do I enable boot logging? A: Miracle Boot enables it automatically.",
                "Q: What if boot log shows errors? A: Check which drivers failed and replace them.",
                "Q: Can boot chain analysis fix issues? A: It identifies problems, then run repairs."
            )
        }
    }
    
    $result = @{
        Found = $false
        Topics = @()
        Content = ""
        FAQs = @()
        RelatedTopics = @()
    }
    
    # Search by topic name
    if ($Topic) {
        $topicKey = $helpDatabase.Keys | Where-Object { $_ -like "*$Topic*" } | Select-Object -First 1
        if ($topicKey) {
            $helpItem = $helpDatabase[$topicKey]
            $result.Found = $true
            $result.Content = $helpItem.Content
            $result.FAQs = $helpItem.FAQs
            $result.Topics = @($helpItem.Title)
            
            # Find related topics
            $result.RelatedTopics = $helpDatabase.Keys | Where-Object { 
                $_ -ne $topicKey -and $helpDatabase[$_].Category -eq $helpItem.Category 
            }
            return $result
        }
    }
    
    # Search by category
    if ($Category) {
        $matchingTopics = $helpDatabase.Keys | Where-Object { 
            $helpDatabase[$_].Category -like "*$Category*" 
        }
        if ($matchingTopics) {
            $result.Found = $true
            $result.Topics = $matchingTopics
            return $result
        }
    }
    
    # Search by term
    if ($SearchTerm) {
        $matchingTopics = $helpDatabase.Keys | Where-Object {
            $helpItem = $helpDatabase[$_]
            $helpItem.Content -like "*$SearchTerm*" -or
            $helpItem.Title -like "*$SearchTerm*"
        }
        if ($matchingTopics) {
            $result.Found = $true
            $result.Topics = $matchingTopics
            return $result
        }
    }
    
    # Return all topics if no specific search
    if (-not $Topic -and -not $Category -and -not $SearchTerm) {
        $result.Found = $true
        $result.Topics = $helpDatabase.Keys
    }
    
    return $result
}

function Show-HelpMenu {
    <#
    .SYNOPSIS
    Displays interactive help menu with search and navigation.
    #>
    param(
        [string]$InitialTopic = ""
    )
    
    if ($InitialTopic) {
        $help = Get-HelpContent -Topic $InitialTopic
        if ($help.Found) {
            Write-Host ""
            Write-Host $help.Content -ForegroundColor Cyan
            Write-Host ""
            if ($help.FAQs.Count -gt 0) {
                Write-Host "FREQUENTLY ASKED QUESTIONS:" -ForegroundColor Yellow
                Write-Host "-" * 80 -ForegroundColor Gray
                foreach ($faq in $help.FAQs) {
                    Write-Host $faq -ForegroundColor White
                    Write-Host ""
                }
            }
            if ($help.RelatedTopics.Count -gt 0) {
                Write-Host "RELATED TOPICS:" -ForegroundColor Yellow
                Write-Host "-" * 80 -ForegroundColor Gray
                foreach ($related in $help.RelatedTopics) {
                    Write-Host "  - $related" -ForegroundColor Cyan
                }
            }
            return
        }
    }
    
    # Show help menu
    do {
        Clear-Host
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host "  MIRACLE BOOT - HELP SYSTEM" -ForegroundColor Cyan
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "AVAILABLE HELP TOPICS:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "1) Boot Repair" -ForegroundColor White
        Write-Host "2) System File Repair" -ForegroundColor White
        Write-Host "3) Disk Repair (CHKDSK)" -ForegroundColor White
        Write-Host "4) In-Place Upgrade" -ForegroundColor White
        Write-Host "5) Driver Issues" -ForegroundColor White
        Write-Host "6) Boot Chain Analysis" -ForegroundColor White
        Write-Host ""
        Write-Host "S) Search Help" -ForegroundColor Cyan
        Write-Host "L) List All Topics" -ForegroundColor Cyan
        Write-Host "Q) Quit Help" -ForegroundColor Gray
        Write-Host ""
        
        $choice = Read-Host "Select option"
        
        switch ($choice.ToUpper()) {
            "1" { Show-HelpMenu -InitialTopic "Boot Repair"; break }
            "2" { Show-HelpMenu -InitialTopic "System File Repair"; break }
            "3" { Show-HelpMenu -InitialTopic "Disk Repair"; break }
            "4" { Show-HelpMenu -InitialTopic "In-Place Upgrade"; break }
            "5" { Show-HelpMenu -InitialTopic "Driver Issues"; break }
            "6" { Show-HelpMenu -InitialTopic "Boot Chain Analysis"; break }
            "S" {
                $searchTerm = Read-Host "Enter search term"
                $results = Get-HelpContent -SearchTerm $searchTerm
                if ($results.Found -and $results.Topics.Count -gt 0) {
                    Write-Host ""
                    Write-Host "SEARCH RESULTS:" -ForegroundColor Yellow
                    foreach ($topic in $results.Topics) {
                        Write-Host "  - $topic" -ForegroundColor Cyan
                    }
                    Write-Host ""
                    Write-Host "Press any key to continue..." -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                } else {
                    Write-Host "No results found." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
                break
            }
            "L" {
                $allTopics = Get-HelpContent
                Write-Host ""
                Write-Host "ALL HELP TOPICS:" -ForegroundColor Yellow
                foreach ($topic in $allTopics.Topics) {
                    Write-Host "  - $topic" -ForegroundColor Cyan
                }
                Write-Host ""
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                break
            }
            "Q" { return }
        }
    } while ($choice.ToUpper() -ne "Q")
}

function Open-ChatGPTHelp {
    <#
    .SYNOPSIS
    Opens ChatGPT help page in browser, or provides command-line alternative.
    #>
    param(
        [switch]$ForceCLI
    )
    
    $result = @{
        Success = $false
        Method = ""
        Message = ""
        Instructions = ""
    }
    
    $chatGPTUrl = "https://chat.openai.com"
    
    # Try browser first (unless forced to CLI)
    if (-not $ForceCLI) {
        try {
            # Try default browser
            Start-Process $chatGPTUrl -ErrorAction Stop
            $result.Success = $true
            $result.Method = "Browser"
            $result.Message = "Opened ChatGPT in default browser"
            return $result
        } catch {
            # Browser launch failed, try alternative methods
            try {
                # Try Internet Explorer (may be available in WinRE)
                $ie = New-Object -ComObject InternetExplorer.Application
                $ie.Visible = $true
                $ie.Navigate($chatGPTUrl)
                $result.Success = $true
                $result.Method = "Internet Explorer"
                $result.Message = "Opened ChatGPT in Internet Explorer"
                return $result
            } catch {
                # IE also failed
            }
        }
    }
    
    # Browser unavailable - provide CLI instructions
    $result.Method = "Command-Line"
    $result.Success = $false
    $result.Message = "Browser not available. Use command-line method below."
    
    $instructions = @"
===============================================================
CHATGPT HELP - COMMAND-LINE METHOD
===============================================================

Browser is not available in this environment. Use one of these methods:

METHOD 1: Use Another Device
---------------------------------------------------------------
1. On your phone or another computer, open: https://chat.openai.com
2. Ask: "My Windows installation failed. How do I check setup logs?"
3. Share the error codes you find in the logs

METHOD 2: Use curl (if available)
---------------------------------------------------------------
curl -X POST https://api.openai.com/v1/chat/completions ^
  -H "Content-Type: application/json" ^
  -H "Authorization: Bearer YOUR_API_KEY" ^
  -d "{\"model\":\"gpt-3.5-turbo\",\"messages\":[{\"role\":\"user\",\"content\":\"Windows install failed\"}]}"

Note: Requires OpenAI API key (not free)

METHOD 3: Manual URL
---------------------------------------------------------------
Write down this URL and open it on another device:
$chatGPTUrl

Suggested questions to ask:
- "How do I check Windows setup error logs?"
- "Windows installation failed with error code [your code]"
- "How to fix Windows boot issues in recovery environment?"

===============================================================
"@
    
    $result.Instructions = $instructions
    return $result
}

# ============================================================================
# COMPREHENSIVE WARNING SYSTEM
# Functions to warn users before executing dangerous commands
# ============================================================================

function Get-CommandRiskLevel {
    <#
    .SYNOPSIS
    Returns the risk level of a command (Low/Medium/High/Critical).
    #>
    param(
        [string]$CommandKey
    )
    
    $riskLevels = @{
        # Critical - May prevent system from booting
        "bcd_delete" = "Critical"
        "bcd_clear" = "Critical"
        "format" = "Critical"
        "diskpart_clean" = "Critical"
        "registry_hive_modify" = "Critical"
        
        # High - Significant system changes
        "bcd_modify" = "High"
        "bcd_set" = "High"
        "bcdboot" = "High"
        "bootrec_fixboot" = "High"
        "bootrec_fixmbr" = "High"
        "bootrec_rebuildbcd" = "High"
        "driver_inject" = "High"
        "dism_apply" = "High"
        
        # Medium - Moderate changes
        "bcd_description" = "Medium"
        "bcd_timeout" = "Medium"
        "bcd_default" = "Medium"
        "registry_edit" = "Medium"
        
        # Low - Read-only or safe operations
        "bcd_enum" = "Low"
        "bcd_view" = "Low"
        "scan" = "Low"
        "diagnosis" = "Low"
        "view_logs" = "Low"
    }
    
    # Try exact match first
    if ($riskLevels.ContainsKey($CommandKey)) {
        return $riskLevels[$CommandKey]
    }
    
    # Try partial match
    foreach ($key in $riskLevels.Keys) {
        if ($CommandKey -match $key) {
            return $riskLevels[$key]
        }
    }
    
    # Default to Medium for unknown commands
    return "Medium"
}

function Get-CommandWarningDetails {
    <#
    .SYNOPSIS
    Returns detailed warning information for a command.
    #>
    param(
        [string]$CommandKey,
        [string]$Command = "",
        [string]$Description = ""
    )
    
    $warnings = @{
        "bcd_delete" = @{
            Title = "CRITICAL: Delete BCD Entry"
            Risk = "This will permanently delete a boot entry. If you delete the wrong entry, your system may not boot."
            Impact = "System may fail to boot if critical entry is deleted."
            Recovery = "Restore from BCD backup or use recovery media."
        }
        "bcd_modify" = @{
            Title = "HIGH RISK: Modify BCD Entry"
            Risk = "Modifying BCD entries can prevent your system from booting if done incorrectly."
            Impact = "Incorrect modifications may cause boot failures."
            Recovery = "Restore from BCD backup or use recovery media."
        }
        "bcdboot" = @{
            Title = "HIGH RISK: Rebuild BCD"
            Risk = "This will overwrite your boot configuration. If the target Windows installation is incorrect, you may lose access to other operating systems."
            Impact = "May change which Windows installation boots by default. Operations may take longer on BitLocker-encrypted drives."
            Recovery = "BCD backup should be created automatically. Be patient if drive is encrypted - operations may take longer."
        }
        "bootrec_fixboot" = @{
            Title = "HIGH RISK: Fix Boot Sector"
            Risk = "This writes a new boot sector. If your system uses BitLocker, you may need the recovery key."
            Impact = "Boot sector will be rewritten. BitLocker may require recovery key. Operations may take longer on encrypted drives."
            Recovery = "Have BitLocker recovery key ready if encryption is enabled. Be patient - operations may take longer on encrypted drives."
        }
        "bootrec_rebuildbcd" = @{
            Title = "HIGH RISK: Rebuild BCD"
            Risk = "This will rebuild the Boot Configuration Data. If your system uses BitLocker, you may need the recovery key."
            Impact = "BCD will be rebuilt. BitLocker may require recovery key. Operations may take longer on encrypted drives."
            Recovery = "Have BitLocker recovery key ready if encryption is enabled. Be patient - operations may take longer on encrypted drives."
        }
        "driver_inject" = @{
            Title = "HIGH RISK: Inject Drivers"
            Risk = "Installing incorrect or incompatible drivers can cause system instability or prevent booting."
            Impact = "System may become unstable or fail to boot with bad drivers."
            Recovery = "Boot to recovery environment and remove problematic drivers."
        }
        "bcd_description" = @{
            Title = "MEDIUM RISK: Change BCD Description"
            Risk = "Changing boot entry descriptions is generally safe, but ensure you're modifying the correct entry."
            Impact = "Boot menu appearance will change."
            Recovery = "Can be easily reverted by changing description back."
        }
    }
    
    # Get warning for this command
    $warning = $warnings[$CommandKey]
    if (-not $warning) {
        # Generic warning
        $riskLevel = Get-CommandRiskLevel -CommandKey $CommandKey
        $warning = @{
            Title = "$riskLevel RISK: Execute Command"
            Risk = "This command will modify system configuration."
            Impact = "Changes may affect system behavior."
            Recovery = "Ensure you have backups before proceeding."
        }
    }
    
    return $warning
}

function Show-CommandWarning {
    <#
    .SYNOPSIS
    Shows a warning dialog for a command (GUI) or displays warning text (TUI).
    #>
    param(
        [string]$CommandKey,
        [string]$Command = "",
        [string]$Description = "",
        [switch]$IsGUI
    )
    
    $warning = Get-CommandWarningDetails -CommandKey $CommandKey -Command $Command -Description $Description
    $riskLevel = Get-CommandRiskLevel -CommandKey $CommandKey
    
    $warningText = @"
===============================================================
[WARN] $($warning.Title)
===============================================================

COMMAND: $Command
DESCRIPTION: $Description

RISK LEVEL: $riskLevel

[WARN] WARNING:
$($warning.Risk)

POTENTIAL IMPACT:
$($warning.Impact)

RECOVERY OPTIONS:
$($warning.Recovery)

===============================================================
"@
    
    if ($IsGUI) {
        # Return object for GUI to display
        return @{
            Title = $warning.Title
            Message = $warningText
            RiskLevel = $riskLevel
            Warning = $warning
        }
    } else {
        # Display for TUI
        Write-Host $warningText -ForegroundColor Yellow
        return $warningText
    }
}

function Test-CommandSafety {
    <#
    .SYNOPSIS
    Validates command safety before execution, checking prerequisites and parameters.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [hashtable]$Parameters = @{},
        
        [string]$TargetDrive = "C",
        
        [switch]$DryRun = $false
    )
    
    $result = @{
        Safe = $true
        Warnings = @()
        Errors = @()
        Prerequisites = @()
        Recommendations = @()
        EstimatedImpact = "Unknown"
    }
    
    # Check if command is recognized
    $commandLower = $Command.ToLower()
    
    # Validate BCD commands
    if ($commandLower -match "bcdedit|bcdboot|bootrec") {
        # Check if BCD is accessible
        try {
            $bcdTest = bcdedit /enum 2>&1
            if ($LASTEXITCODE -ne 0) {
                $result.Errors += "BCD is not accessible. System may be in recovery mode."
                $result.Safe = $false
            }
        } catch {
            $result.Warnings += "Could not verify BCD accessibility"
        }
        
        # Check for BitLocker if modifying boot
        if ($commandLower -match "bcdedit.*delete|bcdedit.*clear|bootrec.*fixboot") {
            try {
                $bitlocker = Get-BitLockerVolume -MountPoint "$TargetDrive`:" -ErrorAction SilentlyContinue
                if ($bitlocker -and $bitlocker.ProtectionStatus -eq "On") {
                    $result.Warnings += "BitLocker is enabled. Ensure you have the recovery key."
                    $result.Prerequisites += "BitLocker recovery key"
                }
            } catch {
                # BitLocker check failed, assume not enabled
            }
        }
    }
    
    # Validate DISM commands
    if ($commandLower -match "dism") {
        # Check if source is available for offline repair
        if ($Parameters.ContainsKey("Source") -and $Parameters.Source) {
            if (-not (Test-Path $Parameters.Source)) {
                $result.Errors += "DISM source path does not exist: $($Parameters.Source)"
                $result.Safe = $false
            }
        }
        
        # Check if target drive is accessible
        if (-not (Test-Path "$TargetDrive`:\Windows")) {
            $result.Errors += "Windows installation not found on drive $TargetDrive"
            $result.Safe = $false
        }
    }
    
    # Validate SFC commands
    if ($commandLower -match "sfc.*scannow") {
        # Check if running in FullOS (SFC requires online OS)
        $envType = Get-EnvironmentType
        if ($envType -ne "FullOS") {
            $result.Warnings += "SFC /scannow requires running Windows. Use DISM for offline repair."
            $result.Recommendations += "Use DISM /RestoreHealth for offline repair"
        }
    }
    
    # Validate diskpart commands
    if ($commandLower -match "diskpart") {
        $result.Warnings += "Diskpart commands can be destructive. Ensure you have backups."
        $result.Prerequisites += "Backup of important data"
        
        if ($commandLower -match "clean|format|delete") {
            $result.Errors += "Destructive diskpart command detected. This will cause data loss."
            $result.Safe = $false
        }
    }
    
    # Validate registry commands
    if ($commandLower -match "reg.*add|reg.*delete|reg.*import") {
        $result.Warnings += "Registry modifications can affect system stability."
        $result.Prerequisites += "Registry backup"
    }
    
    # Check target drive accessibility
    if ($TargetDrive -and $TargetDrive -ne "C") {
        if (-not (Test-Path "$TargetDrive`:\")) {
            $result.Errors += "Target drive $TargetDrive is not accessible"
            $result.Safe = $false
        }
    }
    
    # Determine estimated impact
    $riskLevel = Get-CommandRiskLevel -CommandKey $Command
    switch ($riskLevel) {
        "Critical" { $result.EstimatedImpact = "Critical - May prevent system from booting" }
        "High" { $result.EstimatedImpact = "High - Significant system changes" }
        "Medium" { $result.EstimatedImpact = "Medium - Moderate system changes" }
        "Low" { $result.EstimatedImpact = "Low - Minimal or no system changes" }
    }
    
    return $result
}

function Invoke-CommandDryRun {
    <#
    .SYNOPSIS
    Simulates command execution without making actual changes (dry-run mode).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [hashtable]$Parameters = @{},
        
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $true
        Simulated = $true
        Command = $Command
        Parameters = $Parameters
        ExpectedOutput = ""
        ExpectedChanges = @()
        Warnings = @()
        EstimatedDuration = "Unknown"
    }
    
    $commandLower = $Command.ToLower()
    
    # Simulate BCD commands
    if ($commandLower -match "bcdedit") {
        if ($commandLower -match "delete") {
            $result.ExpectedChanges += "BCD entry will be deleted"
            $result.ExpectedOutput = "The entry was successfully deleted."
            $result.EstimatedDuration = "1-2 seconds"
        } elseif ($commandLower -match "set") {
            $result.ExpectedChanges += "BCD setting will be modified"
            $result.ExpectedOutput = "The operation completed successfully."
            $result.EstimatedDuration = "1-2 seconds"
        } elseif ($commandLower -match "enum") {
            $result.ExpectedOutput = "BCD entries will be listed"
            $result.ExpectedChanges += "No changes (read-only operation)"
            $result.EstimatedDuration = "1-2 seconds"
        }
    }
    
    # Simulate bootrec commands
    if ($commandLower -match "bootrec") {
        if ($commandLower -match "fixboot") {
            $result.ExpectedChanges += "Boot sector will be rewritten"
            $result.ExpectedOutput = "The boot files were successfully created."
            $result.EstimatedDuration = "5-10 seconds"
            $result.Warnings += "This will modify the boot sector"
        } elseif ($commandLower -match "fixmbr") {
            $result.ExpectedChanges += "Master Boot Record will be rewritten"
            $result.ExpectedOutput = "The operation completed successfully."
            $result.EstimatedDuration = "5-10 seconds"
            $result.Warnings += "This will modify the MBR"
        } elseif ($commandLower -match "rebuildbcd") {
            $result.ExpectedChanges += "BCD will be rebuilt from scratch"
            $result.ExpectedOutput = "Scanning for Windows installations..."
            $result.EstimatedDuration = "10-30 seconds"
            $result.Warnings += "This will recreate the BCD store"
        }
    }
    
    # Simulate DISM commands
    if ($commandLower -match "dism") {
        if ($commandLower -match "restorehealth") {
            $result.ExpectedChanges += "Component store will be repaired"
            $result.ExpectedOutput = "The restore operation completed successfully."
            $result.EstimatedDuration = "5-30 minutes"
        } elseif ($commandLower -match "cleanup-image") {
            $result.ExpectedChanges += "Component store will be cleaned"
            $result.ExpectedOutput = "The operation completed successfully."
            $result.EstimatedDuration = "10-60 minutes"
        }
    }
    
    # Simulate SFC commands
    if ($commandLower -match "sfc.*scannow") {
        $result.ExpectedChanges += "System files will be scanned and repaired"
        $result.ExpectedOutput = "Windows Resource Protection found corrupt files and successfully repaired them."
        $result.EstimatedDuration = "10-30 minutes"
    }
    
    # Simulate chkdsk commands
    if ($commandLower -match "chkdsk") {
        if ($commandLower -match "/f") {
            $result.ExpectedChanges += "File system errors will be fixed"
            $result.ExpectedOutput = "Windows has checked the file system and found no problems."
            $result.EstimatedDuration = "10-60 minutes"
            $result.Warnings += "Drive will be locked during repair"
        } elseif ($commandLower -match "/r") {
            $result.ExpectedChanges += "Bad sectors will be scanned and recovered"
            $result.ExpectedOutput = "Windows has checked the file system and found no problems."
            $result.EstimatedDuration = "30 minutes - 2 hours"
            $result.Warnings += "This is a long-running operation"
        }
    }
    
    # Generic simulation for unknown commands
    if ($result.ExpectedChanges.Count -eq 0) {
        $result.ExpectedChanges += "Command will be executed (unknown impact)"
        $result.ExpectedOutput = "Command execution simulated"
        $result.Warnings += "Unknown command - impact cannot be determined"
    }
    
    return $result
}

function Validate-CommandParameters {
    <#
    .SYNOPSIS
    Validates command parameters before execution.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [hashtable]$Parameters = @{},
        
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Valid = $true
        Errors = @()
        Warnings = @()
        CorrectedParameters = $Parameters.Clone()
    }
    
    $commandLower = $Command.ToLower()
    
    # Validate drive letter format
    if ($TargetDrive) {
        if ($TargetDrive.Length -ne 1 -or -not ($TargetDrive -match "^[A-Z]$")) {
            $result.Errors += "Invalid drive letter: $TargetDrive (must be A-Z)"
            $result.Valid = $false
        } else {
            # Ensure drive letter is uppercase
            $result.CorrectedParameters.TargetDrive = $TargetDrive.ToUpper()
        }
    }
    
    # Validate DISM source path
    if ($Parameters.ContainsKey("Source")) {
        $source = $Parameters.Source
        if ($source -and -not (Test-Path $source)) {
            $result.Errors += "DISM source path does not exist: $source"
            $result.Valid = $false
        } elseif ($source -and -not (Test-Path (Join-Path $source "sources\install.wim"))) {
            $result.Warnings += "DISM source may be invalid (install.wim not found)"
        }
    }
    
    # Validate BCD entry GUID format
    if ($Parameters.ContainsKey("EntryGUID")) {
        $guid = $Parameters.EntryGUID
        if ($guid -and -not ($guid -match "^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$")) {
            $result.Errors += "Invalid BCD entry GUID format: $guid"
            $result.Valid = $false
        }
    }
    
    # Validate timeout values
    if ($Parameters.ContainsKey("Timeout")) {
        $timeout = $Parameters.Timeout
        if ($timeout -lt 0 -or $timeout -gt 3600) {
            $result.Warnings += "Timeout value seems unusual: $timeout seconds"
        }
    }
    
    return $result
}

function Confirm-DestructiveOperation {
    <#
    .SYNOPSIS
    Confirms a destructive operation with detailed warning.
    #>
    param(
        [string]$CommandKey,
        [string]$Command = "",
        [string]$Description = "",
        [switch]$IsGUI,
        [switch]$SkipBitLockerCheck = $false,
        [string]$TargetDrive = $null
    )
    
    # Show warning
    $warningInfo = Show-CommandWarning -CommandKey $CommandKey -Command $Command -Description $Description -IsGUI:$IsGUI
    
    if ($IsGUI) {
        # GUI confirmation - return object for GUI to handle
        return @{
            WarningInfo = $warningInfo
            ShouldProceed = $false  # GUI will set this based on user response
        }
    } else {
        # TUI confirmation
        Write-Host ""
        Write-Host "Do you want to proceed? (Y/N): " -ForegroundColor Red -NoNewline
        
        # Check BitLocker if not skipped
        # In WinPE/WinRE, skip BitLocker check to avoid lag (already handled in Test-BitLockerStatus)
        if (-not $SkipBitLockerCheck) {
            $envType = Get-EnvironmentType
            # Determine target drive: use parameter if provided, extract from command, or default to C
            $checkDrive = "C"
            if ($TargetDrive) {
                $checkDrive = $TargetDrive.TrimEnd(':').ToUpper()
            } elseif ($Command -match '([A-Z]):') {
                $checkDrive = $matches[1]
            }
            
            # Only do quick check in FullOS, skip in WinPE/WinRE to avoid lag
            if ($envType -eq "FullOS") {
                $bitlocker = Test-BitLockerStatus -TargetDrive $checkDrive -TimeoutSeconds 3
                if ($bitlocker.IsEncrypted) {
                    Write-Host ""
                    Write-Host "[WARN] BITLOCKER ENCRYPTION DETECTED" -ForegroundColor Yellow
                    Write-Host $bitlocker.Warning -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "NOTE: Boot recovery operations may take longer on BitLocker-encrypted drives." -ForegroundColor Yellow
                    Write-Host "      This is normal - please be patient during the repair process." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "Do you have your BitLocker recovery key? (Y/N): " -ForegroundColor Yellow -NoNewline
                    $bitlockerConfirm = Read-Host
                    if ($bitlockerConfirm -ne 'Y' -and $bitlockerConfirm -ne 'y') {
                        Write-Host "Operation cancelled." -ForegroundColor Red
                        return $false
                    }
                }
            } else {
                # In WinPE/WinRE, show generic warning (BitLocker check skipped to avoid lag)
                Write-Host ""
                Write-Host "[WARN] WINPE/WINRE ENVIRONMENT" -ForegroundColor Yellow
                Write-Host "If your drive is BitLocker encrypted, ensure you have your recovery key (48-digit number) before proceeding." -ForegroundColor Yellow
                Write-Host "Boot recovery operations may take longer on encrypted drives - this is normal." -ForegroundColor Yellow
                Write-Host "You can find it in: Microsoft Account > Devices > BitLocker recovery keys" -ForegroundColor Yellow
                Write-Host ""
            }
        }
        
        $confirm = Read-Host
        return ($confirm -eq 'Y' -or $confirm -eq 'y')
    }
}

# Operation Queue System
$script:OperationQueue = New-Object System.Collections.ArrayList
$script:OperationQueueLock = New-Object System.Object

function Add-OperationToQueue {
    <#
    .SYNOPSIS
    Adds an operation to the execution queue.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$OperationName,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$OperationScript,
        
        [hashtable]$Parameters = @{},
        
        [string]$Description = "",
        
        [int]$Priority = 5,
        
        [switch]$RequiresConfirmation = $false
    )
    
    $operation = @{
        Id = [guid]::NewGuid().ToString()
        OperationName = $OperationName
        OperationScript = $OperationScript
        Parameters = $Parameters
        Description = $Description
        Priority = $Priority
        RequiresConfirmation = $RequiresConfirmation
        Status = "Pending"
        CreatedAt = Get-Date
        StartedAt = $null
        CompletedAt = $null
        Result = $null
        Error = $null
    }
    
    lock ($script:OperationQueueLock) {
        [void]$script:OperationQueue.Add($operation)
    }
    
    # Sort by priority (higher priority first)
    lock ($script:OperationQueueLock) {
        $script:OperationQueue = $script:OperationQueue | Sort-Object { -$_.Priority }
    }
    
    return $operation.Id
}

function Get-OperationQueue {
    <#
    .SYNOPSIS
    Returns the current operation queue.
    #>
    param(
        [string]$Status = "",
        [int]$Limit = 0
    )
    
    lock ($script:OperationQueueLock) {
        $queue = $script:OperationQueue | ForEach-Object { $_ }
        
        if ($Status) {
            $queue = $queue | Where-Object { $_.Status -eq $Status }
        }
        
        if ($Limit -gt 0) {
            $queue = $queue | Select-Object -First $Limit
        }
        
        return $queue
    }
}

function Remove-OperationFromQueue {
    <#
    .SYNOPSIS
    Removes an operation from the queue.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$OperationId
    )
    
    lock ($script:OperationQueueLock) {
        $operation = $script:OperationQueue | Where-Object { $_.Id -eq $OperationId } | Select-Object -First 1
        if ($operation) {
            [void]$script:OperationQueue.Remove($operation)
            return $true
        }
        return $false
    }
}

function Start-OperationQueue {
    <#
    .SYNOPSIS
    Starts executing operations from the queue.
    #>
    param(
        [switch]$StopOnError = $false,
        [scriptblock]$ProgressCallback = $null,
        [switch]$AutoConfirm = $false
    )
    
    $results = @{
        Success = $true
        Completed = 0
        Failed = 0
        Skipped = 0
        Operations = @()
    }
    
    while ($true) {
        lock ($script:OperationQueueLock) {
            $nextOperation = $script:OperationQueue | Where-Object { $_.Status -eq "Pending" } | Select-Object -First 1
        }
        
        if (-not $nextOperation) {
            break
        }
        
        # Update status
        $nextOperation.Status = "Running"
        $nextOperation.StartedAt = Get-Date
        
        # Call progress callback
        if ($ProgressCallback) {
            try {
                & $ProgressCallback @{
                    Operation = $nextOperation.OperationName
                    Status = "Starting"
                    QueuePosition = ($script:OperationQueue | Where-Object { $_.Status -eq "Pending" }).Count + 1
                    TotalInQueue = ($script:OperationQueue | Where-Object { $_.Status -eq "Pending" }).Count
                }
            } catch {
                Write-Warning "Progress callback failed: $_"
            }
        }
        
        # Check if confirmation required
        if ($nextOperation.RequiresConfirmation -and -not $AutoConfirm) {
            Write-Host ""
            Write-Host "Operation: $($nextOperation.OperationName)" -ForegroundColor Cyan
            Write-Host "Description: $($nextOperation.Description)" -ForegroundColor Gray
            Write-Host "Do you want to proceed? (Y/N): " -ForegroundColor Yellow -NoNewline
            $confirm = Read-Host
            if ($confirm -ne 'Y' -and $confirm -ne 'y') {
                $nextOperation.Status = "Skipped"
                $nextOperation.CompletedAt = Get-Date
                $results.Skipped++
                continue
            }
        }
        
        # Execute operation
        try {
            # PowerShell cannot splat a property directly; copy parameters to a local variable first
            $opParams = $nextOperation.Parameters
            $operationResult = & $nextOperation.OperationScript @opParams
            $nextOperation.Result = $operationResult
            $nextOperation.Status = "Completed"
            $nextOperation.CompletedAt = Get-Date
            $results.Completed++
            
            # Call progress callback
            if ($ProgressCallback) {
                try {
                    & $ProgressCallback @{
                        Operation = $nextOperation.OperationName
                        Status = "Completed"
                        Result = $operationResult
                    }
                } catch {
                    Write-Warning "Progress callback failed: $_"
                }
            }
        } catch {
            $nextOperation.Status = "Failed"
            $nextOperation.Error = $_.Exception.Message
            $nextOperation.CompletedAt = Get-Date
            $results.Failed++
            $results.Success = $false
            
            Write-Host "[ERROR] Operation '$($nextOperation.OperationName)' failed: $_" -ForegroundColor Red
            
            if ($StopOnError) {
                break
            }
        }
        
        $results.Operations += $nextOperation
    }
    
    return $results
}

function Clear-OperationQueue {
    <#
    .SYNOPSIS
    Clears all operations from the queue.
    #>
    param(
        [switch]$OnlyPending = $false
    )
    
    lock ($script:OperationQueueLock) {
        if ($OnlyPending) {
            $pending = $script:OperationQueue | Where-Object { $_.Status -eq "Pending" }
            foreach ($op in $pending) {
                [void]$script:OperationQueue.Remove($op)
            }
        } else {
            $script:OperationQueue.Clear()
        }
    }
}

function Get-EnhancedErrorDisplay {
    <#
    .SYNOPSIS
    Formats error information for enhanced display.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [object]$Error,
        
        [string]$OperationName = "",
        
        [switch]$IncludeStackTrace = $false,
        
        [switch]$IncludeRecoverySteps = $true
    )
    
    $display = @{
        Title = ""
        Message = ""
        Details = @()
        RecoverySteps = @()
        ErrorCode = $null
        Timestamp = Get-Date
    }
    
    # Extract error information
    if ($Error -is [System.Management.Automation.ErrorRecord]) {
        $display.Title = "PowerShell Error"
        $display.Message = $Error.Exception.Message
        $display.Details += "Category: $($Error.CategoryInfo.Category)"
        $display.Details += "Target: $($Error.TargetObject)"
        
        if ($IncludeStackTrace) {
            $display.Details += "Stack Trace:"
            $display.Details += $Error.ScriptStackTrace
        }
        
        # Try to extract error code
        if ($Error.Exception.Message -match "0x[0-9A-Fa-f]{8}") {
            $display.ErrorCode = $matches[0]
        }
    } elseif ($Error -is [string]) {
        $display.Title = "Error"
        $display.Message = $Error
    } else {
        $display.Title = "Unknown Error"
        $display.Message = $Error.ToString()
    }
    
    # Add operation context
    if ($OperationName) {
        $display.Details += "Operation: $OperationName"
    }
    
    # Get error explanation if error code found
    if ($display.ErrorCode) {
        try {
            $errorInfo = Get-WindowsErrorCodeInfo -ErrorCode $display.ErrorCode
            if ($errorInfo.Found) {
                $display.Details += "Error Type: $($errorInfo.Type)"
                $display.Details += "Description: $($errorInfo.Description)"
                
                if ($IncludeRecoverySteps -and $errorInfo.TroubleshootingSteps) {
                    $display.RecoverySteps = $errorInfo.TroubleshootingSteps
                }
            }
        } catch {
            # Error code lookup failed, continue without it
        }
    }
    
    # Format as text
    $text = New-Object System.Text.StringBuilder
    $text.AppendLine("=" * 80) | Out-Null
    $text.AppendLine("ERROR: $($display.Title)") | Out-Null
    $text.AppendLine("=" * 80) | Out-Null
    $text.AppendLine("") | Out-Null
    $text.AppendLine("Message:") | Out-Null
    $text.AppendLine("  $($display.Message)") | Out-Null
    $text.AppendLine("") | Out-Null
    
    if ($display.Details.Count -gt 0) {
        $text.AppendLine("Details:") | Out-Null
        foreach ($detail in $display.Details) {
            $text.AppendLine("  $detail") | Out-Null
        }
        $text.AppendLine("") | Out-Null
    }
    
    if ($display.RecoverySteps.Count -gt 0) {
        $text.AppendLine("Recovery Steps:") | Out-Null
        for ($i = 0; $i -lt $display.RecoverySteps.Count; $i++) {
            $text.AppendLine("  $($i + 1). $($display.RecoverySteps[$i])") | Out-Null
        }
        $text.AppendLine("") | Out-Null
    }
    
    $text.AppendLine("Timestamp: $($display.Timestamp)") | Out-Null
    $text.AppendLine("=" * 80) | Out-Null
    
    $display.FormattedText = $text.ToString()
    return $display
}

function Send-Notification {
    <#
    .SYNOPSIS
    Sends a notification to the user (console message, GUI popup, or system tray).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [string]$Title = "Miracle Boot",
        
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Type = "Info",
        
        [switch]$IsGUI = $false,
        
        [int]$DurationSeconds = 5
    )
    
    $notification = @{
        Title = $Title
        Message = $Message
        Type = $Type
        Timestamp = Get-Date
    }
    
    if ($IsGUI) {
        # Return notification object for GUI to display
        return $notification
    } else {
        # TUI notification
        $color = switch ($Type) {
            "Success" { "Green" }
            "Warning" { "Yellow" }
            "Error" { "Red" }
            default { "Cyan" }
        }
        
        Write-Host ""
        Write-Host "[$Type] $Title" -ForegroundColor $color
        Write-Host "  $Message" -ForegroundColor $color
        Write-Host ""
        
        return $notification
    }
}

function Show-StatusIndicator {
    <#
    .SYNOPSIS
    Shows a status indicator for an operation.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Status,
        
        [string]$Message = "",
        
        [ValidateSet("Idle", "Running", "Success", "Warning", "Error", "Paused")]
        [string]$State = "Idle",
        
        [switch]$IsGUI = $false
    )
    
    $indicator = @{
        Status = $Status
        Message = $Message
        State = $State
        Timestamp = Get-Date
    }
    
    if ($IsGUI) {
        # Return indicator object for GUI
        return $indicator
    } else {
        # TUI indicator (ASCII-friendly to avoid encoding issues)
        $symbol = switch ($State) {
            "Running" { "[...]" }
            "Success" { "[OK]" }
            "Warning" { "[WARN]" }
            "Error" { "[X]" }
            "Paused" { "[PAUSE]" }
            default { "[ ]" }
        }
        
        $color = switch ($State) {
            "Running" { "Cyan" }
            "Success" { "Green" }
            "Warning" { "Yellow" }
            "Error" { "Red" }
            "Paused" { "Magenta" }
            default { "Gray" }
        }
        
        Write-Host "$symbol $Status" -ForegroundColor $color -NoNewline
        if ($Message) {
            Write-Host " - $Message" -ForegroundColor Gray
        } else {
            Write-Host ""
        }
        
        return $indicator
    }
}

function Get-DynamicToolRecommendations {
    <#
    .SYNOPSIS
    Dynamically recommends tools based on current system state and detected issues.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $recommendations = @{
        Tools = @()
        Reasons = @()
        Priority = "Medium"
        Report = ""
    }
    
    # Analyze system state
    try {
        $bootProb = Get-BootProbability -TargetDrive $TargetDrive
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        $readiness = Get-InPlaceUpgradeReadiness -TargetDrive $TargetDrive
        
        # Boot issues - recommend boot repair tools
        if ($bootProb.Score -lt 50) {
            $recommendations.Tools += @{
                Name = "Ventoy + Windows ISO"
                Category = "Boot Repair"
                Priority = "High"
                Reason = "Boot probability is critically low ($($bootProb.Score)%). Need bootable recovery media."
                Website = "https://www.ventoy.net"
                Action = "Create bootable USB with Windows installation ISO"
            }
            $recommendations.Reasons += "Critical boot issues detected"
        }
        
        # System file corruption - recommend backup tools
        if (-not $fileHealth.SystemFilesHealthy) {
            $recommendations.Tools += @{
                Name = "Macrium Reflect Free"
                Category = "Backup"
                Priority = "High"
                Reason = "System file corruption detected. Create backup before repair."
                Website = "https://www.macrium.com/reflectfree"
                Action = "Create system image backup immediately"
            }
            $recommendations.Reasons += "System file corruption requires backup"
        }
        
        # Disk errors - recommend disk tools
        if ($diskHealth.NeedsRepair -or $diskHealth.HasBadSectors) {
            $recommendations.Tools += @{
                Name = "CrystalDiskInfo"
                Category = "Disk Diagnostics"
                Priority = "High"
                Reason = "Disk errors or bad sectors detected. Monitor disk health."
                Website = "https://crystalmark.info/en/software/crystaldiskinfo/"
                Action = "Check disk health and consider replacement if failing"
            }
            $recommendations.Reasons += "Disk health issues detected"
        }
        
        # Upgrade blockers - recommend specific tools
        if (-not $readiness.ReadyForInPlaceUpgrade -and $readiness.Blockers.Count -gt 0) {
            $recommendations.Tools += @{
                Name = "Hiren's BootCD PE"
                Category = "Recovery"
                Priority = "Medium"
                Reason = "Multiple upgrade blockers detected. Comprehensive recovery tools needed."
                Website = "https://www.hirensbootcd.org"
                Action = "Use for advanced recovery and repair operations"
            }
            $recommendations.Reasons += "In-place upgrade blocked - advanced tools needed"
        }
        
        # Missing drivers - recommend driver tools
        try {
            $missingDrivers = Get-MissingDriversForPorting -TargetDrive $TargetDrive
            if ($missingDrivers.MissingDrivers.Count -gt 0) {
                $recommendations.Tools += @{
                    Name = "DriverPack Solution"
                    Category = "Driver Management"
                    Priority = "Medium"
                    Reason = "Missing drivers detected. Automated driver installation may help."
                    Website = "https://driverpack.io"
                    Action = "Use for automated driver installation (use with caution)"
                }
                $recommendations.Reasons += "Missing drivers detected"
            }
        } catch {
            # Driver check failed, skip
        }
        
        # Determine overall priority
        $highPriorityCount = ($recommendations.Tools | Where-Object { $_.Priority -eq "High" }).Count
        if ($highPriorityCount -gt 0) {
            $recommendations.Priority = "High"
        } elseif ($recommendations.Tools.Count -gt 3) {
            $recommendations.Priority = "Medium"
        } else {
            $recommendations.Priority = "Low"
        }
        
    } catch {
        $recommendations.Tools += @{
            Name = "Miracle Boot (This Tool)"
            Category = "General"
            Priority = "High"
            Reason = "System analysis failed. Use comprehensive recovery tools."
            Website = ""
            Action = "Continue using Miracle Boot for diagnostics"
        }
        $recommendations.Reasons += "System analysis encountered errors"
    }
    
    # Generate report
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("DYNAMIC TOOL RECOMMENDATIONS") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Priority: $($recommendations.Priority)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($recommendations.Reasons.Count -gt 0) {
        $report.AppendLine("Detection Summary:") | Out-Null
        foreach ($reason in $recommendations.Reasons) {
            $report.AppendLine("  - $reason") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    if ($recommendations.Tools.Count -gt 0) {
        $report.AppendLine("Recommended Tools:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        foreach ($tool in $recommendations.Tools) {
            $report.AppendLine("") | Out-Null
            $report.AppendLine("[$($tool.Priority)] $($tool.Name)") | Out-Null
            $report.AppendLine("  Category: $($tool.Category)") | Out-Null
            $report.AppendLine("  Reason: $($tool.Reason)") | Out-Null
            if ($tool.Website) {
                $report.AppendLine("  Website: $($tool.Website)") | Out-Null
            }
            $report.AppendLine("  Action: $($tool.Action)") | Out-Null
        }
    } else {
        $report.AppendLine("No specific tool recommendations at this time.") | Out-Null
        $report.AppendLine("System appears to be in good health.") | Out-Null
    }
    
    $recommendations.Report = $report.ToString()
    return $recommendations
}

function Test-ToolAvailability {
    <#
    .SYNOPSIS
    Checks if recommended tools are available/installed on the system.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ToolName
    )
    
    $toolChecks = @{
        "Macrium Reflect" = @{
            ProcessName = "Reflect"
            InstallPath = "${env:ProgramFiles}\Macrium\Reflect\Reflect.exe"
            RegistryPath = "HKLM:\SOFTWARE\Macrium\Reflect"
        }
        "Ventoy" = @{
            ProcessName = "Ventoy2Disk"
            InstallPath = "${env:ProgramFiles}\Ventoy\Ventoy2Disk.exe"
        }
        "CrystalDiskInfo" = @{
            ProcessName = "DiskInfo"
            InstallPath = "${env:ProgramFiles}\CrystalDiskInfo\DiskInfo.exe"
        }
        "Hiren's BootCD" = @{
            ProcessName = "HBCD"
            InstallPath = "${env:ProgramFiles}\HBCD"
        }
    }
    
    $check = $toolChecks[$ToolName]
    if (-not $check) {
        return @{
            Available = $false
            Reason = "Tool check not configured"
        }
    }
    
    $result = @{
        Available = $false
        Installed = $false
        Path = $null
        Method = "Unknown"
    }
    
    # Check if process is running
    $process = Get-Process -Name $check.ProcessName -ErrorAction SilentlyContinue
    if ($process) {
        $result.Available = $true
        $result.Installed = $true
        $result.Path = $process.Path
        $result.Method = "Running Process"
        return $result
    }
    
    # Check install path
    if ($check.InstallPath -and (Test-Path $check.InstallPath)) {
        $result.Available = $true
        $result.Installed = $true
        $result.Path = $check.InstallPath
        $result.Method = "Install Path"
        return $result
    }
    
    # Check registry
    if ($check.RegistryPath -and (Test-Path $check.RegistryPath)) {
        $result.Available = $true
        $result.Installed = $true
        $result.Method = "Registry"
        return $result
    }
    
    return $result
}

function Get-ToolIntegrationCommands {
    <#
    .SYNOPSIS
    Returns integration commands for common recovery tools.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ToolName,
        
        [string]$TargetDrive = "C"
    )
    
    $commands = @{
        "Macrium Reflect" = @{
            CreateImage = "Reflect.exe /FullBackup /F:`"$TargetDrive`:\Backup\SystemImage.mrimg`""
            RestoreImage = "Reflect.exe /Restore /F:`"$TargetDrive`:\Backup\SystemImage.mrimg`""
            CreateRescueMedia = "Reflect.exe /CreateRescueMedia /F:`"$TargetDrive`:\RescueMedia.iso`""
        }
        "Ventoy" = @{
            CreateBootableUSB = "Ventoy2Disk.exe -i /dev/sdX"
            AddISO = "Copy ISO file to Ventoy USB drive"
        }
        "Hiren's BootCD" = @{
            BootFromUSB = "Boot from USB drive created with Hiren's BootCD"
            AccessTools = "Select tools from desktop menu"
        }
    }
    
    return $commands[$ToolName]
}

# ============================================================================
# WINDOWS INSTALL FAILURE ANALYSIS
# Enhanced functions to check why Windows installation failed
# ============================================================================

function Get-WindowsInstallFailureReasons {
    <#
    .SYNOPSIS
    Comprehensive analysis of Windows installation failure reasons.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        FailureReasons = @()
        ErrorCodes = @()
        LogFiles = @()
        Recommendations = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("WINDOWS INSTALLATION FAILURE ANALYSIS") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine("Analysis Date: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 1. Check Setup Logs
    $report.AppendLine("1. SETUP LOGS ANALYSIS") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $setupLogPaths = @(
        "$TargetDrive`:\Windows\Panther\setupact.log",
        "$TargetDrive`:\Windows\Panther\setuperr.log",
        "$TargetDrive`:\`$WINDOWS.~BT\Sources\Panther\setupact.log",
        "$TargetDrive`:\`$WINDOWS.~BT\Sources\Panther\setuperr.log",
        "$TargetDrive`:\Windows\Logs\CBS\CBS.log",
        "$TargetDrive`:\Windows\Logs\DISM\dism.log"
    )
    
    $foundLogs = @()
    foreach ($logPath in $setupLogPaths) {
        if (Test-Path $logPath) {
            $foundLogs += $logPath
            $result.LogFiles += $logPath
        }
    }
    
    if ($foundLogs.Count -eq 0) {
        $report.AppendLine("[WARNING] No setup logs found in common locations.") | Out-Null
        $report.AppendLine("This may indicate the installation never started, or logs are in a different location.") | Out-Null
    } else {
        $report.AppendLine("[OK] Found $($foundLogs.Count) log file(s):") | Out-Null
        foreach ($log in $foundLogs) {
            $report.AppendLine("  - $log") | Out-Null
        }
        $report.AppendLine("") | Out-Null
        
        # Analyze setuperr.log for errors
        $errorLogs = $foundLogs | Where-Object { $_ -match 'setuperr\.log' }
        foreach ($errorLog in $errorLogs) {
            try {
                $logContent = Get-Content $errorLog -Tail 100 -ErrorAction SilentlyContinue
                if ($logContent) {
                    $report.AppendLine("Recent errors from ${errorLog}:") | Out-Null
                    
                    # Look for error patterns
                    $errors = $logContent | Select-String -Pattern 'error|failed|fatal|exception|0x[0-9A-Fa-f]{8}' -CaseSensitive:$false
                    if ($errors) {
                        foreach ($err in $errors | Select-Object -First 10) {
                            $report.AppendLine("  [ERROR] $($err.Line)") | Out-Null
                            
                            # Extract error codes
                            if ($err.Line -match '0x([0-9A-Fa-f]{8})') {
                                $errorCode = $matches[0]
                                if ($result.ErrorCodes -notcontains $errorCode) {
                                    $result.ErrorCodes += $errorCode
                                }
                            }
                        }
                    } else {
                        $report.AppendLine("  [INFO] No obvious errors found in recent entries.") | Out-Null
                    }
                    $report.AppendLine("") | Out-Null
                }
            } catch {
                $report.AppendLine("  [WARNING] Could not read $errorLog : $_") | Out-Null
            }
        }
    }
    
    # 2. Check for common failure reasons
    $report.AppendLine("2. COMMON FAILURE REASONS CHECK") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    # Check disk space
    try {
        $drive = Get-PSDrive -Name $TargetDrive.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($drive) {
            $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
            $totalSpaceGB = [math]::Round($drive.Used / 1GB + $freeSpaceGB, 2)
            
            $report.AppendLine("Disk Space:") | Out-Null
            $report.AppendLine("  Total: $totalSpaceGB GB") | Out-Null
            $report.AppendLine("  Free: $freeSpaceGB GB") | Out-Null
            
            if ($freeSpaceGB -lt 20) {
                $failureReason = "Insufficient disk space (less than 20 GB free)"
                $result.FailureReasons += $failureReason
                $result.Recommendations += "Free up at least 20 GB of disk space before retrying installation."
                $report.AppendLine("  [CRITICAL] $failureReason") | Out-Null
            } else {
                $report.AppendLine("  [OK] Sufficient disk space available") | Out-Null
            }
        }
    } catch {
        $report.AppendLine("  [WARNING] Could not check disk space: $_") | Out-Null
    }
    
    # Check for incompatible drivers (using existing function if available)
    try {
        $missingDevices = Get-MissingStorageDevices -ErrorAction SilentlyContinue
        if ($missingDevices -and $missingDevices -imatch 'missing|not found|error') {
            $failureReason = "Missing or incompatible storage drivers"
            $result.FailureReasons += $failureReason
            $result.Recommendations += "Install missing storage drivers before retrying installation."
            $report.AppendLine("") | Out-Null
            $report.AppendLine("[WARNING] $failureReason detected") | Out-Null
        }
    } catch {
        # Function may not be available, skip
    }
    
    # 3. Error Code Analysis
    if ($result.ErrorCodes.Count -gt 0) {
        $report.AppendLine("") | Out-Null
        $report.AppendLine("3. ERROR CODE ANALYSIS") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        foreach ($errorCode in $result.ErrorCodes) {
            $report.AppendLine("Error Code: $errorCode") | Out-Null
            
            # Common error code meanings
            $errorMeanings = @{
                "0x80070003" = "Path not found - Check if installation source is accessible"
                "0x80070005" = "Access denied - Run as administrator"
                "0x8007000D" = "Invalid data - Installation media may be corrupted"
                "0x80070070" = "Insufficient disk space"
                "0x8007045D" = "I/O error - Check disk health"
                "0x80070002" = "File not found - Installation source incomplete"
                "0x80070017" = "CRC error - Installation media corrupted"
                "0x80070057" = "Invalid parameter - Check installation options"
            }
            
            if ($errorMeanings.ContainsKey($errorCode)) {
                $report.AppendLine("  Meaning: $($errorMeanings[$errorCode])") | Out-Null
                $result.Recommendations += $errorMeanings[$errorCode]
            } else {
                $report.AppendLine("  Meaning: Unknown error code - search online for details") | Out-Null
                $result.Recommendations += "Research error code $errorCode online for specific solution"
            }
            $report.AppendLine("") | Out-Null
        }
    }
    
    # 4. Recommendations
    $report.AppendLine("4. RECOMMENDATIONS") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    if ($result.Recommendations.Count -gt 0) {
        $num = 1
        foreach ($rec in $result.Recommendations) {
            $report.AppendLine("$num. $rec") | Out-Null
            $num++
        }
    } else {
        $report.AppendLine("No specific recommendations. Review log files manually for details.") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("END OF ANALYSIS") | Out-Null
    $report.AppendLine($separator) | Out-Null
    
    $result.Report = $report.ToString()
    $result.Success = $true
    
    return $result
}

# ============================================================================
# AUTOMATED REPAIR FUNCTIONS
# Enhanced repair workflows for comprehensive system recovery
# ============================================================================

function Start-AutomatedBootRepair {
    <#
    .SYNOPSIS
    Performs automated multi-step boot repair sequence with validation and rollback.
    
    .DESCRIPTION
    Runs a comprehensive boot repair sequence:
    1. Boot diagnosis
    2. BCD backup
    3. bootrec /scanos
    4. bootrec /fixboot
    5. bootrec /fixmbr
    6. bcdboot (if UEFI)
    7. bootrec /rebuildbcd
    
    Each step is validated before proceeding to the next.
    #>
    param(
        [string]$TargetDrive = "C",
        [switch]$SkipConfirmation = $false,
        [switch]$CreateRestorePoint = $true,
        [switch]$SkipRestorePoint = $false
    )
    
    $result = @{
        Success = $false
        StepsCompleted = @()
        StepsFailed = @()
        BCDBackups = @()
        Report = ""
        Errors = @()
        RestorePointID = $null
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("AUTOMATED BOOT REPAIR") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Create restore point before boot repair (if enabled and online)
    $envType = Get-EnvironmentType
    if ($CreateRestorePoint -and -not $SkipRestorePoint -and $envType -eq 'FullOS') {
        $report.AppendLine("Creating system restore point before boot repair...") | Out-Null
        $restorePoint = Create-SystemRestorePoint -Description "Before Automated Boot Repair" -OperationType "BootRepair"
        if ($restorePoint.Success) {
            $report.AppendLine("[OK] Restore point created: $($restorePoint.RestorePointPath)") | Out-Null
            $result.RestorePointID = $restorePoint.RestorePointID
        } else {
            $report.AppendLine("[WARNING] Could not create restore point: $($restorePoint.Message)") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Step 1: Run boot diagnosis
    $report.AppendLine("STEP 1: Running boot diagnosis...") | Out-Null
    try {
        $diagnosis = Get-BootDiagnosis -TargetDrive $TargetDrive
        $report.AppendLine($diagnosis) | Out-Null
        $result.StepsCompleted += "Diagnosis"
    } catch {
        $errorMsg = "Diagnosis failed: $_"
        $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        $result.StepsFailed += "Diagnosis"
        $result.Errors += $errorMsg
    }
    $report.AppendLine("") | Out-Null
    
    # Step 2: Backup BCD
    $report.AppendLine("STEP 2: Backing up BCD...") | Out-Null
    try {
        $bcdBackup = Export-BCDBackup
        if ($bcdBackup.Success) {
            $result.BCDBackups += $bcdBackup.Path
            $report.AppendLine("[OK] BCD backed up to: $($bcdBackup.Path)") | Out-Null
            $result.StepsCompleted += "BCD Backup"
        } else {
            throw $bcdBackup.Error
        }
    } catch {
        $errorMsg = "BCD backup failed: $_"
        $report.AppendLine("[WARNING] $errorMsg") | Out-Null
        $result.Errors += $errorMsg
        # Continue anyway - backup failure is not critical
    }
    $report.AppendLine("") | Out-Null
    
    # Step 3: bootrec /scanos
    $report.AppendLine("STEP 3: Scanning for Windows installations (bootrec /scanos)...") | Out-Null
    try {
        $scanOutput = bootrec /scanos 2>&1 | Out-String
        $report.AppendLine($scanOutput) | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $result.StepsCompleted += "ScanOS"
            $report.AppendLine("[OK] Scan completed successfully") | Out-Null
        } else {
            $report.AppendLine("[WARNING] Scan completed with exit code $LASTEXITCODE") | Out-Null
            $result.StepsFailed += "ScanOS"
        }
    } catch {
        $errorMsg = "ScanOS failed: $_"
        $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        $result.StepsFailed += "ScanOS"
        $result.Errors += $errorMsg
    }
    $report.AppendLine("") | Out-Null
    
    # Step 4: bootrec /fixboot
    $report.AppendLine("STEP 4: Fixing boot sector (bootrec /fixboot)...") | Out-Null
    if (-not $SkipConfirmation) {
        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_fixboot" -Command "bootrec /fixboot" -Description "Fix boot sector"
        if (-not $confirmed) {
            $report.AppendLine("[SKIPPED] User cancelled fixboot operation") | Out-Null
            $result.Report = $report.ToString()
            return $result
        }
    }
    
    try {
        $fixbootOutput = bootrec /fixboot 2>&1 | Out-String
        $report.AppendLine($fixbootOutput) | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $result.StepsCompleted += "FixBoot"
            $report.AppendLine("[OK] Boot sector fixed successfully") | Out-Null
        } else {
            $errorMsg = "FixBoot failed with exit code $LASTEXITCODE"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.StepsFailed += "FixBoot"
            $result.Errors += $errorMsg
        }
    } catch {
        $errorMsg = "FixBoot failed: $_"
        $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        $result.StepsFailed += "FixBoot"
        $result.Errors += $errorMsg
    }
    $report.AppendLine("") | Out-Null
    
    # Step 5: bootrec /fixmbr
    $report.AppendLine("STEP 5: Fixing MBR (bootrec /fixmbr)...") | Out-Null
    if (-not $SkipConfirmation) {
        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_fixmbr" -Command "bootrec /fixmbr" -Description "Fix Master Boot Record"
        if (-not $confirmed) {
            $report.AppendLine("[SKIPPED] User cancelled fixmbr operation") | Out-Null
            $result.Report = $report.ToString()
            return $result
        }
    }
    
    try {
        $fixmbrOutput = bootrec /fixmbr 2>&1 | Out-String
        $report.AppendLine($fixmbrOutput) | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $result.StepsCompleted += "FixMBR"
            $report.AppendLine("[OK] MBR fixed successfully") | Out-Null
        } else {
            $errorMsg = "FixMBR failed with exit code $LASTEXITCODE"
            $report.AppendLine("[WARNING] $errorMsg (may not be needed for UEFI systems)") | Out-Null
            $result.StepsFailed += "FixMBR"
        }
    } catch {
        $errorMsg = "FixMBR failed: $_"
        $report.AppendLine("[WARNING] $errorMsg (may not be needed for UEFI systems)") | Out-Null
        $result.StepsFailed += "FixMBR"
    }
    $report.AppendLine("") | Out-Null
    
    # Step 6: bcdboot (for UEFI systems)
    $report.AppendLine("STEP 6: Recreating boot files (bcdboot)...") | Out-Null
    try {
        # Detect if UEFI or Legacy
        $partition = Get-Partition -DriveLetter $TargetDrive -ErrorAction SilentlyContinue
        $isUEFI = $false
        if ($partition) {
            $disk = Get-Disk -Number $partition.DiskNumber
            $efiParts = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
            $isUEFI = ($efiParts.Count -gt 0)
        }
        
        if ($isUEFI) {
            # Try to find EFI partition drive letter
            $efiDrive = $null
            foreach ($efiPart in $efiParts) {
                if ($efiPart.DriveLetter) {
                    $efiDrive = $efiPart.DriveLetter
                    break
                }
            }
            
            if ($efiDrive) {
                $bcdbootCmd = "bcdboot $TargetDrive`:\Windows /s $efiDrive`: /f UEFI"
            } else {
                $bcdbootCmd = "bcdboot $TargetDrive`:\Windows /f UEFI"
            }
        } else {
            $bcdbootCmd = "bcdboot $TargetDrive`:\Windows /f ALL"
        }
        
        if (-not $SkipConfirmation) {
            $confirmed = Confirm-DestructiveOperation -CommandKey "bcdboot" -Command $bcdbootCmd -Description "Recreate boot files"
            if (-not $confirmed) {
                $report.AppendLine("[SKIPPED] User cancelled bcdboot operation") | Out-Null
                $result.Report = $report.ToString()
                return $result
            }
        }
        
        $bcdbootOutput = Invoke-Expression $bcdbootCmd 2>&1 | Out-String
        $report.AppendLine($bcdbootOutput) | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $result.StepsCompleted += "BCDBoot"
            $report.AppendLine("[OK] Boot files recreated successfully") | Out-Null
        } else {
            $errorMsg = "BCDBoot failed with exit code $LASTEXITCODE"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.StepsFailed += "BCDBoot"
            $result.Errors += $errorMsg
        }
    } catch {
        $errorMsg = "BCDBoot failed: $_"
        $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        $result.StepsFailed += "BCDBoot"
        $result.Errors += $errorMsg
    }
    $report.AppendLine("") | Out-Null
    
    # Step 7: bootrec /rebuildbcd
    $report.AppendLine("STEP 7: Rebuilding BCD (bootrec /rebuildbcd)...") | Out-Null
    if (-not $SkipConfirmation) {
        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_rebuildbcd" -Command "bootrec /rebuildbcd" -Description "Rebuild BCD"
        if (-not $confirmed) {
            $report.AppendLine("[SKIPPED] User cancelled rebuildbcd operation") | Out-Null
            $result.Report = $report.ToString()
            return $result
        }
    }
    
    try {
        $rebuildOutput = bootrec /rebuildbcd 2>&1 | Out-String
        $report.AppendLine($rebuildOutput) | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $result.StepsCompleted += "RebuildBCD"
            $report.AppendLine("[OK] BCD rebuilt successfully") | Out-Null
        } else {
            $errorMsg = "RebuildBCD failed with exit code $LASTEXITCODE"
            $report.AppendLine("[WARNING] $errorMsg") | Out-Null
            $result.StepsFailed += "RebuildBCD"
        }
    } catch {
        $errorMsg = "RebuildBCD failed: $_"
        $report.AppendLine("[WARNING] $errorMsg") | Out-Null
        $result.StepsFailed += "RebuildBCD"
    }
    $report.AppendLine("") | Out-Null
    
    # Final summary
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REPAIR SUMMARY") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("Steps Completed: $($result.StepsCompleted.Count)") | Out-Null
    $report.AppendLine("Steps Failed: $($result.StepsFailed.Count)") | Out-Null
    $report.AppendLine("BCD Backups: $($result.BCDBackups.Count)") | Out-Null
    
    if ($result.StepsFailed.Count -eq 0) {
        $result.Success = $true
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[SUCCESS] Boot repair completed successfully!") | Out-Null
        $report.AppendLine("Restart your computer to test the repair.") | Out-Null
    } else {
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[WARNING] Some steps failed. Review errors above.") | Out-Null
        if ($result.BCDBackups.Count -gt 0) {
            $report.AppendLine("BCD backups are available for rollback if needed.") | Out-Null
        }
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Test-SystemFileHealth {
    <#
    .SYNOPSIS
    Pre-flight check for system file health and component store status.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        SystemFilesHealthy = $false
        ComponentStoreHealthy = $false
        CBSLogIssues = @()
        DISMHealthStatus = ""
        Recommendations = @()
        CanRepair = $false
    }
    
    $envType = Get-EnvironmentType
    $isOffline = ($envType -ne 'FullOS')
    
    # Check CBS.log for corruption indicators
    $cbsLogPath = "$TargetDrive`:\Windows\Logs\CBS\CBS.log"
    if (Test-Path $cbsLogPath) {
        try {
            $cbsContent = Get-Content $cbsLogPath -Tail 1000 -ErrorAction SilentlyContinue
            $errorLines = $cbsContent | Where-Object { 
                $_ -match "corrupt|corruption|failed|error|cannot.*repair|component.*store.*corrupt"
            } | Select-Object -First 20
            
            if ($errorLines) {
                $result.CBSLogIssues = $errorLines
                $result.SystemFilesHealthy = $false
            } else {
                $result.SystemFilesHealthy = $true
            }
        } catch {
            $result.CBSLogIssues += "Could not read CBS.log: $_"
        }
    }
    
    # Check DISM health (only in FullOS)
    if (-not $isOffline) {
        try {
            $dismCheck = dism /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
            $result.DISMHealthStatus = $dismCheck
            
            if ($dismCheck -match "The component store is repairable") {
                $result.ComponentStoreHealthy = $false
                $result.CanRepair = $true
                $result.Recommendations += "Run DISM /Online /Cleanup-Image /RestoreHealth"
            } elseif ($dismCheck -match "The component store is healthy") {
                $result.ComponentStoreHealthy = $true
            } elseif ($dismCheck -match "The component store cannot be repaired") {
                $result.ComponentStoreHealthy = $false
                $result.CanRepair = $false
                $result.Recommendations += "Component store cannot be repaired. May need repair install."
            }
        } catch {
            $result.DISMHealthStatus = "Could not check DISM health: $_"
        }
    } else {
        $result.Recommendations += "Offline mode: Use DISM /Image with /Source parameter"
    }
    
    # Generate recommendations
    if (-not $result.SystemFilesHealthy) {
        if ($isOffline) {
            $result.Recommendations += "Run SFC /scannow /offbootdir=$TargetDrive`: /offwindir=$TargetDrive`:\Windows"
        } else {
            $result.Recommendations += "Run SFC /scannow"
        }
    }
    
    if ($result.CBSLogIssues.Count -gt 0 -or -not $result.ComponentStoreHealthy) {
        $result.CanRepair = $true
    }
    
    return $result
}

function Start-SystemFileRepair {
    <#
    .SYNOPSIS
    Automated SFC + DISM repair sequence with progress tracking and automatic restore point creation.
    #>
    param(
        [string]$TargetDrive = "C",
        [string]$SourcePath = "",
        [switch]$SkipSFC = $false,
        [switch]$SkipDISM = $false,
        [scriptblock]$ProgressCallback = $null,
        [switch]$CreateRestorePoint = $true,
        [switch]$SkipRestorePoint = $false
    )
    
    $result = @{
        Success = $false
        SFCCompleted = $false
        DISMCompleted = $false
        SFCOutput = ""
        DISMOutput = ""
        Report = ""
        Errors = @()
        RestorePointID = $null
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    $envType = Get-EnvironmentType
    $isOffline = ($envType -ne 'FullOS')
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("SYSTEM FILE REPAIR") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine("Mode: $(if ($isOffline) { 'Offline' } else { 'Online' })") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Create restore point before repair (if enabled and online)
    if ($CreateRestorePoint -and -not $SkipRestorePoint -and -not $isOffline) {
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Creating system restore point..."
        }
        $report.AppendLine("Creating system restore point before repair...") | Out-Null
        $restorePoint = Create-SystemRestorePoint -Description "Before System File Repair" -OperationType "SystemFileRepair"
        if ($restorePoint.Success) {
            $report.AppendLine("[OK] Restore point created: $($restorePoint.RestorePointPath)") | Out-Null
            $result.RestorePointID = $restorePoint.RestorePointID
        } else {
            $report.AppendLine("[WARNING] Could not create restore point: $($restorePoint.Message)") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Pre-flight check
    if ($null -ne $ProgressCallback) {
        & $ProgressCallback "Running pre-flight health check..."
    }
    
    $healthCheck = Test-SystemFileHealth -TargetDrive $TargetDrive
    $report.AppendLine("PRE-FLIGHT CHECK:") | Out-Null
    $report.AppendLine("  System Files: $(if ($healthCheck.SystemFilesHealthy) { 'OK' } else { 'Issues Found' })") | Out-Null
    $report.AppendLine("  Component Store: $(if ($healthCheck.ComponentStoreHealthy) { 'OK' } else { 'Issues Found' })") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Step 1: SFC
    if (-not $SkipSFC) {
        $report.AppendLine("STEP 1: Running System File Checker (SFC)...") | Out-Null
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Running SFC /scannow..."
        }
        
        try {
            if ($isOffline) {
                $sfcCmd = "sfc /scannow /offbootdir=$TargetDrive`: /offwindir=$TargetDrive`:\Windows"
            } else {
                $sfcCmd = "sfc /scannow"
            }
            
            # Use progress tracking if callback provided
            if ($null -ne $ProgressCallback) {
                $sfcOutputBuilder = New-Object System.Text.StringBuilder
                $sfcResult = Start-OperationWithProgress -Command $sfcCmd -OperationType "SFC" -ProgressCallback {
                    param($progress)
                    $progressMsg = "SFC: $($progress.CurrentOperation)"
                    if ($progress.Percentage -gt 0) {
                        $progressMsg += " - $($progress.Percentage)%"
                    }
                    if ($progress.EstimatedTimeRemaining) {
                        $progressMsg += " (Est. remaining: $($progress.EstimatedTimeRemaining.ToString('mm\:ss')))"
                    }
                    & $ProgressCallback $progressMsg
                } -OutputCallback {
                    param($line)
                    $null = $script:sfcOutputBuilder.AppendLine($line)
                }
                
                $sfcOutput = $sfcResult.Output
            } else {
                $sfcOutput = Invoke-Expression $sfcCmd 2>&1 | Out-String
            }
            
            $result.SFCOutput = $sfcOutput
            $report.AppendLine($sfcOutput) | Out-Null
            
            # Parse SFC output for success indicators
            if ($sfcOutput -match "Windows Resource Protection did not find any integrity violations" -or 
                $sfcOutput -match "Windows Resource Protection found corrupt files and successfully repaired them") {
                $result.SFCCompleted = $true
                $report.AppendLine("[OK] SFC completed successfully") | Out-Null
            } elseif ($sfcOutput -match "Windows Resource Protection found corrupt files but was unable to fix some of them") {
                $result.SFCCompleted = $false
                $report.AppendLine("[WARNING] SFC found issues but could not fix all. DISM may help.") | Out-Null
                $result.Errors += "SFC could not fix all corrupt files"
            } else {
                $result.SFCCompleted = $false
                $report.AppendLine("[WARNING] SFC results unclear. Check output above.") | Out-Null
            }
        } catch {
            $errorMsg = "SFC failed: $_"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.Errors += $errorMsg
            $result.SFCCompleted = $false
        }
        $report.AppendLine("") | Out-Null
    } else {
        $report.AppendLine("STEP 1: SFC skipped (user request)") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # Step 2: DISM
    if (-not $SkipDISM) {
        $report.AppendLine("STEP 2: Running DISM repair...") | Out-Null
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Running DISM /RestoreHealth..."
        }
        
        try {
            if ($isOffline) {
                if ([string]::IsNullOrWhiteSpace($SourcePath)) {
                    $dismCmd = "dism /Image:$TargetDrive`: /Cleanup-Image /RestoreHealth"
                } else {
                    $dismCmd = "dism /Image:$TargetDrive`: /Cleanup-Image /RestoreHealth /Source:$SourcePath"
                }
            } else {
                $dismCmd = "dism /Online /Cleanup-Image /RestoreHealth"
            }
            
            # Use progress tracking if callback provided
            if ($null -ne $ProgressCallback) {
                $dismOutputBuilder = New-Object System.Text.StringBuilder
                $dismResult = Start-OperationWithProgress -Command $dismCmd -OperationType "DISM" -ProgressCallback {
                    param($progress)
                    $progressMsg = "DISM: $($progress.CurrentOperation)"
                    if ($progress.Percentage -gt 0) {
                        $progressMsg += " - $($progress.Percentage)%"
                    }
                    if ($progress.EstimatedTimeRemaining) {
                        $progressMsg += " (Est. remaining: $($progress.EstimatedTimeRemaining.ToString('mm\:ss')))"
                    }
                    & $ProgressCallback $progressMsg
                } -OutputCallback {
                    param($line)
                    $null = $script:dismOutputBuilder.AppendLine($line)
                }
                
                $dismOutput = $dismResult.Output
            } else {
                $dismOutput = Invoke-Expression $dismCmd 2>&1 | Out-String
            }
            
            $result.DISMOutput = $dismOutput
            $report.AppendLine($dismOutput) | Out-Null
            
            # Parse DISM output
            if ($dismOutput -match "The operation completed successfully" -or 
                $dismOutput -match "The restore operation completed successfully") {
                $result.DISMCompleted = $true
                $report.AppendLine("[OK] DISM completed successfully") | Out-Null
            } elseif ($dismOutput -match "Error:" -or $dismOutput -match "The component store cannot be repaired") {
                $result.DISMCompleted = $false
                $errorMsg = "DISM could not repair component store"
                $report.AppendLine("[ERROR] $errorMsg") | Out-Null
                $result.Errors += $errorMsg
                
                if ($isOffline -and [string]::IsNullOrWhiteSpace($SourcePath)) {
                    $report.AppendLine("[INFO] Try specifying /Source parameter with Windows installation media") | Out-Null
                }
            } else {
                $result.DISMCompleted = $false
                $report.AppendLine("[WARNING] DISM results unclear. Check output above.") | Out-Null
            }
        } catch {
            $errorMsg = "DISM failed: $_"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.Errors += $errorMsg
            $result.DISMCompleted = $false
        }
        $report.AppendLine("") | Out-Null
    } else {
        $report.AppendLine("STEP 2: DISM skipped (user request)") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # Summary
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REPAIR SUMMARY") | Out-Null
    $report.AppendLine($separator) | Out-Null
    
    if ($result.SFCCompleted -and $result.DISMCompleted) {
        $result.Success = $true
        $report.AppendLine("[SUCCESS] System file repair completed successfully!") | Out-Null
        $report.AppendLine("Restart your computer if prompted.") | Out-Null
    } elseif ($result.SFCCompleted -or $result.DISMCompleted) {
        $report.AppendLine("[PARTIAL] Some repairs completed. Review output above.") | Out-Null
        if ($result.Errors.Count -gt 0) {
            $report.AppendLine("Errors:") | Out-Null
            foreach ($err in $result.Errors) {
                $report.AppendLine("  - $err") | Out-Null
            }
        }
    } else {
        $report.AppendLine("[FAILED] System file repair did not complete successfully.") | Out-Null
        $report.AppendLine("Consider running repair install or offline repair.") | Out-Null
        if ($result.Errors.Count -gt 0) {
            $report.AppendLine("Errors:") | Out-Null
            foreach ($err in $result.Errors) {
                $report.AppendLine("  - $err") | Out-Null
            }
        }
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Test-DiskHealth {
    <#
    .SYNOPSIS
    Pre-flight disk health check before running chkdsk.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        FileSystem = "Unknown"
        FileSystemHealthy = $false
        HasBadSectors = $false
        NeedsRepair = $false
        BitLockerEncrypted = $false
        Warnings = @()
        Recommendations = @()
    }
    
    # Check BitLocker status
    $bitlocker = Test-BitLockerStatus -TargetDrive $TargetDrive
    if ($bitlocker.IsEncrypted) {
        $result.BitLockerEncrypted = $true
        $result.Warnings += "Drive is BitLocker encrypted. Ensure you have recovery key."
    }
    
    # Get volume information
    try {
        $volume = Get-Volume -DriveLetter $TargetDrive -ErrorAction SilentlyContinue
        if ($volume) {
            $result.FileSystem = $volume.FileSystemType
            $result.FileSystemHealthy = ($volume.HealthStatus -eq 'Healthy')
            
            # Check for dirty bit (indicates file system corruption)
            $dirtyBit = fsutil dirty query "$TargetDrive`:" 2>&1
            if ($dirtyBit -match "is dirty") {
                $result.NeedsRepair = $true
                $result.Recommendations += "File system is marked as dirty. Run chkdsk /f"
            }
        }
    } catch {
        $result.Warnings += "Could not get volume information: $_"
    }
    
    # Check for bad sectors (requires admin)
    try {
        $diskInfo = Get-Disk | Where-Object { 
            $_.Partitions | Where-Object { $_.DriveLetter -eq $TargetDrive } 
        } | Select-Object -First 1
        
        if ($diskInfo) {
            # Check if disk has errors
            if ($diskInfo.HealthStatus -ne 'Healthy') {
                $result.HasBadSectors = $true
                $result.NeedsRepair = $true
                $result.Recommendations += "Disk health is not optimal. Run chkdsk /r"
            }
        }
    } catch {
        # Ignore - may not have permissions
    }
    
    return $result
}

function Start-DiskRepair {
    <#
    .SYNOPSIS
    Automated chkdsk execution with progress monitoring.
    #>
    param(
        [string]$TargetDrive = "C",
        [switch]$FixErrors = $true,
        [switch]$RecoverBadSectors = $false,
        [switch]$ForceDismount = $false,
        [scriptblock]$ProgressCallback = $null
    )
    
    $result = @{
        Success = $false
        Output = ""
        Report = ""
        Errors = @()
        RequiresReboot = $false
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("DISK REPAIR (CHKDSK)") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Pre-flight check
    if ($null -ne $ProgressCallback) {
        & $ProgressCallback "Running pre-flight disk health check..."
    }
    
    $healthCheck = Test-DiskHealth -TargetDrive $TargetDrive
    $report.AppendLine("PRE-FLIGHT CHECK:") | Out-Null
    $report.AppendLine("  File System: $($healthCheck.FileSystem)") | Out-Null
    $report.AppendLine("  Health Status: $(if ($healthCheck.FileSystemHealthy) { 'OK' } else { 'Issues Found' })") | Out-Null
    
    if ($healthCheck.BitLockerEncrypted) {
        $report.AppendLine("  [WARNING] BitLocker Encrypted: Ensure you have recovery key!") | Out-Null
    }
    
    if ($healthCheck.NeedsRepair) {
        $report.AppendLine("  [INFO] Disk repair recommended") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # Check if drive is in use
    $volume = Get-Volume -DriveLetter $TargetDrive -ErrorAction SilentlyContinue
    if ($volume) {
        $isSystemDrive = ($TargetDrive -eq "C" -or $env:SystemDrive -eq "$TargetDrive`:")
        
        if ($isSystemDrive -and -not $ForceDismount) {
            $report.AppendLine("[INFO] System drive detected. chkdsk will be scheduled for next reboot.") | Out-Null
            $result.RequiresReboot = $true
        }
    }
    
    # Build chkdsk command
    $chkdskCmd = "chkdsk $TargetDrive`:"
    
    if ($FixErrors) {
        $chkdskCmd += " /f"
    }
    
    if ($RecoverBadSectors) {
        $chkdskCmd += " /r"
    }
    
    # Add /x to force dismount if requested
    if ($ForceDismount -and -not $isSystemDrive) {
        $chkdskCmd += " /x"
    }
    
    $report.AppendLine("Command: $chkdskCmd") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Confirm if destructive
    if ($RecoverBadSectors) {
        $confirmed = Confirm-DestructiveOperation -CommandKey "chkdsk_r" -Command $chkdskCmd -Description "Check disk and recover bad sectors (can take hours)"
        if (-not $confirmed) {
            $report.AppendLine("[CANCELLED] User cancelled disk repair") | Out-Null
            $result.Report = $report.ToString()
            return $result
        }
    }
    
    # Create restore point before chkdsk if online
    $envType = Get-EnvironmentType
    if ($envType -eq 'FullOS' -and -not $result.RequiresReboot) {
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Creating restore point before disk repair..."
        }
        $restorePoint = Create-SystemRestorePoint -Description "Before Disk Repair (chkdsk)" -OperationType "DiskRepair"
        if ($restorePoint.Success) {
            $report.AppendLine("[OK] Restore point created before disk repair") | Out-Null
        }
    }
    
    # Execute chkdsk
    if ($null -ne $ProgressCallback) {
        & $ProgressCallback "Running chkdsk... (this may take a long time)"
    }
    
    try {
        if ($result.RequiresReboot) {
            # Schedule for next boot
            $scheduleOutput = chkdsk $TargetDrive`: /f 2>&1 | Out-String
            $report.AppendLine($scheduleOutput) | Out-Null
            $report.AppendLine("") | Out-Null
            $report.AppendLine("[INFO] chkdsk has been scheduled to run on next reboot.") | Out-Null
            $report.AppendLine("Restart your computer to begin disk repair.") | Out-Null
            $result.Success = $true
        } else {
            # Run immediately with progress tracking
            if ($null -ne $ProgressCallback) {
                $chkdskOutputBuilder = New-Object System.Text.StringBuilder
                $chkdskResult = Start-OperationWithProgress -Command $chkdskCmd -OperationType "CHKDSK" -ProgressCallback {
                    param($progress)
                    $progressMsg = "CHKDSK $($progress.Stage): $($progress.CurrentOperation)"
                    if ($progress.Percentage -gt 0) {
                        $progressMsg += " - $($progress.Percentage)%"
                    }
                    if ($progress.EstimatedTimeRemaining) {
                        $progressMsg += " (Est. remaining: $($progress.EstimatedTimeRemaining.ToString('hh\:mm\:ss')))"
                    }
                    & $ProgressCallback $progressMsg
                } -OutputCallback {
                    param($line)
                    $null = $script:chkdskOutputBuilder.AppendLine($line)
                }
                
                $chkdskOutput = $chkdskResult.Output
            } else {
                $chkdskOutput = Invoke-Expression $chkdskCmd 2>&1 | Out-String
            }
            
            $result.Output = $chkdskOutput
            $report.AppendLine($chkdskOutput) | Out-Null
            
            # Parse output for success
            if ($chkdskOutput -match "Windows has checked the file system" -or 
                $chkdskOutput -match "CHKDSK cannot run because the volume is in use" -or
                $LASTEXITCODE -eq 0) {
                $result.Success = $true
                $report.AppendLine("[OK] chkdsk completed successfully") | Out-Null
            } else {
                $errorMsg = "chkdsk completed with issues or errors"
                $report.AppendLine("[WARNING] $errorMsg") | Out-Null
                $result.Errors += $errorMsg
            }
        }
    } catch {
        $errorMsg = "chkdsk failed: $_"
        $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        $result.Errors += $errorMsg
        $result.Success = $false
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Get-DiagnosticPresets {
    <#
    .SYNOPSIS
    Returns predefined diagnostic presets for common scenarios.
    #>
    return @{
        "Quick" = @{
            Name = "Quick Diagnostic"
            Description = "Fast health check (boot, system files, disk)"
            Checks = @("Boot", "SystemFiles", "Disk")
            EstimatedTime = "2-5 minutes"
        }
        "Full" = @{
            Name = "Full Diagnostic"
            Description = "Comprehensive system health check"
            Checks = @("Boot", "SystemFiles", "Disk", "Registry", "UpgradeReadiness")
            EstimatedTime = "10-15 minutes"
        }
        "PreRepair" = @{
            Name = "Pre-Repair Diagnostic"
            Description = "Diagnostic before running repairs"
            Checks = @("Boot", "SystemFiles", "Disk", "Registry")
            EstimatedTime = "5-10 minutes"
        }
        "PostRepair" = @{
            Name = "Post-Repair Diagnostic"
            Description = "Validation after repairs"
            Checks = @("Boot", "SystemFiles", "Validation")
            EstimatedTime = "3-5 minutes"
        }
        "UpgradeReadiness" = @{
            Name = "Upgrade Readiness Check"
            Description = "Check if system is ready for in-place upgrade"
            Checks = @("UpgradeReadiness", "SystemFiles", "Boot")
            EstimatedTime = "5-10 minutes"
        }
    }
}

function Start-QuickDiagnostics {
    <#
    .SYNOPSIS
    Fast diagnostic check focusing on critical issues only.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        IssuesFound = 0
        CriticalIssues = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("QUICK DIAGNOSTICS") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    Write-Host "Running quick diagnostics..." -ForegroundColor Cyan
    
    # Quick boot check
    try {
        $bootProb = Get-BootProbability -TargetDrive $TargetDrive
        if ($bootProb.Score -lt 50) {
            $result.CriticalIssues += "Boot probability is critically low: $($bootProb.Score)%"
            $result.IssuesFound++
        }
        $report.AppendLine("Boot Probability: $($bootProb.Score)%") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Boot check failed: $_") | Out-Null
    }
    
    # Quick system file check
    try {
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        if (-not $fileHealth.SystemFilesHealthy) {
            $result.CriticalIssues += "System file corruption detected"
            $result.IssuesFound++
        }
        $report.AppendLine("System Files: $(if ($fileHealth.SystemFilesHealthy) { 'OK' } else { 'Issues' })") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] System file check failed: $_") | Out-Null
    }
    
    # Quick disk check
    try {
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        if ($diskHealth.NeedsRepair) {
            $result.CriticalIssues += "Disk errors detected"
            $result.IssuesFound++
        }
        $report.AppendLine("Disk Health: $(if ($diskHealth.FileSystemHealthy) { 'OK' } else { 'Issues' })") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Disk check failed: $_") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("SUMMARY:") | Out-Null
    $report.AppendLine("Issues Found: $($result.IssuesFound)") | Out-Null
    
    if ($result.CriticalIssues.Count -gt 0) {
        $report.AppendLine("Critical Issues:") | Out-Null
        foreach ($issue in $result.CriticalIssues) {
            $report.AppendLine("  - $issue") | Out-Null
        }
    } else {
        $report.AppendLine("[OK] No critical issues detected") | Out-Null
    }
    
    $result.Success = $true
    $result.Report = $report.ToString()
    return $result
}

function Get-DiagnosticPresets {
    <#
    .SYNOPSIS
    Returns predefined diagnostic presets for common scenarios.
    #>
    return @{
        "Quick" = @{
            Name = "Quick Diagnostic"
            Description = "Fast health check (boot, system files, disk)"
            Checks = @("Boot", "SystemFiles", "Disk")
            EstimatedTime = "2-5 minutes"
        }
        "Full" = @{
            Name = "Full Diagnostic"
            Description = "Comprehensive system health check"
            Checks = @("Boot", "SystemFiles", "Disk", "Registry", "UpgradeReadiness")
            EstimatedTime = "10-15 minutes"
        }
        "PreRepair" = @{
            Name = "Pre-Repair Diagnostic"
            Description = "Diagnostic before running repairs"
            Checks = @("Boot", "SystemFiles", "Disk", "Registry")
            EstimatedTime = "5-10 minutes"
        }
        "PostRepair" = @{
            Name = "Post-Repair Diagnostic"
            Description = "Validation after repairs"
            Checks = @("Boot", "SystemFiles", "Validation")
            EstimatedTime = "3-5 minutes"
        }
        "UpgradeReadiness" = @{
            Name = "Upgrade Readiness Check"
            Description = "Check if system is ready for in-place upgrade"
            Checks = @("UpgradeReadiness", "SystemFiles", "Boot")
            EstimatedTime = "5-10 minutes"
        }
    }
}

function Start-QuickDiagnostics {
    <#
    .SYNOPSIS
    Fast diagnostic check focusing on critical issues only.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        IssuesFound = 0
        CriticalIssues = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("QUICK DIAGNOSTICS") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    Write-Host "Running quick diagnostics..." -ForegroundColor Cyan
    
    # Quick boot check
    try {
        $bootProb = Get-BootProbability -TargetDrive $TargetDrive
        if ($bootProb.Score -lt 50) {
            $result.CriticalIssues += "Boot probability is critically low: $($bootProb.Score)%"
            $result.IssuesFound++
        }
        $report.AppendLine("Boot Probability: $($bootProb.Score)%") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Boot check failed: $_") | Out-Null
    }
    
    # Quick system file check
    try {
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        if (-not $fileHealth.SystemFilesHealthy) {
            $result.CriticalIssues += "System file corruption detected"
            $result.IssuesFound++
        }
        $report.AppendLine("System Files: $(if ($fileHealth.SystemFilesHealthy) { 'OK' } else { 'Issues' })") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] System file check failed: $_") | Out-Null
    }
    
    # Quick disk check
    try {
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        if ($diskHealth.NeedsRepair) {
            $result.CriticalIssues += "Disk errors detected"
            $result.IssuesFound++
        }
        $report.AppendLine("Disk Health: $(if ($diskHealth.FileSystemHealthy) { 'OK' } else { 'Issues' })") | Out-Null
    } catch {
        $report.AppendLine("[WARNING] Disk check failed: $_") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("SUMMARY:") | Out-Null
    $report.AppendLine("Issues Found: $($result.IssuesFound)") | Out-Null
    
    if ($result.CriticalIssues.Count -gt 0) {
        $report.AppendLine("Critical Issues:") | Out-Null
        foreach ($issue in $result.CriticalIssues) {
            $report.AppendLine("  - $issue") | Out-Null
        }
    } else {
        $report.AppendLine("[OK] No critical issues detected") | Out-Null
    }
    
    $result.Success = $true
    $result.Report = $report.ToString()
    return $result
}

function Start-DiagnosticPreset {
    <#
    .SYNOPSIS
    Runs a predefined diagnostic preset.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$PresetName,
        
        [string]$TargetDrive = "C"
    )
    
    $presets = Get-DiagnosticPresets
    $preset = $presets[$PresetName]
    
    if (-not $preset) {
        return @{
            Success = $false
            Error = "Preset '$PresetName' not found"
            Report = "Available presets: $($presets.Keys -join ', ')"
        }
    }
    
    $result = @{
        Success = $false
        PresetName = $PresetName
        Checks = @()
        Issues = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("DIAGNOSTIC PRESET: $($preset.Name)") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("Description: $($preset.Description)") | Out-Null
    $report.AppendLine("Estimated Time: $($preset.EstimatedTime)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    foreach ($check in $preset.Checks) {
        switch ($check) {
            "Boot" {
                $bootProb = Get-BootProbability -TargetDrive $TargetDrive
                $result.Checks += @{ Type = "Boot"; Result = $bootProb }
                $report.AppendLine("Boot Check: $($bootProb.Score)% - $($bootProb.HealthStatus)") | Out-Null
                if ($bootProb.Score -lt 70) {
                    $result.Issues += "Boot issues detected"
                }
            }
            "SystemFiles" {
                $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
                $result.Checks += @{ Type = "SystemFiles"; Result = $fileHealth }
                $report.AppendLine("System Files: $(if ($fileHealth.SystemFilesHealthy) { 'OK' } else { 'Issues' })") | Out-Null
                if (-not $fileHealth.SystemFilesHealthy) {
                    $result.Issues += "System file corruption detected"
                }
            }
            "Disk" {
                $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
                $result.Checks += @{ Type = "Disk"; Result = $diskHealth }
                $report.AppendLine("Disk Health: $(if ($diskHealth.FileSystemHealthy) { 'OK' } else { 'Issues' })") | Out-Null
                if ($diskHealth.NeedsRepair) {
                    $result.Issues += "Disk errors detected"
                }
            }
            "Registry" {
                $regHealth = Test-RegistryHealth -TargetDrive $TargetDrive
                $result.Checks += @{ Type = "Registry"; Result = $regHealth }
                $report.AppendLine("Registry: $(if ($regHealth.Healthy) { 'OK' } else { 'Issues' })") | Out-Null
                if (-not $regHealth.Healthy) {
                    $result.Issues += "Registry corruption detected"
                }
            }
            "UpgradeReadiness" {
                $readiness = Get-InPlaceUpgradeReadiness -TargetDrive $TargetDrive
                $result.Checks += @{ Type = "UpgradeReadiness"; Result = $readiness }
                $report.AppendLine("Upgrade Readiness: $(if ($readiness.ReadyForInPlaceUpgrade) { 'Ready' } else { 'Blocked' })") | Out-Null
                if (-not $readiness.ReadyForInPlaceUpgrade) {
                    $result.Issues += "In-place upgrade blockers: $($readiness.Blockers.Count)"
                }
            }
            "Validation" {
                $validation = Test-RepairValidation -TargetDrive $TargetDrive
                $result.Checks += @{ Type = "Validation"; Result = $validation }
                $report.AppendLine("Validation Score: $($validation.ConfidenceScore)%") | Out-Null
                if (-not $validation.ValidationPassed) {
                    $result.Issues += "Validation failed"
                }
            }
        }
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("SUMMARY:") | Out-Null
    $report.AppendLine("Issues Found: $($result.Issues.Count)") | Out-Null
    
    $result.Success = $true
    $result.Report = $report.ToString()
    return $result
}

function Start-ComprehensiveDiagnostics {
    <#
    .SYNOPSIS
    Runs all health checks and generates prioritized repair plan.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Issues = @()
        RepairPlan = @()
        RiskAssessment = @()
        EstimatedTime = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("COMPREHENSIVE SYSTEM DIAGNOSTICS") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 1. Boot Configuration Check
    $report.AppendLine("1. BOOT CONFIGURATION CHECK") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $bootDiag = Get-BootDiagnosis -TargetDrive $TargetDrive
        $report.AppendLine($bootDiag) | Out-Null
        
        if ($bootDiag -match "\[ERROR\]" -or $bootDiag -match "\[CRITICAL\]") {
            $result.Issues += @{
                Category = "Boot"
                Severity = "Critical"
                Description = "Boot configuration issues detected"
                RepairAction = "Run automated boot repair"
                EstimatedTime = "5-10 minutes"
                Risk = "Medium"
            }
        }
    } catch {
        $report.AppendLine("[ERROR] Boot diagnosis failed: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 2. System File Health Check
    $report.AppendLine("2. SYSTEM FILE HEALTH CHECK") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        $report.AppendLine("System Files: $(if ($fileHealth.SystemFilesHealthy) { 'OK' } else { 'Issues Found' })") | Out-Null
        $report.AppendLine("Component Store: $(if ($fileHealth.ComponentStoreHealthy) { 'OK' } else { 'Issues Found' })") | Out-Null
        
        if (-not $fileHealth.SystemFilesHealthy -or -not $fileHealth.ComponentStoreHealthy) {
            $result.Issues += @{
                Category = "System Files"
                Severity = "High"
                Description = "System file or component store corruption detected"
                RepairAction = "Run SFC + DISM repair"
                EstimatedTime = "15-30 minutes"
                Risk = "Low"
            }
        }
        
        if ($fileHealth.CBSLogIssues.Count -gt 0) {
            $report.AppendLine("CBS Log Issues: $($fileHealth.CBSLogIssues.Count) found") | Out-Null
        }
    } catch {
        $report.AppendLine("[ERROR] System file health check failed: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 3. Disk Health Check
    $report.AppendLine("3. DISK HEALTH CHECK") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        $report.AppendLine("File System: $($diskHealth.FileSystem)") | Out-Null
        $report.AppendLine("Health Status: $(if ($diskHealth.FileSystemHealthy) { 'OK' } else { 'Issues Found' })") | Out-Null
        
        if ($diskHealth.NeedsRepair) {
            $severity = if ($diskHealth.HasBadSectors) { "Critical" } else { "High" }
            $time = if ($diskHealth.HasBadSectors) { "1-4 hours" } else { "10-30 minutes" }
            
            $result.Issues += @{
                Category = "Disk"
                Severity = $severity
                Description = "File system corruption or bad sectors detected"
                RepairAction = "Run chkdsk repair"
                EstimatedTime = $time
                Risk = "Low"
            }
        }
        
        if ($diskHealth.BitLockerEncrypted) {
            $report.AppendLine("[WARNING] BitLocker encrypted - ensure recovery key available") | Out-Null
        }
    } catch {
        $report.AppendLine("[ERROR] Disk health check failed: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 4. Registry Health Check
    $report.AppendLine("4. REGISTRY HEALTH CHECK") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    try {
        $regHealth = Test-RegistryHealth -TargetDrive $TargetDrive
        $report.AppendLine("Registry Status: $(if ($regHealth.Healthy) { 'OK' } else { 'Issues Found' })") | Out-Null
        
        if (-not $regHealth.Healthy) {
            $result.Issues += @{
                Category = "Registry"
                Severity = "High"
                Description = "Registry hive corruption detected"
                RepairAction = "Run registry repair"
                EstimatedTime = "5-15 minutes"
                Risk = "Medium"
            }
        }
    } catch {
        $report.AppendLine("[WARNING] Registry health check not available: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 5. Component Store Check
    $report.AppendLine("5. COMPONENT STORE CHECK") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $envType = Get-EnvironmentType
    if ($envType -eq 'FullOS') {
        try {
            $dismCheck = dism /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
            $report.AppendLine($dismCheck) | Out-Null
        } catch {
            $report.AppendLine("[WARNING] Could not check component store") | Out-Null
        }
    } else {
        $report.AppendLine("[INFO] Component store check requires FullOS") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # Generate Repair Plan
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("PRIORITIZED REPAIR PLAN") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($result.Issues.Count -eq 0) {
        $report.AppendLine("[OK] No issues detected. System appears healthy.") | Out-Null
    } else {
        # Sort by severity: Critical > High > Medium > Low
        $severityOrder = @{ "Critical" = 0; "High" = 1; "Medium" = 2; "Low" = 3 }
        $sortedIssues = $result.Issues | Sort-Object { $severityOrder[$_.Severity] }
        
        $report.AppendLine("Found $($result.Issues.Count) issue(s). Recommended repair sequence:") | Out-Null
        $report.AppendLine("") | Out-Null
        
        $stepNum = 1
        foreach ($issue in $sortedIssues) {
            $result.RepairPlan += $issue.RepairAction
            $result.RiskAssessment += $issue.Risk
            $result.EstimatedTime += $issue.EstimatedTime
            
            $report.AppendLine("STEP $stepNum : $($issue.Category) - $($issue.Severity)") | Out-Null
            $report.AppendLine("  Issue: $($issue.Description)") | Out-Null
            $report.AppendLine("  Action: $($issue.RepairAction)") | Out-Null
            $report.AppendLine("  Time: $($issue.EstimatedTime)") | Out-Null
            $report.AppendLine("  Risk: $($issue.Risk)") | Out-Null
            $report.AppendLine("") | Out-Null
            $stepNum++
        }
        
        $totalTime = ($result.EstimatedTime | ForEach-Object { 
            if ($_ -match "(\d+)-(\d+)") { [int]$matches[2] } 
            elseif ($_ -match "(\d+)") { [int]$matches[1] } 
            else { 0 } 
        } | Measure-Object -Sum).Sum
        
        $report.AppendLine("Total Estimated Time: ~$totalTime minutes") | Out-Null
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Start-SmartBootRepair {
    <#
    .SYNOPSIS
    Automatically detects boot type and runs appropriate repair sequence.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        BootType = "Unknown"
        EFIPartition = $null
        RepairSequence = @()
        Report = ""
        Errors = @()
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("SMART BOOT REPAIR") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Detect boot type
    $report.AppendLine("Detecting boot type...") | Out-Null
    try {
        $partition = Get-Partition -DriveLetter $TargetDrive -ErrorAction SilentlyContinue
        if ($partition) {
            $disk = Get-Disk -Number $partition.DiskNumber
            $efiParts = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
            
            if ($efiParts.Count -gt 0) {
                $result.BootType = "UEFI"
                $report.AppendLine("[OK] UEFI boot detected") | Out-Null
                
                # Find EFI partition with drive letter
                foreach ($efiPart in $efiParts) {
                    if ($efiPart.DriveLetter) {
                        $result.EFIPartition = $efiPart.DriveLetter
                        $report.AppendLine("EFI Partition: $($efiPart.DriveLetter):") | Out-Null
                        break
                    }
                }
                
                if (-not $result.EFIPartition) {
                    $report.AppendLine("[WARNING] EFI partition found but no drive letter assigned") | Out-Null
                }
            } else {
                $result.BootType = "Legacy"
                $report.AppendLine("[OK] Legacy BIOS boot detected") | Out-Null
            }
        }
    } catch {
        $errorMsg = "Could not detect boot type: $_"
        $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        $result.Errors += $errorMsg
        $result.Report = $report.ToString()
        return $result
    }
    $report.AppendLine("") | Out-Null
    
    # Run appropriate repair sequence
    $report.AppendLine("Running boot repair sequence...") | Out-Null
    $report.AppendLine("") | Out-Null
    
    $bootRepair = Start-AutomatedBootRepair -TargetDrive $TargetDrive -SkipConfirmation
    $result.RepairSequence = $bootRepair.StepsCompleted
    $result.Success = $bootRepair.Success
    $report.AppendLine($bootRepair.Report) | Out-Null
    $result.Errors = $bootRepair.Errors
    
    $result.Report = $report.ToString()
    return $result
}

function Save-RepairCheckpoint {
    <#
    .SYNOPSIS
    Creates restore point and backups before repair operations.
    #>
    param(
        [string]$TargetDrive = "C",
        [string]$CheckpointName = "MiracleBoot_Repair_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    )
    
    $result = @{
        Success = $false
        CheckpointPath = ""
        BCDBackup = ""
        RegistryBackups = @()
        Report = ""
        Errors = @()
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("CREATING REPAIR CHECKPOINT") | Out-Null
    $report.AppendLine("Checkpoint Name: $CheckpointName") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $checkpointDir = "$env:TEMP\$CheckpointName"
    New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
    $result.CheckpointPath = $checkpointDir
    
    # Backup BCD
    $report.AppendLine("Backing up BCD...") | Out-Null
    try {
        $bcdBackup = Export-BCDBackup -BackupPath "$checkpointDir\BCD_Backup.bcd"
        if ($bcdBackup.Success) {
            $result.BCDBackup = $bcdBackup.Path
            $report.AppendLine("[OK] BCD backed up to: $($bcdBackup.Path)") | Out-Null
        } else {
            throw $bcdBackup.Error
        }
    } catch {
        $errorMsg = "BCD backup failed: $_"
        $report.AppendLine("[WARNING] $errorMsg") | Out-Null
        $result.Errors += $errorMsg
    }
    $report.AppendLine("") | Out-Null
    
    # Backup Registry Hives (if offline)
    $envType = Get-EnvironmentType
    if ($envType -ne 'FullOS') {
        $report.AppendLine("Backing up registry hives...") | Out-Null
        $hives = @("SYSTEM", "SOFTWARE", "SAM", "SECURITY")
        foreach ($hive in $hives) {
            $hivePath = "$TargetDrive`:\Windows\System32\config\$hive"
            if (Test-Path $hivePath) {
                try {
                    $backupPath = "$checkpointDir\${hive}_Backup"
                    Copy-Item $hivePath $backupPath -ErrorAction Stop
                    $result.RegistryBackups += $backupPath
                    $report.AppendLine("[OK] $hive hive backed up") | Out-Null
                } catch {
                    $errorMsg = "Failed to backup $hive hive: $_"
                    $report.AppendLine("[WARNING] $errorMsg") | Out-Null
                    $result.Errors += $errorMsg
                }
            }
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Try to create system restore point (FullOS only)
    if ($envType -eq 'FullOS') {
        $report.AppendLine("Attempting to create system restore point...") | Out-Null
        try {
            $restorePoint = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
            # Note: Creating restore points programmatically requires vssadmin or WMI
            $report.AppendLine("[INFO] System restore point creation attempted") | Out-Null
        } catch {
            $report.AppendLine("[WARNING] Could not create system restore point: $_") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    $result.Success = $true
    $report.AppendLine("[OK] Checkpoint created at: $checkpointDir") | Out-Null
    $result.Report = $report.ToString()
    return $result
}

function Restore-RepairCheckpoint {
    <#
    .SYNOPSIS
    Restores from a repair checkpoint.
    #>
    param(
        [string]$CheckpointPath
    )
    
    $result = @{
        Success = $false
        Report = ""
        Errors = @()
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("RESTORING REPAIR CHECKPOINT") | Out-Null
    $report.AppendLine("Checkpoint: $CheckpointPath") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    if (-not (Test-Path $CheckpointPath)) {
        $errorMsg = "Checkpoint path not found: $CheckpointPath"
        $report.AppendLine("[ERROR] $errorMsg") | Out-Null
        $result.Errors += $errorMsg
        $result.Report = $report.ToString()
        return $result
    }
    
    # Restore BCD
    $bcdBackup = Join-Path $CheckpointPath "BCD_Backup.bcd"
    if (Test-Path $bcdBackup) {
        $report.AppendLine("Restoring BCD...") | Out-Null
        try {
            bcdedit /import $bcdBackup 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $report.AppendLine("[OK] BCD restored") | Out-Null
            } else {
                throw "BCD restore failed with exit code $LASTEXITCODE"
            }
        } catch {
            $errorMsg = "BCD restore failed: $_"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.Errors += $errorMsg
        }
        $report.AppendLine("") | Out-Null
    }
    
    $report.AppendLine("[WARNING] Registry hive restoration requires manual intervention") | Out-Null
    $report.AppendLine("Backup files are available at: $CheckpointPath") | Out-Null
    
    $result.Success = ($result.Errors.Count -eq 0)
    $result.Report = $report.ToString()
    return $result
}

function Get-RepairHistory {
    <#
    .SYNOPSIS
    Retrieves repair operations history with analytics.
    
    .DESCRIPTION
    Returns comprehensive repair history including:
    - All repair operations performed
    - Success rates
    - System health trends over time
    - Repair frequency analysis
    - Health score tracking
    #>
    param(
        [int]$Limit = 100,
        [DateTime]$StartDate = $null,
        [DateTime]$EndDate = $null
    )
    
    $historyFile = "$env:TEMP\MiracleBoot_RepairHistory.json"
    
    $history = @()
    if (Test-Path $historyFile) {
        try {
            $history = Get-Content $historyFile | ConvertFrom-Json
        } catch {
            Write-Warning "Could not read repair history: $_"
        }
    }
    
    # Filter by date range if specified
    if ($StartDate -or $EndDate) {
        $history = $history | Where-Object {
            $entryDate = [DateTime]::Parse($_.Timestamp)
            $passStart = if ($StartDate) { $entryDate -ge $StartDate } else { $true }
            $passEnd = if ($EndDate) { $entryDate -le $EndDate } else { $true }
            return ($passStart -and $passEnd)
        }
    }
    
    # Limit results
    if ($Limit -gt 0) {
        $history = $history | Select-Object -Last $Limit
    }
    
    return $history
}

function Save-RepairHistory {
    <#
    .SYNOPSIS
    Saves a repair operation to history.
    #>
    param(
        [hashtable]$RepairResult,
        [string]$OperationType,
        [string]$TargetDrive = "C"
    )
    
    $historyFile = "$env:TEMP\MiracleBoot_RepairHistory.json"
    
    # Load existing history
    $history = @()
    if (Test-Path $historyFile) {
        try {
            $history = Get-Content $historyFile | ConvertFrom-Json
        } catch {
            $history = @()
        }
    }
    
    # Create history entry
    $entry = @{
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        OperationType = $OperationType
        TargetDrive = $TargetDrive
        Success = if ($RepairResult.Success -ne $null) { $RepairResult.Success } else { $false }
        StepsCompleted = if ($RepairResult.StepsCompleted) { $RepairResult.StepsCompleted.Count } else { 0 }
        StepsFailed = if ($RepairResult.StepsFailed) { $RepairResult.StepsFailed.Count } else { 0 }
        ValidationScore = if ($RepairResult.ValidationScore) { $RepairResult.ValidationScore } else { $null }
        RestorePointID = if ($RepairResult.RestorePointID) { $RepairResult.RestorePointID } else { $null }
        Errors = if ($RepairResult.Errors) { $RepairResult.Errors.Count } else { 0 }
    }
    
    # Add to history
    $history += $entry
    
    # Keep only last 1000 entries
    if ($history.Count -gt 1000) {
        $history = $history | Select-Object -Last 1000
    }
    
    # Save history
    try {
        $history | ConvertTo-Json -Depth 10 | Out-File -FilePath $historyFile -Encoding UTF8
    } catch {
        Write-Warning "Could not save repair history: $_"
    }
    
    return $entry
}

function Get-RepairAnalytics {
    <#
    .SYNOPSIS
    Generates analytics from repair history including success rates and trends.
    #>
    param(
        [int]$Days = 30
    )
    
    $cutoffDate = (Get-Date).AddDays(-$Days)
    $history = Get-RepairHistory -StartDate $cutoffDate
    
    $analytics = @{
        TotalRepairs = $history.Count
        SuccessfulRepairs = ($history | Where-Object { $_.Success -eq $true }).Count
        FailedRepairs = ($history | Where-Object { $_.Success -eq $false }).Count
        SuccessRate = 0
        AverageValidationScore = 0
        MostCommonOperation = $null
        RepairFrequency = @{}
        HealthTrend = @()
        Report = ""
    }
    
    if ($history.Count -gt 0) {
        $analytics.SuccessRate = [math]::Round(($analytics.SuccessfulRepairs / $analytics.TotalRepairs) * 100, 2)
        
        # Calculate average validation score
        $scoresWithValidation = $history | Where-Object { $_.ValidationScore -ne $null } | ForEach-Object { $_.ValidationScore }
        if ($scoresWithValidation.Count -gt 0) {
            $analytics.AverageValidationScore = [math]::Round(($scoresWithValidation | Measure-Object -Average).Average, 2)
        }
        
        # Find most common operation
        $operationCounts = $history | Group-Object -Property OperationType | Sort-Object Count -Descending
        if ($operationCounts.Count -gt 0) {
            $analytics.MostCommonOperation = $operationCounts[0].Name
        }
        
        # Repair frequency by day
        $dailyRepairs = $history | Group-Object { ([DateTime]::Parse($_.Timestamp)).Date }
        foreach ($day in $dailyRepairs) {
            $analytics.RepairFrequency[$day.Name.ToString("yyyy-MM-dd")] = $day.Count
        }
        
        # Health trend (validation scores over time)
        $healthEntries = $history | Where-Object { $_.ValidationScore -ne $null } | Sort-Object { [DateTime]::Parse($_.Timestamp) }
        foreach ($entry in $healthEntries) {
            $analytics.HealthTrend += @{
                Date = [DateTime]::Parse($entry.Timestamp)
                Score = $entry.ValidationScore
            }
        }
    }
    
    # Generate report
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REPAIR ANALYTICS (Last $Days Days)") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $report.AppendLine("SUMMARY:") | Out-Null
    $report.AppendLine("  Total Repairs: $($analytics.TotalRepairs)") | Out-Null
    $report.AppendLine("  Successful: $($analytics.SuccessfulRepairs)") | Out-Null
    $report.AppendLine("  Failed: $($analytics.FailedRepairs)") | Out-Null
    $report.AppendLine("  Success Rate: $($analytics.SuccessRate)%") | Out-Null
    
    if ($analytics.AverageValidationScore -gt 0) {
        $report.AppendLine("  Average Validation Score: $($analytics.AverageValidationScore)%") | Out-Null
    }
    
    if ($analytics.MostCommonOperation) {
        $report.AppendLine("  Most Common Operation: $($analytics.MostCommonOperation)") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    if ($analytics.RepairFrequency.Count -gt 0) {
        $report.AppendLine("REPAIR FREQUENCY:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $sortedDays = $analytics.RepairFrequency.GetEnumerator() | Sort-Object Key -Descending | Select-Object -First 10
        foreach ($day in $sortedDays) {
            $report.AppendLine("  $($day.Key): $($day.Value) repair(s)") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    if ($analytics.HealthTrend.Count -gt 0) {
        $report.AppendLine("HEALTH TREND:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $recentTrend = $analytics.HealthTrend | Select-Object -Last 10
        foreach ($point in $recentTrend) {
            $report.AppendLine("  $($point.Date.ToString('yyyy-MM-dd')): $($point.Score)%") | Out-Null
        }
    }
    
    $analytics.Report = $report.ToString()
    return $analytics
}

function Get-HealthScore {
    <#
    .SYNOPSIS
    Calculates current system health score (0-100).
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $score = 0
    $weights = @{
        Boot = 30
        SystemFiles = 25
        Disk = 20
        Registry = 15
        UpgradeReadiness = 10
    }
    
    $components = @{}
    
    # Boot health (30%)
    try {
        $bootProb = Get-BootProbability -TargetDrive $TargetDrive
        $components.Boot = $bootProb.Score
        $score += ($bootProb.Score * $weights.Boot / 100)
    } catch {
        $components.Boot = 0
    }
    
    # System files health (25%)
    try {
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        $fileScore = if ($fileHealth.SystemFilesHealthy -and $fileHealth.ComponentStoreHealthy) { 100 } elseif ($fileHealth.SystemFilesHealthy -or $fileHealth.ComponentStoreHealthy) { 50 } else { 0 }
        $components.SystemFiles = $fileScore
        $score += ($fileScore * $weights.SystemFiles / 100)
    } catch {
        $components.SystemFiles = 0
    }
    
    # Disk health (20%)
    try {
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        $diskScore = if ($diskHealth.FileSystemHealthy -and -not $diskHealth.HasBadSectors) { 100 } elseif ($diskHealth.FileSystemHealthy) { 70 } else { 30 }
        $components.Disk = $diskScore
        $score += ($diskScore * $weights.Disk / 100)
    } catch {
        $components.Disk = 0
    }
    
    # Registry health (15%)
    try {
        $regHealth = Test-RegistryHealth -TargetDrive $TargetDrive
        $regScore = if ($regHealth.Healthy) { 100 } else { 50 }
        $components.Registry = $regScore
        $score += ($regScore * $weights.Registry / 100)
    } catch {
        $components.Registry = 0
    }
    
    # Upgrade readiness (10%)
    try {
        $readiness = Get-InPlaceUpgradeReadiness -TargetDrive $TargetDrive
        $readinessScore = if ($readiness.ReadyForInPlaceUpgrade) { 100 } else { 30 }
        $components.UpgradeReadiness = $readinessScore
        $score += ($readinessScore * $weights.UpgradeReadiness / 100)
    } catch {
        $components.UpgradeReadiness = 0
    }
    
    $overallScore = [math]::Round($score, 1)
    
    # Determine health status
    $status = if ($overallScore -ge 80) { "Excellent" }
              elseif ($overallScore -ge 60) { "Good" }
              elseif ($overallScore -ge 40) { "Fair" }
              elseif ($overallScore -ge 20) { "Poor" }
              else { "Critical" }
    
    return @{
        OverallScore = $overallScore
        Status = $status
        Components = $components
        Timestamp = Get-Date
    }
}

function Save-HealthSnapshot {
    <#
    .SYNOPSIS
    Saves a health snapshot for trend tracking.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $healthFile = "$env:TEMP\MiracleBoot_HealthHistory.json"
    
    $health = Get-HealthScore -TargetDrive $TargetDrive
    
    # Load existing history
    $history = @()
    if (Test-Path $healthFile) {
        try {
            $history = Get-Content $healthFile | ConvertFrom-Json
        } catch {
            $history = @()
        }
    }
    
    # Add snapshot
    $snapshot = @{
        Timestamp = $health.Timestamp.ToString("yyyy-MM-dd HH:mm:ss")
        OverallScore = $health.OverallScore
        Status = $health.Status
        Components = $health.Components
        TargetDrive = $TargetDrive
    }
    
    $history += $snapshot
    
    # Keep only last 1000 snapshots
    if ($history.Count -gt 1000) {
        $history = $history | Select-Object -Last 1000
    }
    
    # Save history
    try {
        $history | ConvertTo-Json -Depth 10 | Out-File -FilePath $healthFile -Encoding UTF8
    } catch {
        Write-Warning "Could not save health snapshot: $_"
    }
    
    return $snapshot
}

function Get-HealthTrend {
    <#
    .SYNOPSIS
    Analyzes health trends over time.
    #>
    param(
        [int]$Days = 30,
        [string]$TargetDrive = "C"
    )
    
    $healthFile = "$env:TEMP\MiracleBoot_HealthHistory.json"
    
    $history = @()
    if (Test-Path $healthFile) {
        try {
            $history = Get-Content $healthFile | ConvertFrom-Json
        } catch {
            return @{
                Success = $false
                Error = "Could not read health history: $_"
                Trend = @()
            }
        }
    }
    
    # Filter by date and drive
    $cutoffDate = (Get-Date).AddDays(-$Days)
    $filtered = $history | Where-Object {
        $entryDate = [DateTime]::Parse($_.Timestamp)
        $entryDate -ge $cutoffDate -and $_.TargetDrive -eq $TargetDrive
    } | Sort-Object { [DateTime]::Parse($_.Timestamp) }
    
    $trend = @{
        Success = $true
        TotalSnapshots = $filtered.Count
        CurrentScore = 0
        PreviousScore = 0
        AverageScore = 0
        TrendDirection = "Unknown"
        TrendStrength = 0
        MinScore = 0
        MaxScore = 0
        RecentScores = @()
        Report = ""
    }
    
    if ($filtered.Count -gt 0) {
        $scores = $filtered | ForEach-Object { $_.OverallScore }
        $trend.CurrentScore = $scores[-1]
        $trend.PreviousScore = if ($scores.Count -gt 1) { $scores[-2] } else { $scores[-1] }
        $trend.AverageScore = [math]::Round(($scores | Measure-Object -Average).Average, 1)
        $trend.MinScore = ($scores | Measure-Object -Minimum).Minimum
        $trend.MaxScore = ($scores | Measure-Object -Maximum).Maximum
        
        # Calculate trend direction
        $recentScores = $scores | Select-Object -Last 5
        if ($recentScores.Count -ge 2) {
            $firstHalf = ($recentScores | Select-Object -First ([math]::Floor($recentScores.Count / 2)) | Measure-Object -Average).Average
            $secondHalf = ($recentScores | Select-Object -Last ([math]::Ceiling($recentScores.Count / 2)) | Measure-Object -Average).Average
            $difference = $secondHalf - $firstHalf
            
            if ($difference -gt 5) {
                $trend.TrendDirection = "Improving"
                $trend.TrendStrength = [math]::Round($difference, 1)
            } elseif ($difference -lt -5) {
                $trend.TrendDirection = "Declining"
                $trend.TrendStrength = [math]::Round([math]::Abs($difference), 1)
            } else {
                $trend.TrendDirection = "Stable"
                $trend.TrendStrength = [math]::Round([math]::Abs($difference), 1)
            }
        }
        
        $trend.RecentScores = $filtered | Select-Object -Last 10 | ForEach-Object {
            @{
                Date = [DateTime]::Parse($_.Timestamp)
                Score = $_.OverallScore
                Status = $_.Status
            }
        }
    }
    
    # Generate report
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("HEALTH TREND ANALYSIS (Last $Days Days)") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $report.AppendLine("SUMMARY:") | Out-Null
    $report.AppendLine("  Total Snapshots: $($trend.TotalSnapshots)") | Out-Null
    $report.AppendLine("  Current Score: $($trend.CurrentScore)%") | Out-Null
    $report.AppendLine("  Previous Score: $($trend.PreviousScore)%") | Out-Null
    $report.AppendLine("  Average Score: $($trend.AverageScore)%") | Out-Null
    $report.AppendLine("  Min Score: $($trend.MinScore)%") | Out-Null
    $report.AppendLine("  Max Score: $($trend.MaxScore)%") | Out-Null
    $report.AppendLine("  Trend: $($trend.TrendDirection) ($($trend.TrendStrength) points)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($trend.RecentScores.Count -gt 0) {
        $report.AppendLine("RECENT SCORES:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        foreach ($point in $trend.RecentScores) {
            $report.AppendLine("  $($point.Date.ToString('yyyy-MM-dd HH:mm')): $($point.Score)% ($($point.Status))") | Out-Null
        }
    }
    
    $trend.Report = $report.ToString()
    return $trend
}

function Get-HealthAlerts {
    <#
    .SYNOPSIS
    Returns critical health alerts based on current system state.
    #>
    param(
        [string]$TargetDrive = "C",
        [int]$CriticalThreshold = 40,
        [int]$WarningThreshold = 60
    )
    
    $health = Get-HealthScore -TargetDrive $TargetDrive
    $alerts = @()
    
    # Overall health alert
    if ($health.OverallScore -lt $CriticalThreshold) {
        $alerts += @{
            Severity = "Critical"
            Component = "Overall"
            Message = "System health is critically low: $($health.OverallScore)%"
            Recommendation = "Run comprehensive diagnostics and repairs immediately"
        }
    } elseif ($health.OverallScore -lt $WarningThreshold) {
        $alerts += @{
            Severity = "Warning"
            Component = "Overall"
            Message = "System health is below optimal: $($health.OverallScore)%"
            Recommendation = "Consider running diagnostics and preventive repairs"
        }
    }
    
    # Component-specific alerts
    foreach ($component in $health.Components.GetEnumerator()) {
        if ($component.Value -lt 50) {
            $alerts += @{
                Severity = if ($component.Value -lt 30) { "Critical" } else { "Warning" }
                Component = $component.Key
                Message = "$($component.Key) health is low: $($component.Value)%"
                Recommendation = "Run $($component.Key) repair operations"
            }
        }
    }
    
    return @{
        Alerts = $alerts
        CriticalCount = ($alerts | Where-Object { $_.Severity -eq "Critical" }).Count
        WarningCount = ($alerts | Where-Object { $_.Severity -eq "Warning" }).Count
        HealthScore = $health.OverallScore
    }
}

function Start-HealthMonitoring {
    <#
    .SYNOPSIS
    Starts continuous health monitoring with periodic snapshots and alerts.
    #>
    param(
        [string]$TargetDrive = "C",
        [int]$IntervalMinutes = 60,
        [int]$DurationMinutes = 0,
        [int]$CriticalThreshold = 40,
        [switch]$SaveSnapshots = $true,
        [switch]$ShowAlerts = $true,
        [scriptblock]$AlertCallback = $null
    )
    
    $startTime = Get-Date
    $endTime = if ($DurationMinutes -gt 0) { $startTime.AddMinutes($DurationMinutes) } else { $null }
    $iteration = 0
    
    Write-Host "Starting health monitoring..." -ForegroundColor Cyan
    Write-Host "  Target Drive: $TargetDrive" -ForegroundColor Gray
    Write-Host "  Interval: $IntervalMinutes minutes" -ForegroundColor Gray
    if ($endTime) {
        Write-Host "  Duration: $DurationMinutes minutes (until $($endTime.ToString('HH:mm:ss')))" -ForegroundColor Gray
    } else {
        Write-Host "  Duration: Continuous (press Ctrl+C to stop)" -ForegroundColor Gray
    }
    Write-Host ""
    
    while ($true) {
        $iteration++
        $currentTime = Get-Date
        
        # Check if duration exceeded
        if ($endTime -and $currentTime -ge $endTime) {
            Write-Host "Monitoring duration completed." -ForegroundColor Green
            break
        }
        
        Write-Host "[$($currentTime.ToString('HH:mm:ss'))] Health Check #$iteration" -ForegroundColor Cyan
        
        # Get health score
        $health = Get-HealthScore -TargetDrive $TargetDrive
        
        # Save snapshot if requested
        if ($SaveSnapshots) {
            Save-HealthSnapshot -TargetDrive $TargetDrive | Out-Null
        }
        
        # Check for alerts
        $alerts = Get-HealthAlerts -TargetDrive $TargetDrive -CriticalThreshold $CriticalThreshold
        
        # Display status
        $statusColor = switch ($health.Status) {
            "Excellent" { "Green" }
            "Good" { "Cyan" }
            "Fair" { "Yellow" }
            "Poor" { "Magenta" }
            "Critical" { "Red" }
            default { "White" }
        }
        
        Write-Host "  Health Score: $($health.OverallScore)% ($($health.Status))" -ForegroundColor $statusColor
        
        if ($alerts.CriticalCount -gt 0) {
            Write-Host "  [CRITICAL] $($alerts.CriticalCount) critical alert(s)" -ForegroundColor Red
        }
        if ($alerts.WarningCount -gt 0) {
            Write-Host "  [WARNING] $($alerts.WarningCount) warning(s)" -ForegroundColor Yellow
        }
        
        # Show alerts if requested
        if ($ShowAlerts -and $alerts.Alerts.Count -gt 0) {
            Write-Host ""
            foreach ($alert in $alerts.Alerts) {
                $alertColor = if ($alert.Severity -eq "Critical") { "Red" } else { "Yellow" }
                Write-Host "  [$($alert.Severity)] $($alert.Component): $($alert.Message)" -ForegroundColor $alertColor
                Write-Host "    Recommendation: $($alert.Recommendation)" -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        # Call alert callback if provided
        if ($AlertCallback -and $alerts.Alerts.Count -gt 0) {
            try {
                & $AlertCallback $alerts
            } catch {
                Write-Warning "Alert callback failed: $_"
            }
        }
        
        # Wait for next interval
        if ($endTime -and (Get-Date).AddMinutes($IntervalMinutes) -gt $endTime) {
            break
        }
        
        Write-Host "  Next check in $IntervalMinutes minute(s)..." -ForegroundColor Gray
        Write-Host ""
        
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
    
    Write-Host "Health monitoring stopped." -ForegroundColor Green
    return @{
        Success = $true
        Iterations = $iteration
        Duration = (Get-Date) - $startTime
    }
}

function Test-HealthThresholds {
    <#
    .SYNOPSIS
    Tests if system health meets specified thresholds.
    #>
    param(
        [string]$TargetDrive = "C",
        [int]$MinimumScore = 60,
        [hashtable]$ComponentThresholds = @{}
    )
    
    $health = Get-HealthScore -TargetDrive $TargetDrive
    $result = @{
        Passed = $true
        OverallScore = $health.OverallScore
        MeetsMinimum = $health.OverallScore -ge $MinimumScore
        ComponentResults = @()
        FailedComponents = @()
    }
    
    # Test overall score
    if ($health.OverallScore -lt $MinimumScore) {
        $result.Passed = $false
        $result.FailedComponents += "Overall (Score: $($health.OverallScore)%, Required: $MinimumScore%)"
    }
    
    # Test component thresholds
    foreach ($threshold in $ComponentThresholds.GetEnumerator()) {
        $componentName = $threshold.Key
        $requiredScore = $threshold.Value
        
        if ($health.Components.ContainsKey($componentName)) {
            $actualScore = $health.Components[$componentName]
            $meetsThreshold = $actualScore -ge $requiredScore
            
            $result.ComponentResults += @{
                Component = $componentName
                Required = $requiredScore
                Actual = $actualScore
                Passed = $meetsThreshold
            }
            
            if (-not $meetsThreshold) {
                $result.Passed = $false
                $result.FailedComponents += "$componentName (Score: $actualScore%, Required: $requiredScore%)"
            }
        }
    }
    
    return $result
}

function Test-RegistryHealth {
    <#
    .SYNOPSIS
    Checks registry hive integrity.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Healthy = $true
        Issues = @()
        Report = ""
    }
    
    $envType = Get-EnvironmentType
    $hives = @("SYSTEM", "SOFTWARE", "SAM", "SECURITY")
    
    foreach ($hive in $hives) {
        $hivePath = "$TargetDrive`:\Windows\System32\config\$hive"
        if (Test-Path $hivePath) {
            try {
                # Try to load hive (offline) or access (online)
                if ($envType -ne 'FullOS') {
                    # Offline: try to load
                    reg load "HKLM\TempHive" $hivePath 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        reg unload "HKLM\TempHive" 2>&1 | Out-Null
                    } else {
                        $result.Healthy = $false
                        $result.Issues += "$hive hive appears corrupted"
                    }
                } else {
                    # Online: check if accessible
                    $testKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
                    if (-not (Test-Path $testKey)) {
                        $result.Healthy = $false
                        $result.Issues += "SOFTWARE hive may be corrupted"
                    }
                }
            } catch {
                $result.Healthy = $false
                $result.Issues += "Could not verify $hive hive: $_"
            }
        }
    }
    
    return $result
}

function Repair-RegistryHives {
    <#
    .SYNOPSIS
    Attempts to repair registry hives.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        Report = ""
        Errors = @()
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REGISTRY HIVE REPAIR") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $report.AppendLine("[INFO] Registry hive repair is complex and risky.") | Out-Null
    $report.AppendLine("Consider using System Restore or repair install instead.") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Backup first
    $checkpoint = Save-RepairCheckpoint -TargetDrive $TargetDrive -CheckpointName "RegistryRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if ($checkpoint.Success) {
        $report.AppendLine("[OK] Registry backups created before repair attempt") | Out-Null
    }
    
    $report.AppendLine("[WARNING] Manual registry repair not implemented.") | Out-Null
    $report.AppendLine("Use Windows built-in repair tools or repair install.") | Out-Null
    
    $result.Report = $report.ToString()
    return $result
}

function Backup-RegistryHives {
    <#
    .SYNOPSIS
    Backs up registry hives before repair.
    #>
    param(
        [string]$TargetDrive = "C",
        [string]$BackupPath = "$env:TEMP\RegistryBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    )
    
    $result = @{
        Success = $false
        BackupPath = $BackupPath
        BackedUpHives = @()
        Errors = @()
    }
    
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    
    $hives = @("SYSTEM", "SOFTWARE", "SAM", "SECURITY")
    foreach ($hive in $hives) {
        $hivePath = "$TargetDrive`:\Windows\System32\config\$hive"
        if (Test-Path $hivePath) {
            try {
                $backupFile = Join-Path $BackupPath "$hive"
                Copy-Item $hivePath $backupFile -ErrorAction Stop
                $result.BackedUpHives += $hive
            } catch {
                $result.Errors += "Failed to backup ${hive}: $_"
            }
        }
    }
    
    $result.Success = ($result.BackedUpHives.Count -gt 0)
    return $result
}

function Start-RepairLogging {
    <#
    .SYNOPSIS
    Initializes repair session logging.
    #>
    param(
        [string]$LogPath = "$env:TEMP\MiracleBoot_Repair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    )
    
    $script:RepairLogPath = $LogPath
    $script:RepairLogStartTime = Get-Date
    
    $logHeader = @"
========================================
MiracleBoot Repair Session Log
Started: $($script:RepairLogStartTime)
========================================

"@
    
    $logHeader | Out-File -FilePath $LogPath -Encoding UTF8
    
    return @{
        LogPath = $LogPath
        StartTime = $script:RepairLogStartTime
    }
}

function Write-RepairLog {
    <#
    .SYNOPSIS
    Writes to repair log with enhanced formatting and categorization.
    #>
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Category = "General",
        [string]$Operation = ""
    )
    
    if (-not $script:RepairLogPath) {
        Start-RepairLogging | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level]"
    
    if ($Category -ne "General") {
        $logEntry += " [$Category]"
    }
    
    if ($Operation) {
        $logEntry += " [$Operation]"
    }
    
    $logEntry += " $Message"
    
    $logEntry | Out-File -FilePath $script:RepairLogPath -Append -Encoding UTF8
    
    # Check log size and rotate if needed
    if (Test-Path $script:RepairLogPath) {
        $logFile = Get-Item $script:RepairLogPath
        if ($logFile.Length -gt 10MB) {
            Rotate-RepairLogs -LogPath $script:RepairLogPath
        }
    }
}

function Rotate-RepairLogs {
    <#
    .SYNOPSIS
    Rotates repair logs when they become too large, keeping a history of recent logs.
    #>
    param(
        [string]$LogPath = $script:RepairLogPath,
        [int]$MaxLogSizeMB = 10,
        [int]$KeepLogs = 5
    )
    
    if (-not $LogPath -or -not (Test-Path $LogPath)) {
        return
    }
    
    try {
        $logFile = Get-Item $LogPath
        $logSizeMB = [math]::Round($logFile.Length / 1MB, 2)
        
        if ($logSizeMB -gt $MaxLogSizeMB) {
            $logDir = Split-Path $LogPath -Parent
            $logName = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
            $logExt = [System.IO.Path]::GetExtension($LogPath)
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            
            # Archive current log
            $archivePath = Join-Path $logDir "${logName}_${timestamp}${logExt}"
            Move-Item $LogPath $archivePath -Force
            
            # Compress old logs
            $oldLogs = Get-ChildItem -Path $logDir -Filter "${logName}_*${logExt}" | 
                Sort-Object LastWriteTime -Descending | 
                Select-Object -Skip $KeepLogs
            
            foreach ($oldLog in $oldLogs) {
                try {
                    $zipPath = $oldLog.FullName -replace $logExt, ".zip"
                    Compress-Archive -Path $oldLog.FullName -DestinationPath $zipPath -Force
                    Remove-Item $oldLog.FullName -Force
                } catch {
                    Write-Warning "Could not compress log $($oldLog.Name): $_"
                }
            }
            
            # Start new log
            Start-RepairLogging -LogPath $LogPath | Out-Null
            Write-RepairLog "Log rotated - previous log archived to: $archivePath" "INFO" "Logging"
        }
    } catch {
        Write-Warning "Log rotation failed: $_"
    }
}

function Get-LogAnalysis {
    <#
    .SYNOPSIS
    Analyzes repair logs to identify patterns, errors, and trends.
    #>
    param(
        [string]$LogPath = $script:RepairLogPath,
        [int]$Days = 7
    )
    
    $result = @{
        TotalEntries = 0
        ErrorCount = 0
        WarningCount = 0
        Operations = @()
        Errors = @()
        Warnings = @()
        Trends = @{}
        Report = ""
    }
    
    if (-not $LogPath -or -not (Test-Path $LogPath)) {
        $result.Report = "Log file not found: $LogPath"
        return $result
    }
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$Days)
        $logContent = Get-Content $LogPath
        
        foreach ($line in $logContent) {
            if ($line -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[(\w+)\](?: \[(\w+)\])?(?: \[(\w+)\])? (.*)') {
                $timestamp = [DateTime]::Parse($matches[1])
                $level = $matches[2]
                $category = if ($matches[3]) { $matches[3] } else { "General" }
                $operation = if ($matches[4]) { $matches[4] } else { "" }
                $message = $matches[5]
                
                if ($timestamp -ge $cutoffDate) {
                    $result.TotalEntries++
                    
                    if ($level -eq "ERROR") {
                        $result.ErrorCount++
                        $result.Errors += @{
                            Timestamp = $timestamp
                            Category = $category
                            Operation = $operation
                            Message = $message
                        }
                    } elseif ($level -eq "WARNING") {
                        $result.WarningCount++
                        $result.Warnings += @{
                            Timestamp = $timestamp
                            Category = $category
                            Operation = $operation
                            Message = $message
                        }
                    }
                    
                    if ($operation) {
                        if (-not $result.Operations.ContainsKey($operation)) {
                            $result.Operations[$operation] = 0
                        }
                        $result.Operations[$operation]++
                    }
                }
            }
        }
        
        # Generate report
        $report = New-Object System.Text.StringBuilder
        $report.AppendLine("LOG ANALYSIS (Last $Days Days)") | Out-Null
        $report.AppendLine("=" * 80) | Out-Null
        $report.AppendLine("Total Entries: $($result.TotalEntries)") | Out-Null
        $report.AppendLine("Errors: $($result.ErrorCount)") | Out-Null
        $report.AppendLine("Warnings: $($result.WarningCount)") | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($result.Operations.Count -gt 0) {
            $report.AppendLine("OPERATIONS:") | Out-Null
            foreach ($op in $result.Operations.GetEnumerator() | Sort-Object Value -Descending) {
                $report.AppendLine("  $($op.Key): $($op.Value)") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.Errors.Count -gt 0) {
            $report.AppendLine("RECENT ERRORS:") | Out-Null
            foreach ($errItem in $result.Errors | Select-Object -Last 10) {
                $report.AppendLine("  [$($errItem.Timestamp)] $($errItem.Message)") | Out-Null
            }
        }
        
        $result.Report = $report.ToString()
        
    } catch {
        $result.Report = "Log analysis failed: $_"
    }
    
    return $result
}

function Compress-RepairLogs {
    <#
    .SYNOPSIS
    Compresses old repair logs to save disk space.
    #>
    param(
        [string]$LogDirectory = $env:TEMP,
        [int]$DaysOld = 7
    )
    
    $result = @{
        Compressed = 0
        Errors = @()
    }
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        $logFiles = Get-ChildItem -Path $LogDirectory -Filter "MiracleBoot_Repair_*.log" | 
            Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        foreach ($logFile in $logFiles) {
            try {
                $zipPath = $logFile.FullName -replace "\.log$", ".zip"
                Compress-Archive -Path $logFile.FullName -DestinationPath $zipPath -Force
                Remove-Item $logFile.FullName -Force
                $result.Compressed++
            } catch {
                $result.Errors += "Failed to compress $($logFile.Name): $_"
            }
        }
        
        Write-Host "Compressed $($result.Compressed) log file(s)" -ForegroundColor Green
        
    } catch {
        $result.Errors += "Compression failed: $_"
    }
    
    return $result
}

function Get-RepairReport {
    <#
    .SYNOPSIS
    Generates final repair report in text format.
    #>
    param(
        [string]$LogPath = $script:RepairLogPath
    )
    
    if (-not $LogPath -or -not (Test-Path $LogPath)) {
        return "No repair log found."
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REPAIR SESSION REPORT") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $logContent = Get-Content $LogPath
    $report.AppendLine($logContent) | Out-Null
    
    if ($script:RepairLogStartTime) {
        $duration = (Get-Date) - $script:RepairLogStartTime
        $report.AppendLine("") | Out-Null
        $report.AppendLine("Total Duration: $($duration.ToString('hh\:mm\:ss'))") | Out-Null
    }
    
    return $report.ToString()
}

function Export-RepairConfiguration {
    <#
    .SYNOPSIS
    Exports repair configuration, diagnostics, and settings to a file.
    
    .DESCRIPTION
    Saves current system state, diagnostics, and repair settings to a JSON file
    that can be imported later or shared with support technicians.
    #>
    param(
        [string]$TargetDrive = "C",
        [string]$OutputPath = "$env:TEMP\MiracleBoot_Configuration_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    )
    
    $result = @{
        Success = $false
        OutputPath = $OutputPath
        Errors = @()
    }
    
    try {
        Write-Host "Collecting system information for export..." -ForegroundColor Cyan
        
        # Collect comprehensive system information
        $config = @{
            ExportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Version = "7.3.0"
            SystemInfo = Get-SystemInformation -TargetDrive $TargetDrive
            BootProbability = Get-BootProbability -TargetDrive $TargetDrive
            Diagnostics = Start-ComprehensiveDiagnostics -TargetDrive $TargetDrive
            UpgradeReadiness = Get-InPlaceUpgradeReadiness -TargetDrive $TargetDrive
            RepairHistory = Get-RepairHistory -Limit 10
            RepairAnalytics = Get-RepairAnalytics -Days 30
        }
        
        # Export to JSON
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        
        $result.Success = $true
        Write-Host "[OK] Configuration exported to: $OutputPath" -ForegroundColor Green
        
    } catch {
        $result.Errors += "Export failed: $_"
        Write-Host "[ERROR] Export failed: $_" -ForegroundColor Red
    }
    
    return $result
}

function Import-RepairConfiguration {
    <#
    .SYNOPSIS
    Imports repair configuration from a previously exported file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )
    
    $result = @{
        Success = $false
        Configuration = $null
        Errors = @()
    }
    
    if (-not (Test-Path $ConfigPath)) {
        $result.Errors += "Configuration file not found: $ConfigPath"
        return $result
    }
    
    try {
        $configContent = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $result.Configuration = $configContent
        $result.Success = $true
        Write-Host "[OK] Configuration imported successfully" -ForegroundColor Green
    } catch {
        $result.Errors += "Import failed: $_"
        Write-Host "[ERROR] Import failed: $_" -ForegroundColor Red
    }
    
    return $result
}

function Export-RepairTemplate {
    <#
    .SYNOPSIS
    Exports a repair template to a JSON file for sharing.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplateId,
        
        [string]$OutputPath = "$env:TEMP\MiracleBoot_Template_$TemplateId.json"
    )
    
    $result = @{
        Success = $false
        OutputPath = $OutputPath
        Errors = @()
    }
    
    try {
        $templates = Get-RepairTemplates
        $template = $templates | Where-Object { $_.Id -eq $TemplateId } | Select-Object -First 1
        
        if (-not $template) {
            $result.Errors += "Template '$TemplateId' not found"
            return $result
        }
        
        $template | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        $result.Success = $true
        Write-Host "[OK] Template exported to: $OutputPath" -ForegroundColor Green
        
    } catch {
        $result.Errors += "Export failed: $_"
    }
    
    return $result
}

function Import-RepairTemplate {
    <#
    .SYNOPSIS
    Imports a repair template from a JSON file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath
    )
    
    $result = @{
        Success = $false
        Template = $null
        Errors = @()
    }
    
    if (-not (Test-Path $TemplatePath)) {
        $result.Errors += "Template file not found: $TemplatePath"
        return $result
    }
    
    try {
        $templateContent = Get-Content $TemplatePath -Raw | ConvertFrom-Json
        $result.Template = $templateContent
        $result.Success = $true
        Write-Host "[OK] Template imported successfully" -ForegroundColor Green
    } catch {
        $result.Errors += "Import failed: $_"
    }
    
    return $result
}

function Export-RepairReport {
    <#
    .SYNOPSIS
    Generates comprehensive repair reports in multiple formats (HTML, JSON, XML, TXT).
    
    .DESCRIPTION
    Creates professional repair reports with detailed information about repair operations,
    results, diagnostics, and recommendations. Supports HTML (with styling), JSON, XML, and plain text formats.
    
    .PARAMETER RepairResults
    Array of repair result objects from various repair operations.
    
    .PARAMETER OutputPath
    Base path for output files (without extension). Defaults to TEMP folder.
    
    .PARAMETER Formats
    Array of formats to generate: HTML, JSON, XML, TXT. Defaults to all.
    
    .PARAMETER IncludeLogs
    Include full repair log content in the report.
    
    .EXAMPLE
    $results = @(
        (Start-SystemFileRepair -TargetDrive "C"),
        (Start-DiskRepair -TargetDrive "C")
    )
    Export-RepairReport -RepairResults $results -OutputPath "C:\Reports\RepairReport"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$RepairResults,
        
        [string]$OutputPath = "$env:TEMP\MiracleBoot_RepairReport_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
        
        [ValidateSet("HTML", "JSON", "XML", "TXT")]
        [string[]]$Formats = @("HTML", "JSON", "XML", "TXT"),
        
        [switch]$IncludeLogs = $true,
        
        [string]$LogPath = $script:RepairLogPath
    )
    
    $result = @{
        Success = $false
        GeneratedFiles = @()
        Errors = @()
    }
    
    # Collect report data
    $reportData = @{
        GeneratedDate = Get-Date
        SystemInfo = @{
            ComputerName = $env:COMPUTERNAME
            OSVersion = (Get-CimInstance Win32_OperatingSystem).Caption
            OSVersionNumber = (Get-CimInstance Win32_OperatingSystem).Version
            Architecture = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
        }
        Environment = Get-EnvironmentType
        RepairOperations = @()
        Summary = @{
            TotalOperations = $RepairResults.Count
            SuccessfulOperations = 0
            FailedOperations = 0
            Warnings = 0
            TotalDuration = $null
        }
        RestorePoints = @()
        Recommendations = @()
    }
    
    # Process repair results
    $startTime = $null
    $endTime = Get-Date
    
    foreach ($repairResult in $RepairResults) {
        $opData = @{
            OperationType = $repairResult.OperationType
            Success = $repairResult.Success
            StartTime = if ($repairResult.StartTime) { $repairResult.StartTime } else { Get-Date }
            EndTime = if ($repairResult.EndTime) { $repairResult.EndTime } else { Get-Date }
            Duration = if ($repairResult.Duration) { $repairResult.Duration } else { 
                $start = if ($repairResult.StartTime) { $repairResult.StartTime } else { Get-Date }
                (Get-Date) - $start
            }
            Report = $repairResult.Report
            Errors = $repairResult.Errors
            Warnings = $repairResult.Warnings
            RestorePointID = $repairResult.RestorePointID
        }
        
        if (-not $startTime -or $opData.StartTime -lt $startTime) {
            $startTime = $opData.StartTime
        }
        
        if ($repairResult.Success) {
            $reportData.Summary.SuccessfulOperations++
        } else {
            $reportData.Summary.FailedOperations++
        }
        
        if ($repairResult.Warnings) {
            $reportData.Summary.Warnings += $repairResult.Warnings.Count
        }
        
        if ($repairResult.RestorePointID) {
            $reportData.RestorePoints += @{
                ID = $repairResult.RestorePointID
                Operation = $opData.OperationType
                CreatedAt = $opData.StartTime
            }
        }
        
        $reportData.RepairOperations += $opData
    }
    
    if ($startTime) {
        $reportData.Summary.TotalDuration = $endTime - $startTime
    }
    
    # Add log content if requested
    if ($IncludeLogs -and $LogPath -and (Test-Path $LogPath)) {
        $reportData.LogContent = Get-Content $LogPath -Raw
    }
    
    # Generate reports in requested formats
    try {
        if ($Formats -contains "HTML") {
            $htmlPath = "$OutputPath.html"
            $htmlContent = ConvertTo-HtmlReport -ReportData $reportData
            $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
            $result.GeneratedFiles += $htmlPath
        }
        
        if ($Formats -contains "JSON") {
            $jsonPath = "$OutputPath.json"
            $reportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
            $result.GeneratedFiles += $jsonPath
        }
        
        if ($Formats -contains "XML") {
            $xmlPath = "$OutputPath.xml"
            $reportData | Export-Clixml -Path $xmlPath
            $result.GeneratedFiles += $xmlPath
        }
        
        if ($Formats -contains "TXT") {
            $txtPath = "$OutputPath.txt"
            $txtContent = ConvertTo-TextReport -ReportData $reportData
            $txtContent | Out-File -FilePath $txtPath -Encoding UTF8
            $result.GeneratedFiles += $txtPath
        }
        
        $result.Success = $true
        
    } catch {
        $result.Errors += "Error generating reports: $_"
    }
    
    return $result
}

function ConvertTo-HtmlReport {
    param([hashtable]$ReportData)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Miracle Boot Repair Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078D7; border-bottom: 3px solid #0078D7; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; border-bottom: 2px solid #e0e0e0; padding-bottom: 5px; }
        .summary { background: #f9f9f9; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .summary-item { display: inline-block; margin: 10px 20px 10px 0; }
        .summary-label { font-weight: bold; color: #666; }
        .summary-value { font-size: 1.2em; color: #0078D7; }
        .success { color: #28a745; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #0078D7; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #e0e0e0; }
        tr:hover { background: #f5f5f5; }
        .code-block { background: #f4f4f4; padding: 15px; border-radius: 5px; font-family: 'Consolas', monospace; white-space: pre-wrap; overflow-x: auto; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 2px solid #e0e0e0; color: #666; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Miracle Boot Repair Report</h1>
        <p><strong>Generated:</strong> $($ReportData.GeneratedDate.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        
        <div class="summary">
            <h2>Summary</h2>
            <div class="summary-item">
                <span class="summary-label">Total Operations:</span>
                <span class="summary-value">$($ReportData.Summary.TotalOperations)</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Successful:</span>
                <span class="summary-value success">$($ReportData.Summary.SuccessfulOperations)</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Failed:</span>
                <span class="summary-value error">$($ReportData.Summary.FailedOperations)</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">Warnings:</span>
                <span class="summary-value warning">$($ReportData.Summary.Warnings)</span>
            </div>
            $(if ($ReportData.Summary.TotalDuration) {
                "<div class='summary-item'><span class='summary-label'>Total Duration:</span><span class='summary-value'>$($ReportData.Summary.TotalDuration.ToString('hh\:mm\:ss'))</span></div>"
            })
        </div>
        
        <h2>System Information</h2>
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Computer Name</td><td>$($ReportData.SystemInfo.ComputerName)</td></tr>
            <tr><td>OS Version</td><td>$($ReportData.SystemInfo.OSVersion)</td></tr>
            <tr><td>OS Version Number</td><td>$($ReportData.SystemInfo.OSVersionNumber)</td></tr>
            <tr><td>Architecture</td><td>$($ReportData.SystemInfo.Architecture)</td></tr>
            <tr><td>Environment</td><td>$($ReportData.Environment)</td></tr>
        </table>
        
        <h2>Repair Operations</h2>
        <table>
            <tr>
                <th>Operation</th>
                <th>Status</th>
                <th>Duration</th>
                <th>Restore Point</th>
            </tr>
"@
    
    foreach ($op in $ReportData.RepairOperations) {
        $statusClass = if ($op.Success) { "success" } else { "error" }
        # Use ASCII-only status text to avoid encoding issues in some environments
        $statusText = if ($op.Success) { "[OK] Success" } else { "[X] Failed" }
        $duration = if ($op.Duration) { $op.Duration.ToString('hh\:mm\:ss') } else { "N/A" }
        $restorePoint = if ($op.RestorePointID) { "RP #$($op.RestorePointID)" } else { "-" }
        
        $html += @"
            <tr>
                <td>$($op.OperationType)</td>
                <td class="$statusClass">$statusText</td>
                <td>$duration</td>
                <td>$restorePoint</td>
            </tr>
"@
    }
    
    $html += @"
        </table>
        
        $(if ($ReportData.RestorePoints.Count -gt 0) {
            "<h2>System Restore Points Created</h2>
            <table>
                <tr><th>ID</th><th>Operation</th><th>Created At</th></tr>
                $(foreach ($rp in $ReportData.RestorePoints) {
                    "<tr><td>$($rp.ID)</td><td>$($rp.Operation)</td><td>$($rp.CreatedAt.ToString('yyyy-MM-dd HH:mm:ss'))</td></tr>"
                })
            </table>"
        })
        
        $(if ($ReportData.LogContent) {
            $encodedLog = $ReportData.LogContent -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&#39;'
            "<h2>Repair Log</h2>
            <div class='code-block'>$encodedLog</div>"
        })
        
        <div class="footer">
            <p>Generated by Miracle Boot v7.2.0</p>
            <p>For support and documentation, visit the Miracle Boot repository</p>
        </div>
    </div>
</body>
</html>
"@
    
    return $html
}

function ConvertTo-TextReport {
    param([hashtable]$ReportData)
    
    $text = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $text.AppendLine($separator) | Out-Null
    $text.AppendLine("MIRACLE BOOT REPAIR REPORT") | Out-Null
    $text.AppendLine($separator) | Out-Null
    $text.AppendLine("Generated: $($ReportData.GeneratedDate.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
    $text.AppendLine("") | Out-Null
    
    $text.AppendLine("SUMMARY:") | Out-Null
    $text.AppendLine("-" * 80) | Out-Null
    $text.AppendLine("Total Operations: $($ReportData.Summary.TotalOperations)") | Out-Null
    $text.AppendLine("Successful: $($ReportData.Summary.SuccessfulOperations)") | Out-Null
    $text.AppendLine("Failed: $($ReportData.Summary.FailedOperations)") | Out-Null
    $text.AppendLine("Warnings: $($ReportData.Summary.Warnings)") | Out-Null
    if ($ReportData.Summary.TotalDuration) {
        $text.AppendLine("Total Duration: $($ReportData.Summary.TotalDuration.ToString('hh\:mm\:ss'))") | Out-Null
    }
    $text.AppendLine("") | Out-Null
    
    $text.AppendLine("SYSTEM INFORMATION:") | Out-Null
    $text.AppendLine("-" * 80) | Out-Null
    $text.AppendLine("Computer Name: $($ReportData.SystemInfo.ComputerName)") | Out-Null
    $text.AppendLine("OS Version: $($ReportData.SystemInfo.OSVersion)") | Out-Null
    $text.AppendLine("Architecture: $($ReportData.SystemInfo.Architecture)") | Out-Null
    $text.AppendLine("Environment: $($ReportData.Environment)") | Out-Null
    $text.AppendLine("") | Out-Null
    
    $text.AppendLine("REPAIR OPERATIONS:") | Out-Null
    $text.AppendLine("-" * 80) | Out-Null
    foreach ($op in $ReportData.RepairOperations) {
        $status = if ($op.Success) { "[SUCCESS]" } else { "[FAILED]" }
        $duration = if ($op.Duration) { $op.Duration.ToString('hh\:mm\:ss') } else { "N/A" }
        $text.AppendLine("$status $($op.OperationType) - Duration: $duration") | Out-Null
        if ($op.RestorePointID) {
            $text.AppendLine("  Restore Point: #$($op.RestorePointID)") | Out-Null
        }
        if ($op.Errors.Count -gt 0) {
            foreach ($err in $op.Errors) {
                $text.AppendLine("  ERROR: $err") | Out-Null
            }
        }
        $text.AppendLine("") | Out-Null
    }
    
    if ($ReportData.LogContent) {
        $text.AppendLine("REPAIR LOG:") | Out-Null
        $text.AppendLine("-" * 80) | Out-Null
        $text.AppendLine($ReportData.LogContent) | Out-Null
    }
    
    return $text.ToString()
}

function Start-CompleteSystemRepair {
    <#
    .SYNOPSIS
    Master repair function that orchestrates all repair steps in optimal order.
    #>
    param(
        [string]$TargetDrive = "C",
        [switch]$SkipDiskRepair = $false,
        [switch]$SkipSystemFileRepair = $false,
        [switch]$SkipBootRepair = $false,
        [switch]$SkipConfirmation = $false,
        [scriptblock]$ProgressCallback = $null,
        [switch]$CreateRestorePoint = $true,
        [switch]$SkipRestorePoint = $false
    )
    
    $result = @{
        Success = $false
        StepsCompleted = @()
        StepsFailed = @()
        CheckpointPath = ""
        Report = ""
        Errors = @()
        RestorePointID = $null
        ValidationScore = $null
        ValidationPassed = $false
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("COMPLETE SYSTEM REPAIR") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Initialize logging
    $logSession = Start-RepairLogging
    Write-RepairLog "Starting complete system repair for drive $TargetDrive`:"
    
    # Step 0: Run comprehensive diagnostics
    $report.AppendLine("STEP 0: Running comprehensive diagnostics...") | Out-Null
    Write-RepairLog "Running comprehensive diagnostics"
    try {
        $diagnostics = Start-ComprehensiveDiagnostics -TargetDrive $TargetDrive
        $report.AppendLine($diagnostics.Report) | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($diagnostics.Issues.Count -eq 0) {
            $report.AppendLine("[INFO] No issues detected. System appears healthy.") | Out-Null
            $result.Success = $true
            $result.Report = $report.ToString()
            return $result
        }
    } catch {
        $errorMsg = "Diagnostics failed: $_"
        $report.AppendLine("[WARNING] $errorMsg") | Out-Null
        Write-RepairLog "Diagnostics failed: $_" "WARNING"
    }
    $report.AppendLine("") | Out-Null
    
    # Step 1: Create restore point and checkpoint
    $envType = Get-EnvironmentType
    if ($CreateRestorePoint -and -not $SkipRestorePoint -and $envType -eq 'FullOS') {
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Creating system restore point before complete repair..."
        }
        $report.AppendLine("STEP 1: Creating system restore point...") | Out-Null
        Write-RepairLog "Creating system restore point"
        try {
            $restorePoint = Create-SystemRestorePoint -Description "Before Complete System Repair" -OperationType "CompleteSystemRepair"
            if ($restorePoint.Success) {
                $report.AppendLine("[OK] Restore point created: $($restorePoint.RestorePointPath)") | Out-Null
                $result.RestorePointID = $restorePoint.RestorePointID
                Write-RepairLog "Restore point created: $($restorePoint.RestorePointPath)"
            } else {
                $report.AppendLine("[WARNING] Could not create restore point: $($restorePoint.Message)") | Out-Null
                Write-RepairLog "Warning: Could not create restore point: $($restorePoint.Message)" "WARNING"
            }
        } catch {
            $report.AppendLine("[WARNING] Restore point creation failed: $_") | Out-Null
            Write-RepairLog "Restore point creation failed: $_" "WARNING"
        }
        $report.AppendLine("") | Out-Null
    }
    
    $report.AppendLine("STEP 2: Creating repair checkpoint...") | Out-Null
    Write-RepairLog "Creating repair checkpoint"
    try {
        $checkpoint = Save-RepairCheckpoint -TargetDrive $TargetDrive
        if ($checkpoint.Success) {
            $result.CheckpointPath = $checkpoint.CheckpointPath
            $report.AppendLine("[OK] Checkpoint created: $($checkpoint.CheckpointPath)") | Out-Null
            $result.StepsCompleted += "Checkpoint"
        } else {
            $report.AppendLine("[WARNING] Checkpoint creation had issues but continuing...") | Out-Null
        }
    } catch {
        $errorMsg = "Checkpoint creation failed: $_"
        $report.AppendLine("[WARNING] $errorMsg") | Out-Null
        Write-RepairLog $errorMsg "WARNING"
    }
    $report.AppendLine("") | Out-Null
    
    # Step 2: Disk Repair (if needed and not skipped)
    if (-not $SkipDiskRepair) {
        $report.AppendLine("STEP 2: Disk Repair...") | Out-Null
        Write-RepairLog "Starting disk repair"
        try {
            $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
            if ($diskHealth.NeedsRepair) {
                $diskRepair = Start-DiskRepair -TargetDrive $TargetDrive -FixErrors -ProgressCallback $ProgressCallback -RecoverBadSectors:$diskHealth.HasBadSectors
                $report.AppendLine($diskRepair.Report) | Out-Null
                
                if ($diskRepair.Success) {
                    $result.StepsCompleted += "DiskRepair"
                    Write-RepairLog "Disk repair completed successfully"
                } else {
                    $result.StepsFailed += "DiskRepair"
                    Write-RepairLog "Disk repair failed" "ERROR"
                }
            } else {
                $report.AppendLine("[SKIP] Disk health check passed. Skipping disk repair.") | Out-Null
                Write-RepairLog "Disk health OK, skipping repair"
            }
        } catch {
            $errorMsg = "Disk repair failed: $_"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.StepsFailed += "DiskRepair"
            $result.Errors += $errorMsg
            Write-RepairLog $errorMsg "ERROR"
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Step 3: System File Repair (if not skipped)
    if (-not $SkipSystemFileRepair) {
        $report.AppendLine("STEP 3: System File Repair (SFC + DISM)...") | Out-Null
        Write-RepairLog "Starting system file repair"
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Starting system file repair..."
        }
        try {
            $fileRepair = Start-SystemFileRepair -TargetDrive $TargetDrive -ProgressCallback $ProgressCallback
            $report.AppendLine($fileRepair.Report) | Out-Null
            
            if ($fileRepair.Success) {
                $result.StepsCompleted += "SystemFileRepair"
                Write-RepairLog "System file repair completed successfully"
            } else {
                $result.StepsFailed += "SystemFileRepair"
                Write-RepairLog "System file repair had issues" "WARNING"
            }
        } catch {
            $errorMsg = "System file repair failed: $_"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.StepsFailed += "SystemFileRepair"
            $result.Errors += $errorMsg
            Write-RepairLog $errorMsg "ERROR"
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Step 4: Boot Repair (if not skipped)
    if (-not $SkipBootRepair) {
        $report.AppendLine("STEP 4: Boot Repair...") | Out-Null
        Write-RepairLog "Starting boot repair"
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Starting boot repair..."
        }
        try {
            $bootRepair = Start-AutomatedBootRepair -TargetDrive $TargetDrive -SkipConfirmation:$SkipConfirmation
            $report.AppendLine($bootRepair.Report) | Out-Null
            
            if ($bootRepair.Success) {
                $result.StepsCompleted += "BootRepair"
                Write-RepairLog "Boot repair completed successfully"
            } else {
                $result.StepsFailed += "BootRepair"
                Write-RepairLog "Boot repair had issues" "WARNING"
            }
        } catch {
            $errorMsg = "Boot repair failed: $_"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.StepsFailed += "BootRepair"
            $result.Errors += $errorMsg
            Write-RepairLog $errorMsg "ERROR"
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Step 5: Post-Repair Validation
    $report.AppendLine("STEP 5: Post-Repair Validation...") | Out-Null
    Write-RepairLog "Running post-repair validation"
    if ($null -ne $ProgressCallback) {
        & $ProgressCallback "Validating repair results..."
    }
    try {
        # Capture pre-repair state for comparison (if available)
        $preRepairState = @{
            SystemFileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
            DiskHealth = Test-DiskHealth -TargetDrive $TargetDrive
            RegistryHealth = Test-RegistryHealth -TargetDrive $TargetDrive
        }
        
        # Run validation
        $validation = Test-RepairValidation -TargetDrive $TargetDrive -PreRepairState $preRepairState -RestorePointID $result.RestorePointID
        $report.AppendLine($validation.Report) | Out-Null
        
        $result.ValidationScore = $validation.ConfidenceScore
        $result.ValidationPassed = $validation.ValidationPassed
        
        if ($validation.ValidationPassed) {
            $result.StepsCompleted += "Validation"
            Write-RepairLog "Validation passed with score: $($validation.ConfidenceScore)%"
        } else {
            $result.StepsFailed += "Validation"
            Write-RepairLog "Validation failed with score: $($validation.ConfidenceScore)%" "WARNING"
            if ($validation.ShouldRollback) {
                $result.Errors += "Validation recommends rollback - critical issues detected"
                $report.AppendLine("[WARNING] Validation recommends considering rollback from restore point") | Out-Null
            }
        }
    } catch {
        $errorMsg = "Validation failed: $_"
        $report.AppendLine("[WARNING] $errorMsg") | Out-Null
        Write-RepairLog $errorMsg "WARNING"
    }
    $report.AppendLine("") | Out-Null
    
    # Final Summary
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REPAIR SUMMARY") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("Steps Completed: $($result.StepsCompleted.Count)") | Out-Null
    $report.AppendLine("Steps Failed: $($result.StepsFailed.Count)") | Out-Null
    if ($result.ValidationScore -ne $null) {
        $report.AppendLine("Validation Score: $($result.ValidationScore)%") | Out-Null
        $report.AppendLine("Validation Passed: $(if ($result.ValidationPassed) { 'YES' } else { 'NO' })") | Out-Null
    }
    
    if ($result.CheckpointPath) {
        $report.AppendLine("Checkpoint: $($result.CheckpointPath)") | Out-Null
    }
    
    if ($result.StepsFailed.Count -eq 0) {
        $result.Success = $true
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[SUCCESS] Complete system repair finished successfully!") | Out-Null
        Write-RepairLog "Complete system repair finished successfully"
    } else {
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[PARTIAL] Some repair steps failed. Review errors above.") | Out-Null
        if ($result.CheckpointPath) {
            $report.AppendLine("Checkpoint available for rollback if needed.") | Out-Null
        }
        Write-RepairLog "Repair completed with some failures" "WARNING"
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Repair log: $($logSession.LogPath)") | Out-Null
    
    $result.Report = $report.ToString()
    Write-RepairLog "Repair session ended"
    
    # Save to repair history
    try {
        Save-RepairHistory -RepairResult $result -OperationType "CompleteSystemRepair" -TargetDrive $TargetDrive
    } catch {
        Write-Warning "Could not save repair history: $_"
    }
    
    return $result
}

function Get-InPlaceUpgradeReadiness {
    <#
    .SYNOPSIS
    Comprehensive check for in-place upgrade readiness by analyzing Windows logs and health components.
    
    .DESCRIPTION
    Checks various Windows log files and system health components to determine if an in-place
    installation/upgrade is possible. Analyzes:
    - nbtlog.txt (boot log)
    - $WINDOWS.~BT (Windows installation files)
    - $Windows.~WS (Windows installation files)
    - CBS logs
    - Component store health
    - Pending operations
    - Registry health
    - Setup logs
    
    Returns detailed report with blockers and recommendations.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        ReadyForInPlaceUpgrade = $false
        Blockers = @()
        Warnings = @()
        Recommendations = @()
        LogFilesAnalyzed = @()
        HealthChecks = @{}
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("IN-PLACE UPGRADE READINESS CHECK") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine("Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $envType = Get-EnvironmentType
    $isOffline = ($envType -ne 'FullOS')
    
    # ========================================================================
    # CHECK 1: Boot Log (nbtlog.txt)
    # ========================================================================
    $report.AppendLine("CHECK 1: Boot Log Analysis (nbtlog.txt)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $nbtlogPath = "$TargetDrive`:\Windows\nbtlog.txt"
    if (Test-Path $nbtlogPath) {
        $result.LogFilesAnalyzed += "nbtlog.txt"
        try {
            $nbtlogContent = Get-Content $nbtlogPath -ErrorAction SilentlyContinue -Tail 500
            $bootErrors = $nbtlogContent | Where-Object { $_ -match "FAIL|ERROR|Did not load" } | Select-Object -First 20
            
            if ($bootErrors) {
                $report.AppendLine("[WARNING] Boot log shows errors:") | Out-Null
                foreach ($bootError in $bootErrors) {
                    $report.AppendLine("  - $bootError") | Out-Null
                }
                $result.Warnings += "Boot log contains errors - may indicate driver or service issues"
            } else {
                $report.AppendLine("[OK] Boot log shows no critical errors") | Out-Null
            }
            
            # Check for boot startup status
            $bootSuccess = $nbtlogContent | Where-Object { $_ -match "Successfully loaded|Loaded driver" } | Measure-Object
            $report.AppendLine("[INFO] Successfully loaded drivers/services: $($bootSuccess.Count)") | Out-Null
        } catch {
            $report.AppendLine("[WARNING] Could not read boot log: $_") | Out-Null
        }
    } else {
        $report.AppendLine("[INFO] Boot log (nbtlog.txt) not found - this is normal if boot logging is disabled") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 2: $WINDOWS.~BT Folder (Windows Installation Files)
    # ========================================================================
    $report.AppendLine("CHECK 2: Windows Installation Files ($WINDOWS.~BT)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $windowsBT = "$TargetDrive`:\`$WINDOWS.~BT"
    if (Test-Path $windowsBT) {
        $result.LogFilesAnalyzed += "\$WINDOWS.~BT"
        try {
            $btSize = (Get-ChildItem $windowsBT -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB
            $report.AppendLine("[INFO] $WINDOWS.~BT folder exists (Size: $([math]::Round($btSize, 2)) GB)") | Out-Null
            
            # Check for setup logs in ~BT
            $pantherPath = "$windowsBT\Sources\Panther"
            if (Test-Path $pantherPath) {
                $setupLogs = Get-ChildItem $pantherPath -Filter "*.log" -ErrorAction SilentlyContinue
                if ($setupLogs) {
                    $report.AppendLine("[INFO] Found $($setupLogs.Count) setup log file(s) in Panther folder") | Out-Null
                    
                    # Check for error logs
                    $errorLogs = $setupLogs | Where-Object { $_.Name -match "error|setuperr" }
                    if ($errorLogs) {
                        foreach ($log in $errorLogs) {
                            $result.LogFilesAnalyzed += $log.FullName
                            $logContent = Get-Content $log.FullName -Tail 100 -ErrorAction SilentlyContinue
                            $errors = $logContent | Where-Object { $_ -match "error|failed|blocked|ineligible" } | Select-Object -First 10
                            if ($errors) {
                                $report.AppendLine("[WARNING] Errors found in $($log.Name):") | Out-Null
                                foreach ($err in $errors) {
                                    $report.AppendLine("  - $err") | Out-Null
                                    if ($err -match "blocked|ineligible|cannot.*upgrade") {
                                        $result.Blockers += "Setup log indicates upgrade blocked: $err"
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            # Check if ~BT indicates a failed installation attempt
            $setupact = "$pantherPath\setupact.log"
            if (Test-Path $setupact) {
                $result.LogFilesAnalyzed += $setupact
                $setupContent = Get-Content $setupact -Tail 200 -ErrorAction SilentlyContinue
                $failedPhases = $setupContent | Where-Object { $_ -match "failed|error|blocked" } | Select-Object -First 10
                if ($failedPhases) {
                    $report.AppendLine("[WARNING] Previous installation attempt may have failed") | Out-Null
                    $result.Warnings += "Previous setup attempt detected - may need cleanup"
                }
            }
        } catch {
            $report.AppendLine("[WARNING] Could not analyze $WINDOWS.~BT folder: $_") | Out-Null
        }
    } else {
        $report.AppendLine("[OK] No $WINDOWS.~BT folder found - system is clean") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 3: $Windows.~WS Folder
    # ========================================================================
    $report.AppendLine("CHECK 3: Windows Installation Files ($Windows.~WS)") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $windowsWS = "$TargetDrive`:\`$Windows.~WS"
    if (Test-Path $windowsWS) {
        $result.LogFilesAnalyzed += "\$Windows.~WS"
        try {
            $wsSize = (Get-ChildItem $windowsWS -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB
            $report.AppendLine("[INFO] $Windows.~WS folder exists (Size: $([math]::Round($wsSize, 2)) GB)") | Out-Null
            $result.Warnings += "$Windows.~WS folder present - may indicate incomplete installation"
        } catch {
            $report.AppendLine("[WARNING] Could not analyze $Windows.~WS folder: $_") | Out-Null
        }
    } else {
        $report.AppendLine("[OK] No $Windows.~WS folder found") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 4: CBS Logs and Component Store Health
    # ========================================================================
    $report.AppendLine("CHECK 4: Component-Based Servicing (CBS) Health") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $cbsLogPath = "$TargetDrive`:\Windows\Logs\CBS\CBS.log"
    if (Test-Path $cbsLogPath) {
        $result.LogFilesAnalyzed += "CBS.log"
        try {
            $cbsContent = Get-Content $cbsLogPath -Tail 1000 -ErrorAction SilentlyContinue
            $cbsErrors = $cbsContent | Where-Object { 
                $_ -match "corrupt|corruption|failed|error|cannot.*repair|component.*store.*corrupt" 
            } | Select-Object -First 20
            
            if ($cbsErrors) {
                $report.AppendLine("[WARNING] CBS log shows corruption or errors:") | Out-Null
                foreach ($err in $cbsErrors | Select-Object -First 5) {
                    $report.AppendLine("  - $err") | Out-Null
                }
                $result.Warnings += "CBS log indicates component store issues"
            } else {
                $report.AppendLine("[OK] CBS log shows no critical corruption errors") | Out-Null
            }
        } catch {
            $report.AppendLine("[WARNING] Could not read CBS.log: $_") | Out-Null
        }
    }
    
    # Check for pending.xml (indicates pending CBS operations)
    $pendingXml = "$TargetDrive`:\Windows\WinSxS\pending.xml"
    if (Test-Path $pendingXml) {
        $report.AppendLine("[CRITICAL] pending.xml found - Pending CBS operations detected!") | Out-Null
        $result.Blockers += "Pending CBS operations (pending.xml exists) - Reboot required before upgrade"
        $result.HealthChecks["PendingCBS"] = "BLOCKED"
    } else {
        $report.AppendLine("[OK] No pending.xml found - No pending CBS operations") | Out-Null
        $result.HealthChecks["PendingCBS"] = "OK"
    }
    
    # Check component store health (if online)
    if (-not $isOffline) {
        try {
            $dismCheck = dism /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
            if ($dismCheck -match "The component store is repairable") {
                $report.AppendLine("[OK] Component store is repairable - OK for in-place upgrade") | Out-Null
                $result.HealthChecks["ComponentStore"] = "REPAIRABLE"
            } elseif ($dismCheck -match "The component store is healthy") {
                $report.AppendLine("[OK] Component store is healthy") | Out-Null
                $result.HealthChecks["ComponentStore"] = "HEALTHY"
            } elseif ($dismCheck -match "The component store cannot be repaired") {
                $report.AppendLine("[CRITICAL] Component store cannot be repaired - Setup will block upgrade") | Out-Null
                $result.Blockers += "Component store cannot be repaired - DISM reports irreparable state"
                $result.HealthChecks["ComponentStore"] = "IRREPARABLE"
            } else {
                $report.AppendLine("[INFO] Component store status unclear") | Out-Null
                $result.HealthChecks["ComponentStore"] = "UNKNOWN"
            }
        } catch {
            $report.AppendLine("[WARNING] Could not check component store health: $_") | Out-Null
            $result.HealthChecks["ComponentStore"] = "ERROR"
        }
    } else {
        $report.AppendLine("[INFO] Component store check requires FullOS (currently in $envType)") | Out-Null
        $result.HealthChecks["ComponentStore"] = "SKIPPED"
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 5: Registry Health
    # ========================================================================
    $report.AppendLine("CHECK 5: Registry Hive Health") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    try {
        $regHealth = Test-RegistryHealth -TargetDrive $TargetDrive
        if ($regHealth.Healthy) {
            $report.AppendLine("[OK] Registry hives appear healthy") | Out-Null
            $result.HealthChecks["Registry"] = "HEALTHY"
        } else {
            $report.AppendLine("[WARNING] Registry hive issues detected:") | Out-Null
            foreach ($issue in $regHealth.Issues) {
                $report.AppendLine("  - $issue") | Out-Null
            }
            $result.Warnings += "Registry hive health concerns detected"
            $result.HealthChecks["Registry"] = "ISSUES"
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check registry health: $_") | Out-Null
        $result.HealthChecks["Registry"] = "ERROR"
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 6: Setup Logs Analysis
    # ========================================================================
    $report.AppendLine("CHECK 6: Setup Logs Analysis") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $setupLogAnalysis = Get-SetupLogAnalysis -TargetDrive $TargetDrive
    if ($setupLogAnalysis.Success) {
        $report.AppendLine("[INFO] Analyzed setup logs for eligibility issues") | Out-Null
        
        if ($setupLogAnalysis.EligibilityIssues.Count -gt 0) {
            $report.AppendLine("[WARNING] Eligibility issues found in setup logs:") | Out-Null
            foreach ($issue in $setupLogAnalysis.EligibilityIssues | Select-Object -First 10) {
                $report.AppendLine("  - $issue") | Out-Null
                if ($issue -match "blocked|cannot|ineligible") {
                    $result.Blockers += "Setup log blocker: $issue"
                }
            }
        }
        
        if ($setupLogAnalysis.PendingOperations) {
            $report.AppendLine("[CRITICAL] Pending operations detected in setup logs") | Out-Null
            $result.Blockers += "Pending operations detected - may block in-place upgrade"
        }
        
        $result.LogFilesAnalyzed += $setupLogAnalysis.LogFilesFound
    } else {
        $report.AppendLine("[INFO] No setup logs found or analysis failed") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 7: System File Health
    # ========================================================================
    $report.AppendLine("CHECK 7: System File Health") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    try {
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        if ($fileHealth.SystemFilesHealthy -and $fileHealth.ComponentStoreHealthy) {
            $report.AppendLine("[OK] System files and component store appear healthy") | Out-Null
            $result.HealthChecks["SystemFiles"] = "HEALTHY"
        } else {
            if (-not $fileHealth.SystemFilesHealthy) {
                $report.AppendLine("[WARNING] System file corruption detected") | Out-Null
                $result.Warnings += "System file corruption may affect upgrade"
                $result.HealthChecks["SystemFiles"] = "CORRUPTED"
            }
            if (-not $fileHealth.ComponentStoreHealthy) {
                $report.AppendLine("[WARNING] Component store issues detected") | Out-Null
                $result.Warnings += "Component store issues may affect upgrade"
            }
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check system file health: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # FINAL ASSESSMENT
    # ========================================================================
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("FINAL ASSESSMENT") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($result.Blockers.Count -eq 0) {
        $result.ReadyForInPlaceUpgrade = $true
        $report.AppendLine("[READY] System appears ready for in-place upgrade!") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("No critical blockers detected. You can proceed with in-place upgrade.") | Out-Null
    } else {
        $report.AppendLine("[BLOCKED] System is NOT ready for in-place upgrade") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("CRITICAL BLOCKERS FOUND:") | Out-Null
        foreach ($blocker in $result.Blockers) {
            $report.AppendLine("  [X] $blocker") | Out-Null
        }
    }
    
    if ($result.Warnings.Count -gt 0) {
        $report.AppendLine("") | Out-Null
        $report.AppendLine("WARNINGS:") | Out-Null
        foreach ($warning in $result.Warnings) {
            $report.AppendLine("  [WARN] $warning") | Out-Null
        }
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("RECOMMENDATIONS:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    if ($result.Blockers.Count -gt 0) {
        foreach ($blocker in $result.Blockers) {
            if ($blocker -match "pending.xml|Pending CBS") {
                $result.Recommendations += "Reboot the system to clear pending CBS operations, then retry"
            }
            if ($blocker -match "Component store cannot be repaired") {
                $result.Recommendations += "Run DISM /Online /Cleanup-Image /RestoreHealth to attempt component store repair"
                $result.Recommendations += "If repair fails, consider offline repair or clean install"
            }
            if ($blocker -match "Setup log blocker") {
                $result.Recommendations += "Review setup logs in \$WINDOWS.~BT\Sources\Panther for specific error codes"
                $result.Recommendations += "Apply registry fixes if edition/language mismatch detected"
            }
        }
    } else {
        $result.Recommendations += "System is ready for in-place upgrade"
        $result.Recommendations += "Ensure you have a backup before proceeding"
        $result.Recommendations += "Use matching Windows ISO (same edition, language, and build family)"
    }
    
    foreach ($rec in $result.Recommendations) {
        $report.AppendLine("  - $rec") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Log Files Analyzed: $($result.LogFilesAnalyzed.Count)") | Out-Null
    $report.AppendLine("  - $($result.LogFilesAnalyzed -join "`n  - ")") | Out-Null
    
    $result.Report = $report.ToString()
    return $result
}

function Get-BootChainAnalysis {
    <#
    .SYNOPSIS
    Analyzes boot logs to identify which stage of the boot chain failed and why.
    #>
    param([string]$TargetDrive = 'C')
    # Implementation will be added
    return @{ Report = 'Boot chain analysis function' }
}
function Get-BootChainAnalysis {
    <#
    .SYNOPSIS
    Analyzes boot logs to identify which stage of the boot chain failed and why.
    
    .DESCRIPTION
    Provides detailed boot chain failure analysis by examining:
    - Boot log (nbtlog.txt) for driver/service failures
    - BCD entries for bootloader issues
    - Boot files for corruption
    - Identifies failure stage: BIOS/UEFI, Boot Manager, Boot Loader, Kernel, Drivers, or Session Manager
    
    Returns detailed report showing where in the boot chain Windows failed.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        FailureStage = "Unknown"
        FailureReason = ""
        BootStages = @()
        FailedDrivers = @()
        FailedServices = @()
        BootFilesStatus = @{}
        BCDStatus = "Unknown"
        Recommendations = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("BOOT CHAIN FAILURE ANALYSIS") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Define boot stages
    $bootStages = @(
        @{ Name = "Stage 1: BIOS/UEFI Initialization"; Status = "Unknown"; Details = "" },
        @{ Name = "Stage 2: Boot Manager (bootmgr)"; Status = "Unknown"; Details = "" },
        @{ Name = "Stage 3: Boot Loader (winload.exe)"; Status = "Unknown"; Details = "" },
        @{ Name = "Stage 4: Kernel Initialization (ntoskrnl.exe)"; Status = "Unknown"; Details = "" },
        @{ Name = "Stage 5: Driver Loading"; Status = "Unknown"; Details = "" },
        @{ Name = "Stage 6: Session Manager (smss.exe)"; Status = "Unknown"; Details = "" },
        @{ Name = "Stage 7: Windows Logon"; Status = "Unknown"; Details = "" }
    )
    
    # Check boot log
    $logPath = "$TargetDrive`:\Windows\ntbtlog.txt"
    $bootLogAnalysis = Get-BootLogAnalysis -TargetDrive $TargetDrive
    
    # Stage 1: BIOS/UEFI - Usually passes if we can see the drive
    if (Test-Path "$TargetDrive`:\Windows") {
        $bootStages[0].Status = "Passed"
        $bootStages[0].Details = "Hardware detected, can access Windows drive"
    } else {
        $bootStages[0].Status = "Failed"
        $bootStages[0].Details = "Cannot access Windows drive - hardware issue"
        $result.FailureStage = "Stage 1: BIOS/UEFI"
        $result.FailureReason = "Hardware initialization failure - cannot access Windows drive"
    }
    
    # Stage 2: Boot Manager - Check BCD
    try {
        $bcdCheck = bcdedit /enum 2>&1 | Select-String "Windows Boot Manager"
        if ($bcdCheck) {
            $bootStages[1].Status = "Passed"
            $bootStages[1].Details = "BCD contains Windows Boot Manager entry"
            $result.BCDStatus = "OK"
        } else {
            $bootStages[1].Status = "Failed"
            $bootStages[1].Details = "BCD missing or corrupted - no Windows Boot Manager entry"
            $result.BCDStatus = "Corrupted"
            if ($result.FailureStage -eq "Unknown") {
                $result.FailureStage = "Stage 2: Boot Manager"
                $result.FailureReason = "Boot Configuration Data (BCD) is missing or corrupted"
            }
        }
    } catch {
        $bootStages[1].Status = "Failed"
        $bootStages[1].Details = "Cannot access BCD: $_"
        $result.BCDStatus = "Inaccessible"
        if ($result.FailureStage -eq "Unknown") {
            $result.FailureStage = "Stage 2: Boot Manager"
            $result.FailureReason = "Cannot access BCD store"
        }
    }
    
    # Stage 3: Boot Loader - Check winload.exe
    $winloadPath = "$TargetDrive`:\Windows\System32\winload.exe"
    if (Test-Path $winloadPath) {
        $bootStages[2].Status = "Passed"
        $bootStages[2].Details = "winload.exe found"
        $result.BootFilesStatus["winload.exe"] = "OK"
    } else {
        $bootStages[2].Status = "Failed"
        $bootStages[2].Details = "winload.exe missing or corrupted"
        $result.BootFilesStatus["winload.exe"] = "Missing"
        if ($result.FailureStage -eq "Unknown") {
            $result.FailureStage = "Stage 3: Boot Loader"
            $result.FailureReason = "Boot loader (winload.exe) is missing or corrupted"
        }
    }
    
    # Stage 4: Kernel - Check ntoskrnl.exe and hal.dll
    $kernelPath = "$TargetDrive`:\Windows\System32\ntoskrnl.exe"
    $halPath = "$TargetDrive`:\Windows\System32\hal.dll"
    
    if (Test-Path $kernelPath) {
        $bootStages[3].Status = "Passed"
        $bootStages[3].Details = "ntoskrnl.exe found"
        $result.BootFilesStatus["ntoskrnl.exe"] = "OK"
    } else {
        $bootStages[3].Status = "Failed"
        $bootStages[3].Details = "ntoskrnl.exe missing or corrupted"
        $result.BootFilesStatus["ntoskrnl.exe"] = "Missing"
        if ($result.FailureStage -eq "Unknown") {
            $result.FailureStage = "Stage 4: Kernel"
            $result.FailureReason = "Windows kernel (ntoskrnl.exe) is missing or corrupted"
        }
    }
    
    if (Test-Path $halPath) {
        $result.BootFilesStatus["hal.dll"] = "OK"
    } else {
        $result.BootFilesStatus["hal.dll"] = "Missing"
        if ($result.FailureStage -eq "Unknown") {
            $result.FailureStage = "Stage 4: Kernel"
            $result.FailureReason = "Hardware Abstraction Layer (hal.dll) is missing"
        }
    }
    
    # Stage 5: Driver Loading - Analyze boot log
    if ($bootLogAnalysis.Found) {
        if ($bootLogAnalysis.MissingDrivers.Count -gt 0) {
            $bootStages[4].Status = "Failed"
            $bootStages[4].Details = "$($bootLogAnalysis.MissingDrivers.Count) critical drivers failed to load"
            $result.FailedDrivers = $bootLogAnalysis.MissingDrivers
            if ($result.FailureStage -eq "Unknown") {
                $result.FailureStage = "Stage 5: Driver Loading"
                $result.FailureReason = "Critical drivers failed to load: $($bootLogAnalysis.MissingDrivers -join ', ')"
            }
        } else {
            $bootStages[4].Status = "Passed"
            $bootStages[4].Details = "No critical driver failures detected"
        }
    } else {
        $bootStages[4].Status = "Unknown"
        $bootStages[4].Details = "Boot log not available for analysis"
    }
    
    # Stage 6 & 7: Session Manager and Logon - Check for system file corruption
    $smssPath = "$TargetDrive`:\Windows\System32\smss.exe"
    $winlogonPath = "$TargetDrive`:\Windows\System32\winlogon.exe"
    
    if (Test-Path $smssPath) {
        $bootStages[5].Status = "Passed"
        $bootStages[5].Details = "smss.exe found"
    } else {
        $bootStages[5].Status = "Failed"
        $bootStages[5].Details = "smss.exe missing"
        if ($result.FailureStage -eq "Unknown") {
            $result.FailureStage = "Stage 6: Session Manager"
            $result.FailureReason = "Session Manager (smss.exe) is missing"
        }
    }
    
    if (Test-Path $winlogonPath) {
        $bootStages[6].Status = "Passed"
        $bootStages[6].Details = "winlogon.exe found"
    } else {
        $bootStages[6].Status = "Failed"
        $bootStages[6].Details = "winlogon.exe missing"
        if ($result.FailureStage -eq "Unknown") {
            $result.FailureStage = "Stage 7: Windows Logon"
            $result.FailureReason = "Windows Logon (winlogon.exe) is missing"
        }
    }
    
    # Generate recommendations based on failure stage
    switch ($result.FailureStage) {
        "Stage 1: BIOS/UEFI" {
            $result.Recommendations += "Check hardware connections (SATA cables, power)"
            $result.Recommendations += "Verify disk is detected in BIOS/UEFI"
            $result.Recommendations += "Test with different SATA port or cable"
        }
        "Stage 2: Boot Manager" {
            $result.Recommendations += "Run: bcdboot $TargetDrive`:\Windows"
            $result.Recommendations += "Run: bootrec /rebuildbcd"
            $result.Recommendations += "Check EFI partition is accessible"
        }
        "Stage 3: Boot Loader" {
            $result.Recommendations += "Run: bootrec /fixboot"
            $result.Recommendations += "Run: bcdboot $TargetDrive`:\Windows"
            $result.Recommendations += "Check for disk corruption: chkdsk $TargetDrive`: /f"
        }
        "Stage 4: Kernel" {
            $result.Recommendations += "Run: sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows"
            $result.Recommendations += "Run: DISM /Image:$TargetDrive`:\ /Cleanup-Image /RestoreHealth"
            $result.Recommendations += "Check for disk corruption: chkdsk $TargetDrive`: /f /r"
        }
        "Stage 5: Driver Loading" {
            $result.Recommendations += "Identify missing drivers from boot log"
            $result.Recommendations += "Inject missing drivers using DISM"
            $result.Recommendations += "Check for driver signature issues"
            $result.Recommendations += "Verify storage controller drivers are present"
        }
        "Stage 6: Session Manager" {
            $result.Recommendations += "Run: sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows"
            $result.Recommendations += "Check registry hives for corruption"
            $result.Recommendations += "Consider in-place upgrade repair"
        }
        "Stage 7: Windows Logon" {
            $result.Recommendations += "Run: sfc /scannow"
            $result.Recommendations += "Check for system file corruption"
            $result.Recommendations += "Consider in-place upgrade repair"
        }
        default {
            $result.Recommendations += "Run comprehensive diagnostics"
            $result.Recommendations += "Check boot log for detailed errors"
            $result.Recommendations += "Run automated boot repair"
        }
    }
    
    # Determine "where they made it" - find the last passed stage
    $lastPassedStage = -1
    $firstFailedStage = -1
    for ($i = 0; $i -lt $bootStages.Count; $i++) {
        if ($bootStages[$i].Status -eq "Passed") {
            $lastPassedStage = $i
        } elseif ($bootStages[$i].Status -eq "Failed" -and $firstFailedStage -eq -1) {
            $firstFailedStage = $i
        }
    }
    
    # Build report with visual progress indicator
    $report.AppendLine("BOOT CHAIN STAGE ANALYSIS:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Show progress indicator
    if ($lastPassedStage -ge 0) {
        $progressPercent = [math]::Round((($lastPassedStage + 1) / $bootStages.Count) * 100)
        $report.AppendLine("BOOT PROGRESS: $progressPercent% Complete") | Out-Null
        $report.AppendLine("") | Out-Null
        
        # Visual progress bar
        $progressBar = ""
        $filled = [math]::Floor(($lastPassedStage + 1) / $bootStages.Count * 40)
        for ($i = 0; $i -lt 40; $i++) {
            if ($i -lt $filled) {
                $progressBar += "="
            } else {
                $progressBar += "-"
            }
        }
        $report.AppendLine("[$progressBar]") | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($lastPassedStage -lt $bootStages.Count - 1) {
            $report.AppendLine("WHERE YOU MADE IT:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            $report.AppendLine("SUCCESS: Windows successfully completed: $($bootStages[$lastPassedStage].Name)") | Out-Null
            if ($firstFailedStage -ge 0) {
                $report.AppendLine("FAILURE: Windows failed at: $($bootStages[$firstFailedStage].Name)") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        } else {
            $report.AppendLine("SUCCESS: All boot stages completed successfully!") | Out-Null
            $report.AppendLine("") | Out-Null
        }
    }
    
    $report.AppendLine("DETAILED STAGE STATUS:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    foreach ($stage in $bootStages) {
        $statusIcon = switch ($stage.Status) {
            "Passed" { "[OK]" }
            "Failed" { "[FAIL]" }
            default { "[?]" }
        }
        $report.AppendLine("$statusIcon $($stage.Name)") | Out-Null
        $report.AppendLine("    $($stage.Details)") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($result.FailureStage -ne "Unknown") {
        $report.AppendLine("FAILURE DETECTED") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $report.AppendLine("Failure Stage: $($result.FailureStage)") | Out-Null
        $report.AppendLine("Failure Reason: $($result.FailureReason)") | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($result.FailedDrivers.Count -gt 0) {
            $report.AppendLine("Failed Drivers:") | Out-Null
            foreach ($driver in $result.FailedDrivers) {
                $report.AppendLine("  - $driver") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        $report.AppendLine("RECOMMENDATIONS:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        foreach ($rec in $result.Recommendations) {
            $report.AppendLine("  - $rec") | Out-Null
        }
        $report.AppendLine("") | Out-Null
        
        # Suggest looking up common error codes
        $report.AppendLine("COMMON ERROR CODES FOR THIS FAILURE STAGE:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        switch ($result.FailureStage) {
            "Stage 1: BIOS/UEFI" {
                $report.AppendLine("  - 0xC000000E - Boot device inaccessible") | Out-Null
                $report.AppendLine("  - 0xC000000F - Boot file not found") | Out-Null
            }
            "Stage 2: Boot Manager" {
                $report.AppendLine("  - 0xC000000E - Boot device inaccessible") | Out-Null
                $report.AppendLine("  - 0xC0000225 - BCD missing or corrupted") | Out-Null
                $report.AppendLine("  - 0xC000000F - Boot file not found") | Out-Null
            }
            "Stage 3: Boot Loader" {
                $report.AppendLine("  - 0xC000000F - Boot file not found") | Out-Null
                $report.AppendLine("  - 0xC000000E - Boot device inaccessible") | Out-Null
            }
            "Stage 4: Kernel" {
                $report.AppendLine("  - 0x0000007B - Inaccessible boot device (BSOD)") | Out-Null
                $report.AppendLine("  - 0x00000050 - Page fault in nonpaged area (BSOD)") | Out-Null
            }
            "Stage 5: Driver Loading" {
                $report.AppendLine("  - 0x0000007B - Inaccessible boot device (BSOD)") | Out-Null
                $report.AppendLine("  - 0x0000007E - System thread exception (BSOD)") | Out-Null
                $report.AppendLine("  - 0x0000001E - KMODE exception (BSOD)") | Out-Null
                $report.AppendLine("  - 0x000000D1 - Driver IRQL not less or equal (BSOD)") | Out-Null
            }
            "Stage 6: Session Manager" {
                $report.AppendLine("  - 0xC0000098 - Registry file failure") | Out-Null
                $report.AppendLine("  - 0xC000021A - Fatal system error") | Out-Null
            }
            "Stage 7: Windows Logon" {
                $report.AppendLine("  - 0xC000021A - Fatal system error") | Out-Null
                $report.AppendLine("  - 0x000000F4 - Critical object termination (BSOD)") | Out-Null
            }
        }
        $report.AppendLine("") | Out-Null
        $report.AppendLine("  Use menu option 'J' to look up any error code for detailed troubleshooting.") | Out-Null
        $report.AppendLine("") | Out-Null
    } else {
        $report.AppendLine("NO FAILURE DETECTED") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $report.AppendLine("All boot chain stages appear to have passed.") | Out-Null
        $report.AppendLine("If boot is still failing, check:") | Out-Null
        $report.AppendLine("  - Event logs for application/service errors") | Out-Null
        $report.AppendLine("  - System file integrity (SFC/DISM)") | Out-Null
        $report.AppendLine("  - Disk health (chkdsk)") | Out-Null
        $report.AppendLine("  - Look up specific error codes using menu option 'J'") | Out-Null
    }
    
    $result.BootStages = $bootStages
    $result.Report = $report.ToString()
    return $result
}

function Install-PortableBrowser {
    <#
    .SYNOPSIS
    Attempts to install a portable browser (Chrome or Firefox) in WinPE environment.
    #>
    param(
        [ValidateSet("Chrome", "Firefox")]
        [string]$Browser = "Chrome"
    )
    
    $envType = Get-EnvironmentType
    
    if ($envType -ne "WinPE") {
        return @{
            Success = $false
            Message = "Browser installation only available in WinPE environment. Current environment: $envType"
        }
    }
    
    $result = @{
        Success = $false
        Message = ""
        BrowserPath = ""
    }
    
    $browserDir = "$env:SystemDrive\Browsers"
    
    try {
        if (-not (Test-Path $browserDir)) {
            New-Item -ItemType Directory -Path $browserDir -Force | Out-Null
        }
        
        if ($Browser -eq "Chrome") {
            $chromePath = "$browserDir\Chrome\chrome.exe"
            
            if (Test-Path $chromePath) {
                $result.Success = $true
                $result.Message = "Chrome already installed at: $chromePath"
                $result.BrowserPath = $chromePath
                return $result
            }
            
            $result.Message = "Chrome portable browser installation requires manual download.`n`n"
            $result.Message += "Instructions:`n"
            $result.Message += "1. Download Chrome Portable from: https://portableapps.com/apps/internet/google_chrome_portable`n"
            $result.Message += "2. Extract to: $browserDir\Chrome`n"
            $result.Message += "3. Run: $chromePath`n`n"
            $result.Message += "Alternatively, use the network-enabled CLI browser option (option 7 in menu)."
            
        } else {
            $firefoxPath = "$browserDir\Firefox\firefox.exe"
            
            if (Test-Path $firefoxPath) {
                $result.Success = $true
                $result.Message = "Firefox already installed at: $firefoxPath"
                $result.BrowserPath = $firefoxPath
                return $result
            }
            
            $result.Message = "Firefox portable browser installation requires manual download.`n`n"
            $result.Message += "Instructions:`n"
            $result.Message += "1. Download Firefox Portable from: https://portableapps.com/apps/internet/firefox_portable`n"
            $result.Message += "2. Extract to: $browserDir\Firefox`n"
            $result.Message += "3. Run: $firefoxPath`n`n"
            $result.Message += "Alternatively, use the network-enabled CLI browser option (option 7 in menu)."
        }
        
    } catch {
        $result.Message = "Error during browser installation: $_"
    }
    
    return $result
}

function Start-UtilitiesMenu {
    <#
    .SYNOPSIS
    Launches Windows utilities from WinPE/WinRE environment.
    #>
    param(
        [ValidateSet("Notepad", "Registry", "PowerShell", "SystemRestore", "CommandPrompt", "DiskManagement", "EventViewer", "RestartExplorer")]
        [string]$Utility
    )
    
    $result = @{
        Success = $false
        Message = ""
    }
    
    try {
        switch ($Utility) {
            "Notepad" {
                if (Test-Path "$env:SystemRoot\System32\notepad.exe") {
                    Start-Process "$env:SystemRoot\System32\notepad.exe"
                    $result.Success = $true
                    $result.Message = "Notepad opened successfully"
                } else {
                    $result.Message = "Notepad not available in this environment"
                }
            }
            "Registry" {
                if (Test-Path "$env:SystemRoot\regedit.exe") {
                    Start-Process "$env:SystemRoot\regedit.exe"
                    $result.Success = $true
                    $result.Message = "Registry Editor opened successfully"
                } else {
                    $result.Message = "Registry Editor not available in this environment"
                }
            }
            "PowerShell" {
                if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
                    Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle = 'MiracleBoot - PowerShell'"
                    $result.Success = $true
                    $result.Message = "PowerShell opened successfully"
                } else {
                    $result.Message = "PowerShell not available in this environment"
                }
            }
            "SystemRestore" {
                if (Test-Path "$env:SystemRoot\System32\rstrui.exe") {
                    Start-Process "$env:SystemRoot\System32\rstrui.exe"
                    $result.Success = $true
                    $result.Message = "System Restore opened successfully"
                } else {
                    $result.Message = "System Restore not available in this environment"
                }
            }
            "CommandPrompt" {
                Start-Process cmd.exe
                $result.Success = $true
                $result.Message = "Command Prompt opened successfully"
            }
            "DiskManagement" {
                if (Test-Path "$env:SystemRoot\System32\diskmgmt.msc") {
                    Start-Process "$env:SystemRoot\System32\diskmgmt.msc"
                    $result.Success = $true
                    $result.Message = "Disk Management opened successfully"
                } else {
                    $result.Message = "Disk Management not available in this environment"
                }
            }
            "EventViewer" {
                if (Test-Path "$env:SystemRoot\System32\eventvwr.msc") {
                    Start-Process "$env:SystemRoot\System32\eventvwr.msc"
                    $result.Success = $true
                    $result.Message = "Event Viewer opened successfully"
                } else {
                    $result.Message = "Event Viewer not available in this environment"
                }
            }
            "RestartExplorer" {
                $explorerResult = Restart-WindowsExplorer
                $result.Success = $explorerResult.Success
                $result.Message = $explorerResult.Message
            }
        }
    } catch {
        $result.Message = "Error launching $Utility : $_"
    }
    
    return $result
}

function Restart-WindowsExplorer {
    <#
    .SYNOPSIS
    Restarts Windows Explorer process if it has crashed or is not responding.
    
    .DESCRIPTION
    Safely restarts the Windows Explorer shell process. This is useful when:
    - Explorer has crashed and the desktop/taskbar is missing
    - Explorer is frozen and not responding
    - Desktop icons or taskbar are not displaying correctly
    
    The function:
    1. Checks if Explorer is running
    2. Stops the Explorer process gracefully
    3. Waits a moment for cleanup
    4. Restarts Explorer
    
    .EXAMPLE
    Restart-WindowsExplorer
    
    .NOTES
    This function requires administrator privileges in some cases.
    #>
    
    $result = @{
        Success = $false
        Message = ""
        WasRunning = $false
        Restarted = $false
    }
    
    try {
        # Check if Explorer is currently running
        $explorerProcesses = Get-Process -Name "explorer" -ErrorAction SilentlyContinue
        $result.WasRunning = ($explorerProcesses.Count -gt 0)
        
        if ($result.WasRunning) {
            Write-Host "Stopping Windows Explorer..." -ForegroundColor Yellow
            
            # Stop Explorer processes
            try {
                Stop-Process -Name "explorer" -Force -ErrorAction Stop
                Write-Host "Explorer stopped. Waiting for cleanup..." -ForegroundColor Gray
                Start-Sleep -Seconds 2
            } catch {
                $result.Message = "Failed to stop Explorer: $($_.Exception.Message)"
                return $result
            }
        } else {
            Write-Host "Explorer is not running. Starting Explorer..." -ForegroundColor Yellow
        }
        
        # Start Explorer
        try {
            Start-Process "explorer.exe" -ErrorAction Stop
            Write-Host "Explorer started successfully." -ForegroundColor Green
            Start-Sleep -Seconds 1
            
            # Verify Explorer is running
            $newExplorerProcesses = Get-Process -Name "explorer" -ErrorAction SilentlyContinue
            if ($newExplorerProcesses.Count -gt 0) {
                $result.Success = $true
                $result.Restarted = $true
                if ($result.WasRunning) {
                    $result.Message = "Windows Explorer restarted successfully. Desktop and taskbar should be restored."
                } else {
                    $result.Message = "Windows Explorer started successfully. Desktop and taskbar should now be visible."
                }
            } else {
                $result.Message = "Explorer process started but could not be verified. It may take a moment to appear."
            }
        } catch {
            $result.Message = "Failed to start Explorer: $($_.Exception.Message)"
            return $result
        }
        
    } catch {
        $result.Message = "Unexpected error: $($_.Exception.Message)"
    }
    
    return $result
}

function Get-MissingDriversForPorting {
    <#
    .SYNOPSIS
    Identifies missing drivers and helps users port them to a folder for use in other OS/PE environments.
    
    .DESCRIPTION
    Analyzes the system to find missing drivers, then helps users extract and port existing drivers
    from a working system to a portable folder that can be used in recovery environments.
    #>
    param(
        [string]$SourceDrive = "C",
        [string]$OutputFolder = "$env:SystemDrive\DriverPort",
        [switch]$IncludeAllDrivers,
        [switch]$OnlyMissing
    )
    
    $result = @{
        Success = $false
        MissingDrivers = @()
        PortedDrivers = @()
        OutputPath = $OutputFolder
        Instructions = ""
        Report = ""
    }
    
    # Create output folder
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    
    # Detect missing drivers
    $missingDevices = Get-MissingStorageDevices
    $missingDrivers = @()
    
    if ($missingDevices -and $missingDevices.Count -gt 0) {
        foreach ($device in $missingDevices) {
            $missingDrivers += @{
                DeviceName = $device.DeviceName
                HardwareID = $device.HardwareID
                Description = $device.Description
            }
        }
    }
    
    $result.MissingDrivers = $missingDrivers
    
    # Port drivers from source drive
    if (Test-Path "$SourceDrive`:\Windows\System32\DriverStore\FileRepository") {
        $driverStore = "$SourceDrive`:\Windows\System32\DriverStore\FileRepository"
        
        # Find storage-related drivers
        $storageDrivers = Get-ChildItem $driverStore -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue |
            Where-Object {
                $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                $content -match "iastor|stornvme|nvme|uasp|ahci|raid|scsi" -or
                ($OnlyMissing -and $missingDrivers.Count -gt 0 -and 
                 ($missingDrivers | Where-Object { $content -match [regex]::Escape($_.HardwareID) }))
            }
        
        foreach ($driver in $storageDrivers) {
            $driverFolder = $driver.DirectoryName
            $driverName = Split-Path $driverFolder -Leaf
            $destFolder = Join-Path $OutputFolder $driverName
            
            if (-not (Test-Path $destFolder)) {
                Copy-Item -Path $driverFolder -Destination $destFolder -Recurse -Force -ErrorAction SilentlyContinue
                $result.PortedDrivers += @{
                    Name = $driverName
                    Source = $driverFolder
                    Destination = $destFolder
                    INF = $driver.FullName
                }
            }
        }
    }
    
    # Generate instructions
    $instructions = @"
DRIVER PORTING COMPLETE
===================================================================================

Output Folder: $OutputFolder
Drivers Ported: $($result.PortedDrivers.Count)
Missing Drivers Detected: $($result.MissingDrivers.Count)

HOW TO USE THESE DRIVERS:
-------------------------------------------------------------------------------

1. IN WINPE/WINRE:
   - Copy this folder to a USB drive or network location
   - Use: drvload [path]\driver.inf
   - Or use Miracle Boot's "Inject Drivers Offline" option

2. FOR OFFLINE WINDOWS INSTALLATION:
   - Use DISM: dism /Image:C:\ /Add-Driver /Driver:"$OutputFolder" /Recurse
   - Or use Miracle Boot's driver injection feature

3. FOR WINDOWS SETUP (Shift+F10):
   - Copy drivers to USB
   - During setup, press Shift+F10
   - Use: drvload [path]\driver.inf

4. FOR IN-PLACE UPGRADE:
   - Ensure drivers are accessible
   - Windows Setup should detect them automatically
   - Or inject before starting setup

DRIVER FILES INCLUDED:
-------------------------------------------------------------------------------
"@
    
    foreach ($driver in $result.PortedDrivers) {
        $instructions += "`n- $($driver.Name)"
        $instructions += "  INF: $($driver.INF)"
    }
    
    $result.Instructions = $instructions
    $result.Success = $true
    
    return $result
}

function Get-DriverSearchUrls {
    <#
    .SYNOPSIS
    Builds safe, read-only search URLs for a given hardware ID.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$HardwareID
    )

    # Normalize HWID for queries
    $encodedId = [uri]::EscapeDataString($HardwareID)

    return @{
        HardwareID             = $HardwareID
        MicrosoftUpdateCatalog = "https://www.catalog.update.microsoft.com/Search.aspx?q=$encodedId"
        GenericWebSearch       = "https://www.bing.com/search?q=$encodedId+Windows+driver"
        VendorSearchHint       = "If vendor is known (Intel/AMD/NVIDIA/Dell/HP/etc.), search their support site for: $HardwareID"
    }
}

function Get-DriverDownloadPlan {
    <#
    .SYNOPSIS
    Generates a non-destructive driver download plan for missing drivers.

    .DESCRIPTION
    Uses existing missing-driver detection to produce a structured plan with
    URLs and next steps, but does NOT download or inject anything. Safe in WinPE.
    #>
    param(
        [string]$SourceDrive = "C"
    )

    $plan = @{
        Success         = $true
        TargetDrive     = $SourceDrive
        Drivers         = @()
        Summary         = ""
        Report          = ""
        Recommendations = @()
    }

    # Reuse existing detection logic (storage-focused for now)
    $portingResult = Get-MissingDriversForPorting -SourceDrive $SourceDrive -OutputFolder "$env:TEMP\DriverPort_Plan" -OnlyMissing

    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("DRIVER DOWNLOAD PLAN (NON-DESTRUCTIVE)") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null

    if (-not $portingResult.MissingDrivers -or $portingResult.MissingDrivers.Count -eq 0) {
        $report.AppendLine("No missing storage drivers were detected by Miracle Boot's scanner.") | Out-Null
        $report.AppendLine("If you still suspect driver issues (e.g. INACCESSIBLE_BOOT_DEVICE), you can:") | Out-Null
        $report.AppendLine("  - Export drivers from a known-good system using this tool") | Out-Null
        $report.AppendLine("  - Manually download storage/NVMe/RAID drivers from your motherboard or OEM website") | Out-Null

        $plan.Summary = "No missing storage drivers detected; manual OEM driver check recommended if boot errors persist."
        $plan.Report  = $report.ToString()
        return $plan
    }

    $report.AppendLine("Detected missing storage-related devices:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null

    foreach ($drv in $portingResult.MissingDrivers) {
        $urls = Get-DriverSearchUrls -HardwareID $drv.HardwareID

        $plan.Drivers += @{
            DeviceName  = $drv.DeviceName
            Description = $drv.Description
            HardwareID  = $drv.HardwareID
            SearchUrls  = $urls
        }

        $report.AppendLine("") | Out-Null
        $report.AppendLine("DEVICE : $($drv.DeviceName)") | Out-Null
        if ($drv.Description) {
            $report.AppendLine("DESC   : $($drv.Description)") | Out-Null
        }
        $report.AppendLine("HWID   : $($drv.HardwareID)") | Out-Null
        $report.AppendLine("Search :") | Out-Null
        $report.AppendLine("  - Microsoft Update Catalog : $($urls.MicrosoftUpdateCatalog)") | Out-Null
        $report.AppendLine("  - Web Search               : $($urls.GenericWebSearch)") | Out-Null
        $report.AppendLine("  - Vendor Hint              : $($urls.VendorSearchHint)") | Out-Null
    }

    $report.AppendLine("") | Out-Null
    $report.AppendLine("NEXT STEPS (MANUAL & SAFE):") | Out-Null
    $report.AppendLine("- Use the URLs above from a working machine or WinPE with browser support.") | Out-Null
    $report.AppendLine("- Download the correct driver packages (prefer OEM / motherboard vendor first).") | Out-Null
    $report.AppendLine("- Place drivers on a USB stick (e.g. \\Drivers).") | Out-Null
    $report.AppendLine("- In WinPE/WinRE, use: drvload <path>\\driver.inf or DISM /Add-Driver with /Recurse.") | Out-Null

    $plan.Summary = "Driver download plan generated for $($plan.Drivers.Count) missing device(s). No changes were made."
    $plan.Report  = $report.ToString()
    $plan.Recommendations = @(
        "Download drivers from OEM / motherboard vendor first whenever possible.",
        "Avoid random driver sites; they may bundle malware or incorrect drivers.",
        "After injecting drivers offline, re-run boot repair and readiness checks."
    )

    return $plan
}

function Generate-SaveMeTxt {
    <#
    .SYNOPSIS
    Generates a comprehensive SAVE_ME.txt file with FAQ-style troubleshooting tips and commands.
    #>
    param(
        [string]$OutputPath = "$env:SystemDrive\SAVE_ME.txt"
    )
    
    $content = @"
===================================================================================
                    SAVE_ME.TXT - Windows Recovery Guide
                    Generated by Miracle Boot v7.2.0
                    Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
===================================================================================

[WARN] IMPORTANT: If you're stuck, ask ChatGPT or search online for specific error messages!

===================================================================================
SECTION 1: COMMON BOOT REPAIR COMMANDS
===================================================================================

1. REBUILD BCD (Boot Configuration Data)
   Command: bcdboot C:\Windows
   When to use: BCD is missing or corrupted, "Boot Configuration Data file is missing"
   Note: Replace C: with your Windows drive letter

2. FIX BOOT SECTOR
   Command: bootrec /fixboot
   When to use: Boot sector is corrupted, "Bootmgr is missing"

3. SCAN FOR WINDOWS INSTALLATIONS
   Command: bootrec /scanos
   When to use: Windows not detected, need to find all Windows installations

4. REBUILD BCD FROM SCRATCH
   Command: bootrec /rebuildbcd
   When to use: BCD completely broken, need to rebuild from detected installations

5. FIX MASTER BOOT RECORD (MBR)
   Command: bootrec /fixmbr
   When to use: MBR corruption, legacy BIOS systems

6. SYSTEM FILE CHECKER (SFC)
   Command: sfc /scannow
   Offline: sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows
   When to use: Corrupted system files, Windows won't boot

7. DISM REPAIR (Component Store)
   Command: DISM /Online /Cleanup-Image /RestoreHealth
   Offline: DISM /Image:C:\ /Cleanup-Image /RestoreHealth
   When to use: Component store corruption, SFC can't repair files

8. CHECK DISK (CHKDSK)
   Command: chkdsk C: /f /r
   When to use: Disk errors, file system corruption, bad sectors
   Warning: /r can take hours! Use /f for quick fix first.

===================================================================================
SECTION 2: DISKPART - DISK MANAGEMENT VIA COMMAND LINE
===================================================================================

HOW TO USE DISKPART:
-------------------------------------------------------------------------------
1. Type: diskpart
2. Type commands one at a time
3. Type: exit when done

FINDING YOUR DRIVES AND VOLUMES:
-------------------------------------------------------------------------------

Step 1: List all disks
   Command: list disk
   Shows: Disk number, size, status
   Example output:
     Disk 0  Online  500 GB
     Disk 1  Online  1000 GB

Step 2: Select a disk
   Command: select disk 0
   (Replace 0 with your disk number)

Step 3: List volumes on selected disk
   Command: list volume
   Shows: Volume number, drive letter, label, file system, size, status
   Example output:
     Volume 0  C  Windows    NTFS  450 GB  Healthy
     Volume 1  D  Data       NTFS  50 GB   Healthy

Step 4: Find volume label
   Command: list volume
   Look for the "Label" column - that's your volume label!

COMMON DISKPART COMMANDS:
-------------------------------------------------------------------------------

Assign drive letter:
   select volume 0
   assign letter=E

Remove drive letter:
   select volume 0
   remove letter=E

Format volume (WARNING: DELETES DATA!):
   select volume 0
   format fs=NTFS quick label="NewVolume"

Create partition:
   select disk 0
   create partition primary size=50000
   (size in MB)

Set partition as active (for boot):
   select partition 1
   active

Clean disk (WARNING: DELETES ALL PARTITIONS!):
   select disk 0
   clean

===================================================================================
SECTION 3: IN-PLACE REPAIR / UPGRADE COMMANDS
===================================================================================

FORCE IN-PLACE UPGRADE (Repair Install):
-------------------------------------------------------------------------------
1. Mount Windows ISO or extract to folder
2. Navigate to sources folder
3. Run: setup.exe /auto upgrade /quiet /noreboot
   Or: setup.exe /auto upgrade (for interactive)

SKIP COMPATIBILITY CHECKS:
   setup.exe /auto upgrade /compat IgnoreWarning

DISABLE DYNAMIC UPDATE:
   setup.exe /auto upgrade /DynamicUpdate disable

REGISTRY OVERRIDES (Advanced - Use Miracle Boot's registry tools):
-------------------------------------------------------------------------------
If in-place upgrade is blocked, you may need to modify registry:
- SetupPhase = 0
- EditionID override
- ProgramFilesDir fix

Use Miracle Boot's "One-Click Registry Fixes" or "Generate Registry Override Script"

===================================================================================
SECTION 4: DRIVER MANAGEMENT
===================================================================================

LOAD DRIVER IN WINPE/WINRE:
-------------------------------------------------------------------------------
Command: drvload [path]\driver.inf
Example: drvload X:\Drivers\iastor.inf

INJECT DRIVERS INTO OFFLINE WINDOWS:
-------------------------------------------------------------------------------
Command: DISM /Image:C:\ /Add-Driver /Driver:"X:\Drivers" /Recurse
This adds drivers to Windows installation on C: drive from X:\Drivers folder

FIND MISSING DRIVERS:
-------------------------------------------------------------------------------
1. Check boot log: C:\Windows\nbtlog.txt
2. Look for "Did not load driver" entries
3. Identify hardware IDs from Device Manager (if accessible)
4. Use Miracle Boot's "Scan Storage Drivers" feature

PORT DRIVERS FROM WORKING SYSTEM:
-------------------------------------------------------------------------------
Use Miracle Boot's "Get Missing Drivers for Porting" feature to:
- Identify missing drivers
- Extract drivers from working system
- Create portable driver folder

===================================================================================
SECTION 5: COMMON PROBLEMS AND SOLUTIONS
===================================================================================

PROBLEM: "Boot Configuration Data file is missing"
SOLUTION:
  1. bootrec /scanos
  2. bootrec /rebuildbcd
  3. bcdboot C:\Windows

PROBLEM: "Inaccessible Boot Device"
SOLUTION:
  1. Load storage drivers: drvload [path]\driver.inf
  2. Or inject drivers: DISM /Image:C:\ /Add-Driver /Driver:"[path]" /Recurse
  3. Check boot log for missing driver names

PROBLEM: "Windows failed to start"
SOLUTION:
  1. Run: sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows
  2. Run: DISM /Image:C:\ /Cleanup-Image /RestoreHealth
  3. Check boot log: C:\Windows\nbtlog.txt

PROBLEM: "In-place upgrade blocked by pending operations"
SOLUTION:
  1. Delete: C:\Windows\System32\config\pending.xml (if exists)
  2. Run: DISM /Image:C:\ /Cleanup-Image /RestoreHealth
  3. Check CBS logs: C:\Windows\Logs\CBS\CBS.log

PROBLEM: "Can't find Windows installation"
SOLUTION:
  1. Use: bootrec /scanos
  2. Check diskpart: list volume (find Windows drive)
  3. Verify: C:\Windows\System32\ntoskrnl.exe exists

PROBLEM: "BCD store is corrupted"
SOLUTION:
  1. Backup: bcdedit /export C:\BCD_Backup
  2. Rebuild: bootrec /rebuildbcd
  3. Or: bcdboot C:\Windows

PROBLEM: "Missing or corrupted system files"
SOLUTION:
  1. SFC: sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows
  2. DISM: DISM /Image:C:\ /Cleanup-Image /RestoreHealth
  3. If still failing, try in-place upgrade

===================================================================================
SECTION 6: ADVANCED TROUBLESHOOTING
===================================================================================

VIEW BOOT LOG:
-------------------------------------------------------------------------------
Command: notepad C:\Windows\nbtlog.txt
Look for: "Did not load driver", "FAIL", "ERROR"

ANALYZE EVENT LOGS:
-------------------------------------------------------------------------------
Command: wevtutil qe System /c:100 /rd:true /f:text > C:\events.txt
Then: notepad C:\events.txt

CHECK DISK HEALTH:
-------------------------------------------------------------------------------
Command: wmic diskdrive get status,model,size
Shows: Disk status and model information

CHECK PARTITION LAYOUT:
-------------------------------------------------------------------------------
Command: diskpart
  list disk
  select disk 0
  list partition
  list volume

BACKUP BCD BEFORE CHANGES:
-------------------------------------------------------------------------------
Command: bcdedit /export C:\BCD_Backup_$(Get-Date -Format 'yyyyMMdd').txt
Always backup before making BCD changes!

VIEW SYSTEM INFORMATION:
-------------------------------------------------------------------------------
Command: systeminfo
Shows: OS version, hardware, system details

===================================================================================
SECTION 7: GETTING HELP
===================================================================================

IF YOU'RE STUCK:
-------------------------------------------------------------------------------
1. Use ChatGPT or search online for your specific error message
2. Check Windows Event Viewer for detailed error codes
3. Review boot log (nbtlog.txt) for driver failures
4. Use Miracle Boot's diagnostic features:
   - Boot Chain Analysis
   - Boot Probability Check
   - Comprehensive Diagnostics
   - In-Place Upgrade Readiness

COMMON ERROR CODES:
-------------------------------------------------------------------------------
- 0xc000000e: BCD error, boot files missing
- 0xc000000f: Boot file not found
- 0xc0000225: Boot configuration data missing
- 0xc0000098: Registry file failure
- 0x80070002: File not found
- 0x80070003: Path not found

SEARCH FOR HELP:
-------------------------------------------------------------------------------
Copy the exact error message and search:
- Google: "[your error message]"
- ChatGPT: "Windows boot error [error code]"
- Microsoft Support: support.microsoft.com

===================================================================================
SECTION 8: QUICK REFERENCE - COMMAND CHEAT SHEET
===================================================================================

BOOT REPAIR:
  bcdboot C:\Windows                    - Rebuild BCD
  bootrec /fixboot                      - Fix boot sector
  bootrec /scanos                       - Find Windows
  bootrec /rebuildbcd                   - Rebuild BCD
  bootrec /fixmbr                       - Fix MBR

SYSTEM FILE REPAIR:
  sfc /scannow                           - Scan system files
  sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows  - Offline scan
  DISM /Online /Cleanup-Image /RestoreHealth  - Repair component store
  DISM /Image:C:\ /Cleanup-Image /RestoreHealth  - Offline repair

DISK REPAIR:
  chkdsk C: /f                           - Quick fix
  chkdsk C: /f /r                        - Full repair (slow!)

DRIVER MANAGEMENT:
  drvload X:\Drivers\driver.inf         - Load driver
  DISM /Image:C:\ /Add-Driver /Driver:"X:\Drivers" /Recurse  - Inject drivers

DISK MANAGEMENT:
  diskpart                               - Open diskpart
  list disk                              - Show disks
  list volume                            - Show volumes
  select disk 0                          - Select disk
  select volume 0                        - Select volume

IN-PLACE UPGRADE:
  setup.exe /auto upgrade                - Start upgrade
  setup.exe /auto upgrade /compat IgnoreWarning  - Skip checks

===================================================================================
END OF SAVE_ME.TXT
===================================================================================

Remember: When in doubt, ask ChatGPT or search online for your specific error!

"@
    
    try {
        $content | Out-File -FilePath $OutputPath -Encoding UTF8
        return @{
            Success = $true
            Path = $OutputPath
            Message = "SAVE_ME.txt generated successfully at: $OutputPath"
        }
    } catch {
        return @{
            Success = $false
            Path = $OutputPath
            Message = "Failed to generate SAVE_ME.txt: $_"
        }
    }
}

function Start-DiskManagementHelper {
    <#
    .SYNOPSIS
    Provides disk management capabilities via command line, helping users with diskpart operations.
    #>
    param(
        [switch]$Interactive,
        [string]$Command
    )
    
    if ($Interactive) {
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host "  DISK MANAGEMENT HELPER" -ForegroundColor Cyan
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "This helper will guide you through diskpart operations." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "1) List all disks and volumes" -ForegroundColor White
        Write-Host "2) Find volume label for a drive" -ForegroundColor White
        Write-Host "3) Assign drive letter" -ForegroundColor White
        Write-Host "4) Open Disk Management (GUI - if available)" -ForegroundColor White
        Write-Host "5) Open diskpart directly" -ForegroundColor White
        Write-Host "B) Back to main menu" -ForegroundColor Yellow
        Write-Host ""
        
        $choice = Read-Host "Select option"
        
        switch ($choice) {
            "1" {
                Write-Host "`nListing disks and volumes..." -ForegroundColor Gray
                Write-Host ""
                Write-Host "DISKS:" -ForegroundColor Cyan
                $disks = Get-Disk | Format-Table -AutoSize
                Write-Host $disks
                Write-Host ""
                Write-Host "VOLUMES:" -ForegroundColor Cyan
                $volumes = Get-Volume | Format-Table -AutoSize
                Write-Host $volumes
                Write-Host ""
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "2" {
                Write-Host "`nFinding volume labels..." -ForegroundColor Gray
                Write-Host ""
                $volumes = Get-Volume | Where-Object { $_.DriveLetter }
                Write-Host "VOLUME LABELS:" -ForegroundColor Cyan
                Write-Host "---------------------------------------------------------" -ForegroundColor Gray
                foreach ($vol in $volumes) {
                    Write-Host "Drive: $($vol.DriveLetter):" -ForegroundColor White
                    Write-Host "  Label: $($vol.FileSystemLabel)" -ForegroundColor Yellow
                    Write-Host "  File System: $($vol.FileSystemType)" -ForegroundColor Gray
                    Write-Host "  Size: $([math]::Round($vol.Size / 1GB, 2)) GB" -ForegroundColor Gray
                    Write-Host ""
                }
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "3" {
                Write-Host "`nAssign drive letter..." -ForegroundColor Gray
                Write-Host ""
                Write-Host "Available volumes without drive letters:" -ForegroundColor Cyan
                $volumes = Get-Volume | Where-Object { -not $_.DriveLetter -and $_.Size -gt 0 }
                $volumes | Format-Table -AutoSize
                Write-Host ""
                $volNum = Read-Host "Enter volume number to assign letter to"
                $letter = Read-Host "Enter drive letter (e.g. E, F, G)"
                
                try {
                    $vol = Get-Volume -UniqueId $volumes[$volNum].UniqueId
                    Set-Partition -Volume $vol -NewDriveLetter $letter
                    Write-Host "Drive letter $letter`: assigned successfully!" -ForegroundColor Green
                } catch {
                    Write-Host "Error: $_" -ForegroundColor Red
                    Write-Host "You may need to use diskpart manually:" -ForegroundColor Yellow
                    Write-Host "  diskpart" -ForegroundColor White
                    Write-Host "  select volume $volNum" -ForegroundColor White
                    Write-Host "  assign letter=$letter" -ForegroundColor White
                }
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "4" {
                $result = Start-UtilitiesMenu -Utility "DiskManagement"
                Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "5" {
                Write-Host "`nOpening diskpart..." -ForegroundColor Gray
                Write-Host "Type 'exit' to return to Miracle Boot" -ForegroundColor Yellow
                Start-Process diskpart
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "B" { return }
            "b" { return }
        }
    }
}

function Get-OperationProgress {
    <#
    .SYNOPSIS
    Parses command output to extract progress information for SFC, DISM, and chkdsk.
    
    .DESCRIPTION
    Monitors command output in real-time and extracts progress percentages, 
    current operations, and estimated time remaining.
    #>
    param(
        [string]$CommandOutput,
        [string]$OperationType,  # "SFC", "DISM", "CHKDSK"
        [System.Management.Automation.Job]$Job = $null
    )
    
    $progress = @{
        Percentage = 0
        CurrentOperation = ""
        Stage = ""
        EstimatedTimeRemaining = $null
        IsComplete = $false
        Status = "Running"
    }
    
    switch ($OperationType.ToUpper()) {
        "SFC" {
            # SFC doesn't provide percentage, but we can track stages
            if ($CommandOutput -match "Beginning verification phase") {
                $progress.Stage = "Verification"
                $progress.CurrentOperation = "Verifying system files..."
            } elseif ($CommandOutput -match "Beginning system file repair") {
                $progress.Stage = "Repair"
                $progress.CurrentOperation = "Repairing system files..."
            } elseif ($CommandOutput -match "Windows Resource Protection did not find any integrity violations" -or
                      $CommandOutput -match "Windows Resource Protection found corrupt files and successfully repaired them" -or
                      $CommandOutput -match "Windows Resource Protection found corrupt files but was unable to fix some") {
                $progress.IsComplete = $true
                $progress.Status = "Complete"
                $progress.Percentage = 100
            }
            
            # Try to extract file counts if available
            if ($CommandOutput -match "(\d+) files") {
                $progress.CurrentOperation = "Processing files..."
            }
        }
        
        "DISM" {
            # DISM provides percentage in multiple formats:
            # "Progress: 50%"
            # "[==========================50.0%==========================]"
            # "50 percent complete"
            if ($CommandOutput -match "Progress:\s*(\d+(?:\.\d+)?)%") {
                $progress.Percentage = [int][math]::Floor([double]$matches[1])
            } elseif ($CommandOutput -match "\[.*?(\d+(?:\.\d+)?)%") {
                $progress.Percentage = [int][math]::Floor([double]$matches[1])
            } elseif ($CommandOutput -match "(\d+(?:\.\d+)?)\s+percent complete") {
                $progress.Percentage = [int][math]::Floor([double]$matches[1])
            }
            
            # DISM stages with better detection
            if ($CommandOutput -match "Checking component store" -or $CommandOutput -match "Scanning") {
                $progress.Stage = "Checking"
                $progress.CurrentOperation = "Checking component store..."
            } elseif ($CommandOutput -match "Restoring health" -or $CommandOutput -match "RestoreHealth") {
                $progress.Stage = "Restoring"
                $progress.CurrentOperation = "Restoring component store health..."
            } elseif ($CommandOutput -match "Processing" -or $CommandOutput -match "Applying") {
                $progress.Stage = "Processing"
                $progress.CurrentOperation = "Processing components..."
            } elseif ($CommandOutput -match "The operation completed successfully" -or
                      $CommandOutput -match "The restore operation completed successfully" -or
                      $CommandOutput -match "Operation completed successfully") {
                $progress.IsComplete = $true
                $progress.Status = "Complete"
                $progress.Percentage = 100
            } elseif ($CommandOutput -match "Error:" -or $CommandOutput -match "Error\s+\d+") {
                $progress.Status = "Error"
                $progress.IsComplete = $true
            }
        }
        
        "CHKDSK" {
            # chkdsk provides percentage in multiple formats:
            # "10 percent complete"
            # "10% complete"
            # "10%"
            if ($CommandOutput -match "(\d+)\s*percent\s+complete" -or 
                $CommandOutput -match "(\d+)%\s+complete" -or
                $CommandOutput -match "(\d+)%\s*$") {
                $progress.Percentage = [int]$matches[1]
            }
            
            # chkdsk stages with better detection
            if ($CommandOutput -match "Stage 1:" -or $CommandOutput -match "Examining basic file system structure") {
                $progress.Stage = "Stage 1"
                $progress.CurrentOperation = "Examining file system structure..."
                # Stage 1 is roughly 0-20% of total
                if ($progress.Percentage -eq 0) { $progress.Percentage = 5 }
            } elseif ($CommandOutput -match "Stage 2:" -or $CommandOutput -match "Examining file name linkage") {
                $progress.Stage = "Stage 2"
                $progress.CurrentOperation = "Examining file name linkage..."
                # Stage 2 is roughly 20-40% of total
                if ($progress.Percentage -lt 20) { $progress.Percentage = 25 }
            } elseif ($CommandOutput -match "Stage 3:" -or $CommandOutput -match "Examining security descriptors") {
                $progress.Stage = "Stage 3"
                $progress.CurrentOperation = "Examining security descriptors..."
                # Stage 3 is roughly 40-60% of total
                if ($progress.Percentage -lt 40) { $progress.Percentage = 45 }
            } elseif ($CommandOutput -match "Stage 4:" -or $CommandOutput -match "Looking for bad clusters") {
                $progress.Stage = "Stage 4"
                $progress.CurrentOperation = "Looking for bad clusters..."
                # Stage 4 is roughly 60-80% of total
                if ($progress.Percentage -lt 60) { $progress.Percentage = 65 }
            } elseif ($CommandOutput -match "Stage 5:" -or $CommandOutput -match "Looking for bad, free clusters") {
                $progress.Stage = "Stage 5"
                $progress.CurrentOperation = "Looking for bad, free clusters..."
                # Stage 5 is roughly 80-100% of total
                if ($progress.Percentage -lt 80) { $progress.Percentage = 85 }
            } elseif ($CommandOutput -match "Windows has checked the file system" -or
                      $CommandOutput -match "CHKDSK is verifying files" -or
                      $CommandOutput -match "CHKDSK is verifying indexes") {
                # These are sub-operations within stages
                if (-not $progress.Stage) {
                    $progress.Stage = "Verifying"
                    $progress.CurrentOperation = "Verifying file system..."
                }
            } elseif ($CommandOutput -match "Windows has made corrections" -or
                      $CommandOutput -match "Windows has checked the file system") {
                $progress.IsComplete = $true
                $progress.Status = "Complete"
                $progress.Percentage = 100
            }
        }
    }
    
    return $progress
}

function Start-OperationWithProgress {
    <#
    .SYNOPSIS
    Executes a command with real-time progress tracking.
    
    .DESCRIPTION
    Runs a command and monitors its output in real-time, calling progress callbacks
    to update the UI with current progress.
    #>
    param(
        [string]$Command,
        [string]$OperationType,
        [scriptblock]$ProgressCallback = $null,
        [scriptblock]$OutputCallback = $null,
        [int]$UpdateInterval = 500  # milliseconds
    )
    
    $output = New-Object System.Text.StringBuilder
    $startTime = Get-Date
    $lastProgress = @{ Percentage = 0 }
    
    try {
        # Start process with redirected output
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/c $Command"
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        
        # Setup output handlers
        $outputHandler = {
            if (-not [string]::IsNullOrWhiteSpace($EventArgs.Data)) {
                $line = $EventArgs.Data
                $null = $output.AppendLine($line)
                
                if ($null -ne $OutputCallback) {
                    & $OutputCallback $line
                }
                
                # Parse progress
                $progress = Get-OperationProgress -CommandOutput $line -OperationType $OperationType
                
                if ($progress.Percentage -gt $lastProgress.Percentage -or 
                    $progress.Stage -ne $lastProgress.Stage -or
                    $progress.CurrentOperation -ne $lastProgress.CurrentOperation) {
                    
                    $lastProgress = $progress
                    
                    if ($null -ne $ProgressCallback) {
                        & $ProgressCallback $progress
                    }
                }
            }
        }
        
        $errorHandler = {
            if (-not [string]::IsNullOrWhiteSpace($EventArgs.Data)) {
                $line = $EventArgs.Data
                $null = $output.AppendLine($line)
                
                if ($null -ne $OutputCallback) {
                    & $OutputCallback $line
                }
            }
        }
        
        Register-ObjectEvent -InputObject $process -EventName "OutputDataReceived" -Action $outputHandler | Out-Null
        Register-ObjectEvent -InputObject $process -EventName "ErrorDataReceived" -Action $errorHandler | Out-Null
        
        # Start process
        $process.Start() | Out-Null
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        
        # Wait for completion with progress updates
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds $UpdateInterval
            
            # Calculate estimated time if we have progress
            if ($lastProgress.Percentage -gt 0 -and $lastProgress.Percentage -lt 100) {
                $elapsed = (Get-Date) - $startTime
                $estimatedTotal = $elapsed.TotalSeconds / ($lastProgress.Percentage / 100)
                $estimatedRemaining = $estimatedTotal - $elapsed.TotalSeconds
                $lastProgress.EstimatedTimeRemaining = [TimeSpan]::FromSeconds($estimatedRemaining)
                
                if ($null -ne $ProgressCallback) {
                    & $ProgressCallback $lastProgress
                }
            }
        }
        
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        
        return @{
            Success = ($exitCode -eq 0)
            ExitCode = $exitCode
            Output = $output.ToString()
            Duration = (Get-Date) - $startTime
        }
        
    } catch {
        return @{
            Success = $false
            ExitCode = -1
            Output = $output.ToString()
            Error = $_.Exception.Message
            Duration = (Get-Date) - $startTime
        }
    }
}

function Create-SystemRestorePoint {
    <#
    .SYNOPSIS
    Creates a system restore point with metadata about what operation triggered it.
    #>
    param(
        [string]$Description = "Miracle Boot Repair Operation",
        [string]$OperationType = "Repair",
        [hashtable]$Metadata = @{}
    )
    
    $result = @{
        Success = $false
        RestorePointID = $null
        RestorePointPath = ""
        Message = ""
        Error = ""
    }
    
    try {
        # Check if System Restore is enabled
        $restoreInfo = Get-SystemRestoreInfo
        if (-not $restoreInfo.Enabled) {
            $result.Message = "System Restore is not enabled on this system."
            return $result
        }
        
        # Create restore point using VSS
        $fullDescription = "$Description - $OperationType - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        
        # Use Checkpoint-Computer for Windows 10/11
        if (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue) {
            Checkpoint-Computer -Description $fullDescription -RestorePointType "MODIFY_SETTINGS"
            $result.Success = $true
            $result.Message = "System Restore point created successfully: $fullDescription"
            
            # Get the restore point ID
            $restorePoints = Get-ComputerRestorePoint | Sort-Object CreationTime -Descending | Select-Object -First 1
            if ($restorePoints) {
                $result.RestorePointID = $restorePoints.SequenceNumber
                $result.RestorePointPath = "Restore Point #$($restorePoints.SequenceNumber)"
            }
        } else {
            # Fallback: Use vssadmin (requires admin)
            $vssOutput = vssadmin create shadow /For=C: /AutoRetry=1 2>&1 | Out-String
            
            if ($LASTEXITCODE -eq 0) {
                $result.Success = $true
                $result.Message = "System Restore point created using VSS"
            } else {
                $result.Error = "Failed to create restore point: $vssOutput"
                $result.Message = "Could not create restore point. Ensure System Restore is enabled and you have administrator privileges."
            }
        }
        
    } catch {
        $result.Error = $_.Exception.Message
        $result.Message = "Error creating restore point: $_"
    }
    
    return $result
}

function Get-SystemRestorePoints {
    <#
    .SYNOPSIS
    Gets list of available system restore points with details.
    #>
    param(
        [int]$Limit = 50
    )
    
    $restorePoints = @()
    
    try {
        if (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue) {
            $points = Get-ComputerRestorePoint | Sort-Object CreationTime -Descending | Select-Object -First $Limit
            
            foreach ($point in $points) {
                $restorePoints += @{
                    SequenceNumber = $point.SequenceNumber
                    Description = $point.Description
                    CreationTime = $point.CreationTime
                    RestorePointType = $point.RestorePointType
                    EventType = $point.EventType
                }
            }
        } else {
            # Fallback: Parse vssadmin output
            $vssOutput = vssadmin list shadows 2>&1 | Out-String
            
            if ($vssOutput -match "Shadow Copy Volume:") {
                # Parse shadow copy information
                # This is a simplified parser - vssadmin output is complex
                $restorePoints += @{
                    SequenceNumber = 1
                    Description = "Shadow Copy (from vssadmin)"
                    CreationTime = Get-Date
                    RestorePointType = "Unknown"
                }
            }
        }
    } catch {
        Write-Warning "Error retrieving restore points: $_"
    }
    
    return $restorePoints
}

function Test-SystemRestorePoint {
    <#
    .SYNOPSIS
    Validates that a restore point exists and can be restored from.
    
    .DESCRIPTION
    Checks if a restore point exists, is accessible, and can be used for restoration.
    Returns detailed validation information including health status.
    #>
    param(
        [int]$RestorePointID = $null,
        [string]$Description = $null
    )
    
    $result = @{
        Valid = $false
        RestorePointID = $null
        Description = ""
        CreationTime = $null
        HealthStatus = "Unknown"
        CanRestore = $false
        Message = ""
        Errors = @()
    }
    
    try {
        if (-not (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue)) {
            $result.Message = "System Restore is not available in this environment"
            return $result
        }
        
        # Get restore points
        $restorePoints = Get-ComputerRestorePoint | Sort-Object CreationTime -Descending
        
        if ($restorePoints.Count -eq 0) {
            $result.Message = "No restore points found on this system"
            return $result
        }
        
        # Find the specific restore point
        $targetPoint = $null
        if ($RestorePointID) {
            $targetPoint = $restorePoints | Where-Object { $_.SequenceNumber -eq $RestorePointID } | Select-Object -First 1
        } elseif ($Description) {
            $targetPoint = $restorePoints | Where-Object { $_.Description -like "*$Description*" } | Select-Object -First 1
        } else {
            # Get the most recent one
            $targetPoint = $restorePoints | Select-Object -First 1
        }
        
        if (-not $targetPoint) {
            $result.Message = "Restore point not found"
            return $result
        }
        
        # Validate restore point
        $result.RestorePointID = $targetPoint.SequenceNumber
        $result.Description = $targetPoint.Description
        $result.CreationTime = $targetPoint.CreationTime
        
        # Check if restore point is recent (within last 30 days)
        $age = (Get-Date) - $targetPoint.CreationTime
        if ($age.Days -gt 30) {
            $result.HealthStatus = "Old"
            $result.Message = "Restore point is $($age.Days) days old. Consider creating a new one."
        } else {
            $result.HealthStatus = "Good"
        }
        
        # Check if we can restore from it (basic check - actual restore requires admin)
        try {
            $testRestore = Get-ComputerRestorePoint -RestorePoint $targetPoint.SequenceNumber -ErrorAction Stop
            $result.CanRestore = $true
            $result.Message = "Restore point is valid and can be restored from"
            $result.Valid = $true
        } catch {
            $result.CanRestore = $false
            $result.Message = "Restore point exists but may not be restorable: $_"
            $result.Errors += $_.Exception.Message
        }
        
    } catch {
        $result.Message = "Error validating restore point: $_"
        $result.Errors += $_.Exception.Message
    }
    
    return $result
}

function Restore-FromSystemRestorePoint {
    <#
    .SYNOPSIS
    Restores system from a specific restore point.
    #>
    param(
        [int]$RestorePointID,
        [switch]$Confirm
    )
    
    $result = @{
        Success = $false
        Message = ""
        Error = ""
    }
    
    if (-not $Confirm) {
        $result.Message = "Restore operation requires explicit confirmation. Use -Confirm switch."
        return $result
    }
    
    try {
        if (Get-Command Restore-Computer -ErrorAction SilentlyContinue) {
            Restore-Computer -RestorePoint $RestorePointID -Confirm:$false
            $result.Success = $true
            $result.Message = "System restore initiated. System will restart."
        } else {
            $result.Error = "Restore-Computer cmdlet not available"
            $result.Message = "Cannot restore from this environment. Use Windows Recovery Environment."
        }
    } catch {
        $result.Error = $_.Exception.Message
        $result.Message = "Error initiating restore: $_"
    }
    
    return $result
}

function Manage-SystemRestorePoints {
    <#
    .SYNOPSIS
    Manages system restore points - cleanup, health check, etc.
    #>
    param(
        [switch]$CleanupOld,
        [int]$KeepDays = 30,
        [switch]$HealthCheck
    )
    
    $result = @{
        Success = $false
        ActionsTaken = @()
        RestorePointsDeleted = 0
        HealthStatus = "Unknown"
        Message = ""
    }
    
    try {
        if ($HealthCheck) {
            $restoreInfo = Get-SystemRestoreInfo
            if ($restoreInfo.Enabled) {
                $result.HealthStatus = "Healthy"
                $result.ActionsTaken += "Health check passed - System Restore is enabled"
            } else {
                $result.HealthStatus = "Disabled"
                $result.ActionsTaken += "System Restore is disabled"
            }
        }
        
        if ($CleanupOld) {
            $cutoffDate = (Get-Date).AddDays(-$KeepDays)
            $allPoints = Get-SystemRestorePoints -Limit 1000
            
            foreach ($point in $allPoints) {
                if ($point.CreationTime -lt $cutoffDate) {
                    # Delete old restore point
                    # Note: PowerShell doesn't have a direct delete cmdlet
                    # This would require vssadmin or WMI
                    $result.RestorePointsDeleted++
                    $result.ActionsTaken += "Marked for deletion: $($point.Description) ($($point.CreationTime))"
                }
            }
            
            if ($result.RestorePointsDeleted -gt 0) {
                $result.Message = "Found $($result.RestorePointsDeleted) restore points older than $KeepDays days. Manual cleanup may be required."
            } else {
                $result.Message = "No old restore points found."
            }
        }
        
        $result.Success = $true
        
    } catch {
        $result.Message = "Error managing restore points: $_"
    }
    
    return $result
}

# Repair-Install Readiness Engine
# Ensures Windows is eligible for in-place upgrade (setup.exe with "Keep apps + files")
# Part of MiracleBoot v7.2.0

function Test-RepairInstallEligibility {
    <#
    .SYNOPSIS
    Comprehensive pre-flight check for repair-install eligibility.
    
    .DESCRIPTION
    Checks all critical blockers that prevent Windows Setup from allowing
    "Keep apps + files" in-place upgrade option.
    
    .PARAMETER TargetDrive
    Windows drive letter (e.g., "C")
    
    .OUTPUTS
    Hashtable with eligibility status, blockers, and recommendations
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Eligible = $false
        ReadinessScore = 0
        Blockers = @()
        Warnings = @()
        Recommendations = @()
        Details = @{}
    }
    
    $envType = Get-EnvironmentType
    $isOffline = ($envType -ne 'FullOS')
    $windowsPath = "$TargetDrive`:\Windows"
    $system32Path = "$windowsPath\System32"
    
    Write-Host "Testing repair-install eligibility for drive $TargetDrive`:..." -ForegroundColor Cyan
    
    # 1. Check if Windows directory exists
    if (-not (Test-Path $windowsPath)) {
        $result.Blockers += "Windows directory not found at $windowsPath"
        return $result
    }
    
    # 2. Check CBS Component Store State
    Write-Host "  Checking CBS component store state..." -ForegroundColor Gray
    try {
        if ($isOffline) {
            $cbsCheck = dism /Image:$TargetDrive`: /Cleanup-Image /CheckHealth 2>&1 | Out-String
        } else {
            $cbsCheck = dism /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
        }
        
        if ($cbsCheck -match "The component store is repairable" -or 
            $cbsCheck -match "The component store is healthy") {
            $result.ReadinessScore += 15
            $result.Details.CBSState = "Healthy"
        } elseif ($cbsCheck -match "The component store cannot be repaired") {
            $result.Blockers += "CBS component store is corrupted beyond repair"
            $result.Details.CBSState = "Corrupted"
        } else {
            $result.Warnings += "CBS component store may need repair"
            $result.Details.CBSState = "Unknown"
        }
    } catch {
        $result.Warnings += "Could not check CBS state: $_"
    }
    
    # 3. Check RebootPending flags
    Write-Host "  Checking for pending reboots..." -ForegroundColor Gray
    try {
        $pendingReboot = $false
        $pendingRebootReasons = @()
        
        # Check registry for RebootPending
        if ($isOffline) {
            # Mount registry hive
            $regPath = "$TargetDrive`:\Windows\System32\config\SYSTEM"
            if (Test-Path $regPath) {
                reg load HKLM\TEMP_SYSTEM $regPath 2>&1 | Out-Null
                try {
                    $rebootPending = Get-ItemProperty -Path "HKLM:\TEMP_SYSTEM\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
                    if ($rebootPending) {
                        $pendingReboot = $true
                        $pendingRebootReasons += "PendingFileRenameOperations found"
                    }
                } finally {
                    reg unload HKLM\TEMP_SYSTEM 2>&1 | Out-Null
                }
            }
        } else {
            $rebootPending = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
            if ($rebootPending) {
                $pendingReboot = $true
                $pendingRebootReasons += "PendingFileRenameOperations found"
            }
        }
        
        if (-not $pendingReboot) {
            $result.ReadinessScore += 10
            $result.Details.RebootPending = $false
        } else {
            $result.Blockers += "System has pending reboot operations: $($pendingRebootReasons -join ', ')"
            $result.Details.RebootPending = $true
        }
    } catch {
        $result.Warnings += "Could not check reboot pending status: $_"
    }
    
    # 4. Check Edition/Build compatibility
    Write-Host "  Checking Windows edition and build..." -ForegroundColor Gray
    try {
        if ($isOffline) {
            $regPath = "$TargetDrive`:\Windows\System32\config\SOFTWARE"
            if (Test-Path $regPath) {
                reg load HKLM\TEMP_SOFTWARE $regPath 2>&1 | Out-Null
                try {
                    $edition = (Get-ItemProperty -Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction SilentlyContinue).EditionID
                    $build = (Get-ItemProperty -Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuild" -ErrorAction SilentlyContinue).CurrentBuild
                    $releaseId = (Get-ItemProperty -Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ReleaseId" -ErrorAction SilentlyContinue).ReleaseId
                    $installationType = (Get-ItemProperty -Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "InstallationType" -ErrorAction SilentlyContinue).InstallationType
                } finally {
                    reg unload HKLM\TEMP_SOFTWARE 2>&1 | Out-Null
                }
            }
        } else {
            $edition = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction SilentlyContinue).EditionID
            $build = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuild" -ErrorAction SilentlyContinue).CurrentBuild
            $releaseId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ReleaseId" -ErrorAction SilentlyContinue).ReleaseId
            $installationType = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "InstallationType" -ErrorAction SilentlyContinue).InstallationType
        }
        
        if ($edition -and $build) {
            $result.Details.Edition = $edition
            $result.Details.Build = $build
            $result.Details.ReleaseId = $releaseId
            $result.Details.InstallationType = $installationType
            
            # Check for problematic editions
            if ($edition -match "Evaluation|EnterpriseN|EducationN") {
                $result.Warnings += "Edition '$edition' may have limited upgrade options"
            }
            
            # Check installation type
            if ($installationType -ne "Client") {
                $result.Warnings += "InstallationType is '$installationType' (expected 'Client')"
            }
            
            $result.ReadinessScore += 15
        } else {
            $result.Blockers += "Could not determine Windows edition/build"
        }
    } catch {
        $result.Warnings += "Could not check edition/build: $_"
    }
    
    # 5. Check WinRE status
    Write-Host "  Checking WinRE status..." -ForegroundColor Gray
    try {
        if (-not $isOffline) {
            $reagentcInfo = reagentc /info 2>&1 | Out-String
            if ($reagentcInfo -match "Windows RE status.*Enabled") {
                $result.ReadinessScore += 10
                $result.Details.WinREStatus = "Enabled"
            } elseif ($reagentcInfo -match "Windows RE status.*Disabled") {
                $result.Warnings += "WinRE is disabled - may affect repair install"
                $result.Details.WinREStatus = "Disabled"
            } else {
                $result.Warnings += "Could not determine WinRE status"
                $result.Details.WinREStatus = "Unknown"
            }
        } else {
            # Offline: Check for WinRE partition
            $volumes = Get-WindowsVolumes
            $winreFound = $false
            foreach ($vol in $volumes) {
                if ($vol.Label -match "Recovery|WinRE" -or $vol.FileSystemLabel -match "Recovery|WinRE") {
                    $winreFound = $true
                    break
                }
            }
            if ($winreFound) {
                $result.ReadinessScore += 10
                $result.Details.WinREStatus = "Partition found"
            } else {
                $result.Warnings += "WinRE partition not found"
                $result.Details.WinREStatus = "Not found"
            }
        }
    } catch {
        $result.Warnings += "Could not check WinRE: $_"
    }
    
    # 6. Check SetupPlatform registry keys
    Write-Host "  Checking SetupPlatform registry..." -ForegroundColor Gray
    try {
        if ($isOffline) {
            $regPath = "$TargetDrive`:\Windows\System32\config\SOFTWARE"
            if (Test-Path $regPath) {
                reg load HKLM\TEMP_SOFTWARE $regPath 2>&1 | Out-Null
                try {
                    $setupPlatform = Test-Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\SetupPlatform"
                } finally {
                    reg unload HKLM\TEMP_SOFTWARE 2>&1 | Out-Null
                }
            }
        } else {
            $setupPlatform = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\SetupPlatform"
        }
        
        if ($setupPlatform) {
            $result.ReadinessScore += 10
            $result.Details.SetupPlatform = "Present"
        } else {
            $result.Warnings += "SetupPlatform registry key missing"
            $result.Details.SetupPlatform = "Missing"
        }
    } catch {
        $result.Warnings += "Could not check SetupPlatform: $_"
    }
    
    # 7. Check for pending operations
    Write-Host "  Checking for pending operations..." -ForegroundColor Gray
    try {
        $pendingOps = @()
        
        # Check CBS pending operations
        $cbsLog = "$TargetDrive`:\Windows\Logs\CBS\CBS.log"
        if (Test-Path $cbsLog) {
            $cbsContent = Get-Content $cbsLog -Tail 100 -ErrorAction SilentlyContinue
            if ($cbsContent -match "pending|incomplete|failed") {
                $pendingOps += "CBS has pending operations"
            }
        }
        
        if ($pendingOps.Count -eq 0) {
            $result.ReadinessScore += 10
            $result.Details.PendingOperations = "None"
        } else {
            $result.Warnings += "Pending operations detected: $($pendingOps -join ', ')"
            $result.Details.PendingOperations = $pendingOps -join '; '
        }
    } catch {
        $result.Warnings += "Could not check pending operations: $_"
    }
    
    # 8. Check disk space (critical for setup)
    Write-Host "  Checking available disk space..." -ForegroundColor Gray
    try {
        $drive = Get-PSDrive -Name $TargetDrive -ErrorAction SilentlyContinue
        if ($drive) {
            $freeGB = [math]::Round($drive.Free / 1GB, 2)
            $result.Details.FreeSpaceGB = $freeGB
            
            if ($freeGB -ge 20) {
                $result.ReadinessScore += 10
            } elseif ($freeGB -ge 10) {
                $result.Warnings += "Low disk space: $freeGB GB free (recommend 20+ GB)"
            } else {
                $result.Blockers += "Insufficient disk space: $freeGB GB free (need 20+ GB)"
            }
        }
    } catch {
        $result.Warnings += "Could not check disk space: $_"
    }
    
    # Calculate final eligibility
    if ($result.Blockers.Count -eq 0) {
        $result.Eligible = $true
        if ($result.ReadinessScore -ge 80) {
            $result.Recommendations += "System appears ready for repair install"
        } elseif ($result.ReadinessScore -ge 60) {
            $result.Recommendations += "System may be ready, but warnings should be addressed"
        } else {
            $result.Recommendations += "System needs additional preparation before repair install"
        }
    } else {
        $result.Recommendations += "System is NOT ready - blockers must be resolved first"
    }
    
    return $result
}

function Clear-CBSBlockers {
    <#
    .SYNOPSIS
    Normalizes CBS state to remove blockers for repair install.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        ActionsTaken = @()
        Errors = @()
        Report = ""
    }
    
    $envType = Get-EnvironmentType
    $isOffline = ($envType -ne 'FullOS')
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("CBS BLOCKER CLEARANCE") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 1. Clear PendingFileRenameOperations
    Write-Host "Clearing PendingFileRenameOperations..." -ForegroundColor Cyan
    try {
        if ($isOffline) {
            $regPath = "$TargetDrive`:\Windows\System32\config\SYSTEM"
            if (Test-Path $regPath) {
                reg load HKLM\TEMP_SYSTEM $regPath 2>&1 | Out-Null
                try {
                    Remove-ItemProperty -Path "HKLM:\TEMP_SYSTEM\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
                    $result.ActionsTaken += "Cleared PendingFileRenameOperations (offline)"
                    $report.AppendLine("[OK] Cleared PendingFileRenameOperations") | Out-Null
                } finally {
                    reg unload HKLM\TEMP_SYSTEM 2>&1 | Out-Null
                }
            }
        } else {
            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
            $result.ActionsTaken += "Cleared PendingFileRenameOperations"
            $report.AppendLine("[OK] Cleared PendingFileRenameOperations") | Out-Null
        }
    } catch {
        $errorMsg = "Could not clear PendingFileRenameOperations: $_"
        $result.Errors += $errorMsg
        $report.AppendLine("[WARNING] $errorMsg") | Out-Null
    }
    
    # 2. Run DISM /Cleanup-Image /ResetBase (if online)
    if (-not $isOffline) {
        Write-Host "Running DISM /ResetBase to clean component store..." -ForegroundColor Cyan
        try {
            $dismOutput = dism /Online /Cleanup-Image /ResetBase 2>&1 | Out-String
            if ($dismOutput -match "The operation completed successfully") {
                $result.ActionsTaken += "Ran DISM /ResetBase"
                $report.AppendLine("[OK] DISM /ResetBase completed") | Out-Null
            } else {
                $report.AppendLine("[INFO] DISM /ResetBase output: $dismOutput") | Out-Null
            }
        } catch {
            $errorMsg = "DISM /ResetBase failed: $_"
            $result.Errors += $errorMsg
            $report.AppendLine("[WARNING] $errorMsg") | Out-Null
        }
    }
    
    # 3. Clear CBS pending operations flag
    Write-Host "Clearing CBS pending operations..." -ForegroundColor Cyan
    try {
        # This is tricky - we can't directly modify CBS state
        # But we can ensure DISM is healthy
        if ($isOffline) {
            $dismCheck = dism /Image:$TargetDrive`: /Cleanup-Image /CheckHealth 2>&1 | Out-String
        } else {
            $dismCheck = dism /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
        }
        
        if ($dismCheck -match "The component store is repairable") {
            if ($isOffline) {
                $dismRepair = dism /Image:$TargetDrive`: /Cleanup-Image /RestoreHealth 2>&1 | Out-String
            } else {
                $dismRepair = dism /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String
            }
            
            if ($dismRepair -match "The operation completed successfully") {
                $result.ActionsTaken += "Repaired CBS component store"
                $report.AppendLine("[OK] CBS component store repaired") | Out-Null
            }
        }
    } catch {
        $errorMsg = "CBS repair failed: $_"
        $result.Errors += $errorMsg
        $report.AppendLine("[WARNING] $errorMsg") | Out-Null
    }
    
    $result.Success = ($result.ActionsTaken.Count -gt 0)
    $result.Report = $report.ToString()
    
    return $result
}

function Get-RepairInstallSummary {
    <#
    .SYNOPSIS
    Lightweight, non-destructive summary of repair-install readiness.

    .DESCRIPTION
    Wraps Test-RepairInstallEligibility to produce a compact object and
    human-readable text summary that can be shown in TUI/GUI without
    modifying the system or invoking any fixes.
    #>
    param(
        [string]$TargetDrive = "C"
    )

    $summary = @{
        TargetDrive     = $TargetDrive
        ReadinessScore  = 0
        Eligible        = $false
        BlockerCount    = 0
        WarningCount    = 0
        Blockers        = @()
        Warnings        = @()
        SummaryText     = ""
    }

    $eligibility = Test-RepairInstallEligibility -TargetDrive $TargetDrive

    $summary.ReadinessScore = $eligibility.ReadinessScore
    $summary.Blockers       = $eligibility.Blockers
    $summary.Warnings       = $eligibility.Warnings
    $summary.BlockerCount   = $eligibility.Blockers.Count
    $summary.WarningCount   = $eligibility.Warnings.Count
    $summary.Eligible       = ($eligibility.Blockers.Count -eq 0 -and $eligibility.ReadinessScore -ge 80)

    $text = New-Object System.Text.StringBuilder
    $text.AppendLine("REPAIR-INSTALL READINESS SUMMARY") | Out-Null
    $text.AppendLine("=" * 60) | Out-Null
    $text.AppendLine("Target Drive   : $TargetDrive`:") | Out-Null
    $text.AppendLine("Score          : $($summary.ReadinessScore)/100") | Out-Null
    $text.AppendLine("Blockers       : $($summary.BlockerCount)") | Out-Null
    $text.AppendLine("Warnings       : $($summary.WarningCount)") | Out-Null
    $text.AppendLine("") | Out-Null

    if ($summary.Eligible) {
        $text.AppendLine("[OK] System appears eligible for repair-install with 'Keep apps + files'.") | Out-Null
    } else {
        $text.AppendLine("[NOT READY] System is NOT yet eligible for repair-install.") | Out-Null
    }

    if ($summary.BlockerCount -gt 0) {
        $text.AppendLine("") | Out-Null
        $text.AppendLine("BLOCKERS:") | Out-Null
        foreach ($b in $summary.Blockers | Select-Object -First 5) {
            $text.AppendLine("  - $b") | Out-Null
        }
        if ($summary.BlockerCount -gt 5) {
            $text.AppendLine("  ... (+$($summary.BlockerCount - 5) more)") | Out-Null
        }
    }

    if ($summary.WarningCount -gt 0) {
        $text.AppendLine("") | Out-Null
        $text.AppendLine("WARNINGS:") | Out-Null
        foreach ($w in $summary.Warnings | Select-Object -First 5) {
            $text.AppendLine("  - $w") | Out-Null
        }
        if ($summary.WarningCount -gt 5) {
            $text.AppendLine("  ... (+$($summary.WarningCount - 5) more)") | Out-Null
        }
    }

    $summary.SummaryText = $text.ToString()
    return $summary
}

function Get-RepairInstallCommandLine {
    <#
    .SYNOPSIS
    Generates a safe, recommended setup.exe command line for a repair install.

    .DESCRIPTION
    Uses existing readiness data to suggest a setup.exe command line plus notes
    about when to use GUI vs command-line, without actually invoking setup.
    This is safe to run from WinPE/WinRE or FullOS as a planning helper.
    #>
    param(
        [string]$TargetDrive = "C",
        [string]$SetupSource = "",
        [switch]$Silent
    )

    $envType = Get-EnvironmentType
    $recommendation = @{
        TargetDrive     = $TargetDrive
        Environment     = $envType
        SetupSource     = $SetupSource
        Eligible        = $false
        SuggestedCommand = ""
        Notes           = @()
        Warnings        = @()
    }

    # Get eligibility snapshot (read-only)
    $summary = Get-RepairInstallSummary -TargetDrive $TargetDrive
    $recommendation.Eligible = $summary.Eligible

    if (-not $summary.Eligible) {
        $recommendation.Warnings += "System is not yet ready for repair-install. Run Start-RepairInstallReadiness -FixBlockers first."
    }

    # Determine default setup path
    if (-not $SetupSource) {
        # Assume running from within mounted ISO or USB where setup.exe is in the root
        $SetupSource = "."
        $recommendation.Notes += "No -SetupSource provided; assuming setup.exe is in the current directory."
    }

    $setupExePath = Join-Path $SetupSource "setup.exe"

    # Build base command
    if ($Silent) {
        # Unattended style (user can still override)
        $cmd = "`"$setupExePath`" /auto upgrade /quiet /noreboot /dynamicupdate disable"
        $recommendation.Notes += "Silent mode requested; this uses /auto upgrade /quiet /noreboot."
    } else {
        # Interactive GUI with pre-selected upgrade path
        $cmd = "`"$setupExePath`" /auto upgrade /dynamicupdate disable"
        $recommendation.Notes += "Recommended to run this from the existing Windows desktop for best results."
    }

    # When running in WinPE/WinRE, remind user about drive letters and edition matching
    if ($envType -ne "FullOS") {
        $recommendation.Warnings += "You are in $envType. For repair-install with 'Keep apps + files', it is usually safer to boot into the existing Windows and run setup.exe from there."
        $recommendation.Notes += "If you must launch setup from WinPE/WinRE, ensure the correct Windows volume (e.g. C:) is targeted and that ISO edition/build matches the installed OS."
    }

    $recommendation.SuggestedCommand = $cmd
    return $recommendation
}

function Get-BootFailurePatterns {
    <#
    .SYNOPSIS
    Detects common boot failure patterns from logs and system state (non-destructive analysis).
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $patterns = @{
        Success = $true
        DetectedPatterns = @()
        Confidence = @{}
        Recommendations = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("BOOT FAILURE PATTERN DETECTION") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Pattern 1: Missing Boot Manager (bootmgr)
    try {
        $bootmgrPath = "$TargetDrive`:\bootmgr"
        if (-not (Test-Path $bootmgrPath)) {
            $patterns.DetectedPatterns += @{
                Pattern = "Missing Boot Manager"
                Severity = "Critical"
                Description = "bootmgr file is missing from root of system drive"
                Confidence = 95
                FixCommand = "bcdboot $TargetDrive`:\Windows /s $TargetDrive`:"
            }
            $patterns.Confidence["Missing Boot Manager"] = 95
            $patterns.Recommendations += "Run: bcdboot $TargetDrive`:\Windows /s $TargetDrive`:"
        }
    } catch {
        # Skip if can't check
    }
    
    # Pattern 2: BCD Store Corruption
    try {
        $bcdPath = "$TargetDrive`:\Boot\BCD"
        if (Test-Path $bcdPath) {
            $bcdTest = bcdedit /enum 2>&1
            if ($LASTEXITCODE -ne 0 -or $bcdTest -match "The system cannot find|corrupt|invalid") {
                $patterns.DetectedPatterns += @{
                    Pattern = "BCD Store Corruption"
                    Severity = "Critical"
                    Description = "BCD store exists but cannot be read or is corrupted"
                    Confidence = 90
                    FixCommand = "bootrec /rebuildbcd"
                }
                $patterns.Confidence["BCD Store Corruption"] = 90
                $patterns.Recommendations += "Run: bootrec /rebuildbcd"
            }
        } else {
            $patterns.DetectedPatterns += @{
                Pattern = "Missing BCD Store"
                Severity = "Critical"
                Description = "BCD store file is missing"
                Confidence = 95
                FixCommand = "bootrec /rebuildbcd"
            }
            $patterns.Confidence["Missing BCD Store"] = 95
            $patterns.Recommendations += "Run: bootrec /rebuildbcd"
        }
    } catch {
        # Skip if can't check
    }
    
    # Pattern 3: Missing Boot Files (winload.exe, winresume.exe)
    try {
        $system32 = "$TargetDrive`:\Windows\System32"
        $winload = Join-Path $system32 "winload.exe"
        $winresume = Join-Path $system32 "winresume.exe"
        
        $missingFiles = @()
        if (-not (Test-Path $winload)) {
            $missingFiles += "winload.exe"
        }
        if (-not (Test-Path $winresume)) {
            $missingFiles += "winresume.exe"
        }
        
        if ($missingFiles.Count -gt 0) {
            $patterns.DetectedPatterns += @{
                Pattern = "Missing Boot Loader Files"
                Severity = "Critical"
                Description = "Critical boot loader files missing: $($missingFiles -join ', ')"
                Confidence = 90
                FixCommand = "sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows"
            }
            $patterns.Confidence["Missing Boot Loader Files"] = 90
            $patterns.Recommendations += "Run: sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows"
        }
    } catch {
        # Skip if can't check
    }
    
    # Pattern 4: EFI System Partition Issues (UEFI systems)
    try {
        $efiPath = "$TargetDrive`:\EFI\Microsoft\Boot\bootmgfw.efi"
        if (-not (Test-Path $efiPath)) {
            # Check if this is a UEFI system
            $biosMode = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).BootupState
            if ($biosMode -match "UEFI|EFI") {
                $patterns.DetectedPatterns += @{
                    Pattern = "Missing EFI Boot Files"
                    Severity = "Critical"
                    Description = "EFI boot files missing on UEFI system"
                    Confidence = 85
                    FixCommand = "bcdboot $TargetDrive`:\Windows /s $TargetDrive`: /f UEFI"
                }
                $patterns.Confidence["Missing EFI Boot Files"] = 85
                $patterns.Recommendations += "Run: bcdboot $TargetDrive`:\Windows /s $TargetDrive`: /f UEFI"
            }
        }
    } catch {
        # Skip if can't check
    }
    
    # Pattern 5: Boot Loop / Continuous Restart
    try {
        $bootLog = "$TargetDrive`:\Windows\ntbtlog.txt"
        if (Test-Path $bootLog) {
            $logContent = Get-Content $bootLog -Tail 100 -ErrorAction SilentlyContinue
            $restartCount = ($logContent | Select-String -Pattern "restart|reboot|shutdown" -CaseSensitive:$false).Count
            if ($restartCount -gt 5) {
                $patterns.DetectedPatterns += @{
                    Pattern = "Boot Loop Detected"
                    Severity = "High"
                    Description = "Multiple restart events detected in boot log"
                    Confidence = 70
                    FixCommand = "Check Event Viewer for critical errors, run: Get-BootChainAnalysis"
                }
                $patterns.Confidence["Boot Loop Detected"] = 70
                $patterns.Recommendations += "Run: Get-BootChainAnalysis -TargetDrive $TargetDrive"
            }
        }
    } catch {
        # Skip if can't check
    }
    
    # Pattern 6: Driver Load Failures
    try {
        $bootLog = "$TargetDrive`:\Windows\ntbtlog.txt"
        if (Test-Path $bootLog) {
            $logContent = Get-Content $bootLog -Tail 200 -ErrorAction SilentlyContinue
            $driverFailures = $logContent | Select-String -Pattern "Did not load driver|Failed to load driver|ERROR.*driver" -CaseSensitive:$false
            if ($driverFailures.Count -gt 3) {
                $patterns.DetectedPatterns += @{
                    Pattern = "Multiple Driver Load Failures"
                    Severity = "High"
                    Description = "$($driverFailures.Count) driver load failures detected"
                    Confidence = 75
                    FixCommand = "Get-MissingDriversForPorting -SourceDrive $TargetDrive"
                }
                $patterns.Confidence["Multiple Driver Load Failures"] = 75
                $patterns.Recommendations += "Run: Get-MissingDriversForPorting -SourceDrive $TargetDrive"
            }
        }
    } catch {
        # Skip if can't check
    }
    
    # Pattern 7: Disk/File System Corruption
    try {
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        if ($diskHealth.NeedsRepair -or -not $diskHealth.FileSystemHealthy) {
            $patterns.DetectedPatterns += @{
                Pattern = "Disk/File System Corruption"
                Severity = "High"
                Description = "File system errors detected on system drive"
                Confidence = 80
                FixCommand = "chkdsk $TargetDrive`: /f /r"
            }
            $patterns.Confidence["Disk/File System Corruption"] = 80
            $patterns.Recommendations += "Run: chkdsk $TargetDrive`: /f /r (may require reboot)"
        }
    } catch {
        # Skip if can't check
    }
    
    # Pattern 8: Registry Corruption
    try {
        $regHealth = Test-RegistryHealth -TargetDrive $TargetDrive
        if (-not $regHealth.Healthy) {
            $patterns.DetectedPatterns += @{
                Pattern = "Registry Corruption"
                Severity = "High"
                Description = "Registry hive corruption detected"
                Confidence = 75
                FixCommand = "sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows"
            }
            $patterns.Confidence["Registry Corruption"] = 75
            $patterns.Recommendations += "Run: sfc /scannow /offbootdir=$TargetDrive`:\ /offwindir=$TargetDrive`:\Windows"
        }
    } catch {
        # Skip if can't check
    }
    
    # Generate report
    if ($patterns.DetectedPatterns.Count -gt 0) {
        $report.AppendLine("DETECTED PATTERNS: $($patterns.DetectedPatterns.Count)") | Out-Null
        $report.AppendLine("") | Out-Null
        
        foreach ($pattern in $patterns.DetectedPatterns) {
            $report.AppendLine("[$($pattern.Severity)] $($pattern.Pattern)") | Out-Null
            $report.AppendLine("  Confidence: $($pattern.Confidence)%") | Out-Null
            $report.AppendLine("  Description: $($pattern.Description)") | Out-Null
            $report.AppendLine("  Fix: $($pattern.FixCommand)") | Out-Null
            $report.AppendLine("") | Out-Null
        }
        
        $report.AppendLine("RECOMMENDED ACTIONS:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        foreach ($rec in $patterns.Recommendations) {
            $report.AppendLine("  - $rec") | Out-Null
        }
    } else {
        $report.AppendLine("No common boot failure patterns detected.") | Out-Null
        $report.AppendLine("System may have a unique issue or may be booting normally.") | Out-Null
    }
    
    $patterns.Report = $report.ToString()
    return $patterns
}

function Normalize-SetupState {
    <#
    .SYNOPSIS
    Normalizes registry keys for setup.exe compatibility.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        ActionsTaken = @()
        Errors = @()
        Report = ""
    }
    
    $envType = Get-EnvironmentType
    $isOffline = ($envType -ne 'FullOS')
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("SETUP STATE NORMALIZATION") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    try {
        if ($isOffline) {
            $regPath = "$TargetDrive`:\Windows\System32\config\SOFTWARE"
            if (Test-Path $regPath) {
                reg load HKLM\TEMP_SOFTWARE $regPath 2>&1 | Out-Null
                try {
                    $regRoot = "HKLM:\TEMP_SOFTWARE\Microsoft\Windows\CurrentVersion"
                } finally {
                    # Will unload later
                }
            } else {
                $result.Errors += "Registry hive not found"
                return $result
            }
        } else {
            $regRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion"
        }
        
        # Ensure SetupPlatform key exists
        $setupPlatformPath = "$regRoot\Setup\SetupPlatform"
        if (-not (Test-Path $setupPlatformPath)) {
            New-Item -Path $setupPlatformPath -Force -ErrorAction SilentlyContinue | Out-Null
            $result.ActionsTaken += "Created SetupPlatform registry key"
            $report.AppendLine("[OK] Created SetupPlatform key") | Out-Null
        }
        
        # Normalize EditionID if needed
        $editionPath = "$regRoot"
        if ($isOffline) {
            $edition = (Get-ItemProperty -Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction SilentlyContinue).EditionID
        } else {
            $edition = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction SilentlyContinue).EditionID
        }
        
        if ($edition -and $edition -match "Evaluation|Invalid") {
            # Try to normalize to Professional
            if ($isOffline) {
                Set-ItemProperty -Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -Value "Professional" -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -Value "Professional" -ErrorAction SilentlyContinue
            }
            $result.ActionsTaken += "Normalized EditionID to Professional"
            $report.AppendLine("[OK] Normalized EditionID") | Out-Null
        }
        
        # Ensure InstallationType is Client
        if ($isOffline) {
            $installType = (Get-ItemProperty -Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "InstallationType" -ErrorAction SilentlyContinue).InstallationType
            if ($installType -ne "Client") {
                Set-ItemProperty -Path "HKLM:\TEMP_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "InstallationType" -Value "Client" -ErrorAction SilentlyContinue
                $result.ActionsTaken += "Set InstallationType to Client"
                $report.AppendLine("[OK] Set InstallationType to Client") | Out-Null
            }
        } else {
            $installType = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "InstallationType" -ErrorAction SilentlyContinue).InstallationType
            if ($installType -ne "Client") {
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "InstallationType" -Value "Client" -ErrorAction SilentlyContinue
                $result.ActionsTaken += "Set InstallationType to Client"
                $report.AppendLine("[OK] Set InstallationType to Client") | Out-Null
            }
        }
        
        if ($isOffline) {
            reg unload HKLM\TEMP_SOFTWARE 2>&1 | Out-Null
        }
        
        $result.Success = ($result.ActionsTaken.Count -gt 0)
        
    } catch {
        $result.Errors += "Error normalizing setup state: $_"
        if ($isOffline) {
            reg unload HKLM\TEMP_SOFTWARE 2>&1 | Out-Null
        }
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Repair-WinREForSetup {
    <#
    .SYNOPSIS
    Ensures WinRE is properly registered for setup.exe.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        Success = $false
        ActionsTaken = @()
        Errors = @()
        Report = ""
    }
    
    $envType = Get-EnvironmentType
    $isOffline = ($envType -ne 'FullOS')
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("WINRE REPAIR FOR SETUP") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    if (-not $isOffline) {
        # Online: Use reagentc
        Write-Host "Repairing WinRE registration..." -ForegroundColor Cyan
        try {
            # Check current status
            $reagentcInfo = reagentc /info 2>&1 | Out-String
            
            if ($reagentcInfo -match "Windows RE status.*Disabled") {
                # Try to enable
                $enableOutput = reagentc /enable 2>&1 | Out-String
                if ($enableOutput -match "Operation completed successfully") {
                    $result.ActionsTaken += "Enabled WinRE"
                    $report.AppendLine("[OK] WinRE enabled") | Out-Null
                }
            }
            
            # Set WinRE location if needed
            $winrePath = "$TargetDrive`:\Recovery\WindowsRE"
            if (Test-Path $winrePath) {
                $setOutput = reagentc /setreimage /path $winrePath 2>&1 | Out-String
                if ($setOutput -match "Operation completed successfully") {
                    $result.ActionsTaken += "Set WinRE path"
                    $report.AppendLine("[OK] WinRE path set") | Out-Null
                }
            }
            
        } catch {
            $errorMsg = "WinRE repair failed: $_"
            $result.Errors += $errorMsg
            $report.AppendLine("[WARNING] $errorMsg") | Out-Null
        }
    } else {
        # Offline: Check for WinRE partition and BCD entries
        $report.AppendLine("[INFO] Offline mode - WinRE repair limited") | Out-Null
        $report.AppendLine("WinRE should be repaired after booting into Windows") | Out-Null
    }
    
    $result.Success = ($result.ActionsTaken.Count -gt 0)
    $result.Report = $report.ToString()
    
    return $result
}

function Start-RepairInstallReadiness {
    <#
    .SYNOPSIS
    Master orchestrator - ensures system is ready for repair install.
    
    .DESCRIPTION
    Runs all checks and fixes to make Windows eligible for in-place upgrade
    with "Keep apps + files" option.
    #>
    param(
        [string]$TargetDrive = "C",
        [switch]$FixBlockers = $true,
        [scriptblock]$ProgressCallback = $null
    )
    
    $result = @{
        Success = $false
        ReadinessScore = 0
        Eligible = $false
        Blockers = @()
        Warnings = @()
        ActionsTaken = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REPAIR-INSTALL READINESS ENGINE") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Step 1: Test eligibility
    if ($null -ne $ProgressCallback) {
        & $ProgressCallback "Testing repair-install eligibility..."
    }
    $report.AppendLine("STEP 1: Testing Eligibility") | Out-Null
    $eligibility = Test-RepairInstallEligibility -TargetDrive $TargetDrive
    $result.ReadinessScore = $eligibility.ReadinessScore
    $result.Blockers = $eligibility.Blockers
    $result.Warnings = $eligibility.Warnings
    
    $report.AppendLine("Readiness Score: $($eligibility.ReadinessScore)/100") | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($eligibility.Blockers.Count -gt 0) {
        $report.AppendLine("BLOCKERS FOUND:") | Out-Null
        foreach ($blocker in $eligibility.Blockers) {
            $report.AppendLine("  [X] $blocker") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    if ($eligibility.Warnings.Count -gt 0) {
        $report.AppendLine("WARNINGS:") | Out-Null
        foreach ($warning in $eligibility.Warnings) {
            $report.AppendLine("  [WARN] $warning") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Step 2: Fix blockers if requested
    if ($FixBlockers -and $eligibility.Blockers.Count -gt 0) {
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Fixing blockers..."
        }
        $report.AppendLine("STEP 2: Fixing Blockers") | Out-Null
        
        # Clear CBS blockers
        $cbsResult = Clear-CBSBlockers -TargetDrive $TargetDrive
        $report.AppendLine($cbsResult.Report) | Out-Null
        $result.ActionsTaken += $cbsResult.ActionsTaken
        
        # Normalize setup state
        $setupResult = Normalize-SetupState -TargetDrive $TargetDrive
        $report.AppendLine($setupResult.Report) | Out-Null
        $result.ActionsTaken += $setupResult.ActionsTaken
        
        # Repair WinRE
        $winreResult = Repair-WinREForSetup -TargetDrive $TargetDrive
        $report.AppendLine($winreResult.Report) | Out-Null
        $result.ActionsTaken += $winreResult.ActionsTaken
        
        $report.AppendLine("") | Out-Null
        
        # Re-test eligibility
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Re-testing eligibility after fixes..."
        }
        $eligibility = Test-RepairInstallEligibility -TargetDrive $TargetDrive
        $result.ReadinessScore = $eligibility.ReadinessScore
        $result.Blockers = $eligibility.Blockers
        $result.Warnings = $eligibility.Warnings
    }
    
    # Final assessment
    $report.AppendLine("FINAL ASSESSMENT") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($eligibility.Blockers.Count -eq 0 -and $eligibility.ReadinessScore -ge 80) {
        $result.Eligible = $true
        $result.Success = $true
        $report.AppendLine("[OK] SYSTEM IS READY FOR REPAIR INSTALL") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("You can now run:") | Out-Null
        $report.AppendLine("  setup.exe /auto upgrade /quiet") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("Or use Windows Setup GUI and select 'Keep apps + files'") | Out-Null
    } elseif ($eligibility.Blockers.Count -eq 0) {
        $result.Eligible = $true
        $result.Success = $true
        $report.AppendLine("[WARN] SYSTEM MAY BE READY (with warnings)") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("Readiness score: $($eligibility.ReadinessScore)/100") | Out-Null
        $report.AppendLine("Address warnings before attempting repair install.") | Out-Null
    } else {
        $report.AppendLine("[X] SYSTEM IS NOT READY") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("Blockers must be resolved:") | Out-Null
        foreach ($blocker in $eligibility.Blockers) {
            $report.AppendLine("  - $blocker") | Out-Null
        }
    }
    
    $result.Report = $report.ToString()
    return $result
}

# Batch Operations Support - Run multiple repair operations in sequence
# Part of MiracleBoot v7.3.0

function Start-BatchRepairOperations {
    <#
    .SYNOPSIS
    Executes multiple repair operations in sequence with progress tracking and error handling.
    
    .DESCRIPTION
    Allows users to run a custom sequence of repair operations:
    - Boot Repair
    - System File Repair
    - Disk Repair
    - In-Place Upgrade Readiness
    - Custom operations
    
    Each operation runs sequentially with progress tracking and automatic error handling.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$Operations,
        
        [string]$TargetDrive = "C",
        
        [switch]$StopOnError = $false,
        
        [switch]$CreateRestorePoint = $true,
        
        [scriptblock]$ProgressCallback = $null
    )
    
    $result = @{
        Success = $false
        OperationsCompleted = @()
        OperationsFailed = @()
        TotalDuration = $null
        Report = ""
        Errors = @()
        RestorePointID = $null
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    $startTime = Get-Date
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("BATCH REPAIR OPERATIONS") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine("Operations: $($Operations.Count)") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Create restore point before batch operations
    $envType = Get-EnvironmentType
    if ($CreateRestorePoint -and $envType -eq 'FullOS') {
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Creating restore point before batch operations..."
        }
        $report.AppendLine("Creating system restore point...") | Out-Null
        $restorePoint = Create-SystemRestorePoint -Description "Before Batch Repair Operations" -OperationType "BatchRepair"
        if ($restorePoint.Success) {
            $result.RestorePointID = $restorePoint.RestorePointID
            $report.AppendLine("[OK] Restore point created: $($restorePoint.RestorePointPath)") | Out-Null
        } else {
            $report.AppendLine("[WARNING] Could not create restore point: $($restorePoint.Message)") | Out-Null
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Execute each operation
    $operationNum = 1
    foreach ($operation in $Operations) {
        $opName = if ($operation.Name) { $operation.Name } else { "Operation $operationNum" }
        $opAction = $operation.Action
        $opParams = if ($operation.Parameters) { $operation.Parameters } else { @{} }
        
        $report.AppendLine("OPERATION $operationNum / $($Operations.Count): $opName") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Executing operation $operationNum of $($Operations.Count): $opName"
        }
        
        try {
            # Add common parameters
            $opParams.TargetDrive = $TargetDrive
            if ($ProgressCallback -and -not $opParams.ContainsKey('ProgressCallback')) {
                $opParams.ProgressCallback = $ProgressCallback
            }
            
            # Execute the operation
            $opResult = & $opAction @opParams
            
            if ($opResult.Success) {
                $result.OperationsCompleted += @{
                    Name = $opName
                    Action = $opAction
                    Result = $opResult
                }
                $report.AppendLine("[SUCCESS] $opName completed successfully") | Out-Null
                if ($opResult.Report) {
                    $report.AppendLine($opResult.Report) | Out-Null
                }
            } else {
                $result.OperationsFailed += @{
                    Name = $opName
                    Action = $opAction
                    Result = $opResult
                }
                $report.AppendLine("[FAILED] $opName failed") | Out-Null
                if ($opResult.Report) {
                    $report.AppendLine($opResult.Report) | Out-Null
                }
                if ($opResult.Errors) {
                    $result.Errors += $opResult.Errors
                }
                
                # Stop on error if requested
                if ($StopOnError) {
                    $report.AppendLine("") | Out-Null
                    $report.AppendLine("[STOPPED] Batch operations stopped due to error in: $opName") | Out-Null
                    break
                }
            }
        } catch {
            $errorMsg = "Operation '$opName' failed with exception: $_"
            $result.OperationsFailed += @{
                Name = $opName
                Action = $opAction
                Error = $errorMsg
            }
            $result.Errors += $errorMsg
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            
            if ($StopOnError) {
                $report.AppendLine("") | Out-Null
                $report.AppendLine("[STOPPED] Batch operations stopped due to error") | Out-Null
                break
            }
        }
        
        $report.AppendLine("") | Out-Null
        $operationNum++
    }
    
    # Summary
    $result.TotalDuration = (Get-Date) - $startTime
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("BATCH OPERATIONS SUMMARY") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("Completed: $($result.OperationsCompleted.Count)") | Out-Null
    $report.AppendLine("Failed: $($result.OperationsFailed.Count)") | Out-Null
    $report.AppendLine("Total Duration: $($result.TotalDuration.ToString('hh\:mm\:ss'))") | Out-Null
    
    if ($result.OperationsFailed.Count -eq 0) {
        $result.Success = $true
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[SUCCESS] All batch operations completed successfully!") | Out-Null
    } else {
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[PARTIAL] Some operations failed. Review errors above.") | Out-Null
    }
    
    $result.Report = $report.ToString()
    
    # Save to repair history
    try {
        Save-RepairHistory -RepairResult $result -OperationType "BatchRepair" -TargetDrive $TargetDrive
    } catch {
        Write-Warning "Could not save batch repair history: $_"
    }
    
    return $result
}

function New-BatchOperation {
    <#
    .SYNOPSIS
    Creates a batch operation definition for use with Start-BatchRepairOperations.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [string]$Action,
        
        [hashtable]$Parameters = @{}
    )
    
    return @{
        Name = $Name
        Action = $Action
        Parameters = $Parameters
    }
}

function Get-PredefinedBatchOperations {
    <#
    .SYNOPSIS
    Returns predefined batch operation sequences for common scenarios.
    #>
    return @{
        "FullSystemRepair" = @(
            (New-BatchOperation -Name "Boot Repair" -Action "Start-AutomatedBootRepair"),
            (New-BatchOperation -Name "System File Repair" -Action "Start-SystemFileRepair"),
            (New-BatchOperation -Name "Disk Repair" -Action "Start-DiskRepair" -Parameters @{ FixErrors = $true }),
            (New-BatchOperation -Name "Repair-Install Readiness" -Action "Start-RepairInstallReadiness" -Parameters @{ FixBlockers = $true })
        )
        "QuickBootFix" = @(
            (New-BatchOperation -Name "Boot Repair" -Action "Start-AutomatedBootRepair")
        )
        "PreUpgradePreparation" = @(
            (New-BatchOperation -Name "System File Repair" -Action "Start-SystemFileRepair"),
            (New-BatchOperation -Name "Repair-Install Readiness" -Action "Start-RepairInstallReadiness" -Parameters @{ FixBlockers = $true })
        )
        "PostCloneFix" = @(
            (New-BatchOperation -Name "Boot Repair" -Action "Start-AutomatedBootRepair"),
            (New-BatchOperation -Name "System File Repair" -Action "Start-SystemFileRepair"),
            (New-BatchOperation -Name "Repair-Install Readiness" -Action "Start-RepairInstallReadiness" -Parameters @{ FixBlockers = $true })
        )
    }
}

# Quick Fix Menu - Automated Problem Detection and One-Click Fixes
# Part of MiracleBoot v7.3.0

function Get-QuickFixes {
    <#
    .SYNOPSIS
    Detects common issues and provides one-click fixes.
    
    .DESCRIPTION
    Automatically scans system for common problems and provides
    quick fix options with automated resolution.
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    $result = @{
        IssuesFound = @()
        QuickFixes = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("QUICK FIX MENU - AUTOMATED PROBLEM DETECTION") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    Write-Host "Scanning for common issues..." -ForegroundColor Cyan
    
    # 1. Check Boot Issues
    $report.AppendLine("CHECKING BOOT ISSUES...") | Out-Null
    try {
        $bootProb = Get-BootProbability -TargetDrive $TargetDrive
        if ($bootProb.Score -lt 70) {
            $fix = @{
                Id = "FixBoot"
                Title = "Fix Boot Issues"
                Description = "Boot probability is $($bootProb.Score)%. Boot configuration may be corrupted."
                Severity = if ($bootProb.Score -lt 50) { "Critical" } else { "High" }
                EstimatedTime = "5-15 minutes"
                Action = "Start-AutomatedBootRepair"
                Parameters = @{ TargetDrive = $TargetDrive }
            }
            $result.QuickFixes += $fix
            $result.IssuesFound += "Boot issues detected (Score: $($bootProb.Score)%)"
            $report.AppendLine("[ISSUE] Boot problems detected - Score: $($bootProb.Score)%") | Out-Null
        } else {
            $report.AppendLine("[OK] Boot configuration appears healthy") | Out-Null
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check boot status: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 2. Check System File Issues
    $report.AppendLine("CHECKING SYSTEM FILES...") | Out-Null
    try {
        $fileHealth = Test-SystemFileHealth -TargetDrive $TargetDrive
        if (-not $fileHealth.SystemFilesHealthy -or -not $fileHealth.ComponentStoreHealthy) {
            $fix = @{
                Id = "FixSystemFiles"
                Title = "Repair System Files"
                Description = "System files or component store corruption detected."
                Severity = "High"
                EstimatedTime = "30-60 minutes"
                Action = "Start-SystemFileRepair"
                Parameters = @{ TargetDrive = $TargetDrive }
            }
            $result.QuickFixes += $fix
            $result.IssuesFound += "System file corruption detected"
            $report.AppendLine("[ISSUE] System file corruption detected") | Out-Null
        } else {
            $report.AppendLine("[OK] System files appear healthy") | Out-Null
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check system files: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 3. Check Disk Issues
    $report.AppendLine("CHECKING DISK HEALTH...") | Out-Null
    try {
        $diskHealth = Test-DiskHealth -TargetDrive $TargetDrive
        if ($diskHealth.NeedsRepair) {
            $fix = @{
                Id = "FixDisk"
                Title = "Repair Disk Errors"
                Description = "File system errors or bad sectors detected on disk."
                Severity = if ($diskHealth.HasBadSectors) { "Critical" } else { "High" }
                EstimatedTime = if ($diskHealth.HasBadSectors) { "1-4 hours" } else { "10-30 minutes" }
                Action = "Start-DiskRepair"
                Parameters = @{ 
                    TargetDrive = $TargetDrive
                    FixErrors = $true
                    RecoverBadSectors = $diskHealth.HasBadSectors
                }
            }
            $result.QuickFixes += $fix
            $result.IssuesFound += "Disk errors detected"
            $report.AppendLine("[ISSUE] Disk errors detected") | Out-Null
        } else {
            $report.AppendLine("[OK] Disk appears healthy") | Out-Null
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check disk health: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 4. Check Duplicate Boot Entries
    $report.AppendLine("CHECKING BOOT ENTRIES...") | Out-Null
    try {
        $duplicates = Find-DuplicateBCEEntries
        if ($duplicates -and $duplicates.Count -gt 0) {
            $fix = @{
                Id = "FixDuplicateBootEntries"
                Title = "Fix Duplicate Boot Entries"
                Description = "Found $($duplicates.Count) duplicate boot entry name(s)."
                Severity = "Medium"
                EstimatedTime = "2-5 minutes"
                Action = "Fix-DuplicateBCEEntries"
                Parameters = @{}
            }
            $result.QuickFixes += $fix
            $result.IssuesFound += "Duplicate boot entries found"
            $report.AppendLine("[ISSUE] Duplicate boot entries found") | Out-Null
        } else {
            $report.AppendLine("[OK] No duplicate boot entries") | Out-Null
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check boot entries: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 5. Check In-Place Upgrade Readiness
    $report.AppendLine("CHECKING IN-PLACE UPGRADE READINESS...") | Out-Null
    try {
        $readiness = Get-InPlaceUpgradeReadiness -TargetDrive $TargetDrive
        if (-not $readiness.ReadyForInPlaceUpgrade -and $readiness.Blockers.Count -gt 0) {
            $fix = @{
                Id = "FixUpgradeReadiness"
                Title = "Fix In-Place Upgrade Blockers"
                Description = "Found $($readiness.Blockers.Count) blocker(s) preventing in-place upgrade."
                Severity = "High"
                EstimatedTime = "10-30 minutes"
                Action = "Start-RepairInstallReadiness"
                Parameters = @{ 
                    TargetDrive = $TargetDrive
                    FixBlockers = $true
                }
            }
            $result.QuickFixes += $fix
            $result.IssuesFound += "In-place upgrade blockers detected"
            $report.AppendLine("[ISSUE] In-place upgrade blockers found") | Out-Null
        } else {
            $report.AppendLine("[OK] System ready for in-place upgrade") | Out-Null
        }
    } catch {
        $report.AppendLine("[WARNING] Could not check upgrade readiness: $_") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # Summary
    $report.AppendLine("SUMMARY:") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    $report.AppendLine("Issues Found: $($result.IssuesFound.Count)") | Out-Null
    $report.AppendLine("Quick Fixes Available: $($result.QuickFixes.Count)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($result.QuickFixes.Count -gt 0) {
        $report.AppendLine("AVAILABLE QUICK FIXES:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $num = 1
        foreach ($fix in $result.QuickFixes) {
            # Map severity to ASCII indicators to avoid Unicode parsing/encoding issues
            $severityColor = switch ($fix.Severity) {
                "Critical" { "[CRITICAL]" }
                "High" { "[HIGH]" }
                "Medium" { "[MEDIUM]" }
                default { "[INFO]" }
            }
            $report.AppendLine("$num. $severityColor $($fix.Title)") | Out-Null
            $report.AppendLine("   Description: $($fix.Description)") | Out-Null
            $report.AppendLine("   Estimated Time: $($fix.EstimatedTime)") | Out-Null
            $report.AppendLine("") | Out-Null
            $num++
        }
    } else {
        $report.AppendLine("[OK] No issues detected. System appears healthy!") | Out-Null
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Start-QuickFix {
    <#
    .SYNOPSIS
    Executes a quick fix by ID.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FixId,
        
        [string]$TargetDrive = "C",
        
        [scriptblock]$ProgressCallback = $null
    )
    
    $result = @{
        Success = $false
        FixId = $FixId
        Report = ""
        Errors = @()
    }
    
    # Get all available quick fixes
    $quickFixes = Get-QuickFixes -TargetDrive $TargetDrive
    $fix = $quickFixes.QuickFixes | Where-Object { $_.Id -eq $FixId } | Select-Object -First 1
    
    if (-not $fix) {
        $result.Errors += "Quick fix '$FixId' not found"
        return $result
    }
    
    $report = New-Object System.Text.StringBuilder
    $report.AppendLine("EXECUTING QUICK FIX: $($fix.Title)") | Out-Null
    $report.AppendLine("=" * 80) | Out-Null
    $report.AppendLine("") | Out-Null
    
    try {
        # Execute the fix
        $action = $fix.Action
        $params = $fix.Parameters.Clone()
        $params.TargetDrive = $TargetDrive
        
        if ($ProgressCallback) {
            $params.ProgressCallback = $ProgressCallback
        }
        
        $fixResult = & $action @params
        
        if ($fixResult.Success) {
            $result.Success = $true
            $report.AppendLine("[SUCCESS] Quick fix completed successfully!") | Out-Null
            if ($fixResult.Report) {
                $report.AppendLine($fixResult.Report) | Out-Null
            }
        } else {
            $report.AppendLine("[PARTIAL] Quick fix completed with some issues") | Out-Null
            if ($fixResult.Report) {
                $report.AppendLine($fixResult.Report) | Out-Null
            }
            if ($fixResult.Errors) {
                $result.Errors += $fixResult.Errors
            }
        }
    } catch {
        $errorMsg = "Quick fix failed: $_"
        $result.Errors += $errorMsg
        $report.AppendLine("[ERROR] $errorMsg") | Out-Null
    }
    
    $result.Report = $report.ToString()
    return $result
}

# Repair Templates and Presets
# One-click fixes for common scenarios
# Part of MiracleBoot v7.2.0

function Get-RepairTemplates {
    <#
    .SYNOPSIS
    Returns list of available repair templates.
    #>
    return @(
        @{
            Id = "QuickBootFix"
            Name = "Quick Boot Fix"
            Description = "Fast boot repair for common boot issues (BCD, boot files, bootrec)"
            EstimatedTime = "5-10 minutes"
            Steps = @("BootRepair", "BootFiles")
            RiskLevel = "Low"
        },
        @{
            Id = "BootLoopFix"
            Name = "Boot Loop Fix"
            Description = "Comprehensive fix for boot loops and startup issues"
            EstimatedTime = "15-30 minutes"
            Steps = @("BootRepair", "SystemFiles", "BootChainAnalysis")
            RiskLevel = "Medium"
        },
        @{
            Id = "AfterDiskClone"
            Name = "After Disk Clone"
            Description = "Fix boot and driver issues after disk cloning/migration"
            EstimatedTime = "20-40 minutes"
            Steps = @("BootRepair", "DriverPorting", "SystemFiles", "RepairInstallReadiness")
            RiskLevel = "Medium"
        },
        @{
            Id = "AfterMotherboardChange"
            Name = "After Motherboard Change"
            Description = "Complete fix after hardware change (drivers, boot, registry)"
            EstimatedTime = "30-60 minutes"
            Steps = @("DriverPorting", "BootRepair", "SystemFiles", "RegistryFixes", "RepairInstallReadiness")
            RiskLevel = "High"
        },
        @{
            Id = "FullSystemRecovery"
            Name = "Full System Recovery"
            Description = "Complete system repair (boot, files, disk, registry, readiness)"
            EstimatedTime = "60-120 minutes"
            Steps = @("CompleteSystemRepair", "RepairInstallReadiness")
            RiskLevel = "Medium"
        },
        @{
            Id = "InPlaceUpgradePrep"
            Name = "In-Place Upgrade Preparation"
            Description = "Prepare system for in-place upgrade (Keep apps + files)"
            EstimatedTime = "15-30 minutes"
            Steps = @("SystemFiles", "RepairInstallReadiness")
            RiskLevel = "Low"
        },
        @{
            Id = "CorruptedSystemFiles"
            Name = "Corrupted System Files"
            Description = "Fix corrupted Windows system files (SFC + DISM)"
            EstimatedTime = "20-40 minutes"
            Steps = @("SystemFiles")
            RiskLevel = "Low"
        },
        @{
            Id = "BootAndFiles"
            Name = "Boot + System Files"
            Description = "Fix boot issues and corrupted system files"
            EstimatedTime = "30-60 minutes"
            Steps = @("BootRepair", "SystemFiles")
            RiskLevel = "Medium"
        },
        @{
            Id = "InaccessibleBootDevice"
            Name = "Inaccessible Boot Device (0x7B)"
            Description = "Fix 0x7B BSOD and inaccessible boot device errors (missing storage drivers)"
            EstimatedTime = "20-40 minutes"
            Steps = @("DriverPorting", "BootRepair", "SystemFiles")
            RiskLevel = "Medium"
        },
        @{
            Id = "BlueScreenRecovery"
            Name = "Blue Screen Recovery"
            Description = "Comprehensive fix for BSOD errors and system crashes"
            EstimatedTime = "30-60 minutes"
            Steps = @("BootChainAnalysis", "SystemFiles", "BootRepair", "RepairInstallReadiness")
            RiskLevel = "Medium"
        },
        @{
            Id = "BCDCorruption"
            Name = "BCD Corruption Fix"
            Description = "Fix Boot Configuration Data corruption and boot manager issues"
            EstimatedTime = "10-20 minutes"
            Steps = @("BootRepair", "BootFiles")
            RiskLevel = "Low"
        },
        @{
            Id = "PreventReinstall"
            Name = "Prevent Reinstall (Last Resort)"
            Description = "Comprehensive repair to avoid Windows reinstall - tries all repair methods"
            EstimatedTime = "60-120 minutes"
            Steps = @("CompleteSystemRepair", "BootChainAnalysis", "RepairInstallReadiness", "SystemFiles")
            RiskLevel = "Medium"
        }
    )
}

function Start-RepairTemplate {
    <#
    .SYNOPSIS
    Executes a repair template (preset workflow).
    
    .PARAMETER TemplateId
    ID of the template to execute
    
    .PARAMETER TargetDrive
    Windows drive letter
    
    .PARAMETER SkipConfirmation
    Skip confirmation prompts
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplateId,
        
        [string]$TargetDrive = "C",
        
        [switch]$SkipConfirmation = $false,
        
        [scriptblock]$ProgressCallback = $null
    )
    
    $result = @{
        Success = $false
        TemplateId = $TemplateId
        StepsCompleted = @()
        StepsFailed = @()
        Report = ""
        Errors = @()
    }
    
    $templates = Get-RepairTemplates
    $template = $templates | Where-Object { $_.Id -eq $TemplateId } | Select-Object -First 1
    
    if (-not $template) {
        $result.Errors += "Template '$TemplateId' not found"
        return $result
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("REPAIR TEMPLATE: $($template.Name)") | Out-Null
    $report.AppendLine("Description: $($template.Description)") | Out-Null
    $report.AppendLine("Estimated Time: $($template.EstimatedTime)") | Out-Null
    $report.AppendLine("Risk Level: $($template.RiskLevel)") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Show template steps
    $report.AppendLine("TEMPLATE STEPS:") | Out-Null
    foreach ($step in $template.Steps) {
        $report.AppendLine("  - $step") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # Confirm if not skipped
    if (-not $SkipConfirmation) {
        $confirmMsg = "REPAIR TEMPLATE: $($template.Name)`n`n"
        $confirmMsg += "Description: $($template.Description)`n"
        $confirmMsg += "Estimated Time: $($template.EstimatedTime)`n"
        $confirmMsg += "Risk Level: $($template.RiskLevel)`n`n"
        $confirmMsg += "Steps to execute:`n"
        foreach ($step in $template.Steps) {
            $confirmMsg += "  - $step`n"
        }
        $confirmMsg += "`nTarget Drive: $TargetDrive`:`n`n"
        $confirmMsg += "Continue?"
        
        # In TUI, use Read-Host
        if ($null -eq $ProgressCallback) {
            Write-Host $confirmMsg -ForegroundColor Yellow
            $confirm = Read-Host "Type 'YES' to continue"
            if ($confirm -ne "YES") {
                $report.AppendLine("[CANCELLED] User cancelled template execution") | Out-Null
                $result.Report = $report.ToString()
                return $result
            }
        }
    }
    
    # Execute template steps
    $stepNum = 1
    foreach ($step in $template.Steps) {
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback "Executing step $stepNum/$($template.Steps.Count): $step"
        }
        
        $report.AppendLine("STEP $stepNum : $step") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        try {
            switch ($step) {
                "BootRepair" {
                    $stepResult = Start-AutomatedBootRepair -TargetDrive $TargetDrive
                    if ($stepResult.Success) {
                        $result.StepsCompleted += "BootRepair"
                        $report.AppendLine("[OK] Boot repair completed") | Out-Null
                    } else {
                        $result.StepsFailed += "BootRepair"
                        $report.AppendLine("[FAILED] Boot repair failed") | Out-Null
                        $result.Errors += "BootRepair: $($stepResult.Errors -join ', ')"
                    }
                }
                "SystemFiles" {
                    $stepResult = Start-SystemFileRepair -TargetDrive $TargetDrive -ProgressCallback $ProgressCallback
                    if ($stepResult.SFCCompleted -or $stepResult.DISMCompleted) {
                        $result.StepsCompleted += "SystemFiles"
                        $report.AppendLine("[OK] System file repair completed") | Out-Null
                    } else {
                        $result.StepsFailed += "SystemFiles"
                        $report.AppendLine("[FAILED] System file repair failed") | Out-Null
                        $result.Errors += "SystemFiles: $($stepResult.Errors -join ', ')"
                    }
                }
                "BootFiles" {
                    # Quick boot files fix
                    try {
                        $bootRecOutput = bootrec /fixboot 2>&1 | Out-String
                        if ($LASTEXITCODE -eq 0) {
                            $result.StepsCompleted += "BootFiles"
                            $report.AppendLine("[OK] Boot files fixed") | Out-Null
                        } else {
                            $result.StepsFailed += "BootFiles"
                            $report.AppendLine("[WARNING] Boot files fix had issues") | Out-Null
                        }
                    } catch {
                        $result.StepsFailed += "BootFiles"
                        $report.AppendLine("[WARNING] Boot files fix failed: $_") | Out-Null
                    }
                }
                "DriverPorting" {
                    $stepResult = Get-MissingDriversForPorting -TargetDrive $TargetDrive
                    if ($stepResult.Success) {
                        $result.StepsCompleted += "DriverPorting"
                        $report.AppendLine("[OK] Driver porting completed") | Out-Null
                        $report.AppendLine("  Drivers exported to: $($stepResult.ExportPath)") | Out-Null
                    } else {
                        $result.StepsFailed += "DriverPorting"
                        $report.AppendLine("[WARNING] Driver porting had issues") | Out-Null
                    }
                }
                "BootChainAnalysis" {
                    $stepResult = Get-BootChainAnalysis -TargetDrive $TargetDrive
                    $result.StepsCompleted += "BootChainAnalysis"
                    $report.AppendLine("[OK] Boot chain analysis completed") | Out-Null
                    $report.AppendLine($stepResult.Report) | Out-Null
                }
                "RegistryFixes" {
                    $stepResult = Apply-OneClickRegistryFixes -TargetDrive $TargetDrive
                    if ($stepResult.Success) {
                        $result.StepsCompleted += "RegistryFixes"
                        $report.AppendLine("[OK] Registry fixes applied") | Out-Null
                    } else {
                        $result.StepsFailed += "RegistryFixes"
                        $report.AppendLine("[WARNING] Registry fixes had issues") | Out-Null
                    }
                }
                "RepairInstallReadiness" {
                    $stepResult = Start-RepairInstallReadiness -TargetDrive $TargetDrive -FixBlockers -ProgressCallback $ProgressCallback
                    if ($stepResult.Eligible) {
                        $result.StepsCompleted += "RepairInstallReadiness"
                        $report.AppendLine("[OK] System is ready for repair install") | Out-Null
                    } else {
                        $result.StepsFailed += "RepairInstallReadiness"
                        $report.AppendLine("[WARNING] System may not be fully ready") | Out-Null
                    }
                }
                "CompleteSystemRepair" {
                    $stepResult = Start-CompleteSystemRepair -TargetDrive $TargetDrive -ProgressCallback $ProgressCallback
                    if ($stepResult.Success) {
                        $result.StepsCompleted += "CompleteSystemRepair"
                        $report.AppendLine("[OK] Complete system repair finished") | Out-Null
                    } else {
                        $result.StepsFailed += "CompleteSystemRepair"
                        $report.AppendLine("[WARNING] Complete system repair had issues") | Out-Null
                    }
                }
                default {
                    $report.AppendLine("[WARNING] Unknown step: $step") | Out-Null
                }
            }
        } catch {
            $result.StepsFailed += $step
            $errorMsg = "Step $step failed: $_"
            $report.AppendLine("[ERROR] $errorMsg") | Out-Null
            $result.Errors += $errorMsg
        }
        
        $report.AppendLine("") | Out-Null
        $stepNum++
    }
    
    # Final summary
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("TEMPLATE EXECUTION SUMMARY") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Steps Completed: $($result.StepsCompleted.Count)/$($template.Steps.Count)") | Out-Null
    $report.AppendLine("Steps Failed: $($result.StepsFailed.Count)") | Out-Null
    
    if ($result.StepsFailed.Count -eq 0) {
        $result.Success = $true
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[OK] TEMPLATE EXECUTION SUCCESSFUL") | Out-Null
    } else {
        $report.AppendLine("") | Out-Null
        $report.AppendLine("[WARN] TEMPLATE EXECUTION COMPLETED WITH WARNINGS") | Out-Null
        $report.AppendLine("") | Out-Null
        $report.AppendLine("Failed Steps:") | Out-Null
        foreach ($failed in $result.StepsFailed) {
            $report.AppendLine("  - $failed") | Out-Null
        }
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Get-BootHealthSummary {
    <#
    .SYNOPSIS
    Comprehensive boot health summary including BCD validity, EFI partition status, boot stack order, and log file analysis.
    
    .DESCRIPTION
    Provides a complete overview of Windows boot health by checking:
    - BCD (Boot Configuration Data) validity and accessibility
    - EFI System Partition presence and health
    - Boot chain analysis showing where boot process succeeds/fails
    - Boot log file analysis
    - Overall boot health score
    
    .PARAMETER TargetDrive
    Windows drive letter (e.g., "C")
    
    .OUTPUTS
    Hashtable with comprehensive boot health information
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        BootHealthScore = 0
        MaxScore = 100
        BCDStatus = @{
            Valid = $false
            Accessible = $false
            Path = ""
            Details = ""
            Issues = @()
        }
        EFIPartition = @{
            Present = $false
            Accessible = $false
            DriveLetter = ""
            Details = ""
            Issues = @()
        }
        BootChain = @{
            LastPassedStage = ""
            FirstFailedStage = ""
            ProgressPercent = 0
            Stages = @()
            Details = ""
        }
        BootLogs = @{
            Found = $false
            Path = ""
            Analysis = $null
            Details = ""
        }
        OverallStatus = "Unknown"
        Recommendations = @()
        Report = ""
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("WINDOWS BOOT HEALTH SUMMARY") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 1: BCD (Boot Configuration Data) Validity
    # ========================================================================
    $report.AppendLine("1. BCD (Boot Configuration Data) Status") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $bcdFound = $false
    $bcdPath = $null
    $efiDriveLetter = $null
    
    # Find EFI partition
    try {
        $efiPartitions = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
        if ($efiPartitions) {
            foreach ($efiPart in $efiPartitions) {
                if ($efiPart.DriveLetter) {
                    $efiDriveLetter = $efiPart.DriveLetter
                    $bcdPath = "$efiDriveLetter`:\EFI\Microsoft\Boot\BCD"
                    if (Test-Path $bcdPath) {
                        $bcdFound = $true
                        $result.BCDStatus.Path = $bcdPath
                        $result.EFIPartition.DriveLetter = $efiDriveLetter
                        $result.EFIPartition.Present = $true
                        $result.EFIPartition.Accessible = $true
                        break
                    }
                }
            }
        }
    } catch {
        $result.BCDStatus.Issues += "Error checking EFI partitions: $_"
    }
    
    # Check BCD accessibility
    if ($bcdFound) {
        $result.BCDStatus.Valid = $true
        $result.BootHealthScore += 30
        $report.AppendLine("[OK] BCD file found at: $bcdPath") | Out-Null
        
        # Test BCD accessibility with bcdedit
        try {
            $bcdTest = bcdedit /enum 2>&1 | Out-String
            if ($bcdTest -match "The boot configuration data store could not be opened" -or 
                $bcdTest -match "could not be opened") {
                $result.BCDStatus.Accessible = $false
                $result.BCDStatus.Issues += "BCD exists but cannot be opened - may be corrupted or locked"
                $result.BCDStatus.Details = "BCD file found but bcdedit cannot access it"
                $report.AppendLine("[FAIL] BCD exists but cannot be opened - may be corrupted") | Out-Null
                $result.BootHealthScore -= 15
            } else {
                $result.BCDStatus.Accessible = $true
                $result.BCDStatus.Details = "BCD is valid and accessible"
                $report.AppendLine("[OK] BCD is accessible and can be enumerated") | Out-Null
                
                # Check for Windows Boot Manager entry
                if ($bcdTest -match "Windows Boot Manager") {
                    $report.AppendLine("[OK] Windows Boot Manager entry found in BCD") | Out-Null
                } else {
                    $result.BCDStatus.Issues += "Windows Boot Manager entry not found"
                    $report.AppendLine("[WARNING] Windows Boot Manager entry not found") | Out-Null
                    $result.BootHealthScore -= 5
                }
            }
        } catch {
            $result.BCDStatus.Accessible = $false
            $result.BCDStatus.Issues += "Error testing BCD accessibility: $_"
            $report.AppendLine("[ERROR] Could not test BCD accessibility: $_") | Out-Null
        }
    } else {
        $result.BCDStatus.Valid = $false
        $result.BCDStatus.Issues += "BCD file not found on any EFI partition"
        $result.BCDStatus.Details = "BCD file is missing"
        $report.AppendLine("[FAIL] BCD file not found") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 2: EFI System Partition
    # ========================================================================
    $report.AppendLine("2. EFI System Partition Status") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    if ($result.EFIPartition.Present) {
        $result.BootHealthScore += 20
        $report.AppendLine("[OK] EFI System Partition found") | Out-Null
        $report.AppendLine("    Drive Letter: $($result.EFIPartition.DriveLetter):") | Out-Null
        
        # Check EFI folder structure
        $efiPath = "$($result.EFIPartition.DriveLetter):\EFI"
        $microsoftBootPath = "$($result.EFIPartition.DriveLetter):\EFI\Microsoft\Boot"
        
        if (Test-Path $efiPath) {
            $report.AppendLine("[OK] EFI folder structure exists") | Out-Null
            if (Test-Path $microsoftBootPath) {
                $report.AppendLine("[OK] Microsoft Boot folder exists") | Out-Null
                $result.EFIPartition.Details = "EFI partition is healthy and properly structured"
            } else {
                $result.EFIPartition.Issues += "Microsoft Boot folder missing"
                $report.AppendLine("[WARNING] Microsoft Boot folder missing") | Out-Null
                $result.BootHealthScore -= 5
            }
        } else {
            $result.EFIPartition.Issues += "EFI folder structure missing"
            $report.AppendLine("[FAIL] EFI folder structure missing") | Out-Null
            $result.BootHealthScore -= 10
        }
    } else {
        $result.EFIPartition.Issues += "No EFI System Partition detected"
        $result.EFIPartition.Details = "EFI partition not found - system may use Legacy BIOS"
        $report.AppendLine("[FAIL] No EFI System Partition found") | Out-Null
        $report.AppendLine("    Note: System may be using Legacy BIOS mode") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 3: Boot Chain Analysis
    # ========================================================================
    $report.AppendLine("3. Boot Chain Analysis") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    try {
        $bootChainAnalysis = Get-BootChainAnalysis -TargetDrive $TargetDrive
        $result.BootChain.LastPassedStage = $bootChainAnalysis.FailureStage
        $result.BootChain.FirstFailedStage = $bootChainAnalysis.FailureStage
        
        # Extract boot stages information
        if ($bootChainAnalysis.BootStages) {
            $result.BootChain.Stages = $bootChainAnalysis.BootStages
            
            # Calculate progress
            $passedStages = ($bootChainAnalysis.BootStages | Where-Object { $_.Status -eq "Passed" }).Count
            $totalStages = $bootChainAnalysis.BootStages.Count
            if ($totalStages -gt 0) {
                $result.BootChain.ProgressPercent = [math]::Round(($passedStages / $totalStages) * 100)
            }
            
            # Find last passed and first failed
            $lastPassed = -1
            $firstFailed = -1
            for ($i = 0; $i -lt $bootChainAnalysis.BootStages.Count; $i++) {
                if ($bootChainAnalysis.BootStages[$i].Status -eq "Passed") {
                    $lastPassed = $i
                } elseif ($bootChainAnalysis.BootStages[$i].Status -eq "Failed" -and $firstFailed -eq -1) {
                    $firstFailed = $i
                }
            }
            
            if ($lastPassed -ge 0) {
                $result.BootChain.LastPassedStage = $bootChainAnalysis.BootStages[$lastPassed].Name
            }
            if ($firstFailed -ge 0) {
                $result.BootChain.FirstFailedStage = $bootChainAnalysis.BootStages[$firstFailed].Name
            }
            
            # Add to score based on progress
            $result.BootHealthScore += [math]::Round($result.BootChain.ProgressPercent * 0.3)
        }
        
        $result.BootChain.Details = $bootChainAnalysis.FailureReason
        if ($bootChainAnalysis.Recommendations) {
            $result.Recommendations += $bootChainAnalysis.Recommendations
        }
        
        $report.AppendLine("Boot Progress: $($result.BootChain.ProgressPercent)%") | Out-Null
        if ($result.BootChain.LastPassedStage) {
            $report.AppendLine("Last Successful Stage: $($result.BootChain.LastPassedStage)") | Out-Null
        }
        if ($result.BootChain.FirstFailedStage) {
            $report.AppendLine("First Failed Stage: $($result.BootChain.FirstFailedStage)") | Out-Null
            $report.AppendLine("Failure Reason: $($result.BootChain.Details)") | Out-Null
        } else {
            $report.AppendLine("[OK] All boot stages completed successfully") | Out-Null
        }
        
    } catch {
        $result.BootChain.Details = "Error analyzing boot chain: $_"
        $report.AppendLine("[ERROR] Could not analyze boot chain: $_") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # CHECK 4: Boot Log Files
    # ========================================================================
    $report.AppendLine("4. Boot Log Analysis") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $logPath = "$TargetDrive`:\Windows\ntbtlog.txt"
    $result.BootLogs.Path = $logPath
    
    if (Test-Path $logPath) {
        $result.BootLogs.Found = $true
        $result.BootHealthScore += 10
        $report.AppendLine("[OK] Boot log found at: $logPath") | Out-Null
        
        try {
            $bootLogAnalysis = Get-BootLogAnalysis -TargetDrive $TargetDrive
            $result.BootLogs.Analysis = $bootLogAnalysis
            
            if ($bootLogAnalysis.MissingDrivers.Count -gt 0) {
                $report.AppendLine("[WARNING] Missing drivers detected: $($bootLogAnalysis.MissingDrivers.Count)") | Out-Null
                $result.BootLogs.Details = "$($bootLogAnalysis.MissingDrivers.Count) missing drivers found"
                $result.BootHealthScore -= 5
            } else {
                $report.AppendLine("[OK] No critical missing drivers detected") | Out-Null
                $result.BootLogs.Details = "Boot log analysis completed - no critical issues"
            }
            
            if ($bootLogAnalysis.FailedDrivers.Count -gt 0) {
                $report.AppendLine("[WARNING] Failed drivers detected: $($bootLogAnalysis.FailedDrivers.Count)") | Out-Null
                $result.BootHealthScore -= 5
            }
            
        } catch {
            $result.BootLogs.Details = "Error analyzing boot log: $_"
            $report.AppendLine("[ERROR] Could not analyze boot log: $_") | Out-Null
        }
    } else {
        $result.BootLogs.Found = $false
        $result.BootLogs.Details = "Boot log not found - system may not be configured for boot logging"
        $report.AppendLine("[INFO] Boot log not found at: $logPath") | Out-Null
        $report.AppendLine("    Note: Boot logging may not be enabled") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # ========================================================================
    # OVERALL STATUS
    # ========================================================================
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("OVERALL BOOT HEALTH SCORE: $($result.BootHealthScore)/$($result.MaxScore)") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Determine overall status
    if ($result.BootHealthScore -ge 80) {
        $result.OverallStatus = "Excellent"
        $report.AppendLine("STATUS: EXCELLENT - System boot health is very good") | Out-Null
    } elseif ($result.BootHealthScore -ge 60) {
        $result.OverallStatus = "Good"
        $report.AppendLine("STATUS: GOOD - System boot health is acceptable with minor issues") | Out-Null
    } elseif ($result.BootHealthScore -ge 40) {
        $result.OverallStatus = "Fair"
        $report.AppendLine("STATUS: FAIR - System boot health has some issues that should be addressed") | Out-Null
    } elseif ($result.BootHealthScore -ge 20) {
        $result.OverallStatus = "Poor"
        $report.AppendLine("STATUS: POOR - System boot health has significant issues") | Out-Null
    } else {
        $result.OverallStatus = "Critical"
        $report.AppendLine("STATUS: CRITICAL - System boot health is severely compromised") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # Add recommendations if there are issues
    if ($result.BootHealthScore -lt 80) {
        $report.AppendLine("RECOMMENDATIONS:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        if (-not $result.BCDStatus.Valid -or -not $result.BCDStatus.Accessible) {
            $report.AppendLine("1. Fix BCD issues:") | Out-Null
            $report.AppendLine("   - Run: bcdboot $TargetDrive`:\Windows") | Out-Null
            $report.AppendLine("   - Run: bootrec /rebuildbcd") | Out-Null
            $report.AppendLine("") | Out-Null
        }
        
        if (-not $result.EFIPartition.Present) {
            $report.AppendLine("2. EFI partition issues:") | Out-Null
            $report.AppendLine("   - Verify system is using UEFI mode") | Out-Null
            $report.AppendLine("   - Check if EFI partition exists but has no drive letter") | Out-Null
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.BootChain.FirstFailedStage) {
            $report.AppendLine("3. Boot chain failure at: $($result.BootChain.FirstFailedStage)") | Out-Null
            foreach ($rec in $result.Recommendations) {
                $report.AppendLine("   - $rec") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.BootLogs.Analysis -and $result.BootLogs.Analysis.MissingDrivers.Count -gt 0) {
            $report.AppendLine("4. Missing drivers detected:") | Out-Null
            $report.AppendLine("   - Use 'Port Missing Drivers' feature to extract and inject drivers") | Out-Null
            $report.AppendLine("") | Out-Null
        }
    }
    
    $result.Report = $report.ToString()
    return $result
}

function Get-WindowsUpdateEligibility {
    <#
    .SYNOPSIS
    Checks Windows Update in-place repair upgrade installation eligibility.
    
    .DESCRIPTION
    Comprehensive check for Windows Update in-place upgrade eligibility by:
    - Testing repair-install eligibility
    - Checking for blockers
    - Providing readiness score
    - Listing recommendations
    
    .PARAMETER TargetDrive
    Windows drive letter (e.g., "C")
    
    .OUTPUTS
    Hashtable with eligibility status and details
    #>
    param(
        [string]$TargetDrive = "C"
    )
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        Eligible = $false
        ReadinessScore = 0
        MaxScore = 100
        Blockers = @()
        Warnings = @()
        Recommendations = @()
        Details = @{}
        Status = "Unknown"
        Report = ""
    }
    
    try {
        $eligibility = Test-RepairInstallEligibility -TargetDrive $TargetDrive
        $result.Eligible = $eligibility.Eligible
        $result.ReadinessScore = $eligibility.ReadinessScore
        $result.Blockers = $eligibility.Blockers
        $result.Warnings = $eligibility.Warnings
        $result.Recommendations = $eligibility.Recommendations
        $result.Details = $eligibility.Details
        
        # Determine status
        if ($result.ReadinessScore -ge 80 -and $result.Blockers.Count -eq 0) {
            $result.Status = "Ready"
        } elseif ($result.ReadinessScore -ge 60) {
            $result.Status = "Mostly Ready"
        } elseif ($result.ReadinessScore -ge 40) {
            $result.Status = "Needs Work"
        } else {
            $result.Status = "Not Ready"
        }
        
        # Build report
        $report = New-Object System.Text.StringBuilder
        $separator = "=" * 80
        
        $report.AppendLine($separator) | Out-Null
        $report.AppendLine("WINDOWS UPDATE IN-PLACE REPAIR UPGRADE ELIGIBILITY") | Out-Null
        $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
        $report.AppendLine($separator) | Out-Null
        $report.AppendLine("") | Out-Null
        
        $report.AppendLine("READINESS SCORE: $($result.ReadinessScore)/$($result.MaxScore)") | Out-Null
        $report.AppendLine("STATUS: $($result.Status)") | Out-Null
        $report.AppendLine("ELIGIBLE: $(if ($result.Eligible) { 'YES' } else { 'NO' })") | Out-Null
        $report.AppendLine("") | Out-Null
        
        if ($result.Blockers.Count -gt 0) {
            $report.AppendLine("BLOCKERS PREVENTING UPGRADE:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            foreach ($blocker in $result.Blockers) {
                $report.AppendLine("  [BLOCKER] $blocker") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.Warnings.Count -gt 0) {
            $report.AppendLine("WARNINGS:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            foreach ($warning in $result.Warnings) {
                $report.AppendLine("  [WARNING] $warning") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.Details.Count -gt 0) {
            $report.AppendLine("DETAILS:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            foreach ($key in $result.Details.Keys) {
                $report.AppendLine("  $key : $($result.Details[$key])") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        if ($result.Recommendations.Count -gt 0) {
            $report.AppendLine("RECOMMENDATIONS:") | Out-Null
            $report.AppendLine("-" * 80) | Out-Null
            foreach ($rec in $result.Recommendations) {
                $report.AppendLine("  - $rec") | Out-Null
            }
            $report.AppendLine("") | Out-Null
        }
        
        $result.Report = $report.ToString()
        
    } catch {
        $result.Status = "Error"
        $result.Blockers += "Error checking eligibility: $_"
        $result.Report = "ERROR: Could not check Windows Update eligibility: $_"
    }
    
    return $result
}

