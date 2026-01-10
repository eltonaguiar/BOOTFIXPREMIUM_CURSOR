<#
.SYNOPSIS
    MiracleBoot Pro: Forensic Boot Analyzer & Auto-Repair.
    Diagnostic Engine - Not just a toolbox, but an authoritative diagnosis system.

.DESCRIPTION
    This is the "Brain" of MiracleBoot - transforms from toolbox to diagnostic engine.
    Provides authoritative diagnosis with boot-chain awareness and human-readable explanations.

.PARAMETER Mode
    Operation mode: 'Analyze', 'Repair', 'Monitor', or 'Full'

.PARAMETER TargetDrive
    Target Windows drive (auto-detected if not specified)

.PARAMETER MonitorLogs
    Enable real-time log monitoring mode

.EXAMPLE
    .\MiracleBootPro.ps1 -Mode Full
    
    Performs complete forensic analysis with authoritative diagnosis.
#>

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet('Analyze', 'Repair', 'Monitor', 'Full')]
    [string]$Mode = 'Full',

    [Parameter(Mandatory=$false)]
    [string]$TargetDrive = $null,

    [Parameter(Mandatory=$false)]
    [switch]$MonitorLogs = $false
)

# --- ENHANCED ERROR CODE DATABASE (Authoritative) ---
$Global:ErrorDB = @{
    "0xc000000e" = @{
        Description = "Winload.efi missing or corrupt"
        HumanExplanation = "Windows boot loader file is missing or damaged. This usually happens after disk errors, failed updates, or BCD corruption."
        Stage = "Boot Loader"
        LikelyCauses = @(
            "BCD corruption",
            "EFI partition damage",
            "Failed Windows Update",
            "Disk errors"
        )
        RecommendedActions = @(
            "Rebuild BCD",
            "Check EFI partition",
            "Run chkdsk",
            "Restore from backup"
        )
        Command = "bootrec /rebuildbcd"
        Severity = "Critical"
        Confidence = 95
    }
    "0xc0000001" = @{
        Description = "Required device isn't connected or can't be accessed"
        HumanExplanation = "Windows cannot access the storage device. This is often a driver issue, SATA mode mismatch, or physical connection problem."
        Stage = "Hardware"
        LikelyCauses = @(
            "Missing storage driver",
            "SATA mode mismatch (AHCI vs RAID)",
            "Loose SATA cable",
            "Failing storage device"
        )
        RecommendedActions = @(
            "Check BIOS storage mode",
            "Inject storage drivers",
            "Check physical connections",
            "Test with different drive"
        )
        Command = "chkdsk /f /r"
        Severity = "Critical"
        Confidence = 90
    }
    "INACCESSIBLE_BOOT_DEVICE" = @{
        Description = "Windows cannot access the boot device"
        HumanExplanation = "Your PC cannot find or access the storage drive where Windows is installed. This is common after restoring a backup to different hardware or when storage drivers are missing."
        Stage = "Kernel"
        LikelyCauses = @(
            "Missing storage driver (Intel VMD, AMD RAID, etc.)",
            "VMD/RAID mode mismatch",
            "Restored image from different controller",
            "Driver disabled in registry"
        )
        RecommendedActions = @(
            "Inject storage drivers",
            "Check BIOS storage mode",
            "Enable driver in registry",
            "Rebuild BCD after driver load"
        )
        Command = "Inject drivers, then rebuild BCD"
        Severity = "Critical"
        Confidence = 92
    }
    "0x80070002" = @{
        Description = "The system cannot find the file specified"
        HumanExplanation = "Windows cannot find a required file. This can occur during boot (BCD pointing to wrong location) or during setup/upgrade (missing system files or corrupted installation source)."
        Stage = "File System/Setup"
        LikelyCauses = @(
            "Corrupted system files",
            "BCD pointing to wrong partition",
            "Missing Windows files",
            "Disk errors",
            "Corrupted installation source (ISO/USB)",
            "Incomplete Windows Update download"
        )
        RecommendedActions = @(
            "Verify SystemDrive mapping",
            "Run SFC scan (sfc /scannow)",
            "Rebuild BCD (bootrec /rebuildbcd)",
            "Check disk for errors (chkdsk)",
            "Verify installation source integrity",
            "Re-download Windows Update or use different ISO"
        )
        Command = "sfc /scannow and verify installation source"
        Severity = "High"
        Confidence = 85
    }
    "0xc000021a" = @{
        Description = "Critical Service Failure (ntdll.dll/csrss.exe)"
        HumanExplanation = "A critical Windows service has crashed. This usually means system files are corrupted or incompatible drivers are loaded."
        Stage = "Kernel"
        LikelyCauses = @(
            "Corrupted system files",
            "Incompatible driver",
            "Registry corruption",
            "Malware damage"
        )
        RecommendedActions = @(
            "Run SFC offline scan",
            "Check for incompatible drivers",
            "Scan for malware",
            "System Restore"
        )
        Command = "sfc /scannow /offbootdir={DRIVE}:\ /offwindir={DRIVE}:\Windows"
        Severity = "Critical"
        Confidence = 88
    }
    "0xc0000221" = @{
        Description = "Driver or system DLL is missing or corrupt"
        HumanExplanation = "A critical driver or system file is missing or damaged. This prevents Windows from starting properly."
        Stage = "Driver"
        LikelyCauses = @(
            "Corrupted driver files",
            "Missing system DLLs",
            "Component Store corruption",
            "Failed Windows Update"
        )
        RecommendedActions = @(
            "Run DISM repair",
            "Run SFC scan",
            "Restore from backup",
            "Repair install"
        )
        Command = "dism /image:{DRIVE}:\ /cleanup-image /restorehealth"
        Severity = "Critical"
        Confidence = 90
    }
    "0xc0000142" = @{
        Description = "Application initialization failed"
        HumanExplanation = "Windows cannot start a critical application. This is often caused by corrupted system files or registry issues."
        Stage = "Application"
        LikelyCauses = @(
            "Corrupted system files",
            "Registry corruption",
            "Missing dependencies",
            "File permissions"
        )
        RecommendedActions = @(
            "Run SFC scan",
            "Check system files",
            "Verify registry integrity",
            "System Restore"
        )
        Command = "sfc /scannow"
        Severity = "High"
        Confidence = 80
    }
    "0x80070003" = @{
        Description = "The system cannot find the path specified"
        HumanExplanation = "Windows is trying to access a path that doesn't exist. This usually means the boot configuration is pointing to the wrong location."
        Stage = "Boot Configuration"
        LikelyCauses = @(
            "BCD pointing to wrong partition",
            "Moved Windows installation",
            "Corrupted BCD",
            "Missing partition"
        )
        RecommendedActions = @(
            "Verify boot configuration",
            "Rebuild BCD",
            "Check partition layout",
            "Fix partition letters"
        )
        Command = "bcdedit /enum all"
        Severity = "High"
        Confidence = 85
    }
    "0xc0000098" = @{
        Description = "STATUS_INSUFFICIENT_RESOURCES"
        HumanExplanation = "Windows doesn't have enough resources (memory or disk space) to start. This is usually a disk space issue."
        Stage = "Resource"
        LikelyCauses = @(
            "Low disk space",
            "Memory issues",
            "Too many startup programs",
            "Page file problems"
        )
        RecommendedActions = @(
            "Free up disk space",
            "Check available memory",
            "Disable startup programs",
            "Check page file"
        )
        Command = "Check disk space and available memory"
        Severity = "Medium"
        Confidence = 75
    }
    "0xC1900101" = @{
        Description = "Driver failure during Windows Setup"
        HumanExplanation = "Windows Setup failed because a driver caused a problem during installation. This is often a storage driver (NVMe, RAID, or VMD controller) that's incompatible or missing."
        Stage = "Setup/Upgrade"
        LikelyCauses = @(
            "Incompatible storage driver",
            "Missing NVMe/RAID/VMD driver",
            "Driver conflict during upgrade",
            "Outdated driver incompatible with new Windows version"
        )
        RecommendedActions = @(
            "Update or remove the problematic driver",
            "Inject compatible storage drivers",
            "Check device manager for driver errors",
            "Disable incompatible drivers before upgrade"
        )
        Command = "Update drivers or inject compatible storage drivers"
        Severity = "Critical"
        Confidence = 90
    }
    "0x800F0922" = @{
        Description = "DISM failed - Reserved partition or servicing stack issue"
        HumanExplanation = "Windows cannot update because the reserved partition is missing, too small, or the servicing stack (component store) is corrupted. This prevents Windows Update and in-place upgrades."
        Stage = "Servicing Stack"
        LikelyCauses = @(
            "Missing or corrupted reserved partition",
            "Reserved partition too small",
            "Component store (CBS) corruption",
            "Servicing stack corruption"
        )
        RecommendedActions = @(
            "Run DISM /RestoreHealth to repair component store",
            "Check reserved partition size and integrity",
            "Repair servicing stack with DISM",
            "May require manual reserved partition repair"
        )
        Command = "dism /online /cleanup-image /restorehealth"
        Severity = "Critical"
        Confidence = 88
    }
    "0xC1900208" = @{
        Description = "Incompatible software blocking Windows Setup"
        HumanExplanation = "Windows Setup detected incompatible software that prevents the upgrade from completing. This is often antivirus software, security tools, or legacy applications."
        Stage = "Compatibility"
        LikelyCauses = @(
            "Incompatible antivirus software",
            "Legacy security tools",
            "Outdated applications",
            "OEM-specific software conflicts"
        )
        RecommendedActions = @(
            "Uninstall or update incompatible software",
            "Temporarily disable antivirus",
            "Check Windows Compatibility Center",
            "Remove conflicting applications before upgrade"
        )
        Command = "Uninstall incompatible software, then retry upgrade"
        Severity = "High"
        Confidence = 85
    }
}

