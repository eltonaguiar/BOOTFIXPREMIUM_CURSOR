# Quick fix script for WinRepairCore.ps1
$targetFile = "C:\Users\zerou\Downloads\MiracleBoot_v7_1\WinRepairCore.ps1"

if (Test-Path $targetFile) {
    $content = Get-Content $targetFile -Raw
    
    # Fix the problematic line
    $content = $content -replace '\$imagePath = "\$\{WindowsDrive\}:\\"', '$imagePath = "$($WindowsDrive):"'
    $content = $content -replace '\$imagePath = "\$\{WindowsDrive\}:\\\\"', '$imagePath = "$($WindowsDrive):"'
    
    # Also ensure the function is correct
    if ($content -notmatch 'function Inject-Drivers-Offline') {
        Write-Host "Warning: Inject-Drivers-Offline function not found" -ForegroundColor Yellow
    } else {
        # Replace the entire function if it has the old syntax
        $oldFunction = '(?s)function Inject-Drivers-Offline\s*\{[^}]*\$imagePath\s*=\s*"\$\{WindowsDrive\}:[^"]*"[^}]*\}'
        $newFunction = @'
function Inject-Drivers-Offline {
    param($WindowsDrive,$DriverPath)
    # Construct image path properly - DISM expects format like C:\
    # Use subexpression to avoid parsing issues with colon
    $imagePath = "$($WindowsDrive):"
    dism /Image:"$imagePath" /Add-Driver /Driver:"$DriverPath" /Recurse /ForceUnsigned
}
'@
        if ($content -match $oldFunction) {
            $content = $content -replace $oldFunction, $newFunction
            Write-Host "Function replaced" -ForegroundColor Green
        }
    }
    
    Set-Content $targetFile -Value $content -NoNewline
    Write-Host "File fixed: $targetFile" -ForegroundColor Green
} else {
    Write-Host "File not found: $targetFile" -ForegroundColor Red
    Write-Host "Please update the path in this script or copy the file manually." -ForegroundColor Yellow
}

