$currentPath  = Get-Location
$ls_location = (Get-Item $currentPath).parent.FullName

BeforeAll { 
	. ../LoggingFacility.ps1
	# . ../Confirm-FileAttributes.ps1
	# . ../SQLLogScoutPs.ps1
	# . ../SQLDumpHelper.ps1
}


Describe 'Notepad' {
    It "Notepad Exists in Windows folder" {
        'C:\Windows\system32\notepad.exe' | Should -Exist
    }
	
	It "SQLLogScout Exists " {
        $ls_location + "\SQLLogScoutPs.ps1" | Should -Exist
    }
	
}

Describe 'LoggingFacility functions' {

    BeforeEach{
        
    }
    It "Test Write-Error"{
        Write-Host "This is an error" | Should -Be "This is an error"   #THIS NEEDS RESEARCH

    }

}

