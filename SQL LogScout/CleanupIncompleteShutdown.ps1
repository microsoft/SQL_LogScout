$server =  $env:COMPUTERNAME
$sqlinstance= $server
#find the actively running SQL Server services
$SqlTaskList = Tasklist /SVC /FI "imagename eq sqlservr*" /FO CSV | ConvertFrom-Csv
$SqlTaskList = $SqlTaskList | Select-Object  PID, "Image name", Services 

$instnaceArray= @()
foreach ($sqlinstance in $SqlTaskList.Services)
{
    #in the case of a default instance, just use MSSQLSERVER which is the instance name

    if ($sqlinstance.IndexOf("$") -lt 1)
    {
        $SqlInstance  = $sqlinstance
    }

    #for named instance, strip the part after the "$"
    else
    {
        $SqlInstance  = $server + "\" + $sqlinstance.Substring($sqlinstance.IndexOf("$") + 1)
    }

             
    #add each instance name to the array
    $instnaceArray+=$SqlInstance 
}

Write-Host ""
Write-Host "=============================================================================================================================="
Write-Host "This script is designed to clean up SQL LogScout processes that may have been left behind if SQL LogScout was closed incorrectly`n"
Write-Host "=============================================================================================================================="
Write-Host ""

#print out the instance names

Write-Host "Discovered the following SQL Server instance(s)`n"
Write-Host ""
Write-Host "ID	SQL Instance Name"
Write-Host "--	----------------"
# sort the array by instance name
$instnaceArray = $instnaceArray | Sort-Object

for($i=0; $i -lt $instnaceArray.Count;$i++)
{
    Write-Host $i "	" $instnaceArray[$i]
}

Write-Host ""
$j = Read-Host "Please select the ID for SQL instance."
$SelectedSQLinstnace = $instnaceArray[$j]
$sql_instance_conn_str = $SelectedSQLinstnace 

$xevent_session = "xevent_SQLLogScout"
$xevent_target_file = "xevent_LogScout_target"
$xevent_alwayson_session = "SQLLogScout_AlwaysOn_Data_Movement"

function HandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Write-Host "Function '$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    

    if ($exit_logscout)
    {
        Write-Host "Exiting CleanupIncomplete Shutdown script ..."
        exit
    }
}

try 
{
    Write-Host ""
    Write-Host "Launching cleanup routine... please wait"

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
        $argument_list ="-S" + $sql_instance_conn_str +  " -E -Hsqllogscout_cleanup -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        Write-Host "Executing STOP_SQLLogScout_Xevent session. It will stop the Xevent trace in case it was found to be running" "..."
        $query = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_session] ON SERVER; END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -w8000 -Q`"" + $query + "`""
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
        
        
        $query = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_alwayson_session] ON SERVER; END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -w8000 -Q`"" + $query + "`""
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        $xevent_session = "xevent_SQLLogScout"
        $query = "ALTER EVENT SESSION [$xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_session] ON SERVER;" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
    
        Write-Host "Executing STOP_SQLLogScout_AlwaysOn_Data_Movement. It will stop the Xevent trace in case it was found to be running" "..."
        $xevent_session = "SQLLogScout_AlwaysOn_Data_Movement"
        $query = "ALTER EVENT SESSION [$xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_session] ON SERVER;" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        $collector_name = "Disable_BackupRestore_Trace_Flags"
        Write-Host "Executing" $collector_name "It will disable the trace flags they were found to be enabled..."
        $query = "DBCC TRACEOFF(3004,3212,3605,-1)" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden


        $collector_name = "PerfmonStop"
        Write-Host "Executing $collector_name. It will stop Perfmon started by SQL LogScout in case it was found to be running ..."
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon"
        $executable = "cmd.exe"
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        $collector_name = "NettraceStop"
        Write-Host "Executing $collector_name. It will stop the network trace in case it was found to be running..."
        $argument_list = "/C title Stopping Network trace... & echo This process may take a few minutes. Do not close this window... & StopNetworkTrace.bat"
        $executable = "cmd.exe"
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Normal
 
        #----------------------
        Write-Host "Executing WPR -cancel. This will stop all WPR traces in case any was found running..."
        $executable = "cmd.exe"
        $argument_list = $argument_list = "/C wpr.exe -cancel " 
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
        #-----------------------------
        Write-Host "Executing STOP storport. It will stop a stoport trace if it was found to be running..."
        $argument_list = "/C logman stop ""storport"" -ets"
        $executable = "cmd.exe"
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
        #-------------------------------------
}
catch 
{
    HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
}


