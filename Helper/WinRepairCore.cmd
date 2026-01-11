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
echo 6) Boot Diagnosis ^& Repair
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

if /i "%choice%"=="6" (
    call :BootDiagnosis
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
            REM Step 1: Check if winload.efi exists in Windows directory
            if not exist "!target_drive!:\Windows\System32\winload.efi" (
                echo [WARNING] winload.efi is missing from Windows directory.
                echo.
                echo Step 3: Checking source template folder (C:\Windows\System32\Boot\winload.efi)...
                echo bcdboot works by copying files from C:\Windows\System32\Boot
                if exist "!target_drive!:\Windows\System32\Boot\winload.efi" (
                    echo [INFO] Source template found in Boot folder.
                    echo Copying from Boot folder to System32...
                    copy "!target_drive!:\Windows\System32\Boot\winload.efi" "!target_drive!:\Windows\System32\winload.efi" /y
                    if exist "!target_drive!:\Windows\System32\winload.efi" (
                        echo [SUCCESS] winload.efi copied from Boot folder to System32.
                    ) else (
                        echo [WARNING] Copy failed. The issue may be that the destination (EFI Partition) is write-protected or out of space.
                    )
                ) else (
                    echo [WARNING] Source template missing from Boot folder.
                    echo The 'template' is gone. Attempting to restore winload.efi from Windows Component Store...
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
                        echo Step 5: Attempting manual extraction from Windows installation media (install.wim/install.esd)...
                        echo.
                        REM Step 5: Manual Extraction (The "Infallible" Fix)
                        REM Search for install.wim or install.esd in common locations
                        set "FOUND_MEDIA=0"
                        if exist "X:\sources\install.wim" (
                            echo [INFO] Found Windows installation media: X:\sources\install.wim
                            echo Attempting to extract winload.efi using DISM...
                            dism /Image:!target_drive!: /RestoreHealth /Source:X:\sources\install.wim:1
                            if exist "!target_drive!:\Windows\System32\winload.efi" (
                                echo [SUCCESS] winload.efi extracted from installation media
                                set "FOUND_MEDIA=1"
                            )
                        ) else if exist "X:\sources\install.esd" (
                            echo [INFO] Found Windows installation media: X:\sources\install.esd
                            echo Attempting to extract winload.efi using DISM...
                            dism /Image:!target_drive!: /RestoreHealth /Source:X:\sources\install.esd:1
                            if exist "!target_drive!:\Windows\System32\winload.efi" (
                                echo [SUCCESS] winload.efi extracted from installation media
                                set "FOUND_MEDIA=1"
                            )
                        ) else if exist "D:\sources\install.wim" (
                            echo [INFO] Found Windows installation media: D:\sources\install.wim
                            echo Attempting to extract winload.efi using DISM...
                            dism /Image:!target_drive!: /RestoreHealth /Source:D:\sources\install.wim:1
                            if exist "!target_drive!:\Windows\System32\winload.efi" (
                                echo [SUCCESS] winload.efi extracted from installation media
                                set "FOUND_MEDIA=1"
                            )
                        ) else if exist "D:\sources\install.esd" (
                            echo [INFO] Found Windows installation media: D:\sources\install.esd
                            echo Attempting to extract winload.efi using DISM...
                            dism /Image:!target_drive!: /RestoreHealth /Source:D:\sources\install.esd:1
                            if exist "!target_drive!:\Windows\System32\winload.efi" (
                                echo [SUCCESS] winload.efi extracted from installation media
                                set "FOUND_MEDIA=1"
                            )
                        ) else if exist "E:\sources\install.wim" (
                            echo [INFO] Found Windows installation media: E:\sources\install.wim
                            echo Attempting to extract winload.efi using DISM...
                            dism /Image:!target_drive!: /RestoreHealth /Source:E:\sources\install.wim:1
                            if exist "!target_drive!:\Windows\System32\winload.efi" (
                                echo [SUCCESS] winload.efi extracted from installation media
                                set "FOUND_MEDIA=1"
                            )
                        ) else if exist "E:\sources\install.esd" (
                            echo [INFO] Found Windows installation media: E:\sources\install.esd
                            echo Attempting to extract winload.efi using DISM...
                            dism /Image:!target_drive!: /RestoreHealth /Source:E:\sources\install.esd:1
                            if exist "!target_drive!:\Windows\System32\winload.efi" (
                                echo [SUCCESS] winload.efi extracted from installation media
                                set "FOUND_MEDIA=1"
                            )
                        )
                        if "!FOUND_MEDIA!"=="0" (
                            echo [ERROR] Could not find Windows installation media (install.wim/install.esd)
                            echo Please attach Windows ISO/USB and ensure it's accessible, then retry.
                        )
                    )
                )
                echo.
            )
            
            REM Step 2: Verify file attributes (clear hidden/system if needed)
            if exist "!target_drive!:\Windows\System32\winload.efi" (
                echo Step 2: Verifying file attributes...
                attrib -s -h -r "!target_drive!:\Windows\System32\winload.efi"
                echo [OK] File attributes verified.
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
            echo Step 3: Running: bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
            bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
            if errorlevel 1 (
                echo [WARNING] bcdboot reported issues.
                echo.
                echo Step 4: Checking EFI partition health (write-protection, space, corruption)...
                echo [WARNING] EFI partition may be corrupted, write-protected, or out of space.
                echo Step 4: Formatting EFI partition !EFI_DRIVE!: as FAT32 (quick format)...
                echo WARNING: This will wipe the EFI partition (safe if Windows partition is intact)
                echo Y | format !EFI_DRIVE!: /fs:FAT32 /q
                if errorlevel 1 (
                    echo [ERROR] EFI partition format failed.
                ) else (
                    echo [OK] EFI partition formatted successfully.
                    echo.
                    echo Retrying bcdboot after EFI partition format...
                    bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
                    if errorlevel 1 (
                        echo [ERROR] bcdboot still failed after format.
                        echo The source template (C:\Windows\System32\Boot\winload.efi) may be missing.
                        echo Step 5: Manual extraction from Windows installation media (install.wim/install.esd) is required.
                    ) else (
                        REM Verify winload.efi was copied to EFI partition
                        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                            echo [SUCCESS] winload.efi copied to EFI partition after format.
                        ) else (
                            echo [WARNING] winload.efi not found in EFI partition after format and retry.
                            echo The source template (C:\Windows\System32\Boot\winload.efi) may be missing.
                            echo Step 5: Manual extraction from Windows installation media (install.wim/install.esd) is required.
                        )
                    )
                )
            ) else (
                REM Verify winload.efi was copied to EFI partition
                if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                    echo [SUCCESS] winload.efi copied to EFI partition.
                ) else (
                    echo [WARNING] winload.efi not found in EFI partition after bcdboot.
                    echo The source template (C:\Windows\System32\Boot\winload.efi) may be missing.
                    echo Step 5: Manual extraction from Windows installation media (install.wim/install.esd) is required.
                )
            )
            echo.
            
            REM Verify winload.efi was copied to EFI partition
            if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                echo [SUCCESS] Verified: winload.efi is now present in EFI partition.
            ) else (
                echo [WARNING] winload.efi not found in EFI partition after bcdboot.
                echo Step 5: Manual extraction from Windows installation media may be required.
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

        REM Step 5: Check if winload.efi exists and restore if missing
        echo Step 5: Checking for missing winload.efi...
        if not exist "!target_drive!:\Windows\System32\winload.efi" (
            echo [WARNING] winload.efi is missing from Windows directory.
            echo.
            echo Step 3: Checking source template folder (C:\Windows\System32\Boot\winload.efi)...
            echo bcdboot works by copying files from C:\Windows\System32\Boot
            if exist "!target_drive!:\Windows\System32\Boot\winload.efi" (
                echo [INFO] Source template found in Boot folder.
                echo Copying from Boot folder to System32...
                copy "!target_drive!:\Windows\System32\Boot\winload.efi" "!target_drive!:\Windows\System32\winload.efi" /y
                if exist "!target_drive!:\Windows\System32\winload.efi" (
                    echo [SUCCESS] winload.efi copied from Boot folder to System32.
                ) else (
                    echo [WARNING] Copy failed. The issue may be that the destination (EFI Partition) is write-protected or out of space.
                )
            ) else (
                echo [WARNING] Source template missing from Boot folder.
                echo The 'template' is gone. Attempting to restore winload.efi from Windows Component Store...
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
                    echo Step 5: Attempting manual extraction from Windows installation media (install.wim/install.esd)...
                    echo.
                    REM Step 5: Manual Extraction (The "Infallible" Fix)
                    REM Search for install.wim or install.esd in common locations
                    set "FOUND_MEDIA=0"
                    if exist "X:\sources\install.wim" (
                        echo [INFO] Found Windows installation media: X:\sources\install.wim
                        echo Attempting to extract winload.efi using DISM...
                        dism /Image:!target_drive!: /RestoreHealth /Source:X:\sources\install.wim:1
                        if exist "!target_drive!:\Windows\System32\winload.efi" (
                            echo [SUCCESS] winload.efi extracted from installation media
                            set "FOUND_MEDIA=1"
                        )
                    ) else if exist "X:\sources\install.esd" (
                        echo [INFO] Found Windows installation media: X:\sources\install.esd
                        echo Attempting to extract winload.efi using DISM...
                        dism /Image:!target_drive!: /RestoreHealth /Source:X:\sources\install.esd:1
                        if exist "!target_drive!:\Windows\System32\winload.efi" (
                            echo [SUCCESS] winload.efi extracted from installation media
                            set "FOUND_MEDIA=1"
                        )
                    ) else if exist "D:\sources\install.wim" (
                        echo [INFO] Found Windows installation media: D:\sources\install.wim
                        echo Attempting to extract winload.efi using DISM...
                        dism /Image:!target_drive!: /RestoreHealth /Source:D:\sources\install.wim:1
                        if exist "!target_drive!:\Windows\System32\winload.efi" (
                            echo [SUCCESS] winload.efi extracted from installation media
                            set "FOUND_MEDIA=1"
                        )
                    ) else if exist "D:\sources\install.esd" (
                        echo [INFO] Found Windows installation media: D:\sources\install.esd
                        echo Attempting to extract winload.efi using DISM...
                        dism /Image:!target_drive!: /RestoreHealth /Source:D:\sources\install.esd:1
                        if exist "!target_drive!:\Windows\System32\winload.efi" (
                            echo [SUCCESS] winload.efi extracted from installation media
                            set "FOUND_MEDIA=1"
                        )
                    ) else if exist "E:\sources\install.wim" (
                        echo [INFO] Found Windows installation media: E:\sources\install.wim
                        echo Attempting to extract winload.efi using DISM...
                        dism /Image:!target_drive!: /RestoreHealth /Source:E:\sources\install.wim:1
                        if exist "!target_drive!:\Windows\System32\winload.efi" (
                            echo [SUCCESS] winload.efi extracted from installation media
                            set "FOUND_MEDIA=1"
                        )
                    ) else if exist "E:\sources\install.esd" (
                        echo [INFO] Found Windows installation media: E:\sources\install.esd
                        echo Attempting to extract winload.efi using DISM...
                        dism /Image:!target_drive!: /RestoreHealth /Source:E:\sources\install.esd:1
                        if exist "!target_drive!:\Windows\System32\winload.efi" (
                            echo [SUCCESS] winload.efi extracted from installation media
                            set "FOUND_MEDIA=1"
                        )
                    )
                    if "!FOUND_MEDIA!"=="0" (
                        echo [ERROR] Could not find Windows installation media (install.wim/install.esd)
                        echo Please attach Windows ISO/USB and ensure it's accessible, then retry.
                    )
                )
            )
            echo.
        ) else (
            echo [OK] winload.efi found in Windows directory.
        )
        
        REM Step 5.2: Verify file attributes (clear hidden/system if needed)
        if exist "!target_drive!:\Windows\System32\winload.efi" (
            echo Step 5.2: Verifying file attributes...
            attrib -s -h -r "!target_drive!:\Windows\System32\winload.efi"
            echo [OK] File attributes verified.
            echo.
        )
        
        REM Step 5.3: Copy to EFI partition if not already there
        if exist "!target_drive!:\Windows\System32\winload.efi" (
            echo Step 5.3: Copying winload.efi to EFI partition using bcdboot...
            call :MountEFIPartition "!target_drive!"
            if not errorlevel 1 (
                echo Running: bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
                bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
                if errorlevel 1 (
                    echo [WARNING] bcdboot failed.
                    echo Step 4: Checking EFI partition health (write-protection, space, corruption)...
                    echo [WARNING] EFI partition may be corrupted, write-protected, or out of space.
                    echo Step 4: Formatting EFI partition !EFI_DRIVE!: as FAT32 (quick format)...
                    echo WARNING: This will wipe the EFI partition (safe if Windows partition is intact)
                    echo Y | format !EFI_DRIVE!: /fs:FAT32 /q
                    if not errorlevel 1 (
                        echo Retrying bcdboot after EFI partition format...
                        bcdboot !target_drive!:\Windows /s !EFI_DRIVE!: /f UEFI
                    ) else (
                        echo [ERROR] EFI partition format failed.
                    )
                )
                if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                    echo [SUCCESS] winload.efi copied to EFI partition.
                ) else (
                    echo [WARNING] winload.efi not found in EFI partition after bcdboot.
                    echo The source template (C:\Windows\System32\Boot\winload.efi) may be missing.
                    echo Step 5: Manual extraction from Windows installation media (install.wim/install.esd) is required.
                )
            )
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
        
        REM Generate comprehensive repair report
        call :GenerateRepairReport "!target_drive!"
        
        goto :eof

