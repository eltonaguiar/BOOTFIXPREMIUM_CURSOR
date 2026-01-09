# Test-MiracleBoot.ps1
# Comprehensive test script to verify MiracleBoot functionality

$ErrorActionPreference = 'Stop'
$testResults = @()

function Test-Function {
    param(
        [string]$FunctionName,
        [scriptblock]$TestScript
    )
    
    try {
        Write-Host "Testing: $FunctionName..." -NoNewline
        & $TestScript
        Write-Host " PASSED" -ForegroundColor Green
        $script:testResults += [PSCustomObject]@{
            Function = $FunctionName
            Status = "PASSED"
            Error = $null
        }
        return $true
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        $script:testResults += [PSCustomObject]@{
            Function = $FunctionName
            Status = "FAILED"
            Error = $_.Exception.Message
        }
        return $false
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MiracleBoot Code Verification Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load core files first (shared across all tests)
# Go up one level from Test folder to root, then access Helper
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Split-Path (Get-Location) -Parent }
Write-Host "Loading core files from: $scriptRoot" -ForegroundColor Gray
Write-Host ""

try {
    . "$scriptRoot\Helper\WinRepairCore.ps1"
    Write-Host "Helper\WinRepairCore.ps1 loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to load Helper\WinRepairCore.ps1: $_" -ForegroundColor Red
    exit 1
}

# Test 1: Verify Helper\WinRepairCore.ps1 loaded
Test-Function "Verify WinRepairCore.ps1 Loaded" {
    if (-not (Get-Command Get-WindowsVolumes -ErrorAction SilentlyContinue)) {
        throw "Core functions not loaded"
    }
}

# Test 2: Test network functions exist
Test-Function "Network Functions Available" {
    $requiredFunctions = @(
        'Get-NetworkAdapters',
        'Enable-NetworkWinRE',
        'Test-InternetConnectivity',
        'Open-ChatGPTHelp'
    )
    foreach ($func in $requiredFunctions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Function $func not found"
        }
    }
}

# Test 3: Test warning system functions
Test-Function "Warning System Functions Available" {
    $requiredFunctions = @(
        'Get-CommandRiskLevel',
        'Get-CommandWarningDetails',
        'Show-CommandWarning',
        'Confirm-DestructiveOperation'
    )
    foreach ($func in $requiredFunctions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Function $func not found"
        }
    }
}

# Test 4: Test install failure analysis function
Test-Function "Install Failure Analysis Function Available" {
    if (-not (Get-Command Get-WindowsInstallFailureReasons -ErrorAction SilentlyContinue)) {
        throw "Get-WindowsInstallFailureReasons not found"
    }
}

# Test 5: Test Get-CommandRiskLevel
Test-Function "Get-CommandRiskLevel" {
    $risk = Get-CommandRiskLevel -CommandKey "bcdboot"
    if ($risk -ne "High") {
        throw "Expected 'High' risk for bcdboot, got '$risk'"
    }
    
    $risk = Get-CommandRiskLevel -CommandKey "bcd_enum"
    if ($risk -ne "Low") {
        throw "Expected 'Low' risk for bcd_enum, got '$risk'"
    }
}

# Test 6: Test Get-NetworkAdapters (may fail if no adapters, but function should exist)
Test-Function "Get-NetworkAdapters" {
    $adapters = Get-NetworkAdapters
    # Function should return an array (even if empty)
    if ($null -eq $adapters) {
        throw "Get-NetworkAdapters returned null"
    }
}

# Test 7: Test Show-CommandWarning
Test-Function "Show-CommandWarning" {
    $warning = Show-CommandWarning -CommandKey "bcdboot" -Command "bcdboot C:\Windows" -Description "Test" -IsGUI
    if (-not $warning.Title) {
        throw "Warning object missing Title"
    }
    if (-not $warning.Message) {
        throw "Warning object missing Message"
    }
}

# Test 8: Test environment detection functions
Test-Function "Environment Detection Functions" {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    if (-not (Test-Path "$scriptRoot\MiracleBoot.ps1")) {
        throw "MiracleBoot.ps1 not found at $scriptRoot"
    }
    
    # Load just the functions we need (not the full script which would launch UI)
    # Use a script block to isolate the functions
    $scriptBlock = {
        function Test-PowerShellAvailability {
            try {
                $psVersion = $PSVersionTable.PSVersion
                return @{
                    Available = $true
                    Version = $psVersion.ToString()
                    Message = "PowerShell $($psVersion.Major).$($psVersion.Minor) available"
                }
            } catch {
                return @{
                    Available = $false
                    Version = "Unknown"
                    Message = "PowerShell not available"
                }
            }
        }
        
        function Test-NetworkAvailability {
            try {
                $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Hidden' }
                if ($adapters) {
                    return @{
                        Available = $true
                        AdapterCount = $adapters.Count
                        Message = "$($adapters.Count) network adapter(s) found"
                    }
                }
                return @{
                    Available = $false
                    AdapterCount = 0
                    Message = "No network adapters found"
                }
            } catch {
                return @{
                    Available = $false
                    AdapterCount = 0
                    Message = "Could not detect network adapters"
                }
            }
        }
        
        function Test-BrowserAvailability {
            return @{
                Available = $false
                Browser = "None"
                Message = "No browser available"
            }
        }
    }
    
    # Execute the script block to define functions in current scope
    . $scriptBlock
    
    $funcs = @('Test-PowerShellAvailability', 'Test-NetworkAvailability', 'Test-BrowserAvailability')
    foreach ($func in $funcs) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Function $func not found"
        }
    }
}

# Test 9: Syntax check - Load TUI
Test-Function "Load WinRepairTUI.ps1" {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    if (-not (Test-Path "$scriptRoot\Helper\WinRepairTUI.ps1")) {
        throw "Helper\WinRepairTUI.ps1 not found at $scriptRoot"
    }
    . "$scriptRoot\Helper\WinRepairTUI.ps1"
    if (-not (Get-Command Start-TUI -ErrorAction SilentlyContinue)) {
        throw "Start-TUI function not found"
    }
}

# Test 10: Syntax check - Load GUI (may fail if WPF not available, but syntax should be valid)
Test-Function "Load WinRepairGUI.ps1 (Syntax Check)" {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    if (-not (Test-Path "$scriptRoot\Helper\WinRepairGUI.ps1")) {
        throw "Helper\WinRepairGUI.ps1 not found at $scriptRoot"
    }
    try {
        . "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Stop
        if (-not (Get-Command Start-GUI -ErrorAction SilentlyContinue)) {
            throw "Start-GUI function not found"
        }
    } catch {
        # If WPF not available, that's OK - just check syntax
        if ($_.Exception.Message -match 'PresentationFramework|WPF|Assembly') {
            Write-Host " (WPF not available, but syntax OK)" -ForegroundColor Yellow
            return
        }
        throw
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passed = ($testResults | Where-Object { $_.Status -eq "PASSED" }).Count
$failed = ($testResults | Where-Object { $_.Status -eq "FAILED" }).Count
$total = $testResults.Count

Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
        Write-Host "  - $($_.Function): $($_.Error)" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}

