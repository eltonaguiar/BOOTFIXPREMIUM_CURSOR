# REORGANIZATION_EXECUTION_SCRIPT.ps1
# Executes the reorganization plan
# RUN WITH CAUTION - Review plan first!

param(
    [switch]$DryRun = $false,
    [switch]$SkipModularization = $false
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "REORGANIZATION EXECUTION SCRIPT" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN MODE - No files will be moved" -ForegroundColor Yellow
    Write-Host ""
}

# Phase 1: Create folder structure
Write-Host "PHASE 1: Creating folder structure..." -ForegroundColor Yellow

$folders = @(
    "DOCUMENTATION\Status",
    "DOCUMENTATION\Analysis",
    "DOCUMENTATION\Plans",
    "DOCUMENTATION\Features",
    "DOCUMENTATION\Changelogs",
    "DOCUMENTATION\Guides",
    "Test\Unit",
    "Test\Integration",
    "Test\GUI",
    "Test\Production",
    "Test\Validation",
    "Test\Utilities",
    "Test\SuperTest",
    "Test\Documentation",
    "Test\Logs",
    "Helper\GUI",
    "Helper\Core",
    "Helper\TUI",
    "Helper\Utilities",
    "Logs"
)

foreach ($folder in $folders) {
    $fullPath = Join-Path $scriptRoot $folder
    if (-not (Test-Path $fullPath)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        }
        Write-Host "  Created: $folder" -ForegroundColor Green
    } else {
        Write-Host "  Exists: $folder" -ForegroundColor Gray
    }
}

Write-Host ""

# Phase 2: Move documentation
Write-Host "PHASE 2: Moving documentation..." -ForegroundColor Yellow

$docMoves = @{
    "DOCUMENTATION\Status" = @(
        "CURRENT_STATUS.md",
        "FINAL_STATUS.md",
        "PRODUCTION_READY_FINAL.md",
        "PRODUCTION_READY_SUMMARY.md",
        "GITHUB_READY.md"
    )
    "DOCUMENTATION\Analysis" = @(
        "CODE_QUALITY_ANALYSIS_AND_PLAN.md",
        "CODE_FIXES_SUMMARY.md",
        "FIXES_APPLIED_SUMMARY.md",
        "FIXES_APPLIED_SYNTAX_AND_VALIDATION.md",
        "ROOT_CAUSE_ANALYSIS_SYNTAX_ERRORS.md",
        "ROOT_PLAN_CODE_VALIDATION.md",
        "SYNTAX_ERROR_NOTES.md",
        "UI_LAUNCH_RELIABILITY_ANALYSIS.md",
        "HARDENED_TEST_PROCEDURES.md"
    )
    "DOCUMENTATION\Plans" = @(
        "IMPLEMENTATION_PLAN_v7.3.0.md",
        "MERGE_PLAN.md",
        "REPAIR_INSTALL_READINESS_PLAN.md",
        "REORGANIZATION_SUMMARY.md"
    )
    "DOCUMENTATION\Features" = @(
        "ADVANCED_DRIVER_FEATURES_2025.md",
        "FUTURE_ENHANCEMENTS.md",
        "RECOMMENDED_TOOLS_FEATURE.md"
    )
    "DOCUMENTATION\Changelogs" = @(
        "CHANGELOG_v7.3.0.md",
        "CHANGELOG_ExplorerRestart.md"
    )
    "DOCUMENTATION\Guides" = @(
        "TOOLS_USER_GUIDE.md"
    )
}

foreach ($targetFolder in $docMoves.Keys) {
    $files = $docMoves[$targetFolder]
    foreach ($file in $files) {
        $source = Join-Path $scriptRoot $file
        $dest = Join-Path (Join-Path $scriptRoot $targetFolder) $file
        
        if (Test-Path $source) {
            if (-not $DryRun) {
                Move-Item -Path $source -Destination $dest -Force
            }
            Write-Host "  Moved: $file -> $targetFolder" -ForegroundColor Green
        } else {
            Write-Host "  Not found: $file" -ForegroundColor Yellow
        }
    }
}

# Move remaining docs
$remainingDocs = @(
    "COMMIT_README.md",
    "README_GITHUB_UPLOAD.md",
    "PROJECT_STRUCTURE.md",
    "QA_CRITICAL_FIXES_SUMMARY.md",
    "QA_ENHANCEMENTS_LIFE_OR_DEATH.md"
)

foreach ($doc in $remainingDocs) {
    $source = Join-Path $scriptRoot $doc
    if (Test-Path $source) {
        $dest = Join-Path (Join-Path $scriptRoot "DOCUMENTATION") $doc
        if (-not $DryRun) {
            Move-Item -Path $source -Destination $dest -Force
        }
        Write-Host "  Moved: $doc -> DOCUMENTATION" -ForegroundColor Green
    }
}

Write-Host ""

# Phase 3: Move test files
Write-Host "PHASE 3: Organizing test files..." -ForegroundColor Yellow

