@echo off
cd /d "%~dp0"
if errorlevel 1 (
    echo ERROR: No se pudo acceder a la carpeta del servidor.
    pause
    exit /b 1
)

if not exist "server-panel.ps1" (
    echo ERROR: No se encontro server-panel.ps1.
    pause
    exit /b 1
)

start "HORIZONS Server Panel" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0server-panel.ps1"
if errorlevel 1 (
    echo ERROR: No se pudo abrir el panel de HORIZONS.
    echo Como alternativa, ejecutar start-console.bat.
    pause
    exit /b 1
)
exit /b 0
