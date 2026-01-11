<#
.SYNOPSIS
    Advanced Boot Troubleshooting Module for MiracleBoot
    Handles complex boot repair scenarios beyond simple file corruption

.DESCRIPTION
    This module provides advanced diagnostics and repair options for:
    - Intel VMD driver issues (Z790 boards)
    - EFI partition recreation
    - Multiple boot drive conflicts
    - SFC/DISM repairs from WinPE
    - BIOS/firmware state checks
    - Pending updates detection
    - Read-only drive issues
    - MBR/GPT corruption

.NOTES
    Author: MiracleBoot Team
    Version: 1.0
    Date: 2026-01-10
#>

function Test-VMDDriverIssue {
    <#
    .SYNOPSIS
    Detects Intel VMD (Volume Management Device) driver issues on Z790 boards.
    
    .DESCRIPTION
    On newer Intel Z790 boards, VMD is often enabled by default in BIOS.
    This can cause drives to be "invisible" to Windows PE, leading to boot failures.
    
    .OUTPUTS
    PSCustomObject with:
    - VMDDetected: Boolean indicating if VMD controller is present
    - DriverLoaded: Boolean indicating if VMD driver is loaded
    - Recommendation: Action to take
    - DriverPath: Path to VMD driver if found
    #>
    
    $result = [PSCustomObject]@{
        VMDDetected = $false
        DriverLoaded = $false
        Recommendation = ""
        DriverPath = $null
        HardwareID = $null
    }
    
    try {
        # Check for Intel VMD controllers (common PCI IDs)
        $vmdControllers = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
            $_.InstanceId -match "VEN_8086&DEV_9A0B" -or  # Intel VMD (Alder Lake/Raptor Lake)
            $_.InstanceId -match "VEN_8086&DEV_467F" -or  # Intel VMD (Tiger Lake)
            $_.InstanceId -match "VEN_8086&DEV_4E3D" -or  # Intel VMD (Ice Lake)
            $_.FriendlyName -match "Volume Management Device|VMD"
        }
        
        if ($vmdControllers) {
            $result.VMDDetected = $true
            $vmdController = $vmdControllers | Select-Object -First 1
            $result.HardwareID = $vmdController.InstanceId
            
            # Check if driver is loaded
            $errorCode = $vmdController.Status
            if ($errorCode -eq "OK" -or $errorCode -eq 0) {
                $result.DriverLoaded = $true
                $result.Recommendation = "VMD driver is loaded. If boot issues persist, check BIOS VMD settings."
            } else {
                $result.DriverLoaded = $false
                $result.Recommendation = "VMD controller detected but driver not loaded. Load driver using: drvload [path]\iaStorVD.inf"
                
                # Try to find VMD driver
                $possiblePaths = @(
                    "$env:SystemRoot\System32\DriverStore\FileRepository\*iaStorVD*",
                    "$env:SystemRoot\System32\drivers\iaStorVD.sys",
                    "C:\Windows\System32\DriverStore\FileRepository\*iaStorVD*",
                    "D:\Windows\System32\DriverStore\FileRepository\*iaStorVD*"
                )
                
                foreach ($path in $possiblePaths) {
                    $found = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) {
                        if ($found.Extension -eq ".inf") {
                            $result.DriverPath = $found.FullName
                        } elseif ($found.Directory) {
                            $infFile = Get-ChildItem -Path $found.Directory.FullName -Filter "*.inf" -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($infFile) {
                                $result.DriverPath = $infFile.FullName
                            }
                        }
                        break
                    }
                }
            }
        } else {
            $result.Recommendation = "No VMD controller detected. VMD is not the issue."
        }
    } catch {
        $result.Recommendation = "Could not check VMD status: $_"
    }
    
    return $result
}

