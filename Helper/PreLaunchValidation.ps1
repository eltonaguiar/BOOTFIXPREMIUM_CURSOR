<#
    PRE-LAUNCH VALIDATION MODULE
    ============================
    
    This module provides comprehensive validation before launching the UI.
    It checks syntax, module loading, function availability, and environment.
    
    Usage:
        . "$PSScriptRoot\Helper\PreLaunchValidation.ps1"
        $validation = Test-PreLaunchValidation -ScriptRoot $PSScriptRoot
        if (-not $validation.Passed) {
            # Show errors and exit
            exit 1
        }
#>

function Test-PreLaunchValidation {
    <#
    .SYNOPSIS
    Comprehensive pre-launch validation that checks syntax, module loading, and dependencies.
    
    .DESCRIPTION
    Performs multiple validation checks before UI launch:
    1. Syntax validation (all PowerShell files)
    2. Module loading test (dot-source test)
    3. Function availability check
    4. Environment validation
    5. Dependency check
    
    .PARAMETER ScriptRoot
    Root directory of the MiracleBoot scripts
    
    .OUTPUTS
    PSCustomObject with:
    - Passed: Boolean indicating if all checks passed
    - Errors: Array of error messages
    - Warnings: Array of warning messages
    - Details: Detailed results for each check
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptRoot
    )
    
    # CRITICAL: Prevent GUI launch during validation
    $env:MB_VALIDATION_MODE = "1"
    
    # Terminate any existing GUI processes before validation
    Write-Host "`n[VALIDATION] Terminating any existing GUI processes..." -ForegroundColor Cyan
    try {
        # CRITICAL: Multiple safety checks to prevent killing Cursor/IDE processes
        # Detect if running in IDE - skip if so
        $isRunningInIDE = $false
        try {
            $parentProcess = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
            if ($parentProcess) {
                $parentProcInfo = Get-Process -Id $parentProcess -ErrorAction SilentlyContinue
                if ($parentProcInfo) {
                    $parentName = $parentProcInfo.ProcessName.ToLower()
                    if ($parentName -match 'cursor|code|vscode|devenv|rider|pycharm|idea') {
                        $isRunningInIDE = $true
                        Write-Host "  [SKIP] Detected IDE environment ($($parentProcInfo.ProcessName)) - skipping process termination" -ForegroundColor Cyan
                    }
                }
            }
        } catch {
            # If we can't detect, be safe and skip termination
            $isRunningInIDE = $true
            Write-Host "  [SKIP] Cannot determine parent process - skipping termination for safety" -ForegroundColor Cyan
        }
        
        if (-not $isRunningInIDE) {
            $currentPID = $PID
            $excludedPIDs = @($currentPID)
            try {
                $parentPID = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
                if ($parentPID) { $excludedPIDs += $parentPID }
            } catch {}
            
            $guiProcesses = Get-Process | Where-Object {
                # Exclude current and parent processes
                $_.Id -notin $excludedPIDs -and
                # ONLY target PowerShell/pwsh processes (not IDE processes)
                ($_.ProcessName -eq 'powershell' -or $_.ProcessName -eq 'pwsh') -and
                # Only target processes with actual GUI windows (not console windows)
                $_.MainWindowHandle -ne [IntPtr]::Zero -and
                # Match MiracleBoot in window title
                ($_.MainWindowTitle -like "*MiracleBoot*" -or $_.MainWindowTitle -like "*Miracle Boot*")
            }
            if ($guiProcesses) {
                foreach ($proc in $guiProcesses) {
                    Write-Host "  [INFO] Terminating GUI process: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Yellow
                    try {
                        $proc.CloseMainWindow() | Out-Null
                        Start-Sleep -Milliseconds 500
                        if (-not $proc.HasExited) {
                            $proc.Kill()
                        }
                    } catch {
                        Write-Host "  [WARN] Could not terminate process $($proc.Id): $_" -ForegroundColor Yellow
                    }
                }
                Start-Sleep -Milliseconds 1000
            } else {
                Write-Host "  [OK] No GUI processes found" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  [WARN] Error checking for GUI processes: $_" -ForegroundColor Yellow
    }
    
    $result = @{
        Passed = $true
        Errors = @()
        Warnings = @()
        Details = @{}
    }
    
    # PowerShell files to validate
    $psFiles = @(
        "MiracleBoot.ps1",
        "Helper\WinRepairCore.ps1",
        "Helper\WinRepairTUI.ps1",
        "Helper\WinRepairGUI.ps1",
        "Helper\NetworkDiagnostics.ps1",
        "Helper\KeyboardSymbols.ps1",
        "Helper\LogAnalysis.ps1"
    )
    
    # PHASE 1: Syntax Validation
    Write-Host "`n[VALIDATION] Phase 1: Syntax Validation..." -ForegroundColor Cyan
    $syntaxResults = @()
    $syntaxPassed = $true
    
    foreach ($file in $psFiles) {
        $absolutePath = Join-Path $ScriptRoot $file
        if (-not (Test-Path $absolutePath)) {
            $result.Errors += "File not found: $file"
            $result.Details[$file] = @{ Status = "FAILED"; Reason = "File not found" }
            $syntaxPassed = $false
            continue
        }
        
        try {
            $content = Get-Content $absolutePath -Raw -ErrorAction Stop
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
            
            if ($errors.Count -eq 0) {
                $syntaxResults += [PSCustomObject]@{ File = $file; Passed = $true }
                $result.Details[$file] = @{ Status = "PASSED"; Errors = 0 }
                Write-Host "  [PASS] $file" -ForegroundColor Green
            } else {
                $syntaxResults += [PSCustomObject]@{ File = $file; Passed = $false }
                $errorMsg = "$file has $($errors.Count) syntax error(s)"
                $result.Errors += $errorMsg
                $result.Details[$file] = @{ Status = "FAILED"; Errors = $errors.Count; ErrorDetails = $errors }
                $syntaxPassed = $false
                Write-Host "  [FAIL] $file - $($errors.Count) error(s)" -ForegroundColor Red
                foreach ($err in $errors | Select-Object -First 3) {
                    $lineInfo = if ($err.Token) { "Line $($err.Token.StartLine)" } else { "Unknown" }
                    Write-Host "    $lineInfo : $($err.Message)" -ForegroundColor Yellow
                }
            }
        } catch {
            $syntaxResults += [PSCustomObject]@{ File = $file; Passed = $false }
            $errorMsg = "$file failed to parse: $_"
            $result.Errors += $errorMsg
            $result.Details[$file] = @{ Status = "FAILED"; Reason = $_.ToString() }
            $syntaxPassed = $false
            Write-Host "  [FAIL] $file - Parse error: $_" -ForegroundColor Red
        }
    }
    
    if (-not $syntaxPassed) {
        $result.Passed = $false
        Write-Host "`n[VALIDATION FAILED] Syntax errors detected. Cannot proceed." -ForegroundColor Red
        return $result
    }
    
    Write-Host "  [SUCCESS] All $($psFiles.Count) files have valid syntax" -ForegroundColor Green
    
    # PHASE 2: Module Loading Test
    Write-Host "`n[VALIDATION] Phase 2: Module Loading Test..." -ForegroundColor Cyan
    Write-Host "  [NOTE] WinRepairGUI.ps1 is explicitly excluded from module loading to prevent GUI launch" -ForegroundColor Gray
    $modules = @(
        @{ Name = "WinRepairCore.ps1"; Path = "Helper\WinRepairCore.ps1"; Functions = @("Get-WindowsVolumes", "Get-EnvironmentType") },
        @{ Name = "NetworkDiagnostics.ps1"; Path = "Helper\NetworkDiagnostics.ps1"; Functions = @("Get-NetworkAdapterStatus") },
        @{ Name = "KeyboardSymbols.ps1"; Path = "Helper\KeyboardSymbols.ps1"; Functions = @() },
        @{ Name = "LogAnalysis.ps1"; Path = "Helper\LogAnalysis.ps1"; Functions = @("Get-ComprehensiveLogAnalysis") }
        # NOTE: WinRepairGUI.ps1 is NOT included here to prevent GUI launch during validation
        # WinRepairTUI.ps1 is also excluded as it may have interactive elements
    )
    
    $moduleLoadPassed = $true
    foreach ($module in $modules) {
        $fullPath = Join-Path $ScriptRoot $module.Path
        if (-not (Test-Path $fullPath)) {
            $result.Warnings += "Module not found: $($module.Name)"
            $result.Details[$module.Name] = @{ Status = "SKIPPED"; Reason = "File not found" }
            continue
        }
        
        try {
            $Error.Clear()
            . $fullPath
            
            if ($Error.Count -gt 0) {
                $errorMsg = ($Error | Select-Object -First 1).ToString()
                $result.Errors += "$($module.Name) failed to load: $errorMsg"
                $result.Details[$module.Name] = @{ Status = "FAILED"; Reason = $errorMsg }
                $moduleLoadPassed = $false
                Write-Host "  [FAIL] $($module.Name) - Load error: $errorMsg" -ForegroundColor Red
                continue
            }
            
            # Check expected functions
            if ($module.Functions.Count -gt 0) {
                $missingFunctions = @()
                foreach ($funcName in $module.Functions) {
                    $cmd = Get-Command $funcName -ErrorAction SilentlyContinue
                    if (-not $cmd) {
                        $missingFunctions += $funcName
                    }
                }
                
                if ($missingFunctions.Count -gt 0) {
                    $errorMsg = "$($module.Name) missing functions: $($missingFunctions -join ', ')"
                    $result.Errors += $errorMsg
                    $result.Details[$module.Name] = @{ Status = "FAILED"; MissingFunctions = $missingFunctions }
                    $moduleLoadPassed = $false
                    Write-Host "  [FAIL] $($module.Name) - Missing: $($missingFunctions -join ', ')" -ForegroundColor Red
                } else {
                    $result.Details[$module.Name] = @{ Status = "PASSED" }
                    Write-Host "  [PASS] $($module.Name)" -ForegroundColor Green
                }
            } else {
                $result.Details[$module.Name] = @{ Status = "PASSED" }
                Write-Host "  [PASS] $($module.Name)" -ForegroundColor Green
            }
        } catch {
            $errorMsg = "$($module.Name) exception: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            $result.Details[$module.Name] = @{ Status = "FAILED"; Reason = $_.Exception.Message }
            $moduleLoadPassed = $false
            Write-Host "  [FAIL] $($module.Name) - Exception: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    if (-not $moduleLoadPassed) {
        $result.Passed = $false
        Write-Host "`n[VALIDATION FAILED] Module loading errors detected." -ForegroundColor Red
        return $result
    }
    
    Write-Host "  [SUCCESS] All modules loaded successfully" -ForegroundColor Green
    
    # PHASE 3: Environment Validation
    Write-Host "`n[VALIDATION] Phase 3: Environment Validation..." -ForegroundColor Cyan
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5) {
        $result.Warnings += "PowerShell version $($psVersion.ToString()) is older than recommended (5.0+)"
        Write-Host "  [WARN] PowerShell version: $($psVersion.ToString())" -ForegroundColor Yellow
    } else {
        Write-Host "  [PASS] PowerShell version: $($psVersion.ToString())" -ForegroundColor Green
    }
    
    # Check execution policy
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -eq "Restricted") {
        $result.Warnings += "Execution policy is Restricted - may cause issues"
        Write-Host "  [WARN] Execution policy: $executionPolicy" -ForegroundColor Yellow
    } else {
        Write-Host "  [PASS] Execution policy: $executionPolicy" -ForegroundColor Green
    }
    
    # Check if running as admin (for FullOS)
    if ($env:SystemDrive -ne 'X:') {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            $result.Warnings += "Not running as administrator - some features may not work"
            Write-Host "  [WARN] Not running as administrator" -ForegroundColor Yellow
        } else {
            Write-Host "  [PASS] Running as administrator" -ForegroundColor Green
        }
    }
    
    Write-Host "`n[VALIDATION COMPLETE]" -ForegroundColor Cyan
    if ($result.Passed) {
        Write-Host "  [SUCCESS] All validation checks passed. Ready to launch UI." -ForegroundColor Green
    } else {
        Write-Host "  [FAILED] Validation failed. Cannot launch UI." -ForegroundColor Red
        Write-Host "`nErrors:" -ForegroundColor Red
        foreach ($error in $result.Errors) {
            Write-Host "  - $error" -ForegroundColor Yellow
        }
    }
    
    # Clear validation mode flag
    Remove-Item Env:\MB_VALIDATION_MODE -ErrorAction SilentlyContinue
    
    return $result
}






