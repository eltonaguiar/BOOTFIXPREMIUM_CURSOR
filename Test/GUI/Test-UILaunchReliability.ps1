# Test-UILaunchReliability.ps1
# BRUTAL HONESTY TEST - Proves whether UI can launch reliably on Windows 11

Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }
$logFile = Join-Path $env:TEMP "UI_Launch_Analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Write-Analysis {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::White)
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logFile -Value $Message
}

Write-Analysis "=" * 80 Cyan
Write-Analysis "UI LAUNCH RELIABILITY ANALYSIS - BRUTAL HONESTY TEST" Cyan
Write-Analysis "=" * 80 Cyan
Write-Analysis ""

$failures = @()
$warnings = @()

# ============================================================================
# TASK 1: EXECUTION CONTEXT VALIDATION
# ============================================================================
Write-Analysis "TASK 1: EXECUTION CONTEXT VALIDATION" Yellow
Write-Analysis ""

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$systemDrive = $env:SystemDrive
$hasWindows = Test-Path "$systemDrive\Windows"

Write-Analysis "Current Context:" Gray
Write-Analysis "  Running as Admin: $isAdmin" $(if ($isAdmin) { "Green" } else { "Yellow" })
Write-Analysis "  SystemDrive: $systemDrive" Gray
Write-Analysis "  Windows directory exists: $hasWindows" $(if ($hasWindows) { "Green" } else { "Red" })
Write-Analysis ""

if ($systemDrive -eq 'X:') {
    Write-Analysis "[FAIL] Running in WinRE/WinPE - UI WILL NOT LAUNCH" Red
    $failures += "SystemDrive is X: (WinRE/WinPE) - UI not supported"
} elseif (-not $hasWindows) {
    Write-Analysis "[FAIL] Windows directory not found - UI WILL NOT LAUNCH" Red
    $failures += "Windows directory missing - not a valid Windows environment"
} else {
    Write-Analysis "[OK] FullOS environment detected" Green
}

# Check PowerShell version and threading
$psVersion = $PSVersionTable.PSVersion
$threadingModel = [System.Threading.Thread]::CurrentThread.GetApartmentState()

Write-Analysis "PowerShell Version: $psVersion" Gray
Write-Analysis "Threading Model: $threadingModel" $(if ($threadingModel -eq 'STA') { "Green" } else { "Red" })

if ($threadingModel -ne 'STA') {
    Write-Analysis "[CRITICAL] NOT RUNNING IN STA THREAD - WPF WILL FAIL" Red
    $failures += "PowerShell not in STA (Single Threaded Apartment) mode - WPF requires STA"
}

Write-Analysis ""

# ============================================================================
# TASK 2: PRE-UI FAILURE HUNT
# ============================================================================
Write-Analysis "TASK 2: PRE-UI FAILURE HUNT" Yellow
Write-Analysis ""

cd $scriptRoot

# Analyze MiracleBoot.ps1 line by line
$mbContent = Get-Content "MiracleBoot.ps1" -Raw
$mbLines = $mbContent -split "`r?`n"

Write-Analysis "Analyzing statements BEFORE UI launch..." Gray
Write-Analysis ""

# Check for critical issues
$preUIIssues = @()

# Line 63: ErrorActionPreference = 'Stop' - GOOD
# Line 244: . WinRepairCore.ps1 - CAN THROW, exits with ReadKey (BLOCKS)
if ($mbContent -match '\.\s+"\$PSScriptRoot\\Helper\\WinRepairCore\.ps1"') {
    $preUIIssues += "Line ~244: Loading WinRepairCore.ps1 - CAN THROW, exits with ReadKey (BLOCKS USER)"
}

# Line 290-305: Optional modules - uses Write-Warning, continues (OK)
# Line 327-328: Add-Type PresentationFramework - CAN THROW, falls back to TUI (OK)
# Line 355: . WinRepairGUI.ps1 - CAN THROW, caught by try/catch (OK)
# Line 358: Get-Command Start-GUI - uses SilentlyContinue (RISKY)
if ($mbContent -match 'Get-Command Start-GUI.*SilentlyContinue') {
    $preUIIssues += "Line ~358: Get-Command Start-GUI uses SilentlyContinue - if function missing, will throw at line 375"
}

# Line 375: Start-GUI - NO TRY/CATCH AROUND IT!
if ($mbContent -match 'Start-GUI' -and $mbContent -notmatch 'try\s*\{[^}]*Start-GUI[^}]*\}') {
    $preUIIssues += "Line ~375: Start-GUI called WITHOUT try/catch - if it throws, catch at 379 won't catch it!"
}

foreach ($issue in $preUIIssues) {
    Write-Analysis "[FAIL] $issue" Red
    $failures += $issue
}

Write-Analysis ""

# ============================================================================
# TASK 3: UI LAUNCH GUARANTEE
# ============================================================================
Write-Analysis "TASK 3: UI LAUNCH GUARANTEE" Yellow
Write-Analysis ""

# Check WinRepairGUI.ps1
$guiContent = Get-Content "Helper\WinRepairGUI.ps1" -Raw

