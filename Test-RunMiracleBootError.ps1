# Test script to reproduce the batch file error
$testDir = "C:\Users\zerou\Downloads\MiracleBoot_v7_1_1"
$batchFile = Join-Path $testDir "RunMiracleBoot.cmd"

Write-Host "Testing RunMiracleBoot.cmd for parsing errors..." -ForegroundColor Cyan
Write-Host ""

# Read the batch file and check for common issues
$content = Get-Content $batchFile -Raw
Write-Host "File length: $($content.Length) characters" -ForegroundColor Gray

# Check for unmatched parentheses
$openParens = ([regex]::Matches($content, '\(')).Count
$closeParens = ([regex]::Matches($content, '\)')).Count
Write-Host "Open parentheses: $openParens" -ForegroundColor Gray
Write-Host "Close parentheses: $closeParens" -ForegroundColor Gray

if ($openParens -ne $closeParens) {
    Write-Host "WARNING: Unmatched parentheses!" -ForegroundColor Yellow
}

# Check for common batch file issues
$issues = @()
if ($content -match 'if\s+errorlevel\s+1\s+exit\s+/b\s+1\s*$') {
    $issues += "Line 9: 'if errorlevel 1 exit /b 1' should be on separate lines or use parentheses"
}

if ($content -match '%[^%]*%[^%]*%') {
    $issues += "Potential variable expansion issue"
}

if ($issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Potential issues found:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
} else {
    Write-Host "No obvious syntax issues found" -ForegroundColor Green
}

# Try to execute and capture errors
Write-Host ""
Write-Host "Attempting to execute batch file..." -ForegroundColor Cyan
$output = cmd /c "`"$batchFile`"" 2>&1
$errorOutput = $output | Where-Object { $_ -match "unexpected|was unexpected" }

if ($errorOutput) {
    Write-Host "ERROR FOUND:" -ForegroundColor Red
    $errorOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
} else {
    Write-Host "No 'unexpected' errors in output" -ForegroundColor Green
}
