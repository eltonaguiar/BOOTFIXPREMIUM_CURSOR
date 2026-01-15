<#
    ENHANCED ERROR LOGGING FRAMEWORK
    =================================
    
    Centralized error logging for MiracleBoot with automatic log cleanup.
    Captures ALL errors and warnings so user can just say "fix the errors".
#>

# Global log configuration
$script:MiracleBootLogConfig = @{
    LogsPath = $null
    ErrorLogsPath = $null
    CurrentLogFile = $null
    LogRetentionDays = 7  # Keep logs for 7 days
    MaxLogSizeMB = 10     # Rotate if log exceeds 10MB
}

function Initialize-ErrorLogging {
    <#
    .SYNOPSIS
        Initializes logging system and cleans up old logs.
    #>
    param(
        [string]$ScriptRoot = $PSScriptRoot,
        [int]$RetentionDays = 7
    )
    
    $script:MiracleBootLogConfig.LogRetentionDays = $RetentionDays
    
    # Determine script root if not provided
    if (-not $ScriptRoot) {
        $ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.ScriptName }
    }
    
    # Create logs directory structure
    $logsPath = Join-Path $ScriptRoot "LOGS"
    if (-not (Test-Path $logsPath)) {
        try {
            New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
        } catch {
            Write-Host "WARNING: Could not create LOGS directory: $_" -ForegroundColor Yellow
            # Fallback to temp directory
            $logsPath = Join-Path $env:TEMP "MiracleBoot_LOGS"
            New-Item -ItemType Directory -Path $logsPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    
    $errorLogsPath = Join-Path $logsPath "ERROR_LOGS"
    if (-not (Test-Path $errorLogsPath)) {
        try {
            New-Item -ItemType Directory -Path $errorLogsPath -Force | Out-Null
        } catch {
            Write-Host "WARNING: Could not create ERROR_LOGS directory: $_" -ForegroundColor Yellow
            $errorLogsPath = $logsPath
        }
    }
    
    $script:MiracleBootLogConfig.LogsPath = $logsPath
    $script:MiracleBootLogConfig.ErrorLogsPath = $errorLogsPath
    
    # Clean up old logs BEFORE creating new one
    Clear-OldLogs -LogsPath $errorLogsPath -RetentionDays $RetentionDays
    
    # Set current log file
    $today = Get-Date -Format 'yyyy-MM-dd'
    $script:MiracleBootLogConfig.CurrentLogFile = Join-Path $errorLogsPath "MiracleBoot_$today.log"
    
    return @{
        LogsPath = $logsPath
        ErrorLogsPath = $errorLogsPath
        CurrentLogFile = $script:MiracleBootLogConfig.CurrentLogFile
    }
}

function Clear-OldLogs {
    <#
    .SYNOPSIS
        Removes log files older than retention period.
    #>
    param(
        [string]$LogsPath,
        [int]$RetentionDays = 7
    )
    
    if (-not (Test-Path $LogsPath)) {
        return
    }
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        $logFiles = Get-ChildItem -Path $LogsPath -Filter "MiracleBoot_*.log" -ErrorAction SilentlyContinue
        
        $deletedCount = 0
        foreach ($logFile in $logFiles) {
            if ($logFile.LastWriteTime -lt $cutoffDate) {
                try {
                    Remove-Item -Path $logFile.FullName -Force -ErrorAction Stop
                    $deletedCount++
                } catch {
                    # Silently continue if deletion fails
                }
            }
        }
        
        if ($deletedCount -gt 0) {
            Write-Host "[LOG CLEANUP] Removed $deletedCount old log file(s) (older than $RetentionDays days)" -ForegroundColor Gray
        }
    } catch {
        # Silently fail - don't break execution if cleanup fails
    }
}

