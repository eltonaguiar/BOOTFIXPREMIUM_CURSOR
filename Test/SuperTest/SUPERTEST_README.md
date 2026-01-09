# SuperTest - Mandatory Pre-Release Gate

## Overview

**SuperTest-MiracleBoot.ps1** is the **mandatory pre-release gate** that MUST pass before any code can proceed out of the coding phase. This test ensures that:

1. ✅ All PowerShell files have valid syntax (no parser errors)
2. ✅ The GUI can launch successfully in Windows 11
3. ✅ No critical runtime errors are present
4. ✅ All automated test suites pass

## Why SuperTest Exists

**Problem**: Agents would sometimes tell users to test code, but there were obvious syntax errors that would have been caught if output was piped to a file and scanned for error keywords.

**Solution**: SuperTest automatically:
- Validates syntax using PowerShell's built-in parser
- Tests GUI launch capability
- Captures ALL output (stdout + stderr) to log files
- Scans logs for critical error patterns
- Fails fast on syntax errors (before running expensive tests)

## Test Phases

### PHASE 0: Comprehensive Syntax Validation (FASTEST FEEDBACK)

**Purpose**: Catch syntax errors immediately before running any other tests.

**What it does**:
- Uses `[System.Management.Automation.PSParser]::Tokenize()` to validate syntax
- Tests all PowerShell files:
  - `MiracleBoot.ps1`
  - `Helper\WinRepairCore.ps1`
  - `Helper\WinRepairTUI.ps1`
  - `Helper\WinRepairGUI.ps1`
  - `Helper\NetworkDiagnostics.ps1`
  - `Helper\KeyboardSymbols.ps1`

**Failure behavior**: **STOPS IMMEDIATELY** - no other tests run if syntax errors are found.

### PHASE 1: GUI Launch Test

**Purpose**: Ensure the GUI can launch successfully in Windows 11.

**What it does**:
- Checks if running in FullOS environment
- Loads WPF assemblies
- Loads `WinRepairGUI.ps1` module
- Verifies `Start-GUI` function exists
- Captures all output and scans for critical errors

**Failure behavior**: **STOPS IMMEDIATELY** - GUI launch failures must be fixed before proceeding.

### PHASE 2-4: Comprehensive Test Suites

**Purpose**: Run all existing automated test suites.

**What it does**:
- Runs `Test\Test-CompleteCodebase.ps1`
- Runs `Test\Test-SafeFunctions.ps1`
- Runs `Test\Test-MiracleBoot.ps1`
- Captures all output to log files
- Scans output for critical error patterns

## Critical Error Patterns

SuperTest scans for these patterns in all output:

- `Missing closing` - Syntax errors (braces, brackets, parentheses)
- `Unexpected token` - Parser errors
- `ParserError` - PowerShell parser errors
- `Cannot call a method on a null-valued expression` - Runtime null reference errors
- `Exception calling` - Method call exceptions
- `GUI mode failed` - GUI launch failures
- `Falling back to TUI` - GUI fallback (indicates GUI failure)
- And many more...

See `$criticalPatterns` array in `SuperTest-MiracleBoot.ps1` for complete list.

## Usage

### From Repository Root

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\SuperTest-MiracleBoot.ps1"
```

### From Test Directory

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "SuperTest-MiracleBoot.ps1"
```

The script automatically detects the repository root.

## Output

### Console Output

SuperTest provides color-coded console output:
- 🟢 **Green**: Passed tests
- 🔴 **Red**: Failed tests
- 🟡 **Yellow**: Warnings or skipped tests
- ⚪ **Gray**: Informational messages

### Log Files

