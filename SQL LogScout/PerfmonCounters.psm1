
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
        if ($instance_name -eq $host_name)
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
            Copy-Item -Path $perfmonCounterFile -Destination $destinationPerfmonCounterFile -ErrorAction Stop
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
# SIG # Begin signature block
# MIInvQYJKoZIhvcNAQcCoIInrjCCJ6oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD0auy4GqsfNDPJ
# cAcF+rbGDN6PionbyIGwZ7sZFoZjmaCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGY4wghmKAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIIjB
# RAFu1qXgj2ivazdfPZIcPdB4RDOx0+LcgKpWAwZrMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQAYGlMJL2UZftA9WjtUkIScCqX4jWDIoz9r
# 1stie781x03bqDk032NYowLICc+qDL6mYJ6efSBRnjB/1OecvfS2Zx559xYZNGLk
# rA6FrwKsrvVf2X59Mxyd+WkZ0p33Ay3klBOab1IjoolfH2PiUPj0flbmMbxjObjO
# q3XpkuKpJlb2/C5dnwDsPwGv08V3s8r3ZGDn81oUxTpQ00/webntRZ4ljRKutmzN
# czXZloaiErZOWgdOCZYlMNxA7itvZDgudhsOP+BQUR4F9WwkE9gZAwm74OzRcnfk
# /XD/wQTHmmvpsGFaBGkPyS293rxWhxxT402KgZ4M0U6rCQyVHoQ7oYIXFjCCFxIG
# CisGAQQBgjcDAwExghcCMIIW/gYJKoZIhvcNAQcCoIIW7zCCFusCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIAQ+7TmcxSpkyX684gyNxPagKTivrPE4
# BRcGDvLNLMUKAgZiCKzlX14YEzIwMjIwMzAxMTI1MDIzLjk3OVowBIACAfSggdik
# gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UE
# CxMdVGhhbGVzIFRTUyBFU046ODZERi00QkJDLTkzMzUxJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghFlMIIHFDCCBPygAwIBAgITMwAAAYwB
# l2JHNnZmOwABAAABjDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDAeFw0yMTEwMjgxOTI3NDRaFw0yMzAxMjYxOTI3NDRaMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjg2REYtNEJCQy05MzM1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 00hoTKET+SGsayw+9BFdm+uZ+kvEPGLd5sF8XlT3Uy4YGqT86+Dr8G3k6q/lRagi
# xRKvn+g2AFRL9VuZqC1uTva7dZN9ChiotHHFmyyQZPalXdJTC8nKIrbgTMXAwh/m
# bhnmoaxsI9jGlivYgi5GNOE7u6TV4UOtnVP8iohTUfNMKhZaJdzmWDjhWC7LjPXI
# ham9QhRkVzrkxfJKc59AsaGD3PviRkgHoGxfpdWHPPaW8iiEHjc4PDmCKluW3J+I
# dU38H+MkKPmekC7GtRTLXKBCuWKXS8TjZY/wkNczWNEo+l5J3OZdHeVigxpzCnes
# kZfcHXxrCX2hue7qJvWrksFStkZbOG7IYmafYMQrZGull72PnS1oIdQdYnR5/ngc
# vSQb11GQ0kNMDziKsSd+5ifUaYbJLZ0XExNV4qLXCS65Dj+8FygCjtNvkDiB5Hs9
# I7K9zxZsUb7fKKSGEZ9yA0JgTWbcAPCYPtuAHVJ8UKaT967pJm7+r3hgce38VU39
# speeHHgaCS4vXrelTLiUMAl0Otk5ncKQKc2kGnvuwP2RCS3kEEFAxonwLn8pyedy
# reZTbBMQBqf1o3kj0ilOJ7/f/P3c1rnaYO01GDJomv7otpb5z+1hrSoIs8u+6eru
# JKCTihd0i/8bc67AKF76wpWuvW9BhbUMTsWkww4r42cCAwEAAaOCATYwggEyMB0G
# A1UdDgQWBBSWzlOGqYIhYIh5Vp0+iMrdQItSIzAfBgNVHSMEGDAWgBSfpxVdAF5i
# XYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQDXaMVFWMIJqdblQZK6
# oks7cdCUwePAmmEIedsyusgUMIQlQqajfCP9iG58yOFSRx2k59j2hABSZBxFmbkV
# jwhYEC1yJPQm9464gUz5G+uOW51i8ueeeB3h2i+DmoWNKNSulINyfSGgW6PCDCiR
# qO3qn8KYVzLzoemfPir/UVx5CAgVcEDAMtxbRrTHXBABXyCa6aQ3+jukWB5aQzLw
# 6qhHhz7HIOU9q/Q9Y2NnVBKPfzIlwPjb2NrQGfQnXTssfFD98OpRHq07ZUx21g4p
# s8V33hSSkJ2uDwhtp5VtFGnF+AxzFBlCvc33LPTmXsczly6+yQgARwmNHeNA262W
# qLLJM84Iz8OS1VfE1N6yYCkLjg81+zGXsjvMGmjBliyxZwXWGWJmsovB6T6h1Grf
# mvMKudOE92D67SR3zT3DdA5JwL9TAzX8Uhi0aGYtn5uNUDFbxIozIRMpLVpP/YOL
# ng+r2v8s8lyWv0afjwZYHBJ64MWVNxHcaNtjzkYtQjdZ5bhyka6dX+DtQD9bh3zj
# i0SlrfVDILxEb6OjyqtfGj7iWZvJrb4AqIVgHQaDzguixES9ietFikHff6p97C5q
# obTTbKwN0AEP3q5teyI9NIOVlJl0gi5Ibd58Hif3JLO6vp+5yHXjoSL/MlhFmvGt
# aYmQwD7KzTm9uADF4BzP/mx2vzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# VTNYs6FwZvKhggLUMIICPQIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046ODZE
# Ri00QkJDLTkzMzUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2WiIwoBATAHBgUrDgMCGgMVADSi8hTrq/Q8oppweGyuZLNEJq/VoIGDMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDl
# yEKPMCIYDzIwMjIwMzAxMTQ1ODIzWhgPMjAyMjAzMDIxNDU4MjNaMHQwOgYKKwYB
# BAGEWQoEATEsMCowCgIFAOXIQo8CAQAwBwIBAAICEVIwBwIBAAICET0wCgIFAOXJ
# lA8CAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAweh
# IKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQBi+5XMdtqAHwccI/0hOCQB
# gH3GaBwc/rayKALDUF1INCVdE1cIW63mKkQwvmHmuqp7k6+Nv3OGeQiiNzGGo4Xw
# X9KNXsp9jxHTUbhSQBcTFQoPWGkPg12VECVpoq7F2sqSH6z77BvhgIbxzAOK3AfP
# qJCc5m8l3eUGilQBx3w6DDGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAABjAGXYkc2dmY7AAEAAAGMMA0GCWCGSAFlAwQCAQUA
# oIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIE
# IMbKFbPqQeKqkPVOzx1MPkR76lnqfLiglG58DLGUp67bMIH6BgsqhkiG9w0BCRAC
# LzGB6jCB5zCB5DCBvQQg1a2L+BUqkM8Gf8TmIQWdgeKTTrYXIwOofOuJiBiYaZ4w
# gZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAYwBl2JH
# NnZmOwABAAABjDAiBCBNlUx5c5VGUitqq4K6lo3v3VKS0jyFzTGb6pAcAmYkzzAN
# BgkqhkiG9w0BAQsFAASCAgB90DI6N7r12ZHX8Y/mHzL/puKryINSeNK9/b9/of6e
# YPZcKASROD+ps7JTCzynR4vp6sE9PLU9SgpYTEaZunwkZ9i6wVmUtWgEcWS5AwAS
# zuwgKxrSkcU1j1Q+hv54e1y7RZCrZw5Kr8xnT3SlHC4O6EmENPX13uoRgV8ro8v8
# 44zKzobDozP19thW22BpbyAo6R/m1mLhfINBMnAqJ9vupV5SOrvxZZ66puVlqgpr
# Jg9lSgIY4OUWw1o0w1hewZjwg2WH91fNfdAPWzi2op0r8js4CpN07kZBsH1I3i7J
# dNR4NE3r0LnDw8iCpjGdm7xinyhH/ZhybcjG2rb2DadEeldLaf0k3kHOn6bqCI/r
# J7zTk2fdrKHOwVid7NedeS+LhJ8xOWKJL4QtNkXhRHHAbDE9NeLa2PElRe4mfqxL
# YGcyq0hlVqSJaydAFz9T4RT8UoXiLykXlkT1uxt++4Br0vaUP/OZ9Oo9jQ0kPzgi
# ETgt5zzKJk2Mi1D/gKbOTvEt8nZ+pjTgSsBrQq7prgzqJbwPEGBCUpXaKC2NgdVY
# UvCSAfdNwenJT8f2YEdLAnfX72rLYjZohCmOlEhF7Zvzc5sQN2NipEajhNwlW8UL
# H3cSLKYok63g47sFUgV6rkjOie2i09my+yiu8e7Sit4xnSDOSOhAHfNZ0TiGoHkk
# kA==
# SIG # End signature block
