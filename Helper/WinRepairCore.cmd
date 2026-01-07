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

if /i "%choice%"=="Q" goto :eof
if /i "%choice%"=="q" goto :eof

echo Invalid selection.
timeout /t 2 >nul
goto :loop

REM If script is run directly (not called as function), show menu
if "%~1"=="" goto :MainMenu

