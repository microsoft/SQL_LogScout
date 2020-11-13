## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.

param
(

    [ValidateSet(0,1,2,3,4,5)]
    [Parameter(Position=0,HelpMessage='Choose 0|1|2|3|4|5')]
    [int32] $DebugLevel = 0,

    #scenario is an optional parameter since there is a menu that covers for it if not present
    [ValidateSet("MenuChoice","Basic","GeneralPerf", "DetailedPerf", "Replication", "AlwaysOn","Network","Memory","DumpMemory","WPR", "Setup")]
    [Parameter(Position=1,HelpMessage='Choose MenuChoice|Basic|GeneralPerf|DetailedPerf|Replication|AlwaysOn|Memory|DumpMemory|WPR|Setup')]
    [string] $Scenario = "",

    #servername\instnacename is an optional parameter since there is code that auto-discovers instances
    [Parameter(Position=2)]
    [string] $ServerInstanceConStr = "",

    #scenario is an optional parameter since there is a menu that covers for it if not present
    [ValidateSet("DeleteDefaultFolder","NewCustomFolder")]
    [Parameter(Position=3,HelpMessage='Choose DeleteDefaultFolder|NewCustomFolder')]
    [string] $DeleteExistingOrCreateNew = "",

    #specify start time for diagnostic
    [ValidateScript({ [DateTime]::Parse($_, [cultureinfo]::InvariantCulture)})]
    [Parameter(Position=4,HelpMessage='Format is: "2020-10-27 19:26:00"')]
    [string] $DiagStartTime = "0000",
    
    #specify end time for diagnostic
    [ValidateScript({ [DateTime]::Parse($_, [cultureinfo]::InvariantCulture)})]
    [Parameter(Position=5,HelpMessage='Format is: "2020-10-27 19:26:00"')]
    [string] $DiagStopTime = "0000",

    #specify quiet mode for any Y/N prompts
    [ValidateSet("Quiet","Noisy")]
    [Parameter(Position=6,HelpMessage='Choose Queit|Noisy')]
    [string] $InteractivePrompts = "Noisy"
    
)


#=======================================Globals =====================================
[console]::TreatControlCAsInput = $true
[string]$global:present_directory = ""
[string]$global:output_folder = ""
[string]$global:internal_output_folder = ""
[string]$global:perfmon_active_counter_file = "LogmanConfig.txt"
[bool]$global:perfmon_counters_restored = $false
[string]$global:sql_instance_conn_str = "no_instance_found"
[System.Collections.ArrayList]$global:processes = [System.Collections.ArrayList]::new()
[int]$global:DEBUG_LEVEL = $DebugLevel #zero to disable, 1 to 5 to enable different levels of debug logging
[string] $global:ScenarioChoice = $Scenario
[bool]$global:stop_automatically = $false
[string] $global:xevent_collector = ""
[string] $global:app_version = ""
[string] $global:host_name = hostname
[string] $global:wpr_collector_name = ""
[bool] $global:instance_independent_collection = $false
[int] $global:scenario_bitvalue  = 0

#=======================================Start of \OUTPUT and \ERROR directories and files Section

function Init-AppVersion()
{
    $major_version = "2"
    $minor_version = "2"
    $build = "0"
    $global:app_version = $major_version + "." + $minor_version + "." + $build
    Write-LogInformation "SQL LogScout version: $global:app_version"
}
function InitCriticalDirectories()
{
    #initialize this directories
    Get-PresentDirectory 
    Get-OutputPath
    Get-InternalPath

}


function Get-PresentDirectory()
{
	Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
    $global:present_directory = Convert-Path -Path "."
    
    Write-LogInformation "The Present folder for this collection is" $global:present_directory 
}

function Get-OutputPath([string]$output_dirname = "")
{
	Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
    
    if (($output_dirname -eq "") -or ($output_dirname -eq $null))
    {
        #the output folder is subfolder of current folder where the tool is running
        $global:output_folder =  ($global:present_directory + "\output\")
    }
    else 
    {
        $global:output_folder =  ($global:present_directory + $output_dirname)
    }
    Write-LogInformation "Output path: $global:output_folder" #DO NOT CHANGE - Message is backward compatible
}

function Get-InternalPath()
{
	Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
    
    #the \internal folder is subfolder of \output
    $global:internal_output_folder =  ($global:output_folder  + "internal\")
    Write-LogInformation "The Error files path is" $global:internal_output_folder 
}

function Create-PartialOutputFilename ([string]$server)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    if ($global:output_folder -ne "")
    {
        $server_based_file_name = $server -replace "\\", "_"
        $output_file_name = $global:output_folder + $server_based_file_name + "_" + @(Get-Date -Format FileDateTime)
    }
    Write-LogDebug "The server_based_file_name: " $server_based_file_name -DebugLogLevel 3
    Write-LogDebug "The output_path_filename is: " $output_file_name -DebugLogLevel 2
    
    return $output_file_name
}

function Create-PartialErrorOutputFilename ([string]$server)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

	
	if (($server -eq "") -or ($null -eq $server)) 
	{
		$server = hostname 
	}
	
    $error_folder = $global:internal_output_folder 
    
    $server_based_file_name = $server -replace "\\", "_"
    $error_output_file_name = $error_folder + $server_based_file_name + "_" + @(Get-Date -Format FileDateTime)
    
    Write-LogDebug "The error_output_path_filename is: " $error_output_file_name -DebugLogLevel 2
    
    return $error_output_file_name
}

function Reuse-or-RecreateOutputFolder() {
    Write-LogDebug "inside" $MyInvocation.MyCommand

    Write-LogDebug "Output folder is: $global:output_folder" -DebugLogLevel 3
    Write-LogDebug "Error folder is: $global:internal_output_folder" -DebugLogLevel 3
    
    try {
    
        #delete entire \output folder and files/subfolders before you create a new one, if user chooses that
        if (Test-Path -Path $global:output_folder)  
        {
            if ([string]::IsNullOrWhiteSpace($DeleteExistingOrCreateNew) )
            {
                Write-LogInformation ""
        
                [string]$DeleteOrNew = ""
                Write-LogWarning "It appears that output folder '$global:output_folder' has been used before."
                Write-LogWarning "You can choose to:"
                Write-LogWarning " - Delete (D) the \output folder contents and recreate it"
                Write-LogWarning " - Create a new (N) folder using \Output_ddMMyyhhmmss format." 
                Write-LogWarning "   You can delete the new folder manually in the future"
    
                while (-not(($DeleteOrNew -eq "D") -or ($DeleteOrNew -eq "N"))) 
                {
                    $DeleteOrNew = Read-Host "Delete ('D') or create New ('N') >" -CustomLogMessage "Output folder Console input:"
                    
                    $DeleteOrNew = $DeleteOrNew.ToString().ToUpper()
                    if (-not(($DeleteOrNew -eq "D") -or ($DeleteOrNew -eq "N"))) {
                        Write-LogError ""
                        Write-LogError "Please chose [D] to DELETE the output folder $global:output_folder and all files inside of the folder."
                        Write-LogError "Please chose [N] to CREATE a new folder"
                        Write-LogError ""
                    }
                }

            }

            elseif ($DeleteExistingOrCreateNew -in "DeleteDefaultFolder","NewCustomFolder") 
            {
                Write-LogDebug "The DeleteExistingOrCreateNew parameter is $DeleteExistingOrCreateNew" -DebugLogLevel 2

                switch ($DeleteExistingOrCreateNew) 
                {
                    "DeleteDefaultFolder"   {$DeleteOrNew = "D"}
                    "NewCustomFolder"             {$DeleteOrNew = "N"}
                }
                
            }

        }#end of IF

        
        #Get-Childitem -Path $output_folder -Recurse | Remove-Item -Confirm -Force -Recurse  | Out-Null
        if ($DeleteOrNew -eq "D") {
            Remove-Item -Path $global:output_folder -Force -Recurse  | Out-Null
            Write-LogWarning "Deleted $global:output_folder and its contents"
        }
        elseif ($DeleteOrNew -eq "N") {
        
            [string] $new_output_folder_name = "\output_" + @(Get-Date -Format ddMMyyhhmmss) + "\"
            Write-LogDebug "The new output folder name is: $new_output_folder_name" -DebugLogLevel 3

            #these two calls updates the two globals for the new output and internal folders
            Get-OutputPath -output_dirname $new_output_folder_name
            Write-LogDebug "The new output path is: $global:output_folder" -DebugLogLevel 3
        
            Get-InternalPath
            Write-LogDebug "The new error path is: $global:internal_output_folder" -DebugLogLevel 3
        }

        

	
        #create an output folder AND error directory in one shot (creating the child folder \internal will create the parent \output also). -Force will not overwrite it, it will reuse the folder
        New-Item -Path $global:internal_output_folder -ItemType Directory -Force | out-null 
        
    }
    catch {
        $function_name = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$function_name Function failed with error:  $error_msg"
        return $false
    }
}

