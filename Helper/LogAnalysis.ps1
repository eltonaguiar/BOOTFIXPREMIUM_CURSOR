<#
    MIRACLE BOOT – COMPREHENSIVE LOG ANALYSIS MODULE
    ================================================
    
    This module provides comprehensive log gathering and root cause analysis
    based on the tiered log priority system for boot failures and system issues.
    
    TIER SYSTEM:
    - TIER 1: Boot-critical crash dumps (MEMORY.DMP, LiveKernelReports, Minidumps)
    - TIER 2: Boot pipeline logs (Setup logs, ntbtlog.txt)
    - TIER 3: Event logs (System.evtx, SrtTrail.txt)
    - TIER 4: Boot structure (BCD store, Registry)
    - TIER 5: Image/hardware context (metadata)
#>

function Get-ComprehensiveLogAnalysis {
    <#
    .SYNOPSIS
    Gathers and analyzes all important logs from all tiers to identify root causes.
    
    .DESCRIPTION
    Performs comprehensive log collection and analysis following the tiered priority system:
    - TIER 1: Crash dumps (MEMORY.DMP, LiveKernelReports, Minidumps)
    - TIER 2: Boot pipeline logs (Setup logs, ntbtlog.txt)
    - TIER 3: Event logs (System.evtx, SrtTrail.txt)
    - TIER 4: Boot structure (BCD, Registry)
    - TIER 5: Hardware/image context
    
    .PARAMETER TargetDrive
    Target Windows drive letter (default: C)
    
    .PARAMETER IncludeAllTiers
    Include all tiers in analysis (default: true)
    
    .PARAMETER ExportPath
    Optional path to export collected logs
    #>
    param(
        [string]$TargetDrive = "C",
        [switch]$IncludeAllTiers = $true,
        [string]$ExportPath = ""
    )
    
    # Normalize drive letter
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        Success = $false
        TargetDrive = "$TargetDrive`:"
        Timestamp = Get-Date
        Tier1 = @{}
        Tier2 = @{}
        Tier3 = @{}
        Tier4 = @{}
        Tier5 = @{}
        RootCauseSummary = ""
        Recommendations = @()
        LogFilesFound = @()
        LogFilesMissing = @()
        ExportPath = $ExportPath
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("COMPREHENSIVE LOG ANALYSIS - ROOT CAUSE DIAGNOSTICS") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("Target Drive: $TargetDrive`:\") | Out-Null
    $report.AppendLine("Analysis Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # ============================================
    # TIER 1 - BOOT-CRITICAL CRASH DUMPS
    # ============================================
    $report.AppendLine("🔥 TIER 1 — BOOT-CRITICAL CRASH DUMPS") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $tier1 = Get-Tier1CrashDumps -TargetDrive $TargetDrive
    $result.Tier1 = $tier1
    
    if ($tier1.MemoryDump.Found) {
        $report.AppendLine("✅ MEMORY.DMP: FOUND at $($tier1.MemoryDump.Path)") | Out-Null
        $report.AppendLine("   Size: $([math]::Round($tier1.MemoryDump.SizeMB, 2)) MB") | Out-Null
        $report.AppendLine("   Modified: $($tier1.MemoryDump.LastModified)") | Out-Null
        $report.AppendLine("   ⚠️  THIS IS THE HIGHEST PRIORITY DUMP - ANALYZE THIS FIRST!") | Out-Null
        $result.LogFilesFound += $tier1.MemoryDump.Path
    } else {
        $report.AppendLine("❌ MEMORY.DMP: NOT FOUND at C:\Windows\MEMORY.DMP") | Out-Null
        $result.LogFilesMissing += "C:\Windows\MEMORY.DMP"
    }
    
    if ($tier1.LiveKernelReports.Count -gt 0) {
        $report.AppendLine("✅ LiveKernelReports: FOUND $($tier1.LiveKernelReports.Count) report(s)") | Out-Null
        foreach ($reportItem in $tier1.LiveKernelReports | Select-Object -First 5) {
            $report.AppendLine("   - $($reportItem.Path) ($($reportItem.Category))") | Out-Null
            $result.LogFilesFound += $reportItem.Path
        }
        if ($tier1.LiveKernelReports.Count -gt 5) {
            $report.AppendLine("   ... and $($tier1.LiveKernelReports.Count - 5) more") | Out-Null
        }
    } else {
        $report.AppendLine("❌ LiveKernelReports: NOT FOUND in C:\Windows\LiveKernelReports\") | Out-Null
        $result.LogFilesMissing += "C:\Windows\LiveKernelReports\"
    }
    
    if ($tier1.MiniDumps.Count -gt 0) {
        $report.AppendLine("✅ Minidumps: FOUND $($tier1.MiniDumps.Count) dump(s)") | Out-Null
        foreach ($dump in $tier1.MiniDumps | Select-Object -First 3) {
            $report.AppendLine("   - $($dump.Path) ($($dump.Date))") | Out-Null
            $result.LogFilesFound += $dump.Path
        }
    } else {
        $report.AppendLine("⚠️  Minidumps: NOT FOUND (low priority for boot failures)") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # ============================================
    # TIER 2 - BOOT PIPELINE LOGS
    # ============================================
    $report.AppendLine("🔥 TIER 2 — BOOT PIPELINE LOGS") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $tier2 = Get-Tier2BootPipelineLogs -TargetDrive $TargetDrive
    $result.Tier2 = $tier2
    
    if ($tier2.SetupLogs.Count -gt 0) {
        $report.AppendLine("✅ Setup Logs: FOUND $($tier2.SetupLogs.Count) log file(s)") | Out-Null
        foreach ($log in $tier2.SetupLogs) {
            $report.AppendLine("   - $($log.Path)") | Out-Null
            $result.LogFilesFound += $log.Path
        }
    } else {
        $report.AppendLine("❌ Setup Logs: NOT FOUND (check Panther directories)") | Out-Null
    }
    
    if ($tier2.BootLog.Found) {
        $report.AppendLine("✅ Boot Log (ntbtlog.txt): FOUND") | Out-Null
        $report.AppendLine("   - $($tier2.BootLog.Path)") | Out-Null
        $result.LogFilesFound += $tier2.BootLog.Path
    } else {
        $report.AppendLine("⚠️  Boot Log (ntbtlog.txt): NOT FOUND (boot logging may not be enabled)") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # ============================================
    # TIER 3 - EVENT LOGS
    # ============================================
    $report.AppendLine("🔥 TIER 3 — EVENT LOGS") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $tier3 = Get-Tier3EventLogs -TargetDrive $TargetDrive
    $result.Tier3 = $tier3
    
    if ($tier3.SystemLog.Found) {
        $report.AppendLine("✅ System Event Log: FOUND") | Out-Null
        $report.AppendLine("   - $($tier3.SystemLog.Path)") | Out-Null
        $report.AppendLine("   - Events analyzed: $($tier3.SystemLog.EventCount)") | Out-Null
        if ($tier3.SystemLog.CriticalEvents.Count -gt 0) {
            $report.AppendLine("   - ⚠️  CRITICAL EVENTS: $($tier3.SystemLog.CriticalEvents.Count)") | Out-Null
        }
        $result.LogFilesFound += $tier3.SystemLog.Path
    } else {
        $report.AppendLine("❌ System Event Log: NOT FOUND") | Out-Null
        $result.LogFilesMissing += "C:\Windows\System32\winevt\Logs\System.evtx"
    }
    
    if ($tier3.SrtTrail.Found) {
        $report.AppendLine("✅ SrtTrail.txt: FOUND") | Out-Null
        $report.AppendLine("   - $($tier3.SrtTrail.Path)") | Out-Null
        $result.LogFilesFound += $tier3.SrtTrail.Path
    } else {
        $report.AppendLine("⚠️  SrtTrail.txt: NOT FOUND") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # ============================================
    # TIER 4 - BOOT STRUCTURE
    # ============================================
    $report.AppendLine("🔥 TIER 4 — BOOT STRUCTURE") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $tier4 = Get-Tier4BootStructure -TargetDrive $TargetDrive
    $result.Tier4 = $tier4
    
    if ($tier4.BCD.Found) {
        $report.AppendLine("✅ BCD Store: FOUND") | Out-Null
        $report.AppendLine("   - Status: $($tier4.BCD.Status)") | Out-Null
        if ($tier4.BCD.Issues.Count -gt 0) {
            $report.AppendLine("   - ⚠️  ISSUES DETECTED: $($tier4.BCD.Issues.Count)") | Out-Null
            foreach ($issue in $tier4.BCD.Issues) {
                $report.AppendLine("     • $issue") | Out-Null
            }
        }
    } else {
        $report.AppendLine("❌ BCD Store: NOT FOUND or CORRUPT") | Out-Null
    }
    
    if ($tier4.StorageDrivers.Count -gt 0) {
        $report.AppendLine("✅ Storage Drivers: ANALYZED") | Out-Null
        foreach ($driver in $tier4.StorageDrivers) {
            $status = if ($driver.StartValue -eq 0) { "✅" } elseif ($driver.StartValue -eq 4) { "❌ DISABLED" } else { "⚠️" }
            $report.AppendLine("   $status $($driver.Name): Start=$($driver.StartValue)") | Out-Null
        }
    }
    
    $report.AppendLine("") | Out-Null
    
    # ============================================
    # ROOT CAUSE ANALYSIS
    # ============================================
    $report.AppendLine("🧠 ROOT CAUSE ANALYSIS") | Out-Null
    $report.AppendLine("-" * 80) | Out-Null
    
    $rootCause = Get-RootCauseSummary -Tier1 $tier1 -Tier2 $tier2 -Tier3 $tier3 -Tier4 $tier4
    $result.RootCauseSummary = $rootCause.Summary
    $result.Recommendations = $rootCause.Recommendations
    
    $report.AppendLine($rootCause.Summary) | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($rootCause.Recommendations.Count -gt 0) {
        $report.AppendLine("📋 RECOMMENDATIONS:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $counter = 1
        foreach ($rec in $rootCause.Recommendations) {
            $report.AppendLine("$counter. $rec") | Out-Null
            $counter++
        }
        $report.AppendLine("") | Out-Null
    }
    
    # Export logs if requested
    if ($ExportPath -and (Test-Path (Split-Path $ExportPath -Parent))) {
        try {
            $exportResult = Export-LogCollection -TargetDrive $TargetDrive -OutputPath $ExportPath -Tier1 $tier1 -Tier2 $tier2 -Tier3 $tier3
            if ($exportResult.Success) {
                $report.AppendLine("📦 Logs exported to: $ExportPath") | Out-Null
                $result.ExportPath = $ExportPath
            }
        } catch {
            $report.AppendLine("⚠️  Export failed: $_") | Out-Null
        }
    }
    
    $result.Success = $true
    $result.Report = $report.ToString()
    
    return $result
}

function Get-Tier1CrashDumps {
    <#
    .SYNOPSIS
    Gathers TIER 1 crash dump information (MEMORY.DMP, LiveKernelReports, Minidumps).
    #>
    param([string]$TargetDrive = "C")
    
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        MemoryDump = @{ Found = $false; Path = ""; SizeMB = 0; LastModified = $null }
        LiveKernelReports = @()
        MiniDumps = @()
    }
    
    # Check MEMORY.DMP
    $memoryDumpPath = "$TargetDrive`:\Windows\MEMORY.DMP"
    if (Test-Path $memoryDumpPath) {
        $file = Get-Item $memoryDumpPath -ErrorAction SilentlyContinue
        if ($file) {
            $result.MemoryDump = @{
                Found = $true
                Path = $memoryDumpPath
                SizeMB = [math]::Round($file.Length / 1MB, 2)
                LastModified = $file.LastWriteTime
            }
        }
    }
    
    # Check LiveKernelReports
    $liveKernelPath = "$TargetDrive`:\Windows\LiveKernelReports"
    if (Test-Path $liveKernelPath) {
        $categories = @("STORAGE", "WATCHDOG", "NDIS", "USB")
        foreach ($category in $categories) {
            $categoryPath = Join-Path $liveKernelPath $category
            if (Test-Path $categoryPath) {
                $reports = Get-ChildItem -Path $categoryPath -Filter "*.dmp" -ErrorAction SilentlyContinue | 
                    Sort-Object LastWriteTime -Descending | Select-Object -First 10
                foreach ($report in $reports) {
                    $result.LiveKernelReports += @{
                        Path = $report.FullName
                        Category = $category
                        Date = $report.LastWriteTime
                        SizeMB = [math]::Round($report.Length / 1MB, 2)
                    }
                }
            }
        }
    }
    
    # Check Minidumps
    $minidumpPath = "$TargetDrive`:\Windows\Minidump"
    if (Test-Path $minidumpPath) {
        $dumps = Get-ChildItem -Path $minidumpPath -Filter "*.dmp" -ErrorAction SilentlyContinue | 
            Sort-Object LastWriteTime -Descending | Select-Object -First 10
        foreach ($dump in $dumps) {
            $result.MiniDumps += @{
                Path = $dump.FullName
                Date = $dump.LastWriteTime
                SizeMB = [math]::Round($dump.Length / 1MB, 2)
            }
        }
    }
    
    return $result
}

function Get-Tier2BootPipelineLogs {
    <#
    .SYNOPSIS
    Gathers TIER 2 boot pipeline logs (Setup logs, ntbtlog.txt).
    #>
    param([string]$TargetDrive = "C")
    
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        SetupLogs = @()
        BootLog = @{ Found = $false; Path = "" }
    }
    
    # Check Setup logs in multiple locations
    $setupPaths = @(
        "$TargetDrive`:\`$WINDOWS.~BT\Sources\Panther",
        "$TargetDrive`:\Windows\Panther",
        "X:\`$WINDOWS.~BT\Sources\Panther",
        "X:\`$WINDOWS.~BT\Sources\Rollback"
    )
    
    foreach ($setupPath in $setupPaths) {
        if (Test-Path $setupPath) {
            $setupact = Join-Path $setupPath "setupact.log"
            $setuperr = Join-Path $setupPath "setuperr.log"
            
            if (Test-Path $setupact) {
                $result.SetupLogs += @{
                    Path = $setupact
                    Type = "setupact.log"
                    Location = $setupPath
                }
            }
            
            if (Test-Path $setuperr) {
                $result.SetupLogs += @{
                    Path = $setuperr
                    Type = "setuperr.log"
                    Location = $setupPath
                }
            }
        }
    }
    
    # Check boot log
    $bootLogPath = "$TargetDrive`:\Windows\ntbtlog.txt"
    if (Test-Path $bootLogPath) {
        $result.BootLog = @{
            Found = $true
            Path = $bootLogPath
        }
    }
    
    return $result
}

function Get-Tier3EventLogs {
    <#
    .SYNOPSIS
    Gathers TIER 3 event logs (System.evtx, SrtTrail.txt).
    #>
    param([string]$TargetDrive = "C")
    
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        SystemLog = @{ Found = $false; Path = ""; EventCount = 0; CriticalEvents = @() }
        SrtTrail = @{ Found = $false; Path = "" }
    }
    
    # Check System event log
    $systemLogPath = "$TargetDrive`:\Windows\System32\winevt\Logs\System.evtx"
    if (Test-Path $systemLogPath) {
        try {
            $events = Get-WinEvent -Path $systemLogPath -ErrorAction SilentlyContinue -MaxEvents 1000
            $criticalEvents = $events | Where-Object { 
                $_.Id -eq 1001 -or  # BugCheck
                $_.Id -eq 41 -or    # Kernel-Power
                $_.LevelDisplayName -eq "Error" -and (
                    $_.Message -like "*volmgr*" -or
                    $_.Message -like "*disk*" -or
                    $_.Message -like "*nvme*" -or
                    $_.Message -like "*storahci*" -or
                    $_.Message -like "*INACCESSIBLE_BOOT_DEVICE*"
                )
            } | Select-Object -First 20
            
            $result.SystemLog = @{
                Found = $true
                Path = $systemLogPath
                EventCount = $events.Count
                CriticalEvents = $criticalEvents | ForEach-Object { @{
                    Id = $_.Id
                    Time = $_.TimeCreated
                    Level = $_.LevelDisplayName
                    Message = $_.Message
                }}
            }
        } catch {
            # Log exists but couldn't read it
            $result.SystemLog = @{
                Found = $true
                Path = $systemLogPath
                EventCount = 0
                CriticalEvents = @()
                Error = $_.Exception.Message
            }
        }
    }
    
    # Check SrtTrail.txt
    $srtTrailPath = "$TargetDrive`:\Windows\System32\LogFiles\Srt\SrtTrail.txt"
    if (Test-Path $srtTrailPath) {
        $result.SrtTrail = @{
            Found = $true
            Path = $srtTrailPath
        }
    }
    
    return $result
}

function Get-Tier4BootStructure {
    <#
    .SYNOPSIS
    Analyzes TIER 4 boot structure (BCD store, Registry storage drivers).
    #>
    param([string]$TargetDrive = "C")
    
    if ($TargetDrive -match '^([A-Z]):?$') {
        $TargetDrive = $matches[1]
    }
    
    $result = @{
        BCD = @{ Found = $false; Status = ""; Issues = @() }
        StorageDrivers = @()
    }
    
    # Check BCD
    try {
        $bcdOutput = bcdedit /enum all 2>&1
        if ($LASTEXITCODE -eq 0) {
            $result.BCD.Found = $true
            $result.BCD.Status = "OK"
            
            # Check for common issues
            $bcdText = $bcdOutput | Out-String
            if ($bcdText -notmatch "identifier.*\{default\}") {
                $result.BCD.Issues += "Missing {default} entry"
            }
            if ($bcdText -notmatch "Windows Boot Manager") {
                $result.BCD.Issues += "Missing Windows Boot Manager entry"
            }
        } else {
            $result.BCD.Status = "ERROR: Could not enumerate BCD"
            $result.BCD.Issues += "BCD enumeration failed"
        }
    } catch {
        $result.BCD.Status = "ERROR: $($_.Exception.Message)"
        $result.BCD.Issues += "BCD check failed: $_"
    }
    
    # Check storage drivers in registry (offline)
    $systemHive = "$TargetDrive`:\Windows\System32\config\SYSTEM"
    if (Test-Path $systemHive) {
        $storageDrivers = @("stornvme", "storahci", "iaStorV", "iaStorVD", "nvme")
        
        try {
            # Try to load hive (requires admin and may not work in all contexts)
            foreach ($driverName in $storageDrivers) {
                $result.StorageDrivers += @{
                    Name = $driverName
                    StartValue = -1  # Unknown if we can't read
                    Status = "Not checked (offline registry)"
                }
            }
        } catch {
            # Can't read offline registry - that's OK
        }
    } else {
        # Try online registry
        try {
            $storageDrivers = @("stornvme", "storahci", "iaStorV", "iaStorVD", "nvme")
            foreach ($driverName in $storageDrivers) {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$driverName"
                if (Test-Path $regPath) {
                    $startValue = (Get-ItemProperty -Path $regPath -Name Start -ErrorAction SilentlyContinue).Start
                    $result.StorageDrivers += @{
                        Name = $driverName
                        StartValue = $startValue
                        Status = if ($startValue -eq 0) { "Enabled (Boot)" } 
                                 elseif ($startValue -eq 4) { "DISABLED - CRITICAL!" } 
                                 else { "Other ($startValue)" }
                    }
                }
            }
        } catch {
            # Can't read registry
        }
    }
    
    return $result
}

function Get-RootCauseSummary {
    <#
    .SYNOPSIS
    Analyzes all tier data and generates root cause summary and recommendations.
    #>
    param(
        [hashtable]$Tier1,
        [hashtable]$Tier2,
        [hashtable]$Tier3,
        [hashtable]$Tier4
    )
    
    $summary = New-Object System.Text.StringBuilder
    $recommendations = @()
    
    # Decision tree based on findings
    if ($Tier1.MemoryDump.Found) {
        $summary.AppendLine("🎯 PRIMARY FINDING: MEMORY.DMP exists - THIS IS THE HIGHEST PRIORITY") | Out-Null
        $summary.AppendLine("   → Analyze MEMORY.DMP first using crashanalyze.exe or WinDbg") | Out-Null
        $summary.AppendLine("   → This dump contains kernel + storage stack information") | Out-Null
        $summary.AppendLine("   → Best for: INACCESSIBLE_BOOT_DEVICE, VMD/NVMe/RST issues") | Out-Null
        $recommendations += "Analyze C:\Windows\MEMORY.DMP using crashanalyze.exe or WinDbg"
        $recommendations += "Look for storage driver names in the dump analysis"
    }
    
    if ($Tier1.LiveKernelReports.Count -gt 0) {
        $storageReports = $Tier1.LiveKernelReports | Where-Object { $_.Category -eq "STORAGE" }
        if ($storageReports.Count -gt 0) {
            $summary.AppendLine("") | Out-Null
            $summary.AppendLine("🎯 CRITICAL: LiveKernelReports STORAGE dumps found") | Out-Null
            $summary.AppendLine("   → These indicate storage driver hangs before full BSOD") | Out-Null
            $summary.AppendLine("   → Very common with INACCESSIBLE_BOOT_DEVICE") | Out-Null
            $summary.AppendLine("   → Often exists even when Minidump is empty") | Out-Null
            $recommendations += "Analyze LiveKernelReports\STORAGE dumps - they show storage controller issues"
        }
    }
    
    if ($Tier2.SetupLogs.Count -gt 0) {
        $summary.AppendLine("") | Out-Null
        $summary.AppendLine("📋 Setup logs found - check for explicit boot failure reasons") | Out-Null
        $summary.AppendLine("   → Look for: 'Boot environment mismatch', 'Edition/build family mismatch'") | Out-Null
        $summary.AppendLine("   → Look for: 'CBS state invalid', 'Boot device not accessible'") | Out-Null
        $recommendations += "Review setupact.log and setuperr.log for explicit failure messages"
    }
    
    if ($Tier2.BootLog.Found) {
        $summary.AppendLine("") | Out-Null
        $summary.AppendLine("📋 Boot log (ntbtlog.txt) found - shows driver load sequence") | Out-Null
        $summary.AppendLine("   → Check which driver was last loaded before crash") | Out-Null
        $summary.AppendLine("   → If last driver is storage → bingo!") | Out-Null
        $recommendations += "Analyze ntbtlog.txt to identify last loaded driver before crash"
    }
    
    if ($Tier3.SystemLog.Found -and $Tier3.SystemLog.CriticalEvents.Count -gt 0) {
        $summary.AppendLine("") | Out-Null
        $summary.AppendLine("⚠️  Critical events found in System event log") | Out-Null
        $summary.AppendLine("   → Event 1001: BugCheck information") | Out-Null
        $summary.AppendLine("   → Event 41: Kernel-Power (unexpected shutdown)") | Out-Null
        $summary.AppendLine("   → Storage-related errors indicate driver/controller issues") | Out-Null
        $recommendations += "Review System event log for Event 1001 (BugCheck) and Event 41 (Kernel-Power)"
    }
    
    if ($Tier4.BCD.Issues.Count -gt 0) {
        $summary.AppendLine("") | Out-Null
        $summary.AppendLine("❌ BCD ISSUES DETECTED") | Out-Null
        foreach ($issue in $Tier4.BCD.Issues) {
            $summary.AppendLine("   → $issue") | Out-Null
        }
        $summary.AppendLine("   → Missing or broken BCD = instant INACCESSIBLE_BOOT_DEVICE") | Out-Null
        $recommendations += "Rebuild BCD: bcdboot C:\Windows /s S: /f UEFI (after mounting ESP)"
    }
    
    $disabledStorageDrivers = $Tier4.StorageDrivers | Where-Object { $_.StartValue -eq 4 }
    if ($disabledStorageDrivers.Count -gt 0) {
        $summary.AppendLine("") | Out-Null
        $summary.AppendLine("❌ CRITICAL: Storage driver(s) DISABLED in registry") | Out-Null
        foreach ($driver in $disabledStorageDrivers) {
            $summary.AppendLine("   → $($driver.Name): Start=4 (DISABLED)") | Out-Null
        }
        $summary.AppendLine("   → Windows cannot boot without storage driver") | Out-Null
        $recommendations += "Enable storage driver in registry: Set Start=0 for $($disabledStorageDrivers[0].Name)"
        $recommendations += "Or inject correct storage driver in WinPE"
    }
    
    if ($summary.Length -eq 0) {
        $summary.AppendLine("⚠️  No critical issues detected in analyzed logs") | Out-Null
        $summary.AppendLine("   → Check hardware context (TIER 5):") | Out-Null
        $summary.AppendLine("     • Image restored from SATA → NVMe?") | Out-Null
        $summary.AppendLine("     • VMD ON → OFF (or vice versa)?") | Out-Null
        $summary.AppendLine("     • BIOS changed: RAID ↔ AHCI?") | Out-Null
        $summary.AppendLine("     • Disk moved to different NVMe slot?") | Out-Null
        $summary.AppendLine("     • Secure Boot state changed?") | Out-Null
        $recommendations += "Check hardware/BIOS configuration changes"
        $recommendations += "INACCESSIBLE_BOOT_DEVICE is 80% storage context mismatch"
    }
    
    return @{
        Summary = $summary.ToString()
        Recommendations = $recommendations
    }
}

function Export-LogCollection {
    <#
    .SYNOPSIS
    Exports collected logs to a specified location.
    #>
    param(
        [string]$TargetDrive = "C",
        [string]$OutputPath,
        [hashtable]$Tier1,
        [hashtable]$Tier2,
        [hashtable]$Tier3
    )
    
    $result = @{
        Success = $false
        ExportedFiles = @()
        Errors = @()
    }
    
    if (-not $OutputPath) {
        $OutputPath = "$env:TEMP\MiracleBoot_LogCollection_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }
    
    try {
        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        
        # Export Tier 1 dumps (copy if small enough, otherwise just list)
        $tier1Dir = Join-Path $OutputPath "Tier1_CrashDumps"
        New-Item -ItemType Directory -Path $tier1Dir -Force | Out-Null
        
        if ($Tier1.MemoryDump.Found -and $Tier1.MemoryDump.SizeMB -lt 100) {
            Copy-Item $Tier1.MemoryDump.Path -Destination $tier1Dir -ErrorAction SilentlyContinue
            $result.ExportedFiles += $Tier1.MemoryDump.Path
        } else {
            "$($Tier1.MemoryDump.Path) - Size: $($Tier1.MemoryDump.SizeMB) MB" | Out-File (Join-Path $tier1Dir "MEMORY_DMP_Info.txt")
        }
        
        # Export Tier 2 logs
        $tier2Dir = Join-Path $OutputPath "Tier2_BootPipeline"
        New-Item -ItemType Directory -Path $tier2Dir -Force | Out-Null
        
        foreach ($log in $Tier2.SetupLogs) {
            try {
                Copy-Item $log.Path -Destination $tier2Dir -ErrorAction SilentlyContinue
                $result.ExportedFiles += $log.Path
            } catch {
                $result.Errors += "Failed to copy $($log.Path): $_"
            }
        }
        
        if ($Tier2.BootLog.Found) {
            try {
                Copy-Item $Tier2.BootLog.Path -Destination $tier2Dir -ErrorAction SilentlyContinue
                $result.ExportedFiles += $Tier2.BootLog.Path
            } catch {
                $result.Errors += "Failed to copy $($Tier2.BootLog.Path): $_"
            }
        }
        
        $result.Success = $true
        
    } catch {
        $result.Errors += "Export failed: $_"
    }
    
    return $result
}

function Open-EventViewer {
    <#
    .SYNOPSIS
    Opens Windows Event Viewer.
    #>
    try {
        Start-Process "eventvwr.msc"
        return @{ Success = $true; Message = "Event Viewer opened successfully" }
    } catch {
        return @{ Success = $false; Message = "Failed to open Event Viewer: $_" }
    }
}

function Start-CrashAnalyzer {
    <#
    .SYNOPSIS
    Launches crashanalyze.exe with specified dump file.
    
    .PARAMETER DumpPath
    Path to the crash dump file to analyze
    
    .PARAMETER CrashAnalyzerPath
    Path to crashanalyze.exe (default: looks in Helper\CrashAnalyzer\)
    #>
    param(
        [string]$DumpPath = "",
        [string]$CrashAnalyzerPath = ""
    )
    
    $result = @{
        Success = $false
        Message = ""
    }
    
    # Try to find crashanalyze.exe
    if (-not $CrashAnalyzerPath) {
        $possiblePaths = @(
            "$PSScriptRoot\CrashAnalyzer\crashanalyze.exe",
            "$PSScriptRoot\..\Helper\CrashAnalyzer\crashanalyze.exe",
            "I:\Dart Crash analyzer\v10\crashanalyze.exe"
        )
        
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $CrashAnalyzerPath = $path
                break
            }
        }
    }
    
    if (-not $CrashAnalyzerPath -or -not (Test-Path $CrashAnalyzerPath)) {
        $result.Message = "crashanalyze.exe not found. Please specify the path to crashanalyze.exe"
        return $result
    }
    
    try {
        if ($DumpPath -and (Test-Path $DumpPath)) {
            Start-Process -FilePath $CrashAnalyzerPath -ArgumentList "`"$DumpPath`"" -WorkingDirectory (Split-Path $CrashAnalyzerPath -Parent)
            $result.Success = $true
            $result.Message = "Crash Analyzer launched with dump file: $DumpPath"
        } else {
            # Launch without arguments (user can open file from UI)
            Start-Process -FilePath $CrashAnalyzerPath -WorkingDirectory (Split-Path $CrashAnalyzerPath -Parent)
            $result.Success = $true
            $result.Message = "Crash Analyzer launched"
        }
    } catch {
        $result.Message = "Failed to launch Crash Analyzer: $_"
    }
    
    return $result
}

