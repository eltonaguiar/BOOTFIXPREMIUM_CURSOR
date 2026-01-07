Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

function Start-GUI {
$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Miracle Boot v7.2.0 - Advanced Recovery"
 Width="1200" Height="850" WindowStartupLocation="CenterScreen" Background="#F0F0F0">
<Grid>
    <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    
    <!-- Utility Toolbar -->
    <StackPanel Grid.Row="0" Orientation="Horizontal" Background="#E5E5E5" Margin="10,5">
        <TextBlock Text="Utilities:" VerticalAlignment="Center" Margin="5,0,10,0" FontWeight="Bold"/>
        <Button Content="Notepad" Name="BtnNotepad" Width="80" Height="25" Margin="2" ToolTip="Open Notepad"/>
        <Button Content="Registry" Name="BtnRegistry" Width="80" Height="25" Margin="2" ToolTip="Open Registry Editor"/>
        <Button Content="PowerShell" Name="BtnPowerShell" Width="90" Height="25" Margin="2" ToolTip="Open PowerShell"/>
        <Button Content="System Restore" Name="BtnRestore" Width="110" Height="25" Margin="2" ToolTip="Open System Restore Points"/>
        <Button Content="Disk Management" Name="BtnDiskManagement" Width="130" Height="25" Margin="2" ToolTip="Open Disk Management"/>
        <Separator Margin="10,0"/>
        <Button Content="Enable Network" Name="BtnEnableNetwork" Width="110" Height="25" Margin="2" ToolTip="Enable network adapters and test internet"/>
        <Button Content="Network Diagnostics" Name="BtnNetworkDiagnostics" Width="150" Height="25" Margin="2" ToolTip="Comprehensive network diagnostics and driver management"/>
        <Button Content="Keyboard Symbols" Name="BtnKeyboardSymbols" Width="130" Height="25" Margin="2" ToolTip="Keyboard symbol helper and ALT code reference"/>
        <Button Content="ChatGPT Help" Name="BtnChatGPT" Width="100" Height="25" Margin="2" ToolTip="Open ChatGPT for boot assistance help"/>
        <Separator Margin="10,0"/>
        <TextBlock Name="NetworkStatus" Text="Network: Unknown" VerticalAlignment="Center" Margin="5,0" Foreground="Gray"/>
        <TextBlock Name="EnvStatus" Text="Environment: Detecting..." VerticalAlignment="Center" Margin="10,0" Foreground="Gray"/>
</StackPanel>
    
    <TabControl Grid.Row="1" Margin="10">
        <TabItem Header="Volumes &amp; Health">
            <DockPanel Margin="10">
                <Button DockPanel.Dock="Top" Content="Refresh Volume List" Height="35" Name="BtnVol" Background="#0078D7" Foreground="White" FontWeight="Bold"/>
                <ListView Name="VolList" Margin="0,10,0,0">
                    <ListView.View>
                        <GridView>
                            <GridViewColumn Header="Letter" DisplayMemberBinding="{Binding DriveLetter}" Width="50"/>
                            <GridViewColumn Header="Label" DisplayMemberBinding="{Binding FileSystemLabel}" Width="150"/>
                            <GridViewColumn Header="Size" DisplayMemberBinding="{Binding Size}" Width="100"/>
                            <GridViewColumn Header="Status" DisplayMemberBinding="{Binding HealthStatus}" Width="100"/>
                        </GridView>
                    </ListView.View>
                </ListView>
            </DockPanel>
</TabItem>

<TabItem Header="BCD Editor">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <!-- Toolbar -->
                <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                    <Button Content="Load/Refresh BCD" Height="35" Name="BtnBCD" Background="#0078D7" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <Button Content="Create Backup" Height="35" Name="BtnBCDBackup" Background="#28a745" Foreground="White" Width="130" Margin="0,0,10,0"/>
                    <Button Content="Fix Duplicates" Height="35" Name="BtnFixDuplicates" Background="#ffc107" Foreground="Black" Width="130" Margin="0,0,10,0"/>
                    <Button Content="Sync to All EFI Partitions" Height="35" Name="BtnSyncBCD" Background="#6f42c1" Foreground="White" Width="200" Margin="0,0,10,0"/>
                    <Button Content="Boot Diagnosis" Height="35" Name="BtnBootDiagnosisBCD" Background="#17a2b8" Foreground="White" Width="150"/>
</StackPanel>
                
                <!-- Main Content with Tabs -->
                <TabControl Grid.Row="1" Name="BCDTabControl">
                    <TabItem Header="Basic Editor">
                        <Grid Margin="5">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="2*"/>
                                <ColumnDefinition Width="1*"/>
                            </Grid.ColumnDefinitions>
                            
                            <StackPanel Grid.Column="0" Margin="5">
                                <TextBlock Text="BCD Boot Entries" FontWeight="Bold" Margin="0,0,0,5"/>
                                <ListBox Name="BCDList" Height="350" Margin="0,0,0,10">
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <StackPanel>
                                                <TextBlock Text="{Binding DisplayText}" FontWeight="Bold">
                                                    <TextBlock.Style>
                                                        <Style TargetType="TextBlock">
                                                            <Setter Property="Foreground" Value="#0078D7"/>
                                                            <Style.Triggers>
                                                                <DataTrigger Binding="{Binding IsDefault}" Value="True">
                                                                    <Setter Property="Foreground" Value="#28a745"/>
                                                                </DataTrigger>
                                                            </Style.Triggers>
                                                        </Style>
                                                    </TextBlock.Style>
                                                </TextBlock>
                                                <TextBlock Text="{Binding Id}" FontSize="10" Foreground="Gray"/>
                                            </StackPanel>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                                <TextBox Name="BCDBox" AcceptsReturn="True" Height="150" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" IsReadOnly="True" Background="#222" Foreground="#00FF00"/>
                            </StackPanel>

                            <StackPanel Grid.Column="1" Margin="5" Background="#E5E5E5">
                                <TextBlock Text="Edit Selected Entry" FontWeight="Bold" Margin="5"/>
                                <TextBlock Text="Identifier (GUID):" Margin="5,5,0,0"/>
                                <TextBox Name="EditId" Margin="5" IsReadOnly="True" Background="#DDD"/>
                                <TextBlock Text="Description:" Margin="5,5,0,0"/>
                                <TextBox Name="EditDescription" Margin="5"/>
                                <TextBlock Text="New Friendly Name:" Margin="5,5,0,0"/>
                                <TextBox Name="EditName" Margin="5"/>
                                <Button Content="Update Description" Name="BtnUpdateBcd" Margin="5" Height="25"/>
                                <Button Content="Set as Default Boot" Name="BtnSetDefault" Margin="5" Height="25" Background="#D78700" Foreground="White"/>
                                <Separator Margin="5,10"/>
                                <TextBlock Text="Boot Timeout (Seconds):" Margin="5"/>
                                <TextBox Name="TxtTimeout" Margin="5"/>
                                <Button Content="Save Timeout" Name="BtnTimeout" Margin="5" Height="25"/>
                            </StackPanel>
                        </Grid>
</TabItem>

                    <TabItem Header="Advanced Properties">
                        <Grid Margin="5">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            
                            <TextBlock Grid.Row="0" Text="Select an entry from Basic Editor to edit all properties" FontStyle="Italic" Margin="5" Foreground="Gray"/>
                            
                            <DataGrid Grid.Row="1" Name="BCDPropertiesGrid" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="False" Margin="5">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Property" Binding="{Binding Name}" Width="200" IsReadOnly="True"/>
                                    <DataGridTextColumn Header="Value" Binding="{Binding Value}" Width="*"/>
                                </DataGrid.Columns>
                            </DataGrid>
                            
                            <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Bottom" Margin="5">
                                <Button Content="Save Changes" Name="BtnSaveProperties" Height="30" Width="120" Background="#28a745" Foreground="White" Margin="5,0"/>
                                <Button Content="Reset" Name="BtnResetProperties" Height="30" Width="80" Margin="5,0"/>
                            </StackPanel>
                        </Grid>
                    </TabItem>
                </TabControl>
            </Grid>
        </TabItem>

        <TabItem Header="Boot Menu Simulator">
            <StackPanel Background="#003366" Margin="10">
                <TextBlock Text="Windows Boot Manager" Foreground="White" FontSize="22" HorizontalAlignment="Center" Margin="20"/>
                <TextBlock Text="Choose an operating system to start:" Foreground="White" Margin="40,0,0,10"/>
                <ListBox Name="SimList" Height="200" Width="500" Background="#003366" Foreground="White" BorderThickness="0" FontSize="18" Padding="20">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <TextBlock Text="{Binding}"/>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
                <TextBlock Name="SimTimeout" Text="Seconds until auto-start: 30" Foreground="White" HorizontalAlignment="Center" Margin="20"/>
                <TextBlock Text="Use the BCD Editor tab to modify these entries." Foreground="#CCC" FontSize="10" HorizontalAlignment="Center"/>
</StackPanel>
</TabItem>

        <TabItem Header="Driver Diagnostics">
            <DockPanel Margin="10">
                <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
                    <Button Content="Scan for Driver Errors" Height="35" Name="BtnDetect" Background="#dc3545" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Scan for Missing Drivers" Height="35" Name="BtnScanDrivers" Background="#28a745" Foreground="White" Width="200" Margin="0,0,10,0"/>
                    <Button Content="Scan All Drivers" Height="35" Name="BtnScanAllDrivers" Background="#17a2b8" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <ComboBox Name="DriveCombo" Width="100" Height="35" VerticalContentAlignment="Center"/>
                    <Button Content="Install Drivers" Height="35" Name="BtnInstallDrivers" Background="#6c757d" Foreground="White" Width="120" Margin="10,0,0,0" IsEnabled="False"/>
                </StackPanel>
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <TextBox Name="DrvBox" AcceptsReturn="True" VerticalScrollBarVisibility="Disabled" FontFamily="Consolas" Background="White" Foreground="Black" TextWrapping="Wrap" IsReadOnly="True"/>
                </ScrollViewer>
            </DockPanel>
        </TabItem>

        <TabItem Header="Boot Fixer">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Margin="0,0,0,10">
                    <CheckBox Name="ChkTestMode" Content="Test Mode (Preview commands only - will not execute)" IsChecked="True" FontWeight="Bold" Foreground="#d78700" Margin="5"/>
                    <TextBlock Text="When Test Mode is enabled, commands are displayed but not executed. Uncheck to apply fixes." Foreground="Gray" Margin="5,0,0,5" TextWrapping="Wrap"/>
                </StackPanel>
                
                <GroupBox Grid.Row="1" Header="Boot Repair Operations" Margin="5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
<StackPanel Margin="10">
                            <Button Content="1. Rebuild BCD from Windows Installation" Height="40" Name="BtnRebuildBCD" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,5"/>
                            <TextBlock Name="TxtRebuildBCD" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="2. Fix Boot Files (bootrec /fixboot)" Height="40" Name="BtnFixBoot" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtFixBoot" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="3. Scan for Windows Installations" Height="40" Name="BtnScanWindows" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtScanWindows" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="4. Rebuild BCD (bootrec /rebuildbcd)" Height="40" Name="BtnRebuildBCD2" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtRebuildBCD2" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="5. Set Default Boot Entry" Height="40" Name="BtnSetDefaultBoot" Background="#0078D7" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtSetDefault" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to see command and explanation"/>
                            
                            <Button Content="6. Boot Diagnosis" Height="40" Name="BtnBootDiagnosis" Background="#28a745" Foreground="White" FontWeight="Bold" Margin="0,10,0,5"/>
                            <TextBlock Name="TxtBootDiagnosis" TextWrapping="Wrap" Margin="10,5" Foreground="Gray" FontSize="11" Text="Click to run comprehensive boot diagnosis"/>
</StackPanel>
                    </ScrollViewer>
                </GroupBox>
                
                <GroupBox Grid.Row="2" Header="Command Output" Margin="5,10,5,5">
                    <ScrollViewer Height="150" VerticalScrollBarVisibility="Auto">
                        <TextBox Name="FixerOutput" AcceptsReturn="True" FontFamily="Consolas" Background="#222" Foreground="#00FF00" IsReadOnly="True" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </GroupBox>
            </Grid>
</TabItem>

        <TabItem Header="Diagnostics">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                    <TextBlock Text="Target Drive:" VerticalAlignment="Center" Margin="0,0,10,0" FontWeight="Bold"/>
                    <ComboBox Name="DiagDriveCombo" Width="120" Height="30" VerticalContentAlignment="Center" Margin="0,0,20,0"/>
                    <TextBlock Name="CurrentOSLabel" Text="" VerticalAlignment="Center" Foreground="#28a745" FontWeight="Bold" Margin="0,0,10,0"/>
                </StackPanel>
                
                <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
                    <Button Content="Check System Restore" Height="35" Name="BtnCheckRestore" Background="#28a745" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Create Restore Point" Height="35" Name="BtnCreateRestorePoint" Background="#6f42c1" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="List Restore Points" Height="35" Name="BtnListRestorePoints" Background="#17a2b8" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Check Reagentc Health" Height="35" Name="BtnCheckReagentc" Background="#0078D7" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Get OS Information" Height="35" Name="BtnGetOSInfo" Background="#6f42c1" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Install Failure Analysis" Height="35" Name="BtnInstallFailure" Background="#dc3545" Foreground="White" Width="200"/>
</StackPanel>
                
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                    <TextBox Name="DiagBox" AcceptsReturn="True" VerticalScrollBarVisibility="Disabled" FontFamily="Consolas" Background="White" Foreground="Black" TextWrapping="Wrap" IsReadOnly="True" Padding="10"/>
                </ScrollViewer>
            </Grid>
</TabItem>

        <TabItem Header="Diagnostics &amp; Logs">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Margin="0,0,0,10">
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                        <TextBlock Text="Target Drive:" VerticalAlignment="Center" Margin="0,0,10,0" FontWeight="Bold"/>
                        <ComboBox Name="LogDriveCombo" Width="120" Height="30" VerticalContentAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <Button Content="Driver Forensics" Height="35" Name="BtnDriverForensics" Background="#dc3545" Foreground="White" Width="150" Margin="0,0,10,0"/>
                        <Button Content="Analyze Boot Log" Height="35" Name="BtnAnalyzeBootLog" Background="#dc3545" Foreground="White" Width="150" Margin="0,0,10,0"/>
                        <Button Content="Analyze Event Logs" Height="35" Name="BtnAnalyzeEventLogs" Background="#17a2b8" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <Button Content="Full Boot Diagnosis" Height="35" Name="BtnFullBootDiagnosis" Background="#28a745" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <Button Content="Hardware Support" Height="35" Name="BtnHardwareSupport" Background="#6f42c1" Foreground="White" Width="150" Margin="0,0,10,0"/>
                    <Button Content="Unofficial Repair Tips" Height="35" Name="BtnRepairTips" Background="#ffc107" Foreground="Black" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Generate Registry Override Script" Height="35" Name="BtnGenRegScript" Background="#dc3545" Foreground="White" Width="220" Margin="0,0,10,0"/>
                    <Button Content="One-Click Registry Fixes" Height="35" Name="BtnOneClickFix" Background="#28a745" Foreground="White" Width="200" Margin="0,0,10,0"/>
                    <Button Content="Filter Driver Forensics" Height="35" Name="BtnFilterForensics" Background="#17a2b8" Foreground="White" Width="180" Margin="0,0,10,0"/>
                    <Button Content="Recommended Tools" Height="35" Name="BtnRecommendedTools" Background="#6c757d" Foreground="White" Width="160" Margin="0,0,10,0"/>
                        <Button Content="Export In-Use Drivers" Height="35" Name="BtnExportDrivers" Background="#28a745" Foreground="White" Width="180" Margin="0,0,10,0"/>
                        <Button Content="Generate Cleanup Script" Height="35" Name="BtnGenCleanupScript" Background="#ffc107" Foreground="Black" Width="180" Margin="0,0,10,0"/>
                        <Button Content="In-Place Upgrade Readiness" Height="35" Name="BtnInPlaceReadiness" Background="#dc3545" Foreground="White" Width="200" Margin="0,0,10,0"/>
                        <Button Content="Ensure Repair-Install Ready" Height="35" Name="BtnRepairInstallReady" Background="#dc3545" Foreground="White" Width="220" Margin="0,0,10,0"/>
                        <Button Content="Repair Templates" Height="35" Name="BtnRepairTemplates" Background="#6f42c1" Foreground="White" Width="180"/>
                    </StackPanel>
                </StackPanel>
                
                <TextBlock Grid.Row="1" Text="Offline log analysis from target Windows drive. Driver Forensics identifies missing storage drivers and required INF files. Hardware Support shows manufacturer links and driver update alerts." 
                           FontStyle="Italic" Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,10"/>
                
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                    <TextBox Name="LogAnalysisBox" AcceptsReturn="True" VerticalScrollBarVisibility="Disabled" FontFamily="Consolas" Background="White" Foreground="Black" TextWrapping="Wrap" IsReadOnly="True" Padding="10"/>
                </ScrollViewer>
            </Grid>
        </TabItem>
        
        <TabItem Header="Repair Install Forcer">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <StackPanel Grid.Row="0" Margin="0,0,0,10">
                    <TextBlock Text="Force Windows to perform a repair-only in-place upgrade from ISO" FontWeight="Bold" FontSize="14" Margin="0,0,0,10"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                        <RadioButton Name="RbOnlineMode" Content="Online Mode (Running Windows)" IsChecked="True" Margin="0,0,20,0"/>
                        <RadioButton Name="RbOfflineMode" Content="Offline Mode (Non-Booting PC - WinPE/WinRE)" Foreground="#d78700"/>
                    </StackPanel>
                    <TextBlock Name="RepairModeDescription" Text="This forces Setup to reinstall system files while keeping apps and data. Requires same edition, architecture, and build family. Must run from inside Windows." 
                               Foreground="Gray" TextWrapping="Wrap" Margin="0,0,0,10"/>
                </StackPanel>
                
                <GroupBox Grid.Row="1" Header="ISO Selection &amp; Options" Margin="5">
                    <StackPanel Margin="10">
                        <StackPanel Orientation="Horizontal" Margin="0,5" Name="OfflineDrivePanel" Visibility="Collapsed">
                            <TextBlock Text="Offline Windows Drive:" VerticalAlignment="Center" Width="180" Margin="0,0,10,0"/>
                            <ComboBox Name="RepairOfflineDrive" Width="100" Height="25" VerticalContentAlignment="Center" Margin="0,0,10,0"/>
                            <TextBlock Text="(Drive letter where Windows is installed)" Foreground="Gray" VerticalAlignment="Center" FontStyle="Italic"/>
                        </StackPanel>
                        
                        <StackPanel Orientation="Horizontal" Margin="0,5">
                            <TextBlock Text="ISO/Mounted Folder Path:" VerticalAlignment="Center" Width="180" Margin="0,0,10,0"/>
                            <TextBox Name="RepairISOPath" Width="400" Height="25" VerticalContentAlignment="Center" Margin="0,0,10,0"/>
                            <Button Content="Browse..." Name="BtnBrowseISO" Width="80" Height="25"/>
                        </StackPanel>
                        
                        <StackPanel Orientation="Horizontal" Margin="0,10,0,5">
                            <CheckBox Name="ChkSkipCompat" Content="Skip Compatibility Checks" IsChecked="True" Margin="0,0,20,0"/>
                            <CheckBox Name="ChkDisableDynamicUpdate" Content="Disable Dynamic Update" IsChecked="True" Margin="0,0,20,0"/>
                            <CheckBox Name="ChkForceEdition" Content="Force Edition Alignment" IsChecked="False"/>
                        </StackPanel>
                        
                        <StackPanel Orientation="Horizontal" Margin="0,10,0,5">
                            <Button Content="Check Prerequisites" Name="BtnCheckPrereq" Background="#17a2b8" Foreground="White" Width="150" Height="35" Margin="0,0,10,0"/>
                            <Button Content="Show Instructions" Name="BtnShowInstructions" Background="#6c757d" Foreground="White" Width="150" Height="35" Margin="0,0,10,0"/>
                            <Button Content="Start Repair Install" Name="BtnStartRepair" Background="#28a745" Foreground="White" Width="150" Height="35" FontWeight="Bold"/>
                        </StackPanel>
                    </StackPanel>
                </GroupBox>
                
                <GroupBox Grid.Row="2" Header="Status &amp; Output" Margin="5,10,5,5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <TextBox Name="RepairInstallOutput" AcceptsReturn="True" FontFamily="Consolas" Background="#222" Foreground="#00FF00" IsReadOnly="True" TextWrapping="Wrap" Padding="10"/>
                    </ScrollViewer>
                </GroupBox>
                
                <TextBlock Grid.Row="3" Text="Note: This will launch Windows Setup and restart your system. Ensure you have backups and BitLocker recovery key if applicable." 
                           Foreground="#d78700" FontStyle="Italic" TextWrapping="Wrap" Margin="5,10,5,0"/>
            </Grid>
        </TabItem>
</TabControl>
    
    <!-- Status Bar -->
    <StatusBar Grid.Row="2" Background="#E5E5E5" Height="25">
        <StatusBar.ItemsPanel>
            <ItemsPanelTemplate>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                </Grid>
            </ItemsPanelTemplate>
        </StatusBar.ItemsPanel>
        <StatusBarItem Grid.Column="0">
            <TextBlock Name="StatusBarText" Text="Ready" VerticalAlignment="Center" Margin="5,0"/>
        </StatusBarItem>
        <StatusBarItem Grid.Column="1">
            <StackPanel Orientation="Horizontal" Margin="5,0">
                <TextBlock Name="StatusBarProgress" Text="" VerticalAlignment="Center" Margin="0,0,10,0" Foreground="#0078D7" FontWeight="Bold"/>
                <ProgressBar Name="StatusBarProgressBar" Width="100" Height="15" Visibility="Collapsed" IsIndeterminate="True"/>
            </StackPanel>
        </StatusBarItem>
    </StatusBar>
</Grid>
</Window>
"@

$W=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$XAML)))

