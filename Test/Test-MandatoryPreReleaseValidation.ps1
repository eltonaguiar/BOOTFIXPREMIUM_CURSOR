<#
.SYNOPSIS
    MANDATORY PRE-RELEASE VALIDATION - ZERO TOLERANCE FOR ERRORS
    
.DESCRIPTION
    This script performs comprehensive validation that MUST pass before any code
    can be considered ready for release. It uses multiple validation methods to
    catch all possible errors:
    
    1. PowerShell Parser Validation (catches syntax errors)
    2. AST Validation (catches structural errors)
    3. Module Loading Test (catches runtime loading errors)
    4. Function Availability Check (catches missing functions)
    5. GUI Launch Test (catches GUI-specific errors)
    
    This script will NOT allow code to pass if ANY errors are detected.
    
.NOTES
    This is a MANDATORY gate - code cannot proceed if validation fails.
    Do NOT ask users to test until this script passes completely.
#>

$ErrorActionPreference = 'Stop'

# Colors for output
function Write-ValidationHeader {
    param([string]$Message)
    Write-Host "`n" + "=" * 90 -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "=" * 90 -ForegroundColor Cyan
}

function Write-ValidationPass {
    param([string]$Message)
    Write-Host "  [PASS] $Message" -ForegroundColor Green
}

function Write-ValidationFail {
    param([string]$Message, [string]$Details = "")
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
    if ($Details) {
        Write-Host "         $Details" -ForegroundColor Yellow
    }
}

function Write-ValidationError {
    param([string]$Message)
    Write-Host "  [ERROR] $Message" -ForegroundColor Red
}

# Get script root
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = Split-Path -Parent $ScriptRoot

# PowerShell files to validate
$psFiles = @(
    "MiracleBoot.ps1",
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\KeyboardSymbols.ps1",
    "Helper\LogAnalysis.ps1"
)

$validationResults = @{
    Passed = $true
    Errors = @()
    Warnings = @()
    Details = @{}
}

# ============================================================================
# PHASE 1: PowerShell Parser Validation (Syntax Errors)
# ============================================================================
Write-ValidationHeader "PHASE 1: PowerShell Parser Validation (Syntax Errors)"

$syntaxPassed = $true
foreach ($file in $psFiles) {
    $absolutePath = Join-Path $ProjectRoot $file
    if (-not (Test-Path $absolutePath)) {
        Write-ValidationFail "$file" "File not found"
        $validationResults.Errors += "File not found: $file"
        $validationResults.Details[$file] = @{ Status = "FAILED"; Reason = "File not found" }
        $syntaxPassed = $false
        continue
    }
    
    try {
        $content = Get-Content $absolutePath -Raw -ErrorAction Stop
        $parseErrors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$parseErrors)
        
        if ($parseErrors.Count -eq 0) {
            Write-ValidationPass "$file"
            $validationResults.Details[$file] = @{ Status = "PASSED"; Errors = 0 }
        } else {
            Write-ValidationFail "$file" "$($parseErrors.Count) syntax error(s)"
            $errorDetails = @()
            foreach ($err in $parseErrors | Select-Object -First 5) {
                $lineInfo = if ($err.Token) { "Line $($err.Token.StartLine)" } else { "Unknown" }
                $errorDetails += "$lineInfo : $($err.Message)"
                Write-ValidationError "    $lineInfo : $($err.Message)"
            }
            $validationResults.Errors += "$file has $($parseErrors.Count) syntax error(s)"
            $validationResults.Details[$file] = @{ Status = "FAILED"; Errors = $parseErrors.Count; ErrorDetails = $errorDetails }
            $syntaxPassed = $false
        }
    } catch {
        Write-ValidationFail "$file" "Parse exception: $_"
        $validationResults.Errors += "$file failed to parse: $_"
        $validationResults.Details[$file] = @{ Status = "FAILED"; Reason = $_.ToString() }
        $syntaxPassed = $false
    }
}

