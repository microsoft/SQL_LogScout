param
(
    #servername\instnacename is an optional parameter
    [Parameter(Position=0)]
    [string] $ServerName = $env:COMPUTERNAME,
    
    [Parameter(Position=1,Mandatory=$true)]
    [string] $Scenarios = "WRONG_SCENARIO",

    [Parameter(Position=2,Mandatory=$true)]
    [string] $OutputFilename,

    [Parameter(Position=3)]
    [string] $SqlNexusPath,

    [Parameter(Position=4)]
    [string] $SqlNexusDb,

    [Parameter(Position=5)]
    [string] $LogScoutOutputFolder,

    [Parameter(Position=6, Mandatory=$true)]
    [string] $SQLLogScoutRootFolder
)

function GetBasisExclusionsInclusions ([ref] $RetExclusion)
{
    # use a parameter by reference to populate what the caller passed in

    if ($true -eq (CheckLogsForString  -TextToFind "Will not collect SQLAssessmentAPI"))
    {
        $RetExclusion.Value += "BasicAssessmentAPIExclusion"
    }
}
function GetExclusionsInclusions #returns an array of exclusions not just one
{
    
     [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Scenario
    )

    [string[]] $RetExclusions = @()

    # get the basic exclusions/inclusions which apply to all scenarios tested
    GetBasisExclusionsInclusions -RetExclusion ([ref] $RetExclusions)

    switch ($Scenario) 
    {
        # if there are exceptions for more scenarios in the future, use these
        "Basic"  
        {
            # just a placeholder for now

        }
        "Replication" 
        {
            # get the basic exclusions/inclusions

            if ($false -eq (CheckLogsForString  -TextToFind "Collecting Replication Metadata"))
            {
                $RetExclusions += "ReplMetaData"
            }
        }
        "AlwaysOn"
        {
            # get the basic exclusions/inclusions

            if ($true -eq (CheckLogsForString -TextToFind "HADR is off, skipping data movement and AG Topology" ))
            {
                $RetExclusions += "NoAlwaysOn"
            }
        }
        "NeverEndingQuery"
        {
            # get the basic exclusions/inclusions

            if ($true -eq (CheckLogsForString -TextToFind "NeverEndingQuery Exit without collection"))
            {
                $RetExclusions += "NoNeverEndingQuery"

            }
        }
        "Setup"
        {

            if ($true -eq (CheckLogsForString -TextToFind "No missing MSI/MSP files found"))
            {
                $RetExclusions += "NoMissingMSI"
            }
        }

        default
        {
            Write-Host "No exclusions/inclusions will be applied."
        }
    }

    return $RetExclusions
}

function CheckLogsForString()
{
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string] $TextToFind
    )

    #Search the default log first as there less records than debug log.
    if (Select-String -Path $global:SQLLogScoutLog -Pattern $TextToFind)
    {
        return $true
    }
    #If we didn't find in default log, then check debug log for the provided string.
    elseif (Select-String -Path $global:SQLLogScoutDebugLog -Pattern $TextToFind)
    {
        return $true
    }
    #We didn't find the provided text 
    else
    {
        Write-Output "No ##SQLLogScout logs contains the string provided" | Out-File $global:ReportFileSQLNexus -Append
    }
    
    return $false
}


