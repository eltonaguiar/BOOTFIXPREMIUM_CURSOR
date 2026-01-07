# Miracle Boot v7.2.0 - Advanced Windows Recovery Tool

## 🎯 What is Miracle Boot?

**Miracle Boot** is a comprehensive Windows boot repair and recovery tool designed to fix broken Windows operating systems. Whether your Windows won't boot, needs repair, or requires an in-place upgrade, Miracle Boot provides the tools and diagnostics needed to get your system back up and running.

### Primary Goals:
- **Fix broken Windows operating systems** - Repair corrupted system files, boot configurations, and registry issues
- **Enable in-place repairs** - Prepare your system for Windows repair installations that preserve your apps and data
- **Fix Windows boot issues** - Diagnose and repair boot failures, missing boot files, and BCD corruption

---

## 🖥️ Where Can You Use Miracle Boot?

Miracle Boot works in **multiple Windows environments**, automatically detecting your environment and providing the appropriate interface:

### ✅ **Windows 10/11 (FullOS) - Normal Windows Desktop**
**When to use:** Your Windows is running but has boot issues, or you want to perform diagnostics and repairs while Windows is operational.

**How to launch:**
- Double-click `RunMiracleBoot.cmd`
- Or run: `powershell.exe -ExecutionPolicy Bypass -File MiracleBoot.ps1`

**Interface:** Modern WPF GUI with full visual interface, tabs, buttons, and real-time feedback.

**Best for:**
- Diagnosing boot problems before they become critical
- Managing boot configurations (BCD)
- Performing system health checks
- Preparing for in-place upgrades

---

### ✅ **Windows Recovery Environment (WinRE)**
**When to use:** Your Windows won't boot normally, but you can access Advanced Startup Options.

**How to access:**
1. Boot your computer
2. When Windows fails to start, you'll see "Preparing Automatic Repair"
3. Go to **Advanced Options** → **Troubleshoot** → **Command Prompt**
4. Navigate to your Miracle Boot folder
5. Run: `RunMiracleBoot.cmd`

**Interface:** Text-based menu (MS-DOS Style) - all features available via keyboard navigation.

**Best for:**
- Repairing non-booting systems
- Recovering from boot failures
- Fixing boot configuration issues
- Accessing system when Windows won't start

---

### ✅ **Windows Preinstallation Environment (WinPE)**
**When to use:** Your system won't boot at all, or you need to repair from external media.

**How to access:**
1. Boot from WinPE USB/DVD (Hiren's BootCD PE, Sergei Strelec's WinPE, or custom WinPE)
2. Navigate to your Miracle Boot folder (on USB or network)
3. Run: `RunMiracleBoot.cmd`

**Interface:** Text-based menu (MS-DOS Style) - optimized for minimal environments.

**Best for:**
- Repairing systems that won't boot
- Offline repairs (when Windows installation is on another drive)
- Driver injection for missing storage drivers
- Complete system diagnostics from external media

**Special Features:**
- Option to install portable Chrome/Firefox browser for web access
- Network support for downloading drivers and tools
- Full offline repair capabilities

---

### ✅ **Windows Installation Environment (Shift+F10)**
**When to use:** During Windows installation when setup fails or you need to fix installation issues.

**How to access:**
1. Start Windows installation from USB/DVD
2. When installation screen appears, press **Shift+F10** to open command prompt
3. Navigate to your Miracle Boot folder (on USB)
4. Run: `RunMiracleBoot.cmd`

**Interface:** Text-based menu (MS-DOS Style) - limited environment but full repair capabilities.

**Best for:**
- Fixing Windows installation failures
- Enabling network during installation
- Diagnosing installation issues
- Preparing system for successful installation

**Note:** Browser installation not available in Shift+F10 environment (limited Windows Setup environment).

---

## 🚀 Quick Start Guide

### Step 1: Download and Extract
1. Download Miracle Boot
2. Extract all files to a folder (e.g., `C:\MiracleBoot` or `D:\MiracleBoot`)
3. **Important:** Keep all `.ps1` and `.cmd` files together in the same folder

### Step 2: Choose Your Environment

#### **If Windows is Running:**
```cmd
RunMiracleBoot.cmd
```
You'll see a modern GUI with tabs and buttons.

