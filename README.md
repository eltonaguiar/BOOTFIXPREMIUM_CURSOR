<<<<<<< HEAD
# Miracle Boot v7.2.0 - Advanced Windows Recovery Tool

## 🎯 Purpose

**Miracle Boot** is a comprehensive Windows boot repair and recovery tool designed to diagnose and fix boot issues, repair system files, manage boot configurations, and perform advanced recovery operations. It provides both a modern GUI interface (for FullOS) and a text-based TUI interface (for WinPE/WinRE environments).

### Key Capabilities:
- **Boot Repair**: Rebuild BCD, fix boot files, scan for Windows installations
- **System Diagnostics**: Comprehensive health checks, boot probability analysis, failure reason detection
- **Driver Management**: Detect missing drivers, inject drivers offline, perform driver forensics
- **BCD Management**: Visual BCD editor with advanced property editing
- **System File Repair**: SFC and DISM integration for offline repair
- **Disk Repair**: CHKDSK integration with bad sector recovery
- **In-Place Upgrade**: Force repair-only Windows installation from ISO
- **Network Support**: Enable network/internet in WinRE/WinPE environments

---

## 🖥️ Supported Environments

Miracle Boot is designed to run in multiple Windows environments:

### ✅ **Windows 11/10 (FullOS)**
- **Launch**: Run `RunMiracleBoot.cmd` or `MiracleBoot.ps1` directly
- **Interface**: Modern WPF GUI with full feature set
- **Use Case**: Repair boot issues, manage BCD, perform diagnostics while Windows is running

### ✅ **Windows Recovery Environment (WinRE)**
- **Launch**: Access via **Advanced Startup Options** → **Troubleshoot** → **Command Prompt**
- **Interface**: MS-DOS Style TUI (Text User Interface)
- **Use Case**: Repair non-booting systems, recover from boot failures

### ✅ **Windows Preinstallation Environment (WinPE)**
- **Launch**: Boot from WinPE media and run `RunMiracleBoot.cmd`
- **Interface**: MS-DOS Style TUI
- **Use Case**: Repair systems that won't boot, perform offline repairs

### ✅ **Windows Installation Environment (Shift+F10)**
- **Launch**: During Windows installation, press **Shift+F10** to open command prompt, then run `RunMiracleBoot.cmd`
- **Interface**: MS-DOS Style TUI
- **Use Case**: Fix installation failures, enable network, diagnose installation issues

---

## 📋 GUI Interface Overview

When running in FullOS (Windows 11/10), Miracle Boot launches a modern WPF GUI with the following tabs:

---

### 📊 **Tab 1: Volumes & Health**

**Purpose**: Display and monitor all Windows volumes with health status

**Features**:
- **Volume List**: Shows all detected drives with:
  - Drive letter
  - File system label
  - Total size
  - Health status (Healthy, Warning, Error)
- **Refresh Button**: Updates volume list in real-time
- **Health Monitoring**: Visual indicators for volume health

**Use Cases**:
- Identify which drives contain Windows installations
- Check disk health before performing repairs
- Locate system and recovery partitions

---

### ⚙️ **Tab 2: BCD Editor**

**Purpose**: Visual Boot Configuration Data (BCD) editor with advanced management capabilities

#### **Sub-tab 2.1: Basic Editor**
- **BCD Entry List**: Displays all boot entries with:
  - Entry description/name
  - GUID identifier
  - Default boot indicator (highlighted in green)
- **Edit Selected Entry**:
  - Modify description/friendly name
  - Set as default boot entry
  - Configure boot timeout (seconds)
- **Quick Actions**:
  - Load/Refresh BCD entries
  - Create BCD backup
  - Fix duplicate entries
  - Sync BCD to all EFI partitions
  - Run boot diagnosis

#### **Sub-tab 2.2: Advanced Properties**
- **Property Grid**: Edit all BCD properties for selected entry
- **Direct Editing**: Modify any BCD property value
- **Save/Reset**: Apply changes or revert to original values

**Use Cases**:
- Fix boot menu entries
- Remove duplicate boot entries
- Change default boot OS
- Modify boot parameters
- Troubleshoot boot configuration issues

---

### 🖥️ **Tab 3: Boot Menu Simulator**

**Purpose**: Visual preview of how the Windows Boot Manager will appear

**Features**:
- **Boot Menu Preview**: Shows boot entries as they will appear at startup
- **Timeout Display**: Shows countdown timer (default: 30 seconds)
- **Visual Styling**: Matches Windows Boot Manager appearance (blue background, white text)

**Use Cases**:
- Preview boot menu before rebooting
- Verify boot entry names and order
- Test boot menu appearance

---

### 🔧 **Tab 4: Driver Diagnostics**

**Purpose**: Detect, scan, and manage missing or problematic drivers

**Features**:
- **Scan for Driver Errors**: Identifies drivers with issues
- **Scan for Missing Drivers**: Detects required but missing drivers
- **Scan All Drivers**: Comprehensive driver inventory
- **Driver Installation**: Inject drivers into offline Windows installations
- **Drive Selection**: Choose target Windows drive for driver operations
- **Detailed Output**: Shows driver status, INF files, and recommendations

**Use Cases**:
- Fix "inaccessible boot device" errors
- Resolve missing storage driver issues
- Prepare drivers for offline injection
- Diagnose driver-related boot failures

---

### 🔨 **Tab 5: Boot Fixer**

**Purpose**: Automated and manual boot repair operations

**Features**:
- **Test Mode**: Preview commands without executing (enabled by default)
- **Boot Repair Operations**:
  1. **Rebuild BCD from Windows Installation** (bcdboot)
  2. **Fix Boot Files** (bootrec /fixboot)
  3. **Scan for Windows Installations** (bootrec /scanos)
  4. **Rebuild BCD** (bootrec /rebuildbcd)
  5. **Set Default Boot Entry**
  6. **Boot Diagnosis** (comprehensive analysis)
