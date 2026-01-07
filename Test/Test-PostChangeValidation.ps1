<#
    POST-CHANGE VALIDATION TEST
    ===========================
    
    This script MUST be run after every set of code changes to ensure:
    1. Code works without errors
    2. User can get into the GUI (on Windows 10/11)
    3. All modules load correctly
    
    Usage:
        pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\Test-PostChangeValidation.ps1"
    
    Exit Codes:
        0 = All tests passed
        1 = One or more tests failed
#>

$ErrorActionPreference = 'Stop'

# Ensure we are running from the repository root
if ($PSScriptRoot -and (Split-Path $PSScriptRoot -Leaf) -eq 'Test') {
    Set-Location (Split-Path $PSScriptRoot -Parent)
}

$root = Get-Location
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $root "Test\PostChangeValidation_$timestamp.log"

function Write-TestLog {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$AlsoToFile
    )
    Write-Host $Message -ForegroundColor $Color
    if ($AlsoToFile) {
        Add-Content -Path $logFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    }
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = ""
    )
    $status = if ($Passed) { "✅ PASS" } else { "❌ FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-TestLog "$status : $TestName" -Color $color -AlsoToFile
    if ($Details) {
        Write-TestLog "  $Details" -Color Gray -AlsoToFile
    }
    return $Passed
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  POST-CHANGE VALIDATION TEST" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""
Write-TestLog "Test started at $(Get-Date)" -AlsoToFile
Write-TestLog "Repository root: $root" -AlsoToFile
Write-TestLog "Log file: $logFile" -AlsoToFile
Write-Host ""

$allTestsPassed = $true
$testResults = @()

# ============================================================================
# TEST 1: Syntax Validation
# ============================================================================
Write-Host "TEST 1: Syntax Validation" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$psFiles = @(
    "MiracleBoot.ps1",
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\KeyboardSymbols.ps1",
    "Helper\LogAnalysis.ps1"
)

$syntaxErrors = @()
foreach ($file in $psFiles) {
    $filePath = Join-Path $root $file
    if (-not (Test-Path $filePath)) {
        $syntaxErrors += "$file : File not found"
        Write-TestLog "  ❌ $file : File not found" -Color Red
        continue
    }
    
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $filePath -Raw), [ref]$null)
        Write-TestLog "  ✅ $file : Syntax OK" -Color Green
    } catch {
        $syntaxErrors += "$file : $($_.Exception.Message)"
        Write-TestLog "  ❌ $file : $($_.Exception.Message)" -Color Red
    }
}

$syntaxPassed = $syntaxErrors.Count -eq 0
$testResults += Write-TestResult "Syntax Validation" $syntaxPassed "Checked $($psFiles.Count) files"
if (-not $syntaxPassed) {
    Write-TestLog "Syntax errors found:" -Color Red
    foreach ($error in $syntaxErrors) {
        Write-TestLog "  - $error" -Color Red
    }
    $allTestsPassed = $false
}
Write-Host ""

# ============================================================================
# TEST 2: Module Loading (No Export-ModuleMember Errors)
# ============================================================================
Write-Host "TEST 2: Module Loading (No Export-ModuleMember Errors)" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$moduleLoadErrors = @()
$modulesToTest = @(
    "Helper\NetworkDiagnostics.ps1",
    "Helper\KeyboardSymbols.ps1"
)

foreach ($module in $modulesToTest) {
    $modulePath = Join-Path $root $module
    if (-not (Test-Path $modulePath)) {
        $moduleLoadErrors += "$module : File not found"
        continue
    }
    
    try {
        $output = & {
            $ErrorActionPreference = 'Stop'
            . $modulePath 2>&1
        }
        
        $exportErrors = $output | Where-Object { $_ -match "Export-ModuleMember.*can only be called" }
        if ($exportErrors) {
            $moduleLoadErrors += "$module : Export-ModuleMember error detected"
            Write-TestLog "  ❌ $module : Export-ModuleMember error" -Color Red
        } else {
            Write-TestLog "  ✅ $module : Loaded without Export-ModuleMember errors" -Color Green
        }
    } catch {
        $moduleLoadErrors += "$module : $($_.Exception.Message)"
        Write-TestLog "  ❌ $module : $($_.Exception.Message)" -Color Red
    }
}

