## Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.








#=======================================Start of \OUTPUT and \INTERNAL directories and files Section
#======================================== START of Process management section
Import-Module .\CommonFunctions.psm1
#=======================================End of \OUTPUT and \INTERNAL directories and files Section
#======================================== END of Process management section


#======================================== START OF NETNAME + INSTANCE SECTION - Instance Discovery
Import-Module .\InstanceDiscovery.psm1
#======================================== END OF NETNAME + INSTANCE SECTION - Instance Discovery



#======================================== START of Console LOG SECTION
Import-Module .\LoggingFacility.psm1
#======================================== END of Console LOG SECTION

#======================================== START of File Attribute Validation SECTION
Import-Module .\Confirm-FileAttributes.psm1
#======================================== END of File Attribute Validation SECTION



function InitAppVersion()
{
    $major_version = "5"
    $minor_version = "23"
    $build = "06"
    $revision = "06"
    $global:app_version = $major_version + "." + $minor_version + "." + $build + "." + $revision
    Write-LogInformation "SQL LogScout version: $global:app_version"
}


function Replicate ([string] $char, [int] $cnt)
{
    $finalstring = $char * $cnt;
    return $finalstring;
}


function PadString (  [string] $arg1,  [int] $arg2 )
{
     $spaces = Replicate " " 256
     $retstring = "";
    if (!$arg1 )
    {
        $retstring = $spaces.Substring(0, $arg2);
     }
    elseif ($arg1.Length -eq  $arg2)
    {
        $retstring= $arg1;
       }
    elseif ($arg1.Length -gt  $arg2)
    {
        $retstring = $arg1.Substring(0, $arg2); 
        
    }
    elseif ($arg1.Length -lt $arg2)
    {
        $retstring = $arg1 + $spaces.Substring(0, ($arg2-$arg1.Length));
    }
    return $retstring;
}

function GetWindowsHotfixes () 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "WindowsHotfixes"
    $server = $global:sql_instance_conn_str

    Write-LogInformation "Executing Collector: $collector_name"

    try {    
        ##create output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The output_file is $output_file" -DebugLogLevel 3

        #collect Windows hotfixes on the system
        $hotfixes = Get-WmiObject -Class "win32_quickfixengineering"

        #in case CTRL+C is pressed
        HandleCtrlC

        [System.Text.StringBuilder]$rs_runningdrives = New-Object -TypeName System.Text.StringBuilder

        #Running drivers header
        [void]$rs_runningdrives.Append("-- Windows Hotfix List --`r`n")
        [void]$rs_runningdrives.Append("HotfixID       InstalledOn    Description                   InstalledBy  `r`n")
        [void]$rs_runningdrives.Append("-------------- -------------- ----------------------------- -----------------------------`r`n") 

        [int]$counter = 1
        foreach ($hf in $hotfixes) {
            $hotfixid = $hf["HotfixID"] + "";
            $installedOn = $hf["InstalledOn"] + "";
            $Description = $hf["Description"] + "";
            $InstalledBy = $hf["InstalledBy"] + "";
            $output = PadString  $hotfixid 15
            $output += PadString $installedOn  15;
            $output += PadString $Description 30;
            $output += PadString $InstalledBy  30;
            [void]$rs_runningdrives.Append("$output`r`n") 

            #in case CTRL+C is pressed
            HandleCtrlC
        }
        Add-Content -Path ($output_file) -Value ($rs_runningdrives.ToString())
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetWindowsDiskInfo () 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "WindowsDiskInfo"
    $server = $global:sql_instance_conn_str

    Write-LogInformation "Executing Collector: $collector_name"

    try {    
        ##create output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The output_file is $output_file" -DebugLogLevel 3

        #Collect Windows disk info on the system
        $disks = @()
        $LunMap = @()
        $OutputArray = @()
        $disks = Get-WmiObject -Class Win32_diskdrive
        foreach($disk in $disks)
        {          
            $partinfo = $disk.GetRelated("Win32_DiskPartition").GetRelated("Win32_LogicalDisk")
            $LunMap = [PSCustomObject]@{
                ComputerName = $disk.PSComputerName
                DiskInfo = $disk.Caption
                DeviceID = $disk.DeviceID
                PartitionCount = $disk.Partitions
                BytesPerSector = $disk.BytesPerSector
                SizeGB = [math]::Round(($disk.Size/1GB),2)
                SCSIBus = $disk.SCSIBus
                SCSILogicalUnit = $disk.SCSILogicalUnit
                SCSIPort = $disk.SCSIPort
                SCSITargetId = $disk.SCSITargetId
                Volume = $partinfo.Name
                VolumeLabel = $partinfo.VolumeName
                VolumeSizeGB = [math]::Round(($partinfo.Size/1GB),2)
                VolumeFreeSpaceGB = [math]::Round(($partinfo.FreeSpace/1GB),2)
                }
                $LunMap | Out-Null
            Write-LogDebug "In $MyInvocation, the data returned in the loop is $LunMap"
            #Verify if disk is in array before appending
            if ($OutputArray.DeviceId -notcontains $disk.DeviceId)
            {     
                $OutputArray += $Lunmap
            }
        }
        $OutputArray = $OutputArray | Format-Table -Property * | Out-String -Width 512
        #Write data to file
        Add-Content -Path ($output_file) -Value ($OutputArray)

        #in case CTRL+C
        HandleCtrlC

        $HeaderInfo="-- Windows_Disk_Info --"
        $HeaderLength = (Get-Content -Path $output_file) -replace ("=", "-")| Where-Object {$_.trim() -ne ""}
        Set-Content $output_file -value $HeaderInfo,$HeaderLength
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}



function GetEventLogs($server) 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true
    
    $collector_name = $MyInvocation.MyCommand
    Write-LogInformation "Executing Collector:" $collector_name

    $server = $global:sql_instance_conn_str

    try {
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)

        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        $sbWriteLogBegin = {

            [System.Text.StringBuilder]$TXTEvtOutput = New-Object -TypeName System.Text.StringBuilder
            [System.Text.StringBuilder]$CSVEvtOutput = New-Object -TypeName System.Text.StringBuilder

            # TXT header
            [void]$TXTEvtOutput.Append("Date Time".PadRight(25))
            [void]$TXTEvtOutput.Append("Type/Level".PadRight(16))
            [void]$TXTEvtOutput.Append("Computer Name".PadRight(17))
            [void]$TXTEvtOutput.Append("EventID".PadRight(8))
            [void]$TXTEvtOutput.Append("Source".PadRight(51))
            [void]$TXTEvtOutput.Append("Task Category".PadRight(20))
            [void]$TXTEvtOutput.Append("Username".PadRight(51))
            [void]$TXTEvtOutput.AppendLine("Message")
            [void]$TXTEvtOutput.AppendLine("-" * 230)

            # CSV header
            [void]$CSVEvtOutput.AppendLine("`"EntryType`",`"TimeGenerated`",`"Source`",`"EventID`",`"Category`",`"Message`"")
        }

        $sbWriteLogProcess = {
            
            [string]$TimeGenerated = $_.TimeGenerated.ToString("MM/dd/yyyy hh:mm:ss tt")
            [string]$EntryType = $_.EntryType.ToString()
            [string]$MachineName = $_.MachineName.ToString()
            [string]$EventID = $_.EventID.ToString()
            [string]$Source = $_.Source.ToString()
            [string]$Category = $_.Category.ToString()
            [string]$UserName = $_.UserName
            [string]$Message = ((($_.Message.ToString() -replace "`r") -replace "`n", " ") -replace "`t", " ")

            # during testing some usernames are blank so we handle just like Windows Event Viewer displaying "N/A"
            if ($null -eq $UserName) {$UserName = "N/A"}

            # during testing some categories are "(0)" and Windows Event Viewer displays "None", so we just mimic same behavior
            if ("(0)" -eq $Category) {$Category = "None"}

            # TXT event record
            [void]$TXTEvtOutput.Append($TimeGenerated.PadRight(25))
            [void]$TXTEvtOutput.Append($EntryType.PadRight(16))
            [void]$TXTEvtOutput.Append($MachineName.PadRight(17))
            [void]$TXTEvtOutput.Append($EventID.PadRight(8))
            [void]$TXTEvtOutput.Append($Source.PadRight(50).Substring(0, 50).PadRight(51))
            [void]$TXTEvtOutput.Append($Category.PadRight(20))            
            [void]$TXTEvtOutput.Append($UserName.PadRight(50).Substring(0, 50).PadRight(51))
            [void]$TXTEvtOutput.AppendLine($Message)

            # CSV event record
            [void]$CSVEvtOutput.Append('"' + $EntryType + '",')
            [void]$CSVEvtOutput.Append('"' + $TimeGenerated + '",')
            [void]$CSVEvtOutput.Append('"' + $Source + '",')
            [void]$CSVEvtOutput.Append('"' + $EventID + '",')
            [void]$CSVEvtOutput.Append('"' + $Category + '",')
            [void]$CSVEvtOutput.AppendLine('"' + $Message + '"')

            $evtCount++

            # write to the files every 10000 events
            if (($evtCount % 10000) -eq 0) {
                
                $TXTevtfile.Write($TXTEvtOutput.ToString())
                $TXTevtfile.Flush()
                [void]$TXTEvtOutput.Clear()

                $CSVevtfile.Write($CSVEvtOutput.ToString())
                $CSVevtfile.Flush()
                [void]$CSVEvtOutput.Clear()

                Write-LogInformation "   Produced $evtCount records in the EventLog"

                #in case CTRL+C is pressed
                HandleCtrlC

            }

        }
        
        $sbWriteLogEnd = {
            # at end of process we write any remaining messages, flush and close the file    
            if ($TXTEvtOutput.Length -gt 0){
                $TXTevtfile.Write($TXTEvtOutput.ToString())
            }
            $TXTevtfile.Flush()
            $TXTevtfile.Close()

            if ($CSVEvtOutput.Length -gt 0){
                $CSVevtfile.Write($CSVEvtOutput.ToString())
            }
            $CSVevtfile.Flush()
            $CSVevtfile.Close()
            
            Remove-Variable -Name "TXTEvtOutput"
            Remove-Variable -Name "CSVEvtOutput"

            Write-LogInformation "   Produced $evtCount records in the EventLog"
        }

        Write-LogInformation "Gathering Application EventLog in TXT and CSV format  "
        
        $TXTevtfile = New-Object -TypeName System.IO.StreamWriter -ArgumentList (($partial_output_file_name + "_EventLog_Application.out"), $false, [System.Text.Encoding]::ASCII)
        $CSVevtfile = New-Object -TypeName System.IO.StreamWriter -ArgumentList (($partial_output_file_name + "_EventLog_Application.csv"), $false, [System.Text.Encoding]::ASCII)

        [int]$evtCount = 0

        Get-EventLog -LogName Application -After (Get-Date).AddDays(-90) | ForEach-Object -Begin $sbWriteLogBegin -Process $sbWriteLogProcess -End $sbWriteLogEnd 2>> $error_file | Out-Null
        
        Write-LogInformation "Application EventLog in TXT and CSV format completed!"

        #in case CTRL+C is pressed
        HandleCtrlC
        
        Write-LogInformation "Gathering System EventLog in TXT and CSV format  "

        $TXTevtfile = New-Object -TypeName System.IO.StreamWriter -ArgumentList (($partial_output_file_name + "_EventLog_System.out"), $false, [System.Text.Encoding]::ASCII)
        $CSVevtfile = New-Object -TypeName System.IO.StreamWriter -ArgumentList (($partial_output_file_name + "_EventLog_System.csv"), $false, [System.Text.Encoding]::ASCII)

        [int]$evtCount = 0

        Get-EventLog -LogName System -After (Get-Date).AddDays(-90) | ForEach-Object -Begin $sbWriteLogBegin -Process $sbWriteLogProcess -End $sbWriteLogEnd 2>> $error_file | Out-Null
        
        Write-LogInformation "System EventLog in TXT and CSV format completed!"

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetPowerPlan($server) 
{
    #power plan
    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
    
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
        $collector_name = "PowerPlan"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $power_plan_name = Get-WmiObject -Class win32_powerplan -Namespace root\cimv2\power | Where-Object IsActive -eq $true | Select-Object ElementName #|Out-File -FilePath $output_file
        Set-Content -Value "--- Power Plan ---","ActivePlanName","-------------------------------------------------------------------------------------------------------------------",$power_plan_name.ElementName -Path $output_file
        HandleCtrlC
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function Update-Coma([string]$in){
    if([string]::IsNullOrWhiteSpace($in)){
        return ""
    }else{
        return $in.Replace(",",".")
    }
}

function GetRunningDrivers() 
{
    <#
    .SYNOPSIS
        Get a list of running drivers in the system.
    .DESCRIPTION
        Writes a list of running drivers in the system in both TXT and CSV format.
    .PARAMETER FileName
        Specifies the file name to be written to. Extension TXT and CSV will be automatically added.
    .EXAMPLE
        .\Get-RunningDrivers"
#>


    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        
        $partial_output_file_name = CreatePartialOutputFilename ($server)

        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

    
        $collector_name = "RunningDrivers"
        $output_file_csv = ($partial_output_file_name + "_RunningDrivers.csv")
        $output_file_txt = ($partial_output_file_name + "_RunningDrivers.txt")
        Write-LogInformation "Executing Collector: $collector_name"
    
        Write-LogDebug $output_file_csv
        Write-LogDebug $output_file_txt
    
        #gather running drivers
        $driverproperties = Get-WmiObject Win32_SystemDriver | `
            where-object { $_.State -eq "Running" -and $_.PathName -ne $null  } | `
            Select-Object -Property PathName | `
            ForEach-Object { $_.Pathname.Replace("\??\", "") } | `
            Get-ItemProperty | `
            Select-Object -Property Length, LastWriteTime -ExpandProperty "VersionInfo" | `
            Sort-Object CompanyName, FileDescription

        [System.Text.StringBuilder]$TXToutput = New-Object -TypeName System.Text.StringBuilder
        [System.Text.StringBuilder]$CSVoutput = New-Object -TypeName System.Text.StringBuilder

        #CSV header
        [void]$CSVoutput.Append("ID,Module Path,Product Version,File Version,Company Name,File Description,File Size,File Time/Date String,`r`n")

        [int]$counter = 1

        foreach ($driver in $driverproperties) {
            [void]$TXToutput.Append("Module[" + $counter + "] [" + $driver.FileName + "]`r`n")
            [void]$TXToutput.Append("  Company Name:      " + $driver.CompanyName + "`r`n")
            [void]$TXToutput.Append("  File Description:  " + $driver.FileDescription + "`r`n")
            [void]$TXToutput.Append("  Product Version:   (" + $driver.ProductVersion + ")`r`n")
            [void]$TXToutput.Append("  File Version:      (" + $driver.FileVersion + ")`r`n")
            [void]$TXToutput.Append("  File Size (bytes): " + $driver.Length + "`r`n")
            [void]$TXToutput.Append("  File Date:         " + $driver.LastWriteTime + "`r`n")
            [void]$TXToutput.Append("`r`n`r`n")

            [void]$CSVoutput.Append($counter.ToString() + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.FileName)) + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.ProductVersion)) + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.FileVersion)) + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.CompanyName)) + ",")
            [void]$CSVoutput.Append((Update-Coma($driver.FileDescription)) + ",")
            [void]$CSVoutput.Append($driver.Length.ToString() + ",")
            [void]$CSVoutput.Append($driver.LastWriteTime.ToString() + ",")
            [void]$CSVoutput.Append("`r`n")
        
            #in case CTRL+C is pressed
            HandleCtrlC

            $counter++
        }

        Add-Content -Path ($output_file_txt) -Value ($TXToutput.ToString())
        Add-Content -Path ($output_file_csv) -Value ($CSVoutput.ToString())
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return     
    }
}

function GetFsutilSectorInfo()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "Fsutil_SectorInfo"
    Write-LogInformation "Executing Collector: $collector_name"

    $partial_output_file_name = CreatePartialOutputFilename ($server)
    Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

    $output_file_txt = ($partial_output_file_name + "_Fsutil_SectorInfo.out")
    Write-LogDebug $output_file_txt

    try 
    {
        [System.Text.StringBuilder] $fsutil_output = New-Object -TypeName System.Text.StringBuilder

        $fsutil_output.Append("-- fsutil sectorinfo--" + "`r`n") | Out-Null
        $fsutil_output.Append("fsutil_property                                         fsutil_value                   volume" + "`r`n") | Out-Null
        $fsutil_output.Append("------------------------------------------------------- ------------------------------ ---------------" + "`r`n") | Out-Null

        $vol = ""

        #get the volumes on the system. For now we get all of them. In the future we can devise logic to get only the SQL ones
        $vol_array = (Get-PsDrive -PsProvider FileSystem | Select-Object Root ).Root

        if ([String]::IsNullOrWhiteSpace($vol_array) -ne $true)
        {
            foreach ($vol in $vol_array)
            {
                $vol = $vol.Trim() -replace "\\", "" 
                
                Write-LogDebug "Disk volume for fsutil: $vol" -DebugLogLevel 4 


                #call the fsutil command for each volume
                $fsitems = fsutil fsinfo sectorinfo $vol


                #if the output seems proper fsutil output, then append it with formatting
                if ($fsitems[0].ToString().StartsWith("LogicalBytesPerSector"))
                {
                
                    foreach($item in $fsitems)
                    {
                        
                        $fsutil_output.Append($item + $(" " * (86 - $item.Length + 1) ) + $vol + "`r`n") | Out-Null
                    }
                }

                else 
                {
                    foreach($item in $fsitems)
                    {
                        
                        $fsutil_output.Append($item + "`r`n") | Out-Null
                    }
                }

            }

            Add-Content -Path ($output_file_txt) -Value ($fsutil_output.ToString())

        }
        
        
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}

function GetSQLSetupLogs(){
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "SQLSetupLogs"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
        Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\*\Bootstrap\' |
        ForEach-Object {

            [string]$SQLVersion = Split-Path -Path $_.BootstrapDir | Split-Path -Leaf
            [string]$DestinationFolder = $global:output_folder + $env:COMPUTERNAME + "_SQL" + $SQLVersion + "_Setup_Bootstrap"
        
            Write-LogDebug "_.BootstrapDir: $_.BootstrapDir" -DebugLogLevel 2
            Write-LogDebug "DestinationFolder: $DestinationFolder" -DebugLogLevel 2
        
            [string]$BootstrapLogFolder = $_.BootstrapDir + "Log\"

            if(Test-Path -Path $BootstrapLogFolder){

                Write-LogDebug "Executing: Copy-Item -Path ($BootstrapLogFolder) -Destination $DestinationFolder -Recurse"
                try
				{
                    Copy-Item -Path ($BootstrapLogFolder) -Destination $DestinationFolder -Recurse -ErrorAction Stop
                } 
				catch 
				{
                    Write-LogError "Error executing Copy-Item"
                    Write-LogError $_
                }

            } else {

                Write-LogWarning "No SQL Setup logs found in '$BootstrapLogFolder'. Reason: path does not exist"
            }
            
            #in case CTRL+C is pressed
            HandleCtrlC
        }
    } catch {

        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}

function GetInstallerRegistryKeys()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "InstallerRegistryKeys"
    Write-LogInformation "Executing Collector: $collector_name"

    [string]$RegKeyPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    [string]$RegKeyDest = $global:output_folder + $env:COMPUTERNAME + "_HKLM_CurVer_Uninstall.txt"
    Write-LogDebug "Getting Registry Keys from RegKeyPath: $RegKeyPath" -DebugLogLevel 2
    Write-LogDebug "Writing the registry keys output to RegKeyDest: $RegKeyDest" -DebugLogLevel 2
    GetRegistryKeys -RegPath $RegKeyPath -RegOutputFilename $RegKeyDest -Recurse $true

    [string]$RegKeyPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Microsoft SQL Server"
    [string]$RegKeyDest = $global:output_folder + $env:COMPUTERNAME + "_HKLM_MicrosoftSQLServer.txt"
    Write-LogDebug "Getting Registry Keys from RegKeyPath: $RegKeyPath" -DebugLogLevel 2
    Write-LogDebug "Writing the registry keys output to RegKeyDest: $RegKeyDest" -DebugLogLevel 2
    GetRegistryKeys -RegPath $RegKeyPath -RegOutputFilename $RegKeyDest -Recurse $true
}
    
function MSDiagProcsCollector() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true


    #in case CTRL+C is pressed
    HandleCtrlC

    try 
    {

        #msdiagprocs.sql
        #the output is potential errors so sent to error file
        $collector_name = "MSDiagProcs"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    
}

