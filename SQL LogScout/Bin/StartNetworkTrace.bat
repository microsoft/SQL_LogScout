@echo off

netsh trace start capture=yes maxsize=1 TRACEFILE=%2
logman start ndiscap -p Microsoft-Windows-NDIS-PacketCapture -mode newfile -max 200 -o %1%%d.etl -ets




