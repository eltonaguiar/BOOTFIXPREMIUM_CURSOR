# Comprehensive Syntax Check for All Core Files
# Following 7-layer enforcement strategy

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Get-Location }

$errors = @()
$warnings = @()
$files = @()

Write-Host "`n=== COMPREHENSIVE SYNTAX CHECK ===" -ForegroundColor Cyan
Write-Host "Checking all PowerShell files in the project..." -ForegroundColor Cyan
Write-Host ""

# Get all PowerShell files
$psFiles = Get-ChildItem -Path $scriptRoot -Filter "*.ps1" -Recurse -File | 
    Where-Object { 
        $_.FullName -notmatch '\\Test\\' -and
        $_.FullName -notmatch '\\\.git\\' -and
        $_.FullName -notmatch '\\workspace\\' -and
        $_.FullName -notmatch 'backup' -and
        $_.Name -notlike '*backup*'
    } | 
    Sort-Object FullName

Write-Host "Found $($psFiles.Count) PowerShell files to check" -ForegroundColor Gray
Write-Host ""

foreach ($file in $psFiles) {
    $relativePath = $file.FullName.Replace($scriptRoot, "").TrimStart('\')
    Write-Host "[CHECK] $relativePath..." -ForegroundColor Gray -NoNewline
    
    try {
        $content = Get-Content $file.FullName -Raw -ErrorAction Stop
        $parseErrors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$parseErrors)
        
        if ($parseErrors.Count -eq 0) {
            Write-Host " OK" -ForegroundColor Green
            $files += @{ 
                File = $relativePath; 
                Status = "PASS"; 
                Errors = @();
                Warnings = @()
            }
        } else {
            Write-Host " FAIL ($($parseErrors.Count) error(s))" -ForegroundColor Red
            $fileErrors = @()
            foreach ($err in $parseErrors) {
                $errorInfo = @{
                    File = $relativePath
                    Line = $err.Token.StartLine
                    Column = $err.Token.StartColumn
                    ErrorType = "ParserError"
                    ErrorMessage = $err.Message
                    Token = $err.Token.Content
                }
                $fileErrors += $errorInfo
                $errors += $errorInfo
            }
            $files += @{ 
                File = $relativePath; 
                Status = "FAIL"; 
                Errors = $fileErrors;
                Warnings = @()
            }
        }
        
        # Additional checks
        # Check for common issues
        $warningsForFile = @()
        
        # Check for unclosed strings
        $singleQuotes = ([regex]::Matches($content, "'")).Count
        $doubleQuotes = ([regex]::Matches($content, '"')).Count
        if ($singleQuotes % 2 -ne 0) {
            $warningsForFile += "Unmatched single quotes detected"
        }
        if ($doubleQuotes % 2 -ne 0) {
            $warningsForFile += "Unmatched double quotes detected"
        }
        
        # Check for unclosed braces
        $openBraces = ([regex]::Matches($content, '\{')).Count
        $closeBraces = ([regex]::Matches($content, '\}')).Count
        if ($openBraces -ne $closeBraces) {
            $warningsForFile += "Unmatched braces: $openBraces open, $closeBraces close"
        }
        
        # Check for unclosed parentheses
        $openParens = ([regex]::Matches($content, '\(')).Count
        $closeParens = ([regex]::Matches($content, '\)')).Count
        if ($openParens -ne $closeParens) {
            $warningsForFile += "Unmatched parentheses: $openParens open, $closeParens close"
        }
        
        if ($warningsForFile.Count -gt 0) {
            foreach ($warn in $warningsForFile) {
                $warnings += @{
                    File = $relativePath
                    Warning = $warn
                }
            }
            $files | Where-Object { $_.File -eq $relativePath } | ForEach-Object {
                $_.Warnings = $warningsForFile
            }
        }
        
    } catch {
        Write-Host " EXCEPTION" -ForegroundColor Red
        $errors += @{
            File = $relativePath
            Line = 0
            Column = 0
            ErrorType = "Exception"
            ErrorMessage = $_.Exception.Message
            Token = ""
        }
        $files += @{ 
            File = $relativePath; 
            Status = "EXCEPTION"; 
            Errors = @(@{
                File = $relativePath
                Line = 0
                ErrorType = "Exception"
                ErrorMessage = $_.Exception.Message
            });
            Warnings = @()
        }
    }
}

Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
$passed = ($files | Where-Object { $_.Status -eq "PASS" }).Count
$failed = ($files | Where-Object { $_.Status -eq "FAIL" }).Count
$exceptions = ($files | Where-Object { $_.Status -eq "EXCEPTION" }).Count

Write-Host "Total files checked: $($files.Count)" -ForegroundColor Gray
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "Exceptions: $exceptions" -ForegroundColor $(if ($exceptions -eq 0) { "Green" } else { "Red" })
Write-Host "Warnings: $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -eq 0) { "Green" } else { "Yellow" })

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "=== ERRORS FOUND ===" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "FILE: $($err.File)" -ForegroundColor Yellow
        Write-Host "  LINE: $($err.Line):$($err.Column)" -ForegroundColor Yellow
        Write-Host "  TYPE: $($err.ErrorType)" -ForegroundColor Yellow
        Write-Host "  MESSAGE: $($err.ErrorMessage)" -ForegroundColor Yellow
        if ($err.Token) {
            Write-Host "  TOKEN: $($err.Token)" -ForegroundColor Yellow
        }
        Write-Host ""
    }
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "=== WARNINGS ===" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "FILE: $($warning.File)" -ForegroundColor Yellow
        Write-Host "  WARNING: $($warning.Warning)" -ForegroundColor Yellow
        Write-Host ""
    }
}

if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host ""
    Write-Host "[SUCCESS] All files passed syntax validation with no warnings!" -ForegroundColor Green
    exit 0
} elseif ($errors.Count -eq 0) {
    Write-Host ""
    Write-Host "[SUCCESS] All files passed syntax validation (warnings are non-critical)" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "[FAILURE] $($errors.Count) syntax error(s) found" -ForegroundColor Red
    exit 1
}