function GetXeventsGeneralPerf() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {
        
        ##create output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
    

        #XEvents file: xevent_general.sql - GENERAL Perf
        $collector_name_core = "Xevent_Core_AddSession"
        $collector_name_general = "Xevent_General_AddSession"


        # in case the xevent_SQLLogScout is already started, we can add the extra events at run time
        # else create the core events, then add the extra events and start the xevent trace
        if ($true -eq $global:xevent_on)
        {
            Start-SQLCmdProcess -collector_name $collector_name_general -input_script_name "xevent_general" -has_output_results $false
        }
        else 
        {
            Start-SQLCmdProcess -collector_name $collector_name_core -input_script_name "xevent_core" -has_output_results $false -wait_sync $true
            Start-SQLCmdProcess -collector_name $collector_name_general -input_script_name "xevent_general" -has_output_results $false

            Start-Sleep -Seconds 2

            #in case CTRL+C is pressed
            HandleCtrlC

			# introduce a synchronization lock in case somewhere simultaneously we decide to modify  $global:xevent_on
            [System.Threading.Monitor]::Enter($global:xevent_ht)
            $IsLocked = $true


            #add Xevent target
            $collector_name = "Xevent_General_Target"
            $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $global:xevent_target_file + ".xel' " + ", max_file_size=(500), max_rollover_files=(50)); END" 

            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_add_target -has_output_results $false -wait_sync $true


            #in case CTRL+C is pressed
            HandleCtrlC

            #start the XEvent session
            $collector_name = "Xevent_General_Start"
            $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session]  ON SERVER STATE = START; END"

            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_start -has_output_results $false

            # set the Xevent has been started flag to true
            $global:xevent_on = $true

            # signal the next waiting worker in line for the lock                    
            [System.Threading.Monitor]::Pulse($global:xevent_ht)

            # release the lock
            [System.Threading.Monitor]::Exit($global:xevent_ht)
            $IsLocked = $false
            
            Write-LogDebug "Lock on 'global:xevent_ht' released" -DebugLogLevel 4

        }

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

    finally {

        if ($true -eq $IsLocked)
        {
             # signal the next waiting worker in line for the lock                    
            [System.Threading.Monitor]::Pulse($global:xevent_ht)
            [System.Threading.Monitor]::Exit($global:xevent_ht)
        }
       
        Write-LogDebug "Finally(): Lock on 'global:xevent_ht' released" -DebugLogLevel 4
    }
}

function GetXeventsDetailedPerf() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)
    

        #XEvents file: xevent_detailed.sql - Detailed Perf
       
        $collector_name_core = "Xevent_CoreAddSession"
        $collector_name_detailed = "Xevent_DetailedAddSession"

        # in case the xevent_SQLLogScout is already started, we can add the extra events at run time
        # else create the core events, then add the extra events and start the xevent trace
        if ($true -eq $global:xevent_on)
        {
            Start-SQLCmdProcess -collector_name $collector_name_detailed -input_script_name "xevent_detailed" -has_output_results $false
        }
        else 
        {
            Start-SQLCmdProcess -collector_name $collector_name_core -input_script_name "xevent_core" -has_output_results $false -wait_sync $true
            Start-SQLCmdProcess -collector_name $collector_name_detailed -input_script_name "xevent_detailed" -has_output_results $false
        
        
            Start-Sleep -Seconds 2

            #in case CTRL+C is pressed
            HandleCtrlC

            # introduce a synchronization lock in case somewhere simultaneously we decide to modify  $global:xevent_on
            [System.Threading.Monitor]::Enter($global:xevent_ht)
            $IsLocked = $true

            #add Xevent target
            $collector_name = "Xevent_Detailed_Target"
            $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $global:xevent_target_file + ".xel'" + ", max_file_size=(500), max_rollover_files=(50)); END" 
            
            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_add_target -has_output_results $false -wait_sync $true

            #in case CTRL+C is pressed
            HandleCtrlC

            #start the XEvent session
            $collector_name = "Xevent_Detailed_Start"
            $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session]  ON SERVER STATE = START; END" 

            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_start -has_output_results $false
            
            # set the Xevent has been started flag to true
            $global:xevent_on = $true

            # signal the next waiting worker in line for the lock                    
            [System.Threading.Monitor]::Pulse($global:xevent_ht)

            # release the lock
            [System.Threading.Monitor]::Exit($global:xevent_ht)
            $IsLocked = $false
            
            Write-LogDebug "Lock on 'global:xevent_ht' released" -DebugLogLevel 4
        }

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

    finally {

        if ($true -eq $IsLocked)
        {
            # signal the next waiting worker in line for the lock                    
            [System.Threading.Monitor]::Pulse($global:xevent_ht)
            [System.Threading.Monitor]::Exit($global:xevent_ht)
            
        }
       
        Write-LogDebug "Finally(): Lock on 'global:xevent_ht' released" -DebugLogLevel 4
    }
}

function GetAlwaysOnDiag() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        
        #AlwaysOn Basic Info
        $collector_name = "AlwaysOnDiagScript"
        Start-SQLCmdProcess -collector_name "AlwaysOnDiagScript" -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetAGTopologyXml ()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try 
    {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        #Perfmon
        $collector_name = ("GetAGTopology")

        #using no wrapping quotes so I can add them later in the building of the argument list to generate file names dynamically
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -fileExt "_" -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -fileExt "" -needExtraQuotes $false
        $executable = "bcp.exe"

        Write-LogInformation "Executing Collector: $collector_name"

        $sql = "SELECT AGNode.group_name,
                       AGNode.replica_server_name,
                       AGNode.node_name,
                       ReplicaState.ROLE,
                       ReplicaState.role_desc,
                       ReplicaState.is_local,
                       DatabaseState.database_id,
                       db_name(DatabaseState.database_id) AS database_name,
                       DatabaseState.group_database_id,
                       DatabaseState.is_commit_participant,
                       DatabaseState.is_primary_replica,
                       DatabaseState.synchronization_state_desc,
                       DatabaseState.synchronization_health_desc,
                       ClusterState.group_id,
                       ReplicaState.replica_id
                FROM sys.dm_hadr_availability_replica_cluster_nodes AGNode
                JOIN sys.dm_hadr_availability_replica_cluster_states ClusterState ON AGNode.replica_server_name = ClusterState.replica_server_name
                JOIN sys.dm_hadr_availability_replica_states ReplicaState ON ReplicaState.replica_id = ClusterState.replica_id
                JOIN sys.dm_hadr_database_replica_states DatabaseState ON ReplicaState.replica_id = DatabaseState.replica_id
                FOR XML RAW, ROOT('AGInfoRoot');"

            # this is the bcp.exe argument list. bcp file and output files are built dynamically with the counter from the loop
            $argument_list = "`"" + $sql +"`"" + " queryout `"" + ($output_file + ".xml`"") + " -T -c -S " + $server + " -o `"" + ($error_file +".out `"")

            #launch the process
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden | Out-Null
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetXeventsAlwaysOnMovement() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str


    [console]::TreatControlCAsInput = $true

    try {
        
        $skip_AlwaysOn_DataMovement = $false;

        if (($global:sql_major_version -le 11) -or (($global:sql_major_version -eq 13) -and ($global:sql_major_build -lt 4001) ) -or (($global:sql_major_version -eq 12) -and ($global:sql_major_build -lt 5000)) )
        {
            $skip_AlwaysOn_DataMovement = $true
        }

        ##create error output filenames using the path + servername + date and time
        $partial_output_file_name = CreatePartialOutputFilename ($server)


        
        if ($skip_AlwaysOn_DataMovement)
        {
            Write-LogWarning "AlwaysOn_Data_Movement Xevents is not supported on SQL Server version $($global:sql_major_version.ToString() + ".0." + $global:sql_major_build.ToString()). Collection will be skipped. Other data will be collected."
        }
        else 
        {
            $collector_name = "Xevent_AlwaysOn_Data_Movement"
            Start-SQLCmdProcess -collector_name $collector_name -input_script_name "xevent_AlwaysOn_Data_Movement" -has_output_results $false
        }
        
        
        #in case CTRL+C is pressed
        HandleCtrlC

        Start-Sleep -Seconds 2

        #create the target Xevent files 

        if ($true -ne $global:xevent_on)
        {

            # introduce a synchronization lock in case somewhere simultaneously we decide to modify  $global:xevent_on
            [System.Threading.Monitor]::Enter($global:xevent_ht)
            $IsLocked = $true
            
            # create the XEvent sessions for Xevents         
            $collector_name_xeventcore = "Xevent_CoreAddSesion"
            Start-SQLCmdProcess -collector_name $collector_name_xeventcore -input_script_name "xevent_core" -has_output_results $false -wait_sync $true

            #add Xevent target
            $collector_name_xeventcore = "Xevent_CoreTarget"
            $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $global:xevent_target_file + ".xel' " + ", max_file_size=(500), max_rollover_files=(50)); END" 

            Start-SQLCmdProcess -collector_name $collector_name_xeventcore -is_query $true -query_text $alter_event_session_add_target -has_output_results $false -wait_sync $true

            #in case CTRL+C is pressed
            HandleCtrlC

            #start the XEvent session
            $collector_name_xeventcore = "Xevent_CoreStart"
            $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session]  ON SERVER STATE = START; END"
            
            Start-SQLCmdProcess -collector_name $collector_name_xeventcore -is_query $true -query_text $alter_event_session_start -has_output_results $false

            # set the Xevent has been started flag to be true
            $global:xevent_on = $true

            # signal the next waiting worker in line for the lock                    
            [System.Threading.Monitor]::Pulse($global:xevent_ht)

            # release the lock
            [System.Threading.Monitor]::Exit($global:xevent_ht)
            $IsLocked = $false

            Write-LogDebug "Lock on 'global:xevent_ht' released" -DebugLogLevel 4
        }


        #in case CTRL+C is pressed
        HandleCtrlC

        if ($skip_AlwaysOn_DataMovement -eq $false)
        {
            #add Xevent target
            $collector_name = "AlwaysOn_Data_Movement_target"
            $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_alwayson_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $collector_name + ".xel'" + ", max_file_size=(500), max_rollover_files=(50)); END" 
            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_add_target -has_output_results $false -wait_sync $true
            
            #in case CTRL+C is pressed
            HandleCtrlC

            #start the XEvent session
            $collector_name = "AlwaysOn_Data_Movement_Start"
            $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_alwayson_session]  ON SERVER STATE = START; END" 
            Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_start -has_output_results $false
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

    finally {

        if ($true -eq $IsLocked)
        {
            # signal the next waiting worker in line for the lock                    
            [System.Threading.Monitor]::Pulse($global:xevent_ht)

            [System.Threading.Monitor]::Exit($global:xevent_ht)
        }
       
        Write-LogDebug "Finally(): Lock on 'global:xevent_ht' released" -DebugLogLevel 4

    }
}

function GetAlwaysOnHealthXel
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    [console]::TreatControlCAsInput = $true

    $collector_name = "AlwaysOnHealthXevent"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
            $server = $global:sql_instance_conn_str
            $Result = GetSQLInstanceNameByPortNo($server)

            $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
            $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false


            if ($server -notlike '*\*')
            {
                $vInstance = "MSSQLSERVER"
                if ($Result -ne "")
                {
                    $vInstance = $Result
                }
            } 
            if ($server -like '*\*')
            {
                $selectInstanceName = $global:sql_instance_conn_str              
                $server = Get-InstanceNameOnly($selectInstanceName) 
                $vInstance = $server
                if ($Result -ne "")
                {
                    $vInstance = $Result
                }
            }
            [string]$DestinationFolder = $global:output_folder 


            #in case CTRL+C is pressed
            HandleCtrlC
            $vRegInst = (Get-ItemProperty -Path HKLM:"SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$vInstance
            $vRegPath = "SOFTWARE\Microsoft\Microsoft SQL Server\" + $vRegInst + "\MSSQLServer\Parameters" 
            $vLogPath = (Get-ItemProperty -Path HKLM:$vRegPath).SQLArg1 -replace '-e'
            $vLogPath = $vLogPath -replace 'ERRORLOG'
            Get-ChildItem -Path $vLogPath -Filter AlwaysOn_health*.xel | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null

        } 
        catch {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }

}


function GetXeventBackupRestore 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        if ($global:sql_major_version -ge 13)
        {
            ##create error output filenames using the path + servername + date and time
            $partial_output_file_name = CreatePartialOutputFilename ($server)

            #XEvents file: xevent_backup_restore.sql - Backup Restore
       
            $collector_name_core = "Xevent_Core_AddSession"
            $collector_name_bkp_rest  = "Xevent_BackupRestore_AddSession"

            
            # in case the xevent_SQLLogScout is already started, we can add the extra events at run time
            # else create the core events, then add the extra events and start the xevent trace
            if ($true -eq $global:xevent_on)
            {
                Start-SQLCmdProcess -collector_name $collector_name_bkp_rest -input_script_name "xevent_backup_restore" -has_output_results $false
            }
            else 
            {
                Start-SQLCmdProcess -collector_name $collector_name_core -input_script_name "xevent_core" -has_output_results $false -wait_sync $true
                Start-SQLCmdProcess -collector_name $collector_name_bkp_rest -input_script_name "xevent_backup_restore" -has_output_results $false

                Start-Sleep -Seconds 2

                #in case CTRL+C is pressed
                HandleCtrlC

                # introduce a synchronization lock in case somewhere simultaneously we decide to modify  $global:xevent_on
                [System.Threading.Monitor]::Enter($global:xevent_ht)
                $IsLocked = $true

                #add Xevent target
                $collector_name = "Xevent_BackupRestore_Target"
                $alter_event_session_add_target = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER ADD TARGET package0.event_file(SET filename=N'" + $partial_output_file_name + "_" + $global:xevent_target_file + ".xel' " + ", max_file_size=(500), max_rollover_files=(50)); END" 

                Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_add_target -has_output_results $false -wait_sync $true
                
                #in case CTRL+C is pressed
                HandleCtrlC

                #start the XEvent session
                $collector_name = "Xevent_BackupRestore_Start"
                $alter_event_session_start = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session]  ON SERVER STATE = START; END"
                

                Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_start -has_output_results $false
                # set the Xevent has been started flag to be true
                $global:xevent_on = $true

                # signal the next waiting worker in line for the lock                    
                [System.Threading.Monitor]::Pulse($global:xevent_ht)

                # release the lock
                [System.Threading.Monitor]::Exit($global:xevent_ht)
                $IsLocked = $false

                Write-LogDebug "Lock on 'global:xevent_ht' released" -DebugLogLevel 4
            }

        }
        else
        {
            Write-LogWarning "Backup_restore_progress_trace XEvent exists in SQL Server 2016 and higher and cannot be collected for instance '$server'. "
        }
        


    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

    finally {

        if ($true -eq $IsLocked)
        {
            # signal the next waiting worker in line for the lock                    
            [System.Threading.Monitor]::Pulse($global:xevent_ht)

            [System.Threading.Monitor]::Exit($global:xevent_ht)
        }
       
        Write-LogDebug "Finally(): Lock on 'global:xevent_ht' released" -DebugLogLevel 4

    }
}

function GetBackupRestoreTraceFlagOutput
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {

        #SQL Server Slow SQL Server Backup and Restore
        $collector_name = "EnableTraceFlag"
        $trace_flag_enabled = "DBCC TRACEON(3004,3212,3605,-1)"
        
        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $trace_flag_enabled -has_output_results $false
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return     
    }
}

