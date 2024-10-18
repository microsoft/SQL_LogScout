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
    [int] $RepeatCollections = 0
    
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

# create a temporary log file to store the output of the repeated executions
$script:temp_output_sqllogscout = $env:temp + "\SQL_LogScout_Repeated_Execution_" + (Get-Date).ToString('yyyyMMddhhmmss') + ".txt"
$script:search_pattern = $env:temp + "\SQL_LogScout_Repeated_Execution_*.txt"

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
                                -ExecutionCountObject $ExecutionCountObj 
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

