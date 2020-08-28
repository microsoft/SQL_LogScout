## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.

param
(

    [ValidateSet(0,1,2,3,4,5)]
    [Parameter(Position=0,HelpMessage='Choose 0|1|2|3|4|5')]
    [int32] $DebugLevel = 0,

    #scenario is an optional parameter since there is a menu that covers for it if not present
    [ValidateSet("GeneralPerf", "DetailedPerf", "LightPerf","Memory","Basic","AlwaysOn","Replication")]
    [Parameter(Position=1,HelpMessage='Choose GeneralPerf|DetailedPerf|LightPerf|Memory|Basic|Replication|AlwaysOn')]
    [string] $Scenario = ""

)


#=======================================Globals =====================================
[console]::TreatControlCAsInput = $true
[string]$global:full_log_file_path = ""
[string]$global:present_directory = ""
[string]$global:output_folder = ""
[string]$global:internal_output_folder = ""
[string]$global:perfmon_active_counter_file = "LogmanConfig.txt"
[bool]$global:perfmon_counters_restored = $false
[string]$global:sql_instance_conn_str = ""
[System.Collections.ArrayList]$global:processes = [System.Collections.ArrayList]::new()
[int]$global:DEBUG_LEVEL = $DebugLevel #zero to disable, 1 to 5 to enable different levels of debug logging
[string] $global:ScenarioChoice = $Scenario
[bool]$global:stop_automatically = $false
[string] $global:xevent_collector = ""
[string] $global:app_version = ""
#=======================================Start of \OUTPUT and \ERROR directories and files Section

