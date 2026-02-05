## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.


<#
.SYNOPSIS
    SQL LogScout allows you to collect diagnostic logs from your SQL Server system to help resolve technical problems.
.DESCRIPTION
.LINK 
https://github.com/microsoft/SQL_LogScout#examples

.EXAMPLE
   SQL_LogScout.cmd

.EXAMPLE
    SQL_LogScout.cmd GeneralPerf

.EXAMPLE
    SQL_LogScout.cmd DetailedPerf SQLInstanceName "UsePresentDir"  "DeleteDefaultFolder"
.EXAMPLE
   SQL_LogScout.cmd AlwaysOn "DbSrv" "PromptForCustomDir"  "NewCustomFolder"  "2000-01-01 19:26:00" "2020-10-29 13:55:00"
.EXAMPLE
   SQL_LogScout.cmd GeneralPerf+AlwaysOn+BackupRestore "DbSrv" "d:\log" "DeleteDefaultFolder" "01-01-2000" "04-01-2021 17:00" Quiet
#>


#=======================================Script parameters =====================================
param
(
    # DebugLevel parameter is deprecated
    # SQL LogScout will generate *_DEBUG.LOG with verbose level 5 logging for all executions
    # to enable debug messages in console, modify $global:DEBUG_LEVEL in LoggingFacility.ps1
    
    #help parameter is optional parameter used to print the detailed help "/?, ? also work"
    [Parameter(ParameterSetName = 'help',Mandatory=$false)]
    [Parameter(Position=0)]
    [switch] $help,

    #Scenario an optional parameter that tells SQL LogScout what data to collect
    [Parameter(Position=1,HelpMessage='Choose a plus-sign separated list of one or more of: Basic,GeneralPerf,DetailedPerf,Replication,AlwaysOn,Memory,DumpMemory,WPR,Setup,NoBasic. Or MenuChoice')]
    [string[]] $Scenario=[String]::Empty,

    #servername\instancename is an optional parameter since there is code that auto-discovers instances
    [Parameter(Position=2)]
    [string] $ServerName = [String]::Empty,

    #Optional parameter to use current directory or specify a different drive and path 
    [Parameter(Position=3,HelpMessage='Specify a valid path for your output folder, or type "UsePresentDir"')]
    [string] $CustomOutputPath = "PromptForCustomDir",

    #scenario is an optional parameter since there is a menu that covers for it if not present
    [Parameter(Position=4,HelpMessage='Choose DeleteDefaultFolder|NewCustomFolder')]
    [string] $DeleteExistingOrCreateNew = [String]::Empty,

    #specify start time for diagnostic
    [Parameter(Position=5,HelpMessage='Format is: "2020-10-27 19:26:00"')]
    [string] $DiagStartTime = "0000",
    
    #specify end time for diagnostic
    [Parameter(Position=6,HelpMessage='Format is: "2020-10-27 19:26:00"')]
    [string] $DiagStopTime = "0000",

    #specify quiet mode for any Y/N prompts
    [Parameter(Position=7,HelpMessage='Choose Quiet|Noisy')]
    [string] $InteractivePrompts = "Noisy",

    #specify the current repeated execution count 
    [Parameter(Position=8,HelpMessage='$ExecutionCountObject contains the current execution count and repeat collection count')]
    [PSCustomObject] $ExecutionCountObject = $(New-Object -TypeName PSObject -Property @{CurrentExecCount = 0; RepeatCollection= -1; OverwriteFldr = $null}),

    # AdditionalOptionsEnabled parameter is an optional parameter that allows the user to specify additional options
    [Parameter(Position=9,HelpMessage='Choose one or more options separated by +')]
    [string] $AdditionalOptionsEnabled = ""
)


#=======================================Globals =====================================

[string]$global:present_directory = ""
[string]$global:output_folder = ""
[string]$global:internal_output_folder = ""
[string]$global:custom_user_directory = ""  # This is for log folder selected by user other that default
[string]$global:userLogfolderselected = ""
[string]$global:perfmon_active_counter_file = "LogmanConfig.txt"
[string]$global:restart_sqlwriter = ""
[bool]$global:perfmon_counters_restored = $false
[string]$global:NO_INSTANCE_NAME = "_no_instance_found_"
[string]$global:sql_instance_conn_str = $global:NO_INSTANCE_NAME #setting the connection sting to $global:NO_INSTANCE_NAME initially
[System.Collections.ArrayList]$global:processes = New-Object -TypeName System.Collections.ArrayList
[System.Collections.ArrayList] $global:ScenarioChoice = @()
[bool] $global:stop_automatically = $false
[string] $global:xevent_target_file = "xevent_LogScout_target"
[string] $global:xevent_session = "xevent_SQLLogScout"
[string] $global:xevent_alwayson_session = "SQLLogScout_AlwaysOn_Data_Movement"
[bool] $global:xevent_on = $false
[bool] $global:perfmon_is_on = $false
[bool] $global:perfmon_scenario_enabled = $false
[bool] $global:sqlwriter_collector_has_run = $false
[string] $global:app_version = ""
[string] $global:host_name = $env:COMPUTERNAME
[string] $global:wpr_collector_name = ""
[bool] $global:instance_independent_collection = $false
[int] $global:scenario_bitvalue  = 0
[int] $global:sql_major_version = -1
[int] $global:sql_major_build = -1
[long] $global:SQLVERSION = -1
[string] $global:procmon_folder = ""
[bool] $global:gui_mode = $false
[bool] $global:gui_Result = $false
[String[]]$global:varXevents = "xevent_AlwaysOn_Data_Movement", "xevent_core", "xevent_detailed" ,"xevent_general"
[bool] $global:is_secondary_read_intent_only = $false
[bool]$global:allow_static_data_because_service_offline = $false
[string]$global:sql_instance_service_status = ""
[String]$global:dump_helper_arguments = "none"
[String]$global:dump_helper_cmd = ""
[String]$global:dump_helper_outputfolder = ""
[int] $global:dump_helper_count = 1
[int] $global:dump_helper_delay = 0
[bool] $global:is_connection_encrypted = $true
[string] $global:stopFilePath = "logscout.stop"
[bool] $global:miscDiagRanAlready = $false

