# Formal Test Plan Execution Script
# Senior Software Verification Engineer

param(
    [switch]$Module1,
    [switch]$Module2,
    [switch]$Module3,
    [switch]$Module4,
    [switch]$Module5,
    [switch]$Module6,
    [switch]$All,
    [string]$LogDir = "$env:TEMP\miracleboot-formaltest"
)

$ErrorActionPreference = 'Stop'
$global:TestResults = @()

function Write-TestResult {
    param(
        [string]$TestId,
        [string]$Module,
        [string]$Status,
        [string]$Details = "",
        [string]$Error = ""
    )
    $result = [PSCustomObject]@{
        TestId = $TestId
        Module = $Module
        Status = $Status
        Details = $Details
        Error = $Error
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $global:TestResults += $result
    $color = if ($Status -eq "PASS") { "Green" } elseif ($Status -eq "FAIL") { "Red" } else { "Yellow" }
    Write-Host "[$TestId] $Status" -ForegroundColor $color
    if ($Details) { Write-Host "  Details: $Details" -ForegroundColor Gray }
    if ($Error) { Write-Host "  Error: $Error" -ForegroundColor Red }
}

# MODULE 1: SYNTAX & PARSE TESTS
if ($Module1 -or $All) {
    Write-Host "`n=== MODULE 1: SYNTAX & PARSE TESTS ===" -ForegroundColor Cyan
    
    # Test 1.1
    Write-Host "`n[1.1] Testing MiracleBoot.ps1 syntax..." -ForegroundColor Yellow
    try {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "MiracleBoot.ps1" -Raw), [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-TestResult "1.1" "Syntax" "PASS" "0 parser errors"
        } else {
            $errorDetails = ($errors | Select-Object -First 3 | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
            Write-TestResult "1.1" "Syntax" "FAIL" "$($errors.Count) errors found" $errorDetails
        }
    } catch {
        Write-TestResult "1.1" "Syntax" "FAIL" "Parser exception" $_.Exception.Message
    }
    
    # Test 1.2
    Write-Host "`n[1.2] Testing WinRepairCore.ps1 syntax..." -ForegroundColor Yellow
    try {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairCore.ps1" -Raw), [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-TestResult "1.2" "Syntax" "PASS" "0 parser errors"
        } else {
            $errorDetails = ($errors | Select-Object -First 3 | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
            Write-TestResult "1.2" "Syntax" "FAIL" "$($errors.Count) errors found" $errorDetails
        }
    } catch {
        Write-TestResult "1.2" "Syntax" "FAIL" "Parser exception" $_.Exception.Message
    }
    
    # Test 1.3
    Write-Host "`n[1.3] Testing WinRepairGUI.ps1 syntax..." -ForegroundColor Yellow
    try {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairGUI.ps1" -Raw), [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-TestResult "1.3" "Syntax" "PASS" "0 parser errors"
        } else {
            $errorDetails = ($errors | Select-Object -First 3 | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
            Write-TestResult "1.3" "Syntax" "FAIL" "$($errors.Count) errors found" $errorDetails
        }
    } catch {
        Write-TestResult "1.3" "Syntax" "FAIL" "Parser exception" $_.Exception.Message
    }
    
    # Test 1.4
    Write-Host "`n[1.4] Testing WinRepairTUI.ps1 syntax..." -ForegroundColor Yellow
    try {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairTUI.ps1" -Raw), [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-TestResult "1.4" "Syntax" "PASS" "0 parser errors"
        } else {
            $errorDetails = ($errors | Select-Object -First 3 | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
            Write-TestResult "1.4" "Syntax" "FAIL" "$($errors.Count) errors found" $errorDetails
        }
    } catch {
        Write-TestResult "1.4" "Syntax" "FAIL" "Parser exception" $_.Exception.Message
    }
    
    # Test 1.5
    Write-Host "`n[1.5] Testing all helper files syntax..." -ForegroundColor Yellow
    $helperFiles = @("Helper\ErrorLogging.ps1", "Helper\PreLaunchValidation.ps1", "Helper\ReadinessGate.ps1", "Helper\NetworkDiagnostics.ps1", "Helper\LogAnalysis.ps1", "Helper\KeyboardSymbols.ps1")
    $allPassed = $true
    $failures = @()
    foreach ($file in $helperFiles) {
        if (-not (Test-Path $file)) {
            $failures += "$file not found"
            $allPassed = $false
            continue
        }
        try {
            $errors = @()
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file -Raw), [ref]$errors)
            if ($errors.Count -gt 0) {
                $failures += "$file : $($errors.Count) errors"
                $allPassed = $false
            }
        } catch {
            $failures += "$file : $($_.Exception.Message)"
            $allPassed = $false
        }
    }
    if ($allPassed) {
        Write-TestResult "1.5" "Syntax" "PASS" "All $($helperFiles.Count) helper files valid"
    } else {
        Write-TestResult "1.5" "Syntax" "FAIL" "Some files have errors" ($failures -join "; ")
    }
}

