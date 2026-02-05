
    function SQL_Server_Mem_Stats_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "SQL_Server_Mem_Stats"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
-------------------------------memory collectors ------------------------------------------------------------------------------------------------

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
perf mem stats snapshot

********************************************************************/
IF OBJECT_ID ('sp_mem_stats_grants_mem_script','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats_grants_mem_script
GO
--2017-01-10 changed query text be at statement level
CREATE PROCEDURE sp_mem_stats_grants_mem_script @runtime datetime , @lastruntime datetime =null
AS
BEGIN TRY

  print '-- query execution memory mem_script--'
	SELECT    CONVERT (varchar(30), @runtime, 121) as runtime, 
    r.session_id
        , r.blocking_session_id
        , r.cpu_time
        , r.total_elapsed_time
        , r.reads
        , r.writes
        , r.logical_reads
        , r.row_count
        , wait_time
        , wait_type
        , r.command
    , LTRIM(RTRIM(REPLACE(REPLACE (SUBSTRING (SUBSTRING(q.text,r.statement_start_offset/2 +1,  (CASE WHEN r.statement_end_offset = -1  THEN LEN(CONVERT(nvarchar(max), q.text)) * 2   ELSE r.statement_end_offset end -   r.statement_start_offset   )/2 ) , 1, 1000), char(10), ' '), char(13), ' '))) [text]
        , s.login_time
        , DB_NAME(r.database_id) AS name
        , s.login_name
        , s.host_name
        , s.nt_domain
        , s.nt_user_name
        , s.status
        , c.client_net_address
        , s.program_name
        , s.client_interface_name
        , s.last_request_start_time
        , s.last_request_end_time
        , c.connect_time
        , c.last_read
        , c.last_write
        , mg.dop --Degree of parallelism 
        , mg.request_time  --Date and time when this query requested the memory grant.
        , mg.grant_time --NULL means memory has not been granted
        , mg.requested_memory_kb / 1024 AS requested_memory_mb --Total requested amount of memory in megabytes
        , mg.granted_memory_kb / 1024 AS granted_memory_mb --Total amount of memory actually granted in megabytes. NULL if not granted
        , mg.required_memory_kb / 1024 AS required_memory_mb--Minimum memory required to run this query in megabytes. 
        , max_used_memory_kb / 1024 AS max_used_memory_mb 
        , mg.query_cost --Estimated query cost.
        , mg.timeout_sec --Time-out in seconds before this query gives up the memory grant request.
        , mg.resource_semaphore_id --Nonunique ID of the resource semaphore on which this query is waiting.
        , mg.wait_time_ms --Wait time in milliseconds. NULL if the memory is already granted.
        , CASE mg.is_next_candidate --Is this process the next candidate for a memory grant
        WHEN 1 THEN 'Yes'
        WHEN 0 THEN 'No'
        ELSE 'Memory has been granted'
        END AS 'Next Candidate for Memory Grant'
        , rs.target_memory_kb
        / 1024 AS server_target_memory_mb --Grant usage target in megabytes.
        , rs.max_target_memory_kb
        / 1024 AS server_max_target_memory_mb --Maximum potential target in megabytes. NULL for the small-query resource semaphore.
        , rs.total_memory_kb
        / 1024 AS server_total_memory_mb --Memory held by the resource semaphore in megabytes. 
        , rs.available_memory_kb
        / 1024 AS server_available_memory_mb --Memory available for a new grant in megabytes.
        , rs.granted_memory_kb
        / 1024 AS server_granted_memory_mb  --Total granted memory in megabytes.
        , rs.used_memory_kb
        / 1024 AS server_used_memory_mb --Physically used part of granted memory in megabytes.
        , rs.grantee_count --Number of active queries that have their grants satisfied.
        , rs.waiter_count --Number of queries waiting for grants to be satisfied.
        , rs.timeout_error_count --Total number of time-out errors since server startup. NULL for the small-query resource semaphore.
        , rs.forced_grant_count --Total number of forced minimum-memory grants since server startup. NULL for the small-query resource semaphore.
    , OBJECT_NAME (q.objectid, q.dbid) AS 'Object_Name'
FROM     sys.dm_exec_requests r
        JOIN sys.dm_exec_connections c
        ON r.connection_id = c.connection_id
        AND c.net_transport <> 'session'
        JOIN sys.dm_exec_sessions s
        ON c.session_id = s.session_id
        JOIN sys.dm_exec_query_memory_grants mg
        ON s.session_id = mg.session_id
        INNER JOIN sys.dm_exec_query_resource_semaphores rs
        ON mg.resource_semaphore_id = rs.resource_semaphore_id AND mg.pool_id = rs.pool_id
        OUTER APPLY sys.dm_exec_sql_text (r.sql_handle ) AS q
ORDER BY wait_time DESC
OPTION (max_grant_percent = 3, MAXDOP 1, LOOP JOIN, FORCE ORDER)

  RAISERROR ('', 0, 1) WITH NOWAIT
END TRY
BEGIN CATCH
	  PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	  PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
END CATCH
GO

IF OBJECT_ID ('sp_mem_stats_proccache','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats_proccache
GO

CREATE PROCEDURE sp_mem_stats_proccache @runtime datetime , @lastruntime datetime=null
AS

-- This procedure is designed to be run periodically to track the size of the plan cache over time.

BEGIN TRY

  PRINT '-- proccache_summary'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, 
-- We have to cast usecounts as bigint to avoid arithmetic overflow in large TB memory sized servers.

         SUM (cast (size_in_bytes as bigint)) AS total_size_in_bytes, COUNT(*) AS plan_count, AVG (cast(usecounts as bigint)) AS avg_usecounts
  FROM sys.dm_exec_cached_plans
  RAISERROR ('', 0, 1) WITH NOWAIT


  -- Check for plans that are `"polluting`" the proc cache with trivial variations 
  -- (typically due to a lack of parameterization)
  PRINT '-- proccache_pollution';
  WITH cached_plans (cacheobjtype, objtype, usecounts, size_in_bytes, dbid, objectid, short_qry_text) AS 
  (
    SELECT p.cacheobjtype, p.objtype, p.usecounts, size_in_bytes, s.dbid, s.objectid, 
      CONVERT (nvarchar(100), REPLACE (REPLACE (
        CASE 
          -- Special cases: handle NULL s.[text] and 'SET NOEXEC'
          WHEN s.[text] IS NULL THEN NULL 
          WHEN CHARINDEX ('noexec', SUBSTRING (s.[text], 1, 200)) > 0 THEN SUBSTRING (s.[text], 1, 40)
          -- CASE #1: sp_executesql (query text passed in as 1st parameter) 
          WHEN (CHARINDEX ('sp_executesql', SUBSTRING (s.[text], 1, 200)) > 0) 
          THEN SUBSTRING (s.[text], CHARINDEX ('exec', SUBSTRING (s.[text], 1, 200)), 60) 
          -- CASE #3: any other stored proc -- strip off any parameters
          WHEN CHARINDEX ('exec ', SUBSTRING (s.[text], 1, 200)) > 0 
          THEN SUBSTRING (s.[text], CHARINDEX ('exec', SUBSTRING (s.[text], 1, 4000)), 
            CHARINDEX (' ', SUBSTRING (SUBSTRING (s.[text], 1, 200) + '   ', CHARINDEX ('exec', SUBSTRING (s.[text], 1, 500)), 200), 9) )
          -- CASE #4: stored proc that starts with common prefix 'sp%' instead of 'exec'
          WHEN SUBSTRING (s.[text], 1, 2) IN ('sp', 'xp', 'usp')
          THEN SUBSTRING (s.[text], 1, CHARINDEX (' ', SUBSTRING (s.[text], 1, 200) + ' '))
          -- CASE #5: ad hoc UPD/INS/DEL query (on average, updates/inserts/deletes usually 
          -- need a shorter substring to avoid hitting parameters)
          WHEN SUBSTRING (s.[text], 1, 30) LIKE '%UPDATE %' OR SUBSTRING (s.[text], 1, 30) LIKE '%INSERT %' 
            OR SUBSTRING (s.[text], 1, 30) LIKE '%DELETE %' 
          THEN SUBSTRING (s.[text], 1, 30)
          -- CASE #6: other ad hoc query
          ELSE SUBSTRING (s.[text], 1, 45)
        END
      , CHAR (10), ' '), CHAR (13), ' ')) AS short_qry_text 
    FROM sys.dm_exec_cached_plans p
    CROSS APPLY sys.dm_exec_sql_text (p.plan_handle) s
  ) 
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, 
    COUNT(*) AS plan_count, SUM (cast (size_in_bytes as bigint)) AS total_size_in_bytes,
    cacheobjtype, objtype, usecounts, dbid, objectid, short_qry_text 
  FROM cached_plans
  GROUP BY cacheobjtype, objtype, usecounts, dbid, objectid, short_qry_text
  HAVING COUNT(*) > 100
  ORDER BY COUNT(*) DESC
  RAISERROR ('', 0, 1) WITH NOWAIT
END TRY
BEGIN CATCH
	  PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	  PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
END CATCH
GO

IF OBJECT_ID ('sp_mem_stats_general','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats_general
GO

CREATE PROCEDURE sp_mem_stats_general @runtime datetime , @lastruntime datetime=null
AS

DECLARE @SQLVERSION BIGINT =  PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 4) 
                                + RIGHT(REPLICATE ('0', 3) + PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 3), 3)  
                                + RIGHT (replicate ('0', 6) + PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) , 6)

