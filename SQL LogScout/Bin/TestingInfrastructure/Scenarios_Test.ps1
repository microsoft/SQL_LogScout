param
(
    #servername\instancename is an optional parameter
    [Parameter(Position=0)]
    [string] $ServerName = $env:COMPUTERNAME,
    
    [Parameter(Position=1,Mandatory=$true)]
    [string] $Scenarios = "WRONG_SCENARIO",

    [Parameter(Position=2,Mandatory=$true)]
    [string] $SummaryOutputFile,

    [Parameter(Position=3)]
    [string] $SqlNexusPath,

    [Parameter(Position=4)]
    [string] $SqlNexusDb,

    [Parameter(Position=5)]
    [string] $LogScoutOutputFolder,

    [Parameter(Position=6,Mandatory=$true)]
    [string] $RootFolder,

    [Parameter(Position=7)]
    [bool] $RunTSQLLoad = $false,

    [Parameter(Position=8)]
    [string] $DisableCtrlCasInput = "False"
)

$TSQLLoadModule = (Get-Module -Name TSQLLoadModule).Name

if ($TSQLLoadModule -ne "TSQLLoadModule")
    {
        Import-Module .\GenerateTSQLLoad.psm1
    }

$TSQLLoadCommonFunction = (Get-Module -Name CommonFunctions).Name

if ($TSQLLoadCommonFunction -ne "CommonFunctions")
    {
        #Since we are in bin and CommonFunctions is in root directory, we need to step out to import module
        #This is so we can use HandleCatchBlock
        $CurrentPath = Get-Location
        [string]$CommonFunctionsModule = (Get-Item $CurrentPath).parent.FullName + "\CommonFunctions.psm1"
        Import-Module -Name $CommonFunctionsModule
    }




Write-Output "" | Out-File $SummaryOutputFile -Append
Write-Output "" | Out-File $SummaryOutputFile -Append
Write-Output "********************************************************************" | Out-File $SummaryOutputFile -Append
Write-Output "                      Starting '$Scenarios' test                    " | Out-File $SummaryOutputFile -Append     
Write-Output "                      $(Get-Date -Format "dd MMMM yyyy HH:mm:ss")   " | Out-File $SummaryOutputFile -Append     
Write-Output "                      Server Name: $ServerName                      " | Out-File $SummaryOutputFile -Append
Write-Output "********************************************************************" | Out-File $SummaryOutputFile -Append

Write-Output "********************************************************************" 
Write-Output "                      Starting '$Scenarios' test"                     
Write-Output "                      $(Get-Date -Format "dd MMMM yyyy HH:mm:ss")    "
Write-Output "                      Server Name: $ServerName                      " 
Write-Output "********************************************************************" 

[bool] $script_ret = $true
[int] $return_val = 0

# validate root folder 
$PathFound = Test-Path -Path $RootFolder 
if ($PathFound -eq $false)
{
    Write-Host "Invalid Root directory for testing. Exiting."
    $return_val = 4
    return $return_val
}

# start and stop times for LogScout execution

if ($Scenarios -match "NeverEndingQuery"){
    # NeverEndingQuery scenario needs 60 seconds to run before test starts so we can accumulate 60 seconds of CPU time
    $StartTime = (Get-Date).AddSeconds(60).ToString("yyyy-MM-dd HH:mm:ss")
}
else {
    $StartTime = (Get-Date).AddSeconds(20).ToString("yyyy-MM-dd HH:mm:ss")
}

# stop time is 3 minutes from start time. This is to ensure that we have enough data to analyze 
# also ensures that on some machines where the test runs longer, we don't lose logs due to the test ending prematurely
$StopTime = (Get-Date).AddMinutes(3).ToString("yyyy-MM-dd HH:mm:ss")

# start TSQLLoad execution
if ($RunTSQLLoad -eq $true)
{
    Initialize-TSQLLoadLog -Scenario $Scenarios

    TSQLLoadInsertsAndSelectFunction -ServerName $ServerName
}


##execute a regular SQL LogScout data collection from root folder
Write-Host "Starting LogScout"

#build command line and arguments
$LogScoutCmd = "`"" + $RootFolder  + "\SQL_LogScout.cmd" + "`"" 
$argument_list =  $Scenarios + " `"" + $ServerName + "`" UsePresentDir DeleteDefaultFolder `"" + $StartTime.ToString() + "`" `"" + $StopTime.ToString() + "`" Quiet " + $DisableCtrlCasInput

#execute LogScout
Start-Process -FilePath $LogScoutCmd -ArgumentList $argument_list -Wait -NoNewWindow

Write-Host "LogScoutCmd: $LogScoutCmd"
Write-Host "Argument_list: $argument_list"

if ($RunTSQLLoad -eq $true)
{

    Write-Host "Verifying T-SQL workload finished"
    TSQLLoadCheckWorkloadExited
}

#run file validation test

$script_ret = ./FilecountandtypeValidation.ps1 -SummaryOutputFile $SummaryOutputFile 2> .\##TestFailures.LOG
..\StdErrorOutputHandling.ps1 -FileName .\##TestFailures.LOG

if ($script_ret -eq $false)
{
    #FilecountandtypeValidation test failed, return a unique, non-zero value
    $return_val = 1
}

#check SQL_LOGSCOUT_DEBUG log for errors
. .\LogParsing.ps1

# $LogNamePattern defaults to "..\output\internal\##SQLLOGSCOUT_DEBUG.LOG"
# $SummaryFilename defaults to ".\output\SUMMARY.TXT"
# $DetailedFilename defaults to ".\output\DETAILED.TXT"
$script_ret = Search-Log -LogNamePattern ($RootFolder + "\output\internal\##SQLLOGSCOUT_DEBUG.LOG")

if ($script_ret -eq $false)
{
    #Search-Log test failed, return a unique, non-zero value
    $return_val = 2
}

#run SQLNexus import and table verficiation test
$script_ret = .\SQLNexus_Test.ps1 -ServerName $ServerName -Scenarios $Scenarios -OutputFilename $SummaryOutputFile -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -SQLLogScoutRootFolder $RootFolder


if ($script_ret -eq $false)
{
    #SQLNexus test failed, return a non-zero value
    $return_val = 3
}

Write-Host "Scenario_Test return value: $return_val" | Out-Null
return $return_val



