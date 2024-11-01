[System.Diagnostics.Process] $global:sqlcmd_process_tsqlload
[string] $global:TSQLLoadLog
[string] $global:TSQLLoadLogPath

[string]$parentLocation =  (Get-Item (Get-Location)).Parent.FullName 
Import-Module -Name ($parentLocation + "\CommonFunctions.psm1")


function TSQLLoadHandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    #This import is needed here to prevent errors that can happen during ctrl+c
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Write-Error "Function '$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    

}



function Initialize-TSQLLoadLog
{
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LogFileName = "TSQLLoadOutput.log",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Scenario

    )

    try
    {
        $global:TSQLLoadLogPath = (Get-Item (Get-Location)).Parent.FullName + "\TestingInfrastructure\output\"+(Get-Date).ToString('yyyyMMddhhmmss') + '_'+ $Scenario +'_' 
        $global:TSQLLoadLog = $global:TSQLLoadLogPath + $LogFileName
        $LogFileExistsTest = Test-Path -Path $global:TSQLLoadLog
        if ($LogFileExistsTest -eq $False)
        {
            New-Item -Path $global:TSQLLoadLog -ItemType File -Force | Out-Null
            
        }
        else {
            Write-TSQLLoadLog "TSQLLoadLog : Starting New Capture"
        }
    }
	catch
	{
		TSQLLoadHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
	}
}


function Write-TSQLLoadLog()
{
    param 
    ( 
        [Parameter(Position=0,Mandatory=$true)]
        [Object]$Message
    )

    try
    {        
        [String]$strMessage = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $strMessage += "	: "
        $strMessage += [string]($Message)

        Add-Content -Path ($global:TSQLLoadLog) -Value $strMessage
    }
	catch
	{
		TSQLLoadHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
	}
    
}




