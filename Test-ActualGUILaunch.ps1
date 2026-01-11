# Test actual GUI launch
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Get-Location }

Write-Host "Loading modules..." -ForegroundColor Cyan
. "$scriptRoot\Helper\WinRepairCore.ps1"
Add-Type -AssemblyName PresentationFramework
. "$scriptRoot\Helper\WinRepairGUI.ps1"

Write-Host "Launching GUI..." -ForegroundColor Cyan
Write-Host "GUI window should open. Close it to complete the test." -ForegroundColor Yellow

try {
    Start-GUI
    Write-Host "GUI closed successfully." -ForegroundColor Green
    exit 0
} catch {
    Write-Host "ERROR: GUI launch failed: $_" -ForegroundColor Red
    Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
