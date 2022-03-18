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
    [string] $InteractivePrompts = "Noisy"

    
)


#=======================================Globals =====================================
[console]::TreatControlCAsInput = $true
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

#constants
[string] $BASIC_NAME = "Basic"
[string] $GENERALPERF_NAME = "GeneralPerf"
[string] $DETAILEDPERF_NAME = "DetailedPerf"
[string] $REPLICATION_NAME = "Replication"
[string] $ALWAYSON_NAME = "AlwaysOn"
[string] $NETWORKTRACE_NAME = "NetworkTrace"
[string] $MEMORY_NAME = "Memory"
[string] $DUMPMEMORY_NAME = "DumpMemory"
[string] $WPR_NAME = "WPR"
[string] $SETUP_NAME = "Setup"
[string] $BACKUPRESTORE_NAME = "BackupRestore"
[string] $IO_NAME = "IO"
[string] $LIGHTPERF_NAME = "LightPerf"
[string] $NOBASIC_NAME = "NoBasic"
#MenuChoice and NoBasic will not go into this array as they don't need to show up as menu choices
[string[]] $global:ScenarioArray = @($BASIC_NAME,$GENERALPERF_NAME,$DETAILEDPERF_NAME,$REPLICATION_NAME,$ALWAYSON_NAME,$NETWORKTRACE_NAME,$MEMORY_NAME,$DUMPMEMORY_NAME,$WPR_NAME,$SETUP_NAME,$BACKUPRESTORE_NAME,$IO_NAME,$LIGHTPERF_NAME)

[int] $BasicScenId = 0
[int] $GeneralPerfScenId = 1
[int] $DetailedPerfScenId = 2
[int] $ReplicationScenId = 3
[int] $AlwaysOnScenId = 4
[int] $NetworkTraceScenId = 5
[int] $MemoryScenId = 6
[int] $DumpMemoryScenId = 7
[int] $WprScenId = 8
[int] $SetupScenId = 9
[int] $BackupRestoreScenId = 10
[int] $IOScenId = 11
[int] $LightPerfScenId = 12


# 000000000000001 (1)   = Basic
# 000000000000010 (2)   = GeneralPerf
# 000000000000100 (4)   = DetailedPerf
# 000000000001000 (8)   = Replication
# 000000000010000 (16)  = alwayson
# 000000000100000 (32)  = networktrace
# 000000001000000 (64)  = memory
# 000000010000000 (128) = DumpMemory
# 000000100000000 (256) = WPR
# 000001000000000 (512) = Setup
# 000010000000000 (1024)= BackupRestore
# 000100000000000 (2048)= IO
# 001000000000000 (4096)= LightPerf
# 010000000000000 (8192)= NoBasicBit
# 100000000000000 (16384)= futureBit


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
[int] $global:futureScBit      = 16384

#hashtable to use for lookups
$ScenarioBitTbl = @{
    Basic =         $global:basicBit;
    GeneralPerf =   $global:generalperfBit;
    DetailedPerf =  $global:detailedperfBit;
    Replication =   $global:replBit;     
    AlwaysOn =      $global:alwaysonBit;
    NetworkTrace =  $global:networktraceBit;
    Memory =        $global:memoryBit;  
    DumpMemory =    $global:dumpMemoryBit;
    WPR =           $global:wprBit;
    Setup =         $global:setupBit;
    BackupRestore = $global:BackupRestoreBit;
    IO =            $global:IOBit;
    LightPerf =     $global:LightPerfBit;
    NoBasic =       $global:NoBasicBit;
    FutureScen =    $global:futureScBit;
}



function InitAppVersion()
{
    $major_version = "4"
    $minor_version = "5"
    $build = "33"
    $global:app_version = $major_version + "." + $minor_version + "." + $build
    Write-LogInformation "SQL LogScout version: $global:app_version"
}




#=======================================Start of \OUTPUT and \INTERNAL directories and files Section
#======================================== START of Process management section
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


#======================================== Start OF Diagnostics Collection SECTION

function Replicate ([string] $char, [int] $cnt)
{
    $finalstring = $char * $cnt;
    return $finalstring;
}


function PadString (  [string] $arg1,  [int] $arg2 )
{
     $spaces = Replicate " " 256
     $retstring = "";
    if (!$arg1 )
    {
        $retstring = $spaces.Substring(0, $arg2);
     }
    elseif ($arg1.Length -eq  $arg2)
    {
        $retstring= $arg1;
       }
    elseif ($arg1.Length -gt  $arg2)
    {
        $retstring = $arg1.Substring(0, $arg2); 
        
    }
    elseif ($arg1.Length -lt $arg2)
    {
        $retstring = $arg1 + $spaces.Substring(0, ($arg2-$arg1.Length));
    }
    return $retstring;
}

function GetWindowsHotfixes () 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "WindowsHotfixes"
    $server = $global:sql_instance_conn_str

    Write-LogInformation "Executing Collector: $collector_name"

    try {    
        ##create output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The output_file is $output_file" -DebugLogLevel 3

        #collect Windows hotfixes on the system
        $hotfixes = Get-WmiObject -Class "win32_quickfixengineering"

        #in case CTRL+C is pressed
        HandleCtrlC

        [System.Text.StringBuilder]$rs_runningdrives = New-Object -TypeName System.Text.StringBuilder

        #Running drivers header
        [void]$rs_runningdrives.Append("-- Windows Hotfix List --`r`n")
        [void]$rs_runningdrives.Append("HotfixID       InstalledOn    Description                   InstalledBy  `r`n")
        [void]$rs_runningdrives.Append("-------------- -------------- ----------------------------- -----------------------------`r`n") 

        [int]$counter = 1
        foreach ($hf in $hotfixes) {
            $hotfixid = $hf["HotfixID"] + "";
            $installedOn = $hf["InstalledOn"] + "";
            $Description = $hf["Description"] + "";
            $InstalledBy = $hf["InstalledBy"] + "";
            $output = PadString  $hotfixid 15
            $output += PadString $installedOn  15;
            $output += PadString $Description 30;
            $output += PadString $InstalledBy  30;
            [void]$rs_runningdrives.Append("$output`r`n") 

            #in case CTRL+C is pressed
            HandleCtrlC
        }
        Add-Content -Path ($output_file) -Value ($rs_runningdrives.ToString())
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}



function GetEventLogs($server) 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true
    
    $collector_name = $MyInvocation.MyCommand
    Write-LogInformation "Executing Collector:" $collector_name

    $server = $global:sql_instance_conn_str

    try {
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)

        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        $sbWriteLogBegin = {

            [System.Text.StringBuilder]$TXTEvtOutput = New-Object -TypeName System.Text.StringBuilder
            [System.Text.StringBuilder]$CSVEvtOutput = New-Object -TypeName System.Text.StringBuilder

            # TXT header
            [void]$TXTEvtOutput.Append("Date Time".PadRight(25))
            [void]$TXTEvtOutput.Append("Type/Level".PadRight(16))
            [void]$TXTEvtOutput.Append("Computer Name".PadRight(17))
            [void]$TXTEvtOutput.Append("EventID".PadRight(8))
            [void]$TXTEvtOutput.Append("Source".PadRight(51))
            [void]$TXTEvtOutput.Append("Task Category".PadRight(20))
            [void]$TXTEvtOutput.Append("Username".PadRight(51))
            [void]$TXTEvtOutput.AppendLine("Message")
            [void]$TXTEvtOutput.AppendLine("-" * 230)

            # CSV header
            [void]$CSVEvtOutput.AppendLine("`"EntryType`",`"TimeGenerated`",`"Source`",`"EventID`",`"Category`",`"Message`"")
        }

        $sbWriteLogProcess = {
            
            [string]$TimeGenerated = $_.TimeGenerated.ToString("MM/dd/yyyy hh:mm:ss tt")
            [string]$EntryType = $_.EntryType.ToString()
            [string]$MachineName = $_.MachineName.ToString()
            [string]$EventID = $_.EventID.ToString()
            [string]$Source = $_.Source.ToString()
            [string]$Category = $_.Category.ToString()
            [string]$UserName = $_.UserName
            [string]$Message = ((($_.Message.ToString() -replace "`r") -replace "`n", " ") -replace "`t", " ")

            # during testing some usernames are blank so we handle just like Windows Event Viewer displaying "N/A"
            if ($null -eq $UserName) {$UserName = "N/A"}

            # during testing some categories are "(0)" and Windows Event Viewer displays "None", so we just mimic same behavior
            if ("(0)" -eq $Category) {$Category = "None"}

            # TXT event record
            [void]$TXTEvtOutput.Append($TimeGenerated.PadRight(25))
            [void]$TXTEvtOutput.Append($EntryType.PadRight(16))
            [void]$TXTEvtOutput.Append($MachineName.PadRight(17))
            [void]$TXTEvtOutput.Append($EventID.PadRight(8))
            [void]$TXTEvtOutput.Append($Source.PadRight(50).Substring(0, 50).PadRight(51))
            [void]$TXTEvtOutput.Append($Category.PadRight(20))            
            [void]$TXTEvtOutput.Append($UserName.PadRight(50).Substring(0, 50).PadRight(51))
            [void]$TXTEvtOutput.AppendLine($Message)

            # CSV event record
            [void]$CSVEvtOutput.Append('"' + $EntryType + '",')
            [void]$CSVEvtOutput.Append('"' + $TimeGenerated + '",')
            [void]$CSVEvtOutput.Append('"' + $Source + '",')
            [void]$CSVEvtOutput.Append('"' + $EventID + '",')
            [void]$CSVEvtOutput.Append('"' + $Category + '",')
            [void]$CSVEvtOutput.AppendLine('"' + $Message + '"')

            $evtCount++

            # write to the files every 10000 events
            if (($evtCount % 10000) -eq 0) {
                
                $TXTevtfile.Write($TXTEvtOutput.ToString())
                $TXTevtfile.Flush()
                [void]$TXTEvtOutput.Clear()

                $CSVevtfile.Write($CSVEvtOutput.ToString())
                $CSVevtfile.Flush()
                [void]$CSVEvtOutput.Clear()

                Write-LogInformation "   Produced $evtCount records in the EventLog"

                #in case CTRL+C is pressed
                HandleCtrlC

            }

        }
        
        $sbWriteLogEnd = {
            # at end of process we write any remaining messages, flush and close the file    
            if ($TXTEvtOutput.Length -gt 0){
                $TXTevtfile.Write($TXTEvtOutput.ToString())
            }
            $TXTevtfile.Flush()
            $TXTevtfile.Close()

            if ($CSVEvtOutput.Length -gt 0){
                $CSVevtfile.Write($CSVEvtOutput.ToString())
            }
            $CSVevtfile.Flush()
            $CSVevtfile.Close()
            
            Remove-Variable -Name "TXTEvtOutput"
            Remove-Variable -Name "CSVEvtOutput"

            Write-LogInformation "   Produced $evtCount records in the EventLog"
        }

        Write-LogInformation "Gathering Application EventLog in TXT and CSV format  "
        
        $TXTevtfile = New-Object -TypeName System.IO.StreamWriter -ArgumentList (($partial_output_file_name + "_EventLog_Application.out"), $false, [System.Text.Encoding]::ASCII)
        $CSVevtfile = New-Object -TypeName System.IO.StreamWriter -ArgumentList (($partial_output_file_name + "_EventLog_Application.csv"), $false, [System.Text.Encoding]::ASCII)

        [int]$evtCount = 0

        Get-EventLog -LogName Application -After (Get-Date).AddDays(-90) | ForEach-Object -Begin $sbWriteLogBegin -Process $sbWriteLogProcess -End $sbWriteLogEnd 2>> $error_file | Out-Null
        
        Write-LogInformation "Application EventLog in TXT and CSV format completed!"

        #in case CTRL+C is pressed
        HandleCtrlC
        
        Write-LogInformation "Gathering System EventLog in TXT and CSV format  "

        $TXTevtfile = New-Object -TypeName System.IO.StreamWriter -ArgumentList (($partial_output_file_name + "_EventLog_System.out"), $false, [System.Text.Encoding]::ASCII)
        $CSVevtfile = New-Object -TypeName System.IO.StreamWriter -ArgumentList (($partial_output_file_name + "_EventLog_System.csv"), $false, [System.Text.Encoding]::ASCII)

        [int]$evtCount = 0

        Get-EventLog -LogName System -After (Get-Date).AddDays(-90) | ForEach-Object -Begin $sbWriteLogBegin -Process $sbWriteLogProcess -End $sbWriteLogEnd 2>> $error_file | Out-Null
        
        Write-LogInformation "System EventLog in TXT and CSV format completed!"

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetPowerPlan($server) 
{
    #power plan
    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        $collector_name = "PowerPlan"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $power_plan_name = Get-WmiObject -Class win32_powerplan -Namespace root\cimv2\power | Where-Object IsActive -eq $true | Select-Object ElementName #|Out-File -FilePath $output_file
        Set-Content -Value $power_plan_name.ElementName -Path $output_file
        HandleCtrlC
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function Update-Coma([string]$in){
    if([string]::IsNullOrWhiteSpace($in)){
        return ""
    }else{
        return $in.Replace(",",".")
    }
}

function GetRunningDrivers() 
{
    <#
    .SYNOPSIS
        Get a list of running drivers in the system.
    .DESCRIPTION
        Writes a list of running drivers in the system in both TXT and CSV format.
    .PARAMETER FileName
        Specifies the file name to be written to. Extension TXT and CSV will be automatically added.
    .EXAMPLE
        .\Get-RunningDrivers"
#>


    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        
        $partial_output_file_name = CreatePartialOutputFilename ($server)

        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

    
        $collector_name = "RunningDrivers"
        $output_file_csv = ($partial_output_file_name + "_RunningDrivers.csv")
        $output_file_txt = ($partial_output_file_name + "_RunningDrivers.txt")
        Write-LogInformation "Executing Collector: $collector_name"
    
        Write-LogDebug $output_file_csv
        Write-LogDebug $output_file_txt
    
        #gather running drivers
        $driverproperties = Get-WmiObject Win32_SystemDriver | `
            where-object { $_.State -eq "Running" } | `
            Select-Object -Property PathName | `
            ForEach-Object { $_.Pathname.Replace("\??\", "") } | `
            Get-ItemProperty | `
            Select-Object -Property Length, LastWriteTime -ExpandProperty "VersionInfo" | `
            Sort-Object CompanyName, FileDescription

        [System.Text.StringBuilder]$TXToutput = New-Object -TypeName System.Text.StringBuilder
        [System.Text.StringBuilder]$CSVoutput = New-Object -TypeName System.Text.StringBuilder

        #CSV header
        [void]$CSVoutput.Append("ID,Module Path,Product Version,File Version,Company Name,File Description,File Size,File Time/Date String,`r`n")

        [int]$counter = 1

        foreach ($driver in $driverproperties) {
            [void]$TXToutput.Append("Module[" + $counter + "] [" + $driver.FileName + "]`r`n")
            [void]$TXToutput.Append("  Company Name:      " + $driver.CompanyName + "`r`n")
            [void]$TXToutput.Append("  File Description:  " + $driver.FileDescription + "`r`n")
            [void]$TXToutput.Append("  Product Version:   (" + $driver.ProductVersion + ")`r`n")
            [void]$TXToutput.Append("  File Version:      (" + $driver.FileVersion + ")`r`n")
            [void]$TXToutput.Append("  File Size (bytes): " + $driver.Length + "`r`n")
            [void]$TXToutput.Append("  File Date:         " + $driver.LastWriteTime + "`r`n")
            [void]$TXToutput.Append("`r`n`r`n")

            [void]$CSVoutput.Append($counter.ToString() + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.FileName)) + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.ProductVersion)) + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.FileVersion)) + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.CompanyName)) + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.FileDescription)) + ",")
            [void]$CSVoutput.Append($driver.Length.ToString() + ",")
            [void]$CSVoutput.Append($driver.LastWriteTime.ToString() + ",")
            [void]$CSVoutput.Append("`r`n")
        
            #in case CTRL+C is pressed
            HandleCtrlC

            $counter++
        }

        Add-Content -Path ($output_file_txt) -Value ($TXToutput.ToString())
        Add-Content -Path ($output_file_csv) -Value ($CSVoutput.ToString())
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return     
    }
}

function GetSQLSetupLogs(){
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "SQLSetupLogs"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
        Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\*\Bootstrap\' |
        ForEach-Object {

            [string]$SQLVersion = Split-Path -Path $_.BootstrapDir | Split-Path -Leaf
            [string]$DestinationFolder = $global:output_folder + $env:COMPUTERNAME + "_SQL" + $SQLVersion + "_Setup_Bootstrap"
        
            Write-LogDebug "_.BootstrapDir: $_.BootstrapDir" -DebugLogLevel 2
            Write-LogDebug "DestinationFolder: $DestinationFolder" -DebugLogLevel 2
        
            [string]$BootstrapLogFolder = $_.BootstrapDir + "Log\"

            if(Test-Path -Path $BootstrapLogFolder){

                Write-LogDebug "Executing: Copy-Item -Path ($BootstrapLogFolder) -Destination $DestinationFolder -Recurse"
                try
				{
                    Copy-Item -Path ($BootstrapLogFolder) -Destination $DestinationFolder -Recurse -ErrorAction Stop
                } 
				catch 
				{
                    Write-LogError "Error executing Copy-Item"
                    Write-LogError $_
                }

            } else {

                Write-LogWarning "Skipped copying SQL Setup logs from $BootstrapLogFolder"
                Write-LogWarning "Reason: Path is not valid."

            }
            
            #in case CTRL+C is pressed
            HandleCtrlC
        }
    } catch {

        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}
    