# Detect environment
$envType = "FullOS"
if (Test-Path 'HKLM:\System\CurrentControlSet\Control\MiniNT') { $envType = "WinRE" }
if ($env:SystemDrive -eq 'X:') { $envType = "WinRE" }
$W.FindName("EnvStatus").Text = "Environment: $envType"

# Utility buttons
$W.FindName("BtnNotepad").Add_Click({
    try {
        Start-Process notepad.exe -ErrorAction SilentlyContinue
    } catch {
        [System.Windows.MessageBox]::Show("Notepad not available in this environment.", "Warning", "OK", "Warning")
    }
})

$W.FindName("BtnRegistry").Add_Click({
    try {
        Start-Process regedit.exe -ErrorAction SilentlyContinue
    } catch {
        [System.Windows.MessageBox]::Show("Registry Editor not available in this environment.", "Warning", "OK", "Warning")
    }
})

$W.FindName("BtnPowerShell").Add_Click({
    try {
        Start-Process powershell.exe -ErrorAction SilentlyContinue
    } catch {
        [System.Windows.MessageBox]::Show("PowerShell not available.", "Error", "OK", "Error")
    }
})

$W.FindName("BtnDiskManagement").Add_Click({
    try {
        Start-Process diskmgmt.msc -ErrorAction Stop
    } catch {
        [System.Windows.MessageBox]::Show("Disk Management not available in this environment.", "Warning", "OK", "Warning")
    }
})

$W.FindName("BtnRestore").Add_Click({
    # Switch to Diagnostics tab and run System Restore check
    try {
        $grid = $W.Content
        $tabControl = $grid.Children | Where-Object { $_.GetType().Name -eq 'TabControl' } | Select-Object -First 1
        
        if ($tabControl) {
            $diagTab = $tabControl.Items | Where-Object { $_.Header -eq "Diagnostics" }
            if ($diagTab) {
                $tabControl.SelectedItem = $diagTab
                # Use dispatcher to ensure UI is updated before triggering button
                $W.Dispatcher.Invoke([action]{
                    $W.FindName("BtnCheckRestore").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                }, [System.Windows.Threading.DispatcherPriority]::Input)
            }
        }
    } catch {
        # Fallback: show message directing user to Diagnostics tab
        [System.Windows.MessageBox]::Show("Please navigate to the Diagnostics tab and click 'Check System Restore' to view restore points.", "Info", "OK", "Information")
    }
})

# Network enablement button
$W.FindName("BtnEnableNetwork").Add_Click({
    try {
        Update-StatusBar -Message "Enabling network adapters..." -ShowProgress
        $result = Enable-NetworkWinRE
        
        if ($result.Success) {
            $W.FindName("NetworkStatus").Text = "Network: Enabled"
            $W.FindName("NetworkStatus").Foreground = "Green"
            
            # Test internet connectivity
            Update-StatusBar -Message "Testing internet connectivity..." -ShowProgress
            $internetTest = Test-InternetConnectivity
            
            if ($internetTest.Connected) {
                $W.FindName("NetworkStatus").Text = "Network: Connected"
                [System.Windows.MessageBox]::Show("Network enabled successfully!`n`n$($result.Message)`n`n$($internetTest.Message)", "Network Enabled", "OK", "Information")
            } else {
                $W.FindName("NetworkStatus").Text = "Network: No Internet"
                $W.FindName("NetworkStatus").Foreground = "Orange"
                [System.Windows.MessageBox]::Show("Network adapters enabled, but no internet connectivity detected.`n`n$($result.Message)`n`n$($internetTest.Message)", "Network Enabled (No Internet)", "OK", "Warning")
            }
        } else {
            $W.FindName("NetworkStatus").Text = "Network: Failed"
            $W.FindName("NetworkStatus").Foreground = "Red"
            [System.Windows.MessageBox]::Show("Failed to enable network:`n`n$($result.Message)", "Network Error", "OK", "Error")
        }
        Update-StatusBar -Message "Network operation complete" -HideProgress
    } catch {
        Update-StatusBar -Message "Network operation failed: $_" -HideProgress
        [System.Windows.MessageBox]::Show("Error enabling network: $_", "Error", "OK", "Error")
    }
})

