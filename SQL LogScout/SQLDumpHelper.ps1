[CmdletBinding()]
param (
    [Parameter(Position=0, Mandatory=$true)]
    [string] $DumpOutputFolder = ".",
    [Parameter(Position=1, Mandatory=$true)]
    [string] $InstanceOnlyName = ""
)

$isInt = $false
$isIntValDcnt = $false
$isIntValDelay = $false
$SSISIdInt = 0
$NumFoler =""
$OneThruFour = "" 
$SqlDumpTypeSelection = ""
$SSASDumpTypeSelection = ""
$SSISDumpTypeSelection = ""
$SQLNumfolder=0
$SQLDumperDir=""
$OutputFolder= $DumpOutputFolder
$DumpType ="0x0120"
$ValidId
$SharedFolderFound=$false
$YesNo =""
$ProductNumber=""
$ProductStr = ""
$PIDInt = 0

#check for administrator rights
#debugging tools like SQLDumper.exe require Admin privileges to generate a memory dump

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
     Write-Warning "Administrator rights are required to generate a memory dump!`nPlease re-run this script as an Administrator!"
     #break
}



#what product would you like to generate a memory dump
while(($ProductNumber -ne "1") -and ($ProductNumber -ne "2") -and ($ProductNumber -ne "3") -and ($ProductNumber -ne "4") -and ($ProductNumber -ne "5"))
{
    Write-Host "Which product would you like to generate a memory dump of?" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ID   Service/Process"
    Write-Host "--   ----------"
    Write-Host "1    SQL Server"
    Write-Host "2    SSAS (Analysis Services) "
    Write-Host "3    SSIS (Integration Services)"
    Write-Host "4    SSRS (Reporting Services)"
    Write-Host "5    SQL Server Agent"
    Write-Host ""
    $ProductNumber = Read-Host "Enter 1-5>" -CustomLogMessage "Dump Product Console input:"

    if (($ProductNumber -ne "1") -and ($ProductNumber -ne "2") -and ($ProductNumber -ne "3") -and ($ProductNumber -ne "4")-and ($ProductNumber -ne "5"))
    {
        Write-Host ""
        Write-Host "Please enter a valid number from list above!"
        Write-Host ""
        Start-Sleep -Milliseconds 300
    }
}

if ($ProductNumber -eq "1")
{
    # $SqlTaskList has to be an array, so wrapped with @() guarantees an array regardless of number of elemets returned
    $SqlTaskList = @(Tasklist /SVC /FI "imagename eq sqlservr*" /FO CSV | ConvertFrom-Csv)
    $ProductStr = "SQL Server"
    
    # Nothing to do here as SQLLogScout already passes service name correct for SQL Server MSSQLSERVER / MSSQL$INSTANCENAME
}
elseif ($ProductNumber -eq "2")
{
    $SqlTaskList = @(Tasklist /SVC /FI "imagename eq msmdsrv*" /FO CSV | ConvertFrom-Csv)
    $ProductStr = "SSAS (Analysis Services)"

    if (-1 -eq $InstanceOnlyName.IndexOf("`$")){ # default SSAS instance
        $InstanceOnlyName = "MSSQLServerOLAPService"
    } else { # named SSAS instance
        $InstanceOnlyName = "MSOLAP`$" + $InstanceOnlyName.Split("`$")[1]
    }
}
elseif ($ProductNumber -eq "3")
{
    $SqlTaskList = @(Tasklist /SVC /FI "imagename eq msdtssrvr*" /FO CSV | ConvertFrom-Csv)
    $ProductStr = "SSIS (Integration Services)"
    
    $InstanceOnlyName = "MsDtsServer<VERSION>"
}
elseif ($ProductNumber -eq "4")
{
    $SqlTaskList = @(Tasklist /SVC /FI "imagename eq reportingservicesservice*" /FO CSV | ConvertFrom-Csv)
    $ProductStr = "SSRS (Reporting Services)"
    
    if (-1 -eq $InstanceOnlyName.IndexOf("`$")){ # default SSRS instance
        $InstanceOnlyName = "ReportServer"
    } else { # named SSRS instance
        $InstanceOnlyName = "ReportServer`$" + $InstanceOnlyName.Split("`$")[1]
    }
}
elseif ($ProductNumber -eq "5")
{
    $SqlTaskList = @(Tasklist /SVC /FI "imagename eq sqlagent*" /FO CSV | ConvertFrom-Csv)
    $ProductStr = "SQL Server Agent"
    
    if (-1 -eq $InstanceOnlyName.IndexOf("`$")){ # default SQLAgent instance
        $InstanceOnlyName = "SQLSERVERAGENT"
    } else { # named SQLAgent instance
        $InstanceOnlyName = "SQLAgent`$" + $InstanceOnlyName.Split("`$")[1]
    }
}

