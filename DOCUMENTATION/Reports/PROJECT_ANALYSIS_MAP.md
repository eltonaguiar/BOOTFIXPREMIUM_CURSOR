# PROJECT ANALYSIS MAP - MiracleBoot v7.1.1
**Senior Software Verification Engineer Analysis**
**Date:** 2026-01-09
**Status:** ANALYSIS PHASE - NO CODE MODIFICATIONS YET

## 1. FILE ENUMERATION

### 1.1 Execution Entry Points
| File | Type | Language | Version | Purpose |
|------|------|----------|---------|---------|
| `RunMiracleBoot.cmd` | CMD | Batch | Windows CMD | Primary launcher, checks PowerShell availability |
| `MiracleBoot.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | Main orchestrator, environment detection, UI selection |
| `MiracleBoot-Admin-Launcher.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | Auto-elevation wrapper |
| `Helper\WinRepairCore.cmd` | CMD | Batch | Windows CMD | Fallback CMD menu (no PowerShell) |

### 1.2 Core Engine Files
| File | Type | Language | Version | Dependencies |
|------|------|----------|---------|---------------|
| `Helper\WinRepairCore.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | None (core engine) |
| `Helper\ErrorLogging.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | None |
| `Helper\PreLaunchValidation.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | None |
| `Helper\ReadinessGate.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | PreLaunchValidation.ps1 |

### 1.3 UI Layer Files
| File | Type | Language | Version | Dependencies | Framework |
|------|------|----------|---------|---------------|-----------|
| `Helper\WinRepairGUI.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | WinRepairCore.ps1, ErrorLogging.ps1, LogAnalysis.ps1, NetworkDiagnostics.ps1 | WPF (PresentationFramework) |
| `Helper\WinRepairTUI.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | WinRepairCore.ps1, LogAnalysis.ps1 | Console (Read-Host) |

### 1.4 Helper/Utility Files
| File | Type | Language | Version | Dependencies |
|------|------|----------|---------|---------------|
| `Helper\NetworkDiagnostics.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | None |
| `Helper\LogAnalysis.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | None |
| `Helper\KeyboardSymbols.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | None |
| `Helper\XamlDefense.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | None |
| `Helper\BootRepairWizard.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | WinRepairCore.ps1 |
| `Helper\Check-Logs.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | None |
| `Helper\MiracleBootPro.ps1` | PowerShell | PS 5.1+ | Windows PowerShell | WinRepairCore.ps1 |

### 1.5 Test Files (47 PowerShell scripts)
- Located in `Test\` directory
- Various validation, integration, unit, GUI tests
- Not part of runtime execution flow

## 2. EXECUTION FLOW ANALYSIS

### 2.1 Primary Execution Path
```
RunMiracleBoot.cmd
  ├─> Check PowerShell availability
  │   ├─> If NO: Fallback to Helper\WinRepairCore.cmd
  │   └─> If YES: Continue
  ├─> Launch: powershell.exe -ExecutionPolicy Bypass -NoProfile -File MiracleBoot.ps1
  │
  └─> MiracleBoot.ps1
      ├─> Set-ExecutionPolicy Bypass (Process scope)
      ├─> Check STA mode (required for WPF)
      ├─> Load ErrorLogging.ps1
      ├─> Load PreLaunchValidation.ps1
      ├─> Run PreLaunchValidation (syntax check)
      ├─> Get-EnvironmentType (FullOS/WinRE/WinPE)
      ├─> Load WinRepairCore.ps1 (dot-source)
      │
      ├─> IF FullOS:
      │   ├─> Check WPF availability (PresentationFramework)
      │   ├─> Load ReadinessGate.ps1 (if exists)
      │   ├─> Run Test-ReadinessGate
      │   ├─> IF Ready:
      │   │   ├─> Load WinRepairGUI.ps1 (dot-source)
      │   │   └─> Call Start-GUI
      │   └─> IF Not Ready:
      │       ├─> Load WinRepairTUI.ps1 (dot-source)
      │       └─> Call Start-TUI
      │
      └─> IF WinRE/WinPE:
          ├─> Load WinRepairTUI.ps1 (dot-source)
          └─> Call Start-TUI
```

### 2.2 Dependency Graph
```
MiracleBoot.ps1
  ├─> ErrorLogging.ps1 (dot-source)
  ├─> PreLaunchValidation.ps1 (dot-source)
  ├─> WinRepairCore.ps1 (dot-source) [CRITICAL]
  ├─> ReadinessGate.ps1 (conditional dot-source)
  │   └─> PreLaunchValidation.ps1 (already loaded)
  ├─> WinRepairGUI.ps1 (conditional dot-source)
  │   ├─> ErrorLogging.ps1 (dot-source)
  │   ├─> WinRepairCore.ps1 (dot-source, re-loaded)
  │   ├─> LogAnalysis.ps1 (dot-source)
  │   └─> NetworkDiagnostics.ps1 (conditional dot-source)
  └─> WinRepairTUI.ps1 (conditional dot-source)
      └─> LogAnalysis.ps1 (dot-source)
