function Get-RootDirectory() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
    $present_directory = Convert-Path -Path ".\..\"   #this goes to the SQL LogScout source code directory
    return $present_directory
}
function Get-OutputPath() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
        
    $present_directory = Get-RootDirectory
    $output_folder = ($present_directory + "\output\")

    return $output_folder
}
function Get-InternalPath() {
    Write-LogDebug "inside" $MyInvocation.MyCommand -DebugLogLevel 2
        
    $output_folder = Get-OutputPath
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
    $currentDate = [DateTime]::Now.AddDays(-10)
    $output_folder = Get-OutputPath
    $error_folder = Get-InternalPath
    $TestingInfrastructure_folder = TestingInfrastructure-Dir 

    $consolpath = $TestingInfrastructure_folder + 'consoloutput.txt'
    $ReportPath = $TestingInfrastructure_folder + $date + '_ExecutingCollector_CountValidation.txt'
    $error1 = 0

    $filter_pattern = @("*.txt", "*.out", "*.csv", "*.xel", "*.blg", "*.sqlplan", "*.trc", "*.LOG")
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
        echo "Executing CollectorFile Verification......" > $ReportPath

        Foreach ($file in Get-Childitem -Path $error_folder -Include $filter_pattern -Recurse -Filter "##SQLDIAG.LOG" ) 
        { 
            if ($file.LastWriteTime -gt $currentDate) 
            {
                if (Get-Content -Path $file | Select-String -pattern "Executing Collector" | Select-Object Line | Where-Object { $_ -ne "" }) 
                {
                    # get the type of exection -  consol input parameter
                    Get-Content -Path $file | Select-String -pattern "Console input:" |select -First 3 | select -Last 1| Select-Object Line | Where-Object { $_ -ne "" } > $consolpath
                    [String] $t = '';Get-Content $consolpath | % {$t += " $_"};[Regex]::Match($t, '(\w+)[^\w]*$').Groups[2].Value
                    $t = $t.Trim()
                    $len = $t.Length
                    $len = $len - 1
                    $consolinut = $t.Substring($len,1)
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


                                If ($consolinut -eq "0") 
                                {
                                    If  ($collecCount -eq 11)
                                    {
                                        $msg = "You executed ""Basic"" Scenario. Expected Collector count 11 matches current file count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Basic"" Scenario. so Total Collector count should be 11 but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }
                                If ($consolinut -eq "1") 
                                {
                                    If  ($collecCount -eq 23)
                                    {
                                        $msg = "You executed ""General Performance"" Scenario. Expected Collector count of 23 matches current file count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""General Performance"" Scenario. so Total Collector count should be 23 but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }            }
                                If ($consolinut -eq "2") 
                                {
                                    If  ($collecCount -eq 23)
                                    {
                                        $msg = "You executed ""Detailed Performance"" Scenario. Expected Collector count of 23 matches current Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Detailed Performance"" Scenario. so Total Collector count should be 23 but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }            }
                                If ($consolinut -eq "3") 
                                {
                                    If  ($collecCount -eq 14)
                                    {
                                        $msg = "You executed ""Replication"" Scenario. Expected Collector count of 14 matches current Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Replication"" Scenario. so Total Collector count should be 14 but the executed Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: FAILED' -ForegroundColor Red
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                }
                                If ($consolinut -eq "4") 
                                { 
                                    If  ($collecCount -eq 12)
                                    {
                                        $msg = "You executed ""Memory"" Scenario. Expected Collector count of 12 matches current Collector count is : " + $collecCount
                                        $msg = $msg.replace("`n", " ")
                                        Write-Host 'Status: SUCCESS' -ForegroundColor Green
                                        Write-Host 'Summary:'  $msg
                                        Write-Host "`n************************************************************************************************`n"
                                        echo $msg >>  $ReportPath
                                    }
                                    Else
                                    {
                                        $msg = "You executed ""Memory"" Scenario. so Total Collector count should be 12 but the executed Collector count is : " + $collecCount
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
            $internalfold = $dir + "\internal"
            $filecountouptput = (Get-ChildItem -Recurse $dir | Measure-Object).Count - (Get-ChildItem -Recurse $internalfold | Measure-Object).Count
            $msgcount = "Total file count is - " + $filecountouptput
            $msgcount = $msgcount.replace("`n", " ")
            echo ''  >>  $ReportPath
            echo $msgcount  >>  $ReportPath 
            echo ''  >>  $ReportPath
            Write-Host 'TEST: FileCount Validation'

            If ($consolinut -eq "0") 
            {
                If  ($filecountouptput -eq 15)
                {
                    $msg = "You executed ""Basic"" Scenario. Expected File count of 15 matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Basic"" Scenario. so Total File count should be 15 but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }
            If ($consolinut -eq "1") 
            {
                If  ($filecountouptput -eq 25)
                {
                    $msg = "You executed ""General Performance"" Scenario. Expected File count of 25 matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""General Performance"" Scenario. so Total File count should be 25 but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }            }
            If ($consolinut -eq "2") 
            {
                If  ($filecountouptput -eq 25)
                {
                    $msg = "You executed ""Detailed Performance"" Scenario. Expected File count of 25 matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Detailed Performance"" Scenario. so Total File count should be 25 but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }            }
            If ($consolinut -eq "3") 
            {
                If  ($filecountouptput -eq 18)
                {
                    $msg = "You executed ""Replication"" Scenario. Expected File count of 18 matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Replication"" Scenario. so Total File count should be 18 but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }
            If ($consolinut -eq "4") 
            { 
                If  ($filecountouptput -eq 16)
                {
                    $msg = "You executed ""Memory"" Scenario. Expected File count of 16 matches current file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: SUCCESS' -ForegroundColor Green
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
                Else
                {
                    $msg = "You executed ""Memory"" Scenario. so Total File count should be 16 but the generated file count is : " + $filecountouptput
                    $msg = $msg.replace("`n", " ")
                    Write-Host 'Status: FAILED' -ForegroundColor Red
                    Write-Host 'Summary:'  $msg
                    Write-Host "`n************************************************************************************************`n"
                    echo $msg >>  $ReportPath
                }
            }

        }
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
