<#
.SYNOPSIS
    Boot Repair Wizard - Interactive guided repair for WinPE/WinRE command prompt environments.

.DESCRIPTION
    Provides a step-by-step, user-confirmed boot repair process that:
    - Asks user if PC is not booting
    - Encourages backup before proceeding
    - Shows EXACT commands before execution
    - Requires explicit confirmation for each step
    - Explains what each command does
    - Records all changes for rollback

.PARAMETER TargetDrive
    Target Windows drive letter (auto-detected if not specified)

.EXAMPLE
    .\BootRepairWizard.ps1
    .\BootRepairWizard.ps1 -TargetDrive "C"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetDrive = $null
)

# Load core modules
# Fix for WinPE: Handle null MyInvocation.MyCommand.Path
$scriptRoot = $null
if ($MyInvocation.MyCommand.Path) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($PSScriptRoot) {
    $scriptRoot = $PSScriptRoot
} else {
    # Fallback: Try to get script root from current location
    $scriptRoot = Split-Path -Parent (Get-Location).Path
    # If we're in Helper directory, use it
    if ((Split-Path -Leaf $scriptRoot) -ne "Helper") {
        $scriptRoot = Join-Path $scriptRoot "Helper"
    }
}

# Try to load WinRepairCore.ps1
$corePath = Join-Path $scriptRoot "WinRepairCore.ps1"
if (-not (Test-Path $corePath)) {
    # Try parent directory
    $corePath = Join-Path (Split-Path -Parent $scriptRoot) "Helper\WinRepairCore.ps1"
}
if (-not (Test-Path $corePath)) {
    # Try current directory
    $corePath = ".\WinRepairCore.ps1"
    if (-not (Test-Path $corePath)) {
        Write-Error "Cannot find WinRepairCore.ps1. Please ensure it's in the Helper directory."
        exit 1
    }
}
. $corePath -ErrorAction Stop

