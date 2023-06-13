Import-Module .\CommonFunctions.psm1

function Get-ClusterVNN ($instance_name)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    try 
    {
            
        $vnn = ""

        if (($instance_name -ne "") -and ($null -ne $instance_name))
        {
            $sql_fci_object = Get-ClusterResource | Where-Object {($_.ResourceType -eq "SQL Server")} | get-clusterparameter | Where-Object {($_.Name -eq "InstanceName") -and ($_.Value -eq $instance_name)}
            $vnn_obj = Get-ClusterResource  | Where-Object {($_.ResourceType -eq "SQL Server") -and ($_.OwnerGroup -eq $sql_fci_object.ClusterObject.OwnerGroup.Name)} | get-clusterparameter -Name VirtualServerName | Select-Object Value
            $vnn = $vnn_obj.Value
        }
        else
        {
            Write-LogError "Instance name is empty and it shouldn't be at this point"            
        }
        
        Write-LogDebug "The VNN Matched to Instance = '$instance_name' is  '$vnn' " -DebugLogLevel 2

        return $vnn
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function Get-ClusterVnnPlusInstance([string]$instance)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
	
    try 
    {
        
        [string]$VirtNetworkNamePlusInstance = ""

        if (($instance -eq "") -or ($null -eq $instance)) 
        {
            Write-LogError "Instance name is empty and it shouldn't be at this point"
        }
        else
        {
            #take the array instance-only names and look it up against the cluster resources and get the VNN that matches that instance. Then populate the NetName array

            $vnn = Get-ClusterVNN ($instance)

            # for default instance
            # DO NOT concatenate instance name
            if ($instance -eq "MSSQLSERVER"){
                Write-LogDebug  "VirtualName+Instance:   " ($vnn) -DebugLogLevel 2

                $VirtNetworkNamePlusInstance = ($vnn)

                Write-LogDebug "Combined NetName+Instance: '$VirtNetworkNamePlusInstance'" -DebugLogLevel 2
            }
            else
            {
                Write-LogDebug  "VirtualName+Instance:   " ($vnn + "\" + $instance) -DebugLogLevel 2

                $VirtNetworkNamePlusInstance = ($vnn + "\" + $instance)

                Write-LogDebug "Combined NetName+Instance: '$VirtNetworkNamePlusInstance'" -DebugLogLevel 2
            }
        }

        return $VirtNetworkNamePlusInstance    
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function Get-HostnamePlusInstance([string]$instance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
	
    try 
    {
        
        [string]$NetworkNamePlustInstance = ""
        
        if (($instance -eq "") -or ($null -eq $instance)) 
        {
            Write-LogError "Instance name is empty and it shouldn't be at this point"
        }
        else
        {
            #take the array instance-only names and look it up against the cluster resources and get the VNN that matches that instance. Then populate the NetName array
            $host_name = $global:host_name

            #Write-LogDebug "HostNames+Instance:   " ($host_name + "\" + $instance) -DebugLogLevel 4

            if ($instance -eq "MSSQLSERVER")
            {
                $NetworkNamePlustInstance = $host_name
            }
            else
            {
                $NetworkNamePlustInstance = ($host_name + "\" + $instance)
            }

            Write-LogDebug "Combined HostName+Instance: " $NetworkNamePlustInstance -DebugLogLevel 3
        }

        return $NetworkNamePlustInstance
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}



function IsFailoverClusteredInstance([string]$instanceName)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    try 
    {
    
        if (Get-ClusterResource  | Where-Object {($_.ResourceType -eq "SQL Server")} | get-clusterparameter | Where-Object {($_.Name -eq "InstanceName") -and ($_.Value -eq $instanceName)} )
        {
            Write-LogDebug "The instance '$instanceName' is a SQL FCI " -DebugLogLevel 2
            return $true
        }
        else 
        {
            Write-LogDebug "The instance '$instanceName' is NOT a SQL FCI " -DebugLogLevel 2
            return $false    
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function Get-InstanceNamesOnly()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
   
    try 
    {
        
        [string[]]$instnaceArray = @()
        $selectedSqlInstance = ""


        #find the actively running SQL Server services
        $SqlTaskList = Tasklist /SVC /FI "imagename eq sqlservr*" /FO CSV | ConvertFrom-Csv

        
        if ($SqlTaskList.Count -eq 0)
        {

            Write-LogInformation "There are currently no running instances of SQL Server. Would you like to proceed with OS-only log collection" -ForegroundColor Green
            
            if ($global:gInteractivePrompts -eq "Noisy")
            {
                $ValidInput = "Y","N"
                $ynStr = Read-Host "Proceed with logs collection (Y/N)?>" -CustomLogMessage "no_sql_instance_logs input: "
                $HelpMessage = "Please enter a valid input ($ValidInput)"

                #$AllInput = $ValidInput,$WPR_YesNo,$HelpMessage 
                $AllInput = @()
                $AllInput += , $ValidInput
                $AllInput += , $ynStr
                $AllInput += , $HelpMessage
            
                [string] $confirm = validateUserInput($AllInput)
            }
            elseif ($global:gInteractivePrompts -eq "Quiet") 
            {
                Write-LogDebug "'Quiet' mode enabled" -DebugLogLevel 4
                $confirm = "Y"
            }

            Write-LogDebug "The choice made is '$confirm'"

            if ($confirm -eq "Y")
            {
                $instnaceArray+=$global:sql_instance_conn_str
            }
            elseif ($confirm -eq "N")
            {
                Write-LogInformation "Aborting collection..."
                exit
            }
            
        }

        else 
        {
            Write-LogDebug "The running instances are: " $SqlTaskList -DebugLogLevel 3
            Write-LogDebug "" -DebugLogLevel 3
            $SqlTaskList | Select-Object  PID, "Image name", Services | ForEach-Object {Write-LogDebug $_ -DebugLogLevel 5}
            Write-LogDebug ""
        
            foreach ($sqlinstance in $SqlTaskList.Services)
            {
                #in the case of a default instance, just use MSSQLSERVER which is the instance name

                if ($sqlinstance.IndexOf("$") -lt 1)
                {
                    $selectedSqlInstance  = $sqlinstance
                }

                #for named instance, strip the part after the "$"
                else
                {
                    $selectedSqlInstance  = $sqlinstance.Substring($sqlinstance.IndexOf("$") + 1)
                }

                
                #add each instance name to the array
                $instnaceArray+=$selectedSqlInstance 
            }

        }


        return $instnaceArray
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}


function Get-NetNameMatchingInstance()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try
    {
        [string[]]$NetworkNamePlustInstanceArray = @()
        $isClustered = $false
        [string[]]$instanceArrayLocal = @()


        #get the list of instance names
        $instanceArrayLocal = Get-InstanceNamesOnly

        #special cases - if no SQL instance on the machine, just hard-code a value
        if ($global:sql_instance_conn_str -eq $instanceArrayLocal.Get(0) )
        {
            $NetworkNamePlustInstanceArray+=$instanceArrayLocal.Get(0)
            Write-LogDebug "No running SQL Server instances on the box so hard coding a value and collecting OS-data" -DebugLogLevel 1
        }
        elseif ($instanceArrayLocal -and ($null -ne $instanceArrayLocal))
        {
            Write-LogDebug "InstanceArrayLocal contains:" $instanceArrayLocal -DebugLogLevel 2

            #build NetName + Instance 

            $isClustered = IsClustered #($instanceArrayLocal)

            #if this is on a clustered system, then need to check for FCI or AG resources
            if ($isClustered -eq $true)
            {
            
                #loop through each instance name and check if FCI or not. If FCI, use ClusterVnnPlusInstance, else use HostnamePlusInstance
                #append each name to the output array $NetworkNamePlustInstanceArray
                for($i=0; $i -lt $instanceArrayLocal.Count; $i++)
                {
                    if (IsFailoverClusteredInstance($instanceArrayLocal[$i]))
                        {
                            $NetworkNamePlustInstanceArray += Get-ClusterVnnPlusInstance ($instanceArrayLocal[$i])  
                        }
                    else
                    {
                        $NetworkNamePlustInstanceArray += Get-HostnamePlusInstance($instanceArrayLocal[$i])
                    }

                }
            }
            #all local resources so just build array with local instances
            else
            {
                for($i=0; $i -lt $instanceArrayLocal.Count; $i++)
                {
                        $NetworkNamePlustInstanceArray += Get-HostnamePlusInstance($instanceArrayLocal[$i])
                }

            }




        }

        else
        {
            Write-LogError "InstanceArrayLocal array is blank or null - no instances populated for some reason"
        }

        return $NetworkNamePlustInstanceArray
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}


#Display them to user and let him pick one
function Select-SQLServerForDiagnostics()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    try 
    {
    
        $SqlIdInt = 777
        $isInt = $false
        $ValidId = $false
        [string[]]$NetNamePlusinstanceArray = @()
        [string]$PickedNetPlusInstance = ""

        if ($global:instance_independent_collection -eq $true)
        {
            Write-LogDebug "An instance-independent collection is requested. Skipping instance discovery." -DebugLogLevel 1
            return
        }

        #ma Added
        #$global:gui_mode
        [bool]$isInstanceNameSelected = $false
        IF (![string]::IsNullOrWhitespace($Global:ComboBoxInstanceName.Text))
        {
            $portName = $Global:ComboBoxInstanceName.SelectedIndex
            $SqlIdInt = $Global:ComboBoxInstanceName.SelectedIndex
            $isInstanceNameSelected = $true
        } 
       
        #if SQL LogScout did not accept any values for parameter $ServerName 
        if (($true -eq [string]::IsNullOrWhiteSpace($global:gServerName)) -and $global:gServerName.Length -le 1 )
        {
            Write-LogDebug "Server Instance param is blank. Switching to auto-discovery of instances" -DebugLogLevel 2

            $NetNamePlusinstanceArray = Get-NetNameMatchingInstance

            if ($NetNamePlusinstanceArray.get(0) -eq $global:sql_instance_conn_str) 
            {
                $hard_coded_instance  = $NetNamePlusinstanceArray.Get(0)
                Write-LogDebug "No running SQL Server instances, thus returning the default '$hard_coded_instance' and collecting OS-data only" -DebugLogLevel 1
                return 
            }
            elseif ($NetNamePlusinstanceArray -and ($null -ne $NetNamePlusinstanceArray))
            {
                Write-LogDebug "NetNamePlusinstanceArray contains: " $NetNamePlusinstanceArray -DebugLogLevel 4

                #prompt the user to pick from the list

                
                if ($NetNamePlusinstanceArray.Count -ge 1 -and !$isInstanceNameSelected)
                {
                    
                    $instanceIDArray = 0..($NetNamePlusinstanceArray.Length -1)

                    #print out the instance names

                    Write-LogInformation "Discovered the following SQL Server instance(s)`n"
                    Write-LogInformation ""
                    Write-LogInformation "ID	SQL Instance Name"
                    Write-LogInformation "--	----------------"

                    # sort the array by instance name
                    $NetNamePlusinstanceArray = $NetNamePlusinstanceArray | Sort-Object

                    for($i=0; $i -lt $NetNamePlusinstanceArray.Count;$i++)
                    {
                        Write-LogInformation $i "	" $NetNamePlusinstanceArray[$i]
                    }

                    while(($isInt -eq $false) -or ($ValidId -eq $false))
                    {
                        Write-LogInformation ""
                        Write-LogWarning "Enter the ID of the SQL instance for which you want to collect diagnostic data. Then press Enter" 
                        #Write-LogWarning "Then press Enter" 

                        $SqlIdStr = Read-Host "Enter the ID from list above>" -CustomLogMessage "SQL Instance Console input:"
                        
                        try{
                                $SqlIdInt = [convert]::ToInt32($SqlIdStr)
                                $isInt = $true
                            }

                        catch [FormatException]
                            {
                                Write-LogError "The value entered for ID '",$SqlIdStr,"' is not an integer"
                                continue
                            }
            
                        #validate this ID is in the list discovered 
                        if ($SqlIdInt -in ($instanceIDArray))
                        {
                            $ValidId = $true
                            break;
                        }
                        else 
                        {
                            $ValidId = $false
                            Write-LogError "The numeric instance ID entered '$SqlIdInt' is not in the list"
                        }
                    }   #end of while

                }#end of IF
            }
            else
            {
                Write-LogError "NetNamePlusinstanceArray array is blank or null. Exiting..."
                exit
            }

            $str = "You selected instance '" + $NetNamePlusinstanceArray[$SqlIdInt] +"' to collect diagnostic data. "
            Write-LogInformation $str -ForegroundColor Green

            #set the global variable so it can be easily used by multiple collectors
            $global:sql_instance_conn_str = $NetNamePlusinstanceArray[$SqlIdInt] 

            #return $NetNamePlusinstanceArray[$SqlIdInt] 

        }

        else 
        {
            Write-LogDebug "Server Instance param is '$($global:gServerName)'. Using this value for data collection" -DebugLogLevel 2
            
            # assign the param passed into the script to the global variable
            # if parameter passed is "." or "(local)", then use the hostname
            
            if (($global:gServerName -eq ".") -or ($global:gServerName -eq "(local)"))
            {
                $global:sql_instance_conn_str = $global:host_name
            }
            elseif (($global:gServerName -like ".\*") -or ($global:gServerName -eq "(local)\*")) 
            {
                $inst_name = Get-InstanceNameOnly ($global:gServerName)
                $global:sql_instance_conn_str = ($global:host_name + "\" + $inst_name)
            }
            else 
            {
                $global:sql_instance_conn_str = $global:gServerName
            }
            
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}


function Set-NoInstanceToHostName()
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try 
    {
        if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
        {
            $global:sql_instance_conn_str = $global:host_name
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    
}