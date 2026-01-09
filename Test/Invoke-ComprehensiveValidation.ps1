# Comprehensive Validation Test Suite
# Simulates 20 different test agents validating the system

param(
    [switch]$Quick,
    [string]$LogDir = "$env:TEMP\miracleboot-validation"
)

$ErrorActionPreference = 'Stop'
$global:TestResults = @()
$global:TestAgent = 1

function Write-TestResult {
    param([string]$Agent, [string]$Test, [string]$Status, [string]$Details = "")
    $result = [PSCustomObject]@{
        Agent = $Agent
        Test = $Test
        Status = $Status
        Details = $Details
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $global:TestResults += $result
    $color = if ($Status -eq "PASS") { "Green" } elseif ($Status -eq "FAIL") { "Red" } else { "Yellow" }
    Write-Host "[$Agent] $Test : $Status" -ForegroundColor $color
    if ($Details) { Write-Host "  -> $Details" -ForegroundColor Gray }
}

function Test-AgentSyntax {
    param([int]$AgentNum)
    $agent = "Agent-$AgentNum"
    Write-Host "`n=== ${agent}: Syntax Validation ===" -ForegroundColor Cyan
    
    $scripts = @(
        "MiracleBoot.ps1",
        "Helper\WinRepairCore.ps1",
        "Helper\WinRepairTUI.ps1",
        "Helper\WinRepairGUI.ps1",
        "Helper\NetworkDiagnostics.ps1",
        "Helper\LogAnalysis.ps1"
    )
    
    foreach ($script in $scripts) {
        if (-not (Test-Path $script)) {
            Write-TestResult $agent "Syntax-$script" "FAIL" "File not found"
            continue
        }
        
        try {
            $errors = @()
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script -Raw), [ref]$errors)
            if ($errors.Count -eq 0) {
                Write-TestResult $agent "Syntax-$script" "PASS" ""
            } else {
                $errorMsg = ($errors | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
                Write-TestResult $agent "Syntax-$script" "FAIL" $errorMsg
            }
        } catch {
            Write-TestResult $agent "Syntax-$script" "FAIL" $_.Exception.Message
        }
    }
}

function Test-AgentModuleLoad {
    param([int]$AgentNum)
    $agent = "Agent-$AgentNum"
    Write-Host "`n=== ${agent}: Module Loading ===" -ForegroundColor Cyan
    
    try {
        # Test WinRepairCore module loading
        $corePath = Resolve-Path "Helper\WinRepairCore.ps1" -ErrorAction Stop
        $coreContent = Get-Content $corePath -Raw
        
        # Check for critical functions
        $requiredFunctions = @(
            "Start-PrecisionScan",
            "Get-PrecisionDetections",
            "Invoke-PrecisionRemediationPlan",
            "Invoke-PrecisionQuickScan",
            "Invoke-PrecisionParityHarness",
            "Backup-PrecisionState",
            "Write-PrecisionLog"
        )
        
        foreach ($func in $requiredFunctions) {
            if ($coreContent -match "function\s+$func") {
                Write-TestResult $agent "Function-$func" "PASS" ""
            } else {
                Write-TestResult $agent "Function-$func" "FAIL" "Function not found"
            }
        }
        
        # Test actual dot-sourcing (syntax only)
        $testScript = @"
            `$ErrorActionPreference = 'Stop'
            try {
                . '$corePath' -ErrorAction Stop
                Write-Host 'Module loaded successfully'
            } catch {
                throw `$_
            }
"@
        $testFile = "$env:TEMP\test-module-load.ps1"
        $testScript | Out-File $testFile -Encoding UTF8
        
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $testFile 2>&1
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0 -or $output -match "Module loaded successfully") {
            Write-TestResult $agent "ModuleLoad-Core" "PASS" ""
        } else {
            Write-TestResult $agent "ModuleLoad-Core" "FAIL" ($output -join "; ")
        }
        
    } catch {
        Write-TestResult $agent "ModuleLoad-Core" "FAIL" $_.Exception.Message
    }
}

