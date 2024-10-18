<#
written by 
 James.Ferebee @microsoft.com
 PijoCoder @github.com

.SYNOPSIS
  Test Powershell script to create task in Windows Task Scheduler to invoke SQL LogScout.
.LINK 
  https://github.com/microsoft/SQL_LogScout
.EXAMPLE
  .\ScheduleSQLLogScoutAsTask.ps1 -LogScoutPath "C:\temp\log scout\Test 2" -Once -Scenario "GeneralPerf" -SQLInstance "Server1\sqlinst1" 
  -OutputPath "C:\temp\log scout\test 2" -CmdTaskName "First SQLLogScout Capture" -DeleteFolderOrNew "DeleteDefaultFolder" 
  -StartTime "+00:05:00" -EndTime "+00:10:00"
#> 

param
(
    #Implement params to have the script accept parameters which is then provided to Windows Task Scheduler LogScout command
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
    #We are in bin, but have the output file write to the root LogScout folder.
    [string] $OutputPath = (Get-Item (Get-Location)).Parent.FullName,

    #Name of the Task. Use a unique name to create multiple scheduled runs. Defaults to "SQL LogScout Task" if omitted.
    [Parameter(Position=4, Mandatory=$false)]
    [string] $CmdTaskName = "SQL LogScout Task",
    
    #Delete existing folder or create new one.
    [Parameter(Position=5, Mandatory=$false)]
    [string] $DeleteFolderOrNew = "NewCustomFolder",

    #Start time of collector. Defines scheduled task start time. 2022-09-29 21:26:00
    [Parameter(Position=6,Mandatory=$false)]
    [string] $StartTime = "0000",
    
    #How long to execute the collector. In minutes.
    [Parameter(Position=7,Mandatory=$true)]
    [string] $EndTime = "0000",

    #schedule it for one execution
    [Parameter(Position=8, Mandatory=$false)]
    [switch] $Once = $false,

    #schedule it daily at the specified time
    [Parameter(Position=9, Mandatory=$false)]
    [switch] $Daily = $false,

    #run continuously
    [Parameter(Position=10, Mandatory=$false)]
    [switch] $Continuous = $false,

    #schedule it daily at the specified time
    [Parameter(Position=11, Mandatory=$false)]
    [nullable[boolean]] $CreateCleanupJob = $null,

    #schedule it daily at the specified time
    [Parameter(Position=12, Mandatory=$false)]
    [nullable[datetime]] $CleanupJobTime = $null,

    #schedule it daily at the specified time
    [Parameter(Position=13, Mandatory=$false)]
    [string] $LogonType = $null,

    #how long to loop through repetition (total time to run LogScout from windows task scheduler). Convert to timestamp
    [Parameter(Position=14, Mandatory=$false)]
    [int] $RepeatCollections

)


################ Globals ################

[string]$global:CurrentUserAccount = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
#Value used for LogScout invocation. For starttime, will keep relative format.
$global:gStartTime = New-Object -TypeName PSObject -Property @{DateAndOrTime = ""; Relative = $false}
$global:gEndTime = New-Object -TypeName PSObject -Property @{DateAndOrTime = ""; Relative = $false}
$global:gBinPath = (Get-Item -Path ".\" -Verbose).FullName
[datetime]$global:gScheduledTaskStartTime = [datetime]::MinValue

$script:InvalidValue = 0
$script:DefaultValue = 1
$script:DateTimeValue = 2
$script:RelativeTimeValue = 3

################ Import Modules for Shared Functions ################



################ Functions ################
function ScheduledTaskHandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit = $false)
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

    if ($exit -eq $true)
    {
        Log-ScheduledTask -Message "Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 2
        exit
    }
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
        ScheduledTaskHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit $true
    }

}
function ValidateTimeParameter([string]$timeParameter) 
{
    <#
    .DESCRIPTION
        ValidateTimeParameter does verification on the time parameter and sets the appropriate globals.
    #> 
    try
    {
        Log-ScheduledTask -Message "Validating $timeParameter" -WriteToConsole $false

        #If time parameter is provided, validate it.
        if ($timeParameter -ne "0000" -and ($false -eq [String]::IsNullOrWhiteSpace($timeParameter))) 
        {
            [DateTime] $dtOut = New-Object DateTime
            [string] $regexRelativeTime = "^\+(0?[0-9]|1[01]):[0-5][0-9]:[0-5][0-9]$"
            if ($true -eq [DateTime]::TryParse($timeParameter, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dtOut)) 
            {
                return $script:DateTimeValue
            } 
            elseif ($timeParameter -match $regexRelativeTime) 
            {
                return $script:RelativeTimeValue
            } 
            else 
            {
                Log-ScheduledTask "ValidateTimeParameter skipped due to null" -WriteToConsole $false
                return $script:InvalidValue
            }
        }
        elseif ($timeParameter -eq "0000")
        {
            Log-ScheduledTask -Message "User kept default parameter" -WriteToConsole $false
            return $script:DefaultValue
        }
        else
        {
            Log-ScheduledTask -Message "ERROR: Invalid or null time parameter provided. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
            Start-Sleep -Seconds 4
            exit
        }
    }
    catch
    {
		#Write-Error -Exception $_.Exception
        ScheduledTaskHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit $true
    }
}


