@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM FIX_BCD_NOT_FOUND.cmd - Targeted Fix for Missing BCD File
REM Handles: "The system cannot find the file specified" error from bcdedit
REM ============================================================================

echo.
echo ============================================================================
echo   FIX BCD NOT FOUND - Targeted Repair
echo ============================================================================
echo.
echo This script fixes the error:
echo   "The boot configuration data store could not be opened."
echo   "The system cannot find the file specified."
echo.
echo This means the BCD file is completely missing, not just corrupted.
echo.
pause

REM Find Windows installation
echo.
echo Scanning for Windows installations...
set "TARGET_DRIVE="
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%d:\Windows\System32\ntoskrnl.exe" (
        if /i not "%%d"=="X" (
            set "TARGET_DRIVE=%%d"
            echo   Found Windows on %%d: drive
            goto :found_windows
        )
    )
)

if "!TARGET_DRIVE!"=="" (
    echo.
    echo [ERROR] No Windows installation found automatically.
    set /p TARGET_DRIVE="Enter Windows drive letter (e.g. C): "
    if "!TARGET_DRIVE!"=="" set "TARGET_DRIVE=C"
    set "TARGET_DRIVE=!TARGET_DRIVE:~0,1!"
    
    if not exist "!TARGET_DRIVE!:\Windows\System32\ntoskrnl.exe" (
        echo [ERROR] Windows not found on !TARGET_DRIVE!: drive
        pause
        exit /b 1
    )
)

:found_windows
echo.
echo Using Windows drive: !TARGET_DRIVE!:
echo.

REM Step 1: Verify winload.efi exists
echo [Step 1] Verifying winload.efi exists...
if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo   [ERROR] winload.efi is missing from Windows directory
    echo   [FIX] Attempting to restore...
    
    REM Try copy from Boot folder
    if exist "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" (
        copy "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" "!TARGET_DRIVE!:\Windows\System32\winload.efi" /y
        if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
            echo   [SUCCESS] Copied from Boot folder
        )
    )
    
    REM Try DISM if still missing
    if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [FIX] Running DISM /RestoreHealth...
        dism /Image:!TARGET_DRIVE!: /RestoreHealth
    )
    
    REM Check again
    if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [ERROR] winload.efi still missing after restore attempts
        echo   [INFO] You may need Windows installation media to extract winload.efi
        pause
        exit /b 1
    )
) else (
    echo   [OK] winload.efi found
)

echo.

REM Step 2: Mount EFI partition
echo [Step 2] Mounting EFI partition...
set "EFI_DRIVE="

REM Check if already mounted
for %%d in (S T U V W Y Z) do (
    if exist "%%d:\EFI\Microsoft\Boot" (
        set "EFI_DRIVE=%%d"
        echo   [OK] EFI partition already mounted as %%d:
        goto :efi_mounted
    )
)

REM Try to mount using diskpart
echo   [INFO] Attempting to mount EFI partition...
for %%p in (1 2) do (
    (
        echo select disk 0
        echo select partition %%p
        echo assign letter=S
        echo exit
    ) > %TEMP%\mount_efi_%%p.txt
    diskpart /s %TEMP%\mount_efi_%%p.txt >nul 2>&1
    
    if exist "S:\EFI\Microsoft\Boot" (
        set "EFI_DRIVE=S"
        echo   [OK] EFI partition mounted as S: (partition %%p)
        goto :efi_mounted
    )
)

REM Try mountvol
mountvol S: /S >nul 2>&1
if exist "S:\EFI\Microsoft\Boot" (
    set "EFI_DRIVE=S"
    echo   [OK] EFI partition mounted as S: (via mountvol)
    goto :efi_mounted
)