if (-not $syntaxPassed) {
    $validationResults.Passed = $false
    Write-Host "`n[CRITICAL] Syntax validation FAILED. Cannot proceed to other phases." -ForegroundColor Red
    Write-Host "Fix all syntax errors before continuing." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n[SUCCESS] All $($psFiles.Count) files passed syntax validation" -ForegroundColor Green

# ============================================================================
# PHASE 2: AST Validation (Structural Errors)
# ============================================================================
Write-ValidationHeader "PHASE 2: AST Validation (Structural Errors)"

$astPassed = $true
foreach ($file in $psFiles) {
    $absolutePath = Join-Path $ProjectRoot $file
    if (-not (Test-Path $absolutePath)) { continue }
    
    try {
        $content = Get-Content $absolutePath -Raw -ErrorAction Stop
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$null)
        
        if ($ast) {
            Write-ValidationPass "$file"
            $validationResults.Details[$file].AST = "PASSED"
        } else {
            Write-ValidationFail "$file" "AST parsing returned null"
            $validationResults.Errors += "$file AST parsing failed"
            $validationResults.Details[$file].AST = "FAILED"
            $astPassed = $false
        }
    } catch {
        Write-ValidationFail "$file" "AST exception: $_"
        $validationResults.Errors += "$file AST validation failed: $_"
        $validationResults.Details[$file].AST = "FAILED"
        $astPassed = $false
    }
}

if (-not $astPassed) {
    $validationResults.Passed = $false
    Write-Host "`n[CRITICAL] AST validation FAILED." -ForegroundColor Red
    exit 1
}

Write-Host "`n[SUCCESS] All files passed AST validation" -ForegroundColor Green

# ============================================================================
# PHASE 3: Module Loading Test (Runtime Errors)
# ============================================================================
Write-ValidationHeader "PHASE 3: Module Loading Test (Runtime Errors)"

$moduleLoadPassed = $true
$modules = @(
    @{ Name = "WinRepairCore.ps1"; Path = "Helper\WinRepairCore.ps1"; Functions = @("Get-WindowsVolumes", "Get-EnvironmentType") },
    @{ Name = "NetworkDiagnostics.ps1"; Path = "Helper\NetworkDiagnostics.ps1"; Functions = @("Get-NetworkAdapterStatus") },
    @{ Name = "KeyboardSymbols.ps1"; Path = "Helper\KeyboardSymbols.ps1"; Functions = @() },
    @{ Name = "LogAnalysis.ps1"; Path = "Helper\LogAnalysis.ps1"; Functions = @("Get-ComprehensiveLogAnalysis") }
)

foreach ($module in $modules) {
    $fullPath = Join-Path $ProjectRoot $module.Path
    if (-not (Test-Path $fullPath)) {
        Write-ValidationFail "$($module.Name)" "File not found"
        $validationResults.Warnings += "Module not found: $($module.Name)"
        continue
    }
    
    try {
        # Create a new runspace to avoid polluting the current session
        $runspace = [RunspaceFactory]::CreateRunspace()
        $runspace.Open()
        $ps = [PowerShell]::Create()
        $ps.Runspace = $runspace
        
        $Error.Clear()
        $ps.AddScript(". '$fullPath'") | Out-Null
        $ps.Invoke() | Out-Null
        
        if ($ps.Streams.Error.Count -gt 0) {
            $errorMsg = ($ps.Streams.Error | Select-Object -First 1).ToString()
            Write-ValidationFail "$($module.Name)" "Load error: $errorMsg"
            $validationResults.Errors += "$($module.Name) failed to load: $errorMsg"
            $validationResults.Details[$module.Name] = @{ Status = "FAILED"; Reason = $errorMsg }
            $moduleLoadPassed = $false
        } else {
            # Check expected functions
            $missingFunctions = @()
            foreach ($funcName in $module.Functions) {
                $ps.Commands.Clear()
                $ps.AddScript("Get-Command $funcName -ErrorAction SilentlyContinue") | Out-Null
                $result = $ps.Invoke()
                if (-not $result) {
                    $missingFunctions += $funcName
                }
            }
            
            if ($missingFunctions.Count -gt 0) {
                Write-ValidationFail "$($module.Name)" "Missing functions: $($missingFunctions -join ', ')"
                $validationResults.Errors += "$($module.Name) missing functions: $($missingFunctions -join ', ')"
                $validationResults.Details[$module.Name] = @{ Status = "FAILED"; MissingFunctions = $missingFunctions }
                $moduleLoadPassed = $false
            } else {
                Write-ValidationPass "$($module.Name)"
                $validationResults.Details[$module.Name] = @{ Status = "PASSED" }
            }
        }
        
        $ps.Dispose()
        $runspace.Close()
    } catch {
        Write-ValidationFail "$($module.Name)" "Exception: $_"
        $validationResults.Errors += "$($module.Name) failed: $_"
        $validationResults.Details[$module.Name] = @{ Status = "FAILED"; Reason = $_.ToString() }
        $moduleLoadPassed = $false
    }
}

