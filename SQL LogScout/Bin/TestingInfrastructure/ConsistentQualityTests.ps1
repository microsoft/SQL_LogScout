param
(
    #servername\instancename is an optional parameter since there is code that auto-discovers instances
    [Parameter(Position=0)]
    [string] $ServerName = $env:COMPUTERNAME,

    [Parameter(Position=1)]
    [string] $SqlNexusPath ,

    [Parameter(Position=2)]
    [string] $SqlNexusDb ,

    [Parameter(Position=3)]
    [bool] $DoProcmonTest = $false,

    [Parameter(Position=4)]
    [string] $Scenarios = "All"


)

Import-Module -Name ..\CommonFunctions.psm1
Import-Module -Name ..\LoggingFacility.psm1

function CreateTestingInfrastructureDir() 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2

    $present_directory = Convert-Path -Path "."   #this gets the current directory called \TestingInfrastructure
    $TestingInfrastructureFolder = $present_directory + "\Output\"
    New-Item -Path $TestingInfrastructureFolder -ItemType Directory -Force | out-null 
    
    return $TestingInfrastructureFolder
}

function Get-LogScoutRootFolder 
{
    # go back to SQL LogScout root folder
    $root_folder = (Get-Item (Get-Location)).Parent.Parent.FullName

    return $root_folder
}


try 
{

    #create the output directory
    $SummaryFilename = 'Summary.txt'
    $TestingOutputFolder = CreateTestingInfrastructureDir
    $root_folder = Get-LogScoutRootFolder
    $LogScoutOutputFolder = $root_folder + "\Output" # go back to SQL LogScout root folder and create \Output

    #check for existence of Summary.txt and if there, rename it
    $LatestSummaryFile = Get-ChildItem -Path $TestingOutputFolder -Filter $SummaryFilename -Recurse |  Sort-Object LastWriteTime -Descending | Select-Object -First 1 | %{$_.FullName} 

    if ($true -eq (Test-Path -Path ($TestingOutputFolder + "\" + $SummaryFilename) ))
    {
        $LatestSummaryFile = Get-ChildItem -Path $TestingOutputFolder -Filter $SummaryFilename -Recurse |  Sort-Object LastWriteTime -Descending | Select-Object -First 1 | %{$_.FullName} 
        $date_summary = ( get-date ).ToString('yyyyMMddhhmmss');
        $ReportPathSummary = $date_summary +'_Old_Summary.txt' 
        Rename-Item -Path $LatestSummaryFile -NewName $ReportPathSummary
    }

    #create new Summary.txt
    New-Item -itemType File -Path $TestingOutputFolder -Name $SummaryFilename | out-null 

    #create the full path to summary file
    $SummaryOutputFilename = ($TestingOutputFolder + "\" + $SummaryFilename)
    
    # append date to file
    Write-Output "                      $(Get-Date)"   |Out-File $SummaryOutputFilename -Append
    
    
    [int] $TestCount = 0

    #Run Tests and send results to a summary file 

    # Individual Scenarios
    if ($Scenarios -in ("Basic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic"          -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf"    -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("DetailedPerf", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf"   -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true  
        $TestCount++
    }
    if ($Scenarios -in ("Replication", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Replication"    -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder
        $TestCount++
    }
    if ($Scenarios -in ("AlwaysOn", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "AlwaysOn"       -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("NetworkTrace", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "NetworkTrace"   -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        $TestCount++
    }
    if ($Scenarios -in ("Memory", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Memory"         -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("Setup", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Setup"          -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder
        $TestCount++
    }
    if ($Scenarios -in ("BackupRestore", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "BackupRestore"  -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder
        $TestCount++
    }   
    if ($Scenarios -in ("IO", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "IO"             -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf"      -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }

    #Process monitor is a bit different 
    if (($Scenarios -eq "ProcessMonitor") -or ($Scenarios -eq "All" -and $DoProcmonTest -eq $true))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "ProcessMonitor" -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        $TestCount++
    }

    #combine Basic with a Network others
    if ($Scenarios -in ("Basic+NetworkTrace", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic+NetworkTrace"           -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        $TestCount++
    }


    # combine scenario with NoBasic
    if ($Scenarios -in ("Basic+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic+NoBasic"           -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+NoBasic"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("DetailedPerf+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+NoBasic"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("Replication+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Replication+NoBasic"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        $TestCount++
    }
    if ($Scenarios -in ("AlwaysOn+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "AlwaysOn+NoBasic"        -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("Memory+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Memory+NoBasic"          -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("Setup+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Setup+NoBasic"           -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        $TestCount++
    }
    if ($Scenarios -in ("BackupRestore+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "BackupRestore+NoBasic"   -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        $TestCount++
    }
    if ($Scenarios -in ("IO+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "IO+NoBasic"              -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+NoBasic", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+NoBasic"       -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }

    # common combination scenarios
    if ($Scenarios -in ("GeneralPerf+Replication", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+Replication"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf+AlwaysOn", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+AlwaysOn"        -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf+IO", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+IO"              -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf+NetworkTrace", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+NetworkTrace"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("DetailedPerf+AlwaysOn", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+AlwaysOn"       -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("DetailedPerf+IO", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+IO"             -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }

    if ($Scenarios -in ("DetailedPerf+NetworkTrace", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+NetworkTrace"   -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+AlwaysOn", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+AlwaysOn"          -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+IO", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+IO"                -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+BackupRestore", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+BackupRestore"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+Memory", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+Memory"            -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+NetworkTrace", "All"))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+NetworkTrace"      -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true
        $TestCount++
    }


    #Procmon scenario is a bit different needs the extra parameter $DoProcmonTest
    if (($Scenarios -eq "ProcessMonitor+Setup") -or ( $Scenarios -eq "All" -and $DoProcmonTest -eq $true))
    {
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "ProcessMonitor+Setup"        -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        $TestCount++
    }

    if ($Scenarios -eq ("All"))
    {
        # scenarios that don't make sense
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+DetailedPerf"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+LightPerf"       -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+LightPerf"      -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder


        #stress tests
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+AlwaysOn+Replication+NetworkTrace+Memory+Setup+BackupRestore+IO"   -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder
        .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic+GeneralPerf+DetailedPerf+AlwaysOn+Replication+NetworkTrace+Memory+Setup+BackupRestore+IO+LightPerf"  -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder

        $TestCount = $TestCount + 5
    }

    # append test count to Summary file
    Write-Output "********************************************************************"   |Out-File $SummaryOutputFilename -Append
    Write-Output "Executed a total of $TestCount test(s)."   |Out-File $SummaryOutputFilename -Append

    #print the Summary.txt file in console
    Get-Content $SummaryOutputFilename

    #Launch the Summary.txt file for review
    Start-Process $SummaryOutputFilename
}

catch {
    $error_msg = $PSItem.Exception.Message
    $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
    $error_offset = $PSItem.InvocationInfo.OffsetInLine
    $error_script = $PSItem.InvocationInfo.ScriptName
    Write-LogError "Function '$($MyInvocation.MyCommand)' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    

}