#### **If Windows Won't Boot:**
1. Boot into WinRE (Advanced Startup Options) or WinPE (bootable USB)
2. Open Command Prompt
3. Navigate to Miracle Boot folder
4. Run: `RunMiracleBoot.cmd`
5. You'll see a text-based menu - use number/letter keys to navigate

---

## 📋 Key Capabilities

### 🔧 Boot Repair
- Rebuild Boot Configuration Data (BCD)
- Fix boot files and boot sector
- Scan for Windows installations
- Repair boot menu entries
- Fix duplicate boot entries

### 🔍 System Diagnostics
- **Boot Probability Check** - Assess likelihood of successful boot (0-100%)
- **Boot Health Analysis** - Identify boot chain failure points
- **Comprehensive Diagnostics** - Full system health check
- **In-Place Upgrade Readiness** - Check if system can perform repair installation
- **Boot Log Analysis** - View startup/boot logs to see where boot chain fails

### 💾 Driver Management
- Detect missing storage drivers
- Scan for driver errors
- Inject drivers offline into Windows installations
- Driver forensics from system logs
- Export drivers for backup

### 📝 BCD Management
- Visual BCD editor (GUI) or text-based editor (TUI)
- Edit boot entry properties
- Set default boot entry
- Fix duplicate entries
- Sync BCD to all EFI partitions

### 🛠️ System File Repair
- **SFC (System File Checker)** - Scan and repair corrupted system files
- **DISM** - Repair Windows component store
- Offline repair support (from WinPE/WinRE)
- Automated repair workflows

### 💿 Disk Repair
- **CHKDSK** integration
- Bad sector recovery
- File system repair
- Disk health checks

### 🔄 In-Place Upgrade
- Force repair-only Windows installation
- Preserve apps and data
- Online and offline modes
- Registry override for compatibility

### 🌐 Network Support
- Enable network/internet in WinRE/WinPE
- WiFi support
- Internet connectivity testing
- Browser installation (WinPE only)

### 📊 Log Analysis
- Boot log (nbtlog.txt) analysis
- Event log analysis
- Setup log analysis
- Driver forensics
- Failure reason detection

---

## 🛠️ Text-Based Interface (TUI) - MS-DOS Style Mode

When running in WinPE, WinRE, or Shift+F10, you'll see a menu like this:

```
═══════════════════════════════════════════════════════════
  MIRACLE BOOT v7.2.0 - MS-DOS STYLE MODE
  Environment: WinRE / WinPE / FullOS
═══════════════════════════════════════════════════════════

1) List Windows Volumes (Sorted)
2) Scan Storage Drivers (Detailed)
3) Inject Drivers Offline (DISM)
4) Quick View BCD
5) Edit BCD Entry
6) Enable Network/Internet
7) Open ChatGPT Help (Browser/CLI)
8) Check Windows Install Failure Reasons
9) Boot Repair (with warnings)
A) Advanced Diagnostics
B) Boot Probability / Boot Health Check
C) Automated Boot Repair
D) System File Repair (SFC + DISM)
E) Disk Repair (chkdsk)
F) Comprehensive Diagnostics
G) Complete System Repair
H) In-Place Upgrade Readiness Check
I) Boot Log Analysis (View Startup/Boot Logs)
J) Utilities Menu (Notepad, Registry, PowerShell, etc.)
Q) Quit
```

**Navigation:**
- Type the number or letter (e.g., `1`, `B`, `I`) and press Enter
- Type `Q` to quit
- Press any key when prompted to continue

**All GUI features are available in TUI mode** - just navigate through menus instead of clicking buttons.

---

## 📊 GUI Interface Overview (FullOS Only)

When running in Windows 10/11, Miracle Boot provides a modern GUI with 8 tabs:

### 📊 Tab 1: Volumes & Health
View all Windows volumes with health status, drive letters, and file systems.

### ⚙️ Tab 2: BCD Editor
Visual Boot Configuration Data editor with basic and advanced property editing.

### 🖥️ Tab 3: Boot Menu Simulator
Preview how your boot menu will appear at startup.

### 🔧 Tab 4: Driver Diagnostics
Detect, scan, and manage missing or problematic drivers.

### 🔨 Tab 5: Boot Fixer
Automated and manual boot repair operations with test mode.

### 🔍 Tab 6: Diagnostics
System health checks, System Restore status, WinRE health, OS information.

