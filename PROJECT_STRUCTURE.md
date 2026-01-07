# Miracle Boot - Project Structure

## Overview

This document describes the organization and structure of the Miracle Boot project, following industry best practices for PowerShell-based Windows recovery tools.

## Directory Structure

```
MiracleBoot_v7_1_1/
├── MiracleBoot.ps1              # Main PowerShell entry point
├── RunMiracleBoot.cmd           # Main CMD entry point (for non-PowerShell environments)
│
├── Helper/                      # Core modules and engine
│   ├── WinRepairCore.ps1       # Main repair engine (all core functions)
│   ├── WinRepairGUI.ps1        # WPF GUI interface (FullOS only)
│   ├── WinRepairTUI.ps1        # Text-based UI (WinRE/WinPE)
│   ├── WinRepairCore.cmd        # CMD fallback interface
│   ├── NetworkDiagnostics.ps1  # Network adapter diagnostics
│   ├── KeyboardSymbols.ps1     # Unicode symbol support
│   └── README.md                # Helper module documentation
│
├── Helper Scripts/              # Utility and maintenance scripts
│   ├── EnsureMain.ps1          # Main script integrity checker
│   ├── FixWinRepairCore.ps1    # Core module repair utility
│   └── VersionTracker.ps1      # Version tracking utility
│
├── Test/                        # All testing modules and test files
│   ├── SuperTest-MiracleBoot.ps1    # Mandatory pre-release gate
│   ├── Test-CompleteCodebase.ps1    # Comprehensive codebase tests
│   ├── Test-SafeFunctions.ps1       # Safe read-only function tests
│   ├── Test-MiracleBoot.ps1         # Integration tests
│   ├── Test-GUILaunch.ps1           # GUI launch validation
│   ├── Test-GUILaunchDirect.ps1     # Direct GUI testing
│   ├── test_new_features.ps1        # New feature validation
│   ├── SUPERTEST_README.md          # SuperTest documentation
│   ├── TESTING_SUMMARY.md           # Testing summary and results
│   └── SuperTestLogs/               # Test execution logs
│
├── docs/                        # Documentation (if organized separately)
│   └── (documentation files)
│
└── workspace/                   # VS Code workspace configuration
    └── MiracleBoot_v7_1_1.code-workspace
```

## File Organization Principles

### Root Directory (2 Files Maximum)

**Purpose**: Keep root directory clean with only essential entry points.

**Files**:
- `MiracleBoot.ps1` - Main PowerShell script (entry point)
- `RunMiracleBoot.cmd` - Main CMD script (entry point for non-PowerShell environments)

**Rationale**: 
- Users expect entry points in the root
- Simplifies initial discovery
- Follows industry standard for executable projects

### Helper/ Directory

**Purpose**: Core functionality modules that are essential for operation.

**Contents**:
- Core repair engine (`WinRepairCore.ps1`)
- User interfaces (`WinRepairGUI.ps1`, `WinRepairTUI.ps1`)
- Supporting modules (`NetworkDiagnostics.ps1`, `KeyboardSymbols.ps1`)
- Fallback interfaces (`WinRepairCore.cmd`)

**Rationale**:
- Core modules are loaded by main script
- Grouped by functionality (core engine, UI, diagnostics)
- Separated from utility scripts

### Helper Scripts/ Directory

**Purpose**: Utility and maintenance scripts that are not part of core functionality.

**Contents**:
- Maintenance utilities
- Development tools
- Script repair utilities
- Version tracking

**Rationale**:
- Separates core functionality from utilities
- Utilities are optional and not loaded by default
- Makes it clear these are developer/maintenance tools

### Test/ Directory

**Purpose**: All testing-related files and test execution logs.

**Contents**:
- Test scripts (all `Test-*.ps1` files)
- Test documentation
- Test execution logs
- Test results

**Rationale**:
- Centralizes all testing resources
- Keeps root directory clean
- Makes it easy to run all tests
- Follows testing best practices

## Best Practices Implemented

