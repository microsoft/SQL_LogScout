
    function xevent_AlwaysOn_Data_Movement_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "xevent_AlwaysOn_Data_Movement"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 0
BEGIN
    PRINT ''
    PRINT ' *** '
    PRINT ' *** Skipped creating and configuring event session SQLLogScout_AlwaysOn_Data_Movement. Principal ' + SUSER_SNAME() + ' does not have ALTER ANY EVENT SESSION permission.'
    PRINT ' *** To grant permissions, execute the following and rerun the script:'
    PRINT ' *** '
    PRINT ' *** GRANT ALTER ANY EVENT SESSION TO ' + QUOTENAME(SUSER_SNAME())
    PRINT ' *** '
    PRINT ''
END

DECLARE @servermajorversion int, @serverbuild int

--find product version
SET @servermajorversion = CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT)

--find product build
SET @serverbuild = CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT)

--Always ON only above SQL 2012
IF (@servermajorversion <= 11)
BEGIN
    RAISERROR ('SQL Server version is less than 2012. AlwaysOn_Data_Movement Xevents will be skipped.', 0, 1) WITH NOWAIT
	RETURN
END
--Applies to: SQL Server 2014 SP2 (12.0.5000.0), SQL Server 2016 SP1 (13.0.4001), SQL Server 2017 and 2019+
ELSE IF ((@servermajorversion = 13 and @serverbuild < 4001) or (@servermajorversion = 12 and @serverbuild < 5000))
BEGIN
    declare @ver_str varchar (128)
    set @ver_str = 'SQL Server version is ' + convert (varchar, @servermajorversion) + ' build: ' + convert(varchar, @serverbuild)
    RAISERROR (@ver_str, 0, 1) WITH NOWAIT
    RAISERROR ('Version must be SQL Server 2014 SP2 (12.0.5000.0), SQL Server 2016 SP1 (13.0.4001), SQL Server 2017 RTM, or later. AlwaysOn_Data_Movement Xevents will be skipped; other logs will be collected', 0, 1) WITH NOWAIT
	RETURN
END

-- Create the event session

IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
CREATE EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER ADD EVENT sqlserver.file_write_completed( 
	ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
WITH (MAX_MEMORY=200800 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=10 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_CPU,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.error_reported (
	ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
	WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.file_write_enqueued(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_apply_log_block(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_apply_vlfheader(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_capture_compressed_log_cache(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_capture_filestream_wait(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_capture_log_block(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_capture_vlfheader(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_db_commit_mgr_harden(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_db_commit_mgr_harden_still_waiting(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_db_commit_mgr_update_harden(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_filestream_processed_block(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_log_block_compression(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_log_block_decompression(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)

GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_log_block_group_commit(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_log_block_send_complete(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_lsn_send_complete(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_receive_harden_lsn_message(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_send_harden_lsn_message(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_transport_flow_control_action(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_transport_receive_log_block_message(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.log_block_pushed_to_logpool(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.log_flush_complete(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.log_flush_start(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.recovery_unit_harden_log_timestamps(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_transport_dump_message(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT sqlserver.hadr_database_flow_control_action(
    ACTION(package0.event_sequence,sqlos.cpu_id,sqlos.scheduler_id,sqlos.system_thread_id,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid,sqlserver.database_id,sqlserver.database_name,sqlserver.is_system,sqlserver.nt_username,sqlserver.query_hash,sqlserver.request_id,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.session_server_principal_name,sqlserver.sql_text,sqlserver.transaction_id,sqlserver.username)
    WHERE (([sqlserver].[client_hostname]<>N'sqllogscout' AND [sqlserver].[client_hostname]<>N'sqllogscout_stop' AND [sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
	)
GO
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
    
