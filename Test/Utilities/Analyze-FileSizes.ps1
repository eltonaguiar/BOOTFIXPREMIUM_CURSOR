# Analyze file sizes and structure
$files = Get-ChildItem -Path $PSScriptRoot\.. -Recurse -Include *.ps1,*.cmd | Where-Object { $_.FullName -notmatch '\\Test\\' }

$results = @()
foreach ($f in $files) {
    $content = Get-Content $f.FullName -ErrorAction SilentlyContinue
    $lines = if ($content) { $content.Count } else { 0 }
    $functions = ($content | Select-String -Pattern '^function |^class |^enum ').Count
    $relativePath = $f.FullName.Replace((Split-Path $PSScriptRoot -Parent) + '\', '')
    
    $results += [PSCustomObject]@{
        File = $f.Name
        Path = $relativePath
        Lines = $lines
        Functions = $functions
        SizeKB = [math]::Round($f.Length/1KB, 2)
    }
}

$results | Sort-Object Lines -Descending | Format-Table -AutoSize
Write-Host "`nTotal files: $($results.Count)" -ForegroundColor Cyan
Write-Host "Total lines: $(($results | Measure-Object -Property Lines -Sum).Sum)" -ForegroundColor Cyan
Write-Host "Total functions: $(($results | Measure-Object -Property Functions -Sum).Sum)" -ForegroundColor Cyan

