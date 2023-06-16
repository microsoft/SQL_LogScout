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
        [int]$fsize = Get-ChildItem $file |  ForEach-Object { [int]($_.length ) }

        Write-Host "Checking for console execution errors logged into $file..."

        if ($fsize -gt 0) {
            Write-Host "*** Standard ERROR file $file is $fsize bytes and contains the following output:"

            $stderr_string = Get-Content -Path $file 
            Write-Host $stderr_string -ForegroundColor Red
        }

        else {
            Remove-Item -Path $file -Force
            Write-Host "Removed $file which was $fsize bytes"
        }
    }
    Else {
        Write-Host "No $file file at this location"
    }

}

stderror_main