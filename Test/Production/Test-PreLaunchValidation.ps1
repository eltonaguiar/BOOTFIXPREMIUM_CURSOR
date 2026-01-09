# Test-PreLaunchValidation.ps1
# Pre-launch validation that runs MiracleBoot.ps1 up to GUI launch point
# and checks for any errors in the output

$ErrorActionPreference = 'Continue'
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PRE-LAUNCH VALIDATION - MIRACLEBOOT.PS1" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$miracleBootPath = Join-Path $scriptRoot "MiracleBoot.ps1"

if (-not (Test-Path $miracleBootPath)) {
    Write-Host "[FAIL] MiracleBoot.ps1 not found: $miracleBootPath" -ForegroundColor Red
    exit 1
}

Write-Host "Testing MiracleBoot.ps1 execution up to GUI launch point..." -ForegroundColor Yellow
Write-Host ""

# Create a simpler test script
$testScriptPath = Join-Path $env:TEMP "MiracleBoot_PreLaunch_Test_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"

$testScriptContent = @'
$ErrorActionPreference = 'Continue'
$scriptRoot = '{0}'
$allOutput = @()
$allErrors = @()

function Write-OutputCapture {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::White)
    $script:allOutput += $Message
    Write-Host $Message -ForegroundColor $Color
}

try {
    Write-OutputCapture "Starting MiracleBoot.ps1 validation..." Cyan
    
    # Load core modules
    Write-OutputCapture "Loading WinRepairCore.ps1..." Yellow
    try {
        . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Stop
        Write-OutputCapture "WinRepairCore.ps1 loaded successfully" Green
    } catch {
        Write-OutputCapture "ERROR: Failed to load WinRepairCore.ps1: $_" Red
        $script:allErrors += "Failed to load WinRepairCore.ps1: $_"
    }
    
    Write-OutputCapture "Loading NetworkDiagnostics.ps1..." Yellow
    if (Test-Path "$scriptRoot\Helper\NetworkDiagnostics.ps1") {
        try {
            . "$scriptRoot\Helper\NetworkDiagnostics.ps1" -ErrorAction Stop
            Write-OutputCapture "NetworkDiagnostics.ps1 loaded successfully" Green
        } catch {
            Write-OutputCapture "ERROR: Failed to load NetworkDiagnostics.ps1: $_" Red
            $script:allErrors += "Failed to load NetworkDiagnostics.ps1: $_"
        }
    }
    
    Write-OutputCapture "Loading KeyboardSymbols.ps1..." Yellow
    if (Test-Path "$scriptRoot\Helper\KeyboardSymbols.ps1") {
        try {
            . "$scriptRoot\Helper\KeyboardSymbols.ps1" -ErrorAction Stop
            Write-OutputCapture "KeyboardSymbols.ps1 loaded successfully" Green
        } catch {
            Write-OutputCapture "ERROR: Failed to load KeyboardSymbols.ps1: $_" Red
            $script:allErrors += "Failed to load KeyboardSymbols.ps1: $_"
        }
    }
    
    # Test environment detection
    Write-OutputCapture "Testing environment detection..." Yellow
    if (Get-Command Get-EnvironmentType -ErrorAction SilentlyContinue) {
        $envType = Get-EnvironmentType
        Write-OutputCapture "Environment: $envType" Cyan
    } else {
        Write-OutputCapture "ERROR: Get-EnvironmentType function not found" Red
        $script:allErrors += "Get-EnvironmentType function not found"
        $envType = "Unknown"
    }
    
    # Verify core functions
    Write-OutputCapture "Verifying core functions..." Yellow
    $requiredFunctions = @("Get-EnvironmentType", "Get-WindowsVolumes")
    foreach ($func in $requiredFunctions) {
        if (Get-Command $func -ErrorAction SilentlyContinue) {
            Write-OutputCapture "  [OK] $func" Green
        } else {
            Write-OutputCapture "  [FAIL] $func not found" Red
            $script:allErrors += "Required function $func not found"
        }
    }
    
    # Try to load GUI module (but don't launch)
    if ($envType -eq "FullOS") {
        Write-OutputCapture "Testing GUI module loading..." Yellow
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            Write-OutputCapture "WPF assemblies available" Green
            
            if (Test-Path "$scriptRoot\Helper\WinRepairGUI.ps1") {
                Write-OutputCapture "Loading WinRepairGUI.ps1..." Yellow
                . "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Stop
                
                if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
                    Write-OutputCapture "Start-GUI function found" Green
                } else {
                    Write-OutputCapture "ERROR: Start-GUI function not found" Red
                    $script:allErrors += "Start-GUI function not found after loading WinRepairGUI.ps1"
                }
                
                # Verify LogAnalysis.ps1 loaded (it's loaded by WinRepairGUI.ps1)
                if (Get-Command Get-ComprehensiveLogAnalysis -ErrorAction SilentlyContinue) {
                    Write-OutputCapture "LogAnalysis.ps1 loaded successfully" Green
                } else {
                    Write-OutputCapture "INFO: LogAnalysis functions not found (may not be loaded yet)" Gray
                }
            }
        } catch {
            Write-OutputCapture "WPF not available or GUI module failed: $_" Yellow
            if ($_.Exception.Message -match "error|exception|failed|fail") {
                $script:allErrors += "GUI module loading error: $_"
            }
        }
    } else {
        Write-OutputCapture "Not FullOS environment - skipping GUI test" Gray
    }
    
    Write-OutputCapture "" White
    Write-OutputCapture "=== VALIDATION COMPLETE ===" Cyan
    Write-OutputCapture "Output lines: $($allOutput.Count)" Gray
    Write-OutputCapture "Errors found: $($allErrors.Count)" $(if ($allErrors.Count -eq 0) { "Green" } else { "Red" })
    
    # Output all captured content
    $allOutput | ForEach-Object { Write-Host $_ }
    
    if ($allErrors.Count -gt 0) {
        Write-Host ""
        Write-Host "=== ERRORS DETECTED ===" -ForegroundColor Red
        $allErrors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
    
    exit 0
    
} catch {
    Write-Host "[FAIL] Exception during validation: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
    exit 1
}
'@ -f $scriptRoot