# ChatGPT Help button
$W.FindName("BtnNetworkDiagnostics").Add_Click({
    try {
        if (Get-Command Invoke-NetworkDiagnostics -ErrorAction SilentlyContinue) {
            Update-StatusBar -Message "Running network diagnostics..." -ShowProgress
            
            # Switch to Diagnostics tab if available
            $grid = $W.Content
            $tabControl = $grid.Children | Where-Object { $_.GetType().Name -eq 'TabControl' } | Select-Object -First 1
            
            if ($tabControl) {
                $diagTab = $tabControl.Items | Where-Object { $_.Header -eq "Diagnostics" }
                if ($diagTab) {
                    $tabControl.SelectedItem = $diagTab
                }
            }
            
            $result = Invoke-NetworkDiagnostics
            $W.FindName("DiagBox").Text = $result.Report
            Update-StatusBar -Message "Network diagnostics complete" -HideProgress
        } else {
            [System.Windows.MessageBox]::Show(
                "Network Diagnostics module not available.`n`nThis feature requires NetworkDiagnostics.ps1 to be loaded.",
                "Module Not Available",
                "OK",
                "Warning"
            )
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error running network diagnostics: $_", "Error", "OK", "Error")
        Update-StatusBar -Message "Network diagnostics failed" -HideProgress
    }
})

$W.FindName("BtnKeyboardSymbols").Add_Click({
    try {
        if (Get-Command Show-SymbolHelperGUI -ErrorAction SilentlyContinue) {
            Show-SymbolHelperGUI
        } elseif (Get-Command Show-SymbolHelper -ErrorAction SilentlyContinue) {
            # Fallback to console version
            Show-SymbolHelper
        } else {
            [System.Windows.MessageBox]::Show(
                "Keyboard Symbol Helper not available.`n`nThis feature requires KeyboardSymbols.ps1 to be loaded.",
                "Module Not Available",
                "OK",
                "Warning"
            )
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error launching keyboard symbol helper: $_", "Error", "OK", "Error")
    }
})

$W.FindName("BtnChatGPT").Add_Click({
    try {
        Update-StatusBar -Message "Opening ChatGPT help..." -ShowProgress
        $result = Open-ChatGPTHelp
        
        if ($result.Success) {
            Update-StatusBar -Message $result.Message -HideProgress
            [System.Windows.MessageBox]::Show($result.Message, "ChatGPT Help", "OK", "Information")
        } else {
            Update-StatusBar -Message "Browser not available" -HideProgress
            # Show instructions in a message box
            $instructionsWindow = New-Object System.Windows.Window
            $instructionsWindow.Title = "ChatGPT Help - Instructions"
            $instructionsWindow.Width = 600
            $instructionsWindow.Height = 500
            $instructionsWindow.WindowStartupLocation = "CenterScreen"
            
            $textBlock = New-Object System.Windows.Controls.TextBlock
            $textBlock.Text = $result.Instructions
            $textBlock.TextWrapping = "Wrap"
            $textBlock.Margin = "10"
            $textBlock.FontFamily = "Consolas"
            $textBlock.FontSize = "11"
            
            $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
            $scrollViewer.Content = $textBlock
            $scrollViewer.VerticalScrollBarVisibility = "Auto"
            
            $instructionsWindow.Content = $scrollViewer
            $instructionsWindow.ShowDialog() | Out-Null
        }
    } catch {
        Update-StatusBar -Message "Error opening ChatGPT: $_" -HideProgress
        [System.Windows.MessageBox]::Show("Error opening ChatGPT help: $_", "Error", "OK", "Error")
    }
})

# Initialize network status
try {
    $internetTest = Test-InternetConnectivity -TimeoutSeconds 2
    if ($internetTest.Connected) {
        $W.FindName("NetworkStatus").Text = "Network: Connected"
        $W.FindName("NetworkStatus").Foreground = "Green"
    } else {
        $W.FindName("NetworkStatus").Text = "Network: Unknown"
        $W.FindName("NetworkStatus").Foreground = "Gray"
    }
} catch {
    $W.FindName("NetworkStatus").Text = "Network: Unknown"
    $W.FindName("NetworkStatus").Foreground = "Gray"
}

# Populate drive combo
$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemLabel } | Sort-Object DriveLetter
$W.FindName("DriveCombo").Items.Clear()
$W.FindName("DriveCombo").Items.Add("Auto-detect")
foreach ($vol in $volumes) {
    $W.FindName("DriveCombo").Items.Add("$($vol.DriveLetter): - $($vol.FileSystemLabel)")
}
$W.FindName("DriveCombo").SelectedIndex = 0

# Populate log drive combo (for Diagnostics & Logs tab)
$W.FindName("LogDriveCombo").Items.Clear()
$W.FindName("LogDriveCombo").Items.Add("C:")
foreach ($vol in $volumes) {
    if ($vol.DriveLetter -ne "C") {
        $W.FindName("LogDriveCombo").Items.Add("$($vol.DriveLetter):")
    }
}
$W.FindName("LogDriveCombo").SelectedIndex = 0

# Populate Diagnostics drive combo
$W.FindName("DiagDriveCombo").Items.Clear()
$currentSystemDrive = $env:SystemDrive.TrimEnd(':')
$W.FindName("DiagDriveCombo").Items.Add("$currentSystemDrive`: (Current OS)")
foreach ($vol in $volumes) {
    if ($vol.DriveLetter -ne $currentSystemDrive) {
        $W.FindName("DiagDriveCombo").Items.Add("$($vol.DriveLetter):")
    }
}
$W.FindName("DiagDriveCombo").SelectedIndex = 0

# Update current OS label
function Update-CurrentOSLabel {
    $selected = $W.FindName("DiagDriveCombo").SelectedItem
    $drive = $currentSystemDrive
    if ($selected) {
        if ($selected -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    if ($drive -eq $currentSystemDrive) {
        $W.FindName("CurrentOSLabel").Text = "[OK] This is the CURRENT OS (running from $currentSystemDrive`:)"
    } else {
        $W.FindName("CurrentOSLabel").Text = "[OFFLINE] This is an OFFLINE OS (not currently running)"
    }
}
Update-CurrentOSLabel
$W.FindName("DiagDriveCombo").Add_SelectionChanged({ Update-CurrentOSLabel })

# Logic for Volumes
$W.FindName("BtnVol").Add_Click({
    $vols = Get-WindowsVolumes
    $W.FindName("VolList").ItemsSource = $vols
})

# Store BCD entries globally for real-time updates
$script:BCDEntriesCache = $null

# Helper function to update status bar
function Update-StatusBar {
    param(
        [string]$Message = "Ready",
        [switch]$ShowProgress,
        [switch]$HideProgress
    )
    
    $W.FindName("StatusBarText").Text = $Message
    
    if ($ShowProgress) {
        $W.FindName("StatusBarProgressBar").Visibility = "Visible"
        $W.FindName("StatusBarProgress").Text = "Working..."
    } elseif ($HideProgress) {
        $W.FindName("StatusBarProgressBar").Visibility = "Collapsed"
        $W.FindName("StatusBarProgress").Text = ""
    }
}

# Helper function to get default boot entry GUID
function Get-BCDDefaultEntryId {
    try {
        # Get the default entry from Windows Boot Manager
        $bootMgrOutput = bcdedit /enum {bootmgr} 2>&1
        if ($bootMgrOutput -match 'default\s+(\{[0-9A-F-]+\})') {
            return $matches[1]
        }
        # Alternative: check for {default} identifier directly in enum output
        $enumOutput = bcdedit /enum 2>&1
        if ($enumOutput -match 'identifier\s+(\{default\})') {
            return "{default}"
        }
        return $null
    } catch {
        return $null
    }
}

# Logic for BCD - Enhanced parser with duplicate detection
$W.FindName("BtnBCD").Add_Click({
    try {
        # Force UI update immediately
        $W.Dispatcher.Invoke([action]{
            Update-StatusBar -Message "Loading BCD Entries..." -ShowProgress
        }, [System.Windows.Threading.DispatcherPriority]::Render)
        [System.Windows.Forms.Application]::DoEvents()
        
        $rawBcd = bcdedit /enum
        $W.FindName("BCDBox").Text = $rawBcd
        
        $W.Dispatcher.Invoke([action]{
            Update-StatusBar -Message "Parsing BCD entries..." -ShowProgress
        }, [System.Windows.Threading.DispatcherPriority]::Render)
        [System.Windows.Forms.Application]::DoEvents()
        
        # Get default boot entry ID
        $defaultEntryId = Get-BCDDefaultEntryId
        
        # Parse BCD entries with full properties
        $entries = Get-BCDEntriesParsed
        $script:BCDEntriesCache = $entries
        
        $W.Dispatcher.Invoke([action]{
            Update-StatusBar -Message "Processing boot entries..." -ShowProgress
        }, [System.Windows.Threading.DispatcherPriority]::Render)
        [System.Windows.Forms.Application]::DoEvents()
        
        $bcdItems = @()
        foreach ($entry in $entries) {
            $displayText = if ($entry.Description) { $entry.Description } else { $entry.Id }
            
            # Mark default entry
            $isDefault = $false
            if ($defaultEntryId) {
                # Check if this entry's ID matches the default (handle both GUID and {default})
                if ($entry.Id -eq $defaultEntryId -or 
                    ($defaultEntryId -eq "{default}" -and $entry.Id -match '\{default\}')) {
                    $isDefault = $true
                    $displayText = "[DEFAULT] $displayText"
                }
            }
            
            $bcdItems += [PSCustomObject]@{
                Id = $entry.Id
                Description = $entry.Description
                DisplayText = $displayText
                Device = $entry.Device
                Path = $entry.Path
                EntryObject = $entry
                IsDefault = $isDefault
            }
        }
        
        $W.Dispatcher.Invoke([action]{
            Update-StatusBar -Message "Updating BCD list..." -ShowProgress
        }, [System.Windows.Threading.DispatcherPriority]::Render)
        [System.Windows.Forms.Application]::DoEvents()
        
        $W.FindName("BCDList").ItemsSource = $bcdItems
        
        # Update Simulator in real-time
        Update-BootMenuSimulator $bcdItems
        
        $timeout = Get-BCDTimeout
        $W.FindName("TxtTimeout").Text = $timeout
        $W.FindName("SimTimeout").Text = "Seconds until auto-start: $timeout"
        
        $W.Dispatcher.Invoke([action]{
            Update-StatusBar -Message "Checking for duplicate entries..." -ShowProgress
        }, [System.Windows.Threading.DispatcherPriority]::Render)
        [System.Windows.Forms.Application]::DoEvents()
        
        # Check for duplicates
        $duplicates = Find-DuplicateBCEEntries
        if ($duplicates) {
            $dupNames = ($duplicates | ForEach-Object { "'$($_.Name)'" }) -join ", "
            $result = [System.Windows.MessageBox]::Show(
                "Found duplicate boot entry names: $dupNames`n`nWould you like to automatically rename them by appending volume labels?",
                "Duplicate Entries Detected",
                "YesNo",
                "Question"
            )
            if ($result -eq "Yes") {
                $fixed = Fix-DuplicateBCEEntries -AppendVolumeLabels
                if ($fixed.Count -gt 0) {
                    [System.Windows.MessageBox]::Show("Fixed $($fixed.Count) duplicate entry name(s).", "Success", "OK", "Information")
                    # Reload BCD
                    $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                    return
                }
            }
        }
        
        $defaultCount = ($bcdItems | Where-Object { $_.IsDefault }).Count
        $statusMsg = "Loaded $($bcdItems.Count) BCD entries"
        if ($defaultCount -gt 0) {
            $statusMsg += " (1 default entry marked)"
        }
        Update-StatusBar -Message $statusMsg -HideProgress
        
        if (-not $duplicates) {
            [System.Windows.MessageBox]::Show("Loaded $($bcdItems.Count) BCD entries." + $(if ($defaultCount -gt 0) { "`n`nDefault boot entry is marked with [DEFAULT]." } else { "" }), "Success", "OK", "Information")
        }
    } catch {
        Update-StatusBar -Message "Error loading BCD: $_" -HideProgress
        [System.Windows.MessageBox]::Show("Error loading BCD: $_", "Error", "OK", "Error")
    }
})

# Helper function to update Boot Menu Simulator
function Update-BootMenuSimulator {
    param($Items)
    $W.FindName("SimList").Items.Clear()
    foreach ($item in $Items) {
        if ($item.Description) {
            $W.FindName("SimList").Items.Add($item.Description)
        }
    }
}

# BCD List selection - populate both basic and advanced editors
$W.FindName("BCDList").Add_SelectionChanged({
    $selected = $W.FindName("BCDList").SelectedItem
    if ($selected) {
        $W.FindName("EditId").Text = $selected.Id
        $W.FindName("EditDescription").Text = $selected.Description
        $W.FindName("EditName").Text = $selected.Description
        
        # Populate Advanced Properties Grid
        if ($selected.EntryObject) {
            $properties = @()
            foreach ($key in $selected.EntryObject.Keys) {
                if ($key -ne 'Id' -and $key -ne 'EntryType') {
                    $properties += [PSCustomObject]@{
                        Name = $key
                        Value = $selected.EntryObject[$key]
                    }
                }
            }
            $W.FindName("BCDPropertiesGrid").ItemsSource = $properties
        }
    }
})

# BCD Backup button
$W.FindName("BtnBCDBackup").Add_Click({
    try {
        $backup = Export-BCDBackup
        if ($backup.Success) {
            [System.Windows.MessageBox]::Show("BCD backup created successfully!`n`nLocation: $($backup.Path)", "Backup Complete", "OK", "Information")
        } else {
            [System.Windows.MessageBox]::Show("Failed to create backup: $($backup.Error)", "Error", "OK", "Error")
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error creating backup: $_", "Error", "OK", "Error")
    }
})

# Fix Duplicates button
$W.FindName("BtnFixDuplicates").Add_Click({
    $duplicates = Find-DuplicateBCEEntries
    if ($duplicates -and $duplicates.Count -gt 0) {
        $dupList = ""
        foreach ($dup in $duplicates) {
            $dupList += "`n- '$($dup.Name)' (appears $($dup.Count) times)"
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Found duplicate boot entry names:$dupList`n`nHow would you like to fix them?`n`nYes = Append Volume Labels (Recommended)`nNo = Append Entry Numbers`nCancel = Skip",
            "Fix Duplicate Entries",
            "YesNoCancel",
            "Question"
        )
        if ($result -eq "Yes") {
            $fixed = Fix-DuplicateBCEEntries -AppendVolumeLabels
            if ($fixed.Count -gt 0) {
                [System.Windows.MessageBox]::Show("Fixed $($fixed.Count) duplicate entry name(s).", "Success", "OK", "Information")
                $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            }
        } elseif ($result -eq "No") {
            $fixed = Fix-DuplicateBCEEntries
            if ($fixed.Count -gt 0) {
                [System.Windows.MessageBox]::Show("Fixed $($fixed.Count) duplicate entry name(s).", "Success", "OK", "Information")
                $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            }
        }
    } else {
        [System.Windows.MessageBox]::Show(
            "No duplicate boot entry names found.`n`nAll Windows Boot Loader entries have unique names.`n`n(Note: System entries like 'Windows Boot Manager' are excluded from duplicate checking.)",
            "No Duplicates",
            "OK",
            "Information"
        )
    }
})

# Sync BCD to All EFI Partitions
$W.FindName("BtnSyncBCD").Add_Click({
    $selectedDrive = $W.FindName("DriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $result = [System.Windows.MessageBox]::Show(
        "This will synchronize the BCD configuration to ALL EFI System Partitions on all drives.`n`nThis ensures the same boot menu appears regardless of which drive the BIOS boots from.`n`nSource: $drive`:\Windows`n`nContinue?",
        "Synchronize BCD to All EFI Partitions",
        "YesNo",
        "Question"
    )
    
    if ($result -eq "Yes") {
        try {
            $W.FindName("FixerOutput").Text = "Synchronizing BCD to all EFI partitions...`n"
            $syncResult = Sync-BCDToAllEFIPartitions -SourceWindowsDrive $drive
            
            $output = "Synchronization Complete`n"
            $output += "===============================================================`n"
            $output += "$($syncResult.Message)`n`n"
            
            foreach ($res in $syncResult.Results) {
                if ($res.Success) {
                    $output += "[SUCCESS] Drive $($res.Drive): Synced successfully`n"
                } else {
                    $output += "[FAILED] Drive $($res.Drive): $($res.Error)`n"
                }
            }
            
            $W.FindName("FixerOutput").Text = $output
            [System.Windows.MessageBox]::Show($syncResult.Message, "Synchronization Complete", "OK", "Information")
        } catch {
            [System.Windows.MessageBox]::Show("Error during synchronization: $_", "Error", "OK", "Error")
        }
    }
})

# Boot Diagnosis button (Boot Fixer tab)
$W.FindName("BtnBootDiagnosis").Add_Click({
    $selectedDrive = $W.FindName("DriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $diagnosis = Get-BootDiagnosis -TargetDrive $drive
    $W.FindName("FixerOutput").Text = $diagnosis
    
    # Switch to Boot Fixer tab to show the output
    $bootFixerTab = $W.FindName("TabControl").Items | Where-Object { $_.Header -eq "Boot Fixer" }
    if ($bootFixerTab) {
        $W.FindName("TabControl").SelectedItem = $bootFixerTab
    }
    
    [System.Windows.MessageBox]::Show(
        "Boot diagnosis complete.`n`nResults are displayed in the 'Boot Fixer' tab below.`n`nScroll down in the output box to see the full diagnosis report.",
        "Diagnosis Complete",
        "OK",
        "Information"
    )
})

# Boot Diagnosis button (BCD Editor tab)
$W.FindName("BtnBootDiagnosisBCD").Add_Click({
    $selectedDrive = $W.FindName("DriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $diagnosis = Get-BootDiagnosis -TargetDrive $drive
    $W.FindName("BCDBox").Text = $diagnosis
    
    [System.Windows.MessageBox]::Show(
        "Boot diagnosis complete.`n`nResults are displayed in the BCD output box below.",
        "Diagnosis Complete",
        "OK",
        "Information"
    )
})

# Update BCD Description with backup and BitLocker check
$W.FindName("BtnUpdateBcd").Add_Click({
    $id = $W.FindName("EditId").Text
    $name = $W.FindName("EditName").Text
    if ($id -and $name) {
        # Show comprehensive warning
        $warningInfo = Show-CommandWarning -CommandKey "bcd_description" -Command "Set-BCDDescription $id $name" -Description "Change BCD entry description" -IsGUI
        
        $warningMsg = "$($warningInfo.Message)`n`nDo you want to proceed?"
        $result = [System.Windows.MessageBox]::Show(
            $warningMsg,
            $warningInfo.Title,
            "YesNo",
            $(if ($warningInfo.RiskLevel -eq "Critical") { "Error" } elseif ($warningInfo.RiskLevel -eq "High") { "Warning" } else { "Question" })
        )
        
        if ($result -eq "No") {
            return
        }
        
        # BitLocker Safety Check
        $bitlocker = Test-BitLockerStatus -TargetDrive "C"
        if ($bitlocker.IsEncrypted) {
            $result = [System.Windows.MessageBox]::Show(
                "$($bitlocker.Warning)`n`nDo you have your BitLocker recovery key available?`n`nClick 'Yes' to proceed anyway, or 'No' to cancel.",
                "BitLocker Encryption Detected",
                "YesNo",
                "Warning"
            )
            if ($result -eq "No") {
                return
            }
        }
        
        # Create backup first
        $backup = Export-BCDBackup
        if ($backup.Success) {
            Set-BCDDescription $id $name
            [System.Windows.MessageBox]::Show("Entry Updated!`n`nBackup saved to: $($backup.Path)", "Success", "OK", "Information")
            
            # Update simulator in real-time
            $selected = $W.FindName("BCDList").SelectedItem
            if ($selected) {
                $selected.Description = $name
                $selected.DisplayText = $name
                $W.FindName("BCDList").Items.Refresh()
                Update-BootMenuSimulator ($W.FindName("BCDList").ItemsSource)
            }
            
            $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
        } else {
            [System.Windows.MessageBox]::Show("Failed to create backup. Update cancelled for safety.", "Error", "OK", "Error")
        }
    }
})

# Save Advanced Properties
$W.FindName("BtnSaveProperties").Add_Click({
    $selected = $W.FindName("BCDList").SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show("Please select a BCD entry first.", "Warning", "OK", "Warning")
        return
    }
    
    $properties = $W.FindName("BCDPropertiesGrid").ItemsSource
    if (-not $properties) { return }
    
    # Create backup first
    $backup = Export-BCDBackup
    if (-not $backup.Success) {
        [System.Windows.MessageBox]::Show("Failed to create backup. Changes cancelled for safety.", "Error", "OK", "Error")
        return
    }
    
    try {
        foreach ($prop in $properties) {
            if ($prop.Name -and $prop.Value) {
                # Validate path/device if applicable
                if ($prop.Name -match 'path|device' -and $prop.Value) {
                    $isValid = Test-BCDPath -Path $prop.Value -Device $selected.Device
                    if (-not $isValid -and $prop.Name -eq 'path') {
                        $result = [System.Windows.MessageBox]::Show(
                            "Warning: The path '$($prop.Value)' may not exist. Continue anyway?",
                            "Path Validation",
                            "YesNo",
                            "Warning"
                        )
                        if ($result -eq "No") { continue }
                    }
                }
                
                Set-BCDProperty -Id $selected.Id -Property $prop.Name -Value $prop.Value
            }
        }
        
        [System.Windows.MessageBox]::Show("Properties updated!`n`nBackup saved to: $($backup.Path)", "Success", "OK", "Information")
        $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    } catch {
        [System.Windows.MessageBox]::Show("Error updating properties: $_", "Error", "OK", "Error")
    }
})

$W.FindName("BtnSetDefault").Add_Click({
    $id = $W.FindName("EditId").Text
    if ($id) {
        $command = "bcdedit /default $id"
        $explanation = "Sets the selected boot entry as the default option that will boot automatically after the timeout period."
        
        $testMode = Show-CommandPreview $command $null "Set Default Boot Entry"
        
        if ($testMode) {
            Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
            return
        }
        
        try {
            Update-StatusBar -Message "Setting default boot entry..." -ShowProgress
            Set-BCDDefaultEntry $id
            Update-StatusBar -Message "Default boot entry set - refreshing list..." -ShowProgress
            
            # Refresh BCD list to show the new default
            $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            
            Update-StatusBar -Message "Default boot entry updated" -HideProgress
            [System.Windows.MessageBox]::Show("Default Boot Set to $id`n`nThe list has been refreshed to show the new default entry.", "Success", "OK", "Information")
        } catch {
            Update-StatusBar -Message "Failed to set default boot entry: $_" -HideProgress
            [System.Windows.MessageBox]::Show("Error setting default boot entry: $_", "Error", "OK", "Error")
        }
    }
})

$W.FindName("BtnTimeout").Add_Click({
    $t = $W.FindName("TxtTimeout").Text
    bcdedit /timeout $t
    [System.Windows.MessageBox]::Show("Timeout updated to $t seconds.", "Success", "OK", "Information")
})

# Driver Diagnostics
$W.FindName("BtnDetect").Add_Click({
    $W.FindName("DrvBox").Text = "Scanning for storage driver errors...`n`n"
    $result = Get-MissingStorageDevices
    $W.FindName("DrvBox").Text = $result
})

$W.FindName("BtnScanDrivers").Add_Click({
    $selectedDrive = $W.FindName("DriveCombo").SelectedItem
    $drive = $null
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1] + ":"
        }
    }
    
    $W.FindName("DrvBox").Text = "Scanning for MISSING storage drivers...`n`n"
    $W.FindName("DrvBox").Text += "Checking for problematic storage controllers first...`n"
    
    $scanResult = Scan-ForDrivers -SourceDrive $drive
    
    if ($scanResult.Found) {
        $output = "`n[SUCCESS] SCAN COMPLETE`n"
        $output += "===============================================================`n"
        $output += "$($scanResult.Message)`n"
        $output += "Source Location: $($scanResult.SearchPath)`n"
        $output += "`nFound Drivers (matching missing devices):`n"
        $output += "---------------------------------------------------------------`n"
        
        $num = 1
        foreach ($driver in $scanResult.Drivers) {
            $output += "$num. $($driver.Name)`n"
            $output += "   Path: $($driver.Path)`n"
            $output += "   Type: $($driver.Type)`n`n"
            $num++
        }
        
        $W.FindName("DrvBox").Text = $output
    } else {
        $W.FindName("DrvBox").Text = "`n[INFO] SCAN RESULTS`n`n$($scanResult.Message)"
    }
})

$W.FindName("BtnScanAllDrivers").Add_Click({
    $selectedDrive = $W.FindName("DriveCombo").SelectedItem
    $drive = $null
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1] + ":"
        }
    }
    
    $W.FindName("DrvBox").Text = "Scanning for ALL available storage drivers...`n`n"
    $W.FindName("DrvBox").Text += "This may take a moment...`n"
    
    $scanResult = Scan-ForDrivers -SourceDrive $drive -ShowAll
    
    if ($scanResult.Found) {
        $output = "`n[SUCCESS] SCAN COMPLETE`n"
        $output += "===============================================================`n"
        $output += "$($scanResult.Message)`n"
        $output += "Source Location: $($scanResult.SearchPath)`n"
        $output += "`nFound Drivers (ALL storage drivers):`n"
        $output += "---------------------------------------------------------------`n"
        
        $num = 1
        foreach ($driver in $scanResult.Drivers) {
            $output += "$num. $($driver.Name)`n"
            $output += "   Path: $($driver.Path)`n"
            $output += "   Type: $($driver.Type)`n`n"
            $num++
        }
        
        $W.FindName("DrvBox").Text = $output
    } else {
        $W.FindName("DrvBox").Text = "`n[FAILED] SCAN FAILED`n`n$($scanResult.Message)"
    }
})

