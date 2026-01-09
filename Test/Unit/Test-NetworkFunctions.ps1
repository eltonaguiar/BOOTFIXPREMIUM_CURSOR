# Test NetworkDiagnostics.ps1 functions
$ErrorActionPreference = 'Continue'
$scriptRoot = Split-Path $PSScriptRoot -Parent

Write-Host "Loading NetworkDiagnostics.ps1..." -ForegroundColor Yellow
. "$scriptRoot\Helper\NetworkDiagnostics.ps1"

Write-Host "`nChecking for functions..." -ForegroundColor Cyan
$functions = @("Get-NetworkAdapterStatus", "Test-NetworkConnectivity", "Get-NetworkDrivers", "Invoke-NetworkDiagnostics")

foreach ($func in $functions) {
    $cmd = Get-Command $func -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "  [FOUND] $func" -ForegroundColor Green
    } else {
        Write-Host "  [NOT FOUND] $func" -ForegroundColor Red
    }
}

Write-Host "`nAll available functions from NetworkDiagnostics:" -ForegroundColor Cyan
Get-Command | Where-Object { $_.Source -like "*NetworkDiagnostics*" } | ForEach-Object {
    Write-Host "  - $($_.Name)" -ForegroundColor Gray
}