BEGIN TRY

  IF OBJECT_ID('tempdb..#db_inmemory') IS NOT NULL
  DROP TABLE #db_inmemory;
  
  IF OBJECT_ID('tempdb..#tmp_dm_db_xtp_index_stats ') IS NOT NULL
  DROP TABLE #tmp_dm_db_xtp_index_stats ;
  
  IF OBJECT_ID('tempdb..#tmp_dm_db_xtp_hash_index_stats ') IS NOT NULL
  DROP TABLE #tmp_dm_db_xtp_hash_index_stats ;
  
  IF OBJECT_ID('tempdb..#tmp_dm_db_xtp_table_memory_stats') IS NOT NULL
  DROP TABLE #tmp_dm_db_xtp_table_memory_stats;
  
  IF OBJECT_ID('tempdb..#tmp_dm_db_xtp_memory_consumers') IS NOT NULL
  DROP TABLE #tmp_dm_db_xtp_memory_consumers;

  PRINT '-- dm_os_memory_cache_counters'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM sys.dm_os_memory_cache_counters
  RAISERROR ('', 0, 1) WITH NOWAIT


  PRINT '-- dm_os_memory_clerks'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM sys.dm_os_memory_clerks
  RAISERROR ('', 0, 1) WITH NOWAIT


  PRINT '-- dm_os_memory_cache_clock_hands'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM sys.dm_os_memory_cache_clock_hands
  RAISERROR ('', 0, 1) WITH NOWAIT


  PRINT '-- dm_os_memory_cache_hash_tables'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM sys.dm_os_memory_cache_hash_tables
  RAISERROR ('', 0, 1) WITH NOWAIT


  PRINT '-- dm_os_memory_pools'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM sys.dm_os_memory_pools
  RAISERROR ('', 0, 1) WITH NOWAIT


  PRINT '-- sys.dm_os_loaded_modules (non-Microsoft)'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM sys.dm_os_loaded_modules 
  WHERE (company NOT LIKE '%Microsoft%' OR company IS NULL)
    AND UPPER (name) NOT LIKE '%_NSTAP_.DLL' -- instapi.dll (MS dll), with `"i`"'s wildcarded for Turkish systems
    AND UPPER (name) NOT LIKE '%\ODBC32.DLL' -- ODBC32.dll (MS dll)
  RAISERROR ('', 0, 1) WITH NOWAIT


  PRINT '-- sys.dm_os_sys_info'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * 
  FROM sys.dm_os_sys_info
  RAISERROR ('', 0, 1) WITH NOWAIT



  PRINT '-- sys.dm_os_memory_objects (total memory by type, >1MB)'

  DECLARE @sqlmemobj NVARCHAR(2048)
  IF  @SQLVERSION   < 11000000000  --prior to 2012
  
  BEGIN
  	SET @sqlmemobj = 
  	'SELECT CONVERT (varchar(30), @runtime, 121) as runtime, ' + 
  	  'SUM (CONVERT(bigint, (pages_allocated_count * page_size_in_bytes))) AS ''total_bytes_used'', type ' + 
  	'FROM sys.dm_os_memory_objects ' + 
  	'GROUP BY type  ' + 
  	'HAVING SUM (CONVERT(bigint,pages_allocated_count) * page_size_in_bytes) >= (1024*1024)  ' + 
  	'ORDER BY SUM (CONVERT(bigint,pages_allocated_count) * page_size_in_bytes) DESC '
  END
  ELSE
  BEGIN
  	SET @sqlmemobj =
  	'SELECT CONVERT (varchar(30), @runtime, 121) as runtime,  ' + 
  	  'SUM (CONVERT(bigint, pages_in_bytes)) AS ''total_bytes_used'', type  ' + 
  	'FROM sys.dm_os_memory_objects ' + 
  	'GROUP BY type  ' + 
  	'HAVING SUM (CONVERT(bigint,pages_in_bytes)) >= (1024*1024) ' + 
  	'ORDER BY SUM (CONVERT(bigint,pages_in_bytes)) DESC '
  END	
  
  EXEC sp_executesql @sqlmemobj, N'@runtime datetime', @runtime
  RAISERROR ('', 0, 1) WITH NOWAIT
  
  -- -- Check for windows memory notifications
  PRINT '-- memory_workingset_trimming'
  SELECT 
      CONVERT (varchar(30), @runtime, 121) as runtime,
      DATEADD (ms, a.[Record Time] - sys.ms_ticks, @runtime) AS Notification_time, 	
      	a.* ,
      sys.ms_ticks AS [Current Time]
  	FROM 
  	(SELECT x.value('(//Record/ResourceMonitor/Notification)[1]', 'varchar(30)') AS [Notification_type], 
  	x.value('(//Record/MemoryRecord/MemoryUtilization)[1]', 'bigint') AS [MemoryUtilizationPercent], 
  	x.value('(//Record/MemoryRecord/TotalPhysicalMemory)[1]', 'bigint') AS [TotalPhysicalMemory_KB], 
  	x.value('(//Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint') AS [AvailablePhysicalMemory_KB], 
  	x.value('(//Record/MemoryRecord/TotalPageFile)[1]', 'bigint') AS [TotalPageFile_KB], 
  	x.value('(//Record/MemoryRecord/AvailablePageFile)[1]', 'bigint') AS [AvailablePageFile_KB], 
  	x.value('(//Record/MemoryRecord/TotalVirtualAddressSpace)[1]', 'bigint') AS [TotalVirtualAddressSpace_KB], 
  	x.value('(//Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint') AS [AvailableVirtualAddressSpace_KB], 
  	x.value('(//Record/MemoryNode/@id)[1]', 'int') AS [Node Id], 
  	x.value('(//Record/MemoryNode/ReservedMemory)[1]', 'bigint') AS [SQL_ReservedMemory_KB], 
  	x.value('(//Record/MemoryNode/CommittedMemory)[1]', 'bigint') AS [SQL_CommittedMemory_KB], 
  	x.value('(//Record/@id)[1]', 'bigint') AS [Record Id], 
  	x.value('(//Record/@type)[1]', 'varchar(30)') AS [Type], 
  	x.value('(//Record/ResourceMonitor/IndicatorsProcess)[1]', 'bigint') AS [IndicatorsProcess], 
  	x.value('(//Record/ResourceMonitor/IndicatorsSystem)[1]', 'bigint') AS [IndicatorsSystem], 
  	x.value('(//Record/ResourceMonitor/IndicatorsPool)[1]', 'bigint') AS [IndicatorsPool], 
  	x.value('(//Record/@time)[1]', 'bigint') AS [Record Time]
  	FROM (SELECT CAST (record as xml) FROM sys.dm_os_ring_buffers 
  	WHERE ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR') AS R(x)) a 
  CROSS JOIN sys.dm_os_sys_info sys
  WHERE DATEADD (ms, a.[Record Time] - sys.ms_ticks, @runtime) BETWEEN @lastruntime AND @runtime
  ORDER BY DATEADD (ms, a.[Record Time] - sys.ms_ticks, @runtime)
  RAISERROR ('', 0, 1) WITH NOWAIT
  
  PRINT '-- sys.dm_os_ring_buffers (RING_BUFFER_RESOURCE_MONITOR and RING_BUFFER_MEMORY_BROKER)'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, 
    DATEADD (ms, ring.[timestamp] - sys.ms_ticks, GETDATE()) AS record_time, 
    ring.[timestamp] AS record_timestamp, sys.ms_ticks AS cur_timestamp, ring.* 
  FROM sys.dm_os_ring_buffers ring
  CROSS JOIN sys.dm_os_sys_info sys
  WHERE ring.ring_buffer_type IN ( 'RING_BUFFER_RESOURCE_MONITOR' , 'RING_BUFFER_MEMORY_BROKER' )
    AND DATEADD (ms, ring.timestamp - sys.ms_ticks, GETDATE()) BETWEEN @lastruntime AND GETDATE()
  RAISERROR ('', 0, 1) WITH NOWAIT
  
  PRINT '-- sys.dm_os_memory_brokers --'
  SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * 
  FROM sys.dm_os_memory_brokers 
  RAISERROR ('', 0, 1) WITH NOWAIT
  
  
  --In-Memory OLTP related data
  
  DECLARE @database_id INT
  DECLARE @dbname SYSNAME
  DECLARE @count INT
  DECLARE @maxcount INT
  DECLARE @sql NVARCHAR(MAX)
  
  DECLARE @dbtable TABLE (id INT IDENTITY (1,1) PRIMARY KEY,
  			                  database_id INT,
  			                  dbname SYSNAME
  			                 )
  
  IF  @SQLVERSION   >= 12000000000  --2014 and later
  BEGIN
  
    --database level in-memory dmvs
  
    SELECT IDENTITY(INT,1,1) AS id, 
           @database_id as database_id , 
           @dbname as dbname 
    INTO #db_inmemory
    FROM sys.databases
    WHERE 1=0
      
    INSERT INTO @dbtable
    SELECT database_id, name FROM sys.databases WHERE state_desc='ONLINE' 
    
    SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM @dbtable)
    
    WHILE (@count<=@maxcount)
    BEGIN
      BEGIN TRY
        SELECT @database_id = database_id,
        	     @dbname = dbname 
        FROM @dbtable
        WHERE id = @count
  
        IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN
      
          SET @sql = N'USE [' + @dbname + '];
    	               IF EXISTS(SELECT type_desc FROM sys.data_spaces WHERE type_desc = ''MEMORY_OPTIMIZED_DATA_FILEGROUP'')
    	               BEGIN
    	    		         INSERT INTO #db_inmemory VALUES (' + CONVERT(NVARCHAR(50),@database_id) + ',''' + @dbname +''');
    	    		       END'
    --    print @sql
          EXEC (@sql)       
          
        END
        
        SET @count = @count + 1

      END TRY
      BEGIN CATCH
      
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	    	PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	    	
        -- Increment the counter to avoid infinite loop. 
        SET @count = @count + 1

      END CATCH
  
    END
  
    SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM #db_inmemory)
  
    PRINT '-- sys.dm_db_xtp_index_stats --'
  
    CREATE TABLE #tmp_dm_db_xtp_index_stats (
      [dbname] SYSNAME NULL,
      [object_id] BIGINT NULL,
      [xtp_object_id]BIGINT NULL,
      [index_name] SYSNAME NULL,
      [scans_started]BIGINT NULL,
      [scans_retries]BIGINT NULL,
      [rows_returned]BIGINT NULL,
      [rows_touched]BIGINT NULL,
      [rows_expiring]BIGINT NULL,
      [rows_expired]BIGINT NULL,
      [rows_expired_removed]BIGINT NULL,
      [phantom_scans_started]BIGINT NULL,
      [phantom_scans_retries]BIGINT NULL,
      [phantom_rows_touched]BIGINT NULL,
      [phantom_expiring_rows_encountered]BIGINT NULL,
      [phantom_expired_removed_rows_encountered]BIGINT NULL,
      [phantom_expired_rows_removed]BIGINT NULL,
      [object_address]VARBINARY(8) NULL
    )
  
    WHILE (@count<=@maxcount)
    BEGIN
      BEGIN TRY
    
        SELECT @database_id = database_id,
    	         @dbname = dbname 
        FROM #db_inmemory
        WHERE id = @count
        
        IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN
          
          IF  @SQLVERSION   >= 13000000000  --SQL 2016 and later
          BEGIN
            SET @sql = N'USE [' + @dbname + '];
           	 		         INSERT INTO #tmp_dm_db_xtp_index_stats
           				       SELECT '''+@dbname+''',
    	    					            [object_id],					    
                                [xtp_object_id],
                                [index_id],
                                [scans_started],
                                [scans_retries],
                                [rows_returned],
                                [rows_touched],
                                [rows_expiring],
                                [rows_expired],
                                [rows_expired_removed],
                                [phantom_scans_started],
                                [phantom_scans_retries],
                                [phantom_rows_touched],
                                [phantom_expiring_rows_encountered],
                                [phantom_expired_removed_rows_encountered],
                                [phantom_expired_rows_removed],
                                [object_address]
           				       FROM sys.dm_db_xtp_index_stats ids;'
          END
          ELSE
          BEGIN
            SET @sql = N'USE [' + @dbname + '];
           	 		         INSERT INTO #tmp_dm_db_xtp_index_stats
           				       SELECT '''+@dbname+''',
    	    					            [object_id],
                               	NULL,--[xtp_object_id],
                               	[index_id],
                               	[scans_started],
                               	[scans_retries],
                               	[rows_returned],
                               	[rows_touched],
                               	[rows_expiring],
                               	[rows_expired],
                               	[rows_expired_removed],
                               	[phantom_scans_started],
                               	[phantom_scans_retries],
                               	[phantom_rows_touched],
                               	[phantom_expiring_rows_encountered],
                               	[phantom_expired_removed_rows_encountered],
                               	[phantom_expired_rows_removed],
                               	[object_address]
           					     FROM sys.dm_db_xtp_index_stats AS ids;'  						       
          END
         
           --print @sql
           EXEC (@sql)

        END

        SET @count = @count + 1

      END TRY
      BEGIN CATCH
        
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	    	PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	    	
        -- Increment the counter to avoid infinite loop. 
        SET @count = @count + 1

      END CATCH
    END
    
    SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM #tmp_dm_db_xtp_index_stats 
    RAISERROR ('', 0, 1) WITH NOWAIT
  
    PRINT '-- sys.dm_db_xtp_hash_index_stats --'
   
    SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM #db_inmemory)
   
    CREATE TABLE #tmp_dm_db_xtp_hash_index_stats(
     dbname SYSNAME NULL,
     objname SYSNAME NULL,
     indexname SYSNAME NULL,
     total_bucket_count BIGINT NULL,
     empty_bucket_count BIGINT NULL,
     empty_bucket_percent FLOAT NULL,
     avg_chain_length BIGINT NULL,
     max_chain_length BIGINT NULL
    )
   
    WHILE (@count<=@maxcount)
    BEGIN

      BEGIN TRY
    
        SELECT @database_id = database_id,
    	       @dbname = dbname 
        FROM #db_inmemory
        WHERE id = @count

        IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN
      
          SET @sql = N'USE [' + @dbname + '];
    	               INSERT INTO #tmp_dm_db_xtp_hash_index_stats
    	    		       SELECT '''+@dbname+''',
                            OBJECT_NAME(hs.object_id),  
                            i.name,  
                            hs.total_bucket_count, 
                            hs.empty_bucket_count, 
                            FLOOR((CAST(empty_bucket_count as float)/total_bucket_count) * 100), 
                            hs.avg_chain_length,  
                            hs.max_chain_length 
                     FROM sys.dm_db_xtp_hash_index_stats AS hs  
                       INNER JOIN sys.indexes AS i  
                         ON hs.object_id=i.object_id AND hs.index_id=i.index_id'
            
          
          --print @sql
          EXEC (@sql)
          
        END

        SET @count = @count + 1

      END TRY
      BEGIN CATCH

        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	    	PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	    	
        -- Increment the counter to avoid infinite loop. 
        SET @count = @count + 1

      END CATCH
    END
   
    SELECT CONVERT (varchar(30), @runtime, 121) as runtime,* FROM #tmp_dm_db_xtp_hash_index_stats
    RAISERROR ('', 0, 1) WITH NOWAIT
    
    PRINT '-- sys.dm_db_xtp_table_memory_stats --'
    
    SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM #db_inmemory)
    
    CREATE TABLE #tmp_dm_db_xtp_table_memory_stats(
      [dbname] SYSNAME NULL,
      [object_name] SYSNAME NULL,
      [object_id] BIGINT NULL,
      [memory_allocated_for_table_kb] BIGINT NULL,
      [memory_used_by_table_kb] BIGINT NULL,
      [memory_allocated_for_indexes_kb] BIGINT NULL,
      [memory_used_by_indexes_kb] BIGINT NULL
    )
        
    WHILE (@count<=@maxcount)
    BEGIN

      BEGIN TRY
    
        SELECT @database_id = database_id,
    	       @dbname = dbname 
        FROM #db_inmemory
        WHERE id = @count

        IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN
      
          SET @sql = N'USE [' + @dbname + '];
    	               INSERT INTO #tmp_dm_db_xtp_table_memory_stats
                     SELECT '''+@dbname+''',
                            OBJECT_NAME(object_id),
                            [object_id],
                            [memory_allocated_for_table_kb],
                            [memory_used_by_table_kb],
                            [memory_allocated_for_indexes_kb],
                            [memory_used_by_indexes_kb]
                     FROM sys.dm_db_xtp_table_memory_stats
                     OPTION (FORCE ORDER);'
        
          --print @sql
          EXEC (@sql)          

        END

        SET @count = @count + 1

      END TRY
      BEGIN CATCH
      
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	    	PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	    	
        -- Increment the counter to avoid infinite loop. 
        SET @count = @count + 1
      
      END CATCH
    
    END
    
    SELECT CONVERT (varchar(30), @runtime, 121) as runtime,* from #tmp_dm_db_xtp_table_memory_stats
    RAISERROR ('', 0, 1) WITH NOWAIT
    
    PRINT '-- sys.dm_db_xtp_memory_consumers --'
    
    SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM #db_inmemory)
    
    CREATE TABLE #tmp_dm_db_xtp_memory_consumers (
    	[dbname] SYSNAME NULL,
    	[object_name] SYSNAME NULL,
    	[memory_consumer_id] BIGINT NULL, 
    	[memory_consumer_type] INT NULL,
    	[memory_consumer_type_desc]NVARCHAR(64) NULL,
    	[memory_consumer_desc]NVARCHAR(64) NULL,
    	[object_id] BIGINT NULL,
    	[xtp_object_id] BIGINT NULL,
    	[index_id] INT NULL,
    	[allocated_bytes] BIGINT NULL,
    	[used_bytes] BIGINT NULL,
    	[allocation_count] INT NULL,
    	[partition_count] INT NULL,
    	[sizeclass_count] INT NULL,
    	[min_sizeclass] INT NULL,
    	[max_sizeclass]INT NULL,
    	[memory_consumer_address] VARBINARY(8) NULL
    	)
    
    
    
    WHILE (@count<=@maxcount)
    BEGIN

      BEGIN TRY
    
        SELECT @database_id = database_id,
            @dbname = dbname 
        FROM #db_inmemory
        WHERE id = @count
      
        
        IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN
          
          IF  @SQLVERSION   >= 13000000000  --SQL 2016 and later
          BEGIN
            SET @sql = N'USE [' + @dbname + ']; 
                         INSERT INTO #tmp_dm_db_xtp_memory_consumers
    	      		         SELECT '''+@dbname+''',
    	      			       	      CONVERT(char(20), OBJECT_NAME(object_id)) AS Name, 
    	      		                [memory_consumer_id],
    	                          [memory_consumer_type],
    	                          [memory_consumer_type_desc],
    	                          [memory_consumer_desc],
    	                          [object_id],
    	                          [xtp_object_id],
    	                          [index_id],
    	                          [allocated_bytes],
    	                          [used_bytes],
    	                          [allocation_count],
    	                          [partition_count],
    	                          [sizeclass_count],
    	                          [min_sizeclass],
    	                          [max_sizeclass],
    	                          [memory_consumer_address]
                         FROM sys.dm_db_xtp_memory_consumers;'
          END
          ELSE
          BEGIN
          
            SET @sql = N'USE [' + @dbname + ']; 
                         INSERT INTO #tmp_dm_db_xtp_memory_consumers
    	      		         SELECT '''+@dbname+''',
    	      			       	      CONVERT(char(20), OBJECT_NAME(object_id)) AS Name, 
    	      		                [memory_consumer_id],
    	                          [memory_consumer_type],
    	                          [memory_consumer_type_desc],
    	                          [memory_consumer_desc],
    	                          [object_id],
    	                          NULL,--[xtp_object_id],
    	                          [index_id],
    	                          [allocated_bytes],
    	                          [used_bytes],
    	                          [allocation_count],
    	                          [partition_count],
    	                          [sizeclass_count],
    	                          [min_sizeclass],
    	                          [max_sizeclass],
    	                          [memory_consumer_address]
                         FROM sys.dm_db_xtp_memory_consumers;'
            
      
          END
        
          --print @sql
          EXEC (@sql)          
        
        END

        SET @count = @count + 1

      END TRY
      BEGIN CATCH
      
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	    	PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	    	
        -- Increment the counter to avoid infinite loop. 
        SET @count = @count + 1
      
      END CATCH
    
    END
    
    SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM #tmp_dm_db_xtp_memory_consumers
    RAISERROR ('', 0, 1) WITH NOWAIT  
    
    PRINT '-- sys.dm_db_xtp_object_stats --'
  
    SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM #db_inmemory)
  	  
  	CREATE table #tmp_dm_db_xtp_object_stats(
        [dbname] SYSNAME NULL,
        [object_id]BIGINT NULL,
        [xtp_object_id]BIGINT NULL,
        [row_insert_attempts]BIGINT NULL,
        [row_update_attempts]BIGINT NULL,
        [row_delete_attempts]BIGINT NULL,
        [write_conflicts]BIGINT NULL,
        [unique_constraint_violations]BIGINT NULL,
        [object_address] VARBINARY(8)
    )
  
  	WHILE (@count<=@maxcount)
    BEGIN
      BEGIN TRY
        SELECT @database_id = database_id,
    	         @dbname = dbname 
        FROM #db_inmemory
        WHERE id = @count
        
        IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN
          IF  @SQLVERSION   >= 13000000000  --SQL 2016 and later
          BEGIN
            SET @sql = N'USE [' + @dbname + '];
           	 		         INSERT INTO #tmp_dm_db_xtp_object_stats
           			         SELECT '''+@dbname+''',
    	    			                [object_id],
                                [xtp_object_id],
                                [row_insert_attempts],
                                [row_update_attempts],
                                [row_delete_attempts],
                                [write_conflicts],
                                [unique_constraint_violations],
                                [object_address]
                          FROM sys.dm_db_xtp_object_stats;'
                                
          END
          ELSE
          BEGIN
            SET @sql = N'USE [' + @dbname + '];
           	 		         INSERT INTO #tmp_dm_db_xtp_object_stats
           			         SELECT '''+@dbname+''',
    	    			                [object_id],
                                NULL, --[xtp_object_id],
                                [row_insert_attempts],
                                [row_update_attempts],
                                [row_delete_attempts],
                                [write_conflicts],
                                [unique_constraint_violations],
                                [object_address]
                         FROM sys.dm_db_xtp_object_stats;'
          END
         
           --print @sql
           EXEC (@sql)
        END
        
        SET @count = @count + 1

      END TRY
      BEGIN CATCH
      
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	    	PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	    	
        -- Increment the counter to avoid infinite loop. 
        SET @count = @count + 1

      END CATCH
       
    END
  
  	SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM #tmp_dm_db_xtp_object_stats 
    RAISERROR ('', 0, 1) WITH NOWAIT	  
      
    PRINT '-- sys.dm_db_xtp_checkpoint_files --'
  
    SET @count = 1
    SET @maxcount = (SELECT MAX(id) FROM #db_inmemory)
     
    CREATE table #tmp_dm_db_xtp_checkpoint_files_2016 (
       [dbname] SYSNAME NULL,
       [container_id] INT NULL,
       [container_guid] UNIQUEIDENTIFIER NULL,
       [checkpoint_file_id] UNIQUEIDENTIFIER NULL,
       [relative_file_path] NVARCHAR (520) NULL,
       [file_type] SMALLINT NULL,
       [file_type_desc] NVARCHAR (120) NULL,
       [internal_storage_slot] INT NULL,
       [checkpoint_pair_file_id]	UNIQUEIDENTIFIER NULL,
       [file_size_in_bytes] BIGINT NULL,
       [file_size_used_in_bytes]	BIGINT NULL,
       [logical_row_count] BIGINT NULL,
       [state] SMALLINT NULL,
       [state_desc] NVARCHAR(120) NULL,
       [lower_bound_tsn]	BIGINT NULL,
       [upper_bound_tsn]	BIGINT NULL,
       [begin_checkpoint_id]	BIGINT NULL,
       [end_checkpoint_id] BIGINT NULL,
       [last_updated_checkpoint_id] bigint NULL,
       [encryption_status] SMALLINT NULL,
       [encryption_status_desc] NVARCHAR (120) NULL
    )
    
    CREATE table #tmp_dm_db_xtp_checkpoint_files_2014(
      [dbname] SYSNAME NULL,
      [container_id] INT NULL,
      [container_guid] UNIQUEIDENTIFIER NULL,
      [checkpoint_file_id] UNIQUEIDENTIFIER NULL,
      [relative_file_path] NVARCHAR (520) NULL,
      [file_type] SMALLINT NULL,
      [file_type_desc] NVARCHAR (120) NULL,
      [internal_storage_slot] int NULL,
      [checkpoint_pair_file_id]	UNIQUEIDENTIFIER NULL,
      [file_size_in_bytes] BIGINT NULL,
      [file_size_used_in_bytes]	BIGINT NULL,
      [inserted_row_count] BIGINT NULL,
      [deleted_row_count] BIGINT NULL,
      [drop_table_deleted_row_count] BIGINT NULL,
      [state] SMALLINT NULL,
      [state_desc] NVARCHAR(120) NULL,
      [lower_bound_tsn]	BIGINT NULL,
      [upper_bound_tsn]	BIGINT NULL,
      [last_backup_page_count] INT NULL,
      [delta_watermark_tsn]	BIGINT NULL,
      [last_checkpoint_recovery_lsn] NUMERIC(25,0) NULL,
      [tombstone_operation_lsn] NUMERIC(25,0) NULL,
      [logical_deletion_log_block_id] BIGINT NULL,
    )
    
    WHILE (@count<=@maxcount)
    BEGIN

      BEGIN TRY
    
        SELECT @database_id = database_id,
    	         @dbname = dbname 
        FROM #db_inmemory
        WHERE id = @count

        IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN
      
          IF  @SQLVERSION   >= 13000000000  --SQL 2016 and later
          BEGIN
            SET @sql = N'USE [' + @dbname + '];
           	 		         INSERT INTO #tmp_dm_db_xtp_checkpoint_files_2016
           			         SELECT '''+@dbname+''',
    	    			           [container_id] ,
                           [container_guid],
                           [checkpoint_file_id],
                           [relative_file_path],
                           [file_type] smallint,
                           [file_type_desc],
                           [internal_storage_slot],
                           [checkpoint_pair_file_id],
                           [file_size_in_bytes],
                           [file_size_used_in_bytes],
                           [logical_row_count],
                           [state],
                           [state_desc],
                           [lower_bound_tsn],	
                           [upper_bound_tsn],
                           [begin_checkpoint_id],
                           [end_checkpoint_id], 
                           [last_updated_checkpoint_id], 
                           [encryption_status], 
                           [encryption_status_desc]
                         FROM sys.dm_db_xtp_checkpoint_files;'
                                
          END
          ELSE
          BEGIN
            SET @sql = N'USE [' + @dbname + '];
           	 		         INSERT INTO #tmp_dm_db_xtp_checkpoint_files_2014
           			         SELECT '''+@dbname+''',
    	    			           [container_id],
                           [container_guid],
                           [checkpoint_file_id],
                           [relative_file_path],
                           [file_type] SMALLINT,
                           [file_type_desc],
                           [internal_storage_slot],
                           [checkpoint_pair_file_id],
                           [file_size_in_bytes],
                           [file_size_used_in_bytes],
                           [inserted_row_count],
                           [deleted_row_count],
                           [drop_table_deleted_row_count],
                           [state],
                           [state_desc],
                           [lower_bound_tsn],
                           [upper_bound_tsn],
                           [last_backup_page_count],
                           [delta_watermark_tsn],
                           [last_checkpoint_recovery_lsn],
                           [tombstone_operation_lsn],
                           [logical_deletion_log_block_id]
                         FROM sys.dm_db_xtp_checkpoint_files;'
          END
          
          --PRINT @sql
          EXEC (@sql)

        END

        SET @count = @count + 1
      
      END TRY
      BEGIN CATCH
      
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	    	PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	    	
        -- Increment the counter to avoid infinite loop. 
        SET @count = @count + 1
      
      END CATCH        
     
    END
  
    IF  @SQLVERSION   >= 13000000000  --SQL 2016 and later
    BEGIN
      SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM #tmp_dm_db_xtp_checkpoint_files_2016
    END 
    ELSE
    BEGIN
      SELECT CONVERT (varchar(30), @runtime, 121) as runtime, * FROM #tmp_dm_db_xtp_checkpoint_files_2014
    END
    RAISERROR ('', 0, 1) WITH NOWAIT
    
    --instance level in-memory dmvs
    PRINT '-- sys.dm_xtp_system_memory_consumers --'
    
    SELECT CONVERT (varchar(30), @runtime, 121) as runtime,
    	   [memory_consumer_id],
    	   [memory_consumer_type],
    	   [memory_consumer_type_desc],
    	   [memory_consumer_desc],
    	   [lookaside_id],
    	   [allocated_bytes],
    	   [used_bytes],
    	   [allocation_count],
    	   [partition_count],
    	   [sizeclass_count],
    	   [min_sizeclass],
    	   [max_sizeclass],
    	   [memory_consumer_address]
    FROM sys.dm_xtp_system_memory_consumers
    WHERE allocated_bytes > 0
    RAISERROR ('', 0, 1) WITH NOWAIT
    
    PRINT '-- sys.dm_xtp_system_memory_consumers_summary --'
    
    SELECT CONVERT (varchar(30), @runtime, 121) as runtime,
           SUM(allocated_bytes) / (1024 * 1024) AS total_allocated_MB,
           SUM(used_bytes) / (1024 * 1024) AS total_used_MB
    FROM sys.dm_xtp_system_memory_consumers
    RAISERROR ('', 0, 1) WITH NOWAIT
    
    PRINT '-- sys.dm_xtp_gc_stats --'
    
    SELECT CONVERT (varchar(30), @runtime, 121) as runtime,
    	[rows_examined],
    	[rows_no_sweep_needed],
    	[rows_first_in_bucket],
    	[rows_first_in_bucket_removed],
    	[rows_marked_for_unlink],
    	[parallel_assist_count],
    	[idle_worker_count],
    	[sweep_scans_started],
    	[sweep_scan_retries],
    	[sweep_rows_touched],
    	[sweep_rows_expiring],
    	[sweep_rows_expired],
    	[sweep_rows_expired_removed]
    FROM sys.dm_xtp_gc_stats
    RAISERROR ('', 0, 1) WITH NOWAIT
    
    
    PRINT '-- sys.dm_xtp_gc_queue_stats --'
    
    SELECT CONVERT (varchar(30), @runtime, 121) as runtime,
    	   [queue_id],
    	   [total_enqueues],
    	   [total_dequeues],
    	   [current_queue_depth],
    	   [maximum_queue_depth],
    	   [last_service_ticks]
    FROM sys.dm_xtp_gc_queue_stats
    ORDER BY current_queue_depth DESC
    RAISERROR ('', 0, 1) WITH NOWAIT
   
  END
  ELSE
  BEGIN
    PRINT 'No XTP supported in this version of SQL Server'
    RAISERROR ('', 0, 1) WITH NOWAIT
  END
