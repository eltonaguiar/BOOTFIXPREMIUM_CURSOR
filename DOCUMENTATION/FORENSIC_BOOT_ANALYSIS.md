================================================================================
FORENSIC BOOT ANALYSIS & REPAIR ARCHITECTURE
Windows Boot Internals Engineering - Battle-Hardened Approach
================================================================================

## 🧠 STEP 1 — DEEP BOOT THEORY

### Windows Boot Sequence (UEFI/GPT)

1. **FIRMWARE (UEFI)**
   - UEFI firmware initializes hardware
   - Scans GPT partition table
   - Looks for EFI System Partition (ESP) with GUID: {c12a7328-f81f-11d2-ba4b-00a0c93ec93b}
   - Loads boot manager from ESP: `\EFI\Microsoft\Boot\bootmgfw.efi`
   - **Failure Point**: If ESP missing, wrong GUID, or bootmgfw.efi missing → firmware error

2. **DISK LAYOUT (GPT)**
   - GPT stores partition table in header + backup header
   - ESP must be FAT32, typically 100-500MB
   - Windows partition can be any drive letter (C:, D:, E:, etc.)
   - **Failure Point**: If GPT corrupted, ESP missing, or wrong filesystem → boot fails

3. **EFI SYSTEM PARTITION (ESP)**
   - Contains: `\EFI\Microsoft\Boot\bootmgfw.efi` (Boot Manager)
   - Contains: `\EFI\Microsoft\Boot\BCD` (Boot Configuration Data)
   - Contains: `\EFI\Microsoft\Boot\winload.efi` (OS Loader - UEFI)
   - **Failure Point**: If ESP unmounted, RAW filesystem, or files missing → boot fails

4. **BOOT MANAGER (bootmgfw.efi)**
   - Reads BCD store from ESP
   - Displays boot menu (if multiple entries)
   - Loads selected OS loader (winload.efi)
   - **Failure Point**: If BCD corrupted, missing, or points to wrong path → 0xc000000e

5. **BCD STORE DISCOVERY**
   - BCD is a binary registry hive
   - Location: `\EFI\Microsoft\Boot\BCD` (UEFI) or `\Boot\BCD` (Legacy)
   - Contains: device, osdevice, path, description for each boot entry
   - **Failure Point**: If BCD corrupted, missing, or device/osdevice = "Unknown" → boot fails

6. **WINLOAD.EFI LOCATION**
   - BCD `path` entry points to: `\Windows\system32\winload.efi`
   - BCD `osdevice` entry points to partition containing Windows
   - Boot Manager resolves osdevice → partition → loads winload.efi from that partition
   - **Failure Point**: If winload.efi missing, wrong path, or osdevice points to wrong partition → 0xc0000225

