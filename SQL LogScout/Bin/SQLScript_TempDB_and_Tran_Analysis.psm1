
    function TempDB_and_Tran_Analysis_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "TempDB_and_Tran_Analysis"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
SET NOCOUNT ON
USE tempdb
GO

DECLARE @sql_major_version INT
SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT))

WHILE 1=1
BEGIN

  BEGIN TRY
    IF OBJECT_ID('tempdb..#dbtable') IS NOT NULL
    DROP TABLE #dbtable;
    
    IF OBJECT_ID('tempdb..#db_inmemory') IS NOT NULL
    DROP TABLE #db_inmemory;
  
	  IF OBJECT_ID('tempdb..#tmp_dm_db_xtp_transactions ') IS NOT NULL
    DROP TABLE #tmp_dm_db_xtp_transactions;  
    
    PRINT '-- Current time'
    SELECT getdate()
	  PRINT ''
  
    DECLARE @runtime VARCHAR(30)
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
      AND c.net_transport <> 'session'
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
	    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) as t 
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
	         ISNULL(s_tdt.database_transaction_begin_time,s_tat.transaction_begin_time) as transaction_begin_time,
           DATEDIFF(second, ISNULL(s_tdt.database_transaction_begin_time,s_tat.transaction_begin_time), getdate()) as elapsed_time_seconds, 
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
   	  INNER JOIN sys.dm_tran_session_transactions s_tst
   		  ON s_tst.transaction_id = s_tdt.transaction_id
   	  INNER JOIN sys.dm_tran_active_transactions s_tat
   		  ON (s_tdt.transaction_id = s_tat.transaction_id)
      INNER JOIN sys.dm_exec_sessions AS s_es    
   		  ON s_es.session_id = s_tst.session_id
      LEFT JOIN sys.dm_exec_requests s_er    
   		  ON s_er.session_id = s_tst.session_id
   	  LEFT JOIN sys.dm_exec_connections con 
   		  ON con.session_id = s_tst.session_id 
   	   AND con.net_transport <> 'session'
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
    FROM   sys.objects AS _Objects WITH (NOLOCK)
    INNER JOIN sys.dm_db_partition_stats AS _Partitions WITH (NOLOCK)
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
      
        IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN

          SET @sql = N'USE [' + @dbname + '];
      	             IF EXISTS(SELECT type_desc FROM sys.data_spaces WHERE type_desc = ''MEMORY_OPTIMIZED_DATA_FILEGROUP'')
      	             BEGIN
      	  		         INSERT INTO #db_inmemory VALUES (' + CONVERT(NVARCHAR(50),@database_id) + ',''' + @dbname +''');
      	  		       END'
          --print @sql
          EXEC (@sql)
        END
        
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
  END TRY
  BEGIN CATCH
    PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
    WAITFOR DELAY '00:00:10'
  END CATCH
