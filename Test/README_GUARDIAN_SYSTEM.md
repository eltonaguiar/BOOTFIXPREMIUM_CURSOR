# MiracleBoot Guardian System - Complete Protection

## Overview

The **MiracleBoot Guardian** is an ultra-hardened validation and repair system designed to protect against AI-generated errors, file corruption, and "wiped" file replacements. It provides bulletproof protection for recovery environments.

## Key Features

### 🛡️ Protection Against AI Errors
- **Imposter Detection**: Identifies files that have been "wiped" or replaced by suspiciously short placeholders
- **AST-Based Validation**: Deep structural analysis using PowerShell's Abstract Syntax Tree parser
- **Heuristic Auto-Repair**: Automatically fixes common AI-generated syntax errors
- **Backup Safety Net**: Creates timestamped backups before any modification

### 🔧 Auto-Repair Capabilities
The Guardian can automatically repair:
- Missing closing braces (`}`)
- Missing closing parentheses (`)`)
- Missing multi-line comment terminators (`#>`)

### 🚨 Safety Features
- **Dual Backup System**: Creates both `.bak` (quick restore) and timestamped backups
- **Post-Repair Verification**: Re-parses files after repair to ensure success
- **Automatic Rollback**: Restores from backup if repair fails
- **Transparent Reporting**: All actions are logged and reported

## Scripts

### 1. `Test-MiracleBootGuardian.ps1` - Main Guardian Script
**Purpose**: Complete protection with imposter detection and auto-repair.

**Features**:
- ✅ Imposter/Wiped file detection
- ✅ AST-based syntax validation
- ✅ Heuristic auto-repair engine
- ✅ Dual backup system (.bak + timestamped)
- ✅ Post-repair verification
- ✅ Automatic rollback on failure
- ✅ JSON report generation

**Usage**:
```powershell
# With auto-repair (recommended for recovery environments)
.\Test\Test-MiracleBootGuardian.ps1 -TargetFolder "C:\MiracleBoot" -AutoRepair

# Without auto-repair (validation only)
.\Test\Test-MiracleBootGuardian.ps1 -TargetFolder "C:\MiracleBoot" -AutoRepair:$false

# Custom line threshold for imposter detection
.\Test\Test-MiracleBootGuardian.ps1 -MinLineThreshold 20
```

**Parameters**:
- `-TargetFolder`: Root folder to scan (default: script root)
- `-MinLineThreshold`: Minimum lines to avoid "wiped" flag (default: 10)
- `-AutoRepair`: Enable auto-repair (default: $true)
- `-ReportPath`: Path for JSON report (default: C:\MiracleBoot_Guardian_Report.json)

**Exit Codes**:
- `0` = All files valid, no issues found
- `1` = Wiped files, syntax errors, or log errors found
- `99` = Critical script error

---

### 2. `Test-HardenedASTValidator.ps1` - Standard Validator
**Purpose**: AST-based validation without repair capabilities.

**Usage**:
```powershell
.\Test\Test-HardenedASTValidator.ps1 -TargetFolder "C:\MiracleBoot"
```

---

### 3. `Test-HardenedASTValidatorWithRepair.ps1` - Validator with Repair
**Purpose**: AST validation with repair, but without imposter detection.

**Usage**:
```powershell
.\Test\Test-HardenedASTValidatorWithRepair.ps1 -TargetFolder "C:\MiracleBoot" -AutoRepair
```

---

### 4. `Test-MandatoryPreReleaseGate.ps1` - Complete Suite
**Purpose**: Comprehensive 4-phase validation (now uses Guardian).

**Phases**:
1. **Guardian Validation** - Imposter detection + AST validation
2. **GUI Launch Validation** - Ensures GUI can launch
3. **Code Quality Checks** - Validates safe patterns
4. **Stress Test** - 10 rapid launches

**Usage**:
```powershell
.\Test\Test-MandatoryPreReleaseGate.ps1
```

---

## Imposter Detection

### How It Works

The Guardian detects "wiped" files by checking:

1. **Line Count**: Files with fewer lines than `MinLineThreshold` (default: 10)
2. **Placeholder Text**: Files containing common placeholder keywords:
   - "placeholder"
   - "todo"
   - "fixme"
   - "not implemented"
   - "coming soon"

### Example Scenario

If an AI replaces a 4,753-line `WinRepairGUI.ps1` with a 4-line placeholder:

```
# Placeholder
# TODO: Implement this
# Coming soon
```

The Guardian will:
1. ✅ Detect it as a "wiped" file (only 4 lines)
2. ✅ Flag it as CRITICAL (contains placeholder text)
3. ✅ Block execution
4. ✅ Report the issue with severity level

### Recovery

If a wiped file is detected:
1. Check for `.bak` backup files
2. Restore from the most recent backup
3. Re-run Guardian to verify restoration
4. Investigate what caused the wipe

---

## Auto-Repair Process

### Step-by-Step

