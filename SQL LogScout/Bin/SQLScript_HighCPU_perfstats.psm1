
    function HighCPU_perfstats_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "HighCPU_perfstats"
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

IF OBJECT_ID ('#sp_perf_high_cpu_snapshots','P') IS NOT NULL
   DROP PROCEDURE #sp_perf_high_cpu_snapshots
GO

CREATE PROCEDURE #sp_perf_high_cpu_snapshots @appname sysname='sqllogscout', @runtime datetime, @runtime_utc datetime
AS
SET NOCOUNT ON
BEGIN
	BEGIN TRY
		DECLARE @msg varchar(100)
		IF NOT EXISTS (SELECT * FROM sys.dm_exec_requests req LEFT OUTER JOIN sys.dm_exec_sessions sess
						ON req.session_id = sess.session_id
						WHERE req.session_id <> @@SPID AND ISNULL (sess.host_name, '') != @appname AND is_user_process = 1) 
		BEGIN
			PRINT 'No active queries'
		END
		ELSE 
		BEGIN
		--  SELECT '' 
			IF @runtime IS NULL or @runtime_utc IS NULL
			BEGIN 
				SET @runtime = GETDATE()
				SET @runtime_utc = GETUTCDATE()
				SET @msg = 'Start time: ' + CONVERT (varchar(30), @runtime, 126)
				RAISERROR (@msg, 0, 1) WITH NOWAIT
			END

			PRINT ''
			RAISERROR ('--  high_cpu_queries --', 0, 1) WITH NOWAIT
			
			SELECT	CONVERT (varchar(30), @runtime, 126) as runtime, CONVERT (varchar(30), @runtime_utc, 126) as runtime_utc, req.session_id, thrd.os_thread_id, req.start_time as request_start_time, req.cpu_time, req.total_elapsed_time, req.logical_reads,
					req.status, req.command, req.wait_type, req.wait_time, req.scheduler_id, req.granted_query_memory, tsk.task_state, tsk.context_switches_count,
					replace(replace(substring(ISNULL(SQLText.text, ''),1,1000),CHAR(10), ' '),CHAR(13), ' ')  as batch_text, 
					ISNULL(sess.program_name, '') as program_name, ISNULL (sess.host_name, '') as Host_name, ISNULL(sess.host_process_id,0) as session_process_id, 
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
				OUTER APPLY sys.dm_exec_sql_text (ISNULL (req.sql_handle, conn.most_recent_sql_handle)) as SQLText
				LEFT OUTER JOIN sys.dm_exec_sessions sess ON conn.session_id = sess.session_id
				LEFT OUTER JOIN sys.dm_os_tasks tsk ON sess.session_id = tsk.session_id  --including this to get task state (SPINLOOCK state is crucial)
				INNER JOIN sys.dm_os_threads thrd ON tsk.worker_address = thrd.worker_address  
			WHERE sess.is_user_process = 1 
			AND req.cpu_time > 60000
			--this is to prevent massive grants
			OPTION (MAX_GRANT_PERCENT = 3, MAXDOP 1)
			
			--flush results to client
			RAISERROR (' ', 0, 1) WITH NOWAIT
		END
	END TRY
	BEGIN CATCH
	  PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	  PRINT 'Msg ' + ISNULL(CAST(ERROR_NUMBER() as NVARCHAR(50)), '') + ', Level ' + ISNULL(CAST(ERROR_SEVERITY() as NVARCHAR(50)),'') + ', State ' + ISNULL(CAST(Error_State() as NVARCHAR(50)),'') + ', Server ' + @@servername + ', Line ' + ISNULL(CAST(Error_Line() as NVARCHAR(50)),'') + CHAR(10) +  ERROR_MESSAGE() + CHAR(10);
	END CATCH
END
GO

if object_id ('#sp_run_highcpu_perfstats','p') is not null
   DROP PROCEDURE #sp_Run_HighCPU_PerfStats
