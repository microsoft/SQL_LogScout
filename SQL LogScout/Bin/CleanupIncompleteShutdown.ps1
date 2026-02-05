param
(
    [Parameter(Position=0)]
    [string] $ServerName = [String]::Empty,
    [switch] $EndActiveConsoles = $false
)
######### Globals #########

[string] $global:host_name = $env:COMPUTERNAME
[string] $global:sql_instance_conn_str = ""
[string] $global:CleanupIncompleteShutdownLog = ""
#As -WorkingDirectory is in ScheduledTask or if manually invoked we are in the right directory location, this is safe to use
[string] $global:gBinPathCleanup = (Get-Item -Path ".\" -Verbose).FullName

######### Importing required modules #########
$modules = @("CommonFunctions.psm1", "InstanceDiscovery.psm1","LoggingFacility.psm1")
# Loop through each module name and import the module
foreach ($module in $modules) 
{
    try 
    {
        $module = $global:gBinPathCleanup + "\" + $module
        Import-Module $module -ErrorAction Stop
    } 
    catch 
    {
        Write-Output "Failed to import $module"
        Start-Sleep -Seconds 4
        exit
    }
}

######### Functions #########

#This function is already defined in CommonFunctions , PS doesn't have overlay
function HandleCatchBlockCleanup ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Microsoft.PowerShell.Utility\Write-Host "Function '$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)" -ForegroundColor "Red"

    Microsoft.PowerShell.Utility\Write-Host "Exiting CleanupIncomplete Shutdown script ..."
    exit
}

function Initialize-CleanupIncompleteShutdownTaskLog
(
    [string]$LogFilePath,
    [string]$LogFileName = "##SQLLogScout_CleanupIncompleteShutdown"
)
{
<#
    .DESCRIPTION
        Initialize-CleanupIncompleteShutdownTaskLog creates the log file specific for scheduled tasks in the desired directory. 
        Logging to console is also written to the persisted file on disk.

#>    
    try
    {
        #Create log file in temp directory using full path. The temp var can come back as 8.3 format and so ensure we have the full path.
        $shortEnvTempPath = $env:TEMP
        $LogFilePath = (Get-Item $shortEnvTempPath).FullName

        #Cache LogFileName without date so we can delete old records properly
        $LogFileNameStringToDelete = $LogFileName

        #update file with date
        $LogFileName = $LogFileName + "_" + (Get-Date -Format "yyyyMMddTHHmmssffff") + ".log"
        $global:CleanupIncompleteShutdownLog = $LogFilePath + '\' + $LogFileName
        New-Item -ItemType "file" -Path $global:CleanupIncompleteShutdownLog -Force | Out-Null
        Write-Host "Created log file $global:CleanupIncompleteShutdownLog"
        Write-Host "Log initialization complete!"

        #Array to store the old files in temp directory that we then delete and use the non-date value as the string to find.
        $FilesToDelete = @(Get-ChildItem -Path ($LogFilePath) | Where-Object {$_.Name -match $LogFileNameStringToDelete} | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip 10)
        $NumFilesToDelete = $FilesToDelete.Count

        Log-CleanupIncompleteShutdownTask -Message "Found $NumFilesToDelete older SQL LogScout Scheduled Task Logs"

        # if we have files to delete
        if ($NumFilesToDelete -gt 0) 
        {
            foreach ($elem in $FilesToDelete)
            {
                $FullFileName = $elem.FullName
                Log-CleanupIncompleteShutdownTask -Message "Attempting to remove file: $FullFileName"
                Remove-Item -Path $FullFileName
            }
        }



    }
    catch
    {
		#Write-Error -Exception $_.Exception
        HandleCatchBlockCleanup -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit $true
    }
}

