SET NOCOUNT ON
USE tempdb
GO
IF OBJECT_ID ('dbo.proc_ExclusionsInclusions') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.proc_ExclusionsInclusions
END
GO
IF OBJECT_ID ('dbo.proc_SqlNexusTableValidation') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.proc_SqlNexusTableValidation
END

USE tempdb
GO
CREATE PROCEDURE dbo.proc_ExclusionsInclusions @scenario_name VARCHAR(100), @database_name SYSNAME, @exclusion_tag VARCHAR(32)
AS
BEGIN
	SET NOCOUNT ON
	
	DECLARE @ProductVersion VARCHAR(32) , @sql_major_version INT, @sql_major_build INT, @sql VARCHAR(MAX),  @object varchar(64)

	--create the sqlversion temp table
	IF OBJECT_ID ('tempdb..#sqlversion') IS NOT NULL
	BEGIN
		DROP TABLE #sqlversion;
	END
	CREATE TABLE #sqlversion (MajorVersion INT, MajorBuild INT);


	--build the object string
	SET @object  = @database_name + '.dbo.tbl_ServerProperties'

	--get the SQL Server major build and version into a temp table
	IF OBJECT_ID(@object) IS NOT NULL
	BEGIN
		SET @sqL ='
		INSERT INTO #sqlversion (MajorVersion , MajorBuild )
		SELECT  CAST(PARSENAME(PropertyValue,4) AS INT) as MajorVersion, 
				CAST(PARSENAME(PropertyValue,2) AS INT) as MajorBuild
		FROM ' + @database_name + '.dbo.tbl_ServerProperties
		WHERE PropertyName = ''ProductVersion'''

		EXEC (@sql)
	END

	--select the major build and version into variables for reuse		
	SELECT 
		@sql_major_version = MajorVersion,
		@sql_major_build = MajorBuild
	FROM #sqlversion


	DECLARE @SQLVERSION BIGINT =  PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 4) 
							+ RIGHT(REPLICATE ('0', 3) + PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 3), 3)  
							+ RIGHT (replicate ('0', 6) + PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) , 6)


	--Implement the exceptions now. #temptablelist_sqlnexus is already created by parent proc so it exist in this session

	-- exclude scoped configuration table in versions earlier than SQL 2016
	-- for now lump Perf scenarios together. Break them up in the future if other exceptions needed
	-- that apply to only one of them

	IF (@scenario_name IN ('GeneralPerf', 'DetailedPerf', 'LightPerf'))
	BEGIN
		IF (@sql_major_version < 13)
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'dbo' 
				AND TableName IN (
					'tbl_database_scoped_configurations',
					'tbl_query_store_runtime_stats_interval',
					'tbl_query_store_runtime_stats',
					'tbl_query_store_query',
					'tbl_query_store_query_text',
					'tbl_query_store_plan',
					'tbl_query_store_wait_stats',
					'tbl_database_query_store_options',
					'tbl_query_store_query_hints',
					'tbl_query_store_plan_feedback',
					'tbl_query_store_query_variant'
					)
		END
		
		IF (@sql_major_version < 14)
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'dbo' 
				AND TableName IN (
					--added in 2017
					'tbl_query_store_wait_stats',
					'tbl_dm_db_tuning_recommendations',
					--added in 2022
					'tbl_query_store_query_hints',
					'tbl_query_store_plan_feedback',
					'tbl_query_store_query_variant'
					)
		END

		IF (@sql_major_version < 16)
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'dbo' 
				AND TableName IN (
					--added in 2022
					'tbl_query_store_query_hints',
					'tbl_query_store_plan_feedback',
					'tbl_query_store_query_variant'
					)
		END

		-- in-memory related dmvs
		IF (@sql_major_version < 12)
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'dbo' 
				AND TableName IN (
					'tbl_dm_db_xtp_transactions',
					'tbl_dm_xtp_transaction_stats'					
					)
		END


	END

	--exclude Xevent tables (from RML Utils) in versions earlier than SQL 2016
	ELSE IF (@scenario_name IN ('BackupRestore'))
	BEGIN
		IF (@sql_major_version < 13)
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'ReadTrace' 
				AND TableName IN (
				'tblBatches',
				'tblBatchPartialAggs',
				'tblComparisonBatchPartialAggs',
				'tblConnections',
				'tblInterestingEvents',
				'tblMiscInfo',
				'tblPlanRows',
				'tblPlans',
				'tblProcedureNames',
				'tblStatements',
				'tblStmtPartialAggs',
				'tblTimeIntervals',
				'tblTracedEvents',
				'tblTraceFiles',
				'tblUniqueAppNames',
				'tblUniqueBatches',
				'tblUniqueLoginNames',
				'tblUniquePlanRows',
				'tblUniquePlans',
				'tblUniqueStatements',
				'tblWarnings')
		END
	END

	--exclude auto seeding tables in versions earlier than SQL 2016 for AG
	ELSE IF (@scenario_name IN ('AlwaysOn'))
	BEGIN
		IF (@sql_major_version < 13)
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'dbo' 
				AND TableName IN (
				'tbl_hadr_ag_automatic_seeding',
				'tbl_hadr_ag_physical_seeding_stats')
		END
		IF (@exclusion_tag = 'NoAlwaysOn')
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'ReadTrace' 
		END
	END


	-- Exclude repl metadata tables if no data was collected at all
	-- In case there are CT or CDC changes in the future, 
	-- those would be excluded separately using 'CDC' tag, e.g. in a nested IF check
	ELSE IF (@scenario_name IN ('Replication') )
	BEGIN
		IF (@exclusion_tag = 'ReplMetaData')
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'dbo' 
				AND TableName IN (
				'tbl_repl_msarticles',
				'tbl_repl_mscached_peer_lsns',
				'tbl_repl_msdb_jobs',
				'tbl_repl_msdistribution_agents',
				'tbl_repl_msdistribution_history',
				'tbl_repl_mslogreader_agents',
				'tbl_repl_mslogreader_history',
				'tbl_repl_msmerge_agents',
				'tbl_repl_msmerge_history',
				'tbl_repl_msmerge_identity_range_allocations',
				'tbl_repl_msmerge_sessions',
				'tbl_repl_msmerge_subscriptions',
				'tbl_repl_mspublication_access',
				'tbl_repl_mspublications',
				'tbl_repl_mspublicationthresholds',
				'tbl_repl_mspublisher_databases',
				'tbl_repl_msqreader_agents',
				'tbl_repl_msrepl_backup_lsns',
				'tbl_repl_msrepl_commands_newest',
				'tbl_repl_msrepl_commands_oldest',
				'tbl_repl_msrepl_errors',
				'tbl_repl_msrepl_identity_range',
				'tbl_repl_msrepl_originators',
				'tbl_repl_msrepl_transactions_newest',
				'tbl_repl_msrepl_transactions_oldest',
				'tbl_repl_msrepl_version',
				'tbl_repl_msreplication_monitordata',
				'tbl_repl_mssnapshot_agents',
				'tbl_repl_mssnapshot_history',
				'tbl_repl_mssubscriber_info',
				'tbl_repl_mssubscriber_schedule',
				'tbl_repl_mssubscriptions',
				'tbl_repl_mssync_states',
				'tbl_repl_mstracer_history',
				'tbl_repl_mstracer_tokens',
				'tbl_repl_sourceserver',
				'tbl_repl_sysservers',
				'tbl_repl_msdb_jobhistory',
				'tbl_repl_msdb_msagent_profileandparameters'
				)
		END
	END

	--exclude in-memory dvms from before SQL 2014
	ELSE IF (@scenario_name IN ('Memory'))
	BEGIN
		IF (@sql_major_version < 12)
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'dbo' 
				AND TableName IN (
				'tbl_dm_db_xtp_index_stats'
               ,'tbl_dm_db_xtp_hash_index_stats'
               ,'tbl_dm_db_xtp_table_memory_stats'
               ,'tbl_dm_db_xtp_memory_consumers'
               ,'tbl_dm_db_xtp_object_stats'
               ,'tbl_dm_xtp_system_memory_consumers'
               ,'tbl_dm_xtp_system_memory_consumers_summary'
               ,'tbl_dm_xtp_gc_stats'
               ,'tbl_dm_xtp_gc_queue_stats')
		END
	END

	-- Exclude Never-ending Query tables
	ELSE IF (@scenario_name IN ('NeverEndingQuery'))
	BEGIN
		IF (@SQLVERSION < 13000004001 OR @exclusion_tag = 'NoNeverEndingQuery')
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			
		END
	END

	-- exclude the missing msi/msp tables if the exclusion tag is set
	ELSE IF (@scenario_name IN ('Setup'))
	BEGIN
		IF (@exclusion_tag = 'NoMissingMSI')
		BEGIN
			DELETE FROM #temptablelist_sqlnexus 
			WHERE SchemaName = 'dbo' 
				AND TableName IN (
				'tbl_setup_missing_msi_msp_packages')
			
		END
	END

END
GO

CREATE PROCEDURE dbo.proc_SqlNexusTableValidation
	@scenarioname VARCHAR(100), 
	@databasename SYSNAME, 
	@exclusion VARCHAR(32)
AS
BEGIN
	SET NOCOUNT ON
-- Validate the parameter db name and scenario name
-- only accept single scenario names (no combinations)
	IF (EXISTS (SELECT name FROM master.sys.databases  WHERE (name = @databasename)) 
				and @scenarioname in (
					'AlwaysOn',
					'GeneralPerf',
					'DetailedPerf',
					'Memory',
					'Setup',
					'Basic',
					'BackupRestore',
					'IO',
					'LightPerf',
					'Replication',
					'ServiceBrokerDBMail',
					'NeverEndingQuery')
		)
	BEGIN
		IF  OBJECT_ID('tempdb..#temptablelist_sqlnexus') IS NOT NULL 
		BEGIN
			DROP TABLE #temptablelist_sqlnexus
		END
		CREATE TABLE #temptablelist_sqlnexus (Id INT IDENTITY(1,1),SchemaName VARCHAR(25),TableName VARCHAR (150))

		--create the list of Basic scenario tables for reuse in other scenarios
		IF  OBJECT_ID('tempdb..#tablelist_BasicScenario') IS NOT NULL 
		BEGIN
			DROP TABLE #tablelist_BasicScenario
		END
		CREATE TABLE #tablelist_BasicScenario (Id INT IDENTITY(1,1),SchemaName VARCHAR(25),TableName VARCHAR (150)) 

		INSERT INTO #tablelist_BasicScenario (SchemaName,TableName) VALUES
			('dbo','tblNexusInfo') ,
			('dbo','tbl_ActiveServices_OS') ,
			('dbo','tbl_ActiveProcesses_OS') ,
			('dbo','tbl_fltmc_filters') ,
			('dbo','tbl_fltmc_instances') ,
			('dbo','tbl_DiagInfo') ,
			('dbo','tbl_SCRIPT_ENVIRONMENT_DETAILS') ,
			('dbo','tbl_ServerProperties') ,
			('dbo','tbl_StartupParameters') ,
			('dbo','tbl_TraceFlags') ,
			('dbo','tbl_dm_os_schedulers_snapshot') ,
			('dbo','tbl_dm_os_sys_info_miscpssdiaginfo') ,
			('dbo','tbl_Sys_Configurations') ,
			('dbo','tbl_DatabaseFiles') ,
			('dbo','tbl_SysDatabases') ,
			('dbo','tblTopSqlPlan') ,
			('dbo','tbl_HEADBLOCKERSUMMARY') ,
			('dbo','tbl_NOTABLEACTIVEQUERIES') ,
			('dbo','tbl_REQUESTS') ,
			('dbo','tbl_OS_WAIT_STATS') ,
			('dbo','tbl_SYSPERFINFO') ,
			('dbo','tbl_SQL_CPU_HEALTH') ,
			('dbo','tbl_FILE_STATS') ,
			('dbo','tbl_SYSINFO') ,
			('dbo','tbl_PERF_STATS_SCRIPT_RUNTIMES') ,
			('dbo','tbl_BLOCKING_CHAINS') ,
			('dbo','tbl_Reports') ,
			('dbo','tbl_trace_event_details') ,
			('dbo','tblDefaultConfigures') ,
			('dbo','tblObjectsUsedByTopPlans') ,
			('dbo','tbl_AnalysisSummary') ,
			('dbo','tbl_certificates') ,
			('dbo','tbl_dm_db_log_info'),
			('dbo','Counters'),
			('dbo','CounterDetails'),
			('dbo','CounterData'),
			('dbo', 'tbl_SystemInformation'),
			('dbo', 'tbl_environment_variables')

		--create the list of Basic scenario tables for reuse in other scenarios
		IF  OBJECT_ID('tempdb..#tablelist_LightPerfScenario') IS NOT NULL 
		BEGIN
			DROP TABLE #tablelist_LightPerfScenario
		END
		CREATE TABLE #tablelist_LightPerfScenario (Id INT IDENTITY(1,1),SchemaName VARCHAR(25),TableName VARCHAR (150)) 

		INSERT INTO #tablelist_LightPerfScenario (SchemaName,TableName) VALUES
			('dbo','tbl_RUNTIMES'),
			('dbo','tbl_IMPORTEDFILES'),
			('dbo','tbl_SPINLOCKSTATS'),
			('dbo','tbl_dm_os_sys_info'),
			('dbo','tbl_dm_os_latch_stats'),
			('dbo','tbl_FileStats'),
			('dbo','tbl_dm_exec_query_resource_semaphores'),
			('dbo','tbl_dm_exec_query_memory_grants'),
			('dbo','tbl_dm_os_memory_brokers'),
			('dbo','tbl_dm_os_nodes'),
			('dbo','tbl_dm_os_memory_nodes'),
			('dbo','tbl_LockSummary'),
			('dbo','tbl_ThreadStats'),
			('dbo','tbl_dm_db_file_space_usage'),
			('dbo','tbl_dm_exec_cursors'),
			('dbo','tbl_PlanCache_Stats'),
			('dbo','tbl_System_Requests'),
			('dbo','tbl_Query_Execution_Memory'),
			('dbo','tbl_TopN_QueryPlanStats'),
			('dbo','tbl_MissingIndexes'),
			('dbo','tbl_database_options'),
			('dbo','tbl_db_TDE_Info'),
			('dbo','tbl_dm_os_loaded_modules'),
			('dbo','tbl_server_audit_status'),
			('dbo','tbl_Top10_CPU_Consuming_Procedures'),
			('dbo','tbl_Top10_CPU_Consuming_Triggers'),
			('dbo','tbl_dm_db_stats_properties'),
			('dbo','tbl_DisabledIndexes'),
			('dbo','tbl_server_times'),
			('dbo','tbl_resource_governor_configuration'),
			('dbo','tbl_resource_governor_resource_pools'),
			('dbo','tbl_resource_governor_workload_groups'),
			('dbo','tbl_Hist_Top10_CPU_Queries_by_Planhash_and_Queryhash'),
			('dbo','tbl_Hist_Top10_CPU_Queries_ByQueryHash'),
			('dbo','tbl_Hist_Top10_ElapsedTime_Queries_by_Planhash_and_Queryhash'),
			('dbo','tbl_Hist_Top10_ElapsedTime_Queries_ByQueryHash'),
			('dbo','tbl_Hist_Top10_LogicalReads_Queries_by_Planhash_and_Queryhash'),
			('dbo','tbl_Hist_Top10_LogicalReads_Queries_ByQueryHash'),
			('dbo','tbl_database_scoped_configurations'),
			('dbo','tbl_dm_db_file_space_usage_summary'),
			('dbo','tbl_tempdb_space_usage_by_file'),
			('dbo','tbl_transaction_perfmon_counters'),
			('dbo','tbl_dm_db_session_space_usage'),
			('dbo','tbl_dm_db_task_space_usage'),
			('dbo','tbl_version_store_transactions'),
			('dbo','tbl_open_transactions'),
			('dbo','tbl_tempdb_usage_by_object'),
			('dbo','tbl_tempdb_waits'),
			('dbo','Counters'),
			('dbo','CounterDetails'),
			('dbo','CounterData'),
			('dbo','DisplayToID'),
			('dbo','tbl_query_store_runtime_stats_interval'),
			('dbo','tbl_query_store_runtime_stats'),
			('dbo','tbl_query_store_query'),
			('dbo','tbl_query_store_query_text'),
			('dbo','tbl_query_store_plan'),
			('dbo','tbl_query_store_wait_stats'),
			('dbo','tbl_database_query_store_options'),
			('dbo','tbl_query_store_query_hints'),
			('dbo','tbl_query_store_plan_feedback'),
			('dbo','tbl_query_store_query_variant'),
			('dbo','tbl_profiler_trace_summary') ,
			('dbo','tbl_profiler_trace_event_details') ,
			('dbo','tbl_XEvents'),
			('dbo','tbl_dm_db_xtp_transactions'),
			('dbo','tbl_dm_xtp_transaction_stats')

		--now go through each scenario and the tables expected for it
		IF (@scenarioname = 'AlwaysOn')
		BEGIN
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('dbo','tbl_hadr_endpoints_principals'),
			('dbo','tbl_hadr_mirroring_endpoints_permissions'),
			('dbo','tbl_hadr_mirroring_states'),
			('dbo','tbl_hadr_ag_listeners'),
			('dbo','tbl_hadr_ag_ip_information'),
			('dbo','tbl_hadr_readonly_routing'),
			('dbo','tbl_hadr_cluster'),
			('dbo','tbl_hadr_cluster_members'),
			('dbo','tbl_hadr_ag_states'),
			('dbo','tbl_hadr_ag_replica_states'),
			('dbo','tbl_hadr_dm_os_server_diagnostics_log_configurations'),
			('dbo','tbl_hadr_alwayson_health_alwayson_ddl_executed'),
			('dbo','tbl_hadr_alwayson_health_failovers'),
			('dbo','tbl_hadr_alwayson_health_availability_replica_manager_state_change'),
			('dbo','tbl_hadr_alwayson_health_availability_replica_state_change'),
			('dbo','tbl_hadr_alwayson_health_availability_group_lease_expired'),
			('dbo','tbl_hadr_ag_automatic_seeding'),
			('dbo','tbl_hadr_ag_physical_seeding_stats'),
			('ReadTrace','tblUniqueBatches'),
			('ReadTrace','tblUniqueStatements'),
			('ReadTrace','tblUniquePlans'),
			('ReadTrace','tblUniquePlanRows'),
			('ReadTrace','tblBatches'),
			('ReadTrace','tblStatements'),
			('ReadTrace','tblPlans'),
			('ReadTrace','tblPlanRows'),
			('ReadTrace','tblInterestingEvents'),
			('ReadTrace','tblConnections'),
			('ReadTrace','tblTimeIntervals'),
			('ReadTrace','tblTraceFiles'),
			('ReadTrace','tblTracedEvents'),
			('ReadTrace','tblBatchPartialAggs'),
			('dbo','Counters'),
			('ReadTrace','tblComparisonBatchPartialAggs'),
			('ReadTrace','tblStmtPartialAggs'),
			('ReadTrace','tblWarnings'),
			('ReadTrace','tblMiscInfo'),
			('ReadTrace','tblProcedureNames'),
			('ReadTrace','tblUniqueAppNames'),
			('ReadTrace','tblUniqueLoginNames'),
			('dbo','CounterDetails'),
			('dbo','CounterData'),
			('dbo','DisplayToID')						

			--insert the tables for Basic scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 
			
		END
		ELSE IF ((@scenarioname = 'GeneralPerf') Or (@scenarioname = 'DetailedPerf'))
		BEGIN
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('ReadTrace','tblUniqueBatches'),
			('ReadTrace','tblUniqueStatements'),
			('ReadTrace','tblUniquePlans'),
			('ReadTrace','tblUniquePlanRows'),
			('ReadTrace','tblBatches'),
			('ReadTrace','tblStatements'),
			('ReadTrace','tblPlans'),
			('ReadTrace','tblPlanRows'),
			('ReadTrace','tblInterestingEvents'),
			('ReadTrace','tblConnections'),
			('ReadTrace','tblTimeIntervals'),
			('ReadTrace','tblTraceFiles'),
			('ReadTrace','tblTracedEvents'),
			('ReadTrace','tblBatchPartialAggs'),
			('ReadTrace','tblComparisonBatchPartialAggs'),
			('ReadTrace','tblStmtPartialAggs'),
			('ReadTrace','tblWarnings'),
			('ReadTrace','tblMiscInfo'),
			('ReadTrace','tblProcedureNames'),
			('ReadTrace','tblUniqueAppNames'),
			('ReadTrace','tblUniqueLoginNames')
		
			--insert the tables for LightPerf scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_LightPerfScenario
			
			--insert the tables for Basic scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 
		END
		ELSE IF ((@scenarioname = 'Setup'))
		BEGIN
			-- insert the tables for Setup scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('dbo','tbl_setup_missing_msi_msp_packages')

			--insert the tables for Basic scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 
		END
		ELSE IF (@scenarioname = 'BackupRestore')
		BEGIN
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('dbo','CounterDetails'),
			('dbo','CounterData'),
			('dbo','DisplayToID'),
			('ReadTrace','tblUniqueBatches'),
			('ReadTrace','tblUniqueStatements'),
			('ReadTrace','tblUniquePlans'),
			('ReadTrace','tblUniquePlanRows'),
			('ReadTrace','tblBatches'),
			('ReadTrace','tblStatements'),
			('ReadTrace','tblPlans'),
			('ReadTrace','tblPlanRows'),
			('ReadTrace','tblInterestingEvents'),
			('ReadTrace','tblConnections'),
			('ReadTrace','tblTimeIntervals'),
			('ReadTrace','tblTraceFiles'),
			('ReadTrace','tblTracedEvents'),
			('ReadTrace','tblBatchPartialAggs'),
			('ReadTrace','tblComparisonBatchPartialAggs'),
			('ReadTrace','tblStmtPartialAggs'),
			('ReadTrace','tblWarnings'),
			('ReadTrace','tblMiscInfo'),
			('ReadTrace','tblProcedureNames'),
			('ReadTrace','tblUniqueAppNames'),
			('ReadTrace','tblUniqueLoginNames')
			
						
			--insert the tables for Basic scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 

		END
		ELSE IF (@scenarioname = 'IO')
		BEGIN
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('dbo','Counters'),
			('dbo','CounterDetails'),
			('dbo','CounterData'),
			('dbo','DisplayToID'),
			('dbo','tbl_AnalysisSummary'),
			('dbo','tbl_dm_io_virtual_file_stats')

			--insert the tables for Basic scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 

		END
		ELSE IF (@scenarioname = 'LightPerf')
		BEGIN

			--insert the tables for LightPerf scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_LightPerfScenario


			--insert the tables for Basic scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 

		END

		ELSE IF (@scenarioname = 'Replication')
		BEGIN
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('dbo','tbl_repl_sourceserver'),
			('dbo','tbl_repl_msdb_jobs'),
			('dbo','tbl_repl_msarticles'),
			('dbo','tbl_repl_mscached_peer_lsns'),
			('dbo','tbl_repl_msdistribution_agents'),
			('dbo','tbl_repl_msdistribution_history'),
			('dbo','tbl_repl_mslogreader_agents'),
			('dbo','tbl_repl_mslogreader_history'),
			('dbo','tbl_repl_msmerge_agents'),
			('dbo','tbl_repl_msmerge_history'),
			('dbo','tbl_repl_msmerge_identity_range_allocations'),
			('dbo','tbl_repl_msmerge_sessions'),
			('dbo','tbl_repl_msmerge_subscriptions'),
			('dbo','tbl_repl_mspublication_access'),
			('dbo','tbl_repl_mspublications'),
			('dbo','tbl_repl_mspublicationthresholds'),
			('dbo','tbl_repl_mspublisher_databases'),
			('dbo','tbl_repl_msqreader_agents'),
			('dbo','tbl_repl_msrepl_backup_lsns'),
			('dbo','tbl_repl_msrepl_commands_oldest'),
			('dbo','tbl_repl_msrepl_commands_newest'),
			('dbo','tbl_repl_msrepl_errors'),
			('dbo','tbl_repl_msrepl_identity_range'),
			('dbo','tbl_repl_msrepl_originators'),
			('dbo','tbl_repl_msrepl_transactions_oldest'),
			('dbo','tbl_repl_msrepl_transactions_newest'),
			('dbo','tbl_repl_msrepl_version'),
			('dbo','tbl_repl_msreplication_monitordata'),
			('dbo','tbl_repl_mssnapshot_agents'),
			('dbo','tbl_repl_mssnapshot_history'),
			('dbo','tbl_repl_mssubscriber_info'),
			('dbo','tbl_repl_mssubscriber_schedule'),
			('dbo','tbl_repl_mssubscriptions'),
			('dbo','tbl_repl_mssync_states'),
			('dbo','tbl_repl_mstracer_history'),
			('dbo','tbl_repl_mstracer_tokens'),
			('dbo','tbl_repl_sysservers'),
			('dbo','tbl_Reports'),
			('dbo','tbl_repl_msdb_jobhistory'),
			('dbo','tbl_repl_msdb_msagent_profileandparameters')
			
			--insert the tables for Basic scenario
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 

		END

		ELSE IF (@scenarioname = 'Memory')
		BEGIN
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('dbo','tbl_Query_Execution_Memory_MemScript'),
			('dbo','tbl_proccache_summary'),
			('dbo','tbl_proccache_pollution'),
			('dbo','tbl_DM_OS_MEMORY_CACHE_COUNTERS'),
			('dbo','tbl_DM_OS_MEMORY_CLERKS'),
			('dbo','tbl_DM_OS_MEMORY_CACHE_CLOCK_HANDS'),
			('dbo','tbl_DM_OS_MEMORY_CACHE_HASH_TABLES'),
			('dbo','tbl_dm_os_memory_pools'),
			('dbo','tbl_dm_os_loaded_modules_non_microsoft'),
			('dbo','tbl_dm_os_memory_objects'),
			('dbo','tbl_workingset_trimming'),
			('dbo','tbl_dm_os_ring_buffers_mem'),
			('dbo','tbl_dm_db_xtp_index_stats'),
            ('dbo','tbl_dm_db_xtp_hash_index_stats'),
            ('dbo','tbl_dm_db_xtp_table_memory_stats'),
            ('dbo','tbl_dm_db_xtp_memory_consumers'),
            ('dbo','tbl_dm_db_xtp_object_stats'),
            ('dbo','tbl_dm_xtp_system_memory_consumers'),
            ('dbo','tbl_dm_xtp_system_memory_consumers_summary'),
            ('dbo','tbl_dm_xtp_gc_stats'),
            ('dbo','tbl_dm_xtp_gc_queue_stats')
			
			--add the basic scenario tables
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 

		END
		ELSE IF (@scenarioname = 'ServiceBrokerDBMail')
		BEGIN
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('dbo','tbl_sysmail_profileaccount'),
			('dbo','tbl_sysmail_profile'),
			('dbo','tbl_sysmail_log'),
			('dbo','tbl_sysmail_configuration'),
			('dbo','tbl_sysmail_account'),
			('dbo','tbl_sysmail_mailitems'),
            ('dbo','tbl_sysmail_event_log_sysmail_faileditems'),
			('dbo','tbl_sysmail_server')
			
			--add the basic scenario tables
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 

		END

		ELSE IF (@scenarioname = 'NeverEndingQuery')
		BEGIN
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) VALUES
			('dbo','tbl_CPU_bound_query_never_completes')

			--add the basic scenario tables
			INSERT INTO #temptablelist_sqlnexus (SchemaName,TableName) 
            SELECT SchemaName,TableName FROM #tablelist_BasicScenario 

		END
		
		--call the stored proc to implement exceptions
		EXEC dbo.proc_ExclusionsInclusions @scenario_name = @scenarioname , @database_name = @databasename, @exclusion_tag = @exclusion
		
		--select from the table to show any missing tables
		Exec(
		'SELECT '''+ @databasename+''' DBName ,t1.SchemaName, t1.TableName , ''No'' Present 
		FROM #temptablelist_sqlnexus t1 
			LEFT OUTER JOIN '+ @databasename+'.INFORMATION_SCHEMA.TABLES t2
			ON t1.tablename = t2.TABLE_NAME and t1.SchemaName = t2.TABLE_SCHEMA 
		WHERE t2.TABLE_NAME IS NULL AND t2.TABLE_SCHEMA IS NULL 
		ORDER BY t1.TableName')
		
		--if there rows here, we found a missing table so send some large-value, unique code out to check for that
		--else send some other large value code back out to indicate success
		IF (@@ROWCOUNT > 0)
		BEGIN
		    SELECT ' '
			SELECT 2002002 AS EXIT_CODE
		END
		ELSE
		BEGIN
		    SELECT ' '
			SELECT 1001001 AS EXIT_CODE
		END
	END
	ELSE
	BEGIN
		--if the db name or scenario name is invalid, send some large value code out to indicate failure
		SELECT 'Scenario name or database name is invalid' as 'Error_Message'
		SELECT 3003003 AS EXIT_CODE
	END
END
GO
--exec tempdb..proc_SqlNexusTableValidation 'LightPerf','sqlnexus'
