$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $taskRoot 'deploy\student\public'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($asset in @('index.html', 'app.js', 'style.css')) {
    Copy-Item -LiteralPath (Join-Path $taskRoot "assets\student\$asset") -Destination (Join-Path $destination $asset)
}
Write-Output 'Prepared deploy\student with static student assets only. No roster, Client ID or credentials are copied.'
