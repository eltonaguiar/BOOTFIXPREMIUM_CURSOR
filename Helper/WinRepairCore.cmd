@echo off
REM WinRepairCore.cmd - CMD Batch Script Fallback Functions
REM For use when PowerShell is not available in WinRE

setlocal enabledelayedexpansion

REM ============================================================================
REM NETWORK ENABLEMENT FUNCTIONS
REM ============================================================================

:EnableNetwork
REM Enable network adapters using netsh
echo.
echo Enabling network adapters...
echo.

REM List interfaces
netsh interface show interface >nul 2>&1
if errorlevel 1 (
    echo ERROR: Could not access network interfaces.
    echo Network drivers may not be loaded.
    goto :eof
)

REM Enable all disabled interfaces
for /f "tokens=1,2" %%a in ('netsh interface show interface ^| findstr /i "Disabled"') do (
    echo Enabling interface: %%a
    netsh interface set interface name="%%a" admin=enable >nul 2>&1
    if errorlevel 1 (
        echo   Failed to enable %%a
    ) else (
        echo   Successfully enabled %%a
    )
)

REM Test connectivity
echo.
echo Testing internet connectivity...
ping -n 1 8.8.8.8 >nul 2>&1
if errorlevel 1 (
    ping -n 1 1.1.1.1 >nul 2>&1
    if errorlevel 1 (
        echo WARNING: No internet connectivity detected.
        echo Network adapters may be enabled but not connected.
    ) else (
        echo Internet connectivity confirmed (reached 1.1.1.1)
    )
) else (
    echo Internet connectivity confirmed (reached 8.8.8.8)
)

goto :eof

:CheckInternet
REM Test internet connectivity
echo.
echo Testing internet connectivity...
ping -n 2 8.8.8.8 >nul 2>&1
if errorlevel 1 (
    ping -n 2 1.1.1.1 >nul 2>&1
    if errorlevel 1 (
        echo No internet connectivity detected.
        exit /b 1
    ) else (
        echo Internet connectivity confirmed.
        exit /b 0
    )
) else (
    echo Internet connectivity confirmed.
    exit /b 0
)

:OpenBrowser
REM Attempt to open browser for ChatGPT
echo.
echo Attempting to open ChatGPT help page...
echo.

REM Try default browser
start https://chat.openai.com >nul 2>&1
if errorlevel 1 (
    REM Try Internet Explorer
    start iexplore.exe https://chat.openai.com >nul 2>&1
    if errorlevel 1 (
        echo Browser not available in this environment.
        echo.
        echo ===============================================================
        echo CHATGPT HELP - COMMAND-LINE METHOD
        echo ===============================================================
        echo.
        echo Browser is not available. Use one of these methods:
        echo.
        echo METHOD 1: Use Another Device
        echo ---------------------------------------------------------------
        echo 1. On your phone or another computer, open: https://chat.openai.com
        echo 2. Ask: "My Windows installation failed. How do I check setup logs?"
        echo 3. Share the error codes you find in the logs
        echo.
        echo METHOD 2: Manual URL
        echo ---------------------------------------------------------------
        echo Write down this URL and open it on another device:
        echo https://chat.openai.com
        echo.
        echo Suggested questions to ask:
        echo - "How do I check Windows setup error logs?"
        echo - "Windows installation failed with error code [your code]"
        echo - "How to fix Windows boot issues in recovery environment?"
        echo.
        echo ===============================================================
        exit /b 1
    ) else (
        echo Opened ChatGPT in Internet Explorer
        exit /b 0
    )
) else (
    echo Opened ChatGPT in default browser
    exit /b 0
)

REM ============================================================================
REM INSTALL FAILURE ANALYSIS
REM ============================================================================

:CheckInstallFailure
REM Basic install failure log reading using findstr
set "TARGET_DRIVE=%~1"
if "%TARGET_DRIVE%"=="" set "TARGET_DRIVE=C"

echo.
echo ================================================================
echo WINDOWS INSTALLATION FAILURE ANALYSIS
echo Target Drive: %TARGET_DRIVE%:
echo ================================================================
echo.

REM Check for setup logs
set "LOG_FOUND=0"

