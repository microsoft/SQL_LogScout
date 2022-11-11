
#=======================================Start of \OUTPUT and \Internal directories and files Section
function InitCriticalDirectories()
{
    try 
    {
        # This will set presentaion mode either GUI or console.
         if ($PSVersionTable.PSVersion.Major -gt 4) {
            Set-Mode
        }
        else{
            $PSVersion =$PSVersionTable.PSVersion.Major
            Write-LogWarning "Only script mode is supported on PS Version: $PSVersion"
        }
        if ($global:gui_mode) 
        {
            InitializeGUIComponent  
            if($global:gui_Result -eq $false)
            {
                exit
            }
        }
        else
        {
            #initialize this directories
            Set-PresentDirectory 
              
        }  
        Set-OutputPath
        Set-InternalPath
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  -exit_logscout $true  
    }

}


function Set-PresentDirectory()
{
	Write-LogDebug "inside" $MyInvocation.MyCommand

    try 
    {
        $global:present_directory = Convert-Path -Path "."
        Write-LogInformation "The Present folder for this collection is" $global:present_directory     
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem        
    }
    
}

function Set-OutputPath()
{

    try
    {
        Write-LogDebug "inside" $MyInvocation.MyCommand
        
        #default final directory to present directory (.)
        [string] $final_directory  = $global:present_directory

        # if "UsePresentDir" is passed as a param value, then create where SQL LogScout runs
        if ($global:custom_user_directory -eq "UsePresentDir")
        {
            $final_directory  = $global:present_directory
        }
        #if a custom directory is passed as a parameter to the script. Parameter validation also runs Test-Path on $CustomOutputPath
        elseif (Test-Path -Path $global:custom_user_directory)
        {
            $final_directory = $global:custom_user_directory

        }
        elseif ($global:custom_user_directory -eq "PromptForCustomDir" -And !$global:gui_mode)    
        {
            $userlogfolder = Read-Host "Would your like the logs to be collected on a non-default drive and directory?" -CustomLogMessage "Prompt CustomDir Console Input:"
            $HelpMessage = "Please enter a valid input (Y or N)"

            $ValidInput = "Y","N"
            $AllInput = @()
            $AllInput += , $ValidInput
            $AllInput += , $userlogfolder
            $AllInput += , $HelpMessage

            $YNselected = validateUserInput($AllInput)
            

            if ($YNselected -eq "Y")
            {
                [string] $customOutDir = [string]::Empty

                while([string]::IsNullOrWhiteSpace($customOutDir) -or !(Test-Path -Path $customOutDir))
                {

                    $customOutDir = Read-Host "Enter an output folder with no quotes (e.g. C:\MyTempFolder or C:\My Folder)" -CustomLogMessage "Get Custom Output Folder Console Input:"
                    if ($customOutDir -eq "" -or !(Test-Path -Path $customOutDir))
                    {
                        Write-Host "'" $customOutDir "' is not a valid path. Please, enter a valid drive and folder location" -ForegroundColor Yellow
                    }
                }

                $final_directory =  $customOutDir
            }


        }

        if ($global:gui_mode)
        {
            # Seting final diretory from GUI.
            $final_directory = $Global:txtPresentDirectory.Text
        }

        #the output folder is subfolder of current folder where the tool is running
        $global:output_folder =  ($final_directory + "\output\")
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        exit
    }

}

function Set-NewOutputPath 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try 
    {
        [string] $new_output_folder_name = "_" + @(Get-Date -Format ddMMyyhhmmss) + "\"
        $global:output_folder = $global:output_folder.Substring(0, ($global:output_folder.Length-1)) + $new_output_folder_name        
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
    }
    
}



function Set-InternalPath()
{
	Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try 
    {
        #the \internal folder is subfolder of \output
        $global:internal_output_folder =  ($global:output_folder  + "internal\")    
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem    
    }
}

function CreatePartialOutputFilename ([string]$server)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try 
    {
        if ($global:output_folder -ne "")
        {
            $server_based_file_name = $server -replace "\\", "_"
            $output_file_name = $global:output_folder + $server_based_file_name + "_" + @(Get-Date -Format FileDateTime)
        }
        Write-LogDebug "The server_based_file_name: " $server_based_file_name -DebugLogLevel 3
        Write-LogDebug "The output_path_filename is: " $output_file_name -DebugLogLevel 2
        
        return $output_file_name
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem    
    }
    
}

