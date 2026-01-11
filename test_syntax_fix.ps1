$content = Get-Content 'Helper/WinRepairGUI.ps1' -Raw
$errors = $null
[System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host 'Syntax errors found:'
    $errors | Select-Object -First 5 | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }
    exit 1
} else {
    Write-Host 'Syntax OK - else block indentation fixed'
    exit 0
}