7. **DRIVER LOADING**
   - winload.efi reads `\Windows\System32\config\SYSTEM` registry hive
   - Loads boot-start drivers (Start=0) from `\Windows\System32\drivers\`
   - Critical drivers: storahci.sys, iaStorV.sys, stornvme.sys, etc.
   - **Failure Point**: If driver missing, disabled (Start=3), or StartOverride trap → 0x7B INACCESSIBLE_BOOT_DEVICE

8. **SECURE BOOT INTERFERENCE**
   - Secure Boot verifies EFI file signatures
   - If bootmgfw.efi or winload.efi modified, firmware rejects it
   - **Failure Point**: If Secure Boot ON and files unsigned/modified → firmware error before boot

9. **KERNEL TRANSITION**
   - winload.efi loads `ntoskrnl.exe` (kernel)
   - Kernel initializes memory, drivers, services
   - **Failure Point**: If kernel missing, corrupt, or driver fails → BSOD

### Legacy BIOS Boot Sequence

1. MBR → Active Partition → `\bootmgr` → `\Boot\BCD` → `\Windows\system32\winload.exe`
2. Similar logic but different file locations and boot manager

---

## 🧩 STEP 2 — WHY CURRENT TOOLS FAIL

### Failure Analysis

#### 1. `winload.efi missing` - Why Tools Fail

**Current Tool Behavior:**
- Assumes C: drive
- Runs `bcdboot C:\Windows /s S: /f UEFI`
- If winload.efi missing from C:\Windows\System32, bcdboot fails silently

**Root Causes:**
- **Wrong Drive Assumption**: In PE, Windows might be D:, E:, or other
- **Source Missing**: winload.efi missing from Windows directory (corruption/deletion)
- **bcdboot Limitation**: bcdboot only copies files that exist; can't create missing files
- **No Source Check**: Tool doesn't verify source exists before copying

**Why It Fails:**
- bcdboot reads from `C:\Windows\System32\Boot\winload.efi` (template)
- If template missing, bcdboot has nothing to copy
- bcdboot exits with "Failure when attempting to copy boot files" but tool doesn't check
- Tool reports "success" even though winload.efi still missing

#### 2. `BCD missing or corrupt` - Why Tools Fail

**Current Tool Behavior:**
- Runs `bootrec /rebuildbcd`
- If BCD corrupted, bootrec may fail or create invalid BCD

**Root Causes:**
- **BCD Corruption**: Binary hive corrupted (power loss, disk error)
- **Wrong Partition**: BCD points to non-existent partition (disk cloned/resized)
- **Device/osdevice Unknown**: BCD entries point to Volume GUID that doesn't exist
- **No Validation**: Tool doesn't verify BCD after rebuild

**Why It Fails:**
- bootrec /rebuildbcd may succeed but create BCD with wrong paths
- Tool doesn't verify BCD entries match actual disk layout
- Tool doesn't check for "Unknown" device/osdevice
- Tool doesn't validate BCD can be read by bcdedit

#### 3. `0xc000000e` - Why Tools Fail

**Current Tool Behavior:**
- Generic "boot files missing" error
- Runs bcdboot without verifying what's actually wrong

**Root Causes:**
- **BCD Not Found**: ESP not mounted or BCD missing
- **Wrong BCD Path**: BCD exists but Boot Manager can't find it
- **Firmware Boot Entry Missing**: No UEFI boot entry pointing to bootmgfw.efi
- **ESP Not Accessible**: ESP corrupted, wrong filesystem, or unmounted

**Why It Fails:**
- Tool doesn't check if ESP is mounted
- Tool doesn't verify firmware boot entries
- Tool doesn't check ESP filesystem health
- Tool assumes ESP is accessible

#### 4. `0xc0000225` - Why Tools Fail

**Current Tool Behavior:**
- Assumes winload.efi path issue
- Doesn't verify actual file location

**Root Causes:**
- **winload.efi Missing**: File deleted or corrupted
- **Wrong Path in BCD**: BCD points to wrong location (e.g., winload.exe instead of winload.efi)
- **Wrong Partition**: BCD osdevice points to wrong partition
- **Secure Boot Mismatch**: winload.efi signature invalid (Secure Boot ON)

**Why It Fails:**
- Tool doesn't verify winload.efi exists at BCD-specified path
- Tool doesn't check BCD path entry correctness
- Tool doesn't verify Secure Boot compatibility
- Tool doesn't check if osdevice matches actual Windows partition

#### 5. `Access denied` on `/fixboot` - Why Tools Fail

**Current Tool Behavior:**
- Runs bootrec /fixboot without checking permissions
- Doesn't handle access denied gracefully

**Root Causes:**
- **Not Running as Admin**: Insufficient privileges
- **ESP Write-Protected**: ESP mounted read-only
- **BitLocker Locked**: Drive encrypted and locked
- **File System Lock**: Files in use or locked

**Why It Fails:**
- Tool doesn't check admin privileges before running
- Tool doesn't verify ESP is writable
- Tool doesn't check BitLocker status
- Tool doesn't handle access denied errors

#### 6. BCD Points to Wrong Partition - Why Tools Fail

**Current Tool Behavior:**
- Runs bootrec /rebuildbcd which may detect wrong partition
- Doesn't verify BCD entries match disk layout

**Root Causes:**
- **Disk Cloned**: Partition GUIDs changed but BCD not updated
- **Partition Resized**: Partition moved but BCD still points to old location
- **Multiple Disks**: Windows on different disk than expected
- **No Validation**: Tool doesn't cross-reference BCD with actual partitions

**Why It Fails:**
- bootrec /rebuildbcd may detect wrong Windows installation
- Tool doesn't verify BCD device/osdevice matches actual partition
- Tool doesn't check for "Unknown" in BCD output
- Tool doesn't validate partition exists

#### 7. ESP Not Mounted or Wrong Filesystem - Why Tools Fail

**Current Tool Behavior:**
- Assumes ESP is mounted
- Doesn't verify ESP filesystem

**Root Causes:**
- **ESP Unmounted**: No drive letter assigned
- **ESP RAW**: Filesystem corrupted or not formatted
- **ESP Wrong FS**: Formatted as NTFS instead of FAT32
- **ESP Too Small**: Insufficient space for boot files

**Why It Fails:**
- Tool doesn't check if ESP has drive letter
- Tool doesn't verify ESP filesystem type
- Tool doesn't check ESP health
- Tool doesn't format ESP if needed

#### 8. Windows on Non-Standard Volume - Why Tools Fail

**Current Tool Behavior:**
- Assumes Windows is on C: drive
- Doesn't scan for actual Windows location

**Root Causes:**
- **PE Drive Shift**: In WinPE, Windows may be D:, E:, etc.
- **Multiple Installations**: Multiple Windows installs, wrong one selected
- **Custom Layout**: Windows on non-standard partition
- **No Discovery**: Tool doesn't scan for Windows installations

**Why It Fails:**
- Tool hardcodes C: drive
- Tool doesn't scan for \Windows\System32\config\SYSTEM
- Tool doesn't let user select correct installation
- Tool doesn't verify selected drive has Windows

#### 9. RAID/VMD/Intel RST Systems - Why Tools Fail

**Current Tool Behavior:**
- Doesn't check for storage controller drivers
- Doesn't verify driver configuration

**Root Causes:**
- **VMD Mode**: Intel VMD enabled, requires iaStorVD.sys
- **AHCI Mode**: Requires storahci.sys
- **Driver Disabled**: Driver present but Start=3 (disabled)
- **StartOverride Trap**: StartOverride key overrides Start value

**Why It Fails:**
- Tool doesn't check storage controller type
- Tool doesn't verify required drivers are enabled
- Tool doesn't check StartOverride registry key
- Tool doesn't inject missing drivers

#### 10. BitLocker-Enabled Disks - Why Tools Fail

**Current Tool Behavior:**
- Doesn't check BitLocker status
- Attempts repairs on locked drives

**Root Causes:**
- **Drive Locked**: BitLocker locked, can't read/write
- **TPM PCR Mismatch**: BCD modified, TPM refuses to unseal key
- **No Recovery Key**: User doesn't have recovery key
- **No Check**: Tool doesn't verify drive is accessible

**Why It Fails:**
- Tool doesn't check if drive is locked
- Tool doesn't warn about BitLocker before repairs
- Tool doesn't unlock drive before repairs
- Tool doesn't verify drive accessibility

#### 11. Secure Boot ON with Modified EFI Files - Why Tools Fail

**Current Tool Behavior:**
- Doesn't check Secure Boot status
- Doesn't verify EFI file signatures

**Root Causes:**
- **Secure Boot ON**: Firmware requires signed EFI files
- **Files Modified**: bootmgfw.efi or winload.efi modified/unsigned
- **Signature Invalid**: Files signed but certificate not trusted
- **No Verification**: Tool doesn't check Secure Boot state

**Why It Fails:**
- Tool doesn't check Secure Boot status
- Tool doesn't verify EFI file signatures
- Tool doesn't warn about Secure Boot implications
- Tool doesn't restore factory keys if needed

---

## 🔍 STEP 3 — FORENSIC DIAGNOSTIC MODE

### Diagnostic Phase Architecture

The diagnostic phase MUST run before any repair attempts. It produces a machine-readable report.

### Diagnostic Categories

#### A. Disk / Firmware Diagnostics

```powershell
# Detect firmware type
$firmwareType = "Unknown"
if (Test-Path "HKLM:\System\CurrentControlSet\Control\SecureBoot") {
    $firmwareType = "UEFI"
} else {
    # Check for EFI partition
    $efiPartitions = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
    if ($efiPartitions) {
        $firmwareType = "UEFI"
    } else {
        $firmwareType = "Legacy BIOS"
    }
}

