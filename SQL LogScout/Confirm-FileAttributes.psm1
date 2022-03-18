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
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "073C0BBAB692A88387AF355A0CEC7A069B7F6C442A8DABF4EFC46E54ACEC7B569B866778A66FE1ADEBF8AD4F30EF3EAF7EF32DD436BC023CD4BC3AD52923AB9F"; FileName = ".\Change_Tracking.sql"; FileSize = 5110}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "A5D2B75290F953A4F184EF700712C31580AC835ADD4D4A9D84C9D202FC04999E69933604C3BC8E05D2B3C4497675959B61BC2AD538518966516FE0AF52FFE5AD"; FileName = ".\collecterrorlog.sql"; FileSize = 361}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "2D349AE6F6AEFB934BB93451B99148137DB1A550831EF661945B361FE11F92E6FF73F540DCCBF87BB22AD386053042163227BEB43B9620F10BD966F55C6CD304"; FileName = ".\HighCPU_perfstats.sql"; FileSize = 5360}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "A7C01702151F50B171161FA988A6D43A9E502E1FBD63EC315E97E92E597F2B04EE5260866EB9E7454743F9DD092C91932F39B2AB562B4A5A17FBAF2D61D939C9"; FileName = ".\linked_server_config.sql"; FileSize = 3803}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "9AE087048F14AA8BB0A42E7088486EB3343EC302E0D81E4EEF0C12C1858658AE6CE8855F8BF289C4A1EA8EA00103025685679A4BDDF9521007077CF1024D6489"; FileName = ".\LogmanConfig.txt"; FileSize = 4217}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "E6CD30ECDC3FD177C6A88C3954BFDE9C36CC2BB97C41A58E3126FB73EC63C1489C182556E28A0F259FB20CC3F6065BB883210E9BAACDB6B5105A6CA3E3CE6FC0"; FileName = ".\MiscPssdiagInfo.sql"; FileSize = 21884}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "218F71ECDA1075B4D2B5785A94EF43569306BBDB026C163DFEAF33F960F802D13C65F1BC103CC2978F497A2EF5EA972EE89940C807188FC7366E11A1C30DB2D9"; FileName = ".\MSDiagProcs.sql"; FileSize = 194123}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "E406F0C68E781A77BDED5720DDA57C8EED7D7270DFAA5FFAED520749B7D8DC0C8B3E4D6ACB47EF36C1DB4B22C62C9B2AE8627E39319375D6D68375C145FC5142"; FileName = ".\Profiler Traces.sql"; FileSize = 2749}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "5D2E56C8F1D88F21AEC00A82C6225AC7D80CD0496E30F85592719187F748631B2C61D509292B1CAA95B39B7BAF55CAB2740FE26A839E3AE171A2FC0E500671BB"; FileName = ".\Query Store.sql"; FileSize = 3271}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "295825B1F30E7C770DC51666FD8FB8325C8F75F1475024CCA2418A39005886B3B92FB40FFAD47143019B4709769F393ABE9C918A744AD17A8C5FE05295718164"; FileName = ".\Readme.htm"; FileSize = 63868}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "B63DF8FEDCD904738B406F9ABCA35352FFC4E71B882F6145F00B3C205ACDC8506DA3C787762FF05B051DBDE35B915248B1FA05E7BF7B6DB2F825726AC5026BC1"; FileName = ".\Repl_Metadata_Collector.sql"; FileSize = 53273}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "F16FE5055F1E876B0771CA71190713A2E1578CBA56754E04E49CEA80CD76261A2AB8F20885F451FEA3FA9AE2078F4492EBE9DD73A888CF94E4E747F38BAEFF37"; FileName = ".\SQL Server Perf Stats Snapshot.sql"; FileSize = 29682}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "FA61A62C52D10F2C79BBFFA0151D74B129476599A51584BE75FF8E4A4E7F678420B828C381209C3F04B7CE848F89F0F6A1034FA9AA95B6894E1EDAB8572F03ED"; FileName = ".\SQL Server Perf Stats.sql"; FileSize = 68781}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "31E499F8E6F660DF1501A99D05B5A701AB77A66B0878C64A4D2EDF182759059A5EB7468E78CF036F1AE16F47B3FB4DD3E713E8624213FF3DA573327E061860B6"; FileName = ".\SQL_LogScout.cmd"; FileSize = 2398}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "AB735636B1473787DAEB508CB6F64327D6409F5DB0CA7E40EAFB05047D291EA07F24AD2D96ED9A61E0690DB6FEB59554ED4B50F225DE065C4A65772724F0DE74"; FileName = ".\SQL_Server_Mem_Stats.sql"; FileSize = 16571}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "5CB4E3F3B3FD99E90603D84AD8C18C6A06E663210C2FD6FB42718431CACB7F84E5DFA3B172C1E065F70504B415D4EE9AAB2CFE0333A9CD28381D73E39C77A781"; FileName = ".\SSB_diag.sql"; FileSize = 10531}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "542C1B4F4A461370726AF54BC738731A30E9E894F6D191EAD8A65EEA3F44713BA4C88F09FBB4EFAC44DFA111990844EBA304B65DE57557953192606729A69942"; FileName = ".\TempDBAnalysis.sql"; FileSize = 1622}
        ,[PSCustomObject]@{Algorithm = "SHA512"; Hash = "E9F2DE7EDE1AF7DCC980F8661FCCCA817896BB9220001FB2C4D1A40703096B1E94BD2C39EDDC147FA6D9269835C83AA8714597BBD8C56B3A5C93F1F268268342"; FileName = ".\xevent_AlwaysOn_Data_Movement.sql"; FileSize = 23224}
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
# SIG # Begin signature block
# MIInpwYJKoZIhvcNAQcCoIInmDCCJ5QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB0pjlLHcGRSMJY
# SS5OqUreCcEGCtxZWN/LYfB4yds3eKCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
# 3pbexW7MAAAAAAJTMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMzAwWhcNMjIwOTAxMTgzMzAwWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDLhxHwq3OhH+4J+SX4qS/VQG8HybccH7tnG+BUqrXubfGuDFYPZ29uCuHfQlO1
# lygLgMpJ4Geh6/6poQ5VkDKfVssn6aA1PCzIh8iOPMQ9Mju3sLF9Sn+Pzuaie4BN
# rp0MuZLDEXgVYx2WNjmzqcxC7dY9SC3znOh5qUy2vnmWygC7b9kj0d3JrGtjc5q5
# 0WfV3WLXAQHkeRROsJFBZfXFGoSvRljFFUAjU/zdhP92P+1JiRRRikVy/sqIhMDY
# +7tVdzlE2fwnKOv9LShgKeyEevgMl0B1Fq7E2YeBZKF6KlhmYi9CE1350cnTUoU4
# YpQSnZo0YAnaenREDLfFGKTdAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUlZpLWIccXoxessA/DRbe26glhEMw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzQ2NzU5ODAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AKVY+yKcJVVxf9W2vNkL5ufjOpqcvVOOOdVyjy1dmsO4O8khWhqrecdVZp09adOZ
# 8kcMtQ0U+oKx484Jg11cc4Ck0FyOBnp+YIFbOxYCqzaqMcaRAgy48n1tbz/EFYiF
# zJmMiGnlgWFCStONPvQOBD2y/Ej3qBRnGy9EZS1EDlRN/8l5Rs3HX2lZhd9WuukR
# bUk83U99TPJyo12cU0Mb3n1HJv/JZpwSyqb3O0o4HExVJSkwN1m42fSVIVtXVVSa
# YZiVpv32GoD/dyAS/gyplfR6FI3RnCOomzlycSqoz0zBCPFiCMhVhQ6qn+J0GhgR
# BJvGKizw+5lTfnBFoqKZJDROz+uGDl9tw6JvnVqAZKGrWv/CsYaegaPePFrAVSxA
# yUwOFTkAqtNC8uAee+rv2V5xLw8FfpKJ5yKiMKnCKrIaFQDr5AZ7f2ejGGDf+8Tz
# OiK1AgBvOW3iTEEa/at8Z4+s1CmnEAkAi0cLjB72CJedU1LAswdOCWM2MDIZVo9j
# 0T74OkJLTjPd3WNEyw0rBXTyhlbYQsYt7ElT2l2TTlF5EmpVixGtj4ChNjWoKr9y
# TAqtadd2Ym5FNB792GzwNwa631BPCgBJmcRpFKXt0VEQq7UXVNYBiBRd+x4yvjqq
# 5aF7XC5nXCgjbCk7IXwmOphNuNDNiRq83Ejjnc7mxrJGMIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGXgwghl0AgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIOi2
# RSVznNd+691i81YCmgOqa8ftnW+IXOo1/g15zVdtMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQBTg/O0ew2dA9o6QbSzASQqIto0nBw62+kg
# sktNlPAwcL0z2Uxp7/4Y3SVvUZls73H1Q9WCtlq5S4ALevul0JYtd3Sf8plb07mW
# Z//TOPYSq1e8zs6MCchn79TCGjZ/cs7BYA5e3JpNf7qgEoXi+b/HomxXxxFErF8Q
# U+IsqgP/KkKz03wL64LwpaBvELzUfEuyvjRaQ7B8iAoBty3hffdFh91eShP9t8Qc
# lKoeaJcHyvl8wsSjP1G3heozgiOXt45ATwd3kDrEYuR1JbhcVDBIthX+jeD3kJFI
# x4dubcbeY1Tk2os5/G3IuV5EcWKVtuYcEIZFTxzi2YZID5P+1iIuoYIXADCCFvwG
# CisGAQQBgjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIHleRcDcxhWYGyVIuc19AYTRDelizLcd
# 8NjFXgNBdi25AgZiFl7b9QIYEzIwMjIwMzAxMTI1MDEwLjU3M1owBIACAfSggdCk
# gc0wgcoxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNV
# BAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOkU1QTYtRTI3Qy01OTJFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloIIRVzCCBwwwggT0oAMCAQICEzMAAAGVt/wN1uM3MSUA
# AQAAAZUwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwHhcNMjExMjAyMTkwNTEyWhcNMjMwMjI4MTkwNTEyWjCByjELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RTVBNi1F
# MjdDLTU5MkUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Uw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCfbUEMZ7ZLOz9aoRCeJL4h
# hT9Q8JZB2xaVlMNCt3bwhcTI5GLPrt2e93DAsmlqOzw1cFiPPg6S5sLCXz7LbbUQ
# pLha8S4v2qccMtTokEaDQS+QJErnAsl6VSmRvAy0nlj+C/PaZuLb3OzY0ARw7UeC
# ZLpyWPPH+k5MdYj6NUDTNoXqbzQHCuPs+fgIoro5y3DHoO077g6Ir2THIx1yfVFE
# t5zDcFPOYMg4yBi4A6Xc3hm9tZ6w849nBvVKwm5YALfH3y/f3n4LnN61b1wzAx3Z
# CZjf13UKbpE7p6DYJrHRB/+pwFjG99TwHH6uXzDeZT6/r6qH7AABwn8fpYc1Tmle
# FY8YRuVzzjp9VkPHV8VzvzLL7QK2kteeXLL/Y4lvjL6hzyOmE+1LVD3lEbYho1zC
# t+F7bU+FpjyBfTC4i/wHsptb218YlbkQt1i1B6llmJwVFwCLX7gxQ48QIGUacMy8
# kp1+zczY+SxlpaEgNmQkfc1raPh9y5sMa6X48+x0K7B8OqDoXcTiECIjJetxwtuB
# lQseJ05HRfisfgFm09kG7vdHEo3NbUuMMBFikc4boN9Ufm0iUhq/JtqV0Kwrv9Cv
# 3ayDgdNwEWiL2a65InEWSpRTYfsCQ03eqEh5A3rwV/KfUFcit+DrP+9VcDpjWRsC
# okZv4tgn5qAXNMtHa8NiqQIDAQABo4IBNjCCATIwHQYDVR0OBBYEFKuX02ICFFdX
# grcCBmDJfH5v/KkXMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8G
# A1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBs
# BggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# DQYJKoZIhvcNAQELBQADggIBAOCzNt4fJ+jOvQuq0Itn37IZrYNBGswAi+IAFM3Y
# GK/wGQlEncgjmNBuac95W2fAL6xtFVfMfkeqSLMLqoidVsU9Bm4DEBjaWNOT9uX/
# tcYiJSfFQM0rDbrl8V4nM88RZF56G/qJW9g5dIqOSoimzKUt/Q7WH6VByW0sar5w
# GvgovK3qFadwKShzRYcEqTkHH2zip5e73jezPHx2+taYqJG5xJzdDErZ1nMixRja
# Hs3KpcsmZYuxsIRfBYOJvAFGymTGRv5PuwsNps9Ech1Aasq84H/Y/8xN3GQj4P3M
# iDn8izUBDCuXIfHYk39bqnaAmFbUiCby+WWpuzdk4oDKz/sWwrnsoQ72uEGVEN7+
# kyw9+HSo5i8l8Zg1Ymj9tUgDpVUGjAduoLyHQ7XqknKmS9kJSBKk4okEDg0Id6Le
# KLQwH1e4aVeTyUYwcBX3wg7pLJQWvR7na2SGrtl/23YGQTudmWOryhx9lnU7KBGV
# /aNvz0tTpcsucsK+cZFKDEkWB/oUFVrtyun6ND5pYZNj0CgRup5grVACq/Agb+EO
# GLCD+zEtGNop4tfKvsYb64257NJ9XrMHgpCib76WT34RPmCBByxLUkHxHq5zCyYN
# u0IFXAt1AVicw14M+czLYIVM7NOyVpFdcB1B9MiJik7peSii0XTRdl5/V/KscTaC
# BFz3MIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0B
# AQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAG
# A1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAw
# HhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOTh
# pkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xP
# x2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ
# 3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOt
# gFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYt
# cI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXA
# hjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0S
# idb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSC
# D/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEB
# c8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh
# 8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8Fdsa
# N8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkr
# BgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q
# /y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBR
# BgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAP
# BgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjE
# MFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEF
# BQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEB
# CwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnX
# wnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOw
# Bb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jf
# ZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ
# 5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+
# ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgs
# sU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6
# OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p
# /cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6
# TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784
# cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3
# AgEBMIH4oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYD
# VQQLEx1UaGFsZXMgVFNTIEVTTjpFNUE2LUUyN0MtNTkyRTElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA0Y+CyLez
# GgVHWFNmKI1LuE/hY6uggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQUFAAIFAOXIHXkwIhgPMjAyMjAzMDExMjIwMDlaGA8y
# MDIyMDMwMjEyMjAwOVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5cgdeQIBADAK
# AgEAAgIOBgIB/zAHAgEAAgIRrDAKAgUA5clu+QIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBBQUAA4GBAKN1YaQOMdsFywu98vao4DYcpvQj72H7FHSt2IU0JR9ULtWLnUo5
# wh1s0SBXOXA249ayHTi81Bk2j0Sr3Xz7JLJOEZs/+0HOt7GP34DIVmErFyVG9Vf/
# Cwa8FXJXk3iU/u3JXFyUr3UaRhW7s4+ACSz2L8p5sz8+SKDnRnvoKVmkMYIEDTCC
# BAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGVt/wN
# 1uM3MSUAAQAAAZUwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsq
# hkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg//VrkEfnOIDeqijVjOi6XgGUsdya
# 88SK3TkJm2JS4PQwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBc5kvhjZAL
# e2mhIz/Qd7keVOmA/cC1dzKZT4ybLEkCxzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAABlbf8DdbjNzElAAEAAAGVMCIEIEoh/phCqCUc
# IPPiyGWCEdRvsvakFpcxPBkeGlu/JAB3MA0GCSqGSIb3DQEBCwUABIICAGZ7i1aI
# yZUcjKhM2cfG5JPGdrx8NWMy9j4eyhoXTTvKyFx3bvyrNUU0IUPc0aL1yRONy10l
# a4qemU4BQFy2fe7JNdWv1uPE9QAQeFUZk2GPz2iLDensPCmxhX81fdz2AurYOWwk
# dp5zu5AokaIq6xuG+vl4fpR50VhzBb0AFgx65bG5cyfj6OQHr00/qNQPpOVOnYfQ
# aT7SholLqmcAJ7clm2HdX4QBRLSB40osoIWiJyY8R8xHsPSPfdglJstJXO9ibtRq
# foM6J+Nkx2ZafHGZE0taJQnUdC1OhTQLtmC2F0oHAer15ok0CueE+VaC5rlmEsJW
# iDXum+6AY0087biL0olE55c289ESMOco1fqORouXsIjPQXwhtNaklTylFFXGd/jK
# 1rcyXL4zm91Z0sV2HIZoXxJVs5o1kQut4PYVzy18bu6gMr6gdHXNlCtywhcEL3sH
# DmUMRhtIIhJNynSlqTLxGlK2RcRlpks4TvdMMw9VguVvfNeSH9Afk7GskIshP3In
# 3z6Rp475rHQCToLlIyG2nQp9KJWAqNWJirmCMhOPfGirOI3jqo/spKas44iEGppv
# pKcRjpUJsA0x9zJoNo6vcQdtoklBrnvqi4fBDcl4v1thN300AUIqIbZZapZqXFP7
# eR74ojnPn6mf8QJ0VEtxggE5vphvvESOq7Yl
# SIG # End signature block
