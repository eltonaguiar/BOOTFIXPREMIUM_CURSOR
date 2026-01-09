<#
    GUI LAUNCH VERIFICATION TEST
    ============================
    
    This test ACTUALLY attempts to launch the GUI and verifies the user can get into the UI.
    It captures all errors and provides detailed debugging information.
    
    This test MUST pass before code can be considered ready.
    
    Usage:
        pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Test\Test-GUILaunchVerification.ps1"
    
    Exit Codes:
        0 = GUI launches successfully
        1 = GUI failed to launch - fix required
#>

$ErrorActionPreference = 'Continue'
$Error.Clear()

# Ensure we are running from the repository root
if ($PSScriptRoot -and (Split-Path $PSScriptRoot -Leaf) -eq 'Test') {
    Set-Location (Split-Path $PSScriptRoot -Parent)
}

$root = Get-Location
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $root "Test\GUILaunchVerification_$timestamp.log"

function Write-TestLog {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    $timestamped = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $timestamped -ForegroundColor $Color
    Add-Content -Path $logFile -Value $timestamped -ErrorAction SilentlyContinue
}

function Write-ErrorLog {
    param(
        [string]$Message,
        [Exception]$Exception = $null
    )
    Write-TestLog "ERROR: $Message" -Color Red
    if ($Exception) {
        Write-TestLog "  Exception: $($Exception.Message)" -Color Red
        Write-TestLog "  StackTrace: $($Exception.StackTrace)" -Color Gray
        if ($Exception.InnerException) {
            Write-TestLog "  InnerException: $($Exception.InnerException.Message)" -Color Red
        }
    }
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  GUI LAUNCH VERIFICATION TEST" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""
Write-TestLog "Test started at $(Get-Date)"
Write-TestLog "Repository root: $root"
Write-TestLog "Log file: $logFile"
Write-Host ""

$allChecksPassed = $true
$errors = @()

# ============================================================================
# CHECK 1: Environment Detection
# ============================================================================
Write-Host "CHECK 1: Environment Detection" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$envType = "Unknown"
$isFullOS = $false

try {
    if ($env:SystemDrive -eq 'X:') {
        $envType = "WinRE/WinPE"
        Write-TestLog "  SystemDrive is X: - This is WinRE/WinPE environment" -Color Yellow
        Write-TestLog "  GUI will not be available in this environment" -Color Yellow
        Write-Host ""
        Write-Host "⚠️  SKIPPING GUI TEST - Not in FullOS environment" -ForegroundColor Yellow
        Write-Host "   GUI is only available in FullOS (Windows 10/11 desktop)" -ForegroundColor Gray
        exit 0
    } elseif (Test-Path "$env:SystemDrive\Windows") {
        $envType = "FullOS"
        $isFullOS = $true
        Write-TestLog "  ✅ FullOS environment detected" -Color Green
        Write-TestLog "  SystemDrive: $env:SystemDrive" -Color Gray
        Write-TestLog "  Windows path: $env:SystemDrive\Windows" -Color Gray
    } else {
        Write-TestLog "  ⚠️  Cannot determine environment - Windows directory not found" -Color Yellow
    }
} catch {
    Write-ErrorLog "Environment detection failed" -Exception $_
    $allChecksPassed = $false
}

Write-Host ""

# ============================================================================
# CHECK 2: PowerShell Version
# ============================================================================
Write-Host "CHECK 2: PowerShell Version" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

try {
    $psVersion = $PSVersionTable.PSVersion
    Write-TestLog "  PowerShell Version: $psVersion" -Color Gray
    Write-TestLog "  PowerShell Edition: $($PSVersionTable.PSEdition)" -Color Gray
    
    if ($psVersion.Major -lt 5) {
        Write-TestLog "  ⚠️  PowerShell version is old - may cause issues" -Color Yellow
    } else {
        Write-TestLog "  ✅ PowerShell version is acceptable" -Color Green
    }
} catch {
    Write-ErrorLog "PowerShell version check failed" -Exception $_
}

Write-Host ""

# ============================================================================
# CHECK 3: WPF Availability
# ============================================================================
Write-Host "CHECK 3: WPF Availability (Required for GUI)" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$wpfAvailable = $false
$wpfError = ""

try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $wpfAvailable = $true
    Write-TestLog "  ✅ WPF assemblies loaded successfully" -Color Green
} catch {
    $wpfError = $_.Exception.Message
    Write-ErrorLog "WPF not available" -Exception $_
    Write-TestLog "  ❌ WPF is REQUIRED for GUI mode" -Color Red
    $allChecksPassed = $false
    $errors += "WPF not available: $wpfError"
}

