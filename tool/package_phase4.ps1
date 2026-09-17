$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $taskRoot 'build\FAPHelper-Phase4-Mock-Extension.zip'
Compress-Archive -LiteralPath (Join-Path $taskRoot 'mock-fap'), (Join-Path $taskRoot 'extension'), (Join-Path $taskRoot 'docs\phase-4.md'), (Join-Path $taskRoot 'docs\vercel-mock-setup.md') -DestinationPath $destination -Force
Get-Item -LiteralPath $destination | Select-Object FullName, Length
