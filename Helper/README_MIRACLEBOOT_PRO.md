# MiracleBoot Pro - Forensic Boot Analyzer & Auto-Repair

## Overview

**MiracleBoot Pro** is the "Brain" of the MiracleBoot system - an automated forensic analyzer that goes beyond simple diagnostics to provide intelligent, actionable repair recommendations based on boot chain analysis and error code database lookups.

## Key Features

### 🧠 Intelligent Analysis
- **Boot Chain Forensics**: Analyzes boot stages to identify exact failure points
- **Error Code Database**: Maps Windows error codes to specific repair actions
- **Automated Detection**: Auto-detects Windows partition in WinPE/WinRE
- **Real-Time Monitoring**: Live log tailing for immediate error detection

### 🔧 Automated Repair
- **Registry Blocker Clearing**: Automatically removes "dirty" bits that block repairs
- **Offline SFC/DISM**: Intelligently constructs correct commands for offline repair
- **Hardware Diagnostics**: Rules out physical disk failures before software repair
- **Direct Action**: Provides exact commands to fix detected issues

### 🛡️ Safety Features
- **Non-Destructive**: Analysis mode doesn't modify anything
- **Confirmation Required**: Repair actions require explicit approval
- **Backup Recommendations**: Suggests backups before critical operations
- **Hardware First**: Checks disk health before attempting software repairs

---

## Usage

### Analysis Mode (Safe - No Changes)
```powershell
.\Helper\MiracleBootPro.ps1 -Mode Analyze
```

**What it does**:
- Analyzes boot chain and logs
- Detects registry blockers
- Checks disk health
- Provides repair recommendations
- **Does NOT modify anything**

### Full Mode (Analysis + Repair Options)
```powershell
.\Helper\MiracleBootPro.ps1 -Mode Full
```

**What it does**:
- Performs complete analysis
- Offers to clear registry blockers
- Provides repair commands with execution prompts
- Requires confirmation for each action

### Repair Mode (Auto-Fix Blockers)
```powershell
.\Helper\MiracleBootPro.ps1 -Mode Repair
```

**What it does**:
- Analyzes system
- Automatically clears registry blockers
- Provides repair commands (with prompts)

### Monitor Mode (Real-Time Log Watching)
```powershell
.\Helper\MiracleBootPro.ps1 -Mode Monitor
```

**What it does**:
- Monitors Panther logs in real-time
- Alerts when error codes appear
- Provides immediate recommendations
- Press Ctrl+C to stop

---

## Error Code Database

The system includes a comprehensive database of Windows error codes with specific repair actions:

| Error Code | Description | Action | Severity |
|------------|-------------|--------|----------|
| `0xc000000e` | Winload.efi missing/corrupt | Rebuild BCD | Critical |
| `0xc0000001` | Device not accessible | Check Disk/SATA | Critical |
| `0x80070002` | File not found | Verify SystemDrive | High |
| `0xc000021a` | Critical service failure | SFC Offline scan | Critical |
| `0xc0000221` | DLL missing/corrupt | DISM repair | Critical |
| `0xc0000142` | App initialization failed | SFC scan | High |
| `0x80070003` | Path not found | Verify BCD | High |
| `0xc0000098` | Insufficient resources | Check disk/memory | Medium |

**Extending the Database**:
Edit `$Global:ErrorDB` in `MiracleBootPro.ps1` to add new error codes and their repair actions.

---

## Registry Blockers

The system detects and can clear these common blockers:

### 1. Portable Operating System Flag
**Path**: `HKLM:\SYSTEM\CurrentControlSet\Control\PortableOperatingSystem`  
**Issue**: When set to 1, Windows Setup refuses to run  
**Fix**: Automatically set to 0

### 2. Pending File Rename Operations
**Path**: `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations`  
**Issue**: Blocks repairs until reboot  
**Fix**: Automatically cleared

### 3. Pending Reboot
**Path**: `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired`  
**Issue**: System thinks reboot is required  
**Fix**: Automatically cleared

### 4. CBS Reboot Pending
**Path**: `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending`  
**Issue**: Component store operations pending  
**Fix**: Automatically cleared

---

## Offline SFC/DISM Intelligence

### Automatic Partition Detection

In WinPE/WinRE (Shift+F10), the system automatically:
1. Detects the Windows partition (often NOT C: in recovery)
2. Constructs correct SFC command: `sfc /scannow /offbootdir=D:\ /offwindir=D:\Windows`
3. Constructs correct DISM command: `dism /image:D:\ /cleanup-image /restorehealth`

### Manual Override

```powershell
.\Helper\MiracleBootPro.ps1 -Mode Full -TargetDrive "D"
```

---

## Hardware Diagnostics

Before attempting software repairs, the system checks:

✅ **Disk Health Status** (Healthy/Warning/Critical)  
✅ **Read-Only Status** (prevents write operations)  
✅ **Free Disk Space** (warns if <10%)  
✅ **SMART Status** (temperature, if available)  

**If hardware issues are detected**:
- Software repairs are NOT recommended
- User is advised to backup data and replace hardware
- Prevents wasting time on software fixes for hardware failures

---

## Live Log Monitoring

### Real-Time Error Detection

```powershell
.\Helper\MiracleBootPro.ps1 -Mode Monitor
```

**Features**:
- Monitors Panther logs (`setupact.log`) in real-time
- Alerts immediately when error codes appear
- Provides instant recommendations
- Shows new log entries as they're written
- Timeout: 5 minutes (configurable)