# Detect partition style
$partitionStyle = (Get-Disk | Select-Object -First 1).PartitionStyle  # GPT or MBR

# Detect ESP
$espInfo = @{
    Exists = $false
    DriveLetter = $null
    FileSystem = "Unknown"
    Size = 0
    HealthStatus = "Unknown"
    Mounted = $false
    BootFilesPresent = $false
}

$efiPartitions = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
if ($efiPartitions) {
    $espInfo.Exists = $true
    $espPartition = $efiPartitions[0]
    $espInfo.Size = $espPartition.Size
    
    if ($espPartition.DriveLetter) {
        $espInfo.DriveLetter = $espPartition.DriveLetter
        $espInfo.Mounted = $true
        
        $espVolume = Get-Volume -DriveLetter $espPartition.DriveLetter -ErrorAction SilentlyContinue
        if ($espVolume) {
            $espInfo.FileSystem = $espVolume.FileSystemType
            $espInfo.HealthStatus = $espVolume.HealthStatus
        }
        
        # Check for boot files
        $bootmgfwPath = "$($espPartition.DriveLetter):\EFI\Microsoft\Boot\bootmgfw.efi"
        $bcdPath = "$($espPartition.DriveLetter):\EFI\Microsoft\Boot\BCD"
        $winloadEfiPath = "$($espPartition.DriveLetter):\EFI\Microsoft\Boot\winload.efi"
        
        $espInfo.BootFilesPresent = (Test-Path $bootmgfwPath) -and (Test-Path $bcdPath)
    }
}
```

#### B. Windows Installations Discovery

```powershell
# Scan all volumes for Windows installations
$windowsInstallations = @()

