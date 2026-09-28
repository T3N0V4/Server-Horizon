param([switch]$NoShow)
$ErrorActionPreference='Stop'
$script:serverRoot=$PSScriptRoot
$script:javaExe='C:\Program Files\Java\jdk-17\bin\java.exe'
$script:serverJar='fabric-server-mc.1.20.1-loader.0.16.10-launcher.1.1.2.jar'
$script:bridge=$null
$script:state='stopped'
$script:closeWhenStopped=$false
$script:readySeen=$false
$script:startedAt=$null
$script:lastOutputAt=$null
$script:lineCount=0
$script:warningCount=0
$script:errorCount=0
$script:lastExitCode=$null
$script:cpuSample=$null
$script:lastStatsAt=[DateTime]::MinValue
function Save-PanelError($record) {
    try {
        $dir=Join-Path $script:serverRoot 'logs'
        [void][IO.Directory]::CreateDirectory($dir)
        [IO.File]::AppendAllText((Join-Path $dir 'panel-errors.log'),
            ("[{0:o}] {1}{2}{3}{2}" -f [DateTime]::Now,$record,[Environment]::NewLine,$record.ScriptStackTrace),[Text.Encoding]::UTF8)
    } catch { }
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
trap {
    Save-PanelError $_
    if (-not $NoShow) {
        [void][Windows.Forms.MessageBox]::Show(
            ('No se pudo abrir el panel. Revisar logs\panel-errors.log.'+[Environment]::NewLine+$_.Exception.Message),
            'HORIZONS - Error del panel','OK','Error')
    }
    exit 1
}
Add-Type -Path (Join-Path $PSScriptRoot 'panel\ProcessBridge.cs')
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'HORIZONS Server Panel'
$form.Size = New-Object System.Drawing.Size(1120, 720)
$form.MinimumSize = New-Object System.Drawing.Size(820, 520)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 24)
$form.ForeColor = [System.Drawing.Color]::FromArgb(225, 230, 238)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 82
$header.BackColor = [System.Drawing.Color]::FromArgb(23, 28, 37)
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'HORIZONS'
$title.Location = New-Object System.Drawing.Point(22, 12)
$title.AutoSize = $true
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 21)
$title.ForeColor = [System.Drawing.Color]::FromArgb(120, 208, 255)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Minecraft Fabric 1.20.1  |  Panel del servidor dedicado'
$subtitle.Location = New-Object System.Drawing.Point(25, 51)
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 177)
$header.Controls.Add($subtitle)

$statusDot = New-Object System.Windows.Forms.Label
$statusDot.Text = [char]0x25CF
$statusDot.Location = New-Object System.Drawing.Point(835, 18)
$statusDot.AutoSize = $true
$statusDot.Font = New-Object System.Drawing.Font('Segoe UI', 16)
$statusDot.ForeColor = [System.Drawing.Color]::FromArgb(130, 140, 155)
$statusDot.Anchor = 'Top,Right'
$header.Controls.Add($statusDot)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'DETENIDO'
$statusLabel.Location = New-Object System.Drawing.Point(864, 22)
$statusLabel.Size = New-Object System.Drawing.Size(220, 24)
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$statusLabel.Anchor = 'Top,Right'
$header.Controls.Add($statusLabel)

$statsLabel = New-Object System.Windows.Forms.Label
$statsLabel.Text = 'RAM: --  |  Tiempo: --'
$statsLabel.Location = New-Object System.Drawing.Point(840, 49)
$statsLabel.Size = New-Object System.Drawing.Size(245, 21)
$statsLabel.TextAlign = 'MiddleRight'
$statsLabel.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 177)
$statsLabel.Anchor = 'Top,Right'
$header.Controls.Add($statsLabel)

$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Dock = 'Top'
$toolbar.Height = 62
$toolbar.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 9)
$toolbar.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 29)
$form.Controls.Add($toolbar)

function New-PanelButton([string]$text, [System.Drawing.Color]$color, [int]$left, [int]$width) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Location = New-Object System.Drawing.Point($left, 12)
    $button.Size = New-Object System.Drawing.Size($width, 38)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $color
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $toolbar.Controls.Add($button)
    return $button
}

