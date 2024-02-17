
SET NOCOUNT ON
USE tempdb
GO

DECLARE @sql_major_version INT
SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT))

WHILE 1=1
BEGIN

  IF OBJECT_ID('tempdb..#dbtable') IS NOT NULL
  DROP TABLE #dbtable;
  
  IF OBJECT_ID('tempdb..#db_inmemory') IS NOT NULL
  DROP TABLE #db_inmemory;

	IF OBJECT_ID('tempdb..#tmp_dm_db_xtp_transactions ') IS NOT NULL
  DROP TABLE #tmp_dm_db_xtp_transactions;  
  
  PRINT '-- Current time'
  SELECT getdate()
	PRINT ''

  DECLARE @runtime datetime
  SET @runtime = CONVERT (varchar(30), GETDATE(), 121) 

  PRINT '-- sys.dm_db_file_space_usage --'
  SELECT @runtime AS runtime, 
         DB_NAME() AS dbname, 
         SUM (user_object_reserved_page_count)*8 AS usr_obj_kb,
         SUM (internal_object_reserved_page_count)*8 AS internal_obj_kb,
         SUM (version_store_reserved_page_count)*8  AS version_store_kb,
         SUM (unallocated_extent_page_count)*8 AS freespace_kb,
         SUM (mixed_extent_page_count)*8 AS mixedextent_kb
  FROM sys.dm_db_file_space_usage 
  OPTION (max_grant_percent = 3, MAXDOP 2)
  PRINT ''

  PRINT '-- tempdb_space_usage_by_file --'
  SELECT	@runtime AS runtime, 
          SUBSTRING(name, 0, 32) AS filename, 
	        physical_name,
	        CONVERT(decimal(10,3),size/128.0) AS currentsize_mb, 
          CONVERT(decimal(10,3),size/128.0 - FILEPROPERTY(name, 'SpaceUsed')/128.0) AS freespace_mb
  FROM tempdb.sys.database_files f
  PRINT ''


	PRINT '-- transaction_perfmon_counters --'
  
  SELECT @runtime AS runtime, 
	CONVERT(VARCHAR(16), DB_NAME ()) AS dbname,
	SUBSTRING(object_name,0,28) as object_name,
	SUBSTRING(counter_name,0,42) as counter_name,
	cntr_value AS counter_value
  FROM sys.dm_os_performance_counters
  WHERE Object_Name LIKE '%:Transactions%'
  RAISERROR ('', 0, 1) WITH NOWAIT
  PRINT ''

  PRINT '-- sys.dm_db_session_space_usage --'
  SELECT TOP 10 @runtime AS runtime,
	       su.session_id,
	       su.database_id,
	       su.internal_objects_alloc_page_count,
	       su.internal_objects_dealloc_page_count,
	       su.user_objects_alloc_page_count,
	       su.user_objects_dealloc_page_count,
	       su.user_objects_deferred_dealloc_page_count,
	       s.open_transaction_count,
	       s.last_request_end_time,
	       SUBSTRING(s.host_name, 0, 48) host_name,
	       SUBSTRING(s.program_name,0,48) program_name,
	       LTRIM(RTRIM(REPLACE(REPLACE(SUBSTRING(t.text, 0,256), CHAR(10), ' '), CHAR(13), ' '))) AS most_recent_query  
  FROM	sys.dm_db_session_space_usage su
	LEFT OUTER JOIN sys.dm_exec_sessions s
	  ON su.session_id = s.session_id
    LEFT OUTER JOIN sys.dm_exec_connections c
	  on su.session_id = c.session_id
	OUTER APPLY sys.dm_exec_sql_text (c.most_recent_sql_handle) as t
    WHERE (internal_objects_alloc_page_count +	internal_objects_dealloc_page_count + user_objects_alloc_page_count + user_objects_dealloc_page_count + su.user_objects_deferred_dealloc_page_count) !=0
    ORDER BY (user_objects_alloc_page_count + internal_objects_alloc_page_count) DESC
    OPTION (max_grant_percent = 3, MAXDOP 2)
    PRINT ''


  PRINT '-- sys.dm_db_task_space_usage --'
	SELECT	TOP 10 @runtime AS runtime,
	     	 	tsu.session_id,
	     		tsu.database_id,
	     		tsu.internal_objects_alloc_page_count,
	     		tsu.internal_objects_dealloc_page_count,
	     		tsu.user_objects_alloc_page_count,
	     		tsu.user_objects_dealloc_page_count,
	     		tsu.exec_context_id,
	     		r.status,
	     		r.wait_type,
	     		r.wait_time,
	     		r.cpu_time,
	        LTRIM(RTRIM(REPLACE(REPLACE(SUBSTRING(t.text, (r.statement_start_offset/2)+1,   
	       	((CASE r.statement_end_offset  
	     	     WHEN -1 THEN DATALENGTH(t.text)  
	     		   ELSE r.statement_end_offset  
	     		 END - r.statement_start_offset)/2) + 1), CHAR(10), ' '), CHAR(13), ' '))) AS statement_text,
	     		LTRIM(RTRIM(REPLACE(REPLACE(SUBSTRING(t.text, 0,256), CHAR(10), ' '), CHAR(13), ' '))) AS batch_text  
  FROM	sys.dm_db_task_space_usage tsu
    LEFT JOIN sys.dm_exec_requests r
	    ON tsu.session_id = r.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
  WHERE (internal_objects_alloc_page_count +	internal_objects_dealloc_page_count + user_objects_alloc_page_count + user_objects_dealloc_page_count) !=0
  ORDER BY (user_objects_alloc_page_count + internal_objects_alloc_page_count) DESC
  OPTION (max_grant_percent = 3, MAXDOP 2)
  PRINT ''

  PRINT '-- version store transactions --'
  SELECT	@runtime AS runtime,
	        ast.transaction_id,
	        ast.transaction_sequence_num,
	        ast.commit_sequence_num,
	        ast.elapsed_time_seconds,
	        ast.average_version_chain_traversed,
	        ast.max_version_chain_traversed,
	        ast.first_snapshot_sequence_num,
	        ast.is_snapshot,
	        ast.session_id,
	        r.blocking_session_id,
	        r.status,
	        r.wait_type,
	        r.wait_time,
	        r.cpu_time,
	        r.total_elapsed_time,
	        r.granted_query_memory,
	        r.open_transaction_count,
	        r.transaction_isolation_level,
	        LTRIM(RTRIM(REPLACE(REPLACE(SUBSTRING(t.text, (r.statement_start_offset/2)+1,   
           ((CASE r.statement_end_offset  
               WHEN -1 THEN DATALENGTH(t.text)  
               ELSE r.statement_end_offset  
            END - r.statement_start_offset)/2) + 1), CHAR(10), ' '), CHAR(13), ' '))) AS statement_text  
  FROM	sys.dm_tran_active_snapshot_database_transactions ast 
    LEFT JOIN sys.dm_exec_requests r
	    ON ast.session_id = r.session_id
	  CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) as t 
  RAISERROR ('', 0, 1) WITH NOWAIT
  PRINT ''

  PRINT '-- open transactions --'
  SELECT @runtime AS runtime,
         s_tdt.transaction_id,
	       s_tdt.database_transaction_state,
	       s_tdt.database_transaction_type,
	       s_tdt.database_transaction_log_record_count,
	       s_tdt.database_transaction_begin_lsn,
	       s_tdt.database_transaction_last_lsn,
	       s_tdt.database_transaction_begin_time,
         s_tdt.database_transaction_log_bytes_used,
         s_tdt.database_transaction_log_bytes_reserved,
	       s_tdt.database_transaction_log_bytes_reserved_system,
	       s_tdt.database_transaction_log_bytes_used_system,
         s_tst.session_id,
	       s_tst.is_local,
	       s_es.login_time,
	       s_es.last_request_end_time,
	       CONVERT(VARCHAR(36), DB_NAME (s_tdt.database_id)) AS dbname,
	       con.most_recent_session_id,
	       s_es.open_transaction_count,
	       s_es.status,
	       SUBSTRING(s_es.host_name, 0, 48) host_name,
	       SUBSTRING(s_es.program_name,0,48) program_name,
	       s_es.is_user_process,
	       s_es.host_process_id,
	       SUBSTRING(s_es.login_name, 0,48) login_name,
	       con.client_net_address,
	       con.net_transport
  FROM sys.dm_tran_database_transactions s_tdt
    JOIN sys.dm_tran_session_transactions s_tst
      ON s_tst.transaction_id = s_tdt.transaction_id
    JOIN sys.dm_exec_sessions AS s_es    
	    ON s_es.session_id = s_tst.session_id
    LEFT OUTER JOIN sys.dm_exec_requests s_er    
	    ON s_er.session_id = s_tst.session_id
	  LEFT OUTER JOIN sys.dm_exec_connections con 
	    ON con.session_id = s_tst.session_id 
      OUTER APPLY sys.dm_exec_sql_text(con.most_recent_sql_handle) T
  ORDER BY database_transaction_begin_time ASC
  OPTION (max_grant_percent = 3, MAXDOP 2)

  RAISERROR ('', 0, 1) WITH NOWAIT
  PRINT ''
  
  PRINT '-- tempdb usage by objects --'
  SELECT TOP 10
         @runtime AS runtime,
         CONVERT(VARCHAR(16), DB_NAME ()) AS dbname,
         DB_ID() AS database_id,
         _Objects.schema_id AS schema_id,
         Schema_Name(_Objects.schema_id) AS schema_name,
         _Objects.object_id AS object_id,
         RTrim(_Objects.name) AS table_name,
         (~(Cast(_Partitions.index_id AS Bit))) AS is_heap,       
         SUM(_Partitions.used_page_count) * 8192/1024 used_pages_kb,
         SUM(_Partitions.reserved_page_count) * 8192/1024 reserved_pages_kb
  FROM   sys.objects AS _Objects
  INNER JOIN sys.dm_db_partition_stats AS _Partitions
    ON (_Objects.object_id = _Partitions.object_id)
  WHERE (_Partitions.index_id IN (0, 1))
  GROUP BY _Objects.schema_id,
                _Objects.object_id,
                _Objects.name,
                _Partitions.index_id
  ORDER BY used_pages_kb DESC
  OPTION (max_grant_percent = 3, MAXDOP 2)
  PRINT ''


  PRINT '-- waits-in-tempdb --'
  SELECT @runtime AS runtime, 
	  session_id,    
	  start_time,                    
	  status,                    
	  command,                        
	  CONVERT(VARCHAR(36), DB_NAME (database_id)) AS dbname,
	  blocking_session_id,          
	  wait_type,           
	  wait_time,   
	  last_wait_type,
	  wait_resource,                  
	  open_transaction_count,
	  cpu_time,        
	  total_elapsed_time,
	  logical_reads                  
  FROM sys.dm_exec_requests
  WHERE wait_resource like '% 2:%'
  OPTION (max_grant_percent = 3, MAXDOP 2)
	PRINT ''

	IF @sql_major_version >= 15 
	BEGIN
		PRINT '-- dm_tran_aborted_transactions --'
		SELECT @runtime AS runtime, 
		  transaction_id, 
		  database_id, 
		  begin_xact_lsn, 
		  end_xact_lsn, 
		  begin_time, 
		  nest_aborted
		FROM sys.dm_tran_aborted_transactions
	END

  RAISERROR ('', 0, 1) WITH NOWAIT
  PRINT ''
    
	PRINT '-- sys.dm_tran_active_transactions --'
	SELECT [transaction_id],
	       [name],
	       [transaction_begin_time],
	       [transaction_type],
	       [transaction_uow],
	       [transaction_state],
	       [transaction_status],
	       [transaction_status2],
	       [dtc_state],
	       [dtc_status],
	       [dtc_isolation_level],
	       [filestream_transaction_id]
  FROM sys.dm_tran_active_transactions
	RAISERROR ('', 0, 1) WITH NOWAIT
  PRINT ''

	--in-memory related

	IF (@sql_major_version > 11) 
  BEGIN
	
	  DECLARE @database_id INT
    DECLARE @dbname SYSNAME
    DECLARE @count INT
    DECLARE @maxcount INT
	  DECLARE @sql NVARCHAR(MAX)

	  CREATE TABLE #dbtable (
      id INT IDENTITY (1,1) PRIMARY KEY,
			database_id INT,
			dbname SYSNAME
		)

	  --database level in-memory dmvs

    SELECT IDENTITY(INT,1,1) AS id, 
           @database_id as database_id , 
           @dbname as dbname 
    INTO #db_inmemory
    FROM sys.databases
    WHERE 1=0
      
    INSERT INTO #dbtable
    SELECT database_id, name FROM sys.databases WHERE state_desc='ONLINE' 
    
    SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM #dbtable)
    
    WHILE (@count<=@maxcount)
    BEGIN
      SELECT @database_id = database_id,
      	     @dbname = dbname 
      FROM #dbtable
      WHERE id = @count
    
      SET @sql = N'USE [' + @dbname + '];
    	           IF EXISTS(SELECT type_desc FROM sys.data_spaces WHERE type_desc = ''MEMORY_OPTIMIZED_DATA_FILEGROUP'')
    	           BEGIN
    			         INSERT INTO #db_inmemory VALUES (' + CONVERT(NVARCHAR(50),@database_id) + ',''' + @dbname +''');
    			       END'
    --print @sql
      EXEC (@sql)
      SET @count = @count + 1
    
    END
    
    PRINT '-- sys.dm_db_xtp_transactions --'
  
	  CREATE TABLE  #tmp_dm_db_xtp_transactions (
	    [dbname] SYSNAME NULL,
      [node_id] SMALLINT NULL,
    	[xtp_transaction_id] BIGINT NULL,
    	[transaction_id] BIGINT NULL,
    	[session_id] SMALLINT NULL,
    	[begin_tsn] BIGINT NULL,
    	[end_tsn] BIGINT NULL,
    	[state] INT NULL,
    	[state_desc] NVARCHAR(16) NULL,
    	[result] INT NULL,
    	[result_desc] NVARCHAR(24) NULL,
    	[xtp_parent_transaction_node_id] SMALLINT NULL,
    	[xtp_parent_transaction_id] BIGINT NULL,
    	[last_error]INT NULL,
    	[is_speculative] BIT NULL,
    	[is_prepared] BIT NULL,
    	[is_delayed_durability] BIT NULL ,
    	[memory_address] VARBINARY(8) NULL,
    	[database_address] VARBINARY(8) NULL,
    	[thread_id] INT NULL,
    	[read_set_row_count] INT NULL,
    	[write_set_row_count] INT NULL,
    	[scan_set_count] INT NULL,
    	[savepoint_garbage_count] INT NULL,
    	[log_bytes_required]BIGINT NULL,
    	[count_of_allocations] INT NULL,
    	[allocated_bytes] INT NULL,
    	[reserved_bytes] INT NULL,
    	[commit_dependency_count] INT NULL,
    	[commit_dependency_total_attempt_count] INT NULL,
    	[scan_area] INT NULL,
    	[scan_area_desc] NVARCHAR(16) NULL,
    	[scan_location] INT NULL,
    	[dependent_1_address] VARBINARY(8) NULL,
    	[dependent_2_address] VARBINARY(8) NULL,
    	[dependent_3_address] VARBINARY(8) NULL,
    	[dependent_4_address] VARBINARY(8) NULL,
    	[dependent_5_address] VARBINARY(8) NULL,
    	[dependent_6_address] VARBINARY(8) NULL,
    	[dependent_7_address] VARBINARY(8) NULL,
    	[dependent_8_address] VARBINARY(8) NULL
    )
  
	  SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM #db_inmemory)
  
	  WHILE (@count<=@maxcount)
    BEGIN
      
      SELECT @database_id = database_id,
    	       @dbname = dbname 
      FROM #db_inmemory
      WHERE id = @count
    
      IF (@sql_major_version >=13 )
      BEGIN
        SET @sql = N'USE [' + @dbname + '];
         		         INSERT INTO #tmp_dm_db_xtp_transactions
       	   			     SELECT '''+@dbname+''',
    			     			        [node_id],
                            [xtp_transaction_id],
                            [transaction_id],
                            [session_id],
                            [begin_tsn],
                            [end_tsn],
                            [state],
                            [state_desc],
                            [result],
                            [result_desc],
                            [xtp_parent_transaction_node_id],
                            [xtp_parent_transaction_id],
                            [last_error],
                            [is_speculative],
                            [is_prepared],
                            [is_delayed_durability],
                            [memory_address],
                            [database_address],
                            [thread_id],
                            [read_set_row_count],
                            [write_set_row_count],
                            [scan_set_count],
                            [savepoint_garbage_count],
                            [log_bytes_required],
                            [count_of_allocations],
                            [allocated_bytes],
                            [reserved_bytes],
                            [commit_dependency_count],
                            [commit_dependency_total_attempt_count],
                            [scan_area],
                            [scan_area_desc],
                            [scan_location],
                            [dependent_1_address],
                            [dependent_2_address],
                            [dependent_3_address],
                            [dependent_4_address],
                            [dependent_5_address],
                            [dependent_6_address],
                            [dependent_7_address],
                            [dependent_8_address]
                     FROM sys.dm_db_xtp_transactions;'
      END
      ELSE
      BEGIN
        SET @sql = N'USE [' + @dbname + '];
       	 		         INSERT INTO #tmp_dm_db_xtp_transactions
       				       SELECT '''+@dbname+''',
    						            NULL, --[node_id],
                            [xtp_transaction_id],
                            [transaction_id],
                            [session_id],
                            [begin_tsn],
                            [end_tsn],
                            [state],
                            [state_desc],
                            [result],
                            [result_desc],
                            NULL, --[xtp_parent_transaction_node_id],
                            NULL, --[xtp_parent_transaction_id],
                            [last_error],
                            [is_speculative],
                            [is_prepared],
                            [is_delayed_durability],
                            [memory_address],
                            [database_address],
                            [thread_id],
                            [read_set_row_count],
                            [write_set_row_count],
                            [scan_set_count],
                            [savepoint_garbage_count],
                            [log_bytes_required],
                            [count_of_allocations],
                            [allocated_bytes],
                            [reserved_bytes],
                            [commit_dependency_count],
                            [commit_dependency_total_attempt_count],
                            [scan_area],
                            [scan_area_desc],
                            [scan_location],
                            [dependent_1_address],
                            [dependent_2_address],
                            [dependent_3_address],
                            [dependent_4_address],
                            [dependent_5_address],
                            [dependent_6_address],
                            [dependent_7_address],
                            [dependent_8_address]
                     FROM sys.dm_db_xtp_transactions;'
      END
     
      --print @sql
      EXEC (@sql)
      SET @count = @count + 1
    END
	  
	  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM #tmp_dm_db_xtp_transactions 
    RAISERROR ('', 0, 1) WITH NOWAIT
    
    PRINT '-- sys.dm_xtp_transaction_stats --'
    SET @sql = N'SELECT [total_count]
                        ,[read_only_count]
                        ,[total_aborts]
                        ,[system_aborts]
                        ,[validation_failures]
                        ,[dependencies_taken]
                        ,[dependencies_failed]
                        ,[savepoint_create]
                        ,[savepoint_rollbacks]
                        ,[savepoint_refreshes]
                        ,[log_bytes_written]
                        ,[log_IO_count]
                        ,[phantom_scans_started]
                        ,[phantom_scans_retries]
                        ,[phantom_rows_touched]
                        ,[phantom_rows_expiring]
                        ,[phantom_rows_expired]
                        ,[phantom_rows_expired_removed]
                        ,[scans_started]
                        ,[scans_retried]
                        ,[rows_returned]
                        ,[rows_touched]
                        ,[rows_expiring]
                        ,[rows_expired]
                        ,[rows_expired_removed]
                        ,[row_insert_attempts]
                        ,[row_update_attempts]
                        ,[row_delete_attempts]
                        ,[write_conflicts]
                        ,[unique_constraint_violations]'
	  IF (@sql_major_version >= 13) 
    BEGIN
      SET @sql = @sql + N',[drop_table_memory_attempts]
                          ,[drop_table_memory_failures]'
	  END
      
	  SET @sql = @sql + N'FROM sys.dm_xtp_transaction_stats;
	                      RAISERROR ('''', 0, 1) WITH NOWAIT;'
    EXEC (@sql)
  END
    
  WAITFOR DELAY '00:01:00'
END
GO 