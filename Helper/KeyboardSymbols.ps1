################################################################################
# KeyboardSymbols.ps1
# 
# Purpose: Comprehensive keyboard symbol management module for MiracleBoot
#          Handles symbol copy-paste, ALT code reference, and keyboard layout info
#
# Features:
#   - Interactive symbol helper menu with copy-to-clipboard
#   - ALT code reference guide (Windows numeric keypad codes)
#   - On-screen keyboard launcher
#   - Keyboard layout information and switching
#   - GUI mode with WPF interface
#   - Symbol search and filtering by category
#   - Common problematic symbols from non-English layouts
#
# Author: MiracleBoot Project
# Version: 1.0
################################################################################

# ============================================================================
# SYMBOL DATABASE
# ============================================================================

# Comprehensive symbol reference with ALT codes, descriptions, and categories
$script:SymbolDatabase = @(
    # Quotation marks
    @{ Symbol = '"'; ALTCode = 34; Description = 'Double Quote'; Category = 'Quotation'; Problematic = $true; Common = $true }
    @{ Symbol = "'"; ALTCode = 39; Description = 'Single Quote/Apostrophe'; Category = 'Quotation'; Problematic = $true; Common = $true }
    @{ Symbol = '`'; ALTCode = 96; Description = 'Backtick/Grave Accent'; Category = 'Quotation'; Problematic = $true; Common = $false }
    @{ Symbol = [char]0x00AB; ALTCode = 174; Description = 'Left Double Guillemet'; Category = 'Quotation'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00BB; ALTCode = 175; Description = 'Right Double Guillemet'; Category = 'Quotation'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x201C; ALTCode = 147; Description = 'Left Smart Quote'; Category = 'Quotation'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x201D; ALTCode = 148; Description = 'Right Smart Quote'; Category = 'Quotation'; Problematic = $false; Common = $false }
    
    # Backslash and Forward Slash
    @{ Symbol = '\'; ALTCode = 92; Description = 'Backslash'; Category = 'Path'; Problematic = $true; Common = $true }
    @{ Symbol = '/'; ALTCode = 47; Description = 'Forward Slash'; Category = 'Path'; Problematic = $true; Common = $true }
    
    # Exclamation and Other Punctuation
    @{ Symbol = '!'; ALTCode = 33; Description = 'Exclamation Mark'; Category = 'Punctuation'; Problematic = $true; Common = $true }
    @{ Symbol = '?'; ALTCode = 63; Description = 'Question Mark'; Category = 'Punctuation'; Problematic = $true; Common = $true }
    @{ Symbol = '.'; ALTCode = 46; Description = 'Period/Full Stop'; Category = 'Punctuation'; Problematic = $false; Common = $true }
    @{ Symbol = ','; ALTCode = 44; Description = 'Comma'; Category = 'Punctuation'; Problematic = $false; Common = $true }
    @{ Symbol = ';'; ALTCode = 59; Description = 'Semicolon'; Category = 'Punctuation'; Problematic = $true; Common = $false }
    @{ Symbol = ':'; ALTCode = 58; Description = 'Colon'; Category = 'Punctuation'; Problematic = $true; Common = $false }
    @{ Symbol = '~'; ALTCode = 126; Description = 'Tilde'; Category = 'Punctuation'; Problematic = $true; Common = $false }
    
    # Special Characters
    @{ Symbol = '@'; ALTCode = 64; Description = 'At Sign'; Category = 'Special'; Problematic = $true; Common = $true }
    @{ Symbol = '#'; ALTCode = 35; Description = 'Hash/Number Sign'; Category = 'Special'; Problematic = $true; Common = $true }
    @{ Symbol = '$'; ALTCode = 36; Description = 'Dollar Sign'; Category = 'Special'; Problematic = $true; Common = $true }
    @{ Symbol = '%'; ALTCode = 37; Description = 'Percent'; Category = 'Special'; Problematic = $true; Common = $true }
    @{ Symbol = '&'; ALTCode = 38; Description = 'Ampersand'; Category = 'Special'; Problematic = $true; Common = $true }
    @{ Symbol = [char]0x00A7; ALTCode = 21; Description = 'Section Sign'; Category = 'Special'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00B6; ALTCode = 20; Description = 'Pilcrow/Paragraph'; Category = 'Special'; Problematic = $false; Common = $false }
    
    # Mathematical Operators
    @{ Symbol = '+'; ALTCode = 43; Description = 'Plus Sign'; Category = 'Operators'; Problematic = $false; Common = $true }
    @{ Symbol = '-'; ALTCode = 45; Description = 'Hyphen/Minus'; Category = 'Operators'; Problematic = $true; Common = $true }
    @{ Symbol = '*'; ALTCode = 42; Description = 'Asterisk/Multiply'; Category = 'Operators'; Problematic = $true; Common = $true }
    @{ Symbol = '/'; ALTCode = 47; Description = 'Slash/Divide'; Category = 'Operators'; Problematic = $true; Common = $true }
    @{ Symbol = '='; ALTCode = 61; Description = 'Equals Sign'; Category = 'Operators'; Problematic = $true; Common = $true }
    @{ Symbol = '<'; ALTCode = 60; Description = 'Less Than'; Category = 'Operators'; Problematic = $true; Common = $true }
    @{ Symbol = '>'; ALTCode = 62; Description = 'Greater Than'; Category = 'Operators'; Problematic = $true; Common = $true }
    @{ Symbol = [char]0x00B1; ALTCode = 241; Description = 'Plus-Minus'; Category = 'Operators'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00D7; ALTCode = 158; Description = 'Multiplication Sign'; Category = 'Operators'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00F7; ALTCode = 246; Description = 'Division Sign'; Category = 'Operators'; Problematic = $false; Common = $false }
    
    # Brackets and Parentheses
    @{ Symbol = '('; ALTCode = 40; Description = 'Left Parenthesis'; Category = 'Brackets'; Problematic = $true; Common = $true }
    @{ Symbol = ')'; ALTCode = 41; Description = 'Right Parenthesis'; Category = 'Brackets'; Problematic = $true; Common = $true }
    @{ Symbol = '['; ALTCode = 91; Description = 'Left Square Bracket'; Category = 'Brackets'; Problematic = $true; Common = $true }
    @{ Symbol = ']'; ALTCode = 93; Description = 'Right Square Bracket'; Category = 'Brackets'; Problematic = $true; Common = $true }
    @{ Symbol = '{'; ALTCode = 123; Description = 'Left Curly Brace'; Category = 'Brackets'; Problematic = $true; Common = $true }
    @{ Symbol = '}'; ALTCode = 125; Description = 'Right Curly Brace'; Category = 'Brackets'; Problematic = $true; Common = $true }
    @{ Symbol = '<'; ALTCode = 60; Description = 'Left Angle Bracket'; Category = 'Brackets'; Problematic = $true; Common = $false }
    @{ Symbol = '>'; ALTCode = 62; Description = 'Right Angle Bracket'; Category = 'Brackets'; Problematic = $true; Common = $false }
    
    # Logical and Special
    @{ Symbol = '|'; ALTCode = 124; Description = 'Pipe/Vertical Bar'; Category = 'Special'; Problematic = $true; Common = $true }
    @{ Symbol = '^'; ALTCode = 94; Description = 'Caret/Circumflex'; Category = 'Special'; Problematic = $true; Common = $true }
    @{ Symbol = '~'; ALTCode = 126; Description = 'Tilde'; Category = 'Special'; Problematic = $true; Common = $false }
    @{ Symbol = '_'; ALTCode = 95; Description = 'Underscore'; Category = 'Special'; Problematic = $true; Common = $true }
    @{ Symbol = [char]0x00A8; ALTCode = 249; Description = 'Diaeresis'; Category = 'Special'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00AF; ALTCode = 175; Description = 'Macron'; Category = 'Special'; Problematic = $false; Common = $false }
    
    # Assignment/Equals variations
    @{ Symbol = [char]0x2248; ALTCode = 247; Description = 'Approximately Equal'; Category = 'Operators'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x2260; ALTCode = 173; Description = 'Not Equal'; Category = 'Operators'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x2264; ALTCode = 243; Description = 'Less Than or Equal'; Category = 'Operators'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x2265; ALTCode = 242; Description = 'Greater Than or Equal'; Category = 'Operators'; Problematic = $false; Common = $false }
    
    # Additional Common Symbols
    @{ Symbol = [char]0x00B0; ALTCode = 248; Description = 'Degree Symbol'; Category = 'Special'; Problematic = $false; Common = $true }
    @{ Symbol = [char]0x00A9; ALTCode = 169; Description = 'Copyright'; Category = 'Special'; Problematic = $false; Common = $true }
    @{ Symbol = [char]0x00AE; ALTCode = 174; Description = 'Registered Trademark'; Category = 'Special'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x2122; ALTCode = 153; Description = 'Trademark'; Category = 'Special'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x20AC; ALTCode = 128; Description = 'Euro Sign'; Category = 'Currency'; Problematic = $false; Common = $true }
    @{ Symbol = [char]0x00A3; ALTCode = 156; Description = 'Pound Sign'; Category = 'Currency'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00A5; ALTCode = 157; Description = 'Yen Sign'; Category = 'Currency'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00A2; ALTCode = 155; Description = 'Cent Sign'; Category = 'Currency'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00A4; ALTCode = 207; Description = 'Generic Currency'; Category = 'Currency'; Problematic = $false; Common = $false }
    
    # Bullet and Arrow Symbols
    @{ Symbol = [char]0x2022; ALTCode = 7; Description = 'Bullet Point'; Category = 'Symbols'; Problematic = $false; Common = $true }
    @{ Symbol = [char]0x2192; ALTCode = 26; Description = 'Right Arrow'; Category = 'Symbols'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x2190; ALTCode = 27; Description = 'Left Arrow'; Category = 'Symbols'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x2191; ALTCode = 24; Description = 'Up Arrow'; Category = 'Symbols'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x2193; ALTCode = 25; Description = 'Down Arrow'; Category = 'Symbols'; Problematic = $false; Common = $false }
    
    # Fraction and Mathematical
    @{ Symbol = [char]0x00BD; ALTCode = 171; Description = 'One Half'; Category = 'Fractions'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00BC; ALTCode = 172; Description = 'One Quarter'; Category = 'Fractions'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00BE; ALTCode = 184; Description = 'Three Quarters'; Category = 'Fractions'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00B3; ALTCode = 252; Description = 'Superscript Three'; Category = 'Fractions'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00B2; ALTCode = 253; Description = 'Superscript Two'; Category = 'Fractions'; Problematic = $false; Common = $false }
    @{ Symbol = [char]0x00B9; ALTCode = 185; Description = 'Superscript One'; Category = 'Fractions'; Problematic = $false; Common = $false }
)

# ============================================================================
# INTERNAL HELPER FUNCTIONS
# ============================================================================

function Invoke-SymbolCopy {
    <#
    .SYNOPSIS
    Copies a selected symbol to the clipboard with validation.
    
    .PARAMETER Symbol
    The symbol character to copy
    
    .PARAMETER Description
    Description of the symbol for user feedback
    
    .OUTPUTS
    Boolean indicating success or failure
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Symbol,
        
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    
    try {
        # Copy to clipboard using .NET
        [System.Windows.Forms.Clipboard]::SetText($Symbol)
        
        # Verify it was copied
        $clipboardContent = [System.Windows.Forms.Clipboard]::GetText()
        
        if ($clipboardContent -eq $Symbol) {
            Write-Host "[OK] Copied to clipboard: '$Symbol' ($Description)" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "[FAILED] Failed to copy symbol to clipboard" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "[ERROR] Error copying symbol: $_" -ForegroundColor Red
        return $false
    }
}

function Get-SymbolsByCategory {
    <#
    .SYNOPSIS
    Retrieves all symbols in a specific category
    
    .PARAMETER Category
    The category to filter by
    
    .OUTPUTS
    Array of symbol objects
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )
    
    return @($script:SymbolDatabase | Where-Object { $_.Category -eq $Category })
}

function Get-AllCategories {
    <#
    .SYNOPSIS
    Returns list of all unique symbol categories
    
    .OUTPUTS
    Array of category names
    #>
    return @($script:SymbolDatabase | Select-Object -ExpandProperty Category -Unique | Sort-Object)
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Show-SymbolHelper {
    <#
    .SYNOPSIS
    Displays interactive menu to copy symbols to clipboard
    
    .DESCRIPTION
    Shows all available symbols organized by category. Users can:
    - Browse symbols by category
    - Copy symbols to clipboard
    - View ALT codes
    - Search for specific symbols
    
    .EXAMPLE
    Show-SymbolHelper
    
    Displays the interactive symbol helper menu
    
    .EXAMPLE
    Show-SymbolHelper -Category "Quotation"
    
    Shows only symbols in the Quotation category
    
    .PARAMETER Category
    Filter to specific category. If not provided, shows all categories.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Category
    )
    
    # Load Windows Forms for clipboard access
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    
    # Get categories to display
    $categories = if ($Category) {
        @($Category)
    }
    else {
        Get-AllCategories
    }
    
    $selectedSymbols = if ($Category) {
        Get-SymbolsByCategory -Category $Category
    }
    else {
        $script:SymbolDatabase
    }
    
    # Sort symbols by category
    $selectedSymbols = $selectedSymbols | Sort-Object Category, Symbol
    
    while ($true) {
        Clear-Host
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "         SYMBOL HELPER - Copy to Clipboard" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Display categories
        $categories = Get-AllCategories
        Write-Host "Available Categories:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $categories.Count; $i++) {
            Write-Host "  $($i + 1). $($categories[$i])" -ForegroundColor Green
        }
        Write-Host "  0. View All" -ForegroundColor Green
        Write-Host "  S. Search" -ForegroundColor Green
        Write-Host "  Q. Quit" -ForegroundColor Yellow
        Write-Host ""
        
        $choice = Read-Host "Select category (1-$($categories.Count), 0, S, or Q)"
        
        if ($choice -eq 'Q') { break }
        if ($choice -eq 'S') {
            $searchTerm = Read-Host "Search for symbol or description"
            $results = @($script:SymbolDatabase | 
                Where-Object { $_.Symbol -like "*$searchTerm*" -or $_.Description -like "*$searchTerm*" })
            
            if ($results.Count -eq 0) {
                Write-Host "No symbols found matching '$searchTerm'" -ForegroundColor Red
                Read-Host "Press Enter to continue"
                continue
            }
            
            Show-SymbolTable -Symbols $results
            continue
        }
        
        # Get selected category symbols
        if ($choice -eq '0') {
            $categorySymbols = $script:SymbolDatabase
        }
        elseif ($choice -ge 1 -and $choice -le $categories.Count) {
            $selectedCategory = $categories[$choice - 1]
            $categorySymbols = Get-SymbolsByCategory -Category $selectedCategory
        }
        else {
            Write-Host "Invalid selection" -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
        
        # Display and handle symbol selection
        Show-SymbolTable -Symbols $categorySymbols
    }
}

function Show-SymbolTable {
    <#
    .SYNOPSIS
    Displays a formatted table of symbols for selection
    
    .PARAMETER Symbols
    Array of symbol objects to display
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Symbols
    )
    
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    
    while ($true) {
        Clear-Host
        Write-Host "======================================================================" -ForegroundColor Cyan
        Write-Host "                     SELECT SYMBOL TO COPY" -ForegroundColor Cyan
        Write-Host "======================================================================" -ForegroundColor Cyan
        Write-Host ""
        
        # Display symbols in a table
        Write-Host "  # | Symbol | ALT Code | Description | Category" -ForegroundColor White
        Write-Host "----+--------+----------+-------------+--------------" -ForegroundColor Gray
        
        for ($i = 0; $i -lt $Symbols.Count; $i++) {
            $sym = $Symbols[$i]
            $symbolDisplay = if ($sym.Problematic) { "$($sym.Symbol) [WARNING]" } else { $sym.Symbol }
            Write-Host ("  {0:2d} |   {1}   |  {2,3}    | {3,-11} | {4}" -f `
                    $i + 1, $symbolDisplay, $sym.ALTCode, $sym.Description.Substring(0, [Math]::Min(11, $sym.Description.Length)), $sym.Category) -ForegroundColor White
        }
        
        Write-Host ""
        Write-Host "Legend: [WARNING] = Problematic in non-English layouts" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "B. Back | Q. Quit" -ForegroundColor Yellow
        
        $choice = Read-Host "Enter number to copy (1-$($Symbols.Count)), B, or Q"
        
        if ($choice -eq 'Q') { exit }
        if ($choice -eq 'B') { return }
        
        if ($choice -ge 1 -and $choice -le $Symbols.Count) {
            $selectedSymbol = $Symbols[$choice - 1]
            
            # Copy symbol
            $result = Invoke-SymbolCopy -Symbol $selectedSymbol.Symbol -Description $selectedSymbol.Description
            
            if ($result) {
                Write-Host ""
                Write-Host "ALT Code for this symbol: Alt+$($selectedSymbol.ALTCode)" -ForegroundColor Cyan
                Write-Host "(Hold Alt on numeric keypad, type $($selectedSymbol.ALTCode), release Alt)" -ForegroundColor Gray
                Write-Host ""
            }
            
            Read-Host "Press Enter to continue"
        }
        else {
            Write-Host "Invalid selection" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

function Show-ALTCodeReference {
    <#
    .SYNOPSIS
    Displays comprehensive ALT code reference in table format
    
    .DESCRIPTION
    Shows all symbols with their ALT codes in an easy-to-read table format.
    Symbols marked as "Problematic" are those that commonly get corrupted
    when typing on wrong keyboard layouts.
    
    .PARAMETER ShowProblematicOnly
    If specified, only shows symbols that are problematic in non-English layouts
    
    .PARAMETER ExportToFile
    If specified, exports reference to a text file
    
    .EXAMPLE
    Show-ALTCodeReference
    
    Displays the complete ALT code reference
    
    .EXAMPLE
    Show-ALTCodeReference -ShowProblematicOnly
    
    Shows only problematic symbols
    
    .EXAMPLE
    Show-ALTCodeReference -ExportToFile "$env:USERPROFILE\Desktop\ALT_Codes.txt"
    
    Exports reference to Desktop
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ShowProblematicOnly,
        
        [Parameter(Mandatory = $false)]
        [string]$ExportToFile
    )
    
    $symbols = if ($ShowProblematicOnly) {
        $script:SymbolDatabase | Where-Object { $_.Problematic -eq $true }
    }
    else {
        $script:SymbolDatabase
    }
    
    $symbols = $symbols | Sort-Object ALTCode
    
    # Build reference text
    $reference = @()
    $reference += "=" * 80
    $reference += "WINDOWS ALT CODE REFERENCE FOR SPECIAL SYMBOLS"
    $reference += "=" * 80
    $reference += ""
    $reference += "INSTRUCTIONS:"
    $reference += "1. Hold Alt key on the numeric keypad (not the number row)"
    $reference += "2. Type the ALT code number"
    $reference += "3. Release Alt key"
    $reference += "[WARNING] = Problematic symbol in non-English keyboard layouts"
    $reference += ""
    $reference += ""
    
    # Group by category
    $categories = $symbols | Select-Object -ExpandProperty Category -Unique | Sort-Object
    
    foreach ($cat in $categories) {
        $catSymbols = $symbols | Where-Object { $_.Category -eq $cat } | Sort-Object ALTCode
        
        $reference += "-" * 80
        $reference += "CATEGORY: $cat"
        $reference += "-" * 80
        
        foreach ($sym in $catSymbols) {
            $marker = if ($sym.Problematic) { "[WARNING] " } else { "  " }
            $reference += "{0} Alt+{1,-3} | '{2}' | {3}" -f $marker, $sym.ALTCode, $sym.Symbol, $sym.Description
        }
        
        $reference += ""
    }
    
    # Display to console
    Clear-Host
    $reference | ForEach-Object { Write-Host $_ }
    
    # Export to file if requested
    if ($ExportToFile) {
        try {
            $reference | Out-File -FilePath $ExportToFile -Encoding UTF8 -Force
            Write-Host ""
            Write-Host "[OK] Reference exported to: $ExportToFile" -ForegroundColor Green
        }
        catch {
            Write-Host "[FAILED] Failed to export reference: $_" -ForegroundColor Red
        }
    }
    
    Read-Host "Press Enter to continue"
}

function Launch-OnScreenKeyboard {
    <#
    .SYNOPSIS
    Launches the Windows on-screen keyboard (osk.exe)
    
    .DESCRIPTION
    Opens the Windows on-screen keyboard, useful when the physical
    keyboard layout doesn't match the system setting.
    
    .EXAMPLE
    Launch-OnScreenKeyboard
    
    Opens the Windows on-screen keyboard
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Launching Windows On-Screen Keyboard..." -ForegroundColor Cyan
        Start-Process -FilePath "osk.exe" -ErrorAction Stop
        Start-Sleep -Seconds 1
        Write-Host "[OK] On-screen keyboard launched" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED] Failed to launch on-screen keyboard: $_" -ForegroundColor Red
    }
}

function Get-KeyboardInfo {
    <#
    .SYNOPSIS
    Displays current keyboard layout and switching options
    
    .DESCRIPTION
    Shows the currently active keyboard layout and provides information
    on how to switch between layouts.
    
    .EXAMPLE
    Get-KeyboardInfo
    
    Shows current keyboard layout information
    #>
    [CmdletBinding()]
    param()
    
    Clear-Host
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "          KEYBOARD LAYOUT INFORMATION" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Get current keyboard layout using WMI
        $layouts = Get-WmiObject -Class Win32_KeyboardLayout
        
        Write-Host "Installed Keyboard Layouts:" -ForegroundColor Yellow
        Write-Host ""
        
        if ($layouts) {
            foreach ($layout in $layouts) {
                $layoutId = $layout.Name
                # Common layout IDs
                $layoutName = switch ($layoutId) {
                    "00000409" { "English (United States)" }
                    "00000809" { "English (United Kingdom)" }
                    "00000C0C" { "French (Canadian)" }
                    "0000040C" { "French (France)" }
                    "00000407" { "German (Germany)" }
                    "00000410" { "Italian (Italy)" }
                    "00000419" { "Russian (Russia)" }
                    "0000041D" { "Swedish (Sweden)" }
                    "00000406" { "Danish (Denmark)" }
                    "00000413" { "Dutch (Netherlands)" }
                    default { "Layout: $layoutId" }
                }
                
                Write-Host "  • $layoutName (ID: $layoutId)" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  Could not retrieve keyboard layout information" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  Error retrieving keyboard layouts: $_" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "How to Switch Keyboard Layouts:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Method 1 - Windows 10/11 Quick Settings:" -ForegroundColor Cyan
    Write-Host "    • Click language icon in taskbar" -ForegroundColor Gray
    Write-Host "    • Select desired keyboard layout" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Method 2 - Language Settings:" -ForegroundColor Cyan
    Write-Host "    • Settings > Time & Language > Language & Region" -ForegroundColor Gray
    Write-Host "    • Or: Settings > System > Display > Related settings > Language" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Method 3 - Quick Switch:" -ForegroundColor Cyan
    Write-Host "    • Alt + Shift (if configured)" -ForegroundColor Gray
    Write-Host "    • Ctrl + Shift (alternative shortcut)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Problematic Symbols by Layout:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  French (AZERTY):" -ForegroundColor Cyan
    Write-Host "    • Numbers require Shift key" -ForegroundColor Gray
    Write-Host "    • Brackets: [ ] { } may be in different positions" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  German (QWERTZ):" -ForegroundColor Cyan
    Write-Host "    • Y and Z are swapped from QWERTY" -ForegroundColor Gray
    Write-Host "    • Special characters in different positions" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Russian (Cyrillic):" -ForegroundColor Cyan
    Write-Host "    • Completely different key positions" -ForegroundColor Gray
    Write-Host "    • English symbols require layout switching" -ForegroundColor Gray
    Write-Host ""
    
    Read-Host "Press Enter to continue"
}

function Show-ProblematicSymbols {
    <#
    .SYNOPSIS
    Shows symbols that are commonly problematic in non-English keyboard layouts
    
    .DESCRIPTION
    Displays symbols that frequently get corrupted or are difficult to type
    when the physical keyboard layout doesn't match the system setting.
    
    .EXAMPLE
    Show-ProblematicSymbols
    
    Shows all problematic symbols with their ALT codes
    #>
    [CmdletBinding()]
    param()
    
    $problematicSymbols = $script:SymbolDatabase | Where-Object { $_.Problematic -eq $true } | Sort-Object Symbol
    
    Clear-Host
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "    PROBLEMATIC SYMBOLS (Non-English Keyboard Layouts)" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "These symbols are most likely to be corrupted when typing with" -ForegroundColor Gray
    Write-Host "a physical keyboard that doesn't match your OS language setting." -ForegroundColor Gray
    Write-Host ""
    
    # Group by category
    $categories = $problematicSymbols | Select-Object -ExpandProperty Category -Unique | Sort-Object
    
    foreach ($cat in $categories) {
        $catSymbols = $problematicSymbols | Where-Object { $_.Category -eq $cat }
        
        Write-Host "${cat}:" -ForegroundColor Cyan
        foreach ($sym in $catSymbols | Sort-Object ALTCode) {
            Write-Host "  • '$($sym.Symbol)' (Alt+$($sym.ALTCode)) - $($sym.Description)" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    Write-Host "Recommendation:" -ForegroundColor Yellow
    Write-Host "  Use Copy-Paste Helper or ALT codes for these symbols to avoid" -ForegroundColor Gray
    Write-Host "  typing errors that can break scripts, file paths, and code." -ForegroundColor Gray
    Write-Host ""
    
    Read-Host "Press Enter to continue"
}

function Show-SymbolHelperGUI {
    <#
    .SYNOPSIS
    Displays symbols in an interactive WPF GUI window
    
    .DESCRIPTION
    Opens a graphical interface for easier symbol selection and copying.
    Requires .NET Framework with WPF support.
    
    .EXAMPLE
    Show-SymbolHelperGUI
    
    Launches the GUI-based symbol helper
    #>
    [CmdletBinding()]
    param()
    
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }
    catch {
        Write-Host "[FAILED] WPF is not available on this system" -ForegroundColor Red
        Write-Host "  Please use Show-SymbolHelper instead" -ForegroundColor Yellow
        return
    }
    
    # Create WPF window
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Symbol Helper" Height="600" Width="800" Background="#F0F0F0">
    <Grid>
        <StackPanel Margin="10">
            <TextBlock Text="Symbol Helper" FontSize="18" FontWeight="Bold" Foreground="#0078D4" Margin="0,0,0,10"/>
            <TextBlock Text="Click on any symbol to copy it to clipboard" FontSize="12" Foreground="#666" Margin="0,0,0,10"/>
            <ComboBox x:Name="CategoryCombo" Height="30" Margin="0,0,0,10" FontSize="12"/>
            <ListBox x:Name="SymbolList" Height="400" Margin="0,0,0,10" FontSize="12"/>
            <TextBlock x:Name="StatusText" Height="30" Foreground="Green" VerticalAlignment="Bottom"/>
        </StackPanel>
    </Grid>
</Window>
"@
    
    $window = [Windows.Markup.XamlReader]::Parse($xaml)
    $categoryCombo = $window.FindName("CategoryCombo")
    $symbolList = $window.FindName("SymbolList")
    $statusText = $window.FindName("StatusText")
    
    # Populate categories
    $categories = Get-AllCategories
    $categoryCombo.ItemsSource = @("All") + $categories
    $categoryCombo.SelectedIndex = 0
    
    # Category selection handler
    $categoryCombo.Add_SelectionChanged({
        $selected = $categoryCombo.SelectedItem
        
        if ($selected -eq "All") {
            $toShow = $script:SymbolDatabase | Sort-Object Symbol
        }
        else {
            $toShow = Get-SymbolsByCategory -Category $selected | Sort-Object Symbol
        }
        
        $symbolList.Items.Clear()
        foreach ($sym in $toShow) {
            $item = "$($sym.Symbol) (Alt+$($sym.ALTCode)) - $($sym.Description)"
            $symbolList.Items.Add($item) | Out-Null
        }
    })
    
    # Trigger initial population
    $categoryCombo.SelectedIndex = 0
    
    # Symbol click handler
    $symbolList.Add_MouseDoubleClick({
        if ($symbolList.SelectedIndex -ge 0) {
            $selectedText = $symbolList.SelectedItem
            $symbol = $selectedText[0]
            
            [System.Windows.Forms.Clipboard]::SetText($symbol)
            $statusText.Text = "[OK] Copied: '$symbol' to clipboard"
            
            $window.Dispatcher.Invoke({
                Start-Sleep -Milliseconds 2000
                $statusText.Text = ""
            })
        }
    })
    
    # Show window
    $window.ShowDialog() | Out-Null
}

function Invoke-SymbolSearch {
    <#
    .SYNOPSIS
    Search for symbols by character or description
    
    .PARAMETER SearchTerm
    The term to search for (symbol or description)
    
    .PARAMETER CopyIfSingle
    If only one symbol matches, automatically copy it to clipboard
    
    .EXAMPLE
    Invoke-SymbolSearch -SearchTerm "quote"
    
    Finds all symbols with "quote" in the description
    
    .EXAMPLE
    Invoke-SymbolSearch -SearchTerm "'"
    
    Finds the single quote symbol
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchTerm,
        
        [Parameter(Mandatory = $false)]
        [switch]$CopyIfSingle
    )
    
    $results = @($script:SymbolDatabase | 
        Where-Object { 
            $_.Symbol -like "*$SearchTerm*" -or 
            $_.Description -like "*$SearchTerm*" -or
            $_.Category -like "*$SearchTerm*"
        })
    
    if ($results.Count -eq 0) {
        Write-Host "No symbols found matching '$SearchTerm'" -ForegroundColor Red
        return
    }
    
    if ($results.Count -eq 1 -and $CopyIfSingle) {
        Invoke-SymbolCopy -Symbol $results[0].Symbol -Description $results[0].Description
        return
    }
    
    Write-Host "Found $($results.Count) matching symbol(s):" -ForegroundColor Cyan
    Write-Host ""
    
    $results = $results | Sort-Object Category, Symbol
    
    for ($i = 0; $i -lt $results.Count; $i++) {
        $sym = $results[$i]
        $marker = if ($sym.Problematic) { "[WARNING] " } else { "  " }
        Write-Host ("{0}{1}. '{2}' (Alt+{3,-3}) - {4} [{5}]" -f $marker, $i + 1, $sym.Symbol, $sym.ALTCode, $sym.Description, $sym.Category) -ForegroundColor Green
    }
    
    Write-Host ""
    $choice = Read-Host "Select symbol to copy (1-$($results.Count)) or Press Enter to cancel"
    
    if ($choice -ge 1 -and $choice -le $results.Count) {
        Invoke-SymbolCopy -Symbol $results[$choice - 1].Symbol -Description $results[$choice - 1].Description
    }
}

function Get-CommonSymbols {
    <#
    .SYNOPSIS
    Returns the most common symbols that are problematic
    
    .DESCRIPTION
    Retrieves frequently-used symbols that are likely to cause typing
    errors when keyboard layout is mismatched.
    
    .EXAMPLE
    Get-CommonSymbols
    
    Lists all common and problematic symbols
    #>
    [CmdletBinding()]
    param()
    
    $common = $script:SymbolDatabase | Where-Object { $_.Common -eq $true } | Sort-Object Symbol
    
    Write-Host "Most Common Symbols:" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($sym in $common) {
        $marker = if ($sym.Problematic) { "[WARNING]" } else { "[OK]" }
        Write-Host "  $marker '$($sym.Symbol)' (Alt+$($sym.ALTCode)) - $($sym.Description)" -ForegroundColor Green
    }
}

function Get-SymbolByALTCode {
    <#
    .SYNOPSIS
    Find symbol by its ALT code
    
    .PARAMETER ALTCode
    The ALT code number to search for
    
    .EXAMPLE
    Get-SymbolByALTCode -ALTCode 34
    
    Returns the double quote symbol (")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ALTCode
    )
    
    $symbol = $script:SymbolDatabase | Where-Object { $_.ALTCode -eq $ALTCode }
    
    if ($symbol) {
        Write-Host "Symbol for Alt+${ALTCode}: '$($symbol.Symbol)'" -ForegroundColor Green
        Write-Host "  Description: $($symbol.Description)" -ForegroundColor Gray
        Write-Host "  Category: $($symbol.Category)" -ForegroundColor Gray
        Write-Host "  Problematic: $(if ($symbol.Problematic) { 'Yes' } else { 'No' })" -ForegroundColor Gray
        return $symbol
    }
    else {
        Write-Host "No symbol found for Alt+$ALTCode" -ForegroundColor Red
        return $null
    }
}

function Get-AllSymbols {
    <#
    .SYNOPSIS
    Returns all symbols in the database
    
    .OUTPUT
    Array of all symbol objects
    #>
    [CmdletBinding()]
    param()
    
    return @($script:SymbolDatabase)
}

function Export-SymbolDatabase {
    <#
    .SYNOPSIS
    Exports symbol database to a file
    
    .PARAMETER FilePath
    Path where to export the database
    
    .PARAMETER Format
    Export format: 'CSV' or 'JSON'
    
    .EXAMPLE
    Export-SymbolDatabase -FilePath "C:\symbols.csv" -Format CSV
    
    Exports database as CSV file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('CSV', 'JSON')]
        [string]$Format = 'CSV'
    )
    
    try {
        if ($Format -eq 'CSV') {
            $script:SymbolDatabase | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8 -Force
        }
        elseif ($Format -eq 'JSON') {
            $script:SymbolDatabase | ConvertTo-Json | Out-File -FilePath $FilePath -Encoding UTF8 -Force
        }
        
            Write-Host "[OK] Database exported to: $FilePath" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED] Failed to export database: $_" -ForegroundColor Red
    }
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Export public functions
Export-ModuleMember -Function @(
    'Show-SymbolHelper',
    'Show-ALTCodeReference',
    'Launch-OnScreenKeyboard',
    'Get-KeyboardInfo',
    'Show-ProblematicSymbols',
    'Show-SymbolHelperGUI',
    'Invoke-SymbolSearch',
    'Get-CommonSymbols',
    'Get-SymbolByALTCode',
    'Get-AllSymbols',
    'Export-SymbolDatabase',
    'Invoke-SymbolCopy',
    'Show-SymbolTable'
)

Write-Verbose "KeyboardSymbols module loaded successfully"