### 📝 Tab 7: Diagnostics & Logs
Advanced log analysis, driver forensics, registry tools, in-place upgrade readiness.

### 🔄 Tab 8: Repair Install Forcer
Force Windows to perform a repair-only in-place upgrade from ISO.

---

## 🆕 New Features in v7.2.0

### Boot Chain Failure Analysis
- **View Startup/Boot Logs** - See exactly where in the boot chain Windows is failing
- **Boot Chain Stage Identification** - Identifies failure at BIOS/UEFI, bootloader, kernel, or driver stage
- **Detailed Failure Reasons** - Explains why each stage failed
- **Actionable Recommendations** - Provides specific steps to fix identified issues

### Enhanced WinPE/Shift+F10 Support
- **Utilities Menu** - Quick access to Notepad, Registry Editor, PowerShell, System Restore
- **Browser Installation** (WinPE only) - Install portable Chrome or Firefox for web access
- **Improved Boot Log Analysis** - Better visualization of boot chain failures

### Boot Probability Assessment
- Calculate boot success probability (0-100%)
- Identify critical issues preventing boot
- Health status indicators (Excellent, Good, Fair, Poor, Critical)

### In-Place Upgrade Readiness
- Comprehensive analysis of system readiness
- Identifies blockers preventing in-place upgrade
- Analyzes CBS logs, component store, registry, setup logs

---

## ⚠️ Important Notes

### Administrator Rights
Most operations require administrator privileges. Always run as administrator.

### Backups
- Always backup BCD before making changes
- Tool can create automatic backups before repairs
- System Restore points recommended before major repairs

### BitLocker
If BitLocker is enabled, ensure you have recovery keys before performing repairs.

### Test Mode
Boot Fixer tab runs in Test Mode by default - uncheck to apply fixes.

### Data Safety
Most operations are non-destructive, but always verify target drives before proceeding.

---

## 🔍 Understanding Boot Chain Failures

### Windows Boot Process Stages:

1. **BIOS/UEFI Initialization** - Hardware detection and initialization
2. **Boot Manager** - Windows Boot Manager (bootmgr) loads
3. **Boot Loader** - winload.exe loads the Windows kernel
4. **Kernel Initialization** - Windows kernel (ntoskrnl.exe) starts
5. **Driver Loading** - System drivers load in phases
6. **Session Manager** - smss.exe starts user sessions
7. **Windows Logon** - winlogon.exe and services start

### Common Failure Points:

- **Stage 1-2:** Missing or corrupted boot files, BCD corruption
- **Stage 3:** Corrupted winload.exe or kernel files
- **Stage 4:** Kernel corruption, missing hal.dll
- **Stage 5:** Missing storage drivers, driver corruption
- **Stage 6-7:** Corrupted system files, registry issues

### How Miracle Boot Helps:

- **Boot Log Analysis** - Shows which drivers/services failed to load
- **Boot Chain Diagnostics** - Identifies exact failure stage
- **Boot Probability** - Assesses overall boot health
- **Automated Repair** - Fixes common boot issues automatically

---

## 📦 Project Structure

```
MiracleBoot_v7_1_1/
├── MiracleBoot.ps1          # Main launcher (detects environment, loads interface)
├── RunMiracleBoot.cmd        # Batch launcher (compatible with all environments)
├── README.md                 # This file
├── Helper/                   # Helper scripts and modules
│   ├── WinRepairCore.ps1    # Core functions and repair operations
│   ├── WinRepairGUI.ps1     # GUI interface (WPF) for FullOS
│   ├── WinRepairTUI.ps1     # Text-based interface for WinPE/WinRE
│   ├── WinRepairCore.cmd    # CMD fallback functions
│   └── FixWinRepairCore.ps1 # Additional repair functions
└── Test/                     # Testing scripts and documentation
```

---

## 🔗 Compatibility

- **Windows 11** (All editions)
- **Windows 10** (All editions)
- **Windows Server 2016/2019/2022**
- **Windows PE 10/11**
- **Windows RE 10/11**

---

## 📄 License

This project is provided as-is for educational and recovery purposes.

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome!

---

## 📞 Support

For issues, questions, or contributions, please open an issue on the GitHub repository.

---

**Miracle Boot v7.2.0** - *Your comprehensive Windows recovery solution*
