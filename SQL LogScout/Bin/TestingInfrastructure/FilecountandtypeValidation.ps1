param
(
    [Parameter(Position=0)]
    [string]    $SummaryOutputFile,

    [Parameter(Position=1)]
    [switch]    $DebugOn

)

$DebugOn = $false

<#
1 - This module validates if all the expected log files are generated for the given scenario.
2 - In the case of expected files not being found in the output folder, a message is displayed with the missing file name in red for each scenario.
3 - An array is maintained for each scenario with the list of expected files. If a new log file is collected for a scenario, the corresponding array needs to be updated to include that file in the array.
4 - Execution of the scenario is obtained from ##SQLLOGSCOUT.LOG  by scanning for this text pattern "Scenario Console input:" , so if any changes are made to the  ##SQLLOGSCOUT.LOG file, the logic here needs to be updated here as well.
5 - This module works for validating a single scenario or  multiple scenarios
#>

Import-Module -Name ..\CommonFunctions.psm1
Import-Module -Name ..\LoggingFacility.psm1

# Declaration of global variables
$global:sqllogscout_log = "##SQLLOGSCOUT.LOG"
$global:sqllogscoutdebug_log = "##SQLLOGSCOUT_DEBUG.LOG"
$global:filter_pattern = @("*.txt", "*.out", "*.csv", "*.xel", "*.blg", "*.sqlplan", "*.trc", "*.LOG","*.etl","*.NGENPDB","*.mdmp", "*.pml")
$global:sqllogscout_latest_output_folder = ""
$global:sqllogscout_root_directory = Convert-Path -Path ".\..\..\"   #this goes to the SQL LogScout root directory
$global:sqllogscout_latest_internal_folder = ""
$global:sqllogscout_testing_infrastructure_output_folder = ""
$global:sqllogscout_latest_output_internal_logpath = ""
$global:sqllogscout_latest_output_internal_debuglogpath = ""
$global:DetailFile = ""

[System.Collections.ArrayList]$global:BasicFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:GeneralPerfFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:DetailedPerfFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:ReplicationFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:AlwaysOnFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:NetworkTraceFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:MemoryFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:DumpMemoryFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:WPRFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:SetupFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:BackupRestoreFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:IOFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:LightPerfFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:ProcessMonitorFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:ServiceBrokerDbMailFiles = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList]$global:NeverEndingQueryFiles = New-Object -TypeName System.Collections.ArrayList


function CopyArray([System.Collections.ArrayList]$Source, [System.Collections.ArrayList]$Destination)
{
    foreach ($file in $Source)
    {
        [void]$Destination.Add($file)
    }
}



#Function for inclusions and exclusions to search the logs (debug and regular) for a string and add to array if found as we expect the file to be written.
function ModifyArray()
{
    param
        (
            [Parameter(Position=0, Mandatory=$true)]
            [string] $ActionType,

            [Parameter(Position=1, Mandatory=$true)]
            [string] $TextToFind,

            [Parameter(Position=2, Mandatory=$false)]
            [System.Collections.ArrayList] $ArrayToEdit,

            [Parameter(Position=3, Mandatory=$false)]
            [string] $ReferencedLog
        )

        #Check the default log first as there less records than debug log.
        #If we didn't find in default log, then check debug log for the provided string.
        [Boolean] $fTextFound = (Select-String -Path $global:sqllogscout_latest_output_internal_logpath -Pattern $TextToFind) -OR
        (Select-String -Path $global:sqllogscout_latest_output_internal_debuglogpath -Pattern $TextToFind)

        #we check for $null ArrayEdit since it is mandatory

        if ($null -eq $ArrayToEdit) 
        {
            WriteToConsoleAndFile -Message "ArrayToEdit should not be null"
            return
        }
    if ($fTextFound) 
    {
        if ($ActionType -eq 'Add')
        {
            [void]$ArrayToEdit.Add($ReferencedLog)
            WriteToConsoleAndFile -Message "Adding value '$ReferencedLog' to array"

        }

        elseif ($ActionType -eq 'Remove')
        {

            [void]$ArrayToEdit.Remove($ReferencedLog)
            WriteToConsoleAndFile -Message "Removing value '$ReferencedLog' from array"

        } elseif ($ActionType -eq "Clear")
        {
            [void]$ArrayToEdit.Clear()
            WriteToConsoleAndFile -Message "Removing all values from array"
        } 

        #We didn't find the provided text so don't add to array. We don't expect the file.
        else
        {
            WriteToConsoleAndFile -Message "Improper use of ModifyArray(). Value passed: $ActionType" -ForegroundColor Red
        }
    }
    
}

