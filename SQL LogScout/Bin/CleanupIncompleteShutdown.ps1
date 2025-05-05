param
(
    [Parameter(Position=0)]
    [string] $ServerName = [String]::Empty,
    [switch] $EndActiveConsoles = $false
)
######### Globals #########

[string] $global:host_name = $env:COMPUTERNAME
[string] $global:sql_instance_conn_str = ""
[string] $global:CleanupIncompleteShutdownLog = ""
#As -WorkingDirectory is in ScheduledTask or if manually invoked we are in the right directory location, this is safe to use
[string] $global:gBinPathCleanup = (Get-Item -Path ".\" -Verbose).FullName

######### Importing required modules #########
$modules = @("CommonFunctions.psm1", "InstanceDiscovery.psm1","LoggingFacility.psm1")
# Loop through each module name and import the module
foreach ($module in $modules) 
{
    try 
    {
        $module = $global:gBinPathCleanup + "\" + $module
        Import-Module $module -ErrorAction Stop
    } 
    catch 
    {
        Write-Output "Failed to import $module"
        Start-Sleep -Seconds 4
        exit
    }
}

######### Functions #########

#This function is already defined in CommonFunctions , PS doesn't have overlay
function HandleCatchBlockCleanup ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Microsoft.PowerShell.Utility\Write-Host "Function '$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)" -ForegroundColor "Red"

    Microsoft.PowerShell.Utility\Write-Host "Exiting CleanupIncomplete Shutdown script ..."
    exit
}

function Initialize-CleanupIncompleteShutdownTaskLog
(
    [string]$LogFilePath,
    [string]$LogFileName = "##SQLLogScout_CleanupIncompleteShutdown"
)
{
<#
    .DESCRIPTION
        Initialize-CleanupIncompleteShutdownTaskLog creates the log file specific for scheduled tasks in the desired directory. 
        Logging to console is also written to the persisted file on disk.

#>    
    try
    {
        #Create log file in temp directory using full path. The temp var can come back as 8.3 format and so ensure we have the full path.
        $shortEnvTempPath = $env:TEMP
        $LogFilePath = (Get-Item $shortEnvTempPath).FullName

        #Cache LogFileName without date so we can delete old records properly
        $LogFileNameStringToDelete = $LogFileName

        #update file with date
        $LogFileName = $LogFileName + "_" + (Get-Date -Format "yyyyMMddTHHmmssffff") + ".log"
        $global:CleanupIncompleteShutdownLog = $LogFilePath + '\' + $LogFileName
        New-Item -ItemType "file" -Path $global:CleanupIncompleteShutdownLog -Force | Out-Null
        Write-Host "Created log file $global:CleanupIncompleteShutdownLog"
        Write-Host "Log initialization complete!"

        #Array to store the old files in temp directory that we then delete and use the non-date value as the string to find.
        $FilesToDelete = @(Get-ChildItem -Path ($LogFilePath) | Where-Object {$_.Name -match $LogFileNameStringToDelete} | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip 10)
        $NumFilesToDelete = $FilesToDelete.Count

        Log-CleanupIncompleteShutdownTask -Message "Found $NumFilesToDelete older SQL LogScout Scheduled Task Logs"

        # if we have files to delete
        if ($NumFilesToDelete -gt 0) 
        {
            foreach ($elem in $FilesToDelete)
            {
                $FullFileName = $elem.FullName
                Log-CleanupIncompleteShutdownTask -Message "Attempting to remove file: $FullFileName"
                Remove-Item -Path $FullFileName
            }
        }



    }
    catch
    {
		#Write-Error -Exception $_.Exception
        HandleCatchBlockCleanup -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit $true
    }
}