function Log-CleanupIncompleteShutdownTask
(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Message,
    [Parameter(Mandatory=$false, Position=1)]
    [bool]$WriteToConsole = $false,
    [Parameter(Mandatory=$false, Position=2)]
    [System.ConsoleColor]$ConsoleMsgColor = [System.ConsoleColor]::White,
    [Parameter(Mandatory=$false, Position=3)]
    [System.ConsoleColor]$ConsoleBackgroundColor = [System.ConsoleColor]::Blue
)  
{
<#
    .DESCRIPTION
        Appends messages to the persisted log and also returns output to console if flagged.

#>
    try 
    {
        #Add timestamp to message
        [string]$Message = (Get-Date -Format("yyyy-MM-dd HH:mm:ss.ms")) + ': '+ $Message

        #Log to file in $env:temp
        Add-Content -Path $global:CleanupIncompleteShutdownLog -Value $Message | Out-Null

        #if we want to write to console, we can provide that parameter and optionally a color as well.
        if ($true -eq $WriteToConsole)
        {
            if ($ConsoleMsgColor -ine $null -or $ConsoleMsgColor -ine "") 
            {
                Microsoft.PowerShell.Utility\Write-Host -Object $Message -ForegroundColor $ConsoleMsgColor
            }
            else 
            {
                #Return message to console with provided color.
                Microsoft.PowerShell.Utility\Write-Host -Object $Message
            }
        }        

    }
    catch 
    {
        ScheduledTaskHandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit $true
    }
}