# --- BOOT STAGE DETECTION (Authoritative) ---

function Get-BootStage {
    <#
    .SYNOPSIS
        Identifies exact boot failure stage with confidence.
    #>
    param(
        [string]$WindowsDrive,
        [object]$Forensics
    )
    
    $stage = @{
        Stage = "Unknown"
        Confidence = 0
        Evidence = @()
        HumanExplanation = "Unable to determine boot failure stage."
    }
    
    # Check for EFI vs Legacy
    $efiPartition = Get-Partition | Where-Object { $_.Type -eq 'EFI' -or $_.GptType -eq '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' }
    $isUEFI = $efiPartition.Count -gt 0
    
    if ($isUEFI) {
        $stage.Evidence += "UEFI boot detected"
    } else {
        $stage.Evidence += "Legacy BIOS boot detected"
    }
    
    # Check BCD status
    try {
        $bcdOutput = bcdedit /enum all 2>&1
        if ($LASTEXITCODE -eq 0) {
            $stage.Evidence += "BCD accessible"
            
            # Check for missing entries
            if ($bcdOutput -notmatch "Windows Boot Loader") {
                $stage.Stage = "Boot Manager"
                $stage.Confidence = 95
                $stage.HumanExplanation = "Boot Configuration Data (BCD) is missing Windows Boot Loader entries. Windows cannot start because the boot manager doesn't know where to find Windows."
                return $stage
            }
        } else {
            $stage.Stage = "Boot Manager"
            $stage.Confidence = 90
            $stage.HumanExplanation = "BCD is corrupted or inaccessible. The boot manager cannot read the boot configuration."
            return $stage
        }
    } catch {
        $stage.Stage = "Boot Manager"
        $stage.Confidence = 85
        $stage.HumanExplanation = "Cannot access BCD. Boot configuration may be corrupted."
        return $stage
    }
    
    # Check boot log for driver failures
    $bootLogPath = "${WindowsDrive}:\Windows\ntbtlog.txt"
    if (Test-Path $bootLogPath) {
        $bootLog = Get-Content $bootLogPath -ErrorAction SilentlyContinue | Select-Object -Last 200
        
        $lastLoaded = $bootLog | Where-Object { $_ -match "Loaded driver" } | Select-Object -Last 1
        $firstFailed = $bootLog | Where-Object { $_ -match "Did not load driver|Failed to load" } | Select-Object -First 1
        
        if ($firstFailed) {
            $driverName = if ($firstFailed -match "\\\\([^\\]+\.sys)") { $matches[1] } else { "unknown" }
            
            $stage.Stage = "Driver Initialization"
            $stage.Confidence = 92
            $stage.HumanExplanation = "Windows fails during driver initialization. The driver '$driverName' failed to load. This is often a storage driver issue (Intel VMD, AMD RAID, or NVMe controller)."
            $stage.Evidence += "Failed driver: $driverName"
            return $stage
        }
        
        if ($lastLoaded) {
            $stage.Stage = "Driver Initialization"
            $stage.Confidence = 70
            $stage.HumanExplanation = "Windows is loading drivers but may be failing during initialization."
            $stage.Evidence += "Last loaded: $($lastLoaded -replace '.*Loaded driver\s+', '')"
        }
    }
    
    # Check for INACCESSIBLE_BOOT_DEVICE
    if ($Forensics.ErrorCode -eq "INACCESSIBLE_BOOT_DEVICE" -or 
        $Forensics.ErrorDetails.Description -match "INACCESSIBLE_BOOT_DEVICE") {
        $stage.Stage = "Kernel"
        $stage.Confidence = 95
        $stage.HumanExplanation = "Windows kernel cannot access the boot device. This is common when storage drivers are missing or disabled, especially after restoring a backup to different hardware."
        return $stage
    }
    
    # Check Panther logs for setup failures
    $pantherPath = "${WindowsDrive}:\Windows\Panther\setupact.log"
    if (Test-Path $pantherPath) {
        $pantherContent = Get-Content $pantherPath -ErrorAction SilentlyContinue | Select-Object -Last 1000
        
        if ($pantherContent -match "FirstBoot|OOBE") {
            $stage.Stage = "Post-Setup / First Boot"
            $stage.Confidence = 85
            $stage.HumanExplanation = "Windows Setup completed but failed during first boot or out-of-box experience."
            return $stage
        }
        
        if ($pantherContent -match "Install|Upgrade") {
            $stage.Stage = "Installation Phase"
            $stage.Confidence = 80
            $stage.HumanExplanation = "Windows Setup is failing during the installation or upgrade phase."
            return $stage
        }
    }
    
    # Default based on error code
    if ($Forensics.ErrorDetails) {
        $stage.Stage = $Forensics.ErrorDetails.Stage
        $stage.Confidence = $Forensics.ErrorDetails.Confidence
        $stage.HumanExplanation = $Forensics.ErrorDetails.HumanExplanation
    }
    
    return $stage
}

# --- DEEP PANTHER LOG INTELLIGENCE ---

