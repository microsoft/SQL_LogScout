
#=======================================Globals =====================================
[string]$global:full_log_file_path = ""
[System.IO.StreamWriter]$global:logstream
$global:logbuffer = @()

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

    if ($MessageType -eq "System.Collections.Generic.List[System.Object]")
    {
        foreach ($item in $Message) {
            
            [String]$itemType = $item.GetType()
            
            #if item is a list we recurse
            #if not we cast to string and concatenate
            if($itemType -eq "System.Collections.Generic.List[System.Object]")
            {
                $strMessage += (Format-LogMessage($item)) + " "
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
    [string]$LogFileName = "##SQLLOGSCOUT.LOG"

    )

    #Safe to call Write-LogDebug because we will buffer the log entries while log is not initialized
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try
    {
        # if $global:logstream does not exists it means the log has not been initialized yet
        if ( -not(Get-Variable -Name logstream -Scope global -ErrorAction SilentlyContinue) ){
            
            #$error_folder = $global:internal_output_folder # moved to be passed into $LogFilePath parameter when calling from SQLLogScout.ps1
            $full_log_file_path = $LogFilePath + $LogFileName
            
            #create a new folder if not already there - TODO: perhaps check if there Test-Path(), and only then create a new one
            New-Item -Path $LogFilePath -ItemType Directory -Force | out-null 
            
            #create the file and keep a reference to StreamWriter
            $global:logstream = [System.IO.StreamWriter]::new( $LogFilePath + $LogFileName, $false, [System.Text.Encoding]::ASCII)
            
            #add initial message
            Write-LogInformation "Initializing log $full_log_file_path"
    
            #if we buffered log messages while log was not initialized, now we need to write them
            if ($null -ne $global:logbuffer){
                foreach ($Message in $global:logbuffer) {
                    $global:logstream.WriteLine([String]$Message)
                }
                $global:logstream.Flush()
            }
        } else { #if the log has already been initialized then throw an error
            Write-LogError "Attempt to initialize log already initialized!"
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
        [String]$strMessage = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
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
            #if ($null -eq $global:logbuffer){
            #    $global:logbuffer = @()
            #}

            $global:logbuffer += ,$strMessage
        }

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
