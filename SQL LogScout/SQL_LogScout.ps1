## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.


<#
.SYNOPSIS
    SQL LogScout allows you to collect diagnostic logs from your SQL Server system to help resolve technical problems.
.DESCRIPTION
.LINK 
https://github.com/microsoft/SQL_LogScout#examples

.EXAMPLE
   SQL_LogScout.ps1
.EXAMPLE
    SQL_LogScout.ps1 -Scenario GeneralPerf
.EXAMPLE
    SQL_LogScout.ps1 -Scenario DetailedPerf -ServerName "SQLInstanceName" -CustomOutputPath "UsePresentDir" -DeleteExistingOrCreateNew "DeleteDefaultFolder"
.EXAMPLE
    SQL_LogScout.ps1 -Scenario "AlwaysOn" -ServerName "DbSrv" -CustomOutputPath "PromptForCustomDir" -DeleteExistingOrCreateNew "NewCustomFolder" -DiagStartTime "2000-01-01 19:26:00" -DiagStopTime "2020-10-29 13:55:00"
.EXAMPLE
   SQL_LogScout.ps1 -Scenario "GeneralPerf+AlwaysOn+BackupRestore" -ServerName "DbSrv" -CustomOutputPath "d:\log" -DeleteExistingOrCreateNew "DeleteDefaultFolder" -DiagStartTime "01-01-2000" -DiagStopTime "04-01-2021 17:00" -InteractivePrompts "Quiet"
#>


#=======================================Script parameters =====================================
param
(
    # DebugLevel parameter is deprecated
    # SQL LogScout will generate *_DEBUG.LOG with verbose level 5 logging for all executions
    # to enable debug messages in console, modify $global:DEBUG_LEVEL in LoggingFacility.ps1
    
    #help parameter is optional parameter used to print the detailed help "/?, ? also work"
    [Parameter(ParameterSetName = 'help',Mandatory=$false)]
    [Parameter(Position=0)]
    [switch] $help,

    #Scenario an optional parameter that tells SQL LogScout what data to collect
    [Parameter(Position=1,HelpMessage='Choose a plus-sign separated list of one or more of: Basic,GeneralPerf,DetailedPerf,Replication,AlwaysOn,Memory,DumpMemory,WPR,Setup,NoBasic. Or MenuChoice')]
    [string[]] $Scenario=[String]::Empty,

    #servername\instnacename is an optional parameter since there is code that auto-discovers instances
    [Parameter(Position=2)]
    [string] $ServerName = [String]::Empty,

    #Optional parameter to use current directory or specify a different drive and path 
    [Parameter(Position=3,HelpMessage='Specify a valid path for your output folder, or type "UsePresentDir"')]
    [string] $CustomOutputPath = "PromptForCustomDir",

    #scenario is an optional parameter since there is a menu that covers for it if not present
    [Parameter(Position=4,HelpMessage='Choose DeleteDefaultFolder|NewCustomFolder')]
    [string] $DeleteExistingOrCreateNew = [String]::Empty,

    #specify start time for diagnostic
    [Parameter(Position=5,HelpMessage='Format is: "2020-10-27 19:26:00"')]
    [string] $DiagStartTime = "0000",
    
    #specify end time for diagnostic
    [Parameter(Position=6,HelpMessage='Format is: "2020-10-27 19:26:00"')]
    [string] $DiagStopTime = "0000",

    #specify quiet mode for any Y/N prompts
    [Parameter(Position=7,HelpMessage='Choose Quiet|Noisy')]
    [string] $InteractivePrompts = "Noisy",

    [Parameter(Position=8,HelpMessage='Provide 0 for no repetition | Specify >0 for as many times as you want to run the script. Default is 0.')]
    [int] $RepeatCollections = 0,

    # Additional options parameter
    [Parameter(Position=9,HelpMessage='Choose one or more of: NoClusterLogs,TrackCausality, RedoTasksPerfStats, FullTextSearchLogs separated by +')]
    [string] $AdditionalOptionsEnabled = ""
)

