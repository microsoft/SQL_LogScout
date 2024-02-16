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
    [string] $SqlNexusPath,

    [Parameter(Position=4)]
    [string] $SqlNexusDb,

    [Parameter(Position=5)]
    [string] $LogScoutOutputFolder,

    [Parameter(Position=6, Mandatory=$true)]
    [string] $SQLLogScoutRootFolder
)


function GetExclusionsInclusions ([string]$Scenario)
{
    [string] $RetExclusion = ""

    switch ($Scenario) 
    {
        # if there are exceptions for more scenarios in the future, use these
        "Basic" {}
        "Replication" 
        {
            if ($false -eq (CheckLogsForString  -TextToFind "Collecting Replication Metadata"))
            {
                $RetExclusion = "ReplMetaData"
            }
        }
        "AlwaysOn"
        {
            if ($true -eq (CheckLogsForString -TextToFind "HADR is off, skipping data movement and AG Topology" ))
            {
                $RetExclusion = "NoAlwaysOn"
            }
        }
        "NeverEndingQuery"
        {
            if ($true -eq (CheckLogsForString -TextToFind "NeverEndingQuery Exit without collection"))
            {
                $RetExclusion = "NoNeverEndingQuery"

            }
        }
    }

    return $RetExclusion
}

function CheckLogsForString()
{
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [string] $TextToFind
    )

    #Search the default log first as there less records than debug log.
    if (Select-String -Path $global:SQLLogScoutLog -Pattern $TextToFind)
    {
        return $true
    }
    #If we didn't find in default log, then check debug log for the provided string.
    elseif (Select-String -Path $global:SQLLogScoutDebugLog -Pattern $TextToFind)
    {
        return $true
    }
    #We didn't find the provided text 
    else
    {
        Write-Output "No ##SQLLogScout logs contains the string provided" | Out-File $global:ReportFileSQLNexus -Append
    }
    
    return $false
}


