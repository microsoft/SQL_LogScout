<#
written by 
 James.Ferebee@microsoft.com
 PijoCoder @github.com

.SYNOPSIS
  Test Powershell script to create task in Windows Task Scheduler to invoke SQL LogScout.
.LINK 
  https://github.com/microsoft/sql_logscout
.EXAMPLE
  .\ScheduleSQLLogScoutAsTask.ps1 -LogScoutPath "C:\temp\log scout\Test 2" -Scenario "GeneralPerf" -SQLInstance "Server1\sqlinst1" 
  -OutputPath "C:\temp\log scout\test 2" -CmdTaskName "First SQLLogScout Capture" -DeleteFolderOrNew "DeleteDefaultFolder" 
  -StartTime "2022-08-24 08:26:00" -DurationInMins 10 -Once 
#> 

param
(
    #Implement params to have the script accept parameters which is then provided to Windows Task Scheduler logscout command
    #LogScout path directory
    [Parameter(Position=0)]
    [string] $LogScoutPath, 

    #GeneralPerf, etc.
    [Parameter(Position=1, Mandatory=$true)]
    [string] $Scenario,

    #Connection string into SQL.
    [Parameter(Position=2, Mandatory=$true)]
    [string] $SQLInstance,

    #Whether to use custom path or not
    [Parameter(Position=3, Mandatory=$false)]
    #We are in bin, but have the output file write to the root logscout folder.
    [string] $OutputPath = (Get-Item (Get-Location)).Parent.FullName,

    #Name of the Task. Use a unique name to create multiple scheduled runs. Defaults to "SQL LogScout Task" if omitted.
    [Parameter(Position=4, Mandatory=$false)]
    [string] $CmdTaskName = "SQL LogScout Task",
    
    #Delete existing folder or create new one.
    [Parameter(Position=5, Mandatory=$true)]
    [string] $DeleteFolderOrNew,

    #Start time of collector. 2022-09-29 21:26:00
    [Parameter(Position=6,Mandatory=$true)]
    [datetime] $StartTime,
    
    #How long to execute the collector. In minutes.
    [Parameter(Position=7,Mandatory=$true)]
    [double] $DurationInMins,

    #schedule it for one execution
    [Parameter(Position=8, Mandatory=$false)]
    [switch] $Once = $false,

    #schedule it daily at the specified time
    [Parameter(Position=9, Mandatory=$false)]
    [switch] $Daily = $false,

    #schedule it daily at the specified time
    [Parameter(Position=10, Mandatory=$false)]
    [nullable[boolean]] $CreateCleanupJob = $null,

    #schedule it daily at the specified time
    [Parameter(Position=11, Mandatory=$false)]
    [nullable[datetime]] $CleanupJobTime = $null,

    #schedule it daily at the specified time
    [Parameter(Position=12, Mandatory=$false)]
    [string] $LogonType = $null

    #Later add switch to auto-delete task if it already exists

    #for future scenarios
    #[Parameter(Position=9)]
    #[timespan] $RepetitionDuration, 

    #[Parameter(Position=10)]
    #[timespan] $RepetitionInterval

)




################ Globals ################

[string]$global:CurrentUserAccount = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

################ Import Modules for Shared Functions ################



################ Functions ################
function HandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
<#
    .DESCRIPTION
        error handling
#>  
{
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Log-ScheduledTask -Message "'$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)" -WriteToConsole $true -ConsoleMsgColor "Red"
}


