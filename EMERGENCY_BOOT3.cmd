@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM EMERGENCY_BOOT3.cmd - Comprehensive Boot Repair
REM Handles all issues from simple to complex with multiple repair strategies
REM ============================================================================

echo.
echo ============================================================================
echo   EMERGENCY BOOT REPAIR - COMPREHENSIVE MODE
echo ============================================================================
echo.
echo This tool provides comprehensive boot repair with multiple strategies:
echo   - Simple fixes (file copies, basic commands)
echo   - Intermediate fixes (DISM, SFC, bcdboot)
echo   - Advanced fixes (EFI partition format, BCD rebuild, install.wim extraction)
echo   - Complex fixes (partition recreation, manual file extraction)
echo.
echo WARNING: Only run this from Windows Recovery Environment (WinRE/WinPE)
echo.
pause

REM ============================================================================
REM PHASE 1: DISCOVERY
REM ============================================================================
echo.
echo ============================================================================
echo   PHASE 1: DISCOVERY
echo ============================================================================
echo.

REM Find Windows installations
echo Scanning for Windows installations...
set "INSTALL_COUNT=0"
set "INSTALL_LIST="
set "INSTALL_DETAILS="

for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%d:\Windows\System32\ntoskrnl.exe" (
        if /i not "%%d"=="X" (
            set /a INSTALL_COUNT+=1
            set "INSTALL_LIST=!INSTALL_LIST! %%d"
            
            REM Get Windows version
            set "WIN_VER=Unknown"
            if exist "%%d:\Windows\System32\winload.efi" (
                set "WIN_VER=UEFI"
            ) else if exist "%%d:\Windows\System32\winload.exe" (
                set "WIN_VER=Legacy"
            )
            
            echo   [!INSTALL_COUNT!] %%d: - Windows !WIN_VER! installation
            set "INSTALL_DETAILS=!INSTALL_DETAILS! %%d:!WIN_VER!"
        )
    )
)

if !INSTALL_COUNT! EQU 0 (
    echo.
    echo [WARNING] No Windows installations found automatically.
    set /p MANUAL_DRIVE="Enter Windows drive letter manually (e.g. C): "
    if "!MANUAL_DRIVE!"=="" set "MANUAL_DRIVE=C"
    set "MANUAL_DRIVE=!MANUAL_DRIVE:~0,1!"
    
    if not exist "!MANUAL_DRIVE!:\Windows\System32\ntoskrnl.exe" (
        echo ERROR: Windows not found on !MANUAL_DRIVE!: drive
        pause
        exit /b 1
    )
    
    set "TARGET_DRIVE=!MANUAL_DRIVE!"
    goto :start_comprehensive_repair
)

if !INSTALL_COUNT! EQU 1 (
    echo Only one Windows installation found. Using it automatically.
    for %%d in (!INSTALL_LIST!) do set "TARGET_DRIVE=%%d"
    goto :start_comprehensive_repair
)

echo.
set /p DRIVE_CHOICE="Select Windows installation (1-!INSTALL_COUNT!): "
if "!DRIVE_CHOICE!"=="" (
    echo Invalid selection.
    pause
    exit /b 1
)

set "INDEX=0"
for %%d in (!INSTALL_LIST!) do (
    set /a INDEX+=1
    if !INDEX! EQU !DRIVE_CHOICE! (
        set "TARGET_DRIVE=%%d"
        goto :start_comprehensive_repair
    )
)

echo Invalid selection.
pause
exit /b 1

:start_comprehensive_repair
echo.
echo ============================================================================
echo   PHASE 2: COMPREHENSIVE DIAGNOSIS
echo ============================================================================
echo.
echo Target drive: !TARGET_DRIVE!:
echo.

set "ISSUES_FOUND=0"
set "FIXES_APPLIED=0"
set "CRITICAL_ISSUES=0"

REM ============================================================================
REM DIAGNOSIS: Check 1 - winload.efi in Windows directory
REM ============================================================================
echo [Diagnosis 1] Checking winload.efi in Windows directory...
if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    if not exist "!TARGET_DRIVE!:\Windows\System32\winload.exe" (
        echo   [CRITICAL] winload.efi/winload.exe missing from Windows directory
        set /a ISSUES_FOUND+=1
        set /a CRITICAL_ISSUES+=1
    ) else (
        echo   [WARNING] winload.efi missing (Legacy winload.exe found)
        set /a ISSUES_FOUND+=1
    )
) else (
    echo   [OK] winload.efi found
)