function Show-BootRepairWizard {
    <#
    .SYNOPSIS
        Main wizard function that guides user through boot repair.
    #>
    param(
        [string]$WindowsDrive = "C"
    )
    
    Clear-Host
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  BOOT REPAIR WIZARD - Step-by-Step Guided Repair" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Step 0: Initial question
    Write-Host "Is your PC not booting? (Y/N): " -NoNewline -ForegroundColor Yellow
    $response = Read-Host
    if ($response -notmatch '^[Yy]') {
        Write-Host "`nIf your PC is booting normally, you may not need this wizard." -ForegroundColor Gray
        Write-Host "Press any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    Write-Host ""
    Write-Host "This wizard will guide you through repairing your Windows boot system." -ForegroundColor White
    Write-Host "Each step will show you EXACTLY what will be executed before running it." -ForegroundColor White
    Write-Host ""
    Write-Host "NOTE: If your drive is BitLocker encrypted, boot recovery operations may take longer." -ForegroundColor Yellow
    Write-Host "      This is normal - BitLocker encryption adds processing overhead to boot repairs." -ForegroundColor Yellow
    Write-Host ""
    
    # Backup reminder
    Write-Host "IMPORTANT: BACKUP REMINDER" -ForegroundColor Yellow
    Write-Host "===============================================================" -ForegroundColor Yellow
    Write-Host "Before proceeding, we STRONGLY recommend creating a system image backup." -ForegroundColor White
    Write-Host "This allows you to restore your system if something goes wrong." -ForegroundColor White
    Write-Host ""
    Write-Host "Have you created a backup? (Y/N/Skip): " -NoNewline -ForegroundColor Yellow
    $backupResponse = Read-Host
    if ($backupResponse -match '^[Nn]') {
        Write-Host ""
        Write-Host "We recommend creating a backup first. You can:" -ForegroundColor Yellow
        Write-Host "  1. Use Windows Backup (if available)" -ForegroundColor Gray
        Write-Host "  2. Use third-party backup software" -ForegroundColor Gray
        Write-Host "  3. Create a system image to external drive" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Continue anyway? (Y/N): " -NoNewline -ForegroundColor Yellow
        $continue = Read-Host
        if ($continue -notmatch '^[Yy]') {
            Write-Host "`nWizard cancelled. Please create a backup and try again." -ForegroundColor Yellow
            return
        }
    }
    
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  REPAIR STEPS" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Track changes for rollback documentation
    $changes = @()
    $stepNumber = 1
    
    # Step 1: Disk Check
    $proceed = Show-RepairStep -StepNumber $stepNumber `
        -Title "Disk Check" `
        -Command "chkdsk ${WindowsDrive}: /F /R" `
        -Description "Scans the disk for errors and repairs them. This ensures the disk is healthy before attempting boot repairs." `
        -Duration "15-30 minutes (depends on disk size)" `
        -Warning "This may take a long time. The system may appear frozen, but it's working."
    
    if ($proceed -eq "Y") {
        Write-Host "`nRunning disk check..." -ForegroundColor Cyan
        try {
            $output = chkdsk "${WindowsDrive}:" /F /R 2>&1 | Out-String
            Write-Host $output -ForegroundColor White
            $changes += @{
                Step = $stepNumber
                Command = "chkdsk ${WindowsDrive}: /F /R"
                Result = "Completed"
                Output = $output
            }
            Write-Host "`n[OK] Disk check completed." -ForegroundColor Green
        } catch {
            Write-Host "`n[ERROR] Disk check failed: $_" -ForegroundColor Red
            $changes += @{
                Step = $stepNumber
                Command = "chkdsk ${WindowsDrive}: /F /R"
                Result = "Failed: $_"
            }
        }
        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } elseif ($proceed -eq "Skip") {
        Write-Host "`nSkipping disk check." -ForegroundColor Yellow
    }
    
    $stepNumber++
    
    # Step 2: Boot Sector Repair
    $proceed = Show-RepairStep -StepNumber $stepNumber `
        -Title "Boot Sector Repair" `
        -Command "bootrec /fixboot" `
        -Description "Repairs the Windows boot sector. This fixes issues where the boot sector is corrupted or damaged." `
        -Duration "1-2 minutes"
    
    if ($proceed -eq "Y") {
        Write-Host "`nRepairing boot sector..." -ForegroundColor Cyan
        try {
            $output = bootrec /fixboot 2>&1 | Out-String
            Write-Host $output -ForegroundColor White
            $changes += @{
                Step = $stepNumber
                Command = "bootrec /fixboot"
                Result = "Completed"
                Output = $output
            }
            Write-Host "`n[OK] Boot sector repair completed." -ForegroundColor Green
        } catch {
            Write-Host "`n[ERROR] Boot sector repair failed: $_" -ForegroundColor Red
            $changes += @{
                Step = $stepNumber
                Command = "bootrec /fixboot"
                Result = "Failed: $_"
            }
        }
        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } elseif ($proceed -eq "Skip") {
        Write-Host "`nSkipping boot sector repair." -ForegroundColor Yellow
    }
    
    $stepNumber++
    
    # Step 3: MBR Repair
    $proceed = Show-RepairStep -StepNumber $stepNumber `
        -Title "Master Boot Record (MBR) Repair" `
        -Command "bootrec /fixmbr" `
        -Description "Repairs the Master Boot Record. This is needed for legacy BIOS systems or when the MBR is corrupted." `
        -Duration "1-2 minutes" `
        -Note "Note: This only applies to legacy BIOS systems. UEFI systems don't use MBR."
    
    if ($proceed -eq "Y") {
        Write-Host "`nRepairing MBR..." -ForegroundColor Cyan
        try {
            $output = bootrec /fixmbr 2>&1 | Out-String
            Write-Host $output -ForegroundColor White
            $changes += @{
                Step = $stepNumber
                Command = "bootrec /fixmbr"
                Result = "Completed"
                Output = $output
            }
            Write-Host "`n[OK] MBR repair completed." -ForegroundColor Green
        } catch {
            Write-Host "`n[ERROR] MBR repair failed: $_" -ForegroundColor Red
            $changes += @{
                Step = $stepNumber
                Command = "bootrec /fixmbr"
                Result = "Failed: $_"
            }
        }
        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } elseif ($proceed -eq "Skip") {
        Write-Host "`nSkipping MBR repair." -ForegroundColor Yellow
    }
    
    $stepNumber++
    
    # Step 4: BCD Rebuild
    $proceed = Show-RepairStep -StepNumber $stepNumber `
        -Title "Boot Configuration Data (BCD) Rebuild" `
        -Command "bootrec /rebuildbcd" `
        -Description "Rebuilds the Boot Configuration Data. This fixes issues where Windows boot entries are missing or corrupted." `
        -Duration "2-3 minutes" `
        -Warning "This will scan for Windows installations and rebuild the boot menu."
    
    if ($proceed -eq "Y") {
        Write-Host "`nRebuilding BCD..." -ForegroundColor Cyan
        Write-Host "This will scan for Windows installations. You may be prompted to add installations to the boot menu." -ForegroundColor Yellow
        Write-Host ""
        try {
            $output = bootrec /rebuildbcd 2>&1 | Out-String
            Write-Host $output -ForegroundColor White
            $changes += @{
                Step = $stepNumber
                Command = "bootrec /rebuildbcd"
                Result = "Completed"
                Output = $output
            }
            Write-Host "`n[OK] BCD rebuild completed." -ForegroundColor Green
        } catch {
            Write-Host "`n[ERROR] BCD rebuild failed: $_" -ForegroundColor Red
            $changes += @{
                Step = $stepNumber
                Command = "bootrec /rebuildbcd"
                Result = "Failed: $_"
            }
        }
        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } elseif ($proceed -eq "Skip") {
        Write-Host "`nSkipping BCD rebuild." -ForegroundColor Yellow
    }
    
    $stepNumber++
    
    # Step 5: Advanced - Driver Injection (Optional)
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  ADVANCED OPTION: Driver Injection" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "If your PC uses special storage drivers (NVMe, RAID, VMD), you may need" -ForegroundColor White
    Write-Host "to inject them into the offline Windows installation." -ForegroundColor White
    Write-Host ""
    Write-Host "Do you want to inject storage drivers? (Y/N): " -NoNewline -ForegroundColor Yellow
    $driverResponse = Read-Host
    
    if ($driverResponse -match '^[Yy]') {
        Write-Host ""
        Write-Host "Please provide the path to your driver folder (or press Enter to skip): " -NoNewline -ForegroundColor Yellow
        $driverPath = Read-Host
        
        if (-not [string]::IsNullOrWhiteSpace($driverPath) -and (Test-Path $driverPath)) {
            $proceed = Show-RepairStep -StepNumber $stepNumber `
                -Title "Driver Injection" `
                -Command "dism /Image:${WindowsDrive}:\ /Add-Driver /Driver:$driverPath /Recurse" `
                -Description "Injects storage drivers into the offline Windows installation. This is needed if Windows cannot see your storage drive." `
                -Duration "2-5 minutes"
            
            if ($proceed -eq "Y") {
                Write-Host "`nInjecting drivers..." -ForegroundColor Cyan
                try {
                    $imagePath = "${WindowsDrive}:"
                    $dismArgs = @(
                        "/Image:$imagePath\",
                        "/Add-Driver",
                        "/Driver:$driverPath",
                        "/Recurse"
                    )
                    $output = & dism $dismArgs 2>&1 | Out-String
                    Write-Host $output -ForegroundColor White
                    $changes += @{
                        Step = $stepNumber
                        Command = "dism /Image:${WindowsDrive}:\ /Add-Driver /Driver:$driverPath /Recurse"
                        Result = "Completed"
                        Output = $output
                    }
                    Write-Host "`n[OK] Driver injection completed." -ForegroundColor Green
                } catch {
                    Write-Host "`n[ERROR] Driver injection failed: $_" -ForegroundColor Red
                    $changes += @{
                        Step = $stepNumber
                        Command = "dism /Image:${WindowsDrive}:\ /Add-Driver /Driver:$driverPath /Recurse"
                        Result = "Failed: $_"
                    }
                }
            }
        } else {
            Write-Host "`nSkipping driver injection (invalid path or cancelled)." -ForegroundColor Yellow
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  REPAIR SUMMARY" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = ($changes | Where-Object { $_.Result -match "Completed" }).Count
    $failCount = ($changes | Where-Object { $_.Result -match "Failed" }).Count
    
    Write-Host "Steps completed: $successCount" -ForegroundColor $(if ($successCount -gt 0) { "Green" } else { "Yellow" })
    Write-Host "Steps failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
    Write-Host ""
    
    if ($changes.Count -gt 0) {
        Write-Host "Changes made (for rollback reference):" -ForegroundColor White
        foreach ($change in $changes) {
            Write-Host "  Step $($change.Step): $($change.Command)" -ForegroundColor Gray
            Write-Host "    Result: $($change.Result)" -ForegroundColor $(if ($change.Result -match "Completed") { "Green" } else { "Red" })
        }
        
        # Save rollback documentation
        $rollbackFile = "$env:TEMP\MiracleBoot_Rollback_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $rollbackContent = @"
Miracle Boot - Repair Rollback Documentation
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

REPAIR STEPS EXECUTED:
$($changes | ForEach-Object { "Step $($_.Step): $($_.Command)`nResult: $($_.Result)`n" } | Out-String)

MANUAL ROLLBACK INSTRUCTIONS:
If you need to undo these changes, you may need to:
1. Restore from system image backup (recommended)
2. Use System Restore if available
3. Manually reverse BCD changes using bcdedit

For assistance, refer to the Miracle Boot documentation or contact support.
"@
        Set-Content -Path $rollbackFile -Value $rollbackContent -Encoding UTF8
        Write-Host ""
        Write-Host "Rollback documentation saved to: $rollbackFile" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  NEXT STEPS" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Restart your computer and test if it boots normally." -ForegroundColor White
    Write-Host "2. If it still doesn't boot, check for:" -ForegroundColor White
    Write-Host "   - Missing storage drivers (may need driver injection)" -ForegroundColor Gray
    Write-Host "   - Hardware issues (failing disk, RAM problems)" -ForegroundColor Gray
    Write-Host "   - Corrupted Windows installation" -ForegroundColor Gray
    Write-Host "3. If problems persist, consider:" -ForegroundColor White
    Write-Host "   - Running an in-place repair installation" -ForegroundColor Gray
    Write-Host "   - Checking hardware health (SMART status, memory test)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-RepairStep {
    <#
    .SYNOPSIS
        Displays a repair step with command preview and confirmation.
    #>
    param(
        [int]$StepNumber,
        [string]$Title,
        [string]$Command,
        [string]$Description,
        [string]$Duration,
        [string]$Warning = $null,
        [string]$Note = $null
    )
    
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  Step $StepNumber - $Title" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Command that will be executed:" -ForegroundColor Yellow
    Write-Host "  $Command" -ForegroundColor White
    Write-Host ""
    Write-Host "What it does:" -ForegroundColor Yellow
    Write-Host "  $Description" -ForegroundColor White
    Write-Host ""
    Write-Host "Estimated duration: $Duration" -ForegroundColor Gray
    if ($Warning) {
        Write-Host ""
        Write-Host "WARNING: $Warning" -ForegroundColor Yellow
    }
    if ($Note) {
        Write-Host ""
        Write-Host "NOTE: $Note" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "Proceed with this step? (Y/N/Skip): " -NoNewline -ForegroundColor Yellow
    $response = Read-Host
    
    return $response
}

# Main execution
try {
    # Auto-detect Windows drive if not specified
    if ([string]::IsNullOrWhiteSpace($TargetDrive)) {
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\Windows") } | Sort-Object DriveLetter
        if ($volumes.Count -gt 0) {
            $TargetDrive = $volumes[0].DriveLetter
            Write-Host "Auto-detected Windows drive: ${TargetDrive}:" -ForegroundColor Cyan
        } else {
            $TargetDrive = "C"
            Write-Host "Could not auto-detect Windows drive. Using default: C:" -ForegroundColor Yellow
        }
    } else {
        $TargetDrive = $TargetDrive.TrimEnd(':').ToUpper()
    }
    
    Show-BootRepairWizard -WindowsDrive $TargetDrive
} catch {
    Write-Host "`n[ERROR] Boot Repair Wizard failed: $_" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}


