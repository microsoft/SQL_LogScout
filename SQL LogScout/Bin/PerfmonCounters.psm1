
#======================================== START OF PERFMON COUNTER FILES SECTION




function Get-PerfmonString ([string]$NetNamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try 
    {

        #if default instance, this function will return the hostname
        $host_name = $global:host_name

        $instance_name = Get-InstanceNameOnly($NetNamePlusInstance)

        #if default instance use "SQLServer", else "MSSQL$InstanceName
        # on a cluster $NetNamePlusInstance would contain the VNN when a default instance 
        if (($instance_name -eq $host_name) -or ($instance_name -eq $NetNamePlusInstance))
        {
            $perfmon_str = "SQLServer"
        }
        else
        {
            $perfmon_str = "MSSQL$"+$instance_name

        }

        Write-LogDebug "Perfmon string is: $perfmon_str" -DebugLogLevel 2

        return $perfmon_str

    }
    catch 
    {
        
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}


function Update-PerfmonConfigFile([string]$NetNamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try
    {
        #fetch the location of the copied counter file in the \internal folder. Could write a function in the future if done more than once
        $internal_directory = $global:internal_output_folder
        $perfmonCounterFile = $internal_directory+$global:perfmon_active_counter_file

        Write-LogDebug "New Perfmon counter file location is: " $perfmonCounterFile

        $original_string = 'MSSQL$*:'
        $new_string = Get-PerfmonString ($NetNamePlusInstance) 
        $new_string += ":"
        
        Write-LogDebug "Replacement string is: " $new_string -DebugLogLevel 2

        if (Test-Path -Path $perfmonCounterFile)
        {
            #This does the magic. Loads the file in memory, and replaces the original string with the new built string
            ((Get-Content -path $perfmonCounterFile -Raw ) -replace  [regex]::Escape($original_string), $new_string) | Set-Content -Path $perfmonCounterFile 
        }
        else 
        {
            Write-LogError "The file $perfmonCounterFile does not exist."
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function Copy-OriginalLogmanConfig()
{
    #this function makes a copy of the original Perfmon counters LogmanConfig.txt file in the \output\internal directory
    #the file will be used from there
    

    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    $internal_path = $global:internal_output_folder
    $present_directory = $global:present_directory
    $perfmon_file = $global:perfmon_active_counter_file

    $perfmonCounterFile = $present_directory+"\"+$perfmon_file     #"LogmanConfig.txt"
    $destinationPerfmonCounterFile = $internal_path + $perfmon_file   #\output\internal\LogmanConfig.txt
    

    try
    {
        if(Test-Path -Path $internal_path)
        {
            #copy the file to internal path so it can be used from there
            if ($global:gui_mode) 
            {
                [System.Text.StringBuilder]$SB_PerfmonCounter = New-Object -TypeName System.Text.StringBuilder
                foreach($item in $Global:list)
                {
                    if ($item.State -eq $true)
                    { 
                        [void]$SB_PerfmonCounter.Append($item.Value + "`r`n")
                    }
                }
                Add-Content $destinationPerfmonCounterFile $SB_PerfmonCounter
            }
            else
            {
                Copy-Item -Path $perfmonCounterFile -Destination $destinationPerfmonCounterFile -ErrorAction Stop
            }
            Write-LogInformation "$perfmon_file copied to " $destinationPerfmonCounterFile
           
            #file has been copied
            return $true
        }
        else 
        {
            $mycommand = $MyInvocation.MyCommand
            $error_msg = $PSItem.Exception.Message 
            
            $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
            $error_offset = $PSItem.InvocationInfo.OffsetInLine
            Write-LogError "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"

            #Write-LogError "The file $perfmonCounterFile is not present."
            return $false
        }
        
        
    }

    catch
    {
        $error_msg = $PSItem.Exception.Message 

        if ($error_msg -Match "because it does not exist")
        {
            Write-LogError "The $perfmon_file file does not exist."
        }
        else
        {
            Write-LogError "Copy-Item  cmdlet failed with the following error: " $error_msg 
        }

        return $false
    }
}

function PrepareCountersFile()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        
        #if we are not calling a Perfmon scenario, return and don't proceed
        if ($global:perfmon_scenario_enabled -eq $false)
        {
            Write-LogWarning "No Perfmon-collection scenario is selected. Perfmon counters file will not be created"
            return
        }

        if (($global:sql_instance_conn_str -ne "") -and ($null -ne $global:sql_instance_conn_str) )
        {
            [string] $SQLServerName = $global:sql_instance_conn_str
        }
        else 
        {
            Write-LogError "SQL instance name is empty.Exiting..."    
            exit
        }

        if (Copy-OriginalLogmanConfig)
        {
            Write-LogDebug "Perfmon Counters file was copied. It is safe to update it in new location" -DebugLogLevel 2
            Update-PerfmonConfigFile($SQLServerName)
        }
        #restoration of original file is in the Stop-DiagCollectors
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}


#======================================== END OF PERFMON COUNTER FILES SECTION