
    function FullTextSearchMetadata_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "FullTextSearchMetadata"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
PRINT '-------------------------------------------'
PRINT '---- FullTextSearch Information Collector'
PRINT '---- `$Date: 2024/06/28 `$'
PRINT '---- `$Comments: Replaced calls to xp procs by dmvs to improve security'
PRINT '---- `$Comments: Improvements in the output, adding info from all dbs on the same resultset'
PRINT '---- `$Comments: Fixing issue to retrive data from StoLists and Stopwords info'
PRINT '-------------------------------------------'
PRINT ''

PRINT 'Start Time: ' + CONVERT (VARCHAR(30), GETDATE(), 121)
PRINT ''

GO

DECLARE @IsFullTextInstalled INT

PRINT ''

PRINT '-- Full-text Service Information --'

PRINT '-- FULLTEXTSERVICEPROPERTY (IsFulltextInstalled) --'
SET @IsFullTextInstalled = FULLTEXTSERVICEPROPERTY ('IsFulltextInstalled')
PRINT CASE @IsFullTextInstalled 
WHEN 1 THEN '1 - Yes' 
WHEN 0 THEN '0 - No' 
ELSE 'Unknown'
END

IF (@IsFullTextInstalled = 1)
BEGIN

    PRINT ''
    PRINT '-- FULLTEXTSERVICEPROPERTY (Memory ResourceUsage) --'
    PRINT CASE FULLTEXTSERVICEPROPERTY ('ResourceUsage')
    WHEN 1 THEN '1 - Least Aggressive (Background)'
    WHEN 2 THEN '2 - Low'
    WHEN 3 THEN '3 - Normal (Default)'
    WHEN 4 THEN '4 - High'
    WHEN 5 THEN '5 - Most Aggressive (Highest)'
    ELSE CONVERT (VARCHAR, FULLTEXTSERVICEPROPERTY ('ResourceUsage'))
END

PRINT ''
PRINT '-- FULLTEXTSERVICEPROPERTY (LoadOSResources) --'
PRINT CASE FULLTEXTSERVICEPROPERTY ('LoadOSResources')
WHEN 1 THEN '1 - Loads OS filters and word breakers.'
WHEN 0 THEN '0 - Use only filters and word breakers specific to this instance of SQL Server. Equivalent to ~DOES NOT LOAD OS filters/word-breakers~' 
ELSE CONVERT (VARCHAR, FULLTEXTSERVICEPROPERTY ('LoadOSResources'))
END

PRINT ''
PRINT '-- FULLTEXTSERVICEPROPERTY (VerifySignature) --'
PRINT CASE FULLTEXTSERVICEPROPERTY ('VerifySignature')
WHEN 1 THEN '1 - Verify that only trusted, signed binaries are loaded.'
WHEN 0 THEN '0 - Do not verify whether or not binaries are signed. (Unsigned binaries can be loaded)' 
ELSE CONVERT (VARCHAR, FULLTEXTSERVICEPROPERTY ('VerifySignature'))
END

PRINT ''
END

GO

SET NOCOUNT ON

GO

DECLARE @execoutput NVARCHAR(1000)
PRINT '-- SQL Full-text Filter Daemon Launcher Startup Account --'

SELECT servicename , service_account FROM sys.dm_server_services
WHERE servicename LIKE '%Full-text%'

GO

PRINT ''
PRINT '-- tbl_FullText_Catalog_Info_Properties --'

IF OBJECT_ID('tempdb..#tbl_FullText_Catalog_Info_Properties') IS NOT NULL
BEGIN
	DROP TABLE #tbl_FullText_Catalog_Info_Properties
END

