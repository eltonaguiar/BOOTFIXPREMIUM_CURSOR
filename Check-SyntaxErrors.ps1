$content = Get-Content 'Helper\WinRepairGUI.ps1' -Raw
$errors = $null
[System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors) | Out-Null
$errors | Where-Object { $_.Token.StartLine -eq 3872 -or $_.Token.StartLine -eq 6354 } | Format-List
