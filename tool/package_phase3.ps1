$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$release = Join-Path $taskRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath (Join-Path $release 'fap_helper_v1.exe'))) {
    throw 'Build Windows release before packaging.'
}
$binary = Join-Path $release 'cloudflared.exe'
$expected = '2837888cc0f5d58f15b6dc478376de90b4d3ba5241c7947455d1e0a0df429712'
if (-not (Test-Path -LiteralPath $binary)) {
    Invoke-WebRequest -Uri 'https://github.com/cloudflare/cloudflared/releases/download/2026.9.1/cloudflared-windows-amd64.exe' -OutFile "$binary.download"
    if ((Get-FileHash -LiteralPath "$binary.download" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
        throw 'Cloudflared checksum mismatch; download not installed.'
    }
    Move-Item -LiteralPath "$binary.download" -Destination $binary
}
if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Cloudflared checksum mismatch; package not created.'
}
Copy-Item -LiteralPath (Join-Path $taskRoot 'docs\third-party-cloudflared.txt') -Destination $release
Copy-Item -LiteralPath (Join-Path $taskRoot 'docs\phase-3.md') -Destination (Join-Path $release 'HUONG-DAN-PHASE-3.md')
Copy-Item -LiteralPath (Join-Path $taskRoot 'docs\vercel-setup.md') -Destination (Join-Path $release 'vercel-setup.md')
Compress-Archive -Path (Join-Path $release '*') -DestinationPath (Join-Path $taskRoot 'build\FAPHelper-Phase3-Windows-x64.zip') -Force
Get-Item -LiteralPath (Join-Path $taskRoot 'build\FAPHelper-Phase3-Windows-x64.zip') | Select-Object FullName, Length