#constants
[string] $global:BASIC_NAME = "Basic"
[string] $global:GENERALPERF_NAME = "GeneralPerf"
[string] $global:DETAILEDPERF_NAME = "DetailedPerf"
[string] $global:REPLICATION_NAME = "Replication"
[string] $global:ALWAYSON_NAME = "AlwaysOn"
[string] $global:NETWORKTRACE_NAME = "NetworkTrace"
[string] $global:MEMORY_NAME = "Memory"
[string] $global:DUMPMEMORY_NAME = "DumpMemory"
[string] $global:WPR_NAME = "WPR"
[string] $global:SETUP_NAME = "Setup"
[string] $global:BACKUPRESTORE_NAME = "BackupRestore"
[string] $global:IO_NAME = "IO"
[string] $global:LIGHTPERF_NAME = "LightPerf"
[string] $global:NOBASIC_NAME = "NoBasic"
[string] $global:PROCMON_NAME = "ProcessMonitor"
[string] $global:SSB_DBMAIL_NAME = "ServiceBrokerDBMail"
[string] $global:Never_Ending_Query_NAME = "NeverEndingQuery"


#MenuChoice and NoBasic will not go into this array as they don't need to show up as menu choices
[string[]] $global:ScenarioArray = @(
    $global:BASIC_NAME,
    $global:GENERALPERF_NAME,
    $global:DETAILEDPERF_NAME,
    $global:REPLICATION_NAME,
    $global:ALWAYSON_NAME,
    $global:NETWORKTRACE_NAME,
    $global:MEMORY_NAME,
    $global:DUMPMEMORY_NAME,
    $global:WPR_NAME,
    $global:SETUP_NAME,
    $global:BACKUPRESTORE_NAME,
    $global:IO_NAME,
    $global:LIGHTPERF_NAME,
    $global:PROCMON_NAME,
    $global:SSB_DBMAIL_NAME,
    $global:Never_Ending_Query_NAME)

# ValidAdditionalOptions is an array of valid addition options that can be used with the -AdditionalOptionsEnabled parameter
[string[]] $global:ValidAdditionalOptions = @(
    "NoClusterLogs", 
    "TrackCausality",
    "RedoTasksPerfStats",
    "FullTextSearchLogs")


# documenting the bits
# 000000000000000001 (1)   = Basic
# 000000000000000010 (2)   = GeneralPerf
# 000000000000000100 (4)   = DetailedPerf
# 000000000000001000 (8)   = Replication
# 000000000000010000 (16)  = alwayson
# 000000000000100000 (32)  = networktrace
# 000000000001000000 (64)  = memory
# 000000000010000000 (128) = DumpMemory
# 000000000100000000 (256) = WPR
# 000000001000000000 (512) = Setup
# 000000010000000000 (1024)= BackupRestore
# 000000100000000000 (2048)= IO
# 000001000000000000 (4096)= LightPerf
# 000010000000000000 (8192)= NoBasicBit
# 000100000000000000 (16384)= ProcmonBit
# 001000000000000000 (32768)= ServiceBrokerDBMail
# 010000000000000000 (65536)= neverEndingQuery
# 100000000000000000 (131072) = futureBit

[int] $global:basicBit         = 1
[int] $global:generalperfBit   = 2 
[int] $global:detailedperfBit  = 4
[int] $global:replBit          = 8
[int] $global:alwaysonBit      = 16
[int] $global:networktraceBit  = 32
[int] $global:memoryBit        = 64
[int] $global:dumpMemoryBit    = 128
[int] $global:wprBit           = 256
[int] $global:setupBit         = 512
[int] $global:BackupRestoreBit = 1024
[int] $global:IOBit            = 2048
[int] $global:LightPerfBit     = 4096
[int] $global:NoBasicBit       = 8192
[int] $global:ProcmonBit       = 16384
[int] $global:ssbDbmailBit     = 32768
[int] $global:neverEndingQBit  = 65536
[int] $global:futureScBit      = 131072

#globals to map script parameters into
[string[]] $global:gScenario
[string] $global:gServerName
[string] $global:gDeleteExistingOrCreateNew
$global:gDiagStopTime = New-Object -TypeName PSObject -Property @{DateAndOrTime = ""; Relative = $false}
$global:gDiagStartTime = New-Object -TypeName PSObject -Property @{DateAndOrTime = ""; Relative = $false}
[string] $global:gInteractivePrompts
$global:gExecutionCount = New-Object -TypeName PSObject -Property @{CurrentExecCount = 0; RepeatCollection= 0; OverwriteFldr = $false}
[string[]] $global:gAdditionalOptionsEnabled = @()

#global to hold the base date time
$global:baseDateTime = [DateTime]::MinValue

#global to store sqlcmd full path
$global:sqlcmdPath = ""

#hashtable to use for lookups bits to names and reverse
$global:ScenarioBitTbl = @{}
$global:ScenarioMenuOrdinals = @{}

$global:ScenarioBitTbl.Add($global:BASIC_NAME                , $global:basicBit)
$global:ScenarioBitTbl.Add($global:GENERALPERF_NAME          , $global:generalperfBit)
$global:ScenarioBitTbl.Add($global:DETAILEDPERF_NAME         , $global:detailedperfBit)
$global:ScenarioBitTbl.Add($global:REPLICATION_NAME          , $global:replBit)
$global:ScenarioBitTbl.Add($global:ALWAYSON_NAME             , $global:alwaysonBit)
$global:ScenarioBitTbl.Add($global:NETWORKTRACE_NAME         , $global:networktraceBit)
$global:ScenarioBitTbl.Add($global:MEMORY_NAME               , $global:memoryBit)
$global:ScenarioBitTbl.Add($global:DUMPMEMORY_NAME           , $global:dumpMemoryBit)
$global:ScenarioBitTbl.Add($global:WPR_NAME                  , $global:wprBit)
$global:ScenarioBitTbl.Add($global:SETUP_NAME                , $global:setupBit)
$global:ScenarioBitTbl.Add($global:BACKUPRESTORE_NAME        , $global:BackupRestoreBit)
$global:ScenarioBitTbl.Add($global:IO_NAME                   , $global:IOBit)
$global:ScenarioBitTbl.Add($global:LIGHTPERF_NAME            , $global:LightPerfBit)
$global:ScenarioBitTbl.Add($global:NOBASIC_NAME              , $global:NoBasicBit)
$global:ScenarioBitTbl.Add($global:PROCMON_NAME              , $global:ProcmonBit)
$global:ScenarioBitTbl.Add($global:SSB_DBMAIL_NAME           , $global:ssbDbmailBit)
$global:ScenarioBitTbl.Add($global:Never_Ending_Query_NAME   , $global:neverEndingQBit)
$global:ScenarioBitTbl.Add("FutureScen"                      , $global:futureScBit)

#hashtable for menu ordinal numbers to be mapped to bits