try 
{
    $return_val = $true
    $testingFolder = $SQLLogScoutRootFolder + "\Bin\TestingInfrastructure\"
    $global:ReportFileSQLNexus = $testingFolder + "output\" + (Get-Date).ToString('yyyyMMddhhmmss') + '_'+ $Scenarios +'_SQLNexusOutput.txt'
    $out_string = "SQLNexus '$Scenarios' scenario test:"
    $global:SQLLogScoutLog = $LogScoutOutputFolder + "\internal\##SQLLOGSCOUT.LOG"
    $global:SQLLogScoutDebugLog = $LogScoutOutputFolder + "\internal\##SQLLOGSCOUT_DEBUG.LOG"


    #if SQLNexus.exe path is provided we run the test
    if ($SqlNexusPath -ne "")
    {
        #check if multiple scenarios are provided and exit if so
        if ($Scenarios.Split("+").Count -gt 1)
        {
            $out_string = ($out_string + " "*(60 - $out_string.Length) + "FAILED!!! SQLNexus_Test does not support multiple scenarios (only single scenario).")
            Write-Output $out_string | Out-File $OutputFilename -Append
            return $false
        }

        $sqlnexus_imp_msg =  "Importing logs in SQL database '$SqlNexusDb' using SQLNexus.exe"
        Write-Host $sqlnexus_imp_msg

        Write-Host "SQL LogScout assumes you have already downloaded SQLNexus.exe. If not, please download it here -> https://github.com/Microsoft/SqlNexus/releases "

        $executable = ($SqlNexusPath + "\sqlnexus.exe")
        
        if (Test-Path -Path ($executable))
        {
            $sqlnexus_version = (Get-Item $executable).VersionInfo.ProductVersion
            $sqlnexus_found = "SQLNexus.exe v$sqlnexus_version found. Executing test..."
            Write-Host $sqlnexus_found


            #launch SQLNexus  and wait for it to finish processing -Wait before continuing
            $argument_list = "/S" + '"'+ $ServerName +'"' + " /D" + '"'+ $SqlNexusDb +'"'  + " /E" + " /I" + '"'+ $LogScoutOutputFolder +'"' + " /Q /N"
            Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait

            
            # check the tables in SQL Nexus-created database and report if some were not imported
            $sqlnexus_scripts = $testingFolder + "sqlnexus_tablecheck_proc.sql" 


            #create the stored procedure
            $executable  = "sqlcmd.exe"
            $argument_list = "-S" + '"'+ $ServerName +'"' + " -d" + '"'+ $SqlNexusDb +'"'  + " -E -Hsqllogscout_sqlnexustest -w8000" + " -i" + '"'+ $sqlnexus_scripts +'"' 
            Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait

            # check for any exception/exclusion situations
            $ExclusionTag = GetExclusionsInclusions -Scenario $Scenarios

            #execute the stored procedure
            $sqlnexus_query = "exec tempdb.dbo.proc_SqlNexusTableValidation '" + $Scenarios + "', '" + $SqlNexusDb + "', '" +  $ExclusionTag + "'"
            $argument_list2 = "-S" + '"'+ $ServerName +'"' + " -d" + '"'+ $SqlNexusDb +'"'  + " -E -Hsqllogscout_sqlnexustest -w8000" + " -Q" + '"EXIT('+ $sqlnexus_query +')"' + " -o" + '"'+ $global:ReportFileSQLNexus +'"' 
            $proc = Start-Process -FilePath $executable -ArgumentList $argument_list2 -WindowStyle Hidden -Wait -PassThru 

            if ($proc)
            {
                

                if($proc.ExitCode -eq 2002002)
                {
                    #there are tables that are not present. report in summary file
                    $out_string = ($out_string + " "*(60 - $out_string.Length) + "FAILED!!! (Found missing tables; see '$global:ReportFileSQLNexus')")
                    $return_val = $false
                }
                elseif ($proc.ExitCode -eq 1001001)
                {
                    $out_string = ($out_string + " "*(60 - $out_string.Length) + "SUCCESS ")
                    
                }
                else
                {
                    $out_string = ($out_string + " "*(60 - $out_string.Length) + "FAILED!!! Query/script failure of some kind. Exit code = '$($proc.ExitCode)' ")
                    $return_val = $false
                }

                Write-Output $out_string | Out-File $OutputFilename -Append
            }

            #clean up stored procedure

            $sqlnexus_query = 'DROP PROCEDURE dbo.proc_SqlNexusTableValidation ' 
            $executable  = "sqlcmd.exe"
            $argument_list3 = "-S" + '"'+ $ServerName +'"' + " -d" + '"tempdb"'  + " -E -Hsqllogscout_cleanup -w8000" + " -Q" + '"'+ $sqlnexus_query +'"'  
            Start-Process -FilePath $executable -ArgumentList $argument_list3 -WindowStyle Hidden 

        }
        else
        {
            $missing_sqlnexus_err = "The SQLNexus directory '$SqlNexusPath' is invalid or SQLNexus.exe is not present in it." 

            #write to detailed file
            Write-Host $missing_sqlnexus_err -ForegroundColor Red
            Write-Output $missing_sqlnexus_err | Out-File $global:ReportFileSQLNexus -Append

            # write out to the summary file
            $out_string = ($out_string + " "*(60 - $out_string.Length) + "FAILED!!! SQLNexus.exe not found. See '$global:ReportFileSQLNexus'")
            Write-Output $out_string | Out-File $OutputFilename -Append
            $return_val = $false
        }

        #append several message to the datetime_scenario_SQLNexusOutput.txt file
        $storedproc_results = Get-Content -Path  $global:ReportFileSQLNexus
        Set-Content -Path  $global:ReportFileSQLNexus -Value $sqlnexus_imp_msg
        Add-Content -Path  $global:ReportFileSQLNexus -Value $sqlnexus_found
        Add-Content -Path  $global:ReportFileSQLNexus -Value ""
        Add-Content -Path $global:ReportFileSQLNexus -Value $storedproc_results
    }

    # if some error occurred, print the report file to the console (for debugging purposes)
    if ($return_val -eq $false)
    {   Write-Host "Printing detailed SQLNexus test output '$global:ReportFileSQLNexus':`n"
        Get-Content -Path $global:ReportFileSQLNexus | Out-Host
    }

    return $return_val

}
catch 
{
    $mycommand = $MyInvocation.MyCommand
    $error_msg = $PSItem.Exception.Message
    Write-Host $_.Exception.Message
    $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
    $error_offset = $PSItem.InvocationInfo.OffsetInLine
    Write-LogError "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
    return $false
}
