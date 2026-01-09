# Precision Boot Issue Identification — Test Cases

Purpose: verify precision detection identifies boot blockers exactly, presents correct remediation commands, and achieves parity between CMD and GUI/TUI.

Guideline per test:
- Detection: issue identified with name + evidence.
- Suggested remediation: exact command(s) shown.
- Dry-run: commands previewed before execution.
- Apply: commands run and outcomes match expected.
- Logs: tool offers to scan and opens in Notepad when user agrees.
- Interface parity: run same scenario in CLI and GUI/TUI and compare outputs.

Format: ID — Title — Environment → Steps → Expected detection → Remediation commands → Acceptance criteria

---

TC-001 — Missing winload.efi (simple) — UEFI/GPT, BitLocker OFF
- Steps: delete C:\Windows\System32\winload.efi; boot to recovery; run `bootfix.exe scan --precision`
- Expected: missing file flagged with evidence (dir shows absent)
- Remediation: copy winload.efi (install media or DISM from install.wim) or `bcdboot C:\Windows /s Z: /f ALL`
- Acceptance: scanner flags missing file; after fix, Windows boots

TC-002 — Corrupt BCD — Legacy BIOS or UEFI
- Steps: corrupt/replace BCD; run scan
- Expected: “Corrupt BCD” with path and export failure evidence
- Remediation: `bcdedit /export C:\BCD_Backup`; `bootrec /fixboot`; `bootrec /rebuildbcd`; or `bcdboot C:\Windows /s Z: /f ALL`
- Acceptance: tool reports corruption; commands restore boot

TC-003 — Wrong ESP mapping (no drive letter) — UEFI/GPT
- Steps: remove ESP letter; run scan
- Expected: “EFI System Partition not assigned or not found” with evidence
- Remediation: `diskpart` assign letter, then `bcdboot C:\Windows /s Z: /f UEFI`
- Acceptance: suggests assignment + bcdboot; boot succeeds

TC-004 — Bad partition GUID/type — GPT
- Steps: set wrong partition type GUID on ESP/Windows partition
- Expected: “Partition GUID/type mismatch” with actual vs expected
- Remediation: `diskpart` (or `sgdisk`) to set correct GUID; warn before changes
- Acceptance: detection accurate; fixing GUID restores boot

TC-005 — EFI ACL / permission issues — UEFI
- Steps: restrict ACLs on EFI\Microsoft\Boot
- Expected: “Access denied reading …BCD — ACL indicates no read permission”
- Remediation: `takeown /F Z:\EFI\Microsoft\Boot /R /A`; `icacls Z:\EFI\Microsoft\Boot /grant Administrators:F /T`; rerun `bcdboot` if needed
- Acceptance: ACL issue reported; after commands, boot files readable and boot works

TC-006 — Secure Boot / BitLocker blocker — UEFI, SB ON, BitLocker ON
- Steps: attempt boot writes while BitLocker active
- Expected: detection of BitLocker volume + notice about Secure Boot
- Remediation: prompt to suspend BitLocker (`manage-bde -protectors -disable C:` or `-suspend`); inform about Secure Boot (no auto-disable)
- Acceptance: refuses destructive actions until BitLocker suspended or explicit override; user decision logged; commands correct

TC-007 — MBR vs UEFI mismatch — firmware vs disk schema mismatch
- Steps: create mismatch (e.g., GPT disk with legacy boot files)
- Expected: “Boot mode mismatch: firmware=UEFI, disk=MBR (or vice-versa)”
- Remediation: advise firmware mode change or disk conversion (MBR2GPT with warnings)
- Acceptance: mismatch detected; guidance safe and explicit

TC-008 — Multiple simultaneous issues
- Steps: introduce several faults (e.g., corrupt BCD + missing winload.efi + wrong ESP)
- Expected: all issues enumerated with evidence and ordered fixes
- Remediation: ordered plan (ESP letter → restore winload.efi → rebuild BCD)
- Acceptance: ordered plan resolves boot; logs show all steps

