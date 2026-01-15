# Diagnostic script to check actual disk health and identify false positives

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DISK HEALTH DIAGNOSTICS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load core module
try {
    . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Stop
    Write-Host "[OK] Core module loaded" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Failed to load core: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get system drive
$drive = $env:SystemDrive.TrimEnd(':')
Write-Host "Target Drive: $drive`:" -ForegroundColor Yellow
Write-Host ""

# Run Test-DiskHealth
Write-Host "[TEST] Running Test-DiskHealth..." -ForegroundColor Yellow
try {
    $diskHealth = Test-DiskHealth -TargetDrive $drive
    Write-Host "[OK] Test-DiskHealth completed" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Test-DiskHealth failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TEST-DISKHEALTH RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Display all properties returned
Write-Host "Properties returned by Test-DiskHealth:" -ForegroundColor Yellow
$diskHealth.PSObject.Properties | ForEach-Object {
    $value = $_.Value
    if ($value -is [System.Array]) {
        $value = "$($value.Count) item(s)"
    } elseif ($value -is [System.Collections.Hashtable]) {
        $value = "Hashtable with $($value.Keys.Count) keys"
    }
    Write-Host "  $($_.Name): $value" -ForegroundColor Gray
}

Write-Host ""

# Check what the GUI expects vs what we get
Write-Host "GUI EXPECTS vs ACTUAL:" -ForegroundColor Yellow
Write-Host "  DiskHealthy: $(if ($diskHealth.DiskHealthy) { 'EXISTS' } else { 'MISSING (FALSE POSITIVE!)' })" -ForegroundColor $(if ($diskHealth.DiskHealthy) { "Green" } else { "Red" })
Write-Host "  CanProceedWithSoftwareRepair: $(if ($diskHealth.CanProceedWithSoftwareRepair) { 'EXISTS' } else { 'MISSING (FALSE POSITIVE!)' })" -ForegroundColor $(if ($diskHealth.CanProceedWithSoftwareRepair) { "Green" } else { "Red" })
Write-Host "  Issues: $(if ($diskHealth.Issues) { 'EXISTS' } else { 'MISSING' })" -ForegroundColor $(if ($diskHealth.Issues) { "Green" } else { "Yellow" })
Write-Host ""
Write-Host "ACTUAL PROPERTIES:" -ForegroundColor Yellow
Write-Host "  FileSystemHealthy: $($diskHealth.FileSystemHealthy)" -ForegroundColor $(if ($diskHealth.FileSystemHealthy) { "Green" } else { "Red" })
Write-Host "  HasBadSectors: $($diskHealth.HasBadSectors)" -ForegroundColor $(if ($diskHealth.HasBadSectors) { "Red" } else { "Green" })
Write-Host "  NeedsRepair: $($diskHealth.NeedsRepair)" -ForegroundColor $(if ($diskHealth.NeedsRepair) { "Yellow" } else { "Green" })
Write-Host "  FileSystem: $($diskHealth.FileSystem)" -ForegroundColor Gray
Write-Host "  BitLockerEncrypted: $($diskHealth.BitLockerEncrypted)" -ForegroundColor Gray

Write-Host ""

# Get detailed disk information
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DETAILED DISK INFORMATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    $volume = Get-Volume -DriveLetter $drive -ErrorAction Stop
    Write-Host "Volume Information:" -ForegroundColor Yellow
    Write-Host "  Drive Letter: $($volume.DriveLetter):" -ForegroundColor Gray
    Write-Host "  FileSystem: $($volume.FileSystemType)" -ForegroundColor Gray
    Write-Host "  HealthStatus: $($volume.HealthStatus)" -ForegroundColor $(if ($volume.HealthStatus -eq 'Healthy') { "Green" } else { "Red" })
    Write-Host "  Size: $([math]::Round($volume.Size / 1GB, 2)) GB" -ForegroundColor Gray
    Write-Host "  Free Space: $([math]::Round($volume.SizeRemaining / 1GB, 2)) GB ($([math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 2))%)" -ForegroundColor Gray
    Write-Host ""
    
    $partition = Get-Partition -DriveLetter $drive -ErrorAction Stop
    if ($partition) {
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
        Write-Host "Physical Disk Information:" -ForegroundColor Yellow
        Write-Host "  Disk Number: $($disk.Number)" -ForegroundColor Gray
        Write-Host "  Friendly Name: $($disk.FriendlyName)" -ForegroundColor Gray
        Write-Host "  Model: $($disk.Model)" -ForegroundColor Gray
        Write-Host "  Size: $([math]::Round($disk.Size / 1GB, 2)) GB" -ForegroundColor Gray
        Write-Host "  HealthStatus: $($disk.HealthStatus)" -ForegroundColor $(if ($disk.HealthStatus -eq 'Healthy') { "Green" } else { "Red" })
        Write-Host "  OperationalStatus: $($disk.OperationalStatus)" -ForegroundColor Gray
        Write-Host "  IsReadOnly: $($disk.IsReadOnly)" -ForegroundColor $(if ($disk.IsReadOnly) { "Red" } else { "Green" })
        Write-Host "  PartitionStyle: $($disk.PartitionStyle)" -ForegroundColor Gray
        Write-Host ""
        
        # Check for S.M.A.R.T. attributes if available
        try {
            $smart = Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk | Where-Object { $_.DeviceID -eq $disk.Number } | Select-Object -First 1) -ErrorAction SilentlyContinue
            if ($smart) {
                Write-Host "S.M.A.R.T. Information:" -ForegroundColor Yellow
                Write-Host "  Temperature: $($smart.Temperature)°C" -ForegroundColor Gray
                Write-Host "  Wear: $($smart.Wear)" -ForegroundColor Gray
                Write-Host "  ReadErrorsTotal: $($smart.ReadErrorsTotal)" -ForegroundColor $(if ($smart.ReadErrorsTotal -gt 0) { "Red" } else { "Green" })
                Write-Host "  WriteErrorsTotal: $($smart.WriteErrorsTotal)" -ForegroundColor $(if ($smart.WriteErrorsTotal -gt 0) { "Red" } else { "Green" })
                Write-Host ""
            }
        } catch {
            Write-Host "S.M.A.R.T. information not available" -ForegroundColor Gray
            Write-Host ""
        }
    }
} catch {
    Write-Host "[WARNING] Could not get detailed disk information: $_" -ForegroundColor Yellow
    Write-Host ""
}

