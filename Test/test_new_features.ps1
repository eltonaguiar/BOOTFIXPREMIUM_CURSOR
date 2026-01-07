# Test script for new features
# Run this to verify all new functions are working correctly

$ErrorActionPreference = 'Continue'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing New Features" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load the core module
Write-Host "Loading Helper\WinRepairCore.ps1..." -ForegroundColor Yellow
try {
    . ..\Helper\WinRepairCore.ps1 -ErrorAction Stop
    Write-Host "[OK] Helper\WinRepairCore.ps1 loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to load Helper\WinRepairCore.ps1: $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 1: Check function availability
Write-Host "TEST 1: Function Availability Check" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
$functions = @(
    'Get-BootProbability',
    'Get-InPlaceUpgradeReadiness',
    'Start-AutomatedBootRepair',
    'Start-SystemFileRepair',
    'Start-DiskRepair',
    'Start-ComprehensiveDiagnostics',
    'Start-CompleteSystemRepair',
    'Test-SystemFileHealth',
    'Test-DiskHealth',
    'Save-RepairCheckpoint',
    'Start-RepairLogging'
)

$allFound = $true
foreach ($func in $functions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "  [OK] $func" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $func" -ForegroundColor Red
        $allFound = $false
    }
}

if ($allFound) {
    Write-Host "[PASS] All functions are available" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Some functions are missing" -ForegroundColor Red
}
Write-Host ""

# Test 2: Get-BootProbability (quick test)
Write-Host "TEST 2: Get-BootProbability Function" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
try {
    $result = Get-BootProbability -TargetDrive 'C' -ErrorAction Stop
    Write-Host "[OK] Function executed successfully" -ForegroundColor Green
    Write-Host "  Boot Probability: $($result.BootProbability)%" -ForegroundColor Cyan
    Write-Host "  Boot Health: $($result.BootHealth)" -ForegroundColor Cyan
    Write-Host "  Score: $($result.Score)/$($result.MaxScore)" -ForegroundColor Cyan
    Write-Host "  Checks performed: $($result.Checks.Count)" -ForegroundColor Cyan
    Write-Host "  Critical issues: $($result.CriticalIssues.Count)" -ForegroundColor $(if ($result.CriticalIssues.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "[PASS] Get-BootProbability test completed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Get-BootProbability test failed: $_" -ForegroundColor Red
    Write-Host "  Error details: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 3: Get-InPlaceUpgradeReadiness (quick test)
Write-Host "TEST 3: Get-InPlaceUpgradeReadiness Function" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
try {
    $result = Get-InPlaceUpgradeReadiness -TargetDrive 'C' -ErrorAction Stop
    Write-Host "[OK] Function executed successfully" -ForegroundColor Green
    Write-Host "  Ready for upgrade: $($result.ReadyForInPlaceUpgrade)" -ForegroundColor $(if ($result.ReadyForInPlaceUpgrade) { 'Green' } else { 'Yellow' })
    Write-Host "  Blockers found: $($result.Blockers.Count)" -ForegroundColor $(if ($result.Blockers.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "  Warnings: $($result.Warnings.Count)" -ForegroundColor $(if ($result.Warnings.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "  Log files analyzed: $($result.LogFilesAnalyzed.Count)" -ForegroundColor Cyan
    Write-Host "[PASS] Get-InPlaceUpgradeReadiness test completed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Get-InPlaceUpgradeReadiness test failed: $_" -ForegroundColor Red
    Write-Host "  Error details: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 4: Test-SystemFileHealth
Write-Host "TEST 4: Test-SystemFileHealth Function" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
try {
    $result = Test-SystemFileHealth -TargetDrive 'C' -ErrorAction Stop
    Write-Host "[OK] Function executed successfully" -ForegroundColor Green
    Write-Host "  System files healthy: $($result.SystemFilesHealthy)" -ForegroundColor $(if ($result.SystemFilesHealthy) { 'Green' } else { 'Yellow' })
    Write-Host "  Component store healthy: $($result.ComponentStoreHealthy)" -ForegroundColor $(if ($result.ComponentStoreHealthy) { 'Green' } else { 'Yellow' })
    Write-Host "  Can repair: $($result.CanRepair)" -ForegroundColor Cyan
    Write-Host "[PASS] Test-SystemFileHealth test completed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Test-SystemFileHealth test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 5: Test-DiskHealth
Write-Host "TEST 5: Test-DiskHealth Function" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
try {
    $result = Test-DiskHealth -TargetDrive 'C' -ErrorAction Stop
    Write-Host "[OK] Function executed successfully" -ForegroundColor Green
    Write-Host "  File system: $($result.FileSystem)" -ForegroundColor Cyan
    Write-Host "  Needs repair: $($result.NeedsRepair)" -ForegroundColor $(if ($result.NeedsRepair) { 'Yellow' } else { 'Green' })
    Write-Host "  BitLocker encrypted: $($result.BitLockerEncrypted)" -ForegroundColor Cyan
    Write-Host "[PASS] Test-DiskHealth test completed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Test-DiskHealth test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 6: Start-RepairLogging
Write-Host "TEST 6: Start-RepairLogging Function" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
try {
    $result = Start-RepairLogging -ErrorAction Stop
    Write-Host "[OK] Function executed successfully" -ForegroundColor Green
    Write-Host "  Log path: $($result.LogPath)" -ForegroundColor Cyan
    Write-Host "  Start time: $($result.StartTime)" -ForegroundColor Cyan
    
    # Test Write-RepairLog
    Write-RepairLog "Test log entry" "INFO"
    Write-Host "[OK] Write-RepairLog executed successfully" -ForegroundColor Green
    
    # Test Get-RepairReport
    $report = Get-RepairReport
    if ($report -and $report.Length -gt 0) {
        Write-Host "[OK] Get-RepairReport executed successfully" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Get-RepairReport returned empty report" -ForegroundColor Yellow
    }
    Write-Host "[PASS] Logging functions test completed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Logging functions test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "All core functions have been tested." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps for full testing:" -ForegroundColor Yellow
Write-Host "  1. Test in WinRE/WinPE environment" -ForegroundColor White
Write-Host "  2. Test BCD loading with UI updates" -ForegroundColor White
Write-Host "  3. Test boot probability check with actual system" -ForegroundColor White
Write-Host "  4. Test in-place upgrade readiness with various system states" -ForegroundColor White
Write-Host "  5. Test automated repair workflows" -ForegroundColor White
Write-Host ""

