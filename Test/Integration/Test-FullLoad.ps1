# Test full module loading as it happens in WinRepairGUI.ps1
$ErrorActionPreference = 'Continue'
$Error.Clear()

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "FULL MODULE LOAD TEST" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$scriptRoot = Split-Path $PSScriptRoot -Parent
$logAnalysisPath = Join-Path $scriptRoot "Helper\LogAnalysis.ps1"

Write-Host "Script Root: $scriptRoot" -ForegroundColor Gray
Write-Host "LogAnalysis Path: $logAnalysisPath" -ForegroundColor Gray
Write-Host ""

if (-not (Test-Path $logAnalysisPath)) {
    Write-Host "ERROR: LogAnalysis.ps1 not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Attempting to load LogAnalysis.ps1 (as WinRepairGUI.ps1 does)..." -ForegroundColor Yellow
Write-Host ""

try {
    # This is how WinRepairGUI.ps1 loads it
    . $logAnalysisPath
    
    Write-Host "SUCCESS: LogAnalysis.ps1 loaded" -ForegroundColor Green
    Write-Host ""
    
    # Check if function exists
    $func = Get-Command Get-ComprehensiveLogAnalysis -ErrorAction SilentlyContinue
    if ($func) {
        Write-Host "Function Get-ComprehensiveLogAnalysis found!" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Function Get-ComprehensiveLogAnalysis not found" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR: Failed to load LogAnalysis.ps1" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Category: $($_.CategoryInfo.Category)" -ForegroundColor Yellow
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    
    if ($Error.Count -gt 0) {
        Write-Host ""
        Write-Host "All errors captured:" -ForegroundColor Magenta
        $Error | Select-Object -First 10 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Red
        }
    }
    
    exit 1
}

Write-Host ""
Write-Host "Test completed successfully!" -ForegroundColor Green


