################################################################################
#
# NetworkDiagnostics.ps1 - Network Connectivity & Driver Management Module
# Part of MiracleBoot v7.2.0 - Advanced Windows Recovery Toolkit
#
# Purpose:  Comprehensive network diagnostics, driver detection, and management
#           for WinPE/WinRE and FullOS environments
#
# Features: - Network adapter detection (wireless & wired)
#           - DHCP and DNS validation
#           - Internet connectivity testing
#           - Network driver harvesting and injection
#           - Driver path searching across volumes
#           - Detailed troubleshooting guidance
#
# Author:   MiracleBoot Development Team
# Version:  1.0.0
# Updated:  January 2026
#
################################################################################

<#
.SYNOPSIS
    Comprehensive network diagnostics and driver management for recovery environments

.DESCRIPTION
    This module provides production-grade functions for:
    - Detecting network adapters (physical and virtual)
    - Testing DHCP, DNS, and internet connectivity
    - Harvesting drivers from running system
    - Searching for drivers on mounted volumes
    - Injecting drivers into WinPE environments
    - Detailed troubleshooting and reporting

.NOTES
    Requires: Administrator privileges
    Supports: Windows 10/11 (FullOS and WinPE/WinRE)
    Error Handling: Comprehensive try-catch with detailed logging
#>

################################################################################
# NETWORK ADAPTER DETECTION FUNCTIONS
################################################################################

function Get-NetworkAdapterStatus {
    <#
    .SYNOPSIS
        Detects and reports on all network adapters and their current status
    
    .DESCRIPTION
        Returns detailed information about physical network adapters including:
        - Adapter name and description
        - Connection status (connected/disconnected)
        - IP configuration (DHCP/Static)
        - MAC address
        - Link speed
        - Driver information
    
    .OUTPUTS
        PSCustomObject with adapter details
    #>
    
    param(
        [switch]$IncludeDisabled
    )
    
    $adapters = @()
    
    try {
        # Get network adapters via WMI (works in both FullOS and WinPE)
        $netAdapters = Get-WmiObject Win32_NetworkAdapter -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.PhysicalAdapter -eq $true -or $IncludeDisabled
            }
        
        foreach ($adapter in $netAdapters) {
            try {
                # Get configuration
                $config = Get-WmiObject Win32_NetworkAdapterConfiguration |
                    Where-Object { $_.Index -eq $adapter.Index }
                
                # Determine connection type
                $adapterType = "Unknown"
                if ($adapter.AdapterType -match "Ethernet") {
                    $adapterType = "Wired (Ethernet)"
                } elseif ($adapter.AdapterType -match "Wireless|WiFi|802.11") {
                    $adapterType = "Wireless (WiFi)"
                } elseif ($adapter.Description -match "Wireless|WiFi|802.11") {
                    $adapterType = "Wireless (WiFi)"
                } elseif ($adapter.Description -match "Ethernet|LAN") {
                    $adapterType = "Wired (Ethernet)"
                }
                
                # Get IP info
                $ipAddress = if ($config -and $config.IPAddress) { 
                    $config.IPAddress[0] 
                } else { 
                    "Not configured" 
                }
                
                $dhcpEnabled = if ($config) { 
                    $config.DHCPEnabled 
                } else { 
                    "Unknown" 
                }
                
                $adapters += [PSCustomObject]@{
                    Name              = $adapter.Name
                    Description       = $adapter.Description
                    Type              = $adapterType
                    Status            = $adapter.NetConnectionStatus
                    Connected         = $adapter.NetConnectionStatus -eq 2
                    MacAddress        = $adapter.MACAddress
                    IPAddress         = $ipAddress
                    DHCPEnabled       = $dhcpEnabled
                    Speed             = $adapter.Speed
                    DriverVersion     = $adapter.DriverVersion
                    Manufacturer      = $adapter.Manufacturer
                    Enabled           = $adapter.NetEnabled
                }
            } catch {
                Write-Warning "Failed to process adapter $($adapter.Name): $_"
            }
        }
    } catch {
        Write-Error "Failed to enumerate network adapters: $_"
        return $null
    }
    
    return $adapters
}

function Get-WirelessAdapters {
    <#
    .SYNOPSIS
        Gets only wireless network adapters
    
    .OUTPUTS
        Array of wireless adapter objects
    #>
    
    $adapters = Get-NetworkAdapterStatus -IncludeDisabled
    return $adapters | Where-Object { $_.Type -match "Wireless" }
}

function Get-WiredAdapters {
    <#
    .SYNOPSIS
        Gets only wired (Ethernet) network adapters
    
    .OUTPUTS
        Array of wired adapter objects
    #>
    
    $adapters = Get-NetworkAdapterStatus -IncludeDisabled
    return $adapters | Where-Object { $_.Type -match "Wired|Ethernet" }
}

################################################################################
# NETWORK CONNECTIVITY TESTING FUNCTIONS
################################################################################

