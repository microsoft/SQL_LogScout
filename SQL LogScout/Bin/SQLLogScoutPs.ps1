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

    #servername\instnacename is an optional parameter since there is code that auto-discovers instances
    [Parameter(Position=2)]
    [string] $ServerName = [String]::Empty,

    #Optional parameter to use current directory or specify a different drive and path 
    [Parameter(Position=3,HelpMessage='Specify a valid path for your output folder, or type "UsePresentDir"')]
    [string] $CustomOutputPath = "PromptForCustomDir",

    #scenario is an optional parameter since there is a menu that covers for it if not present
    [Parameter(Position=4,HelpMessage='Choose DeleteDefaultFolder|NewCustomFolder|ServerBasedFolder')]
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

    #scenario is an optional parameter since there is a menu that covers for it if not present. Always keep as the last parameter
    [Parameter(Position=8,Mandatory=$false,HelpMessage='Test parameter that should not be used for most collections')]
    [string] $DisableCtrlCasInput = "False"
)


#=======================================Globals =====================================

if ($global:gDisableCtrlCasInput -eq "False")
{
    [console]::TreatControlCAsInput = $true
}

[string]$global:present_directory = ""
[string]$global:output_folder = ""
[string]$global:internal_output_folder = ""
[string]$global:custom_user_directory = ""  # This is for log folder selected by user other that default
[string]$global:userLogfolderselected = ""
[string]$global:perfmon_active_counter_file = "LogmanConfig.txt"
[string]$global:restart_sqlwriter = ""
[bool]$global:perfmon_counters_restored = $false
[string]$NO_INSTANCE_NAME = "no_instance_found"
[string]$global:sql_instance_conn_str = $NO_INSTANCE_NAME #setting the connection sting to $NO_INSTANCE_NAME initially
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
[string] $global:gDiagStartTime
[string] $global:gDiagStopTime
[string] $global:gInteractivePrompts
[string] $global:gDisableCtrlCasInput


$global:ScenarioBitTbl = @{}
$global:ScenarioMenuOrdinals = @{}

#hashtable to use for lookups bits to names and reverse

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
[System.Data.SqlClient.SqlConnection] $global:SQLConnection
[System.Data.SqlClient.SqlCommand] $global:SQLCcommand

#=======================================Start of \OUTPUT and \INTERNAL directories and files Section
#======================================== START of Process management section
if ($PSVersionTable.PSVersion.Major -gt 4) { Import-Module .\GUIHandler.psm1 }
Import-Module .\CommonFunctions.psm1
#=======================================End of \OUTPUT and \INTERNAL directories and files Section
#======================================== END of Process management section


#======================================== START OF NETNAME + INSTANCE SECTION - Instance Discovery
Import-Module .\InstanceDiscovery.psm1
#======================================== END OF NETNAME + INSTANCE SECTION - Instance Discovery


#======================================== START of Console LOG SECTION
Import-Module .\LoggingFacility.psm1
#======================================== END of Console LOG SECTION

#======================================== START of File Attribute Validation SECTION
Import-Module .\Confirm-FileAttributes.psm1
#======================================== END of File Attribute Validation SECTION

