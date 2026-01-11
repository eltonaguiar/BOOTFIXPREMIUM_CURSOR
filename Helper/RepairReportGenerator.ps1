# RepairReportGenerator.ps1
# Comprehensive report generation for one-click boot repair

# Helper function to safely open files in Notepad (prevents multiple instances)
function Start-SafeNotepad {
    <#
    .SYNOPSIS
    Safely opens a file in Notepad, preventing duplicate instances of the same file.
    
    .PARAMETER FilePath
    Path to the file to open in Notepad.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    # Track opened files in a module-level variable
    if (-not $script:NotepadOpenedFiles) {
        $script:NotepadOpenedFiles = @{}
    }
    
    try {
        # Resolve full path
        $resolvedPath = if (Test-Path $FilePath) {
            (Resolve-Path $FilePath -ErrorAction SilentlyContinue).Path
        } else {
            $FilePath
        }
        
        if (-not $resolvedPath) {
            $resolvedPath = $FilePath
        }
        
        # Normalize path for comparison
        $normalizedPath = $resolvedPath.ToLower().Replace('\', '/')
        
        # Check if this file is already open (debounce within 5 seconds)
        if ($script:NotepadOpenedFiles.ContainsKey($normalizedPath)) {
            $lastOpened = $script:NotepadOpenedFiles[$normalizedPath]
            $timeSinceOpened = (Get-Date) - $lastOpened
            
            # If opened within last 5 seconds, don't open again
            if ($timeSinceOpened.TotalSeconds -lt 5) {
                # Try to bring existing Notepad window to front
                try {
                    $notepadProcesses = Get-Process -Name "notepad" -ErrorAction SilentlyContinue
                    foreach ($proc in $notepadProcesses) {
                        try {
                            $windowTitle = $proc.MainWindowTitle
                            if ($windowTitle -and ($windowTitle -like "*$(Split-Path -Leaf $resolvedPath)*" -or $windowTitle -eq $resolvedPath)) {
                                Add-Type -TypeDefinition @"
                                    using System;
                                    using System.Runtime.InteropServices;
                                    public class Win32 {
                                        [DllImport("user32.dll")]
                                        public static extern bool SetForegroundWindow(IntPtr hWnd);
                                        [DllImport("user32.dll")]
                                        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
                                    }
"@ -ErrorAction SilentlyContinue
                                [Win32]::ShowWindow($proc.MainWindowHandle, 9) # SW_RESTORE
                                [Win32]::SetForegroundWindow($proc.MainWindowHandle)
                                return
                            }
                        } catch {
                            # Continue to next process
                        }
                    }
                } catch {
                    # If we can't bring to front, just skip opening
                    return
                }
            }
        }
        
        # Open the file in Notepad
        if (Test-Path $resolvedPath) {
            Start-Process notepad.exe -ArgumentList "`"$resolvedPath`"" -ErrorAction SilentlyContinue
            # Track that we opened this file
            $script:NotepadOpenedFiles[$normalizedPath] = Get-Date
        } else {
            # File doesn't exist, but try to open it anyway (Notepad will show error)
            Start-Process notepad.exe -ArgumentList "`"$resolvedPath`"" -ErrorAction SilentlyContinue
            $script:NotepadOpenedFiles[$normalizedPath] = Get-Date
        }
        
        # Clean up old entries (older than 1 hour) to prevent memory bloat
        $cutoffTime = (Get-Date).AddHours(-1)
        $keysToRemove = $script:NotepadOpenedFiles.Keys | Where-Object {
            $script:NotepadOpenedFiles[$_] -lt $cutoffTime
        }
        foreach ($key in $keysToRemove) {
            $script:NotepadOpenedFiles.Remove($key)
        }
        
    } catch {
        # Fallback: just try to open normally
        try {
            Start-Process notepad.exe -ArgumentList "`"$FilePath`"" -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Failed to open Notepad: $_"
        }
    }
}

function New-RepairReport {
    <#
    .SYNOPSIS
    Creates a new repair report object to track commands, errors, and results.
    #>
    param(
        [string]$TargetDrive = "C",
        [string]$ReportPath = "$env:TEMP\BootRepairReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    )
    
    $report = [PSCustomObject]@{
        TargetDrive = $TargetDrive
        ReportPath = $ReportPath
        StartTime = Get-Date
        EndTime = $null
        Commands = New-Object System.Collections.ArrayList
        Errors = New-Object System.Collections.ArrayList
        Warnings = New-Object System.Collections.ArrayList
        IssuesFound = New-Object System.Collections.ArrayList
        IssuesFixed = New-Object System.Collections.ArrayList
        IssuesRemaining = New-Object System.Collections.ArrayList
        PostRepairVerification = $null
    }
    
    return $report
}

function Add-RepairCommand {
    <#
    .SYNOPSIS
    Adds a command to the repair report with its result.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Report,
        [Parameter(Mandatory=$true)]
        [string]$Command,
        [string]$Description = "",
        [string]$Output = "",
        [int]$ExitCode = 0,
        [bool]$Success = $true,
        [string]$Error = "",
        [bool]$IsRepairCommand = $false
    )
    
    $commandEntry = [PSCustomObject]@{
        Timestamp = Get-Date
        Command = $Command
        Description = $Description
        Output = $Output
        ExitCode = $ExitCode
        Success = $Success
        Error = $Error
        IsRepairCommand = $IsRepairCommand
    }
    
    [void]$Report.Commands.Add($commandEntry)
    
    # Track errors
    if (-not $Success -or $ExitCode -ne 0 -or $Error) {
        [void]$Report.Errors.Add($commandEntry)
    }
    
    return $commandEntry
}

function Add-RepairIssue {
    <#
    .SYNOPSIS
    Adds an issue to the repair report.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Report,
        [Parameter(Mandatory=$true)]
        [string]$Issue,
        [string]$Category = "Unknown",
        [bool]$Fixed = $false
    )
    
    $issueEntry = [PSCustomObject]@{
        Issue = $Issue
        Category = $Category
        Fixed = $Fixed
        Timestamp = Get-Date
    }
    
    if ($Fixed) {
        [void]$Report.IssuesFixed.Add($issueEntry)
    } else {
        [void]$Report.IssuesRemaining.Add($issueEntry)
    }
    
    [void]$Report.IssuesFound.Add($issueEntry)
    
    return $issueEntry
}

function Set-PostRepairVerification {
    <#
    .SYNOPSIS
    Sets the post-repair verification results.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Report,
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$VerificationResult
    )
    
    $Report.PostRepairVerification = $VerificationResult
}

function Export-RepairReport {
    <#
    .SYNOPSIS
    Exports the repair report to a formatted text file and opens it in Notepad.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Report,
        [switch]$OpenInNotepad = $true
    )
    
    $Report.EndTime = Get-Date
    $duration = $Report.EndTime - $Report.StartTime
    
    $reportContent = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    # Header
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("ONE-CLICK BOOT REPAIR REPORT") | Out-Null
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("") | Out-Null
    $reportContent.AppendLine("Generated: $($Report.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
    $reportContent.AppendLine("Duration: $($duration.ToString('hh\:mm\:ss'))") | Out-Null
    $reportContent.AppendLine("Target Drive: $($Report.TargetDrive):") | Out-Null
    $reportContent.AppendLine("") | Out-Null
    
    # CODE RED: FAILED COMMANDS (at the top as requested)
    if ($Report.Errors.Count -gt 0) {
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("CODE RED: FAILED COMMANDS!") | Out-Null
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("") | Out-Null
        $reportContent.AppendLine("The following commands failed during the repair process:") | Out-Null
        $reportContent.AppendLine("") | Out-Null
        
        foreach ($error in $Report.Errors) {
            $reportContent.AppendLine("FAILED COMMAND: $($error.Command)") | Out-Null
            if ($error.Description) {
                $reportContent.AppendLine("  Description: $($error.Description)") | Out-Null
            }
            if ($error.ExitCode -ne 0) {
                $reportContent.AppendLine("  Exit Code: $($error.ExitCode)") | Out-Null
            }
            if ($error.Error) {
                $reportContent.AppendLine("  Error: $($error.Error)") | Out-Null
            }
            if ($error.Output) {
                $outputPreview = $error.Output
                if ($outputPreview.Length -gt 500) {
                    $outputPreview = $outputPreview.Substring(0, 500) + "... (truncated)"
                }
                $reportContent.AppendLine("  Output: $outputPreview") | Out-Null
            }
            $reportContent.AppendLine("  Timestamp: $($error.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
            $reportContent.AppendLine("") | Out-Null
        }
        
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("") | Out-Null
    }
    
    # Summary
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("REPAIR SUMMARY") | Out-Null
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("") | Out-Null
    $reportContent.AppendLine("Total Commands Executed: $($Report.Commands.Count)") | Out-Null
    $reportContent.AppendLine("Failed Commands: $($Report.Errors.Count)") | Out-Null
    $reportContent.AppendLine("Issues Found: $($Report.IssuesFound.Count)") | Out-Null
    $reportContent.AppendLine("Issues Fixed: $($Report.IssuesFixed.Count)") | Out-Null
    $reportContent.AppendLine("Issues Remaining: $($Report.IssuesRemaining.Count)") | Out-Null
    $reportContent.AppendLine("") | Out-Null
    
    # What Was Wrong
    if ($Report.IssuesFound.Count -gt 0) {
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("WHAT WAS WRONG") | Out-Null
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("") | Out-Null
        
        foreach ($issue in $Report.IssuesFound) {
            $status = if ($issue.Fixed) { "[FIXED]" } else { "[NOT FIXED]" }
            $reportContent.AppendLine("$status $($issue.Category): $($issue.Issue)") | Out-Null
        }
        
        $reportContent.AppendLine("") | Out-Null
    }
    
    # What Is Still Wrong
    if ($Report.IssuesRemaining.Count -gt 0) {
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("WHAT IS STILL WRONG") | Out-Null
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("") | Out-Null
        
        foreach ($issue in $Report.IssuesRemaining) {
            $reportContent.AppendLine("[$($issue.Category)] $($issue.Issue)") | Out-Null
        }
        
        $reportContent.AppendLine("") | Out-Null
    }
    
    # Commands Executed
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("COMMANDS EXECUTED") | Out-Null
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("") | Out-Null
    
    foreach ($cmd in $Report.Commands) {
        $status = if ($cmd.Success) { "[SUCCESS]" } else { "[FAILED]" }
        $type = if ($cmd.IsRepairCommand) { "[REPAIR]" } else { "[DIAGNOSTIC]" }
        $reportContent.AppendLine("$status $type $($cmd.Command)") | Out-Null
        if ($cmd.Description) {
            $reportContent.AppendLine("  Description: $($cmd.Description)") | Out-Null
        }
        if ($cmd.ExitCode -ne 0) {
            $reportContent.AppendLine("  Exit Code: $($cmd.ExitCode)") | Out-Null
        }
        if ($cmd.Error) {
            $reportContent.AppendLine("  Error: $($cmd.Error)") | Out-Null
        }
        $reportContent.AppendLine("  Timestamp: $($cmd.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
        $reportContent.AppendLine("") | Out-Null
    }
    
    # Post-Repair Verification
    if ($Report.PostRepairVerification) {
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("POST-REPAIR VERIFICATION") | Out-Null
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("") | Out-Null
        $reportContent.AppendLine($Report.PostRepairVerification) | Out-Null
        $reportContent.AppendLine("") | Out-Null
    }
    
    # Footer
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("END OF REPORT") | Out-Null
    $reportContent.AppendLine($separator) | Out-Null
    
    # Write to file
    try {
        $reportContent.ToString() | Out-File -FilePath $Report.ReportPath -Encoding UTF8 -Force
        Write-Host "Report saved to: $($Report.ReportPath)" -ForegroundColor Green
        
        if ($OpenInNotepad) {
            Start-SafeNotepad -FilePath $Report.ReportPath
        }
        
        return $Report.ReportPath
    } catch {
        Write-Error "Failed to save report: $_"
        return $null
    }
}

function Get-FailureReportCommands {
    <#
    .SYNOPSIS
    Generates alternative commands for issues that could not be fixed automatically.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Report,
        [string]$TargetDrive = "C"
    )
    
    $commands = New-Object System.Collections.ArrayList
    $executedCommands = $Report.Commands | Where-Object { $_.IsRepairCommand } | ForEach-Object { $_.Command }
    
    foreach ($issue in $Report.IssuesRemaining) {
        $category = $issue.Category
        $issueText = $issue.Issue
        
        # Generate alternative commands based on issue type
        switch -Wildcard ($category) {
            "*winload*" {
                # Alternative winload.efi repair commands
                $altCommands = @(
                    "dism /Image:$TargetDrive`: /RestoreHealth /Source:wim:<path_to_install.wim>:1 /LimitAccess",
                    "sfc /ScanNow /OffBootDir=$TargetDrive`: /OffWinDir=$TargetDrive`:\Windows",
                    "copy /Y $TargetDrive`:\Windows\System32\Boot\winload.efi $TargetDrive`:\Windows\System32\winload.efi",
                    "bcdedit /set {default} path \Windows\system32\winload.efi",
                    "bcdedit /set {default} device partition=$TargetDrive`:",
                    "bcdedit /set {default} osdevice partition=$TargetDrive`:"
                )
                
                foreach ($cmd in $altCommands) {
                    # Only add if not already executed
                    $alreadyRun = $false
                    foreach ($exec in $executedCommands) {
                        if ($exec -like "*$($cmd.Split(' ')[0])*") {
                            $alreadyRun = $true
                            break
                        }
                    }
                    if (-not $alreadyRun) {
                        [void]$commands.Add([PSCustomObject]@{
                            Issue = $issueText
                            Command = $cmd
                            Description = "Alternative method to repair winload.efi"
                        })
                    }
                }
            }
            "*BCD*" {
                $altCommands = @(
                    "bcdedit /export $env:TEMP\BCD_backup.bak",
                    "bcdedit /store $env:TEMP\BCD_backup.bak /enum all",
                    "bootrec /rebuildbcd",
                    "bootrec /fixboot",
                    "bootrec /fixmbr",
                    "bcdboot $TargetDrive`:\Windows /s <ESP_DRIVE>: /f UEFI"
                )
                
                foreach ($cmd in $altCommands) {
                    $alreadyRun = $false
                    foreach ($exec in $executedCommands) {
                        if ($exec -like "*$($cmd.Split(' ')[0])*") {
                            $alreadyRun = $true
                            break
                        }
                    }
                    if (-not $alreadyRun) {
                        [void]$commands.Add([PSCustomObject]@{
                            Issue = $issueText
                            Command = $cmd
                            Description = "Alternative method to repair BCD"
                        })
                    }
                }
            }
            "*EFI*" {
                $altCommands = @(
                    "diskpart",
                    "  list disk",
                    "  select disk 0",
                    "  list partition",
                    "  select partition <EFI_PARTITION_NUMBER>",
                    "  assign letter=S",
                    "  exit",
                    "format S: /fs:FAT32 /q /y",
                    "bcdboot $TargetDrive`:\Windows /s S: /f UEFI"
                )
                
                foreach ($cmd in $altCommands) {
                    $alreadyRun = $false
                    foreach ($exec in $executedCommands) {
                        if ($exec -like "*$($cmd.Trim().Split(' ')[0])*") {
                            $alreadyRun = $true
                            break
                        }
                    }
                    if (-not $alreadyRun) {
                        [void]$commands.Add([PSCustomObject]@{
                            Issue = $issueText
                            Command = $cmd
                            Description = "Alternative method to repair EFI partition"
                        })
                    }
                }
            }
        }
    }
    
    return $commands
}