function TSQLLoadInsertsAndSelectFunction
{
    
    param
    (
        [Parameter(Position=0)]
        [string] $ServerName = $env:COMPUTERNAME
    )

    try 
    {
        
    
        $executable = "sqlcmd.exe"
        
        $neverending_query = "SELECT COUNT_BIG(*) FROM sys.messages a, sys.messages b, sys.messages c OPTION(MAXDOP 8)"

        $query = "SET NOCOUNT ON;

        DECLARE @sql_major_version INT, 
                @sql_major_build INT, 
                @sql NVARCHAR(max), 
                @qds_sql NVARCHAR(MAX)
        
        SELECT  @sql_major_version = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT)),
                @sql_major_build = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT)) 
       
        -- create some QDS actions 

        IF (@sql_major_version >= 13)
        BEGIN
			SET @qds_sql = 'IF DB_ID(''QDS_TEST_LOGSCOUT'') IS NOT NULL DROP DATABASE QDS_TEST_LOGSCOUT'
            EXEC(@qds_sql)
			
            
            SET @qds_sql = '
            PRINT ''Creating ''''QDS_TEST_LOGSCOUT'''' database''
            CREATE DATABASE QDS_TEST_LOGSCOUT'
            EXEC(@qds_sql)
            
            SET @qds_sql = 'ALTER DATABASE QDS_TEST_LOGSCOUT
            SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE)'
            EXEC(@qds_sql)

			SET @qds_sql = 'SET NOCOUNT ON;
            USE QDS_TEST_LOGSCOUT;
            SELECT TOP 200 * INTO messagesA FROM sys.messages
            SELECT TOP 100 * INTO messagesB FROM sys.messages
            SELECT TOP 300 * INTO messagesC FROM sys.messages
            
            SELECT TOP 5 a.message_id , b.text 
            FROM messagesA a 
            JOIN messagesB b 
            ON a.message_id = b.message_id 
            AND a.language_id = b.language_id
            RIGHT JOIN messagesC c
            ON b.message_id = c.message_id 
            AND b.language_id = c.language_id
            JOIN sys.messages d
            ON c.message_id = d.message_id 
            AND c.language_id = d.language_id '
			EXEC(@qds_sql)
        END

        
        --Wait for logscout to start up for ScenarioTest
        WAITFOR DELAY '00:00:30';
        USE tempdb;
        GO
        
        IF OBJECT_ID('##TestSQLLogscoutTable') IS NOT NULL DROP TABLE ##TestSQLLogscoutTable;
        GO
        
        IF OBJECT_ID('##TestSQLLogscoutProcedure') IS NOT NULL DROP PROCEDURE ##TestSQLLogscoutProcedure;
        GO
        
        CREATE TABLE ##TestSQLLogscoutTable
        ([ID] int, [Description] nvarchar(128));
        GO
        
        INSERT INTO ##TestSQLLogscoutTable
        VALUES (0,'Test insert from SQL_LogScout Testing Infrastructure');
        GO
        
        --This proc usually takes 30 seconds
        CREATE PROCEDURE ##TestSQLLogscoutProcedure
        AS
            BEGIN
            DECLARE @cntr int
            SET @cntr = 0
            WHILE @cntr<1999
                BEGIN
                    WAITFOR DELAY '00:00:00:01'
                    SET @cntr = @cntr+1
                    INSERT INTO ##TestSQLLogscoutTable
                    VALUES ((select max(ID) FROM ##TestSQLLogscoutTable)+1, 'Test insert from SQL_LogScout Testing Infrastructure')
                END
            END
        GO
        
        --Run proc that executes 2000 times	
        EXEC ##TestSQLLogscoutProcedure
        
        
        
        --Run basic select
        SELECT [Description], count(*) [#Inserts]
        FROM ##TestSQLLogscoutTable
        GROUP BY [Description];
        GO
        
        IF OBJECT_ID('##TestSQLLogscoutTable') IS NOT NULL DROP TABLE ##TestSQLLogscoutTable;
        GO
        
        IF OBJECT_ID('##TestSQLLogscoutProcedure') IS NOT NULL DROP PROCEDURE ##TestSQLLogscoutProcedure;
        GO

        DECLARE @sql_major_version INT = (CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 4) AS INT)),
        @qds_sql NVARCHAR(MAX)
        IF (@sql_major_version >= 13)
        BEGIN
            SET @qds_sql = 'USE master;
            IF DB_ID(''QDS_TEST_LOGSCOUT'') IS NOT NULL
            BEGIN
                ALTER DATABASE QDS_TEST_LOGSCOUT SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                PRINT ''Dropping ''''QDS_TEST_LOGSCOUT'''' database''
                DROP DATABASE QDS_TEST_LOGSCOUT
            END'
            EXEC(@qds_sql)
        END
        "
    
        $sqlcmd_output = $global:TSQLLoadLogPath + "TSQLLoad_SQLCmd.out"
        $sqlcmd_error = $global:TSQLLoadLogPath + "TSQLLoad_SQLCmd.err"


        # Start the process for never ending query execution - run it for 160 seconds and timeout
        $argument_list_never_ending = "-S" + $ServerName + " -E -Hsqllogscout_loadtest -t160 -w8000 -Q`""+ $neverending_query + "`" "
        Write-TSQLLoadLog "TSQLLoadLog : Never-ending argument list - $argument_list_never_ending"

        $sqlcmd_process_never_ending = Start-Process -FilePath $executable -ArgumentList $argument_list_never_ending -WindowStyle Hidden -PassThru -RedirectStandardError $sqlcmd_error
        Write-TSQLLoadLog "TSQLLoadLog : Started Load Script"
        Write-TSQLLoadLog "TSQLLoadLog : Process ID for Never-ending Test Load is: $sqlcmd_process_never_ending"


        # Start the process for the bigger workload
        $argument_list = "-S" + $ServerName + " -E -Hsqllogscout_loadtest -w8000 -Q`""+ $query + "`" "
        Write-TSQLLoadLog "TSQLLoadLog : Argument List - $argument_list"
    
        
        $sqlcmd_process_tsqlload = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru -RedirectStandardOutput $sqlcmd_output
        $global:sqlcmd_process_tsqlload = $sqlcmd_process_tsqlload.Id
                
        Write-TSQLLoadLog "TSQLLoadLog : Process ID for Test Load is: $global:sqlcmd_process_tsqlload"

    }
    
    catch 
    {
        TSQLLoadHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}





function TSQLLoadCheckWorkloadExited ()
{
    try 
    {
        while ($false -eq $global:sqlcmd_process_tsqlload.HasExited) 
        ##Logically we should never enter this code as this tsql load should have completed before logscout finished. If we are hung for some reason, we need to terminate the process.
        {
            Stop-Process $global:sqlcmd_process_tsqlload
            Write-TSQLLoadLog "TSQLLoadLog : TSQL Load Terminated Due to Long Duration"
        }
        Write-TSQLLoadLog "TSQLLoadLog : Process exited as expected" 
    }

    catch 
    {
        TSQLLoadHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}
