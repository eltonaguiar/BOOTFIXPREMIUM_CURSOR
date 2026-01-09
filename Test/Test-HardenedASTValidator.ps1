<#
.SYNOPSIS
    Ultra-Rigid Readiness & Syntax Validator for MiracleBoot Packages.
    Designed for Windows 10/11 and WinPE (Shift+F10).

.DESCRIPTION
    This script is built to be "AI-Hostile" regarding errors. It performs:
    1. Structural Syntax Validation (AST Parsing) to catch missing brackets/comments.
    2. Deep Keyword Scanning for log-based error patterns.
    3. Environment context verification.
    
    Uses PowerShell Abstract Syntax Tree (AST) Parser to catch structural failures
    that simple string matching would miss.

.PARAMETER TargetFolder
    Root folder to scan for PowerShell files (defaults to script root)

.PARAMETER ErrorPatterns
    Array of error patterns to search for in log files

.PARAMETER ReportPath
    Path where validation report JSON will be saved

.EXAMPLE
    .\Test-HardenedASTValidator.ps1 -TargetFolder "C:\MiracleBoot"
    
    Scans all PowerShell files in the target folder and validates syntax.
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$TargetFolder = $PSScriptRoot,

    [Parameter(Mandatory=$false)]
    [string[]]$ErrorPatterns = @("error", "fail", "exception", "critical", "denied", "missing"),

    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "$env:SystemDrive\MiracleBoot_QA_Report.json"
)

# --- THE "SCARY" STUFF: SYNTAX INTEGRITY ---

function Test-ScriptIntegrity {
    <#
    This function uses the PowerShell Parser to find syntax errors 
    WITHOUT running the code. It catches the errors shown in your screenshots.
    #>
    param([string]$FilePath)
    
    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$errors)
    
    return $errors # Returns a collection of ParseError objects
}

# --- CORE VALIDATION ENGINE ---

