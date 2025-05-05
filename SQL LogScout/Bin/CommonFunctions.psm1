
#=======================================Start of \OUTPUT and \Internal directories and files Section
function InitCriticalDirectories()
{
    try 
    {
        # This will set presentaion mode either GUI or console.
        if ($PSVersionTable.PSVersion.Major -gt 4) {
            Set-Mode
        }
        else{
            $PSVersion =$PSVersionTable.PSVersion.Major
            Write-LogWarning "Only script mode is supported on PS Version: $PSVersion"
        }
        if ($global:gui_mode) 
        {
            InitializeGUIComponent  
            if($global:gui_Result -eq $false)
            {
                exit
            }
        }
        else
        {
            #initialize this directories
            Set-PresentDirectory 
              
        }  
        Set-OutputPath
        Set-InternalPath
        Set-StopFilePath
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

        #parent of \Bin folder
        $parent_directory = (Get-Item $global:present_directory).Parent.FullName

        [string] $final_directory  = $parent_directory

        # if "UsePresentDir" is passed as a param value, then create where SQL LogScout runs
        if ($global:custom_user_directory -eq "UsePresentDir")
        {
            $final_directory  = $parent_directory
        }
        #if a custom directory is passed as a parameter to the script. Parameter validation also runs Test-Path on $CustomOutputPath
        elseif (Test-Path -Path $global:custom_user_directory)
        {
            $final_directory = $global:custom_user_directory

        }
        elseif ($global:custom_user_directory -eq "PromptForCustomDir" -And !$global:gui_mode)    
        {
            $userlogfolder = Read-Host "Would you like the logs to be collected on a non-default drive and directory?" -CustomLogMessage "Prompt CustomDir Console Input:"
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

        if ($global:gui_mode)
        {
            # Seting final diretory from GUI.
            $final_directory = $Global:txtPresentDirectory.Text
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
        [string] $new_output_folder_name = "_" + @(Get-Date -Format yyyyMMddTHHmmss) + "\"
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

function Set-StopFilePath() 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    try 
    {
        #set the stop file path to the \internal folder
        $global:stopFilePath = ($global:internal_output_folder + "logscout.stop")    
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
            $output_file_name = $global:output_folder + $server_based_file_name + "_" + @(Get-Date -Format "yyyyMMddTHHmmssffff")
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
        $error_output_file_name = $error_folder + $server_based_file_name + "_" + @(Get-Date -Format "yyyyMMddTHHmmssffff")
        
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
        if ($global:gui_mode) 
        {
            if($Global:overrideExistingCheckBox.IsChecked) 
                {$DeleteOrNew = "D"}
            else
                {$DeleteOrNew = "N"}
        }
        else
        {
            if ([string]::IsNullOrWhiteSpace($global:gDeleteExistingOrCreateNew) )
            {
            
                #if the output folder exists, ask the user if they want to delete it or create a new one. Else proceed to create one.
                if ((Test-Path -Path $global:output_folder) -eq $true)
                {
                    Write-LogInformation ""
            
                    [string]$DeleteOrNew = ""
                    Write-LogWarning "It appears that output folder '$global:output_folder' has been used before."
                    Write-LogWarning "You can choose to:"
                    Write-LogWarning " - Delete (d) the \output folder contents and recreate it"
                    Write-LogWarning " - Create a new (n) folder using '\Output_yyyyMMddTHHmmss' format. You can manually delete this folder in the future" 
        
                    while (-not(($DeleteOrNew -eq "D") -or ($DeleteOrNew -eq "N"))) 
                    {
                        $DeleteOrNew = Read-Host "Delete ('d') or create new ('n') >" -CustomLogMessage "Output folder Console input:"
                        
                        $DeleteOrNew = $DeleteOrNew.ToString().ToUpper()
                        if (-not(($DeleteOrNew -eq "D") -or ($DeleteOrNew -eq "N"))) {
                            Write-LogError ""
                            Write-LogError "Please chose [d] to delete the output folder $global:output_folder and all files inside of the folder."
                            Write-LogError "Please chose [n] to create a new folder"
                            Write-LogError ""
                        }
                    }
                }
            }
            else 
            {
                Write-LogDebug "The DeleteExistingOrCreateNew parameter is $($global:gDeleteExistingOrCreateNew)" -DebugLogLevel 2

                switch ($global:gDeleteExistingOrCreateNew) 
                {
                    "DeleteDefaultFolder"   {$DeleteOrNew = "D"}
                    "NewCustomFolder"       {$DeleteOrNew = "N"}
                    default                 {$DeleteOrNew = "N"}
                }
                
            }

        }#end of IF

        
        #Get-Childitem -Path $output_folder -Recurse | Remove-Item -Confirm -Force -Recurse  | Out-Null
        if ($DeleteOrNew -eq "D") 
        {
            #delete the existing \output folder
            if (Test-Path -Path $global:output_folder)
            {
                Remove-Item -Path $global:output_folder -Force -Recurse  | Out-Null
                Write-LogInformation "Deleting '$global:output_folder' and its contents. Please wait..."
                Write-LogWarning "Deleted '$global:output_folder' folder and its contents"
            }
        }
        elseif ($DeleteOrNew -eq "N") 
        {

            #these two calls updates the two globals for the new output and internal folders using the \Output_yyyyMMddTHHmmss format.
            
            # [string] $new_output_folder_name = "_" + @(Get-Date -Format yyyyMMddTHHmmss) + "\"
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
        Write-LogInformation "Error log path is" $global:internal_output_folder 
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
        if(($true -eq $global:gui_Result  -And $true -eq $global:varXevents.contains($script_name)) -or ($true -eq $global:tblInternalSQLFiles.Contains($script_name)) )
        {
            $input_script = "`"" + $global:internal_output_folder + $script_name +".sql" + "`""
            return $input_script
        }
        else
        {
            $input_script = "`"" + $present_directory+"\"+$script_name +".sql" + "`""
            return $input_script
        }
        
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
        $prid = $p.Id

        Write-LogDebug "Process started: name = '$pn', id ='$prid', starttime = '$($st.ToString("yyyy-MM-dd HH:mm:ss.fff"))' " -DebugLogLevel 1

        # add the process object to the array of started processes (if it has not exited already)
        if($false -eq $p.HasExited)   
        {
            [void]$global:processes.Add($p)
        }

        # this is equivalent to a return - but used in PS to send the value to the pipeline 
        return $p

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
    

}

# fucntion to collect SQL SERVERPROPERTY and cahe it in $global:SQLSERVERPROPERTYTBL 
# if globla variable is populated it will use it.

function getServerproperty() 
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    $SQLSERVERPROPERTYTBL = @{}
    [String] $query 
    
    if ($global:SQLSERVERPROPERTYTBL.Count -gt 0) {
        Write-LogDebug "SQLSERVERPROPERTYTBL cached " -DebugLogLevel 2
        return $global:SQLSERVERPROPERTYTBL
    }

    $properties = "BuildClrVersion",
                    "Collation",
                    "CollationID",
                    "ComparisonStyle",
                    "ComputerNamePhysicalNetBIOS",
                    "Edition",
                    "EditionID",
                    "EngineEdition",
                    "FilestreamConfiguredLevel",
                    "FilestreamEffectiveLevel",
                    "FilestreamShareName",
                    "HadrManagerStatus",
                    "InstanceDefaultBackupPath",
                    "InstanceDefaultDataPath",
                    "InstanceDefaultLogPath",
                    "InstanceName",
                    "IsAdvancedAnalyticsInstalled",
                    "IsBigDataCluster",
                    "IsClustered",
                    "IsExternalAuthenticationOnly",
                    "IsExternalGovernanceEnabled",
                    "IsFullTextInstalled",
                    "IsHadrEnabled",
                    "IsIntegratedSecurityOnly",
                    "IsLocalDB",
                    "IsPolyBaseInstalled",
                    "IsServerSuspendedForSnapshotBackup",
                    "IsSingleUser",
                    "IsTempDbMetadataMemoryOptimized",
                    "IsXTPSupported",
                    "LCID",
                    "LicenseType",
                    "MachineName",
                    "NumLicenses",
                    "PathSeparator",
                    "ProcessID",
                    "ProductBuild",
                    "ProductBuildType",
                    "ProductLevel",
                    "ProductMajorVersion",
                    "ProductMinorVersion",
                    "ProductUpdateLevel",
                    "ProductUpdateReference",
                    "ProductVersion",
                    "ResourceLastUpdateDateTime",
                    "ResourceVersion",
                    "ServerName",
                    "SqlCharSet",
                    "SqlCharSetName",
                    "SqlSortOrder",
                    "SqlSortOrderName",
                    "SuspendedDatabaseCount"    

    foreach ($propertyName in $properties) {
        $query += "  SELECT SERVERPROPERTY ('$propertyName') as value, cast('$propertyName' as varchar(100)) as PropertyName UNION `r`n"
    }
    $query = $query.Substring(0,$query.Length - 9)

    Write-LogDebug "Serverproperty Query : $query" -DebugLogLevel 2

    $result = execSQLQuery -SqlQuery $query
    $emptyTBL =  @{Empty=$true}

    #if no connection, return null
    if ($false -eq $result)
    {
        Write-LogDebug "Failed to connect to SQL instance (may be expected behavior)" -DebugLogLevel 2
        return $emptyTBL
    }
    else 
    {
        #We connected, but resultset is blank for some reason. Return null.
        if ($result.Tables[0].rowcount -eq 0)
        {
            Write-LogDebug "No SERVERPROPERTY returned" -DebugLogLevel 2
            return $emptyTBL
        }
    }

    foreach ($row in $result.Tables[0].Rows) {
        $SQLSERVERPROPERTYTBL.add($row.PropertyName.ToString().Trim(), $row.value)
    }
    
    $global:SQLSERVERPROPERTYTBL = $SQLSERVERPROPERTYTBL

    return $SQLSERVERPROPERTYTBL
}

function getSQLConnection ([Boolean] $SkipStatusCheck = $false, [int] $tryCount = 0)
{
    Write-LogDebug "inside " $MyInvocation.MyCommand


    try
    {

        $globalCon = $global:SQLConnection

        if ( $null -eq $globalCon) 
        {
            Write-LogDebug "SQL Connection is null, initializing now" -DebugLogLevel 2

            [System.Data.Odbc.OdbcConnection] $globalCon = New-Object System.Data.Odbc.OdbcConnection

            $conString = getSQLConnectionString -SkipStatusCheck $SkipStatusCheck -tryCount $tryCount

            if ($false -eq $conString ) 
            {
                #we failed to get proper conneciton string
                Write-LogDebug "We failed to get connection string, check pervious messages to for more details"  -DebugLogLevel 3
            
                return $false
            }

            $globalCon.ConnectionString = $conString
            
            $globalCon.Open() | Out-Null
            
            $global:SQLConnection = $globalCon
        
        } elseif (($globalCon.GetType() -eq [System.Data.Odbc.OdbcConnection]) -and ($globalCon.State -ne "Open") )
        {
            Write-LogDebug "Connection exists and is not Open, opening now" -DebugLogLevel 2
            
            $globalCon.Open() | Out-Null
        } elseif ( $globalCon.GetType() -ne [System.Data.Odbc.OdbcConnection]) 
        {

            Write-LogError "Could not create or obtain SqlConnection object  "  $globalCon.GetType()

            return $false
        }
        
        return $globalCon

    }

    catch {
        if ($PSItem.Exception.InnerException.Message.Contains("[08001]"))
        {
            Write-LogWarning "Could not connect to SQL Server "
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }
        else 
        {
            HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        }
        return $false
    }
}

function getODBCDriver ([int] $tryCount)
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    # Get the list of ODBC drivers
    $drivers = Get-OdbcDriver -Name "*SQL Server*" -Platform 32-bit 

    # Filter and sort the drivers by version
    $sortedDrivers = $drivers |
        Sort-Object {
            if ($_.Name -match 'ODBC Driver (\d+) for SQL Server') {
                [int]$matches[1]
            } elseif ($_.Name -match 'SQL Server Native Client (\d+)') {
                [int]$matches[1]
            } else {
                0
            }
        } -Descending 

    # Output the sorted drivers
    $sortedDriverNames = $sortedDrivers.Name 

    Write-LogDebug "List of ODBC Drivers on the system"
    $sortedDriverNames | ForEach-Object { Write-LogDebug "  $($_)"}

    [String] $highestDriver
    if (($sortedDriverNames.Count -ge 1) -and ( $tryCount -lt $sortedDriverNames.Count))
    {
        [String] $temp_DriverName
        if ($sortedDriverNames.Count -gt 1)
        {
            $temp_DriverName = $sortedDriverNames[$tryCount]
        } else {
            $temp_DriverName = $sortedDriverNames.ToString()
        }
        # Get the highest version driver for the number of tries
        $highestDriver = $temp_DriverName 
    } 
    else 
    {
        $highestDriver = "SQL Server"
        
    }
    Write-LogDebug "Highest ODBC driver returned ($highestDriver)"

    return $highestDriver
}

function getSQLConnectionString ([Boolean] $SkipStatusCheck = $false, [int] $tryCount = 0)
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    try 
    {
        if 
        (
            ($global:sql_instance_conn_str -eq $global:NO_INSTANCE_NAME)    -or    
            ($true -eq $global:instance_independent_collection )     -or 
            ( ("Running" -ne $global:sql_instance_service_status) -and (-$false -eq $SkipStatusCheck) )
        )
        {
            Write-LogWarning "No SQL Server instance found, instance is offline, or instance-independent collection. Not executing SQL queries."
            return $false
        }
        elseif ([String]::IsNullOrEmpty($global:sql_instance_conn_str) -eq $false)
        {
            
            $SQLInstance = $global:sql_instance_conn_str
        } 
        else 
        {
            Write-LogError "SQL Server instance name is empty. Exiting..."
            exit
        }

        [String] $ODBCDriverName = getODBCDriver -tryCount $tryCount
        [System.Data.Odbc.OdbcConnectionStringBuilder] $connectionStringBuilder =  New-Object -TypeName System.Data.Odbc.OdbcConnectionStringBuilder

        #verifying that we have recevied a value ODBC Driver name, if not we use SQL Server as default.
        if ([string]::IsNullOrEmpty($ODBCDriverName) -or $ODBCDriverName.Trim() -notmatch ".*SQL Server.*" )
        {
            
            Write-LogDebug "getODBCDriver failed to return value, we are failing back to default"
            $ODBCDriverName = "SQL Server"
        }

        $connectionStringBuilder.Driver = $ODBCDriverName.Trim()
        $connectionStringBuilder["Server"] = $SQLInstance
        $connectionStringBuilder["Database"] = "master"
        $connectionStringBuilder["Application Name"] = "SQLLogScout"

        if ("SQL Server" -ne $ODBCDriverName.Trim())
        {
            $connectionStringBuilder["Trusted_Connection"]="Yes"
            $connectionStringBuilder["Encrypt"] = "Yes"
            $connectionStringBuilder["TrustServerCertificate"] = "Yes"

        } else {

            #only for the classic SQL Server driver  use no encryption as it doesn't support it in all OS versions. But also convenient for WID connections
            $connectionStringBuilder["Integrated Security"] = "True"
            $global:is_connection_encrypted = $false

            Write-LogWarning ("*"*70)
            Write-LogWarning "*  SQL LogScout is switching to the classic SQL Server ODBC driver."  
            Write-LogWarning "*  Thus, this local connection is unencrypted to ensure it is successful"
            Write-LogWarning "*  To exit without collecting LogScout press Ctrl+C"
            Write-LogWarning ("*"*70)
            Start-Sleep 6

        }
        Write-LogDebug "Received parameter SQLInstance: `"$SQLInstance`"" -DebugLogLevel 2

        Write-LogDebug "Connection String : " $connectionStringBuilder.ConnectionString

        #default integrated security and encryption with trusted server certificate
        return $connectionStringBuilder.ConnectionString #"Driver={SQL Server};Server=$SQLInstance;Database=master;Application Name=SQLLogScout;Integrated Security=True;Encrypt=NotTrue;TrustServerCertificate=true;"
    }

    catch {
       HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
       return $false
    }        
}

function getSQLCommand([Boolean] $SkipStatusCheck)
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    try 
    {
     
        $SqlCmd = $global:SQLCommand
        
        if ($null -eq $SqlCmd) 
        {
            $SqlCmd = New-Object System.Data.Odbc.OdbcCommand
            $conn = getSQLConnection($SkipStatusCheck)

            #if we receive $false (connection failed for some reason) we try multiple times to see if we can find a working driver
            for ($i = 1; $i -lt 10 -and $false -eq $conn; $i++ ) {
                Write-LogDebug "First ODBC connection failed, trying a $($i+1) time"
                Write-LogDebug "Trying ODBC Driver :  $i"
                $conn = getSQLConnection($SkipStatusCheck) -tryCount $i
            }

            if ($false -eq $conn) {
                #failed to obtain a connection
                Write-LogDebug "Failed to get a connection object, check previous messages" -DebugLogLevel 3
                return $false
            }
            $SqlCmd.Connection = $conn
        }
        
        if ($SqlCmd.GetType() -eq [System.Data.Odbc.OdbcCommand]) 
        {
            return $SqlCmd
        }

        Write-LogDebug "Did not get a valid SQLCommand , Type : $SqlCmd.GetType() " -DebugLogLevel 2 
        
        #if type is not correct don't return it
        return $false
    }

    catch {
       HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
       return $false
    }
}

function execSQLNonQuery ($SqlQuery,[Boolean] $TestFailure = $false) 
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    return execSQLQuery -SqlQuery $SqlQuery  -Command "ExecuteNonQuery" -TestFailure $TestFailure
}

function execSQLScalar ($SqlQuery, [int] $Timeout = 30, [Boolean] $TestFailure = $false) 
{
    Write-LogDebug "inside " $MyInvocation.MyCommand

    return execSQLQuery -SqlQuery $SqlQuery  -Command "ExecuteScalar" -Timeout $Timeout -TestFailure $TestFailure
}
function saveContentToFile() 
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory, Position=0)]
        [String]$content,
        [Parameter(Mandatory, Position=1)]
        [String] $fileName
    )
    
    Write-LogDebug "inside " $MyInvocation.MyCommand

    $content | out-file $fileName | Out-Null
    return $true
}
function saveSQLQuery() 
{
[CmdletBinding()]
    param 
    (
        [Parameter(Mandatory, Position=0)]
        [String]$SqlQuery,
        [Parameter(Mandatory, Position=1)]
        [String] $fileName,
        [int] $Timeout = 30,
        [Boolean] $TestFailure = $false
    )

    Write-LogDebug "inside " $MyInvocation.MyCommand

    $DS = execSQLQuery -SqlQuery $SqlQuery -Timeout $Timeout -TestFailure $TestFailure
    
    if ($DS.GetType() -eq [System.Data.DataSet])
    {
        try {
            [String] $content =""
            foreach ($row in $DS.Tables[0].Rows)
            {
                $content = $content + $row[0]
            }
            Write-LogDebug "Saving query to file $fileName"

            
            $content | out-file $fileName | Out-Null
            return $true
        } catch 
        {
            Write-LogError "Could not save query to file $fileName "
    
            $mycommand = $MyInvocation.MyCommand
            $error_msg = $PSItem.Exception.InnerException.Message
            Write-LogError "$mycommand Function failed with error:  $error_msg"
    
            return $false
        }
        

    } else {
        Write-LogDebug "Query failed, errors mabye in execSQLQuery messages " -DebugLogLevel 3
        return $false
    }
    
} #saveSQLQuery -SqlQuery -fileName

