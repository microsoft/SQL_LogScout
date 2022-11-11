

<#
written by 
 James.Ferebee@microsoft.com
 PijoCoder @github.com

.SYNOPSIS
  Test Powershell script to create task in Windows Task Scheduler to invoke SQL LogScout.
.LINK 
  https://github.com/microsoft/sql_logscout
.EXAMPLE
  .\ScheduleLogScoutAsTask.ps1 -LogScoutPath "C:\temp\log scout\Test 2" -Scenario "GeneralPerf" -SQLInstance "Server1\sqlinst1" -OutputPath "C:\temp\log scout\test 2" -CmdTaskName "First SQLLogScout Capture" -DeleteFolderOrNew "DeleteDefaultFolder" -StartTime "2022-08-24 08:26:00" -DurationInMins 10 -Once 
#> 



param
(
    #Implement params to have the script accept parameters which is then passed to Windows Task Scheduler logscout command
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
    [string] $OutputPath = (Get-Location | Select-Object Path).Path,

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
    [Parameter(Position=7)]
    [double] $DurationInMins,

    #schedule it for one execution
    [Parameter(Position=8, Mandatory=$false)]
    [switch] $Once,

    #schedule it daily at the specified time
    [Parameter(Position=9, Mandatory=$false)]
    [switch] $Daily

    #for future scenarios
    #[Parameter(Position=9)]
    #[timespan] $RepetitionDuration, 

    #[Parameter(Position=10)]
    #[timespan] $RepetitionInterval

)

#exception handling function

function HandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Write-Host "'$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    -ForegroundColor Red
}


function Log-Message ([string]$Message, [string] $MsgColor = "none")
{

    if ($MsgColor -eq "none")
    {
        Write-Host (Get-Date -Format "yyyy-MM-dd HH:MM:ss.ms") $Message
    }
    else {
        Write-Host (Get-Date -Format "yyyy-MM-dd HH:MM:ss.ms") $Message -ForegroundColor $MsgColor
    }
}


