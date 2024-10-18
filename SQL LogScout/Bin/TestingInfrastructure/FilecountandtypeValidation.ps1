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
        'azcmagent-logs'
	)

	# inclusions and exclusions to the array
    ModifyArray -ActionType "Add" -TextToFind "This is a Windows Cluster for sure!"  -ArrayToEdit $global:BasicFiles -ReferencedLog "_SQLDIAG"
    ModifyArray -ActionType "Remove" -TextToFind "Azcmagent not found" -ArrayToEdit $global:BasicFiles -ReferencedLog "azcmagent-logs"
    ModifyArray -ActionType "Remove" -TextToFind "Will not collect SQLAssessmentAPI" -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLAssessmentAPI"
    ModifyArray -ActionType "Remove" -TextToFind "No SQLAgent log files found" -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLAGENT"
    ModifyArray -ActionType "Remove" -TextToFind "SQL_AzureVM_Information will not be collected" -ArrayToEdit $global:BasicFiles -ReferencedLog "SQL_AzureVM_Information.out"
    ModifyArray -ActionType "Add" -TextToFind "memory dumps \(max count limit of 20\), from the past 2 months, of size < 100 MB"  -ArrayToEdit $global:BasicFiles -ReferencedLog ".mdmp"
    ModifyArray -ActionType "Add" -TextToFind "memory dumps \(max count limit of 20\), from the past 2 months, of size < 100 MB"  -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLDUMPER_ERRORLOG.log"
    ModifyArray -ActionType "Add" -TextToFind "HADR /AG is enabled on this system" -ArrayToEdit $global:BasicFiles -ReferencedLog "AlwaysOnDiagScript.out"
    ModifyArray -ActionType "Add" -TextToFind "Found AlwaysOn_health files" -ArrayToEdit $global:BasicFiles -ReferencedLog "AlwaysOn_health"
    ModifyArray -ActionType "Add" -TextToFind "This is a Windows Cluster for sure!"  -ArrayToEdit $global:BasicFiles -ReferencedLog "cluster.log"
    ModifyArray -ActionType "Add" -TextToFind "This is a Windows Cluster for sure!"  -ArrayToEdit $global:BasicFiles -ReferencedLog "ClusterInfo.out"
    ModifyArray -ActionType "Add" -TextToFind "This is a Windows Cluster for sure!"  -ArrayToEdit $global:BasicFiles -ReferencedLog "ClusterRegistryHive.out"
    ModifyArray -ActionType "Add" -TextToFind "FullText is installed on this SQL instance" -ArrayToEdit $global:BasicFiles -ReferencedLog "FDLAUNCHERRORLOG"
    ModifyArray -ActionType "Add" -TextToFind "FullText is installed on this SQL instance" -ArrayToEdit $global:BasicFiles -ReferencedLog "_FD"
    ModifyArray -ActionType "Add" -TextToFind "FulText-Search Log file *SQLFT* copied." -ArrayToEdit $global:BasicFiles -ReferencedLog "SQLFT"

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
    #...

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
    #...

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
        'SQLDmpr',
        'SQLDUMPER_ERRORLOG.log'
    )

    #dumpmemory does not collect basic scenario logs with it

    # inclusions and exclusions to the array
    #...

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
        '_MissingMsiMsp_Summary.txt'
    )


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
    #...

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
                # if a file is found , set the flag
                if ($actFile.Name -like ("*" + $expFile + "*"))
                {
                    $file_found = $true
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
