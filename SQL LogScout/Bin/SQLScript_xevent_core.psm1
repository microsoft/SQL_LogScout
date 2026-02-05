
function xevent_core_Query([Boolean] $returnVariable = $false)
{

  Write-LogDebug "Inside" $MyInvocation.MyCommand

  [String] $collectorName = "xevent_core"
  [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

  $content =  "
  IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 0
    BEGIN
      PRINT ''
      PRINT ' *** '
      PRINT ' *** Skipped creating and configuring event session xevent_SQLLogScout. Principal ' + SUSER_SNAME() + ' does not have ALTER ANY EVENT SESSION permission.'
      PRINT ' *** To grant permissions, execute the following and rerun the script:'
      PRINT ' *** '
      PRINT ' *** GRANT ALTER ANY EVENT SESSION TO ' + QUOTENAME(SUSER_SNAME())
      PRINT ' *** '
      PRINT ''
    END
    GO
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        if exists (select * from sys.server_event_sessions where name= 'xevent_SQLLogScout') drop  EVENT SESSION [xevent_SQLLogScout] ON SERVER 
    GO
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        CREATE  EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.existing_connection ( SET collect_database_name=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
        WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
      )
      WITH (MAX_MEMORY=200800 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=10 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_CPU,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
    GO
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.login ( SET collect_options_text=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
        WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
      )
    GO
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.logout (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
        WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
      )
    GO
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sql_batch_completed ( SET collect_batch_text=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
        WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
      )
    GO
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.sql_batch_starting (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
        WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
      )
    GO
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.rpc_starting (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
        WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
      )
    GO
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.rpc_completed ( SET collect_data_stream=(1)      ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)      
        WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
      )
    GO

    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.error_reported (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
          WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
        )
    GO
    
    IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1
        ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER  ADD EVENT sqlserver.execution_warning (     ACTION (package0.event_sequence, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.client_pid, sqlserver.database_id, sqlserver.database_name, sqlserver.is_system, sqlserver.nt_username, sqlserver.query_hash, sqlserver.request_id, sqlserver.server_principal_name, sqlserver.session_server_principal_name, sqlserver.session_id, sqlserver.session_nt_username, sqlserver.sql_text, sqlserver.transaction_id, sqlserver.username)     
          WHERE (([sqlserver].[client_hostname]<>N'sqllogscout') AND ([sqlserver].[client_hostname]<>N'sqllogscout_stop') AND ([sqlserver].[client_hostname]<>N'sqllogscout_cleanup'))
        )
    GO

    "
  
  # Add additional options if enabled
  if ($global:gAdditionalOptionsEnabled -contains "TrackCausality")
  {
    $track_causality = "ALTER EVENT SESSION [xevent_SQLLogScout] ON SERVER WITH (TRACK_CAUSALITY = ON);"
    $content = $content + $track_causality
    Write-LogWarning "TRACK_CAUSALITY is enabled, this will increase the size of the Xevent file and may impact performance."
  }



  if ($true -eq $returnVariable)
  {
    Write-LogDebug "Returned variable without creating file, this maybe due to use of GUI to filter out some of the xevents"

    $content = $content -split "`r`n"
    return $content
  }

  if (-Not (Test-Path $fileName))
  {
    Set-Content -Path $fileName -Value $content
  } 
  else 
  {
    Write-LogDebug "$fileName already exists, likely generated by GUI"

    # append to the $fileName the $track_causality if it exists
    if (($global:gAdditionalOptionsEnabled -contains "TrackCausality") -and ($track_causality)) 
    {
        Add-Content -Path $fileName -Value $track_causality
        Write-LogDebug "Appended TRACK_CAUSALITY=ON to existing file $fileName"
    }
  }



  #check if last command was successful, then add the file to the list for cleanup AND return collector name
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAhGooNc8cmI4gQ
# FsLVZhY7LILnWytNkvhv4KkIq7KrzaCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILJrHcc7bZPbf9703H3wjP6oQeM9j4Le
# WnkF2UdnNJqlMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# YZSTfz0w4P/AOtUG8vHPpGKbc80DErvKhxpI/eskjf1EESq8X/JaS0pvHJZcU9Ze
# N4LWfXrTYDbi5PIZRM7/pA3WELso07PXOFZWiymYZTbaZz0zEQ1ri2ZbeGTP9K54
# jmwW+LXX6VnFWFdNVeg031bpYgxRFd3GpcCfsdra+e757LgNUkpr1Plu3BCnvOc8
# 4RCYH1/Un8f63zZL1LMRPq+n5rrMKMh73uPyWs4SV/RBUtpa8gs1WV+mniLHmw7A
# vlnikBKMIq/JZSPMCk/rHxpNN8sr39IFLlq1JFxR4i558Unsw+139j32GFJgj96P
# +A8KtvT3OCbsK7Ift3N1hKGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCD/Xz67dhBbVR5jQcJXw344+AQDt0tm6Dam+NNEw4AA/wIGaWjo97F3GBMyMDI2
# MDIwNDE2MzUzNS4xODJaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
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
# DQEJBDEiBCCTyaAjJbeT8PD8POCL9mg4VkUMDwQHwe1jfAmVY41zpDCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EINUo17cFMZN46MI5NfIAg9Ux5cO5xM9inre5
# riuOZ8ItMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIMuWTjNZzs9K4AAQAAAgwwIgQgT+jPnBIIP9shvRM8rjFVYz7ININcDtUTh1HB
# 3F0DtIUwDQYJKoZIhvcNAQELBQAEggIAOPKU3cFUKHAZRrxdaiLAtmyv92+lBCPK
# vYKFh2b4pfS2RJufG23DzMOJcIvCkU33KC5m+iga0mJGjGolArn/DzZU8BiNmR4t
# HX0PBTzNOmwEQO2fQmvhlBLx868FoyADnylg/9VHi9AI+rDi4SRXSkLlM6P/zRJ6
# kbhmww6UOFkP1i7P1g3zIAWmk6k+FcSwr7jx9bwg7rS/OFfcMqsoZVwoLhQ+xzF0
# 1BNyqAJZb7301BbqYfVQyJCspMC0I1pXXACB64dqB/w0KNyRy3pmzkQLZw8yHh4Z
# Z8carXrkqlBz1Hwm6aJc17+dNxcN/GQlk3HCUmk124xciByv5RYqHBM0RuWJTfho
# P0MmM8iZStP5ONc2yO3Lz+4w8nEQnW15MdKXanCoiqOl2jlRMKay6D8ynoCwqAhi
# oW0OrDSIJr/5PKqBuWgMnunDU+iDWfF1G4rbfRhZOtV4+xS9PKOxeqLzQXd4mBfP
# jzB3nwczCE8V7JsH16BGHNf4z9EAOIrN1xhExUPBveBjaDDRgg3PfhWHtE2Bom9c
# Htqla0o+ZmNIzqtRPqr/FitIRTxq7rN3Rc3/vaRYx/7ryLc0gpzP83Noqjy4VpUJ
# 4mE4Hi/jti5C+/EKR3tfa/eWlkM9kOG0fHdccAbf5XwHnHjgWBv2PnUFU1fPnEbu
# njVCWP5Mhn0=
# SIG # End signature block