function GetVSSAdminLogs()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true


    try 
    {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #list VSS Admin providers
        $collector_name = "VSSAdmin_Providers"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " list providers"
        $executable = "VSSAdmin.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file | Out-Null
        

        $collector_name = "VSSAdmin_Shadows"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " list shadows"
        $executable = "VSSAdmin.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file | Out-Null
        

        Start-Sleep -Seconds 1

        $collector_name = "VSSAdmin_Shadowstorage"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " list shadowstorage"
        $executable = "VSSAdmin.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file | Out-Null
        

        
        $collector_name = "VSSAdmin_Writers"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " list writers"
        $executable = "VSSAdmin.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file | Out-Null
        

            
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function SetVerboseSQLVSSWriterLog()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true
    
    if ($true -eq $global:sqlwriter_collector_has_run)
    {
        return
    }

    # set this to true
    $global:sqlwriter_collector_has_run = $true


    $collector_name = "SetVerboseSQLVSSWriterLog"
    Write-Loginformation "Executing collector: $collector_name"

    if ($global:sql_major_version -lt 15)
    {
        Write-LogDebug "SQL Server major version is $global:sql_major_version. Not collecting SQL VSS log" -DebugLogLevel 4
        return
    }


    try 
    {
        [string]$DestinationFolder = $global:output_folder
        
         # if backup restore scenario, we will get a verbose trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit))
        {
            
            Write-LogWarning "To enable SQL VSS VERBOSE loggging, the SQL VSS Writer service must be restarted now and when shutting down data collection. This is a very quick process." 
            
            Start-Sleep 4
            

            if ($global:gInteractivePrompts -eq "Quiet") 
            {
                Write-LogDebug "Running in 'Quiet' mode" -DebugLogLevel 4
                Write-LogWarning "You are running in QUIET mode: the SQL VSS Writer service will be restarted automatically (in 5 seconds)."
            
                Start-Sleep 1
                HandleCtrlC
                Start-Sleep 5
                $userinputvss = "Y"
                $global:restart_sqlwriter = "Y"
            }
            else
            {          
                $userinputvss = Read-Host "Do you want to restart SQL VSS Writer Service>" 
                $HelpMessage = "Please enter a valid input (Y or N)"

                $ValidInput = "Y","N"
                $AllInput = @()
                $AllInput += , $ValidInput
                $AllInput += , $userinputvss
                $AllInput += , $HelpMessage
                $global:restart_sqlwriter = validateUserInput($AllInput)
            }
            

            
            if($userinputvss -eq "Y")
            {
                
                if ("Running" -ne (Get-Service -Name SQLWriter).Status)
                {
                    Write-LogInformation "Attempting to start SQLWriter Service which is not running."
                    Restart-Service SQLWriter -force
                }
                
            }
            else  # ($userinputvss -eq "N")
            {
                Write-LogInformation "You have chosen not to restart SQLWriter Service. No verbose logging will be collected for SQL VSS Writer (2019 or later)"
                return
            }

            
            #  collect verbose SQL VSS Writer log if SQL 2019
            $file = 'C:\Program Files\Microsoft SQL Server\90\Shared\SqlWriterConfig.ini'
            if (!(Test-Path $file ))  
            {
                Write-LogWarning "Attempted to enable verbose logging in SqlWriterConfig.ini, but the file does not exist."
                Write-LogWarning "Verbose SQL VSS Writer logging will not be captured"
            }
            else
            {
                (Get-Content $file).Replace("TraceLevel=DEFAULT","TraceLevel=VERBOSE") | Set-Content $file
                (Get-Content $file).Replace("TraceFileSizeMb=1","TraceFileSizeMb=10") | Set-Content $file

                $matchfoundtracelevel = Get-Content $file | Select-String -Pattern 'TraceLevel=VERBOSE' -CaseSensitive -SimpleMatch
            
                if ([String]::IsNullOrEmpty -ne $matchfoundtracelevel)
                {
                    Write-LogDebug "The TraceLevel is setting is: $matchfoundtracelevel" -DebugLogLevel 4
                }

                $matchfoundFileSize = Get-Content $file | Select-String -Pattern 'TraceFileSizeMb=10' -CaseSensitive -SimpleMatch
            
                if ([String]::IsNullOrEmpty -ne $matchfoundFileSize)
                {
                    Write-LogDebug "The TraceFileSizeMb is: $matchfoundFileSize" -DebugLogLevel 4
                }

                Write-LogInformation "Retarting SQLWriter Service."
                Restart-Service SQLWriter -force
            }

        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    finally 
    {
        # we just finished executing this once, don't repeat
        $global:sqlwriter_collector_has_run = $true
        Write-LogDebug "Inside finally block for SQLVSSWriter log." -DebugLogLevel 5
    }
}
function GetSysteminfoSummary() 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try 
    {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #Systeminfo (MSInfo)
        $collector_name = "SystemInfo_Summary"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name $collector_name  
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "systeminfo"
        $argument_list = "/FO LIST"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -RedirectStandardOutput $output_file | Out-Null
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetMiscDiagInfo() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true

    try 
    {
        #in case CTRL+C is pressed
        HandleCtrlC

        #misc DMVs 
        $collector_name = "MiscPssdiagInfo"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetErrorlogs() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {

        #in case CTRL+C is pressed
        HandleCtrlC

        #errorlogs
        $collector_name = "collecterrorlog"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetTaskList () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true

    try {

        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        ##task list
        #tasklist processes
    
        $collector_name = "TaskListVerbose"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $tasklist = $output_file
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "tasklist.exe"
        $argument_list = "/V /FO TABLE"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file -Wait $true | Out-Null
        #Makeit importable in SQL Nexus
        $newline="`n-- task_list --"
        $tasklist = (Get-Content -Path $output_file) -replace ("=", "-")| Where-Object {$_.trim() -ne ""} 
        Set-Content $output_file -value $newline,$tasklist
        #in case CTRL+C
        HandleCtrlC


        #tasklist services
        $collector_name = "TaskListServices"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $tasklist_SVC = $output_file
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
        $executable = "tasklist.exe"
        $argument_list = "/SVC"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file -Wait $true | Out-Null
        #Makeit importable in SQL Nexus
        $newline="`n-- service_list --"
        $tasklist = (Get-Content -Path $output_file) -replace ("=", "-")| Where-Object {$_.trim() -ne ""} 
        Set-Content $output_file -value $newline,$tasklist
            
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetRunningProfilerXeventTraces () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try {

        #in case CTRL+C is pressed
        HandleCtrlC

        #active profiler traces and xevents
        $collector_name = "ExistingProfilerXeventTraces"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name "Profiler Traces"
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }


}

function GetHighCPUPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true


    try {

        #in case CTRL+C is pressed
        HandleCtrlC

        #SQL Server High CPU Perf Stats
        $collector_name = "HighCPU_perfstats"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {
        
        Start-SQLCmdProcess -collector_name "PerfStats" -input_script_name "SQL Server Perf Stats"
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetPerfStatsSnapshot ([string] $TimeOfCapture="Startup") 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true


    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of PerfStats shutdown collector"
        return
    }

    try 
    {
        [bool] $wait_synchonous = $false

        #for shutdown we must wait for the script to complete, otherwise the Kill script will terminate its execution in the middle
        if ($TimeOfCapture -eq "Shutdown")
        {
            $wait_synchonous = $true
        }

        
        #SQL Server Perf Stats Snapshot
        Start-SQLCmdProcess -collector_name ("PerfStatsSnapshot"+ $TimeOfCapture) -input_script_name "SQL Server Perf Stats Snapshot" -Wait $wait_synchonous
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetTopNQueryPlansInXml ([int] $PlanCount = 5, [string] $TimeOfCapture = "Shutdown")
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try 
    {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        #Perfmon
        $collector_name = ("Top_CPU_QueryPlansXml_" + $TimeOfCapture)

        #using no wrapping quotes so I can add them later in the building of the argument list to generate file names dynamically
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -fileExt "_" -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -fileExt "_" -needExtraQuotes $false
        $executable = "bcp.exe"

        Write-LogInformation "Executing Collector: $collector_name"

        for ($i=1; $i -le $PlanCount; $i++)
        {

            $sql = "SELECT xmlplan FROM (SELECT ROW_NUMBER() OVER(ORDER BY (highest_cpu_queries.total_worker_time/highest_cpu_queries.execution_count) DESC) AS RowNumber,
                    CAST(query_plan AS XML) xmlplan FROM (SELECT TOP " + ($PlanCount.ToString()) + " qs.plan_handle, qs.total_worker_time,qs.execution_count FROM sys.dm_exec_query_stats qs
                    ORDER BY qs.total_worker_time DESC) AS highest_cpu_queries CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS q CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS p) AS x
                    WHERE RowNumber = $i"

            # this is the bcp.exe argument list. bcp file and output files are built dynamically with the counter from the loop
            $argument_list = "`"" + $sql +"`"" + " queryout `"" + ($output_file + $i + ".sqlplan`"") + " -T -c -S " + $server + " -o `"" + ($error_file + "_" + $i + ".out `"")

            #launch the process
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden | Out-Null
    

            # take a break to ensure no CPU spikes on the system
            Start-Sleep -Milliseconds 100

        }
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetPerfmonCounters () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    [console]::TreatControlCAsInput = $true

    if ($true -eq $global:perfmon_is_on)
    {
        Write-LogDebug "Perfmon has already been started by another collector." -DebugLogLevel 3
        return
    }

    $server = $global:sql_instance_conn_str
    $internal_folder = $global:internal_output_folder

    try {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        #Perfmon
        $collector_name = "Perfmon"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
        $executable = "cmd.exe"
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon & logman CREATE COUNTER -n logscoutperfmon -cf `"" + $internal_folder + "LogmanConfig.txt`" -f bin -si 00:00:05 -max 250 -cnf 01:00:00  -o " + $output_file + "  & logman start logscoutperfmon "
        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file | Out-Null

        #turn on the perfmon notification to let others know it is enabled
        $global:perfmon_is_on = $true
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetServiceBrokerInfo () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {
        #in case CTRL+C is pressed
        HandleCtrlC

        #Service Broker collection
        $collector_name = "SSB_diag"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetTempdbSpaceLatchingStats () 
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try {


        #Tempdb space and latching
        $collector_name = "TempDB_and_Tran_Analysis"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetLinkedServerInfo () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try {

        #Linked Server configuration
        $collector_name = "linked_server_config"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetQDSInfo () 
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try {

        #Query Store
        $collector_name = "Query Store"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}


function GetReplMetadata ([string] $TimeOfCapture = "Shutdown") 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        #Prompt user that if they are running in quiet mode, we are not going to prompt.
        if ($global:gInteractivePrompts -eq "Quiet") 
        {
            Write-LogWarning "Selecting the 'Quiet' option assumes you pressed 'Y' for all user input prompts"
            Start-Sleep -Seconds 5
        }


        [bool] $wait_synchonous = $true

        [string] $server_name = $global:sql_instance_conn_str

        #Code to check if distribution is a remote distributor or not. Read from the sqlcmd out file from the function and if anything other than local, we want to prompt user/exit.
        
        
        $SqlQuery = "SELECT provider_string, data_source FROM master.sys.servers WITH (NOLOCK) WHERE is_distributor = 1 "
        $ConnString = "Server=$($global:sql_instance_conn_str);Database=master;Integrated Security=True;Application Name=SQLLogScout;"
    
        Write-LogDebug "connection string = $ConnString" -DebugLogLevel 2

        Write-LogDebug "Creating SqlClient objects and setting parameters" -DebugLogLevel 2
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = $ConnString
        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.CommandText = $SqlQuery
        $SqlCmd.Connection = $SqlConnection
        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $SqlAdapter.SelectCommand = $SqlCmd
        $DataSetPermissions = New-Object System.Data.DataSet
    
        Write-LogDebug "About to call SqlDataAdapter.Fill()" -DebugLogLevel 2
        try {
            $SqlAdapter.Fill($DataSetPermissions) | Out-Null #fill method returns rowcount, Out-Null prevents the number from being printed in console    
        }
        catch {
            Write-LogError "Could not connect to SQL Server instance '$SQLInstance' to get distributor information."
            
            $mycommand = $MyInvocation.MyCommand
            $error_msg = $PSItem.Exception.InnerException.Message 
            Write-LogError "$mycommand Function failed with error:  $error_msg"
            
            # we can't connect to SQL, probably whole capture will fail, so we just abort here
            return $false
        }
    
        $distributor_provider_string = $DataSetPermissions.Tables[0].Rows[0].provider_string
        $distributor_data_source = $DataSetPermissions.Tables[0].Rows[0].data_source


        #Check to see if distributor is blank. If it is, repl isn't configured. Return.
        if ([String]::IsNullOrWhiteSpace($distributor_data_source) -eq $true)
        {
            Write-LogInformation "Distributor not identified on $server_name. Skipping replication collector." -ForegroundColor Yellow
            return
        }


        
        
        #Check to see if the data source stored as distributor matches instance name. If so, distributor is local. Get the data. 
        if ($distributor_data_source -eq $global:sql_instance_conn_str)
        {
            Write-LogInformation "Local Distributor identified. Collecting Replication Metadata." -ForegroundColor Green
            $collector_name = "Repl_Metadata_Collector" 
            #We are passing the setsqlcmddisplaywidth as the comments field is very important in the history tables and can be 4k characters.
            Start-SQLCmdProcess -collector_name ($collector_name + $TimeOfCapture) -input_script_name $collector_name -wait_sync $wait_synchonous -server $server_name -setsqlcmddisplaywidth "4096"
        }

        #If user runs script in quiet mode, then just get the data.
        elseif ($global:gInteractivePrompts -eq "Quiet")
        {
            Write-LogInformation "Remote Distributor identified and Quiet parameter passed. Collecting data without prompting." -ForegroundColor Green
            if ([String]::IsNullOrWhiteSpace($distributor_provider_string) -eq $true)
                    {
                        $server_name = $distributor_data_source
                    }
                else 
                    {
                        #strip the addr= from provider string
                        Write-LogInformation "Provider string value is populated in sys.servers for distribution" -ForegroundColor Green
                        $server_name1 = $distributor_provider_string.Replace("addr=","")
                        $server_name = $server_name1.Replace("tcp:","")
                    }
        }

        else 
        {
            Write-LogInformation "Remote Distributor identified. Please respond below..." -ForegroundColor Yellow
            #If distributor is not local, we need to connect to remote distributor.
            
            
            $RemoteDistributorPrompt = Read-Host -Prompt "Discovered remote Distributor $distributor_data_source. Is it OK to connect to it and collect metadata? Y or N" -CustomLogMessage "You responded:"
            $HelpMessage = "Please enter a valid input (Y or N)"

            $ValidInput = "Y","N"
            $AllInput = @()
            $AllInput += , $ValidInput
            $AllInput += , $RemoteDistributorPrompt
            $AllInput += , $HelpMessage

            $YNselected = validateUserInput($AllInput)
            
            #Remote distributor and user chose to collect data.
            if ($YNselected -eq "Y")
            {
                #For distributor in AG, we can populate the provider string in sys.servers. 
                #If provider_string is blank, just use data source.
                #If it is populated, we need to strip out the connection string and connect to that machine - especially important for custom port.
                if ([String]::IsNullOrWhiteSpace($distributor_provider_string) -eq $true)
                    {
                        $server_name = $distributor_data_source
                    }
                else 
                    {
                        #strip the addr= from provider string
                        Write-LogInformation "Provider string value is populated in sys.servers for distribution" -ForegroundColor Green
                        $server_name1 = $distributor_provider_string.Replace("addr=","")
                        $server_name = $server_name1.Replace("tcp:","")
                    }
                
                Write-LogInformation "Remote Distributor identified and user confirmed collection of data. Collecting Replication Metadata from $server_name." -ForegroundColor Green
                $collector_name = "Repl_Metadata_Collector" 
                #User selected to collect data. Proceed.
                #We are passing the setsqlcmddisplaywidth as the comments field is very important in the history tables and can be 4k characters. SQLCMD will truncate this by default.
                Start-SQLCmdProcess -collector_name ($collector_name + $TimeOfCapture) -input_script_name $collector_name -wait_sync $wait_synchonous -server $server_name -setsqlcmddisplaywidth "4096"
            
            }

            #User declined remote data capture.
            if ($YNselected -eq "N")
            {
                Write-LogInformation "You chose to not collect distributor information from $distributor_data_source. Skipping replication collector."
                return
            }
    
            

        }
    }

    catch

    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetChangeDataCaptureInfo ([string] $TimeOfCapture = "Startup") {
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        [bool] $wait_synchonous = $false

        #for shutdown we must wait for the script to complete, otherwise the Kill script will terminate its execution in the middle
        if ($TimeOfCapture -eq "Shutdown")
        {
            $wait_synchonous = $true
        }

        #Change Data Capture (CDC)
        $collector_name = "ChangeDataCapture" 
        Start-SQLCmdProcess -collector_name ($collector_name + $TimeOfCapture) -input_script_name $collector_name -wait_sync $wait_synchonous
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetChangeTracking ([string] $TimeOfCapture = "Startup") 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        [bool] $wait_synchonous = $false

        #for shutdown we must wait for the script to complete, otherwise the Kill script will terminate its execution in the middle
        if ($TimeOfCapture -eq "Shutdown")
        {
            $wait_synchonous = $true
        }

        #Change Tracking
        $collector_name = "Change_Tracking"
        Start-SQLCmdProcess -collector_name ($collector_name + $TimeOfCapture) -input_script_name $collector_name -wait_sync $wait_synchonous
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetFilterDrivers () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

        #filter drivers
        $collector_name = "FLTMC_Filters"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $argument_list = " filters"
        $executable = "fltmc.exe"
        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file -Wait $true | Out-Null
        #Makeit importable in SQL Nexus
        $newline="`n-- fltmc_filters --"
        $fltmclist = (Get-Content -Path $output_file) -replace ("=", "-")| Where-Object {$_.trim() -ne ""} 
        Set-Content $output_file -value $newline, $fltmclist


        #filters instance
        $collector_name = "FLTMC_Instances"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  
        $executable = "fltmc.exe"
        $argument_list = " instances"
        Write-LogInformation "Executing Collector: $collector_name"
        
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardOutput $output_file -WindowStyle Hidden -RedirectStandardError $error_file -Wait $true | Out-Null
        #Makeit importable in SQL Nexus
        $newline="`n-- fltmc_instances --"
        $fltmclist = (Get-Content -Path $output_file) -replace ("=", "-")| Where-Object {$_.trim() -ne ""} 
        Set-Content $output_file -value $newline, $fltmclist

    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}


function GetNetworkTrace () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true
    
    $server = $global:sql_instance_conn_str

    $internal_folder = $global:internal_output_folder

    try {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
    
        #in case CTRL+C is pressed
        HandleCtrlC

        
        #netsh to configure the network trace
        $collector_name = $global:NETWORKTRACE_NAME + "_NetshConfig"
        $netsh_error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stderr") -needExtraQuotes $false
        #use the errorfile logic to redirect any output to \internal folder
        $netsh_output_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stdout") -needExtraQuotes $false
        $netsh_delete_me = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name "delete" -needExtraQuotes $true -fileExt ".me"
        
        
        $executable = "netsh"
        $argument_list = "trace start capture=yes maxsize=1 report=disabled tracefile=" + $netsh_delete_me
        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Normal -RedirectStandardOutput $netsh_output_file -RedirectStandardError $netsh_error_file | Out-Null


        #logman to start the capture
        $collector_name = $global:NETWORKTRACE_NAME + "_LogmanStart"
        #use the errorfile logic to redirect any output to \internal folder
        $logman_error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stderr") -needExtraQuotes $false
        $logman_output_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stdout") -needExtraQuotes $false
        $etl_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt "%d.etl"

        $executable = "logman"
        $argument_list = "start -n sqllogscoutndiscap -p Microsoft-Windows-NDIS-PacketCapture -mode newfile -max 200 -o $etl_file -ets"
        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $logman_output_file -RedirectStandardError $logman_error_file | Out-Null


    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetMemoryDumps () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand


    try {
    
        $InstanceSearchStr = ""
        #strip the server name from connection string so it can be used for looking up PID
        $instanceonly = Get-InstanceNameOnly -NetnamePlusInstance $global:sql_instance_conn_str


        #if default instance use "MSSQLSERVER", else "MSSQL$InstanceName
        if ($instanceonly -eq $global:host_name) {
            $InstanceSearchStr = "MSSQLSERVER"
        }
        else {
            $InstanceSearchStr = "MSSQL$" + $instanceonly

        }
		$collector_name = "Memorydump"
        Write-LogDebug "Output folder is $global:output_folder" -DebugLogLevel 2
        Write-LogDebug "Service name is $InstanceSearchStr" -DebugLogLevel 2
        Write-LogInformation "Executing Collector: $collector_name"
        #invoke SQLDumpHelper
        .\SQLDumpHelper.ps1 -DumpOutputFolder $global:output_folder -InstanceOnlyName $InstanceSearchStr
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
} 


function CheckWPRVersion
{
    try 
    {
        [System.Version]$WPRVersion = '0.0.0.0'

        #Strip out only WPR version and remove Windows info so we get a comparable string.
        $CheckWPRExists = Get-Command -Name "wpr.exe" -ErrorAction Ignore
        if ($null -ne $CheckWPRExists)
        {
            $FullVersionInfo = (Get-Command -Name "wpr.exe" -ErrorAction Ignore).FileVersionInfo.FileVersion

            if ([string]::IsNullOrEmpty($FullVersionInfo) -eq $false)
            {
                $PartString = $FullVersionInfo.IndexOf("(")
                $WPRVersion = $FullVersionInfo.Substring(0,$PartString-1)
                Write-LogDebug "WPR version identified: $WPRVersion" -DebugLogLevel 1
            }
        }


        else 
        {
            Write-LogError "WPR.exe not found. Data collection cancelled. Please install WPR to continue or select a different scenario. Exiting..."
            #Keep window up long enough for user to read message.
            Start-Sleep -s 7
            exit
        }
    }
    
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return $WPRVersion
    }

   return $WPRVersion
}

function GetWPRTrace () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    $server = $global:host_name
    
    [console]::TreatControlCAsInput = $true


    try {

        $WPRVersionCheck = CheckWPRVersion

        if ($WPRVersionCheck -ne '0.0.0.0')
        {
            
      
            #$partial_error_output_file_name = CreatePartialErrorOutputFilename -server $server
            $partial_output_file_name = CreatePartialOutputFilename ($server)
            $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)

            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3

            #choose collector type

            
            [string[]] $WPRArray = "CPU", "Heap and Virtual memory", "Disk and File I/O", "Filter drivers"
            $WPRIntRange = 0..($global:ScenarioArray.Length - 1)  

            Write-LogInformation "Please select one of the following Data Collection Type:`n"
            Write-LogInformation ""
            Write-LogInformation "ID   WPR Profile"
            Write-LogInformation "--   ---------------"

            for ($i = 0; $i -lt $WPRArray.Count; $i++) {
                Write-LogInformation $i "  " $WPRArray[$i]
            }
            $isInt = $false
            
            Write-LogInformation ""
            Write-LogWarning "Enter the WPR Profile ID for which you want to collect performance data. Then press Enter" 

            $ValidInput = "0","1","2","3"
            $wprIdStr = Read-Host "Enter the WPR Profile ID from list above>" -CustomLogMessage "WPR Profile Console input:"
            $HelpMessage = "Please enter a valid input (0,1,2 or 3)"

            #$AllInput = $ValidInput,$WPR_YesNo,$HelpMessage 
            $AllInput = @()
            $AllInput += , $ValidInput
            $AllInput += , $wprIdStr
            $AllInput += , $HelpMessage
        
            $wprIdStr = validateUserInput($AllInput)

            #Write-LogInformation "WPR Profile Console input: $wprIdStr"
            
            try {
                $wprIdStrIdInt = [convert]::ToInt32($wprIdStr)
                $isInt = $true
            }

            catch [FormatException] {
                Write-LogError "The value entered for ID '", $ScenIdStr, "' is not an integer"
                continue 
            }
            #Take user input for collection time for WPR trace
            $ValidInputRuntime = (3..45)

            Write-LogWarning "How long do you want to run the WPR trace (maximum 45 seconds)?"
            $wprruntime = Read-Host "number of seconds (maximum 45 seconds)>" -CustomLogMessage "WPR runtime input:"

            $HelpMessageRuntime = "This is an invalid entry. Please enter a value between 3 and 45 seconds"
            $AllInputruntime = @()
            $AllInputruntime += , $ValidInputRuntime
            $AllInputruntime += , $wprruntime
            $AllInputruntime += , $HelpMessageRuntime
            
            $wprruntime = validateUserInput($AllInputruntime)
            
            Write-LogInformation "You selected $wprruntime seconds to run WPR Trace"
            #Write-Host "The configuration is ready. Press <Enter> key to proceed..."
            Read-Host -Prompt "<Press Enter> to proceed"

            If ($isInt -eq $true) {
                #Perfmon
                
                switch ($wprIdStr) {
                    "0" { 
                        $collector_name = $global:wpr_collector_name= "WPR_CPU"
                        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start CPU -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file | Out-Null
                        
                        Start-Sleep -s $wprruntime 
                    }
                    "1" { 
                        $collector_name = $global:wpr_collector_name = "WPR_HeapAndVirtualMemory"
                        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start Heap -start VirtualAllocation  -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file | Out-Null
                        
                        Start-Sleep -s $wprruntime 
                    }
                    "2" { 
                        $collector_name = $global:wpr_collector_name = "WPR_DiskIO_FileIO"
                        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start DiskIO -start FileIO -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file | Out-Null
                        
                        Start-Sleep -s $wprruntime 
                    }
                    "3" { 
                        $collector_name = $global:wpr_collector_name = "WPR_MiniFilters"
                        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                        $executable = "cmd.exe"
                        $argument_list = "/C wpr.exe -start Minifilter -filemode "
                        Write-LogInformation "Executing Collector: $collector_name"
                        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file | Out-Null
                        
                        Start-Sleep -s $wprruntime 
                    }                    
                }
            }
        }
    
        else {
            Write-Error -Message "Unable to find WPR on your machine. Exiting."
            return
        }

    
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    }



function GetMemoryLogs()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true


    try 
    {
        #Change Tracking
        $collector_name = "SQL_Server_Mem_Stats"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
        
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }


}

function GetClusterInformation()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str
    $output_folder = $global:output_folder
    $ClusterError = 0
    $collector_name = "ClusterLogs"
    $partial_output_file_name = CreatePartialOutputFilename ($server)

    
    Write-LogInformation "Executing Collector: $collector_name"

    $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false -fileExt ".out"
    [System.Text.StringBuilder]$rs_ClusterLog = New-Object -TypeName System.Text.StringBuilder


    
    if ($ClusterError -eq 0)
    {
        try 
        {
                #Cluster Registry Hive
                $collector_name = "ClusterRegistryHive"
                
                $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false -fileExt ".out"
                Get-ChildItem 'HKLM:HKEY_LOCAL_MACHINE\Cluster' -Recurse | Out-File -FilePath $output_file
                
                $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".hiv"
                $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name  -needExtraQuotes $false
                $executable = "reg.exe"
                $argument_list = "save `"HKEY_LOCAL_MACHINE\Cluster`" $output_file"
                Write-LogInformation "Executing Collector: $collector_name"
                
                StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file | Out-Null

        }
        catch
        {
                $function_name = $MyInvocation.MyCommand 
                $error_msg = $PSItem.Exception.Message 
				$error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
				$error_offset = $PSItem.InvocationInfo.OffsetInLine
                Write-LogError "$function_name - Error while accessing cluster registry keys...:  $error_msg (line: $error_linenum, $error_offset)"
        }

        $collector_name = "ClusterInfo"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false -fileExt ".out"

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Nodes --`r`n")
            $clusternodenames =  Get-Clusternode | Out-String
            [void]$rs_ClusterLog.Append("$clusternodenames`r`n")
            
            #in case CTRL+C is pressed
            HandleCtrlC
        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster (node):  $error_msg"
        }
 
        try 
        {
            Import-Module FailoverClusters
            [void]$rs_ClusterLog.Append("-- Windows Cluster Name --`r`n")
            $clusterName = Get-cluster
            [void]$rs_ClusterLog.Append("$clusterName`r`n")
            
            #dumping windows cluster log
            Write-LogInformation "Collecting Windows cluster log for all running nodes, this process may take some time....."
            $nodes =  Get-Clusternode | Where-Object {$_.state -eq 'Up'} |Select-Object name  

            Foreach ($node in $nodes)
            {
                #in case CTRL+C is pressed
                HandleCtrlC
                Get-ClusterLog -Node $node.name -Destination $output_folder  -UseLocalTime | Out-Null
            }
        }
        catch 
        {
            $ClusterError = 1
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }


        try
        {
            [void]$rs_ClusterLog.Append("-- Cluster Network Interfaces --`r`n")
            $ClusterNetworkInterface = Get-ClusterNetworkInterface | Out-String
            [void]$rs_ClusterLog.Append("$ClusterNetworkInterface`r`n") 

            #in case CTRL+C is pressed
            HandleCtrlC
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Cluster Network Interface:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Shared Volume(s) --`r`n")
            $ClusterSharedVolume = Get-ClusterSharedVolume | Out-String
            [void]$rs_ClusterLog.Append("$ClusterSharedVolume`r`n") 

        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Cluster Shared Volume:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Cluster Quorum --`r`n")
            $ClusterQuorum = Get-ClusterQuorum | Format-List * | Out-String
            [void]$rs_ClusterLog.Append("$ClusterQuorum`r`n") 

            #in case CTRL+C is pressed
            HandleCtrlC

            Get-Clusterquorum | ForEach-Object {
                        $cluster = $_.Cluster
                        $QuorumResource = $_.QuorumResource
                        $QuorumType = $_.QuorumType
            
                        # $results = New-Object PSObject -property @{
                        # "QuorumResource" = $QuorumResource
                        # "QuorumType" = $QuorumType
                        # "cluster" = $Cluster
                        } | Out-String

            [void]$rs_ClusterLog.Append("$results`r`n") 
           
        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Cluster Quorum:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Physical Disks --`r`n")
            $PhysicalDisk = Get-PhysicalDisk | Out-String           
            [void]$rs_ClusterLog.Append("$PhysicalDisk`r`n") 
        }
        catch {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Physical Disk:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Groups (Roles) --`r`n")
            $clustergroup = Get-Clustergroup | Out-String
            [void]$rs_ClusterLog.Append("$clustergroup`r`n") 

            #in case CTRL+C is pressed
            HandleCtrlC
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster group:  $error_msg"
        }
        
        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Resources --`r`n")
            $clusterresource = Get-ClusterResource | Out-String
            [void]$rs_ClusterLog.Append("$clusterresource`r`n")

        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster resource:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Net Firewall Profiles --`r`n")
            $NetFirewallProfile = Get-NetFirewallProfile | Out-String
            [void]$rs_ClusterLog.Append("$NetFirewallProfile`r`n") 
        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing Net Firewall Profile:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- cluster clusternetwork --`r`n")
            $clusternetwork = Get-clusternetwork| Format-List * | Out-String
            [void]$rs_ClusterLog.Append("$clusternetwork`r`n") 
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster network:  $error_msg"
        }

       try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Info--`r`n")
            $clusterfl = Get-Cluster | Format-List *  | Out-String
            [void]$rs_ClusterLog.Append("$clusterfl`r`n") 

            #in case CTRL+C is pressed
            HandleCtrlC
        }
        catch 
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster configured value:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- Cluster Access--`r`n")
            $clusteraccess = get-clusteraccess | Out-String
            [void]$rs_ClusterLog.Append("$clusteraccess`r`n") 
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster access settings:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("-- cluster Node Details --`r`n")
            $clusternodefl = get-clusternode | Format-List * | Out-String
            [void]$rs_ClusterLog.Append("$clusternodefl`r`n") 
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster node configured value:  $error_msg"
        }

        try 
        {
            [void]$rs_ClusterLog.Append("   `r`n")
            [void]$rs_ClusterLog.Append("-- Availability Group timeout settings --`r`n")
            [void]$rs_ClusterLog.Append("Availability Group               timeout_setting_name     timeout_value`r`n")
            [void]$rs_ClusterLog.Append("-------------------------------- ------------------------ -------------`r`n")


            $clresources = Get-ClusterResource

            ForEach($resource in $clresources) 
            {
                if($resource.ResourceType -eq "SQL Server Availability Group")
                {
                    $name = $resource.Name
                    $healthCheckTimeout = (Get-ClusterParameter -Name HealthCheckTimeout -InputObject $resource).Value 
                    $HealthCheckTimeout = $name + " "*(32 - $name.Length) + " HealthCheckTimeout       " + $healthCheckTimeout.ToString()

                    $leaseTimeout = (Get-ClusterParameter -Name LeaseTimeout -InputObject $resource).Value     
                    $LeaseTimeout = $name + " "*(32 - $name.Length) + " LeaseTimeout             "+ $leaseTimeout.ToString()
            
                    [void]$rs_ClusterLog.Append("$HealthCheckTimeout`r`n") 
                    [void]$rs_ClusterLog.Append("$LeaseTimeout`r`n")
                }
            }
        }
        catch
        {
            $function_name = $MyInvocation.MyCommand 
            $error_msg = $PSItem.Exception.Message 
            Write-LogError "$function_name - Error while accessing cluster node configured value:  $error_msg"
        }

        Add-Content -Path ($output_file) -Value ($rs_ClusterLog.ToString())
    }
}

function GetSQLAzureArcLogs(){
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str
    $hostname = $global:host_name

    # This lets the SQLLogScout process listen for ctrl+c input and handle CtrlC which in our case will exit out of SQLLogScout after calling the shutdown process
    [console]::TreatControlCAsInput = $true

    $collector_name = "SQLAzureArcLogs"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
            # This variable represents the azcmagent output compressed file name which we build here to mimic what azcmagent generates by default.
            $SQLAzureArcLogOutputTarget = "`"" + $global:output_folder + "azcmagent-logs-" + (Get-Date).ToString("yyMMddThhmm") + $hostname + ".zip" + "`""

            
            # Check to see if Arc connected machine agent is installed which comes with the azcmagent utiliity. If this utility is not installed, we can safely assume that SQL ARC extension is also not correctly installed.
            if ( ($null -ne (Get-Command "azcmagent.exe" -ErrorAction SilentlyContinue) ) -or (Test-Path -Path "C:\Program Files\AzureConnectedMachineAgent\azcmagent.exe") -eq $true )
            { 
                $partial_output_file_name = CreatePartialOutputFilename ($server)
                $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
                Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
                Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
            
                #in case CTRL+C is pressed
                HandleCtrlC

                $collector_name = "SQLAzureArcLogs"
                $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
                $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
                $argument_list = " logs -f -o " + $SQLAzureArcLogOutputTarget

                $executable = "Azcmagent"
                Write-LogDebug "Executing Collector: $collector_name"
                StartNewProcess -FilePath $executable -ArgumentList  $argument_list  -WindowStyle Hidden -RedirectStandardError $error_file -RedirectStandardOutput $output_file | Out-Null
                
                #in case CTRL+C is pressed
                HandleCtrlC               
            }
            else
            {
                Write-LogInformation "Azcmagent not found. Will not collect $collector_name."
            }
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
} #End of function GetSQLAzureArcLogs
function GetIPandDNSConfig
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str
    $hostname = $global:host_name

    # This lets the SQLLogScout process listen for ctrl+c input and handle CtrlC which in our case will exit out of SQLLogScout after calling the shutdown process
    [console]::TreatControlCAsInput = $true

    try{

        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3
            
        #in case CTRL+C is pressed
        HandleCtrlC

        $collector_name = "IPConfig"
        Write-LogInformation "Executing Collector: $collector_name"
        $str_NexusFriendlyHeader = "-- IPConfig --"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $argument_list = " /all " 
        $executable = "ipconfig"
        Add-Content -Path ($output_file) -Value ($str_NexusFriendlyHeader.ToString())
        StartNewProcess -FilePath $executable -ArgumentList  $argument_list  -WindowStyle Hidden -RedirectStandardError $error_file -RedirectStandardOutput $output_file | Out-Null
        
        #in case CTRL+C is pressed
        HandleCtrlC     
        
        $collector_name = "NetTCPandUDPConnections"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $str_NexusFriendlyHeader = "-- net_tcp_connection --"
        $str_NexusFriendlyHeader | Out-file -FilePath $output_file  -Encoding ascii
        Get-NetTCPConnection | Select-Object Local*, Remote*, State, @{n="ProcessName";e={(Get-Process -Id $_.OwningProcess).ProcessName}}, @{n="ProcessPath";e={(Get-Process -Id $_.OwningProcess).Path}} | Format-Table -Auto | Out-File -Append -FilePath $output_file -Encoding ascii -Width 100000
        
        #in case CTRL+C is pressed
        HandleCtrlC    
        $str_NexusFriendlyHeader = "-- net_udp_endpoint --"
        $str_NexusFriendlyHeader | Out-file -FilePath $output_file  -Encoding ascii -Append        
        Get-NetUDPEndpoint | Select-Object Local*, @{n="ProcessName";e={(Get-Process -Id $_.OwningProcess).ProcessName}}, @{n="ProcessPath";e={(Get-Process -Id $_.OwningProcess).Path}} | Format-Table -Auto | Out-File -Append -FilePath $output_file -Encoding ascii -Width 100000
        
        #in case CTRL+C is pressed
        HandleCtrlC               

        $collector_name = "DNSClientInfo"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $str_NexusFriendlyHeader = "-- dns_client --"
        $str_NexusFriendlyHeader | Out-file -FilePath $output_file  -Encoding ascii
        Get-DnsClient | Select-Object Interface*, Connection*, RegisterThisConnectionsAddress, UseSuffixwhenRegistering | Format-Table -Auto | Out-File -Append -FilePath $output_file -Encoding ascii -Width 100000

        #in case CTRL+C is pressed
        HandleCtrlC  
        $str_NexusFriendlyHeader = "-- dns_client_cache --"
        $str_NexusFriendlyHeader | Out-file -FilePath $output_file  -Encoding ascii -Append
        Get-DnsClientCache | Select-Object Entry, RecordName, RecordType, Status, Section, TimeToLive, DataLength, Data | Format-Table -Auto | Out-File -Append -FilePath $output_file -Encoding ascii -Width 100000

        #in case CTRL+C is pressed
        HandleCtrlC  
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function GetSQLInstanceNameByPortNo($server)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    # If User Passed the SQL Instance Name in the form of Ip Address,Port Number

    $commaPos = $server.IndexOf(",") + 1
    $portno = $server.Substring($commaPos, $server.Length - $commaPos)
    $Result= ""

    [string]$PortString = $portno
    [Int32]$portcheck = $null

    #if no port is present, just use the instance name and return out of here
    if ([Int32]::TryParse($PortString,[ref]$portcheck))
    {
       $Result = @()
    } 
    else 
    {
        $Result = Get-InstanceNameOnly -NetnamePlusInstance $selectInstanceName 
        return $Result;
    }

    #Get all the registry keys where an instance name is present using "MSSQL" and Property like "(default)" to check TCP/IP Sockets
    $InstRegKeys = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' |
                     Where-Object {$_.Name -like '*MSSQL*' -and $_.Property -like "(default)"} |
                      Select-Object PSChildName 


    foreach ($key in $InstRegKeys)
    {
        #first extract the instance name from the reg key (e.g. get the part after the . in "MSSQL14.MYSQL2017")
        $InstanceName = $key.PSChildName.Substring($key.PSChildName.IndexOf(".")+1)

        #build the reg key in the form HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MYSQL2019\MSSQLServer\SuperSocketNetLib\Tcp
        $tcpKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\" + $key.PSChildName + "\MSSQLServer\SuperSocketNetLib\Tcp"
        
        Write-LogDebug "PATH: $tcpKey" -DebugLogLevel 4

        if (Test-Path -Path $tcpKey)
        {
           #check if TCP/IP Sockets is enabled
           $tcpEnabled = Get-ItemProperty -Path $tcpKey | Select-Object -Property Enabled

           #if enabled, go through ports
           if ($tcpEnabled.Enabled -eq "1")
           {

             foreach ($Port in (Get-ItemProperty -Path ($tcpKey+"\IP*") | Select-Object TcpPort, TcpDynamicPorts))
             {
                if ([String]::IsNullOrWhiteSpace($portno) -ne $true)
                {
                    Write-LogDebug "Comparing port=$portno to dynamic=$($Port.TcpDynamicPorts) or static=$($Port.TcpPort)" -DebugLogLevel 4

                    if ( (($Port.TcpDynamicPorts) -eq $portno) -or (($Port.TcpPort) -eq $portno) )
                    {
                        $Result =  $InstanceName
                    }
                    
                }

                else
                {   
                    $Result =  $global:host_name 
                }

             }

           }

           else 
           {
                $Result = Get-InstanceNameOnly -NetnamePlusInstance $selectInstanceName
           }
        }


    }

    Write-LogDebug "The instance name selected after port look-up is $Result" -DebugLogLevel 3

    return $Result
}

function GetSQLErrorLogsDumpsSysHealth()
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "SQLErrorLogs_AgentLogs_SystemHealth_MemDumps_FciXel"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
            $server = $global:sql_instance_conn_str
            $Result = GetSQLInstanceNameByPortNo($server)

            $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
            $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false

            if ($server -notlike '*\*')
            {
                $vInstance = "MSSQLSERVER"
                if ($true -ne [String]::IsNullOrWhiteSpace($Result)) 
                {
                    $vInstance = $Result
                    
                }
            } 
            elseif ($server -like '*\*')
            {
                $vInstance = Get-InstanceNameOnly($server)
                if ($true -ne [String]::IsNullOrWhiteSpace($Result)) 
                {
                    $vInstance = $Result
                }
            }

            [string]$DestinationFolder = $global:output_folder 

            #in case CTRL+C is pressed
            HandleCtrlC
            
            # get XEL files from last three weeks
            $time_threshold = (Get-Date).AddDays(-21)

            $vRegInst = (Get-ItemProperty -Path HKLM:"SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$vInstance
            $vRegPath = "SOFTWARE\Microsoft\Microsoft SQL Server\" + $vRegInst + "\MSSQLServer\Parameters" 
            $vLogPath = (Get-ItemProperty -Path HKLM:$vRegPath).SQLArg1 -replace '-e'
            $vLogPath = $vLogPath -replace 'ERRORLOG'

            Write-LogDebug "The \LOG folder discovered for instance is: $vLogPath" -DebugLogLevel 4

  
            # for ERRORLOG files that are larger than 1 GB copy only head or tail. Otherwise copy the file itself
            Write-LogDebug "Getting ERRORLOG files" -DebugLogLevel 3

            [datetime] $ErrorLogDateLimit = (Get-Date).AddMonths(-2)
            $ErrlogFiles = Get-ChildItem -Path $vLogPath -Filter "ERRORLOG*" | Where-Object {$_.LastWriteTime -ge $ErrorLogDateLimit}
            Write-LogDebug "Capturing all error logs up to 2 months back, starting from '$ErrorLogDateLimit'" -DebugLogLevel 4

            #build a string of servername_instancename, if there is a named instance (\) involved 
            $server_instance = $server -replace "\\", "_"


            foreach ($file in $ErrlogFiles)
            {
               $source = $file.FullName
               $destination = $DestinationFolder + $server_instance + "_" + $file.Name
               $destination_head_tail = $DestinationFolder + $server_instance + "_" + $file.Name + "_Head_and_Tail_Only"
             
               # if file size is > 1 GB, get 500 lines from head and tail of the file
               if ($file.Length -ge 1073741824)
               {
                 Get-Content $source -TotalCount 500 | Set-Content -Path $destination_head_tail | Out-Null
                 Add-Content -Value "`n   <<... middle part of file not captured because the file is too large (>1 GB) ...>>`n" -Path $destination_head_tail | Out-Null
                 Get-Content $source -Tail 500 | Add-Content -Path $destination_head_tail | Out-Null
               }
               elseif ($file.Length -gt 0)
               {
                 Copy-Item -Path $source -Destination  $destination | Out-Null
               }
            }



            #get SQLAgent files
            Write-LogDebug "Getting SQLAGENT files" -DebugLogLevel 3
            Get-ChildItem -Path $vLogPath -Filter "SQLAGENT*" | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null

            #get SystemHealth XEL files
            Write-LogDebug "Getting System_Health*.xel files" -DebugLogLevel 3
            Get-ChildItem -Path $vLogPath -Filter "system_health*.xel" | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null
            

            #get SQL memory dumps
            Write-LogDebug "Getting SQL Dump files" -DebugLogLevel 3

            #first, count how many dump files from the last 2 months
            $DumpFilesTemp = Get-ChildItem -Path "$vLogPath\SQLDump*.mdmp"  | Where-Object {($_.LastWriteTime -gt $ErrorLogDateLimit)}

            Write-LogDebug "Found $($DumpFilesTemp.Count) memory dumps from the past 2 months (since '$ErrorLogDateLimit')" -DebugLogLevel 4

            # now get the memory dumps for last 2 months, of size < 50 MB, and if too many, get only the most recent 20 
            $DumpFiles = Get-ChildItem -Path "$vLogPath\SQLDump*.mdmp" | `
                            Where-Object {($_.LastWriteTime -gt $ErrorLogDateLimit) -and ($_.Length -le 52428800)} | `
                            Sort-Object -Property LastWriteTime -Descending | `
                            Select-Object -First 20

            if ($DumpFiles -ne $null)
            {
                Write-LogDebug "Capturing the most recent $($DumpFiles.Count) memory dumps (max count limit of 20), from the past 2 months, of size < 50 MB " -DebugLogLevel 4
                Write-LogInformation "Gathering '$($DumpFiles.Count)' out of '$($DumpFilesTemp.Count)' memory dumps (max limit of 20) from last 2 months of size < 50 MB"

                Copy-Item -Path $DumpFiles -Destination $DestinationFolder 2>> $error_file | Out-Null

                # Get the  SQLdumper errorlog as well
                Get-ChildItem -Path "$vLogPath\SQLDUMPER_ERRORLOG.log"  | Copy-Item -Path $DumpFiles -Destination $DestinationFolder 2>> $error_file | Out-Null
            }
            else {
                Write-LogDebug "Not capturing any memory dumps. There are $($DumpFiles.Count) memory dumps from last 2 months of size < 50 MB in the '$vLogPath' folder." -DebugLogLevel 4
            }

            #get SQLDIAG XEL files for cluster troubleshooting
            if (IsClustered)
            {
                Write-LogDebug "Getting MSSQLSERVER_SQLDIAG*.xel files" -DebugLogLevel 3
                Get-ChildItem -Path $vLogPath -Filter "*_SQLDIAG*.xel" | Copy-Item -Destination $DestinationFolder 2>> $error_file | Out-Null
            }
        
        } 
        catch 
        {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }
}

function GetPolybaseLogs()
{
    
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $collector_name = "PolybaseLogs"
    Write-LogInformation "Executing Collector: $collector_name"

    try{
            $server = $global:sql_instance_conn_str
            $Result = GetSQLInstanceNameByPortNo($server)

            $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
            Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
            $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false


            if ($server -notlike '*\*')
            {
                $vInstance = "MSSQLSERVER"
                if ($true -ne [String]::IsNullOrWhiteSpace($Result)) 
                {
                    $vInstance = $Result
                }
            } 
            if ($server -like '*\*')
            {
                $vInstance = Get-InstanceNameOnly($server)
                if ($true -ne [String]::IsNullOrWhiteSpace($Result)) 
                {
                    $vInstance = $Result
                } 
            }
            [string]$DestinationFolder = $global:output_folder 

            #in case CTRL+C is pressed
            HandleCtrlC

            $vRegInst = (Get-ItemProperty -Path HKLM:"SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$vInstance
            $vRegPath = "SOFTWARE\Microsoft\Microsoft SQL Server\" + $vRegInst + "\MSSQLServer\Parameters" 
            $vLogPath = (Get-ItemProperty -Path HKLM:$vRegPath).SQLArg1 -replace '-e'
            $vLogPath = $vLogPath -replace 'ERRORLOG'
            # polybase path
            $polybase_path = $vLogPath + '\Polybase\'            
            $ValidPath = Test-Path -Path $polybase_path
            $exclude_ext = @('*.hprof','*.bak')  #exclude file with these extensions when copying.
            If ($ValidPath -ne $False)
            {
                $DestinationFolder_polybase = $DestinationFolder + '\Polybase\'
                Copy-Item $polybase_path $DestinationFolder
                Get-ChildItem $polybase_path -recurse -Exclude $exclude_ext  | where-object {$_.length -lt 1073741824} | Copy-Item -Destination $DestinationFolder_polybase 2>> $error_file | Out-Null
            }

        } 
        catch 
        {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }
}

function GetStorport()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    [console]::TreatControlCAsInput = $true

    $collector_name = "StorPort"
    Write-LogInformation "Executing Collector: $collector_name"
    $server = $global:sql_instance_conn_str

    try
    {
        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)

        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

      
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"

        $executable = "cmd.exe"
        $argument_list = "/C logman create trace  ""storport"" -ow -o $output_file -p ""Microsoft-Windows-StorPort"" 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 4096 -ets"

        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file | Out-Null
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetHighIOPerfStats () 
{

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {

        #in case CTRL+C is pressed
        HandleCtrlC

        #SQL Server High IO Perf Stats
        $collector_name = "High_IO_Perfstats"
        Start-SQLCmdProcess -collector_name $collector_name -input_script_name $collector_name
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return 
    }

}

function GetSQLAssessmentAPI() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try 
    {

        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC


        $collector_name = "SQLAssessmentAPI"
        Write-LogInformation "Executing Collector: $collector_name"
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false

        if (Get-Module -ListAvailable -Name sqlserver)
        {
            if ((Get-Module -ListAvailable -Name sqlserver).exportedCommands.Values | Where-Object name -EQ "Invoke-SqlAssessment")
            {
                Write-LogDebug "Invoke-SqlAssessment() function present" -DebugLogLevel 3
                Get-SqlInstance -ServerInstance $server | Invoke-SqlAssessment -FlattenOutput | Out-File $output_file
            } 
            else 
            {
                Write-LogDebug "Invoke-SqlAssessment() function NOT present. Will not collect $collector_name" -DebugLogLevel 3
            }

        }
        else
        {
                Write-LogInformation "SQLServer PS module not found. Will not collect $collector_name"
        }
    
    }

    catch 
    {
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.Message 
        $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
        $error_offset = $PSItem.InvocationInfo.OffsetInLine
        Write-LogError "Function $mycommand failed with error:  $error_msg (line: $error_linenum, $error_offset)"
        return
    }
}

function GetUserRights () 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    $userRights = @(
        [PSCustomObject]@{Constant="SeTrustedCredManAccessPrivilege"; Description="Access Credential Manager as a trusted caller"}
        ,[PSCustomObject]@{Constant="SeNetworkLogonRight"; Description="Access this computer from the network"}
        ,[PSCustomObject]@{Constant="SeTcbPrivilege"; Description="Act as part of the operating system"}
        ,[PSCustomObject]@{Constant="SeMachineAccountPrivilege"; Description="Add workstations to domain"}
        ,[PSCustomObject]@{Constant="SeIncreaseQuotaPrivilege"; Description="Adjust memory quotas for a process"}
        ,[PSCustomObject]@{Constant="SeInteractiveLogonRight"; Description="Allow log on locally"}
        ,[PSCustomObject]@{Constant="SeRemoteInteractiveLogonRight"; Description="Allow log on through Remote Desktop Services"}
        ,[PSCustomObject]@{Constant="SeBackupPrivilege"; Description="Back up files and directories"}
        ,[PSCustomObject]@{Constant="SeChangeNotifyPrivilege"; Description="Bypass traverse checking"}
        ,[PSCustomObject]@{Constant="SeSystemtimePrivilege"; Description="Change the system time"}
        ,[PSCustomObject]@{Constant="SeTimeZonePrivilege"; Description="Change the time zone"}
        ,[PSCustomObject]@{Constant="SeCreatePagefilePrivilege"; Description="Create a pagefile"}
        ,[PSCustomObject]@{Constant="SeCreateTokenPrivilege"; Description="Create a token object"}
        ,[PSCustomObject]@{Constant="SeCreateGlobalPrivilege"; Description="Create global objects"}
        ,[PSCustomObject]@{Constant="SeCreatePermanentPrivilege"; Description="Create permanent shared objects"}
        ,[PSCustomObject]@{Constant="SeCreateSymbolicLinkPrivilege"; Description="Create symbolic links"}
        ,[PSCustomObject]@{Constant="SeDebugPrivilege"; Description="Debug programs"}
        ,[PSCustomObject]@{Constant="SeDenyNetworkLogonRight"; Description="Deny access to this computer from the network"}
        ,[PSCustomObject]@{Constant="SeDenyBatchLogonRight"; Description="Deny log on as a batch job"}
        ,[PSCustomObject]@{Constant="SeDenyServiceLogonRight"; Description="Deny log on as a service"}
        ,[PSCustomObject]@{Constant="SeDenyInteractiveLogonRight"; Description="Deny log on locally"}
        ,[PSCustomObject]@{Constant="SeDenyRemoteInteractiveLogonRight"; Description="Deny log on through Remote Desktop Services"}
        ,[PSCustomObject]@{Constant="SeEnableDelegationPrivilege"; Description="Enable computer and user accounts to be trusted for delegation"}
        ,[PSCustomObject]@{Constant="SeRemoteShutdownPrivilege"; Description="Force shutdown from a remote system"}
        ,[PSCustomObject]@{Constant="SeAuditPrivilege"; Description="Generate security audits"}
        ,[PSCustomObject]@{Constant="SeImpersonatePrivilege"; Description="Impersonate a client after authentication"}
        ,[PSCustomObject]@{Constant="SeIncreaseWorkingSetPrivilege"; Description="Increase a process working set"}
        ,[PSCustomObject]@{Constant="SeIncreaseBasePriorityPrivilege"; Description="Increase scheduling priority"}
        ,[PSCustomObject]@{Constant="SeLoadDriverPrivilege"; Description="Load and unload device drivers"}
        ,[PSCustomObject]@{Constant="SeLockMemoryPrivilege"; Description="Lock pages in memory"}
        ,[PSCustomObject]@{Constant="SeBatchLogonRight"; Description="Log on as a batch job"}
        ,[PSCustomObject]@{Constant="SeServiceLogonRight"; Description="Log on as a service"}
        ,[PSCustomObject]@{Constant="SeSecurityPrivilege"; Description="Manage auditing and security log"}
        ,[PSCustomObject]@{Constant="SeRelabelPrivilege"; Description="Modify an object label"}
        ,[PSCustomObject]@{Constant="SeSystemEnvironmentPrivilege"; Description="Modify firmware environment values"}
        ,[PSCustomObject]@{Constant="SeDelegateSessionUserImpersonatePrivilege"; Description="Obtain an impersonation token for another user in the same session"}
        ,[PSCustomObject]@{Constant="SeManageVolumePrivilege"; Description="Perform volume maintenance tasks"}
        ,[PSCustomObject]@{Constant="SeProfileSingleProcessPrivilege"; Description="Profile single process"}
        ,[PSCustomObject]@{Constant="SeSystemProfilePrivilege"; Description="Profile system performance"}
        ,[PSCustomObject]@{Constant="SeUndockPrivilege"; Description="Remove computer from docking station"}
        ,[PSCustomObject]@{Constant="SeAssignPrimaryTokenPrivilege"; Description="Replace a process level token"}
        ,[PSCustomObject]@{Constant="SeRestorePrivilege"; Description="Restore files and directories"}
        ,[PSCustomObject]@{Constant="SeShutdownPrivilege"; Description="Shut down the system"}
        ,[PSCustomObject]@{Constant="SeSyncAgentPrivilege"; Description="Synchronize directory service data"}
        ,[PSCustomObject]@{Constant="SeTakeOwnershipPrivilege"; Description="Take ownership of files or other objects"}
        ,[PSCustomObject]@{Constant="SeUnsolicitedInputPrivilege"; Description="Read unsolicited input from a terminal device"}
    )

    try {

        $collectorData = New-Object System.Text.StringBuilder
        [void]$collectorData.AppendLine("Defined User Rights")
        [void]$collectorData.AppendLine("===================")
        [void]$collectorData.AppendLine()

        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #Linked Server configuration
        $collector_name = "UserRights"
        #$input_script = BuildInputScript $global:present_directory $collector_name
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $executable = "$Env:windir\system32\secedit.exe"
        $argument_list = "/export /areas USER_RIGHTS /cfg `"$output_file.tmp`" /quiet"

        Write-LogDebug "The output_file is $output_file" -DebugLogLevel 5
        Write-LogDebug "The error_file is $error_file" -DebugLogLevel 5
        Write-LogDebug "The executable is $executable" -DebugLogLevel 5
        Write-LogDebug "The argument_list is $argument_list" -DebugLogLevel 5

        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath  $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -Wait $true | Out-Null

        #$allRights = (Get-Content -Path "$output_file.tmp" | Select-String '^(Se\S+) = (\S+)')
        $allRights = Get-Content -Path "$output_file.tmp"
        Remove-Item -Path "$output_file.tmp" #delete the temporary file created by SECEDIT.EXE

        foreach($right in $userRights){

            Write-LogDebug "Processing " $right.Constant -DebugLogLevel 5
            
            $line = $allRights | Where-Object {$_.StartsWith($right.Constant)}

            [void]$collectorData.AppendLine($right.Description)
            [void]$collectorData.AppendLine("=" * $right.Description.Length)

            if($null -eq $line){
                
                [void]$collectorData.AppendLine("0 account(s) with the " + $right.Constant + " user right:")
                
            } else {

                $users = $line.Split(" = ")[3].Split(",")
                [void]$collectorData.AppendLine([string]$users.Count + " account(s) with the " + $right.Constant + " user right:")
                
                $resolvedUserNames = New-Object -TypeName System.Collections.ArrayList

                foreach ($user in $users) {
                    
                    if($user[0] -eq "*"){
                        
                        $SID = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList (($user.Substring(1)))

                        try { #some account lookup may fail hence then nested try-catch
                            $account = $SID.Translate([Security.Principal.NTAccount]).Value    
                        } catch {
                            $account = $user.Substring(1) + " <== SID Lookup failed with: " + $_.Exception.InnerException.Message
                        }
                        
                        [void]$resolvedUserNames.Add($account)

                    } else {
                        
                        $NTAccount = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList ($user)

                        try {
                            
                            #try to get SID from account, then translate SID back to account
                            #done to mimic SDP behavior adding hostname to local accounts
                            $SID = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList (($NTAccount.Translate([Security.Principal.SecurityIdentifier]).Value))
                            $account = $SID.Translate([Security.Principal.NTAccount]).Value
                            [void]$resolvedUserNames.Add($account)

                        } catch {

                            #if the above fails we just add user name as fail-safe
                            [void]$resolvedUserNames.Add($user)

                        }

                    }

                }

                [void]$resolvedUserNames.Sort()
                [void]$collectorData.AppendLine($resolvedUserNames -Join "`r`n")
                [void]$collectorData.AppendLine("All accounts enumerated")

            }

            [void]$collectorData.AppendLine()
            [void]$collectorData.AppendLine()

        }

        Add-Content -Path $output_file -Value $collectorData.ToString()
        
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function GetProcmonLog ()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    $server = $global:sql_instance_conn_str

    try 
    {

        

        $collector_name = "ProcessMonitor"
        Write-LogInformation "Executing Collector: $collector_name"

        #discover the directory where ProcessMonitor is installed

        Write-LogInformation "SQL LogScout assumes you have already installed Process Monitor. If not, please download it here -> https://download.sysinternals.com/files/ProcessMonitor.zip "

        while ($true)
        {
            $global:procmon_folder = Read-Host "Please enter the directory where Procmon.exe is available (use no quotes)" -CustomLogMessage "Procmon folder:"
            
            if (Test-Path -Path ($global:procmon_folder+"\Procmon.exe"))
            {
                break
            }
            else
            {
                Write-LogWarning "The directory is invalid or Procmon.exe is not available in it."
            }
        }

        #run Process Monitor

        $partial_output_file_name = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)

        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        #in case CTRL+C is pressed
        HandleCtrlC

      
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true -fileExt ".pml"

        $executable = ($global:procmon_folder + "\Procmon.exe")
        $argument_list = "/accepteula /RingBuffer /RingBufferSize 3096 /quiet /backingfile $output_file"

        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file | Out-Null

        Write-Loginformation "Process Monitor collection started"

        
    }

    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}


function validateUserInput([string[]]$AllInput)
{
    $ExpectedValidInput =  $AllInput[0]
    $ExpectedValidInput = $ExpectedValidInput.split(" ")
    $userinput =  $AllInput[1]
    $HelpMessage = $AllInput[2]

    $ValidId = $false

    while(($ValidId -eq $false) )
    {
        try
        {    
            $userinput = $userinput.ToUpper()
            if ($ExpectedValidInput.Contains($userinput))
            {
                $userinput = [convert]::ToInt32($userinput)
                $ValidId = $true
                $ret = $userinput
                return $ret 
            }
            else
            {
                $userinput = Read-Host "$HelpMessage"
                $userinput = $userinput.ToUpper()
            }
        }

        catch [FormatException]
        {
            try
            {    
                $userinput = [convert]::ToString(($userinput))
                $userinput = $userinput.ToUpper()

                try
                {
                    $userinput =  $userinput.Trim()
                    $ExpectedValidInput =  $AllInput[0] # re-initalyze the vairable as in second attempt it becomes empty
                    If ($userinput.Length -gt 0 -and $userinput -match '[a-zA-Z]' -and $ExpectedValidInput.Contains($userinput))
                    {
                        $userinput = $userinput.ToUpper()
                        $ValidId = $true
                        $ret = $userinput
                        return $ret 
                    }
                    else
                    {
                        $userinput = Read-Host "$HelpMessage"
                        $ValidId = $false
                        continue
                    }
                }
                catch
                {
                    $ValidId = $false
                    continue 
                }
            }

            catch [FormatException]
                {
                    $ValidId = $false
                    continue 
                }
            continue 
        }
    }    
}

function IsCollectingXevents()
{
    Write-LogDebug "inside " $MyInvocation.MyCommand
    
    if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit)) `
    -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit)) `
    -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit)) `
    -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit))
    )
    {
        return $true
    }
    else 
    {
        return $false
    }

}

function DetailedPerfCollectorWarning ()
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    #if we are not running an detailed XEvent collector (scenario 2), exit this function as we don't need to raise warning

    Write-LogWarning "The 'DetailedPerf' scenario collects statement-level and query plan XEvent traces. This may impact SQL Server performance"

    if ($global:gInteractivePrompts -eq "Quiet") 
    {
        Write-LogDebug "Running in 'Quiet' mode assumes you selected 'Y' for user input." -DebugLogLevel 4

        Start-Sleep 5
        return $true
    }
    
    $ValidInput = "Y","N"
    $confirmAccess = Read-Host "Are you sure you would like to Continue?> (y/n)" -CustomLogMessage "Detailed Perf Warning Console input:"
    $HelpMessage = "Please enter a valid input (Y or N)"

    $AllInput = @()
    $AllInput += , $ValidInput
    $AllInput += , $confirmAccess
    $AllInput += , $HelpMessage

    $confirmAccess = validateUserInput($AllInput)

    Write-LogDebug "ConfirmAccess = $confirmAccess" -DebugLogLevel 3

    if ($confirmAccess -eq 'Y')
    { 
        #user chose to proceed
        return $true
    } 
    else 
    { 
        #user chose to abort
        return $false
    }
}

function CheckInternalFolderError ()
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    Write-LogInformation "Checking for errors in collector logs"
    
    $IgnoreError = @(
        "The command completed successfully", `
        "Data Collector Set was not found", `
        "DBCC execution completed. If DBCC printed error messages",`
        "Trace configuration:",`
        "Starting copy..."
        )

    $InternalFolderFiles = Get-ChildItem -Path $global:internal_output_folder -Filter *.out -File 

    foreach ($error_file in $InternalFolderFiles) 
    {
    
        $size = $error_file.Length/1024  
    
        if ($size -gt 0)
        {
            #handle the exclusion strings by ignoring files that contain them
            for ($i=0; $i -lt $IgnoreError.Length; $i++) 
            {
                $StringExist = Select-String -Path $error_file.FullName -pattern $IgnoreError[$i]

                if($StringExist)
                {
                    break  
                }
            }

            if(!$StringExist)
            {
                Write-LogWarning "***************************************************************************************************************"
                Write-LogWarning "A possible failure occurred to collect a log. Please take a look at the contents of file below and resolve the problem before you re-run SQL LogScout"
                Write-LogWarning "File '$($error_file.FullName)' contains the following:"
                Write-LogError (Get-Content -Path  $error_file.FullName)
            }
        } 
    }
}


function Invoke-BasicScenario([bool] $PerfmonOnly = $false)
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:BASIC_NAME' scenario" -ForegroundColor Green

 # this section is intended to start a Perfmon within Basic scenario to gather a few snapshots
 # this function is called 2 times once with PerfmonOnly = true and second time with PerfmonOnly = false

 # this section is intended to start a Perfmon within Basic scenario to gather a few snapshots
 # this function is called 2 times once with PerfmonOnly = true and second time with PerfmonOnly = false

    if ($true -eq $PerfmonOnly)
    {
        Write-LogDebug "Launching Perfmon only within Basic" -DebugLogLevel 2
        GetPerfmonCounters

        #return here as we only want to launch perfmon. The rest will be launched on shutdown
        return
    }
  
    GetTaskList 
    GetFilterDrivers
    GetSysteminfoSummary

    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        GetMiscDiagInfo
        HandleCtrlC
        GetSQLErrorLogsDumpsSysHealth
        Start-Sleep -Seconds 2
        GetPolybaseLogs
        HandleCtrlC
        GetSQLAssessmentAPI
     }
    
    GetUserRights
    GetRunningDrivers

    HandleCtrlC
    Start-Sleep -Seconds 1

    GetPowerPlan
    GetWindowsHotfixes
    GetWindowsDiskInfo
    GetFsutilSectorInfo
    
    HandleCtrlC
    Start-Sleep -Seconds 2
    GetIPandDNSConfig 
    GetEventLogs
    GetSQLAzureArcLogs
} 

function Invoke-GeneralPerfScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:GENERALPERF_NAME' scenario" -ForegroundColor Green
    
    
    GetPerfmonCounters
    
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {

        HandleCtrlC
        #add waits to avoid overwhelming the system with a burts of process launches
        Start-Sleep -Seconds 1
        GetXeventsGeneralPerf
        GetRunningProfilerXeventTraces 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetHighCPUPerfStats
        GetPerfStats 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetPerfStatsSnapshot 
        GetQDSInfo 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetTempdbSpaceLatchingStats 
        GetLinkedServerInfo 
        GetServiceBrokerInfo

        # get basic SQL info if Basic scenario is not collected
        if (IsScenarioEnabled  -scenarioBit $global:NoBasicBit)
        {
            GetMiscDiagInfo
        }
    } 
}

function Invoke-DetailedPerfScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$DETAILEDPERF_NAME' scenario" -ForegroundColor Green

    
    GetPerfmonCounters
    
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        Start-Sleep -Seconds 1
        GetXeventsDetailedPerf
        GetRunningProfilerXeventTraces 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetHighCPUPerfStats 
        GetPerfStats 
        
        HandleCtrlC
        Start-Sleep -Seconds 2
        GetPerfStatsSnapshot 
        GetQDSInfo 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetTempdbSpaceLatchingStats
        GetLinkedServerInfo 
        GetServiceBrokerInfo

        # get basic SQL info if Basic scenario is not collected
        if (IsScenarioEnabled  -scenarioBit $global:NoBasicBit)
        {
            GetMiscDiagInfo
        }
    } 
}

function Invoke-LightPerfScenario ()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:LIGHTPERF_NAME' scenario" -ForegroundColor Green
    
    
    GetPerfmonCounters
    
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {

        HandleCtrlC
        Start-Sleep -Seconds 1
        GetRunningProfilerXeventTraces 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetHighCPUPerfStats
        GetPerfStats 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetPerfStatsSnapshot 
        GetQDSInfo 

        HandleCtrlC
        Start-Sleep -Seconds 2
        GetTempdbSpaceLatchingStats 
        GetLinkedServerInfo 
        GetServiceBrokerInfo

        # get basic SQL info if Basic scenario is not collected
        if (IsScenarioEnabled  -scenarioBit $global:NoBasicBit)
        {
            GetMiscDiagInfo
        }        

    } 
}
function Invoke-AlwaysOnScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:ALWAYSON_NAME' scenario" -ForegroundColor Green
    

    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        GetAlwaysOnDiag
        GetXeventsAlwaysOnMovement
        GetPerfmonCounters
        GetAlwaysOnHealthXel
        GetAGTopologyXml

        # get basic SQL info if Basic scenario is not collected
        if (IsScenarioEnabled  -scenarioBit $global:NoBasicBit)
        {
            GetMiscDiagInfo
        }


    }
}

function Invoke-ReplicationScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:REPLICATION_NAME' scenario" -ForegroundColor Green
        
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        Start-Sleep -Seconds 2
        GetChangeDataCaptureInfo
        GetChangeTracking
    }
}

function Invoke-DumpMemoryScenario
{  
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:DUMPMEMORY_NAME' scenario" -ForegroundColor Green

    #invoke memory dump facility
    GetMemoryDumps

}


function Invoke-NetworkScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:NETWORKTRACE_NAME' scenario" -ForegroundColor Green

    GetNetworkTrace 

}





function Invoke-WPRScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:WPR_NAME' scenario" -ForegroundColor Green

    Write-LogWarning "WPR is a resource-intensive data collection process! Use under Microsoft guidance."
    
    $ValidInput = "Y","N"
    $WPR_YesNo = Read-Host "Do you want to proceed - Yes ('Y') or No ('N') >" -CustomLogMessage "WPR_YesNo Console input:"
    $HelpMessage = "Please enter a valid input (Y or N)"

    $AllInput = @()
    $AllInput += , $ValidInput
    $AllInput += , $WPR_YesNo
    $AllInput += , $HelpMessage
  
    $WPR_YesNo = validateUserInput($AllInput)
    $WPR_YesNo = $WPR_YesNo.ToUpper()

    if ($WPR_YesNo -eq "N") 
    {
        Write-LogInformation "You aborted the WPR data collection process"
        exit
    }
        
    #invoke the functionality
    GetWPRTrace 
}

function Invoke-MemoryScenario 
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:MEMORY_NAME' scenario" -ForegroundColor Green


    
    if ($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME)
    {
        Write-LogWarning "No SQL Server instance specified, thus skipping execution of SQL Server-based collectors"
    }
    else 
    {
        HandleCtrlC
        Start-Sleep -Seconds 2
        GetMemoryLogs 
        GetPerfmonCounters

        # get basic SQL info if Basic scenario is not collected
        if (IsScenarioEnabled  -scenarioBit $global:NoBasicBit)
        {
            GetMiscDiagInfo
        }
    }
}

function Invoke-SetupScenario 
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:SETUP_NAME' scenario" -ForegroundColor Green
    
    HandleCtrlC
    GetSQLSetupLogs
    GetInstallerRegistryKeys
}

function Invoke-BackupRestoreScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    Write-LogInformation "Collecting logs for '$global:BACKUPRESTORE_NAME' scenario" -ForegroundColor Green

    GetXeventBackupRestore

    HandleCtrlC
    
    GetBackupRestoreTraceFlagOutput

    # adding Perfmon counter collection to this scenario
    GetPerfmonCounters

    HandleCtrlC

    #GetSQLVSSWriterLog is called on shutdown
    SetVerboseSQLVSSWriterLog
    GetVSSAdminLogs

    # get basic SQL info if Basic scenario is not collected
    if (IsScenarioEnabled  -scenarioBit $global:NoBasicBit)
    {
        GetMiscDiagInfo
    }
}


function Invoke-IOScenario()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        Write-LogInformation "Collecting logs for '$global:IO_NAME' scenario" -ForegroundColor Green

        GetStorport
        GetHighIOPerfStats
        HandleCtrlC
        
        # adding Perfmon counter collection to this scenario
        GetPerfmonCounters

        HandleCtrlC

        # get basic SQL info if Basic scenario is not collected
        if (IsScenarioEnabled  -scenarioBit $global:NoBasicBit)
        {
            GetMiscDiagInfo
        }

     
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}

function Invoke-ProcmonScenario ()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        Write-LogInformation "Collecting logs for '$global:PROCMON_NAME' scenario" -ForegroundColor Green
        HandleCtrlC

        GetProcmonLog
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}



function Invoke-OnShutDown()
{
    [console]::TreatControlCAsInput = $true
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        
        if (IsScenarioEnabled -scenarioBit $global:setupBit -logged $true)
        {
            Invoke-SetupScenario
        }

        # collect Basic collectors on shutdown
        if (IsScenarioEnabled -scenarioBit $global:basicBit -logged $true)
        {
            Invoke-BasicScenario 
        }

        HandleCtrlC

        # PerfstatsSnapshot needs to be collected on shutdown so people can perform comparative analysis
        
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit -logged $true)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit -logged $true)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit -logged $true)) 
        )
        {
            GetPerfStatsSnapshot -TimeOfCapture "Shutdown"
            GetTopNQueryPlansInXml -PlanCount 10 -TimeOfCapture "Shutdown"
        }

        HandleCtrlC

        # CDC and CT needs to be collected on shutdown so people can perform comparative analysis
        if (IsScenarioEnabled -scenarioBit $global:replBit -logged $true)
        {
            GetChangeDataCaptureInfo -TimeOfCapture "Shutdown"
            GetChangeTracking -TimeOfCapture "Shutdown"
            GetReplMetadata -TimeOfCapture "Shutdown"
        }

        #Set back the setting of  SqlWriterConfig.ini file 
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit) -or ($true -eq (IsScenarioEnabled -scenarioBit $global:basicBit)) )
        {
            GetSQLVSSWriterLog
        }

        if (IsScenarioEnabled -scenarioBit $global:alwaysonBit -logged $true)
        {
            if (IsClustered)
            {
                GetClusterInformation
            } 
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function StartStopTimeForDiagnostics ([string] $timeParam, [string] $startOrStop="")
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try
    {
        if ( ($timeParam -eq "0000") -or ($true -eq [String]::IsNullOrWhiteSpace($timeParam)) )
        {
            Write-LogDebug "No start/end time specified for diagnostics" -DebugLogLevel 2
            return
        }
        
        $datetime = $timeParam #format "2020-10-27 19:26:00"
        
        $formatted_date_time = [DateTime]::Parse($datetime, [cultureinfo]::InvariantCulture);
        
        Write-LogDebug "The formatted time is: $formatted_date_time" -DebugLogLevel 3
        Write-LogDebug ("The current time is:" + (Get-Date) ) -DebugLogLevel 3
    
        #wait until time is reached
        if ($formatted_date_time -gt (Get-Date))
        {
            Write-LogWarning "Waiting until the specified $startOrStop time '$timeParam' is reached...(CTRL+C to stop - wait for response)"
        }
        else
        {
            Write-LogInformation "The specified $startOrStop time '$timeParam' is in the past. Continuing execution."     
        }
        

        [int] $increment = 0
        [int] $sleepInterval = 2

        while ((Get-Date) -lt (Get-Date $formatted_date_time)) 
        {
            Start-Sleep -Seconds $sleepInterval

            if ($Host.UI.RawUI.KeyAvailable -and (3 -eq [int]$Host.UI.RawUI.ReadKey("AllowCtrlC,IncludeKeyUp,IncludeKeyDown,NoEcho").Character))
            {
               Write-LogWarning "*******************"
               Write-LogWarning "You pressed CTRL-C. Stopped waiting..."
               Write-LogWarning "*******************"
               break
            }

            $increment += $sleepInterval
            
            if ($increment % 120 -eq 0)
            {
                $startDate = (Get-Date)
                $endDate =(Get-Date $formatted_date_time)
                $delta = [Math]::Round((New-TimeSpan -Start $startDate -End $endDate).TotalMinutes, 2)
                Write-LogWarning "Collection will $startOrStop in $delta minutes ($startOrStop time was set to: $timeParam)"
            }
        }


    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}

function ArbitrateSelectedScenarios ([bool] $Skip = $false)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    if ($true -eq $Skip)
    {
        return
    }

    #set up Basic bit to ON for several scenarios, unless NoBasic bit is enabled
    if ($false -eq (IsScenarioEnabled -scenarioBit $global:NoBasicBit))
    {
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:replBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:memoryBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:setupBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:IOBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit)) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit))
        )
        {
            EnableScenario -pScenarioBit $global:basicBit
        }
        
        
    }
    else #NoBasic is enabled
    {
        #if both NoBasic and Basic are enabled, assume Basic is intended
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:BasicBit ))
        {
            Write-LogInformation "'$global:BASIC_NAME' and '$global:NOBASIC_NAME' were selected. We assume you meant to collect data - enabling '$global:BASIC_NAME'."
            EnableScenario -pScenarioBit $global:basicBit
        }
        else #Collect scenario without basic logs
        {
            Write-LogInformation "'$global:BASIC_NAME' scenario is disabled due to '$global:NOBASIC_NAME' parameter value specified "    
        }   
        
    }
    
    #if generalperf and detailedperf are both enabled , disable general perf and keep detailed (which is a superset)
    if (($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
    -and ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit  )) )
    {
        DisableScenario -pScenarioBit $global:generalperfBit
        Write-LogWarning "Disabling '$global:GENERALPERF_NAME' scenario since '$global:DETAILEDPERF_NAME' is already enabled"
    }

    #if lightperf and detailedperf are both enabled , disable general perf and keep detailed (which is a superset)
    if (
        ($true -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit )) `
        -and ( ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit ) )  -or ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit ) ))
    )
    {
        DisableScenario -pScenarioBit $global:LightPerfBit
        Write-LogWarning "Disabling '$global:LIGHTPERF_NAME' scenario since '$global:DETAILEDPERF_NAME' or '$global:GENERALPERF_NAME' is already enabled"
    }


    #limit WPR to run only with Basic
    if ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit )) 
    {
        #check if Basic is enabled
        $basic_enabled = IsScenarioEnabled -scenarioBit $global:basicBit

        #reset scenario bit to 0 to turn off all collection
        Write-LogWarning "The '$global:WPR_NAME' scenario is only allowed to run together with Basic scenario. All other scenarios will be disabled" 
        DisableAllScenarios
        Start-Sleep 5
        
        #enable WPR
        EnableScenario -pScenarioBit $global:wprBit
        
        #if Basic was enabled earlier, turn it back on after all was reset
        if ($true -eq $basic_enabled)
        {
            EnableScenario -pScenarioBit $global:basicBit
        }
        return
    }

}

