[https://aka.ms/sqllogscout](https://aka.ms/sqllogscout) gets you here

1. [Introduction](#introduction)
1. [Minimum Requirements](#minimum-requirements)
1. [Download location](#download-location)
1. [How to use](#how-to-use)
    - [Automate data collection](#automate-data-collection)
    - [Interrupt execution](#interrupt-execution)
    - [Parameters](#parameters)
    - [Examples](#examples)
1. [Scenarios](#scenarios)
1. [Output folders](#output-folders)
1. [Logging](#logging)
1. [Permissions](#permissions)
1. [Targeted SQL instances](#targeted-sql-instances)
1. [Security](#security)
1. [Sample output](#sample-output)
1. [Test Suite](#test-suite)
1. [Script to cleanup an incomplete shutdown of SQL LogScout](#script-to-cleanup-an-incomplete-shutdown-of-sql-logscout)
1. [SQL LogScout as a scheduled task in Windows Task Scheduler](#schedule-sql-logscout-as-a-task-to-automate-execution)

# Introduction

SQL LogScout allows you to collect diagnostic logs from your SQL Server system to help you and Microsoft technical support engineers (CSS) to resolve SQL Server technical incidents faster. It is a light, script-based, open-source tool that is version-agnostic. SQL LogScout discovers the SQL Server instances running locally on the system (including FCI and AG instances) and offers you a list to choose from. SQL LogScout can be executed without the need for Sysadmin privileges on the SQL Server instance (see [Permissions](#permissions)).

SQL LogScout is developed and maintained by members of the Microsoft SQL Server technical support teams in CSS.

# Minimum requirements

- Windows 2012 or later (including Windows Server Core)
- Powershell version 4.0, 5.0, or 6.0
- Powershell execution policy `RemoteSigned` or less restrictive

  If you have never run Powershell scripts before on your system, you must ensure that execution policy allows you to run scripts. Otherwise, you will get UnauthorizedAccess error "sqllogscoutps.ps1 cannot be loaded because running scripts is disabled on this system". To check the execution policy, open PowerShell and run this command:

   ```Powershell
   Get-ExecutionPolicy
   ```

   If the result is "Restricted", reset it to RemoteSigned or Unrestricted for your user

   ```PowerShell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

- Full Language Mode (For more information see [about_Language_Modes](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/about/about_language_modes)
  To check the language mode, execute this in PowerShell:

  ```powershell
  $ExecutionContext.SessionState.LanguageMode
  ```


  If your language mode is not FullLanguage or you received an error like this when executing SQL LogScout : `Method invocation is supported only on core types in this language mode` you need to enable FullLanguage mode. To do so, run this in PowerShell

   ```powershell
   $ExecutionContext.SessionState.LanguageMode = "FullLanguage"
   ```

# How get get SQL LogScout

You can obtain SQL LogScout in two ways:

- Download from Github
- Use it directly inside a SQL VM image (preinstalled)

## Download location

Download the latest version of SQL LogScout at [https://aka.ms/get-sqllogscout](https://aka.ms/get-sqllogscout).

## Get inside an Azure SQL Server VM image

If you create a SQL Server VM on Windows resource on Azure, you will get SQL LogScout as part of the image. You can locate it under `C:\SQLServerTools` folder on the image. For example, the "SQL Server 2019 on Windows Server 2022" or "SQL Server 2019 on Windows Server 2019" resources will include SQL LogScout. BYOL (bring your own license) resources do not include the tool by default and it has to be downloaded.

# Where to place and run SQL LogScout

You can place the downloaded SQL_LogScout_*.zip file in any folder of your choice. However, it is critical that the output folder where logs are stored is on a *fast-performing* disk volume, not a network share nor a network-mapped drive. SQL LogScout collects various logs (Xevent traces, Perfmon logs, event logs, cluster logs, etc) and the writing speed of the disk they are placed on is crucial in order to minimize performance impact on the system. The faster the I/O response, the smaller the impact of log collection will be on SQL Server performance. We recommend that you place SQL LogScout on a dedicated disk drive, different from the one where database files reside.

**NOTE:** Avoid using non-alphanumeric characters for folder names in the SQL LogScout path. Some collectors or functionality  may behave unexpectedly or fail if you use characters such as "!@#$%^&*()" in directory names. Currently we are aware that Network trace and Command prompt are affected.

# How to use

There are 3 possible ways to run and interact with SQL LogScout:

- Batch file
- GUI
- PowerShell file

## Use batch file

1. Place the downloaded files on a disk volume where diagnostic logs will be captured. An \output* sub-folder will be created automatically by the tool when you start it

   | :warning: WARNING          |
   |:---------------------------|
   | Please make sure that the SQL Server startup account has **write** permissions to the folder you selected. Typically folders like %USERPROFILE%\Downloads, %USERPROFILE%\Documents AND %USERPROFILE%\Desktop folders are **not** write-accessible by the SQL Server service account by default.|

1. Open a Command Prompt as an Administrator and change to the folder where SQL LogScout files reside. For example:

   ```console
   cd d:\sqllogscout
   ```

1. Start the tool via `SQL_LogScout.cmd` before or while the issue is occurring and follow the menus

   ```console
   SQL_LogScout.cmd
   ```

1. Pick one or more [Scenarios](#scenarios) from a menu list (based on the issue under investigation). Scenario names can optionally be passed as parameters to the main script (see [Parameters](#parameters))
1. Select from which SQL instance you want to diagnose
1. Stop the collection when you are ready (by typing "stop" or "STOP"). In some Scenarios (e.g. Basic) the collection stops automatically when it finishes collecting static logs

   NOTE: You can use [parameters](#parameters) to automate the execution and bypass interactive menus. For example:

   ```console
   SQL_LogScout.cmd GeneralPerf+Memory server_name
   ```

   For more information see [Examples](#examples)

## Use graphical user interface (GUI)

1. Place the downloaded files on a disk volume where diagnostic logs will be captured. An \output* sub-folder will be created automatically by the tool when you start it

  | :warning: WARNING          |
  |:---------------------------|
  | Please make sure that the SQL Server startup account has **write** permissions to the folder you selected. Typically folders like %USERPROFILE%\Downloads, %USERPROFILE%\Documents AND %USERPROFILE%\Desktop folders are **not** write-accessible by the SQL Server service account by default.|

1. Open a Command Prompt as an Administrator and change to the folder where SQL LogScout files reside. For example:

   ```console
   cd d:\sqllogscout
   ```

1. Start the tool via `SQL_LogScout.cmd` before or while the issue is occurring and follow the menus

   ```console
   SQL_LogScout.cmd
   ```

1. When prompted `Would you like to use GUI mode ?> (Y/N):` type 'y' and you will be presented with a GUI
1. Pick one or more [Scenarios](#scenarios) from a list (based on the issue under investigation).
1. Select from which SQL instance you want to diagnose
1. Select whether to overwrite an existing folder with data or let it default to creating a new folder
1. Stop the collection when you are ready (by typing "stop" or "STOP"). In some Scenarios (e.g. Basic) the collection stops automatically when it finishes collecting static logs

## Use PowerShell script

1. Place the downloaded files on a disk volume where diagnostic logs will be captured. An \output* sub-folder will be created automatically by the tool when you start it

   | :warning: WARNING          |
   |:---------------------------|
   | Please make sure that the SQL Server startup account has **write** permissions to the folder you selected. Typically folders like %USERPROFILE%\Downloads, %USERPROFILE%\Documents AND %USERPROFILE%\Desktop folders are **not** write-accessible by the SQL Server service account by default.|

1. Open a Command Prompt as an Administrator and change to the folder where SQL LogScout files reside. For example:

   ```console
   cd d:\sqllogscout
   ```

1. Start PowerShell (PS). For example you can run

   ```console
   powershell.exe
   ```

1. Run the following PS script by itself or by using [parameters](#parameters). For example:

   ```powershell
   PS > .\SQLLogScoutPs.ps1 -Scenario Basic -ServerName "Win2022machine\inst2022" -DiagStopTime "10-27-2022 19:15"
   ```

## Automate data collection

SQL LogScout can be executed with multiple parameters allowing for full automation and no interaction with menus. You can:

- Provide the SQL Server instance name
- Select which scenario(s) to collect data for
- Schedule start and stop time of data collection
- Use Quiet mode to accept all prompts automatically
- Choose the destination output folder (custom location, delete default or create a new one folder)

See [Parameters](#parameters) and [Example E](#e-execute-sql-logscout-with-multiple-scenarios-and-in-quiet-mode) for detailed information.

## Interrupt execution

If the need arises, you can interrupt the execution of SQL LogScout by pressing **CTRL+C** at any time. In some cases you may have to be patient before the CTRL+C is reflected (a few seconds) depending on what is being executed at the time. But in most cases the process is immediate.

| :warning: WARNING          |
|:---------------------------|
| Do **not** close the Command Prompt window where SQL LogScout is running because this may leave a data collector running on your system. You can safely do so when SQL LogScout completes.|

## Parameters

SQL_LogScout.cmd accepts several optional parameters. Because this is a batch file, you have to specify the parameters in the sequence listed below. Also, you cannot omit parameters. For example if you would like to specify the server instance (3rd parameter), you must specify the Scenario parameter before it.

### Scenario

Possible values are:

 - Basic
 - GeneralPerf
 - DetailedPerf
 - Replication
 - AlwaysOn
 - NetworkTrace
 - Memory
 - DumpMemory
 - WPR
 - Setup
 - BackupRestore
 - IO
 - LightPerf
 - ProcessMonitor
 - MenuChoice - this directs SQL LogScout to present an interactive menu with Scenario choices. The option is available in cases where multiple parameters are used with SQL_LogScout.cmd. Combining MenuChoice with another scenario choice, causes SQL LogScout to ignore MenuChoice and pick the selected scenario(s). For more information on what data each scenario collects, see [Scenarios](#scenarios)
 - NoBasic - this instructs SQL LogScout to skip the collection of basic logs, when Basic scenario is part of another scenario by default. For example if you use GeneralPerf+NoBasic, only the performance logs will be collected and static logs (Basic) will be skipped. If NoBasic+Basic is specified by mistake, the assumption is you intend to collect data; therefore Basic is enabled and NoBasic flag is disabled. Similarly, if NoBasic+Basic+A_VALID_SCENARIO is selected, again the assumption is that data collection is intended. In this case, Basic is enabled, NoBasic is disabled and A_VALID_SCENARIO will collect Basic logs.

*Multiple Scenarios:** You can select *one or more* scenarios. To combine multiple scenarios use the *plus sign* (+). For example:

   `GeneralPerf+Memory+Setup`

*Note:* Scenario parameter is only required when parameters are used for automation. An empty string "" is equivalent to MenuChoice and will cause the Menu to be displayed. Specifying a string with spaces " " will trigger an incorrect parameter message. In summary, if Scenario contains only "MenuChoice" or only "NoBasic" or is empty (no parameters passed), or MenuChoice+NoBasic is passed, then the Menu will be displayed.

### ServerName

Specify the SQL Server to collect data from by using the following format "Server\Instance". For clustered instances (FCI) or Always On, use the virtual network name (VNN). You can use period "." to connect to a local default instance. If you do so, the dot will be converted to the local host name. You can also use a combination of "ServerName,Port" or "IPAddress,Port" (with quotes around). For example "DbServer,1445" or "192.168.100.154,1433".

### CustomOutputPath

Specify a custom volume and directory where the data can be collected. An *\output* folder or *\output_ddMMyyhhmmss* would still be created under this custom path. Possible values are:

 - PromptForCustomDir - will cause the user to be prompted whether to specify a custom path
 - UsePresentDir  - will use the present directory where SQL LogScout is copied (no custom path)
 - An existing path (e.g. D:\logs) - will use the specified path for data collection.  **Note:** Do not use a trailing backslash at the end. For example "D:\logs\\" will lead to an error.

### DeleteExistingOrCreateNew

Possible values are:

 - DeleteDefaultFolder - will cause the default \output folder to be deleted and recreated
 - NewCustomFolder  - will cause the creation of a new folder in the format *\output_ddMMyyhhmmss*. If a previous collection created an \output folder, then that folder will be preserved when NewCustomFolder option is used.

### DiagStartTime

Specify the time when you want SQL LogScout to start data collection in the future. If the time is older than or equal to current time, data collection starts immediately. Format to use is "yyyy-MM-dd hh:mm:ss" (in quotes). For example: "2020-10-27 19:26:00" or "07-07-2021" (if you want to specify a date in the past without regard for a time).  

### DiagStopTime

Specify the time when you want SQL LogScout to stop data collection in the future. If the time is older than or equal to current time, data collection stops immediately. Format to use is "yyyy-MM-dd hh:mm:ss" (in quotes). For example: "2020-10-27 19:26:00" or "07-07-2021" (if you want to specify a date in the past without regard for a time).

### InteractivePrompts

Possible values are:

 - Quiet - suppresses possible prompts for data input. Selecting Quiet mode implicitly selects "Y" to all the screens that requires an agreement to proceed.
 - Noisy - (default) shows prompts requesting user input where necessary

## Graphical User Interface (GUI)

The GUI is a feature added in version 5.0 of SQL LogScout. It allows the user to make many of the selections in a single user interface, if they prefer it over the menu options in command prompt. You can do the following in the GUI:

- Select the scenario(s) you would like to collect data for
- Select the target SQL Server instance
- Select the destination log output folder. The default option here is to create a new folder under the Log location you choose. The new folder is of the format \Output_datetime. See **-DeleteFolderOrNew** parameter and  `NewCustomFolder` value as a reference. If you check the `Overwrite Existing Logs` option, an \Output folder will be created or overwritten if another copy existed before.
- Perfmon counters and SQL Server Extended events. Certain scenarios allow you to collect Perfmon counters and Xevent data (see [Scenarios](#scenarios) for more information). As you select scenarios these options will be enabled or disabled. You can also uncheck certain counters or Xevents if you want avoid collecting them, though it is recommended to go with the full set of counters and events that the scenario uses.
- The NoBasic checkbox corresponds to the NoBasic scenario switch. Essentially it collects logs for the specific scenario selected but excludes collecting basic logs, which is a default option for many of the scenarios. For more information, see [Parameters](#parameters) -> Scenarios.

If you do not select any option in the GUI (e.g. scenario or server name) and click OK, you would be prompted to do so in the command prompt menu options that follow the GUI. If you click the Cancel button in the GUI, SQL LogScout will clean up and exit.

## Examples

### A. Execute SQL LogScout (most common execution)

This is the most common method to execute SQL LogScout which allows you to pick your choices from a menu of options

```bash
SQL_LogScout.cmd
```

### B. Execute SQL LogScout using a specific scenario and debug level

This command starts the diagnostic collection specifying the GeneralPerf scenario.

```bash
SQL_LogScout.cmd GeneralPerf
```

### C. Execute SQL LogScout by specifying folder creation option

Execute SQL LogScout using the DetailedPerf Scenario, specifies the Server name, use the present directory and folder option to delete the default \output folder if present

```bash
SQL_LogScout.cmd DetailedPerf "DbSrv\SQL2019" "UsePresentDir" "DeleteDefaultFolder"
```

### D. Execute SQL LogScout with start and stop times

The following example collects the AlwaysOn scenario against the "DbSrv" default instance, prompts user to choose a custom path and a new custom subfolder, and sets the stop time to some time in the future, while setting the start time in the past to ensure the collectors start without delay.  

```bash
SQL_LogScout.cmd AlwaysOn "DbSrv" PromptForCustomDir NewCustomFolder "2000-01-01 19:26:00" "2020-10-29 13:55:00"
```

**Note:** All parameters are required if you need to specify the last parameter. For example, if you need to specify stop time, the 5 prior parameters have to be passed.

### E. Execute SQL LogScout with multiple scenarios and in Quiet mode

The example collects data for GeneralPerf, AlwaysOn, and BackupRestore scenarios against the "DbSrv" default instance, re-uses the default output folder but creates it in the D:\Log custom path, and sets the stop time to some time in the future, while setting the start time in the past to ensure the collectors start without delay.  It also automatically accepts the prompts by using Quiet mode and helps a full automation with no interaction.

```bash
SQL_LogScout.cmd GeneralPerf+AlwaysOn+BackupRestore DbSrv "d:\log" DeleteDefaultFolder "01-01-2000" "04-01-2021 17:00" Quiet
```

**Note:**  Selecting Quiet mode implicitly selects "Y" to all the screens that requires your agreement to proceed.

# Scenarios

Scenarios are sets of log collections for specific issues that you may encounter. For example, the IO scenario captures I/O-related information on SQL Server and the OS, the GeneralPerf scenario captures performance related statistics for SQL Server, the Setup scenario gets SQL Server installation/setup logs, and so on.

## 0. Basic scenario

Collects snapshot or static logs. It captures information on:

- Running drivers on the system
- System information (systeminfo.exe)
- Miscellaneous sql configuration (sp_configure, database files and configuration, log info, etc)
- Processes running on the system (Tasklist.exe)
- Current active PowerPlan
- Installed Windows Hotfixes
- OS disk information
- Running filter drivers
- Event logs (system and application in both .CSV and .TXT formats)
- IPConfig, DNSClientInfo, and TCP and UDP endpoints
- SQL Errorlogs
- SQL Agent logs
- Polybase logs
- Azure Arc Agent logs (if SQL Server enabled for Azure Arc)
- Performance Monitor counters for SQL Server instance and general OS counters - just a few snapshots for a few seconds.
- [AlwaysOn_health.xel](https://docs.microsoft.com/sql/database-engine/availability-groups/windows/always-on-extended-events#bkmk_alwayson_health)
- [MSSQLSERVER_SQLDIAG.xel](https://docs.microsoft.com/sql/database-engine/availability-groups/windows/always-on-health-diagnostics-log)
- [SQL VSS Writer Log (SQL Server 2019 and later)](https://docs.microsoft.com/sql/relational-databases/backup-restore/sql-server-vss-writer-logging)
- [SQL Assessment API](https://docs.microsoft.com/sql/tools/sql-assessment-api/sql-assessment-api-overview) log

## 1. GeneralPerf scenario

Collects all the Basic scenario logs as well as some long-term, continuous logs (until SQL LogScout is stopped).

- Basic scenario
- Performance Monitor counters for SQL Server instance and general OS counters
- Extended Event (XEvent) trace captures batch-level starting/completed events, errors  warnings, log growth/shrink, lock escalation and timeout, deadlock, login/logout
- List of actively-running SQL traces and Xevents
- Snapshots of SQL DMVs that track waits/blocking and high CPU queries
- Query Data Store (QDS) info (if that is active)
- Tempdb contention info from SQL DMVs/system views
- Linked Server metadata (SQL DMVs/system views)
- Service Broker configuration information (SQL DMVs/system views)

 *Note:* If you combine GeneralPerf with DetailedPerf scenario, then the GeneralPerf will be disabled and only DetailedPerf will be collected.

## 2. DetailedPerf scenario

Collects the same info that the GeneralPerf scenario. The difference is in the Extended event trace

- GeneralPerf scenario (includes Basic scenario)
- Extended Event trace captures same as GeneralPerf. In addition in the same trace it captures statement level starting/completed events and actual XML query plans (for completed queries)

## 3. Replication scenario

Collects all the Basic scenario logs plus SQL Replication, Change Data Capture (CDC) and Change Tracking (CT) information

- Basic Scenario
- Replication, CDC, CT diagnostic info (SQL DMVs/system views). This is captured both at startup and shutdown so a comparative analysis can be performed on the data collected during SQL LogScout execution.

## 4. AlwaysOn scenario

Collects all the Basic scenario logs as well as Always On configuration information from DMVs

- Basic scenario
- Always On diagnostic info (SQL DMVs/system views)
- Always On [Data Movement Latency Xevent ](https://techcommunity.microsoft.com/t5/sql-server-support/troubleshooting-data-movement-latency-between-synchronous-commit/ba-p/319141) and the AG topology XML file required for [AG latency](https://learn.microsoft.com/archive/blogs/psssql/aglatency-report-tool-introduction) analysis.
- Core Xevents trace (RPC and Batch started and completed, login/logout, errors)
- Performance Monitor counters for SQL Server instance and general OS counters
- Windows Cluster HKEY_LOCAL_MACHINE\Cluster registry hive in .HIV format
- [Windows Cluster logs](https://docs.microsoft.com/en-us/powershell/module/failoverclusters/get-clusterlog) in local server time
- Cluster resource information (name, nodes, groups, shared volumes, network interfaces, quorum, physical disks, etc)
  
## 5. Network Trace scenario

Collects a network trace from the machine where SQL LogScout is running. The output is an .ETL file. This is achieved with a combination of Netsh trace and Logman built-in Windows utilities.

## 6. Memory

Collects all the Basic scenario logs and a couple of additional memory-related data points

- Basic scenario
- Performance Monitor counters for SQL Server instance and general OS counters
- Memory diagnostic info from SQL DMVs/system views

## 7. Generate Memory Dumps scenario

Allows you to collect one or more memory dumps of SQL Server family of processes (SQL Server, SSAS, SSIS, SSRS, SQL Agent). If multiple dumps are selected, the number of dumps and the interval between them is customizable. Also the type of dump is offered as a choice (mini dump, mini with indirect memory, filtered (SQL Server), full.

## 8. Windows Performance Recorder (WPR) scenario

Allows you to collect a [Windows Performance Recorder](https://docs.microsoft.com/windows-hardware/test/wpt/introduction-to-wpr) trace. Here you can execute a sub-scenario depending on the knd of problem you want to address. These sub-scenarios are:

- CPU - collects Windows performance data about CPU-related activities performed by processes and the OS
- Heap and Virtual memory - collects Windows performance data about memory allocations (virtual and heap memory)performed by processes and the OS
- Disk and File I/O - collects Windows performance data about I/O performance performed by processes and the OS
- Filter drivers - collects performance data about filter driver activity on the system (OS)

| :warning: WARNING          |
|:---------------------------|
| WPR traces collect system-wide diagnostic data. Thus a large set of trace data may be collected and it may take several minutes to stop the trace. Therefore the WPR trace is limited to 45 seconds of data collection. You can specify a custom value between 3 and 45 seconds.|

## 9. Setup scenario

Collects Setup logs and allows analysis of installation issues of SQL Server components:

- Basic scenario logs
- All SQL Setup logs from the \Setup Bootstrap\ folders on the system.

## 10. BackupRestore scenario

Collects various logs related to backup and restore activities in SQL Server. These logs include:

- Basic scenario
- Backup and restore-related Xevent (backup_restore_progress_trace  and batch start end xevents)
- Enables backup and restore related TraceFlags to produce information in the Errorlog
- Performance Monitor counters for SQL Server instance and general OS counters
- SQL VSS Writer Log (on SQL Server 2019 and later)
- VSS Admin (OS) logs for VSS backup-related scenarios

## 11. IO scenario

Collects the Basic scenario logs and several logs related to disk I/O activity:

- Basic scenario
- [StorPort trace](https://docs.microsoft.com/archive/blogs/askcore/tracing-with-storport-in-windows-2012-and-windows-8-with-kb2819476-hotfix) which gathers information about the device driver activity connected to STORPORT.SYS.  
- High_IO_Perfstats - collects data from disk I/O related DMVs in SQL Server
- Performance Monitor counters for SQL Server instance and general OS counters

## 12. LightPerf

Collects everything that the GeneralPerf scenario does (includes Basic scenario), _except_ the Extended Event traces. This is intended to capture light perf data to get an overall system performance view without detailed execution of queries (no XEvents).

## 13. ProcessMonitor

Collects a [Process Monitor](https://docs.microsoft.com/en-us/sysinternals/downloads/procmon) (Procmon) log to help with troubleshooting specific file or registry related issues. This collector requires that you have Procmon downloaded and unzipped in a folder of your choice. SQL LogScout will prompt you to provide the path to that folder. You don't need to wrap the path in quotes even if there are spaces in the path name. 

# Output folders

**Output folder**: All the diagnostic log files are collected in the \output (or \output_ddMMyyhhmmss) folder. These include Perfmon log (.BLG), event logs, system information, extended event (.XEL), etc. By default this folder is created in the same location where SQL LogScout files reside (present directory). However a user can choose to collect data on a different disk volume and folder. This can be done by following the prompt for a non-default drive and directory or by using the CustomOutputPath parameter ([Parameters](#parameters))

**Internal folder**: The \output\internal folder stores error log files for each individual data collector. Most of those files are empty (zero bytes) if the specific collector did not generate any errors or console output. If those files are not empty, they contain information about whether a particular data-collector failed or produced some result (not necessarily failure). If a collector fails, then an error will be logged in the corresponding error file in this folder, as well as the error text will be displayed during execution as warning. The \internal folder also stores the main activity log file for SQL LogScout (##SQLLOGSCOUT.LOG).  If the main script produces some errors in the console, those are redirected to a file ##STDERR.LOG which is also moved to \internal folder at the end of execution if the file is non-zero in size.

## Schedule SQL LogScout as a task to automate execution

SQL LogScout can be scheduled as a task in Windows Task Scheduler. This allows you to run SQL LogScout at a defined time even if you are not physically present to do this manually. You can schedule the task to execute once or daily at the same time. To schedule a task use the `ScheduleSQLLogScoutAsTask.ps1` script. The script accepts the following parameters:

- **-LogScoutPath** - this is the executable path to the `SQL_LogScout.cmd` file. It defaults to the current path you are running the script from.
- **-Scenario** - you can input the scenario (s) you want to collect data for. Examples include "Basic", "GeneralPerf" or "Basic+Replication". For more information see [Scenarios](#scenarios)
- **-SQLInstance** - this is the name of the SQL Server instance to connect to. Please provide correct name (for example: "MACHINE1\SQLINST1")
- **-OutputPath** - you specify whether you want a custom output path by providing the path itself, or specify 'UsePresentDir' to use the current folder as a base under which an output folder will be created. This corresponds to `CustomOutputPath` in SQL LogScout [Parameters](#parameters). Do NOT use `PromptForCustomDir` for a scheduled task, because you have to present to accept this on the screen.
- **-CmdTaskName** - this is the name of the task as it appears in Windows Task Scheduler. This is an optional parameter that allows you to create multiple scheduled tasks. If you pass a value which already exists, you will be prompted to overwrite or keep original task. Default value is "SQL LogScout Task".
- **-DeleteFolderOrNew** - this controls the sub-folder name where the output data goes. Options for it are `DeleteDefaultFolder`, which causes the default \output folder to be deleted and recreated or `NewCustomFolder` which causes the creation of a new folder in the format \output_ddMMyyhhmmss. For more information see, `DeleteExistingOrCreateNew` in [Parameters](#parameters).
- **-StartTime** - this is the start time of the scheduled task in Windows Task Scheduler. If the `-Once` parameter is used together with this, only a single execution will occur on the specified date and time. If `-Daily` parameter is used, then the task will execute daily on the specified hour. Valid format for this parameter is  "yyyy-MM-dd hh:mm:ss" (in quotes). For example: "2020-10-27 19:26:00"
- **-DurationInMins** - this specifies how long, in minutes, the SQL LogScout will run before it stops. Specify an integer value for example "10". This will calculate the stop time for SQL LogScout and pass it as a parameter to `DiagStopTime`.
- **-Once** - you can request the scheduled task to run a single time at the specified `-StartTime`. Use either this parameter or `-Daily` but not both.
- **-Daily** - you can request the scheduled task to run daily  at the specified `-StartTime` (the date part will be ignored for daily executions, after the very first one, only the time is honored). Use either this parameter or `-Once` but not both.
- **-CreateCleanupJob** -  Without a cleanup task, the SQL LogScout Windows Task will remain after collection. This parameter allows you to create a job that will clean itself up after invocation. This is an optional parameter that defaults to $null. If you provide $true, you must also pass `-CleanupJobTime`. If $false is passed, we will not create the job or prompt and manual cleanup is required.
- **-CleanupJobTime** - Required only when `-CreateCleanupJob` is used. The date passed to this field should be after the LogScout collection has completed, which is not between `-StartTime` and the endtime calculated from `-DurationInMins`. If you pass a date to this field, you must also pass $true to `-CreateCleanupJob`. If `-CreateCleanupJob` is omitted, the value passed to this parameter is ignored.
- **-LogonType** - Defaults to null and prompts the user for input if omitted. Accepted values are `Interactive` and `S4U`. This is the value passed to create both the main SQL LogScout job and the Cleanup Job (if applicable). If `Interactive` is selected, when the job runs make sure your user is logged in. If set to `S4U`, make sure your account is logged out when the task is scheduled to run (screen lock is not considered a logout). If the user omits the parameter, the task will prompt Yes or No as to whether you will be logged in. The input will be used to determine if `Interactive` or `S4U` is used. For more information, see [Task Schedule Logon Type](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/ne-taskschd-task_logon_type).

Here is an example of how to schedule

```powershell
.\ScheduleSQLLogScoutAsTask.ps1  -StartTime "2022-08-30 10:55" -Scenario GeneralPerf -SQLInstance SQLmachine\sql2017 -DeleteFolderOrNew DeleteDefaultFolder -Once -DurationInMins 3
```

If the scheduled task with the same name already exists, you will get the option to overwrite it with a new one.

# Logging

### ##SQLLOGSCOUT.LOG file

SQL LogScout logs the flow of activity in two files ##SQLLOGSCOUT.LOG and ##SQLLOGSCOUT_DEBUG.LOG. The activity flow on the console is logged in ##SQLLOGSCOUT.LOG. The design goal is to match what the user sees on the screen with what is written in the log file so that a post-mortem analysis can be performed. This file can be found in the **\Internal** folder

### ##STDERR.LOG file
If SQL LogScout main script generates any runtime errors that were not caught, those will be written to the ##STDERR.LOG file and the contents of that file is displayed in the console after the main script completes execution. The ##STDERR.LOG file is stored in the root directory where SQL LogScout runs because any failures that occur early before the creation of an output folder may be logged in this file. This file can be found together with the scripts (**\Bin** folder).

### ##SQLLOGSCOUT_DEBUG.LOG file
This file contains everything the ##SQLLOGSCOUT.LOG contains, but also adds many debug-level, detailed messages. These can be used to investigate any issues with SQL LogScout and examine the flow of execution in detail. This file can be found in the **\Internal** folder. In addition, the %temp% folder stores copies of ##SQLLOGSCOUT_DEBUG.LOG from the last 10 executions.

# Permissions

- **Windows**: Local Administrator permissions on the machine are required to collect most system-related logs

- **SQL Server**: VIEW SERVER STATE and ALTER ANY EVENT SESSION are the minimum required permission for collecting the SQL Server data. If you are using the Replication scenario, the account running SQLLogScout will need the `db_datareader` permission on the distribution database(s).

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
Get-ChildItem -Path "c:\SQL_LogScout\*" -Recurse -Include "*.ps*1" | Get-AuthenticodeSignature | Format-List -Property Path, Status, StatusMessage, SignerCertificate
```

For each file:

1. Confirm the path and filename in `Path` property.
2. Confirm that `Status` property is **`Valid`**. For any `Status` other than `Valid`, `StatusMessage` property provides an description of the issue.
3. Confirm the details of `SignerCertificate` property to indicate that Microsoft Corporation is the subject of the certificate.

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
2021-09-10 11:03:26.230	INFO	SQL LogScout version: 4.5.33 
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
2021-09-10 11:04:17.055	INFO	Executing Collector: Xevent_Core_AddSession 
2021-09-10 11:04:17.088	INFO	Executing Collector: Xevent_General_AddSession 
2021-09-10 11:04:19.130	INFO	Executing Collector: Xevent_General_Target 
2021-09-10 11:04:19.152	INFO	Executing Collector: Xevent_General_Start 
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
2021-09-10 11:04:25.788	INFO	Executing Collector: Xevent_CoreAddSesion 
2021-09-10 11:04:25.809	INFO	Executing Collector: Xevent_AlwaysOn_Data_Movement 
2021-09-10 11:04:27.853	INFO	Executing Collector: AlwaysOn_Data_Movement_target 
2021-09-10 11:04:27.881	INFO	Executing Collector: AlwaysOn_Data_Movement_Start 
2021-09-10 11:04:27.922	INFO	Executing Collector: AlwaysOnHealthXevent 
2021-09-10 11:04:28.007	INFO	Collecting logs for 'BackupRestore' scenario 
2021-09-10 11:04:28.023	INFO	Executing Collector: Xevent_BackupRestore_AddSession 
2021-09-10 11:04:30.070	INFO	Executing Collector: EnableTraceFlag 
2021-09-10 11:04:30.088	INFO	Executing collector: SetVerboseSQLVSSWriterLog
2021-09-10 11:04:30.159	WARN	To enable SQL VSS VERBOSE loggging, the SQL VSS Writer service must be restarted now and when shutting down data collection. This is a very quick process.
2021-09-10 11:04:36.697	INFO	Console Input: n 
2021-09-10 11:04:36.705	INFO	You have chosen not to restart SQLWriter Service. No verbose logging will be collected for SQL VSS Writer (2019 or later)
2021-09-10 11:04:36.737	INFO	Executing Collector: VSSAdmin_Providers 
2021-09-10 11:04:36.778	INFO	Executing Collector: VSSAdmin_Shadows 
2021-09-10 11:04:37.832	INFO	Executing Collector: VSSAdmin_Shadowstorage 
2021-09-10 11:04:37.873	INFO	Executing Collector: VSSAdmin_Writers 
2021-09-10 11:04:37.924	INFO	Please type 'STOP' to terminate the diagnostics collection when you finished capturing the issue 
2021-09-10 11:04:43.012	INFO	StopCollection Console input: stop 
2021-09-10 11:04:43.014	INFO	Shutting down the collector 
2021-09-10 11:04:43.032	INFO	Executing shutdown command: Xevents_Stop 
2021-09-10 11:04:43.073	INFO	Executing shutdown command: Xevents_Alwayson_Data_Movement_Stop 
2021-09-10 11:04:43.098	INFO	Executing shutdown command: Disable_BackupRestore_Trace_Flags
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
2021-09-10 11:06:04.879	INFO	Executing Collector: PerfStatsSnapshotShutdown
2021-09-10 11:06:04.888	INFO	Executing collector: GetSQLVSSWriterLog
2021-09-10 11:06:04.900 INFO	SQLWriter Service has been restarted
2021-09-10 11:06:04.917	INFO	Waiting 3 seconds to ensure files are written to and closed by any program including anti-virus... 
2021-09-10 11:06:08.518	INFO	Ending data collection 
2021-09-10 11:06:08.533	WARN	Launching cleanup and exit routine... please wait 
2021-09-10 11:06:13.780	INFO	Thank you for using SQL LogScout! 

Checking for console execution errors logged into .\##STDERR.LOG...
Removed .\##STDERR.LOG which was 0 bytes
```

# Test Suite

The test suite is intended to be used by developers. The set of tests will grow over time. To run a test, simply execute the `RunIndividualTest.bat` under the \TestingInfrastructure folder in command prompt. To execute overall testing you can call `powershell -File ConsistentQualityTests.ps1 <SqlServerName>`

- RunIndividualTest.bat invokes individual tests after a single SQL LogScout run
- FileCountAndTypeValidation.ps1 - confirm existence of output logs from SQL LogScout (smoke tests)
- ConsistentQualityTests.ps1 - this runs an overall test that exercises all scenarios individually and with some combinations. To run this you have to pass below parameters.  
- Scenarios_Test.ps1 - a file used by ConsistentQualityTests.ps1 to call individual tests

## Execute overall test suite

Here is an example of how to execute the entire test suite:

```Powershell
cd .\Bin\TestingInfrastructure 
.\ConsistentQualityTests.ps1 -ServerName <SQL Instance Name> -SqlNexusPath <PathToSQLNexusExe> -SqlNexusDb <SQLNexusDbName> -DoProcmonTest <$True/$False>
```

The full test suite may take a about 2 hours to run and test all the scenarios.

Parameters details used in above command:

- ServerName - This is an optional parameter. You can pass the SQL Instance name from which you collect data. It is strongly recommended to pass the server name. If omitted, the only data collected will be Windows related.
- SqlNexusPath - This is an optional parameter but can be used if you wish to verify the logs collected are imported properly through SQL Nexus. This value points SQLNexus.exe to the path local to the server where SQL LogScout is run.
- SqlNexusDb - This parameter is required if the `<SqlNexusPath`>parameter is passed, otherwise it is optional.  The value passed is used to create the SQLNexus database name which is created within SQL Server and caches the Nexus objects associated to the scenarios collected in SQL LogScout.
- DoProcmonTest - This is an optional $True or $False parameter with a default value of $False. You can call it explicitly and set it to $True in case you want to run the scenario "ProcessMonitor". You must have [ProcessMonitor](https://learn.microsoft.com/en-us/sysinternals/downloads/procmon) installed on your system and you will be prompted to provide a folder location of where the tool is installed. The test will therefore not be fully automated, but will wait on tester input

In case you want to Cancel execution, hit CTRL+C - you may have to do that multiple times to catch in the right spot in the process. 

| :warning: WARNING          |
|:---------------------------|
| Don't close the Command prompt window or you may orphan some processes.|


## Examples of SQL LogScout Tests

```bash
cd TestingInfrastructure 
RunIndividualTest.bat
```

## Sample testing output

```output
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

# Script to cleanup an incomplete shutdown of SQL LogScout

SQL LogScout was designed to shutdown and clean-up any processes that it launched during its execution. There are 3 levels of clean-up: regular shutdown, a cleanup action upon exit, and a final process termination of any processes launched by SQL LogScout during collection. However, on rare occasions you may be left with processes still running. One such occasion is if you closed the Commmand Prompt window before SQL LogScout completed.

| :warning: WARNING          |
|:---------------------------|
| Do **not** close the Command Prompt or PowerShell window where SQL LogScout is running because this may leave a data collector running on your system. You can safely do so when SQL LogScout completes.|

If you end up in this situation, you can use the `CleanupIncompleteShutdown.ps1` to terminate any left-over processes, as long as you specify the correct SQL Server instance that was used by SQL LogScout.

To execute the script, do the following:

```powershell
powershell -File CleanupIncompleteShutdown.ps1
```

Here is a sample output:

```output
======================================================================================
This script is designed to clean up SQL LogScout processes that may have be left behind if SQL LogScout was closed incorrectly

======================================================================================

Discovered the following SQL Server instance(s)


ID      SQL Instance Name
--      ----------------
0        DbServerMachine\SQL2016
1        DbServerMachine\SQL2017
2        DbServerMachine

Please select the ID for SQL instance.: 2

Launching cleanup routine... please wait
Executing STOP_SQLLogScout_Xevent session. It will stop the Xevent trace in case it was found to be running ...
Executing STOP_SQLLogScout_AlwaysOn_Data_Movement. It will stop the Xevent trace in case it was found to be running ...
Executing Disable_BackupRestore_Trace_Flags It will disable the trace flags they were found to be enabled...
Executing PerfmonStop. It will stop Perfmon started by SQL LogScout in case it was found to be running ...
Executing NettraceStop. It will stop the network trace in case it was found to be running...
Executing WPR -cancel. This will stop all WPR traces in case any was found running...
Executing STOP storport. It will stop a stoport trace if it was found to be running...
```