function BuildBasicFileArray([bool]$IsNoBasic)
{
    $global:BasicFiles =
	@(
		'ERRORLOG',
		'SQLAGENT',
		'system_health',
		'RunningDrivers.csv',
		'RunningDrivers.txt',
		'SystemInfo_Summary.out',
		'MiscDiagInfo.out',
		'TaskListServices.out',
		'TaskListVerbose.out',
		'PowerPlan.out',
		'WindowsHotfixes.out',
        'WindowsDiskInfo.out',
		'FLTMC_Filters.out',
		'FLTMC_Instances.out',
		'EventLog_Application.csv',
		'EventLog_System.csv',
        'EventLog_System.out',
        'EventLog_Application.out',
		'UserRights.out',	
		'Fsutil_SectorInfo.out',
        'Perfmon.out',
        'DNSClientInfo.out',
        'IPConfig.out',
        'NetTCPandUDPConnections.out',
        'SQL_AzureVM_Information.out',
        'Environment_Variables.out',
        'azcmagent-logs',
        'AllMemoryDumps_List.out',
        'exception.log',
        'SQLDUMPER_ERRORLOG.log',
        'DotNetVersions.out'
	)

	# inclusions and exclusions to the array
    ModifyArray -ActionType "Add" -TextToFind "Getting MSSQLSERVER_SQLDIAG*.xel files"  -ArrayToEdit $global:BasicFiles -ReferencedLog "_SQLDIAG"
    ModifyArray -ActionType "Remove" -TextToFind "Azcmagent not found" -ArrayToEdit $global:BasicFiles -ReferencedLog "azcmagent-logs"
    ModifyArray -ActionType "Remove" -TextToFind "Will not collect SQLAssessmentAPI" -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLAssessmentAPI"
    ModifyArray -ActionType "Remove" -TextToFind "No SQLAgent log files found" -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLAGENT"
    ModifyArray -ActionType "Remove" -TextToFind "SQL_AzureVM_Information will not be collected" -ArrayToEdit $global:BasicFiles -ReferencedLog "SQL_AzureVM_Information.out"
    ModifyArray -ActionType "Add" -TextToFind "memory dumps \(max count limit of 20\), from the past 2 months, of size < 100 MB"  -ArrayToEdit $global:BasicFiles -ReferencedLog "PATTERN:.*\.(mdmp|dmp)$"
    ModifyArray -ActionType "Add" -TextToFind "memory dumps \(max count limit of 20\), from the past 2 months, of size < 100 MB"  -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLDUMPER_ERRORLOG.log"
    ModifyArray -ActionType "Add" -TextToFind "HADR /AG is enabled on this system" -ArrayToEdit $global:BasicFiles -ReferencedLog "AlwaysOnDiagScript.out"
    ModifyArray -ActionType "Add" -TextToFind "Found AlwaysOn_health files" -ArrayToEdit $global:BasicFiles -ReferencedLog "AlwaysOn_health"
    ModifyArray -ActionType "Add" -TextToFind "This is a Windows Cluster for sure!"  -ArrayToEdit $global:BasicFiles -ReferencedLog "cluster.log"
    ModifyArray -ActionType "Add" -TextToFind "This is a Windows Cluster for sure!"  -ArrayToEdit $global:BasicFiles -ReferencedLog "ClusterInfo.out"
    ModifyArray -ActionType "Add" -TextToFind "This is a Windows Cluster for sure!"  -ArrayToEdit $global:BasicFiles -ReferencedLog "ClusterRegistryHive.out"
    ModifyArray -ActionType "Add" -TextToFind "Full-Text FD\* log files." -ArrayToEdit $global:BasicFiles -ReferencedLog "FDLAUNCHERRORLOG"
    ModifyArray -ActionType "Add" -TextToFind "Full-Text FD\* log files." -ArrayToEdit $global:BasicFiles -ReferencedLog "_FD"
    ModifyArray -ActionType "Add" -TextToFind "Full-Text SQLFT\* log files." -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLFT"
    ModifyArray -ActionType "Add" -TextToFind "Collecting FullTextSearch Metadata output" -ArrayToEdit $global:BasicFiles -ReferencedLog "FullTextSearchMetadata.out"
    ModifyArray -ActionType "Remove" -TextToFind "Not capturing exception.log. File not found in the" -ArrayToEdit $global:BasicFiles -ReferencedLog "exception.log"
    ModifyArray -ActionType "Remove" -TextToFind "Not capturing SQL Dumper Error Log. File not found in the" -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLDUMPER_ERRORLOG.log"
    ModifyArray -ActionType "Remove" -TextToFind "Skipping Cluster Log collection as 'NoClusterLogs' option is enabled."  -ArrayToEdit $global:BasicFiles -ReferencedLog "cluster.log"
    ModifyArray -ActionType "Add" -TextToFind "Default trace files found" -ArrayToEdit $global:BasicFiles -ReferencedLog "PATTERN:log_\d+\.trc"
    
    

    #calculate count of expected files
    $ExpectedFiles = $global:BasicFiles
    return $ExpectedFiles

}

function BuildGeneralPerfFileArray([bool]$IsNoBasic)
{
    $global:GeneralPerfFiles =
	@(
        'Perfmon.out',
        'xevent_LogScout_target',
        'ExistingProfilerXeventTraces.out',
        'HighCPU_perfstats.out',
        'PerfStats.out',
        'PerfStatsSnapshotStartup.out',
        'QueryStore.out',
        'TempDB_and_Tran_Analysis.out',
        'linked_server_config.out',
        'PerfStatsSnapshotShutdown.out',
        'Top_CPU_QueryPlansXml_Shutdown_'
	)

    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:GeneralPerfFiles
    }

	# inclusions and exclusions to the array

    ModifyArray -ActionType "Add" -TextToFind "AdditionalOptionsEnabled contains 'RedoTasksPerfStats', calling RedoQueue_PerfStats_Query collector" -ArrayToEdit $global:GeneralPerfFiles -ReferencedLog "RedoTasks_PerfStats"
    
    #calculate count of expected files
    $ExpectedFiles = $global:GeneralPerfFiles
    return $ExpectedFiles

}

function BuildDetailedPerfFileArray([bool]$IsNoBasic)
{

    $global:DetailedPerfFiles =
	@(
        'Perfmon.out',
        'xevent_LogScout_target',
        'ExistingProfilerXeventTraces.out',
        'HighCPU_perfstats.out',
        'PerfStats.out',
        'PerfStatsSnapshotStartup.out',
        'QueryStore.out',
        'TempDB_and_Tran_Analysis.out',
        'linked_server_config.out',
        'PerfStatsSnapshotShutdown.out',
        'Top_CPU_QueryPlansXml_Shutdown_'
     )

    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:DetailedPerfFiles
    }

	# inclusions and exclusions to the array

    ModifyArray -ActionType "Add" -TextToFind "AdditionalOptionsEnabled contains 'RedoTasksPerfStats', calling RedoQueue_PerfStats_Query collector" -ArrayToEdit $global:DetailedPerfFiles -ReferencedLog "RedoTasks_PerfStats"

    #calculate count of expected files
    $ExpectedFiles = $global:DetailedPerfFiles
    return $ExpectedFiles
}


