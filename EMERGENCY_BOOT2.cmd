@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM EMERGENCY_BOOT2.cmd - Advanced Boot Repair with Windows Detection
REM Finds Windows installations and checks for common issues
REM ============================================================================

echo.
echo ============================================================================
echo   EMERGENCY BOOT REPAIR - ADVANCED MODE
echo ============================================================================
echo.
echo This tool will:
echo   1. Find all Windows installations
echo   2. Let you choose which one to repair
echo   3. Check for common boot issues (winload.efi, BCD, EFI partition)
echo   4. Attempt to fix detected issues
echo.
echo WARNING: Only run this from Windows Recovery Environment (WinRE/WinPE)
echo.
pause

REM Find Windows installations
echo.
echo Scanning for Windows installations...
echo.
set "INSTALL_COUNT=0"
set "INSTALL_LIST="

for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%d:\Windows\System32\ntoskrnl.exe" (
        if /i not "%%d"=="X" (
            set /a INSTALL_COUNT+=1
            set "INSTALL_LIST=!INSTALL_LIST! %%d"
            echo   [!INSTALL_COUNT!] %%d: - Windows installation found
        )
    )
)

if !INSTALL_COUNT! EQU 0 (
    echo.
    echo [WARNING] No Windows installations found automatically.
    echo.
    set /p MANUAL_DRIVE="Enter Windows drive letter manually (e.g. C): "
    if "!MANUAL_DRIVE!"=="" set "MANUAL_DRIVE=C"
    set "MANUAL_DRIVE=!MANUAL_DRIVE:~0,1!"
    
    if not exist "!MANUAL_DRIVE!:\Windows\System32\ntoskrnl.exe" (
        echo ERROR: Windows not found on !MANUAL_DRIVE!: drive
        pause
        exit /b 1
    )
    
    set "TARGET_DRIVE=!MANUAL_DRIVE!"
    goto :start_repair
)

echo.
if !INSTALL_COUNT! EQU 1 (
    echo Only one Windows installation found. Using it automatically.
    for %%d in (!INSTALL_LIST!) do set "TARGET_DRIVE=%%d"
    goto :start_repair
)

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
        goto :start_repair
    )
)

echo Invalid selection.
pause
exit /b 1

:start_repair
echo.
echo ============================================================================
echo   DIAGNOSING BOOT ISSUES - !TARGET_DRIVE!: Drive
echo ============================================================================
echo.

set "ISSUES_FOUND=0"
set "FIXES_APPLIED=0"

REM Check 1: winload.efi in Windows directory
echo [Check 1] Checking winload.efi in Windows directory...
if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo   [FAIL] winload.efi missing from Windows directory
    set /a ISSUES_FOUND+=1
    
    echo   [FIX] Attempting to restore winload.efi...
    
    REM Try copy from Boot folder
    if exist "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" (
        copy "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" "!TARGET_DRIVE!:\Windows\System32\winload.efi" /y
        if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
            echo   [SUCCESS] Copied from Boot folder
            set /a FIXES_APPLIED+=1
        )
    )
    
    REM Try DISM if copy failed
    if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [FIX] Running DISM /RestoreHealth...
        dism /Image:!TARGET_DRIVE!: /RestoreHealth >nul 2>&1
        if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
            echo   [SUCCESS] DISM restored winload.efi
            set /a FIXES_APPLIED+=1
        ) else (
            echo   [WARNING] DISM did not restore winload.efi
        )
    )
    
    REM Try SFC if still missing
    if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [FIX] Running SFC /ScanNow...
        sfc /ScanNow /OffBootDir=!TARGET_DRIVE!: /OffWinDir=!TARGET_DRIVE!:\Windows >nul 2>&1
        if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
            echo   [SUCCESS] SFC restored winload.efi
            set /a FIXES_APPLIED+=1
        ) else (
            echo   [WARNING] SFC did not restore winload.efi
        )
    )
) else (
    echo   [OK] winload.efi found
)

echo.

REM Check 2: EFI partition
echo [Check 2] Checking EFI partition...
set "EFI_DRIVE="
for %%d in (S T U V W Y Z) do (
    if exist "%%d:\EFI\Microsoft\Boot\BCD" (
        set "EFI_DRIVE=%%d"
        goto :efi_found
    )
)

REM Try to mount EFI partition
echo   [INFO] EFI partition not mounted, attempting to mount...
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
    echo   [OK] EFI partition mounted as S:
) else (
    echo   [FAIL] Could not mount EFI partition
    set /a ISSUES_FOUND+=1
    echo   [INFO] You may need to mount it manually using diskpart
)

:efi_found
if "!EFI_DRIVE!"=="" (
    echo   [FAIL] EFI partition not accessible
    set /a ISSUES_FOUND+=1
) else (
    echo   [OK] EFI partition accessible as !EFI_DRIVE!:
)

echo.

REM Check 3: BCD file
if not "!EFI_DRIVE!"=="" (
    echo [Check 3] Checking BCD file...
    if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
        bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
        if errorlevel 1 (
            echo   [FAIL] BCD file is corrupted or unreadable
            set /a ISSUES_FOUND+=1
            
            echo   [FIX] Attempting to rebuild BCD...
            bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
            if errorlevel 1 (
                echo   [WARNING] bcdboot failed, trying EFI partition format...
                echo Y | format !EFI_DRIVE!: /fs:FAT32 /q >nul 2>&1
                bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
                if not errorlevel 1 (
                    echo   [SUCCESS] BCD rebuilt after EFI format
                    set /a FIXES_APPLIED+=1
                )
            ) else (
                echo   [SUCCESS] BCD rebuilt
                set /a FIXES_APPLIED+=1
            )
        ) else (
            echo   [OK] BCD file is readable
        )
    ) else (
        echo   [FAIL] BCD file missing from EFI partition
        set /a ISSUES_FOUND+=1
        
        echo   [FIX] Creating new BCD...
        bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
        if not errorlevel 1 (
            echo   [SUCCESS] BCD created
            set /a FIXES_APPLIED+=1
        ) else (
            echo   [WARNING] bcdboot failed
        )
    )
    echo.
)

REM Check 4: winload.efi in EFI partition
if not "!EFI_DRIVE!"=="" (
    echo [Check 4] Checking winload.efi in EFI partition...
    if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
        echo   [OK] winload.efi found in EFI partition
    ) else (
        echo   [FAIL] winload.efi missing from EFI partition
        set /a ISSUES_FOUND+=1
        
        if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
            echo   [FIX] Copying winload.efi to EFI partition...
            bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
            if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                echo   [SUCCESS] winload.efi copied to EFI partition
                set /a FIXES_APPLIED+=1
            ) else (
                echo   [WARNING] bcdboot did not copy winload.efi
            )
        ) else (
            echo   [WARNING] Cannot copy winload.efi - source file missing
        )
    )
    echo.
)

REM Summary
echo ============================================================================
echo   DIAGNOSIS SUMMARY
echo ============================================================================
echo.
echo Issues found: !ISSUES_FOUND!
echo Fixes applied: !FIXES_APPLIED!
echo.

if !ISSUES_FOUND! EQU 0 (
    echo [SUCCESS] No boot issues detected!
) else if !FIXES_APPLIED! GTR 0 (
    echo [PARTIAL] Some issues were fixed. Please restart and test.
) else (
    echo [WARNING] Issues detected but could not be automatically fixed.
    echo Consider trying EMERGENCY_BOOT3.cmd for advanced repair options.
)

echo.
echo ============================================================================
echo   REPAIR COMPLETE
echo ============================================================================
echo.
pause

endlocal