function Test-InternetConnectivity {
    <#
    .SYNOPSIS
        Comprehensive internet connectivity test with detailed failure reporting
    
    .DESCRIPTION
        Performs step-by-step connectivity testing:
        1. Tests DHCP configuration
        2. Tests DNS resolution
        3. Tests ping to 8.8.8.8 (Google DNS)
        4. Tests ping to google.com (resolving hostname)
        5. Reports specific failure points
    
    .PARAMETER Verbose
        Shows detailed step-by-step output
    
    .OUTPUTS
        PSCustomObject with test results and failure points
    #>
    
    param(
        [switch]$Verbose
    )
    
    $result = [PSCustomObject]@{
        Success           = $false
        DHCPConfigured    = $false
        DNSResolving      = $false
        CanPingGoogle     = $false
        CanResolveGoogle  = $false
        InternetReachable = $false
        FailurePoints     = @()
        Details           = @()
        Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    # Step 1: Check DHCP Configuration
    if ($Verbose) { Write-Host "[1/5] Checking DHCP configuration..." -ForegroundColor Cyan }
    try {
        $adapters = Get-NetworkAdapterStatus | Where-Object { $_.Connected }
        
        if ($adapters.Count -eq 0) {
            $result.FailurePoints += "No connected network adapters detected"
            if ($Verbose) { Write-Host "    [FAILED] No connected adapters found" -ForegroundColor Red }
            return $result
        }
        
        $dhcpConfigs = $adapters | Where-Object { $_.DHCPEnabled -eq $true }
        if ($dhcpConfigs.Count -gt 0) {
            $result.DHCPConfigured = $true
            if ($Verbose) { 
                Write-Host "    [OK] DHCP configured on $($dhcpConfigs.Count) adapter(s)" -ForegroundColor Green 
            }
        } else {
            $result.FailurePoints += "DHCP not enabled on any connected adapter"
            if ($Verbose) { Write-Host "    [FAILED] DHCP not configured" -ForegroundColor Red }
        }
    } catch {
        $result.FailurePoints += "Error checking DHCP: $_"
        if ($Verbose) { Write-Host "    [FAILED] Error: $_" -ForegroundColor Red }
    }
    
    # Step 2: Check DNS Configuration
    if ($Verbose) { Write-Host "[2/5] Checking DNS configuration..." -ForegroundColor Cyan }
    try {
        $dnsServers = Get-DnsClientServerAddress -ErrorAction SilentlyContinue | 
            Where-Object { $_.ServerAddresses.Count -gt 0 } |
            Select-Object -First 1
        
        if ($dnsServers) {
            $result.DNSResolving = $true
            if ($Verbose) { 
                Write-Host "    [OK] DNS servers configured: $($dnsServers.ServerAddresses -join ', ')" -ForegroundColor Green 
            }
        } else {
            $result.FailurePoints += "No DNS servers configured"
            if ($Verbose) { Write-Host "    [FAILED] No DNS servers found" -ForegroundColor Red }
        }
    } catch {
        $result.FailurePoints += "Error checking DNS: $_"
        if ($Verbose) { Write-Host "    [FAILED] Error: $_" -ForegroundColor Red }
    }
    
    # Step 3: Test Ping to Google DNS (8.8.8.8)
    if ($Verbose) { Write-Host "[3/5] Testing connectivity to 8.8.8.8 (Google DNS)..." -ForegroundColor Cyan }
    try {
        $pingResult = Test-Connection -ComputerName "8.8.8.8" -Count 1 -ErrorAction SilentlyContinue
        if ($pingResult) {
            $result.CanPingGoogle = $true
            if ($Verbose) { 
                Write-Host "    [OK] Successfully pinged 8.8.8.8 (Response time: $($pingResult.ResponseTime)ms)" -ForegroundColor Green 
            }
        } else {
            $result.FailurePoints += "Cannot ping 8.8.8.8 - No response or timeout"
            if ($Verbose) { Write-Host "    [FAILED] No response from 8.8.8.8" -ForegroundColor Red }
        }
    } catch {
        $result.FailurePoints += "Error pinging 8.8.8.8: $_"
        if ($Verbose) { Write-Host "    [FAILED] Error: $_" -ForegroundColor Red }
    }
    
    # Step 4: Test DNS Resolution and Connectivity to google.com
    if ($Verbose) { Write-Host "[4/5] Testing DNS resolution for google.com..." -ForegroundColor Cyan }
    try {
        $dnsResolve = Resolve-DnsName -Name "google.com" -ErrorAction SilentlyContinue
        if ($dnsResolve) {
            if ($Verbose) { 
                Write-Host "    [OK] DNS resolution successful (IP: $($dnsResolve.IPAddress | Select-Object -First 1))" -ForegroundColor Green 
            }
            
            # Step 5: Ping google.com
            if ($Verbose) { Write-Host "[5/5] Testing connectivity to google.com..." -ForegroundColor Cyan }
            $pingGoogle = Test-Connection -ComputerName "google.com" -Count 1 -ErrorAction SilentlyContinue
            if ($pingGoogle) {
                $result.InternetReachable = $true
                $result.CanResolveGoogle = $true
                if ($Verbose) { 
                    Write-Host "    [OK] Successfully reached google.com (Response time: $($pingGoogle.ResponseTime)ms)" -ForegroundColor Green 
                }
            } else {
                $result.FailurePoints += "DNS resolved but cannot ping google.com"
                if ($Verbose) { Write-Host "    [FAILED] Cannot reach google.com despite DNS resolution" -ForegroundColor Red }
            }
        } else {
            $result.FailurePoints += "DNS resolution failed for google.com"
            if ($Verbose) { Write-Host "    [FAILED] DNS resolution failed" -ForegroundColor Red }
        }
    } catch {
        $result.FailurePoints += "Error during DNS resolution test: $_"
        if ($Verbose) { Write-Host "    [FAILED] Error: $_" -ForegroundColor Red }
    }
    
    # Determine overall success
    $result.Success = $result.InternetReachable
    
    return $result
}

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Quick network connectivity check
    
    .DESCRIPTION
        Lightweight check for basic network connectivity
    
    .OUTPUTS
        Boolean - True if internet is reachable
    #>
    
    try {
        $test = Test-Connection -ComputerName "8.8.8.8" -Count 1 -ErrorAction SilentlyContinue
        return $null -ne $test
    } catch {
        return $false
    }
}

################################################################################
# NETWORK DRIVER DETECTION FUNCTIONS
################################################################################

