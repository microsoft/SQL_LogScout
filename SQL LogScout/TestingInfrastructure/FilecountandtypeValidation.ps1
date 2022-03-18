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
# function Write-LogDebug() {
#     <#
#     .SYNOPSIS
#         Write-LogDebug is a wrapper to Write-Log standardizing console color output
#         Logging of debug messages will be skip if debug logging is disabled.

#     .DESCRIPTION
#         Write-LogDebug is a wrapper to Write-Log standardizing console color output
#         Logging of debug messages will be skip if debug logging is disabled.

#     .PARAMETER Message
#         Message string to be logged

#     .PARAMETER DebugLogLevel
#         Optional - Level of the debug message ranging from 1 to 5.
#         When ommitted Level 1 is assumed.

#     .EXAMPLE
#         Write-LogDebug "Inside" $MyInvocation.MyCommand -DebugLogLevel 2
#     #>
#     [CmdletBinding()]
#     param ( 
#         [Parameter(Position = 0, Mandatory, ValueFromRemainingArguments)] 
#         [ValidateNotNull()]
#         $Message,

#         [Parameter()]
#         [ValidateRange(1, 5)]
#         [Int]$DebugLogLevel
#     )

#     #when $DebugLogLevel is not specified we assume it is level 1
#     #this is to avoid having to refactor all calls to Write-LogDebug because of new parameter
#     if (($null -eq $DebugLogLevel) -or (0 -eq $DebugLogLevel)) { $DebugLogLevel = 1 }

#     try {

#         #log message if debug logging is enabled and
#         #debuglevel of the message is less than or equal to global level
#         #otherwise we just skip calling Write-Log
#         if (($global:DEBUG_LEVEL -gt 0) -and ($DebugLogLevel -le $global:DEBUG_LEVEL)) {
#             Write-Log -Message $Message -LogType "DEBUG$DebugLogLevel" -ForegroundColor Magenta
#             return #return here so we don't log messages twice if both debug flags are enabled
#         }
            
#     }
#     catch {
#         $mycommand = $MyInvocation.MyCommand
#         $error_msg = $PSItem.Exception.Message 
#         Write-Host $_.Exception.Message
#         $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
#         $error_offset = $PSItem.InvocationInfo.OffsetInLine
#         Write-Host "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
#     }
# }



function TestingInfrastructure-Dir() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2

    $present_directory = Convert-Path -Path "."   #this gets the current directory called \TestingInfrastructure
    $TestingInfrastructure_folder = $present_directory + "\output\"
    New-Item -Path $TestingInfrastructure_folder -ItemType Directory -Force | out-null 
    
    return $TestingInfrastructure_folder
}
#--------------------------------------------------------Scenario check Start ------------------------------------------------------------

