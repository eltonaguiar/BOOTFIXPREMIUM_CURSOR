# Deep Syntax Audit - Senior PowerShell Engineer & QA Automation Architect
# Comprehensive parser-based validation with adversarial testing

param(
    [string]$LogDir = "$env:TEMP\miracleboot-deepaudit"
)

$ErrorActionPreference = 'Stop'
$global:AuditResults = @()

function Test-SyntaxWithParser {
    param([string]$FilePath)
    
    $errors = @()
    try {
        $content = Get-Content $FilePath -Raw -ErrorAction Stop
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
        
        return @{
            File = $FilePath
            Valid = ($errors.Count -eq 0)
            Errors = $errors
            LineCount = ($content -split "`n").Count
        }
    } catch {
        return @{
            File = $FilePath
            Valid = $false
            Errors = @([PSCustomObject]@{ Message = $_.Exception.Message; Token = $null })
            LineCount = 0
        }
    }
}

function Test-UnclosedBrackets {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $issues = @()
    
    # Check for unclosed brackets
    $openBraces = ([regex]::Matches($content, '\{')).Count
    $closeBraces = ([regex]::Matches($content, '\}')).Count
    if ($openBraces -ne $closeBraces) {
        $issues += "Brace mismatch: $openBraces open, $closeBraces close"
    }
    
    $openParens = ([regex]::Matches($content, '\(')).Count
    $closeParens = ([regex]::Matches($content, '\)')).Count
    if ($openParens -ne $closeParens) {
        $issues += "Parenthesis mismatch: $openParens open, $closeParens close"
    }
    
    $openSquare = ([regex]::Matches($content, '\[')).Count
    $closeSquare = ([regex]::Matches($content, '\]')).Count
    if ($openSquare -ne $closeSquare) {
        $issues += "Square bracket mismatch: $openSquare open, $closeSquare close"
    }
    
    return @{
        File = $FilePath
        Issues = $issues
        Valid = ($issues.Count -eq 0)
    }
}

function Test-UninitializedVariables {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $issues = @()
    
    # Find variable assignments
    $assignments = [regex]::Matches($content, '\$([a-zA-Z_][a-zA-Z0-9_]*)\s*=')
    $assignedVars = $assignments | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    
    # Find variable usages
    $usages = [regex]::Matches($content, '\$([a-zA-Z_][a-zA-Z0-9_]+)')
    $usedVars = $usages | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    
    # Check for common uninitialized patterns (non-exhaustive, heuristic)
    $commonUninit = @('result', 'output', 'data', 'temp', 'var')
    foreach ($var in $commonUninit) {
        if ($content -match "\$$var\s*[^=]" -and $content -notmatch "\$$var\s*=") {
            # Check if it's a parameter or global
            if ($content -notmatch "param.*\`$$var" -and $content -notmatch "\`$global:$var" -and $content -notmatch "\`$script:$var") {
                $issues += "Potential uninitialized variable: `$$var"
            }
        }
    }
    
    return @{
        File = $FilePath
        Issues = $issues
        Valid = ($issues.Count -eq 0)
    }
}

function Test-HardcodedPaths {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $issues = @()
    
    # Check for hardcoded C: drive (should use variables in WinPE)
    if ($content -match 'C:\\Windows[^"]' -and $content -notmatch '\$WindowsRoot' -and $content -notmatch '\$env:') {
        $issues += "Hardcoded C:\\Windows path found (may fail in WinPE)"
    }
    
    # Check for hardcoded X: drive (WinPE RAM disk)
    if ($content -match 'X:\\[^"]' -and $content -notmatch '\$env:' -and $content -notmatch 'WinPE') {
        $issues += "Hardcoded X: drive path found"
    }
    
    return @{
        File = $FilePath
        Issues = $issues
        Valid = ($issues.Count -eq 0)
    }
}

function Test-StringEscaping {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $lines = $content -split "`n"
    $issues = @()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNum = $i + 1
        
        # Check for unescaped quotes in double-quoted strings
        if ($line -match '"[^"]*"[^"]*"' -and $line -notmatch '`"' -and $line -notmatch "''") {
            # Might be an issue, but could be legitimate (like dictionary keys)
            # Only flag if it looks problematic
            if ($line -match '"([^"]*)"([^"]*)"([^"]*)"' -and $line -notmatch 'Here-String') {
                $issues += "Line $lineNum : Potential unescaped quote issue"
            }
        }
    }
    
    return @{
        File = $FilePath
        Issues = $issues
        Valid = ($issues.Count -eq 0)
    }
}

function Test-VariableColonIssues {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $issues = @()
    
    # Check for $variable: patterns that should be ${variable}:
    $problematic = [regex]::Matches($content, '\$([a-zA-Z_][a-zA-Z0-9_]*):\s')
    foreach ($match in $problematic) {
        $varName = $match.Groups[1].Value
        # Skip legitimate patterns like $env:, $global:, $script:, $local:
        if ($varName -notmatch '^(env|global|script|local|private|using)$') {
            $issues += "Variable colon issue: `$$varName`: should be `${$varName}:"
        }
    }
    
    return @{
        File = $FilePath
        Issues = $issues
        Valid = ($issues.Count -eq 0)
    }
}

