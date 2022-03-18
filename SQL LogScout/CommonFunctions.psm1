
#=======================================Start of \OUTPUT and \Internal directories and files Section
function InitCriticalDirectories()
{
    try 
    {
        #initialize this directories
        Set-PresentDirectory 
        Set-OutputPath
        Set-InternalPath    
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  -exit_logscout $true  
    }

}


function Set-PresentDirectory()
{
	Write-LogDebug "inside" $MyInvocation.MyCommand

    try 
    {
        $global:present_directory = Convert-Path -Path "."
        Write-LogInformation "The Present folder for this collection is" $global:present_directory     
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem        
    }
    
}

function Set-OutputPath()
{

    try
    {
        Write-LogDebug "inside" $MyInvocation.MyCommand
        
        #default final directory to present directory (.)
        [string] $final_directory  = $global:present_directory

        # if "UsePresentDir" is passed as a param value, then create where SQL LogScout runs
        if ($global:custom_user_directory -eq "UsePresentDir")
        {
            $final_directory  = $global:present_directory
        }
        #if a custom directory is passed as a parameter to the script. Parameter validation also runs Test-Path on $CustomOutputPath
        elseif (Test-Path -Path $global:custom_user_directory)
        {
            $final_directory = $global:custom_user_directory

        }
        elseif ($global:custom_user_directory -eq "PromptForCustomDir")    
        {
            $userlogfolder = Read-Host "Would your like the logs to be collected on a non-default drive and directory?" -CustomLogMessage "Prompt CustomDir Console Input:"
            $HelpMessage = "Please enter a valid input (Y or N)"

            $ValidInput = "Y","N"
            $AllInput = @()
            $AllInput += , $ValidInput
            $AllInput += , $userlogfolder
            $AllInput += , $HelpMessage

            $YNselected = validateUserInput($AllInput)
            

            if ($YNselected -eq "Y")
            {
                [string] $customOutDir = [string]::Empty

                while([string]::IsNullOrWhiteSpace($customOutDir) -or !(Test-Path -Path $customOutDir))
                {

                    $customOutDir = Read-Host "Enter an output folder with no quotes (e.g. C:\MyTempFolder or C:\My Folder)" -CustomLogMessage "Get Custom Output Folder Console Input:"
                    if ($customOutDir -eq "" -or !(Test-Path -Path $customOutDir))
                    {
                        Write-Host "'" $customOutDir "' is not a valid path. Please, enter a valid drive and folder location" -ForegroundColor Yellow
                    }
                }

                $final_directory =  $customOutDir
            }


        }

        #the output folder is subfolder of current folder where the tool is running
        $global:output_folder =  ($final_directory + "\output\")
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        exit
    }

}

function Set-NewOutputPath 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try 
    {
        [string] $new_output_folder_name = "_" + @(Get-Date -Format ddMMyyhhmmss) + "\"
        $global:output_folder = $global:output_folder.Substring(0, ($global:output_folder.Length-1)) + $new_output_folder_name        
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem  
    }
    
}

function Set-InternalPath()
{
	Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try 
    {
        #the \internal folder is subfolder of \output
        $global:internal_output_folder =  ($global:output_folder  + "internal\")    
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem    
    }
}

function CreatePartialOutputFilename ([string]$server)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try 
    {
        if ($global:output_folder -ne "")
        {
            $server_based_file_name = $server -replace "\\", "_"
            $output_file_name = $global:output_folder + $server_based_file_name + "_" + @(Get-Date -Format FileDateTime)
        }
        Write-LogDebug "The server_based_file_name: " $server_based_file_name -DebugLogLevel 3
        Write-LogDebug "The output_path_filename is: " $output_file_name -DebugLogLevel 2
        
        return $output_file_name
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem    
    }
    
}

function CreatePartialErrorOutputFilename ([string]$server)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

	try 
    {
        if (($server -eq "") -or ($null -eq $server)) 
        {
            $server = $global:host_name 
        }
        
        $error_folder = $global:internal_output_folder 
        
        $server_based_file_name = $server -replace "\\", "_"
        $error_output_file_name = $error_folder + $server_based_file_name + "_" + @(Get-Date -Format FileDateTime)
        
        Write-LogDebug "The error_output_path_filename is: " $error_output_file_name -DebugLogLevel 2
        
        return $error_output_file_name
        
    }

    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem 
    }
}

