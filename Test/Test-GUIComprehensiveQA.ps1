<#
.SYNOPSIS
Comprehensive QA Panel for GUI Validation

.DESCRIPTION
Thoroughly tests all aspects of the GUI to ensure it's ready for launch.
Checks XAML syntax, control existence, event handlers, dependencies, and more.
#>

$ErrorActionPreference = "Stop"
# Get the script root - ensure we're at project root, not Helper directory
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
# If script is in root, scriptRoot is parent of root (wrong). If in Helper, scriptRoot is root (correct).
# Check if we need to adjust
$scriptLeaf = Split-Path -Leaf $scriptRoot
if ($scriptLeaf -eq "Helper") {
    # Script is in Helper directory, go up one level
    $scriptRoot = Split-Path -Parent $scriptRoot
} elseif ($scriptLeaf -ne "MiracleBoot_v7_1_1" -and (Test-Path (Join-Path $scriptRoot "Helper\WinRepairGUI.ps1"))) {
    # We're at project root already
    # Do nothing
} else {
    # Try to find project root by looking for Helper directory
    $helperPath = Join-Path $scriptRoot "Helper"
    if (-not (Test-Path $helperPath)) {
        # Maybe we're one level up?
        $possibleRoot = Join-Path $scriptRoot "MiracleBoot_v7_1_1"
        if (Test-Path (Join-Path $possibleRoot "Helper\WinRepairGUI.ps1")) {
            $scriptRoot = $possibleRoot
        }
    }
}
$testResults = @{
    Passed = 0
    Failed = 0
    Warnings = 0
    Tests = @()
}

function Add-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [string]$Warning = ""
    )
    
    $result = @{
        TestName = $TestName
        Passed = $Passed
        Message = $Message
        Warning = $Warning
        Timestamp = Get-Date
    }
    
    $testResults.Tests += $result
    
    if ($Passed) {
        $testResults.Passed++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Gray
        }
    } else {
        $testResults.Failed++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) {
            Write-Host "       $Message" -ForegroundColor Yellow
        }
    }
    
    if ($Warning) {
        $testResults.Warnings++
        Write-Host "[WARN] $Warning" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  COMPREHENSIVE GUI QA PANEL" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: WPF Availability
Write-Host "[TEST 1] Checking WPF Availability..." -ForegroundColor Gray
try {
    $null = [System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework')
    $null = [System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')
    $null = [System.Reflection.Assembly]::LoadWithPartialName('WindowsBase')
    Add-TestResult -TestName "WPF Assemblies Available" -Passed $true -Message "PresentationFramework, PresentationCore, WindowsBase loaded"
} catch {
    Add-TestResult -TestName "WPF Assemblies Available" -Passed $false -Message "Failed to load WPF assemblies: $_"
}

# Test 2: STA Mode Check
Write-Host "[TEST 2] Checking STA Mode..." -ForegroundColor Gray
try {
    $currentThread = [System.Threading.Thread]::CurrentThread
    $apartmentState = $currentThread.GetApartmentState()
    if ($apartmentState -eq 'STA') {
        Add-TestResult -TestName "STA Mode" -Passed $true -Message "Current thread is in STA mode"
    } else {
        Add-TestResult -TestName "STA Mode" -Passed $false -Message "Current thread is in $apartmentState mode (STA required for WPF)"
    }
} catch {
    Add-TestResult -TestName "STA Mode" -Passed $false -Message "Failed to check STA mode: $_"
}

# Test 3: GUI Script File Exists
Write-Host "[TEST 3] Checking GUI Script File..." -ForegroundColor Gray
$guiScriptPath = Join-Path $scriptRoot "Helper\WinRepairGUI.ps1"
if (Test-Path $guiScriptPath) {
    Add-TestResult -TestName "GUI Script File Exists" -Passed $true -Message "Found at: $guiScriptPath"
} else {
    Add-TestResult -TestName "GUI Script File Exists" -Passed $false -Message "Not found at: $guiScriptPath"
    exit 1
}

# Test 4: GUI Script Syntax Validation
Write-Host "[TEST 4] Validating GUI Script Syntax..." -ForegroundColor Gray
try {
    $env:MB_VALIDATION_MODE = "1"
    $errors = @()
    $null = . $guiScriptPath 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $errors += $_.Exception.Message
        }
    }
    
    $syntaxErrors = $errors | Where-Object { $_ -match 'ParserError|SyntaxError|Missing|Unexpected' }
    if ($syntaxErrors.Count -eq 0) {
        Add-TestResult -TestName "GUI Script Syntax" -Passed $true -Message "No syntax errors detected"
    } else {
        Add-TestResult -TestName "GUI Script Syntax" -Passed $false -Message "Syntax errors found: $($syntaxErrors -join '; ')"
    }
} catch {
    Add-TestResult -TestName "GUI Script Syntax" -Passed $false -Message "Failed to validate syntax: $_"
}

# Test 5: Start-GUI Function Exists
Write-Host "[TEST 5] Checking Start-GUI Function..." -ForegroundColor Gray
try {
    if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
        Add-TestResult -TestName "Start-GUI Function Exists" -Passed $true -Message "Function is defined"
    } else {
        Add-TestResult -TestName "Start-GUI Function Exists" -Passed $false -Message "Function not found after loading script"
    }
} catch {
    Add-TestResult -TestName "Start-GUI Function Exists" -Passed $false -Message "Error checking function: $_"
}