CREATE TABLE #tbl_FullText_Catalog_Info_Properties(
	[DatabaseName] SYSNAME NOT NULL,
	[CatalogName] SYSNAME NOT NULL,
	[CatalogID] INT NOT NULL,
	[ErrorLogSize] INT NULL,
	[FullTextIndexSize] INT NULL,
	[ItemCount] INT NULL,
	[UniqueKeyCount] INT NULL,
	[PopulationStatus] VARCHAR(100) NOT NULL,
	[ChangeTracking] NVARCHAR(100) NULL,
	[IsMasterMergeHappening] INT NULL,
	[LastCrawlType] NVARCHAR(100) NULL,
	[LastCrawlSTARTDate] DATETIME NULL,
	[LastCrawlENDDate] DATETIME NULL,
	[CatalogRootPath] NVARCHAR(500) NOT NULL
)
GO

DECLARE @databases table
(id INT IDENTITY(1,1) PRIMARY KEY,
 dbname SYSNAME
)

DECLARE @count INT
DECLARE @maxcount INT
DECLARE @dbname SYSNAME
DECLARE @sql NVARCHAR(MAX)

INSERT INTO @databases
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'

SET @count = 1
SET @maxcount = (SELECT MAX(id) FROM @databases)

WHILE (@count <= @maxcount)
BEGIN

	SET @dbname = (SELECT dbname FROM @databases WHERE id = @count)
    SET @sql = 'USE [' + @dbname + '];'
	SET @sql = @sql + N'IF EXISTS (SELECT * FROM ['+@dbname+N'].sys.fulltext_catalogs) 
                        BEGIN 
						  INSERT INTO #tbl_FullText_Catalog_Info_Properties
                          SELECT 
                            ''' + @dbname + ''' AS [DatabaseName],
                            cat.name AS [CatalogName], cat.fulltext_catalog_id AS [CatalogID],
                            FULLTEXTCATALOGPROPERTY(cat.name,''LogSize'') AS [ErrorLogSize], 
                            FULLTEXTCATALOGPROPERTY(cat.name,''IndexSize'') AS [FullTextIndexSize], 
                            FULLTEXTCATALOGPROPERTY(cat.name,''ItemCount'') AS [ItemCount], 
                            FULLTEXTCATALOGPROPERTY(cat.name,''UniqueKeyCount'') AS [UniqueKeyCount], 
                            [PopulationStatus] = CASE 
                            WHEN FULLTEXTCATALOGPROPERTY(cat.name,''PopulateStatus'') = 0 THEN ''Idle''
                            WHEN FULLTEXTCATALOGPROPERTY(cat.name,''PopulateStatus'') = 1 THEN ''Full population in progress'' 
                            WHEN FULLTEXTCATALOGPROPERTY(cat.name,''PopulateStatus'') = 2 THEN ''Paused''
                            WHEN FULLTEXTCATALOGPROPERTY(cat.name,''PopulateStatus'') = 4 THEN ''Recovering''
                            WHEN FULLTEXTCATALOGPROPERTY(cat.name,''PopulateStatus'') = 6 THEN ''Incremental population in progress''
                            WHEN FULLTEXTCATALOGPROPERTY(cat.name,''PopulateStatus'') = 7 THEN ''Building index''
                            WHEN FULLTEXTCATALOGPROPERTY(cat.name,''PopulateStatus'') = 9 THEN ''Change tracking''
                            ELSE ''Other Status(3/5/8)''END,
                            tbl.change_tracking_state_desc AS [ChangeTracking],
                            FULLTEXTCATALOGPROPERTY(cat.name,''MergeStatus'') AS [IsMasterMergeHappening],
                            tbl.crawl_type_desc AS [LastCrawlType],
                            tbl.crawl_start_date AS [LastCrawlSTARTDate],
                            tbl.crawl_end_date AS [LastCrawlENDDate],
                            ISNULL(cat.path,N'''') AS [CatalogRootPath] 
						  FROM sys.fulltext_catalogs AS cat 
                          LEFT OUTER JOIN sys.filegroups AS fg ON cat.data_space_id = fg.data_space_id 
                          LEFT OUTER JOIN sys.database_principals AS dp ON cat.principal_id=dp.principal_id 
                          LEFT OUTER JOIN sys.fulltext_indexes AS tbl ON cat.fulltext_catalog_id = tbl.fulltext_catalog_id  
                        END'
	EXEC sp_executesql @sql
	SET @count = @count + 1 

END

SELECT * FROM #tbl_FullText_Catalog_Info_Properties

PRINT ''
PRINT '-- tbl_FullText_Index_Info_table --'

IF OBJECT_ID('tempdb..#tbl_FullText_Index_Info_table') IS NOT NULL
BEGIN
	DROP TABLE #tbl_FullText_Index_Info_table
END

CREATE TABLE #tbl_FullText_Index_Info_table(
	[DatabaseName] SYSNAME NOT NULL,
	[TableName] SYSNAME NOT NULL,
	[CatalogName]SYSNAME NOT NULL,
	[IsEnabled] BIT NULL,
	[PopulationStatus] INT NULL,
	[ChangeTracking] INT NOT NULL,
	[ItemCount] INT NULL,
	[DocumentsProcessed] INT NULL,
	[PendingChanges] INT NULL,
	[NumberOfFailures] INT NULL,
	[UniqueIndexName] SYSNAME NULL
) 

SET @count = 1
SET @dbname = (SELECT dbname FROM @databases WHERE id = @count)

WHILE (@count <= @maxcount)
BEGIN

	SET @dbname = (SELECT dbname FROM @databases WHERE id = @count)
	SET @sql = 'USE [' + @dbname + '];'
	SET @sql = @sql + N'IF EXISTS (SELECT * FROM ['+@dbname+'].sys.fulltext_indexes WHERE is_enabled=1) 
                   BEGIN
					INSERT INTO #tbl_FullText_Index_Info_table
                    SELECT 
                        ''' + @dbname + ''' AS [DatabaseName],
                        sobj.name as [TableName], cat.name AS [CatalogName],
                        CAST(fti.is_enabled AS bit) AS [IsEnabled],
                        OBJECTPROPERTY(fti.object_id,''TableFullTextPopulateStatus'') AS [PopulationStatus],
                        (case change_tracking_state when ''M'' then 1 when ''A'' then 2 ELSE 0 END) AS [ChangeTracking],
                        OBJECTPROPERTY(fti.object_id,''TableFullTextItemCount'') AS [ItemCount],
                        OBJECTPROPERTY(fti.object_id,''TableFullTextDocsProcessed'') AS [DocumentsProcessed],
                        OBJECTPROPERTY(fti.object_id,''TableFullTextPendingChanges'') AS [PendingChanges],
                        OBJECTPROPERTY(fti.object_id,''TableFullTextFailCount'') AS [NumberOfFailures],
                        si.name AS [UniqueIndexName]
					FROM sys.tables AS tbl
                    INNER JOIN sys.fulltext_indexes AS fti ON fti.object_id=tbl.object_id
                    INNER JOIN sys.fulltext_catalogs AS cat ON cat.fulltext_catalog_id = fti.fulltext_catalog_id
                    INNER JOIN sys.indexes AS si ON si.index_id=fti.unique_index_id and si.object_id=fti.object_id
                    INNER JOIN sys.sysobjects as sobj ON fti.object_id=sobj.id
                   END'

	EXEC sp_executesql @sql
	SET @count = @count + 1 
END

SELECT * FROM #tbl_FullText_Index_Info_table

PRINT ''

PRINT '-- tbl_FullText_Column_Info --'

IF OBJECT_ID('tempdb..#tbl_FullText_Column_Info') IS NOT NULL
BEGIN
	DROP TABLE #tbl_FullText_Column_Info
END

CREATE TABLE #tbl_FullText_Column_Info(
	[DatabaseName] SYSNAME NOT NULL,
	[ColumnName] SYSNAME NULL,
	[TableName] SYSNAME NOT NULL
) 

SET @count = 1

WHILE (@count <= @maxcount)
BEGIN

	SET @dbname = (SELECT dbname FROM @databases WHERE id = @count)
    SET @sql = 'USE [' + @dbname + '];'

	SET @sql = @sql + N'IF EXISTS (SELECT * FROM ['+@dbname+'].sys.fulltext_index_columns) 
                   BEGIN 
					INSERT INTO #tbl_FullText_Column_Info
                    SELECT 
                     ''' + @dbname + ''' AS [DatabaseName],   
                     col.name AS [ColumnName], 
                     sobj.name AS [TableName]
					FROM sys.tables AS tbl
                    INNER JOIN sys.fulltext_indexes AS fti ON fti.object_id=tbl.object_id
                    INNER JOIN sys.fulltext_index_columns AS icol ON icol.object_id=fti.object_id
                    INNER JOIN sys.columns AS col ON col.object_id = icol.object_id and col.column_id = icol.column_id
                    INNER JOIN sys.sysobjects as sobj ON icol.object_id=sobj.id
                   END'

	EXEC sp_executesql @sql
	SET @count = @count + 1 

END

SELECT * FROM #tbl_FullText_Column_Info

PRINT ''
PRINT '-- tbl_FullText_WordBreaking_Language_Info --'

IF OBJECT_ID('tempdb..#tbl_FullText_WordBreaking_Language_Info') IS NOT NULL
BEGIN
	DROP TABLE #tbl_FullText_WordBreaking_Language_Info
END

CREATE TABLE #tbl_FullText_WordBreaking_Language_Info(
	[DatabaseName] SYSNAME NOT NULL,
	[ObjectID] INT NOT NULL,
	[TableName] SYSNAME NOT NULL,
	[ColumnName] SYSNAME NULL,
	[WordBreaker_Language] NVARCHAR(500) NOT NULL,
	[LCID] [int] NOT NULL
)

SET @count = 1

WHILE (@count <= @maxcount)
BEGIN

	SET @dbname = (SELECT dbname FROM @databases WHERE id = @count)
    SET @sql = 'USE [' + @dbname + '];'

	SET @sql = @sql + N'IF EXISTS (SELECT * FROM ['+@dbname+'].sys.fulltext_indexes WHERE is_enabled=1)
                        BEGIN
							INSERT INTO #tbl_FullText_WordBreaking_Language_Info
                            SELECT 
                                ''' + @dbname + ''' AS [DatabaseName],   
                                tbl.object_id as [ObjectID], 
                                tbl.name as [TableName], 
                                col.name AS [ColumnName], 
                                sl.name AS [WordBreaker_Language], 
                                sl.lcid AS [LCID]
							FROM sys.tables AS tbl
                            INNER JOIN sys.fulltext_indexes AS fti ON fti.object_id=tbl.object_id
                            INNER JOIN sys.fulltext_index_columns AS icol ON icol.object_id=fti.object_id
                            INNER JOIN sys.columns AS col ON col.object_id = icol.object_id and col.column_id = icol.column_id
                            INNER JOIN sys.fulltext_languages AS sl ON sl.lcid=icol.language_id
                        END'

	EXEC sp_executesql @sql
	SET @count = @count + 1 

END

SELECT * FROM #tbl_FullText_WordBreaking_Language_Info

PRINT ''
PRINT '-- tbl_FullText_IFilters --'

SELECT document_type as [Extension], manufacturer, version, path, class_id FROM sys.fulltext_document_types

PRINT ''
PRINT '-- tbl_FullText_NonMicrosoft_IFilters --'

SET @count = (SELECT count(*) FROM sys.fulltext_document_types WHERE manufacturer NOT LIKE 'Microsoft Corporation' and path NOT LIKE '%offfilt%')
IF(@count <> 0)
BEGIN
    SELECT document_type as [Extension], manufacturer, version, path, class_id FROM sys.fulltext_document_types WHERE manufacturer NOT LIKE 'Microsoft Corporation' and path NOT LIKE '%offfilt%' 
END
ELSE
BEGIN
    PRINT 'No Non-Microsoft filters loaded'
PRINT ''
END

PRINT ''
PRINT '-- tbl_FullText_StopLists --'

IF OBJECT_ID('tempdb..#tbl_FullText_StopLists') IS NOT NULL
BEGIN
	DROP TABLE #tbl_FullText_StopLists
END

CREATE TABLE #tbl_FullText_StopLists(
    [DatabaseName] SYSNAME NOT NULL,
	[stoplist_id] [int] NOT NULL,
	[name] [sysname] NOT NULL,
	[create_date] [datetime] NOT NULL,
	[modify_date] [datetime] NOT NULL,
	[principal_id] [int] NULL
) 

SET @count = 1

WHILE (@count <= @maxcount)
BEGIN

    SET @dbname = (SELECT dbname FROM @databases WHERE id = @count)
    SET @sql = 'USE [' + @dbname + '];'

	SET @sql = @sql + N'IF EXISTS (SELECT * FROM ['+@dbname+'].sys.fulltext_stoplists)
                        BEGIN 
						    INSERT INTO #tbl_FullText_StopLists
                            SELECT ''' + @dbname + ''' AS [DatabaseName]   
                                   ,stoplist_id
                                   ,name
                                   ,create_date
                                   ,modify_date
                                   ,principal_id 
                            FROM sys.fulltext_stoplists
                        END'

	EXEC sp_executesql @sql
	SET @count = @count + 1 

END

SELECT * FROM #tbl_FullText_StopLists

PRINT ''
PRINT '-- tbl_FullText_StopWords --'

IF OBJECT_ID('tempdb..#tbl_FullText_StopWords') IS NOT NULL
BEGIN
	DROP TABLE #tbl_FullText_StopWords
END

CREATE TABLE #tbl_FullText_StopWords(
    [DatabaseName] SYSNAME NOT NULL,
	[stoplist_id] [int] NOT NULL,
	[stopword] [nvarchar](64) NOT NULL,
	[language] [nvarchar](128) NOT NULL,
	[language_id] [int] NOT NULL
) 

SET @count = 1


WHILE (@count <= @maxcount)
BEGIN

    SET @dbname = (SELECT dbname FROM @databases WHERE id = @count)
    SET @sql = 'USE [' + @dbname + '];'

	SET @sql = @sql + N'IF EXISTS (SELECT * FROM ['+@dbname+'].sys.fulltext_stopwords)
                        BEGIN 
							INSERT INTO #tbl_FullText_StopWords
                            SELECT ''' + @dbname + ''',    
                                   stoplist_id,
	                               stopword,
	                               language,
	                               language_id
                            FROM sys.fulltext_stopwords
                        END'
	EXEC sp_executesql @sql
	SET @count = @count + 1 

END

SELECT * FROM #tbl_FullText_StopWords

GO
PRINT ''
PRINT 'End Time: ' + CONVERT (VARCHAR(30), GETDATE(), 121)
GO
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD1ggY2mAvJvX/W
# 97eNHaRr4ThN8EHdqdm0YNnjCTQ1raCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJPY+JcciP1qIJGzcsMD7PZrAuR4VIiN
# bwwih9+Xjg25MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# DiQj9+FQZPxZ4ngSZ9ej0CeKXwXLjagEF/9hy6PrrLHHwbHVqu9dmYWLTTbXaUFY
# fJRVUAODBFlOkOm2THhbeIH9vSQy35k+AZTnMvARkHzQXbs2MQjc+Cii6kPQJBzy
# SluHs/xErbrU9Xj+MyqCLZ93yRC1dv1AogKYTkA1QxKLyqvslnDEt1Yh+QI9p9iD
# j7bOCaf+Cz8jz66JZO5DdcI+iyabcQzEoVklU8UEbiNnxPa9AL8XfS7csfcd6yO4
# X8/I8kBMnE3DrFhaT8sLhyzCBmyP1I55CM89o/Q5OPAo3PwJdBlPC6wxHeMJ75Tq
# ZVSK3SIhkfKWoGv39SLQ3aGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCDhJ+Vc754KIIvgm6UEzVpum/2+ieS0dIRNMGOEn1/14AIGaWj23IQ9GBMyMDI2
# MDIwNDE2MzUyOC43MTlaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046REMwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIH
# IDCCBQigAwIBAgITMwAAAgO7HlwAOGx0ygABAAACAzANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNDZaFw0y
# NjA0MjIxOTQyNDZaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046REMwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQChl0MH5wAnOx8Uh8RtidF0J0yaFDHJYHTpPvRR16X1KxGDYfT8
# PrcGjCLCiaOu3K1DmUIU4Rc5olndjappNuOgzwUoj43VbbJx5PFTY/a1Z80tpqVP
# 0OoKJlUkfDPSBLFgXWj6VgayRCINtLsUasy0w5gysD7ILPZuiQjace5KxASjKf2M
# VX1qfEzYBbTGNEijSQCKwwyc0eavr4Fo3X/+sCuuAtkTWissU64k8rK60jsGRApi
# ESdfuHr0yWAmc7jTOPNeGAx6KCL2ktpnGegLDd1IlE6Bu6BSwAIFHr7zOwIlFqyQ
# uCe0SQALCbJhsT9y9iy61RJAXsU0u0TC5YYmTSbEI7g10dYx8Uj+vh9InLoKYC5D
# pKb311bYVd0bytbzlfTRslRTJgotnfCAIGMLqEqk9/2VRGu9klJi1j9nVfqyYHYr
# MPOBXcrQYW0jmKNjOL47CaEArNzhDBia1wXdJANKqMvJ8pQe2m8/cibyDM+1BVZq
# uNAov9N4tJF4ACtjX0jjXNDUMtSZoVFQH+FkWdfPWx1uBIkc97R+xRLuPjUypHZ5
# A3AALSke4TaRBvbvTBYyW2HenOT7nYLKTO4jw5Qq6cw3Z9zTKSPQ6D5lyiYpes5R
# R2MdMvJS4fCcPJFeaVOvuWFSQ/EGtVBShhmLB+5ewzFzdpf1UuJmuOQTTwIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFLIpWUB+EeeQ29sWe0VdzxWQGJJ9MB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQCQEMbesD6TC08R0oYCdSC452AQrGf/O89GQ54CtgEs
# bxzwGDVUcmjXFcnaJSTNedBKVXkBgawRonP1LgxH4bzzVj2eWNmzGIwO1FlhldAP
# OHAzLBEHRoSZ4pddFtaQxoabU/N1vWyICiN60It85gnF5JD4MMXyd6pS8eADIi6T
# tjfgKPoumWa0BFQ/aEzjUrfPN1r7crK+qkmLztw/ENS7zemfyx4kGRgwY1WBfFqm
# /nFlJDPQBicqeU3dOp9hj7WqD0Rc+/4VZ6wQjesIyCkv5uhUNy2LhNDi2leYtAiI
# FpmjfNk4GngLvC2Tj9IrOMv20Srym5J/Fh7yWAiPeGs3yA3QapjZTtfr7NfzpBIJ
# Q4xT/ic4WGWqhGlRlVBI5u6Ojw3ZxSZCLg3vRC4KYypkh8FdIWoKirjidEGlXsNO
# o+UP/YG5KhebiudTBxGecfJCuuUspIdRhStHAQsjv/dAqWBLlhorq2OCaP+wFhE3
# WPgnnx5pflvlujocPgsN24++ddHrl3O1FFabW8m0UkDHSKCh8QTwTkYOwu99iExB
# VWlbYZRz2qOIBjL/ozEhtCB0auKhfTLLeuNGBUaBz+oZZ+X9UAECoMhkETjb6YfN
# aI1T7vVAaiuhBoV/JCOQT+RYZrgykyPpzpmwMNFBD1vdW/29q9nkTWoEhcEOO0L9
# NzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
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
# CxMeblNoaWVsZCBUU1MgRVNOOkRDMDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDNrxRX/iz6
# ss1lBCXG8P1LFxD0e6CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S3PzTAiGA8yMDI2MDIwNDE0MDE0OVoYDzIw
# MjYwMjA1MTQwMTQ5WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDtLc/NAgEAMAcC
# AQACAg7DMAcCAQACAhNAMAoCBQDtLyFNAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEL
# BQADggEBAF9NqvthO/BPxRXl0x/A4YVflTubZi4kxlIwt6CrkyRpmkNBMoxCzGUb
# qrcdWLet4VmhivIZ6w/GKQJgNFjB7N3P9/7oealcKBZztovPRxXgD2eGz3ejoRh7
# qx36t/HsyWJDdmqrS92Fyoig768cW1fzO5umhPz6Oa+tT69fo2pBPgzs1HLDPT4r
# X4cHl0uyuHKi+zxcwAY/plgky3QvLGHAqza8trDlTM9UFVffTZLK8dwNrgoT9FPb
# JSIj0MmNr/lzhvOyJ+0i7UBPIn93ZOf2KxyHpFZlN3HEDbLSUGRNfRCgNISWLrIl
# ra5lzWeNQZ6sUWswY8vgXc5PQgciw3MxggQNMIIECQIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAgO7HlwAOGx0ygABAAACAzANBglghkgB
# ZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCAivVxqvjgojA/3K5OZteQ4th5JamxWNlIXkWrfYR/gMzCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EIEsD3RtxlvaTxFOZZnpQw0DksPmVduo5SyK9
# h9w++hMtMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIDux5cADhsdMoAAQAAAgMwIgQg/Q5Om1TNKf7HmvAD8aUlKepzDSaVPISQ8YR3
# YYhCN1AwDQYJKoZIhvcNAQELBQAEggIABAObJkZ550vsmMN2ucBAMJ04tNm9CwzI
# cQclSrSunkTO+Vk6TvLf5lpJP3rXdINQwUeOXAqhAORGJIhZt0ePSYsm9DlZevpb
# S8CjVTWovF4bfrKgyOJn2dCtPyjhUTTAXZ3NGDBpJlAtHeGDzBnilb7tk5VIvjub
# CtNnz8wlxaB8GK1i+A5/hGZzJb1dfPHQDfYZgx02h327FO2tK7P5ZssYd87jKbQI
# pPWjUJpwQ7QhhwSFyWvcK1rKjEWK/aGDnV6dC52a7uUkL8OZ1RkL9tX6sSbDkobA
# i8LwmlEMz0hHZF4wDY2j55HNwY2gWrlAAUXfRHACBODuyLo1UfZRbag3hMJTk0GD
# 0knXpZWjjWmwmJT5BARlz9Scg1zNZJ/Gdw9Jxzyj/tWOcw6ptlQiIa5tIQ2FyuYV
# aTvuIBI0/UPiL+yVp5/GjdrUoRGKyCPrS5JH4I+a4xUXHYwQ9hpvm+O92Uj32ASc
# JjXafaKkNyjmv1Xy+vKPnTY+2Y3ELE2JTEneZah50nh5pWLKFqBL+7zKI4/454K9
# kOEk7K2AJCAERmo7ju/v2iMI9Fsf4c47OBDWJ9+sakwLJ6nISm1hroRO31KGDK1D
# JUoH74lJQIxrOie7uCJ/91jB3j+jMAgj9fQluOQGCClEoXoq+Tic25zfAF5e3bNa
# Y3Ggd5YK9no=
# SIG # End signature block
