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


if ($sqlnexuspath -ne "")
{
    Write-LogInformation "Importing the log in SQL database using SQLNexus.exe"

    Write-Host "SQL LogScout assumes you have already downloaded SQLNexus.exe. If not, please download it here -> https://github.com/Microsoft/SqlNexus/releases "

    if (Test-Path -Path ($sqlnexuspath +"\sqlnexus.exe"))
    {
        Write-Host "The directory is valid or SQLNexus.exe is available in it."

        $executable = ($sqlnexuspath + "\sqlnexus.exe")

        $argument_list = "/S" + '"'+ $ServerName +'"' + " /D" + '"'+ $sqlnexusdb +'"'  + " /E" + " /I" + '"'+ $logfolder +'"' + " /Q /N"

        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait

        # check the tables in Database which was used to import above in SQLNEXUS
    
        $sqlnexus_scrips = (get-item $logfolder).Parent.FullName + "\TestingInfrastructure\sqlnexus_tablecheck_proc.sql" 
        $datetime = ( get-date ).ToString('yyyyMMddhhmmss');
        $sqlnexusreportfile = $datetime + '_'+ $Scenarios +'_SQLNexusOutput.txt'
        $Reportfilesqlnexus = (get-item $logfolder).Parent.FullName + "\TestingInfrastructure\output\" + $sqlnexusreportfile 

        $executable  = "sqlcmd.exe"
        $argument_list = "-S" + '"'+ $ServerName +'"' + " -d" + '"'+ $sqlnexusdb +'"'  + " -E -Hsqllogscout_cleanup -w8000" + " -i" + '"'+ $sqlnexus_scrips +'"' 
        Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait

        $sqlnexus_query = 'exec tempdb.dbo.temp_sqlnexus ''' + $Scenarios + '''' + ', ' + '''' + $sqlnexusdb + ''''
        $argument_list2 = "-S" + '"'+ $ServerName +'"' + " -d" + '"'+ $sqlnexusdb +'"'  + " -E -Hsqllogscout_cleanup -w8000" + " -Q" + '"EXIT('+ $sqlnexus_query +')"' + " -o" + '"'+ $Reportfilesqlnexus +'"' 
        $proc = Start-Process -FilePath $executable -ArgumentList $argument_list2 -WindowStyle Hidden -Wait -PassThru

        if ($proc)
        {
            if($proc.ExitCode -eq 202)
            {
                #there are tables that are not present. report in summary file
                Write-Output "SQLNexus '$Scenarios' scenario test: FAILED!!! Found missing tables; see '$Reportfilesqlnexus'" | Out-File $OutputFilename -Append
            }
            else 
            {
                Write-Output "SQLNexus $Scenarios scenario test: SUCCESS. " | Out-File $OutputFilename -Append
            }
        }

        $sqlnexus_query = 'Drop procedure temp_sqlnexus ' 
        $argument_list3 = "-S" + '"'+ $ServerName +'"' + " -d" + '"tempdb"'  + " -E -Hsqllogscout_cleanup -w8000" + " -Q" + '"'+ $sqlnexus_query +'"'  
        Start-Process -FilePath $executable -ArgumentList $argument_list3 -WindowStyle Hidden 

    }
    else
    {
        Write-Host "The directory is invalid or SQLNexus.exe is not available in it."

    }
}
