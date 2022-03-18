$CommonFuncModule = Get-Module -Name CommonFunctions | select-object Name

if ($CommonFuncModule.Name -ne "CommonFunctions")
{
    Import-Module -Name .\CommonFunctions.psm1
}


#=======================================Globals =====================================
[int]$global:DEBUG_LEVEL = 0 # zero to disable, 1 to 5 to enable different levels of debug logging to *CONSOLE*
[string]$global:full_log_file_path = ""
[System.IO.StreamWriter]$global:consoleLogStream
[System.IO.StreamWriter]$global:debugLogStream
[System.IO.StreamWriter]$global:ltDebugLogStream # log-term debug log, this will be stored in $env:TEMP, most recent 15 files are kept
$global:consoleLogBuffer = @()
$global:debugLogBuffer = @()

#=======================================Init    =====================================
#cleanup from previous script runs
#NOT needed when running script from CMD
#but helps when running script in debug from VSCode
if ($Global:consoleLogBuffer) {Remove-Variable -Name "consoleLogBuffer" -Scope "global"}
if ($Global:debugLogBuffer) {Remove-Variable -Name "debugLogBuffer" -Scope "global"}
if ($Global:consoleLogStream)
{
    $Global:consoleLogStream.Flush
    $Global:consoleLogStream.Close
    Remove-Variable -Name "consoleLogStream" -Scope "global"
}
if ($Global:debugLogStream)
{
    $Global:debugLogStream.Flush
    $Global:debugLogStream.Close
    Remove-Variable -Name "debugLogStream" -Scope "global"
}
if ($Global:ltDebugLogStream)
{
    $Global:ltDebugLogStream.Flush
    $Global:ltDebugLogStream.Close
    Remove-Variable -Name "ltDebugLogStream" -Scope "global"
}

function Read-Host
{
<#
    .SYNOPSIS
        Wrapper function to intercept calls to Read-Host and make sure that input is recorded by calling Write-LogInformation.
    .DESCRIPTION
        Wrapper function to intercept calls to Read-Host and make sure that input is recorded by calling Write-LogInformation.
        By intercepting these calls we can ensure that all console reads get recorded into ##SQLLOGSCOUT.LOG.
    .EXAMPLE
        $ret = Read-Host
        $ret = Read-Host "Overwrite? (Y/N)"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [Object]$Prompt,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]$AsSecureString,

    [Parameter()]
    [string]$CustomLogMessage
    )

    # if CustomLogMessage was not passed as parameter we define a generic log message
    if (-not($PSBoundParameters.ContainsKey("CustomLogMessage"))){
        $CustomLogMessage = "Console Input:"
    }

    if ($AsSecureString) {
        $ret = Microsoft.PowerShell.Utility\Read-Host -Prompt $Prompt -AsSecureString
    } else {
        $ret = Microsoft.PowerShell.Utility\Read-Host -Prompt $Prompt
    }

    if ($ret.GetType() -eq "System.Security.SecureString"){
        Write-LogInformation ($CustomLogMessage + " <SecureString ommitted>")
    } else {
        Write-LogInformation ($CustomLogMessage + " " + $ret)
    }

    return $ret
}