function MSDiagProcsCollector() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true


    #in case CTRL+C is pressed
    HandleCtrlC

    try 
    {

        #msdiagprocs.sql
        #the output is potential errors so sent to error file
        $collector_name = "MSDiagProcs"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    
}

function GetXeventsGeneralPerf() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        
        ##create output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
    

        #XEvents file: xevent_general.sql - GENERAL Perf
        $collector_name_core = "Xevent_Core_AddSession"
        $collector_name_general = "Xevent_General_AddSession"


        if ($true -eq $global:xevent_on)
        {
            Start-SQLCmdProcess -collector_name $collector_name_general -input_script_name "xevent_general" -has_output_results $false
        }
        else 
        {
            Start-SQLCmdProcess -collector_name $collector_name_core -input_script_name "xevent_core" -has_output_results $false
            Start-SQLCmdProcess -collector_name $collector_name_general -input_script_name "xevent_general" -has_output_results $false

        }
        

        Start-Sleep -Seconds 2

        #in case CTRL+C is pressed
        HandleCtrlC

        if ($true -ne $global:xevent_on)
        {
            #add Xevent target
            $collector_name = "Xevent_General_Target"
            $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $global:xevent_target_file + ".xel' " + ", max_file_size=(500), max_rollover_files=(50)); END" 

            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_add_target -has_output_results $false


            #in case CTRL+C is pressed
            HandleCtrlC

            #start the XEvent session
            $collector_name = "Xevent_General_Start"
            $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session]  ON SERVER STATE = START; END"

            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_start -has_output_results $false

            # set the Xevent has been started flag to be true
            $global:xevent_on = $true
        }

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetXeventsDetailedPerf() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
    

        #XEvents file: xevent_detailed.sql - Detailed Perf
       
        $collector_name_core = "Xevent_CoreAddSession"
        $collector_name_detailed = "Xevent_DetailedAddSession"

        if ($true -eq $global:xevent_on)
        {
            Start-SQLCmdProcess -collector_name $collector_name_detailed -input_script_name "xevent_core" -has_output_results $false
        }
        else 
        {
            Start-SQLCmdProcess -collector_name $collector_name_core -input_script_name "xevent_core" -has_output_results $false
            Start-SQLCmdProcess -collector_name $collector_name_detailed -input_script_name "xevent_detailed" -has_output_results $false
        }
        
        Start-Sleep -Seconds 2

        #in case CTRL+C is pressed
        HandleCtrlC

        if ($true -ne $global:xevent_on)
        {
            #add Xevent target
            $collector_name = "Xevent_Detailed_Target"
            $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $global:xevent_target_file + ".xel'" + ", max_file_size=(500), max_rollover_files=(50)); END" 
            
            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_add_target -has_output_results $false

            #in case CTRL+C is pressed
            HandleCtrlC

            #start the XEvent session
            $collector_name = "Xevent_Detailed_Start"
            $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session]  ON SERVER STATE = START; END" 

            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_start -has_output_results $false
            
            # set the Xevent has been started flag to be true
            $global:xevent_on = $true
        }

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetAlwaysOnDiag() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        
        #AlwaysOn Basic Info
        $collector_name = "AlwaysOnDiagScript"
        Start-SQLCmdProcess -collector_name "AlwaysOnDiagScript" -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetXeventsAlwaysOnMovement() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str


    [console]::TreatControlCAsInput = $true

    try {
        
        $skip_AlwaysOn_DataMovement = $false;

        if (($global:sql_major_version -le 11) -or (($global:sql_major_version -eq 13) -and ($global:sql_major_build -lt 4001) ) -or (($global:sql_major_version -eq 12) -and ($global:sql_major_build -lt 5000)) )
        {
            $skip_AlwaysOn_DataMovement = $true
        }

        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)


        # create the XEvent sessions for Always on and some core Xevents         
        $collector_name_xeventcore = "Xevent_CoreAddSesion"
        Start-SQLCmdProcess -collector_name $collector_name_xeventcore -input_script_name "xevent_core" -has_output_results $false
        
        if ($skip_AlwaysOn_DataMovement)
        {
            Write-LogWarning "AlwaysOn_Data_Movement Xevents is not supported on $($global:sql_major_version.ToString() + ".0." + $global:sql_major_build.ToString()) version. Collection will be skipped. Other data will be collected."
        }
        else 
        {
            $collector_name = "Xevent_AlwaysOn_Data_Movement"
            Start-SQLCmdProcess -collector_name $collector_name -input_script_name "xevent_AlwaysOn_Data_Movement" -has_output_results $false
        }
        
        
        #in case CTRL+C is pressed
        HandleCtrlC

        Start-Sleep -Seconds 2

        #create the target Xevent files 

        if ($true -ne $global:xevent_on)
        {
            #add Xevent target
            $collector_name_xeventcore = "Xevent_CoreTarget"
            $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $global:xevent_target_file + ".xel' " + ", max_file_size=(500), max_rollover_files=(50)); END" 

            Start-SQLCmdProcess -collector_name $collector_name_xeventcore -is_query $true -query_text $alter_event_session_add_target -has_output_results $false

            #in case CTRL+C is pressed
            HandleCtrlC

            #start the XEvent session
            $collector_name_xeventcore = "Xevent_CoreStart"
            $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session]  ON SERVER STATE = START; END"
            
            Start-SQLCmdProcess -collector_name $collector_name_xeventcore -is_query $true -query_text $alter_event_session_start -has_output_results $false

            # set the Xevent has been started flag to be true
            $global:xevent_on = $true
        }


        #in case CTRL+C is pressed
        HandleCtrlC

        if ($skip_AlwaysOn_DataMovement -eq $false)
        {
            #add Xevent target
            $collector_name = "AlwaysOn_Data_Movement_target"
            $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_alwayson_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $collector_name + ".xel'" + ", max_file_size=(500), max_rollover_files=(50)); END" 
            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_add_target -has_output_results $false
            
            #in case CTRL+C is pressed
            HandleCtrlC

            #start the XEvent session
            $collector_name = "AlwaysOn_Data_Movement_Start"
            $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_alwayson_session]  ON SERVER STATE = START; END" 
            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_start -has_output_results $false
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetAlwaysOnHealthXel
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    [console]::TreatControlCAsInput = $true

    $collector_name = "AlwaysOnHealthXevent"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
            $server = $global:sql_instance_conn_str

            $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
            $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false


            if ($server -notlike '*\*')
            {
                $vInstance = "MSSQLSERVER"
            } 
            if ($server -like '*\*')
            {
                $selectInstanceName = $global:sql_instance_conn_str              
                $server = Get-InstanceNameOnly($selectInstanceName) 
                $vInstance = $server
            }
            [string]$DestinationFolder = $global:output_folder 


            #in case CTRL+C is pressed
            HandleCtrlC
            
            $vRegInst = (Get-ItemProperty -Path HKLM:"SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$vInstance
            $vRegPath = "SOFTWARE\Microsoft\Microsoft SQL Server\" + $vRegInst + "\MSSQLServer\Parameters" 
            $vLogPath = (Get-ItemProperty -Path HKLM:$vRegPath).SQLArg1 -replace '-e'
            $vLogPath = $vLogPath -replace 'ERRORLOG'
            Get-ChildItem -Path $vLogPath -Filter AlwaysOn_health*.xel | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null

        } 
        catch {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }

}


function GetXeventBackupRestore 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        if ($global:sql_major_version -ge 13)
        {
            ##create error output filenames using the path + servername + date and time
            $partial_output_file_name = CreatePartialOutputFilename ($server)

            #XEvents file: xevent_backup_restore.sql - Backup Restore
       
            $collector_name_core = "Xevent_Core_AddSession"
            $collector_name_bkp_rest  = "Xevent_BackupRestore_AddSession"

            if ($true -eq $global:xevent_on)
            {
                Start-SQLCmdProcess -collector_name $collector_name_bkp_rest -input_script_name "xevent_backup_restore" -has_output_results $false
            }
            else 
            {
                Start-SQLCmdProcess -collector_name $collector_name_core -input_script_name "xevent_core" -has_output_results $false
                Start-SQLCmdProcess -collector_name $collector_name_bkp_rest -input_script_name "xevent_backup_restore" -has_output_results $false
            }
            

            Start-Sleep -Seconds 2

            #in case CTRL+C is pressed
            HandleCtrlC

            if ($true -ne $global:xevent_on)
            {
                


                
                #add Xevent target
                $collector_name = "Xevent_BackupRestore_Target"
                $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $global:xevent_target_file + ".xel' " + ", max_file_size=(500), max_rollover_files=(50)); END" 

                Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_add_target -has_output_results $false
                
                #in case CTRL+C is pressed
                HandleCtrlC

                #start the XEvent session
                $collector_name = "Xevent_BackupRestore_Start"
                $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session]  ON SERVER STATE = START; END"
                

                Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_start -has_output_results $false
                # set the Xevent has been started flag to be true
                $global:xevent_on = $true

            }

        }
        else
        {
            Write-LogWarning "Backup_restore_progress_trace XEvent exists in SQL Server 2016 and higher and cannot be collected for instance $server. "
        }
        


    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetBackupRestoreTraceFlagOutput
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {

        #SQL Server Slow SQL Server Backup and Restore
        $collector_name = "EnableTraceFlag"
        $trace_flag_enabled = "DBCC TRACEON(3004,3212,3605,-1)"
        
        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $trace_flag_enabled -has_output_results $false
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return     
    }
}

