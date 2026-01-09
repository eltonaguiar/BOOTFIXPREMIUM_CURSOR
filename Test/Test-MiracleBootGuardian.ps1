<#
.SYNOPSIS
    MiracleBoot Guardian: Protection against AI-wiped or broken scripts.
    Designed for Windows 10/11 and WinPE Recovery (Shift+F10).

.DESCRIPTION
    1. Backs up files before any modification.
    2. Detects "Wiped" files (suspiciously low line counts).
    3. Uses AST Parsing to fix syntax errors (missing comment terminators, braces, or parentheses).
    4. Scans logs for critical failures.
    5. Provides JSON-ready reports for automation.

.PARAMETER TargetFolder
    Root folder to scan for PowerShell files

.PARAMETER MinLineThreshold
    Files below this line count are flagged as "Wiped" (default: 10)

.PARAMETER AutoRepair
    Enable automatic repair of common syntax errors (default: $true)

.PARAMETER ReportPath
    Path where validation report JSON will be saved

.EXAMPLE
    .\Test-MiracleBootGuardian.ps1 -TargetFolder "C:\MiracleBoot" -AutoRepair
    
    Scans for wiped files and syntax errors, attempts auto-repair with backups.
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$TargetFolder = $PSScriptRoot,

    [Parameter(Mandatory=$false)]
    [int]$MinLineThreshold = 10, # Files below this line count are flagged as "Wiped"

    [Parameter(Mandatory=$false)]
    [switch]$AutoRepair = $true,

    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "$env:SystemDrive\MiracleBoot_Guardian_Report.json"
)

# --- UTILITIES ---

function New-Backup {
    <#
    .SYNOPSIS
        Creates a timestamped backup of a file before modification.
    #>
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    
    $backupPath = "$FilePath.bak"
    $timestampedBackup = "$FilePath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    # Create both .bak (quick restore) and timestamped backup
    try {
        Copy-Item -Path $FilePath -Destination $backupPath -Force -ErrorAction Stop
        Copy-Item -Path $FilePath -Destination $timestampedBackup -Force -ErrorAction Stop
        Write-Host "    [BACKUP] Created: $(Split-Path -Leaf $backupPath)" -ForegroundColor Gray
        Write-Host "    [BACKUP] Created: $(Split-Path -Leaf $timestampedBackup)" -ForegroundColor Gray
        return @($backupPath, $timestampedBackup)
    } catch {
        Write-Host "    [ERROR] Failed to create backup: $_" -ForegroundColor Red
        return $null
    }
}

