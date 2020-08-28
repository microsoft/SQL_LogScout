param
(
    [Parameter(Position=0,HelpMessage='provide a file name',Mandatory=$true)]
    [string] $FileName
)


function stderror_main()
{

    $file = $FileName #'.\##STDERR.LOG'
    $fileExists = (Test-Path -Path $file)



    If ($fileExists -eq $True) {
        [int]$fsize = Get-ChildItem $file |  ForEach-Object { [int]($_.length ) / 1kb }

        if ($fsize -gt 0) {
            Write-Host "*** Standard ERROR contains the following output:"

            $stderr_string = Get-Content -Path $file 
            Write-Host $stderr_string -ForegroundColor Red
        }

        else {
            Remove-Item -Path $file -Force
            Write-Host "Found and removed $file which was empty"
        }
    }
    Else {
        Write-Host "No $file file at this location"
    }

}

stderror_main