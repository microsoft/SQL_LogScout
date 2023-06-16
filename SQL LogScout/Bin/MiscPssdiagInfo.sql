set nocount on
go
print ''
RAISERROR ('-- DiagInfo --', 0, 1) WITH NOWAIT
select 1001 as 'DiagVersion', '2015-01-09' as 'DiagDate'
print ''
go
print 'Script Version = 1001'
print ''
go
SET LANGUAGE us_english
PRINT '-- Script and Environment Details --'
PRINT 'Name                     Value'
PRINT '------------------------ ---------------------------------------------------'
PRINT 'Script Name              Misc Pssdiag Info'
PRINT 'Script File Name         $File: MiscPssdiagInfo.sql $'
PRINT 'Revision                 $Revision: 1 $ ($Change: ? $)'
PRINT 'Last Modified            $Date: 2015/01/26 12:04:00 EST $'
PRINT 'Script Begin Time        ' + CONVERT (varchar(30), GETDATE(), 126) 
PRINT 'Current Database         ' + DB_NAME()
PRINT ''
GO

DECLARE @sql_major_version INT, @sql_major_build INT, @sql NVARCHAR(max)
SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT)),
       @sql_major_build = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT)) 

create table #summary (PropertyName nvarchar(50) primary key, PropertyValue nvarchar(256))
insert into #summary values ('ProductVersion', cast (SERVERPROPERTY('ProductVersion') as nvarchar(max)))
insert into #summary values ('MajorVersion', LEFT(CONVERT(SYSNAME,SERVERPROPERTY('ProductVersion')), CHARINDEX('.', CONVERT(SYSNAME,SERVERPROPERTY('ProductVersion')), 0)-1))
insert into #summary values ('IsClustered', cast (SERVERPROPERTY('IsClustered') as nvarchar(max)))
insert into #summary values ('Edition', cast (SERVERPROPERTY('Edition') as nvarchar(max)))
insert into #summary values ('InstanceName', cast (SERVERPROPERTY('InstanceName') as nvarchar(max)))
insert into #summary values ('SQLServerName', @@SERVERNAME)
insert into #summary values ('MachineName', cast (SERVERPROPERTY('MachineName') as nvarchar(max)))
insert into #summary values ('ProcessID', cast (SERVERPROPERTY('ProcessID') as nvarchar(max)))
insert into #summary values ('ResourceVersion', cast (SERVERPROPERTY('ResourceVersion') as nvarchar(max)))
insert into #summary values ('ServerName', cast (SERVERPROPERTY('ServerName') as nvarchar(max)))
insert into #summary values ('ComputerNamePhysicalNetBIOS', cast (SERVERPROPERTY('ComputerNamePhysicalNetBIOS') as nvarchar(max)))
insert into #summary values ('BuildClrVersion', cast (SERVERPROPERTY('BuildClrVersion') as nvarchar(max)))
insert into #summary values ('IsFullTextInstalled', cast (SERVERPROPERTY('IsFullTextInstalled') as nvarchar(max)))
insert into #summary values ('IsIntegratedSecurityOnly', cast (SERVERPROPERTY('IsIntegratedSecurityOnly') as nvarchar(max)))
insert into #summary values ('ProductLevel', cast (SERVERPROPERTY('ProductLevel') as nvarchar(max)))
insert into #summary values ('suser_name()', cast (SUSER_NAME() as nvarchar(max)))

insert into #summary select 'number of visible schedulers', count (*) 'cnt' from sys.dm_os_schedulers where status = 'VISIBLE ONLINE'
insert into #summary select 'number of visible numa nodes', count (distinct parent_node_id) 'cnt' from sys.dm_os_schedulers where status = 'VISIBLE ONLINE'
insert into #summary select 'cpu_count', cpu_count from sys.dm_os_sys_info
insert into #summary select 'hyperthread_ratio', hyperthread_ratio from sys.dm_os_sys_info
insert into #summary select 'machine start time', convert(varchar(23),dateadd(SECOND, -ms_ticks/1000, GETDATE()),121) from sys.dm_os_sys_info
insert into #summary select 'number of tempdb data files', count (*) 'cnt' from master.sys.master_files where database_id = 2 and [type] = 0
insert into #summary select 'number of active profiler traces',count(*) 'cnt' from ::fn_trace_getinfo(0) where property = 5 and convert(tinyint,value) = 1
insert into #summary select 'suser_name() default database name',default_database_name from sys.server_principals where name = SUSER_NAME()

