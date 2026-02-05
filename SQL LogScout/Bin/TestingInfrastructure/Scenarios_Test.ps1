param
(
    #servername\instancename is an optional parameter
    [Parameter(Position=0)]
    [string] $ServerName = $env:COMPUTERNAME,
    
    [Parameter(Position=1,Mandatory=$true)]
    [string] $Scenarios = "WRONG_SCENARIO",

    [Parameter(Position=2,Mandatory=$true)]
    [string] $SummaryOutputFile,

    [Parameter(Position=3)]
    [string] $SqlNexusPath,

    [Parameter(Position=4)]
    [string] $SqlNexusDb,

    [Parameter(Position=5)]
    [string] $LogScoutOutputFolder,

    [Parameter(Position=6,Mandatory=$true)]
    [string] $RootFolder,

    [Parameter(Position=7)]
    [bool] $RunTSQLLoad = $false,

    [Parameter(Position=8)]
    [bool] $UseRelativeStartStopTime = $false,

    [Parameter(Position=9,Mandatory=$false)]
    [int] $RepeatCollections = 0,

    [Parameter(Position=10)]
    [double] $RunDuration = 3,
    
    [Parameter(Position=11)]
    $UseStopFile = $false,

    [Parameter(Position=12)]
    [string] $AdditionalOptionsEnabled = "",

    [Parameter(Position=13)]
    [string[]] $excludePatterns = @()
)


