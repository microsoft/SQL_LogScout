
    function Change_Tracking_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "Change_Tracking"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
    
    
/*
Purpose:	Change Tracking Script for PSSDiag
Date:		1/3/2020
Note:		
Version:	1.4
Change List: Added CT_oject_id and cleanup_version_commit_time
10/1/21 -- added section to collect cleanup History
*/


USE master
go

SET NOCOUNT ON
SET QUOTED_IDENTIFIER ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @StartTime datetime
select @@version as 'Version'
select GETDATE() as 'RunDateTime', GETUTCDATE() as 'RunUTCDateTime', SYSDATETIMEOFFSET() as 'SysDateTimeOffset'

select @@servername as 'ServerName'
PRINT '-- CT enabled databases --' 
SELECT
	db.name AS change_tracking_db,
	ct.database_id,
	is_auto_cleanup_on,
	retention_period,
	retention_period_units_desc
FROM sys.change_tracking_databases ct
JOIN sys.databases db on
	ct.database_id=db.database_id;
PRINT ''


-- Loop Through DBs and Gather CT information specific to each DB
DECLARE tnames_cursor CURSOR
FOR SELECT
	db.name AS name
FROM sys.change_tracking_databases ct
JOIN sys.databases db on
	ct.database_id=db.database_id;