REM If still not mounted
echo   [ERROR] Could not mount EFI partition automatically
echo   [INFO] Please mount it manually:
echo   [INFO]   1. Run: diskpart
echo   [INFO]   2. Run: select disk 0
echo   [INFO]   3. Run: list partition
echo   [INFO]   4. Run: select partition 1 (or EFI partition number)
echo   [INFO]   5. Run: assign letter=S
echo   [INFO]   6. Run: exit
echo   [INFO]   7. Then run this script again
pause
exit /b 1

:efi_mounted
echo.

REM Step 3: Check if BCD exists
echo [Step 3] Checking BCD file status...
if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
    echo   [INFO] BCD file exists, checking if it's accessible...
    bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
    if errorlevel 1 (
        echo   [WARNING] BCD file exists but is corrupted
        echo   [FIX] Backing up and deleting corrupted BCD...
        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD.backup" (
            del "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD.backup" >nul 2>&1
        )
        copy "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD.backup" >nul 2>&1
        del "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" >nul 2>&1
        echo   [OK] Corrupted BCD backed up and deleted
    ) else (
        echo   [OK] BCD file is accessible
        echo   [INFO] BCD appears to be working. The error may be from a different BCD store.
        echo   [INFO] Try running: bcdedit /enum all
        pause
        exit /b 0
    )
) else (
    echo   [INFO] BCD file does not exist - this is the root cause
    echo   [FIX] Will create new BCD file
)

echo.

REM Step 4: Create new BCD using bcdboot
echo [Step 4] Creating new BCD file using bcdboot...
echo   [INFO] Running: bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI

if errorlevel 1 (
    echo   [ERROR] bcdboot failed
    echo   [INFO] Checking EFI partition health...
    
    REM Check if EFI partition is write-protected or corrupted
    echo   [FIX] Attempting to format EFI partition (quick format)...
    echo   [WARNING] This will delete all files on EFI partition
    echo   [WARNING] This is safe if Windows partition is intact
    pause
    
    echo Y | format !EFI_DRIVE!: /fs:FAT32 /q >nul 2>&1
    if errorlevel 1 (
        echo   [ERROR] EFI partition format failed
        echo   [INFO] EFI partition may be write-protected or in use
        pause
        exit /b 1
    )
    
    echo   [OK] EFI partition formatted
    echo   [FIX] Retrying bcdboot after format...
    bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
    if errorlevel 1 (
        echo   [ERROR] bcdboot still failed after format
        echo   [INFO] Check if winload.efi exists in: !TARGET_DRIVE!:\Windows\System32\Boot\winload.efi
        pause
        exit /b 1
    )
)

echo.

REM Step 5: Verify BCD was created
echo [Step 5] Verifying BCD file was created...
if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
    echo   [OK] BCD file exists
) else (
    echo   [ERROR] BCD file was not created
    pause
    exit /b 1
)

REM Step 6: Verify BCD is accessible
echo [Step 6] Verifying BCD is accessible...
bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
if errorlevel 1 (
    echo   [ERROR] BCD file exists but is still not accessible
    echo   [INFO] BCD may be locked or have permission issues
    pause
    exit /b 1
) else (
    echo   [SUCCESS] BCD file is accessible
)

REM Step 7: Verify winload.efi in EFI partition
echo [Step 7] Verifying winload.efi in EFI partition...
if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
    echo   [SUCCESS] winload.efi found in EFI partition
) else (
    echo   [WARNING] winload.efi not found in EFI partition
    echo   [INFO] bcdboot may not have copied it
    echo   [INFO] Source template may be missing: !TARGET_DRIVE!:\Windows\System32\Boot\winload.efi
)

echo.
echo ============================================================================
echo   REPAIR COMPLETE
echo ============================================================================
echo.
echo Summary:
echo   - Windows drive: !TARGET_DRIVE!:
echo   - EFI partition: !EFI_DRIVE!:
echo   - BCD file: Created and verified
echo.
echo Next steps:
echo   1. Restart your computer
echo   2. Test if Windows boots normally
echo   3. If problems persist, check BIOS/UEFI boot order
echo.
pause

endlocal
