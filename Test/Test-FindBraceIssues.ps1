# Quick brace checker
$file = "Helper\WinRepairGUI.ps1"
$content = Get-Content $file -Raw
$lines = $content -split "`n"

$openBraces = 0
$openParens = 0
$lineNum = 0

foreach ($line in $lines) {
    $lineNum++
    $openBraces += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
    $openBraces -= ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
    $openParens += ($line.ToCharArray() | Where-Object { $_ -eq '(' }).Count
    $openParens -= ($line.ToCharArray() | Where-Object { $_ -eq ')' }).Count
    
    if ($openBraces -lt 0 -or $openParens -lt 0) {
        Write-Host "Line $lineNum : Unbalanced - Braces: $openBraces, Parens: $openParens" -ForegroundColor Yellow
    }
}

Write-Host "Final: Braces: $openBraces, Parens: $openParens" -ForegroundColor $(if ($openBraces -eq 0 -and $openParens -eq 0) { "Green" } else { "Red" })

