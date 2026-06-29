<#
  Continuum remote bootstrap (Windows / PowerShell).

  One-line install (global — once for every agent):
    irm https://raw.githubusercontent.com/AnasNafees1802/continuum/main/bootstrap.ps1 | iex

  Force all known agents (even undetected):
    $env:CONTINUUM_ALL='1'; irm https://raw.githubusercontent.com/AnasNafees1802/continuum/main/bootstrap.ps1 | iex

  Per-project install (ledger + committed adapters in the current directory):
    $env:CONTINUUM_MODE='project'; irm https://raw.githubusercontent.com/AnasNafees1802/continuum/main/bootstrap.ps1 | iex

  It downloads the repo to a temp folder and runs the matching installer, then cleans up.
#>
$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'AnasNafees1802/continuum'
$Branch = 'main'
$Mode = if ($env:CONTINUUM_MODE) { $env:CONTINUUM_MODE } else { 'global' }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("continuum-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp 'continuum.zip'
$zipUrl = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"

try {
    Write-Host "Downloading Continuum ($Branch)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $src = Join-Path $tmp "continuum-$Branch"

    if ($Mode -eq 'project') {
        $target = if ($env:CONTINUUM_TARGET) { $env:CONTINUUM_TARGET } else { (Get-Location).Path }
        & (Join-Path $src 'install.ps1') -Target $target
    }
    else {
        if ($env:CONTINUUM_ALL -eq '1') { & (Join-Path $src 'install-global.ps1') -All }
        else { & (Join-Path $src 'install-global.ps1') }
    }
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
