# Emergency Boot Repair Scripts - Usage Guide

## Overview

Three emergency boot repair scripts have been created to handle boot issues when the main GUI and CMD tools fail. Each script uses a different approach and complexity level.

---

## When to Use Each Script

### EMERGENCY_BOOT1.cmd - Simple Mode
**Use when:**
- You need a quick, reliable fix
- You know your Windows drive letter
- You want minimal complexity
- Other tools have failed due to complexity

**What it does:**
- Asks for Windows drive letter
- Runs basic repair commands in sequence:
  1. Checks and copies winload.efi from Boot folder
  2. Runs DISM /RestoreHealth
  3. Runs SFC /ScanNow
  4. Mounts EFI partition
  5. Runs bcdboot
  6. Verifies and rebuilds BCD

**Best for:** Quick fixes when you know the drive letter

---

### EMERGENCY_BOOT2.cmd - Advanced Mode
**Use when:**
- You have multiple Windows installations
- You want to see what's wrong before fixing
- You need detailed diagnosis
- You want automatic Windows detection

**What it does:**
- Scans for all Windows installations
- Lets you choose which one to repair
- Performs comprehensive diagnosis:
  1. Checks winload.efi in Windows directory
  2. Checks EFI partition accessibility
  3. Checks BCD file integrity
  4. Checks winload.efi in EFI partition
- Attempts fixes for each detected issue
- Provides detailed status reporting

**Best for:** Multiple installations or when you need diagnosis first

---

### EMERGENCY_BOOT3.cmd - Comprehensive Mode
**Use when:**
- Simple fixes haven't worked
- You have complex boot issues
- Multiple repair strategies are needed
- You need the most thorough repair possible

**What it does:**
- Comprehensive discovery (finds Windows, detects UEFI/Legacy)
- Detailed diagnosis of all boot components
- Multiple repair strategies in order:
  1. **Simple fixes:** File copies from Boot folder or EFI partition
  2. **Intermediate fixes:** DISM /RestoreHealth, SFC /ScanNow
  3. **Advanced fixes:** bcdboot, EFI partition format, BCD rebuild
  4. **Complex fixes:** install.wim/install.esd extraction
  5. **Bootrec commands:** /scanos, /rebuildbcd, /fixboot, /fixmbr
- Final verification of all fixes
- Detailed reporting of what was fixed and what remains

**Best for:** Complex issues requiring multiple repair strategies

---

## Common Boot Issues and Solutions

### Issue 1: Missing winload.efi

**Symptoms:**
- "winload.efi is missing or contains errors"
- Windows fails to boot
- Boot loop or black screen

**Solutions (in order of complexity):**
1. Copy from Boot folder: `copy C:\Windows\System32\Boot\winload.efi C:\Windows\System32\winload.efi`
2. Run DISM: `dism /Image:C: /RestoreHealth`
3. Run SFC: `sfc /ScanNow /OffBootDir=C: /OffWinDir=C:\Windows`
4. Extract from install.wim: `dism /Image:C: /RestoreHealth /Source:X:\sources\install.wim:1`
5. Use bcdboot to copy to EFI partition: `bcdboot C:\Windows /s S: /f UEFI`

**Which script handles this:**
- All 3 scripts handle this
- EMERGENCY_BOOT3.cmd tries all methods automatically

---

### Issue 2: Missing or Corrupted BCD

**Symptoms:**
- "Boot Configuration Data file is missing"
- "BCD is missing or contains errors"
- Boot menu doesn't appear

**Solutions:**
1. Rebuild BCD: `bootrec /rebuildbcd`
2. Use bcdboot: `bcdboot C:\Windows /s S: /f UEFI`
3. Format EFI partition and retry: `format S: /fs:FAT32 /q` then `bcdboot C:\Windows /s S: /f UEFI`
4. Manual BCD creation using bcdedit

**Which script handles this:**
- All 3 scripts handle this
- EMERGENCY_BOOT2.cmd and EMERGENCY_BOOT3.cmd provide detailed BCD diagnosis

---

### Issue 3: Missing EFI Partition

