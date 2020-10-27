
# Introduction
SQL LogScout allows you to collect diagnostic logs from your SQL Server system to help you and Microsoft technical support engineers (CSS) to resolve SQL Server technical incidents faster. It is a light, script-based, open-source tool that is version-agnostic. SQL LogScout discovers the SQL Server instances running locally on the system (including FCI and AG instances) and offers you a list to choose from. SQL LogScout can be executed without the need for Sysadmin privileges on the SQL Server instance (see [Permissions](#permissions)). 

# Download

Download the latest version of SQL LogScout at [http://aka.ms/get-sqllogscout](http://aka.ms/get-sqllogscout)

# Usage

1. Start the tool via SQL_LogScout.cmd when the issue is happening
1. Select which SQL instance you want to diagnose from a numbered list
1. Pick the [Scenario](#scenarios) from a menu list (based on the issue under investigation). Scenario names can optionally be passed as parameters to the main script (see [Parameters](#Examples))
1. Stop the collection when you are ready (by typing "stop" or "STOP")

# Examples

## A. Execute SQL LogScout (most common execution)

```bash
SQL_LogScout.cmd
```

## B. Execute using GeneralPerf scenario and debug level 0

```bash
SQL_LogScout.cmd 0 GeneralPerf
```

## C. Execute with Scenario, Debug level, Server, and Folder option parameters

```bash
SQL_LogScout.cmd 2 DetailedPerf "DbSrv\SQL2019" DeleteDefaultFolder
```

## Parameters

SQL_LogScout.cmd accepts several *optional* parameters:

1. **DebugLevel** - values are between 0 and 5 (default 0). Debug level provides detail on sequence of execution and variable values and is mostly for troubleshooting and debugging of SQL LogScout. In large majority of the cases you don't need to use anything other than 0, which provides the information you need.

1. **Scenario** - possible values are:
    - "Basic"
    - "GeneralPerf"
    - "DetailedPerf"
    - "Replication"
    - "AlwaysOn"
    - "Network"
    - "Memory"
    - "DumpMemory"
    - "WPR"
    - "MenuChoice" - this will present an interactive menu with Scenario choices. This is available in cases where multiple parameters must be used. *Note:* Not required when parameters are not specified for the command.

   For more information on each scenario see [Scenarios](#scenarios)

1. **ServerInstanceConStr** - specify the SQL Server to collect data from by using the following format "Server\Instance".

1. **DeleteExistingOrCreateNew** - possible values are "DeleteDefaultFolder" and "NewCustomFolder".  DeleteDefaultFolder will cause the default \output folder to be deleted and recreated. NewCustomFolder value will cause the creation of a new folder in the format *\output_ddMMyyhhmmss*. If a previous collection created an \output folder, then that folder will be preserved when NewCustomFolder option is used.

## Permissions

- **Windows**: Local Administrator permissions on the machine are required to collect most system-related logs

- **SQL Server**: VIEW SERVER STATE and ALTER ANY EVENT SESSION are the minimum required permission for collecting the SQL Server data.

## Scenarios

0. **Basic scenario** collects snapshot logs. It captures information:
   - Running drivers on the system
   - System information (systeminfo.exe)
   - Miscellaneous sql configuration (sp_configure, databases, etc)
   - Processes running on the system (Tasklist.exe)
   - Current active PowerPlan
   - Installed Windows Hotfixes
   - Running filter drivers
   - Event logs (system and application)

1. **GeneralPerf scenario** collects all the Basic scenario logs as well as some long-term, continuous logs (until SQL LogScout is stopped).
   - Basic scenario
   - Performance Monitor counters for SQL Server instance and general OS counters
   - Extended Event trace captures batch-level starting/completed events, errors and warnings, log growth/shrink, lock escalation and timeout, deadlock, login/logout
   - List of actively-running SQL traces and Xevents
   - Snapshots of SQL DMVs that track waits/blocking and high CPU queries
   - Query Data Store info (if that is active)
   - Tempdb contention info from SQL DMVs/system views
   - Linked Server metadata (SQL DMVs/system views)
   - Service Broker configuration information (SQL DMVs/system views)
2. **DetailedPerf scenario** collects the same info that the GeneralPerf scenario. The difference is in the Extended event trace
   - GeneralPerf scenario
   - Extended Event trace captures same as GeneralPerf. In addition in the same trace it captures statement level starting/completed events and actual XML query plans (for completed queries)

3. **Replication scenario** collects all the Basic scenario logs plus SQL Replication, Change Data Capture (CDC) and Change Tracking (CT) information
   - Basic Scenario
   - Replication, CDC, CT diagnostic info (SQL DMVs/system views)

4. **AlwaysOn scenario** collects all the Basic scenario logs as well as Always On configuration information from DMVs
   - Basic scenario
   - Always On diagnostic info (SQL DMVs/system views)
   - Always On [Data Movement Latency Xevent ](https://techcommunity.microsoft.com/t5/sql-server-support/troubleshooting-data-movement-latency-between-synchronous-commit/ba-p/319141)

5. **Network Trace** collects a Netsh-based network trace from the machine where SQL LogSout is running. The output is an .ETL file

6. **Memory** - collects
   - Basic scenario
   - Performance Monitor counters for SQL Server instance and general OS counters
   - Memory diagnostic info from SQL DMVs/system views

7. **Generate Memory Dumps** - allows to collect one or more memory dumps of SQL Server family of processes (SQL Server, SSAS, SSIS, SSRS, SQL Agent). If multiple dumps are selected, the number of dumps and the interval between them is customizable. Also the type of dump is offered as a choice (mini dump, mini with indirect memory, filtered (SQL Server), full.

8. **Windows Performance Recorder (WPR)** Here you can execute a sub-scenario depending on the knd of problem you want to address. These subscenarios are:
    - CPU - collects Windows performance data about CPU-related activities performed by processes and the OS 
    - Heap and Virtual memory - collects Windows performance data about memory allocations (virtual and heap memory)performed by processes and the OS 
    - Disk and File I/O - collects Windows performance data about I/O performance performed by processes and the OS 
    - Filter drivers - collects performance data about filter driver activity on the system (OS)


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

2020-08-27 11:58:57.738	INFO	Initializing log C:\temp\Test 2\output\internal\##SQLDIAG.LOG 
2020-08-27 11:58:54.930	INFO	SQL LogScout version: 1.1.0 
2020-08-27 11:58:55.031	INFO	The Present folder for this collection is C:\temp\Test 2 
2020-08-27 11:58:55.046	INFO	Output path: C:\temp\Test 2\output\ 
2020-08-27 11:58:55.046	INFO	The Error files path is C:\temp\Test 2\output\internal\ 
2020-08-27 11:58:55.046	INFO	 
2020-08-27 11:58:55.062	WARN	It appears that output folder C:\temp\Test 2\output\ has been used before. 
2020-08-27 11:58:55.062	WARN	DELETE the files it contains (Y/N)? 
2020-08-27 11:58:57.607	INFO	Console input: y 
2020-08-27 11:58:58.108	INFO	Discovered the following SQL Server instance(s)
 
2020-08-27 11:58:58.108	INFO	 
2020-08-27 11:58:58.108	INFO	ID	SQL Instance Name 
2020-08-27 11:58:58.108	INFO	--	---------------- 
2020-08-27 11:58:58.108	INFO	0 	 DbServerMachine\SQL2014 
2020-08-27 11:58:58.124	INFO	1 	 DbServerMachine 
2020-08-27 11:58:58.124	INFO	2 	 DbServerMachine\SQL2017 
2020-08-27 11:58:58.124	INFO	 
2020-08-27 11:58:58.124	WARN	Enter the ID of the SQL instance for which you want to collect diagnostic data. Then press Enter 
2020-08-27 11:59:01.549	INFO	Console input: 0 
2020-08-27 11:59:01.565	INFO	You selected instance 'DbServerMachine\SQL2014' to collect diagnostic data.  
2020-08-27 11:59:01.649	INFO	Confirmed that MYDOMAIN\Joseph has VIEW SERVER STATE on SQL Server Instance DbServerMachine\SQL2014 
2020-08-27 11:59:01.665	INFO	LogmanConfig.txt copied to  C:\temp\Test 2\output\internal\LogmanConfig.txt 
2020-08-27 11:59:01.734	INFO	 
2020-08-27 11:59:01.734	INFO	Initiating diagnostics collection...  
2020-08-27 11:59:01.734	INFO	Please select one of the following scenarios:
 
2020-08-27 11:59:01.734	INFO	 
2020-08-27 11:59:01.749	INFO	ID   Scenario 
2020-08-27 11:59:01.749	INFO	--   --------------- 
2020-08-27 11:59:01.749	INFO	0    Basic (no performance data) 
2020-08-27 11:59:01.749	INFO	1    General Performance (recommended for most cases) 
2020-08-27 11:59:01.749	INFO	2    Detailed Performance (statement level and query plans) 
2020-08-27 11:59:01.749	INFO	3    Replication 
2020-08-27 11:59:01.749	INFO	4    AlwaysON 
2020-08-27 11:59:01.749	INFO	5    Network Trace 
2020-08-27 11:59:01.749	INFO	6    Memory
2020-08-27 11:59:01.749	INFO	7    Generate Memory dumps
2020-08-27 11:59:01.749	INFO	8    Windows Performance Recorder (WPR)
2020-08-27 11:59:01.749	INFO	 
2020-08-27 11:59:01.765	WARN	Enter the Scenario ID for which you want to collect diagnostic data. Then press Enter 
2020-08-27 11:59:11.613	INFO	Console input: 1 
2020-08-27 11:59:11.629	INFO	Executing Collector: RunningDrivers 
2020-08-27 11:59:12.742	INFO	Executing Collector: SystemInfo_Summary 
2020-08-27 11:59:13.797	INFO	Executing Collector: MiscPssdiagInfo 
2020-08-27 11:59:15.819	INFO	Executing Collector: TaskListVerbose 
2020-08-27 11:59:15.850	INFO	Executing Collector: TaskListServices 
2020-08-27 11:59:15.872	INFO	Executing Collector: collecterrorlog 
2020-08-27 11:59:17.908	INFO	Executing Collector: PowerPlan 
2020-08-27 11:59:18.008	INFO	Executing Collector: WindowsHotfixes 
2020-08-27 11:59:18.309	INFO	Executing Collector: FLTMC_Filters 
2020-08-27 11:59:18.325	INFO	Executing Collector: FLTMC_Instances 
2020-08-27 11:59:20.347	INFO	Executing Collector: GetEventLogs 
2020-08-27 11:59:27.783	INFO	Executing Collector: Perfmon 
2020-08-27 11:59:28.824	INFO	Executing Collector: pssdiag_xevent 
2020-08-27 11:59:30.877	INFO	Executing Collector: pssdiag_xevent_general_target 
2020-08-27 11:59:30.893	INFO	Executing Collector: pssdiag_xevent_Start 
2020-08-27 11:59:30.908	INFO	Executing Collector: ExistingProfilerXeventTraces 
2020-08-27 11:59:32.937	INFO	Executing Collector: HighCPU_perfstats 
2020-08-27 11:59:32.953	INFO	Executing Collector: SQLServerPerfStats 
2020-08-27 11:59:34.990	INFO	Executing Collector: SQLServerPerfStatsSnapshotStartup 
2020-08-27 11:59:35.022	INFO	Executing Collector: Query Store 
2020-08-27 11:59:37.032	INFO	Executing Collector: TempDBAnalysis 
2020-08-27 11:59:37.047	INFO	Executing Collector: linked_server_config 
2020-08-27 11:59:37.085	INFO	Executing Collector: SSB_pssdiag 
2020-08-27 11:59:37.116	INFO	Diagnostic collection started. 
2020-08-27 11:59:37.116	INFO	 
2020-08-27 11:59:37.116	WARN	Please type 'STOP' or 'stop' to terminate the diagnostics collection when you finished capturing the issue 
2020-08-27 11:59:53.639	INFO	Console input: stop 
2020-08-27 11:59:53.654	INFO	Shutting down the collector 
2020-08-27 11:59:53.654	INFO	Stopping Collector: SQLServerPerfStatsSnapshotShutdown 
2020-08-27 11:59:53.670	INFO	Stopping Collector: xevents_stop 
2020-08-27 11:59:53.686	INFO	Stopping Collector: PerfmonStop 
2020-08-27 11:59:56.714	INFO	Running: killpssdiagSessions 
2020-08-27 11:59:56.720	INFO	Waiting 5 seconds to ensure files are written to and closed by any program including anti-virus... 
2020-08-27 12:00:01.731	INFO	Ending data collection 
```

# Output folders

**Output folder**: All the log files are collected in the \output folder. These include perfmon log (.BLG), event logs, system information, extended event (.XEL), etc. 

**Internal folder**: The \internal folder stores error log files for each individual data collector. Most of those files are empty (zero bytes) if the specific collector did not generate any errors or console output. If those files are not empty, they contain information about whether a particular data-collector failed or produced some result (not necessarily failure). The \internal folder also stores the main activity log file for SQL LogScout (##SQLDIAG.LOG).  If the main script produces some errors in the console, those are redirected to a file ##STDERR.LOG which is also moved to \internal folder at the end of execution if the file is non-zero in size.

# Logging
SQL LogScout logs the flow of activity on the console as well as in a log file - ##SQLDIAG.LOG. The design goal is to match what the user sees on the screen with what is written in the log file so that a post-mortem analysis can be performed. If SQL LogScout main script generates any runtime errors that were not caught, those will be written to the ##STDERR.LOG file and the contents of that file is displayed in the console after the main script completes execution.


# Targeted SQL instances

Data is collected from the SQL instance you selected locally on the machine where SQL LogScout runs. SQL LogScout does not capture data on remote machines. You are prompted to pick a SQL Server instance you want to target. The SQL Server-specific data collection comes from a single instance only. 

# Test Suite

The test suite is intended for confirm existence of output logs from SQL LogScout (smoke tests) currently. The set of tests will grow over time. To run the test, simply execute the RunTests.bat under the \TestingInfrastructure folder in command prompt.

## Example:

## Execute SQL LogScout Tests
```bash
cd TestingInfrastructure 
RunTests.bat
```

## Sample Output

```
TEST: ExecutingCollectors Validation
Status: SUCCESS
Summary: You executed "General Performance" Scenario. Expected Collector count of 23 matches current file count is : 23

************************************************************************************************

TEST: FileCount Validation
Status: SUCCESS
Summary: You executed "General Performance" Scenario. Expected File count of 25 matches current file count is : 25

************************************************************************************************

Testing has been completed , reports are at: C:\temp\Test 2\TestingInfrastructure\output\

```
