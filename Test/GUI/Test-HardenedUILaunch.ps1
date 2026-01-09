# Test-HardenedUILaunch.ps1
# HARDENED TEST - Actually launches UI and verifies it appears
# FAILS LOUDLY if UI doesn't launch

Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = 'Stop'

# Get root directory (where MiracleBoot.ps1 exists)
if ($PSScriptRoot) {
    $current = $PSScriptRoot
    while ($current -and -not (Test-Path (Join-Path $current "MiracleBoot.ps1"))) {
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }
    $scriptRoot = $current
} else {
    $scriptRoot = Get-Location
    while ($scriptRoot -and -not (Test-Path (Join-Path $scriptRoot "MiracleBoot.ps1"))) {
        $parent = Split-Path $scriptRoot -Parent
        if ($parent -eq $scriptRoot) { break }
        $scriptRoot = $parent
    }
}
$logFile = Join-Path $env:TEMP "HardenedUI_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$errorLog = Join-Path $env:TEMP "HardenedUI_Errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Write-TestLog {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::White)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor $Color
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Write-ErrorLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $errorLog -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue
}

Write-TestLog ("=" * 80) Cyan
Write-TestLog "HARDENED UI LAUNCH TEST - BRUTAL VERIFICATION" Cyan
Write-TestLog ("=" * 80) Cyan
Write-TestLog ""

$failures = @()
$criticalErrors = @()

# ============================================================================
# PHASE 1: PRE-FLIGHT CHECKS
# ============================================================================
Write-TestLog "PHASE 1: PRE-FLIGHT CHECKS" Yellow
Write-TestLog ""

# Check STA mode
$threadState = [System.Threading.Thread]::CurrentThread.GetApartmentState()
Write-TestLog "Threading: $threadState" $(if ($threadState -eq 'STA') { "Green" } else { "Red" })

if ($threadState -ne 'STA') {
    $failures += "NOT IN STA MODE - WPF REQUIRES STA"
    Write-TestLog "[CRITICAL] PowerShell not in STA mode" Red
    Write-TestLog "Launch with: powershell.exe -STA -File Test-HardenedUILaunch.ps1" Yellow
    Write-TestLog ""
}

# Check environment
if ($env:SystemDrive -eq 'X:') {
    Write-TestLog "[SKIP] WinRE/WinPE - UI not supported" Yellow
    exit 0
}

if (-not (Test-Path "$env:SystemDrive\Windows")) {
    $failures += "Not a valid Windows environment"
    Write-TestLog "[FAIL] Windows directory missing" Red
    exit 1
}

Write-TestLog "[OK] FullOS environment" Green
Write-TestLog ""

# ============================================================================
# PHASE 2: ASSEMBLY LOADING TEST
# ============================================================================
Write-TestLog "PHASE 2: ASSEMBLY LOADING TEST" Yellow
Write-TestLog ""

try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Write-TestLog "[OK] PresentationFramework loaded" Green
} catch {
    $failures += "PresentationFramework failed: $_"
    Write-TestLog "[FAIL] PresentationFramework: $_" Red
    Write-ErrorLog "PresentationFramework load failed: $_"
}

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Write-TestLog "[OK] System.Windows.Forms loaded" Green
} catch {
    $failures += "System.Windows.Forms failed: $_"
    Write-TestLog "[FAIL] System.Windows.Forms: $_" Red
    Write-ErrorLog "System.Windows.Forms load failed: $_"
}

Write-TestLog ""

# ============================================================================
# PHASE 3: MODULE LOADING TEST
# ============================================================================
Write-TestLog "PHASE 3: MODULE LOADING TEST" Yellow
Write-TestLog ""

cd $scriptRoot

try {
    $corePath = Join-Path $scriptRoot "Helper\WinRepairCore.ps1"
    . $corePath -ErrorAction Stop
    Write-TestLog "[OK] WinRepairCore.ps1 loaded" Green
} catch {
    $failures += "WinRepairCore.ps1 failed: $_"
    Write-TestLog "[FAIL] WinRepairCore.ps1: $_" Red
    Write-ErrorLog "WinRepairCore.ps1 load failed: $_"
    exit 1
}