function EndActiveConsoles
{
    try
    {
        $scriptName = "sql_logscout.ps1"

        # Get all PowerShell processes
        $psProcesses = Get-Process -Name "powershell*" -ErrorAction SilentlyContinue

        if ($null -eq $psProcesses)
        {
            Log-CleanupIncompleteShutdownTask "No active powershell sessions found."
            return
        }
        else 
        {
            foreach ($process in $psProcesses) 
            {

                $cimProc = (Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)")
                # Get the process owner
                $user = ($cimProc | Invoke-CimMethod -MethodName GetOwner).User
                $command = $cimProc.CommandLine

                if ($command -like "*$scriptName*" -and $command -like "*$ServerName*")
                {
                    Log-CleanupIncompleteShutdownTask "Found SQL_LogScout session to terminate: '$command'"
                    # Terminate the process
                    Stop-Process -Id ($process.Id) -Force
                    Log-CleanupIncompleteShutdownTask "Terminated process $($process.Id) running '$scriptName' for user '$user'" -WriteToConsole $true -ConsoleMsgColor "Yellow"
                }
                else 
                {
                    Log-CleanupIncompleteShutdownTask "Powershell session identified but not invoking $scriptName"
                }
            }
        }
    }
    catch
    {
        HandleCatchBlockCleanup -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}


######### Initialize Log #########
Initialize-CleanupIncompleteShutdownTaskLog

#Log all the input parameters used for the scheduled task for debugging purposes
foreach ($param in $PSCmdlet.MyInvocation.BoundParameters.GetEnumerator()) 
{
    Log-CleanupIncompleteShutdownTask "PARAMETER USED: $($param.Key): $($param.Value)"
}

######### Main Logic #########
Log-CleanupIncompleteShutdownTask "======================================================================================================================================" -WriteToConsole $true -ConsoleBackgroundColor "Blue"
Log-CleanupIncompleteShutdownTask "This script is designed to clean up SQL LogScout processes that may have been left behind if SQL LogScout was closed incorrectly" -WriteToConsole $true -ConsoleMsgColor "Yellow"
Log-CleanupIncompleteShutdownTask "======================================================================================================================================" -WriteToConsole $true -ConsoleBackgroundColor "Blue"

#print out the instance names

if ([string]::IsNullOrWhiteSpace($ServerName))
{
    Select-SQLServerForDiagnostics | Out-Null
}
else 
{
    $global:sql_instance_conn_str = $ServerName
}


$xevent_session = "xevent_SQLLogScout"
$xevent_target_file = "xevent_LogScout_target"
$xevent_alwayson_session = "SQLLogScout_AlwaysOn_Data_Movement"

try 
{
    Log-CleanupIncompleteShutdownTask "Testing connection into: '$global:sql_instance_conn_str'. If connection fails, verify instance name or running status." -WriteToConsole $true
    $ConnectionResult = Test-SQLConnection ($global:sql_instance_conn_str)

    if ($ConnectionResult -eq $false)
    {
        Log-CleanupIncompleteShutdownTask "Connection to '$global:sql_instance_conn_str' failed. Please verify the instance name and try again." -WriteToConsole $true
        exit
    }
    else 
    {
        Log-CleanupIncompleteShutdownTask "Connection to '$global:sql_instance_conn_str' successful." -WriteToConsole $true
    }
    
}
catch 
{
    HandleCatchBlockCleanup -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
}



try 
{
    #If user wants to end active consoles, we will do that first for the same connection string ServerName that was provided
    if ($EndActiveConsoles -eq $true)
    {
        EndActiveConsoles
    }

    Log-CleanupIncompleteShutdownTask "Launching cleanup routine for instance '$global:sql_instance_conn_str'... please wait" -WriteToConsole $true

    #----------------------
    Log-CleanupIncompleteShutdownTask "Executing 'WPR-cancel'. It will stop all WPR traces in case any was found running..." -WriteToConsole $true
    $executable = "cmd.exe"
    $argument_list = $argument_list = "/C wpr.exe -cancel " 
    Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
    #-----------------------------
    Log-CleanupIncompleteShutdownTask "Executing 'StorportStop'. It will stop stoport tracing if it was found to be running..." -WriteToConsole $true
    $argument_list = "/C logman stop ""storport"" -ets"
    $executable = "cmd.exe"
    Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
    #-------------------------------------

    $query = "
        declare curSession
        CURSOR for select 'kill ' + cast( session_id as varchar(max)) from sys.dm_exec_sessions where host_name = 'sqllogscout' and program_name='SQLCMD' and session_id <> @@spid
        open curSession
        declare @sql varchar(max)
        fetch next from curSession into @sql
        while @@FETCH_STATUS = 0
        begin
            exec (@sql)
            fetch next from curSession into @sql
        end
        close curSession;
        deallocate curSession;
        " 
         
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $global:sql_instance_conn_str +  " -E -Hsqllogscout_cleanup -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #stop perf Xevent
        Log-CleanupIncompleteShutdownTask "Executing 'Stop_$xevent_session' session. It will stop the SQLLogScout performance Xevent trace in case it was found to be running..." -WriteToConsole $true
        
        $query = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_session] ON SERVER; END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $global:sql_instance_conn_str + " -E -w8000 -Q`"" + $query + "`""
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
        
        $xevent_session = "xevent_SQLLogScout"
        $query = "ALTER EVENT SESSION [$xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_session] ON SERVER;" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $global:sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
    
        #stop always on data movement Xevent
        Log-CleanupIncompleteShutdownTask "Executing 'Stop_$xevent_alwayson_session'. It will stop the SQLLogScout AlwaysOn Xevent trace in case it was found to be running..." -WriteToConsole $true
        
        $query = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_alwayson_session] ON SERVER; END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $global:sql_instance_conn_str + " -E -w8000 -Q`"" + $query + "`""
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        $query = "ALTER EVENT SESSION [$xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$xevent_alwayson_session] ON SERVER;" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $global:sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #disable backup/restore trace flags
        $collector_name = "Disable_BackupRestore_Trace_Flags"
        Log-CleanupIncompleteShutdownTask "Executing '$collector_name' It will disable the trace flags they were found to be enabled..." -WriteToConsole $true
        $query = "DBCC TRACEOFF(3004,3212,3605,-1)" 
        $executable = "sqlcmd.exe"
        $argument_list ="-S" + $global:sql_instance_conn_str +  " -E -w8000 -Q`""+ $query + "`" "
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        #stop perfmon collector
        $collector_name = "PerfmonStop"
        Log-CleanupIncompleteShutdownTask "Executing '$collector_name'. It will stop Perfmon started by SQL LogScout in case it was found to be running..." -WriteToConsole $true
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon"
        $executable = "cmd.exe"
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

        # stop network traces 
        # stop logman - wait synchronously for it to finish
        $collector_name = "NetworkTraceStop"
        Log-CleanupIncompleteShutdownTask "Executing '$collector_name'. It will stop network tracing initiated by SQLLogScout in case it was found to be running..." -WriteToConsole $true
        $executable = "logman"
        $argument_list = "stop -n sqllogscoutndiscap -ets"
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait

        # stop netsh  asynchronously but wait for it to finish in a loop
        $executable = "netsh"
        $argument_list = "trace stop"
        $proc = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru

        if ($null -ne $proc)
        {

            [int]$cntr = 0

            while ($false -eq $proc.HasExited) 
            {
                if ($cntr -gt 0) {
                    Log-CleanupIncompleteShutdownTask "Shutting down network tracing may take a few minutes. Please do not close this window..." -WriteToConsole $true
                }
                [void] $proc.WaitForExit(10000)

                $cntr++
            }
        }

    Log-CleanupIncompleteShutdownTask "Cleanup script execution completed." -WriteToConsole $true

}
catch 
{
    HandleCatchBlockCleanup -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
}

finally
{
    #Cleanup the global variables. Otherwise, they will be available in the session and 
    #the next run of the script may connect to the same instance.
    Remove-Variable -Name "*" -Scope "Global" -ErrorAction SilentlyContinue
}



# SIG # Begin signature block
# MIIr5AYJKoZIhvcNAQcCoIIr1TCCK9ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDBEbUxn5ZSdGA5
# uKWw+rnZtmdA+UHy4/tJLUWGmt3QXaCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMIrJVwYuPUrS+3SAfNLZ/UJhMss+YDT
# q2P7v2X4vJaEMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# WmH8S3ApmPA3CSps/BEYij+IBU8Q+KSDRT57h0BdU3jkz30pUPfFWxqEuk10ddyL
# NnKkZrPHpqJVPDiSyFhyonUJdeu7aivdkaKc8bQArsp9JANPrPLpdoeuTOwCOd7k
# TSEJmuAKW6Qfg00gyHvGjt5rKb5gVUggce4im7DZbB3VHGFAf3SelJZN04/V4NRq
# vQAvSPniquipWtk4FPOIAEYFGBTf84I0XMSa7E150zyRLVxPJmoR65oZM06wtK3D
# GQex/8LKaSh+jPgpI/P0RdwhCi/Qfj29zV1ehGcyvIDmKLhiG4ztT/cAEhV9Rblt
# 2O1U0bieKyYBdDO4+OfLfaGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCBV73raoApMSnH5TvxyHqwi+4N0W7ixx7UFKyzS+g7ZkwIGaWj23IRVGBMyMDI2
# MDIwNDE2MzUyOS42NTlaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
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
# DQEJBDEiBCCUdOcMG6E6DQNuqOaXZDVBtO1+D68LOajh3h+vSHhCLjCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EIEsD3RtxlvaTxFOZZnpQw0DksPmVduo5SyK9
# h9w++hMtMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIDux5cADhsdMoAAQAAAgMwIgQg/Q5Om1TNKf7HmvAD8aUlKepzDSaVPISQ8YR3
# YYhCN1AwDQYJKoZIhvcNAQELBQAEggIAbRxLe68uSwpXGr7CVqjR+Ctud/4LA+VT
# VLXZD2p4t1KaHjnkWopZblSI62VvJnf7hMHp8dEz6R7tPGQj/GJQeFXdUyi1aaBN
# QuBPp68CSYSFotesVE58hTcOkQXv4vMhMEtcB7pKVltta/ee/sCyMVpoi1Dgn3j7
# z9kAS49MVAlNWK1c1L4m1xQrD0ZxqLs0sSrhdewoDa6F0pF67vZjCYpCBe9erHOg
# CNM7pDEyQbyp4NOeXWonypOSmMyF8hOcWMqA+Y3H3QEJgNQaA0KtF5j9BavRbC18
# +kXvaDVDp/rCT2VN17qYAL7rDTtIuS/deQiQHNlO1vDBpX4h6NC8IuBfW/VyYcza
# aUbftu1/LtiKDRANx4rJ5evcBSEqs9vMfCdwENKaRYzSWduOGPJbjfpcvVOmOn22
# m6OtR1OC+bR5Et0gj7lkAGRVUXSVQtUM1o9VX9UajiJS0tvLwMnfri9P2I1z8nPw
# 7PSabDZCwI0U59cSQr6Hc6ZO/n5rIgYCNKugeGAaldI2qa4qfVcbBR6/i6B/TS8a
# pBhjqXExtqBlX65oVN3LjDzSr1I5JEvgQWcozlV237mwiXnb4vppQFF1xCUQobIL
# +ya2hK4z8o0v3DHNkN/JDo6yHUCpVW/S4/7QlsMRiLn8YQz5QdxZFNQi1cUrQBCD
# ELQBkHxRlNg=
# SIG # End signature block
