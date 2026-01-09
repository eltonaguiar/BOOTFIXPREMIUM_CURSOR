# Post-Change Validation Test

## Overview

**CRITICAL**: This test **MUST** be run after every set of code changes to ensure:
1. Code works without errors
2. User can get into the GUI (on Windows 10/11)
3. All modules load correctly

## Usage

### Quick Run
```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\Test-PostChangeValidation.ps1"
```

### From Repository Root
```powershell
.\Test\Test-PostChangeValidation.ps1
```

## What It Tests

### 1. Syntax Validation
- Validates PowerShell syntax for all core files
- Checks for parser errors, missing braces, etc.
- Files tested:
  - `MiracleBoot.ps1`
  - `Helper\WinRepairCore.ps1`
  - `Helper\WinRepairTUI.ps1`
  - `Helper\WinRepairGUI.ps1`
  - `Helper\NetworkDiagnostics.ps1`
  - `Helper\KeyboardSymbols.ps1`
  - `Helper\LogAnalysis.ps1`

### 2. Module Loading
- Tests that `NetworkDiagnostics.ps1` and `KeyboardSymbols.ps1` load without `Export-ModuleMember` errors
- Ensures modules can be dot-sourced properly

### 3. Core Module Loading
- Verifies `WinRepairCore.ps1` loads without critical errors
- Checks for runtime exceptions

### 4. WPF Availability
- Tests if WPF assemblies are available (required for GUI)
- Checks `PresentationFramework` and `System.Windows.Forms`

### 5. GUI Module Loading
- Verifies `WinRepairGUI.ps1` loads correctly
- Checks that `Start-GUI` function exists
- Only runs if WPF is available

### 6. Browser Test
- Ensures browser test doesn't automatically open browser
- Verifies `Test-BrowserAvailability` works correctly

### 7. Main Entry Point
- Tests that `MiracleBoot.ps1` loads correctly
- Verifies `Get-EnvironmentType` function exists

## Exit Codes

- **0**: All tests passed - code is ready
- **1**: One or more tests failed - review debug output

## Debug Routine

If tests fail, the script automatically runs a debug routine that provides:

1. **Environment Information**
   - PowerShell version
   - OS version
   - SystemDrive
   - Current directory

2. **.NET Framework Check**
   - .NET version information

3. **WPF Debugging** (if WPF unavailable)
   - Error details
   - Troubleshooting steps
   - DLL location check

4. **GUI Module Debugging** (if GUI fails)
   - Error details
   - Troubleshooting steps
   - Syntax check recommendations

5. **Syntax Error Debugging** (if syntax errors found)
   - How to validate syntax
   - Commands to run

6. **Module Load Error Debugging** (if module errors found)
   - Export-ModuleMember fix instructions

## Log Files

Test results are logged to:
```
Test\PostChangeValidation_YYYYMMDD_HHMMSS.log
```

## When to Run

**MANDATORY**: Run this test after:
- ✅ Any code changes to core files
- ✅ Adding new modules
- ✅ Modifying GUI components
- ✅ Changing module loading logic
- ✅ Before committing changes
- ✅ Before creating pull requests

## Integration with Development Workflow

### Recommended Workflow

1. Make code changes
2. Run `Test\Test-PostChangeValidation.ps1`
3. If tests pass → proceed
4. If tests fail → review debug output and fix issues
5. Re-run test until all pass
6. Commit changes

### Quick Validation Command

For quick validation during development:
```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\Test-PostChangeValidation.ps1"; if ($LASTEXITCODE -eq 0) { Write-Host "✅ Ready to commit!" -ForegroundColor Green } else { Write-Host "❌ Fix issues before committing" -ForegroundColor Red }
```

## Troubleshooting

### GUI Not Launching

If GUI tests fail:
1. Check WPF availability (Test 4)
2. Review GUI module errors (Test 5)
3. Check syntax errors (Test 1)
4. Review log file for details

### Export-ModuleMember Errors

If module loading fails:
1. Ensure `Export-ModuleMember` is wrapped in module check
2. Use: `if ($MyInvocation.MyCommand.ModuleName) { Export-ModuleMember ... }`

### Syntax Errors

If syntax validation fails:
1. Review error messages
2. Check for missing braces, parentheses, brackets
3. Use `Validate-Syntax.ps1` for detailed analysis

## Notes

- This test is designed to be fast and provide immediate feedback
- It does NOT test full functionality, only that code loads correctly
- GUI test does NOT actually launch the GUI window (validates loading only)
- Browser test ensures no automatic browser opening occurs

