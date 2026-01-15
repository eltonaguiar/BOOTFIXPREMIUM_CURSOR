# LAYER 2 - PARSER-ONLY MODE
# Validate syntax of all PowerShell and Batch files
# NO LOGIC REASONING - ONLY SYNTAX VALIDATION

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Get-Location }

$errors = @()
$files = @()

# PowerShell files to validate
$psFiles = @(
    "MiracleBoot.ps1",
    "Helper\WinRepairCore.ps1",
    "Helper\WinRepairGUI.ps1",
    "Helper\WinRepairTUI.ps1",
    "Helper\EmergencyRepair.ps1",
    "Helper\PreLaunchValidation.ps1",
    "Helper\ErrorLogging.ps1",
    "Helper\NetworkDiagnostics.ps1",
    "Helper\LogAnalysis.ps1",
    "Helper\KeyboardSymbols.ps1",
    "Helper\RepairReportGenerator.ps1",
    "Helper\AdvancedBootTroubleshooting.ps1",
    "Helper\ReadinessGate.ps1",
    "Helper\GUIFailureDiagnostics.ps1"
)

Write-Host "`n=== LAYER 2: PARSER-ONLY MODE ===" -ForegroundColor Cyan
Write-Host "Validating syntax of all PowerShell files..." -ForegroundColor Cyan
Write-Host ""

foreach ($file in $psFiles) {
    $fullPath = Join-Path $scriptRoot $file
    if (-not (Test-Path $fullPath)) {
        Write-Host "[SKIP] $file - File not found" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "[VALIDATE] $file..." -ForegroundColor Gray -NoNewline
    
    try {
        $content = Get-Content $fullPath -Raw -ErrorAction Stop
        $parseErrors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$parseErrors)
        
        if ($parseErrors.Count -eq 0) {
            Write-Host " OK" -ForegroundColor Green
            $files += @{ File = $file; Status = "PASS"; Errors = @() }
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            foreach ($err in $parseErrors) {
                $errors += @{
                    File = $file
                    Line = $err.Token.StartLine
                    ErrorType = "ParserError"
                    ErrorMessage = $err.Message
                    RootCause = "Syntax error detected by PowerShell parser"
                    Confidence = 100
                }
                $files += @{ File = $file; Status = "FAIL"; Errors = @($err) }
            }
        }
    } catch {
        Write-Host " EXCEPTION" -ForegroundColor Red
        $errors += @{
            File = $file
            Line = 0
            ErrorType = "Exception"
            ErrorMessage = $_.Exception.Message
            RootCause = "Exception during parsing"
            Confidence = 100
        }
    }
}

# Batch file validation (basic check)
Write-Host ""
Write-Host "[VALIDATE] RunMiracleBoot.cmd..." -ForegroundColor Gray -NoNewline
$batchFile = Join-Path $scriptRoot "RunMiracleBoot.cmd"
if (Test-Path $batchFile) {
    try {
        $batchContent = Get-Content $batchFile -Raw -ErrorAction Stop
        # Basic validation: check for unmatched parentheses and quotes
        $openParens = ([regex]::Matches($batchContent, '\(')).Count
        $closeParens = ([regex]::Matches($batchContent, '\)')).Count
        $openQuotes = ([regex]::Matches($batchContent, '"')).Count
        
        if ($openParens -eq $closeParens -and $openQuotes % 2 -eq 0) {
            Write-Host " OK" -ForegroundColor Green
            $files += @{ File = "RunMiracleBoot.cmd"; Status = "PASS"; Errors = @() }
        } else {
            Write-Host " WARN (basic check only)" -ForegroundColor Yellow
            $files += @{ File = "RunMiracleBoot.cmd"; Status = "WARN"; Errors = @() }
        }
    } catch {
        Write-Host " EXCEPTION" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== VALIDATION SUMMARY ===" -ForegroundColor Cyan
Write-Host "Files checked: $($files.Count)" -ForegroundColor Gray
$passed = ($files | Where-Object { $_.Status -eq "PASS" }).Count
$failed = ($files | Where-Object { $_.Status -eq "FAIL" }).Count
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "=== ERRORS FOUND ===" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "FILE: $($err.File)" -ForegroundColor Yellow
        Write-Host "LINE: $($err.Line)" -ForegroundColor Yellow
        Write-Host "ERROR TYPE: $($err.ErrorType)" -ForegroundColor Yellow
        Write-Host "ERROR MESSAGE: $($err.ErrorMessage)" -ForegroundColor Yellow
        Write-Host "ROOT CAUSE: $($err.RootCause)" -ForegroundColor Yellow
        Write-Host "CONFIDENCE: $($err.Confidence)%" -ForegroundColor Yellow
        Write-Host ""
    }
    exit 1
} else {
    Write-Host ""
    Write-Host "[OK] All syntax validation passed" -ForegroundColor Green
    exit 0
}