TC-009 — Log scan & Notepad open (policy)
- Steps: ensure SrtTrail.txt/ntbtlog exist; run `bootfix.exe scan --precision --scan-logs=ask`; answer Yes
- Expected: prompts to scan/open; opens in Notepad on consent
- Acceptance: prompt honored; Notepad shows file

TC-010 — GUI/TUI vs CMD parity
- Steps: run TC-002 in CLI and GUI/TUI; compare outputs
- Expected: identical detections, evidence, and remediation commands
- Acceptance: no discrepancies

---

CATEGORY A — DRIVER & KERNEL BOOT-STOPPERS

TC-011 — INACCESSIBLE_BOOT_DEVICE (0x7B) — AHCI/RAID mode mismatch
- Env: Win10/11; BIOS supports AHCI/RAID toggle
- Steps: install in AHCI; switch BIOS to RAID; BSOD 0x7B; run scan
- Expected: INACCESSIBLE_BOOT_DEVICE with evidence (BIOS mode ≠ registry StartOverride)
- Remediation: load SYSTEM hive; set storahci Start=0 and StartOverride 0=0; or BIOS revert
- Acceptance: boots after registry fix or BIOS revert

TC-012 — CRITICAL_PROCESS_DIED (0xEF) — core binary corrupt
- Steps: corrupt/replace csrss.exe; BSOD; run scan
- Expected: CRITICAL_PROCESS_DIED with hash mismatch / SFC failure evidence
- Remediation: `sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows`; `dism /image:C:\ /cleanup-image /restorehealth`
- Acceptance: system file restored; boot succeeds

TC-013 — SYSTEM_THREAD_EXCEPTION_NOT_HANDLED — bad GPU/storage driver
- Steps: install broken GPU driver; force boot loop; run scan
- Expected: detection referencing offending driver from minidump (e.g., nvlddmkm.sys)
- Remediation: `dism /image:C:\ /get-drivers`; `dism /image:C:\ /remove-driver /driver:oemXX.inf`; or `bcdedit /set {default} safeboot minimal`
- Acceptance: boots to Safe Mode or normal after driver removal

---

CATEGORY B — UPDATE / SERVICING FAILURES

TC-014 — Windows Update rollback loop
- Steps: interrupt feature update; endless “Undoing changes”; run scan
- Expected: rollback loop detected; evidence pending.xml, RebootPending
- Remediation: `dism /image:C:\ /cleanup-image /revertpendingactions`; delete pending.xml
- Acceptance: rollback completes; system boots

TC-015 — Component store corruption (WinSxS)
- Expected: “Component store corruption”; evidence DISM 0x800f081f
- Remediation: `dism /image:C:\ /cleanup-image /restorehealth /source:X:\sources\install.wim`
- Acceptance: DISM completes; servicing stack healthy

---

CATEGORY C — FILESYSTEM & DISK FAILURES

TC-016 — NTFS metadata corruption / UNMOUNTABLE_BOOT_VOLUME
- Expected: “NTFS corruption detected”; chkdsk required; dirty bit set
- Remediation: `chkdsk C: /f /r`
- Acceptance: NTFS repaired; boot resumes

TC-017 — Disk signature collision (cloning)
- Expected: “Disk signature collision detected”; duplicate disk IDs
- Remediation: `diskpart` → `select disk X` → `uniqueid disk`
- Acceptance: collision resolved; correct disk boots

---

CATEGORY D — REGISTRY & CONFIG FAILURES

TC-018 — Corrupt SYSTEM or SOFTWARE hive
- Expected: registry hive corrupt/missing; BSOD 0x51
- Remediation: restore from RegBack (`SYSTEM`, `SOFTWARE`)
- Acceptance: boot using restored hive

---

CATEGORY E — BOOT CONFIG EDGE CASES

