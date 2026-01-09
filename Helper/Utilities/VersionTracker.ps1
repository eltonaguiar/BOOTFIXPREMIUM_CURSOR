# Version Tracker for Miracle Boot
# Creates backup branches every 20 commits with version numbers

param(
    [switch]$ForceBackup
)

$ErrorActionPreference = 'Stop'

# Get current commit count
$commitCount = git rev-list --count HEAD
$currentBranch = git rev-parse --abbrev-ref HEAD

# Calculate which version milestone we're at (every 20 commits)
# Version numbers: v7.1 at commit 20, v7.2 at commit 40, etc.
$lastBackupCommit = [math]::Floor($commitCount / 20) * 20
$nextBackupAt = $lastBackupCommit + 20
$versionNumber = [math]::Floor($commitCount / 20)

# If we're at exactly a milestone (20, 40, 60, etc.), use that version
if ($commitCount -gt 0 -and $commitCount % 20 -eq 0) {
    $versionNumber = ($commitCount / 20)
    $shouldCreateBackup = $true
} else {
    $shouldCreateBackup = $false
}

Write-Host "Current Status:" -ForegroundColor Cyan
Write-Host "  Branch: $currentBranch" -ForegroundColor Gray
Write-Host "  Total Commits: $commitCount" -ForegroundColor Gray
Write-Host "  Last Backup Version: v7.$versionNumber" -ForegroundColor Gray
Write-Host "  Next Backup at Commit: $nextBackupAt" -ForegroundColor Gray
Write-Host ""

# Check if we need to create a backup branch
if ($shouldCreateBackup -or $ForceBackup) {
    if ($ForceBackup) {
        $backupVersion = $versionNumber + 1
    } else {
        $backupVersion = $versionNumber
    }
    $backupBranchName = "backup-v7.$backupVersion"
    
    # Check if backup branch already exists
    $branchExists = git branch -a | Select-String -Pattern $backupBranchName
    
    if (-not $branchExists -or $ForceBackup) {
        Write-Host "Creating backup branch: $backupBranchName" -ForegroundColor Yellow
        
        # Create and push backup branch
        git branch $backupBranchName
        git push origin $backupBranchName
        
        Write-Host "Backup branch created successfully!" -ForegroundColor Green
        Write-Host "  Branch: $backupBranchName" -ForegroundColor Gray
        Write-Host "  Commit: $(git rev-parse --short HEAD)" -ForegroundColor Gray
    } else {
        Write-Host "Backup branch $backupBranchName already exists. Use -ForceBackup to recreate." -ForegroundColor Yellow
    }
} else {
    $commitsUntilBackup = $nextBackupAt - $commitCount
    Write-Host "No backup needed yet. $commitsUntilBackup more commit(s) until next backup." -ForegroundColor Green
}

# List all backup branches
Write-Host ""
Write-Host "Existing Backup Branches:" -ForegroundColor Cyan
$backupBranches = git branch -a | Select-String -Pattern "backup-v7\."
if ($backupBranches) {
    foreach ($branch in $backupBranches) {
        Write-Host "  $($branch.ToString().Trim())" -ForegroundColor Gray
    }
} else {
    Write-Host "  No backup branches found." -ForegroundColor Gray
}