OPEN tnames_cursor;
DECLARE @dbname sysname;
DECLARE @cmd3 nvarchar(1024); -- New Command
FETCH NEXT FROM tnames_cursor INTO @dbname;
WHILE (@@FETCH_STATUS = 0)
BEGIN

	select @dbname = RTRIM(@dbname);
	EXEC ('USE [' + @dbname + ']');
		BEGIN
		PRINT ''
		PRINT '====================================================================================='
		PRINT 'Begin Database: ' + @dbname
		SELECT @StartTime = GETDATE()
		PRINT 'Start Time : ' + CONVERT(Varchar(50), @StartTime)
		
		PRINT ''
		PRINT '-- Tables involved in CT --'
		EXEC ('SELECT 
				sc.name as tracked_schema_name,
				so.name as tracked_table_name,
				ctt.is_track_columns_updated_on,
				ctt.begin_version /*when CT was enabled, or table was truncated */,
				ctt.min_valid_version /*syncing applications should only expect data on or after this version */ ,
				ctt.cleanup_version /*cleanup may have removed data up to this version */,
				dtc.commit_time as cleanup_version_commit_time /*Cleanup version commit_time*/
				FROM [' + @dbname + '].sys.change_tracking_tables AS ctt
				JOIN [' + @dbname + '].sys.objects AS so on
				ctt.[object_id]=so.[object_id]
				JOIN sys.schemas AS sc on
				so.schema_id=sc.schema_id
				JOIN [' + @dbname + '].sys.dm_tran_commit_table dtc on
				ctt.cleanup_version = dtc.commit_ts;');


		PRINT ''
		PRINT 'Committed transactions in the commit_table --'
		EXEC ('SELECT
				count(*) AS number_commits,
				MIN(commit_ts) AS minimum_commit_ts,
				MIN(commit_time) AS minimum_commit_time,
				MAX(commit_ts) AS maximum_commit_ts,
				MAX(commit_time) AS maximum_commit_time
				FROM [' + @dbname + '].sys.dm_tran_commit_table;');	
	
   		PRINT ''
		PRINT 'Size of internal CT tables --'
		EXEC ('
			select sct1.name as CT_schema,
			sot1.name as CT_table,
			sot1.object_id as CT_oject_id,
			ps1.row_count as CT_rows,
			ps1.used_page_count*8./1024. as CT_used_MB,
			sct2.name as tracked_schema,
			sot2.name as tracked_name,
			ps2.row_count as tracked_rows,
			ps2.used_page_count*8./1024. as tracked_base_table_MB 
			FROM
				[' + @dbname + '].sys.internal_tables it
			JOIN [' + @dbname + '].sys.objects sot1 on it.object_id=sot1.object_id
			JOIN [' + @dbname + '].sys.schemas AS sct1 on
					sot1.schema_id=sct1.schema_id
			JOIN [' + @dbname + '].sys.dm_db_partition_stats ps1 on
				it.object_id = ps1. object_id
				and ps1.index_id in (0,1)
			LEFT JOIN [' + @dbname + '].sys.objects sot2 on it.parent_object_id=sot2.object_id
			LEFT JOIN [' + @dbname + '].sys.schemas AS sct2 on
				sot2.schema_id=sct2.schema_id
			LEFT JOIN [' + @dbname + '].sys.dm_db_partition_stats ps2 on
				sot2.object_id = ps2. object_id
				and ps2.index_id in (0,1)
			WHERE it.internal_type IN (209, 210)
			order by 4 desc ;');	

		PRINT 'Get the Safe and Hardened Cleanup version. Run on 2014 Sp2 / 2016 Sp1 and above--'
		EXEC ( '[' + @dbname + ']..sp_flush_commit_table_on_demand 1;');


		PRINT ''
		PRINT 'Active Snapshot transactions --'
		EXEC ('select top 10 * from [' 
		+ @dbname + '].sys.dm_tran_active_snapshot_database_transactions order by elapsed_time_seconds desc');	

		PRINT ''
		PRINT 'CT Cleanup History --'
		EXEC ('
		IF OBJECT_ID(' + '''' + @dbname + '.dbo.MSchange_tracking_history'+ '''' +','+ ''''+ 'U'+''''+ ') IS NOT NULL 
		BEGIN
		  select top 1000 * from ' + @dbname + '.[dbo].[MSchange_tracking_history] order by start_time desc
		END
		')


   PRINT ''
   PRINT 'End of Database: ' + @dbname 
   PRINT 'END Time : ' + CONVERT(Varchar(50), GetDate())
   PRINT 'Data Collection Duration in milliseconds for ' + @dbname
   PRINT ''
   SELECT DATEDIFF(millisecond, @StartTime, GETDATE()) as Duration_ms

   PRINT '====================================================================================='
   PRINT '====================================================================================='
   PRINT '' 
   END;
   FETCH NEXT FROM tnames_cursor INTO @dbname;
END;
CLOSE tnames_cursor;
DEALLOCATE tnames_cursor;
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBOsFn06Z+Pg9Lb
# FIcA5x7iB+8ALGxSKD24blxsPOWdMKCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILtVPdyWDtQd
# 5QF1gM9042OZeVy/9gGpVmKECBZ9X76hMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAcN4m3JZmHTiimG1cfPLOqLLMT9+bGelKkebqP4hjZyXr
# TK1v8krj3NpsvHm9uv/lpaUEsCD1GQ71gH8q1opfzUxUWkfy3UUAwDbsox3Uoh1n
# FaSg+y5jmmix3x7lKSS2oa7JAK13SYnFmwD9sL5XEFz8aCohkl39wQNTDIBxe4TX
# 2SLnqY4fvDjuLDL3zpEDv1S56xj00g6Q+QmcHPeV+5oDXkNF4j3PJqplQTZU9d4U
# 6N1xJ/ZTxk1kqNH35VCKMecGmgWZw3aZMudXkMD/i5dnA/ec3f4BKlKBTqZ+GprL
# sPe0Bg0M7A8PqS6heQgh20EKw0YuJaExHAAv1kjNe6GCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCBYuP8MG/BNPsgnQsnhQeMOH+iKlIkvv2KLD0IBkAjO
# pQIGaXOd2U1KGBMyMDI2MDIwNDE2MzUyNy4zMzZaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjoyQTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACEKvN5BYY7zmw
# AAEAAAIQMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgxMloXDTI2MTExMzE4NDgxMlowgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjJBMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAjcc4q057
# ZwIgpKu4pTXWLejvYEduRf+1mIpbiJEMFWWmU2xpip+zK7xFxKGB1CclUXBU0/ZQ
# Z6LG8H0gI7yvosrsPEI1DPB/XccGCvswKbAKckngOuGTEPGk7K/vEZa9h0Xt02b7
# m2n9MdIjkLrFl0pDriKyz0QHGpdh93X6+NApfE1TL24Vo0xkeoFGpL3rX9gXhIOF
# 59EMnTd2o45FW/oxMgY9q0y0jGO0HrCLTCZr50e7TZRSNYAy2lyKbvKI2MKlN1wL
# zJvZbbc//L3s1q3J6KhS0KC2VNEImYdFgVkJej4zZqHfScTbx9hjFgFpVkJl4xH5
# VJ8tyJdXE9+vU0k9AaT2QP1Zm3WQmXedSoLjjI7LWznuHwnoGIXLiJMQzPqKqRIF
# L3wzcrDrZeWgtAdBPbipglZ5CQns6Baj5Mb6a/EZC9G3faJYK5QVHeE6eLoSEwp1
# dz5WurLXNPsp0VWplpl/FJb8jrRT/jOoHu85qRcdYpgByU9W7IWPdrthmyfqeAw0
# omVWN5JxcogYbLo2pANJHlsMdWnxIpN5YwHbGEPCuosBHPk2Xd9+E/pZPQUR6v+D
# 85eEN5A/ZM/xiPpxa8dJZ87BpTvui7/2uflUMJf2Yc9ZLPgEdhQQo0LwMDSTDT48
# y3sV7Pdo+g5q+MqnJztN/6qt1cgUTe9u+ykCAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBSe42+FrpdF2avbUhlk86BLSH5kejAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# vs4rO3oo8czOrxPqnnSEkUVq718QzlrIiy7/EW7JmQXsJoFxHWUF0Ux0PDyKFDRX
# PJVv29F7kpJkBJJmcQg5HQV7blUXIMWQ1qX0KdtFQXI/MRL77Z+pK5x1jX+tbRkA
# 7a5Ft7vWuRoAEi02HpFH5m/Akh/dfsbx8wOpecJbYvuHuy4aG0/tGzOWFCxMMNhG
# AIJ4qdV87JnY/uMBmiodlm+Gz357XWW5tg3HrtNZXuQ0tWUv26ud4nGKJo/oLZHP
# 75p4Rpt7dMdYKUF9AuVFBwxYZYpvgk12tfK+/yOwq84/fjXVCdM83Qnawtbenbk/
# lnbc9KsZom+GnvA4itAMUpSXFWrcRkqdUQLN+JrG6fPBoV8+D8U2Q2F4XkiCR6EU
# 9JzYKwTuvL6t3nFuxnkLdNjbTg2/yv2j3WaDuCK5lSPgsndIiH6Bku2Ui3A0aUo6
# D9z9v+XEuBs9ioVJaOjf/z+Urqg7ESnxG0/T1dKci7vLQ2XNgWFYO+/OlDjtGoma
# 1ijX4m14N9qgrXTuWEGwgC7hhBgp3id/LAOf9BSTWA5lBrilsEoexXBrOn/1wM3r
# jG0hIsxvF5/YOK78mVRGY6Y7zYJ+uXt4OTOFBwadPv8MklreQZLPnQPtiwop4rlL
# UYaPCiD4YUqRNbLp8Sgyo9g0iAcZYznTuc+8Q8ZIrgwwggdxMIIFWaADAgECAhMz
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
# bGQgVFNTIEVTTjoyQTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAOsyf2b6riPKnnXlIgIL2
# f53PUsKggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0t7YkwIhgPMjAyNjAyMDQxNjA4NDFaGA8yMDI2MDIwNTE2
# MDg0MVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7S3tiQIBADAKAgEAAgIE6AIB
# /zAHAgEAAgISszAKAgUA7S8/CQIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IB
# AQAbd/A2xPd2kx8o3momOdlE3W4wDnfg5fxTAjo73zs0TyjZPWmt+hVm87jSA+DI
# aqpaLu8wa+Aosh6psX6wSzlYnXkTY1fDgjgkEYcvJ4j8vTXj6QQcvnuOUX8yqlo6
# rkCMPXuH0fHCFWCE4/hX0Vp7HisFsq9VKYyXMcChYN61BBVPdc+OG9BrCrbsep+s
# +G1NKgI4NqtCPKRduls8SXKzOYhGzvlkU2GiiplHIypNupgzKeMC8Xqi28ECmYjY
# 7a1f+KjZMsxEJPKzea31apPFOZsJs9M1iM/ek8Fe3z3urXXh8qHewsWW3/oxXWrS
# kboJxb1smnI1HUsOVnFYmnVtMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIQq83kFhjvObAAAQAAAhAwDQYJYIZIAWUDBAIB
# BQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgCsdoUnbK1xo6V1vnagVz9ZeGZUcTwUeY3dGJ4uAlvR8wgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCDD1SHufsjzY59S1iHUQY9hnsKSrJPg5a9Mc4YnGmPH
# xjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACEKvN
# 5BYY7zmwAAEAAAIQMCIEIG3yvOZ7LOtyGf17rtSzYjgf2DoeKomwsuam2J/peVaM
# MA0GCSqGSIb3DQEBCwUABIICADALyp0GYPGUgDqdslqDrMUL6sp3S+DmnSmoRpOK
# 8yUjjarvscOy/g1lPuJYnNtEYH2uW/IHzOt9EA8pV7qQKZrd0WECCbCClR6w1Wr3
# CJJOw9wFpDL/6OGfiTNFN6mvxXLYN851PwYnZbG1i6m1fRuzjnhK4o4W0sid/OYl
# HOJBpzFlXbgCuqt26gRXt7Z+96zlRVQJ7FXzMk74zgXaT1tcQi6fzEYEJ15XwfaI
# eK/sIVGn9cNzpYUhOBUw/iSxy3HEvKpKJ/wt8j97/pEMpUl0/V3Pe4sARsaM2g0+
# BsY5eKzTUP3GAFGyG3NFz9dIMCDjo6t1alWHiM8owQFNLEXoNzxkj5fyjrq6u0XY
# TWNR4vCFYAbF9RxOT8Tcr2IKTizQ6cBHUb8sAWovIOeNivUSv+0LQ7kkxsg+1rC9
# XTEzm2hZn5T7CFZkVsxY1mlYIJzwJnkn1wsalvkeRpYp4MNYs+uGVDskSCVwu6n/
# 1paZiT+crsobNGBEhhy08xRElnu4Zk4qylTUo6f4zRfmsQzAV78fvU9kQdZbghxx
# wWMCr14nvVHNtDkM30zl/h7oxFiyQpjk4p4YBqOKGtkWVTNCaixBdLdieajDFqPy
# YvuFNW4VLxIhEQRSehTD2aZ8V4pIpYevjV8QVdNOMYa1ccSzx6FyfffKqs/rLN/M
# SKnQ
# SIG # End signature block
