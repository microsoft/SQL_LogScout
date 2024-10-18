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
    [string] $Scenarios = "All",

    [Parameter(Position=5)]
    [double] $RunDuration = 3

)

#load common functions and logging facility modules
[string]$parentLocation =  (Get-Item (Get-Location)).Parent.FullName 
Import-Module -Name ($parentLocation + "\CommonFunctions.psm1")
Import-Module -Name ($parentLocation + "\LoggingFacility.psm1")



function CreateTestingInfrastructureDir() 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2

    $present_directory = Convert-Path -Path $PSScriptRoot   #this gets the current directory called \TestingInfrastructure
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

    Write-Host "Testing Output Folder: $TestingOutputFolder"

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
    New-Item -ItemType "File" -Path $TestingOutputFolder -Name $SummaryFilename | out-null 

    #create the full path to summary file
    $SummaryOutputFilename = ($TestingOutputFolder + "\" + $SummaryFilename)
    
    # append date to file
    Write-Output "                      $(Get-Date)"   |Out-File $SummaryOutputFilename -Append
    
    
    [int] $TestCount = 0
    $temp_return_val = 0
    $return_val = 0

    #Run Tests and send results to a summary file 

    # Individual Scenarios
    if ($Scenarios -in ("Basic", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic"          -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunDuration $RunDuration
        
        #due to PS pipeline, Scenario_Test returns many things in an array. 
        #We need to get the last element of the array - the return value which is sent out last
        $return_val+=$temp_return_val[$temp_return_val.Count-1]

        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf"    -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("DetailedPerf", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf"   -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("Replication", "All"))
    {

        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Replication"    -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("AlwaysOn", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "AlwaysOn"       -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("NetworkTrace", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "NetworkTrace"   -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder 
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("Memory", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Memory"         -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder  -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("Setup", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Setup"          -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("BackupRestore", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "BackupRestore"  -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }   
    if ($Scenarios -in ("IO", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "IO"             -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf"      -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    #Process monitor is a bit different 
    if (($Scenarios -eq "ProcessMonitor") -or ($Scenarios -eq "All" -and $DoProcmonTest -eq $true))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "ProcessMonitor" -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder 
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    if ($Scenarios -in ("ServiceBrokerDBMail", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "ServiceBrokerDBMail"      -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    if ($Scenarios -in ("NeverEndingQuery", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "NeverEndingQuery"      -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    #combine Basic with a Network others
    if ($Scenarios -in ("Basic+NetworkTrace", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic+NetworkTrace"           -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }


    # combine scenario with NoBasic
    if ($Scenarios -in ("Basic+NoBasic", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic+NoBasic"           -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf+NoBasic", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+NoBasic"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("DetailedPerf+NoBasic", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+NoBasic"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("Replication+NoBasic", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Replication+NoBasic"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("AlwaysOn+NoBasic", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "AlwaysOn+NoBasic"        -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("Memory+NoBasic", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Memory+NoBasic"          -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("Setup+NoBasic", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Setup+NoBasic"           -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("BackupRestore+NoBasic", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "BackupRestore+NoBasic"   -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("IO+NoBasic", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "IO+NoBasic"              -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+NoBasic", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+NoBasic"       -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    # common combination scenarios
    if ($Scenarios -in ("GeneralPerf+Replication", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+Replication"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1][$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf+AlwaysOn", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+AlwaysOn"        -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1][$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf+IO", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+IO"              -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1][$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("GeneralPerf+NetworkTrace", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+NetworkTrace"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1][$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("DetailedPerf+AlwaysOn", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+AlwaysOn"       -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1][$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("DetailedPerf+IO", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+IO"             -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1][$temp_return_val.Count-1]
        $TestCount++
    }

    if ($Scenarios -in ("DetailedPerf+NetworkTrace", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+NetworkTrace"   -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+AlwaysOn", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+AlwaysOn"          -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+IO", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+IO"                -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+BackupRestore", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+BackupRestore"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+Memory", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+Memory"            -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }
    if ($Scenarios -in ("LightPerf+NetworkTrace", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+NetworkTrace"      -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    if ($Scenarios -in ("ServiceBrokerDBMail+GeneralPerf", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "ServiceBrokerDBMail+GeneralPerf"      -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    if ($Scenarios -in ("NeverEndingQuery+GeneralPerf", "All"))
    {
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "NeverEndingQuery+GeneralPerf"      -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    #Procmon scenario is a bit different needs the extra parameter $DoProcmonTest
    if (($Scenarios -eq "ProcessMonitor+Setup") -or ( $Scenarios -eq "All" -and $DoProcmonTest -eq $true))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "ProcessMonitor+Setup"        -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
    }

    if ($Scenarios -eq ("All"))
    {
        # test relative time parameters
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf+NoBasic"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -UseRelativeStartStopTime $true
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++

        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Memory+NoBasic"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -UseRelativeStartStopTime $true
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++

        #test repeat collection (continous)
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "IO+NoBasic"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -UseRelativeStartStopTime $true -RepeatCollections 3
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++


        # scenarios that don't make sense
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+DetailedPerf"    -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
        
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+LightPerf"       -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++
        
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+LightPerf"      -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++

        #stress tests
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+AlwaysOn+Replication+NetworkTrace+Memory+Setup+BackupRestore+IO"   -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++

        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic+GeneralPerf+DetailedPerf+AlwaysOn+Replication+NetworkTrace+Memory+Setup+BackupRestore+IO+LightPerf+ServiceBrokerDBMail+NeverEndingQuery"  -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder  -RunDuration $RunDuration
        $return_val+=$temp_return_val[$temp_return_val.Count-1]
        $TestCount++

    }

    # append test count to Summary file
    Write-Output "********************************************************************"   |Out-File $SummaryOutputFilename -Append
    Write-Output "Executed a total of $TestCount test(s)."   |Out-File $SummaryOutputFilename -Append
    
    # append overall test status to Summary file
    if ($return_val -eq 0)
    {
        Write-Output "OVERALL STATUS: All tests passed."   |Out-File $SummaryOutputFilename -Append
    }
    else
    {
        Write-Output "OVERALL STATUS: One or more tests failed."   |Out-File $SummaryOutputFilename -Append
    }

    #print the Summary.txt file in console
    Get-Content $SummaryOutputFilename

    #Launch the Summary.txt file for review
    Start-Process $SummaryOutputFilename

    #return the value of the last test
    #use exit so parent can handle the error in cmd prompt (%errorlevel%) or powershell ($LASTEXITCODE)
    # if ($return_val -ne 0) then the last test failed
    exit $return_val
}

catch {
    $error_msg = $PSItem.Exception.Message
    $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
    $error_offset = $PSItem.InvocationInfo.OffsetInLine
    $error_script = $PSItem.InvocationInfo.ScriptName
    Write-Error -Message "Function '$($MyInvocation.MyCommand)' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    
    exit 999
}