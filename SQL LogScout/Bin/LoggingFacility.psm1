$CommonFuncModule = (Get-Module -Name CommonFunctions).Name

if ($CommonFuncModule -ne "CommonFunctions")
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

if($null -eq $global:EnvTempVarFullPath) 
{
    $global:EnvTempVarFullPath = $Env:TEMP
}



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
            Write-LogDebug "Pruning older SQL LogScout DEBUG Logs in '$global:EnvTempVarFullPath'" -DebugLogLevel 1
            $LogFileName = ($LogFileName -replace "_DEBUG.LOG", ("_DEBUG_*.LOG"))
            $FilesToDelete = (Get-ChildItem -Path ($global:EnvTempVarFullPath + "\" + $LogFileName) | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip 9)
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
            $LogFileName = ($LogFileName -replace "_DEBUG_\*.LOG", ("_DEBUG_" + @(Get-Date -Format  "yyyyMMddTHHmmssffff") + ".LOG"))
            
            # create the long-term debug log and keep a reference to it
            $full_log_file_path = $global:EnvTempVarFullPath + "\" + $LogFileName
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
# MIIr5wYJKoZIhvcNAQcCoIIr2DCCK9QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCa3CkfAjxUVPmt
# dJjWn4CQts5GANDSa57K+a8t/2cHl6CCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
# D0nu2y38AAIAAAINMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzA5MzBaFw0yNjA0MjYyMzE5MzBaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCpj9ry6z6v08TIeKoxS2+5c928SwYKDXCyPWZHpm3xIHTqBBmlTM1GO7X4
# ap5jj/wroH7TzukJtfLR6Z4rBkjdlocHYJ2qU7ggik1FDeVL1uMnl5fPAB0ETjqt
# rk3Lt2xT27XUoNlKfnFcnmVpIaZ6fnSAi2liEhbHqce5qEJbGwv6FiliSJzkmeTK
# 6YoQQ4jq0kK9ToBGMmRiLKZXTO1SCAa7B4+96EMK3yKIXnBMdnKhWewBsU+t1LHW
# vB8jt8poBYSg5+91Faf9oFDvl5+BFWVbJ9+mYWbOzJ9/ZX1J4yvUoZChaykKGaTl
# k51DUoZymsBuatWbJsGzo0d43gMLAgMBAAGjggWKMIIFhjApBgkrBgEEAYI3FQoE
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
# aG9yaXR5MB0GA1UdDgQWBBS6kl+vZengaA7Cc8nJtd6sYRNA3jAOBgNVHQ8BAf8E
# BAMCB4AwRQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEWMBQGA1UEBRMNMjM2MTY3KzUwNjA0MjCCAeYGA1UdHwSCAd0wggHZMIIB
# 1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpaW5mcmEvQ1JM
# L0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwxLmFtZS5nYmwv
# Y3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwyLmFtZS5n
# YmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwzLmFt
# ZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmw0
# LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGgb1sZGFwOi8v
# L0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQS0lDU0NBMDEsQ049Q0RQ
# LENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZp
# Z3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0
# P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwHwYDVR0jBBgw
# FoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgwFgYKKwYBBAGCN1sBAQYI
# KwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAJKGB9zyDWN/9twAY6qCLnfDCKc/
# PuXoCYI5Snobtv15QHAJwwBJ7mr907EmcwECzMnK2M2auU/OUHjdXYUOG5TV5L7W
# xvf0xBqluWldZjvnv2L4mANIOk18KgcSmlhdVHT8AdehHXSs7NMG2di0cPzY+4Ol
# 2EJ3nw2JSZimBQdRcoZxDjoCGFmHV8lOHpO2wfhacq0T5NK15yQqXEdT+iRivdhd
# i/n26SOuPDa6Y/cCKca3CQloCQ1K6NUzt+P6E8GW+FtvcLza5dAWjJLVvfemwVyl
# JFdnqejZPbYBRdNefyLZjFsRTBaxORl6XG3kiz2t6xeFLLRTJgPPATx1S7Awggjo
# MIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0GCSqGSIb3DQEBCwUAMDwx
# EzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxEDAOBgNV
# BAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYwNTIxMTg1NDE0WjBBMRMw
# EQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQD
# EwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDJ
# mlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL9rNHnHDGfJgeuRIYO1LY
# /1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc411WxA+Pv2rteAcz0eHM
# H36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaCIIWBXyEchv+sM9eKDsUO
# LdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8pXirIYOgM770CYOiZrcKH
# K7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p/6fksgEILptOKhx9c+ia
# piNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkrBgEEAYI3FQEEBQIDAgAC
# MCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMALI38/RzAdBgNVHQ4EFgQU
# llGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfwwgfkGBysGAQUCAwUGCCsG
# AQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYBBAGCNxUGBgorBgEEAYI3
# CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgCAgYKKwYBBAGCN0ABAQYL
# KwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcVBQYKKwYBBAGCNxQCAgYK
# KwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEGCisGAQQBgjdbAgEGCisG
# AQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEGCisGAQQBgjdbBAIwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwNp4x1AdEJCygwggFoBgNV
# HR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDovL2NybDIuYW1lLmdibC9j
# cmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL2FtZXJvb3Qu
# Y3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVyb290LmNybIaBqmxkYXA6
# Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPUFNRSxE
# Qz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNz
# PWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUHAQEEggGdMIIBmTBHBggr
# BgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NlcnRz
# L0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwyLmFt
# ZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6
# Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUH
# MAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQw
# gaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290LENOPUFJQSxDTj1QdWJs
# aWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9u
# LERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29iamVjdENsYXNzPWNl
# cnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQELBQADggIBAFAQI7dPD+jf
# XtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTHb8BDfRN+AD0YEmeDB5HK
# QoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a/752hMIn+L4ZuyxVeSBp
# fwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9zAh9yRKKls2bziPEnxeO
# ZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAmn3WCPWNFC1YTIIHw/mD2
# cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtzyb7fbNS1dE740re0COE6
# 7YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjFK1yMw4Ni5fMabcgmzRvS
# jAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bzMzsikuDW9xH10graZzSm
# PjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIzJ6Q9G3NPCB+7KwX0OQmK
# yv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/ywO6SYSreVW+5Y0mzJutn
# BC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEISRtShDZbuYymynY1un+Ry
# fiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZzzCCGcsCAQEwWDBBMRMwEQYKCZIm
# iZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQDEwxBTUUg
# Q1MgQ0EgMDECEzYAAAIN4oQPSe7bLfwAAgAAAg0wDQYJYIZIAWUDBAIBBQCgga4w
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJrwLUp7Yx5AVu3o8vpOb3QpcM1Ed33x
# E5dNvGOWToy/MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# Z9YqG/B3ZGy4R60um+owfmTOBN9CeSOuuInRiMH9Vct9Av/nptN7h4mj37NWOm6z
# SUvSTeYnGBdabUJCdfCCJG9onhcJURPJ4TPWXx2wVhmbTzufw3cOQFOuFuOutZol
# fzk4udhab3hL16rX/1hCKiNz7bLKIa98W7c8UYegmkQcNbxG5xLm/P0bV5oAWgkI
# sO36P8u1X2Pr5URVZ4cKVpFLjvsHU6ZK2YitX0KO1yiNppiiNcMxLYXlE5T33u96
# q2toqSkkUeTesJDNuyP85EBVjKAp6PfGG6hKYmlIP2djrPdI7/c/4ynerYVAoYez
# LshDxN3LVG3KhiDvwGZMu6GCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCCF38GCSqG
# SIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCBzAgaImTUtXXRqe4DILQZhjoSxV92PIBXTbbzackpy4AIGaW+QihzkGBMyMDI2
# MDIwNDE2MzUyNy40ODFaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHtMIIH
# IDCCBQigAwIBAgITMwAAAg4syyh9lSB1YwABAAACDjANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQzMDNaFw0y
# NjA0MjIxOTQzMDNaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQCs5t7iRtXt0hbeo9ME78ZYjIo3saQuWMBFQ7X4s9vooYRABTOf
# 2poTHatx+EwnBUGB1V2t/E6MwsQNmY5XpM/75aCrZdxAnrV9o4Tu5sBepbbfehsr
# OWRBIGoJE6PtWod1CrFehm1diz3jY3H8iFrh7nqefniZ1SnbcWPMyNIxuGFzpQiD
# A+E5YS33meMqaXwhdb01Cluymh/3EKvknj4dIpQZEWOPM3jxbRVAYN5J2tOrYkJc
# dDx0l02V/NYd1qkvUBgPxrKviq5kz7E6AbOifCDSMBgcn/X7RQw630Qkzqhp0kDU
# 2qei/ao9IHmuuReXEjnjpgTsr4Ab33ICAKMYxOQe+n5wqEVcE9OTyhmWZJS5AnWU
# Tniok4mgwONBWQ1DLOGFkZwXT334IPCqd4/3/Ld/ItizistyUZYsml/C4ZhdALbv
# fYwzv31Oxf8NTmV5IGxWdHnk2Hhh4bnzTKosEaDrJvQMiQ+loojM7f5bgdyBBnYQ
# Bm5+/iJsxw8k227zF2jbNI+Ows8HLeZGt8t6uJ2eVjND1B0YtgsBP0csBlnnI+4+
# dvLYRt0cAqw6PiYSz5FSZcbpi0xdAH/jd3dzyGArbyLuo69HugfGEEb/sM07rcoP
# 1o3cZ8eWMb4+MIB8euOb5DVPDnEcFi4NDukYM91g1Dt/qIek+rtE88VS8QIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFIVxRGlSEZE+1ESK6UGI7YNcEIjbMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQB14L2TL+L8OXLxnGSal2h30mZ7FsBFooiYkUVOY05F
# 9pnwPTVufEDGWEpNNy2OfaUHWIOoQ/9/rjwO0hS2SpB0BzMAk2gyz92NGWOpWbpB
# dMvrrRDpiWZi/uLS4ZGdRn3P2DccYmlkNP+vaRAXvnv+mp27KgI79mJ9hGyCQbvt
# MIjkbYoLqK7sF7Wahn9rLjX1y5QJL4lvEy3QmA9KRBj56cEv/lAvzDq7eSiqRq/p
# Cyqyc8uzmQ8SeKWyWu6DjUA9vi84QsmLjqPGCnH4cPyg+t95RpW+73snhew1iCV+
# wXu2RxMnWg7EsD5eLkJHLszUIPd+XClD+FTvV03GfrDDfk+45flH/eKRZc3MUZtn
# hLJjPwv3KoKDScW4iV6SbCRycYPkqoWBrHf7SvDA7GrH2UOtz1Wa1k27sdZgpG6/
# c9CqKI8CX5vgaa+A7oYHb4ZBj7S8u8sgxwWK7HgWDRByOH3CiJu4LJ8h3TiRkRAr
# mHRp0lbNf1iAKuL886IKE912v0yq55t8jMxjBU7uoLsrYVIoKkzh+sAkgkpGOoZL
# 14+dlxVM91Bavza4kODTUlwzb+SpXsSqVx8nuB6qhUy7pqpgww1q4SNhAxFnFxsx
# iTlaoL75GNxPR605lJ2WXehtEi7/+YfJqvH+vnqcpqCjyQ9hNaVzuOEHX4Myuqcj
# wjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
# BQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNV
# BAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4X
# DTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM
# 57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm
# 95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzB
# RMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBb
# fowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCO
# Mcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYw
# XE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW
# /aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/w
# EPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPK
# Z6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2
# BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfH
# CBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYB
# BAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8v
# BO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEF
# BQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBW
# BgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUH
# AQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# L2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsF
# AAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518Jx
# Nj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+
# iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2
# pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefw
# C2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7
# T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFO
# Ry3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhL
# mm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3L
# wUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5
# m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE
# 0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNQMIICOAIB
# ATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOjg5MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBK6HY/ZWLn
# OcMEQsjkDAoB/JZWCKCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S3S7TAiGA8yMDI2MDIwNDE0MTUwOVoYDzIw
# MjYwMjA1MTQxNTA5WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDtLdLtAgEAMAoC
# AQACAhnNAgH/MAcCAQACAhNcMAoCBQDtLyRtAgEAMDYGCisGAQQBhFkKBAIxKDAm
# MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcN
# AQELBQADggEBALgXTSEo42wjLxYsZSWpgZvj4tT0qTLhNHOY6fkXroQhH4KfqCBn
# QoJ81gOjjSS7L7DMC0766Q31OevwZvV/6lSH5qgjPUx1ejN8kttL6PjF8Q6+96Ww
# hh/93xunj7EOKbZMDblDZzZja0JtavoUQ/wjaVvE4KT4KIzzBla+s1sUZvCxLlX0
# /PNpd/uPLLYqfvLOLRCrgMGF5kCyskfmHEOyhFI9HJ2ZcmUThT0J3UfhM393cOrJ
# 8vULfDKmpnxw46sRdxGouezb77G3eehWZ4O7lTMn5EDqym7WvTjmQ9jL5oYy5wUU
# /Ew6AIV/aANtPGb0Euk8pIZBq3bUt8T9PMYxggQNMIIECQIBATCBkzB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAg4syyh9lSB1YwABAAACDjANBglg
# hkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
# SIb3DQEJBDEiBCBgKTj11fnN4Z376PQnbiRBjB3KnfIcSRjsS/KiUOOcJzCB+gYL
# KoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIAF0HXMl8OmBkK267mxobKSihwOdP0eU
# NXQMypPzTxKGMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAAIOLMsofZUgdWMAAQAAAg4wIgQgrb4hmZtEY3u7RJP6/zdCTkUUGMjjQQuY
# B2lFj8o9V+cwDQYJKoZIhvcNAQELBQAEggIAmSaXMNeX36tUP5X40p8/JKMpY90L
# dQoFvE+B19juIT8zJqiHCc/IKLxizsR8Km+3KfovGWgBNWOmnzCIiAxpPCL7ZSE9
# jBX05oZxoYHX7SjlfpwNypdsr0qDdpKH5Uo/qBcLDieImtBDvjKA64BFEfYKXSg/
# /4AATYMX1oVvb1Y+PWeKuINW0914KmJGG4Pbf3w1vFEdo6UfnhIpHYLC6gSHjSHI
# KGmYs14kbV71/akhyYzizKXKywCmKfJLAwADhEH3HDdmiAvpjTpMJ3+ImCi/P6S6
# brFoUuY4lcypq2vXfJmhpXSglU9gytF1jHtpeuG3aKiIuRVt3jWVNTvuQirpK8ae
# ak2JVzBs9wNT11c7avAqqvDQmfMmi/5LnCVHtvo+5kwVHwO24B+6z9jKxqj6CY41
# f9lbdBV8EWDitFUHPrn0V02fI9bgOauuffGz4cQDdxjkw7o362guMAzMO+F0aU9n
# e+jmoxJ4RE3uEbXQjHzDf/DMPBn/RhH47HFNbcym4HbgzL54/UbtDe+tRrkh5UUC
# qfDLU1oUfdBxjWFudB69lmRHqAFe33ouJqiuWy/2W+FmVvhZaoNo4nEZ1q1NkdIw
# ++k/jAF89BNPgBAQQRTtEDCKohu9AEX+MoUFennuKSefyKdhNws1+2OarVYl+FqJ
# VKnkvRg+t0exdOI=
# SIG # End signature block