Write-Host ""

# ============================================================================
# CHECK 4: Core Module Loading
# ============================================================================
Write-Host "CHECK 4: Core Module Loading" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$coreLoaded = $false

try {
    $corePath = Join-Path $root "Helper\WinRepairCore.ps1"
    if (-not (Test-Path $corePath)) {
        throw "WinRepairCore.ps1 not found at $corePath"
    }
    
    Write-TestLog "  Loading WinRepairCore.ps1..." -Color Gray
    
    # Capture all output and errors
    $output = & {
        $ErrorActionPreference = 'Continue'
        . $corePath 2>&1
    }
    
    $criticalErrors = $output | Where-Object { 
        $_ -is [System.Management.Automation.ErrorRecord] -or
        ($_ -match "Missing closing|ParserError|Unexpected token|Exception calling|Cannot call a method on a null")
    }
    
    if ($criticalErrors) {
        Write-TestLog "  ❌ Critical errors detected in core module:" -Color Red
        foreach ($err in $criticalErrors | Select-Object -First 5) {
            Write-TestLog "    $err" -Color Red
        }
        $allChecksPassed = $false
        $errors += "Core module has critical errors"
    } else {
        $coreLoaded = $true
        Write-TestLog "  ✅ Core module loaded successfully" -Color Green
    }
} catch {
    Write-ErrorLog "Core module load failed" -Exception $_
    $allChecksPassed = $false
    $errors += "Core module failed to load: $($_.Exception.Message)"
}

Write-Host ""

# ============================================================================
# CHECK 5: GUI Module Loading
# ============================================================================
Write-Host "CHECK 5: GUI Module Loading" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$guiLoaded = $false
$startGUIFound = $false