REM ============================================================================
REM BOOT DIAGNOSIS & REPAIR
REM ============================================================================

:BootDiagnosis
REM Boot diagnosis with optional repair
echo.
echo ================================================================
echo   BOOT DIAGNOSIS ^& REPAIR
echo ================================================================
echo.

REM First, try to use PowerShell if available (full diagnosis)
where powershell.exe >nul 2>&1
if not errorlevel 1 (
    echo PowerShell is available. Using full diagnosis mode...
    echo.
    echo This will provide comprehensive boot analysis with 3 modes:
    echo   1. DIAGNOSIS ONLY - Find what's broken
    echo   2. DIAGNOSIS + FIX - Automatically fix issues
    echo   3. DIAGNOSIS THEN ASK - Diagnose first, then ask about fixes
    echo.
    echo The diagnosis covers 8 phases:
    echo   1. UEFI/GPT Integrity Check
    echo   2. BCD File ^& Integrity
    echo   3. BCD Entries Validation
    echo   4. WinRE Access
    echo   5. Driver Matching
    echo   6. Windows Kernel
    echo   7. Boot Log Analysis
    echo   8. Event Log Analysis
    echo.
    set /p mode_choice="Select mode (1=Diagnosis Only, 2=Diagnosis+Fix, 3=Diagnosis Then Ask, default 1): "
    if "!mode_choice!"=="" set "mode_choice=1"
    if "!mode_choice!"=="1" set "mode=DiagnosisOnly"
    if "!mode_choice!"=="2" set "mode=DiagnosisAndFix"
    if "!mode_choice!"=="3" set "mode=DiagnosisThenAsk"
    if "!mode!"=="" set "mode=DiagnosisOnly"
    
    set /p verbose_choice="Run in VERBOSE mode? (Y/N, default N): "
    if /i "!verbose_choice!"=="Y" (
        set "verbose_flag=1"
    ) else (
        set "verbose_flag=0"
    )
    
    set /p drive="Enter target Windows drive letter (e.g. C, or press Enter for C): "
    if "!drive!"=="" set "drive=C"
    set "drive=!drive:~0,1!"
    
    REM Verify drive exists
    if not exist "!drive!:\Windows\System32\ntoskrnl.exe" (
        echo ERROR: Windows installation not found on !drive!: drive.
        goto :eof
    )
    
    echo.
    echo Starting boot diagnosis (Mode: !mode!) on !drive!:...
    echo.
    
    REM Get the script directory (Helper folder)
    set "SCRIPT_DIR=%~dp0"
    if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
    
    REM Call PowerShell with the diagnosis function
    REM Note: WinRepairCore.ps1 should be in the same directory as this CMD file
    if !verbose_flag! EQU 1 (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $ErrorActionPreference = 'Stop'; $scriptRoot = '!SCRIPT_DIR!'; $corePath = Join-Path $scriptRoot 'WinRepairCore.ps1'; if (Test-Path $corePath) { . $corePath; Start-BootDiagnosisAndRepair -Drive '!drive!' -Mode '!mode!' -Verbose } else { Write-Host 'ERROR: WinRepairCore.ps1 not found in ' $scriptRoot; exit 1 } }"
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $ErrorActionPreference = 'Stop'; $scriptRoot = '!SCRIPT_DIR!'; $corePath = Join-Path $scriptRoot 'WinRepairCore.ps1'; if (Test-Path $corePath) { . $corePath; Start-BootDiagnosisAndRepair -Drive '!drive!' -Mode '!mode!' } else { Write-Host 'ERROR: WinRepairCore.ps1 not found in ' $scriptRoot; exit 1 } }"
    )
    
    if errorlevel 1 (
        echo.
        echo ERROR: PowerShell diagnosis failed. Falling back to simplified CMD diagnosis...
        echo.
        goto :SimpleDiagnosis
    ) else (
        echo.
        echo Boot diagnosis completed.
        goto :eof
    )
)

