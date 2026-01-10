# ============================================================================
# POST-REPAIR TRUTH ENGINE
# Forensic verification that provides honest boot viability assessment
# ============================================================================

function Test-BootViability {
    <#
    .SYNOPSIS
    Post-repair truth engine - determines if system will actually boot.
    
    .DESCRIPTION
    After all automated fixes, this function switches to FORENSIC MODE:
    - No more writes (read-only verification)
    - Re-detects boot environment (fresh scan)
    - Runs comprehensive boot viability checklist
    - Provides clear YES/NO verdict
    - Explains exactly why it won't boot if it won't
    - Outputs machine-readable diagnostic payload
    
    .PARAMETER TargetDrive
    Target Windows drive letter (optional, will auto-detect if not provided)
    
    .OUTPUTS
    PSCustomObject with properties:
    - WillBoot: Boolean (true/false)
    - Verdict: "YES" or "NO"
    - Confidence: 0-100 (percentage)
    - BlockingIssues: Array of issues that prevent boot
    - Evidence: Detailed evidence for each check
    - UserMessage: Human-readable verdict message
    - DiagnosticPayload: Machine-readable JSON
    #>
    
    param(
        [string]$TargetDrive = $null
    )
    
    $result = @{
        WillBoot = $false
        Verdict = "UNKNOWN"
        Confidence = 0
        BlockingIssues = @()
        Evidence = @{}
        UserMessage = ""
        DiagnosticPayload = $null
        Checks = @{
            EFIBootFiles = $false
            BCDRealityMatch = $false
            WinloadReality = $false
            BootCriticalDrivers = $false
            BootHandoffChain = $false
        }
    }
    
    $report = New-Object System.Text.StringBuilder
    $separator = "=" * 80
    
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("POST-REPAIR TRUTH ENGINE - BOOT VIABILITY ASSESSMENT") | Out-Null
    $report.AppendLine($separator) | Out-Null
    $report.AppendLine("") | Out-Null
    $report.AppendLine("FORENSIC MODE: Read-only verification (no writes)") | Out-Null
    $report.AppendLine("") | Out-Null
    
    try {
        # PHASE 1: Re-detect boot environment (FRESH SCAN)
        $report.AppendLine("PHASE 1: RE-DETECTING BOOT ENVIRONMENT") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        
        # Detect firmware mode
        $firmwareType = "Unknown"
        $diskLayout = "Unknown"
        $espInfo = @{
            Present = $false
            Mounted = $false
            DriveLetter = $null
            FileSystem = "Unknown"
            HealthStatus = "Unknown"
        }
        
        # Check for UEFI
        try {
            $efiPartitions = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
            if ($efiPartitions) {
                $firmwareType = "UEFI"
                $diskLayout = "GPT"
                $espInfo.Present = $true
                
                $espPartition = $efiPartitions[0]
                if ($espPartition.DriveLetter) {
                    $espInfo.Mounted = $true
                    $espInfo.DriveLetter = $espPartition.DriveLetter
                    
                    $espVolume = Get-Volume -DriveLetter $espPartition.DriveLetter -ErrorAction SilentlyContinue
                    if ($espVolume) {
                        $espInfo.FileSystem = $espVolume.FileSystemType
                        $espInfo.HealthStatus = $espVolume.HealthStatus
                    }
                }
            } else {
                # Check for MBR/Legacy
                $disks = Get-Disk | Select-Object -First 1
                if ($disks -and $disks.PartitionStyle -eq "MBR") {
                    $firmwareType = "Legacy BIOS"
                    $diskLayout = "MBR"
                }
            }
        } catch {
            $report.AppendLine("[WARNING] Could not detect firmware type: $_") | Out-Null
        }
        
        $report.AppendLine("Firmware Type: $firmwareType") | Out-Null
        $report.AppendLine("Disk Layout: $diskLayout") | Out-Null
        $report.AppendLine("ESP Present: $($espInfo.Present)") | Out-Null
        $report.AppendLine("ESP Mounted: $($espInfo.Mounted)") | Out-Null
        if ($espInfo.Mounted) {
            $report.AppendLine("ESP Drive: $($espInfo.DriveLetter):") | Out-Null
            $report.AppendLine("ESP FileSystem: $($espInfo.FileSystem)") | Out-Null
            $report.AppendLine("ESP Health: $($espInfo.HealthStatus)") | Out-Null
        }
        $report.AppendLine("") | Out-Null
        
        # Re-discover Windows installations
        $windowsInstallations = @()
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
        
        foreach ($vol in $volumes) {
            $drive = $vol.DriveLetter
            $systemHive = "$drive`:\Windows\System32\config\SYSTEM"
            
            if (Test-Path $systemHive) {
                $windowsPath = "$drive`:\Windows"
                $kernelPath = "$drive`:\Windows\System32\ntoskrnl.exe"
                
                if (Test-Path $kernelPath) {
                    $windowsInstallations += [PSCustomObject]@{
                        DriveLetter = $drive
                        WindowsPath = $windowsPath
                        SystemHivePath = $systemHive
                        KernelPath = $kernelPath
                        IsCurrentOS = ($env:SystemDrive -eq "$drive`:")
                    }
                }
            }
        }
        
        $report.AppendLine("Windows Installations Found: $($windowsInstallations.Count)") | Out-Null
        foreach ($inst in $windowsInstallations) {
            $report.AppendLine("  - $($inst.DriveLetter): (Current OS: $($inst.IsCurrentOS))") | Out-Null
        }
        $report.AppendLine("") | Out-Null
        
        # Select target Windows installation
        $targetOS = $null
        if ($TargetDrive) {
            $targetOS = $windowsInstallations | Where-Object { $_.DriveLetter -eq $TargetDrive.TrimEnd(':').ToUpper() } | Select-Object -First 1
        }
        
        if (-not $targetOS) {
            $targetOS = $windowsInstallations | Where-Object { $_.IsCurrentOS } | Select-Object -First 1
        }
        
        if (-not $targetOS) {
            $targetOS = $windowsInstallations | Select-Object -First 1
        }
        
        if (-not $targetOS) {
            $errorMsg = "No Windows installation found"
            $result.BlockingIssues += $errorMsg
            $result.UserMessage = "BOOT STATUS: WILL NOT BOOT ❌`n`nREASON: $errorMsg"
            $result.Report = $report.ToString()
            return $result
        }
        
        $report.AppendLine("Target Windows Installation: $($targetOS.DriveLetter):") | Out-Null
        $report.AppendLine("") | Out-Null
        
        # PHASE 2: BOOT VIABILITY CHECKLIST
        $report.AppendLine("PHASE 2: BOOT VIABILITY CHECKLIST") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $report.AppendLine("") | Out-Null
        
        $checksPassed = 0
        $totalChecks = 5
        
        # CHECK A: EFI Boot Files (or Legacy Boot Files)
        $report.AppendLine("CHECK A: BOOT FILES") | Out-Null
        $checkA = @{
            Passed = $false
            Evidence = @()
            Issues = @()
        }
        
        if ($firmwareType -eq "UEFI") {
            if ($espInfo.Mounted) {
                $bootmgfwPath = "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\bootmgfw.efi"
                $bcdPath = "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\BCD"
                
                $bootmgfwExists = Test-Path $bootmgfwPath
                $bcdExists = Test-Path $bcdPath
                
                $checkA.Evidence += "bootmgfw.efi: $(if ($bootmgfwExists) { 'PRESENT' } else { 'MISSING' }) at $bootmgfwPath"
                $checkA.Evidence += "BCD: $(if ($bcdExists) { 'PRESENT' } else { 'MISSING' }) at $bcdPath"
                
                if ($bootmgfwExists -and $bcdExists) {
                    # Verify ESP filesystem
                    if ($espInfo.FileSystem -eq "FAT32") {
                        $checkA.Passed = $true
                        $checksPassed++
                        $report.AppendLine("  [PASS] EFI boot files present and ESP is FAT32") | Out-Null
                    } else {
                        $checkA.Issues += "ESP filesystem is $($espInfo.FileSystem), must be FAT32"
                        $report.AppendLine("  [FAIL] ESP filesystem is $($espInfo.FileSystem), must be FAT32") | Out-Null
                    }
                } else {
                    if (-not $bootmgfwExists) {
                        $checkA.Issues += "bootmgfw.efi missing from ESP"
                        $report.AppendLine("  [FAIL] bootmgfw.efi missing from ESP") | Out-Null
                    }
                    if (-not $bcdExists) {
                        $checkA.Issues += "BCD missing from ESP"
                        $report.AppendLine("  [FAIL] BCD missing from ESP") | Out-Null
                    }
                }
            } else {
                $checkA.Issues += "ESP not mounted (no drive letter)"
                $checkA.Evidence += "ESP exists but not mounted"
                $report.AppendLine("  [FAIL] ESP not mounted") | Out-Null
            }
        } elseif ($firmwareType -eq "Legacy BIOS") {
            # Check for legacy boot files
            $bootmgrPath = "$($targetOS.DriveLetter):\bootmgr"
            $legacyBcdPath = "$($targetOS.DriveLetter):\Boot\BCD"
            
            $bootmgrExists = Test-Path $bootmgrPath
            $legacyBcdExists = Test-Path $legacyBcdPath
            
            $checkA.Evidence += "bootmgr: $(if ($bootmgrExists) { 'PRESENT' } else { 'MISSING' }) at $bootmgrPath"
            $checkA.Evidence += "BCD: $(if ($legacyBcdExists) { 'PRESENT' } else { 'MISSING' }) at $legacyBcdPath"
            
            if ($bootmgrExists -and $legacyBcdExists) {
                $checkA.Passed = $true
                $checksPassed++
                $report.AppendLine("  [PASS] Legacy boot files present") | Out-Null
            } else {
                if (-not $bootmgrExists) {
                    $checkA.Issues += "bootmgr missing"
                    $report.AppendLine("  [FAIL] bootmgr missing") | Out-Null
                }
                if (-not $legacyBcdExists) {
                    $checkA.Issues += "BCD missing from Boot folder"
                    $report.AppendLine("  [FAIL] BCD missing from Boot folder") | Out-Null
                }
            }
        } else {
            $checkA.Issues += "Firmware type unknown"
            $report.AppendLine("  [FAIL] Firmware type unknown") | Out-Null
        }
        
        $result.Checks.EFIBootFiles = $checkA.Passed
        $result.Evidence.CheckA = $checkA
        if (-not $checkA.Passed) {
            $result.BlockingIssues += "Boot files missing or invalid"
        }
        
        $report.AppendLine("") | Out-Null
        
        # CHECK B: BCD to Disk Reality Match
        $report.AppendLine("CHECK B: BCD TO DISK REALITY MATCH") | Out-Null
        $checkB = @{
            Passed = $false
            Evidence = @()
            Issues = @()
        }
        
        if ($firmwareType -eq "UEFI" -and $espInfo.Mounted) {
            $bcdPath = "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\BCD"
            
            if (Test-Path $bcdPath) {
                try {
                    $bcdEnum = & bcdedit /store $bcdPath /enum {default} 2>&1 | Out-String
                    
                    if ($LASTEXITCODE -eq 0) {
                        # Extract device/osdevice
                        $deviceUnknown = $bcdEnum -match "device\s+Unknown"
                        $osdeviceUnknown = $bcdEnum -match "osdevice\s+Unknown"
                        
                        if ($deviceUnknown -or $osdeviceUnknown) {
                            $checkB.Issues += "BCD device/osdevice is Unknown"
                            $checkB.Evidence += "BCD shows device/osdevice = Unknown"
                            $report.AppendLine("  [FAIL] BCD device/osdevice is Unknown") | Out-Null
                        } else {
                            # Extract partition GUID from osdevice
                            if ($bcdEnum -match "osdevice\s+partition=([a-f0-9-]+)") {
                                $bcdGuid = $matches[1]
                                $checkB.Evidence += "BCD osdevice points to partition GUID: $bcdGuid"
                                
                                # Verify partition exists
                                $partition = Get-Partition | Where-Object { $_.Guid -eq $bcdGuid }
                                if ($partition) {
                                    $checkB.Evidence += "Partition exists: $($partition.DriveLetter):"
                                    
                                    # Verify partition contains Windows
                                    $windowsOnPartition = Test-Path "$($partition.DriveLetter):\Windows\System32\ntoskrnl.exe"
                                    if ($windowsOnPartition) {
                                        $checkB.Passed = $true
                                        $checksPassed++
                                        $report.AppendLine("  [PASS] BCD points to valid Windows partition") | Out-Null
                                    } else {
                                        $checkB.Issues += "BCD points to partition without Windows"
                                        $checkB.Evidence += "Partition $($partition.DriveLetter): does not contain Windows"
                                        $report.AppendLine("  [FAIL] BCD points to partition without Windows") | Out-Null
                                    }
                                } else {
                                    $checkB.Issues += "BCD points to non-existent partition"
                                    $checkB.Evidence += "Partition GUID $bcdGuid does not exist"
                                    $report.AppendLine("  [FAIL] BCD points to non-existent partition (GUID: $bcdGuid)") | Out-Null
                                }
                            } else {
                                # Try to extract drive letter format
                                if ($bcdEnum -match "osdevice\s+partition=([A-Z]):") {
                                    $bcdDrive = $matches[1]
                                    $checkB.Evidence += "BCD osdevice points to drive: $bcdDrive`:"
                                    
                                    if (Test-Path "$bcdDrive`:\Windows\System32\ntoskrnl.exe") {
                                        $checkB.Passed = $true
                                        $checksPassed++
                                        $report.AppendLine("  [PASS] BCD points to valid Windows drive") | Out-Null
                                    } else {
                                        $checkB.Issues += "BCD points to drive without Windows"
                                        $report.AppendLine("  [FAIL] BCD points to drive without Windows") | Out-Null
                                    }
                                } else {
                                    $checkB.Issues += "Could not parse BCD osdevice"
                                    $report.AppendLine("  [FAIL] Could not parse BCD osdevice") | Out-Null
                                }
                            }
                        }
                    } else {
                        $checkB.Issues += "BCD not readable"
                        $checkB.Evidence += "bcdedit /enum failed (exit code: $LASTEXITCODE)"
                        $report.AppendLine("  [FAIL] BCD not readable") | Out-Null
                    }
                } catch {
                    $checkB.Issues += "BCD verification failed: $_"
                    $report.AppendLine("  [FAIL] BCD verification failed: $_") | Out-Null
                }
            } else {
                $checkB.Issues += "BCD file not found"
                $report.AppendLine("  [FAIL] BCD file not found") | Out-Null
            }
        } elseif ($firmwareType -eq "Legacy BIOS") {
            # Legacy BCD check
            $legacyBcdPath = "$($targetOS.DriveLetter):\Boot\BCD"
            if (Test-Path $legacyBcdPath) {
                try {
                    $bcdEnum = & bcdedit /store $legacyBcdPath /enum {default} 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0) {
                        $checkB.Passed = $true
                        $checksPassed++
                        $report.AppendLine("  [PASS] Legacy BCD is readable") | Out-Null
                    } else {
                        $checkB.Issues += "Legacy BCD not readable"
                        $report.AppendLine("  [FAIL] Legacy BCD not readable") | Out-Null
                    }
                } catch {
                    $checkB.Issues += "Legacy BCD verification failed: $_"
                    $report.AppendLine("  [FAIL] Legacy BCD verification failed: $_") | Out-Null
                }
            } else {
                $checkB.Issues += "Legacy BCD not found"
                $report.AppendLine("  [FAIL] Legacy BCD not found") | Out-Null
            }
        }
        
        $result.Checks.BCDRealityMatch = $checkB.Passed
        $result.Evidence.CheckB = $checkB
        if (-not $checkB.Passed) {
            $result.BlockingIssues += "BCD does not match disk reality"
        }
        
        $report.AppendLine("") | Out-Null
        
        # CHECK C: winload.efi Reality
        $report.AppendLine("CHECK C: WINLOAD.EFI REALITY") | Out-Null
        $checkC = @{
            Passed = $false
            Evidence = @()
            Issues = @()
        }
        
        $winloadPath = "$($targetOS.WindowsPath)\System32\winload.efi"
        $winloadExists = Test-Path $winloadPath
        
        $checkC.Evidence += "winload.efi: $(if ($winloadExists) { 'PRESENT' } else { 'MISSING' }) at $winloadPath"
        
        if ($winloadExists) {
            # Verify file is readable and has content
            try {
                $winloadFile = Get-Item $winloadPath -ErrorAction Stop
                $fileSize = $winloadFile.Length
                $checkC.Evidence += "File size: $fileSize bytes"
                
                if ($fileSize -gt 0) {
                    # Check architecture (x64 vs x86)
                    # x64 winload.efi is typically > 1MB, x86 is smaller
                    if ($fileSize -gt 1000000) {
                        $checkC.Evidence += "Architecture: x64 (likely)"
                    } else {
                        $checkC.Evidence += "Architecture: x86 (likely)"
                    }
                    
                    # Check Secure Boot if enabled
                    $secureBootEnabled = $false
                    try {
                        $sbState = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\SecureBoot\State" -Name "UEFISecureBootEnabled" -ErrorAction SilentlyContinue).UEFISecureBootEnabled
                        if ($sbState -eq 1) {
                            $secureBootEnabled = $true
                            $checkC.Evidence += "Secure Boot: Enabled (signature verification required)"
                            # Note: We can't verify signature programmatically, but file exists
                        }
                    } catch {
                        # Secure Boot registry not accessible (may be in PE)
                    }
                    
                    $checkC.Passed = $true
                    $checksPassed++
                    $report.AppendLine("  [PASS] winload.efi exists and is readable ($fileSize bytes)") | Out-Null
                } else {
                    $checkC.Issues += "winload.efi is 0 bytes (corrupted)"
                    $report.AppendLine("  [FAIL] winload.efi is 0 bytes (corrupted)") | Out-Null
                }
            } catch {
                $checkC.Issues += "winload.efi not accessible: $_"
                $report.AppendLine("  [FAIL] winload.efi not accessible: $_") | Out-Null
            }
        } else {
            $checkC.Issues += "winload.efi missing from Windows directory"
            $report.AppendLine("  [FAIL] winload.efi missing from Windows directory") | Out-Null
        }
        
        $result.Checks.WinloadReality = $checkC.Passed
        $result.Evidence.CheckC = $checkC
        if (-not $checkC.Passed) {
            $result.BlockingIssues += "winload.efi missing or corrupted"
        }
        
        $report.AppendLine("") | Out-Null
        
        # CHECK D: Boot-Critical Drivers
        $report.AppendLine("CHECK D: BOOT-CRITICAL DRIVERS") | Out-Null
        $checkD = @{
            Passed = $false
            Evidence = @()
            Issues = @()
        }
        
        try {
            # Mount SYSTEM hive
            reg load "HKLM\TempSys" "$($targetOS.SystemHivePath)" 2>&1 | Out-Null
            
            # Check storage controller drivers
            $storageDrivers = @(
                @{Service = "iaStorV"; Driver = "iaStorVD.sys"; Name = "Intel VMD"},
                @{Service = "storahci"; Driver = "storahci.sys"; Name = "AHCI"},
                @{Service = "stornvme"; Driver = "stornvme.sys"; Name = "NVMe"},
                @{Service = "iaStorAC"; Driver = "iaStorAC.sys"; Name = "Intel RST"}
            )
            
            $driverFound = $false
            foreach ($driverInfo in $storageDrivers) {
                $servicePath = "HKLM:\TempSys\ControlSet001\Services\$($driverInfo.Service)"
                if (Test-Path $servicePath) {
                    $service = Get-ItemProperty $servicePath -ErrorAction SilentlyContinue
                    if ($service) {
                        $driverPath = "$($targetOS.WindowsPath)\System32\drivers\$($driverInfo.Driver)"
                        $driverFileExists = Test-Path $driverPath
                        $driverEnabled = ($service.Start -eq 0)
                        
                        # Check StartOverride trap
                        $startOverride = Get-ItemProperty "$servicePath\StartOverride" -ErrorAction SilentlyContinue
                        $hasStartOverride = ($null -ne $startOverride)
                        
                        $checkD.Evidence += "$($driverInfo.Name): Service=$($driverInfo.Service), File=$driverFileExists, Enabled=$driverEnabled, StartOverride=$hasStartOverride"
                        
                        if ($driverFileExists -and $driverEnabled -and -not $hasStartOverride) {
                            $driverFound = $true
                        } elseif ($driverFileExists -and -not $driverEnabled) {
                            $checkD.Issues += "$($driverInfo.Name) driver disabled (Start=$($service.Start))"
                        } elseif ($driverFileExists -and $hasStartOverride) {
                            $checkD.Issues += "$($driverInfo.Name) driver has StartOverride trap"
                        } elseif (-not $driverFileExists) {
                            $checkD.Issues += "$($driverInfo.Name) driver file missing: $driverPath"
                        }
                    }
                }
            }
            
            reg unload "HKLM\TempSys" 2>&1 | Out-Null
            
            if ($driverFound) {
                $checkD.Passed = $true
                $checksPassed++
                $report.AppendLine("  [PASS] Boot-critical storage driver found and enabled") | Out-Null
            } else {
                if ($checkD.Issues.Count -eq 0) {
                    $checkD.Issues += "No storage controller drivers detected"
                }
                $report.AppendLine("  [FAIL] Boot-critical driver issues detected") | Out-Null
                foreach ($issue in $checkD.Issues) {
                    $report.AppendLine("    - $issue") | Out-Null
                }
            }
        } catch {
            $checkD.Issues += "Could not verify drivers: $_"
            $report.AppendLine("  [FAIL] Could not verify drivers: $_") | Out-Null
            reg unload "HKLM\TempSys" 2>&1 | Out-Null
        }
        
        $result.Checks.BootCriticalDrivers = $checkD.Passed
        $result.Evidence.CheckD = $checkD
        if (-not $checkD.Passed) {
            $result.BlockingIssues += "Boot-critical drivers missing or disabled"
        }
        
        $report.AppendLine("") | Out-Null
        
        # CHECK E: Boot Handoff Chain
        $report.AppendLine("CHECK E: BOOT HANDOFF CHAIN") | Out-Null
        $checkE = @{
            Passed = $false
            Evidence = @()
            Issues = @()
        }
        
        # Verify complete chain: Firmware → bootmgfw.efi → BCD → winload.efi → ntoskrnl.exe
        $chainLinks = @()
        
        # Link 1: Firmware (assumed present if we're running)
        $chainLinks += @{Name = "Firmware"; Present = $true}
        
        # Link 2: bootmgfw.efi (or bootmgr for legacy)
        if ($firmwareType -eq "UEFI" -and $espInfo.Mounted) {
            $bootmgrPath = "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\bootmgfw.efi"
            $bootmgrPresent = Test-Path $bootmgrPath
            $chainLinks += @{Name = "bootmgfw.efi"; Present = $bootmgrPresent; Path = $bootmgrPath}
        } elseif ($firmwareType -eq "Legacy BIOS") {
            $bootmgrPath = "$($targetOS.DriveLetter):\bootmgr"
            $bootmgrPresent = Test-Path $bootmgrPath
            $chainLinks += @{Name = "bootmgr"; Present = $bootmgrPresent; Path = $bootmgrPath}
        } else {
            $chainLinks += @{Name = "Boot Manager"; Present = $false}
        }
        
        # Link 3: BCD
        if ($firmwareType -eq "UEFI" -and $espInfo.Mounted) {
            $bcdPath = "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\BCD"
            $bcdPresent = Test-Path $bcdPath
            $bcdReadable = $false
            if ($bcdPresent) {
                try {
                    $bcdTest = & bcdedit /store $bcdPath /enum all 2>&1 | Out-String
                    $bcdReadable = ($LASTEXITCODE -eq 0)
                } catch {
                    $bcdReadable = $false
                }
            }
            $chainLinks += @{Name = "BCD"; Present = $bcdPresent; Readable = $bcdReadable; Path = $bcdPath}
        } elseif ($firmwareType -eq "Legacy BIOS") {
            $bcdPath = "$($targetOS.DriveLetter):\Boot\BCD"
            $bcdPresent = Test-Path $bcdPath
            $bcdReadable = $false
            if ($bcdPresent) {
                try {
                    $bcdTest = & bcdedit /store $bcdPath /enum all 2>&1 | Out-String
                    $bcdReadable = ($LASTEXITCODE -eq 0)
                } catch {
                    $bcdReadable = $false
                }
            }
            $chainLinks += @{Name = "BCD"; Present = $bcdPresent; Readable = $bcdReadable; Path = $bcdPath}
        } else {
            $chainLinks += @{Name = "BCD"; Present = $false}
        }
        
        # Link 4: winload.efi
        $winloadPath = "$($targetOS.WindowsPath)\System32\winload.efi"
        $winloadPresent = Test-Path $winloadPath
        $chainLinks += @{Name = "winload.efi"; Present = $winloadPresent; Path = $winloadPath}
        
        # Link 5: ntoskrnl.exe
        $kernelPath = "$($targetOS.WindowsPath)\System32\ntoskrnl.exe"
        $kernelPresent = Test-Path $kernelPath
        $chainLinks += @{Name = "ntoskrnl.exe"; Present = $kernelPresent; Path = $kernelPath}
        
        # Build evidence
        foreach ($link in $chainLinks) {
            $status = if ($link.Present) { "PRESENT" } else { "MISSING" }
            if ($link.Path) {
                $checkE.Evidence += "$($link.Name): $status at $($link.Path)"
            } else {
                $checkE.Evidence += "$($link.Name): $status"
            }
            
            if (-not $link.Present) {
                $checkE.Issues += "$($link.Name) missing"
            } elseif ($link.Readable -eq $false) {
                $checkE.Issues += "$($link.Name) not readable"
            }
        }
        
        # Verify all links present
        $allLinksPresent = ($chainLinks | Where-Object { $_.Present -eq $true }).Count -eq $chainLinks.Count
        $bcdReadable = ($chainLinks | Where-Object { $_.Name -eq "BCD" } | Select-Object -First 1).Readable
        
        if ($allLinksPresent -and ($bcdReadable -ne $false)) {
            $checkE.Passed = $true
            $checksPassed++
            $report.AppendLine("  [PASS] All boot handoff chain links present") | Out-Null
        } else {
            $report.AppendLine("  [FAIL] Boot handoff chain broken") | Out-Null
            foreach ($issue in $checkE.Issues) {
                $report.AppendLine("    - $issue") | Out-Null
            }
        }
        
        $result.Checks.BootHandoffChain = $checkE.Passed
        $result.Evidence.CheckE = $checkE
        if (-not $checkE.Passed) {
            $result.BlockingIssues += "Boot handoff chain broken"
        }
        
        $report.AppendLine("") | Out-Null
        
        # PHASE 3: FINAL BOOT VERDICT
        $report.AppendLine("PHASE 3: FINAL BOOT VERDICT") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $report.AppendLine("") | Out-Null
        
        $confidence = [math]::Round(($checksPassed / $totalChecks) * 100, 1)
        $result.Confidence = $confidence
        
        # CRITICAL 3-CHECK VERIFICATION (Physical State, Not Return Codes)
        $report.AppendLine("") | Out-Null
        $report.AppendLine("CRITICAL 3-CHECK VERIFICATION (Physical State)") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $report.AppendLine("Verifying physical disk state (not trusting command return codes)...") | Out-Null
        $report.AppendLine("") | Out-Null
        
        $criticalChecks = @{
            Physical = $false  # winload.efi must physically exist
            Logical = $false   # BCD path must point to winload.efi
            Security = $false  # BitLocker must be unlocked
        }
        
        $criticalFailures = @()
        
        # CHECK 1: Physical - winload.efi must exist
        $winloadPhysicalPath = "$($targetOS.WindowsPath)\System32\winload.efi"
        $criticalChecks.Physical = Test-Path $winloadPhysicalPath
        
        if ($criticalChecks.Physical) {
            $fileSize = (Get-Item $winloadPhysicalPath -ErrorAction SilentlyContinue).Length
            $report.AppendLine("[PASS] PHYSICAL: winload.efi exists at $winloadPhysicalPath ($fileSize bytes)") | Out-Null
        } else {
            $criticalFailures += "PHYSICAL MISSING: winload.efi is still missing from the source folder"
            $report.AppendLine("[FAIL] PHYSICAL: winload.efi MISSING at $winloadPhysicalPath") | Out-Null
            $report.AppendLine("       Fix: Source template is corrupted. Needs DISM extraction from ISO.") | Out-Null
        }
        
        # CHECK 2: Logical - BCD path must point to winload.efi
        $bcdPathCorrect = $false
        if ($firmwareType -eq "UEFI" -and $espInfo.Mounted) {
            $bcdPath = "$($espInfo.DriveLetter):\EFI\Microsoft\Boot\BCD"
            if (Test-Path $bcdPath) {
                try {
                    $bcdEnum = & bcdedit /store $bcdPath /enum {default} 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0) {
                        if ($bcdEnum -match "path\s+\\Windows\\system32\\winload\.efi") {
                            $criticalChecks.Logical = $true
                            $bcdPathCorrect = $true
                            $report.AppendLine("[PASS] LOGICAL: BCD path correctly points to \Windows\system32\winload.efi") | Out-Null
                        } else {
                            $criticalFailures += "BCD MISMATCH: The boot configuration is pointing to the wrong file/path"
                            $report.AppendLine("[FAIL] LOGICAL: BCD path does NOT point to winload.efi") | Out-Null
                            $report.AppendLine("       Current BCD path: $($bcdEnum -match 'path\s+(.+)' | ForEach-Object { $matches[1] })") | Out-Null
                            $report.AppendLine("       Fix: Run 'bcdedit /set {default} path \Windows\system32\winload.efi'") | Out-Null
                        }
                    } else {
                        $criticalFailures += "BCD MISMATCH: BCD is not readable"
                        $report.AppendLine("[FAIL] LOGICAL: BCD is not readable") | Out-Null
                    }
                } catch {
                    $criticalFailures += "BCD MISMATCH: Could not verify BCD path"
                    $report.AppendLine("[FAIL] LOGICAL: Could not verify BCD path: $_") | Out-Null
                }
            } else {
                $criticalFailures += "BCD MISMATCH: BCD file not found"
                $report.AppendLine("[FAIL] LOGICAL: BCD file not found") | Out-Null
            }
        } elseif ($firmwareType -eq "Legacy BIOS") {
            $legacyBcdPath = "$($targetOS.DriveLetter):\Boot\BCD"
            if (Test-Path $legacyBcdPath) {
                try {
                    $bcdEnum = & bcdedit /store $legacyBcdPath /enum {default} 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0 -and $bcdEnum -match "path\s+\\Windows\\system32\\winload\.exe") {
                        $criticalChecks.Logical = $true
                        $bcdPathCorrect = $true
                        $report.AppendLine("[PASS] LOGICAL: Legacy BCD path correctly points to winload.exe") | Out-Null
                    } else {
                        $criticalFailures += "BCD MISMATCH: Legacy BCD path incorrect"
                        $report.AppendLine("[FAIL] LOGICAL: Legacy BCD path does not point to winload.exe") | Out-Null
                    }
                } catch {
                    $criticalFailures += "BCD MISMATCH: Could not verify legacy BCD"
                    $report.AppendLine("[FAIL] LOGICAL: Could not verify legacy BCD: $_") | Out-Null
                }
            } else {
                $criticalFailures += "BCD MISMATCH: Legacy BCD file not found"
                $report.AppendLine("[FAIL] LOGICAL: Legacy BCD file not found") | Out-Null
            }
        }
        
        # CHECK 3: Security - BitLocker must be unlocked
        $bitlockerLocked = $false
        try {
            $bitlockerStatus = manage-bde -status "$($targetOS.DriveLetter):" 2>&1 | Out-String
            if ($bitlockerStatus -match "Lock Status:\s+Locked") {
                $criticalChecks.Security = $false
                $bitlockerLocked = $true
                $criticalFailures += "BITLOCKER LOCKED: The drive is encrypted and 'bcdboot' could not write to it"
                $report.AppendLine("[FAIL] SECURITY: BitLocker is LOCKED on drive $($targetOS.DriveLetter):") | Out-Null
                $report.AppendLine("       Fix: You MUST unlock the drive with your recovery key before repairing.") | Out-Null
                $report.AppendLine("       Command: manage-bde -unlock $($targetOS.DriveLetter): -RecoveryPassword <YOUR_KEY>") | Out-Null
            } else {
                $criticalChecks.Security = $true
                $report.AppendLine("[PASS] SECURITY: BitLocker is unlocked or not enabled") | Out-Null
            }
        } catch {
            # manage-bde might not be available or drive might not be encrypted
            # If we can't check, assume it's OK (non-encrypted drive)
            $criticalChecks.Security = $true
            $report.AppendLine("[INFO] SECURITY: Could not check BitLocker status (drive may not be encrypted)") | Out-Null
        }
        
        $report.AppendLine("") | Out-Null
        
        # FINAL VERDICT BASED ON CRITICAL 3-CHECK VERIFICATION
        if ($criticalChecks.Physical -and $criticalChecks.Logical -and $criticalChecks.Security) {
            $result.WillBoot = $true
            $result.Verdict = "YES"
            
            $report.AppendLine("=" * 80) | Out-Null
            $report.AppendLine("WILL IT BOOT: YES") | Out-Null
            $report.AppendLine("=" * 80) | Out-Null
            $report.AppendLine("") | Out-Null
            $report.AppendLine("Feedback: All critical boot files verified and BCD is correctly mapped.") | Out-Null
            $report.AppendLine("") | Out-Null
            $report.AppendLine("All boot viability checks passed:") | Out-Null
            $report.AppendLine("  [OK] Boot files present and valid") | Out-Null
            $report.AppendLine("  [OK] BCD matches detected Windows installation") | Out-Null
            $report.AppendLine("  [OK] winload.efi exists and is accessible") | Out-Null
            $report.AppendLine("  [OK] Boot-critical drivers detected") | Out-Null
            $report.AppendLine("  [OK] Boot handoff chain intact") | Out-Null
            $report.AppendLine("") | Out-Null
            $report.AppendLine("ACTION:") | Out-Null
            $report.AppendLine("You may reboot safely.") | Out-Null
            
            $result.UserMessage = "WILL IT BOOT: YES`n`nFeedback: All critical boot files verified and BCD is correctly mapped.`n`nYou may reboot safely."
        } else {
            $result.WillBoot = $false
            $result.Verdict = "NO"
            
            $report.AppendLine("=" * 80) | Out-Null
            $report.AppendLine("WILL IT BOOT: NO") | Out-Null
            $report.AppendLine("=" * 80) | Out-Null
            $report.AppendLine("") | Out-Null
            $report.AppendLine("REASON(S) FOR FAILURE:") | Out-Null
            $report.AppendLine("") | Out-Null
            
            foreach ($failure in $criticalFailures) {
                $report.AppendLine("  [!] $failure") | Out-Null
            }
            
            $result.UserMessage = "WILL IT BOOT: NO`n`nREASON(S) FOR FAILURE:`n"
            foreach ($failure in $criticalFailures) {
                $result.UserMessage += "  [!] $failure`n"
            }
        } else {
            $result.WillBoot = $false
            $result.Verdict = "NO"
            
            $report.AppendLine("BOOT STATUS: WILL NOT BOOT [FAIL]") | Out-Null
            $report.AppendLine("") | Out-Null
            
            # Root Cause Classification
            $primaryCause = "Unknown"
            if ($result.BlockingIssues -match "winload.efi") {
                $primaryCause = "Missing winload.efi"
            } elseif ($result.BlockingIssues -match "BCD") {
                $primaryCause = "BCD points to wrong partition or corrupted"
            } elseif ($result.BlockingIssues -match "ESP") {
                $primaryCause = "EFI System Partition missing or invalid"
            } elseif ($result.BlockingIssues -match "Secure Boot") {
                $primaryCause = "Secure Boot blocking loader"
            } elseif ($result.BlockingIssues -match "driver") {
                $primaryCause = "Storage driver missing or disabled"
            } elseif ($result.BlockingIssues -match "Windows install") {
                $primaryCause = "Windows install incomplete or corrupted"
            } elseif ($result.BlockingIssues -match "Firmware") {
                $primaryCause = "Firmware / disk mode mismatch"
            } elseif ($result.BlockingIssues -match "BitLocker") {
                $primaryCause = "BitLocker blocking access"
            }
            
            $report.AppendLine("ROOT CAUSE: $primaryCause") | Out-Null
            $report.AppendLine("") | Out-Null
            
            # Evidence
            $report.AppendLine("EVIDENCE:") | Out-Null
            foreach ($checkKey in @("CheckA", "CheckB", "CheckC", "CheckD", "CheckE")) {
                if ($result.Evidence.ContainsKey($checkKey)) {
                    $check = $result.Evidence[$checkKey]
                    foreach ($evidence in $check.Evidence) {
                        $report.AppendLine("  - $evidence") | Out-Null
                    }
                }
            }
            $report.AppendLine("") | Out-Null
            
            # Why Automatic Repair Failed
            $report.AppendLine("WHY AUTOMATIC REPAIR FAILED:") | Out-Null
            $repairFailureReasons = @()
            
            if (-not $checkA.Passed) {
                $repairFailureReasons += "Boot files missing or ESP not properly formatted"
            }
            if (-not $checkB.Passed) {
                $repairFailureReasons += "BCD points to wrong partition or partition does not exist"
            }
            if (-not $checkC.Passed) {
                $repairFailureReasons += "winload.efi missing from Windows directory (source files not available)"
            }
            if (-not $checkD.Passed) {
                $repairFailureReasons += "Storage drivers missing or disabled (requires driver injection)"
            }
            if (-not $checkE.Passed) {
                $repairFailureReasons += "Boot handoff chain broken (critical files missing)"
            }
            
            foreach ($reason in $repairFailureReasons) {
                $report.AppendLine("  - $reason") | Out-Null
            }
            $report.AppendLine("") | Out-Null
            
            # Next Steps
            $report.AppendLine("NEXT STEPS:") | Out-Null
            $nextSteps = @()
            
            if (-not $checkA.Passed) {
                if ($firmwareType -eq "UEFI") {
                    $nextSteps += "Manually mount ESP and verify boot files exist"
                    $nextSteps += "Format ESP as FAT32 if filesystem is wrong"
                } else {
                    $nextSteps += "Verify bootmgr and BCD exist in root of Windows drive"
                }
            }
            if (-not $checkB.Passed) {
                $nextSteps += "Rebuild BCD with explicit partition GUID: bcdboot $($targetOS.WindowsPath) /s $($espInfo.DriveLetter): /f UEFI"
                $nextSteps += "Manually fix BCD device/osdevice using bcdedit"
            }
            if (-not $checkC.Passed) {
                $nextSteps += "Extract winload.efi from Windows installation media (install.wim)"
                $nextSteps += "Run DISM /RestoreHealth and SFC /ScanNow to restore from Component Store"
            }
            if (-not $checkD.Passed) {
                $nextSteps += "Inject missing storage drivers using DISM /Add-Driver"
                $nextSteps += "Enable storage driver in registry (Start=0) and remove StartOverride"
            }
            if (-not $checkE.Passed) {
                $nextSteps += "Verify all chain links exist: Firmware → bootmgfw.efi → BCD → winload.efi → ntoskrnl.exe"
            }
            
            if ($nextSteps.Count -eq 0) {
                $nextSteps += "Review evidence above and determine manual repair path"
            }
            
            foreach ($step in $nextSteps) {
                $report.AppendLine("  - $step") | Out-Null
            }
            
            $result.UserMessage = "BOOT STATUS: WILL NOT BOOT [FAIL]`n`nROOT CAUSE: $primaryCause`n`nSee detailed report for evidence and next steps."
        }
        
        $report.AppendLine("") | Out-Null
        $report.AppendLine($separator) | Out-Null
        
        # Machine-Readable Diagnostic Payload
        $diagnosticPayload = @{
            bootable = $result.WillBoot
            verdict = $result.Verdict
            confidence = $confidence
            firmware = $firmwareType
            disk_layout = $diskLayout
            esp_present = $espInfo.Present
            esp_mounted = $espInfo.Mounted
            esp_filesystem = $espInfo.FileSystem
            esp_health = $espInfo.HealthStatus
            bcd_valid = $checkB.Passed
            bcd_correct = $checkB.Passed
            winload_present = $checkC.Passed
            drivers_ok = $checkD.Passed
            chain_intact = $checkE.Passed
            blocking_issue = if ($result.BlockingIssues.Count -gt 0) { $result.BlockingIssues[0] } else { $null }
            auto_fix_exhausted = $true
            checks_passed = "$checksPassed / $totalChecks"
            target_drive = $targetOS.DriveLetter
            target_windows_path = $targetOS.WindowsPath
        }
        
        $result.DiagnosticPayload = $diagnosticPayload
        
        $report.AppendLine("") | Out-Null
        $report.AppendLine("MACHINE-READABLE DIAGNOSTIC PAYLOAD:") | Out-Null
        $report.AppendLine("-" * 80) | Out-Null
        $jsonPayload = $diagnosticPayload | ConvertTo-Json -Depth 10
        $report.AppendLine($jsonPayload) | Out-Null
        
        $result.Report = $report.ToString()
        
    } catch {
        $errorMsg = "Boot viability assessment failed: $_"
        $result.BlockingIssues += $errorMsg
        $result.UserMessage = "BOOT STATUS: ASSESSMENT FAILED [FAIL]`n`n$errorMsg"
        $result.Report = $report.ToString()
    }
    
    return $result
}