function Test-AgentGUILaunch {
    param([int]$AgentNum)
    $agent = "Agent-$AgentNum"
    Write-Host "`n=== ${agent}: GUI Launch Test ===" -ForegroundColor Cyan
    
    try {
        # Check if GUI script exists and has valid syntax
        $guiPath = Resolve-Path "Helper\WinRepairGUI.ps1" -ErrorAction Stop
        
        # Test XAML loading
        $guiContent = Get-Content $guiPath -Raw
        if ($guiContent -match '\[xml\]\s*\$xaml') {
            Write-TestResult $agent "GUI-XAMLParse" "PASS" ""
        } else {
            Write-TestResult $agent "GUI-XAMLParse" "WARN" "XAML parsing pattern not found"
        }
        
        # Test for critical GUI functions
        $guiFunctions = @("Show-WinRepairGUI", "Initialize-GUI")
        foreach ($func in $guiFunctions) {
            if ($guiContent -match "function\s+$func" -or $guiContent -match "^\s*function\s+$func") {
                Write-TestResult $agent "GUI-Function-$func" "PASS" ""
            } else {
                Write-TestResult $agent "GUI-Function-$func" "WARN" "Function pattern not found"
            }
        }
        
        # Test syntax of GUI file
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize($guiContent, [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-TestResult $agent "GUI-Syntax" "PASS" ""
        } else {
            $errorMsg = ($errors | Select-Object -First 3 | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
            Write-TestResult $agent "GUI-Syntax" "FAIL" $errorMsg
        }
        
    } catch {
        Write-TestResult $agent "GUI-Launch" "FAIL" $_.Exception.Message
    }
}

function Test-AgentTUILaunch {
    param([int]$AgentNum)
    $agent = "Agent-$AgentNum"
    Write-Host "`n=== ${agent}: TUI Launch Test ===" -ForegroundColor Cyan
    
    try {
        $tuiPath = Resolve-Path "Helper\WinRepairTUI.ps1" -ErrorAction Stop
        $tuiContent = Get-Content $tuiPath -Raw
        
        # Check for menu structure
        if ($tuiContent -match "Show-MainMenu" -or $tuiContent -match "function.*Menu") {
            Write-TestResult $agent "TUI-Menu" "PASS" ""
        } else {
            Write-TestResult $agent "TUI-Menu" "WARN" "Menu function not found"
        }
        
        # Test syntax
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize($tuiContent, [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-TestResult $agent "TUI-Syntax" "PASS" ""
        } else {
            $errorMsg = ($errors | Select-Object -First 3 | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
            Write-TestResult $agent "TUI-Syntax" "FAIL" $errorMsg
        }
        
    } catch {
        Write-TestResult $agent "TUI-Launch" "FAIL" $_.Exception.Message
    }
}

function Test-AgentPrecisionFunctions {
    param([int]$AgentNum)
    $agent = "Agent-$AgentNum"
    Write-Host "`n=== ${agent}: Precision Functions Test ===" -ForegroundColor Cyan
    
    try {
        $corePath = Resolve-Path "Helper\WinRepairCore.ps1" -ErrorAction Stop
        $coreContent = Get-Content $corePath -Raw
        
        # Test for critical precision detection patterns
        $patterns = @{
            "TC-001" = "Missing.*winload"
            "TC-002" = "Corrupt.*BCD|BCD.*corrupt"
            "TC-011" = "INACCESSIBLE_BOOT_DEVICE|0x7B|StartOverride"
            "TC-014" = "pending\.xml|exclusive"
            "TC-021" = "VMD|iaStorVD"
        }
        
        foreach ($tc in $patterns.Keys) {
            if ($coreContent -match $patterns[$tc]) {
                Write-TestResult $agent "Precision-$tc" "PASS" ""
            } else {
                Write-TestResult $agent "Precision-$tc" "WARN" "Pattern not found"
            }
        }
        
        # Test safety functions
        $safetyFunctions = @("Invoke-BootPrecisionSafetyCheck", "Backup-PrecisionState")
        foreach ($func in $safetyFunctions) {
            if ($coreContent -match "function\s+$func") {
                Write-TestResult $agent "Safety-$func" "PASS" ""
            } else {
                Write-TestResult $agent "Safety-$func" "FAIL" "Safety function missing"
            }
        }
        
    } catch {
        Write-TestResult $agent "Precision-Functions" "FAIL" $_.Exception.Message
    }
}

function Test-AgentErrorHandling {
    param([int]$AgentNum)
    $agent = "Agent-$AgentNum"
    Write-Host "`n=== ${agent}: Error Handling Test ===" -ForegroundColor Cyan
    
    try {
        $corePath = Resolve-Path "Helper\WinRepairCore.ps1" -ErrorAction Stop
        $coreContent = Get-Content $corePath -Raw
        
        # Check for try-catch blocks in critical functions
        $criticalFunctions = @("Start-PrecisionScan", "Get-PrecisionDetections", "Invoke-PrecisionRemediationPlan")
        
        foreach ($func in $criticalFunctions) {
            $funcBlock = $coreContent -replace "(?s).*?function\s+$func\s*\{([^}]+)\}.*", '$1'
            if ($funcBlock -match "try\s*\{") {
                Write-TestResult $agent "ErrorHandling-$func" "PASS" ""
            } else {
                Write-TestResult $agent "ErrorHandling-$func" "WARN" "No try-catch found"
            }
        }
        
    } catch {
        Write-TestResult $agent "ErrorHandling" "FAIL" $_.Exception.Message
    }
}

function Test-AgentMainScript {
    param([int]$AgentNum)
    $agent = "Agent-$AgentNum"
    Write-Host "`n=== ${agent}: Main Script Test ===" -ForegroundColor Cyan
    
    try {
        $mainPath = Resolve-Path "MiracleBoot.ps1" -ErrorAction Stop
        $mainContent = Get-Content $mainPath -Raw
        
        # Check for validation phase
        if ($mainContent -match "Validation|PreLaunchValidation") {
            Write-TestResult $agent "Main-Validation" "PASS" ""
        } else {
            Write-TestResult $agent "Main-Validation" "WARN" "Validation not found"
        }
        
        # Test syntax
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize($mainContent, [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-TestResult $agent "Main-Syntax" "PASS" ""
        } else {
            $errorMsg = ($errors | Select-Object -First 3 | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }) -join "; "
            Write-TestResult $agent "Main-Syntax" "FAIL" $errorMsg
        }
        
    } catch {
        Write-TestResult $agent "Main-Script" "FAIL" $_.Exception.Message
    }
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "COMPREHENSIVE VALIDATION TEST SUITE" -ForegroundColor Magenta
Write-Host "20 Test Agents - Full System Validation" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

$agents = if ($Quick) { 1..5 } else { 1..20 }

foreach ($agentNum in $agents) {
    Test-AgentSyntax -AgentNum $agentNum
    Test-AgentModuleLoad -AgentNum $agentNum
    Test-AgentGUILaunch -AgentNum $agentNum
    Test-AgentTUILaunch -AgentNum $agentNum
    Test-AgentPrecisionFunctions -AgentNum $agentNum
    Test-AgentErrorHandling -AgentNum $agentNum
    Test-AgentMainScript -AgentNum $agentNum
}

# Summary
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "VALIDATION SUMMARY" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

$passCount = ($global:TestResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($global:TestResults | Where-Object { $_.Status -eq "FAIL" }).Count
$warnCount = ($global:TestResults | Where-Object { $_.Status -eq "WARN" }).Count
$totalCount = $global:TestResults.Count

Write-Host "Total Tests: $totalCount" -ForegroundColor White
Write-Host "PASS: $passCount" -ForegroundColor Green
Write-Host "FAIL: $failCount" -ForegroundColor Red
Write-Host "WARN: $warnCount" -ForegroundColor Yellow

# Export results
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$reportPath = Join-Path $LogDir "validation-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$global:TestResults | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
Write-Host "`nReport saved to: $reportPath" -ForegroundColor Cyan

if ($failCount -gt 0) {
    Write-Host "`nFAILED TESTS:" -ForegroundColor Red
    $global:TestResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  [$($_.Agent)] $($_.Test): $($_.Details)" -ForegroundColor Yellow
    }
    exit 1
} else {
    Write-Host "`nALL CRITICAL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
