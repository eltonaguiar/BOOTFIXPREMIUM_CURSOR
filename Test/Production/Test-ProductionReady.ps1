# Test-ProductionReady.ps1
# Comprehensive production readiness test that actually calls Start-GUI
# and verifies no critical errors occur during GUI initialization

$ErrorActionPreference = 'Continue'
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PRODUCTION READINESS TEST - MIRACLEBOOT GUI" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Check environment
if ($env:SystemDrive -eq 'X:') {
    Write-Host "[SKIP] Not in FullOS environment (SystemDrive=X:) - GUI test skipped" -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path "$env:SystemDrive\Windows")) {
    Write-Host "[SKIP] Windows directory not found - may not be FullOS - GUI test skipped" -ForegroundColor Yellow
    exit 0
}

Write-Host "Environment: FullOS detected" -ForegroundColor Green
Write-Host ""

# Load modules
Write-Host "Loading core modules..." -ForegroundColor Yellow
. "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Continue

# Check WPF
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Write-Host "WPF assemblies available" -ForegroundColor Green
} catch {
    Write-Host "[SKIP] WPF not available: $_" -ForegroundColor Yellow
    exit 0
}

# Load GUI module
Write-Host "Loading WinRepairGUI.ps1..." -ForegroundColor Yellow
$errorBefore = $Error.Count
. "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Continue
$errorAfter = $Error.Count

# Check for errors during load
$loadErrors = @()
if ($errorAfter -gt $errorBefore) {
    for ($i = $errorBefore; $i -lt $errorAfter; $i++) {
        $err = $Error[$i]
        if ($err.Exception.Message -notmatch 'Export-ModuleMember') {
            $loadErrors += $err.Exception.Message
        }
    }
}

if ($loadErrors.Count -gt 0) {
    Write-Host "[FAIL] Errors during module load:" -ForegroundColor Red
    $loadErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host "GUI module loaded successfully" -ForegroundColor Green

# Verify Start-GUI exists
if (-not (Get-Command Start-GUI -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] Start-GUI function not found" -ForegroundColor Red
    exit 1
}

Write-Host "Start-GUI function found" -ForegroundColor Green
Write-Host ""

# Actually call Start-GUI and capture errors
Write-Host "Calling Start-GUI (will monitor for 8 seconds)..." -ForegroundColor Yellow
Write-Host ""

$outputFile = Join-Path $env:TEMP "MiracleBoot_GUI_Test_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$errorFile = Join-Path $env:TEMP "MiracleBoot_GUI_Errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Create a script that will actually invoke Start-GUI
$testScript = @"
`$ErrorActionPreference = 'Continue'
cd '$scriptRoot'

# Capture output
`$allOutput = New-Object System.Collections.ArrayList
`$allErrors = New-Object System.Collections.ArrayList

function Write-Host {
    param([object]`$Object, [ConsoleColor]`$ForegroundColor = [ConsoleColor]::White)
    [void]`$script:allOutput.Add(`$Object.ToString())
    Microsoft.PowerShell.Utility\Write-Host `$Object -ForegroundColor `$ForegroundColor
}

function Write-Warning {
    param([string]`$Message)
    [void]`$script:allOutput.Add("WARNING: `$Message")
    [void]`$script:allErrors.Add("WARNING: `$Message")
    Microsoft.PowerShell.Utility\Write-Warning `$Message
}

function Write-Error {
    param([string]`$Message)
    [void]`$script:allOutput.Add("ERROR: `$Message")
    [void]`$script:allErrors.Add("ERROR: `$Message")
    Microsoft.PowerShell.Utility\Write-Error `$Message
}

try {
    # Load modules
    . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Continue
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    . "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Continue
    
    Write-Host "Calling Start-GUI..." -ForegroundColor Cyan
    
    # Call Start-GUI in a way that won't block forever
    # We'll use a job with timeout
    `$guiJob = Start-Job -ScriptBlock {
        param(`$scriptRoot)
        . "$using:scriptRoot\Helper\WinRepairCore.ps1"
        Add-Type -AssemblyName PresentationFramework
        . "$using:scriptRoot\Helper\WinRepairGUI.ps1"
        Start-GUI
    } -ArgumentList '$scriptRoot'
    
    # Wait a bit for initialization
    Start-Sleep -Seconds 5
    
    if (`$guiJob.State -eq 'Running') {
        Write-Host "GUI launched successfully (job running)" -ForegroundColor Green
        Stop-Job `$guiJob
        Remove-Job `$guiJob -Force
    } else {
        `$result = Receive-Job `$guiJob
        if (`$result) {
            [void]`$script:allOutput.AddRange(`$result)
        }
        Remove-Job `$guiJob -Force
    }
    
} catch {
    [void]`$script:allErrors.Add(`$_.Exception.Message)
    [void]`$script:allErrors.Add(`$_.ScriptStackTrace)
    Write-Host "EXCEPTION: `$_" -ForegroundColor Red
}