```

## 3. OS ASSUMPTIONS

### 3.1 Operating System Requirements
- **Minimum**: Windows 10 (build 10240+) or Windows 11
- **Environments**: FullOS, WinRE, WinPE
- **Architecture**: x64 (primary), x86 (legacy support)
- **PowerShell**: Windows PowerShell 5.1+ (NOT PowerShell Core 6+)

### 3.2 Framework Dependencies
- **WPF**: PresentationFramework.dll (FullOS GUI only)
- **Windows Forms**: System.Windows.Forms.dll (GUI helper)
- **Visual Basic**: Microsoft.VisualBasic.dll (InputBox helper)
- **.NET Framework**: 4.5+ (implicit)

### 3.3 Drive Letter Assumptions
- **FullOS**: Typically C:\Windows
- **WinRE**: X: (RAM disk), target OS on C: or D:
- **WinPE**: X: (RAM disk), target OS variable
- **No Hardcoding**: Uses `$WindowsRoot` parameter, `Get-WindowsVolumes` function

## 4. GUI FRAMEWORK ASSUMPTIONS

### 4.1 WPF Requirements
- **Threading Model**: STA (Single Threaded Apartment) - CRITICAL
- **XAML**: Embedded in WinRepairGUI.ps1 as string (not separate .xaml file)
- **Window**: System.Windows.Window class
- **Controls**: Standard WPF controls (Button, TextBox, TabControl, etc.)

### 4.2 Async Patterns (GUI Non-Blocking)
- **Runspaces**: `[runspacefactory]::CreateRunspace()` for background operations
- **Jobs**: `Start-Job` for long-running tasks
- **Dispatcher**: `$W.Dispatcher.Invoke()` for thread-safe UI updates
- **DoEvents**: `[System.Windows.Forms.Application]::DoEvents()` for responsiveness
- **Heartbeat**: `Start-OperationWithHeartbeat` function for progress updates

## 5. CROSS-FILE DEPENDENCIES

### 5.1 Critical Dependencies (Must Exist)
1. `Helper\WinRepairCore.ps1` - Loaded by ALL execution paths
2. `Helper\ErrorLogging.ps1` - Loaded by main script and GUI
3. `Helper\PreLaunchValidation.ps1` - Loaded before any UI

### 5.2 Conditional Dependencies
1. `Helper\ReadinessGate.ps1` - Only for FullOS GUI path
2. `Helper\WinRepairGUI.ps1` - Only for FullOS with WPF
3. `Helper\WinRepairTUI.ps1` - Fallback for WinRE/WinPE or failed GUI
4. `Helper\NetworkDiagnostics.ps1` - Only if network features used
5. `Helper\LogAnalysis.ps1` - Only if log analysis features used

## 6. KNOWN SYNTAX ISSUES (PREVIOUSLY IDENTIFIED)

### 6.1 Fixed Issues
1. **Line 659 (WinRepairCore.ps1)**: Escaped quotes `exclusive=\"true\"` → `exclusive=true` ✅ FIXED
2. **Line 936 (WinRepairCore.ps1)**: Variable colon `$driveLetter:` → `${driveLetter}:` ✅ FIXED
3. **Line 940 (WinRepairCore.ps1)**: Variable colon `$driveLetter:` → `${driveLetter}:` ✅ FIXED

### 6.2 Pending Verification
- All files must pass parser validation
- No unclosed brackets
- No uninitialized variables in critical paths
- No hardcoded paths that fail in WinPE

## 7. EXECUTION ENVIRONMENT MAPPING

### 7.1 FullOS (Windows 10/11 Desktop)
- **SystemDrive**: C:
- **PowerShell**: Full .NET Framework available
- **WPF**: Available
- **Network**: Usually available
- **UI Path**: GUI (if WPF loads) → TUI (fallback)

### 7.2 WinRE (Recovery Environment)
- **SystemDrive**: X: (RAM disk)
- **PowerShell**: Limited .NET Framework
- **WPF**: NOT available
- **Network**: May be available (needs enabling)
- **UI Path**: TUI only

### 7.3 WinPE (Preinstallation Environment)
- **SystemDrive**: X: (RAM disk)
- **PowerShell**: Limited .NET Framework
- **WPF**: NOT available
- **Network**: May be available (needs enabling)
- **UI Path**: TUI only

## 8. PERMISSION REQUIREMENTS

### 8.1 Admin Rights
- **Required For**: BCD writes, registry modifications, system file repairs
- **Checked By**: `[Security.Principal.WindowsPrincipal]` in various functions
- **Elevation**: MiracleBoot-Admin-Launcher.ps1 provides auto-elevation

### 8.2 Execution Policy
- **Set By**: `Set-ExecutionPolicy Bypass -Scope Process` in MiracleBoot.ps1
- **Scope**: Process only (does not modify system policy)

## 9. NEXT STEPS (TEST PLAN DESIGN)

After this analysis, the test plan will cover:
1. Syntax & Parse Tests (every file)
2. Dependency Resolution Tests
3. Execution Flow Tests
4. GUI Stability Tests
5. User Interaction Tests
6. OS & Permission Tests

**STATUS: ANALYSIS COMPLETE - READY FOR TEST PLAN DESIGN**
