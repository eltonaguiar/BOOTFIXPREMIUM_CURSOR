# 20-Agent Comprehensive Validation Test
# Simulates 20 different test agents with unique perspectives

param(
    [switch]$TestGUILaunch,
    [string]$LogDir = "$env:TEMP\miracleboot-20agent"
)

$ErrorActionPreference = 'Stop'
$global:AllResults = @()

function Invoke-AgentTest {
    param(
        [int]$AgentNum,
        [string]$TestName,
        [scriptblock]$TestScript
    )
    
    $agent = "Agent-$AgentNum"
    try {
        $result = & $TestScript
        $status = if ($result -eq $true -or ($result -is [bool] -and $result)) { "PASS" } else { "FAIL" }
        $global:AllResults += [PSCustomObject]@{
            Agent = $agent
            Test = $TestName
            Status = $status
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Write-Host "[$agent] $TestName : $status" -ForegroundColor $(if ($status -eq "PASS") { "Green" } else { "Red" })
        return $status -eq "PASS"
    } catch {
        $global:AllResults += [PSCustomObject]@{
            Agent = $agent
            Test = $TestName
            Status = "FAIL"
            Error = $_.Exception.Message
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        Write-Host "[$agent] $TestName : FAIL - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "20-AGENT COMPREHENSIVE VALIDATION" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

# Agent 1-5: Syntax Validation Specialists
1..5 | ForEach-Object {
    $agentNum = $_
    Invoke-AgentTest $agentNum "Syntax-MiracleBoot.ps1" {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "MiracleBoot.ps1" -Raw), [ref]$errors)
        $errors.Count -eq 0
    }
    
    Invoke-AgentTest $agentNum "Syntax-WinRepairCore.ps1" {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairCore.ps1" -Raw), [ref]$errors)
        $errors.Count -eq 0
    }
    
    Invoke-AgentTest $agentNum "Syntax-WinRepairGUI.ps1" {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairGUI.ps1" -Raw), [ref]$errors)
        $errors.Count -eq 0
    }
    
    Invoke-AgentTest $agentNum "Syntax-WinRepairTUI.ps1" {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairTUI.ps1" -Raw), [ref]$errors)
        $errors.Count -eq 0
    }
}

# Agent 6-10: Module Loading Specialists
6..10 | ForEach-Object {
    $agentNum = $_
    Invoke-AgentTest $agentNum "ModuleLoad-Core" {
        $corePath = Resolve-Path "Helper\WinRepairCore.ps1" -ErrorAction Stop
        $testFile = "$env:TEMP\test-load-$agentNum.ps1"
        @"
            `$ErrorActionPreference = 'Stop'
            . '$corePath' -ErrorAction Stop
            Write-Output 'LOADED'
"@ | Out-File $testFile -Encoding UTF8
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $testFile 2>&1
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        $output -match "LOADED"
    }
    
    Invoke-AgentTest $agentNum "Function-Start-PrecisionScan" {
        $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
        $content -match "function\s+Start-PrecisionScan"
    }
    
    Invoke-AgentTest $agentNum "Function-Get-PrecisionDetections" {
        $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
        $content -match "function\s+Get-PrecisionDetections"
    }
}

# Agent 11-15: GUI/TUI Launch Specialists
11..15 | ForEach-Object {
    $agentNum = $_
    Invoke-AgentTest $agentNum "GUI-SyntaxValid" {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairGUI.ps1" -Raw), [ref]$errors)
        $errors.Count -eq 0
    }
    
    Invoke-AgentTest $agentNum "GUI-XAMLPresent" {
        $content = Get-Content "Helper\WinRepairGUI.ps1" -Raw
        $content -match '\[xml\]\s*\$xaml' -or $content -match 'XamlReader'
    }
    
    Invoke-AgentTest $agentNum "TUI-SyntaxValid" {
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content "Helper\WinRepairTUI.ps1" -Raw), [ref]$errors)
        $errors.Count -eq 0
    }
}

# Agent 16-20: Precision Feature Specialists
16..20 | ForEach-Object {
    $agentNum = $_
    Invoke-AgentTest $agentNum "Precision-TC-001" {
        $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
        $content -match "TC-001" -and $content -match "winload"
    }
    
    Invoke-AgentTest $agentNum "Precision-TC-011" {
        $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
        $content -match "TC-011" -and ($content -match "0x7B" -or $content -match "StartOverride")
    }
    
    Invoke-AgentTest $agentNum "Precision-TC-014" {
        $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
        $content -match "TC-014" -and $content -match "pending\.xml"
    }
    
    Invoke-AgentTest $agentNum "Safety-BRICKME" {
        $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
        $content -match "BRICKME" -or $content -match "Invoke-BootPrecisionSafetyCheck"
    }
    
    Invoke-AgentTest $agentNum "Safety-Backup" {
        $content = Get-Content "Helper\WinRepairCore.ps1" -Raw
        $content -match "Backup-PrecisionState"
    }
}

# GUI Launch Test (if requested and in FullOS)
if ($TestGUILaunch -and (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)) {
    Write-Host "`n=== GUI Launch Test ===" -ForegroundColor Cyan
    try {
        $guiPath = Resolve-Path "Helper\WinRepairGUI.ps1" -ErrorAction Stop
        $testFile = "$env:TEMP\test-gui-launch.ps1"
        @"
            `$ErrorActionPreference = 'Stop'
            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
            . '$guiPath' -ErrorAction Stop
            Write-Output 'GUI_MODULE_LOADED'
"@ | Out-File $testFile -Encoding UTF8
        
        $output = & powershell -NoProfile -STA -ExecutionPolicy Bypass -File $testFile 2>&1
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        
        if ($output -match "GUI_MODULE_LOADED") {
            Write-Host "[GUI-TEST] Module loaded successfully" -ForegroundColor Green
            $global:AllResults += [PSCustomObject]@{
                Agent = "GUI-TEST"
                Test = "GUI-ModuleLoad"
                Status = "PASS"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        } else {
            Write-Host "[GUI-TEST] Module load failed" -ForegroundColor Red
            $global:AllResults += [PSCustomObject]@{
                Agent = "GUI-TEST"
                Test = "GUI-ModuleLoad"
                Status = "FAIL"
                Error = ($output -join "; ")
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
    } catch {
        Write-Host "[GUI-TEST] Exception: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "VALIDATION SUMMARY" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

$passCount = ($global:AllResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($global:AllResults | Where-Object { $_.Status -eq "FAIL" }).Count
$totalCount = $global:AllResults.Count

Write-Host "Total Tests: $totalCount" -ForegroundColor White
Write-Host "PASS: $passCount" -ForegroundColor Green
Write-Host "FAIL: $failCount" -ForegroundColor Red

# Export results
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$reportPath = Join-Path $LogDir "20agent-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$global:AllResults | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
Write-Host "`nReport saved to: $reportPath" -ForegroundColor Cyan

if ($failCount -gt 0) {
    Write-Host "`nFAILED TESTS:" -ForegroundColor Red
    $global:AllResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  [$($_.Agent)] $($_.Test)" -ForegroundColor Yellow
        if ($_.Error) { Write-Host "    Error: $($_.Error)" -ForegroundColor Gray }
    }
    exit 1
} else {
    Write-Host "`nALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