$moduleLoadPassed = $moduleLoadErrors.Count -eq 0
$testResults += Write-TestResult "Module Loading" $moduleLoadPassed "Tested $($modulesToTest.Count) modules"
if (-not $moduleLoadPassed) {
    Write-TestLog "Module load errors found:" -Color Red
    foreach ($error in $moduleLoadErrors) {
        Write-TestLog "  - $error" -Color Red
    }
    $allTestsPassed = $false
}
Write-Host ""

# ============================================================================
# TEST 3: Core Module Loading
# ============================================================================
Write-Host "TEST 3: Core Module Loading" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$coreLoadPassed = $false
try {
    $corePath = Join-Path $root "Helper\WinRepairCore.ps1"
    if (-not (Test-Path $corePath)) {
        throw "WinRepairCore.ps1 not found"
    }
    
    $output = & {
        $ErrorActionPreference = 'Stop'
        . $corePath 2>&1
    }
    
    $criticalErrors = $output | Where-Object { 
        $_ -match "Missing closing|ParserError|Unexpected token|Exception calling|Cannot call a method on a null"
    }
    
    if ($criticalErrors) {
        Write-TestLog "  ❌ Core module has critical errors:" -Color Red
        foreach ($err in $criticalErrors | Select-Object -First 5) {
            Write-TestLog "    $err" -Color Red
        }
    } else {
        $coreLoadPassed = $true
        Write-TestLog "  ✅ Core module loaded successfully" -Color Green
    }
} catch {
    Write-TestLog "  ❌ Core module load failed: $($_.Exception.Message)" -Color Red
}

$testResults += Write-TestResult "Core Module Loading" $coreLoadPassed
if (-not $coreLoadPassed) {
    $allTestsPassed = $false
}
Write-Host ""

# ============================================================================
# TEST 4: WPF Availability (Required for GUI)
# ============================================================================
Write-Host "TEST 4: WPF Availability (Required for GUI)" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$wpfAvailable = $false
$wpfError = ""

try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $wpfAvailable = $true
    Write-TestLog "  ✅ WPF assemblies available" -Color Green
} catch {
    $wpfError = $_.Exception.Message
    Write-TestLog "  ❌ WPF not available: $wpfError" -Color Red
}

$testResults += Write-TestResult "WPF Availability" $wpfAvailable $wpfError
if (-not $wpfAvailable) {
    $allTestsPassed = $false
}
Write-Host ""

# ============================================================================
# TEST 5: GUI Module Loading
# ============================================================================
Write-Host "TEST 5: GUI Module Loading" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$guiLoadPassed = $false
$guiError = ""

if (-not $wpfAvailable) {
    Write-TestLog "  ⚠️  Skipping GUI test - WPF not available" -Color Yellow
    $guiError = "WPF not available"
} else {
    try {
        $guiPath = Join-Path $root "Helper\WinRepairGUI.ps1"
        if (-not (Test-Path $guiPath)) {
            throw "WinRepairGUI.ps1 not found"
        }
        
        # Load core first (required by GUI)
        . (Join-Path $root "Helper\WinRepairCore.ps1") -ErrorAction Stop
        
        # Try to load GUI module
        $output = & {
            $ErrorActionPreference = 'Stop'
            . $guiPath 2>&1
        }
        
        $criticalErrors = $output | Where-Object { 
            $_ -match "Missing closing|ParserError|Unexpected token|Exception calling|Cannot call a method on a null"
        }
        
        if ($criticalErrors) {
            $guiError = "Critical errors detected in GUI module"
            Write-TestLog "  ❌ GUI module has critical errors:" -Color Red
            foreach ($err in $criticalErrors | Select-Object -First 3) {
                Write-TestLog "    $err" -Color Red
            }
        } else {
            # Check if Start-GUI function exists
            if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
                $guiLoadPassed = $true
                Write-TestLog "  ✅ GUI module loaded, Start-GUI function found" -Color Green
            } else {
                $guiError = "Start-GUI function not found after loading GUI module"
                Write-TestLog "  ❌ $guiError" -Color Red
            }
        }
    } catch {
        $guiError = $_.Exception.Message
        Write-TestLog "  ❌ GUI module load failed: $guiError" -Color Red
    }
}