# Boot Fixer Functions - Enhanced with detailed command info
function Show-CommandPreview {
    param($Command, $Key, $Description)
    $testMode = $W.FindName("ChkTestMode").IsChecked
    $cmdInfo = Get-DetailedCommandInfo $Key
    
    $output = ">>> ANALYSIS REPORT`n"
    $output += "===============================================================`n"
    $output += "Time: $([DateTime]::Now.ToString('HH:mm:ss'))`n"
    $output += "Command: $Command`n"
    $output += "Description: $Description`n`n"
    
    if ($cmdInfo) {
        $output += "WHY USE THIS:`n"
        $output += "  $($cmdInfo.Why)`n`n"
        $output += "TECHNICAL ACTION:`n"
        $output += "  $($cmdInfo.What)`n`n"
    }
    
    if ($testMode) {
        $output += "--- [TEST MODE ACTIVE: NO CHANGES WILL BE MADE] ---`n"
        $output += "Uncheck 'Test Mode' to execute this command.`n"
    } else {
        $output += "--- [EXECUTING COMMAND] ---`n"
    }
    
    $W.FindName("FixerOutput").Text = $output
    $W.FindName("FixerOutput").ScrollToEnd()
    
    return $testMode
}

$W.FindName("BtnRebuildBCD").Add_Click({
    $selectedDrive = $W.FindName("DriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $command = "bcdboot $drive`:\Windows"
    $explanation = Get-CommandExplanation "bcdboot"
    $cmdInfo = Get-DetailedCommandInfo "bcdboot"
    
    $displayText = "COMMAND: $command`n`n"
    if ($cmdInfo) {
        $displayText += "WHY USE THIS:`n$($cmdInfo.Why)`n`n"
        $displayText += "TECHNICAL ACTION:`n$($cmdInfo.What)`n"
    } else {
        $displayText += "EXPLANATION:`n$explanation"
    }
    $W.FindName("TxtRebuildBCD").Text = $displayText
    
    $testMode = Show-CommandPreview $command "bcdboot" "Rebuild BCD from Windows Installation"
    
    if (-not $testMode) {
        # Show comprehensive warning
        $warningInfo = Show-CommandWarning -CommandKey "bcdboot" -Command $command -Description "Rebuild BCD from Windows Installation" -IsGUI
        
        $warningMsg = "$($warningInfo.Message)`n`nDo you want to proceed?"
        $result = [System.Windows.MessageBox]::Show(
            $warningMsg,
            $warningInfo.Title,
            "YesNo",
            "Warning"
        )
        
        if ($result -eq "No") {
            $W.FindName("FixerOutput").Text += "`nOperation cancelled by user.`n"
            Update-StatusBar -Message "Operation cancelled" -HideProgress
            return
        }
        
        # BitLocker Safety Check
        $bitlocker = Test-BitLockerStatus -TargetDrive $drive
        if ($bitlocker.IsEncrypted) {
            $result = [System.Windows.MessageBox]::Show(
                "$($bitlocker.Warning)`n`nDo you have your BitLocker recovery key available?`n`nClick 'Yes' to proceed anyway, or 'No' to cancel.",
                "BitLocker Encryption Detected",
                "YesNo",
                "Warning"
            )
            if ($result -eq "No") {
                $W.FindName("FixerOutput").Text += "`nOperation cancelled due to BitLocker encryption.`n"
                Update-StatusBar -Message "Operation cancelled" -HideProgress
                return
            }
        }
        
        try {
            Update-StatusBar -Message "Executing BCD rebuild..." -ShowProgress
            $result = Invoke-Expression $command 2>&1
            $W.FindName("FixerOutput").Text += "`nOutput: $result`n"
            Update-StatusBar -Message "BCD rebuild completed" -HideProgress
        } catch {
            $W.FindName("FixerOutput").Text += "`nError: $_`n"
            Update-StatusBar -Message "BCD rebuild failed: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
})

$W.FindName("BtnFixBoot").Add_Click({
    $selectedDrive = $W.FindName("DriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive -and $selectedDrive -ne "Auto-detect") {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $command = "bootrec /fixboot"
    $cmdInfo = Get-DetailedCommandInfo "fixboot"
    
    $displayText = "COMMAND: $command`nAlso runs: bootrec /fixmbr`nAlso runs: bootrec /rebuildbcd`n`n"
    if ($cmdInfo) {
        $displayText += "WHY USE THIS:`n$($cmdInfo.Why)`n`n"
        $displayText += "TECHNICAL ACTION:`n$($cmdInfo.What)`n"
    }
    $W.FindName("TxtFixBoot").Text = $displayText
    
    $testMode = Show-CommandPreview $command "fixboot" "Fix Boot Files (bootrec)"
    
    if (-not $testMode) {
        # Show comprehensive warning
        $warningInfo = Show-CommandWarning -CommandKey "bootrec_fixboot" -Command $command -Description "Fix Boot Files (bootrec)" -IsGUI
        
        $warningMsg = "$($warningInfo.Message)`n`nDo you want to proceed?"
        $result = [System.Windows.MessageBox]::Show(
            $warningMsg,
            $warningInfo.Title,
            "YesNo",
            "Warning"
        )
        
        if ($result -eq "No") {
            $W.FindName("FixerOutput").Text += "`nOperation cancelled by user.`n"
            Update-StatusBar -Message "Operation cancelled" -HideProgress
            return
        }
        
        # BitLocker Safety Check
        $bitlocker = Test-BitLockerStatus -TargetDrive $drive
        if ($bitlocker.IsEncrypted) {
            $result = [System.Windows.MessageBox]::Show(
                "$($bitlocker.Warning)`n`nDo you have your BitLocker recovery key available?`n`nClick 'Yes' to proceed anyway, or 'No' to cancel.",
                "BitLocker Encryption Detected",
                "YesNo",
                "Warning"
            )
            if ($result -eq "No") {
                $W.FindName("FixerOutput").Text += "`nOperation cancelled due to BitLocker encryption.`n"
                Update-StatusBar -Message "Operation cancelled" -HideProgress
                return
            }
        }
        
        try {
            Update-StatusBar -Message "Executing boot fix commands..." -ShowProgress
            $result1 = bootrec /fixboot 2>&1
            $result2 = bootrec /fixmbr 2>&1
            $result3 = bootrec /rebuildbcd 2>&1
            $W.FindName("FixerOutput").Text += "`nOutput:`n$result1`n$result2`n$result3`n"
            Update-StatusBar -Message "Boot fix completed" -HideProgress
        } catch {
            $W.FindName("FixerOutput").Text += "`nError: $_`n"
            Update-StatusBar -Message "Boot fix failed: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
})

$W.FindName("BtnScanWindows").Add_Click({
    $command = "bootrec /scanos"
    $cmdInfo = Get-DetailedCommandInfo "scanos"
    
    $displayText = "COMMAND: $command`n`n"
    if ($cmdInfo) {
        $displayText += "WHY USE THIS:`n$($cmdInfo.Why)`n`n"
        $displayText += "TECHNICAL ACTION:`n$($cmdInfo.What)`n"
    }
    $W.FindName("TxtScanWindows").Text = $displayText
    
    $testMode = Show-CommandPreview $command "scanos" "Scan for Windows Installations"
    
    if (-not $testMode) {
        try {
            Update-StatusBar -Message "Scanning for Windows installations..." -ShowProgress
            $result = bootrec /scanos 2>&1
            $W.FindName("FixerOutput").Text += "`nOutput: $result`n"
            Update-StatusBar -Message "Windows scan completed" -HideProgress
        } catch {
            $W.FindName("FixerOutput").Text += "`nError: $_`n"
            Update-StatusBar -Message "Windows scan failed: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
})

$W.FindName("BtnRebuildBCD2").Add_Click({
    $command = "bootrec /rebuildbcd"
    $cmdInfo = Get-DetailedCommandInfo "rebuildbcd"
    
    $displayText = "COMMAND: $command`n`n"
    if ($cmdInfo) {
        $displayText += "WHY USE THIS:`n$($cmdInfo.Why)`n`n"
        $displayText += "TECHNICAL ACTION:`n$($cmdInfo.What)`n"
    }
    $W.FindName("TxtRebuildBCD2").Text = $displayText
    
    $testMode = Show-CommandPreview $command "rebuildbcd" "Rebuild BCD (bootrec)"
    
    if (-not $testMode) {
        try {
            Update-StatusBar -Message "Rebuilding BCD..." -ShowProgress
            $result = bootrec /rebuildbcd 2>&1
            $W.FindName("FixerOutput").Text += "`nOutput: $result`n"
            Update-StatusBar -Message "BCD rebuild completed" -HideProgress
        } catch {
            $W.FindName("FixerOutput").Text += "`nError: $_`n"
            Update-StatusBar -Message "BCD rebuild failed: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
})

$W.FindName("BtnSetDefaultBoot").Add_Click({
    $selected = $W.FindName("BCDList").SelectedItem
    if (-not $selected) {
        [System.Windows.MessageBox]::Show("Please select a BCD entry first in the BCD Editor tab.", "Warning", "OK", "Warning")
        return
    }
    
    $command = "bcdedit /default $($selected.Id)"
    $explanation = "Sets the selected boot entry as the default option that will boot automatically after the timeout period. This is useful when you have multiple Windows installations and want to change which one boots by default."
    $W.FindName("TxtSetDefault").Text = "COMMAND: $command`nEntry: $($selected.Description)`n`nEXPLANATION:`n$explanation"
    
    $testMode = Show-CommandPreview $command $null "Set Default Boot Entry"
    
    if (-not $testMode) {
        try {
            Set-BCDDefaultEntry $selected.Id
            $W.FindName("FixerOutput").Text += "Default boot entry set successfully.`n"
            Update-StatusBar -Message "Default boot entry set successfully - refreshing list..." -ShowProgress
            
            # Refresh BCD list to show the new default
            $W.FindName("BtnBCD").RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            
            Update-StatusBar -Message "Default boot entry updated" -HideProgress
        } catch {
            $W.FindName("FixerOutput").Text += "Error: $_`n"
            Update-StatusBar -Message "Failed to set default boot entry: $_" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Command preview complete (Test Mode)" -HideProgress
    }
})

# Diagnostics Tab Handlers
$W.FindName("BtnCheckRestore").Add_Click({
    $selectedDrive = $W.FindName("DiagDriveCombo").SelectedItem
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $W.FindName("DiagBox").Text = "Checking System Restore status for drive $drive`:...`n`n"
    $restoreInfo = Get-SystemRestoreInfo -TargetDrive $drive
    
    $output = "SYSTEM RESTORE DIAGNOSTICS`n"
    $output += "===============================================================`n`n"
    $output += "Status: $($restoreInfo.Message)`n`n"
    
    if ($restoreInfo.Enabled -and $restoreInfo.RestorePoints.Count -gt 0) {
        $output += "RESTORE POINTS:`n"
        $output += "---------------------------------------------------------------`n"
        $num = 1
        foreach ($point in $restoreInfo.RestorePoints) {
            $output += "$num. $($point.Description)`n"
            $output += "   Created: $($point.CreationTime)`n"
            $output += "   Type: $($point.RestorePointType)`n"
            $output += "   Sequence: $($point.SequenceNumber)`n`n"
            $num++
            if ($num -gt 20) { break } # Limit to 20 most recent
        }
    } else {
        $output += "No restore points found.`n"
        $output += "`nTo enable System Restore:`n"
        $output += "1. Open System Properties`n"
        $output += "2. Go to System Protection tab`n"
        $output += "3. Select your drive and click Configure`n"
        $output += "4. Enable System Protection`n"
    }
    
    $W.FindName("DiagBox").Text = $output
})

$W.FindName("BtnCreateRestorePoint").Add_Click({
    $selectedDrive = $W.FindName("DiagDriveCombo").SelectedItem
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    # Use a simple input dialog
    $description = "Miracle Boot Manual Restore Point - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $userInput = [Microsoft.VisualBasic.Interaction]::InputBox(
            "Enter description for restore point:",
            "Create System Restore Point",
            $description
        )
        if (-not [string]::IsNullOrWhiteSpace($userInput)) {
            $description = $userInput
        }
    } catch {
        # If InputBox fails, use default description
        Write-Warning "Could not show input dialog, using default description"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($description)) {
        Update-StatusBar -Message "Creating restore point..." -ShowProgress
        $W.FindName("DiagBox").Text = "Creating system restore point...`n`nPlease wait...`n"
        
        $result = Create-SystemRestorePoint -Description $description -OperationType "Manual"
        
        $output = "RESTORE POINT CREATION`n"
        $output += "===============================================================`n`n"
        
        if ($result.Success) {
            $output += "[SUCCESS] Restore point created successfully!`n`n"
            $output += "Description: $description`n"
            if ($result.RestorePointID) {
                $output += "Restore Point ID: $($result.RestorePointID)`n"
            }
            if ($result.RestorePointPath) {
                $output += "Path: $($result.RestorePointPath)`n"
            }
            Update-StatusBar -Message "Restore point created successfully" -HideProgress
        } else {
            $output += "[ERROR] Failed to create restore point`n`n"
            $output += "Message: $($result.Message)`n"
            if ($result.Error) {
                $output += "Error: $($result.Error)`n"
            }
            Update-StatusBar -Message "Failed to create restore point" -HideProgress
        }
        
        $W.FindName("DiagBox").Text = $output
    }
})

$W.FindName("BtnListRestorePoints").Add_Click({
    $selectedDrive = $W.FindName("DiagDriveCombo").SelectedItem
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    Update-StatusBar -Message "Retrieving restore points..." -ShowProgress
    $W.FindName("DiagBox").Text = "Retrieving restore points for drive $drive`:...`n`n"
    
    $restorePoints = Get-SystemRestorePoints -Limit 50
    
    $output = "SYSTEM RESTORE POINTS`n"
    $output += "===============================================================`n`n"
    
    if ($restorePoints.Count -gt 0) {
        $output += "Found $($restorePoints.Count) restore point(s):`n`n"
        $num = 1
        foreach ($point in $restorePoints) {
            $output += "$num. ID: $($point.SequenceNumber)`n"
            $output += "   Description: $($point.Description)`n"
            $output += "   Created: $($point.CreationTime)`n"
            $output += "   Type: $($point.RestorePointType)`n"
            $output += "   Event: $($point.EventType)`n`n"
            $num++
        }
        Update-StatusBar -Message "Found $($restorePoints.Count) restore points" -HideProgress
    } else {
        $output += "[INFO] No restore points found.`n`n"
        $output += "System Restore may be disabled or no restore points have been created.`n"
        Update-StatusBar -Message "No restore points found" -HideProgress
    }
    
    $W.FindName("DiagBox").Text = $output
})

$W.FindName("BtnCheckReagentc").Add_Click({
    $W.FindName("DiagBox").Text = "Checking Reagentc (Windows Recovery Environment) health...`n`n"
    $reagentcHealth = Get-ReagentcHealth
    
    $output = "REAGENTC HEALTH CHECK`n"
    $output += "===============================================================`n`n"
    $output += "$($reagentcHealth.Message)`n`n"
    
    if ($reagentcHealth.WinRELocation) {
        $output += "WinRE Location: $($reagentcHealth.WinRELocation)`n`n"
    }
    
    $output += "DETAILED OUTPUT:`n"
    $output += "---------------------------------------------------------------`n"
    foreach ($line in $reagentcHealth.Details) {
        $output += "$line`n"
    }
    
    $output += "`n`nRECOMMENDATIONS:`n"
    $output += "---------------------------------------------------------------`n"
    if ($reagentcHealth.Status -eq "Disabled") {
        $output += "To enable WinRE, run: reagentc /enable`n"
        $output += "To set WinRE location: reagentc /setreimage /path [path]`n"
    } else {
        $output += "WinRE appears to be properly configured.`n"
    }
    
    $W.FindName("DiagBox").Text = $output
})

$W.FindName("BtnGetOSInfo").Add_Click({
    $selectedDrive = $W.FindName("DiagDriveCombo").SelectedItem
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $W.FindName("DiagBox").Text = "Gathering Operating System information for drive $drive`:...`n`n"
    $osInfo = Get-OSInfo -TargetDrive $drive
    
    $output = "OPERATING SYSTEM INFORMATION`n"
    $output += "===============================================================`n`n"
    
    # Show current OS indicator
    if ($osInfo.IsCurrentOS) {
        $output += "[CURRENT OS] This is the operating system you are currently running from.`n"
        $output += "Drive: $drive`: (System Drive: $($env:SystemDrive))`n`n"
    } else {
        $output += "[OFFLINE OS] This is an offline Windows installation.`n"
        $output += "Drive: $drive`: (Not currently running)`n`n"
    }
    
    if ($osInfo.Error) {
        $output += "[ERROR] $($osInfo.Error)`n"
    } else {
        $output += "OS Name: $($osInfo.OSName)`n"
        $output += "Version: $($osInfo.Version)`n"
        if ($osInfo.BuildNumber) {
            $output += "Build Number: $($osInfo.BuildNumber)`n"
        }
        if ($osInfo.UBR) {
            $output += "Update Build Revision (UBR): $($osInfo.UBR)`n"
        }
        if ($osInfo.ReleaseId) {
            $output += "Release ID: $($osInfo.ReleaseId)`n"
        }
        if ($osInfo.EditionID) {
            $output += "Edition: $($osInfo.EditionID)`n"
        }
        $output += "Architecture: $($osInfo.Architecture)`n"
        $output += "Language: $($osInfo.Language)"
        if ($osInfo.LanguageCode) {
            $output += " (Code: $($osInfo.LanguageCode))"
        }
        $output += "`n"
        
        # Show Insider build info
        if ($osInfo.IsInsider) {
            $output += "`n[INSIDER BUILD DETECTED]`n"
            $output += "This is a Windows Insider Preview build.`n"
            if ($osInfo.InsiderChannel) {
                $output += "Channel: $($osInfo.InsiderChannel)`n"
            }
            $output += "`nINSIDER ISO DOWNLOAD LINKS:`n"
            $output += "---------------------------------------------------------------`n"
            $output += "Official Insider ISO Downloads:`n"
            $output += "  $($osInfo.InsiderLinks.DevChannel)`n`n"
            $output += "UUP Dump (Community ISO Builder):`n"
            $output += "  $($osInfo.InsiderLinks.UUP)`n"
            $output += "  (Search for build $($osInfo.BuildNumber) to find matching ISO)`n`n"
        }
        
        if ($osInfo.InstallDate) {
            $output += "Install Date: $($osInfo.InstallDate)`n"
        }
        if ($osInfo.SerialNumber) {
            $output += "Serial Number: $($osInfo.SerialNumber)`n"
        }
        
        # Show recommended ISO (only if not insider, or show both)
        if (-not $osInfo.IsInsider) {
            $output += "`n`nRECOMMENDED RECOVERY ISO:`n"
            $output += "===============================================================`n"
            $output += "To create a compatible recovery ISO, you need:`n`n"
            $output += "Architecture: $($osInfo.RecommendedISO.Architecture)`n"
            $output += "Language: $($osInfo.RecommendedISO.Language) ($($osInfo.Language))`n"
            $output += "Version: $($osInfo.RecommendedISO.Version)`n`n"
            $output += "Download from:`n"
            if ($osInfo.RecommendedISO.Version -match "11") {
                $output += "  https://www.microsoft.com/software-download/windows11`n"
            } else {
                $output += "  https://www.microsoft.com/software-download/windows10`n"
            }
            $output += "`nMake sure to select:`n"
            $output += "- $($osInfo.RecommendedISO.Architecture) architecture`n"
            $output += "- $($osInfo.Language) language`n"
            $output += "- The same or newer version than your current installation`n"
        } else {
            $output += "`n`nNOTE: For Insider builds, use the Insider ISO links above.`n"
            $output += "Standard Windows 10/11 ISOs may not be compatible with Insider builds.`n"
        }
    }
    
    $W.FindName("DiagBox").Text = $output
})

# Install Failure Analysis button
$W.FindName("BtnInstallFailure").Add_Click({
    $selectedDrive = $W.FindName("DiagDriveCombo").SelectedItem
    $drive = $env:SystemDrive.TrimEnd(':')
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    Update-StatusBar -Message "Analyzing Windows installation failure reasons..." -ShowProgress
    $W.FindName("DiagBox").Text = "Analyzing Windows installation failure reasons for drive $drive`:...`n`nPlease wait...`n"
    
    $analysis = Get-WindowsInstallFailureReasons -TargetDrive $drive
    
    $W.FindName("DiagBox").Text = $analysis.Report
    Update-StatusBar -Message "Install failure analysis complete" -HideProgress
    
    if ($analysis.FailureReasons.Count -gt 0) {
        [System.Windows.MessageBox]::Show(
            "Installation failure analysis complete.`n`nFound $($analysis.FailureReasons.Count) potential failure reason(s).`n`nSee the Diagnostics tab for full details and recommendations.",
            "Analysis Complete",
            "OK",
            "Warning"
        )
    } else {
        [System.Windows.MessageBox]::Show(
            "Installation failure analysis complete.`n`nNo obvious failure reasons detected. Review the log files manually for details.",
            "Analysis Complete",
            "OK",
            "Information"
        )
    }
})

# Diagnostics & Logs Tab Handlers
$W.FindName("BtnDriverForensics").Add_Click({
    $W.FindName("LogAnalysisBox").Text = "Running storage driver forensics analysis...`n`nScanning for missing devices and matching to INF files...`n"
    
    $forensics = Get-MissingDriverForensics
    
    $W.FindName("LogAnalysisBox").Text = $forensics
})

$W.FindName("BtnAnalyzeBootLog").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $W.FindName("LogAnalysisBox").Text = "Analyzing boot log from $drive`:...`n`n"
    
    $bootLog = Get-BootLogAnalysis -TargetDrive $drive
    
    $output = $bootLog.Summary
    
    if ($bootLog.Found) {
        $output += "`n`nDETAILED DRIVER FAILURES:`n"
        $output += "---------------------------------------------------------------`n"
        if ($bootLog.FailedDrivers.Count -gt 0) {
            $num = 1
            foreach ($driver in $bootLog.FailedDrivers | Select-Object -First 20) {
                $output += "$num. $driver`n"
                $num++
            }
        } else {
            $output += "No driver failures recorded.`n"
        }
    }
    
    $W.FindName("LogAnalysisBox").Text = $output
})

$W.FindName("BtnAnalyzeEventLogs").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $W.FindName("LogAnalysisBox").Text = "Analyzing event logs from $drive`:...`n`nThis may take a moment...`n"
    
    $eventLogs = Get-OfflineEventLogs -TargetDrive $drive
    
    if ($eventLogs.Success) {
        $W.FindName("LogAnalysisBox").Text = $eventLogs.Summary
    } else {
        $W.FindName("LogAnalysisBox").Text = $eventLogs.Summary
    }
})

$W.FindName("BtnFullBootDiagnosis").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $W.FindName("LogAnalysisBox").Text = "Running comprehensive automated boot diagnosis for $drive`:...`n`nPlease wait...`n"
    
    # Run enhanced automated diagnosis
    $diagnosis = Run-BootDiagnosis -Drive $drive
    
    $output = $diagnosis.Report
    
    # Add boot log summary if available
    $bootLog = Get-BootLogAnalysis -TargetDrive $drive
    if ($bootLog.Found) {
        $output += "`n`n"
        $output += "===============================================================`n"
        $output += "BOOT LOG SUMMARY`n"
        $output += "===============================================================`n"
        $output += "Boot log found. Critical missing drivers: $($bootLog.MissingDrivers.Count)`n"
        if ($bootLog.MissingDrivers.Count -gt 0) {
            $output += "Critical drivers that failed to load:`n"
            foreach ($driver in $bootLog.MissingDrivers) {
                $output += "  - $driver`n"
            }
        }
    }
    
    # Add event log summary if available
    $eventLogs = Get-OfflineEventLogs -TargetDrive $drive
    if ($eventLogs.Success) {
        $output += "`n`n"
        $output += "===============================================================`n"
        $output += "EVENT LOG SUMMARY`n"
        $output += "===============================================================`n"
        $output += "Recent shutdowns: $($eventLogs.ShutdownEvents.Count)`n"
        $output += "BSOD events: $($eventLogs.BSODInfo.Count)`n"
        $output += "Recent errors: $($eventLogs.RecentErrors.Count)`n"
        if ($eventLogs.BSODInfo.Count -gt 0) {
            $output += "`nMost recent BSOD:`n"
            $latestBSOD = $eventLogs.BSODInfo | Sort-Object Time -Descending | Select-Object -First 1
            $output += "  Stop Code: $($latestBSOD.StopCode)`n"
            $output += "  $($latestBSOD.Explanation)`n"
        }
    }
    
    # Show critical issues warning if found
    if ($diagnosis.HasCriticalIssues) {
        $output += "`n`n"
        $output += "===============================================================`n"
        $output += "⚠️  CRITICAL ISSUES DETECTED - IMMEDIATE ACTION REQUIRED`n"
        $output += "===============================================================`n"
        $output += "Review the issues above and follow the recommended actions.`n"
        $output += "Use the Boot Fixer tab to apply repairs.`n"
    }
    
    $W.FindName("LogAnalysisBox").Text = $output
})

$W.FindName("BtnHardwareSupport").Add_Click({
    $W.FindName("LogAnalysisBox").Text = "Gathering hardware information and support links...`n`n"
    
    $hwInfo = Get-HardwareSupportInfo
    
    $output = "HARDWARE SUPPORT INFORMATION`n"
    $output += "===============================================================`n`n"
    
    if ($hwInfo.Error) {
        $output += "[ERROR] $($hwInfo.Error)`n"
    } else {
        $output += "MOTHERBOARD:`n"
        $output += "---------------------------------------------------------------`n"
        if ($hwInfo.Motherboard) {
            $output += "$($hwInfo.Motherboard)`n`n"
        } else {
            $output += "Information not available`n`n"
        }
        
        $output += "GRAPHICS CARDS:`n"
        $output += "---------------------------------------------------------------`n"
        if ($hwInfo.GPUs.Count -gt 0) {
            foreach ($gpu in $hwInfo.GPUs) {
                $output += "$($gpu.Name)`n"
                $output += "  Driver Version: $($gpu.DriverVersion)`n"
                if ($gpu.DriverDate) {
                    $output += "  Driver Date: $($gpu.DriverDate)`n"
                }
                if ($gpu.SupportLink) {
                    $output += "  Support: $($gpu.SupportLink)`n"
                }
                $output += "`n"
            }
        } else {
            $output += "No dedicated graphics cards detected`n`n"
        }
        
        $output += "SUPPORT LINKS:`n"
        $output += "---------------------------------------------------------------`n"
        if ($hwInfo.SupportLinks.Count -gt 0) {
            foreach ($link in $hwInfo.SupportLinks) {
                $output += "$($link.Name) ($($link.Type)):`n"
                $output += "  $($link.URL)`n`n"
            }
        } else {
            $output += "No manufacturer support links available`n`n"
        }
        
        if ($hwInfo.DriverAlerts.Count -gt 0) {
            $output += "DRIVER UPDATE ALERTS:`n"
            $output += "---------------------------------------------------------------`n"
            foreach ($alert in $hwInfo.DriverAlerts) {
                $output += "[!] $alert`n"
            }
            $output += "`n"
        }
        
        $output += "NOTE: Click the links above to download the latest drivers from manufacturer websites.`n"
        $output += "For storage drivers (VMD/RAID), use the 'Driver Forensics' button to identify required INF files.`n"
    }
    
    $W.FindName("LogAnalysisBox").Text = $output
})

$W.FindName("BtnRepairTips").Add_Click({
    $tips = Get-UnofficialRepairTips
    $W.FindName("LogAnalysisBox").Text = $tips
})

$W.FindName("BtnGenRegScript").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $script = Get-RegistryEditionOverride -TargetDrive $drive
    
    # Save script to file
    $scriptPath = "$env:TEMP\RegistryEditionOverride_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    $script | Out-File -FilePath $scriptPath -Encoding UTF8
    
    $output = "REGISTRY EDITIONID OVERRIDE SCRIPT GENERATED`n"
    $output += "===============================================================`n`n"
    $output += "Script saved to: $scriptPath`n`n"
    $output += "===============================================================`n"
    $output += "INSTRUCTIONS:`n"
    $output += "===============================================================`n"
    $output += "1. Run this script as Administrator BEFORE launching setup.exe`n"
    $output += "2. The script will backup your registry first`n"
    $output += "3. It will modify EditionID to 'Professional' for compatibility`n"
    $output += "4. IMMEDIATELY run setup.exe from your Windows ISO (do NOT reboot)`n"
    $output += "5. To restore original values later, use the backup file`n`n"
    $output += "⚠️  WARNING: This modifies system registry. Use at your own risk.`n`n"
    $output += "===============================================================`n"
    $output += "SCRIPT PREVIEW:`n"
    $output += "===============================================================`n`n"
    $output += $script
    
    $W.FindName("LogAnalysisBox").Text = $output
    
    $result = [System.Windows.MessageBox]::Show(
        "Script generated successfully!`n`nLocation: $scriptPath`n`nWould you like to open the script file location?",
        "Script Generated",
        "YesNo",
        "Information"
    )
    
    if ($result -eq "Yes") {
        try {
            Start-Process explorer.exe -ArgumentList "/select,`"$scriptPath`""
        } catch {
            [System.Windows.MessageBox]::Show("Could not open file location.", "Error", "OK", "Error")
        }
    }
})

$W.FindName("BtnOneClickFix").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $result = [System.Windows.MessageBox]::Show(
        "This will apply ALL registry overrides to enable In-Place Upgrade compatibility:`n`n" +
        "- EditionID → Professional`n" +
        "- InstallLanguage → 0409 (US English)`n" +
        "- ProgramFilesDir → Reset to $drive`:\Program Files`n`n" +
        "A full registry backup will be created first.`n`n" +
        "Continue?",
        "One-Click Registry Fixes",
        "YesNo",
        "Question"
    )
    
    if ($result -eq "Yes") {
        $W.FindName("LogAnalysisBox").Text = "Applying one-click registry fixes...`n`nPlease wait...`n"
        
        $fixResults = Apply-OneClickRegistryFixes -TargetDrive $drive
        
        $output = "ONE-CLICK REGISTRY FIXES RESULTS`n"
        $output += "===============================================================`n`n"
        
        if ($fixResults.Success) {
            $output += "[SUCCESS] Registry fixes applied successfully!`n`n"
        } else {
            $output += "[PARTIAL] Some fixes applied, but some failed.`n`n"
        }
        
        $output += "APPLIED FIXES:`n"
        $output += "---------------------------------------------------------------`n"
        if ($fixResults.Applied.Count -gt 0) {
            foreach ($fix in $fixResults.Applied) {
                $output += "[OK] $fix`n"
            }
        } else {
            $output += "No changes were needed (values already correct).`n"
        }
        
        if ($fixResults.Failed.Count -gt 0) {
            $output += "`nFAILED FIXES:`n"
            $output += "---------------------------------------------------------------`n"
            foreach ($fail in $fixResults.Failed) {
                $output += "[FAIL] $fail`n"
            }
        }
        
        if ($fixResults.Warnings.Count -gt 0) {
            $output += "`nWARNINGS:`n"
            $output += "---------------------------------------------------------------`n"
            foreach ($warn in $fixResults.Warnings) {
                $output += "[WARN] $warn`n"
            }
        }
        
        $output += "`n`nNEXT STEPS:`n"
        $output += "---------------------------------------------------------------`n"
        $output += "1. IMMEDIATELY run setup.exe from your Windows ISO`n"
        $output += "2. Do NOT reboot before running setup.exe`n"
        $output += "3. The 'Keep personal files and apps' option should now be available`n"
        $output += "`nBackup location: $($fixResults.BackupPath)`n"
        
        $W.FindName("LogAnalysisBox").Text = $output
        
        if ($fixResults.Success) {
            [System.Windows.MessageBox]::Show(
                "Registry fixes applied successfully!`n`nNow run setup.exe from your Windows ISO IMMEDIATELY (do not reboot).",
                "Success",
                "OK",
                "Information"
            )
        } else {
            [System.Windows.MessageBox]::Show(
                "Some fixes failed. See the output for details.",
                "Partial Success",
                "OK",
                "Warning"
            )
        }
    }
})

$W.FindName("BtnFilterForensics").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $W.FindName("LogAnalysisBox").Text = "Analyzing filter drivers in SYSTEM registry hive...`n`nThis may take a moment...`n"
    
    $forensics = Get-FilterDriverForensics -TargetDrive $drive
    
    $W.FindName("LogAnalysisBox").Text = $forensics.Summary
})

