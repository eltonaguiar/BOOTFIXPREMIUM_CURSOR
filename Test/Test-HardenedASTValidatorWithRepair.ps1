<#
.SYNOPSIS
    Ultra-Rigid Validator & Heuristic Repair Tool for MiracleBoot.
    Targets "AI Hallucination" errors in Windows 10/11 and WinPE.

.DESCRIPTION
    1. Scans .ps1 files using the AST Parser to detect structural syntax errors.
    2. Attempts to auto-repair missing braces, parentheses, and comment blocks.
    3. Scans logs for critical error keywords.
    4. Blocks execution if unrepairable errors persist.
    
    This tool is designed for recovery environments where having a working
    system is critical, even if it requires automatic repairs.

.PARAMETER TargetFolder
    Root folder to scan for PowerShell files

.PARAMETER ErrorPatterns
    Array of error patterns to search for in log files

.PARAMETER AutoRepair
    Enable automatic repair of common syntax errors (default: $true)

.PARAMETER ReportPath
    Path where validation report JSON will be saved

.EXAMPLE
    .\Test-HardenedASTValidatorWithRepair.ps1 -TargetFolder "C:\MiracleBoot" -AutoRepair
    
    Scans and attempts to repair syntax errors automatically.
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$TargetFolder = $PSScriptRoot,

    [Parameter(Mandatory=$false)]
    [string[]]$ErrorPatterns = @("error", "fail", "exception", "critical", "denied", "missing"),

    [Parameter(Mandatory=$false)]
    [switch]$AutoRepair = $true,

    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "$env:SystemDrive\MiracleBoot_QA_Report.json"
)

# --- REPAIR ENGINE ---

function Invoke-HeuristicRepair {
    <#
    .SYNOPSIS
        Attempts to repair common AI-generated syntax errors.
        
    .DESCRIPTION
        Targets specific error types that are commonly introduced by AI:
        - Missing closing braces
        - Missing closing parentheses
        - Missing multi-line comment terminators
        
    .NOTES
        This function is conservative - it only fixes well-known patterns
        and re-validates after each repair attempt.
    #>
    param(
        [string]$FilePath,
        [System.Management.Automation.Language.ParseError[]]$Errors
    )
    
    if (-not (Test-Path $FilePath)) {
        return $false
    }
    
    $content = Get-Content -Path $FilePath -Raw
    $originalContent = $content
    $repaired = $false
    $repairActions = @()

    foreach ($err in $Errors) {
        # Target specific AI-modified failure types
        switch -regex ($err.ErrorId) {
            "MissingTerminatorMultiLineComment" {
                Write-Host "    [REPAIR] Closing multi-line comment..." -ForegroundColor Yellow
                $content += "`r`n#>"
                $repairActions += "Added missing comment terminator (#>)"
                $repaired = $true
            }
            "MissingClosingBraceInStatementBlock" {
                Write-Host "    [REPAIR] Closing missing brace..." -ForegroundColor Yellow
                $content += "`r`n}"
                $repairActions += "Added missing closing brace (})"
                $repaired = $true
            }
            "MissingClosingBrace" {
                Write-Host "    [REPAIR] Closing missing brace..." -ForegroundColor Yellow
                $content += "`r`n}"
                $repairActions += "Added missing closing brace (})"
                $repaired = $true
            }
            "MissingEndParenthesisInExpression" {
                Write-Host "    [REPAIR] Closing missing parenthesis..." -ForegroundColor Yellow
                $content += "`r`n)"
                $repairActions += "Added missing closing parenthesis ())"
                $repaired = $true
            }
            "MissingClosingParenthesis" {
                Write-Host "    [REPAIR] Closing missing parenthesis..." -ForegroundColor Yellow
                $content += "`r`n)"
                $repairActions += "Added missing closing parenthesis ())"
                $repaired = $true
            }
        }
    }

    if ($repaired) {
        try {
            # Create backup before repair
            $backupPath = "$FilePath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Set-Content -Path $backupPath -Value $originalContent -Encoding UTF8 -ErrorAction Stop
            
            # Apply repair
            Set-Content -Path $FilePath -Value $content -Encoding UTF8 -ErrorAction Stop
            
            Write-Host "    [BACKUP] Created backup: $(Split-Path -Leaf $backupPath)" -ForegroundColor Gray
            
            # Re-parse after repair to verify
            $verifyErrors = $null
            $verifyTokens = $null
            $verifyAst = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$verifyTokens, [ref]$verifyErrors)
            
            if ($verifyErrors -and $verifyErrors.Count -gt 0) {
                Write-Host "    [WARN] Repair did not fully resolve errors. Remaining: $($verifyErrors.Count)" -ForegroundColor Yellow
                return @{
                    Success = $false
                    Actions = $repairActions
                    RemainingErrors = $verifyErrors.Count
                }
            } else {
                Write-Host "    [SUCCESS] Repair verified - file now has valid syntax" -ForegroundColor Green
                return @{
                    Success = $true
                    Actions = $repairActions
                    BackupPath = $backupPath
                }
            }
        } catch {
            Write-Host "    [ERROR] Repair failed: $_" -ForegroundColor Red
            return @{
                Success = $false
                Actions = $repairActions
                Error = $_.Exception.Message
            }
        }
    }
    
    return @{
        Success = $false
        Actions = @()
        Reason = "No repairable errors found"
    }
}

