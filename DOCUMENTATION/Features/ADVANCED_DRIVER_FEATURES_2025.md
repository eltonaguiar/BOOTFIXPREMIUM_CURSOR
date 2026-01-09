# Advanced Storage Controller & Driver Management Features (2025+ Systems)

## Overview

This document describes the advanced storage controller detection, driver matching, and injection features added to MiracleBoot to address the #1 reason repair installs fail in 2025+ systems.

## Problem Statement

Modern Windows systems (2025+) frequently fail during repair installs due to:
1. **Storage Controller Detection** - Advanced controllers (Intel VMD, RAID, NVMe) not recognized by Windows installer
2. **Driver Matching Logic** - Inaccurate or missing driver-to-hardware matching
3. **Driver Injection/Loading Flow** - Failures in the driver injection process during setup

## New Features

### 1. Advanced Storage Controller Detection

**Function:** `Get-AdvancedStorageControllerInfo`

**Capabilities:**
- Multi-method detection using WMI, Registry, and PCI enumeration
- Identifies controller types: Intel VMD, Intel RST RAID, AMD RAID, NVMe, AHCI
- Extracts hardware IDs, compatible IDs, and device information
- Determines boot-critical status
- Identifies required INF files
- Reports driver status and error codes

**Usage:**
```powershell
# Basic detection
$controllers = Get-AdvancedStorageControllerInfo

# Detailed detection with non-critical controllers
$controllers = Get-AdvancedStorageControllerInfo -IncludeNonCritical -Detailed
```

**Output:**
- Controller name, type, vendor
- Hardware IDs and compatible IDs
- Driver status (has driver, needs driver)
- Boot-critical flag
- Required INF file name
- Error codes and status

### 2. Advanced Driver Matching Logic

**Function:** `Test-DriverMatch`

**Capabilities:**
- Parses INF files to extract hardware IDs and compatible IDs
- Matches drivers to controllers using:
  - Exact hardware ID match (highest priority, score: 100)
  - Compatible ID match (medium priority, score: 60-80)
  - Partial match (VEN/DEV match, score: 80)
- Validates driver signatures
- Extracts service names and driver versions
- Ranks matches by precision

**Usage:**
```powershell
$match = Test-DriverMatch -HardwareID @("PCI\VEN_8086&DEV_9A0B") -DriverPath "X:\Drivers\Intel"
if ($match.Matched) {
    Write-Host "Found: $($match.DriverName) (Match: $($match.MatchType), Score: $($match.MatchScore))"
}
```

**Output:**
- Match status (matched/not matched)
- Driver name and INF path
- Match type (Exact, Compatible, Partial)
- Match score (0-100)
- Driver signature status
- All potential matches ranked by score

### 3. Advanced Driver Injection Flow

**Function:** `Start-AdvancedDriverInjection`

**Capabilities:**
- Pre-injection validation (INF parsing, signature verification)
- Hardware ID matching verification
- Dependency resolution
- Driver store integration via DISM
- Post-injection verification
- Comprehensive error reporting
- Progress callbacks for UI integration

**Usage:**
```powershell
$controllers = Get-AdvancedStorageControllerInfo
$result = Start-AdvancedDriverInjection -WindowsDrive "C" -DriverPath "X:\Drivers" -ControllerInfo $controllers

if ($result.Success) {
    Write-Host "Injected $($result.DriversInjected.Count) driver(s)"
} else {
    Write-Host "Errors: $($result.Errors -join ', ')"
}
```

**Features:**
- Validates drivers before injection
- Matches drivers to controllers automatically
- Handles unsigned drivers (with `-ForceUnsigned` flag)
- Provides detailed reports
- Supports validation-only mode (`-ValidateOnly`)

### 4. Find Matching Drivers

**Function:** `Find-MatchingDrivers`

**Capabilities:**
- Searches multiple sources for matching drivers:
  - Current Windows DriverStore
  - Offline Windows installation DriverStore
  - External driver folders
  - Manufacturer driver packages
- Ranks matches by quality
- Returns top 5 matches per controller

**Usage:**
```powershell
$controllers = Get-AdvancedStorageControllerInfo
$matches = Find-MatchingDrivers -ControllerInfo $controllers -SearchPaths @("X:\Drivers", "D:\DriverPack") -WindowsDrive "C"

foreach ($match in $matches) {
    Write-Host "$($match.Controller): $($match.MatchesFound) matches found"
}
```

## UI Integration

### Text User Interface (TUI)

Access via main menu option **3A) Advanced Driver Tools (2025+ Systems)**