function GetVSSAdminLogs()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true


    try 
    {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #list VSS Admin providers
        $collector_name = "VSSAdmin_Providers"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " list providers"
        $executable = "VSSAdmin.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file
        

        $collector_name = "VSSAdmin_Shadows"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " list shadows"
        $executable = "VSSAdmin.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file
        

        Start-Sleep -Seconds 1

        $collector_name = "VSSAdmin_Shadowstorage"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " list shadowstorage"
        $executable = "VSSAdmin.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file
        

        
        $collector_name = "VSSAdmin_Writers"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " list writers"
        $executable = "VSSAdmin.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file
        

            
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function SetVerboseSQLVSSWriterLog()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true
    
    if ($true -eq $global:sqlwriter_collector_has_run)
    {
        return
    }

    # set this to true
    $global:sqlwriter_collector_has_run = $true


    $collector_name = "SetVerboseSQLVSSWriterLog"
    Write-Loginformation "Executing collector: $collector_name"

    if ($global:sql_major_version -lt 15)
    {
        Write-LogDebug "SQL Server major version is $global:sql_major_version. Not collecting SQL VSS log" -DebugLogLevel 4
        return
    }


    try 
    {
        [string]$DestinationFolder = $global:output_folder
        
         # if backup restore scenario, we will get a verbose trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit))
        {

            Write-LogWarning "To enable SQL VSS VERBOSE loggging, the SQL VSS Writer service must be restarted now and when shutting down data collection. This is a very quick process."
            $userinputvss = Read-Host "Do you want to restart SQL VSS Writer Service>" 
            $HelpMessage = "Please enter a valid input (Y or N)"

            $ValidInput = "Y","N"
            $AllInput = @()
            $AllInput += , $ValidInput
            $AllInput += , $userinputvss
            $AllInput += , $HelpMessage

            $global:restart_sqlwriter = validateUserInput($AllInput)
            
            if($userinputvss -eq "Y")
            {
                
                if ("Running" -ne (Get-Service -Name SQLWriter).Status)
                {
                    Write-LogInformation "Attempting to start SQLWriter Service which is not running."
                    Restart-Service SQLWriter -force
                }
                
            }
            else  # ($userinputvss -eq "N")
            {
                Write-LogInformation "You have chosen not to restart SQLWriter Service. No verbose logging will be collected for SQL VSS Writer (2019 or later)"
                return
            }

            
            #  collect verbose SQL VSS Writer log if SQL 2019
            $file = 'C:\Program Files\Microsoft SQL Server\90\Shared\SqlWriterConfig.ini'
            if (!(Test-Path $file ))  
            {
                Write-LogWarning "Attempted to enable verbose logging in SqlWriterConfig.ini, but the file does not exist."
                Write-LogWarning "Verbose SQL VSS Writer logging will not be captured"
            }
            else
            {
                (Get-Content $file).Replace("TraceLevel=DEFAULT","TraceLevel=VERBOSE") | Set-Content $file
                (Get-Content $file).Replace("TraceFileSizeMb=1","TraceFileSizeMb=10") | Set-Content $file

                $matchfoundtracelevel = Get-Content $file | Select-String -Pattern 'TraceLevel=VERBOSE' -CaseSensitive -SimpleMatch
            
                if ([String]::IsNullOrEmpty -ne $matchfoundtracelevel)
                {
                    Write-LogDebug "The TraceLevel is setting is: $matchfoundtracelevel" -DebugLogLevel 4
                }

                $matchfoundFileSize = Get-Content $file | Select-String -Pattern 'TraceFileSizeMb=10' -CaseSensitive -SimpleMatch
            
                if ([String]::IsNullOrEmpty -ne $matchfoundFileSize)
                {
                    Write-LogDebug "The TraceFileSizeMb is: $matchfoundFileSize" -DebugLogLevel 4
                }

                Write-LogInformation "Retarting SQLWriter Service."
                Restart-Service SQLWriter -force
            }

        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    finally 
    {
        # we just finished executing this once, don't repeat
        $global:sqlwriter_collector_has_run = $true
        Write-LogDebug "Inside finally block for SQLVSSWriter log." -DebugLogLevel 5
    }
}
function GetSysteminfoSummary() 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #Systeminfo (MSInfo)
        $collector_name = "SystemInfo_Summary"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name $collector_name  
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "systeminfo"
        $argument_list = "/FO LIST"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -RedirectStandardOutput $output_file
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetMisciagInfo() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true

    try 
    {
        #in case CTRL+C is pressed
        HandleCtrlC

        #misc DMVs 
        $collector_name = "MiscPssdiagInfo"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetErrorlogs() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {

        #in case CTRL+C is pressed
        HandleCtrlC

        #errorlogs
        $collector_name = "collecterrorlog"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetTaskList () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {

        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        ##task list
        #tasklist processes
    
        $collector_name = "TaskListVerbose"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "tasklist.exe"
        $argument_list = "/V"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file

        #in case CTRL+C
        HandleCtrlC


        #tasklist services
        $collector_name = "TaskListServices"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "tasklist.exe"
        $argument_list = "/SVC"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file
        
            
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetRunningProfilerXeventTraces () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try {

        #in case CTRL+C is pressed
        HandleCtrlC

        #active profiler traces and xevents
        $collector_name = "ExistingProfilerXeventTraces"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name "Profiler Traces"
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }


}

function GetHighCPUPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true


    try {

        #in case CTRL+C is pressed
        HandleCtrlC

        #SQL Server High CPU Perf Stats
        $collector_name = "HighCPU_perfstats"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {
        
        Start-SQLCmdProcess -collector_name "PerfStats" -input_script_name "SQL Server Perf Stats"
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetPerfStatsSnapshot ([string] $TimeOfCapture="Startup") 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true


    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of PerfStats shutdown collector"
        return
    }

    try 
    {
        #SQL Server Perf Stats Snapshot
        Start-SQLCmdProcess -collector_name ("PerfStatsSnapshot"+ $TimeOfCapture) -input_script_name "SQL Server Perf Stats Snapshot"
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetPerfmonCounters () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true

    if ($true -eq $global:perfmon_is_on)
    {
        Write-LogDebug "Perfmon has already been started by another collector." -DebugLogLevel 3
        return
    }

    $server = $global:sql_instance_conn_str
    $internal_folder = $global:internal_output_folder

    try {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        #Perfmon
        $collector_name = "Perfmon"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "cmd.exe"
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon & logman CREATE COUNTER -n logscoutperfmon -cf `"" + $internal_folder + "LogmanConfig.txt`" -f bin -si 00:00:05 -max 250 -cnf 01:00:00  -o " + $output_file + "  & logman start logscoutperfmon "
        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file

        #turn on the perfmon notification to let others know it is enabled
        $global:perfmon_is_on = $true
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetServiceBrokerInfo () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {
        #in case CTRL+C is pressed
        HandleCtrlC

        #Service Broker collection
        $collector_name = "SSB_diag"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetTempdbSpaceLatchingStats () 
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try {


        #Tempdb space and latching
        $collector_name = "TempDBAnalysis"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetLinkedServerInfo () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try {

        #Linked Server configuration
        $collector_name = "linked_server_config"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetQDSInfo () 
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try {

        #Query Store
        $collector_name = "Query Store"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetReplMetadata () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand


    try
    {

        #Replication Metadata
        $collector_name = "Repl_Metadata_Collector"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetChangeDataCaptureInfo ([string] $TimeOfCapture = "Startup") {
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {

        #Change Data Capture (CDC)
        $collector_name = "ChangeDataCapture" 
        Start-SQLCmdProcess -collector_name ($collector_name + $TimeOfCapture) -input_script_name $collector_name 
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetChangeTracking ([string] $TimeOfCapture = "Startup") 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {

        #Change Tracking
        $collector_name = "Change_Tracking"
        Start-SQLCmdProcess -collector_name ($collector_name + $TimeOfCapture) -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetFilterDrivers () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #filter drivers
        $collector_name = "FLTMC_Filters"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " filters"
        $executable = "fltmc.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file


        #filters instance
        $collector_name = "FLTMC_Instances"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $executable = "fltmc.exe"
        $argument_list = " instances"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}


function GetNetworkTrace () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true
    
    $server = $global:sql_instance_conn_str

    $internal_folder = $global:internal_output_folder

    try {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        #Perfmon
        $collector_name = $NETWORKTRACE_NAME
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $netsh_output = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name "delete" -needExtraQuotes $true -fileExt ".me"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt "_"
        $param2 =  Split-Path (Split-Path $output_file -Parent) -Leaf
        $executable = "cmd.exe"
        #$argument_list = "/C netsh trace start sessionname='sqllogscout_nettrace' report=yes persistent=yes capture=yes tracefile=" + $output_file
        $argument_list  = "/c StartNetworkTrace.bat " + $output_file + " " + $netsh_output
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $param2
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetMemoryDumps () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand


    try {
    
        $InstanceSearchStr = ""
        #strip the server name from connection string so it can be used for looking up PID
        $instanceonly = Get-InstanceNameOnly -NetnamePlusInstance $global:sql_instance_conn_str


        #if default instance use "MSSQLSERVER", else "MSSQL$InstanceName
        if ($instanceonly -eq $global:host_name) {
            $InstanceSearchStr = "MSSQLSERVER"
        }
        else {
            $InstanceSearchStr = "MSSQL$" + $instanceonly

        }
		$collector_name = "Memorydump"
        Write-LogDebug "Output folder is $global:output_folder" -DebugLogLevel 2
        Write-LogDebug "Service name is $InstanceSearchStr" -DebugLogLevel 2
        Write-LogInformation "Executing Collector: $collector_name"
        #invoke SQLDumpHelper
        .\SQLDumpHelper.ps1 -DumpOutputFolder $global:output_folder -InstanceOnlyName $InstanceSearchStr
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
} 

function GetWindowsVersion
{
   #Write-LogDebug "Inside" $MyInvocation.MyCommand

   try {
       $winver = [Environment]::OSVersion.Version.Major    
   }
   catch
   {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
   }
   
   
   #Write-Debug "Windows version is: $winver" -DebugLogLevel 3

   return $winver;
}

function GetWPRTrace () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $wpr_win_version = GetWindowsVersion

    if ($wpr_win_version -lt 8) 
    {
        Write-LogError "Windows Performance Recorder is not available on this version of Windows"
        exit;   
    } 
    else 
    {
        try {

            $partial_error_output_file_name = CreatePartialErrorOutputFilename -server $server
    
            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3

            #choose collector type

            
            [string[]] $WPRArray = "CPU", "Heap and Virtual memory", "Disk and File I/O", "Filter drivers"
            $WPRIntRange = 0..($global:ScenarioArray.Length - 1)  

            Write-LogInformation "Please select one of the following Data Collection Type:`n"
            Write-LogInformation ""
            Write-LogInformation "ID   WPR Profile"
            Write-LogInformation "--   ---------------"

            for ($i = 0; $i -lt $WPRArray.Count; $i++) {
                Write-LogInformation $i "  " $WPRArray[$i]
            }
            $isInt = $false
            
            Write-LogInformation ""
            Write-LogWarning "Enter the WPR Profile ID for which you want to collect performance data. Then press Enter" 

            $ValidInput = "0","1","2","3"
            $wprIdStr = Read-Host "Enter the WPR Profile ID from list above>" -CustomLogMessage "WPR Profile Console input:"
            $HelpMessage = "Please enter a valid input (0,1,2 or 3)"

            #$AllInput = $ValidInput,$WPR_YesNo,$HelpMessage 
            $AllInput = @()
            $AllInput += , $ValidInput
            $AllInput += , $wprIdStr
            $AllInput += , $HelpMessage
        
            $wprIdStr = validateUserInput($AllInput)

            #Write-LogInformation "WPR Profile Console input: $wprIdStr"
            
            try {
                $wprIdStrIdInt = [convert]::ToInt32($wprIdStr)
                $isInt = $true
            }

            catch [FormatException] {
                Write-LogError "The value entered for ID '", $ScenIdStr, "' is not an integer"
                continue 
            }
            #Take user input for collection time for WPR trace
            $ValidInputRuntime = (0..45)

            Write-LogWarning "How long do you want to run the WPR trace (maximum 45 seconds)?"
            $wprruntime = Read-Host "number of seconds (maximum 45 seconds)>" -CustomLogMessage "WPR runtime input:"

            $HelpMessageRuntime = "This is an invalid entry. Please enter a value between 1 and 45 seconds"
            $AllInputruntime = @()
            $AllInputruntime += , $ValidInputRuntime
            $AllInputruntime += , $wprruntime
            $AllInputruntime += , $HelpMessageRuntime
        
            $wprruntime = validateUserInput($AllInputruntime)
            
            Write-LogInformation "You selected $wprruntime seconds to run WPR Trace"
            #Write-Host "The configuration is ready. Press <Enter> key to proceed..."
            Read-Host -Prompt "<Press Enter> to proceed"
 
            If ($isInt -eq $true) {
                #Perfmon
                
                switch ($wprIdStr) {
                    "0" { 
                        $collector_name = $global:wpr_collector_name= "WPR_CPU"
                        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start CPU -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file
                        
                        Start-Sleep -s $wprruntime 
                    }
                    "1" { 
                        $collector_name = $global:wpr_collector_name = "WPR_HeapAndVirtualMemory"
                        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start Heap -start VirtualAllocation  -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file
                        
                        Start-Sleep -s $wprruntime 
                    }
                    "2" { 
                        $collector_name = $global:wpr_collector_name = "WPR_DiskIO_FileIO"
                        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start DiskIO -start FileIO -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file
                        
                        Start-Sleep -s $wprruntime 
                    }
                    "3" { 
                        $collector_name = $global:wpr_collector_name = "WPR_MiniFilters"
                        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start Minifilter -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file
                        
                        Start-Sleep -s $wprruntime 
                    }                    
                }
            }
        }
        catch {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
            return
        }
    }

}

function GetMemoryLogs()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true


    try 
    {
        #Change Tracking
        $collector_name = "SQL_Server_Mem_Stats"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }


}

function GetClusterInformation()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str
    $output_folder = $global:output_folder
    $ClusterError = 0
    $collector_name = "ClusterLogs"
    $partial_output_file_name = CreatePartialOutputFilename ($server)

    
    Write-LogInformation "Executing Collector: $collector_name"

    $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false -fileExt ".out"
    [System.Text.StringBuilder]$rs_ClusterLog = New-Object -TypeName System.Text.StringBuilder


    
    if ($ClusterError -eq 0)
    {
        try 
        {
                #Cluster Registry Hive
                $collector_name = "ClusterRegistryHive"
                
                $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false -fileExt ".out"
                Get-ChildItem 'HKLM:HKEY_LOCAL_MACHINE\Cluster' -Recurse | Out-File -FilePath $output_file
                
                $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".hiv"
                $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
                $executable = "reg.exe"
                $argument_list = "save `"HKEY_LOCAL_MACHINE\Cluster`" $output_file"
                Write-LogInformation "Executing Collector: $collector_name"
                
                StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file

        }
        catch
        {
                $function_name = $MyInvocation.MyCommand 
                $error_msg = $PSItem.Exception.Message 
				$error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
				$error_offset = $PSItem.InvocationInfo.OffsetInLine
                Write-LogError "$function_name - Error while accessing cluster registry keys...:  $error_msg (line: $error_linenum, $error_offset)"
        }

        $collector_name = "ClusterInfo"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false -fileExt ".out"

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Nodes --`r`n")
            $clusternodenames =  Get-Clusternode | Out-String
            [void]$rs_ClusterLog.Append("$clusternodenames`r`n") 
        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster (node):  $error_msg"
        }
 
        try 
        {
            Import-Module FailoverClusters
            [void]$rs_ClusterLog.Append("-- Windows Cluster Name --`r`n")
            $clusterName = Get-cluster
            [void]$rs_ClusterLog.Append("$clusterName`r`n")
            
            #dumping windows cluster log
            Write-LogInformation "Collecting Windows cluster log for all running nodes, this process may take some time....."
            $nodes =  Get-Clusternode | Where-Object {$_.state -eq 'Up'} |Select-Object name  

            Foreach ($node in $nodes)
            {
    
                Get-ClusterLog -Node $node.name -Destination $output_folder  -UseLocalTime | Out-Null
            }
        }
        catch 
        {
            $ClusterError = 1
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }


        try
        {
            [void]$rs_ClusterLog.Append("-- Cluster Network Interfaces --`r`n")
            $ClusterNetworkInterface = Get-ClusterNetworkInterface | Out-String
            [void]$rs_ClusterLog.Append("$ClusterNetworkInterface`r`n") 
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Cluster Network Interface:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Shared Volume(s) --`r`n")
            $ClusterSharedVolume = Get-ClusterSharedVolume | Out-String
            [void]$rs_ClusterLog.Append("$ClusterSharedVolume`r`n") 

        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Cluster Shared Volume:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Cluster Quorum --`r`n")
            $ClusterQuorum = Get-ClusterQuorum | Format-List * | Out-String
            [void]$rs_ClusterLog.Append("$ClusterQuorum`r`n") 


            Get-Clusterquorum | ForEach-Object {
                        $cluster = $_.Cluster
                        $QuorumResource = $_.QuorumResource
                        $QuorumType = $_.QuorumType
            
                        # $results = New-Object PSObject -property @{
                        # "QuorumResource" = $QuorumResource
                        # "QuorumType" = $QuorumType
                        # "cluster" = $Cluster
                        } | Out-String

            [void]$rs_ClusterLog.Append("$results`r`n") 
           
        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Cluster Quorum:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Physical Disks --`r`n")
            $PhysicalDisk = Get-PhysicalDisk | Out-String           
            [void]$rs_ClusterLog.Append("$PhysicalDisk`r`n") 
        }
        catch {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Physical Disk:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Groups (Roles) --`r`n")
            $clustergroup = Get-Clustergroup | Out-String
            [void]$rs_ClusterLog.Append("$clustergroup`r`n") 
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster group:  $error_msg"
        }
        
        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Resources --`r`n")
            $clusterresource = Get-ClusterResource | Out-String
            [void]$rs_ClusterLog.Append("$clusterresource`r`n")

        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster resource:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Net Firewall Profiles --`r`n")
            $NetFirewallProfile = Get-NetFirewallProfile | Out-String
            [void]$rs_ClusterLog.Append("$NetFirewallProfile`r`n") 
        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Net Firewall Profile:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- cluster clusternetwork --`r`n")
            $clusternetwork = Get-clusternetwork| Format-List * | Out-String
            [void]$rs_ClusterLog.Append("$clusternetwork`r`n") 
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster network:  $error_msg"
        }

       try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Info--`r`n")
            $clusterfl = Get-Cluster | Format-List *  | Out-String
            [void]$rs_ClusterLog.Append("$clusterfl`r`n") 
        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster configured value:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Access--`r`n")
            $clusteraccess = get-clusteraccess | Out-String
            [void]$rs_ClusterLog.Append("$clusteraccess`r`n") 
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster access settings:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- cluster Node Details --`r`n")
            $clusternodefl = get-clusternode | Format-List * | Out-String
            [void]$rs_ClusterLog.Append("$clusternodefl`r`n") 
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster node configured value:  $error_msg"
        }

        Add-Content -Path ($output_file) -Value ($rs_ClusterLog.ToString())
    }
}

function GetSQLErrorLogsDumpsSysHealth()
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "SQLErrorLogs_AgentLogs_SystemHealth_MemDumps_FciXel"
    Write-LogInformation "Executing Collector: $collector_name"

    try{

            $server = $global:sql_instance_conn_str

            
            $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
            $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false


            if ($server -notlike '*\*')
            {
                $vInstance = "MSSQLSERVER"
            } 
            elseif ($server -like '*\*')
            {
                $vInstance = Get-InstanceNameOnly($server) 
            }

            [string]$DestinationFolder = $global:output_folder 

            #in case CTRL+C is pressed
            HandleCtrlC
            
            # get XEL files from last three weeks
            $time_threshold = (Get-Date).AddDays(-21)

            $vRegInst = (Get-ItemProperty -Path HKLM:"SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$vInstance
            $vRegPath = "SOFTWARE\Microsoft\Microsoft SQL Server\" + $vRegInst + "\MSSQLServer\Parameters" 
            $vLogPath = (Get-ItemProperty -Path HKLM:$vRegPath).SQLArg1 -replace '-e'
            $vLogPath = $vLogPath -replace 'ERRORLOG'

            Write-LogDebug "The \LOG folder discovered for instance is: $vLogPath" -DebugLogLevel 4

            Write-LogDebug "Getting ERRORLOG files" -DebugLogLevel 3
            Get-ChildItem -Path $vLogPath -Filter "ERRORLOG*" | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null

            Write-LogDebug "Getting SQLAGENT files" -DebugLogLevel 3
            Get-ChildItem -Path $vLogPath -Filter "SQLAGENT*" | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null

            Write-LogDebug "Getting System_Health*.xel files" -DebugLogLevel 3
            Get-ChildItem -Path $vLogPath -Filter "system_health*.xel" | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null
            
            Write-LogDebug "Getting SQL Dump files" -DebugLogLevel 3
            Get-ChildItem -Path "$vLogPath\SQLDump*.mdmp", "$vLogPath\SQLDump*.log" | Where-Object {$_.LastWriteTime -gt $time_threshold} | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null

            if (IsClustered)
            {
                Write-LogDebug "Getting MSSQLSERVER_SQLDIAG*.xel files" -DebugLogLevel 3
                Get-ChildItem -Path $vLogPath -Filter "*_SQLDIAG*.xel" | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null
            }
        } 
        catch 
        {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }
}
function GetPolybaseLogs()
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "PolybaseLogs"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
            $server = $global:sql_instance_conn_str

            $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
            $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false


            if ($server -notlike '*\*')
            {
                $vInstance = "MSSQLSERVER"
            } 
            if ($server -like '*\*')
            {
                $vInstance = Get-InstanceNameOnly($server) 
            }
            [string]$DestinationFolder = $global:output_folder 

            #in case CTRL+C is pressed
            HandleCtrlC

            $vRegInst = (Get-ItemProperty -Path HKLM:"SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$vInstance
            $vRegPath = "SOFTWARE\Microsoft\Microsoft SQL Server\" + $vRegInst + "\MSSQLServer\Parameters" 
            $vLogPath = (Get-ItemProperty -Path HKLM:$vRegPath).SQLArg1 -replace '-e'
            $vLogPath = $vLogPath -replace 'ERRORLOG'
            # polybase path
            $polybase_path = $vLogPath + '\Polybase\'            
            $ValidPath = Test-Path -Path $polybase_path
            $exclude_ext = @('*.hprof','*.bak')  #exclude file with these extensions when copying.
            If ($ValidPath -ne $False)
            {
                $DestinationFolder_polybase = $DestinationFolder + '\Polybase\'
                Copy-Item $polybase_path $DestinationFolder
                Get-ChildItem $polybase_path -recurse -Exclude $exclude_ext  | where-object {$_.length -lt 1073741824} | Copy-Item -Destination $DestinationFolder_polybase 2>> $error_file | Out-Null
            }

        } 
        catch 
        {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }
}

function GetStorport()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    [console]::TreatControlCAsInput = $true

    $collector_name = "StorPort"
    Write-LogInformation "Executing Collector: $collector_name"
    $server = $global:sql_instance_conn_str

    try
    {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)

        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

      
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"

        $executable = "cmd.exe"
        $argument_list = "/C logman create trace  ""storport"" -ow -o $output_file -p ""Microsoft-Windows-StorPort"" 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 4096 -ets"

        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetHighIOPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {

        #in case CTRL+C is pressed
        HandleCtrlC

        #SQL Server High IO Perf Stats
        $collector_name = "High_IO_Perfstats"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return 
    }

}

function GetSQLAssessmentAPI() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try 
    {

        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC


        $collector_name = "SQLAssessmentAPI"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false

        if (Get-Module -ListAvailable -Name sqlserver)
        {
            if ((Get-Module -ListAvailable -Name sqlserver).exportedCommands.Values | Where-Object name -EQ "Invoke-SqlAssessment")
            {
                Write-LogDebug "Invoke-SqlAssessment() function present" -DebugLogLevel 3
                Get-SqlInstance -ServerInstance $server | Invoke-SqlAssessment -FlattenOutput | Out-File $output_file
            } 
            else 
            {
                Write-LogDebug "Invoke-SqlAssessment() function NOT present" -DebugLogLevel 3
            }

        }
        else
        {
                Write-LogWarning "SQLServer PS module not installed. Will not collect $collector_name"
        }
    
    }

    catch 
    {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
        $error_offset = $PSItem.InvocationInfo.OffsetInLine
        Write-LogError "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
        return
    }
}

function GetUserRights () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    $userRights = @(
        [PSCustomObject]@{Constant="SeTrustedCredManAccessPrivilege"; Description="Access Credential Manager as a trusted caller"}
        ,[PSCustomObject]@{Constant="SeNetworkLogonRight"; Description="Access this computer from the network"}
        ,[PSCustomObject]@{Constant="SeTcbPrivilege"; Description="Act as part of the operating system"}
        ,[PSCustomObject]@{Constant="SeMachineAccountPrivilege"; Description="Add workstations to domain"}
        ,[PSCustomObject]@{Constant="SeIncreaseQuotaPrivilege"; Description="Adjust memory quotas for a process"}
        ,[PSCustomObject]@{Constant="SeInteractiveLogonRight"; Description="Allow log on locally"}
        ,[PSCustomObject]@{Constant="SeRemoteInteractiveLogonRight"; Description="Allow log on through Remote Desktop Services"}
        ,[PSCustomObject]@{Constant="SeBackupPrivilege"; Description="Back up files and directories"}
        ,[PSCustomObject]@{Constant="SeChangeNotifyPrivilege"; Description="Bypass traverse checking"}
        ,[PSCustomObject]@{Constant="SeSystemtimePrivilege"; Description="Change the system time"}
        ,[PSCustomObject]@{Constant="SeTimeZonePrivilege"; Description="Change the time zone"}
        ,[PSCustomObject]@{Constant="SeCreatePagefilePrivilege"; Description="Create a pagefile"}
        ,[PSCustomObject]@{Constant="SeCreateTokenPrivilege"; Description="Create a token object"}
        ,[PSCustomObject]@{Constant="SeCreateGlobalPrivilege"; Description="Create global objects"}
        ,[PSCustomObject]@{Constant="SeCreatePermanentPrivilege"; Description="Create permanent shared objects"}
        ,[PSCustomObject]@{Constant="SeCreateSymbolicLinkPrivilege"; Description="Create symbolic links"}
        ,[PSCustomObject]@{Constant="SeDebugPrivilege"; Description="Debug programs"}
        ,[PSCustomObject]@{Constant="SeDenyNetworkLogonRight"; Description="Deny access to this computer from the network"}
        ,[PSCustomObject]@{Constant="SeDenyBatchLogonRight"; Description="Deny log on as a batch job"}
        ,[PSCustomObject]@{Constant="SeDenyServiceLogonRight"; Description="Deny log on as a service"}
        ,[PSCustomObject]@{Constant="SeDenyInteractiveLogonRight"; Description="Deny log on locally"}
        ,[PSCustomObject]@{Constant="SeDenyRemoteInteractiveLogonRight"; Description="Deny log on through Remote Desktop Services"}
        ,[PSCustomObject]@{Constant="SeEnableDelegationPrivilege"; Description="Enable computer and user accounts to be trusted for delegation"}
        ,[PSCustomObject]@{Constant="SeRemoteShutdownPrivilege"; Description="Force shutdown from a remote system"}
        ,[PSCustomObject]@{Constant="SeAuditPrivilege"; Description="Generate security audits"}
        ,[PSCustomObject]@{Constant="SeImpersonatePrivilege"; Description="Impersonate a client after authentication"}
        ,[PSCustomObject]@{Constant="SeIncreaseWorkingSetPrivilege"; Description="Increase a process working set"}
        ,[PSCustomObject]@{Constant="SeIncreaseBasePriorityPrivilege"; Description="Increase scheduling priority"}
        ,[PSCustomObject]@{Constant="SeLoadDriverPrivilege"; Description="Load and unload device drivers"}
        ,[PSCustomObject]@{Constant="SeLockMemoryPrivilege"; Description="Lock pages in memory"}
        ,[PSCustomObject]@{Constant="SeBatchLogonRight"; Description="Log on as a batch job"}
        ,[PSCustomObject]@{Constant="SeServiceLogonRight"; Description="Log on as a service"}
        ,[PSCustomObject]@{Constant="SeSecurityPrivilege"; Description="Manage auditing and security log"}
        ,[PSCustomObject]@{Constant="SeRelabelPrivilege"; Description="Modify an object label"}
        ,[PSCustomObject]@{Constant="SeSystemEnvironmentPrivilege"; Description="Modify firmware environment values"}
        ,[PSCustomObject]@{Constant="SeDelegateSessionUserImpersonatePrivilege"; Description="Obtain an impersonation token for another user in the same session"}
        ,[PSCustomObject]@{Constant="SeManageVolumePrivilege"; Description="Perform volume maintenance tasks"}
        ,[PSCustomObject]@{Constant="SeProfileSingleProcessPrivilege"; Description="Profile single process"}
        ,[PSCustomObject]@{Constant="SeSystemProfilePrivilege"; Description="Profile system performance"}
        ,[PSCustomObject]@{Constant="SeUndockPrivilege"; Description="Remove computer from docking station"}
        ,[PSCustomObject]@{Constant="SeAssignPrimaryTokenPrivilege"; Description="Replace a process level token"}
        ,[PSCustomObject]@{Constant="SeRestorePrivilege"; Description="Restore files and directories"}
        ,[PSCustomObject]@{Constant="SeShutdownPrivilege"; Description="Shut down the system"}
        ,[PSCustomObject]@{Constant="SeSyncAgentPrivilege"; Description="Synchronize directory service data"}
        ,[PSCustomObject]@{Constant="SeTakeOwnershipPrivilege"; Description="Take ownership of files or other objects"}
        ,[PSCustomObject]@{Constant="SeUnsolicitedInputPrivilege"; Description="Read unsolicited input from a terminal device"}
    )

    try {

        $collectorData = New-Object System.Text.StringBuilder
        [void]$collectorData.AppendLine("Defined User Rights")
        [void]$collectorData.AppendLine("===================")
        [void]$collectorData.AppendLine()

        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Linked Server configuration
        $collector_name = "UserRights"
        #$input_script = BuildInputScript $global:present_directory $collector_name
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "$Env:windir\system32\secedit.exe"
        $argument_list = "/export /areas USER_RIGHTS /cfg `"$output_file.tmp`" /quiet"

        Write-LogDebug "The output_file is $output_file" -DebugLogLevel 5
        Write-LogDebug "The error_file is $error_file" -DebugLogLevel 5
        Write-LogDebug "The executable is $executable" -DebugLogLevel 5
        Write-LogDebug "The argument_list is $argument_list" -DebugLogLevel 5

        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath  $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -Wait $true

        #$allRights = (Get-Content -Path "$output_file.tmp" | Select-String '^(Se\S+) = (\S+)')
        $allRights = Get-Content -Path "$output_file.tmp"
        Remove-Item -Path "$output_file.tmp" #delete the temporary file created by SECEDIT.EXE

        foreach($right in $userRights){

            Write-LogDebug "Processing " $right.Constant -DebugLogLevel 5
            
            $line = $allRights | Where-Object {$_.StartsWith($right.Constant)}

            [void]$collectorData.AppendLine($right.Description)
            [void]$collectorData.AppendLine("=" * $right.Description.Length)

            if($null -eq $line){
                
                [void]$collectorData.AppendLine("0 account(s) with the " + $right.Constant + " user right:")
                
            } else {

                $users = $line.Split(" = ")[3].Split(",")
                [void]$collectorData.AppendLine([string]$users.Count + " account(s) with the " + $right.Constant + " user right:")
                
                $resolvedUserNames = New-Object -TypeName System.Collections.ArrayList

                foreach ($user in $users) {
                    
                    if($user[0] -eq "*"){
                        
                        $SID = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList (($user.Substring(1)))

                        try { #some account lookup may fail hence then nested try-catch
                            $account = $SID.Translate([Security.Principal.NTAccount]).Value    
                        } catch {
                            $account = $user.Substring(1) + " <== SID Lookup failed with: " + $_.Exception.InnerException.Message
                        }
                        
                        [void]$resolvedUserNames.Add($account)

                    } else {
                        
                        $NTAccount = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList ($user)

                        try {
                            
                            #try to get SID from account, then translate SID back to account
                            #done to mimic SDP behavior adding hostname to local accounts
                            $SID = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList (($NTAccount.Translate([Security.Principal.SecurityIdentifier]).Value))
                            $account = $SID.Translate([Security.Principal.NTAccount]).Value
                            [void]$resolvedUserNames.Add($account)

                        } catch {

                            #if the above fails we just add user name as fail-safe
                            [void]$resolvedUserNames.Add($user)

                        }

                    }

                }

                [void]$resolvedUserNames.Sort()
                [void]$collectorData.AppendLine($resolvedUserNames -Join "`r`n")
                [void]$collectorData.AppendLine("All accounts enumerated")

            }

            [void]$collectorData.AppendLine()
            [void]$collectorData.AppendLine()

        }

        Add-Content -Path $output_file -Value $collectorData.ToString()
        
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function validateUserInput([string[]]$AllInput)
{
    $ExpectedValidInput =  $AllInput[0]
    $userinput =  $AllInput[1]
    $HelpMessage = $AllInput[2]

    $ValidId = $false

    while(($ValidId -eq $false) )
    {
        try
        {    
            $userinput = $userinput.ToUpper()
            if ($ExpectedValidInput.Contains($userinput))
            {
                $userinput = [convert]::ToInt32($userinput)
                $ValidId = $true
                $ret = $userinput
                return $ret 
            }
            else
            {
                $userinput = Read-Host "$HelpMessage"
                $userinput = $userinput.ToUpper()
            }
        }

        catch [FormatException]
        {
            try
            {    
                $userinput = [convert]::ToString(($userinput))
                $userinput = $userinput.ToUpper()

                try
                {
                    $userinput =  $userinput.Trim()
                    $ExpectedValidInput =  $AllInput[0] # re-initalyze the vairable as in second attempt it becomes empty
                    If ($userinput.Length -gt 0 -and $userinput -match '[a-zA-Z]' -and $ExpectedValidInput.Contains($userinput))
                    {
                        $userinput = $userinput.ToUpper()
                        $ValidId = $true
                        $ret = $userinput
                        return $ret 
                    }
                    else
                    {
                        $userinput = Read-Host "$HelpMessage"
                        $ValidId = $false
                        continue
                    }
                }
                catch
                {
                    $ValidId = $false
                    continue 
                }
            }

            catch [FormatException]
                {
                    $ValidId = $false
                    continue 
                }
            continue 
        }
    }    
}

function IsCollectingXevents()
{
    Write-LogDebug "inside " $MyInvocation.MyCommand
    
    if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit)) `
    -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit)) `
    -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit)) `
    -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit))
    )
    {
        return $true
    }
    else 
    {
        return $false
    }

}

function DetailedPerfCollectorWarning ()
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    #if we are not running an detailed XEvent collector (scenario 2), exit this function as we don't need to raise warning

    Write-LogWarning "The 'DetailedPerf' scenario collects statement-level, detailed Xevent traces. This can impact the performance of SQL Server"

    if ($InteractivePrompts -eq "Quiet") 
    {
        Write-LogDebug "Running in QUIET mode" -DebugLogLevel 4
        Start-Sleep 5
        return $true
    }
    
    $ValidInput = "Y","N"
    $confirmAccess = Read-Host "Are you sure you would like to Continue?> (y/n)" -CustomLogMessage "Detailed Perf Warning Console input:"
    $HelpMessage = "Please enter a valid input (Y or N)"

    $AllInput = @()
    $AllInput += , $ValidInput
    $AllInput += , $confirmAccess
    $AllInput += , $HelpMessage

    $confirmAccess = validateUserInput($AllInput)

    Write-LogDebug "ConfirmAccess = $confirmAccess" -DebugLogLevel 3

    if ($confirmAccess -eq 'Y')
    { 
        #user chose to proceed
        return $true
    } 
    else 
    { 
        #user chose to abort
        return $false
    }
}

function CheckInternalFolderError ()
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    Write-LogInformation "Checking for errors in collector logs"
    
    $IgnoreError = @("The command completed successfully","Data Collector Set was not found","DBCC execution completed. If DBCC printed error messages")

    $internalfolderfiles = Get-ChildItem -Path $global:internal_output_folder -Filter *.out -Recurse -File -Name 

    foreach ($filename in $internalfolderfiles) 
    {
        $filename = $global:internal_output_folder +  $filename   
        $size=(Get-Item $filename).length/1024  
        if ($size -gt 0)
        {
            #handle the Perfmon output log case
            For ($i=0; $i -lt $IgnoreError.Length; $i++) 
            {
                $StringExist = Select-String -Path $filename -pattern $IgnoreError[$i]
                If($StringExist)
                {
                    Break  
                }
            }
            If(!$StringExist)
            {
                Write-LogWarning "***************************************************************************************************************"
                Write-LogWarning "A possible failure occurred to collect a log. Please take a look at the contents of file below and resolve the problem before you re-run SQL LogScout"
                Write-LogWarning "File '$filename' contains the following:"
                Write-LogError (Get-Content -Path  $filename)
            }
        } 
    }
}


function Invoke-CommonCollectors()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$BASIC_NAME' scenario" -ForegroundColor Green

  
    GetTaskList 
    GetFilterDrivers
    GetSysteminfoSummary

    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        GetMisciagInfo
        HandleCtrlC
        GetSQLErrorLogsDumpsSysHealth
        Start-Sleep -Seconds 2
        GetPolybaseLogs
        HandleCtrlC
        GetSQLAssessmentAPI
        
    }
    
    GetUserRights
    GetRunningDrivers
    

    HandleCtrlC
    Start-Sleep -Seconds 1

    
    GetPowerPlan
    GetWindowsHotfixes
    
    
    HandleCtrlC
    Start-Sleep -Seconds 2
    GetEventLogs

    if (IsClustered)
    {
        GetClusterInformation
    } 

} 

function Invoke-GeneralPerfScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$GENERALPERF_NAME' scenario" -ForegroundColor Green
    
    
    GetPerfmonCounters
    
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {

        HandleCtrlC
        Start-Sleep -Seconds 1
        GetXeventsGeneralPerf
        GetRunningProfilerXeventTraces 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetHighCPUPerfStats
        GetPerfStats 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetPerfStatsSnapshot 
        GetQDSInfo 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetTempdbSpaceLatchingStats 
        GetLinkedServerInfo 
        GetServiceBrokerInfo
    } 
}

function Invoke-DetailedPerfScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$DETAILEDPERF_NAME' scenario" -ForegroundColor Green

    
    GetPerfmonCounters
    
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        Start-Sleep -Seconds 1
        GetXeventsDetailedPerf
        GetRunningProfilerXeventTraces 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetHighCPUPerfStats 
        GetPerfStats 
        
        HandleCtrlC
        Start-Sleep -Seconds 2
        GetPerfStatsSnapshot 
        GetQDSInfo 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetTempdbSpaceLatchingStats
        GetLinkedServerInfo 
        GetServiceBrokerInfo
    } 
}

function Invoke-LightPerfScenario ()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$LIGHTPERF_NAME' scenario" -ForegroundColor Green
    
    
    GetPerfmonCounters
    
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {

        HandleCtrlC
        Start-Sleep -Seconds 1
        GetRunningProfilerXeventTraces 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetHighCPUPerfStats
        GetPerfStats 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetPerfStatsSnapshot 
        GetQDSInfo 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetTempdbSpaceLatchingStats 
        GetLinkedServerInfo 
        GetServiceBrokerInfo
    } 
}
function Invoke-AlwaysOnScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$ALWAYSON_NAME' scenario" -ForegroundColor Green
    

    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        GetAlwaysOnDiag
        GetXeventsAlwaysOnMovement
        GetPerfmonCounters
        GetAlwaysOnHealthXel
    }
}

function Invoke-ReplicationScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$REPLICATION_NAME' scenario" -ForegroundColor Green
        
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        Start-Sleep -Seconds 2
        GetReplMetadata 
        GetChangeDataCaptureInfo 
        GetChangeTracking 
    }
}

function Invoke-DumpMemoryScenario
{  
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$DUMPMEMORY_NAME' scenario" -ForegroundColor Green

    #invoke memory dump facility
    GetMemoryDumps

}


function Invoke-NetworkScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$NETWORKTRACE_NAME' scenario" -ForegroundColor Green

    GetNetworkTrace 

}





function Invoke-WPRScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$WPR_NAME' scenario" -ForegroundColor Green

    Write-LogWarning "WPR is a resource-intensive data collection process! Use under Microsoft guidance."
    
    $ValidInput = "Y","N"
    $WPR_YesNo = Read-Host "Do you want to proceed - Yes ('Y') or No ('N') >" -CustomLogMessage "WPR_YesNo Console input:"
    $HelpMessage = "Please enter a valid input (Y or N)"

    $AllInput = @()
    $AllInput += , $ValidInput
    $AllInput += , $WPR_YesNo
    $AllInput += , $HelpMessage
  
    $WPR_YesNo = validateUserInput($AllInput)
    $WPR_YesNo = $WPR_YesNo.ToUpper()

    if ($WPR_YesNo -eq "N") 
    {
        Write-LogInformation "You aborted the WPR data collection process"
        exit
    }
        
    #invoke the functionality
    GetWPRTrace 
}

function Invoke-MemoryScenario 
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$MEMORY_NAME' scenario" -ForegroundColor Green


    
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        Start-Sleep -Seconds 2
        GetMemoryLogs 
        GetPerfmonCounters
    }
}

function Invoke-SetupScenario 
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$SETUP_NAME' scenario" -ForegroundColor Green
    
    HandleCtrlC
    GetSQLSetupLogs
}

function Invoke-BackupRestoreScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$BACKUPRESTORE_NAME' scenario" -ForegroundColor Green

    GetXeventBackupRestore

    HandleCtrlC
    
    GetBackupRestoreTraceFlagOutput

    # adding Perfmon counter collection to this scenario
    GetPerfmonCounters

    HandleCtrlC

    #GetSQLVSSWriterLog is called on shutdown
    SetVerboseSQLVSSWriterLog

    GetVSSAdminLogs
}


function Invoke-IOScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        Write-LogInformation "Collecting logs for '$IO_NAME' scenario" -ForegroundColor Green

        GetStorport
        GetHighIOPerfStats
        HandleCtrlC
        
        # adding Perfmon counter collection to this scenario
        GetPerfmonCounters

        HandleCtrlC
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}


function Invoke-OnShutDown()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        
        # collect Basic collectors on shutdown
        if (IsScenarioEnabled -scenarioBit $global:basicBit -logged $true)
        {
            Invoke-CommonCollectors 
        }

        HandleCtrlC

        # PerfstatsSnapshot needs to be collected on shutdown so people can perform comparative analysis
        
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit -logged $true)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit -logged $true)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit -logged $true)) 
        )
        {
            GetPerfStatsSnapshot -TimeOfCapture "Shutdown"
        }

        HandleCtrlC

        # CDC and CT needs to be collected on shutdown so people can perform comparative analysis
        if (IsScenarioEnabled -scenarioBit $global:replBit -logged $true)
        {
            GetChangeDataCaptureInfo -TimeOfCapture "Shutdown"
            GetChangeTracking -TimeOfCapture "Shutdown"
        }

        #Set back the setting of  SqlWriterConfig.ini file 
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit) -or ($true -eq (IsScenarioEnabled -scenarioBit $global:basicBit)) )
        {
            GetSQLVSSWriterLog
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function StartStopTimeForDiagnostics ([string] $timeParam, [string] $startOrStop="")
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try
    {
        if ( ($timeParam -eq "0000") -or ($true -eq [String]::IsNullOrWhiteSpace($timeParam)) )
        {
            Write-LogDebug "No start/end time specified for diagnostics" -DebugLogLevel 2
            return
        }
        
        $datetime = $timeParam #format "2020-10-27 19:26:00"
        
        $formatted_date_time = [DateTime]::Parse($datetime, [cultureinfo]::InvariantCulture);
        
        Write-LogDebug "The formatted time is: $formatted_date_time" -DebugLogLevel 3
        Write-LogDebug ("The current time is:" + (Get-Date) ) -DebugLogLevel 3
    
        #wait until time is reached
        if ($formatted_date_time -gt (Get-Date))
        {
            Write-LogWarning "Waiting until the specified $startOrStop time '$timeParam' is reached...(CTRL+C to stop - wait for response)"
        }
        else
        {
            Write-LogInformation "The specified $startOrStop time '$timeParam' is in the past. Continuing execution."     
        }
        

        [int] $increment = 0
        [int] $sleepInterval = 2

        while ((Get-Date) -lt (Get-Date $formatted_date_time)) 
        {
            Start-Sleep -Seconds $sleepInterval

            if ($Host.UI.RawUI.KeyAvailable -and (3 -eq [int]$Host.UI.RawUI.ReadKey("AllowCtrlC,IncludeKeyUp,IncludeKeyDown,NoEcho").Character))
            {
               Write-LogWarning "*******************"
               Write-LogWarning "You pressed CTRL-C. Stopped waiting..."
               Write-LogWarning "*******************"
               break
            }

            $increment += $sleepInterval
            
            if ($increment % 120 -eq 0)
            {
                $startDate = (Get-Date)
                $endDate =(Get-Date $formatted_date_time)
                $delta = [Math]::Round((New-TimeSpan -Start $startDate -End $endDate).TotalMinutes, 2)
                Write-LogWarning "Collection will $startOrStop in $delta minutes ($startOrStop time was set to: $timeParam)"
            }
        }


    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function ArbitrateSelectedScenarios ([bool] $Skip = $false)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    if ($true -eq $Skip)
    {
        return
    }

    #set up Basic bit to ON for several scenarios, unless NoBasic bit is enabled
    if ($false -eq (IsScenarioEnabled -scenarioBit $global:NoBasicBit))
    {
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:replBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:memoryBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:setupBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:IOBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit))
        )
        {
            EnableScenario -pScenarioBit $global:basicBit
        }
        
        
    }
    else #NoBasic is enabled
    {
        #if both NoBasic and Basic are enabled, assume Basic is intended
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:BasicBit ))
        {
            Write-LogInformation "'$BASIC_NAME' and '$NOBASIC_NAME' were selected. We assume you meant to collect data - enabling '$BASIC_NAME'."
            EnableScenario -pScenarioBit $global:basicBit
        }
        else #Collect scenario without basic logs
        {
            Write-LogInformation "'$BASIC_NAME' scenario is disabled due to '$NOBASIC_NAME' parameter value specified "    
        }   
        
    }
    
    #if generalperf and detailedperf are both enabled , disable general perf and keep detailed (which is a superset)
    if (($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
    -and ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit  )) )
    {
        DisableScenario -pScenarioBit $global:generalperfBit
        Write-LogWarning "Disabling '$GENERALPERF_NAME' scenario since '$DETAILEDPERF_NAME' is already enabled"
    }

    #if lightperf and detailedperf are both enabled , disable general perf and keep detailed (which is a superset)
    if (
        ($true -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit )) `
        -and ( ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit ) )  -or ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit ) ))
    )
    {
        DisableScenario -pScenarioBit $global:LightPerfBit
        Write-LogWarning "Disabling '$LIGHTPERF_NAME' scenario since '$DETAILEDPERF_NAME' or '$GENERALPERF_NAME' is already enabled"
    }


    #limit WPR to run only with Basic
    if ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit )) 
    {
        #check if Basic is enabled
        $basic_enabled = IsScenarioEnabled -scenarioBit $global:basicBit

        #reset scenario bit to 0 to turn off all collection
        Write-LogWarning "The '$WPR_NAME' scenario is only allowed to run together with Basic scenario. All other scenarios will be disabled" 
        DisableAllScenarios
        Start-Sleep 5
        
        #enable WPR
        EnableScenario -pScenarioBit $global:wprBit
        
        #if Basic was enabled earlier, turn it back on after all was reset
        if ($true -eq $basic_enabled)
        {
            EnableScenario -pScenarioBit $global:basicBit
        }
        return
    }

}

function Select-Scenario()
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

  try
  {

        Write-LogInformation ""
        Write-LogInformation "Initiating diagnostics collection... " -ForegroundColor Green
        
        #[string[]]$ScenarioArray = "Basic (no performance data)","General Performance (recommended for most cases)","Detailed Performance (statement level and query plans)","Replication","AlwaysON", "Network Trace","Memory", "Generate Memory dumps","Windows Performance Recorder (WPR)", "Setup", "Backup and Restore","IO"
        $scenarioIntRange = 0..($global:ScenarioArray.Length -1)  #dynamically count the values in array and create a range

        #split the $Scenario string to array elements
        $ScenarioArrayLocal = $Scenario.Split('+')

        [int[]]$scenIntArray =@()

        #If Scenario array contains only "MenuChoice" or only "NoBasic" or array is empty (no parameters passed), or MenuChoice+NoBasic is passed, then show Menu
        if ( (($ScenarioArrayLocal -contains "MenuChoice") -and ($ScenarioArrayLocal.Count -eq 1 ) ) `
            -or ( $ScenarioArrayLocal -contains [String]::Empty  -and @($ScenarioArrayLocal).count -lt 2   ) `
            -or ($ScenarioArrayLocal -contains "NoBasic" -and $ScenarioArrayLocal.Count -eq 1) `
            -or ($ScenarioArrayLocal -contains "NoBasic" -and $ScenarioArrayLocal -contains "MenuChoice" -and $ScenarioArrayLocal.Count -eq 2) 
            )
        {
            Write-LogInformation "Please select one of the following scenarios:"
            Write-LogInformation ""
            Write-LogInformation "ID`t Scenario"
            Write-LogInformation "--`t ---------------"

            for($i=0; $i -lt $global:ScenarioArray.Count;$i++)
            {
                Write-LogInformation $i "`t" $global:ScenarioArray[$i]
            }
            Write-LogInformation "--`t ---------------`n"
            Write-LogInformation "See https://aka.ms/sqllogscout#Scenarios for Scenario details"

            $isInt = $false
            $ScenarioIdInt = 777
            $WantDetailedPerf = $false

            

            
            while(($isInt -eq $false) -or ($ValidId -eq $false) -or ($WantDetailedPerf -eq $false))
            {
                Write-LogInformation ""
                Write-LogWarning "Type one or more Scenario IDs (separated by '+') for which you want to collect diagnostic data. Then press Enter" 

                $ScenIdStr = Read-Host "Scenario ID(s) e.g. 0+3+6>" -CustomLogMessage "Scenario Console input:"
                [string[]]$scenStrArray = $ScenIdStr.Split('+')
                
                Write-LogDebug "You have selected the following scenarios (str): $scenStrArray" -DebugLogLevel 3

                
                
                foreach($int_string in $scenStrArray) 
                {
                    try 
                    {
                        #convert the strings to integers and add to int array
                        $int_number = [int]::parse($int_string)
                        $scenIntArray+=$int_number

                        $isInt = $true
                        if($int_string -notin ($scenarioIntRange))
                        {
                            $ValidId = $false
                            $scenIntArray =@()
                            Write-LogError "The ID entered '",$ScenIdStr,"' is not in the list "
                        }
                        else 
                        {
                            $ValidId = $true    
                        }
                    }
                    catch 
                    {
                        Write-LogError "The value entered for ID '",$int_string,"' is not an integer"
                        $scenIntArray =@()
                        $isInt = $false
                    }
                }

                
                #warn users when they select the Detailed perf scenario about perf impact. No warning if all others
                if ($int_number -eq $DetailedPerfScenId) 
                {
                    # if true, proceed, else, disable scenario and try again
                    $WantDetailedPerf = DetailedPerfCollectorWarning

                    if ($false -eq $WantDetailedPerf)
                    {
                        #once user declines, need to clear the selected bit
                        DisableScenario -pScenarioBit $global:detailedperfBit
                        Write-LogWarning "You selected not to proceed with Detailed Perf scenario. Please choose again"    
                    }
                }
                else 
                {
                    $WantDetailedPerf = $true    
                }
                
            } #end of WHILE to select scenario

                #remove duplicate entries
                $scenIntArray = $scenIntArray | Select-Object -Unique 

                Write-LogDebug "You have selected the following scearnios (int): $scenIntArray" -DebugLogLevel 3
                
                foreach ($ScenarioIdInt in $scenIntArray) 
                {
                    switch ($ScenarioIdInt) 
                    {
                        $BasicScenId 
                        { 
                            EnableScenario -pScenarioBit $global:basicBit
                        }
                        $GeneralPerfScenId 
                        {
                            EnableScenario -pScenarioBit $global:generalperfBit
                            
                        }
                        $DetailedPerfScenId 
                        { 
                            EnableScenario -pScenarioBit $global:detailedperfBit

                        }
                        $ReplicationScenId
                        { 
                            EnableScenario -pScenarioBit $global:replBit
                            
                        }
                        $AlwaysOnScenId
                        { 
                            EnableScenario -pScenarioBit $global:alwaysonBit
                        }
                        $NetworkTraceScenId
                        { 
                            EnableScenario -pScenarioBit $global:networktraceBit
                        }
                        $MemoryScenId
                        { 
                            EnableScenario -pScenarioBit $global:memoryBit

                        }
                        $DumpMemoryScenId
                        { 
                            EnableScenario -pScenarioBit $global:dumpMemoryBit
                        }
                        $WprScenId
                        { 
                            EnableScenario -pScenarioBit $global:wprBit
                        }
                        $SetupScenId
                        { 
                            EnableScenario -pScenarioBit $global:setupBit

                        }
                        $BackupRestoreScenId
                        { 
                            EnableScenario -pScenarioBit $global:BackupRestoreBit

                        }
                        $IOScenId
                        { 
                            EnableScenario -pScenarioBit $global:IOBit

                        }
                        $LightPerfScenId
                        {
                            EnableScenario -pScenarioBit $global:LightPerfBit
                        }
                        # NoBasic scenario is only available as a command line option so not here

                        Default {
                                Write-LogError "No valid scenario was picked. Not sure why we are here"
                                return $false
                        }
                    } # end of Switch
                } #end of foreach    

        } #end of if for using a Scenario menu

        #handle the command-line parameter case
        else 
        {
            
            Write-LogDebug "Command-line scenarios selected: $Scenario. Parsed: $ScenarioArray" -DebugLogLevel 3

            #parse startup parameter $Scenario for any values
            foreach ($scenario_name_item in $ScenarioArrayLocal) 
            {
                Write-LogDebug "Individual scenario from Scenario param: $scenario_name_item" -DebugLogLevel 5

                # convert the name to a scenario bit
                $bit = ScenarioNameToBit -pScenarioName $scenario_name_item
                EnableScenario -pScenarioBit $bit

                # send a warning for Detailed Perf
                if ($bit -eq $global:detailedperfBit) 
                {
                    # if true, proceed, else, exit
                    if($false -eq (DetailedPerfCollectorWarning))
                    {
                        exit
                    }
                }

                
            }
            
        }

        #resolove /arbitrate any scenario inconsistencies, conflicts, illogical choices
        ArbitrateSelectedScenarios 


        #set additional properties to certain scenarios
        Set-AutomaticStop 
        Set-InstanceIndependentCollection 
        Set-PerfmonScenarioEnabled

        Write-LogDebug "Scenario Bit value = $global:scenario_bitvalue" -DebugLogLevel 2
        Write-LogInformation "The scenarios selected are: '$global:ScenarioChoice'"

        return $true
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }        
}


function Set-AutomaticStop () 
{
    try 
    {
        # this function is invoked when the user does not need to wait for any long-term collectors (like Xevents, Perfmon, Netmon). 
        # Just gather everything and shut down

        Write-LogDebug "Inside" $MyInvocation.MyCommand

        if ((
                ($true -eq (IsScenarioEnabled -scenarioBit $global:basicBit)) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:dumpMemoryBit )) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit )) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:setupBit )) `
            )  -and
            (
                ($false -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:replBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:memoryBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:IOBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit ))
            ) )
        {
            Write-LogInformation "The selected '$global:ScenarioChoice ' collector(s) will stop automatically after logs are gathered" -ForegroundColor Green
            $global:stop_automatically = $true
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    
}

function Set-InstanceIndependentCollection () 
{
    # this function is invoked when the data collected does not target a specific SQL instance (e.g. WPR, Netmon, Setup). 

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
            
        if ((
                ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit )) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit )) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:IOBit ))
                
            )  -and
            (
                ($false -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:memoryBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:basicBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:replBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:dumpMemoryBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:setupBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit )) `
            ) )
        {
            Write-LogInformation "The selected '$global:ScenarioChoice' scenario(s) gather logs independent of a SQL instance"
            $global:instance_independent_collection = $true    
        }

    }
    catch 
    {
        
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
   
}


