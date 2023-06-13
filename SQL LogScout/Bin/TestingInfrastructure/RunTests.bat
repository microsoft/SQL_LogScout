@echo off

powershell.exe -ExecutionPolicy Bypass -File TestsEntryPoint.ps1 2> .\##TestFailures.LOG

powershell.exe -ExecutionPolicy Bypass -File ..\StdErrorOutputHandling.ps1 .\##TestFailures.LOG