### 1. Separation of Concerns
- **Core functionality** (Helper/) - Essential modules
- **Utilities** (Helper Scripts/) - Optional tools
- **Tests** (Test/) - Validation and verification
- **Documentation** (root/docs) - User and developer guides

### 2. Clear Entry Points
- Two main entry points in root (`.ps1` and `.cmd`)
- Easy to discover and use
- Supports multiple execution environments

### 3. Modular Design
- Core engine separated from UI
- Diagnostic modules isolated
- Easy to test individual components

### 4. Test Organization
- All tests in dedicated directory
- SuperTest as mandatory gate
- Comprehensive test coverage
- Test logs preserved for debugging

### 5. Documentation Structure
- README.md in root (user-facing)
- Documentation files organized by purpose
- Helper modules have their own README
- Test documentation in Test/ directory

## File Naming Conventions

### PowerShell Scripts
- **Main scripts**: `Verb-Noun.ps1` (e.g., `MiracleBoot.ps1`)
- **Test scripts**: `Test-*.ps1` (e.g., `Test-CompleteCodebase.ps1`)
- **Helper modules**: `WinRepair*.ps1` or descriptive names

### Documentation
- **Markdown files**: `UPPERCASE_DESCRIPTION.md` (e.g., `README.md`, `CHANGELOG_v7.3.0.md`)
- **Test docs**: Descriptive names (e.g., `SUPERTEST_README.md`)

### Directories
- **PascalCase** for main directories (e.g., `Helper`, `Test`)
- **Descriptive names** with spaces allowed (e.g., `Helper Scripts`)

## Path References

When referencing files in code, use relative paths from the script location:

```powershell
# In MiracleBoot.ps1
$PSScriptRoot\Helper\WinRepairCore.ps1
$PSScriptRoot\Helper\WinRepairGUI.ps1

# In test scripts
$PSScriptRoot\..\Helper\WinRepairCore.ps1
$PSScriptRoot\SuperTest-MiracleBoot.ps1
```

## Migration Notes

### From Old Structure
- Test files moved from root to `Test/`
- Utility scripts moved from `Helper/` to `Helper Scripts/`
- Documentation consolidated
- All path references updated

### Breaking Changes
- Test scripts now in `Test/` directory
- Utility scripts now in `Helper Scripts/` directory
- Update any external scripts that reference old paths

## Maintenance Guidelines

### Adding New Files

1. **Core functionality** → `Helper/`
2. **Utility scripts** → `Helper Scripts/`
3. **Test files** → `Test/`
4. **Documentation** → Root or `docs/` (if created)

### Running Tests

All tests should be run from the repository root:

```powershell
# Run SuperTest (mandatory gate)
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\SuperTest-MiracleBoot.ps1"

# Run individual tests
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\Test-CompleteCodebase.ps1"
```

### Updating Documentation

When adding new features:
1. Update `README.md` if user-facing
2. Update `CHANGELOG_v7.3.0.md` for version changes
3. Update `FUTURE_ENHANCEMENTS.md` for planned features
4. Update this file if structure changes

## Comparison with Industry Standards

### Similar Projects

**WindowsRescue / Repair-Windows**:
- Uses `/src` for main scripts
- `/tests` for test files
- `/docs` for documentation
- Similar modular approach

**PowerShell DSC Modules**:
- `/DSCResources` for core modules
- `/Tests` for Pester tests
- `/Examples` for usage examples
- `/Docs` for documentation

**Our Approach**:
- Root for entry points (simpler for end users)
- `Helper/` for core modules (clearer naming)
- `Test/` for all tests (comprehensive)
- Documentation in root (easier discovery)

## Benefits of This Structure

1. **Clarity**: Easy to find what you need
2. **Maintainability**: Logical organization
3. **Scalability**: Easy to add new modules
4. **Testing**: All tests in one place
5. **User Experience**: Entry points obvious
6. **Developer Experience**: Clear separation of concerns

---

**Last Updated**: January 2026  
**Version**: 7.3.0  
**Maintained By**: Miracle Boot Development Team


