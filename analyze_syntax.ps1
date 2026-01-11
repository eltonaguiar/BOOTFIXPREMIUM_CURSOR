$file = 'Helper\WinRepairGUI.ps1'
$content = Get-Content $file -Raw
$syntaxErrors = $null
[System.Management.Automation.PSParser]::Tokenize($content, [ref]$syntaxErrors) | Out-Null

if ($syntaxErrors -and $syntaxErrors.Count -gt 0) {
    Write-Host "Found $($syntaxErrors.Count) syntax error(s) in $file"
    foreach ($err in $syntaxErrors) {
        if ($err.Token) {
            Write-Host "Line $($err.Token.StartLine): $($err.Message)"
        } else {
            Write-Host "Error: $($err.Message)"
        }
    }
} else {
    Write-Host "No syntax errors found"
}
