# MiracleBoot Centralized Logging System

## Overview

The MiracleBoot logging system captures **ALL errors and warnings** automatically, with automatic cleanup of old logs. When users report issues, you can simply say "fix the errors" and the system will have all the information needed.

## Features

### ✅ Automatic Error/Warning Capture
- All `Write-Warning` calls are automatically logged
- All `Write-Error` calls are automatically logged
- Custom `Add-MiracleBootLog` for structured logging
- Convenience functions: `Write-ErrorLog`, `Write-WarningLog`

### ✅ Automatic Log Cleanup
- Old logs (older than 7 days) are automatically deleted when new logs are created
- Prevents log directory from growing indefinitely
- Configurable retention period

### ✅ Log Rotation
- Logs rotate when they exceed 10MB
- Timestamped rotated logs are preserved
- Current log always available

### ✅ Dual Output
- Logs written to file: `LOGS\ERROR_LOGS\MiracleBoot_YYYY-MM-DD.log`
- Also displayed in console (unless `-NoConsole` flag used)
- In-memory buffer for quick access (last 1000 entries)

## Usage

### Basic Logging

```powershell
# Log an error
Add-MiracleBootLog -Level "ERROR" -Message "Something went wrong" -Location "MyFunction"

# Log a warning
Add-MiracleBootLog -Level "WARNING" -Message "This might be an issue" -Location "MyFunction"

# Log info (silent - no console output)
Add-MiracleBootLog -Level "INFO" -Message "Operation completed" -Location "MyFunction" -NoConsole
```

### Convenience Functions

```powershell
# Log error with exception
Write-ErrorLog -Message "Failed to load module" -Exception $_.Exception -Location "LoadModule"

# Log warning
Write-WarningLog -Message "Control not found" -Location "Get-Control" -Data @{ControlName="BtnTest"}
```

### Automatic Capture

All `Write-Warning` calls are automatically captured:

```powershell
Write-Warning "Control 'BtnTest' not found in XAML"
# This is automatically logged to file, even without explicit logging call
```

## Log File Location

```
MiracleBoot_v7_1_1/
└── LOGS/
    └── ERROR_LOGS/
        ├── MiracleBoot_2026-01-07.log  (current)
        ├── MiracleBoot_2026-01-06.log  (yesterday)
        └── MiracleBoot_2026-01-05.log  (2 days ago)
```

Old logs (7+ days) are automatically deleted when new logs are created.

## Log Format

```
[2026-01-07 14:23:45.123] [WARNING] [PID:12345] [Get-Control@Helper\WinRepairGUI.ps1:661] Control 'BtnTest' not found in XAML | Data: {"ControlName":"BtnTest"}
```

Format: `[Timestamp] [Level] [PID] [Location] Message | Data: {...}`

## Getting Log Summary

```powershell
# Get summary of all errors/warnings
$summary = Get-MiracleBootLogSummary
Write-Host "Errors: $($summary.TotalErrors)"
Write-Host "Warnings: $($summary.TotalWarnings)"

# Get current log file path
$logFile = Get-MiracleBootLogFile
```

## Integration

### MiracleBoot.ps1
- Logging initialized at startup
- All errors during environment detection are logged
- Module loading errors are logged

### WinRepairGUI.ps1
- Logging initialized when GUI module loads
- All control lookup failures are logged (with `-Silent` flag for optional controls)
- All event handler errors are logged

### Get-Control Function
- Uses `-Silent` flag for optional controls (no warning logged)
- Logs warnings for required controls that are missing
- All logged to file automatically

## Configuration

Edit `Helper\ErrorLogging.ps1`:

```powershell
$script:MiracleBootLogConfig = @{
    LogRetentionDays = 7   # Keep logs for 7 days
    MaxLogSizeMB = 10      # Rotate if log exceeds 10MB
}
```

## Troubleshooting

### "Logs directory not created"
- Check write permissions
- Falls back to `$env:TEMP\MiracleBoot_LOGS` if primary location fails

### "Logs not being written"
- Check disk space
- Check file permissions
- Check if logging module loaded successfully

### "Too many logs"
- Adjust `LogRetentionDays` in configuration
- Manually delete old logs from `LOGS\ERROR_LOGS\`

## Example: Fixing Errors

When user says "fix the errors":

1. **Get log file**:
   ```powershell
   $logFile = Get-MiracleBootLogFile
   ```

2. **Read errors**:
   ```powershell
   $errors = Get-Content $logFile | Select-String "\[ERROR\]"
   ```

3. **Get summary**:
   ```powershell
   $summary = Get-MiracleBootLogSummary
   $summary.Errors | ForEach-Object {
       Write-Host "$($_.Location): $($_.Message)"
   }
   ```

4. **Fix issues** based on logged errors

## Best Practices

1. **Use appropriate log levels**:
   - `ERROR`: Something broke, needs fixing
   - `WARNING`: Potential issue, might need attention
   - `INFO`: Normal operation, for debugging
   - `DEBUG`: Verbose debugging info

2. **Include location**:
   - Always specify `-Location` parameter
   - Helps identify where error occurred

3. **Include context**:
   - Use `-Data` parameter for structured data
   - Helps with debugging

4. **Use `-Silent` for optional controls**:
   - Prevents log spam from missing optional UI elements
   - Still logs to file, just doesn't show in console

## Summary

✅ **All errors/warnings automatically logged**  
✅ **Old logs automatically cleaned up**  
✅ **Log rotation for large files**  
✅ **Easy access via `Get-MiracleBootLogSummary`**  
✅ **User can just say "fix the errors" and you have everything**

