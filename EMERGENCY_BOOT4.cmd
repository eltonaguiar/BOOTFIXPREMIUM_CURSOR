@echo off
setlocal enabledelayedexpansion
REM ============================================================================
REM EMERGENCY_BOOT4.cmd - Smart Minimal Boot Repair
REM Only runs necessary commands based on actual issues detected
REM Shows progress percentage and exact commands being executed
REM ============================================================================

echo.
echo ============================================================================
echo   EMERGENCY BOOT REPAIR #4 - SMART MINIMAL MODE
echo ============================================================================
echo.
echo This tool performs intelligent diagnosis and only fixes what's broken.
echo It will skip unnecessary commands (e.g., won't run SFC if only BCD is broken).
echo.
echo Features:
echo   - Progress percentage tracking
echo   - Shows exact commands before execution
echo   - Only runs minimum necessary repairs
echo   - Skips unnecessary operations
echo.
echo WARNING: Only run this from Windows Recovery Environment (WinRE/WinPE)
echo.
pause

REM ============================================================================
REM PHASE 0: DISCOVERY
REM ============================================================================
echo.
echo ============================================================================
echo   PHASE 0: DISCOVERY (0%%)
echo ============================================================================
echo.

REM Find Windows installations
echo [0%%] Scanning for Windows installations...
set "INSTALL_COUNT=0"
set "INSTALL_LIST="
set "TARGET_DRIVE="

for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%d:\Windows\System32\ntoskrnl.exe" (
        if /i not "%%d"=="X" (
            set /a INSTALL_COUNT+=1
            set "INSTALL_LIST=!INSTALL_LIST! %%d"
            if not defined TARGET_DRIVE set "TARGET_DRIVE=%%d"
            echo   Found Windows on %%d: drive
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
        echo [ERROR] Windows not found on !MANUAL_DRIVE!: drive
        pause
        exit /b 1
    )
    
    set "TARGET_DRIVE=!MANUAL_DRIVE!"
    goto :start_smart_repair
)

if !INSTALL_COUNT! GTR 1 (
    echo.
    echo Multiple Windows installations found:
    set "INDEX=0"
    for %%d in (!INSTALL_LIST!) do (
        set /a INDEX+=1
        echo   [!INDEX!] %%d: drive
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
            goto :start_smart_repair
        )
    )
    
    echo Invalid selection.
    pause
    exit /b 1
)

:start_smart_repair
echo.
echo ============================================================================
echo   Target Windows Drive: !TARGET_DRIVE!:
echo ============================================================================
echo.

REM ============================================================================
REM PHASE 1: SMART DIAGNOSIS (10%% - 40%%)
REM ============================================================================
echo ============================================================================
echo   PHASE 1: SMART DIAGNOSIS (10%% - 40%%)
echo ============================================================================
echo.

set "ISSUE_WINLOAD_WIN=0"
set "ISSUE_WINLOAD_EFI=0"
set "ISSUE_BCD_MISSING=0"
set "ISSUE_BCD_CORRUPT=0"
set "ISSUE_EFI_NOT_MOUNTED=0"
set "ISSUE_EFI_MISSING=0"
set "TOTAL_ISSUES=0"
set "EFI_DRIVE="

REM Check 1: winload.efi in Windows directory (10%%)
echo [10%%] Checking winload.efi in Windows directory...
echo   Command: Test-Path "!TARGET_DRIVE!:\Windows\System32\winload.efi"
if not exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
    if not exist "!TARGET_DRIVE!:\Windows\System32\winload.exe" (
        echo   [ISSUE] winload.efi/winload.exe missing
        set "ISSUE_WINLOAD_WIN=1"
        set /a TOTAL_ISSUES+=1
    ) else (
        echo   [OK] winload.exe found (Legacy BIOS)
    )
) else (
    echo   [OK] winload.efi found
)

REM Check 2: EFI partition (15%%)
echo.
echo [15%%] Checking EFI partition...
echo   Command: Checking for mounted EFI partition...

REM Check if already mounted
for %%d in (S T U V W Y Z) do (
    if exist "%%d:\EFI\Microsoft\Boot\BCD" (
        set "EFI_DRIVE=%%d"
        echo   [OK] EFI partition already mounted as %%d:
        goto :efi_mounted
    )
)

REM Try to mount EFI partition
echo   [INFO] EFI partition not mounted, attempting to mount...
echo   Command: mountvol S: /S
mountvol S: /S >nul 2>&1
if exist "S:\EFI\Microsoft\Boot\BCD" (
    set "EFI_DRIVE=S"
    echo   [OK] EFI partition mounted as S:
    goto :efi_mounted
)

