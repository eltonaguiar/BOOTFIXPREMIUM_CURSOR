function Start-TUI {
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
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  MIRACLE BOOT v7.2.0 - MS-DOS STYLE MODE" -ForegroundColor Cyan
        Write-Host "  Environment: $envDisplay" -ForegroundColor Gray
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1) List Windows Volumes (Sorted)" -ForegroundColor White
        Write-Host "2) Scan Storage Drivers (Detailed)" -ForegroundColor White
        Write-Host "3) Inject Drivers Offline (DISM)" -ForegroundColor White
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
        Write-Host "Q) Quit" -ForegroundColor Yellow
        Write-Host ""

        $c = Read-Host "Select"
        switch ($c) {
            "1" { 
                Write-Host "`nScanning volumes..." -ForegroundColor Gray
                Get-WindowsVolumes | Format-Table -AutoSize
                Write-Host "Press any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    } else {
                        Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                }
            }
            "4" { 
                Write-Host "`nBCD Entries:" -ForegroundColor Cyan
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
                bcdedit /enum
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    } else {
                        Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "8" {
                $drive = Read-Host "`nEnter target drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                Write-Host "`nAnalyzing Windows installation failure reasons for drive ${drive}:..." -ForegroundColor Gray
                Write-Host ""
                $analysis = Get-WindowsInstallFailureReasons -TargetDrive $drive
                Write-Host $analysis.Report
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "9" {
                Write-Host "`nBOOT REPAIR OPTIONS" -ForegroundColor Cyan
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
                Write-Host ""
                Write-Host "1) Rebuild BCD from Windows Installation (bcdboot)" -ForegroundColor White
                Write-Host "2) Fix Boot Files (bootrec /fixboot)" -ForegroundColor White
                Write-Host "3) Scan for Windows Installations (bootrec /scanos)" -ForegroundColor White
                Write-Host "4) Rebuild BCD (bootrec /rebuildbcd)" -ForegroundColor White
                Write-Host "B) Back to main menu" -ForegroundColor Yellow
                Write-Host ""
                $bootChoice = Read-Host "Select boot repair option"
                
                $drive = Read-Host "Target Windows drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                switch ($bootChoice) {
                    "1" {
                        $command = "bcdboot ${drive}:\Windows"
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bcdboot" -Command $command -Description "Rebuild BCD from Windows installation"
                        if ($confirmed) {
                            Write-Host "`nExecuting: $command" -ForegroundColor Gray
                            $output = Invoke-Expression $command 2>&1
                            Write-Host $output
                            Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        } else {
                            Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        }
                    }
                    "2" {
                        $command = "bootrec /fixboot"
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_fixboot" -Command $command -Description "Fix boot sector"
                        if ($confirmed) {
                            Write-Host "`nExecuting: $command" -ForegroundColor Gray
                            $output = bootrec /fixboot 2>&1
                            Write-Host $output
                            Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        } else {
                            Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        }
                    }
                    "3" {
                        Write-Host "`nScanning for Windows installations..." -ForegroundColor Gray
                        $output = bootrec /scanos 2>&1
                        Write-Host $output
                        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    "4" {
                        $command = "bootrec /rebuildbcd"
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_rebuildbcd" -Command $command -Description "Rebuild BCD"
                        if ($confirmed) {
                            Write-Host "`nExecuting: $command" -ForegroundColor Gray
                            $output = bootrec /rebuildbcd 2>&1
                            Write-Host $output
                            Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        } else {
                            Write-Host "Operation cancelled. Press any key to continue..." -ForegroundColor Yellow
                            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        }
                    }
                    "B" { continue }
                    "b" { continue }
                    default {
                        Write-Host "`nInvalid selection. Press any key to continue..." -ForegroundColor Red
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                }
            }
            "A" {
                Write-Host "`nADVANCED DIAGNOSTICS" -ForegroundColor Cyan
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
                Write-Host ""
                Write-Host "1) Boot Diagnosis" -ForegroundColor White
                Write-Host "2) System Restore Check" -ForegroundColor White
                Write-Host "3) Reagentc Health Check" -ForegroundColor White
                Write-Host "4) OS Information" -ForegroundColor White
                Write-Host "B) Back to main menu" -ForegroundColor Yellow
                Write-Host ""
                $diagChoice = Read-Host "Select diagnostic option"
                
                $drive = Read-Host "Target drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                switch ($diagChoice) {
                    "1" {
                        Write-Host "`nRunning boot diagnosis..." -ForegroundColor Gray
                        $diagnosis = Get-BootDiagnosis -TargetDrive $drive
                        Write-Host $diagnosis
                        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    "2" {
                        Write-Host "`nChecking System Restore..." -ForegroundColor Gray
                        $restoreInfo = Get-SystemRestoreInfo -TargetDrive $drive
                        Write-Host ""
                        Write-Host "SYSTEM RESTORE STATUS" -ForegroundColor Cyan
                        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
                        Write-Host $restoreInfo.Message
                        if ($restoreInfo.Enabled -and $restoreInfo.RestorePoints.Count -gt 0) {
                            Write-Host "`nRestore Points:" -ForegroundColor Cyan
                            $num = 1
                            foreach ($point in $restoreInfo.RestorePoints | Select-Object -First 10) {
                                Write-Host "$num. $($point.Description) - $($point.CreationTime)" -ForegroundColor Gray
                                $num++
                            }
                        }
                        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    "3" {
                        Write-Host "`nChecking Reagentc health..." -ForegroundColor Gray
                        $reagentcHealth = Get-ReagentcHealth
                        Write-Host ""
                        Write-Host "REAGENTC HEALTH" -ForegroundColor Cyan
                        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
                        Write-Host $reagentcHealth.Message
                        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    "4" {
                        Write-Host "`nGathering OS information..." -ForegroundColor Gray
                        $osInfo = Get-OSInfo -TargetDrive $drive
                        Write-Host ""
                        Write-Host "OPERATING SYSTEM INFORMATION" -ForegroundColor Cyan
                        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
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
                        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    "B" { continue }
                    "b" { continue }
                    default {
                        Write-Host "`nInvalid selection. Press any key to continue..." -ForegroundColor Red
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                }
            }
            "a" {
                # Handle lowercase 'a' for Advanced Diagnostics
                $c = "A"
                continue
            }
            "B" {
                $drive = Read-Host "`nTarget Windows drive letter (e.g. C, or press Enter for C)"
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
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
                Write-Host "  BOOT PROBABILITY: $($bootHealth.BootProbability)%" -ForegroundColor $(if ($bootHealth.BootProbability -ge 75) { "Green" } elseif ($bootHealth.BootProbability -ge 50) { "Yellow" } else { "Red" })
                Write-Host "  BOOT HEALTH: $($bootHealth.BootHealth)" -ForegroundColor $(if ($bootHealth.BootProbability -ge 75) { "Green" } elseif ($bootHealth.BootProbability -ge 50) { "Yellow" } else { "Red" })
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
                
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "b" {
                $c = "B"
                continue
            }
            "C" {
                $drive = Read-Host "`nTarget Windows drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nRunning automated boot repair..." -ForegroundColor Gray
                $repairResult = Start-AutomatedBootRepair -TargetDrive $drive
                Write-Host ""
                Write-Host $repairResult.Report
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "c" {
                $c = "C"
                continue
            }
            "D" {
                $drive = Read-Host "`nTarget Windows drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                $source = Read-Host "Windows installation source path (optional, for offline repair - press Enter to skip)"
                
                Write-Host "`nRunning system file repair (SFC + DISM)..." -ForegroundColor Gray
                Write-Host "This may take 15-30 minutes..." -ForegroundColor Yellow
                Write-Host ""
                
                if ([string]::IsNullOrWhiteSpace($source)) {
                    $repairResult = Start-SystemFileRepair -TargetDrive $drive
                } else {
                    $repairResult = Start-SystemFileRepair -TargetDrive $drive -SourcePath $source
                }
                
                Write-Host ""
                Write-Host $repairResult.Report
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "c" {
                $c = "C"
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
                
                $repairResult = Start-DiskRepair -TargetDrive $drive -FixErrors -RecoverBadSectors:$recoverBadSectors
                
                Write-Host ""
                Write-Host $repairResult.Report
                if ($repairResult.RequiresReboot) {
                    Write-Host "`nNOTE: chkdsk has been scheduled for next reboot." -ForegroundColor Yellow
                }
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "d" {
                $c = "D"
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
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "e" {
                $c = "E"
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
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "f" {
                $c = "F"
                continue
            }
            "G" {
                $drive = Read-Host "`nTarget Windows drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nCOMPLETE SYSTEM REPAIR" -ForegroundColor Cyan
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
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
                    Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                } else {
                    Write-Host "`nOperation cancelled. Press any key to continue..." -ForegroundColor Yellow
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
            }
            "g" {
                $c = "G"
                continue
            }
            "G" {
                $drive = Read-Host "`nTarget Windows drive letter (e.g. C, or press Enter for C)"
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                Write-Host "`nCOMPLETE SYSTEM REPAIR" -ForegroundColor Cyan
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Gray
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
                    Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                } else {
                    Write-Host "`nOperation cancelled. Press any key to continue..." -ForegroundColor Yellow
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
            }
            "g" {
                $c = "G"
                continue
            }
            "H" {
                $drive = Read-Host "`nTarget Windows drive letter (e.g. C, or press Enter for C)"
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
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor $(if ($readiness.ReadyForInPlaceUpgrade) { "Green" } else { "Red" })
                if ($readiness.ReadyForInPlaceUpgrade) {
                    Write-Host "  STATUS: READY FOR IN-PLACE UPGRADE" -ForegroundColor Green
                } else {
                    Write-Host "  STATUS: BLOCKED - NOT READY FOR IN-PLACE UPGRADE" -ForegroundColor Red
                    Write-Host "  BLOCKERS FOUND: $($readiness.Blockers.Count)" -ForegroundColor Red
                }
                Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor $(if ($readiness.ReadyForInPlaceUpgrade) { "Green" } else { "Red" })
                
                Write-Host "`nPress any key to continue..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "h" {
                $c = "H"
                continue
            }
            "Q" { 
                Write-Host "`nExiting..." -ForegroundColor Yellow
                break 
            }
            "q" { 
                Write-Host "`nExiting..." -ForegroundColor Yellow
                break 
            }
            default {
                Write-Host "`nInvalid selection. Press any key to continue..." -ForegroundColor Red
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }
    } while ($c -ne "Q" -and $c -ne "q")
}