# --- VALIDATION CORE ---

function Start-HardenedScan {
    Write-Host "[!] INITIATING DEEP INTEGRITY SCAN WITH REPAIR ENGINE..." -ForegroundColor Cyan
    Write-Host ""
    
    $report = @{ 
        syntax_failures = @()
        fixed_files = @()
        repair_failures = @()
        log_findings = @()
        files_scanned = 0
        is_ready = $false
    }
    
    # Get PowerShell files (exclude utilities and test files from critical validation)
    $psFiles = Get-ChildItem -Path $TargetFolder -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | 
               Where-Object { 
                   $_.FullName -notmatch '\\Test\\' -or $_.Name -like 'Test-*.ps1'
               } |
               Where-Object {
                   $_.FullName -notmatch '\\Utilities\\' -or 
                   $_.Name -eq 'VersionTracker.ps1'
               }
    
    Write-Host "Scanning PowerShell files..." -ForegroundColor Yellow
    foreach ($file in $psFiles) {
        $report.files_scanned++
        $relativePath = $file.FullName.Replace($TargetFolder, '').TrimStart('\')
        Write-Host "  Checking: $relativePath..." -NoNewline -ForegroundColor Gray
        
        try {
            $errors = $null
            $tokens = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)

            if ($errors -and $errors.Count -gt 0) {
                Write-Host " [FAILED - $($errors.Count) error(s)]" -ForegroundColor Red
                
                if ($AutoRepair) {
                    Write-Host "    Attempting heuristic repair..." -ForegroundColor Cyan
                    $repairResult = Invoke-HeuristicRepair -FilePath $file.FullName -Errors $errors
                    
                    if ($repairResult.Success) {
                        $report.fixed_files += @{
                            file = $relativePath
                            fullPath = $file.FullName
                            actions = $repairResult.Actions
                            backup = $repairResult.BackupPath
                        }
                        Write-Host "  [FIXED] $relativePath" -ForegroundColor Green
                        
                        # Re-check after repair
                        $errors = $null
                        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
                    } else {
                        $report.repair_failures += @{
                            file = $relativePath
                            fullPath = $file.FullName
                            reason = if ($repairResult.Error) { $repairResult.Error } else { $repairResult.Reason }
                            remainingErrors = if ($repairResult.RemainingErrors) { $repairResult.RemainingErrors } else { $errors.Count }
                        }
                    }
                }
                
                # Record any remaining errors
                if ($errors -and $errors.Count -gt 0) {
                    foreach ($err in $errors) {
                        $report.syntax_failures += @{
                            file = $relativePath
                            fullPath = $file.FullName
                            line = $err.Extent.StartLineNumber
                            column = $err.Extent.StartColumnNumber
                            message = $err.Message
                            id = $err.ErrorId
                            extent = $err.Extent.Text
                        }
                    }
                }
            } else {
                Write-Host " [OK]" -ForegroundColor Green
            }
        } catch {
            Write-Host " [EXCEPTION: $_]" -ForegroundColor Red
            $report.syntax_failures += @{
                file = $relativePath
                fullPath = $file.FullName
                line = 0
                message = "Parser exception: $_"
                id = "ParserException"
            }
        }
    }

    Write-Host ""
    Write-Host "Scanning critical log files..." -ForegroundColor Yellow
    
    # Log Check (only root-level production error log)
    $rootErrorLog = Join-Path $TargetFolder "MiracleBoot_GUI_Error.log"
    if (Test-Path $rootErrorLog) {
        Write-Host "  Scanning: MiracleBoot_GUI_Error.log..." -NoNewline -ForegroundColor Gray
        try {
            $matches = Select-String -Path $rootErrorLog -Pattern $ErrorPatterns -SimpleMatch -CaseSensitive:$false -ErrorAction SilentlyContinue
            if ($matches) {
                Write-Host " [FOUND $($matches.Count) match(es)]" -ForegroundColor Yellow
                foreach ($m in $matches) {
                    $report.log_findings += @{
                        file = "MiracleBoot_GUI_Error.log"
                        fullPath = $rootErrorLog
                        line = $m.LineNumber
                        content = $m.Line.Trim()
                    }
                }
            } else {
                Write-Host " [OK]" -ForegroundColor Green
            }
        } catch {
            Write-Host " [ERROR: $_]" -ForegroundColor Red
        }
    } else {
        Write-Host "  No error log found (OK)" -ForegroundColor Green
    }

    # Final Readiness Logic
    # Strict Gate: 0 syntax errors AND 0 log findings AND files must actually exist
    if ($report.syntax_failures.Count -eq 0 -and $report.log_findings.Count -eq 0 -and $report.files_scanned -gt 0) {
        $report.is_ready = $true
    }

    return $report
}

