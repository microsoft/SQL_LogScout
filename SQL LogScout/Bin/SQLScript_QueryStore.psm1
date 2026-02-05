
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDVkVGW1GImqHcz
# nyn15CNGXo6RySTwi2bUiE8a62iXvaCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIE3PTSGiZtI9mhtt97LC0TnX3nOgR290
# kb+5CM7KlQA3MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# jyG2JfNwnpB0a2lMez/qeSnziLqPyGWpUG2qmbgZBGCKwgfz/oqs/UXbKI1Ht06q
# wmPRSak7FLoSI3ghTRvyk7KokWQ5RmaseyGM9xIpN8O12cS0ExLk3eybf4xDwRGm
# OSNU/WxgY94bhA6fHfD3M27Jl8JYwFquL+tQ7wnShFHNVLnqo7nu6h1Abg03xEoh
# RJXigwdHWgo9kQTv5Y0285kp8Dw6Hbl+PgqQBGGQpz+0WVyZghiOc404gEg18w7G
# LqFxJ6bBXkjaoj7cvCQqGZAoq09rEwBR6mK2wDVXfZX8o39IE+hONHwMRUg65tBc
# meufKVelUoF+wrT3Z+0BWqGCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCCF38GCSqG
# SIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCDR7eZSavA60qOIV0OwjqHfBURAfXxuI6dxda9zu/OG+AIGaW/bNTbzGBMyMDI2
# MDIwNDE2MzUyNy42NjRaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
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
# SIb3DQEJBDEiBCDmEG8IBttheZ0CSzUCdu2+oZz8cBFp3ByXIUbdlrPyZTCB+gYL
# KoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIN1Hd5UmKnm7FW7xP3niGsfHJt4xR8Xu
# +MxgXXc0iqn4MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAAIPV5pHFEDmRuYAAQAAAg8wIgQggJaC5NyYEeDBw8mhStN8P3YkXAq3/VI4
# oN2YoRc07jswDQYJKoZIhvcNAQELBQAEggIACA/NDnt7yAg2RM8K+Ry02KKo01K3
# KLLhYudB3UnLU7P7OxVDJkBd+uDgq4jQdw3bMNeqE/I3yoq4fKGSwurNbxfZAkaN
# dlkvpnI91z3dxc3EM77gvveDyz2U23iCz4WwlMV8+sKnjJCJ6FslLbiBBQOTAqX+
# oAuFOjsxu2Raynb4JHFhKKcXnyjEn8XVHV/M/2zQN5Q8uOdpp+pTZ+8Ezoxubcfl
# +sJd+2ae3iHBiYHVXTRrxSIdBpGogjGHP8R2cFZWZpxqrBtTInWXgpEpMQVOKFul
# Tp5qVRXTMQMMSa7y9QxlAG0aq/W4/m7i52wq8kd5r8ZtgKxpqgI5yfAtTZHxi4tP
# EQjztA3RnQsewq7kc1io6SmnGREwUjqJL9Pway3miYxMEbdk9TlOlbssz4R4VUDn
# 166WrLuD6343EU1CEoM4OEMgcOggwwJyVp4NK6ueDPWvnl/BD0xrcRbeSk2zs1sh
# 5Apgm9wCo+jh6dXpinbBkzV+oXNsSe03TIQjGVgy4/wowv7Q4hT5+30dYDO7fD9i
# 1H48MAIiw2k05Xt3K++hZ8hQQsYmOLhaxTf0NhHYul+aXjDJjbqtzl0Qq123yp2l
# 1WvZ7kDse0bLvmt8SYX6M+F1JCPuEfH8VLCfYkdFQzcjAu3uXhhgRSR4fDvwaD2n
# MfNkEeLD6LiSHjI=
# SIG # End signature block
