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
         [PSCustomObject]@{Algorithm = "SHA512"; Hash = "76DBE5D92A6ADBBAD8D7DCAAC5BD582DF5E87D6B7899882BB0D7489C557352219795106EBD3014BC76E07332FA899CE1B58B273AE5836B34653D4C545BBF89A4"; FileName = $pwdir + "\AlwaysOnDiagScript.sql"; FileSize = 21298}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "4E2E0C0018B1AE4E6402D5D985B71E03E8AECBB9DA3145E63758343AEAC234E3D4988739CCE1AC034DDA7CE77482B27FB5C2A7A4E266E9C283F90593A1B562A2"; FileName = $pwdir + "\ChangeDataCapture.sql"; FileSize = 4672}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "073C0BBAB692A88387AF355A0CEC7A069B7F6C442A8DABF4EFC46E54ACEC7B569B866778A66FE1ADEBF8AD4F30EF3EAF7EF32DD436BC023CD4BC3AD52923AB9F"; FileName = $pwdir + "\Change_Tracking.sql"; FileSize = 5110}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "7E4BF16CD162F767D92AB5EE2FCBC0107DB43068A9EA45C68C2E1DD078C1FA15E9A10CEB63B9D8AEA237F4A2D96E7E5CE34AC30C2CEF304056D9FB287DF67971"; FileName = $pwdir + "\HighCPU_perfstats.sql"; FileSize = 6649}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "D9FA1C31F90188779B00552755059A0E3747F768AA55DEBE702D039D7F942F7C4EA746EE7DE7AC02D0685DDFEED22854EB85B3268594D0A18F1147CA9C20D55A"; FileName = $pwdir + "\High_IO_Perfstats.sql"; FileSize = 9554}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "824A41667D5DAA02729BB469E97701A41A09462EBBEDD2F5851061DC25465DC4422AD52DEDE1B5321FB55D485FDA6DBEE3B6429B303361078ACE3EF0581A8230"; FileName = $pwdir + "\linked_server_config.sql"; FileSize = 1184}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "B97914C0D8B53261A6C9CE93D6E306FE36A97FCE2F632C76FB180F2D1A2EC12510095CE35413D349386FD96B0F8EE54256EEE0AD9DA43CB0D386205D63F7EB20"; FileName = $pwdir + "\MiscDiagInfo.sql"; FileSize = 17791}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "218F71ECDA1075B4D2B5785A94EF43569306BBDB026C163DFEAF33F960F802D13C65F1BC103CC2978F497A2EF5EA972EE89940C807188FC7366E11A1C30DB2D9"; FileName = $pwdir + "\MSDiagProcs.sql"; FileSize = 194123}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "9789564CA007738B53D6CE21E6065A3D57D3E5A85DE85D32EC1456ED5A79CB1FA0265351FE402D266D6E90E31761DCED208AAA98EDA8BBC24AC25CF7819287D5"; FileName = $pwdir + "\QueryStore.sql"; FileSize = 4870}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "7216F9591ECB3C38BD962C146E57800687244B1C0E8450157E21CF5922BBBF92BB8431A814E0F5DF68933623DD76F9E4486A5D20162F58C232B8116920C252C7"; FileName = $pwdir + "\ProfilerTraces.sql"; FileSize = 3601}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "42BE545BC8D902A9D43146ACFC8D6A164242B567996C992D57CFBC6660B4E08051E7E687E2D140DAE5B17A8EEE652CFBD3904EC385702A2B8B666A980AE3C982"; FileName = $pwdir + "\Repl_Metadata_Collector.sql"; FileSize = 23414}
	    ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "3089C42E8B2A1F4DE4EDD172C4D43F978147DB875D25989662C36286C755F46C462CF8AB1A163083B8BBB4973F97AC333752D5CFBDE2BBEFDDA1556CBC884485"; FileName = $pwdir + "\SQL_Server_PerfStats_Snapshot.sql"; FileSize = 36982}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "275BF48FF8C495B6BA9217D2E5A3F7A7D1A7BDFF32AF035A2E9A03AF18773522816C6484B6F463C123B78572EF586CE846D9C1C36917E398A20E094D3836C58C"; FileName = $pwdir + "\SQL_Server_PerfStats.sql"; FileSize = 73276}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "98DD9089860E83AD5116AFC88E8A58EF18F3BC99FE68AC4E37765AF3442D58D2DC3C6826E860C0F0604B2C4733F33396F0894C2ACA9E905346D7C4D5A4854185"; FileName = $parentdir + "\SQL_LogScout.cmd"; FileSize = 2564}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "FC0FA00B999C9A6BF8CD55033A530C35D47F95CEE0156D540C77480E91180C7B9DBD303D5B73208D2C783D1FE628BF88AC845A4A452DD2FE3563E15E35A91BBD"; FileName = $pwdir + "\SQL_Server_Mem_Stats.sql"; FileSize = 35326}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "96CD13704AD380D61BC763479C1509F5B6EFCC678558AE8EACE1869C4BCD1B80767115D109402E9FDF52C144CFD5D33AAFFF23FE6CFFDF62CD99590B37D5D6CF"; FileName = $pwdir + "\SSB_DbMail_Diag.sql"; FileSize = 12477}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "2269D31F61959F08646C3E8B595191A110A8B559DEE43A60A5267B52A04F6A895E808CF2EC7C21B212BCAF9DD5AF3C25101B3C0FB91E8C1D6A2D1E42C9567FEC"; FileName = $pwdir + "\TempDB_and_Tran_Analysis.sql"; FileSize = 19749}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "26FB26FBC977B8DD1D853CBE3ABD9FFAA87743CF7048F5E6549858422749B9BD8D6F2CA1AFE35C3A703407E252D8F3CDC887460D2400E69063E99E9E76D4AFFB"; FileName = $pwdir + "\xevent_AlwaysOn_Data_Movement.sql"; FileSize = 23164}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "4EE3B0EE6CEA79CA9611489C2A351A7CCB27D3D5AD2691BE6380BF9C2D6270EE0CFC639B584A2307856384E7AA3B08462BCEA288D954786576DAFC4346670376"; FileName = $pwdir + "\xevent_backup_restore.sql"; FileSize = 1178}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "DE42C1F05E42FF67BBE576EA8B8ADF443DD2D889CBE34F50F4320BE3DC793AF88F5DE13FDC46147CA69535691CC78ADB89463602F5364ED332F6F09A254B7948"; FileName = $pwdir + "\xevent_core.sql"; FileSize = 8134}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "9E09DC85282A3870A339B4928AE1E3D4ECE34B5346DA9E52BD18712A6E3D07241D80083C4A18206BBBA4D2971F13BC937CE6062C76FD83189D66B8704B0CBA1A"; FileName = $pwdir + "\xevent_detailed.sql"; FileSize = 25312}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "2C5A3942093AC02FDE94626B327F6073056E4C14DA8AA13FE69404EFBABDF935B8622BA77316F630A2B313B7CE1EF20BC5A0A37E69FE38FFFCD794C16D82A71C"; FileName = $pwdir + "\xevent_general.sql"; FileSize = 20705}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "F643167BBC7C3BAAA3A9916A5A83C951DEC49A11DF7335E231D778F02C5271C934A3EDBEE8DC01B7F0624B54C8AB37576289441C8A1867F02620F4B6328CCBAC"; FileName = $pwdir + "\xevent_servicebroker_dbmail.sql"; FileSize = 39706}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "BF31CC80FDA7ED1DD52C88AE797B1FA186770DF005F3428D09785AD2307D6C059B71E5D8AF4EBF6A6AE60FF730519F25CEA934604BDD37CE8060BB38788CB497"; FileName = $pwdir + "\NeverEndingQuery_perfstats.sql"; FileSize = 6866}
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