function Write-Host
{
<#
    .SYNOPSIS
        Wrapper function to intercept calls to Write-Host and make sure those are logged by calling Write-Log*.
    .DESCRIPTION
        Wrapper function to intercept calls to Write-Host and make sure those are logged by calling Write-Log*.
        By intercepting these calls we can ensure that all messages get recorded into ##SQLLOGSCOUT.LOG.
        If foreground message color is yellow it'll invoke Write-LogWarning.
        If foreground message color is red it'll invoke Write-LogError.
        For any other color it will invoke Write-LogInformation.
    .EXAMPLE
        Write-Host "Test"
        Write-Host "Some warning" -ForegroundColor Yellow
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [Object]$Object,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]$NoNewline,
    
    [Parameter()]
    [Object]$Separator,

    [Parameter()]
    [System.ConsoleColor]$ForegroundColor,

    [Parameter()]
    [System.ConsoleColor]$BackgroundColor
    )

    if (-not($PSBoundParameters.ContainsKey("ForegroundColor"))){
        $ForegroundColor = [System.ConsoleColor]::White
    }

    if (-not($PSBoundParameters.ContainsKey("BackgroundColor"))){
        $BackgroundColor = [System.ConsoleColor]::Black
    }

    if ($ForegroundColor -eq [System.ConsoleColor]::Yellow){
        Write-LogWarning $Object
    } elseif ($ForegroundColor -eq [System.ConsoleColor]::Red){
        Write-LogError $Object
    } else {
        Write-LogInformation $Object -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    }
    #Microsoft.PowerShell.Utility\Write-Host $Object, $NoNewline, $Separator, $ForegroundColor, $BackgroundColor
}

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

    if (($MessageType -eq "System.Collections.Generic.List[System.Object]") -or
        ($MessageType -eq "System.Collections.ArrayList"))
    {
        foreach ($item in $Message) {
            
            [String]$itemType = $item.GetType()
            
            #if item is a list we recurse
            #if not we cast to string and concatenate
            if(($itemType -eq "System.Collections.Generic.List[System.Object]") -or
                ($itemType -eq "System.Collections.ArrayList"))
            {
                $strMessage += (Format-LogMessage($item)) + " "
            } else {
                $strMessage += [String]$item + " "
            } 
        }
    } elseif (($MessageType -eq "string") -or ($MessageType -eq "System.String")) {
        $strMessage += [String]$Message + " "
    } else {
        # calls native Write-Host implementation to avoid indirect recursion scenario
        Microsoft.PowerShell.Utility\Write-Host "Unexpected MessageType $MessageType" -ForegroundColor Red
        Microsoft.PowerShell.Utility\Write-Error "Unexpected MessageType $MessageType"
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
        Initialize-Log "C:\temp\" "mylog.txt"
        Initialize-Log -LogFileName "mylog.txt" # creates the log in current folder
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogFilePath = "./",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogFileName = "##SQLLOGSCOUT_CONSOLE.LOG"

    )

    #Safe to call Write-LogDebug because we will buffer the log entries while log is not initialized
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try
    {
        # if $global:consoleLogStream does not exists it means the log has not been initialized yet
        if ( -not(Get-Variable -Name logstream -Scope global -ErrorAction SilentlyContinue) ){
            
            #create a new folder if not already there - TODO: perhaps check if there Test-Path(), and only then create a new one
            New-Item -Path $LogFilePath -ItemType Directory -Force | out-null 
            
            #create the file and keep a reference to StreamWriter
            $full_log_file_path = $LogFilePath + $LogFileName
            Write-LogInformation "Creating log file $full_log_file_path"
            $global:consoleLogStream = New-Object -TypeName System.IO.StreamWriter -ArgumentList ($full_log_file_path, $false, [System.Text.Encoding]::ASCII)

            if ($LogFileName -like "*CONSOLE*"){
                # if the log file name contains the word CONSOLE we just replace by DEBUG
                $LogFileName = ($LogFileName -replace "CONSOLE", "DEBUG")
            } else {
                # otherwise just append _DEBUG.LOG to the name
                $LogFileName = $LogFileName.Split(".")[0]+"_DEBUG.LOG"
            }

            $full_log_file_path = $LogFilePath + $LogFileName
            Write-LogInformation "Creating debug log file $full_log_file_path"
            $global:debugLogStream = New-Object -TypeName System.IO.StreamWriter -ArgumentList ($full_log_file_path, $false, [System.Text.Encoding]::ASCII)
            
            # before we create the long-term debug log
            # we prune these files leaving only the 9 most recent ones
            # after that we create the 10th
            Write-LogDebug "Pruning older SQL LogScout DEBUG Logs in $env:TEMP" -DebugLogLevel 1
            $LogFileName = ($LogFileName -replace "_DEBUG.LOG", ("_DEBUG_*.LOG"))
            $FilesToDelete = (Get-ChildItem -Path ($env:TEMP + "\" + $LogFileName) | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip 9)
            $NumFilesToDelete = $FilesToDelete.Count

            Write-LogDebug "Found $NumFilesToDelete older SQL LogScout DEBUG Logs" -DebugLogLevel 2

            # if we have files to delete
            if ($NumFilesToDelete -gt 0) {
                $FilesToDelete | ForEach-Object {
                    $FullFileName = $_.FullName
                    Write-LogDebug "Attempting to remove file: $FullFileName" -DebugLogLevel 5
                    try {
                        Remove-Item $_
                    } catch {
                        Write-Error -Exception $_.Exception
                    }
                }
            }

            # determine the name of the long-term debug log
            $LogFileName = ($LogFileName -replace "_DEBUG_\*.LOG", ("_DEBUG_" + @(Get-Date -Format FileDateTime) + ".LOG"))
            
            # create the long-term debug log and keep a reference to it
            $full_log_file_path = $env:TEMP + "\" + $LogFileName
            Write-LogInformation "Creating long term debug log file $full_log_file_path"
            $global:ltDebugLogStream = New-Object -TypeName System.IO.StreamWriter -ArgumentList ($full_log_file_path, $false, [System.Text.Encoding]::ASCII)
            
            #if we buffered log messages while log was not initialized, now we need to write them
            if ($null -ne $global:consoleLogBuffer){
                foreach ($Message in $global:consoleLogBuffer) {
                    $global:consoleLogStream.WriteLine([String]$Message)
                }
                $global:consoleLogStream.Flush()
            }

            if ($null -ne $global:debugLogBuffer){
                foreach ($Message in $global:debugLogBuffer) {
                    $global:debugLogStream.WriteLine([String]$Message)
                    $global:ltDebugLogStream.WriteLine([String]$Message)
                }
                $global:debugLogStream.Flush()
                $global:ltDebugLogStream.Flush()
            }

            Write-LogInformation "Log initialization complete!"

        } else { #if the log has already been initialized then throw an error
            Write-LogError "Attempt to initialize log already initialized!"
        }
    }
    catch
    {
		#Write-Error -Exception $_.Exception
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  -exit_logscout $true
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
        [String]$strMessage = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $strMessage += "	"
        $strMessage += $LogType
        $strMessage += "	"
        $strMessage += Format-LogMessage($Message)
        
        # all non-debug messages are now logged to console log
        if ($LogType -in("INFO", "WARN", "ERROR")) {

            if ($null -ne $global:consoleLogStream)
            {
                #if log was initialized we just write $Message to it
                $stream = [System.IO.StreamWriter]$global:consoleLogStream
                $stream.WriteLine($strMessage)
                $stream.Flush() #this is necessary to ensure all log is written in the event of Powershell being forcefuly terminated
            } else {
                #because we may call Write-Log before log has been initialized, I will buffer the contents then dump to log on initialization
                
                $global:consoleLogBuffer += ,$strMessage
            }
        }

        # log both debug and non-debug messages to debug log
        if (($null -ne $global:debugLogStream) -and ($null -ne $global:ltDebugLogStream))
        {
            #if log was initialized we just write $Message to it
            $stream = [System.IO.StreamWriter]$global:debugLogStream
            $stream.WriteLine($strMessage)
            $stream.Flush() #this is necessary to ensure all log is written in the event of Powershell being forcefuly terminated

            #then repeat for long term debug log as well
            $stream = [System.IO.StreamWriter]$global:ltDebugLogStream
            $stream.WriteLine($strMessage)
            $stream.Flush() #this is necessary to ensure all log is written in the event of Powershell being forcefuly terminated

        } else {
            #because we may call Write-Log before log has been initialized, I will buffer the contents then dump to log on initialization
            
            $global:debugLogBuffer += ,$strMessage
        }
        
        if ($LogType -like "DEBUG*"){
            $dbgLevel = [int][string]($LogType[5])
        } else {
            $dbgLevel = 0
        }

        if (($LogType -in("INFO", "WARN", "ERROR")) -or
            ($dbgLevel -le $global:DEBUG_LEVEL)) {
            #Write-Host $strMessage -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
            if (($null -eq $ForegroundColor) -and ($null -eq $BackgroundColor)) { #both colors null
                Microsoft.PowerShell.Utility\Write-Host $strMessage
            } elseif (($null -ne $ForegroundColor) -and ($null -eq $BackgroundColor)) { #only foreground
                Microsoft.PowerShell.Utility\Write-Host $strMessage -ForegroundColor $ForegroundColor
            } elseif (($null -eq $ForegroundColor) -and ($null -ne $BackgroundColor)) { #only bacground
                Microsoft.PowerShell.Utility\Write-Host $strMessage -BackgroundColor $BackgroundColor
            } elseif (($null -ne $ForegroundColor) -and ($null -ne $BackgroundColor)) { #both colors not null
                Microsoft.PowerShell.Utility\Write-Host $strMessage -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
            }
        }
    }
	catch
	{
		HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
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

    try 
    {
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
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
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

    try
    {

        #log message if debug logging is enabled and
        #debuglevel of the message is less than or equal to global level
        #otherwise we just skip calling Write-Log
        # if(($global:DEBUG_LEVEL -gt 0) -and ($DebugLogLevel -le $global:DEBUG_LEVEL))
        # {
            Write-Log -Message $Message -LogType "DEBUG$DebugLogLevel" -ForegroundColor Magenta
            return #return here so we don't log messages twice if both debug flags are enabled
        # }
        
    } 
    
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

# SIG # Begin signature block
# MIInvQYJKoZIhvcNAQcCoIInrjCCJ6oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBtd6i1lKa6YRy2
# AeLqOVb+eda38tkwMGKPisIbab2cGqCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGY4wghmKAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIABi
# ibYj4RQgI0sfjGvYXAw6tD37125VXWKnHEH49ruyMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQAYc5ghmWiO7h0jBXgNVi4GyU4g/JwNufDZ
# l+6DYH4JvgevQGrTQ4ZN/ufW19V9cIMaKcRwTY5SckhucLc/wz0GP/b9LYjQSGof
# cCracgeYF76xwdRCtCmZ7cakZa5tX/+uigFRTmxJbYgdiN299DQxk5ohed/m4BDl
# FfaRYpamlFYU65G5Y0tdnjUeKn+Pp5NFpzJJdD4YAz4flW8rxIALHvnXkbcrb6AP
# AVtMbu0ZzksJ44oW0cujr5ulc1ge4gzsTfp1dU4IbxtpAsI5GiduhCMTelDzHEAr
# K7Olau1luf8ZPcUNOgsMI0YZ9XOi8SVJzOTqMw1V06SKAgP6riY2oYIXFjCCFxIG
# CisGAQQBgjcDAwExghcCMIIW/gYJKoZIhvcNAQcCoIIW7zCCFusCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIF1R/aSxl0I3gWMtfEp4MBjMhqGluI6p
# pf63CYgvnxxUAgZiCKzlXwkYEzIwMjIwMzAxMTI1MDE4LjA3OVowBIACAfSggdik
# gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UE
# CxMdVGhhbGVzIFRTUyBFU046ODZERi00QkJDLTkzMzUxJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghFlMIIHFDCCBPygAwIBAgITMwAAAYwB
# l2JHNnZmOwABAAABjDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDAeFw0yMTEwMjgxOTI3NDRaFw0yMzAxMjYxOTI3NDRaMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjg2REYtNEJCQy05MzM1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 00hoTKET+SGsayw+9BFdm+uZ+kvEPGLd5sF8XlT3Uy4YGqT86+Dr8G3k6q/lRagi
# xRKvn+g2AFRL9VuZqC1uTva7dZN9ChiotHHFmyyQZPalXdJTC8nKIrbgTMXAwh/m
# bhnmoaxsI9jGlivYgi5GNOE7u6TV4UOtnVP8iohTUfNMKhZaJdzmWDjhWC7LjPXI
# ham9QhRkVzrkxfJKc59AsaGD3PviRkgHoGxfpdWHPPaW8iiEHjc4PDmCKluW3J+I
# dU38H+MkKPmekC7GtRTLXKBCuWKXS8TjZY/wkNczWNEo+l5J3OZdHeVigxpzCnes
# kZfcHXxrCX2hue7qJvWrksFStkZbOG7IYmafYMQrZGull72PnS1oIdQdYnR5/ngc
# vSQb11GQ0kNMDziKsSd+5ifUaYbJLZ0XExNV4qLXCS65Dj+8FygCjtNvkDiB5Hs9
# I7K9zxZsUb7fKKSGEZ9yA0JgTWbcAPCYPtuAHVJ8UKaT967pJm7+r3hgce38VU39
# speeHHgaCS4vXrelTLiUMAl0Otk5ncKQKc2kGnvuwP2RCS3kEEFAxonwLn8pyedy
# reZTbBMQBqf1o3kj0ilOJ7/f/P3c1rnaYO01GDJomv7otpb5z+1hrSoIs8u+6eru
# JKCTihd0i/8bc67AKF76wpWuvW9BhbUMTsWkww4r42cCAwEAAaOCATYwggEyMB0G
# A1UdDgQWBBSWzlOGqYIhYIh5Vp0+iMrdQItSIzAfBgNVHSMEGDAWgBSfpxVdAF5i
# XYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQDXaMVFWMIJqdblQZK6
# oks7cdCUwePAmmEIedsyusgUMIQlQqajfCP9iG58yOFSRx2k59j2hABSZBxFmbkV
# jwhYEC1yJPQm9464gUz5G+uOW51i8ueeeB3h2i+DmoWNKNSulINyfSGgW6PCDCiR
# qO3qn8KYVzLzoemfPir/UVx5CAgVcEDAMtxbRrTHXBABXyCa6aQ3+jukWB5aQzLw
# 6qhHhz7HIOU9q/Q9Y2NnVBKPfzIlwPjb2NrQGfQnXTssfFD98OpRHq07ZUx21g4p
# s8V33hSSkJ2uDwhtp5VtFGnF+AxzFBlCvc33LPTmXsczly6+yQgARwmNHeNA262W
# qLLJM84Iz8OS1VfE1N6yYCkLjg81+zGXsjvMGmjBliyxZwXWGWJmsovB6T6h1Grf
# mvMKudOE92D67SR3zT3DdA5JwL9TAzX8Uhi0aGYtn5uNUDFbxIozIRMpLVpP/YOL
# ng+r2v8s8lyWv0afjwZYHBJ64MWVNxHcaNtjzkYtQjdZ5bhyka6dX+DtQD9bh3zj
# i0SlrfVDILxEb6OjyqtfGj7iWZvJrb4AqIVgHQaDzguixES9ietFikHff6p97C5q
# obTTbKwN0AEP3q5teyI9NIOVlJl0gi5Ibd58Hif3JLO6vp+5yHXjoSL/MlhFmvGt
# aYmQwD7KzTm9uADF4BzP/mx2vzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
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
# VTNYs6FwZvKhggLUMIICPQIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046ODZE
# Ri00QkJDLTkzMzUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2WiIwoBATAHBgUrDgMCGgMVADSi8hTrq/Q8oppweGyuZLNEJq/VoIGDMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDl
# yEKPMCIYDzIwMjIwMzAxMTQ1ODIzWhgPMjAyMjAzMDIxNDU4MjNaMHQwOgYKKwYB
# BAGEWQoEATEsMCowCgIFAOXIQo8CAQAwBwIBAAICEVIwBwIBAAICET0wCgIFAOXJ
# lA8CAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAweh
# IKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQBi+5XMdtqAHwccI/0hOCQB
# gH3GaBwc/rayKALDUF1INCVdE1cIW63mKkQwvmHmuqp7k6+Nv3OGeQiiNzGGo4Xw
# X9KNXsp9jxHTUbhSQBcTFQoPWGkPg12VECVpoq7F2sqSH6z77BvhgIbxzAOK3AfP
# qJCc5m8l3eUGilQBx3w6DDGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAABjAGXYkc2dmY7AAEAAAGMMA0GCWCGSAFlAwQCAQUA
# oIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIE
# IIW5SrnScFrBaJGM7zYPYcy/wZr8E0ByA2yNPOP48b/SMIH6BgsqhkiG9w0BCRAC
# LzGB6jCB5zCB5DCBvQQg1a2L+BUqkM8Gf8TmIQWdgeKTTrYXIwOofOuJiBiYaZ4w
# gZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAYwBl2JH
# NnZmOwABAAABjDAiBCBNlUx5c5VGUitqq4K6lo3v3VKS0jyFzTGb6pAcAmYkzzAN
# BgkqhkiG9w0BAQsFAASCAgCJGNZI833MJjAy2pj9ew9TP/x7YL1x7h/cG9F69y/v
# T9AiXCI2Cu+y3r9ux41qWZGEL1PZwt+UyoO5I798ESj25Karf/hdj+nJHAAqiQHs
# g1LkPDenuqA612eMrF15fwqvjovJRUzfq4wPsEd2+k2M9VCXI8q2gZKEhZ5W7kTV
# ddkeM+jTMcq7/7WayeVSG98RdZEv8SpMkuF/k/CrAaktj4eW45hu56+/9JIG0pKA
# ReXxgS4tmogi1caE1bdKB14Jl4lxgeWJy07YpW9qCyf+0nRiUG+rbwXy8sJTWuLy
# Rp3suO98cig33ktsxj5LOUpVXyf0uV74pmE4ZM3gDrXYRer1Gff1teIUniFwOABD
# 9SaDKbHi9xNjJ6tTlFvhfTk9Tt/WKW+OB7o4zTDqCw+xUE300AxUf7yo7vEvZULS
# cvBWQ7vrxIfRuV6Sq+E7+cseMQAZaJgNV0C0Ua/9xDeHTaTB8USgZocaGaWwMxxQ
# 00YpgOTBMO2CNKvzLyY7sYtkQ65M3bZndetoAd+jajVGKu2ZG11tLM76aPuQg/Zd
# wRrodTEPSGko75U54pzE/VyolTzUSuNnueCNMiFtVIL0a+hLR5d62b8vD3FwKJKF
# 3S55WY0OaEFeIyqM5znpRAutfTF8YyRMMT1OS8GRWGZkHc6QQ7qeaqUfJj89tces
# LA==
# SIG # End signature block
