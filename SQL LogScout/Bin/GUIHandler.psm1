
#=======================================Handle the GUI..
[Collections.Generic.List[GenericModel]]$global:PerfmonCounterList = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_general = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_AlwaysOn = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_core = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_detailed = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_servicebroker_dbmail = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:AdditionalOptionEnabledUIList = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[ServiceState]]$global:List_service_name_status = New-Object Collections.Generic.List[ServiceState]

[String[]]$global:varXevents = "xevent_AlwaysOn_Data_Movement", "xevent_core", "xevent_detailed" , "xevent_general", "xevent_servicebroker_dbmail"
class GenericModel {
    [String]$Caption
    [String]$Value
    [bool]$State
}

class ServiceState {
    [String]$Name
    [String]$Status
}

function InitializeGUIComponent() {
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try {
        Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
        [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
        
        #Fetch current directory
        $CurrentDirectory = Convert-Path -Path "."
        
        #Build files name, with fully qualified path.
        $ConfigPath = $CurrentDirectory + '\Config.xml'
        $XAMLPath = $CurrentDirectory + '\SQLLogScoutView.xaml'
        
        $Launch_XAML = [XML](Get-Content $XAMLPath) 
        $xamlReader_Launch = New-Object System.Xml.XmlNodeReader $Launch_XAML
        $Global:Window = [Windows.Markup.XamlReader]::Load($xamlReader_Launch)
        $Global:txtPresentDirectory = $Global:Window.FindName("txtPresentDirectory") 
        $Global:okButton = $Global:Window.FindName("okButton")

        $Global:XmlDataProviderName = $Global:Window.FindName("XmlDataProviderName")
    

        #create CheckBoxes globals.
        $Global:basicPerfCheckBox = $Global:Window.FindName("basicPerfCheckBox")
        $Global:generalPerfCheckBox = $Global:Window.FindName("generalPerfCheckBox")
        $Global:LightPerfCheckBox = $Global:Window.FindName("LightPerfCheckBox")
        $Global:DetailedPerfCheckBox = $Global:Window.FindName("DetailedPerfCheckBox")
        $Global:replicationPerfCheckBox = $Global:Window.FindName("replicationPerfCheckBox")
        $Global:alwaysOnPerfCheckBox = $Global:Window.FindName("alwaysOnPerfCheckBox")
        $Global:networkTraceCheckBox = $Global:Window.FindName("networkTraceCheckBox")
        $Global:memoryCheckBox = $Global:Window.FindName("memoryCheckBox")
        $Global:dumpMemoryCheckBox = $Global:Window.FindName("dumpMemoryCheckBox")
        $Global:WPRCheckBox = $Global:Window.FindName("WPRCheckBox")
        $Global:SetupCheckBox = $Global:Window.FindName("SetupCheckBox")
        $Global:BackupRestoreCheckBox = $Global:Window.FindName("BackupRestoreCheckBox")
        $Global:IOCheckBox = $Global:Window.FindName("IOCheckBox")
        $Global:ServiceBrokerDbMailCheckBox = $Global:Window.FindName("ServiceBrokerDbMailCheckBox")
        $Global:NeverEndingQueryCheckBox = $Global:window.FindName("NeverEndingQueryCheckBox")
        $Global:NoBasicCheckBox = $Global:Window.FindName("NoBasicCheckBox")
        $Global:overrideExistingCheckBox = $Global:Window.FindName("overrideExistingCheckBox")
        
        $Global:ComboBoxInstanceName = $Global:Window.FindName("ComboBoxInstanceName")
        $Global:ButtonPresentDirectory = $Global:Window.FindName("ButtonPresentDirectory")
        
        $Global:listPerfmon = $Global:Window.FindName("listPerfmon")
        $Global:listXevnets = $Global:Window.FindName("listXevnets")
        $Global:list_xevent_detailed = $Global:Window.FindName("list_xevent_detailed")
        $Global:list_xevent_core = $Global:Window.FindName("list_xevent_core")
        $Global:list_xevent_AlwaysOn = $Global:Window.FindName("list_xevent_AlwaysOn")
        $Global:list_xevent_servicebroker_dbmail = $Global:Window.FindName("list_xevent_servicebroker_dbmail")
        $Global:list_additional_options_enabled = $Global:Window.FindName("list_additional_options_enabled")

        $Global:TVI_xevent_general = $Global:Window.FindName("TVI_xevent_general")
        $Global:TVI_xevent_detailed = $Global:Window.FindName("TVI_xevent_detailed")
        $Global:TVI_xevent_core = $Global:Window.FindName("TVI_xevent_core")
        $Global:TVI_xevent_AlwaysOn = $Global:Window.FindName("TVI_xevent_AlwaysOn")
        $Global:TVI_xevent_servicebroker_dbmail = $Global:Window.FindName("TVI_xevent_servicebroker_dbmail")
        
        $Global:xeventcore_CheckBox = $Global:Window.FindName("xeventcore_CheckBox")
        $Global:XeventAlwaysOn_CheckBox = $Global:Window.FindName("XeventAlwaysOn_CheckBox")
        $Global:XeventGeneral_CheckBox = $Global:Window.FindName("XeventGeneral_CheckBox")
        $Global:XeventDetailed_CheckBox = $Global:Window.FindName("XeventDetailed_CheckBox")
        $Global:XeventServiceBrokerDbMail_CheckBox = $Global:Window.FindName("XeventServiceBrokerDbMail_CheckBox")


        #set the output folder to be parent of folder where execution files reside
        $Global:txtPresentDirectory.Text = (Get-Item $CurrentDirectory).Parent.FullName
        #Read current config.
        $Global:XmlDataProviderName.Source = $ConfigPath
        
        #Setting the item source for various lists.
        $Global:listPerfmon.ItemsSource = $Global:PerfmonCounterList
        $Global:listXevnets.ItemsSource = $Global:XeventsList_general
        $Global:list_xevent_detailed.ItemsSource = $Global:XeventsList_detailed
        $Global:list_xevent_core.ItemsSource = $Global:XeventsList_core
        $Global:list_xevent_AlwaysOn.ItemsSource = $Global:XeventsList_AlwaysOn
        $Global:list_xevent_servicebroker_dbmail.ItemsSource = $Global:XeventsList_servicebroker_dbmail
        $Global:list_additional_options_enabled.ItemsSource = $Global:AdditionalOptionEnabledUIList
             
        RegisterEvents
        Set-PresentDirectory

        Set-OverrideExistingCheckBoxVisibility $Global:txtPresentDirectory.Text
        $Global:txtPresentDirectory.Add_TextChanged({
                Set-OverrideExistingCheckBoxVisibility $Global:txtPresentDirectory.Text
            })
        $Global:Window.Title = $Global:Window.Title + $global:app_version
        $global:gui_Result = $Global:Window.ShowDialog()

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}
function Set-OverrideExistingCheckBoxVisibility([String]$path) {
    $path = $path + "\output"
    if (Test-Path $path) {
        $Global:overrideExistingCheckBox.Visibility = "visible"
    }
    else {
        $Global:overrideExistingCheckBox.Visibility = "hidden"
        $Global:overrideExistingCheckBox.IsChecked = $true
    }
}
function RegisterEvents() {
    $Global:ButtonPresentDirectory.Add_Click({ ButtonPresentDirectory_EventHandler })
    $Global:okButton.Add_Click({ $global:gAdditionalOptionsEnabled = (Get-SelectedAdditionalOptions | Select-Object -Unique); $Global:Window.DialogResult = $true })
    $Global:WPRCheckBox.Add_Click({ DisableAll $Global:WPRCheckBox.IsChecked })
    $Global:Window.Add_Loaded({ Window_Loaded_EventHandler })  
    $Global:DetailedPerfCheckBox.Add_Click({ DetailedPerfCheckBox_Click_EventHandler $Global:DetailedPerfCheckBox.IsChecked })
    $Global:generalPerfCheckBox.Add_Click({ generalPerfCheckBox_Click_EventHandler $Global:generalPerfCheckBox.IsChecked })
    $Global:LightPerfCheckBox.Add_Click({ LightPerfCheckBox_Click_EventHandler $Global:LightPerfCheckBox.IsChecked })
    $Global:alwaysOnPerfCheckBox.Add_Click({ alwaysOnPerfCheckBox_Click_EventHandler $Global:alwaysOnPerfCheckBox.IsChecked })
    $Global:ServiceBrokerDbMailCheckBox.Add_Click({ ServiceBrokerDbMailCheckBox_Click_EventHandler $Global:ServiceBrokerDbMailCheckBox.IsChecked })

    #perfmon counters
    $Global:memoryCheckBox.Add_Click({ Manage_PerfmonCounters $Global:memoryCheckBox.IsChecked })
    $Global:BackupRestoreCheckBox.Add_Click({ Manage_PerfmonCounters $Global:BackupRestoreCheckBox.IsChecked })
    $Global:IOCheckBox.Add_Click({ Manage_PerfmonCounters $Global:IOCheckBox.IsChecked })
    $Global:basicPerfCheckBox.Add_Click({ Manage_PerfmonCounters $Global:basicPerfCheckBox.IsChecked })
    $Global:NoBasicCheckBox.Add_Click({ Manage_PerfmonCounters $Global:NoBasicCheckBox.IsChecked })

    #xevents
    $Global:xeventcore_CheckBox.Add_Click({ HandleCeventcore_CheckBoxClick $Global:xeventcore_CheckBox.IsChecked })
    $Global:XeventAlwaysOn_CheckBox.Add_Click({ AlwaysOn_CheckBoxClick $Global:XeventAlwaysOn_CheckBox.IsChecked })
    $Global:XeventGeneral_CheckBox.Add_Click({ XeventGeneral_CheckBoxClick $Global:XeventGeneral_CheckBox.IsChecked })
    $Global:XeventDetailed_CheckBox.Add_Click({ XeventDetailed_CheckBoxClick $Global:XeventDetailed_CheckBox.IsChecked })
    $Global:NeverEndingQueryCheckBox.Add_Click({ Manage_PerfmonCounters $Global:NeverEndingQueryCheckBox.IsChecked })

    # Keep $global:gAdditionalOptionsEnabled in sync when the user toggles checkboxes in the AdditionalOptions list
    try {
        $Global:list_additional_options_enabled.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, { param($s,$e) HandleAdditionalOptionsListToggle $s $e })
        $Global:list_additional_options_enabled.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, { param($s,$e) HandleAdditionalOptionsListToggle $s $e })
    }
    catch {
        Write-LogDebug "RegisterEvents: unable to wire additional-options handlers: $($_.Exception.Message)" -DebugLogLevel 4
    }

}


