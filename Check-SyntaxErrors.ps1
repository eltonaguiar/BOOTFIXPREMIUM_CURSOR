# Check syntax errors in specific files
$files = @(
    'Helper\Utilities\FixAllUnsafeFindName.ps1',
    'Helper\Utilities\FixAllUnsafeFindNameComprehensive.ps1',
    'Helper\Utilities\Fix-NullFindNameCalls.ps1',
    'Helper\Utilities\FixUnsafeFindNameBulk.ps1',
    'MiracleBoot-Admin-Launcher.ps1'
)

foreach ($file in $files) {
    Write-Host "`n=== $file ===" -ForegroundColor Cyan
    if (-not (Test-Path $file)) {
        Write-Host "File not found" -ForegroundColor Red
        continue
    }
    
    $content = Get-Content $file -Raw
    $errs = $null
    [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errs) | Out-Null
    
    if ($errs -and $errs.Count -gt 0) {
        Write-Host "Errors found: $($errs.Count)" -ForegroundColor Red
        foreach ($err in $errs) {
            Write-Host "  Line $($err.Token.StartLine), Column $($err.Token.StartColumn): $($err.Message)" -ForegroundColor Yellow
            Write-Host "    Token: '$($err.Token.Content)'" -ForegroundColor Gray
        }
    } else {
        Write-Host "No syntax errors" -ForegroundColor Green
    }
}
