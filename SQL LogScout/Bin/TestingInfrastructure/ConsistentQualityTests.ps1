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

function GetPortFromInstance {
    param (
        [string]$server
    )

    Write-Host "Testing GetPortFromInstance function with server: $server"

    try 
    {
        # Extract the instance name from the server string
        $instanceName = if ($server -match '\\') {
            $server.Split('\')[1]
        } else {
            'MSSQLSERVER'  # Default instance name
        }

        # Get all the registry keys where an instance name is present using "MSSQL" and Property like "(default)" to check TCP/IP Sockets
        $InstancesInReg = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue |
                    Where-Object {$_.Name -like '*MSSQL*' -and $_.Property -like "(default)"} |
                    Select-Object -ExpandProperty PSChildName

        if (-not $InstancesInReg) 
        {
            Write-Host "No SQL Server instances found in the registry."
            return $null
        }

        Write-Host "Found these instances in the registry: $InstancesInReg"

        # Go through each instance in the registry
        foreach ($InstKey in $InstancesInReg) 
        {
            # Extract the instance name from the reg key (e.g. get the part after the . in "MSSQL14.MYSQL2017")
            $RegInstanceName = $InstKey.Substring($InstKey.IndexOf(".") + 1)

            # Check if the instance name matches the one we are looking for
            if ($RegInstanceName -eq $instanceName) 
            {
                # Build the reg key in the form HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$InstKey\MSSQLServer\SuperSocketNetLib\Tcp
                $tcpKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$InstKey\MSSQLServer\SuperSocketNetLib\Tcp"

                Write-Host "TCP key for instance '$instanceName' is $tcpKey"

                # Check if the TCP key exists
                if (Test-Path -Path $tcpKey) 
                {
                    # Check if TCP/IP Sockets is enabled
                    $tcpEnabled = Get-ItemProperty -Path $tcpKey -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Enabled

                    # If enabled, go through ports
                    if ($tcpEnabled -eq "1") 
                    {
                        $Ports = Get-ItemProperty -Path "$tcpKey\IP*" -ErrorAction SilentlyContinue | Select-Object TcpPort, TcpDynamicPorts
                        foreach ($port in $Ports) 
                        {
                            # Skip if the port is not set (0 or null)
                            if (-not [string]::IsNullOrWhiteSpace($port.TcpDynamicPorts) -and $port.TcpDynamicPorts -gt 0) 
                            {
                                Write-Host "Port found: $($port.TcpDynamicPorts)"
                                return $port.TcpDynamicPorts
                            } 
                            elseif (-not [string]::IsNullOrWhiteSpace($port.TcpPort) -and $port.TcpPort -gt 0) {
                                Write-Host "Port found: $($port.TcpPort)"
                                return $port.TcpPort
                            }
                        }
                    } 
                    else 
                    {
                        Write-Host "TCP/IP Sockets is not enabled for instance $instanceName"
                        return $null
                    }
                }
            }
        }

        Write-Host "No matching instance found for server: $server"
        return $null
    } 
    catch 
    {
        Write-Host "Test failed with error: $_"
    }
}


# Main entry point

try 
{

    #create the output directory
    $SummaryFilename = 'Summary.txt'
    $TestingOutputFolder = CreateTestingInfrastructureDir
    $root_folder = Get-LogScoutRootFolder
    $LogScoutOutputFolder = $root_folder + "\Output" # go back to SQL LogScout root folder and create \Output

    Write-Host "Testing Output Folder: $TestingOutputFolder"

    #check for existence of Summary.txt and if there, rename it

    if ($true -eq (Test-Path -Path ($TestingOutputFolder + "\" + $SummaryFilename) ))
    {
        $LatestSummaryFile = Get-ChildItem -Path $TestingOutputFolder -Filter $SummaryFilename -Recurse |  Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object{$_.FullName} 
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
    if ($Scenarios -in ("Basic", "All"))
    {
        # Get the port number for the instance and use it as a connection string to test the Basic scenario and GetSQLInstanceNameByPortNo()
        $port = GetPortFromInstance -server $ServerName

        # If the port is found, run the Basic scenario with the port number. Else, skip the test
        if ($port) 
        {
            $temp_return_val = .\Scenarios_Test.ps1 -ServerName ("127.0.0.1,"+$port) -Scenarios "Basic"          -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunDuration $RunDuration
               
            #due to PS pipeline, Scenario_Test returns many things in an array. 
            #We need to get the last element of the array - the return value which is sent out last
            $return_val+=$temp_return_val[$temp_return_val.Count-1]
            
            $TestCount++
        }    
        
    }
    if ($Scenarios -in ("BasicAndFullText", "All"))
    {
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "Basic" -AdditionalOptionsEnabled "FullTextSearchLogs" -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunDuration $RunDuration
        
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
    if ($Scenarios -in ("LightPerfFileLock", "All"))
    {
        try 
        {
            
            $scriptFiles = ( 'SQLScript_AlwaysOnDiagScript',
                            'SQLScript_ChangeDataCapture',
                            'SQLScript_Change_Tracking',
                            'SQLScript_FullTextSearchMetadata',
                            'SQLScript_NeverEndingQuery_perfstats',
                            'SQLScript_Replication_Metadata_Collector',
                            'SQLScript_SSB_DbMail_Diag',
                            'SQLScript_xevent_AlwaysOn_Data_Movement',
                            'SQLScript_xevent_backup_restore',
                            'SQLScript_xevent_detailed',
                            'SQLScript_xevent_general',
                            'SQLScript_xevent_servicebroker_dbmail')


            # using the array of script files, pick a random script file to place a lock on it
            $randomIndex = Get-Random -Minimum 0 -Maximum $scriptFiles.Count
            $randomScriptFileSelected = $scriptFiles[$randomIndex]
            Write-Host "Selected random script file: '$randomScriptFileSelected' for LightPerfFileLock scenario."

            # Construct the full path to the script file
            $randomScriptFullPath = $root_folder + "\Bin\" + $randomScriptFileSelected + ".psm1"

            if (Test-Path -Path $randomScriptFullPath) 
            {
                # Create a file stream to exclusively lock the script file
                Write-Host "Locking script file: $randomScriptFullPath..." 
                $stream = [System.IO.File]::Open($randomScriptFullPath, 'Open', 'Read', 'None')
            } 
            else 
            {
                Write-Host "Random script file not found: $randomScriptFullPath"
            }

            $exclusionPattern = "because it is being used by another process. "
            # Run the LightPerfFileLock scenario with the locked script file            
            $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "LightPerf"      -SummaryOutputFile $SummaryOutputFilename -SqlNexusPath $SqlNexusPath -SqlNexusDb $SqlNexusDb -LogScoutOutputFolder $LogScoutOutputFolder -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration -excludePatterns $exclusionPattern
            $return_val+=$temp_return_val[$temp_return_val.Count-1]
            
        }
        catch 
        {
                Write-Host "LightPerfFileLock scenario failed with error: $_"
                $return_val = 1 # Set return value to indicate failure
        }
        finally 
        {
            Write-Host "LightPerfFileLock scenario completed. Releasing exclusive lock on file."
            $stream.Close()
            $TestCount++
        }
        
       
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
        #Run this scenario with a logscout.stop file to test that functionality -UseStopFile $true
        $temp_return_val =.\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "GeneralPerf+NoBasic"     -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration -UseStopFile $true
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
        # test the TrackCausality, NoClusterLogs,RedoTasksPerfStats options with -AdditionalOptionsEnabled
        $temp_return_val = .\Scenarios_Test.ps1 -ServerName $ServerName -Scenarios "DetailedPerf+AlwaysOn"       -SummaryOutputFile $SummaryOutputFilename -RootFolder $root_folder -RunTSQLLoad $true  -RunDuration $RunDuration -AdditionalOptionsEnabled "TrackCausality+NoClusterLogs+RedoTasksPerfStats"
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
# SIG # Begin signature block
# MIIsDwYJKoZIhvcNAQcCoIIsADCCK/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDnHnniCnUw1LhA
# Dby1p9WRQANcrdTqs9KaPUOLyAs72KCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
# oOn9X5/TAAIAAAIOMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzEyMDNaFw0yNjA0MjYyMzIyMDNaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCfrw9mbjhRpCz0Wh+dmWU4nlBbeiDkl5NfNWFA9NWUAfDcSAEtWiJTZLIB
# Vt+E5kjpxQfCeObdxk0aaPKmhkANla5kJ5egjmrttmGvsI/SPeeQ890j/QO4YI4g
# QWpXnt8EswtW6xzmRdMMP+CASyAYJ0oWQMVXXMNhBG9VBdrZe+L1+DzLawq42AWG
# NoKL6JdGg21P0W11MN1OtwrhubgTqEBkgYp7m1Bt4EeOxBz0GwZfPODbLVTblACS
# LmGlfEePEdVamqIUTTdsrAKG8NM/gGx010AiqAv6p2sCtSeZpvV7fkppLY9ajdm8
# Yc4Kf1KNI3U5ZNMdLIDz9fA5Q+ulAgMBAAGjggWZMIIFlTApBgkrBgEEAYI3FQoE
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
# aG9yaXR5MB0GA1UdDgQWBBSbKJrguVhFagj1tSbzFntHGtugCTAOBgNVHQ8BAf8E
# BAMCB4AwVAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjM2MTY3KzUwNjA1MjCCAeYG
# A1UdHwSCAd0wggHZMIIB1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5j
# b20vcGtpaW5mcmEvQ1JML0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6
# Ly9jcmwxLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0
# dHA6Ly9jcmwyLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyG
# MWh0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5j
# cmyGMWh0dHA6Ly9jcmw0LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgy
# KS5jcmyGgb1sZGFwOi8vL0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQ
# S0lDU0NBMDEsQ049Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNl
# cnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0
# ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9u
# UG9pbnQwHwYDVR0jBBgwFoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgw
# FgYKKwYBBAGCN1sBAQYIKwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAKaBh/B8
# 42UPFqNHP+m2mYSY80orKjPVnXEb+KlCoxL1Ikl2DfziE1PBZXtCDbYtvyMqC9Pj
# KvB8TNz71+CWrO0lqV2f0KITMmtXiCy+yThBqLYvUZrbrRzlXYv2lQmqWMy0OqrK
# TIdMza2iwUp2gdLnKzG7DQ8IcbguYXwwh+GzbeUjY9hEi7sX7dgVP4Ls1UQNkRqR
# FcRPOAoTBZvBGhPSkOAnl9CShvCHfKrHl0yzBk/k/lnt4Di6A6wWq4Ew1BveHXMH
# 1ZT+sdRuikm5YLLqLc/HhoiT3rid5EHVQK3sng95fIdBMgj26SScMvyKWNC9gKkp
# emezUSM/c91wEhwwggjoMIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0G
# CSqGSIb3DQEBCwUAMDwxEzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/Is
# ZAEZFgNBTUUxEDAOBgNVBAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYw
# NTIxMTg1NDE0WjBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQB
# GRYDQU1FMRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQDJmlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL
# 9rNHnHDGfJgeuRIYO1LY/1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc
# 411WxA+Pv2rteAcz0eHMH36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaC
# IIWBXyEchv+sM9eKDsUOLdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8p
# XirIYOgM770CYOiZrcKHK7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p
# /6fksgEILptOKhx9c+iapiNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkr
# BgEEAYI3FQEEBQIDAgACMCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMAL
# I38/RzAdBgNVHQ4EFgQUllGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfww
# gfkGBysGAQUCAwUGCCsGAQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYB
# BAGCNxUGBgorBgEEAYI3CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgC
# AgYKKwYBBAGCN0ABAQYLKwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcV
# BQYKKwYBBAGCNxQCAgYKKwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEG
# CisGAQQBgjdbAgEGCisGAQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEG
# CisGAQQBgjdbBAIwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQD
# AgGGMBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwN
# p4x1AdEJCygwggFoBgNVHR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDov
# L2NybDIuYW1lLmdibC9jcmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5n
# YmwvY3JsL2FtZXJvb3QuY3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVy
# b290LmNybIaBqmxkYXA6Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxD
# Tj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1
# cmF0aW9uLERDPUFNRSxEQz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9i
# YXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUH
# AQEEggGdMIIBmTBHBggrBgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NlcnRzL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKG
# K2h0dHA6Ly9jcmwyLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYI
# KwYBBQUHMAKGK2h0dHA6Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9v
# dC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJv
# b3RfYW1lcm9vdC5jcnQwgaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290
# LENOPUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxD
# Tj1Db25maWd1cmF0aW9uLERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNl
# P29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQEL
# BQADggIBAFAQI7dPD+jfXtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTH
# b8BDfRN+AD0YEmeDB5HKQoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a
# /752hMIn+L4ZuyxVeSBpfwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9
# zAh9yRKKls2bziPEnxeOZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAm
# n3WCPWNFC1YTIIHw/mD2cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtz
# yb7fbNS1dE740re0COE67YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjF
# K1yMw4Ni5fMabcgmzRvSjAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bz
# MzsikuDW9xH10graZzSmPjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIz
# J6Q9G3NPCB+7KwX0OQmKyv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/y
# wO6SYSreVW+5Y0mzJutnBC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEIS
# RtShDZbuYymynY1un+RyfiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZ6DCCGeQC
# AQEwWDBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1F
# MRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDECEzYAAAIOeZeg6f1fn9MAAgAAAg4wDQYJ
# YIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIM9EemlCM16v
# YmTlNdxKoRJCk2P4oOL3or5fDmfILAXCMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAd7MCIx2fzXiOtfDVD2jBCrOjK8QykBTT0nkcfbkUfIex
# HkusAuU83ZDyeIQlMLiPb4fqBJV/1om1Vq8xvdw6DlFB6JPxblkGcGpC9l/gWI4F
# /LLimePJDXewJwmFX9+0SNy5KNZxCNEFNI9IaKHNOsnGeePrFr9Q4a8fohjFMkUB
# tcmSH0GE3MxkkNQbbs8R08a2ndGSloUwuYERKl4x6Nf4GeXcOpLNMvzHR2SfSRRH
# 4ebXSeabwQpNjcmCJ/HSJMCyBBFfylBRgRC9bCHwbu2Z0DAW2qTg7DbkFWsFNeDZ
# V3VMTfSN1tHyU4S9ezg/Cc9qi0KSfitzELdVzMyvvKGCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCBHRAMVghyi/U2iA83VL+EnZTZdxUqQ2d7Ox5TGX0PH
# IAIGaXSr3pIIGBMyMDI2MDIwNDE2MzUyNy44NTRaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo2NTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACFRgD04EHJnxT
# AAEAAAIVMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgyMFoXDTI2MTExMzE4NDgyMFowgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjY1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAw3HV3hVx
# L0lEYPV03XeNKZ517VIbgexhlDPdpXwDS0BYtxPwi4XYpZR1ld0u6cr2Xjuugdg5
# 0DUx5WHL0QhY2d9vkJSk02rE/75hcKt91m2Ih287QRxRMmFu3BF6466k8qp5uXtf
# e6uciq49YaS8p+dzv3uTarD4hQ8UT7La95pOJiRqxxd0qOGLECvHLEXPXioNSx9p
# yhzhm6lt7ezLxJeFVYtxShkavPoZN0dOCiYeh4KgoKoyagzMuSiLCiMUW4Ue4Qsm
# 658FJNGTNh7V5qXYVA6k5xjw5WeWdKOz0i9A5jBcbY9fVOo/cA8i1bytzcDTxb3n
# ctcly8/OYeNstkab/Isq3Cxe1vq96fIHE1+ZGmJjka1sodwqPycVp/2tb+BjulPL
# 5D6rgUXTPF84U82RLKHV57bB8fHRpgnjcWBQuXPgVeSXpERWimt0NF2lCOLzqgrv
# S/vYqde5Ln9YlKKhAZ/xDE0TLIIr6+I/2JTtXP34nfjTENVqMBISWcakIxAwGb3R
# B5yHCxynIFNVLcfKAsEdC5U2em0fAvmVv0sonqnv17cuaYi2eCLWhoK1Ic85Dw7s
# /lhcXrBpY4n/Rl5l3wHzs4vOIhu87DIy5QUaEupEsyY0NWqgI4BWl6v1wgse+l8D
# WFeUXofhUuCgVTuTHN3K8idoMbn8Q3edUIECAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBSJIXfxcqAwFqGj9jdwQtdSqadj1zAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# d42HtV+kGbvxzLBTC5O7vkCIBPy/BwpjCzeL53hAiEOebp+VdNnwm9GVCfYq3KMf
# rj4UvKQTUAaS5Zkwe1gvZ3ljSSnCOyS5OwNu9dpg3ww+QW2eOcSLkyVAWFrLn6Ii
# g3TC/zWMvVhqXtdFhG2KJ1lSbN222csY3E3/BrGluAlvET9gmxVyyxNy59/7JF5z
# IGcJibydxs94JL1BtPgXJOfZzQ+/3iTc6eDtmaWT6DKdnJocp8wkXKWPIsBEfkD6
# k1Qitwvt0mHrORah75SjecOKt4oWayVLkPTho12e0ongEg1cje5fxSZGthrMrWKv
# I4R7HEC7k8maH9ePA3ViH0CVSSOefaPTGMzIhHCo5p3jG5SMcyO3eA9uEaYQJITJ
# lLG3BwwGmypY7C/8/nj1SOhgx1HgJ0ywOJL9xfP4AOcWmCfbsqgGbCaC7WH5sINd
# zfMar8V7YNFqkbCGUKhc8GpIyE+MKnyVn33jsuaGAlNRg7dVRUSoYLJxvUsw9GOw
# yBpBwbE9sqOLm+HsO00oF23PMio7WFXcFTZAjp3ujihBAfLrXICgGOHPdkZ042u1
# LZqOcnlr3XzvgMe+mPPyasW8f0rtzJj3V5E/EKiyQlPxj9Mfq2x9himnlXWGZCVP
# eEBROrNbDYBfazTyLNCOTsRtksOSV3FBtPnpQtLN754wggdxMIIFWaADAgECAhMz
# AAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0z
# MDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP9
# 7pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMM
# tY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gm
# U3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130
# /o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP
# 3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
# vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+A
# utuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz
# 1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
# EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/Zc
# UlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZy
# acaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJ
# KwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8G
# CCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3Mv
# UmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZF
# aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
# AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cB
# MSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7
# bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/
# SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2
# EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2Fz
# Lixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0
# /fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
# swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJ
# Xk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+
# pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
# 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCCAkECAQEwggEBoYHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo2NTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAj6eTejbuYE1Ifjbfrt6t
# XevCUSCggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0tqhwwIhgPMjAyNjAyMDQxMTIxMDBaGA8yMDI2MDIwNTEx
# MjEwMFowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7S2qHAIBADAKAgEAAgIViwIB
# /zAHAgEAAgISiDAKAgUA7S77nAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IB
# AQBrLZ3XO1wMVB4He8jOf3DV9mcxZtGtWM81QzCG/AAvmb1BZjvtTWZydyErnCLG
# Cc8WKzRGq5AfWJw9lYCbxKGlSBskcWiFzfvtSCMLOSByGI0gMgmSxJQrXzF7KMjh
# esXjmkK+t9WeeWG7+NqOMXD64zYnC0/fElSCe8c+yJvgHwc6NZ9jYjXcU8DWW1WZ
# VCjI3YbPUzEUqZ2IbWmRfLivgs1Wn5+PAcJXR7TfRmLSsE5M5ebx7jiubtKXlPdm
# XynIyroA+qvxMKxUlVyOcHx94OpjGUWRdMBoYSDVEi8zZmSuN+SOic0kPx3fsVtI
# aH+MKlW0Q355OAcnpRH7c6bVMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIVGAPTgQcmfFMAAQAAAhUwDQYJYIZIAWUDBAIB
# BQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgi5+vzNmuVm51Duo2t7Gz8HGfHn8D5zEoyTVsBEl7YpMwgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCBwEPR2PDrTFLcrtQsKrUi7oz5JNRCF/KRHMihSNe7s
# ijCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACFRgD
# 04EHJnxTAAEAAAIVMCIEIAy84l0FlIwqrldfB3TmTArja2bSHILWYvHOj9pAXLHS
# MA0GCSqGSIb3DQEBCwUABIICAGQGwkgTOWPdUbvQmYgNPR6ZGM5ks9/zohIiNsHB
# GQ8opOGTWErHN10NRxla4XCI6LDht858xkf6iwIOQTCfMmfvxJLN1jGnrMUIqhFm
# L2zHFoLGfT0Noxa7ZZO9B+1vxAKsaC6RhuoaurDkEK+Eo5WlvPah7RF0qHzHnDuN
# xwmQAadBvKkyQF4nPCWFaiH6f3IKFn7L7t6zx9S+1ABwtBdM7rt9/HOZXAl6sUTl
# cMuWTmjQ8WHmoPyupkGbo805L9oUlVnykqr2oFEHJDCcBQo4onSE2TWQtrGyEDWJ
# 6ZJ+RXGhgyn8GMUfeEZ3LaR1fPpXljz4pKs3sUhBLjo7cOLP4O0IYq04CSm+FzWY
# BnKESbVB6r1NcE4NQOzLgOy1j5e7akeUrTsbE+869w18gfd7shq3f5yZQ/+3ibo4
# iZ3QjV8Jm1pG/4GBG7Ya8fiRj9z+eDOnIqwAJxm2390IGPw4OBk93Nfn3dzBa4Zl
# k73xXeqedusUB0Q3F5OensBd1tciPLHp2k4IOeic3j3yXW+63IB2HsK8FN8UyukE
# WIynl8Jw6TS0cNrpm7jJ0xqBIeE0bssL2TJiF1S8THq6m2k896BtYe5iYHiZYsxx
# 20FauvFxEd6thKVzQUVWa3oKAc19iaMoTZtKQ4PpMHih6TsuIWaIUyoeNUwgpGok
# 0GgG
# SIG # End signature block
