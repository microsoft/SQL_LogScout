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
            
            if ($InteractivePrompts -eq "Noisy")
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
            elseif ($InteractivePrompts -eq "Quiet") 
            {
                Write-LogDebug "QUIET mode enabled" -DebugLogLevel 4
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

        #if SQL LogScout did not accept any values for parameter $ServerName 
        if (($true -eq [string]::IsNullOrWhiteSpace($ServerName)) -and $ServerName.Length -le 1 )
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

                
                if ($NetNamePlusinstanceArray.Count -ge 1)
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
            Write-LogDebug "Server Instance param is '$ServerName'. Using this value for data collection" -DebugLogLevel 2
            
            # assign the param passed into the script to the global variable
            # if parameter passed is "." or "(local)", then use the hostname
            
            if (($ServerName -eq ".") -or ($ServerName -eq "(local)"))
            {
                $global:sql_instance_conn_str = $global:host_name
            }
            elseif (($ServerName -like ".\*") -or ($ServerName -eq "(local)\*")) 
            {
                $inst_name = Get-InstanceNameOnly ($ServerName)
                $global:sql_instance_conn_str = ($global:host_name + "\" + $inst_name)
            }
            else 
            {
                $global:sql_instance_conn_str = $ServerName
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
# SIG # Begin signature block
# MIInwAYJKoZIhvcNAQcCoIInsTCCJ60CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBdS4aBkilHgQ1x
# 0oYor24msaMI0dRo0xOBukZd6jITQaCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGZEwghmNAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMQ2
# 7Lo8gDo5rxlCMcCXobzm1/770UyC2w1Wk5YiA9O8MEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQCTbDMUoOa+BYvb/eAe9hPQEEgh4CVB6Agm
# +IvN+RUfrlV3fC+Sxe/IFaEiJiTJXGnIeqjv1wTAkkCt32/jYZc8EAW9KlRGl/ck
# jqaw3gTuj+R9PdRvyk4bazYfZWdpQM1cFGlLNVbUKZLZ80Q8x7dcwgKmXUI0GSXF
# 7coPhMY0OVsMwMHdn7Ur9ZgVLM3NqMYDb6PGcoYvp9JFvDW2b8MZbhagCfZEckNm
# ftJklIwEWF8VZR4cc32g4ObkRmUdqnIfN61FoSrl8G06bwWtRe5RBEjEFjRjvUkW
# 6HvlUnxHkWbA17CtDpJdQgyLMXqwqf4DxuDOc/KoyqTAguBO6JDaoYIXGTCCFxUG
# CisGAQQBgjcDAwExghcFMIIXAQYJKoZIhvcNAQcCoIIW8jCCFu4CAQMxDzANBglg
# hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIJMgdv05z5awmUWyQGmKR+aeEnH0a4Pc
# jevqqI463274AgZiF5Wl+RwYEzIwMjIwMzAxMTI1MDE1LjczMlowBIACAfSggdik
# gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UE
# CxMdVGhhbGVzIFRTUyBFU046RDA4Mi00QkZELUVFQkExJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghFoMIIHFDCCBPygAwIBAgITMwAAAY/z
# UajrWnLdzAABAAABjzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDAeFw0yMTEwMjgxOTI3NDZaFw0yMzAxMjYxOTI3NDZaMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOkQwODItNEJGRC1FRUJBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# mVc+/rXPFx6Fk4+CpLrubDrLTa3QuAHRVXuy+zsxXwkogkT0a+XWuBabwHyqj8RR
# iZQQvdvbOq5NRExOeHiaCtkUsQ02ESAe9Cz+loBNtsfCq846u3otWHCJlqkvDrSr
# 7mMBqwcRY7cfhAGfLvlpMSojoAnk7Rej+jcJnYxIeN34F3h9JwANY360oGYCIS7p
# LOosWV+bxug9uiTZYE/XclyYNF6XdzZ/zD/4U5pxT4MZQmzBGvDs+8cDdA/stZfj
# /ry+i0XUYNFPhuqc+UKkwm/XNHB+CDsGQl+ZS0GcbUUun4VPThHJm6mRAwL5y8zp
# tWEIocbTeRSTmZnUa2iYH2EOBV7eCjx0Sdb6kLc1xdFRckDeQGR4J1yFyybuZsUP
# 8x0dOsEEoLQuOhuKlDLQEg7D6ZxmZJnS8B03ewk/SpVLqsb66U2qyF4BwDt1uZkj
# EZ7finIoUgSz4B7fWLYIeO2OCYxIE0XvwsVop9PvTXTZtGPzzmHU753GarKyuM6o
# a/qaTzYvrAfUb7KYhvVQKxGUPkL9+eKiM7G0qenJCFrXzZPwRWoccAR33PhNEuuz
# zKZFJ4DeaTCLg/8uK0Q4QjFRef5n4H+2KQIEibZ7zIeBX3jgsrICbzzSm0QX3SRV
# mZH//Aqp8YxkwcoI1WCBizv84z9eqwRBdQ4HYcNbQMMCAwEAAaOCATYwggEyMB0G
# A1UdDgQWBBTzBuZ0a65JzuKhzoWb25f7NyNxvDAfBgNVHSMEGDAWgBSfpxVdAF5i
# XYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQDNf9Oo9zyhC5n1jC8i
# U7NJY39FizjhxZwJbJY/Ytwn63plMlTSaBperan566fuRojGJSv3EwZs+RruOU2T
# /ZRDx4VHesLHtclE8GmMM1qTMaZPL8I2FrRmf5Oop4GqcxNdNECBClVZmn0KzFdP
# MqRa5/0R6CmgqJh0muvImikgHubvohsavPEyyHQa94HD4/LNKd/YIaCKKPz9SA5f
# Aa4phQ4Evz2auY9SUluId5MK9H5cjWVwBxCvYAD+1CW9z7GshJlNjqBvWtKO6J0A
# emfg6z28g7qc7G/tCtrlH4/y27y+stuwWXNvwdsSd1lvB4M63AuMl9Yp6au/XFkn
# GzJPF6n/uWR6JhQvzh40ILgeThLmYhf8z+aDb4r2OBLG1P2B6aCTW2YQkt7TpUnz
# I0cKGr213CbKtGk/OOIHSsDOxasmeGJ+FiUJCiV15wh3aZT/VT/PkL9E4hDBAwGt
# 49G88gSCO0x9jfdDZWdWGbELXlSmA3EP4eTYq7RrolY04G8fGtF0pzuZu43A29za
# I9lIr5ulKRz8EoQHU6cu0PxUw0B9H8cAkvQxaMumRZ/4fCbqNb4TcPkPcWOI24QY
# lvpbtT9p31flYElmc5wjGplAky/nkJcT0HZENXenxWtPvt4gcoqppeJPA3S/1D57
# KL3667epIr0yV290E2otZbAW8DCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
# AAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX
# 9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1q
# UoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8d
# q6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byN
# pOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
# rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
# Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgS
# Uei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8
# QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6Cm
# gyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzF
# ER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQID
# AQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQU
# KqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0
# bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwU
# tj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN
# 3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU
# 5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5
# KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGy
# qVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
# 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
# AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFp
# AUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcd
# FYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRb
# atGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQd
# VTNYs6FwZvKhggLXMIICQAIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RDA4
# Mi00QkZELUVFQkExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2WiIwoBATAHBgUrDgMCGgMVAD5NL4IEdudIBwdGoCaV0WBbQZpqoIGDMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDl
# yAKRMCIYDzIwMjIwMzAxMTAyNTIxWhgPMjAyMjAzMDIxMDI1MjFaMHcwPQYKKwYB
# BAGEWQoEATEvMC0wCgIFAOXIApECAQAwCgIBAAICDiYCAf8wBwIBAAICEokwCgIF
# AOXJVBECAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQAC
# AwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQCi7/Qgy5RIzO5k/Kcz
# 17kx4jdq1rzyZz7Hxr5ulFxvtpeZeUFa51JrYmyNduSeE9boJEiHTkA5+hNs3ysx
# x0dEQmjwIi9OqdqRJ9uy9orTzjjSpaepRMeLC7Vq59n/KQ/G1q/GoHAGjb0+eFZl
# c+64YhBxVZ40o4Be+oquKEiGUzGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAABj/NRqOtact3MAAEAAAGPMA0GCWCGSAFlAwQC
# AQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkE
# MSIEIBvmh7i4nW0LszG2yDWU6uA/OZJlxvn7XaV1C57ciOqiMIH6BgsqhkiG9w0B
# CRACLzGB6jCB5zCB5DCBvQQgl3IFT+LGxguVjiKm22ItmO6dFDWW8nShu6O6g8yF
# xx8wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAY/z
# UajrWnLdzAABAAABjzAiBCDSqiy1zjSAKJFMNkkBPZs9eTsF8tzk3Nrr2PIWPi2e
# 8zANBgkqhkiG9w0BAQsFAASCAgBMHEVvepxvD9wzPPhisw6AkuO2yP+wdXlqYAnm
# RVaSirOO5RrsputPONHu6QW3pbHpdmpQbTt4Jfuch4lUt+6bLqY2Zdi2RoGo1Ayl
# Im+vqNO5SJ/I489WjzaKJ82fWMZDcz+hEpa1xu1DIowKDUvjUitAdyY2yWAyqC1V
# NAyXFLuYkvIpXHiyMJK9+dFpXQydeqxUQ7MOvrf06eIjzTnXpyDvtHx/hlWnqIZH
# FNXCrN1cN5hksJXAGrpJdSucV0CNr+qkNj3N0oYAp5TCh+xrjGUkYP++dGDuksgH
# vz+4fFMl6zpkrJ5h6wAMJZD+P24N3B4FYYC8PlSplDZckExCJzYKUytNl2T1P7WB
# YCkD2x7qrFqYJ2BzS6ZvgW6H9O06OBIKAb1adfzPdrrdhfCOyh9u64dOAlSlOu8a
# wveW8+VZxKyPhfcfh9bWIpebpx/ZsCG+f00+5v8ltYL+XfQ3V/lMVj7fTwPwzCrR
# YN7NSb2O1ohUtYFpv93RYS2woQ7eMJwWV9qgEPS3kqBRnqAlsORKOf50ohBs98y1
# pS4oL/5f5hfCRnsze/rfJPysfO0J2noyb7ZsNBvRluvHRKiL4aC/rku4II3MNfrj
# qiyeg50LyCVjzQMigHyAxA3tBXCXfEdGbbN+CsQyvqpXnrRQOtydiC1xt5d3N9zy
# NndJuQ==
# SIG # End signature block