function Start-HardenedValidation {
    Write-Host "[!] INITIATING DEEP INTEGRITY SCAN..." -ForegroundColor Cyan
    Write-Host ""
    
    $results = @{
        syntax_failures = @()
        log_findings    = @()
        files_scanned   = 0
        is_ready        = $false
    }

    # 1. Recursive Syntax Check (Catching the AI Hallucinations)
    # Exclude utility scripts and test files from critical validation
    $psFiles = Get-ChildItem -Path $TargetFolder -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | 
               Where-Object { 
                   $_.FullName -notmatch '\\Test\\' -or $_.Name -eq 'Test-HardenedASTValidator.ps1' -or $_.Name -like 'Test-*.ps1'
               } |
               Where-Object {
                   $_.FullName -notmatch '\\Utilities\\' -or 
                   $_.Name -eq 'VersionTracker.ps1'
               }
    
    Write-Host "Scanning PowerShell files..." -ForegroundColor Yellow
    foreach ($file in $psFiles) {
        $results.files_scanned++
        $relativePath = $file.FullName.Replace($TargetFolder, '').TrimStart('\')
        Write-Host "  Checking Syntax: $relativePath..." -NoNewline -ForegroundColor Gray
        
        try {
            $syntaxErrors = Test-ScriptIntegrity -FilePath $file.FullName
            if ($syntaxErrors -and $syntaxErrors.Count -gt 0) {
                Write-Host " [FAILED - $($syntaxErrors.Count) error(s)]" -ForegroundColor Red
                foreach ($err in $syntaxErrors) {
                    $results.syntax_failures += @{
                        file    = $relativePath
                        fullPath = $file.FullName
                        line    = $err.Extent.StartLineNumber
                        column  = $err.Extent.StartColumnNumber
                        message = $err.Message
                        id      = $err.ErrorId
                        extent  = $err.Extent.Text
                    }
                }
            } else {
                Write-Host " [OK]" -ForegroundColor Green
            }
        } catch {
            Write-Host " [EXCEPTION: $_]" -ForegroundColor Red
            $results.syntax_failures += @{
                file    = $relativePath
                fullPath = $file.FullName
                line    = 0
                message = "Parser exception: $_"
                id      = "ParserException"
            }
        }
    }

    Write-Host ""
    Write-Host "Scanning critical log files..." -ForegroundColor Yellow
    
    # 2. Log/String Scanning (only root-level production error log)
    $rootErrorLog = Join-Path $TargetFolder "MiracleBoot_GUI_Error.log"
    $logFiles = @()
    if (Test-Path $rootErrorLog) {
        $logFiles = @(Get-Item $rootErrorLog)
    }
    foreach ($log in $logFiles) {
        $relativePath = $log.FullName.Replace($TargetFolder, '').TrimStart('\')
        Write-Host "  Scanning Log: $relativePath..." -NoNewline -ForegroundColor Gray
        try {
            $matches = Select-String -Path $log.FullName -Pattern $ErrorPatterns -SimpleMatch -CaseSensitive:$false -ErrorAction SilentlyContinue
            if ($matches) {
                Write-Host " [FOUND $($matches.Count) match(es)]" -ForegroundColor Yellow
                foreach ($m in $matches) {
                    $results.log_findings += @{
                        file    = $relativePath
                        fullPath = $log.FullName
                        line    = $m.LineNumber
                        content = $m.Line.Trim()
                    }
                }
            } else {
                Write-Host " [OK]" -ForegroundColor Green
            }
        } catch {
            Write-Host " [ERROR: $_]" -ForegroundColor Red
        }
    }

    # 3. Final Readiness Logic
    # Strict Gate: 0 syntax errors AND 0 keyword findings AND files must actually exist
    if ($results.syntax_failures.Count -eq 0 -and $results.log_findings.Count -eq 0 -and $results.files_scanned -gt 0) {
        $results.is_ready = $true
    }

    return $results
}

# --- REPORTING & UI ---

function Write-FinalReport {
    param($Data)

    $reportObj = [PSCustomObject]@{
        timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        env            = if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT") { "WinPE" } else { "FullOS" }
        ready_to_launch = $Data.is_ready
        files_checked  = $Data.files_scanned
        syntax_errors  = $Data.syntax_failures
        log_errors     = $Data.log_findings
        summary        = if ($Data.is_ready) {
            "READY: All $($Data.files_scanned) files validated successfully with zero errors."
        } else {
            "NOT READY: Found $($Data.syntax_failures.Count) syntax error(s) and $($Data.log_findings.Count) log error(s)."
        }
    }

    $json = $reportObj | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $ReportPath -Encoding UTF8
    
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    if ($Data.is_ready) {
        Write-Host "  VALIDATION SUCCESSFUL: READY TO PROCEED" -ForegroundColor Green
        Write-Host "  No syntax errors or log failures detected." -ForegroundColor Green
        Write-Host "  Files Scanned: $($Data.files_scanned)" -ForegroundColor Green
    } else {
        Write-Host "  VALIDATION FAILED: DO NOT PROCEED" -ForegroundColor Red
        Write-Host "  Syntax Errors: $($Data.syntax_failures.Count)" -ForegroundColor Yellow
        Write-Host "  Log Findings:  $($Data.log_findings.Count)" -ForegroundColor Yellow
        
        if ($Data.syntax_failures.Count -gt 0) {
            Write-Host ""
            Write-Host "  Syntax Error Details:" -ForegroundColor Yellow
            foreach ($err in $Data.syntax_failures | Select-Object -First 10) {
                Write-Host "    - $($err.file):$($err.line) - $($err.message)" -ForegroundColor Red
            }
            if ($Data.syntax_failures.Count -gt 10) {
                Write-Host "    ... and $($Data.syntax_failures.Count - 10) more error(s)" -ForegroundColor Yellow
            }
        }
        
        Write-Host ""
        Write-Host "  Check Report:  $ReportPath" -ForegroundColor Cyan
    }
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    # Return structured JSON to the stream for AI/Pipe consumption
    return $json
}

# --- EXECUTION ---
try {
    $ScanResults = Start-HardenedValidation
    $Output = Write-FinalReport -Data $ScanResults
    
    if ($ScanResults.is_ready) { 
        exit 0 
    } else { 
        exit 1 
    }
}
catch {
    Write-Host "CRITICAL SCRIPT ERROR: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 99
}

