[http://aka.ms/sqllogscout](http://aka.ms/sqllogscout) gets you here



# Introduction

SQL LogScout allows you to collect diagnostic logs from your SQL Server system to help you and Microsoft technical support engineers (CSS) to resolve SQL Server technical incidents faster. It is a light, script-based, open-source tool that is version-agnostic. SQL LogScout discovers the SQL Server instances running locally on the system (including FCI and AG instances) and offers you a list to choose from. SQL LogScout can be executed without the need for Sysadmin privileges on the SQL Server instance (see [Permissions](#permissions)).

# Download

Download the latest version of SQL LogScout at [http://aka.ms/get-sqllogscout](http://aka.ms/get-sqllogscout). 

# Usage

1. Place the downloaded files on a disk volume where diagnostic logs will be captured. An \output* sub-folder will be created automatically by the tool when you start it
1. Open a Command Prompt and change to the folder where SQL LogScout files reside
1. Start the tool via `SQL_LogScout.cmd` before or while the issue is occurring
1. Select which SQL instance you want to diagnose from a numbered list
1. Pick one or more [Scenarios](#scenarios) from a menu list (based on the issue under investigation). Scenario names can optionally be passed as parameters to the main script (see [Parameters](#Parameters))
1. Stop the collection when you are ready (by typing "stop" or "STOP")

## Automating data collection

SQL LogScout can be executed with multiple switches allowing for full automation and no interaction with menus. You can:

- Provide the SQL Server instance name
- Schedule start and stop time of data collection
- Use Quiet mode to accept all prompts automatically
- Choose the destination folder (delete default or create a new one)

See [Parameters](#parameters) and [Example E](#e-execute-sql-logscout-with-multiple-scenarios-and-in-quiet-mode) for detailed information.

## Interrupting data collection/execution

If the need arises, you can interrupt the execution of SQL LogScout by pressing **CTRL+C** at any time. In some cases you may have to be patient before the CTRL+C is reflected (a few seconds) depending on what is being executed at the time. But in most cases the process is immediate. It is not recommended to close the Command Prompt window where SQL LogScout is running because this may leave a data collector running on your system.

# Examples

## A. Execute SQL LogScout (most common execution)

This is the most common method to execute SQL LogScout which allows you to pick your choices from a menu of options

```bash
SQL_LogScout.cmd
```

## B. Execute SQL LogScout using a specific scenario and debug level

This command starts the diagnostic collection with no debug logging and specifies the GeneralPerf scenario.

```bash
SQL_LogScout.cmd 0 GeneralPerf
```

## C. Execute SQL LogScout by specifying folder creation option

Execute SQL LogScout using the DetailedPerf Scenario, DebugLevel 2, specifies the Server name, use the present directory and folder option to delete the default \output folder if present

```bash
SQL_LogScout.cmd 2 DetailedPerf "DbSrv\SQL2019" "UsePresentDir" "DeleteDefaultFolder"
```

## D. Execute SQL LogScout with start and stop times

The following example uses debuglevel 5, collects the AlwaysOn scenario against the "DbSrv" default instance, prompts user to choose a custom path and a new custom subfolder, and sets the stop time to some time in the future, while setting the start time in the past to ensure the collectors start without delay.  

```bash
SQL_LogScout.cmd 5 AlwaysOn "DbSrv" PromptForCustomDir NewCustomFolder "2000-01-01 19:26:00" "2020-10-29 13:55:00"
```

**Note:** All parameters are required if you need to specify the last parameter. For example, if you need to specify stop time, the 5 prior parameters have to be passed.

## E. Execute SQL LogScout with multiple scenarios and in Quiet mode

The example uses debuglevel 5, collects data for GeneralPerf, AlwaysOn, and BackupRestore scenarios against the "DbSrv" default instance, re-uses the default output folder but creates it in the D:\Log custom path, and sets the stop time to some time in the future, while setting the start time in the past to ensure the collectors start without delay.  It also automatically accepts the prompts by using Quiet mode and helps a full automation with no interaction.

```bash
SQL_LogScout.cmd 5 GeneralPerf+AlwaysOn+BackupRestore DbSrv "d:\log" DeleteDefaultFolder "01-01-2000" "04-01-2021 17:00" Quiet
```

**Note:**  Selecting Quiet mode implicitly selects "Y" to all the screens that requires your agreement to proceed. 

# Parameters

SQL_LogScout.cmd accepts several optional parameters. Because this is a batch file, you have to specify the parameters in the sequence listed below. Also, you cannot omit parameters. For example if you would like to specify the server instance (3rd parameter), you must specify DebugLevel and Scenario parameters before it.

1. **DebugLevel** - values are between 0 and 5 (default 0). Debug level provides detail on sequence of execution and variable values and is mostly for troubleshooting and debugging of SQL LogScout. In large majority of the cases you don't need to use anything other than 0, which provides the information you need.

1. **Scenario** - possible values are:
    - "Basic"
    - "GeneralPerf"
    - "DetailedPerf"
    - "Replication"
    - "AlwaysOn"
    - "NetworkTrace"
    - "Memory"
    - "DumpMemory"
    - "WPR"
    - "Setup"
    - "BackupRestore"
    - "MenuChoice" - this directs SQL LogScout to present an interactive menu with Scenario choices. The option is available in cases where multiple parameters must be used. 

   You can select one or more scenarios. To combine multiple scenarios use the *plus sign* (+). For example:

   `GeneralPerf+Memory+Setup`

   *Note:* Not required when parameters are not specified for the command.

   For more information on each scenario see [Scenarios](#Scenarios)

1. **ServerInstanceConStr** - specify the SQL Server to collect data from by using the following format "Server\Instance".

1. **CustomOutputPath** - specify a custom volume and directory where the data can be collected. An *\output* folder or *\output_ddMMyyhhmmss* would still be created under this custom path. Possible values are:
    - "PromptForCustomDir" - will cause the user to be prompted whether to specify a custom path
    - "UsePresentDir"  - will use the present directory wher SQL LogScout is copied (no custom path)
    - An existing path (e.g. D:\logs) - will use the specified path for data collection.  **Note:** Do not use a trailing backslash at the end. For example "D:\logs\\" will lead to an error.

1. **DeleteExistingOrCreateNew** - possible values are: 
    - "DeleteDefaultFolder" - will cause the default \output folder to be deleted and recreated
    - "NewCustomFolder"  - will cause the creation of a new folder in the format *\output_ddMMyyhhmmss*. If a previous collection created an \output folder, then that folder will be preserved when NewCustomFolder option is used.

1. **DiagStartTime** - specify the time when you want SQL LogScout to start data collection in the future. If the time is older than or equal to current time, data collection starts immediately. Format to use is "yyyy-MM-dd hh:mm:ss" (in quotes). For example: "2020-10-27 19:26:00".  

1. **DiagStopTime** - specify the time when you want SQL LogScout to stop data collection in the future. If the time is older than or equal to current time, data collection stops immediately. Format to use is "yyyy-MM-dd hh:mm:ss" (in quotes). For example: "2020-10-27 19:26:00".

1. **InteractivePrompts** - possible values are:
     - Quiet - suppresses possible prompts for data input. Selecting Quiet mode implicitly selects "Y" to all the screens that requires an agreement to proceed.
     - Noisy - (default) shows prompts requesting user input where necessary

# Permissions

- **Windows**: Local Administrator permissions on the machine are required to collect most system-related logs

- **SQL Server**: VIEW SERVER STATE and ALTER ANY EVENT SESSION are the minimum required permission for collecting the SQL Server data.

# Scenarios

0. **Basic scenario** collects snapshot logs. It captures information:
   - Running drivers on the system
   - System information (systeminfo.exe)
   - Miscellaneous sql configuration (sp_configure, databases, etc)
   - Processes running on the system (Tasklist.exe)
   - Current active PowerPlan
   - Installed Windows Hotfixes
   - Running filter drivers
   - Event logs (system and application)
   - SQL Errorlogs
   - SQL Agent logs
   - Polybase logs
   - Windows Cluster logs
   - [AlwaysOn_health*.xel](https://docs.microsoft.com/sql/database-engine/availability-groups/windows/always-on-extended-events#BKMK_alwayson_health)
   - [MSSQLSERVER_SQLDIAG*.xel](https://docs.microsoft.com/sql/database-engine/availability-groups/windows/always-on-health-diagnostics-log)
   - [SQL VSS Writer Log (SQL Server 2019 and later)](https://docs.microsoft.com/sql/relational-databases/backup-restore/sql-server-vss-writer-logging)

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
   - Performance Monitor counters for SQL Server instance and general OS counters

5. **Network Trace scenario** collects a Netsh-based network trace from the machine where SQL LogSout is running. The output is an .ETL file

6. **Memory** - collects
   - Basic scenario
   - Performance Monitor counters for SQL Server instance and general OS counters
   - Memory diagnostic info from SQL DMVs/system views

7. **Generate Memory Dumps scenario** - allows to collect one or more memory dumps of SQL Server family of processes (SQL Server, SSAS, SSIS, SSRS, SQL Agent). If multiple dumps are selected, the number of dumps and the interval between them is customizable. Also the type of dump is offered as a choice (mini dump, mini with indirect memory, filtered (SQL Server), full.

8. **Windows Performance Recorder (WPR) scenario** allows to collect a [Windows Performance Recorder](https://docs.microsoft.com/windows-hardware/test/wpt/introduction-to-wpr) trace. Here you can execute a sub-scenario depending on the knd of problem you want to address. These subscenarios are:
    - CPU - collects Windows performance data about CPU-related activities performed by processes and the OS
    - Heap and Virtual memory - collects Windows performance data about memory allocations (virtual and heap memory)performed by processes and the OS
    - Disk and File I/O - collects Windows performance data about I/O performance performed by processes and the OS
    - Filter drivers - collects performance data about filter driver activity on the system (OS)

   **WARNING**: WPR traces collect system-wide diagnostic data. Thus a large set of trace data may be collected and it may take several minutes to stop the trace. Therefore the WPR trace is limited to 15 seconds of data collection.

9. **Setup scenario** - collects all the Basic scenario logs and all SQL Setup logs from the \Setup Bootstrap\ folders on the system. This allows analysis of setup or installation issues of SQL Server components.

10. **Backup and Restore scenario** - collects the Basic scenario logs and various logs related to backup and restore activities in SQL Server. These logs include:

    - Backup and restore-related Xevent (backup_restore_progress_trace  and batch start end xevents)
    - Enables backup and restore related TraceFlags to produce information in the Errorlog
    - Performance Monitor counters for SQL Server instance and general OS counters
    - SQL VSS Writer Log (on SQL Server 2019 and later)
    - VSS Admin (OS) logs for VSS backup-related scenarios
 
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

Launching SQL LogScout...
Copyright (c) 2021 Microsoft Corporation. All rights reserved.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.

2021-04-01 12:00:16.337	INFO	Initializing log C:\temp\log scout\Test 2\output\internal\##SQLLOGSCOUT.LOG 
2021-04-01 12:00:10.970	INFO	SQL LogScout version: 3.3.3 
2021-04-01 12:00:11.081	INFO	The Present folder for this collection is C:\temp\log scout\Test 2 
2021-04-01 12:00:11.086	INFO	Output path: C:\temp\log scout\Test 2\output\ 
2021-04-01 12:00:11.090	INFO	The Error files path is C:\temp\log scout\Test 2\output\internal\ 
2021-04-01 12:00:11.109	INFO	 
2021-04-01 12:00:11.113	WARN	It appears that output folder 'C:\temp\log scout\Test 2\output\' has been used before. 
2021-04-01 12:00:11.118	WARN	You can choose to: 
2021-04-01 12:00:11.122	WARN	 - Delete (D) the \output folder contents and recreate it 
2021-04-01 12:00:11.124	WARN	 - Create a new (N) folder using \Output_ddMMyyhhmmss format. 
2021-04-01 12:00:11.127	WARN	   You can delete the new folder manually in the future 
2021-04-01 12:00:16.141	INFO	Output folder Console input: d 
2021-04-01 12:00:16.311	WARN	Deleted C:\temp\log scout\Test 2\output\ and its contents 
2021-04-01 12:00:16.415	INFO	 
2021-04-01 12:00:16.419	INFO	Initiating diagnostics collection...  
2021-04-01 12:00:16.427	INFO	Please select one of the following scenarios:
 
2021-04-01 12:00:16.432	INFO	 
2021-04-01 12:00:16.435	INFO	ID	 Scenario 
2021-04-01 12:00:16.437	INFO	--	 --------------- 
2021-04-01 12:00:16.443	INFO	0 	 Basic (no performance data) 
2021-04-01 12:00:16.449	INFO	1 	 General Performance (recommended for most cases) 
2021-04-01 12:00:16.452	INFO	2 	 Detailed Performance (statement level and query plans) 
2021-04-01 12:00:16.454	INFO	3 	 Replication 
2021-04-01 12:00:16.456	INFO	4 	 AlwaysON 
2021-04-01 12:00:16.459	INFO	5 	 Network Trace 
2021-04-01 12:00:16.463	INFO	6 	 Memory 
2021-04-01 12:00:16.465	INFO	7 	 Generate Memory dumps 
2021-04-01 12:00:16.467	INFO	8 	 Windows Performance Recorder (WPR) 
2021-04-01 12:00:16.469	INFO	9 	 Setup 
2021-04-01 12:00:16.472	INFO	10 	 Backup and Restore 
2021-04-01 12:00:16.477	INFO	 
2021-04-01 12:00:16.481	WARN	Type one or more Scenario IDs (separated by '+') for which you want to collect diagnostic data. Then press Enter 
2021-04-01 12:00:35.449	INFO	Scenario Console input: 1+4+10 
2021-04-01 12:00:35.527	INFO	The scenarios selected are: 'GeneralPerf Basic AlwaysOn BackupRestore' 
2021-04-01 12:00:35.950	INFO	Discovered the following SQL Server instance(s)
 
2021-04-01 12:00:35.953	INFO	 
2021-04-01 12:00:35.957	INFO	ID	SQL Instance Name 
2021-04-01 12:00:35.959	INFO	--	---------------- 
2021-04-01 12:00:35.964	INFO	0 	 DbServerMachine 
2021-04-01 12:00:35.966	INFO	1 	 DbServerMachine\SQL2014 
2021-04-01 12:00:35.969	INFO	2 	 DbServerMachine\SQL2017 
2021-04-01 12:00:35.972	INFO	 
2021-04-01 12:00:35.977	WARN	Enter the ID of the SQL instance for which you want to collect diagnostic data. Then press Enter 
2021-04-01 12:00:40.456	INFO	SQL Instance Console input: 1 
2021-04-01 12:00:40.466	INFO	You selected instance 'rabotenlaptop\SQL2014' to collect diagnostic data.  
2021-04-01 12:00:40.585	INFO	Confirmed that MYDOMAIN\Joseph has VIEW SERVER STATE on SQL Server Instance 'DbServerMachine\SQL2014' 
2021-04-01 12:00:40.589	INFO	Confirmed that MYDOMAIN\Joseph has ALTER ANY EVENT SESSION on SQL Server Instance 'DbServerMachine\SQL2014' 
2021-04-01 12:00:41.120	WARN	At least one of the selected 'GeneralPerf Basic AlwaysOn BackupRestore' scenarios collects Xevent traces 
2021-04-01 12:00:41.123	WARN	The service account 'NT Service\MSSQL$SQL2014' for SQL Server instance 'DbServerMachine\SQL2014' must have write/modify permissions on the 'C:\temp\log scout\Test 2\output\' folder 
2021-04-01 12:00:41.127	WARN	The easiest way to validate write permissions on the folder is to test-run SQL LogScout for 1-2 minutes and ensure an *.XEL file exists that you can open and read in SSMS 
2021-04-01 12:00:43.812	INFO	Access verification Console input: y 
2021-04-01 12:00:43.854	INFO	LogmanConfig.txt copied to  C:\temp\log scout\Test 2\output\internal\LogmanConfig.txt 
2021-04-01 12:00:43.921	INFO	Basic collectors will execute on shutdown 
2021-04-01 12:00:43.929	INFO	Collecting logs for 'GeneralPerf' scenario 
2021-04-01 12:00:43.957	INFO	Executing Collector: Perfmon 
2021-04-01 12:00:45.046	INFO	Executing Collector: xevent_general 
2021-04-01 12:00:47.110	INFO	Executing Collector: xevent_general_target 
2021-04-01 12:00:47.132	INFO	Executing Collector: xevent_general_Start 
2021-04-01 12:00:47.179	INFO	Executing Collector: ExistingProfilerXeventTraces 
2021-04-01 12:00:49.225	INFO	Executing Collector: HighCPU_perfstats 
2021-04-01 12:00:49.259	INFO	Executing Collector: SQLServerPerfStats 
2021-04-01 12:00:51.313	INFO	Executing Collector: SQLServerPerfStatsSnapshotStartup 
2021-04-01 12:00:51.348	INFO	Executing Collector: Query Store 
2021-04-01 12:00:53.397	INFO	Executing Collector: TempDBAnalysis 
2021-04-01 12:00:53.433	INFO	Executing Collector: linked_server_config 
2021-04-01 12:00:53.475	INFO	Executing Collector: SSB_diag 
2021-04-01 12:00:53.522	INFO	Collecting logs for 'AlwaysOn' scenario 
2021-04-01 12:00:53.534	INFO	Executing Collector: AlwaysOnDiagScript 
2021-04-01 12:00:53.591	INFO	Executing Collector: xevent_AlwaysOn_Data_Movement 
2021-04-01 12:00:55.631	INFO	Executing Collector: AlwaysOn_Data_Movement_target 
2021-04-01 12:00:55.655	INFO	Executing Collector: AlwaysOn_Data_Movement_Start 
2021-04-01 12:00:55.699	INFO	Executing Collector: AlwaysOnHealthXevent 
2021-04-01 12:00:55.738	INFO	Collecting logs for 'BackupRestore' scenario 
2021-04-01 12:00:55.756	INFO	Executing Collector: EnableTraceFlag 
2021-04-01 12:00:55.800	INFO	Executing Collector: VSSAdmin_Providers 
2021-04-01 12:00:55.836	INFO	Executing Collector: VSSAdmin_Shadows 
2021-04-01 12:00:56.896	INFO	Executing Collector: VSSAdmin_Shadowstorage 
2021-04-01 12:00:56.931	INFO	Executing Collector: VSSAdmin_Writers 
2021-04-01 12:00:56.974	WARN	Please type 'STOP' to terminate the diagnostics collection when you finished capturing the issue 
2021-04-01 12:01:06.448	INFO	StopCollection Console input: stop 
2021-04-01 12:01:06.453	INFO	Shutting down the collector 
2021-04-01 12:01:06.463	INFO	Executing shutdown command: SQLServerPerfStatsSnapshotShutdown 
2021-04-01 12:01:06.484	INFO	Executing shutdown command: xevents_stop 
2021-04-01 12:01:06.506	INFO	Executing shutdown command: xevents_alwayson_data_movement_stop 
2021-04-01 12:01:06.535	INFO	Executing Disabling traceflag command: Disable Backup Restore Trace Flag 
2021-04-01 12:01:06.565	INFO	Executing shutdown command: PerfmonStop 
2021-04-01 12:01:09.622	INFO	Executing shutdown command: KillActiveLogscoutSessions 
2021-04-01 12:01:10.664	INFO	Collecting logs for 'Basic' scenario 
2021-04-01 12:01:10.681	INFO	Executing Collector: RunningDrivers 
2021-04-01 12:01:11.651	INFO	Executing Collector: SystemInfo_Summary 
2021-04-01 12:01:12.700	INFO	Executing Collector: MiscPssdiagInfo 
2021-04-01 12:01:14.751	INFO	Executing Collector: TaskListVerbose 
2021-04-01 12:01:14.790	INFO	Executing Collector: TaskListServices 
2021-04-01 12:01:14.831	INFO	Executing Collector: SQLErrorLogs_AgentLogs_SystemHealth_MemDumps_FciXel 
2021-04-01 12:01:15.253	INFO	Executing Collector: PolybaseLogs 
2021-04-01 12:01:17.279	INFO	Executing Collector: PowerPlan 
2021-04-01 12:01:17.383	INFO	Executing Collector: WindowsHotfixes 
2021-04-01 12:01:17.808	INFO	Executing Collector: FLTMC_Filters 
2021-04-01 12:01:17.841	INFO	Executing Collector: FLTMC_Instances 
2021-04-01 12:01:19.899	INFO	Executing Collector: GetEventLogs 
2021-04-01 12:01:32.991	INFO	Waiting 3 seconds to ensure files are written to and closed by any program including anti-virus... 
2021-04-01 12:01:36.602	INFO	Ending data collection 
Checking for console execution errors logged into .\##STDERR.LOG...
Removed .\##STDERR.LOG which was 0 bytes

```

# Output folders

**Output folder**: All the diagnostic log files are collected in the \output (or \output_ddMMyyhhmmss) folder. These include perfmon log (.BLG), event logs, system information, extended event (.XEL), etc. 

**Internal folder**: The \output\internal folder stores error log files for each individual data collector. Most of those files are empty (zero bytes) if the specific collector did not generate any errors or console output. If those files are not empty, they contain information about whether a particular data-collector failed or produced some result (not necessarily failure). The \internal folder also stores the main activity log file for SQL LogScout (##SQLLOGSCOUT.LOG).  If the main script produces some errors in the console, those are redirected to a file ##STDERR.LOG which is also moved to \internal folder at the end of execution if the file is non-zero in size.

# Logging

SQL LogScout logs the flow of activity on the console as well as in a log file - ##SQLLOGSCOUT.LOG. The design goal is to match what the user sees on the screen with what is written in the log file so that a post-mortem analysis can be performed. If SQL LogScout main script generates any runtime errors that were not caught, those will be written to the ##STDERR.LOG file and the contents of that file is displayed in the console after the main script completes execution.

# Targeted SQL instances

Diagnostic data is collected from the SQL instance you selected locally on the machine where SQL LogScout runs. SQL LogScout does not capture data on remote machines. You are prompted to pick a SQL Server instance you want to target. The SQL Server-specific data collection comes from a single instance only.

# Test Suite

The test suite is intended for confirm existence of output logs from SQL LogScout (smoke tests) currently. The set of tests will grow over time. To run the test, simply execute the RunTests.bat under the \TestingInfrastructure folder in command prompt.

## Examples:

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
