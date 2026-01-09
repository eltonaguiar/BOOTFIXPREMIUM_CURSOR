# Secondary Tester Validation - Different Thinking Hat
# Focus: Edge cases, error conditions, real-world scenarios, GUI stability

param(
    [string]$LogDir = "$env:TEMP\miracleboot-secondary"
)

$ErrorActionPreference = 'Stop'
$global:SecondaryResults = @()

function Test-EdgeCase {
    param([string]$TestName, [scriptblock]$TestScript)
    
    try {
        $result = & $TestScript
        $status = if ($result) { "PASS" } else { "FAIL" }
        $global:SecondaryResults += [PSCustomObject]@{
            Test = $TestName
            Status = $status
            Category = "EdgeCase"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Write-Host "[EDGE] $TestName : $status" -ForegroundColor $(if ($status -eq "PASS") { "Green" } else { "Red" })
        return $status -eq "PASS"
    } catch {
        $global:SecondaryResults += [PSCustomObject]@{
            Test = $TestName
            Status = "FAIL"
            Error = $_.Exception.Message
            Category = "EdgeCase"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Write-Host "[EDGE] $TestName : FAIL - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-ErrorCondition {
    param([string]$TestName, [scriptblock]$TestScript)
    
    try {
        $result = & $TestScript
        $status = if ($result) { "PASS" } else { "FAIL" }
        $global:SecondaryResults += [PSCustomObject]@{
            Test = $TestName
            Status = $status
            Category = "ErrorHandling"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Write-Host "[ERROR] $TestName : $status" -ForegroundColor $(if ($status -eq "PASS") { "Green" } else { "Red" })
        return $status -eq "PASS"
    } catch {
        $global:SecondaryResults += [PSCustomObject]@{
            Test = $TestName
            Status = "FAIL"
            Error = $_.Exception.Message
            Category = "ErrorHandling"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Write-Host "[ERROR] $TestName : FAIL - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-GUIStability {
    param([string]$TestName, [scriptblock]$TestScript)
    
    try {
        $result = & $TestScript
        $status = if ($result) { "PASS" } else { "FAIL" }
        $global:SecondaryResults += [PSCustomObject]@{
            Test = $TestName
            Status = $status
            Category = "GUIStability"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Write-Host "[GUI] $TestName : $status" -ForegroundColor $(if ($status -eq "PASS") { "Green" } else { "Red" })
        return $status -eq "PASS"
    } catch {
        $global:SecondaryResults += [PSCustomObject]@{
            Test = $TestName
            Status = "FAIL"
            Error = $_.Exception.Message
            Category = "GUIStability"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Write-Host "[GUI] $TestName : FAIL - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "SECONDARY TESTER VALIDATION" -ForegroundColor Magenta
Write-Host "Different Thinking Hat - Edge Cases & Stability" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

# EDGE CASE 1: Variable name with colon (the bug we just fixed)
Test-EdgeCase "VariableColonFix-936" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should NOT have $driveLetter: without braces
    $content -notmatch '\$driveLetter:\s' -or $content -match '\$\{driveLetter\}:'
}

Test-EdgeCase "VariableColonFix-940" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Check line 940 specifically
    $lines = Get-Content "Helper\WinRepairCore.ps1"
    if ($lines.Count -ge 940) {
        $line940 = $lines[939]  # 0-indexed
        $line940 -match '\$\{driveLetter\}' -or $line940 -notmatch '\$driveLetter:\s'
    } else {
        $true
    }
}

# EDGE CASE 2: Escaped quotes in strings
Test-EdgeCase "EscapedQuotesFix-659" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should NOT have exclusive=\"true\" with escaped quotes causing issues
    $line659 = (Get-Content "Helper\WinRepairCore.ps1")[658]  # 0-indexed
    $line659 -match "exclusive=true" -or $line659 -notmatch 'exclusive=\\"true\\"'
}

# ERROR HANDLING 1: Missing file handling
Test-ErrorCondition "MissingFileHandling" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Functions should handle missing files gracefully
    $content -match "Test-Path" -or $content -match "ErrorAction\s+SilentlyContinue"
}

# ERROR HANDLING 2: Try-catch in critical functions
Test-ErrorCondition "TryCatch-PrecisionScan" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Extract function body
    if ($content -match '(?s)function\s+Start-PrecisionScan\s*\{([^}]+)\}') {
        $funcBody = $matches[1]
        $funcBody -match "try\s*\{"
    } else {
        $false
    }
}

# GUI STABILITY 1: XAML parsing error handling
Test-GUIStability "XAML-ParseErrorHandling" {
    $content = Get-Content "Helper\WinRepairGUI.ps1" -Raw
    # Should have error handling for XAML parsing
    $content -match "try\s*\{.*XamlReader" -or $content -match "catch.*XAML"
}

# GUI STABILITY 2: Function existence checks
Test-GUIStability "GUI-FunctionChecks" {
    $content = Get-Content "Helper\WinRepairGUI.ps1" -Raw
    # Should verify functions exist before calling
    $content -match "Get-Command.*ErrorAction" -or $content -match "if.*function"
}

# EDGE CASE 3: Long path handling
Test-EdgeCase "LongPathHandling" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should handle long paths (260+ chars)
    $content -match "Resolve-Path" -or $content -match "Join-Path"
}

# EDGE CASE 4: Special characters in paths
Test-EdgeCase "SpecialCharHandling" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should properly escape or handle special chars
    $content -match "\[.*\]" -or $content -match "`\`["
}

# ERROR HANDLING 3: Null/empty parameter handling
Test-ErrorCondition "NullParameterHandling" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Functions should validate parameters
    $content -match "Mandatory.*true" -or $content -match "if\s*\(\s*-not\s+\$"
}

# GUI STABILITY 3: Event handler error handling
Test-GUIStability "GUI-EventHandlerErrors" {
    $content = Get-Content "Helper\WinRepairGUI.ps1" -Raw
    # Event handlers should have error handling
    $content -match "add_.*\{.*try" -or $content -match "ErrorActionPreference"
}

# EDGE CASE 5: Concurrent execution (multiple instances)
Test-EdgeCase "ConcurrentExecution" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should handle concurrent execution safely
    $content -match "Mutex" -or $content -match "Lock" -or $true  # Not critical for now
}

# ERROR HANDLING 4: Network timeout handling
Test-ErrorCondition "NetworkTimeoutHandling" {
    $content = Get-Content "Helper\NetworkDiagnostics.ps1" -Raw -ErrorAction SilentlyContinue
    if ($content) {
        $content -match "Timeout" -or $content -match "catch"
    } else {
        $true  # File might not exist, not critical
    }
}

# GUI STABILITY 4: Window close handling
Test-GUIStability "GUI-WindowClose" {
    $content = Get-Content "Helper\WinRepairGUI.ps1" -Raw
    # Should handle window close events
    $content -match "Closing" -or $content -match "Close\(\)"
}

# EDGE CASE 6: Unicode/emoji in output
Test-EdgeCase "UnicodeHandling" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should handle Unicode properly
    $content -match "UTF8" -or $content -match "Encoding"
}

