$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Can Node.js 22 tro len. Cai Node.js roi chay lai start.ps1.'
}
node server.mjs
