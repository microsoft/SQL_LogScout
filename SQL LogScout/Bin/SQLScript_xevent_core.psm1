
    function xevent_core_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "xevent_core"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 0
BEGIN
	PRINT ''
	PRINT ' *** '
	PRINT ' *** Skipped creating and configuring event session xevent_SQLLogScout. Principal ' + SUSER_SNAME() + ' does not have ALTER ANY EVENT SESSION permission.'
	PRINT ' *** To grant permissions, execute the following and rerun the script:'
	PRINT ' *** '
	PRINT ' *** GRANT ALTER ANY EVENT SESSION TO ' + QUOTENAME(SUSER_SNAME())
	PRINT ' *** '
	PRINT ''
END
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    if exists (select * from sys.server_event_sessions where name= 'xevent_SQLLogScout') drop  EVENT SESSION [xevent_SQLLogScout] ON SERVER 
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    CREATE  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.existing_connection ( SET collect_database_name=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
	  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
	WITH (MAX_MEMORY=200800 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=10 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_CPU,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.login ( SET collect_options_text=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
	  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.logout (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
	  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sql_batch_completed ( SET collect_batch_text=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
	  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sql_batch_starting (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
	  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.rpc_starting (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
	  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.rpc_completed ( SET collect_data_stream=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
	  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO

IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.error_reported (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
      WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
    )
GO
 
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
    ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.execution_warning (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
      WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
    )
    "

    if ($true -eq $returnVariable)
    {
    Write-LogDebug "Returned variable without creating file, this maybe due to use of GUI to filter out some of the xevents"

    $content = $content -split "`r`n"
    return $content
    }

    if (-Not (Test-Path $fileName))
    {
        Set-Content -Path $fileName -Value $content
    } else 
    {
        Write-LogDebug "$filName already exists, could be from GUI"
    }

    #check if command was successful, then add the file to the list for cleanup AND return collector name
    if ($true -eq $?) 
    {
        $global:tblInternalSQLFiles += $collectorName
        return $collectorName
    }

    Write-LogDebug "Failed to build SQL File " 
    Write-LogDebug $fileName

    #return false if we reach here.
    return $false

    }

    
