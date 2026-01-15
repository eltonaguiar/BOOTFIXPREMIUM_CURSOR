@echo off
setlocal EnableDelayedExpansion
set BRICKME_OK=
set /p BRICKME_OK=Type BRICKME: 
echo Raw value: [!BRICKME_OK!]
echo Length: 
echo !BRICKME_OK! | find /c /v ""
if /I "!BRICKME_OK!"=="BRICKME" (
    echo Exact match works
) else (
    echo Exact match failed
)
REM Try with trimmed comparison
for /f "tokens=*" %%a in ("!BRICKME_OK!") do set BRICKME_TRIMMED=%%a
if /I "!BRICKME_TRIMMED!"=="BRICKME" (
    echo Trimmed match works
) else (
    echo Trimmed match failed - Value: [!BRICKME_TRIMMED!]
)