function HandleAdditionalOptionsListToggle($toggleBtn, $evt) {
    try {
        $model = $toggleBtn.DataContext

        if ($null -eq $model) 
            { return }
        
        SetGlobalAdditionalOptionState -ModValue $model.Value -Enabled $model.State
    }
    catch {
        Write-LogDebug "HandleAdditionalOptionsListToggle: $($_.Exception.Message)" -DebugLogLevel 4
    }
}

function SetGlobalAdditionalOptionState([string]$ModValue, [bool]$Enabled) {
    try {
        if ($null -eq $global:gAdditionalOptionsEnabled) { $global:gAdditionalOptionsEnabled = @() }

        if ($Enabled) 
        {
            
            if ($global:gAdditionalOptionsEnabled -notcontains $ModValue) 
                { $global:gAdditionalOptionsEnabled += $ModValue }
        }
        else 
        {
            # Remove all instances of the option from the array when unchecked
            if ($global:gAdditionalOptionsEnabled -contains $ModValue) {
                $global:gAdditionalOptionsEnabled = $global:gAdditionalOptionsEnabled | Where-Object { $_ -ne $ModValue }
            }
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function Get-SelectedAdditionalOptions { 
    return $Global:AdditionalOptionEnabledUIList | 
        Where-Object { $_.State } | ForEach-Object { $_.Value } 
}

function HandleCeventcore_CheckBoxClick([bool] $state) {
    

        foreach ($item in $Global:XeventsList_core) {
            [GenericModel] $item = $item
            
            if ($item.Caption -like "*existing_connection*" ) {
                #This should remain always seleted because core xevents is needed to create the main event
                $item.State = $true
            } else {
                $item.State = $state
            }
        }
        $Global:list_xevent_core.ItemsSource = $null
        $Global:list_xevent_core.ItemsSource = $Global:XeventsList_core
        #Core xevent collection is needed because it is the one that creates xevent_SQLLogScout session
        $Global:xeventcore_CheckBox.IsChecked = $Global:TVI_xevent_core.IsEnabled  #$state
}
function AlwaysOn_CheckBoxClick([bool] $state) {
    

        foreach ($item in $Global:XeventsList_AlwaysOn) {
            $item.State = $state
        }
        $Global:XeventAlwaysOn_CheckBox.IsChecked = $state
        $Global:list_xevent_AlwaysOn.ItemsSource = $null
        $Global:list_xevent_AlwaysOn.ItemsSource = $Global:XeventsList_AlwaysOn
    
}

function XeventGeneral_CheckBoxClick([bool] $state) {
    

        foreach ($item in $Global:XeventsList_general) {
            $item.State = $state
        }
        $Global:listXevnets.ItemsSource = $null
        $Global:listXevnets.ItemsSource = $Global:XeventsList_general
        $Global:XeventGeneral_CheckBox.IsChecked = $state

    
}

function XeventDetailed_CheckBoxClick([bool] $state) {
    

        foreach ($item in $Global:XeventsList_detailed) {
            $item.State = $state
        }
        $Global:XeventDetailed_CheckBox.IsChecked = $state
        $Global:list_xevent_detailed.ItemsSource = $null
        $Global:list_xevent_detailed.ItemsSource = $Global:XeventsList_detailed
    
}

function XeventServiceBrokerDbMail_CheckBoxClick([bool] $state) {
    

    foreach ($item in $Global:XeventsList_servicebroker_dbmail) {
        $item.State = $state
    }

    $Global:XeventServiceBrokerDbMail_CheckBox.IsChecked = $state
    $Global:list_xevent_servicebroker_dbmail.ItemsSource = $null
    $Global:list_xevent_servicebroker_dbmail.ItemsSource = $Global:XeventsList_servicebroker_dbmail
}

function ButtonPresentDirectory_EventHandler() {
    $objForm = New-Object System.Windows.Forms.FolderBrowserDialog
    $Show = $objForm.ShowDialog()
    if ($Show -eq "OK") {
        $Global:txtPresentDirectory.Text = $objForm.SelectedPath;
    }
}

function Window_Loaded_EventHandler() {

    BuildServiceNameStatusModel
    BuildPermonModel
    BuildXEventsModel_general
    BuildXEventsModel_core
    BuildXEventsModel_detailed
    BuildXEventsModel_AlwaysOn
    BuildXEventsModel_servicebroker_dbmail
    BuildAdditionalOptionsEnabledModel


    Manage_PerfmonCounters($false)
    HandleCeventcore_CheckBoxClick($false)
    AlwaysOn_CheckBoxClick($false)
    XeventGeneral_CheckBoxClick($false)
    XeventDetailed_CheckBoxClick($false)
    XeventServiceBrokerDbMail_CheckBoxClick($false)

}
function Manage_PerfmonCounters([bool] $state) {
    if ($Global:DetailedPerfCheckBox.IsChecked -or
        $Global:generalPerfCheckBox.IsChecked -or
        $Global:LightPerfCheckBox.IsChecked -or
        $Global:alwaysOnPerfCheckBox.IsChecked -or
        $Global:memoryCheckBox.IsChecked -or
        $Global:BackupRestoreCheckBox.IsChecked -or
        $Global:IOCheckBox.IsChecked -or
        $Global:basicPerfCheckBox.IsChecked -or
        $Global:NeverEndingQueryCheckBox.IsChecked -or
        $Global:ServiceBrokerDbMailCheckBox.IsChecked -or
        $Global:basicPerfCheckBox.IsChecked) {
        $Global:listPerfmon.IsEnabled = $true
        foreach ($item in $Global:PerfmonCounterList) {
            $item.State = $true
        }
        $Global:listPerfmon.ItemsSource = $null
        $Global:listPerfmon.ItemsSource = $Global:PerfmonCounterList
    }
    else {
        $Global:listPerfmon.IsEnabled = $false

        foreach ($item in $Global:PerfmonCounterList) {
            $item.State = $false
        }
        $Global:listPerfmon.ItemsSource = $null
        $Global:listPerfmon.ItemsSource = $Global:PerfmonCounterList
    }
}


# function ManageAdditionalOptionsEnabled([bool]$Enable) {
#     try 
#     {   
#         foreach ($item in $Global:AdditionalOptionEnabledUIList) {
#             $item.State = $true
#         }
        
#         $Global:list_additional_options_enabled.ItemsSource = $null
#         $Global:list_additional_options_enabled.ItemsSource = $Global:AdditionalOptionEnabledUIList
#     }
#     catch {
#         HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
#     }
# }


function BuildAdditionalOptionsEnabledModel() {
    try {
        # Ensure the UI list is empty before building
        $Global:AdditionalOptionEnabledUIList.Clear()

        # populate the list with the valid items and check any boxes if they were supplied via command line
        foreach ($add_optn in $global:ValidAdditionalOptions) {
            $AdditionalOptionsObj = [GenericModel]::new()
            $AdditionalOptionsObj.Caption = $add_optn
            $AdditionalOptionsObj.Value = $add_optn
            # Pre-check items if they were supplied via the CLI
            $AdditionalOptionsObj.State = ($null -ne $global:gAdditionalOptionsEnabled -and $global:gAdditionalOptionsEnabled -contains $add_optn)
            $Global:AdditionalOptionEnabledUIList.Add($AdditionalOptionsObj)
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function DetailedPerfCheckBox_Click_EventHandler([bool] $state) {
    #$Global:basicPerfCheckBox.IsChecked = $false
    #$Global:basicPerfCheckBox.IsEnabled = !$state
    
    $Global:generalPerfCheckBox.IsChecked = $false
    $Global:LightPerfCheckBox.IsChecked = $false
    
    $Global:generalPerfCheckBox.IsEnabled = !$state
    $Global:LightPerfCheckBox.IsEnabled = !$state

    $Global:TVI_xevent_general.IsEnabled = $false
    $Global:TVI_xevent_detailed.IsEnabled = $state
    $Global:TVI_xevent_core.IsEnabled = $state
    HandleCeventcore_CheckBoxClick($state)
    XeventGeneral_CheckBoxClick($false)
    XeventDetailed_CheckBoxClick($state)
    Manage_PerfmonCounters($state)
}

function LightPerfCheckBox_Click_EventHandler([bool] $state) {
    $Global:TVI_xevent_general.IsEnabled = $false
    $Global:TVI_xevent_detailed.IsEnabled = $false
    $Global:TVI_xevent_core.IsEnabled = $false
    XeventGeneral_CheckBoxClick($false)
    XeventDetailed_CheckBoxClick($false)
    HandleCeventcore_CheckBoxClick($false)
    Manage_PerfmonCounters($state)
}

function generalPerfCheckBox_Click_EventHandler([bool] $state) {
    $Global:LightPerfCheckBox.IsChecked = $false
    $Global:LightPerfCheckBox.IsEnabled = !$state
    $Global:TVI_xevent_general.IsEnabled = $state
    $Global:TVI_xevent_general.IsEnabled = $state
    $Global:TVI_xevent_detailed.IsEnabled = $false
    $Global:TVI_xevent_core.IsEnabled = $state
    XeventDetailed_CheckBoxClick($false)
    XeventGeneral_CheckBoxClick($state)
    HandleCeventcore_CheckBoxClick($state)
    Manage_PerfmonCounters(!$state)
    
    
}

function alwaysOnPerfCheckBox_Click_EventHandler([bool] $state) {
    $Global:TVI_xevent_AlwaysOn.IsEnabled = $state 
    $Global:TVI_xevent_core.IsEnabled = $state
    HandleCeventcore_CheckBoxClick($state)
    AlwaysOn_CheckBoxClick($state)
    Manage_PerfmonCounters($state)
    if(!$state)
    {
       if($Global:generalPerfCheckBox.IsChecked)
        {
          generalPerfCheckBox_Click_EventHandler $Global:generalPerfCheckBox.IsChecked
        }
           if($Global:DetailedPerfCheckBox.IsChecked)
        {
               DetailedPerfCheckBox_Click_EventHandler $Global:DetailedPerfCheckBox.IsChecked
        }
    }
}

function ServiceBrokerDbMailCheckBox_Click_EventHandler([bool] $state) {

    $Global:TVI_xevent_core.IsEnabled = $state
    $Global:TVI_xevent_servicebroker_dbmail.IsEnabled = $state

    XeventServiceBrokerDbMail_CheckBoxClick($state)
    HandleCeventcore_CheckBoxClick($state)
    Manage_PerfmonCounters($state)

}


function Set-Mode() {

    try {

        # if Scenario, ServerName, CustomOutputPath and DeleteExistingOrCreateNew parameters are not null, no need to offer GUI
        if (($true -ne [String]::IsNullOrWhiteSpace($global:custom_user_directory)) `
                -and ($true -ne [String]::IsNullOrWhiteSpace($global:gDeleteExistingOrCreateNew)) `
                -and ($true -ne [String]::IsNullOrWhiteSpace($global:gServerName)) `
                -and ($true -ne [String]::IsNullOrWhiteSpace($global:gScenario)) 
        ) { 
            $global:gui_mode = $false; 
            return 
        }

        Write-LogDebug "inside" $MyInvocation.MyCommand
       
        $userlogfolder = Read-Host "Would you like to use GUI mode ?> (Y/N)" -CustomLogMessage "Prompt GUI mode Input:"
        $HelpMessage = "Please enter a valid input (Y or N)"

        $ValidInput = "Y", "N"
        $AllInput = @()
        $AllInput += , $ValidInput
        $AllInput += , $userlogfolder
        $AllInput += , $HelpMessage

        $YNselected = validateUserInput($AllInput)
            

        if ($YNselected -eq "Y") {
            $global:gui_mode = $true;
        }


    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        exit
    }

}

function EnableScenarioFromGUI {
    #Note: this required big time optimization is just for testing purpose.
    if ($Global:basicPerfCheckBox.IsChecked) {
        $global:gScenario += "Basic+"
    }
    if ($Global:generalPerfCheckBox.IsChecked) {
        $global:gScenario += "GeneralPerf+"
    }
    if ($Global:DetailedPerfCheckBox.IsChecked) {
        $global:gScenario += "DetailedPerf+"
    }
    if ($Global:LightPerfCheckBox.IsChecked) {
        $global:gScenario += "LightPerf+"
    }
    if ($Global:replicationPerfCheckBox.IsChecked) {
        $global:gScenario += "Replication+"
    }
    if ($Global:alwaysOnPerfCheckBox.IsChecked) {
        $global:gScenario += "AlwaysOn+"
    }
    if ($Global:networkTraceCheckBox.IsChecked) {
        $global:gScenario += "NetworkTrace+"
    }
    if ($Global:memoryCheckBox.IsChecked) {
        $global:gScenario += "Memory+"
    }
    if ($Global:dumpMemoryCheckBox.IsChecked) {
        $global:gScenario += "DumpMemory+"
    }
    if ($Global:WPRCheckBox.IsChecked) {
        $global:gScenario += "WPR+"
    }
    if ($Global:SetupCheckBox.IsChecked) {
        $global:gScenario += "Setup+"
    }
    if ($Global:BackupRestoreCheckBox.IsChecked) {
        $global:gScenario += "BackupRestore+"
    }
    if ($Global:IOCheckBox.IsChecked) { 
        $global:gScenario += "IO+"
    }
    if ($Global:NeverEndingQueryCheckBox.IsChecked) {
        $global:gScenario += "NeverEndingQuery+"
    }
    if ($Global:ServiceBrokerDbMailCheckBox.IsChecked) { 
        $global:gScenario += "ServiceBrokerDbMail+"
    }
    if ($Global:NoBasicCheckBox.IsChecked) { 
        $global:gScenario += "NoBasic+"
    }
}

function BuildPermonModel() {
    try {
        Write-LogDebug "inside -BuildPermonModel method"   
        #Read LogmanConfig and fill the UI model. 
        foreach ($line in Get-Content .\LogmanConfig.txt) {
            $PerfmonModelobj = New-Object GenericModel
            $PerfmonModelobj.Value = $line
            $PerfmonModelobj.Caption = $line.split('\')[1]
            $PerfmonModelobj.State = $false
            $Global:PerfmonCounterList.Add($PerfmonModelobj)
        }
    }
    catch {
        HandleCatchBlock -function_name
        exit
    }

}

function DisableAll([bool] $state) {
    #$Global:basicPerfCheckBox.IsChecked = $false
    # $Global:basicPerfCheckBox.IsEnabled = !$state

    $Global:generalPerfCheckBox.IsChecked = $false
    $Global:DetailedPerfCheckBox.IsChecked = $false
    $Global:LightPerfCheckBox.IsChecked = $false
    $Global:replicationPerfCheckBox.IsChecked = $false
    $Global:alwaysOnPerfCheckBox.IsChecked = $false
    $Global:networkTraceCheckBox.IsChecked = $false
    $Global:memoryCheckBox.IsChecked = $false
    $Global:dumpMemoryCheckBox.IsChecked = $false
    $Global:SetupCheckBox.IsChecked = $false
    $Global:BackupRestoreCheckBox.IsChecked = $false
    $Global:IOCheckBox.IsChecked = $false
    $Global:NeverEndingQueryCheckBox.IsChecked = $false
    $Global:ServiceBrokerDbMailCheckBox.IsChecked = $false
    $Global:generalPerfCheckBox.IsEnabled = !$state
    $Global:DetailedPerfCheckBox.IsEnabled = !$state
    $Global:LightPerfCheckBox.IsEnabled = !$state
    $Global:replicationPerfCheckBox.IsEnabled = !$state
    $Global:alwaysOnPerfCheckBox.IsEnabled = !$state
    $Global:networkTraceCheckBox.IsEnabled = !$state
    $Global:memoryCheckBox.IsEnabled = !$state
    $Global:dumpMemoryCheckBox.IsEnabled = !$state
    $Global:SetupCheckBox.IsEnabled = !$state
    $Global:BackupRestoreCheckBox.IsEnabled = !$state
    $Global:IOCheckBox.IsEnabled = !$state
    $Global:NeverEndingQueryCheckBox.IsEnabled = !$state
    $Global:ServiceBrokerDbMailCheckBox.IsEnabled = !$state
}

function GenerateXeventFileFromGUI {
    Write-LogDebug "inside" $MyInvocation.MyCommand  
    try {
        CreateFile -mylist $Global:XeventsList_general -fileName "xevent_general.sql"
        MakeSureCreateBeforeAlterEvent -mylist $Global:XeventsList_core -pattern "EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT"
        CreateFile -mylist $Global:XeventsList_core -fileName 'xevent_core.sql'
        CreateFile -mylist $Global:XeventsList_detailed -fileName 'xevent_detailed.sql'

        CreateFile -mylist $Global:XeventsList_servicebroker_dbmail -fileName 'xevent_servicebroker_dbmail.sql'

        MakeSureCreateBeforeAlterEvent -mylist $Global:XeventsList_AlwaysOn -pattern " EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER"
        CreateFile -mylist $Global:XeventsList_AlwaysOn -fileName 'xevent_AlwaysOn_Data_Movement.sql'
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
    }
    
}

function MakeSureCreateBeforeAlterEvent($myList, [String]$pattern) {
    $flag = $true
    $patternToBeReplaced = "ALTER " + $pattern
    $patternToBeReplacedWith = "CREATE " + $pattern
    foreach ($item in $myList) {
        if ($item.State -eq $true) { 
            if ($flag -and $item.Value.Contains($pattern)) {
                $item.Value = $item.Value.Replace($patternToBeReplaced, $patternToBeReplacedWith)
                $flag = $false
            }
        }
    }
}


function CreateFile($myList, [string]$fileName) {
    Write-LogDebug "inside" $MyInvocation.MyCommand  
    try {
        $internal_path = $global:internal_output_folder
        $destinationFile = $internal_path + $fileName
        foreach ($item in $myList) {
            if ($item.State -eq $true) { 
                Add-Content $destinationFile $item.Value
            }
        }
        Add-Content $destinationFile "GO"    
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
    }
}
function BuildXEventsModel_general() {
    Import-Module .\SQLScript_xevent_general.psm1 
    try {
        Write-LogDebug "inside" $MyInvocation.MyCommand  
        Write-LogDebug "BuildXEventsModel...."
        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel
        $content = xevent_general_Query -returnVariable $true

        foreach ($element in $content <#Get-Content .\xevent_general.sql#>) {
            if ($element.Trim() -eq "GO") { 
                $GenericModelobj.Value = $xevent_string
                $GenericModelobj.State = $true
                $Global:XeventsList_general.Add($GenericModelobj)
                $GenericModelobj = New-Object GenericModel
                $xevent_string = New-Object -TypeName System.Text.StringBuilder
                [void]$xevent_string.Append("GO `r`n")
            }
            else {
                [void]$xevent_string.Append($element)
                [void]$xevent_string.Append("`r`n")
                
                #$GenericModelobj.Value = $line
                if ($element.contains("[xevent_SQLLogScout]")) {
                    $temp = $element.split('(')[0].split('.')
                    if ($temp.count -eq 2) {
                        $GenericModelobj.Caption = $temp[1]
                    }

                }
            }
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
        exit
    }
}

function BuildXEventsModel_core() {
    try {
        Write-LogDebug "inside" $MyInvocation.MyCommand  

        Import-Module .\SQLScript_xevent_core.psm1

        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel
        $content = xevent_core_Query -returnVariable $true

        foreach ($element in $content <#Get-Content .\xevent_core.sql#>) {
            if ($element.Trim() -eq "GO") { 
                $GenericModelobj.Value = $xevent_string
                $GenericModelobj.State = $true
                $Global:XeventsList_core.Add($GenericModelobj)
                 
                $GenericModelobj = New-Object GenericModel
                $xevent_string = New-Object -TypeName System.Text.StringBuilder
                [void]$xevent_string.Append("GO `r`n")
            }
            else {
                [void]$xevent_string.Append($element)
                [void]$xevent_string.Append("`r`n")
                
                #$GenericModelobj.Value = $line
                if ($element.contains("[xevent_SQLLogScout]")) {
                    $temp = $element.split('(')[0].split('.')
                    if ($temp.count -eq 2) {
                        $GenericModelobj.Caption = $temp[1]
                    }

                }
            }
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
        exit
    }

}

function BuildXEventsModel_detailed() {
    Import-Module .\SQLScript_xevent_detailed.psm1

    try {
        Write-LogDebug "inside" $MyInvocation.MyCommand  
        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel
        $content = xevent_detailed_Query -returnVariable $true

        foreach ($element in $content) {
            if ($element.Trim() -eq "GO") { 
                $GenericModelobj.Value = $xevent_string
                $GenericModelobj.State = $true
                $Global:XeventsList_detailed.Add($GenericModelobj)
                 
                $GenericModelobj = New-Object GenericModel
                $xevent_string = New-Object -TypeName System.Text.StringBuilder
                [void]$xevent_string.Append("GO `r`n")
            }
            else {
                [void]$xevent_string.Append($element)
                [void]$xevent_string.Append("`r`n")
                
                #$GenericModelobj.Value = $line
                if ($element.contains("[xevent_SQLLogScout]")) {
                    $temp = $element.split('(')[0].split('.')
                    if ($temp.count -eq 2) {
                        $GenericModelobj.Caption = $temp[1]
                    }

                }
            }
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
        exit
    }

}

function BuildXEventsModel_AlwaysOn() {
    Import-Module .\SQLScript_xevent_AlwaysOn_Data_Movement.psm1
    try {
        Write-LogDebug "inside" $MyInvocation.MyCommand  
        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel
        $content = xevent_AlwaysOn_Data_Movement_Query -returnVariable $true
        foreach ($element in $content ) {
            if ($element.Trim() -eq "GO")  { 
                $GenericModelobj.Value = $xevent_string
                $GenericModelobj.State = $true
                $Global:XeventsList_AlwaysOn.Add($GenericModelobj)
                 
                $GenericModelobj = New-Object GenericModel
                $xevent_string = New-Object -TypeName System.Text.StringBuilder
                [void]$xevent_string.Append("GO `r`n")
            }
            else {
                [void]$xevent_string.Append($element)
                [void]$xevent_string.Append("`r`n")
                if ($element.contains("[SQLLogScout_AlwaysOn_Data_Movement]")) {

                    $temp = $element.split('(')[0].split('.')
                    if ($temp.count -eq 2) {
                        $GenericModelobj.Caption = $temp[1]
                    }

                }
            }
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
        exit
    }

}


function BuildXEventsModel_servicebroker_dbmail() {
    Import-Module .\SQLScript_xevent_servicebroker_dbmail.psm1
    try {
        Write-LogDebug "inside" $MyInvocation.MyCommand  
        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel

        $content = xevent_servicebroker_dbmail_Query -returnVariable $true
        foreach ($element in $content ) {
            if ($element.Trim() -eq "GO") { 
                $GenericModelobj.Value = $xevent_string
                $GenericModelobj.State = $true
                $global:XeventsList_servicebroker_dbmail.Add($GenericModelobj)
                 
                # reset the object and string builder
                $GenericModelobj = New-Object GenericModel
                $xevent_string = New-Object -TypeName System.Text.StringBuilder
                [void]$xevent_string.Append("GO `r`n")
            }
            else {
                [void]$xevent_string.Append($element)
                [void]$xevent_string.Append("`r`n")
                
                #$GenericModelobj.Value = $line
                # get the event name from the event session and add it to the model
                if ($element.contains("[xevent_SQLLogScout]")) {
                    $temp = $element.split('(')[0].split('.')
                    if ($temp.count -eq 2) {
                        $GenericModelobj.Caption = $temp[1]
                    }

                }
            }
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
        exit
    }

}

function BuildServiceNameStatusModel() {

    try 
    {
        foreach ($Instance in Get-NetNameMatchingInstance) 
        { 
            $global:List_service_name_status.Add((New-Object ServiceState -Property @{Name=$Instance.Name; Status=$Instance.Status}))
            
        }   
        
        $ComboBoxInstanceName.ItemsSource = $global:List_service_name_status 
    }
    
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
        exit
    }
}

# SIG # Begin signature block
# MIIr5AYJKoZIhvcNAQcCoIIr1TCCK9ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCT8wDSWXnlP2IJ
# Oful0ReognnLYedZr6Nuxo5bv9AxFaCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
# D0nu2y38AAIAAAINMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzA5MzBaFw0yNjA0MjYyMzE5MzBaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCpj9ry6z6v08TIeKoxS2+5c928SwYKDXCyPWZHpm3xIHTqBBmlTM1GO7X4
# ap5jj/wroH7TzukJtfLR6Z4rBkjdlocHYJ2qU7ggik1FDeVL1uMnl5fPAB0ETjqt
# rk3Lt2xT27XUoNlKfnFcnmVpIaZ6fnSAi2liEhbHqce5qEJbGwv6FiliSJzkmeTK
# 6YoQQ4jq0kK9ToBGMmRiLKZXTO1SCAa7B4+96EMK3yKIXnBMdnKhWewBsU+t1LHW
# vB8jt8poBYSg5+91Faf9oFDvl5+BFWVbJ9+mYWbOzJ9/ZX1J4yvUoZChaykKGaTl
# k51DUoZymsBuatWbJsGzo0d43gMLAgMBAAGjggWKMIIFhjApBgkrBgEEAYI3FQoE
# HDAaMAwGCisGAQQBgjdbAQEwCgYIKwYBBQUHAwMwPQYJKwYBBAGCNxUHBDAwLgYm
# KwYBBAGCNxUIhpDjDYTVtHiE8Ys+hZvdFs6dEoFgg93NZoaUjDICAWQCAQ4wggJ2
# BggrBgEFBQcBAQSCAmgwggJkMGIGCCsGAQUFBzAChlZodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpaW5mcmEvQ2VydHMvQlkyUEtJQ1NDQTAxLkFNRS5HQkxfQU1F
# JTIwQ1MlMjBDQSUyMDAxKDIpLmNydDBSBggrBgEFBQcwAoZGaHR0cDovL2NybDEu
# YW1lLmdibC9haWEvQlkyUEtJQ1NDQTAxLkFNRS5HQkxfQU1FJTIwQ1MlMjBDQSUy
# MDAxKDIpLmNydDBSBggrBgEFBQcwAoZGaHR0cDovL2NybDIuYW1lLmdibC9haWEv
# QlkyUEtJQ1NDQTAxLkFNRS5HQkxfQU1FJTIwQ1MlMjBDQSUyMDAxKDIpLmNydDBS
# BggrBgEFBQcwAoZGaHR0cDovL2NybDMuYW1lLmdibC9haWEvQlkyUEtJQ1NDQTAx
# LkFNRS5HQkxfQU1FJTIwQ1MlMjBDQSUyMDAxKDIpLmNydDBSBggrBgEFBQcwAoZG
# aHR0cDovL2NybDQuYW1lLmdibC9haWEvQlkyUEtJQ1NDQTAxLkFNRS5HQkxfQU1F
# JTIwQ1MlMjBDQSUyMDAxKDIpLmNydDCBrQYIKwYBBQUHMAKGgaBsZGFwOi8vL0NO
# PUFNRSUyMENTJTIwQ0ElMjAwMSxDTj1BSUEsQ049UHVibGljJTIwS2V5JTIwU2Vy
# dmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1BTUUsREM9R0JM
# P2NBQ2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0
# aG9yaXR5MB0GA1UdDgQWBBS6kl+vZengaA7Cc8nJtd6sYRNA3jAOBgNVHQ8BAf8E
# BAMCB4AwRQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEWMBQGA1UEBRMNMjM2MTY3KzUwNjA0MjCCAeYGA1UdHwSCAd0wggHZMIIB
# 1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpaW5mcmEvQ1JM
# L0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwxLmFtZS5nYmwv
# Y3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwyLmFtZS5n
# YmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwzLmFt
# ZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmw0
# LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGgb1sZGFwOi8v
# L0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQS0lDU0NBMDEsQ049Q0RQ
# LENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZp
# Z3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0
# P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwHwYDVR0jBBgw
# FoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgwFgYKKwYBBAGCN1sBAQYI
# KwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAJKGB9zyDWN/9twAY6qCLnfDCKc/
# PuXoCYI5Snobtv15QHAJwwBJ7mr907EmcwECzMnK2M2auU/OUHjdXYUOG5TV5L7W
# xvf0xBqluWldZjvnv2L4mANIOk18KgcSmlhdVHT8AdehHXSs7NMG2di0cPzY+4Ol
# 2EJ3nw2JSZimBQdRcoZxDjoCGFmHV8lOHpO2wfhacq0T5NK15yQqXEdT+iRivdhd
# i/n26SOuPDa6Y/cCKca3CQloCQ1K6NUzt+P6E8GW+FtvcLza5dAWjJLVvfemwVyl
# JFdnqejZPbYBRdNefyLZjFsRTBaxORl6XG3kiz2t6xeFLLRTJgPPATx1S7Awggjo
# MIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0GCSqGSIb3DQEBCwUAMDwx
# EzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxEDAOBgNV
# BAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYwNTIxMTg1NDE0WjBBMRMw
# EQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQD
# EwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDJ
# mlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL9rNHnHDGfJgeuRIYO1LY
# /1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc411WxA+Pv2rteAcz0eHM
# H36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaCIIWBXyEchv+sM9eKDsUO
# LdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8pXirIYOgM770CYOiZrcKH
# K7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p/6fksgEILptOKhx9c+ia
# piNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkrBgEEAYI3FQEEBQIDAgAC
# MCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMALI38/RzAdBgNVHQ4EFgQU
# llGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfwwgfkGBysGAQUCAwUGCCsG
# AQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYBBAGCNxUGBgorBgEEAYI3
# CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgCAgYKKwYBBAGCN0ABAQYL
# KwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcVBQYKKwYBBAGCNxQCAgYK
# KwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEGCisGAQQBgjdbAgEGCisG
# AQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEGCisGAQQBgjdbBAIwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwNp4x1AdEJCygwggFoBgNV
# HR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDovL2NybDIuYW1lLmdibC9j
# cmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL2FtZXJvb3Qu
# Y3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVyb290LmNybIaBqmxkYXA6
# Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPUFNRSxE
# Qz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNz
# PWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUHAQEEggGdMIIBmTBHBggr
# BgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NlcnRz
# L0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwyLmFt
# ZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6
# Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUH
# MAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQw
# gaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290LENOPUFJQSxDTj1QdWJs
# aWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9u
# LERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29iamVjdENsYXNzPWNl
# cnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQELBQADggIBAFAQI7dPD+jf
# XtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTHb8BDfRN+AD0YEmeDB5HK
# QoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a/752hMIn+L4ZuyxVeSBp
# fwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9zAh9yRKKls2bziPEnxeO
# ZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAmn3WCPWNFC1YTIIHw/mD2
# cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtzyb7fbNS1dE740re0COE6
# 7YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjFK1yMw4Ni5fMabcgmzRvS
# jAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bzMzsikuDW9xH10graZzSm
# PjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIzJ6Q9G3NPCB+7KwX0OQmK
# yv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/ywO6SYSreVW+5Y0mzJutn
# BC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEISRtShDZbuYymynY1un+Ry
# fiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZzDCCGcgCAQEwWDBBMRMwEQYKCZIm
# iZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQDEwxBTUUg
# Q1MgQ0EgMDECEzYAAAIN4oQPSe7bLfwAAgAAAg0wDQYJYIZIAWUDBAIBBQCgga4w
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJRPHRQCxG7I2ukLcng8Zw79QW9fip59
# YZvDt3LfUgifMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# nDXqUYyvZwLe2ELzk0sP4VfcBsVuZbabbHUFg8wjN+QcLIoNEAFNPOPeiWaWaeQR
# Wi/WkAcI1lg3VNimqiioxLsrzwZ+ORzLyLAsP0jZ4R+R03M2f6c+cS7Ku5OArvcG
# 98G1c7A84gsmImszqtBPlWdLzaB6fAWQtKioffcwyElP8vPLCRfimNZu7ro7aZAH
# rj+LlL/dw+25iQYreicViMhNAP227ld8FpCoBeKti2zVCEt/WjVDJ8smNlc5yI6d
# MunYXZuYoPprh9sB+/x/KIP6xCJfAehxr8zgr3acXx7m6ijO7Q1MwrlsLqg6dc9w
# ugaA5AW+FhjZPx0a8I5WRaGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCBR76UG81TxcqaQXWGCBPOdjBvOBqZ+9x1FAOfN2VF/lwIGaWjjQl4LGBMyMDI2
# MDIwNDE2MzUyNy4yNzhaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODYwMy0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIH
# IDCCBQigAwIBAgITMwAAAgcsETmJzYX7xQABAAACBzANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNTJaFw0y
# NjA0MjIxOTQyNTJaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046ODYwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQDFP/96dPmcfgODe3/nuFveuBst/JmSxSkOn89ZFytHQm344iLo
# PqkVws+CiUejQabKf+/c7KU1nqwAmmtiPnG8zm4Sl9+RJZaQ4Dx3qtA9mdQdS7Ch
# f6YUbP4Z++8laNbTQigJoXCmzlV34vmC4zpFrET4KAATjXSPK0sQuFhKr7ltNaMF
# GclXSnIhcnScj9QUDVLQpAsJtsKHyHN7cN74aEXLpFGc1I+WYFRxaTgqSPqGRfEf
# uQ2yGrAbWjJYOXueeTA1MVKhW8zzSEpfjKeK/t2XuKykpCUaKn5s8sqNbI3bHt/r
# E/pNzwWnAKz+POBRbJxIkmL+n/EMVir5u8uyWPl1t88MK551AGVh+2H4ziR14YDx
# zyCG924gaonKjicYnWUBOtXrnPK6AS/LN6Y+8Kxh26a6vKbFbzaqWXAjzEiQ8EY9
# K9pYI/KCygixjDwHfUgVSWCyT8Kw7mGByUZmRPPxXONluMe/P8CtBJMpuh8CBWyj
# vFfFmOSNRK8ETkUmlTUAR1CIOaeBqLGwscShFfyvDQrbChmhXib4nRMX5U9Yr9d7
# VcYHn6eZJsgyzh5QKlIbCQC/YvhFK42ceCBDMbc+Ot5R6T/Mwce5jVyVCmqXVxWO
# aQc4rA2nV7onMOZC6UvCG8LGFSZBnj1loDDLWo/I+RuRok2j/Q4zcMnwkQIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFHK1UmLCvXrQCvR98JBq18/4zo0eMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQDju0quPbnix0slEjD7j2224pYOPGTmdDvO0+bNRCNk
# ZqUv07P04nf1If3Y/iJEmUaU7w12Fm582ImpD/Kw2ClXrNKLPTBO6nfxvOPGtalp
# Al4wqoGgZxvpxb2yEunG4yZQ6EQOpg1dE9uOXoze3gD4Hjtcc75kca8yivowEI+r
# hXuVUWB7vog4TGUxKdnDvpk5GSGXnOhPDhdId+g6hRyXdZiwgEa+q9M9Xctz4TGh
# DgOKFsYxFhXNJZo9KRuGq6evhtyNduYrkzjDtWS6gW8akR59UhuLGsVq+4AgqEY8
# WlXjQGM2OTkyBnlQLpB8qD7x9jRpY2Cq0OWWlK0wfH/1zefrWN5+be87Sw2TPcIu
# dIJn39bbDG7awKMVYDHfsPJ8ZvxgWkZuf6ZZAkph0eYGh3IV845taLkdLOCvw49W
# xqha5Dmi2Ojh8Gja5v9kyY3KTFyX3T4C2scxfgp/6xRd+DGOhNVPvVPa/3yRUqY5
# s5UYpy8DnbppV7nQO2se3HvCSbrb+yPyeob1kUfMYa9fE2bEsoMbOaHRgGji8ZPt
# /Jd2bPfdQoBHcUOqPwjHBUIcSc7xdJZYjRb4m81qxjma3DLjuOFljMZTYovRiGvE
# ML9xZj2pHRUyv+s5v7VGwcM6rjNYM4qzZQM6A2RGYJGU780GQG0QO98w+sucuTVr
# fTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
# BQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNV
# BAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4X
# DTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM
# 57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm
# 95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzB
# RMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBb
# fowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCO
# Mcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYw
# XE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW
# /aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/w
# EPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPK
# Z6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2
# BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfH
# CBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYB
# BAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8v
# BO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEF
# BQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBW
# BgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUH
# AQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# L2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsF
# AAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518Jx
# Nj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+
# iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2
# pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefw
# C2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7
# T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFO
# Ry3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhL
# mm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3L
# wUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5
# m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE
# 0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIICNQIB
# ATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOjg2MDMtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDTvVU/Yj9l
# USyeDCaiJ2Da5hUiS6CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S28KTAiGA8yMDI2MDIwNDEyMzgwMVoYDzIw
# MjYwMjA1MTIzODAxWjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDtLbwpAgEAMAcC
# AQACAgwnMAcCAQACAhJlMAoCBQDtLw2pAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEL
# BQADggEBAIIdrcApLSM72/9Fg/mCcoZkxw0+uF0DoGMKEGt/4gdioTkG1Ryno4GQ
# X1O8RGJXZe8YxsXL8PBGYBtIDQAPfB5TbIdzo6bxmf5FwMDTp5MUkDGnHG3uYrID
# iNV1+cy5SNbf8IrlYc8RIhx8TXhvIEEIBaawT6pi21ZtIuqhkpjZOCnty7BS6u2y
# umP9v/0TDqh9DB42ukojaz7JvBAhXqT/VaC6X9hW2PvCFMEjzUeL3Vk5k6VT9487
# U0jVHAZsZtyDEHI1DPhUfPxCCAcGD+S/+CFBdlLZjrT0x8MyREpJE9hIvf9kiaSq
# m3o7wPS+Owtyp5n6lY3nqRCtI9g3UMIxggQNMIIECQIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAgcsETmJzYX7xQABAAACBzANBglghkgB
# ZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCA9IxEge87i6X7Hncx0QigG3OjlVsK525xcLfCBriVCejCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EIC/31NHQds1IZ5sPnv59p+v6BjBDgoDPIwiA
# mn0PHqezMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIHLBE5ic2F+8UAAQAAAgcwIgQgN8JU7q6J935AlUibduNYTl3vobxEAmwqvjHm
# 9Z/OT2swDQYJKoZIhvcNAQELBQAEggIAdSEih76w3tZS6BWwOmj8T3Byy8EtSrTz
# xq1ALYL8Uop/ZJ9ydxzUPu0uxqzvV5MkX880Upkr0qxRDmWLb/EUE+d2JtdcZzUe
# /jrvwNsTx9B9fYP+0L5hRE/IHexnAhdIBg4rhWEOBAuKfuy7hr6MdSfXjQCZ6ebE
# wR59HhXol1DE4/K9YRdTcYQX7BzvQLvuO6dl2QFuQEKD1vfutwVADupSJjQdrZg3
# chKVGvUNLl4QEsLhoB4fZsxh2HUDJ8ymngtvMWrOIKuJKXeXXRwMSDNKRyUG6t0O
# f/CGXMra4LHiOzW68ULU9bWm5/YZbbGWDZIZ7XlYILFFUu1E5qhdPjod+99/uyWy
# 929H9Znc26vYInzxGtjII4WhBGTacq95uLv6PfZ8fMvhFcp7vOi95pKpZe7gFZVy
# +WbKcQrtc0ZdKiBvTuADpSZ/4GHr5E4bhpnhE/BsL3YNJF5a8b20+aG5R5utdmxC
# X/f3qF4IJcRJ+SMzb8n2grs17Cp9PHvuCOraWsPVZoKmC5gk2F51vD68Md3PreIM
# 5/Tas+ep023S+W63lyye7CAY+1HhU1vXnt0kp89iaO95OwnRYfkVc5is6LT+Jtoc
# 0YAawMsswJJQjYmEOSkVHT36hkC4lhhNc0E4IS3T8BuN7xy606ujODIqGCRD20N5
# Rnz2F4tmMPQ=
# SIG # End signature block
