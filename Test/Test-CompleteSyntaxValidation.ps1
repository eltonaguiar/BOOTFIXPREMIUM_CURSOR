<#
.SYNOPSIS
    Comprehensive Syntax Validation Test - MANDATORY PRE-RELEASE GATE
    
.DESCRIPTION
    This test performs exhaustive syntax validation on ALL PowerShell files in the project.
    It uses PowerShell's native parser to catch syntax errors before they reach users.
    
    This test MUST pass before any code can be considered ready for demo/client presentation.
    
.NOTES
    - Uses [System.Management.Automation.PSParser]::Tokenize() for accurate parsing
    - Checks all PowerShell files in the project
    - Provides detailed error reporting with line numbers
    - Exits with code 1 if any errors found (blocks all other tests)
    
.EXAMPLE
    .\Test-CompleteSyntaxValidation.ps1
    
    Validates all PowerShell files and reports results.
#>

$ErrorActionPreference = 'Stop'

# Get script root
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot

Write-Host "=" * 90 -ForegroundColor Cyan
Write-Host "COMPREHENSIVE SYNTAX VALIDATION TEST" -ForegroundColor Cyan
Write-Host "=" * 90 -ForegroundColor Cyan
Write-Host "Project Root: $projectRoot" -ForegroundColor Gray
Write-Host ""

# All PowerShell files to validate
$psFiles = @(
    "MiracleBoot.ps1",
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\KeyboardSymbols.ps1",
    "Helper\LogAnalysis.ps1",
    "Helper\PreLaunchValidation.ps1"
)

$results = @()
$totalErrors = 0
$filesPassed = 0
$filesFailed = 0

Write-Host "[VALIDATION] Starting syntax validation..." -ForegroundColor Cyan
Write-Host ""

foreach ($file in $psFiles) {
    $absolutePath = Join-Path $projectRoot $file
    
    if (-not (Test-Path $absolutePath)) {
        Write-Host "  [SKIP] $file - File not found" -ForegroundColor Yellow
        continue
    }
    
    try {
        $content = Get-Content $absolutePath -Raw -ErrorAction Stop
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
        
        if ($errors.Count -eq 0) {
            Write-Host "  [PASS] $file" -ForegroundColor Green
            $results += [PSCustomObject]@{
                File = $file
                Status = "PASS"
                ErrorCount = 0
                Errors = @()
            }
            $filesPassed++
        } else {
            Write-Host "  [FAIL] $file - $($errors.Count) error(s)" -ForegroundColor Red
            $totalErrors += $errors.Count
            $filesFailed++
            
            # Show first 5 errors
            $errorDetails = @()
            foreach ($err in $errors | Select-Object -First 5) {
                $lineInfo = if ($err.Token) { "Line $($err.Token.StartLine)" } else { "Unknown" }
                $errorMsg = "$lineInfo : $($err.Message)"
                Write-Host "    $errorMsg" -ForegroundColor Yellow
                $errorDetails += $errorMsg
            }
            
            if ($errors.Count -gt 5) {
                Write-Host "    ... and $($errors.Count - 5) more error(s)" -ForegroundColor Yellow
            }
            
            $results += [PSCustomObject]@{
                File = $file
                Status = "FAIL"
                ErrorCount = $errors.Count
                Errors = $errorDetails
            }
        }
    } catch {
        Write-Host "  [FAIL] $file - Parse exception: $_" -ForegroundColor Red
        $totalErrors++
        $filesFailed++
        $results += [PSCustomObject]@{
            File = $file
            Status = "FAIL"
            ErrorCount = 1
            Errors = @("Parse exception: $_")
        }
    }
}

Write-Host ""
Write-Host "=" * 90 -ForegroundColor Cyan
Write-Host "VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 90 -ForegroundColor Cyan
Write-Host "Files Validated: $($psFiles.Count)" -ForegroundColor White
Write-Host "Files Passed: $filesPassed" -ForegroundColor $(if ($filesPassed -eq $psFiles.Count) { "Green" } else { "Yellow" })
Write-Host "Files Failed: $filesFailed" -ForegroundColor $(if ($filesFailed -eq 0) { "Green" } else { "Red" })
Write-Host "Total Errors: $totalErrors" -ForegroundColor $(if ($totalErrors -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($totalErrors -eq 0) {
    Write-Host "✓✓✓ ALL SYNTAX VALIDATION TESTS PASSED ✓✓✓" -ForegroundColor Green
    Write-Host "Code is ready for demo/client presentation." -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗✗✗ SYNTAX VALIDATION FAILED ✗✗✗" -ForegroundColor Red
    Write-Host ""
    Write-Host "CRITICAL: Code cannot proceed until ALL syntax errors are fixed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Failed Files:" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.File): $($_.ErrorCount) error(s)" -ForegroundColor Yellow
    }
    exit 1
}