if exist "%TARGET_DRIVE%:\Windows\Panther\setuperr.log" (
    echo [OK] Found: %TARGET_DRIVE%:\Windows\Panther\setuperr.log
    echo.
    echo Recent errors:
    echo ----------------------------------------------------------------
    findstr /i /c:"error" /c:"failed" /c:"fatal" /c:"exception" "%TARGET_DRIVE%:\Windows\Panther\setuperr.log" | findstr /i "0x" | more
    set "LOG_FOUND=1"
)

if exist "%TARGET_DRIVE%:\$WINDOWS.~BT\Sources\Panther\setuperr.log" (
    echo.
    echo [OK] Found: %TARGET_DRIVE%:\$WINDOWS.~BT\Sources\Panther\setuperr.log
    echo.
    echo Recent errors:
    echo ----------------------------------------------------------------
    findstr /i /c:"error" /c:"failed" /c:"fatal" /c:"exception" "%TARGET_DRIVE%:\$WINDOWS.~BT\Sources\Panther\setuperr.log" | findstr /i "0x" | more
    set "LOG_FOUND=1"
)

if "%LOG_FOUND%"=="0" (
    echo [WARNING] No setup error logs found in common locations.
    echo This may indicate the installation never started.
)

echo.
echo ================================================================
echo END OF ANALYSIS
echo ================================================================

goto :eof

REM ============================================================================
REM WARNING DISPLAY
REM ============================================================================

:ShowWarning
REM Display warnings in CMD (using echo and choice)
set "WARNING_TITLE=%~1"
set "WARNING_MSG=%~2"

echo.
echo ================================================================
echo %WARNING_TITLE%
echo ================================================================
echo.
echo %WARNING_MSG%
echo.
echo ================================================================
echo.
choice /C YN /M "Do you want to proceed"
if errorlevel 2 exit /b 1
if errorlevel 1 exit /b 0
exit /b 1

REM ============================================================================
REM MAIN MENU (if called directly)
REM ============================================================================

:MainMenu
:loop
cls
echo.
echo ================================================================
echo   MIRACLE BOOT - CMD MODE (PowerShell Not Available)
echo ================================================================
echo.
echo 1) Enable Network/Internet
echo 2) Check Internet Connectivity
echo 3) Open ChatGPT Help
echo 4) Check Windows Install Failure Reasons
echo 5) ONE-CLICK BOOT FIX
echo Q) Quit
echo.

set /p choice="Select: "

if /i "%choice%"=="1" (
    call :EnableNetwork
    pause
    goto :loop
)

if /i "%choice%"=="2" (
    call :CheckInternet
    pause
    goto :loop
)

if /i "%choice%"=="3" (
    call :OpenBrowser
    pause
    goto :loop
)

if /i "%choice%"=="4" (
    set /p drive="Enter target drive letter (e.g. C, or press Enter for C): "
    if "!drive!"=="" set "drive=C"
    call :CheckInstallFailure "!drive!"
    pause
    goto :loop
)

if /i "%choice%"=="5" (
    call :OneClickBootFix
    pause
    goto :loop
)

if /i "%choice%"=="Q" goto :eof
if /i "%choice%"=="q" goto :eof

echo Invalid selection.
timeout /t 2 >nul
goto :loop

REM ============================================================================
REM ONE-CLICK BOOT FIX
REM ============================================================================

:OneClickBootFix
REM Automated boot repair with safety checks
echo.
echo ================================================================
echo   ONE-CLICK BOOT FIX
echo ================================================================
echo.
echo WARNING: This will attempt to repair boot files on your Windows installation.
echo.

REM Safety interlock: if running in a live Windows OS (not WinRE/WinPE X:),
REM require explicit confirmation before allowing boot writes.
if /I not "%SystemDrive%"=="X:" (
    echo SAFETY WARNING: You are running from a live Windows OS (%SystemDrive%).
    echo Destructive boot repairs can brick the system if misused.
    echo.
    set "BRICKME_OK="
    set /p BRICKME_OK="Type BRICKME to continue (or press Enter to cancel): "
    if /I not "!BRICKME_OK!"=="BRICKME" (
        echo Aborting by user choice. No changes made.
        goto :eof
    )
    echo.
)