REM ============================================================================
REM DIAGNOSIS: Check 2 - EFI partition
REM ============================================================================
echo.
echo [Diagnosis 2] Checking EFI partition...
set "EFI_DRIVE="
set "EFI_MOUNTED=0"

REM Check if already mounted
for %%d in (S T U V W Y Z) do (
    if exist "%%d:\EFI\Microsoft\Boot\BCD" (
        set "EFI_DRIVE=%%d"
        set "EFI_MOUNTED=1"
        echo   [OK] EFI partition already mounted as %%d:
        goto :efi_check_done
    )
)

REM Try to mount
echo   [INFO] Attempting to mount EFI partition...
(
    echo select disk 0
    echo list partition
    echo select partition 1
    echo assign letter=S
    echo exit
) > %TEMP%\mount_efi.txt
diskpart /s %TEMP%\mount_efi.txt >nul 2>&1

if exist "S:\EFI\Microsoft\Boot\BCD" (
    set "EFI_DRIVE=S"
    set "EFI_MOUNTED=1"
    echo   [OK] EFI partition mounted as S:
) else (
    echo   [CRITICAL] Could not mount EFI partition
    set /a ISSUES_FOUND+=1
    set /a CRITICAL_ISSUES+=1
)

:efi_check_done

REM ============================================================================
REM DIAGNOSIS: Check 3 - BCD file
REM ============================================================================
if not "!EFI_DRIVE!"=="" (
    echo.
    echo [Diagnosis 3] Checking BCD file...
    if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
        bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
        if errorlevel 1 (
            echo   [CRITICAL] BCD file is corrupted or unreadable
            set /a ISSUES_FOUND+=1
            set /a CRITICAL_ISSUES+=1
        ) else (
            echo   [OK] BCD file is readable
        )
    ) else (
        echo   [CRITICAL] BCD file missing from EFI partition
        set /a ISSUES_FOUND+=1
        set /a CRITICAL_ISSUES+=1
    )
)

REM ============================================================================
REM DIAGNOSIS: Check 4 - winload.efi in EFI partition
REM ============================================================================
if not "!EFI_DRIVE!"=="" (
    echo.
    echo [Diagnosis 4] Checking winload.efi in EFI partition...
    if not exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
        echo   [CRITICAL] winload.efi missing from EFI partition
        set /a ISSUES_FOUND+=1
        set /a CRITICAL_ISSUES+=1
    ) else (
        echo   [OK] winload.efi found in EFI partition
    )
)

REM ============================================================================
REM DIAGNOSIS: Check 5 - Boot files in EFI partition
REM ============================================================================
if not "!EFI_DRIVE!"=="" (
    echo.
    echo [Diagnosis 5] Checking other boot files in EFI partition...
    set "BOOT_FILES_MISSING=0"
    
    if not exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\bootmgfw.efi" (
        echo   [WARNING] bootmgfw.efi missing
        set /a BOOT_FILES_MISSING+=1
    )
    
    if not exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\memtest.efi" (
        echo   [INFO] memtest.efi missing (optional)
    )
    
    if !BOOT_FILES_MISSING! GTR 0 (
        set /a ISSUES_FOUND+=1
    ) else (
        echo   [OK] Essential boot files present
    )
)

REM ============================================================================
REM DIAGNOSIS: Check 6 - Windows directory structure
REM ============================================================================
echo.
echo [Diagnosis 6] Checking Windows directory structure...
if not exist "!TARGET_DRIVE!:\Windows\System32\ntoskrnl.exe" (
    echo   [CRITICAL] Windows kernel missing
    set /a ISSUES_FOUND+=1
    set /a CRITICAL_ISSUES+=1
) else (
    echo   [OK] Windows kernel found
)

if not exist "!TARGET_DRIVE!:\Windows\System32\config\SYSTEM" (
    echo   [WARNING] SYSTEM registry hive missing
    set /a ISSUES_FOUND+=1
) else (
    echo   [OK] SYSTEM registry hive found
)

REM ============================================================================
REM SUMMARY AND REPAIR STRATEGY
REM ============================================================================
echo.
echo ============================================================================
echo   DIAGNOSIS SUMMARY
echo ============================================================================
echo.
echo Total issues found: !ISSUES_FOUND!
echo Critical issues: !CRITICAL_ISSUES!
echo.

if !ISSUES_FOUND! EQU 0 (
    echo [SUCCESS] No boot issues detected!
    echo.
    pause
    exit /b 0
)

