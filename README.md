
# Introduction
SQL LogScout allows you to collect diagnostic logs from your SQL Server system to help you and Microsoft technical support engineers (CSS) to resolve SQL Server technical incidents faster. It is a light, script-based, open-source tool that is version-agnostic. SQL LogScout discovers the SQL Server instances running locally on the system (including FCI and AG instances) and offers you a list to choose from. 

# Usage

1. Start the tool via SQL_LogScout.cmd when the issue is happening
1. Select which SQL instance you want to diagnose from a numbered list
1. Pick the Scenario from a menu list (based on the issue under investigation)
1. Stop the collection when you are ready (by typing "stop")

## Parameters
SQL_LogScout.cmd accepts two optional parameters:
1. **DebugLevel** - values are between 0 and 5 (default 0). Debug level provides detail on what is executed on the system and is mostly for troubleshooting and debugging SQL LogScout
1. **Scenario** - possible values are "Basic", "GeneralPerf", "DetailedPerf", "AlwaysOn","Replication" (no default). For more information on each scenario see [Scenarios](#scenarios)

## Scenarios
1. **Basic scenario** collects snapshot logs. It captures information:
   - Running drivers on the system
   - System information (systeminfo.exe)
   - Miscelaneous sql configuration (sp_configure, databases, etc)
   - Processes running on the system (Tasklist.exe)
   - Current active PowerPlan
   - Installed Windows Hotfixes
   - Running filter drivers
   - Event logs (system and application)
1. **GeneralPerf scenario** collects all the Basic scenario logs as well as some long-term, continuos logs (until SQL LogScout is stopped).
   - Basic scenario
   - Performance Monitor counters for SQL Server instance and general OS counters
   - Extended Event trace captures batch-level starting/completed events, errors and warnings, log growth/shrink, lock escalation and timeout, deadlock, login/logout
   - List of actively-running SQL traces and Xevents
   - Snapshots of SQL DMVs that track waits/blocking and high CPU queries
   - Query Data Store info (if that is active)
   - Tempdb contention info from SQL DMVs/system views
   - Linked Server metadata (SQL DMVs/system views)
   - Service Broker configuration information (SQL DMVs/system views)
1. **DetailedPerf scenario** collects the same info that the GeneralPerf scenario. The difference is in the Extended event trace
   - GeneralPerf scenario
   - Extended Event trace captures same as GeneralPerf. In addition in the same trace it captures statement level starting/completed events and actual XML query plans (for completed queries)
1. **AlwaysOn scenario** collects all the Basic scenario logs as well as Always On configuration information from DMVs
   - Basic scenario
   - Always On diagnostic info (SQL DMVs/system views)
1. **Replication scenario** collects all the Basic scenario logs plus SQL Replication, Change Data Capture and Change Tracking information
   - Basic Scenario
   - Replication, CDC, CT diagnostic info (SQL DMVs/system views)


# Sample output

```bash
     ======================================================================================================
              #####   #####  #          #                      #####
             #     # #     # #          #        ####   ####  #     #  ####   ####  #    # #####
             #       #     # #          #       #    # #    # #       #    # #    # #    #   #
              #####  #     # #          #       #    # #       #####  #      #    # #    #   #
                   # #   # # #          #       #    # #  ###       # #      #    # #    #   #
             #     # #    #  #          #       #    # #    # #     # #    # #    # #    #   #
              #####   #### # #######    #######  ####   ####   #####   ####   ####   ####    #
     ======================================================================================================

2020-07-16 09:51:40.363 INFO    The Present folder for this collection is C:\temp\pssdiag\Test 2
2020-07-16 09:51:40.425 INFO    Output path: C:\temp\pssdiag\Test 2\output\
2020-07-16 09:51:40.432 INFO    The Error files path is C:\temp\pssdiag\Test 2\output\internal\
2020-07-16 09:51:40.447 INFO    Initializing log C:\temp\pssdiag\Test 2\output\internal\##SQLDIAG.LOG
2020-07-16 09:51:40.748 INFO    Discovered the following SQL Server instance(s)

2020-07-16 09:51:40.748 INFO
2020-07-16 09:51:40.764 INFO    ID      SQL InstanceName
2020-07-16 09:51:40.766 INFO    --      ----------------
2020-07-16 09:51:40.769 INFO    0        DbServerMachine\SQL2014
2020-07-16 09:51:40.773 INFO    1        DbServerMachine
2020-07-16 09:51:40.775 INFO    2        DbServerMachine\SQL2017
2020-07-16 09:51:40.777 INFO
2020-07-16 09:51:40.780 WARN    Please, enter the ID from list above of the SQL instance for which you want to collect diagnostic data. Then press Enter
Enter the ID from list above>: 1
2020-07-16 09:51:47.502 INFO    Console input: 1
2020-07-16 09:51:47.502 INFO    You selected instance 'DbServerMachine' to collect diagnostic data.
2020-07-16 09:51:47.633 INFO    Confirmed that NADOMAIN\JOSEPH has VIEW SERVER STATE on SQL Server Instance DbServerMachine
2020-07-16 09:51:47.633 INFO    The \Error folder for this collection is C:\temp\pssdiag\Test 2\output\internal\
2020-07-16 09:51:47.656 INFO    LogmanConfig.txt copied to  C:\temp\pssdiag\Test 2\output\internal\LogmanConfig.txt
2020-07-16 09:51:47.656 INFO    The \Error folder for this collection is C:\temp\pssdiag\Test 2\output\internal\
2020-07-16 09:51:47.735 INFO
2020-07-16 09:51:47.735 INFO    Initiating diagnostics collection...
2020-07-16 09:51:47.755 INFO    Executing Collector: MSDiagProcs
2020-07-16 09:51:47.790 INFO    Executing Collector: pssdiag_xevent
2020-07-16 09:51:50.816 INFO    Executing Collector: pssdiag_xevent_target
2020-07-16 09:51:50.831 INFO    Executing Collector: pssdiag_xevent_Start
2020-07-16 09:51:50.862 INFO    Executing Collector: AlwaysOnDiagScript
2020-07-16 09:51:51.900 INFO    Executing Collector: SystemInfo_Summary
2020-07-16 09:51:51.922 INFO    Executing Collector: MiscPssdiagInfo
2020-07-16 09:51:51.938 INFO    Executing Collector: collecterrorlog
2020-07-16 09:51:53.958 INFO    Executing Collector: TaskListVerbose
2020-07-16 09:51:53.974 INFO    Executing Collector: TaskListServices
2020-07-16 09:51:55.994 INFO    Executing Collector: ExistingProfilerXeventTraces
2020-07-16 09:51:59.025 INFO    Executing Collector: HighCPU_perfstats
2020-07-16 09:52:00.045 INFO    Executing Collector: SQLServerPerfStats
2020-07-16 09:52:00.056 INFO    Executing Collector: SQLServerPerfStatsSnapshotStartup
2020-07-16 09:52:02.075 INFO    Executing Collector: Perfmon
2020-07-16 09:52:03.115 INFO    Executing Collector: SSB_pssdiag
2020-07-16 09:52:03.122 INFO    Executing Collector: TempDBAnalysis
2020-07-16 09:52:03.137 INFO    Executing Collector: linked_server_config
2020-07-16 09:52:05.170 INFO    Executing Collector: Query Store
2020-07-16 09:52:05.185 INFO    Executing Collector: Repl_Metadata_Collector
2020-07-16 09:52:05.201 INFO    Executing Collector: ChangeDataCapture
2020-07-16 09:52:05.223 INFO    Executing Collector: Change_Tracking
2020-07-16 09:52:07.269 INFO    Executing Collector: FLTMC_Filters
2020-07-16 09:52:07.284 INFO    Executing Collector: FLTMC_Instances
2020-07-16 09:52:07.300 INFO    Executing Collector: PowerPlan
2020-07-16 09:52:07.416 INFO    Executing Collector: WindowsHotfixes
2020-07-16 09:52:07.719 INFO    Executing Collector: GetEventLogs
2020-07-16 09:52:14.387 INFO    Executing Collector: RunningDrivers
2020-07-16 09:52:15.220 INFO    Diagnostic collection started.
2020-07-16 09:52:15.220 INFO
2020-07-16 09:52:15.236 WARN    Please type 'STOP' or 'stop' to terminate the diagnostics collection when you finished capturing the issue
>: stop
2020-07-16 09:54:41.146 INFO    Console input: stop
2020-07-16 09:54:41.146 WARN    Shutting down the collector
2020-07-16 09:54:41.177 INFO    Stopping Collector: SQLServerPerfStatsSnapshotShutdown
2020-07-16 09:54:41.183 INFO    Stopping Collector: xevents_stop
2020-07-16 09:54:41.199 INFO    Stopping Collector: PerfmonStop
2020-07-16 09:54:41.230 INFO    Stopping Collector: RestoreTraceFlagOrigValues
2020-07-16 09:54:44.246 INFO    Running: killpssdiagSessions
2020-07-16 09:54:44.262 INFO    Waiting 5 seconds to ensure files are written to and closed by any program including anti-virus...
2020-07-16 09:54:49.270 INFO    Ending data collection
```

# Output folders

**Output folder**: All the log files are collected in the \output folder. These include perfmon log (.BLG), event logs, system information, extended event (.XEL), etc. 

**Internal folder**: The \internal folder stores error log files as well as the main activity log file for SQL LogScout (##SQLDIAG.LOG). If those files are not empty, they contain information about whether a particular data-collector failed or produced some result (not necessarily failure). If the main script produces some errors in the console, those are redirected to a file ##STDERR.LOG and the contents of that file is displayed in the console after the main script completes execution.

# Targeted SQL instances

Data is collected from the SQL instance you selected locally on the machine where SQL LogScout runs. SQL LogScout does not capture data on remote machines. You are prompted to pick a SQL Server instance you want to target. The SQL Server-specific data collection comes from a single instance only. 