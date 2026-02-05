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

#This script block is needed to allow execution to be deferred , in which case we save the user input in global variables and later use it when dump command is invoked.
$MainBodyBlock =
{
    #what product would you like to generate a memory dump
    $ProductList = @("1","2","3","4","5")

    while(($ProductList -notcontains $ProductNumber))
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
        $ProductNumber = Read-Host "Enter 1-5>" -CustomLogMessage "Dump Product console input:"

        if (($ProductList -notcontains $ProductNumber ) )
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
        Write-Host "There are currently no running instances of $ProductStr. SQLDumper.exe won't run. Exiting..." -ForegroundColor Green
        Start-Sleep -Seconds 2
        Write-LogDebug "No memory dumps generated. SQLDumper.exe didn't run. Exiting..." -DebugLogLevel 1
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
                $IdStr = Read-Host ">" -CustomLogMessage "ID choice console input:"
            
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
            Write-Host "$ProductStr service name = '$InstanceOnlyName'"
            $PIDStr = $SqlTaskList | Where-Object {$_.Services -like "*$InstanceOnlyName"} | Select-Object PID
            Write-Host "Service ProcessID = '$($PIDStr.PID)'"
            $PIDInt = [convert]::ToInt32($PIDStr.PID)
        
            Write-LogDebug "Using PID = '$PIDInt' for generating a $ProductStr memory dump" -DebugLogLevel 1
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
                    $SSISIdStr = Read-Host ">" -CustomLogMessage "ID choice console input:"
                
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
        $regexMatch = '^[1-4]$'
        while(($SqlDumpTypeSelection -notmatch $regexMatch ))
        {
            Write-Host "Which type of memory dump would you like to generate?`n" -ForegroundColor Yellow
            Write-Host "ID   Dump Type"
            Write-Host "--   ---------"
            Write-Host "1    Mini-dump"
            Write-Host "2    Mini-dump with referenced memory (Recommended)" 
            Write-Host "3    Filtered dump  (Not Recommended)"
            Write-Host "4    Full dump      (Do Not Use on Production systems!)"
            Write-Host ""
            $SqlDumpTypeSelection = Read-Host "Enter 1-4>" -CustomLogMessage "Dump type console input:"

            if (($SqlDumpTypeSelection -notmatch $regexMatch))
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


        Write-LogDebug "SQL Version: $SqlVersion" -DebugLogLevel 1

        [string]$CompressDumpFlag = ""

        
        # if the version is between SQL 2019, CU23 (16000004075) and  16000000000 (SQL 2022)  
        # or if greater than or equal to 2022 CU8 (16000004075), then we can create a compressed dump -zdmp flag

        if ($SqlDumpTypeSelection -in ("3", "4"))  
        {
            if ((checkSQLVersion -VersionsList @("2022RTMCU8", "2019RTMCU23") -eq $true) )
            {
                Write-Host "Starting with SQL Server 2019 CU23 and SQL Server 2022 CU8, you can create a compressed full or filtered memory dump."
                Write-Host "Would you like to create compressed memory dumps?" 
                
                while ($isCompressedDump -notin ("Y", "N"))
                {
                
                    $isCompressedDump = Read-Host "Create a compressed memory dump? (Y/N)" -CustomLogMessage "Compressed Dump console input:"
                    $isCompressedDump = $isCompressedDump.ToUpper()

                    if ($isCompressedDump -eq "Y")
                    {
                        $CompressDumpFlag = "-zdmp"
                    }
                    elseif ($isCompressedDump -eq "N")
                    {
                        $CompressDumpFlag = ""
                    }
                    else 
                    {
                        Write-Host "Not a valid 'Y' or 'N' response"
                    }
                }
            }
            Write-Host "WARNING: Filtered and Full dumps are not recommended for production systems. They might cause performance issues and should only be used when directed by Microsoft Support." -ForegroundColor Yellow
            Write-Host ""
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
            $SSASDumpTypeSelection = Read-Host "Enter 1-2>" -CustomLogMessage "SSAS Dump Type console input:"

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
            $SSISDumpTypeSelection = Read-Host "Enter 1-2>" -CustomLogMessage "SSIS Dump Type console input:"

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
        Write-Host "Where would you like the memory dump stored (output folder)?" -ForegroundColor Yellow
        $OutputFolder = Read-Host "Enter an output folder with no quotes (e.g. C:\MyTempFolder or C:\My Folder)" -CustomLogMessage "Dump Output Folder console input:"
        if ($OutputFolder -eq "" -or !(Test-Path -Path $OutputFolder))
        {
            Write-Host "'" $OutputFolder "' is not a valid folder. Please, enter a valid folder location" -ForegroundColor Yellow
        }
    }

    #strip the last character of the Output folder if it is a backslash "\". Else Sqldumper.exe will fail
    if ($OutputFolder.Substring($OutputFolder.Length-1) -eq "\")
    {
        $OutputFolder = $OutputFolder.Substring(0, $OutputFolder.Length-1)
        Write-LogDebug "Stripped the last '\' from output folder name. Now folder name is  $OutputFolder" -DebugLogLevel 1
    }

    #find the highest version of SQLDumper.exe on the machine
    $NumFolder = Get-ChildItem -Path "c:\Program Files\microsoft sql server\1*" -Directory | Select-Object @{name = "DirNameInt"; expression={[int]($_.Name)}}, Name, Mode | Sort-Object DirNameInt -Descending

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
    $arglist = $PIDInt.ToString() + " 0 " +$DumpType +" 0 $([char]34)" + $OutputFolder + "$([char]34) " + $CompressDumpFlag
    Write-Host "Command for dump generation: ", $cmd, $arglist -ForegroundColor Green

    #do-we-want-multiple-dumps section
    Write-Host ""
    Write-Host "This utility can generate multiple memory dumps, at a certain interval"
    Write-Host "Would you like to collect multiple memory dumps?" -ForegroundColor Yellow

    #validate Y/N input
    $YesNo = $null # reset the variable because it could be assigned at this point
    $regexMatch = '^(?:Y|N)$'

    while ($YesNo -NotMatch $regexMatch) 
    {
        $YesNo = Read-Host "Enter Y or N>" -CustomLogMessage "Multiple Dumps Choice console input:"

        if ($YesNo -match $regexMatch)
        {
            break
        }
        else
        {
            Write-Host "Not a valid 'Y' or 'N' response"
        }
    }

    [int]$DumpCountInt = 0
    [int]$DelayIntervalInt=0

    #get input on how many dumps and at what interval
    if ($YesNo -eq "y")
    {
        while(1 -ge $DumpCountInt)
        {
            Write-Host "How many dumps would you like to generate for this $ProductStr" -ForegroundColor Yellow
            $DumpCountStr = Read-Host ">" -CustomLogMessage "Dump Count console input:"

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

        while(0 -ge $DelayIntervalInt)
        {
            Write-Host "How frequently (in seconds) would you like to generate the memory dumps?" -ForegroundColor Yellow
            $DelayIntervalStr = Read-Host ">" -CustomLogMessage "Dump Frequency console input:"

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

         Write-Host "Generating $DumpCountInt memory dumps at a $DelayIntervalStr-second interval" -ForegroundColor Green
    } 
    else 
    {
        $DumpCountInt = 1
        $DelayIntervalStr = "0"
    }

    #if we have Memory Dump execlusively used, then no need for deferred execution
    if ($global:scenario_bitvalue -ne $global:dumpMemoryBit) 
    {
        #Execute now or Later?
        Write-Host ""
        Write-Host "This utility can delay execution until later in the collection process"
        Write-Host "Would you like to generate memory dumps now? (type 'n' to do it later)" -ForegroundColor Yellow
        #validate Y/N input
        if ($global:gInteractivePrompts -eq "Quiet") {
            $YesNo = "Y" #in Quite mode we skip this input and dump immediately
        } else {
            $YesNo = $null # reset the variable because it could be assigned at this point
        }
        
        $regexMatch = '^(?:Y|N)$'
        while ($YesNo -NotMatch $regexMatch) 
        {
            $YesNo = (Read-Host "Enter Y or N>" -CustomLogMessage "MemDUMP now or defer:").ToUpper()

            if ($YesNo -match $regexMatch)
            {
                break
            }
            else
            {
                Write-Host "Not a valid 'Y' or 'N' response"
            }
        }
    } else 
    {
        $YesNo = "Y"
    }

    

    if ($YesNo -eq "N")
    {
        $global:dump_helper_arguments = $arglist
        $global:dump_helper_count = $DumpCountInt
        $global:dump_helper_delay = $DelayIntervalInt
        $global:dump_helper_cmd = $cmd
        $global:dump_helper_outputfolder = $OutputFolder

        Write-LogDebug "Dump Helper Arguments saved : " $global:dump_helper_arguments -DebugLogLevel 3
        Write-LogDebug "CMD  " $cmd -DebugLogLevel 3
        return
    } 
    else {
        #for immediate execution we pass back variables to main script
        $script:arglist = $arglist
        $script:DumpCountInt = $DumpCountInt
        $script:DelayIntervalInt = $DelayIntervalInt
        $script:OutputFolder = $OutputFolder
        $script:cmd = $cmd
    }

} # MainBody ScriptBlock

if ($global:dump_helper_arguments -eq "none") 
{
    #We don't have cached info, so we run main block
    &$MainBodyBlock

    if ($global:dump_helper_arguments -ne "none") 
    {
        #if we have saved arguments then we are deferred 
        Write-LogDebug "Deferring Dump Helper execution" -DebugLogLevel 3
        return
    }

} else {
    #helper arguments are not empty , so we execute dump immediately

    $DumpCountInt = $global:dump_helper_count
    $DelayIntervalInt = $global:dump_helper_delay
    $DelayIntervalStr = $global:dump_helper_delay
    $arglist = $global:dump_helper_arguments
    $cmd = $global:dump_helper_cmd
    $OutputFolder = $global:dump_helper_outputfolder

}
   

    #loop to generate multiple dumps    
    $cntr = 0

    while($cntr -lt $DumpCountInt)
    {
        Start-Process -FilePath $cmd -Wait -Verb runAs -ArgumentList $arglist 
        $cntr++

        if ($DumpCountInt -gt 1) { Write-Host "Generated $cntr memory dump(s)." -ForegroundColor Green }

        Start-Sleep -S $DelayIntervalInt
    }

    #print what files exist in the output folder
    $dumps_generated = Get-ChildItem -Path ($OutputFolder + "\*dmp")
    if ($dumps_generated.Count -eq 0)
    {
        Write-Host "No memory dumps were found."
    }
    else 
    {
        
        Write-Host ""
        Write-Host "Here are all the memory dumps in the output folder '$OutputFolder'" -ForegroundColor Green
        $dumps_string = $dumps_generated | Out-String
        Write-Host $dumps_string

    }


Write-Host "If SQLDumper.exe ran, it has generated a SQLDUMPER_ERRORLOG.log in the output folder '$OutputFolder'. For errors and completion status, review that log." 
Write-Host "If SQLDumper.exe failed, look for the log in the folder where you ran this script"
Write-Host "Process complete"

# SIG # Begin signature block
# MIIr5AYJKoZIhvcNAQcCoIIr1TCCK9ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAGI0sGOcOXf/le
# 4TXvh1hP9AzJjBMKS1WbRxCMmZi+9aCCEW4wggh+MIIHZqADAgECAhM2AAACDeKE
# D0nu2y38AAIAAAINMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzA5MzBaFw0yNjA0MjYyMzE5MzBaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCpj9ry6z6v08TIeKoxS2+5c928SwYKDXCyPWZHpm3xIHTqBBmlTM1GO7X4
# ap5jj/wroH7TzukJtfLR6Z4rBkjdlocHYJ2qU7ggik1FDeVL1uMnl5fPAB0ETjqt
# rk3Lt2xT27XUoNlKfnFcnmVpIaZ6fnSAi2liEhbHqce5qEJbGwv6FiliSJzkmeTK
# 6YoQQ4jq0kK9ToBGMmRiLKZXTO1SCAa7B4+96EMK3yKIXnBMdnKhWewBsU+t1LHW
# vB8jt8poBYSg5+91Faf9oFDvl5+BFWVbJ9+mYWbOzJ9/ZX1J4yvUoZChaykKGaTl
# k51DUoZymsBuatWbJsGzo0d43gMLAgMBAAGjggWKMIIFhjApBgkrBgEEAYI3FQoE
# HDAaMAwGCisGAQQBgjdbAQEwCgYIKwYBBQUHAwMwPQYJKwYBBAGCNxUHBDAwLgYm
# KwYBBAGCNxUIhpDjDYTVtHiE8Ys+hZvdFs6dEoFgg93NZoaUjDICAWQCAQ4wggJ2
# BggrBgEFBQcBAQSCAmgwggJkMGIGCCsGAQUFBzAChlZodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpaW5mcmEvQ2VydHMvQlkyUEtJQ1NDQTAxLkFNRS5HQkxfQU1F
# JTIwQ1MlMjBDQSUyMDAxKDIpLmNydDBSBggrBgEFBQcwAoZGaHR0cDovL2NybDEu
# YW1lLmdibC9haWEvQlkyUEtJQ1NDQTAxLkFNRS5HQkxfQU1FJTIwQ1MlMjBDQSUy
# MDAxKDIpLmNydDBSBggrBgEFBQcwAoZGaHR0cDovL2NybDIuYW1lLmdibC9haWEv
# QlkyUEtJQ1NDQTAxLkFNRS5HQkxfQU1FJTIwQ1MlMjBDQSUyMDAxKDIpLmNydDBS
# BggrBgEFBQcwAoZGaHR0cDovL2NybDMuYW1lLmdibC9haWEvQlkyUEtJQ1NDQTAx
# LkFNRS5HQkxfQU1FJTIwQ1MlMjBDQSUyMDAxKDIpLmNydDBSBggrBgEFBQcwAoZG
# aHR0cDovL2NybDQuYW1lLmdibC9haWEvQlkyUEtJQ1NDQTAxLkFNRS5HQkxfQU1F
# JTIwQ1MlMjBDQSUyMDAxKDIpLmNydDCBrQYIKwYBBQUHMAKGgaBsZGFwOi8vL0NO
# PUFNRSUyMENTJTIwQ0ElMjAwMSxDTj1BSUEsQ049UHVibGljJTIwS2V5JTIwU2Vy
# dmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1BTUUsREM9R0JM
# P2NBQ2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0
# aG9yaXR5MB0GA1UdDgQWBBS6kl+vZengaA7Cc8nJtd6sYRNA3jAOBgNVHQ8BAf8E
# BAMCB4AwRQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEWMBQGA1UEBRMNMjM2MTY3KzUwNjA0MjCCAeYGA1UdHwSCAd0wggHZMIIB
# 1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpaW5mcmEvQ1JM
# L0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwxLmFtZS5nYmwv
# Y3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwyLmFtZS5n
# YmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmwzLmFt
# ZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6Ly9jcmw0
# LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGgb1sZGFwOi8v
# L0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQS0lDU0NBMDEsQ049Q0RQ
# LENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZp
# Z3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0
# P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwHwYDVR0jBBgw
# FoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgwFgYKKwYBBAGCN1sBAQYI
# KwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAJKGB9zyDWN/9twAY6qCLnfDCKc/
# PuXoCYI5Snobtv15QHAJwwBJ7mr907EmcwECzMnK2M2auU/OUHjdXYUOG5TV5L7W
# xvf0xBqluWldZjvnv2L4mANIOk18KgcSmlhdVHT8AdehHXSs7NMG2di0cPzY+4Ol
# 2EJ3nw2JSZimBQdRcoZxDjoCGFmHV8lOHpO2wfhacq0T5NK15yQqXEdT+iRivdhd
# i/n26SOuPDa6Y/cCKca3CQloCQ1K6NUzt+P6E8GW+FtvcLza5dAWjJLVvfemwVyl
# JFdnqejZPbYBRdNefyLZjFsRTBaxORl6XG3kiz2t6xeFLLRTJgPPATx1S7Awggjo
# MIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0GCSqGSIb3DQEBCwUAMDwx
# EzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxEDAOBgNV
# BAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYwNTIxMTg1NDE0WjBBMRMw
# EQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQD
# EwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDJ
# mlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL9rNHnHDGfJgeuRIYO1LY
# /1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc411WxA+Pv2rteAcz0eHM
# H36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaCIIWBXyEchv+sM9eKDsUO
# LdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8pXirIYOgM770CYOiZrcKH
# K7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p/6fksgEILptOKhx9c+ia
# piNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkrBgEEAYI3FQEEBQIDAgAC
# MCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMALI38/RzAdBgNVHQ4EFgQU
# llGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfwwgfkGBysGAQUCAwUGCCsG
# AQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYBBAGCNxUGBgorBgEEAYI3
# CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgCAgYKKwYBBAGCN0ABAQYL
# KwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcVBQYKKwYBBAGCNxQCAgYK
# KwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEGCisGAQQBgjdbAgEGCisG
# AQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEGCisGAQQBgjdbBAIwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwNp4x1AdEJCygwggFoBgNV
# HR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDovL2NybDIuYW1lLmdibC9j
# cmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL2FtZXJvb3Qu
# Y3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVyb290LmNybIaBqmxkYXA6
# Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPUFNRSxE
# Qz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNz
# PWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUHAQEEggGdMIIBmTBHBggr
# BgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NlcnRz
# L0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwyLmFt
# ZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6
# Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUH
# MAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQw
# gaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290LENOPUFJQSxDTj1QdWJs
# aWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9u
# LERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29iamVjdENsYXNzPWNl
# cnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQELBQADggIBAFAQI7dPD+jf
# XtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTHb8BDfRN+AD0YEmeDB5HK
# QoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a/752hMIn+L4ZuyxVeSBp
# fwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9zAh9yRKKls2bziPEnxeO
# ZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAmn3WCPWNFC1YTIIHw/mD2
# cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtzyb7fbNS1dE740re0COE6
# 7YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjFK1yMw4Ni5fMabcgmzRvS
# jAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bzMzsikuDW9xH10graZzSm
# PjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIzJ6Q9G3NPCB+7KwX0OQmK
# yv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/ywO6SYSreVW+5Y0mzJutn
# BC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEISRtShDZbuYymynY1un+Ry
# fiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZzDCCGcgCAQEwWDBBMRMwEQYKCZIm
# iZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1FMRUwEwYDVQQDEwxBTUUg
# Q1MgQ0EgMDECEzYAAAIN4oQPSe7bLfwAAgAAAg0wDQYJYIZIAWUDBAIBBQCgga4w
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJxRSiKIr3owOVYfN/0eJyiQqOtGYzcd
# xmb+T09Tn477MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYA
# dKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# FeZtPdQyoV7CbMc1kLQzaaAflDd16n3r83g4rZOYUEmVjfyKbxUa89N/dZq2X/7m
# RbkFEAlSjwt0Mmuf6M5zf0ezwTLDTFzAbngGEOKsFXsfy8oOlxSJRIBO51lM+ecM
# vYdhsP18d+bUq8+lN5SbiKcXGYBHf5o2C/nBOieYOYj7WafT9wDCe5QoDB3vWGU4
# HjqIfrIrL4dZ7E8PdnxNqvd3wpqN517t/S3C62w9zyElvENUgdAWJQOdWcsMOapI
# PJJDFfOnUI0KrcV9PvI/0NXt3uRQ/P2OzWtSkF7oW1jzoYH6GPk7+EqFI7t4JXFC
# qSVsdx6HDkIlbY7c46N0UqGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqG
# SIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0B
# CRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCByFzY9AgMzv/uAgq2+xxgEvGFaECrPS66EfvbAnzUuVQIGaWkVtLU4GBMyMDI2
# MDIwNDE2MzUyNy42NjNaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIH
# IDCCBQigAwIBAgITMwAAAgh4nVhdksfZUgABAAACCDANBgkqhkiG9w0BAQsFADB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNTNaFw0y
# NjA0MjIxOTQyNTNaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYD
# VQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQC1y3AI5lIz3Ip1nK5BMUUbGRsjSnCz/VGs33zvY0NeshsPgfld
# 3/Z3/3dS8WKBLlDlosmXJOZlFSiNXUd6DTJxA9ik/ZbCdWJ78LKjbN3tFkX2c6RR
# pRMpA8sq/oBbRryP3c8Q/gxpJAKHHz8cuSn7ewfCLznNmxqliTk3Q5LHqz2PjeYK
# D/dbKMBT2TAAWAvum4z/HXIJ6tFdGoNV4WURZswCSt6ROwaqQ1oAYGvEndH+DXZq
# 1+bHsgvcPNCdTSIpWobQiJS/UKLiR02KNCqB4I9yajFTSlnMIEMz/Ni538oGI64p
# hcvNpUe2+qaKWHZ8d4T1KghvRmSSF4YF5DNEJbxaCUwsy7nULmsFnTaOjVOoTFWW
# fWXvBuOKkBcQKWGKvrki976j4x+5ezAP36fq3u6dHRJTLZAu4dEuOooU3+kMZr+R
# BYWjTHQCKV+yZ1ST0eGkbHXoA2lyyRDlNjBQcoeZIxWCZts/d3+nf1jiSLN6f6wd
# HaUz0ADwOTQ/aEo1IC85eFePvyIKaxFJkGU2Mqa6Xzq3qCq5tokIHtjhogsrEgfD
# KTeFXTtdhl1IPtLcCfMcWOGGAXosVUU7G948F6W96424f2VHD8L3FoyAI9+r4zyI
# QUmqiESzuQWeWpTTjFYwCmgXaGOuSDV8cNOVQB6IPzPneZhVTjwxbAZlaQIDAQAB
# o4IBSTCCAUUwHQYDVR0OBBYEFKMx4vfOqcUTgYOVB9f18/mhegFNMB8GA1UdIwQY
# MBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUt
# U3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYB
# BQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWlj
# cm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB
# /wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0G
# CSqGSIb3DQEBCwUAA4ICAQBRszKJKwAfswqdaQPFiaYB/ZNAYWDa040XTcQsCaCu
# a5nsG1IslYaSpH7miTLr6eQEqXczZoqeOa/xvDnMGifGNda0CHbQwtpnIhsutrKO
# 2jhjEaGwlJgOMql21r7Ik6XnBza0e3hBOu4UBkMl/LEX+AURt7i7+RTNsGN0cXPw
# PSbTFE+9z7WagGbY9pwUo/NxkGJseqGCQ/9K2VMU74bw5e7+8IGUhM2xspJPqnSe
# HPhYmcB0WclOxcVIfj/ZuQvworPbTEEYDVCzSN37c0yChPMY7FJ+HGFBNJxwd5lK
# Ir7GYfq8a0gOiC2ljGYlc4rt4cCed1XKg83f0l9aUVimWBYXtfNebhpfr6Lc3jD8
# NgsrDhzt0WgnIdnTZCi7jxjsIBilH99pY5/h6bQcLKK/E6KCP9E1YN78fLaOXkXM
# yO6xLrvQZ+uCSi1hdTufFC7oSB/CU5RbfIVHXG0j1o2n1tne4eCbNfKqUPTE31tN
# bWBR23Yiy0r3kQmHeYE1GLbL4pwknqaip1BRn6WIUMJtgncawEN33f8AYGZ4a3Nn
# HopzGVV6neffGVag4Tduy+oy1YF+shChoXdMqfhPWFpHe3uJGT4GJEiNs4+28a/w
# HUuF+aRaR0cN5P7XlOwU1360iUCJtQdvKQaNAwGI29KOwS3QGriR9F2jOGPUAlpe
# EzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQEL
# BQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNV
# BAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4X
# DTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM
# 57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm
# 95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzB
# RMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBb
# fowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCO
# Mcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYw
# XE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW
# /aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/w
# EPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPK
# Z6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2
# BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfH
# CBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYB
# BAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8v
# BO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEF
# BQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBW
# BgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUH
# AQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# L2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsF
# AAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518Jx
# Nj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+
# iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2
# pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefw
# C2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7
# T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFO
# Ry3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhL
# mm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3L
# wUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5
# m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE
# 0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIICNQIB
# ATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOkEwMDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCNkvu0NKcS
# jdYKyrhJZcsyXOUTNKCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA7S3vjzAiGA8yMDI2MDIwNDE2MTcxOVoYDzIw
# MjYwMjA1MTYxNzE5WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDtLe+PAgEAMAcC
# AQACAhicMAcCAQACAhIdMAoCBQDtL0EPAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEL
# BQADggEBAHPhG5SbcC6Gg67QIzRV9Ef6w9MO9/GGCWiXkb8ac9gVYxvj3do+xAp3
# j81oqGZ0LKLUDjFop3zwI9SMhpkq1AA+oR1iW7WU+JOsiF3C8sQqGNLJDLnwnS9v
# MUdA4MyudyV9HyDuUiUX7Jrg8wjw2JZtai3cuXyJjefkUFL/cXCaP5yfE+Qt3Hri
# Jn8uUt3gBz3HS785GGntsKGYgwOqsM4fyqj1ihG4nLIFKHW8Kcg0JsAb6jTrjkQV
# VWMhftZ3HWOgXRiId8DJSrX0frzYsFCNKix1Ba3xUpGfhp6d27V1YEJssMi4emz4
# CjzW8vzfxc6uDpSnNwM7bvWthRie2OcxggQNMIIECQIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAgh4nVhdksfZUgABAAACCDANBglghkgB
# ZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCD6x0t6vp7YoLBOXsTJBTENFoDg7ljk7o42ScdOj1HURjCB+gYLKoZI
# hvcNAQkQAi8xgeowgecwgeQwgb0EII//jm8JHa2W1O9778t9+Ft2Z5NmKqttPk6Q
# +9RRpmepMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMA
# AAIIeJ1YXZLH2VIAAQAAAggwIgQgxKH5b/AUp9X5FgKyUEZcCow4aoM3ixkp1myS
# y5BFtPswDQYJKoZIhvcNAQELBQAEggIAS7DAiMAUGAPCGtCsER6URdM4O5e4sX7K
# MwTlVOXPkVr22ahCYLhG8LtpEfzqdFKO5GjvoxZg3YvqPblSBZaiP18LVzJ3yRcO
# xSQ0LYZTrE1W0OfSgDx3rjJHzYfl9zD2/xaXois67y0bg18nVBkY5BPzQv7FmBeo
# vC/j8K0FbfYWV9OEWtY6v/2jWnSZDVO4+XhpyIFKUiOIQn32zCkckwHtDK9/lJa3
# 08+2Gf4YQW73Oese2LEoIYqlRtd84FRG0hnxgPGx0SnbhERR0O+E5FPrl4xBc8rY
# 1oLs7IFl/rVubXDShr1H7XJm/7UxQIJhAU5YQj9RYQqOEdnr8Ls7JJ4QfnVr/42F
# h+TPZMLNlHUJNU+uPNNrukkthnxgSz4U+f4qGsKp9K3GZMh9/3Ubkafzsw4iuBJc
# i3ych0VWi5IbAfUlpfAF3PR6iH6MXESKPnBYpy4+aFI3970BO8dDbHU3xC2OBs3H
# ROmKGQakVhoo7veA5pUVRh3IHof9S+RmvEIsRLDnr+FbcAc8neARsQzoUvd4YQya
# Li5XFtQJDGKqjBY+w53MglF0JnDRYYkMun6HOjRM6xTMrK8w98jBOwhKZYqupZS0
# lGQ/e8gfHE9b/Q8RXzbZPg0R31Fe0AmwXY0LBDHUU1ilqrBVnj68GCu+DLhLY2Tr
# AARCG2eg3Wk=
# SIG # End signature block
