# FixAllUnsafeFindNameComprehensive.ps1
# Comprehensive fix for all unsafe FindName calls in WinRepairGUI.ps1

$guiFile = "Helper\WinRepairGUI.ps1"
$content = Get-Content $guiFile -Raw

Write-Host "Fixing unsafe FindName calls..." -ForegroundColor Cyan

# Pattern 1: $W.FindName("X").Property = value (assignment)
# Replace with: $control = Get-Control "X"; if ($control) { $control.Property = value }
$pattern1 = [regex]::Escape('$W.FindName(') + '([''")([^''"]+)\1\)\.(\w+)\s*='
$replacements1 = [regex]::Matches($content, $pattern1)
Write-Host "Found $($replacements1.Count) unsafe property assignments" -ForegroundColor Yellow

# Pattern 2: $W.FindName("X").Property (read access)
# Replace with: $control = Get-Control "X"; if ($control) { $control.Property }
$pattern2 = [regex]::Escape('$W.FindName(') + '([''")([^''"]+)\1\)\.(\w+)(?!\s*=)'
$replacements2 = [regex]::Matches($content, $pattern2)
Write-Host "Found $($replacements2.Count) unsafe property reads" -ForegroundColor Yellow

# Pattern 3: $W.FindName("X").Method(...) (method calls)
$pattern3 = [regex]::Escape('$W.FindName(') + '([''")([^''"]+)\1\)\.(\w+)\('
$replacements3 = [regex]::Matches($content, $pattern3)
Write-Host "Found $($replacements3.Count) unsafe method calls" -ForegroundColor Yellow

# We need to process in reverse order to preserve positions
$allMatches = @()
foreach ($match in $replacements1) {
    $allMatches += [PSCustomObject]@{ Type = 'Assignment'; Match = $match; Control = $match.Groups[2].Value; Property = $match.Groups[3].Value }
}
foreach ($match in $replacements2) {
    # Skip if already in assignments
    if (-not ($allMatches | Where-Object { $_.Match.Index -eq $match.Index })) {
        $allMatches += [PSCustomObject]@{ Type = 'Read'; Match = $match; Control = $match.Groups[2].Value; Property = $match.Groups[3].Value }
    }
}
foreach ($match in $replacements3) {
    # Skip if already processed
    if (-not ($allMatches | Where-Object { $_.Match.Index -eq $match.Index })) {
        $allMatches += [PSCustomObject]@{ Type = 'Method'; Match = $match; Control = $match.Groups[2].Value; Property = $match.Groups[3].Value }
    }
}

# Sort by position (reverse order for safe replacement)
$allMatches = $allMatches | Sort-Object { $_.Match.Index } -Descending

$fixedCount = 0
foreach ($item in $allMatches) {
    $match = $item.Match
    $controlName = $item.Control
    $property = $item.Property
    $varName = $controlName -replace '[^a-zA-Z0-9]', '_'
    
    # Get the full line context to understand the pattern better
    $lineStart = $content.LastIndexOf("`n", $match.Index) + 1
    $lineEnd = $content.IndexOf("`n", $match.Index)
    if ($lineEnd -eq -1) { $lineEnd = $content.Length }
    $line = $content.Substring($lineStart, $lineEnd - $lineStart)
    
    # Skip if already using Get-Control
    if ($line -match 'Get-Control') {
        continue
    }
    
    # For assignments: $W.FindName("X").Text = "value"
    if ($item.Type -eq 'Assignment') {
        # Find where the assignment ends (semicolon or newline)
        $assignEnd = $match.Index + $match.Length
        $restOfLine = $content.Substring($assignEnd)
        $valueEnd = $restOfLine.IndexOf("`n")
        if ($valueEnd -eq -1) { $valueEnd = $restOfLine.Length }
        $fullAssignment = $content.Substring($match.Index, $match.Length + $valueEnd)
        
        # Create safe version
        $safeVar = "`$ctrl_$varName"
        $safeCode = "$safeVar = Get-Control -Name `"$controlName`"`n"
        $safeCode += "if ($safeVar) { "
        $safeCode += $fullAssignment -replace '\$W\.FindName\(([''"])' + [regex]::Escape($controlName) + '\1\)\.' + [regex]::Escape($property), "$safeVar.$property"
        $safeCode += " }"
        
        $content = $content.Substring(0, $match.Index) + $safeCode + $content.Substring($match.Index + $match.Length + $valueEnd)
        $fixedCount++
    }
    # For reads: $W.FindName("X").Text
    elseif ($item.Type -eq 'Read') {
        # This is more complex - need to see the context
        # For now, just wrap in null check
        $safeVar = "`$ctrl_$varName"
        $safeCode = "(`$tempCtrl = Get-Control -Name `"$controlName`"; if (`$tempCtrl) { `$tempCtrl.$property } else { `$null })"
        
        $content = $content.Substring(0, $match.Index) + $safeCode + $content.Substring($match.Index + $match.Length)
        $fixedCount++
    }
}

Write-Host "Fixed $fixedCount unsafe calls" -ForegroundColor Green
Write-Host "Saving fixed file..." -ForegroundColor Cyan

# Save backup first
$backupFile = "$guiFile.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $guiFile $backupFile
Write-Host "Backup saved to: $backupFile" -ForegroundColor Gray

Set-Content -Path $guiFile -Value $content -NoNewline
Write-Host "Fixed file saved!" -ForegroundColor Green

