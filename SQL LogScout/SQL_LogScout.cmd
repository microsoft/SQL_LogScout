@echo off 
rem  Copyright (c) Microsoft Corporation.
rem  Licensed under the MIT license.


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

powershell.exe -ExecutionPolicy RemoteSigned -File SQLLogScoutPs.ps1 %1 %2 %3 %4 %5 %6 %7 %8 2> .\##STDERR.LOG

powershell.exe -ExecutionPolicy RemoteSigned -File StdErrorOutputHandling.ps1 .\##STDERR.LOG