function BuildReplicationFileArray([bool]$IsNoBasic)
{

    $global:ReplicationFiles =
	@(
        'ChangeDataCaptureStartup.out',
        'Change_TrackingStartup.out',
        'ChangeDataCaptureShutdown.out',
        'Change_TrackingShutdown.out'
     )

    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:ReplicationFiles
    }

	# inclusions and exclusions to the array
    ModifyArray -ActionType "Add" -TextToFind "Collecting Replication Metadata"  -ArrayToEdit $global:ReplicationFiles -ReferencedLog "Repl_Metadata_CollectorShutdown"

    #calculate count of expected files
    $ExpectedFiles = $global:ReplicationFiles
    return $ExpectedFiles

}

function BuildAlwaysOnFileArray([bool]$IsNoBasic)
{

    $global:AlwaysOnFiles =
	@(
        'AlwaysOnDiagScript.out',
        'AlwaysOn_Data_Movement_target',
        'xevent_LogScout_target',
        'Perfmon.out',
        'cluster.log',
        'ClusterInfo.out',
        'ClusterRegistryHive.out'
        'GetAGTopology.xml'
     )

    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:AlwaysOnFiles
	}

    # inclusions and exclusions to the array
    ModifyArray -ActionType "Remove" -TextToFind "AlwaysOn_Data_Movement Xevents is not supported on SQL Server version"  -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "AlwaysOn_Data_Movement_target"
    ModifyArray -ActionType "Remove" -TextToFind "This is Not a Windows Cluster!"  -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "cluster.log"
    ModifyArray -ActionType "Remove" -TextToFind "This is Not a Windows Cluster!"  -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "ClusterRegistryHive.out"
    ModifyArray -ActionType "Remove" -TextToFind "This is Not a Windows Cluster!"  -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "ClusterInfo.out"
    ModifyArray -ActionType "Remove" -TextToFind "HADR is off, skipping data movement and AG Topology" -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "GetAGTopology.xml"
    ModifyArray -ActionType "Remove" -TextToFind "HADR is off, skipping data movement and AG Topology" -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "AlwaysOn_Data_Movement_target"
    ModifyArray -ActionType "Remove" -TextToFind "HADR is off, skipping data movement and AG Topology" -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "xevent_LogScout_target"
    ModifyArray -ActionType "Add" -TextToFind "Found AlwaysOn_health files" -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "AlwaysOn_health"
    ModifyArray -ActionType "Remove" -TextToFind "Skipping Cluster Log collection as 'NoClusterLogs' option is enabled."  -ArrayToEdit $global:AlwaysOnFiles -ReferencedLog "cluster.log"
    
    #calculate count of expected files
    $ExpectedFiles = $global:AlwaysOnFiles
    return $ExpectedFiles
}


function BuildNetworkTraceFileArray([bool]$IsNoBasic)
{

    $global:NetworkTraceFiles =
	@(
        'delete.me',
        'NetworkTrace_LogmanStart1.etl'
     )

    #network trace does not collect basic scenario logs with it

    # inclusions and exclusions to the array
    #...

    #calculate count of expected files
    $ExpectedFiles = $global:NetworkTraceFiles
    return $ExpectedFiles
}


function BuildMemoryFileArray([bool]$IsNoBasic)
{

    $global:MemoryFiles =
	@(
        'SQL_Server_Mem_Stats.out',
        'Perfmon.out'
    )

    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:MemoryFiles
	}

    # inclusions and exclusions to the array
    #...

    #calculate count of expected files
    $ExpectedFiles = $global:MemoryFiles
    return $ExpectedFiles
}


function BuildDumpMemoryFileArray([bool]$IsNoBasic)
{

    $global:DumpMemoryFiles =
	@(
        'SQLDump',
        'SQLDUMPER_ERRORLOG.log'
    )

    #dumpmemory does not collect basic scenario logs with it

    # inclusions and exclusions to the array

    ModifyArray -ActionType "Remove" -TextToFind "No memory dumps generated. SQLDumper.exe didn't run. Exiting..." -ArrayToEdit $global:DumpMemoryFiles -ReferencedLog "SQLDump"
    ModifyArray -ActionType "Remove" -TextToFind "No memory dumps generated. SQLDumper.exe didn't run. Exiting..." -ArrayToEdit $global:DumpMemoryFiles -ReferencedLog "SQLDUMPER_ERRORLOG.log"
    

    #calculate count of expected files
    $ExpectedFiles = $global:DumpMemoryFiles
    return $ExpectedFiles
}

function BuildWPRFileArray([bool]$IsNoBasic)
{

    $global:WPRFiles = 	@()

    #WPR does not collect basic scenario logs with it

    # inclusions and exclusions to the array
    #...

    #cpu scenario
    $WPRCollected = Select-String -Path $global:sqllogscout_latest_output_internal_logpath -Pattern "WPR_CPU_Stop"

    if ([string]::IsNullOrEmpty($WPRCollected) -eq $false)
    {
        [void]$global:WPRFiles.Add("WPR_CPU_Stop.etl")
    }

    #heap and virtual memory
    $WPRCollected = Select-String -Path $global:sqllogscout_latest_output_internal_logpath -Pattern "WPR_HeapAndVirtualMemory_Stop "

    if ([string]::IsNullOrEmpty($WPRCollected) -eq $false)
    {
        [void]$global:WPRFiles.Add("WPR_HeapAndVirtualMemory_Stop.etl")
    }

    #disk and file I/O
    $WPRCollected = Select-String -Path $global:sqllogscout_latest_output_internal_logpath -Pattern "WPR_DiskIO_FileIO_Stop"

    if ([string]::IsNullOrEmpty($WPRCollected) -eq $false)
    {
        [void]$global:WPRFiles.Add("WPR_DiskIO_FileIO_Stop.etl")
    }

    #filter drivers scenario
    $WPRCollected = Select-String -Path $global:sqllogscout_latest_output_internal_logpath -Pattern "WPR_MiniFilters_Stop"

    if ([string]::IsNullOrEmpty($WPRCollected) -eq $false)
    {
        [void]$global:WPRFiles.Add("WPR_MiniFilters_Stop.etl")
    }


    #calculate count of expected files
    $ExpectedFiles = $global:WPRFiles
    return $ExpectedFiles
}

