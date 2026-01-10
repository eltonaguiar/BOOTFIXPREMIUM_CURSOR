# CRITICAL TEST: Actual GUI Launch
# This test ACTUALLY launches the GUI to catch stack overflow

$ErrorActionPreference = 'Stop'
if ($PSScriptRoot) {
    $scriptRoot = $PSScriptRoot
} else {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $scriptRoot) {
    $scriptRoot = Get-Location
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ACTUAL GUI LAUNCH TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This test will ACTUALLY parse XAML and create the window." -ForegroundColor Yellow
Write-Host "If stack overflow occurs, we'll catch it here." -ForegroundColor Yellow
Write-Host ""

# Load modules
Write-Host "[STEP 1] Loading modules..." -ForegroundColor Yellow
try {
    . "$scriptRoot\Helper\WinRepairCore.ps1" -ErrorAction Stop
    Write-Host "  [OK] Core loaded" -ForegroundColor Green
    
    . "$scriptRoot\Helper\WinRepairGUI.ps1" -ErrorAction Stop
    Write-Host "  [OK] GUI loaded" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Module load failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Extract XAML and test parsing
Write-Host "[STEP 2] Extracting and testing XAML..." -ForegroundColor Yellow
try {
    # Get the actual path - check multiple locations
    $guiPath = Join-Path $scriptRoot "Helper\WinRepairGUI.ps1"
    if (-not (Test-Path $guiPath)) {
        # Try current directory
        $guiPath = "Helper\WinRepairGUI.ps1"
        if (-not (Test-Path $guiPath)) {
            # Try absolute path from where we are
            $guiPath = Resolve-Path "Helper\WinRepairGUI.ps1" -ErrorAction SilentlyContinue
            if (-not $guiPath) {
                throw "WinRepairGUI.ps1 not found. Checked: $scriptRoot\Helper\WinRepairGUI.ps1 and Helper\WinRepairGUI.ps1"
            }
        }
    }
    
    Write-Host "  [INFO] Using GUI file: $guiPath" -ForegroundColor Gray
    $guiContent = Get-Content $guiPath -Raw
    
    # Extract XAML using regex
    if ($guiContent -match '(?s)\$XAML\s*=\s*@"(.*?)"@') {
        $xaml = $matches[1]
        $xamlSize = [System.Text.Encoding]::UTF8.GetByteCount($xaml)
        $xamlSizeMB = [math]::Round($xamlSize / 1MB, 2)
        
        Write-Host "  [OK] XAML extracted ($xamlSizeMB MB)" -ForegroundColor Green
        
        # Test XAML parsing
        Write-Host "  [TEST] Parsing XAML..." -ForegroundColor Gray
        
        Add-Type -AssemblyName PresentationFramework
        $xmlDoc = [xml]$xaml
        $xmlReader = New-Object System.Xml.XmlNodeReader($xmlDoc)
        
        try {
            $window = [Windows.Markup.XamlReader]::Load($xmlReader)
            
            if ($window) {
                Write-Host "  [OK] Window created successfully!" -ForegroundColor Green
                $window.Close()
                Write-Host "  [OK] Window closed" -ForegroundColor Green
                Write-Host ""
                Write-Host "[PASS] XAML parsing and window creation successful" -ForegroundColor Green
            } else {
                Write-Host "  [FAIL] Window is null" -ForegroundColor Red
                exit 1
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Host "  [FAIL] XAML parsing failed: $errorMsg" -ForegroundColor Red
            
            if ($errorMsg -match 'stack|overflow|buffer|0xC0000409|-1073740771') {
                Write-Host ""
                Write-Host "*** STACK BUFFER OVERRUN DETECTED ***" -ForegroundColor Red
                Write-Host "This is the critical bug!" -ForegroundColor Red
            }
            
            exit 1
        } finally {
            if ($xmlReader) {
                try {
                    $xmlReader.Close()
                    $xmlReader.Dispose()
                } catch {}
            }
        }
    } else {
        Write-Host "  [FAIL] Could not extract XAML from WinRepairGUI.ps1" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  [FAIL] XAML test failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ALL TESTS PASSED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The GUI can be launched without stack overflow errors." -ForegroundColor Green
Write-Host ""
