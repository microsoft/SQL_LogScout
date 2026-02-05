
    function SQL_Server_PerfStats_Snapshot_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "SQL_Server_PerfStats_Snapshot"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
USE tempdb
GO
SET NOCOUNT ON
SET QUOTED_IDENTIFIER ON
SET ANSI_NULLS ON
SET ANSI_PADDING ON
SET ANSI_WARNINGS ON
SET ARITHABORT ON
SET CONCAT_NULL_YIELDS_NULL ON
SET QUOTED_IDENTIFIER ON
SET NUMERIC_ROUNDABORT OFF
GO

/*******************************************************************
perf stats snapshot

********************************************************************/
use tempdb
go
IF OBJECT_ID ('#sp_perf_stats_snapshot','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot
GO

CREATE PROCEDURE #sp_perf_stats_snapshot  
as
begin
	BEGIN TRY

		PRINT 'Starting SQL Server Perf Stats Snapshot Script...'
		PRINT 'SQL Version (SP)         ' + CONVERT (varchar, SERVERPROPERTY ('ProductVersion')) + ' (' + CONVERT (varchar, SERVERPROPERTY ('ProductLevel')) + ')'
		DECLARE @runtime datetime 
		DECLARE @cpu_time_start bigint, @cpu_time bigint, @elapsed_time_start bigint, @rowcount bigint
		DECLARE @queryduration int, @qrydurationwarnthreshold int
		DECLARE @querystarttime datetime
		SET @runtime = GETDATE()
		SET @qrydurationwarnthreshold = 5000

		PRINT ''
		PRINT 'Start time: ' + CONVERT (varchar(30), @runtime, 126)
		PRINT ''
		PRINT '-- Top N Query Plan Statistics --'
		SELECT @cpu_time_start = cpu_time FROM sys.dm_exec_sessions WHERE session_id = @@SPID
		SET @querystarttime = GETDATE()
		SELECT 
		CONVERT (varchar(30), @runtime, 126) AS 'runtime', 
		LEFT (p.cacheobjtype + ' (' + p.objtype + ')', 35) AS 'cacheobjtype',
		p.usecounts, p.size_in_bytes / 1024 AS 'size_in_kb',
		PlanStats.total_worker_time/1000 AS 'tot_cpu_ms', PlanStats.total_elapsed_time/1000 AS 'tot_duration_ms', 
		PlanStats.total_physical_reads, PlanStats.total_logical_writes, PlanStats.total_logical_reads,
		PlanStats.CpuRank, PlanStats.PhysicalReadsRank, PlanStats.DurationRank, 
		LEFT (CASE 
			WHEN pa.value=32767 THEN 'ResourceDb' 
			ELSE ISNULL (DB_NAME (CONVERT (sysname, pa.value)), CONVERT (sysname,pa.value))
		END, 40) AS 'dbname',
		sql.objectid, 
		CONVERT (nvarchar(50), CASE 
			WHEN sql.objectid IS NULL THEN NULL 
			ELSE REPLACE (REPLACE (sql.[text],CHAR(13), ' '), CHAR(10), ' ')
		END) AS 'procname', 
		REPLACE (REPLACE (SUBSTRING (sql.[text], PlanStats.statement_start_offset/2 + 1, 
			CASE WHEN PlanStats.statement_end_offset = -1 THEN LEN (CONVERT(nvarchar(max), sql.[text])) 
				ELSE PlanStats.statement_end_offset/2 - PlanStats.statement_start_offset/2 + 1
			END), CHAR(13), ' '), CHAR(10), ' ') AS 'stmt_text' 
		,PlanStats.query_hash, PlanStats.query_plan_hash, PlanStats.creation_time, PlanStats.statement_start_offset, PlanStats.statement_end_offset, PlanStats.plan_generation_num,
		PlanStats.min_worker_time, PlanStats.last_worker_time, PlanStats.max_worker_time,
		PlanStats.min_elapsed_time, PlanStats.last_elapsed_time, PlanStats.max_elapsed_time,
		PlanStats.min_physical_reads, PlanStats.last_physical_reads, PlanStats.max_physical_reads, 
		PlanStats.min_logical_writes, PlanStats.last_logical_writes, PlanStats.max_logical_writes, 
		PlanStats.min_logical_reads, PlanStats.last_logical_reads, PlanStats.max_logical_reads,
		PlanStats.plan_handle
		FROM 
		(
		SELECT 
			stat.plan_handle, statement_start_offset, statement_end_offset, 
			stat.total_worker_time, stat.total_elapsed_time, stat.total_physical_reads, 
			stat.total_logical_writes, stat.total_logical_reads,
			stat.query_hash, stat.query_plan_hash, stat.plan_generation_num, stat.creation_time, 
			stat.last_worker_time, stat.min_worker_time, stat.max_worker_time, stat.last_elapsed_time, stat.min_elapsed_time, stat.max_elapsed_time,
			stat.last_physical_reads, stat.min_physical_reads, stat.max_physical_reads, stat.last_logical_writes, stat.min_logical_writes, stat.max_logical_writes, stat.last_logical_reads, stat.min_logical_reads, stat.max_logical_reads,
			ROW_NUMBER() OVER (ORDER BY stat.total_worker_time DESC) AS CpuRank, 
			ROW_NUMBER() OVER (ORDER BY stat.total_physical_reads DESC) AS PhysicalReadsRank, 
			ROW_NUMBER() OVER (ORDER BY stat.total_elapsed_time DESC) AS DurationRank 
		FROM sys.dm_exec_query_stats stat 
		) AS PlanStats 
		INNER JOIN sys.dm_exec_cached_plans p ON p.plan_handle = PlanStats.plan_handle 
		OUTER APPLY sys.dm_exec_plan_attributes (p.plan_handle) pa 
		OUTER APPLY sys.dm_exec_sql_text (p.plan_handle) AS sql
		WHERE (PlanStats.CpuRank < 50 OR PlanStats.PhysicalReadsRank < 50 OR PlanStats.DurationRank < 50)
		AND pa.attribute = 'dbid' 
		ORDER BY tot_cpu_ms DESC
		OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)

		SET @rowcount = @@ROWCOUNT
		SET @queryduration = DATEDIFF (ms, @querystarttime, GETDATE())
		IF @queryduration > @qrydurationwarnthreshold
		BEGIN
		SELECT @cpu_time = cpu_time - @cpu_time_start FROM sys.dm_exec_sessions WHERE session_id = @@SPID
		PRINT ''
		PRINT 'DebugPrint: perfstats_snapshot_querystats - ' + CONVERT (varchar, @queryduration) + 'ms, ' 
			+ CONVERT (varchar, @cpu_time) + 'ms cpu, '
			+ 'rowcount=' + CONVERT(varchar, @rowcount) 
		PRINT ''
		END

		PRINT ''
		PRINT '==============================================================================================='
		PRINT 'Missing Indexes: '
		PRINT 'The `"improvement_measure`" column is an indicator of the (estimated) improvement that might '
		PRINT 'be seen if the index was created.  This is a unitless number, and has meaning only relative '
		PRINT 'the same number for other indexes.  The measure is a combination of the avg_total_user_cost, '
		PRINT 'avg_user_impact, user_seeks, and user_scans columns in sys.dm_db_missing_index_group_stats.'
		PRINT ''
		PRINT '-- Missing Indexes --'
		SELECT CONVERT (varchar(30), @runtime, 126) AS runtime, 
		mig.index_group_handle, mid.index_handle, 
		CONVERT (bigint, migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans)) AS improvement_measure, 
		'CREATE INDEX missing_index_' + CONVERT (varchar, mig.index_group_handle) + '_' + CONVERT (varchar, mid.index_handle) 
		+ ' ON ' + mid.statement 
		+ ' (' + ISNULL (mid.equality_columns,'') 
			+ CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END + ISNULL (mid.inequality_columns, '')
		+ ')' 
		+ ISNULL (' INCLUDE (' + mid.included_columns + ')', '') AS create_index_statement, 
		migs.*, mid.database_id, mid.[object_id]
		FROM sys.dm_db_missing_index_groups mig
		INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
		INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
		WHERE CONVERT (bigint, migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans)) > 10
		ORDER BY improvement_measure DESC
		OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)

		PRINT ''
		PRINT ''

		PRINT '-- Current database options --'
		SELECT LEFT ([name], 128) AS [name], 
		dbid, cmptlevel, 
		CONVERT (int, (SELECT SUM (CONVERT (bigint, [size])) * 8192 / 1024 / 1024 FROM master.sys.master_files f WHERE f.database_id = d.dbid)) AS db_size_in_mb, 
		LEFT (
		'Status=' + CONVERT (sysname, DATABASEPROPERTYEX ([name],'Status')) 
		+ ', Updateability=' + CONVERT (sysname, DATABASEPROPERTYEX ([name],'Updateability')) 
		+ ', UserAccess=' + CONVERT (varchar(40), DATABASEPROPERTYEX ([name], 'UserAccess')) 
		+ ', Recovery=' + CONVERT (varchar(40), DATABASEPROPERTYEX ([name], 'Recovery')) 
		+ ', Version=' + CONVERT (varchar(40), DATABASEPROPERTYEX ([name], 'Version')) 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsAutoCreateStatistics') = 1 THEN ', IsAutoCreateStatistics' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsAutoUpdateStatistics') = 1 THEN ', IsAutoUpdateStatistics' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsShutdown') = 1 THEN '' ELSE ', Collation=' + CONVERT (varchar(40), DATABASEPROPERTYEX ([name], 'Collation'))  END
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsAutoClose') = 1 THEN ', IsAutoClose' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsAutoShrink') = 1 THEN ', IsAutoShrink' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsInStandby') = 1 THEN ', IsInStandby' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsTornPageDetectionEnabled') = 1 THEN ', IsTornPageDetectionEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsAnsiNullDefault') = 1 THEN ', IsAnsiNullDefault' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsAnsiNullsEnabled') = 1 THEN ', IsAnsiNullsEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsAnsiPaddingEnabled') = 1 THEN ', IsAnsiPaddingEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsAnsiWarningsEnabled') = 1 THEN ', IsAnsiWarningsEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsArithmeticAbortEnabled') = 1 THEN ', IsArithmeticAbortEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsCloseCursorsOnCommitEnabled') = 1 THEN ', IsCloseCursorsOnCommitEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsFullTextEnabled') = 1 THEN ', IsFullTextEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsLocalCursorsDefault') = 1 THEN ', IsLocalCursorsDefault' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsNumericRoundAbortEnabled') = 1 THEN ', IsNumericRoundAbortEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsQuotedIdentifiersEnabled') = 1 THEN ', IsQuotedIdentifiersEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsRecursiveTriggersEnabled') = 1 THEN ', IsRecursiveTriggersEnabled' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsMergePublished') = 1 THEN ', IsMergePublished' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsPublished') = 1 THEN ', IsPublished' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsSubscribed') = 1 THEN ', IsSubscribed' ELSE '' END 
		+ CASE WHEN DATABASEPROPERTYEX ([name], 'IsSyncWithBackup') = 1 THEN ', IsSyncWithBackup' ELSE '' END
		, 512) AS status
		FROM master.dbo.sysdatabases d
		PRINT ''
		
		print '-- sys.dm_database_encryption_keys TDE --'
		declare @sql_major_version INT, @sql_major_build INT, @sql nvarchar (max)
		SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT)), 
			@sql_major_build = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT)) 
		set @sql = 'select DB_NAME(database_id) as ''database_name'', 
					[database_id]
					,[encryption_state]
					,[create_date]
					,[regenerate_date]
					,[modify_date]
					,[set_date]
					,[opened_date]
					,[key_algorithm]
					,[key_length]
					,[encryptor_thumbprint]
					,[percent_complete]'

		IF (@sql_major_version >=11)
		BEGIN	   
		set @sql = @sql + ',[encryptor_type]'
		END
		
		IF (@sql_major_version >=15)
		BEGIN	   
		set @sql = @sql + '[encryption_state_desc]
							,[encryption_scan_state]
							,[encryption_scan_state_desc]
							,[encryption_scan_modify_date]'
		END

		set @sql = @sql + ' from sys.dm_database_encryption_keys '
		
		--print @sql
		exec (@sql)
		
		PRINT ''

		

		print '-- sys.dm_server_audit_status --'
		select  
			audit_id,
			[name],
			[status],
			status_desc,
			status_time,
			event_session_address,
			audit_file_path,
			audit_file_size
		from sys.dm_server_audit_status
		print ''

		print '-- top 10 CPU consuming procedures --'
		SELECT TOP 10 getdate() as runtime, d.object_id, d.database_id, db_name(database_id) 'db name', object_name (object_id, database_id) 'proc name',  d.cached_time, d.last_execution_time, d.total_elapsed_time, d.total_elapsed_time/d.execution_count AS [avg_elapsed_time], d.last_elapsed_time, d.execution_count
		from sys.dm_exec_procedure_stats d
		ORDER BY [total_worker_time] DESC
		print ''

		print '-- top 10 CPU consuming triggers --'
		SELECT TOP 10 getdate() as runtime, d.object_id, d.database_id, db_name(database_id) 'db name', object_name (object_id, database_id) 'proc name',  d.cached_time, d.last_execution_time, d.total_elapsed_time, d.total_elapsed_time/d.execution_count AS [avg_elapsed_time], d.last_elapsed_time, d.execution_count
		from sys.dm_exec_trigger_stats d
		ORDER BY [total_worker_time] DESC
		print ''

		--new stats DMV
		set nocount on
		declare @dbname sysname, @dbid int

		SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT)), 
			@sql_major_build = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT)) 
		
		
		DECLARE dbCursor CURSOR FOR 
		select name, database_id from sys.databases where state_desc='ONLINE' and name not in ('model','tempdb') order by name
		OPEN dbCursor

		FETCH NEXT FROM dbCursor  INTO @dbname, @dbid
		
		--replaced sys.dm_db_index_usage_stats  by sys.stat since the first doesn't return anything in case the table or index was not accessed since last SQL restart
		select @dbid 'Database_Id', @dbname 'Database_Name',  Object_name(st.object_id) 'Object_Name', SCHEMA_NAME(schema_id) 'Schema_Name', ss.name 'Statistics_Name', 
				st.object_id, st.stats_id, st.last_updated, st.rows, st.rows_sampled, st.steps, st.unfiltered_rows, st.modification_counter
		into #tmpStats 
		from sys.stats ss cross apply sys.dm_db_stats_properties (ss.object_id, ss.stats_id) st inner join sys.objects so ON (ss.object_id = so.object_id) where 1=0
		
		--column st.persisted_sample_percent was only introduced on sys.dm_db_stats_properties on SQL Server 2016 (13.x) SP1 CU4 -- 13.0.4446.0 and 2017 CU1 14.0.3006.16	 
		IF (@sql_major_version >14 OR (@sql_major_version=13 AND @sql_major_build>=4446) OR (@sql_major_version=14 AND @sql_major_build>=3006))
		BEGIN
			ALTER TABLE #tmpStats ADD persisted_sample_percent FLOAT
		END

		WHILE @@FETCH_STATUS = 0
		BEGIN
			BEGIN TRY
			
				set @sql = 'USE [' + @dbname + ']'
				--replaced sys.dm_db_index_usage_stats  by sys.stat since the first doesn't return anything in case the table or index was not accessed since last SQL restart
				IF (@sql_major_version >14 OR (@sql_major_version=13 AND @sql_major_build>=4446) OR (@sql_major_version=14 AND @sql_major_build>=3006))
				BEGIN
					set @sql = @sql + '	insert into #tmpStats	select ' + cast( @dbid as nvarchar(20)) +   ' ''Database_Id''' + ',''' +  @dbname  + ''' Database_Name,  Object_name(st.object_id) ''Object_Name'', SCHEMA_NAME(schema_id) ''Schema_Name'', ss.name ''Statistics_Name'', 
																		st.object_id, st.stats_id, st.last_updated, st.rows, st.rows_sampled, st.steps, st.unfiltered_rows, st.modification_counter, st.persisted_sample_percent
																from sys.stats ss 
																	cross apply sys.dm_db_stats_properties (ss.object_id, ss.stats_id) st 
																	inner join sys.objects so ON (ss.object_id = so.object_id)
																where so.type not in (''S'', ''IT'')'
				END
				ELSE
				BEGIN

				set @sql = @sql + '	insert into #tmpStats	select ' + cast( @dbid as nvarchar(20)) +   ' ''Database_Id''' + ',''' +  @dbname  + ''' Database_Name,  Object_name(st.object_id) ''Object_Name'', SCHEMA_NAME(schema_id) ''Schema_Name'', ss.name ''Statistics_Name'', 
																		st.object_id, st.stats_id, st.last_updated, st.rows, st.rows_sampled, st.steps, st.unfiltered_rows, st.modification_counter
																from sys.stats ss 
																cross apply sys.dm_db_stats_properties (ss.object_id, ss.stats_id) st 
																inner join sys.objects so ON (ss.object_id = so.object_id)
																where so.type not in (''S'', ''IT'')'
				
				END
				
				-- added this check to prevent script from failing on principals with restricted access
				if HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
					
					exec (@sql)
				else
					PRINT 'Skipped index usage and stats properties check. Principal ' + SUSER_SNAME() + ' does not have CONNECT permission on database ' + @dbname
				--print @sql
				FETCH NEXT FROM dbCursor  INTO @dbname, @dbid
			END TRY
			BEGIN CATCH
				PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
				PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
			END CATCH
		END
		close  dbCursor
		deallocate dbCursor
		print ''
		print '-- sys.dm_db_stats_properties --'
		declare @sql2 nvarchar (max)

		IF (@sql_major_version >14 OR (@sql_major_version=13 AND @sql_major_build>=4446) OR (@sql_major_version=14 AND @sql_major_build>=3006))
		BEGIN
			set @sql2 = 'select --*
							Database_Id,
							[Database_Name],
							[Schema_Name],
							[Object_Name],
							[object_id],
							[stats_id],
							[Statistics_Name],
							[last_updated],
							[rows],
							rows_sampled,
							steps,
							unfiltered_rows,
							modification_counter,
							persisted_sample_percent
						from #tmpStats 
						order by [Database_Name]'
		
		END
		ELSE
		BEGIN
		set @sql2 = 'select --*
						Database_Id,
						[Database_Name],
						[Schema_Name],
						[Object_Name],
						[object_id],
						[stats_id],
						[Statistics_Name],
						[last_updated],
						[rows],
						rows_sampled,
						steps,
						unfiltered_rows,
						modification_counter
					from #tmpStats 
					order by [Database_Name]'
		END

		exec (@sql2)
		drop table #tmpStats
		print ''

		--get disabled indexes
		--import in SQLNexus

		set nocount on
		declare @dbname_index sysname, @dbid_index int
		DECLARE dbCursor_Index CURSOR FOR 
		select QUOTENAME(name) name, database_id from sys.databases where state_desc='ONLINE' and database_id > 4 order by name
		OPEN dbCursor_Index

		FETCH NEXT FROM dbCursor_Index  INTO @dbname_index, @dbid_index
		select db_id() 'database_id', db_name() 'database_name', object_name(object_id) 'object_name', object_id,
												name,
												index_id, 
												type, 
												type_desc, 
												is_disabled into #tblDisabledIndex from sys.indexes where is_disabled = 1 and 1=0 


		WHILE @@FETCH_STATUS = 0
		BEGIN
			BEGIN TRY
				declare @sql_index nvarchar (max)
				set @sql_index = 'USE ' + @dbname_index
			
				set @sql_index = @sql_index + '	insert into #tblDisabledIndex	
												select  db_id()  database_id, 
													db_name() database_name, 
													object_name(object_id) object_name, 
													object_id,
													name,
													index_id, 
													type, 
													type_desc, 
													is_disabled
												from sys.indexes where is_disabled = 1'
			
				-- added this check to prevent script from failing on principals with restricted access
				if HAS_PERMS_BY_NAME(@dbname_index, 'DATABASE', 'CONNECT') = 1
					exec (@sql_index)
				else
					PRINT 'Skipped disabled indexes check. Principal ' + SUSER_SNAME() + ' does not have CONNECT permission on database ' + @dbname
				--print @sql
				FETCH NEXT FROM dbCursor_Index  INTO @dbname_index, @dbid_index
			END TRY
			BEGIN CATCH
				PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
				PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
			END CATCH
		END
		close  dbCursor_Index
		deallocate dbCursor_Index
		print ''
		print '--disabled indexes--'
		select * from #tblDisabledIndex order by database_name
		drop table #tblDisabledIndex
		print ''


		print '-- server_times --'
		select CONVERT (varchar(30), getdate(), 126) as server_time, CONVERT (varchar(30), getutcdate(), 126)  utc_time, DATEDIFF(hh, getutcdate(), getdate() ) time_delta_hours

		/*
		this takes too long for large machines
			PRINT '-- High Compile Queries --';
		WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)  
		select   
		stmt.stmt_details.value ('(./sp:QueryPlan/@CompileTime)[1]', 'int') 'CompileTime',
		stmt.stmt_details.value ('(./sp:QueryPlan/@CompileCPU)[1]', 'int') 'CompileCPU',
		SUBSTRING(replace(replace(stmt.stmt_details.value ('@StatementText', 'nvarchar(max)'), char(13), ' '), char(10), ' '), 1, 8000) 'Statement'
		from (   SELECT  query_plan as sqlplan FROM sys.dm_exec_cached_plans AS qs CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle))
		as p       cross apply sqlplan.nodes('//sp:StmtSimple') as stmt (stmt_details)
		order by 1 desc;
		*/
		RAISERROR ('', 0, 1) WITH NOWAIT;
	END TRY
	BEGIN CATCH
		PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
		PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	END CATCH
END
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot9','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot9
GO

CREATE PROCEDURE #sp_perf_stats_snapshot9 
AS
BEGIN
	exec #sp_perf_stats_snapshot
END
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot10','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot10
GO

CREATE PROCEDURE #sp_perf_stats_snapshot10
AS
BEGIN
	BEGIN TRY
		exec #sp_perf_stats_snapshot9

		print 'getting resource governor info'
		print '=========================================='
		print ''
		
		print '-- sys.resource_governor_configuration --'
		declare @sql_major_version INT, @sql_major_build INT, @sql nvarchar (max)

		SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT)), 
			@sql_major_build = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT)) 
		
		BEGIN
		SET @sql = 'select --* 
						classifier_function_id,
						is_enabled'
		
		IF (@sql_major_version >12)
		BEGIN
			SET @sql = @sql + ',[max_outstanding_io_per_volume]'
		END
		
		SET @sql = @sql + ' from sys.resource_governor_configuration;'
		
		--print @sql
		
		exec (@sql)
		
		END
		print ''
		
		print '-- sys.resource_governor_resource_pools --'
		SET @sql ='select --* 
					pool_id,
					[name],
					min_cpu_percent,
					max_cpu_percent,
					min_memory_percent,
					max_memory_percent'
		IF (@sql_major_version >=11)
		BEGIN
		SET @sql = @sql + ',cap_cpu_percent'
		END
		IF (@sql_major_version >=12)
		BEGIN
		SET @sql = @sql + ',min_iops_per_volume, max_iops_per_volume'
		END

		SET @sql = @sql + ' from sys.resource_governor_resource_pools;'

		--print @sql
		
		exec (@sql)    		 
				
		print ''
		
		print '-- sys.resource_governor_workload_groups --'
		SET @sql ='select --* 
					group_id,
					[name],
					importance,
					request_max_memory_grant_percent,
					request_max_cpu_time_sec,
					request_memory_grant_timeout_sec,
					max_dop,
					group_max_requests,
					pool_id'
		IF (@sql_major_version >=13)
		BEGIN
		SET @sql = @sql + ',external_pool_id'
		END

		SET @sql = @sql + ' from sys.resource_governor_workload_groups'
		
		--print @sql
		
		exec (@sql)    		 

		print ''
		
		print 'Query and plan hash capture '


		--import in SQLNexus	
		print '-- top 10 CPU by query_hash --'
		select getdate() as runtime, *  --into tbl_QueryHashByCPU
		from
		(
		SELECT TOP 10 query_hash, COUNT (distinct query_plan_hash) as 'distinct query_plan_hash count',
			sum(execution_count) as 'execution_count', 
			sum(total_worker_time) as 'total_worker_time',
			SUM(total_elapsed_time) as 'total_elapsed_time',
			SUM (total_logical_reads) as 'total_logical_reads',
		
			max(REPLACE (REPLACE (SUBSTRING (st.[text], qs.statement_start_offset/2 + 1, 
			CASE WHEN qs.statement_end_offset = -1 THEN LEN (CONVERT(nvarchar(max), st.[text])) 
				ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
			END), CHAR(13), ' '), CHAR(10), ' '))  AS sample_statement_text
		FROM sys.dm_exec_query_stats AS qs
		CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
		group by query_hash
		ORDER BY sum(total_worker_time) DESC
		) t
		OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)

		print ''


		--import in SQLNexus
		print '-- top 10 logical reads by query_hash --'
		select getdate() as runtime, *  --into tbl_QueryHashByLogicalReads
		from
		(
		SELECT TOP 10 query_hash, 
			COUNT (distinct query_plan_hash) as 'distinct query_plan_hash count',
			sum(execution_count) as 'execution_count', 
			sum(total_worker_time) as 'total_worker_time',
			SUM(total_elapsed_time) as 'total_elapsed_time',
			SUM (total_logical_reads) as 'total_logical_reads',
			max(REPLACE (REPLACE (SUBSTRING (st.[text], qs.statement_start_offset/2 + 1, 
			CASE WHEN qs.statement_end_offset = -1 THEN LEN (CONVERT(nvarchar(max), st.[text])) 
				ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
			END), CHAR(13), ' '), CHAR(10), ' '))  AS sample_statement_text
		FROM sys.dm_exec_query_stats AS qs
		CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
		group by query_hash
		ORDER BY sum(total_logical_reads) DESC
		) t
		OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)
		print ''

		--import in SQLNexus
		print '-- top 10 elapsed time by query_hash --'
		select getdate() as runtime, * -- into tbl_QueryHashByElapsedTime
		from
		(
		SELECT TOP 10 query_hash, 
			sum(execution_count) as 'execution_count', 
			COUNT (distinct query_plan_hash) as 'distinct query_plan_hash count',
			sum(total_worker_time) as 'total_worker_time',
			SUM(total_elapsed_time) as 'total_elapsed_time',
			SUM (total_logical_reads) as 'total_logical_reads',
			max(REPLACE (REPLACE (SUBSTRING (st.[text], qs.statement_start_offset/2 + 1, 
			CASE WHEN qs.statement_end_offset = -1 THEN LEN (CONVERT(nvarchar(max), st.[text])) 
				ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
			END), CHAR(13), ' '), CHAR(10), ' '))  AS sample_statement_text
		FROM sys.dm_exec_query_stats AS qs
		CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
		GROUP BY query_hash
		ORDER BY sum(total_elapsed_time) DESC
		) t
		OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)
		print ''

		--import in SQLNexus
		print '-- top 10 CPU by query_plan_hash and query_hash --'
		SELECT TOP 10 getdate() as runtime, query_plan_hash, query_hash, 
		COUNT (distinct query_plan_hash) as 'distinct query_plan_hash count',
		sum(execution_count) as 'execution_count', 
			sum(total_worker_time) as 'total_worker_time',
			SUM(total_elapsed_time) as 'total_elapsed_time',
			SUM (total_logical_reads) as 'total_logical_reads',
			max(REPLACE (REPLACE (SUBSTRING (st.[text], qs.statement_start_offset/2 + 1, 
			CASE WHEN qs.statement_end_offset = -1 THEN LEN (CONVERT(nvarchar(max), st.[text])) 
				ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
			END), CHAR(13), ' '), CHAR(10), ' '))  AS sample_statement_text
		FROM sys.dm_exec_query_stats AS qs
		CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
		GROUP BY query_plan_hash, query_hash
		ORDER BY sum(total_worker_time) DESC
		OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)
		print ''


		--import in SQLNexus
		print '-- top 10 logical reads by query_plan_hash and query_hash --'
		SELECT TOP 10 getdate() as runtime, query_plan_hash, query_hash, sum(execution_count) as 'execution_count',  
			sum(total_worker_time) as 'total_worker_time',
			SUM(total_elapsed_time) as 'total_elapsed_time',
			SUM (total_logical_reads) as 'total_logical_reads',
			max(REPLACE (REPLACE (SUBSTRING (st.[text], qs.statement_start_offset/2 + 1, 
			CASE WHEN qs.statement_end_offset = -1 THEN LEN (CONVERT(nvarchar(max), st.[text])) 
				ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
			END), CHAR(13), ' '), CHAR(10), ' '))  AS sample_statement_text
		FROM sys.dm_exec_query_stats AS qs
		CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
		group by query_plan_hash, query_hash
		ORDER BY sum(total_logical_reads) DESC
		OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)
		print ''

		--import in SQLNexus
		print '-- top 10 elapsed time  by query_plan_hash and query_hash --'
		SELECT TOP 10 getdate() as runtime, query_plan_hash, query_hash, sum(execution_count) as 'execution_count', 
			sum(total_worker_time) as 'total_worker_time',
			SUM(total_elapsed_time) as 'total_elapsed_time',
			SUM (total_logical_reads) as 'total_logical_reads',
			max(REPLACE (REPLACE (SUBSTRING (st.[text], qs.statement_start_offset/2 + 1, 
			CASE WHEN qs.statement_end_offset = -1 THEN LEN (CONVERT(nvarchar(max), st.[text])) 
				ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
			END), CHAR(13), ' '), CHAR(10), ' '))  AS sample_statement_text
		FROM sys.dm_exec_query_stats AS qs
		CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
		group by query_plan_hash, query_hash
		ORDER BY sum(total_elapsed_time) DESC
		OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)
	print ''
	END TRY
	BEGIN CATCH
	  PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	  PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	END CATCH
END
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot11','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot11
GO

CREATE PROCEDURE #sp_perf_stats_snapshot11
AS
BEGIN
	exec #sp_perf_stats_snapshot10

END 
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot12','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot12
GO

CREATE PROCEDURE #sp_perf_stats_snapshot12
as
BEGIN
	exec #sp_perf_stats_snapshot11
END
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot13','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot13
GO

CREATE PROCEDURE #sp_perf_stats_snapshot13
AS
BEGIN
  EXEC #sp_perf_stats_snapshot12
END
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot14','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot14
GO

CREATE PROCEDURE #sp_perf_stats_snapshot14
AS
BEGIN
	exec #sp_perf_stats_snapshot13
END
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot15','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot15
GO

CREATE PROCEDURE #sp_perf_stats_snapshot15
AS
BEGIN
	BEGIN TRY
		exec #sp_perf_stats_snapshot14
		
		DECLARE @sql_major_version INT
		SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT))	
		-- Check the MS Version
		IF (@sql_major_version >=15)
		BEGIN
			-- Add identifier
			print '-- sys.index_resumable_operations --'
			SELECT object_id, OBJECT_NAME(object_id) [object_name], index_id, name [index_name],
			sql_text,last_max_dop_used,	partition_number, state, state_desc, start_time, 
			last_pause_time, total_execution_time, percent_complete, page_count 
			FROM sys.index_resumable_operations WITH (NOLOCK)
			
			PRINT ''
			RAISERROR ('', 0, 1) WITH NOWAIT
		END
	END TRY
	BEGIN CATCH
	  PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	  PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	END CATCH
END
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot16','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot16
GO

CREATE PROCEDURE #sp_perf_stats_snapshot16
AS
BEGIN
	exec #sp_perf_stats_snapshot15
END
GO

IF OBJECT_ID ('#sp_perf_stats_snapshot17','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_stats_snapshot17
GO

CREATE PROCEDURE #sp_perf_stats_snapshot17
AS
BEGIN
	exec #sp_perf_stats_snapshot16
END
GO

/*****************************************************************
*                   main loop   perf statssnapshot               *
******************************************************************/

IF OBJECT_ID ('#sp_Run_PerfStats_Snapshot','P') IS NOT NULL
   DROP PROCEDURE #sp_Run_PerfStats_Snapshot
GO
CREATE PROCEDURE #sp_Run_PerfStats_Snapshot  @IsLite bit=0 
AS 
	BEGIN TRY

		DECLARE @servermajorversion nvarchar(2)
		SET @servermajorversion = REPLACE (LEFT (CONVERT (varchar, SERVERPROPERTY ('ProductVersion')), 2), '.', '')
		declare @#sp_perf_stats_snapshot_ver sysname
		set @#sp_perf_stats_snapshot_ver = '#sp_perf_stats_snapshot' + @servermajorversion
		print 'executing procedure ' + @#sp_perf_stats_snapshot_ver
		exec @#sp_perf_stats_snapshot_ver
	END TRY
	BEGIN CATCH
	  PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	  PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	END CATCH
GO

exec #sp_Run_PerfStats_Snapshot
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
# MIIr4wYJKoZIhvcNAQcCoIIr1DCCK9ACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC65Mg0L5QHnrA/
# nt/YNkcJPdHXRXS8ef91WrhWLZNiTaCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
# D0nu2y38AAIAAAINMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzA5MzBaFw0yNjA0MjYyMzE5MzBaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCpj9ry6z6v08TIeKoxS2+5c928SwYKDXCyPWZHpm3xIHTqBBmlTM1GO7X4
# ap5jj/wroH7TzukJtfLR6Z4rBkjdlocHYJ2qU7ggik1FDeVL1uMnl5fPAB0ETjqt
# rk3Lt2xT27XUoNlKfnFcnmVpIaZ6fnSAi2liEhbHqce5qEJbGwv6FiliSJzkmeTK
# 6YoQQ4jq0kK9ToBGMmRiLKZXTO1SCAa7B4+96EMK3yKIXnBMdnKhWewBsU+t1LHW
# vB8jt8poBYSg5+91Faf9oFDvl5+BFWVbJ9+mYWbOzJ9/ZX1J4yvUoZChaykKGaTl
# k51DUoZymsBuatWbJsGzo0d43gMLAgMBAAGjggWKMIIFhjApBgkrBgEEAYI3FQoE
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
# aG9yaXR5MB0GA1UdDgQWBBS6kl+vZengaA7Cc8nJtd6sYRNA3jAOBgNVHQ8BAf8E
# BAMCB4AwRQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEWMBQGA1UEBRMNMjM2MTY3KzUwNjA0MjCCAeYGA1UdHwSCAd0wggHZMIIB
# 1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpaW5mcmEvQ1JM
# L0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwxLmFtZS5nYmwv
# Y3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwyLmFtZS5n
# YmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwzLmFt
# ZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmw0
# LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGgb1sZGFwOi8v
# L0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQS0lDU0NBMDEsQ049Q0RQ
# LENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZp
# Z3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0
# P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwHwYDVR0jBBgw
# FoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgwFgYKKwYBBAGCN1sBAQYI
# KwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAJKGB9zyDWN/9twAY6qCLnfDCKc/
# PuXoCYI5Snobtv15QHAJwwBJ7mr907EmcwECzMnK2M2auU/OUHjdXYUOG5TV5L7W
# xvf0xBqluWldZjvnv2L4mANIOk18KgcSmlhdVHT8AdehHXSs7NMG2di0cPzY+4Ol
# 2EJ3nw2JSZimBQdRcoZxDjoCGFmHV8lOHpO2wfhacq0T5NK15yQqXEdT+iRivdhd
# i/n26SOuPDa6Y/cCKca3CQloCQ1K6NUzt+P6E8GW+FtvcLza5dAWjJLVvfemwVyl
# JFdnqejZPbYBRdNefyLZjFsRTBaxORl6XG3kiz2t6xeFLLRTJgPPATx1S7Awggjo
# MIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0GCSqGSIb3DQEBCwUAMDwx
# EzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxEDAOBgNV
# BAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYwNTIxMTg1NDE0WjBBMRMw
# EQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQD
# EwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDJ
# mlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL9rNHnHDGfJgeuRIYO1LY
# /1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc411WxA+Pv2rteAcz0eHM
# H36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaCIIWBXyEchv+sM9eKDsUO
# LdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8pXirIYOgM770CYOiZrcKH
# K7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p/6fksgEILptOKhx9c+ia
# piNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkrBgEEAYI3FQEEBQIDAgAC
# MCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMALI38/RzAdBgNVHQ4EFgQU
# llGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfwwgfkGBysGAQUCAwUGCCsG
# AQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYBBAGCNxUGBgorBgEEAYI3
# CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgCAgYKKwYBBAGCN0ABAQYL
# KwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcVBQYKKwYBBAGCNxQCAgYK
# KwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEGCisGAQQBgjdbAgEGCisG
# AQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEGCisGAQQBgjdbBAIwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwNp4x1AdEJCygwggFoBgNV
# HR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDovL2NybDIuYW1lLmdibC9j
# cmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL2FtZXJvb3Qu
# Y3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVyb290LmNybIaBqmxkYXA6
# Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPUFNRSxE
# Qz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNz
# PWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUHAQEEggGdMIIBmTBHBggr
# BgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NlcnRz
# L0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwyLmFt
# ZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6
# Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUH
# MAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQw
# gaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290LENOPUFJQSxDTj1QdWJs
# aWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9u
# LERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29iamVjdENsYXNzPWNl
# cnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQELBQADggIBAFAQI7dPD+jf
# XtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTHb8BDfRN+AD0YEmeDB5HK
# QoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a/752hMIn+L4ZuyxVeSBp
# fwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9zAh9yRKKls2bziPEnxeO
# ZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAmn3WCPWNFC1YTIIHw/mD2
# cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtzyb7fbNS1dE740re0COE6
# 7YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjFK1yMw4Ni5fMabcgmzRvS
# jAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bzMzsikuDW9xH10graZzSm
# PjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIzJ6Q9G3NPCB+7KwX0OQmK
# yv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/ywO6SYSreVW+5Y0mzJutn
# BC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEISRtShDZbuYymynY1un+Ry
# fiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZyzCCGccCAQEwWDBBMRMwEQYKCZIm
# iZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQDEwxBTUUg
# Q1MgQ0EgMDECEzYAAAIN4oQPSe7bLfwAAgAAAg0wDQYJYIZIAWUDBAIBBQCgga4w
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJ3GRHsRTsGVsttJmeEO5X/TIs5rW4HM
# PNtk7QsGF0loMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# fpTX4X6KzLw5wP4HPqsAQkeLlXqlFhg1A4wCuYDzhU6d4u52wNp4buFtYHRTW1AM
# eQT7SyTlczyR/V6KLukvjuK2m+PtmiXHTpmX2TyMivYT7fukDAXuohKmrze3oyYH
# UBH//8FuVyYzDXAsr26usM3TcdbHBjuGcsv+axvHoTappBr/2Px62Tb8BKjfiwKZ
# vNDKp4OKspvuDbWh/h+P5JCzQhNfA8IXTDoeW6WGtZx0DWwOGPlVdzxqFTd73RKD
# 9fhNn49MzxbPEMS6UB3hyLt+tBY5saZt3aCNQC6/AyTpaizFBXWJOKD7xjeSKEYr
# tbGmV15+Ay3dG0tD7e9RV6GCF5MwghePBgorBgEEAYI3AwMBMYIXfzCCF3sGCSqG
# SIb3DQEHAqCCF2wwghdoAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFRBgsqhkiG9w0B
# CRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCCkI4aJFEiClDnSyb0CYzmqdk5+6ICdMuARKjrYS9I1GAIGaWj23IQTGBIyMDI2
# MDIwNDE2MzUyNy41OFowBIACAfSggdGkgc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9w
# ZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpEQzAwLTA1RTAtRDk0
# NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEeowggcg
# MIIFCKADAgECAhMzAAACA7seXAA4bHTKAAEAAAIDMA0GCSqGSIb3DQEBCwUAMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDEzMDE5NDI0NloXDTI2
# MDQyMjE5NDI0NlowgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjpEQzAwLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAKGXQwfnACc7HxSHxG2J0XQnTJoUMclgdOk+9FHXpfUrEYNh9Pw+
# twaMIsKJo67crUOZQhThFzmiWd2Nqmk246DPBSiPjdVtsnHk8VNj9rVnzS2mpU/Q
# 6gomVSR8M9IEsWBdaPpWBrJEIg20uxRqzLTDmDKwPsgs9m6JCNpx7krEBKMp/YxV
# fWp8TNgFtMY0SKNJAIrDDJzR5q+vgWjdf/6wK64C2RNaKyxTriTysrrSOwZECmIR
# J1+4evTJYCZzuNM4814YDHooIvaS2mcZ6AsN3UiUToG7oFLAAgUevvM7AiUWrJC4
# J7RJAAsJsmGxP3L2LLrVEkBexTS7RMLlhiZNJsQjuDXR1jHxSP6+H0icugpgLkOk
# pvfXVthV3RvK1vOV9NGyVFMmCi2d8IAgYwuoSqT3/ZVEa72SUmLWP2dV+rJgdisw
# 84FdytBhbSOYo2M4vjsJoQCs3OEMGJrXBd0kA0qoy8nylB7abz9yJvIMz7UFVmq4
# 0Ci/03i0kXgAK2NfSONc0NQy1JmhUVAf4WRZ189bHW4EiRz3tH7FEu4+NTKkdnkD
# cAAtKR7hNpEG9u9MFjJbYd6c5PudgspM7iPDlCrpzDdn3NMpI9DoPmXKJil6zlFH
# Yx0y8lLh8Jw8kV5pU6+5YVJD8Qa1UFKGGYsH7l7DMXN2l/VS4ma45BNPAgMBAAGj
# ggFJMIIBRTAdBgNVHQ4EFgQUsilZQH4R55Db2xZ7RV3PFZAYkn0wHwYDVR0jBBgw
# FoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1T
# dGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEF
# BQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNy
# b3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/
# BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwDQYJ
# KoZIhvcNAQELBQADggIBAJAQxt6wPpMLTxHShgJ1ILjnYBCsZ/87z0ZDngK2ASxv
# HPAYNVRyaNcVydolJM150EpVeQGBrBGic/UuDEfhvPNWPZ5Y2bMYjA7UWWGV0A84
# cDMsEQdGhJnil10W1pDGhptT83W9bIgKI3rQi3zmCcXkkPgwxfJ3qlLx4AMiLpO2
# N+Ao+i6ZZrQEVD9oTONSt883Wvtysr6qSYvO3D8Q1LvN6Z/LHiQZGDBjVYF8Wqb+
# cWUkM9AGJyp5Td06n2GPtaoPRFz7/hVnrBCN6wjIKS/m6FQ3LYuE0OLaV5i0CIgW
# maN82TgaeAu8LZOP0is4y/bRKvKbkn8WHvJYCI94azfIDdBqmNlO1+vs1/OkEglD
# jFP+JzhYZaqEaVGVUEjm7o6PDdnFJkIuDe9ELgpjKmSHwV0hagqKuOJ0QaVew06j
# 5Q/9gbkqF5uK51MHEZ5x8kK65Sykh1GFK0cBCyO/90CpYEuWGiurY4Jo/7AWETdY
# +CefHml+W+W6Ohw+Cw3bj7510euXc7UUVptbybRSQMdIoKHxBPBORg7C732ITEFV
# aVthlHPao4gGMv+jMSG0IHRq4qF9Mst640YFRoHP6hln5f1QAQKgyGQRONvph81o
# jVPu9UBqK6EGhX8kI5BP5FhmuDKTI+nOmbAw0UEPW91b/b2r2eRNagSFwQ47Qv03
# MIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsF
# ADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UE
# AxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcN
# MjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzn
# tHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3
# lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFE
# yHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+
# jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4x
# yDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBc
# TyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9
# pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ
# 8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pn
# ol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYG
# NRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cI
# FRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEE
# AYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E
# 7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwr
# BgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUF
# BwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYG
# A1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3Js
# L3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcB
# AQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kv
# Y2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUA
# A4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2
# P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J
# 6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfak
# Vqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/AL
# aoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtP
# u4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5H
# LcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEua
# bvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvB
# QUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb
# /wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETR
# kPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCA00wggI1AgEB
# MIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQL
# Ex5uU2hpZWxkIFRTUyBFU046REMwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAM2vFFf+LPqy
# zWUEJcbw/UsXEPR7oIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwDQYJKoZIhvcNAQELBQACBQDtLc/NMCIYDzIwMjYwMjA0MTQwMTQ5WhgPMjAy
# NjAyMDUxNDAxNDlaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAO0tz80CAQAwBwIB
# AAICDsMwBwIBAAICE0AwCgIFAO0vIU0CAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYK
# KwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQsF
# AAOCAQEAX02q+2E78E/FFeXTH8DhhV+VO5tmLiTGUjC3oKuTJGmaQ0EyjELMZRuq
# tx1Yt63hWaGK8hnrD8YpAmA0WMHs3c/3/uh5qVwoFnO2i89HFeAPZ4bPd6OhGHur
# Hfq38ezJYkN2aqtL3YXKiKDvrxxbV/M7m6aE/Po5r61Pr1+jakE+DOzUcsM9Pitf
# hweXS7K4cqL7PFzABj+mWCTLdC8sYcCrNry2sOVMz1QVV99Nksrx3A2uChP0U9sl
# IiPQyY2v+XOG87In7SLtQE8if3dk5/YrHIekVmU3ccQNstJQZE19EKA0hJYusiWt
# rmXNZ41BnqxRazBjy+Bdzk9CByLDczGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACA7seXAA4bHTKAAEAAAIDMA0GCWCGSAFl
# AwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIAS8kMA7M4ZOrKClFxBRXMDgoD7C9Xj09qCG3ZpI5Kk6MIH6BgsqhkiG
# 9w0BCRACLzGB6jCB5zCB5DCBvQQgSwPdG3GW9pPEU5lmelDDQOSw+ZV26jlLIr2H
# 3D76Ey0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# AgO7HlwAOGx0ygABAAACAzAiBCD9Dk6bVM0p/sea8APxpSUp6nMNJpU8hJDxhHdh
# iEI3UDANBgkqhkiG9w0BAQsFAASCAgAR+NPami84gdJ3EgtVw+Xg+Ng5H71gHB4a
# eheKoVEGPbfTFYYjFoBnmb/55CI8Fj2E0x/e296s6Y9HZVQpQDDxNLRCumoImFa7
# EWHvvIKDdzTZtciz0L7jFjjciagWxzy0wX+v+fQufiLR5Yav5m7gVmEbMl697DBT
# UaPw1qHsjnuk59Q/pF/LxjzgIrGN6gHSrBmPzK8G4pNkNixt/lwYpfy2xsytkGSw
# nNpL8aip1G5Nt3/mlfDkcKGUSu7/MmzSRc39SAK5Ij8M9ZcRLxD9SPV6w7Y+s1Tz
# hEjBfARw2GwTAdoOMogbXLv6XoKVMEOwqYnkE7cZ70WrrKqcAVdGK2e4USoi4HWD
# RQZq4LMnakJpdqPYI8xokEcgv8w3Qq9akuAVnc8ILN6kOg1gtXqDRdTOWjFFezen
# 3xubgnbu5VW2QXvp6SehsixIVy4KFV7J2eChPZ6pzC26N+3VXYB/FwSvZmXAMDWi
# wRGPOc3f3M8iqiBQ6VvCH3PKBEOwI0CQz9HmGMWKuJDr6ii31BpOc3NcqCHD1OTt
# K0CdFwcoBhhEK5KMIy3Rs+B2DDySTBIKQX8KgvwUz7snWNllpJxiXXdI64dQxzSx
# z1LW1IQHPVYR3VJYU0vZbN6tC6TyJrfH9MSkRUv0ARZKlDxHTCKdWnZ/KtOSKsyq
# NLRFGUcg6A==
# SIG # End signature block
