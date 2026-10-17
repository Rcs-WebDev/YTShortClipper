@echo off
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-0C8375ABAB64}" >nul 2>&1
if %errorlevel% neq 0 (
    echo Installing WebView2 Runtime, please wait...
    start /wait MicrosoftEdgeWebview2Setup.exe /silent /install
)
start yt-short-clipper-v2.exe
