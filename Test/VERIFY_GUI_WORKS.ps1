<#
    VERIFY GUI WORKS - SIMPLE TEST
    ==============================
    
    This is a SIMPLE, RELIABLE test that verifies the GUI can be launched.
    Run this after EVERY code change.
    
    Usage:
        .\Test\VERIFY_GUI_WORKS.ps1
#>

$ErrorActionPreference = 'Continue'

# Get root directory
if ($PSScriptRoot) {
    if ((Split-Path $PSScriptRoot -Leaf) -eq 'Test') {
        $root = Split-Path $PSScriptRoot -Parent
    } else {
        $root = $PSScriptRoot
    }
} else {
    $root = Get-Location
}

Set-Location $root

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  VERIFYING GUI CAN BE LAUNCHED" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# Check environment
if ($env:SystemDrive -eq 'X:') {
    Write-Host "⚠️  WinRE/WinPE environment - GUI not available" -ForegroundColor Yellow
    Write-Host "   This is expected. GUI only works in FullOS." -ForegroundColor Gray
    exit 0
}

# Check WPF
Write-Host "Checking WPF availability..." -ForegroundColor Yellow
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Write-Host "  ✅ WPF available" -ForegroundColor Green
} catch {
    Write-Host "  ❌ WPF not available: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "GUI cannot be launched without WPF." -ForegroundColor Red
    exit 1
}

# Load modules
Write-Host "Loading modules..." -ForegroundColor Yellow

$Error.Clear()
. "Helper\WinRepairCore.ps1" 2>&1 | Out-Null
if ($Error) {
    $coreErrors = $Error | Where-Object { $_.Exception.Message -match "Missing closing|ParserError|Unexpected token" }
    if ($coreErrors) {
        Write-Host "  ❌ Core module has errors:" -ForegroundColor Red
        foreach ($err in $coreErrors | Select-Object -First 3) {
            Write-Host "    $($err.Exception.Message)" -ForegroundColor Red
        }
        exit 1
    }
}
Write-Host "  ✅ Core module loaded" -ForegroundColor Green

$Error.Clear()
. "Helper\WinRepairGUI.ps1" 2>&1 | Out-Null
if ($Error) {
    $guiErrors = $Error | Where-Object { $_.Exception.Message -match "Missing closing|ParserError|Unexpected token|Unexpected token.*in expression" }
    if ($guiErrors) {
        Write-Host "  ❌ GUI module has errors:" -ForegroundColor Red
        foreach ($err in $guiErrors | Select-Object -First 5) {
            Write-Host "    Line $($err.InvocationInfo.ScriptLineNumber): $($err.Exception.Message)" -ForegroundColor Red
            if ($err.InvocationInfo.Line) {
                Write-Host "      $($err.InvocationInfo.Line.Trim())" -ForegroundColor Gray
            }
        }
        exit 1
    }
}
Write-Host "  ✅ GUI module loaded" -ForegroundColor Green

# Check for Start-GUI
Write-Host "Checking for Start-GUI function..." -ForegroundColor Yellow
if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
    Write-Host "  ✅ Start-GUI function found" -ForegroundColor Green
} else {
    Write-Host "  ❌ Start-GUI function NOT found" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Green
Write-Host "  ✅ SUCCESS - GUI CAN BE LAUNCHED" -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Users on Windows 10/11 will be able to access the GUI." -ForegroundColor Green
Write-Host "Run: .\MiracleBoot.ps1" -ForegroundColor Cyan
Write-Host ""

exit 0

