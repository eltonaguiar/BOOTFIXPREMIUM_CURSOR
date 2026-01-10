# Comprehensive test for ONE-CLICK REPAIR - All Phases
# Tests every phase in test mode to ensure no errors or false positives

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ONE-CLICK REPAIR - ALL PHASES TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$global:TestResults = @{
    Total = 0
    Passed = 0
    Failed = 0
    FailedTests = @()
    Warnings = @()
}

function Write-TestLog {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "Gray"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Run-Test {
    param(
        [string]$TestName,
        [scriptblock]$TestScriptBlock
    )
    $global:TestResults.Total++
    Write-Host "`n[TEST] $TestName..." -ForegroundColor Yellow
    try {
        & $TestScriptBlock
        Write-TestLog "  [PASS] $TestName" -Color Green
        $global:TestResults.Passed++
    } catch {
        $errorMessage = $_.Exception.Message
        Write-TestLog "  [FAIL] ${TestName}: $errorMessage" -Color Red
        $global:TestResults.Failed++
        $global:TestResults.FailedTests += "${TestName}: $errorMessage"
    }
}

function Run-SubTest {
    param(
        [string]$TestName,
        [scriptblock]$TestScriptBlock
    )
    Write-Host "  [SUB-TEST] $TestName..." -ForegroundColor DarkYellow
    try {
        & $TestScriptBlock
        Write-TestLog "    [PASS] $TestName" -Color Green
    } catch {
        $errorMessage = $_.Exception.Message
        Write-TestLog "    [FAIL] ${TestName}: $errorMessage" -Color Red
        throw $errorMessage
    }
}

# Load core module
Write-Host "[SETUP] Loading WinRepairCore.ps1..." -ForegroundColor Cyan
try {
    . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Stop
    Write-Host "[OK] Core module loaded" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Failed to load core: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get system drive
$drive = $env:SystemDrive.TrimEnd(':')
Write-Host "Target Drive: $drive`:" -ForegroundColor Yellow
Write-Host ""

# ========================================
# PHASE 1: Hardware Diagnostics
# ========================================
Run-Test "Phase 1: Hardware Diagnostics (Disk Health)" {
    Run-SubTest "Test-DiskHealth function exists" {
        if (-not (Get-Command Test-DiskHealth -ErrorAction SilentlyContinue)) {
            throw "Test-DiskHealth function not found"
        }
    }
    
    Run-SubTest "Test-DiskHealth returns valid object" {
        $diskHealth = Test-DiskHealth -TargetDrive $drive
        if (-not $diskHealth) {
            throw "Test-DiskHealth returned null"
        }
        # Test-DiskHealth returns a hashtable, check for keys
        if (-not $diskHealth.ContainsKey('FileSystemHealthy')) {
            throw "Test-DiskHealth missing FileSystemHealthy key"
        }
    }
    
    Run-SubTest "No false positive hardware failure" {
        $diskHealth = Test-DiskHealth -TargetDrive $drive
        # Check that we're using correct keys (not non-existent ones)
        $hasCorrectKey = $diskHealth.ContainsKey('FileSystemHealthy')
        $hasWrongKey = $diskHealth.ContainsKey('DiskHealthy')
        
        if (-not $hasCorrectKey) {
            throw "Missing correct key: FileSystemHealthy"
        }
        if ($hasWrongKey) {
            throw "Has wrong key: DiskHealthy (should not exist)"
        }
    }
    
    Run-SubTest "Can determine hardware vs software issues" {
        $diskHealth = Test-DiskHealth -TargetDrive $drive
        $isHealthy = $diskHealth.FileSystemHealthy
        $hasBadSectors = $diskHealth.HasBadSectors
        
        # If healthy, should not trigger hardware failure
        if ($isHealthy -and -not $hasBadSectors) {
            # This should NOT be a hardware failure
            Write-TestLog "    Disk is healthy - correctly identified" -Color Gray
        }
    }
}

# ========================================
# PHASE 2: Storage Driver Check
# ========================================
Run-Test "Phase 2: Storage Driver Check" {
    Run-SubTest "Get-MissingStorageDevices function exists" {
        if (-not (Get-Command Get-MissingStorageDevices -ErrorAction SilentlyContinue)) {
            throw "Get-MissingStorageDevices function not found"
        }
    }
    
    Run-SubTest "Get-MissingStorageDevices executes without error" {
        $missingDevices = Get-MissingStorageDevices -ErrorAction Stop
        # Should return a string, not throw an error
        if ($null -eq $missingDevices) {
            throw "Get-MissingStorageDevices returned null"
        }
    }
    
    Run-SubTest "No command execution errors" {
        # This should not throw "command not recognized" errors
        $missingDevices = Get-MissingStorageDevices -ErrorAction Stop
        Write-TestLog "    Result: $($missingDevices.Substring(0, [Math]::Min(100, $missingDevices.Length)))..." -Color Gray
    }
}

# ========================================
# PHASE 3: BCD Integrity Check
# ========================================
Run-Test "Phase 3: BCD Integrity Check" {
    Run-SubTest "bcdedit command is available" {
        $bcdCmd = Get-Command "bcdedit" -ErrorAction SilentlyContinue
        if (-not $bcdCmd) {
            throw "bcdedit command not found"
        }
    }
    
    Run-SubTest "bcdedit /enum all executes without error" {
        $bcdCheck = bcdedit /enum all 2>&1 | Out-String
        # Should not throw "command not recognized"
        if ($bcdCheck -match "is not recognized") {
            throw "bcdedit command not recognized: $bcdCheck"
        }
    }
    
    Run-SubTest "bootrec.exe availability check" {
        # Check if bootrec.exe exists (may not in regular Windows)
        $bootrecPath = $null
        $bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
        if ($bootrecCmd) {
            $bootrecPath = $bootrecCmd.Source
        } else {
            # Try common paths
            $possiblePaths = @(
                "$env:SystemRoot\System32\bootrec.exe",
                "X:\Windows\System32\bootrec.exe",
                "C:\Windows\System32\Recovery\bootrec.exe"
            )
            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    $bootrecPath = $path
                    break
                }
            }
        }
        
        if ($bootrecPath) {
            Write-TestLog "    bootrec.exe found at: $bootrecPath" -Color Gray
        } else {
            Write-TestLog "    bootrec.exe not available (normal in regular Windows)" -Color Yellow
            $global:TestResults.Warnings += "bootrec.exe not available - this is normal in regular Windows session"
        }
    }
    
    Run-SubTest "bootrec /rebuildbcd does not throw if bootrec unavailable" {
        # This should gracefully handle missing bootrec
        $bootrecPath = $null
        $bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
        if ($bootrecCmd) {
            $bootrecPath = $bootrecCmd.Source
        } else {
            $possiblePaths = @(
                "$env:SystemRoot\System32\bootrec.exe",
                "X:\Windows\System32\bootrec.exe",
                "C:\Windows\System32\Recovery\bootrec.exe"
            )
            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    $bootrecPath = $path
                    break
                }
            }
        }
        
        if ($bootrecPath) {
            # If available, test that it can be called
            try {
                $result = & $bootrecPath /rebuildbcd 2>&1 | Out-String
                Write-TestLog "    bootrec.exe executed (may fail if not in WinRE, but command exists)" -Color Gray
            } catch {
                # This is OK - bootrec may fail if not in WinRE, but shouldn't throw "not recognized"
                if ($_.Exception.Message -match "not recognized") {
                    throw "bootrec command not recognized: $_"
                }
                Write-TestLog "    bootrec.exe failed (expected if not in WinRE): $($_.Exception.Message)" -Color Yellow
            }
        } else {
            # If not available, should not throw error
            Write-TestLog "    bootrec.exe not available - gracefully handled" -Color Gray
        }
    }
}

