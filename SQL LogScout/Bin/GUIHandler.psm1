
#=======================================Handle the GUI..
[Collections.Generic.List[GenericModel]]$global:list = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_general = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_AlwaysOn = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_core = New-Object Collections.Generic.List[GenericModel]
[Collections.Generic.List[GenericModel]]$global:XeventsList_detailed = New-Object Collections.Generic.List[GenericModel]
[String[]]$global:varXevents = "xevent_AlwaysOn_Data_Movement", "xevent_core", "xevent_detailed" ,"xevent_general"
 class GenericModel
        {
            [String]$Caption
            [String]$Value
            [bool]$State
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
        $Global:NoBasicCheckBox = $Global:Window.FindName("NoBasicCheckBox")
        $Global:overrideExistingCheckBox = $Global:Window.FindName("overrideExistingCheckBox")
        
        $Global:ComboBoxInstanceName = $Global:Window.FindName("ComboBoxInstanceName")
        $Global:ButtonPresentDirectory = $Global:Window.FindName("ButtonPresentDirectory")
        
        $Global:listExtraSkills = $Global:Window.FindName("listExtraSkills")
        $Global:listXevnets = $Global:Window.FindName("listXevnets")
        $Global:list_xevent_detailed = $Global:Window.FindName("list_xevent_detailed")
        $Global:list_xevent_core = $Global:Window.FindName("list_xevent_core")
        $Global:list_xevent_AlwaysOn = $Global:Window.FindName("list_xevent_AlwaysOn")
        $Global:TVI_xevent_general = $Global:Window.FindName("TVI_xevent_general")
        $Global:TVI_xevent_detailed = $Global:Window.FindName("TVI_xevent_detailed")
        $Global:TVI_xevent_core = $Global:Window.FindName("TVI_xevent_core")
        $Global:TVI_xevent_AlwaysOn = $Global:Window.FindName("TVI_xevent_AlwaysOn")
        
        $Global:txtPresentDirectory.Text = $CurrentDirectory 
        #Read current config.
        $Global:XmlDataProviderName.Source = $ConfigPath
        
        #Setting the item source for verious lists.
        $Global:listExtraSkills.ItemsSource = $Global:list      
        $Global:listXevnets.ItemsSource = $Global:XeventsList_general
        $Global:list_xevent_detailed.ItemsSource = $Global:XeventsList_detailed
        $Global:list_xevent_core.ItemsSource = $Global:XeventsList_core
        $Global:list_xevent_AlwaysOn.ItemsSource = $Global:XeventsList_AlwaysOn
        
        RegisterEvents
        Set-PresentDirectory
        
        $Global:Window.Title = $Global:Window.Title + $global:app_version
        $global:gui_Result = $Global:Window.ShowDialog()

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function RegisterEvents()
{
    $Global:ButtonPresentDirectory.Add_Click({ButtonPresentDirectory_EventHandler})
    $Global:okButton.Add_Click({$Global:Window.DialogResult = $true})
    $Global:WPRCheckBox.Add_Click({DisableAll $Global:WPRCheckBox.IsChecked})
    $Global:Window.Add_Loaded({Window_Loaded_EventHandler})  
    $Global:DetailedPerfCheckBox.Add_Click({DetailedPerfCheckBox_Click_EventHandler $Global:DetailedPerfCheckBox.IsChecked})
    $Global:generalPerfCheckBox.Add_Click({generalPerfCheckBox_Click_EventHandler $Global:generalPerfCheckBox.IsChecked})
    $Global:LightPerfCheckBox.Add_Click({LightPerfCheckBox_Click_EventHandler $Global:LightPerfCheckBox.IsChecked})
    $Global:alwaysOnPerfCheckBox.Add_Click({alwaysOnPerfCheckBox_Click_EventHandler $Global:alwaysOnPerfCheckBox.IsChecked})
}

function ButtonPresentDirectory_EventHandler()
{
    $objForm = New-Object System.Windows.Forms.FolderBrowserDialog
                $Show = $objForm.ShowDialog()
                if ($Show -eq "OK") {
                    $Global:txtPresentDirectory.Text = $objForm.SelectedPath;
                }
}

function Window_Loaded_EventHandler()
{
    Foreach ($Instance in Get-NetNameMatchingInstance) { $ComboBoxInstanceName.Items.Add($Instance) }           
                BuildPermonModel
                BuildXEventsModel
                BuildXEventsModel_core
                BuildXEventsModel_detailed
                BuildXEventsModel_AlwaysOn
}

function DetailedPerfCheckBox_Click_EventHandler([bool] $state)
{
    #$Global:basicPerfCheckBox.IsChecked = $false
    #$Global:basicPerfCheckBox.IsEnabled = !$state
    
    $Global:generalPerfCheckBox.IsChecked = $false
    $Global:LightPerfCheckBox.IsChecked = $false
    
    $Global:generalPerfCheckBox.IsEnabled = !$state
    $Global:LightPerfCheckBox.IsEnabled = !$state

    $Global:TVI_xevent_general.IsEnabled = !$state
}

function LightPerfCheckBox_Click_EventHandler([bool] $state)
{
    $Global:TVI_xevent_general.IsEnabled = !$state
     $Global:TVI_xevent_detailed.IsEnabled = !$state
     $Global:TVI_xevent_core.IsEnabled = !$state
}

function generalPerfCheckBox_Click_EventHandler([bool] $state)
{
    $Global:LightPerfCheckBox.IsChecked = $false
    $Global:LightPerfCheckBox.IsEnabled = !$state
    $Global:TVI_xevent_detailed.IsEnabled = !$state
    
}

function alwaysOnPerfCheckBox_Click_EventHandler([bool] $state)
{
   $Global:TVI_xevent_AlwaysOn.IsEnabled = $state  
}

function Set-Mode() {

    try {
        if ($global:gInteractivePrompts -eq "Quiet") { $global:gui_mode = $false; return }
        Write-LogDebug "inside" $MyInvocation.MyCommand
       
        $userlogfolder = Read-Host "Would you like to use GUI mode ?> (Y/N)" -CustomLogMessage "Prompt CustomDir Console Input:"
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
            $PerfmonModelobj.State = $true
            $Global:list.Add($PerfmonModelobj)
        }
    }
    catch {
        HandleCatchBlock -function_name
        exit
    }

}

