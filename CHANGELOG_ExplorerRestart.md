# Changelog - Windows Explorer Restart Feature

## Date: January 7, 2026

## Changes Made

### 1. Fixed Emoji Encoding Issue
- **Problem**: Emoji characters (🔥, 📋) in GUI code were causing syntax errors due to encoding issues
- **Solution**: Removed emoji characters and replaced with plain text
- **Files Modified**:
  - `Helper/WinRepairGUI.ps1` (lines 2686, 2702)

### 2. Added Windows Explorer Restart Feature

#### Core Function (`Helper/WinRepairCore.ps1`)
- **New Function**: `Restart-WindowsExplorer`
  - Safely stops and restarts Windows Explorer process
  - Checks if Explorer is running before attempting restart
  - Verifies Explorer restarted successfully
  - Provides detailed status messages
  - Handles errors gracefully

#### GUI Integration (`Helper/WinRepairGUI.ps1`)
- **New Button**: "Restart Explorer" in utility toolbar
  - Located next to "Disk Management" button
  - Tooltip: "Restart Windows Explorer if it crashed"
  - Shows success/error message boxes
  - Integrated with existing utility button pattern

#### TUI Integration (`Helper/WinRepairTUI.ps1`)
- **New Menu Option**: "8) Restart Windows Explorer" in Utilities Menu
  - Accessible from main menu → K (Utilities Menu) → 8
  - Provides color-coded feedback
  - Pauses for user confirmation

#### Utilities Menu Integration (`Helper/WinRepairCore.ps1`)
- **Updated**: `Start-UtilitiesMenu` function
  - Added "RestartExplorer" to ValidateSet
  - Integrated with existing utility menu system

## Usage

### GUI Mode
1. Launch Miracle Boot
2. Click "Restart Explorer" button in the utility toolbar
3. Confirmation message will appear

### TUI Mode
1. Launch Miracle Boot
2. Select "K) Utilities Menu"
3. Select "8) Restart Windows Explorer"
4. Follow on-screen prompts

## Function Details

### `Restart-WindowsExplorer`

**Purpose**: Restarts Windows Explorer when it has crashed or is not responding.

**When to Use**:
- Desktop/taskbar is missing
- Explorer is frozen
- Desktop icons not displaying
- Taskbar not responding

**Returns**:
```powershell
@{
    Success = $true/false
    Message = "Status message"
    WasRunning = $true/false
    Restarted = $true/false
}
```

**Example**:
```powershell
$result = Restart-WindowsExplorer
if ($result.Success) {
    Write-Host $result.Message
}
```

## Testing

✅ Syntax validation passed
✅ GUI launch test passed
✅ All modules load correctly
✅ No Export-ModuleMember errors

## Notes

- Function requires appropriate permissions to stop/start processes
- Works in FullOS (Windows 10/11 desktop)
- May not work in WinRE/WinPE (Explorer not available)
- Safe to use - will not cause data loss