function Invoke-PantherIntelligence {
    <#
    .SYNOPSIS
        Deep analysis of Panther logs to extract blocking rules and failures.
    #>
    param([string]$WindowsDrive)
    
    Write-Host "[!] Deep Panther Log Analysis..." -ForegroundColor Cyan
    Write-Host ""
    
    $report = @{
        BlockingRule = $null
        BlockType = $null # HardBlock, SoftBlock, Compatibility
        FailureReason = $null
        DriverIssues = @()
        CompatibilityIssues = @()
        CBSIssues = @()
        EditionMismatch = $false
    }
    
    # Check multiple Panther locations
    $pantherPaths = @(
        "${WindowsDrive}:\Windows\Panther\setupact.log",
        "${WindowsDrive}:\Windows\Panther\setuperr.log",
        "${WindowsDrive}:\`$WINDOWS.~BT\Sources\Panther\setupact.log",
        "${WindowsDrive}:\`$WINDOWS.~BT\Sources\Panther\setuperr.log",
        "X:\Sources\Panther\setupact.log"
    )
    
    $activePantherPath = $null
    foreach ($path in $pantherPaths) {
        if (Test-Path $path) {
            $activePantherPath = $path
            Write-Host "  [FOUND] Panther Log: $path" -ForegroundColor Green
            break
        }
    }
    
    if (-not $activePantherPath) {
        Write-Host "  [NOT FOUND] Panther logs" -ForegroundColor Yellow
        return $report
    }
    
    $pantherContent = Get-Content $activePantherPath -ErrorAction SilentlyContinue
    
    # Extract blocking rules
    $blockingRules = $pantherContent | Where-Object { 
        $_ -match "Blocking|HardBlock|SoftBlock|Compatibility" -or
        $_ -match "Setup cannot continue|Upgrade blocked"
    }
    
    if ($blockingRules) {
        $lastBlock = $blockingRules | Select-Object -Last 1
        $report.BlockingRule = $lastBlock.Trim()
        
        if ($lastBlock -match "HardBlock") {
            $report.BlockType = "HardBlock"
            Write-Host "  [HARD BLOCK] In-place upgrade is blocked" -ForegroundColor Red
        } elseif ($lastBlock -match "SoftBlock") {
            $report.BlockType = "SoftBlock"
            Write-Host "  [SOFT BLOCK] Upgrade has warnings but may proceed" -ForegroundColor Yellow
        } elseif ($lastBlock -match "Compatibility") {
            $report.BlockType = "Compatibility"
            Write-Host "  [COMPATIBILITY] Compatibility issue detected" -ForegroundColor Yellow
        }
    }
    
    # Extract driver rejection reasons
    $driverRejects = $pantherContent | Where-Object {
        $_ -match "driver.*reject|driver.*rank|driver.*fail" -or
        $_ -match "iaStor|vmd|storahci|nvme" -and $_ -match "fail|error|missing"
    }
    
    foreach ($reject in $driverRejects | Select-Object -First 10) {
        if ($reject -match "iaStor|Intel.*Storage|Rapid.*Storage") {
            $report.DriverIssues += "Intel Rapid Storage driver issue: $($reject.Trim())"
        } elseif ($reject -match "vmd|VMD") {
            $report.DriverIssues += "Intel VMD driver issue: $($reject.Trim())"
        } elseif ($reject -match "storahci|stornvme") {
            $report.DriverIssues += "Storage driver issue: $($reject.Trim())"
        }
    }
    
    # Check for edition mismatch
    if ($pantherContent -match "Edition.*mismatch|Cannot.*upgrade.*edition") {
        $report.EditionMismatch = $true
        Write-Host "  [ISSUE] Edition mismatch detected" -ForegroundColor Yellow
    }
    
    # Check setupapi.dev.log for device installation failures
    $setupapiPath = "${WindowsDrive}:\Windows\inf\setupapi.dev.log"
    if (Test-Path $setupapiPath) {
        $setupapiContent = Get-Content $setupapiPath -ErrorAction SilentlyContinue | Select-Object -Last 500
        
        $deviceFailures = $setupapiContent | Where-Object {
            $_ -match "failed to install|installation failed|driver.*not.*found"
        }
        
        foreach ($failure in $deviceFailures | Select-Object -First 5) {
            if ($failure -match "STOR|SCSI|PCI\\VEN") {
                $report.DriverIssues += "Device installation failure: $($failure.Trim())"
            }
        }
    }
    
    # Extract specific failure reason
    $failurePatterns = @(
        "Intel.*Rapid.*Storage.*driver.*missing",
        "VMD.*driver.*required",
        "Storage.*controller.*not.*found",
        "Driver.*rank.*rejection",
        "Compatibility.*check.*failed"
    )
    
    foreach ($pattern in $failurePatterns) {
        $match = $pantherContent | Where-Object { $_ -match $pattern } | Select-Object -Last 1
        if ($match) {
            $report.FailureReason = $match.Trim()
            Write-Host "  [REASON] $($match.Trim())" -ForegroundColor Yellow
            break
        }
    }
    
    return $report
}

# --- OFFLINE REGISTRY INTELLIGENCE ---

function Invoke-OfflineRegistryAnalysis {
    <#
    .SYNOPSIS
        Analyzes offline registry hives to detect driver and service issues.
    #>
    param([string]$WindowsDrive)
    
    Write-Host "[!] Offline Registry Analysis..." -ForegroundColor Cyan
    Write-Host ""
    
    $report = @{
        MissingDrivers = @()
        DisabledDrivers = @()
        MissingServices = @()
        CorruptControlSet = $false
        MountedDevicesIssues = $false
    }
    
    $systemHive = "${WindowsDrive}:\Windows\System32\config\SYSTEM"
    
    if (-not (Test-Path $systemHive)) {
        Write-Host "  [WARNING] Cannot access SYSTEM hive (may need WinPE/WinRE)" -ForegroundColor Yellow
        return $report
    }
    
    try {
        # Load SYSTEM hive
        $tempKey = "HKLM\MB_TEMP_SYSTEM"
        reg load $tempKey $systemHive 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [LOADED] SYSTEM hive" -ForegroundColor Green
            
            # Check for critical storage drivers
            $criticalDrivers = @("storahci", "iaStorVD", "vmd", "stornvme", "pciide")
            
            foreach ($driver in $criticalDrivers) {
                $driverPath = "$tempKey\CurrentControlSet\Services\$driver"
                try {
                    $driverKey = Get-Item "Registry::$driverPath" -ErrorAction Stop
                    $startValue = (Get-ItemProperty "Registry::$driverPath" -Name "Start" -ErrorAction SilentlyContinue).Start
                    
                    if ($startValue -eq 4) {
                        $report.DisabledDrivers += "$driver (disabled - Start=4)"
                        Write-Host "    [ISSUE] $driver is disabled" -ForegroundColor Yellow
                    } elseif ($startValue -eq 0 -or $startValue -eq 1) {
                        Write-Host "    [OK] $driver is enabled (Start=$startValue)" -ForegroundColor Green
                    }
                } catch {
                    $report.MissingDrivers += "$driver (not found in registry)"
                    Write-Host "    [MISSING] $driver not found" -ForegroundColor Red
                }
            }
            
            # Check ControlSet integrity
            try {
                $controlSets = Get-Item "Registry::$tempKey" | Get-ChildItem | Where-Object { $_.Name -match "ControlSet" }
                if ($controlSets.Count -lt 1) {
                    $report.CorruptControlSet = $true
                    Write-Host "  [CRITICAL] No valid ControlSet found" -ForegroundColor Red
                }
            } catch {
                $report.CorruptControlSet = $true
                Write-Host "  [CRITICAL] Cannot read ControlSet" -ForegroundColor Red
            }
            
            # Unload hive
            reg unload $tempKey 2>&1 | Out-Null
        } else {
            Write-Host "  [ERROR] Could not load SYSTEM hive" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [ERROR] Registry analysis failed: $_" -ForegroundColor Red
    }
    
    return $report
}

