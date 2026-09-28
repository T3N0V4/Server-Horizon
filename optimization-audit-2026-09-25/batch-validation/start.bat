@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 goto DIRECTORY_ERROR

title HORIZONS SERVER - Fabric 1.20.1

rem Java 17 instalado en este equipo. Cambiar solo esta ruta si se mueve Java.
set "JAVA_EXE=C:\Program Files\Java\jdk-17\bin\java.exe"
set "SERVER_JAR=fabric-server-mc.1.20.1-loader.0.16.10-launcher.1.1.2.jar"
set "MIN_RAM=4G"
set "MAX_RAM=8G"

echo ========================================
echo       HORIZONS SERVER - Fabric 1.20.1
echo ========================================
echo Carpeta: %CD%
echo RAM del servidor: %MIN_RAM% inicial / %MAX_RAM% maxima
echo Para guardar y apagar normalmente, escribir: stop
echo.

if not exist "%JAVA_EXE%" (
    echo ERROR: No se encontro Java 17 en "%JAVA_EXE%".
    echo Corregir JAVA_EXE en este archivo.
    set "SERVER_EXIT=1"
    goto FINISH
)
if not exist "%SERVER_JAR%" (
    echo ERROR: No se encontro "%SERVER_JAR%".
    set "SERVER_EXIT=1"
    goto FINISH
)
if not exist "logs\" mkdir "logs"
if not exist "logs\" (
    echo ERROR: No se pudo crear la carpeta logs.
    set "SERVER_EXIT=1"
    goto FINISH
)

"%JAVA_EXE%" -version
if errorlevel 1 (
    echo ERROR: Java no pudo iniciarse.
    set "SERVER_EXIT=1"
    goto FINISH
)
echo.
echo Iniciando HORIZONS...

rem G1 conserva su ajuste automatico. El log de GC rota para limitar su tamano.
"%JAVA_EXE%" -Xms%MIN_RAM% -Xmx%MAX_RAM% ^
-XX:+UseG1GC ^
-XX:+DisableExplicitGC ^
-Xlog:gc*,safepoint:file=logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10M ^
-jar "%SERVER_JAR%" nogui
set "SERVER_EXIT=%ERRORLEVEL%"
goto FINISH

:DIRECTORY_ERROR
echo ERROR: No se pudo acceder a la carpeta del servidor.
set "SERVER_EXIT=1"

:FINISH
echo.
echo HORIZONS finalizo. Codigo de salida: %SERVER_EXIT%
if not "%SERVER_EXIT%"=="0" echo Revisar los errores de esta consola y logs\latest.log.
echo.
pause
endlocal & exit /b %SERVER_EXIT%
