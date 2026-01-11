# Fix-NullFindNameCalls.ps1
# Script to find and fix all direct FindName calls without null checking

$guiFile = "Helper\WinRepairGUI.ps1"
$content = Get-Content $guiFile -Raw

# Pattern: $W.FindName("ControlName").Property
$pattern = '\$W\.FindName\([''"]([^''"]+)[''"]\)\.(\w+)'

$matches = [regex]::Matches($content, $pattern)

Write-Host "Found $($matches.Count) direct FindName calls without null checking:" -ForegroundColor Yellow
Write-Host ""

foreach ($match in $matches) {
    $controlName = $match.Groups[1].Value
    $property = $match.Groups[2].Value
    $lineNum = ($content.Substring(0, $match.Index) -split "`r?`n").Count
    
    Write-Host "Line ~$lineNum : `$W.FindName(`"$controlName`").$property" -ForegroundColor Red
    Write-Host "  Should be: `$control = Get-Control `"$controlName`"; if (`$control) { `$control.$property = ... }" -ForegroundColor Green
    Write-Host ""
}

Write-Host "Total unsafe calls: $($matches.Count)" -ForegroundColor Cyan