$global:ScenarioMenuOrdinals.Add(0  , $global:ScenarioBitTbl[$global:BASIC_NAME]        )
$global:ScenarioMenuOrdinals.Add(1  , $global:ScenarioBitTbl[$global:GENERALPERF_NAME]  )
$global:ScenarioMenuOrdinals.Add(2  , $global:ScenarioBitTbl[$global:DETAILEDPERF_NAME] )
$global:ScenarioMenuOrdinals.Add(3  , $global:ScenarioBitTbl[$global:REPLICATION_NAME]  )
$global:ScenarioMenuOrdinals.Add(4  , $global:ScenarioBitTbl[$global:ALWAYSON_NAME]     )
$global:ScenarioMenuOrdinals.Add(5  , $global:ScenarioBitTbl[$global:NETWORKTRACE_NAME] )
$global:ScenarioMenuOrdinals.Add(6  , $global:ScenarioBitTbl[$global:MEMORY_NAME]       )
$global:ScenarioMenuOrdinals.Add(7  , $global:ScenarioBitTbl[$global:DUMPMEMORY_NAME]   )
$global:ScenarioMenuOrdinals.Add(8  , $global:ScenarioBitTbl[$global:WPR_NAME]          )
$global:ScenarioMenuOrdinals.Add(9  , $global:ScenarioBitTbl[$global:SETUP_NAME]        )
$global:ScenarioMenuOrdinals.Add(10 , $global:ScenarioBitTbl[$global:BACKUPRESTORE_NAME])
$global:ScenarioMenuOrdinals.Add(11 , $global:ScenarioBitTbl[$global:IO_NAME]           )
$global:ScenarioMenuOrdinals.Add(12 , $global:ScenarioBitTbl[$global:LIGHTPERF_NAME]    )
$global:ScenarioMenuOrdinals.Add(13 , $global:ScenarioBitTbl[$global:PROCMON_NAME]      )
$global:ScenarioMenuOrdinals.Add(14 , $global:ScenarioBitTbl[$global:SSB_DBMAIL_NAME]   )
$global:ScenarioMenuOrdinals.Add(15 , $global:ScenarioBitTbl[$global:Never_Ending_Query_NAME]   )

# synchronizable hashtable (collection) to be used for thread synchronization
[hashtable] $global:xevent_ht = @{}
$global:xevent_ht.IsSynchronized = $true

#SQLSERVERPROPERTY list will be popluated during intialization
$global:SQLSERVERPROPERTYTBL = @{}

$global:SqlServerVersionsTbl = @{}

#SQLCMD objects reusing the same connection to query SQL Server where needed is more efficient.
[System.Data.Odbc.OdbcConnection] $global:SQLConnection
[System.Data.Odbc.OdbcCommand] $global:SQLCcommand

#List of SQL Script files to clean upon exit
$global:tblInternalSQLFiles = @()

#SQLInstanceType is a global hashtable to map the type of SQL instance. Enums are not well supported in PS 4.0 due to using module
$global:SQLInstanceType = @{
    "StartingValue" = 0
    "NamedInstance" = 1
    "DefaultInstanceVNN" = 2
    "DefaultInstanceHostName" = 3
}


#=======================================Start of Module Import secion

#======================================== START of Console LOG SECTION
Import-Module .\LoggingFacility.psm1 -Force -Global
#======================================== END of Console LOG SECTION



#======================================== END of Import-Module replace should happen before any import-module calls


# Get all files starting with SQLScript and ending with .psm1
$scriptFiles = ('LoggingFacility',
'SQLScript_AlwaysOnDiagScript',
'SQLScript_ChangeDataCapture',
'SQLScript_Change_Tracking',
'SQLScript_FullTextSearchMetadata',
'SQLScript_HighCPU_perfstats',
'SQLScript_High_IO_Perfstats',
'SQLScript_linked_server_config',
'SQLScript_MiscDiagInfo',
'SQLScript_NeverEndingQuery_perfstats',
'SQLScript_ProfilerTraces',
'SQLScript_QueryStore',
'SQLScript_Replication_Metadata_Collector',
'SQLScript_SQL_Server_Mem_Stats',
'SQLScript_SQL_Server_PerfStats',
'SQLScript_SQL_Server_PerfStats_Snapshot',
'SQLScript_SSB_DbMail_Diag',
'SQLScript_TempDB_and_Tran_Analysis',
'SQLScript_xevent_AlwaysOn_Data_Movement',
'SQLScript_xevent_backup_restore',
'SQLScript_xevent_core',
'SQLScript_xevent_detailed',
'SQLScript_xevent_general',
'SQLScript_xevent_servicebroker_dbmail',
'SqlVersionsTable',
'InstanceDiscovery',
'SQLLogScoutCoreModule',
'Confirm-FileAttributes',
'InstanceDiscovery',
'CommonFunctions'
#'GUIHandler' #will be imported separately since it requires PS 4 and up to function
)

# Import each module
foreach ($file in $scriptFiles) {
    try {
        $fileName = "$file.psm1"
        $fileFullName = "$PSScriptRoot\$fileName"

        # import the module, make sure to stop on error and suppress warnings (e.g. unapproved verbs in function names warning)
        Import-Module -Name $fileFullName -Force -ErrorAction Stop -WarningAction SilentlyContinue

        Write-LogDebug "Imported file : $fileFullName"

    } catch {
        Write-LogWarning $("="*75)
        Write-LogWarning "Please check if SQL LogScout module files are missing, quarantined or locked by"
        Write-LogWarning "an anti-virus program or another service/application."
        Write-LogWarning $("="*75)

        Write-LogError "Failed to import module: $($fileName). Error: $_"
        Write-LogError "Some SQL LogScout functionality may not work due to import module failure."
    }
}


#Importing GUIHandler separately and only if PS version is 4 and up
if ($PSVersionTable.PSVersion.Major -gt 4) { Import-Module .\GUIHandler.psm1 }