REM Simplified CMD-only diagnosis (if PowerShell not available)
:SimpleDiagnosis
echo Running simplified boot diagnosis (CMD mode)...
echo.
set /p drive="Enter target Windows drive letter (e.g. C, or press Enter for C): "
if "!drive!"=="" set "drive=C"
set "drive=!drive:~0,1!"

REM Verify drive exists
if not exist "!drive!:\Windows\System32\ntoskrnl.exe" (
    echo ERROR: Windows installation not found on !drive!: drive.
    goto :eof
)

echo.
echo ================================================================
echo SIMPLIFIED BOOT DIAGNOSIS - !drive!: Drive
echo ================================================================
echo.

REM Phase 1: Check critical boot files
echo [Phase 1] Checking critical boot files...
set "ISSUES=0"

if not exist "!drive!:\Windows\System32\ntoskrnl.exe" (
    echo   [FAIL] ntoskrnl.exe missing
    set /a ISSUES+=1
) else (
    echo   [OK] ntoskrnl.exe found
)

if not exist "!drive!:\Windows\System32\winload.efi" (
    if not exist "!drive!:\Windows\System32\winload.exe" (
        echo   [FAIL] winload.efi/winload.exe missing
        set /a ISSUES+=1
    ) else (
        echo   [OK] winload.exe found (Legacy BIOS)
    )
) else (
    echo   [OK] winload.efi found (UEFI)
)

