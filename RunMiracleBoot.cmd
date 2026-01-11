@echo off
REM Miracle Boot v7.2.0 Launcher
REM Compatible with Windows Recovery Environment (WinRE) Shift+F10 command prompt

echo(
echo ========================================
echo   Miracle Boot v7.2.0 Launcher
echo ========================================
echo(
REM Safety interlock: if running in a live Windows OS (not WinRE/WinPE X:),
REM require explicit confirmation before allowing boot writes.
if /I not "%SystemDrive%"=="X" (
    echo SAFETY WARNING: You are running from a live Windows OS (%SystemDrive%).
    echo Destructive boot repairs can brick the system if misused.
    echo To continue, type BRICKME and press Enter. Otherwise, press Ctrl+C to abort.
    set BRICKME_OK=
    set /p BRICKME_OK=Type BRICKME to continue: 
    if /I not "%BRICKME_OK%"=="BRICKME" (
        echo Aborting by user choice. No changes made.
        exit /b 1
    )
)

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Check if PowerShell is available
powershell.exe -Command "exit 0" >nul 2>&1
if errorlevel 1 (
    echo WARNING: PowerShell is not available in this environment.
    echo(
    echo Falling back to CMD-based mode with limited functionality.
    echo(
    echo Available options in CMD mode:
    echo   - Enable Network/Internet
    echo   - Check Internet Connectivity
    echo   - Open ChatGPT Help
    echo   - Check Windows Install Failure Reasons
    echo(
    pause
    echo(
    echo Launching CMD-based Miracle Boot...
    echo(
    call "%SCRIPT_DIR%Helper\WinRepairCore.cmd"
    exit /b %errorlevel%
)

REM Check if user wants emergency repair mode
if /i "%1"=="--emergency" (
    echo(
    echo ================================================================================
    echo EMERGENCY REPAIR MODE
    echo ================================================================================
    echo(
    echo Launching emergency repair routine (bypasses main scripts)...
    echo This mode works even if WinRepairTUI.ps1 or WinRepairGUI.ps1 have syntax errors.
    echo(
    cd /d "%SCRIPT_DIR%"
    powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "$Host.UI.RawUI.WindowTitle = 'MiracleBoot Emergency Repair'; . '.\Helper\EmergencyRepair.ps1'; Start-EmergencyRepair -Drive '%SystemDrive:~0,1%'"
    goto :end
)

REM Launch the PowerShell script
echo Launching Miracle Boot (PowerShell mode)...
echo(
cd /d "%SCRIPT_DIR%"
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "$Host.UI.RawUI.WindowTitle = 'MiracleBoot v7.2.0'; & '.\MiracleBoot.ps1'"

:end

if errorlevel 1 (
    echo(
    echo ERROR: Script execution failed.
    echo(
    echo Troubleshooting:
    echo 1. Ensure all .ps1 files are in the same directory as this .cmd file
    echo 2. Check that you have administrator privileges
    echo 3. Try running PowerShell directly: powershell.exe -ExecutionPolicy Bypass -File MiracleBoot.ps1
    echo(
    pause
)
