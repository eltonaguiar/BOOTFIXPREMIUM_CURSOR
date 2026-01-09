# FORMAL TEST PLAN - MiracleBoot v7.1.1
**Senior Software Verification Engineer**
**Date:** 2026-01-09
**Status:** TEST PLAN DESIGN PHASE

## TEST PLAN STRUCTURE

This test plan is broken into micro-modules, each with:
- Preconditions
- Exact command used
- Expected output
- Failure signature

## MODULE 1: SYNTAX & PARSE TESTS

### Test 1.1: Parser Validation - MiracleBoot.ps1
**Preconditions:**
- File exists at root: `MiracleBoot.ps1`
- PowerShell 5.1+ available

**Command:**
```powershell
$errors = @()
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "MiracleBoot.ps1" -Raw), [ref]$errors)
if ($errors.Count -eq 0) { Write-Output "PASS" } else { Write-Output "FAIL: $($errors.Count) errors" }
```

**Expected Output:**
```
PASS
```

**Failure Signature:**
- Any error count > 0
- Parser exception thrown
- File not found

---

### Test 1.2: Parser Validation - WinRepairCore.ps1
**Preconditions:**
- File exists: `Helper\WinRepairCore.ps1`

**Command:**
```powershell
$errors = @()
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairCore.ps1" -Raw), [ref]$errors)
if ($errors.Count -eq 0) { Write-Output "PASS" } else { Write-Output "FAIL: $($errors.Count) errors" }
```

**Expected Output:**
```
PASS
```

**Failure Signature:**
- Error count > 0
- Specific errors: Line 659, 936, 940 (variable colon issues)

---

### Test 1.3: Parser Validation - WinRepairGUI.ps1
**Preconditions:**
- File exists: `Helper\WinRepairGUI.ps1`

**Command:**
```powershell
$errors = @()
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairGUI.ps1" -Raw), [ref]$errors)
if ($errors.Count -eq 0) { Write-Output "PASS" } else { Write-Output "FAIL: $($errors.Count) errors" }
```

**Expected Output:**
```
PASS
```

**Failure Signature:**
- Parser errors
- XAML string syntax issues

---

### Test 1.4: Parser Validation - WinRepairTUI.ps1
**Preconditions:**
- File exists: `Helper\WinRepairTUI.ps1`

**Command:**
```powershell
$errors = @()
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairTUI.ps1" -Raw), [ref]$errors)
if ($errors.Count -eq 0) { Write-Output "PASS" } else { Write-Output "FAIL: $($errors.Count) errors" }
```

**Expected Output:**
```
PASS
```

**Failure Signature:**
- Parser errors
- Unclosed brackets

---

### Test 1.5: Parser Validation - All Helper Files
**Preconditions:**
- All helper files exist

**Command:**
```powershell
$files = @("Helper\ErrorLogging.ps1", "Helper\PreLaunchValidation.ps1", "Helper\ReadinessGate.ps1", "Helper\NetworkDiagnostics.ps1", "Helper\LogAnalysis.ps1", "Helper\KeyboardSymbols.ps1")
$allPassed = $true
foreach ($file in $files) {
    $errors = @()
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file -Raw), [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Output "FAIL: $file has $($errors.Count) errors"
        $allPassed = $false
    }
}
if ($allPassed) { Write-Output "PASS" }
```

**Expected Output:**
```
PASS
```

**Failure Signature:**
- Any file reports errors

---

## MODULE 2: DEPENDENCY RESOLUTION TESTS

### Test 2.1: Core Module Load Test
**Preconditions:**
- PowerShell 5.1+ available
- Current directory is project root

**Command:**
```powershell
$ErrorActionPreference = "Stop"
try {
    . "Helper\WinRepairCore.ps1" -ErrorAction Stop
    Write-Output "PASS: Module loaded"
} catch {
    Write-Output "FAIL: $($_.Exception.Message)"
}
```

**Expected Output:**
```
PASS: Module loaded
```

**Failure Signature:**
- Dot-source fails
- Function not found errors
- Missing dependency errors

---

### Test 2.2: GUI Module Load Test (FullOS Only)
**Preconditions:**
- Running in FullOS (Windows 10/11 desktop)
- WPF assemblies available

**Command:**
```powershell
$ErrorActionPreference = "Stop"
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    . "Helper\WinRepairGUI.ps1" -ErrorAction Stop
    if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
        Write-Output "PASS: GUI module loaded, Start-GUI exists"
    } else {
        Write-Output "FAIL: Start-GUI function not found"
    }
} catch {
    Write-Output "FAIL: $($_.Exception.Message)"
}
```

**Expected Output:**
```
PASS: GUI module loaded, Start-GUI exists
```