function BuildSetupFileArray([bool]$IsNoBasic)
{

    $global:SetupFiles =
	@(
        'Setup_Bootstrap',
        '_HKLM_CurVer_Uninstall.txt',
        '_HKLM_MicrosoftSQLServer.txt',
        '_MissingMsiMsp_Detailed.txt',
        '_MissingMsiMsp_Summary.txt',
        '_InstalledPrograms.out'
    )

    #inclusions and exclusions to the array
    ModifyArray -ActionType "Add" -TextToFind "Copying the unattended SQL Setup log file"  -ArrayToEdit $global:SetupFiles -ReferencedLog "UnattendedInstall_SqlSetup"

    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:SetupFiles
	}


    # inclusions and exclusions to the array
    #...

    #calculate count of expected files
    $ExpectedFiles = $global:SetupFiles
    return $ExpectedFiles
}

function BuildBackupRestoreFileArray([bool]$IsNoBasic)
{

    $global:BackupRestoreFiles =
	@(
        'xevent_LogScout_target',
        'Perfmon.out_000001.blg',
        'VSSAdmin_Providers.out',
        'VSSAdmin_Shadows.out',
        'VSSAdmin_Shadowstorage.out',
        'VSSAdmin_Writers.out',
        'SqlWriterLogger.txt'
    )

    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:BackupRestoreFiles
	}

    # inclusions and exclusions to the array
    ModifyArray -ActionType "Remove" -TextToFind "Not collecting SQL VSS log"  -ArrayToEdit $global:BackupRestoreFiles -ReferencedLog "SqlWriterLogger.txt"
    ModifyArray -ActionType "Remove" -TextToFind "Backup_restore_progress_trace XEvent exists in SQL Server 2016 and higher and cannot be collected for instance"  -ArrayToEdit $global:BackupRestoreFiles -ReferencedLog "xevent_LogScout_target"

    #calculate count of expected files
    $ExpectedFiles = $global:BackupRestoreFiles
    return $ExpectedFiles
}

function BuildIOFileArray([bool]$IsNoBasic)
{

    $global:IOFiles =
	@(
        'StorPort.etl',
        'High_IO_Perfstats.out',
        'Perfmon.out'
    )


    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:IOFiles
	}


    # inclusions and exclusions to the array
    #...

    #calculate count of expected files
    $ExpectedFiles = $global:IOFiles
    return $ExpectedFiles
}

function BuildLightPerfFileArray([bool]$IsNoBasic)
{
    $global:LightPerfFiles =
	@(
        'Perfmon.out',
        'ExistingProfilerXeventTraces.out',
        'HighCPU_perfstats.out',
        'PerfStats.out',
        'PerfStatsSnapshotStartup.out',
        'QueryStore.out',
        'TempDB_and_Tran_Analysis.out',
        'linked_server_config.out',
        'PerfStatsSnapshotShutdown.out',
        'Top_CPU_QueryPlansXml_Shutdown_'
    )

    if ($IsNoBasic -ne $true)
    {
        #add the basic array files
        CopyArray -Source $global:BasicFiles -Destination $global:LightPerfFiles
	}

    # inclusions and exclusions to the array
    
    ModifyArray -ActionType "Add" -TextToFind "AdditionalOptionsEnabled contains 'RedoTasksPerfStats', calling RedoQueue_PerfStats_Query collector" -ArrayToEdit $global:LightPerfFiles -ReferencedLog "RedoTasks_PerfStats"

    #calculate count of expected files
    $ExpectedFiles = $global:LightPerfFiles
    return $ExpectedFiles
}
function BuildProcessMonitorFileArray([bool]$IsNoBasic)
{

    $global:ProcessMonitorFiles =
	@(
        'ProcessMonitor.pml'
     )


    #ProcessMonitor does not collect basic scenario logs with it


    # inclusions and exclusions to the array
    #...

    #calculate count of expected files
    $ExpectedFiles = $global:ProcessMonitorFiles
    return $ExpectedFiles
}

function BuildNeverEndingQueryFileArray([bool]$IsNoBasic)
{
    $global:NeverEndingQueryFiles =
    @(
        'NeverEndingQuery_perfstats.out',
        'NeverEnding_HighCPU_QueryPlansXml_',
        'NeverEnding_statistics_QueryPlansXml_'
    )

    if ($true -ne $IsNoBasic) 
        {
            #add the basic array files
            CopyArray -Source $global:BasicFiles -Destination $global:NeverEndingQueryFiles
        }
    ModifyArray -ActionType "Clear" -TextToFind "NeverEndingQuery Exit without collection" -ArrayToEdit $global:NeverEndingQueryFiles 

    return $global:NeverEndingQueryFiles
}
function BuildServiceBrokerDbMailFileArray([bool]$IsNoBasic)
{

    $global:ServiceBrokerDbMailFiles =
	@(
        'Perfmon.out',
        'SSB_DbMail_Diag.out',
        'xevent_LogScout_target'
     )

    #network trace does not collect basic scenario logs with it

    # inclusions and exclusions to the array
    #...

    #calculate count of expected files
    $ExpectedFiles = $global:ServiceBrokerDbMailFiles
    return $ExpectedFiles
}

function WriteToSummaryFile ([string]$SummaryOutputString)
{
    if ([string]::IsNullOrWhiteSpace($SummaryOutputFile) -ne $true)
    {
        Write-Output $SummaryOutputString |Out-File $SummaryOutputFile -Append
    }

}

function WriteToConsoleAndFile ([string]$Message, [string]$ForegroundColor = "")
{
    if ($ForegroundColor -ne "")
    {
        Write-Host $Message -ForegroundColor $ForegroundColor
    }
    else
    {
        Write-Host $Message
    }

    if ($true -eq (Test-Path $global:DetailFile))
    {
        Write-Output $Message | Out-File -FilePath $global:DetailFile -Append
    }
}