# MODULE 2: DEPENDENCY RESOLUTION TESTS
if ($Module2 -or $All) {
    Write-Host "`n=== MODULE 2: DEPENDENCY RESOLUTION TESTS ===" -ForegroundColor Cyan
    
    # Test 2.1
    Write-Host "`n[2.1] Testing WinRepairCore.ps1 module load..." -ForegroundColor Yellow
    try {
        $ErrorActionPreference = "Stop"
        . "Helper\WinRepairCore.ps1" -ErrorAction Stop
        Write-TestResult "2.1" "Dependency" "PASS" "Module loaded successfully"
    } catch {
        Write-TestResult "2.1" "Dependency" "FAIL" "Module load failed" $_.Exception.Message
    }
    
    # Test 2.2 (GUI - FullOS only)
    Write-Host "`n[2.2] Testing WinRepairGUI.ps1 module load..." -ForegroundColor Yellow
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        . "Helper\WinRepairGUI.ps1" -ErrorAction Stop
        if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
            Write-TestResult "2.2" "Dependency" "PASS" "GUI module loaded, Start-GUI exists"
        } else {
            Write-TestResult "2.2" "Dependency" "FAIL" "Start-GUI function not found"
        }
    } catch {
        Write-TestResult "2.2" "Dependency" "FAIL" "GUI module load failed" $_.Exception.Message
    }
    
    # Test 2.3
    Write-Host "`n[2.3] Testing WinRepairTUI.ps1 module load..." -ForegroundColor Yellow
    try {
        . "Helper\WinRepairTUI.ps1" -ErrorAction Stop
        if (Get-Command Start-TUI -ErrorAction SilentlyContinue) {
            Write-TestResult "2.3" "Dependency" "PASS" "TUI module loaded, Start-TUI exists"
        } else {
            Write-TestResult "2.3" "Dependency" "FAIL" "Start-TUI function not found"
        }
    } catch {
        Write-TestResult "2.3" "Dependency" "FAIL" "TUI module load failed" $_.Exception.Message
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "TEST EXECUTION SUMMARY" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

$passCount = ($global:TestResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($global:TestResults | Where-Object { $_.Status -eq "FAIL" }).Count
$totalCount = $global:TestResults.Count

Write-Host "Total Tests: $totalCount" -ForegroundColor White
Write-Host "PASS: $passCount" -ForegroundColor Green
Write-Host "FAIL: $failCount" -ForegroundColor Red

# Export results
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$reportPath = Join-Path $LogDir "formaltest-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$global:TestResults | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
Write-Host "`nReport saved to: $reportPath" -ForegroundColor Cyan

if ($failCount -gt 0) {
    Write-Host "`nFAILED TESTS:" -ForegroundColor Red
    $global:TestResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  [$($_.TestId)] $($_.Details)" -ForegroundColor Yellow
        if ($_.Error) { Write-Host "    $($_.Error)" -ForegroundColor Gray }
    }
    exit 1
} else {
    Write-Host "`nALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
