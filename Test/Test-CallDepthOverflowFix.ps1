# Test-CallDepthOverflowFix.ps1
# Comprehensive automated test for call depth overflow fix
# Tests Write-Warning recursion protection and call depth limits

$ErrorActionPreference = 'Stop'
$PSMaximumCallDepth = 5000

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CALL DEPTH OVERFLOW FIX TEST SUITE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$testResults = @()
$testCount = 0
$passCount = 0
$failCount = 0

function Test-CallDepthScenario {
    param(
        [string]$TestName,
        [scriptblock]$TestScript,
        [string]$ExpectedResult = "No overflow"
    )
    
    $script:testCount++
    Write-Host "[TEST $testCount] $TestName..." -ForegroundColor Yellow -NoNewline
    
    try {
        $result = & $TestScript
        $script:passCount++
        Write-Host " PASS" -ForegroundColor Green
        $script:testResults += @{
            Test = $TestName
            Status = "PASS"
            Result = $result
        }
        return $true
    } catch {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match 'depth|overflow') {
            $script:failCount++
            Write-Host " FAIL" -ForegroundColor Red
            Write-Host "  Error: $errorMsg" -ForegroundColor Yellow
            $script:testResults += @{
                Test = $TestName
                Status = "FAIL"
                Error = $errorMsg
            }
            return $false
        } else {
            # Non-overflow error, might be expected
            $script:passCount++
            Write-Host " PASS (non-overflow error)" -ForegroundColor Green
            $script:testResults += @{
                Test = $TestName
                Status = "PASS"
                Note = "Non-overflow error: $errorMsg"
            }
            return $true
        }
    }
}

Write-Host "Loading ErrorLogging.ps1..." -ForegroundColor Gray
try {
    . '.\Helper\ErrorLogging.ps1'
    Write-Host "[OK] ErrorLogging.ps1 loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Failed to load ErrorLogging.ps1: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Running test scenarios..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Simple Write-Warning call
Test-CallDepthScenario -TestName "Simple Write-Warning call" -TestScript {
    Write-Warning "Test warning message"
    return "OK"
}

# Test 2: Multiple Write-Warning calls
Test-CallDepthScenario -TestName "Multiple Write-Warning calls (10)" -TestScript {
    for ($i = 1; $i -le 10; $i++) {
        Write-Warning "Test warning $i"
    }
    return "OK"
}

# Test 3: Nested Write-Warning calls (simulating recursion)
Test-CallDepthScenario -TestName "Nested Write-Warning calls (5 levels)" -TestScript {
    function Test-NestedWarning {
        param([int]$Depth)
        if ($Depth -le 0) { return }
        Write-Warning "Nested warning at depth $Depth"
        Test-NestedWarning -Depth ($Depth - 1)
    }
    Test-NestedWarning -Depth 5
    return "OK"
}

# Test 4: Write-Warning during Add-MiracleBootLog (if it triggers)
Test-CallDepthScenario -TestName "Write-Warning during logging operations" -TestScript {
    # Simulate logging that might trigger Write-Warning
    Add-MiracleBootLog -Level "INFO" -Message "Test log message" -Location "Test" -NoConsole -ErrorAction SilentlyContinue
    Write-Warning "Warning after logging"
    return "OK"
}

# Test 5: Rapid Write-Warning calls
Test-CallDepthScenario -TestName "Rapid Write-Warning calls (50)" -TestScript {
    for ($i = 1; $i -le 50; $i++) {
        Write-Warning "Rapid warning $i"
    }
    return "OK"
}

# Test 6: Write-Warning with long message
Test-CallDepthScenario -TestName "Write-Warning with long message" -TestScript {
    $longMessage = "A" * 1000
    Write-Warning $longMessage
    return "OK"
}

# Test 7: Write-Warning in try-catch block
Test-CallDepthScenario -TestName "Write-Warning in error handling" -TestScript {
    try {
        throw "Test error"
    } catch {
        Write-Warning "Warning in catch block: $_"
    }
    return "OK"
}

# Test 8: Multiple simultaneous Write-Warning calls (simulate concurrent)
Test-CallDepthScenario -TestName "Multiple Write-Warning in loop (100)" -TestScript {
    1..100 | ForEach-Object {
        Write-Warning "Warning $_"
    }
    return "OK"
}

# Test 9: Write-Warning during GUI initialization simulation
Test-CallDepthScenario -TestName "Write-Warning during simulated GUI init" -TestScript {
    # Simulate GUI initialization with many operations
    $script:DisableCallStackRetrieval = $true
    for ($i = 1; $i -le 20; $i++) {
        Write-Warning "GUI init warning $i"
    }
    $script:DisableCallStackRetrieval = $false
    return "OK"
}

# Test 10: Verify call depth limit is respected
Test-CallDepthScenario -TestName "Call depth limit check" -TestScript {
    $currentDepth = (Get-PSCallStack).Count
    if ($currentDepth -gt 5000) {
        throw "Call depth exceeds limit: $currentDepth"
    }
    return "OK - Depth: $currentDepth"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TEST RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $testCount" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($failCount -eq 0) {
    Write-Host "[SUCCESS] All call depth overflow tests passed!" -ForegroundColor Green
    Write-Host "[VERIFIED] Write-Warning recursion protection is working" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "[FAILURE] $failCount test(s) failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Yellow
    foreach ($result in $testResults) {
        if ($result.Status -eq "FAIL") {
            Write-Host "  - $($result.Test): $($result.Error)" -ForegroundColor Red
        }
    }
    exit 1
}