REM Try other drive letters
for %%d in (T U V W Y Z) do (
    echo   Command: mountvol %%d: /S
    mountvol %%d: /S >nul 2>&1
    if exist "%%d:\EFI\Microsoft\Boot\BCD" (
        set "EFI_DRIVE=%%d"
        echo   [OK] EFI partition mounted as %%d:
        goto :efi_mounted
    )
)

REM Try diskpart method
echo   [INFO] Trying diskpart method...
(
    echo select disk 0
    echo list partition
    echo exit
) > %TEMP%\find_efi.txt
diskpart /s %TEMP%\find_efi.txt > %TEMP%\partitions.txt 2>&1

REM Try partition 1
(
    echo select disk 0
    echo select partition 1
    echo assign letter=S
    echo exit
) > %TEMP%\mount_efi.txt
diskpart /s %TEMP%\mount_efi.txt >nul 2>&1
if exist "S:\EFI\Microsoft\Boot\BCD" (
    set "EFI_DRIVE=S"
    echo   [OK] EFI partition mounted as S: (partition 1)
    goto :efi_mounted
)

REM Try partition 2
(
    echo select disk 0
    echo select partition 2
    echo assign letter=S
    echo exit
) > %TEMP%\mount_efi2.txt
diskpart /s %TEMP%\mount_efi2.txt >nul 2>&1
if exist "S:\EFI\Microsoft\Boot\BCD" (
    set "EFI_DRIVE=S"
    echo   [OK] EFI partition mounted as S: (partition 2)
    goto :efi_mounted
)

echo   [ISSUE] Could not mount EFI partition
set "ISSUE_EFI_NOT_MOUNTED=1"
set /a TOTAL_ISSUES+=1
goto :diagnosis_continue

:efi_mounted
echo   [OK] EFI partition accessible

:diagnosis_continue

REM Check 3: BCD file (25%%)
if not "!EFI_DRIVE!"=="" (
    echo.
    echo [25%%] Checking BCD file...
    echo   Command: Test-Path "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD"
    if not exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
        echo   [ISSUE] BCD file missing
        set "ISSUE_BCD_MISSING=1"
        set /a TOTAL_ISSUES+=1
    ) else (
        echo   [OK] BCD file exists, checking integrity...
        echo   Command: bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default}
        bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
        if errorlevel 1 (
            echo   [ISSUE] BCD file is corrupted or unreadable
            set "ISSUE_BCD_CORRUPT=1"
            set /a TOTAL_ISSUES+=1
        ) else (
            echo   [OK] BCD file is readable
        )
    )
) else (
    echo.
    echo [25%%] Skipping BCD check - EFI partition not accessible
)

REM Check 4: winload.efi in EFI partition (30%%)
if not "!EFI_DRIVE!"=="" (
    echo.
    echo [30%%] Checking winload.efi in EFI partition...
    echo   Command: Test-Path "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi"
    if not exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
        echo   [ISSUE] winload.efi missing from EFI partition
        set "ISSUE_WINLOAD_EFI=1"
        set /a TOTAL_ISSUES+=1
    ) else (
        echo   [OK] winload.efi found in EFI partition
    )
)

REM Diagnosis Summary (35%%)
echo.
echo [35%%] Diagnosis Summary:
echo   Total issues found: !TOTAL_ISSUES!
if !ISSUE_WINLOAD_WIN! EQU 1 echo   - winload.efi missing from Windows directory
if !ISSUE_WINLOAD_EFI! EQU 1 echo   - winload.efi missing from EFI partition
if !ISSUE_BCD_MISSING! EQU 1 echo   - BCD file missing
if !ISSUE_BCD_CORRUPT! EQU 1 echo   - BCD file corrupted
if !ISSUE_EFI_NOT_MOUNTED! EQU 1 echo   - EFI partition not accessible

if !TOTAL_ISSUES! EQU 0 (
    echo.
    echo ============================================================================
    echo   [SUCCESS] No boot issues detected!
    echo ============================================================================
    echo.
    echo All boot components are healthy. No repairs needed.
    pause
    exit /b 0
)

echo.
echo ============================================================================
echo   PHASE 2: MINIMAL REPAIR (40%% - 90%%)
echo ============================================================================
echo.

set "FIXES_APPLIED=0"
set "CURRENT_PROGRESS=40"
set "PROGRESS_INCREMENT=0"

