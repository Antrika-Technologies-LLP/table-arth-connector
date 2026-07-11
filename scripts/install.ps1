# TableArth Connector Agent installer for Windows.
#
#   irm https://raw.githubusercontent.com/Antrika-Technologies-LLP/table-arth-connector/main/scripts/install.ps1 | iex
#
# Downloads the agent binary for this machine's architecture and installs it to
# %ProgramFiles%\table-arth-connector. Run configuration steps from docs/INSTALL.md.

$ErrorActionPreference = 'Stop'

$base = 'https://raw.githubusercontent.com/Antrika-Technologies-LLP/table-arth-connector/main/bin'
$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'amd64' }
$url  = "$base/tac-agent-windows-$arch.exe"

$dir = Join-Path $env:ProgramFiles 'table-arth-connector'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$exe = Join-Path $dir 'tac-agent.exe'

Write-Host "Downloading $url ..."
Invoke-WebRequest -Uri $url -OutFile $exe

$cfgDir = Join-Path $env:ProgramData 'table-arth-connector'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

Write-Host ""
Write-Host "Installed: $exe"
Write-Host "Next steps:"
Write-Host "  1. Create $cfgDir\config.yaml (see docs/INSTALL.md)"
Write-Host "  2. Run:  & '$exe' -config '$cfgDir\config.yaml'"
Write-Host "     or install it as a Windows service (docs/INSTALL.md)."