if (($SqlTaskList.Count -eq 0))
{
    Write-Host "There are curerntly no running instances of $ProductStr. Exiting..." -ForegroundColor Green
    Start-Sleep -Seconds 2
    return
} elseif (("3" -ne $ProductNumber) -and (($SqlTaskList | Where-Object {$_.Services -like "*$InstanceOnlyName"} | Measure-Object).Count -eq 0)) {

    while (($YesNo -ne "y") -and ($YesNo -ne "n"))
    {
        Write-Host "Instance $InstanceOnlyName is not currently running. Would you like to generate a dump of another $ProductStr instance? (Y/N)" -ForegroundColor Yellow
        $YesNo = Read-Host "(Y/N)> "
    
        $YesNo = $YesNo.ToUpper()
        if (($YesNo -eq "Y") -or ($YesNo -eq "N") )
        {
            break
        }
        else
        {
            Write-Host "Not a valid 'Y' or 'N' response"
        }
    }
    
    if ($YesNo -eq "Y")
    {
        
        Write-LogInformation "Discovered the following $ProductStr Service(s)`n"
        Write-LogInformation ""
        Write-LogInformation "ID	Service Name"
        Write-LogInformation "--	----------------"

        for($i=0; $i -lt $SqlTaskList.Count;$i++)
        {
            Write-LogInformation $i "	" $SqlTaskList[$i].Services
        }
        
        #check input and make sure it is a valid integer
        $isInt = $false
        $ValidId = $false
        while(($isInt -eq $false) -or ($ValidId -eq $false))
        {   
            Write-LogInformation ""
            Write-Host "Please enter the ID for the desired $ProductStr from list above" -ForegroundColor Yellow
            $IdStr = Read-Host ">" -CustomLogMessage "ID choice Console input:"
        
            try{
                $IdInt = [convert]::ToInt32($IdStr)
                $isInt = $true
            }
            catch [FormatException]
            {
                Write-Host "The value entered for ID '",$IdStr,"' is not an integer"
            }
            
            if(($IdInt -ge 0) -and ($IdInt -le ($SqlTaskList.Count-1)))
            {
                $ValidId = $true
                $PIDInt = $SqlTaskList[$IdInt].PID
                $InstanceOnlyName = $SqlTaskList[$IdInt].Services
                break;
            }

        }
    } 
}

# if we still don't have a PID to dump
if (0 -eq $PIDInt)
{
    # for anything other than SSIS
    if (-not ($InstanceOnlyName.StartsWith("MsDtsServer", [System.StringComparison]::CurrentCultureIgnoreCase)))
    {
        Write-Host "$ProductStr service name = $InstanceOnlyName"
        $PIDStr = $SqlTaskList | Where-Object {$_.Services -like "*$InstanceOnlyName"} | Select-Object PID
        Write-Host "Service ProcessID =" $PIDStr.PID
        $PIDInt = [convert]::ToInt32($PIDStr.PID)
    
        Write-Host "Using PID=", $PIDInt," for generating a $ProductStr memory dump" -ForegroundColor Green
        Write-Host ""

    } else {

        #if multiple SSIS processes, get the user to input PID for desired SQL Server
        if ($SqlTaskList.Count -gt 1) 
        {
            Write-Host "More than one $ProductStr instance found." 

            #$SqlTaskList | Select-Object  PID, "Image name", Services |Out-Host 
            $SSISServices = Tasklist /SVC /FI "imagename eq msdtssrvr*" /FO CSV | ConvertFrom-Csv | Sort-Object -Property services
            
            Write-LogInformation "Discovered the following SSIS Service(s)`n"
            Write-LogInformation ""
            Write-LogInformation "ID	Service Name"
            Write-LogInformation "--	----------------"

            for($i=0; $i -lt $SSISServices.Count;$i++)
            {
                Write-LogInformation $i "	" $SSISServices[$i].Services
            }
            
            #check input and make sure it is a valid integer
            $isInt = $false
            $ValidId = $false
            while(($isInt -eq $false) -or ($ValidId -eq $false))
            {   
                Write-LogInformation ""
                Write-Host "Please enter the ID for the desired SSIS from list above" -ForegroundColor Yellow
                $SSISIdStr = Read-Host ">" -CustomLogMessage "ID choice Console input:"
            
                try{
                        $SSISIdInt = [convert]::ToInt32($SSISIdStr)
                        $isInt = $true
                    }

                catch [FormatException]
                    {
                        Write-Host "The value entered for ID '",$SSISIdStr,"' is not an integer"
                    }
                
                if(($SSISIdInt -ge 0) -and ($SSISIdInt -le ($SSISServices.Count-1)))
                {
                    $ValidId = $true
                    $PIDInt = $SSISServices[$SSISIdInt].PID
                    break;
                }

            }   

        
            Write-Host "Using PID=$PIDInt for generating a $ProductStr memory dump" -ForegroundColor Green
            Write-Host ""
            
        }
        else #if only one SSSIS on the box, go here
        {
            $SqlTaskList | Select-Object PID, "Image name", Services |Out-Host
            $PIDInt = [convert]::ToInt32($SqlTaskList.PID)
        
            Write-Host "Using PID=", $PIDInt, " for generating a $ProductStr memory dump" -ForegroundColor Green
            Write-Host ""
        }
    }
}