function Log-CleanupIncompleteShutdownTask
(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Message,
    [Parameter(Mandatory=$false, Position=1)]
    [bool]$WriteToConsole = $false,
    [Parameter(Mandatory=$false, Position=2)]
    [System.ConsoleColor]$ConsoleMsgColor = [System.ConsoleColor]::White,
    [Parameter(Mandatory=$false, Position=3)]
    [System.ConsoleColor]$ConsoleBackgroundColor = [System.ConsoleColor]::Blue
)  
{
<#
    .DESCRIPTION
        Appends messages to the persisted log and also returns output to console if flagged.

#>
    try 
    {
        #Add timestamp to message
        [string]$Message = (Get-Date -Format("yyyy-MM-dd HH:mm:ss.ms")) + ': '+ $Message

        #Log to file in $env:temp
        Add-Content -Path $global:CleanupIncompleteShutdownLog -Value $Message | Out-Null

        #if we want to write to console, we can provide that parameter and optionally a color as well.
        if ($true -eq $WriteToConsole)
        {
            if ($ConsoleMsgColor -ine $null -or $ConsoleMsgColor -ine "") 
            {
                Microsoft.PowerShell.Utility\Write-Host -Object $Message -ForegroundColor $ConsoleMsgColor
            }
            else 
            {
                #Return message to console with provided color.
                Microsoft.PowerShell.Utility\Write-Host -Object $Message
            }
        }        

    }
    catch 
    {
        ScheduledTaskHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit $true
    }
}