$W.FindName("BtnRecommendedTools").Add_Click({
    $tools = Get-RecommendedTools
    $W.FindName("LogAnalysisBox").Text = $tools
})

$W.FindName("BtnExportDrivers").Add_Click({
    $W.FindName("LogAnalysisBox").Text = "Exporting in-use drivers list...`n`nThis may take a moment...`n"
    
    # Let user choose save location
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
    $saveDialog.FileName = "In-Use_Drivers_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $saveDialog.InitialDirectory = $env:USERPROFILE + "\Desktop"
    $saveDialog.Title = "Save In-Use Drivers Export"
    
    $result = $saveDialog.ShowDialog()
    
    if ($result -eq "OK") {
        $exportResult = Export-InUseDrivers -OutputPath $saveDialog.FileName
        
        if ($exportResult.Success) {
            $output = "IN-USE DRIVERS EXPORT COMPLETE`n"
            $output += "===============================================================`n`n"
            $output += "[SUCCESS] Driver list exported successfully!`n`n"
            $output += "File Location: $($exportResult.Path)`n`n"
            $output += "Export Statistics:`n"
            $output += "  Total Devices: $($exportResult.DeviceCount)`n"
            $output += "  Device Classes: $($exportResult.ClassCount)`n`n"
            $output += "===============================================================`n"
            $output += "WHAT'S IN THE FILE:`n"
            $output += "===============================================================`n"
            $output += "The exported file contains:`n`n"
            $output += "1. All currently working (in-use) drivers from your PC`n"
            $output += "2. Device names and hardware IDs`n"
            $output += "3. Driver INF file paths and locations`n"
            $output += "4. Driver versions and providers`n"
            $output += "5. Organized by device class (Storage, Display, Network, etc.)`n`n"
            $output += "===============================================================`n"
            $output += "HOW TO USE:`n"
            $output += "===============================================================`n"
            $output += "1. Take this file to your installer/recovery environment`n"
            $output += "2. Use the INF file paths to locate drivers in DriverStore`n"
            $output += "3. Copy the driver folders to your recovery USB/ISO`n"
            $output += "4. Use Hardware IDs to match drivers to devices`n`n"
            $output += "TIP: Focus on critical drivers (Storage, Network, Display)`n"
            $output += "     These are most likely needed for recovery operations.`n"
            
            $W.FindName("LogAnalysisBox").Text = $output
            
            $msgResult = [System.Windows.MessageBox]::Show(
                "Driver export complete!`n`nFile saved to:`n$($exportResult.Path)`n`nWould you like to open the file location?",
                "Export Complete",
                "YesNo",
                "Information"
            )
            
            if ($msgResult -eq "Yes") {
                try {
                    Start-Process explorer.exe -ArgumentList "/select,`"$($exportResult.Path)`""
                } catch {
                    [System.Windows.MessageBox]::Show("Could not open file location.", "Error", "OK", "Error")
                }
            }
        } else {
            $output = "EXPORT FAILED`n"
            $output += "===============================================================`n`n"
            $output += "[ERROR] Failed to export drivers: $($exportResult.Error)`n`n"
            $output += "Please ensure you have write permissions to the selected location.`n"
            
            $W.FindName("LogAnalysisBox").Text = $output
            [System.Windows.MessageBox]::Show(
                "Failed to export drivers.`n`nError: $($exportResult.Error)",
                "Export Failed",
                "OK",
                "Error"
            )
        }
    } else {
        $W.FindName("LogAnalysisBox").Text = "Export cancelled by user."
    }
})

$W.FindName("BtnGenCleanupScript").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    $script = Get-CleanupScript -TargetDrive $drive
    
    # Save script to file
    $scriptPath = "$env:TEMP\WindowsOldCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    $script | Out-File -FilePath $scriptPath -Encoding UTF8
    
    $output = "WINDOWS.OLD CLEANUP SCRIPT GENERATED`n"
    $output += "===============================================================`n`n"
    $output += "Script saved to: $scriptPath`n`n"
    $output += "===============================================================`n"
    $output += "INSTRUCTIONS:`n"
    $output += "===============================================================`n"
    $output += "1. Run this script AFTER a successful In-Place Upgrade`n"
    $output += "2. It will remove the Windows.old folder to reclaim disk space`n"
    $output += "3. The script will show the size before deletion`n"
    $output += "4. You will be prompted to confirm before deletion`n`n"
    $output += "[WARNING] This permanently deletes Windows.old. Only run this`n"
    $output += "   after you're certain the repair was successful!`n`n"
    $output += "===============================================================`n"
    $output += "SCRIPT PREVIEW:`n"
    $output += "===============================================================`n`n"
    $output += $script
    
    $W.FindName("LogAnalysisBox").Text = $output
    
    $result = [System.Windows.MessageBox]::Show(
        "Cleanup script generated successfully!`n`nLocation: $scriptPath`n`nWould you like to open the script file location?",
        "Script Generated",
        "YesNo",
        "Information"
    )
    
    if ($result -eq "Yes") {
        try {
            Start-Process explorer.exe -ArgumentList "/select,`"$scriptPath`""
        } catch {
            [System.Windows.MessageBox]::Show("Could not open file location.", "Error", "OK", "Error")
        }
    }
})

$W.FindName("BtnInPlaceReadiness").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    Update-StatusBar -Message "Running in-place upgrade readiness check..." -ShowProgress
    $W.FindName("LogAnalysisBox").Text = "Running comprehensive in-place upgrade readiness check...`n`n"
    $W.FindName("LogAnalysisBox").Text += "Analyzing:`n"
    $W.FindName("LogAnalysisBox").Text += "  - Boot log (nbtlog.txt)`n"
    $W.FindName("LogAnalysisBox").Text += "  - Windows installation files (`$WINDOWS.~BT, `$Windows.~WS)`n"
    $W.FindName("LogAnalysisBox").Text += "  - CBS logs and component store`n"
    $W.FindName("LogAnalysisBox").Text += "  - Registry health`n"
    $W.FindName("LogAnalysisBox").Text += "  - Setup logs`n"
    $W.FindName("LogAnalysisBox").Text += "  - System file health`n`n"
    $W.FindName("LogAnalysisBox").Text += "This may take a few minutes...`n`n"
    
    try {
        $readiness = Get-InPlaceUpgradeReadiness -TargetDrive $drive
        
        $output = $readiness.Report
        
        # Add visual status indicator
        $output += "`n`n"
        $output += "=" * 80 + "`n"
        if ($readiness.ReadyForInPlaceUpgrade) {
            $output += "STATUS: [OK] READY FOR IN-PLACE UPGRADE`n"
        } else {
            $output += "STATUS: [BLOCKED] NOT READY FOR IN-PLACE UPGRADE`n"
            $output += "BLOCKERS FOUND: $($readiness.Blockers.Count)`n"
        }
        $output += "=" * 80 + "`n"
        
        $W.FindName("LogAnalysisBox").Text = $output
        
        if ($readiness.ReadyForInPlaceUpgrade) {
            Update-StatusBar -Message "System is ready for in-place upgrade" -HideProgress
            [System.Windows.MessageBox]::Show(
                "System appears ready for in-place upgrade!`n`nNo critical blockers detected.`n`nReview the detailed report for any warnings.",
                "Ready for In-Place Upgrade",
                "OK",
                "Information"
            )
        } else {
            Update-StatusBar -Message "System is NOT ready - $($readiness.Blockers.Count) blocker(s) found" -HideProgress
            $blockerList = $readiness.Blockers -join "`n  • "
            [System.Windows.MessageBox]::Show(
                "System is NOT ready for in-place upgrade.`n`nBLOCKERS:`n  • $blockerList`n`nReview the detailed report for recommendations.",
                "Blockers Detected",
                "OK",
                "Warning"
            )
        }
    } catch {
        Update-StatusBar -Message "Error during readiness check: $_" -HideProgress
        $W.FindName("LogAnalysisBox").Text = "ERROR: Failed to run in-place upgrade readiness check:`n`n$_"
        [System.Windows.MessageBox]::Show(
            "Error running readiness check: $_",
            "Error",
            "OK",
            "Error"
        )
    }
})

$W.FindName("BtnRepairInstallReady").Add_Click({
    $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
    $drive = "C"
    
    if ($selectedDrive) {
        if ($selectedDrive -match '^([A-Z]):') {
            $drive = $matches[1]
        }
    }
    
    # Confirm action
    $confirmMsg = "REPAIR-INSTALL READINESS ENGINE`n`n"
    $confirmMsg += "This will:`n"
    $confirmMsg += "  • Test eligibility for in-place upgrade (Keep apps + files)`n"
    $confirmMsg += "  • Clear CBS blockers (pending reboots, component store issues)`n"
    $confirmMsg += "  • Normalize setup state (registry keys, edition compatibility)`n"
    $confirmMsg += "  • Repair WinRE registration`n`n"
    $confirmMsg += "Target Drive: $drive`:`n`n"
    $confirmMsg += "Continue?"
    
    $result = [System.Windows.MessageBox]::Show(
        $confirmMsg,
        "Repair-Install Readiness",
        "YesNo",
        "Question"
    )
    
    if ($result -eq "Yes") {
        Update-StatusBar -Message "Running repair-install readiness engine..." -ShowProgress
        $W.FindName("LogAnalysisBox").Text = "REPAIR-INSTALL READINESS ENGINE`n"
        $W.FindName("LogAnalysisBox").Text += "=" * 80 + "`n`n"
        $W.FindName("LogAnalysisBox").Text += "Target Drive: $drive`:`n"
        $W.FindName("LogAnalysisBox").Text += "Mode: $(if ((Get-EnvironmentType) -eq 'FullOS') { 'Online' } else { 'Offline' })`n`n"
        $W.FindName("LogAnalysisBox").Text += "Running comprehensive checks and fixes...`n`n"
        $W.FindName("LogAnalysisBox").Text += "This may take several minutes...`n`n"
        
        try {
            # Progress callback for status updates
            $progressCallback = {
                param($message)
                $W.Dispatcher.Invoke([action]{
                    $W.FindName("LogAnalysisBox").Text += "$message`n"
                    $W.FindName("LogAnalysisBox").ScrollToEnd()
                    Update-StatusBar -Message $message -ShowProgress
                }, [System.Windows.Threading.DispatcherPriority]::Input)
            }
            
            $readinessResult = Start-RepairInstallReadiness -TargetDrive $drive -FixBlockers -ProgressCallback $progressCallback
            
            $output = $readinessResult.Report
            
            # Add visual summary
            $output += "`n`n"
            $output += "=" * 80 + "`n"
            $output += "SUMMARY`n"
            $output += "=" * 80 + "`n"
            $output += "Readiness Score: $($readinessResult.ReadinessScore)/100`n"
            $output += "Eligible: $(if ($readinessResult.Eligible) { 'YES ✅' } else { 'NO ❌' })`n"
            $output += "Actions Taken: $($readinessResult.ActionsTaken.Count)`n"
            $output += "Blockers Remaining: $($readinessResult.Blockers.Count)`n"
            $output += "Warnings: $($readinessResult.Warnings.Count)`n`n"
            
            if ($readinessResult.Eligible) {
                $output += "✅ SYSTEM IS READY FOR REPAIR INSTALL`n`n"
                $output += "You can now run:`n"
                $output += "  setup.exe /auto upgrade /quiet`n`n"
                $output += "Or use Windows Setup GUI and select 'Keep apps + files'`n"
            } else {
                $output += "❌ SYSTEM IS NOT FULLY READY`n`n"
                if ($readinessResult.Blockers.Count -gt 0) {
                    $output += "Blockers must be resolved:`n"
                    foreach ($blocker in $readinessResult.Blockers) {
                        $output += "  • $blocker`n"
                    }
                }
            }
            
            $W.FindName("LogAnalysisBox").Text = $output
            $W.FindName("LogAnalysisBox").ScrollToEnd()
            
            # Show result dialog
            if ($readinessResult.Eligible) {
                [System.Windows.MessageBox]::Show(
                    "✅ System is ready for repair install!`n`n" +
                    "Readiness Score: $($readinessResult.ReadinessScore)/100`n`n" +
                    "You can now run setup.exe with 'Keep apps + files' option.",
                    "Ready for Repair Install",
                    "OK",
                    "Information"
                )
            } else {
                [System.Windows.MessageBox]::Show(
                    "⚠ System may not be fully ready.`n`n" +
                    "Readiness Score: $($readinessResult.ReadinessScore)/100`n`n" +
                    "Review the report for blockers and warnings.",
                    "Repair-Install Readiness",
                    "OK",
                    "Warning"
                )
            }
            
            Update-StatusBar -Message "Repair-install readiness check complete" -HideProgress
        } catch {
            $W.FindName("LogAnalysisBox").Text += "`n`n[ERROR] Failed: $_`n"
            Update-StatusBar -Message "Repair-install readiness check failed" -HideProgress
            [System.Windows.MessageBox]::Show(
                "Error running repair-install readiness check:`n`n$_",
                "Error",
                "OK",
                "Error"
            )
        }
    } else {
        Update-StatusBar -Message "Repair-install readiness check cancelled" -HideProgress
    }
})

$W.FindName("BtnRepairTemplates").Add_Click({
    if (-not (Get-Command Get-RepairTemplates -ErrorAction SilentlyContinue)) {
        [System.Windows.MessageBox]::Show(
            "Repair Templates feature not available.`n`nThis feature requires WinRepairCore.ps1 to be loaded.",
            "Feature Not Available",
            "OK",
            "Warning"
        )
        return
    }
    
    $templates = Get-RepairTemplates
    
    # Create template selection window
    $templateWindow = New-Object System.Windows.Window
    $templateWindow.Title = "Repair Templates - One-Click Fixes"
    $templateWindow.Width = 700
    $templateWindow.Height = 500
    $templateWindow.WindowStartupLocation = "CenterScreen"
    
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = "10"
    
    # ListBox for templates
    $listBox = New-Object System.Windows.Controls.ListBox
    $listBox.Margin = "0,0,0,10"
    
    foreach ($template in $templates) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $stackPanel = New-Object System.Windows.Controls.StackPanel
        $stackPanel.Margin = "5"
        
        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $template.Name
        $nameBlock.FontWeight = "Bold"
        $nameBlock.FontSize = "14"
        $stackPanel.Children.Add($nameBlock) | Out-Null
        
        $descBlock = New-Object System.Windows.Controls.TextBlock
        $descBlock.Text = $template.Description
        $descBlock.Foreground = "Gray"
        $descBlock.Margin = "0,5,0,0"
        $descBlock.TextWrapping = "Wrap"
        $stackPanel.Children.Add($descBlock) | Out-Null
        
        $infoBlock = New-Object System.Windows.Controls.TextBlock
        $infoBlock.Text = "Time: $($template.EstimatedTime) | Risk: $($template.RiskLevel)"
        $infoBlock.Foreground = "DarkOrange"
        $infoBlock.Margin = "0,5,0,0"
        $stackPanel.Children.Add($infoBlock) | Out-Null
        
        $item.Content = $stackPanel
        $item.Tag = $template.Id
        $listBox.Items.Add($item) | Out-Null
    }
    
    # Buttons
    $buttonPanel = New-Object System.Windows.Controls.StackPanel
    $buttonPanel.Orientation = "Horizontal"
    $buttonPanel.HorizontalAlignment = "Right"
    
    $executeBtn = New-Object System.Windows.Controls.Button
    $executeBtn.Content = "Execute Template"
    $executeBtn.Width = "150"
    $executeBtn.Height = "30"
    $executeBtn.Margin = "0,0,10,0"
    $executeBtn.IsEnabled = $false
    
    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Width = "100"
    $cancelBtn.Height = "30"
    
    $buttonPanel.Children.Add($executeBtn) | Out-Null
    $buttonPanel.Children.Add($cancelBtn) | Out-Null
    
    # Enable execute button when template is selected
    $listBox.Add_SelectionChanged({
        $executeBtn.IsEnabled = ($listBox.SelectedItem -ne $null)
    })
    
    # Execute button handler
    $executeBtn.Add_Click({
        if ($listBox.SelectedItem) {
            $templateId = $listBox.SelectedItem.Tag
            $templateWindow.DialogResult = $true
            $templateWindow.Close()
            
            # Get drive
            $selectedDrive = $W.FindName("LogDriveCombo").SelectedItem
            $drive = "C"
            if ($selectedDrive) {
                if ($selectedDrive -match '^([A-Z]):') {
                    $drive = $matches[1]
                }
            }
            
            # Execute template
            Update-StatusBar -Message "Executing repair template..." -ShowProgress
            $W.FindName("LogAnalysisBox").Text = "Executing repair template...`n`n"
            
            $progressCallback = {
                param($message)
                $W.Dispatcher.Invoke([action]{
                    $W.FindName("LogAnalysisBox").Text += "$message`n"
                    $W.FindName("LogAnalysisBox").ScrollToEnd()
                    Update-StatusBar -Message $message -ShowProgress
                }, [System.Windows.Threading.DispatcherPriority]::Input)
            }
            
            try {
                $result = Start-RepairTemplate -TemplateId $templateId -TargetDrive $drive -SkipConfirmation -ProgressCallback $progressCallback
                
                $W.FindName("LogAnalysisBox").Text = $result.Report
                $W.FindName("LogAnalysisBox").ScrollToEnd()
                
                if ($result.Success) {
                    [System.Windows.MessageBox]::Show(
                        "✅ Template execution completed successfully!`n`n" +
                        "Steps completed: $($result.StepsCompleted.Count)",
                        "Template Complete",
                        "OK",
                        "Information"
                    )
                } else {
                    [System.Windows.MessageBox]::Show(
                        "⚠ Template execution completed with warnings.`n`n" +
                        "Steps completed: $($result.StepsCompleted.Count)`n" +
                        "Steps failed: $($result.StepsFailed.Count)",
                        "Template Complete",
                        "OK",
                        "Warning"
                    )
                }
                
                Update-StatusBar -Message "Template execution complete" -HideProgress
            } catch {
                $W.FindName("LogAnalysisBox").Text += "`n`n[ERROR] Failed: $_`n"
                Update-StatusBar -Message "Template execution failed" -HideProgress
                [System.Windows.MessageBox]::Show(
                    "Error executing template:`n`n$_",
                    "Error",
                    "OK",
                    "Error"
                )
            }
        }
    })
    
    $cancelBtn.Add_Click({
        $templateWindow.DialogResult = $false
        $templateWindow.Close()
    })
    
    $grid.Children.Add($listBox) | Out-Null
    $grid.Children.Add($buttonPanel) | Out-Null
    
    $templateWindow.Content = $grid
    $templateWindow.ShowDialog() | Out-Null
})

# Repair Install Forcer Handlers
# Update mode description when radio buttons change
$W.FindName("RbOnlineMode").Add_Checked({
    if ($W.FindName("RbOnlineMode").IsChecked) {
        $W.FindName("RepairModeDescription").Text = "This forces Setup to reinstall system files while keeping apps and data. Requires same edition, architecture, and build family. Must run from inside Windows."
        $W.FindName("OfflineDrivePanel").Visibility = "Collapsed"
    }
})

$W.FindName("RbOfflineMode").Add_Checked({
    if ($W.FindName("RbOfflineMode").IsChecked) {
        $W.FindName("RepairModeDescription").Text = "[WARNING] ADVANCED/HACKY METHOD: Forces Setup on non-booting PC by manipulating offline registry hives. Requires WinPE/WinRE environment. This tricks Setup into thinking it's upgrading a running OS. Use with caution."
        $W.FindName("OfflineDrivePanel").Visibility = "Visible"
        
        # Populate offline drive combo
        $W.FindName("RepairOfflineDrive").Items.Clear()
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemLabel } | Sort-Object DriveLetter
        foreach ($vol in $volumes) {
            if ($vol.DriveLetter -ne "X") {
                $testPath = "$($vol.DriveLetter):\Windows"
                if (Test-Path $testPath) {
                    $W.FindName("RepairOfflineDrive").Items.Add("$($vol.DriveLetter):")
                }
            }
        }
        if ($W.FindName("RepairOfflineDrive").Items.Count -gt 0) {
            $W.FindName("RepairOfflineDrive").SelectedIndex = 0
        }
    }
})

