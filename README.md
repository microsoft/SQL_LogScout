[https://aka.ms/sqllogscout](https://aka.ms/sqllogscout) gets you here


1. [Introduction](#Introduction)
1. [Minimum Requirements](#Minimum-requirements)
1. [Download location](#Download-location)
1. [How to use](#How-to-use)
    - [Automate data collection](#Automate-data-collection)
    - [Interrupt execution](#Interrupt-execution)
    - [Parameters](#Parameters)
    - [Examples](#examples)
1. [Scenarios](#Scenarios)
1. [Output folders](#Output-folders)
1. [Logging](#Logging)
1. [Permissions](#Permissions)
1. [Targeted SQL instances](#Targeted-SQL-instances)
1. [Security](#Security)
1. [Sample output](#Sample-output)
1. [Test Suite](#Test-Suite)

# Important Note
   > SQL LogScout development team is aware that some third-party tools are flagging both the ZIP package and individual files of ***`version 4.1.1`*** as a malicious threat. **The development team conducted extensive review of the source files and found no malicious code in it.** In addition, the development teams is improving the software to avoid this annoyance in the future. **We have discovered that if we break up the main file into several files - smaller and less complex scripts - then this issue is no longer reported.** We wanted to remind you that all of the SQL LogScout files are digitally signed which ensures that they cannot be modified or tampered with – for more details around the security measures see section [SQL LogScout - Security](https://github.com/microsoft/SQL_LogScout#Security).

# Introduction

SQL LogScout allows you to collect diagnostic logs from your SQL Server system to help you and Microsoft technical support engineers (CSS) to resolve SQL Server technical incidents faster. It is a light, script-based, open-source tool that is version-agnostic. SQL LogScout discovers the SQL Server instances running locally on the system (including FCI and AG instances) and offers you a list to choose from. SQL LogScout can be executed without the need for Sysadmin privileges on the SQL Server instance (see [Permissions](#permissions)).

SQL LogScout is developed and maintained by members of the Microsoft SQL Server technical support teams in CSS.

# Minimum requirements

- Windows 2012 or later
- Powershell version 4.0 or later

# Download location

Download the latest version of SQL LogScout at [https://aka.ms/get-sqllogscout](https://aka.ms/get-sqllogscout). 

# How to use

1. Place the downloaded files on a disk volume where diagnostic logs will be captured. An \output* sub-folder will be created automatically by the tool when you start it
   > **WARNING**
   > Please make sure that the SQL Server startup account has **write** permissions to the folder you selected. Typically folders like %USERPROFILE%\Downloads, %USERPROFILE%\Documents AND %USERPROFILE%\Desktop folders are **not** write-accessible by the SQL Server service account by default.

1. Open a Command Prompt as an Administrator and change to the folder where SQL LogScout files reside
1. Start the tool via `SQL_LogScout.cmd` before or while the issue is occurring. You can use [parameters](#Parameters) to automate the execution and bypass interactive menus.
1. Select from a list which SQL instance you want to diagnose
1. Pick one or more [Scenarios](#scenarios) from a menu list (based on the issue under investigation). Scenario names can optionally be passed as parameters to the main script (see [Parameters](#Parameters))
1. Stop the collection when you are ready (by typing "stop" or "STOP"). In some Scenarios (e.g. Basic) the collection stops automatically

## Automate data collection

SQL LogScout can be executed with multiple parameters allowing for full automation and no interaction with menus. You can:

- Provide the SQL Server instance name
- Schedule start and stop time of data collection
- Use Quiet mode to accept all prompts automatically
- Choose the destination output folder (custom location, delete default or create a new one folder)

See [Parameters](#parameters) and [Example E](#e-execute-sql-logscout-with-multiple-scenarios-and-in-quiet-mode) for detailed information.

## Interrupt execution

If the need arises, you can interrupt the execution of SQL LogScout by pressing **CTRL+C** at any time. In some cases you may have to be patient before the CTRL+C is reflected (a few seconds) depending on what is being executed at the time. But in most cases the process is immediate. It is not recommended to close the Command Prompt window where SQL LogScout is running because this may leave a data collector running on your system.

## Parameters

SQL_LogScout.cmd accepts several optional parameters. Because this is a batch file, you have to specify the parameters in the sequence listed below. Also, you cannot omit parameters. For example if you would like to specify the server instance (3rd parameter), you must specify DebugLevel and Scenario parameters before it.

1. **DebugLevel** - this parameter is no longer honored in version 4.1.11. It is still present but will not do anything. See [Debug Log](#sqllogscout_debuglog-file) for detailed-level debugging information. This parameter will be removed in future versions.

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
    - "IO"
    - "LightPerf"
    - "MenuChoice" - this directs SQL LogScout to present an interactive menu with Scenario choices. The option is available in cases where multiple parameters are used with the tool. Combining MenuChoice with another scenario choice, causes SQL LogScout to ignore MenuChoice and pick the selected scenario(s). For more information on what data each scenario collects, see [Scenarios](#Scenarios)

   **Multiple Scenarions:** You can select *one or more* scenarios. To combine multiple scenarios use the *plus sign* (+). For example:

   `GeneralPerf+Memory+Setup`

   *Note:* This is only required when parameters are used for automation.

1. **ServerName** - specify the SQL Server to collect data from by using the following format "Server\Instance". For clustered instances (FCI) or Always On, use the virtual network name (VNN).

1. **CustomOutputPath** - specify a custom volume and directory where the data can be collected. An *\output* folder or *\output_ddMMyyhhmmss* would still be created under this custom path. Possible values are:
    - "PromptForCustomDir" - will cause the user to be prompted whether to specify a custom path
    - "UsePresentDir"  - will use the present directory wher SQL LogScout is copied (no custom path)
    - An existing path (e.g. D:\logs) - will use the specified path for data collection.  **Note:** Do not use a trailing backslash at the end. For example "D:\logs\\" will lead to an error.

1. **DeleteExistingOrCreateNew** - possible values are: 
    - "DeleteDefaultFolder" - will cause the default \output folder to be deleted and recreated
    - "NewCustomFolder"  - will cause the creation of a new folder in the format *\output_ddMMyyhhmmss*. If a previous collection created an \output folder, then that folder will be preserved when NewCustomFolder option is used.

1. **DiagStartTime** - specify the time when you want SQL LogScout to start data collection in the future. If the time is older than or equal to current time, data collection starts immediately. Format to use is "yyyy-MM-dd hh:mm:ss" (in quotes). For example: "2020-10-27 19:26:00" or "07-07-2021" (if you want to specify a date in the past without regard for a time).  

1. **DiagStopTime** - specify the time when you want SQL LogScout to stop data collection in the future. If the time is older than or equal to current time, data collection stops immediately. Format to use is "yyyy-MM-dd hh:mm:ss" (in quotes). For example: "2020-10-27 19:26:00" or "07-07-2021" (if you want to specify a date in the past without regard for a time).

1. **InteractivePrompts** - possible values are:
     - Quiet - suppresses possible prompts for data input. Selecting Quiet mode implicitly selects "Y" to all the screens that requires an agreement to proceed.
     - Noisy - (default) shows prompts requesting user input where necessary

## Examples

### A. Execute SQL LogScout (most common execution)

This is the most common method to execute SQL LogScout which allows you to pick your choices from a menu of options

```bash
SQL_LogScout.cmd
```

### B. Execute SQL LogScout using a specific scenario and debug level

This command starts the diagnostic collection with no debug logging and specifies the GeneralPerf scenario.

```bash
SQL_LogScout.cmd 0 GeneralPerf
```

### C. Execute SQL LogScout by specifying folder creation option

Execute SQL LogScout using the DetailedPerf Scenario, DebugLevel 2, specifies the Server name, use the present directory and folder option to delete the default \output folder if present

```bash
SQL_LogScout.cmd 2 DetailedPerf "DbSrv\SQL2019" "UsePresentDir" "DeleteDefaultFolder"
```

### D. Execute SQL LogScout with start and stop times

The following example uses debuglevel 5, collects the AlwaysOn scenario against the "DbSrv" default instance, prompts user to choose a custom path and a new custom subfolder, and sets the stop time to some time in the future, while setting the start time in the past to ensure the collectors start without delay.  

```bash
SQL_LogScout.cmd 5 AlwaysOn "DbSrv" PromptForCustomDir NewCustomFolder "2000-01-01 19:26:00" "2020-10-29 13:55:00"
```

**Note:** All parameters are required if you need to specify the last parameter. For example, if you need to specify stop time, the 5 prior parameters have to be passed.

### E. Execute SQL LogScout with multiple scenarios and in Quiet mode

The example uses debuglevel 5, collects data for GeneralPerf, AlwaysOn, and BackupRestore scenarios against the "DbSrv" default instance, re-uses the default output folder but creates it in the D:\Log custom path, and sets the stop time to some time in the future, while setting the start time in the past to ensure the collectors start without delay.  It also automatically accepts the prompts by using Quiet mode and helps a full automation with no interaction.

```bash
SQL_LogScout.cmd 5 GeneralPerf+AlwaysOn+BackupRestore DbSrv "d:\log" DeleteDefaultFolder "01-01-2000" "04-01-2021 17:00" Quiet
```

**Note:**  Selecting Quiet mode implicitly selects "Y" to all the screens that requires your agreement to proceed. 


# Scenarios

0. **Basic scenario** collects snapshot logs. It captures information:
   - Running drivers on the system
   - System information (systeminfo.exe)
   - Miscellaneous sql configuration (sp_configure, databases, etc)
   - Processes running on the system (Tasklist.exe)
   - Current active PowerPlan
   - Installed Windows Hotfixes
   - Running filter drivers
   - Event logs (system and application in both .CSV and .TXT formats)
   - SQL Errorlogs
   - SQL Agent logs
   - Polybase logs
   - [Windows Cluster logs](https://docs.microsoft.com/en-us/powershell/module/failoverclusters/get-clusterlog)
   - [AlwaysOn_health*.xel](https://docs.microsoft.com/sql/database-engine/availability-groups/windows/always-on-extended-events#BKMK_alwayson_health)
   - [MSSQLSERVER_SQLDIAG*.xel](https://docs.microsoft.com/sql/database-engine/availability-groups/windows/always-on-health-diagnostics-log)
   - [SQL VSS Writer Log (SQL Server 2019 and later)](https://docs.microsoft.com/sql/relational-databases/backup-restore/sql-server-vss-writer-logging)
   - [SQL Assessment API](https://docs.microsoft.com/sql/tools/sql-assessment-api/sql-assessment-api-overview) log
   - Windows Cluster HKEY_LOCAL_MACHINE\Cluster registry hive in .HIV format

1. **GeneralPerf scenario** collects all the Basic scenario logs as well as some long-term, continuous logs (until SQL LogScout is stopped).
   - Basic scenario
   - Performance Monitor counters for SQL Server instance and general OS counters
   - Extended Event (XEvent) trace captures batch-level starting/completed events, errors and warnings, log growth/shrink, lock escalation and timeout, deadlock, login/logout
   - List of actively-running SQL traces and Xevents
   - Snapshots of SQL DMVs that track waits/blocking and high CPU queries
   - Query Data Store info (if that is active)
   - Tempdb contention info from SQL DMVs/system views
   - Linked Server metadata (SQL DMVs/system views)
   - Service Broker configuration information (SQL DMVs/system views)

    *Note:* If you combine GeneralPerf with DetailedPerf scenario, then the GeneralPerf will be disabled and only DetailedPerf will be collected.

1. **DetailedPerf scenario** collects the same info that the GeneralPerf scenario. The difference is in the Extended event trace
   - GeneralPerf scenario
   - Extended Event trace captures same as GeneralPerf. In addition in the same trace it captures statement level starting/completed events and actual XML query plans (for completed queries)

1. **Replication scenario** collects all the Basic scenario logs plus SQL Replication, Change Data Capture (CDC) and Change Tracking (CT) information
   - Basic Scenario
   - Replication, CDC, CT diagnostic info (SQL DMVs/system views). This is captured both at startup and shutdown so a comparative analysis can be performed on the data collected during SQL LogScout execution. 

1. **AlwaysOn scenario** collects all the Basic scenario logs as well as Always On configuration information from DMVs
   - Basic scenario
   - Always On diagnostic info (SQL DMVs/system views)
   - Always On [Data Movement Latency Xevent ](https://techcommunity.microsoft.com/t5/sql-server-support/troubleshooting-data-movement-latency-between-synchronous-commit/ba-p/319141)
   - Performance Monitor counters for SQL Server instance and general OS counters

1. **Network Trace scenario** collects a network trace from the machine where SQL LogSout is running. The output is an .ETL file. This is achived with a combination of Netsh trace and Logman built-in Windows utilities. These are invoked via StartNetworkTrace.bat.

1. **Memory** - collects
   - Basic scenario
   - Performance Monitor counters for SQL Server instance and general OS counters
   - Memory diagnostic info from SQL DMVs/system views

1. **Generate Memory Dumps scenario** - allows to collect one or more memory dumps of SQL Server family of processes (SQL Server, SSAS, SSIS, SSRS, SQL Agent). If multiple dumps are selected, the number of dumps and the interval between them is customizable. Also the type of dump is offered as a choice (mini dump, mini with indirect memory, filtered (SQL Server), full.

1. **Windows Performance Recorder (WPR) scenario** allows to collect a [Windows Performance Recorder](https://docs.microsoft.com/windows-hardware/test/wpt/introduction-to-wpr) trace. Here you can execute a sub-scenario depending on the knd of problem you want to address. These subscenarios are:
    - CPU - collects Windows performance data about CPU-related activities performed by processes and the OS
    - Heap and Virtual memory - collects Windows performance data about memory allocations (virtual and heap memory)performed by processes and the OS
    - Disk and File I/O - collects Windows performance data about I/O performance performed by processes and the OS
    - Filter drivers - collects performance data about filter driver activity on the system (OS)

   **WARNING**: WPR traces collect system-wide diagnostic data. Thus a large set of trace data may be collected and it may take several minutes to stop the trace. Therefore the WPR trace is limited to 15 seconds of data collection.

1. **Setup scenario** - collects all the Basic scenario logs and all SQL Setup logs from the \Setup Bootstrap\ folders on the system. This allows analysis of setup or installation issues of SQL Server components.

1. **Backup and Restore scenario** - collects the Basic scenario logs and various logs related to backup and restore activities in SQL Server. These logs include:

    - Backup and restore-related Xevent (backup_restore_progress_trace  and batch start end xevents)
    - Enables backup and restore related TraceFlags to produce information in the Errorlog
    - Performance Monitor counters for SQL Server instance and general OS counters
    - SQL VSS Writer Log (on SQL Server 2019 and later)
    - VSS Admin (OS) logs for VSS backup-related scenarios

1. **I/O** - collects the Basic scenario logs and several logs related to disk I/O activity:
    - [StorPort trace](https://docs.microsoft.com/archive/blogs/askcore/tracing-with-storport-in-windows-2012-and-windows-8-with-kb2819476-hotfix) which gathers information about the device driver activity connected to STORPORT.SYS.  
    - High_IO_Perfstats - collects data from disk I/O related DMVs in SQL Server
    - Performance Monitor counters for SQL Server instance and general OS counters
1. **LightPerf** - collects everything that the GeneralPerf scenario does, _except_ the Extended Event traces. This is intended to capture light perf data to get an overall system performance view without detailed execution of queries (no XEvents).

# Output folders

**Output folder**: All the diagnostic log files are collected in the \output (or \output_ddMMyyhhmmss) folder. These include perfmon log (.BLG), event logs, system information, extended event (.XEL), etc. By default this folder is created in the same location where SQL LogScout files reside (present directory). However a user can choose to collect data on a different disk volume and folder. This can be done by following the prompt for a non-default drive and directory or by using the CustomOutputPath parameter ([Parameters](#Parameters))

**Internal folder**: The \output\internal folder stores error log files for each individual data collector. Most of those files are empty (zero bytes) if the specific collector did not generate any errors or console output. If those files are not empty, they contain information about whether a particular data-collector failed or produced some result (not necessarily failure). The \internal folder also stores the main activity log file for SQL LogScout (##SQLLOGSCOUT.LOG).  If the main script produces some errors in the console, those are redirected to a file ##STDERR.LOG which is also moved to \internal folder at the end of execution if the file is non-zero in size.

# Logging

### ##SQLLOGSCOUT.LOG file

SQL LogScout logs the flow of activity in two files ##SQLLOGSCOUT.LOG and ##SQLLOGSCOUT_DEBUG.LOG. The activity flow on the console is logged in ##SQLLOGSCOUT.LOG. The design goal is to match what the user sees on the screen with what is written in the log file so that a post-mortem analysis can be performed. 

### ##STDERR.LOG file
If SQL LogScout main script generates any runtime errors that were not caught, those will be written to the ##STDERR.LOG file and the contents of that file is displayed in the console after the main script completes execution. The ##STDERR.LOG file is stored in the root directory where SQL LogScout runs because any failures that occur early before the creation of an output folder may be logged in this file. 

### ##SQLLOGSCOUT_DEBUG.LOG file
This file contains everything the ##SQLLOGSCOUT.LOG contains, but also adds many debug-level, detailed messages. These can be used to investigate any issues with SQL LogScout and examine the flow of execution in detail. 

# Permissions

- **Windows**: Local Administrator permissions on the machine are required to collect most system-related logs

- **SQL Server**: VIEW SERVER STATE and ALTER ANY EVENT SESSION are the minimum required permission for collecting the SQL Server data.

# Targeted SQL instances

Diagnostic data is collected from the SQL instance you selected locally on the machine where SQL LogScout runs. SQL LogScout does not capture data on remote machines. You are prompted to pick a SQL Server instance you want to target. The SQL Server-specific data collection comes from a single instance only.

# Security

SQL LogScout is released with digitally-signed Powershell files. For other files, SQL LogScout calculates a SHA512 hash and compares it to the expected value of each file. If the stored hash does not match the calculated hash on disk, then SQL LogScout will not run.  

To manually validate script signature, you may execute the following:

```bash
Get-ChildItem <SQL LogScout unzipped folder>\*.ps*1 | Get-AuthenticodeSignature | Format-List -Property Path, Status, StatusMessage, SignerCertificate`
```

Example:

```bash
Get-ChildItem C:\SQL_LogScout_v4.1.11_Signed\*.ps*1 | Get-AuthenticodeSignature | Format-List -Property Path, Status, StatusMessage, SignerCertificate`
```

For each file:

1. Confirm the path and filename in `Path` property.
2. Confirm that `Status` property is **`Valid`**. For any `Status` other than `Valid`, `StatusMessage` property provides an description of the issue.
4. Confirm the details of `SignerCertificate` property to indicate that Microsoft Corporation is the subject of the certificate.

Example output for successful validation:
```bash
Path              : C:\SQL_LogScout_v4.1.11_Signed\SQLLogScoutPs.ps1
Status            : Valid
StatusMessage     : Signature verified.
SignerCertificate : [Subject]
                      CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US

                    [Issuer]
                      CN=Microsoft Code Signing PCA 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US

                    [Serial Number]
                      33000001DF6BF02E92A74AB4D00000000001DF

                    [Not Before]
                      12/15/2020 6:31:45 PM

                    [Not After]
                      12/2/2021 6:31:45 PM

                    [Thumbprint]
                      ABDCA79AF9DD48A0EA702AD45260B3C03093FB4B
```

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

2021-09-10 11:03:32.148	INFO	Initializing log C:\temp\log scout\Test 2\output\internal\##SQLLOGSCOUT.LOG 
2021-09-10 11:03:26.230	INFO	SQL LogScout version: 4.1.0 
2021-09-10 11:03:26.302	INFO	The Present folder for this collection is C:\temp\log scout\Test 2 
2021-09-10 11:03:30.479	INFO	Prompt CustomDir Console Input: n 
2021-09-10 11:03:30.551	INFO	 
2021-09-10 11:03:30.560	WARN	It appears that output folder 'C:\temp\log scout\Test 2\output\' has been used before. 
2021-09-10 11:03:30.562	WARN	You can choose to: 
2021-09-10 11:03:30.562	WARN	 - Delete (D) the \output folder contents and recreate it 
2021-09-10 11:03:30.572	WARN	 - Create a new (N) folder using \Output_ddMMyyhhmmss format. 
2021-09-10 11:03:30.572	WARN	   You can delete the new folder manually in the future 
2021-09-10 11:03:31.954	INFO	Output folder Console input: d 
2021-09-10 11:03:32.118	WARN	Deleted C:\temp\log scout\Test 2\output\ and its contents 
2021-09-10 11:03:32.126	INFO	Output path: C:\temp\log scout\Test 2\output\ 
2021-09-10 11:03:32.126	INFO	Error  path is C:\temp\log scout\Test 2\output\internal\ 
2021-09-10 11:03:32.168	INFO	Validating attributes for non-Powershell script files 
2021-09-10 11:03:32.648	INFO	 
2021-09-10 11:03:32.656	INFO	Initiating diagnostics collection...  
2021-09-10 11:03:32.659	INFO	Please select one of the following scenarios:
 
2021-09-10 11:03:32.659	INFO	 
2021-09-10 11:03:32.669	INFO	ID	 Scenario 
2021-09-10 11:03:32.669	INFO	--	 --------------- 
2021-09-10 11:03:32.677	INFO	0 	 Basic 
2021-09-10 11:03:32.679	INFO	1 	 GeneralPerf 
2021-09-10 11:03:32.679	INFO	2 	 DetailedPerf 
2021-09-10 11:03:32.687	INFO	3 	 Replication 
2021-09-10 11:03:32.689	INFO	4 	 AlwaysOn 
2021-09-10 11:03:32.689	INFO	5 	 NetworkTrace 
2021-09-10 11:03:32.689	INFO	6 	 Memory 
2021-09-10 11:03:32.689	INFO	7 	 DumpMemory 
2021-09-10 11:03:32.697	INFO	8 	 WPR 
2021-09-10 11:03:32.699	INFO	9 	 Setup 
2021-09-10 11:03:32.699	INFO	10 	 BackupRestore 
2021-09-10 11:03:32.699	INFO	11 	 IO 
2021-09-10 11:03:32.699	INFO	12 	 LightPerf 
2021-09-10 11:03:32.709	INFO	 
2021-09-10 11:03:32.709	WARN	Type one or more Scenario IDs (separated by '+') for which you want to collect diagnostic data. Then press Enter 
2021-09-10 11:04:02.077	INFO	Scenario Console input: 1+4+10 
2021-09-10 11:04:02.208	INFO	The scenarios selected are: 'GeneralPerf AlwaysOn BackupRestore Basic' 
2021-09-10 11:04:02.665	INFO	Discovered the following SQL Server instance(s)
 
2021-09-10 11:04:02.665	INFO	 
2021-09-10 11:04:02.676	INFO	ID	SQL Instance Name 
2021-09-10 11:04:02.678	INFO	--	---------------- 
2021-09-10 11:04:02.679	INFO	0 	 DbServerMachine 
2021-09-10 11:04:02.679	INFO	1 	 DbServerMachine\SQL2014 
2021-09-10 11:04:02.686	INFO	2 	 DbServerMachine\SQL2017 
2021-09-10 11:04:02.686	INFO	3 	 DbServerMachine\SQL2019 
2021-09-10 11:04:02.686	INFO	 
2021-09-10 11:04:02.686	WARN	Enter the ID of the SQL instance for which you want to collect diagnostic data. Then press Enter 
2021-09-10 11:04:11.899	INFO	SQL Instance Console input: 3 
2021-09-10 11:04:11.911	INFO	You selected instance 'DbServerMachine\SQL2019' to collect diagnostic data.  
2021-09-10 11:04:12.022	INFO	Confirmed that MYDOMAIN\Joseph has VIEW SERVER STATE on SQL Server Instance 'DbServerMachine\SQL2019' 
2021-09-10 11:04:12.022	INFO	Confirmed that MYDOMAIN\Joseph has ALTER ANY EVENT SESSION on SQL Server Instance 'DbServerMachine\SQL2019' 
2021-09-10 11:04:12.735	WARN	At least one of the selected 'GeneralPerf AlwaysOn BackupRestore Basic' scenarios collects Xevent traces 
2021-09-10 11:04:12.751	WARN	The service account 'NT Service\MSSQL$SQL2019' for SQL Server instance 'DbServerMachine\SQL2019' must have write/modify permissions on the 'C:\temp\log scout\Test 2\output\' folder 
2021-09-10 11:04:12.751	WARN	The easiest way to validate write permissions on the folder is to test-run SQL LogScout for 1-2 minutes and ensure an *.XEL file exists that you can open and read in SSMS 
2021-09-10 11:04:15.822	INFO	Access verification Console input: y 
2021-09-10 11:04:15.841	INFO	LogmanConfig.txt copied to  C:\temp\log scout\Test 2\output\internal\LogmanConfig.txt 
2021-09-10 11:04:15.922	INFO	Basic collectors will execute on shutdown 
2021-09-10 11:04:15.934	INFO	Collecting logs for 'GeneralPerf' scenario 
2021-09-10 11:04:15.964	INFO	Executing Collector: Perfmon 
2021-09-10 11:04:17.055	INFO	Executing Collector: xevent_general 
2021-09-10 11:04:19.130	INFO	Executing Collector: xevent_general_target 
2021-09-10 11:04:19.152	INFO	Executing Collector: xevent_general_Start 
2021-09-10 11:04:19.214	INFO	Executing Collector: ExistingProfilerXeventTraces 
2021-09-10 11:04:21.313	INFO	Executing Collector: HighCPU_perfstats 
2021-09-10 11:04:21.364	INFO	Executing Collector: SQLServerPerfStats 
2021-09-10 11:04:23.441	INFO	Executing Collector: SQLServerPerfStatsSnapshotStartup 
2021-09-10 11:04:23.492	INFO	Executing Collector: Query Store 
2021-09-10 11:04:25.552	INFO	Executing Collector: TempDBAnalysis 
2021-09-10 11:04:25.601	INFO	Executing Collector: linked_server_config 
2021-09-10 11:04:25.652	INFO	Executing Collector: SSB_diag 
2021-09-10 11:04:25.708	INFO	Collecting logs for 'AlwaysOn' scenario 
2021-09-10 11:04:25.740	INFO	Executing Collector: AlwaysOnDiagScript 
2021-09-10 11:04:25.809	INFO	Executing Collector: xevent_AlwaysOn_Data_Movement 
2021-09-10 11:04:27.853	INFO	Executing Collector: AlwaysOn_Data_Movement_target 
2021-09-10 11:04:27.881	INFO	Executing Collector: AlwaysOn_Data_Movement_Start 
2021-09-10 11:04:27.922	INFO	Executing Collector: AlwaysOnHealthXevent 
2021-09-10 11:04:28.007	INFO	Collecting logs for 'BackupRestore' scenario 
2021-09-10 11:04:28.023	INFO	Executing Collector: xevent_backup_restore 
2021-09-10 11:04:30.070	INFO	Executing Collector: EnableTraceFlag 
2021-09-10 11:04:30.159	WARN	To enable SQL VSS VERBOSE loggging, the SQL VSS Writer service must be restarted now and when shutting down data collection. This is a very quick process. 
2021-09-10 11:04:36.697	INFO	Console Input: n 
2021-09-10 11:04:36.705	INFO	You have chosen not to restart SQLWriter Service. No verbose logging will be collected 
2021-09-10 11:04:36.737	INFO	Executing Collector: VSSAdmin_Providers 
2021-09-10 11:04:36.778	INFO	Executing Collector: VSSAdmin_Shadows 
2021-09-10 11:04:37.832	INFO	Executing Collector: VSSAdmin_Shadowstorage 
2021-09-10 11:04:37.873	INFO	Executing Collector: VSSAdmin_Writers 
2021-09-10 11:04:37.924	INFO	Please type 'STOP' to terminate the diagnostics collection when you finished capturing the issue 
2021-09-10 11:04:43.012	INFO	StopCollection Console input: stop 
2021-09-10 11:04:43.014	INFO	Shutting down the collector 
2021-09-10 11:04:43.032	INFO	Executing shutdown command: xevents_stop 
2021-09-10 11:04:43.073	INFO	Executing shutdown command: xevents_alwayson_data_movement_stop 
2021-09-10 11:04:43.098	INFO	Executing shutdown command: Disable Backup Restore Trace Flag 
2021-09-10 11:04:43.145	INFO	Executing shutdown command: PerfmonStop 
2021-09-10 11:04:46.228	INFO	Executing shutdown command: KillActiveLogscoutSessions 
2021-09-10 11:04:47.277	INFO	Collecting logs for 'Basic' scenario 
2021-09-10 11:04:47.298	INFO	Executing Collector: TaskListVerbose 
2021-09-10 11:04:47.339	INFO	Executing Collector: TaskListServices 
2021-09-10 11:04:47.407	INFO	Executing Collector: FLTMC_Filters 
2021-09-10 11:04:47.464	INFO	Executing Collector: FLTMC_Instances 
2021-09-10 11:04:47.533	INFO	Executing Collector: SystemInfo_Summary 
2021-09-10 11:04:47.618	INFO	Executing Collector: MiscPssdiagInfo 
2021-09-10 11:04:47.681	INFO	Executing Collector: SQLErrorLogs_AgentLogs_SystemHealth_MemDumps_FciXel 
2021-09-10 11:04:50.501	INFO	Executing Collector: PolybaseLogs 
2021-09-10 11:04:50.533	INFO	Executing Collector: SQLAssessmentAPI 
2021-09-10 11:05:09.554	INFO	Executing Collector: UserRights 
2021-09-10 11:05:12.266	INFO	Executing Collector: RunningDrivers 
2021-09-10 11:05:14.217	INFO	Executing Collector: PowerPlan 
2021-09-10 11:05:14.308	INFO	Executing Collector: WindowsHotfixes 
2021-09-10 11:05:16.694	INFO	Executing Collector: GetEventLogs 
2021-09-10 11:05:16.707	INFO	Gathering Application EventLog in TXT and CSV format   
2021-09-10 11:05:23.218	INFO	   Produced 10000 records in the EventLog 
2021-09-10 11:05:29.011	INFO	   Produced 20000 records in the EventLog 
2021-09-10 11:05:35.914	INFO	   Produced 30000 records in the EventLog 
2021-09-10 11:05:41.975	INFO	   Produced 39129 records in the EventLog 
2021-09-10 11:05:41.975	INFO	Application EventLog in TXT and CSV format completed! 
2021-09-10 11:05:41.975	INFO	Gathering System EventLog in TXT and CSV format   
2021-09-10 11:05:50.913	INFO	   Produced 10000 records in the EventLog 
2021-09-10 11:05:59.494	INFO	   Produced 20000 records in the EventLog 
2021-09-10 11:06:04.839	INFO	   Produced 26007 records in the EventLog 
2021-09-10 11:06:04.842	INFO	System EventLog in TXT and CSV format completed! 
2021-09-10 11:06:04.879	INFO	Executing Collector: SQLServerPerfStatsSnapshotShutdown 
2021-09-10 11:06:04.917	INFO	Waiting 3 seconds to ensure files are written to and closed by any program including anti-virus... 
2021-09-10 11:06:08.518	INFO	Ending data collection 
2021-09-10 11:06:08.533	WARN	Launching cleanup and exit routine... please wait 
2021-09-10 11:06:13.780	INFO	Thank you for using SQL LogScout! 

Checking for console execution errors logged into .\##STDERR.LOG...
Removed .\##STDERR.LOG which was 0 bytes
```

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
