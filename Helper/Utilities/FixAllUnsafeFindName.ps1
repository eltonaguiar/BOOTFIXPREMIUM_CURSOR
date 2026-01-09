# FixAllUnsafeFindName.ps1
# Script to fix all unsafe FindName().Add_Click() calls in WinRepairGUI.ps1

$guiFile = "Helper\WinRepairGUI.ps1"
$content = Get-Content $guiFile -Raw

# Pattern: $W.FindName("ControlName").Add_Click({
$pattern = '\$W\.FindName\(["\']([^"\']+)["\']\)\.Add_Click\(\{'

$matches = [regex]::Matches($content, $pattern)

Write-Host "Found $($matches.Count) unsafe FindName().Add_Click() calls" -ForegroundColor Yellow

# Process in reverse order to preserve line numbers
for ($i = $matches.Count - 1; $i -ge 0; $i--) {
    $match = $matches[$i]
    $controlName = $match.Groups[1].Value
    
    # Find the matching closing brace for this Add_Click block
    $startPos = $match.Index + $match.Length
    $braceCount = 1
    $endPos = $startPos
    $inString = $false
    $stringChar = $null
    
    while ($braceCount -gt 0 -and $endPos -lt $content.Length) {
        $char = $content[$endPos]
        
        if (-not $inString) {
            if ($char -eq '"' -or $char -eq "'") {
                $inString = $true
                $stringChar = $char
            } elseif ($char -eq '{') {
                $braceCount++
            } elseif ($char -eq '}') {
                $braceCount--
            }
        } else {
            if ($char -eq $stringChar -and ($endPos -eq 0 -or $content[$endPos-1] -ne '\')) {
                $inString = $false
                $stringChar = $null
            }
        }
        
        $endPos++
    }
    
    if ($braceCount -eq 0) {
        $handlerBlock = $content.Substring($startPos, $endPos - $startPos - 1)
        
        # Create safe version
        $safeVersion = @"
`$btn$($controlName.Replace('Btn', '')) = Get-Control -Name "$controlName"
if (`$btn$($controlName.Replace('Btn', ''))) {
    `$btn$($controlName.Replace('Btn', '')).Add_Click({
$handlerBlock
    })
}
"@
        
        # Replace the unsafe call
        $oldText = $match.Value + $handlerBlock + "}"
        $content = $content.Substring(0, $match.Index) + $safeVersion + $content.Substring($endPos)
        
        Write-Host "Fixed: $controlName" -ForegroundColor Green
    }
}

# Save the fixed content
Set-Content -Path $guiFile -Value $content -NoNewline
Write-Host "`nAll unsafe FindName calls have been fixed!" -ForegroundColor Cyan