$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem }
foreach ($vol in $volumes) {
    $drive = $vol.DriveLetter
    $systemHive = "$drive`:\Windows\System32\config\SYSTEM"
    $kernelPath = "$drive`:\Windows\System32\ntoskrnl.exe"
    
    if ((Test-Path $systemHive) -or (Test-Path $kernelPath)) {
        # Get partition info
        $partition = Get-Partition -DriveLetter $drive -ErrorAction SilentlyContinue
        $disk = if ($partition) { Get-Disk -Number $partition.DiskNumber } else { $null }
        
        # Get OS version from registry
        $osVersion = "Unknown"
        $osBuild = "Unknown"
        try {
            reg load "HKLM\TempSys" $systemHive 2>&1 | Out-Null
            $osVersion = (Get-ItemProperty "HKLM:\TempSys\Setup" -Name "ProductName" -ErrorAction SilentlyContinue).ProductName
            $osBuild = (Get-ItemProperty "HKLM:\TempSys\Setup" -Name "BuildLabEx" -ErrorAction SilentlyContinue).BuildLabEx
            reg unload "HKLM\TempSys" 2>&1 | Out-Null
        } catch {
            reg unload "HKLM\TempSys" 2>&1 | Out-Null
        }
        
        $windowsInstallations += [PSCustomObject]@{
            DriveLetter = $drive
            WindowsPath = "$drive`:\Windows"
            SystemHivePath = $systemHive
            KernelPath = $kernelPath
            OSVersion = $osVersion
            OSBuild = $osBuild
            DiskNumber = if ($disk) { $disk.Number } else { $null }
            PartitionNumber = if ($partition) { $partition.PartitionNumber } else { $null }
            IsCurrentOS = ($env:SystemDrive -eq "$drive`:")
        }
    }
}
```

#### C. Boot Files Verification

```powershell
# For each Windows installation, verify boot files
foreach ($install in $windowsInstallations) {
    $bootFiles = @{
        bootmgfw_efi_esp = $false
        bootmgfw_efi_win = $false
        winload_efi_esp = $false
        winload_efi_win = $false
        winload_exe_win = $false
        bcd_exists = $false
        bcd_readable = $false
        bcd_valid = $false
    }
    
    # Check ESP files (if mounted)
    if ($espInfo.Mounted) {
        $bootFiles.bootmgfw_efi_esp = Test-Path "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\bootmgfw.efi"
        $bootFiles.winload_efi_esp = Test-Path "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\winload.efi"
        $bootFiles.bcd_exists = Test-Path "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\BCD"
    }
    
    # Check Windows directory files
    $bootFiles.bootmgfw_efi_win = Test-Path "$($install.WindowsPath)\System32\bootmgfw.efi"
    $bootFiles.winload_efi_win = Test-Path "$($install.WindowsPath)\System32\winload.efi"
    $bootFiles.winload_exe_win = Test-Path "$($install.WindowsPath)\System32\winload.exe"
    
    # Verify BCD readability
    if ($bootFiles.bcd_exists) {
        try {
            $bcdTest = bcdedit /store "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\BCD" /enum all 2>&1
            if ($LASTEXITCODE -eq 0) {
                $bootFiles.bcd_readable = $true
                
                # Check for "Unknown" device/osdevice
                if ($bcdTest -notmatch "device\s+Unknown" -and $bcdTest -notmatch "osdevice\s+Unknown") {
                    $bootFiles.bcd_valid = $true
                }
            }
        } catch {
            # BCD not readable
        }
    }
}
```

#### D. Configuration Hazards Detection

```powershell
# Secure Boot status
$secureBootStatus = @{
    Enabled = $false
    State = "Unknown"
}

try {
    $sbState = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\SecureBoot\State" -Name "UEFISecureBootEnabled" -ErrorAction SilentlyContinue).UEFISecureBootEnabled
    if ($sbState -eq 1) {
        $secureBootStatus.Enabled = $true
        $secureBootStatus.State = "Enabled"
    } else {
        $secureBootStatus.State = "Disabled"
    }
} catch {
    # Secure Boot registry not accessible (may be in PE)
}

# BitLocker status (for each Windows installation)
foreach ($install in $windowsInstallations) {
    $bitlockerStatus = Test-BitLockerGatekeeper -TargetDrive $install.DriveLetter
    $install | Add-Member -NotePropertyName "BitLockerStatus" -NotePropertyValue $bitlockerStatus
}

# Storage controller drivers
foreach ($install in $windowsInstallations) {
    $driverStatus = @{
        StorageController = "Unknown"
        RequiredDriver = $null
        DriverPresent = $false
        DriverEnabled = $false
        StartOverrideTrap = $false
    }
    
    # Mount SYSTEM hive
    try {
        reg load "HKLM\TempSys" "$($install.SystemHivePath)" 2>&1 | Out-Null
        
        # Check for VMD (Intel)
        $vmdDriver = Get-ItemProperty "HKLM:\TempSys\ControlSet001\Services\iaStorV" -ErrorAction SilentlyContinue
        if ($vmdDriver) {
            $driverStatus.StorageController = "Intel VMD"
            $driverStatus.RequiredDriver = "iaStorVD.sys"
            $driverStatus.DriverPresent = Test-Path "$($install.WindowsPath)\System32\drivers\iaStorVD.sys"
            $driverStatus.DriverEnabled = ($vmdDriver.Start -eq 0)
            
            # Check StartOverride trap
            $startOverride = Get-ItemProperty "HKLM:\TempSys\ControlSet001\Services\iaStorV\StartOverride" -ErrorAction SilentlyContinue
            if ($startOverride) {
                $driverStatus.StartOverrideTrap = $true
            }
        }
        
        # Check for AHCI
        $ahciDriver = Get-ItemProperty "HKLM:\TempSys\ControlSet001\Services\storahci" -ErrorAction SilentlyContinue
        if ($ahciDriver) {
            $driverStatus.StorageController = "AHCI"
            $driverStatus.RequiredDriver = "storahci.sys"
            $driverStatus.DriverPresent = Test-Path "$($install.WindowsPath)\System32\drivers\storahci.sys"
            $driverStatus.DriverEnabled = ($ahciDriver.Start -eq 0)
            
            # Check StartOverride trap
            $startOverride = Get-ItemProperty "HKLM:\TempSys\ControlSet001\Services\storahci\StartOverride" -ErrorAction SilentlyContinue
            if ($startOverride) {
                $driverStatus.StartOverrideTrap = $true
            }
        }
        
        reg unload "HKLM\TempSys" 2>&1 | Out-Null
    } catch {
        reg unload "HKLM\TempSys" 2>&1 | Out-Null
    }
    
    $install | Add-Member -NotePropertyName "DriverStatus" -NotePropertyValue $driverStatus
}
```

---

## 🛠 STEP 4 — INTELLIGENT REPAIR LOGIC (DECISION TREE)

### Repair Decision Tree

```
START
  |
  v