function Test-PowerShellVersionAndHost()
{
    #check for version 4-6 and not ISE 
    $psversion_maj = (Get-Host).Version.Major
    $psversion_min = (Get-Host).Version.Minor
    $pshost_name = (Get-Host).Name

    if (($psversion_maj -lt 4) -or ($psversion_maj -ge 7))
    {
        Microsoft.PowerShell.Utility\Write-Host "Please use a supported PowerShell version 4.x, 5.x or 6.x. Your current verion is $psversion_maj.$psversion_min." -ForegroundColor Yellow
        Microsoft.PowerShell.Utility\Write-Host "Exiting..." -ForegroundColor Yellow
        exit 7654321
    }
    elseif ($pshost_name -match "ISE") 
    {
        Microsoft.PowerShell.Utility\Write-Host "The 'Windows PowerShell ISE Host' is not supported as a PowerShell host for SQL LogScout." -ForegroundColor Yellow
        Microsoft.PowerShell.Utility\Write-Host "Please use a PowerShell console (ConsoleHost)"  -ForegroundColor Yellow
        Microsoft.PowerShell.Utility\Write-Host "Exiting..." -ForegroundColor Yellow
        exit 8765432
    }

    else {
        Write-Host "Launching SQL LogScout..."
    }
}


# get the full but by default short path of the temp folder and convert it to full path. Then store it in a global variable
$shortEnvTempPath = $env:TEMP
$global:EnvTempVarFullPath = (Get-Item $shortEnvTempPath).FullName

# create a temporary log file to store the output of the repeated executions
# the file will be created in the temp folder and will be deleted at the end of the script

$script:temp_output_sqllogscout = $global:EnvTempVarFullPath + "\SQL_LogScout_Repeated_Execution_" + (Get-Date).ToString('yyyyMMddhhmmss') + ".txt"
$script:search_pattern = $global:EnvTempVarFullPath+ "\SQL_LogScout_Repeated_Execution_*.txt"

function Write-SQLLogScoutTempLog()
{
    param 
    ( 
        [Parameter(Position=0,Mandatory=$true)]
        [Object]$Message
    )

    try
    {        
        [String]$strMessage = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $strMessage += "	: "
        $strMessage += [string]($Message)

        Add-Content -Path $script:temp_output_sqllogscout -Value $strMessage
    }
	catch
	{
		Write-Host "Exception writing to the temp log file: $script:temp_output_sqllogscout. Error: $($_.Exception.Message)"
	}
    
}


