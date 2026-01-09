<#
    MIRACLE BOOT – TEXT USER INTERFACE (TUI)
    ========================================

    This module implements the **console menu experience** used when the GUI
    cannot or should not be used (WinRE / WinPE / Shift+F10). It is a thin UI
    layer over the core engine in `Helper\WinRepairCore.ps1`.

    TABLE OF CONTENTS (HIGH‑LEVEL)
    ------------------------------
    1. Environment Banner & Main Loop
       - `Start-TUI` (environment detection + main menu)
    2. Core Menus
       - Volumes & Health (A–G style options)
       - Boot repair & diagnostics
       - System file and disk repair
       - Complete system repair pipelines
    3. Advanced Tools
       - In-place upgrade readiness
       - Boot chain / boot log analysis
       - Network diagnostics & driver management
       - Driver porting and SAVE_ME.txt generator
       - Disk Management Helper
       - System Restore Point Management
       - Keyboard Symbol Helper
    4. Safety / Warning Flows
       - Confirmation prompts before destructive actions
       - Integration with command risk / warning system in core

    ENVIRONMENT MAPPING – WHEN THIS TUI RUNS
    ----------------------------------------
    - **WinRE / Shift+F10 setup console**
        - Launched by `MiracleBoot.ps1` when `Get-EnvironmentType` reports `WinRE`.
        - Optimized for:
            - X: RAM disk system drive
            - Offline Windows installations mounted on other letters (C:, D:, etc.).

    - **WinPE (USB / rescue media)**
        - Also launched by `MiracleBoot.ps1` when `Get-EnvironmentType` reports `WinPE`.
        - Enables WinPE‑specific options (e.g. browser installation).

    - **FullOS (fallback)**
        - Can be launched from a full Windows desktop if WPF is unavailable or the
          user explicitly wants a console‑only workflow.

    FLOW MAPPING – HOW REQUESTS MOVE THROUGH THE SYSTEM
    ---------------------------------------------------
    1. `Start-TUI`
         - Detects environment (FullOS vs WinRE vs WinPE) **for display only**.
         - Enters a `do { ... } while` menu loop.

    2. User selects a menu option (e.g. Disk Repair, Boot Repair, Readiness Check).

    3. The corresponding case in the main `switch ($c)`:
         - Gathers parameters (target drive, confirmation, etc.).
         - Calls into **core engine functions** in `WinRepairCore.ps1`, such as:
             - `Start-SystemFileRepair`
             - `Start-DiskRepair`
             - `Start-RepairInstallReadiness`
             - `Get-BootChainAnalysis`, `Get-BootLogAnalysis`
             - `Create-SystemRestorePoint`, `Get-SystemRestorePoints`, `Restore-FromSystemRestorePoint`

    4. Any progress reporting from the engine is surfaced via:
         - `ProgressCallback` scriptblocks passed into core functions.
         - Console messages and simple ASCII progress indicators.

    QUICK ORIENTATION
    -----------------
    - **Want to know what the user can do in WinRE/WinPE?**  
        → Read the `Start-TUI` menu definitions; each option maps to one or more
          core engine calls.

    - **Adding a new menu option?**  
        → Add the UI shell here (prompting, menu text) and call into a new or
          existing function in `WinRepairCore.ps1`.

    - **Need to adjust environment‑specific availability?**  
        → Use the `$envDisplay` logic at the top of `Start-TUI` and gate menu
          entries (e.g. WinPE‑only options) based on that value.
#>

# Helper function to create enhanced TUI progress callback with ASCII progress bars
function New-TUIProgressCallback {
    <#
    .SYNOPSIS
    Creates a progress callback scriptblock for TUI that displays ASCII progress bars and percentage.
    
    .DESCRIPTION
    Returns a scriptblock that can be passed to repair functions. The callback receives
    either a progress object (hashtable/PSCustomObject) with Percentage, Stage, CurrentOperation,
    EstimatedTimeRemaining properties, or a simple string message.
    
    Uses Write-Progress for in-place updates and also displays ASCII progress bars.
    #>
    param(
        [string]$Activity = "Operation",
        [string]$Status = "In Progress"
    )
    
    $script:lastProgressId = 1
    $script:lastPercentage = -1
    $script:lastStage = ""
    
    return {
        param($progress)
        
        # Handle both progress object format and simple string messages
        if ($progress -is [hashtable] -or $progress -is [PSCustomObject]) {
            $percentage = if ($progress.Percentage) { $progress.Percentage } else { -1 }
            $stage = if ($progress.Stage) { $progress.Stage } else { "" }
            $currentOp = if ($progress.CurrentOperation) { $progress.CurrentOperation } else { $Status }
            $estimatedTime = if ($progress.EstimatedTimeRemaining) { $progress.EstimatedTimeRemaining } else { $null }
            
            # Build status text
            $statusText = $currentOp
            if ($stage) {
                $statusText = "$stage - $currentOp"
            }
            
            # Add estimated time if available
            if ($estimatedTime -and $estimatedTime.TotalSeconds -gt 0) {
                $minutes = [math]::Floor($estimatedTime.TotalMinutes)
                $seconds = [math]::Floor($estimatedTime.TotalSeconds % 60)
                if ($minutes -gt 0) {
                    $statusText += " (~${minutes}m ${seconds}s remaining)"
                } else {
                    $statusText += " (~${seconds}s remaining)"
                }
            }
            
            # Use Write-Progress for in-place updates (works in all PowerShell hosts)
            if ($percentage -ge 0) {
                Write-Progress -Activity $Activity -Status $statusText -PercentComplete $percentage -Id $script:lastProgressId
                
                # Also display ASCII progress bar on a new line (for better visibility)
                if ($percentage -ne $script:lastPercentage -or $stage -ne $script:lastStage) {
                    $barWidth = 40
                    $filled = [math]::Floor($percentage / 100 * $barWidth)
                    $bar = "[" + ("=" * $filled) + (" " * ($barWidth - $filled)) + "]"
                    Write-Host "`r$bar $percentage% - $statusText" -NoNewline -ForegroundColor Cyan
                    $script:lastPercentage = $percentage
                    $script:lastStage = $stage
                }
            } else {
                Write-Progress -Activity $Activity -Status $statusText -Id $script:lastProgressId
                Write-Host "`r[$Activity] $statusText" -NoNewline -ForegroundColor Cyan
            }
        } else {
            # Simple string message
            Write-Progress -Activity $Activity -Status $progress -Id $script:lastProgressId
            Write-Host "`r[$Activity] $progress" -NoNewline -ForegroundColor Cyan
        }
    }
}