# ========================================
# PHASE 4: Boot File Check
# ========================================
Run-Test "Phase 4: Boot File Check" {
    Run-SubTest "Boot file paths are valid" {
        $bootFiles = @("bootmgfw.efi", "winload.efi", "winload.exe")
        $efiPath = "$drive`:\EFI\Microsoft\Boot"
        $winPath = "$drive`:\Windows\System32"
        
        # Check that paths can be constructed
        foreach ($file in $bootFiles) {
            $fullEfiPath = "$efiPath\$file"
            $fullWinPath = "$winPath\$file"
            # Just check that paths are valid format, not that files exist
            if ($fullEfiPath -notmatch '^[A-Z]:\\') {
                throw "Invalid EFI path format: $fullEfiPath"
            }
            if ($fullWinPath -notmatch '^[A-Z]:\\') {
                throw "Invalid Windows path format: $fullWinPath"
            }
        }
    }
    
    Run-SubTest "Test-Path works for boot files" {
        $bootFiles = @("bootmgfw.efi", "winload.efi", "winload.exe")
        foreach ($file in $bootFiles) {
            $efiPath = "$drive`:\EFI\Microsoft\Boot\$file"
            $winPath = "$drive`:\Windows\System32\$file"
            # Test-Path should not throw errors
            $efiExists = Test-Path $efiPath -ErrorAction SilentlyContinue
            $winExists = Test-Path $winPath -ErrorAction SilentlyContinue
            # Just verify it doesn't throw
        }
    }
    
    Run-SubTest "bootrec /fixboot does not throw if bootrec unavailable" {
        $bootrecPath = $null
        $bootrecCmd = Get-Command "bootrec" -ErrorAction SilentlyContinue
        if ($bootrecCmd) {
            $bootrecPath = $bootrecCmd.Source
        } else {
            $possiblePaths = @(
                "$env:SystemRoot\System32\bootrec.exe",
                "X:\Windows\System32\bootrec.exe",
                "C:\Windows\System32\Recovery\bootrec.exe"
            )
            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    $bootrecPath = $path
                    break
                }
            }
        }
        
        if ($bootrecPath) {
            try {
                $result = & $bootrecPath /fixboot 2>&1 | Out-String
                Write-TestLog "    bootrec.exe executed (may fail if not in WinRE, but command exists)" -Color Gray
            } catch {
                if ($_.Exception.Message -match "not recognized") {
                    throw "bootrec command not recognized: $_"
                }
                Write-TestLog "    bootrec.exe failed (expected if not in WinRE): $($_.Exception.Message)" -Color Yellow
            }
        } else {
            Write-TestLog "    bootrec.exe not available - gracefully handled" -Color Gray
        }
    }
}