**Use Cases**:
- Monitor repair operations in progress
- Catch errors as they occur
- Get immediate feedback during In-Place Upgrades

---

## Integration with MiracleBoot.ps1

### Automatic Integration

Add to `MiracleBoot.ps1`:

```powershell
# After environment detection, before GUI launch
if ($envType -eq "FullOS") {
    $proAnalyzer = Join-Path $PSScriptRoot "Helper\MiracleBootPro.ps1"
    if (Test-Path $proAnalyzer) {
        Write-Host "Running Pro analysis..." -ForegroundColor Cyan
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $proAnalyzer -Mode Analyze
    }
}
```

### Manual Launch

From GUI or TUI:
```powershell
# In WinRepairGUI.ps1 or WinRepairTUI.ps1
$proPath = Join-Path $PSScriptRoot "Helper\MiracleBootPro.ps1"
& pwsh -NoProfile -ExecutionPolicy Bypass -File $proPath -Mode Full
```

---

## Example Output

```
==========================================================================================
MIRACLEBOOT PRO: FORENSIC BOOT ANALYZER & AUTO-REPAIR
==========================================================================================

Windows Drive: C:

[!] Analyzing Boot Chain Stage...

  [FOUND] Boot Log: C:\Windows\ntbtlog.txt
    Last loaded: storahci.sys
    First failure: Did not load driver \SystemRoot\System32\drivers\storahci.sys
  [FOUND] Panther Log: C:\Windows\Panther\setupact.log
    Detected error code: 0xc0000221
    Stage: Driver
    Severity: Critical
    Recommended: Run DISM repair

[?] Identifying Registry Blockers...

  [BLOCKER] Portable OS flag is set to 1 (Setup will refuse to run)

[!] Running Hardware Diagnostics...

  Disk: Samsung SSD 980 PRO 1TB
  Health Status: Healthy
  Free Space: 450.23 GB (45.02%)
  [PASS] Disk health check passed

==========================================================================================
[ANALYSIS RESULTS]
==========================================================================================
Failure Stage:  Driver Initialization
Detected Code:  0xc0000221
Description:    Driver or system DLL is missing or corrupt
Severity:       Critical
Recommended:    Run DISM repair

[UPGRADE BLOCKERS DETECTED]
  - Portable OS Flag (Critical)
    Path: HKLM:\SYSTEM\CurrentControlSet\Control\PortableOperatingSystem

[AUTO-REPAIR SUGGESTIONS]
Recommended Command:
  dism /image:C:\ /cleanup-image /restorehealth

Would you like to execute this command? (Y/N):
```

---

## Best Practices

### Before Running Repairs
1. **Always run Analyze mode first**
2. **Check hardware diagnostics** - Don't repair software if hardware is failing
3. **Review blockers** - Clear registry blockers before attempting repairs
4. **Backup critical data** - Especially before DISM/SFC operations

### In Recovery Environment
1. **Auto-detect works** - System finds Windows partition automatically
2. **Use Full mode** - Get analysis and repair options
3. **Monitor logs** - Use Monitor mode during long operations
4. **Check disk health first** - Rule out hardware before software repair

### For Automation
```powershell
# Non-interactive analysis
$result = & pwsh -File "Helper\MiracleBootPro.ps1" -Mode Analyze
# Parse JSON output for automation
```

---

## Troubleshooting

### "Windows partition not detected"
**Solution**: Manually specify with `-TargetDrive "D"`

### "Registry access denied"
**Solution**: Run as Administrator or in WinPE/WinRE

### "Log file not found"
**Solution**: Normal if system hasn't failed yet. Run after a boot failure.

### "Monitor mode shows no output"
**Solution**: Log file may not be actively being written. Check if repair is actually running.

---

## Extending the System

### Adding New Error Codes

Edit `$Global:ErrorDB` in `MiracleBootPro.ps1`:

```powershell
"0xNEWERROR" = @{
    Description = "Your error description"
    Action = "Your repair action"
    Command = "your-command-here"
    Severity = "Critical" # or "High", "Medium", "Low"
    Stage = "Boot Loader" # or "Driver", "Kernel", etc.
}
```

### Adding New Registry Blockers

Add detection in `Test-RepairInstallBlockers`:

```powershell
# Check for your blocker
$yourBlocker = Get-ItemProperty -Path "HKLM:\Your\Path" -Name "YourKey" -ErrorAction SilentlyContinue
if ($yourBlocker) {
    $blockers += @{
        Type = "Your Blocker Name"
        Path = "HKLM:\Your\Path"
        Severity = "High"
        Fix = "Clear-YourBlocker"
    }
}
```

Add clearing logic in `Clear-AllBlockers`:

```powershell
"Your Blocker Name" {
    Remove-ItemProperty -Path "HKLM:\Your\Path" -Name "YourKey" -ErrorAction Stop
    Write-Host " [SUCCESS]" -ForegroundColor Green
    $cleared++
}
```

---

## Summary

MiracleBoot Pro provides:

✅ **Intelligent Analysis** - Knows what's wrong and how to fix it  
✅ **Automated Detection** - Finds Windows partition and errors automatically  
✅ **Direct Action** - Provides exact commands to fix issues  
✅ **Safety First** - Checks hardware before software repairs  
✅ **Real-Time Monitoring** - Watches logs as repairs happen  
✅ **Recovery Ready** - Works in all Windows environments  

**This is the "Take My Money" level of reliability and speed.**

