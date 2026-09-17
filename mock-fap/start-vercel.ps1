param(
    [Parameter(Mandatory = $true)][string]$Origin,
    [string]$Cloudflared = ''
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Can Node.js 22 tro len.' }
if (-not $Cloudflared) {
    $Cloudflared = Join-Path (Split-Path -Parent $PSScriptRoot) 'build\windows\x64\runner\Release\cloudflared.exe'
}
if (-not (Test-Path -LiteralPath $Cloudflared)) { throw 'Khong tim thay cloudflared.exe. Dung tham so -Cloudflared voi duong dan file trong goi desktop.' }
node (Join-Path $PSScriptRoot 'vercel-bridge.mjs') $Origin $Cloudflared