# Test 6: XAML Structure Validation
Write-Host "[TEST 6] Validating XAML Structure..." -ForegroundColor Gray
try {
    $guiContent = Get-Content $guiScriptPath -Raw
    $xamlStart = $guiContent.IndexOf('$XAML = @"')
    if ($xamlStart -eq -1) {
        Add-TestResult -TestName "XAML Definition Found" -Passed $false -Message "XAML definition not found in script"
    } else {
        $xamlEnd = $guiContent.IndexOf('"@', $xamlStart)
        if ($xamlEnd -eq -1) {
            Add-TestResult -TestName "XAML Definition Found" -Passed $false -Message "XAML definition not properly closed"
        } else {
            $xamlContent = $guiContent.Substring($xamlStart + 10, $xamlEnd - $xamlStart - 10)
            
            # Validate XML structure
            try {
                $xmlDoc = [xml]$xamlContent
                Add-TestResult -TestName "XAML XML Structure" -Passed $true -Message "XAML is valid XML"
                
                # Check for Window element
                if ($xmlDoc.Window) {
                    Add-TestResult -TestName "XAML Window Element" -Passed $true -Message "Window element found"
                } else {
                    Add-TestResult -TestName "XAML Window Element" -Passed $false -Message "Window element not found"
                }
                
                # Check for Grid
                if ($xmlDoc.Window.Grid) {
                    Add-TestResult -TestName "XAML Grid Element" -Passed $true -Message "Grid element found"
                } else {
                    Add-TestResult -TestName "XAML Grid Element" -Passed $false -Message "Grid element not found"
                }
                
                # Check for Menu (using XPath to find anywhere in document)
                $menuFound = $xmlDoc.SelectNodes("//*[local-name()='Menu']") | Measure-Object
                if ($menuFound.Count -gt 0) {
                    Add-TestResult -TestName "XAML Menu Element" -Passed $true -Message "Found $($menuFound.Count) Menu element(s)"
                } else {
                    Add-TestResult -TestName "XAML Menu Element" -Passed $false -Message "Menu element not found"
                }
                
                # Check for TabControl (using XPath to find anywhere in document)
                $tabControlFound = $xmlDoc.SelectNodes("//*[local-name()='TabControl']") | Measure-Object
                if ($tabControlFound.Count -gt 0) {
                    Add-TestResult -TestName "XAML TabControl Element" -Passed $true -Message "Found $($tabControlFound.Count) TabControl element(s)"
                } else {
                    Add-TestResult -TestName "XAML TabControl Element" -Passed $false -Message "TabControl element not found"
                }
                
            } catch {
                Add-TestResult -TestName "XAML XML Structure" -Passed $false -Message "XAML is not valid XML: $_"
            }
        }
    }
} catch {
    Add-TestResult -TestName "XAML Structure Validation" -Passed $false -Message "Failed to validate XAML: $_"
}

# Test 7: Critical Controls Check
Write-Host "[TEST 7] Checking Critical Controls..." -ForegroundColor Gray
$criticalControls = @(
    "BtnOneClickRepair",
    "FixerOutput",
    "MenuSettingsOpen",
    "MenuSettingsSequential",
    "BtnSettingsSequential",
    "RadioLightMode",
    "RadioDarkMode",
    "InterfaceScaleSlider",
    "WindowSizeSlider"
)