function Select-Scenario()
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

  try
  {

        Write-LogInformation ""
        Write-LogInformation "Initiating diagnostics collection... " -ForegroundColor Green
        
        #[string[]]$ScenarioArray = "Basic (no performance data)","General Performance (recommended for most cases)","Detailed Performance (statement level and query plans)","Replication","AlwaysON", "Network Trace","Memory", "Generate Memory dumps","Windows Performance Recorder (WPR)", "Setup", "Backup and Restore","IO"
        $scenarioIntRange = 0..($global:ScenarioArray.Length -1)  #dynamically count the values in array and create a range
         if($global:gui_Result)
         {
            EnableScenarioFromGUI
         }
        #split the $Scenario string to array elements. If gScenario is empty, then we are fine, this will still work.
        $ScenarioArrayLocal = $global:gScenario.Split('+')

        $scenIntArray =@{}

        #If Scenario array contains only "MenuChoice" or only "NoBasic" or array is empty (no parameters passed), or MenuChoice+NoBasic is passed, then show Menu
        if ( (($ScenarioArrayLocal -contains "MenuChoice") -and ($ScenarioArrayLocal.Count -eq 1 ) ) `
            -or ( $ScenarioArrayLocal -contains [String]::Empty  -and @($ScenarioArrayLocal).count -lt 2   ) `
            -or ($ScenarioArrayLocal -contains "NoBasic" -and $ScenarioArrayLocal.Count -eq 1) `
            -or ($ScenarioArrayLocal -contains "NoBasic" -and $ScenarioArrayLocal -contains "MenuChoice" -and $ScenarioArrayLocal.Count -eq 2) 
            )
        {
            Write-LogInformation "Please select one of the following scenarios:"
            Write-LogInformation ""
            Write-LogInformation "ID`t Scenario"
            Write-LogInformation "--`t ---------------"

            for($i=0; $i -lt $global:ScenarioArray.Count;$i++)
            {
                Write-LogInformation $i "`t" $global:ScenarioArray[$i]
            }
            Write-LogInformation "--`t ---------------`n"
            Write-LogInformation "See https://aka.ms/sqllogscout#Scenarios for Scenario details"

            $isInt = $false
            $ScenarioIdInt = 777
            $WantDetailedPerf = $false

            

            
            while(($isInt -eq $false) -or ($ValidId -eq $false) -or ($WantDetailedPerf -eq $false))
            {
                Write-LogInformation ""
                Write-LogWarning "Type one or more Scenario IDs (separated by '+') for which you want to collect diagnostic data. Then press Enter" 

                $ScenIdStr = Read-Host "Scenario ID(s) e.g. 0+3+6>" -CustomLogMessage "Scenario Console input:"
                [string[]]$scenStrArray = $ScenIdStr.Split('+')
                
                Write-LogDebug "You have selected the following scenarios (str): $scenStrArray" -DebugLogLevel 3

                
                
                foreach($int_string in $scenStrArray) 
                {
                    try 
                    {
                        #convert the strings to integers and add to int array
                        $int_number = [int]::parse($int_string)
                        $scenIntArray.Add($int_number, $int_number)

                        $isInt = $true
                        if($int_string -notin ($scenarioIntRange))
                        {
                            $ValidId = $false
                            $scenIntArray.Clear()
                            Write-LogError "The ID entered '",$ScenIdStr,"' is not in the list "
                        }
                        else 
                        {
                            $ValidId = $true    
                        }
                    }
                    catch 
                    {
                        Write-LogError "The value entered for ID '",$int_string,"' is not an integer"
                        $scenIntArray.Clear()
                        $isInt = $false
                    }
                }

                #warn users when they select the Detailed perf scenario about perf impact. No warning if all others
                [int]$detailed_scen_menu_choice = (($global:ScenarioMenuOrdinals.GetEnumerator() | Where-Object {$_.Value -eq $global:ScenarioBitTbl["DetailedPerf"]}).Key)
                
                if ($int_number -eq $detailed_scen_menu_choice) 
                {
                    # if true, proceed, else, disable scenario and try again
                    $WantDetailedPerf = DetailedPerfCollectorWarning
                    if ($false -eq $WantDetailedPerf)
                    {
                        #once user declines, need to clear the selected bit
                        DisableScenario -pScenarioBit $global:detailedperfBit
                        $int_number = $int_number - $detailed_scen_menu_choice
                        $scenIntArray.Remove($detailed_scen_menu_choice)
                        Write-LogWarning "You selected not to proceed with Detailed Perf scenario. Choose a different scenario(s) or press CTRL+C to exit"    
                    }
                }
                else 
                {
                    $WantDetailedPerf = $true    
                }
                
            } #end of WHILE to select scenario

            #if there are selected scenarios, enable them in the bit mask
            if ($scenIntArray.Count -gt 0)
            {
                Write-LogDebug "You have selected the following scenarios (int): $($scenIntArray.Values)" -DebugLogLevel 3
                
                #go through the selected numbers from the menu (which are in an array) and enable the corresponding scenario bit
                foreach ($ScenarioIdInt in $scenIntArray.Keys)
                {
                    #use the hashtable to map a menu number to a scenario bit
                    EnableScenario -pScenarioBit $global:ScenarioMenuOrdinals[$ScenarioIdInt]
                } #end of foreach    
            }
            

        } #end of if for using a Scenario menu

        #handle the command-line parameter case
        else 
        {
            
            Write-LogDebug "Command-line scenarios selected: $Scenario. Parsed: $ScenarioArray" -DebugLogLevel 3

            #parse startup parameter $Scenario for any values
            foreach ($scenario_name_item in $ScenarioArrayLocal) 
            {
                Write-LogDebug "Individual scenario from Scenario param: $scenario_name_item" -DebugLogLevel 5
                $bit = ""
                # convert the name to a scenario bit
                if(![String]::IsNullOrEmpty($scenario_name_item))
                {
                    $bit = ScenarioNameToBit -pScenarioName $scenario_name_item
                    EnableScenario -pScenarioBit $bit
                }
                
                # send a warning for Detailed Perf
                if ($bit -eq $global:detailedperfBit) 
                {
                    # if true, proceed, else, exit
                    if($false -eq (DetailedPerfCollectorWarning))
                    {
                        exit
                    }
                }

                
            }
            
        }

        #resolove /arbitrate any scenario inconsistencies, conflicts, illogical choices
        ArbitrateSelectedScenarios 


        #set additional properties to certain scenarios
        Set-AutomaticStop 
        Set-InstanceIndependentCollection 
        Set-PerfmonScenarioEnabled

        Write-LogDebug "Scenario Bit value = $global:scenario_bitvalue" -DebugLogLevel 2
        Write-LogInformation "The scenarios selected are: '$global:ScenarioChoice'"

        return $true
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }        
}