GO
CREATE PROCEDURE #sp_Run_HighCPU_PerfStats 
AS
BEGIN TRY
  -- Main loop

	PRINT 'starting high cpu perf stats script...'
	SET LANGUAGE us_english
	PRINT '-- script source --'
	SELECT 'high cpu perf stats script' as script_name, '`$revision: 16 `$ (`$change: ? `$)' as revision
	PRINT ''
	PRINT '-- script AND environment details --'
	PRINT 'name                     value'
	PRINT '------------------------ ---------------------------------------------------'
	PRINT 'sql server name          ' + @@servername
	PRINT 'machine name             ' + convert (varchar, serverproperty ('machinename'))
	PRINT 'sql version (sp)         ' + convert (varchar, serverproperty ('productversion')) + ' (' + convert (varchar, serverproperty ('productlevel')) + ')'
	PRINT 'edition                  ' + convert (varchar, serverproperty ('edition'))
	PRINT 'script name              sql server perf stats script'
	PRINT 'script file name         `$file: highcpu_perfstats.sql `$'
	PRINT 'revision                 `$revision: 16 `$ (`$change: ? `$)'
	PRINT 'last modified            `$date: 2019/11/16  `$'
	PRINT 'script begin time        ' + convert (varchar(30), getdate(), 126) 
	PRINT 'current database         ' + db_name()
	PRINT '@@spid                   ' + ltrim(str(@@spid))
	PRINT ''

	DECLARE @runtime datetime, @runtime_utc datetime, @prevruntime datetime
	DECLARE @msg varchar(100)
	SELECT @prevruntime = sqlserver_start_time FROM sys.dm_os_sys_info
	--set prevtime to 5 min earlier, in case SQL just started
	SET @prevruntime = DATEADD(SECOND, -300, @prevruntime)

	WHILE (1=1)
	BEGIN
		BEGIN TRY
			SET @runtime = GETDATE()
			SET @runtime_utc = GETUTCDATE()
			SET @msg = 'Start time: ' + CONVERT (varchar(30), @runtime, 126)

			PRINT ''
			RAISERROR (@msg, 0, 1) WITH NOWAIT
			
			-- Collect sp_perf_high_Cpu_snapshot every 3 minutes
			EXEC #sp_perf_high_cpu_snapshots 'sqllogscout', @runtime = @runtime, @runtime_utc = @runtime_utc
			SET @prevruntime = @runtime
			WAITFOR DELAY '0:00:30'
		END TRY
		BEGIN CATCH
			PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
			PRINT 'Msg ' + ISNULL(CAST(ERROR_NUMBER() as NVARCHAR(50)), '') + ', Level ' + ISNULL(CAST(ERROR_SEVERITY() as NVARCHAR(50)),'') + ', State ' + ISNULL(CAST(Error_State() as NVARCHAR(50)),'') + ', Server ' + @@servername + ', Line ' + ISNULL(CAST(Error_Line() as NVARCHAR(50)),'') + CHAR(10) +  ERROR_MESSAGE() + CHAR(10);
		END CATCH
	END
END TRY
BEGIN CATCH
	PRINT 'Exception occured in: `"' + OBJECT_NAME(@@PROCID)  + '`"'     
	PRINT 'Msg ' + ISNULL(CAST(ERROR_NUMBER() as NVARCHAR(50)), '') + ', Level ' + ISNULL(CAST(ERROR_SEVERITY() as NVARCHAR(50)),'') + ', State ' + ISNULL(CAST(Error_State() as NVARCHAR(50)),'') + ', Server ' + @@servername + ', Line ' + ISNULL(CAST(Error_Line() as NVARCHAR(50)),'') + CHAR(10) +  ERROR_MESSAGE() + CHAR(10);
END CATCH
GO