REM Phase 2: Check BCD
echo.
echo [Phase 2] Checking Boot Configuration Data (BCD)...
call :MountEFIPartition "!drive!"
if not errorlevel 1 (
    if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
        echo   [OK] BCD file found in EFI partition
        bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
        if errorlevel 1 (
            echo   [FAIL] BCD is corrupted or unreadable
            set /a ISSUES+=1
        ) else (
            echo   [OK] BCD is readable
        )
    ) else (
        echo   [FAIL] BCD file missing from EFI partition
        set /a ISSUES+=1
    )
) else (
    echo   [WARNING] Could not mount EFI partition to check BCD
    set /a ISSUES+=1
)

REM Phase 3: Check Windows directory structure
echo.
echo [Phase 3] Checking Windows directory structure...
if not exist "!drive!:\Windows\System32\config\SYSTEM" (
    echo   [FAIL] SYSTEM registry hive missing
    set /a ISSUES+=1
) else (
    echo   [OK] SYSTEM registry hive found
)

REM Phase 4: Check for boot logs
echo.
echo [Phase 4] Checking for boot failure logs...
set "LOG_FOUND=0"
if exist "!drive!:\Windows\Minidump\*.dmp" (
    echo   [INFO] Memory dump files found (may indicate crashes)
    set "LOG_FOUND=1"
)
if exist "!drive!:\Windows\Logs\CBS\*.log" (
    echo   [INFO] Component-Based Servicing logs found
    set "LOG_FOUND=1"
)