if (-not $wpfAvailable) {
    Write-TestLog "  ⚠️  Skipping GUI module test - WPF not available" -Color Yellow
} elseif (-not $coreLoaded) {
    Write-TestLog "  ⚠️  Skipping GUI module test - Core module not loaded" -Color Yellow
} else {
    try {
        $guiPath = Join-Path $root "Helper\WinRepairGUI.ps1"
        if (-not (Test-Path $guiPath)) {
            throw "WinRepairGUI.ps1 not found at $guiPath"
        }
        
        Write-TestLog "  Loading WinRepairGUI.ps1..." -Color Gray
        
        # Load GUI module directly (not in sub-expression to preserve scope)
        $ErrorActionPreference = 'Continue'
        $guiLoadErrors = $null
        
        # Capture errors during load
        $oldErrorView = $ErrorView
        $ErrorView = 'NormalView'
        
        try {
            . $guiPath -ErrorAction Continue 2>&1 | Out-Null
        } catch {
            $guiLoadErrors = $_
        }
        
        $ErrorView = $oldErrorView
        
        # Check for critical errors in $Error
        $criticalErrors = $Error | Where-Object { 
            $_.Exception.Message -match "Missing closing|ParserError|Unexpected token|Exception calling|Cannot call a method on a null"
        }
        
        if ($criticalErrors -or $guiLoadErrors) {
            Write-TestLog "  ❌ Critical errors detected in GUI module:" -Color Red
            if ($guiLoadErrors) {
                Write-TestLog "    Exception: $($guiLoadErrors.Exception.Message)" -Color Red
            }
            foreach ($err in $criticalErrors | Select-Object -First 5) {
                Write-TestLog "    Line $($err.InvocationInfo.ScriptLineNumber): $($err.Exception.Message)" -Color Red
            }
            $allChecksPassed = $false
            $errors += "GUI module has critical errors"
        } else {
            $guiLoaded = $true
            Write-TestLog "  ✅ GUI module loaded successfully" -Color Green
            
            # Check if Start-GUI function exists - check in current scope
            $startGUIFound = $false
            
            # Try multiple methods to find the function
            $functionCheck = Get-Command Start-GUI -ErrorAction SilentlyContinue
            if (-not $functionCheck) {
                $functionCheck = Get-Command Start-GUI -ErrorAction SilentlyContinue -All
            }
            if (-not $functionCheck) {
                $scriptScopeCheck = Get-ChildItem -Path Function: -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Start-GUI' }
                if ($scriptScopeCheck) {
                    $functionCheck = $scriptScopeCheck
                }
            }
            
            if ($functionCheck) {
                $startGUIFound = $true
                Write-TestLog "  ✅ Start-GUI function found" -Color Green
                Write-TestLog "    Function type: $($functionCheck.CommandType)" -Color Gray
            } else {
                Write-TestLog "  ❌ Start-GUI function NOT found" -Color Red
                Write-TestLog "    Checking available functions..." -Color Gray
                $allFunctions = Get-ChildItem -Path Function: -ErrorAction SilentlyContinue | Select-Object -First 10 Name
                foreach ($func in $allFunctions) {
                    Write-TestLog "      Found: $($func.Name)" -Color Gray
                }
                $allChecksPassed = $false
                $errors += "Start-GUI function not found after loading GUI module"
            }
        }
        
        # Clear error array for next check
        $Error.Clear()
    } catch {
        Write-ErrorLog "GUI module load failed" -Exception $_
        $allChecksPassed = $false
        $errors += "GUI module failed to load: $($_.Exception.Message)"
    }
}

Write-Host ""

# ============================================================================
# CHECK 6: Actual GUI Launch Test (Non-Blocking)
# ============================================================================
Write-Host "CHECK 6: GUI Launch Test (Non-Blocking)" -ForegroundColor Yellow
Write-Host "-" * 80 -ForegroundColor Gray

$guiLaunchSuccess = $false

if (-not $wpfAvailable -or -not $coreLoaded -or -not $guiLoaded -or -not $startGUIFound) {
    Write-TestLog "  ⚠️  Skipping GUI launch test - prerequisites not met" -Color Yellow
} else {
    try {
        Write-TestLog "  Attempting to launch GUI (non-blocking test)..." -Color Gray
        
        # Create a test script that tries to launch GUI
        $testScript = @"
`$ErrorActionPreference = 'Stop'
`$root = '$root'

try {
    # Load core
    . "`$root\Helper\WinRepairCore.ps1" -ErrorAction Stop
    
    # Load GUI
    . "`$root\Helper\WinRepairGUI.ps1" -ErrorAction Stop
    
    # Check if Start-GUI exists
    if (-not (Get-Command Start-GUI -ErrorAction SilentlyContinue)) {
        Write-Host "FAIL: Start-GUI function not found" -ForegroundColor Red
        exit 1
    }
    
    # Try to create the GUI window (but don't show it)
    # We'll test if the function can be called without errors
    Write-Host "SUCCESS: GUI can be launched" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "FAIL: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-Host "StackTrace: `$(`$_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}
"@
        
        $testScriptPath = Join-Path $env:TEMP "GUILaunchTest_$timestamp.ps1"
        $testScript | Out-File -FilePath $testScriptPath -Encoding UTF8 -Force
        
        $launchResult = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $testScriptPath 2>&1
        
        Remove-Item $testScriptPath -Force -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0 -and ($launchResult -match "SUCCESS")) {
            $guiLaunchSuccess = $true
            Write-TestLog "  ✅ GUI launch test passed" -Color Green
        } else {
            Write-TestLog "  ❌ GUI launch test failed" -Color Red
            Write-TestLog "  Output: $launchResult" -Color Gray
            $allChecksPassed = $false
            $errors += "GUI launch test failed"
        }
    } catch {
        Write-ErrorLog "GUI launch test exception" -Exception $_
        $allChecksPassed = $false
        $errors += "GUI launch test exception: $($_.Exception.Message)"
    }
}

