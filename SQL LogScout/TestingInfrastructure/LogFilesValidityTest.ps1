$global:sqllogscout_log = "##SQLLOGSCOUT.LOG"

#---------------------------------------------------Files detail wrt differnet scinario-----------------------------------
$basic_collectors = 
@(
'RunningDrivers.csv',                                                                     
'RunningDrivers.txt',                                                                    
'SystemInfo_Summary.out',                                                                
'MiscPssdiagInfo.out',                                                                   
'TaskListServices.out',                                                                   
'TaskListVerbose.out',                                                                   
'collecterrorlog.out',                                                                   
'PowerPlan.out',                                                                          
'WindowsHotfixes.out',                                                                  
'FLTMC_Filters.out',                                                                     
'Instances.out',                                                                   
'AppEventLog.txt',                                                                        
'SysEventLog.txt',                                                
'SQLServerPerfStatsSnapshotShutdown.out'
)

$GeneralPerformance = 
(
'RunningDrivers.csv',
'RunningDrivers.txt',
'SystemInfo_Summary.out',
'MiscPssdiagInfo.out',
'TaskListServices.out',
'TaskListVerbose.out',
'collecterrorlog.out',
'PowerPlan.out',
'WindowsHotfixes.out',
'FLTMC_Filters.out',
'FLTMC_Instances.out',
'AppEventLog.txt',
'SysEventLog.txt',
'Perfmon.out_000001.blg',
'xevent_general_target',
'ExistingProfilerXeventTraces.out',
'HighCPU_perfstats.out',
'SQLServerPerfStats.out',
'SQLServerPerfStatsSnapshotStartup.out',
'Query Store.out',
'TempDBAnalysis.out',
'linked_server_config.out',
'SSB_diag.out',
'SQLServerPerfStatsSnapshotShutdown.out'
)
$DetailedPerformance = 
(
'RunningDrivers.csv',
'RunningDrivers.txt',
'SystemInfo_Summary.out',
'MiscPssdiagInfo.out',
'TaskListServices.out',
'TaskListVerbose.out',
'collecterrorlog.out',
'PowerPlan.out',
'WindowsHotfixes.out',
'FLTMC_Filters.out',
'FLTMC_Instances.out',
'AppEventLog.txt',
'SysEventLog.txt',
'Perfmon.out_000001.blg',
'xevent_detailed_target',
'ExistingProfilerXeventTraces.out',
'HighCPU_perfstats.out',
'SQLServerPerfStats.out',
'SQLServerPerfStatsSnapshotStartup.out',
'Query Store.out',
'TempDBAnalysis.out',
'linked_server_config.out',
'SSB_diag.out',
'SQLServerPerfStatsSnapshotShutdown.out'
)

$Replication= 
(
'RunningDrivers.csv',
'RunningDrivers.txt',
'SystemInfo_Summary.out',
'MiscPssdiagInfo.out',
'TaskListServices.out',
'TaskListVerbose.out',
'collecterrorlog.out',
'PowerPlan.out',
'WindowsHotfixes.out',
'FLTMC_Filters.out',
'FLTMC_Instances.out',
'AppEventLog.txt',
'SysEventLog.txt',
'Repl_Metadata_Collector.out',
'ChangeDataCapture.out',
'Change_Tracking.out',
'SQLServerPerfStatsSnapshotShutdown.out'
)