**Failure Signature:**
- WPF assembly load fails
- Dot-source fails
- Start-GUI function missing

---

### Test 2.3: TUI Module Load Test
**Preconditions:**
- PowerShell available

**Command:**
```powershell
$ErrorActionPreference = "Stop"
try {
    . "Helper\WinRepairTUI.ps1" -ErrorAction Stop
    if (Get-Command Start-TUI -ErrorAction SilentlyContinue) {
        Write-Output "PASS: TUI module loaded, Start-TUI exists"
    } else {
        Write-Output "FAIL: Start-TUI function not found"
    }
} catch {
    Write-Output "FAIL: $($_.Exception.Message)"
}
```

**Expected Output:**
```
PASS: TUI module loaded, Start-TUI exists
```

**Failure Signature:**
- Dot-source fails
- Start-TUI function missing

---

### Test 2.4: Path Resolution Test (WinPE Scenario)
**Preconditions:**
- Simulate WinPE environment (X: drive)

**Command:**
```powershell
# Simulate WinPE: SystemDrive = X:
$originalDrive = $env:SystemDrive
$env:SystemDrive = "X:"
try {
    . "Helper\WinRepairCore.ps1"
    $volumes = Get-WindowsVolumes
    if ($volumes -and $volumes.Count -gt 0) {
        Write-Output "PASS: Found $($volumes.Count) Windows volume(s)"
    } else {
        Write-Output "FAIL: No Windows volumes found"
    }
} catch {
    Write-Output "FAIL: $($_.Exception.Message)"
} finally {
    $env:SystemDrive = $originalDrive
}
```

**Expected Output:**
```
PASS: Found X Windows volume(s)
```

**Failure Signature:**
- Hardcoded C: paths fail
- No volumes found
- Exception thrown

---

## MODULE 3: EXECUTION FLOW TESTS

### Test 3.1: CMD → PowerShell Handoff
**Preconditions:**
- RunMiracleBoot.cmd exists
- PowerShell available

**Command:**
```cmd
RunMiracleBoot.cmd
```

**Expected Output:**
- CMD script executes
- PowerShell launches
- No "PowerShell not available" message

**Failure Signature:**
- PowerShell detection fails
- Script execution fails immediately
- Error message displayed

---

### Test 3.2: Main Script Execution (Dry Run)
**Preconditions:**
- PowerShell available
- All dependencies present

**Command:**
```powershell
powershell.exe -STA -ExecutionPolicy Bypass -NoProfile -File MiracleBoot.ps1
# Press Ctrl+C immediately after launch to test initialization
```

**Expected Output:**
- Script starts
- Environment detection runs
- PreLaunchValidation executes
- No syntax errors displayed

**Failure Signature:**
- Syntax error screen appears
- PreLaunchValidation fails
- Script exits immediately with error

---

### Test 3.3: GUI Launch Flow (FullOS)
**Preconditions:**
- FullOS environment
- WPF available
- All modules valid

**Command:**
```powershell
powershell.exe -STA -ExecutionPolicy Bypass -NoProfile -File MiracleBoot.ps1
# Type "BRICKME" when prompted
```

**Expected Output:**
- GUI window appears
- No "Not Responding" in title bar
- Window is interactive

**Failure Signature:**
- GUI fails to launch
- Window appears but is frozen
- Exception dialog appears
- Script crashes

---

### Test 3.4: TUI Launch Flow (WinRE Simulation)
**Preconditions:**
- Simulate WinRE (no WPF)

**Command:**
```powershell
# Mock WinRE environment
$env:SYSTEMDRIVE = "X:"
powershell.exe -ExecutionPolicy Bypass -NoProfile -File MiracleBoot.ps1
```

**Expected Output:**
- TUI menu appears
- Text-based interface functional
- No GUI attempted

**Failure Signature:**
- TUI fails to launch
- GUI attempted (should not happen)
- Script crashes

---

## MODULE 4: GUI STABILITY TESTS

### Test 4.1: Thread Blocking Test
**Preconditions:**
- GUI launched successfully
- Test Mode enabled

**Command:**
```powershell
# Launch GUI, then:
# 1. Click "Precision Detection & Repair"
# 2. Immediately try to interact with other controls
```

**Expected Output:**
- GUI remains responsive during scan
- Other controls can be clicked
- Status bar updates periodically

**Failure Signature:**
- Window becomes "Not Responding"
- Controls are disabled/frozen
- No status updates

---

### Test 4.2: Long-Running Task Isolation
**Preconditions:**
- GUI launched
- Test Mode enabled

**Command:**
```powershell
# Launch GUI, then:
# 1. Click "Run Disk Check" (simulates long operation)
# 2. Observe window behavior
```