$startButton = New-PanelButton 'Iniciar servidor' ([System.Drawing.Color]::FromArgb(32, 146, 93)) 18 150
$stopButton = New-PanelButton 'Detener (stop)' ([System.Drawing.Color]::FromArgb(190, 71, 73)) 180 145
$clearButton = New-PanelButton 'Limpiar vista' ([System.Drawing.Color]::FromArgb(62, 72, 89)) 337 125
$openLogsButton = New-PanelButton 'Abrir logs' ([System.Drawing.Color]::FromArgb(62, 72, 89)) 474 115
$stopButton.Enabled = $false

$phaseLabel = New-Object System.Windows.Forms.Label
$phaseLabel.Text = 'Fase: esperando inicio'
$phaseLabel.Location = New-Object System.Drawing.Point(610, 12)
$phaseLabel.Size = New-Object System.Drawing.Size(470, 38)
$phaseLabel.Anchor = 'Top,Left,Right'
$phaseLabel.TextAlign = 'MiddleRight'
$phaseLabel.ForeColor = [System.Drawing.Color]::FromArgb(170, 181, 198)
$phaseLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$toolbar.Controls.Add($phaseLabel)

$console = New-Object System.Windows.Forms.RichTextBox
$console.Dock = 'Fill'
$console.BackColor = [System.Drawing.Color]::FromArgb(8, 10, 14)
$console.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 225)
$console.Font = New-Object System.Drawing.Font('Cascadia Mono', 9.5)
$console.ReadOnly = $true
$console.BorderStyle = 'None'
$console.DetectUrls = $false
$console.WordWrap = $false
$console.ScrollBars = 'Both'
$form.Controls.Add($console)

$commandPanel = New-Object System.Windows.Forms.Panel
$commandPanel.Dock = 'Bottom'
$commandPanel.Height = 64
$commandPanel.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 12)
$commandPanel.BackColor = [System.Drawing.Color]::FromArgb(23, 28, 37)
$form.Controls.Add($commandPanel)

$promptLabel = New-Object System.Windows.Forms.Label
$promptLabel.Text = '>'
$promptLabel.Location = New-Object System.Drawing.Point(20, 17)
$promptLabel.Size = New-Object System.Drawing.Size(22, 30)
$promptLabel.Font = New-Object System.Drawing.Font('Cascadia Mono', 14, [System.Drawing.FontStyle]::Bold)
$promptLabel.ForeColor = [System.Drawing.Color]::FromArgb(120, 208, 255)
$commandPanel.Controls.Add($promptLabel)

$commandBox = New-Object System.Windows.Forms.TextBox
$commandBox.Location = New-Object System.Drawing.Point(45, 15)
$commandBox.Size = New-Object System.Drawing.Size(900, 31)
$commandBox.Anchor = 'Left,Right,Top'
$commandBox.BackColor = [System.Drawing.Color]::FromArgb(11, 14, 19)
$commandBox.ForeColor = [System.Drawing.Color]::FromArgb(235, 239, 245)
$commandBox.BorderStyle = 'FixedSingle'
$commandBox.Font = New-Object System.Drawing.Font('Cascadia Mono', 11)
$commandBox.Enabled = $false
$commandPanel.Controls.Add($commandBox)

$sendButton = New-Object System.Windows.Forms.Button
$sendButton.Text = 'Enviar'
$sendButton.Location = New-Object System.Drawing.Point(960, 13)
$sendButton.Size = New-Object System.Drawing.Size(120, 36)
$sendButton.Anchor = 'Top,Right'
$sendButton.FlatStyle = 'Flat'
$sendButton.FlatAppearance.BorderSize = 0
$sendButton.BackColor = [System.Drawing.Color]::FromArgb(38, 119, 174)
$sendButton.ForeColor = [System.Drawing.Color]::White
$sendButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$sendButton.Enabled = $false
$commandPanel.Controls.Add($sendButton)



