@echo off 
rem  Copyright (c) Microsoft Corporation.
rem  Licensed under the MIT license.

@echo off

IF "%1"=="?" GOTO :Help
IF "%1"=="-?" GOTO :Help
IF "%1"=="/?" GOTO :Help
IF "%1"=="help" GOTO :Help
IF "%1"=="-help" GOTO :Help
IF "%1"=="--help" GOTO :Help

echo.
echo      ======================================================================================================
echo               #####   #####  #          #                      #####                             
echo              #     # #     # #          #        ####   ####  #     #  ####   ####  #    # ##### 
echo              #       #     # #          #       #    # #    # #       #    # #    # #    #   #   
echo               #####  #     # #          #       #    # #       #####  #      #    # #    #   #   
echo                    # #   # # #          #       #    # #  ###       # #      #    # #    #   #   
echo              #     # #    #  #          #       #    # #    # #     # #    # #    # #    #   #   
echo               #####   #### # #######    #######  ####   ####   #####   ####   ####   ####    #   
echo      ======================================================================================================
echo.

set cwd=%~dp0
cd "%cwd%"

powershell.exe -ExecutionPolicy RemoteSigned -File MinVersionValidation.ps1

rem if the min version of Powershell is less than 4.0, exit since we cannot execute futher
rem MinVersionValidation.ps1 returns a custom exit code 7654321 if the min version is less than 4

if %errorlevel% EQU 7654321 exit /b

IF [%1] EQU [] (set p1="") ELSE (set p1=%1)
IF [%2] EQU [] (set p2="") ELSE (set p2=%2)
IF [%3] EQU [] (set p3="") ELSE (set p3=%3)
IF [%4] EQU [] (set p4="") ELSE (set p4=%4)
IF [%5] EQU [] (set p5="") ELSE (set p5=%5)
IF [%6] EQU [] (set p6="") ELSE (set p6=%6)
IF [%7] EQU [] (set p7="") ELSE (set p7=%7)
IF [%8] EQU [] (set p8="") ELSE (set p8=%8)


powershell.exe -ExecutionPolicy RemoteSigned -File SQLLogScoutPs.ps1 -Scenario %p1% -ServerName %p2% -CustomOutputPath %p3% -DeleteExistingOrCreateNew %p4% -DiagStartTime %p5% -DiagStopTime %p6% -InteractivePrompts %p7% 2> .\##STDERR.LOG

powershell.exe -ExecutionPolicy RemoteSigned -File StdErrorOutputHandling.ps1 .\##STDERR.LOG

exit /b

:Help
@echo off
powershell.exe -ExecutionPolicy RemoteSigned -File SQLLogScoutPs.ps1 -help

:EOF