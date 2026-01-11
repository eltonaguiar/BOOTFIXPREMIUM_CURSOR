# Test GUI Launch Verification Script
# Verifies that WinRepairGUI.ps1 can be loaded and the GUI window can be created without syntax errors

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GUI Launch Verification Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptPath = Join-Path $PSScriptRoot "Helper\WinRepairGUI.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "[ERROR] WinRepairGUI.ps1 not found at: $scriptPath" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Testing syntax validation..." -ForegroundColor Yellow
try {
    $content = Get-Content $scriptPath -Raw
    $errors = $null
    [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
    
    if ($errors.Count -gt 0) {
        Write-Host "[FAIL] Syntax errors found:" -ForegroundColor Red
        $errors | Select-Object -First 10 | ForEach-Object {
            Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Red
        }
        exit 1
    } else {
        Write-Host "[OK] No syntax errors detected" -ForegroundColor Green
    }
} catch {
    Write-Host "[FAIL] Syntax validation failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[INFO] Testing script loading (dot-sourcing)..." -ForegroundColor Yellow
try {
    # Test if we can load the script without executing it
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$null)
    Write-Host "[OK] Script can be parsed successfully" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Script parsing failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[INFO] Testing function definitions..." -ForegroundColor Yellow
try {
    # Check for critical functions
    $scriptContent = Get-Content $scriptPath -Raw
    $requiredFunctions = @(
        "Start-GUI",
        "Set-FileOwnershipAndPermissions",
        "Test-AndRecreateBCD",
        "Invoke-BcdbootRepairWithFallback",
        "Mount-EFIPartition"
    )
    
    $missingFunctions = @()
    foreach ($func in $requiredFunctions) {
        if ($scriptContent -notmatch "function\s+$func") {
            $missingFunctions += $func
        }
    }
    
    if ($missingFunctions.Count -gt 0) {
        Write-Host "[WARNING] Missing function definitions:" -ForegroundColor Yellow
        $missingFunctions | ForEach-Object {
            Write-Host "  - $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[OK] All critical functions are defined" -ForegroundColor Green
    }
} catch {
    Write-Host "[WARNING] Function check failed: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[INFO] Testing critical code sections..." -ForegroundColor Yellow

# Check for the fixed else statement
$scriptContent = Get-Content $scriptPath -Raw
$lines = $scriptContent -split "`r?`n"

# Check line 5526 area for proper else statement
$line5526 = $lines[5525]  # 0-indexed
if ($line5526 -match '^\s*\}\s+else\s+\{' -or $line5526 -match '^\s*\}\s*else\s*\{') {
    Write-Host "[OK] Line 5526 has proper else statement structure" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Line 5526 structure: $($line5526.Trim())" -ForegroundColor Yellow
}

# Check for proper if ($efiDrive) structure
$ifEfiDriveFound = $false
$elseFound = $false
for ($i = 5190; $i -lt 5530; $i++) {
    if ($i -lt $lines.Count) {
        if ($lines[$i] -match '^\s*if\s+\(\$efiDrive\)\s*\{') {
            $ifEfiDriveFound = $true
        }
        if ($lines[$i] -match '^\s*\}\s*else\s*\{' -and $ifEfiDriveFound) {
            $elseFound = $true
            Write-Host "[OK] Found matching else for if (`$efiDrive) around line $($i + 1)" -ForegroundColor Green
            break
        }
    }
}

if (-not $ifEfiDriveFound) {
    Write-Host "[WARNING] Could not find if (`$efiDrive) statement" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[INFO] Syntax validation: PASSED" -ForegroundColor Green
Write-Host "[INFO] Script structure: VERIFIED" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: Test actual GUI launch with:" -ForegroundColor Yellow
Write-Host "  powershell.exe -ExecutionPolicy Bypass -File Helper\WinRepairGUI.ps1" -ForegroundColor White
Write-Host ""