$testMoves = @{
    "Test\Unit" = @(
        "Test-LogAnalysis.ps1",
        "Test-NetworkFunctions.ps1",
        "Test-SafeFunctions.ps1",
        "Test-RuntimeModuleLoad.ps1"
    )
    "Test\Integration" = @(
        "Test-FullLoad.ps1",
        "Test-CompleteCodebase.ps1",
        "Test-MiracleBoot.ps1",
        "Test-PostChangeValidation.ps1"
    )
    "Test\GUI" = @(
        "Test-ActualGUILaunch.ps1",
        "Test-GUILaunch.ps1",
        "Test-GUILaunchDirect.ps1",
        "Test-GUILaunchVerification.ps1",
        "Test-RealGUILaunch.ps1",
        "Test-HardenedUILaunch.ps1",
        "Test-UILaunchReliability.ps1",
        "Test-BrutalHonesty.ps1",
        "VERIFY_GUI_WORKS.ps1"
    )
    "Test\Production" = @(
        "Test-ProductionReady.ps1",
        "Test-ProductionReadyElevated.ps1",
        "Test-FinalProductionCheck.ps1",
        "Test-PreLaunchValidation.ps1"
    )
    "Test\Validation" = @(
        "Validate-Syntax.ps1",
        "Check-Syntax.ps1",
        "Test-LogAnalysisLoad.ps1"
    )
    "Test\Utilities" = @(
        "Read-TestOutput.ps1",
        "Analyze-FileSizes.ps1",
        "test_new_features.ps1"
    )
    "Test\SuperTest" = @(
        "SuperTest-MiracleBoot.ps1"
    )
    "Test\Documentation" = @(
        "TESTING_SUMMARY.md",
        "POST_CHANGE_VALIDATION_README.md"
    )
    "Test\Logs" = @(
        "PostChangeValidation_*.log"
    )
}

foreach ($targetFolder in $testMoves.Keys) {
    $files = $testMoves[$targetFolder]
    foreach ($file in $files) {
        $source = Join-Path (Join-Path $scriptRoot "Test") $file
        if ($file -like "*.*") {
            # Handle wildcards
            $found = Get-ChildItem -Path (Join-Path $scriptRoot "Test") -Filter $file -ErrorAction SilentlyContinue
            foreach ($f in $found) {
                $dest = Join-Path (Join-Path $scriptRoot $targetFolder) $f.Name
                if (-not $DryRun) {
                    Move-Item -Path $f.FullName -Destination $dest -Force
                }
                Write-Host "  Moved: $($f.Name) -> $targetFolder" -ForegroundColor Green
            }
        } else {
            if (Test-Path $source) {
                $dest = Join-Path (Join-Path $scriptRoot $targetFolder) $file
                if (-not $DryRun) {
                    Move-Item -Path $source -Destination $dest -Force
                }
                Write-Host "  Moved: $file -> $targetFolder" -ForegroundColor Green
            }
        }
    }
}

# Move SuperTestLogs folder
$superTestLogs = Join-Path $scriptRoot "Test\SuperTestLogs"
if (Test-Path $superTestLogs) {
    $dest = Join-Path $scriptRoot "Test\SuperTest\SuperTestLogs"
    if (-not $DryRun) {
        Move-Item -Path $superTestLogs -Destination $dest -Force
    }
    Write-Host "  Moved: SuperTestLogs -> Test\SuperTest" -ForegroundColor Green
}

# Move SUPERTEST_README.md
$superTestReadme = Join-Path $scriptRoot "Test\SUPERTEST_README.md"
if (Test-Path $superTestReadme) {
    $dest = Join-Path $scriptRoot "Test\SuperTest\SUPERTEST_README.md"
    if (-not $DryRun) {
        Move-Item -Path $superTestReadme -Destination $dest -Force
    }
    Write-Host "  Moved: SUPERTEST_README.md -> Test\SuperTest" -ForegroundColor Green
}

Write-Host ""

# Phase 4: Move Helper Scripts
Write-Host "PHASE 4: Consolidating Helper Scripts..." -ForegroundColor Yellow

$helperScripts = @(
    "Helper Scripts\FixWinRepairCore.ps1",
    "Helper Scripts\VersionTracker.ps1"
)

foreach ($script in $helperScripts) {
    $source = Join-Path $scriptRoot $script
    if (Test-Path $source) {
        $dest = Join-Path (Join-Path $scriptRoot "Helper\Utilities") (Split-Path $script -Leaf)
        if (-not $DryRun) {
            Move-Item -Path $source -Destination $dest -Force
        }
        Write-Host "  Moved: $(Split-Path $script -Leaf) -> Helper\Utilities" -ForegroundColor Green
    }
}

# Move Fix-NullFindNameCalls.ps1
$fixNull = Join-Path $scriptRoot "Helper\Fix-NullFindNameCalls.ps1"
if (Test-Path $fixNull) {
    $dest = Join-Path $scriptRoot "Helper\Utilities\Fix-NullFindNameCalls.ps1"
    if (-not $DryRun) {
        Move-Item -Path $fixNull -Destination $dest -Force
    }
    Write-Host "  Moved: Fix-NullFindNameCalls.ps1 -> Helper\Utilities" -ForegroundColor Green
}

Write-Host ""

# Phase 5: Move log files
Write-Host "PHASE 5: Moving log files..." -ForegroundColor Yellow

$logFiles = @(
    "MiracleBoot_GUI_Error.log"
)

foreach ($log in $logFiles) {
    $source = Join-Path $scriptRoot $log
    if (Test-Path $source) {
        $dest = Join-Path (Join-Path $scriptRoot "Logs") $log
        if (-not $DryRun) {
            Move-Item -Path $source -Destination $dest -Force
        }
        Write-Host "  Moved: $log -> Logs" -ForegroundColor Green
    }
}

Write-Host ""

# Summary
Write-Host "=" * 80 -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "DRY RUN COMPLETE - No files were moved" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To execute for real, run:" -ForegroundColor Cyan
    Write-Host "  .\REORGANIZATION_EXECUTION_SCRIPT.ps1" -ForegroundColor White
} else {
    Write-Host "REORGANIZATION COMPLETE" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. Review moved files" -ForegroundColor White
    Write-Host "  2. Update path references in scripts" -ForegroundColor White
    Write-Host "  3. Modularize large scripts (if approved)" -ForegroundColor White
    Write-Host "  4. Test that everything still works" -ForegroundColor White
}

Write-Host ""

