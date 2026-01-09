# LAYER 1 - PROJECT ANALYSIS (NO CODE GENERATION)
**Status**: ANALYSIS ONLY - NO MODIFICATIONS

## 1. FULL PROJECT FILE TREE

### Entry Points (Execution Start)
```
RunMiracleBoot.cmd                    [CMD/Batch]     Windows CMD
MiracleBoot.ps1                       [PowerShell]    Windows PowerShell 5.1+
MiracleBoot-Admin-Launcher.ps1       [PowerShell]    Windows PowerShell 5.1+
Helper\WinRepairCore.cmd              [CMD/Batch]     Windows CMD (fallback)
```

### Core Engine
```
Helper\WinRepairCore.ps1              [PowerShell]    Windows PowerShell 5.1+  [19,534 lines]
```

### UI Layers
```
Helper\WinRepairGUI.ps1               [PowerShell]    Windows PowerShell 5.1+  [WPF/XAML embedded]
Helper\WinRepairTUI.ps1               [PowerShell]    Windows PowerShell 5.1+  [Console/TUI]
```

### Helper Modules
```
Helper\ErrorLogging.ps1               [PowerShell]    Windows PowerShell 5.1+
Helper\PreLaunchValidation.ps1       [PowerShell]    Windows PowerShell 5.1+
Helper\ReadinessGate.ps1             [PowerShell]    Windows PowerShell 5.1+
Helper\NetworkDiagnostics.ps1         [PowerShell]    Windows PowerShell 5.1+
Helper\LogAnalysis.ps1                [PowerShell]    Windows PowerShell 5.1+
Helper\KeyboardSymbols.ps1             [PowerShell]    Windows PowerShell 5.1+
Helper\XamlDefense.ps1                [PowerShell]    Windows PowerShell 5.1+
Helper\BootRepairWizard.ps1           [PowerShell]    Windows PowerShell 5.1+
Helper\Check-Logs.ps1                 [PowerShell]    Windows PowerShell 5.1+
Helper\MiracleBootPro.ps1             [PowerShell]    Windows PowerShell 5.1+
```

### Test Files (47 PowerShell scripts - NOT runtime)
```
Test\*.ps1                            [PowerShell]    Windows PowerShell 5.1+
```

## 2. EXECUTION ORDER

### Primary Path (FullOS with PowerShell)
```
1. RunMiracleBoot.cmd
   └─> Check PowerShell availability
       └─> powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "& 'MiracleBoot.ps1'"
           └─> MiracleBoot.ps1
               ├─> Set-ExecutionPolicy Bypass (Process scope)
               ├─> Check STA mode (required for WPF)
               ├─> Load ErrorLogging.ps1 (dot-source)
               ├─> Load PreLaunchValidation.ps1 (dot-source)
               ├─> Run Test-PreLaunchValidation (syntax check)
               ├─> Get-EnvironmentType (FullOS/WinRE/WinPE)
               ├─> Load WinRepairCore.ps1 (dot-source) [CRITICAL]
               │
               ├─> IF FullOS:
               │   ├─> Check WPF availability (PresentationFramework)
               │   ├─> Load ReadinessGate.ps1 (if exists)
               │   ├─> Run Test-ReadinessGate
               │   ├─> IF Ready:
               │   │   ├─> Load WinRepairGUI.ps1 (dot-source)
               │   │   │   ├─> Load ErrorLogging.ps1 (dot-source)
               │   │   │   ├─> Load WinRepairCore.ps1 (dot-source, re-loaded)
               │   │   │   ├─> Load LogAnalysis.ps1 (dot-source)
               │   │   │   └─> Load NetworkDiagnostics.ps1 (conditional)
               │   │   └─> Call Start-GUI
               │   └─> IF Not Ready:
               │       ├─> Load WinRepairTUI.ps1 (dot-source)
               │       └─> Call Start-TUI
               │
               └─> IF WinRE/WinPE:
                   ├─> Load WinRepairTUI.ps1 (dot-source)
                   └─> Call Start-TUI
```

### Fallback Path (No PowerShell)
```
1. RunMiracleBoot.cmd
   └─> PowerShell check fails
       └─> call Helper\WinRepairCore.cmd
           └─> CMD-based menu system
```

### Admin Elevation Path
```
1. MiracleBoot-Admin-Launcher.ps1
   └─> Check admin rights
       ├─> IF Admin: & ".\MiracleBoot.ps1"
       └─> IF Not Admin: Start-Process powershell.exe -Verb RunAs
```

## 3. ENTRY POINTS

| Entry Point | Type | Interpreter | Version | Purpose |
|-------------|------|-------------|---------|---------|
| `RunMiracleBoot.cmd` | Batch | Windows CMD | Any Windows | Primary launcher, checks PowerShell |
| `MiracleBoot.ps1` | PowerShell | Windows PowerShell | 5.1+ | Main orchestrator |
| `MiracleBoot-Admin-Launcher.ps1` | PowerShell | Windows PowerShell | 5.1+ | Auto-elevation wrapper |
| `Helper\WinRepairCore.cmd` | Batch | Windows CMD | Any Windows | Fallback (no PowerShell) |

