$LoggingFacilityModule = Get-Module -Name LoggingFacility | select-object Name

if ($LoggingFacilityModule.Name -ne "LoggingFacility")
{
    Import-Module -Name ..\LoggingFacility.psm1
}

function Search-Log {
<#
    .SYNOPSIS
        Open each log matching filename pattern and look for each string pattern in it.
    .DESCRIPTION
        Open each log matching filename pattern and look for each string pattern in it.
        Writes directly into summary file and detailed file.
    .EXAMPLE
        
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$LogNamePattern = "..\output\internal\##SQLLOGSCOUT_DEBUG.LOG",

    [Parameter()]
    $MessagePatterns = @(
        "\tERROR\t", 
        "Msg\s\d{1,5},\sLevel\s\d{1,3},\sState\s\d{1,2},\s.*Line\s\d+"
        ),

    [Parameter()]
    [string]$SummaryFilename = ".\output\SUMMARY.TXT",

    [Parameter()]
    [string]$DetailedFilename = ".\output\SearchForErrors_Detailed.TXT"
    )

    try {

        $return_val = $true

        #clear contents of the detailed file
        if (Test-Path $DetailedFilename)
        {
            Clear-Content -Path $DetailedFilename
        }

        #search the debug log for errors
        $AllMatches = Select-String -Path $LogNamePattern -Pattern $MessagePatterns

        [System.Text.StringBuilder]$detailedOutput = New-Object -TypeName System.Text.StringBuilder
        [string]$Path = ""

        foreach($Match in $AllMatches){

            #if the Match is for a different filename then print header
            if($Path -ne $Match.Path){
                
                $Path = $Match.Path

                [void]$detailedOutput.AppendLine("")
                [void]$detailedOutput.AppendLine("********************************************************************")
                [void]$detailedOutput.AppendLine(" Found errors in file: $Path")
                [void]$detailedOutput.AppendLine("********************************************************************")
            }
            
            [void]$detailedOutput.AppendLine($Match.LineNumber.ToString() + ": " + $Match.Line)
        }

        #write to the detailed output to file if there is any error found
        if (-not([string]::IsNullOrWhiteSpace($detailedOutput.ToString()))){
            $detailedOutput.ToString() | Out-File $DetailedFilename -Append
        }

        #write summary to file
        $SummaryMsg = "Total Error Pattern Match: " + $AllMatches.Matches.Count.ToString()

        if(0 -eq $AllMatches.Matches.Count)
        {
            $SummaryMsg = ($SummaryMsg + " "*(60 - $SummaryMsg.Length) + "SUCCESS")
        } 
        else 
        {
            # build the full path to the detailed file
            $cwd = (Get-location).Path 
            $detailedFileFullPath = (Join-Path $cwd $DetailedFilename) | Resolve-Path
            
            $SummaryMsg = ($SummaryMsg + " "*(60 - $SummaryMsg.Length) + "ERRORS FOUND! (See '$detailedFileFullPath' for more details)")
            $return_val = $false
        }
        
        Write-Output ($SummaryMsg) | Out-File $SummaryFilename -Append



        if ($return_val -eq $false)
        {
            
            Write-Host "Printing detailed Search-Log test output '$detailedFileFullPath)':`n"
            Get-Content -Path $DetailedFilename | Out-Host
        }
        return $return_val
    }
    catch {
        
        $error_msg = $PSItem.Exception.Message
        $error_linenum = $PSItem.InvocationInfo.ScriptLineNumber
        $error_offset = $PSItem.InvocationInfo.OffsetInLine
        $error_script = $PSItem.InvocationInfo.ScriptName
        Write-LogError "Function '$($MyInvocation.MyCommand)' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    
        $return_val = $false
    }
}