function Add-MiracleBootLog {
    <#
    .SYNOPSIS
        Logs a message with automatic error/warning capture.
    #>
    param(
        [ValidateSet("ERROR", "WARNING", "INFO", "DEBUG", "SUCCESS")]
        [string]$Level = "INFO",
        [string]$Message = "",
        [string]$Location = "Unknown",
        [hashtable]$Data = @{},
        [string]$ScriptRoot = $PSScriptRoot,
        [switch]$NoConsole  # Don't write to console (for high-volume logging)
    )
    
    # Initialize logging if not already done
    if (-not $script:MiracleBootLogConfig.CurrentLogFile) {
        $null = Initialize-ErrorLogging -ScriptRoot $ScriptRoot
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    
    # Get calling function/script name
    # CRITICAL: Disable call stack retrieval during GUI initialization to prevent call depth overflow
    # Global flag to disable Get-PSCallStack entirely during high-call-depth operations
    if (-not (Test-Path Variable:script:DisableCallStackRetrieval)) {
        $script:DisableCallStackRetrieval = $false
    }
    
    # Only get call stack if:
    # 1. Location is Unknown
    # 2. Call stack retrieval is not disabled (GUI init mode)
    # 3. We're not in a deep call chain
    if ($Location -eq "Unknown" -and -not $script:DisableCallStackRetrieval) {
        try {
            # Check current call depth first (without retrieving full stack)
            # Use a lightweight check to avoid adding to call depth
            $currentDepth = 0
            try {
                $testStack = Get-PSCallStack -ErrorAction SilentlyContinue
                if ($testStack) { $currentDepth = $testStack.Count }
            } catch {
                # If even checking depth fails, skip entirely
                $Location = "Unknown"
            }
            
            # Only retrieve full call stack if depth is safe (< 50 to prevent overflow)
            if ($currentDepth -gt 0 -and $currentDepth -lt 50) {
                $callStack = Get-PSCallStack -ErrorAction SilentlyContinue
                if ($callStack -and $callStack.Count -gt 1) {
                    $caller = $callStack[1]
                    $Location = "$($caller.FunctionName)@$($caller.ScriptName):$($caller.ScriptLineNumber)"
                }
            } else {
                # Depth too high, skip call stack retrieval
                $Location = "Unknown"
            }
        } catch {
            # Silently fail if call stack retrieval causes issues
            $Location = "Unknown"
        }
    }
    
    $dataStr = ""
    if ($Data.Count -gt 0) {
        try {
            $dataStr = " | Data: " + ($Data | ConvertTo-Json -Compress -Depth 3)
        } catch {
            $dataStr = " | Data: (unable to serialize)"
        }
    }
    
    $logLine = "[$timestamp] [$Level] [PID:$processId] [$Location] $Message$dataStr"
    
    # Write to console (unless NoConsole specified)
    if (-not $NoConsole) {
        $color = switch ($Level) {
            "ERROR"   { "Red" }
            "WARNING" { "Yellow" }
            "INFO"    { "Gray" }
            "DEBUG"   { "DarkGray" }
            "SUCCESS" { "Green" }
            default   { "White" }
        }
        Write-Host $logLine -ForegroundColor $color
    }
    
    # Write to log file
    try {
        # Check if log file needs rotation
        if (Test-Path $script:MiracleBootLogConfig.CurrentLogFile) {
            $logFile = Get-Item $script:MiracleBootLogConfig.CurrentLogFile
            if ($logFile.Length -gt ($script:MiracleBootLogConfig.MaxLogSizeMB * 1MB)) {
                Rotate-LogFile -LogFile $script:MiracleBootLogConfig.CurrentLogFile
            }
        }
        
        Add-Content -Path $script:MiracleBootLogConfig.CurrentLogFile -Value $logLine -ErrorAction Stop -Encoding UTF8
    } catch {
        # Try to log to alternate location if primary fails
        try {
            $altLog = Join-Path $env:TEMP "MiracleBoot_Error_$(Get-Date -Format 'yyyy-MM-dd').log"
            Add-Content -Path $altLog -Value $logLine -ErrorAction Stop -Encoding UTF8
        } catch {
            # Last resort: silently fail
        }
    }
    
    # Add to in-memory buffer
    if (-not (Test-Path Variable:global:MiracleBootLogBuffer)) {
        $global:MiracleBootLogBuffer = @()
    }
    $global:MiracleBootLogBuffer += @{
        Timestamp = $timestamp
        Level     = $Level
        Location  = $Location
        Message   = $Message
        Data      = $Data
    }
    
    # Keep buffer size manageable (last 1000 entries)
    if ($global:MiracleBootLogBuffer.Count -gt 1000) {
        $global:MiracleBootLogBuffer = $global:MiracleBootLogBuffer[-1000..-1]
    }
}

function Rotate-LogFile {
    <#
    .SYNOPSIS
        Rotates log file when it exceeds size limit.
    #>
    param([string]$LogFile)
    
    if (-not (Test-Path $LogFile)) {
        return
    }
    
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $rotatedName = $LogFile -replace '\.log$', "_$timestamp.log"
        Move-Item -Path $LogFile -Destination $rotatedName -Force -ErrorAction Stop
        
        # Create new log file
        $null = New-Item -ItemType File -Path $LogFile -Force
        
        Add-MiracleBootLog -Level "INFO" -Message "Log file rotated due to size limit" -Location "Rotate-LogFile" -NoConsole
    } catch {
        # Silently fail
    }
}