function Start-VMDDriverLoad {
    <#
    .SYNOPSIS
    Attempts to load Intel VMD driver in WinPE environment.
    
    .PARAMETER DriverPath
    Path to the VMD driver INF file.
    
    .PARAMETER AutoFind
    If set, attempts to automatically locate the VMD driver.
    #>
    param(
        [string]$DriverPath,
        [switch]$AutoFind
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        Message = ""
        DriverPath = $null
    }
    
    try {
        if ($AutoFind) {
            $vmdCheck = Test-VMDDriverIssue
            if ($vmdCheck.DriverPath) {
                $DriverPath = $vmdCheck.DriverPath
            } else {
                $result.Message = "Could not automatically locate VMD driver. Please provide path manually."
                return $result
            }
        }
        
        if (-not $DriverPath -or -not (Test-Path $DriverPath)) {
            $result.Message = "VMD driver path not found: $DriverPath"
            return $result
        }
        
        Write-Host "Loading VMD driver: $DriverPath" -ForegroundColor Yellow
        $loadResult = drvload $DriverPath 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $result.Success = $true
            $result.Message = "VMD driver loaded successfully."
            $result.DriverPath = $DriverPath
        } else {
            $result.Message = "Failed to load VMD driver: $loadResult"
        }
    } catch {
        $result.Message = "Error loading VMD driver: $_"
    }
    
    return $result
}

function Test-MultipleBootDrives {
    <#
    .SYNOPSIS
    Detects multiple drives that might have boot entries, causing conflicts.
    
    .DESCRIPTION
    When multiple drives have Windows installations, UEFI firmware can get confused
    about which drive is the actual "Windows Boot Manager", causing boot failures.
    #>
    
    $result = [PSCustomObject]@{
        MultipleDrivesDetected = $false
        BootDrives = @()
        Recommendation = ""
    }
    
    try {
        $installations = @(Get-WindowsInstallations)
        
        if ($installations.Count -gt 1) {
            $result.MultipleDrivesDetected = $true
            $result.BootDrives = $installations | ForEach-Object { "$($_.DriveLetter):" }
            $result.Recommendation = "Multiple Windows installations detected on: $($result.BootDrives -join ', ').`n" +
                                    "Unplug all drives except your primary NVME boot drive, then attempt repair.`n" +
                                    "After repair succeeds, you can reconnect other drives and clean up boot entries using msconfig or EasyBCD."
        } else {
            $result.Recommendation = "Only one Windows installation detected. Multiple boot drives are not the issue."
        }
    } catch {
        $result.Recommendation = "Could not check for multiple boot drives: $_"
    }
    
    return $result
}

function Start-EFIPartitionRecreation {
    <#
    .SYNOPSIS
    Recreates the EFI System Partition from scratch (destructive to EFI partition only).
    
    .DESCRIPTION
    Sometimes the BCD store is "locked" or marked as read-only by a failed update.
    This function deletes and recreates the EFI partition, then rebuilds boot files.
    
    .PARAMETER WindowsDrive
    Drive letter of the Windows installation (e.g., "C")
    
    .PARAMETER DiskNumber
    Disk number containing the Windows installation
    
    .PARAMETER EFISizeMB
    Size of EFI partition to create (default: 100MB)
    
    .WARNING
    This is DESTRUCTIVE to the EFI partition only. Your data partition is safe.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory=$false)]
        [int]$DiskNumber = -1,
        
        [Parameter(Mandatory=$false)]
        [int]$EFISizeMB = 100
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        Message = ""
        EFIDrive = $null
        Commands = @()
    }
    
    try {
        # Get disk number if not provided
        if ($DiskNumber -eq -1) {
            $vol = Get-Volume -DriveLetter $WindowsDrive -ErrorAction SilentlyContinue
            if ($vol) {
                $part = Get-Partition -Volume $vol -ErrorAction SilentlyContinue
                if ($part) {
                    $DiskNumber = $part.DiskNumber
                }
            }
        }
        
        if ($DiskNumber -eq -1) {
            $result.Message = "Could not determine disk number for drive $WindowsDrive"
            return $result
        }
        
        Write-Host "WARNING: This will DELETE and RECREATE the EFI partition!" -ForegroundColor Red
        Write-Host "Your data partition is safe, but boot entries will be lost." -ForegroundColor Yellow
        Write-Host ""
        
        # Create diskpart script
        $diskpartScript = @"
select disk $DiskNumber
list partition
"@
        
        $partitions = $diskpartScript | diskpart | Out-String
        
        # Find EFI partition
        $efiPartition = $null
        if ($partitions -match "System|EFI") {
            # Try to identify EFI partition by size (usually 100-500MB)
            $lines = $partitions -split "`n"
            foreach ($line in $lines) {
                if ($line -match "Partition\s+(\d+).*?(\d+)\s+(MB|GB)") {
                    $partNum = $matches[1]
                    $size = [int]$matches[2]
                    if ($size -ge 90 -and $size -le 600) {
                        $efiPartition = $partNum
                        break
                    }
                }
            }
        }
        
        if (-not $efiPartition) {
            $result.Message = "Could not identify EFI partition. Please run diskpart manually to identify it."
            return $result
        }
        
        # Create full diskpart script
        $fullScript = @"
select disk $DiskNumber
select partition $efiPartition
delete partition override
create partition efi size=$EFISizeMB
format quick fs=fat32 label="System"
assign letter=S
active
exit
"@
        
        $result.Commands += "diskpart script executed"
        
        # Execute diskpart
        $diskpartResult = $fullScript | diskpart 2>&1 | Out-String
        
        if ($LASTEXITCODE -eq 0 -or $diskpartResult -match "successfully") {
            # Rebuild boot files
            $bcdbootCmd = "bcdboot $WindowsDrive`:\Windows /s S: /f UEFI"
            $result.Commands += $bcdbootCmd
            
            $bcdbootResult = Invoke-Expression $bcdbootCmd 2>&1 | Out-String
            
            if ($LASTEXITCODE -eq 0) {
                $result.Success = $true
                $result.EFIDrive = "S:"
                $result.Message = "EFI partition recreated and boot files rebuilt successfully."
            } else {
                $result.Message = "EFI partition recreated but bcdboot failed: $bcdbootResult"
            }
        } else {
            $result.Message = "Failed to recreate EFI partition: $diskpartResult"
        }
        
    } catch {
        $result.Message = "Error during EFI partition recreation: $_"
    }
    
    return $result
}