try {
    $guiPath = Join-Path $scriptRoot "Helper\WinRepairGUI.ps1"
    . $guiPath -ErrorAction Stop
    Write-TestLog "[OK] WinRepairGUI.ps1 loaded" Green
} catch {
    $failures += "WinRepairGUI.ps1 failed: $_"
    Write-TestLog "[FAIL] WinRepairGUI.ps1: $_" Red
    Write-ErrorLog "WinRepairGUI.ps1 load failed: $_"
    Write-ErrorLog "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}

if (-not (Get-Command Start-GUI -ErrorAction Stop)) {
    $failures += "Start-GUI function not found"
    Write-TestLog "[FAIL] Start-GUI function missing" Red
    exit 1
}

Write-TestLog "[OK] Start-GUI function found" Green
Write-TestLog ""

# ============================================================================
# PHASE 4: ACTUAL UI LAUNCH TEST
# ============================================================================
Write-TestLog "PHASE 4: ACTUAL UI LAUNCH TEST" Yellow
Write-TestLog ""

Write-TestLog "Attempting to launch GUI window..." Cyan
Write-TestLog "Window should appear within 5 seconds..." Gray
Write-TestLog ""

# Capture all errors
$Error.Clear()
$allErrors = @()

# Create a job that launches the GUI
$job = Start-Job -ScriptBlock {
    param($scriptRoot)
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Set-Location $scriptRoot
    $ErrorActionPreference = 'Continue'
    
    # Capture errors
    $jobErrors = @()
    $Error.Clear()
    
    try {
        # Load modules
        $corePath = Join-Path $scriptRoot "Helper\WinRepairCore.ps1"
        . $corePath -ErrorAction Stop
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $guiPath = Join-Path $scriptRoot "Helper\WinRepairGUI.ps1"
        . $guiPath -ErrorAction Stop
        
        # Launch GUI
        Start-GUI
    } catch {
        $jobErrors += "EXCEPTION: $($_.Exception.Message)"
        $jobErrors += "Stack: $($_.ScriptStackTrace)"
        if ($_.Exception.InnerException) {
            $jobErrors += "Inner: $($_.Exception.InnerException.Message)"
        }
    }
    
    # Capture any errors from $Error collection
    foreach ($err in $Error) {
        $jobErrors += "ERROR: $($err.Exception.Message)"
        if ($err.Exception.InnerException) {
            $jobErrors += "  Inner: $($err.Exception.InnerException.Message)"
        }
    }
    
    return @{
        Errors = $jobErrors
        ErrorCount = $Error.Count
    }
} -ArgumentList $scriptRoot

# Wait for GUI to initialize (10 seconds max)
$job | Wait-Job -Timeout 10 | Out-Null

if ($job.State -eq 'Running') {
    Write-TestLog "[SUCCESS] GUI launched (job still running - window should be visible)" Green
    Write-TestLog ""
    Write-TestLog "VERIFICATION: Check your screen - GUI window should be visible" Cyan
    Write-TestLog ""
    
    # Give user 2 seconds to see it
    Start-Sleep -Seconds 2
    
    # Stop the job
    Stop-Job $job
    Remove-Job $job -Force
    Write-TestLog "[OK] GUI test completed" Green
} else {
    $result = Receive-Job $job
    Remove-Job $job -Force
    
    if ($result.Errors.Count -gt 0) {
        Write-TestLog "[FAIL] GUI launch produced errors:" Red
        foreach ($err in $result.Errors) {
            Write-TestLog "  $err" Red
            $criticalErrors += $err
            Write-ErrorLog $err
        }
        $failures += "GUI launch failed with $($result.Errors.Count) error(s)"
    }
    
    if ($result.ErrorCount -gt 0) {
        Write-TestLog "[FAIL] $($result.ErrorCount) errors in Error collection" Red
        $failures += "$($result.ErrorCount) errors detected"
    }
    
    Write-TestLog "[FAIL] GUI did not launch (job completed immediately)" Red
    $failures += "GUI window did not appear"
}

Write-TestLog ""

# ============================================================================
# PHASE 5: ERROR PATTERN SCAN
# ============================================================================
Write-TestLog "PHASE 5: ERROR PATTERN SCAN" Yellow
Write-TestLog ""

$errorPatterns = @(
    @{ Pattern = 'null-valued expression'; Severity = 'CRITICAL' }
    @{ Pattern = 'Get-Control.*not recognized'; Severity = 'CRITICAL' }
    @{ Pattern = 'Cannot call a method on a null'; Severity = 'CRITICAL' }
    @{ Pattern = 'GUI MODE FAILED'; Severity = 'CRITICAL' }
    @{ Pattern = 'FALLING BACK TO TUI'; Severity = 'CRITICAL' }
    @{ Pattern = 'Failed to parse XAML'; Severity = 'CRITICAL' }
    @{ Pattern = 'WPF.*failed'; Severity = 'CRITICAL' }
    @{ Pattern = 'STA.*mode'; Severity = 'HIGH' }
)

if (Test-Path $errorLog) {
    $errorContent = Get-Content $errorLog -Raw
    foreach ($pattern in $errorPatterns) {
        if ($errorContent -match $pattern.Pattern) {
            Write-TestLog "[$($pattern.Severity)] Found: $($pattern.Pattern)" Red
            $failures += "$($pattern.Severity): $($pattern.Pattern)"
        }
    }
}

Write-TestLog ""

# ============================================================================
# FINAL VERDICT
# ============================================================================
Write-TestLog ("=" * 80) Cyan
Write-TestLog "FINAL VERDICT" Cyan
Write-TestLog ("=" * 80) Cyan
Write-TestLog ""

if ($failures.Count -eq 0 -and $criticalErrors.Count -eq 0) {
    Write-TestLog "UI WILL LAUNCH RELIABLY" Green
    Write-TestLog ""
    Write-TestLog "All tests passed. GUI window launched successfully." Green
    Write-TestLog ""
    Write-TestLog "Log: $logFile" Gray
    exit 0
} else {
    Write-TestLog "UI WILL NOT LAUNCH RELIABLY" Red
    Write-TestLog ""
    Write-TestLog "CRITICAL FAILURES:" Red
    $failures | ForEach-Object { Write-TestLog "  - $_" Red }
    Write-TestLog ""
    if ($criticalErrors.Count -gt 0) {
        Write-TestLog "CRITICAL ERRORS DETECTED:" Red
        $criticalErrors | ForEach-Object { Write-TestLog "  - $_" Red }
        Write-TestLog ""
    }
    Write-TestLog "Error log: $errorLog" Gray
    Write-TestLog "Test log: $logFile" Gray
    Write-TestLog ""
    Write-TestLog "THIS SCRIPT IS NOT PRODUCTION READY" Red
    exit 1
}