[Diagnostic Phase]
  |
  v
{ESP Missing?}
  | YES -> [Create ESP] -> [Format ESP] -> [Copy Boot Files]
  | NO  -> Continue
  |
  v
{ESP Empty/Corrupt?}
  | YES -> [Format ESP] -> [Copy Boot Files]
  | NO  -> Continue
  |
  v
{BCD Missing?}
  | YES -> [Create BCD] -> [Add Boot Entry]
  | NO  -> Continue
  |
  v
{BCD Corrupt/Invalid?}
  | YES -> [Backup BCD] -> [Rebuild BCD] -> [Verify BCD]
  | NO  -> Continue
  |
  v
{BCD Points to Wrong Partition?}
  | YES -> [Fix BCD device/osdevice] -> [Verify Partition Exists]
  | NO  -> Continue
  |
  v
{winload.efi Missing from Windows?}
  | YES -> [Check Boot folder] -> [DISM Restore] -> [SFC Restore] -> [Manual Extract]
  | NO  -> Continue
  |
  v
{winload.efi Missing from ESP?}
  | YES -> [Copy from Windows] -> [Verify Copy]
  | NO  -> Continue
  |
  v
{BCD Path Wrong?}
  | YES -> [Fix BCD path] -> [Verify Path]
  | NO  -> Continue
  |
  v
{Secure Boot Mismatch?}
  | YES -> [Warn User] -> [Restore Factory Keys] or [Disable Secure Boot]
  | NO  -> Continue
  |
  v
{BitLocker Locked?}
  | YES -> [Block Repair] -> [Request Unlock]
  | NO  -> Continue
  |
  v
{Driver Issues?}
  | YES -> [Enable Driver] -> [Remove StartOverride] -> [Inject Driver]
  | NO  -> Continue
  |
  v
[Final Verification]
  |
  v
END
```

### Scenario-Specific Repair Logic

#### Scenario 1: ESP Missing

**Preconditions:**
- UEFI firmware detected
- No EFI partition found
- GPT disk

**Exact Commands:**
```powershell
# 1. Create ESP partition (100MB minimum)
diskpart /s create_esp.txt
# create_esp.txt:
#   select disk 0
#   create partition efi size=100
#   format fs=fat32 quick label="System"
#   assign letter=S
#   exit

# 2. Copy boot files
bcdboot C:\Windows /s S: /f UEFI

# 3. Verify
Test-Path "S:\EFI\Microsoft\Boot\bootmgfw.efi"
Test-Path "S:\EFI\Microsoft\Boot\BCD"
```

**Fallback:**
- If diskpart fails, manual instructions
- If bcdboot fails, manual file copy

**Validation:**
- ESP exists and mounted
- bootmgfw.efi present
- BCD present and readable

#### Scenario 2: ESP Exists but Empty

**Preconditions:**
- ESP partition exists
- No boot files in ESP
- ESP may be RAW or wrong filesystem

**Exact Commands:**
```powershell
# 1. Format ESP
format S: /fs:FAT32 /q /y

# 2. Copy boot files
bcdboot C:\Windows /s S: /f UEFI

# 3. Verify
Test-Path "S:\EFI\Microsoft\Boot\bootmgfw.efi"
```

**Fallback:**
- If format fails, check ESP health
- If bcdboot fails, check Windows source files

**Validation:**
- ESP formatted as FAT32
- Boot files present
- BCD readable

#### Scenario 3: BCD Points to Wrong Disk

**Preconditions:**
- BCD exists and readable
- BCD device/osdevice = "Unknown"
- Partition exists but BCD doesn't match

**Exact Commands:**
```powershell
# 1. Get actual partition GUID
$partition = Get-Partition -DriveLetter C
$actualGuid = $partition.Guid

# 2. Get BCD entry
$bcdEntry = bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /enum {default}

# 3. Fix device/osdevice
bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /set {default} device partition=$actualGuid
bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /set {default} osdevice partition=$actualGuid

# 4. Verify
bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /enum {default}
# Check for "Unknown" - should be gone
```

**Fallback:**
- If GUID resolution fails, use disk/partition numbers
- If bcdedit fails, rebuild BCD entirely

**Validation:**
- BCD device/osdevice no longer "Unknown"
- BCD points to correct partition
- Partition exists and accessible

#### Scenario 4: winload.efi Missing but install.wim Exists

**Preconditions:**
- winload.efi missing from Windows directory
- Windows installation media available (ISO/USB)
- install.wim or install.esd present

**Exact Commands:**
```powershell
# 1. Mount WIM
$wimPath = "D:\sources\install.wim"
$mountPath = "C:\Mount"
dism /Mount-Wim /WimFile:$wimPath /Index:1 /MountDir:$mountPath

