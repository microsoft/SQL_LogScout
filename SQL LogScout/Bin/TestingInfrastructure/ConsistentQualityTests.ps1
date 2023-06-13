param
(
    #servername\instancename is an optional parameter since there is code that auto-discovers instances
    [Parameter(Position=0)]
    [string] $ServerName = $env:COMPUTERNAME,

    [Parameter(Position=1)]
    [string] $sqlnexuspath ,

    [Parameter(Position=2)]
    [string] $sqlnexusDB ,

    [Parameter(Position=3)]
    [bool] $DoProcmonTest = $false

)
Import-Module -Name ..\LoggingFacility.psm1

try 
{

    function CreateTestingInfrastructureDir() 
    {
        Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2

        $present_directory = Convert-Path -Path "."   #this gets the current directory called \TestingInfrastructure
        $TestingInfrastructureFolder = $present_directory + "\output\"
        New-Item -Path $TestingInfrastructureFolder -ItemType Directory -Force | out-null 
        
        return $TestingInfrastructureFolder
    }


    #create the output directory
    $filename = 'Summary.txt'
    $TestingOutputFolder = CreateTestingInfrastructureDir
    $logfolder = (get-item $TestingOutputFolder).Parent.FullName # go back to 1 level up to infra folder
    $logfolder = (get-item $logfolder).Parent.FullName           # go back to SQL LogScout main folder
    $logfolder  = $logfolder + "\output"

    #check for existence of Summary.txt and if there, rename it
    $LatestSummaryFile = Get-ChildItem -Path $TestingOutputFolder -Filter $filename -Recurse |  Sort-Object LastWriteTime -Descending | Select-Object -First 1 | %{$_.FullName} 

    if ($true -eq (Test-Path -Path ($TestingOutputFolder + "\" + $filename) ))
    {
        $LatestSummaryFile = Get-ChildItem -Path $TestingOutputFolder -Filter $filename -Recurse |  Sort-Object LastWriteTime -Descending | Select-Object -First 1 | %{$_.FullName} 
        $date_summary = ( get-date ).ToString('yyyyMMddhhmmss');
        $ReportPathSummary = $date_summary +'_Old_Summary.txt' 
        Rename-Item -Path $LatestSummaryFile -NewName $ReportPathSummary
    }

    #create new Summary.txt
    New-Item -itemType File -Path $TestingOutputFolder -Name $filename | out-null 

    $OutputFilename = ($TestingOutputFolder + "\" + $filename)

    # append date to file
    Write-Output "                      $(Get-Date)"   |Out-File $OutputFilename -Append
    
    
    #RunAllTest.ps1 and send results to a summary file 

    # Individual Scenarios
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic"          -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf"    -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf"   -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder  
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Replication"    -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "AlwaysOn"       -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "NetworkTrace"   -OutputFilename $OutputFilename
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Memory"         -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Setup"          -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "BackupRestore"  -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "IO"             -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf"      -OutputFilename $OutputFilename -sqlnexuspath $sqlnexuspath -sqlnexusDB $sqlnexusDB -logfolder $logfolder


    if ($DoProcmonTest -eq $true)
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "ProcessMonitor" -OutputFilename $OutputFilename
    }

    # Test each parameter with various switches
    <#
    Example:
    SQL_LogScout.cmd GeneralPerf+AlwaysOn+BackupRestore DbSrv "d:\log" DeleteDefaultFolder "01-01-2000" "04-01-2021 17:00" Quiet
    SQL_LogScout.cmd GeneralPerf+AlwaysOn+BackupRestore DbSrv "UsePresentDir" DeleteDefaultFolder "01-01-2000" "04-01-2021 17:00" Quiet
    #>

    # combine scenario with NoBasic
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic+NoBasic"           -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+NoBasic"     -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+NoBasic"    -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Replication+NoBasic"     -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "AlwaysOn+NoBasic"       -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Memory+NoBasic"          -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Setup+NoBasic"           -OutputFilename $OutputFilename
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "BackupRestore+NoBasic"   -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "IO+NoBasic"              -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+NoBasic"       -OutputFilename $OutputFilename 


    # common combination scenarios
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+Replication"     -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+AlwaysOn"        -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+IO"              -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+NetworkTrace"    -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+AlwaysOn"       -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+IO"             -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+NetworkTrace"   -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+AlwaysOn"          -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+IO"                -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+BackupRestore"     -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+Memory"            -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+NetworkTrace"      -OutputFilename $OutputFilename


    if ($DoProcmonTest -eq $true)
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "ProcessMonitor+Setup"        -OutputFilename $OutputFilename
    }

    # scenarios that don't make sense
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+DetailedPerf"    -OutputFilename $OutputFilename
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+LightPerf"       -OutputFilename $OutputFilename
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+LightPerf"      -OutputFilename $OutputFilename


    #stress tests
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+AlwaysOn+Replication+NetworkTrace+Memory+Setup+BackupRestore+IO"   -OutputFilename $OutputFilename 
    .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic+GeneralPerf+DetailedPerf+AlwaysOn+Replication+NetworkTrace+Memory+Setup+BackupRestore+IO+LightPerf"  -OutputFilename $OutputFilename 

}

catch {
    $error_msg = $PSItem.Exception.Message
    $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
    $error_offset = $PSItem.InvocationInfo.OffsetInLine
    $error_script = $PSItem.InvocationInfo.ScriptName
    Write-LogError "Function '$($MyInvocation.MyCommand)' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    

}