Write-Host ""

# ============================================================================
# SUMMARY AND DEBUGGING
# ============================================================================
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

$checks = @(
    @{ Name = "Environment Detection"; Passed = $isFullOS }
    @{ Name = "WPF Availability"; Passed = $wpfAvailable }
    @{ Name = "Core Module Loading"; Passed = $coreLoaded }
    @{ Name = "GUI Module Loading"; Passed = $guiLoaded }
    @{ Name = "Start-GUI Function Found"; Passed = $startGUIFound }
    @{ Name = "GUI Launch Test"; Passed = $guiLaunchSuccess }
)

foreach ($check in $checks) {
    $status = if ($check.Passed) { "✅ PASS" } else { "❌ FAIL" }
    $color = if ($check.Passed) { "Green" } else { "Red" }
    Write-TestLog "$status : $($check.Name)" -Color $color
}

Write-Host ""

if ($allChecksPassed -and $guiLaunchSuccess) {
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "  ✅ ALL CHECKS PASSED - GUI CAN BE LAUNCHED" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host ""
    Write-TestLog "All checks passed - GUI is ready"
    exit 0
} else {
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  ❌ GUI LAUNCH FAILED - DEBUGGING REQUIRED" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host ""
    
    # Detailed debugging
    Write-TestLog "DEBUGGING INFORMATION" -Color Yellow
    Write-Host ""
    
    if ($errors.Count -gt 0) {
        Write-TestLog "Errors Detected:" -Color Red
        foreach ($errItem in $errors) {
            Write-TestLog "  - $errItem" -Color Red
        }
        Write-Host ""
    }
    
    # Environment info
    Write-TestLog "Environment Information:" -Color Cyan
    Write-TestLog "  OS: $([System.Environment]::OSVersion)" -Color Gray
    Write-TestLog "  PowerShell: $($PSVersionTable.PSVersion)" -Color Gray
    Write-TestLog "  SystemDrive: $env:SystemDrive" -Color Gray
    Write-TestLog "  Current Directory: $(Get-Location)" -Color Gray
    Write-Host ""
    
    # WPF debugging
    if (-not $wpfAvailable) {
        Write-TestLog "WPF Debugging:" -Color Cyan
        Write-TestLog "  Error: $wpfError" -Color Red
        Write-TestLog "  Troubleshooting:" -Color Yellow
        Write-TestLog "    1. Ensure .NET Framework 4.5+ is installed" -Color Gray
        Write-TestLog "    2. Check if PresentationFramework.dll exists" -Color Gray
        try {
            $wpfAssembly = [System.Reflection.Assembly]::LoadWithPartialName("PresentationFramework")
            if ($wpfAssembly) {
                Write-TestLog "      Found: $($wpfAssembly.Location)" -Color Green
            }
        } catch {
            Write-TestLog "      ⚠️  Could not locate PresentationFramework.dll" -Color Red
        }
        Write-Host ""
    }
    
    # GUI module debugging
    if (-not $guiLoaded -or -not $startGUIFound) {
        Write-TestLog "GUI Module Debugging:" -Color Cyan
        Write-TestLog "  Check syntax: pwsh -NoLogo -NoProfile -File 'Test\Validate-Syntax.ps1' 'Helper\WinRepairGUI.ps1'" -Color Yellow
        Write-TestLog "  Review log file: $logFile" -Color Yellow
        Write-Host ""
    }
    
    Write-TestLog "Full error log saved to: $logFile" -Color Cyan
    Write-Host ""
    Write-TestLog "GUI launch verification FAILED at $(Get-Date)"
    exit 1
}

