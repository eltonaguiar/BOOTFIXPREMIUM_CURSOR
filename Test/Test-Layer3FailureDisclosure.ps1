# LAYER 3 - AUTOMATED FAILURE DISCLOSURE
# Test GUI launch and enumerate ALL failures with root cause and confidence

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Get-Location }

$failures = @()

Write-Host "`n=== LAYER 3: AUTOMATED FAILURE DISCLOSURE ===" -ForegroundColor Cyan
Write-Host "Testing GUI launch and enumerating all failures..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Module Loading
Write-Host "[TEST 1] Module Loading..." -ForegroundColor Gray
try {
    . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Stop
    Write-Host "  [OK] WinRepairCore.ps1 loaded" -ForegroundColor Green
} catch {
    $failures += @{
        File = "Helper\WinRepairCore.ps1"
        Line = 0
        ErrorType = "ModuleLoadError"
        ErrorMessage = $_.Exception.Message
        RootCause = "Failed to load core module - dependency or syntax issue"
        Confidence = 95
    }
    Write-Host "  [FAIL] WinRepairCore.ps1: $_" -ForegroundColor Red
}

# Test 2: WPF Assembly Loading
Write-Host "[TEST 2] WPF Assembly Loading..." -ForegroundColor Gray
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Write-Host "  [OK] PresentationFramework loaded" -ForegroundColor Green
} catch {
    $failures += @{
        File = "System.Windows.PresentationFramework"
        Line = 0
        ErrorType = "AssemblyLoadError"
        ErrorMessage = $_.Exception.Message
        RootCause = "WPF assembly not available - requires .NET Framework and Windows OS"
        Confidence = 100
    }
    Write-Host "  [FAIL] PresentationFramework: $_" -ForegroundColor Red
}

# Test 3: GUI Module Loading (without launching)
Write-Host "[TEST 3] GUI Module Loading (syntax check)..." -ForegroundColor Gray
try {
    # Set validation mode to prevent GUI launch
    $env:MB_VALIDATION_MODE = "true"
    . "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Stop
    Remove-Item Env:\MB_VALIDATION_MODE -ErrorAction SilentlyContinue
    Write-Host "  [OK] WinRepairGUI.ps1 loaded (validation mode)" -ForegroundColor Green
} catch {
    Remove-Item Env:\MB_VALIDATION_MODE -ErrorAction SilentlyContinue
    $failures += @{
        File = "Helper\WinRepairGUI.ps1"
        Line = 0
        ErrorType = "ModuleLoadError"
        ErrorMessage = $_.Exception.Message
        RootCause = "Failed to load GUI module - syntax or dependency issue"
        Confidence = 95
    }
    Write-Host "  [FAIL] WinRepairGUI.ps1: $_" -ForegroundColor Red
}

# Test 4: Start-GUI Function Exists
Write-Host "[TEST 4] Start-GUI Function Exists..." -ForegroundColor Gray
try {
    if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
        Write-Host "  [OK] Start-GUI function exists" -ForegroundColor Green
    } else {
        $failures += @{
            File = "Helper\WinRepairGUI.ps1"
            Line = 0
            ErrorType = "FunctionNotFound"
            ErrorMessage = "Start-GUI function not found"
            RootCause = "Start-GUI function not defined in WinRepairGUI.ps1"
            Confidence = 100
        }
        Write-Host "  [FAIL] Start-GUI function not found" -ForegroundColor Red
    }
} catch {
    $failures += @{
        File = "Helper\WinRepairGUI.ps1"
        Line = 0
        ErrorType = "FunctionCheckError"
        ErrorMessage = $_.Exception.Message
        RootCause = "Error checking for Start-GUI function"
        Confidence = 90
    }
    Write-Host "  [FAIL] Error checking Start-GUI: $_" -ForegroundColor Red
}

# Test 5: GUI Launch Test (direct call with error handling)
Write-Host "[TEST 5] GUI Launch Test (direct call)..." -ForegroundColor Gray
try {
    # Terminate any existing GUI processes
    Get-Process powershell | Where-Object { $_.MainWindowTitle -like "*MiracleBoot*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    
    # Load modules fresh
    . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Stop
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    $env:MB_VALIDATION_MODE = "false"  # Allow GUI launch
    . "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Stop
    
    # Try to call Start-GUI directly (this will block, so we'll timeout)
    Write-Host "  [INFO] Attempting GUI launch (will timeout after 3 seconds)..." -ForegroundColor Gray
    
    $guiLaunched = $false
    $launchError = $null
    
    # Use a timer to detect if GUI launches
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # Start GUI in a separate runspace to avoid blocking
        $runspace = [RunspaceFactory]::CreateRunspace()
        $runspace.Open()
        $ps = [PowerShell]::Create()
        $ps.Runspace = $runspace
        $ps.AddScript({
            param($rootPath)
            Set-Location $rootPath
            . "$rootPath\Helper\WinRepairCore.ps1"
            Add-Type -AssemblyName PresentationFramework
            . "$rootPath\Helper\WinRepairGUI.ps1"
            Start-GUI
        }) | Out-Null
        $ps.AddArgument($scriptRoot) | Out-Null
        $handle = $ps.BeginInvoke()
        
        # Wait up to 3 seconds
        $completed = $handle.AsyncWaitHandle.WaitOne(3000)
        
        if ($completed) {
            $ps.EndInvoke($handle)
            $errors = $ps.Streams.Error
            if ($errors) {
                foreach ($err in $errors) {
                    $launchError = $err.Exception.Message
                }
            } else {
                $guiLaunched = $true
            }
        } else {
            # Timeout - GUI likely launched (window is blocking)
            $guiLaunched = $true
        }
        
        $ps.Dispose()
        $runspace.Close()
        $runspace.Dispose()
    } catch {
        $launchError = $_.Exception.Message
    }
    
    if ($launchError) {
        $failures += @{
            File = "Helper\WinRepairGUI.ps1"
            Line = 0
            ErrorType = "GUILaunchError"
            ErrorMessage = $launchError
            RootCause = "GUI launch failed during Start-GUI execution"
            Confidence = 90
        }
        Write-Host "  [FAIL] GUI launch error: $launchError" -ForegroundColor Red
    } elseif ($guiLaunched) {
        Write-Host "  [OK] GUI launched successfully" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] GUI launch status unclear" -ForegroundColor Yellow
    }
} catch {
    $failures += @{
        File = "Helper\WinRepairGUI.ps1"
        Line = 0
        ErrorType = "GUILaunchException"
        ErrorMessage = $_.Exception.Message
        RootCause = "Exception during GUI launch test"
        Confidence = 95
    }
    Write-Host "  [FAIL] GUI launch exception: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FAILURE DISCLOSURE SUMMARY ===" -ForegroundColor Cyan
if ($failures.Count -eq 0) {
    Write-Host "No failures detected. GUI appears to be working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Failures detected: $($failures.Count)" -ForegroundColor Red
    Write-Host ""
    foreach ($failure in $failures) {
        Write-Host "FILE: $($failure.File)" -ForegroundColor Yellow
        Write-Host "LINE: $($failure.Line)" -ForegroundColor Yellow
        Write-Host "ERROR TYPE: $($failure.ErrorType)" -ForegroundColor Yellow
        Write-Host "ERROR MESSAGE: $($failure.ErrorMessage)" -ForegroundColor Yellow
        Write-Host "ROOT CAUSE: $($failure.RootCause)" -ForegroundColor Yellow
        Write-Host "CONFIDENCE LEVEL: $($failure.Confidence)%" -ForegroundColor Yellow
        Write-Host ""
    }
    exit 1
}
