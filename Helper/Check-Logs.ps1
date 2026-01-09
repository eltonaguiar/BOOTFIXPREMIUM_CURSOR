<#
.SYNOPSIS
    Generic Log Validator & Readiness Checker.
    
.DESCRIPTION
    Designed to interface with deployment scripts like Miracleboot.ps1. 
    Accepts dynamic paths and patterns via command line.
    
.EXAMPLE
    .\Check-Logs.ps1 -LogPaths ".\setup.log" -ErrorPatterns "Fail","Error"
#>

param (
    [Parameter(Mandatory=$false)]
    [string[]]$LogPaths = @("C:\Windows\Temp\setup.log", ".\Miracleboot.log"),

    [Parameter(Mandatory=$false)]
    [string[]]$ErrorPatterns = @("error", "fail", "exception", "critical"),

    [Parameter(Mandatory=$false)]
    [string]$ReportDir = "$env:SystemDrive\QA_Reports"
)

# --- Internal Functions ---

function Get-EnvironmentContext {
    $isPE = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT"
    return @{ IsPE = $isPE; Time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
}

function Invoke-LogValidation {
    param($Paths, $Patterns)
    
    $errorEntries = @()
    $validFiles = @()

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            $validFiles += (Resolve-Path $path).Path
            # Case-insensitive search for patterns
            $matches = Select-String -Path $path -Pattern $Patterns -SimpleMatch -ErrorAction SilentlyContinue
            
            if ($matches) {
                foreach ($match in $matches) {
                    $errorEntries += @{
                        file    = $path
                        line    = $match.LineNumber
                        message = $match.Line.Trim()
                    }
                }
            }
        }
    }

    # Logic Gate: Ready only if files were found AND no errors were found
    $isReady = ($validFiles.Count -gt 0 -and $errorEntries.Count -eq 0)
    
    return @{
        checked_files  = $validFiles
        errors_found   = $errorEntries
        ready_to_check = $isReady
    }
}

function Save-StructuredReport {
    param($Data, $TargetDir)
    
    if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
    
    $reportPath = Join-Path $TargetDir "Validation_$(Get-Date -Format 'HHmmss').json"
    $reportJson = $Data | ConvertTo-Json -Depth 5
    $reportJson | Out-File -FilePath $reportPath -Encoding UTF8
    
    return $reportJson
}

# --- Execution ---

$Context = Get-EnvironmentContext
Write-Host "Context: $(if($Context.IsPE){'WinPE/Shift+F10'}else{'Standard OS'}) | Time: $($Context.Time)" -ForegroundColor Gray

$Results = Invoke-LogValidation -Paths $LogPaths -Patterns $ErrorPatterns

$Summary = [PSCustomObject]@{
    timestamp      = $Context.Time
    checked_files  = $Results.checked_files
    errors_found   = $Results.errors_found
    ready_to_check = $Results.ready_to_check
    summary        = if($Results.ready_to_check){"Ready: No errors found."}else{"Not Ready: Errors detected or files missing."}
}

$FinalJson = Save-StructuredReport -Data $Summary -TargetDir $ReportDir

# Final Output for Console/CLI
if ($Summary.ready_to_check) {
    Write-Host "SUCCESS: System is ready for Miracleboot/UI launch." -ForegroundColor Green
    exit 0 # Success Code
} else {
    Write-Host "CRITICAL: Validation failed. Check report in $ReportDir" -ForegroundColor Red
    Write-Output $FinalJson
    exit 1 # Failure Code
}

