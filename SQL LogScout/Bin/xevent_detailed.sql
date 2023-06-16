IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 0
BEGIN
	PRINT ''
	PRINT ' *** '
	PRINT ' *** Skipped creating and configuring event session "xevent_SQLLogScout". Principal ' + SUSER_SNAME() + ' does not have ALTER ANY EVENT SESSION permission.'
	PRINT ' *** To grant permissions, execute the following and rerun the script:'
	PRINT ' *** '
	PRINT ' *** GRANT ALTER ANY EVENT SESSION TO ' + QUOTENAME(SUSER_SNAME())
	PRINT ' *** '
	PRINT ''
END
GO

--introduce a wait and check if the xevent_SQLLogScout has been created
DECLARE @cntr INT = 0
WHILE (NOT EXISTS (SELECT name from sys.server_event_sessions WHERE name= 'xevent_SQLLogScout') AND @cntr < 3)
BEGIN
  WAITFOR DELAY '00:00:03'
  SET @cntr = @cntr +1
END

IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.databases_log_growth (     
ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.databases_log_shrink (     
ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.additional_memory_grant (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.attention (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.background_job_error (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.batch_hash_table_build_bailout (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.blocked_process_report (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.cpu_threshold_exceeded (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.database_suspect_data_page (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.exchange_spill (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.filestream_file_io_failure (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.hash_warning (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.missing_column_statistics ( SET collect_column_list=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.missing_join_predicate (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sort_warning (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.auto_stats (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.plan_guide_successful (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.plan_guide_unsuccessful (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.query_post_execution_showplan (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sp_cache_remove (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sp_statement_completed (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sp_statement_starting (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sql_statement_completed (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sql_statement_recompile (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sql_statement_starting (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.lock_deadlock (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.lock_escalation (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.lock_timeout (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.server_memory_change (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.dtc_transaction (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sql_transaction (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.broker_corrupted_message (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.broker_forwarded_message_dropped (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO
IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
ALTER  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.broker_message_undeliverable (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
  WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
GO