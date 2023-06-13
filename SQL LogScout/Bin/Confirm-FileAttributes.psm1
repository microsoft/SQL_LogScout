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

    $expectedFileAttributes = @(
         [PSCustomObject]@{Algorithm = "SHA512"; Hash = "D3154D5ADA90F997186CA2E42EC29EDD7A19A1484477026D79C9803AF4822EC8D91A6D8C1878826713744C452804FAAFF9BE99979F0F496F176F74CFBA5CC06D"; FileName = $pwdir + ".\AlwaysOnDiagScript.sql"; FileSize = 19874}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "4E2E0C0018B1AE4E6402D5D985B71E03E8AECBB9DA3145E63758343AEAC234E3D4988739CCE1AC034DDA7CE77482B27FB5C2A7A4E266E9C283F90593A1B562A2"; FileName = $pwdir + ".\ChangeDataCapture.sql"; FileSize = 4672}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "073C0BBAB692A88387AF355A0CEC7A069B7F6C442A8DABF4EFC46E54ACEC7B569B866778A66FE1ADEBF8AD4F30EF3EAF7EF32DD436BC023CD4BC3AD52923AB9F"; FileName = $pwdir + ".\Change_Tracking.sql"; FileSize = 5110}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "A5D2B75290F953A4F184EF700712C31580AC835ADD4D4A9D84C9D202FC04999E69933604C3BC8E05D2B3C4497675959B61BC2AD538518966516FE0AF52FFE5AD"; FileName = $pwdir + ".\collecterrorlog.sql"; FileSize = 361}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "2D349AE6F6AEFB934BB93451B99148137DB1A550831EF661945B361FE11F92E6FF73F540DCCBF87BB22AD386053042163227BEB43B9620F10BD966F55C6CD304"; FileName = $pwdir + ".\HighCPU_perfstats.sql"; FileSize = 5360}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "45833A77D15E7C6F2BF6849DC3469B637845D8465E431BFFBBEC78A90CEB7D3E2859FB83BD688EF75A895A232BAE01D97D10E6CB5DDB30453B311682EEDF534C"; FileName = $pwdir + ".\High_IO_Perfstats.sql"; FileSize = 6435}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "824A41667D5DAA02729BB469E97701A41A09462EBBEDD2F5851061DC25465DC4422AD52DEDE1B5321FB55D485FDA6DBEE3B6429B303361078ACE3EF0581A8230"; FileName = $pwdir + ".\linked_server_config.sql"; FileSize = 1184}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "61067CF25088C09C0F0B9EE24BBCAE480488AE9B318B34313F06B151CF2A2BE3D80EB0A4B9D5A2B5A6F790C49BC728092550AB15DC087CC381B593EA6D02B07C"; FileName = $pwdir + ".\MiscPssdiagInfo.sql"; FileSize = 14888}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "218F71ECDA1075B4D2B5785A94EF43569306BBDB026C163DFEAF33F960F802D13C65F1BC103CC2978F497A2EF5EA972EE89940C807188FC7366E11A1C30DB2D9"; FileName = $pwdir + ".\MSDiagProcs.sql"; FileSize = 194123}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "E406F0C68E781A77BDED5720DDA57C8EED7D7270DFAA5FFAED520749B7D8DC0C8B3E4D6ACB47EF36C1DB4B22C62C9B2AE8627E39319375D6D68375C145FC5142"; FileName = $pwdir + ".\Profiler Traces.sql"; FileSize = 2749}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "5D2E56C8F1D88F21AEC00A82C6225AC7D80CD0496E30F85592719187F748631B2C61D509292B1CAA95B39B7BAF55CAB2740FE26A839E3AE171A2FC0E500671BB"; FileName = $pwdir + ".\Query Store.sql"; FileSize = 3271}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "42BE545BC8D902A9D43146ACFC8D6A164242B567996C992D57CFBC6660B4E08051E7E687E2D140DAE5B17A8EEE652CFBD3904EC385702A2B8B666A980AE3C982"; FileName = $pwdir + "\Repl_Metadata_Collector.sql"; FileSize = 23414}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "320808D3A6D4B981A54B3B0D2F8DA243D8C0691DC0726A0EFD3B583F5F98EC6026DBBC5B2D4156D90599488CF4CFB979C7AAB058A9EFE21AB3A2B5BD33D98B61"; FileName = $pwdir + ".\SQL Server Perf Stats Snapshot.sql"; FileSize = 34771}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "D9963417E2B6DC8D287C246D8D0BB0FE050357153B7301687DD64B344FC0D182EC79EFE26E98A97E8F3E6390803726604FFB639A319A8D9C80A0CC600008D93B"; FileName = $pwdir + ".\SQL Server Perf Stats.sql"; FileSize = 69399}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "31E499F8E6F660DF1501A99D05B5A701AB77A66B0878C64A4D2EDF182759059A5EB7468E78CF036F1AE16F47B3FB4DD3E713E8624213FF3DA573327E061860B6"; FileName = $pwdir + ".\SQL_LogScout.cmd"; FileSize = 2398}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "46BD5A2066A43B03816FAE181C9ECB8653E24C6542F391A3FF74E503C5A0D8485EC0EB8CBAE941D8FF028B7F5DB7124325547F94EDCE566E9486E36149DD1924"; FileName = $pwdir + "\SQL_Server_Mem_Stats.sql"; FileSize = 16909}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "5CB4E3F3B3FD99E90603D84AD8C18C6A06E663210C2FD6FB42718431CACB7F84E5DFA3B172C1E065F70504B415D4EE9AAB2CFE0333A9CD28381D73E39C77A781"; FileName = $pwdir + ".\SSB_diag.sql"; FileSize = 10531}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "FE30CCC3613556B7BAC72EA243D540AE352CE22EA5FCF6BD2904C392CE2D9256DBFD98705BA472DFCAF2D2D7186C0BEC1772D6ADAF850DA6E79C6217525EA67D"; FileName = $pwdir + ".\StartNetworkTrace.bat"; FileSize = 178}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "D0286430C1F032486657D574306273CFA19C0972B751A3D1F389AC8301C62294F94BC19318D3D0A96E0B1D10538F4336D22B4C97BC7D4CFC25C70C8A2CF5676B"; FileName = $pwdir + ".\StopNetworkTrace.bat"; FileSize = 55}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "A5AB03D93D7FB256C2DC08B9E5C46CF7D71C403F3074564A66E37DF46F75396BE69593DA2ECA2480073608C5FF215EDE36C6571155BD7EF6B2282C7888EF9401"; FileName = $pwdir + ".\TempDB_and_Tran_Analysis.sql"; FileSize = 9054}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "26FB26FBC977B8DD1D853CBE3ABD9FFAA87743CF7048F5E6549858422749B9BD8D6F2CA1AFE35C3A703407E252D8F3CDC887460D2400E69063E99E9E76D4AFFB"; FileName = $pwdir + ".\xevent_AlwaysOn_Data_Movement.sql"; FileSize = 23164}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "DDBCE9AFA4635677D7B3F7FD3F86C04A59B8AC7EDD5ED8DB5AE10BEFD73F03F6D287984EC2B1B39F55E39DAC7E0F2C2384BB759131BA292537526D268438464E"; FileName = $pwdir + ".\xevent_backup_restore.sql"; FileSize = 1178}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "F92ADC91C074425145EC3F9C7577EA283E293BA0FD73BB731616A34CBC854151824981B3D536E070D7DE37AAB2D7EFE90A923BA4D29B3059F2CE9B78BF465BC0"; FileName = $pwdir + ".\xevent_core.sql"; FileSize = 8142}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "0BB73E8C889E80E8469E5F79F212399EBD50E13DAD39178B75E5578C5CD8E9EE3DCFE0B2D707423765DE8A215FEA9BBC389F30301071B41A5BD5AFCC1187A5DD"; FileName = $pwdir + ".\xevent_detailed.sql"; FileSize = 27710}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "C072CDC86FB9332246B2C7587D3DB2FB8755EA1BBBEE2F3A422FFDD672852CF832D6B2000F9F3FC81CEF46DC677DC0CE1D8AA8834DAF9B3A038228943E059F20"; FileName = $pwdir + ".\xevent_general.sql"; FileSize = 23119})

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

    foreach($file in (Get-ChildItem -Path . -File -Filter $file_name)){

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
            $fileName = "`$pwdir `+ `"`\" + $file.Name + "`""
            $fileSize = [string]$file.Length

            [void]$sb.AppendLine("[PSCustomObject]@{Algorithm = `"$algorithm`"; Hash = `"$hash`"; FileName = $fileName; FileSize = $fileSize}")

        }

    }

    [void]$sb.AppendLine(")")

    Write-Host $sb.ToString()
}
