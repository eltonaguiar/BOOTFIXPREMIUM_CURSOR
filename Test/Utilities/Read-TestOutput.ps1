# Read-TestOutput.ps1
# Reads the latest test output file

$files = Get-ChildItem $env:TEMP -Filter "MiracleBoot_ElevatedTest_*.txt" | Sort-Object LastWriteTime -Descending

if ($files) {
    $latest = $files[0]
    Write-Host "Reading: $($latest.FullName)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "=== FULL OUTPUT ===" -ForegroundColor Cyan
    Write-Host ""
    Get-Content $latest.FullName
} else {
    Write-Host "No output file found" -ForegroundColor Yellow
}