# Check for STA enforcement
if ($guiContent -notmatch 'ApartmentState|STA|SingleThreaded') {
    Write-Analysis "[CRITICAL] NO STA THREADING ENFORCEMENT" Red
    $failures += "WinRepairGUI.ps1 does not enforce STA threading - WPF REQUIRES STA"
}

# Check for assembly loading
$hasPresentationFramework = $guiContent -match 'Add-Type.*PresentationFramework'
$hasWindowsBase = $guiContent -match 'Add-Type.*WindowsBase'
$hasSystemWindows = $guiContent -match 'Add-Type.*System\.Windows'

Write-Analysis "Assembly Loading:" Gray
Write-Analysis "  PresentationFramework: $(if ($hasPresentationFramework) { 'YES' } else { 'NO' })" $(if ($hasPresentationFramework) { "Green" } else { "Red" })
Write-Analysis "  WindowsBase: $(if ($hasWindowsBase) { 'YES' } else { 'NO (may be auto-loaded)' })" Gray
Write-Analysis "  System.Windows.Forms: $(if ($hasSystemWindows) { 'YES' } else { 'NO' })" $(if ($hasSystemWindows) { "Green" } else { "Yellow" })

# Check where Add-Type is called
if ($guiContent -match 'Add-Type.*PresentationFramework' -and $guiContent -notmatch 'function Start-GUI') {
    Write-Analysis "[WARNING] Add-Type called at MODULE LEVEL (line 91-93)" Yellow
    Write-Analysis "  This executes when script is dot-sourced, not when Start-GUI is called" Yellow
    Write-Analysis "  If it fails, error happens before Start-GUI even runs" Yellow
    $warnings += "Add-Type at module level - failures happen before Start-GUI"
}

# Check for ShowDialog error handling
if ($guiContent -match 'ShowDialog' -and $guiContent -match 'try.*ShowDialog.*catch') {
    Write-Analysis "[OK] ShowDialog wrapped in try/catch" Green
} else {
    Write-Analysis "[FAIL] ShowDialog NOT properly wrapped" Red
    $failures += "ShowDialog call not properly error-handled"
}

Write-Analysis ""

# ============================================================================
# TASK 4: FALLBACK BEHAVIOR
# ============================================================================
Write-Analysis "TASK 4: FALLBACK BEHAVIOR" Yellow
Write-Analysis ""

# Check if fallback shows clear message
if ($mbContent -match 'GUI MODE FAILED.*FALLING BACK TO TUI') {
    Write-Analysis "[OK] Clear fallback message exists" Green
} else {
    Write-Analysis "[FAIL] No clear fallback message" Red
    $failures += "No clear message when GUI fails"
}

# Check if fallback uses ReadKey (blocks)
if ($mbContent -match 'ReadKey.*NoEcho.*IncludeKeyDown') {
    Write-Analysis "[WARNING] Fallback uses ReadKey - BLOCKS execution" Yellow
    $warnings += "Fallback blocks with ReadKey - user must press key"
}

# Check if TUI is guaranteed to exist
if (Test-Path "Helper\WinRepairTUI.ps1") {
    Write-Analysis "[OK] TUI fallback exists" Green
} else {
    Write-Analysis "[FAIL] TUI fallback missing" Red
    $failures += "WinRepairTUI.ps1 not found - no fallback available"
}

Write-Analysis ""

# ============================================================================
# TASK 5: FALSE "PRODUCTION READY" DETECTION
# ============================================================================
Write-Analysis "TASK 5: FALSE PRODUCTION READY DETECTION" Yellow
Write-Analysis ""

$antiPatterns = @()

# Check for swallowed errors
if ($mbContent -match 'catch\s*\{\s*\}') {
    $antiPatterns += "Empty catch blocks found - errors are being swallowed"
}

# Check for SilentlyContinue
$silentlyContinueCount = ([regex]::Matches($mbContent, 'SilentlyContinue')).Count
if ($silentlyContinueCount -gt 0) {
    Write-Analysis "[WARNING] Found $silentlyContinueCount instances of SilentlyContinue" Yellow
    $warnings += "$silentlyContinueCount SilentlyContinue usages - may hide errors"
}

# Check for Write-Host instead of logging
$writeHostCount = ([regex]::Matches($mbContent, 'Write-Host')).Count
$writeLogCount = ([regex]::Matches($mbContent, 'Write-Log|Add-Content.*log|Out-File.*log')).Count
Write-Analysis "Write-Host calls: $writeHostCount" Gray
Write-Analysis "Logging calls: $writeLogCount" Gray
if ($writeHostCount -gt $writeLogCount * 2) {
    $antiPatterns += "Excessive Write-Host usage - not proper logging"
}

foreach ($pattern in $antiPatterns) {
    Write-Analysis "[WARNING] $pattern" Yellow
    $warnings += $pattern
}

Write-Analysis ""

# ============================================================================
# TASK 6: FORCE-FAIL TESTS
# ============================================================================
Write-Analysis "TASK 6: FORCE-FAIL TESTS" Yellow
Write-Analysis ""

Write-Analysis "Testing failure scenarios..." Gray

