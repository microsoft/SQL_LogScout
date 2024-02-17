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
PRINT 'Script File Name         $File: MiscDiagInfo.sql $'
PRINT 'Revision                 $Revision: 1 $ ($Change: ? $)'
PRINT 'Last Modified            $Date: 2023/12/06 12:04:00 EST $'
PRINT 'Script Begin Time        ' + CONVERT (VARCHAR(30), GETDATE(), 126) 
PRINT 'Current Database         ' + DB_NAME()
PRINT ''


DECLARE @sql_major_version INT, @sql_major_build INT, @sql NVARCHAR(max), @sql_minor_version INT
SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 4) AS INT)),
       @sql_major_build = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) AS INT)) ,
	   @sql_minor_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 3) AS INT))

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
    INSERT INTO #summary SELECT 'instant_file_initialization_enabled', instant_file_initialization_enabled FROM sys.dm_server_services WHERE process_id = SERVERPROPERTY('ProcessID')
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
SELECT af.dbid as [dbid],  db_name(af.dbid) as [database_name], fileid, groupid, [size], [maxsize], [growth], [status],rtrim(af.filename) as [filename],rtrim(af.name) as [filename]
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
SELECT * FROM sys.change_tracking_databases


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
	pvt_key_last_backup_date
FROM master.sys.certificates 
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

DECLARE Database_Cursor CURSOR FOR SELECT database_id, name FROM MASTER.sys.databases

OPEN Database_Cursor;

FETCH NEXT FROM Database_Cursor INTO @dbid, @dbname;

WHILE @@FETCH_STATUS = 0
	BEGIN

		SET @dbcc_log_info = 'DBCC LOGINFO (''' + @dbname + ''') WITH NO_INFOMSGS'
		
		IF ((@sql_major_version >= 14) or (@sql_major_version >= 13) and (@sql_major_build >= 5026 ))
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

