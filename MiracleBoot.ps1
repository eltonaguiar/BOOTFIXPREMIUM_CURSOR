# Set execution policy for this session (needed in WinRE/WinPE)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

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
        @{ Name = "Default Browser"; Path = "start"; Test = { Start-Process "https://www.microsoft.com" -ErrorAction SilentlyContinue } },
        @{ Name = "Internet Explorer"; Path = "iexplore.exe"; Test = { Test-Path "$env:ProgramFiles\Internet Explorer\iexplore.exe" } },
        @{ Name = "Edge"; Path = "msedge.exe"; Test = { Test-Path "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe" } }
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

$envType = Get-EnvironmentType

# Load core functions
try {
    . "$PSScriptRoot\WinRepairCore.ps1"
} catch {
    Write-Host "Error loading WinRepairCore.ps1: $_" -ForegroundColor Red
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
    Write-Host "Script root: $PSScriptRoot" -ForegroundColor Yellow
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
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

if ($envType -eq 'FullOS') {
    Write-Host "Attempting to launch GUI mode..." -ForegroundColor Green
    
    # Check if WPF is available
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Write-Host "WPF assemblies loaded successfully." -ForegroundColor Green
    } catch {
        Write-Host "WARNING: WPF assemblies not available: $_" -ForegroundColor Yellow
        Write-Host "Falling back to MS-DOS Style mode..." -ForegroundColor Yellow
        . "$PSScriptRoot\WinRepairTUI.ps1"
        Start-TUI
        exit
    }
    
    try {
        . "$PSScriptRoot\WinRepairGUI.ps1"
        if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
            Start-GUI
        } else {
            throw "Start-GUI function not found in WinRepairGUI.ps1"
        }
    } catch {
        Write-Host "`nGUI mode failed, falling back to TUI:" -ForegroundColor Yellow
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host "`nPress any key to continue with TUI mode..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        . "$PSScriptRoot\WinRepairTUI.ps1"
        Start-TUI
    }
} else {
    # WinRE or WinPE - use MS-DOS Style mode
    Write-Host "Running in $envType environment - using MS-DOS Style mode." -ForegroundColor Yellow
    . "$PSScriptRoot\WinRepairTUI.ps1"
    Start-TUI
}
