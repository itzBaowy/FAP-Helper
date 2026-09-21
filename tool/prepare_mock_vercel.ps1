$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $taskRoot 'deploy\mock-fap\public'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($asset in @('index.html', 'app.mjs', 'connection.mjs', 'xlsx-importer.mjs', 'style.css')) {
    Copy-Item -LiteralPath (Join-Path $taskRoot "mock-fap\public\$asset") -Destination (Join-Path $destination $asset)
}
Write-Output 'Prepared deploy\mock-fap with static assets only. No roster, CSV or connection keys are copied.'