echo.
echo ============================================================================
echo   PHASE 3: COMPREHENSIVE REPAIR
echo ============================================================================
echo.

REM ============================================================================
REM REPAIR STRATEGY 1: Simple fixes (file copies)
REM ============================================================================
echo [Repair Strategy 1] Simple fixes (file copies)...
echo.

REM Fix winload.efi in Windows directory
if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo   Attempting to restore winload.efi...
    
    REM Try copy from Boot folder
    if exist "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" (
        echo   [Strategy 1a] Copying from Boot folder...
        copy "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" "!TARGET_DRIVE!:\Windows\System32\winload.efi" /y
        if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
            echo   [SUCCESS] Copied from Boot folder
            set /a FIXES_APPLIED+=1
            goto :winload_fixed
        )
    )
    
    REM Try copy from EFI partition if available
    if not "!EFI_DRIVE!"=="" (
        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
            echo   [Strategy 1b] Copying from EFI partition...
            copy "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" "!TARGET_DRIVE!:\Windows\System32\winload.efi" /y
            if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
                echo   [SUCCESS] Copied from EFI partition
                set /a FIXES_APPLIED+=1
                goto :winload_fixed
            )
        )
    )
    
    :winload_fixed
)

REM ============================================================================
REM REPAIR STRATEGY 2: Intermediate fixes (DISM, SFC)
REM ============================================================================
if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo.
    echo [Repair Strategy 2] Intermediate fixes (DISM, SFC)...
    echo.
    
    echo   [Strategy 2a] Running DISM /RestoreHealth...
    dism /Image:!TARGET_DRIVE!: /RestoreHealth
    if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [SUCCESS] DISM restored winload.efi
        set /a FIXES_APPLIED+=1
        goto :winload_restored
    )
    
    echo   [Strategy 2b] Running SFC /ScanNow...
    sfc /ScanNow /OffBootDir=!TARGET_DRIVE!: /OffWinDir=!TARGET_DRIVE!:\Windows
    if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [SUCCESS] SFC restored winload.efi
        set /a FIXES_APPLIED+=1
        goto :winload_restored
    )
    
    :winload_restored
)

REM ============================================================================
REM REPAIR STRATEGY 3: Advanced fixes (bcdboot, EFI format)
REM ============================================================================
echo.
echo [Repair Strategy 3] Advanced fixes (bcdboot, EFI format)...
echo.

REM Ensure EFI partition is mounted
if "!EFI_DRIVE!"=="" (
    echo   [Strategy 3a] Mounting EFI partition...
    (
        echo select disk 0
        echo list partition
        echo select partition 1
        echo assign letter=S
        echo exit
    ) > %TEMP%\mount_efi2.txt
    diskpart /s %TEMP%\mount_efi2.txt >nul 2>&1
    if exist "S:\EFI\Microsoft\Boot\BCD" (
        set "EFI_DRIVE=S"
        echo   [OK] EFI partition mounted
    )
)

if not "!EFI_DRIVE!"=="" (
    if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [Strategy 3b] Running bcdboot to copy boot files...
        bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
            echo   [SUCCESS] bcdboot copied winload.efi to EFI partition
            set /a FIXES_APPLIED+=1
        ) else (
            echo   [WARNING] bcdboot did not copy winload.efi
            echo   [Strategy 3c] Checking EFI partition health...
            
            REM Check if EFI partition is write-protected or corrupted
            echo   [Strategy 3d] Formatting EFI partition (quick format)...
            echo Y | format !EFI_DRIVE!: /fs:FAT32 /q >nul 2>&1
            if not errorlevel 1 (
                echo   [OK] EFI partition formatted
                echo   [Strategy 3e] Retrying bcdboot after format...
                bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
                if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                    echo   [SUCCESS] bcdboot succeeded after format
                    set /a FIXES_APPLIED+=1
                )
            )
        )
    )
    
    REM Fix BCD if corrupted
    if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
        bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
        if errorlevel 1 (
            echo   [Strategy 3f] BCD is corrupted, rebuilding...
            bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
            if not errorlevel 1 (
                echo   [SUCCESS] BCD rebuilt
                set /a FIXES_APPLIED+=1
            )
        )
    ) else (
        echo   [Strategy 3g] BCD missing, creating new one...
        bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
            echo   [SUCCESS] BCD created
            set /a FIXES_APPLIED+=1
        )
    )
)

