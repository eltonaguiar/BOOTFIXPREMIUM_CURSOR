# Test loading LogAnalysis.ps1
$ErrorActionPreference = 'Continue'
$Error.Clear()

Write-Host "Testing LogAnalysis.ps1 load..." -ForegroundColor Cyan

try {
    $scriptPath = Join-Path $PSScriptRoot "..\Helper\LogAnalysis.ps1"
    Write-Host "Path: $scriptPath" -ForegroundColor Gray
    
    if (-not (Test-Path $scriptPath)) {
        Write-Host "ERROR: File not found!" -ForegroundColor Red
        exit 1
    }
    
    # Try loading with different encodings
    Write-Host "`nAttempting to load with default encoding..." -ForegroundColor Yellow
    . $scriptPath
    Write-Host "SUCCESS: Loaded with default encoding" -ForegroundColor Green
    
} catch {
    Write-Host "`nERROR occurred:" -ForegroundColor Red
    Write-Host "Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Category: $($_.CategoryInfo.Category)" -ForegroundColor Yellow
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    Write-Host "Position: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Yellow
    
    if ($Error.Count -gt 0) {
        Write-Host "`nAll errors:" -ForegroundColor Magenta
        $Error | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
    
    exit 1
}

Write-Host "`nChecking if functions were loaded..." -ForegroundColor Cyan
$functions = Get-Command -Module (Get-Module) | Where-Object { $_.Source -like "*LogAnalysis*" }
if ($functions) {
    Write-Host "Functions found:" -ForegroundColor Green
    $functions | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Green }
} else {
    Write-Host "No functions found (may be dot-sourced, not module)" -ForegroundColor Yellow
    $cmd = Get-Command Get-ComprehensiveLogAnalysis -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "Get-ComprehensiveLogAnalysis function found!" -ForegroundColor Green
    } else {
        Write-Host "Get-ComprehensiveLogAnalysis function NOT found" -ForegroundColor Red
    }
}


