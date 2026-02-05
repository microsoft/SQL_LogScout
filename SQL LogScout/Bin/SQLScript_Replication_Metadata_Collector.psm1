
    function Repl_Metadata_Collector_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "Repl_Metadata_Collector"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
-- PSSDIAG Replication Metadata Collector
--Contributors: jaferebe

USE tempdb
GO
SET QUOTED_IDENTIFIER ON
SET ANSI_NULLS ON 
SET NOCOUNT ON
SET IMPLICIT_TRANSACTIONS OFF
SET ANSI_WARNINGS OFF
GO


--When collector has started
PRINT 'Logging: Replication Collector Start Time'
SELECT [getdate]=getdate()
RAISERROR('',0,1) WITH NOWAIT

-- Global server data
PRINT '-- repl_sourceserver --'
SELECT @@SERVERNAME [SourceServer], REPLACE(REPLACE(@@VERSION, CHAR(10), ' ') , CHAR(13), ' ') [SourceSQLVersion]
RAISERROR('',0,1) WITH NOWAIT

-- msdb jobs that don't have a blank category (excludes user jobs)
PRINT '-- repl_msdb_jobs --'
IF HAS_PERMS_BY_NAME('msdb.dbo.sysjobs', 'object', 'SELECT') = 1
	SELECT job_id,originating_server_id,name,enabled,description,start_step_id,category_id,owner_sid,delete_level,date_created,date_modified 
	FROM [msdb].[dbo].[sysjobs] WITH(NOLOCK)
	WHERE category_id <> 0
ELSE
	PRINT 'Logging: Skipped [sysjobs]. Principal ' + SUSER_SNAME() + ' does not have SELECT permission ON msdb.dbo.sysjobs'
	RAISERROR('',0,1) WITH NOWAIT
GO

-- msdb job history that don't have a blank category (excludes user jobs), we have to sort to get the latest records if there is a verbose history
PRINT '-- repl_msdb_jobhistory --'
IF HAS_PERMS_BY_NAME('msdb.dbo.sysjobhistory', 'object', 'SELECT') = 1
	SELECT TOP (4999) sj.job_id,sj.name,jh.instance_id,jh.step_id,jh.step_name,jh.sql_message_id,jh.sql_severity,CAST(jh.message as nvarchar(256))[message],jh.run_status,jh.run_date,jh.run_time,jh.run_duration,jh.retries_attempted,jh.server
	FROM [msdb].[dbo].[sysjobs] sj WITH(NOLOCK)
	INNER JOIN [msdb].[dbo].[sysjobhistory] jh WITH(NOLOCK) ON sj.[job_id] = jh.[job_id]
	WHERE category_id <> 0
	ORDER BY jh.run_date desc, jh.run_time desc, jh.job_id asc, jh.step_id desc
ELSE
	PRINT 'Logging: Skipped [sysjobhistory]. Principal ' + SUSER_SNAME() + ' does not have SELECT permission ON msdb.dbo.sysjobhistory'
	RAISERROR('',0,1) WITH NOWAIT
GO


-- msdb job history that don't have a blank category (excludes user jobs), we have to sort to get the latest records if there is a verbose history
PRINT '-- repl_msdb_msagent_profileandparameters --'
IF HAS_PERMS_BY_NAME('msdb.dbo.MSagent_profiles', 'object', 'SELECT') = 1
	SELECT aprof.profile_id,aprof.profile_name,aprof.agent_type,aprof.type,CAST(aprof.description as nvarchar(256)) [description],aprof.def_profile,aparam.parameter_name,aparam.value 
	FROM msdb..MSagent_profiles aprof WITH(NOLOCK)
	INNER JOIN msdb..MSagent_parameters aparam WITH(NOLOCK)
	ON aprof.profile_id = aparam.profile_id
	ORDER BY aprof.profile_id