function Export-FailureReport {
    <#
    .SYNOPSIS
    Generates a detailed failure report with error messages, lookup information, and alternative commands.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Report,
        [string]$TargetDrive = "C",
        [switch]$OpenInNotepad = $true
    )
    
    $failureReportPath = "$env:TEMP\BootRepairFailureReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $reportContent = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    # Header
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("BOOT REPAIR FAILURE REPORT") | Out-Null
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("") | Out-Null
    $reportContent.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $reportContent.AppendLine("Target Drive: $TargetDrive`:") | Out-Null
    $reportContent.AppendLine("") | Out-Null
    
    # What Is Still Wrong
    if ($Report.IssuesRemaining.Count -gt 0) {
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("WHAT IS STILL WRONG") | Out-Null
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("") | Out-Null
        
        foreach ($issue in $Report.IssuesRemaining) {
            $reportContent.AppendLine("[$($issue.Category)] $($issue.Issue)") | Out-Null
        }
        
        $reportContent.AppendLine("") | Out-Null
    }
    
    # Error Messages to Look Up
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("ERROR MESSAGES TO LOOK UP") | Out-Null
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("") | Out-Null
    
    $errorMessages = @()
    foreach ($error in $Report.Errors) {
        if ($error.Error) {
            $errorMessages += $error.Error
        }
        if ($error.Output -match "error|failed|cannot|unable|denied|corrupt|missing") {
            $errorMessages += $error.Output
        }
    }
    
    if ($errorMessages.Count -gt 0) {
        $uniqueErrors = $errorMessages | Select-Object -Unique
        foreach ($err in $uniqueErrors) {
            $reportContent.AppendLine("  - $err") | Out-Null
        }
        $reportContent.AppendLine("") | Out-Null
        $reportContent.AppendLine("Search these error messages on Microsoft Support or TechNet for solutions.") | Out-Null
        $reportContent.AppendLine("") | Out-Null
    } else {
        $reportContent.AppendLine("No specific error messages captured.") | Out-Null
        $reportContent.AppendLine("") | Out-Null
    }
    
    # Alternative Commands to Try
    $altCommands = Get-FailureReportCommands -Report $Report -TargetDrive $TargetDrive
    if ($altCommands.Count -gt 0) {
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("ALTERNATIVE COMMANDS TO TRY") | Out-Null
        $reportContent.AppendLine($separator) | Out-Null
        $reportContent.AppendLine("") | Out-Null
        $reportContent.AppendLine("These commands were NOT run by the automated repair tool.") | Out-Null
        $reportContent.AppendLine("Try them manually in an elevated Command Prompt or PowerShell.") | Out-Null
        $reportContent.AppendLine("") | Out-Null
        
        $currentIssue = ""
        foreach ($cmd in $altCommands) {
            if ($cmd.Issue -ne $currentIssue) {
                if ($currentIssue) {
                    $reportContent.AppendLine("") | Out-Null
                }
                $currentIssue = $cmd.Issue
                $reportContent.AppendLine("For: $currentIssue") | Out-Null
                $reportContent.AppendLine("  $($cmd.Description)") | Out-Null
            }
            $reportContent.AppendLine("  Command: $($cmd.Command)") | Out-Null
        }
        
        $reportContent.AppendLine("") | Out-Null
    }
    
    # Details Related to Errors
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("DETAILS RELATED TO YOUR ERRORS") | Out-Null
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("") | Out-Null
    
    foreach ($error in $Report.Errors) {
        $reportContent.AppendLine("Failed Command: $($error.Command)") | Out-Null
        if ($error.Description) {
            $reportContent.AppendLine("  Purpose: $($error.Description)") | Out-Null
        }
        if ($error.ExitCode -ne 0) {
            $reportContent.AppendLine("  Exit Code: $($error.ExitCode)") | Out-Null
        }
        if ($error.Error) {
            $reportContent.AppendLine("  Error Message: $($error.Error)") | Out-Null
        }
        if ($error.Output) {
            $outputPreview = $error.Output
            if ($outputPreview.Length -gt 1000) {
                $outputPreview = $outputPreview.Substring(0, 1000) + "... (truncated)"
            }
            $reportContent.AppendLine("  Full Output:") | Out-Null
            $reportContent.AppendLine("    $outputPreview") | Out-Null
        }
        $reportContent.AppendLine("") | Out-Null
    }
    
    # Footer
    $reportContent.AppendLine($separator) | Out-Null
    $reportContent.AppendLine("END OF FAILURE REPORT") | Out-Null
    $reportContent.AppendLine($separator) | Out-Null
    
    # Write to file
    try {
        $reportContent.ToString() | Out-File -FilePath $failureReportPath -Encoding UTF8 -Force
        Write-Host "Failure report saved to: $failureReportPath" -ForegroundColor Yellow
        
        if ($OpenInNotepad) {
            Start-SafeNotepad -FilePath $failureReportPath
        }
        
        return $failureReportPath
    } catch {
        Write-Error "Failed to save failure report: $_"
        return $null
    }
}
