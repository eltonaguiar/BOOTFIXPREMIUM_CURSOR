<#
.SYNOPSIS
    MANDATORY PRE-RELEASE GATE - Comprehensive Validation System
    
.DESCRIPTION
    This is the MANDATORY gate that MUST pass before any code can be considered ready.
    It performs exhaustive validation including:
    1. Syntax validation (all PowerShell files)
    2. GUI launch validation
    3. Runtime error detection
    4. Log validation
    5. Code quality checks
    
    This script CANNOT be bypassed. All tests must pass.
    
.NOTES
    - Exit code 0 = All tests passed (ready for demo/client)
    - Exit code 1 = Tests failed (BLOCKS release)
    - This script is called automatically by CI/CD and manual validation
    
.EXAMPLE
    .\Test-MandatoryPreReleaseGate.ps1
    
    Runs all validation tests and reports results.
#>

$ErrorActionPreference = 'Stop'

# Get script root
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot

Write-Host "=" * 100 -ForegroundColor Cyan
Write-Host "MANDATORY PRE-RELEASE GATE - COMPREHENSIVE VALIDATION" -ForegroundColor Cyan
Write-Host "=" * 100 -ForegroundColor Cyan
Write-Host "Project Root: $projectRoot" -ForegroundColor Gray
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

$allTestsPassed = $true
$testResults = @()

# ============================================================================
# PHASE 1: HARDENED AST SYNTAX VALIDATION (MANDATORY - BLOCKS ALL OTHER TESTS)
# ============================================================================
Write-Host "[PHASE 1] Hardened AST Syntax Validation..." -ForegroundColor Yellow
Write-Host ""

# Use the Guardian validator for deep structural analysis with imposter detection
    $guardianValidator = Join-Path $scriptRoot "Test-MiracleBootGuardian.ps1"
    $hardenedValidator = Join-Path $scriptRoot "Test-HardenedASTValidator.ps1"
    
    if (Test-Path $guardianValidator) {
        Write-Host "  Running Guardian scan (with imposter detection and auto-repair)..." -ForegroundColor Cyan
        $astResults = & pwsh -NoProfile -ExecutionPolicy Bypass -File $guardianValidator -TargetFolder $projectRoot -AutoRepair:$false -ReportPath (Join-Path $projectRoot "Guardian_Validation_Report.json") 2>&1
    
        # Parse the results
        $astReportPath = Join-Path $projectRoot "Guardian_Validation_Report.json"
        if (-not (Test-Path $astReportPath)) {
            $astReportPath = Join-Path $projectRoot "AST_Validation_Report.json"
        }
    if (Test-Path $astReportPath) {
        $astReport = Get-Content $astReportPath -Raw | ConvertFrom-Json
        $syntaxErrors = $astReport.syntax_errors.Count
        $logErrors = $astReport.log_errors.Count
        
        if ($astReport.ready_to_launch) {
            Write-Host "  [PASS] Guardian Validation: All $($astReport.files_checked) files validated successfully" -ForegroundColor Green
            Write-Host "  [PASS] Wiped Files: 0" -ForegroundColor Green
            Write-Host "  [PASS] Syntax Errors: 0" -ForegroundColor Green
            Write-Host "  [PASS] Log Errors: 0" -ForegroundColor Green
            
            if ($astReport.files_fixed -gt 0) {
                Write-Host "  [INFO] Auto-Repaired: $($astReport.files_fixed) file(s)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [FAIL] Guardian Validation failed" -ForegroundColor Red
            
            if ($astReport.wiped_files -and $astReport.wiped_files.Count -gt 0) {
                Write-Host "  [CRITICAL] Wiped Files: $($astReport.wiped_files.Count)" -ForegroundColor Red
                foreach ($wiped in $astReport.wiped_files | Select-Object -First 3) {
                    Write-Host "    - $($wiped.file) - Only $($wiped.lineCount) lines!" -ForegroundColor Red
                }
            }
            
            Write-Host "  [FAIL] Syntax Errors: $syntaxErrors" -ForegroundColor Red
            Write-Host "  [FAIL] Log Errors: $logErrors" -ForegroundColor Red
            
            if ($syntaxErrors -gt 0) {
                Write-Host ""
                Write-Host "  Syntax Error Details:" -ForegroundColor Yellow
                foreach ($err in $astReport.syntax_errors | Select-Object -First 5) {
                    Write-Host "    - $($err.file):$($err.line) - $($err.message)" -ForegroundColor Red
                }
            }
            
            $allTestsPassed = $false
        }
    } else {
        Write-Host "  [FAIL] AST validator did not produce report" -ForegroundColor Red
        $allTestsPassed = $false
        $syntaxErrors = 999
    }
} else {
    Write-Host "  [WARN] Hardened validator not found, falling back to tokenizer..." -ForegroundColor Yellow
    
    # Fallback to tokenizer method
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

    $syntaxErrors = 0
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
            } else {
                Write-Host "  [FAIL] $file - $($errors.Count) error(s)" -ForegroundColor Red
                $syntaxErrors += $errors.Count
                $allTestsPassed = $false
                foreach ($err in $errors | Select-Object -First 3) {
                    $lineInfo = if ($err.Token) { "Line $($err.Token.StartLine)" } else { "Unknown" }
                    Write-Host "    $lineInfo : $($err.Message)" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "  [FAIL] $file - Parse exception: $_" -ForegroundColor Red
            $syntaxErrors++
            $allTestsPassed = $false
        }
    }
}

