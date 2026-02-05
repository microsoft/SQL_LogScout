
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
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
	ALTER  EVENT SESSION [SQLLogScout_AlwaysOn_Data_Movement] ON SERVER  ADD EVENT ucs.ucs_connection_flow_control(
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
        Write-LogDebug "$fileName already exists, likely generated by GUI"
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
    

# SIG # Begin signature block
# MIIsDwYJKoZIhvcNAQcCoIIsADCCK/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAncwUL9UXsPpjj
# aUNuTMWCfcBVi+IyQmOVWlP0vpVoy6CCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPfIcBUceBU9
# 32nry7JKWl+ofVqZ5zjIP63SiSn0pBTzMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAFqAOsehN7DT0JG1bMB2R+547MuIrZV5BpEJVIUCSCqAP
# qph5FfkHCLsSjApFwVAbJgLNaFQ7fPoUCEwscxTUrmaAycNIghNERKO+5KIMTCJW
# Fq778GJcIKeUoJf4OqWvVeTUOedDZtGaQoPdGHi+mon3NJNUKpGnqmi+edhGpfoc
# GUJswiCQrRr0hf+JFdrMEgwvByVR4ZjFkTxaLwkG9eUBS7i/4BSlRivyW0LvOH4u
# BobABY48+9Bzm094ATH+KjPGed2phaP3pNf7V6uFMWYDtcRK8DxV6CUWNj050Gfm
# r3m4/s0owzSOY2t1f7j+ITt94UfdUZqNL+MOESVqMaGCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCDQpwV7+iNz9ijlHo5RHPaJEXOFwwKYu5PE+tBNLbem
# 5AIGaXSr3pIPGBMyMDI2MDIwNDE2MzUyOC40NjdaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo2NTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACFRgD04EHJnxT
# AAEAAAIVMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgyMFoXDTI2MTExMzE4NDgyMFowgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjY1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAw3HV3hVx
# L0lEYPV03XeNKZ517VIbgexhlDPdpXwDS0BYtxPwi4XYpZR1ld0u6cr2Xjuugdg5
# 0DUx5WHL0QhY2d9vkJSk02rE/75hcKt91m2Ih287QRxRMmFu3BF6466k8qp5uXtf
# e6uciq49YaS8p+dzv3uTarD4hQ8UT7La95pOJiRqxxd0qOGLECvHLEXPXioNSx9p
# yhzhm6lt7ezLxJeFVYtxShkavPoZN0dOCiYeh4KgoKoyagzMuSiLCiMUW4Ue4Qsm
# 658FJNGTNh7V5qXYVA6k5xjw5WeWdKOz0i9A5jBcbY9fVOo/cA8i1bytzcDTxb3n
# ctcly8/OYeNstkab/Isq3Cxe1vq96fIHE1+ZGmJjka1sodwqPycVp/2tb+BjulPL
# 5D6rgUXTPF84U82RLKHV57bB8fHRpgnjcWBQuXPgVeSXpERWimt0NF2lCOLzqgrv
# S/vYqde5Ln9YlKKhAZ/xDE0TLIIr6+I/2JTtXP34nfjTENVqMBISWcakIxAwGb3R
# B5yHCxynIFNVLcfKAsEdC5U2em0fAvmVv0sonqnv17cuaYi2eCLWhoK1Ic85Dw7s
# /lhcXrBpY4n/Rl5l3wHzs4vOIhu87DIy5QUaEupEsyY0NWqgI4BWl6v1wgse+l8D
# WFeUXofhUuCgVTuTHN3K8idoMbn8Q3edUIECAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBSJIXfxcqAwFqGj9jdwQtdSqadj1zAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# d42HtV+kGbvxzLBTC5O7vkCIBPy/BwpjCzeL53hAiEOebp+VdNnwm9GVCfYq3KMf
# rj4UvKQTUAaS5Zkwe1gvZ3ljSSnCOyS5OwNu9dpg3ww+QW2eOcSLkyVAWFrLn6Ii
# g3TC/zWMvVhqXtdFhG2KJ1lSbN222csY3E3/BrGluAlvET9gmxVyyxNy59/7JF5z
# IGcJibydxs94JL1BtPgXJOfZzQ+/3iTc6eDtmaWT6DKdnJocp8wkXKWPIsBEfkD6
# k1Qitwvt0mHrORah75SjecOKt4oWayVLkPTho12e0ongEg1cje5fxSZGthrMrWKv
# I4R7HEC7k8maH9ePA3ViH0CVSSOefaPTGMzIhHCo5p3jG5SMcyO3eA9uEaYQJITJ
# lLG3BwwGmypY7C/8/nj1SOhgx1HgJ0ywOJL9xfP4AOcWmCfbsqgGbCaC7WH5sINd
# zfMar8V7YNFqkbCGUKhc8GpIyE+MKnyVn33jsuaGAlNRg7dVRUSoYLJxvUsw9GOw
# yBpBwbE9sqOLm+HsO00oF23PMio7WFXcFTZAjp3ujihBAfLrXICgGOHPdkZ042u1
# LZqOcnlr3XzvgMe+mPPyasW8f0rtzJj3V5E/EKiyQlPxj9Mfq2x9himnlXWGZCVP
# eEBROrNbDYBfazTyLNCOTsRtksOSV3FBtPnpQtLN754wggdxMIIFWaADAgECAhMz
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
# bGQgVFNTIEVTTjo2NTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAj6eTejbuYE1Ifjbfrt6t
# XevCUSCggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0tqhwwIhgPMjAyNjAyMDQxMTIxMDBaGA8yMDI2MDIwNTEx
# MjEwMFowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7S2qHAIBADAKAgEAAgIViwIB
# /zAHAgEAAgISiDAKAgUA7S77nAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IB
# AQBrLZ3XO1wMVB4He8jOf3DV9mcxZtGtWM81QzCG/AAvmb1BZjvtTWZydyErnCLG
# Cc8WKzRGq5AfWJw9lYCbxKGlSBskcWiFzfvtSCMLOSByGI0gMgmSxJQrXzF7KMjh
# esXjmkK+t9WeeWG7+NqOMXD64zYnC0/fElSCe8c+yJvgHwc6NZ9jYjXcU8DWW1WZ
# VCjI3YbPUzEUqZ2IbWmRfLivgs1Wn5+PAcJXR7TfRmLSsE5M5ebx7jiubtKXlPdm
# XynIyroA+qvxMKxUlVyOcHx94OpjGUWRdMBoYSDVEi8zZmSuN+SOic0kPx3fsVtI
# aH+MKlW0Q355OAcnpRH7c6bVMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIVGAPTgQcmfFMAAQAAAhUwDQYJYIZIAWUDBAIB
# BQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQglnedpNkLHjTZxdOyHXTFpTx0xcRr2/Z/aCbHiNzhPQowgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCBwEPR2PDrTFLcrtQsKrUi7oz5JNRCF/KRHMihSNe7s
# ijCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACFRgD
# 04EHJnxTAAEAAAIVMCIEIAy84l0FlIwqrldfB3TmTArja2bSHILWYvHOj9pAXLHS
# MA0GCSqGSIb3DQEBCwUABIICAICUUWsKy/0AeCsQRNWL4KrlDbu0lshAdKhULvT4
# 0vwFalA7sF+Yk62ftxHGfV0FSL7cui1YJ++h9mQdkw2FiSsJ93E/iBmh4Ha60Rl7
# 2rDgv9HQKRG35Kp3Tkhu2cv6JJq1DeS9eIxw0W/nsUyuvttW9bQxxPf7X3bhV9MO
# BnmGr/Yq4MxhWW1Kzt3qPV2clePSavxg5U3NnQpEBYhcarjiRWRwfUWbakv96Drr
# UgPpXm8+pqsOixyD+2v+w8LmVQiAZ0yGe5/7HtfDMbJeBYno2rKnD0C6FthU2H44
# Te695HO9NmilCNdexo0g/haGTYDFC/gX4hf7ppUVnEdVf1j2YD+i88UYrQeXN+W+
# T8is1PT0rcMiV5mCdfMyeVil7f08VeCNUkU8cbdNFZICDaozPjfy0rqkSjDUrx2I
# pWp2PPkGHLdqA/Ndh4G3d8p6coR122+xdzVnfXK5JQ4VWdkeVmgLBrqBrJntNrAc
# 15H4HjE9SmKERgwYs25RSzeKCW3vI5P7yl6prv2CDRxZfuUdyM+dzpoZdxmEXMz/
# Zv8JP5LGpxOSKjtzsHOMMbtie9ubdkaDCWGSN8/JlqMhinH3AuQ/pvKYbiJpqNWV
# qSruaBtwiL3myPMM6vFvgPLk/lUtmY/EsvUY8fZpYAnQGGn2u9Gku51R+1cm+TUb
# kfr+
# SIG # End signature block
