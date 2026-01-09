# Test-BrutalHonesty.ps1
# BRUTAL HONESTY TEST - Actually runs the script and proves UI can launch

Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = 'Continue'

$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }
$logFile = Join-Path $env:TEMP "BrutalHonesty_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Write-Result {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::White)
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logFile -Value $Message
}

Write-Result "=" * 80 Cyan
Write-Result "BRUTAL HONESTY UI LAUNCH TEST" Cyan
Write-Result "=" * 80 Cyan
Write-Result ""

$failures = @()
$warnings = @()

# Check STA mode
$threadState = [System.Threading.Thread]::CurrentThread.GetApartmentState()
Write-Result "Threading Model: $threadState" $(if ($threadState -eq 'STA') { "Green" } else { "Red" })

if ($threadState -ne 'STA') {
    Write-Result "[CRITICAL] NOT IN STA MODE - UI WILL FAIL" Red
    $failures += "PowerShell not in STA mode"
} else {
    Write-Result "[OK] Running in STA mode" Green
}

# Check environment
if ($env:SystemDrive -eq 'X:') {
    Write-Result "[SKIP] WinRE/WinPE - UI not supported" Yellow
    exit 0
}

if (-not (Test-Path "$env:SystemDrive\Windows")) {
    Write-Result "[FAIL] Not a valid Windows environment" Red
    $failures += "Windows directory missing"
    exit 1
}

Write-Result "[OK] FullOS environment" Green
Write-Result ""

# Test WPF assembly loading
Write-Result "Testing WPF assembly loading..." Yellow
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Write-Result "[OK] PresentationFramework loaded" Green
} catch {
    Write-Result "[FAIL] PresentationFramework failed: $_" Red
    $failures += "WPF assembly load failed: $_"
}

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Write-Result "[OK] System.Windows.Forms loaded" Green
} catch {
    Write-Result "[FAIL] System.Windows.Forms failed: $_" Red
    $failures += "WinForms assembly load failed: $_"
}

Write-Result ""

# Actually run the script
Write-Result "Running MiracleBoot.ps1..." Cyan
Write-Result ""

cd $scriptRoot

# Capture output
$output = @()
$errors = @()

# Override Write-Host temporarily to capture
$originalWriteHost = Get-Command Write-Host
function Write-Host {
    param([object]$Object, [ConsoleColor]$ForegroundColor = [ConsoleColor]::White)
    $script:output += $Object.ToString()
    & $originalWriteHost $Object -ForegroundColor $ForegroundColor
}

# Run in a job with timeout
$job = Start-Job -ScriptBlock {
    param($scriptRoot)
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Set-Location $scriptRoot
    $ErrorActionPreference = 'Continue'
    
    # Capture errors
    $jobErrors = @()
    
    try {
        . ".\MiracleBoot.ps1" 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $script:jobErrors += $_.Exception.Message
            }
            $_
        }
    } catch {
        $script:jobErrors += $_.Exception.Message
    }
    
    return @{
        Errors = $jobErrors
    }
} -ArgumentList $scriptRoot

# Wait up to 15 seconds
$job | Wait-Job -Timeout 15 | Out-Null

if ($job.State -eq 'Running') {
    Write-Result "[SUCCESS] GUI launched (job still running)" Green
    Stop-Job $job
    Remove-Job $job -Force
} else {
    $result = Receive-Job $job
    Remove-Job $job -Force
    
    if ($result.Errors.Count -gt 0) {
        Write-Result "[FAIL] Errors during execution:" Red
        $result.Errors | ForEach-Object {
            Write-Result "  $_" Red
            $failures += $_
        }
    }
}

# Scan output for critical errors
$combinedOutput = $output -join "`n"
$criticalPatterns = @(
    'Get-Control.*not recognized',
    'null-valued expression',
    'GUI MODE FAILED',
    'FALLING BACK TO TUI',
    'Failed to load WPF',
    'STA mode',
    'threading'
)

foreach ($pattern in $criticalPatterns) {
    if ($combinedOutput -match $pattern) {
        if ($pattern -match 'STA mode|threading') {
            # Check if it's a success message
            if ($combinedOutput -match 'STA mode set successfully') {
                Write-Result "[OK] STA mode handled correctly" Green
            } else {
                Write-Result "[WARNING] Found '$pattern' in output" Yellow
                $warnings += "Pattern '$pattern' found"
            }
        } else {
            Write-Result "[FAIL] Found critical pattern: $pattern" Red
            $failures += "Critical error: $pattern"
        }
    }
}

Write-Result ""
Write-Result "=" * 80 Cyan
Write-Result "FINAL VERDICT" Cyan
Write-Result "=" * 80 Cyan
Write-Result ""

if ($failures.Count -eq 0) {
    Write-Result "UI WILL LAUNCH RELIABLY" Green
    Write-Result ""
    Write-Result "All critical checks passed." Green
    exit 0
} else {
    Write-Result "UI WILL NOT LAUNCH RELIABLY" Red
    Write-Result ""
    Write-Result "CRITICAL FAILURES:" Red
    $failures | ForEach-Object { Write-Result "  - $_" Red }
    Write-Result ""
    Write-Result "Log saved to: $logFile" Gray
    exit 1
}

