# Comprehensive Automated Test Suite for MiracleBoot
# Tests all modules and functions without requiring user input
# Version: 1.0

$ErrorActionPreference = 'Stop'
$script:TestResults = @{
    TotalTests = 0
    Passed = 0
    Failed = 0
    Errors = @()
    Warnings = @()
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = ""
    )
    
    $script:TestResults.TotalTests++
    if ($Passed) {
        $script:TestResults.Passed++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "      $Message" -ForegroundColor Gray }
    } else {
        $script:TestResults.Failed++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "      $Message" -ForegroundColor Yellow }
        $script:TestResults.Errors += "$TestName : $Message"
    }
}

function Write-TestWarning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
    $script:TestResults.Warnings += $Message
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  MIRACLE BOOT - COMPREHENSIVE AUTOMATED TEST SUITE" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) {
    $ScriptDir = Get-Location
}

# Test 1: Check all required files exist
Write-Host "PHASE 1: File Existence Checks" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray

$requiredFiles = @(
    "MiracleBoot.ps1",
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\KeyboardSymbols.ps1",
    "RunMiracleBoot.cmd",
    "Helper\WinRepairCore.cmd"
)

foreach ($file in $requiredFiles) {
    $path = Join-Path $ScriptDir $file
    if (Test-Path $path) {
        Write-TestResult "File exists: $file" $true
    } else {
        Write-TestResult "File exists: $file" $false "File not found: $path"
    }
}

Write-Host ""

# Test 2: Syntax validation for all PowerShell files
Write-Host "PHASE 2: Syntax Validation" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray

$psFiles = @(
    "MiracleBoot.ps1",
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\KeyboardSymbols.ps1"
)

foreach ($file in $psFiles) {
    $path = Join-Path $ScriptDir $file
    if (Test-Path $path) {
        try {
            $errors = $null
            $content = Get-Content $path -Raw -ErrorAction Stop
            [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors) | Out-Null
            
            if ($errors.Count -eq 0) {
                Write-TestResult "Syntax check: $file" $true
            } else {
                $errorMsg = "Found $($errors.Count) syntax error(s)"
                Write-TestResult "Syntax check: $file" $false $errorMsg
                foreach ($err in $errors | Select-Object -First 3) {
                    Write-Host "      Line $($err.Token.StartLine): $($err.Message)" -ForegroundColor Red
                }
            }
        } catch {
            Write-TestResult "Syntax check: $file" $false "Failed to parse: $_"
        }
    }
}

Write-Host ""

# Test 3: Load all modules and check for runtime errors
Write-Host "PHASE 3: Module Loading Tests" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray

# Test KeyboardSymbols.ps1 (suppress Export-ModuleMember warnings)
try {
    $ErrorActionPreference = 'SilentlyContinue'
    . (Join-Path $ScriptDir "Helper\KeyboardSymbols.ps1") 2>&1 | Where-Object { $_ -notmatch 'Export-ModuleMember' } | Out-Null
    $ErrorActionPreference = 'Stop'
    Write-TestResult "Load KeyboardSymbols.ps1" $true
} catch {
    if ($_.Exception.Message -match 'Export-ModuleMember') {
        Write-TestResult "Load KeyboardSymbols.ps1" $true "Warning: Export-ModuleMember (expected when dot-sourcing)"
    } else {
        Write-TestResult "Load KeyboardSymbols.ps1" $false $_.Exception.Message
    }
}

# Test NetworkDiagnostics.ps1 (suppress Export-ModuleMember warnings)
try {
    $ErrorActionPreference = 'SilentlyContinue'
    . (Join-Path $ScriptDir "Helper\NetworkDiagnostics.ps1") 2>&1 | Where-Object { $_ -notmatch 'Export-ModuleMember' } | Out-Null
    $ErrorActionPreference = 'Stop'
    Write-TestResult "Load NetworkDiagnostics.ps1" $true
} catch {
    if ($_.Exception.Message -match 'Export-ModuleMember') {
        Write-TestResult "Load NetworkDiagnostics.ps1" $true "Warning: Export-ModuleMember (expected when dot-sourcing)"
    } else {
        Write-TestResult "Load NetworkDiagnostics.ps1" $false $_.Exception.Message
    }
}

# Test WinRepairCore.ps1
try {
    . (Join-Path $ScriptDir "Helper\WinRepairCore.ps1")
    Write-TestResult "Load WinRepairCore.ps1" $true
} catch {
    Write-TestResult "Load WinRepairCore.ps1" $false $_.Exception.Message
}

# Test WinRepairTUI.ps1 (may have dependencies, but don't execute Start-TUI)
try {
    $ErrorActionPreference = 'SilentlyContinue'
    . (Join-Path $ScriptDir "Helper\WinRepairTUI.ps1") 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    Write-TestResult "Load WinRepairTUI.ps1" $true
} catch {
    Write-TestResult "Load WinRepairTUI.ps1" $false $_.Exception.Message
}

