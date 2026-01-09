# Test-RuntimeModuleLoad.ps1
# Validates that modules can actually be LOADED at runtime, not just parsed
# This catches encoding issues, missing dependencies, and other runtime problems

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "RUNTIME MODULE LOAD VALIDATION" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$modules = @(
    @{ Name = "WinRepairCore.ps1"; Path = "Helper\WinRepairCore.ps1"; Functions = @("Get-WindowsVolumes", "Get-EnvironmentType") },
    @{ Name = "NetworkDiagnostics.ps1"; Path = "Helper\NetworkDiagnostics.ps1"; Functions = @("Test-NetworkAvailability") },
    @{ Name = "KeyboardSymbols.ps1"; Path = "Helper\KeyboardSymbols.ps1"; Functions = @() },
    @{ Name = "LogAnalysis.ps1"; Path = "Helper\LogAnalysis.ps1"; Functions = @("Get-ComprehensiveLogAnalysis", "Get-Tier1CrashDumps") },
    @{ Name = "WinRepairTUI.ps1"; Path = "Helper\WinRepairTUI.ps1"; Functions = @("Start-TUI") },
    @{ Name = "WinRepairGUI.ps1"; Path = "Helper\WinRepairGUI.ps1"; Functions = @("Start-GUI") }
)

$allPassed = $true
$results = @()

foreach ($module in $modules) {
    $fullPath = Join-Path $scriptRoot $module.Path
    Write-Host "Testing: $($module.Name)..." -NoNewline -ForegroundColor Yellow
    
    if (-not (Test-Path $fullPath)) {
        Write-Host " FAILED (file not found)" -ForegroundColor Red
        $results += [PSCustomObject]@{ Module = $module.Name; Status = "FAILED"; Error = "File not found: $fullPath" }
        $allPassed = $false
        continue
    }
    
    try {
        # Clear any previous errors
        $Error.Clear()
        
        # Try to load the module
        . $fullPath
        
        # Check if expected functions exist
        $missingFunctions = @()
        foreach ($funcName in $module.Functions) {
            $cmd = Get-Command $funcName -ErrorAction SilentlyContinue
            if (-not $cmd) {
                $missingFunctions += $funcName
            }
        }
        
        if ($missingFunctions.Count -gt 0) {
            Write-Host " FAILED (missing functions: $($missingFunctions -join ', '))" -ForegroundColor Red
            $results += [PSCustomObject]@{ Module = $module.Name; Status = "FAILED"; Error = "Missing functions: $($missingFunctions -join ', ')" }
            $allPassed = $false
        } elseif ($Error.Count -gt 0) {
            $errorMsg = ($Error | Select-Object -First 1).ToString()
            Write-Host " FAILED (errors during load)" -ForegroundColor Red
            Write-Host "  Error: $errorMsg" -ForegroundColor Yellow
            $results += [PSCustomObject]@{ Module = $module.Name; Status = "FAILED"; Error = $errorMsg }
            $allPassed = $false
        } else {
            Write-Host " PASSED" -ForegroundColor Green
            $results += [PSCustomObject]@{ Module = $module.Name; Status = "PASSED"; Error = $null }
        }
        
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
        $results += [PSCustomObject]@{ Module = $module.Name; Status = "FAILED"; Error = $_.Exception.Message }
        $allPassed = $false
    }
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$passed = ($results | Where-Object { $_.Status -eq "PASSED" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAILED" }).Count

Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($failed -gt 0) {
    Write-Host "FAILED MODULES:" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
        Write-Host "  - $($_.Module): $($_.Error)" -ForegroundColor Red
    }
    Write-Host ""
}

if ($allPassed) {
    Write-Host "All modules loaded successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some modules failed to load. Fix errors before proceeding." -ForegroundColor Red
    exit 1
}