function Set-PerfmonScenarioEnabled()
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:memoryBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:IOBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit )) 
        )
        {
            $global:perfmon_scenario_enabled = $true
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    
}



function Start-DiagCollectors ()
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    Write-LogDebug "The ScenarioChoice array contains the following entries: '$global:ScenarioChoice' " -DebugLogLevel 3

    # launch the scenario collectors that are enabled
    # common collectors (basic) will be called on shutdown
    if (IsScenarioEnabled -scenarioBit $global:basicBit -logged $true)
    {
        Write-LogInformation "Basic collectors will execute on shutdown"
    }
    if (IsScenarioEnabled -scenarioBit $global:LightPerfBit -logged $true)
    {
        Invoke-LightPerfScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:generalperfBit -logged $true)
    {
        Invoke-GeneralPerfScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:detailedperfBit -logged $true)
    {
        Invoke-DetailedPerfScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:alwaysonBit -logged $true)
    {
        Invoke-AlwaysOnScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:replBit -logged $true)
    {
        Invoke-ReplicationScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:networktraceBit -logged $true)
    {
        Invoke-NetworkScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:memoryBit -logged $true)
    {
        Invoke-MemoryScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:dumpMemoryBit -logged $true)
    {
        Invoke-DumpMemoryScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:wprBit -logged $true)
    {
        Invoke-WPRScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:setupBit -logged $true)
    {
        Invoke-SetupScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit -logged $true)
    {
        Invoke-BackupRestoreScenario
    } 
    if (IsScenarioEnabled -scenarioBit $global:IOBit -logged $true)
    {
        Invoke-IOScenario
    }    
    if ($false -eq (IsScenarioEnabled -scenarioBit $global:basicBit))
    {
        Write-LogInformation "Diagnostic collection started." -ForegroundColor Green #DO NOT CHANGE - Message is backward compatible
        Write-LogInformation ""
    }
}