function Test-ImposterFile {
    <#
    .SYNOPSIS
        Detects if a file has been "wiped" or replaced by a suspiciously short placeholder.
    #>
    param(
        [string]$FilePath,
        [int]$Threshold
    )
    
    if (-not (Test-Path $FilePath)) {
        return $false
    }
    
    try {
        $contentLines = Get-Content -Path $FilePath -ErrorAction Stop
        $lineCount = $contentLines.Count
        
        # Check if file is suspiciously short (but not empty)
        if ($lineCount -gt 0 -and $lineCount -lt $Threshold) {
            # Additional check: if it's mostly whitespace or placeholder text
            $nonEmptyLines = $contentLines | Where-Object { $_.Trim().Length -gt 0 }
            $placeholderPatterns = @('placeholder', 'todo', 'fixme', 'not implemented', 'coming soon')
            
            $hasPlaceholderText = $false
            foreach ($line in $nonEmptyLines) {
                foreach ($pattern in $placeholderPatterns) {
                    if ($line -match $pattern) {
                        $hasPlaceholderText = $true
                        break
                    }
                }
            }
            
            return @{
                IsImposter = $true
                LineCount = $lineCount
                NonEmptyLines = $nonEmptyLines.Count
                HasPlaceholderText = $hasPlaceholderText
            }
        }
        
        return @{
            IsImposter = $false
            LineCount = $lineCount
        }
    } catch {
        return @{
            IsImposter = $false
            Error = $_.Exception.Message
        }
    }
}

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
    #>
    param(
        [string]$FilePath,
        [System.Management.Automation.Language.ParseError[]]$Errors
    )
    
    if (-not (Test-Path $FilePath)) {
        return @{
            Success = $false
            Reason = "File not found"
        }
    }
    
    # Create backup before repair
    $backups = New-Backup -FilePath $FilePath
    if (-not $backups) {
        return @{
            Success = $false
            Reason = "Failed to create backup"
        }
    }
    
    $content = Get-Content -Path $FilePath -Raw
    $originalContent = $content
    $repaired = $false
    $repairActions = @()

    foreach ($err in $Errors) {
        # Target specific AI-modified failure types
        switch -regex ($err.ErrorId) {
            "MissingTerminatorMultiLineComment" {
                Write-Host "    [FIX] Appending missing comment terminator (#>)..." -ForegroundColor Yellow
                $content += "`r`n#>"
                $repairActions += "Added missing comment terminator (#>)"
                $repaired = $true
            }
            "MissingClosingBraceInStatementBlock" {
                Write-Host "    [FIX] Appending missing closing brace (})..." -ForegroundColor Yellow
                $content += "`r`n}"
                $repairActions += "Added missing closing brace (})"
                $repaired = $true
            }
            "MissingClosingBrace" {
                Write-Host "    [FIX] Appending missing closing brace (})..." -ForegroundColor Yellow
                $content += "`r`n}"
                $repairActions += "Added missing closing brace (})"
                $repaired = $true
            }
            "MissingEndParenthesisInExpression" {
                Write-Host "    [FIX] Appending missing closing parenthesis ())..." -ForegroundColor Yellow
                $content += "`r`n)"
                $repairActions += "Added missing closing parenthesis ())"
                $repaired = $true
            }
            "MissingClosingParenthesis" {
                Write-Host "    [FIX] Appending missing closing parenthesis ())..." -ForegroundColor Yellow
                $content += "`r`n)"
                $repairActions += "Added missing closing parenthesis ())"
                $repaired = $true
            }
        }
    }

    if ($repaired) {
        try {
            # Apply repair
            Set-Content -Path $FilePath -Value $content -Encoding UTF8 -ErrorAction Stop
            
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
                    BackupPaths = $backups
                }
            } else {
                Write-Host "    [SUCCESS] Repair verified - file now has valid syntax" -ForegroundColor Green
                return @{
                    Success = $true
                    Actions = $repairActions
                    BackupPaths = $backups
                }
            }
        } catch {
            Write-Host "    [ERROR] Repair failed: $_" -ForegroundColor Red
            # Restore from backup on failure
            if ($backups -and $backups.Count -gt 0) {
                try {
                    Copy-Item -Path $backups[0] -Destination $FilePath -Force -ErrorAction Stop
                    Write-Host "    [RESTORED] File restored from backup" -ForegroundColor Yellow
                } catch {
                    Write-Host "    [CRITICAL] Failed to restore from backup!" -ForegroundColor Red
                }
            }
            return @{
                Success = $false
                Actions = $repairActions
                Error = $_.Exception.Message
                BackupPaths = $backups
            }
        }
    }
    
    return @{
        Success = $false
        Actions = @()
        Reason = "No repairable errors found"
    }
}

# --- MAIN SCAN ---