#execSQLQery connect to SQL Server using System.data objects
#The simplest way to use it is 

<#
    .SYNOPSIS
        Returns false if query fails and Dataset if it succeeds 

    .DESCRIPTION
        Returns false if query fails and Dataset if it succeeds 
        Can be used to perofrm ExecNonQuery as well

    .EXAMPLE
        execQuery -SqlQuery "SELECT 1 "
#>

function execSQLQuery()
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory, Position=0)]
        [String]$SqlQuery,
        [Parameter(Mandatory=$false)]
        [Boolean]$SkipStatusCheck = $false,
        [Parameter(Mandatory=$false)]
        [Boolean]$TestFailure = $false,
        [String]$Command = "SelectCommand",
        [System.Data.CommandBehavior] $CommandBehavior,
        [int] $Timeout = 30
    )
    
     Write-LogDebug "inside " $MyInvocation.MyCommand
        
     #if in Teting Mode return false immediately
     if ($TestFailure) { return $false }
     
     $permittedCommands = "SelectCommand", "ExecuteNonQuery", "ExecuteReader", "ExecuteScalar"
     
     if (-not( $permittedCommands -contains $command) ) 
     {
         Write-LogWarning "Permitted commands for execQuery are : " $permittedCommands.ToString
         exit
     }

    Write-LogDebug "Creating SqlClient objects and setting parameters" -DebugLogLevel 2
        
    $SqlCmd = getSQLCommand($SkipStatusCheck)
    
    if ($false -eq $SqlCmd) 
    {
        return $false
    }

    $SqlCmd.CommandText = $SqlQuery
    $SqlCmd.CommandTimeout = $Timeout
    
    $SqlAdapter = New-Object System.Data.Odbc.OdbcDataAdapter
    $DataSetResult = New-Object System.Data.DataSet

    Write-LogDebug "About to call the required command : $Command " -DebugLogLevel 2
    try {
        
        if ($Command -eq "SelectCommand") 
        {
            $SqlAdapter.SelectCommand = $SqlCmd
            $SqlAdapter.Fill($DataSetResult) | Out-Null #fill method returns rowcount, Out-Null prevents the number from being printed in console
            return $DataSetResult
        } elseif ($Command -eq "ExecuteNonQuery") 
        {           
            $SqlCmd.ExecuteNonQuery() | Out-Null
            return $true;

        } elseif ($command -eq "ExecuteScalar") 
        {
            return $SqlCmd.ExecuteScalar()
        } 

    }
    catch 
    {
        $ds = $SqlCmd.Connection.DataSource
        Write-LogError "Could not connect to SQL Server instance '$ds' to perform query."
        $con = $SqlCmd.Connection.ConnectionString
        Write-LogDebug "SQL Could not connect , SQL ConnectionString : $con"

        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem

        # we can't connect to SQL, probably whole capture will fail, so we just abort here
        return $false
    }
}

