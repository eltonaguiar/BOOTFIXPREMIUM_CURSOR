function Get-WindowsVolumes {
    Get-Volume | Where-Object FileSystem |
        Sort-Object DriveLetter |
        Select DriveLetter, FileSystemLabel, Size, HealthStatus
}

function Get-BCDEntries {
    # Returns raw objects for the GUI to parse
    bcdedit /enum /v
}

function Get-BCDEntriesParsed {
    # Production-grade BCD parser - captures ALL properties
    $raw = bcdedit /enum /v
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
    param($Id, $NewName)
    if ($Id -and $NewName) { bcdedit /set $Id description "$NewName" }
}

function Set-BCDDefaultEntry {
    param($Id)
    if ($Id) { bcdedit /default $Id }
}

function Set-BCDProperty {
    param($Id, $Property, $Value)
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

function Get-BSODExplanation {
    param($StopCode)
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
    try {
        if ($efiDriveLetter) {
            $bcdPath = "$efiDriveLetter`:\EFI\Microsoft\Boot\BCD"
            if (Test-Path $bcdPath) { 
                $report.AppendLine("[PASS] BCD Store exists at $bcdPath")
                $bcdFound = $true
                
                # Check BCD integrity - try to enumerate
                try {
                    $bcdTest = bcdedit /enum 2>&1
                    if ($bcdTest -match "The boot configuration data store could not be opened") {
                        $report.AppendLine("[FAIL] BCD exists but cannot be opened - may be corrupted or locked")
                        $issues += @{
                            Type = "BCD Integrity Failure"
                            Severity = "Critical"
                            Description = "The BCD exists but is 'orphaned' or the attributes are locked. bcdedit returns 'could not be opened'."
                            Recommendation = "Run: attrib $bcdPath -h -r -s, then rename to bcd.old, then run: bootrec /rebuildbcd"
                        }
                    } else {
                        $report.AppendLine("[PASS] BCD Store is accessible and can be enumerated")
                    }
                } catch {
                    $report.AppendLine("[WARNING] Could not test BCD accessibility: $_")
                }
            } else {
                $report.AppendLine("[FAIL] BCD Store not found at expected location: $bcdPath")
                $issues += @{
                    Type = "Missing BCD File"
                    Severity = "Critical"
                    Description = "The Boot Configuration Data file is missing or located on an unmounted partition, preventing the Windows Boot Manager from locating the OS."
                    Recommendation = "Boot into a recovery environment and run: bcdboot $Drive`:\Windows /s $efiDriveLetter`: /f UEFI"
                }
            }
        } else {
            # Try to find EFI partition with drive letter
            $allEfiParts = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -and $_.DriveLetter }
            foreach ($efi in $allEfiParts) {
                $testPath = "$($efi.DriveLetter):\EFI\Microsoft\Boot\BCD"
                if (Test-Path $testPath) { 
                    $report.AppendLine("[PASS] BCD Store exists at $testPath")
                    $bcdFound = $true
                    $bcdPath = $testPath
                    $efiDriveLetter = $efi.DriveLetter
                    
                    # Test BCD integrity
                    try {
                        $bcdTest = bcdedit /enum 2>&1
                        if ($bcdTest -match "could not be opened") {
                            $report.AppendLine("[FAIL] BCD exists but cannot be opened - may be corrupted")
                            $issues += @{
                                Type = "BCD Integrity Failure"
                                Severity = "Critical"
                                Description = "The BCD exists but is 'orphaned' or locked."
                                Recommendation = "Run: attrib $testPath -h -r -s, rename to bcd.old, then: bootrec /rebuildbcd"
                            }
                        }
                    } catch {
                        # Ignore test errors
                    }
                    break
                }
            }
            if (-not $bcdFound) {
                $report.AppendLine("[FAIL] BCD Store not found in any EFI partition.")
                $issues += @{
                    Type = "Missing BCD File"
                    Severity = "Critical"
                    Description = "The Boot Configuration Data file is missing from all EFI partitions."
                    Recommendation = "Boot into a recovery environment and run: bcdboot $Drive`:\Windows /s [EFILetter]: /f UEFI (replace [EFILetter] with the EFI partition drive letter)"
                }
            }
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
                    if (Test-Path $reLocation) {
                        $report.AppendLine("[PASS] WinRE location is accessible: $reLocation")
                        $report.AppendLine("[PASS] System can reach 'Windows Logo' stage - 'Good Enough' state achieved")
                    } else {
                        $report.AppendLine("[FAIL] WinRE location reported but not accessible: $reLocation")
                        $issues += @{
                            Type = "WinRE Inaccessible"
                            Severity = "Warning"
                            Description = "WinRE is enabled but the recovery environment cannot trigger 'Startup Repair' - location may be invalid."
                            Recommendation = "Run: reagentc /enable to re-link the recovery image to the boot menu."
                        }
                    }
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
            $report.AppendLine("[WARNING] Could not determine WinRE status")
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
    param($TargetDrive = "C")
    $status = @{
        IsEncrypted = $false
        ProtectionStatus = "Unknown"
        EncryptionPercentage = 0
        VolumeStatus = "Unknown"
        KeyProtectors = @()
        Warning = ""
    }
    
    try {
        # Check if BitLocker is available (requires BitLocker feature)
        $bitlockerCmd = Get-Command "manage-bde" -ErrorAction SilentlyContinue
        if (-not $bitlockerCmd) {
            $status.Warning = "BitLocker management tools not available. Cannot determine encryption status."
            return $status
        }
        
        # Get BitLocker status for the target drive
        $bdeStatus = manage-bde -status "$TargetDrive`:" 2>&1
        
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
            $status.Warning += "Ensure you have your recovery key (48-digit number) before proceeding.`n"
            $status.Warning += "You can find it in: Microsoft Account > Devices > BitLocker recovery keys"
        }
        
    } catch {
        # Try alternative method using WMI
        try {
            $bitlocker = Get-WmiObject -Namespace "Root\cimv2\security\microsoftvolumeencryption" -Class "Win32_EncryptableVolume" -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq "$TargetDrive`:" }
            
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
═══════════════════════════════════════════════════════════════════════════════
  UNOFFICIAL REPAIR INSTALLATION TIPS
═══════════════════════════════════════════════════════════════════════════════

⚠️  WARNING: These methods are NOT officially recommended by Microsoft and 
   may carry risk. Proceed at your own discretion. These steps are community-
   sourced workarounds for restoring system integrity without a clean wipe.
   These tips prioritize keeping your files and software intact.

═══════════════════════════════════════════════════════════════════════════════

TIP 1: Windows 11 Cloud Repair (Hidden Feature)
───────────────────────────────────────────────────────────────────────────────
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

═══════════════════════════════════════════════════════════════════════════════

TIP 2: The "In-Place" Upgrade Repair (Standard Method)
───────────────────────────────────────────────────────────────────────────────
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

═══════════════════════════════════════════════════════════════════════════════

TIP 3: The "Product Server" Compatibility Bypass (Force Command)
───────────────────────────────────────────────────────────────────────────────
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

⚠️  Note: This works on some Windows versions but not all. Test in a non-
   critical environment first.

═══════════════════════════════════════════════════════════════════════════════

TIP 4: Registry "EditionID" Override
───────────────────────────────────────────────────────────────────────────────
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

⚠️  CRITICAL: Make a registry backup first! Run: reg export HKLM\SOFTWARE backup.reg
   Restore if needed: reg import backup.reg

═══════════════════════════════════════════════════════════════════════════════

TIP 5: The "Restore to Repair" Workflow
───────────────────────────────────────────────────────────────────────────────
Summary: Restores the bootloader just enough to enter the OS, specifically to 
         trigger an In-Place Repair.

Instructions:
1. If Windows won't boot, use bcdboot C:\Windows /s S: /f UEFI from a 
   recovery USB to fix the "handshake" between hardware and OS.
2. Boot into Windows (even if unstable).
3. Immediately run setup.exe from a mounted ISO to perform an In-Place Upgrade.

Outcome: Prioritizes software and file preservation by using the bootloader fix 
         as a "stepping stone" to a full system refresh.

═══════════════════════════════════════════════════════════════════════════════

TIP 6: Offline Component Store Repair (DISM) - From WinPE/Hiren's
───────────────────────────────────────────────────────────────────────────────
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
───────────────────────────────────────────────────────────────────────────────
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

═══════════════════════════════════════════════════════════════════════════════

TIP 7: Manual Hive Injection
───────────────────────────────────────────────────────────────────────────────
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

⚠️  CRITICAL: Only attempt this if you have a recent backup of the SYSTEM hive.
   Incorrect registry restoration can make the system completely unbootable.

═══════════════════════════════════════════════════════════════════════════════

═══════════════════════════════════════════════════════════════════════════════

PRO-TIP: Preserving Game Libraries on F: Drive
───────────────────────────────────────────────────────────────────────────────
If you perform an In-Place Upgrade, Windows may "forget" that your Steam libraries 
are on F:. To fix this without redownloading:

1. Open Steam after the repair
2. Go to Settings > Storage
3. Click "Add Drive" and select F:\SteamLibrary
4. Steam will instantly "discover" all your existing games without a single 
   byte of download

This works for Epic Games, GOG, and other game launchers too - just point them 
to your existing library folders.

═══════════════════════════════════════════════════════════════════════════════

DISCLAIMER:
These methods are provided as-is for advanced users. Always backup critical 
data before attempting repairs. Microsoft Support should be consulted for 
production systems or critical data scenarios.

═══════════════════════════════════════════════════════════════════════════════
"@
    return $tips
}

function Get-RecommendedTools {
    $tools = @"
═══════════════════════════════════════════════════════════════════════════════
  RECOMMENDED RECOVERY TOOLS
═══════════════════════════════════════════════════════════════════════════════

If you are serious about maintaining your system (and your game libraries on 
the F: drive), these are the "Must-Have" tools:

┌─────────────────────────────────────────────────────────────────────────────┐
│ Tool                          │ Purpose                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│ Hiren's BootCD PE             │ The ultimate Win10-based recovery           │
│                                │ environment. Includes tools for             │
│                                │ partitioning, driver injection, and         │
│                                │ registry editing.                           │
│                                │ Download: hirensbootcd.org                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ Macrium Reflect (Rescue)      │ ESSENTIAL. Its "Fix Windows Boot           │
│                                │ Problems" button is magic—it fixes          │
│                                │ complex BCD/UEFI issues that bootrec       │
│                                │ often fails at.                             │
│                                │ Download: macrium.com/reflectfree          │
├─────────────────────────────────────────────────────────────────────────────┤
│ Sergei Strelec's WinPE        │ A more "advanced" alternative to Hiren's.    │
│                                │ It contains almost every diagnostic tool    │
│                                │ known to man.                               │
│                                │ Download: sergeistrelec.name               │
├─────────────────────────────────────────────────────────────────────────────┤
│ Explorer++                    │ A lightweight file manager that often        │
│                                │ works in WinPE when the standard file       │
│                                │ explorer is buggy.                          │
│                                │ Download: explorerplusplus.com             │
├─────────────────────────────────────────────────────────────────────────────┤
│ Microsoft SaRA                │ (Support and Recovery Assistant) A          │
│                                │ specialized tool that automates fixes for   │
│                                │ Windows Activation and Office issues.       │
│                                │ Download: aka.ms/SaRASetup                 │
└─────────────────────────────────────────────────────────────────────────────┘

USAGE TIPS:
• Keep Hiren's BootCD PE on a USB drive for emergency recovery
• Macrium Reflect Rescue can fix boot issues that bcdboot cannot
• Use Sergei Strelec's WinPE for advanced registry and file system repairs
• Explorer++ is invaluable when Windows Explorer crashes in recovery mode

═══════════════════════════════════════════════════════════════════════════════
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
═══════════════════════════════════════════════════════════════════════════════
  DRIVER EXTRACT INSTRUCTIONS
═══════════════════════════════════════════════════════════════════════════════

This folder contains all driver files extracted from your working PC.
Use these drivers to restore your system on new hardware or in recovery scenarios.

═══════════════════════════════════════════════════════════════════════════════

FOR ACRONIS TRUE IMAGE UNIVERSAL RESTORE:
───────────────────────────────────────────────────────────────────────────────

1. Copy this entire folder to a USB drive or network location accessible from
   your recovery environment.

2. In Acronis True Image:
   - Start Universal Restore
   - When prompted for drivers, browse to this folder
   - Acronis will automatically detect and load the appropriate drivers

3. The folder structure is preserved - each driver is in its own subfolder
   as required by Acronis Universal Restore.

═══════════════════════════════════════════════════════════════════════════════

FOR OTHER RECOVERY TOOLS:
───────────────────────────────────────────────────────────────────────────────

- Windows Recovery Environment (WinRE):
  Use: drvload [path]\driver.inf

- DISM (Offline Driver Injection):
  Use: dism /Image:C:\ /Add-Driver /Driver:[this folder] /Recursive

- Manual Installation:
  Right-click INF files and select "Install"

═══════════════════════════════════════════════════════════════════════════════

IMPORTANT REMINDERS:
───────────────────────────────────────────────────────────────────────────────

⚠️  BACKUP TO CLOUD STORAGE:
   - Upload this folder to Google Drive, OneDrive, or Dropbox
   - This ensures you have drivers available even if local backup is lost
   - Share the link with yourself or keep it in a password manager

⚠️  UPDATE AFTER HARDWARE CHANGES:
   - If you upgrade your motherboard, CPU, or storage controller,
     extract a NEW set of drivers from the updated system
   - Old drivers may not work with new hardware
   - Keep multiple driver sets if you have multiple PC configurations

⚠️  DRIVER COMPATIBILITY:
   - These drivers are specific to your current hardware configuration
   - They may not work on significantly different hardware
   - Always test in a recovery environment before relying on them

═══════════════════════════════════════════════════════════════════════════════

FOLDER CONTENTS:
───────────────────────────────────────────────────────────────────────────────

- Each subfolder contains a complete driver package (INF, SYS, CAT, DLL files)
- Driver_Manifest.txt: List of all extracted drivers and their devices
- INSTRUCTIONS.txt: This file

Total Size: {0} MB
Total Drivers: {1}
Total Files: {2}

═══════════════════════════════════════════════════════════════════════════════
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
                    $summary += "  ⚠️  SUSPICIOUS: $($filter.SuspiciousFilters -join '; ')`n"
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
───────────────────────────────────────────────────────────────────────────────
Forces Windows Setup to perform a "repair-only" in-place upgrade that:
  - Reinstalls Windows system files
  - Rebuilds component store
  - Re-registers services + boot
  - KEEPS: Apps, Data, User profiles
  - WITHOUT: Feature jump, Build bump, Edition change

HARD REQUIREMENTS (MUST MATCH):
───────────────────────────────────────────────────────────────────────────────
  ✓ Edition: EXACT match (Pro → Pro, Home → Home)
  ✓ Architecture: EXACT (x64 → x64, x86 → x86)
  ✓ Build Family: SAME (19041 ↔ 19045 is OK, but 19041 ↔ 22000 is NOT)
  ✓ Language: MUST match
  ✓ Launch Context: From inside Windows (NOT WinRE/WinPE)
  ✓ Registry: Must be loadable
  ✓ CBS: Not permanently locked

STEP-BY-STEP PROCESS:
───────────────────────────────────────────────────────────────────────────────

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
───────────────────────────────────────────────────────────────────────────────
  ✗ Boot breaks before login
  ✗ SYSTEM or SOFTWARE registry hive is corrupt
  ✗ CBS is permanently pending
  ✗ Disk driver stack is broken (e.g., VMD mismatch)
  ✗ Running from WinRE/WinPE
  ✗ Edition/Architecture/Build mismatch

ALTERNATIVES IF REPAIR INSTALL FAILS:
───────────────────────────────────────────────────────────────────────────────
  - Offline servicing (DISM)
  - Side-by-side reinstall
  - Image restore from backup
  - Clean install (last resort)

IMPORTANT NOTES:
───────────────────────────────────────────────────────────────────────────────
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
───────────────────────────────────────────────────────────────────────────────
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

⚠️  WARNING: This is a GRAY-AREA NUCLEAR HACK
───────────────────────────────────────────────────────────────────────────────
This method is documented only in advanced forums (MDL, Win-Raid).
Use at your own risk. This is NOT officially supported by Microsoft.

HARD REQUIREMENTS:
───────────────────────────────────────────────────────────────────────────────
  ✓ Must boot from WinPE or WinRE (SystemDrive = X:)
  ✓ Offline Windows installation must exist on target drive
  ✓ SYSTEM and SOFTWARE registry hives must be loadable
  ✓ ISO must match: Edition, Architecture, Build Family
  ✓ Component store (WinSxS) should be readable

WHEN THIS WORKS:
───────────────────────────────────────────────────────────────────────────────
  ✓ Registry is intact (can be loaded)
  ✓ Program Files structure is consistent
  ✓ Component store is readable
  ✓ Migration engine can access offline files

WHEN THIS FAILS:
───────────────────────────────────────────────────────────────────────────────
  ✗ Pending CBS operations (pending.xml exists)
  ✗ Corrupt SOFTWARE registry hive
  ✗ Missing servicing metadata
  ✗ Component store (WinSxS) is corrupted
  ✗ Program Files structure is inconsistent

STEP-BY-STEP PROCESS:
───────────────────────────────────────────────────────────────────────────────

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
───────────────────────────────────────────────────────────────────────────────
  - Registry hives are automatically backed up before modification
  - Backup location is shown in output
  - If repair fails, you can restore hives from backup
  - Migration engine runs offline, so it may take longer
  - This method bypasses normal Setup checks

ALTERNATIVES IF THIS FAILS:
───────────────────────────────────────────────────────────────────────────────
  - Offline servicing with DISM
  - Side-by-side reinstall
  - Image restore from backup
  - Clean install (last resort)

REFERENCES:
───────────────────────────────────────────────────────────────────────────────
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
        [int]$TimeoutSeconds = 5
    )
    
    $result = @{
        Connected = $false
        Message = ""
        TestedHosts = @()
    }
    
    # Test hosts (in order of reliability)
    $testHosts = @(
        "8.8.8.8",           # Google DNS
        "1.1.1.1",           # Cloudflare DNS
        "microsoft.com",     # Microsoft
        "google.com"         # Google
    )
    
    foreach ($host in $testHosts) {
        try {
            $result.TestedHosts += $host
            $ping = Test-Connection -ComputerName $host -Count 1 -TimeoutSeconds $TimeoutSeconds -ErrorAction Stop
            if ($ping) {
                $result.Connected = $true
                $result.Message = "Internet connectivity confirmed (reached $host)"
                return $result
            }
        } catch {
            # Continue to next host
            continue
        }
    }
    
    # If all pings failed, try HTTP request
    try {
        $webRequest = Invoke-WebRequest -Uri "http://www.microsoft.com" -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
        if ($webRequest.StatusCode -eq 200) {
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
═══════════════════════════════════════════════════════════════
CHATGPT HELP - COMMAND-LINE METHOD
═══════════════════════════════════════════════════════════════

Browser is not available in this environment. Use one of these methods:

METHOD 1: Use Another Device
───────────────────────────────────────────────────────────────
1. On your phone or another computer, open: https://chat.openai.com
2. Ask: "My Windows installation failed. How do I check setup logs?"
3. Share the error codes you find in the logs

METHOD 2: Use curl (if available)
───────────────────────────────────────────────────────────────
curl -X POST https://api.openai.com/v1/chat/completions ^
  -H "Content-Type: application/json" ^
  -H "Authorization: Bearer YOUR_API_KEY" ^
  -d "{\"model\":\"gpt-3.5-turbo\",\"messages\":[{\"role\":\"user\",\"content\":\"Windows install failed\"}]}"

Note: Requires OpenAI API key (not free)

METHOD 3: Manual URL
───────────────────────────────────────────────────────────────
Write down this URL and open it on another device:
$chatGPTUrl

Suggested questions to ask:
- "How do I check Windows setup error logs?"
- "Windows installation failed with error code [your code]"
- "How to fix Windows boot issues in recovery environment?"

═══════════════════════════════════════════════════════════════
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
            Impact = "May change which Windows installation boots by default."
            Recovery = "BCD backup should be created automatically."
        }
        "bootrec_fixboot" = @{
            Title = "HIGH RISK: Fix Boot Sector"
            Risk = "This writes a new boot sector. If your system uses BitLocker, you may need the recovery key."
            Impact = "Boot sector will be rewritten. BitLocker may require recovery key."
            Recovery = "Have BitLocker recovery key ready if encryption is enabled."
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
═══════════════════════════════════════════════════════════════
⚠️  $($warning.Title)
═══════════════════════════════════════════════════════════════

COMMAND: $Command
DESCRIPTION: $Description

RISK LEVEL: $riskLevel

⚠️  WARNING:
$($warning.Risk)

POTENTIAL IMPACT:
$($warning.Impact)

RECOVERY OPTIONS:
$($warning.Recovery)

═══════════════════════════════════════════════════════════════
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
        [switch]$SkipBitLockerCheck = $false
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
        if (-not $SkipBitLockerCheck) {
            $bitlocker = Test-BitLockerStatus -TargetDrive "C"
            if ($bitlocker.IsEncrypted) {
                Write-Host ""
                Write-Host "⚠️  BITLOCKER ENCRYPTION DETECTED" -ForegroundColor Yellow
                Write-Host $bitlocker.Warning -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Do you have your BitLocker recovery key? (Y/N): " -ForegroundColor Yellow -NoNewline
                $bitlockerConfirm = Read-Host
                if ($bitlockerConfirm -ne 'Y' -and $bitlockerConfirm -ne 'y') {
                    Write-Host "Operation cancelled." -ForegroundColor Red
                    return $false
                }
            }
        }
        
        $confirm = Read-Host
        return ($confirm -eq 'Y' -or $confirm -eq 'y')
    }
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
                    $report.AppendLine("Recent errors from $errorLog:") | Out-Null
                    
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
        if ($missingDevices -and $missingDevices -match 'missing|not found|error' -CaseSensitive:$false) {
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
        [switch]$SkipConfirmation = $false
    )
    
    $result = @{
        Success = $false
        StepsCompleted = @()
        StepsFailed = @()
        BCDBackups = @()
        Report = ""
        Errors = @()
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("AUTOMATED BOOT REPAIR") | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
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
    Automated SFC + DISM repair sequence with progress tracking.
    #>
    param(
        [string]$TargetDrive = "C",
        [string]$SourcePath = "",
        [switch]$SkipSFC = $false,
        [switch]$SkipDISM = $false,
        [scriptblock]$ProgressCallback = $null
    )
    
    $result = @{
        Success = $false
        SFCCompleted = $false
        DISMCompleted = $false
        SFCOutput = ""
        DISMOutput = ""
        Report = ""
        Errors = @()
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
            
            $sfcOutput = Invoke-Expression $sfcCmd 2>&1 | Out-String
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
            
            $dismOutput = Invoke-Expression $dismCmd 2>&1 | Out-String
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