try 
{
    $return_val = $true
    $testingFolder = $SQLLogScoutRootFolder + "\Bin\TestingInfrastructure\"
    $global:ReportFileSQLNexus = $testingFolder + "output\" + (Get-Date).ToString('yyyyMMddhhmmss') + '_'+ $Scenarios +'_SQLNexusOutput.txt'
    $out_string = "SQLNexus '$Scenarios' scenario test:"
    $global:SQLLogScoutLog = $LogScoutOutputFolder + "\internal\##SQLLOGSCOUT.LOG"
    $global:SQLLogScoutDebugLog = $LogScoutOutputFolder + "\internal\##SQLLOGSCOUT_DEBUG.LOG"


    #if SQLNexus.exe path is provided we run the test
    if ($SqlNexusPath -ne "")
    {
        #check if multiple scenarios are provided and exit if so
        if ($Scenarios.Split("+").Count -gt 1)
        {
            $out_string = ($out_string + " "*(60 - $out_string.Length) + "FAILED!!! SQLNexus_Test does not support multiple scenarios (only single scenario).")
            Write-Output $out_string | Out-File $OutputFilename -Append
            return $false
        }

        $sqlnexus_imp_msg =  "Importing logs in SQL database '$SqlNexusDb' using SQLNexus.exe"
        Write-Host $sqlnexus_imp_msg

        Write-Host "SQL LogScout assumes you have already downloaded SQLNexus.exe. If not, please download it here -> https://github.com/Microsoft/SqlNexus/releases "

        $executable = ($SqlNexusPath + "\sqlnexus.exe")
        
        if (Test-Path -Path ($executable))
        {
            $sqlnexus_version = (Get-Item $executable).VersionInfo.ProductVersion
            $sqlnexus_found = "SQLNexus.exe v$sqlnexus_version found. Executing test..."
            Write-Host $sqlnexus_found


            #launch SQLNexus  and wait for it to finish processing -Wait before continuing
            $argument_list = "/S" + '"'+ $ServerName +'"' + " /D" + '"'+ $SqlNexusDb +'"'  + " /E" + " /I" + '"'+ $LogScoutOutputFolder +'"' + " /Q /N"
            
            Write-Host "Starting SQLNexus.exe import process...$executable $argument_list"
            Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait 
            
            # in the future we can enable verbose logging again if needed to dump entire SQL Nexus output
            if ($VerboseDebugParam)
            {
                Get-Content -Path "$env:TEMP\sqlnexus.*.log" | Out-Host
            }
            
            # check the tables in SQL Nexus-created database and report if some were not imported
            $sqlnexus_scripts = $testingFolder + "sqlnexus_tablecheck_proc.sql" 


            #create the stored procedure
            $executable  = "sqlcmd.exe"
            $argument_list = "-S" + '"'+ $ServerName +'"' + " -d" + '"'+ $SqlNexusDb +'"'  + " -E -Hsqllogscout_sqlnexustest -w8000 -N -C" + " -i" + '"'+ $sqlnexus_scripts +'"' 
            Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait

            # check for any exception/exclusion situations, exclusionTag -> exclusionTags (et1,et2,...)
            $ExclusionTags = GetExclusionsInclusions -Scenario $Scenarios


            # normalize the ExclusionTags parameter to always be an array
            if ($null -eq $ExclusionTags) {
                $ExclusionTags = @()
            } elseif ($ExclusionTags -isnot [System.Array]) {
                $ExclusionTags = @($ExclusionTags)
            }

            # convert the array to JSON (PS v4 and v5 compatible)
            $tagsJson = ConvertTo-Json -InputObject $ExclusionTags -Depth 1 -Compress
                
            Write-Host "Using the following exclusion tags for scenario '$Scenarios': $tagsJson"

            # # Parameterized ADO.NET call 
            $connectionString = "Server=$ServerName;Database=$SqlNexusDb;Integrated Security=True;TrustServerCertificate=True;"


            # call the stored procedure proc_SqlNexusTableValidation using ADO

            $cn  = New-Object System.Data.SqlClient.SqlConnection ($connectionString)
            $cmd = $cn.CreateCommand()
            $cmd.CommandText = "tempdb.dbo.proc_SqlNexusTableValidation"
            $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
            
            $pScenario = $cmd.Parameters.Add("ScenarioName",  [System.Data.SqlDbType]::VarChar, 100); 
            $pScenario.Value   = $Scenarios

            $pDb = $cmd.Parameters.Add("DatabaseName",        [System.Data.SqlDbType]::NVarChar, 128); 
            $pDb.Value     = $SqlNexusDb
            
            $pExclusionTag = $cmd.Parameters.Add("ExclusionTagsJson",   [System.Data.SqlDbType]::NVarChar, -1 ); 
            $pExclusionTag.Value   = $tagsJson

            
            # capture RETURN value
            $retParam = $cmd.Parameters.Add('@RETURN_VALUE', [System.Data.SqlDbType]::Int)
            $retParam.Direction = [System.Data.ParameterDirection]::ReturnValue

            $cn.Open()

            # format and output any missing tables
            $dbname_pad = 20 
            $table_pad = 80 
            $present_pad = 10 

            # prepare header lines
            $tbl_header = "DBName".PadRight($dbname_pad) + "TableName".PadRight($table_pad) + "Present".PadRight($present_pad)
            $tbl_line = "-" * ($dbname_pad-1) + " " + "-"*($table_pad-1) + " " + "-"*$present_pad

            Write-Output $tbl_header | Out-File $global:ReportFileSQLNexus -Append
            Write-Output $tbl_line | Out-File $global:ReportFileSQLNexus -Append

            # execute the command to get the missing tables if any
            $reader = $cmd.ExecuteReader()
            
            # read each missing table row
            while ($reader.Read()) 
            {

                $missingTable = $reader["DBName"].PadRight($dbname_pad) +
                                ($reader["SchemaName"] + "." + $reader["TableName"]).PadRight($table_pad) + 
                                $reader["Present"].PadRight($present_pad) 

                Write-Output $missingTable | Out-File $global:ReportFileSQLNexus -Append


            }

            $reader.Close()

            
            # get the return value from the stored procedure
            $procRetValue = [int]$retParam.Value

            $cn.Close()

            Write-Host "Return value from proc_SqlNexusTableValidation: $procRetValue"

            # interpret the return value
            if ($procRetValue -eq 1001001)
            {
                $out_string = ($out_string + " "*(60 - $out_string.Length) + "SUCCESS ")
            }
            elseif ($procRetValue -eq 2002002) 
            {
                $out_string = ($out_string + " "*(60 - $out_string.Length) + "FAILED!!! (Found missing tables; see '$global:ReportFileSQLNexus')")
                $return_val = $false
            }
            else {
                $out_string = ($out_string + " "*(60 - $out_string.Length) + "FAILED!!! Query/script failure of some kind. Return value = '$procRetValue' ")
                $return_val = $false
            }

            # write the return value to the report file
            Write-Output "`n`rProc_return_value`n-------------------`n$procRetValue `n"| Out-File $global:ReportFileSQLNexus -Append

            # write the result to the console
            Write-Host $out_string

            # write the summary line to the Summary output file
            Write-Output $out_string | Out-File $OutputFilename -Append
  


            #clean up stored procedure

            $sqlnexus_query = "DROP PROCEDURE dbo.proc_SqlNexusTableValidation; DROP PROCEDURE proc_ExclusionsInclusions" 
            $executable  = "sqlcmd.exe"
            $argument_list3 = "-S" + '"'+ $ServerName +'"' + " -d`"tempdb`" -N -C -E -Hsqllogscout_cleanup -w8000" + " -Q" + '"'+ $sqlnexus_query +'"'  
            Start-Process -FilePath $executable -ArgumentList $argument_list3 -WindowStyle Hidden 

        }
        else
        {
            $missing_sqlnexus_err = "The SQLNexus directory '$SqlNexusPath' is invalid or SQLNexus.exe is not present in it." 

            #write to detailed file
            Write-Host $missing_sqlnexus_err -ForegroundColor Red
            Write-Output $missing_sqlnexus_err | Out-File $global:ReportFileSQLNexus -Append

            # write out to the summary file
            $out_string = ($out_string + " "*(60 - $out_string.Length) + "FAILED!!! SQLNexus.exe not found. See '$global:ReportFileSQLNexus'")
            Write-Output $out_string | Out-File $OutputFilename -Append
            $return_val = $false
        }

        #append several message to the datetime_scenario_SQLNexusOutput.txt file
        $storedproc_results = Get-Content -Path  $global:ReportFileSQLNexus
        Set-Content -Path  $global:ReportFileSQLNexus -Value $sqlnexus_imp_msg
        Add-Content -Path  $global:ReportFileSQLNexus -Value $sqlnexus_found
        Add-Content -Path  $global:ReportFileSQLNexus -Value ""
        Add-Content -Path $global:ReportFileSQLNexus -Value $storedproc_results
    }

    # if some error occurred, print the report file to the console (for debugging purposes)
    if ($return_val -eq $false)
    {   Write-Host "Printing detailed SQLNexus test output '$global:ReportFileSQLNexus':`n"
        Get-Content -Path $global:ReportFileSQLNexus | Out-Host
    }

    return $return_val

}
catch 
{
    $mycommand = $MyInvocation.MyCommand
    $error_msg = $PSItem.Exception.Message
    Write-Host $_.Exception.Message
    $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
    $error_offset = $PSItem.InvocationInfo.OffsetInLine
    Write-Host "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
    return $false
}
try {
    
}
finally 
{
    if (($null -ne $cn) -and ($cn.State -eq 'Open'))
    {
        $cn.Close()
    }
}

# SIG # Begin signature block
# MIIsDwYJKoZIhvcNAQcCoIIsADCCK/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC0mAgpScIniFsF
# BEOL1iXWJN3L3GzvKeRGHPmjgfzWZKCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIO09niBTVfkT
# j2lpJ8D+mmrTv3WgP0hLewYtTERGFyYkMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAQWNDZMOIfCicKjBJ+oGWPcoViOaCyBZfPjrIpdT4M9jX
# hVqzF0+wzDiy8ZWT4V2Du6C68A//+f8k2y81hEeMleYawnGN92q5kZeHrurrag/r
# pejEPIiXMdqEglEmTmXwFdVwCUXjlEdp6U8mlhpYOwiAPxyaFLxF0l4Od40LcEkG
# rzd+YgO6Ijf8EEx04CoyUmnByHevq9Pz+GNUwoZrwz7EI9hqpztaR1pdiNjg3ws9
# PPtX59BJaNPqlDyBP0pXqYf3qWi1bcmP2Q3vfWZMhIVIkWJq7y9sSrJ0cBLRZEQM
# MVPUIJKhxF/q2cVuIKivXguhKoZFfqE5D38+IG4x3qGCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCCuejSlDf2F5RR7e8BVUROpi9DrEa2OHRuxTUPRiIJz
# kAIGaXN6/dgwGBMyMDI2MDIwNDE2MzUyOC41NTFaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACGqmgHQagD0Oq
# AAEAAAIaMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgyOFoXDTI2MTExMzE4NDgyOFowgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjMyMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAmYEAwSTz
# 79q2V3ZWzQ5Ev7RKgadQtMBy7+V3XQ8R0NL8R9mupxcqJQ/KPeZGJTER+9Qq/t7H
# OQfBbDy6e0TepvBFV/RY3w+LOPMKn0Uoh2/8IvdSbJ8qAWRVoz2S9VrJzZpB8/f5
# rQcRETgX/t8N66D2JlEXv4fZQB7XzcJMXr1puhuXbOt9RYEyN1Q3Z7YjRkhfBsRc
# +SD/C9F4iwZqfQgo82GG4wguIhjJU7+XMfrv4vxAFNVg3mn1PoMWGZWio+e14+PG
# YPVLKlad+0IhdHK5AgPyXKkqAhEZpYhYYVEItHOOvqrwukxVAJXMvWA3GatWkRZn
# 33WDJVtghCW6XPLi1cDKiGE5UcXZSV4OjQIUB8vp2LUMRXud5I49FIBcE9nT00z8
# A+EekrPM+OAk07aDfwZbdmZ56j7ub5fNDLf8yIb8QxZ8Mr4RwWy/czBuV5rkWQQ+
# msjJ5AKtYZxJdnaZehUgUNArU/u36SH1eXKMQGRXr/xeKFGI8vvv5Jl1knZ8UqEQ
# r9PxDbis7OXp2WSMK5lLGdYVH8VownYF3sbOiRkx5Q5GaEyTehOQp2SfdbsJZlg0
# SXmHphGnoW1/gQ/5P6BgSq4PAWIZaDJj6AvLLCdbURgR5apNQQed2zYUgUbjACA/
# TomA8Ll7Arrv2oZGiUO5Vdi4xxtA3BRTQTUCAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBTwqyIJ3QMoPasDcGdGovbaY8IlNjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# 1a72WFq7B6bJT3VOJ21nnToPJ9O/q51bw1bhPfQy67uy+f8x8akipzNL2k5b6mtx
# uPbZGpBqpBKguDwQmxVpX8cGmafeo3wGr4a8Yk6Sy09tEh/Nwwlsyq7BRrJNn6bG
# OB8iG4OTy+pmMUh7FejNPRgvgeo/OPytm4NNrMMg98UVlrZxGNOYsifpRJFg5jE/
# Yu6lqFa1lTm9cHuPYxWa2oEwC0sEAsTFb69iKpN0sO19xBZCr0h5ClU9Pgo6ekiJ
# b7QJoDzrDoPQHwbNA87Cto7TLuphj0m9l/I70gLjEq53SHjuURzwpmNxdm18Qg+r
# lkaMC6Y2KukOfJ7oCSu9vcNGQM+inl9gsNgirZ6yJk9VsXEsoTtoR7fMNU6Py6uf
# JQGMTmq6ZCq2eIGOXWMBb79ZF6tiKTa4qami3US0mTY41J129XmAglVy+ujSZkHu
# 2lHJDRHs7FjnIXZVUE5pl6yUIl23jG50fRTLQcStdwY/LvJUgEHCIzjvlLTqLt6J
# VR5bcs5aN4Dh0YPG95B9iDMZrq4rli5SnGNWev5LLsDY1fbrK6uVpD+psvSLsNph
# t27QcHRsYdAMALXM+HNsz2LZ8xiOfwt6rOsVWXoiHV86/TeMy5TZFUl7qB59INoM
# SJgDRladVXeT9fwOuirFIoqgjKGk3vO2bELrYMN0QVwwggdxMIIFWaADAgECAhMz
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
# bGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA8YrutmKpSrubCaAYsU4p
# t1Ft8DaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0tyqswIhgPMjAyNjAyMDQxMzM5NTVaGA8yMDI2MDIwNTEz
# Mzk1NVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7S3KqwIBADAKAgEAAgIJhgIB
# /zAHAgEAAgISNTAKAgUA7S8cKwIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IB
# AQAnWQjJDCou2kYISBh+PBIVXV8fiYJ+DrpZ/Zl1q4/7Gs7lx2Z8VKQAmrqbW0UM
# SAlvQB28TGRH1exjKw/0KwpqZloU6HDUwzDA8Wkkk+GUePRckHGLlIXPNLzT+v9B
# WsvVaOT76tT696cdZyGX+kXHc+XpO1nh+FvVhEyuFlZQsQYFmZbhKci7VjuxzeQp
# EvZxEsSMDbwMJcdWLsRQAeOFxAREJrRWdaNdwta7YCBw4DTs/DzzMiLJHN1y7JMw
# c32FoVrdQqLIGGQJBtkiacnoh1757aXtEtpk23ukaknev1wUwiHrCG44WI5/98ub
# SDMP6i8DS31uXR9nsRcT0pMLMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIaqaAdBqAPQ6oAAQAAAhowDQYJYIZIAWUDBAIB
# BQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgQeyYJFgO6pGclt16IGyQsmBX4KSWb3iHI8uum4DX5zswgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCCdeiHHrbtpKcwB20doVU89WHIOH8S7w37uaHcDmemK
# +zCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACGqmg
# HQagD0OqAAEAAAIaMCIEIJVwLrYvifI5rx962RJ5kSi3edcltLMXKHZFI7c4QKNL
# MA0GCSqGSIb3DQEBCwUABIICAEEgtB7nOF2CRaOh7FEMnutKv48frZbgzmAaozeP
# qPl4V9EU0aV339UQN34IA8MID5kba/09l6ZDmL1T5dCFfsdM/VxrqwQw/PMKarWO
# FfYXM8s9YlZb6LBmM/OG/1EZR+A4YYmgCpWljfP1LN7O4tC+5gbfsXdG4kJH9fzF
# u+k+13ic7p8lIxxJvOyDvhyAz71mjyN4dLAUN/DqkIW7VAK+8yVoG4TqoVAZCt5t
# Wj7Cg+tx4lpnm5gTz8lG+odgp2G7RkJaFybMBDfMQQv3Q3yXQ3N2VRWal0MFynM9
# Ifrr34XMWQzQn92h9tRTFqUaQIG/mbnN/ZIp9TsvxU73D+tzjbKBJAOkMOtOuYJ0
# b3CjI1II7EuNlIP0vthUGbsjtZSkKS0ylDSpvUk6TQkCfJNUNaD1WH4QQVQHV0XV
# d4SknWyAWGIsTpZb+YDkIVvbpRg+/9EDnJ4G0dlE2xNdwf33bSQi1dSwD9Gc4Ch2
# pEV9opppb9FHRCtG7BqZzZRe5hO+VTem6wFeO7vW0Q9WqmOOyjZuu1CrCrKpPJRz
# hjlwWmrFov4n7reGr1VDyBg0CR58KuP1+x9vzMJW9zGNfvpNdiAT2kOrH7fcotRn
# wDRZy1ukyl5IbOhgNwSiY32e94H/5ldpF/RasIXDJU0f7W605rVWhfUt4lN6cxW2
# mX5P
# SIG # End signature block
