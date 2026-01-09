# Test-MiracleBootWithAdmin.ps1
# Tests MiracleBoot.ps1 with proper admin privilege handling

$ErrorActionPreference = 'Continue'
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "MIRACLEBOOT GUI LAUNCH TEST (WITH ADMIN CHECK)" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[WARNING] Not running as Administrator" -ForegroundColor Yellow
    Write-Host "Attempting to elevate..." -ForegroundColor Yellow
    Write-Host ""
    
    # Try to elevate
    $elevatedScript = @"
`$ErrorActionPreference = 'Continue'
cd '$scriptRoot'
`$outputFile = '$env:TEMP\MiracleBoot_Test_Output_`$(Get-Date -Format 'yyyyMMdd_HHmmss').txt'
. '.\MiracleBoot.ps1' 2>&1 | Tee-Object -FilePath `$outputFile
Start-Sleep -Seconds 5
"@
    
    $tempScript = Join-Path $env:TEMP "MiracleBoot_Elevated_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    Set-Content -Path $tempScript -Value $elevatedScript -Encoding UTF8
    
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`"" -Wait -NoNewWindow
        Start-Sleep -Seconds 2
        
        # Check for output file
        $outputFiles = Get-ChildItem $env:TEMP -Filter "MiracleBoot_Test_Output_*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($outputFiles) {
            $output = Get-Content $outputFiles.FullName -Raw
            Write-Host "=== CAPTURED OUTPUT ===" -ForegroundColor Cyan
            Write-Host $output
        }
    } finally {
        if (Test-Path $tempScript) {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "[OK] Running as Administrator" -ForegroundColor Green
    Write-Host ""
    
    # Capture output
    $outputFile = Join-Path $env:TEMP "MiracleBoot_Test_Output_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    
    Write-Host "Running MiracleBoot.ps1 (will capture output for 10 seconds)..." -ForegroundColor Yellow
    Write-Host ""
    
    # Run in background job
    $job = Start-Job -ScriptBlock {
        param($scriptRoot, $outputFile)
        Set-Location $scriptRoot
        $ErrorActionPreference = 'Continue'
        . ".\MiracleBoot.ps1" 2>&1 | Tee-Object -FilePath $outputFile
    } -ArgumentList $scriptRoot, $outputFile
    
    # Wait for initialization
    Start-Sleep -Seconds 10
    
    # Stop the job
    if ($job.State -eq 'Running') {
        Stop-Job $job
        Remove-Job $job -Force
    } else {
        Receive-Job $job | Out-Null
        Remove-Job $job -Force
    }
    
    # Read captured output
    if (Test-Path $outputFile) {
        $output = Get-Content $outputFile -Raw
        Write-Host "=== CAPTURED OUTPUT ===" -ForegroundColor Cyan
        Write-Host $output
        Write-Host ""
        
        # Scan for errors
        $errorPatterns = @(
            'Get-Control.*not recognized',
            'null-valued expression',
            'Cannot set unknown member',
            'GUI MODE FAILED',
            'FALLING BACK TO TUI',
            'Exception',
            'ParserError',
            'Administrator Privileges Required'
        )
        
        $errorsFound = @()
        foreach ($pattern in $errorPatterns) {
            if ($output -match $pattern) {
                $errorsFound += $pattern
            }
        }
        
        Write-Host "=" * 80 -ForegroundColor Cyan
        Write-Host "ERROR ANALYSIS" -ForegroundColor Cyan
        Write-Host "=" * 80 -ForegroundColor Cyan
        Write-Host ""
        
        if ($errorsFound.Count -gt 0) {
            Write-Host "[FAIL] ERRORS DETECTED:" -ForegroundColor Red
            $errorsFound | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            Write-Host ""
            Write-Host "=" * 80 -ForegroundColor Red
            Write-Host "GUI LAUNCH FAILED - FIX ERRORS BEFORE USER TESTING" -ForegroundColor Red
            Write-Host "=" * 80 -ForegroundColor Red
            Write-Host ""
            Write-Host "Output saved to: $outputFile" -ForegroundColor Gray
            exit 1
        } else {
            Write-Host "[PASS] No critical errors detected" -ForegroundColor Green
            Write-Host ""
            Write-Host "=" * 80 -ForegroundColor Green
            Write-Host "GUI LAUNCH TEST PASSED" -ForegroundColor Green
            Write-Host "=" * 80 -ForegroundColor Green
            Write-Host ""
            Write-Host "Output saved to: $outputFile" -ForegroundColor Gray
            exit 0
        }
    } else {
        Write-Host "[WARNING] No output file created" -ForegroundColor Yellow
        exit 1
    }
}