function GetSQLCmdPath() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try 
    {
        [string] $sqlcmd_executable = ""

        # use the global sqlcmdpath variable if it isn't empty. The Test-Path validation will be done just once for perf reasons. 
        # If empty, populate by finding the path to sqlcmd.exe  with highest version
        if (([string]::IsNullOrWhiteSpace($global:sqlcmdPath) -eq $false) -and ($global:sqlcmdPath -match "sqlcmd.exe"))
        {
            $sqlcmd_executable = $global:sqlcmdPath
        }
        else
        {
            #if no  path to sqlcmd, find the highest version of sqlcmd.exe on the system 
            # first start by trying the common case C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\... 
            $sqlcmd_fullpath =  (Get-ChildItem "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\*\Tools\Binn\SQLCMD.EXE" -ErrorAction SilentlyContinue|
                                    Sort-Object -Property FullName -Descending | 
                                    Select-Object -First 1 -Property FullName).FullName
            
            #if path is valid, assign to the global variable and use it
            if (([string]::IsNullOrWhiteSpace($sqlcmd_fullpath) -eq $false) -and (Test-Path -Path $sqlcmd_fullpath))
            {
                $sqlcmd_executable = $global:sqlcmdPath = $sqlcmd_fullpath
                Write-LogDebug "SQLCMD path found in common location and assigned to global variable is '$global:sqlcmdPath'" -DebugLogLevel 2
            }
            else 
            {
                #if no path found thus far, second choice is to get the path from the registry and append the executable name

                # Get the ODBCToolsPath values from the registry
                $paths = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Microsoft SQL Server\*\Tools\ClientSetup\" -Name "ODBCToolsPath" -ErrorAction SilentlyContinue).ODBCToolsPath

                # Append "sqlcmd.exe" to each path
                $paths = $paths | ForEach-Object { $_ + "sqlcmd.exe" }

                # Extract the version numbers and sort the paths based on these numbers
                $sortedPaths = $paths | Sort-Object {
                    # Extract the version number using a regular expression and sort it
                    if ($_ -match '\\ODBC\\(\d+)\\') 
                    {
                        [int]$matches[1]
                    } 
                    else {0}
                } -Descending

                # Get the one path with the highest version number
                $sqlcmd_path_reg = $sortedPaths | Select-Object -First 1


                #if path is valid, assign to global variable
                if (([string]::IsNullOrWhiteSpace($sqlcmd_path_reg) -eq $false) -and (Test-Path -Path $sqlcmd_path_reg))
                {
                    $sqlcmd_executable = $global:sqlcmdPath = $sqlcmd_path_reg
                    Write-LogDebug "SQLCMD.EXE path discovered in registry and assigned to global variable is '$global:sqlcmdPath'" -DebugLogLevel 2
                }
                else 
                {
                    #if no path found thus far, third choice is to look in the Environment variable PATH and pick one if found (last one seems the highest version typically)
                    $sqlcmd_path_env = ((Get-Command -Name "sqlcmd.exe" -CommandType Application -ErrorAction SilentlyContinue) | Select-Object -Last 1)
               
                    #if path is valid, assign to global variable and local return variable
                    # else log an error and continue without T-SQL collections
                    if (($sqlcmd_path_env).Name -match "sqlcmd")
                    {
                        
                        if ( ([string]::IsNullOrWhiteSpace(($sqlcmd_path_env.Source)) -eq $false) -and (Test-Path -Path ($sqlcmd_path_env.Source) ))
                        {
                            $sqlcmd_executable = $global:sqlcmdPath  = $sqlcmd_path_env.Source
                             Write-LogDebug "SQLCMD.EXE path discovered in environment variable PATH and assigned to global variable is '$global:sqlcmdPath'" -DebugLogLevel 2

                        }
                        # in older version like SQL 2012, the registry key ODBCToolsPath is not present AND the Get-Command.Source property is not populated, so hard-codiing the sqlcmd.exe directly
                        else
                        {
                            $sqlcmd_executable = "sqlcmd.exe"
                            Write-LogDebug  "SQLCMD.EXE discovered in environment variable PATH, but it's an older version so assigned executable directly: '$sqlcmd_executable'" -DebugLogLevel 2
                        }

                    }
                    else
                    {
                        $sqlcmd_executable = $null
                        Write-LogError "SQLCMD.EXE not found. Continuing without T-SQL script execution."
                        Write-LogInformation "To enable T-SQL collections, install SQLCMD (ODBC) from your installation media or download from Microsoft."
                    }
                    
                }
            }
        }
        
        return $sqlcmd_executable
            
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
    
}