# 2. Extract winload.efi
$sourceWinload = "$mountPath\Windows\System32\winload.efi"
$targetWinload = "C:\Windows\System32\winload.efi"
Copy-Item $sourceWinload $targetWinload -Force

# 3. Verify
Test-Path $targetWinload

# 4. Unmount WIM
dism /Unmount-Wim /MountDir:$mountPath /Discard
```

**Fallback:**
- If WIM mount fails, try ESD
- If extract fails, manual instructions
- If no media, request user to provide

**Validation:**
- winload.efi exists in Windows directory
- File size > 0
- File attributes correct

#### Scenario 5: Windows Partition Not C:

**Preconditions:**
- Windows on D:, E:, or other drive
- Tool assumed C: drive
- BCD may point to wrong drive

**Exact Commands:**
```powershell
# 1. Discover actual Windows drive
$windowsInstallations = Get-WindowsInstallations
$targetInstall = $windowsInstallations | Where-Object { $_.IsCurrentOS } | Select-Object -First 1
$actualDrive = $targetInstall.DriveLetter

# 2. Mount ESP
$espMount = Mount-EFIPartition -WindowsDrive $actualDrive

# 3. Rebuild BCD pointing to correct drive
bcdboot "$actualDrive`:\Windows" /s "$($espMount.DriveLetter):" /f UEFI

# 4. Verify BCD points to correct drive
$bcdCheck = bcdedit /store "$($espMount.DriveLetter):\EFI\Microsoft\Boot\BCD" /enum {default}
# Verify osdevice points to $actualDrive partition
```

**Fallback:**
- If discovery fails, prompt user
- If mount fails, manual instructions

**Validation:**
- BCD osdevice matches actual Windows partition
- Boot files copied from correct drive
- BCD readable and valid

#### Scenario 6: Secure Boot Blocking Custom EFI

**Preconditions:**
- Secure Boot enabled
- EFI files modified or unsigned
- Firmware rejects boot

**Exact Commands:**
```powershell
# 1. Check Secure Boot status
$secureBootEnabled = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\SecureBoot\State" -Name "UEFISecureBootEnabled" -ErrorAction SilentlyContinue).UEFISecureBootEnabled

# 2. If enabled, warn user
if ($secureBootEnabled -eq 1) {
    Write-Warning "Secure Boot is enabled. Modified EFI files may be rejected."
    Write-Warning "Options:"
    Write-Warning "  1. Restore factory Secure Boot keys in BIOS"
    Write-Warning "  2. Temporarily disable Secure Boot"
    Write-Warning "  3. Use signed EFI files from Windows installation media"
}

# 3. Restore signed winload.efi from Component Store
sfc /scannow /offbootdir=C: /offwindir=C:\Windows

# 4. Or extract from installation media
# (See Scenario 4)
```

**Fallback:**
- If SFC fails, extract from media
- If still fails, user must disable Secure Boot or restore keys

**Validation:**
- winload.efi signature valid
- Secure Boot accepts file
- Boot succeeds

#### Scenario 7: Driver-Related Boot Failure (0x7B)

**Preconditions:**
- INACCESSIBLE_BOOT_DEVICE error
- Storage driver missing or disabled
- StartOverride trap present

**Exact Commands:**
```powershell
# 1. Mount SYSTEM hive
reg load "HKLM\TempSys" "C:\Windows\System32\config\SYSTEM"

# 2. Check storage controller type
$vmdDriver = Get-ItemProperty "HKLM:\TempSys\ControlSet001\Services\iaStorV" -ErrorAction SilentlyContinue
$ahciDriver = Get-ItemProperty "HKLM:\TempSys\ControlSet001\Services\storahci" -ErrorAction SilentlyContinue

# 3. Enable required driver
if ($vmdDriver) {
    # Enable VMD driver
    Set-ItemProperty "HKLM:\TempSys\ControlSet001\Services\iaStorV" -Name "Start" -Value 0
    
    # Remove StartOverride trap
    Remove-Item "HKLM:\TempSys\ControlSet001\Services\iaStorV\StartOverride" -Recurse -Force -ErrorAction SilentlyContinue
}

if ($ahciDriver) {
    # Enable AHCI driver
    Set-ItemProperty "HKLM:\TempSys\ControlSet001\Services\storahci" -Name "Start" -Value 0
    
    # Remove StartOverride trap
    Remove-Item "HKLM:\TempSys\ControlSet001\Services\storahci\StartOverride" -Recurse -Force -ErrorAction SilentlyContinue
}

# 4. Unload hive
reg unload "HKLM\TempSys"
```

**Fallback:**
- If driver missing, inject from installation media
- If injection fails, manual driver installation

**Validation:**
- Driver enabled (Start=0)
- StartOverride removed
- Driver file exists

#### Scenario 8: Corrupt System Hive

**Preconditions:**
- SYSTEM registry hive corrupted
- Cannot read driver configuration
- Boot fails early

**Exact Commands:**
```powershell
# 1. Check for backup hives
$systemHive = "C:\Windows\System32\config\SYSTEM"
$backupHives = @(
    "C:\Windows\System32\config\SYSTEM.alt",
    "C:\Windows\System32\config\SYSTEM.bak",
    "C:\Windows\System32\config\SYSTEM.sav"
)