function SetTimeGlobals([string]$ValidationOutput,[string]$StartOrEnd)
{
    <#
    .DESCRIPTION
        SetTimeGlobals sets the global variables for the start and end times based on the validation output.
    #> 
    try
    {
        Log-ScheduledTask -Message "inside SetTimeGlobals. Values: $ValidationOutput | $StartOrEnd" -WriteToConsole $false

        if ($StartOrEnd -eq "StartTime")
        {
            if ($ValidationOutput -eq $script:DefaultValue)
            {
                [datetime]$CurrentTime = Get-Date
                $global:gStartTime.DateAndOrTime = $CurrentTime.AddMinutes(2)
                $global:gScheduledTaskStartTime = $CurrentTime.AddMinutes(2)
                $global:gStartTime.Relative = $false
                Log-ScheduledTask -Message "ScheduledTaskStartTime is $global:gScheduledTaskStartTime"
                Log-ScheduledTask -Message "Start time was not set. The job is set to start 2 minutes from now" -WriteToConsole $true -ConsoleMsgColor "Yellow"
            }

            elseif ($ValidationOutput -eq $script:DateTimeValue)
            {
                [datetime]$global:gStartTime.DateAndOrTime = $StartTime
                $global:gStartTime.Relative = $false
                $global:gScheduledTaskStartTime = $StartTime
            }

            elseif ($ValidationOutput -eq $script:RelativeTimeValue)
            {
                $global:gStartTime.DateAndOrTime = $StartTime
                $global:gScheduledTaskStartTime = ParseRelativeTimeSchTask -relativeTime $StartTime -baseDateTime (Get-Date)
                Log-ScheduledTask -Message "ScheduledTaskStartTime is $global:gScheduledTaskStartTime"
                $global:gStartTime.Relative = $true
            }
            else 
            {
                Log-ScheduledTask -Message "StartTime identified but unexpected validation output. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }
        }

        elseif ($StartOrEnd -eq "EndTime")
        {
            if ($ValidationOutput -eq $script:DefaultValue)
            {
                Log-ScheduledTask -Message "ERROR: -EndTime omitted. Re-run with endtime." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }
            
            elseif ($ValidationOutput -eq $script:DateTimeValue)
            {
                [datetime]$global:gEndTime.DateAndOrTime = $EndTime
                $global:gEndTime.Relative = $false
            }

            elseif ($ValidationOutput -eq $script:RelativeTimeValue)
            {
                $global:gEndTime.DateAndOrTime = $EndTime
                $global:gEndTime.Relative = $true
            }
            else 
            {
                Log-ScheduledTask -Message "EndTime identified but unexpected validation output. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }
        }
        
        else
        {
            Log-ScheduledTask -Message "ERROR: Invalid SetTimeGlobals. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
            Start-Sleep -Seconds 4
            exit
        }

    }
    catch
    {
        #Write-Error -Exception $_.Exception
        ScheduledTaskHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit $true
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
        [string]$Message = (Get-Date -Format("yyyy-MM-dd HH:mm:ss.ms")) + ': '+ $Message
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
        ScheduledTaskHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit $true
    }
}


function ParseRelativeTimeSchTask ([string]$relativeTime, [datetime]$baseDateTime)
{
    
    try 
    {
        #declare a new datetime variable and set it to min value (can't be null)
        [datetime] $formatted_time = [DateTime]::MinValue

        # first remove the + sign
        $relativeTime  = $relativeTime.TrimStart("+") 
    
        # split the string by :
        $time_parts = $relativeTime.Split(":") 

        # assign the each part to hours, minutes and seconds vars
        $hours = $time_parts[0] 
        $minutes = $time_parts[1]
        $seconds = $time_parts[2] 


        #create a new timespan object
        $timespan = New-TimeSpan -Hours $hours -Minutes $minutes -Seconds $seconds 

        #add the TimeSpan to the current date and time
        if($baseDateTime -ne $null)
        {
            # this is the normal case. add the timespan from relative time to the base datetime
            $formatted_time = $baseDateTime.Add($timespan) 
        }
        else 
        {
            # this is last resort in case null time is passed as a parm -not presice but better than failing
            $baseDateTime = (Get-Date).Add($timespan)
        }
        


        return $formatted_time

    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function CreateCleanupJobTask([datetime]$ExecutionTime)
{
    try
    {
        $triggercleanup = New-ScheduledTaskTrigger -Once -At $ExecutionTime
        Log-ScheduledTask -Message "Creating Cleanup Task for $SQLInstance" -WriteToConsole $true -ConsoleMsgColor "Yellow"
        $actionscleanup = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ("-File `"" + $IncompleteShutdownPath + "`" -ServerName `"" + $SQLInstance + "`" -EndActiveConsoles") -WorkingDirectory $global:gBinPath
        $actions2cleanup = (New-ScheduledTaskAction -Execute schtasks.exe -Argument "/Delete /TN `"$CmdTaskName`" /F")
        $actions3cleanup = (New-ScheduledTaskAction -Execute schtasks.exe -Argument "/Delete /TN `"$CleanupTaskName`" /F")
        $principalcleanup = New-ScheduledTaskPrincipal -UserId $global:CurrentUserAccount -LogonType $LogonTypeInt -RunLevel Highest
        $settingscleanup = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries
        #Actions are sequential
        $taskcleanup = New-ScheduledTask -Action $actionscleanup,$actions2cleanup,$actions3cleanup -Principal $principalcleanup -Trigger $triggercleanup -Settings $settingscleanup
    
        Log-ScheduledTask -Message ("Creating " + $CleanupTaskName)
        Register-ScheduledTask -TaskName $CleanupTaskName  -InputObject $taskcleanup -ErrorAction Stop | Out-Null
    
    
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
    catch
    {
        ScheduledTaskHandleCatchBlock -function_name "CreateCleanupJob" -err_rec $PSItem -exit $true
    }
}

################ Log initialization ################
Initialize-ScheduledTaskLog

Log-ScheduledTask -Message "Creating SQL LogScout as Task" -WriteToConsole $true -ConsoleMsgColor "Green"

#Log all the input parameters used for the scheduled task for debugging purposes
foreach ($param in $PSCmdlet.MyInvocation.BoundParameters.GetEnumerator()) 
{
    Log-ScheduledTask "PARAMETER USED: $($param.Key): $($param.Value)" -WriteToConsole $false
}

################ Validate parameters and date ################
try 
#later add check to make sure SQL_LogScout exists in directory.
{
    #LogScout Path Logic
    if ($true -ieq [string]::IsNullOrEmpty($LogScoutPath))
    {
        #Since LogScout is not in bin, we need to back out one directory to execute LogScout
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

    
    SetTimeGlobals -ValidationOutput (ValidateTimeParameter $StartTime) -StartOrEnd "StartTime"
    SetTimeGlobals -ValidationOutput (ValidateTimeParameter $EndTime) -StartOrEnd "EndTime"

    
    #Verify provided date for LogScout is in the future
    [DateTime] $CurrentTime = Get-Date
    if ($CurrentTime -gt $global:gScheduledTaskStartTime)
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
            #Get duration of LogScout and cleanup 
            $timediff = New-TimeSpan -Start $global:gScheduledTaskStartTime -End $CleanupJobTime

            #If cleanup job is set to run in the past, throw error.
            if ($CurrentTime -gt $CleanupJobTime)
            {
                Log-ScheduledTask -Message "ERROR: Cleanup Job Time Date or time provided is in the past. Please provide a future date/time. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }

            #Verify job is to be running once and that cleanupjobtime is after invocation start.
            if ($global:gScheduledTaskStartTime -ige $CleanupJobTime)
            {
                Log-ScheduledTask -Message "ERROR: LogScout configured to run after cleanup. Please correct the execution times. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }

            #Get minutes between cleanup job and current time. If less than 5, throw error so LogScout has some time to shut down.
            elseif ($timediff.TotalMinutes -le "5")
            {
                Log-ScheduledTask -Message "ERROR: CleanupJobTime parameter was provided but is within 5 minutes of LogScout start time. Please provide a value greater than 5 minutes. Exiting.." -WriteToConsole $true -ConsoleMsgColor "Red"
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

    ###Cleanup Job Parameter Validation###

    else
    {
        Log-ScheduledTask -Message "CreateCleanupJob not provided. No validation performed on CleanupJobTime."
    }

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

    #Main LogScout job parameter validation
    if ([string]::IsNullOrEmpty($DeleteFolderOrNew) -or $DeleteFolderOrNew -ieq 'DeleteDefaultFolder') 
    {
        $DeleteFolderOrNew = 'DeleteDefaultFolder'
    } 
    elseif ($DeleteFolderOrNew -ieq 'NewCustomFolder') 
    {
        $DeleteFolderOrNew = 'NewCustomFolder'
    } 
    #Check if the value passed is a positive whole number
    elseif ($DeleteFolderOrNew -match '^[1-9]\d*$') 
    {
        $NumberOfFilesToRetain = [int]$DeleteFolderOrNew
    }
    else 
    {
        Log-ScheduledTask -Message "ERROR: Please specify a valid parameter for DeleteFolderOrNew. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        exit
    }
    

    

    #define the schedule (execution time) - either run it one time (Once) or every day at the same time (Daily)
    #Verify both Once and Daily aren't provided. If so, exit.

    $switches = @($Once, $Daily, $Continuous)
    $switchCount = ($switches | Where-Object { $_ }).Count
    if (-not ($Once -or $Daily -or $Continuous) -or ($switchCount -gt 1)) 
    {
        Log-ScheduledTask -Message "ERROR: You must specify exactly one of the following switches: -Once, -Daily, -Continuous." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }

    if ($Once -ieq  $true)
    {
        $trigger = New-ScheduledTaskTrigger -Once -At $global:gScheduledTaskStartTime
    }
    elseif ($Daily -ieq $true) 
    {
        #Convert date/time of starttime to different format to prevent skipping a day in collection.'2022-08-24 08:26:00' becomes 8:26:00 AM
        if ($global:gEndTime.Relative -ieq $true)
        {
            #gScheduledTaskStartTime is already set for the start time. We just need to convert it to the correct format for windows task scheduler
            $DailyTimeFormat = Get-Date $global:gScheduledTaskStartTime -DisplayHint Time
            $trigger = New-ScheduledTaskTrigger -Daily -At $DailyTimeFormat 
        }
        else
        {
            Log-ScheduledTask -Message "ERROR: Relative time required for daily job. Please provide a relative time for the EndTime parameter. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
            Start-Sleep -Seconds 4
            exit
        }
    }
    elseif ($Continuous -ieq $true) 
    {
        if ($global:gEndTime.Relative -ieq $true)
        {            
            if (($RepeatCollections -le 0) -or ($null -eq $RepeatCollections))
            {
                Log-ScheduledTask -Message "ERROR: Continuous parameter passed but -RepeatCollections is invalid. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
                Start-Sleep -Seconds 4
                exit
            }
            
            #gScheduledTaskStartTime is already set for the start time. We just need to convert it to the correct format for windows task scheduler
            $trigger = New-ScheduledTaskTrigger -Once -At $global:gScheduledTaskStartTime
        }
        else 
        {
            Log-ScheduledTask -Message "ERROR: Relative end time required for continuous job. Please provide a relative time for the EndTime parameters such as "+00:15:00". Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
            Start-Sleep -Seconds 4
            exit
        }

    }
    else 
    {
        Log-ScheduledTask -Message "ERROR: Please specify only '-Once','-Daily', or '-Continuous' parameter. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }

    #Verify RepeatCollections is only used for Continuous scenarios
    if ($RepeatCollections -gt 0 -and $Continuous -ieq $false)
    {
        Log-ScheduledTask -Message "ERROR: RepeatCollections parameter passed but Continuous switch omitted. RepeatCollections only valid for Continuous scenarios. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
        Start-Sleep -Seconds 4
        exit
    }

    Log-ScheduledTask -Message "$NumberOfFilesToRetain folders will be retained based on -DeleteFolderOrNew" -WriteToConsole $false      
    #Verify RepeatCollections is greater than number of files to retain and not null
    if (($RepeatCollections -le $NumberOfFilesToRetain) -and ($Continuous -ieq $true))
    {
        Log-ScheduledTask -Message "ERROR: -RepeatCollections ($RepeatCollections) is less than or equal to -DeleteFolderOrNew ($NumberOfFilesToRetain) file retention setting. RepeatCollection value must be greater than files retained. Exiting..." -WriteToConsole $true -ConsoleMsgColor "Red"
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
        Log-ScheduledTask -Message "SQL LogScout task already exists. Would you like to delete associated tasks and continue? Provide Y or N." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        
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
            Unregister-ScheduledTask -TaskName $CmdTaskName -Confirm:$false -ErrorAction Stop
        }

     
    }

    #If cleanup task exists for provided input, remove it
    if ($LogScoutCleanupScheduleTaskExists)
    {
        Log-ScheduledTask -Message "SQL LogScout *Cleanup* task already exists. Removing the task." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        Unregister-ScheduledTask -TaskName $CleanupTaskName -Confirm:$false -ErrorAction Stop
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
    $LogScoutPath = $LogScoutPath +'\SQL_LogScout.ps1'
    $IncompleteShutdownPath = $gBinPath  + '\CleanupIncompleteShutdown.ps1'

    try 
    {
        #CMD looks for input for -Execute as C:\SQL_LogScout_v4.5_Signed\SQL_LogScout_v4.5_Signed\SQL_LogScout.cmd
        #The start date parameter is not provided below to New-ScheduledTaskAction as the job is invoked based on the task trigger above which does take the StartTime parameter. 
        $actions = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ("-File `"" + $LogScoutPath + "`" -Scenario " + $Scenario + " -ServerName " + $SQLInstance + " -CustomOutputPath `"" + $OutputPath + "`" -DeleteExistingOrCreateNew `"" + $DeleteFolderOrNew + "`" -DiagStartTime `"" + $global:gScheduledTaskStartTime + "`" -DiagStopTime `"" + $EndTime + "`" -InteractivePrompts `"Quiet`" -RepeatCollections " + [string]$RepeatCollections) -WorkingDirectory $LogScoutPathRoot



        #Set to run whether user is logged on or not.
        $principal = New-ScheduledTaskPrincipal -UserId $global:CurrentUserAccount -LogonType $LogonTypeInt -RunLevel Highest


        $settings = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries
        $task = New-ScheduledTask -Action $actions -Principal $principal -Trigger $trigger -Settings $settings
    

        #Write-Host "`nCreating '$CmdTaskName'... "
        Log-ScheduledTask -Message "Creating '$CmdTaskName'... "

        Register-ScheduledTask -TaskName $CmdTaskName -InputObject $task -ErrorAction Stop | Out-Null
    



        Log-ScheduledTask -Message "Success! Created Windows Task $CmdTaskName" -WriteToConsole $true -ConsoleMsgColor "Magenta"
        Log-ScheduledTask -Message "------------------------" -WriteToConsole $true
        
        $JobCreated = Get-ScheduledTask -TaskName $CmdTaskName -ErrorAction Stop| Select-Object -Property TaskName, State -ExpandProperty Actions | Select-Object TaskName, State, Execute, Arguments
        if ($null -ine $JobCreated)
        {
            foreach ($item in $JobCreated)
            {
            
                Log-ScheduledTask -Message ($item.TaskName.ToString() + " | " + $item.State.ToString() + " | " + $item.Execute.ToString() + " | " + $item.Arguments.ToString())
        
            }

        }    
    }
    catch 
    {
        ScheduledTaskHandleCatchBlock -function_name "ScheduleSQLLogScoutTask" -err_rec $PSItem -exit $true
    }


    #future use: Get-ScheduledTask -TaskName $CmdTaskName | Select-Object -ExpandProperty Triggers | Select-Object -Property StartBoundary, ExecutonTimeLimit, Enabled -ExpandProperty Repetition




 ################ Create SQL LogScout Cleanup Job To Prevent Stale Windows Task Entries ################

    try {
    
        #If CreateCleanupJob is omitted, we can prompt user.
        if (($Once -ieq $true) -and ($null -ieq $CreateCleanupJob))
        {
            Log-ScheduledTask -Message "CreateCleanupJob omitted or provided as false"
            
            #Hardcode cleanup job running 11 hours if user didn't pass parameter. Only valid if user is using -Once.
            $CleanupDelay = '660'
                
            [datetime]$CleanupTaskExecutionTime = $global:gScheduledTaskStartTime.AddMinutes($CleanupDelay)

            Log-ScheduledTask -Message "SQL LogScout task was created and was set to execute once." -WriteToConsole $true -ConsoleMsgColor "Green"
            Log-ScheduledTask -Message "Would you like to create a second job that will delete itself" -WriteToConsole $true -ConsoleMsgColor "Green"
            Log-ScheduledTask -Message "and the SQL LogScout task 11 hours after the provided endtime?" -WriteToConsole $true -ConsoleMsgColor "Green"
            Log-ScheduledTask -Message "This will terminate ALL SQL LogScout sessions for the specified SQL Server instance" -WriteToConsole $true -ConsoleMsgColor "Green"
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
                CreateCleanupJobTask($CleanupTaskExecutionTime)
            }
        }
        #If set to run daily and CreateCleanupJob is null, prompt
        elseif (($Daily -ieq $true -or $Continuous -ieq $true) -and ($null -ieq $CreateCleanupJob)) 
        {
            #Prompt user to delete and ask for a date/time to remove
            Log-ScheduledTask -Message "SQL LogScout task invoked to run daily or continuous." -WriteToConsole $true -ConsoleMsgColor "Green"
            Log-ScheduledTask -Message "Would you like to create a second job that will delete itself" -WriteToConsole $true -ConsoleMsgColor "Green"
            Log-ScheduledTask -Message "and the SQL LogScout task at the provided time?" -WriteToConsole $true -ConsoleMsgColor "Green"
            Log-ScheduledTask -Message "This will terminate ALL SQL LogScout sessions for the specified SQL Server instance" -WriteToConsole $true -ConsoleMsgColor "Green"
            Log-ScheduledTask -Message "------------------------" -WriteToConsole $true
            #change time to be number of days.
            Log-ScheduledTask -Message "Enter the number of days after the start time for" -WriteToConsole $true -ConsoleMsgColor "Yellow"
            Log-ScheduledTask -Message "the cleanup job to run such as '60', or 'N'." -WriteToConsole $true -ConsoleMsgColor "Yellow"
            Log-ScheduledTask -Message "If you wish to preserve the created task, type 'N' and clean it up manually." -WriteToConsole $true -ConsoleMsgColor "Yellow"
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

                [datetime] $TimeForCleanup = $global:gScheduledTaskStartTime
                [datetime] $TimeForCleanup = $TimeForCleanup.AddDays($daily_delete_task)

                CreateCleanupJobTask($TimeForCleanup)
            }
        }


        #If user explicitly passes parameters, allows us to silently create. We check earlier that they passed the other parameters with CreateCleanupJob
        elseif ($CreateCleanupJob -ieq $true)
        {
            #user provided parameters for cleanup task, so don't prompt and just create the job.
            Log-ScheduledTask -Message "Cleanup job parameters provided. Creating cleanup task silently." -WriteToConsole $true -ConsoleMsgColor "Green"

            CreateCleanupJobTask($CleanupJobTime)
        }

        #If user explicitly said to not create the job, just log a message and don't create the cleanup job.
        elseif  ($CreateCleanupJob -ieq $false)
        {
            Log-ScheduledTask -Message "CreateCleanupJob provided as false. Not creating cleanup task. Please clean up Windows Task Scheudler manually." -WriteToConsole $true -ConsoleMsgColor "Yellow"
        }
    }
    catch 
    {
        ScheduledTaskHandleCatchBlock -function_name "ScheduleSQLLogScoutTask" -err_rec $PSItem -exit $true
    }
    

 ################ Log Completion ################
    Log-ScheduledTask -Message "Thank you for using SQL LogScout! Exiting..." -WriteToConsole $true -ConsoleMsgColor "Green"
    Start-Sleep -Seconds 3
}

catch 
{
    ScheduledTaskHandleCatchBlock -function_name "ScheduleSQLLogScoutTask" -err_rec $PSItem -exit $true
}