# the main script
try 
{
    # validate the minimum version of PowerShell and PowerShell host (not ISE)
    Test-PowerShellVersionAndHost

    # check if the temp log file exists, if it does, then delete it
    if (Test-Path -Path $script:search_pattern)
    {
        Remove-Item -Path $script:search_pattern -Force
    }

    # set the output folders array to store all the folders which are created by SQL LogScout in repeated mode
    $script:output_folders_multiple_runs = @()

    # set the execution counter to 0
    [int] $execution_counter = 0

    # If the user wants to run the main script multiple times, then we will loop through multiple times with max = RepeatCollections
    # if RepeatCollections is set to 0, then we will run the script only once (we don't want to repeat)

    do
    {

        # changes the directory to the location of the script, which is the root of SQL LogScout and stores on the stack
        Push-Location -Path $PSScriptRoot

        # Change the location to the Bin folder, 
        Set-Location .\Bin\

        
        # enforce repeat collection to be a valid number (0 or greater)
        if ([Int]::TryParse($RepeatCollections, [ref]$null) -eq $false)
        {
            Microsoft.PowerShell.Utility\Write-Host "Please provide a valid number value for the RepeatCollections parameter (0 or greater)" -ForegroundColor Yellow
            break
        }
        else 
        {
            if (($RepeatCollections -lt 0) -or ($RepeatCollections -eq $null))
            {
                $RepeatCollections = 0
            }
        }

        if ($execution_counter -eq 0)
        {
            Write-SQLLogScoutTempLog "Initial collection running."
            Write-SQLLogScoutTempLog "Total Repeat collections: $RepeatCollections. This count is in addition to the initial collection. Thus the total LogScout collections will be $($RepeatCollections + 1)."
        }
        else 
        {
            Write-SQLLogScoutTempLog "Repeat collection running. Current iteration count: $execution_counter"
        }

        
        # if the user wants multiple executions of the script, then we need to set some parameters 
        if (($RepeatCollections -gt 0))
        {
            
        
            #if repeat collection is set to > 0, then we need to make sure the user has passed a custom output path value or use current path
            if ($CustomOutputPath -eq "PromptForCustomDir")
            {
                Microsoft.PowerShell.Utility\Write-Host "The default value 'PromptForCustomDir' for the CustomOutputPath parameter isn't a valid option when used with RepeatCollections. Specify 'UsePresentDir' or a valid path." -ForegroundColor Yellow
                break
            }

            #if repeat collection is set to > 0, then interactive prompts should be set to quiet
            $InteractivePrompts = "Quiet"


            #if repeat collection is set to > 0, then we need to make sure DeleteExistingOrCreateNew is not null or empty
            #if $DeleteExistingOrCreateNew isn't "DeleteDefaultFolder", "NewCustomFolder", then main script will validate that
            if([Int]::TryParse($DeleteExistingOrCreateNew, [ref]$null) -eq $true)
            {
                #convert the string to an integer and store it in the folders_to_preserve variable
                #this will be used to preserve the most recent folders and delete the rest
                $folders_to_preserve = [Int]::Parse($DeleteExistingOrCreateNew)

                Write-SQLLogScoutTempLog "Folders to keep was set to $folders_to_preserve by the user." 

                #if the value is a number, it behaves like a new custom folder to be created
                $DeleteExistingOrCreateNew = "NewCustomFolder"
            }
            elseif($DeleteExistingOrCreateNew -notin "DeleteDefaultFolder","NewCustomFolder")
            {
                #if the value is "DeleteDefaultFolder", then we will delete the default folder
                Microsoft.PowerShell.Utility\Write-Host "To run in continous mode (RepeatCollections), please provide a valid 'DeleteExistingOrCreateNew' value." -ForegroundColor Yellow
                break
            }

            # If repeat collection is set to > 0, then we need to make sure the user has passed all the parameters for time range
            if ($DiagStartTime -eq "0000" -or $DiagStopTime -eq "0000")
            {
                Microsoft.PowerShell.Utility\Write-Host "Please provide a valid start time (DiagStartTime) and stop time (DiagStopTime) parameters." -ForegroundColor Yellow
                break
            }
        

            #if repeat collection is set to > 0, then we need to make sure the user has passed a server name and scenario
            if (($true -eq [String]::IsNullOrWhiteSpace($ServerName)) -or ($true -eq [String]::IsNullOrWhiteSpace($Scenario)))
            {
                Microsoft.PowerShell.Utility\Write-Host "Please provide a valid server name and scenario for the diagnostic" -ForegroundColor Yellow
                break
            }
        }
        else 
        {
            #if the user has not provided a value for RepeatCollections, then DeleteExistingOrCreateNew should not be a number
            if([Int]::TryParse($DeleteExistingOrCreateNew, [ref]$null) -eq $true)
            {
                Microsoft.PowerShell.Utility\Write-Host "The 'DeleteExistingOrCreateNew' parameter cannot be a number if the 'RepeatCollections' parameter is less than 1. If you want to use repeated collections, specify a value of 1 or greater for RepeatCollections." -ForegroundColor Yellow
                break
            }
            
            
        }

        #create an object to keep track of how many times SQL LogScout will be executed if continuous mode/repeat collection is selected
        #if the user wants to delete the default folder, then we will set the folder overwrite to true
        $ExecutionCountObj = [PSCustomObject]@{
            CurrentExecCount = $execution_counter
            RepeatCollection= $RepeatCollections
            OverwriteFolder = $null}
        
        
        #if user needs to show help, do this
        if ($help)
        {
            .\SQLLogScoutPs.ps1 -help
        }
        # execute SQL LogScout with the parameters provided
        else 
        {
         
            # If repeat collection is set to > 0, then we will keep running the script until we reach RepeatCollections value or the user presses Ctrl+C
            .\SQLLogScoutPs.ps1 -Scenario $Scenario -ServerName $ServerName -CustomOutputPath $CustomOutputPath -DeleteExistingOrCreateNew $DeleteExistingOrCreateNew `
                                -DiagStartTime $DiagStartTime -DiagStopTime $DiagStopTime -InteractivePrompts $InteractivePrompts `
                                -ExecutionCountObject $ExecutionCountObj -AdditionalOptionsEnabled $AdditionalOptionsEnabled
        }


        
        # Add the latest output folder used by LogScout to the array if in repeat mode and reset the global output folder variable
        if ($RepeatCollections -gt 0)
        {

            #if the user has not provided a value for folders to preserve, then we will preserve all the output folders
            # also this value can be reset to null later if the user has provided a number greater than the repeat collections
            if ($null -eq $folders_to_preserve)
            {
                Write-SQLLogScoutTempLog "Folders_to_Preserve is null. Will preserve all output folders."

            }
            
            #reset/correct the number of folders to preserve. 
            #if the user has provided a number, then we will use that number to preserve the folders
            #if the user has provided a number greater than the repeat collections, we won't delete any folders, just keep the ones created
            #if folders to keep is set to 0 folders, then we will default to 1
            if ($folders_to_preserve -eq 0)
            {
                $folders_to_preserve = 1
                Write-SQLLogScoutTempLog "Folders to keep was reset to: $folders_to_preserve" 
            }
            elseif ($folders_to_preserve -ge $RepeatCollections)
            {
                #set the folders to preserve to null, so we don't delete any folders
                Write-SQLLogScoutTempLog "Folders to keep was reset to 'null' since it's larger than RepeatCollecitons. No folders will be deleted." 
                $folders_to_preserve = $null
            }

            Write-SQLLogScoutTempLog "Folders to keep is set to: $folders_to_preserve" 

            #add the output folder to the array script level variable
            $script:output_folders_multiple_runs += $global:output_folder
            
            #log the output folders 
            Write-SQLLogScoutTempLog ("Output folders: `r`n`t`t`t" + ($script:output_folders_multiple_runs -Join "`r`n`t`t`t"))

            #reset the global output folder variable. use a string instead of a $null for debugging purposes
            $global:output_folder = "invalid_folder_path"

            # Get last write times for each folder using Get-Item
            $folderLastWriteTimes = @{}
            foreach ($folderPath in $script:output_folders_multiple_runs) 
            {
                #add both key and value in hash table if the folder exists
                if (Test-Path -Path $folderPath)
                {
                    $folderLastWriteTimes[$folderPath] = (Get-Item $folderPath).LastWriteTime
                }
            }

            # Preserve the most recent X folders and delete the remaining ones, but only if the value is greater than 0 or non-null
            # If the user has not provided a number, then we will not delete any folders
            if (($null -ne $folders_to_preserve) -or ($folders_to_preserve -gt 0))
            {
                
                # Sort folder paths based on last write time
                $sortedFolderPaths = $folderLastWriteTimes.GetEnumerator() | Sort-Object -Property Value -Descending |Select-Object -Property Value, Key


                # Preserve the most recent X folders and delete the remaining ones
                $deletedFolders = $sortedFolderPaths | Select-Object -Skip $folders_to_preserve

                # Print deleted folders
                foreach ($del_folder in $deletedFolders)
                {
                    Write-SQLLogScoutTempLog "Folder being deleted: $($del_folder.Key)"
                }

                # Clean up: Remove the folders
                $deletedFolders | ForEach-Object { Remove-Item -Path $_.Key -Force -Recurse }
            }
        }

        # Return to the original location
        Pop-Location

        # Increment the execution counter
        $execution_counter++

    } while ($execution_counter -le $RepeatCollections)

}
catch 
{
    Write-Host $PSItem.Exception.Message

    $exception_str = "Exception line # " + $($PSItem.InvocationInfo.ScriptLineNumber) + ", offset" + $($PSItem.InvocationInfo.OffsetInLine) + ", script ='" + $($PSItem.InvocationInfo.ScriptName) +"'"

    #write the exception to the temp log file and console
    Write-Host $exception_str
    Write-SQLLogScoutTempLog -Message $exception_str

}
finally 
{
    Pop-Location
}