function ReuseOrRecreateOutputFolder() 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    Write-LogDebug "Output folder is: $global:output_folder" -DebugLogLevel 3
    Write-LogDebug "Error folder is: $global:internal_output_folder" -DebugLogLevel 3
    
    try {
    
        #delete entire \output folder and files/subfolders before you create a new one, if user chooses that
        if (Test-Path -Path $global:output_folder)  
        {
            if ([string]::IsNullOrWhiteSpace($DeleteExistingOrCreateNew) )
            {
                Write-LogInformation ""
        
                [string]$DeleteOrNew = ""
                Write-LogWarning "It appears that output folder '$global:output_folder' has been used before."
                Write-LogWarning "You can choose to:"
                Write-LogWarning " - Delete (D) the \output folder contents and recreate it"
                Write-LogWarning " - Create a new (N) folder using \Output_ddMMyyhhmmss format." 
                Write-LogWarning "   You can delete the new folder manually in the future"
    
                while (-not(($DeleteOrNew -eq "D") -or ($DeleteOrNew -eq "N"))) 
                {
                    $DeleteOrNew = Read-Host "Delete ('D') or create New ('N') >" -CustomLogMessage "Output folder Console input:"
                    
                    $DeleteOrNew = $DeleteOrNew.ToString().ToUpper()
                    if (-not(($DeleteOrNew -eq "D") -or ($DeleteOrNew -eq "N"))) {
                        Write-LogError ""
                        Write-LogError "Please chose [D] to DELETE the output folder $global:output_folder and all files inside of the folder."
                        Write-LogError "Please chose [N] to CREATE a new folder"
                        Write-LogError ""
                    }
                }

            }

            elseif ($DeleteExistingOrCreateNew -in "DeleteDefaultFolder","NewCustomFolder") 
            {
                Write-LogDebug "The DeleteExistingOrCreateNew parameter is $DeleteExistingOrCreateNew" -DebugLogLevel 2

                switch ($DeleteExistingOrCreateNew) 
                {
                    "DeleteDefaultFolder"   {$DeleteOrNew = "D"}
                    "NewCustomFolder"       {$DeleteOrNew = "N"}
                }
                
            }

        }#end of IF

        
        #Get-Childitem -Path $output_folder -Recurse | Remove-Item -Confirm -Force -Recurse  | Out-Null
        if ($DeleteOrNew -eq "D") 
        {
            #delete the existing \output folder
            Remove-Item -Path $global:output_folder -Force -Recurse  | Out-Null
            Write-LogWarning "Deleted $global:output_folder and its contents"
        }
        elseif ($DeleteOrNew -eq "N") 
        {

            #these two calls updates the two globals for the new output and internal folders using the \Output_ddMMyyhhmmss format.
            
            # [string] $new_output_folder_name = "_" + @(Get-Date -Format ddMMyyhhmmss) + "\"
            # $global:output_folder = $global:output_folder.Substring(0, ($global:output_folder.Length-1)) + $new_output_folder_name

            Set-NewOutputPath
            Write-LogDebug "The new output path is: $global:output_folder" -DebugLogLevel 3
        
            #call Set-InternalPath to reset the \Internal folder
            Set-InternalPath
            Write-LogDebug "The new error path is: $global:internal_output_folder" -DebugLogLevel 3
        }

        

	
        #create an output folder AND error directory in one shot (creating the child folder \internal will create the parent \output also). -Force will not overwrite it, it will reuse the folder
        New-Item -Path $global:internal_output_folder -ItemType Directory -Force | out-null 
        
        Write-LogInformation "Output path: $global:output_folder"  #DO NOT CHANGE - Message is backward compatible
        Write-LogInformation "Error  path is" $global:internal_output_folder 
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem -exit_logscout $true
        return $false
    }
}