#=======================================End of Module Import secion
function PrintHelp ([string]$ValidArguments ="", [int]$index=777, [bool]$brief_help = $true)
{
   Try
   { 
       if ($brief_help -eq $true)
       {

           $HelpStr = "`n[-Help <string>] " 
           $scenarioHlpStr = "`n[-Scenario <string[]>] "
           $serverInstHlpStr = "`n[-ServerName <string>] " 
           $customOutputPathHlpStr = "`n[-CustomOutputPath <string>] "
           $delExistingOrCreateNewHlpStr = "`n[-DeleteExistingOrCreateNew <string>] "
           $DiagStartTimeHlpStr = "`n[-DiagStartTime <string>] "
           $DiagStopTimeHlpStr = "`n[-DiagStopTime <string>] "
           $InteractivePromptsHlpStr = "`n[-InteractivePrompts <string>] "
           $AdditionalOptionsHlpStr = "`n[-AdditionalOptionsEnabled <string>] "
       
        

           switch ($index) 
           {
               0 { $HelpStr = $HelpStr + "< " + $ValidArguments +" >"}
               1 { $scenarioHlpStr = $scenarioHlpStr + "< " + $ValidArguments +" >"}
               2 { $serverInstHlpStr = $serverInstHlpStr + "< " + $ValidArguments +" >"}
               3 { $customOutputPathHlpStr = $customOutputPathHlpStr + "< " + $ValidArguments +" >"}
               4 { $delExistingOrCreateNewHlpStr = $delExistingOrCreateNewHlpStr + "< " + $ValidArguments +" >"}
               5 { $DiagStartTimeHlpStr= $DiagStartTimeHlpStr + "< " + $ValidArguments +" >"}
               6 { $DiagStopTimeHlpStr = $DiagStopTimeHlpStr + "< " + $ValidArguments +" >"}
               7 { $InteractivePromptsHlpStr = $InteractivePromptsHlpStr + "< " + $ValidArguments +" >"}
               8 { $AdditionalOptionsHlpStr = $AdditionalOptionsHlpStr + "< " + $ValidArguments +" >"}
           }

   

       $HelpString = "`nSQL_LogScout `n" `
       + $scenarioHlpStr `
       + $serverInstHlpStr `
       + $customOutputPathHlpStr `
       + $delExistingOrCreateNewHlpStr `
       + $DiagStartTimeHlpStr`
       + $DiagStopTimeHlpStr `
       + $InteractivePromptsHlpStr `
       + $AdditionalOptionsHlpStr `
       + $ExecutionCountHlpStr ` + "`n" `
       + "`nExample: `n" `
       + "  SQL_LogScout.ps1 -Scenario `"GeneralPerf+AlwaysOn+BackupRestore`" -ServerName `"DbSrv`" -CustomOutputPath `"d:\log`" -DeleteExistingOrCreateNew `"DeleteDefaultFolder`" -DiagStartTime `"01-01-2000`" -DiagStopTime `"04-01-2021 17:00`" -InteractivePrompts `"Quiet`" -AdditionalOptionsEnabled `"NoClusterLogs+TrackCausality`" `n"


           Microsoft.PowerShell.Utility\Write-Host $HelpString
        }
        else {
    

            Microsoft.PowerShell.Utility\Write-Host "

            SQL_LogScout.ps1 [-Scenario <string[]>] [-ServerInstanceConStr <string>] [-CustomOutputPath <string>] [-DeleteExistingOrCreateNew <string>] [-DiagStartTime <string>] [-DiagStopTime <string>] [-InteractivePrompts <string>] [-AdditionalOptionsEnabled <string>] [<CommonParameters>]
        
            DESCRIPTION
                SQL LogScout allows you to collect diagnostic logs from your SQL Server 
                system to help you and Microsoft technical support engineers (CSS) to 
                resolve SQL Server technical incidents faster. 
            
            ONLINE HELP:    
                You can find help for SQLLogScout help PowerShell online  
                at https://github.com/microsoft/sql_logscout 

            EXAMPLES:
                A. Execute SQL LogScout (most common execution)
                This is the most common method to execute SQL LogScout which allows you to pick your choices from a menu of options " -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "
            Microsoft.PowerShell.Utility\Write-Host "               .\SQL_LogScout.ps1"

            Microsoft.PowerShell.Utility\Write-Host "
                B. Execute SQL LogScout using a specific scenario. This command starts the diagnostic collection with 
                the GeneralPerf scenario." -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "
            Microsoft.PowerShell.Utility\Write-Host "               .\SQL_LogScout.ps1 -Scenario `"GeneralPerf`"" 
            
            Microsoft.PowerShell.Utility\Write-Host "
                C. Execute SQL LogScout by specifying folder creation option
                Execute SQL LogScout using the DetailedPerf Scenario, specifies the Server name, 
                use the present directory and folder option to delete the default \output folder if present" -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "
            Microsoft.PowerShell.Utility\Write-Host "               .\SQL_LogScout.ps1 -Scenario `"DetailedPerf`" -ServerName `"SQLInstanceName`" -CustomOutputPath `"UsePresentDir`" -DeleteExistingOrCreateNew `"DeleteDefaultFolder`" "
            
            Microsoft.PowerShell.Utility\Write-Host "
                D. Execute SQL LogScout with start and stop times
            
                The following example collects the AlwaysOn scenario against the ""DbSrv""  default instance, 
                prompts user to choose a custom path and a new custom subfolder, and sets the stop time to some time in the future, 
                while setting the start time in the past to ensure the collectors start without delay. " -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "
            Microsoft.PowerShell.Utility\Write-Host "               .\SQL_LogScout.ps1 -Scenario `"AlwaysOn`" -ServerName `"DbSrv`" -CustomOutputPath `"PromptForCustomDir`"  -DeleteExistingOrCreateNew `"NewCustomFolder`"  -DiagStartTime `"2000-01-01 19:26:00`" -DiagStopTime `"2020-10-29 13:55:00`"  "
            
            Microsoft.PowerShell.Utility\Write-Host " 
                The following example collects the AlwaysOn scenario against the `"DbSrv`"  default instance, 
                uses the default \output folder under d:\log. Then uses relative time from current time to set the start time 15 minutes from now
                and stop time to one hour from now. " -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "    
            Microsoft.PowerShell.Utility\Write-Host "               .\SQL_LogScout.ps1 -Scenario `"AlwaysOn`" -ServerName `"DbSrv`" -CustomOutputPath `"d:\log`"  -DeleteExistingOrCreateNew `"DeleteDefaultFolder`"  -DiagStartTime `"+00:15:00`" -DiagStopTime `"+01:00:00`"  "


            Microsoft.PowerShell.Utility\Write-Host "
                Note: All parameters are required if you need to specify the last parameter when you use SQL_LogScout.cmd. For example, if you need to specify stop time, 
                the prior parameters have to be passed. However, if you use SQL_LogScout.ps1, parameters can be ommitted and passed without order

                E. Execute SQL LogScout with multiple scenarios and in Quiet mode

                The example collects logs for GeneralPerf, AlwaysOn, and BackupRestore scenarios against the a default instance, 
                re-uses the default \output folder but creates it in the ""D:\Log"" custom path, and sets the stop time to some time in the future, 
                while setting the start time in the past to ensure the collectors start without delay. It also automatically accepts the prompts 
                by using Quiet mode and helps a full automation with no interaction." -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "
            Microsoft.PowerShell.Utility\Write-Host "               .\SQL_LogScout.ps1 -Scenario `"GeneralPerf+AlwaysOn+BackupRestore`" -ServerName `"DbSrv`" -CustomOutputPath `"d:\log`" -DeleteExistingOrCreateNew `"DeleteDefaultFolder`" -DiagStartTime `"01-01-2000`" -DiagStopTime `"04-01-2021 17:00`" -InteractivePrompts `"Quiet`" "
            
        
            Microsoft.PowerShell.Utility\Write-Host "

                F. Execute SQL LogScout in continuous mode (RepeatCollections) and keep a set number of output folders

                The example collects data for Memory scenario without Basic logs against the default instance. It runs SQL LogScout 11 times 
                (one initial run and 10 repeat runs), and keeps only the last 2 output folders of the 11 collections. It starts collection 2 seconds after the initialization 
                and runs for 10 seconds." -ForegroundColor Green

                Microsoft.PowerShell.Utility\Write-Host " "
                Microsoft.PowerShell.Utility\Write-Host "               .\SQL_LogScout.ps1 -Scenario `"Memory+NoBasic`" -ServerName `".`" -RepeatCollections 10  -CustomOutputPath `"UsePresentDir`" -DeleteExistingOrCreateNew `"2`" -DiagStartTime `"+00:00:02`" -DiagStopTime `"+00:00:10`"  "
          
            Microsoft.PowerShell.Utility\Write-Host ""
        }

        #Exit the program at this point
        #exit
    }
   catch 
   {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
   }
}

function ValidateParameters ()
{
    #validate the help parameter
    #help parameter is optional parameter used to print the detailed help "/?, ? also work"
     if ($help -eq $true) #""/?",  "?",--help",
     {
        PrintHelp -ValidArguments "" -brief_help $false
        return $false
     }


    # store the parameters values in an array and print them in the debug log
    $paramValues = @(
        "Scenario: $Scenario",
        "ServerName: $ServerName",
        "CustomOutputPath: $CustomOutputPath",
        "DeleteExistingOrCreateNew: $DeleteExistingOrCreateNew",
        "DiagStartTime: $DiagStartTime",
        "DiagStopTime: $DiagStopTime",
        "InteractivePrompts: $InteractivePrompts",
        "ExecutionCountObject: $ExecutionCountObject",
        "AdditionalOptionsEnabled: $AdditionalOptionsEnabled"
    )
    # Convert any empty or null values from the array into blank strings
    $paramValues = $paramValues | ForEach-Object { if ([String]::IsNullOrEmpty($_)) { "" } else { $_ } }

    # Log the parameters passed to the script with each parameter on a new line
    Write-LogDebug "Parameters passed to the script:`r`n$($paramValues -join"`r`n")"


    #validate the Scenario parameter
    if ([String]::IsNullOrEmpty($Scenario) -eq $false)
    {

        $ScenarioArrayParam = $Scenario.Split('+')

        # use the global scenario Array , but also add the command-line only parameters MenuChoice and NoBasic as valid options
        [string[]] $localScenArray = $global:ScenarioArray
        $localScenArray+="MenuChoice"
        $localScenArray+="NoBasic"

        try 
        {
            foreach ($scenItem in $ScenarioArrayParam)
            {
                if (($localScenArray -notcontains $scenItem))
                {
                    Write-LogError "Parameter 'Scenario' only accepts these values individually or combined, separated by '+' (e.g Basic+AlwaysOn):`n $localScenArray. Current value '$scenItem' is incorrect."
                    PrintHelp -ValidArguments $localScenArray -index 1
                    return $false
                }
            }

            #assign $Scenario param to a global so it can be used later
            $global:gScenario = $Scenario

        }
        catch 
        {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }
    }
    else 
    {
        #assign $gScenario to empty string
        $global:gScenario = ""
    }
    
    #validate the $ServerName parameter - actually most of the validation happens later
    if ($null -ne $ServerName)
    {
        #assign $ServerName param to a global so it can be used later
        $global:gServerName = $ServerName
    }
    else 
    {
        Write-LogError "Parameter 'ServerName' accepts a non-null value. Value '$ServerName' is incorrect."
        PrintHelp -ValidArguments "<server\instance>" -index 2
        return $false
    }
    
        
    #validate CustomOutputPath parameter
    $global:custom_user_directory = $CustomOutputPath

    if ($true -eq [String]::IsNullOrWhiteSpace($global:custom_user_directory))
    {
        $global:custom_user_directory = "PromptForCustomDir"
    }

    $CustomOutputParamArr = @("UsePresentDir", "PromptForCustomDir")
    if( ($global:custom_user_directory -inotin $CustomOutputParamArr) -and ((Test-Path -Path $global:custom_user_directory -PathType Container) -eq $false) )
    {
        Write-LogError "Parameter 'CustomOutputPath' accepts an existing folder path OR one of these values: $CustomOutputParamArr. Value '$CustomOutputPath' is incorrect."
        PrintHelp -ValidArguments $CustomOutputParamArr -index 3
        return $false
    }
    
    #validate DeleteExistingOrCreateNew parameter
    if ([String]::IsNullOrWhiteSpace($DeleteExistingOrCreateNew) -eq $false)
    {
        $DelExistingOrCreateNewParamArr = @("DeleteDefaultFolder","NewCustomFolder")
        if($DeleteExistingOrCreateNew -inotin $DelExistingOrCreateNewParamArr)
        {
            Write-LogError "Parameter 'DeleteExistingOrCreateNew' can only accept one of these values: $DelExistingOrCreateNewParamArr. Current value '$DeleteExistingOrCreateNew' is incorrect."
            PrintHelp -ValidArguments $DelExistingOrCreateNewParamArr -index 4
            return $false
        }
        else
        {
            $global:gDeleteExistingOrCreateNew = $DeleteExistingOrCreateNew
        }
    }

    #validate DiagStartTime parameter
    if (($DiagStartTime -ne "0000") -and ($false -eq [String]::IsNullOrWhiteSpace($DiagStartTime)))
    {
        [DateTime] $dtStartOut = New-Object DateTime

        #regex for relative time: start with +, then optional 0 in front of hour up to 11 hours, 0 to 59 minutes, 0  to 59 seconds
        [string] $regexRelativeTime = "^\+(0?[0-9]|1[01]):[0-5][0-9]:[0-5][0-9]$"

        if($true -eq [DateTime]::TryParse($DiagStartTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dtStartOut))
        {
            $global:gDiagStartTime.DateAndOrTime = $DiagStartTime
            $global:gDiagStartTime.Relative = $false
        }
        elseif ($DiagStartTime -match $regexRelativeTime)
        {
            $global:gDiagStartTime.DateAndOrTime = $DiagStartTime
            $global:gDiagStartTime.Relative = $true
        }
        else
        {
            Write-LogError "Parameter 'DiagStartTime' accepts DateTime values (e.g. `"2021-07-07 17:14:00`") or relative start time less than 12 hours (e.g. `"+03:00:05`"). Current value '$DiagStartTime' is incorrect."
            PrintHelp -ValidArguments "`"yyyy-MM-dd hh:mm:ss`" or `"+hh:mm:ss`"" -index 5
            return $false
        }
    }

    #validate DiagStopTime parameter
    if (($DiagStopTime -ne "0000") -and ($false -eq [String]::IsNullOrWhiteSpace($DiagStopTime)))
    {
        [DateTime] $dtStopOut = New-Object DateTime
        
        #regex for relative time: start with +, then optional 0 in front of hour up to 11 hours, 0 to 59 minutes, 0  to 59 seconds
        [string] $regexRelativeTime = "^\+(0?[0-9]|1[01]):[0-5][0-9]:[0-5][0-9]$"

        #if the time is a valid datetime use it
        if($true -eq ([DateTime]::TryParse($DiagStopTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dtStopOut)))
        {
            $global:gDiagStopTime.DateAndOrTime = $DiagStopTime
            $global:gDiagStopTime.Relative = $false
        }   
        # if relative time e.g. "+03:50:12", then us it
        elseif (($DiagStopTime -match $regexRelativeTime )) 
        {
            $global:gDiagStopTime.DateAndOrTime = $DiagStopTime
            $global:gDiagStopTime.Relative = $true
        }
        else
        {
            Write-LogError "Parameter 'DiagStopTime' accepts DateTime values (e.g. `"2021-07-07 17:14:00`") or relative stop time less than 12 hours (e.g. `"+03:00:05`"). Current value '$DiagStopTime' is incorrect."
            PrintHelp -ValidArguments "`"yyyy-MM-dd hh:mm:ss`" or `"+hh:mm:ss`"" -index 6
            return $false
        }
    }

    #validate InteractivePrompts parameter
    if ($true -eq [String]::IsNullOrWhiteSpace($InteractivePrompts))
    {
        # reset the parameter to default value of Noisy if it was empty space or NULL
        $global:gInteractivePrompts = "Noisy" 
    }
    else 
    {
        $global:gInteractivePrompts = $InteractivePrompts
    }


    $InteractivePromptsParamArr = @("Quiet","Noisy")
    if($global:gInteractivePrompts -inotin $InteractivePromptsParamArr)
    {
        
        Write-LogError "Parameter 'InteractivePrompts' can only accept one of these values: $InteractivePromptsParamArr. Current value '$global:gInteractivePrompts' is incorrect."
        PrintHelp -ValidArguments $InteractivePromptsParamArr -index 7
        return $false
    }

    
    #set ExecutionCount parameter 

    #first set the value for OverwriteFldr based on user selection
    if ($global:gDeleteExistingOrCreateNew -eq "DeleteDefaultFolder")
    {
        $global:gExecutionCount.OverwriteFldr = $true
    }
    elseif ($global:gDeleteExistingOrCreateNew -eq "NewCustomFolder") 
    {
        $global:gExecutionCount.OverwriteFldr  = $false
    }

    #set the current execution count and repeat collection value
    if ($ExecutionCountObject.CurrentExecCount -lt 0)
    {
        $global:gExecutionCount.CurrentExecCount = 0
        $global:gExecutionCount.RepeatCollection = 0
    }
    else 
    {
        $global:gExecutionCount.CurrentExecCount = $ExecutionCountObject.CurrentExecCount
        $global:gExecutionCount.RepeatCollection = $ExecutionCountObject.RepeatCollection
    }
    

    # AdditionalOptionsEnabled parameter validation
    if ([String]::IsNullOrWhiteSpace($AdditionalOptionsEnabled) -eq $false) 
    {
        $AdditionalOptionsArray = $AdditionalOptionsEnabled -split '\+'
    
        foreach ($opt in $AdditionalOptionsArray) 
        {
            if ($global:ValidAdditionalOptions -notcontains $opt) 
            {
                Write-LogError "Parameter 'AdditionalOptionsEnabled' only accepts these values individually or combined, separated by '+' (e.g NoClusterLogs+TrackCausality): $($global:ValidAdditionalOptions -join ', '). Current value '$opt' is incorrect."
                PrintHelp -ValidArguments $global:ValidAdditionalOptions -index 8
                return $false
            }
        }
        # assign the AdditionalOptionsArray to a global variable so it can be used later
        $global:gAdditionalOptionsEnabled = $AdditionalOptionsArray

    } 
    else 
    {
        $global:gAdditionalOptionsEnabled = @()
    }

    # return true since we got to here
    return $true
}