function Build-FinalOutputFile([string]$output_file_name, [string]$collector_name, [bool]$needExtraQuotes, [string]$fileExt = ".out")
{
	Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
	
	$final_output_file = $output_file_name +"_" + $collector_name + $fileExt
	
	if ($needExtraQuotes)
	{
		$final_output_file = "`"" + $final_output_file + "`""
	}
	
	return $final_output_file
}

function Build-InputScript([string]$present_directory, [string]$collector_name)
{
	Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
	$input_script = "`"" + $present_directory+"\"+$collector_name +".sql" + "`""
	return $input_script
}

function Build-FinalErrorFile([string]$partial_error_output_file_name, [string]$collector_name, [bool]$needExtraQuotes)
{
	Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
	
	$error_file = $partial_error_output_file_name + "_"+ $collector_name + "_errors.out"
	
	if ($needExtraQuotes)
	{
		$error_file = "`"" + $error_file + "`""
	}
	
	
	return $error_file
}


#=======================================End of \OUTPUT and \ERROR directories and files Section

#======================================== START of Console LOG SECTION
. ./LoggingFacility.ps1
#======================================== END of Console LOG SECTION


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
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The output_file is $output_file" -DebugLogLevel 3

        #collect Windows hotfixes on the system
        $hotfixes = Get-WmiObject -Class "win32_quickfixengineering"

        #in case CTRL+C is pressed
        HandleCtrlC

        [System.Text.StringBuilder]$rs_runningdrives = [System.Text.StringBuilder]::new()

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
        $function_name = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$function_name Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }
}



function GetEventLogs($server) 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    Write-LogInformation "Executing Collector:" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = Create-PartialOutputFilename ($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #gather system and application Event logs in text format
        $servers = "."
        $date = ( get-date ).ToString('yyyyMMdd');
        $appevtfile = New-Item -type file ($partial_output_file_name + "_AppEventLog.txt") -Force;
        $sysevtfile = New-Item -type file ($partial_output_file_name + "_SysEventLog.txt") -Force;
        Get-EventLog -log Application -Computer $servers   -newest 3000  | Format-Table -Property *  -AutoSize | Out-String -Width 20000  | out-file $appevtfile
        
        #in case CTRL+C is pressed
        HandleCtrlC
        
        Get-EventLog -log System -Computer $servers   -newest 3000  | Format-Table -Property *  -AutoSize | Out-String -Width 20000  | out-file $sysevtfile

            
    }
    catch {
        $mycommand = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetPowerPlan($server) 
{
    #power plan
    Write-LogDebug "inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = Create-PartialOutputFilename ($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        $collector_name = "PowerPlan"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $power_plan_name = Get-WmiObject -Class win32_powerplan -Namespace root\cimv2\power | Where-Object IsActive -eq $true | Select-Object ElementName #|Out-File -FilePath $output_file
        Set-Content -Value $power_plan_name.ElementName -Path $output_file
        
    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
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
        
        $partial_output_file_name = Create-PartialOutputFilename ($server)

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

        [System.Text.StringBuilder]$TXToutput = [System.Text.StringBuilder]::new()
        [System.Text.StringBuilder]$CSVoutput = [System.Text.StringBuilder]::new()

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
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret      
    
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
                try{
                    Copy-Item -Path ($BootstrapLogFolder) -Destination $DestinationFolder -Recurse -ErrorAction Stop
                } catch {
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
        Write-LogError "Error Collecting SQL Server Setup Log Files"
        Write-LogError $_
    }

}
    
function MSDiagProcsCollector() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str


    ##create error output filenames using the path + servername + date and time
    $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)

    Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3

    #in case CTRL+C is pressed
    HandleCtrlC

    try {

        #msdiagprocs.sql
        #the output is potential errors so sent to error file
        $collector_name = "MSDiagProcs"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)
    }
    
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
    
}

function GetXeventsGeneralPerf() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3

        #XEvents file: xevent_general.sql - GENERAL Perf
        #there is no output file for this call - it creates the xevents. only errors if any

        #using the global here assumes that only one Xevent collector will be running at a time from SQL LogScout. Running multiple Xevent sessions is not expected and not reasonable
        if (($global:xevent_collector -ne "") -or ($global:xevent_collector.Length -gt 0)) 
        {
            Write-LogError "There is an Xevent collector started by SQL LogScout. It's name is '$global:xevent_collector'. There must be only one active collector"
            Write-LogDebug "Xevent collector name $global:xevent_collector. There must be only one active collector. This is likely a bug or somehow global variable scope is reused -Multiple SQL LogScouts with weird scope?" -DebugLogLevel 1
            return $false
        }

        $collector_name = $global:xevent_collector = "xevent_general"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        Start-Sleep -Seconds 2

        #in case CTRL+C is pressed
        HandleCtrlC

        #add Xevent target
        $collector_name = "xevent_general_target"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $collector_name + ".xel' " + ", max_file_size=(500), max_rollover_files=(50)); END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_add_target + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        #in case CTRL+C is pressed
        HandleCtrlC

        #start the XEvent session
        $collector_name = "xevent_general_Start"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector]  ON SERVER STATE = START; END"
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_start + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)
    }
    catch {
        $mycommand = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
}

function GetXeventsDetailedPerf() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        
    
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3

        #XEvents file: xevent_detailed.sql - Detailed Perf
        #there is no output file for this call - it creates the xevents. only errors if any

        #using the global here assumes that only one Xevent collector will be running at a time from SQL LogScout. Running multiple Xevent sessions is not expected and not reasonable

        if (($global:xevent_collector -ne "") -or ($global:xevent_collector.Length -gt 0)) 
        {
            Write-LogError "There is an Xevent collector started by SQL LogScout. It's name is '$global:xevent_collector'. There must be only one active collector" 
            Write-LogDebug "Xevent collector name $global:xevent_collector. There must be only one active collector. This is likely a bug or somehow global variable scope is reused -Multiple SQL LogScouts with weird scope?" -DebugLogLevel 1
            return $false
        }

        $collector_name = $global:xevent_collector = "xevent_detailed"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        Start-Sleep -Seconds 2

        #in case CTRL+C is pressed
        HandleCtrlC

        #add Xevent target
        $collector_name = "xevent_detailed_target"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $collector_name + ".xel'" + ", max_file_size=(500), max_rollover_files=(50)); END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_add_target + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        #in case CTRL+C is pressed
        HandleCtrlC

        #start the XEvent session
        $collector_name = "xevent_detailed_Start"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector]  ON SERVER STATE = START; END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_start + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
}

function GetAlwaysOnDiag() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #AlwaysOn Basic Info
        $collector_name = "AlwaysOnDiagScript"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }

}

function GetXeventsAlwaysOnMovement() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        
    
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #XEvents file: AlwaysOn_Data_Movement.sql - Detailed Perf

        #using the global here assumes that only one Xevent collector will be running at a time from SQL LogScout. Running multiple Xevent sessions is not expected and not reasonable

        if (($global:xevent_collector -ne "") -or ($global:xevent_collector.Length -gt 0)) 
        {
            Write-LogError "There is an Xevent collector started by SQL LogScout. It's name is '$global:xevent_collector'. There must be only one active collector"     
            Write-LogDebug "Xevent collector name $global:xevent_collector. There must be only one active collector. This is likely a bug or somehow global variable scope is reused -Multiple SQL LogScouts with weird scope?" -DebugLogLevel 1
            return $false
        }
        
        $collector_name = $global:xevent_collector = "AlwaysOn_Data_Movement"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        Start-Sleep -Seconds 2

        #in case CTRL+C is pressed
        HandleCtrlC

        #add Xevent target
        $collector_name = "AlwaysOn_Data_Movement_target"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $collector_name + ".xel'" + ", max_file_size=(500), max_rollover_files=(50)); END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_add_target + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        #in case CTRL+C is pressed
        HandleCtrlC

        #start the XEvent session
        $collector_name = "AlwaysOn_Data_Movement_Start"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector]  ON SERVER STATE = START; END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_start + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
}


function GetSysteminfoSummary() 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #Systeminfo (MSInfo)
        $collector_name = "SystemInfo_Summary"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name $collector_name  
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "systeminfo"
        $argument_list = "/FO LIST"
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -RedirectStandardOutput $output_file -PassThru
        [void]$global:processes.Add($p)
    }
    catch {
        $mycommand = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
}

function GetMisciagInfo() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        
    
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #misc DMVs 
        $collector_name = "MiscPssdiagInfo"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)
    }

    catch 
    {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret    
    }
}

function GetErrorlogs() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    
    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str
  
    try {
        
    
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #errorlogs
        $collector_name = "collecterrorlog"
        $input_script = Build-InputScript $global:present_directory $collector_name 
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -W -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret    
    }

}

function GetTaskList () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {

        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        ##task list
        #tasklist processes
    
        $collector_name = "TaskListVerbose"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "tasklist.exe"
        $argument_list = "/V"
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

        #in case CTRL+C
        HandleCtrlC


        #tasklist services
        $collector_name = "TaskListServices"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "tasklist.exe"
        $argument_list = "/SVC"
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

            
    }
    catch {
        $mycommand = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }
}

function GetRunningProfilerXeventTraces () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #active profiler traces and xevents
        $collector_name = "ExistingProfilerXeventTraces"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $input_script = Build-InputScript $global:present_directory "Profiler Traces"
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i " + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)
        
    }
    catch {
        $mycommand = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }


}

function GetHighCPUPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #SQL Server High CPU Perf Stats
        $collector_name = "HighCPU_perfstats"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #SQL Server Perf Stats
        $collector_name = "SQLServerPerfStats"
        $input_script = Build-InputScript $global:present_directory "SQL Server Perf Stats"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)
    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetPerfStatsSnapshot () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #SQL Server Perf Stats Snapshot
        $collector_name = "SQLServerPerfStatsSnapshotStartup"
        $input_script = Build-InputScript $global:present_directory "SQL Server Perf Stats Snapshot"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetPerfmonCounters () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str
    $internal_folder = $global:internal_output_folder

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        #Perfmon
        $collector_name = "Perfmon"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "cmd.exe"
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon & logman CREATE COUNTER -n logscoutperfmon -cf `"" + $internal_folder + "LogmanConfig.txt`" -f bin -si 00:00:05 -max 250 -cnf 01:00:00  -o " + $output_file + "  & logman start logscoutperfmon "
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetServiceBrokerInfo () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #Service Broker collection
        $collector_name = "SSB_diag"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetTempdbSpaceLatchingStats () 
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {

        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Tempdb space and latching
        $collector_name = "TempDBAnalysis"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetLinkedServerInfo () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3


        #Linked Server configuration
        $collector_name = "linked_server_config"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath  $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetQDSInfo () 
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {

        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Query Store
        $collector_name = "Query Store"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)
    }
    catch {
        $mycommand = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetReplMetadata () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {

        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Replication Metadata
        $collector_name = "Repl_Metadata_Collector"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetChangeDataCaptureInfo () {
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Change Data Capture (CDC)
        $collector_name = "ChangeDataCapture"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetChangeTracking () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Change Tracking
        $collector_name = "Change_Tracking"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetFilterDrivers () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #filter drivers
        $collector_name = "FLTMC_Filters"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " filters"
        $executable = "fltmc.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

        #filters instance
        $collector_name = "FLTMC_Instances"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $executable = "fltmc.exe"
        $argument_list = " instances"
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}


function GetNetworkTrace () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str
    $internal_folder = $global:internal_output_folder

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        #Perfmon
        $collector_name = "NetworkTrace"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"
        $executable = "cmd.exe"
        #$argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon & logman CREATE COUNTER -n logscoutperfmon -cf `"" + $internal_folder + "LogmanConfig.txt`" -f bin -si 00:00:05 -max 250 -cnf 01:00:00  -o " + $output_file + "  & logman start logscoutperfmon "
        #netsh trace stop sessionname='sqllogscout_nettrace'
        $argument_list = "/C netsh trace start sessionname='sqllogscout_nettrace' report=yes persistent=yes capture=yes tracefile=" + $output_file
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetMemoryDumps () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand


    try {
    
        $InstanceSearchStr = ""
        #strip the server name from connection string so it can be used for looking up PID
        $instanceonly = Strip-InstanceName -NetnamePlusInstance $global:sql_instance_conn_str


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
    catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }
} 

function GetWindowsVersion
{
   #Write-LogDebug "Inside" $MyInvocation.MyCommand

   try {
       $winver = [Environment]::OSVersion.Version.Major    
   }
   catch {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret   
   }
   
   
   #Write-Debug "Windows version is: $winver" -DebugLogLevel 3

   return $winver;
}

function GetWPRTrace () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    $wpr_win_version = GetWindowsVersion

    if ($wpr_win_version -lt 8) 
    {
        Write-LogError "Windows Performance Recorder is not available on this version of Windows"
        exit;   
    } 
    else 
    {
        try {

            $partial_output_file_name = Create-PartialOutputFilename ($server)
            $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
            Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

            #choose collector type

            
            [string[]] $WPRArray = "CPU", "Heap and Virtual memory", "Disk and File I/O", "Filter drivers"
            $WPRIntRange = 0..($ScenarioArray.Length - 1)  

            Write-LogInformation "Please select one of the following Data Collection Type:`n"
            Write-LogInformation ""
            Write-LogInformation "ID   WRP Profile"
            Write-LogInformation "--   ---------------"

            for ($i = 0; $i -lt $WPRArray.Count; $i++) {
                Write-LogInformation $i "  " $WPRArray[$i]
            }
            $isInt = $false
            $wprIdStrIdInt = 777
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

            Write-LogInformation "WPR Profile Console input: $wprIdStr"
            
            try {
                $wprIdStrIdInt = [convert]::ToInt32($wprIdStr)
                $isInt = $true
            }

            catch [FormatException] {
                Write-LogError "The value entered for ID '", $ScenIdStr, "' is not an integer"
                continue 
            }
            
            If ($isInt -eq $true) {
                #Perfmon
                
                switch ($wprIdStr) {
                    "0" { 
                        $collector_name = $global:wpr_collector_name= "WPR_CPU"
                        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start CPU -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
                        [void]$global:processes.Add($p)
                        Start-Sleep -s 15
                    }
                    "1" { 
                        $collector_name = $global:wpr_collector_name = "WPR_HeapAndVirtualMemory"
                        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start Heap -start VirtualAllocation  -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
                        [void]$global:processes.Add($p)
                        Start-Sleep -s 15
                    }
                    "2" { 
                        $collector_name = $global:wpr_collector_name = "WPR_DiskIO_FileIO"
                        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start DiskIO -start FileIO -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
                        [void]$global:processes.Add($p)
                        Start-Sleep -s 15
                    }
                    "3" { 
                        $collector_name = $global:wpr_collector_name = "WPR_MiniFilters"
                        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start Minifilter -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
                        [void]$global:processes.Add($p)
                        Start-Sleep -s 15
                    }                    
                }
            }
        }
        catch {
            
            $mycommand = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "Function $mycommand failed with error:  $error_msg"
            $ret = $false
            return $ret   
        }
    }

}

function GetMemoryLogs()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Change Tracking
        $collector_name = "SQL_Server_Mem_Stats"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

        
    }
    catch {
        $function_name = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$function_name Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }


}

function GetClusterLogs()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str
    $output_folder = $global:output_folder
    $ClusterError = 0
    $collector_name = "GetClusterInfo"
    $partial_output_file_name = Create-PartialOutputFilename ($server)
    
    Write-LogInformation "Executing Collector: $collector_name"

    $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false -fileExt ".out"
    [System.Text.StringBuilder]$rs_ClusterLog = [System.Text.StringBuilder]::new()

    try 
    {
            Import-Module FailoverClusters
            [void]$rs_ClusterLog.Append("-- Windows Cluster Name --`r`n")
            $clusterName = Get-cluster
            [void]$rs_ClusterLog.Append("$clusterName`r`n") 
            
            # dumping windows cluster log
            Write-LogWarning "Collecting Windows cluster log for all nodes, this process may takes some time....." 
            Get-ClusterLog -Destination $output_folder  -UseLocalTime | Out-Null
    }
    catch 
    {
        $ClusterError = 1
        $function_name = $MyInvocation.MyCommand 
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$function_name - Cluster is not found...:  $error_msg"
    }
    
    if ($ClusterError -eq 0)
    {
        try 
        {
                $ReportPath = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name "ClusterRegistryHive" -needExtraQuotes $false -fileExt ".out"
                Get-ChildItem 'HKLM:HKEY_LOCAL_MACHINE\Cluster' -Recurse | Out-File -FilePath $ReportPath
                #reg save "HKEY_LOCAL_MACHINE\Cluster" $ReportPath
            
        }
        catch
        {
                $function_name = $MyInvocation.MyCommand 
                $error_msg = $PSItem.Exception.Message 
                Write-LogError "$function_name - Error while accessing cluster registry keys...:  $error_msg"
        }

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

function GetSQLErrorLogs(){
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "SQLErrorLogs"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
            $installedInstances = $global:sql_instance_conn_str
            if ($installedInstances -notlike '*\*')
            {
                $vInstance = "MSSQLSERVER"
            } 
            if ($installedInstances -like '*\*')
            {
                $selectInstanceName = $global:sql_instance_conn_str              
                $installedInstances = Strip-InstanceName($selectInstanceName) 
                $vInstance = $installedInstances
            }
            [string]$DestinationFolder = $global:output_folder 

            #in case CTRL+C is pressed
            HandleCtrlC

            $vRegInst = (Get-ItemProperty -Path HKLM:"SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$vInstance
            $vRegPath = "SOFTWARE\Microsoft\Microsoft SQL Server\" + $vRegInst + "\MSSQLServer\Parameters" 
            $vLogPath = (Get-ItemProperty -Path HKLM:$vRegPath).SQLArg1 -replace '-e'
            $vLogPath = $vLogPath -replace 'ERRORLOG'
            Get-ChildItem $vLogPath -Filter ERRORLOG* | Copy-Item -Destination $DestinationFolder | Out-Null 
            Get-ChildItem $vLogPath -Filter SQLAGENT* | Copy-Item -Destination $DestinationFolder | Out-Null 

        } catch {
            Write-LogError "Error Collecting SQL Server Error Log Files"
            Write-LogError $_
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


function Invoke-CommonCollectors()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:basicBit

    GetRunningDrivers
    GetSysteminfoSummary
    
    HandleCtrlC
    Start-Sleep -Seconds 1

    if ($global:sql_instance_conn_str -eq "no_instance_found")
    {
        Write-LogInformation "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        GetMisciagInfo
        HandleCtrlC
    }
    

    HandleCtrlC
    Start-Sleep -Seconds 2
    GetTaskList 
    GetSQLErrorLogs

    HandleCtrlC
    Start-Sleep -Seconds 2
    GetPowerPlan
    GetWindowsHotfixes
    GetFilterDrivers
    
    HandleCtrlC
    Start-Sleep -Seconds 2
    GetEventLogs

    if (IsClustered)
    {
        GetClusterLogs
    } 
    
} 

function Invoke-GeneralPerfScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:generalperfBit
    
    Invoke-CommonCollectors
    GetPerfmonCounters
    
    if ($global:sql_instance_conn_str -eq "no_instance_found")
    {
        Write-LogInformation "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
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

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:detailedperfBit

    Invoke-CommonCollectors
    GetPerfmonCounters
    
    if ($global:sql_instance_conn_str -eq "no_instance_found")
    {
        Write-LogInformation "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
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

function Invoke-AlwaysOnScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:alwaysonBit

    Invoke-CommonCollectors

    if ($global:sql_instance_conn_str -eq "no_instance_found")
    {
        Write-LogInformation "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        GetAlwaysOnDiag
        GetXeventsAlwaysOnMovement
        GetPerfmonCounters
    }
}

function Invoke-ReplicationScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:replBit

    Invoke-CommonCollectors
    
    if ($global:sql_instance_conn_str -eq "no_instance_found")
    {
        Write-LogInformation "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
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

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:dumpMemoryBit

    #invoke memory dump facility
    GetMemoryDumps

}


function Invoke-NetworkScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:networktraceBit

    GetNetworkTrace 

}





function Invoke-WPRScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:wprBit


    Write-LogWarning "Windows Performance Recorder (WPR) is a resource-intensive data collection process! Use only under Microsoft guidance."
    
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
        Write-LogInformation "You aborted the WRP data collection process"
        exit
    }
        
    #invoke the functionality
    GetWPRTrace 
}

