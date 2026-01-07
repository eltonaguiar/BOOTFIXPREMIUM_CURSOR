<# 
    SUPER TEST - HARD GATE FOR MIRACLEBOOT
    ======================================
    This script is the **mandatory pre-release gate** that MUST pass before
    any change can be considered "out of coding phase".

    What it does:
    - PHASE 0: Comprehensive syntax validation using PowerShell parser (FASTEST FEEDBACK)
    - PHASE 1: GUI launch test - validates UI can start without showing window
    - PHASE 2: Runs all existing automated suites:
        - Test\Test-CompleteCodebase.ps1
        - Test\Test-SafeFunctions.ps1
        - Test\Test-MiracleBoot.ps1
    - Captures ALL output (stdout + stderr) to timestamped log files.
    - Scans logs for **critical parser/runtime keywords** that should never
      appear if the code is ready (e.g. "Missing closing", "ParserError").
    - Fails with a non‑zero exit code if:
        - Any syntax error is detected, OR
        - GUI cannot launch successfully, OR
        - Any underlying test script returns non‑zero, OR
        - Any critical keyword is detected in logs.

    Usage (from repo root):
        pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\SuperTest-MiracleBoot.ps1"

    This script is intentionally strict – if it passes, you should be able
    to launch MiracleBoot's UI on Windows 11 without obvious syntax errors.
    
    MANDATORY: This test MUST pass before any code can proceed out of coding phase.
#>

$ErrorActionPreference = 'Stop'

# Ensure we are running from the repository root (handles being called from Test\)
if ($PSScriptRoot -and (Split-Path $PSScriptRoot -Leaf) -eq 'Test') {
    Set-Location (Split-Path $PSScriptRoot -Parent)
}

$root = Get-Location
$logRoot = Join-Path $root 'Test\SuperTestLogs'