function Set-AutomaticStop () 
{
    try 
    {
        # this function is invoked when the user does not need to wait for any long-term collectors (like Xevents, Perfmon, Netmon). 
        # Just gather everything and shut down

        Write-LogDebug "Inside" $MyInvocation.MyCommand

        if ((
                ($true -eq (IsScenarioEnabled -scenarioBit $global:basicBit)) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:dumpMemoryBit )) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit )) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:setupBit )) `
            )  -and
            (
                ($false -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:replBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:memoryBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:IOBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:ProcmonBit ))
            ) )
        {
            Write-LogInformation "The selected '$global:ScenarioChoice' collector(s) will stop automatically after logs are gathered" -ForegroundColor Green
            $global:stop_automatically = $true
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    
}

function Set-InstanceIndependentCollection () 
{
    # this function is invoked when the data collected does not target a specific SQL instance (e.g. WPR, Netmon, Setup). 

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
            
        if ((
                ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit )) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit )) `
                -or ($true -eq (IsScenarioEnabled -scenarioBit $global:ProcmonBit ))
                
            )  -and
            (
                ($false -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:memoryBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:basicBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:replBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:dumpMemoryBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:setupBit )) `
                -and ($false -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit )) `
            ) )
        {
            Write-LogInformation "The selected '$global:ScenarioChoice' scenario(s) gather logs independent of a SQL instance"
            $global:instance_independent_collection = $true    
        }

    }
    catch 
    {
        
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
   
}