ELSE
	PRINT 'Logging: Skipped [MSagent_profiles]. Principal ' + SUSER_SNAME() + ' does not have SELECT permission ON msdb.dbo.msagent_profiles'
	RAISERROR('',0,1) WITH NOWAIT
GO



/* Get Replication Database Metadata Tables */

PRINT 'Logging: Creating Table Variable to Store Distribution Database Records'
--Use table variable to store distribution database records. While not common, we can have more than one distribution database on a given instance.

DECLARE @distribution_dbtable TABLE (distribution_db sysname, Processed int DEFAULT 0)
INSERT INTO @distribution_dbtable SELECT name,'0' FROM sys.databases WHERE is_distributor = 1

--Verify we have distribution db.
DECLARE @numberofdistriibutiondbs int
SET @numberofdistriibutiondbs = (SELECT COUNT(*) FROM @distribution_dbtable)
	IF @numberofdistriibutiondbs = 0
		BEGIN
			--technically a redundant check, but should be really efficient anyways
			RAISERROR ('SQL LOGSCOUT: Distributor not configured',20,1) WITH LOG
			RETURN
		END
DECLARE @DistribName sysname

--While loop to iterate through all distribution databases. At the end of this loop, we mark it as processed and proceed onto the next until there are none left.
WHILE(SELECT COUNT(*) FROM @distribution_dbtable WHERE Processed = 0) > 0
BEGIN
	
	SELECT TOP 1 @DistribName = distribution_db FROM @distribution_dbtable WHERE Processed = 0
	PRINT 'Logging: Exporting distribution database tables common for troubleshooting'
	-- get all needed info from distribution database
	--Separator for each distribution database so the file is more readable. If multiple distribution databases are configured, we collect the data and print the distribution database name for each data set as a unique identifier.
	
	PRINT '*****************************************************CURRENT DISTRIBUTION DATABASE:*****************************************************'
	PRINT '*****************************************************'+@DistribName+'*****************************************************'
	PRINT ''
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSarticles'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msarticles --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher_id,publisher_db,publication_id,article,article_id,destination_object,source_owner,source_object 
			FROM MSarticles WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MScached_peer_lsns'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mscached_peer_lsns --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			agent_id,originator,originator_db,originator_publication_id,originator_db_version,originator_lsn 
			FROM MScached_peer_lsns WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSdistribution_agents'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msdistribution_agents --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			id,name,publisher_database_id,publisher_id,publisher_db,publication,subscriber_id,subscriber_db,subscription_type,local_job,job_id,subscription_guid,
			profile_id,anonymous_subid,subscriber_name,virtual_agent_id,anonymous_agent_id,creation_date 
			FROM MSdistribution_agents WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSdistribution_history'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msdistribution_history --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			agent_id,runstatus,start_time,time,duration,comments,xact_seqno,current_delivery_rate,current_delivery_latency,delivered_transactions,delivered_commands,
			average_commands,delivery_rate,delivery_latency,total_delivered_commands,error_id,updateable_row,timestamp 
			FROM MSdistribution_history WITH (NOLOCK)
			/* limit to last 3 days of exeuction as a precaution if the distribution cleanup job is having issues */
			WHERE time >= DATEADD(DAY, -3, GETDATE())
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSlogreader_agents'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mslogreader_agents --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			id,name,publisher_id,publisher_db,publication,local_job,job_id,profile_id,publisher_security_mode,publisher_login,job_step_uid
			FROM MSlogreader_agents WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSlogreader_history'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mslogreader_history --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			agent_id,runstatus,start_time,time,duration,comments,xact_seqno,delivery_time,delivered_transactions,delivered_commands,average_commands,delivery_rate,delivery_latency,
			error_id,timestamp,updateable_row
			FROM MSlogreader_history WITH (NOLOCK)
			/* limit to last 3 days of exeuction as a precaution if the distribution cleanup job is having issues */
			WHERE time >= DATEADD(DAY, -3, GETDATE())
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSmerge_agents'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msmerge_agents --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			id,name,publisher_id,publisher_db,publication,subscriber_id,subscriber_db,local_job,job_id,profile_id,anonymous_subid,subscriber_name,creation_date,offload_enabled,offload_server,
			sid,subscriber_security_mode,subscriber_login,publisher_security_mode,publisher_login,job_step_uid
			FROM MSmerge_agents WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSmerge_articlehistory'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msmerge_articlehistory --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			session_id,phase_id,article_name,start_time,duration,inserts,updates,deletes,conflicts,rows_retried,percent_complete,estimated_changes,relative_cost			
			FROM MSmerge_articlehistory WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSmerge_history'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msmerge_history --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			session_id,agent_id,comments,error_id,timestamp,updateable_row,time		
			FROM MSmerge_history WITH (NOLOCK)
			/* limit to last 3 days of exeuction as a precaution if the distribution cleanup job is having issues */
			WHERE time >= DATEADD(DAY, -3, GETDATE())
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSmerge_identity_range_allocations'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msmerge_identity_range_allocations --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher_id,publisher_db,publication,article,subscriber,subscriber_db,is_pub_range,ranges_allocated,range_begin,range_end,next_range_begin,next_range_end,max_used,time_of_allocation			
			FROM MSmerge_identity_range_allocations WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSmerge_sessions'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msmerge_sessions --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			session_id,agent_id,start_time,end_time,duration,delivery_time,upload_time,download_time,schema_change_time,prepare_snapshot_time,delivery_rate,time_remaining,percent_complete,upload_inserts,
			upload_updates,upload_deletes,upload_conflicts,upload_rows_retried,download_inserts,download_updates,download_deletes,download_conflicts,download_rows_retried,schema_changes,bulk_inserts,metadata_rows_cleanedup,
			runstatus,estimated_upload_changes,estimated_download_changes,connection_type,timestamp,current_phase_id,spid,spid_login_time
			FROM MSmerge_sessions WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSmerge_subscriptions'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msmerge_subscriptions --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher_id,publisher_db,publication_id,subscriber_id,subscriber_db,subscription_type,sync_type,status,subscription_time,description,publisher,subscriber,subid,subscriber_version
			FROM MSmerge_subscriptions WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSpublication_access'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mspublication_access --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publication_id,login,sid
			FROM MSpublication_access WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSpublications'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mspublications --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher_id,publisher_db,publication,publication_id,publication_type,thirdparty_flag,independent_agent,immediate_sync,allow_push,allow_pull,
			allow_anonymous,description,vendor_name,retention,sync_method,allow_subscription_copy,thirdparty_options,allow_queued_tran,options,retention_period_unit,
			allow_initialize_from_backup,min_autonosync_lsn
			FROM MSpublications WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSpublicationthresholds'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mspublicationthresholds --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publication_id,metric_id,CAST(value as nvarchar(256)) [value],shouldalert,isenabled
			FROM MSpublicationthresholds WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSpublisher_databases'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mspublisher_databases --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher_id,publisher_db,id,publisher_engine_edition
			FROM MSpublisher_databases WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSqreader_agents'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msqreader_agents --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			id,name,job_id,profile_id,job_step_uid
			FROM MSqreader_agents WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSqreader_history'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msqreader_history --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			agent_id,publication_id,runstatus,start_time,time,duration,comments,transaction_id,transaction_status,transactions_processed,commands_processed,
			delivery_rate,transaction_rate,subscriber,subscriberdb,error_id,timestamp
			FROM MSqreader_history WITH (NOLOCK)
			/* limit to last 3 days of exeuction as a precaution if the distribution cleanup job is having issues */
			WHERE time >= DATEADD(DAY, -3, GETDATE())
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_backup_lsns'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_backup_lsns --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher_database_id,valid_xact_id,valid_xact_seqno,next_xact_id,next_xact_seqno
			FROM MSrepl_backup_lsns WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_commands'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_commands_oldest --'')
			SELECT TOP 100  distribution_dbname = '''+@DistribName+''''+',
			publisher_database_id,xact_seqno,type,article_id,originator_id,command_id,partial_command,CAST(SUBSTRING(command, 7, 8000) AS NVARCHAR(MAX)) as [command],hashkey,originator_lsn
			FROM MSrepl_commands WITH (NOLOCK)
			ORDER BY xact_seqno ASC
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_commands'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_commands_newest --'')
			SELECT TOP 100  distribution_dbname = '''+@DistribName+''''+',
			publisher_database_id,xact_seqno,type,article_id,originator_id,command_id,partial_command,CAST(SUBSTRING(command, 7, 8000) AS NVARCHAR(MAX)) as [command],hashkey,originator_lsn
			FROM MSrepl_commands WITH (NOLOCK)
			ORDER BY xact_seqno DESC
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_errors'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_errors --'')
			SELECT TOP 1000 distribution_dbname = '''+@DistribName+''''+',
			id,time,error_type_id,source_type_id,source_name,error_code,error_text,xact_seqno,command_id,session_id
			FROM MSrepl_errors WITH (NOLOCK)
			ORDER BY time DESC
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_identity_range'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_identity_range --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher,publisher_db,tablename,identity_support,next_seed,pub_range,range,max_identity,threshold,current_max
			FROM MSrepl_identity_range WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_originators'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_originators --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			id,publisher_database_id,srvname,dbname,publication_id,dbversion
			FROM MSrepl_originators WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_transactions'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_transactions_oldest --'')
			SELECT TOP 100 distribution_dbname = '''+@DistribName+''''+',
			publisher_database_id,xact_id,xact_seqno,entry_time
			FROM MSrepl_transactions WITH (NOLOCK)
			ORDER BY xact_seqno ASC
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_transactions'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_transactions_newest --'')
			SELECT TOP 100 distribution_dbname = '''+@DistribName+''''+',
			publisher_database_id,xact_id,xact_seqno,entry_time
			FROM MSrepl_transactions WITH (NOLOCK)
			ORDER BY xact_seqno DESC
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_version'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msrepl_version --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			major_version,minor_version,revision,db_existed
			FROM MSrepl_version WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSreplication_monitordata'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msreplication_monitordata --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			lastrefresh,computetime,publication_id,publisher,publisher_srvid,publisher_db,publication,publication_type,agent_type,agent_id,agent_name,job_id,status,isagentrunningnow,
			warning,last_distsync,agentstoptime,distdb,retention,time_stamp,worst_latency,best_latency,avg_latency,cur_latency,worst_runspeedPerf,best_runspeedPerf,average_runspeedPerf,
			mergePerformance,mergelatestsessionrunduration,mergelatestsessionrunspeed,mergelatestsessionconnectiontype,retention_period_unit
			FROM MSreplication_monitordata WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSsnapshot_agents'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mssnapshot_agents --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			id,name,publisher_id,publisher_db,publication,publication_type,local_job,job_id,profile_id,dynamic_filter_login,dynamic_filter_hostname,publisher_security_mode,publisher_login,
			job_step_uid
			FROM MSsnapshot_agents WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSsnapshot_history'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mssnapshot_history --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			agent_id,runstatus,start_time,time,duration,comments,delivered_transactions,delivered_commands,delivery_rate,error_id,timestamp
			FROM MSsnapshot_history WITH (NOLOCK)
			/* limit to last 3 days of exeuction as a precaution if the distribution cleanup job is having issues */
			WHERE time >= DATEADD(DAY, -3, GETDATE())
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSsubscriber_info'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mssubscriber_info --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher,subscriber,type,login,description,security_mode
			FROM MSsubscriber_info WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSsubscriber_schedule'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mssubscriber_schedule --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher,subscriber,agent_type,frequency_type,frequency_interval,frequency_relative_interval,frequency_recurrence_factor,frequency_subday,
			frequency_subday_interval,active_start_time_of_day,active_end_time_of_day,active_start_date,active_end_date
			FROM MSsubscriber_schedule WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSsubscriptions'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mssubscriptions --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher_database_id,publisher_id,publisher_db,publication_id,article_id,subscriber_id,subscriber_db,subscription_type,sync_type,status,subscription_seqno,snapshot_seqno_flag,
			independent_agent,subscription_time,loopback_detection,agent_id,update_mode,publisher_seqno,ss_cplt_seqno,nosync_type
			FROM MSsubscriptions WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSsync_states'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mssync_states --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			publisher_id,publisher_db,publication_id
			FROM MSsync_states WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MStracer_history'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mstracer_history --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			parent_tracer_id,agent_id,subscriber_commit
			FROM MStracer_history WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MStracer_tokens'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_mstracer_tokens --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			tracer_id,publication_id,publisher_commit,distributor_commit
			FROM MStracer_tokens WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSredirected_publishers'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msRedirected_Publishers --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			original_publisher,publisher_db,redirected_publisher 
			FROM MSredirected_publishers WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''MSreplservers'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_msreplservers --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			srvid,srvname 
			FROM MSreplservers WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
			'USE '+@DistribName+' '+'IF OBJECT_ID (''sys.servers'') IS NOT NULL
			BEGIN
			PRINT(''-- repl_sysservers --'')
			SELECT distribution_dbname = '''+@DistribName+''''+',
			server_id,name,product,provider,CAST(data_source as nvarchar(256)) [data_source],CAST(location as nvarchar(256)) [location],CAST(provider_string as nvarchar(256)) [provider_string],catalog,is_linked,is_remote_login_enabled,is_rpc_out_enabled,
			is_data_access_enabled,is_system,is_publisher,is_subscriber,is_distributor,is_nonsql_subscriber,is_remote_proc_transaction_promotion_enabled,
			modify_date
			FROM sys.servers WITH (NOLOCK)
			END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	EXEC(
		'USE '+@DistribName+' '+'IF OBJECT_ID (''MSrepl_agent_jobs'') IS NOT NULL
		BEGIN
		PRINT(''-- repl_msrepl_agent_jobs --'')
		SELECT distribution_dbname = '''+@DistribName+''''+',
		job_id,name,enabled,CAST(description as nvarchar (256)) [description],category_name,subsystem,CAST(command as nvarchar(512)) [command],agent_id,active_start_time,active_end_time,freq_type,freq_interval
		FROM MSrepl_agent_jobs WITH (NOLOCK)
		END'
		)
	RAISERROR('',0,1) WITH NOWAIT
	
	--Update the table varaible to mark as processed so we'll return and do the next row in the table.
	UPDATE @distribution_dbtable SET Processed = 1 WHERE distribution_db=@DistribName

	END