## 4. LANGUAGE + INTERPRETER VERSION PER FILE

### PowerShell Files (Windows PowerShell 5.1+)
**REQUIREMENT**: Windows PowerShell 5.1 or later (NOT PowerShell Core 6+)
**REASON**: Uses .NET Framework assemblies (WPF, Windows Forms), not .NET Core

| File | Language | Interpreter | Version | Notes |
|------|----------|-------------|---------|-------|
| `MiracleBoot.ps1` | PowerShell | Windows PowerShell | 5.1+ | Main entry |
| `Helper\WinRepairCore.ps1` | PowerShell | Windows PowerShell | 5.1+ | Core engine (19K+ lines) |
| `Helper\WinRepairGUI.ps1` | PowerShell | Windows PowerShell | 5.1+ | WPF GUI (requires STA mode) |
| `Helper\WinRepairTUI.ps1` | PowerShell | Windows PowerShell | 5.1+ | Console TUI |
| `Helper\ErrorLogging.ps1` | PowerShell | Windows PowerShell | 5.1+ | Logging module |
| `Helper\PreLaunchValidation.ps1` | PowerShell | Windows PowerShell | 5.1+ | Syntax validation |
| `Helper\ReadinessGate.ps1` | PowerShell | Windows PowerShell | 5.1+ | Pre-launch checks |
| `Helper\NetworkDiagnostics.ps1` | PowerShell | Windows PowerShell | 5.1+ | Network tools |
| `Helper\LogAnalysis.ps1` | PowerShell | Windows PowerShell | 5.1+ | Log parsing |
| `Helper\KeyboardSymbols.ps1` | PowerShell | Windows PowerShell | 5.1+ | Symbol helper |
| All other `Helper\*.ps1` | PowerShell | Windows PowerShell | 5.1+ | Various utilities |

### CMD/Batch Files
| File | Language | Interpreter | Version | Notes |
|------|----------|-------------|---------|-------|
| `RunMiracleBoot.cmd` | Batch | Windows CMD | Any Windows | Primary launcher |
| `Helper\WinRepairCore.cmd` | Batch | Windows CMD | Any Windows | Fallback menu |

## 5. CRITICAL DEPENDENCIES

### Required Files (Must Exist)
1. `MiracleBoot.ps1` - Main orchestrator
2. `Helper\WinRepairCore.ps1` - Core engine (loaded by ALL paths)
3. `Helper\ErrorLogging.ps1` - Loaded by main script
4. `Helper\PreLaunchValidation.ps1` - Loaded by main script

### Conditional Files
1. `Helper\WinRepairGUI.ps1` - Only for FullOS with WPF
2. `Helper\WinRepairTUI.ps1` - Fallback for WinRE/WinPE or failed GUI
3. `Helper\ReadinessGate.ps1` - Only for FullOS GUI path
4. `Helper\NetworkDiagnostics.ps1` - Only if network features used
5. `Helper\LogAnalysis.ps1` - Only if log analysis used

## 6. OS ASSUMPTIONS

### Operating System
- **Minimum**: Windows 10 (build 10240+) or Windows 11
- **Environments**: FullOS, WinRE, WinPE
- **Architecture**: x64 (primary), x86 (legacy)

### Framework Dependencies
- **.NET Framework**: 4.5+ (implicit)
- **WPF**: PresentationFramework.dll (FullOS GUI only)
- **Windows Forms**: System.Windows.Forms.dll (GUI helper)
- **Visual Basic**: Microsoft.VisualBasic.dll (InputBox helper)

### Drive Letter Assumptions
- **FullOS**: Typically C:\Windows (but uses `$WindowsRoot` variable)
- **WinRE**: X: (RAM disk), target OS on C: or D:
- **WinPE**: X: (RAM disk), target OS variable
- **NO HARDCODING**: Uses `Get-WindowsVolumes` function

## 7. GUI FRAMEWORK ASSUMPTIONS

### WPF Requirements
- **Threading Model**: STA (Single Threaded Apartment) - CRITICAL
- **XAML**: Embedded as string in WinRepairGUI.ps1 (not separate file)
- **Window**: System.Windows.Window class
- **Controls**: Standard WPF controls

### Async Patterns (Non-Blocking)
- **Runspaces**: `[runspacefactory]::CreateRunspace()`
- **Jobs**: `Start-Job` for background operations
- **Dispatcher**: `$W.Dispatcher.Invoke()` for thread-safe UI updates
- **DoEvents**: `[System.Windows.Forms.Application]::DoEvents()`

## 8. FILES THAT CANNOT BE CONFIDENTLY PARSED

**STATUS**: All critical runtime files can be parsed.

**Test files** (47 PowerShell scripts in `Test\` directory) are NOT part of runtime execution and are excluded from this analysis.

**Backup files** (e.g., `*.backup_*`) are excluded from runtime analysis.

---

**LAYER 1 COMPLETE - READY FOR LAYER 2 (PARSER-ONLY MODE)**