function DiscoverScenarios ([string]$SqlLogscoutLog)
{
    #find the line in the log file that says "The scenarios selected are: 'GeneralPerf Basic' " It contains the scenarios being executed
    #then strip out just the scenario names and use those to find if all the files for them are present

    [String] $ScenSelStr = (Select-String -Path $SqlLogscoutLog -Pattern "The scenarios selected are:" |Select-Object -First 1 Line).Line

    if ($DebugOn)
    {
        Write-Host "ScenSelStr: $ScenSelStr"
    }


    # this section parses out the scenario names from the string extracted from the log
    # NoBasic may also be there and will be used later

    $colon_position = $ScenSelStr.LastIndexOf(":")
    $colon_position = $colon_position + 1
    $ScenSelStr = ($ScenSelStr.Substring($colon_position).TrimEnd()).TrimStart()
    $ScenSelStr = $ScenSelStr.Replace('''','')
    $ScenSelStr = $ScenSelStr.Replace(' ','+')

    #popluate an array with the scenarios
    [string[]]$scenStrArray = $ScenSelStr.Split('+')

    #remove any blank elements in the array
    $scenStrArray = $scenStrArray.Where({ "" -ne $_ })


    return $scenStrArray

}


function CreateTestResultsFile ([string[]]$ScenarioArray)
{

    $fileScenString =""

    foreach($scenario in $ScenarioArray)
    {
        switch ($scenario)
        {
            "NoBasic"       {$fileScenString +="NoB"}
            "Basic"         {$fileScenString +="Bas"}
            "GeneralPerf"   {$fileScenString +="GPf"}
            "DetailedPerf"  {$fileScenString +="DPf"}
            "Replication"   {$fileScenString +="Rep"}
            "AlwaysOn"      {$fileScenString +="AO"}
            "NetworkTrace"  {$fileScenString +="Net"}
            "Memory"        {$fileScenString +="Mem"}
            "DumpMemory"    {$fileScenString +="Dmp"}
            "WPR"           {$fileScenString +="Wpr"}
            "Setup"         {$fileScenString +="Set"}
            "BackupRestore" {$fileScenString +="Bkp"}
            "IO"            {$fileScenString +="IO"}
            "LightPerf"     {$fileScenString +="LPf"}
            "ProcessMonitor"{$fileScenString +="PrM"}
            "ServiceBrokerDBMail"{$fileScenString +="Ssb"}
            "NeverEndingQuery" {$fileScenString +="NEQ"}
        }

        $fileScenString +="_"

    }

    # create the file validation log
    if (!(Test-Path -Path $global:sqllogscout_testing_infrastructure_output_folder))
    {
        Write-Host "Folder '$global:sqllogscout_testing_infrastructure_output_folder' does not exist. Cannot create text output file"
    }
    else
    {
        $FileName = "FileValidation_" + $fileScenString + (Get-Date -Format "MMddyyyyHHmmss").ToString() + ".txt"
        $global:DetailFile = $global:sqllogscout_testing_infrastructure_output_folder + "\" + $FileName

        Write-Host "Creating file validation log in folder '$global:DetailFile'"
        New-Item -ItemType File -Path  $global:sqllogscout_testing_infrastructure_output_folder -Name $FileName | Out-Null
    }

}

function Set-TestInfraOutputFolder()
{
    $present_directory = Convert-Path -Path "."   #this gets the current directory called \TestingInfrastructure

	#create the testing infrastructure output folder
    $folder = New-Item -Path $present_directory -Name "Output" -ItemType Directory -Force
    $global:sqllogscout_testing_infrastructure_output_folder = $folder.FullName

    #create the LogFileMissing.log if output and/or internal folders/files are missing
    $PathToFileMissingLogFile =  $global:sqllogscout_testing_infrastructure_output_folder + '\LogScoutFolderOrFileMissing.LOG'

    # get the latest output folder that contains SQL LogScout logs
    $latest = Get-ChildItem -Path $global:sqllogscout_root_directory -Filter "output*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    
    #if no output folder is found, then we cannot continue
    if ([String]::IsNullOrWhiteSpace($latest))
    {
        Write-Host "No 'output*' folder(s) found'. Cannot continue" -ForegroundColor Red
        Write-Output "No 'output*' folder(s) found'. Cannot continue"  | Out-File -FilePath $PathToFileMissingLogFile -Append
        return $false
    }

    #set the path to the latest output folder
    $global:sqllogscout_latest_output_folder = ($global:sqllogscout_root_directory + "\"+ $latest + "\")

    #check if the \output folder exists
    if (!(Test-Path -Path $global:sqllogscout_latest_output_folder ))
    {
        $OutputFolderCheckLogMessage = "Folder '" + $global:sqllogscout_latest_output_folder + "' does not exist"
        $OutputFolderCheckLogMessage = $OutputFolderCheckLogMessage.replace("`n", " ")

        Write-Host $OutputFolderCheckLogMessage -ForegroundColor Red
        Write-Output $OutputFolderCheckLogMessage  | Out-File -FilePath $PathToFileMissingLogFile -Append

        return $false
    }

    #check if the \internal folder exists
    $global:sqllogscout_latest_internal_folder = ($global:sqllogscout_latest_output_folder + "internal\")

    if (!(Test-Path -Path $global:sqllogscout_latest_internal_folder ))
    {
        $OutputInternalFolderCheckLogMessage = "Folder '" + $global:sqllogscout_latest_internal_folder + "' does not exist"
        $OutputInternalFolderCheckLogMessage = $OutputInternalFolderCheckLogMessage.replace("`n", " ")

        Write-Host $OutputInternalFolderCheckLogMessage -ForegroundColor Red
        Write-Output $OutputInternalFolderCheckLogMessage | Out-File -FilePath $PathToFileMissingLogFile -Append

        return $false
    }

    #get the path to the latest SQL LogScout log and debug log files
	$global:sqllogscout_latest_output_internal_logpath = ($global:sqllogscout_latest_internal_folder + $global:sqllogscout_log)
    $global:sqllogscout_latest_output_internal_debuglogpath = ($global:sqllogscout_latest_internal_folder + $global:sqllogscoutdebug_log)

    return $true
}

#--------------------------------------------------------Scenario check Start ------------------------------------------------------------

function FileCountAndFileTypeValidation([string]$scenario_string, [bool]$IsNoBasic)
{
    $summary_out_string = ""
    $return_val = $true

    try
    {

        $msg = ''

        #build the array of expected files for the respective scenario
        switch ($scenario_string)
        {
            "Basic"
            {
                $ExpectedFiles = BuildBasicFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:BasicFiles.Count
            }
            "GeneralPerf"
            {
                $ExpectedFiles = BuildGeneralPerfFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:GeneralPerfFiles.Count
            }
            "DetailedPerf"
            {
                $ExpectedFiles = BuildDetailedPerfFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:DetailedPerfFiles.Count
            }
            "Replication"
            {
                $ExpectedFiles = BuildReplicationFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:ReplicationFiles.Count
            }
            "AlwaysOn"
            {
                $ExpectedFiles = BuildAlwaysOnFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:AlwaysOnFiles.Count
            }
            "NetworkTrace"
            {
                $ExpectedFiles = BuildNetworkTraceFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:NetworkTraceFiles.Count
            }
            "Memory"
            {
                $ExpectedFiles = BuildMemoryFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:MemoryFiles.Count
            }
            "DumpMemory"
            {
                $ExpectedFiles = BuildDumpMemoryFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:DumpMemoryFiles.Count
            }
            "WPR"
            {
                $ExpectedFiles = BuildWPRFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:WPRFiles.Count
            }
            "Setup"
            {
                $ExpectedFiles = BuildSetupFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:SetupFiles.Count
            }
            "BackupRestore"
            {
                $ExpectedFiles = BuildBackupRestoreFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:BackupRestoreFiles.Count
            }
            "IO"
            {
                $ExpectedFiles = BuildIOFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:IOFiles.Count
            }

            "LightPerf"
            {
                $ExpectedFiles = BuildLightPerfFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:LightPerfFiles.Count
            }
            "ProcessMonitor"
            {
                $ExpectedFiles = BuildProcessMonitorFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:ProcessMonitorFiles.Count
            }
            "ServiceBrokerDbMail"
            {
                $ExpectedFiles = BuildServiceBrokerDbMailFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:ServiceBrokerDbMailFiles.Count
            }
            "NeverEndingQuery"
            {
                $ExpectedFiles = BuildNeverEndingQueryFileArray -IsNoBasic $IsNoBasic
                $ExpectedFileCount = $global:NeverEndingQueryFiles.Count
            }
        }


        #print this if Debug is enabled
        if ($DebugOn)
        {
            Write-Host "******** IsNoBasic: " $IsNoBasic
            Write-Host "******** ScenarioName: " $scenario_string
        }

        WriteToConsoleAndFile -Message "" 
        WriteToConsoleAndFile -Message ("Expected files list: " + $ExpectedFiles)
        WriteToConsoleAndFile -Message ("Expected File Count: " + $ExpectedFileCount)
        


        #-------------------------------------next section does the specific file type validation ------------------------------
        #get a list of all the files in the \Output folder and exclude the \internal folder
        $LogsCollected = Get-ChildItem -Path $global:sqllogscout_latest_output_folder -Exclude "internal"

        $summary_out_string = "File validation test for '$scenario_string':"

        $msg = "-- File validation result for '$scenario_string' scenario --"
        WriteToConsoleAndFile -Message ""
        WriteToConsoleAndFile -Message $msg

        $missing_files_count = 0

        #loop through the expected files array
        foreach ($expFile in $ExpectedFiles)
        {
            $file_found = $false

            #loop through array of actual files found
            foreach ($actFile in $LogsCollected)
            {
                # if a file is found , set the flag to $true
                # for PATTERN: files, use -match instead of -like. These are custom cases where we may need an OR search for multiple files for example
                if ($expFile.StartsWith("PATTERN:"))
                {
                    # remove the PATTERN: from the string and trim spaces
                    $pattern = ($expFile -replace "PATTERN:", "").Trim()
                    if($actFile.Name -match $pattern)
                    {
                        $file_found = $true
                    }
                } 
                else 
                {
                     if($actFile.Name -like ("*" + $expFile + "*"))
                     {
                        $file_found = $true
                     }  
                }
            }

            if ($false -eq $file_found)
            {
                $missing_files_count++
                WriteToConsoleAndFile -Message ("File '$expFile' not found!") -ForegroundColor Red
            }
        } #end of outer loop

        if ($missing_files_count -gt 0)
        {
            WriteToConsoleAndFile -Message ""
            WriteToConsoleAndFile -Message ("Missing file count = $missing_files_count")

            WriteToConsoleAndFile -Message ("Status: FAILED") -ForegroundColor Red

            $summary_out_string =  ($summary_out_string + " "*(60 - $summary_out_string.Length) +"FAILED!!! (See '$global:DetailFile' for more details)")

            $return_val = $false
        }
        else
        {
            WriteToConsoleAndFile -Message ""

            WriteToConsoleAndFile -Message "Status: SUCCESS" -ForegroundColor Green
            WriteToConsoleAndFile -Message ("Summary: All expected log files for scenario '$scenario_string' are present in your latest output folder!!")

            $summary_out_string =  ($summary_out_string + " "*(60 - $summary_out_string.Length) +"SUCCESS")

            $return_val = $true
        }

        #write to Summary.txt if ConsistenQualityTests has been executed
        if ([string]::IsNullOrWhiteSpace($SummaryOutputFile ) -ne $true)
        {
            Write-Output $summary_out_string |Out-File $SummaryOutputFile -Append
        }

        


        #-------------------------------------next section does an overall file count  ------------------------------

        #count the number of files
        $collectCount = ($LogsCollected | Measure-Object).Count

        #first check a simple file count

        $msg = "Total file count in the \Output folder is : " + $collectCount
        
        WriteToConsoleAndFile -Message ""
        WriteToConsoleAndFile -Message $msg
        WriteToConsoleAndFile -Message "`n************************************************************************************************`n"

        #send out success of failure message: true (success) or false (failed)
        #if the expected file count is not equal to the actual file count, then fail
        #if the expected file count is equal to the actual file count, then pass
        return $return_val

    } # end of try
    catch
    {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message
        Write-Host $_.Exception.Message
        $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
        $error_offset = $PSItem.InvocationInfo.OffsetInLine
        Write-LogError "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
        return $false
    }

}

#--------------------------------------------------------Scenario check end ------------------------------------------------------------

function main()
{
    $ret = $true

    # Call Function to set global variables that represent the various SQLLogScout output folder structures like debug, internal, output, testinginfra etc.
    if (!(Set-TestInfraOutputFolder))
    {
        Write-Host "Cannot continue test due to missing folders. Exiting..." -ForegroundColor Red
        return
    }

    #if SQL LogScout has been run longer than 2 days ago, prompt to re-run
    $currentDate = [DateTime]::Now.AddDays(-2)


    try
    {

        # get the latest sqllogscoutlog file and full path
        $sqllogscoutlog = Get-Childitem -Path $global:sqllogscout_latest_output_internal_logpath -Filter $global:sqllogscout_log

        # if check for the file $SqlLogScoutLog
        if (!(Test-Path -Path $sqllogscoutlog))
        {
            throw "SQLLogScoutLog file or path are invalid. Exiting..."
        }

        if ($sqllogscoutlog.LastWriteTime -gt $currentDate)
        {

            # discover scenarios
			[string[]]$scenStrArray = DiscoverScenarios -SqlLogscoutLog $SqlLogscoutLog

            #crate the test results output file
            CreateTestResultsFile -ScenarioArray $scenStrArray

            #write a first line to output file
            $filemsg = "Executing file validation test from output folder: '$global:sqllogscout_latest_output_folder'`n"
            WriteToConsoleAndFile -Message $filemsg
            WriteToConsoleAndFile -Message "`n************************************************************************************************`n"

            #if there are scenarios let's validate the files
			if ($scenStrArray.Count -gt 0)
            {
                $nobasic = $false

				# check for NoBasic and set flag
				foreach($str_scn in $scenStrArray)
                {
                    if ($str_scn -eq "NoBasic")
                    {
                        $nobasic = $true
                    }
                }

                #iterates through the array of scenarios and executes file validation for each of them
                foreach($str_scn in $scenStrArray)
                {
                    WriteToConsoleAndFile -Message ("Scenario: '$str_scn'")

                    if ($str_scn -eq "NoBasic")
                    {
                        WriteToConsoleAndFile -Message "`n************************************************************************************************`n"
                        continue
                    }

                    #validate the file
                    $ret = FileCountAndFileTypeValidation -scenario_string $str_scn -IsNoBasic $nobasic
                }
            }
            else
            {
                WriteToConsoleAndFile -Message "No valid Scenario found to process. Exiting"
                return $false

            }
        }
        else
        {
            Write-Host 'The collected files are old. Please re-run the SQL LogScout and collect more recent logs.......' -ForegroundColor Red
            return $false
        }

        Write-Host "`n`n"
        $msg = "Testing has been completed, the reports are at: " + $global:sqllogscout_testing_infrastructure_output_folder
        Write-Host $msg

        #send out success of failure message: true (success) or false (failed) that came from FileCountAndFileTypeValidation
        return $ret

    }
    catch
    {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message
        Write-Host $_.Exception.Message
        $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
        $error_offset = $PSItem.InvocationInfo.OffsetInLine
        Write-LogError "Function '$mycommand' in 'FileCountAndTypeValidation.ps1' failed with error:  $error_msg (line: $error_linenum, $error_offset)"
    }
}

main

# SIG # Begin signature block
# MIIr5AYJKoZIhvcNAQcCoIIr1TCCK9ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAAj7G3rDJR0eUF
# BDnwscnrdchOnOHK381azinCAK9ntaCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
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
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGqwlLIi+MT04o3BOHbSkNf8A3OBeNZf
# uzRdnG2JqP5KMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# kuFWQ597pKd+coPCH33rV4FmtqVbYqDZyeI2vRjaNV/4jYBnwvHdEafUUnzxSMhG
# KWsdZ294+f+jqIKc4S9LZVx6qKt76p7M1dqvMkphvyoIUTw6NuuoGkTDvI/jY9mm
# W1pe8bpRlB4nEJqS63oPgZ+Ja0Rek1POc+5CAZTgsCEFNJ4GoSXtxgnNiAbXlyi4
# cWLrMhHuStG5LSLgttUWUU0dOG4t9NbThyteJwLSOSgJ0wW1DnvWAj5jwZ3Nh4DT
# ZVN9o6zfC5sbcgbQs17LD9jzxD2HqIwAi2dL5Pc8e/0OZVcqpy4z0EV49rfrM2ag
# mczdgy5CYG1hQH4brrPUHqGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCAbKALmls07CSx50iuwTnOTSsGjQJ3ZyndZA3Z+SJYcJwIGaWkVtLUtGBMyMDI2
# MDIwNDE2MzUyNy4yOThaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIH
# IDCCBQigAwIBAgITMwAAAgh4nVhdksfZUgABAAACCDANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNTNaFw0y
# NjA0MjIxOTQyNTNaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQC1y3AI5lIz3Ip1nK5BMUUbGRsjSnCz/VGs33zvY0NeshsPgfld
# 3/Z3/3dS8WKBLlDlosmXJOZlFSiNXUd6DTJxA9ik/ZbCdWJ78LKjbN3tFkX2c6RR
# pRMpA8sq/oBbRryP3c8Q/gxpJAKHHz8cuSn7ewfCLznNmxqliTk3Q5LHqz2PjeYK
# D/dbKMBT2TAAWAvum4z/HXIJ6tFdGoNV4WURZswCSt6ROwaqQ1oAYGvEndH+DXZq
# 1+bHsgvcPNCdTSIpWobQiJS/UKLiR02KNCqB4I9yajFTSlnMIEMz/Ni538oGI64p
# hcvNpUe2+qaKWHZ8d4T1KghvRmSSF4YF5DNEJbxaCUwsy7nULmsFnTaOjVOoTFWW
# fWXvBuOKkBcQKWGKvrki976j4x+5ezAP36fq3u6dHRJTLZAu4dEuOooU3+kMZr+R
# BYWjTHQCKV+yZ1ST0eGkbHXoA2lyyRDlNjBQcoeZIxWCZts/d3+nf1jiSLN6f6wd
# HaUz0ADwOTQ/aEo1IC85eFePvyIKaxFJkGU2Mqa6Xzq3qCq5tokIHtjhogsrEgfD
# KTeFXTtdhl1IPtLcCfMcWOGGAXosVUU7G948F6W96424f2VHD8L3FoyAI9+r4zyI
# QUmqiESzuQWeWpTTjFYwCmgXaGOuSDV8cNOVQB6IPzPneZhVTjwxbAZlaQIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFKMx4vfOqcUTgYOVB9f18/mhegFNMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQBRszKJKwAfswqdaQPFiaYB/ZNAYWDa040XTcQsCaCu
# a5nsG1IslYaSpH7miTLr6eQEqXczZoqeOa/xvDnMGifGNda0CHbQwtpnIhsutrKO
# 2jhjEaGwlJgOMql21r7Ik6XnBza0e3hBOu4UBkMl/LEX+AURt7i7+RTNsGN0cXPw
# PSbTFE+9z7WagGbY9pwUo/NxkGJseqGCQ/9K2VMU74bw5e7+8IGUhM2xspJPqnSe
# HPhYmcB0WclOxcVIfj/ZuQvworPbTEEYDVCzSN37c0yChPMY7FJ+HGFBNJxwd5lK
# Ir7GYfq8a0gOiC2ljGYlc4rt4cCed1XKg83f0l9aUVimWBYXtfNebhpfr6Lc3jD8
# NgsrDhzt0WgnIdnTZCi7jxjsIBilH99pY5/h6bQcLKK/E6KCP9E1YN78fLaOXkXM
# yO6xLrvQZ+uCSi1hdTufFC7oSB/CU5RbfIVHXG0j1o2n1tne4eCbNfKqUPTE31tN
# bWBR23Yiy0r3kQmHeYE1GLbL4pwknqaip1BRn6WIUMJtgncawEN33f8AYGZ4a3Nn
# HopzGVV6neffGVag4Tduy+oy1YF+shChoXdMqfhPWFpHe3uJGT4GJEiNs4+28a/w
# HUuF+aRaR0cN5P7XlOwU1360iUCJtQdvKQaNAwGI29KOwS3QGriR9F2jOGPUAlpe
# EzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
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
# CxMeblNoaWVsZCBUU1MgRVNOOkEwMDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCNkvu0NKcS
# jdYKyrhJZcsyXOUTNKCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S3vjzAiGA8yMDI2MDIwNDE2MTcxOVoYDzIw
# MjYwMjA1MTYxNzE5WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDtLe+PAgEAMAcC
# AQACAhicMAcCAQACAhIdMAoCBQDtL0EPAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEL
# BQADggEBAHPhG5SbcC6Gg67QIzRV9Ef6w9MO9/GGCWiXkb8ac9gVYxvj3do+xAp3
# j81oqGZ0LKLUDjFop3zwI9SMhpkq1AA+oR1iW7WU+JOsiF3C8sQqGNLJDLnwnS9v
# MUdA4MyudyV9HyDuUiUX7Jrg8wjw2JZtai3cuXyJjefkUFL/cXCaP5yfE+Qt3Hri
# Jn8uUt3gBz3HS785GGntsKGYgwOqsM4fyqj1ihG4nLIFKHW8Kcg0JsAb6jTrjkQV
# VWMhftZ3HWOgXRiId8DJSrX0frzYsFCNKix1Ba3xUpGfhp6d27V1YEJssMi4emz4
# CjzW8vzfxc6uDpSnNwM7bvWthRie2OcxggQNMIIECQIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAgh4nVhdksfZUgABAAACCDANBglghkgB
# ZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCAVrDlVHvFgCFhCseIlMHiSn/B2cZoqgb7ObnZlq79cGDCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EII//jm8JHa2W1O9778t9+Ft2Z5NmKqttPk6Q
# +9RRpmepMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIIeJ1YXZLH2VIAAQAAAggwIgQgxKH5b/AUp9X5FgKyUEZcCow4aoM3ixkp1myS
# y5BFtPswDQYJKoZIhvcNAQELBQAEggIAi+H8ndiKUQZsS/iObtzl01K8pQimbMcd
# +uyTk4SZP4G5tOOHnCEpeEmXmHdnff1MKqjmODsk79wa279KZH3GAj2yF/vYOlTd
# S8ia0QMbekP08RQY7pgD6Hk93xnKEx4vtIVjapTKqHMeIhJJ1iw7XzT8LRt/uAbm
# Vv/cdL0nDMcwEti95DSiHik1npR4LKwFZWXlElTAjxyXeuLT/Uc/q7M+HAY3VxXd
# oRvOOvNXq55oFqp6AOABUelVWXY/tvZvjZUPx3O+b8EL0EqM1TqEKHgoJiCOOZfd
# qfr8CNK5bcORKSWkGuEStKYvqqo7RnaQnzRGZ9vj6S+yIEmEp3eVeYtqukf/JsxM
# B5iIRETGBtOk1RkHfwGzHGAu4mQKmjC1A4id3M86khAMjXcEFCyU7BNYnfd9Jjx+
# 9TOvS1C6sX2F4G3sE58ifKRLT1imdLRYNetor8R+t7WvoguGfXUvjGvHmJI2Ky1t
# 9fFLerrG4vnsP2ZTiN3cIDK40UXkXdEVMQFsgXGlE3Y96LDjRmaz/WRKq4EkA5Hr
# rvRF424DAHokNwBi0bdQBn8cKZZIrjCiZdDTA2O3rtyX2+DPUxOyg15U5O1ZUQ4M
# HpABUTYxc1Pol7fEo5fGCix+1kghKeLsR1GXlG00k9UttgMye/Y68/6PVH/Qixrt
# VDjZPY1EUZ4=
# SIG # End signature block
