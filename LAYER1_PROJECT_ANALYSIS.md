# LAYER 1 - PROJECT STRUCTURE ANALYSIS

## 1. FULL PROJECT FILE TREE

### Entry Points
- `RunMiracleBoot.cmd` - Batch launcher (Windows CMD)
- `MiracleBoot.ps1` - PowerShell entry orchestrator

### Core Modules
- `Helper\WinRepairCore.ps1` - Core engine (PowerShell 5.1+)
- `Helper\WinRepairGUI.ps1` - GUI module (PowerShell 5.1+, WPF)
- `Helper\WinRepairTUI.ps1` - Text UI module (PowerShell 5.1+)
- `Helper\EmergencyRepair.ps1` - Emergency fallback (PowerShell 5.1+)

### Supporting Modules
- `Helper\PreLaunchValidation.ps1` - Syntax validation
- `Helper\ErrorLogging.ps1` - Error handling
- `Helper\NetworkDiagnostics.ps1` - Network utilities
- `Helper\LogAnalysis.ps1` - Log analysis
- `Helper\KeyboardSymbols.ps1` - UI helpers
- `Helper\RepairReportGenerator.ps1` - Report generation
- `Helper\AdvancedBootTroubleshooting.ps1` - Advanced diagnostics
- `Helper\ReadinessGate.ps1` - Pre-launch validation
- `Helper\GUIFailureDiagnostics.ps1` - GUI error diagnostics

## 2. EXECUTION ORDER

### Primary Flow (FullOS with WPF):
1. `RunMiracleBoot.cmd` → launches `MiracleBoot.ps1`
2. `MiracleBoot.ps1` → detects environment → loads `WinRepairCore.ps1`
3. `MiracleBoot.ps1` → loads `WinRepairGUI.ps1` → calls `Start-GUI`
4. `WinRepairGUI.ps1` → defines GUI → launches WPF window

### Fallback Flow (WinRE/No WPF):
1. `RunMiracleBoot.cmd` → launches `MiracleBoot.ps1`
2. `MiracleBoot.ps1` → detects environment → loads `WinRepairCore.ps1`
3. `MiracleBoot.ps1` → loads `WinRepairTUI.ps1` → calls `Start-TUI`

### Emergency Flow (Syntax Errors):
1. `RunMiracleBoot.cmd` → launches `MiracleBoot.ps1`
2. `MiracleBoot.ps1` → fails to load GUI/TUI → loads `EmergencyRepair.ps1`
3. `EmergencyRepair.ps1` → calls `Start-EmergencyRepair`

## 3. ENTRY POINTS

### Main Entry Points:
1. **`RunMiracleBoot.cmd`** (Batch script)
   - Language: Windows CMD/Batch
   - Interpreter: cmd.exe
   - Purpose: Primary launcher, handles safety interlock

2. **`MiracleBoot.ps1`** (PowerShell script)
   - Language: PowerShell
   - Interpreter: powershell.exe (5.1+) or pwsh.exe (7+)
   - Purpose: Environment detection, module loading, experience selection

### Secondary Entry Points:
3. **`Helper\WinRepairGUI.ps1`** (PowerShell script)
   - Language: PowerShell with WPF
   - Interpreter: powershell.exe (5.1+) with PresentationFramework
   - Purpose: GUI definition and launch

4. **`Helper\WinRepairTUI.ps1`** (PowerShell script)
   - Language: PowerShell
   - Interpreter: powershell.exe (5.1+) or pwsh.exe (7+)
   - Purpose: Text-based UI for WinRE/limited environments

5. **`Helper\EmergencyRepair.ps1`** (PowerShell script)
   - Language: PowerShell
   - Interpreter: powershell.exe (5.1+) or pwsh.exe (7+)
   - Purpose: Emergency boot repair when main modules fail

## 4. LANGUAGE + INTERPRETER VERSION PER FILE

### Batch Files:
- `RunMiracleBoot.cmd` - Windows CMD (cmd.exe, all Windows versions)
- `Helper\WinRepairCore.cmd` - Windows CMD (cmd.exe, all Windows versions)

### PowerShell Files (All require PowerShell 5.1+ or PowerShell 7+):
- `MiracleBoot.ps1` - PowerShell 5.1+ (Windows PowerShell) or 7+ (PowerShell Core)
- `Helper\WinRepairCore.ps1` - PowerShell 5.1+ or 7+
- `Helper\WinRepairGUI.ps1` - PowerShell 5.1+ (WPF requires .NET Framework, Windows only)
- `Helper\WinRepairTUI.ps1` - PowerShell 5.1+ or 7+
- `Helper\EmergencyRepair.ps1` - PowerShell 5.1+ or 7+
- `Helper\PreLaunchValidation.ps1` - PowerShell 5.1+ or 7+
- `Helper\ErrorLogging.ps1` - PowerShell 5.1+ or 7+
- `Helper\NetworkDiagnostics.ps1` - PowerShell 5.1+ or 7+
- `Helper\LogAnalysis.ps1` - PowerShell 5.1+ or 7+
- `Helper\KeyboardSymbols.ps1` - PowerShell 5.1+ or 7+
- `Helper\RepairReportGenerator.ps1` - PowerShell 5.1+ or 7+
- `Helper\AdvancedBootTroubleshooting.ps1` - PowerShell 5.1+ or 7+
- `Helper\ReadinessGate.ps1` - PowerShell 5.1+ or 7+
- `Helper\GUIFailureDiagnostics.ps1` - PowerShell 5.1+ or 7+

## 5. CRITICAL DEPENDENCIES

### WPF Requirements (GUI only):
- .NET Framework 4.5+ (Windows PowerShell 5.1)
- PresentationFramework assembly
- Windows OS (not available on Linux/Mac)

### Common Requirements:
- Administrator privileges (for boot repair operations)
- Access to System32, EFI partition, BCD store

## 6. FILES THAT CANNOT BE CONFIDENTLY PARSED

**NONE** - All files are standard PowerShell or Batch scripts with clear syntax.