function Start-SQLCmdProcess([string]$collector_name, [string]$input_script_name, [bool]$is_query=$false, [string]$query_text, [bool]$has_output_results=$true, [bool]$wait_sync=$false, [string]$server = $global:sql_instance_conn_str, [string]$setsqlcmddisplaywidth)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    # if query is empty, then script should be populated
    # if query is populated script should be ::Empty


    try 
    {
        
        if ($true -eq [string]::IsNullOrWhiteSpace($collector_name))
        {
            $collector_name = "blank_collector_name"
        }

        
        Write-LogInformation "Executing Collector: $collector_name"

        #get the path to the input script
        $input_script = BuildInputScript $global:present_directory $input_script_name 

        #get the path to sqlcmd.exe
        $executable = GetSQLCmdPath

        if ([string]::IsNullOrWhiteSpace($executable))
        {
            #if we can't find sqlcmd.exe, we can't execute the script so just return
            return
        }

        #command arguments for sqlcmd; server connection, trusted connection, Hostname, wide output, and encryption negotiation
        $argument_list = "-S" + $server + " -E -Hsqllogscout -w8000" 
        
        #if we connected with unencrypted connection earlier with the SQL Server driver, remove -C -N from the command line
        #otherwise, default to using encrypted connection with the ODBC driver
        if ($global:is_connection_encrypted -eq $true)
        {
            $argument_list += " -C -N"
        }
        

        #if secondary replica has read-intent, we add -KReadOnly to avoid failures on those secondaries
        if ($global:is_secondary_read_intent_only -eq $true)
        {
            $argument_list += " -KReadOnly"
        }

        #if query is passed, use the -Q parameter
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

        #Depending on the script executed, we may need to increase the result length. Logically we should only care about this parameter if we are writing an output file.
        
        #If $setsqlcmddisplaywidth is passed to Start-SQLCmdProcess explicitly, then use that explicit
        if (([string]::IsNullOrEmpty($setsqlcmddisplaywidth) -eq $false) -and ($has_output_results -eq $true))
        {
            $argument_list += " -y" + $setsqlcmddisplaywidth
        }

        #If $setsqlcmddisplaywidth is NOT passed to Start-SQLCmdProcess explicitly, then pass it by default with 512 hardcoded value.
        if (([string]::IsNullOrEmpty($setsqlcmddisplaywidth) -eq $true) -and ($has_output_results -eq $true))
        {
            $argument_list += " -y" + "512"
        }


        
        $partial_error_output_file_name = CreatePartialErrorOutputFilename($server)
    
        Write-LogDebug "The partial_error_output_file_name is $partial_error_output_file_name" -DebugLogLevel 3
        Write-LogDebug "The partial_output_file_name is $partial_output_file_name" -DebugLogLevel 3

        $error_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stderr") -needExtraQuotes $false 
        $stdoutput_file = BuildFinalErrorFile -partial_error_output_file_name $partial_error_output_file_name -collector_name ($collector_name+"_stdout") -needExtraQuotes $false 

        #start the process
        StartNewProcess -FilePath $executable -ArgumentList $argument_list -WindowStyle Hidden -RedirectStandardError $error_file -RedirectStandardOutput $stdoutput_file -Wait $wait_sync | Out-Null
        
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

#======================================== END of Process management section

#check if HADR is enabled from serverproperty
function isHADREnabled() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    $propertiesList = $global:SQLSERVERPROPERTYTBL
    
    if (!$propertiesList) {
        #We didn't receive server properteis     
        Write-LogError " getServerproperty returned no results " 
        return $false
    }
    
    $isHadrEnabled = $propertiesList."IsHadrEnabled"

    if ($isHadrEnabled -eq "1") {
        Write-LogDebug "HADR /AG is enabled on this system" -DebugLogLevel 2 
        return $True
    }
    
    return $false

}
function IsSqlFCI() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    $propertiesList = $global:SQLSERVERPROPERTYTBL
    
    if (!$propertiesList) {
        #We didn't receive server properteis     
        Write-LogError " getServerproperty returned no results " 
        return $false
    }
    
    $isSqlFci = $propertiesList."IsClustered"

    if ($isSqlFci -eq "1") {
        Write-LogDebug "SQL Server is FCI on this system" -DebugLogLevel 2 
        return $true
    }
    
    return $false

}