function Initialize-ScheduledTaskLog
    (
        [string]$LogFilePath = $env:TEMP,
        [string]$LogFileName = "##SQLLogScout_ScheduledTask"
    )
{
<#
    .DESCRIPTION
        Initialize-ScheduledTaskLog creates the log file specific for scheduled tasks in the desired directory. 
        Logging to console is also written to the persisted file on disk.

#>    
    try
    {
        #Cache LogFileName withotu date so we can delete old records properly
        $LogFileNameStringToDelete = $LogFileName

        #update file with date
        $LogFileName = ($LogFileName -replace "##SQLLogScout_ScheduledTask", ("##SQLLogScout_ScheduledTask_" + @(Get-Date -Format  "yyyyMMddTHHmmssffff") + ".log"))
        $global:ScheduledTaskLog = $LogFilePath + '\' + $LogFileName
        New-Item -ItemType "file" -Path $global:ScheduledTaskLog -Force | Out-Null
        $CurrentTime = (Get-Date -Format("yyyy-MM-dd HH:MM:ss.ms"))
        Write-Host "$CurrentTime : Created log file $global:ScheduledTaskLog"
        $CurrentTime = (Get-Date -Format("yyyy-MM-dd HH:MM:ss.ms"))
        Write-Host "$CurrentTime : Log initialization complete!"

        #Array to store the old files in temp directory that we then delete and use the non-date value as the string to find.
        $FilesToDelete = @(Get-ChildItem -Path ($LogFilePath) | Where-Object {$_.Name -match $LogFileNameStringToDelete} | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip 10)
        $NumFilesToDelete = $FilesToDelete.Count

        Log-ScheduledTask -Message "Found $NumFilesToDelete older SQL LogScout Scheduled Task Logs"

        # if we have files to delete
        if ($NumFilesToDelete -gt 0) 
        {
            foreach ($elem in $FilesToDelete)
            {
                $FullFileName = $elem.FullName
                Log-ScheduledTask -Message "Attempting to remove file: $FullFileName"
                Remove-Item -Path $FullFileName
            }
        }


    }
    catch
    {
		#Write-Error -Exception $_.Exception
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  -exit_logscout $true
    }

}

function Log-ScheduledTask 
    
    (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Message,
        [Parameter(Mandatory=$false, Position=1)]
        [bool]$WriteToConsole = $false,
        [Parameter(Mandatory=$false, Position=2)]
        [System.ConsoleColor]$ConsoleMsgColor = [System.ConsoleColor]::White
    )  
{
<#
    .DESCRIPTION
        Appends messages to the persisted log and also returns output to console if flagged.

#>


    try 
    {
        #Add timestamp
        [string]$Message = (Get-Date -Format("yyyy-MM-dd HH:MM:ss.ms")) + ': '+ $Message
        #if we want to write to console, we can provide that parameter and optionally a color as well.
        if ($true -eq $WriteToConsole)
        {
            if ($ConsoleMsgColor -ine $null -or $ConsoleMsgColor -ine "") 
            {
                Write-Host -Object $Message -ForegroundColor $ConsoleMsgColor
            }
            else 
            {
                #Return message to console with provided color.
                Write-Host -Object $Message
            }
        }        
        #Log to file in $env:temp
        Add-Content -Path $global:ScheduledTaskLog -Value $Message | Out-Null
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  -exit_logscout $true
    }
}


################ Log initialization ################
Initialize-ScheduledTaskLog

Log-ScheduledTask -Message "Creating SQL Scout as Task" -WriteToConsole $true -ConsoleMsgColor "Green"