function Set-PerfmonScenarioEnabled()
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:memoryBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:IOBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:LightPerfBit )) `
        -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BasicBit )) 
        )
        {
            $global:perfmon_scenario_enabled = $true
            Write-LogDebug "Set '`$global:perfmon_scenario_enabled' = $global:perfmon_scenario_enabled"
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    
}



function Start-DiagCollectors ()
{
    [console]::TreatControlCAsInput = $true

    Write-LogDebug "Inside" $MyInvocation.MyCommand

    Write-LogDebug "The ScenarioChoice array contains the following entries: '$global:ScenarioChoice' " -DebugLogLevel 3

    # launch the scenario collectors that are enabled
    # common collectors (basic) will be called on shutdown
    # for  now not calling in a loop because we can control the order and sequence of invoking scenarios
    if (IsScenarioEnabled -scenarioBit $global:basicBit -logged $true)
    {
        #this will only collect Perfmon for a couple of snapshots
        Invoke-BasicScenario -PerfmonOnly $true

        Write-LogInformation "Basic collectors will execute on shutdown"
    }
    if (IsScenarioEnabled -scenarioBit $global:ProcmonBit -logged $true)
    {
        Invoke-ProcmonScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:LightPerfBit -logged $true)
    {
        Invoke-LightPerfScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:generalperfBit -logged $true)
    {
        Invoke-GeneralPerfScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:detailedperfBit -logged $true)
    {
        Invoke-DetailedPerfScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:alwaysonBit -logged $true)
    {
        Invoke-AlwaysOnScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:replBit -logged $true)
    {
        Invoke-ReplicationScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:networktraceBit -logged $true)
    {
        Invoke-NetworkScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:memoryBit -logged $true)
    {
        Invoke-MemoryScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:dumpMemoryBit -logged $true)
    {
        Invoke-DumpMemoryScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:wprBit -logged $true)
    {
        Invoke-WPRScenario
    }
    if (IsScenarioEnabled -scenarioBit $global:setupBit -logged $true)
    {
        Write-LogInformation "Setup collectors will execute on shutdown"
    }
    if (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit -logged $true)
    {
        Invoke-BackupRestoreScenario
    } 
    if (IsScenarioEnabled -scenarioBit $global:IOBit -logged $true)
    {
        Invoke-IOScenario
    }    
    if ($false -eq (IsScenarioEnabled -scenarioBit $global:basicBit))
    {
        Write-LogInformation "Diagnostic collection started." -ForegroundColor Green #DO NOT CHANGE - Message is backward compatible
        Write-LogInformation ""
    }
}

function Stop-DiagCollectors() 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    $ValidStop = $false

    # Wait for stop time to be reached and shutdown at that time. No need for user to type STOP
    # for Basic scenario we don't need to wait for long-term data collection as there are only static logs
    if (($global:gDiagStopTime -ne "0000") -and ($false -eq [String]::IsNullOrWhiteSpace($global:gDiagStopTime)) -and ((IsScenarioEnabledExclusively -scenarioBit $global:BasicBit) -eq $false))
    {
        #likely a timer parameter is set to stop at a specified time
        StartStopTimeForDiagnostics -timeParam $global:gDiagStopTime -startOrStop "stop"

        #bypass the manual "STOP" interactive user command and cause system to stop
        $global:stop_automatically = $true
    }
    try
    {
        # This function will display error messsage to the user if found any in internal folder
        CheckInternalFolderError

        if ($false -eq $global:stop_automatically)
        { #wait for user to type "STOP"
            while ($ValidStop -eq $false) 
            {
                Write-LogInformation "Please type 'STOP' to terminate the diagnostics collection when you finished capturing the issue" -ForegroundColor Green
                $StopStr = Read-Host ">" -CustomLogMessage "StopCollection Console input:"
                    
                #validate this PID is in the list discovered 
                if (($StopStr -eq "STOP") -or ($StopStr -eq "stop") ) 
                {
                    $ValidStop = $true
                    Write-LogInformation "Shutting down the collector" -ForegroundColor Green #DO NOT CHANGE - Message is backward compatible
                    break;
                }
                else 
                {
                    $ValidStop = $false
                }
            }
        }  
        else 
        {
            Write-LogInformation "Shutting down automatically. No user interaction to stop collectors" -ForegroundColor Green

            if ($true -eq (IsScenarioEnabled -scenarioBit $global:BasicBit))
            {
                Write-LogInformation "Waiting 10-15 seconds to capture a few snapshots of Perfmon before shutting down."
                Start-Sleep -Seconds 12
            }
  
            Write-LogInformation "Shutting down the collector"  #DO NOT CHANGE - Message is backward compatible
        }        
        #create an output directory. -Force will not overwrite it, it will reuse the folder
        #$global:present_directory = Convert-Path -Path "."

        $partial_output_file_name = CreatePartialOutputFilename -server $server
        $partial_error_output_file_name = CreatePartialErrorOutputFilename -server $server


        #STOP the XEvent sessions
        if ( (($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit)) )
            ) 
        { 
            #avoid errors if there was not Xevent collector started 
            Stop-Xevent -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }

        if ( $true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit ) ) 
        { 
            #avoid errors if there was not Xevent collector started 
            Stop-AlwaysOn-Xevents -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }

        

        #Disable backup restore trace flag
        if ( $true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit ) ) 
        { 
            Disable-BackupRestoreTraceFlag -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }

        #STOP Perfmon
        if ( ($true -eq (IsScenarioEnabled -scenarioBit $global:generalperfBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:detailedperfBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:memoryBit )) `
            -or ($true -eq (IsScenarioEnabled -scenarioBit $global:alwaysonBit )) `
            )
        {
            Stop-Perfmon -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
           
        }


        Start-Sleep -Seconds 3

        # stop the most verbose and potentially impactful collectors first

        #stop procmon trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:ProcmonBit ))
        {
            #$global:procmon_folder
            Stop-ProcMonTrace -partial_error_output_file_name $partial_error_output_file_name
        }
        
        #stop storport trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:IOBit ))
        {
            Stop-StorPortTrace -partial_error_output_file_name $partial_error_output_file_name
        }
        
        #stop WPR trace - this usually runs by itself so no need to be stopped first
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit ))
        {
            #Logic to check if -skipPdbGen is supported. If it is then pass the parameter.
            [System.Version]$MinVersionForPDB = "10.0.19041.1"
            [System.Version]$CheckWPRVersionReturn = CheckWPRVersion

            if ($CheckWPRVersionReturn -ge [System.Version]$MinVersionForPDB) 
            {
                Write-LogDebug "Using SkipPdbGen to improve performance. Stopping WPR."
                Stop-WPRTrace -partial_error_output_file_name $partial_error_output_file_name " -skipPdbGen"    
            }
            else 
            {
                Write-LogDebug "SkipPdbGen not supported with this version of WPR. Stopping WPR."
                Stop-WPRTrace -partial_error_output_file_name $partial_error_output_file_name
            }
        }
      

        #STOP Network trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit))
        {
            Stop-NetworkTrace -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }



        # collectors which are invoked on shutdown
        Invoke-OnShutDown


        #wait for other work to finish
        Start-Sleep -Seconds 3

        #if an actual instance was used, kill any queries
        if ($global:instance_independent_collection -eq $false)
        {
            #kill active SQLLogScout sessions and send the output file to \internal
            Kill-ActiveLogscoutSessions -partial_output_file_name $partial_output_file_name -partial_error_output_file_name $partial_error_output_file_name
        }
        
        #check network trace status and wait for it to finish shutting down
        if (($null -ne $global:netsh_shut_proc) -and ($global:netsh_shut_proc -is [System.Diagnostics.Process]))
        {
            # check if network trace is still shutting down. wait for it to finish before exiting
            CheckNetTraceStopStatus -Process $global:netsh_shut_proc
        }
        

        Write-LogInformation "Waiting 3 seconds to ensure files are written to and closed by any program including anti-virus..." -ForegroundColor Green
        Start-Sleep -Seconds 3



    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }

}