function Test-GUIBlocking {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $issues = @()
    
    # Check for synchronous operations that could block GUI
    $blockingPatterns = @(
        'Start-Process.*-Wait',
        'Invoke-Command.*-Wait',
        'Start-Job.*Wait-Job',
        'Get-Content.*-Wait',
        'bcdedit.*\|.*Out-Null',
        'diskpart.*\|.*Out-Null'
    )
    
    foreach ($pattern in $blockingPatterns) {
        if ($content -match $pattern) {
            $issues += "Potential blocking operation: $pattern"
        }
    }
    
    # Check if GUI file uses async patterns
    if ($FilePath -match "GUI" -and $content -notmatch "Runspace" -and $content -notmatch "Start-Job" -and $content -notmatch "Dispatcher") {
        $issues += "GUI file may not use async patterns for long operations"
    }
    
    return @{
        File = $FilePath
        Issues = $issues
        Valid = ($issues.Count -eq 0)
    }
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "DEEP SYNTAX AUDIT" -ForegroundColor Magenta
Write-Host "Senior PowerShell Engineer & QA Automation" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

$psFiles = @(
    "MiracleBoot.ps1",
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\LogAnalysis.ps1",
    "Helper\PreLaunchValidation.ps1"
)

$allPassed = $true

foreach ($file in $psFiles) {
    if (-not (Test-Path $file)) {
        Write-Host "[SKIP] $file - File not found" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "`n=== Auditing: $file ===" -ForegroundColor Cyan
    
    # Test 1: Parser-based syntax validation
    $syntax = Test-SyntaxWithParser -FilePath $file
    if ($syntax.Valid) {
        Write-Host "[PASS] Parser syntax validation" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Parser syntax validation - $($syntax.Errors.Count) error(s)" -ForegroundColor Red
        $syntax.Errors | Select-Object -First 5 | ForEach-Object {
            Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Yellow
        }
        $allPassed = $false
    }
    $global:AuditResults += [PSCustomObject]@{
        File = $file
        Test = "ParserSyntax"
        Status = if ($syntax.Valid) { "PASS" } else { "FAIL" }
        Details = "$($syntax.Errors.Count) errors"
    }
    
    # Test 2: Unclosed brackets
    $brackets = Test-UnclosedBrackets -FilePath $file
    if ($brackets.Valid) {
        Write-Host "[PASS] Bracket matching" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Bracket matching" -ForegroundColor Red
        $brackets.Issues | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        $allPassed = $false
    }
    $global:AuditResults += [PSCustomObject]@{
        File = $file
        Test = "BracketMatching"
        Status = if ($brackets.Valid) { "PASS" } else { "FAIL" }
        Details = ($brackets.Issues -join "; ")
    }
    
    # Test 3: Variable colon issues
    $colon = Test-VariableColonIssues -FilePath $file
    if ($colon.Valid) {
        Write-Host "[PASS] Variable colon validation" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Variable colon validation" -ForegroundColor Red
        $colon.Issues | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        $allPassed = $false
    }
    $global:AuditResults += [PSCustomObject]@{
        File = $file
        Test = "VariableColon"
        Status = if ($colon.Valid) { "PASS" } else { "FAIL" }
        Details = ($colon.Issues -join "; ")
    }
    
    # Test 4: Hardcoded paths (warnings only)
    $paths = Test-HardcodedPaths -FilePath $file
    if ($paths.Valid) {
        Write-Host "[PASS] Path validation" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Path validation" -ForegroundColor Yellow
        $paths.Issues | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    }
    $global:AuditResults += [PSCustomObject]@{
        File = $file
        Test = "HardcodedPaths"
        Status = if ($paths.Valid) { "PASS" } else { "WARN" }
        Details = ($paths.Issues -join "; ")
    }
    
    # Test 5: GUI blocking (for GUI files)
    if ($file -match "GUI") {
        $blocking = Test-GUIBlocking -FilePath $file
        if ($blocking.Valid) {
            Write-Host "[PASS] GUI blocking check" -ForegroundColor Green
        } else {
            Write-Host "[WARN] GUI blocking check" -ForegroundColor Yellow
            $blocking.Issues | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        }
        $global:AuditResults += [PSCustomObject]@{
            File = $file
            Test = "GUIBlocking"
            Status = if ($blocking.Valid) { "PASS" } else { "WARN" }
            Details = ($blocking.Issues -join "; ")
        }
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "AUDIT SUMMARY" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

$passCount = ($global:AuditResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($global:AuditResults | Where-Object { $_.Status -eq "FAIL" }).Count
$warnCount = ($global:AuditResults | Where-Object { $_.Status -eq "WARN" }).Count

Write-Host "Total Tests: $($global:AuditResults.Count)" -ForegroundColor White
Write-Host "PASS: $passCount" -ForegroundColor Green
Write-Host "FAIL: $failCount" -ForegroundColor Red
Write-Host "WARN: $warnCount" -ForegroundColor Yellow

# Export results
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$reportPath = Join-Path $LogDir "deepaudit-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$global:AuditResults | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
Write-Host "`nReport saved to: $reportPath" -ForegroundColor Cyan

if ($failCount -gt 0) {
    Write-Host "`nFAILED TESTS:" -ForegroundColor Red
    $global:AuditResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  [$($_.File)] $($_.Test): $($_.Details)" -ForegroundColor Yellow
    }
    exit 1
} else {
    Write-Host "`nALL CRITICAL TESTS PASSED!" -ForegroundColor Green
    if ($warnCount -gt 0) {
        Write-Host "Warnings present but non-blocking." -ForegroundColor Yellow
    }
    exit 0
}