TC-019 — Wrong OS device path in BCD
- Expected: “BCD device path incorrect”
- Remediation: `bcdedit /enum all`; set {default} device/osdevice to C:
- Acceptance: corrected path; boot succeeds

TC-020 — Hyper-V / VBS boot failure
- Expected: “VBS / Hyper-V boot blocker detected”
- Remediation: `bcdedit /set hypervisorlaunchtype off`
- Acceptance: boot succeeds on hardware that fails with VBS

---

CATEGORY F — OEM / REAL-WORLD PAIN POINTS

TC-021 — Intel RST / VMD controller missing driver
- Expected: “Intel VMD controller active but driver missing”
- Remediation: inject IRST driver: `dism /image:C:\ /add-driver /driver:X:\IRST /recurse`
- Acceptance: storage recognized; boot continues

TC-022 — Automatic Repair loop
- Expected: “Automatic Repair loop detected”
- Remediation: `bcdedit /set {default} recoveryenabled No`
- Acceptance: loop broken; boot proceeds (or clearer error presented)

---

CATEGORY G — SAFETY / UX EDGE CASES

TC-023 — Wrong Windows install selected
- Expected: prompt to select correct install with evidence (build, size, date)
- Acceptance: user selection recorded; repair targets chosen volume

TC-024 — Read-only volume / write protection
- Expected: “Volume is read-only”
- Remediation: `diskpart` → `attributes volume clear readonly`
- Acceptance: writes allowed; repairs proceed

---

Additional categories:
- Fuzz: random BCD corruption to ensure robust detection.
- Permissions regression: suggest minimally privileged commands; prompt for admin.
- Safety regression: dry-run prevents writes unless confirmed (BRICKME in live OS).
- Logging/audit: actions.log records timestamps, commands, user decisions.

Reporting:
- For each TC: keep a short report with exact commands, action logs, and repro notes or VM snapshots.

Tooling aids for precision debugging:
- CLI/WinRE/WinPE: `Start-PrecisionScan -PassThru` or `Invoke-PrecisionQuickScan -AsJson` for automation/log capture.
- Error-code lookup: `Search-PrecisionErrorCode "0x7B"` → TC-011; `CRITICAL_PROCESS_DIED` → TC-012; `SYSTEM_THREAD_EXCEPTION_NOT_HANDLED` → TC-013.
- Minidump/BugCheck triage: `Get-PrecisionDumpSummary -WindowsRoot C:\Windows` for latest dumps; `Get-PrecisionRecentBugcheck -WindowsRoot C:\Windows` to pull BugCheck 1001 from offline System.evtx.
- Parity (TC-010): `Invoke-PrecisionParityHarness -WindowsRoot C:\Windows -EspDriveLetter Z` compares CLI baseline with GUI/TUI outputs to ensure identical detection/remediation text.
- JSON export (CLI/TUI/GUI):
  - CLI: `Invoke-PrecisionQuickScan -WindowsRoot C:\Windows -EspDriveLetter Z -AsJson -IncludeBugcheck`
  - GUI: Diagnostics & Logs → “Export Precision Scan (JSON)” button.
  - TUI: Menu “X) Precision Quick Scan JSON export”.
  - Parity JSON: `Invoke-PrecisionParityHarness -WindowsRoot C:\Windows -EspDriveLetter Z -AsJson -OutFile parity.json`; GUI “Save Parity JSON to File”; TUI menu “W2) Precision Parity JSON export”.
- CLI alias (quick JSON to console): `Invoke-PrecisionQuickScanCli -WindowsRoot C:\Windows -EspDriveLetter Z -IncludeBugcheck`

Additional categories:
- Fuzz: random BCD corruption to ensure robust detection.
- Permissions regression: suggest minimally privileged commands; prompt for admin.
- Safety regression: dry-run mode prevents writes unless confirmed.
- Logging/audit: actions.log records timestamps, commands, user decisions.

Reporting:
- For each TC: keep a short report with exact commands, action logs, and repro notes or VM snapshots.
