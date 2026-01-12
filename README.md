# Miracle Boot v7.2.0 - Advanced Windows Recovery Tool

## 🎯 What is Miracle Boot?

**Miracle Boot** is a comprehensive Windows boot repair and recovery tool designed to fix broken Windows operating systems. Whether your Windows won't boot, needs repair, or requires an in-place upgrade, Miracle Boot provides the tools and diagnostics needed to get your system back up and running.

### Primary Goals:
- **Fix broken Windows operating systems** - Repair corrupted system files, boot configurations, and registry issues
- **Enable in-place repairs** - Prepare your system for Windows repair installations that preserve your apps and data
- **Fix Windows boot issues** - Diagnose and repair boot failures, missing boot files, and BCD corruption
- **Validate Windows installations** - Ensure boot repairs target real Windows installations, not just WinRE entries

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
4. **Enable Internet** (if needed - see `SHIFT_F10.txt` for commands)
5. **Download from GitHub** (if not already on USB):
   ```powershell
   cd D:\
   powershell -Command "$client = New-Object System.Net.WebClient; $client.DownloadFile('https://github.com/eltonaguiar/MiracleBoot_v7_1_1/archive/refs/heads/main.zip', 'D:\MiracleBoot.zip'); Expand-Archive -Path 'D:\MiracleBoot.zip' -DestinationPath 'D:\' -Force"
   cd D:\MiracleBoot_v7_1_1-main
   ```
6. Run: `RunMiracleBoot.cmd`

**Interface:** Text-based menu (MS-DOS Style) - all features available via keyboard navigation.

**Best for:**
- Repairing non-booting systems
- Recovering from boot failures
- Fixing boot configuration issues
- Accessing system when Windows won't start

**Quick Internet Fix in WinRE:**
If internet doesn't work, run these commands first:
```cmd
netsh interface show interface
netsh interface set interface name="Ethernet" admin=enable
netsh interface ip set address name="Ethernet" dhcp
netsh interface ip set dns name="Ethernet" static 8.8.8.8
ping 8.8.8.8
```
See `SHIFT_F10.txt` for complete network troubleshooting guide.

---

### ✅ **Windows Preinstallation Environment (WinPE)**
**When to use:** Your system won't boot at all, or you need to repair from external media.

**How to access:**
1. Boot from WinPE USB/DVD (Hiren's BootCD PE, Sergei Strelec's WinPE, or custom WinPE)
2. **Enable Internet** (if needed - see `SHIFT_F10.txt` for commands):
   ```cmd
   netsh interface show interface
   netsh interface set interface name="Ethernet" admin=enable
   netsh interface ip set address name="Ethernet" dhcp
   netsh interface ip set dns name="Ethernet" static 8.8.8.8
   ping 8.8.8.8
   ```
3. **Download from GitHub** (if not already on USB):
   ```powershell
   cd D:\
   powershell -Command "$client = New-Object System.Net.WebClient; $client.DownloadFile('https://github.com/eltonaguiar/MiracleBoot_v7_1_1/archive/refs/heads/main.zip', 'D:\MiracleBoot.zip'); Expand-Archive -Path 'D:\MiracleBoot.zip' -DestinationPath 'D:\' -Force"
   cd D:\MiracleBoot_v7_1_1-main
   ```
4. Run: `RunMiracleBoot.cmd`

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
- **GitHub download support** - Download directly in WinPE if internet is enabled

**Note:** If internet doesn't work in WinPE, download on another device and copy via USB (see `SHIFT_F10.txt` Section 2, Option C).

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

## ⚡ Quick Start Guide

### Step 1: Download and Extract
1. Download Miracle Boot from GitHub
2. Extract all files to a folder (e.g., `C:\MiracleBoot` or `D:\MiracleBoot`)
3. **Important:** Keep all `.ps1` and `.cmd` files together in the same folder

### Step 2: Choose Your Environment

#### **⚡ Quick Way to Run the GUI (Windows Desktop):**
```cmd
# Method 1: Double-click (Easiest)
RunMiracleBoot.cmd

# Method 2: PowerShell
powershell -ExecutionPolicy Bypass -File .\MiracleBoot.ps1

# Method 3: Direct GUI Launch
powershell -ExecutionPolicy Bypass -File .\Helper\WinRepairGUI.ps1
```
You'll see a modern GUI with tabs and buttons.