$W.FindName("BtnBrowseISO").Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select mounted ISO drive or extracted ISO folder"
    $folderDialog.RootFolder = "MyComputer"
    
    $result = $folderDialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $W.FindName("RepairISOPath").Text = $folderDialog.SelectedPath
    }
})

$W.FindName("BtnShowInstructions").Add_Click({
    $instructions = Get-RepairInstallInstructions
    $W.FindName("RepairInstallOutput").Text = $instructions
    $W.FindName("RepairInstallOutput").ScrollToEnd()
})

$W.FindName("BtnCheckPrereq").Add_Click({
    Update-StatusBar -Message "Checking prerequisites..." -ShowProgress
    $isoPath = $W.FindName("RepairISOPath").Text
    $isOffline = $W.FindName("RbOfflineMode").IsChecked
    
    if ([string]::IsNullOrWhiteSpace($isoPath)) {
        $W.FindName("RepairInstallOutput").Text = "[ERROR] Please specify ISO path first.`n`nClick 'Browse...' to select mounted ISO drive or folder."
        Update-StatusBar -Message "ISO path required" -HideProgress
        return
    }
    
    if ($isOffline) {
        $offlineDrive = $W.FindName("RepairOfflineDrive").SelectedItem
        if (-not $offlineDrive) {
            $W.FindName("RepairInstallOutput").Text = "[ERROR] Please select offline Windows drive first."
            Update-StatusBar -Message "Offline drive required" -HideProgress
            return
        }
        if ($offlineDrive -match '^([A-Z]):') {
            $offlineDrive = $matches[1]
        }
        $prereq = Test-OfflineRepairInstallPrerequisites -ISOPath $isoPath -OfflineWindowsDrive $offlineDrive
    } else {
        $prereq = Test-RepairInstallPrerequisites -ISOPath $isoPath
    }
    
    $output = "PREREQUISITE CHECK RESULTS`n"
    $output += "===============================================================`n`n"
    $output += "ISO Path: $isoPath`n`n"
    
    if ($isOffline) {
        $output += "OFFLINE OS INFORMATION:`n"
        $output += "---------------------------------------------------------------`n"
        $output += "Offline Drive: $($W.FindName("RepairOfflineDrive").SelectedItem)`n"
        $output += "Edition: $($prereq.OfflineOS.EditionID)`n"
        $output += "Architecture: $($prereq.OfflineOS.Architecture)`n"
        $output += "Build Number: $($prereq.OfflineOS.BuildNumber)`n"
        $output += "Version: $($prereq.OfflineOS.Version)`n"
        $output += "Language: $($prereq.OfflineOS.Language)`n`n"
    } else {
        $output += "CURRENT OS INFORMATION:`n"
        $output += "---------------------------------------------------------------`n"
        $output += "Edition: $($prereq.CurrentOS.EditionID)`n"
        $output += "Architecture: $($prereq.CurrentOS.Architecture)`n"
        $output += "Build Number: $($prereq.CurrentOS.BuildNumber)`n"
        $output += "Version: $($prereq.CurrentOS.Version)`n"
        $output += "Language: $($prereq.CurrentOS.Language)`n`n"
    }
    
    if ($prereq.CanProceed) {
        $output += "[SUCCESS] Prerequisites check PASSED`n"
        $output += "===============================================================`n`n"
        $output += "You can proceed with repair install.`n`n"
    } else {
        $output += "[FAILED] Prerequisites check FAILED`n"
        $output += "===============================================================`n`n"
        $output += "BLOCKING ISSUES:`n"
        foreach ($issue in $prereq.Issues) {
            $output += "  ✗ $issue`n"
        }
        $output += "`n"
    }
    
    if ($prereq.Warnings.Count -gt 0) {
        $output += "WARNINGS:`n"
        foreach ($warn in $prereq.Warnings) {
            $output += "  ⚠ $warn`n"
        }
        $output += "`n"
    }
    
    if ($prereq.Recommendations.Count -gt 0) {
        $output += "RECOMMENDATIONS:`n"
        foreach ($rec in $prereq.Recommendations) {
            $output += "  • $rec`n"
        }
        $output += "`n"
    }
    
    $W.FindName("RepairInstallOutput").Text = $output
    $W.FindName("RepairInstallOutput").ScrollToEnd()
    Update-StatusBar -Message "Prerequisites check complete" -HideProgress
})