try 
{
    
    $TSQLLoadModule = (Get-Module -Name TSQLLoadModule).Name

    if ($TSQLLoadModule -ne "GenerateTSQLLoad")
    {
        Import-Module -Name .\GenerateTSQLLoad.psm1
    }

    $TSQLLoadCommonFunction = (Get-Module -Name CommonFunctions).Name

    if ($TSQLLoadCommonFunction -ne "CommonFunctions")
    {
        #Since we are in bin and CommonFunctions is in root directory, we need to step out to import module
        #This is so we can use HandleCatchBlock

        [string]$parentLocation =  (Get-Item (Get-Location)).Parent.FullName 
        Import-Module -Name ($parentLocation + "\CommonFunctions.psm1")
    }




    Write-Output "" | Out-File $SummaryOutputFile -Append
    Write-Output "" | Out-File $SummaryOutputFile -Append
    Write-Output "********************************************************************" | Out-File $SummaryOutputFile -Append
    Write-Output "                      Starting '$Scenarios' test                    " | Out-File $SummaryOutputFile -Append     
    Write-Output "                      $(Get-Date -Format "dd MMMM yyyy HH:mm:ss")   " | Out-File $SummaryOutputFile -Append     
    Write-Output "                      Server Name: $ServerName                      " | Out-File $SummaryOutputFile -Append
    Write-Output "********************************************************************" | Out-File $SummaryOutputFile -Append

    Write-Output "********************************************************************" 
    Write-Output "                      Starting '$Scenarios' test"                     
    Write-Output "                      $(Get-Date -Format "dd MMMM yyyy HH:mm:ss")    "
    Write-Output "                      Server Name: $ServerName                      " 
    Write-Output "********************************************************************" 

    [bool] $script_ret = $true
    [int] $return_val = 0

    # validate root folder 
    $PathFound = Test-Path -Path $RootFolder 
    if ($PathFound -eq $false)
    {
        Write-Host "Invalid Root directory for testing. Exiting."
        $return_val = 4
        return $return_val
    }


    if ($UseRelativeStartStopTime -eq $true)
    {
        # build random start and stop time in the format "+HH:mm:ss" where time is less than 2 minutes
        # this is to test the relative start and stop time feature with semi-random times
        $start_sec = Get-Random -Minimum 0 -Maximum 60
        $stop_sec = Get-Random -Minimum 0 -Maximum 60

        $start_min = Get-Random -Minimum 1 -Maximum 3
        $stop_min = Get-Random -Minimum 1 -Maximum 3


        [string]$StartTime = "+00" + ":" + "0" + $start_min.ToString() + ":" + $(if ($start_sec -le 9) {"0" + $start_sec.ToString()} else {$start_sec.ToString()}) 
        [string]$StopTime  = "+00" + ":" + "0" + $stop_min.ToString() + ":" + $(if ($stop_sec -le 9) {"0" + $stop_sec.ToString()} else {$stop_sec.ToString()})  

        Write-Host "Relative Start Time: $StartTime and Relative Stop Time: $StopTime"
    }
    else
    {
        # start and stop times for LogScout execution
        if ($Scenarios -match "NeverEndingQuery"){
            # NeverEndingQuery scenario needs 60 seconds to run before test starts so we can accumulate 60 seconds of CPU time
            $StartTime = (Get-Date).AddSeconds(60).ToString("yyyy-MM-dd HH:mm:ss")
        }
        else {
            $StartTime = (Get-Date).AddSeconds(20).ToString("yyyy-MM-dd HH:mm:ss")
        }

        # stop time is 3 minutes from start time. This is to ensure that we have enough data to analyze 
        # also ensures that on some machines where the test runs longer, we don't lose logs due to the test ending prematurely
        $StopTime = (Get-Date).AddMinutes($RunDuration).ToString("yyyy-MM-dd HH:mm:ss")
    }


    # start TSQLLoad execution
    if ($RunTSQLLoad -eq $true)
    {
        Initialize-TSQLLoadLog -Scenario $Scenarios

        TSQLLoadInsertsAndSelectFunction -ServerName $ServerName
    }


    #if UseStopFile is set, start a job which will create a stop file after the specified time in seconds (RunDuration *60 * 0.60)
    if ($UseStopFile -eq $true)
    {
        Write-Host "Creating stop file for LogScout to stop in $($RunDuration*60*0.60) seconds"
        $StopFile = $RootFolder + "\output\internal\logscout.stop"
        $StopDuration = ($RunDuration * 60) * 0.60 # 60% of the run duration in seconds
        $stop_job = Start-Job  -Name "CreateStopFileJob" -ScriptBlock {
                            param($StopFile, $StopDuration) 
                            Start-Sleep -Seconds $StopDuration; 
                            Set-Content -Value "stop please" -Path $StopFile -Force;
                            
                            if (Test-Path -Path $StopFile)
                            {
                                Microsoft.PowerShell.Utility\Write-Host "The stop file $StopFile was created successfully."
                            }
                            else
                            {
                                Microsoft.PowerShell.Utility\Write-Host "The stop file $StopFile was not created successfully."
                            }
                            #no need to remove the file as it will be deleted when a new test is run
                        } -ArgumentList $StopFile, $StopDuration
    } 

    ##execute a regular SQL LogScout data collection from root folder
    Write-Host "Starting LogScout"

    #build the path to the SQL_LogScout.ps1 script
    [string] $LogScoutCmd =$RootFolder  + "\SQL_LogScout.ps1" 

    #invoke SQL LogScout in a child process
    $arguments = "-File `"$($LogScoutCmd)`" -Scenario `"$($Scenarios)`" -ServerName `"$($ServerName)`" -CustomOutputPath `"UsePresentDir`" -DeleteExistingOrCreateNew `"DeleteDefaultFolder`" -DiagStartTime `"$($StartTime)`" -DiagStopTime `"$($StopTime)`" -InteractivePrompts `"Quiet`" -RepeatCollections $($RepeatCollections.ToString()) -AdditionalOptionsEnabled `"$($AdditionalOptionsEnabled)`" "
    
    Write-Host "Arguments: $arguments"
    Start-Process -FilePath "powershell" -ArgumentList $arguments -Wait -NoNewWindow

    #check if TSQL workload is enabled and if so, check if it has finished
    if ($RunTSQLLoad -eq $true)
    {
        Write-Host "Verifying T-SQL workload finished"
        if ($TSQLLoadModule -ne "GenerateTSQLLoad")
        {
            Import-Module -Name .\GenerateTSQLLoad.psm1
        }

        TSQLLoadCheckWorkloadExited
    }

    #if UseStopFile is set, wait for the job to complete and print the output
    if ($UseStopFile -eq $true)
    {
        # Wait for the job to complete
        Wait-Job -Job $stop_job | Out-Null

        # Retrieve and display the job output
        $jobOutput = Receive-Job -Job $stop_job
        Microsoft.PowerShell.Utility\Write-Host $jobOutput

        # Remove the job
        Remove-Job -Job $stop_job
    }


    #run file validation test

    $script_ret = ./FileCountAndTypeValidation.ps1 -SummaryOutputFile $SummaryOutputFile 2> .\##TestFailures.LOG
    ..\StdErrorOutputHandling.ps1 -FileName .\##TestFailures.LOG

    if ($script_ret -eq $false)
    {
        #FilecountandtypeValidation test failed, return a unique, non-zero value
        $return_val = 1
    }

    #check SQL_LOGSCOUT_DEBUG log for errors
    . .\LogParsing.ps1

    # $LogNamePattern defaults to "..\output\internal\##SQLLOGSCOUT_DEBUG.LOG"
    # $SummaryFilename defaults to ".\output\SUMMARY.TXT"
    # $DetailedFilename defaults to ".\output\DETAILED.TXT"
    $script_ret = Search-Log -LogNamePattern ($RootFolder + "\output\internal\##SQLLOGSCOUT_DEBUG.LOG") -ExcludePatterns $excludePatterns  

    if ($script_ret -eq $false)
    {
        #Search-Log test failed, return a unique, non-zero value
        $return_val = 2
    }

    Write-Host "Params for SQLNexus Test: ServerName=$ServerName, Scenarios=$Scenarios, OutputFilename=$SummaryOutputFile, SqlNexusPath=$SqlNexusPath, SqlNexusDb=$SqlNexusDb, LogScoutOutputFolder=$LogScoutOutputFolder, SQLLogScoutRootFolder=$RootFolder"
    #run SQLNexus import and table verficiation test
    $script_ret = .\SQLNexus_Test.ps1 -ServerName $ServerName -Scenarios $Scenarios -OutputFilename $SummaryOutputFile -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -SQLLogScoutRootFolder $RootFolder


    if ($script_ret -eq $false)
    {
        #SQLNexus test failed, return a non-zero value
        $return_val = 3
    }

    Write-Host "Scenario_Test return value: $return_val" | Out-Null
    return $return_val

}
catch {
    $error_msg = $PSItem.Exception.Message
    $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
    $error_offset = $PSItem.InvocationInfo.OffsetInLine
    $error_script = $PSItem.InvocationInfo.ScriptName
    Write-Error "Function '$($MyInvocation.MyCommand)' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    
    exit 999
}
# SIG # Begin signature block
# MIIr5wYJKoZIhvcNAQcCoIIr2DCCK9QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDStWtbOPtqMtFM
# dnDUnupLe4v/V47PEEIOt7IErgMAYKCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
# D0nu2y38AAIAAAINMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzA5MzBaFw0yNjA0MjYyMzE5MzBaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCpj9ry6z6v08TIeKoxS2+5c928SwYKDXCyPWZHpm3xIHTqBBmlTM1GO7X4
# ap5jj/wroH7TzukJtfLR6Z4rBkjdlocHYJ2qU7ggik1FDeVL1uMnl5fPAB0ETjqt
# rk3Lt2xT27XUoNlKfnFcnmVpIaZ6fnSAi2liEhbHqce5qEJbGwv6FiliSJzkmeTK
# 6YoQQ4jq0kK9ToBGMmRiLKZXTO1SCAa7B4+96EMK3yKIXnBMdnKhWewBsU+t1LHW
# vB8jt8poBYSg5+91Faf9oFDvl5+BFWVbJ9+mYWbOzJ9/ZX1J4yvUoZChaykKGaTl
# k51DUoZymsBuatWbJsGzo0d43gMLAgMBAAGjggWKMIIFhjApBgkrBgEEAYI3FQoE
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
# aG9yaXR5MB0GA1UdDgQWBBS6kl+vZengaA7Cc8nJtd6sYRNA3jAOBgNVHQ8BAf8E
# BAMCB4AwRQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEWMBQGA1UEBRMNMjM2MTY3KzUwNjA0MjCCAeYGA1UdHwSCAd0wggHZMIIB
# 1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpaW5mcmEvQ1JM
# L0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwxLmFtZS5nYmwv
# Y3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwyLmFtZS5n
# YmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwzLmFt
# ZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmw0
# LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGgb1sZGFwOi8v
# L0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQS0lDU0NBMDEsQ049Q0RQ
# LENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZp
# Z3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0
# P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwHwYDVR0jBBgw
# FoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgwFgYKKwYBBAGCN1sBAQYI
# KwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAJKGB9zyDWN/9twAY6qCLnfDCKc/
# PuXoCYI5Snobtv15QHAJwwBJ7mr907EmcwECzMnK2M2auU/OUHjdXYUOG5TV5L7W
# xvf0xBqluWldZjvnv2L4mANIOk18KgcSmlhdVHT8AdehHXSs7NMG2di0cPzY+4Ol
# 2EJ3nw2JSZimBQdRcoZxDjoCGFmHV8lOHpO2wfhacq0T5NK15yQqXEdT+iRivdhd
# i/n26SOuPDa6Y/cCKca3CQloCQ1K6NUzt+P6E8GW+FtvcLza5dAWjJLVvfemwVyl
# JFdnqejZPbYBRdNefyLZjFsRTBaxORl6XG3kiz2t6xeFLLRTJgPPATx1S7Awggjo
# MIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0GCSqGSIb3DQEBCwUAMDwx
# EzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxEDAOBgNV
# BAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYwNTIxMTg1NDE0WjBBMRMw
# EQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQD
# EwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDJ
# mlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL9rNHnHDGfJgeuRIYO1LY
# /1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc411WxA+Pv2rteAcz0eHM
# H36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaCIIWBXyEchv+sM9eKDsUO
# LdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8pXirIYOgM770CYOiZrcKH
# K7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p/6fksgEILptOKhx9c+ia
# piNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkrBgEEAYI3FQEEBQIDAgAC
# MCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMALI38/RzAdBgNVHQ4EFgQU
# llGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfwwgfkGBysGAQUCAwUGCCsG
# AQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYBBAGCNxUGBgorBgEEAYI3
# CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgCAgYKKwYBBAGCN0ABAQYL
# KwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcVBQYKKwYBBAGCNxQCAgYK
# KwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEGCisGAQQBgjdbAgEGCisG
# AQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEGCisGAQQBgjdbBAIwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwNp4x1AdEJCygwggFoBgNV
# HR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDovL2NybDIuYW1lLmdibC9j
# cmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL2FtZXJvb3Qu
# Y3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVyb290LmNybIaBqmxkYXA6
# Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPUFNRSxE
# Qz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNz
# PWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUHAQEEggGdMIIBmTBHBggr
# BgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NlcnRz
# L0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwyLmFt
# ZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6
# Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUH
# MAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQw
# gaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290LENOPUFJQSxDTj1QdWJs
# aWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9u
# LERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29iamVjdENsYXNzPWNl
# cnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQELBQADggIBAFAQI7dPD+jf
# XtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTHb8BDfRN+AD0YEmeDB5HK
# QoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a/752hMIn+L4ZuyxVeSBp
# fwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9zAh9yRKKls2bziPEnxeO
# ZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAmn3WCPWNFC1YTIIHw/mD2
# cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtzyb7fbNS1dE740re0COE6
# 7YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjFK1yMw4Ni5fMabcgmzRvS
# jAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bzMzsikuDW9xH10graZzSm
# PjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIzJ6Q9G3NPCB+7KwX0OQmK
# yv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/ywO6SYSreVW+5Y0mzJutn
# BC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEISRtShDZbuYymynY1un+Ry
# fiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZzzCCGcsCAQEwWDBBMRMwEQYKCZIm
# iZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQDEwxBTUUg
# Q1MgQ0EgMDECEzYAAAIN4oQPSe7bLfwAAgAAAg0wDQYJYIZIAWUDBAIBBQCgga4w
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIAnzI9tu2yYhgCi5SG1lF/VRKMvJELdO
# m3Sj4rODwog8MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# FJBiM/JRl8hxfI+5nHPdK/iZ0/UokTdsMSelUYBlFQCljeHJTj3XeUPSWK2MeTsO
# V3XJdCmgWzKs8+Eq76DHzkav26559vs2tQka19EyXQBeIhr44t6bXmlyE5K5FXM9
# sxm8bw7p5UkXushVgV0ePP7dymQ3c6BeKag8QTIX44Su7469sJ2FXPF/suv+KEUW
# A5h+LzUyKZTCOogeUfc5bqIgfRc/G8GRAu/4m83G5FQQRcoGqNO4y72xNDPpxG5I
# SWhWp4MzzdCyyZfHtsFYJcpH9LbAFY1Ef0ywEe+I2wtqjIPqr5JHajNLEAu1lBGU
# 91FvrEVY2qGc6v3lVMXYV6GCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCCF38GCSqG
# SIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCDHspN9O4a+bmxLRxoRUuVZaIWh5QtXjy+/nlt9xqM0AgIGaW+Qih0IGBMyMDI2
# MDIwNDE2MzUyOC42ODVaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHtMIIH
# IDCCBQigAwIBAgITMwAAAg4syyh9lSB1YwABAAACDjANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQzMDNaFw0y
# NjA0MjIxOTQzMDNaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQCs5t7iRtXt0hbeo9ME78ZYjIo3saQuWMBFQ7X4s9vooYRABTOf
# 2poTHatx+EwnBUGB1V2t/E6MwsQNmY5XpM/75aCrZdxAnrV9o4Tu5sBepbbfehsr
# OWRBIGoJE6PtWod1CrFehm1diz3jY3H8iFrh7nqefniZ1SnbcWPMyNIxuGFzpQiD
# A+E5YS33meMqaXwhdb01Cluymh/3EKvknj4dIpQZEWOPM3jxbRVAYN5J2tOrYkJc
# dDx0l02V/NYd1qkvUBgPxrKviq5kz7E6AbOifCDSMBgcn/X7RQw630Qkzqhp0kDU
# 2qei/ao9IHmuuReXEjnjpgTsr4Ab33ICAKMYxOQe+n5wqEVcE9OTyhmWZJS5AnWU
# Tniok4mgwONBWQ1DLOGFkZwXT334IPCqd4/3/Ld/ItizistyUZYsml/C4ZhdALbv
# fYwzv31Oxf8NTmV5IGxWdHnk2Hhh4bnzTKosEaDrJvQMiQ+loojM7f5bgdyBBnYQ
# Bm5+/iJsxw8k227zF2jbNI+Ows8HLeZGt8t6uJ2eVjND1B0YtgsBP0csBlnnI+4+
# dvLYRt0cAqw6PiYSz5FSZcbpi0xdAH/jd3dzyGArbyLuo69HugfGEEb/sM07rcoP
# 1o3cZ8eWMb4+MIB8euOb5DVPDnEcFi4NDukYM91g1Dt/qIek+rtE88VS8QIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFIVxRGlSEZE+1ESK6UGI7YNcEIjbMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQB14L2TL+L8OXLxnGSal2h30mZ7FsBFooiYkUVOY05F
# 9pnwPTVufEDGWEpNNy2OfaUHWIOoQ/9/rjwO0hS2SpB0BzMAk2gyz92NGWOpWbpB
# dMvrrRDpiWZi/uLS4ZGdRn3P2DccYmlkNP+vaRAXvnv+mp27KgI79mJ9hGyCQbvt
# MIjkbYoLqK7sF7Wahn9rLjX1y5QJL4lvEy3QmA9KRBj56cEv/lAvzDq7eSiqRq/p
# Cyqyc8uzmQ8SeKWyWu6DjUA9vi84QsmLjqPGCnH4cPyg+t95RpW+73snhew1iCV+
# wXu2RxMnWg7EsD5eLkJHLszUIPd+XClD+FTvV03GfrDDfk+45flH/eKRZc3MUZtn
# hLJjPwv3KoKDScW4iV6SbCRycYPkqoWBrHf7SvDA7GrH2UOtz1Wa1k27sdZgpG6/
# c9CqKI8CX5vgaa+A7oYHb4ZBj7S8u8sgxwWK7HgWDRByOH3CiJu4LJ8h3TiRkRAr
# mHRp0lbNf1iAKuL886IKE912v0yq55t8jMxjBU7uoLsrYVIoKkzh+sAkgkpGOoZL
# 14+dlxVM91Bavza4kODTUlwzb+SpXsSqVx8nuB6qhUy7pqpgww1q4SNhAxFnFxsx
# iTlaoL75GNxPR605lJ2WXehtEi7/+YfJqvH+vnqcpqCjyQ9hNaVzuOEHX4Myuqcj
# wjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
# BQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNV
# BAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4X
# DTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM
# 57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm
# 95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzB
# RMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBb
# fowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCO
# Mcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYw
# XE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW
# /aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/w
# EPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPK
# Z6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2
# BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfH
# CBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYB
# BAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8v
# BO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEF
# BQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBW
# BgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUH
# AQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# L2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsF
# AAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518Jx
# Nj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+
# iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2
# pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefw
# C2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7
# T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFO
# Ry3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhL
# mm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3L
# wUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5
# m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE
# 0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNQMIICOAIB
# ATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOjg5MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBK6HY/ZWLn
# OcMEQsjkDAoB/JZWCKCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S3S7TAiGA8yMDI2MDIwNDE0MTUwOVoYDzIw
# MjYwMjA1MTQxNTA5WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDtLdLtAgEAMAoC
# AQACAhnNAgH/MAcCAQACAhNcMAoCBQDtLyRtAgEAMDYGCisGAQQBhFkKBAIxKDAm
# MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcN
# AQELBQADggEBALgXTSEo42wjLxYsZSWpgZvj4tT0qTLhNHOY6fkXroQhH4KfqCBn
# QoJ81gOjjSS7L7DMC0766Q31OevwZvV/6lSH5qgjPUx1ejN8kttL6PjF8Q6+96Ww
# hh/93xunj7EOKbZMDblDZzZja0JtavoUQ/wjaVvE4KT4KIzzBla+s1sUZvCxLlX0
# /PNpd/uPLLYqfvLOLRCrgMGF5kCyskfmHEOyhFI9HJ2ZcmUThT0J3UfhM393cOrJ
# 8vULfDKmpnxw46sRdxGouezb77G3eehWZ4O7lTMn5EDqym7WvTjmQ9jL5oYy5wUU
# /Ew6AIV/aANtPGb0Euk8pIZBq3bUt8T9PMYxggQNMIIECQIBATCBkzB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAg4syyh9lSB1YwABAAACDjANBglg
# hkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
# SIb3DQEJBDEiBCDhnKi8bNJS/fAVGeXtWg/1AorChA6uLpnmOrBPClBPczCB+gYL
# KoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIAF0HXMl8OmBkK267mxobKSihwOdP0eU
# NXQMypPzTxKGMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAAIOLMsofZUgdWMAAQAAAg4wIgQgrb4hmZtEY3u7RJP6/zdCTkUUGMjjQQuY
# B2lFj8o9V+cwDQYJKoZIhvcNAQELBQAEggIAHwgWXGbZOypc1oVTnNcrXJlkm5lo
# 7Awf6pr3SNnrHaVvO8slhiBlvWZ2rlH94mpxt2zB3EP8t8wTKPtqsXRSuFuk4OZk
# FDxGRoJtoxdGVo6xfXtJxPIOQAVd+68GhmljV0yw74Tm9iHlFq0Ai0m0RJj1uLC2
# epmReHkSXqo/OfAigq90rUFm1Sl3IWaFMyJ/wnQYx6kGGqP7fsPHDwiz8q8saAQb
# gIFpJD14Vj98y430zV1xkTUgVQViHmsoOxMZf95sfVuZS4IiDh/UGIxpnOElPj+t
# VVy+0U9HsHPXG6Kq581Wlo7aJyOsH7UJFQ+vUQu0IDiLarU/x0GFBZY46/6muUI6
# RXe82j8liw1J366CPeitK0zvAPyobssUW3ZJ8Bwmb3XgSAZztRaTY9QyaDQNUcUc
# XvDS+WSYfbDNK9ZyPib6WA0bO2Z3r+UpwRM2XafEX6JpPOpUEzQR4E0MZhxxsAyX
# PKpv9hUGvRVH01kPlvmJ3YeVssR/KFIbL9wWI721n6cfgu9hmAtTTrGptxD3pVcz
# OXtypvvj15odz6veb6o+UlpgxFuE0yeRNnuXKv0NYbOlvbLQ7WKH9of6KZ2a1NQ6
# 1xhIES+pQ4Zj2SIRBL/I63pLZH61eoRCtI3Y9ZWadApP4CkA+JtN7uslUVFEeC5j
# OjC2z2wGcCwuhEE=
# SIG # End signature block
