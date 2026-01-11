@echo off
REM Miracle Boot v7.2.0 Launcher
REM Compatible with Windows Recovery Environment (WinRE) Shift+F10 command prompt

REM Safety interlock: if running in a live Windows OS (not WinRE/WinPE X:),
REM require explicit confirmation before allowing boot writes.
REM Use PowerShell to handle the confirmation to avoid batch parsing issues
setlocal
set "SCRIPT_ROOT=%~dp0"
cd /d "%SCRIPT_ROOT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Helper\CheckBrickmeConfirmation.ps1"
if errorlevel 1 (
    endlocal
    exit /b 1
)
endlocal

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
REM Terminate any existing MiracleBoot GUI processes before launching
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Get-Process | Where-Object { $_.MainWindowTitle -like '*MiracleBoot*' -or ($_.ProcessName -eq 'powershell' -and $_.MainWindowTitle -like '*MiracleBoot*') } | Stop-Process -Force -ErrorAction SilentlyContinue"
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "$Host.UI.RawUI.WindowTitle = 'MiracleBoot v7.2.0'; & '.\MiracleBoot.ps1'"

:end
exit /b 0

:error_exit
exit /b 1
