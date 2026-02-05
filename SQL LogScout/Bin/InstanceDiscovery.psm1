Import-Module .\CommonFunctions.psm1

function Get-ClusterVNN ($instance_name)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    try 
    {
            
        $vnn = ""

        if (($instance_name -ne "") -and ($null -ne $instance_name))
        {
            $sql_fci_object = Get-ClusterResource | Where-Object {($_.ResourceType -eq "SQL Server")} | Get-ClusterParameter | Where-Object {($_.Name -eq "InstanceName") -and ($_.Value -eq $instance_name)}
            $vnn_obj = Get-ClusterResource  | Where-Object {($_.ResourceType -eq "SQL Server") -and ($_.OwnerGroup -eq $sql_fci_object.ClusterObject.OwnerGroup.Name)} | Get-ClusterParameter -Name VirtualServerName | Select-Object Value
            $vnn = $vnn_obj.Value
        }
        else
        {
            Write-LogError "Instance name is empty and it shouldn't be at this point ($($MyInvocation.MyCommand))"            
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
            Write-LogError "Instance name is empty and it shouldn't be at this point ($($MyInvocation.MyCommand))"
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
            Write-LogError "Instance name is empty and it shouldn't be at this point ($($MyInvocation.MyCommand))"
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


function GetSqlFciAndLocalityStatus ([string]$instanceName)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        if (($instanceName -eq "") -or ($null -eq $instanceName)) 
        {
            throw "Instance name is empty and it shouldn't be at this point."
        }
    
        # get the list of SQL Server resources in the cluster
        $sqlResources = Get-ClusterResource | Where-Object { $_.ResourceType -eq "SQL Server" }
        
        # now filter the resources to find the one that matches the instance name
        # and check if it is owned by the current node. Foreach loop will run one time only

        foreach ($res in $sqlResources) 
        {
            # check if the resource has a parameter called "InstanceName" and if its value matches the instance name and get that object
            $instClustParam = $res | Get-ClusterParameter | Where-Object { $_.Name -eq "InstanceName" -and $_.Value -eq $instanceName }

            if ($instClustParam ) 
            {
                # if the instance is a SQL FCI, then it will have a parameter called "VirtualServerName" - get that parameter's value
                $virtServerName = Get-ClusterResource  | Where-Object {($_.ResourceType -eq "SQL Server") -and ($_.OwnerGroup -eq $instClustParam.ClusterObject.OwnerGroup.Name)} |
                                        Get-ClusterParameter -Name VirtualServerName | Select-Object Value

                #if the VirtualServerName is empty (broken cluster), or the same as $global:host_name (local machine name) then this is not a SQL FCI - treat as local instance
                if ([string]::IsNullOrWhiteSpace($virtServerName.Value) -or ($virtServerName.Value -eq $global:host_name)) 
                {
                    Write-LogDebug "The instance '$instanceName' is NOT a SQL FCI" -DebugLogLevel 2
                    return "NotSQLFCI"
                }
                else
                {
                    Write-LogDebug "The instance '$instanceName' is a SQL FCI" -DebugLogLevel 2

                    # if the OwnerNode of the resource is the same as the current node, then this is a local SQL FCI
                    # otherwise, this  SQL FCI is running on another node
                    if ($res.OwnerNode -eq $global:host_name) 
                    {
                        Write-LogDebug "The instance '$instanceName' is a SQL FCI and is running locally on this node" -DebugLogLevel 2
                        return "SQLFCILocal"
                    }
                    else 
                    {
                        Write-LogDebug "The instance '$instanceName' is a SQL FCI and is running on another node: '$($res.OwnerNode)'" -DebugLogLevel 2
                        return "SQLFCIRemote"
                    }
                }
            }
        }

        # if no resources found, then return NotSQLFCI. We should not get here, but just in case
        Write-LogDebug "The instance '$instanceName' doesn't have a Cluster resource matching to it. Possibly a local instance" -DebugLogLevel 2
        return "NotSQLFCI" 
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
            [PSCustomObject]$sql_services = @{Name=$global:NO_INSTANCE_NAME; Status='UNKNOWN'}
            Write-LogDebug "No installed SQL Server instances found. Name='$($sql_services.Name)', Status='$($sql_services.Status)'"  -DebugLogLevel 1
   

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

                #in the case of a default instance, just use MSSQLSERVER which is the instance name
                if ($sqlserver.Name -contains "$")
                {
                    Write-LogDebug "The SQL Server service array returned $sqlserver" -DebugLogLevel 3
                    $InstanceArray  += $sqlserver
                }

                #for named instance, strip the part after the "$"
                else
                {
                    $sqlserver.Name = $sqlserver.Name -replace '.*\$',''
                    $InstanceArray  += $sqlserver
                    Write-LogDebug "The SQL Server service named extracted instance array returned $sqlserver" -DebugLogLevel 3
                }
            }

        }

        Write-LogDebug "The SQL Server instances discovered are: "   -DebugLogLevel 3
        $InstanceArray | ForEach-Object {
            Write-LogDebug "  $($_.Name) $($_.Status) " -DebugLogLevel 3
        }

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
        $isNodeClustered = $false
        #create dummy record in array and delete $NetworkNamePlusInstanceArray
        

        #get the list of instance names and status of the service
        [PSCustomObject]$InstanceNameAndStatusArray = Get-SQLServiceNameAndStatus
        

        # check if this is a clustered node - machine is part of a WSFC
        # if this is a clustered node, then later we need to check if the instance is a FCI or an AG
        $isNodeClustered = IsNodeOnWSFC 


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

                

                #if this is on a clustered system, then need to check for FCI or AG resources
                if ($true -eq $isNodeClustered)
                {
                
                    #loop through each instance name and check if FCI or not. If FCI, use ClusterVnnPlusInstance, else use HostnamePlusInstance
                    #append each name to the output array $NetworkNamePlusInstanceArray
                    $status = GetSqlFciAndLocalityStatus -instanceName ($SQLInstance.Name)

                    
                    switch ($status)
                    {
                        "SQLFCILocal"
                        {
                            $SQLInstance.Name = Get-ClusterVnnPlusInstance($SQLInstance.Name)
                            $NetworkNamePlusInstanceArray += @([PSCustomObject]$SQLInstance)
                            
                        }
                        "SQLFCIRemote"
                        {

                            # If the SQL FCI is running on another node (FCI remote), then we want to check if there is a local instance with the same name (a very unlikely scenario)
                            # If there is, then we will append it to the array, otherwise just log the message that it is running on another node

                            if ($SQLInstance.Status -eq "Running")
                            {
                                $SQLInstance.Name = Get-HostnamePlusInstance($SQLInstance.Name)
                                $NetworkNamePlusInstanceArray += @([PSCustomObject]$SQLInstance)
                            }
                            else
                            {
                                # no need to append to the array, just log the message
                                Write-LogInformation  "Skipping instance '$($SQLInstance.Name)' from being listed since it's running on another node."
                                continue
                            }

                        }
                        "NotSQLFCI"
                        {
                            $SQLInstance.Name = Get-HostnamePlusInstance($SQLInstance.Name)
                            $NetworkNamePlusInstanceArray += @([PSCustomObject]$SQLInstance)
                        }
                        default
                        ############# this is a catch-all for any other value returned by GetSqlFci
                        {
                            Write-LogError "The instance '$($SQLInstance.Name)' is not in a defined state SQL FCI or not. Skipping it."
                            continue
                        }
                    }

                }
                else #all local resources so just build array with local instances
                {
                    $SQLInstance.Name = Get-HostnamePlusInstance($SQLInstance.Name)
                    Write-LogDebug "Array value after Get-HostnamePlusInstance is $SQLInstance" -DebugLogLevel 3
                    $NetworkNamePlusInstanceArray += @([PSCustomObject]$SQLInstance)
                }
            }

            else
            {
                Write-LogError "InstanceArrayLocal array is blank or null - no instances populated for some reason"
            }
        }#end of foreach


        Write-LogDebug "The NetworkNamePlusInstanceArray in Get-NetNameMatchingInstance contains: " -DebugLogLevel 3
    
        #display the array contents
        $NetworkNamePlusInstanceArray | ForEach-Object {
            Write-LogDebug "  $_" -DebugLogLevel 3
        }

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


            if ($NetNamePlusinstanceArray.Name -eq $global:sql_instance_conn_str) 
            {
                $hard_coded_instance  = $NetNamePlusinstanceArray.Name
                Write-LogDebug "No running SQL Server instances, thus returning the default '$hard_coded_instance' and collecting OS-data only" -DebugLogLevel 3
                return 
            }
            elseif ($NetNamePlusinstanceArray.Name -and ($null -ne $NetNamePlusinstanceArray.Name))
            {
        
                #prompt the user to pick from the list

                $Count = $NetNamePlusinstanceArray.Count
                Write-LogDebug "Count of NetNamePlusinstanceArray is $Count" -DebugLogLevel 3
                Write-LogDebug "isInstanceNameSelected is $isInstanceNameSelected" -DebugLogLevel 3

                if ($NetNamePlusinstanceArray.Count -ne 0 -and !$isInstanceNameSelected)
                {
                    Write-LogDebug "NetNamePlusinstanceArray contains more than one instance. Prompting user to select one" -DebugLogLevel 3
                    
                    $instanceIDArray = 0..($NetNamePlusinstanceArray.Length -1)                 




                    # sort the array by instance name
                    $NetNamePlusinstanceArray = $NetNamePlusinstanceArray | Sort-Object -Property Name

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

                    # create the header hyphens to go above the ID#
                    [string]$IDMaxHeader = '-' * $IDMaxLen

                    ## build the instance name header values
                    [string]$InstanceNameHeader = "SQL Instance Name"

                    #get the max length of all the instances found the box (running or stopped)
                    [int]$SQLInstanceNameMaxLen = ($NetNamePlusinstanceArray.Name | ForEach-Object {[string]$_}| Measure-Object -Maximum -Property Length).Maximum
                   
                    # if longest instance name is less than the defined header length, then pad to the header length and not instance length
                    if ($SQLInstanceNameMaxLen -le ($InstanceNameHeader.Length))
                    {
                        $SQLInstanceNameMaxLen = $InstanceNameHeader.Length
                    }

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

                    #prepare the header hyphens to go above service status
                    [string]$ServiceStatusMaxHeader = '-' * $ServiceStatusMaxLen

                    #display the header
                    Write-LogInformation "Discovered the following locally-running SQL Server instance(s):`n"
                    Write-LogInformation "$($IDHeader+$StaticGap+$InstanceNameHeader.PadRight($SQLInstanceNameMaxLen)+$StaticGap+$InstanceStatusHeader.PadRight($ServiceStatusMaxLen))"
                    Write-LogInformation "$($IDMaxHeader+$StaticGap+$SQLInstanceNameMaxHeader+$StaticGap+$ServiceStatusMaxHeader)"
                    
                    
                    #loop through instances and append to cmd display
                    $i = 0
                    foreach ($FoundInstance in $NetNamePlusinstanceArray)
                    {
                        $InstanceName = $FoundInstance.Name
                        $InstanceStatus = $FoundInstance.Status

                        Write-LogInformation "$($i.ToString().PadRight($IdMaxLen)+$StaticGap+$InstanceName.PadRight($SQLInstanceNameMaxLen)+$StaticGap+$InstanceStatus.PadRight($ServiceStatusMaxWithSpace))"
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
                $inst_name_object = Get-InstanceNameObject ($global:gServerName)

                #if a named instance (type 1) name is valid, then use it
                if ($inst_name_object.Type -eq $global:SQLInstanceType["NamedInstance"]) 
                {
                    $inst_name = $inst_name_object.InstanceName
                    $global:sql_instance_conn_str = ($global:host_name + "\" + $inst_name)
                }
                else # this is not likely to happen, but just in case we need to handle it and cause a failure
                {
                    Write-LogError "The instance name passed in is not valid."
                    $global:sql_instance_conn_str = $global:NO_INSTANCE_NAME
                }
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

        #return instance in case this function needs to be called externally
        return $global:sql_instance_conn_str

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return $global:NO_INSTANCE_NAME
    }
}


function Set-NoInstanceToHostName()
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try 
    {
        if ($global:sql_instance_conn_str -eq $global:NO_INSTANCE_NAME)
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
# SIG # Begin signature block
# MIIsDwYJKoZIhvcNAQcCoIIsADCCK/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB3qF+wOw8oRINE
# 2+G7yWTPUxbEz3nIVrfQdfwwwccsc6CCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
# oOn9X5/TAAIAAAIOMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzEyMDNaFw0yNjA0MjYyMzIyMDNaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCfrw9mbjhRpCz0Wh+dmWU4nlBbeiDkl5NfNWFA9NWUAfDcSAEtWiJTZLIB
# Vt+E5kjpxQfCeObdxk0aaPKmhkANla5kJ5egjmrttmGvsI/SPeeQ890j/QO4YI4g
# QWpXnt8EswtW6xzmRdMMP+CASyAYJ0oWQMVXXMNhBG9VBdrZe+L1+DzLawq42AWG
# NoKL6JdGg21P0W11MN1OtwrhubgTqEBkgYp7m1Bt4EeOxBz0GwZfPODbLVTblACS
# LmGlfEePEdVamqIUTTdsrAKG8NM/gGx010AiqAv6p2sCtSeZpvV7fkppLY9ajdm8
# Yc4Kf1KNI3U5ZNMdLIDz9fA5Q+ulAgMBAAGjggWZMIIFlTApBgkrBgEEAYI3FQoE
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
# aG9yaXR5MB0GA1UdDgQWBBSbKJrguVhFagj1tSbzFntHGtugCTAOBgNVHQ8BAf8E
# BAMCB4AwVAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjM2MTY3KzUwNjA1MjCCAeYG
# A1UdHwSCAd0wggHZMIIB1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5j
# b20vcGtpaW5mcmEvQ1JML0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6
# Ly9jcmwxLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0
# dHA6Ly9jcmwyLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyG
# MWh0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5j
# cmyGMWh0dHA6Ly9jcmw0LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgy
# KS5jcmyGgb1sZGFwOi8vL0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQ
# S0lDU0NBMDEsQ049Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNl
# cnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0
# ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9u
# UG9pbnQwHwYDVR0jBBgwFoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgw
# FgYKKwYBBAGCN1sBAQYIKwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAKaBh/B8
# 42UPFqNHP+m2mYSY80orKjPVnXEb+KlCoxL1Ikl2DfziE1PBZXtCDbYtvyMqC9Pj
# KvB8TNz71+CWrO0lqV2f0KITMmtXiCy+yThBqLYvUZrbrRzlXYv2lQmqWMy0OqrK
# TIdMza2iwUp2gdLnKzG7DQ8IcbguYXwwh+GzbeUjY9hEi7sX7dgVP4Ls1UQNkRqR
# FcRPOAoTBZvBGhPSkOAnl9CShvCHfKrHl0yzBk/k/lnt4Di6A6wWq4Ew1BveHXMH
# 1ZT+sdRuikm5YLLqLc/HhoiT3rid5EHVQK3sng95fIdBMgj26SScMvyKWNC9gKkp
# emezUSM/c91wEhwwggjoMIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0G
# CSqGSIb3DQEBCwUAMDwxEzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/Is
# ZAEZFgNBTUUxEDAOBgNVBAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYw
# NTIxMTg1NDE0WjBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQB
# GRYDQU1FMRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQDJmlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL
# 9rNHnHDGfJgeuRIYO1LY/1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc
# 411WxA+Pv2rteAcz0eHMH36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaC
# IIWBXyEchv+sM9eKDsUOLdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8p
# XirIYOgM770CYOiZrcKHK7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p
# /6fksgEILptOKhx9c+iapiNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkr
# BgEEAYI3FQEEBQIDAgACMCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMAL
# I38/RzAdBgNVHQ4EFgQUllGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfww
# gfkGBysGAQUCAwUGCCsGAQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYB
# BAGCNxUGBgorBgEEAYI3CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgC
# AgYKKwYBBAGCN0ABAQYLKwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcV
# BQYKKwYBBAGCNxQCAgYKKwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEG
# CisGAQQBgjdbAgEGCisGAQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEG
# CisGAQQBgjdbBAIwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQD
# AgGGMBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwN
# p4x1AdEJCygwggFoBgNVHR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDov
# L2NybDIuYW1lLmdibC9jcmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5n
# YmwvY3JsL2FtZXJvb3QuY3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVy
# b290LmNybIaBqmxkYXA6Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxD
# Tj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1
# cmF0aW9uLERDPUFNRSxEQz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9i
# YXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUH
# AQEEggGdMIIBmTBHBggrBgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NlcnRzL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKG
# K2h0dHA6Ly9jcmwyLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYI
# KwYBBQUHMAKGK2h0dHA6Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9v
# dC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJv
# b3RfYW1lcm9vdC5jcnQwgaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290
# LENOPUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxD
# Tj1Db25maWd1cmF0aW9uLERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNl
# P29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQEL
# BQADggIBAFAQI7dPD+jfXtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTH
# b8BDfRN+AD0YEmeDB5HKQoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a
# /752hMIn+L4ZuyxVeSBpfwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9
# zAh9yRKKls2bziPEnxeOZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAm
# n3WCPWNFC1YTIIHw/mD2cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtz
# yb7fbNS1dE740re0COE67YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjF
# K1yMw4Ni5fMabcgmzRvSjAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bz
# MzsikuDW9xH10graZzSmPjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIz
# J6Q9G3NPCB+7KwX0OQmKyv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/y
# wO6SYSreVW+5Y0mzJutnBC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEIS
# RtShDZbuYymynY1un+RyfiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZ6DCCGeQC
# AQEwWDBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1F
# MRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDECEzYAAAIOeZeg6f1fn9MAAgAAAg4wDQYJ
# YIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPo449FFAt/M
# UWdJoRJrCuzYkzl9uBHgvlGrleGllg8HMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEACx1mbvkyspwYbXfRXF3f8PTvG67HngpusKMgm83ZYvoR
# yXxZ9WIAMlKdQCvR2J/ibtWKewW7Ra6Ujn0qDBd1WmH41qWRk/oZFB/nhCTqJAQd
# HrHorY4hvtZ8DYnIiaFPMKtY8Bk6wOJPyIJNrjl+o0rd7JwVo0KmZah6JnFOSwSR
# zAykaVkVHF8tYG7E9Du5an/c1bBN7yG+7fDQx2ofCR64ruKR09SK/qAK5Um4Zj3F
# i1Ghy1mX5SIVPSZp7eXpk2AqDmapgb7uGCe7wI24jjS2rZfVV83aLxAlB0/m8ooG
# YUVY7+wxHbW55ojpM8/diecSJG2rM+S7EqiXIrNutKGCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCDa0RfcC9YyB8CrfPtxQ7KTZp+Vig5aWQ1YG8eSdWX4
# qgIGaXRAeW+WGBMyMDI2MDIwNDE2MzUzMC4zNTdaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo1OTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACFI3NI0TuBt9y
# AAEAAAIUMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgxOFoXDTI2MTExMzE4NDgxOFowgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjU5MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyU+nWgCU
# yvfyGP1zTFkLkdgOutXcVteP/0CeXfrF/66chKl4/MZDCQ6E8Ur4kqgCxQvef7Lg
# 1gfso1EWWKG6vix1VxtvO1kPGK4PZKmOeoeL68F6+Mw2ERPy4BL2vJKf6Lo5Z7X0
# xkRjtcvfM9T0HDgfHUW6z1CbgQiqrExs2NH27rWpUkyTYrMG6TXy39+GdMOTgXyU
# DiRGVHAy3EqYNw3zSWusn0zedl6a/1DbnXIcvn9FaHzd/96EPNBOCd2vOpS0Ck7k
# gkjVxwOptsWa8I+m+DA43cwlErPaId84GbdGzo3VoO7YhCmQIoRab0d8or5Pmyg+
# VMl8jeoN9SeUxVZpBI/cQ4TXXKlLDkfbzzSQriViQGJGJLtKS3DTVNuBqpjXLdu2
# p2Yq9ODPqZCoiNBh4CB6X2iLYUSO8tmbUVLMMEegbvHSLXQR88QNICjFoBBDCDyd
# oTo9/TNkq80mO77wDM04tPdvbMmxT01GTod60JJxUGmMTgseghdBGjkN+D6GsUpY
# 7ta7hP9PzLrs+Alxu46XT217bBn6EwJsAYAc9C28mKRUcoIZWQRb+McoZaSu2EcS
# zuIlAaNIQNtGlz2PF3foSeGmc/V7gCGs8AHkiKwXzJSPftnsH8O/R3pJw2D/2hHE
# 3JzxH2SrLX1FdI7Drw145PkL0hbFL6MVCCkCAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBTbX/bs1cSpyTYnYuf/Mt9CPNhwGzAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# P3xp9D4Gu0SH9B+1JH0hswFquINaTT+RjpfEr8UmUOeDl4U5uV+i28/eSYXMxgem
# 3yBZywYDyvf4qMXUvbDcllNqRyL2Rv8jSu8wclt/VS1+c5cVCJfM+WHvkUr+dCfU
# lOy9n4exCPX1L6uWwFH5eoFfqPEp3Fw30irMN2SonHBK3mB8vDj3D80oJKqe2tat
# O38yMTiREdC2HD7eVIUWL7d54UtoYxzwkJN1t7gEEGosgBpdmwKVYYDO1USWSNmZ
# ELglYA4LoVoGDuWbN7mD8VozYBsfkZarOyrJYlF/UCDZLB8XaLfrMfMyZTMCOuEu
# PD4zj8jy/Jt40clrIW04cvLhkhkydBzcrmC2HxeE36gJsh+jzmivS9YvyiPhLkom
# 1FP0DIFr4VlqyXHKagrtnqSF8QyEpqtQS7wS7ZzZF0eZe0fsYD0J1RarbVuDxmWs
# q45n1vjRdontuGUdmrG2OGeKd8AtiNghfnabVBbgpYgcx/eLyW/n40eTbKIlsm0c
# seyuWvYFyOqQXjoWtL4/sUHxlWIsrjnNarNr+POkL8C1jGBCJuvm0UYgjhIaL+XB
# XavrbOtX9mrZ3y8GQDxWXn3mhqM21ZcGk83xSRqB9ecfGYNRG6g65v635gSzUmBK
# ZWWcDNzwAoxsgEjTFXz6ahfyrBLqshrjJXPKfO+9Ar8wggdxMIIFWaADAgECAhMz
# AAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0z
# MDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP9
# 7pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMM
# tY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gm
# U3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130
# /o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP
# 3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
# vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+A
# utuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz
# 1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
# EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/Zc
# UlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZy
# acaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJ
# KwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8G
# CCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3Mv
# UmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZF
# aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
# AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cB
# MSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7
# bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/
# SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2
# EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2Fz
# Lixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0
# /fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
# swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJ
# Xk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+
# pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
# 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCCAkECAQEwggEBoYHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo1OTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA2RysX196RXLTwA/P8RFW
# dUTpUsaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0t53MwIhgPMjAyNjAyMDQxNTQyNDNaGA8yMDI2MDIwNTE1
# NDI0M1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7S3ncwIBADAKAgEAAgIB2wIB
# /zAHAgEAAgISOzAKAgUA7S848wIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IB
# AQCWj6LbcjtppvPg46eU6FmATii+3YF/eGZqbM+xvp1MWOmwywxcgzEjJcRmZ7bo
# mbvv7PXIZmwrNN2tQtvU+2QolYFmDiUVToJ29JAsK8wVXe5RmmIY4B/mhMmVWZNC
# kVfycFo4IbMiXbfBQzPs+ELqSBmb9Txn+LIvK/qX5GxPT7z3d2BRVuvdttsZVoQl
# 8xrVjciuzb35c87kqsl5vmHhvLlG2R7bt2dBATZHiJWc5sl6UShC8KEtAc03m/Vd
# 4BxLvnYXFUh7Gwg3u7esQ9olTBh8R+Kg7fIIs78MmbieiFgeTR5/cBly36DYJlMW
# Ng30BeFB/7OvN1imTRjrjh6vMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIUjc0jRO4G33IAAQAAAhQwDQYJYIZIAWUDBAIB
# BQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgMgXXdKwW+glwMjpjhBXvgl69WIEwEAUTODpkDj4p9FEwgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCA2eKvvWx5bcoi43bRO3+EttQUCvyeD2dbXy/6+0xK+
# xzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACFI3N
# I0TuBt9yAAEAAAIUMCIEICtPp+hyWwC7IKIybvj3Fc0ZTxyC5wEnJ36AwhgVt0m1
# MA0GCSqGSIb3DQEBCwUABIICAHNEvNiNWMDuotDkHF/bO4RbRHqYOqJtGag8s39d
# 2hXnPGdmoiepTD77EKXc/gqcH56LWmS1uAjdzi72y0OVaDiKb+IFrEQDXtFgGpw3
# YJt9kgnMu3d3OyVOZ4GUYW4fcQNgBhZYSzf+7g5/nrE9CXMuAkejJe7ceu1LWol+
# ceVQOd0X9dVJtwCioUYMsunO48anFCN3TIRt2ZbwtxHlgFRVPfX2zTMgw1XiiTOC
# PelMZyFiiPacIBe9N8BCMaWsUkzBGtPdngvbhlHG0UZkLNWwttQ33Ie+I15/UMBP
# LDz8v5uYPy/4nhUnX6Y92D1Lg6tfTX0Vb6I/NRkRFUCYjOpb0MIsMPRQmjpfLfRV
# Zh3fxVXkJrpCnzLsvCrTBnVeUgeCvoT1lHvDwZRcVkWiRKla1fE8lSkoBEJ8lGKR
# VfhBI97UW9ENbRLw1FW/KoFBjuMdJC7bD+Gr7Uk81UOJL4+kQe0+JhCXf5k6sjF8
# vRIeLy1qbDrn1AhBml900yZYTuuRraDO1Ckxk2nNBmrK5hKh4JYm/AsuCWNRrLBQ
# ZhLGMb59sDsvTVdDOke5kry1kyChhaaFUyMFkTOYH7orkLMp7GuKXIjkCF5As4xl
# vpLTCJkkTFWGOdQHXIspcH8Gs3R7BzUPAYuIqwNbzD4n3ym2tiOa3aZrLjfwKpsM
# Tb4U
# SIG # End signature block