#check if cluster - based on cluster service status and cluster registry key
function IsClustered()
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    $ret = $false
    $error_msg = ""
    
    
    try 
    { 
        #optimization with $is_clustered global to avoid querying the cluster service status and registry key 
        #if we already know this is a cluster. This function is called in multiple spots so we need the optimization
    
        if ($global:is_clustered -eq 2) #if global set to 2 (default), we need to check whether it is a cluster and set accordingly
        {
            $clusServiceisRunning = $false
            $clusRegKeyExists = $false
            $ClusterServiceKey="HKLM:\Cluster"

            # Check if cluster service is running
            if ((Get-Service |  Where-Object  {$_.Displayname -match "Cluster Service"}).Status -eq "Running") 
            {
                $clusServiceisRunning =  $true
                Write-LogDebug "Cluster service is running: $clusServiceisRunning  " -DebugLogLevel 2   
            }
            
            # Check if cluster registry key exists
            if (Test-Path -Path $ClusterServiceKey) 
            { 
                $clusRegKeyExists  = $true
                Write-LogDebug "Cluster key $ClusterServiceKey exists: $clusRegKeyExists " -DebugLogLevel 2
            }

            #if both conditions are true, then this is a cluster
            if (($clusRegKeyExists -eq $true) -and ($clusServiceisRunning -eq $true ))
            {
                $global:is_clustered = 1
            }
            else #not a cluster
            {
                $global:is_clustered = 0
            }
        }

        # now that we have the global variable set, we can return cluster status
        if ($global:is_clustered -eq 1)
        {
            Write-LogDebug "This is a Windows Cluster for sure!" -DebugLogLevel 2
            return $true
        }
        elseif ($global:is_clustered -eq 0) 
        {
            Write-LogDebug "This is Not a Windows Cluster!" -DebugLogLevel 2
            return $false
        }
        else
        {
            Write-LogDebug "If we're here, there's a problem. Could not determine if this is a Windows Cluster!" -DebugLogLevel 2
            return $false
        }

    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

    return $ret
}

function IsFullTextInstalled() 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    $propertiesList = $global:SQLSERVERPROPERTYTBL
    
    if (!$propertiesList) {
        #We didn't receive server properteis     
        Write-LogError " getServerproperty returned no results " 
        return $false
    }
    
    $IsFullTextInstalled = $propertiesList."IsFullTextInstalled"

    if ($IsFullTextInstalled -eq "1") {
        Write-LogDebug "FullText is installed on this SQL instance" -DebugLogLevel 2 
        return $True
    }
    
    return $false

}

