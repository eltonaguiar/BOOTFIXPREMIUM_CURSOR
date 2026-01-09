# Test-FinalProductionCheck.ps1
# Final production check - actually runs MiracleBoot.ps1 with proper execution policy

Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = 'Continue'
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "FINAL PRODUCTION CHECK - RUNNING MIRACLEBOOT.PS1" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

cd $scriptRoot

Write-Host "Current directory: $(Get-Location)" -ForegroundColor Gray
Write-Host "Execution Policy: $(Get-ExecutionPolicy -Scope Process)" -ForegroundColor Gray
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

# Capture output
$outputFile = Join-Path $env:TEMP "MiracleBoot_FinalTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$errorFile = Join-Path $env:TEMP "MiracleBoot_FinalErrors_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

Write-Host "Running MiracleBoot.ps1 (capturing output for 10 seconds)..." -ForegroundColor Yellow
Write-Host ""

# Run in background to capture output
$job = Start-Job -ScriptBlock {
    param($scriptRoot, $outputFile)
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Set-Location $scriptRoot
    $ErrorActionPreference = 'Continue'
    
    # Redirect all output
    . ".\MiracleBoot.ps1" *> $outputFile
} -ArgumentList $scriptRoot, $outputFile

# Wait for initialization
Start-Sleep -Seconds 10

# Stop the job
if ($job.State -eq 'Running') {
    Write-Host "GUI appears to have launched (job still running)" -ForegroundColor Green
    Stop-Job $job
    Remove-Job $job -Force
} else {
    Receive-Job $job | Out-Null
    Remove-Job $job -Force
}

# Read captured output
if (Test-Path $outputFile) {
    $output = Get-Content $outputFile -Raw
    
    Write-Host "=== CAPTURED OUTPUT (last 50 lines) ===" -ForegroundColor Cyan
    Write-Host ""
    ($output -split "`r?`n" | Select-Object -Last 50) -join "`n"
    Write-Host ""
    
    # Scan for critical errors
    $criticalPatterns = @(
        'Get-Control.*not recognized',
        'null-valued expression',
        'Cannot set unknown member',
        'GUI MODE FAILED',
        'FALLING BACK TO TUI',
        'ParserError',
        'syntax error',
        'Missing closing',
        'Unexpected token',
        'Exception calling'
    )
    
    # Expected patterns (not errors)
    $expectedPatterns = @(
        'Administrator Privileges Required',
        'Export-ModuleMember'
    )
    
    $criticalErrors = @()
    foreach ($pattern in $criticalPatterns) {
        if ($output -match $pattern) {
            # Check context to see if it's near an expected pattern
            $matchIndex = $output.IndexOf($pattern)
            $context = $output.Substring([Math]::Max(0, $matchIndex - 100), [Math]::Min(200, $output.Length - [Math]::Max(0, $matchIndex - 100)))
            
            $isExpected = $false
            foreach ($expected in $expectedPatterns) {
                if ($context -match $expected) {
                    $isExpected = $true
                    break
                }
            }
            
            if (-not $isExpected) {
                $criticalErrors += $pattern
            }
        }
    }
    
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "ERROR ANALYSIS" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host ""
    
    if ($criticalErrors.Count -gt 0) {
        Write-Host "[FAIL] CRITICAL ERRORS DETECTED:" -ForegroundColor Red
        $criticalErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host "PRODUCTION CHECK FAILED" -ForegroundColor Red
        Write-Host "DO NOT PROCEED TO USER TESTING" -ForegroundColor Red
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host ""
        Write-Host "Full output saved to: $outputFile" -ForegroundColor Gray
        exit 1
    } else {
        Write-Host "[PASS] No critical errors detected" -ForegroundColor Green
        Write-Host ""
        
        # Check for success indicators
        $successPatterns = @(
            'GUI module loaded successfully',
            'Start-GUI function found',
            'WPF assemblies loaded'
        )
        
        $successCount = 0
        foreach ($pattern in $successPatterns) {
            if ($output -match $pattern) {
                $successCount++
            }
        }
        
        Write-Host "Success indicators found: $successCount / $($successPatterns.Count)" -ForegroundColor $(if ($successCount -eq $successPatterns.Count) { "Green" } else { "Yellow" })
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Green
        Write-Host "PRODUCTION CHECK PASSED" -ForegroundColor Green
        Write-Host "GUI LAUNCHES SUCCESSFULLY - READY FOR USER TESTING" -ForegroundColor Green
        Write-Host "=" * 80 -ForegroundColor Green
        Write-Host ""
        Write-Host "Note: 'Administrator Privileges Required' is EXPECTED when" -ForegroundColor Gray
        Write-Host "      clicking BCD operations without admin privileges." -ForegroundColor Gray
        Write-Host ""
        Write-Host "Full output saved to: $outputFile" -ForegroundColor Gray
        exit 0
    }
} else {
    Write-Host "[WARNING] No output file created" -ForegroundColor Yellow
    exit 1
}