function Invoke-MemoryScenario 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:memoryBit

    Invoke-CommonCollectors

    if ($global:sql_instance_conn_str -eq "no_instance_found")
    {
        Write-LogInformation "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
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
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #turn the bit on for this scenario
    EnableScenario -scenarioBit $global:setupBit

    Invoke-CommonCollectors
    HandleCtrlC
    GetSQLSetupLogs
}

function StartStopTimeForDiagnostics ([string] $timeParam, [string] $startOrStop="")
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try
    {
        if ($timeParam -eq "0000")
        {
            Write-LogDebug "No start/end time specified for diagnostics" -DebugLogLevel 2
            return
        }
        
        $datetime = $timeParam #format "2020-10-27 19:26:00"
        
        $formatted_date_time = [DateTime]::Parse($datetime, [cultureinfo]::InvariantCulture);
        
        Write-LogDebug "The formatted time is: $formatted_date_time" -DebugLogLevel 3
    
        #wait until time is reached
        if ($formatted_date_time -gt (Get-Date))
        {
            Write-LogWarning "Waiting until the specified $startOrStop time '$timeParam' is reached...(CTRL+C to stop)"
        }
        else
        {
            Write-LogInformation "The specified $startOrStop time '$timeParam' is in the past. Continuing execution."     
        }
        

        [int] $increment = 0
        [int] $sleepInterval = 5

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
                $delta = (New-TimeSpan -Start $startDate -End $endDate).TotalMinutes
                Write-LogWarning "$delta minutes remain"
            }
        }


    }
    catch 
    {
        $function_name = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-Host "'$function_name' function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function Select-Scenario()
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    #check if a timer parameter set is passed and sleep until specified time
    StartStopTimeForDiagnostics -timeParam $DiagStartTime -startOrStop "start"

    Write-LogInformation ""
    Write-LogInformation "Initiating diagnostics collection... " -ForegroundColor Green

    [string[]]$ScenarioArray = "Basic (no performance data)","General Performance (recommended for most cases)","Detailed Performance (statement level and query plans)","Replication","AlwaysON", "Network Trace","Memory", "Generate Memory dumps","Windows Performance Recorder (WPR)", "Setup"
    $scenarioIntRange = 0..($ScenarioArray.Length -1)  #dynamically count the values in array and create a range

    if (($global:ScenarioChoice -eq "MenuChoice") -or ($global:ScenarioChoice -eq ""))
    {
        Write-LogInformation "Please select one of the following scenarios:`n"
        Write-LogInformation ""
        Write-LogInformation "ID   Scenario"
        Write-LogInformation "--   ---------------"

        for($i=0; $i -lt $ScenarioArray.Count;$i++)
        {
            Write-LogInformation $i "  " $ScenarioArray[$i]
        }

        $isInt = $false
        $ScenarioIdInt = 777
        



        
        while(($isInt -eq $false) -or ($ValidId -eq $false))
        {
            Write-LogInformation ""
            Write-LogWarning "Enter the Scenario ID for which you want to collect diagnostic data. Then press Enter" 

            $ScenIdStr = Read-Host "Enter the Scenario ID from list above>" -CustomLogMessage "Scenario Console input:"
            
            try{
                    $ScenarioIdInt = [convert]::ToInt32($ScenIdStr)
                    $isInt = $true
                }

            catch [FormatException]
                {
                     Write-LogError "The value entered for ID '",$ScenIdStr,"' is not an integer"
                     continue 
                }

            #validate this ID is in the list discovered 
            if($ScenarioIdInt -in ($scenarioIntRange))
            {
                $ValidId = $true

                switch ($ScenarioIdInt) 
                {
                    0 { $global:ScenarioChoice = "Basic"}
                    1 { $global:ScenarioChoice = "GeneralPerf"}
                    2 { $global:ScenarioChoice = "DetailedPerf"}
                    3 { $global:ScenarioChoice = "Replication"}
                    4 { $global:ScenarioChoice = "AlwaysOn"}
                    5 { $global:ScenarioChoice = "Network"}
                    6 { $global:ScenarioChoice = "Memory"}
                    7 { $global:ScenarioChoice = "DumpMemory"}
                    8 { $global:ScenarioChoice = "WPR"}
                    9 { $global:ScenarioChoice = "Setup"}
                    Default { Write-LogError "No valid scenario was picked. Not sure why we are here"}
                }
                
            }
            else
            {
                $ValidId = $false
                Write-LogError "The ID entered '",$ScenIdStr,"' is not in the list "
            }
        } #end of while

    } #end of if for using a Scenario menu

    #set additional properties to certain scenarios
    switch ($global:ScenarioChoice) 
    {
        "Basic" { 
            Set-AutomaticStop -collector_name $global:ScenarioChoice
        }
        "Replication" { 
            Set-AutomaticStop -collector_name $global:ScenarioChoice
        }
        "Network" { 
            Set-InstanceIndependentCollection -collector_name $global:ScenarioChoice
        }
        "DumpMemory" { 
            Set-AutomaticStop -collector_name $global:ScenarioChoice
        }
        "WPR" { 
            Set-AutomaticStop -collector_name $global:ScenarioChoice
            Set-InstanceIndependentCollection -collector_name $global:ScenarioChoice
        }
        "Setup" { 
            Set-AutomaticStop -collector_name $global:ScenarioChoice
        }
    }
        

}

function Set-AutomaticStop ([string] $collector_name) 
{
    # this function is invoked when the user does not need to wait for any long-term collectors (like Xevents, Perfmon, Netmon). 
    # Just gather everything and shut down

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    Write-LogInformation "The selected '$collector_name' collector will stop automatically after it gathers logs" -ForegroundColor Green
    $global:stop_automatically = $true
}

function Set-InstanceIndependentCollection ([string] $collector_name) 
{
    # this function is invoked when the data collected does not target a specific SQL instance (e.g. WPR, Netmon, Setup). 

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    Write-LogInformation "The selected '$collector_name' scenario gathers logs independent of a SQL instance"
    $global:instance_independent_collection = $true    
}

function Start-DiagCollectors ()
{


    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    
            
    #launch the scenario collectors

    switch ($global:ScenarioChoice) 
    {
        "GeneralPerf" 
        {
            Invoke-GeneralPerfScenario
        }
        "DetailedPerf"
        {
            Invoke-DetailedPerfScenario
        }
        "Basic"
        {
            Invoke-CommonCollectors 
        }
        "AlwaysOn"
        {
            Invoke-AlwaysOnScenario
        }
        "Replication"
        {
            Invoke-ReplicationScenario
        }
        "Network"
        {
            Invoke-NetworkScenario
        }
        "Memory"
        {
            Invoke-MemoryScenario
        }
        "DumpMemory"
        {
            Invoke-DumpMemoryScenario
        }
        "WPR"
        {
            Invoke-WPRScenario
        }
        "Setup"
        {
            Invoke-SetupScenario
        }

        Default 
        {
            Write-LogInformation "No scenario was invoked"
        }
    }
    
    Write-LogInformation "Diagnostic collection started." -ForegroundColor Green #DO NOT CHANGE - Message is backward compatible
    Write-LogInformation ""

}