$AlwaysON = 
(
'RunningDrivers.csv',
'RunningDrivers.txt',
'SystemInfo_Summary.out',
'MiscPssdiagInfo.out',
'TaskListServices.out',
'TaskListVerbose.out',
'collecterrorlog.out',
'PowerPlan.out',
'WindowsHotfixes.out',
'FLTMC_Filters.out',
'FLTMC_Instances.out',
'AppEventLog.txt',
'SysEventLog.txt',
'AlwaysOnDiagScript.out',
'AlwaysOn_Data_Movement',
'SQLServerPerfStatsSnapshotShutdown.out'
)
$NetworkTrace = 
(
'NetworkTrace.cab',
'NetworkTrace.etl',
'SQLServerPerfStatsSnapshotShutdown.out'
)
$Memory = 
(
'SQLServerPerfStatsSnapshotShutdown.out'
) 
$GenerateMemorydumps = 
(
'SQLServerPerfStatsSnapshotShutdown.out',
'SQLDmpr0001.mdmp',
'SQLDUMPER_ERRORLOG.log'
)
$WPR = 
(
'etl.NGENPDB',
'SQLServerPerfStatsSnapshotShutdown.out',
'.etl'
)  
#------------------------------------------------------------------------------------------------------------------------
function Get-RootDirectory() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
    $present_directory = Convert-Path -Path ".\..\"   #this goes to the SQL LogScout source code directory
    return $present_directory
}
function Get-OutputPathLatest() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
        
    $present_directory = Get-RootDirectory
    $filter="output*"
    $latest = Get-ChildItem -Path $present_directory -Filter $filter | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $output_folder = ($present_directory + "\"+ $latest + "\")

    return $output_folder
}
function Get-InternalPath() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
        
    $output_folder = Get-OutputPathLatest
    $internal_output_folder = ($output_folder + "internal\")

    return $internal_output_folder
}
function Write-LogDebug() {
    <#
    .SYNOPSIS
        Write-LogDebug is a wrapper to Write-Log standardizing console color output
        Logging of debug messages will be skip if debug logging is disabled.

    .DESCRIPTION
        Write-LogDebug is a wrapper to Write-Log standardizing console color output
        Logging of debug messages will be skip if debug logging is disabled.

    .PARAMETER Message
        Message string to be logged

    .PARAMETER DebugLogLevel
        Optional - Level of the debug message ranging from 1 to 5.
        When ommitted Level 1 is assumed.

    .EXAMPLE
        Write-LogDebug "Inside" $MyInvocation.MyCommand -DebugLogLevel 2
    #>
    [CmdletBinding()]
    param ( 
        [Parameter(Position = 0, Mandatory, ValueFromRemainingArguments)] 
        [ValidateNotNull()]
        $Message,

        [Parameter()]
        [ValidateRange(1, 5)]
        [Int]$DebugLogLevel
    )

    #when $DebugLogLevel is not specified we assume it is level 1
    #this is to avoid having to refactor all calls to Write-LogDebug because of new parameter
    if (($null -eq $DebugLogLevel) -or (0 -eq $DebugLogLevel)) { $DebugLogLevel = 1 }

    try {

        #log message if debug logging is enabled and
        #debuglevel of the message is less than or equal to global level
        #otherwise we just skip calling Write-Log
        if (($global:DEBUG_LEVEL -gt 0) -and ($DebugLogLevel -le $global:DEBUG_LEVEL)) {
            Write-Log -Message $Message -LogType "DEBUG$DebugLogLevel" -ForegroundColor Magenta
            return #return here so we don't log messages twice if both debug flags are enabled
        }
            
    }
    catch {
        Write-Error -Exception $_.Exception
    }
}


function TestingInfrastructure-Dir() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2

    $present_directory = Convert-Path -Path "."   #this gets the current directory called \TestingInfrastructure
    $TestingInfrastructure_folder = $present_directory + "\output\"
    New-Item -Path $TestingInfrastructure_folder -ItemType Directory -Force | out-null 
    
    return $TestingInfrastructure_folder
}