try 
{
    if([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($CmdTaskName) -eq $true)
    {
        #Task cannot have a wildcard character
        throw "Task Name cannot contain wildcard characters. Exiting..." 
        exit
    }
           
    Write-Host ""

    #If scheduled SQL LogScout task already exists, exit or prompt for delete
    $LogScoutScheduleTaskExists = Get-ScheduledTask -TaskName $CmdTaskName -ErrorAction SilentlyContinue

    if ($LogScoutScheduleTaskExists)
    {
        Log-Message -Message "SQL Logscout task already exists. Would you like to delete it and continue, or exit?" -MsgColor Yellow
        
        $delete_task = $null

        #while ( ($delete_task -ne "Y") -and ($delete_task -ne "N") -and ($null -eq $delete_task))
        while ( ($delete_task -ne "Y") -and ($delete_task -ne "N") )
        {
            $delete_task = Read-Host "Delete existing task (y/n)?"

            $delete_task = $delete_task.ToString().ToUpper()
            if ( ($delete_task -ne "Y") -and ($delete_task -ne "N"))
            {
                Write-Host "Please chose 'Y' or 'N' to proceed"
            }
        }

        if ($delete_task -eq 'N')
        {
            Log-Message "Please review and delete existing task manually if you wish to re-run. Exiting..."
            exit
        }
        else 
        {
            Unregister-ScheduledTask -TaskName $CmdTaskName -Confirm:$false
        }

     
    }
            


    #LogScout Path Validation
    if ([string]::IsNullOrEmpty($LogScoutPath) -eq $True)
    {
        $LogScoutPath = (Get-Location | Select-Object Path).Path
    }
    #validate the folder
    elseif ((Test-Path $LogScoutPath) -eq $True)
    {   
        #trim a trailing backslash if one was passed. otherwise the job would fail
        if ($LogScoutPath.Substring($LogScoutPath.Length -1) -eq "`\")
        {
            $LogScoutPath = $LogScoutPath.Substring(0,$LogScoutPath.Length -1)
        }
    }
    else 
    {
        throw "Invalid directory passed as SQL LogScout path. Please correct and re-run. Exiting..."
        exit
    }



    #Calculate stoptime based on minutes passed to determine end time of LogScout
    if ($DurationInMins-lt 1)
    {
        $DurationInMins = 1
    }

    [datetime] $time = $StartTime
    [datetime] $endtime=$time.AddMinutes($DurationInMins)

    Log-Message "Based on starttime = '$StartTime' and duration = $DurationInMins minute(s), the end time is '$endtime'" 

    

    #Output path check
    if (([string]::IsNullOrEmpty($OutputPath) -eq $true) -or ($OutputPath -eq 'UsePresentDir') )
    {
        $OutputPath = 'UsePresentDir'
    }
    else
    {
        $validpath = Test-Path $OutputPath

        #if $OutputPath is valid use it, otherwise, throw an exception
        if ($validpath -eq $false)
        {
            throw "Invalid directory passed as LogScout Output folder. Please correct and re-run. Exiting..." 
            exit
        }

        #trim a trailing backslash if one was passed. otherwise the job would fail
        if ($OutputPath.Substring($OutputPath.Length -1) -eq "`\")
        {
            $OutputPath = $OutputPath.Substring(0,$OutputPath.Length -1)
        }

    }

    #Whether to delete the existing folder or use new folder with incremental date_time in the name
    if ([string]::IsNullOrEmpty($DeleteFolderOrNew) -eq $true)
    {
        $DeleteFolderOrNew = 'DeleteDefaultFolder'
    }
    elseif ($DeleteFolderOrNew -eq 'NewCustomFolder')
    {    
        $DeleteFolderOrNew = 'NewCustomFolder'
    }
    else
    {
        $DeleteFolderOrNew = 'DeleteDefaultFolder'
    }
    

    #define the schedule (execution time) - either run it one time (Once) or every day at the same time (Daily)
    if ($Once -eq $true)
    {
        $trigger = New-ScheduledTaskTrigger -Once -At $StartTime
    }
    elseif ($Daily -eq $true) 
    {
        $trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
    }
    else {
        throw "Please specify either '-Once' or '-Daily' parameter (but not both)"
    }
    
    

    $LogScoutPath = $LogScoutPath +'\SQL_LogScout.cmd'
    #CMD looks for input for -Execute as C:\SQL_LogScout_v4.5_Signed\SQL_LogScout_v4.5_Signed\SQL_LogScout.cmd
    #The start date parameter is not passed below to New-ScheduledTaskAction as the job is invoked based on the task trigger above which does take the StartTime parameter. 
    #To reduce likelihood of issue, 2000 date is hardcoded.
    $actions = (New-ScheduledTaskAction -Execute $LogScoutPath -Argument "$Scenario $SQLInstance `"$OutputPath`" `"$DeleteFolderOrNew`" `"2000-01-01`" `"$endtime`" `"Quiet`"" )

    

    # get the current account and use it for the job
    $account = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $account -RunLevel Highest


    $settings = New-ScheduledTaskSettingsSet -WakeToRun
    $task = New-ScheduledTask -Action $actions -Principal $principal -Trigger $trigger -Settings $settings


    #Write-Host "`nCreating '$CmdTaskName'... "
    Log-Message "Creating '$CmdTaskName'... "
    Register-ScheduledTask -TaskName $CmdTaskName -InputObject $task | Out-Null


    Log-Message "The created '$CmdTaskName' has the following properties:"
    
    Get-ScheduledTask -TaskName $CmdTaskName | Select-Object -Property TaskName, State -ExpandProperty Actions | Select-Object TaskName, State, Execute, Arguments | Format-List

    #future use: Get-ScheduledTask -TaskName $CmdTaskName | Select-Object -ExpandProperty Triggers | Select-Object -Property StartBoundary, ExecutonTimeLimit, Enabled -ExpandProperty Repetition
}

catch 
{
    HandleCatchBlock -function_name "ScheduleSQLLogScoutTask" -err_rec $PSItem
}