#======================================== START of File Attribute Validation SECTION
Import-Module .\SQLLogScoutPs.psm1 -DisableNameChecking
#======================================== END of File Attribute Validation SECTION


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
           $DisableCtrlCasInputHlpStr = "`n[-DisableCtrlCasInput <string>] "
       
        

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
               8 { $DisableCtrlCasInputHlpStr = $DisableCtrlCasInputHlpStr + "< " + $ValidArguments +" >"}
           }

   

       $HelpString = "`nSQL_LogScout `n" `
       + $scenarioHlpStr `
       + $serverInstHlpStr `
       + $customOutputPathHlpStr `
       + $delExistingOrCreateNewHlpStr `
       + $DiagStartTimeHlpStr`
       + $DiagStopTimeHlpStr `
       + $InteractivePromptsHlpStr ` + "`n" `
       + "`nExample: `n" `
       + "  SQL_LogScout.cmd GeneralPerf+AlwaysOn+BackupRestore DbSrv `"d:\log`" DeleteDefaultFolder `"01-01-2000`" `"04-01-2021 17:00`" Quiet`n"


           Microsoft.PowerShell.Utility\Write-Host $HelpString
        }
        else {
    

            Microsoft.PowerShell.Utility\Write-Host "

            sql_logscout.cmd [-Scenario <string[]>] [-ServerInstanceConStr <string>] [-CustomOutputPath <string>] [-DeleteExistingOrCreateNew <string>] [-DiagStartTime <string>] [-DiagStopTime <string>] [-InteractivePrompts <string>] [<CommonParameters>]
        
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
            Microsoft.PowerShell.Utility\Write-Host "               SQL_LogScout.cmd"

            Microsoft.PowerShell.Utility\Write-Host "
                B. Execute SQL LogScout using a specific scenario. This command starts the diagnostic collection with 
                the GeneralPerf scenario." -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "
            Microsoft.PowerShell.Utility\Write-Host "               SQL_LogScout.cmd GeneralPerf" 
            
            Microsoft.PowerShell.Utility\Write-Host "
                C. Execute SQL LogScout by specifying folder creation option
                Execute SQL LogScout using the DetailedPerf Scenario, specifies the Server name, 
                use the present directory and folder option to delete the default \output folder if present" -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "
            Microsoft.PowerShell.Utility\Write-Host "               SQL_LogScout.cmd DetailedPerf SQLInstanceName ""UsePresentDir""  ""DeleteDefaultFolder"" "
            
            Microsoft.PowerShell.Utility\Write-Host "
                D. Execute SQL LogScout with start and stop times
            
                The following example collects the AlwaysOn scenario against the ""DbSrv""  default instance, 
                prompts user to choose a custom path and a new custom subfolder, and sets the stop time to some time in the future, 
                while setting the start time in the past to ensure the collectors start without delay. " -ForegroundColor Green

            Microsoft.PowerShell.Utility\Write-Host " "
            Microsoft.PowerShell.Utility\Write-Host "               SQL_LogScout.cmd AlwaysOn ""DbSrv"" ""PromptForCustomDir""  ""NewCustomFolder""  ""2000-01-01 19:26:00"" ""2020-10-29 13:55:00""  "


            Microsoft.PowerShell.Utility\Write-Host "
                Note: All parameters are required if you need to specify the last parameter. For example, if you need to specify stop time, 
                the prior parameters have to be passed.

                E. Execute SQL LogScout with multiple scenarios and in Quiet mode

                The example collects logs for GeneralPerf, AlwaysOn, and BackupRestore scenarios against the a default instance, 
                re-uses the default \output folder but creates it in the ""D:\Log"" custom path, and sets the stop time to some time in the future, 
                while setting the start time in the past to ensure the collectors start without delay. It also automatically accepts the prompts 
                by using Quiet mode and helps a full automation with no interaction." -ForegroundColor Green

                Microsoft.PowerShell.Utility\Write-Host " "
                Microsoft.PowerShell.Utility\Write-Host "               SQL_LogScout.cmd GeneralPerf+AlwaysOn+BackupRestore ""DbSrv"" ""d:\log"" ""DeleteDefaultFolder"" ""01-01-2000"" ""04-01-2021 17:00"" Quiet "
            
            Microsoft.PowerShell.Utility\Write-Host "
                Note: Selecting Quiet mode implicitly selects ""Y"" to all the screens that requires your agreement to proceed."  -ForegroundColor Green
        
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
        $DelExistingOrCreateNewParamArr = @("DeleteDefaultFolder","NewCustomFolder","ServerBasedFolder")
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
        if([DateTime]::TryParse($DiagStartTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dtStartOut) -eq $false)
        {
            Write-LogError "Parameter 'DiagStartTime' accepts DateTime values (e.g. `"2021-07-07 17:14:00`"). Current value '$DiagStartTime' is incorrect."
            PrintHelp -ValidArguments "yyyy-MM-dd hh:mm:ss" -index 5
            return $false
        }
        else 
        {
            $global:gDiagStartTime = $DiagStartTime
        }
    }
    

    #validate DiagStopTime parameter
    if (($DiagStopTime -ne "0000") -and ($false -eq [String]::IsNullOrWhiteSpace($DiagStopTime)))
    {
        [DateTime] $dtStopOut = New-Object DateTime
	[int]$durationInMinutes = 0;
	if([int]::TryParse($DiagStopTime,[ref]$durationInMinutes))
	{
		$DiagStopTime = (Get-Date).AddMinutes($durationInMinutes)		
	}
        if([DateTime]::TryParse($DiagStopTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dtStopOut) -eq $false)
        {
            Write-LogError "Parameter 'DiagStopTime' accepts DateTime values (e.g. `"2021-07-07 17:14:00`"). Current value '$DiagStopTime' is incorrect."
            PrintHelp -ValidArguments "yyyy-MM-dd hh:mm:ss" -index 6
            return $false
        }
        else
        {
            $global:gDiagStopTime  = $DiagStopTime
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

    #validate DisableCtrlCasInput parameter
    
    if ($DisableCtrlCasInput -eq "True")
    {
        #If DisableCtrlCasInput is true, then pass as true
        $global:gDisableCtrlCasInput = "True"
    }

    else 
    {
        #any value other than True or null/whitespace, set value to false.
        $global:gDisableCtrlCasInput = "False"
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