REM Calculate progress increment per fix
if !TOTAL_ISSUES! GTR 0 (
    set /a PROGRESS_INCREMENT=50 / !TOTAL_ISSUES!
)

REM Fix 1: winload.efi in Windows directory (if needed)
if !ISSUE_WINLOAD_WIN! EQU 1 (
    echo [!CURRENT_PROGRESS!%%] Fixing winload.efi in Windows directory...
    echo   Issue: winload.efi missing from Windows directory
    echo   Strategy: Try minimal fixes first (copy from Boot folder, then DISM)
    
    REM Try copy from Boot folder first (fastest)
    if exist "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" (
        echo   Command: copy "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" "!TARGET_DRIVE!:\Windows\System32\winload.efi" /y
        copy "!TARGET_DRIVE!:\Windows\System32\Boot\winload.efi" "!TARGET_DRIVE!:\Windows\System32\winload.efi" /y >nul 2>&1
        if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
            echo   [SUCCESS] Copied from Boot folder
            set /a FIXES_APPLIED+=1
            set /a CURRENT_PROGRESS+=!PROGRESS_INCREMENT!
            goto :winload_win_fixed
        )
    )
    
    REM Try DISM (minimal - only if copy failed)
    echo   Command: dism /Image:!TARGET_DRIVE!: /RestoreHealth
    echo   [INFO] Running DISM (this may take a few minutes)...
    dism /Image:!TARGET_DRIVE!: /RestoreHealth >nul 2>&1
    if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [SUCCESS] DISM restored winload.efi
        set /a FIXES_APPLIED+=1
        set /a CURRENT_PROGRESS+=!PROGRESS_INCREMENT!
    ) else (
        echo   [WARNING] DISM did not restore winload.efi
        echo   [INFO] SFC would be next step, but skipping (minimal mode)
    )
    
    :winload_win_fixed
    echo.
)

REM Fix 2: Mount EFI partition (if needed)
if !ISSUE_EFI_NOT_MOUNTED! EQU 1 (
    echo [!CURRENT_PROGRESS!%%] Mounting EFI partition...
    echo   Issue: EFI partition not accessible
    echo   Strategy: Try multiple mounting methods
    
    REM Already tried above, but try one more time with different approach
    echo   Command: mountvol S: /S
    mountvol S: /S >nul 2>&1
    if exist "S:\EFI\Microsoft\Boot\BCD" (
        set "EFI_DRIVE=S"
        echo   [SUCCESS] EFI partition mounted as S:
        set "ISSUE_EFI_NOT_MOUNTED=0"
        set /a FIXES_APPLIED+=1
        set /a CURRENT_PROGRESS+=!PROGRESS_INCREMENT!
    ) else (
        echo   [WARNING] Could not mount EFI partition automatically
        echo   [INFO] Manual intervention may be required
    )
    echo.
)

REM Fix 3: BCD file (if needed)
if not "!EFI_DRIVE!"=="" (
    if !ISSUE_BCD_MISSING! EQU 1 (
        echo [!CURRENT_PROGRESS!%%] Creating BCD file...
        echo   Issue: BCD file missing
        echo   Strategy: Create new BCD using bcdboot
        echo   Command: bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
        bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
        if not errorlevel 1 (
            if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
                echo   [SUCCESS] BCD file created
                set "ISSUE_BCD_MISSING=0"
                set /a FIXES_APPLIED+=1
                set /a CURRENT_PROGRESS+=!PROGRESS_INCREMENT!
            ) else (
                echo   [WARNING] bcdboot completed but BCD file not found
            )
        ) else (
            echo   [WARNING] bcdboot failed
        )
        echo.
    )
    
    if !ISSUE_BCD_CORRUPT! EQU 1 (
        echo [!CURRENT_PROGRESS!%%] Rebuilding corrupted BCD...
        echo   Issue: BCD file corrupted
        echo   Strategy: Backup, delete, and recreate BCD
        echo   Command: copy "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD.backup"
        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
            copy "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD.backup" /y >nul 2>&1
            echo   [INFO] BCD backed up to BCD.backup
        )
        echo   Command: del "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD"
        del "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" >nul 2>&1
        echo   Command: bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
        bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
        if not errorlevel 1 (
            echo   Command: bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default}
            bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
            if not errorlevel 1 (
                echo   [SUCCESS] BCD rebuilt and verified
                set "ISSUE_BCD_CORRUPT=0"
                set /a FIXES_APPLIED+=1
                set /a CURRENT_PROGRESS+=!PROGRESS_INCREMENT!
            ) else (
                echo   [WARNING] BCD rebuilt but verification failed
            )
        ) else (
            echo   [WARNING] bcdboot failed to rebuild BCD
        )
        echo.
    )
    
    REM Fix 4: winload.efi in EFI partition (if needed)
    if !ISSUE_WINLOAD_EFI! EQU 1 (
        echo [!CURRENT_PROGRESS!%%] Copying winload.efi to EFI partition...
        echo   Issue: winload.efi missing from EFI partition
        echo   Strategy: Use bcdboot to copy boot files
        if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
            echo   Command: bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
            bcdboot !TARGET_DRIVE!:\Windows /s !EFI_DRIVE!: /f UEFI
            if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
                echo   [SUCCESS] winload.efi copied to EFI partition
                set "ISSUE_WINLOAD_EFI=0"
                set /a FIXES_APPLIED+=1
                set /a CURRENT_PROGRESS+=!PROGRESS_INCREMENT!
            ) else (
                echo   [WARNING] bcdboot did not copy winload.efi
            )
        ) else (
            echo   [WARNING] Cannot copy winload.efi - source file missing
        )
        echo.
    )
)

