
    function NeverEndingQuery_perfstats_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "NeverEndingQuery_perfstats"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
use tempdb
go
IF OBJECT_ID ('dbo.sp_perf_never_ending_query_snapshots','P') IS NOT NULL
   DROP PROCEDURE dbo.sp_perf_never_ending_query_snapshots
GO

CREATE PROCEDURE dbo.sp_perf_never_ending_query_snapshots @appname sysname='SqlLogScout'
AS
SET NOCOUNT ON

DECLARE @cpu_threshold_ms int = 60000

BEGIN TRY
 
  DECLARE @msg varchar(100)
 
  IF EXISTS (SELECT * FROM sys.dm_exec_requests req left outer join sys.dm_exec_sessions sess
 				on req.session_id = sess.session_id
 				WHERE req.session_id <> @@SPID AND ISNULL (sess.host_name, '') != @appname and sess.is_user_process = 1 AND req.cpu_time > @cpu_threshold_ms) 
 					
  BEGIN
     
 	DECLARE @runtime datetime = GETDATE(), @runtime_utc datetime = GETUTCDATE()
     --SET @msg = 'Start time: ' + CONVERT (varchar(30), @runtime, 126)
     RAISERROR (@msg, 0, 1) WITH NOWAIT
 
 	
 	PRINT ''
 	RAISERROR ('-- neverending_query --', 0, 1) WITH NOWAIT
 
    --query the DMV in a loop to compare the 
    SELECT CONVERT(VARCHAR(30), @runtime, 126) AS runtime,
           CONVERT(VARCHAR(30), @runtime_utc, 126) AS runtime_utc,
           qp.session_id,
           convert(NVARCHAR(48), qp.physical_operator_name) AS physical_operator_name,
           qp.row_count,
           qp.estimate_row_count,
           qp.node_id,
           req.cpu_time,
           req.total_elapsed_time,
           SUBSTRING(REPLACE(REPLACE(SUBSTRING(SQLText.text, (req.statement_start_offset / 2) + 1, (
           					(
           						CASE statement_END_offset
           							WHEN - 1
           								THEN DATALENGTH(SQLText.text)
           							ELSE req.statement_END_offset
           							END - req.statement_start_offset
           						) / 2
           					) + 1), CHAR(10), ' '), CHAR(13), ' '), 1, 512) AS active_statement_text,
           qp.rewind_count,
           qp.rebind_count,
           qp.end_of_scan_count,
           replace(replace(substring(ISNULL(SQLText.text, ''), 1, 150), CHAR(10), ' '), CHAR(13), ' ') AS batch_text
    FROM sys.dm_exec_query_profiles qp
    RIGHT OUTER JOIN sys.dm_exec_requests req ON qp.session_id = req.session_id
    LEFT OUTER JOIN sys.dm_exec_sessions sess ON req.session_id = sess.session_id
    LEFT OUTER JOIN sys.dm_exec_connections conn ON conn.session_id = req.session_id
    	AND conn.net_transport <> 'session'
    OUTER APPLY sys.dm_exec_sql_text(ISNULL(req.sql_handle, conn.most_recent_sql_handle)) AS SQLText
    WHERE req.session_id <> @@SPID
    	AND ISNULL(sess.host_name, '') != @appname
    	AND sess.is_user_process = 1
    	AND req.cpu_time > @cpu_threshold_ms
    ORDER BY qp.session_id,
    	qp.node_id
    --this is to prevent massive grants
    OPTION (max_grant_percent = 3,MAXDOP 1)
     
 	--flush results to client
 	RAISERROR (' ', 0, 1) WITH NOWAIT
 
  END
END TRY
BEGIN CATCH
  PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
  PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
END CATCH
GO

IF OBJECT_ID ('dbo.sp_Run_NeverEndingQuery_Stats','P') IS NOT NULL
   DROP PROCEDURE dbo.sp_Run_NeverEndingQuery_Stats
GO

CREATE PROCEDURE dbo.sp_Run_NeverEndingQuery_Stats
as
SET NOCOUNT ON

