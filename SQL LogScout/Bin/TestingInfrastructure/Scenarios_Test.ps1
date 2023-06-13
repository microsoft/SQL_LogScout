
param
(
    #servername\instnacename is an optional parameter
    [Parameter(Position=0)]
    [string] $ServerName = $env:COMPUTERNAME,
    
    [Parameter(Position=1,Mandatory=$true)]
    [string] $Scenarios = "WRONG_SCENARIO",

    [Parameter(Position=2,Mandatory=$true)]
    [string] $OutputFilename,

    [Parameter(Position=3)]
    [string] $sqlnexuspath ,

    [Parameter(Position=4)]
    [string] $sqlnexusDB,

    [Parameter(Position=5)]
    [string] $logfolder

)
Write-Output "" | Out-File $OutputFilename -Append
Write-Output "" | Out-File $OutputFilename -Append
Write-Output "********************************************************************" | Out-File $OutputFilename -Append
Write-Output "                      Starting '$Scenarios' test                    " | Out-File $OutputFilename -Append     
Write-Output "                      $(Get-Date -Format "dd MMMM yyyy HH:mm:ss")   " | Out-File $OutputFilename -Append     
Write-Output "                      Server Name: $ServerName                      " | Out-File $OutputFilename -Append
Write-Output "********************************************************************" | Out-File $OutputFilename -Append

Write-Output "********************************************************************" 
Write-Output "                      Starting '$Scenarios' test"                     
Write-Output "                      $(Get-Date -Format "dd MMMM yyyy HH:mm:ss")    "
Write-Output "                      Server Name: $ServerName                      " 
Write-Output "********************************************************************" 


$StartTime = (Get-Date).AddSeconds(20)
$StopTime = (Get-Date).AddMinutes(2)

..\SQL_LogScout $Scenarios $ServerName "UsePresentDir" "DeleteDefaultFolder" $StartTime $StopTime "Quiet"

#run file validation test
.\RunTests.bat

#check SQL_LOGSCOUT_DEBUG log for errors
. .\LogParsing.ps1

# $LogNamePattern defaults to "..\output\internal\##SQLLOGSCOUT_DEBUG.LOG"
# $SummaryFilename defaults to ".\output\SUMMARY.TXT"
# $DetailedFilename defaults to ".\output\DETAILED.TXT"
Search-Log # there should be no need to specify parmeters here due to defaults, but we can review later as needed
# Check the collected log is ok to import in SQLNexus

#run SQLNexus import and table verficiation test
.\SQLNexus_Test.ps1 -ServerName $ServerName -Scenarios $Scenarios -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder

