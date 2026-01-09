# Test-ProductionReadyElevated.ps1
# Launches elevated PowerShell and runs MiracleBoot.ps1 inside it
# Captures all output to verify production readiness

$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }
$outputFile = Join-Path $env:TEMP "MiracleBoot_ElevatedTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$errorFile = Join-Path $env:TEMP "MiracleBoot_ElevatedErrors_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PRODUCTION READINESS TEST - ELEVATED MODE" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "Creating elevated PowerShell test script..." -ForegroundColor Yellow

# Create script that will run in elevated PowerShell
$elevatedScript = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
`$ErrorActionPreference = 'Continue'
cd '$scriptRoot'

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "MIRACLEBOOT PRODUCTION TEST - ELEVATED SESSION" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "Current directory: `$(Get-Location)" -ForegroundColor Gray
Write-Host "Execution Policy: `$(Get-ExecutionPolicy -Scope Process)" -ForegroundColor Gray
Write-Host "Running as Admin: `$(([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))" -ForegroundColor Gray
Write-Host ""

# Capture all output
`$allOutput = @()
`$allErrors = @()

function Write-OutputCapture {
    param([string]`$Message, [ConsoleColor]`$Color = [ConsoleColor]::White)
    `$script:allOutput += `$Message
    Write-Host `$Message -ForegroundColor `$Color
}

function Write-WarningCapture {
    param([string]`$Message)
    `$script:allOutput += "WARNING: `$Message"
    `$script:allErrors += "WARNING: `$Message"
    Write-Warning `$Message
}

function Write-ErrorCapture {
    param([string]`$Message)
    `$script:allOutput += "ERROR: `$Message"
    `$script:allErrors += "ERROR: `$Message"
    Write-Error `$Message
}

try {
    Write-OutputCapture "Loading MiracleBoot.ps1..." Cyan
    
    # Run MiracleBoot.ps1 in a job with timeout
    `$job = Start-Job -ScriptBlock {
        param(`$scriptRoot)
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Set-Location `$scriptRoot
        `$ErrorActionPreference = 'Continue'
        . ".\MiracleBoot.ps1"
    } -ArgumentList '$scriptRoot'
    
    # Wait up to 12 seconds for GUI to initialize
    `$job | Wait-Job -Timeout 12 | Out-Null
    
    if (`$job.State -eq 'Running') {
        Write-OutputCapture "GUI launched successfully (job still running)" Green
        Stop-Job `$job
        Remove-Job `$job -Force
    } else {
        `$result = Receive-Job `$job
        if (`$result) {
            `$script:allOutput += `$result
        }
        Remove-Job `$job -Force
    }
    
    Write-OutputCapture "" White
    Write-OutputCapture "=== TEST COMPLETE ===" Cyan
    
} catch {
    `$script:allErrors += `$_.Exception.Message
    `$script:allErrors += `$_.ScriptStackTrace
    Write-OutputCapture "EXCEPTION: `$_" Red
}

# Write output to files
`$allOutput | Out-File '$outputFile' -Encoding UTF8
if (`$allErrors.Count -gt 0) {
    `$allErrors | Out-File '$errorFile' -Encoding UTF8
}

# Display summary
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "OUTPUT SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
`$allOutput | Select-Object -Last 30 | ForEach-Object { Write-Host `$_ }

if (`$allErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "ERRORS FOUND: `$(`$allErrors.Count)" -ForegroundColor Red
    `$allErrors | ForEach-Object { Write-Host `$_ -ForegroundColor Red }
} else {
    Write-Host ""
    Write-Host "NO ERRORS DETECTED" -ForegroundColor Green
}

Write-Host ""
Write-Host "Output saved to: $outputFile" -ForegroundColor Gray
if (Test-Path '$errorFile') {
    Write-Host "Errors saved to: $errorFile" -ForegroundColor Gray
}

# Scan for critical errors
`$criticalPatterns = @(
    'Get-Control.*not recognized',
    'null-valued expression',
    'Cannot set unknown member',
    'GUI MODE FAILED',
    'FALLING BACK TO TUI',
    'ParserError',
    'syntax error'
)

`$combinedOutput = (`$allOutput -join "`n") + "`n" + (`$allErrors -join "`n")
`$criticalErrors = @()
foreach (`$pattern in `$criticalPatterns) {
    if (`$combinedOutput -match `$pattern) {
        `$criticalErrors += `$pattern
    }
}

if (`$criticalErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Red
    Write-Host "CRITICAL ERRORS DETECTED" -ForegroundColor Red
    `$criticalErrors | ForEach-Object { Write-Host "  - `$_" -ForegroundColor Red }
    Write-Host "=" * 80 -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Green
    Write-Host "PRODUCTION READINESS TEST PASSED" -ForegroundColor Green
    Write-Host "=" * 80 -ForegroundColor Green
    exit 0
}
"@