function Get-InstanceNameObject([string]$NetnamePlusInstance)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    $host_name = $global:host_name

    <#  Create an object to return the instance name and type
        for Type property in the PSCustomObject:
        Type = 0 - starting value/null
        Type = 1 - for named instance 
        Type = 2 - default instance with VNN server name
        Type = 3 - default instance with host name
    #>

    $InstNameObj = [PSCustomObject]@{
       InstanceName = ""
       Type  = $global:SQLInstanceType["StartingValue"]}


    try 
    {
        # if this is a named instance, we need to extract the instance name
        if ($NetnamePlusInstance -like '*\*')
        {
            #extract the instance name and hostname from the NetnamePlusInstance to compare them
            $selectedSqlInstance  = $NetnamePlusInstance.Substring($NetnamePlusInstance.IndexOf("\") + 1)
            $servername =   $NetnamePlusInstance.Substring(0,$NetnamePlusInstance.IndexOf("\"))

            #if the servername is not the same as the hostname, we log a message - likely FCI
            if (($servername -ne $host_name) )
            {
                Write-LogDebug "Using a '$servername' instead of the hostname $host_name" -DebugLogLevel 2
            }


            #if the named instance name is the same as the hostname, we log a message as a warning (rare but possible) 
            if ($selectedSqlInstance -eq $servername)
            {
                Write-LogDebug "Server name and instance name are the same on this system '$servername\$selectedSqlInstance'" -DebugLogLevel 3
            }

            #return object - for named instance
            $InstNameObj.InstanceName = $selectedSqlInstance
            $InstNameObj.Type  = $global:SQLInstanceType["NamedInstance"]

        }
        else 
        {
            #if this is a default instance, we return a VNN for default FCI case and MSSQLSERVER for a non-FCI default instance 
            if ($NetnamePlusInstance -ne $host_name)
            {
                #default instance likely using a VNN
                $selectedSqlInstance = $NetnamePlusInstance

                #set the return object values
                $InstNameObj.InstanceName = $selectedSqlInstance
                $InstNameObj.Type  = $global:SQLInstanceType["DefaultInstanceVNN"]
            }
            else
            {
                $selectedSqlInstance = "MSSQLSERVER"

                #default instance, same as host
                $InstNameObj.InstanceName = $selectedSqlInstance
                $InstNameObj.Type  = $global:SQLInstanceType["DefaultInstanceHostName"]
            }
        }

        Write-LogDebug "InstNameObject.InstanceName = $($InstNameObj.InstanceName), InstNameObj.Type = $($InstNameObj.Type)" -DebugLogLevel 2 
         
        return $InstNameObj
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }

}

# use this to look up Windows version
function GetWindowsVersion
{
   #Write-LogDebug "Inside" $MyInvocation.MyCommand

   try {
       $winver = [Environment]::OSVersion.Version.Major  
   }
   catch
   {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
   }
   
   
   #Write-Debug "Windows version is: $winver" -DebugLogLevel 3

   return $winver;
}



#used in Catch blocks throughout
function HandleCatchBlock ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec, [bool]$exit_logscout = $false)
{
    #This import is needed here to prevent errors that can happen during ctrl-c
    Import-Module .\LoggingFacility.psm1
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

Function GetRegistryKeys
{
<#
    .SYNOPSIS
        This function is the Powershell equivalent of reg.exe        
    .DESCRIPTION
        This function writes the registry extract to an output file. It takes three parameters:
        $RegPath - This is a mandatory input paramter that accepts the registry key value
        $RegOutputFilename - This is a mandatory input parameter that takes the output file name with path to write the registry information into
        $Recurse - This is a mandatory boolean input parameter that indicates whether to recurse the given registry key to include subkeys.

    .EXAMPLE
        GetRegistryKeys -RegPath "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer" -RegOutputFilename "C:\temp\RegistryKeys\HKLM_CV_Installer_PS.txt" -Recurse $true
        Reg.exe equivalent
        reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer" /s > C:\temp\RegistryKeys\HKLM_CV_Installer_Reg.txt

        GetRegistryKeys -RegPath "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer" -RegOutputFilename "C:\temp\RegistryKeys\HKLM_CV_Installer_PS.txt"
        Reg.exe equivalent
        reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer" > C:\temp\RegistryKeys\HKLM_CV_Installer_Reg.txt
#>
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$RegPath, #Registry Key Location
        [string]$RegOutputFilename, #Output file name
        [bool]$Recurse = $true #Get the nested subkeys for the given registry key if $recurse = true
    )
    
    try
    {
        # String used to hold the output buffer before writing to file. Introduced for performance so that disk writes can be reduced. 
        [System.Text.StringBuilder]$str_InstallerRegistryKeys = New-Object -TypeName System.Text.StringBuilder

        #Gets the registry key and only the properties of the registry keys
        Get-Item -Path  $RegPath | Out-File  -FilePath $RegOutputFilename -Encoding utf8

        #Get all nested subkeys of the given registry key and assosicated properties if $recurse = true. Only gets the first level of nested keys if $recurse = false
        if ($Recurse -eq $true)
        {
            $Keys = Get-ChildItem -recurse $RegPath
        }
        else
        {
            $Keys = Get-ChildItem $RegPath
        }
        
        # This counter is incremented with every foreach loop. Once the counter evaluates to 0 with mod 50, the flush to the output file on disk is performed from the string str_InstallerRegistryKeys that holds the contents in memory. The value of 50 was chosen imprecisely to batch entries in memory before flushing to improve performance.
        [bigint]$FlushToDisk = 0

        # This variable is used to hold the PowerShell Major version for calling the appropriate cmdlet that is compatible with the PS Version
        [int]$CurrentPSMajorVer = ($PSVersionTable.PSVersion).Major


        # for each nested key perform an iteration to get all the properties for writing to the output file
        foreach ($k in $keys)
        {
            if ($null -eq $k)
            {
                continue
            }
       
            # Appends the key's information to in-memory stringbuilder string str_InstallerRegistryKeys
            [void]$str_InstallerRegistryKeys.Append("`n" + $k.Name.tostring() + "`n" + "`n")

  
            #When the FlushToDisk counter evalues to 0 with modulo 50, flush the contents ofthe string to the output file on disk
            if ($FlushToDisk % 50 -eq 0)
            {
                Add-Content -Path ($regoutputfilename) -Value ($str_InstallerRegistryKeys.ToString())
                $str_InstallerRegistryKeys = ""
            }

            # Get all properties of the given registry key
            $props = (Get-Item -Path $k.pspath).property

            # Loop through the properties, and for each property , write the details into the stringbuilder in memory. 
            foreach ($p in $props) 
            {
                # Fetches the value of the property ; Get-ItemPropertyValue cmdlet only works with PS Major Version 5 and above. For PS 4 and below, we need to use a workaround.
                # Fetches the value of the property ; Get-ItemPropertyValue cmdlet only works with PS Major Version 5 and above. For PS 4 and below, we need to use a workaround.
                $v = ""
                if ($CurrentPSMajorVer -lt 5)
                {
                    $v = $((Get-ItemProperty -Path $k.pspath).$p) 
                }
                else
                {
                    $v = Get-ItemPropertyvalue -Path $k.pspath -name  $p 
                }
        
                # Fethes the type of property. For default property that has a non-null value, GetValueKind has a bug due to which it cannot fetch the type. This check is to 
                # define type as null if the property is default. 
                try
                {           
                     if ( ($p -ne "(default)") -or ( ( ( $p -eq "(default)" ) -and ($null -eq $v) ) ) )
                     {
                        $t = $k.GetValueKind($p)
                     }
                    else 
                    {
                        $t = ""
                    }
                }
                catch
                {
                    HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
                }
                
                # Reg.exe displays the Windows API registry data type, whereas PowerShell displays the data type in a different format. This switch statement converts the 
                # PS data type to the Windows API registry data type using the table on this MS Docs article as reference: https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registryvaluekind?view=net-7.0
                switch($t)
                {
                    "DWord" {$t = "REG_DWORD"}
                    "String" {$t = "REG_SZ"}
                    "ExpandString" {$t = "REG_EXPAND_SZ"}
                    "Binary" {$t = "REG_BINARY"}
                    "QWord" {$t = "REG_QWORD"}
                    "MultiString" {$t = "REG_MULTI_SZ"}
                }
                
                # This if statement formats the REG_DWORD and REG_BINARY to the right values
                if ($t -eq "REG_DWORD")
                {
                    [void]$str_InstallerRegistryKeys.Append("`t$p`t$t`t" + '0x'+ '{0:X}' -f $v + " ($v)" + "`n")
                }
                elseif ($t -eq "REG_BINARY")
                {
                    $hexv = ([System.BitConverter]::ToString([byte[]]$v)).Replace('-','')
                    [void]$str_InstallerRegistryKeys.Append("`t$p`t$t`t$hexv"  + "`n")
                }
                else
                {
                    [void]$str_InstallerRegistryKeys.Append("`t$p`t$t`t$v"  + "`n" )
                }

                # If FLushToDisk value evaluates to 0 when modul0 50 is performed, the contents in memory are flushed to the output file on disk. 
                if ($FlushToDisk % 50 -eq 0)
                {
                    Add-Content -Path ($RegOutputFilename) -Value ($str_InstallerRegistryKeys.ToString())
                    $str_InstallerRegistryKeys = ""
                }
        
                $FlushToDisk = $FlushToDisk + 1
        
            } # End of property loop
       
        $FlushToDisk = $FlushToDisk + 1
        } # End of key loop
        
        # Flush any remaining contents in stringbuilder to disk.
        Add-Content -Path ($RegOutputFilename) -Value ($str_InstallerRegistryKeys.ToString())
        $str_InstallerRegistryKeys = ""
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
} #End of GetRegistryKeys

#Test connection functionality to see if SQL accessible.
function Test-SQLConnection ([string]$SQLServerName,[string]$SqlQuery)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    if ([string]::IsNullOrEmpty($SqlQuery))
    {
        $Sqlquery = "SELECT @@SERVERNAME"
    }
    
    $DataSetPermissions = execSQLQuery -SqlQuery $Sqlquery -SkipStatusCheck $true #-TestFailure $true
    
    if ($DataSetPermissions -eq $false) {
        return $false;
    } else {
        return $true;
    }
}


#Call this function to check if your version is supported checkSQLVersion -VersionsList @("SQL2022RTMCU8", "SQL2019RTMCU23")
#The function checks if current vesion is higher than versionsList, if you want it lowerthan, then user -LowerThan:$true
function checkSQLVersion ([String[]] $VersionsList, [Boolean]$LowerThan = $false, [Long] $SQLVersion = -1)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    #in case we decide to pass the version , for testing or any other reason
    if ($SQLVersion -eq -1) {
        $currentSQLVersion =  $global:SQLVERSION 
    } else {
        $currentSQLVersion = $SQLVersion
    }

    [long[]] $versions = @()
    foreach ($ver in $VersionsList) 
    {
        $versions += $global:SqlServerVersionsTbl[$ver]
    }

    #upper limit is used to up the version to its ceiling
    $upperLimit = 999999999
    
    #count is needed to check if we are on the upper limit of the array
    [int] $count = 0

    $modulusFactor = 1000000000

    #sorting is important to make sure we compare the upper limits first and exit early
    if (-Not $LowerThan) 
    {
        $sortedVersions = $versions  | Sort-Object -Descending
    } else {
        $sortedVersions = $versions  | Sort-Object 
    }

    foreach ($v in $sortedVersions)
    {
        $vLower = $v - ($v % $modulusFactor)
        
        #if we are on the head of the array, make the limit significantly high and low to encompass all above upper ad below lower.
        if ($count -eq 0 )
        {
            $vUpper = $upperLimit * $modulusFactor * 1000
            $vLower = 0
        } else {
            $vUpper = $vLower + $upperLimit
        }

        #This bit identifies the upper/lower limits to compare to, to avoid having copy of the same if statement
        if (-Not $LowerThan) {
            $gtBaseValue = $v
            $leBaseValue = $vUpper
        } else {
            $gtBaseValue = $vLower
            $leBaseValue = $v-1 #-1 needed to make sure we are less than Base not equl.
        }
        Write-LogDebug "current $currentSQLVersion gt $gtBaseValue lt $leBaseValue" -DebugLogLevel 3
        if ($currentSQLVersion -ge $gtBaseValue -and $currentSQLVersion -le $leBaseValue )
        {
            Write-LogDebug "Version $currentSQLVersion is supported in $v" -DebugLogLevel 3
            return $true
        }
        $count ++
    }

    Write-LogDebug "Version $currentSQLVersion is not supported" -DebugLogLevel 3
    #we reach here, we are unsupported
    return $false
}

function GetLogPathFromReg([string]$server, [string]$logType) 
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    try
    {
        $vInstance = ""
        $vInstanceType = ""
        $vRegInst = ""
        $RegPathParams = ""
        $retLogPath = ""
        $regInstNames = "HKLM:SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"


        # extract the instance name from the server name
        $instByPortObj = GetSQLInstanceNameByPortNo($server)
        Write-LogDebug "Result from GetSQLInstanceNameByPortNo is '$instByPortObj'" -DebugLogLevel 2
        
        if (-not ([String]::IsNullOrWhiteSpace($instByPortObj.InstanceName)))
        {
            $vInstance = $instByPortObj.InstanceName
            $vInstanceType = $instByPortObj.Type
        }
        else 
        {   
            # get the instance name from the server name (registry stores MSSQLSERVER if default instance)
            $vInstanceObj = Get-InstanceNameObject($server)
            $vInstance = $vInstanceObj.InstanceName
            $vInstanceType = $vInstanceObj.Type
        }
        
        # if the instance name is default instance on an FCI, we need to set it to the MSSQLSERVER because the registry stores it that way
        if ($vInstanceType -eq $global:SQLInstanceType["DefaultInstanceVNN"])
        {
            $vInstance = "MSSQLSERVER"
        }

        Write-LogDebug "Instance name for the purpose of reg key lookup is '$vInstance'" -DebugLogLevel 2

        # make sure a Instance Names is a valid registry key (could be missing if SQL Server is not installed or registry is corrupt)
        if (Test-Path -Path $regInstNames)
        {
            $vRegInst = (Get-ItemProperty -Path $regInstNames).$vInstance
        }
        else
        {
            Write-LogDebug "Registry regInstNames='$regInstNames' is not valid or doesn't exist" -DebugLogLevel 2
            return $false
        }
        

        # validate the registry value with the instance name appended to the end
        # for example, HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL\SQL2017
        # special case for WID
        if (([String]::IsNullOrWhiteSpace($vRegInst) -eq $true) -and ($vInstance -ne "MSWIN8.SQLWID"))
        {
            Write-LogDebug "Registry value vRegInst is null or empty. Not getting files from Log directory" -DebugLogLevel 2
            return $false
        }
        else
        {
            #special case for WID
            # if the server name (alias) to connect to is "MSWIN8.SQLWID", then hard-code the $vRegInst to "MSWIN8.SQLWID"
            if ($vInstance -eq "MSWIN8.SQLWID")
            {
                $vRegInst = "MSWIN8.SQLWID"
                Write-LogDebug "It appears this is WID, assigning vRegInst to '$vRegInst'" -DebugLogLevel 2
            }
        
            # get the SQL Server registry key + instance name
            $RegPathInstance = "HKLM:SOFTWARE\Microsoft\Microsoft SQL Server\" + $vRegInst 


            # go after the startup params registry key 
            $RegPathParams = $RegPathInstance + "\MSSQLSERVER\Parameters"

            if (Test-Path -Path $RegPathParams)
            {
                Write-LogDebug "Registry RegPathParams='$RegPathParams' is valid. Getting SQLArg keys" -DebugLogLevel 2

                # Get all the SQLArg keys
                $keys = Get-ItemProperty -Path $RegPathParams | Select-Object -Property SQLArg*

                # Initialize the errorLogPath and data path variables 
                $errorLogPath = $null
                $DataFilesPath = $null

                # Loop through the keys to find the one containing "-e"
                foreach ($key in $keys.PSObject.Properties) 
                {
                    #find the error log path and store it in the errorLogPath variable
                    if ($key.Value -like "-e*") 
                    {
                        $errorLogPath = $key.Value
                        
                    }

                    #find the data files path and store it in the DataFilesPath variable
                    if ($key.Value -like "-d*") 
                    {
                        $DataFilesPath = $key.Value
                    }

                }

                Write-LogDebug "Registry - Error log path: '$errorLogPath'. Data files path found: '$DataFilesPath'" -DebugLogLevel 3

                # validate key to get the path to the ERRORLOG and strip the -e from the beginning of the string
                if ([string]::IsNullOrWhiteSpace($errorLogPath) -eq $false) 
                {
                    Write-LogDebug "Error log path found: $errorLogPath" -DebugLogLevel 3

                    # strip the -e from the beginning of the string
                    $errorLogPath = $errorLogPath -replace "^-e", ""
                } 
                else 
                {
                    Write-LogDebug "No error log path found in the registry with '-e'. How does SQL Server even start?" -DebugLogLevel 3
                    return $false
                }


                #validate key to the data files path and strip the -d from the beginning of the string
                if ([string]::IsNullOrWhiteSpace($DataFilesPath) -eq $false) 
                {
                    Write-LogDebug "Data files path found: $DataFilesPath" -DebugLogLevel 3

                    # strip the -d from the beginning of the string
                    $DataFilesPath = $DataFilesPath -replace "^-d", ""
                } 
                else 
                {
                    Write-LogDebug "No data files path found in the registry with '-d'. How does SQL Server even start?" -DebugLogLevel 3
                    return $false
                }

            }
            else
            {
                Write-LogDebug "Registry RegPathParams='$RegPathParams' is not valid or doesn't exist" -DebugLogLevel 2
                return $false
            }
            

            switch ($logType)
            {
                "ERRORLOG"
                {
                    # just return the full path with log file name
                    # the file name will be extracted by the caller

                    $retLogPath = $errorLogPath

                }
                "FDLAUNCHERRORLOG"
                {
                    # strip the master.mdf from the end of the string and then the \DATA (or whatever name) folder from the end of the string
                    $retLogPath = $DataFilesPath | Split-Path -Parent | Split-Path -Parent
                    $retLogPath = $retLogPath + "\Log\"
                }
                {($_ -eq "LOG") -or ($_ -eq "POLYBASELOG") -or ($_ -eq "SQLFTLOG")}
                {

                    # strip the word ERRORLOG (or whatever name is stored) from the end of the string
                    $retLogPath = Split-Path $errorLogPath -Parent

                    if ($logType -eq "POLYBASELOG") 
                    {
                        # append the PolyBase folder name to the end of the path
                        $retLogPath = $retLogPath + "\PolyBase\"
                    }
                }
                "DUMPLOG"
                {
                    # go after the dump configured registry key
                    # HKLM:SOFTWARE\Microsoft\Microsoft SQL Server\vRegInst\CPE
                    $vRegDmpPath = $RegPathInstance + "\CPE"
                
                    if (Test-Path -Path $vRegDmpPath)
                    {
                        # strip the -e from the beginning of the string
                        $retLogPath = (Get-ItemProperty -Path $vRegDmpPath).ErrorDumpDir
                    }
                    else
                    {
                        # if the \CPE reg key doesn't exist, then memory dumps are stored in the \LOG folder in SQL Server
                        Write-LogDebug "Registry RegDmpPath='$vRegDmpPath' is not valid or doesn't exist. Defaulting to \LOG folder" -DebugLogLevel 2
                        
                        # default to the \LOG folder by removing the ERORLOG file name from the path
                        $retLogPath = Split-Path $errorLogPath -Parent
                    }
                }
                Default
                {
                    Write-LogDebug "Invalid logType='$logType' passed to GetLogPathFromReg()" -DebugLogLevel 2
                    return $false
                }
            }
        }

        # make sure the path to the log directory is valid
        if (Test-Path -Path $retLogPath)
        {
            Write-LogDebug "Log path is $retLogPath" -DebugLogLevel 2
        }
        else
        {
            if ($logType -ne "POLYBASELOG")
            {
                Write-LogWarning "The directory $retLogPath is not accessible to collect logs. Check the disk is mounted and the folder is valid. Continuing with other collectors."
            }
            #Give user time to read the prompt.
            Start-Sleep -Seconds 4

            Write-LogDebug "Log path '$retLogPath' is not valid or doesn't exist" -DebugLogLevel 2
            return $false
        }

        # return the path to directory pulled from registry
        return $retLogPath
        
    }
    catch 
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}

