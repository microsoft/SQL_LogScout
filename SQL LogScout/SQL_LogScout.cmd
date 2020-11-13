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

powershell.exe -ExecutionPolicy Bypass -File SQLLogScoutPs.ps1 %1 %2 %3 %4 %5 %6 2> .\##STDERR.LOG

powershell.exe -ExecutionPolicy Bypass -File StdErrorOutputHandling.ps1 .\##STDERR.LOG