function Stop-DiagCollectors() 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    $ValidStop = $false

    # Wait for stop time to be reached and shutdown at that time. No need for user to type STOP
    # for Basic scenario we don't need to wait for long-term data collection as there are only static logs
    if (($DiagStopTime -ne "0000") -and ($false -eq [String]::IsNullOrWhiteSpace($DiagStopTime)) -and ((IsScenarioEnabledExclusively -scenarioBit $global:BasicBit) -eq $false))
    {
        #likely a timer parameter is set to stop at a specified time
        StartStopTimeForDiagnostics -timeParam $DiagStopTime -startOrStop "stop"

        #bypass the manual "STOP" interactive user command and cause system to stop
        $global:stop_automatically = $true
    }
    try
    {
        # This function will display error messsage to the user if found any in internal folder
        CheckInternalFolderError

        if ($false -eq $global:stop_automatically)
        { #wait for user to type "STOP"
            while ($ValidStop -eq $false) 
            {
                Write-LogInformation "Please type 'STOP' to terminate the diagnostics collection when you finished capturing the issue" -ForegroundColor Green
                $StopStr = Read-Host ">" -CustomLogMessage "StopCollection Console input:"
                    
                #validate this PID is in the list discovered 
                if (($StopStr -eq "STOP") -or ($StopStr -eq "stop") ) 
                {
                    $ValidStop = $true
                    Write-LogInformation "Shutting down the collector" -ForegroundColor Green #DO NOT CHANGE - Message is backward compatible
                    break;
                }
                else 
                {
                    $ValidStop = $false
                }
            }
        }  
        else 
        {
            Write-LogInformation "Shutting down automatically. No user interaction to stop collectors" -ForegroundColor Green
            Write-LogInformation "Shutting down the collectors"  #DO NOT CHANGE - Message is backward compatible
        }        
        #create an output directory. -Force will not overwrite it, it will reuse the folder
        #$global:present_directory = Convert-Path -Path "."

        $partial_output_file_name = CreatePartialOutputFilename -server $server
        $partial_error_output_file_name = CreatePartialErrorOutputFilename -server $server


        #STOP the XEvent sessions
        if ( (($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit)) )
            ) 
        { 
            #avoid errors if there was not Xevent collector started 
            Stop-Xevent -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }

        if ( $true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit ) ) 
        { 
            #avoid errors if there was not Xevent collector started 
            Stop-AlwaysOn-Xevents -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }

        

        #Disable backup restore trace flag
        if ( $true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit ) ) 
        { 
            Disable-BackupRestoreTraceFlag -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }

        #STOP Perfmon
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:memoryBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
            )
        {
            Stop-Perfmon -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
           
        }

        #wait for other work to finish
        Start-Sleep -Seconds 3

        #send the output file to \internal
        Kill-ActiveLogscoutSessions -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name

        Start-Sleep -Seconds 1


        #STOP Network trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit))
        {
            Stop-NetworkTrace -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }

        
        #stop WPR trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit ))
        {
            Stop-WPRTrace -partial_error_output_file_name $partial_error_output_file_name " -skippdbgen"
        }
        #stop storport trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:IOBit ))
        {
            Stop-StorPortTrace -partial_error_output_file_name $partial_error_output_file_name
        }

        # shutdown collectors
        Invoke-OnShutDown

        Write-LogInformation "Waiting 3 seconds to ensure files are written to and closed by any program including anti-virus..." -ForegroundColor Green
        Start-Sleep -Seconds 3



    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}