# 2. Try to restore from backup
foreach ($backup in $backupHives) {
    if (Test-Path $backup) {
        Copy-Item $backup $systemHive -Force
        # Test if hive is now readable
        reg load "HKLM\TempSys" $systemHive 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            reg unload "HKLM\TempSys"
            Write-Host "Restored from $backup"
            break
        }
        reg unload "HKLM\TempSys" 2>&1 | Out-Null
    }
}

# 3. If no backup works, repair install required
```

**Fallback:**
- If backups fail, repair install required
- Cannot fix without valid SYSTEM hive

**Validation:**
- SYSTEM hive readable
- Can enumerate services
- Driver configuration accessible

#### Scenario 9: ReAgent Disabled / Broken WinRE

**Preconditions:**
- WinRE partition missing or corrupted
- ReAgent disabled
- Recovery options unavailable

**Exact Commands:**
```powershell
# 1. Check WinRE status
reagentc /info

# 2. If disabled, enable
reagentc /enable

# 3. If WinRE missing, recreate
# (Requires Windows installation media)
dism /image:C:\ /set-targetpath:C:\ /enable-feature /featurename:WinPE-OC-Package /source:D:\sources\sxs
```

**Fallback:**
- If WinRE partition missing, recreate from media
- If media unavailable, manual instructions

**Validation:**
- WinRE accessible
- ReAgent enabled
- Recovery options available

---

## 🧪 STEP 5 — REAL VERIFICATION (NO FALSE SUCCESS)

### Post-Repair Verification Checklist

After EVERY repair step, verify:

1. **File Existence**
   ```powershell
   Test-Path "C:\Windows\System32\winload.efi"
   Test-Path "S:\EFI\Microsoft\Boot\winload.efi"
   Test-Path "S:\EFI\Microsoft\Boot\bootmgfw.efi"
   Test-Path "S:\EFI\Microsoft\Boot\BCD"
   ```

2. **BCD Readability**
   ```powershell
   $bcdTest = bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /enum all 2>&1
   if ($LASTEXITCODE -ne 0) {
       # BCD still not readable
   }
   ```

3. **BCD Path Correctness**
   ```powershell
   $bcdEntry = bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /enum {default}
   if ($bcdEntry -notmatch "path\s+\\Windows\\system32\\winload\.efi") {
       # BCD path incorrect
   }
   ```

4. **BCD Device/osdevice Validity**
   ```powershell
   $bcdEntry = bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /enum {default}
   if ($bcdEntry -match "device\s+Unknown" -or $bcdEntry -match "osdevice\s+Unknown") {
       # BCD points to non-existent partition
   }
   ```

5. **Partition Exists**
   ```powershell
   # Extract partition GUID from BCD
   $bcdEntry = bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /enum {default}
   if ($bcdEntry -match "osdevice\s+partition=([a-f0-9\-]+)") {
       $partitionGuid = $matches[1]
       $partition = Get-Partition | Where-Object { $_.Guid -eq $partitionGuid }
       if (-not $partition) {
           # Partition doesn't exist
       }
   }
   ```

6. **Firmware Boot Entry**
   ```powershell
   $firmwareEntries = bcdedit /enum firmware
   if ($firmwareEntries -notmatch "bootmgfw\.efi") {
       # No firmware boot entry
   }
   ```

7. **ESP Accessibility**
   ```powershell
   $espVolume = Get-Volume -DriveLetter S -ErrorAction SilentlyContinue
   if (-not $espVolume -or $espVolume.HealthStatus -ne "Healthy") {
       # ESP not accessible
   }
   ```

### Failure Reporting

If verification fails, report:

- **WHAT failed**: Specific check that failed
- **WHY it failed**: Root cause analysis
- **WHAT is missing**: What file/configuration is missing
- **HOW to fix**: Manual steps or what's needed

---

## 🧾 STEP 6 — CODE GENERATION

### Pseudocode Architecture

```
FUNCTION DefensiveBootRepair() {
    // STEP 1: Discovery
    targetOS = DiscoverTrueWindowsDrive()
    if (targetOS == null) {
        return ERROR("No Windows installation found")
    }
    
    // STEP 2: Security Gatekeeper
    bitlockerStatus = CheckBitLockerStatus(targetOS.Drive)
    if (bitlockerStatus.IsLocked) {
        return BLOCKED("Drive is BitLocker locked. Unlock first.")
    }
    
    // STEP 3: ESP Health Check
    espInfo = GetEFIPartitionHealth(targetOS.Drive)
    if (espInfo.NeedsFormat) {
        FormatESP(espInfo.DriveLetter)
    }
    
    // STEP 4: Diagnostic Phase
    diagnosis = RunForensicDiagnostics(targetOS, espInfo)
    
    // STEP 5: Decision Tree Repair
    foreach (issue in diagnosis.Issues) {
        repairResult = ApplyRepair(issue)
        if (repairResult.Success) {
            VerifyRepair(repairResult)
        }
    }
    
    // STEP 6: Final Verification
    finalCheck = VerifyCompleteBootChain()
    return finalCheck
}
```

### PowerShell Implementation

See `Helper/DefensiveBootChain.ps1` for complete implementation.

### Batch/CMD Hybrid Logic

For CMD version, use PowerShell calls where possible:

```cmd
REM Check if PowerShell available
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell not available. Using CMD-only methods.
    goto :cmd_only_repair
)

