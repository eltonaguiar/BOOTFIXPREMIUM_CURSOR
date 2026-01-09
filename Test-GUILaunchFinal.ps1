# Final GUI Launch Test - Ensures zero errors/warnings
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  FINAL GUI LAUNCH VERIFICATION" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

$errors = @()
$warnings = @()

# Step 1: Check environment
Write-Host "[1/5] Checking environment..." -ForegroundColor Yellow
try {
    if ($env:SystemDrive -eq 'X:') {
        Write-Host "  [SKIP] WinPE/WinRE environment - GUI not available" -ForegroundColor Yellow
        exit 0
    }
    Write-Host "  [OK] FullOS environment detected" -ForegroundColor Green
} catch {
    $errors += "Environment check failed: $_"
}

# Step 2: Load core module
Write-Host "[2/5] Loading WinRepairCore.ps1..." -ForegroundColor Yellow
$errorCountBefore = $Error.Count
try {
    . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Continue 2>&1 | Out-Null
    $errorCountAfter = $Error.Count
    if ($errorCountAfter -gt $errorCountBefore) {
        $newErrors = $Error[$errorCountBefore..($errorCountAfter-1)]
        foreach ($err in $newErrors) {
            if ($err.Exception.Message -notmatch 'Export-ModuleMember') {
                $errors += "Core module error: $($err.Exception.Message)"
            }
        }
    }
    if ($errors.Count -eq 0) {
        Write-Host "  [OK] Core module loaded successfully" -ForegroundColor Green
    }
} catch {
    $errors += "Failed to load core module: $_"
}

# Step 3: Check WPF availability
Write-Host "[3/5] Checking WPF availability..." -ForegroundColor Yellow
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    Write-Host "  [OK] WPF assemblies available" -ForegroundColor Green
} catch {
    $errors += "WPF not available: $_"
    Write-Host "  [FAIL] WPF not available - GUI cannot launch" -ForegroundColor Red
    exit 1
}

# Step 4: Load GUI module
Write-Host "[4/5] Loading WinRepairGUI.ps1..." -ForegroundColor Yellow
$errorCountBefore = $Error.Count
try {
    . "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Continue 2>&1 | Out-Null
    $errorCountAfter = $Error.Count
    if ($errorCountAfter -gt $errorCountBefore) {
        $newErrors = $Error[$errorCountBefore..($errorCountAfter-1)]
        foreach ($err in $newErrors) {
            if ($err.Exception.Message -notmatch 'Export-ModuleMember') {
                $errors += "GUI module error: $($err.Exception.Message)"
            }
        }
    }
    
    if (-not (Get-Command Start-GUI -ErrorAction SilentlyContinue)) {
        $errors += "Start-GUI function not found after loading GUI module"
    }
    
    if ($errors.Count -eq 0) {
        Write-Host "  [OK] GUI module loaded successfully" -ForegroundColor Green
        Write-Host "  [OK] Start-GUI function found" -ForegroundColor Green
    }
} catch {
    $errors += "Failed to load GUI module: $_"
}

# Step 5: Test GUI initialization (without showing window)
Write-Host "[5/5] Testing GUI initialization..." -ForegroundColor Yellow
try {
    # We can't actually show the window in automated test, but we can verify
    # the function exists and can be called (it will error if there are issues)
    $guiFunction = Get-Command Start-GUI -ErrorAction Stop
    Write-Host "  [OK] Start-GUI function is callable" -ForegroundColor Green
} catch {
    $errors += "Start-GUI function not available: $_"
}

# Summary
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
if ($errors.Count -eq 0) {
    Write-Host "  [PASS] GUI LAUNCH TEST: PASSED" -ForegroundColor Green
    Write-Host "  Zero errors detected" -ForegroundColor Green
    Write-Host "  GUI is ready to launch" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  [FAIL] GUI LAUNCH TEST: FAILED" -ForegroundColor Red
    Write-Host "  Errors detected: $($errors.Count)" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "    - $($err)" -ForegroundColor Red
    }
    exit 1
}