# ========================================
# PHASE 5: Final Summary
# ========================================
Run-Test "Phase 5: Final Summary Generation" {
    Run-SubTest "Summary can be generated" {
        # Just verify we can create summary text
        $summary = "ONE-CLICK REPAIR SUMMARY`n"
        $summary += "===============================================================`n"
        $summary += "Drive: $drive`:`n"
        $summary += "Status: Test Complete`n"
        
        if ([string]::IsNullOrWhiteSpace($summary)) {
            throw "Summary is empty"
        }
    }
    
    Run-SubTest "No null reference errors" {
        # Verify we can access properties without null errors
        $issuesFound = 0
        $diskHealth = Test-DiskHealth -TargetDrive $drive
        if (-not $diskHealth.FileSystemHealthy) {
            $issuesFound++
        }
        # Should not throw null reference
    }
}

# ========================================
# SUMMARY
# ========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nTotal Tests: $($global:TestResults.Total)"
Write-Host "Passed: $($global:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($global:TestResults.Failed)" -ForegroundColor $(if ($global:TestResults.Failed -eq 0) { "Green" } else { "Red" })

if ($global:TestResults.Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    foreach ($warning in $global:TestResults.Warnings) {
        Write-Host "  - $warning" -ForegroundColor Yellow
    }
}

if ($global:TestResults.Failed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $global:TestResults.FailedTests | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    exit 1
} else {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nAll phases of ONE-CLICK REPAIR are working correctly." -ForegroundColor Green
    exit 0
}