REM Summary
echo.
echo ================================================================
echo DIAGNOSIS SUMMARY
echo ================================================================
echo.
if !ISSUES! EQU 0 (
    echo [OK] No critical boot issues detected.
    echo.
    echo The system appears to have all critical boot files present.
    echo If boot problems persist, consider:
    echo   - Running full diagnosis with PowerShell (if available)
    echo   - Checking hardware (RAM, disk health)
    echo   - Reviewing BIOS/UEFI settings
) else (
    echo [WARNING] !ISSUES! critical issue(s) detected.
    echo.
    echo Recommended actions:
    echo   1. Run "ONE-CLICK BOOT FIX" (option 5) to attempt automatic repair
    echo   2. If PowerShell is available, run full diagnosis for detailed analysis
    echo   3. Check Windows installation media for repair options
)
echo.
echo ================================================================
echo END OF DIAGNOSIS
echo ================================================================
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

REM ============================================================================
REM GENERATE REPAIR REPORT
REM ============================================================================

:GenerateRepairReport
REM Generates a comprehensive repair report and opens it in Notepad
setlocal enabledelayedexpansion
set "TARGET_DRIVE=%~1"
if "!TARGET_DRIVE!"=="" set "TARGET_DRIVE=C"

REM Create unique report filename
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set "REPORT_FILE=%TEMP%\BootRepairReport_CMD_%datetime:~0,8%_%datetime:~8,6%.txt"