function Init-AppVersion()
{
    $major_version = "1"
    $minor_version = "1"
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

function Get-OutputPath()
{
	Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
    
    #the output folder is subfolder of current folder where the tool is running
	$global:output_folder =  ($global:present_directory + "\output\")

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

function Reuse-or-RecreateOutputFolder()
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    $output_folder = $global:output_folder
    $error_folder = $global:internal_output_folder

	Write-LogDebug "Output folder is: $global:output_folder" -DebugLogLevel 3
	Write-LogDebug "Error folder is: $error_folder" -DebugLogLevel 3
    

    #delete entire \output folder and files/subfolders before you create a new one, if user chooses that
    if (Test-Path -Path $output_folder)
    {
        Write-LogInformation ""
        
        [string]$deleteYN = $null
        while (-not(($deleteYN -eq "Y") -or ($deleteYN -eq "N")))
        {
            Write-LogWarning "It appears that output folder $output_folder has been used before."
            Write-LogWarning "DELETE the files it contains (Y/N)?"
            $deleteYN = Read-Host "Enter 'Y' or 'N' >"

            Write-LogInformation "Console input: $deleteYN"
            $deleteYN = $deleteYN.ToString().ToUpper()
            if (-not(($deleteYN -eq "Y") -or ($deleteYN -eq "N")))
            {
                Write-LogError ""
                Write-LogError "Please chose [Y] to DELETE the output folder $output_folder and all files inside of the folder."
                Write-LogError "Please chose [N] to continue using the same folder - will overwrite existing files as needed."
                Write-LogError ""
            }
        }
        #Get-Childitem -Path $output_folder -Recurse | Remove-Item -Confirm -Force -Recurse  | Out-Null
        if ($deleteYN = "Y") {Remove-Item -Path $output_folder -Force -Recurse  | Out-Null}
    }
	
    #create an output folder and error directory in one shot (creating the child folder \internal will create the parent \output also). -Force will not overwrite it, it will reuse the folder
    New-Item -Path $error_folder -ItemType Directory -Force | out-null 
}

function Build-FinalOutputFile([string]$output_file_name, [string]$collector_name, [bool]$needExtraQuotes)
{
	Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
	
	$final_output_file = $output_file_name +"_" + $collector_name + ".out"
	
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
function Write-Error
{
<#
    .SYNOPSIS
        Wrapper function to intercept calls to Write-Error and make sure those are logged by calling Write-LogError.
    .DESCRIPTION
        Wrapper function to intercept calls to Write-Error and make sure those are logged by calling Write-LogError.
        Once logging is done, this function will call original implementation of Write-Error.
    .EXAMPLE
        Preferred ==> Write-Error -Exception $_.Exception
        Write-Error "My custom error"
        Write-Error -ErrorRecord $_.Exception.ErrorRecord
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ParameterSetName = "NoException", Mandatory, ValueFromPipeline)]
    [Parameter(ParameterSetName = "WithException")]
    [Alias("Msg")]
    [string]$Message,

    [Parameter(ParameterSetName = "WithException", Mandatory)]
    [Exception]$Exception,

    [Parameter(ParameterSetName = "ErrorRecord", Mandatory)]
    [System.Management.Automation.ErrorRecord]$ErrorRecord,

    [Parameter(ParameterSetName = "NoException")]
    [Parameter(ParameterSetName = "WithException")]
    [System.Management.Automation.ErrorCategory]$Category = [System.Management.Automation.ErrorCategory]::NotSpecified,

    [Parameter(ParameterSetName = "NoException")]
    [Parameter(ParameterSetName = "WithException")]
    [string]$ErrorId = [string].Empty,

    [Parameter(ParameterSetName = "NoException")]
    [Parameter(ParameterSetName = "WithException")]
    [object]$TargetObject = $null,

    [Parameter()]
    [string]$RecommendedAction = [string].Empty,

    [Parameter()]
    [Alias("Activity")]
    [string]$CategoryActivity = [string].Empty,

    [Parameter()]
    [Alias("Reason")]
    [string]$CategoryReason = [string].Empty,

    [Parameter()]
    [Alias("TargetName")]
    [string]$CategoryTargetName = [string].Empty,

    [Parameter()]
    [Alias("TargetType")]
    [string]$CategoryTargetType = [string].Empty
    )


    switch ($PsCmdlet.ParameterSetName)
    {
        "NoException"
        {
            Write-LogError "Error with no exception"
            Write-LogError "Message: " $Message
            Write-LogError "Category: " $Category            
        }
        
        "WithException"
        {
            if("" -eq $Message) {$Message = $Exception.Message}
            if($null -eq $ErrorRecord) {$ErrorRecord = $Exception.ErrorRecord}

            Write-LogError "Error with Exception information"
            Write-LogError "Exception: " $Exception
            Write-LogError "ScriptLineNumber: " $ErrorRecord.InvocationInfo.ScriptLineNumber "OffsetInLine: " $ErrorRecord.InvocationInfo.OffsetInLine
            Write-LogError "Line: " $ErrorRecord.InvocationInfo.Line
            Write-LogError "ScriptStackTrace: " $ErrorRecord.ScriptStackTrace
            Write-LogError "Message: " $Message
            Write-LogError "Category: " $Category
        }
        
        "ErrorRecord"
        {
            if($null -eq $Exception) {$Exception = $ErrorRecord.Exception}
            if("" -eq $Message) {$Message = $Exception.Message}
            
            Write-LogError "Error with Error Record information"
            Write-LogError "Exception: " $Exception
            Write-LogError "ScriptLineNumber: " $ErrorRecord.InvocationInfo.ScriptLineNumber "OffsetInLine: " $ErrorRecord.InvocationInfo.OffsetInLine
            Write-LogError "Line: " $ErrorRecord.InvocationInfo.Line
            Write-LogError "ScriptStackTrace: " $ErrorRecord.ScriptStackTrace
            Write-LogError "Message: " $Message
            Write-LogError "Category: " $Category
        }
    }

    if("" -ne $ErrorId) {Write-LogError "ErrorId: " $ErrorId}
    if($null -ne $TargetObject) {Write-LogError "TargetObject: " $TargetObject}
    if("" -ne $RecommendedAction) {Write-LogError "RecommendedAction: " $RecommendedAction}
    if("" -ne $CategoryActivity) {Write-LogError "CategoryActivity: " $CategoryActivity}
    if("" -ne $CategoryReason) {Write-LogError "CategoryReason: " $CategoryReason}
    if("" -ne $CategoryTargetName) {Write-LogError "CategoryTargetName: " $CategoryTargetName}
    if("" -ne $CategoryTargetType) {Write-LogError "CategoryTargetType: " $CategoryTargetType}
    
    switch ($PsCmdlet.ParameterSetName)
    {
        "NoException"
        {
            Microsoft.PowerShell.Utility\Write-Error -Message $Message -Category $Category -ErrorId $ErrorId -TargetObject $TargetObject -RecommendedAction $RecommendedAction `
            -CategoryActivity $CategoryActivity -CategoryReason $CategoryReason -CategoryTargetName $CategoryTargetName -CategoryTargetType $CategoryTargetType
        }
        
        "WithException"
        {
            Microsoft.PowerShell.Utility\Write-Error -Exception $Exception -Message $Message -Category $Category -ErrorId $ErrorId -TargetObject $TargetObject `
            -RecommendedAction $RecommendedAction -CategoryActivity $CategoryActivity -CategoryReason $CategoryReason -CategoryTargetName $CategoryTargetName -CategoryTargetType $CategoryTargetType
        }
        
        "ErrorRecord"
        {
            Microsoft.PowerShell.Utility\Write-Error -ErrorRecord $ErrorRecord -RecommendedAction $RecommendedAction -CategoryActivity $CategoryActivity -CategoryReason $CategoryReason `
            -CategoryTargetName $CategoryTargetName -CategoryTargetType $CategoryTargetType
        }
    }
}
function Format-LogMessage()
{
<#
    .SYNOPSIS
        Format-LogMessage handles complex objects that need to be formatted before writing to the log
    .DESCRIPTION
        Format-LogMessage handles complex objects that need to be formatted before writing to the log
        To prevent writing "System.Collections.Generic.List`1[System.Object]" to the log
    .PARAMETER Message
        Object containing string, list, or list of lists
#>
[CmdletBinding()]
param ( 
    [Parameter(Mandatory)] 
    [ValidateNotNull()]
    [Object]$Message
    )

    [String]$strMessage = ""
    [String]$MessageType = $Message.GetType()

    if ($MessageType -eq "System.Collections.Generic.List[System.Object]")
    {
        foreach ($item in $Message) {
            
            [String]$itemType = $item.GetType()
            
            #if item is a list we recurse
            #if not we cast to string and concatenate
            if($itemType -eq "System.Collections.Generic.List[System.Object]")
            {
                $strMessage += Format-LogMessage($item) + " "
            } else {
                $strMessage += [String]$item + " "
            } 
        }
    } elseif (($MessageType -eq "string") -or ($MessageType -eq "System.String")) {
        $strMessage += [String]$Message + " "
    } else {
        Write-LogError "Unexpected MessageType in Format-LogMessage: " $MessageType
    }
    
    return $strMessage
    
}

function Initialize-Log()
{
<#
    .SYNOPSIS
        Initialize-Log creates the log file in right directory and sets global reference to StreamWriter object

    .DESCRIPTION
        Initialize-Log creates the log file in right directory and sets global reference to StreamWriter object

    .EXAMPLE
        Initialize-Log
#>
    #Safe to call Write-LogDebug because we will buffer the log entries while log is not initialized
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try
    {
        $error_folder = $global:internal_output_folder
        $log_file = "##SQLDIAG.LOG" 
        $global:full_log_file_path = $error_folder + $log_file
        
        #create a new folder if not already there - TODO: perhaps check if there Test-Path(), and only then create a new one
        New-Item -Path $error_folder -ItemType Directory -Force | out-null 
        
        #create the file and keep a reference to StreamWriter
        $global:logstream = [System.IO.StreamWriter]::new( $error_folder + $log_file, $false, [System.Text.Encoding]::ASCII)
        
        #add initial message
        Write-LogInformation "Initializing log $global:full_log_file_path"

        #if we buffered log messages while log was not initialized, now we need to write them
        if ($null -ne $global:logbuffer){
            foreach ($Message in $global:logbuffer) {
                $global:logstream.WriteLine([String]$Message)
            }
            $global:logstream.Flush()
        }
    }
    catch
    {
		Write-Error -Exception $_.Exception        
    }

}

function Write-Log()
{
<#
    .SYNOPSIS
        Write-Log will write message to log file and console

    .DESCRIPTION
        Write-Log will write message to log file and console.
        Should NOT be called directly, use wrapper functions such as Write-LogInformation, Write-LogWarning, Write-LogError, Write-LogDebug

    .PARAMETER Message
        Message string to be logged

    .PARAMETER ForegroundColor
        Color of the message to be displayed in console

    .EXAMPLE
        Should NOT be called directly, use wrapper functions such as Write-LogInformation, Write-LogWarning, Write-LogError, Write-LogDebug        
#>
    [CmdletBinding()]
    param ( 
        [Parameter(Mandatory,ValueFromRemainingArguments)] 
        [ValidateNotNull()]
        [Object]$Message,

        [Parameter(Mandatory)]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG1", "DEBUG2", "DEBUG3", "DEBUG4", "DEBUG5")]
        [String]$LogType,

        [Parameter()]
        [ValidateNotNull()]
        [System.ConsoleColor]$ForegroundColor,

        [Parameter()]
        [ValidateNotNull()]
        [System.ConsoleColor]$BackgroundColor
    )

    try
    {
        [String]$strMessage = Get-Date -Format "yyyy-MM-dd hh:mm:ss.fff"
        $strMessage += "	"
        $strMessage += $LogType
        $strMessage += "	"
        $strMessage += Format-LogMessage($Message)
        
        if ($null -ne $global:logstream)
        {
            #if log was initialized we just write $Message to it
            $stream = [System.IO.StreamWriter]$global:logstream
            $stream.WriteLine($strMessage)
            $stream.Flush() #this is necessary to ensure all log is written in the event of Powershell being forcefuly terminated
        } else {
            #because we may call Write-Log before log has been initialized, I will buffer the contents then dump to log on initialization
            
            #if the buffer does not exists we create it
            if ($null -eq $global:logbuffer){
                $global:logbuffer = @()
            }

            $global:logbuffer += ,$strMessage
        }

        #Write-Host $strMessage -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
        if (($null -eq $ForegroundColor) -and ($null -eq $BackgroundColor)) { #both colors null
            Write-Host $strMessage
        } elseif (($null -ne $ForegroundColor) -and ($null -eq $BackgroundColor)) { #only foreground
            Write-Host $strMessage -ForegroundColor $ForegroundColor
        } elseif (($null -eq $ForegroundColor) -and ($null -ne $BackgroundColor)) { #only bacground
            Write-Host $strMessage -BackgroundColor $BackgroundColor
        } elseif (($null -ne $ForegroundColor) -and ($null -ne $BackgroundColor)) { #both colors not null
            Write-Host $strMessage -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
        }    
    }
	catch
	{
		Write-Error -Exception $_.Exception 
	}
    
}

function Write-LogInformation()
{
<#
    .SYNOPSIS
        Write-LogInformation is a wrapper to Write-Log standardizing console color output

    .DESCRIPTION
        Write-LogInformation is a wrapper to Write-Log standardizing console color output

    .PARAMETER Message
        Message string to be logged

    .EXAMPLE
        Write-LogInformation "Log Initialized. No user action required."
#>
[CmdletBinding()]
param ( 
        [Parameter(Position=0,Mandatory,ValueFromRemainingArguments)] 
        [ValidateNotNull()]
        [Object]$Message,

        [Parameter()]
        [ValidateNotNull()]
        [System.ConsoleColor]$ForegroundColor,

        [Parameter()]
        [ValidateNotNull()]
        [System.ConsoleColor]$BackgroundColor
    )

    if (($null -eq $ForegroundColor) -and ($null -eq $BackgroundColor)) { #both colors null
        Write-Log -Message $Message -LogType "INFO"
    } elseif (($null -ne $ForegroundColor) -and ($null -eq $BackgroundColor)) { #only foreground
        Write-Log -Message $Message -LogType "INFO" -ForegroundColor $ForegroundColor
    } elseif (($null -eq $ForegroundColor) -and ($null -ne $BackgroundColor)) { #only bacground
        Write-Log -Message $Message -LogType "INFO" -BackgroundColor $BackgroundColor
    } elseif (($null -ne $ForegroundColor) -and ($null -ne $BackgroundColor)) { #both colors not null
        Write-Log -Message $Message -LogType "INFO" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    }
}

function Write-LogWarning()
{
<#
    .SYNOPSIS
        Write-LogWarning is a wrapper to Write-Log standardizing console color output

    .DESCRIPTION
        Write-LogWarning is a wrapper to Write-Log standardizing console color output

    .PARAMETER Message
        Message string to be logged

    .EXAMPLE
        Write-LogWarning "Sample warning."
#>
[CmdletBinding()]
param ( 
        [Parameter(Mandatory,ValueFromRemainingArguments)] 
        [ValidateNotNull()]
        [Object]$Message
    )

    Write-Log -Message $Message -LogType "WARN" -ForegroundColor Yellow
}

function Write-LogError()
{
<#
    .SYNOPSIS
        Write-LogError is a wrapper to Write-Log standardizing console color output

    .DESCRIPTION
        Write-LogError is a wrapper to Write-Log standardizing console color output

    .PARAMETER Message
        Message string to be logged

    .EXAMPLE
        Write-LogError "Error connecting to SQL Server instance"
#>
[CmdletBinding()]
param ( 
        [Parameter(Mandatory,ValueFromRemainingArguments)] 
        [ValidateNotNull()]
        [Object]$Message
    )

    Write-Log -Message $Message -LogType "ERROR" -ForegroundColor Red -BackgroundColor Black
}

function Write-LogDebug()
{
<#
    .SYNOPSIS
        Write-LogDebug is a wrapper to Write-Log standardizing console color output
        Logging of debug messages will be skip if debug logging is disabled.

    .DESCRIPTION
        Write-LogDebug is a wrapper to Write-Log standardizing console color output
        Logging of debug messages will be skip if debug logging is disabled.

    .PARAMETER Message
        Message string to be logged

    .PARAMETER DebugLogLevel
        Optional - Level of the debug message ranging from 1 to 5.
        When ommitted Level 1 is assumed.

    .EXAMPLE
        Write-LogDebug "Inside" $MyInvocation.MyCommand -DebugLogLevel 2
#>
[CmdletBinding()]
    param ( 
        [Parameter(Position=0,Mandatory,ValueFromRemainingArguments)] 
        [ValidateNotNull()]
        $Message,

        [Parameter()]
        [ValidateRange(1,5)]
        [Int]$DebugLogLevel
    )

    #when $DebugLogLevel is not specified we assume it is level 1
    #this is to avoid having to refactor all calls to Write-LogDebug because of new parameter
    if(($null -eq $DebugLogLevel) -or (0 -eq $DebugLogLevel)) {$DebugLogLevel = 1}

    try{

        #log message if debug logging is enabled and
        #debuglevel of the message is less than or equal to global level
        #otherwise we just skip calling Write-Log
        if(($global:DEBUG_LEVEL -gt 0) -and ($DebugLogLevel -le $global:DEBUG_LEVEL))
        {
            Write-Log -Message $Message -LogType "DEBUG$DebugLogLevel" -ForegroundColor Magenta
            return #return here so we don't log messages twice if both debug flags are enabled
        }
        
    } catch {
		Write-Error -Exception $_.Exception
    }
}
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
        $Identifier = "-- Windows Hotfix List --";
        $Header1 = PadString "HotfixID" 15;
        $header1 += PadString "InstalledOn" 15;
        $header1 += PadString "Description" 30;
        $header1 += PadString "InstalledBy" 30;
        $header2 = Replicate "-" 14
        $header2 += " ";
        $header2 += Replicate "-" 14;
        $header2 += " ";
        $header2 += Replicate "-" 29;
        $header2 += " ";
        $header2 += Replicate "-" 29;
        $header2 += " ";
        Add-Content -Value $Identifier -Path $output_file;
        Add-Content -Value $header1 -Path $output_file;
        Add-Content -Value $header2 -Path $output_file;

        foreach ($hf in $hotfixes) {
   
            $hotfixid = $hf["HotfixID"] + "";
            $installedOn = $hf["InstalledOn"] + "";
            $Description = $hf["Description"] + "";
            $InstalledBy = $hf["InstalledBy"] + "";
            $output = PadString  $hotfixid 15
            $output += PadString $installedOn  15;
            $output += PadString $Description 30;
            $output += PadString $InstalledBy  30;
      
            Add-Content -Value $output -Path $output_file;
      
        }

        $Blankstring = Replicate " " 50;
        Add-Content -Value $Blankstring -Path $output_file;

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}



function GetEventLogs($server) 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

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
        Get-EventLog -log System -Computer $servers   -newest 3000  | Format-Table -Property *  -AutoSize | Out-String -Width 20000  | out-file $sysevtfile

            
    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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

    try {
        
    
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
        
            $counter++
        }

        Add-Content -Path ($output_file_txt) -Value ($TXToutput.ToString())
        Add-Content -Path ($output_file_csv) -Value ($CSVoutput.ToString())
    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret      
    
    }
}

