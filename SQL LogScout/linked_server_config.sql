
SET NOCOUNT ON
GO
PRINT '---------------------------------------'
PRINT '---- linked_server_config.sql'
PRINT '----   $Revision: 2 $'
PRINT '----   $Date: 2022/08/01  $'
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