function Append-Console([string]$line, [Drawing.Color]$color) {
    if ($form.IsDisposed) { return }
    if ($console.TextLength -gt 1500000) { $console.Select(0,400000); $console.SelectedText = '' }
    $console.Select($console.TextLength,0)
    $console.SelectionColor = $color
    $console.AppendText($line + [Environment]::NewLine)
    $console.ScrollToCaret()
}
function Set-ServerState([string]$value) {
    $script:state = $value
    $startButton.Enabled = $value -in @('stopped','failed')
    $stopButton.Enabled = $value -in @('starting','running')
    $commandBox.Enabled = $stopButton.Enabled
    $sendButton.Enabled = $stopButton.Enabled
    switch ($value) {
        'starting' { $statusLabel.Text='INICIANDO'; $statusDot.ForeColor=[Drawing.Color]::Gold }
        'running' { $statusLabel.Text='EN EJECUCION'; $statusDot.ForeColor=[Drawing.Color]::LightGreen }
        'stopping' { $statusLabel.Text='GUARDANDO'; $statusDot.ForeColor=[Drawing.Color]::Gold; $phaseLabel.Text='Esperando el cierre de Java y el guardado del mundo' }
        'failed' { $statusLabel.Text='ERROR'; $statusDot.ForeColor=[Drawing.Color]::Salmon }
        default { $statusLabel.Text='DETENIDO'; $statusDot.ForeColor=[Drawing.Color]::Silver }
    }
}
function Handle-OutputLine($entry) {
    $line = $entry.Text
    $script:lineCount++
    $script:lastOutputAt=[DateTime]::Now
    $color=$console.ForeColor
    if ($line -match '(?i)(/ERROR\]|\[ERROR\]|/FATAL\]|Exception|Caused by:)') { $script:errorCount++; $color=[Drawing.Color]::Salmon }
    elseif ($line -match '(/WARN\]|\[WARN\])') { $script:warningCount++; $color=[Drawing.Color]::Gold }
    elseif ($entry.IsError) { $color=[Drawing.Color]::FromArgb(221,202,187) }
    Append-Console $line $color
    if ($line -match 'Done \(.+\)!') {
        $script:readySeen=$true
        if ($script:state -ne 'stopping') { Set-ServerState 'running'; $phaseLabel.Text='Servidor listo - conectate a localhost' }
    } elseif ($line -match 'Stopping server') { Set-ServerState 'stopping' }
    elseif (-not $script:readySeen -and $script:state -ne 'stopping') {
        if ($line -match 'Loading Minecraft') { $phaseLabel.Text='Cargando Fabric y Minecraft' }
        elseif ($line -match 'Loading (\d+) mods') { $phaseLabel.Text="Cargando $($Matches[1]) mods" }
        elseif ($line -match 'Initializing com\.ishland\.c2me') { $phaseLabel.Text='Inicializando C2ME' }
        elseif ($line -match 'Preparing level') { $phaseLabel.Text='Cargando el mundo' }
        elseif ($line -match 'Started DhServerLevel') { $phaseLabel.Text='Preparando Distant Horizons y dimensiones' }
        elseif ($line -match 'Preparing start region') { $phaseLabel.Text='Preparando la region inicial' }
        elseif ($line -match 'Preparing spawn area: (\d+)%') { $phaseLabel.Text="Preparando spawn: $($Matches[1])% (solo esta fase)" }
        elseif ($line -match "Failed to load datapacks|can't proceed|Failed to start") { $phaseLabel.Text='Error al iniciar Minecraft - revisar las lineas rojas' }
    }
}
function Get-StartBlocker {
    try {
        $others=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($script:serverJar) })
        if ($others.Count) { return ('Ya existe HORIZONS (PID '+(($others | ForEach-Object { $_.ProcessId }) -join ', ')+'). Detenelo antes de iniciar otra instancia.') }
    } catch {
        if (@([Diagnostics.Process]::GetProcessesByName('java')).Count) { return 'Hay un proceso Java que no pude identificar. Comproba que el servidor anterior este detenido.' }
    }
    $port=25565
    $properties=Join-Path $script:serverRoot 'server.properties'
    if (Test-Path -LiteralPath $properties) {
        foreach ($line in [IO.File]::ReadAllLines($properties)) { if ($line -match '^server-port=(\d+)$') { $port=[int]$Matches[1] } }
    }
    if (@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object { $_.Port -eq $port }).Count) { return "El puerto $port ya esta ocupado. Comproba el servidor abierto." }
    return $null
}
function Start-Server {
    if ($null -ne $script:bridge) { return }
    try {
        $blocker=Get-StartBlocker
        if ($blocker) { Append-Console $blocker ([Drawing.Color]::Gold); $phaseLabel.Text=$blocker; return }
        if (-not (Test-Path -LiteralPath $script:javaExe)) { throw "No se encontro Java: $script:javaExe" }
        if (-not (Test-Path -LiteralPath (Join-Path $script:serverRoot $script:serverJar))) { throw "No se encontro $script:serverJar" }
        $logDir=Join-Path $script:serverRoot 'logs'
        [void][IO.Directory]::CreateDirectory($logDir)
        $script:readySeen=$false
        $script:closeWhenStopped=$false
        $script:lineCount=0
        $script:warningCount=0
        $script:errorCount=0
        $script:lastExitCode=$null
        $script:cpuSample=$null
        $script:startedAt=[DateTime]::Now
        $script:lastOutputAt=$script:startedAt
        $script:lastStatsAt=[DateTime]::MinValue
        $script:bridge=New-Object Horizons.Panel.ProcessBridge
        $arguments='-Xms4G -Xmx8G -XX:+UseG1GC -XX:+DisableExplicitGC "-Xlog:gc*,safepoint:file=logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10M" -jar "'+$script:serverJar+'" nogui'
        Set-ServerState 'starting'
        $phaseLabel.Text='Iniciando Java - esperando los primeros mensajes'
        Append-Console ('Iniciando HORIZONS en '+$script:serverRoot) ([Drawing.Color]::LightSkyBlue)
        Append-Console 'Heap: 4G inicial / 8G maximo. Consola completa: logs\panel-console.log' ([Drawing.Color]::LightSkyBlue)
        $script:bridge.Start($script:javaExe,$arguments,$script:serverRoot,(Join-Path $logDir 'panel-console.log'))
    } catch {
        Save-PanelError $_
        Append-Console ('Error de inicio: '+$_.Exception.Message) ([Drawing.Color]::Salmon)
        if ($null -eq $script:bridge -or $null -eq $script:bridge.Process -or $script:bridge.HasExited) {
            if ($null -ne $script:bridge) { $script:bridge.Dispose(); $script:bridge=$null }
            Set-ServerState 'failed'
        }
    }
}
function Stop-Server {
    if ($null -eq $script:bridge -or $script:bridge.HasExited -or $script:state -eq 'stopping') { return }
    try { $script:bridge.Send('stop'); Append-Console '> stop' ([Drawing.Color]::LightSkyBlue); Set-ServerState 'stopping' }
    catch { Save-PanelError $_; Append-Console ('No se pudo enviar stop: '+$_.Exception.Message) ([Drawing.Color]::Salmon); $script:closeWhenStopped=$false }
}
function Send-ServerCommand {
    if ($null -eq $script:bridge -or $script:bridge.HasExited) { return }
    $command=$commandBox.Text.Trim()
    if (-not $command) { return }
    if ($command -eq 'stop') { Stop-Server; $commandBox.Clear(); return }
    try { $script:bridge.Send($command); Append-Console ('> '+$command) ([Drawing.Color]::LightSkyBlue); $commandBox.Clear() }
    catch { Save-PanelError $_; Append-Console ('Error al enviar: '+$_.Exception.Message) ([Drawing.Color]::Salmon) }
}
function Complete-Session {
    $script:lastExitCode=$script:bridge.ExitCode
    $wasStopping=$script:state -eq 'stopping'
    Append-Console ("HORIZONS finalizo. Codigo de salida: $script:lastExitCode") ([Drawing.Color]::LightSkyBlue)
    $script:bridge.Dispose()
    $script:bridge=$null
    if ($script:lastExitCode -ne 0 -or (-not $script:readySeen -and -not $wasStopping)) {
        Set-ServerState 'failed'
        $phaseLabel.Text="Minecraft no termino normalmente. Salida: $script:lastExitCode. Revisa la consola."
        $script:closeWhenStopped=$false
    } else { Set-ServerState 'stopped'; $phaseLabel.Text="Servidor detenido. Codigo de salida: $script:lastExitCode" }
    if ($script:closeWhenStopped) { $form.Close() }
}
function Pump-Server {
    if ($null -eq $script:bridge) { return }
    foreach ($entry in $script:bridge.Drain(180)) { Handle-OutputLine $entry }
    if ($script:bridge.OutputCompleted -and $script:bridge.IsQueueEmpty) { Complete-Session; return }
    $now=[DateTime]::Now
    if (($now-$script:lastStatsAt).TotalSeconds -ge 1) {
        $script:lastStatsAt=$now
        if (-not $script:bridge.HasExited) {
            $process=$script:bridge.Process
            $process.Refresh()
            $cpuTime=$process.TotalProcessorTime.TotalSeconds
            $cpuPercent=0
            if ($null -ne $script:cpuSample) {
                $wallSeconds=($now-$script:cpuSample.Time).TotalSeconds
                if ($wallSeconds -gt 0) { $cpuPercent=[Math]::Max(0,[Math]::Min(100,100*($cpuTime-$script:cpuSample.Cpu)/$wallSeconds/[Environment]::ProcessorCount)) }
            }
            $script:cpuSample=@{Time=$now;Cpu=$cpuTime}
            $elapsed=$now-$script:startedAt
            $statsLabel.Text=('PID: {0}    RAM proceso: {1:N2} GB    CPU equipo: {2:N1}%    Tiempo: {3:00}:{4:00}:{5:00}' -f $process.Id,($process.WorkingSet64/1GB),$cpuPercent,[Math]::Floor($elapsed.TotalHours),$elapsed.Minutes,$elapsed.Seconds)
        }
        $footer.Text=('Lineas: {0}   Avisos: {1}   Errores: {2}   Ultima salida: hace {3:N0}s   Omitidas en pantalla: {4}' -f $script:lineCount,$script:warningCount,$script:errorCount,($now-$script:lastOutputAt).TotalSeconds,$script:bridge.DroppedLines)
    }
}
function Request-PanelClose($eventArgs) {
    if ($null -eq $script:bridge) { return }
    $eventArgs.Cancel=$true
    if ($script:closeWhenStopped -or $script:bridge.HasExited) { return }
    $answer=[Windows.Forms.MessageBox]::Show($form,'El servidor sigue activo. Enviar stop y cerrar cuando termine de guardar?','HORIZONS',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -eq [Windows.Forms.DialogResult]::Yes) { $script:closeWhenStopped=$true; Stop-Server }
}
$timer=New-Object Windows.Forms.Timer
$timer.Interval=100
$timer.Add_Tick({ try { Pump-Server } catch { Save-PanelError $_; Append-Console ('Error del panel: '+$_.Exception.Message) ([Drawing.Color]::Salmon) } })
$startButton.Add_Click({ Start-Server })
$stopButton.Add_Click({ Stop-Server })
$sendButton.Add_Click({ Send-ServerCommand })
$clearButton.Add_Click({ $console.Clear() })
$openLogsButton.Add_Click({
    try { Start-Process explorer.exe -ArgumentList ('"'+(Join-Path $script:serverRoot 'logs')+'"') }
    catch { Save-PanelError $_; Append-Console $_.Exception.Message ([Drawing.Color]::Salmon) }
})
$commandBox.Add_KeyDown({
    param($sender,$eventArgs)
    if ($eventArgs.KeyCode -eq [Windows.Forms.Keys]::Enter) { $eventArgs.SuppressKeyPress=$true; Send-ServerCommand }
})
$form.Add_FormClosing({ param($sender,$eventArgs) Request-PanelClose $eventArgs })
Set-ServerState 'stopped'
Append-Console 'Panel listo. Inicia el servidor para ver toda la salida en tiempo real.' ([Drawing.Color]::LightSkyBlue)
if (-not $NoShow) {
    $hasher=[Security.Cryptography.SHA256]::Create()
    $key=[BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($script:serverRoot.ToLowerInvariant()))).Replace('-','')
    $hasher.Dispose()
    $panelMutex=New-Object Threading.Mutex($false,('Local\HorizonsPanel_'+$key))
    $acquired=$false
    try { $acquired=$panelMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired=$true }
    if (-not $acquired) {
        [void][Windows.Forms.MessageBox]::Show('Ya hay un panel abierto para este servidor.','HORIZONS')
        $panelMutex.Dispose()
        $form.Dispose()
        return
    }
    try { $timer.Start(); [void]$form.ShowDialog() }
    finally { $timer.Stop(); $timer.Dispose(); $form.Dispose(); $panelMutex.ReleaseMutex(); $panelMutex.Dispose() }
}
