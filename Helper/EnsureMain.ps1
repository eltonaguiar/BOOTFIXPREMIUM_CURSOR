# Ensure Main Branch Script
# Ensures main branch is up to date and creates backup branches every 20 commits

param(
    [switch]$ForcePush,
    [switch]$CreateBackup
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Miracle Boot - Main Branch Manager" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get current branch
$currentBranch = git rev-parse --abbrev-ref HEAD

if ($currentBranch -ne "main") {
    Write-Host "WARNING: Not on main branch. Current branch: $currentBranch" -ForegroundColor Yellow
    $switch = Read-Host "Switch to main branch? (Y/N)"
    if ($switch -eq 'Y' -or $switch -eq 'y') {
        git checkout main
        $currentBranch = "main"
    } else {
        Write-Host "Aborting. Please switch to main branch first." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Current Branch: $currentBranch" -ForegroundColor Green
Write-Host ""

# Fetch latest from remote
Write-Host "Fetching latest from remote..." -ForegroundColor Cyan
git fetch origin

# Check if local main is ahead or behind
$localCommits = git rev-list --count HEAD
$remoteCommits = git rev-list --count origin/main 2>$null

if ($remoteCommits) {
    Write-Host "Local commits: $localCommits" -ForegroundColor Gray
    Write-Host "Remote commits: $remoteCommits" -ForegroundColor Gray
    
    if ($localCommits -lt $remoteCommits) {
        Write-Host ""
        Write-Host "WARNING: Remote main has more commits than local." -ForegroundColor Yellow
        Write-Host "Remote has $($remoteCommits - $localCommits) additional commit(s)." -ForegroundColor Yellow
        
        if ($ForcePush) {
            Write-Host "Force pushing local main to remote (overwriting remote)..." -ForegroundColor Yellow
            git push origin main --force
        } else {
            Write-Host "Use -ForcePush to overwrite remote with local changes." -ForegroundColor Yellow
            Write-Host "Or pull remote changes first: git pull origin main" -ForegroundColor Yellow
        }
    } elseif ($localCommits -gt $remoteCommits) {
        Write-Host ""
        Write-Host "Local main is ahead of remote. Pushing..." -ForegroundColor Green
        git push origin main
    } else {
        Write-Host "Local and remote are in sync." -ForegroundColor Green
    }
} else {
    Write-Host "No remote tracking set. Pushing to origin/main..." -ForegroundColor Yellow
    git push -u origin main
}

Write-Host ""

# Check if we need to create a backup branch
if ($CreateBackup) {
    Write-Host "Checking for backup branch creation..." -ForegroundColor Cyan
    & "$PSScriptRoot\VersionTracker.ps1" -ForceBackup
} else {
    & "$PSScriptRoot\VersionTracker.ps1"
}

Write-Host ""
Write-Host "Main branch management complete!" -ForegroundColor Green

