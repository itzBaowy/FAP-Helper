$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskFiles = @('index.html','app.mjs','connection.mjs','xlsx-importer.mjs','style.css','workspace.mjs','reports.mjs')
foreach ($taskTarget in @('assets\teacher','deploy\mock-fap\public')) {
    $taskDestination = Join-Path $taskRoot $taskTarget
    New-Item -ItemType Directory -Path $taskDestination -Force | Out-Null
    foreach ($taskFile in $taskFiles) {
        Copy-Item -LiteralPath (Join-Path $taskRoot "mock-fap\public\$taskFile") -Destination (Join-Path $taskDestination $taskFile)
    }
}
Write-Output 'Prepared matching teacher web and bundled assets. No roster, connection key or credentials copied.'
