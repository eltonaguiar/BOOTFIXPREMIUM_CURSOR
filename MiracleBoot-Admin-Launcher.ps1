# MiracleBoot-Admin-Launcher.ps1
# Automatically elevates to Administrator if needed

Write-Host "MiracleBoot Admin Launcher" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan

# Check if already running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if ($isAdmin) {
    Write-Host "✓ Already running as Administrator" -ForegroundColor Green
    Write-Host "Launching MiracleBoot..." -ForegroundColor Green
    & ".\MiracleBoot.ps1"
} else {
    Write-Host "⚠ Not running as Administrator" -ForegroundColor Yellow
    Write-Host "Requesting elevation..." -ForegroundColor Yellow
    
    # Re-launch as admin
    $script = $PSCommandPath
    Start-Process powershell.exe -ArgumentList "-STA -ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs
}
