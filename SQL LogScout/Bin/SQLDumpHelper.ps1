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
        Write-Host "Where would your like the memory dump stored (output folder)?" -ForegroundColor Yellow
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
            $YesNo = (Read-Host "Enter Y or N>" -CustomLogMessage "MemDUMP Now or Defer:").ToUpper()

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
    Write-Host "Generating $DumpCountInt memory dumps at a $DelayIntervalStr-second interval" -ForegroundColor Green

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
    Write-Host ""
    Write-Host "Here are all the memory dumps in the output folder '$OutputFolder'" -ForegroundColor Green
    #$MemoryDumps = $OutputFolder + "\SQLDmpr*"
    $dumps_string = Get-ChildItem -Path ($OutputFolder + "\*dmp") | Out-String
    Write-Host $dumps_string

    Write-Host "Process complete"

Write-Host "For errors and completion status, review SQLDUMPER_ERRORLOG.log created by SQLDumper.exe in the output folder '$OutputFolder'. `Or if SQLDumper.exe failed look in the folder from which you are running this script"