# --- REPORTING & UI ---

function Write-FinalReport {
    param($Data)

    $reportObj = [PSCustomObject]@{
        timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        env            = if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT") { "WinPE" } else { "FullOS" }
        ready_to_launch = $Data.is_ready
        files_checked  = $Data.files_scanned
        files_fixed    = $Data.fixed_files.Count
        repair_failures = $Data.repair_failures.Count
        syntax_errors  = $Data.syntax_failures
        log_errors     = $Data.log_findings
        summary        = if ($Data.is_ready) {
            "READY: All $($Data.files_scanned) files validated successfully. Fixed $($Data.fixed_files.Count) file(s)."
        } else {
            "NOT READY: Found $($Data.syntax_failures.Count) syntax error(s) and $($Data.log_findings.Count) log error(s)."
        }
    }

    $json = $reportObj | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $ReportPath -Encoding UTF8
    
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "=== MIRACLEBOOT INTEGRITY REPORT ===" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    if ($Data.fixed_files.Count -gt 0) {
        Write-Host "Files Fixed:    $($Data.fixed_files.Count)" -ForegroundColor Green
        foreach ($fixed in $Data.fixed_files) {
            Write-Host "  - $($fixed.file)" -ForegroundColor Gray
            foreach ($action in $fixed.actions) {
                Write-Host "    $action" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
    
    Write-Host "Files Scanned:  $($Data.files_scanned)" -ForegroundColor Cyan
    Write-Host "Syntax Errors:  $($Data.syntax_failures.Count)" -ForegroundColor $(if($Data.syntax_failures.Count -eq 0){"Green"}else{"Red"})
    Write-Host "Log Findings:   $($Data.log_findings.Count)" -ForegroundColor $(if($Data.log_findings.Count -eq0){"Green"}else{"Yellow"})
    
    if ($Data.repair_failures.Count -gt 0) {
        Write-Host "Repair Failures: $($Data.repair_failures.Count)" -ForegroundColor Yellow
        foreach ($failure in $Data.repair_failures) {
            Write-Host "  - $($failure.file): $($failure.reason)" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    if ($Data.is_ready) {
        Write-Host ""
        Write-Host "[SUCCESS] All files are structurally sound. Ready to launch." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "[CRITICAL] Unrepairable errors remain. DO NOT LAUNCH." -ForegroundColor Red
        if ($Data.syntax_failures.Count -gt 0) {
            Write-Host ""
            Write-Host "Unrepairable Syntax Errors:" -ForegroundColor Red
            foreach ($err in $Data.syntax_failures | Select-Object -First 10) {
                Write-Host "  ! $($err.file):$($err.line) - $($err.message)" -ForegroundColor Red
            }
            if ($Data.syntax_failures.Count -gt 10) {
                Write-Host "  ... and $($Data.syntax_failures.Count - 10) more error(s)" -ForegroundColor Yellow
            }
        }
        Write-Host ""
        Write-Host "Check Report: $ReportPath" -ForegroundColor Cyan
    }
    
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    return $json
}

# --- MAIN EXECUTION ---
try {
    $Results = Start-HardenedScan
    $Output = Write-FinalReport -Data $Results
    
    if ($Results.is_ready) { 
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

