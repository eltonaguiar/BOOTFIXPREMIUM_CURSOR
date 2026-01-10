# ENHANCED TESTING PROTOCOL

## Critical Failure: Stack Buffer Overrun (0xC0000409)

### Root Cause
Previous testing protocol **ONLY** tested:
1. ✅ Syntax validation (PSParser)
2. ✅ Module loading (dot-sourcing)
3. ✅ Function existence (Get-Command)

**MISSING CRITICAL TESTS:**
- ❌ Actual XAML parsing
- ❌ Actual window creation
- ❌ Memory/stack usage monitoring

### New Mandatory Testing Protocol

#### Phase 1: Pre-Launch Validation
1. **Syntax Validation** ✅
   - Use PSParser to validate all PowerShell files
   - Check for parser errors

2. **Module Loading** ✅
   - Dot-source modules
   - Check for load errors

3. **Function Existence** ✅
   - Verify all required functions exist
   - Check function signatures

#### Phase 2: GUI-Specific Validation (NEW - CRITICAL)
4. **XAML Structure Validation** ✅
   - Parse XAML as XML
   - Validate XML structure
   - Check for malformed elements

5. **XAML Size Check** ✅ (NEW)
   - Verify XAML size < 10MB
   - Warn if approaching limits
   - Prevent stack overflow

6. **ACTUAL WINDOW CREATION TEST** ❌ (NEW - CRITICAL)
   - **MUST** actually parse XAML using XamlReader
   - **MUST** create the window object
   - **MUST** verify window is not null
   - **MUST** monitor memory usage
   - **MUST** catch stack overflow errors

#### Phase 3: Runtime Validation
7. **Window Show Test** (Optional - can skip for automated testing)
   - Actually show window (briefly)
   - Verify no crashes
   - Close window immediately

### Implementation

#### Test Script: Test-GUIWindowCreation.ps1
This script MUST:
1. Load all modules
2. Extract XAML from WinRepairGUI.ps1
3. Parse XAML using XamlReader
4. Create window object
5. Verify window is not null
6. Monitor memory usage
7. Catch and report stack overflow errors

#### Enhanced Error Handling in WinRepairGUI.ps1
- Added XAML size validation (10MB limit)
- Added stack overflow detection
- Added proper resource cleanup
- Added detailed error messages

### Testing Checklist

Before any release, MUST verify:
- [ ] Syntax validation passes
- [ ] Module loading succeeds
- [ ] Functions exist
- [ ] XAML structure is valid
- [ ] XAML size < 10MB
- [ ] **Window creation test passes** (CRITICAL)
- [ ] Memory usage is reasonable
- [ ] No stack overflow errors

### Failure Prevention

1. **Automated Testing**
   - Run Test-GUIWindowCreation.ps1 in CI/CD
   - Fail build if window creation fails
   - Monitor memory usage

2. **Manual Testing**
   - Always test actual GUI launch before release
   - Test in clean environment
   - Test with different PowerShell versions

3. **Code Reviews**
   - Review XAML changes carefully
   - Check for circular references
   - Verify resource cleanup

### Lessons Learned

1. **Testing function existence ≠ Testing function execution**
   - Just because a function exists doesn't mean it works
   - Must actually CALL the function to test it

2. **XAML parsing can cause stack overflow**
   - Large/complex XAML can exceed stack limits
   - Must validate XAML size
   - Must test actual parsing

3. **Memory safety is critical**
   - Monitor memory usage during tests
   - Clean up resources properly
   - Handle stack overflow gracefully