EXEC #sp_Run_HighCPU_PerfStats
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
# MIIsCwYJKoZIhvcNAQcCoIIr/DCCK/gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDWg6k2hzbOD/Cb
# 0PuvpefYn2waz6AR3sYPgz8JAxyEOqCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# RtShDZbuYymynY1un+RyfiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZ5DCCGeAC
# AQEwWDBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1F
# MRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDECEzYAAAIOeZeg6f1fn9MAAgAAAg4wDQYJ
# YIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEID6El3TAxcn/
# NcR5gsAHUWIWUxkbwk+FDUPeF0Ty+p9QMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAluadrdDlnIKnWDJMg4MY5XtO33DAOm1/3Z/AjYQkhJWx
# pD9Sl3CGaabtpmnlglIj2s8pj4jnBq1/3Y3bggQjmNJOqUtYVFPY/9GySX7jYV+Y
# rV1QtVkzuyewGECdvBvLLwFpj1n6aTkqnJ6W9vA3ITnuy5jrKYIyYqgWZgYEs6HZ
# mqwTQ1e9QVv1o40N/YLib9wfMha4A3jfcSu2c2W1mE8Xg/VD3GBjZHrRH1ZrhWxa
# /R2uyzKtqR2e7fK3H45PSAXRpwvWIWPUx76FBo/yAe1nUPMUDja3mg0l8935lhv/
# Bfa+OnE1H/mbI+P1/kLGwxO4e4iADPyLg5ZdOFrJrKGCF6wwgheoBgorBgEEAYI3
# AwMBMYIXmDCCF5QGCSqGSIb3DQEHAqCCF4UwgheBAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCBUsLP7k/lccjA623r84OaDXdiFiQL4oIBfdlylWYK/
# /wIGaXNm4xVgGBIyMDI2MDIwNDE2MzUzMC42OFowBIACAfSggdmkgdYwgdMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jv
# c29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjM2MDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloIIR+zCCBygwggUQoAMCAQICEzMAAAITsEM1Zs+vlegA
# AQAAAhMwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwHhcNMjUwODE0MTg0ODE3WhcNMjYxMTEzMTg0ODE3WjCB0zELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IEly
# ZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBF
# U046MzYwNS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQD0mXrguhnE
# Mg1IWDP70pLk7O/mbnjx49XNz1FdZ7hPj8ymV+Brh6rXZEZ2nlxW+eN17m/F+rZr
# H+Oe7u9Rbitk3iY5Sbm+H6RxixCVhDncXCAgHecSNxAeiasbeZl7+jOMVICvoluC
# Uq0h4DJI/MBwXPIB6vmUs1QcES9AwzwE6MzJqkK+HTGyDjEoVxUQlAsoR8IYF98x
# kj9qa60cVvcJRNntpWkbYocQVQ2VnW/Awq/FdM9EOdvA8bPLKoknOd+ws0dDi9e3
# a21LU94KgYjSE3U96rzIawhcz2ihzALToMY1Iz/gsDHa4q/CZSfo3AtzT62a+fLr
# Dbytkt6OyRF+dVah8S/WZZjSMdScevBIYFLyBU/2BwGzo/mDQ6kk8x/F1SQddGRw
# w89bSEg/w1tbxblK6nwe7CdIpuOnICUYFR0z9XmtlvSxmaSfvXivpQsYr5wssA3p
# HcWFfo3SePrgXbstMrYFtLSkllpeOjR4M3PVBzF4gUtSAX5EGwtgOfwTxwKR7Erw
# 2W3caL3Ml/nnDpR9Nn6TBMzEyoXGHv5N/Hv5oE5tn6fH3rUC2KoDLvNVXr2j8tZF
# 0o9l29mf0RLIZtOc9+OQERG/bamtKUROVHDM/puYRU4pYtZXDG7CHttRZS5RvVyP
# 3fO+21BgZBq3kT0Assk2aW8soKyQHutouwIDAQABo4IBSTCCAUUwHQYDVR0OBBYE
# FBOeEErH4WvKmFBYxGKkfj2wwUA6MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWn
# G1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEw
# KDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFt
# cCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAww
# CgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCC
# bFomsapDYPpQmFnpCXZJkU5o24ZtbcvMH4RL6XYEHUwm0FFIV2L+FVjfc2nGwlCF
# DlMtWnQNdg6Qig9BzXusf4hWF6Y7yMK35TojVMjDpxHtz60Sj8mOnoSoRTVzj+at
# oyOAeFD6toL85QCb3wDWvhsg8e2wGYtE4aZ4TlcsgVoEhlYe+HYI5chMo5tdV3nA
# a0nV1ll3BocAJcXnTqO1r66hR3LMB642VM8tOtnyfKHEbCT1WHp6INDsJAxZJJrw
# MlL09ReN6iL29N1Ltkxeq762/pDPfG2gEXn5gUri4T6aIaz3QXGbRUraVauYWGOR
# GXnPKgc53Abuyk1iQOiYI81Yi51RCZBgqm38eyyl9xv7GmdYgNB0zOATymPW+nAu
# BYScfsu1Ph1kJ6gOj08rjRHEEPyQonvr2eCQTB/AIPYRf8xCTv14i86GmcfXYa5U
# HK9opmTldm+q08403Cvyr+oDfzvsi5bBaCdp5f6munDR1n9Au1sYZWuA/5NFCO37
# Z1xkDk/dfgvAA2GI+zLQ6XhcJ2Ps7EEsW87OwI8M9pWeSn518MUb404GKvtqpMnr
# zrbanKaDVX7qBz/VG/EL/CC9jIbTfd5wmq/Q6fRlE1iv6L86TCADcc/VosPRoesS
# nDqW3TbreJGQK+tx1w5bzDeMLxMm5oZbILZL2MSPODCCB3EwggVZoAMCAQICEzMA
# AAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMw
# MDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3u
# nAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1
# jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZT
# fDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+
# jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c
# +gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+
# cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C6
# 26p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV
# 2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoS
# CtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxS
# UV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJp
# xq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkr
# BgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYI
# KwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9S
# ZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIE
# DB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNV
# HSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVo
# dHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29D
# ZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAC
# hj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1
# dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwEx
# JFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts
# 0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9I
# dQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYS
# EhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMu
# LGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT9
# 9kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2z
# AVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6Ile
# T53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6l
# MVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbh
# IurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3u
# gm2lBRDBcQZqELQdVTNYs6FwZvKhggNWMIICPgIBATCCAQGhgdmkgdYwgdMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jv
# c29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjM2MDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCYETxIKPGCNpybLz9UR2Ts
# 3GlHpqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBCwUAAgUA7S22kDAiGA8yMDI2MDIwNDEyMTQwOFoYDzIwMjYwMjA1MTIx
# NDA4WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDtLbaQAgEAMAcCAQACAgsoMAcC
# AQACAhNxMAoCBQDtLwgQAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAFbN
# rjM8oZ9pepoZXUYjD0kDAP7MHku0SszNYCAJ9Q+t4c2k1efDKGC3HJMYvlYBqbPl
# r0AnwJDpRAHJ0+xYpSBVxM0g3tKUu8GnvNFflYAEXbWRqJOCUbK1JGFG/Lo+bMby
# eiMDInm01E2FGBLzr+omcNr3d1Wng84v8ue1zhmEtpVcm6z4eQ7FHBtMoPopcLKq
# m/83SSFASZhYtJnlwtRkT0gSGvPXYelydE0o5cM9TT+1o9PG7L+TxEd70sNWC3Qx
# ogR0twCFjYFR7oldTrEsZKEKv7AxnTSwGSigicPfbf9s9EC5PJPjK/AHgEBXRmHJ
# Oj9oNDs2w6Xy/Lr0s8sxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMAITMwAAAhOwQzVmz6+V6AABAAACEzANBglghkgBZQMEAgEFAKCC
# AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBH
# yinxscUpcMvTBvB8QofLGolj7WIo1Uy5MorHVVwXYzCB+gYLKoZIhvcNAQkQAi8x
# geowgecwgeQwgb0EIMzhCW0UhTPwngOMDM/idWh1m9DFgaV5Qh+nzo5rnFhoMIGY
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAITsEM1Zs+v
# legAAQAAAhMwIgQgaJyg1itfeCRNJe5Mljby17AiDt8mwEVP7FafKoEpqKowDQYJ
# KoZIhvcNAQELBQAEggIA1DiLgRRAloFtoPp6WJ1dVCRBF8B0g6/SkL7DvJw7/sjw
# iWoezPefOc9QKG64TSIVXprIN7/+MZK5yl+AOZBRui9ZYXGfdOzlIYhUUUF8Wi2p
# bsLMNEk7zooDfwC0NU8CCzps2YKBEZN8v4CIVVgrMrjYAlEKFW6FPdFUDy+dMzVL
# pvn9VQixg48VEHk21OdImgwrA7b+fAbGvgOTVF0YGFr/3HjIaPnuYasg/f2DCF8Z
# cG+9rZtNtEM8ToE7+Ol1LzqzPYVz57tSGOadm+NkIQxfE9lV8QwEpXmaL2WKsSc4
# iHJAx9RiVs29Jz7cZ3mynXOdMNA4TItBWO3SSjzH7lf6qkw9TQhtVAZU2EAzDfcF
# fk9HNQ1YuM7FI8pQ0iRPEWKWtanQ2MxKjvR0oLnDG/PHPY86knNaDS+3ygLGdO2a
# M394sHCKDW5nki7zePPPCO8FnpwbeOxDxAEEd8MIKPZohLhB5YXK/3u29pQZLsTK
# nTFPPtjjtrCpMVHK0KuGPA/5c1egQQKBVobrwXcrnv1do2hfXqmXcJzADEHT7eXf
# YlbelKDebNiadFI7qolLlmPFAR5X1Nw2YCXcD8YCc1tWp8qpO+Lm3FsCcfl7p1iH
# 6x7Rz5ZU52c666X7RWh3bOpD0b6CAOzqAGJzNqdoMxh1g/QyrNqPoABJg+Cages=
# SIG # End signature block