# Test 1: Missing WPF assembly (simulated)
Write-Analysis "Test 1: Missing PresentationFramework assembly" Gray
try {
    Add-Type -AssemblyName "NonExistentAssembly12345" -ErrorAction Stop
    Write-Analysis "  [FAIL] Should have thrown" Red
} catch {
    Write-Analysis "  [OK] Correctly throws when assembly missing" Green
}

# Test 2: Non-STA thread (check current)
Write-Analysis "Test 2: Threading model check" Gray
if ($threadingModel -ne 'STA') {
    Write-Analysis "  [FAIL] Not in STA mode - WPF will fail" Red
    $failures += "Current PowerShell session not in STA mode"
} else {
    Write-Analysis "  [OK] Running in STA mode" Green
}

# Test 3: Constrained environment
Write-Analysis "Test 3: Constrained execution policy" Gray
$currentPolicy = Get-ExecutionPolicy -Scope Process
Write-Analysis "  Current policy: $currentPolicy" Gray
if ($currentPolicy -eq 'Restricted') {
    Write-Analysis "  [FAIL] Execution policy is Restricted" Red
    $failures += "Execution policy Restricted - scripts won't run"
} else {
    Write-Analysis "  [OK] Execution policy allows scripts" Green
}

Write-Analysis ""

# ============================================================================
# TASK 7: ACTUAL UI LAUNCH TEST
# ============================================================================
Write-Analysis "TASK 7: ACTUAL UI LAUNCH TEST" Yellow
Write-Analysis ""

Write-Analysis "Attempting to actually launch UI..." Cyan
Write-Analysis ""

# Try to load modules
try {
    . "Helper\WinRepairCore.ps1" -ErrorAction Stop
    Write-Analysis "[OK] WinRepairCore.ps1 loaded" Green
} catch {
    Write-Analysis "[FAIL] WinRepairCore.ps1 failed to load: $_" Red
    $failures += "WinRepairCore.ps1 load failed: $_"
}

# Try to load WPF
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Write-Analysis "[OK] WPF assemblies loaded" Green
} catch {
    Write-Analysis "[FAIL] WPF assemblies failed: $_" Red
    $failures += "WPF assembly load failed: $_"
}

# Try to load GUI module
try {
    . "Helper\WinRepairGUI.ps1" -ErrorAction Stop
    Write-Analysis "[OK] WinRepairGUI.ps1 loaded" Green
} catch {
    Write-Analysis "[FAIL] WinRepairGUI.ps1 failed: $_" Red
    $failures += "WinRepairGUI.ps1 load failed: $_"
}

# Check if Start-GUI exists
if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
    Write-Analysis "[OK] Start-GUI function found" Green
    
    # Actually try to call it (with timeout)
    Write-Analysis "Calling Start-GUI (5 second timeout)..." Yellow
    $job = Start-Job -ScriptBlock {
        param($scriptRoot)
        Set-Location $scriptRoot
        Set-ExecutionPolicy Bypass -Scope Process -Force
        . "Helper\WinRepairCore.ps1"
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName System.Windows.Forms
        . "Helper\WinRepairGUI.ps1"
        Start-GUI
    } -ArgumentList $scriptRoot
    
    $job | Wait-Job -Timeout 5 | Out-Null
    
    if ($job.State -eq 'Running') {
        Write-Analysis "[SUCCESS] GUI launched (job still running)" Green
        Stop-Job $job
        Remove-Job $job -Force
    } else {
        $result = Receive-Job $job
        if ($result) {
            Write-Analysis "[FAIL] GUI launch produced output/errors:" Red
            $result | ForEach-Object { Write-Analysis "  $_" Red }
            $failures += "GUI launch failed with output"
        } else {
            Write-Analysis "[WARNING] GUI job completed immediately (may have failed silently)" Yellow
            $warnings += "GUI job completed too quickly - may have failed"
        }
        Remove-Job $job -Force
    }
} else {
    Write-Analysis "[FAIL] Start-GUI function not found" Red
    $failures += "Start-GUI function not available"
}

Write-Analysis ""

# ============================================================================
# FINAL VERDICT
# ============================================================================
Write-Analysis "=" * 80 Cyan
Write-Analysis "FINAL VERDICT" Cyan
Write-Analysis "=" * 80 Cyan
Write-Analysis ""

if ($failures.Count -eq 0) {
    Write-Analysis "UI WILL LAUNCH RELIABLY" Green
    Write-Analysis ""
    Write-Analysis "All critical checks passed." Green
} else {
    Write-Analysis "UI WILL NOT LAUNCH RELIABLY" Red
    Write-Analysis ""
    Write-Analysis "CRITICAL FAILURES:" Red
    $failures | ForEach-Object { Write-Analysis "  - $_" Red }
}

if ($warnings.Count -gt 0) {
    Write-Analysis ""
    Write-Analysis "WARNINGS:" Yellow
    $warnings | ForEach-Object { Write-Analysis "  - $_" Yellow }
}

Write-Analysis ""
Write-Analysis "Analysis log saved to: $logFile" Gray
Write-Analysis ""

if ($failures.Count -gt 0) {
    exit 1
} else {
    exit 0
}