try {
    $guiContent = Get-Content $guiScriptPath -Raw
    $missingControls = @()
    
    foreach ($control in $criticalControls) {
        $pattern = "Name=`"$control`""
        if ($guiContent -match [regex]::Escape($pattern)) {
            Add-TestResult -TestName "Control: $control" -Passed $true
        } else {
            $missingControls += $control
            Add-TestResult -TestName "Control: $control" -Passed $false -Message "Control not found in XAML"
        }
    }
    
    if ($missingControls.Count -eq 0) {
        Add-TestResult -TestName "All Critical Controls Present" -Passed $true -Message "All $($criticalControls.Count) critical controls found"
    }
} catch {
    Add-TestResult -TestName "Critical Controls Check" -Passed $false -Message "Failed to check controls: $_"
}

# Test 8: Function Definitions Check
Write-Host "[TEST 8] Checking Function Definitions..." -ForegroundColor Gray
$requiredFunctions = @(
    "Start-GUI",
    "Start-EmergencyBootScript",
    "Start-SafeNotepad"
)

foreach ($funcName in $requiredFunctions) {
    try {
        if (Get-Command $funcName -ErrorAction SilentlyContinue) {
            Add-TestResult -TestName "Function: $funcName" -Passed $true
        } else {
            Add-TestResult -TestName "Function: $funcName" -Passed $false -Message "Function not defined"
        }
    } catch {
        Add-TestResult -TestName "Function: $funcName" -Passed $false -Message "Error checking function: $_"
    }
}

# Check for functions defined inside Start-GUI (they exist in script but are scoped)
Write-Host "[TEST 8b] Checking Internal Functions (in script source)..." -ForegroundColor Gray
$internalFunctions = @(
    "Set-DarkMode",
    "Set-WindowSize",
    "Set-InterfaceScale",
    "Start-SequentialRepair"
)

$guiContent = Get-Content $guiScriptPath -Raw
foreach ($funcName in $internalFunctions) {
    $pattern = "function\s+$funcName"
    if ($guiContent -match $pattern) {
        Add-TestResult -TestName "Function Source: $funcName" -Passed $true -Message "Function defined in script"
    } else {
        Add-TestResult -TestName "Function Source: $funcName" -Passed $false -Message "Function not found in script source"
    }
}

# Test 9: Event Handler Wiring Check
Write-Host "[TEST 9] Checking Event Handler Wiring..." -ForegroundColor Gray
try {
    $guiContent = Get-Content $guiScriptPath -Raw
    
    $eventHandlers = @(
        @{ Control = "MenuSettingsOpen"; Event = "Add_Click" },
        @{ Control = "MenuSettingsSequential"; Event = "Add_Click" },
        @{ Control = "BtnSettingsSequential"; Event = "Add_Click" },
        @{ Control = "RadioLightMode"; Event = "Add_Checked" },
        @{ Control = "RadioDarkMode"; Event = "Add_Checked" },
        @{ Control = "InterfaceScaleSlider"; Event = "Add_ValueChanged" },
        @{ Control = "WindowSizeSlider"; Event = "Add_ValueChanged" }
    )
    
    foreach ($handler in $eventHandlers) {
        $pattern = "\`$$($handler.Control).*$($handler.Event)"
        if ($guiContent -match $pattern) {
            Add-TestResult -TestName "Event Handler: $($handler.Control).$($handler.Event)" -Passed $true
        } else {
            Add-TestResult -TestName "Event Handler: $($handler.Control).$($handler.Event)" -Passed $false -Message "Event handler not wired"
        }
    }
} catch {
    Add-TestResult -TestName "Event Handler Wiring" -Passed $false -Message "Failed to check event handlers: $_"
}

# Test 10: XAML Parsing Test (Dry Run)
Write-Host "[TEST 10] Testing XAML Parsing (Dry Run)..." -ForegroundColor Gray
try {
    $env:MB_VALIDATION_MODE = "1"
    
    # Extract XAML from script
    $guiContent = Get-Content $guiScriptPath -Raw
    $xamlStart = $guiContent.IndexOf('$XAML = @"')
    $xamlEnd = $guiContent.IndexOf('"@', $xamlStart)
    
    if ($xamlStart -ne -1 -and $xamlEnd -ne -1) {
        $xamlContent = $guiContent.Substring($xamlStart + 10, $xamlEnd - $xamlStart - 10)
        
        # Try to parse XAML
        try {
            $xmlReader = New-Object System.Xml.XmlNodeReader([xml]$xamlContent)
            $null = [Windows.Markup.XamlReader]::Load($xmlReader)
            $xmlReader.Close()
            Add-TestResult -TestName "XAML Parsing" -Passed $true -Message "XAML parsed successfully"
        } catch {
            Add-TestResult -TestName "XAML Parsing" -Passed $false -Message "XAML parsing failed: $_"
        }
    } else {
        Add-TestResult -TestName "XAML Parsing" -Passed $false -Message "Could not extract XAML from script"
    }
} catch {
    Add-TestResult -TestName "XAML Parsing Test" -Passed $false -Message "Failed to test XAML parsing: $_"
}

# Test 11: Dependencies Check
Write-Host "[TEST 11] Checking Dependencies..." -ForegroundColor Gray
$dependencies = @(
    @{ Path = "Helper\WinRepairCore.ps1"; Name = "Core Engine" },
    @{ Path = "Helper\RepairReportGenerator.ps1"; Name = "Report Generator" },
    @{ Path = "EMERGENCY_BOOT1.cmd"; Name = "Emergency Boot 1" },
    @{ Path = "EMERGENCY_BOOT2.cmd"; Name = "Emergency Boot 2" },
    @{ Path = "EMERGENCY_BOOT3.cmd"; Name = "Emergency Boot 3" },
    @{ Path = "EMERGENCY_BOOT4.cmd"; Name = "Emergency Boot 4" },
    @{ Path = "FIX_BCD_NOT_FOUND.cmd"; Name = "Fix BCD Not Found" }
)

foreach ($dep in $dependencies) {
    # Try multiple possible locations
    $depPath = $null
    $found = $false
    
    # Try 1: Direct path from scriptRoot
    $tryPath1 = Join-Path $scriptRoot $dep.Path
    if (Test-Path $tryPath1) {
        $depPath = $tryPath1
        $found = $true
    } else {
        # Try 2: If Helper\Helper, try just Helper
        if ($dep.Path -match "^Helper\\(.+)") {
            $tryPath2 = Join-Path $scriptRoot "Helper\$($matches[1])"
            if (Test-Path $tryPath2) {
                $depPath = $tryPath2
                $found = $true
            }
        }
        # Try 3: For .cmd files, try root
        if (-not $found -and $dep.Path -match "\.cmd$") {
            $tryPath3 = Join-Path $scriptRoot (Split-Path -Leaf $dep.Path)
            if (Test-Path $tryPath3) {
                $depPath = $tryPath3
                $found = $true
            }
        }
    }
    
    if ($found) {
        Add-TestResult -TestName "Dependency: $($dep.Name)" -Passed $true -Message "Found at: $depPath"
    } else {
        Add-TestResult -TestName "Dependency: $($dep.Name)" -Passed $false -Message "Not found. Checked: $tryPath1" -Warning "This may cause runtime errors"
    }
}

# Test 12: Registry Access Check
Write-Host "[TEST 12] Checking Registry Access..." -ForegroundColor Gray
try {
    $regPath = "HKCU:\Software\MiracleBoot"
    $testValue = "TestValue_$(Get-Random)"
    
    if (-not (Test-Path $regPath)) {
        $null = New-Item -Path $regPath -Force -ErrorAction SilentlyContinue
    }
    
    Set-ItemProperty -Path $regPath -Name "QATest" -Value $testValue -ErrorAction Stop
    $readValue = (Get-ItemProperty -Path $regPath -Name "QATest" -ErrorAction SilentlyContinue).QATest
    
    if ($readValue -eq $testValue) {
        Remove-ItemProperty -Path $regPath -Name "QATest" -ErrorAction SilentlyContinue
        Add-TestResult -TestName "Registry Access" -Passed $true -Message "Can read/write to registry"
    } else {
        Add-TestResult -TestName "Registry Access" -Passed $false -Message "Registry write succeeded but read failed"
    }
} catch {
    Add-TestResult -TestName "Registry Access" -Passed $false -Message "Registry access failed: $_" -Warning "Settings preferences may not be saved"
}

# Summary
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  QA PANEL SUMMARY" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $($testResults.Tests.Count)" -ForegroundColor White
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -eq 0) { "Green" } else { "Red" })
Write-Host "Warnings: $($testResults.Warnings)" -ForegroundColor $(if ($testResults.Warnings -eq 0) { "Green" } else { "Yellow" })
Write-Host ""

if ($testResults.Failed -eq 0) {
    Write-Host "✅ ALL TESTS PASSED - GUI IS READY" -ForegroundColor Green
    Write-Host ""
    exit 0
} else {
    Write-Host "❌ SOME TESTS FAILED - GUI MAY NOT WORK CORRECTLY" -ForegroundColor Red
    Write-Host ""
    Write-Host "Failed Tests:" -ForegroundColor Yellow
    $testResults.Tests | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "  - $($_.TestName): $($_.Message)" -ForegroundColor Yellow
    }
    Write-Host ""
    exit 1
}