#dump type
if ($ProductNumber -eq "1")  #SQL Server memory dump
{
    #ask what type of SQL Server memory dump 
    while(($SqlDumpTypeSelection  -ne "1") -and ($SqlDumpTypeSelection -ne "2") -And ($SqlDumpTypeSelection -ne "3") -And ($SqlDumpTypeSelection -ne "4" ))
    {
        Write-Host "Which type of memory dump would you like to generate?`n" -ForegroundColor Yellow
        Write-Host "ID   Dump Type"
        Write-Host "--   ---------"
        Write-Host "1    Mini-dump"
        Write-Host "2    Mini-dump with referenced memory (Recommended)" 
        Write-Host "3    Filtered dump  (Not Recommended)"
        Write-Host "4    Full dump      (Do Not Use on Production systems!)"
        Write-Host ""
        $SqlDumpTypeSelection = Read-Host "Enter 1-4>" -CustomLogMessage "Dump type Console Input:"

        if (($SqlDumpTypeSelection -ne "1") -and ($SqlDumpTypeSelection -ne "2") -And ($SqlDumpTypeSelection -ne "3") -And ($SqlDumpTypeSelection -ne "4" ))
        {
            Write-Host ""
            Write-Host "Please enter a valid type of memory dump!"
            Write-Host ""
            Start-Sleep -Milliseconds 300
        }
    }

    Write-Host ""

    switch ($SqlDumpTypeSelection)
    {
        "1" {$DumpType="0x0120";break}
        "2" {$DumpType="0x0128";break}
        "3" {$DumpType="0x8100";break}
        "4" {$DumpType="0x01100";break}
        default {"0x0120"; break}

    }

}
elseif ($ProductNumber -eq "2")  #SSAS dump 
{

    #ask what type of SSAS memory dump 
    while(($SSASDumpTypeSelection  -ne "1") -and ($SSASDumpTypeSelection -ne "2"))
    {
        Write-Host "Which type of memory dump would you like to generate?" -ForegroundColor Yellow
        Write-Host "1) Mini-dump"
        Write-Host "2) Full dump  (Do Not Use on Production systems!)" -ForegroundColor Red
        Write-Host ""
        $SSASDumpTypeSelection = Read-Host "Enter 1-2>" -CustomLogMessage "SSAS Dump Type Console input:"

        if (($SSASDumpTypeSelection -ne "1") -and ($SSASDumpTypeSelection -ne "2"))
        {
            Write-Host ""
            Write-Host "Please enter a valid type of memory dump!"
            Write-Host ""
            Start-Sleep -Milliseconds 300
        }
    }

    Write-Host ""

    switch ($SSASDumpTypeSelection)
    {
        "1" {$DumpType="0x0";break}
        "2" {$DumpType="0x34";break}
        default {"0x0120"; break}

    }
}

