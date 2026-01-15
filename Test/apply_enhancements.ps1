# ENHANCEMENT: Add comprehensive logging throughout the initialization

# After the ExecutionPolicy line, add:
# 1. Load ErrorLogging framework
# 2. Load XamlDefense framework  
# 3. Add null-checks before every module load

# Find the line with "Load error logging framework" - it should already be there from our first edit
# If not, we need to add it

$content = Get-Content "MiracleBoot.ps1" -Raw

# Check if ErrorLogging is already loaded
if ($content -notmatch "ErrorLogging.ps1") {
    Write-Host "ERROR: ErrorLogging not integrated! Aborting patch." -ForegroundColor Red
    exit 1
}

# Check if XamlDefense is loaded - if not, add it
if ($content -notmatch "XamlDefense.ps1") {
    Write-Host "Adding XamlDefense.ps1 to initialization..." -ForegroundColor Green
    
    # Find a good place to load XamlDefense - right after ErrorLogging
    $pattern = '. "\$PSScriptRoot\\Helper\\ErrorLogging.ps1"'
    $replacement = '. "\$PSScriptRoot\\Helper\\ErrorLogging.ps1"
. "\$PSScriptRoot\\Helper\\XamlDefense.ps1" -ErrorAction SilentlyContinue'
    
    $newContent = $content -replace $pattern, $replacement
    $newContent | Out-File "MiracleBoot.ps1" -Encoding UTF8 -Force
    Write-Host "XamlDefense.ps1 added to initialization" -ForegroundColor Green
}