insert into #summary select  'VISIBLEONLINE_SCHEDULER_COUNT' PropertyName, count (*) PropertValue from sys.dm_os_schedulers where status='VISIBLE ONLINE'
insert into #summary select 'UTCOffset_in_Hours' PropertyName, cast( datediff (MINUTE, getutcdate(), getdate()) / 60.0 as decimal(10,2)) PropertyValue


declare @cpu_ticks bigint
select @cpu_ticks = cpu_ticks from sys.dm_os_sys_info
waitfor delay '0:0:2'
select @cpu_ticks = cpu_ticks - @cpu_ticks from sys.dm_os_sys_info

insert into #summary values ('cpu_ticks_per_sec', @cpu_ticks / 2 )

PRINT ''

GO

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
 

IF (@@MICROSOFTVERSION >= 167773760) --10.0.1600
begin
	exec sp_executesql N'insert into #summary select ''sqlserver_start_time'', convert(varchar(23),sqlserver_start_time,121) from sys.dm_os_sys_info'
	exec sp_executesql N'insert into #summary select ''resource governor enabled'', is_enabled from sys.resource_governor_configuration'
	insert into #summary values ('FilestreamShareName', cast (SERVERPROPERTY('FilestreamShareName') as nvarchar(max)))
	insert into #summary values ('FilestreamConfiguredLevel', cast (SERVERPROPERTY('FilestreamConfiguredLevel') as nvarchar(max)))
	insert into #summary values ('FilestreamEffectiveLevel', cast (SERVERPROPERTY('FilestreamEffectiveLevel') as nvarchar(max)))
	insert into #summary select 'number of active extended event traces',count(*) as 'cnt' from sys.dm_xe_sessions
end

IF (@@MICROSOFTVERSION >= 171050560) --10.50.1600
begin
	exec sp_executesql N'insert into #summary select ''possibly running in virtual machine'', virtual_machine_type from sys.dm_os_sys_info'
end

IF (@@MICROSOFTVERSION >= 184551476) --11.0.2100
begin
	exec sp_executesql N'insert into #summary select ''physical_memory_kb'', physical_memory_kb from sys.dm_os_sys_info'
	insert into #summary values ('HadrManagerStatus', cast (SERVERPROPERTY('HadrManagerStatus') as nvarchar(max)))
	insert into #summary values ('IsHadrEnabled', cast (SERVERPROPERTY('IsHadrEnabled') as nvarchar(max)))	
      insert into #summary SELECT 'instant_file_initialization_enabled', instant_file_initialization_enabled from sys.dm_server_services where process_id = SERVERPROPERTY('ProcessID')
end

IF (@@MICROSOFTVERSION >= 201328592) --12.0.2000
begin
	insert into #summary values ('IsLocalDB', cast (SERVERPROPERTY('IsLocalDB') as nvarchar(max)))
	insert into #summary values ('IsXTPSupported', cast (SERVERPROPERTY('IsXTPSupported') as nvarchar(max)))
end

RAISERROR ('--ServerProperty--', 0, 1) WITH NOWAIT

select * from #summary
order by PropertyName
drop table #summary
print ''

GO
--changing xp_instance_regenumvalues to dmv access as a part of issue #149

declare @startup table (ArgsName nvarchar(10), ArgsValue nvarchar(max))
insert into @startup 
SELECT     sReg.value_name,     CAST(sReg.value_data AS nvarchar(max))
FROM sys.dm_server_registry AS sReg
WHERE     sReg.value_name LIKE N'SQLArg%';

RAISERROR ('--Startup Parameters--', 0, 1) WITH NOWAIT
select * from @startup
go
print ''

create table #traceflg (TraceFlag int, Status int, Global int, Session int)
insert into #traceflg exec ('dbcc tracestatus (-1)')
print ''
RAISERROR ('--traceflags--', 0, 1) WITH NOWAIT
select * from #traceflg
drop table #traceflg
go

print ''
RAISERROR ('--sys.dm_os_schedulers--', 0, 1) WITH NOWAIT
select * from sys.dm_os_schedulers
go

IF (@@MICROSOFTVERSION >= 167773760 --10.0.1600
	and @@MICROSOFTVERSION < 171048960) --10.50.0.0
begin
	print ''
	RAISERROR ('--sys.dm_os_nodes--', 0, 1) WITH NOWAIT
	exec sp_executesql N'select node_id, memory_object_address, memory_clerk_address, io_completion_worker_address, memory_node_id, cpu_affinity_mask, online_scheduler_count, idle_scheduler_count active_worker_count, avg_load_balance, timer_task_affinity_mask, permanent_task_affinity_mask, resource_monitor_state, node_state_desc from sys.dm_os_nodes'