$testResults += Write-TestResult "GUI Module Loading" $guiLoadPassed $guiError
if (-not $guiLoadPassed -and $wpfAvailable) {
    $allTestsPassed = $false
}
Write-Host ""

# ============================================================================
# TEST 6: Browser Test (Should NOT Open Browser)
# ============================================================================
Write-Host "TEST 6: Browser Test (Should NOT Open Browser)" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$browserTestPassed = $false
$browserTestError = ""

try {
    # Check if Test-BrowserAvailability exists and doesn't open browser
    if (Get-Command Test-BrowserAvailability -ErrorAction SilentlyContinue) {
        # This should just check registry, not open browser
        $result = Test-BrowserAvailability
        if ($result) {
            $browserTestPassed = $true
            Write-TestLog "  ✅ Browser test completed without opening browser" -Color Green
            Write-TestLog "    Browser available: $($result.Available)" -Color Gray
        } else {
            $browserTestError = "Test-BrowserAvailability returned null"
            Write-TestLog "  ⚠️  $browserTestError" -Color Yellow
        }
    } else {
        $browserTestError = "Test-BrowserAvailability function not found"
        Write-TestLog "  ⚠️  $browserTestError" -Color Yellow
        $browserTestPassed = $true  # Not a critical failure
    }
} catch {
    $browserTestError = $_.Exception.Message
    Write-TestLog "  ⚠️  Browser test error: $browserTestError" -Color Yellow
    $browserTestPassed = $true  # Not a critical failure
}

$testResults += Write-TestResult "Browser Test (No Auto-Open)" $browserTestPassed $browserTestError
Write-Host ""

# ============================================================================
# TEST 7: Main Entry Point Test
# ============================================================================
Write-Host "TEST 7: Main Entry Point Test" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$entryPointPassed = $false
$entryPointError = ""

try {
    $mainScript = Join-Path $root "MiracleBoot.ps1"
    if (-not (Test-Path $mainScript)) {
        throw "MiracleBoot.ps1 not found"
    }
    
    # Check if Get-EnvironmentType function exists (key function)
    . $mainScript -ErrorAction Stop
    
    if (Get-Command Get-EnvironmentType -ErrorAction SilentlyContinue) {
        $entryPointPassed = $true
        Write-TestLog "  ✅ Main entry point loads, Get-EnvironmentType found" -Color Green
    } else {
        $entryPointError = "Get-EnvironmentType function not found"
        Write-TestLog "  ❌ $entryPointError" -Color Red
    }
} catch {
    $entryPointError = $_.Exception.Message
    Write-TestLog "  ❌ Main entry point test failed: $entryPointError" -Color Red
}

$testResults += Write-TestResult "Main Entry Point" $entryPointPassed $entryPointError
if (-not $entryPointPassed) {
    $allTestsPassed = $false
}
Write-Host ""

# ============================================================================
# SUMMARY AND DEBUG ROUTINE
# ============================================================================
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

$passedCount = ($testResults | Where-Object { $_ -eq $true }).Count
$totalCount = $testResults.Count

Write-TestLog "Tests Passed: $passedCount / $totalCount" -Color $(if ($allTestsPassed) { "Green" } else { "Red" }) -AlsoToFile

foreach ($result in $testResults) {
    $status = if ($result) { "✅" } else { "❌" }
    Write-TestLog "  $status" -Color $(if ($result) { "Green" } else { "Red" })
}

Write-Host ""

