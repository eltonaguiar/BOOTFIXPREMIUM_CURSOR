# FixUnsafeFindNameBulk.ps1
# Bulk fix for unsafe FindName calls - simpler approach

$guiFile = "Helper\WinRepairGUI.ps1"
$content = Get-Content $guiFile -Raw

Write-Host "Fixing unsafe FindName calls..." -ForegroundColor Cyan

# Fix pattern: $W.FindName("ControlName").Property = value
# Replace with: $var = Get-Control "ControlName"; if ($var) { $var.Property = value }

# Common controls that need fixing
$controlsToFix = @(
    "LogAnalysisBox", "ErrorCodeInput", "LogDriveCombo", "DiagBox", "DiagDriveCombo",
    "FixerOutput", "DrvBox", "BCDBox", "DriveCombo", "EditId", "EditName", "EditDescription",
    "BCDList", "BCDPropertiesGrid", "SimList", "TxtTimeout", "TxtRebuildBCD", "TxtFixBoot",
    "TxtScanWindows", "TxtRebuildBCD2", "TxtSetDefault", "StatusBarText", "NetworkStatus",
    "TabControl"
)

$fixCount = 0

foreach ($controlName in $controlsToFix) {
    # Pattern: $W.FindName("ControlName").Property
    $pattern = '\$W\.FindName\("' + [regex]::Escape($controlName) + '"\)\.(\w+)'
    
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -gt 0) {
        Write-Host "Found $($matches.Count) unsafe calls for $controlName" -ForegroundColor Yellow
        
        # Process in reverse to preserve positions
        for ($i = $matches.Count - 1; $i -ge 0; $i--) {
            $match = $matches[$i]
            $property = $match.Groups[1].Value
            
            # Get context - check if it's an assignment or read
            $afterMatch = $content.Substring($match.Index + $match.Length, [Math]::Min(10, $content.Length - $match.Index - $match.Length))
            $isAssignment = $afterMatch -match '^\s*='
            
            # Get the line to understand context better
            $lineStart = $content.LastIndexOf("`n", [Math]::Max(0, $match.Index - 1)) + 1
            $lineEnd = $content.IndexOf("`n", $match.Index)
            if ($lineEnd -eq -1) { $lineEnd = $content.Length }
            $line = $content.Substring($lineStart, $lineEnd - $lineStart)
            
            # Skip if already using Get-Control
            if ($line -match 'Get-Control') {
                continue
            }
            
            # Create variable name
            $varName = "`$ctrl_" + ($controlName -replace '[^a-zA-Z0-9]', '_')
            
            if ($isAssignment) {
                # Assignment: $W.FindName("X").Text = "value"
                # Replace with: $var = Get-Control "X"; if ($var) { $var.Text = "value" }
                $valuePart = $content.Substring($match.Index + $match.Length)
                $valueEnd = $valuePart.IndexOf("`n")
                if ($valueEnd -eq -1) { $valueEnd = $valuePart.Length }
                $fullLine = $content.Substring($lineStart, $lineEnd - $lineStart)
                
                # Extract the assignment value
                $assignPattern = '=\s*(.+?)(?:\s*`n|$)'
                if ($fullLine -match $assignPattern) {
                    $value = $matches[0] -replace '^=\s*', ''
                    
                    # Create safe version
                    if ($line -match '^(\s+)') {
                        $indent = $matches[1]
                    } else {
                        $indent = ''
                    }
                    $safeCode = "$varName = Get-Control -Name `"$controlName`"`n$indent" + 
                                "if ($varName) {`n$indent    $varName.$property = $value`n$indent}"
                    
                    # Replace the unsafe call
                    $content = $content.Substring(0, $match.Index) + $safeCode + $content.Substring($match.Index + $match.Length + $valueEnd)
                    $fixCount++
                }
            } else {
                # Read access: $W.FindName("X").Text or $W.FindName("X").SelectedItem
                # For reads, we need to be more careful - replace inline
                $safeCode = "(($varName = Get-Control -Name `"$controlName`") ? $varName.$property : `$null)"
                $content = $content.Substring(0, $match.Index) + $safeCode + $content.Substring($match.Index + $match.Length)
                $fixCount++
            }
        }
    }
}

Write-Host "Fixed $fixCount unsafe calls" -ForegroundColor Green

# Save backup
$backupFile = "$guiFile.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $guiFile $backupFile
Write-Host "Backup: $backupFile" -ForegroundColor Gray

Set-Content -Path $guiFile -Value $content -NoNewline
Write-Host "Fixed file saved!" -ForegroundColor Green