END TRY
BEGIN CATCH
	  PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	  PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
END CATCH
GO


IF OBJECT_ID ('sp_mem_stats9','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats9
GO
go
CREATE PROCEDURE sp_mem_stats9  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	EXEC sp_mem_stats_grants_mem_script @runtime, @lastruntime
	EXEC sp_mem_stats_proccache @runtime, @lastruntime
	EXEC sp_mem_stats_general @runtime, @lastruntime
END
GO

IF OBJECT_ID ('sp_mem_stats10','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats10
GO

CREATE PROCEDURE sp_mem_stats10  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	EXEC sp_mem_stats9  @runtime, @lastruntime
END
GO


IF OBJECT_ID ('sp_mem_stats11','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats11
GO
go
CREATE PROCEDURE sp_mem_stats11  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	EXEC sp_mem_stats10  @runtime, @lastruntime
END
GO

IF OBJECT_ID ('sp_mem_stats12','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats12
GO

CREATE PROCEDURE sp_mem_stats12  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	EXEC sp_mem_stats11  @runtime, @lastruntime
END
GO

IF OBJECT_ID ('sp_mem_stats13','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats13
GO

CREATE PROCEDURE sp_mem_stats13  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	EXEC sp_mem_stats12  @runtime, @lastruntime
END
GO

IF OBJECT_ID ('sp_mem_stats14','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats14
GO
go
CREATE PROCEDURE sp_mem_stats14  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	EXEC sp_mem_stats13  @runtime, @lastruntime
END
GO

IF OBJECT_ID ('sp_mem_stats15','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats15
GO

CREATE PROCEDURE sp_mem_stats15  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	EXEC sp_mem_stats14  @runtime, @lastruntime
END
GO

IF OBJECT_ID ('sp_mem_stats16','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats16
GO
go
CREATE PROCEDURE sp_mem_stats16  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	exec sp_mem_stats15  @runtime, @lastruntime
END
GO
IF OBJECT_ID ('sp_mem_stats17','P') IS NOT NULL
   DROP PROCEDURE sp_mem_stats17
GO
go
CREATE PROCEDURE sp_mem_stats17  @runtime datetime , @lastruntime datetime =null
AS 
BEGIN
	exec sp_mem_stats16  @runtime, @lastruntime
END
GO



IF OBJECT_ID ('sp_Run_MemStats','P') IS NOT NULL
   DROP PROCEDURE sp_Run_MemStats
GO
create procedure sp_Run_MemStats @WaitForDelayString nvarchar(10)
as
DECLARE @runtime datetime
DECLARE @lastruntime datetime
SET @lastruntime = '19000101'

DECLARE @servermajorversion nvarchar(2)
SET @servermajorversion = REPLACE (LEFT (CONVERT (varchar, SERVERPROPERTY ('ProductVersion')), 2), '.', '')
declare @sp_mem_stats_ver sysname
set @sp_mem_stats_ver = 'sp_mem_stats' + @servermajorversion

print 'running memory collector ' + @sp_mem_stats_ver
WHILE (1=1)
BEGIN
  BEGIN TRY
    SET @runtime = GETDATE()
    PRINT ''
    PRINT 'Start time: ' + CONVERT (varchar (50), GETDATE(), 121)
    PRINT ''

    exec @sp_mem_stats_ver @runtime, @lastruntime

      -- Save current runtime -- we'll use it to display only new ring buffer records on the next snapshot
    SET @lastruntime = DATEADD (s, -15, @runtime) -- allow for up to a 15 second snapshot runtime without missing records
    -- flush the buffer
    RAISERROR ('', 0,1) WITH NOWAIT
    WAITFOR DELAY @WaitForDelayString
  END TRY
  BEGIN CATCH
				PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
				PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
  END CATCH
END
GO

exec sp_Run_MemStats '0:2:0'
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAfCQU+x+OWQJ76
# //V3BHRMTYV2ze5avVAlnsKZK5OiCKCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEINhpGYasmYj4
# Zf9AQJgKgMPegSjC3IBqQm56lC2aLtRpMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAbaoHZkikd0g5mIkoNE/8V2DwvigNJR3NAiiUxOJsutoT
# kzdayDsvRzFx7LRWsVXj2xfdZAdFl6B0VgoVHT+93TR0emItYk2HfkQ5bhayoqip
# caE1UWyuEmGZImWC5L6Z1xhZGf48ATOL7v3YVeUof+UuUBDClLf7RNiOXTZlOLvb
# 81xLRNEHmbzZmpPiJm//3dJ8ERYucMTYq7NNf4NhuB9O81Q7HEfcRMFpl3/MTf6b
# UYDTVmfgXqgKIq7OsgMJaJCDawG/RpbisbJbD4hP72tKbs1XUGc9meVOUSDVHGYR
# 0jZnx/RNbRkHKpvqpgBMrmrkPkKH6foaniV/Fxs+oaGCF60wghepBgorBgEEAYI3
# AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCCoI2u5QGV3tVN8TmBeOmEjSRwEbo1qb7uyIHxWv8LM
# TwIGaXNTHBuPGBMyMDI2MDIwNDE2MzUyOC41NjFaMASAAgH0oIHZpIHWMIHTMQsw
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
# FCzWxKrnkDIbII6uXzeYYOReeU1rFvt3A+gMnY/xYCEwgfoGCyqGSIb3DQEJEAIv
# MYHqMIHnMIHkMIG9BCAsrTOpmu+HTq1aXFwvlhjF8p2nUCNNCEX/OWLHNDMmtzCB
# mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACEUUYOZtD
# z/xsAAEAAAIRMCIEIPtAmOQ4ljBTF5yKpkNotGmgdzTRPv/JiYhDf6hGv7h+MA0G
# CSqGSIb3DQEBCwUABIICAJrXLju3yKwv0sdT3v7Ign7Y6klgshvTHjBAXQD+k8a1
# MFTxWwgctVlqDTmRsqnUVsIHCnL4cxewk8OoC4+4U1EU+n/JBflIayAF/+EnaRnh
# pgaz8hnPN+VI6CYpuehu94iku77u4IovcXecmaw2KgLWEdwQ9yyjgrntGB9qPE3R
# QEnvUdr0yYWT9JIIxHrM+yrHkAOyhqf3ZMuJtpn7QkLwn4dJ1A0ARUe/IO1bs8Wd
# rOzMpfoQVMBRVuSUXZgwa/PPsicPd7dBV/s8WgR1nEpXXZPmuKlwakPb94uraJa0
# MHB+CkeaCUUOBxqHG4k0Qa9RhiusftxKOLHYBgLoK+KjTgxyrPC3WsR0xn/vkQpI
# 4r5x6O73x7C4lgZC3fhdCtmwRDEVBvnT4ShF9EmTFVGx0c65kj9aKQ0+vaNb8UG4
# h+lRw99X3RtLjiNZQLSmY0FR7y+Y5PbUcS362zIFPhqR015P2w1okvYoivCXPAW1
# cBPO0DtMZdhBlqSsotUlRXnGdc2bxwVXxtOi9K7kYrq5CadrjqgWZT5cFwEnZzws
# kZEh/n2yyIzkeivL7yL7W/R0qw8ChPRjUfwQs2Fzz/v7ECUgJASIOSBroTOZU6KR
# cQSv91ARdIUK8YZDAzKaDpZIYAJTlG3IKO16p/5DjsBufi4p9RX9WNKF53gRUxlO
# SIG # End signature block
