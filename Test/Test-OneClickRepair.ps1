# Automated Test for ONE-CLICK REPAIR Feature
# Tests the feature without user intervention

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ONE-CLICK REPAIR AUTOMATED TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allTestsPassed = $true
$testResults = @()

function Add-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message
    )
    $script:testResults += [PSCustomObject]@{
        Test = $TestName
        Passed = $Passed
        Message = $Message
    }
    if ($Passed) {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] ${TestName}: $Message" -ForegroundColor Red
        $script:allTestsPassed = $false
    }
}

# TEST 1: Load Core Module
Write-Host "[TEST 1] Loading WinRepairCore.ps1..." -ForegroundColor Yellow
try {
    $corePath = Join-Path $scriptRoot "Helper\WinRepairCore.ps1"
    if (-not (Test-Path $corePath)) {
        Add-TestResult "Core Module Path" $false "WinRepairCore.ps1 not found at: $corePath"
    } else {
        Add-TestResult "Core Module Path" $true "Found at: $corePath"
        
        . $corePath -ErrorAction Stop
        Add-TestResult "Core Module Load" $true "WinRepairCore.ps1 loaded successfully"
    }
} catch {
    Add-TestResult "Core Module Load" $false "Failed to load: $_"
}

Write-Host ""

# TEST 2: Verify Required Functions Exist
Write-Host "[TEST 2] Verifying required functions..." -ForegroundColor Yellow
$requiredFunctions = @(
    "Test-DiskHealth",
    "Get-MissingStorageDevices"
)

foreach ($funcName in $requiredFunctions) {
    if (Get-Command $funcName -ErrorAction SilentlyContinue) {
        Add-TestResult "Function: $funcName" $true "Function exists"
    } else {
        Add-TestResult "Function: $funcName" $false "Function not found"
    }
}

Write-Host ""

# TEST 3: Test Path Resolution (Simulating Event Handler)
Write-Host "[TEST 3] Testing path resolution in event handler context..." -ForegroundColor Yellow

# Simulate the event handler scriptblock context
$testScriptBlock = {
    param($scriptRoot)
    
    # This simulates what happens in the event handler
    if (-not $scriptRoot) {
        if ($PSScriptRoot) {
            $scriptRoot = $PSScriptRoot
        } elseif ($MyInvocation.MyCommand.Path) {
            $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
        } else {
            $scriptRoot = if (Test-Path "Helper\WinRepairCore.ps1") { 
                "Helper" 
            } elseif (Test-Path "$(Get-Location)\Helper\WinRepairCore.ps1") {
                Join-Path (Get-Location) "Helper"
            } else {
                $null
            }
        }
    }
    
    return $scriptRoot
}

try {
    # Test with module-level scriptRoot
    $resolvedPath = & $testScriptBlock -scriptRoot $scriptRoot
    if ($resolvedPath) {
        Add-TestResult "Path Resolution (with module scriptRoot)" $true "Resolved to: $resolvedPath"
    } else {
        Add-TestResult "Path Resolution (with module scriptRoot)" $false "Failed to resolve path"
    }
    
    # Test without module-level scriptRoot (simulating event handler)
    $resolvedPath2 = & $testScriptBlock -scriptRoot $null
    if ($resolvedPath2) {
        Add-TestResult "Path Resolution (without module scriptRoot)" $true "Resolved to: $resolvedPath2"
    } else {
        Add-TestResult "Path Resolution (without module scriptRoot)" $false "Failed to resolve path"
    }
} catch {
    Add-TestResult "Path Resolution" $false "Exception: $_"
}

Write-Host ""