function Start-WinPESFCDISMRepair {
    <#
    .SYNOPSIS
    Runs SFC and DISM repairs from WinPE environment.
    
    .DESCRIPTION
    If winload.efi is truly missing or 0KB, you need to pull a fresh copy from the
    Windows Image (WIM) file on recovery media.
    
    .PARAMETER WindowsDrive
    Drive letter of the Windows installation (e.g., "C")
    
    .PARAMETER SourceDrive
    Drive letter of USB Installation Media containing install.wim (e.g., "D")
    
    .PARAMETER WIMIndex
    Index of Windows edition in WIM file (default: 1)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$WindowsDrive,
        
        [Parameter(Mandatory=$false)]
        [string]$SourceDrive = "D",
        
        [Parameter(Mandatory=$false)]
        [int]$WIMIndex = 1
    )
    
    $result = [PSCustomObject]@{
        Success = $false
        Message = ""
        DISMOutput = ""
        SFCOutput = ""
    }
    
    try {
        $windowsPath = "$WindowsDrive`:\Windows"
        $wimPath = "$SourceDrive`:\sources\install.wim"
        
        if (-not (Test-Path $wimPath)) {
            $result.Message = "Could not find install.wim at $wimPath. Please specify correct source drive."
            return $result
        }
        
        # Step 1: DISM RestoreHealth
        Write-Host "Running DISM /RestoreHealth..." -ForegroundColor Yellow
        $dismCmd = "dism /Image:${WindowsDrive}:\ /Cleanup-Image /RestoreHealth /Source:wim:${wimPath}:${WIMIndex} /LimitAccess"
        $dismResult = Invoke-Expression $dismCmd 2>&1 | Out-String
        $result.DISMOutput = $dismResult
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "DISM completed successfully." -ForegroundColor Green
            
            # Step 2: SFC /ScanNow
            Write-Host "Running SFC /ScanNow..." -ForegroundColor Yellow
            $sfcCmd = "sfc /scannow /offbootdir=$WindowsDrive`:\ /offwindir=$windowsPath"
            $sfcResult = Invoke-Expression $sfcCmd 2>&1 | Out-String
            $result.SFCOutput = $sfcResult
            
            if ($LASTEXITCODE -eq 0) {
                $result.Success = $true
                $result.Message = "DISM and SFC repairs completed successfully."
            } else {
                $result.Message = "DISM succeeded but SFC failed: $sfcResult"
            }
        } else {
            $result.Message = "DISM failed: $dismResult"
        }
        
    } catch {
        $result.Message = "Error during WinPE SFC/DISM repair: $_"
    }
    
    return $result
}

