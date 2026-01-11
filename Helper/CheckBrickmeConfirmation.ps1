# CheckBrickmeConfirmation.ps1
# Safety interlock confirmation check

Write-Host ''
Write-Host '========================================' -ForegroundColor Yellow
Write-Host '  Miracle Boot v7.2.0 Launcher' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Yellow
Write-Host ''

if ($env:SystemDrive -ne 'X:') {
    Write-Host 'SAFETY WARNING: You are running from a live Windows OS drive' $env:SystemDrive -ForegroundColor Red
    Write-Host 'Destructive boot repairs can brick the system if misused.' -ForegroundColor Yellow
    Write-Host 'To continue, type BRICKME and press Enter. Otherwise, press Ctrl+C to abort.' -ForegroundColor Yellow
    Write-Host ''
    $confirm = Read-Host 'Type BRICKME to continue'
    if ($confirm -ne 'BRICKME') {
        Write-Host 'Aborting by user choice. No changes made.' -ForegroundColor Yellow
        exit 1
    }
}

exit 0
