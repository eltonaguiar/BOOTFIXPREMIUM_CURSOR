# Quick parser validation for critical files
$files = @(
    'Helper\WinRepairCore.ps1',
    'Helper\WinRepairTUI.ps1'
)

foreach ($f in $files) {
    Write-Host "`n=== $f ===" -ForegroundColor Cyan
    $errors = @()
    try {
        $content = Get-Content $f -Raw
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
        if ($errors.Count -eq 0) {
            Write-Host "PARSER: VALID (0 errors)" -ForegroundColor Green
        } else {
            Write-Host "PARSER: FAIL ($($errors.Count) errors)" -ForegroundColor Red
            $errors | ForEach-Object {
                Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "PARSER: EXCEPTION - $_" -ForegroundColor Red
    }
}
