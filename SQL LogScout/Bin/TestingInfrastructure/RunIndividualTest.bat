@echo off

echo.
echo *****************************************************************
echo               Starting Tests Infrastructure                    
echo *****************************************************************
echo.


powershell.exe -ExecutionPolicy Bypass -File FilecountandtypeValidation.ps1 2> .\##TestFailures.LOG

powershell.exe -ExecutionPolicy Bypass -File ..\StdErrorOutputHandling.ps1 .\##TestFailures.LOG

