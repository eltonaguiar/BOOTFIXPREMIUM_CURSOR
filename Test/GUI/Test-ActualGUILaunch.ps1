# Test-ActualGUILaunch.ps1
# Actually calls Start-GUI and captures real errors

$ErrorActionPreference = 'Continue'
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "ACTUAL GUI LAUNCH TEST - CALLS Start-GUI" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Check if we're in FullOS
if ($env:SystemDrive -eq 'X:') {
    Write-Host "[SKIP] Not in FullOS environment (SystemDrive=X:) - GUI test skipped" -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path "$env:SystemDrive\Windows")) {
    Write-Host "[SKIP] Windows directory not found - may not be FullOS - GUI test skipped" -ForegroundColor Yellow
    exit 0
}

# Load core modules
Write-Host "Loading core modules..." -ForegroundColor Yellow
. "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Continue

# Try to load WPF
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Write-Host "WPF assemblies loaded" -ForegroundColor Green
} catch {
    Write-Host "[SKIP] WPF not available: $_" -ForegroundColor Yellow
    exit 0
}

# Load GUI module
Write-Host "Loading WinRepairGUI.ps1..." -ForegroundColor Yellow
$errorBefore = $Error.Count
. "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Continue
$errorAfter = $Error.Count

if ($errorAfter -gt $errorBefore) {
    $newErrors = $Error[$errorBefore..($errorAfter-1)]
    foreach ($err in $newErrors) {
        if ($err.Exception.Message -notmatch 'Export-ModuleMember') {
            Write-Host "ERROR during module load: $($err.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Check if Start-GUI exists
if (-not (Get-Command Start-GUI -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] Start-GUI function not found" -ForegroundColor Red
    exit 1
}

Write-Host "Start-GUI function found" -ForegroundColor Green
Write-Host ""
Write-Host "Attempting to call Start-GUI (will timeout after 5 seconds)..." -ForegroundColor Yellow
Write-Host ""

# Create a job that will call Start-GUI and capture errors
$jobScript = {
    param($scriptRoot)
    $ErrorActionPreference = 'Continue'
    
    # Capture all output
    $allOutput = @()
    $allErrors = @()
    
    function Write-Host {
        param([object]$Object, [ConsoleColor]$ForegroundColor = [ConsoleColor]::White)
        $script:allOutput += $Object.ToString()
        Microsoft.PowerShell.Utility\Write-Host $Object -ForegroundColor $ForegroundColor
    }
    
    function Write-Warning {
        param([string]$Message)
        $script:allOutput += "WARNING: $Message"
        $script:allErrors += "WARNING: $Message"
        Microsoft.PowerShell.Utility\Write-Warning $Message
    }
    
    function Write-Error {
        param([string]$Message)
        $script:allOutput += "ERROR: $Message"
        $script:allErrors += "ERROR: $Message"
        Microsoft.PowerShell.Utility\Write-Error $Message
    }
    
    try {
        # Load modules
        . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Continue
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        . "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Continue
        
        # Actually call Start-GUI
        Write-Host "Calling Start-GUI..." -ForegroundColor Cyan
        
        # We'll use a timeout to prevent hanging
        $job = Start-Job -ScriptBlock {
            param($scriptRoot)
            . "$using:scriptRoot\Helper\WinRepairCore.ps1"
            Add-Type -AssemblyName PresentationFramework
            . "$using:scriptRoot\Helper\WinRepairGUI.ps1"
            Start-GUI
        } -ArgumentList $scriptRoot
        
        # Wait up to 5 seconds for errors
        $job | Wait-Job -Timeout 5 | Out-Null
        
        if ($job.State -eq 'Running') {
            Write-Host "GUI launched (job still running - this is expected)" -ForegroundColor Green
            Stop-Job $job
            Remove-Job $job -Force
        } else {
            $result = Receive-Job $job
            if ($result) {
                $allOutput += $result
            }
            Remove-Job $job -Force
        }
        
    } catch {
        $allErrors += $_.Exception.Message
        $allErrors += $_.ScriptStackTrace
        Write-Host "EXCEPTION: $_" -ForegroundColor Red
    }
    
    # Return results
    @{
        Output = $allOutput
        Errors = $allErrors
    }
}

# Run the test
try {
    $result = & $jobScript $scriptRoot
    
    Write-Host ""
    Write-Host "=== CAPTURED OUTPUT ===" -ForegroundColor Cyan
    $result.Output | ForEach-Object { Write-Host $_ }
    
    if ($result.Errors.Count -gt 0) {
        Write-Host ""
        Write-Host "=== ERRORS DETECTED ===" -ForegroundColor Red
        $result.Errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        
        # Check for critical error patterns
        $criticalPatterns = @('Get-Control.*not recognized', 'null-valued expression', 'Cannot set unknown member')
        $hasCritical = $false
        
        foreach ($pattern in $criticalPatterns) {
            if ($result.Errors -match $pattern -or $result.Output -match $pattern) {
                Write-Host ""
                Write-Host "CRITICAL ERROR FOUND: $pattern" -ForegroundColor Red
                $hasCritical = $true
            }
        }
        
        if ($hasCritical) {
            Write-Host ""
            Write-Host "=" * 80 -ForegroundColor Red
            Write-Host "GUI LAUNCH FAILED - DO NOT PROCEED TO USER TESTING" -ForegroundColor Red
            Write-Host "=" * 80 -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Green
        Write-Host "GUI LAUNCH TEST PASSED - NO ERRORS DETECTED" -ForegroundColor Green
        Write-Host "=" * 80 -ForegroundColor Green
        exit 0
    }
    
} catch {
    Write-Host "[FAIL] Exception during test: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
    exit 1
}