**Symptoms:**
- Cannot mount EFI partition
- "EFI System Partition not found"
- UEFI boot fails

**Solutions:**
1. Mount EFI partition using diskpart:
   ```
   diskpart
   select disk 0
   list partition
   select partition 1
   assign letter=S
   exit
   ```
2. If partition doesn't exist, create it:
   - Requires advanced diskpart operations
   - May need to shrink main partition first
   - Format as FAT32
   - Set as EFI System Partition

**Which script handles this:**
- EMERGENCY_BOOT2.cmd and EMERGENCY_BOOT3.cmd attempt to mount EFI partition
- EMERGENCY_BOOT3.cmd provides more detailed EFI partition handling

---

### Issue 4: Corrupted Boot Files

**Symptoms:**
- Multiple boot files missing
- Boot process fails at different stages
- Inconsistent boot behavior

**Solutions:**
1. Run DISM /RestoreHealth
2. Run SFC /ScanNow
3. Use bcdboot to copy all boot files: `bcdboot C:\Windows /s S: /f UEFI`
4. Format EFI partition and rebuild: `format S: /fs:FAT32 /q` then `bcdboot C:\Windows /s S: /f UEFI`
5. Extract from install.wim if Component Store is corrupted

**Which script handles this:**
- EMERGENCY_BOOT3.cmd handles this comprehensively
- Tries all repair strategies in sequence

---

## Boot Repair Commands Reference

### bcdboot
**Purpose:** Copies boot files and creates/updates BCD
**Syntax:** `bcdboot <WindowsPath> /s <EFIPartition> /f <FirmwareType>`
**Example:** `bcdboot C:\Windows /s S: /f UEFI`
**Notes:**
- Requires Windows directory to have winload.efi in System32\Boot folder
- Creates BCD if missing
- Copies bootmgfw.efi and winload.efi to EFI partition

### bootrec
**Purpose:** Boot recovery commands (WinRE only)
**Commands:**
- `bootrec /scanos` - Scans for Windows installations
- `bootrec /rebuildbcd` - Rebuilds BCD store
- `bootrec /fixboot` - Fixes boot sector
- `bootrec /fixmbr` - Fixes Master Boot Record

### DISM
**Purpose:** Deployment Image Servicing and Management
**Syntax:** `dism /Image:<Drive>: /RestoreHealth [/Source:<Path>]`
**Example:** `dism /Image:C: /RestoreHealth`
**Notes:**
- Restores system files from Component Store
- Can use install.wim as source if Component Store is corrupted
- Requires Windows installation media for source option

### SFC
**Purpose:** System File Checker
**Syntax:** `sfc /ScanNow /OffBootDir=<Drive>: /OffWinDir=<WindowsPath>`
**Example:** `sfc /ScanNow /OffBootDir=C: /OffWinDir=C:\Windows`
**Notes:**
- Scans and repairs system files
- Must use /OffBootDir and /OffWinDir when running from WinRE

### bcdedit
**Purpose:** Boot Configuration Data Editor
**Syntax:** `bcdedit /store <BCD_Path> /enum {default}`
**Example:** `bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /enum {default}`
**Notes:**
- Used to view and edit BCD entries
- Can verify BCD integrity
- Can manually fix BCD path issues

---

## Web Research Findings

### Key Boot Repair Techniques (2024)

1. **BCD Repair:**
   - Use `bootrec /rebuildbcd` to scan and rebuild BCD
   - Use `bcdboot` to create new BCD if missing
   - Format EFI partition if BCD is severely corrupted

2. **winload.efi Restoration:**
   - Copy from `C:\Windows\System32\Boot\winload.efi` (bcdboot source template)
   - Use DISM /RestoreHealth to restore from Component Store
   - Extract from install.wim/install.esd if Component Store is corrupted
   - Use SFC /ScanNow as additional repair method

3. **EFI Partition Issues:**
   - Mount EFI partition using diskpart (assign drive letter)
   - Check filesystem health (must be FAT32)
   - Format if corrupted or write-protected
   - Ensure sufficient free space (at least 10MB)

