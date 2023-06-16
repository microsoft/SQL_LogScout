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
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "A5D2B75290F953A4F184EF700712C31580AC835ADD4D4A9D84C9D202FC04999E69933604C3BC8E05D2B3C4497675959B61BC2AD538518966516FE0AF52FFE5AD"; FileName = $pwdir + "\collecterrorlog.sql"; FileSize = 361}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "2D349AE6F6AEFB934BB93451B99148137DB1A550831EF661945B361FE11F92E6FF73F540DCCBF87BB22AD386053042163227BEB43B9620F10BD966F55C6CD304"; FileName = $pwdir + "\HighCPU_perfstats.sql"; FileSize = 5360}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "45833A77D15E7C6F2BF6849DC3469B637845D8465E431BFFBBEC78A90CEB7D3E2859FB83BD688EF75A895A232BAE01D97D10E6CB5DDB30453B311682EEDF534C"; FileName = $pwdir + "\High_IO_Perfstats.sql"; FileSize = 6435}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "824A41667D5DAA02729BB469E97701A41A09462EBBEDD2F5851061DC25465DC4422AD52DEDE1B5321FB55D485FDA6DBEE3B6429B303361078ACE3EF0581A8230"; FileName = $pwdir + "\linked_server_config.sql"; FileSize = 1184}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "81FEFECB0F45598AE8A71511E025AD62439307CBA2FD7F71265C7B3E59008987BD0C2434906D43892CCDB7F38B49E9D0AA0842A24251D3FE4C6CFFB0C188E2BF"; FileName = $pwdir + "\MiscPssdiagInfo.sql"; FileSize = 17128}        
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "218F71ECDA1075B4D2B5785A94EF43569306BBDB026C163DFEAF33F960F802D13C65F1BC103CC2978F497A2EF5EA972EE89940C807188FC7366E11A1C30DB2D9"; FileName = $pwdir + "\MSDiagProcs.sql"; FileSize = 194123}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "9789564CA007738B53D6CE21E6065A3D57D3E5A85DE85D32EC1456ED5A79CB1FA0265351FE402D266D6E90E31761DCED208AAA98EDA8BBC24AC25CF7819287D5"; FileName = $pwdir + "\Query Store.sql"; FileSize = 4870}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "7216F9591ECB3C38BD962C146E57800687244B1C0E8450157E21CF5922BBBF92BB8431A814E0F5DF68933623DD76F9E4486A5D20162F58C232B8116920C252C7"; FileName = $pwdir + "\Profiler Traces.sql"; FileSize = 3601}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "42BE545BC8D902A9D43146ACFC8D6A164242B567996C992D57CFBC6660B4E08051E7E687E2D140DAE5B17A8EEE652CFBD3904EC385702A2B8B666A980AE3C982"; FileName = $pwdir + "\Repl_Metadata_Collector.sql"; FileSize = 23414}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "3659F226CD6CFD723D6137BDFA4570F7ACD35255E3DDA90653D57A26781D61CCD2FC1A984EDB774E2C377E44C230A412A9EEF93D8EC9CFA72DE2479D64153F92"; FileName = $pwdir + "\SQL Server Perf Stats Snapshot.sql"; FileSize = 34961}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "325C084DEFC12C19224ABA31484EA42AC3144A13BA534F7163965837CE9D98B3D69B89C7D037F8CE72D7C073F34B83C55E2E6234BA590E58067EEDD5BE1CDA8D"; FileName = $pwdir + "\SQL Server Perf Stats.sql"; FileSize = 69524}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "6159E67BD8E7EF981AFC72D574785548550A7D5CF9367697E6804E6731544F5930A5298D4D8446BAE254A5DB881E60394B884CF9D61BDD11266219A31FC42186"; FileName = $parentdir + "\SQL_LogScout.cmd"; FileSize = 2411}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "D6448617265A9A7DAE8DA8F651642D507AEFEED211BBE0E9F9A4E4C542688129451F2E515BD8702A38D04E662D83DBC43098F4AA4EB58B014F451A66A23CC9E5"; FileName = $pwdir + "\SQL_Server_Mem_Stats.sql"; FileSize = 17163}  
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "BE4C71610793F5912A8D90A7082B4B3A3581DD3AF3FD0C5FB6A08A129AB77B797E72CEFF0EA12486C3FEAA346ECA8394D18AB15B7FF74E1F9B13FA763ABD6278"; FileName = $pwdir + "\SSB_diag.sql"; FileSize = 11040}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "A5AB03D93D7FB256C2DC08B9E5C46CF7D71C403F3074564A66E37DF46F75396BE69593DA2ECA2480073608C5FF215EDE36C6571155BD7EF6B2282C7888EF9401"; FileName = $pwdir + "\TempDB_and_Tran_Analysis.sql"; FileSize = 9054}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "26FB26FBC977B8DD1D853CBE3ABD9FFAA87743CF7048F5E6549858422749B9BD8D6F2CA1AFE35C3A703407E252D8F3CDC887460D2400E69063E99E9E76D4AFFB"; FileName = $pwdir + "\xevent_AlwaysOn_Data_Movement.sql"; FileSize = 23164}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "4EE3B0EE6CEA79CA9611489C2A351A7CCB27D3D5AD2691BE6380BF9C2D6270EE0CFC639B584A2307856384E7AA3B08462BCEA288D954786576DAFC4346670376"; FileName = $pwdir + "\xevent_backup_restore.sql"; FileSize = 1178}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "DE42C1F05E42FF67BBE576EA8B8ADF443DD2D889CBE34F50F4320BE3DC793AF88F5DE13FDC46147CA69535691CC78ADB89463602F5364ED332F6F09A254B7948"; FileName = $pwdir + "\xevent_core.sql"; FileSize = 8134}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "0BB73E8C889E80E8469E5F79F212399EBD50E13DAD39178B75E5578C5CD8E9EE3DCFE0B2D707423765DE8A215FEA9BBC389F30301071B41A5BD5AFCC1187A5DD"; FileName = $pwdir + "\xevent_detailed.sql"; FileSize = 27710}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "C072CDC86FB9332246B2C7587D3DB2FB8755EA1BBBEE2F3A422FFDD672852CF832D6B2000F9F3FC81CEF46DC677DC0CE1D8AA8834DAF9B3A038228943E059F20"; FileName = $pwdir + "\xevent_general.sql"; FileSize = 23119})

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