function Start-GuardianScan {
    Write-Host "--- MiracleBoot Guardian v2.0 ---" -ForegroundColor Cyan
    Write-Host "Target: $TargetFolder" -ForegroundColor Gray
    Write-Host "Min Line Threshold: $MinLineThreshold" -ForegroundColor Gray
    Write-Host "Auto-Repair: $AutoRepair" -ForegroundColor Gray
    Write-Host ""
    
    $report = @{ 
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        env = if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT") { "WinPE" } else { "FullOS" }
        syntax_failures = @()
        wiped_files = @()
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
        
        # 1. Check for AI "Wiping" (LMStudio/Copilot empty placeholders)
        $imposterCheck = Test-ImposterFile -FilePath $file.FullName -Threshold $MinLineThreshold
        if ($imposterCheck.IsImposter) {
            Write-Host " [WIPED - $($imposterCheck.LineCount) lines]" -ForegroundColor Red
            $report.wiped_files += @{
                file = $relativePath
                fullPath = $file.FullName
                lineCount = $imposterCheck.LineCount
                nonEmptyLines = $imposterCheck.NonEmptyLines
                hasPlaceholderText = $imposterCheck.HasPlaceholderText
                severity = if ($imposterCheck.HasPlaceholderText) { "CRITICAL" } else { "SUSPICIOUS" }
            }
            continue
        }

        # 2. Syntax Check using AST
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
                            backups = $repairResult.BackupPaths
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
                            backups = if ($repairResult.BackupPaths) { $repairResult.BackupPaths } else { @() }
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
            $matches = Select-String -Path $rootErrorLog -Pattern @("error", "fail", "exception", "critical", "denied", "missing") -SimpleMatch -CaseSensitive:$false -ErrorAction SilentlyContinue
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
    # Strict Gate: 0 syntax errors AND 0 wiped files AND 0 log findings AND files must actually exist
    if ($report.syntax_failures.Count -eq 0 -and 
        $report.wiped_files.Count -eq 0 -and 
        $report.log_findings.Count -eq 0 -and 
        $report.files_scanned -gt 0) {
        $report.is_ready = $true
    }

    return $report
}

# --- REPORTING ---

function Write-GuardianReport {
    param($Data)

    $reportObj = [PSCustomObject]@{
        timestamp = $Data.timestamp
        env = $Data.env
        ready_to_launch = $Data.is_ready
        files_checked = $Data.files_scanned
        wiped_files = $Data.wiped_files
        files_fixed = $Data.fixed_files.Count
        repair_failures = $Data.repair_failures.Count
        syntax_errors = $Data.syntax_failures
        log_errors = $Data.log_findings
        summary = if ($Data.is_ready) {
            "READY: All $($Data.files_scanned) files validated successfully. Fixed $($Data.fixed_files.Count) file(s)."
        } else {
            "NOT READY: Found $($Data.wiped_files.Count) wiped file(s), $($Data.syntax_failures.Count) syntax error(s), and $($Data.log_findings.Count) log error(s)."
        }
    }

    $json = $reportObj | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $ReportPath -Encoding UTF8
    
    Write-Host ""
    Write-Host "=== INTEGRITY SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Files Scanned:  $($Data.files_scanned)" -ForegroundColor Cyan
    Write-Host "Wiped/Truncated: $($Data.wiped_files.Count)" -ForegroundColor $(if($Data.wiped_files.Count -gt 0){"Red"}else{"Green"})
    Write-Host "Auto-Repaired:   $($Data.fixed_files.Count)" -ForegroundColor $(if($Data.fixed_files.Count -gt 0){"Green"}else{"Gray"})
    Write-Host "Repair Failures: $($Data.repair_failures.Count)" -ForegroundColor $(if($Data.repair_failures.Count -gt 0){"Yellow"}else{"Gray"})
    Write-Host "Syntax Errors:   $($Data.syntax_failures.Count)" -ForegroundColor $(if($Data.syntax_failures.Count -eq 0){"Green"}else{"Red"})
    Write-Host "Log Findings:   $($Data.log_findings.Count)" -ForegroundColor $(if($Data.log_findings.Count -eq 0){"Green"}else{"Yellow"})
    
    if ($Data.wiped_files.Count -gt 0) {
        Write-Host ""
        Write-Host "CRITICAL: Wiped Files Detected!" -ForegroundColor Red
        foreach ($wiped in $Data.wiped_files) {
            Write-Host "  ! $($wiped.file) - Only $($wiped.lineCount) lines (expected >$MinLineThreshold)" -ForegroundColor Red
            if ($wiped.hasPlaceholderText) {
                Write-Host "    Contains placeholder text - likely AI replacement!" -ForegroundColor Red
            }
            Write-Host "    Restore from .bak backup immediately!" -ForegroundColor Yellow
        }
    }
    
    if ($Data.fixed_files.Count -gt 0) {
        Write-Host ""
        Write-Host "Files Auto-Repaired:" -ForegroundColor Green
        foreach ($fixed in $Data.fixed_files) {
            Write-Host "  ✓ $($fixed.file)" -ForegroundColor Green
            foreach ($action in $fixed.actions) {
                Write-Host "    - $action" -ForegroundColor Gray
            }
            if ($fixed.backups) {
                Write-Host "    Backups: $(($fixed.backups | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')" -ForegroundColor Gray
            }
        }
    }
    
    if ($Data.is_ready) {
        Write-Host ""
        Write-Host "[PASS] System is structurally sound. No AI-wiping or syntax errors found." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "[FAIL] CRITICAL ERRORS REMAIN." -ForegroundColor Red
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
    
    Write-Host ""
    return $json
}

# --- EXECUTION ---
try {
    $Results = Start-GuardianScan
    $Output = Write-GuardianReport -Data $Results
    
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

