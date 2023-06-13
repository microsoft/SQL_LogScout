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
alter  EVENT SESSION [xevent_SQLLogScout] ON SERVER  	
ADD EVENT sqlserver.backup_restore_progress_trace (  ACTION (sqlos.numa_node_id,sqlserver.client_app_name,sqlserver.database_id,sqlserver.database_name,sqlserver.plan_handle,sqlserver.query_hash,sqlserver.query_hash_signed,sqlserver.query_plan_hash,sqlserver.server_instance_name,sqlserver.server_principal_name,sqlserver.session_id,sqlserver.session_nt_username,sqlserver.sql_text,sqlserver.username)	
	WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
)
Go