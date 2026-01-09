# Test-MiracleBootDirect.ps1
# Directly runs MiracleBoot.ps1 and captures errors

$ErrorActionPreference = 'Continue'
$scriptRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

Write-Host "Testing MiracleBoot.ps1 directly..." -ForegroundColor Cyan
Write-Host ""

# Redirect output to capture errors
$outputFile = Join-Path $env:TEMP "MiracleBoot_Test_Output_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$errorFile = Join-Path $env:TEMP "MiracleBoot_Test_Errors_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Run in a separate process with timeout
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'pwsh.exe'
$psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -Command `"cd '$scriptRoot'; `$ErrorActionPreference='Continue'; . '.\MiracleBoot.ps1' 2>&1 | Tee-Object -FilePath '$outputFile'`""
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi

[void]$process.Start()

# Wait up to 15 seconds for GUI to initialize (or fail)
$process.WaitForExit(15000)

if (-not $process.HasExited) {
    # Process is still running (GUI launched successfully)
    Write-Host "GUI appears to have launched (process still running)" -ForegroundColor Green
    $process.Kill()
    $process.WaitForExit(5000)
} else {
    # Process exited - check exit code
    Write-Host "Process exited with code: $($process.ExitCode)" -ForegroundColor $(if ($process.ExitCode -eq 0) { "Green" } else { "Yellow" })
}

# Read captured output
if (Test-Path $outputFile) {
    $output = Get-Content $outputFile -Raw
    Write-Host ""
    Write-Host "=== CAPTURED OUTPUT ===" -ForegroundColor Cyan
    Write-Host $output
    
    # Scan for errors
    $errorPatterns = @(
        'Get-Control.*not recognized',
        'null-valued expression',
        'Cannot set unknown member',
        'GUI MODE FAILED',
        'FALLING BACK TO TUI',
        'ERROR:',
        'Exception',
        'Failed to'
    )
    
    $errorsFound = @()
    foreach ($pattern in $errorPatterns) {
        if ($output -match $pattern) {
            $errorsFound += $pattern
        }
    }
    
    if ($errorsFound.Count -gt 0) {
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host "ERRORS DETECTED:" -ForegroundColor Red
        $errorsFound | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host ""
        Write-Host "Output saved to: $outputFile" -ForegroundColor Gray
        exit 1
    } else {
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Green
        Write-Host "NO ERRORS DETECTED - GUI LAUNCH APPEARS SUCCESSFUL" -ForegroundColor Green
        Write-Host "=" * 80 -ForegroundColor Green
        exit 0
    }
} else {
    Write-Host "No output file created" -ForegroundColor Yellow
    exit 1
}


