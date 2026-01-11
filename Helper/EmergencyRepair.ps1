<#
    EMERGENCY REPAIR ROUTINE
    ========================
    
    This is a minimal, syntax-error-resistant backup repair routine that can run
    even if WinRepairTUI.ps1, WinRepairGUI.ps1, or WinRepairCore.ps1 have syntax errors.
    
    It uses only basic Windows commands (bcdboot, bcdedit, mountvol) and minimal
    PowerShell syntax to ensure maximum reliability.
    
    USAGE:
    ------
    . .\Helper\EmergencyRepair.ps1
    Start-EmergencyRepair -Drive "C"
#>

function Start-EmergencyRepair {
    param(
        [string]$Drive = "C",
        [switch]$TestMode
    )
    
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Yellow
    Write-Host "EMERGENCY REPAIR ROUTINE" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This is a minimal backup repair routine that runs even if main scripts fail." -ForegroundColor Gray
    Write-Host ""
    
    $errors = @()
    $success = $false
    
    try {
        # Step 1: Mount EFI partition
        Write-Host "[1/4] Mounting EFI partition..." -ForegroundColor Cyan
        $efiMounted = $false
        $efiDrive = $null
        
        # Try mountvol first
        try {
            $mountResult = & mountvol S: /S 2>&1
            if ($LASTEXITCODE -eq 0) {
                $efiDrive = "S"
                $efiMounted = $true
                Write-Host "  [OK] EFI partition mounted as S:" -ForegroundColor Green
            }
        } catch {
            # Continue to diskpart fallback
        }
        
        # Fallback to diskpart if mountvol failed
        if (-not $efiMounted) {
            try {
                $diskpartScript = @"
select disk 0
list partition
select partition 1
assign letter=S
exit
"@
                $diskpartScript | & diskpart 2>&1 | Out-Null
                if (Test-Path "S:\") {
                    $efiDrive = "S"
                    $efiMounted = $true
                    Write-Host "  [OK] EFI partition mounted as S: via diskpart" -ForegroundColor Green
                }
            } catch {
                $errors += "Failed to mount EFI partition: $_"
                Write-Host "  [ERROR] Could not mount EFI partition" -ForegroundColor Red
            }
        }
        
        if (-not $efiMounted) {
            Write-Host "  [WARNING] EFI partition not mounted. Some repairs may be limited." -ForegroundColor Yellow
        }
        
        # Step 2: Rebuild BCD using bcdboot
        Write-Host ""
        Write-Host "[2/4] Rebuilding BCD..." -ForegroundColor Cyan
        
        if ($TestMode) {
            Write-Host "  [TEST MODE] Would run: bcdboot $Drive`:\Windows /s $efiDrive`: /f UEFI" -ForegroundColor Gray
            $bcdbootSuccess = $true
        } else {
            try {
                if ($efiMounted) {
                    $bcdbootCmd = "bcdboot $Drive`:\Windows /s $efiDrive`: /f UEFI"
                } else {
                    $bcdbootCmd = "bcdboot $Drive`:\Windows /f UEFI"
                }
                
                $bcdbootOutput = Invoke-Expression $bcdbootCmd 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $bcdbootSuccess = $true
                    Write-Host "  [OK] BCD rebuilt successfully" -ForegroundColor Green
                } else {
                    $bcdbootSuccess = $false
                    $errors += "bcdboot failed: $bcdbootOutput"
                    Write-Host "  [ERROR] bcdboot failed: $bcdbootOutput" -ForegroundColor Red
                }
            } catch {
                $bcdbootSuccess = $false
                $errors += "bcdboot exception: $_"
                Write-Host "  [ERROR] bcdboot exception: $_" -ForegroundColor Red
            }
        }
        
        # Step 3: Verify BCD accessibility
        Write-Host ""
        Write-Host "[3/4] Verifying BCD..." -ForegroundColor Cyan
        
        if ($TestMode) {
            Write-Host "  [TEST MODE] Would run: bcdedit /enum {bootmgr}" -ForegroundColor Gray
            $bcdVerifySuccess = $true
        } else {
            try {
                $bcdVerifyOutput = & bcdedit /enum {bootmgr} 2>&1
                if ($LASTEXITCODE -eq 0 -and $bcdVerifyOutput -match "bootmgr") {
                    $bcdVerifySuccess = $true
                    Write-Host "  [OK] BCD is accessible" -ForegroundColor Green
                } else {
                    $bcdVerifySuccess = $false
                    $errors += "BCD verification failed"
                    Write-Host "  [ERROR] BCD verification failed" -ForegroundColor Red
                }
            } catch {
                $bcdVerifySuccess = $false
                $errors += "BCD verification exception: $_"
                Write-Host "  [ERROR] BCD verification exception: $_" -ForegroundColor Red
            }
        }
        
        # Step 4: Check winload.efi
        Write-Host ""
        Write-Host "[4/4] Checking winload.efi..." -ForegroundColor Cyan
        
        if ($efiMounted) {
            $winloadPath = "$efiDrive`:\EFI\Microsoft\Boot\winload.efi"
            if (Test-Path $winloadPath) {
                Write-Host "  [OK] winload.efi found at $winloadPath" -ForegroundColor Green
                $winloadExists = $true
            } else {
                Write-Host "  [WARNING] winload.efi not found at $winloadPath" -ForegroundColor Yellow
                $winloadExists = $false
                $errors += "winload.efi not found"
            }
        } else {
            Write-Host "  [SKIP] Cannot check winload.efi (EFI partition not mounted)" -ForegroundColor Gray
            $winloadExists = $null
        }
        
        # Summary
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Yellow
        if ($bcdbootSuccess -and $bcdVerifySuccess) {
            Write-Host "EMERGENCY REPAIR COMPLETED SUCCESSFULLY" -ForegroundColor Green
            $success = $true
        } else {
            Write-Host "EMERGENCY REPAIR COMPLETED WITH ISSUES" -ForegroundColor Yellow
            if ($errors.Count -gt 0) {
                Write-Host ""
                Write-Host "Errors encountered:" -ForegroundColor Red
                foreach ($error in $errors) {
                    Write-Host "  - $error" -ForegroundColor Red
                }
            }
        }
        Write-Host "=" * 80 -ForegroundColor Yellow
        Write-Host ""
        
        return @{
            Success = $success
            Errors = $errors
            EFIMounted = $efiMounted
            BCDRebuilt = $bcdbootSuccess
            BCDVerified = $bcdVerifySuccess
            WinloadExists = $winloadExists
        }
        
    } catch {
        Write-Host ""
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host "EMERGENCY REPAIR FAILED" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host "=" * 80 -ForegroundColor Red
        Write-Host ""
        
        return @{
            Success = $false
            Errors = @("Emergency repair exception: $_")
        }
    }
}

# Export function
Export-ModuleMember -Function Start-EmergencyRepair
