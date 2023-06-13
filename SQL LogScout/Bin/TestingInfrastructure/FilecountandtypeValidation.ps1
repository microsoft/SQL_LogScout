<#
1 - This module validate the all the expected log files are generated , In case if any of the log files not found in output folder 
    it will display the message of the file name in red for each scenario.
2 - To validate a files is there or not we need to add file name in the array of scenario list.
3 - We are checking the scenarion with the text "Scenario Console input:" , so if we make any changes in ##SQLLOGSCOUT.LOG we have to update here as well. 
4 - This module works for multiple scenario validation as well
#>

Import-Module -Name ..\CommonFunctions.psm1
Import-Module -Name ..\LoggingFacility.psm1



$global:sqllogscout_log = "##SQLLOGSCOUT.LOG"
$global:sqllogscoutdebug_log = "##SQLLOGSCOUT_DEBUG.LOG"
$global:filterPatter = @("*.txt", "*.out", "*.csv", "*.xel", "*.blg", "*.sqlplan", "*.trc", "*.LOG","*.etl","*.NGENPDB","*.mdmp", "*.pml")
#------------------------------------------------------------------------------------------------------------------------
function Get-RootDirectory() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
    $present_directory = Convert-Path -Path ".\..\"   #this goes to the SQL LogScout source code directory
    return $present_directory
}
function Get-OutputPathLatest() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
        
    $present_directory = Get-RootDirectory
    $filter="output*"
    $latest = Get-ChildItem -Path $present_directory -Filter $filter | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $output_folder = ($present_directory + "\"+ $latest + "\")

    return $output_folder
}
function Get-InternalPath() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
        
    $output_folder = Get-OutputPathLatest
    $internal_output_folder = ($output_folder + "internal\")

    return $internal_output_folder
}

function Get-InternalLogPath() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
        
    $internal_output_folder = Get-InternalPath
    $internal_output_log = ($internal_output_folder + $global:sqllogscout_log)
   
    return $internal_output_log
}




function TestingInfrastructure-Dir() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2

    $present_directory = Convert-Path -Path "."   #this gets the current directory called \TestingInfrastructure
    $TestingInfrastructure_folder = $present_directory + "\output\"
    New-Item -Path $TestingInfrastructure_folder -ItemType Directory -Force | out-null 
    
    return $TestingInfrastructure_folder
}
#--------------------------------------------------------Scenario check Start ------------------------------------------------------------