function Test-PendingUpdates {
    <#
    .SYNOPSIS
    Checks for pending Windows updates that might be blocking boot repair.
    
    .DESCRIPTION
    Sometimes C:\Windows\WinSxS\pending.xml indicates pending updates that can
    prevent boot configuration changes.
    #>
    
    $result = [PSCustomObject]@{
        PendingUpdatesFound = $false
        PendingXMLPath = $null
        Recommendation = ""
    }
    
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne 'X' }
        
        foreach ($drive in $drives) {
            $pendingPath = "$($drive.Name):\Windows\WinSxS\pending.xml"
            if (Test-Path $pendingPath) {
                $result.PendingUpdatesFound = $true
                $result.PendingXMLPath = $pendingPath
                $result.Recommendation = "Pending updates file found at: $pendingPath`n" +
                                        "Rename or delete this file to allow boot repair: `n" +
                                        "  Rename-Item '$pendingPath' '$pendingPath.old'"
                break
            }
        }
        
        if (-not $result.PendingUpdatesFound) {
            $result.Recommendation = "No pending updates detected. Pending updates are not blocking repair."
        }
    } catch {
        $result.Recommendation = "Could not check for pending updates: $_"
    }
    
    return $result
}

function Test-ReadOnlyDrive {
    <#
    .SYNOPSIS
    Checks if the Windows drive is marked as read-only.
    
    .PARAMETER WindowsDrive
    Drive letter of the Windows installation
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$WindowsDrive
    )
    
    $result = [PSCustomObject]@{
        IsReadOnly = $false
        Recommendation = ""
    }
    
    try {
        $vol = Get-Volume -DriveLetter $WindowsDrive -ErrorAction SilentlyContinue
        if ($vol) {
            $part = Get-Partition -Volume $vol -ErrorAction SilentlyContinue
            if ($part) {
                $disk = Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue
                if ($disk) {
                    if ($disk.IsReadOnly) {
                        $result.IsReadOnly = $true
                        $result.Recommendation = "Drive is marked as read-only. Run in diskpart: `n" +
                                                 "  select disk $($disk.Number)`n" +
                                                 "  attributes disk clear readonly"
                    } else {
                        $result.Recommendation = "Drive is not read-only. Read-only status is not the issue."
                    }
                }
            }
        }
    } catch {
        $result.Recommendation = "Could not check read-only status: $_"
    }
    
    return $result
}

function Test-MBRGPTCorruption {
    <#
    .SYNOPSIS
    Checks for MBR/GPT corruption that might prevent boot repair.
    
    .PARAMETER WindowsDrive
    Drive letter of the Windows installation
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$WindowsDrive
    )
    
    $result = [PSCustomObject]@{
        CorruptionDetected = $false
        CorruptionType = ""
        Recommendation = ""
    }
    
    try {
        $vol = Get-Volume -DriveLetter $WindowsDrive -ErrorAction SilentlyContinue
        if ($vol) {
            $part = Get-Partition -Volume $vol -ErrorAction SilentlyContinue
            if ($part) {
                $disk = Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue
                if ($disk) {
                    if ($disk.PartitionStyle -eq "GPT") {
                        # Check GPT integrity
                        $gptCheck = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
                        if (-not $gptCheck) {
                            $result.CorruptionDetected = $true
                            $result.CorruptionType = "GPT"
                            $result.Recommendation = "GPT corruption detected. Run: bootsect /nt60 ALL /force /mbr`n" +
                                                     "Or recreate GPT: gptgen [drive]"
                        }
                    } elseif ($disk.PartitionStyle -eq "MBR") {
                        # Check MBR integrity
                        $mbrCheck = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
                        if (-not $mbrCheck) {
                            $result.CorruptionDetected = $true
                            $result.CorruptionType = "MBR"
                            $result.Recommendation = "MBR corruption detected. Run: bootsect /nt60 ALL /force /mbr"
                        }
                    }
                }
            }
        }
        
        if (-not $result.CorruptionDetected) {
            $result.Recommendation = "No MBR/GPT corruption detected."
        }
    } catch {
        $result.Recommendation = "Could not check MBR/GPT status: $_"
    }
    
    return $result
}

