

Import-Module .\CommonFunctions.psm1

[string]$global:ErrorFile = ""


#Appends messages to the persisted log 
function LogErrors([string]$Message)
{
    try 
    {
        #Add timestamp
        [string]$Message = (Get-Date -Format("yyyy-MM-dd HH:MM:ss.ms")) + ': '+ $Message
        
        #Write the message to the error file
        Write-Output -InputObject $Message | Out-File -FilePath $ErrorFile -Append
    }
    catch 
    {
        HandleCatchBlockMissingMSI -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
    }
}


function HandleCatchBlockMissingMSI ([string] $function_name, [System.Management.Automation.ErrorRecord] $err_rec)
{
    #This import is needed here to prevent errors that can happen during ctrl-c
    $error_msg = $err_rec.Exception.Message
    $error_linenum = $err_rec.InvocationInfo.ScriptLineNumber
    $error_offset = $err_rec.InvocationInfo.OffsetInLine
    $error_script = $err_rec.InvocationInfo.ScriptName
    LogErrors -Message "Function '$function_name' failed with error:  $error_msg (line: $error_linenum, offset: $error_offset, file: $error_script)" 
}


function Get-MissingMsiMspFilesInfo ([string]$OutputLocation, [string]$ErrorFile)
{

    try 
    {
        # set the global error file
        $global:ErrorFile = $ErrorFile

        [string]$HKCR = "Registry::HKEY_CLASSES_ROOT"
        [string]$HKLM = "Registry::HKEY_LOCAL_MACHINE"
        

        [string]$strSQLName = "SQL"
        [string]$strNewRTMSource =""

        # set the output file names
        [string]$detailedOutputFile = $OutputLocation + "_MissingMsiMsp_Detailed.txt"
        [string]$summaryOutputFile  = $OutputLocation + "_MissingMsiMsp_Summary.txt"

        # initialize the error file name
        Write-Output "======================================================================================" | Out-File -FilePath $ErrorFile
        
        # remove the output files if they exist
        if (Test-Path -Path $detailedOutputFile) { Remove-Item -Path $detailedOutputFile}
        if (Test-Path -Path $summaryOutputFile) { Remove-Item -Path $summaryOutputFile}


        # string builder obejct to hold the output text
        [System.Text.StringBuilder]$strOutputText = New-Object -TypeName System.Text.StringBuilder
        [System.Text.StringBuilder]$strSummaryOutputText = New-Object -TypeName System.Text.StringBuilder
        [System.Text.StringBuilder]$strCopyCommandsSummaryOutputText = New-Object -TypeName System.Text.StringBuilder

        # an array to hold the list of SQL Server products that were not found installer cache
        [System.Collections.ArrayList]$arrMissingSQLProducts = New-Object -TypeName System.Collections.ArrayList

        [bool] $packageIsCorrupted = $false
        [bool] $canBeFixedwithCopy = $false
        [bool] $mspPackageIsCorrupted = $false
        [bool] $mspCanBeFixedwithCopy = $false


        # get all the subkeys under HKCR\Installer\Products
        $regHKCRinstProdKey = $HKCR + "\Installer\Products\"
        $installerProductGUIDs = Get-ChildItem -Path $regHKCRinstProdkey -Name


        # loop through each product subkey
        foreach ($prodGUID in $installerProductGUIDs)
        {


            # set the error action preference to silently continue for all the Get-ItemPropertyValue calls

            [string] $productsKey = $regHKCRinstProdkey + $prodGUID
            [string] $sourceListKey = $regHKCRinstProdkey + $prodGUID + "\SourceList"
            [string] $listMediaKey =  $regHKCRinstProdkey + $prodGUID + "\SourceList\Media"


            # get the product name
            # since -ErrorAction SlientlyContinue does not work, we employ this the catch block will be executed if the product name is not found
            # For reference https://github.com/PowerShell/PowerShell/issues/5906
            # Also using Get-ItemProperty instead of Get-ItemPropertyValue to support PS 4.0

            try 
            {
                $productName = (Get-ItemProperty -Path $productsKey -Name "ProductName" -ErrorAction Stop | 
                                Select-Object -Property "ProductName").ProductName
            }
            catch 
            {
                $productName = "No Product Name found"
                LogErrors -Message "$productName in $productsKey"
            }
            

            # check only for products that contain "SQL" in the name
            if ($productName -match $strSQLName)
            {
                # S-1-5-18 is the SID for the system account
                [string] $instPropertiesKey = $HKLM + "\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\" + $prodGUID + "\InstallProperties\"

                # get the package name
                try 
                {
                    $packageName        = (Get-ItemProperty -Path $sourceListKey -Name "PackageName" -ErrorAction SilentlyContinue |
                                            Select-Object -Property "PackageName").PackageName
                }
                catch 
                {
                    
                    $packageName = "No Package Name found"
                    LogErrors -Message "$packageName in $sourceListKey"
                }
                

                # get the last used source
                try 
                {
                    $lastUsedSource = (Get-ItemProperty -Path $sourceListKey -Name "LastUsedSource" -ErrorAction SilentlyContinue |
                                            Select-Object -Property "LastUsedSource").LastUsedSource
                }
                catch
                {
                    $lastUsedSource = "No Last Used Source found"
                    LogErrors -Message "$lastUsedSource in $sourceListKey"
                }
                
                # get the media package
                try 
                {
                    $mediaPackage = (Get-ItemProperty -Path $listMediaKey -Name "MediaPackage" -ErrorAction Stop | 
                                        Select-Object -Property "MediaPackage").MediaPackage
                }
                catch
                {
                    $mediaPackage = "No Media Package found"
                    LogErrors -Message "$mediaPackage in $listMediaKey" 
                    
                }

                # get the local package
                try 
                {
                    $locPkgInInstCache  = (Get-ItemProperty -Path $instPropertiesKey -Name "LocalPackage" -ErrorAction SilentlyContinue |
                                        Select-Object -Property "LocalPackage").LocalPackage
                }
                catch
                {
                    $locPkgInInstCache = "No Local Package found"
                    LogErrors -Message "$locPkgInInstCache in $instPropertiesKey" 
                }


                # get the display version
                try 
                {
                    $displayVersion     = (Get-ItemProperty -Path $instPropertiesKey -Name "DisplayVersion" -ErrorAction SilentlyContinue |
                                        Select-Object -Property "DisplayVersion").DisplayVersion
                }
                catch
                {
                    $displayVersion = "No Display Version found"
                    LogErrors -Message "$displayVersion in $instPropertiesKey" 
                }

                # get the install date
                try
                {
                    $installDate = (Get-ItemProperty -Path $instPropertiesKey -Name "InstallDate" -ErrorAction SilentlyContinue |
                                        Select-Object -Property "InstallDate").InstallDate
                }
                catch
                {
                    $installDate = "No Install Date found"
                    LogErrors -Message "$installDate in $instPropertiesKey" 
                }

                # get the uninstall string
                try
                {
                    $uninstallString    = (Get-ItemProperty -Path $instPropertiesKey -Name "UninstallString" -ErrorAction SilentlyContinue |
                                        Select-Object -Property "UninstallString").UninstallString
                }
                catch
                {
                    $uninstallString = "No Uninstall String found"
                    LogErrors -Message "$uninstallString in $instPropertiesKey" 
                }
                


                
                # Pull the Product Code from the Uninstall String
                if ($uninstallString.Length -gt 14)
                {
                    $prodCode =  $uninstallString.Substring(14)
                }

                # Pull out path from LastUsedSource
                if ($lastUsedSource.Length -gt 4)
                {
                    $lastUsedSourcePath = $lastUsedSource.Substring(4)
                }

                $installSource = $strNewRTMSource + $mediaPackage

                # msiPath =  $lastUsedSourcePath + "\" + $packageName, no need for separator, already there
                $msiFileName = $lastUsedSourcePath + $packageName
                
                #check for the existence of the installation msi file in the last used source path 
                [bool] $instalMsiFileExists = Test-Path -Path $msiFileName

                #check for the existence of the local package in the installer cache
                [bool] $locPkgExistsInInstCache = Test-Path -Path $locPkgInInstCache


                #start the output text
                
                [void]$strOutputText.Append("================================================================================`r`n")
                [void]$strOutputText.Append("PRODUCT NAME: " + $productName + "`r`n")
                [void]$strOutputText.Append("================================================================================`r`n")
                [void]$strOutputText.Append("  Product Code : $prodCode `r`n")
                [void]$strOutputText.Append("  Version: $displayVersion `r`n")
                [void]$strOutputText.Append("  Most Current Install Date: $installDate `r`n")
                [void]$strOutputText.Append("  Registry Path: `r`n")
                [void]$strOutputText.Append("   " + ($sourceListKey -replace "Registry::") + "`r`n")
                [void]$strOutputText.Append("  Package   : $packageName `r`n")
                [void]$strOutputText.Append("  Install Source : $installSource `r`n")
                [void]$strOutputText.Append("  LastUsedSource : '$lastUsedSourcePath' `r`n")
                [void]$strOutputText.Append("  Expected LocalPackage file in installer cache '" + $locPkgInInstCache + "'`r`n")
                [void]$strOutputText.Append("  Full path of source MSI file Name " + $msiFileName + "`r`n")


                # check if the original installation source msi file exists in the last used source path
                if ($true -eq $instalMsiFileExists)
                {
                    [void]$strOutputText.Append("`r`n")
                    [void]$strOutputText.Append("  Installation '" + $packageName + "' exist in the LastUsedSource installation path.`r`n")
                }
                else
                {
                    [void]$strOutputText.Append("`r`n")
                    [void]$strOutputText.Append("  Installation '" + $packageName + "' does NOT exist in the LastUsedSource installation path '" + $lastUsedSourcePath + "'`r`n")
                }

                
                #file exists in the installer cache
                if ($locPkgExistsInInstCache)
                {
                    # check if the file in the installer cache is the same size as the orig install msi file
                    if ($instalMsiFileExists)
                    {
                        #since the file exists in the installer cache, it can be fixed with a copy
                        $canBeFixedwithCopy = $true

                        [void]$strOutputText.Append("  Can be fixed with copy: $canBeFixedwithCopy `r`n")

                        $localPackageSize = (Get-Item $locPkgInInstCache).Length
                        $msiFileSize = (Get-Item $msiFileName).Length

                        [void]$strOutputText.Append("`r`n")
                        [void]$strOutputText.Append("  Local package file size: " + $localPackageSize + " bytes`r`n")
                        [void]$strOutputText.Append("  Installation MSI file size: " + $msiFileSize + " bytes`r`n")

                        #if they are not the same size, one of the files is likely corrupt
                        #we will assume that the MSIs are the ones that are corrupted, not the original installer package
                        if ($localPackageSize -ne $msiFileSize)
                        {
                            $packageIsCorrupted = $true
                            

                            [void]$strOutputText.Append("`r`n")
                            [void]$strOutputText.Append(" !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`r`n")
                            [void]$strOutputText.Append(" !!!! Package '" + $locPkgInInstCache + "' exists in installer cache but is likely corrupted. !!!! `r`n")
                            [void]$strOutputText.Append(" !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`r`n")
                            [void]$strOutputText.Append("`r`n")
                            [void]$strOutputText.Append("     Action needed: Recreate or re-establish path to the installation directory:`r`n")
                            [void]$strOutputText.Append("     '$lastUsedSourcePath' then run the copy command below to update installer cache`r`n")
                            [void]$strOutputText.Append("     The path on the line above must exist at the root location to resolve this problem of msi/msp file being corrupted`r`n")
                            [void]$strOutputText.Append("     In some cases you may need to copy the missing file manually from somewhere else or`r`n")
                            [void]$strOutputText.Append("     replace the problem file by overwriting if it exists: `r`n")
                            [void]$strOutputText.Append("`r`n`r`n")
                            [void]$strOutputText.Append("     copy `""  + $msiFileName +  "`" " + $locPkgInInstCache + "`r`n")
                            [void]$strOutputText.Append("`r`n")
                            [void]$strOutputText.Append("     Replace the existing file if prompted to do so.`r`n")
                            [void]$strOutputText.Append("`r`n")
                        }
                        else 
                        {
                            [void]$strOutputText.Append("`r`n")
                            [void]$strOutputText.Append("  Package '" + $locPkgInInstCache + "' exists in the Installer cache, and has the same size as original installation MSI file.`r`n")
                            [void]$strOutputText.Append("  No action needed as everything seems in order.`r`n")
                            [void]$strOutputText.Append("`r`n")
                        }

                    }
                    else # the installation msi file does not exist in the last used source path
                    {
                        [void]$strOutputText.Append("  Can be fixed with copy: $canBeFixedwithCopy `r`n")
                        
                        #warn - likely all good but if errors, take action
                        [void]$strOutputText.Append("`r`n")
                        [void]$strOutputText.Append("    Package '" + $locPkgInInstCache + "' exists in the Installer cache. Likely no actions needed.`r`n")
                        [void]$strOutputText.Append("    The original installation MSI file '$msiFileName' is not present.`r`n")
                        [void]$strOutputText.Append("`r`n")
                        [void]$strOutputText.Append("    Should you get errors about '$locPkgInInstCache'  `r`n")
                        [void]$strOutputText.Append("    then you may need to manually copy the file, if it exists to replace the problem file. `r`n") 
                        [void]$strOutputText.Append("`r`n")
                    }


                }
                else #package doesn't exist in installer cache
                {
                    ## copy the file from the last installation source to the local machine
                    if ($instalMsiFileExists)
                    {
                        $canBeFixedwithCopy = $true
                        [void]$strOutputText.Append("  Can be fixed with copy: $canBeFixedwithCopy `r`n")

                    }
                    else # if the msi file does not exist in the last used source path
                    {
                        $canBeFixedwithCopy = $false
                        [void]$strOutputText.Append("  Can be fixed with copy: $canBeFixedwithCopy `r`n")
                    }

                    [void]$strOutputText.Append("`r`n")
                    [void]$strOutputText.Append(" !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`r`n")
                    [void]$strOutputText.Append(" !!!! Package '" + $locPkgInInstCache + "' does NOT exist in installer cache. !!!! `r`n")
                    [void]$strOutputText.Append(" !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`r`n")
                    [void]$strOutputText.Append("`r`n")
                    [void]$strOutputText.Append("     Action needed: Recreate or re-establish the path to the installation directory:`r`n")
                    [void]$strOutputText.Append("     " + $lastUsedSourcePath + "then run the copy command below to update installer cache`r`n")
                    [void]$strOutputText.Append("     The path on the line above must exist as shown to resolve this problem of msi/msp file not being found`r`n")
                    [void]$strOutputText.Append("     In some cases you may need to copy the missing file manually from somewhere else or`r`n")
                    [void]$strOutputText.Append("     replace the problem file by overwriting if it exists: `r`n")
                    [void]$strOutputText.Append("`r`n `r`n")
                    [void]$strOutputText.Append("     copy `""  + $msiFileName +  "`" " + $locPkgInInstCache + "`r`n")
                    [void]$strOutputText.Append("`r`n")
                    [void]$strOutputText.Append("     Replace the existing file if prompted to do so.`r`n")
                    [void]$strOutputText.Append("`r`n")

                }

                # add the product to the array of products that are missing or corrupted in installer cache
                if (($packageIsCorrupted -eq $true) -or ($locPkgExistsInInstCache -eq $false))
                {
                    $missingPackage = [PSCustomObject]@{
                        m_ProductName               = $productName
                        m_Version                   = $displayVersion
                        m_FileName                  = $packageName
                        m_PackageInCache            = $locPkgInInstCache
                        m_CopyCommandToFix          = "copy `"$msiFileName`" $locPkgInInstCache"
                        m_CanBeFixedwCopy           = $canBeFixedwithCopy
                        m_InstallMSIExists          = $instalMsiFileExists
                        m_LocalPackageExists        = $locPkgExistsInInstCache
                        m_PackageInCacheIsCorrupted = $packageIsCorrupted
                    }          

                    [void]$arrMissingSQLProducts.Add($missingPackage)
                }
                
                #reset some variables
                $packageIsCorrupted = $false
                $canBeFixedwithCopy = $false


                # now get the patches installed for the product

                [void]$strOutputText.Append("`r`n")
                [void]$strOutputText.Append("" + $productName + " Patches Installed `r`n")
                [void]$strOutputText.Append("--------------------------------------------------------------------------------`r`n")

                # get the patches installed for the product - strInstallSource2        
                [string]$regHKLMpatchesKey = $HKLM + "\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\" + $prodGUID +  "\Patches\"
                
                # get the patches installed for the product - strInstallSource3        
                [string]$regHKLMpatchesDirectKey = $HKLM + "\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Patches\"
                


                if ($true -eq [string]::IsNullOrEmpty($regHKLMpatchesKey))
                {
                    [void]$strOutputText.Append("regHKLMpatchesKey is null or empty.`r`n")
                    LogErrors -Message "regHKLMpatchesKey is null or empty." 
                }

                # get all the Patches GUIDs installed for the product
                $installedPatchesGUIDs = Get-ChildItem -Path $regHKLMpatchesKey -Name
                
                # loop through each patch installed for the product and check if the patch exists in the installer cache
                foreach ($patchesGUID in $installedPatchesGUIDs)
                {

                    $instPatchesSrcList = $HKCR + "\Installer\Patches\" + $patchesGUID + "\SourceList"
                    $HKLMpatchesKeyandGUID = $regHKLMpatchesKey + $patchesGUID + "\"
                    $HKLMpatchesDirectKeyandGUID = $regHKLMpatchesDirectKey  + $patchesGUID + "\"

                    # # get the local package msp
                    try 
                    {
                        $locMspPkgInInstCache = (Get-ItemProperty -Path $HKLMpatchesDirectKeyandGUID -Name "LocalPackage" -ErrorAction Stop |
                                                Select-Object -Property "LocalPackage").LocalPackage
                    }
                    catch
                    {
                        $locMspPkgInInstCache = "No Local Msp Package found"
                        LogErrors -Message "$locMspPkgInInstCache in $HKLMpatchesDirectKeyandGUID" 
                        
                    }

                    # get the uninstallable value for msp
                    try
                    {
                        $UninstallableValue =  (Get-ItemProperty -Path $HKLMpatchesKeyandGUID -Name "Uninstallable" -ErrorAction Stop |
                                                Select-Object -Property "Uninstallable").Uninstallable
                    }
                    catch
                    {
                        $UninstallableValue = "No Uninstallable found"
                        LogErrors -Message "$UninstallableValue in $HKLMpatchesKeyandGUID" 
                    }

                    # get the MoreInfoURL value for msp
                    try
                    {
                        $MoreInfoURLValue =  (Get-ItemProperty -Path $HKLMpatchesKeyandGUID -Name "MoreInfoURL" -ErrorAction Stop |
                                                Select-Object -Property "MoreInfoURL").MoreInfoURL

                    }
                    catch
                    {
                        $MoreInfoURLValue = "No URL found"
                        LogErrors -Message "$MoreInfoURLValue in $HKLMpatchesKeyandGUID" 
                    }

                    # get the DisplayName value for msp
                    try 
                    {
                        $DisplayNameValue =  (Get-ItemProperty -Path $HKLMpatchesKeyandGUID -Name "DisplayName" -ErrorAction Stop |
                                            Select-Object -Property "DisplayName").DisplayName
                    }
                    catch
                    {
                        $DisplayNameValue = "No Display Name found"
                        LogErrors -Message "$DisplayNameValue in $HKLMpatchesKeyandGUID" 
                    }
                    
                    # get the Installed value for msp
                    try 
                    {
                        $InstalledDateValue =  (Get-ItemProperty -Path $HKLMpatchesKeyandGUID -Name "Installed" -ErrorAction Stop |
                                            Select-Object -Property "Installed").Installed
                    }
                    catch
                    {
                        $InstalledDateValue = "No Installed Date found"
                        LogErrors -Message "$InstalledDateValue in $HKLMpatchesKeyandGUID" 
                    }


                    # get the PackageName value for msp
                    try 
                    {
                        $hkcrPatchesPackageName =  (Get-ItemProperty -Path $instPatchesSrcList -Name "PackageName" -ErrorAction Stop |
                                            Select-Object -Property "PackageName").PackageName
                    }
                    catch
                    {
                        $hkcrPatchesPackageName = "No Package Name found"
                        LogErrors -Message "$hkcrPatchesPackageName in $instPatchesSrcList" 
                    }


                    # get the LastUsedSource value for msp
                    try 
                    {
                        $hkcrPatchesLastUsedSource =  (Get-ItemProperty -Path $instPatchesSrcList -Name "LastUsedSource" -ErrorAction SilentlyContinue |
                                                        Select-Object -Property "LastUsedSource").LastUsedSource
                    }
                    catch
                    {
                        $hkcrPatchesLastUsedSource = "No Last Used Source found"
                        LogErrors -Message "$hkcrPatchesLastUsedSource in $instPatchesSrcList" 
                    }


                    # Pull the URL from the MoreInfoURL String
                    if ($false -eq [String]::IsNullOrWhiteSpace($MoreInfoURLValue) -or ($MoreInfoURLValue -ne "No URL found"))
                    {
                        if ($MoreInfoURLValue.Length -gt 43)
                        {
                            $MoreInfoURLTrimmedValue = $MoreInfoURLValue.Substring($MoreInfoURLValue.Length - 43);
                        }
                        else
                        {
                            $MoreInfoURLTrimmedValue = $MoreInfoURLValue
                        }
                    }

                    # Pull the URL from the LastUsedSource String
                    $hkcrProdLastUsedSourceTrimmedValue = $hkcrPatchesLastUsedSource.Substring(4);

                    #build the msp file name path
                    $mspFileName = $hkcrProdLastUsedSourceTrimmedValue + $hkcrPatchesPackageName

                    #check for the existence of the installation msp file in the last used source path
                    [bool] $instalMspFileExists = Test-Path -Path $mspFileName

                    #check for the existence of the local package MSP in the installer cache
                    [bool] $patchExistsInInstCache = Test-Path -Path $locMspPkgInInstCache


                    [void]$strOutputText.Append(" Display Name:    " + $DisplayNameValue + "`r`n")
                    [void]$strOutputText.Append(" KB Article URL:  " + $MoreInfoURLTrimmedValue + "`r`n")
                    [void]$strOutputText.Append(" Install Date:    " + $InstalledDateValue + "`r`n")
                    [void]$strOutputText.Append("   Uninstallable:   " + $UninstallableValue + "`r`n")
                    [void]$strOutputText.Append(" Patch Details: `r`n")
                    [void]$strOutputText.Append("   HKEY_CLASSES_ROOT\Installer\Patches\" + $patchesGUID + "`r`n")
                    [void]$strOutputText.Append("   PackageName:   " + $hkcrPatchesPackageName + "`r`n")
                    [void]$strOutputText.Append("    Patch LastUsedSource: " + $hkcrPatchesLastUsedSource + "`r`n")
                    [void]$strOutputText.Append("   Installer Cache File Path:     " + $locMspPkgInInstCache + "`r`n")
                    [void]$strOutputText.Append("     Per " + $HKLMpatchesDirectKeyandGUID + "LocalPackage" + "`r`n")

                    

                    #if there are msp file for this product, go and check if they are present
                    if ($false -eq [String]::IsNullOrEmpty($hkcrPatchesPackageName))
                    {
                        #file exists in the installer cache
                        if ($patchExistsInInstCache)
                        {
                            if ($instalMspFileExists) 
                            {
                                $localPatchFileSize = (Get-Item $locMspPkgInInstCache).Length
                                $mspFileSize = (Get-Item $mspFileName).Length
                                
                                #if they are not the same size, one of the files is likely corrupt
                                #we will assume that the msps are the ones that are corrupted, not the original installer package
                                if ($localPatchFileSize -ne $mspFileSize)
                                {
                                    $mspPackageIsCorrupted = $true
                                    $mspCanBeFixedwithCopy = $true

                                    [void]$strOutputText.Append("`r`n")
                                    [void]$strOutputText.Append(" !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`r`n")
                                    [void]$strOutputText.Append(" !!!! Package '" + $locMspPkgInInstCache + "' exists in installer cache but is likely corrupted. !!!! `r`n")
                                    [void]$strOutputText.Append(" !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`r`n")
                                    [void]$strOutputText.Append("`r`n")
                                    [void]$strOutputText.Append("     Action needed: Recreate or re-establish path to the installation directory:`r`n")
                                    [void]$strOutputText.Append("      " + $hkcrProdLastUsedSourceTrimmedValue + "then run the copy command below to update installer cache`r`n")
                                    [void]$strOutputText.Append("     The path on the line above must exist at the root location to resolve this problem of msi/msp file being corrupted`r`n")
                                    [void]$strOutputText.Append("     In some cases you may need to copy the missing file manually from somewhere else or`r`n")
                                    [void]$strOutputText.Append("     replace the problem file by overwriting if it exists: `r`n")
                                    [void]$strOutputText.Append("`r`n`r`n")
                                    [void]$strOutputText.Append("     copy `""  + $mspFileName +  "`" " + $locMspPkgInInstCache + "`r`n")
                                    [void]$strOutputText.Append("`r`n")
                                    [void]$strOutputText.Append("     Replace the existing file if prompted to do so.`r`n")
                                    [void]$strOutputText.Append("`r`n")
                                    [void]$strOutputText.Append("     Use the following URL to assist with downloading the patch:`r`n")
                                    [void]$strOutputText.Append("     " + $MoreInfoURLTrimmedValue + "`r`n")

                                }
                                else 
                                {
                                    [void]$strOutputText.Append("`r`n")
                                    [void]$strOutputText.Append("  Package '" + $locMspPkgInInstCache + "' exists in the Installer cache, and has the same size as original installation MSI file.`r`n")
                                    [void]$strOutputText.Append("  No action needed as everything seems in order.`r`n")
                                    [void]$strOutputText.Append("`r`n")
                                }
                    

                            }
                            else # the installation msp file does not exist in the last used source path 
                            {
                                [void]$strOutputText.Append("`r`n")
                                [void]$strOutputText.Append("    Package '" + $locMspPkgInInstCache + "' exists in the Installer cache. Likely no actions needed.`r`n")
                                [void]$strOutputText.Append("    The original installation MSP file '$mspFileName' is not present.`r`n")
                                [void]$strOutputText.Append("`r`n")
                                [void]$strOutputText.Append("    Should you get errors about '$locMspPkgInInstCache' or '$mspFileName' `r`n")
                                [void]$strOutputText.Append("    then you may need to manually copy the file, if it exists to replace the problem file. `r`n") 
                                [void]$strOutputText.Append("`r`n")
                            }
                        }
                        # file doesn't exist in the installer cache
                        else 
                        {
                            if ($instalMspFileExists)
                            {
                                $mspCanBeFixedwithCopy = $true
                            }
                            else # if the msp file does not exist in the last used source path
                            {
                                #recreate in some other way
                                $mspCanBeFixedwithCopy = $false
                            }

                            [void]$strOutputText.Append("`r`n")
                            [void]$strOutputText.Append(" !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`r`n")
                            [void]$strOutputText.Append(" !!!! Package '" + $locMspPkgInInstCache + "' does NOT exist in the Installer cache. !!!! `r`n")
                            [void]$strOutputText.Append(" !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`r`n")
                            [void]$strOutputText.Append("`r`n")
                            [void]$strOutputText.Append("     Action needed: Recreate or re-establish the path to the installation directory:`r`n")
                            [void]$strOutputText.Append("     " + $hkcrProdLastUsedSourceTrimmedValue + "then run the copy command below to update installer cache`r`n")
                            [void]$strOutputText.Append("     The path on the line above must exist at the root location to resolve this problem of msi/msp file not being found`r`n")
                            [void]$strOutputText.Append("     In some cases you may need to copy the missing file manually from somewhere else or`r`n")
                            [void]$strOutputText.Append("     replace the problem file by overwriting if it exists: `r`n")
                            [void]$strOutputText.Append("`r`n`r`n")
                            [void]$strOutputText.Append("     copy `""  + $mspFileName +  "`" " + $locMspPkgInInstCache + "`r`n")
                            [void]$strOutputText.Append("`r`n")
                            [void]$strOutputText.Append("     Replace the existing file if prompted to do so.`r`n")
                            [void]$strOutputText.Append("`r`n")
                            [void]$strOutputText.Append("     Use the following URL to assist with downloading the patch:`r`n")
                            [void]$strOutputText.Append("     " + $MoreInfoURLTrimmedValue + "`r`n")

                        }

                    }
                    else 
                    {
                        [void]$strOutputText.Append("`r`n")
                        [void]$strOutputText.Append("  No Patches Found.`r`n")
                        [void]$strOutputText.Append("`r`n")
                        
                    }

                    [void]$strOutputText.Append("--------------------------------------------------------------------------------`r`n")

                    
                    # add the patch to the array of products that are missing or corrupted in installer cache
                    if (($mspPackageIsCorrupted -eq $true) -or ($patchExistsInInstCache -eq $false))
                    {
                        $missingPackage = [PSCustomObject]@{
                            m_ProductName               = $DisplayNameValue
                            m_Version                   = ""
                            m_FileName                  = $hkcrPatchesPackageName
                            m_PackageInCache            = $locMspPkgInInstCache
                            m_CopyCommandToFix          = "copy `"$mspFileName`" $locMspPkgInInstCache"
                            m_CanBeFixedwCopy           = $mspCanBeFixedwithCopy
                            m_InstallMSIExists          = $instalMspFileExists
                            m_LocalPackageExists        = $patchExistsInInstCache
                            m_PackageInCacheIsCorrupted = $mspPackageIsCorrupted
                        }
                        
                        
                        [void]$arrMissingSQLProducts.Add($missingPackage)
                    }
                    #reset some variables
                    $mspPackageIsCorrupted = $false
                    $mspCanBeFixedwithCopy = $false

                }
                
            } #end of check if product name contains SQL


            # write the output to file 
            if ($strOutputText.Length -gt 32768)
            {
                [void]$strOutputText.Append("`r`n")

                Add-Content -Path $detailedOutputFile -Value ($strOutputText.ToString())
                
                #reset the string builder object
                $strOutputText = ""
            }
            

        } #end of loop through each product subkey




        [void]$strOutputText.Append("==================================================================================`r`n")


        # write the output to file
        Add-Content -Path $detailedOutputFile -Value ($strOutputText.ToString())


        # print a summary list of SQL Server products that are missing in the installer cache
        # just the summary list of missing ones and how to fix it


        # if there are no missing packages, return
        if ($arrMissingSQLProducts.Count -eq 0)
        {
            [void]$strSummaryOutputText.Append("Great news! No missing installer MSI or MSP packages for SQL products.`r`n")
            Add-Content -Path $summaryOutputFile -Value ($strSummaryOutputText.ToString())
            return ($arrMissingSQLProducts.Count)
        }
        else 
        {
            # else if there are missing packages print the summary list from the $arrMissingSQLProducts array

            [void]$strSummaryOutputText.Append("==================================================================================`r`n")
            [void]$strSummaryOutputText.Append("This is the list of SQL Server products that are missing in the installer cache: `r`n")
            [void]$strSummaryOutputText.Append("==================================================================================`r`n`r`n")

            $countMissingPackages = 0
            [bool]$foundCorruptPackages = $false
            $strLenProdN = 65
            $strLenVer = 14
            $strLenPkgName = 32
            $strLenPkgInCache = 50

            # loop through the missing products and see if there are any reported corrupted packages
            foreach ($missingProduct in $arrMissingSQLProducts)
            {
                if ($missingProduct.m_PackageInCacheIsCorrupted -eq $true)
                {
                    #we found a corrupted package, set the flag to true and break the loop
                    $foundCorruptPackages = $true
                    break
                }
            }

            if ($foundCorruptPackages -eq $true)
            {
                [void]$strSummaryOutputText.Append("`r`n")
                [void]$strSummaryOutputText.Append("Warning: One or more MSI/MSP packages is possibly corrupt. This is determined by comparing the size of the current installer cache file to the original installation MSI/MSP package. If the original installation package is not correct or is from a different product version with same file name, then the reported corrupt file is false. Thus the usage of the word 'possibly' corrupt.`r`n")
                [void]$strSummaryOutputText.Append("`r`n")
            }
            

            # add the header to the summary output
            [void]$strSummaryOutputText.Append("-- missing or corrupt installer msi or msp packages --" +  "`r`n")
            [void]$strSummaryOutputText.Append("ProductName".PadRight($strLenProdN) + " " + "ExpectedInstallerCacheFile".PadRight($strLenPkgInCache) + " " + "FileIsPresentInCacheButPossiblyCorrupt".PadRight($strLenPkgInCache) + " " + "ProductVersion".PadRight($strLenVer)  + " " + "PackageName".PadRight($strLenPkgName) +  "`r`n")
            [void]$strSummaryOutputText.Append("-" * $strLenProdN + " " + "-" * $strLenPkgInCache +  " " + "-" * $strLenPkgInCache + " " + "-" * $strLenVer + " "+ "-" * $strLenPkgName + "`r`n")

            $canBeFixedwithCopyCntrForHeader = 0

            # loop through the missing products and add the missing packages to the summary output
            foreach ($missingProduct in $arrMissingSQLProducts)
            {
                if (($missingProduct.m_LocalPackageExists -eq $false) -or ($missingProduct.m_PackageInCacheIsCorrupted -eq $true))
                {
                    #increment the count of missing packages
                    $countMissingPackages++

                    #initialize the string variables
                    $prodNameSumFile = ""
                    $prodVersionSumFile = ""
                    $prodPkgNameSumFile = ""
                    $prodLocalPkginCacheSumFile = ""
                    
                    #format the product name to 65 characters
                    if (($missingProduct.m_ProductName).Length -gt $strLenProdN)
                    {
                        $prodNameSumFile = ($missingProduct.m_ProductName).Substring(0, $strLenProdN) 
                    }
                    else
                    {
                        $prodNameSumFile = ($missingProduct.m_ProductName).PadRight($strLenProdN)
                    }

                    # if the package in cache is corrupted, add the corrupted package to the summary output and package in cache leave blank
                    if ($missingProduct.m_PackageInCacheIsCorrupted -eq $true)
                    {

                        #format the package in cache to 50 characters
                        if (($missingProduct.m_PackageInCache).Length -gt $strLenPkgInCache)
                        {
                            $prodLocalPkgCorruptedSumFile = ($missingProduct.m_PackageInCache).Substring(0, $strLenPkgInCache)
                        }
                        else
                        {
                            $prodLocalPkgCorruptedSumFile = ($missingProduct.m_PackageInCache).PadRight($strLenPkgInCache)
                        }

                        # add spaces for package in cache
                        $prodLocalPkginCacheSumFile = "".PadRight($strLenPkgInCache)
                    }

                    else 
                    {
                        #format the package in cache to 50 characters
                        if (($missingProduct.m_PackageInCache).Length -gt $strLenPkgInCache)
                        {
                            $prodLocalPkginCacheSumFile = ($missingProduct.m_PackageInCache).Substring(0, $strLenPkgInCache)
                        }
                        else
                        {
                            $prodLocalPkginCacheSumFile = ($missingProduct.m_PackageInCache).PadRight($strLenPkgInCache)
                        }

                        # add spaces for corrupted package
                        $prodLocalPkgCorruptedSumFile = "".PadRight($strLenPkgInCache)

                    }


                    #format the version to 14 characters
                    if (($missingProduct.m_Version).Length -gt $strLenVer)
                    {
                        $prodVersionSumFile = ($missingProduct.m_Version).Substring(0, $strLenVer)
                    }
                    else
                    {
                        $prodVersionSumFile = ($missingProduct.m_Version).PadRight($strLenVer)
                    }

                    #format the package name to 32 characters
                    if (($missingProduct.m_FileName).Length -gt $strLenPkgName)
                    {
                        $prodPkgNameSumFile = ($missingProduct.m_FileName).Substring(0, $strLenPkgName)
                    }
                    else
                    {
                        $prodPkgNameSumFile = ($missingProduct.m_FileName).PadRight($strLenPkgName)
                    }


                    # add the product name that has a missing MSI to the summary output
                    [void]$strSummaryOutputText.Append("$prodNameSumFile $prodLocalPkginCacheSumFile $prodLocalPkgCorruptedSumFile $prodVersionSumFile $prodPkgNameSumFile`r`n")

                    # if the package can be fixed with copy, add the copy command to the summary output
                    if ($missingProduct.m_CanBeFixedwCopy -eq $true)
                    {
                        # if there is at least one copy command, add the header
                        $canBeFixedwithCopyCntrForHeader++

                        if ($canBeFixedwithCopyCntrForHeader -eq 1)
                        {
                            [void]$strCopyCommandsSummaryOutputText.Append("`r`n")
                            [void]$strCopyCommandsSummaryOutputText.Append("=================================================================================================================================`r`n")
                            [void]$strCopyCommandsSummaryOutputText.Append("Copy command(s) to resolve missing MSI/MSP file when the original install package is present`r`n")
                            [void]$strCopyCommandsSummaryOutputText.Append("=================================================================================================================================`r`n")
                        }
                        
                        [void]$strCopyCommandsSummaryOutputText.Append("$($missingProduct.m_CopyCommandToFix) `r`n")
                    }
                }

            }

            if ($canBeFixedwithCopyCntrForHeader -eq 1)
            {
                [void]$strCopyCommandsSummaryOutputText.Append("`r`n`r`n")
                [void]$strCopyCommandsSummaryOutputText.Append("Warning: The copy command(s) here are created only for packages that have the original installation files available. Therefore, for some or many packages you may not be able to re-create them using copy commands. `r`n")
                [void]$strCopyCommandsSummaryOutputText.Append("         For full resolution options see https://learn.microsoft.com/troubleshoot/sql/database-engine/install/windows/restore-missing-windows-installer-cache-files article `r`n`r`n")
            }

            Add-Content -Path $summaryOutputFile -Value ($strSummaryOutputText.ToString())
            Add-Content -Path $summaryOutputFile -Value ($strCopyCommandsSummaryOutputText.ToString())
        }
    }
    
    catch 
    {
        HandleCatchBlockMissingMSI -function_name $($MyInvocation.MyCommand) -err_rec $PSItem
        return 0
    }

    # return the count of missing packages
    return ($arrMissingSQLProducts.Count)
}
