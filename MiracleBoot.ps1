<#
    MIRACLE BOOT – ENTRY ORCHESTRATOR
    =================================

    This script is the **single entry point** for Miracle Boot when launched from
    `RunMiracleBoot.cmd` or directly via PowerShell. It detects the environment,
    loads the core engine, and chooses the correct experience (GUI vs TUI vs CMD).

    TABLE OF CONTENTS
    -----------------
    1. Environment Detection
       - `Get-EnvironmentType`
       - `Test-PowerShellAvailability`
       - `Test-NetworkAvailability`
       - `Test-BrowserAvailability`
    2. Core Engine Bootstrap
       - Location resolution (`$PSScriptRoot`)
       - Dot-sourcing `Helper\WinRepairCore.ps1`
    3. Experience Selection
       - FullOS + WPF available  → `Start-GUI` (WPF UI)
       - WinRE / WinPE / limited PowerShell → `Start-TUI` (console UI)
       - No PowerShell (handled by `RunMiracleBoot.cmd`) → `WinRepairCore.cmd`
    4. Safety & Diagnostics
       - Console banner and environment summary
       - Basic error handling when loading core modules

    ENVIRONMENT MAPPING & FLOW
    --------------------------
    - **FullOS (Windows 10/11 desktop)**
        1. `Get-EnvironmentType` returns `FullOS`.
        2. Script dot-sources `Helper\WinRepairCore.ps1`.
        3. If WPF assemblies load successfully, `Helper\WinRepairGUI.ps1` is loaded
           and `Start-GUI` is invoked → full graphical experience.
        4. If WPF is not available, falls back to `Helper\WinRepairTUI.ps1` → TUI.

    - **WinRE / Shift+F10 setup console**
        1. `Get-EnvironmentType` usually returns `WinRE`.
        2. Script dot-sources `Helper\WinRepairCore.ps1` and `Helper\WinRepairTUI.ps1`.
        3. Always launches `Start-TUI` → safe console experience designed for
           recovery consoles and limited shells.

    - **WinPE (USB / recovery media)**
        1. `Get-EnvironmentType` returns `WinPE`.
        2. Flow is identical to WinRE, but additional WinPE-only options may
           appear in the TUI (e.g. browser installation).

    - **No / Broken PowerShell**
        - `RunMiracleBoot.cmd` detects this case **before** calling this script and
          falls back to `WinRepairCore.cmd` (pure CMD menu).

    QUICK REFERENCE
    ---------------
    - Use **this file** to understand *where* the user will land (GUI vs TUI vs CMD)
      based on their environment.
    - Use `Helper\WinRepairCore.ps1` for the **engine** (what work gets done).
    - Use `Helper\WinRepairTUI.ps1` for the **console menus** in WinRE/WinPE.
    - Use `Helper\WinRepairGUI.ps1` for the **WPF desktop UI** in FullOS.
#>

# Set execution policy for this session (needed in WinRE/WinPE)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