function Get-BIOSFirmwareRecommendations {
    <#
    .SYNOPSIS
    Provides BIOS/firmware recommendations for boot issues.
    
    .DESCRIPTION
    Checks system information and provides specific BIOS recommendations for:
    - Secure Boot settings
    - CSM (Compatibility Support Module) settings
    - VMD settings
    #>
    
    $result = [PSCustomObject]@{
        Recommendations = @()
        SecureBootStatus = "Unknown"
        CSMRecommendation = ""
        VMDRecommendation = ""
    }
    
    try {
        # Check Secure Boot status
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
        if ($secureBoot) {
            $result.SecureBootStatus = "Enabled"
            $result.Recommendations += "Secure Boot is ENABLED. If boot repair fails, try disabling Secure Boot temporarily in BIOS (set to 'Other OS' or 'Disabled')."
        } else {
            $result.SecureBootStatus = "Disabled"
            $result.Recommendations += "Secure Boot is disabled. This is fine for most boot repairs."
        }
        
        # CSM recommendation
        $result.CSMRecommendation = "CSM (Compatibility Support Module) should be DISABLED for NVME/UEFI boot.`n" +
                                    "If CSM is enabled, winload.efi often fails to initialize.`n" +
                                    "Check BIOS -> Boot -> CSM and ensure it's disabled."
        
        # VMD recommendation
        $vmdCheck = Test-VMDDriverIssue
        if ($vmdCheck.VMDDetected -and -not $vmdCheck.DriverLoaded) {
            $result.VMDRecommendation = "Intel VMD detected without driver. Options:`n" +
                                       "1. Load VMD driver in WinPE: drvload [path]\iaStorVD.inf`n" +
                                       "2. Disable VMD in BIOS -> Storage Configuration (may require reinstall if originally installed with VMD on)"
        } else {
            $result.VMDRecommendation = "VMD status OK or not applicable."
        }
        
        $result.Recommendations += $result.CSMRecommendation
        if ($vmdCheck.VMDDetected) {
            $result.Recommendations += $result.VMDRecommendation
        }
        
    } catch {
        $result.Recommendations += "Could not check BIOS/firmware status: $_"
    }
    
    return $result
}

