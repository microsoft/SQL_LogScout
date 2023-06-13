#Importing required modules

Import-Module .\CommonFunctions.psm1

Import-Module .\InstanceDiscovery.psm1

Import-Module .\LoggingFacility.psm1

function HandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Write-LogError "Function '$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    

    Write-Host "Exiting CleanupIncomplete Shutdown script ..."
    exit
}


[string] $global:host_name = $env:COMPUTERNAME
[string] $global:sql_instance_conn_str = ""

Write-Host ""
Write-Host "=============================================================================================================================="
Write-Host "This script is designed to clean up SQL LogScout processes that may have been left behind if SQL LogScout was closed incorrectly`n"
Write-Host "=============================================================================================================================="
Write-Host ""

#print out the instance names

Select-SQLServerForDiagnostics

$sql_instance_conn_str = $global:sql_instance_conn_str

$xevent_session = "xevent_SQLLogScout"
$xevent_target_file = "xevent_LogScout_target"
$xevent_alwayson_session = "SQLLogScout_AlwaysOn_Data_Movement"



try 
{
    Write-Host ""
    Write-Host "Launching cleanup routine for instance '$sql_instance_conn_str'... please wait`n"

    #----------------------
    Write-Host "Executing 'WPR-cancel'. It will stop all WPR traces in case any was found running..."
    $executable = "cmd.exe"
    $argument_list = $argument_list = "/C wpr.exe -cancel " 
    Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
    #-----------------------------
    Write-Host "Executing 'StorportStop'. It will stop stoport tracing if it was found to be running..."
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
        $argument_list ="-S" + $sql_instance_conn_str +  " -E -Hsqllogscout_cleanup -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #stop perf Xevent
        Write-Host "Executing 'Stop_SQLLogScout_Xevent' session. It will stop the SQLLogScout performance Xevent trace in case it was found to be running" "..."
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
    
        #stop always on data movement Xevent
        Write-Host "Executing 'Stop_SQLLogScout_AlwaysOn_Data_Movement'. It will stop the SQLLogScout AlwaysOn Xevent trace in case it was found to be running" "..."
        $xevent_session = "SQLLogScout_AlwaysOn_Data_Movement"
        $query = "ALTER EVENT SESSION [$xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_session] ON SERVER;" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #disable backup/restore trace flags
        $collector_name = "Disable_BackupRestore_Trace_Flags"
        Write-Host "Executing '$collector_name' It will disable the trace flags they were found to be enabled..."
        $query = "DBCC TRACEOFF(3004,3212,3605,-1)" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #stop perfmon collector
        $collector_name = "PerfmonStop"
        Write-Host "Executing '$collector_name'. It will stop Perfmon started by SQL LogScout in case it was found to be running ..."
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon"
        $executable = "cmd.exe"
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        # stop network traces 
        # stop logman - wait synchronously for it to finish
        $collector_name = "NetworkTraceStop"
        Write-Host "Executing '$collector_name'. It will stop network tracing initiated by SQLLogScout in case it was found to be running..."
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
                    Write-Host "Shutting down network tracing may take a few minutes. Please do not close this window ..."
                }
                [void] $proc.WaitForExit(10000)

                $cntr++
            }
        }

    Write-Host "Cleanup script execution completed."
        

}
catch 
{
    HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
}


