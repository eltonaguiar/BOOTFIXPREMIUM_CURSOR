# ONE-CLICK REPAIR Phase 2 Fix

## Problem
User reported that ONE-CLICK REPAIR fails on "phase 2" with error:
```
Error: The term 'bootrec' is not recognized as a name of a cmdlet, function, script file, or executable program.
```

## Root Cause
The code was calling `bootrec` directly without checking if it exists. `bootrec.exe` is **only available in WinRE/WinPE environments**, not in regular Windows sessions.

**Locations where bootrec was called:**
1. Line 3153: `bootrec /rebuildbcd` (Phase 3: BCD rebuild)
2. Line 3205: `bootrec /fixboot` (Phase 4: Boot file repair)

## Fix Applied

### 1. Added bootrec.exe Availability Check
Before calling `bootrec`, the code now:
1. Checks if `bootrec` is available via `Get-Command`
2. If not found, tries common WinRE paths:
   - `$env:SystemRoot\System32\bootrec.exe`
   - `X:\Windows\System32\bootrec.exe` (WinRE default)
   - `C:\Windows\System32\Recovery\bootrec.exe`

### 2. Graceful Handling When bootrec Unavailable
If `bootrec.exe` is not found:
- Shows informative message: "bootrec.exe not available in this environment"
- Explains: "This is normal in a regular Windows session. bootrec.exe is only available in WinRE/WinPE."
- Suggests alternative: "To rebuild BCD, use: bcdboot C:\Windows /s <ESP_DRIVE>:"

### 3. Updated Both Locations
- **Phase 3 (BCD Rebuild)**: Now checks for bootrec before calling it
- **Phase 4 (Boot File Repair)**: Now checks for bootrec before calling it

## Code Changes

**Before:**
```powershell
$bcdRebuild = bootrec /rebuildbcd 2>&1 | Out-String
```

**After:**
```powershell
# Check if bootrec.exe is available (only in WinRE/WinPE)
$bootrecPath = $null
$bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
if ($bootrecCmd) {
    $bootrecPath = $bootrecCmd.Source
} else {
    # Try common WinRE paths
    $possiblePaths = @(
        "$env:SystemRoot\System32\bootrec.exe",
        "X:\Windows\System32\bootrec.exe",
        "C:\Windows\System32\Recovery\bootrec.exe"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $bootrecPath = $path
            break
        }
    }
}

if ($bootrecPath) {
    try {
        $bcdRebuild = & $bootrecPath /rebuildbcd 2>&1 | Out-String
        # ... handle output
    } catch {
        # ... handle error gracefully
    }
} else {
    # Show informative message about bootrec not being available
    # Suggest alternative: bcdboot
}
```

## Testing

Created comprehensive test script: `Test-OneClickRepairAllPhases.ps1`

**Test Coverage:**
- ✅ Phase 1: Hardware Diagnostics (Disk Health)
- ✅ Phase 2: Storage Driver Check
- ✅ Phase 3: BCD Integrity Check (including bootrec availability)
- ✅ Phase 4: Boot File Check (including bootrec availability)
- ✅ Phase 5: Final Summary Generation

**Test Results:**
- All phases pass when bootrec is unavailable (normal in regular Windows)
- No "command not recognized" errors
- Graceful handling with informative messages

## Status

✅ **FIXED** - The ONE-CLICK REPAIR feature now:
1. Checks for bootrec.exe availability before calling it
2. Gracefully handles when bootrec is not available
3. Provides informative messages and alternative suggestions
4. No longer throws "command not recognized" errors

The feature will work correctly in both:
- **Regular Windows sessions** (bootrec not available - shows info message)
- **WinRE/WinPE environments** (bootrec available - executes normally)
