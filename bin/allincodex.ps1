#!/usr/bin/env pwsh
# allincodex - one-command orchestrator to use Kiro Gateway (or any local
# OpenAI-compatible gateway) models inside the official Codex Desktop/CLI,
# via the opencodex proxy. Windows-first.
#
# Usage:
#   allincodex setup                 install + configure + sync (run once)
#   allincodex start                 bring gateway + proxy up, sync models
#   allincodex status | doctor       read-only health report
#   allincodex autostart install     logon autostart (gateway + opencodex service)
#   allincodex autostart uninstall   remove logon autostart
#   allincodex restore               stop proxy + gateway, restore vanilla Codex
#   allincodex help

param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Sub = ''
)

$ErrorActionPreference = 'Stop'
$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
. (Join-Path $libDir 'common.ps1')
. (Join-Path $libDir 'gateway.ps1')
. (Join-Path $libDir 'opencodex.ps1')
. (Join-Path $libDir 'autostart.ps1')

function Show-Help {
    Get-Content -LiteralPath $PSCommandPath | Select-Object -First 18 | ForEach-Object { $_ -replace '^#\s?', '' } | Select-Object -Skip 1
}

function Invoke-Doctor {
    param($Cfg)
    Write-AicInfo ("config source: " + $Cfg._source)
    $gw = Test-GatewayUp -Cfg $Cfg
    $px = Get-OpencodexProxyUp -Cfg $Cfg
    Write-Host ("  gateway " + $Cfg.gateway.healthUrl + " : " + $(if ($gw) { 'OK' } else { 'DOWN' }))
    Write-Host ("  opencodex proxy :" + $Cfg.opencodexPort + " : " + $(if ($px) { 'OK' } else { 'DOWN' }))
    Write-Host ("  opencodex CLI (ocx) installed : " + (Test-OpencodexInstalled))
    # Codex config injection (read-only)
    $codexCfg = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (Test-Path $codexCfg) {
        $prov = (Select-String -LiteralPath $codexCfg -Pattern '^\s*model_provider\s*=\s*"([^"]+)"' | Select-Object -First 1)
        $provVal = if ($prov) { $prov.Matches[0].Groups[1].Value } else { '(default openai)' }
        Write-Host ("  Codex model_provider : " + $provVal)
    }
    $gwVbs = Get-GatewayVbsPath
    Write-Host ("  gateway logon autostart : " + (Test-Path $gwVbs))
    if (-not $gw) { Write-AicWarn 'gateway down -> kiro models will not respond. Run: allincodex start' }
    if (-not $px) { Write-AicWarn 'proxy down -> Codex cannot reach models. Run: allincodex start' }
    if ($gw -and $px) { Write-AicOk 'core path healthy (gateway + proxy up)' }
}

function Invoke-Start {
    param($Cfg)
    [void](Start-Gateway -Cfg $Cfg)
    if (-not (Get-OpencodexProxyUp -Cfg $Cfg)) {
        if (-not (Test-OpencodexInstalled)) { Write-AicErr 'opencodex not installed. Run: allincodex setup'; return }
        Write-AicInfo 'starting opencodex proxy (detached) ...'
        Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', 'ocx start') -WindowStyle Hidden
        for ($i = 0; $i -lt 30; $i++) {
            if (Get-OpencodexProxyUp -Cfg $Cfg) { break }
            Start-Sleep -Milliseconds 700
        }
    }
    if (Get-OpencodexProxyUp -Cfg $Cfg) { Write-AicOk 'opencodex proxy healthy' } else { Write-AicWarn 'opencodex proxy did not come up' }
    Invoke-OpencodexSync
    Write-AicOk 'allincodex start complete. Open Codex and pick a gateway model.'
}

function Invoke-Setup {
    param($Cfg)
    Write-AicInfo 'allincodex setup'
    if (-not (Install-Opencodex)) { Write-AicErr 'opencodex install failed'; return }
    [void](Start-Gateway -Cfg $Cfg)
    [void](Set-OpencodexProvider -Cfg $Cfg)
    Invoke-Start -Cfg $Cfg
    Write-AicInfo 'For autostart on login: allincodex autostart install'
}

function Invoke-Restore {
    param($Cfg)
    Write-AicWarn 'restoring vanilla Codex (ocx stop) and stopping gateway ...'
    if (Test-OpencodexInstalled) { ocx stop 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host ("  " + $_) } }
    $wrapper = $Cfg.gateway.wrapperScript
    if (Test-Path $wrapper) { pwsh -NoProfile -File $wrapper -Action stop -Port $Cfg.gateway.port | Out-Null }
    Write-AicOk 'restored. Plain Codex uses its default provider now.'
}

$cfg = Get-AicConfig
switch ($Command.ToLower()) {
    'setup' { Invoke-Setup -Cfg $cfg }
    'start' { Invoke-Start -Cfg $cfg }
    'status' { Invoke-Doctor -Cfg $cfg }
    'doctor' { Invoke-Doctor -Cfg $cfg }
    'restore' { Invoke-Restore -Cfg $cfg }
    'autostart' {
        switch ($Sub.ToLower()) {
            'install' { Install-GatewayAutostart -Cfg $cfg; if ($cfg.autostart.opencodexService) { Install-OpencodexAutostart } }
            'uninstall' { Uninstall-GatewayAutostart }
            default { Write-AicErr 'usage: allincodex autostart <install|uninstall>' }
        }
    }
    default { Show-Help }
}