function Stop-DiagCollectors() 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    $ValidStop = $false

    #for Basic scenario we don't need to wait as there are only static logs
    if (($DiagStopTime -ne "0000") -and ($Scenario -ne "Basic"))
    {
        #likely a timer parameter is set to stop at a specified time
        StartStopTimeForDiagnostics -timeParam $DiagStopTime -startOrStop "stop"

        #bypass the manual "STOP" interactive user command and cause system to stop
        $global:stop_automatically = $true
    }
    try
    {

        if ($false -eq $global:stop_automatically)
        { #wait for user to type "STOP"
            while ($ValidStop -eq $false) 
            {
                Write-LogWarning "Please type 'STOP' to terminate the diagnostics collection when you finished capturing the issue"
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
            Write-LogDebug "Shutting down automatically. No user interaction to stop collectors" -DebugLogLevel 2
            Write-LogInformation "Shutting down the collectors" -ForegroundColor Green #DO NOT CHANGE - Message is backward compatible
        }        
        #create an output directory. -Force will not overwrite it, it will reuse the folder
        #$global:present_directory = Convert-Path -Path "."

        $partial_output_file_name = Create-PartialOutputFilename -server $server
        $partial_error_output_file_name = Create-PartialErrorOutputFilename -server $server

        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit -scenarioName "GeneralPerf")) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit -scenarioName "DetailedPerf")) `
        )
        {
            #SQL Server Perf Stats Snapshot
            $collector_name = "SQLServerPerfStatsSnapshotShutdown"
            $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
            $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
            $input_script = Build-InputScript $global:present_directory "SQL Server Perf Stats Snapshot"
            $argument_list = "-S" + $server + " -E -Hsqllogscout_stop -w4000 -o" + $output_file + " -i" + $input_script
            Write-LogDebug $argument_list
            Write-LogInformation "Executing shutdown command: $collector_name"
            $p = Start-Process -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden -PassThru
            [void]$global:processes.Add($p)
        }

        #STOP the XEvent session
        if (($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit -scenarioName "GeneralPerf")) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit -scenarioName "DetailedPerf")) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit -scenarioName "AlwaysOn")) `
            -and ("" -ne $global:xevent_collector)
            ) 
        { 
            #avoid errors if there was not Xevent collector started
            $collector_name = "xevents_stop"
            $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true  
            $alter_event_session_stop = "ALTER EVENT SESSION [$global:xevent_collector] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_collector] ON SERVER;" 
            $argument_list = "-S" + $server + " -E -Hsqllogscout_stop -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_stop + "`""
            Write-LogInformation "Executing shutdown command: $collector_name"
            Write-LogDebug $alter_event_session_stop
            Write-LogDebug $argument_list
            $p = Start-Process -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden -PassThru
            [void]$global:processes.Add($p)
        }

        #STOP Perfmon
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit -scenarioName "GeneralPerf")) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit -scenarioName "DetailedPerf")) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:memoryBit -scenarioName "Memory")) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit -scenarioName "AlwaysOn")) `
            )
        {

            $collector_name = "PerfmonStop"
            $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
            $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon"
            Write-LogInformation "Executing shutdown command: $collector_name"
            Write-LogDebug $argument_list
            $p = Start-Process -FilePath "cmd.exe" -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden -PassThru
            [void]$global:processes.Add($p)
        }


        
        # #sp_diag_trace_flag_restore
        # $collector_name = "RestoreTraceFlagOrigValues"
        # $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        # $query = "EXEC tempdb.dbo.sp_diag_trace_flag_restore  'SQLDIAG'"  
        # $argument_list ="-S" + $server +  " -E -Hsqllogscout_stop -w4000 -o"+$error_file + " -Q`""+ $query + "`" "
        # Write-LogInformation "Stopping Collector: $collector_name"
        # Write-LogDebug $argument_list
        # $p = Start-Process -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        # [void]$global:processes.Add($p)

        #wait for other work to finish
        Start-Sleep -Seconds 3

        #send the output file to \internal
        $collector_name = "KillActiveLogscoutSessions"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
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
        $argument_list = "-S" + $server + " -E -Hsqllogscout_stop -w4000 -o" + $error_file + " -Q`"" + $query + "`" "
        Write-LogInformation "Executing shutdown command: $collector_name"
        Write-LogDebug $argument_list
        $p = Start-Process -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        Start-Sleep -Seconds 1

        #STOP Network trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit -scenarioName "NetworkTrace"))
        {

            $collector_name = "NettraceStop"
            $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
            $argument_list = "/C title 'stopping network trace...' & netsh trace stop sessionname='sqllogscout_nettrace'"
            Write-LogInformation "Executing shutdown command: $collector_name. Waiting - this may take a few of minutes..."
            Write-LogDebug $argument_list
            $p = Start-Process -FilePath "cmd.exe" -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Normal -PassThru
            [void]$global:processes.Add($p)

            [int]$cntr = 0

            while ($false -eq $p.HasExited) 
            {
                [void] $p.WaitForExit(20000)
                if ($cntr -gt 0) {
                    Write-LogWarning "Continuing to wait for network trace to stop..."
                }
                $cntr++
            } 

        }

        
        #stop WPR trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit -scenarioName "WPR"))
        {
            $collector_name = $global:wpr_collector_name
            $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
            $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"
            $executable = "cmd.exe"
            $argument_list = $argument_list = "/C wpr.exe -stop " + $output_file
            Write-LogInformation "Executing shutdown command: $collector_name"
            Write-LogDebug $argument_list
            $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
            [void]$global:processes.Add($p)

            $cntr = 0 #reset the counter
            while ($false -eq $p.HasExited) 
            {
                [void] $p.WaitForExit(5000)
            
                if ($cntr -gt 0) {
                    Write-LogWarning "Continuing to wait for WPR trace to stop..."
                }
                $cntr++
            } 
        }

        Write-LogInformation "Waiting 3 seconds to ensure files are written to and closed by any program including anti-virus..." -ForegroundColor Green
        Start-Sleep -Seconds 3


    }
    catch {
        $function_name = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$function_name Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function Invoke-DiagnosticCleanUp()
{

  Write-LogDebug "inside" $MyInvocation.MyCommand

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
  if ($server -ne "no_instance_found")
  {
      $executable = "sqlcmd.exe"
      $argument_list ="-S" + $server +  " -E -Hsqllogscout_cleanup -w4000 -Q`""+ $query + "`" "
      Write-LogDebug $executable $argument_list
      $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
      [void]$global:processes.Add($p)
  }
  
  
  #STOP Perfmon
  $executable = "cmd.exe"
  $argument_list ="/C logman stop logscoutperfmon & logman delete logscoutperfmon"
  Write-LogDebug $executable $argument_list
  $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
  [void]$global:processes.Add($p)
  
  if ($server -ne "no_instance_found")
  {  
    $alter_event_session_stop = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_collector] ON SERVER; END" 
    $executable = "sqlcmd.exe"
    $argument_list = "-S" + $server + " -E -Hsqllogscout_cleanup -w4000 -Q`"" + $alter_event_session_stop + "`""
    Write-LogDebug $executable $argument_list
    $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
    [void]$global:processes.Add($p)
  }

  #STOP network trace
  if ($true -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit -scenarioName "NetworkTrace"))
  {
    $executable = "cmd.exe"
    $argument_list ="/C title 'cleanup network trace...' & echo 'This process may take a few minutes...' & netsh trace stop sessionname='sqllogscout_nettrace'"
    Write-LogDebug $executable $argument_list
    $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru -Wait
    [void]$global:processes.Add($p)
  }

  #stop the WPR process if running any
  if ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit -scenarioName "WPR"))
  {
    $executable = "cmd.exe"
    $argument_list = $argument_list = "/C wpr.exe -cancel " 
    Write-LogDebug $executable $argument_list
    $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
    [void]$global:processes.Add($p)

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

  }

  
    Write-LogDebug "Checking that all processes terminated..."

    #allowing some time for above processes to clean-up
    Start-Sleep 3

    foreach ($p in $global:processes) {
        if ($p.HasExited -eq $false) {

            $wmiqry = "select * from Win32_Process where ProcessId = " + ([string]$p.Id)
            $OSCommandLine = (Get-WmiObject -Query $wmiqry).CommandLine

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
  
  exit
}



#======================================== END OF Diagnostics Collection SECTION

#======================================== START OF Bitmask Enabling, Diabling and Checking of Scenarios

# 00000000001 (1)   = Basic
# 00000000010 (2)   = GeneralPerf
# 00000000100 (4)   = DetailedPerf
# 00000001000 (8)   = Replication
# 00000010000 (16)  = alwayson
# 00000100000 (32)  = networktrace
# 00001000000 (64)  = memory
# 00010000000 (128) = DumpMemory
# 00100000000 (256) = WPR
# 01000000000 (512) = Setup
# 10000000000 (1024)= XXX

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
[int] $global:futureScBit      = 1024


function EnableScenario([int]$scenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    Write-LogDebug "Enabling scenario bit $scenarioBit" -DebugLogLevel 3

    $global:scenario_bitvalue = $global:scenario_bitvalue -bor $scenarioBit
}

function DisableScenario([int]$scenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    Write-LogDebug "Disabling scenario bit $scenarioBit" -DebugLogLevel 3
    
    $global:scenario_bitvalue = $global:scenario_bitvalue -bxor $scenarioBit
}


function IsScenarioEnabled([int]$scenarioBit, [string]$scenarioName="No Scenario")
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand "($scenarioName)"

    $bm_enabled = $global:scenario_bitvalue -band $scenarioBit

    Write-LogDebug "The bitmask result for $scenarioName scenario = $bm_enabled" -DebugLogLevel 4

    if (($global:scenario_bitvalue -band $scenarioBit) -gt 0)
    {
        Write-LogDebug "$scenarioName scenario is enabled" -DebugLogLevel 2
        return $true
    }
    else
    {
        Write-LogDebug "$scenarioName scenario is disabled" -DebugLogLevel 2
        return $false
    }

}


#======================================== END OF Bitmask Enabling, Diabling and Checking of Scenarios


#======================================== START OF NETNAME + INSTANCE SECTION

function Get-ClusterVNN ($instance_name)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    $vnn = ""

    if (($instance_name -ne "") -and ($null -ne $instance_name))
    {
        $sql_fci_object = Get-ClusterResource | Where-Object {($_.ResourceType -eq "SQL Server")} | get-clusterparameter | Where-Object {($_.Name -eq "InstanceName") -and ($_.Value -eq $instance_name)}
        $vnn_obj = Get-ClusterResource  | Where-Object {($_.ResourceType -eq "SQL Server") -and ($_.Name -eq $sql_fci_object.ClusterObject.OwnerGroup.Name)} | get-clusterparameter -Name VirtualServerName | Select-Object Value
        $vnn = $vnn_obj.Value
    }
    else
    {
        Write-LogError "Instance name is empty and it shouldn't be at this point"            
    }
    
    Write-LogDebug "The VNN Matched to Instance = '$instance_name' is  '$vnn' " -DebugLogLevel 2

    return $vnn
}

function Build-ClusterVnnPlusInstance([string]$instance)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
	
        
    [string]$VirtNetworkNamePlusInstance = ""

    if (($instance -eq "") -or ($null -eq $instance)) 
    {
        Write-LogError "Instance name is empty and it shouldn't be at this point"
    }
    else
    {
        #take the array instance-only names and look it up against the cluster resources and get the VNN that matches that instance. Then populate the NetName array

                $vnn = Get-ClusterVNN ($instance)

                Write-LogDebug  "VirtualName+Instance:   " ($vnn + "\" + $instance) -DebugLogLevel 2

                $VirtNetworkNamePlusInstance = ($vnn + "\" + $instance)

                Write-LogDebug "Combined NetName+Instance: '$VirtNetworkNamePlusInstance'" -DebugLogLevel 2
    }

    return $VirtNetworkNamePlusInstance    
}

function Build-HostnamePlusInstance([string]$instance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
		
    [string]$NetworkNamePlustInstance = ""
    
    if (($instance -eq "") -or ($null -eq $instance)) 
    {
        Write-LogError "Instance name is empty and it shouldn't be at this point"
    }
    else
    {
        #take the array instance-only names and look it up against the cluster resources and get the VNN that matches that instance. Then populate the NetName array
        $host_name = hostname

        Write-LogDebug "HostNames+Instance :   " ($host_name + "\" + $instance) -DebugLogLevel 2

        if ($instance -eq "MSSQLSERVER")
        {
            $NetworkNamePlustInstance = $host_name
        }
        else
        {
            $NetworkNamePlustInstance = ($host_name + "\" + $instance)
        }

        Write-LogDebug "Combined HostName+Instance: " $NetworkNamePlustInstance -DebugLogLevel 2
    }

    return $NetworkNamePlustInstance
}


#check if cluster - based on cluster service status and cluster registry key
function IsClustered()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $ret = $false
    $error_msg = ""
        
    $clusServiceisRunning = $false
    $clusRegKeyExists = $false
    $ClusterServiceKey="HKLM:\Cluster"

    # Check if cluster service is running
    try 
    { 
        if ((Get-Service |  Where-Object  {$_.Displayname -match "Cluster Service"}).Status -eq "Running") 
        {
            $clusServiceisRunning =  $true
            Write-LogDebug "Cluster services status is running: $clusServiceisRunning  " -DebugLogLevel 2   
        }
        
        if (Test-Path $ClusterServiceKey) 
        { 
            $clusRegKeyExists  = $true
            Write-LogDebug "Cluster key $ClusterServiceKey Exists: $clusRegKeyExists  " -DebugLogLevel 2
        }

        if (($clusRegKeyExists -eq $true) -and ($clusServiceisRunning -eq $true ))
        {
            Write-LogDebug 'This is a Windows Cluster for sure!' -DebugLogLevel 2
            return $true
        }
        else 
        {
            Write-LogDebug 'This is Not a Windows Cluster!' -DebugLogLevel 2
            $ret = $false
            return $ret
        }
    }
    catch 
    {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Function $mycommand failed with error:  $error_msg"
        $ret = $false
        return $ret              
    }

    return $ret
}

function IsFailoverClusteredInstance([string]$instanceName)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    if (Get-ClusterResource  | Where-Object {($_.ResourceType -eq "SQL Server")} | get-clusterparameter | Where-Object {($_.Name -eq "InstanceName") -and ($_.Value -eq $instanceName)} )
    {
        Write-LogDebug "The instance '$instanceName' is a SQL FCI " -DebugLogLevel 2
        return $true
    }
    else 
    {
        Write-LogDebug "The instance '$instanceName' is NOT a SQL FCI " -DebugLogLevel 2
        return $false    
    }
}

function Get-InstanceNamesOnly()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [string[]]$instnaceArray = @()
    $selectedSqlInstance = ""


    #find the actively running SQL Server services
    $SqlTaskList = Tasklist /SVC /FI "imagename eq sqlservr*" /FO CSV | ConvertFrom-Csv

    
    if ($SqlTaskList.Count -eq 0)
    {

        Write-LogInformation "There are curerntly no running instances of SQL Server. Would you like to proceed with OS-only log collection" -ForegroundColor Green
        
        if ($InteractivePrompts -eq "Noisy")
        {
            $ValidInput = "Y","N"
            $ynStr = Read-Host "Proceed with logs collection (Y/N)?>" -CustomLogMessage "no_sql_instance_logs input: "
            $HelpMessage = "Please enter a valid input ($ValidInput)"

            #$AllInput = $ValidInput,$WPR_YesNo,$HelpMessage 
            $AllInput = @()
            $AllInput += , $ValidInput
            $AllInput += , $ynStr
            $AllInput += , $HelpMessage
        
            [string] $confirm = validateUserInput($AllInput)
        }
        elseif ($InteractivePrompts -eq "Quiet") 
        {
            $confirm = "Y"
        }

        Write-LogDebug "The choice made is '$confirm'"

        if ($confirm -eq "Y")
        {
            $instnaceArray+=$global:sql_instance_conn_str
        }
        elseif ($confirm -eq "N")
        {
            Write-LogInformation "Aborting collection..."
            exit
        }
        
    }

    else 
    {
        Write-LogDebug "The running instances are: " $SqlTaskList -DebugLogLevel 3
        Write-LogDebug "" -DebugLogLevel 3
        $SqlTaskList | Select-Object  PID, "Image name", Services | ForEach-Object {Write-LogDebug $_ -DebugLogLevel 3}
        Write-LogDebug ""
    
        foreach ($sqlinstance in $SqlTaskList.Services)
        {
            #in the case of a default instance, just use MSSQLSERVER which is the instance name

            if ($sqlinstance.IndexOf("$") -lt 1)
            {
                $selectedSqlInstance  = $sqlinstance
            }

            #for named instance, strip the part after the "$"
            else
            {
                $selectedSqlInstance  = $sqlinstance.Substring($sqlinstance.IndexOf("$") + 1)
            }

            
            #add each instance name to the array
            $instnaceArray+=$selectedSqlInstance 
        }

    }


    return $instnaceArray
}

function Get-NetNameMatchingInstance()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [string[]]$NetworkNamePlustInstanceArray = @()
    $isClustered = $false
	[string[]]$instanceArrayLocal = @()


    #get the list of instance names
    $instanceArrayLocal = Get-InstanceNamesOnly

    #special cases - if no SQL instance on the machine, just hard-code a value
    if ($global:sql_instance_conn_str -eq $instanceArrayLocal.Get(0) )
    {
        $NetworkNamePlustInstanceArray+=$instanceArrayLocal.Get(0)
        Write-LogDebug "No running SQL Server instances on the box so hard coding a value and collecting OS-data" -DebugLogLevel 1
    }
    elseif ($instanceArrayLocal -and ($null -ne $instanceArrayLocal))
    {
        Write-LogDebug "InstanceArrayLocal contains:" $instanceArrayLocal -DebugLogLevel 2

        #build NetName + Instance 

        $isClustered = IsClustered #($instanceArrayLocal)

        #if this is on a clustered system, then need to check for FCI or AG resources
        if ($isClustered -eq $true)
        {
        
            #loop through each instance name and check if FCI or not. If FCI, use ClusterVnnPlusInstance, else use HostnamePlusInstance
            #append each name to the output array $NetworkNamePlustInstanceArray
            for($i=0; $i -lt $instanceArrayLocal.Count; $i++)
            {
                if (IsFailoverClusteredInstance($instanceArrayLocal[$i]))
                    {
                        $NetworkNamePlustInstanceArray += Build-ClusterVnnPlusInstance ($instanceArrayLocal[$i])  
                    }
                else
                {
                    $NetworkNamePlustInstanceArray += Build-HostnamePlusInstance($instanceArrayLocal[$i])
                }

            }
        }
        #all local resources so just build array with local instances
        else
        {
            for($i=0; $i -lt $instanceArrayLocal.Count; $i++)
            {
                    $NetworkNamePlustInstanceArray += Build-HostnamePlusInstance($instanceArrayLocal[$i])
            }

        }




    }

    else
    {
        Write-LogError "InstanceArrayLocal array is blank or null - no instances populated for some reason"
    }

    

    return $NetworkNamePlustInstanceArray

}


#Display them to user and let him pick one
function Pick-SQLServer-for-Diagnostics()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    $SqlIdInt = 777
    $isInt = $false
    $ValidId = $false
    [string[]]$NetNamePlusinstanceArray = @()
    [string]$PickedNetPlusInstance = ""

    if ($global:instance_independent_collection -eq $true)
    {
        Write-LogDebug "An instance-independent collection is requested. Skipping instance discovery." -DebugLogLevel 1
        return
    }

    #if SQL LogScout did not accept any values for parameter $ServerInstanceConStr 
    if (($true -eq [string]::IsNullOrWhiteSpace($ServerInstanceConStr)) -and $ServerInstanceConStr.Length -le 1 )
    {
        Write-LogDebug "Server Instance param is blank. Switching to auto-discovery of instances" -DebugLogLevel 2

        $NetNamePlusinstanceArray = Get-NetNameMatchingInstance

        if ($NetNamePlusinstanceArray.get(0) -eq $global:sql_instance_conn_str) 
        {
            $hard_coded_instance  = $NetNamePlusinstanceArray.Get(0)
            Write-LogDebug "No running SQL Server instances, thus returning the default '$hard_coded_instance' and collecting OS-data only" -DebugLogLevel 1
            return 
        }
        elseif ($NetNamePlusinstanceArray -and ($null -ne $NetNamePlusinstanceArray))
        {
            Write-LogDebug "NetNamePlusinstanceArray contains: " $NetNamePlusinstanceArray -DebugLogLevel 2

            #prompt the user to pick from the list

            
            if ($NetNamePlusinstanceArray.Count -ge 1)
            {
                

                #print out the instance names

                Write-LogInformation "Discovered the following SQL Server instance(s)`n"
                Write-LogInformation ""
                Write-LogInformation "ID	SQL Instance Name"
                Write-LogInformation "--	----------------"

                for($i=0; $i -lt $NetNamePlusinstanceArray.Count;$i++)
                {
                    Write-LogInformation $i "	" $NetNamePlusinstanceArray[$i]
                }

                while(($isInt -eq $false) -or ($ValidId -eq $false))
                {
                    Write-LogInformation ""
                    Write-LogWarning "Enter the ID of the SQL instance for which you want to collect diagnostic data. Then press Enter" 
                    #Write-LogWarning "Then press Enter" 

                    $SqlIdStr = Read-Host "Enter the ID from list above>" -CustomLogMessage "SQL Instance Console input:"
                    
                    try{
                            $SqlIdInt = [convert]::ToInt32($SqlIdStr)
                            $isInt = $true
                        }

                    catch [FormatException]
                        {
                            Write-LogError "The value entered for ID '",$SqlIdStr,"' is not an integer"
                        }
        
                    #validate this ID is in the list discovered 
                    for($i=0;$i -lt $NetNamePlusinstanceArray.Count;$i++)
                    {
                        if($SqlIdInt -eq $i)
                        {
                            $ValidId = $true
                            break;
                        }
                        else
                        {
                            $ValidId = $false
                        }
                    } #end of for

                }   #end of while


            }#end of IF



        }

        
        else
        {
            Write-LogError "NetNamePlusinstanceArray array is blank or null. Exiting..."
            exit
        }

        $str = "You selected instance '" + $NetNamePlusinstanceArray[$SqlIdInt] +"' to collect diagnostic data. "
        Write-LogInformation $str -ForegroundColor Green

        #set the global variable so it can be easily used by multiple collectors
        $global:sql_instance_conn_str = $NetNamePlusinstanceArray[$SqlIdInt] 

        return $NetNamePlusinstanceArray[$SqlIdInt] 

    }

    else 
    {
        Write-LogDebug "Server Instance param is '$ServerInstanceConStr'. Using this value for data collection" -DebugLogLevel 2
        $global:sql_instance_conn_str = $ServerInstanceConStr
    }
}