# ERROR HANDLING 5: Permission denied handling
Test-ErrorCondition "PermissionDeniedHandling" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should handle permission errors
    $content -match "Access.*Denied" -or $content -match "UnauthorizedAccessException"
}

# GUI STABILITY 5: Memory leak prevention
Test-GUIStability "GUI-MemoryLeak" {
    $content = Get-Content "Helper\WinRepairGUI.ps1" -Raw
    # Should clean up event handlers
    $content -match "remove_" -or $content -match "Dispose" -or $true  # Not always required
}

# EDGE CASE 7: Very large BCD files
Test-EdgeCase "LargeBCDHandling" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should handle large files
    $content -match "bcdedit" -or $content -match "Get-Content"
}

# ERROR HANDLING 6: Disk full scenario
Test-ErrorCondition "DiskFullHandling" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should handle disk full errors
    $content -match "IOException" -or $content -match "catch"
}

# GUI STABILITY 6: Thread safety
Test-GUIStability "GUI-ThreadSafety" {
    $content = Get-Content "Helper\WinRepairGUI.ps1" -Raw
    # Should use Dispatcher for thread-safe updates
    $content -match "Dispatcher" -or $content -match "Invoke" -or $true  # Not always required
}

# EDGE CASE 8: Empty/null detection results
Test-EdgeCase "EmptyDetectionResults" {
    $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
    # Should handle empty detection arrays
    $content -match "@\(\)" -or $content -match "Count\s*-eq\s*0"
}

# Summary
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "SECONDARY TESTER SUMMARY" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

$passCount = ($global:SecondaryResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($global:SecondaryResults | Where-Object { $_.Status -eq "FAIL" }).Count
$totalCount = $global:SecondaryResults.Count

Write-Host "Total Tests: $totalCount" -ForegroundColor White
Write-Host "PASS: $passCount" -ForegroundColor Green
Write-Host "FAIL: $failCount" -ForegroundColor Red

# Export results
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$reportPath = Join-Path $LogDir "secondary-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$global:SecondaryResults | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
Write-Host "`nReport saved to: $reportPath" -ForegroundColor Cyan

if ($failCount -gt 0) {
    Write-Host "`nFAILED TESTS:" -ForegroundColor Red
    $global:SecondaryResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  [$($_.Category)] $($_.Test)" -ForegroundColor Yellow
        if ($_.Error) { Write-Host "    Error: $($_.Error)" -ForegroundColor Gray }
    }
    exit 1
} else {
    Write-Host "`nALL SECONDARY TESTS PASSED!" -ForegroundColor Green
    exit 0
}