#***********************************stop collector function start********************************


function Stop-Xevent([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    #avoid errors if there was not Xevent collector started
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    { 
        $collector_name = "Xevents_Stop"
        $alter_event_session_stop = "ALTER EVENT SESSION [$global:xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_session] ON SERVER;" 

        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_stop -has_output_results $false
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return  
    }
}

function Stop-AlwaysOn-Xevents([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    #avoid errors if there was not Xevent collector started 
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "Xevents_Alwayson_Data_Movement_Stop"
        $alter_event_session_ag_stop = "ALTER EVENT SESSION [$global:xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_alwayson_session] ON SERVER;" 
        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_ag_stop -has_output_results $false
     }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return  
    }
}

function Disable-BackupRestoreTraceFlag([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        Write-LogDebug "Disabling trace flags for Backup/Restore: $Disabled_Trace_Flag " -DebugLogLevel 2

        $collector_name = "Disable_BackupRestore_Trace_Flags"
        $Disabled_Trace_Flag = "DBCC TRACEOFF(3004,3212,3605,-1)" 
        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $Disabled_Trace_Flag -has_output_results $false
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return 
    }
}

function Stop-Perfmon([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "PerfmonStop"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon"
        $executable = "cmd.exe"
        Write-LogInformation "Executing shutdown command: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}


function Kill-ActiveLogscoutSessions([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "KillActiveLogscoutSessions"
        $query = "declare curSession 
                CURSOR for select 'kill ' + cast( session_id as varchar(max)) from sys.dm_exec_sessions where host_name = 'sqllogscout' and program_name='SQLCMD' and session_id <> @@spid
                open curSession
                declare @sql varchar(max)
                fetch next from curSession into @sql
                while @@FETCH_STATUS = 0
                begin
                    exec (@sql)
                    fetch next from curSession into @sql
                end
                close curSession;
                deallocate curSession;"  

        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $query -has_output_results $false
    }
    catch 
	{
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return  
    }
}

function Stop-NetworkTrace([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "NettraceStop"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 

        $argument_list = "/C title Stopping Network trace... & echo This process may take a few minutes. Do not close this window... & StopNetworkTrace.bat"
        $executable = "cmd.exe"

        Write-LogInformation "Executing shutdown command: $collector_name"

        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Normal -PassThru
        $pn = $p.ProcessName
        $sh = $p.SafeHandle
        if($false -eq $p.HasExited)   
        {
            [void]$global:processes.Add($p)
        }

        [int]$cntr = 0

        while ($false -eq $p.HasExited) 
        {
            [void] $p.WaitForExit(20000)
            if ($cntr -gt 0) {
                #Write-LogWarning "Please wait for network trace to stop..."
                Write-LogWarning "Shutting down network tracing may take a few minutes. Please wait..."
            }
            $cntr++
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}

function Stop-WPRTrace([string]$partial_error_output_file_name,[string] $stoppdbgen)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = $global:wpr_collector_name
        $partial_output_file_name_wpr = CreatePartialOutputFilename -server $server
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name_wpr -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"
        $executable = "cmd.exe"
        $argument_list = $argument_list = "/C wpr.exe -stop " + $output_file + $stoppdbgen
        Write-LogInformation "Executing shutdown command: $collector_name"
        Write-LogDebug $executable $argument_list
        # StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
        $pn = $p.ProcessName
        $sh = $p.SafeHandle
        if($false -eq $p.HasExited)   
        {
            [void]$global:processes.Add($p)
        }

        $cntr = 0 #reset the counter
        while ($false -eq $p.HasExited) 
        {
            [void] $p.WaitForExit(5000)
        
            if ($cntr -gt 0) {
                Write-LogWarning "Please wait for WPR trace to stop..."
            }
            $cntr++
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return  
    }
}

function Stop-StorPortTrace([string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "StorPort_Stop"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        $argument_list = "/C logman stop ""storport"" -ets"
        $executable = "cmd.exe"
        Write-LogInformation "Executing shutdown command: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}


function GetSQLVSSWriterLog([string]$partial_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    if ($global:sql_major_version -lt 15)
    {
        Write-LogDebug "SQL Server major version is $global:sql_major_version. Not collecting SQL VSS log" -DebugLogLevel 4
        return
    }

    try
    {
        
        $collector_name = "GetSQLVSSWriterLog"
        Write-LogInformation "Executing collector: $collector_name"
        
        
        [string]$DestinationFolder = $global:output_folder 

        if ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit))
        {
            # copy the SqlWriterConfig.txt file in 
            $file = 'C:\Program Files\Microsoft SQL Server\90\Shared\SqlWriterLogger.txt'
            Get-ChildItem $file |  Copy-Item -Destination $DestinationFolder | Out-Null


            $file = 'C:\Program Files\Microsoft SQL Server\90\Shared\SqlWriterConfig.ini'
            if (!(Test-Path $file ))  
            {
                Write-LogWarning "$file does not exist"
            }
            else
            {
                (Get-Content $file).Replace("TraceLevel=VERBOSE","TraceLevel=DEFAULT") | Set-Content $file
                (Get-Content $file).Replace("TraceFileSizeMb=10","TraceFileSizeMb=1") | Set-Content $file
            }
            # Bugfixrestart sqlwriter
            if ($global:restart_sqlwriter -in "Y" , "y" , "Yes" , "yes")
            {
                Restart-Service SQLWriter -force
                Write-LogInformation "SQLWriter Service has been restarted"
            }
        }
        # if Basic scenario only, then collect the default SQL 2019+ VSS writer trace
        elseif (($true -eq (IsScenarioEnabled -scenarioBit $global:basicBit)) -and ($false -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit)) )     
        {
            $file = 'C:\Program Files\Microsoft SQL Server\90\Shared\SqlWriterLogger.txt'
            Get-childitem $file |  Copy-Item -Destination $DestinationFolder | Out-Null
        }
        else {
            Write-LogDebug "No SQLWriterLogger.txt will be collected. Not sure why we are here"
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}


#**********************************Stop collector function end***********************************


function Invoke-DiagnosticCleanUpAndExit()
{

    Write-LogDebug "inside" $MyInvocation.MyCommand

    try
    {
        Write-LogWarning "Launching cleanup and exit routine... please wait"
        $server = $global:sql_instance_conn_str

        #quick cleanup to ensure no collectors are running. 
        #Kill existing sessions
        #send the output file to \internal
        $query = "
            declare curSession
            CURSOR for select 'kill ' + cast( session_id as varchar(max)) from sys.dm_exec_sessions where host_name = 'sqllogscout' and program_name='SQLCMD' and session_id <> @@spid
            open curSession
            declare @sql varchar(max)
            fetch next from curSession into @sql
            while @@FETCH_STATUS = 0
            begin
                exec (@sql)
                fetch next from curSession into @sql
            end
            close curSession;
            deallocate curSession;
            "  
        if ($server -ne $NO_INSTANCE_NAME)
        {
            $executable = "sqlcmd.exe"
            $argument_list ="-S" + $server +  " -E -Hsqllogscout_cleanup -w8000 -Q`""+ $query + "`" "
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
                
        }

        
        #STOP the XEvent sessions

        if ($server -ne $NO_INSTANCE_NAME)
        {  
            $alter_event_session_stop = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_session] ON SERVER; END" 
            $executable = "sqlcmd.exe"
            $argument_list = "-S" + $server + " -E -Hsqllogscout_cleanup -w8000 -Q`"" + $alter_event_session_stop + "`""
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
                

            #avoid errors if there was not Xevent collector started 
            $alter_event_session_ag_stop = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_alwayson_session] ON SERVER; END" 
            $executable = "sqlcmd.exe"
            $argument_list = "-S" + $server + " -E -Hsqllogscout_stop -w8000 -Q`"" + $alter_event_session_ag_stop + "`""
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
            
        }

        #STOP Perfmon
        $executable = "cmd.exe"
        $argument_list ="/C logman stop logscoutperfmon & logman delete logscoutperfmon"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden


        #cleanup network trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit ))
        {
            $executable = "cmd.exe"
            $argument_list ="/C title Cleanup Network trace... & echo This process may take a few minutes. Do not close this window... & StopNetworkTrace.bat"
            $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Normal -PassThru
            Write-LogWarning "Cleaning up network tracing may take a few minutes. Please wait..."

            $pn = $p.ProcessName
            $sh = $p.SafeHandle
            if($false -eq $p.HasExited)   
            {
                [void]$global:processes.Add($p)
            }

            [int]$cntr = 0

            while ($false -eq $p.HasExited) 
            {
                [void] $p.WaitForExit(20000)
                if ($cntr -gt 0) {
                    #Write-LogWarning "Please wait for network trace to stop..."
                    Write-LogWarning "Shutting down network tracing may take a few minutes. Please do not close this window ..."
                }
                $cntr++
            }

        }

        #stop the WPR process if running any on the system
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit ))
        {
            $executable = "cmd.exe"
            $argument_list = $argument_list = "/C wpr.exe -cancel " 
            # StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden
            Write-LogDebug $executable $argument_list
            $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
            $pn = $p.ProcessName
            $sh = $p.SafeHandle
            if($false -eq $p.HasExited)   
            {
                [void]$global:processes.Add($p)
            }

            [int]$cntr = 0 
            while ($false -eq $p.HasExited) 
            {
                [void] $p.WaitForExit(5000)

                if ($cntr -gt 0)
                {
                    Write-LogWarning "Continuing to wait for WPR trace to cancel..."
                }
                $cntr++
            } 
        } #if wpr enabled

        if (($server -ne $NO_INSTANCE_NAME) -and ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit )) )
        {
            #clean up backup/restore tace flags
            $Disabled_Trace_Flag = "DBCC TRACEOFF(3004,3212,3605,-1)" 
            $argument_list = "-S" + $server + " -E -Hsqllogscout_stop -w8000 -Q`"" + $Disabled_Trace_Flag + "`""
            StartNewProcess -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden
                
        } 

        Write-LogDebug "Checking that all processes terminated..."

        #allowing some time for above processes to clean-up
        Start-Sleep 5

        [string]$processname = [String]::Empty
        [string]$processid = [String]::Empty
        [string]$process_startime = [String]::Empty

        foreach ($p in $global:processes) 
        {
            # get the properties of the processes we stored in the array into string variables so we can show them
            if ($true -ne [String]::IsNullOrWhiteSpace($p.ProcessName) )
            {
                $processname = $p.ProcessName
            }
            else 
            {
                $processname = "NoProcessName"
            }
            if ($null -ne $p.Id )
            {
                $processid = $p.Id.ToString()
            }
            else 
            {
                $processid = "0"
            }
            if ($null -ne $p.StartTime)
            {
                $process_startime = $p.StartTime.ToString('yyyyMMddHHmmssfff')
            }
            else 
            {
                $process_startime = "NoStartTime"
            }

            Write-LogDebug "Process contained in Processes array is '$processname', $processid, $process_startime" -DebugLogLevel 5

            if ($p.HasExited -eq $false) 
            {
                $cur_proc = Get-Process -Id $p.Id

                $cur_proc_id = $cur_proc.Id.ToString()
                $cur_proc_starttime = $cur_proc.StartTime.ToString('yyyyMMddHHmmssfff')
                $cur_proc_name = $cur_proc.ProcessName

                Write-LogDebug "Original process which hasn't exited and is matched by Id is: $cur_proc_id, $cur_proc_name, $cur_proc_starttime" -DebugLogLevel 5

                if (($cur_proc.Id -eq $p.Id) -and ($cur_proc.StartTime -eq $p.StartTime) -and ($cur_proc.ProcessName -eq $p.ProcessName) )
                {
                    Write-LogInformation ("Process ID " + ([string]$p.Id) + " has not exited yet.")
                    Write-LogInformation ("Process CommandLine for Process ID " + ([string]$p.Id) + " is: " + $OSCommandLine)
                    Write-LogDebug ("Process CPU Usage Total / User / Kernel: " + [string]$p.TotalProcessorTime + "     " + [string]$p.UserProcessorTime + "     " + [string]$p.PrivilegedProcessorTime) -DebugLogLevel 3
                    Write-LogDebug ("Process Start Time: " + [string]$p.StartTime) -DebugLogLevel 3
                    Write-LogDebug ("Process CPU Usage %: " + [string](($p.TotalProcessorTime.TotalMilliseconds / ((Get-Date) - $p.StartTime).TotalMilliseconds) * 100)) -DebugLogLevel 3
                    Write-LogDebug ("Process Peak WorkingSet (MB): " + [string]$p.PeakWorkingSet64 / ([Math]::Pow(1024, 2))) -DebugLogLevel 3
                    Write-LogWarning ("Stopping Process ID " + ([string]$p.Id))
                    Stop-Process $p
                }
            }
            else {
                Write-LogDebug "Process '$processname', $processid, $process_startime has exited." -DebugLogLevel 5
            }
        }
    
        Write-LogInformation "Thank you for using SQL LogScout!" -ForegroundColor Yellow
        exit
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}



#======================================== END OF Diagnostics Collection SECTION

#======================================== START OF Bitmask Enabling, Diabling and Checking of Scenarios

function ScenarioBitToName ([int] $pScenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        [string] $scenName = [String]::Empty

        switch ($pScenarioBit) 
        {
            $global:basicBit { $scenName = $BASIC_NAME}
            $global:generalperfBit { $scenName = $GENERALPERF_NAME}
            $global:detailedperfBit { $scenName = $DETAILEDPERF_NAME}
            $global:replBit { $scenName = $REPLICATION_NAME}
            $global:alwaysonBit { $scenName = $ALWAYSON_NAME}
            $global:networktraceBit { $scenName = $NETWORKTRACE_NAME}
            $global:memoryBit { $scenName = $MEMORY_NAME}
            $global:dumpMemoryBit { $scenName = $DUMPMEMORY_NAME}
            $global:wprBit { $scenName = $WPR_NAME}
            $global:setupBit { $scenName = $SETUP_NAME}
            $global:BackupRestoreBit { $scenName = $BACKUPRESTORE_NAME}
            $global:IOBit { $scenName = $IO_NAME}
            $global:LightPerfBit { $scenName = $LIGHTPERF_NAME}
            $global:NoBasicBit {$scenName = $NOBASIC_NAME}
            Default {}
        }
    
       Write-LogDebug "Scenario bit $pScenarioBit translates to $scenName" -DebugLogLevel 5
    
        return $scenName    

    }
    catch 
    {
        
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    
}


function ScenarioNameToBit ([string] $pScenarioName)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        [int] $scenBit = 0

        switch ($pScenarioName) 
        {
            $BASIC_NAME { $scenBit = $global:basicBit}
            $GENERALPERF_NAME { $scenBit = $global:generalperfBit}
            $DETAILEDPERF_NAME { $scenBit = $global:detailedperfBit}
            $REPLICATION_NAME { $scenBit = $global:replBit}
            $ALWAYSON_NAME { $scenBit = $global:alwaysonBit}
            $NETWORKTRACE_NAME { $scenBit = $global:networktraceBit}
            $MEMORY_NAME { $scenBit = $global:memoryBit}
            $DUMPMEMORY_NAME { $scenBit = $global:dumpMemoryBit}
            $WPR_NAME { $scenBit = $global:wprBit}
            $SETUP_NAME { $scenBit = $global:setupBit}
            $BACKUPRESTORE_NAME { $scenBit = $global:BackupRestoreBit}
            $IO_NAME { $scenBit = $global:IOBit}
            $LIGHTPERF_NAME { $scenBit = $global:LightPerfBit}
            $NOBASIC_NAME {$scenBit = $global:NoBasicBit}
            Default {}
        }
    
        Write-LogDebug "Scenario name $pScenarioName translates to bit $scenBit" -DebugLogLevel 5
    
        return $scenBit    

    }
    catch 
    {
        
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    
}

function EnableScenario([int]$pScenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        
        [string] $scenName = ScenarioBitToName -pScenarioBit $pScenarioBit

        Write-LogDebug "Enabling scenario bit $pScenarioBit, '$scenName' scenario" -DebugLogLevel 3

        #de-duplicate entries
        if (!$global:ScenarioChoice.Contains($scenName))
        {
            #populate the ScenarioChoice array
            [void] $global:ScenarioChoice.Add($scenName)

        }

        $global:scenario_bitvalue = $global:scenario_bitvalue -bor $pScenarioBit
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function DisableScenario([int]$pScenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        Write-LogDebug "Disabling scenario bit $pScenarioBit" -DebugLogLevel 3
    
        [string] $scenName = ScenarioBitToName -pScenarioBit $pScenarioBit
        
        $global:ScenarioChoice.Remove($scenName)
        $global:scenario_bitvalue = $global:scenario_bitvalue -bxor $pScenarioBit    
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem    
    }
    
}

function DisableAllScenarios()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        Write-LogDebug "Setting Scenarios bit to 0" -DebugLogLevel 3

        #reset both scenario structures
        $global:ScenarioChoice.Clear()
        $global:scenario_bitvalue = 0    
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem        
    }
    
}

function IsScenarioEnabled([int]$scenarioBit, [bool] $logged = $false)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try
    {
        #perform the check 
        $bm_enabled = $global:scenario_bitvalue -band $scenarioBit

        if ($true -eq $logged)
        {
            [string] $scenName = ScenarioBitToName -pScenarioBit $scenarioBit
            Write-LogDebug "The bitmask result for $scenName scenario = $bm_enabled" -DebugLogLevel 4
        }

        #if enabled, return true, else false
        if ($bm_enabled -gt 0)
        {
            if ($true -eq $logged)
            {
                Write-LogDebug "$scenName scenario is enabled" -DebugLogLevel 2
            }
            
            return $true
        }
        else
        {
            if ($true -eq $logged)
            {
                Write-LogDebug "$scenName scenario is disabled" -DebugLogLevel 2
            }
            return $false
        }    
    }
    
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}

