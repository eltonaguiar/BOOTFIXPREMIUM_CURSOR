# CLI smoke for precision/parity/JSON/BRICKME/log prompt
param(
    [string]$WindowsRoot = "C:\Windows",
    [string]$EspDriveLetter = "Z"
)

Write-Host "=== PRECISION SMOKE: PREVIEW ===" -ForegroundColor Cyan
Start-PrecisionScan -WindowsRoot $WindowsRoot -EspDriveLetter $EspDriveLetter -ActionLogPath "$env:TEMP\precision-actions.log"

Write-Host "=== PRECISION SMOKE: APPLY (DRY BY DEFAULT) ===" -ForegroundColor Cyan
Start-PrecisionScan -WindowsRoot $WindowsRoot -EspDriveLetter $EspDriveLetter -Apply -ActionLogPath "$env:TEMP\precision-actions.log"

Write-Host "=== PRECISION QUICK JSON (CONSOLE) ===" -ForegroundColor Cyan
Invoke-PrecisionQuickScanCli -WindowsRoot $WindowsRoot -EspDriveLetter $EspDriveLetter -IncludeBugcheck

Write-Host "=== PARITY JSON (CONSOLE) ===" -ForegroundColor Cyan
Invoke-PrecisionParityHarness -WindowsRoot $WindowsRoot -EspDriveLetter $EspDriveLetter -AsJson -ActionLogPath "$env:TEMP\precision-actions.log"

Write-Host "=== PRECISION JSON TO FILE ===" -ForegroundColor Cyan
Invoke-PrecisionQuickScan -WindowsRoot $WindowsRoot -EspDriveLetter $EspDriveLetter -AsJson -IncludeBugcheck -OutFile "$env:TEMP\precision-scan.json"
Write-Host "Wrote $env:TEMP\precision-scan.json" -ForegroundColor Green

Write-Host "=== PARITY JSON TO FILE ===" -ForegroundColor Cyan
Invoke-PrecisionParityHarness -WindowsRoot $WindowsRoot -EspDriveLetter $EspDriveLetter -AsJson -OutFile "$env:TEMP\precision-parity.json" -ActionLogPath "$env:TEMP\precision-actions.log"
Write-Host "Wrote $env:TEMP\precision-parity.json" -ForegroundColor Green

Write-Host "=== BCD ENUM ===" -ForegroundColor Cyan
cmd.exe /c "bcdedit /enum all"

Write-Host "=== LOG PROMPT (MANUAL) ===" -ForegroundColor Cyan
Start-PrecisionScan -WindowsRoot $WindowsRoot -EspDriveLetter $EspDriveLetter -AskOpenLogs