#### **⚡ Quick Way to Run Emergency Fix (CMD Version):**
For quick boot repair without GUI (works in WinRE/WinPE/CMD):
```cmd
# Recommended: Emergency Boot 4 (Smart Minimal)
EMERGENCY_BOOT4.cmd

# Other options:
EMERGENCY_BOOT1.cmd    # Ultra-simple boot repair
EMERGENCY_BOOT2.cmd    # Advanced boot repair
EMERGENCY_BOOT3.cmd    # Comprehensive boot repair
FIX_BCD_NOT_FOUND.cmd  # Targeted fix for missing BCD
```
These scripts run in separate Command Prompt windows and provide step-by-step repair processes with detailed error reporting.

#### **If Windows Won't Boot:**
1. Boot into WinRE (Advanced Startup Options) or WinPE (bootable USB)
2. Open Command Prompt
3. Navigate to Miracle Boot folder
4. Run: `RunMiracleBoot.cmd` (for GUI/TUI) or `EMERGENCY_BOOT4.cmd` (for quick fix)
5. You'll see a text-based menu - use number/letter keys to navigate

---

## 📋 Detailed Feature List

### 🔧 Boot Repair Functions

#### **One-Click Repair**
- **Automated Boot Repair** - Attempts multiple repair strategies automatically
- **Sequential Repair** - Tries emergency scripts in sequence until one succeeds
- **Automatic Fallback** - If initial repair fails, automatically tries remaining fixes
- **Comprehensive Diagnostics** - Generates detailed reports if all repairs fail
- **Success Verification** - Validates that repairs actually fixed the boot issue

#### **Emergency Boot Repair Scripts**
- **EMERGENCY_BOOT1.cmd** - Ultra-simple boot repair for basic issues
- **EMERGENCY_BOOT2.cmd** - Advanced boot repair with Windows detection
- **EMERGENCY_BOOT3.cmd** - Comprehensive repair with all strategies (DISM, SFC, bcdboot, install.wim extraction)
- **EMERGENCY_BOOT4.cmd** - Smart minimal repair that only fixes what's broken
- **FIX_BCD_NOT_FOUND.cmd** - Targeted fix for missing BCD file

**All emergency scripts now include:**
- Detailed error reporting with exact failure reasons
- Progress percentage tracking
- Verification of repairs
- Specific solutions for each failure type
- Exit codes (0 = success, 1 = failure) for automation

#### **Boot Configuration Data (BCD) Management**
- **Rebuild BCD** - Recreate BCD from Windows installation
- **Edit BCD Entries** - Visual editor (GUI) or text-based editor (TUI)
- **Set Default Boot Entry** - Change which OS boots by default
- **Fix Duplicate Entries** - Remove or rename duplicate boot entries
- **Sync BCD** - Copy BCD to all EFI partitions
- **BCD Validation** - Verify BCD contains valid Windows installations (not just WinRE)
- **Windows Installation Validation** - Ensures boot repairs target real Windows installations

#### **Boot File Repair**
- **winload.efi/winload.exe** - Restore missing boot loaders
- **bootmgfw.efi** - Restore boot manager
- **BCD File** - Repair or recreate corrupted BCD
- **EFI Partition** - Mount and repair EFI System Partition

---

### 🔍 System Diagnostics Functions

#### **Boot Probability Assessment**
- **Boot Success Probability** - Calculate likelihood of successful boot (0-100%)
- **Health Status Indicators** - Excellent, Good, Fair, Poor, Critical
- **Critical Issue Identification** - Lists issues preventing boot
- **Actionable Recommendations** - Specific steps to improve boot probability

#### **Boot Health Analysis**
- **Boot Chain Stage Identification** - Identifies failure at BIOS/UEFI, bootloader, kernel, or driver stage
- **Detailed Failure Reasons** - Explains why each stage failed
- **Boot Chain Visualization** - Shows where in the boot process Windows fails

#### **Comprehensive Diagnostics**
- **Full System Health Check** - Complete analysis of boot components
- **Boot File Status** - Check all critical boot files
- **EFI Partition Status** - Verify EFI partition health
- **BCD Entry Validation** - Ensure BCD contains valid Windows installations
- **Windows Installation Verification** - Confirm target is a real Windows installation (not WinRE)

#### **Boot Log Analysis**
- **View Startup/Boot Logs** - See exactly where in the boot chain Windows is failing
- **Driver Failure Detection** - Identify which drivers failed to load
- **Service Failure Detection** - Identify which services failed to start
- **Boot Chain Failure Points** - Pinpoint exact failure stage

