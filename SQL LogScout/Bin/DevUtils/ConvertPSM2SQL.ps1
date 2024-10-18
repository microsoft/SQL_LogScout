 <#
        .SYNOPSIS
        This module export SQL Script out of PSM files.

        .DESCRIPTION
        In order to make it easy for developers to work directly with SQL files, this script will extract the SQL content of SQLScript_ file(s) and save it as pure .SQL file
        Later the same file can be converted again to PSM1 file using ConvertSQL2PSM.ps1.

        .PARAMETER CollectorName
        This parameter has a list of all current Collector/Script names (AlwaysOn_Data_Movement..etc), this will help you choose a specific collector to export,
        You can alternatively chose to convert "ALL" scripts at once.

        .INPUTS
        None. You can't pipe objects to Add-Extension.

        .OUTPUTS
        SQL File(s) for choosen collector or ALL collectors exported in the same folder BIN\DevUtils.

        .EXAMPLE
        PS> ConvertPSM2SQL.ps1 -CollectorName Change_Tracking
        .EXAMPLE
        PS> ConvertPSM2SQL.ps1 -CollectorName ALL
        .LINK
        Online documenation: https://mssql-support.visualstudio.com/SQL%20LogScout/_wiki/wikis/SQL-LogScout.wiki/110/Working-TSQL-Scripts

    #>

Param(
    [Parameter(Mandatory=$true)]
    [ValidateSet ("ALL", #this shall trigger conversion of all scripts by enumerating the files SQLScript_* files in bin folder
    "AlwaysOnDiagScript",
    "Change_Tracking",
    "ChangeDataCapture",
    "FullTextSearchMetadata",
    "High_IO_Perfstats",
    "HighCPU_perfstats",
    "linked_server_config",
    "MiscDiagInfo",
    "MSDiagProcs",
    "NeverEndingQuery_perfstats",
    "ProfilerTraces",
    "QueryStore",
    "Repl_Metadata_Collector",
    "SQL_Server_Mem_Stats",
    "SQL_Server_PerfStats_Snapshot",
    "SQL_Server_PerfStats",
    "SSB_DbMail_Diag",
    "TempDB_and_Tran_Analysis",
    "xevent_AlwaysOn_Data_Movement",
    "xevent_backup_restore",
    "xevent_core",
    "xevent_detailed",
    "xevent_general",
    "xevent_servicebroker_dbmail")]
    [String]$CollectorName
)


#This function will convert a psm file to a TSQL file to helep developers change TSQL code and later convert it again to psm1 file using the the utilit ConvertSQL2PSM.ps1

function convertFile2SQL([String] $cName)
{
     #since we are working inside bin\DevUtils we need to get the parent folder path to read the SQLScript*.psm1 files.
    $parentPath = Split-Path -Path $PSScriptRoot  -Parent
    $fileFullName =  $parentPath + "\" + "SQLScript_" + $cName + ".psm1"
    $SQLFileName = $cName + ".sql"

    $functionName = $cName + "_Query"

    if (-Not (Test-Path ($fileFullName)))
    {
        Write-Host "$fileFullname Does not exist, exiting "
        Exit
    }
    
        
    #import the psm1 file
    Import-Module $fileFullName
        
    #return the content the tsql content as a variable 
    $content = & $functionName -returnVariable $true

    #Remove trailing empty spaces.
    while ([string]::IsNullOrEmpty( $content[-1].Trim())) {
        $content = $content[0..($content.Length - 2)]
    }
     

    #write the content to tsql file name inside DevUtils
    Set-Content -Path $SQLFileName -Value $content

    Write-Host "$SQLFileName saved to disk"


}

Import-Module "..\CommonFunctions.psm1"
Import-Module "..\LoggingFacility.psm1"

#if user choses a specific collector, then we test if the file exists then call the function to convert.
if (($CollectorName -ne "ALL") )
{
    convertFile2SQL -cName $CollectorName
    
} 
elseif ($CollectorName -eq "ALL")
{
    $parentPath = Split-Path -Path $PSScriptRoot  -Parent
    #Write-Host $parentPath
    $files = Get-ChildItem  -Path $parentPath -Filter SQLScript*.psm1 

    foreach ($file in $files)
    {
        #Remove extension from file name
        $fName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

        #Remove SQLSCript_ to extract collector's name
        $fName = $fName -replace "SQLScript_", ""
        
        convertFile2SQL -cName $fName

    }

}