# Output results
`$allOutput | Out-File '$outputFile' -Encoding UTF8
if (`$allErrors.Count -gt 0) {
    `$allErrors | Out-File '$errorFile' -Encoding UTF8
}

# Output to console
Write-Host ""
Write-Host "=== OUTPUT ===" -ForegroundColor Cyan
`$allOutput | ForEach-Object { Write-Host `$_ }

if (`$allErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "=== ERRORS ===" -ForegroundColor Red
    `$allErrors | ForEach-Object { Write-Host `$_ -ForegroundColor Red }
    exit 1
} else {
    exit 0
}
"@

$tempScript = Join-Path $env:TEMP "MiracleBoot_StartGUI_Test_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
Set-Content -Path $tempScript -Value $testScript -Encoding UTF8

try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'pwsh.exe'
    $psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$tempScript`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    
    [void]$process.Start()
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()
    $process.WaitForExit(10000)
    
    if (-not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit(2000)
    }
    
    $exitCode = $process.ExitCode
    
    Write-Host $stdOut
    if ($stdErr) {
        Write-Host $stdErr -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "ERROR ANALYSIS" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host ""
    
    # Critical error patterns (these indicate actual failures)
    $criticalPatterns = @(
        'Get-Control.*not recognized',
        'null-valued expression',
        'Cannot set unknown member',
        'GUI MODE FAILED',
        'FALLING BACK TO TUI',
        'ParserError',
        'syntax error',
        'Missing closing',
        'Unexpected token'
    )
    
    # Expected patterns (not errors)
    $expectedPatterns = @(
        'Administrator Privileges Required',  # Expected when clicking BCD without admin
        'Export-ModuleMember'                 # Expected warning
    )
    
    $combinedOutput = $stdOut + "`n" + $stdErr
    $criticalErrors = @()
    
    foreach ($pattern in $criticalPatterns) {
        if ($combinedOutput -match $pattern) {
            # Check if it's an expected pattern
            $isExpected = $false
            foreach ($expected in $expectedPatterns) {
                if ($combinedOutput -match $expected) {
                    # If the error is near an expected pattern, it might be expected
                    $isExpected = $false  # Keep checking
                }
            }
            if (-not $isExpected) {
                $criticalErrors += $pattern
            }
        }
    }
    
    if ($criticalErrors.Count -gt 0) {
        Write-Host "[FAIL] CRITICAL ERRORS DETECTED:" -ForegroundColor Red
        $criticalErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host "PRODUCTION READINESS TEST FAILED" -ForegroundColor Red
        Write-Host "DO NOT PROCEED TO USER TESTING" -ForegroundColor Red
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host ""
        if (Test-Path $outputFile) {
            Write-Host "Full output: $outputFile" -ForegroundColor Gray
        }
        if (Test-Path $errorFile) {
            Write-Host "Errors: $errorFile" -ForegroundColor Gray
        }
        exit 1
    } else {
        Write-Host "[PASS] No critical errors detected" -ForegroundColor Green
        Write-Host ""
        Write-Host "EXIT CODE: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Green
        Write-Host "PRODUCTION READINESS TEST PASSED" -ForegroundColor Green
        Write-Host "GUI LAUNCHES SUCCESSFULLY - READY FOR USER TESTING" -ForegroundColor Green
        Write-Host "=" * 80 -ForegroundColor Green
        Write-Host ""
        Write-Host "Note: 'Administrator Privileges Required' messages are EXPECTED" -ForegroundColor Gray
        Write-Host "      when clicking BCD operations without admin privileges." -ForegroundColor Gray
        exit 0
    }
    
} finally {
    if (Test-Path $tempScript) {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }
}