function Start-AdvancedBootDiagnostics {
    <#
    .SYNOPSIS
    Runs comprehensive advanced boot diagnostics.
    
    .DESCRIPTION
    Performs all advanced diagnostic checks and provides a comprehensive report.
    
    .PARAMETER WindowsDrive
    Drive letter of the Windows installation
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$WindowsDrive
    )
    
    $report = [System.Text.StringBuilder]::new()
    $report.AppendLine("ADVANCED BOOT TROUBLESHOOTING REPORT") | Out-Null
    $report.AppendLine("=====================================") | Out-Null
    $report.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
    $report.AppendLine("Target Drive: $WindowsDrive`:") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 1. VMD Driver Check
    $report.AppendLine("1. INTEL VMD DRIVER CHECK") | Out-Null
    $report.AppendLine("----------------------------------------") | Out-Null
    $vmdCheck = Test-VMDDriverIssue
    $report.AppendLine("VMD Detected: $($vmdCheck.VMDDetected)") | Out-Null
    $report.AppendLine("Driver Loaded: $($vmdCheck.DriverLoaded)") | Out-Null
    $report.AppendLine("Recommendation: $($vmdCheck.Recommendation)") | Out-Null
    if ($vmdCheck.DriverPath) {
        $report.AppendLine("Driver Path: $($vmdCheck.DriverPath)") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # 2. Multiple Boot Drives
    $report.AppendLine("2. MULTIPLE BOOT DRIVES CHECK") | Out-Null
    $report.AppendLine("----------------------------------------") | Out-Null
    $multiDriveCheck = Test-MultipleBootDrives
    $report.AppendLine("Multiple Drives: $($multiDriveCheck.MultipleDrivesDetected)") | Out-Null
    if ($multiDriveCheck.BootDrives.Count -gt 0) {
        $report.AppendLine("Boot Drives: $($multiDriveCheck.BootDrives -join ', ')") | Out-Null
    }
    $report.AppendLine("Recommendation: $($multiDriveCheck.Recommendation)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 3. Pending Updates
    $report.AppendLine("3. PENDING UPDATES CHECK") | Out-Null
    $report.AppendLine("----------------------------------------") | Out-Null
    $pendingCheck = Test-PendingUpdates
    $report.AppendLine("Pending Updates Found: $($pendingCheck.PendingUpdatesFound)") | Out-Null
    if ($pendingCheck.PendingXMLPath) {
        $report.AppendLine("Pending XML: $($pendingCheck.PendingXMLPath)") | Out-Null
    }
    $report.AppendLine("Recommendation: $($pendingCheck.Recommendation)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 4. Read-Only Drive
    $report.AppendLine("4. READ-ONLY DRIVE CHECK") | Out-Null
    $report.AppendLine("----------------------------------------") | Out-Null
    $readOnlyCheck = Test-ReadOnlyDrive -WindowsDrive $WindowsDrive
    $report.AppendLine("Is Read-Only: $($readOnlyCheck.IsReadOnly)") | Out-Null
    $report.AppendLine("Recommendation: $($readOnlyCheck.Recommendation)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 5. MBR/GPT Corruption
    $report.AppendLine("5. MBR/GPT CORRUPTION CHECK") | Out-Null
    $report.AppendLine("----------------------------------------") | Out-Null
    $corruptionCheck = Test-MBRGPTCorruption -WindowsDrive $WindowsDrive
    $report.AppendLine("Corruption Detected: $($corruptionCheck.CorruptionDetected)") | Out-Null
    if ($corruptionCheck.CorruptionType) {
        $report.AppendLine("Corruption Type: $($corruptionCheck.CorruptionType)") | Out-Null
    }
    $report.AppendLine("Recommendation: $($corruptionCheck.Recommendation)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    # 6. BIOS/Firmware Recommendations
    $report.AppendLine("6. BIOS/FIRMWARE RECOMMENDATIONS") | Out-Null
    $report.AppendLine("----------------------------------------") | Out-Null
    $biosCheck = Get-BIOSFirmwareRecommendations
    $report.AppendLine("Secure Boot Status: $($biosCheck.SecureBootStatus)") | Out-Null
    foreach ($rec in $biosCheck.Recommendations) {
        $report.AppendLine("  - $rec") | Out-Null
    }
    $report.AppendLine("") | Out-Null
    
    # Summary
    $report.AppendLine("SUMMARY") | Out-Null
    $report.AppendLine("----------------------------------------") | Out-Null
    $criticalIssues = @()
    if ($vmdCheck.VMDDetected -and -not $vmdCheck.DriverLoaded) {
        $criticalIssues += "VMD driver not loaded"
    }
    if ($multiDriveCheck.MultipleDrivesDetected) {
        $criticalIssues += "Multiple boot drives detected"
    }
    if ($pendingCheck.PendingUpdatesFound) {
        $criticalIssues += "Pending updates blocking repair"
    }
    if ($readOnlyCheck.IsReadOnly) {
        $criticalIssues += "Drive marked as read-only"
    }
    if ($corruptionCheck.CorruptionDetected) {
        $criticalIssues += "$($corruptionCheck.CorruptionType) corruption detected"
    }
    
    if ($criticalIssues.Count -gt 0) {
        $report.AppendLine("CRITICAL ISSUES FOUND:") | Out-Null
        foreach ($issue in $criticalIssues) {
            $report.AppendLine("  - $issue") | Out-Null
        }
    } else {
        $report.AppendLine("No critical issues detected. Boot repair should proceed normally.") | Out-Null
    }
    
    return $report.ToString()
}

# Export functions
Export-ModuleMember -Function @(
    'Test-VMDDriverIssue',
    'Start-VMDDriverLoad',
    'Test-MultipleBootDrives',
    'Start-EFIPartitionRecreation',
    'Start-WinPESFCDISMRepair',
    'Test-PendingUpdates',
    'Test-ReadOnlyDrive',
    'Test-MBRGPTCorruption',
    'Get-BIOSFirmwareRecommendations',
    'Start-AdvancedBootDiagnostics'
)