PRINT 'starting query never seems to complete perf stats script...'
SET language us_english
PRINT '-- script source --'
SELECT 'query never completes stats script' as script_name
PRINT ''
PRINT '-- script and environment details --'
PRINT 'name                     value'
PRINT '------------------------ ---------------------------------------------------'
PRINT 'sql server name          ' + @@servername
PRINT 'machine name             ' + convert (varchar, serverproperty ('machinename'))
PRINT 'sql version (sp)         ' + convert (varchar, serverproperty ('productversion')) + ' (' + convert (varchar, serverproperty ('productlevel')) + ')'
PRINT 'edition                  ' + convert (varchar, serverproperty ('edition'))
PRINT 'script name              Query Never Completes stats script'
PRINT 'script file name         `$file: QueryNeverCompletes_perfstats.sql `$'
PRINT 'last modified            `$date: 2021/09/07  `$'
PRINT 'script begin time        ' + convert (varchar(30), getdate(), 126) 
PRINT 'current database         ' + db_name()
PRINT '@@spid                   ' + ltrim(str(@@spid))


--handle SQL Server 2008 code line, thus need to parse ProductVersion
DECLARE @servermajorversion int
SET @servermajorversion = CONVERT (INT, (REPLACE (LEFT (CONVERT (nvarchar, SERVERPROPERTY ('ProductVersion')), 2), '.', '')))

IF (@servermajorversion < 12)
BEGIN
    RAISERROR ('Lightweight Profiling    SQL Server version is less than 2014. No additional data can be collected', 0, 1) WITH NOWAIT
	PRINT ''
    RETURN
END

DECLARE @serverbuild INT
SET @serverbuild = CONVERT (int, SERVERPROPERTY ('ProductBuild'))

--minimum build 12.0.5000.0 , see https://docs.microsoft.com/en-us/sql/relational-databases/performance/query-profiling-infrastructure?view=sql-server-ver15
IF (@servermajorversion <= 12 and @serverbuild < 5000)
BEGIN
    RAISERROR ('Lightweight Profiling    Your SQL Sever version does not support collecting real-time perf stats on long-running query', 0, 1) WITH NOWAIT
	PRINT ''
END
--13.0.4001.0 (SP1)
ELSE IF ((@servermajorversion = '13' and @serverbuild <4001) or (@servermajorversion = 12 and @serverbuild >= 5000))
BEGIN
	RAISERROR ('Lightweight Profiling    Using Lightweight Profiling Ver1 requires that you enable SET STATISTICS PROFILE ON in the same session where the query runs', 0, 1) WITH NOWAIT
	PRINT ''
	PRINT 'See https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-query-profiles-transact-sql#examples for more information'
	PRINT ''
END
ELSE IF ((@servermajorversion = '13' and @serverbuild >=4001) or @servermajorversion = '14')
BEGIN
    RAISERROR ('Lightweight Profiling    SQL 2016 SP1+ or 2017. Using Lightweight Profiling Ver2', 0, 1) WITH NOWAIT
	PRINT ''
	PRINT 'Enabling TF 7412'
		IF (OBJECT_ID('tempdb.dbo.original_config_tf_7412')) IS NULL
		BEGIN
			CREATE TABLE tempdb.dbo.original_config_tf_7412 ([ID] [bigint] IDENTITY(1,1) NOT NULL,[TraceFlag] INT, Status INT, Global INT, Session INT)
		END
		INSERT INTO tempdb.dbo.original_config_tf_7412 EXEC('DBCC TRACESTATUS (7412)')
		IF EXISTS (SELECT 1 FROM tempdb.dbo.original_config_tf_7412 WHERE GLOBAL = 0 AND TraceFlag = 7412) DBCC TRACEON (7412, -1)

    WHILE (1=1)
	BEGIN
      BEGIN TRY
        --query the DMV in a loop to compare the 
		EXEC dbo.sp_perf_never_ending_query_snapshots @appname = 'SqlLogScout'
        WAITFOR DELAY '00:00:10'
      END TRY
      BEGIN CATCH
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
        PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
      END CATCH
    END
END
ELSE IF (@servermajorversion >= '15')
BEGIN
    RAISERROR ('Lightweight Profiling    SQL 2019. Using Lightweight Profiling Ver3 (enabled by default)', 0, 1) WITH NOWAIT
	PRINT ''

	WHILE (1=1)
	BEGIN
      BEGIN TRY
        --query the DMV in a loop to compare the 
		EXEC dbo.sp_perf_never_ending_query_snapshots @appname = 'SqlLogScout'
        WAITFOR DELAY '00:00:20'
      END TRY
      BEGIN CATCH
        PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
        PRINT 'Msg ' + isnull(cast(Error_Number() as nvarchar(50)), '') + ', Level ' + isnull(cast(Error_Severity() as nvarchar(50)),'') + ', State ' + isnull(cast(Error_State() as nvarchar(50)),'') + ', Server ' + @@servername + ', Line ' + isnull(cast(Error_Line() as nvarchar(50)),'') + char(10) +  Error_Message() + char(10);
      END CATCH
    END