# CRITICAL: WPF requires STA (Single Threaded Apartment) threading
# Check and enforce STA mode before any WPF operations
$currentThread = [System.Threading.Thread]::CurrentThread
$apartmentState = $currentThread.GetApartmentState()
if ($apartmentState -ne 'STA') {
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host "CRITICAL ERROR: PowerShell must run in STA mode for WPF UI" -ForegroundColor Red
    Write-Host ("=" * 80) -ForegroundColor Red
    Write-Host ""
    Write-Host "Current threading mode: $apartmentState" -ForegroundColor Yellow
    Write-Host "WPF (Windows Presentation Foundation) REQUIRES STA mode." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "SOLUTION:" -ForegroundColor Cyan
    Write-Host "  Launch PowerShell with: powershell.exe -STA -File MiracleBoot.ps1" -ForegroundColor White
    Write-Host "  Or use: pwsh.exe -STA -File MiracleBoot.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "Attempting to set STA mode..." -ForegroundColor Yellow
    try {
        $currentThread.SetApartmentState([System.Threading.ApartmentState]::STA)
        $newState = $currentThread.GetApartmentState()
        if ($newState -eq 'STA') {
            Write-Host "STA mode set successfully." -ForegroundColor Green
        } else {
            Write-Host "Failed to set STA mode. Current state: $newState" -ForegroundColor Red
            Write-Host "Please restart PowerShell with -STA flag." -ForegroundColor Yellow
            Write-Host "Press any key to exit..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit 1
        }
    } catch {
        Write-Host "Cannot set STA mode at runtime: $_" -ForegroundColor Red
        Write-Host "Please restart PowerShell with -STA flag." -ForegroundColor Yellow
        Write-Host "Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

$ErrorActionPreference = 'Stop'

function Get-EnvironmentType {
    # More robust detection - check multiple indicators
    
    # Primary check: SystemDrive is the most reliable indicator
    # In FullOS, SystemDrive is usually C:, in WinPE/WinRE it's X:
    if ($env:SystemDrive -eq 'X:') {
        # X: drive indicates WinPE/WinRE
        if (Test-Path 'HKLM:\System\Setup') {
            $setupType = (Get-ItemProperty -Path 'HKLM:\System\Setup' -Name 'CmdLine' -ErrorAction SilentlyContinue).CmdLine
            if ($setupType -match 'recovery|WinRE') {
                return 'WinRE'
            }
        }
        # Check for MiniNT (WinPE indicator)
        if (Test-Path 'HKLM:\System\CurrentControlSet\Control\MiniNT') {
            return 'WinPE'
        }
        return 'WinRE' # Default to WinRE if on X: drive
    }
    
    # Secondary check: MiniNT registry key (but only if SystemDrive is X:)
    # This check alone is not reliable in FullOS
    if (Test-Path 'HKLM:\System\CurrentControlSet\Control\MiniNT') {
        # Only trust this if we're on X: drive
        if ($env:SystemDrive -eq 'X:') {
            return 'WinPE'
        }
        # If we have MiniNT but SystemDrive is NOT X:, it might be a false positive
        # Check if Windows directory exists on SystemDrive
        if (Test-Path "$env:SystemDrive\Windows") {
            # Windows exists, this is likely FullOS with some registry quirk
            return 'FullOS'
        }
    }
    
    # Final check: If SystemDrive is C: (or other), and Windows directory exists, it's FullOS
    if ($env:SystemDrive -ne 'X:' -and (Test-Path "$env:SystemDrive\Windows")) {
        return 'FullOS'
    }
    
    # Default to FullOS if we can't determine (safer assumption)
    return 'FullOS'
}

function Test-PowerShellAvailability {
    <#
    .SYNOPSIS
    Tests if PowerShell is available and functional.
    #>
    try {
        $psVersion = $PSVersionTable.PSVersion
        return @{
            Available = $true
            Version = $psVersion.ToString()
            Message = "PowerShell $($psVersion.Major).$($psVersion.Minor) available"
        }
    } catch {
        return @{
            Available = $false
            Version = "Unknown"
            Message = "PowerShell not available"
        }
    }
}

function Test-NetworkAvailability {
    <#
    .SYNOPSIS
    Tests if network adapters are available (not necessarily connected).
    #>
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Hidden' }
        if ($adapters) {
            $enabled = ($adapters | Where-Object { $_.Status -eq 'Up' }).Count
            return @{
                Available = $true
                AdapterCount = $adapters.Count
                EnabledCount = $enabled
                Message = "$($adapters.Count) network adapter(s) found ($enabled enabled)"
            }
        }
        
        # Fallback: Check with netsh
        $netshOutput = netsh interface show interface 2>&1
        if ($netshOutput -match 'connected|disconnected') {
            return @{
                Available = $true
                AdapterCount = 1
                EnabledCount = 0
                Message = "Network adapters detected (via netsh)"
            }
        }
        
        return @{
            Available = $false
            AdapterCount = 0
            EnabledCount = 0
            Message = "No network adapters found"
        }
    } catch {
        return @{
            Available = $false
            AdapterCount = 0
            EnabledCount = 0
            Message = "Could not detect network adapters: $_"
        }
    }
}

function Test-BrowserAvailability {
    <#
    .SYNOPSIS
    Tests if a web browser is available.
    #>
    $browsers = @(
        @{ Name = "Default Browser"; Path = "start"; Test = { $null -ne (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -ErrorAction SilentlyContinue) } },
        @{ Name = "Internet Explorer"; Path = "iexplore.exe"; Test = { Test-Path "$env:ProgramFiles\Internet Explorer\iexplore.exe" } },
        @{ Name = "Edge"; Path = "msedge.exe"; Test = { Test-Path "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe" -or Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" } },
        @{ Name = "Chrome"; Path = "chrome.exe"; Test = { Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" -or Test-Path "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe" } },
        @{ Name = "Firefox"; Path = "firefox.exe"; Test = { Test-Path "$env:ProgramFiles\Mozilla Firefox\firefox.exe" -or Test-Path "$env:ProgramFiles (x86)\Mozilla Firefox\firefox.exe" } }
    )
    
    foreach ($browser in $browsers) {
        try {
            if (& $browser.Test) {
                return @{
                    Available = $true
                    Browser = $browser.Name
                    Message = "$($browser.Name) available"
                }
            }
        } catch {
            continue
        }
    }
    
    return @{
        Available = $false
        Browser = "None"
        Message = "No browser available"
    }
}

# Initialize script root path
if ($null -eq $PSScriptRoot -or $PSScriptRoot -eq '') {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
    if ($null -eq $PSScriptRoot -or $PSScriptRoot -eq '') {
        $PSScriptRoot = Get-Location
    }
}

# Ensure we have a valid path
if (-not (Test-Path $PSScriptRoot)) {
    $PSScriptRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Path))
}

# Initialize centralized logging system
try {
    if (Test-Path "$PSScriptRoot\Helper\ErrorLogging.ps1") {
        . "$PSScriptRoot\Helper\ErrorLogging.ps1"
        $null = Initialize-ErrorLogging -ScriptRoot $PSScriptRoot -RetentionDays 7
        Add-MiracleBootLog -Level "INFO" -Message "MiracleBoot.ps1 started" -Location "MiracleBoot.ps1"
    }
} catch {
    # Silently continue if logging fails - don't break startup
}

$envType = Get-EnvironmentType

# Pre-launch validation
try {
    if (Test-Path "$PSScriptRoot\Helper\PreLaunchValidation.ps1") {
        . "$PSScriptRoot\Helper\PreLaunchValidation.ps1"
        $validation = Test-PreLaunchValidation -ScriptRoot $PSScriptRoot
        
        if (-not $validation.Passed) {
            Write-Host ""
            Write-Host "===============================================================" -ForegroundColor Red
            Write-Host "  PRE-LAUNCH VALIDATION FAILED" -ForegroundColor Red
            Write-Host "===============================================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "The following errors were detected:" -ForegroundColor Yellow
            foreach ($error in $validation.Errors) {
                Write-Host "  - $error" -ForegroundColor White
            }
            Write-Host ""
            if ($validation.Warnings.Count -gt 0) {
                Write-Host "Warnings:" -ForegroundColor Yellow
                foreach ($warning in $validation.Warnings) {
                    Write-Host "  - $warning" -ForegroundColor Gray
                }
                Write-Host ""
            }
            Write-Host "Please fix these errors before launching Miracle Boot." -ForegroundColor Yellow
            Write-Host "Press any key to exit..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit 1
        }
        
        if ($validation.Warnings.Count -gt 0) {
            Write-Host ""
            Write-Host "Validation warnings (non-critical):" -ForegroundColor Yellow
            foreach ($warning in $validation.Warnings) {
                Write-Host "  - $warning" -ForegroundColor Gray
            }
            Write-Host ""
        }
    }
} catch {
    Write-Host "Warning: Pre-launch validation failed: $_" -ForegroundColor Yellow
    Write-Host "Continuing anyway..." -ForegroundColor Yellow
}

# Load core functions
try {
    #region agent log - WinRepairCore load
    try {
        $logPayload = @{
            sessionId    = "debug-session"
            runId        = "verify-run"
            hypothesisId = "H1"
            location     = "MiracleBoot.ps1:before-load-core"
            message      = "About to load WinRepairCore.ps1"
            data         = @{
                ScriptRoot = $PSScriptRoot
                CorePath   = "$PSScriptRoot\Helper\WinRepairCore.ps1"
            }
            timestamp    = [int][double]::Parse((Get-Date -UFormat %s))
        } | ConvertTo-Json -Compress
        Add-Content -Path ".cursor\debug.log" -Value $logPayload -ErrorAction SilentlyContinue
    } catch {}
    #endregion
    
    . "$PSScriptRoot\Helper\WinRepairCore.ps1"
    
    #region agent log - WinRepairCore loaded
    try {
        $logPayload = @{
            sessionId    = "debug-session"
            runId        = "verify-run"
            hypothesisId = "H2"
            location     = "MiracleBoot.ps1:after-load-core"
            message      = "WinRepairCore.ps1 loaded successfully"
            data         = @{
                FunctionsLoaded = $true
            }
            timestamp    = [int][double]::Parse((Get-Date -UFormat %s))
        } | ConvertTo-Json -Compress
        Add-Content -Path ".cursor\debug.log" -Value $logPayload -ErrorAction SilentlyContinue
    } catch {}
    #endregion
} catch {
    #region agent log - WinRepairCore load error
    try {
        $logPayload = @{
            sessionId    = "debug-session"
            runId        = "verify-run"
            hypothesisId = "H3"
            location     = "MiracleBoot.ps1:load-core-error"
            message      = "Failed to load WinRepairCore.ps1"
            data         = @{
                Error = $_.ToString()
            }
            timestamp    = [int][double]::Parse((Get-Date -UFormat %s))
        } | ConvertTo-Json -Compress
        Add-Content -Path ".cursor\debug.log" -Value $logPayload -ErrorAction SilentlyContinue
    } catch {}
    #endregion
    
    Write-Host "Error loading Helper\WinRepairCore.ps1: $_" -ForegroundColor Red
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
    Write-Host "Script root: $PSScriptRoot" -ForegroundColor Yellow
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Load GUI failure diagnostics module early (needed for fallback scenarios)
try {
    if (Test-Path "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1") {
        . "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1"
    }
} catch {
    Write-Warning "Could not load GUIFailureDiagnostics.ps1: $_"
}

# Load additional modules (if available)
try {
    if (Test-Path "$PSScriptRoot\Helper\NetworkDiagnostics.ps1") {
        . "$PSScriptRoot\Helper\NetworkDiagnostics.ps1"
        Write-Host "Network Diagnostics module loaded." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not load NetworkDiagnostics.ps1: $_"
}

try {
    if (Test-Path "$PSScriptRoot\Helper\KeyboardSymbols.ps1") {
        . "$PSScriptRoot\Helper\KeyboardSymbols.ps1"
        Write-Host "Keyboard Symbols module loaded." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not load KeyboardSymbols.ps1: $_"
}

# Check environment capabilities
$psInfo = Test-PowerShellAvailability
$networkInfo = Test-NetworkAvailability
$browserInfo = Test-BrowserAvailability

# Launch appropriate interface
Write-Host "Detected Environment: $envType" -ForegroundColor Cyan
Write-Host "SystemDrive: $env:SystemDrive" -ForegroundColor Gray
Write-Host ""
Write-Host "Environment Capabilities:" -ForegroundColor Cyan
Write-Host "  PowerShell: $($psInfo.Message)" -ForegroundColor $(if ($psInfo.Available) { "Green" } else { "Yellow" })
Write-Host "  Network: $($networkInfo.Message)" -ForegroundColor $(if ($networkInfo.Available) { "Green" } else { "Yellow" })
Write-Host "  Browser: $($browserInfo.Message)" -ForegroundColor $(if ($browserInfo.Available) { "Green" } else { "Yellow" })
Write-Host ""

# Safety interlock for live FullOS: require explicit confirmation before boot writes
if ($envType -eq 'FullOS') {
    if (-not $env:CI -and -not $env:TF_BUILD) {
        $confirm = Read-Host "SAFETY WARNING: You are running in a live Windows session. Type 'BRICKME' to continue or press Enter to abort"
        if ($confirm -ne 'BRICKME') {
            Write-Host "Aborting by user choice. No changes made." -ForegroundColor Yellow
            exit 1
        }
    }
}

# GUI can launch in FullOS or WinPE (if WPF is available)
# WinRE will use TUI for safety
$canLaunchGUI = ($envType -eq 'FullOS') -or ($envType -eq 'WinPE')

if ($canLaunchGUI) {
    if ($envType -eq 'WinPE') {
        Write-Host "=" * 80 -ForegroundColor Yellow
        Write-Host "WARNING: GUI MODE IN WINPE ENVIRONMENT" -ForegroundColor Yellow
        Write-Host "=" * 80 -ForegroundColor Yellow
        Write-Host ""
        Write-Host "You are launching the GUI in Windows Preinstallation Environment (WinPE)." -ForegroundColor Yellow
        Write-Host "While the GUI interface itself is safe, the repair operations it allows" -ForegroundColor Yellow
        Write-Host "can be DESTRUCTIVE if misused. Please exercise caution when:" -ForegroundColor Yellow
        Write-Host "  - Modifying boot configuration (BCD)" -ForegroundColor Yellow
        Write-Host "  - Repairing system files on offline installations" -ForegroundColor Yellow
        Write-Host "  - Performing disk repairs" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "The GUI will launch in 3 seconds. Press Ctrl+C to cancel and use TUI instead." -ForegroundColor Cyan
        Start-Sleep -Seconds 3
        Write-Host ""
    } else {
        Write-Host "Attempting to launch GUI mode..." -ForegroundColor Green
    }
    
    # Check if WPF is available
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        Write-Host "WPF assemblies loaded successfully." -ForegroundColor Green
        
        #region agent log - WPF loaded
        try {
            $logPayload = @{
                sessionId    = "debug-session"
                runId        = "verify-run"
                hypothesisId = "H4"
                location     = "MiracleBoot.ps1:wpf-loaded"
                message      = "WPF assemblies loaded, attempting GUI"
                data         = @{ WPFReady = $true }
                timestamp    = [int][double]::Parse((Get-Date -UFormat %s))
            } | ConvertTo-Json -Compress
            Add-Content -Path ".cursor\debug.log" -Value $logPayload -ErrorAction SilentlyContinue
        } catch {}
        #endregion
    } catch {
        Write-Host "WARNING: WPF assemblies not available: $_" -ForegroundColor Yellow
        Write-Host "Falling back to MS-DOS Style mode..." -ForegroundColor Yellow
        
        # Generate and show diagnostic report
        try {
            if (Test-Path "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1") {
                . "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1"
                Show-GUIFailureReport -FailureReason "WPF assemblies not available" `
                                      -ErrorDetails $_ `
                                      -Exception $_ `
                                      -FailurePoint "WPF_Assemblies"
            }
        } catch {
            Write-Warning "Could not generate GUI failure report: $_"
        }
        
        Write-Host ""
        Write-Host "Press any key to continue with TUI mode..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        . "$PSScriptRoot\Helper\WinRepairTUI.ps1"
        Start-TUI
        exit
    }
    
    try {
        # Run Readiness Gate before GUI launch
        $readinessGatePath = Join-Path $PSScriptRoot "Helper\ReadinessGate.ps1"
        if (Test-Path $readinessGatePath) {
            Write-Host "Running readiness validation..." -ForegroundColor Gray
            . $readinessGatePath
            $readiness = Test-ReadinessGate -ScriptRoot $PSScriptRoot
            if (-not $readiness.IsReady) {
                Write-Host ""
                Write-Host "❌ READINESS GATE FAILED - GUI LAUNCH BLOCKED" -ForegroundColor Red
                Write-Host "The following issues must be fixed before GUI can launch:" -ForegroundColor Yellow
                $blockersList = $readiness.Blockers -join "; "
                foreach ($blocker in $readiness.Blockers) {
                    Write-Host "  - $blocker" -ForegroundColor Yellow
                }
                Write-Host ""
                Write-Host "Falling back to TUI mode..." -ForegroundColor Yellow
                
                # Generate and show diagnostic report
                try {
                    if (Test-Path "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1") {
                        . "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1"
                        Show-GUIFailureReport -FailureReason "Readiness gate failed" `
                                              -ErrorDetails $blockersList `
                                              -FailurePoint "Readiness_Gate"
                    }
                } catch {
                    Write-Warning "Could not generate GUI failure report: $_"
                }
                
                throw "Readiness gate failed - GUI launch blocked"
            }
        }
        
        Write-Host "Loading GUI module..." -ForegroundColor Gray
        
        # Load GUI module with comprehensive error handling
        $guiLoadErrors = @()
        try {
            # Capture any errors during module load
            $ErrorActionPreference = 'Continue'
            $guiOutput = . "$PSScriptRoot\Helper\WinRepairGUI.ps1" 2>&1
            $ErrorActionPreference = 'Stop'
            
            # Check for errors in output
            foreach ($line in $guiOutput) {
                if ($line -is [System.Management.Automation.ErrorRecord]) {
                    $guiLoadErrors += $line.Exception.Message
                    Write-Host "WARNING during GUI module load: $($line.Exception.Message)" -ForegroundColor Yellow
                }
            }
            
            # Check for parser errors
            if ($guiLoadErrors.Count -gt 0) {
                $criticalErrors = $guiLoadErrors | Where-Object { $_ -match 'ParserError|SyntaxError|Missing|Unexpected' }
                if ($criticalErrors.Count -gt 0) {
                    throw "Critical errors during GUI module load: $($criticalErrors -join '; ')"
                }
            }
            
            Write-Host "GUI module loaded." -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to load GUI module: $_" -ForegroundColor Red
            Write-Host "Falling back to TUI mode..." -ForegroundColor Yellow
            
            # Generate and show diagnostic report
            try {
                if (Test-Path "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1") {
                    . "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1"
                    Show-GUIFailureReport -FailureReason "GUI module load failed" `
                                          -ErrorDetails $_ `
                                          -Exception $_ `
                                          -FailurePoint "GUI_Module_Load"
                }
            } catch {
                Write-Warning "Could not generate GUI failure report: $_"
            }
            
            throw "GUI module load failed: $_"
        }
        
        # Verify Start-GUI function exists (use Stop to fail fast if missing)
        if (-not (Get-Command Start-GUI -ErrorAction SilentlyContinue)) {
            # Generate and show diagnostic report
            try {
                if (Test-Path "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1") {
                    . "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1"
                    Show-GUIFailureReport -FailureReason "Start-GUI function not found" `
                                          -ErrorDetails "The Start-GUI function is missing from Helper\WinRepairGUI.ps1" `
                                          -FailurePoint "Start_GUI_Function"
                }
            } catch {
                Write-Warning "Could not generate GUI failure report: $_"
            }
            
            throw "Start-GUI function not found in WinRepairGUI.ps1"
        }
        
        Write-Host "GUI function verified." -ForegroundColor Green
        Write-Host "Launching GUI window..." -ForegroundColor Green
        
        # Additional safety check: Verify GUI module loaded without errors
        $guiErrors = $null
        try {
            # Test that Start-GUI is callable
            $guiCmd = Get-Command Start-GUI -ErrorAction Stop
            if ($null -eq $guiCmd) {
                throw "Start-GUI command not found after module load"
            }
        } catch {
            $guiErrors = $_.Exception.Message
            Write-Host "ERROR: GUI module validation failed: $guiErrors" -ForegroundColor Red
            
            # Generate and show diagnostic report
            try {
                if (Test-Path "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1") {
                    . "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1"
                    Show-GUIFailureReport -FailureReason "GUI module validation failed" `
                                          -ErrorDetails $guiErrors `
                                          -Exception $_ `
                                          -FailurePoint "GUI_Module_Validation"
                }
            } catch {
                Write-Warning "Could not generate GUI failure report: $_"
            }
            
            throw "GUI module validation failed: $guiErrors"
        }
        #region agent log - GUI starting
        try {
            $logPayload = @{
                sessionId    = "debug-session"
                runId        = "verify-run"
                hypothesisId = "H5"
                location     = "MiracleBoot.ps1:gui-starting"
                message      = "Starting GUI mode"
                data         = @{ GUIMode = $true }
                timestamp    = [int][double]::Parse((Get-Date -UFormat %s))
            } | ConvertTo-Json -Compress
            Add-Content -Path ".cursor\debug.log" -Value $logPayload -ErrorAction SilentlyContinue
        } catch {}
        #endregion
        
        # Call Start-GUI with explicit error handling
        try {
            Start-GUI
            Write-Host "GUI launched successfully." -ForegroundColor Green
            exit 0  # Exit successfully after GUI closes
        } catch {
            # Log error to file for debugging
            $errorLogPath = Join-Path $PSScriptRoot "MiracleBoot_GUI_Error.log"
            $errorMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): GUI window launch failed: $($_.Exception.Message)"
            Add-Content -Path $errorLogPath -Value $errorMsg -ErrorAction SilentlyContinue
            Add-Content -Path $errorLogPath -Value "Stack trace: $($_.ScriptStackTrace)" -ErrorAction SilentlyContinue
            throw  # Re-throw to be caught by outer catch
        }
    } catch {
        #region agent log - GUI failed, falling back
        try {
            $logPayload = @{
                sessionId    = "debug-session"
                runId        = "verify-run"
                hypothesisId = "H6"
                location     = "MiracleBoot.ps1:gui-failed"
                message      = "GUI window launch failed, falling back to TUI"
                data         = @{
                    Error = $_.ToString()
                    FallbackToTUI = $true
                }
                timestamp    = [int][double]::Parse((Get-Date -UFormat %s))
            } | ConvertTo-Json -Compress
            Add-Content -Path ".cursor\debug.log" -Value $logPayload -ErrorAction SilentlyContinue
        } catch {}
        #endregion
        
        Write-Host "`n===============================================================" -ForegroundColor Yellow
        Write-Host "GUI WINDOW LAUNCH FAILED - FALLING BACK TO TUI" -ForegroundColor Yellow
        Write-Host "===============================================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Note: GUI module loaded successfully, but the window failed to launch." -ForegroundColor Gray
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        
        # Generate and show diagnostic report
        try {
            if (Test-Path "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1") {
                . "$PSScriptRoot\Helper\GUIFailureDiagnostics.ps1"
                Show-GUIFailureReport -FailureReason "GUI window launch failed" `
                                      -ErrorDetails "GUI module loaded but window failed to launch" `
                                      -Exception $_ `
                                      -FailurePoint "GUI_Window_Launch"
            }
        } catch {
            Write-Warning "Could not generate GUI failure report: $_"
        }
        
        Write-Host ""
        Write-Host "Error Details:" -ForegroundColor Yellow
        Write-Host "  $($_.Exception.Message)" -ForegroundColor White
        if ($_.Exception.InnerException) {
            Write-Host "  Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "This usually means:" -ForegroundColor Yellow
        Write-Host "  - WPF assemblies failed to load" -ForegroundColor Gray
        Write-Host "  - GUI module has syntax errors" -ForegroundColor Gray
        Write-Host "  - Missing .NET Framework components" -ForegroundColor Gray
        Write-Host ""
        Write-Host "A diagnostic report has been opened in Notepad with full details." -ForegroundColor Cyan
        Write-Host "Press any key to continue with TUI mode..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        . "$PSScriptRoot\Helper\WinRepairTUI.ps1"
        Start-TUI
    }
} else {
    # WinRE or WinPE - use MS-DOS Style mode
    Write-Host "Running in $envType environment - using MS-DOS Style mode." -ForegroundColor Yellow
    
    #region agent log - TUI mode
    try {
        $logPayload = @{
            sessionId    = "debug-session"
            runId        = "verify-run"
            hypothesisId = "H7"
            location     = "MiracleBoot.ps1:tui-mode"
            message      = "Starting TUI mode"
            data         = @{
                Environment = $envType
                TUIMode = $true
            }
            timestamp    = [int][double]::Parse((Get-Date -UFormat %s))
        } | ConvertTo-Json -Compress
        Add-Content -Path ".cursor\debug.log" -Value $logPayload -ErrorAction SilentlyContinue
    } catch {}
    #endregion
    
    . "$PSScriptRoot\Helper\WinRepairTUI.ps1"
    Start-TUI
}
