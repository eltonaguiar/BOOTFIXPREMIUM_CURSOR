# MODE 1 — STATIC ANALYSIS MODE
**Status**: ANALYSIS ONLY - NO FIXES ALLOWED
**Confidence**: 100%

## 1. FULL PROJECT FILE TREE

### Entry Points (Execution Start)
```
RunMiracleBoot.cmd                    [CMD/Batch]     Windows CMD (any version)
MiracleBoot.ps1                       [PowerShell]    Windows PowerShell 5.1+
MiracleBoot-Admin-Launcher.ps1       [PowerShell]    Windows PowerShell 5.1+
Helper\WinRepairCore.cmd              [CMD/Batch]     Windows CMD (fallback)
```

### Core Engine (Runtime Critical)
```
Helper\WinRepairCore.ps1              [PowerShell]    Windows PowerShell 5.1+  [19,534 lines]
```

### UI Layers (Runtime Critical)
```
Helper\WinRepairGUI.ps1               [PowerShell]    Windows PowerShell 5.1+  [WPF/XAML embedded]
Helper\WinRepairTUI.ps1               [PowerShell]    Windows PowerShell 5.1+  [Console/TUI]
```

### Helper Modules (Runtime - Loaded Conditionally)
```
Helper\ErrorLogging.ps1               [PowerShell]    Windows PowerShell 5.1+  [Always loaded]
Helper\PreLaunchValidation.ps1       [PowerShell]    Windows PowerShell 5.1+  [Always loaded]
Helper\ReadinessGate.ps1             [PowerShell]    Windows PowerShell 5.1+  [FullOS GUI only]
Helper\NetworkDiagnostics.ps1         [PowerShell]    Windows PowerShell 5.1+  [Conditional]
Helper\LogAnalysis.ps1                [PowerShell]    Windows PowerShell 5.1+  [Conditional]
Helper\KeyboardSymbols.ps1             [PowerShell]    Windows PowerShell 5.1+  [Conditional]
Helper\XamlDefense.ps1                 [PowerShell]    Windows PowerShell 5.1+  [Utility]
Helper\BootRepairWizard.ps1           [PowerShell]    Windows PowerShell 5.1+  [Utility]
Helper\Check-Logs.ps1                 [PowerShell]    Windows PowerShell 5.1+  [Utility]
Helper\MiracleBootPro.ps1             [PowerShell]    Windows PowerShell 5.1+  [Utility]
```

### Test Files (NOT Runtime - 47 PowerShell scripts)
```
Test\*.ps1                            [PowerShell]    Windows PowerShell 5.1+  [Excluded from runtime analysis]
```

## 2. EXECUTION ORDER

### Primary Path (FullOS with PowerShell)
```
1. RunMiracleBoot.cmd
   ├─> Check: %SystemDrive% != X: → BRICKME prompt
   ├─> Check: PowerShell available?
   │   ├─> NO → Fallback to Helper\WinRepairCore.cmd
   │   └─> YES → Continue
   └─> Launch: powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "& 'MiracleBoot.ps1'"
       │
       └─> MiracleBoot.ps1
           ├─> Set-ExecutionPolicy Bypass (Process scope)
           ├─> Check STA mode (required for WPF)
           ├─> Load ErrorLogging.ps1 (dot-source, line 262)
           ├─> Load PreLaunchValidation.ps1 (dot-source, line 275)
           ├─> Run Test-PreLaunchValidation (syntax check)
           ├─> Get-EnvironmentType (FullOS/WinRE/WinPE)
           ├─> Load WinRepairCore.ps1 (dot-source, line 336) [CRITICAL - ALWAYS LOADED]
           ├─> Load NetworkDiagnostics.ps1 (dot-source, line 383, conditional)
           ├─> Load KeyboardSymbols.ps1 (dot-source, line 392, conditional)
           │
           ├─> IF FullOS:
           │   ├─> Check WPF availability (PresentationFramework)
           │   ├─> Load ReadinessGate.ps1 (if exists, conditional)
           │   ├─> Run Test-ReadinessGate
           │   ├─> IF Ready:
           │   │   ├─> Load WinRepairGUI.ps1 (dot-source, line 477)
           │   │   │   ├─> Load ErrorLogging.ps1 (re-loaded)
           │   │   │   ├─> Load WinRepairCore.ps1 (re-loaded)
           │   │   │   ├─> Load LogAnalysis.ps1 (conditional)
           │   │   │   └─> Load NetworkDiagnostics.ps1 (conditional)
           │   │   └─> Call Start-GUI
           │   └─> IF Not Ready:
           │       ├─> Load WinRepairTUI.ps1 (dot-source, line 451)
           │       └─> Call Start-TUI
           │
           └─> IF WinRE/WinPE:
               ├─> Load WinRepairTUI.ps1 (dot-source, line 553 or 578)
               └─> Call Start-TUI
```