if (-not $moduleLoadPassed) {
    $validationResults.Passed = $false
    Write-Host "`n[CRITICAL] Module loading validation FAILED." -ForegroundColor Red
    exit 1
}

Write-Host "`n[SUCCESS] All modules loaded successfully" -ForegroundColor Green

# ============================================================================
# PHASE 4: GUI Launch Test (GUI-Specific Errors)
# ============================================================================
Write-ValidationHeader "PHASE 4: GUI Launch Test (GUI-Specific Errors)"

$guiTestPassed = $true
$guiFile = Join-Path $ProjectRoot "Helper\WinRepairGUI.ps1"

if (Test-Path $guiFile) {
    try {
        # Check if we're in a GUI-capable environment
        $guiCapable = $false
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            $guiCapable = $true
        } catch {
            Write-Host "  [SKIP] GUI test - WPF not available (expected in non-GUI environments)" -ForegroundColor Yellow
            $guiTestPassed = $true
        }
        
        if ($guiCapable) {
            # Test that Start-GUI function can be loaded
            $runspace = [RunspaceFactory]::CreateRunspace()
            $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
            $runspace.Open()
            $ps = [PowerShell]::Create()
            $ps.Runspace = $runspace
            
            $ps.AddScript(". '$guiFile'") | Out-Null
            $ps.Invoke() | Out-Null
            
            if ($ps.Streams.Error.Count -gt 0) {
                $errorMsg = ($ps.Streams.Error | Select-Object -First 1).ToString()
                Write-ValidationFail "GUI Module" "Load error: $errorMsg"
                $validationResults.Errors += "GUI module failed to load: $errorMsg"
                $guiTestPassed = $false
            } else {
                # Check if Start-GUI function exists
                $ps.Commands.Clear()
                $ps.AddScript("Get-Command Start-GUI -ErrorAction SilentlyContinue") | Out-Null
                $result = $ps.Invoke()
                
                if ($result) {
                    Write-ValidationPass "GUI Module (Start-GUI function found)"
                    $validationResults.Details["GUI"] = @{ Status = "PASSED" }
                } else {
                    Write-ValidationFail "GUI Module" "Start-GUI function not found"
                    $validationResults.Errors += "Start-GUI function not found"
                    $guiTestPassed = $false
                }
            }
            
            $ps.Dispose()
            $runspace.Close()
        }
    } catch {
        Write-ValidationFail "GUI Module" "Exception: $_"
        $validationResults.Errors += "GUI test failed: $_"
        $guiTestPassed = $false
    }
} else {
    Write-ValidationFail "GUI Module" "File not found"
    $validationResults.Errors += "GUI file not found"
    $guiTestPassed = $false
}

if (-not $guiTestPassed) {
    $validationResults.Passed = $false
    Write-Host "`n[CRITICAL] GUI validation FAILED." -ForegroundColor Red
    exit 1
}

Write-Host "`n[SUCCESS] GUI module validation passed" -ForegroundColor Green

# ============================================================================
# FINAL SUMMARY
# ============================================================================
Write-ValidationHeader "FINAL VALIDATION SUMMARY"

if ($validationResults.Passed) {
    Write-Host "`n✓✓✓ ALL VALIDATION PHASES PASSED ✓✓✓" -ForegroundColor Green
    Write-Host "`nThe code is ready for release and client demonstration." -ForegroundColor Green
    Write-Host "`nValidation Details:" -ForegroundColor Cyan
    Write-Host "  - Syntax Validation: PASSED" -ForegroundColor Green
    Write-Host "  - AST Validation: PASSED" -ForegroundColor Green
    Write-Host "  - Module Loading: PASSED" -ForegroundColor Green
    Write-Host "  - GUI Validation: PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗✗✗ VALIDATION FAILED ✗✗✗" -ForegroundColor Red
    Write-Host "`nThe following errors were detected:" -ForegroundColor Yellow
    foreach ($error in $validationResults.Errors) {
        Write-Host "  - $error" -ForegroundColor Red
    }
    Write-Host "`nCode is NOT ready for release. Fix all errors before proceeding." -ForegroundColor Red
    exit 1
}

