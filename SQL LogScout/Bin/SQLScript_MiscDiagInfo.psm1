
    function MiscDiagInfo_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "MiscDiagInfo"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
    SET NOCOUNT ON

    PRINT ''
    RAISERROR ('-- DiagInfo --', 0, 1) WITH NOWAIT
    SELECT 1002 AS 'DiagVersion', '2023-12-06' AS 'DiagDate'
    PRINT ''

    PRINT 'Script Version = 1001'
    PRINT ''

    SET LANGUAGE us_english
    PRINT '-- Script and Environment Details --'
    PRINT 'Name                     Value'
    PRINT '------------------------ ---------------------------------------------------'
    PRINT 'Script Name              Misc Diagnostics Info'
    PRINT 'Script File Name         `$File: MiscDiagInfo.sql `$'
    PRINT 'Revision                 `$Revision: 1 `$ (`$Change: ? `$)'
    PRINT 'Last Modified            `$Date: 2023/12/06 12:04:00 EST `$'
    PRINT 'Script Begin Time        ' + CONVERT (VARCHAR(30), GETDATE(), 126) 
    PRINT 'Current Database         ' + DB_NAME()
    PRINT ''



    -- ParsName is used to extract MajorVersion , MinorVersion and Build from ProductVersion e.g. 16.0.1105.1 will comeback AS 16000001105

    DECLARE @SQLVERSION BIGINT =  PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 4) 
                                + RIGHT(REPLICATE ('0', 3) + PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 3), 3)  
                                + RIGHT (replicate ('0', 6) + PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) , 6)

    CREATE TABLE #summary (PropertyName NVARCHAR(50) primary key, PropertyValue NVARCHAR(256))
    INSERT INTO #summary VALUES ('ProductVersion', cast (SERVERPROPERTY('ProductVersion') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('MajorVersion', LEFT(CONVERT(SYSNAME,SERVERPROPERTY('ProductVersion')), CHARINDEX('.', CONVERT(SYSNAME,SERVERPROPERTY('ProductVersion')), 0)-1))
    INSERT INTO #summary VALUES ('IsClustered', cast (SERVERPROPERTY('IsClustered') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('Edition', cast (SERVERPROPERTY('Edition') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('InstanceName', cast (SERVERPROPERTY('InstanceName') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('SQLServerName', @@SERVERNAME)
    INSERT INTO #summary VALUES ('MachineName', cast (SERVERPROPERTY('MachineName') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('ProcessID', cast (SERVERPROPERTY('ProcessID') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('ResourceVersion', cast (SERVERPROPERTY('ResourceVersion') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('ServerName', cast (SERVERPROPERTY('ServerName') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('ComputerNamePhysicalNetBIOS', cast (SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('BuildClrVersion', cast (SERVERPROPERTY('BuildClrVersion') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('IsFullTextInstalled', cast (SERVERPROPERTY('IsFullTextInstalled') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('IsIntegratedSecurityOnly', cast (SERVERPROPERTY('IsIntegratedSecurityOnly') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('ProductLevel', cast (SERVERPROPERTY('ProductLevel') AS NVARCHAR(max)))
    INSERT INTO #summary VALUES ('suser_name()', cast (SUSER_NAME() AS NVARCHAR(max)))

    INSERT INTO #summary SELECT 'number of visible schedulers', count (*) 'cnt' FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE'
    INSERT INTO #summary SELECT 'number of visible numa nodes', count (distinct parent_node_id) 'cnt' FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE'
    INSERT INTO #summary SELECT 'cpu_count', cpu_count FROM sys.dm_os_sys_info
    INSERT INTO #summary SELECT 'hyperthread_ratio', hyperthread_ratio FROM sys.dm_os_sys_info
    INSERT INTO #summary SELECT 'machine start time', convert(VARCHAR(23),dateadd(SECOND, -ms_ticks/1000, GETDATE()),121) FROM sys.dm_os_sys_info
    INSERT INTO #summary SELECT 'number of tempdb data files', count (*) 'cnt' FROM master.sys.master_files WHERE database_id = 2 and [type] = 0
    INSERT INTO #summary SELECT 'number of active profiler traces',count(*) 'cnt' FROM ::fn_trace_getinfo(0) WHERE property = 5 and convert(TINYINT,value) = 1
    INSERT INTO #summary SELECT 'suser_name() default database name',default_database_name FROM sys.server_principals WHERE name = SUSER_NAME()

    INSERT INTO #summary SELECT  'VISIBLEONLINE_SCHEDULER_COUNT' PropertyName, count (*) PropertValue FROM sys.dm_os_schedulers WHERE status='VISIBLE ONLINE'
    INSERT INTO #summary SELECT 'UTCOffset_in_Hours' PropertyName, cast( datediff (MINUTE, getutcdate(), getdate()) / 60.0 AS decimal(10,2)) PropertyValue


    DECLARE @cpu_ticks BIGINT
    SELECT @cpu_ticks = cpu_ticks FROM sys.dm_os_sys_info
    WAITFOR DELAY '0:0:2'
    SELECT @cpu_ticks = cpu_ticks - @cpu_ticks FROM sys.dm_os_sys_info

    INSERT INTO #summary VALUES ('cpu_ticks_per_sec', @cpu_ticks / 2 )

    PRINT ''

    -- GO

    --removing xp_instance_regread calls & related variables as a part of issue #149
    
    DECLARE @value NVARCHAR(256)
    DECLARE @pos INT 
    
    --get windows info from dmv
    SELECT @value = windows_release FROM sys.dm_os_windows_info

    SET @pos = CHARINDEX(N'.', @value)
    IF @pos != 0
    BEGIN
        INSERT INTO #summary VALUES ('operating system version major',SUBSTRING(@value, 1, @pos-1))
        INSERT INTO #summary VALUES ('operating system version minor',SUBSTRING(@value, @pos+1, LEN(@value)))	
        
        --inserting NULL to keep same #summary structure

        INSERT INTO #summary VALUES ('operating system version build', NULL)
        
        INSERT INTO #summary VALUES ('operating system', NULL)	

        INSERT INTO #summary VALUES ('operating system install date',NULL)
    
    END
    
        --inserting NULL to keep same #summary structure 
        INSERT INTO #summary VALUES ('registry SystemManufacturer', NULL)

        INSERT INTO #summary VALUES ('registry SystemProductName', NULL)	

        INSERT INTO #summary VALUES ('registry ActivePowerScheme (default)', NULL)	

        INSERT INTO #summary VALUES ('registry ActivePowerScheme', NULL)	

        --inserting OS Edition and Build from @@Version 
        INSERT INTO #summary VALUES ('OS Edition and Build from @@Version',  REPLACE(LTRIM(SUBSTRING(@@VERSION,CHARINDEX(' on ',@@VERSION)+3,100)),CHAR(10),''))
    

    IF (@SQLVERSION >= 10000001600) --10.0.1600
    BEGIN
        EXEC sp_executesql N'INSERT INTO #summary SELECT ''sqlserver_start_time'', convert(VARCHAR(23),sqlserver_start_time,121) FROM sys.dm_os_sys_info'
        EXEC sp_executesql N'INSERT INTO #summary SELECT ''resource governor enabled'', is_enabled FROM sys.resource_governor_configuration'
        INSERT INTO #summary VALUES ('FilestreamShareName', cast (SERVERPROPERTY('FilestreamShareName') AS NVARCHAR(max)))
        INSERT INTO #summary VALUES ('FilestreamConfiguredLevel', cast (SERVERPROPERTY('FilestreamConfiguredLevel') AS NVARCHAR(max)))
        INSERT INTO #summary VALUES ('FilestreamEffectiveLevel', cast (SERVERPROPERTY('FilestreamEffectiveLevel') AS NVARCHAR(max)))
        INSERT INTO #summary SELECT 'number of active extENDed event traces',count(*) AS 'cnt' FROM sys.dm_xe_sessions
    END

    IF (@SQLVERSION >= 10050001600) --10.50.1600
    BEGIN
        EXEC sp_executesql N'INSERT INTO #summary SELECT ''possibly running in virtual machine'', virtual_machine_type FROM sys.dm_os_sys_info'
    END

    IF (@SQLVERSION >= 11000002100) --11.0.2100
    BEGIN
        EXEC sp_executesql N'INSERT INTO #summary SELECT ''physical_memory_kb'', physical_memory_kb FROM sys.dm_os_sys_info'
        INSERT INTO #summary VALUES ('HadrManagerStatus', cast (SERVERPROPERTY('HadrManagerStatus') AS NVARCHAR(max)))
        INSERT INTO #summary VALUES ('IsHadrEnabled', cast (SERVERPROPERTY('IsHadrEnabled') AS NVARCHAR(max)))	
    END

    IF (@SQLVERSION >= 14000001000) --14.0.1000.169	- SQL 2017 RTM
    OR (@SQLVERSION BETWEEN 13000004001 AND 13999999999) --13.0.4001.0 - SQL 2016 SP1
    OR (@SQLVERSION BETWEEN 12000006024 AND 12999999999) --12.0.6024.0 - SQL 2014 SP3
    OR (@SQLVERSION BETWEEN 11000007001 AND 11999999999) --11.0.7001 - SQL 2012 SP4
    BEGIN
        EXEC sp_executesql N'INSERT INTO #summary SELECT ''instant_file_initialization_enabled'', instant_file_initialization_enabled FROM sys.dm_server_services WHERE process_id = SERVERPROPERTY(''ProcessID'')'
    END

    IF (@SQLVERSION >= 12000002000) --12.0.2000
    BEGIN
        INSERT INTO #summary VALUES ('IsLocalDB', cast (SERVERPROPERTY('IsLocalDB') AS NVARCHAR(max)))
        INSERT INTO #summary VALUES ('IsXTPSupported', cast (SERVERPROPERTY('IsXTPSupported') AS NVARCHAR(max)))
    END

    RAISERROR ('--ServerProperty--', 0, 1) WITH NOWAIT

    SELECT * FROM #summary
    ORDER BY PropertyName
    DROP TABLE #summary
    PRINT ''

    --GO
    --changing xp_instance_regenumvalues to dmv access as a part of issue #149

    DECLARE @startup table (ArgsName NVARCHAR(10), ArgsValue NVARCHAR(max))
    INSERT INTO @startup 
    SELECT     sReg.value_name,     CAST(sReg.value_data AS NVARCHAR(max))
    FROM sys.dm_server_registry AS sReg
    WHERE     sReg.value_name LIKE N'SQLArg%';

    RAISERROR ('--Startup Parameters--', 0, 1) WITH NOWAIT
    SELECT * FROM @startup

    PRINT ''

    CREATE TABLE #traceflg (TraceFlag INT, Status INT, Global INT, Session INT)
    INSERT INTO #traceflg EXEC ('dbcc tracestatus (-1)')
    PRINT ''
    RAISERROR ('--traceflags--', 0, 1) WITH NOWAIT
    SELECT * FROM #traceflg
    DROP TABLE #traceflg


    PRINT ''
    RAISERROR ('--sys.dm_os_schedulers--', 0, 1) WITH NOWAIT
    SELECT * FROM sys.dm_os_schedulers


    PRINT ''
    RAISERROR ('-- sys.dm_os_loaded_modules --', 0, 1) WITH NOWAIT
            SELECT base_address      , 
                file_version, 
                product_version, 
                debug, 
                patched, 
                prerelease, 
                private_build, 
                special_build, 
                [language], 
                company, 
                [description], 
                [name]
            FROM sys.dm_os_loaded_modules
            PRINT ''


    IF (@SQLVERSION >= 10000001600 --10.0.1600
        and @SQLVERSION < 10050000000) --10.50.0.0
    BEGIN
        PRINT ''
        RAISERROR ('--sys.dm_os_nodes--', 0, 1) WITH NOWAIT
        EXEC sp_executesql N'SELECT node_id, memory_object_address, memory_clerk_address, io_completion_worker_address, memory_node_id, cpu_affinity_mask, online_scheduler_count, idle_scheduler_count active_worker_count, avg_load_balance, timer_task_affinity_mask, permanent_task_affinity_mask, resource_monitor_state, node_state_desc FROM sys.dm_os_nodes'
    END


    IF (@SQLVERSION >= 10050000000) --10.50.0.0
    BEGIN
        PRINT ''
        RAISERROR ('--sys.dm_os_nodes--', 0, 1) WITH NOWAIT
        EXEC sp_executesql N'SELECT node_id, memory_object_address, memory_clerk_address, io_completion_worker_address, memory_node_id, cpu_affinity_mask, online_scheduler_count, idle_scheduler_count active_worker_count, avg_load_balance, timer_task_affinity_mask, permanent_task_affinity_mask, resource_monitor_state, online_scheduler_mask, processor_group, node_state_desc FROM sys.dm_os_nodes'
    END


    PRINT ''
    RAISERROR ('--dm_os_sys_info--', 0, 1) WITH NOWAIT
    SELECT * FROM sys.dm_os_sys_info


    if cast (SERVERPROPERTY('IsClustered') AS INT) = 1
    BEGIN
        PRINT ''
        RAISERROR ('--fn_virtualservernodes--', 0, 1) WITH NOWAIT
        SELECT * FROM fn_virtualservernodes()
    END



    PRINT ''
    RAISERROR ('--sys.configurations--', 0, 1) WITH NOWAIT
    SELECT configuration_id, 
    convert(INT,value) AS 'value', 
    convert(INT,value_in_use) AS 'value_in_use', 
    convert(INT,minimum) AS 'minimum', 
    convert(INT,maximum) AS 'maximum', 
    convert(INT,is_dynamic) AS 'is_dynamic', 
    convert(INT,is_advanced) AS 'is_advanced', 
    name  
    FROM sys.configurations 
    ORDER BY name


    PRINT ''
    RAISERROR ('--database files--', 0, 1) WITH NOWAIT
    SELECT database_id, [file_id], file_guid, [type],  LEFT(type_desc,10) AS 'type_desc', data_space_id, [state], LEFT(state_desc,16) AS 'state_desc', size, max_size, growth,
    is_media_read_only, is_read_only, is_sparse, is_percent_growth, is_name_reserved, create_lsn,  drop_lsn, read_only_lsn, read_write_lsn, differential_base_lsn, differential_base_guid,
    differential_base_time, redo_start_lsn, redo_start_fork_guid, redo_target_lsn, redo_target_fork_guid, backup_lsn, db_name(database_id) AS 'Database_name',  name, physical_name 
    FROM master.sys.master_files ORDER BY database_id, type, file_id

    PRINT ''
    RAISERROR ('-- sysaltfiles--', 0, 1) WITH NOWAIT
    SELECT af.dbid as [dbid],  db_name(af.dbid) as [database_name], fileid, groupid, [size], [maxsize], [growth], [status],rtrim(af.filename) as [filename],rtrim(af.name) as [logical_filename]
    FROM master.sys.sysaltfiles af
    WHERE af.dbid != db_id('tempdb')
    ORDER BY af.dbid,af.fileid

    PRINT ''
    RAISERROR ('--sys.databases_ex--', 0, 1) WITH NOWAIT
    SELECT cast(DATABASEPROPERTYEX (name,'IsAutoCreateStatistics') AS INT) 'IsAutoCreateStatistics', cast( DATABASEPROPERTYEX (name,'IsAutoUpdateStatistics') AS INT) 'IsAutoUpdateStatistics', cast (DATABASEPROPERTYEX (name,'IsAutoCreateStatisticsIncremental') AS INT) 'IsAutoCreateStatisticsIncremental', *  FROM sys.databases

    PRINT ''
    RAISERROR ('-- Windows Group Default Databases other than master --', 0, 1) WITH NOWAIT
    SELECT name,default_database_name FROM sys.server_principals WHERE [type] = 'G' and is_disabled = 0 and default_database_name != 'master'

    --removed AG related dmvs as a part of issue #162
    PRINT ''
    PRINT '-- sys.change_tracking_databases --'
    SELECT database_id,is_auto_cleanup_on,retention_period,retention_period_units,retention_period_units_desc FROM sys.change_tracking_databases


    PRINT ''
    PRINT '-- sys.dm_database_encryption_keys --'
    SELECT database_id, encryption_state FROM sys.dm_database_encryption_keys



    PRINT ''
    IF @SQLVERSION >= 15000002000 --15.0.2000
    BEGIN
        PRINT '-- sys.dm_tran_persistent_version_store_stats --'
        SELECT * FROM sys.dm_tran_persistent_version_store_stats
        PRINT ''
    END


    PRINT '-- sys.certificates --' 
    SELECT
        CONVERT(VARCHAR(64),DB_NAME())  AS [database_name], 
        name,
        certificate_id,
        principal_id,
        pvt_key_encryption_type,
        CONVERT(VARCHAR(32), pvt_key_encryption_type_desc) AS pvt_key_encryption_type_desc,
        is_active_for_begin_dialog,
        CONVERT(VARCHAR(512), issuer_name) AS issuer_name,
        cert_serial_number,
        sid,
        string_sid,
        CONVERT(VARCHAR(512),subject) AS subject,
        expiry_date,
        start_date,
        '0x' + CONVERT(VARCHAR(64),thumbprint,2) AS thumbprint,
        CONVERT(VARCHAR(256), attested_by) AS attested_by,
        pvt_key_last_backup_date,
        key_length
    FROM master.sys.certificates 
    PRINT ''


    PRINT '-- sys.servers --'
    SELECT [server_id]
      ,[name]
      ,[product]
      ,[provider]
      ,CONVERT(VARCHAR(512),[data_source]) AS [data_source]
      ,CONVERT(VARCHAR(512),[location]) AS [location]
      ,CONVERT(VARCHAR(512),[provider_string]) AS [provider_string]
      ,[catalog]
      ,[connect_timeout]
      ,[query_timeout]
      ,[is_linked]
      ,[is_remote_login_enabled]
      ,[is_rpc_out_enabled]
      ,[is_data_access_enabled]
      ,[is_collation_compatible]
      ,[uses_remote_collation]
      ,[collation_name]
      ,[lazy_schema_validation]
      ,[is_system]
      ,[is_publisher]
      ,[is_subscriber]
      ,[is_distributor]
      ,[is_nonsql_subscriber]
      ,[is_remote_proc_transaction_promotion_enabled]
      ,[modify_date]
    FROM [master].[sys].[servers]
    PRINT '' 

    --this proc is only present in SQL Server 2019 and later but seems not present in early builds
    IF OBJECT_ID('sys.sp_certificate_issuers') IS NOT NULL
    BEGIN

        CREATE TABLE #certificate_issuers(
                certificateid INT,
                dnsname NVARCHAR(128) )

        INSERT INTO #certificate_issuers
        EXEC ('EXEC sys.sp_certificate_issuers')

        PRINT '-- sys_sp_certificate_issuers --'
        
        SELECT certificateid, dnsname 
        FROM #certificate_issuers

        DROP TABLE #certificate_issuers
    END
    PRINT ''
    PRINT ''


    -- Collect db_log_info to check for VLF issues
    --this table to be used by older versions of SQL Server prior to 2016 SP2
    CREATE TABLE #dbcc_loginfo_cur_db
    (
        RecoveryUnitId INT,
        FileId      INT,
        FileSize    BIGINT,
        StartOffset  BIGINT,
        FSeqNo      BIGINT,
        Status      INT,
        Parity		INT,
        CreateLSN	NVARCHAR(48)
    )
    --this table contains all the results
    CREATE TABLE #loginfo_all_dbs
    (
        database_id	INT,
        [database_name] VARCHAR(64),
        vlf_count INT,
        vlf_avg_size_mb	DECIMAL(10,2),
        vlf_min_size_mb DECIMAL(10,2),
        vlf_max_size_mb DECIMAL(10,2),
        vlf_status INT,
        vlf_active BIT
    )

    DECLARE @dbname NVARCHAR(64), @dbid INT
    DECLARE @dbcc_log_info VARCHAR(MAX)

    DECLARE Database_Cursor CURSOR FOR SELECT database_id, name FROM master.sys.databases

    OPEN Database_Cursor;

    FETCH NEXT FROM Database_Cursor INTO @dbid, @dbname;

    WHILE @@FETCH_STATUS = 0
        BEGIN

            SET @dbcc_log_info = 'DBCC LOGINFO (''' + @dbname + ''') WITH NO_INFOMSGS'

            IF ((@SQLVERSION >= 14000001000) --14.0.1000
              OR (@SQLVERSION >= 13000005026 )) --13.0.5026.0 - SQL 2016 SP2
            BEGIN
            
                INSERT INTO #loginfo_all_dbs(
                    database_id	,
                    database_name ,
                    vlf_count,
                    vlf_avg_size_mb	,
                    vlf_min_size_mb,
                    vlf_max_size_mb,
                    vlf_status ,
                    vlf_active)
                SELECT 
                    database_id,
                    @dbname,
                    count(*) AS vlf_count,
                    AVG(vlf_size_mb) AS vlf_avg_size_mb,
                    MIN(vlf_size_mb) AS vlf_min_size_mb,
                    MAX(vlf_size_mb) AS vlf_max_size_mb,
                    vlf_status,
                    vlf_active
                FROM sys.dm_db_log_info (db_id(@dbname))
                GROUP BY database_id, vlf_status, vlf_active

            END
            ELSE
            --if version is prior to SQL 2016 SP2, use DBCC LOGINFO to get the data
            --but insert and format it into a table as if it came from sys.dm_db_log_info
            BEGIN
                INSERT INTO #dbcc_loginfo_cur_db (
                    RecoveryUnitId ,
                    FileId      ,
                    FileSize    ,
                    StartOffset ,
                    FSeqNo      ,
                    Status      ,
                    Parity		,
                    CreateLSN)
                EXEC(@dbcc_log_info)

                
                INSERT INTO #loginfo_all_dbs(
                    database_id	,
                    database_name ,
                    vlf_count ,
                    vlf_avg_size_mb	,
                    vlf_min_size_mb,
                    vlf_max_size_mb,
                    vlf_status ,
                    vlf_active )
            --do the formatting to match the sys.dm_db_log_info standard as much as possible	
                SELECT 
                    @dbid, 
                    @dbname, 
                    COUNT(li.FSeqNo) AS vlf_count,
                    CONVERT(DECIMAL(10,2),AVG(li.FileSize/1024/1024.0)) AS vlf_avg_size_mb,
                    CONVERT(DECIMAL(10,2),MIN(li.FileSize/1024/1024.0)) AS vlf_min_size_mb,
                    CONVERT(DECIMAL(10,2),MAX(li.FileSize/1024/1024.0)) AS vlf_max_size_mb,
                    li.Status,
                    CASE WHEN li.Status = 2 THEN 1 ELSE 0 END AS Active
                FROM #dbcc_loginfo_cur_db li
                GROUP BY Status, CASE WHEN li.Status = 2 THEN 1 ELSE 0 END 

                --clean up the temp table for next loop
                TRUNCATE TABLE #dbcc_loginfo_cur_db
            END

            FETCH NEXT FROM Database_Cursor INTO @dbid, @dbname;

        END;
    CLOSE Database_Cursor;
    DEALLOCATE Database_Cursor;

    PRINT '-- sys_dm_db_log_info --'
    SELECT 
        database_id	,
        database_name ,
        vlf_count ,
        vlf_avg_size_mb	,
        vlf_min_size_mb	,
        vlf_max_size_mb	,
        vlf_status ,
        vlf_active 
    FROM #loginfo_all_dbs
    ORDER BY database_name


    DROP TABLE #dbcc_loginfo_cur_db
    DROP TABLE #loginfo_all_dbs
    PRINT ''

    PRINT '-- sql_agent_jobs_information --'; 
WITH LastExecution AS (
    SELECT ROW_NUMBER() OVER (PARTITION  BY job_id ORDER BY run_date DESC, run_time  DESC) as id,
	       job_id,
	       run_date,
		   run_time,
		   run_status
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
    )
    SELECT sj.name AS JobName, 
        CASE sj.enabled 
         WHEN 1 THEN 'Yes'
         ELSE 'No'
        END AS IsEnabled,
        CASE ss.enabled
         WHEN 1 THEN 'Yes'
         ELSE 'No'
        END AS ScheduleEnabled,
        CASE ss.freq_type
         WHEN 1 THEN 'Once'
         WHEN 4 THEN 'Daily'
         WHEN 8 THEN 'Weekly'
         WHEN 16 THEN 'Monthly'
         WHEN 32 THEN 'Monthly - Interval Related' 
         WHEN 64 THEN 'When Agent Starts'
         WHEN 128 THEN 'When Computer is Idle'
        END AS Frequency, 
        CASE ss.freq_subday_type
         WHEN 0 THEN 'N/A'
         WHEN 1 THEN 'Specific Time'
         WHEN 2 THEN 'Seconds'
         WHEN 4 THEN 'Minutes'
         WHEN 8 THEN 'Hours'
        END AS IntervalType,
        CASE
         WHEN ss.freq_subday_type = 1 THEN LEFT(STUFF(STUFF(STUFF(CONVERT(VARCHAR(6), active_start_time), 1, 0,
                                          REPLICATE('0', 6 - LEN(CONVERT(VARCHAR(6), active_start_time)))), 3, 0, ':'), 6, 0, ':'), 12)
         ELSE 'N/A'
        END AS ExecutionTime,
        CASE 
         WHEN ss.freq_type = 1 THEN 'N/A'
         WHEN ss.freq_type = 64 THEN 'N/A'
         WHEN ss.freq_type = 16 THEN 'N/A'
         WHEN ss.freq_type = 4 THEN 'Every ' + CONVERT(VARCHAR(10), ss.freq_relative_interval) + ' day(s)' 
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 1 THEN 'Sunday' 
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 2 THEN 'Monday' 
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 4 THEN 'Tuesday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 8 THEN 'Wednesday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 16 THEN 'Thursday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 32 THEN 'Friday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 62 THEN 'Monday to Saturday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 64 THEN 'Saturday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 65 THEN 'Saturday, Sunday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 124 THEN 'Tuesday to Sunday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 126 THEN 'Monday to Sunday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 127 THEN 'Monday to Sunday (All days)'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 9 THEN 'Wednesday, Sunday'
         WHEN ss.freq_type = 8 AND ss.freq_relative_interval = 95 THEN 'Monday, Tuesday, Wednesday, Thursday, Saturday, Sunday'
         WHEN ss.freq_type = 8 THEN 'Every ' + CONVERT(VARCHAR(20), ss.freq_recurrence_factor) + ' Week'
         WHEN ss.freq_type = 16 THEN 'Every ' + CONVERT(VARCHAR(20), ss.freq_recurrence_factor) + ' Month'
         WHEN ss.freq_type = 32 THEN 'Every ' + CONVERT(VARCHAR(20), ss.freq_recurrence_factor) + ' Month'
         ELSE 'N/A'
        END AS Interval,
        CASE
         WHEN ss.freq_subday_type = 1 THEN 'N/A'
         WHEN ss.freq_subday_type = 2 THEN 'Every ' + CONVERT(VARCHAR(20), ss.freq_subday_interval) + ' second(s)'
         WHEN ss.freq_subday_type = 4 THEN 'Every ' + CONVERT(VARCHAR(20), ss.freq_subday_interval) + ' minute(s)'
         WHEN ss.freq_subday_type = 8 THEN 'Every ' + CONVERT(VARCHAR(20), ss.freq_subday_interval) + ' hour(s)'
         ELSE 'N/A'
        END AS DayInterval,
        CASE 
         WHEN ss.freq_type = 16 THEN CONVERT(VARCHAR(2), ss.freq_relative_interval)
         WHEN ss.freq_type = 32 AND ss.freq_interval = 1 AND ss.freq_relative_interval = 1 THEN 'First Sunday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 2 AND ss.freq_relative_interval = 1 THEN 'First Monday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 3 AND ss.freq_relative_interval = 1 THEN 'First Tuesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 4 AND ss.freq_relative_interval = 1 THEN 'First Wednesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 5 AND ss.freq_relative_interval = 1 THEN 'First Thursday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 6 AND ss.freq_relative_interval = 1 THEN 'First Friday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 7 AND ss.freq_relative_interval = 1 THEN 'First Saturday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 8 AND ss.freq_relative_interval = 1 THEN 'First day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 9 AND ss.freq_relative_interval = 1 THEN 'First weekday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 10 AND ss.freq_relative_interval = 1 THEN 'First weekend day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 1 AND ss.freq_relative_interval = 2 THEN 'Second Sunday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 2 AND ss.freq_relative_interval = 2 THEN 'Second Monday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 3 AND ss.freq_relative_interval = 2 THEN 'Second Tuesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 4 AND ss.freq_relative_interval = 2 THEN 'Second Wednesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 5 AND ss.freq_relative_interval = 2 THEN 'Second Thursday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 6 AND ss.freq_relative_interval = 2 THEN 'Second Friday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 7 AND ss.freq_relative_interval = 2 THEN 'Second Saturday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 8 AND ss.freq_relative_interval = 2 THEN 'Second day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 9 AND ss.freq_relative_interval = 2 THEN 'Second weekday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 10 AND ss.freq_relative_interval = 2 THEN 'Second weekend day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 1 AND ss.freq_relative_interval = 4 THEN 'Third Sunday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 2 AND ss.freq_relative_interval = 4 THEN 'Third Monday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 3 AND ss.freq_relative_interval = 4 THEN 'Third Tuesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 4 AND ss.freq_relative_interval = 4 THEN 'Third Wednesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 5 AND ss.freq_relative_interval = 4 THEN 'Third Thursday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 6 AND ss.freq_relative_interval = 4 THEN 'Third Friday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 7 AND ss.freq_relative_interval = 4 THEN 'Third Saturday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 8 AND ss.freq_relative_interval = 4 THEN 'Third day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 9 AND ss.freq_relative_interval = 4 THEN 'Third weekday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 10 AND ss.freq_relative_interval = 4 THEN 'Third weekend day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 1 AND ss.freq_relative_interval = 8 THEN 'Fourth Sunday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 2 AND ss.freq_relative_interval = 8 THEN 'Fourth Monday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 3 AND ss.freq_relative_interval = 8 THEN 'Fourth Tuesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 4 AND ss.freq_relative_interval = 8 THEN 'Fourth Wednesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 5 AND ss.freq_relative_interval = 8 THEN 'Fourth Thursday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 6 AND ss.freq_relative_interval = 8 THEN 'Fourth Friday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 7 AND ss.freq_relative_interval = 8 THEN 'Fourth Saturday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 8 AND ss.freq_relative_interval = 8 THEN 'Fourth day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 9 AND ss.freq_relative_interval = 8 THEN 'Fourth weekday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 10 AND ss.freq_relative_interval = 8 THEN 'Fourth weekend day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 1 AND ss.freq_relative_interval = 16 THEN 'Last Sunday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 2 AND ss.freq_relative_interval = 16 THEN 'Last Monday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 3 AND ss.freq_relative_interval = 16 THEN 'Last Tuesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 4 AND ss.freq_relative_interval = 16 THEN 'Last Wednesday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 5 AND ss.freq_relative_interval = 16 THEN 'Last Thursday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 6 AND ss.freq_relative_interval = 16 THEN 'Last Friday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 7 AND ss.freq_relative_interval = 16 THEN 'Last Saturday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 8 AND ss.freq_relative_interval = 16 THEN 'Last day of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 9 AND ss.freq_relative_interval = 16 THEN 'Last weekday of every month'
         WHEN ss.freq_type = 32 AND ss.freq_interval = 10 AND ss.freq_relative_interval = 16 THEN 'Last weekend day of every month'
         ELSE 'N/A'
        END AS MonthDay,      
        CONVERT(VARCHAR(10), CONVERT(DATETIME, CONVERT(VARCHAR(10), active_start_date)), 126) AS StartDate,
        CONVERT(VARCHAR(10), CONVERT(DATETIME, CONVERT(VARCHAR(10), active_end_date)), 126) AS EndDate,
        LEFT(STUFF(STUFF(STUFF(CONVERT(VARCHAR(6), active_start_time), 1, 0, REPLICATE('0', 6 - LEN(CONVERT(VARCHAR(6), active_start_time)))), 3, 0, ':'), 6, 0, ':'), 12) AS StartTime,
        LEFT(STUFF(STUFF(STUFF(CONVERT(VARCHAR(6), active_end_time), 1, 0, REPLICATE('0', 6 - LEN(CONVERT(VARCHAR(6), active_end_time)))), 3, 0, ':'), 6, 0, ':'), 12) AS EndTime,
        CASE le.run_status
           WHEN 0 THEN 'Failed'
           WHEN 1 THEN 'Succeeded'
           WHEN 2 THEN 'Retry'
           WHEN 3 THEN 'Canceled'
           WHEN 4 THEN 'In Progress'
		   ELSE 'Unknown'
       END as LastExecutionStatus,
		CONVERT(date, CONVERT(varchar(10), le.run_date)) AS LastExecutionDate,
        STUFF(STUFF(RIGHT('000000' + CAST(le.run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS LastExecutionTime
    FROM msdb..sysjobs sj
    LEFT OUTER JOIN msdb..sysjobschedules sjs 
        ON (sj.job_id = sjs.job_id)
    LEFT OUTER JOIN msdb..sysschedules ss 
        ON (sjs.schedule_id = ss.schedule_id)
    LEFT OUTER JOIN LastExecution le 
        ON sj.job_id = le.job_id AND
		   le.id = 1
    ORDER BY sj.name
    OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1);

    PRINT ''
    PRINT '-- sql_agent_job_history --'
    SELECT 
        j.name AS job_name,
        h.job_id,
        h.step_id,
        h.step_name,
        h.sql_message_id,
        h.sql_severity,
        h.message,
        h.run_status,
        h.run_date,
        h.run_time,
        h.run_duration,
        h.operator_id_emailed,
        h.operator_id_netsent,
        h.operator_id_paged,
        h.retries_attempted,
        h.server,
        h.instance_id
    FROM (
        SELECT TOP 1000 *
        FROM (
            SELECT *,
                ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
            FROM msdb.dbo.sysjobhistory
        ) AS JobHistory
        WHERE rn <= 100
    ) AS h
    JOIN msdb.dbo.sysjobs AS j
    ON h.job_id = j.job_id
    ORDER BY h.run_date DESC, h.run_time DESC;

    PRINT ''
    PRINT '-- sys.dm_clr_appdomains --'
    SELECT TOP 1000 
        appdomain_address,
        appdomain_id,
        LEFT(appdomain_name, 80) AS appdomain_name,
        creation_time,
        db_id,
        user_id,
        LEFT(state, 48) AS state,
        strong_refcount,
        weak_refcount,
        cost,
        value,
        compatibility_level,
        total_processor_time_ms,
        total_allocated_memory_kb,
        survived_memory_kb
    FROM sys.dm_clr_appdomains
    IF @@ROWCOUNT >= 1000 PRINT '<<<<< LIMIT OF 1000 ROWS EXCEEDED, SOME RESULTS NOT SHOWN >>>>>'
    PRINT ''
    
    PRINT '-- sys.dm_clr_loaded_assemblies --'
    SELECT TOP 1000 
        assembly_id,         
        appdomain_address,   
        load_time
    FROM sys.dm_clr_loaded_assemblies
    IF @@rowcount >= 1000 PRINT '<<<<< LIMIT OF 1000 ROWS EXCEEDED, SOME RESULTS NOT SHOWN >>>>>'
    PRINT ''


    PRINT '-- sys.dm_clr_tasks --'
    SELECT TOP 1000
        task_address,
        sos_task_address,
        appdomain_address,
        LEFT(state,64) AS state,   
        LEFT(abort_state,64) AS abort_state,
        LEFT(type,64) AS type,         
        affinity_count,
        forced_yield_count
    FROM sys.dm_clr_tasks
    IF @@rowcount >= 1000 PRINT '<<<<< LIMIT OF 1000 ROWS EXCEEDED, SOME RESULTS NOT SHOWN >>>>>'
    PRINT ''

 	-- Create temporary tables to store the results for sys.assemblies, sys.assembly_modules, and sys.assembly_types
    CREATE TABLE #assemblies (
        database_name NVARCHAR(128),
        name SYSNAME NULL,
        assembly_id INT,
        principal_id INT,
        clr_name NVARCHAR(512) NULL,
        permission_set TINYINT NULL,
        permission_set_desc NVARCHAR(128) NULL,
        is_visible BIT,
        create_date DATETIME,
        modify_date DATETIME,
        is_user_defined BIT  NULL
    );

    CREATE TABLE #assembly_modules (
        database_name NVARCHAR(128),
        object_id INT,
        assembly_id INT,
        assembly_class NVARCHAR(256) NULL,
        assembly_method NVARCHAR(256) NULL,
        null_on_null_input BIT NULL,
        execute_as_principal_id INT  NULL
    );

    CREATE TABLE #assembly_types (
        database_name NVARCHAR(128),
        name SYSNAME,
        system_type_id TINYINT,
        user_type_id INT,
        schema_id INT,
        principal_id INT NULL,
        max_length SMALLINT,
        precision TINYINT,
        scale TINYINT,
        collation_name SYSNAME NULL,
        is_nullable BIT NULL,
        is_user_defined BIT,
        is_assembly_type BIT,
        default_object_id INT,
        rule_object_id INT,
        assembly_id INT,
        assembly_class NVARCHAR(256) NULL,
        is_binary_ordered BIT NULL,
        is_fixed_length BIT NULL,
        prog_id NVARCHAR(80) NULL,
        assembly_qualified_name NVARCHAR(512) NULL,
        is_table_type BIT
    );

    -- Declare a variable to store the database name
    DECLARE @database_name NVARCHAR(128);

    -- Declare a table variable to store the list of databases
    DECLARE @databases TABLE (database_name NVARCHAR(128));

    -- Insert the list of databases into the table variable
    INSERT INTO @databases (database_name)
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE' AND name NOT IN ('master', 'tempdb', 'model', 'msdb');

    -- Loop through each database and insert the assemblies, assembly modules, and assembly types into the temporary tables
    WHILE EXISTS (SELECT 1 FROM @databases)
    BEGIN
        -- Get the next database name
        SELECT TOP 1 @database_name = database_name
        FROM @databases;

        IF HAS_PERMS_BY_NAME(@database_name, 'DATABASE', 'CONNECT') = 1
	    BEGIN

          -- Construct the dynamic SQL to insert the assemblies into the temporary table
          DECLARE @SQLTxt NVARCHAR(MAX) = '
              INSERT INTO #assemblies (database_name, assembly_id, name, principal_id, clr_name, permission_set, permission_set_desc, is_visible, create_date, modify_date, is_user_defined)
              SELECT ''' + @database_name + ''', assembly_id, name, principal_id, clr_name, permission_set, permission_set_desc, is_visible, create_date, modify_date, is_user_defined
              FROM ' + QUOTENAME(@database_name) + '.sys.assemblies
              WHERE assembly_id <> 1';
  
          EXEC sp_executesql @SQLTxt;
  
          -- Construct the dynamic SQL to insert the assembly modules into the temporary table
          SET @SQLTxt = '
              INSERT INTO #assembly_modules (database_name, object_id, assembly_id, assembly_class, assembly_method, null_on_null_input, execute_as_principal_id)
              SELECT ''' + @database_name + ''', object_id, assembly_id, assembly_class, assembly_method, null_on_null_input, execute_as_principal_id
              FROM ' + QUOTENAME(@database_name) + '.sys.assembly_modules';
  
          EXEC sp_executesql @SQLTxt;
  
          -- Construct the dynamic SQL to insert the assembly types into the temporary table
          SET @SQLTxt = '
              INSERT INTO #assembly_types (database_name, name, system_type_id, user_type_id, schema_id, principal_id, max_length, precision, scale, collation_name, is_nullable, is_user_defined, is_assembly_type, default_object_id, rule_object_id, assembly_id, assembly_class, is_binary_ordered, is_fixed_length, prog_id, assembly_qualified_name, is_table_type)
              SELECT ''' + @database_name + ''', name, system_type_id, user_type_id, schema_id, principal_id, max_length, precision, scale, collation_name, is_nullable, is_user_defined, is_assembly_type, default_object_id, rule_object_id, assembly_id, assembly_class, is_binary_ordered, is_fixed_length, prog_id, assembly_qualified_name, is_table_type
              FROM ' + QUOTENAME(@database_name) + '.sys.assembly_types
              WHERE schema_id <> SCHEMA_ID(''sys'')';
  
          EXEC sp_executesql @SQLTxt;
        
        END;
        
          -- Remove the processed database from the table variable
          DELETE FROM @databases
          WHERE database_name = @database_name;
        
    END;

    -- Select the results from the temporary tables
    PRINT '-- sys.assemblies --'
    SELECT * FROM #assemblies;
    PRINT ''

    PRINT '-- sys.assembly_modules --'
    SELECT * FROM #assembly_modules;
    PRINT ''

    PRINT '-- sys.assembly_types --'
    SELECT * FROM #assembly_types;
    PRINT ''

    -- Drop the temporary tables
    DROP TABLE #assemblies;
    DROP TABLE #assembly_modules;
    DROP TABLE #assembly_types;

    PRINT ''

    IF OBJECT_ID ('sys.database_scoped_configurations') IS NOT NULL
	BEGIN

      PRINT '-- sys.database_scoped_configurations --'
  
	  DECLARE @database_id INT
	  DECLARE @cont INT
	  DECLARE @maxcont INT
	  DECLARE @is_value_default BIT
      DECLARE @sql NVARCHAR(MAX)

	  DECLARE @dbtable TABLE (
	  id INT IDENTITY (1,1) PRIMARY KEY,
	  database_id INT,
	  dbname SYSNAME
	  )
	  
	  INSERT INTO @dbtable
	  SELECT database_id, name FROM sys.databases WHERE state_desc='ONLINE' AND name NOT IN ('model','tempdb') ORDER BY name
	  
	  SET @cont = 1
	  SET @maxcont = (SELECT MAX(id) FROM @dbtable)
     
      --create the schema
	  SELECT  @database_id as database_id , @dbname as dbname, configuration_id, name, value, value_for_secondary, @is_value_default AS is_value_default 
	  INTO #db_scoped_config
	  FROM sys.database_scoped_configurations
	  WHERE 1=0
	  
	  --insert from all databases
	  WHILE (@cont<=@maxcont)
	  BEGIN
	    BEGIN TRY
	      
          SELECT @database_id = database_id,
	    	     @dbname = dbname 
	      FROM @dbtable
	      WHERE id = @cont
	      
          IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
	      BEGIN
	      
            IF (@SQLVERSION >= 14000001000) --14.0.1000
	        BEGIN
	          SET @sql = ' INSERT INTO #db_scoped_config SELECT ' + CONVERT(VARCHAR,@database_id) + ',''' + @dbname + ''', configuration_id, name, value, value_for_secondary, is_value_default FROM [' + @dbname + '].sys.database_scoped_configurations'
	        END
	        
            ELSE
	        BEGIN
	        	SET @sql = ' INSERT INTO #db_scoped_config SELECT ' + CONVERT(VARCHAR,@database_id) + ',''' + @dbname + ''', configuration_id, name, value, value_for_secondary, NULL FROM [' + @dbname + '].sys.database_scoped_configurations'
	        END
	    	--PRINT @sql
	    	EXEC (@sql)
	      END
	      
          SET @cont = @cont + 1
	    
	    END TRY
	    
        BEGIN CATCH
	    	PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	    	PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
	    	
            -- Increment the counter to avoid infinite loop. 
            SET @cont = @cont + 1
	    END CATCH

	  END
	  		
	  SELECT 
	  	database_id, 
	  	CONVERT(VARCHAR(48), dbname) AS dbname, 
	  	configuration_id, 
	  	name, 
	  	CONVERT(VARCHAR(256), value) AS value, 
	  	CONVERT(VARCHAR(256),value_for_secondary) AS value_for_secondary, 
	  	is_value_default 
	  FROM #db_scoped_config
	
    END

    IF (@SQLVERSION >= 17000000925) --17.0.925.4 [SQL Server 2025 RC1]
    BEGIN
        PRINT ''
        RAISERROR ('-- sys.dm_os_memory_health_history --', 0, 1) WITH NOWAIT
        EXEC sp_executesql N'SELECT snapshot_time,severity_level,severity_level_desc,allocation_potential_memory_mb,reclaimable_cache_memory_mb,clerk_type,pages_allocated_kb,out_of_memory_event_count,memgrant_timeout_count,memgrant_waiter_count FROM sys.dm_os_memory_health_history CROSS APPLY OPENJSON(top_memory_clerks) WITH (clerk_type sysname ''$.clerk_type'',pages_allocated_kb bigint ''$.pages_allocated_kb'') ORDER BY snapshot_time DESC, pages_allocated_kb DESC'

    END

    PRINT ''
    RAISERROR ('-- Script End --', 0, 1) WITH NOWAIT
    PRINT 'Script End Time        ' + CONVERT (VARCHAR(30), GETDATE(), 126) 
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA5o/GXvzVfsrWS
# Ai0oRfCtpL3XGrBZcO45SkmeBeU7kKCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIIFsDgQatoMX
# UlfIxZ6rzi64YwnJV+2gUnZigNAs/oILMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAX4HpEpp/TTxWTkxMxAu3mAHrP1cvpEbpJFoQ/KaVZzm8
# QYOeMHQILxBoGyuW8IGdpDt1qdbAVCAuvaz7BSPcuT9pO9zoTwfTgoDAjjpy2ehF
# gj8vq+wgACq5tfbA1ifBTAKcpGPgKWc7L704xoxBqWY9MphhLm/5Mkl7ebsPWiWv
# +9Z55kYpeXZRxiiCoa9dAlWnNiX6z3yKCYjc9Npun3tO5cAUim5Q2/0xyabxIdZ9
# R5cpfRUH6pjBwU9Ab6Ql77oFZn+j+sTc5M0coNBPlBGHN15XB2SMI8m3Gq4oUhuN
# CIitHoqWyKZayV50N6UafovGBjIoID8aqsj25RNK56GCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCAXuCe7YjYha7OsnuiYtXdwxkbPsMjaoLvJ8AH9HdVI
# tAIGaXSr3pISGBMyMDI2MDIwNDE2MzUyOC43MzhaMASAAgH0oIHZpIHWMIHTMQsw
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
# IgQgyb228wgkcklQ0xUr7AZD/cgp2w9Hcpz3pyuyNh+L5U4wgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCBwEPR2PDrTFLcrtQsKrUi7oz5JNRCF/KRHMihSNe7s
# ijCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACFRgD
# 04EHJnxTAAEAAAIVMCIEIAy84l0FlIwqrldfB3TmTArja2bSHILWYvHOj9pAXLHS
# MA0GCSqGSIb3DQEBCwUABIICAJuN+ZCvfOuhhKszM3jOp0ptdbR/I+OPyy5xa+/U
# KE5/cWFnmCVMkmeZQsrgAtJMPYqU+XIdh7gfDZ5OHJoLQ1dRHzGykp2wwkG0cd14
# OzrY709BnJzBz4ve7Z6VHSW1WZHlMXDIzSPrM7ndhNBiFFGh4UDoh4y9SOC1Ikl1
# UebiEPCZm2xURq2jzR4KtnjDTtv1/znTyu7mnI13A9qIC8at18g2ZNhgy//TtuQc
# JacxbxEV3FMMpAD4VB/MKYQ0pwIVPw2BAUaKFXGyvdKEFli6c/TTQc26qhtq8H8i
# HMUppLEwPwq0v53RafqNoBA694niIxDgr1NU8jUwd8inSSse0HSpNmuCuZdX5Ncb
# JOIvL1Yt7irQuVNoNd+DLl4r0xIJWQQ+uD41/OY78WhVteywkO9uEzeEXPZzpxFs
# cNp4IsLQGSeOBaSWwDccPmKAQr8eqSHjb/KQsS1DN0jvVN0osJCtyLZ8lIwswiwA
# +KYatvq69Mm49YfefuSJj4XDApOM52WKJYAErCZvf1pkkvS8CdgOtCjKKhIxOO3G
# 9fjkpV+TR78hG5YKcse21sRfIajn++w2vc9d6KYgBVG55miBHfLiDvGn6OKid/5Y
# xHceMVx27gOdqjaKqd3rEQQ3Eu9OatSHS1/YR1FLewNE4VfWzGm9N5971k91pGkR
# 04X4
# SIG # End signature block