REM ============================================================================
REM PHASE 3: VERIFICATION (90%% - 100%%)
REM ============================================================================
echo ============================================================================
echo   PHASE 3: VERIFICATION (90%% - 100%%)
echo ============================================================================
echo.

echo [90%%] Verifying repairs...
set "VERIFICATION_PASSED=1"

REM Verify winload.efi in Windows
if !ISSUE_WINLOAD_WIN! EQU 1 (
    echo   Command: Test-Path "!TARGET_DRIVE!:\Windows\System32\winload.efi"
    if exist "!TARGET_DRIVE!:\Windows\System32\winload.efi" (
        echo   [OK] winload.efi now exists in Windows directory
    ) else (
        echo   [FAIL] winload.efi still missing from Windows directory
        set "VERIFICATION_PASSED=0"
    )
)

REM Verify EFI partition
if !ISSUE_EFI_NOT_MOUNTED! EQU 1 (
    if "!EFI_DRIVE!"=="" (
        echo   [FAIL] EFI partition still not accessible
        set "VERIFICATION_PASSED=0"
    ) else (
        echo   [OK] EFI partition is accessible
    )
)

REM Verify BCD
if not "!EFI_DRIVE!"=="" (
    if !ISSUE_BCD_MISSING! EQU 1 (
        echo   Command: Test-Path "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD"
        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" (
            echo   [OK] BCD file now exists
        ) else (
            echo   [FAIL] BCD file still missing
            set "VERIFICATION_PASSED=0"
        )
    )
    
    if !ISSUE_BCD_CORRUPT! EQU 1 (
        echo   Command: bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default}
        bcdedit /store "!EFI_DRIVE!:\EFI\Microsoft\Boot\BCD" /enum {default} >nul 2>&1
        if not errorlevel 1 (
            echo   [OK] BCD file is now readable
        ) else (
            echo   [FAIL] BCD file is still corrupted
            set "VERIFICATION_PASSED=0"
        )
    )
    
    REM Verify winload.efi in EFI
    if !ISSUE_WINLOAD_EFI! EQU 1 (
        echo   Command: Test-Path "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi"
        if exist "!EFI_DRIVE!:\EFI\Microsoft\Boot\winload.efi" (
            echo   [OK] winload.efi now exists in EFI partition
        ) else (
            echo   [FAIL] winload.efi still missing from EFI partition
            set "VERIFICATION_PASSED=0"
        )
    )
)

echo.
echo [100%%] Repair complete!
echo.

REM ============================================================================
REM FINAL SUMMARY
REM ============================================================================
echo ============================================================================
echo   REPAIR SUMMARY
echo ============================================================================
echo.
echo Issues found: !TOTAL_ISSUES!
echo Fixes applied: !FIXES_APPLIED!
echo.

if !VERIFICATION_PASSED! EQU 1 (
    echo [SUCCESS] All detected issues have been fixed!
    echo.
    echo Please restart your computer to test if Windows boots normally.
) else (
    echo [PARTIAL] Some issues were fixed, but verification failed for some items.
    echo.
    echo You may need to:
    echo   - Run a more comprehensive repair tool (EMERGENCY_BOOT3.cmd)
    echo   - Manually check the EFI partition
    echo   - Run SFC /ScanNow if winload.efi issues persist
)

echo.
pause
exit /b 0
