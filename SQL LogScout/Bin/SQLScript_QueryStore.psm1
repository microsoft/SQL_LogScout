
    function QueryStore_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "QueryStore"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
        SET NOCOUNT ON
        DECLARE @sql_major_version INT
        SELECT  @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT))

        -- if SQL version is 2016 or later we capture Query Store information
        -- otherwise just print a message informing version to be older
        IF @sql_major_version >= 13
        BEGIN

            IF OBJECT_ID ('tempdb..#qsdbs') IS NOT NULL
            BEGIN
                DROP TABLE #qsdbs 
            END

            CREATE TABLE #qsdbs (name sysname NOT NULL)

            -- EXECute the SELECT on sys.databases dynamically, otherwise binding fails due to missing column is_query_store_on on SQL older than 2016
            EXEC('INSERT INTO #qsdbs (name) SELECT name FROM sys.databases where state_desc=''ONLINE'' and user_access_desc=''MULTI_USER'' and is_query_store_on = 1')
            
            DECLARE @dbname sysname
            DECLARE dbname_cursor CURSOR for SELECT name FROM #qsdbs
            DECLARE @sql1 NVARCHAR(max) = 'SELECT db_id() dbid, db_name() dbname, * FROM sys.query_store_runtime_stats_interval where start_time > dateadd (dd,-7, getdate())'
            DECLARE @sql2 NVARCHAR(max) = 'SELECT db_id() dbid, db_name() dbname, * FROM sys.query_store_runtime_stats where runtime_stats_interval_id in (SELECT runtime_stats_interval_id FROM sys.query_store_runtime_stats_interval where start_time > dateadd (dd,-7, getdate()))'
            DECLARE @sql3 NVARCHAR(max) ='SELECT db_id() dbid, db_name() dbname, * FROM   sys.query_store_query '
            DECLARE @sql4 NVARCHAR(max) = 'SELECT db_id() dbid, db_name() dbname, query_text_id, statement_sql_handle, is_part_of_encrypted_module, has_restricted_text, substring (REPLACE (REPLACE (query_sql_text,CHAR(13), '' ''), CHAR(10), '' ''), 1, 256)  as  query_sql_text FROM sys.query_store_query_text'
            DECLARE @sql5 NVARCHAR(max) = 'SELECT db_id() dbid, db_name() dbname, plan_id, query_id, plan_group_id, engine_version, compatibility_level, query_plan_hash, is_forced_plan, force_failure_count, last_force_failure_reason_desc FROM sys.query_store_plan'
            DECLARE @sql6 NVARCHAR(max) ='SELECT db_id() dbid, db_name() dbname, * FROM sys.database_query_store_options'
            

            -- only on SQL 2017+
            IF @sql_major_version >= 14
            BEGIN
                DECLARE @sql7 NVARCHAR(max) ='SELECT db_id() dbid, db_name() dbname, * FROM sys.query_store_wait_stats'
                SET @sql5 = 'SELECT db_id() dbid, db_name() dbname, plan_id, query_id, plan_group_id, engine_version, compatibility_level, query_plan_hash, is_forced_plan, force_failure_count, last_force_failure_reason_desc, plan_forcing_type_desc FROM sys.query_store_plan'		
            -- Get sys.dm_db_tuning_recommendations table for auto tuning recommendations.
                DECLARE @sql11 NVARCHAR(max) = 
                'SELECT reason, score, planForceDetails.*,
                    estimated_gain = (regressedPlanExecutionCount + recommendedPlanExecutionCount) * (regressedPlanCpuTimeAverage - recommendedPlanCpuTimeAverage)/1000000,
                    error_prone = IIF(regressedPlanErrorCount > recommendedPlanErrorCount, ''YES'',''NO'')
                FROM sys.dm_db_tuning_recommendations
                CROSS APPLY OPENJSON (Details, ''`$.planForceDetails'')
                WITH (  [query_id] int ''`$.queryId'',
                        regressedPlanId int ''`$.regressedPlanId'',
                        recommendedPlanId int ''`$.recommendedPlanId'',
                        regressedPlanErrorCount int,
                        recommendedPlanErrorCount int,
                        regressedPlanExecutionCount int,
                        regressedPlanCpuTimeAverage float,
                        recommendedPlanExecutionCount int,
                        recommendedPlanCpuTimeAverage float
                    ) AS planForceDetails;'	
            END
            -- only on SQL 2022+
            IF @sql_major_version >= 16
            BEGIN
                DECLARE @sql8 NVARCHAR(max) ='SELECT db_id() dbid, db_name() dbname, * FROM sys.query_store_query_hints'
                DECLARE @sql9 NVARCHAR(max) ='SELECT db_id() dbid, db_name() dbname, * FROM sys.query_store_plan_feedback'
                DECLARE @sql10 NVARCHAR(max) ='SELECT db_id() dbid, db_name() dbname, * FROM sys.query_store_query_variant'
            END

            DECLARE @sql NVARCHAR(max)
            OPEN dbname_cursor
            FETCH NEXT FROM dbname_cursor INTO @dbname 
            WHILE @@FETCH_STATUS = 0

            BEGIN
                PRINT 'DATABASE: ''' + @dbname + ''''
                PRINT '============================='
                PRINT ''

                RAISERROR ('--sys.query_store_runtime_stats_interval--', 0, 1) WITH NOWAIT
                SET @sql = N'use [' + @dbname + '] ' + @sql1
                EXEC (@sql)
                RAISERROR (' ', 0, 1) WITH NOWAIT

                RAISERROR ('--sys.query_store_runtime_stats--', 0, 1) WITH NOWAIT
                SET @sql = N'use [' + @dbname + '] ' + @sql2
                EXEC (@sql)
                RAISERROR (' ', 0, 1) WITH NOWAIT

                RAISERROR ('--sys.query_store_query--', 0, 1) WITH NOWAIT
                SET @sql = N'use [' + @dbname + '] ' + @sql3
                EXEC (@sql)
                RAISERROR (' ', 0, 1) WITH NOWAIT

                RAISERROR ('--sys.query_store_query_text--', 0, 1) WITH NOWAIT
                SET @sql = N'use [' + @dbname + '] ' + @sql4
                EXEC (@sql)
                RAISERROR (' ', 0, 1) WITH NOWAIT

                RAISERROR ('--sys.query_store_plan--', 0, 1) WITH NOWAIT
                SET @sql = N'use [' + @dbname + '] ' + @sql5
                EXEC (@sql)
                RAISERROR (' ', 0, 1) WITH NOWAIT

                RAISERROR ('--sys.database_query_store_options--', 0, 1) WITH NOWAIT
                SET @sql = N'use [' + @dbname + '] ' + @sql6
                EXEC (@sql)
                RAISERROR (' ', 0, 1) WITH NOWAIT

                IF @sql_major_version >= 14
                BEGIN
                    RAISERROR ('--sys.query_store_wait_stats--', 0, 1) WITH NOWAIT
                    SET @sql = N'use [' + @dbname + '] ' + @sql7
                    EXEC (@sql)
                    RAISERROR (' ', 0, 1) WITH NOWAIT

        -- Get sys.dm_db_tuning_recommendations table for auto tuning recommendations.
                    RAISERROR ('--sys.dm_db_tuning_recommendations--', 0, 1) WITH NOWAIT
                    SET @sql = N'use [' + @dbname + '] ' + @sql11
                    EXEC (@sql)
                    RAISERROR (' ', 0, 1) WITH NOWAIT
                END

                IF @sql_major_version >= 16
                BEGIN
                    RAISERROR ('--sys.query_store_query_hints--', 0, 1) WITH NOWAIT
                    SET @sql = N'use [' + @dbname + '] ' + @sql8
                    EXEC (@sql)
                    RAISERROR (' ', 0, 1) WITH NOWAIT

                    RAISERROR ('--sys.query_store_plan_feedback--', 0, 1) WITH NOWAIT
                    SET @sql = N'use [' + @dbname + '] ' + @sql9
                    EXEC (@sql)
                    RAISERROR (' ', 0, 1) WITH NOWAIT

                    RAISERROR ('--sys.query_store_query_variant--', 0, 1) WITH NOWAIT
                    SET @sql = N'use [' + @dbname + '] ' + @sql10
                    EXEC (@sql)
                    RAISERROR (' ', 0, 1) WITH NOWAIT

                END

                
                FETCH NEXT FROM dbname_cursor INTO @dbname 
            END

            CLOSE dbname_cursor
            DEALLOCATE dbname_cursor


        END
        ELSE
        BEGIN
            PRINT 'Skipped capturing Query Store information. SQL Server build version older than SQL Server 2016.'
        END
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

    
