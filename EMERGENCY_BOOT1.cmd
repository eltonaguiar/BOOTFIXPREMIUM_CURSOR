@echo off
REM ============================================================================
REM EMERGENCY_BOOT1.cmd - Ultra-Simple Boot Repair
REM Minimal logic, maximum reliability
REM ============================================================================

echo.
echo ============================================================================
echo   EMERGENCY BOOT REPAIR - SIMPLE MODE
echo ============================================================================
echo.
echo This tool will attempt to fix boot issues using basic commands.
echo.
echo WARNING: Only run this from Windows Recovery Environment (WinRE/WinPE)
echo Running from live Windows can damage your system!
echo.
pause

REM Get drive letter from user
echo.
set /p DRIVE="Enter your Windows drive letter (e.g. C): "
if "%DRIVE%"=="" set "DRIVE=C"
set "DRIVE=%DRIVE:~0,1%"

echo.
echo Using drive: %DRIVE%:
echo.

REM Check if Windows exists
if not exist "%DRIVE%:\Windows\System32\ntoskrnl.exe" (
    echo ERROR: Windows not found on %DRIVE%: drive
    pause
    exit /b 1
)

echo Step 1: Checking winload.efi...
if not exist "%DRIVE%:\Windows\System32\winload.efi" (
    echo [MISSING] winload.efi not found
    echo.
    echo Step 1a: Trying to copy from Boot folder...
    if exist "%DRIVE%:\Windows\System32\Boot\winload.efi" (
        copy "%DRIVE%:\Windows\System32\Boot\winload.efi" "%DRIVE%:\Windows\System32\winload.efi" /y
        echo [OK] Copied from Boot folder
    ) else (
        echo [FAIL] Boot folder copy failed
    )
) else (
    echo [OK] winload.efi found
)

echo.
echo Step 2: Running DISM...
dism /Image:%DRIVE%: /RestoreHealth
echo.

echo Step 3: Running SFC...
sfc /ScanNow /OffBootDir=%DRIVE%: /OffWinDir=%DRIVE%:\Windows
echo.

echo Step 4: Mounting EFI partition...
echo select disk 0 > %TEMP%\mount.txt
echo list partition >> %TEMP%\mount.txt
echo select partition 1 >> %TEMP%\mount.txt
echo assign letter=S >> %TEMP%\mount.txt
echo exit >> %TEMP%\mount.txt
diskpart /s %TEMP%\mount.txt >nul 2>&1

if exist "S:\EFI\Microsoft\Boot\BCD" (
    echo [OK] EFI partition mounted as S:
) else (
    echo [WARNING] Could not mount EFI partition
    echo You may need to mount it manually using diskpart
)

echo.
echo Step 5: Running bcdboot...
bcdboot %DRIVE%:\Windows /s S: /f UEFI
echo.

echo Step 6: Verifying winload.efi in EFI partition...
if exist "S:\EFI\Microsoft\Boot\winload.efi" (
    echo [SUCCESS] winload.efi found in EFI partition
) else (
    echo [WARNING] winload.efi not found in EFI partition
)

echo.
echo Step 7: Rebuilding BCD...
if exist "S:\EFI\Microsoft\Boot\BCD" (
    bcdedit /store "S:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
    if errorlevel 1 (
        echo [WARNING] BCD appears corrupted, attempting rebuild...
        bcdboot %DRIVE%:\Windows /s S: /f UEFI
    ) else (
        echo [OK] BCD is readable
    )
) else (
    echo [WARNING] BCD file not found, creating new one...
    bcdboot %DRIVE%:\Windows /s S: /f UEFI
)

echo.
echo ============================================================================
echo   REPAIR COMPLETE
echo ============================================================================
echo.
echo Next steps:
echo 1. Restart your computer
echo 2. Check if Windows boots normally
echo 3. If problems persist, try EMERGENCY_BOOT2.cmd or EMERGENCY_BOOT3.cmd
echo.
pause
