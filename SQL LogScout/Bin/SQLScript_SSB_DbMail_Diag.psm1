
    function SSB_DbMail_Diag_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "SSB_DbMail_Diag"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
USE master
GO

SET NOCOUNT ON
SET QUOTED_IDENTIFIER ON;
DECLARE @StartTime datetime

SELECT @@version as 'Version'
PRINT ''
SELECT GETDATE() as 'RunDateTime', GETUTCDATE() as 'RunUTCDateTime', SYSDATETIMEOFFSET() as 'SysDateTimeOffset'
PRINT ''
SELECT @@servername as 'ServerName'
PRINT ''
PRINT '-- sys.databases --' 
SELECT * FROM master.sys.databases where is_broker_enabled = 1 and name not in('tempdb', 'model', 'AdventureWorks', 'AdventureWorksDW')
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- sys.dm_broker_activated_tasks --' 
SELECT * FROM sys.dm_broker_activated_tasks
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- sys.dm_broker_connections --' 
SELECT * FROM sys.dm_broker_connections
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- broker_connections_count_by_state --'
SELECT count(*) as Cnt, state_desc, login_state_desc FROM sys.dm_broker_connections GROUP BY state_desc, login_state_desc ORDER BY state_desc 
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- sys.dm_broker_forwarded_messages --' 
SELECT * FROM sys.dm_broker_forwarded_messages
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- sys.service_broker_endpoints --' 
SELECT * FROM sys.service_broker_endpoints
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- sys.tcp_endpoints --' 
SELECT * FROM sys.tcp_endpoints
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- sys.database_mirroring --' 
SELECT * FROM sys.database_mirroring where mirroring_guid is not null
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- sys.dm_db_mirroring_connections --' 
SELECT * FROM sys.dm_db_mirroring_connections
RAISERROR (' ', 0, 1) WITH NOWAIT; 

PRINT '-- sys.dm_os_memory_clerks_service_broker --'  
SELECT * FROM sys.dm_os_memory_clerks where type like '%BROKER%' order by type desc
RAISERROR (' ', 0, 1) WITH NOWAIT; 

-- Loop Through DBs and Gather SSB information specific to each DB
DECLARE tnames_cursor CURSOR
FOR SELECT name 
	  FROM master.sys.databases 
	  WHERE is_broker_enabled = 1 
	        AND state = 0 
	        AND name not in('tempdb', 'model', 'AdventureWorks', 'AdventureWorksDW')
	  ORDER BY [name]
OPEN tnames_cursor;

DECLARE @dbname sysname;
DECLARE @SCI int; -- Checking for Broker activity
DECLARE @cmd3 nvarchar(1024); -- New Command