4. **Boot File Verification:**
   - Check winload.efi in both Windows directory and EFI partition
   - Verify bootmgfw.efi (Boot Manager) exists
   - Verify BCD file exists and is readable
   - Check file attributes (remove read-only if needed)

5. **Advanced Techniques:**
   - Extract specific files from install.wim using DISM
   - Use diskpart to create EFI partition if missing
   - Use bcdedit to manually fix BCD entries
   - Check disk health with chkdsk before repair

### Common Failure Scenarios

1. **Access Denied:**
   - EFI partition write-protected → Format partition
   - Insufficient permissions → Run from WinRE as administrator

2. **Source Template Missing:**
   - `C:\Windows\System32\Boot\winload.efi` missing → Use DISM or install.wim extraction

3. **BCD Path Mismatch:**
   - BCD points to wrong path → Use bcdedit to correct path
   - BCD points to wrong drive → Use bcdedit to correct device/osdevice

4. **BitLocker Locked:**
   - Drive encrypted and locked → Unlock BitLocker before repair

5. **EFI Partition Corrupted:**
   - Filesystem is RAW or corrupted → Format EFI partition
   - Insufficient space → Check and free up space

---

## Troubleshooting

### Script Fails to Find Windows
- Manually enter drive letter when prompted
- Verify Windows directory exists: `dir C:\Windows\System32\ntoskrnl.exe`
- Check if drive is BitLocker locked

### EFI Partition Cannot Be Mounted
- Run diskpart manually to mount:
  ```
  diskpart
  select disk 0
  list partition
  select partition 1
  assign letter=S
  exit
  ```
- Check if EFI partition exists using diskpart

### bcdboot Fails
- Verify winload.efi exists in `C:\Windows\System32\Boot\` folder
- Check EFI partition filesystem (must be FAT32)
- Try formatting EFI partition and retrying
- Check if source template is missing (use DISM to restore)

### DISM/SFC Fail
- Component Store may be corrupted
- Use install.wim as source: `dism /Image:C: /RestoreHealth /Source:X:\sources\install.wim:1`
- Ensure Windows installation media is accessible

### install.wim Not Found
- Attach Windows ISO/USB
- Ensure it's accessible from WinRE
- Check common locations: X:, D:, E:, F: drives

---

## Best Practices

1. **Always run from WinRE/WinPE:**
   - Never run from live Windows
   - Boot from Windows installation media
   - Select "Repair your computer" > "Troubleshoot" > "Command Prompt"

2. **Start with simplest script:**
   - Try EMERGENCY_BOOT1.cmd first
   - If that fails, try EMERGENCY_BOOT2.cmd
   - Use EMERGENCY_BOOT3.cmd for complex issues

3. **Have Windows installation media ready:**
   - ISO or USB with Windows installation files
   - Needed for install.wim extraction if Component Store is corrupted

4. **Backup important data:**
   - Boot repairs are generally safe
   - But always backup critical data before repairs

5. **Document what you try:**
   - Note which script you used
   - Note what errors you see
   - Helps with troubleshooting if issues persist

---

## Script Comparison

| Feature | EMERGENCY_BOOT1 | EMERGENCY_BOOT2 | EMERGENCY_BOOT3 |
|---------|----------------|-----------------|-----------------|
| Complexity | Simple | Advanced | Comprehensive |
| Windows Detection | Manual input | Automatic scan | Automatic scan + details |
| Diagnosis | Basic | Detailed | Comprehensive |
| Repair Strategies | 1 (sequential) | 1 (per issue) | 5 (multiple fallbacks) |
| install.wim Extraction | No | No | Yes |
| Bootrec Commands | No | No | Yes (if available) |
| EFI Format | No | Yes (if needed) | Yes (if needed) |
| Best For | Quick fixes | Multiple installs | Complex issues |

---

## Conclusion

These three emergency boot repair scripts provide multiple fallback options when the main GUI and CMD tools fail. Start with the simplest (EMERGENCY_BOOT1.cmd) and progress to more complex scripts if needed. All scripts are designed to work from WinRE/WinPE environment and handle the most common boot issues.