################ Validate parameters and date ################
try 
#later add check to make sure sql_logscout exists in directory.
{
    #Logscout Path Logic
    if ($true -ieq [string]::IsNullOrEmpty($LogScoutPath))
    {
        #Since logscout is not in bin, we need to back out one directory to execute logscout
        $CurrentDir = Get-Location 
        [string]$LogScoutPath = (Get-Item $CurrentDir).parent.FullName
    }
    #validate the folder
    if ((Test-Path $LogScoutPath) -ieq $true)
    {   
        #trim a trailing backslash if one was provided. otherwise the job would fail
        if ($LogScoutPath.Substring($LogScoutPath.Length -1) -eq "`\")
        {
            $LogScoutPath = $LogScoutPath.Substring(0,$LogScoutPath.Length -1)
        }
    }


    #Make sure characters are permitted
    $disallowed_characters = @("\\","/",":","\*","\?",'"',"<",">","\|")
    foreach ($disallowed_characters in $disallowed_characters)
    {
        if ($CmdTaskName -match $disallowed_characters)
        { 
            Log-ScheduledTask -Message "ERROR: Task Name cannot contain wildcard characters. Disallowed characters: $disallowed_characters. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
            Start-Sleep -Seconds 4
            exit
        }
    }
    
    #Verify provided date for logscout is in the future
    [DateTime] $CurrentTime = Get-Date
    if ($CurrentTime -gt $StartTime)
    {
        Log-ScheduledTask -Message "ERROR: Date or time provided is in the past. Please provide a future date/time. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }

    #Verify parameter passed
    if (($LogonType -ne "S4U") -and ($LogonType -ne "Interactive") -and ([string]::IsNullOrEmpty($LogonType) -ne $true))
    {
        Log-ScheduledTask -Message "ERROR: LogonType was provided and is not S4U or Interactive. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }

    ###Cleanup Job Parameter Validation###
    #Verify cleanup job date provided is in the future

    if ($CreateCleanupJob -ieq $true) 
    {
        if ($null -ne $CleanupJobTime) 
        {
            #Get duration of logscout and cleanup 
            $timediff = New-TimeSpan -Start $StartTime -End $CleanupJobTime

            #If cleanup job is set to run in the past, throw error.
            if ($CurrentTime -gt $CleanupJobTime)
            {
                Log-ScheduledTask -Message "ERROR: Cleanup Job Time Date or time provided is in the past. Please provide a future date/time. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }

            #Verify job is to be running once and that cleanupjobtime is after invocation start.
            if ($StartTime -ige $CleanupJobTime)
            {
                Log-ScheduledTask -Message "ERROR: Logscout configured to run after cleanup. Please correct the execution times. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }

            #Get minutes between cleanup job and current time. If less than 5, throw error so logscout has some time to shut down.
            elseif ($timediff.TotalMinutes -le "5")
            {
                Log-ScheduledTask -Message "ERROR: CleanupJobTime parameter was provided but is within 5 minutes of LogScout start time. Please provide a value greater than 5 minutes. Exiting.." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }

            #For once executions, verify cleanup job HH:mm is different than start as we could spin them up at the same time.
            if ($Daily -ieq $true -and (($StartTime.Hour -ieq $CleanupJobTime.Hour) -and ($StartTime.Minute -ieq $CleanupJobTime.Minute)))
            {
                Log-ScheduledTask -Message "ERROR: Logscout configured to run daily and cleanup job set to run at the same hour and minute. Please update the cleanup job to run at a different time. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }

            else
            {
                Log-ScheduledTask -Message "Cleanup Parameter Validation Passed"
            }

        }
        else 
        {
            #CreateCleanupJob is true, but CleanupJobTime is null. Exit.
            Log-ScheduledTask -Message "ERROR: CreateCleanupJob provided as true but CleanupJobTime omitted. Provide both parameters or neither. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
            Start-Sleep -Seconds 4
            exit
        }
        
    }

    ###/Cleanup Job Parameter Validation###

    else
    {
        Log-ScheduledTask -Message "CreateCleanupJob not provided. No validation performed on CleanupJobTime."
    }

        

    #Calculate stoptime based on minutes provided to determine end time of LogScout
    if ($DurationInMins-lt 1)
    {
        $DurationInMins = 1
    }

    [datetime] $time = $StartTime
    [datetime] $endtime = $time.AddMinutes($DurationInMins)

    Log-ScheduledTask -Message "Based on starttime $StartTime and duration $DurationInMins minute(s), the end time is $endtime" 

    

    #Output path check
    if (([string]::IsNullOrEmpty($OutputPath) -ieq $true) -or ($OutputPath -ieq 'UsePresentDir') )
    {
        $OutputPath = 'UsePresentDir'
    }
    else
    {
        $validpath = Test-Path $OutputPath

        #if $OutputPath is valid use it, otherwise, throw an exception
        if ($validpath -ieq $false)
        {
            Log-ScheduledTask -Message "ERROR: Invalid directory provided as SQL LogScout Output folder. Please correct and re-run. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
            Start-Sleep -Seconds 4
            exit
        }

        #trim a trailing backslash if one was provided. otherwise the job would fail
        if ($OutputPath.Substring($OutputPath.Length -1) -eq "`\")
        {
            $OutputPath = $OutputPath.Substring(0,$OutputPath.Length -1)
        }

    }

    #Whether to delete the existing folder or use new folder with incremental date_time in the name
    #If left blank or null, default behavior is DeleteDefaultFolder
    if ([string]::IsNullOrEmpty($DeleteFolderOrNew) -ieq $true)
    {
        $DeleteFolderOrNew = 'DeleteDefaultFolder'
    }

    elseif ($DeleteFolderOrNew -ieq 'DeleteDefaultFolder')
    {    
        $DeleteFolderOrNew = 'DeleteDefaultFolder'
    }

    elseif ($DeleteFolderOrNew -ieq 'NewCustomFolder')
    {    
        $DeleteFolderOrNew = 'NewCustomFolder'
    }

    else
    {
        Log-ScheduledTask -Message "ERROR: Please specify a valid parameter for DeleteFolderOrNew. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        exit
    }
    

    #define the schedule (execution time) - either run it one time (Once) or every day at the same time (Daily)
    #Verify both Once and Daily aren't provided. If so, exit.
    if ($Once -ieq $true -and $Daily -ieq $true)
    {
        Log-ScheduledTask -Message "ERROR: Both Once and Daily switches used in command. Please use only one. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }

    #Verify both Once and Daily aren't omitted. If so, exit.
    if ($Once -ieq $false -and $Daily -ieq $false)
    {
        Log-ScheduledTask -Message "ERROR: Once and Daily not provided. Please provide either Once or Daily to command. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }
    if ($Once -ieq  $true)
    {
        $trigger = New-ScheduledTaskTrigger -Once -At $StartTime
    }
    elseif ($Daily -ieq $true) 
    {
        #Convert date/time of starttime to different format to prevent skipping a day in collection.'2022-08-24 08:26:00' becomes 8:26:00 AM
        $DailyTimeFormat = Get-Date $StartTime -DisplayHint Time

        $trigger = New-ScheduledTaskTrigger -Daily -At $DailyTimeFormat 
    }
    else 
    {
        Log-ScheduledTask -Message "ERROR: Please specify either '-Once' or '-Daily' parameter (but not both). Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }

    

    ################ Verify Not Duplicated Job ################
    #After all the checks above, we can now see if scheduled SQL LogScout task already exists, exit or prompt for delete
    $LogScoutScheduleTaskExists = Get-ScheduledTask -TaskName $CmdTaskName -ErrorAction SilentlyContinue
    $CleanupTaskName = "SQL LogScout Cleanup Task for '" + $CmdTaskName + "'"
    $LogScoutCleanupScheduleTaskExists = Get-ScheduledTask -TaskName $CleanupTaskName  -ErrorAction SilentlyContinue

    if ($LogScoutScheduleTaskExists)
    {
        Log-ScheduledTask -Message "SQL Logscout task already exists. Would you like to delete associated tasks and continue? Provide Y or N." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        
        $delete_task = $null

        while ( ($delete_task -ne "Y") -and ($delete_task -ne "N") )
        {
            $delete_task = Read-Host "Delete existing SQL LogScout task (Y/N)?"

            $delete_task = $delete_task.ToString().ToUpper()
            if ( ($delete_task -ne "Y") -and ($delete_task -ne "N"))
            {
                Write-Host "Please provide 'Y' or 'N' to proceed"
            }
        }
    
        

        if ($delete_task -ieq 'N')
        {
            Log-ScheduledTask -Message "ERROR: Please review and delete existing task manually if you wish to re-run. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
            Start-Sleep -Seconds 4
            exit
        }
        else 
        {
            Unregister-ScheduledTask -TaskName $CmdTaskName -Confirm:$false
        }

     
    }

    #If cleanup task exists for provided input, remove it
    if ($LogScoutCleanupScheduleTaskExists)
    {
        Log-ScheduledTask -Message "SQL Logscout *Cleanup* task already exists. Removing the task." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        Unregister-ScheduledTask -TaskName $CleanupTaskName -Confirm:$false
    }


    Log-ScheduledTask -Message "Logon type before prompt $LogonType" -WriteToConsole $false

    ################ Prompt User Credentials ################
    if ([string]::IsNullOrEmpty($LogonType) -eq $true)
    {
        Log-ScheduledTask -Message "Will your account be logged in when the task executes" -WriteToConsole $true -ConsoleMsgColor "Green"
        Log-ScheduledTask -Message "(this includes logged in with screen locked)?" -WriteToConsole $true -ConsoleMsgColor "Green"
        Log-ScheduledTask -Message "------------------------" -WriteToConsole $true
        Log-ScheduledTask -Message "Provide Y or N." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        
        [string]$set_logintype = $null

        while ( ($set_logintype -ne "Y") -and ($set_logintype -ne "N") )
        {
            $set_logintype  = Read-Host "Will you be logged in when running the job? Provide 'Y' or 'N'"

            $set_logintype  = $set_logintype.ToString().ToUpper()
            if ( ($set_logintype -ne "Y") -and ($set_logintype -ne "N"))
            {
                Write-Host "Please provide 'Y' or 'N' to proceed"
            }
        }
        $LogonType = $set_logintype
        Log-ScheduledTask -Message "Logon type returned after prompt is $LogonType" -WriteToConsole $false
    }

       
    #Convert LoginType string to int for proper creation of job
    if ($LogonType.ToString().ToUpper() -eq 'N' -or $LogonType.ToString().ToUpper() -eq 'S4U')
    {
        [int]$LogonTypeInt = [int][Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.LogonTypeEnum]::S4U
    }
    elseif ($LogonType.ToString().ToUpper() -eq 'Y' -or $LogonType.ToString().ToUpper() -eq 'INTERACTIVE') 
    {
        [int]$LogonTypeInt = [int][Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.LogonTypeEnum]::Interactive
    }
    else 
    {
        Log-ScheduledTask -Message "ERROR: Unhandled LogonType parameter provided. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }


    ################ Create SQL LogScout Main Job ################
    $LogScoutPathRoot = $LogScoutPath
    $LogScoutPath = $LogScoutPath +'\SQL_LogScout.cmd'

    #CMD looks for input for -Execute as C:\SQL_LogScout_v4.5_Signed\SQL_LogScout_v4.5_Signed\SQL_LogScout.cmd
    #The start date parameter is not provided below to New-ScheduledTaskAction as the job is invoked based on the task trigger above which does take the StartTime parameter. 
    #To reduce likelihood of issue, 2000 date is hardcoded.
    $actions = (New-ScheduledTaskAction -Execute $LogScoutPath -Argument "$Scenario $SQLInstance `"$OutputPath`" `"$DeleteFolderOrNew`" `"2000-01-01`" `"$endtime`" `"Quiet`"" -WorkingDirectory "$LogScoutPathRoot")


    #Set to run whether user is logged on or not.
    $principal = New-ScheduledTaskPrincipal -UserId $global:CurrentUserAccount -LogonType $LogonTypeInt -RunLevel Highest


    $settings = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries
    $task = New-ScheduledTask -Action $actions -Principal $principal -Trigger $trigger -Settings $settings
 

    #Write-Host "`nCreating '$CmdTaskName'... "
    Log-ScheduledTask -Message "Creating '$CmdTaskName'... "
    Register-ScheduledTask -TaskName $CmdTaskName -InputObject $task | Out-Null


    Log-ScheduledTask -Message "Success! Created Windows Task $CmdTaskName" -WriteToConsole $true -ConsoleMsgColor "Magenta"
    Log-ScheduledTask -Message "------------------------" -WriteToConsole $true
    
    $JobCreated = Get-ScheduledTask -TaskName $CmdTaskName | Select-Object -Property TaskName, State -ExpandProperty Actions | Select-Object TaskName, State, Execute, Arguments
    if ($null -ine $JobCreated)
    {
        foreach ($item in $JobCreated)
        {
        
            Log-ScheduledTask -Message ($item.TaskName.ToString() + " | " + $item.State.ToString() + " | " + $item.Execute.ToString() + " | " + $item.Arguments.ToString())
       
        }

    }    


    #future use: Get-ScheduledTask -TaskName $CmdTaskName | Select-Object -ExpandProperty Triggers | Select-Object -Property StartBoundary, ExecutonTimeLimit, Enabled -ExpandProperty Repetition




 ################ Create SQL LogScout Cleanup Job To Prevent Stale Windows Task Entries ################


    #If CreateCleanupJob is omitted, we can prompt user.
    if (($Once -ieq $true) -and ($null -ieq $CreateCleanupJob))
    {
        Log-ScheduledTask -Message "CreateCleanupJob omitted or provided as false"
        
        #Hardcode cleanup job running 11 hours if user didn't pass parameter. Only valid if user is using -Once.
        $CleanupDelay = '660'
            
        [datetime]$CleanupTaskExecutionTime = $StartTime.AddMinutes($CleanupDelay)
        $triggercleanup = New-ScheduledTaskTrigger -Once -At $CleanupTaskExecutionTime

        Log-ScheduledTask -Message "SQL Logscout task was created and was set to execute once." -WriteToConsole $true -ConsoleMsgColor "Green"
        Log-ScheduledTask -Message "Would you like to create a second job that will delete itself" -WriteToConsole $true -ConsoleMsgColor "Green"
        Log-ScheduledTask -Message "and the SQL LogScout task 11 hours after the provided endtime?" -WriteToConsole $true -ConsoleMsgColor "Green"
        Log-ScheduledTask -Message "------------------------" -WriteToConsole $true
        Log-ScheduledTask -Message "Provide Y or N." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        
        [string]$create_delete_task = $null

        while ( ($create_delete_task -ne "Y") -and ($create_delete_task -ne "N") )
        {
            $create_delete_task  = Read-Host "Automatically delete existing task 11 hours after scheduled endtime (Y/N)?"

            $create_delete_task  = $create_delete_task.ToString().ToUpper()
            if ( ($create_delete_task  -ne "Y") -and ($create_delete_task  -ne "N"))
            {
                Write-Host "Please provide 'Y' or 'N' to proceed"
            }
        }

        if ($create_delete_task -ieq 'N')
        {
            Log-ScheduledTask -Message "You declined to automatically delete the job. Please perform manual cleanup in Task Scheduler after logs are collected." -WriteToConsole $true -ConsoleMsgColor "DarkYellow"
        }
        else 
        {
            #2 action task to delete the logscout task and the cleanup job itself to be run 11 hours later
            $actionscleanup = (New-ScheduledTaskAction -Execute schtasks.exe -Argument "/Delete /TN `"$CmdTaskName`" /F")
            $actions2cleanup = (New-ScheduledTaskAction -Execute schtasks.exe -Argument "/Delete /TN `"$CleanupTaskName`" /F")
            $principalcleanup = New-ScheduledTaskPrincipal -UserId $global:CurrentUserAccount -LogonType $LogonTypeInt -RunLevel Highest
            $settingscleanup = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries
            #Actions are sequential
            $taskcleanup = New-ScheduledTask -Action $actionscleanup,$actions2cleanup -Principal $principalcleanup -Trigger $triggercleanup -Settings $settingscleanup
        
            Log-ScheduledTask -Message ("Creating " + $CleanupTaskName)
            Register-ScheduledTask -TaskName $CleanupTaskName  -InputObject $taskcleanup | Out-Null
        
        
            Log-ScheduledTask -Message "Success! Created Windows Task for SQL LogScout Cleanup ""$CleanupTaskName""" -WriteToConsole $true -ConsoleMsgColor "Magenta"
            Log-ScheduledTask -Message "------------------------" -WriteToConsole $true

            $CleanupTaskProperties = Get-ScheduledTask -TaskName $CleanupTaskName  | Select-Object -Property TaskName, State -ExpandProperty Actions | Select-Object TaskName, State, Execute, Arguments

            if ($null -ine $CleanupTaskProperties)
            {
                foreach ($item in $CleanupTaskProperties)
                {
                
                    Log-ScheduledTask -Message ($item.TaskName.ToString() + " | " + $item.State.ToString() + " | " + $item.Execute.ToString() + " | " + $item.Arguments.ToString())
            
                }
        
            }    
        }
    }
    #If set to run daily and CreateCleanupJob is null, prompt
    elseif (($Daily -ieq $true) -and ($null -ieq $CreateCleanupJob)) 
    {
        #Prompt user to delete and ask for a date/time to remove
        Log-ScheduledTask -Message "SQL Logscout task invoked to run daily." -WriteToConsole $true -ConsoleMsgColor "Green"
        Log-ScheduledTask -Message "Would you like to create a second job that will delete itself" -WriteToConsole $true -ConsoleMsgColor "Green"
        Log-ScheduledTask -Message "and the SQL LogScout task at the provided time?" -WriteToConsole $true -ConsoleMsgColor "Green"
        Log-ScheduledTask -Message "------------------------" -WriteToConsole $true
        #change time to be number of days.
        Log-ScheduledTask -Message "Enter the number of days after the start time for" -WriteToConsole $true -ConsoleMsgColor "Yellow"
        Log-ScheduledTask -Message "the cleanup job to run such as '60', or 'N'." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        Log-ScheduledTask -Message "If you wish to run indefinitely, provide 'N' and perform manual cleanup." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        [string]$daily_delete_task = $null

        #Check to make sure the value is a postive int or N.
        while ( ($daily_delete_task -inotmatch "^\d+$") -and ($daily_delete_task -ne "N") )
        {
            $daily_delete_task = Read-Host "Please provide response to cleanup job (NumberOfDays/N)?"

            $daily_delete_task = $daily_delete_task.ToString().ToUpper()
            if ( ($daily_delete_task -inotmatch "^\d+$") -and ($daily_delete_task -ne "N"))
            {
                Write-Host "Please provide Number of Days or 'N' to proceed"
            }
        }
        if ($daily_delete_task -ieq 'N')
        {
            Log-ScheduledTask -Message "You declined to automatically delete the job. Please perform manual cleanup in Task Scheduler after logs are collected." -WriteToConsole $true -ConsoleMsgColor "DarkYellow"
        }
        else 
        {
            $daily_delete_task = [int]$daily_delete_task
                #Calculate stoptime based on minutes provided to determine end time of LogScout
            if ($daily_delete_task -lt 1)
            {
                $daily_delete_task = 1
            }

            [datetime] $TimeForCleanup = $StartTime
            [datetime] $TimeForCleanup = $TimeForCleanup.AddDays($daily_delete_task)

            $triggercleanup = New-ScheduledTaskTrigger -Once -At $TimeForCleanup 
            
            #2 action task to delete the logscout task and the cleanup job itself to be run 11 hours later
            $actionscleanup = (New-ScheduledTaskAction -Execute schtasks.exe -Argument "/Delete /TN `"$CmdTaskName`" /F")
            $actions2cleanup = (New-ScheduledTaskAction -Execute schtasks.exe -Argument "/Delete /TN `"$CleanupTaskName`" /F")
            $principalcleanup = New-ScheduledTaskPrincipal -UserId $global:CurrentUserAccount -LogonType $LogonTypeInt -RunLevel Highest
            $settingscleanup = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries
            #Actions are sequential
            $taskcleanup = New-ScheduledTask -Action $actionscleanup,$actions2cleanup -Principal $principalcleanup -Trigger $triggercleanup -Settings $settingscleanup
        
            Log-ScheduledTask -Message ("Creating " + $CleanupTaskName)
            Register-ScheduledTask -TaskName $CleanupTaskName  -InputObject $taskcleanup | Out-Null
        
        
            Log-ScheduledTask -Message "Success! Created Windows Task for SQL LogScout Cleanup ""$CleanupTaskName""" -WriteToConsole $true -ConsoleMsgColor "Magenta"
            Log-ScheduledTask -Message "------------------------" -WriteToConsole $true

            $CleanupTaskProperties = Get-ScheduledTask -TaskName $CleanupTaskName  | Select-Object -Property TaskName, State -ExpandProperty Actions | Select-Object TaskName, State, Execute, Arguments

            if ($null -ine $CleanupTaskProperties)
            {
                foreach ($item in $CleanupTaskProperties)
                {
                
                    Log-ScheduledTask -Message ($item.TaskName.ToString() + " | " + $item.State.ToString() + " | " + $item.Execute.ToString() + " | " + $item.Arguments.ToString())
               
                }
        
            }    
        }
    }


    #If user explicitly passes parameters, allows us to silently create. We check earlier that they passed the other parameters with CreateCleanupJob
    elseif ($CreateCleanupJob -ieq $true)
    {
        #user provided parameters for cleanup task, so don't prompt and just create the job.
        Log-ScheduledTask -Message "Cleanup job parameters provided. Creating cleanup task silently." -WriteToConsole $true -ConsoleMsgColor "Green"

        $triggercleanup = New-ScheduledTaskTrigger -Once -At $CleanupJobTime
        $actionscleanup = (New-ScheduledTaskAction -Execute schtasks.exe -Argument "/Delete /TN `"$CmdTaskName`" /F")
        $actions2cleanup = (New-ScheduledTaskAction -Execute schtasks.exe -Argument "/Delete /TN `"$CleanupTaskName`" /F")
        $principalcleanup = New-ScheduledTaskPrincipal -UserId $global:CurrentUserAccount -LogonType $LogonTypeInt -RunLevel Highest
        $settingscleanup = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries
        #Actions are sequential
        $taskcleanup = New-ScheduledTask -Action $actionscleanup,$actions2cleanup -Principal $principalcleanup -Trigger $triggercleanup -Settings $settingscleanup

        Log-ScheduledTask -Message ("Creating " + $CleanupTaskName)
        Register-ScheduledTask -TaskName $CleanupTaskName  -InputObject $taskcleanup | Out-Null


        Log-ScheduledTask -Message "Success! Created Windows Task for SQL LogScout Cleanup ""$CleanupTaskName""" -WriteToConsole $true -ConsoleMsgColor "Magenta"
        Log-ScheduledTask -Message "------------------------" -WriteToConsole $true

        $CleanupTaskProperties = Get-ScheduledTask -TaskName $CleanupTaskName  | Select-Object -Property TaskName, State -ExpandProperty Actions | Select-Object TaskName, State, Execute, Arguments
        if ($null -ine $CleanupTaskProperties)
                {
                    foreach ($item in $CleanupTaskProperties)
                    {
                    
                        Log-ScheduledTask -Message ($item.TaskName.ToString() + " | " + $item.State.ToString() + " | " + $item.Execute.ToString() + " | " + $item.Arguments.ToString())
                
                    }
            
                }    
    }
    #If user explicitly said to not create the job, just log a message and don't create the cleanup job.
    elseif  ($CreateCleanupJob -ieq $false)
    {
        Log-ScheduledTask -Message "CreateCleanupJob provided as false. Not creating cleanup task. Please clean up Windows Task Scheudler manually." -WriteToConsole $true -ConsoleMsgColor "Yellow"
    }
    

 ################ Log Completion ################
    Log-ScheduledTask -Message "Thank you for using SQL LogScout! Exiting..." -WriteToConsole $true -ConsoleMsgColor "Green"
    Start-Sleep -Seconds 3
}

catch 
{
    HandleCatchBlock -function_name "ScheduleSQLLogScoutTask" -err_rec $PSItem
}
