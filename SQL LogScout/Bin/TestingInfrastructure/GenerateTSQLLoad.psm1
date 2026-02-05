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
        $argument_list_never_ending = "-S" + $ServerName + " -N -C -E -Hsqllogscout_loadtest -t160 -w8000 -Q`""+ $neverending_query + "`" "
        Write-TSQLLoadLog "TSQLLoadLog : Never-ending argument list - $argument_list_never_ending"

        $sqlcmd_process_never_ending = Start-Process -FilePath $executable -ArgumentList $argument_list_never_ending -WindowStyle Hidden -PassThru -RedirectStandardError $sqlcmd_error
        Write-TSQLLoadLog "TSQLLoadLog : Started Load Script"
        Write-TSQLLoadLog "TSQLLoadLog : Process ID for Never-ending Test Load is: $sqlcmd_process_never_ending"


        # Start the process for the bigger workload
        $argument_list = "-S" + $ServerName + " -N -C -E -Hsqllogscout_loadtest -w8000 -Q`""+ $query + "`" "
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

# SIG # Begin signature block
# MIIsDAYJKoZIhvcNAQcCoIIr/TCCK/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAAAHq+Bjgk6lhP
# d2dpTyhZg+dJt8wM9TLATOSEbvqJa6CCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
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
# RtShDZbuYymynY1un+RyfiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZ5TCCGeEC
# AQEwWDBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1F
# MRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDECEzYAAAIOeZeg6f1fn9MAAgAAAg4wDQYJ
# YIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIO1WDV96KqAl
# sY7L+x9c6Z1aV0xreVqmDpmop7HSoP2yMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAXsMeJeWL8u+JPV6imrIZUtZftOFwAEvtWYxRvkeC2xv5
# rH4PCBDgF9QGaTZ76I01GkGl6qtlp10IwFH3NwD+agE7zK4lavbUrZAvTn3j/X88
# MBn/98wpG02wTXKirHVfm13+TnjbhfylM6djlgUQkaV5fm+6X3T6UXeYYBOIV3o0
# LdxeWDQvYIMa425Ry1hsi8Q4PiurRvHZv6Q6OFGxAKhbKDT2Xw+OvBaeoONr2LZz
# FL72Zba17bQPz5PmU7815QCyRPvt46khsxdNLDjzQ+3FVBNI0KLh976PivlfYtlF
# NWFVbPyoIUHYgl3pQjCHXUzkCy3eP8x29R3NUac0iKGCF60wghepBgorBgEEAYI3
# AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCBJCR/PwTpmzub5HjupXfA86CK7nUOVjL4D4NiJoSwX
# JQIGaXNm4xVNGBMyMDI2MDIwNDE2MzUyOC44OTVaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjozNjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAACE7BDNWbPr5Xo
# AAEAAAITMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgxN1oXDTI2MTExMzE4NDgxN1owgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjM2MDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA9Jl64LoZ
# xDINSFgz+9KS5Ozv5m548ePVzc9RXWe4T4/Mplfga4eq12RGdp5cVvnjde5vxfq2
# ax/jnu7vUW4rZN4mOUm5vh+kcYsQlYQ53FwgIB3nEjcQHomrG3mZe/ozjFSAr6Jb
# glKtIeAySPzAcFzyAer5lLNUHBEvQMM8BOjMyapCvh0xsg4xKFcVEJQLKEfCGBff
# MZI/amutHFb3CUTZ7aVpG2KHEFUNlZ1vwMKvxXTPRDnbwPGzyyqJJznfsLNHQ4vX
# t2ttS1PeCoGI0hN1Peq8yGsIXM9oocwC06DGNSM/4LAx2uKvwmUn6NwLc0+tmvny
# 6w28rZLejskRfnVWofEv1mWY0jHUnHrwSGBS8gVP9gcBs6P5g0OpJPMfxdUkHXRk
# cMPPW0hIP8NbW8W5Sup8HuwnSKbjpyAlGBUdM/V5rZb0sZmkn714r6ULGK+cLLAN
# 6R3FhX6N0nj64F27LTK2BbS0pJZaXjo0eDNz1QcxeIFLUgF+RBsLYDn8E8cCkexK
# 8Nlt3Gi9zJf55w6UfTZ+kwTMxMqFxh7+Tfx7+aBObZ+nx961AtiqAy7zVV69o/LW
# RdKPZdvZn9ESyGbTnPfjkBERv22prSlETlRwzP6bmEVOKWLWVwxuwh7bUWUuUb1c
# j93zvttQYGQat5E9ALLJNmlvLKCskB7raLsCAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBQTnhBKx+FryphQWMRipH49sMFAOjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# gmxaJrGqQ2D6UJhZ6Ql2SZFOaNuGbW3LzB+ES+l2BB1MJtBRSFdi/hVY33NpxsJQ
# hQ5TLVp0DXYOkIoPQc17rH+IVhemO8jCt+U6I1TIw6cR7c+tEo/Jjp6EqEU1c4/m
# raMjgHhQ+raC/OUAm98A1r4bIPHtsBmLROGmeE5XLIFaBIZWHvh2COXITKObXVd5
# wGtJ1dZZdwaHACXF506jta+uoUdyzAeuNlTPLTrZ8nyhxGwk9Vh6eiDQ7CQMWSSa
# 8DJS9PUXjeoi9vTdS7ZMXqu+tv6Qz3xtoBF5+YFK4uE+miGs90Fxm0VK2lWrmFhj
# kRl5zyoHOdwG7spNYkDomCPNWIudUQmQYKpt/Hsspfcb+xpnWIDQdMzgE8pj1vpw
# LgWEnH7LtT4dZCeoDo9PK40RxBD8kKJ769ngkEwfwCD2EX/MQk79eIvOhpnH12Gu
# VByvaKZk5XZvqtPONNwr8q/qA3877IuWwWgnaeX+prpw0dZ/QLtbGGVrgP+TRQjt
# +2dcZA5P3X4LwANhiPsy0Ol4XCdj7OxBLFvOzsCPDPaVnkp+dfDFG+NOBir7aqTJ
# 68622pymg1V+6gc/1RvxC/wgvYyG033ecJqv0On0ZRNYr+i/OkwgA3HP1aLD0aHr
# Epw6lt0263iRkCvrcdcOW8w3jC8TJuaGWyC2S9jEjzgwggdxMIIFWaADAgECAhMz
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
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCCAj4CAQEwggEBoYHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjozNjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAmBE8SCjxgjacmy8/VEdk
# 7NxpR6aggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0ttpAwIhgPMjAyNjAyMDQxMjE0MDhaGA8yMDI2MDIwNTEy
# MTQwOFowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7S22kAIBADAHAgEAAgILKDAH
# AgEAAgITcTAKAgUA7S8IEAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZ
# CgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQBW
# za4zPKGfaXqaGV1GIw9JAwD+zB5LtErMzWAgCfUPreHNpNXnwyhgtxyTGL5WAamz
# 5a9AJ8CQ6UQBydPsWKUgVcTNIN7SlLvBp7zRX5WABF21kaiTglGytSRhRvy6PmzG
# 8nojAyJ5tNRNhRgS86/qJnDa93dVp4POL/Lntc4ZhLaVXJus+HkOxRwbTKD6KXCy
# qpv/N0khQEmYWLSZ5cLUZE9IEhrz12HpcnRNKOXDPU0/taPTxuy/k8RHe9LDVgt0
# MaIEdLcAhY2BUe6JXU6xLGShCr+wMZ00sBkooInD323/bPRAuTyT4yvwB4BAV0Zh
# yTo/aDQ7NsOl8vy69LPLMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTACEzMAAAITsEM1Zs+vlegAAQAAAhMwDQYJYIZIAWUDBAIBBQCg
# ggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg
# iw9vJ+4iQr9awpOHCSkJk6f2GZN+MubX4Xr7MTaCapcwgfoGCyqGSIb3DQEJEAIv
# MYHqMIHnMIHkMIG9BCDM4QltFIUz8J4DjAzP4nVodZvQxYGleUIfp86Oa5xYaDCB
# mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACE7BDNWbP
# r5XoAAEAAAITMCIEIGicoNYrX3gkTSXuTJY28tewIg7fJsBFT+xWnyqBKaiqMA0G
# CSqGSIb3DQEBCwUABIICAAiMm8vTrBh4P97tEYHmqnGFaEsKQR4ud8U/OquBL7Us
# C8n7kMfx+4rJKrKlAeYw7Q0O7GWWe2wHNK6kbMM4Oj7sasFjtVl9YTa5+OG1fkv0
# XSx0WyUlsFEyaIrYACUDdIrjUHsbXbScGKQc7dWvMTfFbfm1xwTJ33cBRwGEwFfJ
# 7tRhO+QTej07KFvwKKy8mDysQZcd2lbwnh0YNPy0gbOV8Wx1X0jUEPMDCFDBwra5
# 1boQC9pYD9w+skOfb/Z3uE0yjqtLFX/DAC6bZt6CCOOgGc6rO0fULJY1CCtvGWIN
# b9HZqo1GQB8qo/f7Q/di6lz71JSM80Da60OoXDF1FsuzilZZHf2xjIMYAf3xV7ew
# /h3/nGuGMXcSMg7YXzlbSv48A5jJ5YFbK2IZBZuRfi6eQoFAPInLXKZp1aE5HNgK
# xSTTRGM6pegeywOSgwEqbppAp4DrIjTebaYu7g4SebHdy06kppvbOE0U51h6UXTT
# Z+CCethyiXswWNj3ScDcQn/KuF/IqbAnQupZ1UjyqUj3iEWRrlfZCd40wcs/SDRN
# c5JCiA5e+W460fdsdsELbu54XkhRqZkm9HFnvip24BXVUPVijy/orY8m8XtrWAMr
# AdQOV2lSJL68p9yoryDQwJDnDJVkAUtTo2RZ+c+6D3kH/uJKbVp0u9Qj74eC0g6F
# SIG # End signature block
