# Quick syntax validation script
param([string]$FilePath)

$content = Get-Content $FilePath -Raw -Encoding UTF8
$errors = @()
$null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)

if ($errors.Count -gt 0) {
    Write-Host "Syntax errors found:" -ForegroundColor Red
    foreach ($error in $errors) {
        Write-Host "Line $($error.Token.StartLine) Char $($error.Token.StartColumn): $($error.Message)" -ForegroundColor Red
        # Show the problematic line
        $lines = $content -split "`r?`n"
        if ($error.Token.StartLine -le $lines.Count) {
            $lineNum = $error.Token.StartLine - 1
            Write-Host "  $($lines[$lineNum])" -ForegroundColor Yellow
        }
    }
    exit 1
} else {
    Write-Host "No syntax errors found" -ForegroundColor Green
    exit 0
}