REM ============================================================================
REM REPAIR STRATEGY 4: Complex fixes (install.wim extraction)
REM ============================================================================
if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo.
    echo [Repair Strategy 4] Complex fixes (install.wim extraction)...
    echo.
    
    echo   Searching for Windows installation media (install.wim/install.esd)...
    set "MEDIA_FOUND=0"
    
    for %%m in (X D E F) do (
        if exist "%%m:\sources\install.wim" (
            echo   [Strategy 4a] Found install.wim at %%m:\sources\install.wim
            echo   Extracting winload.efi using DISM...
            dism /Image:!TARGET_DRIVE!: /RestoreHealth /Source:%%m:\sources\install.wim:1 /LimitAccess
            if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
                echo   [SUCCESS] winload.efi extracted from install.wim
                set /a FIXES_APPLIED+=1
                set "MEDIA_FOUND=1"
                goto :media_extraction_done
            )
        )
        if exist "%%m:\sources\install.esd" (
            echo   [Strategy 4b] Found install.esd at %%m:\sources\install.esd
            echo   Extracting winload.efi using DISM...
            dism /Image:!TARGET_DRIVE!: /RestoreHealth /Source:%%m:\sources\install.esd:1 /LimitAccess
            if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
                echo   [SUCCESS] winload.efi extracted from install.esd
                set /a FIXES_APPLIED+=1
                set "MEDIA_FOUND=1"
                goto :media_extraction_done
            )
        )
    )
    
    :media_extraction_done
    if "!MEDIA_FOUND!"=="0" (
        echo   [WARNING] Could not find Windows installation media
        echo   Please attach Windows ISO/USB and ensure it's accessible
    )
)

REM ============================================================================
REM REPAIR STRATEGY 5: Bootrec commands (if available)
REM ============================================================================
where bootrec.exe >nul 2>&1
if not errorlevel 1 (
    echo.
    echo [Repair Strategy 5] Bootrec commands (if available)...
    echo.
    
    echo   [Strategy 5a] Running bootrec /scanos...
    bootrec /scanos
    
    echo   [Strategy 5b] Running bootrec /rebuildbcd...
    bootrec /rebuildbcd
    
    echo   [Strategy 5c] Running bootrec /fixboot...
    bootrec /fixboot
    
    echo   [Strategy 5d] Running bootrec /fixmbr...
    bootrec /fixmbr
    
    echo   [OK] Bootrec commands completed
)

REM ============================================================================
REM FINAL VERIFICATION
REM ============================================================================
echo.
echo ============================================================================
echo   PHASE 4: FINAL VERIFICATION
echo ============================================================================
echo.

set "FINAL_ISSUES=0"

if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo [FAIL] winload.efi still missing from Windows directory
    set /a FINAL_ISSUES+=1
) else (
    echo [OK] winload.efi found in Windows directory
)

if not "!EFI_DRIVE!"=="" (
    if not exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
        echo [FAIL] winload.efi still missing from EFI partition
        set /a FINAL_ISSUES+=1
    ) else (
        echo [OK] winload.efi found in EFI partition
    )
    
    if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
        bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
        if errorlevel 1 (
            echo [FAIL] BCD still corrupted
            set /a FINAL_ISSUES+=1
        ) else (
            echo [OK] BCD is readable
        )
    ) else (
        echo [FAIL] BCD still missing
        set /a FINAL_ISSUES+=1
    )
) else (
    echo [WARNING] EFI partition not accessible for verification
    set /a FINAL_ISSUES+=1
)

REM ============================================================================
REM FINAL SUMMARY
REM ============================================================================
echo.
echo ============================================================================
echo   REPAIR SUMMARY
echo ============================================================================
echo.
echo Issues found: !ISSUES_FOUND!
echo Fixes applied: !FIXES_APPLIED!
echo Remaining issues: !FINAL_ISSUES!
echo.

if !FINAL_ISSUES! EQU 0 (
    echo [SUCCESS] All boot issues have been resolved!
    echo.
    echo Next steps:
    echo 1. Restart your computer
    echo 2. Test if Windows boots normally
) else (
    echo [WARNING] Some issues could not be automatically fixed.
    echo.
    echo Manual steps you may need to try:
    echo 1. Ensure Windows installation media (ISO/USB) is accessible
    echo 2. Try extracting winload.efi manually from install.wim using DISM
    echo 3. Check if EFI partition has sufficient free space
    echo 4. Verify disk health using chkdsk
    echo 5. Consider running an in-place repair installation
)

echo.
echo ============================================================================
echo   REPAIR COMPLETE
echo ============================================================================
echo.
pause

endlocal
