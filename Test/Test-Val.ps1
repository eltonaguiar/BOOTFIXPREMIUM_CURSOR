$scriptRoot = Get-Location
. .\Helper\PreLaunchValidation.ps1
$validation = Test-PreLaunchValidation -ScriptRoot $scriptRoot
if (-not $validation.Passed) {
    Write-Host "FAILED" -ForegroundColor Red
    $validation.Errors | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    exit 1
} else {
    Write-Host "PASSED" -ForegroundColor Green
    exit 0
}