REM Use PowerShell for complex logic
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { . '%~dp0Helper\DefensiveBootChain.ps1'; Invoke-DefensiveBootRepair }"

:cmd_only_repair
REM Fallback to diskpart/bcdboot/bcdedit
```

### Logging Strategy

```powershell
$logFile = "$env:TEMP\BootRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-RepairLog {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
    Write-Host $logEntry
}
```

### Dry-Run Mode

```powershell
function Invoke-DefensiveBootRepair {
    param(
        [switch]$DryRun,
        [switch]$Force
    )
    
    if ($DryRun) {
        Write-RepairLog "DRY-RUN MODE: Commands will be logged but not executed"
        # Log all commands that would be run
        # Don't execute actual repairs
    }
}
```

### Read-Only Diagnostic Mode

```powershell
function Invoke-ForensicDiagnostics {
    param(
        [switch]$DiagnosticOnly
    )
    
    # Run all diagnostic checks
    # Generate comprehensive report
    # Do NOT attempt any repairs
    
    return $diagnosisReport
}
```

---

## 🧠 STEP 7 — WHY THIS WILL WORK

### Why This Approach Fixes Current Failures

1. **True Drive Discovery**
   - Doesn't assume C: drive
   - Scans for actual Windows installations
   - Handles PE drive letter shifts
   - **Fixes**: Wrong drive targeting

2. **BitLocker Gatekeeper**
   - Checks lock status before repairs
   - Blocks repairs on locked drives
   - Prevents BitLocker recovery loops
   - **Fixes**: BitLocker recovery key prompts

3. **ESP Health Verification**
   - Checks ESP filesystem and health
   - Formats if needed
   - Verifies mount status
   - **Fixes**: ESP not mounted, RAW filesystem

4. **Source File Verification**
   - Checks if winload.efi exists before copying
   - Verifies Boot folder template
   - Restores from Component Store if missing
   - **Fixes**: winload.efi missing errors

5. **BCD Validation**
   - Verifies BCD readability
   - Checks for "Unknown" device/osdevice
   - Validates path correctness
   - Fixes BCD path mismatches
   - **Fixes**: BCD corruption, wrong paths

6. **Post-Repair Verification**
   - Re-checks all files after repair
   - Validates BCD entries
   - Confirms partition existence
   - **Fixes**: False success reports

### Windows Boot Myths Avoided

1. **Myth**: "bcdboot always works"
   - **Reality**: bcdboot fails if source files missing
   - **Fix**: Verify source exists before bcdboot

2. **Myth**: "Windows is always on C:"
   - **Reality**: Drive letters shift in PE
   - **Fix**: Scan for actual Windows location

3. **Myth**: "BCD is always authoritative"
   - **Reality**: BCD can point to non-existent partitions
   - **Fix**: Cross-reference BCD with actual disk layout

4. **Myth**: "ESP is always mounted"
   - **Reality**: ESP often unmounted in PE
   - **Fix**: Auto-mount ESP before repairs

5. **Myth**: "Secure Boot doesn't matter"
   - **Reality**: Secure Boot rejects modified EFI files
   - **Fix**: Check Secure Boot status and warn

### Edge Cases Handled

1. Multiple Windows installations
2. Cloned/resized disks
3. RAID/VMD storage controllers
4. BitLocker encrypted drives
5. Secure Boot enabled systems
6. Corrupted ESP filesystem
7. Missing source files
8. BCD path mismatches
9. Driver StartOverride traps
10. PE drive letter shifts

### What Cannot Be Fixed Programmatically

1. **Physical Disk Failure**
   - Bad sectors, failing drive
   - **Why**: Hardware issue, not software

2. **Firmware Corruption**
   - UEFI firmware corrupted
   - **Why**: Requires firmware update/flash

3. **Missing Installation Media**
   - winload.efi missing, no ISO available
   - **Why**: Cannot create file from nothing

4. **Incompatible Hardware**
   - Windows doesn't support hardware
   - **Why**: Driver/hardware compatibility issue

5. **User Doesn't Have Recovery Key**
   - BitLocker locked, no key
   - **Why**: Encryption security feature

---

## IMPLEMENTATION STATUS

✅ **Defensive Boot-Chain Logic Module**: Created (`Helper/DefensiveBootChain.ps1`)
✅ **True Drive Discovery**: Implemented (`Get-TargetOSDrive`)
✅ **BitLocker Gatekeeper**: Implemented (`Test-BitLockerGatekeeper`)
✅ **ESP Health Check**: Implemented (`Get-EFIPartitionHealth`)
✅ **Complete Repair Chain**: Implemented (`Invoke-DefensiveBootRepair`)
✅ **GUI Integration**: Integrated into ONE-CLICK REPAIR
✅ **Verification Logic**: Post-repair verification implemented

🔄 **In Progress**: CMD version integration, TUI integration
📋 **Next Steps**: Comprehensive testing, edge case handling

================================================================================