**Expected Output:**
- Operation runs in background
- Window remains responsive
- Progress updates visible
- Can cancel operation

**Failure Signature:**
- Window freezes
- No progress updates
- Cannot cancel
- Application hangs

---

### Test 4.3: Event Loop Integrity
**Preconditions:**
- GUI launched

**Command:**
```powershell
# Launch GUI, then:
# 1. Rapidly click multiple buttons
# 2. Switch tabs quickly
# 3. Type in text boxes
```

**Expected Output:**
- All interactions register
- No missed clicks
- Text input works
- Tab switching smooth

**Failure Signature:**
- Clicks ignored
- Text input laggy
- Tab switching freezes
- Event handlers not firing

---

## MODULE 5: USER INTERACTION TESTS

### Test 5.1: Invalid Input Handling
**Preconditions:**
- GUI or TUI launched

**Command:**
```powershell
# In GUI: Enter invalid drive letter (e.g., "Z99:")
# In TUI: Enter invalid menu option (e.g., "999")
```

**Expected Output:**
- Error message displayed
- No crash
- Can retry with valid input

**Failure Signature:**
- Script crashes
- Exception dialog
- No error message
- Cannot recover

---

### Test 5.2: Repeated Clicks
**Preconditions:**
- GUI launched

**Command:**
```powershell
# Rapidly click same button 10 times
```

**Expected Output:**
- Operation runs once (or queued properly)
- No duplicate operations
- No crash

**Failure Signature:**
- Multiple operations start
- Script crashes
- GUI becomes unresponsive

---

### Test 5.3: Interrupted Execution
**Preconditions:**
- Long operation running

**Command:**
```powershell
# Start long operation, then:
# 1. Close window
# 2. Or press Ctrl+C in console
```

**Expected Output:**
- Operation cancels gracefully
- Resources cleaned up
- No orphaned processes

**Failure Signature:**
- Operation continues in background
- Resources not released
- Orphaned processes
- System instability

---

## MODULE 6: OS & PERMISSION TESTS

### Test 6.1: Admin vs Non-Admin
**Preconditions:**
- Test as standard user

**Command:**
```powershell
# Run as standard user (not admin)
powershell.exe -ExecutionPolicy Bypass -NoProfile -File MiracleBoot.ps1
```

**Expected Output:**
- Admin prompt appears
- Or graceful message about needing admin
- No crash

**Failure Signature:**
- Script crashes on permission denied
- No admin check
- Silent failure

---

### Test 6.2: Execution Policy Test
**Preconditions:**
- Execution policy set to Restricted

**Command:**
```powershell
Set-ExecutionPolicy Restricted -Scope Process
powershell.exe -NoProfile -File MiracleBoot.ps1
```

**Expected Output:**
- Script sets Bypass for process
- Executes successfully
- Or clear error message

**Failure Signature:**
- Script blocked
- No error message
- Silent failure

---

### Test 6.3: Windows Defender / Antivirus
**Preconditions:**
- Windows Defender enabled

**Command:**
```powershell
# Launch script normally
# Check Windows Defender logs
```

**Expected Output:**
- Script executes
- No false positive detection
- Or clear message if blocked

**Failure Signature:**
- Script blocked by Defender
- No explanation
- Silent failure

---

## TEST EXECUTION MATRIX

| Test ID | Module | Status | Notes |
|---------|--------|--------|-------|
| 1.1 | Syntax | PENDING | |
| 1.2 | Syntax | PENDING | Critical file |
| 1.3 | Syntax | PENDING | GUI file |
| 1.4 | Syntax | PENDING | TUI file |
| 1.5 | Syntax | PENDING | All helpers |
| 2.1 | Dependency | PENDING | Core load |
| 2.2 | Dependency | PENDING | GUI load |
| 2.3 | Dependency | PENDING | TUI load |
| 2.4 | Dependency | PENDING | WinPE paths |
| 3.1 | Execution | PENDING | CMD handoff |
| 3.2 | Execution | PENDING | Main script |
| 3.3 | Execution | PENDING | GUI launch |
| 3.4 | Execution | PENDING | TUI launch |
| 4.1 | GUI Stability | PENDING | Thread blocking |
| 4.2 | GUI Stability | PENDING | Long tasks |
| 4.3 | GUI Stability | PENDING | Event loop |
| 5.1 | User Interaction | PENDING | Invalid input |
| 5.2 | User Interaction | PENDING | Repeated clicks |
| 5.3 | User Interaction | PENDING | Interrupted exec |
| 6.1 | OS/Permission | PENDING | Admin check |
| 6.2 | OS/Permission | PENDING | Execution policy |
| 6.3 | OS/Permission | PENDING | Defender |

**STATUS: TEST PLAN COMPLETE - READY FOR EXECUTION PHASE**