function filecountAndFiletypeValidation([Int]$console_input)
{
    try {         
            $clusterInstance    = Get-Content -Path $debugLog | Select-String -pattern "This is a Windows Cluster for sure!" |select -First 1 | select -Last 1| Select-Object Line | Where-Object { $_ -ne "" }
            $versioncheckvsslog = Get-Content -Path $debugLog | Select-String -pattern "Not collecting SQL VSS log" |select -First 1 | select -Last 1| Select-Object Line | Where-Object { $_ -ne "" }
            
            $output_folder = Get-OutputPathLatest


            IF (($console_input -eq 0) -or ($nobasic = $true))
            {
                $ScenarioName = "Basic"

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
                'SQLAssessmentAPI.out',
                'UserRights.out',
                'SQLAGENT.OUT'
                )
                $collectors = $basic_collectors
                if ($clusterInstance.Length -ne 0) 
                {
                    $collectors +="_SQLDIAG" 
                }
                
                $ExpectedFileCount = $basic_collectors.Count
            }
        
            IF ($console_input -eq 1)
            {
                $ScenarioName = "GeneralPerf"
                
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
                'TempDBAnalysis.out',
                'linked_server_config.out',
                'SSB_diag.out'
                'TaskListServices.out', 
                'TaskListVerbose.out',  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'SQLAssessmentAPI.out',
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

                if ($nobasic = $true)
                {
                    if ($GeneralPerf_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $GeneralPerf_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object  $GeneralPerf_collectors $basic_collectors) | select -Expand InputObject
                        
                    }
                    Else
                    {
                        $ExpectedFileCount = $GeneralPerf_collectors.Count
                        $collectors = $GeneralPerf_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $GeneralPerf_collectors.Count
                    $collectors = $GeneralPerf_collectors
                }
                
            }

            IF ($console_input -eq 2)
            {
                $ScenarioName = "DetailedPerf"

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
                'TempDBAnalysis.out',
                'linked_server_config.out',
                'SSB_diag.out'
                'TaskListServices.out', 
                'TaskListVerbose.out',  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'SQLAssessmentAPI.out',
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
                if ($nobasic = $true)
                {
                    if ($DetailedPerf_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $DetailedPerf_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $DetailedPerf_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $DetailedPerf_collectors.Count
                        $collectors = $DetailedPerf_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $DetailedPerf_collectors.Count
                    $collectors = $DetailedPerf_collectors
                }
                
                
            }
            IF ($console_input -eq 3)
            {
                $ScenarioName = "Replication"

                $Replication_collectors = 
                @(
                'ERRORLOG',
                'Repl_Metadata_Collector.out',
                'ChangeDataCaptureStartup.out',
                'Change_TrackingStartup.out',
                'TaskListServices.out', 
                'TaskListVerbose.out',  
                'FLTMC_Filters.out',
                'FLTMC_Instances.out', 
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',
                'SQLAssessmentAPI.out',
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
                
                If ($versioncheckvsslog.Length -eq 0) 
                {
                    $collectors +="SqlWriterLogger.txt"
                }
                if ($nobasic = $true)
                {
                    if ($Replication_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $Replication_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $Replication_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $Replication_collectors.Count
                        $collectors = $Replication_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $Replication_collectors.Count
                    $collectors = $Replication_collectors
                }
                
                
            }
            IF ($console_input -eq 4)
            {
                $ScenarioName = "AlwaysOn"

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
                'SQLAssessmentAPI.out',
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
                if ($nobasic = $true)
                {
                    if ($AlwaysOn_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $AlwaysOn_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $AlwaysOn_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $AlwaysOn_collectors.Count
                        $collectors = $AlwaysOn_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $AlwaysOn_collectors.Count
                    $collectors = $AlwaysOn_collectors
                }
                
                
            }
            IF ($console_input -eq 5)
            {
                $ScenarioName = "NetworkTrace"

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
                'SQLAssessmentAPI.out',
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
                if ($nobasic = $true)
                {
                    if ($NetworkTrace_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $NetworkTrace_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $NetworkTrace_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $NetworkTrace_collectors.Count
                        $collectors = $NetworkTrace_collectors
                    }
                }
                Else 
                {
                    $ExpectedFileCount = $NetworkTrace_collectors.Count
                    $collectors = $NetworkTrace_collectors
                }
                
                
            }

            IF ($console_input -eq 6)
            {
                $ScenarioName = "Memory"
                
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
                'SQLAssessmentAPI.out',
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
                if ($nobasic = $true)
                {
                    if ($Memory_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $Memory_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $Memory_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $Memory_collectors.Count
                        $collectors = $Memory_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $Memory_collectors.Count
                    $collectors = $Memory_collectors
                }
                
                
            }


            IF ($console_input -eq 7)
            {
                $ScenarioName = "DumpMemory"

                $DumpMemory_collectors = 
                @(
                'ERRORLOG',
                'TaskListServices.out',                                                                   
                'TaskListVerbose.out', 
                'FLTMC_Filters.out',
                'FLTMC_Instances.out',
                'SystemInfo_Summary.out',                                                                
                'MiscPssdiagInfo.out', 
                'SQLAssessmentAPI.out',
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
                if ($nobasic = $true)
                {
                    if ($DumpMemory_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $DumpMemory_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $DumpMemory_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $DumpMemory_collectors.Count
                        $collectors = $DumpMemory_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $DumpMemory_collectors.Count
                    $collectors = $DumpMemory_collectors
                }
                
                
            }
            IF ($console_input -eq 8)
            {
                $ScenarioName = "WPR"

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
                'SQLAssessmentAPI.out',
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
                if ($nobasic = $true)
                {
                    if ($WPR_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $WPR_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $WPR_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $WPR_collectors.Count
                        $collectors = $WPR_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $WPR_collectors.Count
                    $collectors = $WPR_collectors
                }
                
                
            }
            IF ($console_input -eq 9)
            {
                $ScenarioName = "Setup"

                $Setup_collectors = 
                @(
                'Setup_Bootstrap',
                'ERRORLOG', 
                'TaskListServices.out',                                                                   
                'TaskListVerbose.out',
                'FLTMC_Filters.out',
                'FLTMC_Instances.out',
                'SystemInfo_Summary.out', 
                'MiscPssdiagInfo.out',                
                'SQLAssessmentAPI.out',
                'UserRights.out'
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
                if ($nobasic = $true)
                {
                    if ($Setup_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $Setup_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $Setup_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $Setup_collectors.Count
                        $collectors = $Setup_collectors
                    }
                }
                Els
                {
                    $ExpectedFileCount = $Setup_collectors.Count
                    $collectors = $Setup_collectors
                }
                
                
            }
            IF ($console_input -eq 10)
            {
                $ScenarioName = "BackupRestore"

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
                'SQLAssessmentAPI.out',
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

                if ($nobasic = $true)
                {
                    if ($BackupRestore_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $BackupRestore_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $BackupRestore_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $BackupRestore_collectors.Count
                        $collectors = $BackupRestore_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $BackupRestore_collectors.Count
                    $collectors = $BackupRestore_collectors
                }

                
                
            }
            IF ($console_input -eq 11)
            {
                $ScenarioName = "IO"

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
                'SQLAssessmentAPI.out',
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
                if ($nobasic = $true)
                {
                    if ($IO_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $IO_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $IO_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $IO_collectors.Count
                        $collectors = $IO_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $IO_collectors.Count
                    $collectors = $IO_collectors
                }
                
                
            }
            IF ($console_input -eq 12)
            {
                $ScenarioName = "LightPerf"

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
                'SQLAssessmentAPI.out',
                'UserRights.out',
                'SQLAGENT.OUT'
                )
                
                if ($nobasic = $true)
                {
                    if ($LightPerf_collectors.Count - $basic_collectors.Count -gt 0)
                    {
                        $ExpectedFileCount = $LightPerf_collectors.Count - $basic_collectors.Count
                        $collectors = @(Compare-Object $basic_collectors $LightPerf_collectors) | select -Expand InputObject
                    }
                    Else
                    {
                        $ExpectedFileCount = $LightPerf_collectors.Count
                        $collectors = $LightPerf_collectors
                    }
                }
                Else
                {
                    $ExpectedFileCount = $LightPerf_collectors.Count
                    $collectors = $LightPerf_collectors
                }
                
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
                        Write-Host "TEST: Executing Collectors count Validation for $ScenarioName  Scenario"

                        $collecCount = (Get-ChildItem -Path $output_folder | Measure-Object).Count  

                        $PatternBasic = @("*.txt", "*.out", "*.csv", "*.xel","*.hiv", "*.blg", "*.sqlplan", "*.trc", "*.LOG","*.etl","*.NGENPDB","*.mdmp")


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
                            }
                            else
                            {
								Write-Host "Status:  SUCCESS" -ForegroundColor Green
                                Write-Host "Summary: All expected log files for scenario '$ScenarioName' are present in your latest output folder!!"
                                $msg = $msg + ',' + 'All expected log files are there in your latest output folder!!' + ','+ ','
								
                            }

                            $msg = $msg.replace(",","`n")
                            Write-Host $ReportPathInternal
                            echo $msg >>  $ReportPathInternal


                        }
                        Else
                        {
                            $msg = "You executed '$ScenarioName' scenario; mimimum collector count should be $BasicExpectedCount. Actual collector count is : " + $collecCount
                            $msg = $msg.replace("`n", " ")
                            Write-Host 'Status:  FAILED' -ForegroundColor Red
                            Write-Host 'Summary: ' $msg
                            Write-Host "`n************************************************************************************************`n"
                            echo $msg >>  $ReportPathInternal
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
        Write-Host "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
        return
    }
}

#--------------------------------------------------------Scenario check end ------------------------------------------------------------

function main() {
    $date = ( get-date ).ToString('yyyyMMddhhmmss');
    $currentDate = [DateTime]::Now.AddDays(-1)
    $output_folder = Get-OutputPathLatest
    $error_folder = Get-InternalPath
    $TestingInfrastructure_folder = TestingInfrastructure-Dir 
    
    $consolpath = $TestingInfrastructure_folder + 'consoloutput.txt'
    $ReportPath = $TestingInfrastructure_folder + $date + '_ExecutingCollector_CountValidation.txt'
    $ReportPathInternal = $TestingInfrastructure_folder + $date + '_CollectedFiles_Validation.txt'
    $error1 = 0
    $filter_pattern = @("*.txt", "*.out", "*.csv", "*.xel", "*.blg", "*.sqlplan", "*.trc", "*.LOG","*.etl","*.NGENPDB","*.mdmp")

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
            $ReportPath = $TestingInfrastructure_folder + $date + '_ExecutingCollector_CountValidation.txt'
            $filemsg = "Executing Log File validation test from Source Folder: '" + $error_folder + $global:sqllogscout_log + "'" + " and cross verifying 'executing collector' info with output folder '" +  $output_folder +"'"
            #Write-Host '         '
            Write-Host $filemsg
            #Write-Host '         '
            echo $filemsg > $ReportPath

           #---------------------------------------------------Pulling the data from $global:sqllogscoutdebug_log
            $debugLog =  Get-Childitem -Path $error_folder -Include $filter_pattern -Recurse -Filter $global:sqllogscoutdebug_log

            Foreach ($file in Get-Childitem -Path $error_folder -Include $filter_pattern -Recurse -Filter $global:sqllogscout_log ) 
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
                    elseIf ((Get-Content -Path $file | Select-String -pattern "Console input: D" | Select-Object Line | Where-Object { $_ -ne "" }) -ne "" )
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
                        $t
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
                            echo 'The collectors files are are below.......' >> $ReportPath
                            Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" } >>$ReportPath
                            $fileContent = Get-Content -Path $file | Select-String "Executing Collector" | Group-Object -property Pattern

                            filecountAndFiletypeValidation($scenarioID)

                        }
                        catch [FormatException] {
                            Write-LogDebug "The scenario ID is '", $scenarioID, "' is not an integer"
                            continue 
                        }
                    } 
                    #---------------------------------------For User ran the multiple Scenario-------------------------
                    elseif ($console_input.IndexOf("+") -eq 1)
                    {
                        echo 'The collectors files are are below.......' >> $ReportPath
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
                                 
                                 if (Test-Path $consolpath) {
                                 Remove-Item $consolpath
                                 }                                

                                 filecountAndFiletypeValidation($scenarioID)

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
            
            


        }
        catch {
            $mycommand = $MyInvocation.MyCommand
            $error_msg = $PSItem.Exception.Message 
            Write-Host $_.Exception.Message
            $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
            $error_offset = $PSItem.InvocationInfo.OffsetInLine
            Write-Host "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
        }
}
main 


# SIG # Begin signature block
# MIInpwYJKoZIhvcNAQcCoIInmDCCJ5QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBIzH9v4Ts9EEck
# h5sd/Bdh4ecwLTIS68Fj0tbCd4ogW6CCDYUwggYDMIID66ADAgECAhMzAAACU+OD
# 3pbexW7MAAAAAAJTMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMzAwWhcNMjIwOTAxMTgzMzAwWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDLhxHwq3OhH+4J+SX4qS/VQG8HybccH7tnG+BUqrXubfGuDFYPZ29uCuHfQlO1
# lygLgMpJ4Geh6/6poQ5VkDKfVssn6aA1PCzIh8iOPMQ9Mju3sLF9Sn+Pzuaie4BN
# rp0MuZLDEXgVYx2WNjmzqcxC7dY9SC3znOh5qUy2vnmWygC7b9kj0d3JrGtjc5q5
# 0WfV3WLXAQHkeRROsJFBZfXFGoSvRljFFUAjU/zdhP92P+1JiRRRikVy/sqIhMDY
# +7tVdzlE2fwnKOv9LShgKeyEevgMl0B1Fq7E2YeBZKF6KlhmYi9CE1350cnTUoU4
# YpQSnZo0YAnaenREDLfFGKTdAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUlZpLWIccXoxessA/DRbe26glhEMw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzQ2NzU5ODAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AKVY+yKcJVVxf9W2vNkL5ufjOpqcvVOOOdVyjy1dmsO4O8khWhqrecdVZp09adOZ
# 8kcMtQ0U+oKx484Jg11cc4Ck0FyOBnp+YIFbOxYCqzaqMcaRAgy48n1tbz/EFYiF
# zJmMiGnlgWFCStONPvQOBD2y/Ej3qBRnGy9EZS1EDlRN/8l5Rs3HX2lZhd9WuukR
# bUk83U99TPJyo12cU0Mb3n1HJv/JZpwSyqb3O0o4HExVJSkwN1m42fSVIVtXVVSa
# YZiVpv32GoD/dyAS/gyplfR6FI3RnCOomzlycSqoz0zBCPFiCMhVhQ6qn+J0GhgR
# BJvGKizw+5lTfnBFoqKZJDROz+uGDl9tw6JvnVqAZKGrWv/CsYaegaPePFrAVSxA
# yUwOFTkAqtNC8uAee+rv2V5xLw8FfpKJ5yKiMKnCKrIaFQDr5AZ7f2ejGGDf+8Tz
# OiK1AgBvOW3iTEEa/at8Z4+s1CmnEAkAi0cLjB72CJedU1LAswdOCWM2MDIZVo9j
# 0T74OkJLTjPd3WNEyw0rBXTyhlbYQsYt7ElT2l2TTlF5EmpVixGtj4ChNjWoKr9y
# TAqtadd2Ym5FNB792GzwNwa631BPCgBJmcRpFKXt0VEQq7UXVNYBiBRd+x4yvjqq
# 5aF7XC5nXCgjbCk7IXwmOphNuNDNiRq83Ejjnc7mxrJGMIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGXgwghl0AgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJch
# 0YZCu27020JUQZkUfmxFpMbiLxjq/qEQczNB6AMCMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQB1KCwyd1qO4hSINvub2kgNGaBCq6Oskkmq
# p4atlGjDdK6prKc8k8+ysnijyf5F0CzyyIb4L3jpMP5zwM5sb3kj4z2f2hKQCRwW
# gDh/8wP/JQuy5EHWmkyOwBbob6x0J00kqtou9g2V1mQ/5s13FSay3iybT9vtLRV+
# 6n3qzJADidcN2aS4sFZBTjKS93PudqnwoPZF4aPc2iPv3ZjncPQj57vbCyLy/3w+
# z1D7YpEJB5fiRbc7aQLvueo9vrC/ZttxQAFodJAjPpNoJVsgXk6xKO3rQuoHz9iI
# 4HCbTXWGfUG/5T1Lyi5R7goi8ZaM1q7KIuwE0WeOLNE+NaNveEVeoYIXADCCFvwG
# CisGAQQBgjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIMYXJLkVcNOxfgTlQ36oU1BWeAiJ/Ps6
# l8DIXoO22tTcAgZiFmxsYGAYEzIwMjIwMzAxMTI1MDEyLjM2NFowBIACAfSggdCk
# gc0wgcoxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNV
# BAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjNCQkQtRTMzOC1FOUExMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloIIRVzCCBwwwggT0oAMCAQICEzMAAAGd/onl+Xu7TMAA
# AQAAAZ0wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwHhcNMjExMjAyMTkwNTE5WhcNMjMwMjI4MTkwNTE5WjCByjELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046M0JCRC1F
# MzM4LUU5QTExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Uw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDgEWh60BxJFuR+mlFuFCtG
# 3mR2XHNCfPMTXcp06YewAtS1bbGzK7hDC1JRMethcmiKM/ebdCcG6v6k4lQyLlSa
# HmHkIUC5pNEtlutzpsVN+jo+Nbdyu9w0BMh4KzfduLdxbda1VztKDSXjE3eEl5Of
# +5hY3pHoJX9Nh/5r4tc4Nvqt9tvVcYeIxpchZ81AK3+UzpA+hcR6HS67XA8+cQUB
# 1fGyRoVh1sCu0+ofdVDcWOG/tcSKtJch+eRAVDe7IRm84fPsPTFz2dIJRJA/PUaZ
# R+3xW4Fd1ZbLNa/wMbq3vaYtKogaSZiiCyUxU7mwoA32iyTcGHC7hH8MgZWVOEBu
# 7CfNvMyrsR8Quvu3m91Dqsc5gZHMxvgeAO9LLiaaU+klYmFWQvLXpilS1iDXb/82
# +TjwGtxEnc8x/EvLkk7Ukj4uKZ6J8ynlgPhPRqejcoKlHsKgxWmD3wzEXW1a09d1
# L2Io004w01i31QAMB/GLhgmmMIE5Z4VI2Jlh9sX2nkyh5QOnYOznECk4za9cIdMK
# P+sde2nhvvcSdrGXQ8fWO/+N1mjT0SIkX41XZjm+QMGR03ta63pfsj3g3E5a1r0o
# 9aHgcuphW0lwrbBA/TGMo5zC8Z5WI+Rwpr0MAiDZGy5h2+uMx/2+/F4ZiyKauKXq
# d7rIl1seAYQYxKQ4SemB0QIDAQABo4IBNjCCATIwHQYDVR0OBBYEFNbfEI3hKujM
# nF4Rgdvay4rZG1XkMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8G
# A1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBs
# BggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# DQYJKoZIhvcNAQELBQADggIBAIbHcpxLt2h0LNJ334iCNZYsta2Eant9JUeipweb
# FIwQMij7SIQ83iJ4Y4OL5YwlppwvF516AhcHevYMScY6NAXSAGhp5xYtkEckeV6g
# Nbcp3C4I3yotWvDd9KQCh7LdIhpiYCde0SF4N5JRZUHXIMczvNhe8+dEuiCnS1sW
# iGPUFzNJfsAcNs1aBkHItaSxM0AVHgZfgK8R2ihVktirxwYG0T9o1h0BkRJ3PfuJ
# F+nOjt1+eFYYgq+bOLQs/SdgY4DbUVfrtLdEg2TbS+siZw4dqzM+tLdye5XGyJlK
# BX7aIs4xf1Hh1ymMX24YJlm8vyX+W4x8yytPmziNHtshxf7lKd1Pm7t+7UUzi8QB
# hby0vYrfrnoW1Kws+z34uoc2+D2VFxrH39xq/8KbeeBpuL5++CipoZQsd5QO5Ni8
# 1nBlwi/71JsZDEomso/k4JioyvVAM2818CgnsNJnMZZSxM5kyeRdYh9IbjGdPddP
# Vcv0kPKrNalPtRO4ih0GVkL/a4BfEBtXDeEUIsM4A00QehD+ESV3I0UbW+b4NTmb
# RcjnVFk5t6nuK/FoFQc5N4XueYAOw2mMDhAoFE+2xtTHk2ewd9xGkbFDl2b6u/Fb
# hsUb5+XoP0PdJ3FTNP6G/7Vr4sIOxar4PpY674aQCiMSywwtIWOoqRS/OP/rSjF9
# E/xfMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0B
# AQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAG
# A1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAw
# HhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOTh
# pkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xP
# x2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ
# 3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOt
# gFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYt
# cI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXA
# hjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0S
# idb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSC
# D/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEB
# c8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh
# 8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8Fdsa
# N8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkr
# BgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q
# /y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBR
# BgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAP
# BgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjE
# MFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEF
# BQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEB
# CwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnX
# wnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOw
# Bb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jf
# ZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ
# 5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+
# ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgs
# sU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6
# OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p
# /cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6
# TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784
# cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3
# AgEBMIH4oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYD
# VQQLEx1UaGFsZXMgVFNTIEVTTjozQkJELUUzMzgtRTlBMTElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAt+lDSRX9
# 2KFyij71Jn20CoSyyuCggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQUFAAIFAOXIKwEwIhgPMjAyMjAzMDExMzE3NTNaGA8y
# MDIyMDMwMjEzMTc1M1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5cgrAQIBADAK
# AgEAAgIjFgIB/zAHAgEAAgIR3zAKAgUA5cl8gQIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBBQUAA4GBAKOB4BHDdmci7occeRf7UYToKOKmOwo/br4tN1NGSaGmDLJDIa1Y
# UaC+JDB+5o1sErrEkAQ4r3Q87nkP3CVb8u2LSc4mhF1/DfKcOV6oTbg4j0p92A03
# wP5awUCGad6tR2g/ofVYdGhLgsMx7eqg2R73fGkAbP0OWCq9flVSJcpeMYIEDTCC
# BAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGd/onl
# +Xu7TMAAAQAAAZ0wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsq
# hkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgxqG6QOdGk3z46suHfxBAv8+S47Mj
# GpnU9bc+5cbDo58wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCD1HmOt4Iqg
# T4A0n4JblX/fzFLyEu4OBDOb+mpMlYdFoTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAABnf6J5fl7u0zAAAEAAAGdMCIEIEuCZiyCsnGj
# g4tgF1TG7TkoDtoXxfESwX/VfezRduKIMA0GCSqGSIb3DQEBCwUABIICAKhukKot
# 4hkpg1b341OiXkr8e+TxX21iAeK8SWY+7ukfmVUyIeNBA3mXplJRAx+nAL7EEpD2
# UCKcQrGrZL1dYVqxgM9+rltX7cCaIE+SFK3Y/DKFbKDt3sGQnsSO307DCyEZgB7T
# sEjfynpbKxOwtZAX0Y458JBRrfv8tg0WNlW1Uz0dezdf7XMdRkF20E3mH2580vsQ
# s+3TDlPTQ59EsdzdbgGjpReEY9npE0hODaijCH4pz0fgf0bts1/3Co/OLi1JHMp1
# Aaf/BHJVUKwACY+76mrhElHB7LHOjG+XZVKyEXNJg8rguQn7BCisPY3Rp5FQJ3Dn
# SY7AfOCaMr/FtWibAAoUqTWBG0Ebj1cF4AN8F+SChYsLCsqxem2y+U/lLRPmN0jG
# 1SEYL+8bkx36BpBpxKmfVz8BjTz4hKMtPnnl7K9sfEtbYT31JxAFuXXjNPxORGSt
# 0dmq3ANfDJs5b5fMaDQZGPmH6BXxwXNrFnERvR6bQAsQjTDgbLvc8oN59VkBnLYa
# 8KRoCubd/ty3I8u7fiWlUV/Ibv3emj1dPo3ULyX6sbe0yZIWmQLi1QLREb3nOIzP
# 0V8I1SOlLMDvOOj5Lmu2LjJ8FgbAabbqapwMO8ZiwqnS1uaUf5xnvn85pywJ+cNs
# qNZrsUg3kpMfXGAtIVmVaRxXPHP9eAv5jtlD
# SIG # End signature block