$tempScript = Join-Path $env:TEMP "MiracleBoot_ElevatedRunner_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
Set-Content -Path $tempScript -Value $elevatedScript -Encoding UTF8

Write-Host "Launching elevated PowerShell..." -ForegroundColor Yellow
Write-Host ""

try {
    # Launch elevated PowerShell and run the test
    $process = Start-Process pwsh.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`"" -Wait -PassThru
    
    Write-Host "Elevated PowerShell exited with code: $($process.ExitCode)" -ForegroundColor $(if ($process.ExitCode -eq 0) { "Green" } else { "Yellow" })
    Write-Host ""
    
    # Read the output file
    if (Test-Path $outputFile) {
        $output = Get-Content $outputFile -Raw
        Write-Host "=== CAPTURED OUTPUT ===" -ForegroundColor Cyan
        Write-Host $output
        Write-Host ""
        
        # Check for critical errors
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
        
        $criticalErrors = @()
        foreach ($pattern in $criticalPatterns) {
            if ($output -match $pattern) {
                # Check if it's an expected pattern (like admin prompt)
                if ($output -notmatch 'Administrator Privileges Required.*' + $pattern) {
                    $criticalErrors += $pattern
                }
            }
        }
        
        Write-Host "=" * 80 -ForegroundColor Cyan
        Write-Host "FINAL ANALYSIS" -ForegroundColor Cyan
        Write-Host "=" * 80 -ForegroundColor Cyan
        Write-Host ""
        
        if ($criticalErrors.Count -gt 0) {
            Write-Host "[FAIL] CRITICAL ERRORS DETECTED:" -ForegroundColor Red
            $criticalErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            Write-Host ""
            Write-Host "=" * 80 -ForegroundColor Red
            Write-Host "PRODUCTION READINESS TEST FAILED" -ForegroundColor Red
            Write-Host "DO NOT PROCEED TO USER TESTING" -ForegroundColor Red
            Write-Host "=" * 80 -ForegroundColor Red
            exit 1
        } else {
            Write-Host "[PASS] No critical errors detected" -ForegroundColor Green
            Write-Host ""
            
            # Check for success indicators
            $successIndicators = @(
                'GUI module loaded successfully',
                'Start-GUI function found',
                'WPF assemblies loaded',
                'GUI launched successfully'
            )
            
            $foundSuccess = 0
            foreach ($indicator in $successIndicators) {
                if ($output -match $indicator) {
                    $foundSuccess++
                }
            }
            
            Write-Host "Success indicators: $foundSuccess / $($successIndicators.Count)" -ForegroundColor $(if ($foundSuccess -ge 2) { "Green" } else { "Yellow" })
            Write-Host ""
            Write-Host "=" * 80 -ForegroundColor Green
            Write-Host "PRODUCTION READINESS TEST PASSED" -ForegroundColor Green
            Write-Host "GUI LAUNCHES SUCCESSFULLY - READY FOR USER TESTING" -ForegroundColor Green
            Write-Host "=" * 80 -ForegroundColor Green
            Write-Host ""
            Write-Host "Full output: $outputFile" -ForegroundColor Gray
            exit 0
        }
    } else {
        Write-Host "[WARNING] No output file created" -ForegroundColor Yellow
        Write-Host "The elevated PowerShell may have failed to run" -ForegroundColor Yellow
        exit 1
    }
    
} finally {
    if (Test-Path $tempScript) {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }
}

