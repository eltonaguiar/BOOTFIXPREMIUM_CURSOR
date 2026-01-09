# Precision Boot Repair – Test Plan (GUI / TUI / CLI / WinPE/WinRE/FullOS)

## Scope
- Precision detection/remediation flows (preview and apply).
- GUI, TUI, and CLI parity for detections, evidence, and remediation text.
- Safety gates: BRICKME (live OS), BitLocker awareness, backups before writes, version gate warning.
- JSON exports (scan/parity), log prompts, and BCD listing.
- Fault injection coverage for common boot blockers.

## Environments
- FullOS (Win10/11) elevated PowerShell.
- WinRE (Shift+F10).
- WinPE (e.g., Hiren).
- Disposable VM snapshots for “apply” and fault-injection runs.

## Smoke (non-destructive)
1) CLI preview: `Start-PrecisionScan -WindowsRoot C:\Windows -EspDriveLetter Z`
2) CLI apply (disposable VM): `Start-PrecisionScan -WindowsRoot C:\Windows -EspDriveLetter Z -Apply`
3) CLI JSON scan: `Invoke-PrecisionQuickScanCli -WindowsRoot C:\Windows -EspDriveLetter Z -IncludeBugcheck`
4) CLI parity JSON (console): `Invoke-PrecisionParityHarness -WindowsRoot C:\Windows -EspDriveLetter Z -AsJson`
5) CLI JSON files:
   - Scan: `Invoke-PrecisionQuickScan ... -AsJson -IncludeBugcheck -OutFile $env:TEMP\precision-scan.json`
   - Parity: `Invoke-PrecisionParityHarness ... -AsJson -OutFile $env:TEMP\precision-parity.json`
   - Optional: add `-ActionLogPath $env:TEMP\precision-actions.log` to centralize logging.
6) CI runner (disposable VM): `powershell -ExecutionPolicy Bypass -File .\Test\Invoke-PrecisionCI.ps1 -WithFaults -LogDir C:\Temp\precision-ci`
6) BCD enum: `bcdedit /enum all` (ensure no “unknown” when healthy).
7) Log prompt: `Start-PrecisionScan ... -AskOpenLogs` (Notepad opens on consent).

## GUI (non-destructive)
- Launch via `MiracleBoot.ps1` → GUI.
- BCD tab: Load/Refresh BCD (entries populate; no “unknown” when healthy).
- Precision Detection & Repair with Test Mode on (dry-run); observe output panel updates.
- Export Precision JSON; Save Precision JSON to file; Save Parity JSON to file.
- Parity button matches CLI output textually (Assert-PrecisionInterfaceParity if wired).
- Ensure GUI remains responsive; no crashes when commands are preview-only.

## TUI (non-destructive)
- Launch TUI.
- Z) Precision Boot Scan (preview), Y) Parity, X) Scan JSON (console/file), W2) Parity JSON (console/file).
- BCD view (if available in menus) shows entries; no crash.

## Safety checks
- BRICKME gate triggers in FullOS before Apply; skipped in WinRE/WinPE.
- BitLocker warning surfaces; no destructive writes without suspend/consent.
- Backups taken on Apply: SYSTEM hive save, BCD export.
- Version gate: warn if host PE build < target OS build.

## Fault Injection (disposable VM)
Use `Test\Invoke-FaultInjection.ps1`:
- StartOverride trap: `-DoStartOverride`
- pending.xml exclusive: `-DoPendingXmlExclusive`
- Missing BCD: `-DoBcdMissing`
- (Manual) BitLocker trap: enable BitLocker then run scan (expect halt/warning).
- (Manual) ESP format change: reformat ESP to NTFS in throwaway VM to trigger ESP format detection.

Expected detections after injection:
- StartOverride: TC-011 (INACCESSIBLE_BOOT_DEVICE / StartOverride).
- pending.xml exclusive: TC-014 exclusive lock.
- Missing BCD: TC-002 / TC-019-UNK (unknown device) as applicable.
- BitLocker trap: TC-006-BL warning; remediation requires suspend.
- ESP format: TC-003-ESPFS (not FAT32).

## Additional signals to verify
- Fast boot/hiberfile 0-byte: TC-FASTBOOT.
- Secure Boot on + winload missing: TC-SB-MISSING; Secure Boot on + winload present: TC-SB-SIG guidance.
- Critical driver zero-length (classpnp/ksecdd): TC-013-DRV.
- PendingFileRenameOperations present: TC-014-PFR.
- CBS RebootPending key: TC-014-CBS.
- BCD device/osdevice unknown: TC-019-UNK.

## Logging and JSON
- Validate JSON outputs parse: `Get-Content <file> | ConvertFrom-Json`.
- Ensure repair logs capture evidence and commands (where implemented).
- Check `%TEMP%\precision-actions.log` exists and records version gate, detections, remediation outcomes, and boot file hashes (when bcdboot/bootrec run).
- For CI runner, collect logs/JSON from `C:\Temp\precision-ci` (or chosen log dir).

## Success criteria
- No GUI/TUI crashes; UI remains responsive during dry-run.
- Parity: GUI/TUI outputs align with CLI (labels, evidence, commands).
- Safety gates enforced in live OS; no unguarded writes with BitLocker active.
- Fault-injected cases produce expected detections and suggested remediations.
