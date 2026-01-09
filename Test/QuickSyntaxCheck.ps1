# Quick Syntax Check
$ErrorActionPreference = 'Stop'
$scripts = @("MiracleBoot.ps1", "Helper\WinRepairCore.ps1", "Helper\WinRepairGUI.ps1", "Helper\WinRepairTUI.ps1")
$allPassed = $true

foreach ($script in $scripts) {
    if (-not (Test-Path $script)) {
        Write-Host "[FAIL] $script - File not found" -ForegroundColor Red
        $allPassed = $false
        continue
    }
    
    try {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script -Raw), [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-Host "[PASS] $script" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] $script - $($errors.Count) error(s)" -ForegroundColor Red
            $errors | Select-Object -First 3 | ForEach-Object {
                Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Yellow
            }
            $allPassed = $false
        }
    } catch {
        Write-Host "[FAIL] $script - Exception: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
}

if ($allPassed) {
    Write-Host "`nALL SYNTAX CHECKS PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSYNTAX ERRORS DETECTED!" -ForegroundColor Red
    exit 1
}