function MSDiagProcsCollector() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    ##create error output filenames using the path + servername + date and time
    $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)

    Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
    try {

        #msdiagprocs.sql
        #the output is potential errors so sent to error file
        $collector_name = "MSDiagProcs"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $error_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)
    }
    
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
    
}

function GetXeventsGeneralPerf() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        
    

        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3

        #XEvents file: pssdiag_xevent.sql - GENERAL Perf
        #there is no output file for this call - it creates the xevents. only errors if any

        #using the global here assumes that only one Xevent collector will be running at a time from SQL LogScout. Running multiple Xevent sessions is not expected and not reasonable
        $collector_name = $global:xevent_collector = "pssdiag_xevent"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $error_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        Start-Sleep -Seconds 2

        #add Xevent target
        $collector_name = "pssdiag_xevent_general_target"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $collector_name + ".xel' " + ", max_file_size=(500), max_rollover_files=(50)); END" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_add_target + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        #start the XEvent session
        $collector_name = "pssdiag_xevent_Start"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_collector]  ON SERVER STATE = START; END"
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_start + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)
    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
}

function GetXeventsDetailedPerf() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        
    
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3

        #XEvents file: pssdiag_xevent_detailed.sql - Detailed Perf
        #there is no output file for this call - it creates the xevents. only errors if any

        #using the global here assumes that only one Xevent collector will be running at a time from SQL LogScout. Running multiple Xevent sessions is not expected and not reasonable
        $collector_name = $global:xevent_collector = "pssdiag_xevent_detailed"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $error_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        Start-Sleep -Seconds 2

        #add Xevent target
        $collector_name = "pssdiag_xevent_detailed_target"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_add_target = "ALTER EVENT SESSION [$global:xevent_collector] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $collector_name + ".xel'" + ", max_file_size=(500), max_rollover_files=(50));" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_add_target + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

        #start the XEvent session
        $collector_name = "pssdiag_xevent_Start"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $alter_event_session_start = "ALTER EVENT SESSION [$global:xevent_collector]  ON SERVER STATE = START;" 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $error_file + " -Q`"" + $alter_event_session_start + "`""
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
}

function GetAlwaysOnDiag() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #AlwaysOn Basic Info
        $collector_name = "AlwaysOnDiagScript"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }

}

function GetSysteminfoSummary() 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3


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
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret      
    }
}

function GetMisciagInfo() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        
    
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
  
        #misc DMVs 
        $collector_name = "MiscPssdiagInfo"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)
    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret    
    }
}

function GetErrorlogs() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str
  
    try {
        
    
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #errorlogs
        $collector_name = "collecterrorlog"
        $input_script = Build-InputScript $global:present_directory $collector_name 
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -W -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret    
    }

}

function GetTaskList () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

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
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }
}

function GetRunningProfilerXeventTraces () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #active profiler traces and xevents
        $collector_name = "ExistingProfilerXeventTraces"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $input_script = Build-InputScript $global:present_directory "Profiler Traces"
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i " + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)
        
    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }


}

function GetHighCPUPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #SQL Server High CPU Perf Stats
        $collector_name = "HighCPU_perfstats"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #SQL Server Perf Stats
        $collector_name = "SQLServerPerfStats"
        $input_script = Build-InputScript $global:present_directory "SQL Server Perf Stats"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)
    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetPerfStatsSnapshot () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #SQL Server Perf Stats Snapshot
        $collector_name = "SQLServerPerfStatsSnapshotStartup"
        $input_script = Build-InputScript $global:present_directory "SQL Server Perf Stats Snapshot"
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetPerfmonCounters () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #Perfmon
        $collector_name = "Perfmon"
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "cmd.exe"
        $argument_list = "/C logman stop pssdiagperfmon & logman delete pssdiagperfmon & logman CREATE COUNTER -n pssdiagperfmon -cf LogmanConfig.txt -f bin -si 00:00:05 -max 250 -cnf 01:00:00  -o " + $output_file + "  & logman start pssdiagperfmon "
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetServiceBrokerInfo () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Service Broker collection
        $collector_name = "SSB_pssdiag"
        $input_script = Build-InputScript $global:present_directory $collector_name
        $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath  $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)
    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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
        $argument_list = "-S" + $server + " -E -Hpssdiag -w4000 -o" + $output_file + " -i" + $input_script
        Write-LogInformation "Executing Collector: $collector_name"
        Write-LogDebug $executable $argument_list
        $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -PassThru
        [void]$global:processes.Add($p)

    }
    catch {
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function GetFilterDrivers () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = Create-PartialOutputFilename ($server)
        $partial_error_output_file_name = Create-PartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

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
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
        $ret = $false
        return $ret   
    }

}

function Invoke-CommonCollectors()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    
    GetRunningDrivers
    GetSysteminfoSummary
    
    HandleCtrlC
    Start-Sleep -Seconds 1
    GetMisciagInfo

    HandleCtrlC
    Start-Sleep -Seconds 2
    GetTaskList 
    GetErrorlogs

    HandleCtrlC
    Start-Sleep -Seconds 2
    GetPowerPlan
    GetWindowsHotfixes
    GetFilterDrivers
    
    HandleCtrlC
    Start-Sleep -Seconds 2
    GetEventLogs
} 

function Invoke-GeneralPerfScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    
    Invoke-CommonCollectors
    GetPerfmonCounters
    
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

function Invoke-DetailedPerfScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    Invoke-CommonCollectors
    GetPerfmonCounters

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

function Invoke-AlwaysOnScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    HandleCtrlC
    Invoke-CommonCollectors
    GetAlwaysOnDiag
}

function Invoke-ReplicationScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    Invoke-CommonCollectors

    HandleCtrlC
    Start-Sleep -Seconds 2
    GetReplMetadata 
	GetChangeDataCaptureInfo 
    GetChangeTracking 

}



function Start-DiagColllectors ()
{


    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand


    Write-LogInformation ""
    Write-LogInformation "Initiating diagnostics collection... " -ForegroundColor Green

    [string[]] $ScenarioArray = "Basic (no performance data)","General Performance (recommended for most cases)","Detailed Performance (statement level and query plans)","Replication","AlwaysON"

    if ($global:ScenarioChoice -eq "")
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
        $scenarioIntList = 0..4  #as we add more scenarios above, we will increase the range to match them



        
        while(($isInt -eq $false) -or ($ValidId -eq $false))
        {
            Write-LogInformation ""
            Write-LogWarning "Enter the Scenario ID for which you want to collect diagnostic data. Then press Enter" 

            $ScenIdStr = Read-Host "Enter the Scenario ID from list above>"
            Write-LogInformation "Console input: $ScenIdStr"
            
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
            if($ScenarioIdInt -in ($scenarioIntList))
            {
                $ValidId = $true
                #$global:ScenarioChoice = $ScenarioIdInt

                switch ($ScenarioIdInt) 
                {
                    0 { $global:ScenarioChoice = "Basic"}
                    1 { $global:ScenarioChoice = "GeneralPerf"}
                    2 { $global:ScenarioChoice = "DetailedPerf"}
                    3 { $global:ScenarioChoice = "Replication" }
                    4 { $global:ScenarioChoice = "AlwaysOn"  }
                    Default { Write-LogError "No scenario was picked. Not sure why we are here"}
                }
                
            }
            else
            {
                $ValidId = $false
                Write-LogError "The ID entered '",$ScenIdStr,"' is not in the list "
            }
        } #end of while

    }
        
            
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
            Write-LogInformation "The Basic collector will stop automatically after it gathers logs"
            Invoke-CommonCollectors 
            $global:stop_automatically = $true
            
        }
        "AlwaysOn"
        {
            Invoke-AlwaysOnScenario
        }
        "Replication"
        {
            Invoke-ReplicationScenario
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

    if ($false -eq $global:stop_automatically)
    #wait for user to type "STOP"
    {
        while($ValidStop -eq $false)
        {
                Write-LogWarning "Please type 'STOP' or 'stop' to terminate the diagnostics collection when you finished capturing the issue"
                $StopStr = Read-Host ">" 
                Write-LogInformation "Console input: $StopStr"
                    
                #validate this PID is in the list discovered 
                if(($StopStr -eq "STOP") -or ($StopStr -eq "stop") )
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
        Write-LogDebug "Shutting down automatically. No long-term collectors to wait for" -DebugLogLevel 2
        Write-LogInformation "Shutting down the collector" -ForegroundColor Green #DO NOT CHANGE - Message is backward compatible
    }        
    #create an output directory. -Force will not overwrite it, it will reuse the folder
    #$global:present_directory = Convert-Path -Path "."

    $partial_output_file_name = Create-PartialOutputFilename -server $server
    $partial_error_output_file_name = Create-PartialErrorOutputFilename -server $server


    #SQL Server Perf Stats Snapshot
    $collector_name = "SQLServerPerfStatsSnapshotShutdown"
    $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
    $output_file = Build-FinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
    $input_script = Build-InputScript $global:present_directory "SQL Server Perf Stats Snapshot"
    $argument_list ="-S" + $server +  " -E -Hpssdiag_stop -w4000 -o"+$output_file + " -i"+$input_script
    Write-LogDebug $argument_list
    Write-LogInformation "Stopping Collector: $collector_name"
    $p = Start-Process -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden -PassThru
    [void]$global:processes.Add($p)

    #STOP the XEvent session
    $collector_name = "xevents_stop"
    $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true  
    $alter_event_session_stop = "ALTER EVENT SESSION [$global:xevent_collector] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_collector] ON SERVER;" 
    $argument_list ="-S" + $server +  " -E -Hpssdiag_stop -w4000 -o"+$error_file  + " -Q`"" + $alter_event_session_stop + "`""
    Write-LogInformation "Stopping Collector: $collector_name"
    Write-LogDebug $alter_event_session_stop
    Write-LogDebug $argument_list
    $p = Start-Process -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden -PassThru
    [void]$global:processes.Add($p)

    #STOP Perfmon
    $collector_name = "PerfmonStop"
    $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
    $argument_list ="/C logman stop pssdiagperfmon & logman delete pssdiagperfmon"
    Write-LogInformation "Stopping Collector: $collector_name"
    Write-LogDebug $argument_list
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden -PassThru
    [void]$global:processes.Add($p)

    # #sp_diag_trace_flag_restore
    # $collector_name = "RestoreTraceFlagOrigValues"
    # $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
    # $query = "EXEC tempdb.dbo.sp_diag_trace_flag_restore  'SQLDIAG'"  
    # $argument_list ="-S" + $server +  " -E -Hpssdiag_stop -w4000 -o"+$error_file + " -Q`""+ $query + "`" "
    # Write-LogInformation "Stopping Collector: $collector_name"
    # Write-LogDebug $argument_list
    # $p = Start-Process -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden -PassThru
    # [void]$global:processes.Add($p)

    #wait for other work to finish
    Start-Sleep -Seconds 3

    #sp_killpssdiagSessions
    #send the output file to \internal
    $collector_name = "killpssdiagSessions"
    $error_file = Build-FinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $true
    $query = "declare curSession 
    CURSOR for select 'kill ' + cast( session_id as varchar(max)) from sys.dm_exec_sessions where host_name = 'pssdiag' and program_name='SQLCMD' and session_id <> @@spid
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
    $argument_list ="-S" + $server +  " -E -Hpssdiag_stop -w4000 -o"+$error_file + " -Q`""+ $query + "`" "
    Write-LogInformation "Running: $collector_name"
    Write-LogDebug $argument_list
    $p = Start-Process -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden -PassThru
    [void]$global:processes.Add($p)


    Write-LogInformation "Waiting 5 seconds to ensure files are written to and closed by any program including anti-virus..." -ForegroundColor Green
    Start-Sleep -Seconds 5

    ##delete 0-byte log files
    #$files_to_delete = Get-ChildItem -path ($output_folder + "internal\") | Where-Object Length  -eq 0 | Remove-Item -Force 
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
    CURSOR for select 'kill ' + cast( session_id as varchar(max)) from sys.dm_exec_sessions where host_name = 'pssdiag' and program_name='SQLCMD' and session_id <> @@spid
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
  $executable = "sqlcmd.exe"
  $argument_list ="-S" + $server +  " -E -Hpssdiag_cleanup -w4000 -Q`""+ $query + "`" "
  Write-LogDebug $executable $argument_list
  $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
  [void]$global:processes.Add($p)
  
  #STOP Perfmon
  $executable = "cmd.exe"
  $argument_list ="/C logman stop pssdiagperfmon & logman delete pssdiagperfmon"
  Write-LogDebug $executable $argument_list
  $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
  [void]$global:processes.Add($p)
  
    
  $alter_event_session_stop = "ALTER EVENT SESSION [$global:xevent_collector] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_collector] ON SERVER" 
  $executable = "sqlcmd.exe"
  $argument_list ="-S" + $server +  " -E -Hpssdiag_cleanup -w4000 -Q`"" + $alter_event_session_stop + "`""
  Write-LogDebug $executable $argument_list
  $p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -PassThru
  [void]$global:processes.Add($p)

  exit
}



#======================================== END OF Diagnostics Collection SECTION


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
        $error_msg = $PSItem.Exception.Message 
        Write-LogError "$MyInvocation.MyCommand Function failed with error:  $error_msg"
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
        Write-LogInformation "There are curerntly no running instances of SQL Server. Exiting..." -ForegroundColor Green
        break  #done with execution - nothing else to do
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

    if ($instanceArrayLocal -and ($instanceArrayLocal -ne $null))
    {
        Write-LogDebug "InstanceArrayLocal contains:" $instanceArrayLocal -DebugLogLevel 2

        #build NetName + Instance 

        $isClustered = IsClustered($instanceArrayLocal)

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

    $NetNamePlusinstanceArray = Get-NetNameMatchingInstance

    if ($NetNamePlusinstanceArray -and ($NetNamePlusinstanceArray -ne $null))
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

                $SqlIdStr = Read-Host "Enter the ID from list above>"
                Write-LogInformation "Console input: $SqlIdStr"
                
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
        break
    }

    $str = "You selected instance '" + $NetNamePlusinstanceArray[$SqlIdInt] +"' to collect diagnostic data. "
    Write-LogInformation $str -ForegroundColor Green

    #set the global variable so it can be easily used by multiple collectors
    $global:sql_instance_conn_str = $NetNamePlusinstanceArray[$SqlIdInt] 

    return $NetNamePlusinstanceArray[$SqlIdInt] 
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
            Write-LogInformation "$perfmon_file copied to " $destinationPerfmonCounterFile -ForegroundColor Green
            
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



function PrepareCountersFile([string]$NetNamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    if (Copy-OriginalLogmanConfig)
    {
        Write-LogDebug "Perfmon Counters file was copied. It is safe to update it in new location"
        Update-PerfmonConfigFile($NetNamePlusInstance)
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

    .PARAMETER SQLInstance
        SQL Server instance name. Either SERVERNAME or SERVERNAME\INSTANCENAME
    
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
    [Parameter(Mandatory)] 
    [ValidateNotNullorEmpty()]
    [string]$SQLInstance,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SQLUser,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SQLPwd
    )

    Write-LogDebug "inside " $MyInvocation.MyCommand
    Write-LogDebug "Received parameter SQLInstance: `"$SQLInstance`"" -DebugLogLevel 2
    Write-LogDebug "Received parameter SQLUser: `"$SQLUser`"" -DebugLogLevel 2
    Write-LogDebug "Received parameter SQLPassword (true/false): " (-not ($null -eq $SQLPassword)) #we don't print the password, just inform if we received it or not

    $SqlQuery = "select SUSER_SNAME() login_name, HAS_PERMS_BY_NAME(null, null, 'view server state') has_view_server_state"
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
    $SqlAdapter.Fill($DataSet) | Out-Null #fill method returns rowcount, Out-Null prevents the number from being printed in console
    
    Write-LogDebug "Closing SqlConnection" -DebugLogLevel 2
    $SqlConnection.Close()

    $account = $DataSet.Tables[0].Rows[0].login_name

    if (1 -eq $DataSet.Tables[0].Rows[0].has_view_server_state)
    {
        Write-LogDebug "has_view_server_state returned 1" -DebugLogLevel 2
        Write-LogInformation "Confirmed that $account has VIEW SERVER STATE on SQL Server Instance $SQLInstance"
        return $true #user has view server state
    } else {

        Write-LogDebug "has_view_server_state returned different than one, user does not have view server state" -DebugLogLevel 2
        #user does not have view server state

        Write-LogWarning "User account $account does not posses VIEW SERVER STATE PERMISSION in SQL Server instance $SQLInstance"
        Write-LogWarning "Proceeding with capture will result in SQLDiag not producing the necessary information."
        Write-LogWarning "To grant minimum privilege for a good data capture, connect to SQL Server instance $SQLInstance using administrative account and execute the following:"
        Write-LogWarning "GRANT VIEW SERVER STATE TO [$account]"

        [string]$confirm = $null
        while (-not(($confirm -eq "Y") -or ($confirm -eq "N") -or ($null -eq $confirm)))
        {
            Write-LogWarning "Would you like to proceed capture without required permissions? (Y/N)"
            $confirm = Read-Host ">"

            Write-LogInformation "Console input: $confirm"
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
            Write-LogWarning "f*******************f"
            Write-LogWarning "You pressed CTRL-C. Stopping diagnostic collection..."
            Write-LogWarning "f*******************f"
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



function main ()
{
    
    
    Write-LogDebug "Scenario is $Scenario" -DebugLogLevel 3
    
    [string]$pickedSQLInstance =""
    
	try
	{  
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
		Initialize-Log
		
		$pickedSQLInstance = Pick-SQLServer-for-Diagnostics
		
        #check SQL permission and continue only if user has permissions or user confirms to continue without permissions
        $shouldContinue = Confirm-SQLPermissions -SQLInstance $pickedSQLInstance
        if ($shouldContinue)
        {

            #prepare a pefmon counters file with specific instance info
            
            PrepareCountersFile -NetNamePlusInstance $pickedSQLInstance
            
            #start collecting the diagnostic data
            Start-DiagColllectors
            
            #stop data collection
            Stop-DiagCollectors
        }

        Write-LogInformation "Ending data collection" #DO NOT CHANGE - Message is backward compatible
	}   
	
	finally
    {
        HandleCtrlCFinal
        Write-LogInformation ""
    }
}




#to execute from command prompt use: 
#powershell -ExecutionPolicy Bypass -File PSSDIAG_ScriptOnly.ps1



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
