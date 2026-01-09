<#
    XAML PARSING WRAPPER
    ====================
    
    Defensive XAML parsing with comprehensive validation.
#>

function Test-XamlValid {
    param([string]$XamlString)
    
    if ([string]::IsNullOrWhiteSpace($XamlString)) {
        return $false
    }
    
    try {
        if (-not ($XamlString.Contains("<") -and $XamlString.Contains(">"))) {
            return $false
        }
        
        [xml]$xmlDoc = $XamlString
        return $true
    } catch {
        return $false
    }
}

function Protect-XamlParsing {
    param(
        [string]$XamlString,
        [switch]$ReturnNull = $false
    )
    
    $result = @{
        Success = $false
        WPFObject = $null
        Error = $null
        StackTrace = $null
        Diagnostics = @{}
    }
    
    try {
        Add-MiracleBootLog -Level "DEBUG" -Location "Protect-XamlParsing:validation" -Message "Validating XAML syntax"
        
        if (-not (Test-XamlValid -XamlString $XamlString)) {
            throw "XAML syntax validation failed"
        }
        
        $result.Diagnostics.SyntaxValidated = $true
        
        try {
            $null = [System.Windows.FrameworkElement]
            $result.Diagnostics.WPFAssembliesLoaded = $true
        } catch {
            throw "WPF assemblies not available"
        }
        
        [xml]$xmlDoc = $XamlString
        $xmlReader = New-Object System.Xml.XmlNodeReader $xmlDoc
        $wfpObject = [System.Windows.Markup.XamlReader]::Load($xmlReader)
        
        if ($null -eq $wfpObject) {
            throw "XamlReader.Load() returned null"
        }
        
        $result.Success = $true
        $result.WPFObject = $wfpObject
        $result.Diagnostics.ParsedSuccessfully = $true
        
        Add-MiracleBootLog -Level "SUCCESS" -Location "Protect-XamlParsing" -Message "XAML parsed successfully"
        
    } catch {
        $result.Error = $_.Exception.Message
        $result.StackTrace = $_.ScriptStackTrace
        
        Add-MiracleBootLog -Level "ERROR" -Location "Protect-XamlParsing" -Message "XAML parsing failed: $($_.Exception.Message)"
    }
    
    return $result
}

function Invoke-GuiWithFallback {
    param(
        [string]$GUIModulePath,
        [string]$TUIModulePath,
        [string]$ScriptRoot
    )
    
    $result = @{
        LaunchMode = "UNKNOWN"
        Success = $false
        Error = $null
    }
    
    try {
        Add-MiracleBootLog -Level "INFO" -Location "Invoke-GuiWithFallback" -Message "Attempting to load GUI module"
        
        if (-not (Test-Path $GUIModulePath)) {
            throw "GUI module not found at: $GUIModulePath"
        }
        
        . $GUIModulePath -ErrorAction Stop
        Add-MiracleBootLog -Level "SUCCESS" -Location "Invoke-GuiWithFallback" -Message "GUI module loaded"
        
        if (-not (Get-Command Start-GUI -ErrorAction SilentlyContinue)) {
            throw "Start-GUI function not found"
        }
        
        Add-MiracleBootLog -Level "INFO" -Location "Invoke-GuiWithFallback" -Message "Launching GUI"
        Start-GUI
        
        $result.LaunchMode = "GUI"
        $result.Success = $true
        
    } catch {
        $result.Error = $_.Exception.Message
        
        Add-MiracleBootLog -Level "WARNING" -Location "Invoke-GuiWithFallback" -Message "GUI failed, falling back to TUI"
        
        Write-Host "`n===============================================================" -ForegroundColor Yellow
        Write-Host "  GUI MODE UNAVAILABLE - SWITCHING TO TEXT MODE" -ForegroundColor Yellow
        Write-Host "===============================================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Reason: $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Press any key to continue..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        try {
            if (-not (Test-Path $TUIModulePath)) {
                throw "TUI module not found"
            }
            
            . $TUIModulePath -ErrorAction Stop
            
            if (-not (Get-Command Start-TUI -ErrorAction SilentlyContinue)) {
                throw "Start-TUI function not found"
            }
            
            Add-MiracleBootLog -Level "INFO" -Location "Invoke-GuiWithFallback" -Message "Launching TUI fallback"
            Start-TUI
            
            $result.LaunchMode = "TUI"
            $result.Success = $true
            
        } catch {
            $result.Error = "Both GUI and TUI failed: $($_.Exception.Message)"
            Add-MiracleBootLog -Level "ERROR" -Location "Invoke-GuiWithFallback" -Message "TUI fallback failed"
            throw $result.Error
        }
    }
    
    return $result
}