function EndActiveConsoles
{
    try
    {
        $scriptName = "sql_logscout.ps1"

        # Get all PowerShell processes
        $psProcesses = Get-Process -Name "powershell*" -ErrorAction SilentlyContinue

        if ($null -eq $psProcesses)
        {
            Log-CleanupIncompleteShutdownTask "No active powershell sessions found."
            return
        }
        else 
        {
            foreach ($process in $psProcesses) 
            {

                $cimProc = (Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)")
                # Get the process owner
                $user = ($cimProc | Invoke-CimMethod -MethodName GetOwner).User
                $command = $cimProc.CommandLine

                if ($command -like "*$scriptName*" -and $command -like "*$ServerName*")
                {
                    Log-CleanupIncompleteShutdownTask "Found SQL_LogScout session to terminate: '$command'"
                    # Terminate the process
                    Stop-Process -Id ($process.Id) -Force
                    Log-CleanupIncompleteShutdownTask "Terminated process $($process.Id) running '$scriptName' for user '$user'" -WriteToConsole $true -ConsoleMsgColor "Yellow"
                }
                else 
                {
                    Log-CleanupIncompleteShutdownTask "Powershell session identified but not invoking $scriptName"
                }
            }
        }
    }
    catch
    {
        HandleCatchBlockCleanup -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}


######### Initialize Log #########
Initialize-CleanupIncompleteShutdownTaskLog

#Log all the input parameters used for the scheduled task for debugging purposes
foreach ($param in $PSCmdlet.MyInvocation.BoundParameters.GetEnumerator()) 
{
    Log-CleanupIncompleteShutdownTask "PARAMETER USED: $($param.Key): $($param.Value)"
}

######### Main Logic #########
Log-CleanupIncompleteShutdownTask "======================================================================================================================================" -WriteToConsole $true -ConsoleBackgroundColor "Blue"
Log-CleanupIncompleteShutdownTask "This script is designed to clean up SQL LogScout processes that may have been left behind if SQL LogScout was closed incorrectly" -WriteToConsole $true -ConsoleMsgColor "Yellow"
Log-CleanupIncompleteShutdownTask "======================================================================================================================================" -WriteToConsole $true -ConsoleBackgroundColor "Blue"

#print out the instance names

if ([string]::IsNullOrWhiteSpace($ServerName))
{
    Select-SQLServerForDiagnostics | Out-Null
}
else 
{
    $global:sql_instance_conn_str = $ServerName
}


$xevent_session = "xevent_SQLLogScout"
$xevent_target_file = "xevent_LogScout_target"
$xevent_alwayson_session = "SQLLogScout_AlwaysOn_Data_Movement"

try 
{
    Log-CleanupIncompleteShutdownTask "Testing connection into: '$global:sql_instance_conn_str'. If connection fails, verify instance name or running status." -WriteToConsole $true
    $ConnectionResult = Test-SQLConnection ($global:sql_instance_conn_str)

    if ($ConnectionResult -eq $false)
    {
        Log-CleanupIncompleteShutdownTask "Connection to '$global:sql_instance_conn_str' failed. Please verify the instance name and try again." -WriteToConsole $true
        exit
    }
    else 
    {
        Log-CleanupIncompleteShutdownTask "Connection to '$global:sql_instance_conn_str' successful." -WriteToConsole $true
    }
    
}
catch 
{
    HandleCatchBlockCleanup -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
}



try 
{
    #If user wants to end active consoles, we will do that first for the same connection string ServerName that was provided
    if ($EndActiveConsoles -eq $true)
    {
        EndActiveConsoles
    }

    Log-CleanupIncompleteShutdownTask "Launching cleanup routine for instance '$global:sql_instance_conn_str'... please wait" -WriteToConsole $true

    #----------------------
    Log-CleanupIncompleteShutdownTask "Executing 'WPR-cancel'. It will stop all WPR traces in case any was found running..." -WriteToConsole $true
    $executable = "cmd.exe"
    $argument_list = $argument_list = "/C wpr.exe -cancel " 
    Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
    #-----------------------------
    Log-CleanupIncompleteShutdownTask "Executing 'StorportStop'. It will stop stoport tracing if it was found to be running..." -WriteToConsole $true
    $argument_list = "/C logman stop ""storport"" -ets"
    $executable = "cmd.exe"
    Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
    #-------------------------------------

    $query = "
        declare curSession
        CURSOR for select 'kill ' + cast( session_id as varchar(max)) from sys.dm_exec_sessions where host_name = 'sqllogscout' and program_name='SQLCMD' and session_id <> @@spid
        open curSession
        declare @sql varchar(max)
        fetch next from curSession into @sql
        while @@FETCH_STATUS = 0
        begin
            exec (@sql)
            fetch next from curSession into @sql
        end
        close curSession;
        deallocate curSession;
        " 
         
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $global:sql_instance_conn_str +  " -E -Hsqllogscout_cleanup -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #stop perf Xevent
        Log-CleanupIncompleteShutdownTask "Executing 'Stop_$xevent_session' session. It will stop the SQLLogScout performance Xevent trace in case it was found to be running..." -WriteToConsole $true
        
        $query = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_session] ON SERVER; END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $global:sql_instance_conn_str + " -E -w8000 -Q`"" + $query + "`""
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
        
        $xevent_session = "xevent_SQLLogScout"
        $query = "ALTER EVENT SESSION [$xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_session] ON SERVER;" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $global:sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
    
        #stop always on data movement Xevent
        Log-CleanupIncompleteShutdownTask "Executing 'Stop_$xevent_alwayson_session'. It will stop the SQLLogScout AlwaysOn Xevent trace in case it was found to be running..." -WriteToConsole $true
        
        $query = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_alwayson_session] ON SERVER; END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $global:sql_instance_conn_str + " -E -w8000 -Q`"" + $query + "`""
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        $query = "ALTER EVENT SESSION [$xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_alwayson_session] ON SERVER;" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $global:sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #disable backup/restore trace flags
        $collector_name = "Disable_BackupRestore_Trace_Flags"
        Log-CleanupIncompleteShutdownTask "Executing '$collector_name' It will disable the trace flags they were found to be enabled..." -WriteToConsole $true
        $query = "DBCC TRACEOFF(3004,3212,3605,-1)" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $global:sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #stop perfmon collector
        $collector_name = "PerfmonStop"
        Log-CleanupIncompleteShutdownTask "Executing '$collector_name'. It will stop Perfmon started by SQL LogScout in case it was found to be running..." -WriteToConsole $true
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon"
        $executable = "cmd.exe"
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        # stop network traces 
        # stop logman - wait synchronously for it to finish
        $collector_name = "NetworkTraceStop"
        Log-CleanupIncompleteShutdownTask "Executing '$collector_name'. It will stop network tracing initiated by SQLLogScout in case it was found to be running..." -WriteToConsole $true
        $executable = "logman"
        $argument_list = "stop -n sqllogscoutndiscap -ets"
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait

        # stop netsh  asynchronously but wait for it to finish in a loop
        $executable = "netsh"
        $argument_list = "trace stop"
        $proc = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru

        if ($null -ne $proc)
        {

            [int]$cntr = 0

            while ($false -eq $proc.HasExited) 
            {
                if ($cntr -gt 0) {
                    Log-CleanupIncompleteShutdownTask "Shutting down network tracing may take a few minutes. Please do not close this window..." -WriteToConsole $true
                }
                [void] $proc.WaitForExit(10000)

                $cntr++
            }
        }

    Log-CleanupIncompleteShutdownTask "Cleanup script execution completed." -WriteToConsole $true

}
catch 
{
    HandleCatchBlockCleanup -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
}

finally
{
    #Cleanup the global variables. Otherwise, they will be available in the session and 
    #the next run of the script may connect to the same instance.
    Remove-Variable -Name "*" -Scope "Global" -ErrorAction SilentlyContinue
}