All output is captured to timestamped log files in `Test\SuperTestLogs\`:

- `SuperTest_Summary_YYYYMMDD_HHMMSS.log` - Main summary log
- `GUILaunchTest_YYYYMMDD_HHMMSS.log` - GUI launch test output
- `Test-CompleteCodebase_YYYYMMDD_HHMMSS.log` - Complete codebase test output
- `Test-SafeFunctions_YYYYMMDD_HHMMSS.log` - Safe functions test output
- `Test-MiracleBoot_YYYYMMDD_HHMMSS.log` - MiracleBoot integration test output

Each log file contains:
- Complete stdout output
- Complete stderr output
- Exit codes
- Timestamps

## Exit Codes

- **0**: All tests passed - code is ready
- **1**: One or more tests failed - fix errors before proceeding

## When to Run SuperTest

**MANDATORY**: Run SuperTest before:
- Marking code as "out of coding phase"
- Asking users to test
- Committing to main branch
- Creating a release

**RECOMMENDED**: Run SuperTest:
- After making any code changes
- Before asking for code review
- After merging pull requests

## Integration with Development Workflow

### For Agents

**Before telling users to test**:
1. Run SuperTest
2. If it fails, fix the errors
3. Only after SuperTest passes, tell users to test

**Example workflow**:
```powershell
# Agent makes code changes
# ... code edits ...

# Run SuperTest
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\SuperTest-MiracleBoot.ps1"

# Check exit code
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ SuperTest passed - code is ready for user testing"
} else {
    Write-Host "❌ SuperTest failed - fix errors before proceeding"
    # Show error details from logs
}
```

### For Developers

**Before committing**:
```powershell
# Run SuperTest
.\Test\SuperTest-MiracleBoot.ps1

# If it passes, proceed with commit
# If it fails, check logs and fix errors
```

## Troubleshooting

### SuperTest Fails on Syntax Validation

**Symptom**: Phase 0 fails with syntax errors

**Solution**:
1. Check the console output for file and line number
2. Open the file and fix the syntax error
3. Common issues:
   - Missing closing braces `}`
   - Missing closing brackets `]`
   - Missing closing parentheses `)`
   - Unclosed strings
   - Invalid function definitions

### SuperTest Fails on GUI Launch

**Symptom**: Phase 1 fails with GUI launch errors

**Solution**:
1. Check `Test\SuperTestLogs\GUILaunchTest_*.log` for details
2. Common issues:
   - Syntax errors in `WinRepairGUI.ps1`
   - Missing `Start-GUI` function
   - WPF assembly loading failures (expected in WinRE/WinPE)
   - Null reference errors in GUI code

### SuperTest Fails on Test Suites

**Symptom**: Phase 2-4 fails

**Solution**:
1. Check the specific test log file for details
2. Review the error patterns detected
3. Fix the underlying issues
4. Re-run SuperTest

## Best Practices

1. **Run SuperTest Early**: Don't wait until the end - run it after each significant change
2. **Check Logs**: If SuperTest fails, always check the log files for detailed error information
3. **Fix Syntax First**: Syntax errors are fastest to fix and catch - fix these first
4. **Test GUI Separately**: If GUI launch fails, test the GUI module separately to isolate the issue
5. **Keep Tests Updated**: As new error patterns are discovered, add them to `$criticalPatterns`

## Technical Details

### Syntax Validation

Uses PowerShell's built-in parser:
```powershell
$errors = $null
[System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
```

This catches:
- Missing closing braces/brackets/parentheses
- Invalid tokens
- Parser errors
- Syntax errors

### GUI Launch Test

Creates a temporary PowerShell script that:
1. Checks environment (FullOS only)
2. Loads WPF assemblies
3. Loads GUI module
4. Verifies function availability
5. Captures all output

The test does NOT show the GUI window - it only validates that the GUI can be loaded.

### Output Capture

All test output is captured using:
- `RedirectStandardOutput = $true`
- `RedirectStandardError = $true`
- `UseShellExecute = $false`

This ensures we capture everything, including errors that might be written to stderr.

## Future Enhancements

Potential improvements:
- [ ] Parallel test execution for faster feedback
- [ ] Integration with CI/CD pipelines
- [ ] Automatic error pattern detection from logs
- [ ] Test coverage reporting
- [ ] Performance benchmarking

## Support

If SuperTest fails and you can't determine why:
1. Check all log files in `Test\SuperTestLogs\`
2. Review the console output for specific error messages
3. Check the individual test scripts for more details
4. Verify PowerShell version compatibility

---

**Remember**: SuperTest is your friend! It catches errors before users do. Always run it before marking code as ready.

