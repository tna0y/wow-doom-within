@echo off

if not exist deploy.conf (
    echo "deploy.conf file is missing. Check out the deploy.conf.example file."
    exit /b
)

for /f "tokens=1,2 delims==" %%a in (deploy.conf) do (
set %%a=%%b
)

set ADDON_PATH=%WOW_ADDONS_PATH%\%ADDON_NAME%
echo "Addon path: %ADDON_PATH%"

RD /S /Q "%ADDON_PATH%"
MD "%ADDON_PATH%"
XCOPY /E /Y .\build\%ADDON_NAME%\* "%ADDON_PATH%"