```
1. AST Parser identifies error type and location
   ↓
2. Guardian checks if error is repairable
   ↓
3. Dual backup created:
   - filename.bak (quick restore)
   - filename.backup_YYYYMMDD_HHMMSS (timestamped)
   ↓
4. Heuristic repair applied (appends missing terminator)
   ↓
5. Re-parsing to verify repair success
   ↓
6. If successful: Report success
   If failed: Restore from backup and report failure
```

### Supported Error Types

| Error ID | Fix Applied | Example |
|----------|-------------|---------|
| `MissingTerminatorMultiLineComment` | Appends `#>` | `#<` without closing |
| `MissingClosingBrace` | Appends `}` | Function missing `}` |
| `MissingClosingBraceInStatementBlock` | Appends `}` | Block missing `}` |
| `MissingEndParenthesisInExpression` | Appends `)` | Expression missing `)` |
| `MissingClosingParenthesis` | Appends `)` | Call missing `)` |

---

## Report Format

Guardian generates JSON reports with complete details:

```json
{
  "timestamp": "2026-01-08 00:50:58",
  "env": "FullOS",
  "ready_to_launch": true,
  "files_checked": 45,
  "wiped_files": [],
  "files_fixed": 0,
  "repair_failures": 0,
  "syntax_errors": [],
  "log_errors": [],
  "summary": "READY: All 45 files validated successfully."
}
```

### Report Fields

- `timestamp`: Validation timestamp
- `env`: Environment (FullOS or WinPE)
- `ready_to_launch`: Boolean indicating if system is ready
- `files_checked`: Number of files scanned
- `wiped_files`: Array of detected wiped files
- `files_fixed`: Number of files auto-repaired
- `repair_failures`: Number of failed repair attempts
- `syntax_errors`: Array of unrepairable syntax errors
- `log_errors`: Array of log file error matches
- `summary`: Human-readable summary

---

## Integration Examples

### In MiracleBoot.ps1 (Pre-Launch Check)

```powershell
# At the start of MiracleBoot.ps1
$guardian = Join-Path $PSScriptRoot "Test\Test-MiracleBootGuardian.ps1"
if (Test-Path $guardian) {
    Write-Host "Running Guardian validation..." -ForegroundColor Cyan
    $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $guardian -TargetFolder $PSScriptRoot -AutoRepair
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Guardian detected issues. Check report for details." -ForegroundColor Yellow
        # Optionally: exit or continue with warnings
    }
}
```

### In CI/CD Pipeline

```powershell
# Pre-deployment validation
$exitCode = & pwsh -File "Test\Test-MandatoryPreReleaseGate.ps1"
if ($exitCode -ne 0) {
    Write-Error "Pre-release validation failed - blocking deployment"
    exit 1
}
```

### In Recovery Environment (WinPE/WinRE)

```powershell
# Shift+F10 recovery console
cd X:\MiracleBoot
.\Test\Test-MiracleBootGuardian.ps1 -AutoRepair -MinLineThreshold 5
```

---

## Best Practices

### Before Committing Code
1. Run `Test-MandatoryPreReleaseGate.ps1`
2. Review any auto-repairs made
3. Check for wiped files
4. Commit validation reports

### In Recovery Environment
1. Run Guardian with auto-repair enabled
2. System will attempt to fix common errors
3. Check report for any unrepairable issues
4. Restore from backups if needed

### After AI Modifications
1. **ALWAYS** run Guardian after AI makes changes
2. Check for wiped files first
3. Review auto-repairs
4. Verify all files are intact

### Backup Management
- Guardian creates backups automatically
- Keep `.bak` files for quick restore
- Archive timestamped backups periodically
- Don't delete backups until verified

---

## Troubleshooting

### "Wiped File Detected"
**Symptom**: Guardian reports a file with suspiciously few lines.

**Solution**:
1. Check for `.bak` backup files
2. Restore from most recent backup
3. Investigate what caused the wipe
4. Re-run Guardian to verify

### "Repair Failed"
**Symptom**: Auto-repair couldn't fix the error.

**Solution**:
1. Check the JSON report for details
2. Review the specific error type
3. Fix manually if needed
4. Guardian will have restored from backup

### "Parser Exception"
**Symptom**: Parser throws an exception during validation.

**Solution**:
1. Check file encoding (should be UTF-8)
2. Verify file isn't corrupted
3. Try restoring from backup
4. Check for binary content in PowerShell file

---

## WinPE / Recovery Environment Support

✅ **Fully Compatible**:
- Windows 10/11 FullOS
- WinPE (USB recovery media)
- WinRE (Shift+F10 recovery console)
- Limited PowerShell environments

**Requirements**:
- PowerShell 2.0+ (uses core .NET classes)
- No external dependencies
- No module imports required
- Works with restricted execution policies

---

## Summary

The MiracleBoot Guardian provides:

✅ **Protection**: Detects AI-wiped files and syntax errors  
✅ **Repair**: Automatically fixes common errors  
✅ **Safety**: Creates backups before any modification  
✅ **Verification**: Re-validates after repair  
✅ **Recovery**: Works in all Windows environments  

**The Guardian is your first line of defense against AI-generated errors and file corruption.**