function DisableAll([bool] $state)
{
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
    
    
}
function GenerateXeventFileFromGUI {
    Write-LogDebug "inside" $MyInvocation.MyCommand  
    try {
        CreateFile $Global:XeventsList_general "xevent_general.sql"
        CreateFile $Global:XeventsList_core 'xevent_core.sql'
        CreateFile $Global:XeventsList_detailed 'xevent_detailed.sql'
        CreateFile $Global:XeventsList_AlwaysOn 'xevent_AlwaysOn_Data_Movement.sql'
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
    }
    
}

function CreateFile($myList, [string]$fileName)
{
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
function BuildXEventsModel() {
    try {
        Write-LogDebug "inside" $MyInvocation.MyCommand  
        Write-LogDebug "BuildXEventsModel...."
        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel
        foreach ($element in Get-Content .\xevent_general.sql) {
            if ($element -eq "GO") { 
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
        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel
        foreach ($element in Get-Content .\xevent_core.sql) {
            if ($element -eq "GO") { 
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
    try {
        Write-LogDebug "inside" $MyInvocation.MyCommand  
        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel
        foreach ($element in Get-Content .\xevent_detailed.sql) {
            if ($element -eq "GO") { 
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
    try {
        Write-LogDebug "inside" $MyInvocation.MyCommand  
        $xevent_string = New-Object -TypeName System.Text.StringBuilder
        $GenericModelobj = New-Object GenericModel
        foreach ($element in Get-Content .\xevent_AlwaysOn_Data_Movement.sql) {
            if ($element -eq "GO") { 
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
                #ADD EVENT sqlserver.
                #if ($element.contains("AlwaysOn_Data_Movement")) {
                if ($element.contains("ADD EVENT sqlserver.")) {

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
# SIG # Begin signature block
# MIInpwYJKoZIhvcNAQcCoIInmDCCJ5QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBn8xv4aoQExFKj
# VqSrHUbvmTm2Etk9euFSv96HgKmO5aCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
# 3pbexW7MAAAAAAJTMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMzAwWhcNMjIwOTAxMTgzMzAwWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDLhxHwq3OhH+4J+SX4qS/VQG8HybccH7tnG+BUqrXubfGuDFYPZ29uCuHfQlO1
# lygLgMpJ4Geh6/6poQ5VkDKfVssn6aA1PCzIh8iOPMQ9Mju3sLF9Sn+Pzuaie4BN
# rp0MuZLDEXgVYx2WNjmzqcxC7dY9SC3znOh5qUy2vnmWygC7b9kj0d3JrGtjc5q5
# 0WfV3WLXAQHkeRROsJFBZfXFGoSvRljFFUAjU/zdhP92P+1JiRRRikVy/sqIhMDY
# +7tVdzlE2fwnKOv9LShgKeyEevgMl0B1Fq7E2YeBZKF6KlhmYi9CE1350cnTUoU4
# YpQSnZo0YAnaenREDLfFGKTdAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUlZpLWIccXoxessA/DRbe26glhEMw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzQ2NzU5ODAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AKVY+yKcJVVxf9W2vNkL5ufjOpqcvVOOOdVyjy1dmsO4O8khWhqrecdVZp09adOZ
# 8kcMtQ0U+oKx484Jg11cc4Ck0FyOBnp+YIFbOxYCqzaqMcaRAgy48n1tbz/EFYiF
# zJmMiGnlgWFCStONPvQOBD2y/Ej3qBRnGy9EZS1EDlRN/8l5Rs3HX2lZhd9WuukR
# bUk83U99TPJyo12cU0Mb3n1HJv/JZpwSyqb3O0o4HExVJSkwN1m42fSVIVtXVVSa
# YZiVpv32GoD/dyAS/gyplfR6FI3RnCOomzlycSqoz0zBCPFiCMhVhQ6qn+J0GhgR
# BJvGKizw+5lTfnBFoqKZJDROz+uGDl9tw6JvnVqAZKGrWv/CsYaegaPePFrAVSxA
# yUwOFTkAqtNC8uAee+rv2V5xLw8FfpKJ5yKiMKnCKrIaFQDr5AZ7f2ejGGDf+8Tz
# OiK1AgBvOW3iTEEa/at8Z4+s1CmnEAkAi0cLjB72CJedU1LAswdOCWM2MDIZVo9j
# 0T74OkJLTjPd3WNEyw0rBXTyhlbYQsYt7ElT2l2TTlF5EmpVixGtj4ChNjWoKr9y
# TAqtadd2Ym5FNB792GzwNwa631BPCgBJmcRpFKXt0VEQq7UXVNYBiBRd+x4yvjqq
# 5aF7XC5nXCgjbCk7IXwmOphNuNDNiRq83Ejjnc7mxrJGMIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGXgwghl0AgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEICBH
# kaXgXLgxjhn3ZHFii1F0lsYACcwIngnSVY6ZTQmJMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQCMEvHa0U9pQ+hEEMKO2yrB23ejK1tZJ3lM
# +IK8Moe0YhAh6PzklPPEWmqQV1JgzsZQbBqzRUv48yJ5Rgf5eTaZFCmkqj42OcvY
# MGapQVF23gHNfJd5P3Mk8lYCbINViOD/n3YnPEg54m8loEfMt1F7CJoAqHz1Tt/x
# cfTM4iUPuVd6nZT+FrCNQxRePnY8lnv4DziqR0SHLxLSEkaRhqsgl2F3amOit89r
# Eb77yd3916Bg23DFPBz6PFFC5ZBYhOu9L3nY55tufNxujYsr4zT2EPrz1bwblN0u
# HUz1GvjZII77UcKF+8l+9V6YiBOXqGx2SR7ufSk2kmsFr5wCVmWMoYIXADCCFvwG
# CisGAQQBgjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIGkE27L6oeleEttA7xd0evOgU249mBE8
# ws1auwcbzihdAgZiFl7b9McYEzIwMjIwMzAxMTI1MDA3LjU5M1owBIACAfSggdCk
# gc0wgcoxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNV
# BAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOkU1QTYtRTI3Qy01OTJFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloIIRVzCCBwwwggT0oAMCAQICEzMAAAGVt/wN1uM3MSUA
# AQAAAZUwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwHhcNMjExMjAyMTkwNTEyWhcNMjMwMjI4MTkwNTEyWjCByjELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RTVBNi1F
# MjdDLTU5MkUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Uw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCfbUEMZ7ZLOz9aoRCeJL4h
# hT9Q8JZB2xaVlMNCt3bwhcTI5GLPrt2e93DAsmlqOzw1cFiPPg6S5sLCXz7LbbUQ
# pLha8S4v2qccMtTokEaDQS+QJErnAsl6VSmRvAy0nlj+C/PaZuLb3OzY0ARw7UeC
# ZLpyWPPH+k5MdYj6NUDTNoXqbzQHCuPs+fgIoro5y3DHoO077g6Ir2THIx1yfVFE
# t5zDcFPOYMg4yBi4A6Xc3hm9tZ6w849nBvVKwm5YALfH3y/f3n4LnN61b1wzAx3Z
# CZjf13UKbpE7p6DYJrHRB/+pwFjG99TwHH6uXzDeZT6/r6qH7AABwn8fpYc1Tmle
# FY8YRuVzzjp9VkPHV8VzvzLL7QK2kteeXLL/Y4lvjL6hzyOmE+1LVD3lEbYho1zC
# t+F7bU+FpjyBfTC4i/wHsptb218YlbkQt1i1B6llmJwVFwCLX7gxQ48QIGUacMy8
# kp1+zczY+SxlpaEgNmQkfc1raPh9y5sMa6X48+x0K7B8OqDoXcTiECIjJetxwtuB
# lQseJ05HRfisfgFm09kG7vdHEo3NbUuMMBFikc4boN9Ufm0iUhq/JtqV0Kwrv9Cv
# 3ayDgdNwEWiL2a65InEWSpRTYfsCQ03eqEh5A3rwV/KfUFcit+DrP+9VcDpjWRsC
# okZv4tgn5qAXNMtHa8NiqQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFKuX02ICFFdX
# grcCBmDJfH5v/KkXMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8G
# A1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBs
# BggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# DQYJKoZIhvcNAQELBQADggIBAOCzNt4fJ+jOvQuq0Itn37IZrYNBGswAi+IAFM3Y
# GK/wGQlEncgjmNBuac95W2fAL6xtFVfMfkeqSLMLqoidVsU9Bm4DEBjaWNOT9uX/
# tcYiJSfFQM0rDbrl8V4nM88RZF56G/qJW9g5dIqOSoimzKUt/Q7WH6VByW0sar5w
# GvgovK3qFadwKShzRYcEqTkHH2zip5e73jezPHx2+taYqJG5xJzdDErZ1nMixRja
# Hs3KpcsmZYuxsIRfBYOJvAFGymTGRv5PuwsNps9Ech1Aasq84H/Y/8xN3GQj4P3M
# iDn8izUBDCuXIfHYk39bqnaAmFbUiCby+WWpuzdk4oDKz/sWwrnsoQ72uEGVEN7+
# kyw9+HSo5i8l8Zg1Ymj9tUgDpVUGjAduoLyHQ7XqknKmS9kJSBKk4okEDg0Id6Le
# KLQwH1e4aVeTyUYwcBX3wg7pLJQWvR7na2SGrtl/23YGQTudmWOryhx9lnU7KBGV
# /aNvz0tTpcsucsK+cZFKDEkWB/oUFVrtyun6ND5pYZNj0CgRup5grVACq/Agb+EO
# GLCD+zEtGNop4tfKvsYb64257NJ9XrMHgpCib76WT34RPmCBByxLUkHxHq5zCyYN
# u0IFXAt1AVicw14M+czLYIVM7NOyVpFdcB1B9MiJik7peSii0XTRdl5/V/KscTaC
# BFz3MIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0B
# AQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAG
# A1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAw
# HhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOTh
# pkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xP
# x2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ
# 3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOt
# gFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYt
# cI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXA
# hjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0S
# idb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSC
# D/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEB
# c8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh
# 8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8Fdsa
# N8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkr
# BgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q
# /y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBR
# BgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAP
# BgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjE
# MFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEF
# BQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEB
# CwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnX
# wnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOw
# Bb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jf
# ZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ
# 5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+
# ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgs
# sU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6
# OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p
# /cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6
# TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784
# cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3
# AgEBMIH4oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYD
# VQQLEx1UaGFsZXMgVFNTIEVTTjpFNUE2LUUyN0MtNTkyRTElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA0Y+CyLez
# GgVHWFNmKI1LuE/hY6uggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQUFAAIFAOXIHXkwIhgPMjAyMjAzMDExMjIwMDlaGA8y
# MDIyMDMwMjEyMjAwOVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5cgdeQIBADAK
# AgEAAgIOBgIB/zAHAgEAAgIRrDAKAgUA5clu+QIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBBQUAA4GBAKN1YaQOMdsFywu98vao4DYcpvQj72H7FHSt2IU0JR9ULtWLnUo5
# wh1s0SBXOXA249ayHTi81Bk2j0Sr3Xz7JLJOEZs/+0HOt7GP34DIVmErFyVG9Vf/
# Cwa8FXJXk3iU/u3JXFyUr3UaRhW7s4+ACSz2L8p5sz8+SKDnRnvoKVmkMYIEDTCC
# BAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGVt/wN
# 1uM3MSUAAQAAAZUwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsq
# hkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg6wd2nFKdNNGjsUfcK4Huoe+NklLP
# 0fx5RVdDfvoQllwwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBc5kvhjZAL
# e2mhIz/Qd7keVOmA/cC1dzKZT4ybLEkCxzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAABlbf8DdbjNzElAAEAAAGVMCIEIEoh/phCqCUc
# IPPiyGWCEdRvsvakFpcxPBkeGlu/JAB3MA0GCSqGSIb3DQEBCwUABIICAAouKqQF
# mX4bp00ia0t3Z8TggXv4n7RdGH8BDQmXydLVKGVPpmxvCWllzAZ0wIpU4KbWcy08
# bfMKdjqI958vJOVzakvnCxWOVzvvwrzZpGQZ4XuAWfA0LRZFHOp5q/2KdhcyZLgh
# hWANSQREiw6lZQgnYt1rvcTCsZU2JxRcAfUFfUKu+DGVj9cp8Hwd0RIdoKpa6B94
# FfO+z+EmC389kLJsCaciPAHtZrikJLkqqxpy3dlMPfywQzGEzo562UQa7LlTwUn8
# y+UwJbvC7h5mcHz2tGcx3BGFKfpPVcMM4ORLwwadlhfIPHc7pfuvKs+BS2drWEMs
# +S3grQt5AxYLH5vJvVVOKOrM4/0HG5uwQy2sQJtJZJjaktJ4XJ2jsqmOskhHQcap
# CiyVsbEXUnGgdu7dcOWiNm7sH7QHoMYIuWjXiVkPg3I3lsMy8HfxA2CVLgTuRnDq
# bUW+YAZ644D2qD19fuI7VtSSLuwAZPjHRiJTyGl5FcDaTfRVo7rz4V8haO6u3LOH
# IImIsNpm2EZlZzfDTyivp830167aZoCQ+XG142nVCIJTwPNB8Kg24koqRQhetxn7
# APIaY+itdQh8k9+au+pUgI5eweJFISJStHiVLIGpWr2DKfejvQtXMv9RmjdIfTNQ
# yNDW/ehWNOk1VOy4HY4E0gBfW4inXpwBlD2z
# SIG # End signature block