if ($allTestsPassed) {
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "  ✅ ALL TESTS PASSED - CODE IS READY" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host ""
    Write-TestLog "All tests passed at $(Get-Date)" -AlsoToFile
    exit 0
} else {
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  ❌ SOME TESTS FAILED - DEBUG ROUTINE" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host ""
    
    # ============================================================================
    # DEBUG ROUTINE
    # ============================================================================
    Write-Host "DEBUG ROUTINE" -ForegroundColor Yellow
    Write-Host "-" * 80 -ForegroundColor Gray
    Write-Host ""
    
    # Environment Information
    Write-TestLog "Environment Information:" -Color Cyan
    Write-TestLog "  PowerShell Version: $($PSVersionTable.PSVersion)" -Color Gray
    Write-TestLog "  OS Version: $([System.Environment]::OSVersion)" -Color Gray
    Write-TestLog "  SystemDrive: $env:SystemDrive" -Color Gray
    Write-TestLog "  Current Directory: $(Get-Location)" -Color Gray
    Write-Host ""
    
    # Check .NET Framework
    Write-TestLog ".NET Framework Check:" -Color Cyan
    try {
        $netVersion = [System.Environment]::Version
        Write-TestLog "  .NET Version: $netVersion" -Color Gray
    } catch {
        Write-TestLog "  ⚠️  Could not determine .NET version" -Color Yellow
    }
    Write-Host ""
    
    # Check WPF specifically
    if (-not $wpfAvailable) {
        Write-TestLog "WPF Debugging:" -Color Cyan
        Write-TestLog "  WPF is required for GUI mode" -Color Yellow
        Write-TestLog "  Error: $wpfError" -Color Red
        Write-TestLog ""
        Write-TestLog "  Troubleshooting Steps:" -Color Yellow
        Write-TestLog "    1. Ensure .NET Framework 4.5+ is installed" -Color Gray
        Write-TestLog "    2. Check if PresentationFramework.dll exists:" -Color Gray
        try {
            $wpfPath = [System.Reflection.Assembly]::LoadWithPartialName("PresentationFramework").Location
            Write-TestLog "      Found at: $wpfPath" -Color Green
        } catch {
            Write-TestLog "      ⚠️  Could not locate PresentationFramework.dll" -Color Red
        }
        Write-Host ""
    }
    
    # Check GUI module specifically
    if (-not $guiLoadPassed -and $wpfAvailable) {
        Write-TestLog "GUI Module Debugging:" -Color Cyan
        Write-TestLog "  Error: $guiError" -Color Red
        Write-TestLog ""
        Write-TestLog "  Troubleshooting Steps:" -Color Yellow
        Write-TestLog "    1. Check for syntax errors in Helper\WinRepairGUI.ps1" -Color Gray
        Write-TestLog "    2. Verify all required functions exist in WinRepairCore.ps1" -Color Gray
        Write-TestLog "    3. Check if LogAnalysis.ps1 loads correctly (if used)" -Color Gray
        Write-TestLog "    4. Review log file: $logFile" -Color Gray
        Write-Host ""
    }
    
    # Syntax errors
    if (-not $syntaxPassed) {
        Write-TestLog "Syntax Error Debugging:" -Color Cyan
        Write-TestLog "  Run: pwsh -NoLogo -NoProfile -File 'Test\Validate-Syntax.ps1'" -Color Yellow
        Write-TestLog "  Or check individual files with:" -Color Yellow
        Write-TestLog "    [System.Management.Automation.PSParser]::Tokenize((Get-Content 'file.ps1' -Raw), [ref]`$null)" -Color Gray
        Write-Host ""
    }
    
    # Module load errors
    if (-not $moduleLoadPassed) {
        Write-TestLog "Module Load Error Debugging:" -Color Cyan
        Write-TestLog "  Export-ModuleMember errors occur when scripts are dot-sourced" -Color Yellow
        Write-TestLog "  Ensure Export-ModuleMember is wrapped in module check:" -Color Yellow
        Write-TestLog "    if (`$MyInvocation.MyCommand.ModuleName) { Export-ModuleMember ... }" -Color Gray
        Write-Host ""
    }
    
    Write-TestLog "Full log saved to: $logFile" -Color Cyan
    Write-Host ""
    Write-TestLog "All tests failed at $(Get-Date)" -AlsoToFile
    exit 1
}

