# Fault injection helpers for precision boot scanner
param(
    [string]$TargetWindows = "C:\Windows",
    [string]$EspDrive = "Z",
    [switch]$DoStartOverride,
    [switch]$DoPendingXmlExclusive,
    [switch]$DoBcdMissing,
    [switch]$DoBitLockerTrap,
    [switch]$DoEspFormat
)

function Make-PendingXmlExclusive {
    param($path)
    if (-not (Test-Path $path)) {
        $xml = @"
<PendingOperations>
  <Package id="dummy">
    <Checkpoint exclusive="true" />
  </Package>
</PendingOperations>
"@
        $xml | Set-Content -Path $path -Encoding UTF8
    } else {
        $px = Get-Content $path
        if ($px -notmatch "exclusive=") {
            $px +='<Checkpoint exclusive="true" />' | Set-Content -Path $path
        }
    }
}

if ($DoStartOverride) {
    Write-Host "Injecting storahci StartOverride trap..."
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\storahci" /v Start /t REG_DWORD /d 0 /f | Out-Null
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\storahci\StartOverride" /v 0 /t REG_DWORD /d 3 /f | Out-Null
}

if ($DoPendingXmlExclusive) {
    $pxPath = Join-Path $TargetWindows "WinSxS\pending.xml"
    Write-Host "Creating exclusive pending.xml at $pxPath"
    Make-PendingXmlExclusive -path $pxPath
}

if ($DoBcdMissing) {
    $bcd = "$EspDrive`:\EFI\Microsoft\Boot\BCD"
    if (Test-Path $bcd) {
        Write-Host "Renaming BCD to simulate missing store..."
        Rename-Item $bcd "$bcd.bak" -Force
    }
}

if ($DoBitLockerTrap) {
    Write-Host "Enabling BitLocker trap requires manage-bde; manual setup recommended."
}

if ($DoEspFormat) {
    Write-Host "ESP format change is destructive; run manually in a disposable VM: format $EspDrive`: /fs:ntfs /q"
}
