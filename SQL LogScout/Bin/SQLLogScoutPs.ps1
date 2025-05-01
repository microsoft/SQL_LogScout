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
    [PSCustomObject] $ExecutionCountObject = $(New-Object -TypeName PSObject -Property @{CurrentExecCount = 0; RepeatCollection= -1; OverwriteFldr = $null})
  
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
[int] $global:is_clustered = 2 # 0 = not clustered, 1 = clustered, 2 = unknown/starting state
[String]$global:dump_helper_arguments = "none"
[String]$global:dump_helper_cmd = ""
[String]$global:dump_helper_outputfolder = ""
[int] $global:dump_helper_count = 1
[int] $global:dump_helper_delay = 0
[bool] $global:is_connection_encrypted = $true
[string] $global:stopFilePath = "logscout.stop"

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

#======================================== Import-Module replace should happen before any import-module calls
#Remove Import-Module if it is already custom loaded.
Remove-Item -Path Function:\Import-Module -ErrorAction  SilentlyContinue

Import-Module .\CustomImportModule.psm1 -Force -Global
#======================================== END of Import-Module replace should happen before any import-module calls

# Get all files starting with SQLScript and ending with .psm1
$scriptFiles = ( 'SQLScript_AlwaysOnDiagScript',
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
'SQLScript_Repl_Metadata_Collector',
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
'SQLLogScoutPs',
'Confirm-FileAttributes',
#'LoggingFacility', #should be imported first to load write functions
'InstanceDiscovery',
'CommonFunctions'
#'GUIHandler' #will be imported separately since it requires PS 4 and up to function
)

# Import each module
foreach ($file in $scriptFiles) {
    try {
        Write-LogDebug "Processing $file"
        $fileName = "$file.psm1"
        $fileFullName = "$PSScriptRoot\$fileName"

        Write-LogDebug "Importing file : $fileFullName"

        Import-Module -Name $fileFullName -Force -ErrorAction Stop

        Write-LogDebug "Imported module: $($fileName)"
    } catch {
        Write-LogWarning $("="*75)
        Write-LogWarning "Please check if SQL LogScout module files are missing, quarantined or locked by"
        Write-LogWarning "an anti-virus program or another service/application."
        Write-LogWarning $("="*75)

        Write-LogError "Failed to import module: $($fileName). Error: $_"
        exit
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
           }

   

       $HelpString = "`nSQL_LogScout `n" `
       + $scenarioHlpStr `
       + $serverInstHlpStr `
       + $customOutputPathHlpStr `
       + $delExistingOrCreateNewHlpStr `
       + $DiagStartTimeHlpStr`
       + $DiagStopTimeHlpStr `
       + $InteractivePromptsHlpStr `
       + $ExecutionCountHlpStr ` + "`n" `
       + "`nExample: `n" `
       + "  SQL_LogScout.ps1 -Scenario `"GeneralPerf+AlwaysOn+BackupRestore`" -ServerName `"DbSrv`" -CustomOutputPath `"d:\log`" -DeleteExistingOrCreateNew `"DeleteDefaultFolder`" -DiagStartTime `"01-01-2000`" -DiagStopTime`"04-01-2021 17:00`" -InteractivePrompts `"Quiet`" `n"


           Microsoft.PowerShell.Utility\Write-Host $HelpString
        }
        else {
    

            Microsoft.PowerShell.Utility\Write-Host "

            SQL_LogScout.ps1 [-Scenario <string[]>] [-ServerInstanceConStr <string>] [-CustomOutputPath <string>] [-DeleteExistingOrCreateNew <string>] [-DiagStartTime <string>] [-DiagStopTime <string>] [-InteractivePrompts <string>] [<CommonParameters>]
        
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
     if ($help -eq $true) #""/?",  "?",--help",
     {
        PrintHelp -ValidArguments "" -brief_help $false
        return $false
     }



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
