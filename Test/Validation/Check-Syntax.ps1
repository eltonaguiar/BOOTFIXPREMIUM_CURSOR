param([string]$FilePath)

$content = Get-Content $FilePath -Raw
$errors = $null
[System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)

if ($errors.Count -gt 0) {
    Write-Host "Found $($errors.Count) syntax errors in $FilePath" -ForegroundColor Red
    $errors | Select-Object -First 10 | ForEach-Object {
        Write-Host "  Line $($_.Token.StartLine), Col $($_.Token.StartColumn): $($_.Message)" -ForegroundColor Yellow
    }
    exit 1
} else {
    Write-Host "No syntax errors in $FilePath" -ForegroundColor Green
    exit 0
}