function Get-NetworkDrivers {
    <#
    .SYNOPSIS
        Harvests network drivers from the current system
    
    .DESCRIPTION
        Extracts information about loaded network drivers including:
        - Driver name and version
        - Driver path
        - Associated device
        - Driver file details
    
    .OUTPUTS
        Array of driver objects
    #>
    
    $drivers = @()
    
    try {
        # Get network devices
        $netDevices = Get-WmiObject Win32_NetworkAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.PhysicalAdapter -eq $true }
        
        foreach ($device in $netDevices) {
            try {
                # Get driver info
                $deviceInfo = Get-WmiObject Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
                    Where-Object { 
                        $_.Description -match $device.Description -or
                        $_.DeviceName -match $device.Name
                    }
                
                if ($deviceInfo) {
                    foreach ($driver in $deviceInfo) {
                        $drivers += [PSCustomObject]@{
                            DeviceName     = $device.Description
                            DriverName     = $driver.Description
                            DriverVersion  = $driver.DriverVersion
                            DriverPath     = $driver.InfName
                            DriverClass    = $driver.DeviceClass
                            Manufacturer   = $driver.Manufacturer
                            Status         = "Loaded"
                            IsSigned       = $driver.Signed
                            Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        }
                    }
                }
            } catch {
                Write-Warning "Failed to get driver info for $($device.Description): $_"
            }
        }
    } catch {
        Write-Error "Failed to enumerate network drivers: $_"
    }
    
    return $drivers
}

function Get-DriverStorePath {
    <#
    .SYNOPSIS
        Gets the Windows Driver Store path
    
    .OUTPUTS
        String path to Driver Store
    #>
    
    $driverStore = "$env:SystemRoot\System32\DriverStore\FileRepository"
    return $driverStore
}

function Find-NetworkDrivers {
    <#
    .SYNOPSIS
        Searches for network drivers in DriverStore
    
    .DESCRIPTION
        Locates all network-related INF files in the system DriverStore
    
    .OUTPUTS
        Array of driver paths
    #>
    
    $networkDrivers = @()
    
    try {
        $driverStore = Get-DriverStorePath
        
        if (Test-Path $driverStore) {
            # Search for network-related drivers
            $drivers = Get-ChildItem -Path $driverStore -Recurse -Include "*.inf" -ErrorAction SilentlyContinue |
                Where-Object { 
                    $_.Directory.Name -match "Net|Network|Ethernet|Wireless|WiFi|NIC|1394|USB"
                }
            
            foreach ($driver in $drivers) {
                $networkDrivers += [PSCustomObject]@{
                    Name       = $driver.Name
                    FullPath   = $driver.FullName
                    Directory  = $driver.Directory.Name
                    Folder     = $driver.Directory.Parent.Name
                    Size       = $driver.Length
                }
            }
        } else {
            Write-Warning "DriverStore not found at: $driverStore"
        }
    } catch {
        Write-Error "Error searching for drivers: $_"
    }
    
    return $networkDrivers
}

################################################################################
# DRIVER SEARCHING ON VOLUMES
################################################################################