- **Command Output**: Real-time display of repair operations
- **Safety Features**: Test mode prevents accidental changes

**Use Cases**:
- Fix "Boot Configuration Data file is missing" errors
- Recover from boot sector corruption
- Rebuild boot configuration after disk cloning
- Restore boot functionality after system changes

---

### 🔍 **Tab 6: Diagnostics**

**Purpose**: System health checks and diagnostic information

**Features**:
- **Target Drive Selection**: Choose Windows drive to analyze
- **Diagnostic Tools**:
  - **Check System Restore**: View restore points and status
  - **Check Reagentc Health**: Verify Windows Recovery Environment
  - **Get OS Information**: Display Windows version, build, edition
  - **Install Failure Analysis**: Analyze Windows installation failure logs
- **Output Display**: Detailed diagnostic reports

**Use Cases**:
- Check if System Restore is available
- Verify WinRE functionality
- Identify Windows version and edition
- Diagnose installation failures
- Assess system recovery options

---

### 📝 **Tab 7: Diagnostics & Logs**

**Purpose**: Advanced log analysis and forensic diagnostics

**Features**:
- **Log Analysis Tools**:
  - **Driver Forensics**: Identify missing storage drivers from logs
  - **Analyze Boot Log**: Parse boot log files for errors
  - **Analyze Event Logs**: Review Windows Event Logs for issues
  - **Full Boot Diagnosis**: Comprehensive boot health check
  - **Hardware Support**: Manufacturer links and driver update alerts
- **Registry Tools**:
  - **Generate Registry Override Script**: Create scripts to fix registry issues
  - **One-Click Registry Fixes**: Apply common registry repairs
- **Advanced Features**:
  - **Filter Driver Forensics**: Focused driver analysis
  - **Export In-Use Drivers**: Extract currently loaded drivers
  - **Generate Cleanup Script**: Create cleanup automation
  - **In-Place Upgrade Readiness**: Check if system can perform in-place upgrade
  - **Recommended Tools**: Suggest third-party repair tools
  - **Unofficial Repair Tips**: Advanced troubleshooting suggestions

**Use Cases**:
- Analyze boot failures from logs
- Identify missing drivers from system logs
- Fix registry corruption issues
- Prepare for in-place upgrade
- Get manufacturer-specific driver links
- Export drivers for backup/transfer

---

### 🔄 **Tab 8: Repair Install Forcer**

**Purpose**: Force Windows to perform a repair-only in-place upgrade

**Features**:
- **Mode Selection**:
  - **Online Mode**: Run from within Windows (recommended)
  - **Offline Mode**: Run from WinPE/WinRE for non-booting systems
- **ISO Selection**: Browse and select Windows installation ISO
- **Options**:
  - Skip compatibility checks
  - Disable Dynamic Update
  - Force edition alignment
- **Prerequisites Check**: Verify system readiness before starting
- **Instructions**: Step-by-step guidance
- **Status Output**: Real-time progress and results

**Use Cases**:
- Repair Windows without losing apps/data
- Fix system file corruption
- Restore Windows functionality
- Perform clean repair installation

---

## 🛠️ TUI Interface (MS-DOS Style Mode)

When running in WinPE/WinRE or when GUI is unavailable, Miracle Boot provides a text-based menu:

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
Q) Quit
```

**All GUI features are available in TUI mode** with menu-driven navigation.

---

## 🚀 Quick Start

### Installation
1. Download or clone this repository
2. Extract all files to a folder (e.g., `C:\MiracleBoot`)
3. Ensure all `.ps1` and `.cmd` files are in the same directory

### Running in FullOS (Windows 11/10)
```cmd
RunMiracleBoot.cmd
```
or
```powershell
powershell.exe -ExecutionPolicy Bypass -File MiracleBoot.ps1
```

### Running in WinRE/WinPE/Shift+F10
1. Boot into recovery environment or press Shift+F10 during installation
2. Navigate to the Miracle Boot folder
3. Run:
```cmd
RunMiracleBoot.cmd
```

---

## ⚠️ Important Notes

- **Administrator Rights**: Most operations require administrator privileges
- **Backups**: Always backup BCD and important data before making changes
- **Test Mode**: Boot Fixer tab runs in Test Mode by default - uncheck to apply fixes
- **BitLocker**: Ensure you have recovery keys if BitLocker is enabled
- **Data Safety**: Most operations are non-destructive, but always verify target drives

---

## 📦 Project Structure

```
MiracleBoot_v7_1_1/
├── MiracleBoot.ps1          # Main launcher script (detects environment, loads appropriate interface)
├── RunMiracleBoot.cmd        # Batch launcher (compatible with all environments)
├── README.md                 # This file
├── Helper/                   # Helper scripts and modules
│   ├── WinRepairCore.ps1    # Core functions and repair operations
│   ├── WinRepairGUI.ps1     # GUI interface (WPF) for FullOS
│   ├── WinRepairTUI.ps1     # Text-based interface for WinPE/WinRE
│   ├── WinRepairCore.cmd    # CMD fallback functions
│   ├── FixWinRepairCore.ps1 # Additional repair functions
│   ├── VersionTracker.ps1   # Automatic backup branch creation (every 20 commits)
│   ├── EnsureMain.ps1      # Main branch synchronization and management
│   └── README.md            # Helper scripts documentation
├── Test/                     # Testing scripts and documentation
│   ├── Test-MiracleBoot.ps1
│   ├── test_new_features.ps1
│   └── TESTING_SUMMARY.md
└── workspace/                # Workspace configuration files
    └── MiracleBoot_v7_1_1.code-workspace
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
