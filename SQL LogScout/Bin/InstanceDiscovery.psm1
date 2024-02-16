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

                $VirtNetworkNamePlusInstance = $vnn

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

function Get-SQLServiceNameAndStatus()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
   
    try 
    {
        
        $InstanceArray = @()


        #find the actively running SQL Server services
        $sql_services = Get-Service | Where-Object {(($_.Name -match "MSSQL\$") -or ($_.Name -eq "MSSQLSERVER"))} | ForEach-Object {[PSCustomObject]@{Name=$_.Name; Status=$_.Status.ToString()}}
        
        if ($sql_services.Count -eq 0)
        {
            #Insert dummy row in array to keep object type consistent
            [PSCustomObject]$sql_services = @{Name='no_instance_found'; Status='UNKNOWN'}
            Write-LogDebug "No installed SQL Server instances found. Array value: $sql_services" -DebugLogLevel 1
   

            Write-LogInformation "There are currently no installed instances of SQL Server. Would you like to proceed with OS-only log collection?" -ForegroundColor Green
            
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
                $InstanceArray+=$sql_services
            }
            elseif ($confirm -eq "N")
            {
                Write-LogInformation "Aborting collection..."
                exit
            }
            
        }

        else 
        {
            
            foreach ($sqlserver in $sql_services)
            {
                Write-LogDebug "The SQL Server service array in foreach contains $sqlserver" -DebugLogLevel 3

                #in the case of a default instance, just use MSSQLSERVER which is the instance name
                if ($sqlserver.Name -contains "$")
                {
                    Write-LogDebug "The SQL Server service array returned $sqlserver" -DebugLogLevel 3
                    $InstanceArray  += $sqlserver
                }

                #for named instance, strip the part after the "$"
                else
                {
                    Write-LogDebug "The SQL Server service named instance array returned $sqlserver" -DebugLogLevel 3
                    $sqlserver.Name = $sqlserver.Name -replace '.*\$',''
                    $InstanceArray  += $sqlserver
                    Write-LogDebug "The SQL Server service named extracted instance array returned $sqlserver" -DebugLogLevel 3
                }
            }

        }

        Write-LogDebug "The running instances are: $InstanceArray"   -DebugLogLevel 3

        return $InstanceArray
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
        $NetworkNamePlusInstanceArray = @()
        $isClustered = $false
        #create dummy record in array and delete $NetworkNamePlusInstanceArray
        

        #get the list of instance names and status of the service
        [PSCustomObject]$InstanceNameAndStatusArray = Get-SQLServiceNameAndStatus
        Write-LogDebug "The InstanceNameAndStatusArray is: $InstanceNameAndStatusArray" -DebugLogLevel 3

        foreach ($SQLInstance in $InstanceNameAndStatusArray)
        {
            Write-LogDebug "Instance name and status: '$SQLInstance'" -DebugLogLevel 3

            #special cases - if no SQL instance on the machine, just hard-code a value
            if ($global:sql_instance_conn_str -eq $SQLInstance.Name)
            {
                $NetworkNamePlusInstanceArray+=@([PSCustomObject]@{Name=$SQLInstance.Name;Status='UNKNOWN'})
                Write-LogDebug "No running SQL Server instances on the box so hard coding a value and collecting OS-data" -DebugLogLevel 1
            }

            elseif ($SQLInstance -and ($null -ne $SQLInstance))
            {
                Write-LogDebug "SQLInstance array contains:" $SQLInstance -DebugLogLevel 2

                #build NetName + Instance 

                $isClustered = IsClustered #($InstanceNameAndStatusArray)

                #if this is on a clustered system, then need to check for FCI or AG resources
                if ($isClustered -eq $true)
                {
                
                    #loop through each instance name and check if FCI or not. If FCI, use ClusterVnnPlusInstance, else use HostnamePlusInstance
                    #append each name to the output array $NetworkNamePlusInstanceArray
                   
                        if (IsFailoverClusteredInstance($SQLInstance.Name))
                            {
                                Write-LogDebug "The instance '$SQLInstance' is a SQL FCI" -DebugLogLevel 2
                                $SQLInstance.Name = Get-ClusterVnnPlusInstance($SQLInstance.Name)
                                $LogRec = $SQLInstance.Name
                                Write-LogDebug "The value of SQLInstance.Name $LogRec" -DebugLogLevel 3
                                Write-LogDebug "Temp FCI value is $SQLInstance" -DebugLogLevel 3
                                Write-LogDebug "The value of the array before change is $NetworkNamePlusInstanceArray" -DebugLogLevel 3
                                Write-LogDebug "The data type of the array before change is ($NetworkNamePlusInstanceArray.GetType())" -DebugLogLevel 3
                                Write-LogDebug "The value of the SQLInstance array before change is $SQLInstance" -DebugLogLevel 3
                                
                                #This doesn't work for some reason
                                #$NetworkNamePlusInstanceArray += $SQLInstance
                                
                                $NetworkNamePlusInstanceArray += @([PSCustomObject]$SQLInstance)

                                Write-LogDebug "The value of the SQLInstance array after change is $SQLInstance" -DebugLogLevel 3
                                Write-LogDebug "Result of FCI is $NetworkNamePlusInstanceArray" -DebugLogLevel 3
                            }
                        else
                        {
                            Write-LogDebug "The instance '$SQLInstance' is a not SQL FCI but is clustered" -DebugLogLevel 2
                            $SQLInstance.Name = Get-HostnamePlusInstance($SQLInstance.Name)
                            $NetworkNamePlusInstanceArray += $SQLInstance
                            Write-LogDebug "Result of non-FCI Cluster is $NetworkNamePlusInstanceArray" -DebugLogLevel 3
                        }

                }
                #all local resources so just build array with local instances
                else
                {
                    $TestLog = $SQLInstance.Name
                    Write-LogDebug "Array value is $SQLInstance" -DebugLogLevel 3
                    Write-LogDebug "Array value.name is $TestLog" -DebugLogLevel 3
                    $SQLInstance.Name = Get-HostnamePlusInstance($SQLInstance.Name)
                    Write-LogDebug "Array value after Get-HostnamePlusInstance is $SQLInstance" -DebugLogLevel 3
                    $NetworkNamePlusInstanceArray += $SQLInstance
                }
            }

            else
            {
                Write-LogError "InstanceArrayLocal array is blank or null - no instances populated for some reason"
            }
        }

        Write-LogDebug "The NetworkNamePlusInstanceArray in Get-NetNameMatchingInstance is: $NetworkNamePlusInstanceArray" -DebugLogLevel 3
        return [PSCustomObject]$NetworkNamePlusInstanceArray
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
        $NetNamePlusinstanceArray = @()

        if ($global:instance_independent_collection -eq $true)
        {
            Write-LogDebug "An instance-independent collection is requested. Skipping instance discovery." -DebugLogLevel 1
            return
        }

        #ma Added
        #$global:gui_mode
        [bool]$isInstanceNameSelected = $false
        if (![string]::IsNullOrWhitespace($Global:ComboBoxInstanceName.Text))
        {
            $SqlIdInt = $Global:ComboBoxInstanceName.SelectedIndex
            $isInstanceNameSelected = $true
        } 
       
        #if SQL LogScout did not accept any values for parameter $ServerName 
        if (($true -eq [string]::IsNullOrWhiteSpace($global:gServerName)) -and $global:gServerName.Length -le 1 )
        {
            Write-LogDebug "Server Instance param is blank. Switching to auto-discovery of instances" -DebugLogLevel 3

            $NetNamePlusinstanceArray = Get-NetNameMatchingInstance

            Write-LogDebug "The NetNamePlusinstanceArray in discovery is: $NetNamePlusinstanceArray" -DebugLogLevel 3

            if ($NetNamePlusinstanceArray.Name -eq $global:sql_instance_conn_str) 
            {
                $hard_coded_instance  = $NetNamePlusinstanceArray.Name
                Write-LogDebug "No running SQL Server instances, thus returning the default '$hard_coded_instance' and collecting OS-data only" -DebugLogLevel 3
                return 
            }
            elseif ($NetNamePlusinstanceArray.Name -and ($null -ne $NetNamePlusinstanceArray.Name))
            {
        
                Write-LogDebug "NetNamePlusinstanceArray contains: " $NetNamePlusinstanceArray -DebugLogLevel 3

                #prompt the user to pick from the list

                $Count = $NetNamePlusinstanceArray.Count
                Write-LogDebug "Count of NetNamePlusinstanceArray is $Count" -DebugLogLevel 3
                Write-LogDebug "isInstanceNameSelected is $isInstanceNameSelected" -DebugLogLevel 3

                if ($NetNamePlusinstanceArray.Count -ne 0 -and !$isInstanceNameSelected)
                {
                    Write-LogDebug "NetNamePlusinstanceArray contains more than one instance. Prompting user to select one" -DebugLogLevel 3
                    
                    $instanceIDArray = 0..($NetNamePlusinstanceArray.Length -1)                 




                    # sort the array by instance name
                    #TO DO - sory by property.
                    $NetNamePlusinstanceArray = $NetNamePlusinstanceArray | Sort-Object -Property Name
                    #TO DO - parse the file length out using something like $maxLength = ($array.Name | Measure-Object -Maximum -Property Length).Maximum. Need to calculate spaces based on values.

                    Write-LogDebug "NetNamePlusinstanceArray sorted contains: " $NetNamePlusinstanceArray -DebugLogLevel 4

                    #set spacing for displaying the text
                    
                    #set hard-coded spacing for displaying the text
                    [string] $StaticGap = "".PadRight(3)

                    #GETTING PROMPT TO DISPLAY 
               
                    ## build the ID# header values
                    $IDHeader = "ID#"

                    #get the max length of the ID# values (for 2000 instances on the box the value would be 1999, and length will be 4 characters)
                    [int]$IDMaxLen = ($NetNamePlusinstanceArray.Count | ForEach-Object { [string]$_ } | Measure-Object -Maximum -Property Length).Maximum

                    #if the max value is less than the header length, then set the header be 3 characters long
                    if ($IDMaxLen -le $IDHeader.Length)
                    {
                        [int]$IDMaxLen = $IDHeader.Length
                    }
                    Write-LogDebug "IDMaxLen is $IDMaxLen"

                    # create the header hyphens to go above the ID#
                    [string]$IDMaxHeader = '-' * $IDMaxLen

                    ## build the instance name header values
                    [string]$InstanceNameHeader = "SQL Instance Name"

                    #get the max length of all the instances found the box (running or stopped)
                    [int]$SQLInstanceNameMaxLen = ($NetNamePlusinstanceArray.Name | ForEach-Object {[string]$_}| Measure-Object -Maximum -Property Length).Maximum
                    Write-LogDebug "SQLInstanceNameMaxLen value is $SQLInstanceNameMaxLen"
                   
                    # if longest instance name is less than the defined header length, then pad to the header length and not instance length
                    if ($SQLInstanceNameMaxLen -le ($InstanceNameHeader.Length))
                    {
                        $SQLInstanceNameMaxLen = $InstanceNameHeader.Length
                    }
                    Write-LogDebug "SQLInstanceNameMaxLen is $SQLInstanceNameMaxLen"

                    # prepare the header hyphens to go above the instance name
                    [string]$SQLInstanceNameMaxHeader = '-' * $SQLInstanceNameMaxLen

                    ## build the service status header values
                    $InstanceStatusHeader = "Status"

                    #get the max length of all the service status strings (running or stopped for now)
                    [int]$ServiceStatusMaxLen= ($NetNamePlusinstanceArray.Status | ForEach-Object {[string]$_} | Measure-Object -Maximum -Property Length).Maximum
 
                    if ($ServiceStatusMaxLen -le $InstanceStatusHeader.Length)
                    {
                        $ServiceStatusMaxLen = $InstanceStatusHeader.Length
                    }
                    Write-LogDebug "ServiceStatusMaxLen is $ServiceStatusMaxLen"

                    #prepare the header hyphens to go above service status
                    [string]$ServiceStatusMaxHeader = '-' * $ServiceStatusMaxLen

                    #display the header
                    Write-LogInformation "Discovered the following SQL Server instance(s)`n"
                    Write-LogInformation ""
                    Write-LogInformation "$($IDHeader+$StaticGap+$InstanceNameHeader.PadRight($SQLInstanceNameMaxLen)+$StaticGap+$InstanceStatusHeader.PadRight($ServiceStatusMaxLen))"
                    Write-LogInformation "$($IDMaxHeader+$StaticGap+$SQLInstanceNameMaxHeader+$StaticGap+$ServiceStatusMaxHeader)"
                    
                    
                    #loop through instances and append to cmd display
                    $i = 0
                    foreach ($FoundInstance in $NetNamePlusinstanceArray)
                    {
                        $InstanceName = $FoundInstance.Name
                        $InstanceStatus = $FoundInstance.Status
                        
                        Write-LogDebug "Looping through $i, $InstanceName, $InstanceStatus" -DebugLogLevel 3
                        Write-LogInformation "$($i.ToString().PadRight($IdMaxLen)+$StaticGap+$InstanceName.PadRight($SQLInstanceNameMaxLen)+$StaticGap+$InstanceStatus.PadRight($ServiceStatusMaxWithSpace))"
                        #Write-LogInformation $i "	" $FoundInstance.Name "	" $FoundInstance.Status
                        $i++
                    }

                    #prompt the user to select an instance
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

            $str = "You selected instance '" + $NetNamePlusinstanceArray[$SqlIdInt].Name +"' to collect diagnostic data. "
            Write-LogInformation $str -ForegroundColor Green

            #set the global variable so it can be easily used by multiple collectors
            $global:sql_instance_conn_str = $NetNamePlusinstanceArray[$SqlIdInt].Name
            
            $global:sql_instance_service_status = $NetNamePlusinstanceArray[$SqlIdInt].Status
            Write-LogDebug "The SQL instance service status is updated to $global:sql_instance_service_status"
            #return $NetNamePlusinstanceArray[$SqlIdInt] 

        }
        # if the instance is passed in as a parameter, then use that value. But test if that instance is running/valid
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
        
            #Get service status. Since user provided instance name, no instance discovery code invoked
            if (Test-SQLConnection($global:sql_instance_conn_str)) 
            {
                $global:sql_instance_service_status = "Running"
            } 
            else 
            {
                $global:sql_instance_service_status = "UNKNOWN"
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