REM Prompt for target drive
echo Detecting Windows installations...
echo.
echo Available drives:
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%d:\Windows\System32\ntoskrnl.exe" (
        if /I not "%%d"=="X" (
            echo   %%d: - Windows installation found
        )
    )
)
echo.
set /p target_drive="Enter target Windows drive letter (e.g. C, or press Enter for C): "
if "!target_drive!"=="" set "target_drive=C"
set "target_drive=!target_drive:~0,1!"

REM Verify drive exists and has Windows
if not exist "!target_drive!:\Windows\System32\ntoskrnl.exe" (
    echo ERROR: Windows installation not found on !target_drive!: drive.
    echo Please verify the drive letter and try again.
    goto :eof
)

echo.
echo Target drive: !target_drive!:
echo.

REM Check if bootrec.exe is available (WinRE/WinPE only)
where bootrec.exe >nul 2>&1
if errorlevel 1 (
    echo WARNING: bootrec.exe is not available in this environment.
    echo bootrec.exe is only available in Windows Recovery Environment (WinRE/WinPE).
    echo.
        echo Alternative: Use bcdboot to repair boot files.
        echo.
        set /p use_bcdboot="Use bcdboot instead? (Y/N): "
        if /I "!use_bcdboot!"=="Y" (
            echo.
            REM Check if winload.efi exists in Windows directory
            if not exist "!target_drive!:\Windows\System32\winload.efi" (
                echo [WARNING] winload.efi is missing from Windows directory.
                echo Attempting to restore winload.efi using DISM and SFC...
                echo.
                echo Running: DISM /Image:!target_drive!: /RestoreHealth
                dism /Image:!target_drive!: /RestoreHealth
                if errorlevel 1 (
                    echo [WARNING] DISM restore health reported issues.
                )
                echo.
                echo Running: SFC /ScanNow /OffBootDir=!target_drive!: /OffWinDir=!target_drive!:\Windows
                sfc /ScanNow /OffBootDir=!target_drive!: /OffWinDir=!target_drive!:\Windows
                if errorlevel 1 (
                    echo [WARNING] SFC reported issues.
                )
                echo.
                REM Check if winload.efi was restored
                if exist "!target_drive!:\Windows\System32\winload.efi" (
                    echo [SUCCESS] winload.efi restored to Windows directory.
                ) else (
                    echo [WARNING] winload.efi still missing after DISM/SFC.
                    echo You may need to extract it from Windows installation media.
                )
                echo.
            )
            
            echo Attempting to mount EFI partition...
            call :MountEFIPartition "!target_drive!"
            if errorlevel 1 (
                echo ERROR: Could not mount EFI partition.
                echo Please mount it manually using diskpart.
                goto :eof
            )
            echo.
            echo Running: bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
            bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
            if errorlevel 1 (
                echo ERROR: bcdboot failed.
            ) else (
                echo.
                echo [SUCCESS] Boot files repaired successfully.
                REM Verify winload.efi was copied to EFI partition
                if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                    echo [SUCCESS] Verified: winload.efi is now present in EFI partition.
                ) else (
                    echo [WARNING] winload.efi not found in EFI partition after bcdboot.
                )
            )
        ) else (
            echo Aborted by user.
        )
        goto :eof
    )

REM bootrec.exe is available - use it
echo Running boot repair commands...
echo.

echo Step 1: Scanning for Windows installations...
bootrec /scanos
if errorlevel 1 (
    echo WARNING: bootrec /scanos reported issues.
)
echo.

echo Step 2: Rebuilding Boot Configuration Data (BCD)...
bootrec /rebuildbcd
if errorlevel 1 (
    echo WARNING: bootrec /rebuildbcd reported issues.
)
echo.