function IsScenarioEnabledExclusively([int]$scenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    
    $ret = $false;

    try
    {
        if (IsScenarioEnabled -scenarioBit $scenarioBit)
        {
            #check all bits to see if more than the one bit is enabled. If yes,stop the loop and return (other bits are enabled)

            # scenario name is Key and bit is value
            foreach ($name in $ScenarioBitTbl.Keys)
            {
                $ret = IsScenarioEnabled -scenarioBit $ScenarioBitTbl[$name]

                #if the scenario is not the one we are testing for and its bit is enabled, it is not exclusive, so  bail out
                if (($ret -eq $true) -and ($ScenarioBitTbl[$name] -ne $scenarioBit))
                {
                    return $false
                }

            }

            #if we got here, it must be the only one - so exclusive
            return $true
        }
        else 
        {
            #the bit is not enabled at all
            return $false    
        }

    }
        
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}



#======================================== END OF Bitmask Enabling, Diabling and Checking of Scenarios



#======================================== START OF PERFMON COUNTER FILES SECTION

Import-Module .\PerfmonCounters.psm1

#======================================== END OF PERFMON COUNTER FILES SECTION



function Check-ElevatedAccess
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    try 
    {
        #check for administrator rights
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
        {
            Write-Warning "Elevated privilege (run as Admininstrator) is required to run SQL_LogScout! Exiting..."
            exit
        }
        
    }

    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit_logscout $true
    }
    

}

function Confirm-SQLPermissions
{
<#
    .SYNOPSIS
        Returns true if user has VIEW SERVER STATE permission in SQL Server, otherwise warns about lack of permissions and request confirmation, returns true if user confirms otherwise returns false.

    .DESCRIPTION
        Returns true if user has VIEW SERVER STATE permission in SQL Server, otherwise warns about lack of permissions and request confirmation, returns true if user confirms otherwise returns false.
    
    .PARAMETER SQLUser
        Optional. SQL Server User Name for SQL Authentication

    .PARAMETER SQLPassword
        Optional. SQL Server Password for SQL Authentication

    .EXAMPLE
        Confirm-SQLPermissions -SQLInstance "SERVER"
        Confirm-SQLPermissions -SQLInstance "SRV\INST" -SQLUser "sqllogin" -Password "sqlpwd"
#>
[CmdletBinding()]
param ( 
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SQLUser,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SQLPwd
    )

    Write-LogDebug "inside " $MyInvocation.MyCommand

    if (($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME) -or ($true -eq $global:instance_independent_collection ) )
    {
        Write-LogWarning "No SQL Server instance found or Instance-independent collection. SQL Permissions-checking is not necessary"
        return $true
    }
    elseif ($global:sql_instance_conn_str -ne "")
    {
        $SQLInstance = $global:sql_instance_conn_str
    }
    else {
        Write-LogError "SQL Server instance name is empty. Exiting..."
        exit
    }
    
    $server = $global:sql_instance_conn_str
    $partial_output_file_name = CreatePartialOutputFilename ($server)
    $XELfilename = $partial_output_file_name + "_" + $global:xevent_target_file + "_test.xel"

    $SQLInstanceUpperCase = $SQLInstance.ToUpper()

    Write-LogDebug "Received parameter SQLInstance: `"$SQLInstance`"" -DebugLogLevel 2
    Write-LogDebug "Received parameter SQLUser: `"$SQLUser`"" -DebugLogLevel 2
    Write-LogDebug "Received parameter SQLPassword (true/false): " (-not ($null -eq $SQLPassword)) #we don't print the password, just inform if we received it or not

    #query bellow does substring of SERVERPROPERTY('ProductVersion') instead of using SERVERPROPERTY('ProductMajorVersion') for backward compatibility with SQL Server 2012 & 2014
    $SqlQuery = "select SUSER_SNAME() login_name, HAS_PERMS_BY_NAME(null, null, 'view server state') has_view_server_state, HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') has_alter_any_event_session, LEFT(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), (CHARINDEX(N'.', CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)))-1)) sql_major_version, CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT) as sql_major_build"
    $ConnString = "Server=$SQLInstance;Database=master;"

    #if either SQLUser or SQLPassword are null we setup Integrated Authentication
    #otherwise if we received both we setup SQL Authentication
    if (($null -eq $SQLUser) -or ($null -eq $SQLPassword))
    {
        $ConnString += "Integrated Security=True;"
    } else
    {
        $ConnString += "User Id=$SQLUser;Password=$SQLPassword"
    }

    Write-LogDebug "Creating SqlClient objects and setting parameters" -DebugLogLevel 2
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $ConnString
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlQuery
    $SqlCmd.Connection = $SqlConnection
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $SqlAdapter.SelectCommand = $SqlCmd
    $DataSetPermissions = New-Object System.Data.DataSet

    Write-LogDebug "About to call SqlDataAdapter.Fill()" -DebugLogLevel 2
    try {
        $SqlAdapter.Fill($DataSetPermissions) | Out-Null #fill method returns rowcount, Out-Null prevents the number from being printed in console    
    }
    catch {
        Write-LogError "Could not connect to SQL Server instance '$SQLInstance' to validate permissions."
        
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.InnerException.Message 
        Write-LogError "$mycommand Function failed with error:  $error_msg"
        
        # we can't connect to SQL, probably whole capture will fail, so we just abort here
        return $false
    }

    $global:sql_major_version = $DataSetPermissions.Tables[0].Rows[0].sql_major_version
    $global:sql_major_build = $DataSetPermissions.Tables[0].Rows[0].sql_major_build
    $account = $DataSetPermissions.Tables[0].Rows[0].login_name
    $has_view_server_state = $DataSetPermissions.Tables[0].Rows[0].has_view_server_state
    $has_alter_any_event_session = $DataSetPermissions.Tables[0].Rows[0].has_alter_any_event_session

    Write-LogDebug "SQL Major Version: " $global:sql_major_version -DebugLogLevel 3
    Write-LogDebug "SQL Account Name: " $account -DebugLogLevel 3
    Write-LogDebug "Has View Server State: " $has_view_server_state -DebugLogLevel 3
    Write-LogDebug "Has Alter Any Event Session: " $has_alter_any_event_session -DebugLogLevel 3
    Write-LogDebug "SQL Major Build: " $global:sql_major_build -DebugLogLevel 3

    $collectingXEvents = IsCollectingXevents

    # if the account doesn't have ALTER ANY EVENT SESSION, we don't bother testing XEvent
    if((1 -eq $has_alter_any_event_session) -and ($collectingXEvents))
    {
        Write-LogDebug "Account has ALTER ANY EVENT SESSION. Check that we can start an Event Session."
        
        # temp sproc that tests creating an XEvent session
        # returns 1 for success
        # returns zero for failure
        $SqlQuery = "CREATE PROCEDURE #TestXEvents
                    AS
                    BEGIN
                    BEGIN TRY
                        
                        -- CHECK AND DROP IF THE TEST EVENT SESSION EXISTS BEFORE PROCEEDING
                        IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = 'xevent_SQLLogScout_Test')
                        BEGIN
                            DROP EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER
                        END

                        -- CREATE AND START THE TEST EVENT SESSION
                        CREATE EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER  ADD EVENT sqlserver.existing_connection
                        ADD TARGET package0.event_file(SET filename=N'$XELfilename', max_file_size=(500), max_rollover_files=(50))
                        WITH (MAX_MEMORY=200800 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=10 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_CPU,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
                        ALTER EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER STATE = START

                        -- IF WE SUCCEEDED THEN JUST REMOVE THE TEST EVENT SESSION
                        IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = 'xevent_SQLLogScout_Test')
                        BEGIN
                            DROP EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER
                        END

                        -- RETURN 1 TO INDICATE SUCCESS 
                        RETURN 1

                    END TRY
                    BEGIN CATCH

                        -- IF THERE'S A DOOMED TRANSACTION WE ROLLBACK
                        IF XACT_STATE() = -1 ROLLBACK TRANSACTION

                        SELECT  
                            ERROR_NUMBER() AS ErrorNumber  
                            ,ERROR_SEVERITY() AS ErrorSeverity  
                            ,ERROR_STATE() AS ErrorState  
                            ,ERROR_PROCEDURE() AS ErrorProcedure  
                            ,ERROR_LINE() AS ErrorLine  
                            ,ERROR_MESSAGE() AS ErrorMessage;  
                        
                        -- CHECK FOR XE SESSIO AND CLEANUP
                        IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = 'xevent_SQLLogScout_Test')
                        BEGIN
                            DROP EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER
                        END

                        -- RETURN ZERO TO INDICATE FAILURE
                        RETURN 0

                    END CATCH
                    END"
        
        Write-LogDebug "Creating Sproc #TestXEvents" -DebugLogLevel 2
        
        if ("Open" -ne $SqlConnection.State){
            $SqlConnection.Open() | Out-Null
        }

        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.CommandText = $SqlQuery
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.ExecuteNonQuery() | Out-Null

        Write-LogDebug "Calling Sproc #TestXEvents" -DebugLogLevel 2
        $SqlRetValue = New-Object System.Data.SqlClient.SqlParameter
        $SqlRetValue.DbType = [System.Data.DbType]::Int32
        $SqlRetValue.Direction = [System.Data.ParameterDirection]::ReturnValue

        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
        $SqlCmd.CommandText = "#TestXEvents"
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.Parameters.Add($SqlRetValue) | Out-Null 
        
        $SqlReader = $SqlCmd.ExecuteReader([System.Data.CommandBehavior]::SingleRow.ToInt32([CultureInfo]::InvariantCulture) + [System.Data.CommandBehavior]::SingleResult.ToInt32([CultureInfo]::InvariantCulture))

        # XE Test Successful
        if (1 -eq $SqlRetValue.Value)
        {    
            Write-LogDebug "Extended Event Session test SUCCESSFUL" -DebugLogLevel 2
            [bool]$XETestSuccessfull = $true
        }
        else
        {    
            Write-LogDebug "Extended Event Session test FAILURE" -DebugLogLevel 2
            [bool]$XETestSuccessfull = $false
            
            $SqlReader.Read() | Out-Null # we expect a single line so no need to Read() in a loop
            $SqlErrorNumber = $SqlReader.GetInt32($SqlReader.GetOrdinal("ErrorNumber"))
            $SqlErrorSeverity = $SqlReader.GetInt32($SqlReader.GetOrdinal("ErrorSeverity"))
            $SqlErrorState = $SqlReader.GetInt32($SqlReader.GetOrdinal("ErrorState"))
            $SqlErrorProcedure = $SqlReader.GetString($SqlReader.GetOrdinal("ErrorProcedure"))
            $SqlErrorLine = $SqlReader.GetInt32($SqlReader.GetOrdinal("ErrorLine"))
            $SqlErrorMessage = $SqlReader.GetString($SqlReader.GetOrdinal("ErrorMessage"))

            Write-LogDebug "Msg $SqlErrorNumber, Level $SqlErrorSeverity, State $SqlErrorState, Procedure $SqlErrorProcedure, Line $SqlErrorLine" -DebugLogLevel 3
            Write-LogDebug "Message: $SqlErrorMessage" -DebugLogLevel 3
        }

        Write-LogDebug "Closing SqlConnection" -DebugLogLevel 2
        $SqlConnection.Close() | Out-Null

        Write-LogDebug "Cleanup any XEL files remaining from test" -DebugLogLevel 2
        Remove-Item ($XELfilename.Replace("_test.xel", "_test*.xel")) | Out-Null

    } # if(1 -eq $has_alter_any_event_session)
    
    if ((1 -eq $has_view_server_state) -and (1 -eq $has_alter_any_event_session) -and ($XETestSuccessfull -or (-not($collectingXEvents))))
    {
        Write-LogInformation "Confirmed that $account has VIEW SERVER STATE on SQL Server Instance '$SQLInstanceUpperCase'"
        Write-LogInformation "Confirmed that $account has ALTER ANY EVENT SESSION on SQL Server Instance '$SQLInstanceUpperCase'"
        
        if (($collectingXEvents) -and ($XETestSuccessfull)) {
            Write-LogInformation "Confirmed that SQL Server Instance $SQLInstance can write Extended Event Session Target at $XELfilename"
        }
        
        # user has view server state and alter any event session
        # SQL can write extended event session
        return $true
    } else {

        # server principal does not have VIEW SERVER STATE or does not have ALTER ANY EVENT SESSION
        if ((1 -ne $DataSetPermissions.Tables[0].Rows[0].has_view_server_state) -or (1 -ne $DataSetPermissions.Tables[0].Rows[0].has_alter_any_event_session)) {
            Write-LogDebug "either has_view_server_state or has_alter_any_event_session returned different than one, user does not have view server state" -DebugLogLevel 2

            Write-LogWarning "User account $account does not posses the required privileges in SQL Server instance '$SQLInstanceUpperCase'"
            Write-LogWarning "Proceeding with capture will result in SQLDiag not producing the necessary information."
            Write-LogWarning "To grant minimum privilege for a successful data capture, connect to SQL Server instance '$SQLInstanceUpperCase' using administrative account and execute the following:"
            Write-LogWarning ""

            if (1 -ne $DataSetPermissions.Tables[0].Rows[0].has_view_server_state) {
                Write-LogWarning "GRANT VIEW SERVER STATE TO [$account]"
            }

            if (1 -ne $DataSetPermissions.Tables[0].Rows[0].has_alter_any_event_session) {
                Write-LogWarning "GRANT ALTER ANY EVENT SESSION TO [$account]"
            } 
            
            Write-LogWarning ""
        }

        # server principal has ALTER ANY EVENT SESSION permission
        # but creating the extended event session still failed
        if ((0 -ne $DataSetPermissions.Tables[0].Rows[0].has_alter_any_event_session) -and (-not($XETestSuccessfull))) {
            # account has ALTER ANY EVENT SESSION yet we could not start extended event session
            Write-LogError "Extended Event log collection test failed for SQL Server '$SQLInstanceUpperCase'"
            Write-LogError "SQL Server Error: $SqlErrorMessage"


            $host_name = $global:host_name
            $instance_name = Get-InstanceNameOnly ($global:sql_instance_conn_str)
            
            if ($instance_name -ne $host_name)
            {
                $sqlservicename = "MSSQL"+"$"+$instance_name
            }
            else
            {
                $sqlservicename = "MSSQLServer"
            }
            
            $startup_account = (Get-wmiobject win32_service -Filter "name='$sqlservicename' " | Select-Object  startname).StartName

            if ($SqlErrorNumber -in 25602 ){
                Write-LogWarning "As a first step, ensure that service account [$startup_account] for SQL instance '$SQLInstanceUpperCase' has write permissions on the output folder."
            }
        }

        Write-LogWarning ""

        [string]$confirm = $null
        while (-not(($confirm -eq "Y") -or ($confirm -eq "N") -or ($null -eq $confirm)))
        {
            Write-LogWarning "Would you like to continue with limited log collection? (Y/N)"
            $confirm = Read-Host "Continue?>" -CustomLogMessage "SQL Permission Console input:"

            $confirm = $confirm.ToString().ToUpper()
            if (-not(($confirm -eq "Y") -or ($confirm -eq "N") -or ($null -eq $confirm)))
            {
                Write-LogError ""
                Write-LogError "Please chose [Y] to proceed capture with limited log collection."
                Write-LogError "Please chose [N] to abort capture."
                Write-LogError ""
            }
        }

        if ($confirm -eq "Y"){ #user chose to continue
            return $true
        } else { #user chose to abort
            return $false
        }
    }

}
function HandleCtrlC ()
{
    if ($Host.UI.RawUI.KeyAvailable -and (3 -eq [int]$Host.UI.RawUI.ReadKey("AllowCtrlC,IncludeKeyUp,IncludeKeyDown,NoEcho").Character))
    {
       Write-LogWarning "*******************"
       Write-LogWarning "You pressed CTRL-C. Stopping diagnostic collection..."
       Write-LogWarning "*******************"
       Invoke-DiagnosticCleanUpAndExit
       break
    }

    #if no CTRL+C just return and move on
    return
    
}

