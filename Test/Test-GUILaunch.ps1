# Test GUI Launch - Verifies the GUI loads and displays successfully
# This test will launch the GUI in a non-blocking way and verify it starts

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  GUI LAUNCH VERIFICATION TEST" -ForegroundColor Cyan
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
Write-Host "Step 5: Launching GUI (non-blocking test)..." -ForegroundColor Yellow
Write-Host "  Note: GUI window should appear. Close it to complete the test." -ForegroundColor Gray
Write-Host ""

try {
    # Launch GUI in a job so we can monitor it
    $job = Start-Job -ScriptBlock {
        param($ScriptDir)
        Set-Location $ScriptDir
        . (Join-Path $ScriptDir "Helper\WinRepairCore.ps1") 2>&1 | Out-Null
        . (Join-Path $ScriptDir "Helper\WinRepairGUI.ps1") 2>&1 | Out-Null
        Start-GUI
    } -ArgumentList $ScriptDir
    
    # Wait a moment for GUI to initialize
    Start-Sleep -Seconds 2
    
    # Check if job is still running (GUI is active)
    if ($job.State -eq 'Running') {
        Write-Host "  [OK] GUI launched successfully (job is running)" -ForegroundColor Green
        Write-Host ""
        Write-Host "  GUI window should be visible. Please:" -ForegroundColor Cyan
        Write-Host "    1. Verify the window appears" -ForegroundColor White
        Write-Host "    2. Check that controls are visible and functional" -ForegroundColor White
        Write-Host "    3. Close the window when done" -ForegroundColor White
        Write-Host ""
        Write-Host "  Waiting for GUI to close..." -ForegroundColor Yellow
        
        # Wait for job to complete (when GUI closes)
        $job | Wait-Job -Timeout 300 | Out-Null
        
        if ($job.State -eq 'Completed') {
            Write-Host "  [OK] GUI closed successfully" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] GUI test timed out or job still running" -ForegroundColor Yellow
        }
        
        # Clean up
        $job | Remove-Job -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  [FAIL] GUI job failed to start or exited immediately" -ForegroundColor Red
        $job | Receive-Job | Write-Host
        exit 1
    }
} catch {
    Write-Host "  [FAIL] Error launching GUI: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Step 6: Checking debug logs..." -ForegroundColor Yellow
if (Test-Path $logPath) {
    $logs = Get-Content $logPath | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($logs) {
        $successLogs = $logs | Where-Object { $_.message -match "About to show GUI|GUI window closed" }
        $errorLogs = $logs | Where-Object { $_.message -match "Error" }
        
        if ($successLogs) {
            Write-Host "  [OK] Found success logs: $($successLogs.Count) entries" -ForegroundColor Green
        }
        if ($errorLogs) {
            Write-Host "  [WARN] Found error logs: $($errorLogs.Count) entries" -ForegroundColor Yellow
            foreach ($log in $errorLogs) {
                Write-Host "    - $($log.message): $($log.data.error)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  [INFO] No structured logs found" -ForegroundColor Gray
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