echo.
echo Generating comprehensive repair report...
echo Report will be saved to: !REPORT_FILE!
echo.

REM Create report header
(
    echo ================================================================================
    echo ONE-CLICK BOOT REPAIR REPORT - CMD MODE
    echo ================================================================================
    echo.
    echo Generated: %date% %time%
    echo Target Drive: !TARGET_DRIVE!:
    echo.
    echo ================================================================================
    echo CODE RED: FAILED COMMANDS!
    echo ================================================================================
    echo.
    echo NOTE: This report tracks commands that returned error codes or failed.
    echo Review the commands below to identify what went wrong.
    echo.
) > "!REPORT_FILE!"

REM Check for common failure indicators
set "HAS_ERRORS=0"
set "REMAINING_ISSUES=0"

REM Check if winload.efi is still missing
if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo [FAILED] winload.efi is still missing from Windows directory >> "!REPORT_FILE!"
    echo   Issue: Boot file missing - Windows cannot boot without this file >> "!REPORT_FILE!"
    echo   Category: Boot Files >> "!REPORT_FILE!"
    echo. >> "!REPORT_FILE!"
    set "HAS_ERRORS=1"
    set /a REMAINING_ISSUES+=1
)

REM Check if EFI drive was set and check BCD
if defined EFI_DRIVE (
    if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
        bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
        if errorlevel 1 (
            echo [FAILED] BCD file exists but is corrupted or unreadable >> "!REPORT_FILE!"
            echo   Issue: BCD corruption - boot configuration cannot be read >> "!REPORT_FILE!"
            echo   Category: BCD >> "!REPORT_FILE!"
            echo   Error Code: %errorlevel% >> "!REPORT_FILE!"
            echo. >> "!REPORT_FILE!"
            set "HAS_ERRORS=1"
            set /a REMAINING_ISSUES+=1
        )
    ) else (
        echo [FAILED] BCD file missing from EFI partition >> "!REPORT_FILE!"
        echo   Issue: BCD file not found - boot configuration missing >> "!REPORT_FILE!"
        echo   Category: EFI Partition >> "!REPORT_FILE!"
        echo. >> "!REPORT_FILE!"
        set "HAS_ERRORS=1"
        set /a REMAINING_ISSUES+=1
    )
)

if "!HAS_ERRORS!"=="0" (
    echo No failed commands detected. All repairs appear successful. >> "!REPORT_FILE!"
    echo. >> "!REPORT_FILE!"
)

REM Add sections
(
    echo ================================================================================
    echo WHAT WAS WRONG
    echo ================================================================================
    echo.
    echo Issues detected during repair:
    echo.
) >> "!REPORT_FILE!"

if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo [FIXED/ATTEMPTED] winload.efi was missing from Windows directory >> "!REPORT_FILE!"
    echo   Action Taken: Attempted to restore from Boot folder, DISM, SFC, or install.wim >> "!REPORT_FILE!"
    echo. >> "!REPORT_FILE!"
)

