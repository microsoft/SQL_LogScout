
    function High_IO_Perfstats_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "High_IO_Perfstats"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
    use tempdb
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

    IF OBJECT_ID ('#sp_perf_virtual_file_stats','P') IS NOT NULL
    DROP PROCEDURE #sp_perf_virtual_file_stats
    GO
    CREATE PROCEDURE #sp_perf_virtual_file_stats @appname sysname='sqllogscout', @runtime DATETIME, @runtime_utc DATETIME
    AS
    SET NOCOUNT ON
    BEGIN
        BEGIN TRY
            PRINT ''
            PRINT '-- file_io_stats --'
            SELECT  CONVERT (VARCHAR(30), @runtime, 126) AS runtime, CONVERT (VARCHAR(30), @runtime_utc, 126) AS runtime_utc,
                    CONVERT(VARCHAR(40), DB_NAME(vfs.database_id)) AS DATABASE_NAME, physical_name AS Physical_Name,
                    size_on_disk_bytes / 1024 / 1024.0 AS File_Size_MB ,
                    CAST(io_stall_read_ms/(1.0 + num_of_reads) AS NUMERIC(10,1)) AS Average_Read_Latency,
                    CAST(io_stall_write_ms/(1.0 + num_of_writes) AS NUMERIC(10,1)) AS Average_Write_Latency,
                    num_of_bytes_read / NULLIF(num_of_reads, 0) AS Average_Bytes_Read,
                    num_of_bytes_written / NULLIF(num_of_writes, 0) AS Average_Bytes_Write
            FROM    sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
            JOIN sys.master_files AS mf 
                ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
            WHERE (CAST(io_stall_write_ms/(1.0 + num_of_writes) AS NUMERIC(10,1))> 15
                    OR (CAST(io_stall_read_ms/(1.0 + num_of_reads) AS NUMERIC(10,1))> 15))
            ORDER BY Average_Read_Latency DESC
            OPTION (max_grant_percent = 3, MAXDOP 1)

            --flush results to client
            RAISERROR (' ', 0, 1) WITH NOWAIT
        END TRY
        BEGIN CATCH
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
        PRINT 'Msg ' + isnull(cast(Error_Number() AS NVARCHAR(50)), '') + ', Level ' + isnull(cast(Error_Severity() AS NVARCHAR(50)),'') + ', State ' + isnull(cast(Error_State() AS NVARCHAR(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() AS NVARCHAR(50)),'') + CHAR(10) +  Error_Message() + CHAR(10);
        END CATCH
    END
    GO

    IF OBJECT_ID ('#sp_perf_io_snapshots','P') IS NOT NULL
    DROP PROCEDURE #sp_perf_io_snapshots
    GO
    CREATE PROCEDURE #sp_perf_io_snapshots @appname sysname='sqllogscout', @runtime DATETIME, @runtime_utc DATETIME
    AS
    SET NOCOUNT ON
    BEGIN
        BEGIN TRY

            DECLARE @msg VARCHAR(100)
            IF NOT EXISTS (SELECT * FROM sys.dm_exec_requests req left outer join sys.dm_exec_sessions sess
                            on req.session_id = sess.session_id
                            WHERE req.session_id <> @@SPID AND ISNULL (sess.host_name, '') != @appname and is_user_process = 1) 
            BEGIN
                PRINT 'No active queries'
            END
            ELSE 
            BEGIN
                IF @runtime IS NULL or @runtime_utc IS NULL
                BEGIN 
                    SET @runtime = GETDATE()
                    SET @runtime_utc = GETUTCDATE()
                END
                    
                PRINT ''
                PRINT '--  high_io_queries --'

                select	CONVERT (VARCHAR(30), @runtime, 126) AS runtime, CONVERT (VARCHAR(30), @runtime_utc, 126) AS runtime_utc, req.session_id, req.start_time AS request_start_time, req.cpu_time, req.total_elapsed_time, req.logical_reads,
                        req.status, req.command, req.wait_type, req.wait_time, req.scheduler_id, req.granted_query_memory, tsk.task_state, tsk.context_switches_count,
                        replace(replace(substring(ISNULL(SQLText.text, ''),1,1000),CHAR(10), ' '),CHAR(13), ' ')  AS batch_text, 
                        ISNULL(sess.program_name, '') AS program_name, ISNULL (sess.host_name, '') AS Host_name, ISNULL(sess.host_process_id,0) AS session_process_id, 
                        ISNULL (conn.net_packet_size, 0) AS 'net_packet_size', LEFT (ISNULL (conn.client_net_address, ''), 20) AS 'client_net_address',
                        substring
                        (REPLACE
                        (REPLACE
                            (SUBSTRING
                            (SQLText.text
                            , (req.statement_start_offset/2) + 1 
                            , (
                                (CASE statement_END_offset
                                    WHEN -1
                                    THEN DATALENGTH(SQLText.text)  
                                    ELSE req.statement_END_offset
                                    END
                                    - req.statement_start_offset)/2) + 1)
                        , CHAR(10), ' '), CHAR(13), ' '), 1, 512)  AS active_statement_text 
                FROM sys.dm_exec_requests req
                    LEFT OUTER JOIN sys.dm_exec_connections conn 
                        ON conn.session_id = req.session_id
                        AND conn.net_transport <> 'session'
                    OUTER APPLY sys.dm_exec_sql_text (ISNULL (req.sql_handle, conn.most_recent_sql_handle)) AS SQLText
                    LEFT OUTER JOIN sys.dm_exec_sessions sess on conn.session_id = sess.session_id
                    LEFT OUTER JOIN sys.dm_os_tasks tsk on sess.session_id = tsk.session_id
                WHERE sess.is_user_process = 1
                AND  wait_type IN ( 'PAGEIOLATCH_SH', 'PAGEIOLATCH_EX', 'PAGEIOLATCH_UP',	'WRITELOG','IO_COMPLETION','ASYNC_IO_COMPLETION' )
                    AND wait_time >= 15
                ORDER BY req.logical_reads desc  
                OPTION (max_grant_percent = 3, MAXDOP 1)
                
                PRINT  ''
                PRINT  '--  sys.dm_io_pending_io_requests --'
            
                DECLARE @sql_major_version INT, @sql_major_build INT, @sql NVARCHAR (max)
                
                SELECT @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)), 4) AS INT))
                    
                SET @sql = N'SELECT CONVERT (VARCHAR(30), @runtime, 121) AS runtime
                                ,[io_completion_request_address]
                                ,[io_type]
                                ,[io_pending_ms_ticks]
                                ,[io_pending]
                                ,[io_completion_routine_address]
                                ,[io_user_data_address]
                                ,[scheduler_address]
                                ,[io_handle]
                                ,[io_offset]
                            '
                IF (@sql_major_version >=12)
                BEGIN
                SET @sql = @sql + N',[io_handle_path]'
                END
                
                SET @sql = @sql + N' FROM sys.dm_io_pending_io_requests'
                    
                
                EXECUTE sp_executesql @sql,
                                    N'@runtime DATETIME',
                                    @runtime = @runtime;
                        
                --flush results to client
                RAISERROR (' ', 0, 1) WITH NOWAIT


            END
        
        END TRY
        BEGIN CATCH
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
        PRINT 'Msg ' + isnull(cast(Error_Number() AS NVARCHAR(50)), '') + ', Level ' + isnull(cast(Error_Severity() AS NVARCHAR(50)),'') + ', State ' + isnull(cast(Error_State() AS NVARCHAR(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() AS NVARCHAR(50)),'') + CHAR(10) +  Error_Message() + CHAR(10);
        END CATCH
    END
    GO

    if object_id ('#sp_run_high_io_perfstats','p') IS NOT NULL
    DROP PROCEDURE #sp_run_high_io_perfstats
    GO
    CREATE PROCEDURE #sp_run_high_io_perfstats 
    AS
        BEGIN TRY
        -- Main loop

            PRINT 'starting high io perf stats script...'
            SET LANGUAGE us_english
            PRINT '-- script source --'
            SELECT 'high io perf stats script' AS script_name
            PRINT ''
            PRINT '-- script and environment details --'
            PRINT 'name                     value'
            PRINT '------------------------ ---------------------------------------------------'
            PRINT 'sql server name          ' + @@servername
            PRINT 'machine name             ' + convert (VARCHAR, serverproperty ('machinename'))
            PRINT 'sql version (sp)         ' + convert (VARCHAR, serverproperty ('productversion')) + ' (' + convert (VARCHAR, serverproperty ('productlevel')) + ')'
            PRINT 'edition                  ' + convert (VARCHAR, serverproperty ('edition'))
            PRINT 'script begin time        ' + convert (VARCHAR(30), getdate(), 126) 
            PRINT 'current database         ' + db_name()
            PRINT '@@spid                   ' + ltrim(str(@@spid))
            PRINT ''

            DECLARE @runtime DATETIME, @runtime_utc DATETIME, @prevruntime DATETIME
            DECLARE @msg VARCHAR(100)
            DECLARE @counter BIGINT
            SELECT @prevruntime = sqlserver_start_time FROM sys.dm_os_sys_info

            --SET prevtime to 5 min earlier, in case SQL just started
            SET @prevruntime = DATEADD(SECOND, -300, @prevruntime)
            SET @counter = 0

            WHILE (1=1)
            BEGIN
                BEGIN TRY
                    SET @runtime = GETDATE()
                    SET @runtime_utc = GETUTCDATE()
                    --SET @msg = 'Start time: ' + CONVERT (VARCHAR(30), @runtime, 126)

                    PRINT ''
                    RAISERROR (@msg, 0, 1) WITH NOWAIT
                
                    if (@counter % 6 = 0)  -- capture this data every 1 minute
                    BEGIN
                        EXEC #sp_perf_virtual_file_stats 'sqllogscout', @runtime = @runtime, @runtime_utc = @runtime_utc
                    END
                    
                    -- Collect sp_perf_high_io_snapshot every 3 minutes
                    EXEC #sp_perf_io_snapshots 'sqllogscout', @runtime = @runtime, @runtime_utc = @runtime_utc
                    SET @prevruntime = @runtime
                    WAITFOR DELAY '0:00:10'
                    SET @counter = @counter + 1
                END TRY		
                BEGIN CATCH
                    PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
                    PRINT 'Msg ' + isnull(cast(Error_Number() AS NVARCHAR(50)), '') + ', Level ' + isnull(cast(Error_Severity() AS NVARCHAR(50)),'') + ', State ' + isnull(cast(Error_State() AS NVARCHAR(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() AS NVARCHAR(50)),'') + CHAR(10) +  Error_Message() + CHAR(10);
                END CATCH			
            END
        END TRY
        BEGIN CATCH
            PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
            PRINT 'Msg ' + isnull(cast(Error_Number() AS NVARCHAR(50)), '') + ', Level ' + isnull(cast(Error_Severity() AS NVARCHAR(50)),'') + ', State ' + isnull(cast(Error_State() AS NVARCHAR(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() AS NVARCHAR(50)),'') + CHAR(10) +  Error_Message() + CHAR(10);
        END CATCH	
    GO

    EXEC #sp_run_high_io_perfstats
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
# MIIr5AYJKoZIhvcNAQcCoIIr1TCCK9ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBZZlYcxA9RL4Ac
# BO1QFxeMjTn0kyLO2WfKEfpd5ehgl6CCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# fiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZzDCCGcgCAQEwWDBBMRMwEQYKCZIm
# iZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQDEwxBTUUg
# Q1MgQ0EgMDECEzYAAAIN4oQPSe7bLfwAAgAAAg0wDQYJYIZIAWUDBAIBBQCgga4w
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEID52OWsEBKIYuQ0A2UO8fSPk1FyuxXXF
# ASjTiYgXocPsMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# c6i8TmRo7WWTrtlGmx8D1E0iqTjnDuGYhwmGftyrtT8AIn4+tgKc0xP6KPRGPG9/
# 1NpMAPqol0DoZ5bQbpxF1wt9D3V8znXHWNHrdfH4xOYXuRvIIqkEge7BvDv9U/4r
# 1f0DXH/tCN2z6cUkzMNbhgrCiDb1kX1bst1aa7dXdbkVHzdDPQHKOFKY0i60Sa5B
# D+kLiP8equ9fY0qeezW7n5xNxcosC0X+Ncs62PAxyylHDOhxI5A5hXPweOTsyxBp
# F5kR/OBtuCMsI4CYic0PQQFGSt6pdMK/gO4DJzE8SO2oExX4rmKTd4UyCEwy3mlc
# /2z95pNrj7HXDvjv3l1xZaGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCB1oLmFTiDV4Yq1kpqiTbYgRw50pOHrg0Rx2AgbrQ9n3wIGaWkVtLVJGBMyMDI2
# MDIwNDE2MzUyOC4xNjlaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIH
# IDCCBQigAwIBAgITMwAAAgh4nVhdksfZUgABAAACCDANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNTNaFw0y
# NjA0MjIxOTQyNTNaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQC1y3AI5lIz3Ip1nK5BMUUbGRsjSnCz/VGs33zvY0NeshsPgfld
# 3/Z3/3dS8WKBLlDlosmXJOZlFSiNXUd6DTJxA9ik/ZbCdWJ78LKjbN3tFkX2c6RR
# pRMpA8sq/oBbRryP3c8Q/gxpJAKHHz8cuSn7ewfCLznNmxqliTk3Q5LHqz2PjeYK
# D/dbKMBT2TAAWAvum4z/HXIJ6tFdGoNV4WURZswCSt6ROwaqQ1oAYGvEndH+DXZq
# 1+bHsgvcPNCdTSIpWobQiJS/UKLiR02KNCqB4I9yajFTSlnMIEMz/Ni538oGI64p
# hcvNpUe2+qaKWHZ8d4T1KghvRmSSF4YF5DNEJbxaCUwsy7nULmsFnTaOjVOoTFWW
# fWXvBuOKkBcQKWGKvrki976j4x+5ezAP36fq3u6dHRJTLZAu4dEuOooU3+kMZr+R
# BYWjTHQCKV+yZ1ST0eGkbHXoA2lyyRDlNjBQcoeZIxWCZts/d3+nf1jiSLN6f6wd
# HaUz0ADwOTQ/aEo1IC85eFePvyIKaxFJkGU2Mqa6Xzq3qCq5tokIHtjhogsrEgfD
# KTeFXTtdhl1IPtLcCfMcWOGGAXosVUU7G948F6W96424f2VHD8L3FoyAI9+r4zyI
# QUmqiESzuQWeWpTTjFYwCmgXaGOuSDV8cNOVQB6IPzPneZhVTjwxbAZlaQIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFKMx4vfOqcUTgYOVB9f18/mhegFNMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQBRszKJKwAfswqdaQPFiaYB/ZNAYWDa040XTcQsCaCu
# a5nsG1IslYaSpH7miTLr6eQEqXczZoqeOa/xvDnMGifGNda0CHbQwtpnIhsutrKO
# 2jhjEaGwlJgOMql21r7Ik6XnBza0e3hBOu4UBkMl/LEX+AURt7i7+RTNsGN0cXPw
# PSbTFE+9z7WagGbY9pwUo/NxkGJseqGCQ/9K2VMU74bw5e7+8IGUhM2xspJPqnSe
# HPhYmcB0WclOxcVIfj/ZuQvworPbTEEYDVCzSN37c0yChPMY7FJ+HGFBNJxwd5lK
# Ir7GYfq8a0gOiC2ljGYlc4rt4cCed1XKg83f0l9aUVimWBYXtfNebhpfr6Lc3jD8
# NgsrDhzt0WgnIdnTZCi7jxjsIBilH99pY5/h6bQcLKK/E6KCP9E1YN78fLaOXkXM
# yO6xLrvQZ+uCSi1hdTufFC7oSB/CU5RbfIVHXG0j1o2n1tne4eCbNfKqUPTE31tN
# bWBR23Yiy0r3kQmHeYE1GLbL4pwknqaip1BRn6WIUMJtgncawEN33f8AYGZ4a3Nn
# HopzGVV6neffGVag4Tduy+oy1YF+shChoXdMqfhPWFpHe3uJGT4GJEiNs4+28a/w
# HUuF+aRaR0cN5P7XlOwU1360iUCJtQdvKQaNAwGI29KOwS3QGriR9F2jOGPUAlpe
# EzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
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
# 0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIICNQIB
# ATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOkEwMDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCNkvu0NKcS
# jdYKyrhJZcsyXOUTNKCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S3vjzAiGA8yMDI2MDIwNDE2MTcxOVoYDzIw
# MjYwMjA1MTYxNzE5WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDtLe+PAgEAMAcC
# AQACAhicMAcCAQACAhIdMAoCBQDtL0EPAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEL
# BQADggEBAHPhG5SbcC6Gg67QIzRV9Ef6w9MO9/GGCWiXkb8ac9gVYxvj3do+xAp3
# j81oqGZ0LKLUDjFop3zwI9SMhpkq1AA+oR1iW7WU+JOsiF3C8sQqGNLJDLnwnS9v
# MUdA4MyudyV9HyDuUiUX7Jrg8wjw2JZtai3cuXyJjefkUFL/cXCaP5yfE+Qt3Hri
# Jn8uUt3gBz3HS785GGntsKGYgwOqsM4fyqj1ihG4nLIFKHW8Kcg0JsAb6jTrjkQV
# VWMhftZ3HWOgXRiId8DJSrX0frzYsFCNKix1Ba3xUpGfhp6d27V1YEJssMi4emz4
# CjzW8vzfxc6uDpSnNwM7bvWthRie2OcxggQNMIIECQIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAgh4nVhdksfZUgABAAACCDANBglghkgB
# ZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCAjCEt3KF4BZUtub7b92NvEQhW8gtty8/+yxBUcY3oLyTCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EII//jm8JHa2W1O9778t9+Ft2Z5NmKqttPk6Q
# +9RRpmepMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIIeJ1YXZLH2VIAAQAAAggwIgQgxKH5b/AUp9X5FgKyUEZcCow4aoM3ixkp1myS
# y5BFtPswDQYJKoZIhvcNAQELBQAEggIAhFbjbSbXQVCgDntSFg2tfIDBK99MxKRn
# yZzHdMl2bYlgoovumsYqVcFBTnBqrEGTwqs+4yHbkG0sVA/NCfi7U8x9MMI3J7rE
# Pn/4T+OI//ziSFYtDfdh2ZnB7kA6K45GGI9o7vO0noME7on+aQY9xVBcuoy5wpKJ
# 7uUa0H7FV/W1XuEhc+WURKTn1aLvDLc5S55KIvt35ZJiMvIpgy3igJESwnBqV1ku
# 5lOn6jtSf8YYQBKWvUL/rovOa9MBQfzSZ+kdCAJc5uVrdm0IfqzKw3Yxwfd9kLVV
# rDGVMpt93rnZ0WlKRwgGyk6oH4Iy346fR8pDhk3dO+ihDponuHGAyRDUwIOBiVSU
# /AH0oqhM76do9toBve4EvSgu9tdN/I/ry3qWKCX4trZyOv3BVVIQLHv4LYWDHLJB
# 5MLmTEnm+nDnoXWVN/PzE0noVZYaFqt5LnurttEScvYIPJDIxAu69Ce9qyWPfANF
# 8TMOyrNNpPkKKLGSVrzYl2QP/N4eN/0mkQgVRnuXcggPMxCmUg6l6venByFwHNGV
# CwHGtMGtsP+1CEnMo5eBYPsMwrBRGVgLzOS10Ms1VWMKpYEp51XWWTlyPo94el/8
# u0h3a5UieYWDe8u1iN8DpSwh/xyVpfci7ktgRU+eK6Xhrga9S9kaQ21gB+uyHCUh
# kmfUL9nzcic=
# SIG # End signature block
