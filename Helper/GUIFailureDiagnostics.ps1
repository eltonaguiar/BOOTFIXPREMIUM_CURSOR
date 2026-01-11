# GUIFailureDiagnostics.ps1
# Generates diagnostic reports when GUI fails to launch

function New-GUIFailureReport {
    <#
    .SYNOPSIS
    Creates a comprehensive diagnostic report when GUI fails to launch.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FailureReason,
        [string]$ErrorDetails = "",
        [string]$ExceptionMessage = "",
        [string]$StackTrace = "",
        [string]$InnerException = "",
        [string]$FailurePoint = "Unknown"
    )
    
    $reportPath = "$env:TEMP\MiracleBoot_GUI_Failure_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    # Header
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("MIRACLE BOOT - GUI LAUNCH FAILURE DIAGNOSTIC REPORT") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Quick Summary (for easy typing)
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("QUICK SUMMARY (Copy this if you can't paste the full report)") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("GUI failed to launch. Reason: $FailureReason") | Out-Null
    $report.AppendLine("Failure point: $FailurePoint") | Out-Null
    if ($ExceptionMessage) {
        $report.AppendLine("Error: $ExceptionMessage") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # System Information
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("SYSTEM INFORMATION") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $report.AppendLine("Operating System: $($os.Caption)") | Out-Null
            $report.AppendLine("Version: $($os.Version)") | Out-Null
            $report.AppendLine("Build: $($os.BuildNumber)") | Out-Null
            $report.AppendLine("Architecture: $($os.OSArchitecture)") | Out-Null
        }
    } catch {
        $report.AppendLine("Operating System: Could not retrieve (Error: $_)") | Out-Null
    }
    
    try {
        $report.AppendLine("PowerShell Version: $($PSVersionTable.PSVersion)") | Out-Null
        $report.AppendLine("PowerShell Edition: $($PSVersionTable.PSEdition)") | Out-Null
        $report.AppendLine("CLR Version: $($PSVersionTable.CLRVersion)") | Out-Null
    } catch {
        $report.AppendLine("PowerShell Info: Could not retrieve") | Out-Null
    }
    
    try {
        $report.AppendLine("System Drive: $env:SystemDrive") | Out-Null
        $report.AppendLine("Computer Name: $env:COMPUTERNAME") | Out-Null
        $report.AppendLine("User: $env:USERNAME") | Out-Null
    } catch {}
    
    try {
        $envType = Get-EnvironmentType -ErrorAction SilentlyContinue
        $report.AppendLine("Environment Type: $envType") | Out-Null
    } catch {
        $report.AppendLine("Environment Type: Could not determine") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # Failure Details
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("FAILURE DETAILS") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Failure Reason: $FailureReason") | Out-Null
    $report.AppendLine("Failure Point: $FailurePoint") | Out-Null
    $report.AppendLine("") | Out-Null
    
    if ($ExceptionMessage) {
        $report.AppendLine("Exception Message:") | Out-Null
        $report.AppendLine("  $ExceptionMessage") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    if ($InnerException) {
        $report.AppendLine("Inner Exception:") | Out-Null
        $report.AppendLine("  $InnerException") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    if ($ErrorDetails) {
        $report.AppendLine("Error Details:") | Out-Null
        $report.AppendLine("  $ErrorDetails") | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    if ($StackTrace) {
        $report.AppendLine("Stack Trace:") | Out-Null
        $report.AppendLine($StackTrace) | Out-Null
        $report.AppendLine("") | Out-Null
    }
    
    # WPF Assembly Check
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("WPF ASSEMBLY AVAILABILITY") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $assemblies = @(
        @{ Name = "PresentationFramework"; Required = $true },
        @{ Name = "System.Windows.Forms"; Required = $true },
        @{ Name = "System.Drawing"; Required = $true },
        @{ Name = "WindowsBase"; Required = $false },
        @{ Name = "PresentationCore"; Required = $false }
    )
    
    foreach ($asm in $assemblies) {
        try {
            Add-Type -AssemblyName $asm.Name -ErrorAction Stop
            $report.AppendLine("[OK] $($asm.Name) - Available") | Out-Null
        } catch {
            $status = if ($asm.Required) { "[FAILED - REQUIRED]" } else { "[FAILED - OPTIONAL]" }
            $report.AppendLine("$status $($asm.Name) - Error: $_") | Out-Null
        }
    }
    
    $report.AppendLine("") | Out-Null
    
    # Threading Mode Check
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("THREADING MODE") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    try {
        $currentThread = [System.Threading.Thread]::CurrentThread
        $apartmentState = $currentThread.GetApartmentState()
        $report.AppendLine("Current Apartment State: $apartmentState") | Out-Null
        if ($apartmentState -ne 'STA') {
            $report.AppendLine("[WARNING] WPF requires STA mode, but current mode is: $apartmentState") | Out-Null
            $report.AppendLine("Solution: Launch PowerShell with -STA flag: powershell.exe -STA -File MiracleBoot.ps1") | Out-Null
        } else {
            $report.AppendLine("[OK] Threading mode is correct (STA)") | Out-Null
        }
    } catch {
        $report.AppendLine("Could not check threading mode: $_") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # File System Checks
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("FILE SYSTEM CHECKS") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    
    $filesToCheck = @(
        "Helper\WinRepairGUI.ps1",
        "Helper\WinRepairCore.ps1",
        "Helper\WinRepairTUI.ps1",
        "MiracleBoot.ps1"
    )
    
    foreach ($file in $filesToCheck) {
        $fullPath = Join-Path $scriptRoot $file
        if (Test-Path $fullPath) {
            try {
                $fileInfo = Get-Item $fullPath
                $report.AppendLine("[OK] $file - Exists ($($fileInfo.Length) bytes, Modified: $($fileInfo.LastWriteTime))") | Out-Null
            } catch {
                $report.AppendLine("[WARNING] $file - Exists but cannot read details: $_") | Out-Null
            }
        } else {
            $report.AppendLine("[MISSING] $file - Not found at: $fullPath") | Out-Null
        }
    }
    
    $report.AppendLine("") | Out-Null
    
    # .NET Framework Check
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine(".NET FRAMEWORK INFORMATION") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    try {
        $dotNetVersion = [System.Environment]::Version
        $report.AppendLine(".NET CLR Version: $dotNetVersion") | Out-Null
    } catch {
        $report.AppendLine(".NET CLR Version: Could not determine") | Out-Null
    }
    
    try {
        $dotNetFramework = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" -Name Release -ErrorAction SilentlyContinue
        if ($dotNetFramework) {
            $report.AppendLine(".NET Framework Release: $($dotNetFramework.Release)") | Out-Null
        }
    } catch {
        $report.AppendLine(".NET Framework: Could not determine version") | Out-Null
    }
    
    $report.AppendLine("") | Out-Null
    
    # Recommendations
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("RECOMMENDATIONS") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    
    switch ($FailurePoint) {
        "WPF_Assemblies" {
            $report.AppendLine("1. Install or repair .NET Framework 4.8 or later") | Out-Null
            $report.AppendLine("2. Run Windows Update to ensure all .NET components are current") | Out-Null
            $report.AppendLine("3. Try running: sfc /scannow (as Administrator)") | Out-Null
        }
        "Readiness_Gate" {
            $report.AppendLine("1. Review the blockers listed above and fix syntax errors") | Out-Null
            $report.AppendLine("2. Check Helper\WinRepairGUI.ps1 for syntax issues") | Out-Null
            $report.AppendLine("3. Run: Get-Content Helper\WinRepairGUI.ps1 | Select-String -Pattern 'ParserError|SyntaxError'") | Out-Null
        }
        "GUI_Module_Load" {
            $report.AppendLine("1. Check Helper\WinRepairGUI.ps1 for syntax errors") | Out-Null
            $report.AppendLine("2. Verify all required modules are present") | Out-Null
            $report.AppendLine("3. Check PowerShell execution policy: Get-ExecutionPolicy") | Out-Null
        }
        "Start_GUI_Function" {
            $report.AppendLine("1. Verify Helper\WinRepairGUI.ps1 contains Start-GUI function") | Out-Null
            $report.AppendLine("2. Check for syntax errors preventing function definition") | Out-Null
        }
        "GUI_Window_Launch" {
            $report.AppendLine("1. Check if another instance of the GUI is already running") | Out-Null
            $report.AppendLine("2. Verify XAML is valid (check Helper\WinRepairGUI.ps1 XAML section)") | Out-Null
            $report.AppendLine("3. Check Windows Event Viewer for .NET errors") | Out-Null
            $report.AppendLine("4. Try running as Administrator") | Out-Null
        }
        default {
            $report.AppendLine("1. Review error details above") | Out-Null
            $report.AppendLine("2. Check Windows Event Viewer for related errors") | Out-Null
            $report.AppendLine("3. Try running as Administrator") | Out-Null
            $report.AppendLine("4. Verify .NET Framework is installed and up to date") | Out-Null
        }
    }
    
    $report.AppendLine("") | Out-Null
    $report.AppendLine("5. Use TUI mode (text interface) which is more reliable in limited environments") | Out-Null
    $report.AppendLine("6. Provide this report to support for investigation") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # Footer
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("END OF REPORT") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("This report has been saved to:") | Out-Null
    $report.AppendLine("  $reportPath") | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("Please provide this file to support for investigation.") | Out-Null
    
    # Write to file
    try {
        $report.ToString() | Out-File -FilePath $reportPath -Encoding UTF8 -Force
        return $reportPath
    } catch {
        Write-Warning "Could not save GUI failure report: $_"
        return $null
    }
}

function Show-GUIFailureReport {
    <#
    .SYNOPSIS
    Creates and displays a GUI failure diagnostic report.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FailureReason,
        [string]$ErrorDetails = "",
        [Exception]$Exception = $null,
        [string]$FailurePoint = "Unknown"
    )
    
    $exceptionMessage = ""
    $innerException = ""
    $stackTrace = ""
    
    if ($Exception) {
        $exceptionMessage = $Exception.Message
        if ($Exception.InnerException) {
            $innerException = $Exception.InnerException.Message
        }
        $stackTrace = $Exception.StackTrace
    }
    
    $reportPath = New-GUIFailureReport -FailureReason $FailureReason `
                                         -ErrorDetails $ErrorDetails `
                                         -ExceptionMessage $exceptionMessage `
                                         -StackTrace $stackTrace `
                                         -InnerException $innerException `
                                         -FailurePoint $FailurePoint
    
    if ($reportPath) {
        # Open in Notepad
        try {
            Start-Process notepad.exe -ArgumentList $reportPath -ErrorAction Stop
            Write-Host "" -ForegroundColor Green
            Write-Host "GUI Failure Diagnostic Report" -ForegroundColor Yellow
            Write-Host "============================" -ForegroundColor Yellow
            Write-Host "A diagnostic report has been generated and opened in Notepad." -ForegroundColor White
            Write-Host "Report location: $reportPath" -ForegroundColor Gray
            Write-Host "" -ForegroundColor White
            Write-Host "The report contains:" -ForegroundColor Cyan
            Write-Host "  - Quick summary (for easy typing)" -ForegroundColor White
            Write-Host "  - System information" -ForegroundColor White
            Write-Host "  - Failure details" -ForegroundColor White
            Write-Host "  - Diagnostic checks" -ForegroundColor White
            Write-Host "  - Recommendations" -ForegroundColor White
            Write-Host "" -ForegroundColor White
        } catch {
            Write-Host "Could not open report in Notepad: $_" -ForegroundColor Yellow
            Write-Host "Report saved to: $reportPath" -ForegroundColor Yellow
        }
    }
    
    return $reportPath
}
