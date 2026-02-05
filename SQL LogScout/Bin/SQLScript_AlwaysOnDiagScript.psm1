
    function AlwaysOnDiagScript_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "AlwaysOnDiagScript"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
    
    
        SET NOCOUNT ON
        GO
        SELECT GETDATE()
        GO

        -- Get the information about the endpoints, owners, config, etc.
        PRINT ''
        PRINT '-- AG_hadr_endpoints_principals --'

        SELECT        tcpe.name, tcpe.endpoint_id, tcpe.principal_id, tcpe.protocol, tcpe.protocol_desc, 
                    tcpe.type, tcpe.type_desc, tcpe.state, tcpe.state_desc, tcpe.is_admin_endpoint, 
                    tcpe.port, tcpe.is_dynamic_port, tcpe.ip_address, 
                    me.role, me.role_desc, me.is_encryption_enabled, me.connection_auth, me.connection_auth_desc, me.certificate_id, me.encryption_algorithm, me.encryption_algorithm_desc,
                    sp.name AS principal_Name,sp.sid, sp.type AS principal_type, sp.type_desc AS principal_type_desc,
                    sp.is_disabled, sp.create_date, sp.modify_date,sp.default_database_name, sp.default_language_name, sp.credential_id, sp.owning_principal_id, sp.is_fixed_role
        FROM         sys.tcp_endpoints                AS tcpe 
        INNER JOIN   sys.database_mirroring_endpoints AS me   ON tcpe.endpoint_id  = me.endpoint_id 
        INNER JOIN   sys.server_principals            AS sp   ON tcpe.principal_id = sp.principal_id
        OPTION (max_grant_percent = 3, MAXDOP 1)

        --Database Mirroring Endpoint Permissions
        PRINT ''
        PRINT '-- AG_mirroring_endpoints_permissions --'
        SELECT cast(perm.class_desc as varchar(30)) as [ClassDesc], 
            cast(prin.name as varchar(30)) [Principal],
            cast(perm.permission_name as varchar(30)) as [Permission], 
            cast(perm.state_desc as varchar(30)) as [StateDesc],
            cast(prin.type_desc as varchar(30)) as [PrincipalType],
            prin.is_disabled 
            FROM sys.server_permissions perm
        LEFT JOIN sys.server_principals prin 	ON perm.grantee_principal_id = prin.principal_id
        LEFT JOIN sys.tcp_endpoints     tep 	ON perm.major_id = tep.endpoint_id
        WHERE perm.class_desc = 'ENDPOINT' AND perm.permission_name = 'CONNECT' AND tep.type = 4
        OPTION (max_grant_percent = 3, MAXDOP 1)

        --Database Mirroring States
        PRINT ''
        PRINT '-- AG_mirroring_states --'
        SELECT database_id, mirroring_guid, mirroring_state, mirroring_role, mirroring_role_sequence, mirroring_safety_level, mirroring_safety_sequence, 
                    mirroring_witness_state, mirroring_failover_lsn, mirroring_end_of_log_lsn, mirroring_replication_lsn, mirroring_connection_timeout, mirroring_redo_queue,
                    db_name(database_id) as 'database_name', mirroring_partner_name, mirroring_partner_instance, mirroring_witness_name 
        FROM sys.database_mirroring 
        WHERE mirroring_guid IS NOT NULL
        OPTION (max_grant_percent = 3, MAXDOP 1)


        --Availability Group Listeners and IP
        --First the listeners, one line per listener instead of the previous multi-line per IP.
        --IPs will be broken out in the next query.
        PRINT ''
        PRINT '-- AG_hadr_ag_listeners --'
        DECLARE @sql_major_version INT, @sql_major_build INT, @sql NVARCHAR(max)

        SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT)),
            @sql_major_build = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT)) 
            

        SET @sql ='SELECT agl.dns_name AS [Listener_Name], ag.name AS [AG_Name] ,agl.group_id,agl.listener_id,agl.dns_name,agl.port,agl.is_conformant,agl.ip_configuration_string_from_cluster'

        IF ((@sql_major_version >=16) OR (@sql_major_version =15 AND @sql_major_build >=4073) OR (@sql_major_version =14 AND @sql_major_build >=3401) OR (@sql_major_version =13 AND @sql_major_build >=6300)) -- this exists  SQL 2019 CU8 ,SQL 2017 CU25,SQL 2016 SP3 and above
            BEGIN
            SET @sql = @sql + ',agl.is_distributed_network_name'
            END
        SET @sql = @sql + ' FROM sys.availability_group_listeners agl
        INNER JOIN sys.availability_groups          ag ON agl.group_id = ag.group_id 
        OPTION (max_grant_percent = 3, MAXDOP 1) '

        EXEC(@sql)

        SET @sql = ''

        --IP information which isn't fully returned via the query above.
        PRINT ''
        PRINT '-- AG_hadr_ag_ip_information --'
        SELECT        agl.dns_name AS Listener_Name, aglip.listener_id, aglip.ip_address, aglip.ip_subnet_mask, aglip.is_dhcp, aglip.network_subnet_ip, 
                    aglip.network_subnet_prefix_length, aglip.network_subnet_ipv4_mask, aglip.state, aglip.state_desc
            FROM	sys.availability_group_listener_ip_addresses AS aglip 
        INNER JOIN	sys.availability_group_listeners             AS agl	   ON aglip.listener_id = agl.listener_id
        OPTION (max_grant_percent = 3, MAXDOP 1)


        --ROUTING LIST INFO
        PRINT ''
        PRINT '-- AG_hadr_readonly_routing --'
        SELECT	cast(ar.replica_server_name as varchar(30)) [WhenThisServerIsPrimary], 
                rl.routing_priority [Priority], 
                cast(ar2.replica_server_name as varchar(30)) [RouteToThisServer],
                ar.secondary_role_allow_connections_desc [ConnectionsAllowed],
                cast(ar2.read_only_routing_url as varchar(50)) as [RoutingURL]

            FROM sys.availability_read_only_routing_lists rl
        INNER JOIN sys.availability_replicas                ar  ON rl.replica_id = ar.replica_id
        INNER JOIN sys.availability_replicas                ar2 ON rl.read_only_replica_id = ar2.replica_id
        ORDER BY ar.replica_server_name, rl.routing_priority
        OPTION (max_grant_percent = 3, MAXDOP 1)


        --AlwaysOn Cluster Information
        PRINT ''
        PRINT '-- AG_hadr_cluster --'
        SELECT  cluster_name,quorum_type,quorum_type_desc,quorum_state,quorum_state_desc
        FROM sys.dm_hadr_cluster
        OPTION (max_grant_percent = 3, MAXDOP 1)



        -- AlwaysOn Cluster Information
        -- Note that this information is not guaranteed to be 100% accurate or correct since Windows Server 2012+.
        PRINT ''
        PRINT '-- AG_hadr_cluster_members --'
        SELECT        cm.member_name, cm.member_type, cm.member_type_desc, cm.member_state, cm.member_state_desc, cm.number_of_quorum_votes,
                    cn.network_subnet_ip, cn.network_subnet_ipv4_mask, cn.network_subnet_prefix_length, cn.is_public, cn.is_ipv4
            FROM	sys.dm_hadr_cluster_members  AS cm 
        INNER JOIN	sys.dm_hadr_cluster_networks AS cn ON cn.member_name = cm.member_name
        OPTION (max_grant_percent = 3, MAXDOP 1)

        PRINT ''

        --AlwaysOn Availability Group State, Identification and Configuration 
        SET @sql ='SELECT	 ag.group_id, ag.name, ag.resource_id, ag.resource_group_id, ag.failure_condition_level, ag.health_check_timeout, ag.automated_backup_preference,ag.automated_backup_preference_desc'

        IF (@sql_major_version >=13) --these exists SQL 2016 and above
            BEGIN
            SET @sql = @sql + ', ag.version, ag.basic_features ,ag.dtc_support, ag.db_failover, ag.is_distributed'
            END
        IF (@sql_major_version >=14) --these exists SQL 2017 and above
            BEGIN
            SET @sql = @sql + ', ag.cluster_type, ag.cluster_type_desc,ag.required_synchronized_secondaries_to_commit, ag.sequence_number'
            END
        IF (@sql_major_version >=15) --this exists SQL 2019 and above
            BEGIN
            SET @sql = @sql + ', ag.is_contained'
            END
        SET @sql = @sql + ', ags.primary_replica, ags.primary_recovery_health, ags.primary_recovery_health_desc, ags.secondary_recovery_health,
                ags.secondary_recovery_health_desc, ags.synchronization_health, ags.synchronization_health_desc
            FROM	sys.availability_groups AS ag 
        INNER JOIN	sys.dm_hadr_availability_group_states AS ags ON ag.group_id = ags.group_id 
        OPTION (max_grant_percent = 3, MAXDOP 1)'
        PRINT '-- AG_hadr_ag_states --'
        EXEC(@sql)

        SET @sql = ''


        --AlwaysOn Availability Replica State, Identification and Configuration 
        SET @sql ='SELECT        arc.group_name, arc.replica_server_name, arc.node_name, ar.replica_id, ar.group_id, ar.replica_metadata_id, 
                    ar.owner_sid, ar.endpoint_url, ar.availability_mode, ar.availability_mode_desc, ar.failover_mode, ar.failover_mode_desc, 
                    ar.session_timeout, ar.primary_role_allow_connections, ar.primary_role_allow_connections_desc, ar.secondary_role_allow_connections, 
                    ar.secondary_role_allow_connections_desc, ar.create_date, ar.modify_date, ar.backup_priority, ar.read_only_routing_url '
        IF (@sql_major_version >=13) --this exists SQL 2016 and above
            BEGIN
            SET @sql = @sql + ', ar.seeding_mode, ar.seeding_mode_desc '
            END

        IF (@sql_major_version >=15) --this exists SQL 2019 and above
            BEGIN
            SET @sql = @sql + ', ar.read_write_routing_url'
            END

        SET @sql = @sql + ' , ars.is_local, ars.role
                            , role_desc = CASE WHEN ars.role_desc IS NULL THEN N''<unknown>'' ELSE ars.role_desc END
                            , ars.operational_state
                            , operational_state_desc = CASE WHEN ars.operational_state_desc  IS NULL THEN N''<unknown>'' ELSE ars.operational_state_desc END
                            , ars.connected_state
                            , connected_state_desc =  CASE WHEN ars.connected_state_desc IS NULL THEN CASE WHEN ars.is_local = 1 THEN N''CONNECTED'' ELSE N''<unknown>'' END ELSE ars.connected_state_desc END
                            , ars.recovery_health, ars.recovery_health_desc, 
                    ars.synchronization_health, ars.synchronization_health_desc, ars.last_connect_error_number, ars.last_connect_error_description, 
                    ars.last_connect_error_timestamp '

        IF (@sql_major_version >=14) --this exists SQL 2017 and above
            BEGIN
            SET @sql = @sql + ', ars.write_lease_remaining_ticks'
            END
        IF (@sql_major_version >=15) --this exists SQL 2019 and above
            BEGIN
            SET @sql = @sql + ', ars.current_configuration_commit_start_time_utc'
            END
        SET @sql = @sql + ' FROM	sys.dm_hadr_availability_replica_cluster_nodes  AS arc 
        INNER JOIN  sys.dm_hadr_availability_replica_cluster_states AS arcs ON arc.replica_server_name = arcs.replica_server_name 
        INNER JOIN	sys.dm_hadr_availability_replica_states         AS ars  ON arcs.replica_id = ars.replica_id 
        INNER JOIN	sys.availability_replicas                       AS ar   ON ars.replica_id  = ar.replica_id 
        INNER JOIN	sys.availability_groups                         AS ag   ON ag.group_id     = arcs.group_id AND ag.name = arc.group_name
        ORDER BY CAST(arc.group_name AS varchar(30)), CAST(ars.role_desc AS varchar(30)) 
        OPTION (max_grant_percent = 3, MAXDOP 1)'
        PRINT ''
        PRINT '-- AG_hadr_ag_replica_states --'
        EXEC(@sql)

        SET @sql = ''


        --AlwaysOn Availability Database Identification, Configuration, State and Performance 
		SET @sql ='SELECT ag.name AS Availability_Group, drcs.replica_id, drcs.group_database_id, dbs.[name] AS [database_name], drcs.is_failover_ready, drcs.is_pending_secondary_suspend, 
				drcs.is_database_joined, drcs.recovery_lsn, drcs.truncation_lsn, drs.database_id, drs.group_id, drs.is_local '

		IF (@sql_major_version >=12) --this exists SQL 2014 and above
			BEGIN
			SET @sql = @sql + ', 	drs.is_primary_replica'
			END
		SET @sql = @sql + ',  drs.synchronization_state, 
				drs.synchronization_state_desc, drs.is_commit_participant,drs.synchronization_health, drs.synchronization_health_desc, drs.database_state, drs.database_state_desc,
				drs.is_suspended, drs.suspend_reason, drs.suspend_reason_desc, drs.last_sent_lsn, drs.last_sent_time,
				drs.last_received_lsn, drs.last_received_time, drs.last_hardened_lsn, drs.last_hardened_time, drs.last_redone_lsn, drs.last_redone_time, 
				drs.log_send_queue_size, drs.log_send_rate, drs.redo_queue_size, drs.redo_rate, drs.filestream_send_rate, drs.end_of_log_lsn, drs.last_commit_lsn, drs.last_commit_time   '

		IF (@sql_major_version >=12) --this exists SQL 2014 and above
			BEGIN
			SET @sql = @sql + ', 	drs.low_water_mark_for_ghosts'
			END
		IF (@sql_major_version >=13) --this exists SQL 2016 and above
			BEGIN
			SET @sql = @sql + ', drs.secondary_lag_seconds'
			END
		IF (@sql_major_version >=15) --this exists SQL 2019 and above
			BEGIN
			SET @sql = @sql + ', drs.quorum_commit_lsn, drs.quorum_commit_time'
			END

		SET @sql = @sql + ', pr.file_id, pr.page_id, pr.error_type, pr.page_status, pr.modification_time ,ag.name, ag.resource_id, ag.resource_group_id, ag.failure_condition_level, ag.health_check_timeout, ag.automated_backup_preference, ag.automated_backup_preference_desc'

		IF (@sql_major_version >=13) --this exists SQL 2016 and above
			BEGIN
			SET @sql = @sql + ', ag.version, ag.basic_features, ag.dtc_support, ag.db_failover, ag.is_distributed'
			END
		IF (@sql_major_version >=14) --this exists SQL 2017 and above
			BEGIN
			SET @sql = @sql + ', ag.cluster_type, ag.cluster_type_desc, ag.required_synchronized_secondaries_to_commit, ag.sequence_number'
			END
		IF (@sql_major_version >=15) --this exists SQL 2019 and above
			BEGIN
			SET @sql = @sql + ', ag.is_contained'
			END
		SET @sql = @sql + ', ar.replica_server_name AS [replica_name], ar.endpoint_url, ar.availability_mode, ar.availability_mode_desc, dbs.log_reuse_wait_desc
		FROM sys.databases dbs
		INNER JOIN sys.dm_hadr_database_replica_states drs
			ON dbs.database_id = drs.database_id 
		INNER JOIN sys.availability_groups ag
			ON drs.group_id = ag.group_id
		INNER JOIN sys.dm_hadr_availability_replica_states ars
			ON ars.replica_id = drs.replica_id
		INNER JOIN sys.availability_replicas ar
			ON ar.replica_id = ars.replica_id
		LEFT OUTER JOIN sys.dm_hadr_auto_page_repair                AS pr  
			ON drs.database_id = pr.database_id 
		LEFT OUTER JOIN sys.dm_hadr_database_replica_cluster_states AS drcs
			ON drs.group_database_id = drcs.group_database_id AND drcs.replica_id = drs.replica_id
		ORDER BY drs.database_id, ar.replica_server_name
		OPTION (max_grant_percent = 3, MAXDOP 1)'
		PRINT ''
		PRINT '--AG_hadr_ag_database_replica_states--'
		EXEC(@sql)
		SET @sql = ''
		PRINT ''


        PRINT '-- AG_dm_os_server_diagnostics_log_configurations --'
        SELECT        is_enabled, path, max_size, max_files
        FROM            sys.dm_os_server_diagnostics_log_configurations
        PRINT ''

        IF (@sql_major_version >=13) --this exists SQL 2016 and above
        BEGIN
            PRINT '-- AG_hadr_automatic_seeding --'
            SELECT	CONVERT(VARCHAR(64),ag.name) AS ag_name, 
                    CONVERT(VARCHAR(64),db_name(dbrs.database_id)) database_name,  
                    start_time, completion_time, operation_id, is_source, 
                    CONVERT(VARCHAR(128),current_state) AS current_state, 
                    performed_seeding, CONVERT(VARCHAR(128),failure_state_desc) AS failure_state_desc, 
                    error_code  
            FROM sys.dm_hadr_automatic_seeding asd 
            LEFT OUTER JOIN sys.availability_groups ag
                ON asd.ag_id = ag.group_id
            LEFT OUTER JOIN sys.dm_hadr_database_replica_states dbrs
                ON asd.ag_db_id  = dbrs.group_database_id
                AND asd.ag_id = dbrs.group_id
            WHERE dbrs.is_primary_replica = 1 OR dbrs.is_primary_replica IS NULL
            ORDER BY start_time
            PRINT ''

            PRINT '-- AG_hadr_physical_seeding_stats --'
            SELECT 
                local_physical_seeding_id,
                remote_physical_seeding_id,
                local_database_id,
                local_database_name,
                remote_machine_name,
                role_desc,
                internal_state_desc,
                transfer_rate_bytes_per_second,
                transferred_size_bytes,
                database_size_bytes,
                start_time_utc,
                end_time_utc,
                estimate_time_complete_utc,
                total_disk_io_wait_time_ms,
                total_network_wait_time_ms,
                failure_code,
                failure_message,
                failure_time_utc,
                is_compression_enabled
            FROM sys.dm_hadr_physical_seeding_stats
        END
        PRINT ''


        SET QUOTED_IDENTIFIER ON

        DECLARE @XELFile VARCHAR(256)
        SELECT @XELFile = path + 'AlwaysOn_health*.xel' FROM sys.dm_os_server_diagnostics_log_configurations

        --read the AOHealth*.xel files into the table
        SELECT cast(event_data as XML) AS EventData
        INTO #AOHealth
        FROM sys.fn_xe_file_target_read_file(
        @XELFile, NULL, null, null);
        PRINT ''


        PRINT '-- AG_AlwaysOn_health_alwayson_ddl_executed --'
        SELECT TOP 500 
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data[@name=`"ddl_action`"]/text)[1]', 'varchar(10)') AS DDLAction,
        EventData.value('(event/data[@name=`"ddl_phase`"]/text)[1]', 'varchar(10)') AS DDLPhase,
        EventData.value('(event/data[@name=`"availability_group_name`"]/value)[1]', 'varchar(20)') AS AGName,
        CAST(REPLACE(REPLACE(EventData.value('(event/data[@name=`"statement`"]/value)[1]','varchar(max)'), CHAR(10), ''), CHAR(13), '') AS VARCHAR(256)) AS DDLStatement
        FROM #AOHealth
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'alwayson_ddl_executed'
            AND UPPER(EventData.value('(event/data[@name=`"statement`"]/value)[1]','varchar(max)')) NOT LIKE '%FAILOVER%'
        ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime') DESC;
        PRINT ''

        PRINT '-- AG_AlwaysOn_health_failovers --'
        SELECT TOP 500 
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data[@name=`"ddl_action`"]/text)[1]', 'varchar(10)') AS DDLAction,
        EventData.value('(event/data[@name=`"ddl_phase`"]/text)[1]', 'varchar(10)') AS DDLPhase,
        EventData.value('(event/data[@name=`"availability_group_name`"]/value)[1]', 'varchar(20)') AS AGName,
        CAST(REPLACE(REPLACE(EventData.value('(event/data[@name=`"statement`"]/value)[1]','varchar(max)'), CHAR(10), ''), CHAR(13), '') AS VARCHAR(256)) AS DDLStatement
        FROM #AOHealth
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'alwayson_ddl_executed'
            AND UPPER(EventData.value('(event/data[@name=`"statement`"]/value)[1]','varchar(max)')) LIKE '%FAILOVER%'
            AND UPPER(EventData.value('(event/data[@name=`"statement`"]/value)[1]','varchar(max)')) NOT LIKE 'CREATE%' -- filter out AG Create
        ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime') DESC
        OPTION (max_grant_percent = 3, MAXDOP 1);

        PRINT ''
        PRINT '-- AG_AlwaysOn_health_availability_replica_manager_state_change --'
        SELECT TOP 500 
        CONVERT(char(25), EventData.value('(event/@timestamp)[1]', 'datetime'), 121) AS TimeStampUTC,
        EventData.value('(event/data[@name=`"current_state`"]/text)[1]', 'varchar(30)') AS CurrentStateDesc
        FROM #AOHealth
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'availability_replica_manager_state_change'
        ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime') DESC
        OPTION (max_grant_percent = 3, MAXDOP 1);

        PRINT ''
        PRINT '-- AG_AlwaysOn_health_availability_replica_state_change --'
        SELECT TOP 500 
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data[@name=`"availability_group_name`"]/value)[1]', 'varchar(20)') AS AGName,
        EventData.value('(event/data[@name=`"previous_state`"]/text)[1]', 'varchar(30)') AS PrevStateDesc,
        EventData.value('(event/data[@name=`"current_state`"]/text)[1]', 'varchar(30)') AS CurrentStateDesc
        FROM #AOHealth
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'availability_replica_state_change'
        ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime') DESC
        OPTION (max_grant_percent = 3, MAXDOP 1);


        PRINT ''
        PRINT '-- AG_AlwaysOn_health_availability_group_lease_expired --'
        SELECT  TOP 500 
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,    
        EventData.value('(event/data[@name=`"availability_group_name`"]/value)[1]', 'varchar(20)') AS AGName,
        EventData.value('(event/data[@name=`"availability_group_id`"]/value)[1]', 'varchar(100)') AS AG_ID
        FROM #AOHealth
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'availability_group_lease_expired'
        ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime') DESC
        OPTION (max_grant_percent = 3, MAXDOP 1);


        SELECT  TOP 500 
        EventData.value('(event/@timestamp)[1]', 'datetime') AS TimeStampUTC,
        EventData.value('(event/data[@name=`"error_number`"]/value)[1]', 'int') AS ErrorNum,
        EventData.value('(event/data[@name=`"severity`"]/value)[1]', 'int') AS Severity,
        EventData.value('(event/data[@name=`"state`"]/value)[1]', 'int') AS State,
        EventData.value('(event/data[@name=`"user_defined`"]/value)[1]', 'varchar(max)') AS UserDefined,
        EventData.value('(event/data[@name=`"category`"]/text)[1]', 'varchar(max)') AS Category,
        EventData.value('(event/data[@name=`"destination`"]/text)[1]', 'varchar(max)') AS DestinationLog,
        EventData.value('(event/data[@name=`"is_intercepted`"]/value)[1]', 'varchar(max)') AS IsIntercepted,
        EventData.value('(event/data[@name=`"message`"]/value)[1]', 'varchar(max)') AS ErrMessage
        INTO #error_reported
        FROM #AOHealth
        WHERE EventData.value('(event/@name)[1]', 'varchar(max)') = 'error_reported'
        ORDER BY EventData.value('(event/@timestamp)[1]', 'datetime') DESC
        OPTION (max_grant_percent = 3, MAXDOP 1);

            --display results from `"error_reported`" event data
        PRINT ''
        PRINT '-- AG_AlwaysOn_health_error_reported --';	
        WITH ErrorCTE (ErrorNum, ErrorCount, FirstDate, LastDate) AS (
            SELECT ErrorNum, Count(ErrorNum), min(TimeStampUTC), max(TimeStampUTC) As ErrorCount FROM #error_reported
                GROUP BY ErrorNum) 
            SELECT CAST(ErrorNum as CHAR(10)) ErrorNum,
                CAST(ErrorCount as CHAR(10)) ErrorCount,
                CONVERT(CHAR(25), FirstDate,121) FirstDate,
                CONVERT(CHAR(25), LastDate, 121) LastDate,
                CAST(CASE ErrorNum 
                WHEN 35202 THEN 'A connection for availability group ... has been successfully established...'
                WHEN 1480 THEN 'The %S_MSG database `"%.*ls`" is changing roles ... because the AG failed over ...'
                WHEN 35206 THEN 'A connection timeout has occurred on a previously established connection ...'
                WHEN 35201 THEN 'A connection timeout has occurred while attempting to establish a connection ...'
                WHEN 41050 THEN 'Waiting for local WSFC service to start.'
                WHEN 41051 THEN 'Local WSFC service started.'
                WHEN 41052 THEN 'Waiting for local WSFC node to start.'
                WHEN 41053 THEN 'Local WSFC node started.'
                WHEN 41054 THEN 'Waiting for local WSFC node to come online.'
                WHEN 41055 THEN 'Local WSFC node is online.'
                WHEN 41048 THEN 'Local WSFC service has become unavailable.'
                WHEN 41049 THEN 'Local WSFC node is no longer online.'
                ELSE m.text END AS VARCHAR(81)) [Abbreviated Message]
                FROM
                ErrorCTE ec LEFT JOIN sys.messages m on ec.ErrorNum = m.message_id
                and m.language_id = 1033
            ORDER BY CAST(ErrorCount as INT) DESC
            OPTION (max_grant_percent = 3, MAXDOP 1);


        DROP TABLE #AOHealth
        DROP TABLE #error_reported
        PRINT ''
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
# MIIr5wYJKoZIhvcNAQcCoIIr2DCCK9QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCKFCn5dfk4SWni
# evNXy42kRb9wSuWRGEqFh+/KlgdVKqCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# fiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZzzCCGcsCAQEwWDBBMRMwEQYKCZIm
# iZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQDEwxBTUUg
# Q1MgQ0EgMDECEzYAAAIN4oQPSe7bLfwAAgAAAg0wDQYJYIZIAWUDBAIBBQCgga4w
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIOImoQYwcFXRd/9lHJDUs8lxZmEn19Ua
# rGteYlTPwlrMMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# KIIgP9DnYx2Hfic32MSx2gCHLYwidnIrbNtWemZXkgx5OKr97Aa5Jqrj9uUKbNFr
# nuPPUGAc9A5265kRvSKgcG2qc8u8EzhguNyeZrBKFsT4q0E/oF1tEh58TZNFUPQf
# D7fIfYEa4U1bMeqyuUD/6biEW5QDduPigpptG9xmOgmPnnpFaw1xeUyzHhazDXGV
# wTzkpu0kb/9WkS2XdvJzCaoEbhd1tKtMSu5INZZSZLGVoJEnodKmyLoIZ0ls61/j
# R2xB5tSjoZv7UJGArpB/VdDj4GpWPNwqyRlYPCqh0xs4TaikPK2hxOxnEUBp1/ZX
# 4jmvPCKAzYt60LIG3Bt1IaGCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCCF38GCSqG
# SIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCAS4XZnsbiCfs/On6qymEdXykNmnMniY5fMGG8vn9MxyAIGaW/bNTb6GBMyMDI2
# MDIwNDE2MzUyNy43NjdaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzMwMy0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHtMIIH
# IDCCBQigAwIBAgITMwAAAg9XmkcUQOZG5gABAAACDzANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQzMDRaFw0y
# NjA0MjIxOTQzMDRaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046MzMwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQCl6DTurxf66o73G0A2yKo1/nYvITBQsd50F52SQzo2cSrt+EDE
# FCDlSxZzWJD7ujQ1Z1dMbMT6YhK7JUvwxQ+LkQXv2k/3v3xw8xJ2mhXuwbT+s1WO
# L0+9g9AOEAAM6WGjCzI/LZq3/tzHr56in/Z++o/2soGhyGhKMDwWl4J4L1Fn8ndt
# oM1SBibPdqmwmPXpB9QtaP+TCOC1vAaGQOdsqXQ8AdlK6Vuk9yW9ty7S0kRP1nXk
# FseM33NzBu//ubaoJHb1ceYPZ4U4EOXBHi/2g09WRL9QWItHjPGJYjuJ0ckyrOG1
# ksfAZWP+Bu8PXAq4s1Ba/h/nXhXAwuxThpvaFb4T0bOjYO/h2LPRbdDMcMfS9Zbh
# q10hXP6ZFHR0RRJ+rr5A8ID9l0UgoUu/gNvCqHCMowz97udo7eWODA7LaVv81FHH
# Yw3X5DSTUqJ6pwP+/0lxatxajbSGsm267zqVNsuzUoF2FzPM+YUIwiOpgQvvjYIB
# kB+KUwZf2vRIPWmhAEzWZAGTox/0vj4eHgxwER9fpThcsbZGSxx0nL54Hz+L36KJ
# yEVio+oJVvUxm75YEESaTh1RnL0Dls91sBw6mvKrO2O+NCbUtfx+cQXYS0JcWZef
# 810BW9Bn/eIvow3Kcx0dVuqDfIWfW7imeTLAK9QAEk+oZCJzUUTvhh2hYQIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFJnUMQ2OtyAhLR/MD2qtJ9lKRP9ZMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQBTowbo1bUE7fXTy+uW9m58qGEXRBGVMEQiFEfSui1f
# hN7jS+kSiN0SR5Kl3AuV49xOxgHo9+GIne5Mpg5n4NS5PW8nWIWGj/8jkE3pdJZS
# vAZarXD4l43iMNxDhdBZqVCkAYcdFVZnxdy+25MRY6RfaGwkinjnYNFA6DYL/1cx
# w6Ya4sXyV7FgPdMmxVpffnPEDFv4mcVx3jvPZod7gqiDcUHbyV1gaND3PejyJ1MG
# fBYbAQxsynLX1FUsWLwKsNPRJjynwlzBT/OQbxnzkjLibi4h4dOwcN+H4myDtUSn
# Yq9Xf4YvFlZ+mJs5Ytx4U9JVCyW/WERtIEieTvTRgvAYj/4Mh1F2Elf8cdILgzi9
# ezqYefxdsBD8Vix35yMC5LTnDUoyVVulUeeDAJY8+6YBbtXIty4phIkihiIHsyWV
# xW2YGG6A6UWenuwY6z9oBONvMHlqtD37ZyLn0h1kCkkp5kcIIhMtpzEcPkfqlkbD
# VogMoWy80xulxt64P4+1YIzkRht3zTO+jLONu1pmBt+8EUh7DVct/33tuW5NOSx5
# 6jXQ1TdOdFBpgcW8HvJii8smQ1TQP42HNIKIJY5aiMkK9M2HoxYrQy2MoHNOPySs
# Ozr3le/4SDdX67uobGkUNerlJKzKpTR5ZU0SeNAu5oCyDb6gdtTiaN50lCC6m44s
# XjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
# BQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNV
# BAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4X
# DTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM
# 57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm
# 95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzB
# RMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBb
# fowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCO
# Mcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYw
# XE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW
# /aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/w
# EPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPK
# Z6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2
# BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfH
# CBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYB
# BAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8v
# BO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEF
# BQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBW
# BgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUH
# AQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# L2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsF
# AAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518Jx
# Nj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+
# iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2
# pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefw
# C2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7
# T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFO
# Ry3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhL
# mm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3L
# wUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5
# m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE
# 0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNQMIICOAIB
# ATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOjMzMDMtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBetIzj2C/M
# kdiI03EyNsCtSOMdWqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S104zAiGA8yMDI2MDIwNDA3MzM1NVoYDzIw
# MjYwMjA1MDczMzU1WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDtLXTjAgEAMAoC
# AQACAgXyAgH/MAcCAQACAhI6MAoCBQDtLsZjAgEAMDYGCisGAQQBhFkKBAIxKDAm
# MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcN
# AQELBQADggEBAJ+VvFSxMgzllskcLFsB+5h0qfksBk0jSo3bAVv+nyq4E3FdQTE0
# 4hXnrQVvVz5wubpyRBbgvHYiyVLEWf2eqoHHpDKlNUHWGD4p1ZIwcdibsAIdXXRS
# Z3fiQ38ZOTWzzJof9/ECGKoQkznJWsPbj9Btfl0vJKMCkkjkmZNxKWha6p4yepRD
# 52y+PEIhalexOZH+mVnvhmV0n05g7hfJwo0K8c8Uidg2yIb2muCs8rONn4sqIreE
# Gyr/2UL8VBsBFNoQQLYGB4l6Q3YAxvV8zDtT5U2oDJOqiqhpLYY61ZSfpuMpVTur
# voli0D7Buelj2e58AVCkv6VIfPIlg/VKbVMxggQNMIIECQIBATCBkzB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAg9XmkcUQOZG5gABAAACDzANBglg
# hkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
# SIb3DQEJBDEiBCBLRpGjXrxYkfx3jo7iqC5daTWMr6UpcEQyiRBejSTO9TCB+gYL
# KoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIN1Hd5UmKnm7FW7xP3niGsfHJt4xR8Xu
# +MxgXXc0iqn4MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAAIPV5pHFEDmRuYAAQAAAg8wIgQggJaC5NyYEeDBw8mhStN8P3YkXAq3/VI4
# oN2YoRc07jswDQYJKoZIhvcNAQELBQAEggIABB3a0qCMb1n9zrH9W8oz1fx98a7v
# q7RQIH+NXdpIKIaFgVWWFlJ7OUfz+hcb+J1DhtMBdg+fOtNweU2F9XPhEVW61yrE
# WTktuhrv2RSyreGu94794VlPs43GFMUsoQTnGtiz9s0HP8aW+m1gOHKgAs+f+/Sn
# 9PT9IcuJYm0GN7iRkpRc1vfA5FPzE2OukuGiiXaRJareBhsXwOv72rIz/ogfiZ0W
# MXMCv6Yj0QcFTiWd4DelDtn+VoHkZzwVbKVX3rE8FX7ELcJSEpO+r6SuNZ6oyU94
# A0GIZCfF1J31nFAKKDlLeK03q6GsgUOMppD8OWGkpH4B+JMgMWv/XAGsi2pzlmbQ
# SIpFXjTzRQnX5IlSDq2DMdxPkvzeSQ0ScrsxQ3WzygQcFwScHeqSHAqEob3mOOkA
# ByK67YcSOwUIEjrPwygldmHNegm7sLYycwtDE3npIuFRr7HU7+Sm5FPh9dJ/I67V
# AOsV1jTcMCZWTMo//0JgZoDv6FCxMqLruzXomsBKgA6fTV8dMoRk95fwm+B3vWCp
# cqI3dkoU9GZZSwAD+ofUq4HIMRoN4DIc4IEQwOmtzUJO+zUGZvOqrQPzCNKYoKw2
# PKcC7tAoT9srWXsXM6Uz1Bq9nhxAbx1AHshIqTH8eN+dYovLRSH/B7GvitxgFwOM
# TR9smlDOZyTvwEM=
# SIG # End signature block