END
go
EXEC dbo.sp_Run_NeverEndingQuery_Stats
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAOEYaRW+iptbv0
# vp/s1l5mHw3BNuNUXRWJvr6F92xmq6CCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPSPhB7F8thmPGntEHcP474hd9hiQNPd
# DLPVosMnO/qMMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# N1KxJOx8wBEmK8FQb4fW+MTSnOfvBix21GllzWEuTFLVG2roIzGmvkzROu+BynYO
# GU2SpQTLFxCW3ErqJl3nTivo1A6do9ho+vO/8b/B46wKIIAeUzt5RIP6J1dwP5zj
# So2JnbhckZ8O56Cb8/V5JWNjC7sV7zjZzZ0gVF2X3QtWG5AFkEeYQyBYuOwF5gMY
# GuRWTnLcSb8Lz4o2U8ldoNOETMUchRf6Lzb+PjO/B0YIpjBsVSgLr17hVqVcFCPB
# FsZqMQrI0hBQOT1Hh/mB+nz4awwwwYOrUSY9jQS1vSlTzUOaLDh71+o78JDQPTxx
# SapsBI7dgOB/tEbT1eGauqGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCCslM5UgLpvWKNuyMW+iCL4EufLnyL3kNkjREYerDJuHwIGaW+wKol9GBMyMDI2
# MDIwNDE2MzUyNy44MzVaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTYwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIH
# IDCCBQigAwIBAgITMwAAAgTY4A4HlzJYmAABAAACBDANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNDdaFw0y
# NjA0MjIxOTQyNDdaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046OTYwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQDw3Sbcee2d66vkWGTIXhfGqqgQGxQXTnq44XlUvNzFSt7ELtO4
# B939jwZFX7DrRt/4fpzGNkFdGpc7EL5S86qKYv360eXjW+fIv1lAqDD31d/p8Ai9
# /AZz8M95zo0rDpK2csz9WAyR9FtUDx52VOs9qP3/pgpHvgUvD8s6/3KNITzms8QC
# 1tJ3TMw1cRn9CZgVIYzw2iD/ZvOW0sbF/DRdgM8UdtxjFIKTXTaI/bJhsQge3Twa
# yKQ2j85RafFFVCR5/ChapkrBQWGwNFaPzpmYN46mPiOvUxriISC9nQ/GrDXUJWzL
# Dmchrmr2baABJevvw31UYlTlLZY6zUmjkgaRfpozd+Glq9TY2E3Dglr6PtTEKgPu
# 2hM6v8NiU5nTvxhDnxdmcf8UN7goeVlELXbOm7j8yw1xM9IyyQuUMWkorBaN/5r9
# g4lvYkMohRXEYB0tMaOPt0FmZmQMLBFpNRVnXBTa4haXvn1adKrvTz8VlfnHxkH6
# riA/h2AlqYWhv0YULsEcHnaDWgqA29ry+jH097MpJ/FHGHxk+d9kH2L5aJPpAYuN
# mMNPB7FDTPWAx7Apjr/J5MhUx0i07gV2brAZ9J9RHi+fMPbS+Qm4AonC5iOTj+dK
# CttVRs+jKKuO63CLwqlljvnUCmuSavOX54IXOtKcFZkfDdOZ7cE4DioP1QIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFBp1dktAcGpW/Km6qm+vu4M1GaJfMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQBecv6sRw2HTLMyUC1WJJ+FR+DgA9Jkv0lGsIt4y69C
# mOj8R63oFbhSmcdpakxqNbr8v9dyTb4RDyNqtohiiXbtrXmQK5X7y/Q++F0zMotT
# tTpTPvG3eltyV/LvO15mrLoNQ7W4VH58aLt030tORxs8VnAQQF5BmQQMOua+EQgH
# 4f1F4uF6rl3EC17JBSJ0wjHSea/n0WYiHPR0qkz/NRAf8lSUUV0gbIMawGIjn7+R
# KyCr+8l1xdNkK/F0UYuX3hG0nE+9Wc0L4A/enluUN7Pa9vOV6Vi3BOJST0RY/ax7
# iZ45leM8kqCw7BFPcTIkWzxpjr2nCtirnkw7OBQ6FNgwIuAvYNTU7r60W421YFOL
# 5pTsMZcNDOOsA01xv7ymCF6zknMGpRHuw0Rb2BAJC9quU7CXWbMbAJLdZ6XINKar
# iSmCX3/MLdzcW5XOycK0QhoRNRf4WqXRshEBaY2ymJvHO48oSSY/kpuYvBS3ljAA
# uLN7Rp8jWS7t916paGeE7prmrP9FJsoy1LFKmFnW+vg43ANhByuAEXq9Cay5o7K2
# H5NFnR5wj/SLRKwK1iyUX926i1TEviEiAh/PVyJbAD4koipig28p/6HDuiYOZ0wU
# km/a5W8orIjoOdU3XsJ4i08CfNp5I73CsvB5QPYMcLpF9NO/1LvoQAw3UPdL55M5
# HTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
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
# CxMeblNoaWVsZCBUU1MgRVNOOjk2MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQC6PYHRw9+9
# SH+1pwy6qzVG3k9lbqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S3yjTAiGA8yMDI2MDIwNDE2MzAwNVoYDzIw
# MjYwMjA1MTYzMDA1WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDtLfKNAgEAMAcC
# AQACAhSiMAcCAQACAhRMMAoCBQDtL0QNAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEL
# BQADggEBABeR9jEY/r6CVh/TXyD8z7/qnDsLCsRscRwCCle2SNdPiVzk2B93k9u5
# YMKdcBuP2r8t3eTrk6tBe4AWB6dKSE2Pe0ZsNrkIJ8oIjYzhpHP0U0Kam0p25Hcr
# wFcwpg4MVSodAGZgTovttdiuw/c/LAgIKhRgdjPCOJyxC6jKSSL5SGoFexL7uIBw
# LzlafB/K6RhvlsY5wAxMuozfdudWZCvT9JARgG4gJDgWmW2yU97VD48/aZ82mDbW
# /+FcbQ0YYxlp0AhaHtOEi7A/0FadHV8y7nLfNTLEjIicuRM/swxsaCu0BHWZYxUk
# xeFbVUX/kxmVwkO2CABfyuo2Sv+TGH4xggQNMIIECQIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAgTY4A4HlzJYmAABAAACBDANBglghkgB
# ZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCA2f0Ku5PgUNh8BNtA5ZtpF0FDKeL/+FvfqHxJRgX6YDTCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EIPnteGX9Wwq8VdJM6mjfx1GEJsu7/6kU6l0S
# S5rcebn+MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIE2OAOB5cyWJgAAQAAAgQwIgQgXuKNR8yZsUlh6DePzpj1QGH+MDA0CEEbjwdb
# vcB6nrEwDQYJKoZIhvcNAQELBQAEggIAgJj+czmnVTVdkufnGc6vX6BP4quvbBRC
# VWyVrIclI0oZoTBN+nrs04c8vKqT38dEjCUnZBNHJ4nXR7P06yJkesrB6jdj+sp6
# WqGcJwpbjF7j29idJd0+tysFIEIBUeXTTJB/3E2fSF39Yw16evkJEg9mgrBOqa1N
# 14NVnx7t/5mn5vdXajYZOwwXhZ6nAIEweyt1nh0jKSw9MqT8nIY8xUa99GUi7V8p
# KMiPq3ULAlmAEiC5aiEhZ+qkjNUk9SsAg41AUdNERRJK+JxvEGBdICNGZb5/+ex5
# 2l40GWkzg0ny9Vsn37ESYMKWyUjsElmPpIsrhqYrtpUvnoiH/FhbRR5+PrScKKhG
# dRmrgQDph1fJOGVUBQdiUXGcs5H3V4GqYaVRuEGdMK3+SRPkrRdFpWQuD9LnMIDm
# OYdGrt+tTJwsuBenuUtXtcGh2OzyQfWxu9MYitwK4kQdl4oF/Z9Wfb9yhXVfIzAs
# sy0FEzOtb1+aUNt/yPDlriZsZLzEpT4todQ1Su+kTChXqPKndDxk2IOfVm5NA5pL
# +QpFgNcZlypyEsfxm5a3alns9IrOpwFgUXi8+7xKOzMp32GP8KJrDSXkp/hKu86c
# 3kVbFJ46riMhXJqyNz7Wp7gGUqc6+oiGp6N2fPOBVCrBabhiLfzjPeiadFO4eufh
# P2SorupXE7U=
# SIG # End signature block