echo Step 3: Fixing boot sector...
bootrec /fixboot
if errorlevel 1 (
    echo WARNING: bootrec /fixboot reported issues.
)
echo.

        echo Step 4: Fixing Master Boot Record (MBR)...
        bootrec /fixmbr
        if errorlevel 1 (
            echo WARNING: bootrec /fixmbr reported issues.
        )
        echo.

        REM Check if winload.efi exists and restore if missing
        echo Step 5: Checking for missing winload.efi...
        if not exist "!target_drive!:\Windows\System32\winload.efi" (
            echo [WARNING] winload.efi is missing from Windows directory.
            echo Attempting to restore winload.efi using DISM and SFC...
            echo.
            echo Running: DISM /Image:!target_drive!: /RestoreHealth
            dism /Image:!target_drive!: /RestoreHealth
            if errorlevel 1 (
                echo [WARNING] DISM restore health reported issues.
            )
            echo.
            echo Running: SFC /ScanNow /OffBootDir=!target_drive!: /OffWinDir=!target_drive!:\Windows
            sfc /ScanNow /OffBootDir=!target_drive!: /OffWinDir=!target_drive!:\Windows
            if errorlevel 1 (
                echo [WARNING] SFC reported issues.
            )
            echo.
            REM Check if winload.efi was restored
            if exist "!target_drive!:\Windows\System32\winload.efi" (
                echo [SUCCESS] winload.efi restored to Windows directory.
                echo.
                echo Attempting to copy winload.efi to EFI partition using bcdboot...
                call :MountEFIPartition "!target_drive!"
                if not errorlevel 1 (
                    echo Running: bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
                    bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
                    if not errorlevel 1 (
                        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                            echo [SUCCESS] winload.efi copied to EFI partition.
                        )
                    )
                )
            ) else (
                echo [WARNING] winload.efi still missing after DISM/SFC.
                echo You may need to extract it from Windows installation media.
            )
        ) else (
            echo [OK] winload.efi found in Windows directory.
        )
        echo.

        echo ================================================================
        echo BOOT REPAIR COMPLETE
        echo ================================================================
        echo.
        echo Next steps:
        echo 1. Restart your computer
        echo 2. Test if Windows boots normally
        echo 3. If problems persist, consider running an in-place repair installation
        echo.

        goto :eof

:MountEFIPartition
REM Attempts to mount EFI partition for target drive
REM Usage: call :MountEFIPartition "C"
setlocal enabledelayedexpansion
set "TARGET_DRIVE=%~1"
set "EFI_DRIVE="

REM Try to find EFI partition using diskpart
echo list disk > %TEMP%\mount_efi.txt
echo list partition >> %TEMP%\mount_efi.txt
echo exit >> %TEMP%\mount_efi.txt

REM Check if EFI partition already has a drive letter
for %%d in (S T U V W Y Z) do (
    if exist "%%d:\EFI\Microsoft\Boot\BCD" (
        set "EFI_DRIVE=%%d"
        goto :efi_found
    )
)

REM Try to assign a drive letter (start from S:)
for %%d in (S T U V W Y Z) do (
    diskpart /s %TEMP%\mount_efi.txt | findstr /i "EFI" >nul 2>&1
    if errorlevel 1 (
        REM Try to assign drive letter using diskpart script
        (
            echo select disk 0
            echo list partition
            echo select partition 1
            echo assign letter=%%d
            echo exit
        ) > %TEMP%\assign_efi.txt
        diskpart /s %TEMP%\assign_efi.txt >nul 2>&1
        if exist "%%d:\EFI\Microsoft\Boot\BCD" (
            set "EFI_DRIVE=%%d"
            goto :efi_found
        )
    )
)

:efi_found
if "!EFI_DRIVE!"=="" (
    echo ERROR: Could not mount EFI partition automatically.
    echo Please mount it manually using diskpart:
    echo   1. Run: diskpart
    echo   2. Run: list disk
    echo   3. Run: select disk 0
    echo   4. Run: list partition
    echo   5. Run: select partition 1 (or the EFI partition number)
    echo   6. Run: assign letter=S
    echo   7. Run: exit
    endlocal
    exit /b 1
) else (
    echo EFI partition mounted as !EFI_DRIVE!:
    endlocal & set "EFI_DRIVE=%EFI_DRIVE%"
    exit /b 0
)

REM If script is run directly (not called as function), show menu
if "%~1"=="" goto :MainMenu