Submenu options:
1. **Advanced Storage Controller Detection** - Shows all detected controllers with detailed information
2. **Advanced Driver Matching & Injection** - Validates and injects drivers with matching
3. **Find Matching Drivers for Controllers** - Searches for drivers matching detected controllers

### Graphical User Interface (GUI)

Three new button handlers are available (add buttons to XAML to enable):
- `BtnAdvancedControllerDetection` - Advanced storage controller detection
- `BtnAdvancedDriverInjection` - Advanced driver matching & injection
- `BtnFindMatchingDrivers` - Find matching drivers

## Real-World Use Cases

### Case 1: Intel VMD Controller Not Detected

**Problem:** Windows installer shows "We couldn't find any drivers" for Intel VMD controller.

**Solution:**
1. Run `Get-AdvancedStorageControllerInfo` to detect VMD controller
2. Identify required INF: `iaStorVD.inf`
3. Use `Find-MatchingDrivers` to locate driver in DriverStore or external sources
4. Use `Start-AdvancedDriverInjection` to inject driver into Windows installation

### Case 2: Driver Mismatch During Repair Install

**Problem:** Repair install fails because driver doesn't match hardware ID.

**Solution:**
1. Use `Test-DriverMatch` to verify driver matches controller hardware ID
2. If no match, use `Find-MatchingDrivers` to find correct driver
3. Inject correct driver using `Start-AdvancedDriverInjection`

### Case 3: Multiple Storage Controllers

**Problem:** System has multiple storage controllers, some missing drivers.

**Solution:**
1. Run `Get-AdvancedStorageControllerInfo -IncludeNonCritical` to see all controllers
2. Identify which controllers need drivers
3. Use `Find-MatchingDrivers` to locate all required drivers
4. Batch inject using `Start-AdvancedDriverInjection`

## Technical Details

### Hardware ID Format

Hardware IDs follow the format: `PCI\VEN_xxxx&DEV_xxxx&SUBSYS_xxxx&REV_xx`

Examples:
- Intel VMD: `PCI\VEN_8086&DEV_9A0B`
- Intel RST RAID: `PCI\VEN_8086&DEV_2822`
- AMD RAID: `PCI\VEN_1022&DEV_7901`
- Samsung NVMe: `PCI\VEN_144D&DEV_A802`

### Driver Matching Priority

1. **Exact Match** (Score: 100) - Hardware ID matches exactly
2. **VEN/DEV Match** (Score: 80) - Vendor and device ID match
3. **Compatible Match** (Score: 60) - Compatible ID matches
4. **No Match** (Score: 0) - No match found

### Supported Controller Types

- Intel VMD (Volume Management Device)
- Intel RST RAID
- Intel RST VROC (Virtual RAID on CPU)
- AMD RAID
- Samsung NVMe
- Generic NVMe
- NVIDIA Storage
- Intel AHCI
- Standard SATA/SCSI

## Microsoft Documentation References

These features are based on:
- Windows Hardware Driver Kit (WDK) documentation
- DISM driver injection best practices
- PnP device enumeration guidelines
- Driver store management procedures
- Hardware ID matching algorithms

## Best Practices

1. **Always validate before injecting** - Use `-ValidateOnly` flag first
2. **Check driver signatures** - Prefer signed drivers when possible
3. **Match hardware IDs exactly** - Use `Test-DriverMatch` to verify
4. **Backup before injection** - Create restore point or backup
5. **Test in WinPE/WinRE first** - Validate drivers before repair install

## Future Enhancements

Potential improvements:
- Automatic driver download from manufacturer websites
- Driver dependency graph resolution
- Driver version comparison and update recommendations
- Integration with Windows Update catalog
- Support for driver packages (.cab files)
- Network-based driver repository search

## Troubleshooting

### No Controllers Detected
- Check if running in WinPE/WinRE (limited WMI access)
- Verify hardware is present in Device Manager
- Try `-Detailed` flag for registry-based detection

### No Driver Matches Found
- Verify hardware IDs are correct
- Check driver INF file format
- Ensure driver supports target Windows version
- Try searching in DriverStore first

### Injection Fails
- Check DISM availability
- Verify Windows installation is accessible
- Ensure driver folder contains all required files (.inf, .sys, .cat)
- Check for unsigned driver issues (use `-ForceUnsigned` if needed)

## Summary

These advanced features provide comprehensive storage controller detection, intelligent driver matching, and robust driver injection capabilities specifically designed to address the most common repair install failure scenarios in 2025+ systems. The multi-method detection, precise matching algorithms, and validation workflows significantly improve the success rate of Windows repair installations.


