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
        [string]$LogFilePath,
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
        #Create log file in temp directory using full path. The temp var can come back as 8.3 format and so ensure we have the full path.
        $shortEnvTempPath = $env:TEMP
        $LogFilePath = (Get-Item $shortEnvTempPath).FullName

        #Cache LogFileName withotu date so we can delete old records properly
        $LogFileNameStringToDelete = $LogFileName

        #update file with date
        $LogFileName = $LogFileName + (Get-Date -Format "yyyyMMddTHHmmssffff") + ".log"
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

# SIG # Begin signature block
# MIIsDwYJKoZIhvcNAQcCoIIsADCCK/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCIqPMlxGM2Hfdy
# Dbb3/hYqVHkpDw28ySJrG0UwLJvB4qCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKqIV+keB6RO
# 1IPv6KeaPCCUz25OXgt4+F0W6+iI6XzTMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAgUDCyjuJa+Zw3fgnsn+RZHvjuOSeaET4bu0LvqXc7VXW
# S+yVngGVdumEFSPAMMkE6Y7W4BqAfBqnP1BAYIk8xlGbczSXUbvVZIAfaKajmjbU
# bbCi6pRUVr5UznbksYCkoKX8sT1UCrH46u3pya5NVFW7CCGY1ABH3ABiCrYhf59N
# X6YHPgfnB1U4FJPCGhvf57T0xl5ifxTZphyjIujOz2De+545ZkTNyziowKsOcy3Y
# zj6F4xqFJJJT66//dBYXglVWjLZxufJw48fYT1Cm/vSn60q8c6jV7M6Oqh6klPyP
# +Q11el2sCJCHu3s5MMgN3jwtRMjsD+o5nuLNKaPoC6GCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCBnsQPnttHa76k0skeb63YwySSraHoI9zAjDcecqgMG
# AgIGaXPPgDzIGBMyMDI2MDIwNDE2MzUyOC4yNzdaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACGCXZkgXi5+Xk
# AAEAAAIYMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgyNVoXDTI2MTExMzE4NDgyNVowgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjRDMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAsdzo6uuQ
# JqAfxLnvEBfIvj6knK+p6bnMXEFZ/QjPOFywlcjDfzI8Dg1nzDlxm7/pqbvjWhyv
# azKmFyO6qbPwClfRnI57h5OCixgpOOCGJJQIZSTiMgui3B8DPiFtJPcfzRt3Fsnx
# jLXwBIjGgnjGfmQl7zejA1WoYL/qBmQhw/FDFTWebxfo4m0RCCOxf2qwj31aOjc2
# aYUePtLMXHsXKPFH0tp5SKIF/9tJxRSg0NYEvQqVilje8aQkPd3qzAux2Mc5HMSK
# 4NMTtVVCYAWDUZ4p+6iDI9t5BNCBIsf5ooFNUWtxCqnpFYiLYkHfFfxhVUBZ8LGG
# xYsA36snD65s2Hf4t86k0e8WelH/usfhYqOM3z2yaI8rg08631IkwqUzyQoEPqMs
# HgBem1xpmOGSIUnVvTsAv+lmECL2RqrcOZlZax8K0aiij8h6UkWBN2IA/ikackTS
# GVRBQmWWZuLFWV/T4xuNzscC0X7xo4fetgpsqaEA0jY/QevkTvLv4OlNN9eOL8LN
# h7Vm0R65P7oabOQDqtUFAwCgjgPJ0iV/jQCaMAcO3SYpG5wSAYiJkk4XLjNSlNxU
# 2Idjs1sORhl7s7LC6hOb7bVAHVwON74GxfFNiEIA6BfudANjpQJ0nUc/ppEXpT4p
# gDBHsYtV8OyKSjKsIxOdFR7fIJIjDc8DvUkCAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBQkLqHEXDobY7dHuoQCBa4sX7aL0TAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# nkjRhjwPgdoIpvt4YioT/j0LWuBxF3ARBKXDENggraKvC0oRPwbjAmsXnPEmtuo5
# MD8uJ9Xw9eYrxqqkK4DF9snZMrHMfooxCa++1irLz8YoozC4tci+a4N37Sbke1pt
# 1xs9qZtvkPgZGWn5BcwVfmAwSZLHi2CuZ06Y0/X+t6fNBnrbMVovNaDX4WPdyI9G
# EzxfIggDsck2Ipo4VXL/Arcz7p2F7bEZGRuyxjgMC+woCkDJaH/yk/wcZpAsixe4
# POdN0DW6Zb35O3Dg3+a6prANMc3WIdvfKDl75P0aqcQbQAR7b0f4gH4NMkUct0Wm
# 4GN5KhsE1YK7V/wAqDKmK4jx3zLz3a8Hsxa9HB3GyitlmC5sDhOl4QTGN5kRi6oC
# oV4hK+kIFgnkWjHhSRNomz36QnbCSG/BHLEm2GRU9u3/I4zUd9E1AC97IJEGfwb+
# 0NWb3QEcrkypdGdWwl0LEObhrQR9B1V7+edcyNmsX0p2BX0rFpd1PkXJSbxf8IcE
# iw/bkNgagZE+VlDtxXeruLdo5k3lGOv7rPYuOEaoZYxDvZtpHP9P36wmW4INjR6N
# Inn2UM+krP/xeLnRbDBkm9RslnoDhVraliKDH62BxhcgL9tiRgOHlcI0wqvVWLdv
# 8yW8rxkawOlhCRqT3EKECW8ktUAPwNbBULkT+oWcvBcwggdxMIIFWaADAgECAhMz
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
# bGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAnWtGrXWiuNE8QrKfm4Ct
# Gr57z+mggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0tdnQwIhgPMjAyNjAyMDQwNzQwMzZaGA8yMDI2MDIwNTA3
# NDAzNlowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7S12dAIBADAKAgEAAgIMLgIB
# /zAHAgEAAgIULzAKAgUA7S7H9AIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IB
# AQCtZZrwK3OPil4hhrCGpE+e5Z4ycXzwOd99g+5mSg6vFuvfPw+VJpMMChqhX9SR
# 47z94TBFMgAj1LVRXK2pFHqwNMl8rIzkNBWrT6s6wD8sEDjSBydHeVysGhxeAqk8
# nY/rMeocZ3o4KpANhdb9husglZH0K6a757mCRwG0afPQIyH9rrauPfxfBq65WGxt
# GZUE9OqXMjUrYHKsxV5nVWASwCdU2tYVpQHiRP5FrkTm8RyEaj4G3+VrjNLSfnTH
# +gI9L1nT+tWtFQWs/6HIJTei17WT4i4FlUJmTwkpWto5ibdSKCncFUK+dyz1UFVl
# LZa3clw3aFOwzdWhs8f26Fh2MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIYJdmSBeLn5eQAAQAAAhgwDQYJYIZIAWUDBAIB
# BQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgDDQs1UVS+deDAWi76GG7KDZm79G2mAB/11IyDAon1cYwgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCCZE9yJuOTItIwWaES6lzGKK1XcSoz1ynRzaOVzx9eF
# ajCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACGCXZ
# kgXi5+XkAAEAAAIYMCIEIGiV6HeMUIMRr3E3MENsJ7dCIGtaBUCnAiB1RXGnwc1o
# MA0GCSqGSIb3DQEBCwUABIICAI67EIvgT+AoaCvPFH8BhoMspsbQ1K8EOR3n+ZbV
# qpRArrrPYmr9GUtm5BOnZ0/0eTzNws2aa2aSpdeZZAu6KJgnGZbghhzlsuQsICu0
# 5DjCzJjC3LpHXVmAnp5F4lv7cV1oe9cXW8h9bndVwfKY53XqtA6lr01Dd5SXwc6N
# /vXVutNhf4C+n0b5qTCGD0CleV8TRS9ui5J0JG2LdcGnBOEyDP1OFZ5S/dM3ydtt
# YVTW3/w0o/TjCK3JvTWYEFXY8qoitHINpY/nDxNZzWZN5yhIaUA+L2HcjZLvUh0g
# 1pZMY9M7qP2dMyZrF8ivTnp47iV4Lt7NDwZ0heRSBCsCc2ghK16Sv8CgXgVlaZ2C
# 90JI+rEgB8bTRd/F/WmJl9V5wDijkDAE5Tr/v/97Ih2UDk1qApqIlzDAkhxIkcYB
# vWwOGOqz5p7Yt2ySy1uzbWCeG4/u2AmgCyL5XsUXNw7WwoARM8+4PuLsx+sCQKp0
# 25EuMuZzxXZy1B4/qesTq4HlFBt2xKLe4ZZAMTtc/Frmp6uErT7DTSS7OaC4vOr2
# qdgtZZQWZCHGTz1LtLHQAk3xYiX855Qti/ua0z5p4k7Xb9KlIYLgkKEKqjd8MqTj
# 8J9KtZTAfNMg8xpHi0Td1no8j6GqivBM1FuO20awBATJFM/RyQe9hCSwuptaADOt
# IzP1
# SIG # End signature block