function main() {
    $date = ( get-date ).ToString('yyyyMMdd');
    $currentDate = [DateTime]::Now.AddDays(-1)
    $output_folder = Get-OutputPathLatest
    $error_folder = Get-InternalPath
    $TestingInfrastructure_folder = TestingInfrastructure-Dir 

    #write-host $TestingInfrastructure_folder 


    $consolpath = $TestingInfrastructure_folder + 'consoloutput.txt'
    $ReportPath = $TestingInfrastructure_folder + $date + '_ExecutingCollector_CountValidation.txt'
    $error1 = 0

    $filter_pattern = @("*.txt", "*.out", "*.csv", "*.xel", "*.blg", "*.sqlplan", "*.trc", "*.LOG","*.etl","*.NGENPDB","*.mdmp")
    try {
        $count = 0
        if (!(Test-Path -Path $output_folder ))
        {
            $message1 = "Files are missing or folder " + $output_folder + " not exist"
                        $message1 = $message1.replace("`n", " ")
            Write-LogDebug $message1
            $TestingInfrastructure_folder1 =  $TestingInfrastructure_folder + 'FileMissing.LOG'
            echo $message1 > $TestingInfrastructure_folder1 
        }
        if (!(Test-Path -Path $error_folder ))
        {
            $message1 = "Files are missing or folder " + $error_folder + " not exist"
                            $message1 = $message1.replace("`n", " ")
            echo $message1 >> $TestingInfrastructure_folder1
            break;
        }

        $ReportPath = $TestingInfrastructure_folder + $date + '_ExecutingCollector_CountValidation.txt'
        $filemsg = "Executing tests from Source Folder: '" + $error_folder + $global:sqllogscout_log + "'" + " and cross verifying 'executing collector' info with output folder '" +  $output_folder +"'"
        Write-Host '         '
        Write-Host $filemsg
        Write-Host '         '
        echo $filemsg > $ReportPath

        Foreach ($file in Get-Childitem -Path $error_folder -Include $filter_pattern -Recurse -Filter "$global:sqllogscout_log" ) 
        { 
            if ($file.LastWriteTime -gt $currentDate) 
            {
                ## checking wheathere user ran the diagostic or not
                $collectorfound = Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" }
                if ($collectorfound[0] -eq "") 
                {
                    Write-Host "         "
                    Write-Host "         "
                    Write-Host "Diagnostic collector not found in log file $global:sqllogscout_log. Please re-run the SQL LogScout with selecting 'Performance and Basic Logs'" 
                    Write-Host "         "
                    Write-Host "         "
                    $filenotfound = 1 
                    echo " " > $ReportPath
                    $messagefilenotfound = "Diagnostic collector not found in log file $global:sqllogscout_log. Please re-run the SQL LogScout with selecting -> Performance and Basic Logs"
                    echo $messagefilenotfound > $ReportPath
                    break
                }

                if (Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" }) 
                {
                    # get the type of exection -  consol input parameter
                    $selectoutputfile =  3
                    $present_directory = Get-RootDirectory
                    $filter="output*"
                    $latest = Get-ChildItem -Path $present_directory -Filter $filter | Sort-Object LastWriteTime -Descending | Select-Object -First 1

                    if ($latest.Name -eq "output")
                    {
                        $selectoutputfile =  2
                    }
                    else
                    {
                        $selectoutputfile =  3
                    }
                    $fileoverride = Get-Content -Path $file | Select-String -pattern "Console input: D" | Select-Object Line | Where-Object { $_ -ne "" }
                    If ($fileoverride -ne "" )
                    {
                        $selectoutputfile =  3
                    }
                    Get-Content -Path $file | Select-String -pattern "Console input:" |select -First $selectoutputfile | select -Last 1| Select-Object Line | Where-Object { $_ -ne "" } > $consolpath
                    [String] $t = '';Get-Content $consolpath | % {$t += " $_"};[Regex]::Match($t, '(\w+)[^\w]*$').Groups[2].Value
                    $t = $t.Trim()
                    $len = $t.Length
                    $len = $len - 1
                    $console_input = $t.Substring($len,1)
                    if (Test-Path $consolpath) {
                      Remove-Item $consolpath
                    }
                    echo 'The collectors files are are below.......' >> $ReportPath
                    Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" } >>$ReportPath

                    $fileContent = Get-Content -Path $file | Select-String "Executing Collector" | Group-Object -property Pattern

                    $fileContent  | Select-object @{Name = $file.Name ; Expression = 
                        {
                            if ($_.Name -eq "Executing Collector") 
                            {
                                "Total Collector Files found: " + ($_.Count)

                                #Write-host "Total Collector Files found: "  ($_.Count)
                                Write-Host 'The Total Executing Collectors and Generated output file count validation Report:' 
                                $collecCount =  ($_.Count)
                                #Write-host '---------------------------------------------------'
                                Write-host '                                                   '
                                Write-Host 'TEST: ExecutingCollectors Validation' 


                                If ($console_input -eq "0") 
                                {
                                    $BasicExpectedCount = 11
                                    If  ($collecCount -eq $BasicExpectedCount)
                                    {
                                        $msg = "You executed ""Basic"" Scenario. Expected Collector count $BasicExpectedCount matches current file count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Basic"" Scenario. so Total Collector count should be $BasicExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }
                                If ($console_input -eq "1") 
                                {
                                    $GeneralPerfExpectedCount = 23
                                    If  ($collecCount -eq $GeneralPerfExpectedCount)
                                    {
                                        $msg = "You executed ""General Performance"" Scenario. Expected Collector count of $GeneralPerfExpectedCount matches current file count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""General Performance"" Scenario. so Total Collector count should be $GeneralPerfExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }            }
                                If ($console_input -eq "2") 
                                {
                                    $DetailedPerfExpectedCount = 23
                                    If  ($collecCount -eq $DetailedPerfExpectedCount)
                                    {
                                        $msg = "You executed ""Detailed Performance"" Scenario. Expected Collector count of $DetailedPerfExpectedCount matches current Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Detailed Performance"" Scenario. so Total Collector count should be $DetailedPerfExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }            }
                                If ($console_input -eq "3") 
                                {
                                    $ReplicationExpectedCount = 14
                                    If  ($collecCount -eq $ReplicationExpectedCount)
                                    {
                                        $msg = "You executed ""Replication"" Scenario. Expected Collector count of $ReplicationExpectedCount matches current Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Replication"" Scenario. so Total Collector count should be $ReplicationExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }
                                If ($console_input -eq "4") 
                                { 
                                    $AlwaysOnExpectedCount = 15
                                    If  ($collecCount -eq $AlwaysOnExpectedCount)
                                    {
                                        $msg = "You executed ""AlwaysON"" Scenario. Expected Collector count of $AlwaysOnExpectedCount matches current Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""AlwaysON"" Scenario. so Total Collector count should be $AlwaysOnExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }
                                If ($console_input -eq "5") 
                                {
                                    $NetTraceExpectedCount = 1
                                    If  ($collecCount -eq $NetTraceExpectedCount)
                                    {
                                        $collecCount = $collecCount + 2
                                        $msg = "You executed ""NetworkTrace"" Scenario. Expected Collector count $NetTraceExpectedCount matches current file count is : " + $collecCount 
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $collecCount = $collecCount + 2
                                        $msg = "You executed ""NetworkTrace"" Scenario. so Total Collector count should be $NetTraceExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }

                                If ($console_input -eq "6") 
                                {
                                    $MemoryExpectedCount = 13
                                    If  ($collecCount -eq $MemoryExpectedCount)
                                    {
                                        $msg = "You executed ""Memory"" Scenario. Expected Collector count $MemoryExpectedCount matches current file count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Memory"" Scenario. Total Collector count should be $MemoryExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }
                                If ($console_input -eq "7") 
                                {
                                    $DumpMemExpectedCount = 1
                                    If  ($collecCount -eq $DumpMemExpectedCount)
                                    {
                                        $msg = "You executed ""Generate Memory dumps"" Scenario. Expected Collector count $DumpMemExpectedCount matches current file count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Generate Memory dumps"" Scenario. so Total Collector count should be $DumpMemExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }
                                If ($console_input -eq "8") 
                                {
                                    $WPRExpectedCount = 1
                                    If  ($collecCount -eq $WPRExpectedCount)
                                    {
                                        $msg = "You executed ""Windows Performance Recorder (WPR)"" Scenario. Expected Collector count $WPRExpectedCount matches current file count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Windows Performance Recorder (WPR)"" Scenario. so Total Collector count should be $WPRExpectedCount but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }
                            }
                        }
                    } >>$ReportPath
                }
            }
            else 
            {
                echo 'The collectors files are old.......' >> $ReportPath
                Write-Host 'The collectors files are old.......'
            }

            #--------------------------------------------------------------------------------------------------------------------------------------------------

            $fileContent = Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" }
            $ReportPath = $TestingInfrastructure_folder + $date + '_OutputFileCountValidation.txt'
            echo "Output folder File Verification......" > $ReportPath

            For ($i = 1; $i -le $fileContent.Count - 1 ; $i++) {
                [String] $fileContent1stLine = ""
                [String] $fileContentSelectedline = $fileContent | select-object -Index  $i
                $j = 1
                For ($j = 1; $j -le $fileContentSelectedline.Length - 1 ; $j++) {
                    if ($fileContentSelectedline[$j] -eq ":") {
                        $startchar = $j
                    }
                    
                }
                $endChar = $fileContentSelectedline.Length - $startchar - 1
                $fileContentSelectedline = $fileContentSelectedline.Substring($startchar, $endChar)

                $dir = $output_folder
                $filesout = (Get-ChildItem $dir).Name # | foreach {$_.Split(".")[0]} #| Where-Object { $_. -ne ""} 
                $filefound = 0
                foreach ($fileout in $filesout) {
                    $filenamewithext = $fileout
                    $fileout = $fileout.Split(".")[0]
                    $str1 = $fileout.LastIndexOf("_") + 1 
                    $index = $fileout.IndexOf('_', $fileout.IndexOf('_') + 1);
                    $str2 = $fileout.Length - ($fileout.LastIndexOf("_") + 1 )
                    $file = $fileout.Substring($str1, $str2)

                    $file1 = $fileout.Substring($fileout.IndexOf('_') + 1, $fileout.length - ($fileout.IndexOf('_') + 1) )
                    $file2 = $file1.Substring($file1.IndexOf('_') + 1, $file1.length - ($file1.IndexOf('_') + 1) )

                    if (($file2 -notlike 'internal' ) -and ( $file2 -notlike 'LogmanConfig') -and ($file2 -notlike 'sanityCheck')) {
                        $filecount = $filecount + 1
                        if ((Get-ChildItem $dir | Where-Object { $_.Name -match $file2 }).Exists) {
                            if ($fileContentSelectedline -match $file2) {
                                $matchedFilename = (Get-ChildItem $dir | Where-Object { $_.Name -match $file2 }).name
                                $message = "File with name like --> " + $file2 + " exists : " + $matchedFilename.TrimEnd() + ""
                                $message = $message.replace("`n", " ")
                                echo $message >>  $ReportPath 
                            } 
                        }
                        elseif ((Get-ChildItem $dir | Where-Object { $_.Name -match $file2 }).Exists) {
                            $message = "File with name like " + $file2.TrimEnd() + " not exists"
                            $message = $message.replace("`n", " ")
                            echo $message >>  $ReportPath 
                        }
                    }
                }
            }

            $dir = $output_folder
            $internalfold = $dir + "\internal"
            $filecountouptput = (Get-ChildItem -Recurse $dir | Measure-Object).Count - (Get-ChildItem -Recurse $internalfold | Measure-Object).Count
            $msgcount = "Total file count is - " + $filecountouptput
            $msgcount = $msgcount.replace("`n", " ")
            echo ''  >>  $ReportPath
            echo $msgcount  >>  $ReportPath 
            echo ''  >>  $ReportPath
            Write-Host 'TEST: FileCount Validation'
            Write-Host "Console input $console_input"
            Write-Host " "
            Write-Host "internal folder - $internalfold"

            If ($console_input -eq "0") 
            {
                $BasicPerfExpectedFileCount=15
                If  ($filecountouptput -eq $BasicPerfExpectedFileCount)
                {
                    $msg = "You executed ""Basic"" Scenario. Expected File count of $BasicPerfExpectedFileCount matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Basic"" Scenario. so Total File count should be $BasicPerfExpectedFileCount but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $basic_collectors.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $basic_collectors[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host 'File not found is -> '$basic_collectors[$i] -ForegroundColor red
                            $msg = $msg + 'File not found for '+ $basic_collectors[$i]
                        }
                    }
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }
            If ($console_input -eq "1") 
            {
                $GenPerfExpectedFileCount = 25
                If  ($filecountouptput -eq $GenPerfExpectedFileCount)
                {
                    $msg = "You executed ""General Performance"" Scenario. Expected File count of $GenPerfExpectedFileCount matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""General Performance"" Scenario. so Total File count should be $GenPerfExpectedFileCount but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $GeneralPerformance.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $GeneralPerformance[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host 'File not found is -> '$GeneralPerformance[$i] -ForegroundColor red
                            $msg = $msg + 'File not found for '+ $GeneralPerformance[$i]
                        }
                    }
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }            }
            If ($console_input -eq "2") 
            {
                $DetailPerfExpectedFileCount =25
                If  ($filecountouptput -eq $DetailPerfExpectedFileCount)
                {
                    $msg = "You executed ""Detailed Performance"" Scenario. Expected File count of $DetailPerfExpectedFileCount matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Detailed Performance"" Scenario. so Total File count should be $DetailPerfExpectedFileCount but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $DetailedPerformance.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $DetailedPerformance[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host 'File not found is -> '$DetailedPerformance[$i] -ForegroundColor red
                            $msg = $msg + 'File not found for '+ $DetailedPerformance[$i]
                        }
                    }
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }            }
            If ($console_input -eq "3") 
            {
                $ReplicationExpectedFileCount = 18
                If  ($filecountouptput -eq $ReplicationExpectedFileCount)
                {
                    $msg = "You executed ""Replication"" Scenario. Expected File count of $ReplicationExpectedFileCount matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Replication"" Scenario. so Total File count should be $ReplicationExpectedFileCount but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $Replication.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $Replication[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host 'File not found is -> '$Replication[$i] -ForegroundColor red
                            $msg = $msg + 'File not found for '+ $Replication[$i]
                        }
                    }
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }
            If ($console_input -eq "4") 
            { 
                $ReplicationExpectedFileCount =17
                If  ($filecountouptput -eq $ReplicationExpectedFileCount)
                {
                    $msg = "You executed ""AlwaysON"" Scenario. Expected File count of $ReplicationExpectedFileCount matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""AlwaysON"" Scenario. so Total File count should be $ReplicationExpectedFileCount but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $AlwaysON.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $AlwaysON[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host 'File not found is -> '$AlwaysON[$i] -ForegroundColor red
                            $msg = $msg + 'File not found for '+ $AlwaysON[$i]
                        }
                    }

                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }

            If ($console_input -eq "5") 
            { 
                $NetTraceExpectedFileCount = 3
                If  ($filecountouptput -eq $NetTraceExpectedFileCount)
                {
                    $msg = "You executed ""Network Trace"" Scenario. Expected File count of $NetTraceExpectedFileCount matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Network Trace"" Scenario. so Total File count should be $NetTraceExpectedFileCount but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $NetworkTrace.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $NetworkTrace[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host 'File not found is -> '$NetworkTrace[$i] -ForegroundColor red
                            $msg = $msg + 'File not found for '+ $NetworkTrace[$i]
                        }
                    }

                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }
            If ($console_input -eq "6") 
            { 
                $MemoryExpectedFileCount =17
                If  ($filecountouptput -eq $MemoryExpectedFileCount)
                {
                    $msg = "You executed ""Memory"" Scenario. Expected File count of $MemoryExpectedFileCount matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Memory"" Scenario. so Total File count should be $MemoryExpectedFileCount but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $Memory.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $Memory[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host 'File not found is -> '$Memory[$i] -ForegroundColor red
                            $msg = $msg + 'File not found for '+ $Memory[$i]
                        }
                    }

                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }
            If ($console_input -eq "7") 
            { 
                $MemoryDumpExpectedFileCount = 4
                If  ($filecountouptput -ge $MemoryDumpExpectedFileCount)
                {
                    $msg = "You executed ""Generate Memory dumps"" Scenario. Expected File count of $MemoryDumpExpectedFileCount or more than $MemoryDumpExpectedFileCount based on your selection ,current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Generate Memory dumps"" Scenario. so Total File count should eqal to $MemoryDumpExpectedFileCount + number of file you select to generate, but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $GenerateMemorydumps.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $GenerateMemorydumps[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host 'File not found is -> '$GenerateMemorydumps[$i] -ForegroundColor red
                            $msg = $msg + 'File not found for '+ $GenerateMemorydumps[$i]
                        }
                    }

                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }
            If ($console_input -eq "8") 
            { 
                $WPRExpectedFileCount = 250
                If  ($filecountouptput -ge $MemoryDumpExpectedFileCount)
                {
                    $msg = "You executed 'Windows Performance Recorder (WPR)' Scenario. There is 1 .etl file and remaining files are metadata with folder last name .etl.NGENPDB"
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed 'Windows Performance Recorder (WPR)' Scenario. There should be 1 .etl file and a metadata folder with last name like .etl.NGENPDB"
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg $filecountouptput
                    Write-Host "`n************************************************************************************************`n"
                    For ($i=0; $i -lt $WPR.Length; $i++) 
                    {
                        $blnfileexist =  '0'
    
                        Foreach ($filefound in Get-ChildItem $output_folder | Where-Object {$_.Name -like "*" + $WPR[$i] + "*" }| select FullName)
                        {
                            $blnfileexist =  '1'
                        }
                        if ($blnfileexist -eq  '0')
                        {
                            Write-Host "File not found is -> " $WPR[$i] -ForegroundColor red
                            $msg = $msg + "File not found for " + $WPR[$i]
                        }
                    }

                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }

        }
        #if ($filenotfound = 1)
        #{
        #    echo $messagefilenotfound >>  $ReportPath
        #}
        $msg2 = "Testing has been completed , reports are at: " + $TestingInfrastructure_folder 
        Write-Host $msg2
        Write-Host "`n`n"
    }
    catch {
        Write-Host $_.Exception.Message
    }

}
##call main()
main 
