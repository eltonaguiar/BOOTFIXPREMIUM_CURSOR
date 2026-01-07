# Repair-Install Readiness Engine - Implementation Plan

## Problem Statement

**Current State:**
- ✅ Boot repair works (bootrec, BCD, EFI)
- ✅ OS integrity repair works (SFC, DISM)
- ⚠️ **MISSING**: Guarantee that Windows is eligible for in-place upgrade (setup.exe with "Keep apps + files")

**The Gap:**
Windows Setup blocks repair installs if ANY of these are broken:
- CBS store state = dirty
- Edition mismatch (Pro vs Home vs Enterprise)
- Build family mismatch (26200 vs 26100 etc.)
- Missing WinRE metadata
- Broken SetupPlatform registry keys
- Offline servicing stack mismatch
- RebootPending flags

## Solution: EnsureRepairInstallReady Module

### Core Functions Required

1. **Test-RepairInstallEligibility**
   - Comprehensive pre-flight check
   - Returns detailed eligibility report
   - Identifies specific blockers

2. **Clear-CBSBlockers**
   - Clear RebootPending
   - Clear PendingFileRenameOperations
   - Validate component store
   - Force DISM /resetbase if needed

3. **Normalize-SetupState**
   - Fix EditionID mismatches
   - Fix InstallationType
   - Normalize registry keys
   - Validate build compatibility

4. **Repair-WinREForSetup**
   - Re-register WinRE
   - Ensure ReAgent.xml is valid
   - Repair BCD {bootloadersettings}
   - Validate WinRE partition

5. **Test-SetupDryRun**
   - Pre-validate setup.exe outcome
   - Detect edition mismatch early
   - Detect build family mismatch early
   - Warn user BEFORE wasting time

6. **Start-RepairInstallReadiness**
   - Master orchestrator
   - Runs all checks and fixes
   - Returns readiness score (0-100%)
   - Provides actionable report

## Implementation Priority

1. **Phase 1: Detection** (Test-RepairInstallEligibility)
2. **Phase 2: CBS Normalization** (Clear-CBSBlockers)
3. **Phase 3: Setup State** (Normalize-SetupState)
4. **Phase 4: WinRE Repair** (Repair-WinREForSetup)
5. **Phase 5: Validation** (Test-SetupDryRun)
6. **Phase 6: Orchestration** (Start-RepairInstallReadiness)

## Integration Points

- Add to WinRepairCore.ps1
- Add TUI menu option: "Ensure Repair-Install Ready"
- Add GUI button/tab: "Repair-Install Readiness"
- Integrate with existing Get-InPlaceUpgradeReadiness (enhance it)

## Success Criteria

✅ System can run: `setup.exe /auto upgrade /quiet`
✅ Setup.exe accepts "Keep apps + files" option
✅ No CBS blockers remain
✅ Edition/build compatibility verified
✅ WinRE properly registered

---

**Status**: Ready for Implementation
**Priority**: CRITICAL
**Estimated Complexity**: High
**Estimated Impact**: Very High

