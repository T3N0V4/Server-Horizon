@echo off
setlocal
cd /d "%~dp0"
title HORIZONS SERVER - Fabric 1.20.1 (Consola)
"C:\Program Files\Java\jdk-17\bin\java.exe" -Xms4G -Xmx8G ^
-XX:+UseG1GC ^
-XX:+DisableExplicitGC ^
-Xlog:gc*,safepoint:file=logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10M ^
-jar "fabric-server-mc.1.20.1-loader.0.16.10-launcher.1.1.2.jar" nogui
set "SERVER_EXIT=%ERRORLEVEL%"
echo.
echo HORIZONS finalizo. Codigo de salida: %SERVER_EXIT%
pause
endlocal & exit /b %SERVER_EXIT%