# --- ENHANCED BOOT FORENSICS ---

function Invoke-BootForensics {
    <#
    .SYNOPSIS
        Enhanced boot chain forensics with authoritative diagnosis.
    #>
    param([string]$WindowsDrive = $null)
    
    Write-Host "[!] Analyzing Boot Chain Stage..." -ForegroundColor Cyan
    Write-Host ""
    
    # Auto-detect Windows drive if not provided
    if (-not $WindowsDrive) {
        $WindowsDrive = $env:SystemDrive.TrimEnd(':')
        if ($WindowsDrive -eq "X") {
            # In WinPE/WinRE, find Windows drive
            $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemLabel } | Sort-Object DriveLetter
            foreach ($vol in $volumes) {
                $testPath = "$($vol.DriveLetter):\Windows\System32"
                if (Test-Path $testPath) {
                    $WindowsDrive = $vol.DriveLetter
                    Write-Host "  Detected Windows drive: ${WindowsDrive}:" -ForegroundColor Green
                    break
                }
            }
        }
    }
    
    $report = @{
        WindowsDrive = $WindowsDrive
        Stage = "Unknown"
        ErrorCode = $null
        ErrorDetails = $null
        Recommendation = "Manual Inspection"
        BootLogFound = $false
        PantherLogFound = $false
        LogPaths = @{}
        Confidence = 0
        HumanExplanation = "Unable to determine the cause of boot failure."
    }
    
    # Check Boot Log (ntbtlog.txt)
    $bootLogPath = "${WindowsDrive}:\Windows\ntbtlog.txt"
    if (Test-Path $bootLogPath) {
        Write-Host "  [FOUND] Boot Log: $bootLogPath" -ForegroundColor Green
        $report.BootLogFound = $true
        $report.LogPaths.BootLog = $bootLogPath
        
        # Analyze boot log for failure points
        $bootLogContent = Get-Content $bootLogPath -ErrorAction SilentlyContinue | Select-Object -Last 200
        $lastLoaded = $bootLogContent | Where-Object { $_ -match "Loaded driver" } | Select-Object -Last 1
        $firstFailed = $bootLogContent | Where-Object { $_ -match "Did not load driver|Failed to load" } | Select-Object -First 1
        
        if ($lastLoaded) {
            $driverName = $lastLoaded -replace '.*Loaded driver\s+', ''
            Write-Host "    Last loaded: $driverName" -ForegroundColor Gray
        }
        if ($firstFailed) {
            Write-Host "    First failure: $firstFailed" -ForegroundColor Yellow
            $report.Stage = "Driver Initialization"
        } else {
            $report.Stage = "Boot Loader"
        }
    } else {
        Write-Host "  [NOT FOUND] Boot Log" -ForegroundColor Yellow
    }
    
    # Deep Panther log analysis
    $pantherIntel = Invoke-PantherIntelligence -WindowsDrive $WindowsDrive
    
    # Check Panther logs (In-Place Upgrade / Setup)
    $pantherPath = "${WindowsDrive}:\Windows\Panther\setupact.log"
    if (Test-Path $pantherPath) {
        Write-Host "  [FOUND] Panther Log: $pantherPath" -ForegroundColor Green
        $report.PantherLogFound = $true
        $report.LogPaths.PantherLog = $pantherPath
        
        # Extract error codes
        $errorCodes = Select-String -Path $pantherPath -Pattern "0x[0-9A-Fa-f]{8}" -AllMatches | 
                      ForEach-Object { $_.Matches } | 
                      ForEach-Object { $_.Value } | 
                      Select-Object -Unique
        
        if ($errorCodes) {
            $lastError = $errorCodes | Select-Object -Last 1
            $report.ErrorCode = $lastError
            
            Write-Host "    Detected error code: $lastError" -ForegroundColor Red
            
            # Map to Database
            if ($Global:ErrorDB.ContainsKey($lastError)) {
                $errorInfo = $Global:ErrorDB[$lastError]
                $report.ErrorDetails = $errorInfo
                $report.Recommendation = "$($errorInfo.Action): $($errorInfo.Description)"
                $report.Confidence = $errorInfo.Confidence
                $report.HumanExplanation = $errorInfo.HumanExplanation
                
                Write-Host "    Stage: $($errorInfo.Stage)" -ForegroundColor Yellow
                Write-Host "    Severity: $($errorInfo.Severity)" -ForegroundColor $(if ($errorInfo.Severity -eq "Critical") { "Red" } else { "Yellow" })
                Write-Host "    Confidence: $($errorInfo.Confidence)%" -ForegroundColor Cyan
                Write-Host "    Recommended: $($errorInfo.Action)" -ForegroundColor Green
            }
        }
        
        # Check for INACCESSIBLE_BOOT_DEVICE (text-based, not just code)
        $pantherContent = Get-Content $pantherPath -ErrorAction SilentlyContinue | Select-Object -Last 1000
        if ($pantherContent -match "INACCESSIBLE_BOOT_DEVICE|inaccessible.*boot.*device") {
            if ($Global:ErrorDB.ContainsKey("INACCESSIBLE_BOOT_DEVICE")) {
                $errorInfo = $Global:ErrorDB["INACCESSIBLE_BOOT_DEVICE"]
                $report.ErrorCode = "INACCESSIBLE_BOOT_DEVICE"
                $report.ErrorDetails = $errorInfo
                $report.Confidence = $errorInfo.Confidence
                $report.HumanExplanation = $errorInfo.HumanExplanation
                Write-Host "    [CRITICAL] INACCESSIBLE_BOOT_DEVICE detected" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  [NOT FOUND] Panther Log" -ForegroundColor Yellow
    }
    
    # Offline registry analysis
    $registryAnalysis = Invoke-OfflineRegistryAnalysis -WindowsDrive $WindowsDrive
    $report.RegistryAnalysis = $registryAnalysis
    
    # Enhanced boot stage detection
    $bootStage = Get-BootStage -WindowsDrive $WindowsDrive -Forensics $report
    if ($bootStage.Confidence -gt $report.Confidence) {
        $report.Stage = $bootStage.Stage
        $report.Confidence = $bootStage.Confidence
        $report.HumanExplanation = $bootStage.HumanExplanation
    }
    
    # Add Panther intelligence to report
    $report.PantherIntelligence = $pantherIntel
    
    return $report
}

# --- REGISTRY BLOCKER DETECTION & CLEARING (Enhanced) ---

function Test-RepairInstallBlockers {
    <#
    .SYNOPSIS
        Enhanced registry blocker detection with detailed explanations.
    #>
    param([string]$WindowsDrive = $null)
    
    Write-Host "[?] Identifying Registry Blockers..." -ForegroundColor Yellow
    Write-Host ""
    
    if (-not $WindowsDrive) {
        $WindowsDrive = $env:SystemDrive.TrimEnd(':')
    }
    
    $blockers = @()
    
    # Check for Pending Reboot
    $pendingRebootPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    if (Test-Path $pendingRebootPath) {
        $blockers += @{
            Type = "Pending Reboot"
            Path = $pendingRebootPath
            Severity = "High"
            HumanExplanation = "Windows Update has marked the system as requiring a reboot. This can block repair operations."
            Fix = "Clear-PendingReboot"
        }
        Write-Host "  [BLOCKER] Pending Reboot detected" -ForegroundColor Red
    }
    
    # Check for Portable Operating System flag
    try {
        $portable = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "PortableOperatingSystem" -ErrorAction SilentlyContinue
        if ($portable -and $portable.PortableOperatingSystem -eq 1) {
            $blockers += @{
                Type = "Portable OS Flag"
                Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PortableOperatingSystem"
                Value = 1
                Severity = "Critical"
                HumanExplanation = "Portable OS flag is set to 1. Windows Setup will refuse to run because it thinks this is a portable installation. This is often set incorrectly after system migrations or backups."
                Fix = "Set-PortableOSFlag -Value 0"
            }
            Write-Host "  [BLOCKER] Portable OS flag is set to 1 (Setup will refuse to run)" -ForegroundColor Red
        }
    } catch {
        # Registry may not be accessible in WinPE
    }
    
    # Check for PendingFileRenameOperations
    try {
        $pendingRename = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($pendingRename -and $pendingRename.PendingFileRenameOperations) {
            $blockers += @{
                Type = "Pending File Rename"
                Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
                Severity = "High"
                HumanExplanation = "Windows has pending file rename operations that will execute on next reboot. This can block repair operations until the reboot completes."
                Fix = "Clear-PendingFileRename"
            }
            Write-Host "  [BLOCKER] Pending file rename operations detected" -ForegroundColor Red
        }
    } catch {}
    
    # Check for Component Based Servicing (CBS) pending operations
    try {
        $cbsPending = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
        if ($cbsPending) {
            $blockers += @{
                Type = "CBS Reboot Pending"
                Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
                Severity = "High"
                HumanExplanation = "Component Based Servicing has pending operations that require a reboot. This can prevent repair operations from completing."
                Fix = "Clear-CBSPending"
            }
            Write-Host "  [BLOCKER] Component Based Servicing reboot pending" -ForegroundColor Red
        }
    } catch {}
    
    return @{
        Blockers = $blockers
        Count = $blockers.Count
    }
}

function Clear-AllBlockers {
    <#
    .SYNOPSIS
        Automatically clears all detected registry blockers with explanations.
    #>
    param([array]$Blockers)
    
    Write-Host "[!] Clearing Registry Blockers..." -ForegroundColor Cyan
    Write-Host ""
    
    $cleared = 0
    $failed = 0
    
    foreach ($blocker in $Blockers) {
        Write-Host "  Clearing: $($blocker.Type)..." -NoNewline -ForegroundColor Yellow
        Write-Host "`n    $($blocker.HumanExplanation)" -ForegroundColor Gray
        
        try {
            switch ($blocker.Type) {
                "Portable OS Flag" {
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "PortableOperatingSystem" -Value 0 -ErrorAction Stop
                    Write-Host "    [SUCCESS] Portable OS flag cleared" -ForegroundColor Green
                    $cleared++
                }
                "Pending File Rename" {
                    Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction Stop
                    Write-Host "    [SUCCESS] Pending file rename cleared" -ForegroundColor Green
                    $cleared++
                }
                "Pending Reboot" {
                    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -Recurse -Force -ErrorAction Stop
                    Write-Host "    [SUCCESS] Pending reboot flag cleared" -ForegroundColor Green
                    $cleared++
                }
                "CBS Reboot Pending" {
                    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -Recurse -Force -ErrorAction Stop
                    Write-Host "    [SUCCESS] CBS pending flag cleared" -ForegroundColor Green
                    $cleared++
                }
                default {
                    Write-Host "    [SKIPPED - Manual fix required]" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "    [FAILED: $_]" -ForegroundColor Red
            $failed++
        }
        Write-Host ""
    }
    
    Write-Host "  Summary: Cleared $cleared, Failed $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })
    
    return @{
        Cleared = $cleared
        Failed = $failed
    }
}

# --- OFFLINE SFC/DISM INTELLIGENCE (Unchanged but kept) ---

function Get-WindowsPartition {
    <#
    .SYNOPSIS
        Automatically detects Windows partition, especially in WinPE/WinRE.
    #>
    $currentDrive = $env:SystemDrive.TrimEnd(':')
    
    if ($currentDrive -ne "X") {
        # Not in WinPE, use current drive
        return $currentDrive
    }
    
    # In WinPE/WinRE, find Windows partition
    Write-Host "[!] Detecting Windows partition (WinPE/WinRE mode)..." -ForegroundColor Cyan
    
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemLabel } | Sort-Object DriveLetter
    foreach ($vol in $volumes) {
        if ($vol.DriveLetter -eq "X") { continue } # Skip WinPE drive
        
        $testPath = "$($vol.DriveLetter):\Windows\System32"
        if (Test-Path $testPath) {
            Write-Host "  Found Windows at: ${vol}:" -ForegroundColor Green
            return $vol.DriveLetter
        }
    }
    
    # Fallback: try common drive letters
    foreach ($letter in @("C", "D", "E", "F")) {
        $testPath = "${letter}:\Windows\System32"
        if (Test-Path $testPath) {
            Write-Host "  Found Windows at: ${letter}:" -ForegroundColor Green
            return $letter
        }
    }
    
    Write-Host "  [WARNING] Could not auto-detect Windows partition" -ForegroundColor Yellow
    return "C" # Default fallback
}

function Invoke-OfflineSFC {
    <#
    .SYNOPSIS
        Runs SFC with correct offline parameters.
    #>
    param([string]$WindowsDrive)
    
    Write-Host "[!] Running Offline SFC Scan..." -ForegroundColor Cyan
    Write-Host ""
    
    $command = "sfc /scannow /offbootdir=${WindowsDrive}:\ /offwindir=${WindowsDrive}:\Windows"
    Write-Host "  Command: $command" -ForegroundColor Gray
    Write-Host ""
    
    try {
        $result = Invoke-Expression $command 2>&1
        Write-Host $result
        return @{ Success = $true; Output = $result }
    } catch {
        Write-Host "  [ERROR] SFC failed: $_" -ForegroundColor Red
        return @{ Success = $false; Error = $_ }
    }
}

function Invoke-OfflineDISM {
    <#
    .SYNOPSIS
        Runs DISM with correct offline parameters.
    #>
    param([string]$WindowsDrive)
    
    Write-Host "[!] Running Offline DISM Repair..." -ForegroundColor Cyan
    Write-Host ""
    
    $command = "dism /image:${WindowsDrive}:\ /cleanup-image /restorehealth"
    Write-Host "  Command: $command" -ForegroundColor Gray
    Write-Host ""
    
    try {
        $result = Invoke-Expression $command 2>&1
        Write-Host $result
        return @{ Success = $true; Output = $result }
    } catch {
        Write-Host "  [ERROR] DISM failed: $_" -ForegroundColor Red
        return @{ Success = $false; Error = $_ }
    }
}

# --- LIVE-LOG MONITORING (Enhanced) ---

function Start-LogMonitor {
    <#
    .SYNOPSIS
        Enhanced log monitoring with error code alerts.
    #>
    param([string]$LogPath, [int]$TimeoutSeconds = 300)
    
    if (-not (Test-Path $LogPath)) {
        Write-Host "[ERROR] Log file not found: $LogPath" -ForegroundColor Red
        return
    }
    
    Write-Host "[!] Starting Live Log Monitor..." -ForegroundColor Cyan
    Write-Host "  Monitoring: $LogPath" -ForegroundColor Gray
    Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
    Write-Host ""
    
    $startTime = Get-Date
    $lastPosition = (Get-Item $LogPath).Length
    
    while ($true) {
        Start-Sleep -Seconds 2
        
        $currentLength = (Get-Item $LogPath).Length
        if ($currentLength -gt $lastPosition) {
            # New content added
            $stream = [System.IO.File]::OpenRead($LogPath)
            $stream.Position = $lastPosition
            $reader = New-Object System.IO.StreamReader($stream)
            $newContent = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
            
            # Check for error codes
            $errorMatches = [regex]::Matches($newContent, "0x[0-9A-Fa-f]{8}")
            foreach ($match in $errorMatches) {
                $errorCode = $match.Value
                Write-Host "[ALERT] Error code detected: $errorCode" -ForegroundColor Red
                
                if ($Global:ErrorDB.ContainsKey($errorCode)) {
                    $errorInfo = $Global:ErrorDB[$errorCode]
                    Write-Host "  Stage: $($errorInfo.Stage)" -ForegroundColor Yellow
                    Write-Host "  Explanation: $($errorInfo.HumanExplanation)" -ForegroundColor White
                    Write-Host "  Action: $($errorInfo.Action)" -ForegroundColor Green
                    Write-Host "  Confidence: $($errorInfo.Confidence)%" -ForegroundColor Cyan
                }
            }
            
            # Check for INACCESSIBLE_BOOT_DEVICE
            if ($newContent -match "INACCESSIBLE_BOOT_DEVICE|inaccessible.*boot.*device") {
                Write-Host "[CRITICAL ALERT] INACCESSIBLE_BOOT_DEVICE detected!" -ForegroundColor Red
                if ($Global:ErrorDB.ContainsKey("INACCESSIBLE_BOOT_DEVICE")) {
                    $errorInfo = $Global:ErrorDB["INACCESSIBLE_BOOT_DEVICE"]
                    Write-Host "  $($errorInfo.HumanExplanation)" -ForegroundColor White
                    Write-Host "  Likely causes:" -ForegroundColor Yellow
                    foreach ($cause in $errorInfo.LikelyCauses) {
                        Write-Host "    - $cause" -ForegroundColor Gray
                    }
                }
            }
            
            # Display new lines
            $newContent -split "`n" | ForEach-Object {
                if ($_.Trim().Length -gt 0) {
                    Write-Host "  $_" -ForegroundColor Gray
                }
            }
            
            $lastPosition = $currentLength
        }
        
        # Timeout check
        if (((Get-Date) - $startTime).TotalSeconds -gt $TimeoutSeconds) {
            Write-Host "[INFO] Monitor timeout reached" -ForegroundColor Yellow
            break
        }
    }
}

# --- HARDWARE DIAGNOSTICS (Enhanced) ---

function Test-DiskHealth {
    <#
    .SYNOPSIS
        Enhanced hardware diagnostics with actionable recommendations.
    #>
    param([string]$WindowsDrive = $null)
    
    Write-Host "[!] Running Hardware Diagnostics..." -ForegroundColor Cyan
    Write-Host ""
    
    if (-not $WindowsDrive) {
        $WindowsDrive = Get-WindowsPartition
    }
    
    $report = @{
        DiskHealthy = $true
        Issues = @()
        Recommendations = @()
        CanProceedWithSoftwareRepair = $true
    }
    
    try {
        # Get physical disk for Windows partition
        $volume = Get-Volume -DriveLetter $WindowsDrive -ErrorAction Stop
        $partition = Get-Partition -DriveLetter $WindowsDrive -ErrorAction Stop
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
        
        Write-Host "  Disk: $($disk.FriendlyName)" -ForegroundColor Gray
        Write-Host "  Model: $($disk.Model)" -ForegroundColor Gray
        Write-Host "  Size: $([math]::Round($disk.Size / 1GB, 2)) GB" -ForegroundColor Gray
        Write-Host "  Health Status: $($disk.HealthStatus)" -ForegroundColor $(if ($disk.HealthStatus -eq "Healthy") { "Green" } else { "Red" })
        
        if ($disk.HealthStatus -ne "Healthy") {
            $report.DiskHealthy = $false
            $report.CanProceedWithSoftwareRepair = $false
            $report.Issues += "Disk health status: $($disk.HealthStatus)"
            $report.Recommendations += "CRITICAL: Disk may be failing. Backup data immediately and replace disk before attempting repairs."
        }
        
        # Check for read-only status
        if ($disk.IsReadOnly) {
            $report.DiskHealthy = $false
            $report.CanProceedWithSoftwareRepair = $false
            $report.Issues += "Disk is read-only"
            $report.Recommendations += "Disk is read-only. Check disk for errors. Software repairs cannot proceed on read-only media."
        }
        
        # Check disk space
        $freeSpaceGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
        $totalSpaceGB = [math]::Round($volume.Size / 1GB, 2)
        $percentFree = [math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 2)
        
        Write-Host "  Free Space: $freeSpaceGB GB ($percentFree%)" -ForegroundColor $(if ($percentFree -lt 10) { "Red" } elseif ($percentFree -lt 20) { "Yellow" } else { "Green" })
        
        if ($percentFree -lt 10) {
            $report.Issues += "Low disk space: $percentFree% free"
            $report.Recommendations += "Free up disk space (at least 10% recommended for repairs)"
            $report.CanProceedWithSoftwareRepair = $false
        } elseif ($percentFree -lt 20) {
            $report.Issues += "Low disk space: $percentFree% free"
            $report.Recommendations += "Consider freeing up disk space before repairs"
        }
        
        # Check for SMART errors (if available)
        try {
            $smart = Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk -FriendlyName $disk.FriendlyName) -ErrorAction SilentlyContinue
            if ($smart) {
                Write-Host "  SMART Status: Available" -ForegroundColor Gray
                if ($smart.Temperature -gt 60) {
                    $report.Issues += "High disk temperature: $($smart.Temperature)°C"
                    $report.Recommendations += "Check disk cooling and ventilation"
                }
            }
        } catch {
            # SMART not available on all systems
        }
        
    } catch {
        Write-Host "  [WARNING] Could not retrieve disk information: $_" -ForegroundColor Yellow
        $report.Issues += "Could not access disk information"
    }
    
    if ($report.Issues.Count -eq 0) {
        Write-Host "  [PASS] Disk health check passed - Software repairs can proceed" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Disk health issues detected" -ForegroundColor Red
        foreach ($issue in $report.Issues) {
            Write-Host "    - $issue" -ForegroundColor Yellow
        }
        if (-not $report.CanProceedWithSoftwareRepair) {
            Write-Host "  [CRITICAL] Software repairs NOT recommended due to hardware issues" -ForegroundColor Red
        }
    }
    
    return $report
}

# --- ROOT CAUSE SUMMARY GENERATOR ---

function Get-TopBlockers {
    <#
    .SYNOPSIS
        Generates a prioritized list of top blockers with confidence scores.
    
    .DESCRIPTION
        Analyzes all detected issues and blockers, ranks them by severity and confidence,
        and returns the top 3 blockers with fix order recommendations.
    
    .PARAMETER Forensics
        Boot forensics object containing error details
    
    .PARAMETER Blockers
        Registry blockers object
    
    .PARAMETER DiskHealth
        Disk health report
    
    .PARAMETER PantherIntel
        Panther log intelligence data
    
    .EXAMPLE
        $topBlockers = Get-TopBlockers -Forensics $forensics -Blockers $blockers -DiskHealth $diskHealth -PantherIntel $pantherIntel
        $topBlockers | ForEach-Object { Write-Host "$($_.Rank). $($_.Issue) (Confidence: $($_.Confidence)%)" }
    #>
    param(
        $Forensics,
        $Blockers,
        $DiskHealth,
        $PantherIntel
    )
    
    $allBlockers = @()
    
    # 1. Primary boot error (highest priority)
    if ($Forensics -and $Forensics.ErrorCode -and $Forensics.ErrorDetails) {
        $allBlockers += @{
            Rank = 0
            Issue = $Forensics.ErrorDetails.Description
            Category = "Boot Failure"
            Confidence = $Forensics.Confidence
            Severity = $Forensics.ErrorDetails.Severity
            Stage = $Forensics.Stage
            RecommendedAction = $Forensics.ErrorDetails.RecommendedActions[0]
            Command = $Forensics.ErrorDetails.Command
            ErrorCode = $Forensics.ErrorCode
            PriorityScore = 0  # Will be calculated
        }
    }
    
    # 2. Disk health issues (critical if hardware failure)
    if ($DiskHealth -and -not $DiskHealth.DiskHealthy) {
        foreach ($issue in $DiskHealth.Issues) {
            $severity = if ($issue -match "CRITICAL|failing|read-only") { "Critical" } else { "High" }
            $confidence = if ($issue -match "SMART|temperature") { 85 } else { 75 }
            $allBlockers += @{
                Rank = 0
                Issue = $issue
                Category = "Hardware"
                Confidence = $confidence
                Severity = $severity
                Stage = "Hardware"
                RecommendedAction = ($DiskHealth.Recommendations | Where-Object { $_ -match $issue })[0]
                Command = "Check disk health and backup data"
                ErrorCode = $null
                PriorityScore = 0
            }
        }
    }
    
    # 3. Registry blockers (medium priority)
    if ($Blockers -and $Blockers.Blockers) {
        foreach ($blocker in $Blockers.Blockers) {
            $allBlockers += @{
                Rank = 0
                Issue = $blocker.Description
                Category = "Registry Blocker"
                Confidence = 80
                Severity = "Medium"
                Stage = "Setup/Upgrade"
                RecommendedAction = "Clear registry blocker: $($blocker.Key)"
                Command = "Clear-AllBlockers"
                ErrorCode = $null
                PriorityScore = 0
            }
        }
    }
    
    # 4. Panther log blockers (high priority for upgrades)
    if ($PantherIntel -and $PantherIntel.BlockType) {
        $allBlockers += @{
            Rank = 0
            Issue = "Setup blocker: $($PantherIntel.BlockType)"
            Category = "Compatibility"
            Confidence = 85
            Severity = "High"
            Stage = "Setup/Upgrade"
            RecommendedAction = $PantherIntel.FailureReason
            Command = "Resolve compatibility issue"
            ErrorCode = $PantherIntel.ErrorCode
            PriorityScore = 0
        }
    }
    
    # Calculate priority scores (lower = higher priority)
    foreach ($blocker in $allBlockers) {
        $score = 0
        
        # Severity weight (Critical = 0, High = 10, Medium = 20, Low = 30)
        switch ($blocker.Severity) {
            "Critical" { $score += 0 }
            "High" { $score += 10 }
            "Medium" { $score += 20 }
            "Low" { $score += 30 }
            default { $score += 15 }
        }
        
        # Confidence adjustment (higher confidence = lower score = higher priority)
        $score += (100 - $blocker.Confidence) / 10
        
        # Category priority (Boot Failure > Hardware > Compatibility > Registry)
        switch ($blocker.Category) {
            "Boot Failure" { $score += 0 }
            "Hardware" { $score += 5 }
            "Compatibility" { $score += 10 }
            "Registry Blocker" { $score += 15 }
            default { $score += 20 }
        }
        
        $blocker.PriorityScore = $score
    }
    
    # Sort by priority score and take top 3
    $topBlockers = $allBlockers | Sort-Object PriorityScore | Select-Object -First 3
    
    # Assign ranks
    for ($i = 0; $i -lt $topBlockers.Count; $i++) {
        $topBlockers[$i].Rank = $i + 1
    }
    
    return $topBlockers
}

# --- HUMAN-READABLE OUTPUT GENERATOR ---

function Write-HumanSummary {
    <#
    .SYNOPSIS
        Generates human-readable summary that explains issues like user is panicking.
    #>
    param($Forensics, $Blockers, $DiskHealth, $PantherIntel)
    
    Write-Host ""
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host "DIAGNOSIS SUMMARY - What's Wrong and How to Fix It" -ForegroundColor Cyan
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host ""
    
    # Human explanation
    Write-Host "WHAT'S HAPPENING:" -ForegroundColor White
    Write-Host ""
    
    if ($Forensics.HumanExplanation -and $Forensics.HumanExplanation -ne "Unable to determine the cause of boot failure.") {
        Write-Host "   $($Forensics.HumanExplanation)" -ForegroundColor White
    } else {
        Write-Host "   Your PC is not booting, but we need more information to determine the exact cause." -ForegroundColor White
    }
    
    Write-Host ""
    
    # Boot stage
    Write-Host "BOOT FAILURE STAGE:" -ForegroundColor White
    Write-Host "   Stage: $($Forensics.Stage)" -ForegroundColor $(if ($Forensics.Stage -ne "Unknown") { "Yellow" } else { "Gray" })
    Write-Host "   Confidence: $($Forensics.Confidence)%" -ForegroundColor $(if ($Forensics.Confidence -ge 90) { "Green" } elseif ($Forensics.Confidence -ge 70) { "Yellow" } else { "Gray" })
    Write-Host ""
    
    # Likely causes
    if ($Forensics.ErrorDetails -and $Forensics.ErrorDetails.LikelyCauses) {
        Write-Host "LIKELY CAUSES:" -ForegroundColor White
        foreach ($cause in $Forensics.ErrorDetails.LikelyCauses) {
            Write-Host "   • $cause" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    # Top 3 Blockers (if available)
    $topBlockers = Get-TopBlockers -Forensics $Forensics -Blockers $Blockers -DiskHealth $DiskHealth -PantherIntel $PantherIntel
    if ($topBlockers -and $topBlockers.Count -gt 0) {
        Write-Host "TOP $($topBlockers.Count) BLOCKERS (Fix in this order):" -ForegroundColor White
        Write-Host ""
        foreach ($blocker in $topBlockers) {
            $color = switch ($blocker.Severity) {
                "Critical" { "Red" }
                "High" { "Yellow" }
                default { "White" }
            }
            Write-Host "   $($blocker.Rank). $($blocker.Issue)" -ForegroundColor $color
            Write-Host "      Category: $($blocker.Category) | Confidence: $($blocker.Confidence)%" -ForegroundColor Gray
            Write-Host "      → $($blocker.RecommendedAction)" -ForegroundColor Green
            Write-Host ""
        }
    }
    
    # Recommended actions (fallback if no top blockers)
    if ((-not $topBlockers -or $topBlockers.Count -eq 0) -and $Forensics.ErrorDetails -and $Forensics.ErrorDetails.RecommendedActions) {
        Write-Host "RECOMMENDED FIXES:" -ForegroundColor White
        $actionNum = 1
        foreach ($action in $Forensics.ErrorDetails.RecommendedActions) {
            Write-Host "   $actionNum. $action" -ForegroundColor Green
            $actionNum++
        }
        Write-Host ""
    }
    
    # Panther intelligence
    if ($PantherIntel -and $PantherIntel.BlockingRule) {
        Write-Host "UPGRADE BLOCKER DETECTED:" -ForegroundColor White
        Write-Host "   $($PantherIntel.BlockingRule)" -ForegroundColor Red
        if ($PantherIntel.FailureReason) {
            Write-Host "   Reason: $($PantherIntel.FailureReason)" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    # Registry blockers
    if ($Blockers -and $Blockers.Count -gt 0) {
        Write-Host "REGISTRY BLOCKERS:" -ForegroundColor White
        foreach ($blocker in $Blockers.Blockers) {
            Write-Host "   • $($blocker.Type) - $($blocker.HumanExplanation)" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    # Hardware status
    if ($DiskHealth -and -not $DiskHealth.DiskHealthy) {
        Write-Host "HARDWARE WARNING:" -ForegroundColor White
        Write-Host "   Your storage device may be failing. Software repairs may not help." -ForegroundColor Red
        foreach ($rec in $DiskHealth.Recommendations) {
            Write-Host "   • $rec" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host ""
}

function Write-TechnicianSummary {
    <#
    .SYNOPSIS
        Generates technical summary for advanced users.
    #>
    param($Forensics, $Blockers, $DiskHealth, $PantherIntel)
    
    Write-Host ""
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host "TECHNICIAN SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Boot Stage:        $($Forensics.Stage)" -ForegroundColor White
    Write-Host "Error Code:        $($Forensics.ErrorCode)" -ForegroundColor $(if ($Forensics.ErrorCode) { "Red" } else { "Gray" })
    Write-Host "Confidence:        $($Forensics.Confidence)%" -ForegroundColor Cyan
    Write-Host "Windows Drive:     $($Forensics.WindowsDrive):" -ForegroundColor White
    Write-Host ""
    
    if ($Forensics.LogPaths) {
        Write-Host "Log Files:" -ForegroundColor White
        foreach ($key in $Forensics.LogPaths.Keys) {
            Write-Host "  $key : $($Forensics.LogPaths[$key])" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    if ($PantherIntel -and $PantherIntel.BlockType) {
        Write-Host "Panther Analysis:" -ForegroundColor White
        Write-Host "  Block Type:     $($PantherIntel.BlockType)" -ForegroundColor Yellow
        Write-Host "  Failure Reason: $($PantherIntel.FailureReason)" -ForegroundColor Yellow
        if ($PantherIntel.DriverIssues.Count -gt 0) {
            Write-Host "  Driver Issues:  $($PantherIntel.DriverIssues.Count)" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    if ($Forensics.RegistryAnalysis) {
        $reg = $Forensics.RegistryAnalysis
        Write-Host "Registry Analysis:" -ForegroundColor White
        if ($reg.MissingDrivers.Count -gt 0) {
            Write-Host "  Missing Drivers: $($reg.MissingDrivers -join ', ')" -ForegroundColor Red
        }
        if ($reg.DisabledDrivers.Count -gt 0) {
            Write-Host "  Disabled Drivers: $($reg.DisabledDrivers -join ', ')" -ForegroundColor Yellow
        }
        if ($reg.CorruptControlSet) {
            Write-Host "  ControlSet: CORRUPT" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    if ($Blockers -and $Blockers.Count -gt 0) {
        Write-Host "Registry Blockers: $($Blockers.Count)" -ForegroundColor White
        foreach ($blocker in $Blockers.Blockers) {
            Write-Host "  - $($blocker.Type) ($($blocker.Severity))" -ForegroundColor Yellow
            Write-Host "    Path: $($blocker.Path)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host ""
}

# --- MAIN EXECUTION ---

Write-Host ("=" * 90) -ForegroundColor Cyan
Write-Host 'MIRACLEBOOT PRO: FORENSIC BOOT ANALYZER & AUTO-REPAIR' -ForegroundColor Cyan
Write-Host "Diagnostic Engine - Authoritative Diagnosis, Not Guessing" -ForegroundColor Gray
Write-Host ("=" * 90) -ForegroundColor Cyan
Write-Host ""

# Detect Windows partition
$windowsDrive = Get-WindowsPartition
if ($TargetDrive) {
    $windowsDrive = $TargetDrive.TrimEnd(':')
}

Write-Host "Windows Drive: ${windowsDrive}:" -ForegroundColor Cyan
Write-Host ""

# Run analysis based on mode
$forensics = $null
$blockers = $null
$diskHealth = $null
$pantherIntel = $null

if ($Mode -eq 'Analyze' -or $Mode -eq 'Full') {
    $forensics = Invoke-BootForensics -WindowsDrive $windowsDrive
    $blockers = Test-RepairInstallBlockers -WindowsDrive $windowsDrive
    $diskHealth = Test-DiskHealth -TargetDrive $windowsDrive
    $pantherIntel = $forensics.PantherIntelligence
}

# Display human-readable summary
if ($forensics) {
    Write-HumanSummary -Forensics $forensics -Blockers $blockers -DiskHealth $diskHealth -PantherIntel $pantherIntel
    Write-TechnicianSummary -Forensics $forensics -Blockers $blockers -DiskHealth $diskHealth -PantherIntel $pantherIntel
}

# Clear blockers if in repair mode
if (($Mode -eq 'Repair' -or $Mode -eq 'Full') -and $blockers -and $blockers.Count -gt 0) {
    Write-Host "[!] Registry Blocker Clearing..." -ForegroundColor Cyan
    $clearResult = Clear-AllBlockers -Blockers $blockers.Blockers
}

# Hardware warning
if ($diskHealth -and -not $diskHealth.CanProceedWithSoftwareRepair) {
    Write-Host ""
    Write-Host ("=" * 90) -ForegroundColor Red
    Write-Host "CRITICAL: Hardware issues detected. Software repairs are NOT recommended." -ForegroundColor Red
    Write-Host ("=" * 90) -ForegroundColor Red
    Write-Host ""
}

# Auto-repair suggestions
if ($forensics -and $forensics.ErrorDetails) {
    Write-Host ""
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host "[AUTO-REPAIR SUGGESTIONS]" -ForegroundColor White
    Write-Host ("=" * 90) -ForegroundColor Cyan
    
    $command = $forensics.ErrorDetails.Command
    $command = $command -replace '\{DRIVE\}', $windowsDrive
    
    Write-Host "Recommended Command:" -ForegroundColor Yellow
    Write-Host "  $command" -ForegroundColor White
    Write-Host ""
    Write-Host "Confidence: $($forensics.ErrorDetails.Confidence)%" -ForegroundColor Cyan
    Write-Host ""
    
    if ($Mode -eq 'Repair' -or $Mode -eq 'Full') {
        Write-Host "Would you like to execute this command? (Y/N): " -NoNewline -ForegroundColor Cyan
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            Write-Host ""
            Invoke-Expression $command
        }
    }
}

# Live monitoring mode
if ($MonitorLogs -or $Mode -eq 'Monitor') {
    $pantherLog = "${windowsDrive}:\Windows\Panther\setupact.log"
    if (Test-Path $pantherLog) {
        Start-LogMonitor -LogPath $pantherLog
    } else {
        Write-Host "[ERROR] Panther log not found for monitoring" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host ("=" * 90) -ForegroundColor Cyan
Write-Host "Analysis Complete" -ForegroundColor Green
Write-Host ("=" * 90) -ForegroundColor Cyan
