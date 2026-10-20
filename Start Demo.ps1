$ErrorActionPreference = 'Stop'
$demoRoot = $PSScriptRoot
$demoPort = 8765
$listener = Get-NetTCPConnection -LocalPort $demoPort -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    $pythonExe = (Get-Command python -ErrorAction Stop).Source
    Start-Process -FilePath $pythonExe -ArgumentList @('-m', 'http.server', "$demoPort", '--bind', '127.0.0.1', '--directory', ('"' + (Join-Path $demoRoot 'build\web') + '"')) -WorkingDirectory $demoRoot -WindowStyle Hidden
}
Start-Process "http://127.0.0.1:$demoPort"
