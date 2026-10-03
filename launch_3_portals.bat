@echo off
setlocal
title EdhiConnect AI - Portal Launcher
set "EDHI_PORT=8080"
if not "%~1"=="" set "EDHI_PORT=%~1"
echo EdhiConnect AI - Citizen, Driver and Admin HQ
echo Start the Flutter web server on port %EDHI_PORT% before using these windows.
echo Sign in with the matching account in each isolated browser session.
echo.
start "" "http://localhost:%EDHI_PORT%"
start "" chrome.exe --incognito "http://localhost:%EDHI_PORT%"
if exist "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" (
    start "" "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" "http://localhost:%EDHI_PORT%"
) else if exist "C:\Program Files\Microsoft\Edge\Application\msedge.exe" (
    start "" "C:\Program Files\Microsoft\Edge\Application\msedge.exe" "http://localhost:%EDHI_PORT%"
) else (
    echo Open the third role in another browser profile or device.
)
echo.
echo Use the regular browser for HQ, Chrome Incognito for Driver, and Edge for Citizen.
echo Separate profiles preserve independent account sessions.
endlocal