#### **In-Place Upgrade Readiness**
- **Comprehensive Analysis** - Check if system can perform repair installation
- **Blocker Identification** - Lists issues preventing in-place upgrade
- **CBS Log Analysis** - Analyze Component-Based Servicing logs
- **Component Store Health** - Check Windows component store integrity
- **Registry Analysis** - Verify registry health for upgrade

---

### 💾 Driver Management Functions

#### **Driver Detection**
- **Missing Storage Drivers** - Detect drivers needed for disk access
- **Driver Error Scanning** - Find problematic or corrupted drivers
- **Driver Forensics** - Analyze system logs for driver issues

#### **Driver Injection**
- **Offline Driver Injection** - Inject drivers into offline Windows installations using DISM
- **Driver Export** - Export drivers for backup
- **Driver Backup** - Create backups before driver operations

---

### 🛠️ System File Repair Functions

#### **SFC (System File Checker)**
- **Online SFC** - Scan and repair corrupted system files in running Windows
- **Offline SFC** - Repair system files in offline Windows installations
- **Automated Repair** - Run SFC with proper parameters automatically

#### **DISM (Deployment Image Servicing and Management)**
- **Component Store Repair** - Fix Windows component store corruption
- **Restore Health** - Restore Windows image health
- **Offline Repair** - Repair offline Windows installations
- **Install.wim/ESD Support** - Extract files from Windows installation media

---

### 💿 Disk Repair Functions

#### **CHKDSK Integration**
- **File System Repair** - Fix file system errors
- **Bad Sector Recovery** - Attempt to recover data from bad sectors
- **Disk Health Checks** - Verify disk integrity
- **Offline Disk Repair** - Repair disks from WinPE/WinRE

---

### 🔄 In-Place Upgrade Functions

#### **Repair Install Forcer**
- **Force Repair-Only Installation** - Make Windows perform repair installation instead of upgrade
- **Preserve Apps and Data** - Keep all user data and applications
- **Online and Offline Modes** - Works from running Windows or WinPE/WinRE
- **Registry Override** - Override compatibility checks for upgrade

---

### 🌐 Network Support Functions

#### **Network Enablement**
- **Enable Network in WinRE/WinPE** - Activate network adapters
- **WiFi Support** - Configure wireless networks
- **Internet Connectivity Testing** - Verify internet access
- **DNS Configuration** - Set up DNS servers for internet access

#### **Browser Installation (WinPE Only)**
- **Portable Chrome** - Install Chrome browser for web access
- **Portable Firefox** - Install Firefox browser for web access
- **Web-Based Help** - Access online help and documentation

---

### 📊 Log Analysis Functions

#### **Boot Log Analysis**
- **nbtlog.txt Analysis** - Parse Windows boot log
- **Driver Load Failures** - Identify drivers that failed to load
- **Service Start Failures** - Identify services that failed to start

#### **Event Log Analysis**
- **System Events** - Analyze system event logs
- **Application Events** - Analyze application event logs
- **Error Code Lookup** - Map error codes to specific issues

#### **Setup Log Analysis**
- **Windows Installation Logs** - Analyze setup logs for installation failures
- **Failure Reason Detection** - Identify why Windows installation failed
- **Component Store Logs** - Analyze CBS logs for component issues

---

### 🛡️ Safety and Validation Functions

#### **Windows Installation Validation**
- **Real Windows Detection** - Verify target is a real Windows installation (not WinRE)
- **Kernel Verification** - Check for ntoskrnl.exe (required for valid Windows)
- **BCD Entry Validation** - Ensure BCD entries point to real Windows installations
- **WinRE Filtering** - Automatically filter out WinRE-only entries

#### **Safety Guardrails**
- **Test Mode** - Preview changes before applying (default in Boot Fixer tab)
- **Backup Creation** - Automatic backups before critical operations
- **Confirmation Prompts** - Require explicit confirmation for destructive operations
- **IDE Detection** - Prevents accidental termination of development environments

#### **Error Reporting**
- **Detailed Failure Messages** - Exact reasons why repairs failed
- **Specific Solutions** - Actionable steps to fix each issue
- **Impact Analysis** - Explains what each failure means for boot
- **Comprehensive Diagnostics** - Full reports when repairs fail

---

## 📊 GUI Interface Overview (FullOS Only)

When running in Windows 10/11, Miracle Boot provides a modern GUI with 8 tabs:

### 📊 Tab 1: Volumes & Health
- View all Windows volumes with health status
- Drive letters and file systems
- Volume size and free space
- Health indicators

### ⚙️ Tab 2: BCD Editor
- Visual Boot Configuration Data editor
- Basic and advanced property editing
- Set default boot entry
- Edit boot entry descriptions
- Fix duplicate entries