Set-Content -Path $testScriptPath -Value $testScriptContent -Encoding UTF8

try {
    Write-Host "Running pre-launch validation..." -ForegroundColor Yellow
    Write-Host ""
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'pwsh.exe'
    $psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$testScriptPath`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    
    [void]$process.Start()
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    
    $exitCode = $process.ExitCode
    
    # Display output
    Write-Host $stdOut
    
    if ($stdErr) {
        Write-Host ""
        Write-Host "=== STDERR ===" -ForegroundColor Yellow
        Write-Host $stdErr -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "ERROR SCAN RESULTS" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host ""
    
    # Scan for error keywords (case-insensitive)
    $errorPatterns = @(
        '\bERROR:\b',           # Explicit ERROR: prefix
        '\b\[FAIL\]\b',        # [FAIL] marker
        '\bFAILED\b',          # FAILED (all caps)
        'parsererror',         # ParserError
        'syntax error',        # syntax error
        'runtime error',       # runtime error
        'exception.*validation', # Exception during validation
        'collection was modified', # Collection enumeration error
        'cannot.*recognized',   # "cannot be recognized"
        'missing.*closing',     # "missing closing"
        'unexpected token'      # unexpected token
    )
    
    # Patterns that are OK (not errors)
    $okPatterns = @(
        'INFO:.*not found.*may not be loaded',  # Info messages about optional functions
        'WARNING:.*not found',                   # Warnings (we track these separately)
        'No.*available',                         # "No browser available" is OK
        'not found.*may not be loaded yet'       # Optional loading messages
    )
    
    $combinedOutput = $stdOut + "`n" + $stdErr
    $errorsFound = @()
    
    foreach ($pattern in $errorPatterns) {
        $matches = [regex]::Matches($combinedOutput, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($matches.Count -gt 0) {
            foreach ($match in $matches) {
                $start = [Math]::Max(0, $match.Index - 100)
                $length = [Math]::Min(200, $combinedOutput.Length - $start)
                $context = $combinedOutput.Substring($start, $length)
                
                # Check if this is a false positive
                $isFalsePositive = $false
                foreach ($okPattern in $okPatterns) {
                    if ($context -match $okPattern) {
                        $isFalsePositive = $true
                        break
                    }
                }
                
                if (-not $isFalsePositive) {
                    $lines = $context -split "`r?`n"
                    $lineNum = ($combinedOutput.Substring(0, $match.Index) -split "`r?`n").Count
                    $lineText = if ($lines.Count -gt 0) { $lines[0].Trim() } else { $context.Trim() }
                    if ($lineText.Length -gt 150) { $lineText = $lineText.Substring(0, 147) + "..." }
                    $errorsFound += [PSCustomObject]@{
                        Pattern = $pattern
                        Line = $lineNum
                        Context = $lineText
                    }
                }
            }
        }
    }
    
    # Remove duplicates
    $errorsFound = $errorsFound | Sort-Object Line, Pattern -Unique
    
    if ($errorsFound.Count -gt 0) {
        Write-Host "[FAIL] ERRORS DETECTED IN OUTPUT:" -ForegroundColor Red
        Write-Host ""
        $errorsFound | Select-Object -First 30 | ForEach-Object {
            Write-Host "  Line ~$($_.Line): Found '$($_.Pattern)'" -ForegroundColor Red
            Write-Host "    Context: $($_.Context)" -ForegroundColor Yellow
            Write-Host ""
        }
        if ($errorsFound.Count -gt 30) {
            Write-Host "  ... and $($errorsFound.Count - 30) more error matches" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "EXIT CODE: $exitCode" -ForegroundColor Red
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host "VALIDATION FAILED - DO NOT PROCEED TO USER TESTING" -ForegroundColor Red
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host ""
        Write-Host "Investigate and fix errors before allowing user testing." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "[PASS] No error keywords found in output" -ForegroundColor Green
        Write-Host ""
        Write-Host "EXIT CODE: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })
        Write-Host ""
        if ($exitCode -eq 0) {
            Write-Host "=" * 80 -ForegroundColor Green
            Write-Host "VALIDATION PASSED - READY FOR USER TESTING" -ForegroundColor Green
            Write-Host "=" * 80 -ForegroundColor Green
            exit 0
        } else {
            Write-Host "=" * 80 -ForegroundColor Yellow
            Write-Host "VALIDATION WARNING - Exit code non-zero but no error keywords found" -ForegroundColor Yellow
            Write-Host "=" * 80 -ForegroundColor Yellow
            Write-Host "Review output above for warnings or issues." -ForegroundColor Yellow
            exit 1
        }
    }
    
} catch {
    Write-Host "[FAIL] Exception during validation: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
    exit 1
} finally {
    if (Test-Path $testScriptPath) {
        Remove-Item $testScriptPath -Force -ErrorAction SilentlyContinue
    }
}
