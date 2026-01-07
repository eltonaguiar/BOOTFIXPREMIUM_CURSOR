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
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host "  MIRACLE BOOT v7.2.0 - MS-DOS STYLE MODE" -ForegroundColor Cyan
        Write-Host "  Environment: $envDisplay" -ForegroundColor Gray
        Write-Host "===============================================================" -ForegroundColor Cyan
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
        Write-Host "I) Boot Chain Analysis (View Startup/Boot Logs)" -ForegroundColor Cyan
        Write-Host "J) Utilities Menu (Notepad, Registry, PowerShell, etc.)" -ForegroundColor White
        if ($envDisplay -eq "WinPE") {
            Write-Host "K) Install Browser (Chrome/Firefox - WinPE only)" -ForegroundColor Cyan
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
                Write-Host "1) Rebuild BCD from Windows Installation (bcdboot)" -ForegroundColor White
                Write-Host "2) Fix Boot Files (bootrec /fixboot)" -ForegroundColor White
                Write-Host "3) Scan for Windows Installations (bootrec /scanos)" -ForegroundColor White
                Write-Host "4) Rebuild BCD (bootrec /rebuildbcd)" -ForegroundColor White
                Write-Host "B) Back to main menu" -ForegroundColor Yellow
                Write-Host ""
                $bootChoice = Read-Host "Select boot repair option"
                
                $drive = Read-Host 'Target Windows drive letter (e.g. C or press Enter for C)'
                if ([string]::IsNullOrWhiteSpace($drive)) {
                    $drive = "C"
                }
                $drive = $drive.TrimEnd(':').ToUpper()
                
                switch ($bootChoice) {
                    '1' {
                        $command = "bcdboot ${drive}:\Windows"
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bcdboot" -Command $command -Description "Rebuild BCD from Windows installation"
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
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_fixboot" -Command $command -Description "Fix boot sector"
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
                        $confirmed = Confirm-DestructiveOperation -CommandKey "bootrec_rebuildbcd" -Command $command -Description "Rebuild BCD"
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
                
                # Progress callback for TUI
                $progressCallback = {
                    param($message)
                    Write-Host $message -ForegroundColor Cyan
                }
                
                if ([string]::IsNullOrWhiteSpace($source)) {
                    $repairResult = Start-SystemFileRepair -TargetDrive $drive -ProgressCallback $progressCallback
                } else {
                    $repairResult = Start-SystemFileRepair -TargetDrive $drive -SourcePath $source -ProgressCallback $progressCallback
                }
                
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
                
                # Progress callback for TUI
                $progressCallback = {
                    param($message)
                    Write-Host $message -ForegroundColor Cyan
                }
                
                $repairResult = Start-DiskRepair -TargetDrive $drive -FixErrors -RecoverBadSectors:$recoverBadSectors -ProgressCallback $progressCallback
                
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
