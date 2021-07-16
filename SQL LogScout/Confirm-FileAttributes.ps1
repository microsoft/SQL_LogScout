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

    $expectedFileAttributes = @(
         [PSCustomObject]@{Algorithm = "SHA512"; Hash = "CF36F43EDA1E12A3067A4A6FD60CF3C498B28A8A8D55AD5C5B06081CA81623BE3462603071ECFC5A30F37962C26180A8420E3A27833FB43081526F8D830ED75A"; FileName = ".\AlwaysOnDiagScript.sql"; FileSize = 15584}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "4E2E0C0018B1AE4E6402D5D985B71E03E8AECBB9DA3145E63758343AEAC234E3D4988739CCE1AC034DDA7CE77482B27FB5C2A7A4E266E9C283F90593A1B562A2"; FileName = ".\ChangeDataCapture.sql"; FileSize = 4672}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "14191A35B305FDB25E8DC2ED5592BB7046E350EFA5039624440A8A0DC8BC9EC09EDA1CC1DC2D952CF94CC47D436B87149EBAAF1908AD9C9CB912586807E2A40C"; FileName = ".\Change_Tracking.sql"; FileSize = 4758}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "A5D2B75290F953A4F184EF700712C31580AC835ADD4D4A9D84C9D202FC04999E69933604C3BC8E05D2B3C4497675959B61BC2AD538518966516FE0AF52FFE5AD"; FileName = ".\collecterrorlog.sql"; FileSize = 361}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "9A79F730D168CEC6F34D26770E1AD3CB3AA9D700B210E6AC26A594BFC76DBFC03692C3F3200E5DBBA6F3D1B10B41C002A87A65F028C97873F97A320AE8933424"; FileName = ".\HighCPU_perfstats.sql"; FileSize = 5181}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "804B3E27309C23E9530BF475DBD8DA52D1DFA334D7A118DE66B77E4E8182BA8FAC1F938C2FDC1D4CB11F73295354ADEECC33075BF7B87F2C505C03C1BB8E86FB"; FileName = ".\linked_server_config.sql"; FileSize = 3638}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "9AE087048F14AA8BB0A42E7088486EB3343EC302E0D81E4EEF0C12C1858658AE6CE8855F8BF289C4A1EA8EA00103025685679A4BDDF9521007077CF1024D6489"; FileName = ".\LogmanConfig.txt"; FileSize = 4217}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "D3294F7FA085109E435A6CC6E1018E8791AB700E17862C88A81CB4A11B3500740AAC94B12AA80C32A796687A7324FE92EFFFCB74E5DD0DFFD2CA1BEC1C7C8934"; FileName = ".\MiscPssdiagInfo.sql"; FileSize = 21611}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "218F71ECDA1075B4D2B5785A94EF43569306BBDB026C163DFEAF33F960F802D13C65F1BC103CC2978F497A2EF5EA972EE89940C807188FC7366E11A1C30DB2D9"; FileName = ".\MSDiagProcs.sql"; FileSize = 194123}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "419373C05FAF27C08C92F3C93333567667B50D7322AAF910327E0F9D071016CF354644B925C30A19A13CCFEDF261834302F9115466C0D8DA81BC40674402025B"; FileName = ".\Profiler Traces.sql"; FileSize = 2415}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "5D2E56C8F1D88F21AEC00A82C6225AC7D80CD0496E30F85592719187F748631B2C61D509292B1CAA95B39B7BAF55CAB2740FE26A839E3AE171A2FC0E500671BB"; FileName = ".\Query Store.sql"; FileSize = 3271}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "B63DF8FEDCD904738B406F9ABCA35352FFC4E71B882F6145F00B3C205ACDC8506DA3C787762FF05B051DBDE35B915248B1FA05E7BF7B6DB2F825726AC5026BC1"; FileName = ".\Repl_Metadata_Collector.sql"; FileSize = 53273}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "4307558EDCD85B40382194411D3502608C412325DC5CE80DFA883A0C6A329E61618453A5A98495DFBF66BE03905A80406478A903B2A88686284D7E0C74EF219F"; FileName = ".\SQL Server Perf Stats Snapshot.sql"; FileSize = 25666}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "FA61A62C52D10F2C79BBFFA0151D74B129476599A51584BE75FF8E4A4E7F678420B828C381209C3F04B7CE848F89F0F6A1034FA9AA95B6894E1EDAB8572F03ED"; FileName = ".\SQL Server Perf Stats.sql"; FileSize = 68781}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "862D3B98BE00A1902B17B364DAB12D4AC41F81BDCC6D22382845535832678DEB60B90D3319CC718C6232F6FCB7C6F0D9977D0F7AB927C0440D172D3ADF3554B6"; FileName = ".\SQL_LogScout.cmd"; FileSize = 1587}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "AB735636B1473787DAEB508CB6F64327D6409F5DB0CA7E40EAFB05047D291EA07F24AD2D96ED9A61E0690DB6FEB59554ED4B50F225DE065C4A65772724F0DE74"; FileName = ".\SQL_Server_Mem_Stats.sql"; FileSize = 16571}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "5CB4E3F3B3FD99E90603D84AD8C18C6A06E663210C2FD6FB42718431CACB7F84E5DFA3B172C1E065F70504B415D4EE9AAB2CFE0333A9CD28381D73E39C77A781"; FileName = ".\SSB_diag.sql"; FileSize = 10531}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "542C1B4F4A461370726AF54BC738731A30E9E894F6D191EAD8A65EEA3F44713BA4C88F09FBB4EFAC44DFA111990844EBA304B65DE57557953192606729A69942"; FileName = ".\TempDBAnalysis.sql"; FileSize = 1622}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "99735D9F10B8B1FB47677345257E344EFBEFB8DC0451206245691F062BAA212C2E1E0EE25046368D9C3B36C1F1408DD8ACC7C491F4D66D2F07DB539D4CFB1C0B"; FileName = ".\xevent_AlwaysOn_Data_Movement.sql"; FileSize = 23198}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "DDBCE9AFA4635677D7B3F7FD3F86C04A59B8AC7EDD5ED8DB5AE10BEFD73F03F6D287984EC2B1B39F55E39DAC7E0F2C2384BB759131BA292537526D268438464E"; FileName = ".\xevent_backup_restore.sql"; FileSize = 1178}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "F92ADC91C074425145EC3F9C7577EA283E293BA0FD73BB731616A34CBC854151824981B3D536E070D7DE37AAB2D7EFE90A923BA4D29B3059F2CE9B78BF465BC0"; FileName = ".\xevent_core.sql"; FileSize = 8142}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "F387D34B7FA0C00C9EBDE37D21AA90B7A08A45FFDB67D5D9AB5BEE4EDF579DC98BD1E721E5BFDFCFC4D4B956591BA3F68E8A1F64BF1B53CEEA3B1505F07AA3DC"; FileName = ".\xevent_detailed.sql"; FileSize = 25034}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "AE0B7C85AF903632EC3D221BC51FF0E56A00270A8482454E75A9A4783E61AA8DACD1F0FEB231CF651F51B5B0CE32E60DEE2245768E5AE64A6EC3B1D7F001F7A2"; FileName = ".\xevent_general.sql"; FileSize = 20469}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "45833A77D15E7C6F2BF6849DC3469B637845D8465E431BFFBBEC78A90CEB7D3E2859FB83BD688EF75A895A232BAE01D97D10E6CB5DDB30453B311682EEDF534C"; FileName = ".\High_IO_Perfstats.sql"; FileSize = 6435}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "FE30CCC3613556B7BAC72EA243D540AE352CE22EA5FCF6BD2904C392CE2D9256DBFD98705BA472DFCAF2D2D7186C0BEC1772D6ADAF850DA6E79C6217525EA67D"; FileName = ".\StartNetworkTrace.bat"; FileSize = 178}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "D0286430C1F032486657D574306273CFA19C0972B751A3D1F389AC8301C62294F94BC19318D3D0A96E0B1D10538F4336D22B4C97BC7D4CFC25C70C8A2CF5676B"; FileName = ".\StopNetworkTrace.bat"; FileSize = 55}
    )

    # global array to keep a System.IO.FileStream object for each of the non-Powershell files
    # files are opened with Read sharing before being hashed
    # files are kept opened until SQL LogScout terminates preventing changes to them
    [System.Collections.ArrayList]$Global:hashedFiles = [System.Collections.ArrayList]::new()

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
            Write-LogError "   Atual File " $fileHash.Algorithm " Hash: " $fileHash.Hash
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

function Get-FileAttributes(){
<#
    .SYNOPSIS
        Display string for $expectedFileAttributes.
    .DESCRIPTION
        This is to be used only when some script is changed and we need to refresh the file attributes in Confirm-FileAttributes.ps1
    .EXAMPLE
        . .\Confirm-FileAttributes.ps1
        Get-FileAttributes
#>

    [int]$fileCount = 0
    [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("`$expectedFileAttributes = @(")
    
    foreach($file in (Get-ChildItem -Path . -File)){
        
        # Powershell files are signed, therefore no need to hash-compare them
        # "Get-ChildItem -Exclude *.ps1 -File" yields zero results, therefore we skip .PS1 files with the following IF
        if (".ps1" -ne $file.Extension){
            
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
            $fileName = ".\" + $file.Name
            $fileSize = [string]$file.Length

            [void]$sb.AppendLine("[PSCustomObject]@{Algorithm = `"$algorithm`"; Hash = `"$hash`"; FileName = `"$fileName`"; FileSize = $fileSize}")

        }

    }

    [void]$sb.AppendLine(")")
    
    Write-Host $sb.ToString()
}