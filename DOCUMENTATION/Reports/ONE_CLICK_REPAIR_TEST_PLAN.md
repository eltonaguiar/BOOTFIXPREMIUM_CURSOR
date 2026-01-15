# ONE-CLICK REPAIR TEST PLAN

## LAYER 1: PROJECT ANALYSIS

### Execution Flow
1. User clicks "REPAIR MY PC" button (`BtnOneClickRepair`)
2. Event handler at line 2946 executes
3. Line 2966: `$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path`
4. Line 2967: `. "$scriptRoot\WinRepairCore.ps1" -ErrorAction Stop`
5. Calls `Test-DiskHealth -WindowsDrive $drive`
6. Calls `Get-StorageControllers -WindowsDrive $drive`
7. Runs BCD checks and boot file checks

### Entry Points
- GUI: `Helper/WinRepairGUI.ps1` line 2946
- TUI: `Helper/WinRepairTUI.ps1` (not applicable - different feature)

### Language/Interpreter
- PowerShell 5.1+ / PowerShell 7+
- WPF GUI (FullOS only)

## LAYER 2: PARSER VALIDATION

### Files to Validate
- `Helper/WinRepairGUI.ps1` (lines 2943-3159)
- `Helper/WinRepairCore.ps1` (functions: Test-DiskHealth, Get-StorageControllers)

### Syntax Checks
- [ ] Validate PowerShell syntax
- [ ] Check bracket matching
- [ ] Verify string escaping
- [ ] Check variable references

## LAYER 3: FAILURE ENUMERATION

### Identified Failures

**FILE:** Helper/WinRepairGUI.ps1
**LINE:** 2966
**ERROR TYPE:** NullReferenceException
**ERROR MESSAGE:** Cannot bind argument to parameter 'Path' because it is null
**ROOT CAUSE:** Inside event handler scriptblock, `$MyInvocation.MyCommand.Path` is null because `$MyInvocation` refers to the scriptblock, not the script file. This causes `$scriptRoot` to be null, making the dot-source path invalid.
**CONFIDENCE LEVEL:** 100%

**FILE:** Helper/WinRepairGUI.ps1
**LINE:** 2967
**ERROR TYPE:** ParameterBindingException
**ERROR MESSAGE:** Cannot bind argument to parameter 'Path' because it is null
**ROOT CAUSE:** When `$scriptRoot` is null, `"$scriptRoot\WinRepairCore.ps1"` becomes `"\WinRepairCore.ps1"` which is invalid, or the path resolution fails entirely.
**CONFIDENCE LEVEL:** 100%

## LAYER 4: SINGLE-FAULT CORRECTION

### Fix Strategy
1. Use module-level `$scriptRoot` variable (defined at line 100)
2. OR use safe path resolution pattern (same as used elsewhere in file)
3. Add null check before dot-sourcing

## LAYER 5: ADVERSARIAL TESTING

### Test Cases
1. **Test with null $MyInvocation.MyCommand.Path**
   - Simulate event handler execution
   - Verify $scriptRoot is not null
   - Verify dot-source succeeds

2. **Test with missing WinRepairCore.ps1**
   - Verify graceful error handling
   - Verify user-friendly error message

3. **Test in test mode**
   - Verify no actual repairs are performed
   - Verify all checks run successfully

## LAYER 6: EXECUTION TRACE

### Step-by-Step Simulation
1. User clicks button
2. Event handler executes
3. `$scriptRoot` is resolved (should use module-level variable)
4. `WinRepairCore.ps1` is dot-sourced
5. `Test-DiskHealth` is called
6. `Get-StorageControllers` is called
7. BCD checks run
8. Boot file checks run
9. Summary is generated

## LAYER 7: FINAL VALIDATION

### Automated Test Requirements
- [ ] Test can run without user intervention
- [ ] Test verifies $scriptRoot is not null
- [ ] Test verifies WinRepairCore.ps1 loads successfully
- [ ] Test verifies all functions are available
- [ ] Test verifies no errors occur in test mode
