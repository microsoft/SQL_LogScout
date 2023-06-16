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
    [bool] $RunTSQLLoad = $false
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


# validate root folder 
$PathFound = Test-Path -Path $RootFolder 
if ($PathFound -eq $false)
{
    Write-Host "Invalid Root directory for testing. Exiting."
    exit
}


$StartTime = (Get-Date).AddSeconds(20)
$StopTime = (Get-Date).AddMinutes(2)

if ($RunTSQLLoad -eq $true)
{
    Initialize-TSQLLoadLog -Scenario $Scenarios

    TSQLLoadInsertsAndSelectFunction -ServerName $ServerName
}

##execute a regular SQL LogScout data collection from root folder
Write-Host "Starting LogScout"
&($RootFolder + "\SQL_LogScout.cmd") $Scenarios $ServerName "UsePresentDir" "DeleteDefaultFolder" $StartTime $StopTime "Quiet"

if ($RunTSQLLoad -eq $true)
{

    Write-Host "Verifying workload finished"
    TSQLLoadCheckWorkloadExited
}

#run file validation test

./FilecountandtypeValidation.ps1 -SummaryOutputFile $SummaryOutputFile 2> .\##TestFailures.LOG
..\StdErrorOutputHandling.ps1 -FileName .\##TestFailures.LOG

#check SQL_LOGSCOUT_DEBUG log for errors
. .\LogParsing.ps1

# $LogNamePattern defaults to "..\output\internal\##SQLLOGSCOUT_DEBUG.LOG"
# $SummaryFilename defaults to ".\output\SUMMARY.TXT"
# $DetailedFilename defaults to ".\output\DETAILED.TXT"
Search-Log -LogNamePattern ($RootFolder + "\output\internal\##SQLLOGSCOUT_DEBUG.LOG")


#run SQLNexus import and table verficiation test
.\SQLNexus_Test.ps1 -ServerName $ServerName -Scenarios $Scenarios -OutputFilename $SummaryOutputFile -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -SQLLogScoutRootFolder $RootFolder