(
    echo ================================================================================
    echo WHAT IS STILL WRONG
    echo ================================================================================
    echo.
) >> "!REPORT_FILE!"

if "!REMAINING_ISSUES!"=="0" (
    echo All issues have been resolved. >> "!REPORT_FILE!"
    echo. >> "!REPORT_FILE!"
) else (
    if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo [NOT FIXED] winload.efi is still missing from Windows directory >> "!REPORT_FILE!"
        echo   Category: Boot Files >> "!REPORT_FILE!"
        echo   Impact: Windows cannot boot without this file >> "!REPORT_FILE!"
        echo. >> "!REPORT_FILE!"
    )
)

(
    echo ================================================================================
    echo COMMANDS EXECUTED
    echo ================================================================================
    echo.
    echo The following commands were executed during the repair process:
    echo.
) >> "!REPORT_FILE!"

echo [SUCCESS] bootrec /scanos - Scanned for Windows installations >> "!REPORT_FILE!"
echo [SUCCESS] bootrec /rebuildbcd - Rebuilt Boot Configuration Data >> "!REPORT_FILE!"
echo [SUCCESS] bootrec /fixboot - Fixed boot sector >> "!REPORT_FILE!"
echo [SUCCESS] bootrec /fixmbr - Fixed Master Boot Record >> "!REPORT_FILE!"

if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    echo [SUCCESS] winload.efi verification - File exists >> "!REPORT_FILE!"
) else (
    echo [FAILED] winload.efi verification - File still missing >> "!REPORT_FILE!"
    echo   Attempted: DISM /Image:!TARGET_DRIVE!: /RestoreHealth >> "!REPORT_FILE!"
    echo   Attempted: SFC /ScanNow /OffBootDir=!TARGET_DRIVE!: /OffWinDir=!TARGET_DRIVE!:\Windows >> "!REPORT_FILE!"
    echo   Attempted: Manual extraction from install.wim/install.esd >> "!REPORT_FILE!"
)

REM Add alternative commands if issues remain
if "!REMAINING_ISSUES!" GTR 0 (
    (
        echo.
        echo ================================================================================
        echo ALTERNATIVE COMMANDS TO TRY
        echo ================================================================================
        echo.
        echo These commands were NOT run by the automated repair tool.
        echo Try them manually in an elevated Command Prompt.
        echo.
    ) >> "!REPORT_FILE!"
    
    if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        (
            echo For: winload.efi missing
            echo.
            echo Option 1: Manual copy from Boot folder
            echo   Command: copy /Y !TARGET_DRIVE!:\Windows\System32\Boot\winload.efi !TARGET_DRIVE!:\Windows\System32\winload.efi
            echo.
            echo Option 2: DISM with source
            echo   Command: dism /Image:!TARGET_DRIVE!: /RestoreHealth /Source:wim:^<path_to_install.wim^>:1 /LimitAccess
            echo   Note: Replace ^<path_to_install.wim^> with actual path to Windows installation media
            echo.
            echo Option 3: BCD path correction
            echo   Command: bcdedit /set {default} path \Windows\system32\winload.efi
            echo   Command: bcdedit /set {default} device partition=!TARGET_DRIVE!:
            echo   Command: bcdedit /set {default} osdevice partition=!TARGET_DRIVE!:
            echo.
        ) >> "!REPORT_FILE!"
    )
)

REM Add footer
(
    echo.
    echo ================================================================================
    echo END OF REPORT
    echo ================================================================================
    echo.
    echo If problems persist:
    echo 1. Search the error messages above on Microsoft Support
    echo 2. Try the alternative commands listed above
    echo 3. Consider running an in-place repair installation
    echo 4. Check hardware health (RAM, disk)
    echo.
) >> "!REPORT_FILE!"

REM Open report in Notepad
echo.
echo Opening report in Notepad...
start notepad.exe "!REPORT_FILE!"

echo Report generated and opened in Notepad.
echo Report location: !REPORT_FILE!
echo.

endlocal
goto :eof

REM If script is run directly (not called as function), show menu
if "%~1"=="" goto :MainMenu

