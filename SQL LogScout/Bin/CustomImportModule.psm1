<#
    This function will confirm if a module is imported in the system or not, it will help prevent
    repeat loading of modules and provide extra logging in debug log.
#>
function confirm-ModuleLoaded ([String] $moduleName, [String] $fullFileName)
{
    Write-LogDebug "Inside" $MyInvocation.MyCommand

    # if user passed fullFileName (e.g. c:\foldr\ModuleName.psm1) then we need to extract the module name
    # to be able to use PS Get-Module 
    if ([String]::IsNullOrEmpty -ne $fullFileName)
    {
        $moduleName = (Split-Path $fullFileName -Leaf) -replace '\.[^.]+$', '' 
        Write-LogDebug "Module Name extracted from file : $moduleName"
    }

    $module = Get-Module -Name $moduleName 

    #confirm returned module object has the module name we are looking for
    if ($module -and $module.Name -eq $moduleName) 
    {
        Write-LogDebug "module  $($module.Name) is imported before"
        return $true
    }
    Write-LogDebug "Module `"$moduleName`" is not imported in the system yet"

    return $false
}

<#
This function will replace the standard Import-Module cmdlet in powershell
it is meant to provide more logging in debug log to help identify if a particulare module fails to load
At the time of writing this function quarantined files by Anti-Virus was the main cause of such issue
#>
function Import-Module {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter()]
        [switch]$Force, 
        [Parameter()]
        [switch]$DisableNameChecking,
        [Parameter()]
        [switch] $Global
    )
    Write-LogDebug "Inside" $MyInvocation.MyCommand
    
    Write-LogDebug "Import-Module : $Name"

    #if module is loaded or user used force switch (which will prevent check for loaded module) we perform import-module
    if ($Force -or $false -eq $(confirm-ModuleLoaded -fullFileName $Name) )
    {
        # Call the original Import-Module cmdlet, we default to force, disableNamechecking to avoid issues with some modules
        # Global is needed to make the import work for all modules imported and called subsequently.

        $m = Microsoft.PowerShell.Core\Import-Module -Name $Name -Force -DisableNameChecking -Global -PassThru -ErrorVariable ErrorMessage

        #check returned -PassThru value to make sure successful import happeend
        if ($m) {
            Write-LogDebug "Module `"$Name`" is imported successfully"
        } else {
            Write-LogDebug "Module `"$Name`" Failed import, error : $ErrorMessage"
        }         
    } else {
        Write-LogDebug "Module `"$Name`" already loaded, no action performed"
    }
}
