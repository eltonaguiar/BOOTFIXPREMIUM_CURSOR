@echo off
REM Comprehensive test suite for RunMiracleBoot.cmd
REM Tests that "was unexpected" error does not occur

set TEST_PASSED=0
set TEST_FAILED=0

echo ================================================================================
echo RunMiracleBoot.cmd Test Suite
echo ================================================================================
echo.

REM Test 1: Basic execution without input
echo [TEST 1] Running RunMiracleBoot.cmd without input...
echo BRICKME | cmd /c "RunMiracleBoot.cmd 2>&1" > test_output_1.txt 2>&1
findstr /C:"was unexpected" test_output_1.txt >nul
if errorlevel 1 (
    echo   [PASS] No "was unexpected" error found
    set /a TEST_PASSED+=1
) else (
    echo   [FAIL] "was unexpected" error found!
    type test_output_1.txt
    set /a TEST_FAILED+=1
)

echo.

REM Test 2: Execution with --emergency flag
echo [TEST 2] Running RunMiracleBoot.cmd with --emergency flag...
cmd /c "RunMiracleBoot.cmd --emergency 2>&1" > test_output_2.txt 2>&1
findstr /C:"was unexpected" test_output_2.txt >nul
if errorlevel 1 (
    echo   [PASS] No "was unexpected" error found
    set /a TEST_PASSED+=1
) else (
    echo   [FAIL] "was unexpected" error found!
    type test_output_2.txt
    set /a TEST_FAILED+=1
)

echo.

REM Test 3: Execution with invalid input (should exit gracefully)
echo [TEST 3] Running RunMiracleBoot.cmd with invalid input...
echo INVALID | cmd /c "RunMiracleBoot.cmd 2>&1" > test_output_3.txt 2>&1
findstr /C:"was unexpected" test_output_3.txt >nul
if errorlevel 1 (
    echo   [PASS] No "was unexpected" error found
    set /a TEST_PASSED+=1
) else (
    echo   [FAIL] "was unexpected" error found!
    type test_output_3.txt
    set /a TEST_FAILED+=1
)

echo.

REM Test 4: Multiple rapid executions
echo [TEST 4] Running RunMiracleBoot.cmd multiple times...
for /L %%i in (1,1,3) do (
    echo BRICKME | cmd /c "RunMiracleBoot.cmd 2>&1" > test_output_4_%%i.txt 2>&1
    findstr /C:"was unexpected" test_output_4_%%i.txt >nul
    if errorlevel 1 (
        echo   [PASS] Iteration %%i: No "was unexpected" error
        set /a TEST_PASSED+=1
    ) else (
        echo   [FAIL] Iteration %%i: "was unexpected" error found!
        type test_output_4_%%i.txt
        set /a TEST_FAILED+=1
    )
)

echo.
echo ================================================================================
echo Test Results
echo ================================================================================
echo Tests Passed: %TEST_PASSED%
echo Tests Failed: %TEST_FAILED%
echo.

if %TEST_FAILED%==0 (
    echo [SUCCESS] All tests passed! No "was unexpected" errors detected.
    exit /b 0
) else (
    echo [FAILURE] Some tests failed. Review output above.
    exit /b 1
)