function ParseRelativeTime ([string]$relativeTime, [datetime]$baseDateTime)
{
    Write-LogDebug "inside" $MyInvocation.MyCommand
    
    try 
    {
        #declare a new datetime variable and set it to min value (can't be null)
        [datetime] $formatted_time = [DateTime]::MinValue

        # first remove the + sign
        $relativeTime  = $relativeTime.TrimStart("+") 
    
        # split the string by :
        $time_parts = $relativeTime.Split(":") 

        # assign the each part to hours, minutes and seconds vars
        $hours = $time_parts[0] 
        $minutes = $time_parts[1]
        $seconds = $time_parts[2] 


        #create a new timespan object
        $timespan = New-TimeSpan -Hours $hours -Minutes $minutes -Seconds $seconds 

        #add the TimeSpan to the current date and time
        if($baseDateTime -ne $null)
        {
            # this is the normal case. add the timespan from relative time to the base datetime
            $formatted_time = $baseDateTime.Add($timespan) 
        }
        else 
        {
            # this is last resort in case null time is passed as a parm -not presice but better than failing
            $baseDateTime = (Get-Date).Add($timespan)
        }
        


        return $formatted_time

    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return
    }
}

function GetTotalRAMSize() 
{
    try
    {
        Write-LogDebug "inside" $MyInvocation.MyCommand

        # get the total physical memory in GB
        $TotalRAM = (Get-CimInstance -ClassName CIM_ComputerSystem).TotalPhysicalMemory / 1GB
        Write-LogDebug "Total RAM: $($TotalRAM.ToString("F2")) GB" -DebugLogLevel 2
        return $TotalRAM
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return 0
    }
}

