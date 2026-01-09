# HARDENED TEST PROCEDURES - UI LAUNCH RELIABILITY

## Test Script: `Test-HardenedUILaunch.ps1`

### Purpose
**BRUTAL VERIFICATION** - Actually launches the UI and verifies it appears. Fails loudly if UI doesn't launch.

### How to Run

```powershell
# MUST run in STA mode
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "Test\Test-HardenedUILaunch.ps1"
```

### Test Phases

1. **PRE-FLIGHT CHECKS**
   - Verifies STA threading mode
   - Checks environment (FullOS vs WinRE/WinPE)
   - Validates Windows directory exists

2. **ASSEMBLY LOADING TEST**
   - Tests PresentationFramework loading
   - Tests System.Windows.Forms loading
   - Captures any assembly load failures

3. **MODULE LOADING TEST**
   - Loads WinRepairCore.ps1
   - Loads WinRepairGUI.ps1
   - Verifies Start-GUI function exists

4. **ACTUAL UI LAUNCH TEST**
   - **Actually calls Start-GUI in a job**
   - Waits 10 seconds for window to appear
   - If job is still running after 10 seconds = SUCCESS (window appeared)
   - If job completes immediately = FAILURE (window didn't appear)
   - Captures ALL errors from $Error collection

5. **ERROR PATTERN SCAN**
   - Scans error log for critical patterns:
     - "null-valued expression"
     - "Get-Control.*not recognized"
     - "Cannot call a method on a null"
     - "GUI MODE FAILED"
     - "FALLING BACK TO TUI"
     - "Failed to parse XAML"
     - "WPF.*failed"
     - "STA.*mode"

### Output

- **Test Log**: `%TEMP%\HardenedUI_YYYYMMDD_HHMMSS.txt`
- **Error Log**: `%TEMP%\HardenedUI_Errors_YYYYMMDD_HHMMSS.txt`

### Exit Codes

- **0**: UI WILL LAUNCH RELIABLY
- **1**: UI WILL NOT LAUNCH RELIABLY

### Critical Failures Detected

The test will fail if:
1. Not in STA mode
2. WPF assemblies fail to load
3. Modules fail to load
4. Start-GUI function missing
5. GUI window doesn't appear
6. Any critical error patterns found

---

## Known Issues Fixed

### 1. Null-Valued Expression Errors
**Location**: `Helper\WinRepairGUI.ps1` line ~999-1007
**Issue**: Direct `$W.FindName()` calls without null checking
**Fix**: Changed to use `Get-Control` function with null checks

### 2. NetworkStatus Control
**Before**:
```powershell
$W.FindName("NetworkStatus").Text = "Network: Connected"
```

**After**:
```powershell
$networkStatusControl = Get-Control "NetworkStatus"
if ($networkStatusControl) {
    $networkStatusControl.Text = "Network: Connected"
}
```

### 3. STA Threading Enforcement
**Location**: `MiracleBoot.ps1` (added)
**Fix**: Checks and enforces STA mode before WPF operations

---

## Remaining Issues to Fix

### Direct FindName Calls (29 instances found)

These need to be fixed to use `Get-Control`:

1. Line ~1198: `$W.FindName("StatusBarText").Text`
2. Line ~1600: `$W.FindName("SimList").Items.Clear()`
3. Line ~1610: `$W.FindName("BCDList").SelectedItem`
4. Line ~1612-1614: Multiple FindName calls
5. Line ~1686: `$W.FindName("DriveCombo").SelectedItem`
6. Line ~1704: `$W.FindName("FixerOutput").Text`
7. And 23 more...

**Action Required**: Replace all direct `$W.FindName()` calls with `Get-Control` function calls.

---

## Test Checklist

Before declaring "PRODUCTION READY":

- [ ] Test runs in STA mode
- [ ] All assemblies load successfully
- [ ] All modules load successfully
- [ ] Start-GUI function exists
- [ ] GUI window actually appears
- [ ] No null-valued expression errors
- [ ] No critical error patterns in logs
- [ ] Test exits with code 0

---

## If Test Fails

1. Check error log: `%TEMP%\HardenedUI_Errors_*.txt`
2. Check test log: `%TEMP%\HardenedUI_*.txt`
3. Review critical errors listed
4. Fix issues in code
5. Re-run test
6. **DO NOT** declare production ready until test passes

---

**Last Updated**: January 7, 2026
**Status**: Test created, needs all FindName calls fixed