#print copyright message
CopyrightAndWarranty

#validate parameters
$ret = ValidateParameters

#start program
if ($ret -eq $true)
{
    Start-SQLLogScout
}

# SIG # Begin signature block
# MIIsDAYJKoZIhvcNAQcCoIIr/TCCK/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBfKMPZZAxtT3MV
# Ju0l5c6yhm2M2BP0YSchcqVPxWZakaCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
# oOn9X5/TAAIAAAIOMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzEyMDNaFw0yNjA0MjYyMzIyMDNaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCfrw9mbjhRpCz0Wh+dmWU4nlBbeiDkl5NfNWFA9NWUAfDcSAEtWiJTZLIB
# Vt+E5kjpxQfCeObdxk0aaPKmhkANla5kJ5egjmrttmGvsI/SPeeQ890j/QO4YI4g
# QWpXnt8EswtW6xzmRdMMP+CASyAYJ0oWQMVXXMNhBG9VBdrZe+L1+DzLawq42AWG
# NoKL6JdGg21P0W11MN1OtwrhubgTqEBkgYp7m1Bt4EeOxBz0GwZfPODbLVTblACS
# LmGlfEePEdVamqIUTTdsrAKG8NM/gGx010AiqAv6p2sCtSeZpvV7fkppLY9ajdm8
# Yc4Kf1KNI3U5ZNMdLIDz9fA5Q+ulAgMBAAGjggWZMIIFlTApBgkrBgEEAYI3FQoE
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
# aG9yaXR5MB0GA1UdDgQWBBSbKJrguVhFagj1tSbzFntHGtugCTAOBgNVHQ8BAf8E
# BAMCB4AwVAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjM2MTY3KzUwNjA1MjCCAeYG
# A1UdHwSCAd0wggHZMIIB1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5j
# b20vcGtpaW5mcmEvQ1JML0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6
# Ly9jcmwxLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0
# dHA6Ly9jcmwyLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyG
# MWh0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5j
# cmyGMWh0dHA6Ly9jcmw0LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgy
# KS5jcmyGgb1sZGFwOi8vL0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQ
# S0lDU0NBMDEsQ049Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNl
# cnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0
# ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9u
# UG9pbnQwHwYDVR0jBBgwFoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgw
# FgYKKwYBBAGCN1sBAQYIKwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAKaBh/B8
# 42UPFqNHP+m2mYSY80orKjPVnXEb+KlCoxL1Ikl2DfziE1PBZXtCDbYtvyMqC9Pj
# KvB8TNz71+CWrO0lqV2f0KITMmtXiCy+yThBqLYvUZrbrRzlXYv2lQmqWMy0OqrK
# TIdMza2iwUp2gdLnKzG7DQ8IcbguYXwwh+GzbeUjY9hEi7sX7dgVP4Ls1UQNkRqR
# FcRPOAoTBZvBGhPSkOAnl9CShvCHfKrHl0yzBk/k/lnt4Di6A6wWq4Ew1BveHXMH
# 1ZT+sdRuikm5YLLqLc/HhoiT3rid5EHVQK3sng95fIdBMgj26SScMvyKWNC9gKkp
# emezUSM/c91wEhwwggjoMIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0G
# CSqGSIb3DQEBCwUAMDwxEzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/Is
# ZAEZFgNBTUUxEDAOBgNVBAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYw
# NTIxMTg1NDE0WjBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQB
# GRYDQU1FMRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQDJmlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL
# 9rNHnHDGfJgeuRIYO1LY/1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc
# 411WxA+Pv2rteAcz0eHMH36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaC
# IIWBXyEchv+sM9eKDsUOLdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8p
# XirIYOgM770CYOiZrcKHK7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p
# /6fksgEILptOKhx9c+iapiNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkr
# BgEEAYI3FQEEBQIDAgACMCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMAL
# I38/RzAdBgNVHQ4EFgQUllGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfww
# gfkGBysGAQUCAwUGCCsGAQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYB
# BAGCNxUGBgorBgEEAYI3CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgC
# AgYKKwYBBAGCN0ABAQYLKwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcV
# BQYKKwYBBAGCNxQCAgYKKwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEG
# CisGAQQBgjdbAgEGCisGAQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEG
# CisGAQQBgjdbBAIwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQD
# AgGGMBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwN
# p4x1AdEJCygwggFoBgNVHR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDov
# L2NybDIuYW1lLmdibC9jcmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5n
# YmwvY3JsL2FtZXJvb3QuY3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVy
# b290LmNybIaBqmxkYXA6Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxD
# Tj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1
# cmF0aW9uLERDPUFNRSxEQz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9i
# YXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUH
# AQEEggGdMIIBmTBHBggrBgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NlcnRzL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKG
# K2h0dHA6Ly9jcmwyLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYI
# KwYBBQUHMAKGK2h0dHA6Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9v
# dC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJv
# b3RfYW1lcm9vdC5jcnQwgaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290
# LENOPUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxD
# Tj1Db25maWd1cmF0aW9uLERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNl
# P29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQEL
# BQADggIBAFAQI7dPD+jfXtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTH
# b8BDfRN+AD0YEmeDB5HKQoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a
# /752hMIn+L4ZuyxVeSBpfwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9
# zAh9yRKKls2bziPEnxeOZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAm
# n3WCPWNFC1YTIIHw/mD2cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtz
# yb7fbNS1dE740re0COE67YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjF
# K1yMw4Ni5fMabcgmzRvSjAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bz
# MzsikuDW9xH10graZzSmPjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIz
# J6Q9G3NPCB+7KwX0OQmKyv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/y
# wO6SYSreVW+5Y0mzJutnBC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEIS
# RtShDZbuYymynY1un+RyfiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZ5TCCGeEC
# AQEwWDBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1F
# MRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDECEzYAAAIOeZeg6f1fn9MAAgAAAg4wDQYJ
# YIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKA2gxdJzIih
# Lt7G7AeRZ6uChlUGGXgnPMI/wemuOXmuMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAEKF2KbrDyx+i+VWgrJmFX9OK1l2iBtZgwa18Zp/s/kCY
# IgpiMOLqgCfALesb4fp97FZeGTM3AxyFuUqnmc8YiEArgtoqYITIbFq0lqtjFoWK
# F9T8npC/vRfxfG8z0/85etmyf7XvBrR+VX9GJg5yJ4R4pI8240jaMa4ryFiimny3
# yw5BcfzYE0B8N2KQ4xxgP6GGpGAcr1+CRT6iLYmpPCxZGWWEMiPk86XM7fA3KpCm
# e2+n5OlbNX4P6lDqW/DpVMk6IT43MX3nM2Uxj3CLGlZ8ahQRQLA0MRXzocR3FDY3
# 1K2zWEIqB/euaAyiRRdG6IjYMvo74xzOf21fsLsSgqGCF60wghepBgorBgEEAYI3
# AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCBqG5qe2MHgu2OSOsontyFRmguGLfWyzuHGuSZt51Ob
# VAIGaXNTHBuVGBMyMDI2MDIwNDE2MzUyOS4xMTJaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAACEUUYOZtDz/xs
# AAEAAAIRMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgxM1oXDTI2MTExMzE4NDgxM1owgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjZCMDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAz7m7MxAd
# L5Vayrk7jsMo3GnhN85ktHCZEvEcj4BIccHKd/NKC7uPvpX5dhO63W6VM5iCxklG
# 8qQeVVrPaKvj8dYYJC7DNt4NN3XlVdC/voveJuPPhTJ/u7X+pYmV2qehTVPOOB1/
# hpmt51SzgxZczMdnFl+X2e1PgutSA5CAh9/Xz5NW0CxnYVz8g0Vpxg+Bq32amktR
# Xr8m3BSEgUs8jgWRPVzPHEczpbhloGGEfHaROmHhVKIqN+JhMweEjU2NXM2W6hm3
# 2j/QH/I/KWqNNfYchHaG0xJljVTYoUKPpcQDuhH9dQKEgvGxj2U5/3Fq1em4dO6I
# h04m6R+ttxr6Y8oRJH9ZhZ3sciFBIvZh7E2YFXOjP4MGybSylQTPDEFAtHHgpksk
# eEUhsPDR9VvWWhekhQx3qXaAKh+AkLmz/hpE3e0y+RIKO2AREjULJAKgf+R9QnNv
# qMeMkz9PGrjsijqWGzB2k2JNyaUYKlbmQweOabsCioiY2fJbimjVyFAGk5AeYddU
# FxvJGgRVCH7BeBPKAq7MMOmSCTOMZ0Sw6zyNx4Uhh5Y0uJ0ZOoTKnB3KfdN/ba/e
# KHFeEhi3WqAfzTxiy0rMvhsfsXZK7zoclqaRvVl8Q48J174+eyriypY9HhU+ohgi
# Yi4uQGDDVdTDeKDtoC/hD2Cn+ARzwE1rFfECAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBRifUUDwOnqIcvfb53+yV0EZn7OcDAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# pEKdnMeIIUiU6PatZ/qbrwiDzYUMKRczC4Bp/XY1S9NmHI+2c3dcpwH2SOmDfdvI
# Iqt7mRrgvBPYOvJ9CtZS5eeIrsObC0b0ggKTv2wrTgWG+qktqNFEhQeipdURNLN6
# 8uHAm5edwBytd1kwy5r6B93klxDsldOmVWtw/ngj7knN09muCmwr17JnsMFcoIN/
# H59s+1RYN7Vid4+7nj8FcvYy9rbZOMndBzsTiosF1M+aMIJX2k3EVFVsuDL7/R5p
# pI9Tg7eWQOWKMZHPdsA3ZqWzDuhJqTzoFSQShnZenC+xq/z9BhHPFFbUtfjAoG6E
# DPjSQJYXmogja8OEa19xwnh3wVufeP+ck+/0gxNi7g+kO6WaOm052F4siD8xi6Uv
# 75L7798lHvPThcxHHsgXqMY592d1wUof3tL/eDaQ0UhnYCU8yGkU2XJnctONnBKA
# vURAvf2qiIWDj4Lpcm0zA7VuofuJR1Tpuyc5p1ja52bNZBBVqAOwyDhAmqWsJXAj
# YXnssC/fJkee314Fh+GIyMgvAPRScgqRZqV16dTBYvoe+w1n/wWs/ySTUsxDw4T/
# AITcu5PAsLnCVpArDrFLRTFyut+eHUoG6UYZfj8/RsuQ42INse1pb/cPm7G2lcLJ
# tkIKT80xvB1LiaNvPTBVEcmNSvFUM0xrXZXcYcxVXiYwggdxMIIFWaADAgECAhMz
# AAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0z
# MDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP9
# 7pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMM
# tY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gm
# U3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130
# /o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP
# 3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
# vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+A
# utuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz
# 1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
# EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/Zc
# UlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZy
# acaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJ
# KwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8G
# CCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3Mv
# UmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZF
# aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
# AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cB
# MSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7
# bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/
# SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2
# EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2Fz
# Lixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0
# /fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
# swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJ
# Xk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+
# pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
# 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCCAj4CAQEwggEBoYHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAKyp8q2VdgAq1VGkzd7PZ
# wV6zNc2ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0tosYwIhgPMjAyNjAyMDQxMDQ5NDJaGA8yMDI2MDIwNTEw
# NDk0MlowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7S2ixgIBADAHAgEAAgImszAH
# AgEAAgISITAKAgUA7S70RgIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZ
# CgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQA7
# IgFh9Y6/b+xP2aeSg2pQo/K3f7Ke8RIatNZf5yVsgc0mQScsY+dhP2jnYx2XR8h8
# 4G/1gRDm0ARudyYYnn0++qQxBJeILiACubTqLGKVKS+H+BBSinEkau6LXBJiBLw0
# tW8glOFysceSeMv8C14iH3L7KuyjI+Yc67+EAcm66gtrBl5VkhgteLp+1yQIVHNa
# LnZAn/fJHOBGt1K97Zl/AJulgrii6rIKBHBaujEcTp0+fiIlnaLVLgvQREwPyW32
# A8jpH7Q5S29dPFqs8xYFQ/chy0DWEsdZWzCb9ADQWe/St12Q7Kf26+vlJ4sHoljd
# 7Al++zetR43/NF8StISyMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTACEzMAAAIRRRg5m0PP/GwAAQAAAhEwDQYJYIZIAWUDBAIBBQCg
# ggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg
# 7AOTp/8QGBxZsgiXgEqsmc8xz4SfQDaIuTO30L3PCbEwgfoGCyqGSIb3DQEJEAIv
# MYHqMIHnMIHkMIG9BCAsrTOpmu+HTq1aXFwvlhjF8p2nUCNNCEX/OWLHNDMmtzCB
# mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACEUUYOZtD
# z/xsAAEAAAIRMCIEIPtAmOQ4ljBTF5yKpkNotGmgdzTRPv/JiYhDf6hGv7h+MA0G
# CSqGSIb3DQEBCwUABIICAIAnVSPdqy4o75fW/PjG57xt3nDvAKLQxHkFh0W+u67E
# Wb6u9N0NHPiITCPbDbvX9107es3+iX4GtEgP+0Yj3YCfKocV1bKHnZ9ajDcm7xnq
# YImXSq+NhXJIVyRqhFAK8bIsuJWzg+/IPTBDvSToAauKYs7v/Y1BOyV8MDxQSGxA
# 2ELm1AN4xpNy0N3zLSh/XrkDCujbisI04gdzxp2JSOaS/8xwGj95LvB9ds70+NJn
# Spn8zXczcEEJGNCpZqF42eVUWNIFIU4ZNZNz4/Va/9bSZYOFgtS67LRRr2c7/Qor
# lmfuIAh6UGnMgaGH8p25ke3N3QYQ7f0tg34ZRTcB9+6sEbaEpFFy+gs9DZhPY8eh
# jixLFzMVdwr9eoe0/O3JhYc8zCXaX51LfxQEafut7kmHwUURr7BV26SNUtcOfmcF
# OmuqrEtTgUL/X1jpRV/Bmo2BzrhbsCTHTupNCKEejhqHZHpA+9FfLKGdPGOcdQPs
# uJ0S0r9eZsjjfrsDRPbpTRYl97yqAhKyJ89f19Po8s3Q+TIVeJM9Worxj00WecU/
# 49R/ZHc+pt3ccfJhs+MHE4EXtfdp/79DPXSp41WDdAt8erR0jIViPfr8+yWk80Mg
# QhfDQSmwvAKvbH/AgsfQPH8KIPzxS9d7iZzJoK96/YoNsoXm5CUiwccUMxOAt9y1
# SIG # End signature block