function Get-MiracleBootLogSummary {
    <#
    .SYNOPSIS
        Gets summary of all logged errors and warnings.
    #>
    param([switch]$IncludeInfo)
    
    if (-not (Test-Path Variable:global:MiracleBootLogBuffer)) {
        return @{
            TotalErrors = 0
            TotalWarnings = 0
            Errors = @()
            Warnings = @()
            AllEntries = @()
        }
    }
    
    $errors = @($global:MiracleBootLogBuffer | Where-Object { $_.Level -eq "ERROR" })
    $warnings = @($global:MiracleBootLogBuffer | Where-Object { $_.Level -eq "WARNING" })
    
    $allEntries = if ($IncludeInfo) {
        $global:MiracleBootLogBuffer
    } else {
        @($errors + $warnings)
    }
    
    return @{
        TotalErrors = $errors.Count
        TotalWarnings = $warnings.Count
        Errors = $errors
        Warnings = $warnings
        AllEntries = $allEntries
        LogFile = $script:MiracleBootLogConfig.CurrentLogFile
    }
}

function Get-MiracleBootLogFile {
    <#
    .SYNOPSIS
        Returns path to current log file.
    #>
    if (-not $script:MiracleBootLogConfig.CurrentLogFile) {
        $null = Initialize-ErrorLogging
    }
    return $script:MiracleBootLogConfig.CurrentLogFile
}

function Write-ErrorLog {
    <#
    .SYNOPSIS
        Convenience function for logging errors.
    #>
    param(
        [string]$Message,
        [string]$Location = "Unknown",
        [hashtable]$Data = @{},
        [Exception]$Exception = $null
    )
    
    if ($Exception) {
        $Message += " | Exception: $($Exception.Message)"
        if ($Exception.StackTrace) {
            $Data.StackTrace = $Exception.StackTrace
        }
    }
    
    Add-MiracleBootLog -Level "ERROR" -Message $Message -Location $Location -Data $Data
}

function Write-WarningLog {
    <#
    .SYNOPSIS
        Convenience function for logging warnings.
    #>
    param(
        [string]$Message,
        [string]$Location = "Unknown",
        [hashtable]$Data = @{}
    )
    
    Add-MiracleBootLog -Level "WARNING" -Message $Message -Location $Location -Data $Data
}

# Override Write-Warning to automatically log
# CRITICAL: Prevent call depth overflow by checking recursion BEFORE calling original
$originalWriteWarning = Get-Command Write-Warning
$script:WriteWarningInProgress = $false
$script:WriteWarningCallCount = 0
function Write-Warning {
    <#
    .SYNOPSIS
        Enhanced Write-Warning that also logs to file.
    #>
    param([string]$Message)
    
    # CRITICAL: Prevent recursion by checking flag FIRST, before any operations
    # If we're already in a Write-Warning call, skip everything to prevent infinite recursion
    if ($script:WriteWarningInProgress) {
        # Just output to console directly to avoid recursion
        [Console]::Error.WriteLine("WARNING: $Message")
        return
    }
    
    # CRITICAL: Check call count to prevent deep recursion chains
    if ($script:WriteWarningCallCount -gt 10) {
        # Too many nested calls, skip logging to prevent overflow
        [Console]::Error.WriteLine("WARNING: $Message")
        return
    }
    
    # Increment call counter and set flag BEFORE calling original
    $script:WriteWarningCallCount++
    $script:WriteWarningInProgress = $true
    
    try {
        # Call original Write-Warning (this may trigger other logging, but we're protected by the flag)
        & $originalWriteWarning -Message $Message -ErrorAction SilentlyContinue
        
        # Also log it (with minimal call stack usage to prevent overflow)
        # Skip call stack retrieval entirely to prevent call depth overflow
        # Just log with "Write-Warning" location to avoid Get-PSCallStack overhead
        # Use -ErrorAction SilentlyContinue to prevent any errors from propagating
        Add-MiracleBootLog -Level "WARNING" -Message $Message -Location "Write-Warning" -NoConsole -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if logging causes issues (prevents recursion)
        # Don't call Write-Warning here as we're already in Write-Warning
    } finally {
        # Always clear the flag and decrement counter
        $script:WriteWarningInProgress = $false
        if ($script:WriteWarningCallCount -gt 0) {
            $script:WriteWarningCallCount--
        }
    }
}

# Initialize on module load
$null = Initialize-ErrorLogging