elseif ($ProductNumber -eq "3" -or $ProductNumber -eq "4" -or $ProductNumber -eq "5")  #SSIS/SSRS/SQL Agent dump
{

    #ask what type of SSIS memory dump 
    while(($SSISDumpTypeSelection   -ne "1") -and ($SSISDumpTypeSelection  -ne "2"))
    {
        Write-Host "Which type of memory dump would you like to generate?" -ForegroundColor Yellow
        Write-Host "1) Mini-dump"
        Write-Host "2) Full dump" 
        Write-Host ""
        $SSISDumpTypeSelection = Read-Host "Enter 1-2>" -CustomLogMessage "SSIS Dump Type Console input:"

        if (($SSISDumpTypeSelection  -ne "1") -and ($SSISDumpTypeSelection  -ne "2"))
        {
            Write-Host ""
            Write-Host "Please enter a valid type of memory dump!"
            Write-Host ""
            Start-Sleep -Milliseconds 300
        }
    }

    Write-Host ""

    switch ($SSISDumpTypeSelection)
    {
        "1" {$DumpType="0x0";break}
        "2" {$DumpType="0x34";break}
        default {"0x0120"; break}

    }
}


# Sqldumper.exe PID 0 0x0128 0 c:\temp
#output folder
while($OutputFolder -eq "" -or !(Test-Path -Path $OutputFolder))
{
    Write-Host ""
    Write-Host "Where would your like the memory dump stored (output folder)?" -ForegroundColor Yellow
    $OutputFolder = Read-Host "Enter an output folder with no quotes (e.g. C:\MyTempFolder or C:\My Folder)" -CustomLogMessage "Dump Output Folder Console Input:"
    if ($OutputFolder -eq "" -or !(Test-Path -Path $OutputFolder))
    {
        Write-Host "'" $OutputFolder "' is not a valid folder. Please, enter a valid folder location" -ForegroundColor Yellow
    }
}