END
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
# MIIsDAYJKoZIhvcNAQcCoIIr/TCCK/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDv6yurdVMxujzW
# nZT0WmkGmP1T1xvDpQbCQqlfSTMvCqCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# RtShDZbuYymynY1un+RyfiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZ5TCCGeEC
# AQEwWDBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1F
# MRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDECEzYAAAIOeZeg6f1fn9MAAgAAAg4wDQYJ
# YIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFy4P+EArLMw
# w7hTDl26F13+9vscXPMto2xWBysuMaEQMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAmirScq7D76eB8jLreihkxviEA+uYtKSXvjxKw3obM6Q1
# ScvV5wGcoXv7K++uXdJlO5FKpQBkUmXzmA6qyIU4VHKvEy7FM4Cln27Ue28Fa2/x
# kCRC48revdPH6dfTVFH4nYRoj/4yHlqnodYNm8TfDncYfRs0mkjfMKfbUMXOnfxt
# 0qw6zQ644+PVJT80gTN0nMiGp5wYl3+6j7VVeuRlZGsmb0nIzNVkg6kCspfNs5qq
# jzrLQZAy4HjVXBghi2Ycn+f0Wmo1HNkfouWNXr5qtyLIdJcQlU3HGMuqHLeb2Um2
# +lLLUUhQ+JVpvFf4bsgfVncMKjajVzq7PNZVurrkl6GCF60wghepBgorBgEEAYI3
# AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCBXo9+g6MgQnTO5hBLelEckh7S+wcTej6TfzZAAAY7C
# lgIGaXNTHBuQGBMyMDI2MDIwNDE2MzUyOC41NzZaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAACEUUYOZtDz/xs
# AAEAAAIRMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgxM1oXDTI2MTExMzE4NDgxM1owgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjZCMDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAz7m7MxAd
# L5Vayrk7jsMo3GnhN85ktHCZEvEcj4BIccHKd/NKC7uPvpX5dhO63W6VM5iCxklG
# 8qQeVVrPaKvj8dYYJC7DNt4NN3XlVdC/voveJuPPhTJ/u7X+pYmV2qehTVPOOB1/
# hpmt51SzgxZczMdnFl+X2e1PgutSA5CAh9/Xz5NW0CxnYVz8g0Vpxg+Bq32amktR
# Xr8m3BSEgUs8jgWRPVzPHEczpbhloGGEfHaROmHhVKIqN+JhMweEjU2NXM2W6hm3
# 2j/QH/I/KWqNNfYchHaG0xJljVTYoUKPpcQDuhH9dQKEgvGxj2U5/3Fq1em4dO6I
# h04m6R+ttxr6Y8oRJH9ZhZ3sciFBIvZh7E2YFXOjP4MGybSylQTPDEFAtHHgpksk
# eEUhsPDR9VvWWhekhQx3qXaAKh+AkLmz/hpE3e0y+RIKO2AREjULJAKgf+R9QnNv
# qMeMkz9PGrjsijqWGzB2k2JNyaUYKlbmQweOabsCioiY2fJbimjVyFAGk5AeYddU
# FxvJGgRVCH7BeBPKAq7MMOmSCTOMZ0Sw6zyNx4Uhh5Y0uJ0ZOoTKnB3KfdN/ba/e
# KHFeEhi3WqAfzTxiy0rMvhsfsXZK7zoclqaRvVl8Q48J174+eyriypY9HhU+ohgi
# Yi4uQGDDVdTDeKDtoC/hD2Cn+ARzwE1rFfECAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBRifUUDwOnqIcvfb53+yV0EZn7OcDAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# pEKdnMeIIUiU6PatZ/qbrwiDzYUMKRczC4Bp/XY1S9NmHI+2c3dcpwH2SOmDfdvI
# Iqt7mRrgvBPYOvJ9CtZS5eeIrsObC0b0ggKTv2wrTgWG+qktqNFEhQeipdURNLN6
# 8uHAm5edwBytd1kwy5r6B93klxDsldOmVWtw/ngj7knN09muCmwr17JnsMFcoIN/
# H59s+1RYN7Vid4+7nj8FcvYy9rbZOMndBzsTiosF1M+aMIJX2k3EVFVsuDL7/R5p
# pI9Tg7eWQOWKMZHPdsA3ZqWzDuhJqTzoFSQShnZenC+xq/z9BhHPFFbUtfjAoG6E
# DPjSQJYXmogja8OEa19xwnh3wVufeP+ck+/0gxNi7g+kO6WaOm052F4siD8xi6Uv
# 75L7798lHvPThcxHHsgXqMY592d1wUof3tL/eDaQ0UhnYCU8yGkU2XJnctONnBKA
# vURAvf2qiIWDj4Lpcm0zA7VuofuJR1Tpuyc5p1ja52bNZBBVqAOwyDhAmqWsJXAj
# YXnssC/fJkee314Fh+GIyMgvAPRScgqRZqV16dTBYvoe+w1n/wWs/ySTUsxDw4T/
# AITcu5PAsLnCVpArDrFLRTFyut+eHUoG6UYZfj8/RsuQ42INse1pb/cPm7G2lcLJ
# tkIKT80xvB1LiaNvPTBVEcmNSvFUM0xrXZXcYcxVXiYwggdxMIIFWaADAgECAhMz
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
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCCAj4CAQEwggEBoYHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAKyp8q2VdgAq1VGkzd7PZ
# wV6zNc2ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0tosYwIhgPMjAyNjAyMDQxMDQ5NDJaGA8yMDI2MDIwNTEw
# NDk0MlowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7S2ixgIBADAHAgEAAgImszAH
# AgEAAgISITAKAgUA7S70RgIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZ
# CgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQA7
# IgFh9Y6/b+xP2aeSg2pQo/K3f7Ke8RIatNZf5yVsgc0mQScsY+dhP2jnYx2XR8h8
# 4G/1gRDm0ARudyYYnn0++qQxBJeILiACubTqLGKVKS+H+BBSinEkau6LXBJiBLw0
# tW8glOFysceSeMv8C14iH3L7KuyjI+Yc67+EAcm66gtrBl5VkhgteLp+1yQIVHNa
# LnZAn/fJHOBGt1K97Zl/AJulgrii6rIKBHBaujEcTp0+fiIlnaLVLgvQREwPyW32
# A8jpH7Q5S29dPFqs8xYFQ/chy0DWEsdZWzCb9ADQWe/St12Q7Kf26+vlJ4sHoljd
# 7Al++zetR43/NF8StISyMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTACEzMAAAIRRRg5m0PP/GwAAQAAAhEwDQYJYIZIAWUDBAIBBQCg
# ggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg
# fwgz+YabYYykpp5T6eXKBT17vfVKhq+qF7N4rIymZ9IwgfoGCyqGSIb3DQEJEAIv
# MYHqMIHnMIHkMIG9BCAsrTOpmu+HTq1aXFwvlhjF8p2nUCNNCEX/OWLHNDMmtzCB
# mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACEUUYOZtD
# z/xsAAEAAAIRMCIEIPtAmOQ4ljBTF5yKpkNotGmgdzTRPv/JiYhDf6hGv7h+MA0G
# CSqGSIb3DQEBCwUABIICAGpF9LV9n2sfZ8m4SK1HUM5PSKxn4MGpE6dcrSKnef4P
# 2fIFebIS4LpVIFNAcAlI6eu9FS+Esu7i2O7UmBQrBnjcAgl93PQJBf/yq+ckScUq
# f7S2yT5qU4KX8Cu97sL1YoXkGsWHPBnfdnAak1l68obMFRX8EBbFZ1kaJ8odctBw
# Gj6nQFBcYAW3RalUcPp1BBruqKo2xEd3CXzEs2pJatJ7TrX2JSUi+8SwkGicbe+o
# 2V5n2RjurRQ7XrcoLhlXyw6ajHPwkSAeGfOdS7JrwBNXFwqfEvr3SxqjweohBi7V
# 5br12lZH+9PIRWZhXjuFGStQT9vA9ngCsXTM1zgTAOVNGPE6t6Ovr7UDcZrojSn2
# ewotxytj2zBpD+u6sNO3eBBMYZeJp6CEyhyhuIxRkkFUXlIvtGiJ3j5h1sPRQdpf
# 0JBKi3HOsuEeoO7w1FeQ7DCFzdOpf3JxGmSniyu0A+JuzfTb4WGkFPxeF9u2YgdF
# KJE8qGXtJh/F/tw8NZdM5NjgxW+11HCMKlnQ8kjKxQoAkUUGholK2iI31ViIHWXb
# yZqjF4GmzucvqMoainjY6MlrsVn0wbpV6uEU7nSZ/mxW3BXWFqc1unXNOTFhSTQA
# 6FSY2Lbh219lzCOjF7YIOuvrPNVhw9UjyYFtQcJwXTtVu65f8kZXfkTYP9lndnwg
# SIG # End signature block
