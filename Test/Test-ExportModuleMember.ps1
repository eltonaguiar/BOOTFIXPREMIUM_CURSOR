<#
.SYNOPSIS
    Tests all Helper scripts for Export-ModuleMember issues
    
.DESCRIPTION
    Scans all PowerShell files in the Helper directory to ensure Export-ModuleMember
    calls are properly wrapped in module checks. This prevents errors when scripts
    are dot-sourced instead of imported as modules.
    
.NOTES
    Exit code 0 = All files pass
    Exit code 1 = Errors found
#>

$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Export-ModuleMember Validation Test" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$errors = @()
$filesChecked = 0
$filesWithExport = 0

$helperFiles = Get-ChildItem -Path (Join-Path $projectRoot "Helper") -Filter "*.ps1" -File | Where-Object { $_.Name -notmatch '\.backup' }

foreach ($file in $helperFiles) {
    $filesChecked++
    $content = Get-Content $file.FullName -Raw
    $fileRelative = $file.FullName.Replace($projectRoot + '\', '')
    
    # Check if file contains Export-ModuleMember
    if ($content -match 'Export-ModuleMember') {
        $filesWithExport++
        
        # Check if it's properly wrapped in module check
        # Pattern: if ($MyInvocation.MyCommand.ModuleName) { ... Export-ModuleMember ... }
        $hasModuleCheck = $content -match 'if\s*\(\s*\$MyInvocation\.MyCommand\.ModuleName\s*\)\s*\{[^}]*Export-ModuleMember'
        
        if (-not $hasModuleCheck) {
            # Find the exact line number
            $lines = Get-Content $file.FullName
            $lineNum = 0
            $foundLine = $null
            
            foreach ($line in $lines) {
                $lineNum++
                # Check if this line has Export-ModuleMember but not in a module check
                if ($line -match 'Export-ModuleMember') {
                    # Check if previous lines have the module check
                    $contextStart = [Math]::Max(1, $lineNum - 5)
                    $contextEnd = $lineNum
                    $context = ($lines[($contextStart-1)..($contextEnd-1)] -join "`n")
                    
                    if ($context -notmatch 'if\s*\(\s*\$MyInvocation\.MyCommand\.ModuleName\s*\)\s*\{') {
                        $foundLine = $lineNum
                        break
                    }
                }
            }
            
            if ($foundLine) {
                $errors += [PSCustomObject]@{
                    File = $fileRelative
                    Line = $foundLine
                    Message = "Export-ModuleMember not wrapped in module check"
                }
                Write-Host "  [FAIL] $fileRelative : Line $foundLine" -ForegroundColor Red
            } else {
                Write-Host "  [PASS] $fileRelative - Export-ModuleMember properly wrapped" -ForegroundColor Green
            }
        } else {
            Write-Host "  [PASS] $fileRelative - Export-ModuleMember properly wrapped" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Files Checked: $filesChecked" -ForegroundColor White
Write-Host "Files with Export-ModuleMember: $filesWithExport" -ForegroundColor White
Write-Host "Errors Found: $($errors.Count)" -ForegroundColor $(if ($errors.Count -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($errors.Count -gt 0) {
    Write-Host "Errors:" -ForegroundColor Red
    foreach ($error in $errors) {
        Write-Host "  - $($error.File) : Line $($error.Line)" -ForegroundColor Yellow
        Write-Host "    $($error.Message)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Fix Instructions:" -ForegroundColor Yellow
    Write-Host "  Wrap Export-ModuleMember in a module check:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  # Export function (only if running as a module)" -ForegroundColor Gray
    Write-Host "  # When dot-sourced, Export-ModuleMember will fail, so we check if we're in a module context" -ForegroundColor Gray
    Write-Host "  if (`$MyInvocation.MyCommand.ModuleName) {" -ForegroundColor Gray
    Write-Host "      Export-ModuleMember -Function ..." -ForegroundColor Gray
    Write-Host "  }" -ForegroundColor Gray
    Write-Host ""
    exit 1
} else {
    Write-Host "[SUCCESS] All Export-ModuleMember calls are properly wrapped!" -ForegroundColor Green
    Write-Host ""
    exit 0
}