$W.FindName("BtnStartRepair").Add_Click({
    $isoPath = $W.FindName("RepairISOPath").Text
    $isOffline = $W.FindName("RbOfflineMode").IsChecked
    
    if ([string]::IsNullOrWhiteSpace($isoPath)) {
        [System.Windows.MessageBox]::Show(
            "Please specify ISO path first.`n`nClick 'Browse...' to select mounted ISO drive or folder.",
            "ISO Path Required",
            "OK",
            "Warning"
        )
        return
    }
    
    if ($isOffline) {
        $offlineDrive = $W.FindName("RepairOfflineDrive").SelectedItem
        if (-not $offlineDrive) {
            [System.Windows.MessageBox]::Show(
                "Please select offline Windows drive first.",
                "Offline Drive Required",
                "OK",
                "Warning"
            )
            return
        }
        if ($offlineDrive -match '^([A-Z]):') {
            $offlineDrive = $matches[1]
        }
    }
    
    # Check prerequisites first
    Update-StatusBar -Message "Checking prerequisites..." -ShowProgress
    if ($isOffline) {
        $prereq = Test-OfflineRepairInstallPrerequisites -ISOPath $isoPath -OfflineWindowsDrive $offlineDrive
    } else {
        $prereq = Test-RepairInstallPrerequisites -ISOPath $isoPath
    }
    
    if (-not $prereq.CanProceed) {
        $W.FindName("RepairInstallOutput").Text = "PREREQUISITE CHECK FAILED`n" +
                                                  "===============================================================`n`n" +
                                                  "Cannot proceed with repair install:`n`n" +
                                                  ($prereq.Issues -join "`n") +
                                                  "`n`nPlease fix these issues and try again."
        Update-StatusBar -Message "Prerequisites check failed" -HideProgress
        return
    }
    
    # Get options
    $skipCompat = $W.FindName("ChkSkipCompat").IsChecked
    $disableUpdate = $W.FindName("ChkDisableDynamicUpdate").IsChecked
    $forceEdition = $W.FindName("ChkForceEdition").IsChecked
    
    # Prepare repair install
    Update-StatusBar -Message "Preparing repair install..." -ShowProgress
    if ($isOffline) {
        $repairResult = Start-OfflineRepairInstall -ISOPath $isoPath -OfflineWindowsDrive $offlineDrive -SkipCompatibility:$skipCompat -DisableDynamicUpdate:$disableUpdate
    } else {
        $repairResult = Start-RepairInstall -ISOPath $isoPath -SkipCompatibility:$skipCompat -DisableDynamicUpdate:$disableUpdate -ForceEdition:$forceEdition
    }
    
    if (-not $repairResult.Success) {
        $W.FindName("RepairInstallOutput").Text = $repairResult.Output
        Update-StatusBar -Message "Failed to prepare repair install" -HideProgress
        return
    }
    
    # Show confirmation
    $modeText = if ($isOffline) { "OFFLINE" } else { "ONLINE" }
    $confirmMsg = "$modeText REPAIR INSTALL READY`n`n" +
                 "Command: $($repairResult.Command)`n`n"
    
    if ($isOffline) {
        $confirmMsg += "This will:`n" +
                      "  • Manipulate offline registry hives`n" +
                      "  • Launch Windows Setup against offline OS`n" +
                      "  • Restart and begin repair process`n`n" +
                      "Registry backups saved to:`n"
        foreach ($backup in $repairResult.RegistryBackups) {
            $confirmMsg += "  • $backup`n"
        }
        $confirmMsg += "`n"
    } else {
        $confirmMsg += "This will:`n" +
                      "  • Launch Windows Setup`n" +
                      "  • Restart your system`n" +
                      "  • Begin repair process`n`n"
    }
    
    $confirmMsg += "Monitor progress at: $($repairResult.LogPath)`n`n" +
                  "Do you want to proceed?"
    
    $result = [System.Windows.MessageBox]::Show(
        $confirmMsg,
        "Confirm Repair Install",
        "YesNo",
        "Question"
    )
    
    if ($result -eq "Yes") {
        Update-StatusBar -Message "Starting repair install..." -ShowProgress
        
        $output = "STARTING REPAIR INSTALL`n"
        $output += "===============================================================`n`n"
        $output += $repairResult.Output
        $output += "`n`n[INFO] Launching Windows Setup...`n"
        $output += "System will restart shortly.`n"
        $output += "`nMonitor progress at: $($repairResult.LogPath)`n"
        
        $W.FindName("RepairInstallOutput").Text = $output
        
        try {
            # Execute the setup command
            Start-Process -FilePath $repairResult.Command.Split(' ')[0].Trim('"') -ArgumentList ($repairResult.Command -replace '^"[^"]+"\s*', '') -NoNewWindow -Wait:$false
            
            Update-StatusBar -Message "Repair install started - system will restart" -HideProgress
            
            [System.Windows.MessageBox]::Show(
                "Repair install has been started.`n`nWindows Setup will launch and your system will restart.`n`nMonitor progress at:`n$($repairResult.LogPath)",
                "Repair Install Started",
                "OK",
                "Information"
            )
        } catch {
            $W.FindName("RepairInstallOutput").Text += "`n`n[ERROR] Failed to start repair install: $_`n"
            Update-StatusBar -Message "Failed to start repair install" -HideProgress
        }
    } else {
        Update-StatusBar -Message "Repair install cancelled" -HideProgress
    }
})

$W.ShowDialog() | Out-Null
}


