function Test-MinPowerShellVersion
{
    
    #check for minimum version 5 
    $psversion_maj = (Get-Host).Version.Major
    $psversion_min = (Get-Host).Version.Minor

    if ($psversion_maj -lt 5)
    {
        Write-Host "Minimum required PowerShell version is 5.x. Your current verion is $psversion_maj.$psversion_min." -ForegroundColor Yellow
        Write-Host "Please upgrade PowerShell @ https://docs.microsoft.com/powershell/scripting/install/installing-powershell"  -ForegroundColor Yellow
        Write-Host "Exiting..." -ForegroundColor Yellow
        exit 7654321
    }

    else {
        Write-Host "Launching SQL LogScout..."
    }
}

Test-MinPowerShellVersion