function CreatePartialErrorOutputFilename ([string]$server)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

	try 
    {
        if (($server -eq "") -or ($null -eq $server)) 
        {
            $server = $global:host_name 
        }
        
        $error_folder = $global:internal_output_folder 
        
        $server_based_file_name = $server -replace "\\", "_"
        $error_output_file_name = $error_folder + $server_based_file_name + "_" + @(Get-Date -Format FileDateTime)
        
        Write-LogDebug "The error_output_path_filename is: " $error_output_file_name -DebugLogLevel 2
        
        return $error_output_file_name
        
    }

    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem 
    }
}

function ReuseOrRecreateOutputFolder() 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    Write-LogDebug "Output folder is: $global:output_folder" -DebugLogLevel 3
    Write-LogDebug "Error folder is: $global:internal_output_folder" -DebugLogLevel 3
    
    try {
    
        #delete entire \output folder and files/subfolders before you create a new one, if user chooses that
        if ($global:gui_mode) 
        {
            if($Global:overrideExistingCheckBox.IsChecked) {$DeleteOrNew = "D"}
            else{$DeleteOrNew = "N"}
        }
        elseif (Test-Path -Path $global:output_folder)  
        {
            if ([string]::IsNullOrWhiteSpace($global:gDeleteExistingOrCreateNew) )
            {
                Write-LogInformation ""
        
                [string]$DeleteOrNew = ""
                Write-LogWarning "It appears that output folder '$global:output_folder' has been used before."
                Write-LogWarning "You can choose to:"
                Write-LogWarning " - Delete (d) the \output folder contents and recreate it"
                Write-LogWarning " - Create a new (n) folder using '\Output_ddMMyyhhmmss' format. You can manually delete this folder in the future" 
    
                while (-not(($DeleteOrNew -eq "D") -or ($DeleteOrNew -eq "N"))) 
                {
                    $DeleteOrNew = Read-Host "Delete ('d') or create new ('n') >" -CustomLogMessage "Output folder Console input:"
                    
                    $DeleteOrNew = $DeleteOrNew.ToString().ToUpper()
                    if (-not(($DeleteOrNew -eq "D") -or ($DeleteOrNew -eq "N"))) {
                        Write-LogError ""
                        Write-LogError "Please chose [d] to delete the output folder $global:output_folder and all files inside of the folder."
                        Write-LogError "Please chose [n] to create a new folder"
                        Write-LogError ""
                    }
                }

            }

            elseif ($global:gDeleteExistingOrCreateNew -in "DeleteDefaultFolder","NewCustomFolder") 
            {
                Write-LogDebug "The DeleteExistingOrCreateNew parameter is $($global:gDeleteExistingOrCreateNew)" -DebugLogLevel 2

                switch ($global:gDeleteExistingOrCreateNew) 
                {
                    "DeleteDefaultFolder"   {$DeleteOrNew = "D"}
                    "NewCustomFolder"       {$DeleteOrNew = "N"}
                }
                
            }

        }#end of IF

        
        #Get-Childitem -Path $output_folder -Recurse | Remove-Item -Confirm -Force -Recurse  | Out-Null
        if ($DeleteOrNew -eq "D") 
        {
            #delete the existing \output folder
            if (Test-Path -Path $global:output_folder)
            {
                Remove-Item -Path $global:output_folder -Force -Recurse  | Out-Null
                Write-LogWarning "Deleted $global:output_folder and its contents"
            }
        }
        elseif ($DeleteOrNew -eq "N") 
        {

            #these two calls updates the two globals for the new output and internal folders using the \Output_ddMMyyhhmmss format.
            
            # [string] $new_output_folder_name = "_" + @(Get-Date -Format ddMMyyhhmmss) + "\"
            # $global:output_folder = $global:output_folder.Substring(0, ($global:output_folder.Length-1)) + $new_output_folder_name

            Set-NewOutputPath
            Write-LogDebug "The new output path is: $global:output_folder" -DebugLogLevel 3
        
            #call Set-InternalPath to reset the \Internal folder
            Set-InternalPath
            Write-LogDebug "The new error path is: $global:internal_output_folder" -DebugLogLevel 3
        }

        

	
        #create an output folder AND error directory in one shot (creating the child folder \internal will create the parent \output also). -Force will not overwrite it, it will reuse the folder
        New-Item -Path $global:internal_output_folder -ItemType Directory -Force | out-null 
        
        Write-LogInformation "Output path: $global:output_folder"  #DO NOT CHANGE - Message is backward compatible
        Write-LogInformation "Error  path is" $global:internal_output_folder 
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit_logscout $true
        return $false
    }
}

