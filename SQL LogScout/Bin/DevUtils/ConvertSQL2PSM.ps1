 <#
        .SYNOPSIS
        This module .SQL files to PSM1 modules.

        .DESCRIPTION
        This file will convert all files with extension .SQL in BIN\DevUtils to SQLScript_<CollectorName>.psm1 files in BIN folder.
        All converted SQL files will be moved to _sql.txt files to avoid double conversion.

        .INPUTS
        None. You can't pipe objects to Add-Extension.

        .OUTPUTS
        All files of .sql extension converted to SQLScript_<collectorName>.psm1

        .EXAMPLE
        PS> ConvertSQL2PSM.ps1
        
        
        .LINK
        Online documenation: https://mssql-support.visualstudio.com/SQL%20LogScout/_wiki/wikis/SQL-LogScout.wiki/110/Working-TSQL-Scripts

    #>

    <#
    This function will take TSQL filename as input (tsql.sql) and convert it to a pouwershell module (psm1) file.
    The fill will containe a single function that will generate the tsql file.

    The function name will be <fileName_without_extension>_Query

    
    #>

function convertFile2PSM ([String] $fileName)
{
    #clean the file from its extension, this will provide us with collector name
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($fileName) 
    
    #since we run this script in bin\devutils we get he parent path to write output files to.
    $path = Split-Path $PSScriptRoot -Parent

    #adding .sql file extension to collector name
    $filepath =  $fileName + ".sql"
    
    #output file name will be SQLScript_<collector name>.psm1
    $outputName = $path + "\SQLScript_" + $fileName + ".psm1"

    #function name will be <collector name>_Query
    $functionName = $fileName + "_Query([Boolean] `$returnVariable = `$false)"

    # Read the content of the text file
    $content = Get-Content -Path $filePath -Raw

    # Escape special characters and double quotes
    $escapedContent = $content -replace  '"', '`"'  -replace  '\$', '`$'


    $fileHeader = "
    function $functionName
    {
        Write-LogDebug `"Inside`" `$MyInvocation.MyCommand

        [String] `$collectorName = `"" + $fileName +"`"
        [String] `$fileName = `$global:internal_output_folder + `$collectorName + `".sql`"

        `$content =  `"
    $escapedContent
    `"

    if (`$true -eq `$returnVariable)
    {
    Write-LogDebug `"Returned variable without creating file, this maybe due to use of GUI to filter out some of the xevents`"

    `$content = `$content -split `"``r``n`"
    return `$content
    }

    if (-Not (Test-Path `$fileName))
    {
        Set-Content -Path `$fileName -Value `$content
    } else 
    {
        Write-LogDebug `"`$filName already exists, could be from GUI`"
    }

    #check if command was successful, then add the file to the list for cleanup AND return collector name
    if (`$true -eq `$?) 
    {
        `$global:tblInternalSQLFiles += `$collectorName
        return `$collectorName
    }

    Write-LogDebug `"Failed to build SQL File `" 
    Write-LogDebug `$fileName

    #return false if we reach here.
    return `$false

    }
    "
    #if output file exists, we can compare content before we write it again to disk
    [Boolean] $fileExist = Test-Path $outputName
    if ($true -eq $fileExist)
    {
        $origContent = Get-Content $outputName 
        #remove trailing spaces.
        while ([string]::IsNullOrEmpty( $origContent[-1].Trim())) {
            $origContent = $origContent[0..($origContent.Length - 2)]
        }
    }


    #if the existing file is the same as new file, do not write it to disk
    if (($true -eq $fileExist) -and ($origContent.Equals($fileHeader)))
    {
        Write-Host "$fileName has the same content, no writing is done"
    }
    else {
        # Output the escaped content
        Set-Content -Path $outputName -Value $fileHeader
        write-host "Converted $outputName"
        $newFileName = $fileName + "_sql.txt"
        Move-Item -Path $filepath  -Destination $newFileName -Force
    }

} #end of convertFile2PSM

#Main body of the script, get a colleection of all .sql files present in BIN\DevUtils folder.
$files =  Get-ChildItem  -Path . -Filter *.sql | Where-Object { $_.Name -notMatch "del_*" }


if ($null -eq $files) {
    Write-Host "No files to process"
    exit
}
#Process each .sql file to creat .psm1 file 
foreach ($file in $files)
{
    Write-Host $file.Name
    convertFile2PSM -fileName $file.Name

}


