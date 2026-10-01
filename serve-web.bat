@echo off
REM Serves the built XV (XAU-Vote) web app on http://localhost:8901/
REM Double-click this file anytime to (re)start the server.
python -m http.server 8901 --directory "%~dp0src\app\build\web"