### Fallback Path (No PowerShell)
```
1. RunMiracleBoot.cmd
   └─> PowerShell check fails (errorlevel 1)
       └─> call Helper\WinRepairCore.cmd
           └─> CMD-based menu system (EnableNetwork, CheckInternet, etc.)
```

### Admin Elevation Path
```
1. MiracleBoot-Admin-Launcher.ps1
   ├─> Check admin rights
   ├─> IF Admin: & ".\MiracleBoot.ps1"
   └─> IF Not Admin: Start-Process powershell.exe -Verb RunAs
```

## 3. ENTRY POINTS

| Entry Point | Type | Interpreter | Version | Invocation |
|-------------|------|-------------|---------|------------|
| `RunMiracleBoot.cmd` | Batch | Windows CMD | Any Windows | Double-click or command line |
| `MiracleBoot.ps1` | PowerShell | Windows PowerShell | 5.1+ | Direct: `powershell.exe -File MiracleBoot.ps1` |
| `MiracleBoot-Admin-Launcher.ps1` | PowerShell | Windows PowerShell | 5.1+ | Double-click or command line |
| `Helper\WinRepairCore.cmd` | Batch | Windows CMD | Any Windows | Called by RunMiracleBoot.cmd if PowerShell unavailable |

## 4. LANGUAGE + INTERPRETER VERSION PER FILE

### PowerShell Files (Windows PowerShell 5.1+)
**CRITICAL REQUIREMENT**: Windows PowerShell 5.1 or later (NOT PowerShell Core 6+)
**REASON**: Uses .NET Framework assemblies (WPF, Windows Forms), not .NET Core

| File | Language | Interpreter | Version | Runtime Critical |
|------|----------|-------------|---------|------------------|
| `MiracleBoot.ps1` | PowerShell | Windows PowerShell | 5.1+ | ✅ YES (Entry Point) |
| `Helper\WinRepairCore.ps1` | PowerShell | Windows PowerShell | 5.1+ | ✅ YES (Core Engine) |
| `Helper\WinRepairGUI.ps1` | PowerShell | Windows PowerShell | 5.1+ | ✅ YES (FullOS UI) |
| `Helper\WinRepairTUI.ps1` | PowerShell | Windows PowerShell | 5.1+ | ✅ YES (WinRE/WinPE UI) |
| `Helper\ErrorLogging.ps1` | PowerShell | Windows PowerShell | 5.1+ | ✅ YES (Always loaded) |
| `Helper\PreLaunchValidation.ps1` | PowerShell | Windows PowerShell | 5.1+ | ✅ YES (Always loaded) |
| `Helper\ReadinessGate.ps1` | PowerShell | Windows PowerShell | 5.1+ | ⚠️ Conditional (FullOS GUI) |
| `Helper\NetworkDiagnostics.ps1` | PowerShell | Windows PowerShell | 5.1+ | ⚠️ Conditional |
| `Helper\LogAnalysis.ps1` | PowerShell | Windows PowerShell | 5.1+ | ⚠️ Conditional |
| `Helper\KeyboardSymbols.ps1` | PowerShell | Windows PowerShell | 5.1+ | ⚠️ Conditional |
| `MiracleBoot-Admin-Launcher.ps1` | PowerShell | Windows PowerShell | 5.1+ | ✅ YES (Entry Point) |
| `Helper\XamlDefense.ps1` | PowerShell | Windows PowerShell | 5.1+ | ❌ NO (Utility) |
| `Helper\BootRepairWizard.ps1` | PowerShell | Windows PowerShell | 5.1+ | ❌ NO (Utility) |
| `Helper\Check-Logs.ps1` | PowerShell | Windows PowerShell | 5.1+ | ❌ NO (Utility) |
| `Helper\MiracleBootPro.ps1` | PowerShell | Windows PowerShell | 5.1+ | ❌ NO (Utility) |

### CMD/Batch Files
| File | Language | Interpreter | Version | Runtime Critical |
|------|----------|-------------|---------|------------------|
| `RunMiracleBoot.cmd` | Batch | Windows CMD | Any Windows | ✅ YES (Primary Entry) |
| `Helper\WinRepairCore.cmd` | Batch | Windows CMD | Any Windows | ✅ YES (Fallback) |

## 5. DEPENDENCY & EXECUTION GRAPH

