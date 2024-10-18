
    function linked_server_config_Query([Boolean] $returnVariable = $false)
    {
        Write-LogDebug "Inside" $MyInvocation.MyCommand

        [String] $collectorName = "linked_server_config"
        [String] $fileName = $global:internal_output_folder + $collectorName + ".sql"

        $content =  "
SET NOCOUNT ON
GO
PRINT '---------------------------------------'
PRINT '---- linked_server_config.sql'
PRINT '----   `$Revision: 2 `$'
PRINT '----   `$Date: 2022/08/01  `$'
PRINT '---------------------------------------'
PRINT ''
PRINT 'Start Time: ' + CONVERT (varchar(30), GETDATE(), 121)
GO
PRINT ''
SELECT @@VERSION as SQLVersion
GO
PRINT ''
SELECT @@SERVERNAME as 'SQL Server Name'
GO
PRINT ''
SELECT HOST_NAME() as 'Host (client) machine name'
GO
PRINT ''
PRINT '--- Active Trace Flags'
DBCC TRACESTATUS(-1)
PRINT ''
GO
PRINT '-- sp_helpsort --'
EXEC sp_helpsort
PRINT ''
GO

PRINT '-- SQL_commandline_args --'
SELECT convert(varchar(16), value_name) value_name, convert(varchar(200), value_data) value_data FROM sys.dm_server_registry 
WHERE value_name LIKE 'SQLArg%'
PRINT ''


PRINT '-- sp_helpserver --'
EXEC master..sp_helpserver
PRINT ''
GO

PRINT '-- sp_helplinkedservers --'
EXEC master..sp_linkedservers
PRINT ''

PRINT '-- sp_helplinkedsrvlogin --'
EXEC master..sp_helplinkedsrvlogin
PRINT ''

PRINT '--  sp_enum_oledb_providers --'
EXEC master..sp_enum_oledb_providers
PRINT ''

SELECT GETDATE() as EndCollection
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

    