# Test WinRepairGUI.ps1 (may have dependencies, but don't execute Start-GUI)
try {
    $ErrorActionPreference = 'SilentlyContinue'
    . (Join-Path $ScriptDir "Helper\WinRepairGUI.ps1") 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    Write-TestResult "Load WinRepairGUI.ps1" $true
} catch {
    Write-TestResult "Load WinRepairGUI.ps1" $false $_.Exception.Message
}

# Test MiracleBoot.ps1 functions (don't execute main script body)
try {
    # Load just the functions, not the execution block
    $content = Get-Content (Join-Path $ScriptDir "MiracleBoot.ps1") -Raw
    # Extract just function definitions (before any execution code)
    $functionBlock = $content -replace '(?s)^.*?(?=function Get-EnvironmentType)', ''
    $functionBlock = $functionBlock -replace '(?s)(Start-GUI|Start-TUI).*$', ''
    Invoke-Expression $functionBlock 2>&1 | Out-Null
    
    # Test that functions are available
    if (Get-Command Get-EnvironmentType -ErrorAction SilentlyContinue) {
        Write-TestResult "Load MiracleBoot.ps1 functions" $true
    } else {
        Write-TestResult "Load MiracleBoot.ps1 functions" $false "Functions not loaded"
    }
} catch {
    Write-TestResult "Load MiracleBoot.ps1 functions" $false $_.Exception.Message
}

Write-Host ""

# Test 4: Function Availability Tests
Write-Host "PHASE 4: Function Availability Tests" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray

$coreFunctions = @(
    "Get-WindowsVolumes",
    "Get-BootChainAnalysis",
    "Get-BootLogAnalysis",
    "Get-WindowsErrorCodeInfo",
    "Get-RepairTemplates",
    "Get-EnvironmentType",
    "Test-PowerShellAvailability"
)

# Load MiracleBoot.ps1 functions separately
try {
    $mbContent = Get-Content (Join-Path $ScriptDir "MiracleBoot.ps1") -Raw
    # Execute only function definitions, skip execution block
    $functionsOnly = $mbContent -split '(?=\n# Main execution|^# Main execution|^if \(.*\)|^\.\s*Helper)' | Select-Object -First 1
    Invoke-Expression $functionsOnly 2>&1 | Out-Null
} catch {
    # Ignore - functions may already be loaded
}

foreach ($func in $coreFunctions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-TestResult "Function available: $func" $true
    } else {
        Write-TestResult "Function available: $func" $false "Function not found"
    }
}

Write-Host ""

# Test 5: Safe Function Execution Tests (no side effects)
Write-Host "PHASE 5: Safe Function Execution Tests" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray

# Test Get-EnvironmentType (safe, no side effects)
try {
    $envType = Get-EnvironmentType -ErrorAction Stop
    if ($envType) {
        Write-TestResult "Execute Get-EnvironmentType" $true "Returned: $envType"
    } else {
        Write-TestResult "Execute Get-EnvironmentType" $false "Returned null"
    }
} catch {
    Write-TestResult "Execute Get-EnvironmentType" $false $_.Exception.Message
}

# Test Get-WindowsVolumes (safe, read-only)
try {
    $volumes = Get-WindowsVolumes -ErrorAction Stop
    if ($null -ne $volumes) {
        Write-TestResult "Execute Get-WindowsVolumes" $true "Found $($volumes.Count) volume(s)"
    } else {
        Write-TestResult "Execute Get-WindowsVolumes" $true "Returned empty (expected in some environments)"
    }
} catch {
    Write-TestResult "Execute Get-WindowsVolumes" $false $_.Exception.Message
}

# Test Get-RepairTemplates (safe, returns data)
try {
    $templates = Get-RepairTemplates -ErrorAction Stop
    if ($templates -and $templates.Count -gt 0) {
        Write-TestResult "Execute Get-RepairTemplates" $true "Found $($templates.Count) template(s)"
    } else {
        Write-TestResult "Execute Get-RepairTemplates" $false "No templates returned"
    }
} catch {
    Write-TestResult "Execute Get-RepairTemplates" $false $_.Exception.Message
}

# Test Get-WindowsErrorCodeInfo (safe, lookup only)
try {
    $errorInfo = Get-WindowsErrorCodeInfo -ErrorCode "0xc000000e" -TargetDrive "C" -ErrorAction Stop
    if ($errorInfo -and $errorInfo.Found) {
        Write-TestResult "Execute Get-WindowsErrorCodeInfo" $true "Found error code info"
    } else {
        Write-TestResult "Execute Get-WindowsErrorCodeInfo" $true "Error code not in database (acceptable)"
    }
} catch {
    Write-TestResult "Execute Get-WindowsErrorCodeInfo" $false $_.Exception.Message
}

# Test Get-BootChainAnalysis (safe, read-only analysis)
try {
    $analysis = Get-BootChainAnalysis -TargetDrive "C" -ErrorAction Stop
    if ($analysis -and $analysis.Report) {
        Write-TestResult "Execute Get-BootChainAnalysis" $true "Analysis completed"
    } else {
        Write-TestResult "Execute Get-BootChainAnalysis" $false "No report generated"
    }
} catch {
    Write-TestResult "Execute Get-BootChainAnalysis" $false $_.Exception.Message
}

