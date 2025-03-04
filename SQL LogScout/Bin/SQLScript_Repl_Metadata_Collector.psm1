
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
	INNER JOIN [msdb].[dbo].[sysjobhistory] jh WITH(NOLOCK) ON sj.[job_id] = sj.[job_id]
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
							publisher_database_id,xact_seqno,type,article_id,originator_id,command_id,partial_command,CAST(command as nvarchar(max)) [command],hashkey,originator_lsn
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
							publisher_database_id,xact_seqno,type,article_id,originator_id,command_id,partial_command,CAST(command as nvarchar(max)) [command],hashkey,originator_lsn
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
        Write-LogDebug "$filName already exists, could be from GUI"
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

    