#***********************************stop collector function start********************************


function Stop-Xevent([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    #avoid errors if there was not Xevent collector started
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    { 
        $collector_name = "Xevents_Stop"
        $alter_event_session_stop = "ALTER EVENT SESSION [$global:xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_session] ON SERVER;" 

        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_stop -has_output_results $false
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return  
    }
}

function Stop-AlwaysOn-Xevents([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    #avoid errors if there was not Xevent collector started 
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "Xevents_Alwayson_Data_Movement_Stop"
        $alter_event_session_ag_stop = "ALTER EVENT SESSION [$global:xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_alwayson_session] ON SERVER;" 
        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $alter_event_session_ag_stop -has_output_results $false
     }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return  
    }
}

function Disable-BackupRestoreTraceFlag([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        Write-LogDebug "Disabling trace flags for Backup/Restore: $Disabled_Trace_Flag " -DebugLogLevel 2

        $collector_name = "Disable_BackupRestore_Trace_Flags"
        $Disabled_Trace_Flag = "DBCC TRACEOFF(3004,3212,3605,-1)" 
        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $Disabled_Trace_Flag -has_output_results $false
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return 
    }
}

function Stop-Perfmon([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "PerfmonStop"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        $argument_list = "/C logman stop logscoutperfmon & logman delete logscoutperfmon"
        $executable = "cmd.exe"
        Write-LogInformation "Executing shutdown command: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden | Out-Null
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}


function Kill-ActiveLogscoutSessions([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "KillActiveLogscoutSessions"
        $query = "declare curSession 
                CURSOR for select 'kill ' + cast( session_id as varchar(max)) from sys.dm_exec_sessions where host_name = 'sqllogscout' and program_name='SQLCMD' and session_id <> @@spid
                open curSession
                declare @sql varchar(max)
                fetch next from curSession into @sql
                while @@FETCH_STATUS = 0
                begin
                    exec (@sql)
                    fetch next from curSession into @sql
                end
                close curSession;
                deallocate curSession;"  

        Start-SQLCmdProcess -collector_name $collector_name -is_query $true -query_text $query -has_output_results $false -wait_sync $true
    }
    catch 
	{
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return  
    }
}

function Stop-NetworkTrace([string]$partial_output_file_name, [string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        #stop logman trace piece. Wait for this to complete before calling netsh
        $collector_name = "NettraceStop_Logman"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        $executable = "logman"
        $argument_list = "stop -n sqllogscoutndiscap -ets"
        Write-LogInformation "Executing shutdown command: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden -Wait $true | Out-Null

        #stop netsh trace - this could potentially be long
        $collector_name = "NettraceStop_Netsh"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        $executable = "netsh"
        $argument_list = "trace stop"
        Write-LogInformation "Executing shutdown command: $collector_name"
        
        #store the process object in a global for quick access later
        $global:netsh_shut_proc = StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function CheckNetTraceStopStatus ([System.Diagnostics.Process] $Process)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try 
    {
        [int]$cntr = 0

        if ($null -ne $Process)
        {
            Write-LogDebug "$($MyInvocation.MyCommand): ProcessID for Network trace Shutdown = $($Process.Id)" -DebugLogLevel 4
            
            while ($false -eq $Process.HasExited) 
            {
                if ($cntr -gt 0) {
                    #Write-LogWarning "Please wait for network trace to stop..."
                    Write-LogWarning "Shutting down network tracing may take a few minutes. Please wait..."
                }
                #wait for 20 sec, then try again
                [void] $Process.WaitForExit(20000)
                $cntr++
            }
        }
    }

    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}


function Stop-WPRTrace([string]$partial_error_output_file_name,[string] $stoppdbgen)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $server = $global:host_name 
        $collector_name = $global:wpr_collector_name+"_Stop"
        #$partial_output_file_name_wpr = CreatePartialOutputFilename -server $server
        $partial_output_file_name_wpr = CreatePartialOutputFilename ($server)
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false
        $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name_wpr -collector_name $collector_name -needExtraQuotes $true -fileExt ".etl"
        $executable = "cmd.exe"
        $argument_list = $argument_list = "/C wpr.exe -stop " + $output_file + $stoppdbgen
        Write-LogInformation "Executing shutdown command: $collector_name"
        Write-LogDebug $executable $argument_list
        
        $p = StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file
        #$p = Start-Process -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardOutput $error_file -PassThru
        $pn = $p.ProcessName
        $sh = $p.SafeHandle
        if($false -eq $p.HasExited)   
        {
            [void]$global:processes.Add($p)
        }

        $cntr = 0 #reset the counter
        while ($false -eq $p.HasExited) 
        {
            [void] $p.WaitForExit(5000)
        
            if ($cntr -gt 0) {
                Write-LogWarning "Please wait for WPR trace to stop..."
            }
            $cntr++
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return  
    }
}

function Stop-StorPortTrace([string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "StorPort_Stop"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        $argument_list = "/C logman stop ""storport"" -ets"
        $executable = "cmd.exe"
        Write-LogInformation "Executing shutdown command: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden | Out-Null
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}


function GetSQLVSSWriterLog([string]$partial_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    if ($global:sql_major_version -lt 15)
    {
        Write-LogDebug "SQL Server major version is $global:sql_major_version. Not collecting SQL VSS log" -DebugLogLevel 4
        return
    }

    try
    {
        
        $collector_name = "GetSQLVSSWriterLog"
        Write-LogInformation "Executing collector: $collector_name"
        
        
        [string]$DestinationFolder = $global:output_folder 

        if ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit))
        {
            # copy the SqlWriterConfig.txt file in 
            $file = 'C:\Program Files\Microsoft SQL Server\90\Shared\SqlWriterLogger.txt'
            Get-ChildItem $file |  Copy-Item -Destination $DestinationFolder | Out-Null


            $file = 'C:\Program Files\Microsoft SQL Server\90\Shared\SqlWriterConfig.ini'
            if (!(Test-Path $file ))  
            {
                Write-LogWarning "$file does not exist"
            }
            else
            {
                (Get-Content $file).Replace("TraceLevel=VERBOSE","TraceLevel=DEFAULT") | Set-Content $file
                (Get-Content $file).Replace("TraceFileSizeMb=10","TraceFileSizeMb=1") | Set-Content $file
            }
            # Bugfixrestart sqlwriter
            if ($global:restart_sqlwriter -in "Y" , "y" , "Yes" , "yes")
            {
                Restart-Service SQLWriter -force
                Write-LogInformation "SQLWriter Service has been restarted"
            }
        }
        # if Basic scenario only, then collect the default SQL 2019+ VSS writer trace
        elseif (($true -eq (IsScenarioEnabled -scenarioBit $global:basicBit)) -and ($false -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit)) )     
        {
            $file = 'C:\Program Files\Microsoft SQL Server\90\Shared\SqlWriterLogger.txt'
            Get-childitem $file |  Copy-Item -Destination $DestinationFolder | Out-Null
        }
        else {
            Write-LogDebug "No SQLWriterLogger.txt will be collected. Not sure why we are here"
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}

function Stop-ProcMonTrace([string]$partial_error_output_file_name)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try
    {
        $collector_name = "ProcMon_Stop"
        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name $collector_name -needExtraQuotes $false 
        
        if (Test-Path -Path ($global:procmon_folder+"\Procmon.exe"))
        {
            $argument_list = "/accepteula /Terminate"
            $executable = ($global:procmon_folder + "\" + "Procmon.exe")
            Write-LogInformation "Executing shutdown command: $collector_name"
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -RedirectStandardError $error_file -WindowStyle Hidden | Out-Null
        }
        else
        {
            Write-LogError "The path to Procmon.exe is empty or invalid. Cannot execute Procmon.exe /Terminate"
        }
        

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return   
    }
}

#**********************************Stop collector function end***********************************


function Invoke-DiagnosticCleanUpAndExit()
{

    Write-LogDebug "inside" $MyInvocation.MyCommand

    try
    {
        Write-LogWarning "Launching cleanup and exit routine... please wait"
        $server = $global:sql_instance_conn_str

        #quick cleanup to ensure no collectors are running. 
        #Kill existing sessions
        #send the output file to \internal
        $query = "
            declare curSession
            CURSOR for select 'kill ' + cast( session_id as varchar(max)) from sys.dm_exec_sessions where host_name = 'sqllogscout' and program_name='SQLCMD' and session_id <> @@spid
            open curSession
            declare @sql varchar(max)
            fetch next from curSession into @sql
            while @@FETCH_STATUS = 0
            begin
                exec (@sql)
                fetch next from curSession into @sql
            end
            close curSession;
            deallocate curSession;
            "  
        if ($server -ne $NO_INSTANCE_NAME)
        {
            $executable = "sqlcmd.exe"
            $argument_list ="-S" + $server +  " -E -Hsqllogscout_cleanup -w8000 -Q`""+ $query + "`" "
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden | Out-Null
                
        }

        
        #STOP the XEvent sessions

        if ($server -ne $NO_INSTANCE_NAME)
        {  
            $alter_event_session_stop = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_session] ON SERVER; END" 
            $executable = "sqlcmd.exe"
            $argument_list = "-S" + $server + " -E -Hsqllogscout_cleanup -w8000 -Q`"" + $alter_event_session_stop + "`""
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden | Out-Null
                

            #avoid errors if there was not Xevent collector started 
            $alter_event_session_ag_stop = "IF HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') = 1 BEGIN ALTER EVENT SESSION [$global:xevent_alwayson_session] ON SERVER STATE = STOP; DROP EVENT SESSION [$global:xevent_alwayson_session] ON SERVER; END" 
            $executable = "sqlcmd.exe"
            $argument_list = "-S" + $server + " -E -Hsqllogscout_stop -w8000 -Q`"" + $alter_event_session_ag_stop + "`""
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden | Out-Null
            
        }

        #STOP Perfmon
        $executable = "cmd.exe"
        $argument_list ="/C logman stop logscoutperfmon & logman delete logscoutperfmon"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden | Out-Null


        #cleanup network trace
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:networktraceBit ))
        {
            # stop logman - wait synchronously for it to finish
            $executable = "logman"
            $argument_list = "stop -n sqllogscoutndiscap -ets"
            StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -Wait $true | Out-Null

            # stop netsh  asynchronously but wait for it to finish in a loop
            $executable = "netsh"
            $argument_list = "trace stop"
            $proc = StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden

            if ($null -ne $proc)
            {
                Write-LogDebug "Clean up network trace, processID = $($proc.Id)" -DebugLogLevel 2
    
                [int]$cntr = 0
    
                while ($false -eq $proc.HasExited) 
                {
                    if ($cntr -gt 0) {
                        Write-LogWarning "Shutting down network tracing may take a few minutes. Please do not close this window ..."
                    }
                    [void] $proc.WaitForExit(10000)
    
                    $cntr++
                }
            }
        }

        #stop the WPR process if running any on the system
        if ($true -eq (IsScenarioEnabled -scenarioBit $global:wprBit ))
        {
            $executable = "cmd.exe"
            $argument_list = $argument_list = "/C wpr.exe -cancel " 
            
            Write-LogDebug $executable $argument_list
            $p = StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden | Out-Null

            if($false -eq $p.HasExited)   
            {
                [void]$global:processes.Add($p)
            }

            [int]$cntr = 0 
            while ($false -eq $p.HasExited) 
            {
                [void] $p.WaitForExit(5000)

                if ($cntr -gt 0)
                {
                    Write-LogWarning "Continuing to wait for WPR trace to cancel..."
                }
                $cntr++
            } 
        } #if wpr enabled


        if ($true -eq (IsScenarioEnabled -scenarioBit $global:ProcmonBit ))
        {

            if (Test-Path -Path ($global:procmon_folder+"\Procmon.exe"))
            {
                $argument_list = "/accepteula /Terminate"
                $executable = ($global:procmon_folder + "\" + "Procmon.exe")
                Write-LogDebug $executable $argument_list
                StartNewProcess -FilePath $executable -ArgumentList $argument_list  -WindowStyle Hidden | Out-Null
            }
            else
            {
                Write-LogError "The path to Procmon.exe is empty or invalid. Cannot execute Procmon.exe /Terminate"
            }

        }

        if (($server -ne $NO_INSTANCE_NAME) -and ($true -eq (IsScenarioEnabled -scenarioBit $global:BackupRestoreBit )) )
        {
            #clean up backup/restore tace flags
            $Disabled_Trace_Flag = "DBCC TRACEOFF(3004,3212,3605,-1)" 
            $argument_list = "-S" + $server + " -E -Hsqllogscout_stop -w8000 -Q`"" + $Disabled_Trace_Flag + "`""
            StartNewProcess -FilePath "sqlcmd.exe" -ArgumentList $argument_list -WindowStyle Hidden | Out-Null
                
        } 

        Write-LogDebug "Checking that all processes terminated..."

        #allowing some time for above processes to clean-up
        Start-Sleep 5

        [string]$processname = [String]::Empty
        [string]$processid = [String]::Empty
        [string]$process_startime = [String]::Empty

        foreach ($p in $global:processes) 
        {
            # get the properties of the processes we stored in the array into string variables so we can show them
            if ($true -ne [String]::IsNullOrWhiteSpace($p.ProcessName) )
            {
                $processname = $p.ProcessName
            }
            else 
            {
                $processname = "NoProcessName"
            }
            if ($null -ne $p.Id )
            {
                $processid = $p.Id.ToString()
            }
            else 
            {
                $processid = "0"
            }
            if ($null -ne $p.StartTime)
            {
                $process_startime = $p.StartTime.ToString('yyyyMMddHHmmssfff')
            }
            else 
            {
                $process_startime = "NoStartTime"
            }

            Write-LogDebug "Process contained in Processes array is '$processname', $processid, $process_startime" -DebugLogLevel 5

            if ($p.HasExited -eq $false) 
            {
                $cur_proc = Get-Process -Id $p.Id

                $cur_proc_id = $cur_proc.Id.ToString()
                $cur_proc_starttime = $cur_proc.StartTime.ToString('yyyyMMddHHmmssfff')
                $cur_proc_name = $cur_proc.ProcessName

                Write-LogDebug "Original process which hasn't exited and is matched by Id is: $cur_proc_id, $cur_proc_name, $cur_proc_starttime" -DebugLogLevel 5

                if (($cur_proc.Id -eq $p.Id) -and ($cur_proc.StartTime -eq $p.StartTime) -and ($cur_proc.ProcessName -eq $p.ProcessName) )
                {
                    Write-LogInformation ("Process ID " + ([string]$p.Id) + " has not exited yet.")
                    Write-LogInformation ("Process CommandLine for Process ID " + ([string]$p.Id) + " is: " + $OSCommandLine)
                    Write-LogDebug ("Process CPU Usage Total / User / Kernel: " + [string]$p.TotalProcessorTime + "     " + [string]$p.UserProcessorTime + "     " + [string]$p.PrivilegedProcessorTime) -DebugLogLevel 3
                    Write-LogDebug ("Process Start Time: " + [string]$p.StartTime) -DebugLogLevel 3
                    Write-LogDebug ("Process CPU Usage %: " + [string](($p.TotalProcessorTime.TotalMilliseconds / ((Get-Date) - $p.StartTime).TotalMilliseconds) * 100)) -DebugLogLevel 3
                    Write-LogDebug ("Process Peak WorkingSet (MB): " + [string]$p.PeakWorkingSet64 / ([Math]::Pow(1024, 2))) -DebugLogLevel 3
                    Write-LogWarning ("Stopping Process ID " + ([string]$p.Id))
                    Stop-Process $p
                }
            }
            else {
                Write-LogDebug "Process '$processname', $processid, $process_startime has exited." -DebugLogLevel 5
            }
        }
    
        Write-LogInformation "Thank you for using SQL LogScout!" -ForegroundColor Green

        #close and remove handles to the log files
        if ($global:debugLogStream)
        {
            $global:debugLogStream.Flush()
            $global:debugLogStream.Close()
            $global:debugLogStream.Dispose()
        }

        if ($global:consoleLogStream)
        {
            $global:consoleLogStream.Flush()
            $global:consoleLogStream.Close()
            $global:consoleLogStream.Dispose()
        }

        if ($global:ltDebugLogStream)
        {
            $global:ltDebugLogStream.Flush()
            $global:ltDebugLogStream.Close()
            $global:ltDebugLogStream.Dispose()
        }
        
        ## Remove all modules from the current session.
        Get-Module | Remove-Module
        
        #Clean up global variables
        Remove-Variable * -ErrorAction SilentlyContinue -Scope "Global"

        exit
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        exit
    }
}



#======================================== END OF Diagnostics Collection SECTION

#======================================== START OF Bitmask Enabling, Diabling and Checking of Scenarios

function ScenarioBitToName ([int] $pScenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        [string] $scenName = [String]::Empty

        #reverse lookup - use Value to lookup Key
        $scenName  = ($ScenarioBitTbl.GetEnumerator() | Where-Object {$_.Value -eq $pScenarioBit}).Key.ToString()
        
        Write-LogDebug "Scenario bit $pScenarioBit translates to $scenName" -DebugLogLevel 5
    
        return $scenName    

    }
    catch 
    {
        
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    
}


function ScenarioNameToBit ([string] $pScenarioName)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    try 
    {
        
        [int] $scenBit = 0

        $scenBit = $ScenarioBitTbl[$pScenarioName]
        
        Write-LogDebug "Scenario name $pScenarioName translates to bit $scenBit" -DebugLogLevel 5
    
        return $scenBit    
        
    }
    catch 
    {
        
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    
}

function EnableScenario([int]$pScenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        
        [string] $scenName = ScenarioBitToName -pScenarioBit $pScenarioBit

        Write-LogDebug "Enabling scenario bit $pScenarioBit, '$scenName' scenario" -DebugLogLevel 3

        #de-duplicate entries
        if (!$global:ScenarioChoice.Contains($scenName))
        {
            #populate the ScenarioChoice array
            [void] $global:ScenarioChoice.Add($scenName)

        }

        $global:scenario_bitvalue = $global:scenario_bitvalue -bor $pScenarioBit
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function DisableScenario([int]$pScenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        Write-LogDebug "Disabling scenario bit $pScenarioBit" -DebugLogLevel 3
    
        [string] $scenName = ScenarioBitToName -pScenarioBit $pScenarioBit
        
        $global:ScenarioChoice.Remove($scenName)
        $global:scenario_bitvalue = $global:scenario_bitvalue -band -bnot([uint32]$pScenarioBit)

        Write-LogDebug "Scenario bit after disabling: $global:scenario_bitvalue" -DebugLogLevel 3
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem    
    }
    
}

function DisableAllScenarios()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        Write-LogDebug "Setting Scenarios bit to 0" -DebugLogLevel 3

        #reset both scenario structures
        $global:ScenarioChoice.Clear()
        $global:scenario_bitvalue = 0    
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem        
    }
    
}

function IsScenarioEnabled([int]$scenarioBit, [bool] $logged = $false)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try
    {
        #perform the check 
        $bm_enabled = $global:scenario_bitvalue -band $scenarioBit

        if ($true -eq $logged)
        {
            [string] $scenName = ScenarioBitToName -pScenarioBit $scenarioBit
            Write-LogDebug "The bitmask result for $scenName scenario = $bm_enabled" -DebugLogLevel 4
        }

        #if enabled, return true, else false
        if ($bm_enabled -gt 0)
        {
            if ($true -eq $logged)
            {
                Write-LogDebug "$scenName scenario is enabled" -DebugLogLevel 2
            }
            
            return $true
        }
        else
        {
            if ($true -eq $logged)
            {
                Write-LogDebug "$scenName scenario is disabled" -DebugLogLevel 2
            }
            return $false
        }    
    }
    
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}

function IsScenarioEnabledExclusively([int]$scenarioBit)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    
    $ret = $false;

    try
    {
        if (IsScenarioEnabled -scenarioBit $scenarioBit)
        {
            #check all bits to see if more than the one bit is enabled. If yes,stop the loop and return (other bits are enabled)

            # scenario name is Key and bit is value
            foreach ($name in $ScenarioBitTbl.Keys)
            {
                $ret = IsScenarioEnabled -scenarioBit $ScenarioBitTbl[$name]

                #if the scenario is not the one we are testing for and its bit is enabled, it is not exclusive, so  bail out
                if (($ret -eq $true) -and ($ScenarioBitTbl[$name] -ne $scenarioBit))
                {
                    return $false
                }

            }

            #if we got here, it must be the only one - so exclusive
            return $true
        }
        else 
        {
            #the bit is not enabled at all
            return $false    
        }

    }
        
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}



#======================================== END OF Bitmask Enabling, Diabling and Checking of Scenarios



