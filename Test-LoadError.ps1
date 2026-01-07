# Test-LoadError.ps1 - Reproduce the loading error
$ErrorActionPreference = 'Stop'

Write-Host "Testing WinRepairCore.ps1 load..." -ForegroundColor Cyan

try {
    # Try to load the file
    . "Helper\WinRepairCore.ps1" -ErrorAction Stop
    Write-Host "SUCCESS: File loaded without errors" -ForegroundColor Green
    exit 0
} catch {
    $errorLine = $_.InvocationInfo.ScriptLineNumber
    $errorChar = $_.InvocationInfo.OffsetInLine
    $errorMessage = $_.Exception.Message
    
    Write-Host ""
    Write-Host "ERROR DETECTED:" -ForegroundColor Red
    Write-Host "  Line: $errorLine" -ForegroundColor Red
    Write-Host "  Character: $errorChar" -ForegroundColor Red
    Write-Host "  Message: $errorMessage" -ForegroundColor Red
    
    if ($_.InvocationInfo.Line) {
        Write-Host ""
        Write-Host "Problematic line:" -ForegroundColor Yellow
        Write-Host $_.InvocationInfo.Line -ForegroundColor Yellow
        
        # Show character at error position
        if ($errorChar -gt 0 -and $errorChar -le $_.InvocationInfo.Line.Length) {
            $line = $_.InvocationInfo.Line
            $char = $line[$errorChar - 1]
            $charCode = [int][char]$char
            Write-Host ""
            Write-Host "Character at position $errorChar : '$char' (Unicode: U+$($charCode.ToString('X4')))" -ForegroundColor Yellow
        }
    }
    
    # Show context lines
    if (Test-Path "Helper\WinRepairCore.ps1") {
        $lines = Get-Content "Helper\WinRepairCore.ps1"
        $startLine = [Math]::Max(1, $errorLine - 3)
        $endLine = [Math]::Min($lines.Count, $errorLine + 3)
        
        Write-Host ""
        Write-Host "Context (lines $startLine - $endLine):" -ForegroundColor Cyan
        for ($i = $startLine - 1; $i -lt $endLine; $i++) {
            $lineNum = $i + 1
            $prefix = if ($lineNum -eq $errorLine) { ">>> " } else { "    " }
            $color = if ($lineNum -eq $errorLine) { "Red" } else { "Gray" }
            Write-Host "$prefix$lineNum`: $($lines[$i])" -ForegroundColor $color
        }
    }
    
    exit 1
}