function BuildFinalOutputFile([string]$output_file_name, [string]$collector_name, [bool]$needExtraQuotes, [string]$fileExt = ".out")
{
	Write-LogDebug "inside" $MyInvocation.MyCommand
	
    try 
    {
        $final_output_file = $output_file_name + "_" + $collector_name + $fileExt
	
        if ($needExtraQuotes)
        {
            $final_output_file = "`"" + $final_output_file + "`""
        }

        return $final_output_file
    }

    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
	
}

function BuildInputScript([string]$present_directory, [string]$script_name)
{
	Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try 
    {
        if($global:gui_Result -eq $true -And $global:varXevents.contains($script_name) -eq $True)
        {
            
            $input_script = "`"" + $global:internal_output_folder + $script_name +".sql" + "`""
            return $input_script
        }
        else
        {
            $input_script = "`"" + $present_directory+"\"+$script_name +".sql" + "`""
            return $input_script
        }
        
    }
    
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem    
    }
	
}

function BuildFinalErrorFile([string]$partial_error_output_file_name, [string]$collector_name, [bool]$needExtraQuotes)
{
	Write-LogDebug "inside" $MyInvocation.MyCommand
	
    try 
    {
        $error_file = $partial_error_output_file_name + "_"+ $collector_name + "_errors.out"
	
        if ($needExtraQuotes)
        {
            $error_file = "`"" + $error_file + "`""
        }
		
	    return $error_file
    }
    catch 
    {

        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
	
}


#=======================================End of \OUTPUT and \Internal directories and files Section


#======================================== START of Process management section

function StartNewProcess()
{
    param
    (
        [Parameter(Mandatory=$true, Position=0)]
        [String] $FilePath,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $ArgumentList = [String]::Empty,

        [Parameter(Mandatory=$false, Position=2)]
        [System.Diagnostics.ProcessWindowStyle] $WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized,
    
        [Parameter(Mandatory=$false, Position=3)]
        [String] $RedirectStandardError = [String]::Empty,    
    
        [Parameter(Mandatory=$false, Position=4)]
        [String] $RedirectStandardOutput = [String]::Empty,

        [Parameter(Mandatory=$false, Position=5)]
        [bool] $Wait = $false
    )

    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {
        #build a hash table of parameters
            
        $StartProcessParams = @{            
            FilePath= $FilePath
        }    

        if ($ArgumentList -ne [String]::Empty)
        {
            [void]$StartProcessParams.Add("ArgumentList", $ArgumentList)     
        }

        if ($null -ne $WindowStyle)
        {
            [void]$StartProcessParams.Add("WindowStyle", $WindowStyle)     
        }

        if ($RedirectStandardOutput -ne [String]::Empty)
        {
            [void]$StartProcessParams.Add("RedirectStandardOutput", $RedirectStandardOutput)     
        }

        if ($RedirectStandardError -ne [String]::Empty)
        {
            [void]$StartProcessParams.Add("RedirectStandardError", $RedirectStandardError)     
        }

        # we will always use -PassThru because we want to keep track of processes launched
        [void]$StartProcessParams.Add("PassThru", $null)     

        if ($true -eq $Wait)
        {
            [void]$StartProcessParams.Add("Wait", $null)
        }
        #print the command executed
        Write-LogDebug $FilePath $ArgumentList

        Write-LogDebug ("StartNewProcess parameters: " + $StartProcessParams.Keys) -DebugLogLevel 5
        Write-LogDebug ("StartNewProcess parameter values: " + $StartProcessParams.Values) -DebugLogLevel 5

        # start the process
        #equivalent to $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WindowStyle $WindowStyle -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError -PassThru -Wait
        $p = Start-Process @StartProcessParams

        #touch a few properties to make sure the process object is populated with them - specifically name and start time
        $pn = $p.ProcessName
        $sh = $p.SafeHandle
        $st = $p.StartTime

        # add the process object to the array of started processes (if it has not exited already)
        if($false -eq $p.HasExited)   
        {
            [void]$global:processes.Add($p)
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    

}

function Start-SQLCmdProcess([string]$collector_name, [string]$input_script_name, [bool]$is_query=$false, [string]$query_text, [bool]$has_output_results=$true, [bool]$wait_sync=$false, [string]$server = $global:sql_instance_conn_str, [string]$setsqlcmddisplaywidth)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand


    [console]::TreatControlCAsInput = $true


    # if query is empty and script should be populated
    # if query is populated script should be ::Empty


    try 
    {
        
        #in case CTRL+C is pressed
        HandleCtrlC

        if ($true -eq [string]::IsNullOrWhiteSpace($collector_name))
        {
            $collector_name = "blank_collector_name"
        }

        $input_script = BuildInputScript $global:present_directory $input_script_name 
        
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w8000"

        #if secondary replica has read-intent, we add -KReadOnly to avoid failures on those secondaries
        if ($global:is_secondary_read_intent_only -eq $true)
        {
            $argument_list += " -KReadOnly"
        }

        if (($is_query -eq $true) -and ([string]::IsNullOrWhiteSpace($query_text) -ne $true) )
        {
            $argument_list += " -Q`"" + $query_text + "`""
        }
        else #otherwise use an input script
        {
            $argument_list += " -i" + $input_script 
        }

        #most executions produce output - so we should include an -o parameter for SQLCMD
        if ($has_output_results -eq $true)
        {
            $partial_output_file_name = CreatePartialOutputFilename ($server)
            
            
            $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true

            $argument_list += " -o" + $output_file
        }

        #Depending on the script executed, we may need to increase the result length. Logically we should only care about this parameter if we are writing an output file. Originally implemented for replication collector.
        if (([string]::IsNullOrEmpty($setsqlcmddisplaywidth) -eq $false) -And ($has_output_results -eq $true))
        {
            $argument_list += " -y" + $setsqlcmddisplaywidth
        }


        
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stderr") -needExtraQuotes $false 
        $stdoutput_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stdout") -needExtraQuotes $false 

        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -RedirectStandardOutput $stdoutput_file -Wait $wait_sync
        
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

#======================================== END of Process management section


#check if cluster - based on cluster service status and cluster registry key
function IsClustered()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $ret = $false
    $error_msg = ""
        
    $clusServiceisRunning = $false
    $clusRegKeyExists = $false
    $ClusterServiceKey="HKLM:\Cluster"

    # Check if cluster service is running
    try 
    { 
        if ((Get-Service |  Where-Object  {$_.Displayname -match "Cluster Service"}).Status -eq "Running") 
        {
            $clusServiceisRunning =  $true
            Write-LogDebug "Cluster services status is running: $clusServiceisRunning  " -DebugLogLevel 2   
        }
        
        if (Test-Path $ClusterServiceKey) 
        { 
            $clusRegKeyExists  = $true
            Write-LogDebug "Cluster key $ClusterServiceKey Exists: $clusRegKeyExists  " -DebugLogLevel 2
        }

        if (($clusRegKeyExists -eq $true) -and ($clusServiceisRunning -eq $true ))
        {
            Write-LogDebug 'This is a Windows Cluster for sure!' -DebugLogLevel 2
            Write-LogInformation 'This is a Windows Cluster'
            return $true
        }
        else 
        {
            Write-LogDebug 'This is Not a Windows Cluster!' -DebugLogLevel 2
            return $false
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

    return $ret
}

function Get-InstanceNameOnly([string]$NetnamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try 
    {
        $selectedSqlInstance  = $NetnamePlusInstance.Substring($NetnamePlusInstance.IndexOf("\") + 1)
        return $selectedSqlInstance         
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}


#used in Catch blocks throughout
function HandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Write-LogError "Function '$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    

    if ($exit_logscout)
    {
        Write-LogWarning "Exiting SQL LogScout..."
        exit
    }
}