function GetCoutLogicalCPUs() 
{
    try
    {
        Write-LogDebug "inside" $MyInvocation.MyCommand

        # get the count of logical CPUs
        $NumLogicalCPUs = (Get-CimInstance -ClassName Win32_Processor | Select-Object -Property NumberOfLogicalProcessors).NumberOfLogicalProcessors
        Write-LogDebug "Number of logical CPUs: $NumLogicalCPUs" -DebugLogLevel 2
        return $NumLogicalCPUs 
    }
    catch
    {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return 0
    }
}

function GetComputerPlatform 
{
    Write-LogDebug "inside" $MyInvocation.MyCommand

    try {
        # Determine if the OS is 64-bit
        $is64BitOS = [System.Environment]::Is64BitOperatingSystem

        # Get the processor architecture from the environment variable
        $processorArchitecture = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "PROCESSOR_ARCHITECTURE").PROCESSOR_ARCHITECTURE

        # Map the processor architecture to a human-readable platform
        switch ($processorArchitecture) {
            "AMD64" {
                if ($is64BitOS) {
                    return "x64"  #AMD64
                } else {
                    return "WOW64" #x86 on x64
                }
            }
            "x86" {
                return "x86"
            }
            "ARM64" {
                return "ARM64"
            }
            "IA64" {
                return "Itanium (IA-64)"
            }
            default {
                return "Unknown platform: $processorArchitecture"
            }
        }
    }
    catch {
        HandleCatchBlock -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return $null
    }
}

