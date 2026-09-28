param([switch]$MockChild)

$ErrorActionPreference = 'Stop'

if ($MockChild) {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
    for ($line = 0; $line -lt 22010; $line++) {
        [Console]::Out.WriteLine('burst-' + $line)
        if (($line % 1000) -eq 0) { [Console]::Error.WriteLine('warning-' + $line) }
    }
    [Console]::Out.WriteLine('READY')
    while (($command = [Console]::ReadLine()) -ne $null) {
        [Console]::Out.WriteLine('received-' + $command)
        if ($command -eq 'stop') { break }
    }
    [Console]::Out.Write('STDOUT-FINAL')
    [Console]::Error.Write('STDERR-FINAL')
    exit 7
}

Add-Type -Path (Join-Path $PSScriptRoot 'ProcessBridge.cs')
$bridge = New-Object Horizons.Panel.ProcessBridge
$logPath = Join-Path $PSScriptRoot ('bridge-test-' + [Guid]::NewGuid().ToString('N') + '.log')
$childArguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -MockChild'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    $bridge.Start((Join-Path $PSHOME 'powershell.exe'), $childArguments, $PSScriptRoot, $logPath)
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 50
        $ready = @(Get-Content -LiteralPath $logPath -Tail 64) -contains 'READY'
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    Assert-True $ready 'El proceso de prueba no llego a READY.'
    Assert-True (-not $bridge.HasExited) 'El proceso termino antes de recibir stop.'
    Assert-True ($bridge.DroppedLines -gt 2000) 'La cola no aplico el limite visual esperado.'

    $rejectedActiveDispose = $false
    try { $bridge.Dispose() } catch { $rejectedActiveDispose = $true }
    Assert-True $rejectedActiveDispose 'Dispose acepto cerrar un proceso activo.'
    Assert-True (-not $bridge.HasExited) 'Dispose interrumpio el proceso activo.'

    $bridge.Send('list')
    $unicodeCommand = 'say ' + [char]0x00f1 + [char]0x00e1 + [char]0x4e16
    $bridge.Send($unicodeCommand)
    $bridge.Send('stop')
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not $bridge.OutputCompleted -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 25
    }
    Assert-True $bridge.OutputCompleted 'No termino la captura de ambas salidas.'
    Assert-True ($bridge.ExitCode -eq 7) 'No se preservo el codigo de salida.'

    $entries = @($bridge.Drain(30000))
    Assert-True ($entries.Count -eq 20000) 'La cola visual debe contener exactamente sus ultimas 20000 lineas.'
    Assert-True $bridge.IsQueueEmpty 'Drain no vacio la cola.'
    Assert-True (@($entries | Where-Object { $_.Text -eq 'STDOUT-FINAL' -and -not $_.IsError }).Count -eq 1) 'Se perdio la ultima linea stdout sin salto final.'
    Assert-True (@($entries | Where-Object { $_.Text -eq 'STDERR-FINAL' -and $_.IsError }).Count -eq 1) 'Se perdio la ultima linea stderr sin salto final.'
    Assert-True (@($entries | Where-Object { $_.Text -eq 'received-list' }).Count -eq 1) 'El proceso no recibio el comando list.'
    Assert-True (@($entries | Where-Object { $_.Text -eq ('received-' + $unicodeCommand) }).Count -eq 1) 'No se conservaron los caracteres Unicode en entrada y salida.'
    $bridge.Dispose()

    $diskLines = @(Get-Content -LiteralPath $logPath)
    Assert-True (@($diskLines | Where-Object { $_ -like 'burst-*' }).Count -eq 22010) 'El limite visual descarto lineas del archivo.'
    Assert-True ($diskLines -contains 'STDOUT-FINAL') 'Falta la ultima linea stdout en el archivo.'
    Assert-True ($diskLines -contains 'STDERR-FINAL') 'Falta la ultima linea stderr en el archivo.'

    $failedBridge = New-Object Horizons.Panel.ProcessBridge
    $launchFailed = $false
    try { $failedBridge.Start('missing-horizons-bridge-test.exe', '', $PSScriptRoot, $logPath) }
    catch { $launchFailed = $true }
    Assert-True $launchFailed 'No se informo el fallo de arranque.'
    Assert-True $failedBridge.HasExited 'El fallo de arranque dejo estado de proceso activo.'
    $failedBridge.Dispose()

    Write-Output ('PASS: stdout/stderr, comandos, cierre seguro, cola de 20000 lineas, transcript completo, EOF y fallo de arranque. Lineas en archivo: ' + $diskLines.Count)
    Write-Output ('Registro de prueba: ' + $logPath)
}
finally {
    if (-not $bridge.HasExited) {
        try { $bridge.Send('stop') } catch { }
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not $bridge.OutputCompleted -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 25 }
    }
    if ($bridge.HasExited) { $bridge.Dispose() }
}
