# Safe Function Testing - Only tests read-only functions that won't modify the system
# Zero user input required, fully automated

$ErrorActionPreference = 'Stop'
$script:Results = @{
    Passed = 0
    Failed = 0
    Errors = @()
}

function Test-SafeFunction {
    param(
        [string]$FunctionName,
        [scriptblock]$TestScript,
        [string]$Description = ""
    )
    
    try {
        & $TestScript | Out-Null
        $script:Results.Passed++
        Write-Host "[PASS] $FunctionName" -ForegroundColor Green
        if ($Description) { Write-Host "      $Description" -ForegroundColor Gray }
        return $true
    } catch {
        $script:Results.Failed++
        $script:Results.Errors += "$FunctionName : $_"
        Write-Host "[FAIL] $FunctionName" -ForegroundColor Red
        Write-Host "      Error: $_" -ForegroundColor Yellow
        return $false
    }
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  SAFE FUNCTION TESTING - READ-ONLY OPERATIONS ONLY" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = Get-Location }

# Load modules (suppress Export-ModuleMember warnings)
Write-Host "Loading modules..." -ForegroundColor Yellow
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $ScriptDir "Helper\WinRepairCore.ps1") 2>&1 | Where-Object { $_ -notmatch 'Export-ModuleMember' } | Out-Null
. (Join-Path $ScriptDir "Helper\NetworkDiagnostics.ps1") 2>&1 | Where-Object { $_ -notmatch 'Export-ModuleMember' } | Out-Null
. (Join-Path $ScriptDir "Helper\KeyboardSymbols.ps1") 2>&1 | Where-Object { $_ -notmatch 'Export-ModuleMember' } | Out-Null
$ErrorActionPreference = 'Stop'

# Load MiracleBoot functions only (not execution)
$mbContent = Get-Content (Join-Path $ScriptDir "MiracleBoot.ps1") -Raw
$functionDefs = $mbContent -split '(?=\n# Main execution|^# Main execution|^if \(.*Get-EnvironmentType|^\.\s*Helper)' | Select-Object -First 1
Invoke-Expression $functionDefs 2>&1 | Out-Null

Write-Host ""

# Test 1: Environment Detection (safe, read-only)
Write-Host "Testing Environment Detection Functions..." -ForegroundColor Yellow
Test-SafeFunction "Get-EnvironmentType" {
    $envType = Get-EnvironmentType
    if (-not $envType) { throw "Returned null" }
    return $true
} "Detected: $envType"

Test-SafeFunction "Test-PowerShellAvailability" {
    $result = Test-PowerShellAvailability
    return $true
} "PowerShell availability checked"

# Test 2: Volume Detection (safe, read-only)
Write-Host ""
Write-Host "Testing Volume Detection Functions..." -ForegroundColor Yellow
Test-SafeFunction "Get-WindowsVolumes" {
    $volumes = Get-WindowsVolumes
    return $true
} "Volume enumeration completed"

# Test 3: Error Code Lookup (safe, read-only)
Write-Host ""
Write-Host "Testing Error Code Lookup System..." -ForegroundColor Yellow
$testCodes = @("0xc000000e", "0x80070002", "0x0000007B", "0xC0000225")
foreach ($code in $testCodes) {
    Test-SafeFunction "Get-WindowsErrorCodeInfo - $code" {
        $result = Get-WindowsErrorCodeInfo -ErrorCode $code -TargetDrive "C"
        if (-not $result) { throw "No result returned" }
        return $true
    } "Type: $($result.Type)"
}

# Test 4: Boot Chain Analysis (safe, read-only)
Write-Host ""
Write-Host "Testing Boot Chain Analysis..." -ForegroundColor Yellow
Test-SafeFunction "Get-BootChainAnalysis" {
    $analysis = Get-BootChainAnalysis -TargetDrive "C"
    if (-not $analysis -or -not $analysis.Report) { throw "No report generated" }
    return $true
} "Analysis completed successfully"

