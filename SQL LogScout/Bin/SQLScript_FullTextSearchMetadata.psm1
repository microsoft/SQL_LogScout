
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
						  INSERT INTO #tbl_FullText_Catalog_Info_PropertieS
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
	EXEC SP_EXECUTESQL @sql
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

	EXEC SP_EXECUTESQL @sql
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

	EXEC SP_EXECUTESQL @sql
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

	EXEC SP_EXECUTESQL @sql
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

	EXEC SP_EXECUTESQL @sql
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
	EXEC SP_EXECUTESQL @sql
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

    