end
go

IF (@@MICROSOFTVERSION >= 171048960) --10.50.0.0
begin
	print ''
	RAISERROR ('--sys.dm_os_nodes--', 0, 1) WITH NOWAIT
	exec sp_executesql N'select node_id, memory_object_address, memory_clerk_address, io_completion_worker_address, memory_node_id, cpu_affinity_mask, online_scheduler_count, idle_scheduler_count active_worker_count, avg_load_balance, timer_task_affinity_mask, permanent_task_affinity_mask, resource_monitor_state, online_scheduler_mask, processor_group, node_state_desc from sys.dm_os_nodes'
end
go

print ''
RAISERROR ('--dm_os_sys_info--', 0, 1) WITH NOWAIT
select * from sys.dm_os_sys_info
go

if cast (SERVERPROPERTY('IsClustered') as int) = 1
begin
	print ''
	RAISERROR ('--fn_virtualservernodes--', 0, 1) WITH NOWAIT
	SELECT * FROM fn_virtualservernodes()
end
go


print ''
RAISERROR ('--sys.configurations--', 0, 1) WITH NOWAIT
select configuration_id, 
  convert(int,value) as 'value', 
  convert(int,value_in_use) as 'value_in_use', 
  convert(int,minimum) as 'minimum', 
  convert(int,maximum) as 'maximum', 
  convert(int,is_dynamic) as 'is_dynamic', 
  convert(int,is_advanced) as 'is_advanced', 
  name  
from sys.configurations order by name
go


print ''
RAISERROR ('--database files--', 0, 1) WITH NOWAIT
select database_id, [file_id], file_guid, [type],  LEFT(type_desc,10) as 'type_desc', data_space_id, [state], LEFT(state_desc,16) as 'state_desc', size, max_size, growth,
  is_media_read_only, is_read_only, is_sparse, is_percent_growth, is_name_reserved, create_lsn,  drop_lsn, read_only_lsn, read_write_lsn, differential_base_lsn, differential_base_guid,
  differential_base_time, redo_start_lsn, redo_start_fork_guid, redo_target_lsn, redo_target_fork_guid, backup_lsn, db_name(database_id) as 'Database_name',  name, physical_name 
from master.sys.master_files order by database_id, type, file_id
print ''

go

print ''
RAISERROR ('--sys.databases_ex--', 0, 1) WITH NOWAIT
select cast(DATABASEPROPERTYEX (name,'IsAutoCreateStatistics') as int) 'IsAutoCreateStatistics', cast( DATABASEPROPERTYEX (name,'IsAutoUpdateStatistics') as int) 'IsAutoUpdateStatistics', cast (DATABASEPROPERTYEX (name,'IsAutoCreateStatisticsIncremental') as int) 'IsAutoCreateStatisticsIncremental', *  from sys.databases
go

print ''
RAISERROR ('-- Windows Group Default Databases other than master --', 0, 1) WITH NOWAIT
select name,default_database_name from sys.server_principals where [type] = 'G' and is_disabled = 0 and default_database_name != 'master'
go

--removed AG related dmvs as a part of issue #162

print '-- sys.change_tracking_databases --'
select * from sys.change_tracking_databases
print ''


print '-- sys.dm_database_encryption_keys --'
select database_id, encryption_state from sys.dm_database_encryption_keys
print ''

go

IF @@MICROSOFTVERSION >= 251658240 --15.0.2000
BEGIN
	PRINT '-- sys.dm_tran_persistent_version_store_stats --'
	SELECT * FROM sys.dm_tran_persistent_version_store_stats
	PRINT ''
END
go

/*
--windows version from @@version
declare @pos int
set @pos = CHARINDEX(N' on ',@@VERSION)
print substring(@@VERSION, @pos + 4, LEN(@@VERSION))
*/



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
	EXEC ('exec sys.sp_certificate_issuers')

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

DECLARE @dbname nvarchar(64), @dbid INT
DECLARE @dbcc_log_info VARCHAR(MAX)
DECLARE @sql_major_version INT
DECLARE @sql_major_build INT

--check the version of current SQL Server (use old style to support older SQL versions)
SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 4) AS INT)), 
	@sql_major_build = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 2) AS INT)) 
		

DECLARE Database_Cursor CURSOR FOR SELECT database_id, name FROM MASTER.sys.databases

OPEN Database_Cursor;

FETCH NEXT FROM Database_Cursor into @dbid, @dbname;

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

		FETCH NEXT FROM Database_Cursor into @dbid, @dbname;

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