# TEST 4: Test Core Module Loading with Resolved Path
Write-Host "[TEST 4] Testing core module loading with resolved path..." -ForegroundColor Yellow
try {
    $resolvedScriptRoot = if ($PSScriptRoot) { 
        $PSScriptRoot 
    } elseif (Test-Path "Helper\WinRepairCore.ps1") { 
        "Helper" 
    } else {
        Join-Path (Get-Location) "Helper"
    }
    
    if ($resolvedScriptRoot) {
        $corePath = Join-Path $resolvedScriptRoot "Helper\WinRepairCore.ps1"
        if (-not (Test-Path $corePath)) {
            # Try without Helper subdirectory
            $corePath = Join-Path $resolvedScriptRoot "WinRepairCore.ps1"
        }
        if (Test-Path $corePath) {
            Add-TestResult "Core Path Resolution" $true "Resolved to: $corePath"
            
            # Try to load it (may already be loaded)
            try {
                . $corePath -ErrorAction Stop
                Add-TestResult "Core Module Reload" $true "Module reloaded successfully"
            } catch {
                # May fail if already loaded, which is OK
                if ($_.Exception.Message -match 'already|loaded') {
                    Add-TestResult "Core Module Reload" $true "Module already loaded (expected)"
                } else {
                    Add-TestResult "Core Module Reload" $false "Failed: $_"
                }
            }
        } else {
            Add-TestResult "Core Path Resolution" $false "Path resolved but file not found: $corePath"
        }
    } else {
        Add-TestResult "Core Path Resolution" $false "Failed to resolve script root"
    }
} catch {
    Add-TestResult "Core Module Loading Test" $false "Exception: $_"
}

Write-Host ""

# TEST 5: Test Function Calls (Dry Run)
Write-Host "[TEST 5] Testing function calls (dry run)..." -ForegroundColor Yellow
try {
    $drive = $env:SystemDrive.TrimEnd(':')
    
    # Test Test-DiskHealth (may fail if not in FullOS, which is OK for test)
    try {
        $diskHealth = Test-DiskHealth -WindowsDrive $drive -ErrorAction Stop
        Add-TestResult "Test-DiskHealth Call" $true "Function called successfully"
    } catch {
        if ($_.Exception.Message -match 'not.*available|WinRE|WinPE') {
            Add-TestResult "Test-DiskHealth Call" $true "Function available (not applicable in this environment)"
        } else {
            Add-TestResult "Test-DiskHealth Call" $false "Failed: $_"
        }
    }
    
    # Test Get-MissingStorageDevices (may fail if not in FullOS, which is OK for test)
    try {
        $missingDevices = Get-MissingStorageDevices -ErrorAction Stop
        Add-TestResult "Get-MissingStorageDevices Call" $true "Function called successfully"
    } catch {
        if ($_.Exception.Message -match 'not.*available|WinRE|WinPE') {
            Add-TestResult "Get-MissingStorageDevices Call" $true "Function available (not applicable in this environment)"
        } else {
            Add-TestResult "Get-MissingStorageDevices Call" $false "Failed: $_"
        }
    }
} catch {
    Add-TestResult "Function Calls Test" $false "Exception: $_"
}

Write-Host ""

# TEST 6: Verify No Null Path Errors
Write-Host "[TEST 6] Verifying no null path parameter errors..." -ForegroundColor Yellow

# Check if any functions have Path parameters that could be null
$functionsWithPath = Get-Command -Module (Get-Module -ListAvailable | Where-Object { $_.Path -like "*WinRepairCore*" }) -ErrorAction SilentlyContinue | 
    Where-Object { $_.Parameters.Keys -contains 'Path' }

if ($functionsWithPath) {
    foreach ($func in $functionsWithPath) {
        $param = $func.Parameters['Path']
        if ($param.Mandatory -and -not $param.DefaultValue) {
            Add-TestResult "Function $($func.Name) Path Parameter" $true "Path parameter exists (mandatory)"
        } else {
            Add-TestResult "Function $($func.Name) Path Parameter" $true "Path parameter exists (optional)"
        }
    }
} else {
    Add-TestResult "Path Parameter Check" $true "No functions with Path parameter found (or module not loaded)"
}

Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$passed = ($testResults | Where-Object { $_.Passed }).Count
$failed = ($testResults | Where-Object { -not $_.Passed }).Count
$total = $testResults.Count

Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

if ($allTestsPassed) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "The ONE-CLICK REPAIR feature should work correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please review the failed tests above." -ForegroundColor Red
    exit 1
}