function BuildFinalOutputFile([string]$output_file_name, [string]$collector_name, [bool]$needExtraQuotes, [string]$fileExt = ".out")
{
	Write-LogDebug "inside" $MyInvocation.MyCommand
	
    try 
    {
        $final_output_file = $output_file_name + "_" + $collector_name + $fileExt
	
        if ($needExtraQuotes)
        {
            $final_output_file = "`"" + $final_output_file + "`""
        }

        return $final_output_file
    }

    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
	
}

function BuildInputScript([string]$present_directory, [string]$script_name)
{
	Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try 
    {
        $input_script = "`"" + $present_directory+"\"+$script_name +".sql" + "`""
        return $input_script
    }
    
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem    
    }
	
}

function BuildFinalErrorFile([string]$partial_error_output_file_name, [string]$collector_name, [bool]$needExtraQuotes)
{
	Write-LogDebug "inside" $MyInvocation.MyCommand
	
    try 
    {
        $error_file = $partial_error_output_file_name + "_"+ $collector_name + "_errors.out"
	
        if ($needExtraQuotes)
        {
            $error_file = "`"" + $error_file + "`""
        }
		
	    return $error_file
    }
    catch 
    {

        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
	
}


#=======================================End of \OUTPUT and \Internal directories and files Section


#======================================== START of Process management section

function StartNewProcess()
{
    param
    (
        [Parameter(Mandatory=$true, Position=0)]
        [String] $FilePath,

        [Parameter(Mandatory=$false, Position=1)]
        [String] $ArgumentList = [String]::Empty,

        [Parameter(Mandatory=$false, Position=2)]
        [System.Diagnostics.ProcessWindowStyle] $WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized,
    
        [Parameter(Mandatory=$false, Position=3)]
        [String] $RedirectStandardError = [String]::Empty,    
    
        [Parameter(Mandatory=$false, Position=4)]
        [String] $RedirectStandardOutput = [String]::Empty,

        [Parameter(Mandatory=$false, Position=5)]
        [bool] $Wait = $false
    )

    Write-LogDebug "inside" $MyInvocation.MyCommand

    [console]::TreatControlCAsInput = $true

    try 
    {
        #build a hash table of parameters
            
        $StartProcessParams = @{            
            FilePath= $FilePath
        }    

        if ($ArgumentList -ne [String]::Empty)
        {
            [void]$StartProcessParams.Add("ArgumentList", $ArgumentList)     
        }

        if ($null -ne $WindowStyle)
        {
            [void]$StartProcessParams.Add("WindowStyle", $WindowStyle)     
        }

        if ($RedirectStandardOutput -ne [String]::Empty)
        {
            [void]$StartProcessParams.Add("RedirectStandardOutput", $RedirectStandardOutput)     
        }

        if ($RedirectStandardError -ne [String]::Empty)
        {
            [void]$StartProcessParams.Add("RedirectStandardError", $RedirectStandardError)     
        }

        # we will always use -PassThru because we want to keep track of processes launched
        [void]$StartProcessParams.Add("PassThru", $null)     

        if ($true -eq $Wait)
        {
            [void]$StartProcessParams.Add("Wait", $null)
        }
        #print the command executed
        Write-LogDebug $FilePath $ArgumentList

        Write-LogDebug ("StartNewProcess parameters: " + $StartProcessParams.Keys) -DebugLogLevel 5
        Write-LogDebug ("StartNewProcess parameter values: " + $StartProcessParams.Values) -DebugLogLevel 5

        # start the process
        #equivalent to $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WindowStyle $WindowStyle -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError -PassThru -Wait
        $p = Start-Process @StartProcessParams

        #touch a few properties to make sure the process object is populated with them - specifically name and start time
        $pn = $p.ProcessName
        $sh = $p.SafeHandle
        $st = $p.StartTime

        # add the process object to the array of started processes (if it has not exited already)
        if($false -eq $p.HasExited)   
        {
            [void]$global:processes.Add($p)
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    

}

function Start-SQLCmdProcess([string]$collector_name, [string]$input_script_name, [bool]$is_query=$false, [string]$query_text, [bool]$has_output_results=$true)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $server = $global:sql_instance_conn_str

    [console]::TreatControlCAsInput = $true


    # if query is empty and script should be populated
    # if query is populated script should be ::Empty


    try 
    {
        
        #in case CTRL+C is pressed
        HandleCtrlC

        if ($true -eq [string]::IsNullOrWhiteSpace($collector_name))
        {
            $collector_name = "blank_collector_name"
        }

        $input_script = BuildInputScript $global:present_directory $input_script_name 
        
        $executable = "sqlcmd.exe"
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w8000"



        if (($is_query -eq $true) -and ([string]::IsNullOrWhiteSpace($query_text) -ne $true) )
        {
            $argument_list += " -Q`"" + $query_text + "`""
        }
        else #otherwise use an input script
        {
            $argument_list += " -i" + $input_script 
        }

        #most executions produce output - so we should include an -o parameter for SQLCMD
        if ($has_output_results -eq $true)
        {
            $partial_output_file_name = CreatePartialOutputFilename ($server)
            
            $output_file = BuildFinalOutputFile -output_file_name $partial_output_file_name -collector_name $collector_name -needExtraQuotes $true
            $argument_list += " -o" + $output_file
        }

        
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stderr") -needExtraQuotes $false 
        $stdoutput_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stdout") -needExtraQuotes $false 

        Write-LogInformation "Executing Collector: $collector_name"
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -RedirectStandardOutput $stdoutput_file
        
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

#======================================== END of Process management section


#check if cluster - based on cluster service status and cluster registry key
function IsClustered()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $ret = $false
    $error_msg = ""
        
    $clusServiceisRunning = $false
    $clusRegKeyExists = $false
    $ClusterServiceKey="HKLM:\Cluster"

    # Check if cluster service is running
    try 
    { 
        if ((Get-Service |  Where-Object  {$_.Displayname -match "Cluster Service"}).Status -eq "Running") 
        {
            $clusServiceisRunning =  $true
            Write-LogDebug "Cluster services status is running: $clusServiceisRunning  " -DebugLogLevel 2   
        }
        
        if (Test-Path $ClusterServiceKey) 
        { 
            $clusRegKeyExists  = $true
            Write-LogDebug "Cluster key $ClusterServiceKey Exists: $clusRegKeyExists  " -DebugLogLevel 2
        }

        if (($clusRegKeyExists -eq $true) -and ($clusServiceisRunning -eq $true ))
        {
            Write-LogDebug 'This is a Windows Cluster for sure!' -DebugLogLevel 2
            Write-LogInformation 'This is a Windows Cluster'
            return $true
        }
        else 
        {
            Write-LogDebug 'This is Not a Windows Cluster!' -DebugLogLevel 2
            return $false
        }
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

    return $ret
}

function Get-InstanceNameOnly([string]$NetnamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try 
    {
        $selectedSqlInstance  = $NetnamePlusInstance.Substring($NetnamePlusInstance.IndexOf("\") + 1)
        return $selectedSqlInstance         
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}


#used in Catch blocks throughout
function HandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    Write-LogError "Function '$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)"    

    if ($exit_logscout)
    {
        Write-LogWarning "Exiting SQL LogScout..."
        exit
    }
}



# SIG # Begin signature block
# MIInpwYJKoZIhvcNAQcCoIInmDCCJ5QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBn8xv4aoQExFKj
# VqSrHUbvmTm2Etk9euFSv96HgKmO5aCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
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
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEICBH
# kaXgXLgxjhn3ZHFii1F0lsYACcwIngnSVY6ZTQmJMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3d3cubWljcm9zb2Z0
# LmNvbTANBgkqhkiG9w0BAQEFAASCAQCMEvHa0U9pQ+hEEMKO2yrB23ejK1tZJ3lM
# +IK8Moe0YhAh6PzklPPEWmqQV1JgzsZQbBqzRUv48yJ5Rgf5eTaZFCmkqj42OcvY
# MGapQVF23gHNfJd5P3Mk8lYCbINViOD/n3YnPEg54m8loEfMt1F7CJoAqHz1Tt/x
# cfTM4iUPuVd6nZT+FrCNQxRePnY8lnv4DziqR0SHLxLSEkaRhqsgl2F3amOit89r
# Eb77yd3916Bg23DFPBz6PFFC5ZBYhOu9L3nY55tufNxujYsr4zT2EPrz1bwblN0u
# HUz1GvjZII77UcKF+8l+9V6YiBOXqGx2SR7ufSk2kmsFr5wCVmWMoYIXADCCFvwG
# CisGAQQBgjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIGkE27L6oeleEttA7xd0evOgU249mBE8
# ws1auwcbzihdAgZiFl7b9McYEzIwMjIwMzAxMTI1MDA3LjU5M1owBIACAfSggdCk
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
# hkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg6wd2nFKdNNGjsUfcK4Huoe+NklLP
# 0fx5RVdDfvoQllwwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBc5kvhjZAL
# e2mhIz/Qd7keVOmA/cC1dzKZT4ybLEkCxzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAABlbf8DdbjNzElAAEAAAGVMCIEIEoh/phCqCUc
# IPPiyGWCEdRvsvakFpcxPBkeGlu/JAB3MA0GCSqGSIb3DQEBCwUABIICAAouKqQF
# mX4bp00ia0t3Z8TggXv4n7RdGH8BDQmXydLVKGVPpmxvCWllzAZ0wIpU4KbWcy08
# bfMKdjqI958vJOVzakvnCxWOVzvvwrzZpGQZ4XuAWfA0LRZFHOp5q/2KdhcyZLgh
# hWANSQREiw6lZQgnYt1rvcTCsZU2JxRcAfUFfUKu+DGVj9cp8Hwd0RIdoKpa6B94
# FfO+z+EmC389kLJsCaciPAHtZrikJLkqqxpy3dlMPfywQzGEzo562UQa7LlTwUn8
# y+UwJbvC7h5mcHz2tGcx3BGFKfpPVcMM4ORLwwadlhfIPHc7pfuvKs+BS2drWEMs
# +S3grQt5AxYLH5vJvVVOKOrM4/0HG5uwQy2sQJtJZJjaktJ4XJ2jsqmOskhHQcap
# CiyVsbEXUnGgdu7dcOWiNm7sH7QHoMYIuWjXiVkPg3I3lsMy8HfxA2CVLgTuRnDq
# bUW+YAZ644D2qD19fuI7VtSSLuwAZPjHRiJTyGl5FcDaTfRVo7rz4V8haO6u3LOH
# IImIsNpm2EZlZzfDTyivp830167aZoCQ+XG142nVCIJTwPNB8Kg24koqRQhetxn7
# APIaY+itdQh8k9+au+pUgI5eweJFISJStHiVLIGpWr2DKfejvQtXMv9RmjdIfTNQ
# yNDW/ehWNOk1VOy4HY4E0gBfW4inXpwBlD2z
# SIG # End signature block