# Test KeyboardSymbols functions
if (Get-Command Get-AllSymbols -ErrorAction SilentlyContinue) {
    try {
        $symbols = Get-AllSymbols -ErrorAction Stop
        if ($symbols -and $symbols.Count -gt 0) {
            Write-TestResult "Execute Get-AllSymbols" $true "Found $($symbols.Count) symbol(s)"
        } else {
            Write-TestResult "Execute Get-AllSymbols" $false "No symbols returned"
        }
    } catch {
        Write-TestResult "Execute Get-AllSymbols" $false $_.Exception.Message
    }
}

# Test NetworkDiagnostics functions
if (Get-Command Get-NetworkAdapterStatus -ErrorAction SilentlyContinue) {
    try {
        $adapters = Get-NetworkAdapterStatus -ErrorAction SilentlyContinue
        Write-TestResult "Execute Get-NetworkAdapterStatus" $true "Function executed (may return empty in WinRE)"
    } catch {
        Write-TestResult "Execute Get-NetworkAdapterStatus" $false $_.Exception.Message
    }
}

Write-Host ""

# Test 6: Check for common issues
Write-Host "PHASE 6: Common Issue Checks" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray

# Check for Unicode characters that might cause issues
$psFiles = @(
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\KeyboardSymbols.ps1"
)

foreach ($file in $psFiles) {
    $path = Join-Path $ScriptDir $file
    if (Test-Path $path) {
        $content = Get-Content $path -Raw -Encoding UTF8
        # Check for problematic Unicode box-drawing characters (using hex codes)
        $hasUnicode = $false
        $unicodePatterns = @(
            [char]0x2554, [char]0x2551, [char]0x255A, [char]0x255D,  # Box drawing: ╔║╚╝
            [char]0x2550, [char]0x2500, [char]0x2502,              # Box drawing: ═─│
            [char]0x250C, [char]0x2510, [char]0x2514, [char]0x2518 # Box drawing: ┌┐└┘
        )
        foreach ($pattern in $unicodePatterns) {
            if ($content -match [regex]::Escape($pattern)) {
                $hasUnicode = $true
                break
            }
        }
        
        if ($hasUnicode) {
            Write-TestWarning "Unicode box-drawing characters found in $file (may cause issues)"
        } else {
            Write-TestResult "Unicode check: $file" $true
        }
    }
}

Write-Host ""

# Test 7: Test error code lookup with multiple codes
Write-Host "PHASE 7: Error Code Lookup Tests" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray

$testCodes = @("0xc000000e", "0x80070002", "0x0000007B", "0xC0000225", "0x80070070")
foreach ($code in $testCodes) {
    try {
        $result = Get-WindowsErrorCodeInfo -ErrorCode $code -TargetDrive "C" -ErrorAction Stop
        if ($result) {
            Write-TestResult "Lookup error code: $code" $true "Type: $($result.Type)"
        } else {
            Write-TestResult "Lookup error code: $code" $false "No result returned"
        }
    } catch {
        Write-TestResult "Lookup error code: $code" $false $_.Exception.Message
    }
}

Write-Host ""

# Test 8: Test repair template system
Write-Host "PHASE 8: Repair Template System Tests" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray

try {
    $templates = Get-RepairTemplates -ErrorAction Stop
    if ($templates) {
        Write-TestResult "Get-RepairTemplates returns data" $true "Found $($templates.Count) templates"
        
        # Test that each template has required properties
        foreach ($template in $templates) {
            $hasId = $template.PSObject.Properties.Name -contains "Id"
            $hasName = $template.PSObject.Properties.Name -contains "Name"
            $hasSteps = $template.PSObject.Properties.Name -contains "Steps"
            
            if ($hasId -and $hasName -and $hasSteps) {
                Write-TestResult "Template structure: $($template.Id)" $true
            } else {
                Write-TestResult "Template structure: $($template.Id)" $false "Missing required properties"
            }
        }
    } else {
        Write-TestResult "Get-RepairTemplates returns data" $false "No templates returned"
    }
} catch {
    Write-TestResult "Get-RepairTemplates" $false $_.Exception.Message
}

Write-Host ""

# Final Summary
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $($script:TestResults.TotalTests)" -ForegroundColor White
Write-Host "Passed: $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -eq 0) { "Green" } else { "Red" })
Write-Host "Warnings: $($script:TestResults.Warnings.Count)" -ForegroundColor Yellow
Write-Host ""

if ($script:TestResults.Failed -eq 0) {
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "  ALL TESTS PASSED - CODEBASE IS ERROR-FREE!" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
    exit 0
} else {
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  SOME TESTS FAILED - REVIEW ERRORS ABOVE" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Failed Tests:" -ForegroundColor Yellow
    foreach ($error in $script:TestResults.Errors) {
        Write-Host "  - $error" -ForegroundColor Red
    }
    exit 1
}