### Dependency Graph (Dot-Source Chain)
```
RunMiracleBoot.cmd
  └─> MiracleBoot.ps1
      ├─> Helper\ErrorLogging.ps1 (line 262)
      ├─> Helper\PreLaunchValidation.ps1 (line 275)
      ├─> Helper\WinRepairCore.ps1 (line 336) [CRITICAL - ALWAYS]
      ├─> Helper\NetworkDiagnostics.ps1 (line 383, conditional)
      ├─> Helper\KeyboardSymbols.ps1 (line 392, conditional)
      │
      ├─> IF FullOS + WPF Ready:
      │   ├─> Helper\ReadinessGate.ps1 (conditional)
      │   │   └─> Helper\PreLaunchValidation.ps1 (already loaded)
      │   └─> Helper\WinRepairGUI.ps1 (line 477)
      │       ├─> Helper\ErrorLogging.ps1 (re-loaded)
      │       ├─> Helper\WinRepairCore.ps1 (re-loaded)
      │       ├─> Helper\LogAnalysis.ps1 (conditional)
      │       └─> Helper\NetworkDiagnostics.ps1 (conditional)
      │
      └─> IF WinRE/WinPE OR GUI Failed:
          └─> Helper\WinRepairTUI.ps1 (line 451, 553, or 578)
              └─> Helper\LogAnalysis.ps1 (conditional)
```

### Execution Graph (Function Call Chain)
```
RunMiracleBoot.cmd
  └─> powershell.exe launches MiracleBoot.ps1
      └─> MiracleBoot.ps1 execution:
          ├─> Get-EnvironmentType() [defined in MiracleBoot.ps1]
          ├─> Test-PreLaunchValidation() [from PreLaunchValidation.ps1]
          ├─> Functions from WinRepairCore.ps1 (all engine functions)
          │
          ├─> IF FullOS + WPF:
          │   └─> Start-GUI() [from WinRepairGUI.ps1]
          │       └─> Calls engine functions from WinRepairCore.ps1
          │
          └─> IF WinRE/WinPE OR GUI Failed:
              └─> Start-TUI() [from WinRepairTUI.ps1]
                  └─> Calls engine functions from WinRepairCore.ps1
```

## 6. CRITICAL DEPENDENCIES (MUST EXIST)

### Tier 1: Absolute Requirements
1. `MiracleBoot.ps1` - Main orchestrator (entry point)
2. `Helper\WinRepairCore.ps1` - Core engine (loaded by ALL paths)
3. `Helper\ErrorLogging.ps1` - Loaded by main script (line 262)
4. `Helper\PreLaunchValidation.ps1` - Loaded by main script (line 275)

### Tier 2: Conditional Requirements
1. `Helper\WinRepairGUI.ps1` - Only for FullOS with WPF
2. `Helper\WinRepairTUI.ps1` - Fallback for WinRE/WinPE or failed GUI
3. `Helper\ReadinessGate.ps1` - Only for FullOS GUI path

### Tier 3: Optional Dependencies
1. `Helper\NetworkDiagnostics.ps1` - Only if network features used
2. `Helper\LogAnalysis.ps1` - Only if log analysis used
3. `Helper\KeyboardSymbols.ps1` - Only if keyboard symbols used

## 7. OS ASSUMPTIONS

### Operating System
- **Minimum**: Windows 10 (build 10240+) or Windows 11
- **Environments**: FullOS, WinRE, WinPE
- **Architecture**: x64 (primary), x86 (legacy support)

### Framework Dependencies
- **.NET Framework**: 4.5+ (implicit)
- **WPF**: PresentationFramework.dll (FullOS GUI only)
- **Windows Forms**: System.Windows.Forms.dll (GUI helper)
- **Visual Basic**: Microsoft.VisualBasic.dll (InputBox helper)

### Drive Letter Assumptions
- **FullOS**: Typically C:\Windows (but uses `$WindowsRoot` variable, NOT hardcoded)
- **WinRE**: X: (RAM disk), target OS on C: or D: (variable)
- **WinPE**: X: (RAM disk), target OS variable
- **NO HARDCODING**: Uses `Get-WindowsVolumes` function

## 8. GUI FRAMEWORK ASSUMPTIONS

### WPF Requirements
- **Threading Model**: STA (Single Threaded Apartment) - CRITICAL
- **XAML**: Embedded as string in WinRepairGUI.ps1 (not separate .xaml file)
- **Window**: System.Windows.Window class
- **Controls**: Standard WPF controls

### Async Patterns (Non-Blocking)
- **Runspaces**: `[runspacefactory]::CreateRunspace()`
- **Jobs**: `Start-Job` for background operations
- **Dispatcher**: `$W.Dispatcher.Invoke()` for thread-safe UI updates
- **DoEvents**: `[System.Windows.Forms.Application]::DoEvents()`

## 9. FILES THAT CANNOT BE CONFIDENTLY PARSED

**STATUS**: All critical runtime files can be parsed.

**Excluded from analysis:**
- Test files (47 PowerShell scripts in `Test\` directory) - NOT runtime
- Backup files (e.g., `*.backup_*`) - NOT runtime
- Documentation files (`.md`, `.txt`) - NOT executable

---

**MODE 1 COMPLETE**

**Previous MODE**: N/A (Initial mode)
**Current MODE**: MODE 1 — STATIC ANALYSIS MODE
**Confidence**: 100%
**Next MODE**: MODE 2 — SYNTAX VERIFICATION MODE
