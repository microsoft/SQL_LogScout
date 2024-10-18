## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.

function Confirm-FileAttributes
{
<#
    .SYNOPSIS
        Checks the file attributes against the expected attributes in $expectedFileAttributes array.
    .DESCRIPTION
        Goal is to make sure that non-Powershell scripts were not inadvertently changed.
        Currently checks for changes to file size and hash.
        Will return $false if any attribute mismatch is found.
    .EXAMPLE
        $ret = Confirm-FileAttributes
#>

    Write-LogDebug "inside" $MyInvocation.MyCommand

    Write-LogInformation "Validating attributes for non-Powershell script files"

    $validAttributes = $true #this will be set to $false if any mismatch is found, then returned to caller

    $pwdir = (Get-Location).Path
    $parentdir = (Get-Item (Get-Location)).Parent.FullName

    $expectedFileAttributes = @(
        [PSCustomObject]@{Algorithm = "SHA512"; Hash = "F81C8F5372C6362539BFB554EA1FF857029BB205BF161E8F0D69843B296F333566F0F0C0D6ECD9D055902275CD60EB83C10ACA9083A48CEE47F6575A32E355AF"; FileName = $parentdir + "\SQL_LogScout.cmd"; FileSize = 2253}
    )
    # global array to keep a System.IO.FileStream object for each of the non-Powershell files
    # files are opened with Read sharing before being hashed
    # files are kept opened until SQL LogScout terminates preventing changes to them
    [System.Collections.ArrayList]$Global:hashedFiles = New-Object -TypeName System.Collections.ArrayList

    foreach ($efa in $expectedFileAttributes) {

        try{
            Write-LogDebug "Attempting to open file with read sharing: " $efa.FileName

            # open the file with read sharing and add to array
            [void]$Global:hashedFiles.Add(
                [System.IO.File]::Open(
                    $efa.FileName,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::Read
                    ))

        } catch {
            $validAttributes = $false
            Write-LogError "Error opening file with read sharing: " $efa.FileName
            Write-LogError $_
            return $validAttributes
        }

        Write-LogDebug "Validating attributes for file " $efa.FileName

        try {
            $file = Get-ChildItem -Path $efa.FileName

            if ($null -eq $file){
                throw "`$file is `$null"
            }
        }
        catch {
            $validAttributes = $false
            Write-LogError ""
            Write-LogError "Could not get properties from file " $efa.FileName
            Write-LogError $_
            Write-LogError ""
            return $validAttributes
        }

        try {
            $fileHash = Get-FileHash -Algorithm $efa.Algorithm -Path $efa.FileName

            if ($null -eq $fileHash){
                throw "`$fileHash is `$null"
            }

        }
        catch {
            $validAttributes = $false
            Write-LogError ""
            Write-LogError "Could not get hash from file " $efa.FileName
            Write-LogError $_
            Write-LogError ""
            return $validAttributes
        }

        if(($file.Length -ne $efa.FileSize) -or ($fileHash.Hash -ne $efa.Hash))
        {
            $validAttributes = $false
            Write-LogError ""
            Write-LogError "Attribute mismatch for file: " $efa.FileName
            Write-LogError ""
            Write-LogError "Expected File Size: " $efa.FileSize
            Write-LogError "  Actual File Size: " $file.Length
            Write-LogError ""
            Write-LogError "Expected File " $efa.Algorithm " Hash: " $efa.Hash
            Write-LogError "   Actual File " $fileHash.Algorithm " Hash: " $fileHash.Hash
            Write-LogError ""

        } else {
            Write-LogDebug "Actual File Size matches Expected File Size: " $efa.FileSize " bytes" -DebugLogLevel 2
            Write-LogDebug "Actual Hash matches Expected Hash (" $efa.Algorithm "): " $efa.Hash -DebugLogLevel 2
        }

        if (-not($validAttributes)){
            # we found a file with mismatching attributes, therefore backout indicating failure
            return $validAttributes
        }

    }

    return $validAttributes
}

function Get-FileAttributes([string] $file_name = ""){
<#
    .SYNOPSIS
        Display string for $expectedFileAttributes.
    .DESCRIPTION
        This is to be used only when some script is changed and we need to refresh the file attributes in Confirm-FileAttributes.ps1
    .EXAMPLE
        Import-Module -Name .\Confirm-FileAttributes.psm1
        Get-FileAttributes #all files
        Get-FileAttributes "xevent_core.sql" #for a single file
#>

    [int]$fileCount = 0
    [System.Text.StringBuilder]$sb = New-Object -TypeName System.Text.StringBuilder

    [void]$sb.AppendLine("`$expectedFileAttributes = @(")

    foreach($file in (Get-ChildItem -Path . -File -Filter $file_name -Recurse)){

        # Powershell files are signed, therefore no need to hash-compare them
        # "Get-ChildItem -Exclude *.ps1 -File" yields zero results, therefore we skip .PS1 files with the following IF
        if ((".sql" -eq $file.Extension) -or (".cmd" -eq $file.Extension) -or (".bat" -eq $file.Extension))
        {

            $fileCount++

            # append TAB+space for first file (identation)
            # append TAB+comma for 2nd file onwards
            if($fileCount -gt 1){
                [void]$sb.Append("`t,")
            } else {
                [void]$sb.Append("`t ")
            }

            $fileHash = Get-FileHash -Algorithm SHA512 -Path $file.FullName

            $algorithm = $fileHash.Algorithm
            $hash = $fileHash.Hash

            if($file.Name -eq "SQL_LogScout.cmd")
            {
                $fileName = "`$parentdir `+ `"`\" + $file.Name + "`""
            }
            else 
            {
                $fileName = "`$pwdir `+ `"`\" + $file.Name + "`""
            }
            
            $fileSize = [string]$file.Length

            [void]$sb.AppendLine("[PSCustomObject]@{Algorithm = `"$algorithm`"; Hash = `"$hash`"; FileName = $fileName; FileSize = $fileSize}")

        }

    }

    [void]$sb.AppendLine(")")

    Write-Host $sb.ToString()
}
