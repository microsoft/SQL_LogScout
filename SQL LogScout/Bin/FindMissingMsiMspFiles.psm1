

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

# SIG # Begin signature block
# MIIsDwYJKoZIhvcNAQcCoIIsADCCK/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCAXyT1gJ01/OlC
# rx5yB5MFgkC7YAN7RU/EsXs0ypve6qCCEX0wggiNMIIHdaADAgECAhM2AAACDnmX
# oOn9X5/TAAIAAAIOMA0GCSqGSIb3DQEBCwUAMEExEzARBgoJkiaJk/IsZAEZFgNH
# QkwxEzARBgoJkiaJk/IsZAEZFgNBTUUxFTATBgNVBAMTDEFNRSBDUyBDQSAwMTAe
# Fw0yNTEwMjMyMzEyMDNaFw0yNjA0MjYyMzIyMDNaMCQxIjAgBgNVBAMTGU1pY3Jv
# c29mdCBBenVyZSBDb2RlIFNpZ24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCfrw9mbjhRpCz0Wh+dmWU4nlBbeiDkl5NfNWFA9NWUAfDcSAEtWiJTZLIB
# Vt+E5kjpxQfCeObdxk0aaPKmhkANla5kJ5egjmrttmGvsI/SPeeQ890j/QO4YI4g
# QWpXnt8EswtW6xzmRdMMP+CASyAYJ0oWQMVXXMNhBG9VBdrZe+L1+DzLawq42AWG
# NoKL6JdGg21P0W11MN1OtwrhubgTqEBkgYp7m1Bt4EeOxBz0GwZfPODbLVTblACS
# LmGlfEePEdVamqIUTTdsrAKG8NM/gGx010AiqAv6p2sCtSeZpvV7fkppLY9ajdm8
# Yc4Kf1KNI3U5ZNMdLIDz9fA5Q+ulAgMBAAGjggWZMIIFlTApBgkrBgEEAYI3FQoE
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
# aG9yaXR5MB0GA1UdDgQWBBSbKJrguVhFagj1tSbzFntHGtugCTAOBgNVHQ8BAf8E
# BAMCB4AwVAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjM2MTY3KzUwNjA1MjCCAeYG
# A1UdHwSCAd0wggHZMIIB1aCCAdGgggHNhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5j
# b20vcGtpaW5mcmEvQ1JML0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0dHA6
# Ly9jcmwxLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyGMWh0
# dHA6Ly9jcmwyLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5jcmyG
# MWh0dHA6Ly9jcmwzLmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgyKS5j
# cmyGMWh0dHA6Ly9jcmw0LmFtZS5nYmwvY3JsL0FNRSUyMENTJTIwQ0ElMjAwMSgy
# KS5jcmyGgb1sZGFwOi8vL0NOPUFNRSUyMENTJTIwQ0ElMjAwMSgyKSxDTj1CWTJQ
# S0lDU0NBMDEsQ049Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNl
# cnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9QU1FLERDPUdCTD9jZXJ0aWZpY2F0
# ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9u
# UG9pbnQwHwYDVR0jBBgwFoAUllGE4Gtve/7YBqvD8oXmKa5q+dQwHwYDVR0lBBgw
# FgYKKwYBBAGCN1sBAQYIKwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAKaBh/B8
# 42UPFqNHP+m2mYSY80orKjPVnXEb+KlCoxL1Ikl2DfziE1PBZXtCDbYtvyMqC9Pj
# KvB8TNz71+CWrO0lqV2f0KITMmtXiCy+yThBqLYvUZrbrRzlXYv2lQmqWMy0OqrK
# TIdMza2iwUp2gdLnKzG7DQ8IcbguYXwwh+GzbeUjY9hEi7sX7dgVP4Ls1UQNkRqR
# FcRPOAoTBZvBGhPSkOAnl9CShvCHfKrHl0yzBk/k/lnt4Di6A6wWq4Ew1BveHXMH
# 1ZT+sdRuikm5YLLqLc/HhoiT3rid5EHVQK3sng95fIdBMgj26SScMvyKWNC9gKkp
# emezUSM/c91wEhwwggjoMIIG0KADAgECAhMfAAAAUeqP9pxzDKg7AAAAAABRMA0G
# CSqGSIb3DQEBCwUAMDwxEzARBgoJkiaJk/IsZAEZFgNHQkwxEzARBgoJkiaJk/Is
# ZAEZFgNBTUUxEDAOBgNVBAMTB2FtZXJvb3QwHhcNMjEwNTIxMTg0NDE0WhcNMjYw
# NTIxMTg1NDE0WjBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQB
# GRYDQU1FMRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDEwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQDJmlIJfQGejVbXKpcyFPoFSUllalrinfEV6JMc7i+bZDoL
# 9rNHnHDGfJgeuRIYO1LY/1f4oMTrhXbSaYRCS5vGc8145WcTZG908bGDCWr4GFLc
# 411WxA+Pv2rteAcz0eHMH36qTQ8L0o3XOb2n+x7KJFLokXV1s6pF/WlSXsUBXGaC
# IIWBXyEchv+sM9eKDsUOLdLTITHYJQNWkiryMSEbxqdQUTVZjEz6eLRLkofDAo8p
# XirIYOgM770CYOiZrcKHK7lYOVblx22pdNawY8Te6a2dfoCaWV1QUuazg5VHiC4p
# /6fksgEILptOKhx9c+iapiNhMrHsAYx9pUtppeaFAgMBAAGjggTcMIIE2DASBgkr
# BgEEAYI3FQEEBQIDAgACMCMGCSsGAQQBgjcVAgQWBBQSaCRCIUfL1Gu+Mc8gpMAL
# I38/RzAdBgNVHQ4EFgQUllGE4Gtve/7YBqvD8oXmKa5q+dQwggEEBgNVHSUEgfww
# gfkGBysGAQUCAwUGCCsGAQUFBwMBBggrBgEFBQcDAgYKKwYBBAGCNxQCAQYJKwYB
# BAGCNxUGBgorBgEEAYI3CgMMBgkrBgEEAYI3FQYGCCsGAQUFBwMJBggrBgEFBQgC
# AgYKKwYBBAGCN0ABAQYLKwYBBAGCNwoDBAEGCisGAQQBgjcKAwQGCSsGAQQBgjcV
# BQYKKwYBBAGCNxQCAgYKKwYBBAGCNxQCAwYIKwYBBQUHAwMGCisGAQQBgjdbAQEG
# CisGAQQBgjdbAgEGCisGAQQBgjdbAwEGCisGAQQBgjdbBQEGCisGAQQBgjdbBAEG
# CisGAQQBgjdbBAIwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQD
# AgGGMBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUKV5RXmSuNLnrrJwN
# p4x1AdEJCygwggFoBgNVHR8EggFfMIIBWzCCAVegggFToIIBT4YxaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraWluZnJhL2NybC9hbWVyb290LmNybIYjaHR0cDov
# L2NybDIuYW1lLmdibC9jcmwvYW1lcm9vdC5jcmyGI2h0dHA6Ly9jcmwzLmFtZS5n
# YmwvY3JsL2FtZXJvb3QuY3JshiNodHRwOi8vY3JsMS5hbWUuZ2JsL2NybC9hbWVy
# b290LmNybIaBqmxkYXA6Ly8vQ049YW1lcm9vdCxDTj1BTUVSb290LENOPUNEUCxD
# Tj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1
# cmF0aW9uLERDPUFNRSxEQz1HQkw/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9i
# YXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50MIIBqwYIKwYBBQUH
# AQEEggGdMIIBmTBHBggrBgEFBQcwAoY7aHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraWluZnJhL2NlcnRzL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYIKwYBBQUHMAKG
# K2h0dHA6Ly9jcmwyLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9vdC5jcnQwNwYI
# KwYBBQUHMAKGK2h0dHA6Ly9jcmwzLmFtZS5nYmwvYWlhL0FNRVJvb3RfYW1lcm9v
# dC5jcnQwNwYIKwYBBQUHMAKGK2h0dHA6Ly9jcmwxLmFtZS5nYmwvYWlhL0FNRVJv
# b3RfYW1lcm9vdC5jcnQwgaIGCCsGAQUFBzAChoGVbGRhcDovLy9DTj1hbWVyb290
# LENOPUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxD
# Tj1Db25maWd1cmF0aW9uLERDPUFNRSxEQz1HQkw/Y0FDZXJ0aWZpY2F0ZT9iYXNl
# P29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQEL
# BQADggIBAFAQI7dPD+jfXtGt3vJp2pyzA/HUu8hjKaRpM3opya5G3ocprRd7vdTH
# b8BDfRN+AD0YEmeDB5HKQoG6xHPI5TXuIi5sm/LeADbV3C2q0HQOygS/VT+m1W7a
# /752hMIn+L4ZuyxVeSBpfwf7oQ4YSZPh6+ngZvBHgfBaVz4O9/wcfw91QDZnTgK9
# zAh9yRKKls2bziPEnxeOZMVNaxyV0v152PY2xjqIafIkUjK6vY9LtVFjJXenVUAm
# n3WCPWNFC1YTIIHw/mD2cTfPy7QA1pT+GPARAKt0bKtq9aCd/Ym0b5tPbpgCiRtz
# yb7fbNS1dE740re0COE67YV2wbeo2sXixzvLftH8L7s9xv9wV+G22qyKt6lmKLjF
# K1yMw4Ni5fMabcgmzRvSjAcbqgp3tk4a8emaaH0rz8MuuIP+yrxtREPXSqL/C5bz
# MzsikuDW9xH10graZzSmPjilzpRfRdu20/9UQmC7eVPZ4j1WNa1oqPHfzET3ChIz
# J6Q9G3NPCB+7KwX0OQmKyv7IDimj8U/GlsHD1z+EF/fYMf8YXG15LamaOAohsw/y
# wO6SYSreVW+5Y0mzJutnBC9Cm9ozj1+/4kqksrlhZgR/CSxhFH3BTweH8gP2FEIS
# RtShDZbuYymynY1un+RyfiK9+iVTLdD1h/SxyxDpZMtimb4CgJQlMYIZ6DCCGeQC
# AQEwWDBBMRMwEQYKCZImiZPyLGQBGRYDR0JMMRMwEQYKCZImiZPyLGQBGRYDQU1F
# MRUwEwYDVQQDEwxBTUUgQ1MgQ0EgMDECEzYAAAIOeZeg6f1fn9MAAgAAAg4wDQYJ
# YIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIBGyRI07r3Rf
# a2ejTaQ2CPEVESGCyEd3b3RJOxjkG1vGMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBN
# AGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJ
# KoZIhvcNAQEBBQAEggEAn5oUJYQ5TmqQ49xSLWQe61vvdCBMoVgk6SLWeSqq+H1G
# 0WrvuRtP2wpkH7aV1gpvddiwoYIojirPNrMSHniNmoLTQox4iCRZEjeeOCSv77pE
# zkpRv6aFHNt/q9qpC+bJs7hkjaDkNGsXXnlo/94/pOPE0U3piprqqPSwA049EkVR
# U4j8dUbVZwY2GHjsrWiARkKj/eEXCJDhNsPJEPN6xicCMoQIJtKoWxndEbwHg4Cw
# MiTWE/DfbK3+fmPyXFbsJEugWzLjjv5DmqVMCyyu3U7jdZ9jUIZ3/1WDi/esIM4F
# yLIskALuSKMctN7H589n5M4/KGZhDeVD1QVrB+pZ6KGCF7AwghesBgorBgEEAYI3
# AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIB
# BQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAx
# MA0GCWCGSAFlAwQCAQUABCBS4QHevDnYhoUewgpcwOLMHdbfim547ognuiMBNFbL
# PAIGaXPPgDzEGBMyMDI2MDIwNDE2MzUyNy45NDFaMASAAgH0oIHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACGCXZkgXi5+Xk
# AAEAAAIYMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDgxNDE4NDgyNVoXDTI2MTExMzE4NDgyNVowgdMxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjRDMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAsdzo6uuQ
# JqAfxLnvEBfIvj6knK+p6bnMXEFZ/QjPOFywlcjDfzI8Dg1nzDlxm7/pqbvjWhyv
# azKmFyO6qbPwClfRnI57h5OCixgpOOCGJJQIZSTiMgui3B8DPiFtJPcfzRt3Fsnx
# jLXwBIjGgnjGfmQl7zejA1WoYL/qBmQhw/FDFTWebxfo4m0RCCOxf2qwj31aOjc2
# aYUePtLMXHsXKPFH0tp5SKIF/9tJxRSg0NYEvQqVilje8aQkPd3qzAux2Mc5HMSK
# 4NMTtVVCYAWDUZ4p+6iDI9t5BNCBIsf5ooFNUWtxCqnpFYiLYkHfFfxhVUBZ8LGG
# xYsA36snD65s2Hf4t86k0e8WelH/usfhYqOM3z2yaI8rg08631IkwqUzyQoEPqMs
# HgBem1xpmOGSIUnVvTsAv+lmECL2RqrcOZlZax8K0aiij8h6UkWBN2IA/ikackTS
# GVRBQmWWZuLFWV/T4xuNzscC0X7xo4fetgpsqaEA0jY/QevkTvLv4OlNN9eOL8LN
# h7Vm0R65P7oabOQDqtUFAwCgjgPJ0iV/jQCaMAcO3SYpG5wSAYiJkk4XLjNSlNxU
# 2Idjs1sORhl7s7LC6hOb7bVAHVwON74GxfFNiEIA6BfudANjpQJ0nUc/ppEXpT4p
# gDBHsYtV8OyKSjKsIxOdFR7fIJIjDc8DvUkCAwEAAaOCAUkwggFFMB0GA1UdDgQW
# BBQkLqHEXDobY7dHuoQCBa4sX7aL0TAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA
# nkjRhjwPgdoIpvt4YioT/j0LWuBxF3ARBKXDENggraKvC0oRPwbjAmsXnPEmtuo5
# MD8uJ9Xw9eYrxqqkK4DF9snZMrHMfooxCa++1irLz8YoozC4tci+a4N37Sbke1pt
# 1xs9qZtvkPgZGWn5BcwVfmAwSZLHi2CuZ06Y0/X+t6fNBnrbMVovNaDX4WPdyI9G
# EzxfIggDsck2Ipo4VXL/Arcz7p2F7bEZGRuyxjgMC+woCkDJaH/yk/wcZpAsixe4
# POdN0DW6Zb35O3Dg3+a6prANMc3WIdvfKDl75P0aqcQbQAR7b0f4gH4NMkUct0Wm
# 4GN5KhsE1YK7V/wAqDKmK4jx3zLz3a8Hsxa9HB3GyitlmC5sDhOl4QTGN5kRi6oC
# oV4hK+kIFgnkWjHhSRNomz36QnbCSG/BHLEm2GRU9u3/I4zUd9E1AC97IJEGfwb+
# 0NWb3QEcrkypdGdWwl0LEObhrQR9B1V7+edcyNmsX0p2BX0rFpd1PkXJSbxf8IcE
# iw/bkNgagZE+VlDtxXeruLdo5k3lGOv7rPYuOEaoZYxDvZtpHP9P36wmW4INjR6N
# Inn2UM+krP/xeLnRbDBkm9RslnoDhVraliKDH62BxhcgL9tiRgOHlcI0wqvVWLdv
# 8yW8rxkawOlhCRqT3EKECW8ktUAPwNbBULkT+oWcvBcwggdxMIIFWaADAgECAhMz
# AAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0z
# MDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP9
# 7pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMM
# tY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gm
# U3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130
# /o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP
# 3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
# vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+A
# utuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz
# 1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6
# EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/Zc
# UlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZy
# acaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJ
# KwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8G
# CCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3Mv
# UmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQC
# BAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
# VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZF
# aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcw
# AoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cB
# MSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7
# bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/
# SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2
# EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2Fz
# Lixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0
# /fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
# swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJ
# Xk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+
# pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW
# 4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N
# 7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCCAkECAQEwggEBoYHZpIHWMIHTMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNy
# b3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAnWtGrXWiuNE8QrKfm4Ct
# Gr57z+mggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkq
# hkiG9w0BAQsFAAIFAO0tdnQwIhgPMjAyNjAyMDQwNzQwMzZaGA8yMDI2MDIwNTA3
# NDAzNlowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7S12dAIBADAKAgEAAgIMLgIB
# /zAHAgEAAgIULzAKAgUA7S7H9AIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
# AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IB
# AQCtZZrwK3OPil4hhrCGpE+e5Z4ycXzwOd99g+5mSg6vFuvfPw+VJpMMChqhX9SR
# 47z94TBFMgAj1LVRXK2pFHqwNMl8rIzkNBWrT6s6wD8sEDjSBydHeVysGhxeAqk8
# nY/rMeocZ3o4KpANhdb9husglZH0K6a757mCRwG0afPQIyH9rrauPfxfBq65WGxt
# GZUE9OqXMjUrYHKsxV5nVWASwCdU2tYVpQHiRP5FrkTm8RyEaj4G3+VrjNLSfnTH
# +gI9L1nT+tWtFQWs/6HIJTei17WT4i4FlUJmTwkpWto5ibdSKCncFUK+dyz1UFVl
# LZa3clw3aFOwzdWhs8f26Fh2MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIYJdmSBeLn5eQAAQAAAhgwDQYJYIZIAWUDBAIB
# BQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgqemVUAajw0Gzz7G7tMijGGluHv06jIHAODEZ2BI0IeQwgfoGCyqGSIb3DQEJ
# EAIvMYHqMIHnMIHkMIG9BCCZE9yJuOTItIwWaES6lzGKK1XcSoz1ynRzaOVzx9eF
# ajCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACGCXZ
# kgXi5+XkAAEAAAIYMCIEIGiV6HeMUIMRr3E3MENsJ7dCIGtaBUCnAiB1RXGnwc1o
# MA0GCSqGSIb3DQEBCwUABIICAGXjrXUEnoka4axlcpmOD954/hV1vBo3pkGLyNRt
# xgYZp2KHFGXrx2ekX+YMXOSiR7xZfajPiw1ftMD3DXwyidvUi24X5bP7V8RhLoZi
# ONj2z1eEm+BlQnvrjtb2vuHrdfq4q5md5UvTLiZj6LoE4H2pcVNGAQBo9q9idjcV
# xb1Ex2G4oIFS1I9jM0J/c49t2ZlxhrHJXqfI7f3Dqj3hS2/vJadRkQ9/JCBBta+A
# kpjiNtQo+o4lAkzjHMzT+drHmV7wIgeP9SVNaQVR1MkDxtI2KB7/1hxNi7VSpiJw
# kVQXQvJmE+uCJFM+7PgVDJr/tjxuF06qm8y/H3hz0JDnYrKF01RnKGOd2nF/3RUO
# EVnMfD5D+KY/5JtUiJjBtE+GvMzr7tsnqQhI8U0EzGNzruxpEioXOqfEt313ilwk
# Rkw3oAbFkXxitGYPXcm6IW401da6w53+rhTtll4j6AvbFAC9yprANXHvnWkXrulp
# yk9DLb1Z4eshI5z4bELfjomkp4MfqREeCKwCDtIC3wFBuDABhwTCg9R8mfCSGUR6
# I1H0LM3Ut78GRIXIOBDwKZOyPD9h3/nFR0kSmTysH+WYfbagQNw5A2+jvGAs0QtS
# Oz5F9ZA3pxHCQqkJmoePsm8UaBt6K/hduT4H+cmZb7VMb/Q5ZKMiighxpAX4as6a
# 9SzX
# SIG # End signature block
