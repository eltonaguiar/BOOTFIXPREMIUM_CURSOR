# Precision CI Runner: smoke + optional fault injection (run in disposable VM)
[CmdletBinding()]
param(
    [string]$WindowsRoot = "C:\Windows",
    [string]$EspDriveLetter = "Z",
    [switch]$WithFaults,
    [string]$LogDir = "$env:TEMP\precision-ci"
)

function Ensure-Dir($path) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
}

Ensure-Dir $LogDir
$actionLog = Join-Path $LogDir "precision-actions.log"
$scanJson  = Join-Path $LogDir "precision-scan.json"
$parityJson= Join-Path $LogDir "precision-parity.json"

Write-Host "=== Precision CI: Smoke ===" -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File ".\Test\Invoke-PrecisionSmoke.ps1"

Copy-Item "$env:TEMP\precision-actions.log" $actionLog -ErrorAction SilentlyContinue
Copy-Item "$env:TEMP\precision-scan.json"  $scanJson  -ErrorAction SilentlyContinue
Copy-Item "$env:TEMP\precision-parity.json" $parityJson -ErrorAction SilentlyContinue

if ($WithFaults) {
    Write-Host "=== Precision CI: Fault Injection ===" -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File ".\Test\Invoke-FaultInjection.ps1" -DoStartOverride -DoPendingXmlExclusive -DoBcdMissing
    Write-Host "Re-running smoke after fault injection..." -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File ".\Test\Invoke-PrecisionSmoke.ps1"
    Copy-Item "$env:TEMP\precision-actions.log" (Join-Path $LogDir "precision-actions-faults.log") -ErrorAction SilentlyContinue
    Copy-Item "$env:TEMP\precision-scan.json"  (Join-Path $LogDir "precision-scan-faults.json") -ErrorAction SilentlyContinue
    Copy-Item "$env:TEMP\precision-parity.json" (Join-Path $LogDir "precision-parity-faults.json") -ErrorAction SilentlyContinue
}

Write-Host "Logs and JSON stored in $LogDir" -ForegroundColor Green