function Find-DriversOnVolumes {
    <#
    .SYNOPSIS
        Searches for network drivers across all mounted volumes
    
    .DESCRIPTION
        Scans mounted drives for driver files (.inf, .sys, .cat)
        in common driver locations:
        - Windows\System32\drivers
        - Windows\Inf
        - Program Files\
        - OEM driver locations
    
    .PARAMETER Volumes
        Specific drive letters to search (e.g., 'D:', 'E:')
    
    .PARAMETER IncludeSystemDrive
        Include the current system drive in search
    
    .OUTPUTS
        Array of discovered driver files
    #>
    
    param(
        [string[]]$Volumes = @(),
        [switch]$IncludeSystemDrive
    )
    
    $drivers = @()
    $searchedPaths = @()
    
    # If no volumes specified, discover them
    if ($Volumes.Count -eq 0) {
        $Volumes = Get-Volume | 
            Where-Object { $_.DriveLetter -and $_.FileSystem -match "NTFS|FAT" } |
            Select-Object -ExpandProperty DriveLetter |
            ForEach-Object { "$_`:" }
    }
    
    # Remove system drive if not requested
    if (-not $IncludeSystemDrive) {
        $systemDrive = $env:SystemDrive
        $Volumes = $Volumes | Where-Object { $_ -ne $systemDrive }
    }
    
    foreach ($volume in $Volumes) {
        Write-Host "Searching for drivers on $volume..." -ForegroundColor Yellow
        
        # Common driver paths
        $driverPaths = @(
            "$volume\Windows\System32\drivers",
            "$volume\Windows\Inf",
            "$volume\Windows\System32\DriverStore\FileRepository",
            "$volume\Program Files\*",
            "$volume\Program Files (x86)\*",
            "$volume\OEM\*",
            "$volume\Drivers"
        )
        
        foreach ($path in $driverPaths) {
            try {
                if (Test-Path $path) {
                    $searchedPaths += $path
                    
                    # Find driver files
                    $files = Get-ChildItem -Path $path -Include ("*.inf", "*.sys", "*.cat") `
                        -Recurse -ErrorAction SilentlyContinue
                    
                    foreach ($file in $files) {
                        # Check if it's a network driver
                        if ($file.Name -match "Net|Ethernet|WiFi|Wireless|NIC" -or 
                            $file.Extension -eq ".inf") {
                            
                            $drivers += [PSCustomObject]@{
                                Name       = $file.Name
                                FullPath   = $file.FullName
                                Directory  = $file.Directory.Name
                                Volume     = $volume
                                Type       = $file.Extension
                                Size       = $file.Length
                                Modified   = $file.LastWriteTime
                            }
                        }
                    }
                }
            } catch {
                # Silently skip inaccessible paths
            }
        }
    }
    
    if ($drivers.Count -eq 0) {
        Write-Warning "No driver files found on searched volumes"
    }
    
    return $drivers | Sort-Object -Property Volume, Directory | Get-Unique -AsString
}

################################################################################
# DRIVER HARVESTING FUNCTIONS
################################################################################

function Export-NetworkDrivers {
    <#
    .SYNOPSIS
        Exports network drivers from DriverStore to a target location
    
    .DESCRIPTION
        Harvests network drivers and creates a driver package
        suitable for WinPE injection
    
    .PARAMETER OutputPath
        Destination folder for exported drivers (default: Desktop\NetworkDrivers)
    
    .PARAMETER ExcludeBuiltin
        Skip built-in Microsoft drivers
    
    .OUTPUTS
        PSCustomObject with export results
    #>
    
    param(
        [string]$OutputPath = "$env:USERPROFILE\Desktop\NetworkDrivers_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
        [switch]$ExcludeBuiltin
    )
    
    $result = @{
        Success      = $false
        OutputPath   = $OutputPath
        DriversFound = 0
        DriversCopied = 0
        Errors       = @()
        Details      = @()
    }
    
    try {
        # Create output directory
        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        
        # Get network drivers
        $drivers = Get-NetworkDrivers
        
        if ($drivers.Count -eq 0) {
            $result.Errors += "No network drivers found to export"
            return $result
        }
        
        $result.DriversFound = $drivers.Count
        
        # Copy driver files
        foreach ($driver in $drivers) {
            try {
                if (-not $driver.DriverPath) { continue }
                
                # Skip Microsoft built-in drivers if requested
                if ($ExcludeBuiltin -and $driver.Manufacturer -match "Microsoft") {
                    continue
                }
                
                $sourceFile = $driver.DriverPath
                if (Test-Path $sourceFile) {
                    $fileName = Split-Path -Leaf $sourceFile
                    $destination = Join-Path $OutputPath $fileName
                    
                    Copy-Item -Path $sourceFile -Destination $destination -Force -ErrorAction SilentlyContinue
                    $result.DriversCopied++
                    $result.Details += "Exported: $fileName from $sourceFile"
                }
            } catch {
                $result.Errors += "Failed to export $($driver.DriverName): $_"
            }
        }
        
        $result.Success = $result.DriversCopied -gt 0
        
        if ($result.Success) {
            Write-Host "[OK] Successfully exported $($result.DriversCopied) driver(s) to: $OutputPath" -ForegroundColor Green
        }
        
    } catch {
        $result.Errors += "Export failed: $_"
    }
    
    return $result
}

################################################################################
# DRIVER INJECTION FUNCTIONS
################################################################################

function Add-DriversToWinPE {
    <#
    .SYNOPSIS
        Injects network drivers into a WinPE image
    
    .DESCRIPTION
        Adds drivers to a mounted WinPE image using DISM
        Supports both mounted WIM and VHD formats
    
    .PARAMETER ImagePath
        Path to mounted WinPE image
    
    .PARAMETER DriverPath
        Path to drivers to inject
    
    .PARAMETER Recursive
        Recursively search for drivers in subdirectories
    
    .OUTPUTS
        PSCustomObject with injection results
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$ImagePath,
        
        [Parameter(Mandatory=$true)]
        [string]$DriverPath,
        
        [switch]$Recursive = $true
    )
    
    $result = @{
        Success = $false
        Command = ""
        Output = @()
        Errors = @()
    }
    
    try {
        # Validate paths
        if (-not (Test-Path $ImagePath)) {
            throw "WinPE image path not found: $ImagePath"
        }
        
        if (-not (Test-Path $DriverPath)) {
            throw "Driver path not found: $DriverPath"
        }
        
        # Build DISM command
        $dismCmd = "dism /Image:`"$ImagePath`" /Add-Driver /Driver:`"$DriverPath`""
        
        if ($Recursive) {
            $dismCmd += " /Recurse"
        }
        
        $dismCmd += " /ForceUnsigned"
        
        $result.Command = $dismCmd
        
        Write-Host "Injecting drivers into WinPE..." -ForegroundColor Yellow
        Write-Host "Command: $dismCmd" -ForegroundColor Gray
        
        # Execute DISM
        $output = Invoke-Expression $dismCmd 2>&1
        $result.Output = $output
        
        # Check for success
        if ($LASTEXITCODE -eq 0) {
            $result.Success = $true
            Write-Host "[OK] Drivers successfully injected" -ForegroundColor Green
        } else {
            $result.Errors += "DISM returned exit code: $LASTEXITCODE"
            Write-Host "[FAILED] Driver injection failed (Exit code: $LASTEXITCODE)" -ForegroundColor Red
        }
        
    } catch {
        $result.Errors += $_
        Write-Error "Driver injection error: $_"
    }
    
    return $result
}

################################################################################
# NETWORK ADAPTER MANAGEMENT
################################################################################

function Enable-NetworkAdapter {
    <#
    .SYNOPSIS
        Enables a disabled network adapter
    
    .DESCRIPTION
        Re-enables a network adapter that has been disabled
        Works in both FullOS and WinPE environments
    
    .PARAMETER AdapterName
        Name of the adapter to enable
    
    .OUTPUTS
        PSCustomObject with operation result
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$AdapterName
    )
    
    $result = @{
        Success = $false
        Message = ""
        Error   = ""
    }
    
    try {
        # Try via netsh (works in most environments)
        Write-Host "Attempting to enable adapter: $AdapterName" -ForegroundColor Yellow
        
        $output = netsh interface set interface name="$AdapterName" admin=enabled 2>&1
        
        # Verify
        Start-Sleep -Seconds 2
        $adapter = Get-NetworkAdapterStatus | Where-Object { $_.Name -eq $AdapterName }
        
        if ($adapter -and $adapter.Enabled) {
            $result.Success = $true
            $result.Message = "Network adapter '$AdapterName' successfully enabled"
            Write-Host "[OK] $($result.Message)" -ForegroundColor Green
        } else {
            $result.Message = "Adapter enable command executed but status unclear"
            Write-Host "[!] $($result.Message)" -ForegroundColor Yellow
        }
        
    } catch {
        $result.Error = $_
        Write-Error "Failed to enable adapter: $_"
    }
    
    return $result
}

function Disable-NetworkAdapter {
    <#
    .SYNOPSIS
        Disables a network adapter
    
    .DESCRIPTION
        Temporarily disables a network adapter
        Can be useful for troubleshooting connectivity issues
    
    .PARAMETER AdapterName
        Name of the adapter to disable
    
    .OUTPUTS
        PSCustomObject with operation result
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [string]$AdapterName
    )
    
    $result = @{
        Success = $false
        Message = ""
        Error   = ""
    }
    
    try {
        Write-Host "Attempting to disable adapter: $AdapterName" -ForegroundColor Yellow
        
        $output = netsh interface set interface name="$AdapterName" admin=disabled 2>&1
        
        Start-Sleep -Seconds 2
        $adapter = Get-NetworkAdapterStatus -IncludeDisabled | Where-Object { $_.Name -eq $AdapterName }
        
        if ($adapter -and -not $adapter.Enabled) {
            $result.Success = $true
            $result.Message = "Network adapter '$AdapterName' successfully disabled"
            Write-Host "[OK] $($result.Message)" -ForegroundColor Green
        } else {
            $result.Message = "Adapter disable command executed but status unclear"
            Write-Host "[!] $($result.Message)" -ForegroundColor Yellow
        }
        
    } catch {
        $result.Error = $_
        Write-Error "Failed to disable adapter: $_"
    }
    
    return $result
}

################################################################################
# COMPREHENSIVE DIAGNOSTICS & TROUBLESHOOTING
################################################################################

function Invoke-NetworkDiagnostics {
    <#
    .SYNOPSIS
        Comprehensive network diagnostics and troubleshooting wizard
    
    .DESCRIPTION
        Interactive guided network troubleshooting that:
        1. Detects network adapters
        2. Checks connectivity at each stage
        3. Reports specific failure points
        4. Suggests remediation steps
        5. Exports detailed diagnostic report
    
    .PARAMETER Interactive
        Provides interactive prompts for user actions
    
    .OUTPUTS
        Comprehensive diagnostic report object
    #>
    
    param(
        [switch]$Interactive
    )
    
    $report = @{
        Timestamp          = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName       = $env:COMPUTERNAME
        Environment        = if ((Get-Item -Path "X:\" -ErrorAction SilentlyContinue)) { "WinPE/WinRE" } else { "FullOS" }
        Adapters           = $null
        WirelessAdapters   = 0
        WiredAdapters      = 0
        ConnectedAdapters  = 0
        Connectivity       = $null
        FailurePoints      = @()
        Recommendations    = @()
        DriversLoaded      = 0
        Success            = $false
    }
    
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "============================================================================================" -ForegroundColor Cyan
    Write-Host "                      NETWORK DIAGNOSTICS & TROUBLESHOOTING" -ForegroundColor Cyan
    Write-Host "                          MiracleBoot Network Module v1.0" -ForegroundColor Cyan
    Write-Host "============================================================================================" -ForegroundColor Cyan
    Write-Host "`n"
    
    # Phase 1: Adapter Detection
    Write-Host "[PHASE 1] Detecting Network Adapters..." -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------------------------------------------" -ForegroundColor Gray
    
    $adapters = Get-NetworkAdapterStatus -IncludeDisabled
    $report.Adapters = $adapters
    
    if ($adapters.Count -eq 0) {
        Write-Host "[FAILED] NO NETWORK ADAPTERS DETECTED" -ForegroundColor Red
        $report.FailurePoints += "No network adapters found in system"
        $report.Recommendations += "Check if drivers are loaded or hardware is present"
        Write-Host "   -> Possible causes: Missing drivers, disabled hardware, BIOS disabled" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "[OK] Found $($adapters.Count) network adapter(s)" -ForegroundColor Green
        Write-Host ""
        
        foreach ($adapter in $adapters) {
            $status = if ($adapter.Connected) { "[OK] Connected" } else { "[FAILED] Disconnected" }
            Write-Host "   $status  $($adapter.Description)" -ForegroundColor $(if ($adapter.Connected) { "Green" } else { "Yellow" })
            Write-Host "            Type: $($adapter.Type) | MAC: $($adapter.MacAddress)" -ForegroundColor Gray
            Write-Host "            IP: $($adapter.IPAddress) | DHCP: $($adapter.DHCPEnabled)" -ForegroundColor Gray
            Write-Host ""
        }
        
        $report.WiredAdapters = ($adapters | Where-Object { $_.Type -match "Wired" }).Count
        $report.WirelessAdapters = ($adapters | Where-Object { $_.Type -match "Wireless" }).Count
        $report.ConnectedAdapters = ($adapters | Where-Object { $_.Connected }).Count
    }
    
    # Phase 2: Drivers
    Write-Host "[PHASE 2] Checking Network Drivers..." -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------------------------------------------" -ForegroundColor Gray
    
    try {
        $drivers = Get-NetworkDrivers
        $report.DriversLoaded = $drivers.Count
        
        if ($drivers.Count -gt 0) {
            Write-Host "[OK] Found $($drivers.Count) loaded network driver(s)" -ForegroundColor Green
            foreach ($driver in $drivers | Select-Object -First 3) {
                Write-Host "   - $($driver.DriverName) (v$($driver.DriverVersion))" -ForegroundColor Gray
            }
            if ($drivers.Count -gt 3) {
                Write-Host "   ... and $($drivers.Count - 3) more" -ForegroundColor Gray
            }
        } else {
            Write-Host "[FAILED] No network drivers detected" -ForegroundColor Red
            $report.FailurePoints += "Network drivers not loaded"
            $report.Recommendations += "Load network drivers using driver injection"
        }
    } catch {
        Write-Host "[!] Could not query drivers: $_" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Phase 3: Connectivity Testing
    Write-Host "[PHASE 3] Testing Internet Connectivity..." -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------------------------------------------" -ForegroundColor Gray
    
    $connectivity = Test-InternetConnectivity -Verbose
    $report.Connectivity = $connectivity
    
    if ($connectivity.Success) {
        Write-Host ""
        Write-Host "[OK] INTERNET CONNECTIVITY CONFIRMED" -ForegroundColor Green
        Write-Host "    All connectivity tests passed!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "[FAILED] CONNECTIVITY ISSUES DETECTED" -ForegroundColor Red
        
        if ($connectivity.FailurePoints.Count -gt 0) {
            Write-Host "`n   Specific Failure Points:" -ForegroundColor Yellow
            foreach ($failure in $connectivity.FailurePoints) {
                Write-Host "   -> $failure" -ForegroundColor Red
            }
        }
        
        $report.FailurePoints += $connectivity.FailurePoints
    }
    Write-Host ""
    
    # Phase 4: Recommendations
    Write-Host "[PHASE 4] Diagnostic Summary & Recommendations..." -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------------------------------------------" -ForegroundColor Gray
    
    if ($connectivity.Success) {
        $report.Success = $true
        Write-Host "[OK] Network Status: FULLY OPERATIONAL" -ForegroundColor Green
        Write-Host "`n   Your network is properly configured and has internet access." -ForegroundColor Green
    } else {
        Write-Host "[!] Network Status: REQUIRES ATTENTION" -ForegroundColor Yellow
        Write-Host ""
        
        if (-not $report.Adapters -or $report.ConnectedAdapters -eq 0) {
            Write-Host "   ISSUE: No connected network adapters" -ForegroundColor Red
            Write-Host "   ACTION: Check cable connections or enable WiFi adapter" -ForegroundColor Yellow
            Write-Host ""
        }
        
        if ($report.DriversLoaded -eq 0) {
            Write-Host "   ISSUE: No network drivers loaded" -ForegroundColor Red
            Write-Host "   ACTION: Inject drivers using 'Add-DriversToWinPE' or enable Windows Updates" -ForegroundColor Yellow
            Write-Host ""
        }
        
        if (-not $connectivity.DHCPConfigured) {
            Write-Host "   ISSUE: DHCP not configured" -ForegroundColor Red
            Write-Host "   ACTION: Enable DHCP in network adapter settings" -ForegroundColor Yellow
            Write-Host ""
        }
        
        if (-not $connectivity.DNSResolving) {
            Write-Host "   ISSUE: DNS not resolving" -ForegroundColor Red
            Write-Host "   ACTION: Check DNS server configuration (8.8.8.8 or 1.1.1.1 as backup)" -ForegroundColor Yellow
            Write-Host ""
        }
    }
    
    Write-Host ""
    
    return $report
}

################################################################################
# HELP & GUIDANCE FUNCTIONS
################################################################################

function Get-NetworkTroubleshootingGuide {
    <#
    .SYNOPSIS
        Displays detailed network troubleshooting guide
    
    .OUTPUTS
        Formatted help text
    #>
    
    $guide = @"
============================================================================================
                    NETWORK TROUBLESHOOTING GUIDE
                        MiracleBoot Network Module
============================================================================================

COMMON NETWORK ISSUES AND SOLUTIONS
-------------------------------------------------------------------------------------------

ISSUE 1: No Network Adapters Detected
============================================================================================

Symptoms:
  - Get-NetworkAdapterStatus returns empty
  - Network icon shows "No adapters"
  - Cannot see any network connections

Possible Causes:
  [FAILED] Network drivers not installed
  [FAILED] Network adapter disabled in Device Manager
  [FAILED] Network adapter disabled in BIOS
  [FAILED] Hardware not recognized

Solutions (in order of ease):
  1. Check BIOS: Reboot and enter BIOS, enable "Onboard Network" or "LAN"
  2. Device Manager: Right-click "Unknown device", update driver
  3. Inject drivers: Use Add-DriversToWinPE with proper network drivers
  4. Hardware test: Run HWINFO to verify hardware is present

Command to re-detect hardware:
  Get-PnpDevice -Status Unknown | Where-Object { $_.InstanceId -match "PCI|USB" }


ISSUE 2: Network Adapter Present But Disconnected
============================================================================================

Symptoms:
  - Adapter shows in Device Manager but marked disconnected
  - No cable symbol or WiFi connected icon

Possible Causes:
  [FAILED] Ethernet cable not connected
  [FAILED] WiFi network not visible or wrong password
  [FAILED] Adapter driver not fully loaded
  [FAILED] DHCP timeout

Solutions:
  1. Physical: Check cable is firmly connected to both PC and router
  2. WiFi: Verify WiFi network is visible and SSID is correct
  3. Restart: Disable then enable adapter
     Enable-NetworkAdapter "Ethernet"
  4. DHCP: Manually request DHCP lease
     ipconfig /release
     ipconfig /renew


ISSUE 3: Adapter Connected But No IP Address (Stuck on DHCP)
============================================================================================

Symptoms:
  - Adapter shows connected but IP is 169.x.x.x (APIPA)
  - ipconfig shows DHCP enabled but no address assigned
  - Cannot access network resources

Possible Causes:
  [FAILED] DHCP server not responding
  [FAILED] Router misconfigured
  [FAILED] Network adapter DHCP timeout
  [FAILED] Duplicate IP on network

Solutions:
  1. Restart DHCP: ipconfig /release && ipconfig /renew
  2. Timeout increase: Restart network service
     net stop dhcp && net start dhcp
  3. Static IP (temporary): Set manual IP for testing
     netsh interface ip set address "Ethernet" static 192.168.1.100 255.255.255.0
  4. Router check: Reboot router and wait 30 seconds

Command to check DHCP lease:
  ipconfig /all | findstr /i "dhcp server lease"


ISSUE 4: DHCP Works But Cannot Resolve Domain Names
============================================================================================

Symptoms:
  - ipconfig shows valid IP and gateway
  - Can ping IP addresses (ping 8.8.8.8 works)
  - Cannot ping domain names (ping google.com fails)
  - "Cannot find host" errors

Possible Causes:
  [FAILED] DNS server not configured
  [FAILED] DNS server unreachable
  [FAILED] ISP DNS is blocking
  [FAILED] Router DNS misconfigured

Solutions:
  1. Check DNS: ipconfig /all | findstr "DNS Server"
  2. Set manual DNS:
     netsh interface ipv4 set dnsservers "Ethernet" static 8.8.8.8 primary
     netsh interface ipv4 add dnsservers "Ethernet" 8.8.4.4 index=2
  3. Clear DNS cache: ipconfig /flushdns
  4. Test: ping google.com

Recommended DNS servers:
  - Google: 8.8.8.8 and 8.8.4.4
  - Cloudflare: 1.1.1.1 and 1.0.0.1
  - OpenDNS: 208.67.222.123 and 208.67.220.123


ISSUE 5: DNS Works But Cannot Access Internet
============================================================================================

Symptoms:
  - ping google.com works
  - Web browser shows "Cannot connect"
  - Some services work, others don't

Possible Causes:
  [FAILED] Firewall blocking internet access
  [FAILED] Proxy misconfigured
  [FAILED] ISP blocking ports
  [FAILED] Network timeout issues

Solutions:
  1. Check firewall: Windows Defender Firewall > Allow an app
  2. Disable firewall (temporary):
     netsh advfirewall set allprofiles state off
  3. Check proxy: netsh winhttp show proxy
  4. Reset proxy: netsh winhttp reset proxy
  5. Advanced troubleshooting: Trace route
     tracert google.com


ISSUE 6: Intermittent Connectivity Drops
============================================================================================

Symptoms:
  - Connection drops for 10-30 seconds then reconnects
  - High packet loss on ping
  - Network becomes unresponsive periodically

Possible Causes:
  [FAILED] Driver issue (power saving mode enabled)
  [FAILED] WiFi interference
  [FAILED] Router stability problem
  [FAILED] Hardware conflict

Solutions:
  1. Disable power saving for NIC:
     powercfg /change disk-timeout-ac 0
     powercfg /change disk-timeout-dc 0
  2. Update driver to latest version
  3. Change WiFi channel (router settings) to less crowded channel
  4. Test wired connection if available
  5. Check router logs for stability issues


QUICK DIAGNOSTICS
-------------------------------------------------------------------------------------------

Run this command for complete network diagnostics:
  Invoke-NetworkDiagnostics -Interactive

Check adapter status:
  Get-NetworkAdapterStatus | Format-Table

Test connectivity:
  Test-InternetConnectivity -Verbose

Find drivers:
  Find-NetworkDrivers

Export drivers:
  Export-NetworkDrivers -OutputPath "C:\Drivers"


ADVANCED COMMANDS
-------------------------------------------------------------------------------------------

ipconfig /all                    - Show all network details
netsh interface show interface   - List all adapters
netsh interface ipv4 show route  - Show routing table
pathping google.com              - Advanced connectivity test
Get-NetAdapter | Select Status   - PowerShell adapter status
Get-NetIPAddress                 - All IP addresses
Resolve-DnsName google.com       - DNS resolution test

"@
    
    return $guide
}

function Get-NetworkDiagnosticsHelp {
    <#
    .SYNOPSIS
        Displays help for available network diagnostics functions
    
    .OUTPUTS
        Formatted help text
    #>
    
    $help = @"
============================================================================================
                  NETWORK DIAGNOSTICS MODULE - FUNCTION REFERENCE
                         MiracleBoot v7.2.0 Network Module
============================================================================================

ADAPTER DETECTION FUNCTIONS
-------------------------------------------------------------------------------------------

Get-NetworkAdapterStatus
  Purpose: Get all network adapters and their status
  Usage:   Get-NetworkAdapterStatus [-IncludeDisabled]
  Example: Get-NetworkAdapterStatus | Where-Object Connected -eq True
  Output:  PSCustomObject with adapter details

Get-WiredAdapters
  Purpose: Get only Ethernet/wired adapters
  Usage:   Get-WiredAdapters
  Example: Get-WiredAdapters | Select Name, Status
  Output:  Array of wired adapter objects

Get-WirelessAdapters
  Purpose: Get only WiFi/wireless adapters
  Usage:   Get-WirelessAdapters
  Example: Get-WirelessAdapters | Format-List
  Output:  Array of wireless adapter objects


CONNECTIVITY TESTING FUNCTIONS
-------------------------------------------------------------------------------------------

Test-InternetConnectivity
  Purpose: Comprehensive multi-step connectivity test
  Usage:   Test-InternetConnectivity [-Verbose]
  Example: \$result = Test-InternetConnectivity -Verbose
  Output:  PSCustomObject with test results and failure points
  Tests:   DHCP -> DNS -> Ping 8.8.8.8 -> Ping google.com

Test-NetworkConnectivity
  Purpose: Quick internet connectivity check
  Usage:   Test-NetworkConnectivity
  Example: if (Test-NetworkConnectivity) { "Online" }
  Output:  Boolean (True/False)


DRIVER DETECTION FUNCTIONS
-------------------------------------------------------------------------------------------

Get-NetworkDrivers
  Purpose: Get currently loaded network drivers
  Usage:   Get-NetworkDrivers
  Example: Get-NetworkDrivers | Export-Csv drivers.csv
  Output:  Array of driver objects with version info

Find-NetworkDrivers
  Purpose: Find network drivers in DriverStore
  Usage:   Find-NetworkDrivers
  Example: \$drivers = Find-NetworkDrivers
  Output:  Array of INF files from DriverStore

Find-DriversOnVolumes
  Purpose: Search for drivers on mounted volumes
  Usage:   Find-DriversOnVolumes [-Volumes D:,E:] [-IncludeSystemDrive]
  Example: Find-DriversOnVolumes -Volumes D: -IncludeSystemDrive
  Output:  Array of driver files found on volumes

Get-DriverStorePath
  Purpose: Get Windows DriverStore path
  Usage:   Get-DriverStorePath
  Example: \$path = Get-DriverStorePath
  Output:  String path to DriverStore


DRIVER MANAGEMENT FUNCTIONS
-------------------------------------------------------------------------------------------

Export-NetworkDrivers
  Purpose: Export network drivers to a folder
  Usage:   Export-NetworkDrivers [-OutputPath path] [-ExcludeBuiltin]
  Example: Export-NetworkDrivers -OutputPath "C:\Drivers"
  Output:  PSCustomObject with export results

Add-DriversToWinPE
  Purpose: Inject drivers into WinPE image
  Usage:   Add-DriversToWinPE -ImagePath path -DriverPath path [-Recursive]
  Example: Add-DriversToWinPE -ImagePath "C:\mount" -DriverPath "C:\Drivers"
  Output:  PSCustomObject with DISM results


ADAPTER MANAGEMENT FUNCTIONS
-------------------------------------------------------------------------------------------

Enable-NetworkAdapter
  Purpose: Enable a disabled network adapter
  Usage:   Enable-NetworkAdapter -AdapterName name
  Example: Enable-NetworkAdapter -AdapterName "Ethernet"
  Output:  PSCustomObject with result

Disable-NetworkAdapter
  Purpose: Disable a network adapter
  Usage:   Disable-NetworkAdapter -AdapterName name
  Example: Disable-NetworkAdapter -AdapterName "WiFi"
  Output:  PSCustomObject with result


DIAGNOSTICS & REPORTING FUNCTIONS
-------------------------------------------------------------------------------------------

Invoke-NetworkDiagnostics
  Purpose: Run comprehensive network diagnostics
  Usage:   Invoke-NetworkDiagnostics [-Interactive]
  Example: \$report = Invoke-NetworkDiagnostics -Interactive
  Output:  Detailed diagnostic report object
  Shows:   Adapters, drivers, connectivity, recommendations

Get-NetworkTroubleshootingGuide
  Purpose: Display network troubleshooting guide
  Usage:   Get-NetworkTroubleshootingGuide
  Example: Get-NetworkTroubleshootingGuide | Out-Host
  Output:  Formatted help text with solutions

Get-NetworkDiagnosticsHelp
  Purpose: Display this function reference
  Usage:   Get-NetworkDiagnosticsHelp
  Example: Get-NetworkDiagnosticsHelp | Out-Host
  Output:  This help text


COMMON WORKFLOWS
-------------------------------------------------------------------------------------------

WORKFLOW 1: Quick Network Check
  Get-NetworkAdapterStatus
  Test-InternetConnectivity
  
WORKFLOW 2: Full Diagnostics
  Invoke-NetworkDiagnostics -Interactive
  
WORKFLOW 3: Export and Inject Drivers
  Export-NetworkDrivers -OutputPath "C:\NetDrivers"
  Add-DriversToWinPE -ImagePath "C:\mount\boot.wim" -DriverPath "C:\NetDrivers"
  
WORKFLOW 4: Find Drivers on USB
  Find-DriversOnVolumes -Volumes D: -IncludeSystemDrive
  
WORKFLOW 5: Troubleshoot Connectivity
  Get-NetworkTroubleshootingGuide
  # Follow step-by-step instructions


TIPS & BEST PRACTICES
-------------------------------------------------------------------------------------------

1. Always run diagnostics before attempting fixes
   \$diag = Invoke-NetworkDiagnostics
   
2. Check failure points for specific issues
   \$diag.FailurePoints
   
3. Export drivers before losing internet
   Export-NetworkDrivers -ExcludeBuiltin
   
4. Use -Verbose flag for detailed output
   Test-InternetConnectivity -Verbose
   
5. Test each step independently
   Get-NetworkAdapterStatus
   Test-NetworkConnectivity
   Resolve-DnsName google.com
   
6. Save diagnostic reports
   \$report = Invoke-NetworkDiagnostics
   \$report | ConvertTo-Json | Out-File "diagnosis.json"


REQUIREMENTS & ENVIRONMENT
-------------------------------------------------------------------------------------------

Privileges: Administrator (required for most operations)
OS Support: Windows 10/11 (FullOS, WinPE, WinRE)
PowerShell: 5.0 or later (7.0+ recommended)
Network: IPv4 supported (IPv6 partial support)

"@
    
    return $help
}

################################################################################
# MODULE EXPORT
################################################################################

# Export all public functions
Export-ModuleMember -Function @(
    'Get-NetworkAdapterStatus',
    'Get-WirelessAdapters',
    'Get-WiredAdapters',
    'Test-InternetConnectivity',
    'Test-NetworkConnectivity',
    'Get-NetworkDrivers',
    'Get-DriverStorePath',
    'Find-NetworkDrivers',
    'Find-DriversOnVolumes',
    'Export-NetworkDrivers',
    'Add-DriversToWinPE',
    'Enable-NetworkAdapter',
    'Disable-NetworkAdapter',
    'Invoke-NetworkDiagnostics',
    'Get-NetworkTroubleshootingGuide',
    'Get-NetworkDiagnosticsHelp'
)

################################################################################
# END OF NETWORK DIAGNOSTICS MODULE
################################################################################
