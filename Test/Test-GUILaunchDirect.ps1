# Test GUI Launch - Direct execution (not in background job)
# WPF requires STA mode which background jobs don't support

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  GUI LAUNCH VERIFICATION TEST (Direct Execution)" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# Clear previous log
$logPath = Join-Path $ScriptDir ".cursor\debug.log"
if (Test-Path $logPath) {
    Remove-Item $logPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Step 1: Loading core modules..." -ForegroundColor Yellow
try {
    . (Join-Path $ScriptDir "Helper\WinRepairCore.ps1") 2>&1 | Where-Object { $_ -notmatch 'Export-ModuleMember' } | Out-Null
    Write-Host "  [OK] WinRepairCore.ps1 loaded" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Error loading WinRepairCore.ps1: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 2: Loading GUI module..." -ForegroundColor Yellow
try {
    . (Join-Path $ScriptDir "Helper\WinRepairGUI.ps1") 2>&1 | Out-Null
    Write-Host "  [OK] WinRepairGUI.ps1 loaded" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Error loading WinRepairGUI.ps1: $_" -ForegroundColor Red
    Write-Host "  Error details: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Step 3: Verifying Start-GUI function exists..." -ForegroundColor Yellow
if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
    Write-Host "  [OK] Start-GUI function found" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Start-GUI function not found" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 4: Testing WPF availability..." -ForegroundColor Yellow
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Write-Host "  [OK] WPF assemblies available" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] WPF not available: $_" -ForegroundColor Yellow
    Write-Host "  GUI will not be able to launch in this environment" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Step 5: Launching GUI..." -ForegroundColor Yellow
Write-Host "  Note: GUI window should appear. This will block until you close the window." -ForegroundColor Gray
Write-Host ""

try {
    Start-GUI
    Write-Host ""
    Write-Host "  [OK] GUI closed successfully" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Error launching GUI: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Yellow
    if ($_.Exception.InnerException) {
        Write-Host "  Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor Yellow
    }
    exit 1
}

Write-Host ""
Write-Host "Step 6: Checking debug logs..." -ForegroundColor Yellow
if (Test-Path $logPath) {
    $logContent = Get-Content $logPath -ErrorAction SilentlyContinue
    if ($logContent) {
        Write-Host "  [OK] Debug log file found with $($logContent.Count) lines" -ForegroundColor Green
        $errorLogs = $logContent | Where-Object { $_ -match '"message".*"Error"' } | Select-Object -First 3
        if ($errorLogs) {
            Write-Host "  [WARN] Found error entries in log" -ForegroundColor Yellow
        } else {
            Write-Host "  [OK] No error entries found in log" -ForegroundColor Green
        }
    } else {
        Write-Host "  [INFO] Debug log file is empty" -ForegroundColor Gray
    }
} else {
    Write-Host "  [INFO] No debug log file found" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  TEST COMPLETE" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "If the GUI window appeared and you were able to interact with it," -ForegroundColor Green
Write-Host "the test was successful!" -ForegroundColor Green