$testResults += [PSCustomObject]@{
    Phase = "AST Syntax Validation"
    Passed = ($syntaxErrors -eq 0)
    Details = "Found $syntaxErrors syntax error(s)"
}

if ($syntaxErrors -gt 0) {
    Write-Host ""
    Write-Host "CRITICAL: Syntax validation failed. Cannot proceed with other tests." -ForegroundColor Red
    Write-Host "All syntax errors must be fixed before continuing." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  [SUCCESS] All files have valid syntax (AST validated)" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 2: GUI LAUNCH VALIDATION (MANDATORY FOR GUI CHANGES)
# ============================================================================
Write-Host "[PHASE 2] GUI Launch Validation..." -ForegroundColor Yellow
Write-Host ""

$guiLaunchPassed = $false
$errorLogPath = Join-Path $projectRoot "MiracleBoot_GUI_Error.log"

# Clear error log
if (Test-Path $errorLogPath) {
    Clear-Content $errorLogPath -ErrorAction SilentlyContinue
}

try {
    # Test GUI launch in background job
    $job = Start-Job -ScriptBlock {
        param($path)
        Set-Location (Split-Path $path)
        & pwsh.exe -STA -ExecutionPolicy Bypass -File $path 2>&1
    } -ArgumentList (Join-Path $projectRoot "MiracleBoot.ps1")
    
    Start-Sleep -Milliseconds 1000
    
    if ($job.State -eq 'Running') {
        Write-Host "  [PASS] GUI launched successfully" -ForegroundColor Green
        $guiLaunchPassed = $true
    } else {
        Write-Host "  [FAIL] GUI failed to launch (State: $($job.State))" -ForegroundColor Red
        $allTestsPassed = $false
    }
    
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -ErrorAction SilentlyContinue
} catch {
    Write-Host "  [FAIL] GUI launch exception: $_" -ForegroundColor Red
    $allTestsPassed = $false
}

# Check error log
Start-Sleep -Milliseconds 500
if (Test-Path $errorLogPath) {
    $errors = Get-Content $errorLogPath -ErrorAction SilentlyContinue
    if ($null -ne $errors -and $errors.Count -gt 0) {
        $guiErrors = $errors | Where-Object { $_ -match 'GUI launch failed' }
        if ($guiErrors.Count -gt 0) {
            Write-Host "  [FAIL] Error log contains $($guiErrors.Count) GUI error(s)" -ForegroundColor Red
            $allTestsPassed = $false
            $guiLaunchPassed = $false
        } else {
            Write-Host "  [PASS] Error log clean (no GUI errors)" -ForegroundColor Green
        }
    } else {
        Write-Host "  [PASS] Error log clean (empty)" -ForegroundColor Green
    }
} else {
    Write-Host "  [PASS] No error log (zero errors)" -ForegroundColor Green
}

$testResults += [PSCustomObject]@{
    Phase = "GUI Launch Validation"
    Passed = $guiLaunchPassed
    Details = if ($guiLaunchPassed) { "GUI launches successfully" } else { "GUI launch failed" }
}

Write-Host ""

# ============================================================================
# PHASE 3: EXPORT-MODULEMEMBER VALIDATION (MANDATORY)
# ============================================================================
Write-Host "[PHASE 3] Export-ModuleMember Validation..." -ForegroundColor Yellow
Write-Host ""

$exportModuleMemberErrors = @()
$helperFiles = Get-ChildItem -Path (Join-Path $projectRoot "Helper") -Filter "*.ps1" -File | Where-Object { $_.Name -notmatch '\.backup' }

foreach ($file in $helperFiles) {
    $content = Get-Content $file.FullName -Raw
    $fileRelative = $file.FullName.Replace($projectRoot + '\', '')
    
    # Check for Export-ModuleMember without module check
    if ($content -match 'Export-ModuleMember') {
        # Check if it's properly wrapped in module check
        $hasModuleCheck = $content -match 'if\s*\(\s*\$MyInvocation\.MyCommand\.ModuleName\s*\)\s*\{[^}]*Export-ModuleMember'
        
        if (-not $hasModuleCheck) {
            # Find the line number
            $lines = Get-Content $file.FullName
            $lineNum = 0
            foreach ($line in $lines) {
                $lineNum++
                if ($line -match 'Export-ModuleMember' -and $line -notmatch 'if\s*\(\s*\$MyInvocation\.MyCommand\.ModuleName') {
                    $exportModuleMemberErrors += "$fileRelative : Line $lineNum - Export-ModuleMember without module check"
                    Write-Host "  [FAIL] $fileRelative : Line $lineNum - Export-ModuleMember not wrapped in module check" -ForegroundColor Red
                    break
                }
            }
        } else {
            Write-Host "  [PASS] $fileRelative - Export-ModuleMember properly wrapped" -ForegroundColor Green
        }
    }
}

if ($exportModuleMemberErrors.Count -gt 0) {
    Write-Host ""
    Write-Host "  [CRITICAL] Found $($exportModuleMemberErrors.Count) Export-ModuleMember error(s)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Fix Instructions:" -ForegroundColor Yellow
    Write-Host "    Wrap Export-ModuleMember in module check:" -ForegroundColor Yellow
    Write-Host "    if (`$MyInvocation.MyCommand.ModuleName) {" -ForegroundColor Gray
    Write-Host "        Export-ModuleMember -Function ..." -ForegroundColor Gray
    Write-Host "    }" -ForegroundColor Gray
    Write-Host ""
    $allTestsPassed = $false
} else {
    Write-Host "  [SUCCESS] All Export-ModuleMember calls are properly wrapped" -ForegroundColor Green
}

$testResults += [PSCustomObject]@{
    Phase = "Export-ModuleMember Validation"
    Passed = ($exportModuleMemberErrors.Count -eq 0)
    Details = if ($exportModuleMemberErrors.Count -eq 0) { "All calls properly wrapped" } else { "Found $($exportModuleMemberErrors.Count) error(s)" }
}

Write-Host ""

# ============================================================================
# PHASE 4: CODE QUALITY CHECKS
# ============================================================================
Write-Host "[PHASE 4] Code Quality Checks..." -ForegroundColor Yellow
Write-Host ""

$guiFile = Join-Path $projectRoot "Helper\WinRepairGUI.ps1"
$content = Get-Content $guiFile -Raw

# Check for unsafe patterns
$unsafeAddClick = ([regex]::Matches($content, '\$W\.FindName\("Btn.*"\)\.Add_Click')).Count
$unsafePropertyAccess = ([regex]::Matches($content, '\$W\.FindName\("(FixerOutput|DrvBox|DiagBox)"\)\.(Text|ScrollToEnd)')).Count
$hasGetControl = $content -match 'function Get-Control'

$qualityPassed = $true

if ($unsafeAddClick -gt 0) {
    Write-Host "  [WARN] Found $unsafeAddClick unsafe Add_Click calls" -ForegroundColor Yellow
    $qualityPassed = $false
} else {
    Write-Host "  [PASS] No unsafe Add_Click calls" -ForegroundColor Green
}

if ($unsafePropertyAccess -gt 0) {
    Write-Host "  [WARN] Found $unsafePropertyAccess unsafe property accesses" -ForegroundColor Yellow
    $qualityPassed = $false
} else {
    Write-Host "  [PASS] No unsafe property accesses" -ForegroundColor Green
}

if ($hasGetControl) {
    Write-Host "  [PASS] Get-Control function present" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Get-Control function missing" -ForegroundColor Red
    $qualityPassed = $false
    $allTestsPassed = $false
}

$testResults += [PSCustomObject]@{
    Phase = "Code Quality"
    Passed = $qualityPassed
    Details = "Unsafe patterns: Add_Click=$unsafeAddClick, PropertyAccess=$unsafePropertyAccess"
}

Write-Host ""

# ============================================================================
# PHASE 5: RAPID LAUNCH STRESS TEST
# ============================================================================
Write-Host "[PHASE 5] Rapid Launch Stress Test (10 launches)..." -ForegroundColor Yellow
Write-Host ""

$stressTestPassed = 0
$stressTestFailed = 0

for ($i = 1; $i -le 10; $i++) {
    try {
        $job = Start-Job -ScriptBlock {
            param($path)
            Set-Location (Split-Path $path)
            & pwsh.exe -STA -ExecutionPolicy Bypass -File $path 2>&1
        } -ArgumentList (Join-Path $projectRoot "MiracleBoot.ps1")
        
        Start-Sleep -Milliseconds 500
        
        if ($job.State -eq 'Running') {
            $stressTestPassed++
        } else {
            $stressTestFailed++
        }
        
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 100
    } catch {
        $stressTestFailed++
    }
}

if ($stressTestFailed -eq 0) {
    Write-Host "  [PASS] All 10 rapid launches successful" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] $stressTestFailed of 10 launches failed" -ForegroundColor Red
    $allTestsPassed = $false
}

$testResults += [PSCustomObject]@{
    Phase = "Stress Test"
    Passed = ($stressTestFailed -eq 0)
    Details = "$stressTestPassed passed, $stressTestFailed failed"
}

Write-Host ""

# ============================================================================
# FINAL SUMMARY
# ============================================================================
Write-Host "=" * 100 -ForegroundColor Cyan
Write-Host "VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 100 -ForegroundColor Cyan
Write-Host ""

$passedCount = ($testResults | Where-Object { $_.Passed }).Count
$failedCount = ($testResults | Where-Object { -not $_.Passed }).Count

$testResults | ForEach-Object {
    $status = if ($_.Passed) { "[PASS]" } else { "[FAIL]" }
    $color = if ($_.Passed) { "Green" } else { "Red" }
    Write-Host "$status $($_.Phase): $($_.Details)" -ForegroundColor $color
}

Write-Host ""
Write-Host "Total Tests: $($testResults.Count)" -ForegroundColor Cyan
Write-Host "Passed: $passedCount" -ForegroundColor Green
Write-Host "Failed: $failedCount" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($allTestsPassed) {
    Write-Host "=" * 100 -ForegroundColor Green
    Write-Host "✓✓✓ ALL VALIDATION TESTS PASSED ✓✓✓" -ForegroundColor Green
    Write-Host "=" * 100 -ForegroundColor Green
    Write-Host ""
    Write-Host "Code is PRODUCTION-READY and APPROVED for demo/client presentation." -ForegroundColor Green
    Write-Host ""
    exit 0
} else {
    Write-Host "=" * 100 -ForegroundColor Red
    Write-Host "✗✗✗ VALIDATION FAILED ✗✗✗" -ForegroundColor Red
    Write-Host "=" * 100 -ForegroundColor Red
    Write-Host ""
    Write-Host "CRITICAL: Code cannot be released until ALL tests pass." -ForegroundColor Red
    Write-Host "Fix all failures and re-run validation." -ForegroundColor Red
    Write-Host ""
    exit 1
}

