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
    [bool] $UseRelativeStartStopTime = $false,

    [Parameter(Position=9,Mandatory=$false)]
    [int] $RepeatCollections = 0,

    [Parameter(Position=10)]
    [double] $RunDuration = 3,
    
    [Parameter(Position=11)]
    $UseStopFile = $false
)


try 
{
    
    $TSQLLoadModule = (Get-Module -Name TSQLLoadModule).Name

    if ($TSQLLoadModule -ne "GenerateTSQLLoad")
    {
        Import-Module -Name .\GenerateTSQLLoad.psm1
    }

    $TSQLLoadCommonFunction = (Get-Module -Name CommonFunctions).Name

    if ($TSQLLoadCommonFunction -ne "CommonFunctions")
    {
        #Since we are in bin and CommonFunctions is in root directory, we need to step out to import module
        #This is so we can use HandleCatchBlock

        [string]$parentLocation =  (Get-Item (Get-Location)).Parent.FullName 
        Import-Module -Name ($parentLocation + "\CommonFunctions.psm1")
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


    if ($UseRelativeStartStopTime -eq $true)
    {
        # build random start and stop time in the format "+HH:mm:ss" where time is less than 2 minutes
        # this is to test the relative start and stop time feature with semi-random times
        $start_sec = Get-Random -Minimum 0 -Maximum 60
        $stop_sec = Get-Random -Minimum 0 -Maximum 60

        $start_min = Get-Random -Minimum 1 -Maximum 3
        $stop_min = Get-Random -Minimum 1 -Maximum 3


        [string]$StartTime = "+00" + ":" + "0" + $start_min.ToString() + ":" + $(if ($start_sec -le 9) {"0" + $start_sec.ToString()} else {$start_sec.ToString()}) 
        [string]$StopTime  = "+00" + ":" + "0" + $stop_min.ToString() + ":" + $(if ($stop_sec -le 9) {"0" + $stop_sec.ToString()} else {$stop_sec.ToString()})  

        Write-Host "Relative Start Time: $StartTime and Relative Stop Time: $StopTime"
    }
    else
    {
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
        $StopTime = (Get-Date).AddMinutes($RunDuration).ToString("yyyy-MM-dd HH:mm:ss")
    }


    # start TSQLLoad execution
    if ($RunTSQLLoad -eq $true)
    {
        Initialize-TSQLLoadLog -Scenario $Scenarios

        TSQLLoadInsertsAndSelectFunction -ServerName $ServerName
    }


    #if UseStopFile is set, start a job which will create a stop file after the specified time in seconds (RunDuration *60 * 0.60)
    if ($UseStopFile -eq $true)
    {
        Write-Host "Creating stop file for LogScout to stop in $($RunDuration*60*0.60) seconds"
        $StopFile = $RootFolder + "\output\internal\logscout.stop"
        $StopDuration = ($RunDuration * 60) * 0.60 # 60% of the run duration in seconds
        $stop_job = Start-Job  -Name "CreateStopFileJob" -ScriptBlock {
                            param($StopFile, $StopDuration) 
                            Start-Sleep -Seconds $StopDuration; 
                            Set-Content -Value "stop please" -Path $StopFile -Force;
                            
                            if (Test-Path -Path $StopFile)
                            {
                                Microsoft.PowerShell.Utility\Write-Host "The stop file $StopFile was created successfully."
                            }
                            else
                            {
                                Microsoft.PowerShell.Utility\Write-Host "The stop file $StopFile was not created successfully."
                            }
                            #no need to remove the file as it will be deleted when a new test is run
                        } -ArgumentList $StopFile, $StopDuration
    } 

    ##execute a regular SQL LogScout data collection from root folder
    Write-Host "Starting LogScout"

    #build the path to the SQL_LogScout.ps1 script
    [string] $LogScoutCmd =$RootFolder  + "\SQL_LogScout.ps1" 

    #invoke SQL LogScout in a child process
    $arguments = "-File `"$($LogScoutCmd)`" -Scenario `"$($Scenarios)`" -ServerName `"$($ServerName)`" -CustomOutputPath `"UsePresentDir`" -DeleteExistingOrCreateNew `"DeleteDefaultFolder`" -DiagStartTime `"$($StartTime)`" -DiagStopTime `"$($StopTime)`" -InteractivePrompts `"Quiet`" -RepeatCollections $($RepeatCollections.ToString()) "
    
    Write-Host "Arguments: $arguments"
    Start-Process -FilePath "powershell" -ArgumentList $arguments -Wait -NoNewWindow

    #check if TSQL workload is enabled and if so, check if it has finished
    if ($RunTSQLLoad -eq $true)
    {
        Write-Host "Verifying T-SQL workload finished"
        if ($TSQLLoadModule -ne "GenerateTSQLLoad")
        {
            Import-Module -Name .\GenerateTSQLLoad.psm1
        }

        TSQLLoadCheckWorkloadExited
    }

    #if UseStopFile is set, wait for the job to complete and print the output
    if ($UseStopFile -eq $true)
    {
        # Wait for the job to complete
        Wait-Job -Job $stop_job | Out-Null

        # Retrieve and display the job output
        $jobOutput = Receive-Job -Job $stop_job
        Microsoft.PowerShell.Utility\Write-Host $jobOutput

        # Remove the job
        Remove-Job -Job $stop_job
    }


    #run file validation test

    $script_ret = ./FileCountAndTypeValidation.ps1 -SummaryOutputFile $SummaryOutputFile 2> .\##TestFailures.LOG
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

}
catch {
    $error_msg = $PSItem.Exception.Message
    $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
    $error_offset = $PSItem.InvocationInfo.OffsetInLine
    $error_script = $PSItem.InvocationInfo.ScriptName
    Write-Error "Function '$($MyInvocation.MyCommand)' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    
    exit 999
}