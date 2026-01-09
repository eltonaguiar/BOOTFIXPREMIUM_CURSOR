# Test-RealGUILaunch.ps1
# Actually runs MiracleBoot.ps1 and captures real errors

$ErrorActionPreference = 'Continue'
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "REAL GUI LAUNCH TEST - RUNNING MIRACLEBOOT.PS1" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$output = @()
$errors = @()

# Capture output
$originalWriteHost = Get-Command Write-Host
$originalWriteWarning = Get-Command Write-Warning
$originalWriteError = Get-Command Write-Error

function Write-Host {
    param([object]$Object, [ConsoleColor]$ForegroundColor = [ConsoleColor]::White)
    $script:output += $Object.ToString()
    & $originalWriteHost $Object -ForegroundColor $ForegroundColor
}

function Write-Warning {
    param([string]$Message)
    $script:output += "WARNING: $Message"
    $script:errors += "WARNING: $Message"
    & $originalWriteWarning $Message
}

function Write-Error {
    param([string]$Message)
    $script:output += "ERROR: $Message"
    $script:errors += "ERROR: $Message"
    & $originalWriteError $Message
}

try {
    Write-Host "Loading MiracleBoot.ps1..." -ForegroundColor Yellow
    Write-Host ""
    
    # Run in a background job with timeout
    $job = Start-Job -ScriptBlock {
        param($scriptRoot)
        Set-Location $scriptRoot
        $ErrorActionPreference = 'Continue'
        . ".\MiracleBoot.ps1"
    } -ArgumentList $scriptRoot
    
    # Wait up to 10 seconds for initialization
    $job | Wait-Job -Timeout 10 | Out-Null
    
    if ($job.State -eq 'Running') {
        Write-Host "GUI appears to have launched (job still running)" -ForegroundColor Green
        Stop-Job $job
        Remove-Job $job -Force
    } else {
        $result = Receive-Job $job
        if ($result) {
            $output += $result
        }
        Remove-Job $job -Force
    }
    
} catch {
    $errors += $_.Exception.Message
    $errors += $_.ScriptStackTrace
    Write-Host "EXCEPTION: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "CAPTURED OUTPUT (last 40 lines):" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
$output | Select-Object -Last 40 | ForEach-Object { Write-Host $_ }

# Scan for critical errors
$criticalPatterns = @(
    'Get-Control.*not recognized',
    'null-valued expression',
    'Cannot set unknown member',
    'GUI MODE FAILED',
    'FALLING BACK TO TUI',
    'Exception',
    'ParserError'
)

$criticalErrors = @()
foreach ($pattern in $criticalPatterns) {
    $matches = $output | Select-String -Pattern $pattern -CaseSensitive:$false
    if ($matches) {
        $criticalErrors += $matches
    }
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "ERROR ANALYSIS" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

if ($criticalErrors.Count -gt 0) {
    Write-Host "[FAIL] CRITICAL ERRORS DETECTED:" -ForegroundColor Red
    $criticalErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Red
    Write-Host "GUI LAUNCH FAILED - FIX ERRORS BEFORE USER TESTING" -ForegroundColor Red
    Write-Host "=" * 80 -ForegroundColor Red
    exit 1
} else {
    Write-Host "[PASS] No critical errors detected" -ForegroundColor Green
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Green
    Write-Host "GUI LAUNCH TEST PASSED" -ForegroundColor Green
    Write-Host "=" * 80 -ForegroundColor Green
    exit 0
}

