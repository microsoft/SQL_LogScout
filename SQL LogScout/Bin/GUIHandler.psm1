
#=======================================Handle the GUI..
[Collections.Generic.List[GenericModel]]$global:list = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_general = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_AlwaysOn = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_core = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_detailed = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_servicebroker_dbmail = New-Object Collections.Generic.List[GenericModel]
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
        
        $Global:listExtraSkills = $Global:Window.FindName("listExtraSkills")
        $Global:listXevnets = $Global:Window.FindName("listXevnets")
        $Global:list_xevent_detailed = $Global:Window.FindName("list_xevent_detailed")
        $Global:list_xevent_core = $Global:Window.FindName("list_xevent_core")
        $Global:list_xevent_AlwaysOn = $Global:Window.FindName("list_xevent_AlwaysOn")
        $Global:list_xevent_servicebroker_dbmail = $Global:Window.FindName("list_xevent_servicebroker_dbmail")

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
        $Global:listExtraSkills.ItemsSource = $Global:list      
        $Global:listXevnets.ItemsSource = $Global:XeventsList_general
        $Global:list_xevent_detailed.ItemsSource = $Global:XeventsList_detailed
        $Global:list_xevent_core.ItemsSource = $Global:XeventsList_core
        $Global:list_xevent_AlwaysOn.ItemsSource = $Global:XeventsList_AlwaysOn
        $Global:list_xevent_servicebroker_dbmail.ItemsSource = $Global:XeventsList_servicebroker_dbmail
        
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
    $Global:okButton.Add_Click({ $Global:Window.DialogResult = $true })
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
        $Global:listExtraSkills.IsEnabled = $true
        foreach ($item in $Global:list) {
            $item.State = $true
        }
        $Global:listExtraSkills.ItemsSource = $null
        $Global:listExtraSkills.ItemsSource = $Global:list
    }
    else {
        $Global:listExtraSkills.IsEnabled = $false

        foreach ($item in $Global:list) {
            $item.State = $false
        }
        $Global:listExtraSkills.ItemsSource = $null
        $Global:listExtraSkills.ItemsSource = $Global:list
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
            $Global:list.Add($PerfmonModelobj)
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