# SIG # Begin signature block
# MIIr4wYJKoZIhvcNAQcCoIIr1DCCK9ACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB5x+jK6Wi3/Fwq
# 3RyYSbCTsVZTzWAlzmQ3PZ2l1EpJIqCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# fiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZyzCCGccCAQEwWDBBMRMwEQYKCZIm
# iZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQDEwxBTUUg
# Q1MgQ0EgMDECEzYAAAIN4oQPSe7bLfwAAgAAAg0wDQYJYIZIAWUDBAIBBQCgga4w
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILX5cbF5OIlpx6CCwu3N3IS9fz9V2Vy+
# YM91p9t+jZVpMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# MHeFx8m5S1D95qvHfbBcr0DsQPDw1zb5pCjvFhXQEuNQkTS0nqBLuKxMo8TwCXVH
# wxUXA+PC4dOYNBNIdS/hdyunIBXo9XCm36u2rCRJtosC/2cUdo9sEAxaixB3YUH7
# 3JhNgLEGx0tV680oWsh2sfABltcPAAE2Fa1D71q2nIpTyxb1zs8rIrKCe+cl9zpr
# GgkGE0LHCBSRyGYu7q+ePl5P0DvF5984zvQBLlS21aoYdmbnmR6tCYaLH5GyqwmH
# KhfckdtGy/R3uAWUtXzIwzIpN8hdrD3Hxx1ITvT8oPItT43e9HI4WG+zRiRQAcV5
# ewbzXXNrqxfJLuwMUwGjxaGCF5MwghePBgorBgEEAYI3AwMBMYIXfzCCF3sGCSqG
# SIb3DQEHAqCCF2wwghdoAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFRBgsqhkiG9w0B
# CRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCC4gvs76HmUsUJZ6yPIT7WYOoMUH5Ogllxl7RrCjkX3gAIGaWj23IQUGBIyMDI2
# MDIwNDE2MzUyNy41OVowBIACAfSggdGkgc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9w
# ZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpEQzAwLTA1RTAtRDk0
# NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEeowggcg
# MIIFCKADAgECAhMzAAACA7seXAA4bHTKAAEAAAIDMA0GCSqGSIb3DQEBCwUAMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDEzMDE5NDI0NloXDTI2
# MDQyMjE5NDI0NlowgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjpEQzAwLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAKGXQwfnACc7HxSHxG2J0XQnTJoUMclgdOk+9FHXpfUrEYNh9Pw+
# twaMIsKJo67crUOZQhThFzmiWd2Nqmk246DPBSiPjdVtsnHk8VNj9rVnzS2mpU/Q
# 6gomVSR8M9IEsWBdaPpWBrJEIg20uxRqzLTDmDKwPsgs9m6JCNpx7krEBKMp/YxV
# fWp8TNgFtMY0SKNJAIrDDJzR5q+vgWjdf/6wK64C2RNaKyxTriTysrrSOwZECmIR
# J1+4evTJYCZzuNM4814YDHooIvaS2mcZ6AsN3UiUToG7oFLAAgUevvM7AiUWrJC4
# J7RJAAsJsmGxP3L2LLrVEkBexTS7RMLlhiZNJsQjuDXR1jHxSP6+H0icugpgLkOk
# pvfXVthV3RvK1vOV9NGyVFMmCi2d8IAgYwuoSqT3/ZVEa72SUmLWP2dV+rJgdisw
# 84FdytBhbSOYo2M4vjsJoQCs3OEMGJrXBd0kA0qoy8nylB7abz9yJvIMz7UFVmq4
# 0Ci/03i0kXgAK2NfSONc0NQy1JmhUVAf4WRZ189bHW4EiRz3tH7FEu4+NTKkdnkD
# cAAtKR7hNpEG9u9MFjJbYd6c5PudgspM7iPDlCrpzDdn3NMpI9DoPmXKJil6zlFH
# Yx0y8lLh8Jw8kV5pU6+5YVJD8Qa1UFKGGYsH7l7DMXN2l/VS4ma45BNPAgMBAAGj
# ggFJMIIBRTAdBgNVHQ4EFgQUsilZQH4R55Db2xZ7RV3PFZAYkn0wHwYDVR0jBBgw
# FoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1T
# dGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEF
# BQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNy
# b3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/
# BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwDQYJ
# KoZIhvcNAQELBQADggIBAJAQxt6wPpMLTxHShgJ1ILjnYBCsZ/87z0ZDngK2ASxv
# HPAYNVRyaNcVydolJM150EpVeQGBrBGic/UuDEfhvPNWPZ5Y2bMYjA7UWWGV0A84
# cDMsEQdGhJnil10W1pDGhptT83W9bIgKI3rQi3zmCcXkkPgwxfJ3qlLx4AMiLpO2
# N+Ao+i6ZZrQEVD9oTONSt883Wvtysr6qSYvO3D8Q1LvN6Z/LHiQZGDBjVYF8Wqb+
# cWUkM9AGJyp5Td06n2GPtaoPRFz7/hVnrBCN6wjIKS/m6FQ3LYuE0OLaV5i0CIgW
# maN82TgaeAu8LZOP0is4y/bRKvKbkn8WHvJYCI94azfIDdBqmNlO1+vs1/OkEglD
# jFP+JzhYZaqEaVGVUEjm7o6PDdnFJkIuDe9ELgpjKmSHwV0hagqKuOJ0QaVew06j
# 5Q/9gbkqF5uK51MHEZ5x8kK65Sykh1GFK0cBCyO/90CpYEuWGiurY4Jo/7AWETdY
# +CefHml+W+W6Ohw+Cw3bj7510euXc7UUVptbybRSQMdIoKHxBPBORg7C732ITEFV
# aVthlHPao4gGMv+jMSG0IHRq4qF9Mst640YFRoHP6hln5f1QAQKgyGQRONvph81o
# jVPu9UBqK6EGhX8kI5BP5FhmuDKTI+nOmbAw0UEPW91b/b2r2eRNagSFwQ47Qv03
# MIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsF
# ADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UE
# AxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcN
# MjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzn
# tHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3
# lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFE
# yHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+
# jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4x
# yDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBc
# TyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9
# pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ
# 8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pn
# ol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYG
# NRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cI
# FRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEE
# AYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E
# 7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwr
# BgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUF
# BwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYG
# A1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3Js
# L3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcB
# AQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kv
# Y2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUA
# A4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2
# P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J
# 6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfak
# Vqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/AL
# aoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtP
# u4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5H
# LcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEua
# bvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvB
# QUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb
# /wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETR
# kPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCA00wggI1AgEB
# MIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQL
# Ex5uU2hpZWxkIFRTUyBFU046REMwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAM2vFFf+LPqy
# zWUEJcbw/UsXEPR7oIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwDQYJKoZIhvcNAQELBQACBQDtLc/NMCIYDzIwMjYwMjA0MTQwMTQ5WhgPMjAy
# NjAyMDUxNDAxNDlaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAO0tz80CAQAwBwIB
# AAICDsMwBwIBAAICE0AwCgIFAO0vIU0CAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYK
# KwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQsF
# AAOCAQEAX02q+2E78E/FFeXTH8DhhV+VO5tmLiTGUjC3oKuTJGmaQ0EyjELMZRuq
# tx1Yt63hWaGK8hnrD8YpAmA0WMHs3c/3/uh5qVwoFnO2i89HFeAPZ4bPd6OhGHur
# Hfq38ezJYkN2aqtL3YXKiKDvrxxbV/M7m6aE/Po5r61Pr1+jakE+DOzUcsM9Pitf
# hweXS7K4cqL7PFzABj+mWCTLdC8sYcCrNry2sOVMz1QVV99Nksrx3A2uChP0U9sl
# IiPQyY2v+XOG87In7SLtQE8if3dk5/YrHIekVmU3ccQNstJQZE19EKA0hJYusiWt
# rmXNZ41BnqxRazBjy+Bdzk9CByLDczGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACA7seXAA4bHTKAAEAAAIDMA0GCWCGSAFl
# AwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIPUD46MenJuJgFTfJvV/qsxPCHEctGPMV+liG2wIJCGlMIH6BgsqhkiG
# 9w0BCRACLzGB6jCB5zCB5DCBvQQgSwPdG3GW9pPEU5lmelDDQOSw+ZV26jlLIr2H
# 3D76Ey0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# AgO7HlwAOGx0ygABAAACAzAiBCD9Dk6bVM0p/sea8APxpSUp6nMNJpU8hJDxhHdh
# iEI3UDANBgkqhkiG9w0BAQsFAASCAgAzmne27Pu29/buWL0tj+6zpetCFDvS17Vd
# 4BbBWgxp/c1ZpR5UBzIQtym32Unay0HDS6HdJ9q/IGHVHNMRjUtd4bLmgHpCJ1yO
# npNGD1NlkOSPou0zzWMG349bhEB6MWVmW7hKWpSSNf5s44dSpajmn6pJ9c56shmk
# oaJvR/as8X0e2+yx9ueRbaIW8E97RkqU4BWIurrVwq6mfFUCYsNsxg6hzmxnKPVF
# epaTwrjOqT/unyEoQc5W1MUyKGte6+18dJ6peGvLXiS9VeItM/RbIq3HIv5NaumK
# ENEjNZ4bXWbvfZmrGaECs3p5bcCq1fybipt3KFk6NiEhUoQJr9jF9C+Pr0BtFrI6
# +7HTgI9ucE2PxHtvYRjGxmoCkyF1zMyvvouuuMQSklYXNNpJ6PvjM4wcllO6rQ3L
# +gg8whe3EYBaFKapU7uopC39c8TQmEum/4+MPvFIxUhmh0fRB0oCAND+FYOsgtKX
# S6n2Pnm9/2m7uxvnEwTFo1nH0F8+C8gyeuqZQhATfnZDD2ISP/+/HC0k8uGbt01o
# +VEEYakE6olf9BuVpz2ehEutn9QuJArW4D1ZPKZimWSS4YwKRJadnr9iziGAsNrE
# dorHpIM65Wf2tiuzDtySUYvVuyiN1+6JRGZHXy2HXijvkDmN9ZV7e4sNC9X3JLqb
# nrlv8CTVVg==
# SIG # End signature block