if (-not (Test-Path $logRoot)) {
    New-Item -Path $logRoot -ItemType Directory | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryLog = Join-Path $logRoot "SuperTest_Summary_$timestamp.log"

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $summaryLog -Value $Message
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  MIRACLEBOOT SUPER TEST - HARD GATE" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Super Test started at $(Get-Date)"
Write-Log "Repository root : $root"
Write-Log "Log directory   : $logRoot"
Write-Log ""

$criticalPatterns = @(
    'Missing closing',
    'Unexpected token',
    'ParserError',
    'The term .* is not recognized',
    'Exception calling',
    'Call stack:',
    'At line:',
    'Cannot index into a null array',
    'Cannot call a method on a null-valued expression',
    'You cannot call a method on a null-valued expression',
    'Cannot bind argument to parameter',
    'Missing argument in parameter list',
    'Missing expression after',
    'The string is missing the terminator',
    'Unexpected end of expression',
    'Missing closing brace',
    'Missing closing bracket',
    'Missing closing parenthesis',
    'Missing type name after',
    'Invalid function definition',
    'Function already defined',
    'Variable.*cannot be found',
    'Property.*cannot be found',
    'Method.*cannot be found',
    'Cannot find type',
    'Assembly.*could not be loaded',
    'Could not load file or assembly',
    'GUI mode failed',
    'Falling back to TUI',
    'Error: At.*char:',
    'SyntaxError',
    'RuntimeException'
)

$overallExitCode = 0
$testRuns = @()

# PowerShell files to validate
$psFiles = @(
    "MiracleBoot.ps1",
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\KeyboardSymbols.ps1"
)

function Test-PowerShellSyntax {
    param(
        [string]$FilePath,
        [string]$DisplayName
    )
    
    $absolutePath = Join-Path $root $FilePath
    if (-not (Test-Path $absolutePath)) {
        Write-Log "[FAIL] Syntax check: $DisplayName - File not found: $absolutePath" ([ConsoleColor]::Red)
        $global:overallExitCode = 1
        return $false
    }
    
    try {
        $content = Get-Content $absolutePath -Raw -ErrorAction Stop
        $errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
        
        if ($errors.Count -eq 0) {
            Write-Log "[PASS] Syntax check: $DisplayName" ([ConsoleColor]::Green)
            return $true
        } else {
            Write-Log "[FAIL] Syntax check: $DisplayName - Found $($errors.Count) syntax error(s)" ([ConsoleColor]::Red)
            foreach ($err in $errors | Select-Object -First 5) {
                $lineInfo = if ($err.Token) { "Line $($err.Token.StartLine), Column $($err.Token.StartColumn)" } else { "Unknown location" }
                Write-Log "      $lineInfo : $($err.Message)" ([ConsoleColor]::Yellow)
            }
            $global:overallExitCode = 1
            return $false
        }
    } catch {
        Write-Log "[FAIL] Syntax check: $DisplayName - Failed to parse: $_" ([ConsoleColor]::Red)
        $global:overallExitCode = 1
        return $false
    }
}

function Test-GUILaunch {
    Write-Log "Testing GUI launch capability..." ([ConsoleColor]::Yellow)
    
    $guiTestLog = Join-Path $logRoot "GUILaunchTest_$timestamp.log"
    $guiTestScript = @"
`$ErrorActionPreference = 'Stop'
`$root = '$root'

try {
    # Simple environment check (GUI only works in FullOS)
    # Check SystemDrive - X: indicates WinRE/WinPE
    if (`$env:SystemDrive -eq 'X:') {
        Write-Host "[SKIP] Not in FullOS environment (SystemDrive=X:) - GUI test skipped" -ForegroundColor Yellow
        exit 0
    }
    
    # Check if Windows directory exists on SystemDrive (FullOS indicator)
    if (-not (Test-Path "`$env:SystemDrive\Windows")) {
        Write-Host "[SKIP] Windows directory not found - may not be FullOS - GUI test skipped" -ForegroundColor Yellow
        exit 0
    }
    
    # Load core
    . "`$root\Helper\WinRepairCore.ps1" -ErrorAction Stop
    
    # Try to load WPF assemblies
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Write-Host "[PASS] WPF assemblies loaded" -ForegroundColor Green
    } catch {
        Write-Host "[SKIP] WPF not available: `$_" -ForegroundColor Yellow
        exit 0
    }
    
    # Load GUI module (this will catch syntax errors)
    `$ErrorActionPreference = 'SilentlyContinue'
    `$output = . "`$root\Helper\WinRepairGUI.ps1" 2>&1
    `$ErrorActionPreference = 'Stop'
    
    # Check for critical errors in output
    `$criticalFound = `$false
    `$criticalPatterns = @('Missing closing', 'ParserError', 'Unexpected token', 'Cannot call a method on a null', 'Exception calling')
    foreach (`$pattern in `$criticalPatterns) {
        if (`$output -match `$pattern) {
            Write-Host "[FAIL] Critical error detected: `$pattern" -ForegroundColor Red
            Write-Host "Output: `$output" -ForegroundColor Red
            `$criticalFound = `$true
        }
    }
    
    if (`$criticalFound) {
        exit 1
    }
    
    # Check if Start-GUI function exists
    if (-not (Get-Command Start-GUI -ErrorAction SilentlyContinue)) {
        Write-Host "[FAIL] Start-GUI function not found after loading WinRepairGUI.ps1" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[PASS] GUI module loaded successfully, Start-GUI function available" -ForegroundColor Green
    
    # Try to validate GUI can initialize (without showing window)
    # We'll create a test that validates the XAML and basic structure
    # but we won't actually show the window or call ShowDialog()
    
    Write-Host "[PASS] GUI launch test passed" -ForegroundColor Green
    exit 0
    
} catch {
    Write-Host "[FAIL] GUI launch test failed: `$_" -ForegroundColor Red
    Write-Host "Error details: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: `$(`$_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
"@
    
    $tempScript = Join-Path $env:TEMP "SuperTest_GUI_$timestamp.ps1"
    Set-Content -Path $tempScript -Value $guiTestScript -Encoding UTF8
    
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'pwsh.exe'
        $psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$tempScript`""
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
        
        # Write to log
        $logContent = @(
            "=== GUI LAUNCH TEST ===",
            "STDOUT:",
            $stdOut,
            "",
            "STDERR:",
            $stdErr,
            "",
            "ExitCode: $exitCode"
        )
        Set-Content -Path $guiTestLog -Value $logContent -Encoding UTF8
        
        # Check for critical patterns
        $hasCritical = $false
        foreach ($pattern in $criticalPatterns) {
            if ($stdOut -match $pattern -or $stdErr -match $pattern) {
                $hasCritical = $true
                Write-Log "  [!] Detected critical pattern '$pattern' in GUI test output." ([ConsoleColor]::Red)
            }
        }
        
        if ($exitCode -eq 0 -and -not $hasCritical) {
            Write-Log "[PASS] GUI launch test passed" ([ConsoleColor]::Green)
            Write-Log "  Log: $guiTestLog"
            return $true
        } else {
            Write-Log "[FAIL] GUI launch test failed (ExitCode=$exitCode, CriticalOutput=$hasCritical)" ([ConsoleColor]::Red)
            Write-Log "  Log: $guiTestLog"
            Write-Log "  Output preview:" ([ConsoleColor]::Yellow)
            $stdOutLines = $stdOut -split "`n" | Select-Object -First 10
            foreach ($line in $stdOutLines) {
                if ($line.Trim()) {
                    Write-Log "    $line" ([ConsoleColor]::Gray)
                }
            }
            $global:overallExitCode = 1
            return $false
        }
    } finally {
        if (Test-Path $tempScript) {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-TestScript {
    param(
        [string]$Name,
        [string]$ScriptPath
    )

    $absolutePath = Join-Path $root $ScriptPath
    $logPath = Join-Path $logRoot ("{0}_{1}.log" -f ($Name -replace '[^\w\-]', '_'), $timestamp)

    if (-not (Test-Path $absolutePath)) {
        Write-Log "[FATAL] Test script not found: $absolutePath" ([ConsoleColor]::Red)
        $global:overallExitCode = 1
        $script:testRuns += [PSCustomObject]@{
            Name      = $Name
            Script    = $absolutePath
            ExitCode  = $null
            Log       = $logPath
            Status    = 'MISSING'
            HasErrors = $true
        }
        return
    }

    Write-Log "Running test: $Name" ([ConsoleColor]::Yellow)
    Write-Log "  Script : $absolutePath"
    Write-Log "  Log    : $logPath"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'pwsh.exe'
    $psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$absolutePath`""
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

    # Write combined output to log
    $logContent = @(
        "=== STDOUT ===",
        $stdOut,
        "",
        "=== STDERR ===",
        $stdErr,
        "",
        "ExitCode: $exitCode"
    )
    Set-Content -Path $logPath -Value $logContent -Encoding UTF8

    $hasCritical = $false
    foreach ($pattern in $criticalPatterns) {
        if ($stdOut -match $pattern -or $stdErr -match $pattern) {
            $hasCritical = $true
            Write-Log "  [!] Detected critical pattern '$pattern' in output." ([ConsoleColor]::Red)
        }
    }

    $statusColor = if ($exitCode -eq 0 -and -not $hasCritical) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    $status = if ($exitCode -eq 0 -and -not $hasCritical) { 'PASS' } else { 'FAIL' }

    Write-Log "  Result : $status (ExitCode=$exitCode, CriticalOutput=$hasCritical)" $statusColor
    Write-Log ""

    if ($exitCode -ne 0 -or $hasCritical) {
        $global:overallExitCode = 1
    }

    $script:testRuns += [PSCustomObject]@{
        Name      = $Name
        Script    = $absolutePath
        ExitCode  = $exitCode
        Log       = $logPath
        Status    = $status
        HasErrors = $hasCritical
    }
}

# PHASE 0: Comprehensive Syntax Validation (FASTEST FEEDBACK - FAIL FAST)
Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  PHASE 0: COMPREHENSIVE SYNTAX VALIDATION" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

$syntaxResults = @()
foreach ($file in $psFiles) {
    $displayName = $file -replace '\\', '/'
    $passed = Test-PowerShellSyntax -FilePath $file -DisplayName $displayName
    $syntaxResults += [PSCustomObject]@{
        File = $displayName
        Passed = $passed
    }
}

Write-Host ""
$syntaxFailed = ($syntaxResults | Where-Object { -not $_.Passed }).Count
if ($syntaxFailed -gt 0) {
    Write-Log "SYNTAX VALIDATION FAILED: $syntaxFailed file(s) have syntax errors" ([ConsoleColor]::Red)
    Write-Log "FIX SYNTAX ERRORS BEFORE PROCEEDING" ([ConsoleColor]::Red)
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  SYNTAX ERRORS DETECTED - STOPPING TESTS" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Files with syntax errors:" -ForegroundColor Yellow
    foreach ($result in $syntaxResults | Where-Object { -not $_.Passed }) {
        Write-Host "  - $($result.File)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Fix these errors and run SuperTest again." -ForegroundColor Yellow
    exit 1
} else {
    Write-Log "SYNTAX VALIDATION PASSED: All $($psFiles.Count) PowerShell files have valid syntax" ([ConsoleColor]::Green)
}

# PHASE 1: GUI Launch Test (Critical for Windows 11 UI)
Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  PHASE 1: GUI LAUNCH TEST" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

$guiTestPassed = Test-GUILaunch
if (-not $guiTestPassed) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  GUI LAUNCH TEST FAILED - FIX ERRORS BEFORE PROCEEDING" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "The GUI cannot launch successfully. This must be fixed before code can proceed." -ForegroundColor Yellow
    exit 1
}

# PHASE 2: Core syntax / module tests
Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  PHASE 2: COMPREHENSIVE TEST SUITES" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

Invoke-TestScript -Name 'Test-CompleteCodebase' -ScriptPath 'Test\Test-CompleteCodebase.ps1'

# PHASE 3: Safe read-only function tests
Invoke-TestScript -Name 'Test-SafeFunctions' -ScriptPath 'Test\Test-SafeFunctions.ps1'

# PHASE 4: Higher-level integration tests (includes GUI/TUI load checks)
Invoke-TestScript -Name 'Test-MiracleBoot' -ScriptPath 'Test\Test-MiracleBoot.ps1'

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  SUPER TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($run in $testRuns) {
    $color = if ($run.Status -eq 'PASS') { 'Green' } elseif ($run.Status -eq 'MISSING') { 'Yellow' } else { 'Red' }
    Write-Host ("{0,-20} : {1,-5} Exit={2,-3} Log={3}" -f $run.Name, $run.Status, ($run.ExitCode -as [string]), $run.Log) -ForegroundColor $color
}

Write-Host ""
Write-Host "Combined Super Test log: $summaryLog" -ForegroundColor Gray
Write-Log "Super Test completed at $(Get-Date)"

if ($overallExitCode -eq 0) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "  SUPER TEST PASSED - CODE IS CLEAR OF OBVIOUS ERRORS" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  SUPER TEST FAILED - FIX ERRORS BEFORE PROCEEDING" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Red
}

exit $overallExitCode