#======================================== END OF NETNAME + INSTANCE SECTION

#======================================== START OF PERFMON COUNTER FILES SECTION


function Strip-InstanceName([string]$NetnamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    $selectedSqlInstance  = $NetnamePlusInstance.Substring($NetnamePlusInstance.IndexOf("\") + 1)
    return $selectedSqlInstance 
}


function Build-PerfmonString ([string]$NetNamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    #if default instance, this function will return the hostname
    $host_name = hostname

    $instance_name = Strip-InstanceName($NetNamePlusInstance)

    #if default instance use "SQLServer", else "MSSQL$InstanceName
    if ($instance_name -eq $host_name)
    {
        $perfmon_str = "SQLServer"
    }
    else
    {
        $perfmon_str = "MSSQL$"+$instance_name

    }

    Write-LogDebug "Perfmon string is: $perfmon_str" -DebugLogLevel 2

    return $perfmon_str
}


function Update-PerfmonConfigFile([string]$NetNamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    #fetch the location of the copied counter file in the \internal folder. Could write a function in the future if done more than once
    $internal_directory = $global:internal_output_folder
    $perfmonCounterFile = $internal_directory+$global:perfmon_active_counter_file

    Write-LogDebug "New Perfmon counter file location is: " $perfmonCounterFile -DebugLogLevel 2

    $original_string = 'MSSQL$*:'
    $new_string = Build-PerfmonString ($NetNamePlusInstance) 
    $new_string += ":"
    
    Write-LogDebug "Replacement string is: " $new_string -DebugLogLevel 2

    try
    {
            if (Test-Path -Path $perfmonCounterFile)
            {
                #This does the magic. Loads the file in memory, and replaces the original string with the new built string
                ((Get-Content -path $perfmonCounterFile -Raw ) -replace  [regex]::Escape($original_string), $new_string) | Set-Content -Path $perfmonCounterFile 
            }
            else 
            {
                Write-LogError "The file $perfmonCounterFile does not exist."
            }
    }
    catch 
    {   
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "Copy-Item or Remove-Item cmdlet failed with the following error:  $error_msg"    
    }
}

function Copy-OriginalLogmanConfig()
{
    #this function makes a copy of the original Perfmon counters LogmanConfig.txt file in the \output\internal directory
    #the file will be used from there
    

    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    $internal_path = $global:internal_output_folder
    $present_directory = $global:present_directory
    $perfmon_file = $global:perfmon_active_counter_file

    $perfmonCounterFile = $present_directory+"\"+$perfmon_file     #"LogmanConfig.txt"
    $destinationPerfmonCounterFile = $internal_path + $perfmon_file   #\output\internal\LogmanConfig.txt
    

    try
    {
        if(Test-Path -Path $internal_path)
        {
            #copy the file to internal path so it can be used from there
            Copy-Item -Path $perfmonCounterFile -Destination $destinationPerfmonCounterFile -ErrorAction Stop
            Write-LogInformation "$perfmon_file copied to " $destinationPerfmonCounterFile
            
            #file has been copied
            return $true
        }
        else 
        {
            Write-LogError "The file $perfmonCounterFile is not present."
            return $false
        }
        
        
    }

    catch
    {
        $error_msg = $PSItem.Exception.Message 
        if ($error_msg -Match "because it does not exist")
        {
            Write-LogError "The $perfmon_file file does not exist."
        }
        else
        {
            Write-LogError "Copy-Item  cmdlet failed with the following error: " $error_msg 
            
        }

        return $false
    }
}



function PrepareCountersFile()
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    if (($global:sql_instance_conn_str -ne "") -and ($null -ne $global:sql_instance_conn_str) )
    {
        [string] $SQLServerName = $global:sql_instance_conn_str
    }
    else 
    {
        Write-LogError "SQL instance name is empty.Exiting..."    
        exit
    }

    if (Copy-OriginalLogmanConfig)
    {
        Write-LogDebug "Perfmon Counters file was copied. It is safe to update it in new location" -DebugLogLevel 2
        Update-PerfmonConfigFile($SQLServerName)
    }
    #restoration of original file is in the Stop-DiagCollectors
}


#======================================== END OF PERFMON COUNTER FILES SECTION



function Check-ElevatedAccess
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    #check for administrator rights
  
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    {
         Write-Warning "Administrator rights are recommended!`nSome functionality will not be available. Exiting..."
         exit
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

    if ($global:sql_instance_conn_str -eq "no_instance_found")
    {
        return
    }
    elseif ($global:sql_instance_conn_str -ne "")
    {
        $SQLInstance = $global:sql_instance_conn_str
    }
    else {
        Write-LogError "SQL Server instance name is empty. Exiting..."
        exit
    }
    
    $SQLInstanceUpperCase = $SQLInstance.ToUpper()
    Write-LogDebug "Received parameter SQLInstance: `"$SQLInstance`"" -DebugLogLevel 2
    Write-LogDebug "Received parameter SQLUser: `"$SQLUser`"" -DebugLogLevel 2
    Write-LogDebug "Received parameter SQLPassword (true/false): " (-not ($null -eq $SQLPassword)) #we don't print the password, just inform if we received it or not

    $SqlQuery = "select SUSER_SNAME() login_name, HAS_PERMS_BY_NAME(null, null, 'view server state') has_view_server_state, HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') has_alter_any_event_session"
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
    $DataSet = New-Object System.Data.DataSet

    Write-LogDebug "About to call SqlDataAdapter.Fill()" -DebugLogLevel 2
    try {
        $SqlAdapter.Fill($DataSet) | Out-Null #fill method returns rowcount, Out-Null prevents the number from being printed in console    
    }
    catch {
        Write-LogError "Could not connect to SQL Server instance '$SQLInstance' to validate permissions."
        
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.InnerException.Message 
        Write-LogError "$mycommand Function failed with error:  $error_msg"
        
        # we can't connect to SQL, probably whole capture will fail, so we just abort here
        return ($false)
    }
    
    Write-LogDebug "Closing SqlConnection" -DebugLogLevel 2
    $SqlConnection.Close()

    $account = $DataSet.Tables[0].Rows[0].login_name

    if ((1 -eq $DataSet.Tables[0].Rows[0].has_view_server_state) -and (1 -eq $DataSet.Tables[0].Rows[0].has_alter_any_event_session))
    {
        Write-LogDebug "has_view_server_state returned 1" -DebugLogLevel 2
        Write-LogInformation "Confirmed that $account has VIEW SERVER STATE on SQL Server Instance '$SQLInstanceUpperCase'"
        Write-LogInformation "Confirmed that $account has ALTER ANY EVENT SESSION on SQL Server Instance '$SQLInstanceUpperCase'"
        return $true #user has view server state
    } else {

        Write-LogDebug "either has_view_server_state or has_alter_any_event_session returned different than one, user does not have view server state" -DebugLogLevel 2
        #user does not have view server state

        Write-LogWarning "User account $account does not posses the required privileges in SQL Server instance '$SQLInstanceUpperCase'"
        Write-LogWarning "Proceeding with capture will result in SQLDiag not producing the necessary information."
        Write-LogWarning "To grant minimum privilege for a successful data capture, connect to SQL Server instance '$SQLInstanceUpperCase' using administrative account and execute the following:"
        Write-LogWarning ""

        if (1 -ne $DataSet.Tables[0].Rows[0].has_view_server_state) {
            Write-LogWarning "GRANT VIEW SERVER STATE TO [$account]"
        }

        if (1 -ne $DataSet.Tables[0].Rows[0].has_alter_any_event_session) {
            Write-LogWarning "GRANT ALTER ANY EVENT SESSION TO [$account]"
        }

        Write-LogWarning ""
        Write-LogWarning "One or more conditions that will affect the quality of data capture were detected."

        [string]$confirm = $null
        while (-not(($confirm -eq "Y") -or ($confirm -eq "N") -or ($null -eq $confirm)))
        {
            Write-LogWarning "Would you like to proceed capture without required permissions? (Y/N)"
            $confirm = Read-Host ">" -CustomLogMessage "SQL Permission Console input:"

            $confirm = $confirm.ToString().ToUpper()
            if (-not(($confirm -eq "Y") -or ($confirm -eq "N") -or ($null -eq $confirm)))
            {
                Write-LogError ""
                Write-LogError "Please chose [Y] to proceed capture without required permissions."
                Write-LogError "Please chose [N] to abort capture."
                Write-LogError ""
            }
        }

        if ($confirm -eq "Y"){ #user chose to continue
            return ($true)
        } else { #user chose to abort
            return ($false)
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
       Invoke-DiagnosticCleanUp
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
            Invoke-DiagnosticCleanUp
        }
		
		else
		{
			Invoke-DiagnosticCleanUp
			break;
		}
    }
}


function Test-MinPowerShellVersion
{
    
    Write-LogDebug "inside " $MyInvocation.MyCommand

    
    #check for minimum version 5 
    $psversion_maj = (Get-Host).Version.Major
    $psversion_min = (Get-Host).Version.Minor

    if ($psversion_maj -lt 5)
    {
        Write-LogWarning "Minimum required version of PowerShell is 5.x. Your current verion is $psversion_maj.$psversion_min. Exiting..."
        break

    }
}

function GetPerformanceDataAndLogs 
{
        
        #prompt for diagnostic scenario
        Select-Scenario

        #pick a sql instnace
        Pick-SQLServer-for-Diagnostics

        #check SQL permission and continue only if user has permissions or user confirms to continue without permissions
        $canContinue = Confirm-SQLPermissions 

        if ($false -eq $canContinue)
        {
            Write-LogInformation "No diagnostic logs will be collected"
            return
        }

        #prepare a pefmon counters file with specific instance info
        PrepareCountersFile

        #start collecting data
        Start-DiagCollectors
        
        #stop data collection
        Stop-DiagCollectors
}

function InvokePluginMenu () 
{
    <#
    .SYNOPSIS
        Can be used as an initial/first menu where we can call SQL LogScout collectors or external scipts if we find them useful
    #>

    $PluginArray = "Performance and Basic Logs", "Memory Dump(s)"
    
    Write-LogInformation "Please select what data you would like to collect:`n"
    Write-LogInformation ""
    Write-LogInformation "Choice   Scenario"
    Write-LogInformation "------   ---------------------------------"

    for ($i = 0; $i -lt $PluginArray.Count; $i++) {
        Write-LogInformation $i "      " $PluginArray[$i]
    }

    $isInt = $false
    $ScenarioIdInt = 777
    $pluginIntList = 0..1  #as we add more scenarios above, we will increase the range to match them



        
    while (($isInt -eq $false) -or ($ValidId -eq $false)) {
        Write-LogInformation ""
        Write-LogWarning "Enter the Choice ID for which you want to collect diagnostic data. Then press Enter" 

        $ScenIdStr = Read-Host "Enter the Choice ID from list above>" -CustomLogMessage "PlugIn Console input:"
            
        try {
            $ScenarioIdInt = [convert]::ToInt32($ScenIdStr)
            $isInt = $true
        }

        catch [FormatException] {
            Write-LogError "The value entered for Choice '", $ScenIdStr, "' is not an integer"
            continue 
        }

        #validate this ID is in the list discovered 
        if ($ScenarioIdInt -in ($pluginIntList)) {
            $ValidId = $true

            switch ($ScenarioIdInt) {
                0 { 
                    # Basic and Performance Logs
                    GetPerformanceDataAndLogs
                }
                1 {
                    # Memory Dumps
                    Write-Host "Output folder is $global:output_folder"
                    .\SQLDumpHelper.ps1 -DumpOutputFolder $global:output_folder # next make this use a parameter for dump location
                }
                Default { Write-LogError "No plugin was picked. Not sure why we are here" }
            }
                
        }
        else {
            $ValidId = $false
            Write-LogError "The ID entered '", $ScenIdStr, "' is not in the list "
        }
    } #end of while
}
function main () 
{

    
    Write-LogDebug "Scenario prameter passed is '$Scenario'" -DebugLogLevel 3

    try {  
        Init-AppVersion

        #check for minimum PowerShell version of 5.x
        Test-MinPowerShellVersion
    
        #check for administrator rights
        Check-ElevatedAccess
    
        #initialize globals for present folder, output folder, internal\error folder
        InitCriticalDirectories
        

        #check if output folder is already present and if so prompt for deletion. Then create new if deleted, or reuse
        Reuse-or-RecreateOutputFolder
    
        #create a log of events
        Initialize-Log -LogFilePath $global:internal_output_folder -LogFileName "##SQLLOGSCOUT.LOG"
    
    
        #invoke the main collectors code
        GetPerformanceDataAndLogs
    
        Write-LogInformation "Ending data collection" #DO NOT CHANGE - Message is backward compatible
    }   
    catch{
        Write-Error "An error occurred:"
        Write-Error $_
        Write-Error $_.ScriptStackTrace
    }
    finally {
        HandleCtrlCFinal
        Write-LogInformation ""
    }
}




#to execute from command prompt use: 
#powershell -ExecutionPolicy Bypass -File sqllogscoutps.ps1



#cleanup from previous script runs
#NOT needed when running script from CMD
#but helps when running script in debug from VSCode
if ($Global:logbuffer) {Remove-Variable -Name "logbuffer" -Scope "global"}
if ($Global:logstream)
{
    $Global:logstream.Flush
    $Global:logstream.Close
    Remove-Variable -Name "logstream" -Scope "global"
}

main