# Check dirty bit
Write-Host "File System Dirty Bit:" -ForegroundColor Yellow
try {
    $dirtyBit = fsutil dirty query "$drive`:" 2>&1
    if ($dirtyBit -match "is dirty") {
        Write-Host "  Status: DIRTY (file system corruption detected)" -ForegroundColor Red
        Write-Host "  This is a SOFTWARE issue, not hardware failure" -ForegroundColor Yellow
    } else {
        Write-Host "  Status: Clean" -ForegroundColor Green
    }
} catch {
    Write-Host "  Status: Could not check (may require admin)" -ForegroundColor Yellow
}

Write-Host ""

# Final assessment
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ASSESSMENT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$isActuallyHealthy = $true
$isHardwareFailure = $false
$issues = @()

if (-not $diskHealth.FileSystemHealthy) {
    $isActuallyHealthy = $false
    if ($diskHealth.HasBadSectors) {
        $isHardwareFailure = $true
        $issues += "Bad sectors detected (HARDWARE FAILURE)"
    } else {
        $issues += "File system not healthy (may be software corruption)"
    }
}

if ($diskHealth.NeedsRepair) {
    $isActuallyHealthy = $false
    $issues += "File system needs repair (software issue, can be fixed)"
}

if ($volume -and $volume.HealthStatus -ne 'Healthy') {
    $isActuallyHealthy = $false
    $issues += "Volume health status: $($volume.HealthStatus)"
}

if ($disk -and $disk.HealthStatus -ne 'Healthy') {
    $isHardwareFailure = $true
    $issues += "Physical disk health status: $($disk.HealthStatus) (HARDWARE FAILURE)"
}

if ($disk -and $disk.IsReadOnly) {
    $isHardwareFailure = $true
    $issues += "Disk is read-only (HARDWARE FAILURE)"
}

Write-Host "Overall Assessment:" -ForegroundColor Yellow
if ($isActuallyHealthy) {
    Write-Host "  Status: HEALTHY" -ForegroundColor Green
    Write-Host "  This is a FALSE POSITIVE in the GUI!" -ForegroundColor Red
    Write-Host "  The GUI is checking for properties that don't exist." -ForegroundColor Red
} elseif ($isHardwareFailure) {
    Write-Host "  Status: HARDWARE FAILURE DETECTED" -ForegroundColor Red
    Write-Host "  This appears to be a REAL hardware issue." -ForegroundColor Red
    Write-Host "  Issues:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "    - $issue" -ForegroundColor Red
    }
} else {
    Write-Host "  Status: SOFTWARE ISSUES (can be repaired)" -ForegroundColor Yellow
    Write-Host "  This is likely a FALSE POSITIVE for hardware failure." -ForegroundColor Yellow
    Write-Host "  Issues:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "    - $issue" -ForegroundColor Yellow
    }
}

Write-Host ""