function Start-TUI {
    # Load LogAnalysis module
    $logAnalysisPath = Join-Path $PSScriptRoot "LogAnalysis.ps1"
    if (Test-Path $logAnalysisPath) {
        try {
            . $logAnalysisPath
        } catch {
            Write-Warning "Failed to load LogAnalysis module: $_"
        }
    }
    
    # Detect environment for display (matching main script logic)
    $envDisplay = "FullOS"
    
    if ($env:SystemDrive -eq 'X:') {
        # X: drive indicates WinPE/WinRE
        if (Test-Path 'HKLM:\System\Setup') {
            $setupType = (Get-ItemProperty -Path 'HKLM:\System\Setup' -Name 'CmdLine' -ErrorAction SilentlyContinue).CmdLine
            if ($setupType -match 'recovery|WinRE') {
                $envDisplay = "WinRE"
            } else {
                $envDisplay = "WinPE"
            }
        } elseif (Test-Path 'HKLM:\System\CurrentControlSet\Control\MiniNT') {
            $envDisplay = "WinPE"
        } else {
            $envDisplay = "WinRE"
        }
    } elseif ($env:SystemDrive -ne 'X:' -and (Test-Path "$env:SystemDrive\Windows")) {
        $envDisplay = "FullOS"
    }
    
    do {
        Clear-Host
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host "  MIRACLE BOOT v7.2.0 - MS-DOS STYLE MODE (Cursor)" -ForegroundColor Cyan
        Write-Host "  Environment: $envDisplay" -ForegroundColor Gray
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1) List Windows Volumes (Sorted)" -ForegroundColor White
        Write-Host "2) Scan Storage Drivers (Detailed)" -ForegroundColor White
        Write-Host "3) Inject Drivers Offline (DISM)" -ForegroundColor White
        Write-Host "3A) Advanced Driver Tools (2025+ Systems)" -ForegroundColor Cyan
        Write-Host "4) Quick View BCD" -ForegroundColor White
        Write-Host "5) Edit BCD Entry" -ForegroundColor White
        Write-Host "6) Enable Network/Internet" -ForegroundColor Cyan
        Write-Host "7) Open ChatGPT Help (Browser/CLI)" -ForegroundColor Cyan
        Write-Host "8) Check Windows Install Failure Reasons" -ForegroundColor Cyan
        Write-Host "9) Boot Repair (with warnings)" -ForegroundColor Yellow
        Write-Host "A) Advanced Diagnostics" -ForegroundColor Magenta
        Write-Host "B) Boot Probability / Boot Health Check" -ForegroundColor Cyan
        Write-Host "C) Automated Boot Repair" -ForegroundColor Green
        Write-Host "D) System File Repair (SFC + DISM)" -ForegroundColor Green
        Write-Host "E) Disk Repair (chkdsk)" -ForegroundColor Green
        Write-Host "F) Comprehensive Diagnostics" -ForegroundColor Cyan
        Write-Host "G) Complete System Repair" -ForegroundColor Yellow
        Write-Host "H) In-Place Upgrade Readiness Check" -ForegroundColor Magenta
        Write-Host "I) Boot Chain Analysis (View Startup/Boot Logs)" -ForegroundColor Cyan
        Write-Host "J) Look Up Windows Error Code (Get troubleshooting help)" -ForegroundColor Yellow
        Write-Host "Z) Precision Boot Scan (ordered detection/remediation, dry-run default)" -ForegroundColor Yellow
        Write-Host "Y) Precision Parity (CLI vs GUI/TUI baseline)" -ForegroundColor Yellow
        Write-Host "X) Precision Quick Scan JSON export" -ForegroundColor Yellow
        Write-Host "W2) Precision Parity JSON export" -ForegroundColor Yellow
        Write-Host "U) Comprehensive Log Analysis (All Tiers - Root Cause)" -ForegroundColor Red
        Write-Host "V) Open Event Viewer" -ForegroundColor Cyan
        Write-Host "W) Crash Dump Analyzer (crashanalyze.exe)" -ForegroundColor Magenta
        Write-Host "K) Utilities Menu (Notepad, Registry, PowerShell, etc.)" -ForegroundColor White
        if ($envDisplay -eq "WinPE") {
            Write-Host "K2) Install Browser (Chrome/Firefox - WinPE only)" -ForegroundColor Cyan
        }
        Write-Host "L) Port Missing Drivers (Extract & Port Drivers)" -ForegroundColor Green
        Write-Host "M) Generate SAVE_ME.txt (Recovery Commands FAQ)" -ForegroundColor Yellow
        Write-Host "N) Disk Management Helper (diskpart guide)" -ForegroundColor Cyan
        Write-Host "O) System Restore Point Management" -ForegroundColor Magenta
        Write-Host "P) Network Diagnostics & Driver Management" -ForegroundColor Cyan
        Write-Host "R) Keyboard Symbol Helper (ALT codes, copy symbols)" -ForegroundColor White
        Write-Host "S) Ensure Repair-Install Ready (Critical for in-place upgrade)" -ForegroundColor Red
        Write-Host "T) Repair Templates (One-click fixes for common scenarios)" -ForegroundColor Magenta
        Write-Host "Q) Quit" -ForegroundColor Yellow
        Write-Host ""

        $c = Read-Host "Select"
        switch ($c) {
            "1" { 
                Write-Host "`nScanning volumes..." -ForegroundColor Gray
                Get-WindowsVolumes | Format-Table -AutoSize
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "2" {
                Write-Host "`nScanning for storage driver issues..." -ForegroundColor Gray
                Write-Host ""
                Write-Host (Get-MissingStorageDevices) -ForegroundColor Yellow
                $ans = Read-Host "`nAttempt to harvest drivers from a Windows drive? (Y/N)"
                if ($ans -eq 'Y' -or $ans -eq 'y') {
                    $src = Read-Host "Source drive (e.g. C)"
                    if ($src) {
                        Write-Host "Harvesting drivers from ${src}:..." -ForegroundColor Gray
                        Harvest-StorageDrivers "$($src):"
                        Write-Host "Loading drivers..." -ForegroundColor Gray
                        Load-Drivers-Live "X:\Harvested"
                        Write-Host "Drivers loaded. Press any key to continue..." -ForegroundColor Green
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                }
            }
            "3" {
                $win = Read-Host "Target Windows drive letter (e.g. C)"
                $path = Read-Host "Path to driver folder"
                if ($win -and $path) {
                    # Show warning before driver injection
                    $confirmed = Confirm-DestructiveOperation -CommandKey "driver_inject" -Command "Inject-Drivers-Offline $win $path" -Description "Inject drivers into offline Windows installation"
                    if ($confirmed) {
                        Write-Host "Injecting drivers into ${win}: using DISM..." -ForegroundColor Gray
                        Inject-Drivers-Offline $win $path
                        Write-Host "Driver injection complete. Press any key to continue..." -ForegroundColor Green
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    } else {
                        Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                }
            }
            "3A" {
                Write-Host "`nAdvanced Driver Tools (2025+ Systems)" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host "1) Advanced Storage Controller Detection" -ForegroundColor White
                Write-Host "2) Advanced Driver Matching & Injection" -ForegroundColor White
                Write-Host "3) Find Matching Drivers for Controllers" -ForegroundColor White
                Write-Host "Q) Back to Main Menu" -ForegroundColor Yellow
                Write-Host ""
                
                $subChoice = Read-Host "Select"
                switch ($subChoice) {
                    "1" {
                        Write-Host "`nAdvanced Storage Controller Detection (2025+ Systems)" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host "Detecting storage controllers using WMI, Registry, and PCI enumeration..." -ForegroundColor Gray
                Write-Host ""
                
                $controllers = Get-AdvancedStorageControllerInfo -IncludeNonCritical -Detailed
                
                if ($controllers.Count -eq 0) {
                    Write-Host "No storage controllers detected." -ForegroundColor Yellow
                } else {
                    Write-Host "Found $($controllers.Count) storage controller(s):" -ForegroundColor Green
                    Write-Host ""
                    
                    foreach ($controller in $controllers) {
                        $statusColor = if ($controller.HasDriver) { "Green" } else { "Red" }
                        $criticalMark = if ($controller.IsBootCritical) { " [BOOT-CRITICAL]" } else { "" }
                        
                        Write-Host "Controller: $($controller.Name)" -ForegroundColor White
                        Write-Host "  Type: $($controller.ControllerType)" -ForegroundColor Gray
                        Write-Host "  Vendor: $($controller.Vendor)" -ForegroundColor Gray
                        Write-Host "  Status: $($controller.Status)" -ForegroundColor $statusColor
                        Write-Host "  Has Driver: $($controller.HasDriver)" -ForegroundColor $statusColor
                        Write-Host "  Needs Driver: $($controller.NeedsDriver)" -ForegroundColor $(if ($controller.NeedsDriver) { "Red" } else { "Green" })
                        Write-Host "  Boot Critical: $($controller.IsBootCritical)$criticalMark" -ForegroundColor $(if ($controller.IsBootCritical) { "Yellow" } else { "Gray" })
                        Write-Host "  Required INF: $($controller.RequiredInf)" -ForegroundColor Gray
                        if ($controller.HardwareIDs -and $controller.HardwareIDs.Count -gt 0) {
                            Write-Host "  Hardware ID: $($controller.HardwareIDs[0])" -ForegroundColor Gray
                        }
                        Write-Host ""
                    }
                    
                    # Show summary
                    $needsDriver = ($controllers | Where-Object { $_.NeedsDriver }).Count
                    $bootCritical = ($controllers | Where-Object { $_.IsBootCritical }).Count
                    
                    Write-Host "Summary:" -ForegroundColor Cyan
                    Write-Host "  Total Controllers: $($controllers.Count)" -ForegroundColor White
                    Write-Host "  Boot-Critical: $bootCritical" -ForegroundColor $(if ($bootCritical -gt 0) { "Yellow" } else { "Gray" })
                    Write-Host "  Need Drivers: $needsDriver" -ForegroundColor $(if ($needsDriver -gt 0) { "Red" } else { "Green" })
                }
                
                Write-Host ""
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                    "2" {
                        Write-Host "`nAdvanced Driver Matching & Injection" -ForegroundColor Cyan
                        Write-Host "===============================================================" -ForegroundColor Gray
                        
                        $win = Read-Host "Target Windows drive letter (e.g. C)"
                        $path = Read-Host "Path to driver folder or INF file"
                        $validateOnly = (Read-Host "Validate only (don't inject)? (Y/N)") -eq 'Y'
                        $forceUnsigned = $false
                        
                        if (-not $validateOnly) {
                            $forceUnsigned = (Read-Host "Force unsigned drivers? (Y/N)") -eq 'Y'
                        }
                        
                        if ($win -and $path) {
                            Write-Host ""
                            Write-Host "Detecting storage controllers..." -ForegroundColor Gray
                            $controllers = Get-AdvancedStorageControllerInfo -IncludeNonCritical
                            
                            Write-Host "Found $($controllers.Count) controller(s), $($controllers | Where-Object { $_.NeedsDriver } | Measure-Object).Count need drivers" -ForegroundColor Gray
                            Write-Host ""
                            
                            if (-not $validateOnly) {
                                $confirmed = Confirm-DestructiveOperation -CommandKey "advanced_driver_inject" -Command "Start-AdvancedDriverInjection -WindowsDrive $win -DriverPath $path" -Description "Advanced driver injection with validation"
                                if (-not $confirmed) {
                                    Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                                    break
                                }
                            }
                            
                            $progressCallback = {
                                param($message, $percent)
                                Write-Host "$message ($percent%)" -ForegroundColor Gray
                            }
                            
                            $result = Start-AdvancedDriverInjection -WindowsDrive $win -DriverPath $path -ControllerInfo $controllers -ValidateOnly:$validateOnly -ForceUnsigned:$forceUnsigned -ProgressCallback $progressCallback
                            
                            Write-Host ""
                            Write-Host $result.Report -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                            
                            if ($result.Errors.Count -gt 0) {
                                Write-Host ""
                                Write-Host "Errors:" -ForegroundColor Red
                                foreach ($err in $result.Errors) {
                                    Write-Host "  - $err" -ForegroundColor Red
                                }
                            }
                            
                            Write-Host ""
                            Write-Host "Press any key to continue..." -ForegroundColor Gray
                            $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                        }
                    }
                    "3" {
                        Write-Host "`nFind Matching Drivers for Controllers" -ForegroundColor Cyan
                        Write-Host "===============================================================" -ForegroundColor Gray
                        
                        Write-Host "Detecting storage controllers..." -ForegroundColor Gray
                        $controllers = Get-AdvancedStorageControllerInfo -IncludeNonCritical
                        
                        if ($controllers.Count -eq 0) {
                            Write-Host "No storage controllers detected." -ForegroundColor Yellow
                            Write-Host "Press any key to continue..." -ForegroundColor Gray
                            $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                            break
                        }
                        
                        $win = Read-Host "`nWindows drive to search (e.g. C, or press Enter to skip)"
                        $searchPaths = @()
                        
                        do {
                            $searchPath = Read-Host "Additional driver search path (or press Enter to finish)"
                            if ($searchPath) {
                                $searchPaths += $searchPath
                            }
                        } while ($searchPath)
                        
                        Write-Host ""
                        Write-Host "Searching for matching drivers..." -ForegroundColor Gray
                        
                        $matches = Find-MatchingDrivers -ControllerInfo $controllers -SearchPaths $searchPaths -WindowsDrive $win
                        
                        Write-Host ""
                        Write-Host "Driver Matching Results:" -ForegroundColor Cyan
                        Write-Host "===============================================================" -ForegroundColor Gray
                        
                        foreach ($match in $matches) {
                            Write-Host ""
                            Write-Host "Controller: $($match.Controller)" -ForegroundColor White
                            Write-Host "  Type: $($match.ControllerType)" -ForegroundColor Gray
                            Write-Host "  Hardware ID: $($match.HardwareID)" -ForegroundColor Gray
                            Write-Host "  Required INF: $($match.RequiredInf)" -ForegroundColor Gray
                            Write-Host "  Matches Found: $($match.MatchesFound)" -ForegroundColor $(if ($match.MatchesFound -gt 0) { "Green" } else { "Red" })
                            
                            if ($match.BestMatches.Count -gt 0) {
                                Write-Host ""
                                Write-Host "  Best Matches:" -ForegroundColor Cyan
                                foreach ($bestMatch in $match.BestMatches) {
                                    $matchColor = switch ($bestMatch.MatchType) {
                                        "Exact" { "Green" }
                                        "Compatible" { "Yellow" }
                                        default { "Gray" }
                                    }
                                    Write-Host "    - $($bestMatch.DriverName)" -ForegroundColor $matchColor
                                    Write-Host "      Source: $($bestMatch.Source)" -ForegroundColor Gray
                                    Write-Host "      Match: $($bestMatch.MatchType) (Score: $($bestMatch.MatchScore))" -ForegroundColor Gray
                                    Write-Host "      Signed: $($bestMatch.IsSigned)" -ForegroundColor Gray
                                    Write-Host "      Path: $($bestMatch.INFPath)" -ForegroundColor DarkGray
                                }
                            } else {
                                Write-Host "  No matching drivers found." -ForegroundColor Red
                                Write-Host "  Recommendation: Download $($match.RequiredInf) from manufacturer" -ForegroundColor Yellow
                            }
                        }
                        
                        Write-Host ""
                        Write-Host "Press any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                    default {
                        # Back to main menu
                    }
                }
            }
            "4" { 
                Write-Host "`nBCD Entries:" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                bcdedit /enum
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "5" {
                Write-Host "`nCurrent BCD Entries:" -ForegroundColor Cyan
                bcdedit /enum | Select-String "identifier" | ForEach-Object { Write-Host $_.Line -ForegroundColor Gray }
                Write-Host ""
                $id = Read-Host "Enter BCD Identifier (GUID)"
                $name = Read-Host "Enter new description"
                if ($id -and $name) {
                    # Show warning before BCD modification
                    $confirmed = Confirm-DestructiveOperation -CommandKey "bcd_description" -Command "Set-BCDDescription $id $name" -Description "Change BCD entry description"
                    if ($confirmed) {
                        Set-BCDDescription $id $name
                        Write-Host "BCD entry updated successfully!" -ForegroundColor Green
                        Write-Host "Press any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    } else {
                        Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                }
            }
            "6" {
                Write-Host "`nEnabling network adapters..." -ForegroundColor Gray
                $result = Enable-NetworkWinRE
                Write-Host ""
                if ($result.Success) {
                    Write-Host $result.Message -ForegroundColor Green
                    Write-Host ""
                    Write-Host "Testing internet connectivity..." -ForegroundColor Gray
                    $internetTest = Test-InternetConnectivity
                    Write-Host $internetTest.Message -ForegroundColor $(if ($internetTest.Connected) { "Green" } else { "Yellow" })
                } else {
                    Write-Host $result.Message -ForegroundColor Red
                    if ($result.Errors.Count -gt 0) {
                        Write-Host "Errors:" -ForegroundColor Red
                        foreach ($err in $result.Errors) {
                            Write-Host "  - $err" -ForegroundColor Red
                        }
                    }
                }
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "7" {
                Write-Host "`nAttempting to open ChatGPT help..." -ForegroundColor Gray
                $result = Open-ChatGPTHelp
                Write-Host ""
                if ($result.Success) {
                    Write-Host $result.Message -ForegroundColor Green
                } else {
                    Write-Host $result.Message -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host $result.Instructions -ForegroundColor Cyan
                }
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "8" {
                $drive = Read-Host 'Enter target drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                Write-Host "`nAnalyzing Windows installation failure reasons for drive ${drive}:..." -ForegroundColor Gray
                Write-Host ""
                $analysis = Get-WindowsInstallFailureReasons -TargetDrive $drive
                Write-Host $analysis.Report
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "9" {
                Write-Host "`nBOOT REPAIR OPTIONS" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host ""
                Write-Host "W) Boot Repair Wizard (Guided Step-by-Step)" -ForegroundColor Green
                Write-Host "1) Rebuild BCD from Windows Installation (bcdboot)" -ForegroundColor White
                Write-Host "2) Fix Boot Files (bootrec /fixboot)" -ForegroundColor White
                Write-Host "3) Scan for Windows Installations (bootrec /scanos)" -ForegroundColor White
                Write-Host "4) Rebuild BCD (bootrec /rebuildbcd)" -ForegroundColor White
                Write-Host "B) Back to main menu" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "NOTE: Boot recovery operations may take longer on BitLocker-encrypted drives." -ForegroundColor Yellow
                Write-Host "      This is normal - please be patient during the repair process." -ForegroundColor Yellow
                Write-Host ""
                $bootChoice = Read-Host "Select boot repair option"
                
                if ($bootChoice -match '^[Ww]') {
                    # Launch Boot Repair Wizard
                    # Fix for WinPE: Handle null MyInvocation.MyCommand.Path
                    $scriptRoot = $null
                    if ($MyInvocation.MyCommand.Path) {
                        $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
                    } elseif ($PSScriptRoot) {
                        $scriptRoot = $PSScriptRoot
                    } else {
                        # Fallback: Try to get script root from current location
                        $scriptRoot = Split-Path -Parent (Get-Location).Path
                        # If we're in Helper directory, go up one level
                        if ((Split-Path -Leaf $scriptRoot) -eq "Helper") {
                            $scriptRoot = Split-Path -Parent $scriptRoot
                        }
                        # Try common locations
                        $possiblePaths = @(
                            (Join-Path $scriptRoot "Helper"),
                            (Join-Path (Split-Path -Parent $scriptRoot) "Helper"),
                            ".\Helper",
                            "..\Helper"
                        )
                        foreach ($path in $possiblePaths) {
                            if (Test-Path (Join-Path $path "BootRepairWizard.ps1")) {
                                $scriptRoot = $path
                                break
                            }
                        }
                    }
                    
                    $wizardPath = Join-Path $scriptRoot "BootRepairWizard.ps1"
                    if (-not (Test-Path $wizardPath)) {
                        # Try alternative: BootRepairWizard.ps1 in Helper subdirectory
                        $wizardPath = Join-Path (Join-Path $scriptRoot "Helper") "BootRepairWizard.ps1"
                    }
                    
                    if (Test-Path $wizardPath) {
                        & $wizardPath
                    } else {
                        Write-Host "`n[ERROR] Boot Repair Wizard not found." -ForegroundColor Red
                        Write-Host "Searched: $wizardPath" -ForegroundColor Gray
                        Write-Host "Press any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    continue
                }
                
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                switch ($bootChoice) {
                    '1' {
                        $command = "bcdboot ${drive}:\Windows"
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bcdboot" -Command $command -Description "Rebuild BCD from Windows installation" -TargetDrive $drive
                        if ($confirmed) {
                            Write-Host "`nExecuting: $command" -ForegroundColor Gray
                            $output = Invoke-Expression $command 2>&1
                            Write-Host $output
                            Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                            $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                        } else {
                            Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                            $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                        }
                    }
                    '2' {
                        $command = "bootrec /fixboot"
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_fixboot" -Command $command -Description "Fix boot sector" -TargetDrive $drive
                        if ($confirmed) {
                            Write-Host "`nExecuting: $command" -ForegroundColor Gray
                            $output = bootrec /fixboot 2>&1
                            Write-Host $output
                            Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                            $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                        } else {
                            Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                            $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                        }
                    }
                    '3' {
                        Write-Host "`nScanning for Windows installations..." -ForegroundColor Gray
                        $output = bootrec /scanos 2>&1
                        Write-Host $output
                        Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                    '4' {
                        $command = "bootrec /rebuildbcd"
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_rebuildbcd" -Command $command -Description "Rebuild BCD" -TargetDrive $drive
                        if ($confirmed) {
                            Write-Host "`nExecuting: $command" -ForegroundColor Gray
                            $output = bootrec /rebuildbcd 2>&1
                            Write-Host $output
                            Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                            $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                        } else {
                            Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                            $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                        }
                    }
                    'B' { continue }
                    'b' { continue }
                    default {
                        Write-Host "`nInvalid selection. Press any key to continue..." -ForegroundColor Red
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                }
            }
            "A" {
                Write-Host "`nADVANCED DIAGNOSTICS" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host ""
                Write-Host "1) Boot Diagnosis" -ForegroundColor White
                Write-Host "2) System Restore Check" -ForegroundColor White
                Write-Host "3) Reagentc Health Check" -ForegroundColor White
                Write-Host "4) OS Information" -ForegroundColor White
                Write-Host "B) Back to main menu" -ForegroundColor Yellow
                Write-Host ""
                $diagChoice = Read-Host "Select diagnostic option"
                
                $drive = Read-Host 'Target drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                switch ($diagChoice) {
                    '1' {
                        Write-Host "`nRunning boot diagnosis..." -ForegroundColor Gray
                        $diagnosis = Get-BootDiagnosis -TargetDrive $drive
                        Write-Host $diagnosis
                        Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                    '2' {
                        Write-Host "`nChecking System Restore..." -ForegroundColor Gray
                        $restoreInfo = Get-SystemRestoreInfo -TargetDrive $drive
                        Write-Host ''
                        Write-Host "SYSTEM RESTORE STATUS" -ForegroundColor Cyan
                        Write-Host "===============================================================" -ForegroundColor Gray
                        Write-Host $restoreInfo.Message
                        if ($restoreInfo.Enabled -and $restoreInfo.RestorePoints.Count -gt 0) {
                            Write-Host "`nRestore Points:" -ForegroundColor Cyan
                            $num = 1
                            foreach ($point in $restoreInfo.RestorePoints | Select-Object -First 10) {
                                Write-Host "$num. $($point.Description) - $($point.CreationTime)" -ForegroundColor Gray
                                $num++
                            }
                        }
                        Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                    '3' {
                        Write-Host "`nChecking Reagentc health..." -ForegroundColor Gray
                        $reagentcHealth = Get-ReagentcHealth
                        Write-Host ''
                        Write-Host "REAGENTC HEALTH" -ForegroundColor Cyan
                        Write-Host "===============================================================" -ForegroundColor Gray
                        Write-Host $reagentcHealth.Message
                        Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                    '4' {
                        Write-Host "`nGathering OS information..." -ForegroundColor Gray
                        $osInfo = Get-OSInfo -TargetDrive $drive
                        Write-Host ''
                        Write-Host "OPERATING SYSTEM INFORMATION" -ForegroundColor Cyan
                        Write-Host "===============================================================" -ForegroundColor Gray
                        if ($osInfo.Error) {
                            Write-Host "[ERROR] $($osInfo.Error)" -ForegroundColor Red
                        } else {
                            Write-Host "OS Name: $($osInfo.OSName)" -ForegroundColor White
                            Write-Host "Version: $($osInfo.Version)" -ForegroundColor White
                            Write-Host "Build: $($osInfo.BuildNumber)" -ForegroundColor White
                            Write-Host "Edition: $($osInfo.EditionID)" -ForegroundColor White
                            Write-Host "Architecture: $($osInfo.Architecture)" -ForegroundColor White
                            Write-Host "Language: $($osInfo.Language)" -ForegroundColor White
                        }
                        Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                    'B' { continue }
                    'b' { continue }
                    default {
                        Write-Host "`nInvalid selection. Press any key to continue..." -ForegroundColor Red
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                }
            }
            "a" {
                # Handle lowercase 'a' for Advanced Diagnostics
                $c = 'A'
                continue
            }
            "B" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nRunning boot probability / boot health check..." -ForegroundColor Gray
                Write-Host "This will assess the likelihood of successful boot..." -ForegroundColor Yellow
                Write-Host ""
                
                $bootHealth = Get-BootProbability -TargetDrive $drive
                
                Write-Host ""
                Write-Host $bootHealth.Report
                
                # Display probability prominently
                Write-Host ""
                Write-Host "===============================================================" -ForegroundColor Cyan
                Write-Host "  BOOT PROBABILITY: $($bootHealth.BootProbability)%" -ForegroundColor $(if ($bootHealth.BootProbability -ge 75) { "Green" } elseif ($bootHealth.BootProbability -ge 50) { "Yellow" } else { "Red" })
                Write-Host "  BOOT HEALTH: $($bootHealth.BootHealth)" -ForegroundColor $(if ($bootHealth.BootProbability -ge 75) { "Green" } elseif ($bootHealth.BootProbability -ge 50) { "Yellow" } else { "Red" })
                Write-Host "===============================================================" -ForegroundColor Cyan
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "b" {
                $c = 'B'
                continue
            }
            "Z" {
                $win = Read-Host 'Target Windows drive letter (default C)'
                if ([string]::IsNullOrWhiteSpace($win)) { $win = "C" }
                $win = $win.TrimEnd(':').ToUpper()
                $windowsRoot = "$win`:\Windows"

                $esp = Read-Host 'EFI System Partition letter (default Z)'
                if ([string]::IsNullOrWhiteSpace($esp)) { $esp = "Z" }
                $esp = $esp.TrimEnd(':').ToUpper()

                $applyResp = Read-Host 'Apply fixes? (Y/N, default N)'
                $apply = ($applyResp -match '^(y|yes)$')

                $logResp = Read-Host 'Offer to open logs after scan? (Y/N, default N)'
                $askLogs = ($logResp -match '^(y|yes)$')

                Write-Host ""
                $result = Start-PrecisionScan -WindowsRoot $windowsRoot -EspDriveLetter $esp -Apply:$apply -AskOpenLogs:$askLogs -PassThru -ActionLogPath "$env:TEMP\precision-actions.log"

                if ($result -and $result.Detections -and $result.Detections.Count -gt 0) {
                    Write-Host "`nPRECISION DETECTIONS:" -ForegroundColor Cyan
                    foreach ($det in $result.Detections) {
                        Write-Host "[$($det.Id)] $($det.Title)  Category: $($det.Category)" -ForegroundColor Yellow
                        foreach ($ev in $det.Evidence) { Write-Host "  Evidence: $ev" -ForegroundColor Gray }
                        if ($det.Remediate) {
                            Write-Host "  Remediation commands:" -ForegroundColor Cyan
                            foreach ($cmd in $det.Remediate) { Write-Host "    - $cmd" -ForegroundColor Gray }
                        }
                    }
                } else {
                    Write-Host "`nNo issues detected by precision scan." -ForegroundColor Green
                }

                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "z" {
                $c = 'Z'
                continue
            }
            "Y" {
                $win = Read-Host 'Target Windows drive letter (default C)'
                if ([string]::IsNullOrWhiteSpace($win)) { $win = "C" }
                $win = $win.TrimEnd(':').ToUpper()
                $windowsRoot = "$win`:\Windows"

                Write-Host ""
                Write-Host "Running precision parity harness for $windowsRoot (ESP Z)..." -ForegroundColor Gray
                try {
                    $parity = Invoke-PrecisionParityHarness -WindowsRoot $windowsRoot -EspDriveLetter "Z" -ActionLogPath "$env:TEMP\precision-actions.log"
                    # Basic parity assertion (CLI baseline vs this TUI call)
                    $matches = $true
                    if (-not $parity.Parity.Matches) { $matches = $false }

                    if ($parity.Parity.Matches) {
                        Write-Host "Parity: MATCH (CLI vs GUI/TUI)" -ForegroundColor Green
                    } else {
                        Write-Host "Parity differences:" -ForegroundColor Yellow
                        foreach ($d in $parity.Parity.Differences) { Write-Host "  - $d" -ForegroundColor Yellow }
                    }
                    if ($parity.Cli.Detections) {
                        Write-Host ""
                        Write-Host "CLI Detections:" -ForegroundColor Cyan
                        foreach ($det in $parity.Cli.Detections) {
                            Write-Host "[$($det.Id)] $($det.Title) (Cat: $($det.Category))" -ForegroundColor White
                        }
                    }
                } catch {
                    Write-Host "Precision parity harness failed: $_" -ForegroundColor Red
                }

                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "y" {
                $c = 'Y'
                continue
            }
            "X" {
                $win = Read-Host 'Target Windows drive letter (default C)'
                if ([string]::IsNullOrWhiteSpace($win)) { $win = "C" }
                $win = $win.TrimEnd(':').ToUpper()
                $windowsRoot = "$win`:\Windows"

                $save = Read-Host "Save to file? (path or press Enter for console only)"
                $outFile = $null
                if (-not [string]::IsNullOrWhiteSpace($save)) {
                    $outFile = $save
                }

                Write-Host ""
                Write-Host "Running precision quick scan (JSON) for $windowsRoot (ESP Z)..." -ForegroundColor Gray
                try {
                    $json = Invoke-PrecisionQuickScan -WindowsRoot $windowsRoot -EspDriveLetter "Z" -AsJson -IncludeBugcheck -OutFile $outFile
                    if ($outFile) {
                        Write-Host "JSON written to $outFile" -ForegroundColor Green
                    } else {
                        Write-Host $json
                    }
                } catch {
                    Write-Host "Precision JSON export failed: $_" -ForegroundColor Red
                }

                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "x" {
                $c = 'X'
                continue
            }
            "W2" {
                $win = Read-Host 'Target Windows drive letter (default C)'
                if ([string]::IsNullOrWhiteSpace($win)) { $win = "C" }
                $win = $win.TrimEnd(':').ToUpper()
                $windowsRoot = "$win`:\Windows"

                $outFile = Read-Host "Save parity JSON to file (path), or press Enter to print"
                if ([string]::IsNullOrWhiteSpace($outFile)) { $outFile = $null }

                Write-Host ""
                Write-Host "Running precision parity harness (JSON) for $windowsRoot (ESP Z)..." -ForegroundColor Gray
                try {
                    $json = Invoke-PrecisionParityHarness -WindowsRoot $windowsRoot -EspDriveLetter "Z" -AsJson -OutFile $outFile -ActionLogPath "$env:TEMP\precision-actions.log"
                    if ($outFile) {
                        Write-Host "Parity JSON written to $outFile" -ForegroundColor Green
                    } else {
                        Write-Host $json
                    }
                } catch {
                    Write-Host "Precision parity JSON export failed: $_" -ForegroundColor Red
                }

                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "C" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nRunning automated boot repair..." -ForegroundColor Gray
                $repairResult = Start-AutomatedBootRepair -TargetDrive $drive
                Write-Host ""
                Write-Host $repairResult.Report
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "c" {
                $c = 'C'
                continue
            }
            "D" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                $source = Read-Host 'Windows installation source path (optional for offline repair - press Enter to skip)'
                
                Write-Host "`nRunning system file repair (SFC + DISM)..." -ForegroundColor Gray
                Write-Host "This may take 15-30 minutes..." -ForegroundColor Yellow
                Write-Host ""
                
                # Enhanced progress callback for TUI with ASCII progress bars
                $progressCallback = New-TUIProgressCallback -Activity "System File Repair (SFC + DISM)" -Status "Repairing system files..."
                
                if ([string]::IsNullOrWhiteSpace($source)) {
                    $repairResult = Start-SystemFileRepair -TargetDrive $drive -ProgressCallback $progressCallback
                } else {
                    $repairResult = Start-SystemFileRepair -TargetDrive $drive -SourcePath $source -ProgressCallback $progressCallback
                }
                
                # Clear progress display
                Write-Progress -Activity "System File Repair" -Completed -Id 1
                Write-Host "" # New line after progress
                
                Write-Host ""
                Write-Host $repairResult.Report
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "c" {
                $c = 'C'
                continue
            }
            "D" {
                $drive = Read-Host "`nTarget drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                $recoverBad = Read-Host "Recover bad sectors? (Y/N - this can take hours)"
                $recoverBadSectors = ($recoverBad -eq 'Y' -or $recoverBad -eq 'y')
                
                Write-Host "`nRunning disk repair (chkdsk)..." -ForegroundColor Gray
                if ($recoverBadSectors) {
                    Write-Host "WARNING: Bad sector recovery can take 1-4 hours!" -ForegroundColor Yellow
                }
                Write-Host ""
                
                # Enhanced progress callback for TUI with ASCII progress bars
                $progressCallback = New-TUIProgressCallback -Activity "Disk Repair (CHKDSK)" -Status "Checking disk..."
                
                $repairResult = Start-DiskRepair -TargetDrive $drive -FixErrors -RecoverBadSectors:$recoverBadSectors -ProgressCallback $progressCallback
                
                # Clear progress display
                Write-Progress -Activity "Disk Repair" -Completed -Id 1
                Write-Host "" # New line after progress
                
                Write-Host ""
                Write-Host $repairResult.Report
                if ($repairResult.RequiresReboot) {
                    Write-Host "`nNOTE: chkdsk has been scheduled for next reboot." -ForegroundColor Yellow
                }
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "d" {
                $c = 'D'
                continue
            }
            "E" {
                $drive = Read-Host "`nTarget drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nRunning comprehensive diagnostics..." -ForegroundColor Gray
                Write-Host "This may take a few minutes..." -ForegroundColor Yellow
                Write-Host ""
                
                $diagResult = Start-ComprehensiveDiagnostics -TargetDrive $drive
                
                Write-Host ""
                Write-Host $diagResult.Report
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "e" {
                $c = 'E'
                continue
            }
            "F" {
                $drive = Read-Host "`nTarget drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nRunning comprehensive diagnostics..." -ForegroundColor Gray
                Write-Host "This may take a few minutes..." -ForegroundColor Yellow
                Write-Host ""
                
                $diagResult = Start-ComprehensiveDiagnostics -TargetDrive $drive
                
                Write-Host ""
                Write-Host $diagResult.Report
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "f" {
                $c = 'F'
                continue
            }
            "G" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nCOMPLETE SYSTEM REPAIR" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host ""
                Write-Host "This will run:" -ForegroundColor White
                Write-Host "  1. Comprehensive diagnostics" -ForegroundColor Gray
                Write-Host "  2. Create repair checkpoint" -ForegroundColor Gray
                Write-Host "  3. Disk repair (if needed)" -ForegroundColor Gray
                Write-Host "  4. System file repair (SFC + DISM)" -ForegroundColor Gray
                Write-Host "  5. Boot repair" -ForegroundColor Gray
                Write-Host ""
                Write-Host "This process can take 30 minutes to several hours." -ForegroundColor Yellow
                Write-Host ""
                $confirm = Read-Host "Do you want to proceed? (Y/N)"
                
                if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                    Write-Host "`nStarting complete system repair..." -ForegroundColor Gray
                    Write-Host ""
                    
                    $repairResult = Start-CompleteSystemRepair -TargetDrive $drive -SkipConfirmation
                    
                    Write-Host ""
                    Write-Host $repairResult.Report
                    Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                } else {
                    Write-Host "`nOperation cancelled. Press any key to continue..." -ForegroundColor Yellow
                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                }
            }
            "g" {
                $c = 'G'
                continue
            }
            "G" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nCOMPLETE SYSTEM REPAIR" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host ""
                Write-Host "This will run:" -ForegroundColor White
                Write-Host "  1. Comprehensive diagnostics" -ForegroundColor Gray
                Write-Host "  2. Create repair checkpoint" -ForegroundColor Gray
                Write-Host "  3. Disk repair (if needed)" -ForegroundColor Gray
                Write-Host "  4. System file repair (SFC + DISM)" -ForegroundColor Gray
                Write-Host "  5. Boot repair" -ForegroundColor Gray
                Write-Host ""
                Write-Host "This process can take 30 minutes to several hours." -ForegroundColor Yellow
                Write-Host ""
                $confirm = Read-Host "Do you want to proceed? (Y/N)"
                
                if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                    Write-Host "`nStarting complete system repair..." -ForegroundColor Gray
                    Write-Host ""
                    
                    $repairResult = Start-CompleteSystemRepair -TargetDrive $drive -SkipConfirmation
                    
                    Write-Host ""
                    Write-Host $repairResult.Report
                    Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                } else {
                    Write-Host "`nOperation cancelled. Press any key to continue..." -ForegroundColor Yellow
                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                }
            }
            "g" {
                $c = 'G'
                continue
            }
            "H" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nRunning in-place upgrade readiness check..." -ForegroundColor Gray
                Write-Host "This will analyze Windows logs and system health..." -ForegroundColor Yellow
                Write-Host "Checking: nbtlog.txt, `$WINDOWS.~BT, `$Windows.~WS, CBS logs, etc." -ForegroundColor Cyan
                Write-Host ""
                
                $readiness = Get-InPlaceUpgradeReadiness -TargetDrive $drive
                
                Write-Host ""
                Write-Host $readiness.Report
                
                # Display readiness status prominently
                Write-Host ""
                Write-Host "===============================================================" -ForegroundColor $(if ($readiness.ReadyForInPlaceUpgrade) { "Green" } else { "Red" })
                if ($readiness.ReadyForInPlaceUpgrade) {
                    Write-Host "  STATUS: READY FOR IN-PLACE UPGRADE" -ForegroundColor Green
                } else {
                    Write-Host "  STATUS: BLOCKED - NOT READY FOR IN-PLACE UPGRADE" -ForegroundColor Red
                    Write-Host "  BLOCKERS FOUND: $($readiness.Blockers.Count)" -ForegroundColor Red
                }
                Write-Host "===============================================================" -ForegroundColor $(if ($readiness.ReadyForInPlaceUpgrade) { "Green" } else { "Red" })
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "h" {
                $c = 'H'
                continue
            }
            "I" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nAnalyzing boot chain to identify failure point..." -ForegroundColor Gray
                Write-Host "This will check all boot stages and identify where Windows is failing..." -ForegroundColor Yellow
                Write-Host ""
                
                $chainAnalysis = Get-BootChainAnalysis -TargetDrive $drive
                
                Write-Host ""
                Write-Host $chainAnalysis.Report
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "i" {
                $c = 'I'
                continue
            }
            "J" {
                Write-Host "`nWINDOWS ERROR CODE LOOKUP" -ForegroundColor Yellow
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host ""
                Write-Host "Enter a Windows error code to get detailed troubleshooting information." -ForegroundColor White
                Write-Host "Examples: 0xc000000e, 0x80070002, 0x0000007B" -ForegroundColor Gray
                Write-Host ""
                
                $errorCode = Read-Host "Enter error code"
                if ($errorCode) {
                    $drive = Read-Host "Target drive (e.g., C) [default: C]"
                    if (-not $drive) { $drive = "C" }
                    $drive = $drive.TrimEnd(':').ToUpper()
                    
                    Write-Host ""
                    Write-Host "Looking up error code: $errorCode" -ForegroundColor Gray
                    Write-Host ""
                    
                    $errorInfo = Get-WindowsErrorCodeInfo -ErrorCode $errorCode -TargetDrive $drive
                    if ($errorInfo) {
                        Write-Host $errorInfo.Report
                    }

                    # Precision mapping
                    $prec = Search-PrecisionErrorCode -Code $errorCode
                    if ($prec) {
                        Write-Host ""
                        Write-Host "PRECISION MAPPING: $($prec.SuggestedTC)" -ForegroundColor Cyan
                        Write-Host "Notes: $($prec.Notes)" -ForegroundColor Gray
                    }

                    # Minidump summary for quick triage
                    $dumpSummary = Get-PrecisionDumpSummary -WindowsRoot "$drive`:\Windows" -Max 3
                    if ($dumpSummary -and $dumpSummary.Count -gt 0) {
                        Write-Host ""
                        Write-Host "Recent minidumps on $drive`: (latest 3)" -ForegroundColor Cyan
                        foreach ($d in $dumpSummary) {
                            Write-Host "  $($d.LastWriteTime)  $($d.SizeMB) MB  $($d.Path)" -ForegroundColor Gray
                        }
                    }

                    # Recent bugcheck from System.evtx (offline-safe)
                    $bug = Get-PrecisionRecentBugcheck -WindowsRoot "$drive`:\Windows"
                    if ($bug -and $bug.Code) {
                        $hex = ("0x{0:X}" -f $bug.Code)
                        Write-Host ""
                        Write-Host "Recent BugCheck (System.evtx): $hex Params: $($bug.Params -join ', ')" -ForegroundColor Cyan
                        Write-Host "Time: $($bug.TimeCreated)" -ForegroundColor Gray
                    }
                    
                    Write-Host ""
                    Write-Host "Press any key to continue..." -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                }
            }
            "j" {
                $c = 'J'
                continue
            }
            "U" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nCOMPREHENSIVE LOG ANALYSIS - ROOT CAUSE DIAGNOSTICS" -ForegroundColor Red
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host ""
                Write-Host "Gathering logs from all tiers..." -ForegroundColor Yellow
                Write-Host "  TIER 1: Crash dumps (MEMORY.DMP, LiveKernelReports, Minidumps)" -ForegroundColor Cyan
                Write-Host "  TIER 2: Boot pipeline logs (Setup logs, ntbtlog.txt)" -ForegroundColor Cyan
                Write-Host "  TIER 3: Event logs (System.evtx, SrtTrail.txt)" -ForegroundColor Cyan
                Write-Host "  TIER 4: Boot structure (BCD, Registry)" -ForegroundColor Cyan
                Write-Host "  TIER 5: Hardware/image context" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "This may take several moments..." -ForegroundColor Gray
                Write-Host ""
                
                try {
                    $analysis = Get-ComprehensiveLogAnalysis -TargetDrive $drive
                    
                    Write-Host ""
                    Write-Host $analysis.Report
                    
                    if ($analysis.RootCauseSummary) {
                        Write-Host ""
                        Write-Host "ROOT CAUSE SUMMARY" -ForegroundColor Yellow
                        Write-Host "-" * 80 -ForegroundColor Gray
                        Write-Host $analysis.RootCauseSummary
                    }
                    
                    if ($analysis.Recommendations.Count -gt 0) {
                        Write-Host ""
                        Write-Host "RECOMMENDATIONS:" -ForegroundColor Green
                        Write-Host "-" * 80 -ForegroundColor Gray
                        $counter = 1
                        foreach ($rec in $analysis.Recommendations) {
                            Write-Host "$counter. $rec" -ForegroundColor White
                            $counter++
                        }
                    }
                    
                } catch {
                    Write-Host ""
                    Write-Host "ERROR: Failed to perform comprehensive log analysis" -ForegroundColor Red
                    Write-Host $_.Exception.Message -ForegroundColor Yellow
                }
                
                Write-Host ""
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "u" {
                $c = 'U'
                continue
            }
            "V" {
                Write-Host "`nOpening Event Viewer..." -ForegroundColor Gray
                try {
                    $result = Open-EventViewer
                    if ($result.Success) {
                        Write-Host "Event Viewer opened successfully." -ForegroundColor Green
                    } else {
                        Write-Host "Failed to open Event Viewer: $($result.Message)" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "Failed to open Event Viewer: $_" -ForegroundColor Red
                }
                Write-Host ""
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "v" {
                $c = 'V'
                continue
            }
            "W" {
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                # Check for MEMORY.DMP
                $memoryDump = "$drive`:\Windows\MEMORY.DMP"
                $dumpPath = ""
                
                if (Test-Path $memoryDump) {
                    Write-Host "`nMEMORY.DMP found at: $memoryDump" -ForegroundColor Green
                    $useDump = Read-Host "Do you want to analyze this dump file? (Y/N)"
                    if ($useDump -eq 'Y' -or $useDump -eq 'y') {
                        $dumpPath = $memoryDump
                    }
                } else {
                    Write-Host "`nMEMORY.DMP not found at: $memoryDump" -ForegroundColor Yellow
                    Write-Host "Crash Analyzer will open without a file." -ForegroundColor Gray
                }
                
                Write-Host ""
                Write-Host "Launching Crash Dump Analyzer..." -ForegroundColor Gray
                
                try {
                    $result = Start-CrashAnalyzer -DumpPath $dumpPath
                    if ($result.Success) {
                        Write-Host "Crash Analyzer launched: $($result.Message)" -ForegroundColor Green
                    } else {
                        Write-Host "Failed to launch Crash Analyzer: $($result.Message)" -ForegroundColor Red
                        Write-Host "Please ensure crashanalyze.exe is available in Helper\CrashAnalyzer\" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "Failed to launch Crash Analyzer: $_" -ForegroundColor Red
                }
                
                Write-Host ""
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "w" {
                $c = 'W'
                continue
            }
            "K" {
                Write-Host "`nUTILITIES MENU" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host ""
                Write-Host "1) Notepad" -ForegroundColor White
                Write-Host "2) Registry Editor" -ForegroundColor White
                Write-Host "3) PowerShell" -ForegroundColor White
                Write-Host "4) System Restore" -ForegroundColor White
                Write-Host "5) Command Prompt" -ForegroundColor White
                Write-Host "6) Disk Management" -ForegroundColor White
                Write-Host "7) Event Viewer" -ForegroundColor White
                Write-Host "8) Restart Windows Explorer" -ForegroundColor White
                Write-Host "B) Back to main menu" -ForegroundColor Yellow
                Write-Host ""
                
                $utilChoice = Read-Host "Select utility"
                
                switch ($utilChoice) {
                    '1' {
                        $result = Start-UtilitiesMenu -Utility "Notepad"
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    '2' {
                        $result = Start-UtilitiesMenu -Utility "Registry"
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    '3' {
                        $result = Start-UtilitiesMenu -Utility "PowerShell"
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    '4' {
                        $result = Start-UtilitiesMenu -Utility "SystemRestore"
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    "5" {
                        $result = Start-UtilitiesMenu -Utility "CommandPrompt"
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    "6" {
                        $result = Start-UtilitiesMenu -Utility "DiskManagement"
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    "7" {
                        $result = Start-UtilitiesMenu -Utility "EventViewer"
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    "8" {
                        Write-Host "`nRestarting Windows Explorer..." -ForegroundColor Yellow
                        $result = Restart-WindowsExplorer
                        if ($result.Success) {
                            Write-Host $result.Message -ForegroundColor Green
                        } else {
                            Write-Host $result.Message -ForegroundColor Red
                        }
                        Write-Host ""
                        Write-Host "Press any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    }
                    'B' { continue }
                    'b' { continue }
                    default {
                        Write-Host 'Invalid selection.' -ForegroundColor Red
                    }
                }
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "j" {
                $c = 'J'
                continue
            }
            "K" {
                if ($envDisplay -ne "WinPE") {
                    Write-Host "`nBrowser installation is only available in WinPE environment." -ForegroundColor Yellow
                    Write-Host "Current environment: $envDisplay" -ForegroundColor Gray
                    Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    continue
                }
                
                Write-Host "`nBROWSER INSTALLATION (WinPE Only)" -ForegroundColor Cyan
                Write-Host "===============================================================" -ForegroundColor Gray
                Write-Host ""
                Write-Host "1) Install Chrome Portable" -ForegroundColor White
                Write-Host "2) Install Firefox Portable" -ForegroundColor White
                Write-Host "B) Back to main menu" -ForegroundColor Yellow
                Write-Host ""
                
                $browserChoice = Read-Host "Select browser"
                
                switch ($browserChoice) {
                    '1' {
                        $result = Install-PortableBrowser -Browser "Chrome"
                        Write-Host ''
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    '2' {
                        $result = Install-PortableBrowser -Browser "Firefox"
                        Write-Host ''
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { "Green" } else { "Yellow" })
                    }
                    'B' { continue }
                    'b' { continue }
                    default {
                        Write-Host 'Invalid selection.' -ForegroundColor Red
                    }
                }
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "k" {
                $c = 'K'
                continue
            }
            "L" {
                $sourceDrive = Read-Host 'Source drive with working Windows (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($sourceDrive)) {
                    $sourceDrive = "C"
                }
                $sourceDrive = $sourceDrive.TrimEnd(':').ToUpper()
                
                $outputFolder = Read-Host "Output folder for drivers (press Enter for default: $env:SystemDrive\DriverPort)"
                if ([string]::IsNullOrWhiteSpace($outputFolder)) {
                    $outputFolder = "$env:SystemDrive\DriverPort"
                }
                
                Write-Host "`nPorting missing drivers..." -ForegroundColor Gray
                Write-Host "This will identify missing drivers and extract them from $sourceDrive`:..." -ForegroundColor Yellow
                Write-Host ""
                
                $result = Get-MissingDriversForPorting -SourceDrive $sourceDrive -OutputFolder $outputFolder
                
                Write-Host ""
                Write-Host $result.Instructions
                Write-Host ""
                Write-Host "Drivers ported: $($result.PortedDrivers.Count)" -ForegroundColor Green
                Write-Host "Missing drivers detected: $($result.MissingDrivers.Count)" -ForegroundColor $(if ($result.MissingDrivers.Count -gt 0) { "Yellow" } else { "Green" })
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "l" {
                $c = 'L'
                continue
            }
            "M" {
                $outputPath = Read-Host "`nOutput path for SAVE_ME.txt (press Enter for default: $env:SystemDrive\SAVE_ME.txt)"
                if ([string]::IsNullOrWhiteSpace($outputPath)) {
                    $outputPath = "$env:SystemDrive\SAVE_ME.txt"
                }
                
                Write-Host "`nGenerating SAVE_ME.txt with recovery commands and FAQ..." -ForegroundColor Gray
                Write-Host ""
                
                $result = Generate-SaveMeTxt -OutputPath $outputPath
                
                if ($result.Success) {
                    Write-Host '[SUCCESS] SAVE_ME.txt generated!' -ForegroundColor Green
                    Write-Host "Location: $($result.Path)" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Opening in Notepad..." -ForegroundColor Yellow
                    Start-Process notepad.exe -ArgumentList $result.Path -ErrorAction SilentlyContinue
                } else {
                    Write-Host "[ERROR] $($result.Message)" -ForegroundColor Red
                }
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            "m" {
                $c = 'M'
                continue
            }
            "N" {
                Start-DiskManagementHelper -Interactive
            }
            "n" {
                $c = 'N'
                continue
            }
            'O' {
                Write-Host ''
                Write-Host 'SYSTEM RESTORE POINT MANAGEMENT' -ForegroundColor Cyan
                Write-Host '===============================================================' -ForegroundColor Gray
                Write-Host ""
                Write-Host "1) Create Restore Point" -ForegroundColor White
                Write-Host "2) List Restore Points" -ForegroundColor White
                Write-Host "3) Restore from Restore Point" -ForegroundColor Yellow
                Write-Host "4) Manage Restore Points (Cleanup, Health Check)" -ForegroundColor White
                Write-Host "B) Back to main menu" -ForegroundColor Yellow
                Write-Host ""
                
                $restoreChoice = Read-Host 'Select option'
                
                switch ($restoreChoice) {
                    '1' {
                        $description = Read-Host 'Restore point description (press Enter for default)'
                        if ([string]::IsNullOrWhiteSpace($description)) {
                            $description = 'Miracle Boot Manual Restore Point'
                        }
                        
                        Write-Host ''
                        Write-Host 'Creating restore point...' -ForegroundColor Gray
                        $result = Create-SystemRestorePoint -Description $description -OperationType 'Manual'
                        
                        if ($result.Success) {
                            Write-Host "[SUCCESS] $($result.Message)" -ForegroundColor Green
                            if ($result.RestorePointID) {
                                Write-Host "Restore Point ID: $($result.RestorePointID)" -ForegroundColor Cyan
                            }
                        } else {
                            Write-Host "[ERROR] $($result.Message)" -ForegroundColor Red
                        }
                    }
                    '2' {
                        Write-Host ''
                        Write-Host 'Retrieving restore points...' -ForegroundColor Gray
                        $restorePoints = Get-SystemRestorePoints -Limit 20
                        
                        if ($restorePoints.Count -gt 0) {
                            Write-Host ''
                            Write-Host 'AVAILABLE RESTORE POINTS:' -ForegroundColor Cyan
                            Write-Host '─────────────────────────────────────────────────────' -ForegroundColor Gray
                            foreach ($point in $restorePoints) {
                                Write-Host "ID: $($point.SequenceNumber)" -ForegroundColor White
                                Write-Host "  Description: $($point.Description)" -ForegroundColor Yellow
                                Write-Host "  Created: $($point.CreationTime)" -ForegroundColor Gray
                                Write-Host "  Type: $($point.RestorePointType)" -ForegroundColor Gray
                                Write-Host ''
                            }
                        } else {
                            Write-Host '[INFO] No restore points found or System Restore is disabled.' -ForegroundColor Yellow
                        }
                    }
                    '3' {
                        Write-Host ''
                        Write-Host "WARNING: This will restore your system to a previous state!" -ForegroundColor Red
                        Write-Host "All changes made after the restore point will be lost." -ForegroundColor Yellow
                        Write-Host ''
                        $confirm = Read-Host 'Are you absolutely sure? Type YES to confirm'
                        
                        if ($confirm -eq "YES") {
                            $restorePoints = Get-SystemRestorePoints -Limit 20
                            if ($restorePoints.Count -gt 0) {
                                Write-Host ''
                                Write-Host "Available restore points:" -ForegroundColor Cyan
                                foreach ($point in $restorePoints) {
                                    Write-Host "  ID $($point.SequenceNumber) - $($point.Description) - $($point.CreationTime)" -ForegroundColor Gray
                                }
                                Write-Host ''
                                $pointId = Read-Host "Enter restore point ID"
                                
                                $result = Restore-FromSystemRestorePoint -RestorePointID ([int]$pointId) -Confirm
                                if ($result.Success) {
                                    Write-Host "[SUCCESS] $($result.Message)" -ForegroundColor Green
                                    Write-Host "System will restart to complete restore." -ForegroundColor Yellow
                                } else {
                                    Write-Host "[ERROR] $($result.Message)" -ForegroundColor Red
                                }
                            } else {
                                Write-Host '[ERROR] No restore points available.' -ForegroundColor Red
                            }
                        } else {
                            Write-Host 'Restore cancelled.' -ForegroundColor Yellow
                        }
                    }
                    '4' {
                        Write-Host ''
                        Write-Host 'Managing restore points...' -ForegroundColor Gray
                        $result = Manage-SystemRestorePoints -HealthCheck -CleanupOld -KeepDays 30
                        
                        Write-Host ''
                        Write-Host "HEALTH STATUS: $($result.HealthStatus)" -ForegroundColor $(if ($result.HealthStatus -eq 'Healthy') { 'Green' } else { 'Yellow' })
                        Write-Host "Restore Points Deleted: $($result.RestorePointsDeleted)" -ForegroundColor Cyan
                        Write-Host ''
                        Write-Host 'Actions Taken:' -ForegroundColor Cyan
                        foreach ($action in $result.ActionsTaken) {
                            Write-Host "  - $action" -ForegroundColor Gray
                        }
                        Write-Host ''
                        Write-Host $result.Message -ForegroundColor $(if ($result.Success) { 'Green' } else { 'Yellow' })
                    }
                    'B' { continue }
                    'b' { continue }
                    default {
                        Write-Host 'Invalid selection.' -ForegroundColor Red
                    }
                }
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            'o' {
                $c = 'O'
                continue
            }
            'P' {
                if (Get-Command Invoke-NetworkDiagnostics -ErrorAction SilentlyContinue) {
                    Write-Host ''
                    Write-Host 'NETWORK DIAGNOSTICS and DRIVER MANAGEMENT' -ForegroundColor Cyan
                    Write-Host '===============================================================' -ForegroundColor Gray
                    Write-Host ""
                    $result = Invoke-NetworkDiagnostics
                    Write-Host $result.Report
                } else {
                    Write-Host ''
                    Write-Host 'Network Diagnostics module not available.' -ForegroundColor Yellow
                    Write-Host 'This feature requires NetworkDiagnostics.ps1 to be loaded.' -ForegroundColor Gray
                }
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            'p' {
                $c = 'P'
                continue
            }
            'R' {
                if (Get-Command Show-SymbolHelper -ErrorAction SilentlyContinue) {
                    Show-SymbolHelper
                } else {
                    Write-Host ''
                    Write-Host 'Keyboard Symbol Helper not available.' -ForegroundColor Yellow
                    Write-Host 'This feature requires KeyboardSymbols.ps1 to be loaded.' -ForegroundColor Gray
                }
            }
            'r' {
                $c = 'R'
                continue
            }
            'S' {
                # Check if we're in WinPE/WinRE - show offline repair install info option
                $envType = Get-EnvironmentType
                if ($envType -eq 'WinPE' -or $envType -eq 'WinRE') {
                    Write-Host ''
                    Write-Host 'REPAIR-INSTALL OPTIONS (WinPE/WinRE Environment)' -ForegroundColor Cyan
                    Write-Host '===============================================================' -ForegroundColor Gray
                    Write-Host ''
                    Write-Host '1) Ensure Repair-Install Ready (Prepare system for repair install)' -ForegroundColor White
                    Write-Host '2) View Offline Repair Install Information (How offline repair works)' -ForegroundColor Yellow
                    Write-Host '0) Back to main menu' -ForegroundColor Gray
                    Write-Host ''
                    
                    $subChoice = Read-Host 'Select option'
                    
                    if ($subChoice -eq '2') {
                        Write-Host ''
                        Write-Host 'OFFLINE REPAIR INSTALL FORCER - DETAILED INFORMATION' -ForegroundColor Yellow
                        Write-Host '===============================================================' -ForegroundColor Gray
                        Write-Host ''
                        
                        $instructions = Get-OfflineRepairInstallInstructions
                        Write-Host $instructions
                        
                        Write-Host ''
                        Write-Host 'Press any key to continue...' -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                        continue
                    } elseif ($subChoice -eq '0' -or [string]::IsNullOrWhiteSpace($subChoice)) {
                        continue
                    }
                    # If choice is '1' or invalid, fall through to normal repair-install readiness
                }
                
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = 'C'
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host ''
                Write-Host 'REPAIR-INSTALL READINESS ENGINE' -ForegroundColor Red
                Write-Host '===============================================================' -ForegroundColor Gray
                Write-Host ""
                Write-Host 'This will ensure Windows is ready for in-place upgrade (Keep apps + files)' -ForegroundColor Yellow
                Write-Host ""
                
                $fix = Read-Host 'Automatically fix blockers? (Y/N, default Y)'
                $fixBlockers = ($fix -ne 'N' -and $fix -ne 'n')
                
                Write-Host ""
                Write-Host 'Running repair-install readiness check...' -ForegroundColor Cyan
                Write-Host ""
                
                # Progress callback
                $progressCallback = {
                    param($message)
                    Write-Host $message -ForegroundColor Gray
                }
                
                $result = Start-RepairInstallReadiness -TargetDrive $drive -FixBlockers:$fixBlockers -ProgressCallback $progressCallback
                
                Write-Host ""
                Write-Host $result.Report
                Write-Host ""
                
                if ($result.Eligible) {
                    Write-Host '[SUCCESS] System is ready for repair install!' -ForegroundColor Green
                    Write-Host 'You can now run: setup.exe /auto upgrade /quiet' -ForegroundColor Cyan
                } else {
                    Write-Host '[WARNING] System is not fully ready. Review blockers above.' -ForegroundColor Yellow
                }
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            's' {
                $c = 'S'
                continue
            }
            'T' {
                Write-Host ''
                Write-Host 'REPAIR TEMPLATES - ONE-CLICK FIXES' -ForegroundColor Magenta
                Write-Host '===============================================================' -ForegroundColor Gray
                Write-Host ''
                
                $templates = Get-RepairTemplates
                
                Write-Host 'Available Repair Templates:' -ForegroundColor Cyan
                Write-Host ''
                $num = 1
                foreach ($template in $templates) {
                    $riskColor = switch ($template.RiskLevel) {
                        'Low' { 'Green' }
                        'Medium' { 'Yellow' }
                        'High' { 'Red' }
                        default { 'White' }
                    }
                    Write-Host "$num) $($template.Name)" -ForegroundColor White
                    Write-Host "   $($template.Description)" -ForegroundColor Gray
                    Write-Host "   Time: $($template.EstimatedTime) | Risk: " -NoNewline
                    Write-Host $template.RiskLevel -ForegroundColor $riskColor
                    Write-Host ''
                    $num++
                }
                Write-Host '0) Back to main menu' -ForegroundColor Yellow
                Write-Host ''
                
                $templateChoice = Read-Host 'Select template (number)'
                
                if ($templateChoice -eq '0' -or [string]::IsNullOrWhiteSpace($templateChoice)) {
                    continue
                }
                
                $selectedTemplate = $null
                if ([int]::TryParse($templateChoice, [ref]$null)) {
                    $templateIndex = [int]$templateChoice - 1
                    if ($templateIndex -ge 0 -and $templateIndex -lt $templates.Count) {
                        $selectedTemplate = $templates[$templateIndex]
                    }
                }
                
                if (-not $selectedTemplate) {
                    Write-Host 'Invalid template selection.' -ForegroundColor Red
                    Write-Host ''
                    Write-Host 'Press any key to continue...' -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    continue
                }
                
                $drive = Read-Host "Target Windows drive letter (e.g. C or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = 'C'
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host ''
                Write-Host "Selected Template: $($selectedTemplate.Name)" -ForegroundColor Cyan
                Write-Host "Description: $($selectedTemplate.Description)" -ForegroundColor Gray
                Write-Host "Estimated Time: $($selectedTemplate.EstimatedTime)" -ForegroundColor Gray
                Write-Host "Risk Level: $($selectedTemplate.RiskLevel)" -ForegroundColor $(switch ($selectedTemplate.RiskLevel) { 'Low' { 'Green' } 'Medium' { 'Yellow' } 'High' { 'Red' } default { 'White' } })
                Write-Host ''
                Write-Host 'Steps to execute:' -ForegroundColor Yellow
                foreach ($step in $selectedTemplate.Steps) {
                    Write-Host "  • $step" -ForegroundColor Gray
                }
                Write-Host ''
                Write-Host "Target Drive: $drive`:" -ForegroundColor Cyan
                Write-Host ''
                
                $confirm = Read-Host 'Type YES to execute this template'
                if ($confirm -ne 'YES') {
                    Write-Host 'Template execution cancelled.' -ForegroundColor Yellow
                    Write-Host ''
                    Write-Host 'Press any key to continue...' -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
                    continue
                }
                
                Write-Host ''
                Write-Host 'Executing template...' -ForegroundColor Cyan
                Write-Host ''
                
                # Progress callback
                $progressCallback = {
                    param($message)
                    Write-Host $message -ForegroundColor Gray
                }
                
                $result = Start-RepairTemplate -TemplateId $selectedTemplate.Id -TargetDrive $drive -ProgressCallback $progressCallback
                
                Write-Host ''
                Write-Host $result.Report
                Write-Host ''
                
                if ($result.Success) {
                    Write-Host '[SUCCESS] Template execution completed successfully!' -ForegroundColor Green
                } else {
                    Write-Host '[WARNING] Template execution completed with some issues.' -ForegroundColor Yellow
                    if ($result.Errors.Count -gt 0) {
                        Write-Host 'Errors:' -ForegroundColor Red
                        foreach ($errItem in $result.Errors) {
                            Write-Host "  • $errItem" -ForegroundColor Red
                        }
                    }
                }
                
                Write-Host ''
                Write-Host 'Press any key to continue...' -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
            't' {
                $c = 'T'
                continue
            }
            'Q' { 
                Write-Host ''
                Write-Host 'Exiting...' -ForegroundColor Yellow
                break 
            }
            'q' { 
                Write-Host ''
                Write-Host 'Exiting...' -ForegroundColor Yellow
                break 
            }
            default {
                Write-Host 'Invalid selection. Press any key to continue...' -ForegroundColor Red
                $null = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)
            }
        }
    } while ($c -ne 'Q' -and $c -ne 'q')
}