PRINT 'Logging: Replication Collector End Time'
SELECT [getdate]=getdate()
RAISERROR('',0,1) WITH NOWAIT
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB5fu3NblO805Tz
# z+/Bir5oPX6K+bgfJNa9BYZf9ig+wKCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFsK7g+kfuT2
# aGwHu6eeaAqfyp3xFjYF2vbm++7t/JSpMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAnujzECr0Osohr74/nQk/B2FhDSlyf+zsCWEdNzqLZ6iH
# JyV/3a0SOyQ7hGjQy5Q92DgDhYjz6D9qkcS32v7twToTSVwcBzK712L//3s9NTrA
# BV5DTar7DWGzBi1EgpXvAA278QMtCZ+vSlDAtDf+WfdTxZ1thxyPS8Cl7rccE2QH
# nBQmrF9tIZnWumJ+EefQzy+6kOtd/nqeLxAMmQ2qDRRHMIOXhrz37Dh7SSP3tuU8
# i8EUocLLwH2+dxe8nPU+982UI+pAweci/eeunaTQBrTmE5i0HEHLWhxslTHI63M5
# W7uC3SFkC99tqX69KCOhfEdBQFox1FHimIGgIyJRs6GCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCCk8dsJ4WpvasX4Pyy/BFeY83s+mdIzoVoeBUaJ7Pdp
# /gIGaXRAeW+AGBMyMDI2MDIwNDE2MzUyOC4xOThaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo1OTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACFI3NI0TuBt9y
# AAEAAAIUMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgxOFoXDTI2MTExMzE4NDgxOFowgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjU5MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyU+nWgCU
# yvfyGP1zTFkLkdgOutXcVteP/0CeXfrF/66chKl4/MZDCQ6E8Ur4kqgCxQvef7Lg
# 1gfso1EWWKG6vix1VxtvO1kPGK4PZKmOeoeL68F6+Mw2ERPy4BL2vJKf6Lo5Z7X0
# xkRjtcvfM9T0HDgfHUW6z1CbgQiqrExs2NH27rWpUkyTYrMG6TXy39+GdMOTgXyU
# DiRGVHAy3EqYNw3zSWusn0zedl6a/1DbnXIcvn9FaHzd/96EPNBOCd2vOpS0Ck7k
# gkjVxwOptsWa8I+m+DA43cwlErPaId84GbdGzo3VoO7YhCmQIoRab0d8or5Pmyg+
# VMl8jeoN9SeUxVZpBI/cQ4TXXKlLDkfbzzSQriViQGJGJLtKS3DTVNuBqpjXLdu2
# p2Yq9ODPqZCoiNBh4CB6X2iLYUSO8tmbUVLMMEegbvHSLXQR88QNICjFoBBDCDyd
# oTo9/TNkq80mO77wDM04tPdvbMmxT01GTod60JJxUGmMTgseghdBGjkN+D6GsUpY
# 7ta7hP9PzLrs+Alxu46XT217bBn6EwJsAYAc9C28mKRUcoIZWQRb+McoZaSu2EcS
# zuIlAaNIQNtGlz2PF3foSeGmc/V7gCGs8AHkiKwXzJSPftnsH8O/R3pJw2D/2hHE
# 3JzxH2SrLX1FdI7Drw145PkL0hbFL6MVCCkCAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBTbX/bs1cSpyTYnYuf/Mt9CPNhwGzAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# P3xp9D4Gu0SH9B+1JH0hswFquINaTT+RjpfEr8UmUOeDl4U5uV+i28/eSYXMxgem
# 3yBZywYDyvf4qMXUvbDcllNqRyL2Rv8jSu8wclt/VS1+c5cVCJfM+WHvkUr+dCfU
# lOy9n4exCPX1L6uWwFH5eoFfqPEp3Fw30irMN2SonHBK3mB8vDj3D80oJKqe2tat
# O38yMTiREdC2HD7eVIUWL7d54UtoYxzwkJN1t7gEEGosgBpdmwKVYYDO1USWSNmZ
# ELglYA4LoVoGDuWbN7mD8VozYBsfkZarOyrJYlF/UCDZLB8XaLfrMfMyZTMCOuEu
# PD4zj8jy/Jt40clrIW04cvLhkhkydBzcrmC2HxeE36gJsh+jzmivS9YvyiPhLkom
# 1FP0DIFr4VlqyXHKagrtnqSF8QyEpqtQS7wS7ZzZF0eZe0fsYD0J1RarbVuDxmWs
# q45n1vjRdontuGUdmrG2OGeKd8AtiNghfnabVBbgpYgcx/eLyW/n40eTbKIlsm0c
# seyuWvYFyOqQXjoWtL4/sUHxlWIsrjnNarNr+POkL8C1jGBCJuvm0UYgjhIaL+XB
# XavrbOtX9mrZ3y8GQDxWXn3mhqM21ZcGk83xSRqB9ecfGYNRG6g65v635gSzUmBK
# ZWWcDNzwAoxsgEjTFXz6ahfyrBLqshrjJXPKfO+9Ar8wggdxMIIFWaADAgECAhMz
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
# bGQgVFNTIEVTTjo1OTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA2RysX196RXLTwA/P8RFW
# dUTpUsaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0t53MwIhgPMjAyNjAyMDQxNTQyNDNaGA8yMDI2MDIwNTE1
# NDI0M1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7S3ncwIBADAKAgEAAgIB2wIB
# /zAHAgEAAgISOzAKAgUA7S848wIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IB
# AQCWj6LbcjtppvPg46eU6FmATii+3YF/eGZqbM+xvp1MWOmwywxcgzEjJcRmZ7bo
# mbvv7PXIZmwrNN2tQtvU+2QolYFmDiUVToJ29JAsK8wVXe5RmmIY4B/mhMmVWZNC
# kVfycFo4IbMiXbfBQzPs+ELqSBmb9Txn+LIvK/qX5GxPT7z3d2BRVuvdttsZVoQl
# 8xrVjciuzb35c87kqsl5vmHhvLlG2R7bt2dBATZHiJWc5sl6UShC8KEtAc03m/Vd
# 4BxLvnYXFUh7Gwg3u7esQ9olTBh8R+Kg7fIIs78MmbieiFgeTR5/cBly36DYJlMW
# Ng30BeFB/7OvN1imTRjrjh6vMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIUjc0jRO4G33IAAQAAAhQwDQYJYIZIAWUDBAIB
# BQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgMgS0wWINCM2Y0v5dUUZrks9+V6x70Ktt9bkKKBBR9YUwgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCA2eKvvWx5bcoi43bRO3+EttQUCvyeD2dbXy/6+0xK+
# xzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACFI3N
# I0TuBt9yAAEAAAIUMCIEICtPp+hyWwC7IKIybvj3Fc0ZTxyC5wEnJ36AwhgVt0m1
# MA0GCSqGSIb3DQEBCwUABIICAK0BUz/xyCQ6pBnackUXfWVNJ7rRKRktwRxvZiGJ
# Q0kwr/dZe449BG2zHxNuz1EqLTJwQ/0AjQ4yvIfg4lXeNhNXdZR5OCddrycATRmh
# zncSPfhjWRniYWFxhumhAzu6SYw1H67M15lD5nOkg/ve86wgQKZ6UIevE4I3gRpU
# vKKvnYVitL9vFxec3rL4wXXVwDD6GzmPfsmpnHA9c6bmc0zwZS26QyjUf5FdTzpL
# lpeui5R9JJKqwj7QfBig/ZqmguTBoP+hgUaLFqQf+GiOVFAyXXA6tBVOBvQ57D4u
# 6IGb4JsBkq+qqNyj0Vm8YSNBYMiHed1T80Bg4vHQMAoMu+OPHa1kYOLRlfV0cKko
# b0QZ4nnSesrP8JgodTYSUqxmrYyv2EiaUVXjMhv5YuFwgKKVBtitCe+DGPPiIcCe
# jkFFCod3pDZhxyK7k+cJt9mT4RZVdiQC22jykOIwlOqh/e03WqBpNrFEcHFiSndk
# B0prS7SDm+iS+yxCgopT6PkkPaWucaTWFFdXV+5zfOqaXpIFkDyQb2/81HZA3aw0
# c4RiWrN2J2zqwjMbWKhMuSUXOJj+IZ8x/hQ4XlIZdudObI34c3RMlJsrws78uBtO
# ec7brYsQE3w76YFN8LMdU14MB664PfL9xIo1g1G9qvVLjxQHXy97GEy2SGkbKstC
# Udcv
# SIG # End signature block