#strip the last character of the Output folder if it is a backslash "\". Else Sqldumper.exe will fail
if ($OutputFolder.Substring($OutputFolder.Length-1) -eq "\")
{
    $OutputFolder = $OutputFolder.Substring(0, $OutputFolder.Length-1)
    Write-Host "Stripped the last '\' from output folder name. Now folder name is  $OutputFolder"
}

#find the highest version of SQLDumper.exe on the machine
$NumFolder = dir "c:\Program Files\microsoft sql server\1*" | Select-Object @{name = "DirNameInt"; expression={[int]($_.Name)}}, Name, Mode | Where-Object Mode -Match "da*" | Sort-Object DirNameInt -Descending

for($j=0;($j -lt $NumFolder.Count); $j++)
{
    $SQLNumfolder = $NumFolder.DirNameInt[$j]   #start with the highest value from sorted folder names - latest version of dumper
    $SQLDumperDir = "c:\Program Files\microsoft sql server\"+$SQLNumfolder.ToString()+"\Shared\"
    $TestPathDumperDir = $SQLDumperDir+"sqldumper.exe" 
    
    $TestPathResult = Test-Path -Path $SQLDumperDir 
    
    if ($TestPathResult -eq $true)
    {
        break;
    }
 }

#build the SQLDumper.exe command e.g. (Sqldumper.exe 1096 0 0x0128 0 c:\temp\)

$cmd = "$([char]34)"+$SQLDumperDir + "sqldumper.exe$([char]34)"
$arglist = $PIDInt.ToString() + " 0 " +$DumpType +" 0 $([char]34)" + $OutputFolder + "$([char]34)"
Write-Host "Command for dump generation: ", $cmd, $arglist -ForegroundColor Green

#do-we-want-multiple-dumps section
Write-Host ""
Write-Host "This utility can generate multiple memory dumps, at a certain interval"
Write-Host "Would you like to collect multiple memory dumps?" -ForegroundColor Yellow

#validate Y/N input
$YesNo = $null # reset the variable because it could be assigned at this point
while (($YesNo -ne "y") -and ($YesNo -ne "n"))
{
    $YesNo = Read-Host "Enter Y or N>" -CustomLogMessage "Multiple Dumps Choice Console input:"

    if (($YesNo -eq "y") -or ($YesNo -eq "n") )
    {
        break
    }
    else
    {
        Write-Host "Not a valid 'Y' or 'N' response"
    }
}


#get input on how many dumps and at what interval
if ($YesNo -eq "y")
{
    [int]$DumpCountInt=0
    while(1 -ge $DumpCountInt)
    {
        Write-Host "How many dumps would you like to generate for this $ProductStr" -ForegroundColor Yellow
        $DumpCountStr = Read-Host ">" -CustomLogMessage "Dump Count Console input:"

        try
        {
            $DumpCountInt = [convert]::ToInt32($DumpCountStr)

            if(1 -ge $DumpCountInt)
            {
                Write-Host "Please enter a number greater than one." -ForegroundColor Red
            }
        }
        catch [FormatException]
        {
                Write-Host "The value entered for dump count '",$DumpCountStr,"' is not an integer" -ForegroundColor Red
        }
        
    }

    [int]$DelayIntervalInt=0
    while(0 -ge $DelayIntervalInt)
    {
        Write-Host "How frequently (in seconds) would you like to generate the memory dumps?" -ForegroundColor Yellow
        $DelayIntervalStr = Read-Host ">" -CustomLogMessage "Dump Frequency Console input:"

        try
        {
            $DelayIntervalInt = [convert]::ToInt32($DelayIntervalStr)
            if(0 -ge $DelayIntervalInt)
            {
                Write-Host "Please enter a number greater than zero." -ForegroundColor Red
            }
        }
        catch [FormatException]
        {
            Write-Host "The value entered for frequency (in seconds) '",$DelayIntervalStr,"' is not an integer" -ForegroundColor Red
        }
    }

    Write-Host "The configuration is ready. Press <Enter> key to proceed..."
    Read-Host -Prompt "<Enter> to proceed"

    Write-Host "Generating $DumpCountInt memory dumps at a $DelayIntervalStr-second interval" -ForegroundColor Green

    #loop to generate multiple dumps    
    $cntr = 0

    while($true)
    {
        Start-Process -FilePath $cmd -Wait -Verb runAs -ArgumentList $arglist 
        $cntr++

        Write-Host "Generated $cntr memory dump(s)." -ForegroundColor Green

        if ($cntr -ge $DumpCountInt)
            {
                break
            }
        Start-Sleep -S $DelayIntervalInt
    }

    #print what files exist in the output folder
    Write-Host ""
    Write-Host "Here are all the memory dumps in the output folder '$OutputFolder'" -ForegroundColor Green
    #$MemoryDumps = $OutputFolder + "\SQLDmpr*"
    $dumps_string = Get-ChildItem -Path ($OutputFolder + "\SQLDmpr*") | Out-String
    Write-Host $dumps_string

    Write-Host "Process complete"
}

else #produce just a single dump
{
    Write-Host "The configuration is ready. Press <Enter> key to proceed..."
    Read-Host -Prompt "<Enter> to proceed"
    
    Start-Process -FilePath $cmd -Wait -Verb runAs -ArgumentList $arglist 

    #print what files exist in the output folder
    Write-Host ""
    Write-Host "Here are all the memory dumps in the output folder '$OutputFolder'" -ForegroundColor Green
    $MemoryDumps = $OutputFolder + "\SQLDmpr*"
    Get-ChildItem -Path $MemoryDumps

    Write-Host ""
    Write-Host "Process complete"
}

Write-Host "For errors and completion status, review SQLDUMPER_ERRORLOG.log created by SQLDumper.exe in the output folder '$OutputFolder'. `Or if SQLDumper.exe failed look in the folder from which you are running this script"

# SIG # Begin signature block
# MIInvQYJKoZIhvcNAQcCoIInrjCCJ6oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDDUmkPl80aTpNe
# 1u7a803bzhw/TIaT7aPG5BEiTp24JaCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGY4wghmKAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKkI
# SqiZhICzedZLQa0SqtJ1ga9Kw8zB32AKwE83itzNMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQBQjT4PLFLVJaJOxqwRLqBn3uYz+YaSWTc5
# s6S2aS9zg1AEqryW54jjJCitsYWKQmgatHGrmUhieu36XAXCSzKERlHshVOqy47Y
# 5CZgVuxLaHHLhROBkWW/2cyP4ZvQQ+XOHMojtWdCxs6I3GyOixRyAUqUfJ2XZDVW
# buHRQRom6TmiZv/UDYApw3KKGDUUCCU7jsKfU4HiWS59a6xAs8PHQGacxAQMMPLE
# SUFjpp0l4tctbjpM08MHOjGj5u0PLJeQv9I2SPyUylPKUv0Hc955PAeltb8W/IGu
# kQ7JS2Zk9FbsV8SB+S/70PWjCwR188GiotD+WRUlZGFli7trqsAToYIXFjCCFxIG
# CisGAQQBgjcDAwExghcCMIIW/gYJKoZIhvcNAQcCoIIW7zCCFusCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIOaHfosA/wf+ZepzEzY3zcqy1iIZQ70I
# fpgAijfIXGuSAgZiCKzlX8AYEzIwMjIwMzAxMTI1MDI4Ljc5MVowBIACAfSggdik
# gdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UE
# CxMdVGhhbGVzIFRTUyBFU046ODZERi00QkJDLTkzMzUxJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghFlMIIHFDCCBPygAwIBAgITMwAAAYwB
# l2JHNnZmOwABAAABjDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDAeFw0yMTEwMjgxOTI3NDRaFw0yMzAxMjYxOTI3NDRaMIHSMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjg2REYtNEJCQy05MzM1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 00hoTKET+SGsayw+9BFdm+uZ+kvEPGLd5sF8XlT3Uy4YGqT86+Dr8G3k6q/lRagi
# xRKvn+g2AFRL9VuZqC1uTva7dZN9ChiotHHFmyyQZPalXdJTC8nKIrbgTMXAwh/m
# bhnmoaxsI9jGlivYgi5GNOE7u6TV4UOtnVP8iohTUfNMKhZaJdzmWDjhWC7LjPXI
# ham9QhRkVzrkxfJKc59AsaGD3PviRkgHoGxfpdWHPPaW8iiEHjc4PDmCKluW3J+I
# dU38H+MkKPmekC7GtRTLXKBCuWKXS8TjZY/wkNczWNEo+l5J3OZdHeVigxpzCnes
# kZfcHXxrCX2hue7qJvWrksFStkZbOG7IYmafYMQrZGull72PnS1oIdQdYnR5/ngc
# vSQb11GQ0kNMDziKsSd+5ifUaYbJLZ0XExNV4qLXCS65Dj+8FygCjtNvkDiB5Hs9
# I7K9zxZsUb7fKKSGEZ9yA0JgTWbcAPCYPtuAHVJ8UKaT967pJm7+r3hgce38VU39
# speeHHgaCS4vXrelTLiUMAl0Otk5ncKQKc2kGnvuwP2RCS3kEEFAxonwLn8pyedy
# reZTbBMQBqf1o3kj0ilOJ7/f/P3c1rnaYO01GDJomv7otpb5z+1hrSoIs8u+6eru
# JKCTihd0i/8bc67AKF76wpWuvW9BhbUMTsWkww4r42cCAwEAAaOCATYwggEyMB0G
# A1UdDgQWBBSWzlOGqYIhYIh5Vp0+iMrdQItSIzAfBgNVHSMEGDAWgBSfpxVdAF5i
# XYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQDXaMVFWMIJqdblQZK6
# oks7cdCUwePAmmEIedsyusgUMIQlQqajfCP9iG58yOFSRx2k59j2hABSZBxFmbkV
# jwhYEC1yJPQm9464gUz5G+uOW51i8ueeeB3h2i+DmoWNKNSulINyfSGgW6PCDCiR
# qO3qn8KYVzLzoemfPir/UVx5CAgVcEDAMtxbRrTHXBABXyCa6aQ3+jukWB5aQzLw
# 6qhHhz7HIOU9q/Q9Y2NnVBKPfzIlwPjb2NrQGfQnXTssfFD98OpRHq07ZUx21g4p
# s8V33hSSkJ2uDwhtp5VtFGnF+AxzFBlCvc33LPTmXsczly6+yQgARwmNHeNA262W
# qLLJM84Iz8OS1VfE1N6yYCkLjg81+zGXsjvMGmjBliyxZwXWGWJmsovB6T6h1Grf
# mvMKudOE92D67SR3zT3DdA5JwL9TAzX8Uhi0aGYtn5uNUDFbxIozIRMpLVpP/YOL
# ng+r2v8s8lyWv0afjwZYHBJ64MWVNxHcaNtjzkYtQjdZ5bhyka6dX+DtQD9bh3zj
# i0SlrfVDILxEb6OjyqtfGj7iWZvJrb4AqIVgHQaDzguixES9ietFikHff6p97C5q
# obTTbKwN0AEP3q5teyI9NIOVlJl0gi5Ibd58Hif3JLO6vp+5yHXjoSL/MlhFmvGt
# aYmQwD7KzTm9uADF4BzP/mx2vzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
# AAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX
# 9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1q
# UoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8d
# q6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byN
# pOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
# rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
# Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgS
# Uei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8
# QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6Cm
# gyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzF
# ER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQID
# AQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQU
# KqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0
# bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwU
# tj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN
# 3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU
# 5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5
# KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGy
# qVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
# 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
# AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFp
# AUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcd
# FYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRb
# atGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQd
# VTNYs6FwZvKhggLUMIICPQIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046ODZE
# Ri00QkJDLTkzMzUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2WiIwoBATAHBgUrDgMCGgMVADSi8hTrq/Q8oppweGyuZLNEJq/VoIGDMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDl
# yEKPMCIYDzIwMjIwMzAxMTQ1ODIzWhgPMjAyMjAzMDIxNDU4MjNaMHQwOgYKKwYB
# BAGEWQoEATEsMCowCgIFAOXIQo8CAQAwBwIBAAICEVIwBwIBAAICET0wCgIFAOXJ
# lA8CAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAweh
# IKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQBi+5XMdtqAHwccI/0hOCQB
# gH3GaBwc/rayKALDUF1INCVdE1cIW63mKkQwvmHmuqp7k6+Nv3OGeQiiNzGGo4Xw
# X9KNXsp9jxHTUbhSQBcTFQoPWGkPg12VECVpoq7F2sqSH6z77BvhgIbxzAOK3AfP
# qJCc5m8l3eUGilQBx3w6DDGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAABjAGXYkc2dmY7AAEAAAGMMA0GCWCGSAFlAwQCAQUA
# oIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIE
# IFnFOjp9d/ummC3dQDipL+BtecEm+ONRBSRHIZzl6GeDMIH6BgsqhkiG9w0BCRAC
# LzGB6jCB5zCB5DCBvQQg1a2L+BUqkM8Gf8TmIQWdgeKTTrYXIwOofOuJiBiYaZ4w
# gZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAYwBl2JH
# NnZmOwABAAABjDAiBCBNlUx5c5VGUitqq4K6lo3v3VKS0jyFzTGb6pAcAmYkzzAN
# BgkqhkiG9w0BAQsFAASCAgC7UHRxjB1dxxmgakxcC1eh9j+Yg36fhJ6xIlynUHL3
# MTi8PDO0lXwusu6JKFoj73COTV0+9Db4J8YuCrieJbbOVxBQPBxmjVakA/9jHw9H
# JBUjCDIvXgW2Js/doYapViME0nOnV4Zu/SxRcGSghjGWgq0pfxK4av/1AHBIOc58
# 34MszjBGZkPOllajfu+mJC+0UrJyyF8c7iW8H7iikExrI1am32/svSIE3fIXC5b/
# cq39UqRoEWDljfp86JJZeE4ib1huELgp4ENz46l6Q8G1hNVw+o7F8xY6Ds0NmpfO
# 2lISFjDFKc6BkLbYJm7IG+DG+pZRzD0SBkpy5JoUwtvk44bXA9G+3AWIieGr0ZdE
# 1a2y4otedUOjymHqZwX3S+KAVvYV2HHzLxgoikxE9rQaWdpbBWSYDZGei3cyQrtU
# UDxG6cJt4kywFUmi29XOVIwNysDIUIw1bFGTL39XAmYnToAjI7MRGiuKTntPo6e2
# d8JgY2vDyNo1oSEPoPRAqLxE1nh/8edlgp8pvTge0l9l1QXdR7z/dtCWPb4+Ieg7
# gG/hREcX7IN27i/nYfKs9xaQ9HnXu4RKN+3yHg9nak3cNPjcDY1ozHBzQ5kkKmwQ
# FdB2U4sp4nu91hUOG1GuYPBugnkfnQzVKE1O4LnUc1y1krrUpOrpcfTSOEO9NBUR
# FQ==
# SIG # End signature block
