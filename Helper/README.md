# Helper Scripts

## VersionTracker.ps1

Automatically creates backup branches every 20 commits with version numbers.

**Usage:**
```powershell
# Check status and create backup if at milestone (commit 20, 40, 60, etc.)
.\Helper\VersionTracker.ps1

# Force create a backup branch now
.\Helper\VersionTracker.ps1 -ForceBackup
```

**How it works:**
- Monitors total commit count
- Creates backup branch `backup-v7.X` at commits 20, 40, 60, 80, etc.
- Version numbers increment: v7.1 (commit 20), v7.2 (commit 40), v7.3 (commit 60), etc.

## EnsureMain.ps1

Ensures main branch is up to date and handles remote synchronization.

**Usage:**
```powershell
# Check and sync main branch
.\Helper\EnsureMain.ps1

# Force push local main to remote (overwrites remote)
.\Helper\EnsureMain.ps1 -ForcePush

# Check status and create backup if needed
.\Helper\EnsureMain.ps1 -CreateBackup
```

**Features:**
- Verifies you're on main branch
- Fetches latest from remote
- Compares local vs remote commits
- Pushes local changes or warns about remote changes
- Optionally creates backup branches

## Workflow

**After making commits:**
```powershell
# 1. Ensure main is up to date
.\Helper\EnsureMain.ps1

# 2. Check if backup is needed (every 20 commits)
.\Helper\VersionTracker.ps1
```

**Or combine both:**
```powershell
.\Helper\EnsureMain.ps1 -CreateBackup
```