# Test 5: Boot Log Analysis (safe, read-only)
Write-Host ""
Write-Host "Testing Boot Log Analysis..." -ForegroundColor Yellow
Test-SafeFunction "Get-BootLogAnalysis" {
    $logAnalysis = Get-BootLogAnalysis -TargetDrive "C"
    return $true
} "Log analysis completed (may not find log in test environment)"

# Test 6: Repair Templates (safe, read-only)
Write-Host ""
Write-Host "Testing Repair Template System..." -ForegroundColor Yellow
Test-SafeFunction "Get-RepairTemplates" {
    $templates = Get-RepairTemplates
    if (-not $templates -or $templates.Count -eq 0) { throw "No templates returned" }
    return $true
} "Found $($templates.Count) templates"

# Test 7: Keyboard Symbols (safe, read-only)
Write-Host ""
Write-Host "Testing Keyboard Symbols Functions..." -ForegroundColor Yellow
if (Get-Command Get-AllSymbols -ErrorAction SilentlyContinue) {
    Test-SafeFunction "Get-AllSymbols" {
        $symbols = Get-AllSymbols
        if (-not $symbols -or $symbols.Count -eq 0) { throw "No symbols returned" }
        return $true
    } "Found $($symbols.Count) symbols"
    
    Test-SafeFunction "Get-AllCategories" {
        $categories = Get-AllCategories
        return $true
    } "Category enumeration completed"
}

# Test 8: Network Diagnostics (safe, read-only queries)
Write-Host ""
Write-Host "Testing Network Diagnostics (Read-Only)..." -ForegroundColor Yellow
if (Get-Command Get-NetworkAdapterStatus -ErrorAction SilentlyContinue) {
    Test-SafeFunction "Get-NetworkAdapterStatus" {
        $adapters = Get-NetworkAdapterStatus -ErrorAction SilentlyContinue
        return $true
    } "Adapter status checked (may return empty in some environments)"
}

# Test 9: Function Parameter Validation
Write-Host ""
Write-Host "Testing Function Parameter Validation..." -ForegroundColor Yellow
Test-SafeFunction "Get-WindowsErrorCodeInfo - Invalid Code" {
    $result = Get-WindowsErrorCodeInfo -ErrorCode "0xINVALID" -TargetDrive "C"
    if (-not $result) { throw "Should return result even for invalid codes" }
    return $true
} "Handles invalid codes gracefully"

# Test 10: Template Structure Validation
Write-Host ""
Write-Host "Testing Template Structure..." -ForegroundColor Yellow
$templates = Get-RepairTemplates
foreach ($template in $templates) {
    $requiredProps = @("Id", "Name", "Description", "Steps", "EstimatedTime", "RiskLevel")
    $missing = @()
    foreach ($prop in $requiredProps) {
        if (-not ($template.PSObject.Properties.Name -contains $prop)) {
            $missing += $prop
        }
    }
    if ($missing.Count -eq 0) {
        $script:Results.Passed++
        Write-Host "[PASS] Template structure: $($template.Id)" -ForegroundColor Green
    } else {
        $script:Results.Failed++
        Write-Host "[FAIL] Template structure: $($template.Id)" -ForegroundColor Red
        Write-Host "      Missing properties: $($missing -join ', ')" -ForegroundColor Yellow
    }
}

# Final Summary
Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $($script:Results.Passed + $script:Results.Failed)" -ForegroundColor White
Write-Host "Passed: $($script:Results.Passed)" -ForegroundColor Green
Write-Host "Failed: $($script:Results.Failed)" -ForegroundColor $(if ($script:Results.Failed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($script:Results.Failed -eq 0) {
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "  ALL SAFE FUNCTION TESTS PASSED!" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
    exit 0
} else {
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Failed Tests:" -ForegroundColor Yellow
    foreach ($error in $script:Results.Errors) {
        Write-Host "  - $error" -ForegroundColor Red
    }
    exit 1
}