function HandleCtrlCFinal ()
{
    while ($true)
    {

        if ($Host.UI.RawUI.KeyAvailable -and (3 -eq [int]$Host.UI.RawUI.ReadKey("AllowCtrlC,IncludeKeyUp,IncludeKeyDown,NoEcho").Character))
        {
            Write-LogWarning "<*******************>"
            Write-LogWarning "You pressed CTRL-C. Stopping diagnostic collection..."
            Write-LogWarning "<*******************>"
            Invoke-DiagnosticCleanUpAndExit
        }
		
		else
		{
			Invoke-DiagnosticCleanUpAndExit
			break;
		}
    }
}



function GetPerformanceDataAndLogs 
{
   try 
   {
        Write-LogDebug "inside" $MyInvocation.MyCommand
        
        [bool] $Continue = $false

        #prompt for diagnostic scenario
        $Continue = Select-Scenario
        if ($false -eq $Continue)
        {
            Write-LogInformation "No diagnostic logs will be collected because no scenario is selected. Exiting..."
            return
        }


        #pick a sql instnace
        Select-SQLServerForDiagnostics

        #check SQL permission and continue only if user has permissions or user confirms to continue without permissions
        $Continue = Confirm-SQLPermissions 
        if ($false -eq $Continue)
        {
            Write-LogInformation "No diagnostic logs will be collected due to insufficient SQL permissions. Exiting..."
            return
        }

        #prepare a pefmon counters file with specific instance info
        PrepareCountersFile

        #check if a timer parameter set is passed and sleep until specified time
        StartStopTimeForDiagnostics -timeParam $DiagStartTime -startOrStop "start" 

        #start collecting data
        Start-DiagCollectors
        
        #stop data collection
        Stop-DiagCollectors
        
   }
   catch 
   {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem

        $call_stack = $PSItem.Exception.InnerException 
        Write-LogError "Function '$mycommand' :  $call_stack"
   }
   
}

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
       + $InteractivePromptsHlpStr + "`n" `
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

        [string[]] $localScenArray = @(("Basic","GeneralPerf", "DetailedPerf", "Replication", "AlwaysOn","NetworkTrace","Memory","DumpMemory","WPR", "Setup", "BackupRestore","IO", "LightPerf","MenuChoice", "NoBasic"))
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
        }
        catch 
        {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }
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
    }
    

    #validate DiagStopTime parameter
    if (($DiagStopTime -ne "0000") -and ($false -eq [String]::IsNullOrWhiteSpace($DiagStopTime)))
    {
        [DateTime] $dtStopOut = New-Object DateTime
        if([DateTime]::TryParse($DiagStopTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dtStopOut) -eq $false)
        {
            Write-LogError "Parameter 'DiagStopTime' accepts DateTime values (e.g. `"2021-07-07 17:14:00`"). Current value '$DiagStopTime' is incorrect."
            PrintHelp -ValidArguments "yyyy-MM-dd hh:mm:ss" -index 6
            return $false
        }
    }
    #validate InteractivePrompts parameter

    $prompts = $InteractivePrompts

    if ($true -eq [String]::IsNullOrWhiteSpace($prompts))
    {
        # reset the parameter to default value of Noisy if it was empty space or NULL
        $prompts = "Noisy" 
    }

    $InteractivePromptsParamArr = @("Quiet","Noisy")
    if($prompts -inotin $InteractivePromptsParamArr)
    {
        Write-LogError "Parameter 'InteractivePrompts' can only accept one of these values: $InteractivePromptsParamArr. Current value '$prompts' is incorrect."
        PrintHelp -ValidArguments $InteractivePromptsParamArr -index 7
        return $false
    }

    else 
    {
        return $true
    }
}


function Start-SQLLogScout 
{
    Write-LogDebug "inside " $MyInvocation.MyCommand
    Write-LogDebug "Scenario prameter passed is '$Scenario'" -DebugLogLevel 3

    try 
    {  
        InitAppVersion
    
        #check for administrator rights
        Check-ElevatedAccess
    
        #initialize globals for present folder, output folder, internal\error folder
        InitCriticalDirectories

        #check if output folder is already present and if so prompt for deletion. Then create new if deleted, or reuse
        ReuseOrRecreateOutputFolder
    
        #create a log of events
        Initialize-Log -LogFilePath $global:internal_output_folder -LogFileName "##SQLLOGSCOUT.LOG"
        
        #check file attributes against expected attributes
        $validFileAttributes = Confirm-FileAttributes
        if (-not($validFileAttributes)){
            Write-LogInformation "File attribute validation FAILED. Exiting..."
            return
        }
        
        #invoke the main collectors code
        GetPerformanceDataAndLogs
    
        Write-LogInformation "Ending data collection" #DO NOT CHANGE - Message is backward compatible
    }   
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem

        $call_stack = $PSItem.Exception.InnerException 
        Write-LogError "Function '$mycommand' :  $call_stack"
    }
    finally {
        HandleCtrlCFinal
        Write-LogInformation ""
    }
}
function CopyrightAndWarranty()
{
    Microsoft.PowerShell.Utility\Write-Host "Copyright (c) 2021 Microsoft Corporation. All rights reserved. `n
    THE SOFTWARE IS PROVIDED `"AS IS`", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE. `n`n"
}

function main () 
{
    
    #print copyright message
    CopyrightAndWarranty

    #validate parameters
    $ret = ValidateParameters

    #start program
    if ($ret -eq $true)
    {
        Start-SQLLogScout
    }

}


#to execute from command prompt use: 
#powershell -ExecutionPolicy Bypass -File sqllogscoutps.ps1

main

# SIG # Begin signature block
# MIInwAYJKoZIhvcNAQcCoIInsTCCJ60CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAPECLVSy0QxBPI
# 5pDdq3+o9bDMouhfVOGD8IX1c5dL0aCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGZEwghmNAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGQx
# 2NE8Mq5UdmVfS51UYKglFdfIll840wU1ceFtstuyMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQCY0gAaXKUj2D6Gjbx8Dvk7xSoSnkLLWmyA
# Exi0JlFKIL8MhaGK6ATAnapnUtJw344tw0cRV+gecvnsQZeNyRJFgL0C43TGvJoh
# eacv7+uCoO4NFSiUflUIrEwzwtPbu/X9OJZSCSqpkC2BVBek59YtUTHPt5HCjVLl
# XElHEcRnNL0oXI4EEnfH2QJCPKt9+g3NLZdyJte8stL8IE4detSsyAZ8bW/mkPT6
# RabGVN5Ng1YyliNTMzNa9j4v9A0WsyvaZ6A0whSLy1vJX88AKeXpyMZUD/AUJs96
# 1z4I19l7CH+XZwzRTDl+ObQXE8QfOUgrfSjNcSRZWN4c+GhYqjV8oYIXGTCCFxUG
# CisGAQQBgjcDAwExghcFMIIXAQYJKoZIhvcNAQcCoIIW8jCCFu4CAQMxDzANBglg
# hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIH7NRzKiwunKnOf4qbsjTt4NPKoOK1MT
# D6wPlTq1i1ocAgZiF5Y7rv8YEzIwMjIwMzAxMTI1MDMwLjE3OVowBIACAfSggdik
# gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UE
# CxMdVGhhbGVzIFRTUyBFU046RkM0MS00QkQ0LUQyMjAxJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghFoMIIHFDCCBPygAwIBAgITMwAAAY5Z
# 20YAqBCUzAABAAABjjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDAeFw0yMTEwMjgxOTI3NDVaFw0yMzAxMjYxOTI3NDVaMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOkZDNDEtNEJENC1EMjIwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# qiMCq6OMzLa5wrtcf7Bf9f1WXW9kpqbOBzgPJvaGLrZG7twgwqTRWf1FkjpJKBOG
# 5QPIRy7a6IFVAy0W+tBaFX4In4DbBf2tGubyY9+hRU+hRewPJH5CYOvpPh77FfGM
# 63+OlwRXp5YER6tC0WRKn3mryWpt4CwADuGv0LD2QjnhhgtRVidsiDnn9+aLjMuN
# apUhstGqCr7JcQZt0ZrPUHW/TqTJymeU1eqgNorEbTed6UQyLaTVAmhXNQXDChfa
# 526nW7RQ7L4tXX9Lc0oguiCSkPlu5drNA6NM8z+UXQOAHxVfIQXmi+Y3SV2hr2dc
# xby9nlTzYvf4ZDr5Wpcwt7tTdRIJibXHsXWMKrmOziliGDToLx34a/ctZE4NOLnl
# rKQWN9ZG+Ox5zRarK1EhShahM0uQNhb6BJjp3+c0eNzMFJ2qLZqDp2/3Yl5Q+4k+
# MDHLTipP6VBdxcdVfd4mgrVTx3afO5KNfgMngGGfhSawGraRW28EhrLOspmIxii9
# 2E7vjncJ2tcjhLCjBArVpPh3cZG5g3ZVy5iiAaoDaswpNgnMFAK5Un1reK+MFhPi
# 9iMnvUPwtTDDJt5YED5DAT3mBUxp5QH3t7RhZwAJNLWLtpTeGF7ub81sSKYv2ard
# azAe9XLS10tV2oOPrcniGJzlXW7VPvxqQNxe8lCDA20CAwEAAaOCATYwggEyMB0G
# A1UdDgQWBBTsQfkz9gT44N/5G8vNHayep+aV5DAfBgNVHSMEGDAWgBSfpxVdAF5i
# XYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQA1UK9xzIeTlKhSbLn0
# bekR5gYh6bB1XQpluCqCA15skZ37UilaFJw8+GklDLzlNhSP2mOiOzVyCq8kkpqn
# fUc01ZaBezQxg77qevj2iMyg39YJfeiCIhxYOFugwepYrPO8MlB/oue/VhIiDb1e
# NYTlPSmv3palsgtkrb0oo0F0uWmX4EQVGKRo0UENtZetVIxa0J9DpUdjQWPeEh9c
# EM+RgE265w5WAVb+WNx0iWiF4iTbCmrWaVEOX92dNqBm9bT1U7nGwN5CygpNAgEa
# YnrTMx1N4AjxObACDN5DdvGlu/O0DfMWVc6qk6iKDFC6WpXQSkMlrlXII/Nhp+0+
# noU6tfEpHKLt7fYm9of5i/QomcCwo/ekiOCjYktp393ovoC1O2uLtbLnMVlE5raB
# LBNSbINZ6QLxiA41lXnVVLIzDihUL8MU9CMvG4sdbhk2FX8zvrsP5PeBIw1faenM
# Zuz0V3UXCtU5Okx5fmioWiiLZSCi1ljaxX+BEwQiinCi+vE59bTYI5FbuR8tDuGL
# iVu/JSpVFXrzWMP2Kn11sCLAGEjqJYUmO1tRY29Kd7HcIj2niSB0PQOCjYlnCnyw
# nDinqS1CXvRsisjVlS1Rp4Tmuks+pGxiMGzF58zcb+hoFKyONuL3b+tgxTAz3sF3
# BVX9uk9M5F+OEoeyLyGfLekNAjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
# AAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX
# 9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1q
# UoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8d
# q6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byN
# pOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
# rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
# Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgS
# Uei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8
# QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6Cm
# gyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzF
# ER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQID
# AQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQU
# KqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0
# bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwU
# tj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN
# 3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU
# 5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5
# KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGy
# qVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
# 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
# AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFp
# AUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcd
# FYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRb
# atGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQd
# VTNYs6FwZvKhggLXMIICQAIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RkM0
# MS00QkQ0LUQyMjAxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2WiIwoBATAHBgUrDgMCGgMVAD1iK+pPThHqgpa5xsPmiYruWVuMoIGDMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDl
# yAMVMCIYDzIwMjIwMzAxMTAyNzMzWhgPMjAyMjAzMDIxMDI3MzNaMHcwPQYKKwYB
# BAGEWQoEATEvMC0wCgIFAOXIAxUCAQAwCgIBAAICC7oCAf8wBwIBAAICEl8wCgIF
# AOXJVJUCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQAC
# AwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQCbYCI6N63yeGod6xTv
# 9Fkj0wN6e6SoKF7Nk8li7Ijy7LxNC3TEh6DfgS2+yWvKZEajNnjky3sHnHfQwE6d
# bnhSmIkggmc7lwcJCKoYy/M6EIIO9EyMGF+MVvyqyK1BDOqp++F8TAbMI8Zcom6x
# M+idWzEbaB3Wvet23Rkuz0xOiDGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAABjlnbRgCoEJTMAAEAAAGOMA0GCWCGSAFlAwQC
# AQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkE
# MSIEINhuDzTXp6Aol4zzsyE9HBM0EybN+7xa/OZxmD/M9uvsMIH6BgsqhkiG9w0B
# CRACLzGB6jCB5zCB5DCBvQQgvQWPITvigaUuV5+f/lWs3BXZwJ/l1mf+yelu5nXm
# xCUwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAY5Z
# 20YAqBCUzAABAAABjjAiBCDW9GeoQHgCx/Z7mlZPoNIBwSLaLnPTUgJ6iej0KCpp
# hDANBgkqhkiG9w0BAQsFAASCAgAeITr30HJwPxuX10PrWLqdLR+PgFsTNAuEorVb
# mORzGe4mBqStrBb/2z5WqHqHoxVlyIo26afije9z6t8Jr7XY4P0xACZvMYhQrTXy
# ZwPrn/1QApHZSkG+b4sufSyBJ+rsCBW/EvekXnbWCGM+AJhKer3MP7k4smorX0KF
# mluWhQ+PmCzxtHqpmQkr/E+K78Y5S5pdV0LilBR1ljt3Ua7PieJ22iT4SCrCI51j
# SYQLsuWBcz5WDRWDx4B35P7MG2O7QKTLcqfAP5yUatSPcs48VuBwS265WKymge7W
# 5J79mS2r50ItPotZPkOjn0+IGbzJer6pAGfCd1Og3YL9OcJmh6QSSnoG7/JsnEBm
# 1bO+b2HOtI0HIuLMlnhkRFJ9thPieAE7AhA2rr3aJwjsJBKzOfBGdsAcT+P+PZ6m
# Njp63jcNSotPMaihLN6ESSB67aDSm03pDqGrDOhsi0fAOh22OhT/F5aKqZHiL6mi
# XUijFkWyeJsXKYKnveQQsqyw1IhqG3Vy5Xbs8xmxzGjckJfxxaj9e/1rGEKP2MNk
# OvWg/xnB/yA+xjB+b4mETZbacAharqmbmLVCae/PZW8znOOZuHCiw4RAJgcynY2t
# kyQIRETedOfyPf8JCKEfd1O/QtNCWxIzDvaPWbpz+jdFegmuvndgPNGd3obfvDBk
# iN6pcw==
# SIG # End signature block