### 🖥️ Tab 3: Boot Menu Simulator
- Preview how your boot menu will appear at startup
- See boot entry order
- Test boot menu appearance

### 🔧 Tab 4: Driver Diagnostics
- Detect missing storage drivers
- Scan for driver errors
- Driver forensics from logs
- Export drivers for backup

### 🔨 Tab 5: Boot Fixer (First Tab)
- **One-Click Repair** - Automated boot repair with automatic fallback
- **Emergency Boot Repair Scripts** - Quick access to all emergency scripts
- **Boot Repair Operations** - Manual repair options with scrolling support
- **Instructions Button** - Detailed guide for running in various environments
- **Test Mode** - Preview changes before applying (default enabled)

### 🔍 Tab 6: Diagnostics
- System health checks
- System Restore status
- WinRE health
- OS information
- Boot probability assessment

### 📝 Tab 7: Diagnostics & Logs
- Advanced log analysis
- Driver forensics
- Registry tools
- In-place upgrade readiness
- Precision detection and repair
- Boot log analysis

### 🔄 Tab 8: Repair Install Forcer
- Force Windows to perform repair-only in-place upgrade
- Select Windows ISO
- Configure upgrade options
- Monitor upgrade progress

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

## 🆕 Recent Improvements (v7.2.0)

### Windows Installation Validation
- **Real Windows Detection** - Validates that boot repairs target actual Windows installations
- **WinRE Filtering** - Automatically filters out Windows Recovery Environment entries
- **Kernel Verification** - Checks for ntoskrnl.exe to confirm valid Windows installation
- **BCD Entry Validation** - Ensures BCD contains entries for real Windows, not just WinRE

### Enhanced Emergency Boot Scripts
- **Detailed Error Reporting** - Exact failure reasons with specific solutions
- **Progress Tracking** - Percentage-based progress indicators
- **Verification** - Confirms repairs actually fixed issues
- **Exit Codes** - Proper exit codes (0 = success, 1 = failure) for automation
- **Failure Diagnostics** - Comprehensive reports when repairs fail

### Improved Boot Validation
- **Automatic Fallback** - If "Repair my PC" fails, automatically tries remaining fixes
- **Comprehensive Diagnostics** - Detailed reports explaining boot issues
- **Success Verification** - Validates that repairs actually worked
- **Clear Error Messages** - Specific reasons why fixes failed

### User Experience Improvements
- **Status Bar Notifications** - Shows "Closing..." when window is closing
- **Help Menu Enhancements** - Execution path viewer, log cleanup function
- **Instructions Button** - Detailed guide for running in various environments
- **Scrolling Support** - Boot Repair Operations section now scrolls for many buttons

### Safety Improvements
- **IDE Detection** - Prevents accidental termination of Cursor, VS Code, etc.
- **Process Safety** - Only targets actual GUI windows, not console/terminal processes
- **Test Mode Default** - Boot Fixer runs in test mode by default

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

### Windows Installation Validation
The tool now validates that boot repairs target real Windows installations. If only WinRE entries are found in BCD, the tool will report this and recommend creating proper Windows boot entries.

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
- **Windows Installation Validation** - Ensures repairs target real Windows installations

---

## 📁 Project Structure

```
MiracleBoot_v7_1_1/
├── MiracleBoot.ps1              # Main PowerShell entry point
├── RunMiracleBoot.cmd           # Main CMD entry point
├── README.md                    # This file
├── Helper/                       # Core modules
│   ├── WinRepairCore.ps1        # Core functions and repair operations
│   ├── WinRepairGUI.ps1         # GUI interface (WPF) for FullOS
│   ├── WinRepairTUI.ps1         # Text-based interface for WinPE/WinRE
│   ├── WinRepairCore.cmd        # CMD fallback functions
│   ├── EmergencyRepair.ps1      # Emergency repair functions
│   ├── ErrorLogging.ps1         # Centralized error logging
│   └── [Other helper modules]
├── EMERGENCY_BOOT1.cmd          # Ultra-simple boot repair
├── EMERGENCY_BOOT2.cmd          # Advanced boot repair
├── EMERGENCY_BOOT3.cmd          # Comprehensive boot repair
├── EMERGENCY_BOOT4.cmd          # Smart minimal boot repair
├── FIX_BCD_NOT_FOUND.cmd        # Targeted BCD fix
├── Test/                        # Testing scripts and documentation
└── DOCUMENTATION/                # Additional documentation
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