function FileCountAndFileTypeValidation([Int]$console_input)
{
    try {         
            $clusterInstance    = Get-Content -Path $debugLog | Select-String -pattern "This is a Windows Cluster for sure!" |select -First 1 | select -Last 1| Select-Object Line | Where-Object { $_ -ne "" }
            $versioncheckvsslog = Get-Content -Path $debugLog | Select-String -pattern "Not collecting SQL VSS log" |select -First 1 | select -Last 1| Select-Object Line | Where-Object { $_ -ne "" }
            
            $output_folder = Get-OutputPathLatest
            $msg = ''
            if ($console_input -eq 0 )
            {
                $nobasic = $false
                $ScenarioName = "Basic"
            }
            # Basic collector refrence iscin each section so initialize on each call
            $basic_collectors = 
                @(
                'ERRORLOG',
                'SQLAGENT',
                'system_health',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',                                                                    
                'SystemInfo_Summary.out',                                                                
                'MiscPssdiagInfo.out',                                                                   
                'TaskListServices.out',                                                                   
                'TaskListVerbose.out',                                                                   
                'PowerPlan.out',                                                                          
                'WindowsHotfixes.out',                                                                  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out',                                                                     
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv',                                                
                'UserRights.out',
                'SQLAGENT.OUT'
                'Fsutil_SectorInfo.out'
                )
                if ($clusterInstance.Length -ne 0) 
                {
                    $collectors +="_SQLDIAG" 
                }

            if (($console_input -eq 0) -and ($nobasic -eq $false))
            {
                $ScenarioName = "Basic"
                
                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_Basic_CollectedFiles_Validation.txt'

                $collectors = $basic_collectors

                $ExpectedFileCount = $basic_collectors.Count
            }
            
            if ($console_input -eq 1)
            {
                $ScenarioName = "GeneralPerf"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_GeneralPerf_CollectedFiles_Validation.txt'

                $GeneralPerf_collectors = 
                @(
                'ERRORLOG',
                'Perfmon.out',
                'xevent_LogScout_target',
                'ExistingProfilerXeventTraces.out',
                'HighCPU_perfstats.out',
                'PerfStats.out',
                'PerfStatsSnapshotStartup.out',
                'Query Store.out',
                'TempDB_and_Tran_Analysis.out',
                'linked_server_config.out',
                'SSB_diag.out'
                'TaskListServices.out', 
                'TaskListVerbose.out',  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'UserRights.out',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',    
                'PowerPlan.out', 
                'WindowsHotfixes.out', 
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv', 
                'PerfStatsSnapshotShutdown.out',                                                   
                'SQLAGENT',                                                               
                'SQLAGENT.OUT',                                                                
                'system_health'
                )

                if ($nobasic -eq $true)
                {
                    if ($GeneralPerf_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $GeneralPerf_collectors.Count - $basic_collectors.Count
                        $collectors  = $GeneralPerf_collectors | where {$basic_collectors -notcontains $_}
                        
                    }
                    else
                    {
                        $ExpectedFileCount = $GeneralPerf_collectors.Count
                        $collectors = $GeneralPerf_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $GeneralPerf_collectors.Count
                    $collectors = $GeneralPerf_collectors
                }
                
            }

            if ($console_input -eq 2)
            {
                $ScenarioName = "DetailedPerf"


                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_DetailedPerf_CollectedFiles_Validation.txt'

                $DetailedPerf_collectors = 
                @(
                'ERRORLOG',
                'Perfmon.out',
                'xevent_LogScout_target',
                'ExistingProfilerXeventTraces.out',
                'HighCPU_perfstats.out',
                'PerfStats.out',
                'PerfStatsSnapshotStartup.out',
                'Query Store.out',
                'TempDB_and_Tran_Analysis.out',
                'linked_server_config.out',
                'SSB_diag.out'
                'TaskListServices.out', 
                'TaskListVerbose.out',  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'UserRights.out',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',    
                'PowerPlan.out', 
                'WindowsHotfixes.out', 
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv', 
                'PerfStatsSnapshotShutdown.out',                                                   
                'SQLAGENT',                                                               
                'SQLAGENT.OUT',                                                                
                'system_health'
                )
                if ($nobasic -eq $true)
                {
                    if ($DetailedPerf_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $DetailedPerf_collectors.Count - $basic_collectors.Count
                        $collectors  = $DetailedPerf_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $DetailedPerf_collectors.Count
                        $collectors = $DetailedPerf_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $DetailedPerf_collectors.Count
                    $collectors = $DetailedPerf_collectors
                }
                
                
            }
            if ($console_input -eq 3)
            {
                $ScenarioName = "Replication"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_Replication_CollectedFiles_Validation.txt'

                $Replication_collectors = 
                @(
                'ERRORLOG',
                'ChangeDataCaptureStartup.out',
                'Change_TrackingStartup.out',
                'TaskListServices.out', 
                'TaskListVerbose.out',  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'UserRights.out',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',    
                'PowerPlan.out', 
                'WindowsHotfixes.out', 
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv', 
                'ChangeDataCaptureShutdown.out',
                'Change_TrackingShutdown.out', 
                'SQLAGENT',                                                               
                'SQLAGENT.OUT',                                                                
                'system_health'
                )
                
                #The logic of replication script is that if it cannot collect data, we don't even write the file. For that reason, we have to dynamically choose whether to look 
                #for it is in the list of files. We search through the logscout.log file for the string that is logged if we collect data to know to look for the file in validation.
                $LogFile = Get-InternalLogPath
                $ReplicationCollected = Get-Content -Path $LogFile | Select-String -Pattern "Collecting Replication Metadata"
                if (                   
                    [string]::IsNullOrEmpty($ReplicationCollected) -eq $false
                    )

                    {
                        $Replication_collectors += "Repl_Metadata_CollectorShutdown.out"

                    }

                If ($versioncheckvsslog.Length -eq 0) 
                {
                    $collectors +="SqlWriterLogger.txt"
                }
                if ($nobasic -eq $true)
                {
                    if ($Replication_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $Replication_collectors.Count - $basic_collectors.Count
                        $collectors  = $Replication_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $Replication_collectors.Count
                        $collectors = $Replication_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $Replication_collectors.Count
                    $collectors = $Replication_collectors
                }
                
                
            }
            if ($console_input -eq 4)
            {
                $ScenarioName = "AlwaysOn"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_AlwaysOn_CollectedFiles_Validation.txt'

                $AlwaysOn_collectors = 
                @(
                'ERRORLOG',
                'AlwaysOnDiagScript.out',
                'AlwaysOn_Data_Movement_target',
                'xevent_LogScout_target',
                'Perfmon.out',
                'TaskListServices.out', 
                'TaskListVerbose.out',  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'UserRights.out',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',    
                'PowerPlan.out', 
                'WindowsHotfixes.out', 
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv', 
                'SQLAGENT',                                                               
                'SQLAGENT.OUT',
                'system_health'
                )
                if ($nobasic -eq $true)
                {
                    if ($AlwaysOn_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $AlwaysOn_collectors.Count - $basic_collectors.Count
                        $collectors  = $AlwaysOn_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $AlwaysOn_collectors.Count
                        $collectors = $AlwaysOn_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $AlwaysOn_collectors.Count
                    $collectors = $AlwaysOn_collectors
                }
                
                
            }
            if ($console_input -eq 5)
            {
                $ScenarioName = "NetworkTrace"


                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_NetworkTrace_CollectedFiles_Validation.txt' 
                              
                $NetworkTrace_collectors = 
                @(
                'ERRORLOG',
                'delete.cab',
                'delete.me',
                'NetworkTrace_1.etl',
                'TaskListServices.out', 
                'TaskListVerbose.out',  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'UserRights.out',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',    
                'PowerPlan.out', 
                'WindowsHotfixes.out', 
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv', 
                'SQLAGENT',                                                               
                'SQLAGENT.OUT',                                                                
                'system_health'
                )
                if ($nobasic.Length -eq 0)
                {
                   $nobasic = $true 
                }
                if ($nobasic -eq $true)
                {
                    if ($NetworkTrace_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $NetworkTrace_collectors.Count - $basic_collectors.Count
                        $collectors  = $NetworkTrace_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $NetworkTrace_collectors.Count
                        $collectors = $NetworkTrace_collectors
                    }
                }
                else 
                {
                    $ExpectedFileCount = $NetworkTrace_collectors.Count
                    $collectors = $NetworkTrace_collectors
                }
                
                
            }

            if ($console_input -eq 6)
            {
                $ScenarioName = "Memory"
 
                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_Memory_CollectedFiles_Validation.txt'
                
                $Memory_collectors = 
                @(
                'ERRORLOG',
                'SQLAGENT',
                'SQL_Server_Mem_Stats.out',
                'Perfmon.out',
                'TaskListServices.out', 
                'TaskListVerbose.out', 
                'FLTMC_Filters.out',
                'FLTMC_Instances.out',
                'SystemInfo_Summary.out',                                                                
                'MiscPssdiagInfo.out', 
                'UserRights.out',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt', 
                'PowerPlan.out', 
                'WindowsHotfixes.out',
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv',
                'SQLAGENT.OUT',
                'system_health'               
                )
                if ($nobasic -eq $true)
                {
                    if ($Memory_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $Memory_collectors.Count - $basic_collectors.Count
                        $collectors  = $Memory_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $Memory_collectors.Count
                        $collectors = $Memory_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $Memory_collectors.Count
                    $collectors = $Memory_collectors
                }
                
                
            }


            if ($console_input -eq 7)
            {
                $ScenarioName = "DumpMemory"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_DumpMemory_CollectedFiles_Validation.txt'

                $DumpMemory_collectors = 
                @(
                'ERRORLOG',
                'TaskListServices.out',                                                                   
                'TaskListVerbose.out', 
                'FLTMC_Filters.out',
                'FLTMC_Instances.out',
                'SystemInfo_Summary.out',                                                                
                'MiscPssdiagInfo.out', 
                'UserRights.out',                               
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',                             
                'PowerPlan.out',                                                                          
                'WindowsHotfixes.out',                                                                  
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv',                                                
                'SQLAGENT',
                'SQLAGENT.OUT'               
                'SQLDmpr',
                'SQLDUMPER_ERRORLOG.log'
                'system_health'
                )
                if ($nobasic -eq $true)
                {
                    if ($DumpMemory_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $DumpMemory_collectors.Count - $basic_collectors.Count
                        $collectors  = $DumpMemory_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $DumpMemory_collectors.Count
                        $collectors = $DumpMemory_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $DumpMemory_collectors.Count
                    $collectors = $DumpMemory_collectors
                }
                
                
            }
            if ($console_input -eq 8)
            {
                $ScenarioName = "WPR"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_WPR_CollectedFiles_Validation.txt'

                $WPR_collectors = 
                @(
                'ERRORLOG',
                'WPR_CPU.etl',
                'WPR_CPU.etl.NGENPDB',
                'TaskListServices.out',                                                                   
                'TaskListVerbose.out', 
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out',
                'MiscPssdiagInfo.out', 
                'UserRights.out',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',
                'PowerPlan.out',
                'WindowsHotfixes.out', 
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv', 
                'SQLAGENT',  
                'SQLAGENT.OUT',           
                'system_health'
                )
                if ($nobasic -eq $true)
                {
                    if ($WPR_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $WPR_collectors.Count - $basic_collectors.Count
                        $collectors  = $WPR_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $WPR_collectors.Count
                        $collectors = $WPR_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $WPR_collectors.Count
                    $collectors = $WPR_collectors
                }
                
                
            }
            if ($console_input -eq 9)
            {
                $ScenarioName = "Setup"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_Setup_CollectedFiles_Validation.txt'

                $Setup_collectors = 
                @(
                'Setup_Bootstrap'
                )
                if ($nobasic -eq $true)
                {
                    if ($Setup_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $Setup_collectors.Count - $basic_collectors.Count
                        $collectors  = $Setup_collectors | where {$basic_collectors -notcontains $_}
                        
                    }
                    else
                    {
                        $ExpectedFileCount = $Setup_collectors.Count
                        $collectors = $Setup_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $Setup_collectors.Count
                    $collectors = $Setup_collectors
                }
                
                
            }
            if ($console_input -eq 10)
            {
                $ScenarioName = "BackupRestore"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_BackupRestore_CollectedFiles_Validation.txt'

                $BackupRestore_collectors = 
                @(
                'ERRORLOG',
                'xevent_LogScout_target',
                'Perfmon.out_000001.blg',
                'VSSAdmin_Providers.out',
                'VSSAdmin_Shadows.out',
                'VSSAdmin_Shadowstorage.out',
                'VSSAdmin_Writers.out',
                'TaskListServices.out',                                                                   
                'TaskListVerbose.out',
                'FLTMC_Filters.out',
                'FLTMC_Instances.out',
                'SystemInfo_Summary.out',
                'MiscPssdiagInfo.out', 
                'UserRights.out',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',                                              
                'PowerPlan.out',                                                                          
                'WindowsHotfixes.out',                                                                  
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv', 
                'SQLAGENT',
                'SQLAGENT.OUT',
                'system_health'
                )

                if ($nobasic -eq $true)
                {
                    if ($BackupRestore_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $BackupRestore_collectors.Count - $basic_collectors.Count
                        $collectors  = $BackupRestore_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $BackupRestore_collectors.Count
                        $collectors = $BackupRestore_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $BackupRestore_collectors.Count
                    $collectors = $BackupRestore_collectors
                }

                
                
            }
            if ($console_input -eq 11)
            {
                $ScenarioName = "IO"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_IO_CollectedFiles_Validation.txt'

                $IO_collectors = 
                @(
                'ERRORLOG',
                'StorPort.etl',
                'High_IO_Perfstats.out',
                'Perfmon.out',
                'TaskListServices.out',                                                                   
                'TaskListVerbose.out', 
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'UserRights.out',                
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',                             
                'PowerPlan.out',                                                                          
                'WindowsHotfixes.out',                                                             
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv',
                'SQLAGENT',
                'SQLAGENT.OUT',
                'system_health'
                )
                if ($nobasic -eq $true)
                {
                    if ($IO_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $IO_collectors.Count - $basic_collectors.Count
                        $collectors  = $IO_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $IO_collectors.Count
                        $collectors = $IO_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $IO_collectors.Count
                    $collectors = $IO_collectors
                }
                
                
            }
            if ($console_input -eq 12)
            {
                $ScenarioName = "LightPerf"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_LightPerf_CollectedFiles_Validation.txt'

                $LightPerf_collectors = 
                @(
                'ERRORLOG',
                'SQLAGENT',
                'system_health',
                'RunningDrivers.csv',                                                                     
                'RunningDrivers.txt',                                                                    
                'SystemInfo_Summary.out',                                                                
                'MiscPssdiagInfo.out',                                                                   
                'TaskListServices.out',                                                                   
                'TaskListVerbose.out',                                                                   
                'PowerPlan.out',                                                                          
                'WindowsHotfixes.out',                                                                  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out',                                                                     
                'Instances.out',                                                                   
                'EventLog_Application.csv',                                                                        
                'EventLog_System.csv',                                                
                'UserRights.out',
                'SQLAGENT.OUT'
                )
                
                if ($nobasic -eq $true)
                {
                    if ($LightPerf_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $LightPerf_collectors.Count - $basic_collectors.Count
                        $collectors  = $LightPerf_collectors | where {$basic_collectors -notcontains $_}
                    }
                    else
                    {
                        $ExpectedFileCount = $LightPerf_collectors.Count
                        $collectors = $LightPerf_collectors
                    }
                }
                else
                {
                    $ExpectedFileCount = $LightPerf_collectors.Count
                    $collectors = $LightPerf_collectors
                }
                
            }

            if ($console_input -eq 13)
            {
                $ScenarioName = "ProcessMonitor"

                $ReportPathInternal = $TestingInfrastructure_folder + $date + '_ProcessMonitor_CollectedFiles_Validation.txt'

                $Procmon_collectors = 
                @(
                'ProcessMonitor.pml'
                )
                
                $ExpectedFileCount = $Procmon_collectors.Count
                $collectors = $Procmon_collectors
                
            }


                $fileContent  | Select-object @{Name = $file.Name ; Expression = 
                {
                    if ($_.Name -eq "Executing Collector") 
                    {    
                        "Total Collector Files found: "  + ($_.Count)

                        #Write-Host 'The Total Executing Collectors and Generated output file count validation Report:' 
                        $collecCount =  ($_.Count)

                        Write-Host "`n"
                        Write-Host "`n"
                        Write-Host "TEST: Executing Collectors count Validation for '$ScenarioName' Scenario"

                        $collecCount = (Get-ChildItem -Path $output_folder | Measure-Object).Count  

                        If  ($collecCount -ge $ExpectedFileCount)
                        {

                            $msg = "You executed '$ScenarioName' scenario. Minimum expected count is $ExpectedFileCount. Current file count is : " + $collecCount + "  "
                            $msg = $msg.replace("`n", " ")
                                            
                            Write-Host "`n`n------ File Count Validation Result ------"
                            Write-Host 'Status:	 SUCCESS' -ForegroundColor Green
                            Write-Host "Summary: $msg "
                            Write-Host "`n`n------ File type Validation Result ------"

                            
                                
                            $missedfilescount = 0
                            For ($i=0; $i -lt $collectors.Length; $i++) 
                            {
                                $blnfileexist =  '0'

                                Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $collectors[$i] + "*" }| select FullName)
                                {
                                    $blnfileexist =  '1'
                                }
                                if ($blnfileexist -eq  '0')
                                {
                                    $missedfilescount = $missedfilescount +1

                                    if ($ScenarioName -eq "DumpMemory")
                                    {
                                        if ($collectors[$i] -eq "SQLDmpr")
                                        {
                                            $collectors[$i] = $collectors[$i] + 'xxxn.mdmp ' +  ' ( n is series number, there will multiple files like SQLDmpr0001.mdmp ,SQLDmpr0002.mdmp,... based on your input'
                                        }

                                    }
                                    Write-Host 'File not found with name like -> '$collectors[$i] -ForegroundColor red
                                    $msg = $msg + ',' + 'File not found with name like '+ $collectors[$i]
                                }
                            }
                            if ($missedfilescount -ne '0')
                            {
                                Write-Host "`n"
                                Write-Host "Missing file count is -> $missedfilescount"
                                Write-Host "`n"
                                Write-Host 'Status:    FAILED' -ForegroundColor Red
                                $summarymsg = $summarymsg  +  'Test result of Scenario  $ScenarioName  - Status FAILED' 
                                $summarymsg = $summarymsg  + "`n"
                                $summarymsg = $summarymsg  + "`n"
                                echo "Test '$ScenarioName'  FAILED!!!" >> $SummaryFile
                            }
                            else
                            {
								Write-Host "Status:  SUCCESS" -ForegroundColor Green
                                Write-Host "Summary: All expected log files for scenario '$ScenarioName' are present in your latest output folder!!"
                                $msg = $msg + ',' + 'All expected log files are there in your latest output folder!!' #+ ','+ ','
                                $summarymsg = $summarymsg  +   'Test result of Scenario  $ScenarioName  - Status Success' 
                                $summarymsg = $summarymsg  + "`n"
                                $summarymsg = $summarymsg  + "`n"
                                echo "Test '$ScenarioName'  SUCCESS" >> $SummaryFile
								
                            }

                            $msg = $msg.replace(",","`n")
                            Write-Host $ReportPathInternal
                            echo $msg >>  $ReportPathInternal
                            

                        }
                        else
                        {
                            $msg = "You executed '$ScenarioName' scenario; mimimum collector count should be $ExpectedFileCount. Actual collector count is : " + $collecCount
                            $msg = $msg.replace("`n", " ")
                            Write-Host 'Status:  FAILED' -ForegroundColor Red
                            Write-Host 'Summary: ' $msg
                            Write-Host "`n************************************************************************************************`n"
                            echo $msg >>  $ReportPathInternal
                            echo "Test '$ScenarioName' FAILED!!!" >> $SummaryFile
                        }
                    }
           }
       } 
    } 
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-Host $_.Exception.Message
        $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
        $error_offset = $PSItem.InvocationInfo.OffsetInLine
        Write-LogError "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
        return
    }
}
function getscenarioname([int] $scenarioID) 
{
    if ($scenarioID -eq 0 )
    {$scenarioname = "Basic"}
    ElseIf($scenarioID -eq 1)
    {$scenarioname = "GeneralPerf"}
    ElseIf($scenarioID -eq 2)
    {$scenarioname = "DetailedPerf"}
    ElseIf($scenarioID -eq 3)
    {$scenarioname = "Replication"}
    ElseIf($scenarioID -eq 4)
    {$scenarioname = "AlwaysOn"}
    ElseIf($scenarioID -eq 5)
    {$scenarioname = "NetworkTrace"}
    ElseIf($scenarioID -eq 6)
    {$scenarioname = "Memory"}
    ElseIf($scenarioID -eq 7)
    {$scenarioname = "DumpMemory"}
    ElseIf($scenarioID -eq 8)
    {$scenarioname = "WPR"}
    ElseIf($scenarioID -eq 9)
    {$scenarioname = "Setup"}
    ElseIf($scenarioID -eq 10)
    {$scenarioname = "BackupRestore"}
    ElseIf($scenarioID -eq 11)
    {$scenarioname = "IO"}
    ElseIf($scenarioID -eq 12)
    {$scenarioname = "LightPerf"}
    ElseIf($scenarioID -eq 12)
    {$scenarioname = "ProcessMonitor"}
    return $scenarioname;
}
#--------------------------------------------------------Scenario check end ------------------------------------------------------------

function main() {

    $date = ( get-date ).ToString('yyyyMMddhhmmss');
    $currentDate = [DateTime]::Now.AddDays(-1)
    $output_folder = Get-OutputPathLatest
    $error_folder = Get-InternalPath
    $TestingInfrastructure_folder = TestingInfrastructure-Dir 

    $consolpath = $TestingInfrastructure_folder + 'consoloutput.txt'

    #$ReportPathInternal = $TestingInfrastructure_folder + $date + '_CollectedFiles_Validation.txt'
    $SummaryFile = $TestingInfrastructure_folder + 'Summary.txt'

    if (!(Test-Path -Path $SummaryFile))
    {
        New-Item -itemType File -Path  $TestingInfrastructure_folder -Name 'Summary.txt'
    }

    $error1 = 0

    try {
            $count = 0
            if (!(Test-Path -Path $output_folder ))
            {
                $message1 = "Files are missing or folder " + $output_folder + " not exist"
                            $message1 = $message1.replace("`n", " ")
                Write-LogDebug $message1
                $TestingInfrastructure_folder1 =  $TestingInfrastructure_folder + 'FileMissing.LOG'
                echo $message1 > $TestingInfrastructure_folder1 
            }
            if (!(Test-Path -Path $error_folder ))
            {
                $message1 = "Files are missing or folder " + $error_folder + " not exist"
                                $message1 = $message1.replace("`n", " ")
                echo $message1 >> $TestingInfrastructure_folder1
                break;
            }
           #---------------------------------------------------Pulling the data from $global:sqllogscoutdebug_log
            $debugLog =  Get-Childitem -Path $error_folder -Include $global:filterPatter -Recurse -Filter $global:sqllogscoutdebug_log

            Foreach ($file in Get-Childitem -Path $error_folder -Include $global:filterPatter -Recurse -Filter $global:sqllogscout_log ) 
            {
                
                if ($file.LastWriteTime -gt $currentDate) 
                {            
                    $selectoutputfile =  2
                    $present_directory = Get-RootDirectory
                    $filter="output*"
                    $latest = Get-ChildItem -Path $present_directory -Filter $filter | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    
                    if ($latest.Name -eq "output")
                    {
                        $selectoutputfile =  2
                    }
                    elseif ((Get-Content -Path $file | Select-String -pattern "Console input: D" | Select-Object Line | Where-Object { $_ -ne "" }) -ne "" )
                    {
                        $selectoutputfile =  3
                    }
                    else
                    {
                        $selectoutputfile =  3
                    }
                    
                    Get-Content -Path $file | Select-String -pattern "Scenario Console input:" |select -First $selectoutputfile | select -Last 1| Select-Object Line | Where-Object { $_ -ne "" } > $consolpath
                    [String] $t = '';Get-Content $consolpath | % {$t += " $_"};[Regex]::Match($t, '(\w+)[^\w]*$').Groups[2].Value
                    
                    $lostcolon = $t.LastIndexOf(":")
                    $lostcolon = $lostcolon +1
                    $len = $t.Length 
                    $console_input = ($t.Substring($lostcolon,$len - $lostcolon).TrimEnd()).TrimStart()
                    
                    If ($console_input -eq "")
                    {
                        
                        [String] $commandlineinput = Get-Content -Path $file | Select-String -pattern "The scenarios selected are:" > $consolpath
                        [String] $t = '';Get-Content $consolpath | % {$t += " $_"};[Regex]::Match($t, '(\w+)[^\w]*$').Groups[2].Value
                        $nobasic = Get-Content $consolpath | Select-String -pattern "NoBasic"
                        if ($nobasic -ne "")
                        {
                            $nobasic = $true
                        }
                        $t = $t.Replace('NoBasic','')
                        #$t = $t.Replace(' ','')
                        $lostcolon = $t.LastIndexOf(":")
                        $lostcolon = $lostcolon+1
                        $len = $t.Length
                        $t = ($t.Substring($lostcolon,$len - $lostcolon-1).TrimEnd()).TrimStart()
                        $t = $t.Replace('''','')
                        $t = $t.Replace(' ','+')
                        $t = $t.Replace('NoBasic','')
                        $t = $t.Replace('Basic','0')
                        $t = $t.Replace('GeneralPerf','1')
                        $t = $t.Replace('DetailedPerf','2')
                        $t = $t.Replace('Replication','3')
                        $t = $t.Replace('AlwaysOn','4')
                        $t = $t.Replace('NetworkTrace','5')
                        $t = $t.Replace('Memory','6')
                        $t = $t.Replace('DumpMemory','7')
                        $t = $t.Replace('WPR','8')
                        $t = $t.Replace('Setup','9')
                        $t = $t.Replace('BackupRestore','10')
                        $t = $t.Replace('IO','11')
                        $t = $t.Replace('LightPerf','12')
                        $t = $t.Replace('ProcessMonitor','13')
                        $console_input = $t
                    }
                    #---------------------------------------For User ran the single Scenario-------------------------
                    $checkmupluscenario = $console_input.IndexOf("+")
                    
                    If ($console_input.IndexOf("+") -ne 1)
                    {
                        try 
                        {
                            $scenarioID = [convert]::ToInt32($console_input)
                            $scenarioID = $console_input
                            if (Test-Path $consolpath) {
                              Remove-Item $consolpath
                            }                            
                            $scenarioname1 = getscenarioname($scenarioID)
                            if ($scenarioname1 -eq "") {break;}
                            $ReportPath = $TestingInfrastructure_folder + $date + '_' + $scenarioname1 + '_ExecutingCollector_CountValidation.txt'
                            $filemsg = "Executing Log File validation test from Source Folder: '" + $error_folder + $global:sqllogscout_log + "'" + " and cross verifying 'executing collector' info with output folder '" +  $output_folder +"'"
                            Write-Host $filemsg
                            echo $filemsg > $ReportPath
                            echo 'The collectors files are are below.......' >> $ReportPath
                            Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" } >>$ReportPath
                            $fileContent = Get-Content -Path $file | Select-String "Executing Collector" | Group-Object -property Pattern
                            FileCountAndFileTypeValidation($scenarioID)

                        }
                        catch [FormatException] {
                            Write-LogDebug "The scenario ID is '", $scenarioID, "' is not an integer"
                            continue 
                        }
                    } 
                    #---------------------------------------For User ran the multiple Scenario-------------------------
                    elseif ($console_input.IndexOf("+") -eq 1)
                    {
                        $scenarioname1 = ""
                        [string[]]$scenStrArray = $console_input.Split('+')
                        Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" } >>$ReportPath
                        $fileContent = Get-Content -Path $file | Select-String "Executing Collector" | Group-Object -property Pattern
                        $totalprint = $false


                        #remove any blank elements in the array 
                        $scenStrArray = $scenStrArray.Where({ "" -ne $_ })

                        foreach($str_scn in $scenStrArray) 
                        {
                            try 
                            {
                                $scenarioID = [convert]::ToInt32($str_scn.trim()) 
                                
                                 if ($scenarioID -eq 0)
                                 {
                                    $nobasic = $false
                                 }
                                 
                                 if (Test-Path $consolpath) {
                                 Remove-Item $consolpath
                                 } 
                                Write-Host "Scenario: $scenarioname1"
                                $scenarioname1 = getscenarioname($scenarioID)
                                $ReportPath = $TestingInfrastructure_folder + $date + '_' + $scenarioname1 + '_ExecutingCollector_CountValidation.txt'
                                $filemsg = "Executing Log File validation test from Source Folder: '" + $error_folder + $global:sqllogscout_log + "'" + " and cross verifying 'executing collector' info with output folder '" +  $output_folder +"'"
                                Write-Host $filemsg
                                echo $filemsg > $ReportPath
                                echo 'The collectors files are are below.......' >> $ReportPath
                                Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" } >>$ReportPath
                                $fileContent = Get-Content -Path $file | Select-String "Executing Collector" | Group-Object -property Pattern
                                FileCountAndFileTypeValidation($scenarioID)

                            }
                            catch 
                            {
                                Write-LogError "$($PSItem.Exception.Message)"
                                $scenStrArray =@()
                                $int_scn = $false
                            }
                        }
                    } 
                }
                else 
                {
                    echo 'The collectors files are old.......' >> $ReportPath
                    Write-Host 'The collectors files are old, Please re-run the tool and collect lataest logs.......' -ForegroundColor Red
                }            
            }
            Write-Host "`n`n"
            $msg2 = "Testing has been completed, the reports are at: " + $TestingInfrastructure_folder 
            Write-Host $msg2
            
            if (Test-Path $consolpath) {
            Remove-Item $consolpath
            }    


        }
        catch {
            $mycommand = $MyInvocation.MyCommand
            $error_msg = $PSItem.Exception.Message 
            Write-Host $_.Exception.Message
            $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
            $error_offset = $PSItem.InvocationInfo.OffsetInLine
            Write-LogError "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
        }
}
main 