FETCH NEXT FROM tnames_cursor INTO @dbname;
WHILE (@@FETCH_STATUS = 0)
BEGIN
  
  SELECT @SCI = 0; -- service_contract_id
  SELECT @dbname = RTRIM(@dbname);
  
  IF HAS_PERMS_BY_NAME(@dbname, 'DATABASE', 'CONNECT') = 1
  BEGIN
    
	  SELECT @cmd3 = N'SELECT @SCI_OUT = MAX(service_contract_id) FROM [' + @dbname + '].sys.service_contracts';
      
	  EXEC sp_executesql @cmd3, N'@SCI_OUT INT OUTPUT', @SCI_OUT = @SCI OUTPUT; 
      
	  IF @SCI > 7
    BEGIN
      
      PRINT ''
      PRINT 'Begin Database: ' + @dbname
      
      SELECT @StartTime = GETDATE()
      PRINT 'Start Time : ' + CONVERT(Varchar(50), @StartTime)
      PRINT ''
      
      PRINT '-- sys.service_message_types --'
      EXEC ('SELECT  * FROM [' + @dbname + '].sys.service_message_types');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.service_contracts --' 
      EXEC ('SELECT * FROM [' + @dbname + '].sys.service_contracts');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.service_queues --' 
      EXEC ('SELECT * FROM [' + @dbname + '].sys.service_queues');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.services --' 
      EXEC ('SELECT * FROM [' + @dbname + '].sys.services');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.routes --' 
      EXEC ('SELECT * FROM [' + @dbname + '].sys.routes');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.remote_service_bindings --' 
      EXEC ('SELECT * FROM [' + @dbname + '].sys.remote_service_bindings');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.certificates --' 
      IF @dbname  != 'master' -- skip master as we are gathering from there in MiscDiagInfo
      BEGIN
        EXEC ('SELECT ''' +
      	       @dbname + ''' AS [database_name], 
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
      	       ''0x'' + CONVERT(VARCHAR(64),thumbprint,2) AS thumbprint,
      	       CONVERT(VARCHAR(256), attested_by) AS attested_by,
      	       pvt_key_last_backup_date,
      	       key_length
              FROM [' + @dbname + '].sys.certificates');
      END
      RAISERROR (' ', 0, 1) WITH NOWAIT; 

      PRINT '-- sys.dm_qn_subscriptions --' 
      EXEC ('SELECT * FROM [' + @dbname + '].sys.dm_qn_subscriptions');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- service_and_queue_monitor_status --' 
      EXEC ('SELECT t1.name AS [Service_Name],  t3.name AS [Schema_Name],  t2.name AS [Queue_Name],  
                    CASE WHEN t4.state IS NULL THEN ''Not available'' 
                    ELSE t4.state 
                    END AS [Queue_State],  
                    CASE WHEN t4.tasks_waiting IS NULL THEN ''--'' 
                    ELSE CONVERT(VARCHAR, t4.tasks_waiting) 
                    END AS tasks_waiting, 
                    CASE WHEN t4.last_activated_time IS NULL THEN ''--'' 
                    ELSE CONVERT(varchar, t4.last_activated_time) 
                    END AS last_activated_time ,  
                    CASE WHEN t4.last_empty_rowset_time IS NULL THEN ''--'' 
                    ELSE CONVERT(varchar,t4.last_empty_rowset_time) 
                    END AS last_empty_rowset_time, 
                    ( 
                    	SELECT COUNT(*) 
                    	FROM [' + @dbname + '].sys.transmission_queue t6 WITH (NOLOCK)
                    	WHERE (t6.from_service_name = t1.name) 
                    ) AS [Tran_Message_Count],
                    DB_NAME() AS DB_NAME 
             FROM [' + @dbname + '].sys.services t1 WITH (NOLOCK) 
               INNER JOIN [' + @dbname + '].sys.service_queues t2 WITH (NOLOCK)
                 ON ( t1.service_queue_id = t2.object_id )   
               INNER JOIN [' + @dbname + '].sys.schemas t3 WITH (NOLOCK) 
                 ON ( t2.schema_id = t3.schema_id )  
               LEFT OUTER JOIN [' + @dbname + '].sys.dm_broker_queue_monitors t4 WITH (NOLOCK)
                 ON ( t2.object_id = t4.queue_id  AND t4.database_id = DB_ID() )  
               INNER JOIN sys.databases t5 WITH (NOLOCK) 
                 ON ( t5.database_id = DB_ID() );')
      RAISERROR (' ', 0, 1) WITH NOWAIT;            	
      
      -- Using count against MetaData columns rather than COUNT(*) becuase it is faster, and we dont' need exact counts
	    PRINT '-- sys.transmission_queue_row_count --' 
      EXEC ('SELECT p.rows as TQ_Count FROM [' + @dbname + '].sys.objects as o join [' + @dbname + '].sys.partitions as p on p.object_id = o.object_id where o.name = ''sysxmitqueue''')
      RAISERROR (' ', 0, 1) WITH NOWAIT; 		
      
      PRINT '-- sys.transmission_queue_count_by_status --'
      EXEC('SELECT COUNT(*) as TQ_GroupCnt, transmission_status FROM [' + @dbname + '].sys.transmission_queue GROUP BY transmission_status');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.transmission_queue_top500 --' 
      EXEC ('SELECT top 500 conversation_handle, to_service_name, to_broker_instance, from_service_name, 
      	            service_contract_name, enqueue_time, message_sequence_number, message_type_name, is_conversation_error, 
      	            is_end_of_dialog, priority, transmission_status, DB_NAME() as DB_Name 
	  	      FROM [' + @dbname + '].sys.transmission_queue with (nolock) 
	  	      ORDER BY enqueue_time, message_sequence_number');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 

      -- Using count against MetaData columns rather than COUNT(*) becuase it is faster, and we dont' need exact counts
      PRINT '-- sys.conversation_endpoints_row_count --'
      EXEC ('SELECT p.rows as CE_Count FROM [' + @dbname + '].sys.objects as o join [' + @dbname + '].sys.partitions as p on p.object_id = o.object_id  where o.name = ''sysdesend''')
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.conversation_endpoints_count_by_state --'
      EXEC  ('SELECT COUNT(*) as CE_GroupCnt, state_desc FROM [' + @dbname + ']. sys.conversation_endpoints GROUP BY state_desc')
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT '-- sys.conversation_endpoints_top500 --'
      EXEC ('SELECT top 500 *, DB_NAME() as DB_Name FROM [' + @dbname + '].sys.conversation_endpoints with (nolock)');
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      PRINT 'End of Database: ' + @dbname 
      PRINT 'END Time : ' + CONVERT(Varchar(50), GetDate())
      PRINT 'Data Collection Duration in milliseconds for ' + @dbname
      RAISERROR (' ', 0, 1) WITH NOWAIT; 
      
      SELECT DATEDIFF(millisecond, @StartTime, GETDATE()) as Duration_ms
      RAISERROR (' ', 0, 1) WITH NOWAIT;        
         
    END;           
  END;
  FETCH NEXT FROM tnames_cursor INTO @dbname;
END;
CLOSE tnames_cursor;
DEALLOCATE tnames_cursor;


PRINT 'Getting Database Mail Information'
RAISERROR (' ', 0, 1) WITH NOWAIT;

PRINT '-- sysmail_event_log_sysmail_faileditems --'
SELECT er.log_id, 
    er.event_type,
    er.log_date, 
    er.description,
    er.process_id, 
    er.mailitem_id, 
    er.account_id, 
    er.last_mod_date, 
    er.last_mod_user,
    fi.send_request_user,
    fi.send_request_date,
    fi.recipients, 
	fi.subject
FROM msdb.dbo.sysmail_event_log er 
    LEFT JOIN msdb.dbo.sysmail_faileditems fi
ON er.mailitem_id = fi.mailitem_id
ORDER BY log_date DESC;
RAISERROR (' ', 0, 1) WITH NOWAIT;

PRINT '-- sysmail_mailitems --'
SELECT mailitem_id,
       profile_id,
       recipients,
       copy_recipients,
       blind_copy_recipients,
       subject,
	   from_address,
       body_format,
       importance,
       sensitivity,
       file_attachments,
       attachment_encoding,
       query,
       execute_query_database,
       attach_query_result_as_file,
       query_result_header,
       query_result_width,
       query_result_separator,
       exclude_query_output,
       append_query_error,
       send_request_date,
       send_request_user,
       sent_account_id,
       CASE sent_status 
          WHEN 0 THEN 'unsent' 
          WHEN 1 THEN 'sent' 
          WHEN 3 THEN 'retrying' 
          ELSE 'failed' 
       END as sent_status_description,
	   sent_status,     
       sent_date,
       last_mod_date,
       last_mod_user
FROM msdb.dbo.sysmail_mailitems;
RAISERROR (' ', 0, 1) WITH NOWAIT;

PRINT '-- sysmail_account --'
SELECT 
  account_id         ,
  name               ,
  description        ,
  email_address      ,
  display_name       ,
  replyto_address    ,
  last_mod_datetime  ,
  last_mod_user    
FROM msdb.dbo.sysmail_account;
RAISERROR (' ', 0, 1) WITH NOWAIT;


PRINT '-- sysmail_configuration --'
SELECT
  paramname          ,
  paramvalue         ,
  description        ,
  last_mod_datetime  ,
  last_mod_user      
FROM msdb.dbo.sysmail_configuration;
RAISERROR (' ', 0, 1) WITH NOWAIT;

PRINT '-- sysmail_log --'
SELECT 
  log_id            ,
  event_type        ,
  log_date          ,
  description,
  process_id        ,
  mailitem_id       ,
  account_id        ,
  last_mod_date     ,
  last_mod_user     
FROM msdb.dbo.sysmail_log; 
RAISERROR (' ', 0, 1) WITH NOWAIT;

PRINT '-- sysmail_profile --'
SELECT 
  profile_id           ,    
  name                 ,    
  description          ,    
  last_mod_datetime    ,    
  last_mod_user            
FROM msdb.dbo.sysmail_profile
RAISERROR (' ', 0, 1) WITH NOWAIT;

PRINT '-- sysmail_profileaccount --'
SELECT 
  profile_id             ,
  account_id             ,
  sequence_number        ,
  last_mod_datetime      ,
  last_mod_user          
FROM 
msdb.dbo.sysmail_profileaccount
RAISERROR (' ', 0, 1) WITH NOWAIT;

PRINT '-- sysmail_server --'
SELECT 
  account_id				,
  servertype				,
  servername				,
  port						,
  username					,
  credential_id				,
  use_default_credentials	,
  enable_ssl				,
  flags						,
  timeout					,
  last_mod_datetime			,
  last_mod_user
FROM 
msdb.dbo.sysmail_server
RAISERROR (' ', 0, 1) WITH NOWAIT;
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBbKbRm9jULkIbW
# 2FELt1U1G5/I7tYHpeljbfT3/cPtHaCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIL6syINwDuyUACBH7AiuI55CXgvS3afJ
# lgL5wjr8THu6MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# H2DYQo5x4tPuhlhBQXDjdzByOAkcrs4AYFyumaDOg/BPCgfyPJtyI83QdK62/aBW
# b0OGj6WBAsffh9vWWEWspSGpI4Yy5IFvkEBBxIygln3RjAs+QGuZ/QLG3lU7x3WE
# A641GSGcYIZf6edrfazPcxVwK32adYZUFF9TonxfTzsYF9uGeuZ8xNzIkdS1NQyI
# Q+ptW1EuUevOFfn9Fm5t52x5xwodRzNuGf13x85OeWqFNNTD3RamZJzvj2yIjhcr
# cyT6LiiQ7IKNmsy3O/HQt+Oni8gEjZzRNDdDb/ge1gqphbxjRVqIQXpdJ/jBRY1U
# beQZH7WdrDsEpspfx3hAi6GCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCCO+0J1C2sOcgwvKeUwbbcRX+N9UcCpuUJiuKGhoLm1dAIGaWjo97CFGBMyMDI2
# MDIwNDE2MzUyNy4yNDFaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTkzNS0wM0UwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIH
# IDCCBQigAwIBAgITMwAAAgy5ZOM1nOz0rgABAAACDDANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQzMDBaFw0y
# NjA0MjIxOTQzMDBaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046QTkzNS0wM0UwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQDKAVYmPeRtga/U6jzqyqLD0MAool23gcBN58+Z/XskYwNJsZ+O
# +wVyQYl8dPTK1/BC2xAic1m+JvckqjVaQ32KmURsEZotirQY4PKVW+eXwRt3r6sz
# gLuic6qoHlbXox/l0HJtgURkzDXWMkKmGSL7z8/crqcvmYqv8t/slAF4J+mpzb9t
# MFVmjwKXONVdRwg9Q3WaPZBC7Wvoi7PRIN2jgjSBnHYyAZSlstKNrpYb6+Gu6oSF
# kQzGpR65+QNDdkP4ufOf4PbOg3fb4uGPjI8EPKlpwMwai1kQyX+fgcgCoV9J+o8M
# YYCZUet3kzhhwRzqh6LMeDjaXLP701SXXiXc2ZHzuDHbS/sZtJ3627cVpClXEIUv
# g2xpr0rPlItHwtjo1PwMCpXYqnYKvX8aJ8nawT9W8FUuuyZPG1852+q4jkVleKL7
# x+7el8ETehbdkwdhAXyXimaEzWetNNSmG/KfHAp9czwsL1vKr4Rgn+pIIkZHuomd
# f5e481K+xIWhLCPdpuV87EqGOK/jbhOnZEqwdvA0AlMaLfsmCemZmupejaYuEk05
# /6cCUxgF4zCnkJeYdMAP+9Z4kVh7tzRFsw/lZSl2D7EhIA6Knj6RffH2k7YtSGSv
# 86CShzfiXaz9y6sTu8SGqF6ObL/eu/DkivyVoCfUXWLjiSJsrS63D0EHHQIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFHUORSH/sB/rQ/beD0l5VxQ706GIMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQDZMPr4gVmwwf4GMB5ZfHSr34uhug6yzu4HUT+JWMZq
# z9uhLZBoX5CPjdKJzwAVvYoNuLmS0+9lA5S74rvKqd/u9vp88VGk6U7gMceatdqp
# KlbVRdn2ZfrMcpI4zOc6BtuYrzJV4cEs1YmX95uiAxaED34w02BnfuPZXA0edsDB
# bd4ixFU8X/1J0DfIUk1YFYPOrmwmI2k16u6TcKO0YpRlwTdCq9vO0eEIER1SLmQN
# BzX9h2ccCvtgekOaBoIQ3ZRai8Ds1f+wcKCPzD4qDX3xNgvLFiKoA6ZSG9S/yOrG
# aiSGIeDy5N9VQuqTNjryuAzjvf5W8AQp31hV1GbUDOkbUdd+zkJWKX4FmzeeN52E
# EbykoWcJ5V9M4DPGN5xpFqXy9aO0+dR0UUYWuqeLhDyRnVeZcTEu0xgmo+pQHauF
# VASsVORMp8TF8dpesd+tqkkQ8VNvI20oOfnTfL+7ZgUMf7qNV0ll0Wo5nlr1CJva
# 1bfk2Hc5BY1M9sd3blBkezyvJPn4j0bfOOrCYTwYsNsjiRl/WW18NOpiwqciwFlU
# NqtWCRMzC9r84YaUMQ82Bywk48d4uBon5ZA8pXXS7jwJTjJj5USeRl9vjT98PDZy
# CFO2eFSOFdDdf6WBo/WZUA2hGZ0q+J7j140fbXCfOUIm0j23HaAV0ckDS/nmC/oF
# 1jCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
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
# CxMeblNoaWVsZCBUU1MgRVNOOkE5MzUtMDNFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDvu8hkhEMt
# 5Z8Ldefls7z1LVU8pqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S3B4zAiGA8yMDI2MDIwNDEzMDIyN1oYDzIw
# MjYwMjA1MTMwMjI3WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDtLcHjAgEAMAcC
# AQACAhHvMAcCAQACAhqwMAoCBQDtLxNjAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEL
# BQADggEBAD36ic0aP72QYyQ+hxGRoSWsbcLRjPSjUs84HpR7n2IeI4hDuklydQAY
# pAzRpvp1gB/tDUExhNnRxVF/JMuv1ni7+1G8F19GD/kPjgq039OJe5pq7nq3UCC8
# atbnFqXmb+XKp9i0w3cKKrMi3UaaoDvb2srhDegok8Ffz9pqjKaPnNp+JnptGExc
# ZyJKeP/suXpGX2auTJrCw3OqLy1gRo23i7HRIUq9FtG/gqNTxeobuj+f1aUIcdeo
# bmpL/3mbcK640YG/DnmYQXv9yZSyL6r9Uma/+oYK2Lk4aKR3QWTh2ejYHX5tTvfC
# NtFNhk8ldddwGPaeYgThgSaIj64EwLgxggQNMIIECQIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAgy5ZOM1nOz0rgABAAACDDANBglghkgB
# ZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCD0br05vDdLw7cSbaAM1Vos5bwwMf2pcp8Sr9X4Aeq5jTCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EINUo17cFMZN46MI5NfIAg9Ux5cO5xM9inre5
# riuOZ8ItMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIMuWTjNZzs9K4AAQAAAgwwIgQgT+jPnBIIP9shvRM8rjFVYz7ININcDtUTh1HB
# 3F0DtIUwDQYJKoZIhvcNAQELBQAEggIACJe8+XJtoqTEQMPRrk3CvchhlDPA6OnX
# 9uJ6pOHwg2Gr1vr4DF5BvGamzDdOvr9boui7dRR4lixAa+mJhw1hOG7cH01MeMn7
# cxIabNTxoJ/YSJTUG82AEN5IHYwqpRLQYICfUDeQLupY/mGa8nXlEs+7Uuutnabr
# sPaaXtP1dLkvyP6P1qBiX6PQuPhG2GGEZm5aU7BcttwAADA8H4Dh+KT1LxwA6IxU
# EYoAeJjfo50IrKhSHaCzaKjmxmZymCoERocHzP/tmxOLam1yzOLxmUyzo9KrbxtU
# B7K0tqW0usu+OQ6C/5umJwx5Qa2NsYRdYYRU2uOkruLPbeNpB0J1WGQBKqQ8WgnT
# 7D4zJg623ycaH8pgGBm+zjm4yb/ZFfL6sGwyALvgjabgA/PWYBEUVtPTJc/h557J
# Nvo+ApxUf/it2vhtaqnFFRleSJtgygYZja6tEuejlP7cC2a5zON9zFq/gIfUM09+
# ZJeW1q2KnQ9YzEbflWo4qAG9/b/lCovrIIBNJBBsNq5IBR7SfbeFLNR13R9yzSwf
# NWlhyAlU/AOR8HF4Q313dUHQ6v+fRefj7c14yPNZAP7fBLjyjajE/qbZSiB7yCOC
# r+Fgyw09sWWGm2x1ouSHEOwr6GkjjcOUNSoKfxYhumfWB0xxNQOj9Buy3nGC5CFj
# xdCW07IuTFE=
# SIG # End signature block