#======================================== START OF PERFMON COUNTER FILES SECTION

Import-Module .\PerfmonCounters.psm1

#======================================== END OF PERFMON COUNTER FILES SECTION



function Check-ElevatedAccess
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    try 
    {
        #check for administrator rights
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
        {
            Write-Warning "Elevated privilege (run as Admininstrator) is required to run SQL_LogScout! Exiting..."
            exit
        }
        
    }

    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit_logscout $true
    }
    

}

function Confirm-SQLPermissions
{
<#
    .SYNOPSIS
        Returns true if user has VIEW SERVER STATE permission in SQL Server, otherwise warns about lack of permissions and request confirmation, returns true if user confirms otherwise returns false.

    .DESCRIPTION
        Returns true if user has VIEW SERVER STATE permission in SQL Server, otherwise warns about lack of permissions and request confirmation, returns true if user confirms otherwise returns false.
    
    .EXAMPLE
        Confirm-SQLPermissions -SQLInstance "SERVER"
#>
[CmdletBinding()]
param ( 
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SQLUser,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SQLPwd
    )

    Write-LogDebug "inside " $MyInvocation.MyCommand

    if (($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME) -or ($true -eq $global:instance_independent_collection ) )
    {
        Write-LogWarning "No SQL Server instance found or Instance-independent collection. SQL Permissions-checking is not necessary"
        return $true
    }
    elseif ($global:sql_instance_conn_str -ne "")
    {
        $SQLInstance = $global:sql_instance_conn_str
    }
    else {
        Write-LogError "SQL Server instance name is empty. Exiting..."
        exit
    }
    
    $server = $global:sql_instance_conn_str
    $partial_output_file_name = CreatePartialOutputFilename ($server)
    $XELfilename = $partial_output_file_name + "_" + $global:xevent_target_file + "_test.xel"

    $SQLInstanceUpperCase = $SQLInstance.ToUpper()

    Write-LogDebug "Received parameter SQLInstance: `"$SQLInstance`"" -DebugLogLevel 2
    Write-LogDebug "Received parameter SQLUser: `"$SQLUser`"" -DebugLogLevel 2
    Write-LogDebug "Received parameter SQLPwd (true/false): " (-not ($null -eq $SQLPwd)) #we don't print the password, just inform if we received it or not

    #query bellow does substring of SERVERPROPERTY('ProductVersion') instead of using SERVERPROPERTY('ProductMajorVersion') for backward compatibility with SQL Server 2012 & 2014
    $SqlQuery = "select SUSER_SNAME() login_name, HAS_PERMS_BY_NAME(null, null, 'view server state') has_view_server_state, HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY EVENT SESSION') has_alter_any_event_session, LEFT(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), (CHARINDEX(N'.', CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)))-1)) sql_major_version, CAST(PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)), 2) AS INT) as sql_major_build"
    $ConnString = "Server=$SQLInstance;Database=master;Application Name=SQLLogScout;"

    #if either SQLUser or SQLPwd are null we setup Integrated Authentication
    #otherwise if we received both we setup SQL Authentication
    if ( ($true -eq [String]::IsNullOrWhiteSpace($SQLUser)) -or ($true -eq [String]::IsNullOrWhiteSpace($SQLPwd) ))
    {
        $ConnString += "Integrated Security=True;"
    } else
    {
        $ConnString += "User Id=$SQLUser;Password=$SQLPwd"
    }

    Write-LogDebug "Creating SqlClient objects and setting parameters" -DebugLogLevel 2
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $ConnString
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlQuery
    $SqlCmd.Connection = $SqlConnection
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $SqlAdapter.SelectCommand = $SqlCmd
    $DataSetPermissions = New-Object System.Data.DataSet

    Write-LogDebug "About to call SqlDataAdapter.Fill()" -DebugLogLevel 2
    try {
        $SqlAdapter.Fill($DataSetPermissions) | Out-Null #fill method returns rowcount, Out-Null prevents the number from being printed in console    
    }
    catch {
        Write-LogError "Could not connect to SQL Server instance '$SQLInstance' to validate permissions."
        
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.InnerException.Message 
        Write-LogError "$mycommand Function failed with error:  $error_msg"
        
        # we can't connect to SQL, probably whole capture will fail, so we just abort here
        return $false
    }

    $global:sql_major_version = $DataSetPermissions.Tables[0].Rows[0].sql_major_version
    $global:sql_major_build = $DataSetPermissions.Tables[0].Rows[0].sql_major_build
    $account = $DataSetPermissions.Tables[0].Rows[0].login_name
    $has_view_server_state = $DataSetPermissions.Tables[0].Rows[0].has_view_server_state
    $has_alter_any_event_session = $DataSetPermissions.Tables[0].Rows[0].has_alter_any_event_session

    Write-LogDebug "SQL Major Version: " $global:sql_major_version -DebugLogLevel 3
    Write-LogDebug "SQL Account Name: " $account -DebugLogLevel 3
    Write-LogDebug "Has View Server State: " $has_view_server_state -DebugLogLevel 3
    Write-LogDebug "Has Alter Any Event Session: " $has_alter_any_event_session -DebugLogLevel 3
    Write-LogDebug "SQL Major Build: " $global:sql_major_build -DebugLogLevel 3

    $collectingXEvents = IsCollectingXevents

    # if the account doesn't have ALTER ANY EVENT SESSION, we don't bother testing XEvent
    if((1 -eq $has_alter_any_event_session) -and ($collectingXEvents))
    {
        Write-LogDebug "Account has ALTER ANY EVENT SESSION. Check that we can start an Event Session."
        
        # temp sproc that tests creating an XEvent session
        # returns 1 for success
        # returns zero for failure
        $SqlQuery = "CREATE PROCEDURE #TestXEvents
                    AS
                    BEGIN
                    BEGIN TRY
                        
                        -- CHECK AND DROP IF THE TEST EVENT SESSION EXISTS BEFORE PROCEEDING
                        IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = 'xevent_SQLLogScout_Test')
                        BEGIN
                            DROP EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER
                        END

                        -- CREATE AND START THE TEST EVENT SESSION
                        CREATE EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER  ADD EVENT sqlserver.existing_connection
                        ADD TARGET package0.event_file(SET filename=N'$XELfilename', max_file_size=(500), max_rollover_files=(50))
                        WITH (MAX_MEMORY=200800 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=10 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_CPU,TRACK_CAUSALITY=OFF,STARTUP_STATE=OFF)
                        ALTER EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER STATE = START

                        -- IF WE SUCCEEDED THEN JUST REMOVE THE TEST EVENT SESSION
                        IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = 'xevent_SQLLogScout_Test')
                        BEGIN
                            DROP EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER
                        END

                        -- RETURN 1 TO INDICATE SUCCESS 
                        RETURN 1

                    END TRY
                    BEGIN CATCH

                        -- IF THERE'S A DOOMED TRANSACTION WE ROLLBACK
                        IF XACT_STATE() = -1 ROLLBACK TRANSACTION

                        SELECT  
                            ERROR_NUMBER() AS ErrorNumber  
                            ,ERROR_SEVERITY() AS ErrorSeverity  
                            ,ERROR_STATE() AS ErrorState  
                            ,ERROR_PROCEDURE() AS ErrorProcedure  
                            ,ERROR_LINE() AS ErrorLine  
                            ,ERROR_MESSAGE() AS ErrorMessage;  
                        
                        -- CHECK FOR XE SESSIO AND CLEANUP
                        IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = 'xevent_SQLLogScout_Test')
                        BEGIN
                            DROP EVENT SESSION [xevent_SQLLogScout_Test] ON SERVER
                        END

                        -- RETURN ZERO TO INDICATE FAILURE
                        RETURN 0

                    END CATCH
                    END"
        
        Write-LogDebug "Creating Sproc #TestXEvents" -DebugLogLevel 2
        
        if ("Open" -ne $SqlConnection.State){
            $SqlConnection.Open() | Out-Null
        }

        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.CommandText = $SqlQuery
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.ExecuteNonQuery() | Out-Null

        Write-LogDebug "Calling Sproc #TestXEvents" -DebugLogLevel 2
        $SqlRetValue = New-Object System.Data.SqlClient.SqlParameter
        $SqlRetValue.DbType = [System.Data.DbType]::Int32
        $SqlRetValue.Direction = [System.Data.ParameterDirection]::ReturnValue

        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
        $SqlCmd.CommandText = "#TestXEvents"
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.Parameters.Add($SqlRetValue) | Out-Null 
        
        $SqlReader = $SqlCmd.ExecuteReader([System.Data.CommandBehavior]::SingleRow.ToInt32([CultureInfo]::InvariantCulture) + [System.Data.CommandBehavior]::SingleResult.ToInt32([CultureInfo]::InvariantCulture))

        # XE Test Successful
        if (1 -eq $SqlRetValue.Value)
        {    
            Write-LogDebug "Extended Event Session test SUCCESSFUL" -DebugLogLevel 2
            [bool]$XETestSuccessfull = $true
        }
        else
        {    
            Write-LogDebug "Extended Event Session test FAILURE" -DebugLogLevel 2
            [bool]$XETestSuccessfull = $false
            
            $SqlReader.Read() | Out-Null # we expect a single line so no need to Read() in a loop
            $SqlErrorNumber = $SqlReader.GetInt32($SqlReader.GetOrdinal("ErrorNumber"))
            $SqlErrorSeverity = $SqlReader.GetInt32($SqlReader.GetOrdinal("ErrorSeverity"))
            $SqlErrorState = $SqlReader.GetInt32($SqlReader.GetOrdinal("ErrorState"))
            $SqlErrorProcedure = $SqlReader.GetString($SqlReader.GetOrdinal("ErrorProcedure"))
            $SqlErrorLine = $SqlReader.GetInt32($SqlReader.GetOrdinal("ErrorLine"))
            $SqlErrorMessage = $SqlReader.GetString($SqlReader.GetOrdinal("ErrorMessage"))

            Write-LogDebug "Msg $SqlErrorNumber, Level $SqlErrorSeverity, State $SqlErrorState, Procedure $SqlErrorProcedure, Line $SqlErrorLine" -DebugLogLevel 3
            Write-LogDebug "Message: $SqlErrorMessage" -DebugLogLevel 3
        }

        Write-LogDebug "Closing SqlConnection" -DebugLogLevel 2
        $SqlConnection.Close() | Out-Null

        Write-LogDebug "Cleanup any XEL files remaining from test" -DebugLogLevel 2
        Remove-Item ($XELfilename.Replace("_test.xel", "_test*.xel")) | Out-Null

    } # if(1 -eq $has_alter_any_event_session)
    
    if ((1 -eq $has_view_server_state) -and (1 -eq $has_alter_any_event_session) -and ($XETestSuccessfull -or (-not($collectingXEvents))))
    {
        Write-LogInformation "Confirmed that $account has VIEW SERVER STATE on SQL Server Instance '$SQLInstanceUpperCase'"
        Write-LogInformation "Confirmed that $account has ALTER ANY EVENT SESSION on SQL Server Instance '$SQLInstanceUpperCase'"
        
        if (($collectingXEvents) -and ($XETestSuccessfull)) {
            Write-LogInformation "Confirmed that SQL Server Instance $SQLInstance can write Extended Event Session Target at $XELfilename"
        }
        
        # user has view server state and alter any event session
        # SQL can write extended event session
        return $true
    } else {

        # server principal does not have VIEW SERVER STATE or does not have ALTER ANY EVENT SESSION
        if ((1 -ne $DataSetPermissions.Tables[0].Rows[0].has_view_server_state) -or (1 -ne $DataSetPermissions.Tables[0].Rows[0].has_alter_any_event_session)) {
            Write-LogDebug "either has_view_server_state or has_alter_any_event_session returned different than one, user does not have view server state" -DebugLogLevel 2

            Write-LogWarning "User account $account does not posses the required privileges in SQL Server instance '$SQLInstanceUpperCase'"
            Write-LogWarning "Proceeding with capture will result in SQLDiag not producing the necessary information."
            Write-LogWarning "To grant minimum privilege for a successful data capture, connect to SQL Server instance '$SQLInstanceUpperCase' using administrative account and execute the following:"
            Write-LogWarning ""

            if (1 -ne $DataSetPermissions.Tables[0].Rows[0].has_view_server_state) {
                Write-LogWarning "GRANT VIEW SERVER STATE TO [$account]"
            }

            if (1 -ne $DataSetPermissions.Tables[0].Rows[0].has_alter_any_event_session) {
                Write-LogWarning "GRANT ALTER ANY EVENT SESSION TO [$account]"
            } 
            
            Write-LogWarning ""
        }

        # server principal has ALTER ANY EVENT SESSION permission
        # but creating the extended event session still failed
        if ((0 -ne $DataSetPermissions.Tables[0].Rows[0].has_alter_any_event_session) -and (-not($XETestSuccessfull))) {
            # account has ALTER ANY EVENT SESSION yet we could not start extended event session
            Write-LogError "Extended Event log collection test failed for SQL Server '$SQLInstanceUpperCase'"
            Write-LogError "SQL Server Error: $SqlErrorMessage"


            $host_name = $global:host_name
            $instance_name = Get-InstanceNameOnly ($global:sql_instance_conn_str)
            
            if ($instance_name -ne $host_name)
            {
                $sqlservicename = "MSSQL"+"$"+$instance_name
            }
            else
            {
                $sqlservicename = "MSSQLServer"
            }
            
            $startup_account = (Get-wmiobject win32_service -Filter "name='$sqlservicename' " | Select-Object  startname).StartName

            if ($SqlErrorNumber -in 25602 ){
                Write-LogWarning "As a first step, ensure that service account [$startup_account] for SQL instance '$SQLInstanceUpperCase' has write permissions on the output folder."
            }
        }

        Write-LogWarning ""

        [string]$confirm = $null
        while (-not(($confirm -eq "Y") -or ($confirm -eq "N") -or ($null -eq $confirm)))
        {
            Write-LogWarning "Would you like to continue with limited log collection? (Y/N)"
            $confirm = Read-Host "Continue?>" -CustomLogMessage "SQL Permission Console input:"

            $confirm = $confirm.ToString().ToUpper()
            if (-not(($confirm -eq "Y") -or ($confirm -eq "N") -or ($null -eq $confirm)))
            {
                Write-LogError ""
                Write-LogError "Please chose [Y] to proceed capture with limited log collection."
                Write-LogError "Please chose [N] to abort capture."
                Write-LogError ""
            }
        }

        if ($confirm -eq "Y"){ #user chose to continue
            return $true
        } else { #user chose to abort
            return $false
        }
    }

}

function Enable-ReadIntentFlagForSecondary
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    if (($global:sql_instance_conn_str -eq $NO_INSTANCE_NAME) -or ($true -eq $global:instance_independent_collection ) -or [String]::IsNullOrWhiteSpace($global:sql_instance_conn_str) )
    {
        Write-LogDebug "No SQL Server instance found or Instance-independent collection. No need to check set -KReadOnly intent flag" -DebugLogLevel 2
        return $false
    }
    else 
    {
        $SQLInstance = $global:sql_instance_conn_str
    }

    #query this gets a count of secondary replicas that are configured as read intent-only on this server
    $SqlQuery = "SELECT count(*) AS IsSecondaryWithReadIntentOnly FROM sys.dm_hadr_availability_replica_states ars INNER JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id AND ars.group_id = ar.group_id WHERE role_desc = 'SECONDARY' and secondary_role_allow_connections_desc = 'READ_ONLY' AND is_local = 1"
    $ConnString = "Server=$SQLInstance;Database=master;Integrated Security=True;Application Name=SQLLogScout;"


    Write-LogDebug "Creating SqlClient objects and setting parameters for Read-intent check" -DebugLogLevel 2
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $ConnString
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlQuery
    $SqlCmd.Connection = $SqlConnection
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $SqlAdapter.SelectCommand = $SqlCmd
    $DataSetAG = New-Object System.Data.DataSet

    Write-LogDebug "About to call SqlDataAdapter.Fill() read-intent check" -DebugLogLevel 2
    try {
        $SqlAdapter.Fill($DataSetAG) | Out-Null #fill method returns rowcount, Out-Null prevents the number from being printed in console    
    }
    catch {
        Write-LogError "Could not connect to SQL Server instance '$SQLInstance' to validate permissions."
        
        $mycommand = $MyInvocation.MyCommand
        $error_msg = $PSItem.Exception.InnerException.Message 
        Write-LogError "$mycommand Function failed with error:  $error_msg"
        
        # we can't connect to SQL, probably whole capture will fail, so we just abort here
        return $false
    }


    #get the value from the table (should be 0 or greater)
    $IsSecondaryWithReadIntentOnly = $DataSetAG.Tables[0].Rows[0].IsSecondaryWithReadIntentOnly
    

    if ($IsSecondaryWithReadIntentOnly -gt 0) 
    {
        $global:is_secondary_read_intent_only = $true
        Write-LogDebug "There is a 'Read-Intent Only' Secondary Replica in this SQL Server" -DebugLogLevel 2
    }
    else 
    {
        $global:is_secondary_read_intent_only = $false
        Write-LogDebug "No 'Read-Intent Only' Secondary Replicas found" -DebugLogLevel 2
    }
}

function HandleCtrlC ()
{
    if ($Host.UI.RawUI.KeyAvailable -and (3 -eq [int]$Host.UI.RawUI.ReadKey("AllowCtrlC,IncludeKeyUp,IncludeKeyDown,NoEcho").Character))
    {
       Write-LogWarning "*******************"
       Write-LogWarning "You pressed CTRL-C. Stopping diagnostic collection..."
       Write-LogWarning "*******************"
       Invoke-DiagnosticCleanUpAndExit
       break
    }

    #if no CTRL+C just return and move on
    return
    
}

function HandleCtrlCFinal ()
{
    while ($true)
    {

        if ($Host.UI.RawUI.KeyAvailable -and (3 -eq [int]$Host.UI.RawUI.ReadKey("AllowCtrlC,IncludeKeyUp,IncludeKeyDown,NoEcho").Character))
        {
            Write-LogWarning "<*******************>"
            Write-LogWarning "You pressed CTRL-C. Stopping diagnostic collection..."
            Write-LogWarning "<*******************>"
            Invoke-DiagnosticCleanUpAndExit
        }
		
		else
		{
			Invoke-DiagnosticCleanUpAndExit
			break;
		}
    }
}



function GetPerformanceDataAndLogs 
{
   try 
   {
        Write-LogDebug "inside" $MyInvocation.MyCommand
        
        [console]::TreatControlCAsInput = $true
        
        [bool] $Continue = $false


        # warn users about running in quiet mode
        if ($global:gInteractivePrompts -eq "Quiet") 
        {
            Write-LogWarning "Selecting the 'Quiet' option assumes you pressed 'Y' for all user input prompts"
            Start-Sleep -Seconds 5
        }


        #prompt for diagnostic scenario
        
        $Continue = Select-Scenario
        if ($false -eq $Continue)
        {
            Write-LogInformation "No diagnostic logs will be collected because no scenario is selected. Exiting..."
            return
        }


        

        #pick a sql instnace
        Select-SQLServerForDiagnostics

        #check SQL permission and continue only if user has permissions or user confirms to continue without permissions
        $Continue = Confirm-SQLPermissions 
        if ($false -eq $Continue)
        {
            Write-LogInformation "No diagnostic logs will be collected due to insufficient SQL permissions or inability to connect to instance. Exiting..."
            return
        }

        #for AG secondary enable -KReadOnly so we can collect data from read-intent only secondary
        Enable-ReadIntentFlagForSecondary


        if ($global:gui_mode) 
        {
            GenerateXeventFileFromGUI                   
        }
        
        #prepare a pefmon counters file with specific instance info
        PrepareCountersFile

        #check if a timer parameter set is passed and sleep until specified time
        StartStopTimeForDiagnostics -timeParam $global:gDiagStartTime -startOrStop "start" 

        #start collecting data
        Start-DiagCollectors
        
        #stop data collection
        Stop-DiagCollectors
        
   }
   catch 
   {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem

        $call_stack = $PSItem.Exception.InnerException 
        Write-LogError "Function '$mycommand' :  $call_stack"
   }
   
}


function Start-SQLLogScout 
{
    Write-LogDebug "inside " $MyInvocation.MyCommand
    Write-LogDebug "Scenario prameter passed is '$global:gScenario'" -DebugLogLevel 3

    try 
    {  
        InitAppVersion
    
        #check for administrator rights
        Check-ElevatedAccess
    
        #initialize globals for present folder, output folder, internal\error folder
        InitCriticalDirectories

        #check if output folder is already present and if so prompt for deletion. Then create new if deleted, or reuse
        ReuseOrRecreateOutputFolder
    
        #create a log of events
        Initialize-Log -LogFilePath $global:internal_output_folder -LogFileName "##SQLLOGSCOUT.LOG"
        
        #check file attributes against expected attributes
        $validFileAttributes = Confirm-FileAttributes
        if (-not($validFileAttributes)){
            Write-LogInformation "File attribute validation FAILED. Exiting..."
            return
        }
        
        #invoke the main collectors code
        GetPerformanceDataAndLogs
    
        Write-LogInformation "Ending data collection" #DO NOT CHANGE - Message is backward compatible
    }   
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem

        $call_stack = $PSItem.Exception.InnerException 
        Write-LogError "Function '$mycommand' :  $call_stack"
    }
    finally {
        HandleCtrlCFinal
        Write-LogInformation ""
    }
}

function CopyrightAndWarranty()
{
    Microsoft.PowerShell.Utility\Write-Host "Copyright (c) 2022 Microsoft Corporation. All rights reserved. `n
    THE SOFTWARE IS PROVIDED `"AS IS`", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE. `n`n"
}

