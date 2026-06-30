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
    [Parameter(Position = 1)][string]$Sub = '',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)

$ErrorActionPreference = 'Stop'
$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
. (Join-Path $libDir 'common.ps1')
. (Join-Path $libDir 'gateway.ps1')
. (Join-Path $libDir 'opencodex.ps1')
. (Join-Path $libDir 'autostart.ps1')
. (Join-Path $libDir 'upstream.ps1')

function Show-Help {
    @"
allincodex - one-command orchestrator for Codex + opencodex + local gateways

Usage:
  allincodex init
  allincodex setup
  allincodex start
  allincodex status | doctor
  allincodex upstream check [--json]
  allincodex upstream sync [--json]
  allincodex update opencodex
  allincodex update kiro-gateway
  allincodex autostart install|uninstall
  allincodex restore
  allincodex about
"@
}

function Invoke-About {
    Write-Host ('allincodex ' + $script:AicWatermark)
    Write-Host ('  author     : ' + $script:AicAuthor)
    Write-Host ('  commitment : sha256 ' + $script:AicAuthorCommitment)
    Write-Host ('  prove it   : allincodex verify-author "<secret phrase>"')
    Write-Host ('  upstream   : https://github.com/AgenticLab-SH/allincodex')
}

function Invoke-Doctor {
    param($Cfg)
    Write-Host ('  build : ' + $script:AicWatermark + ' by ' + $script:AicAuthor)
    Write-AicInfo ("config source: " + $Cfg._source)
    Write-Host ("  opencodex version : " + (Get-OpencodexVersion))
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
    if (-not (Test-OpencodexInstalled)) { Write-AicErr 'opencodex not installed. Run: allincodex setup'; return }
    if (Test-OpencodexCommand -Subcommand 'ensure') {
        Write-AicInfo 'ensuring opencodex proxy + Codex cache (ocx ensure) ...'
        ocx ensure 2>&1 | Select-Object -Last 6 | ForEach-Object { Write-Host ("  " + $_) }
    }
    elseif (-not (Get-OpencodexProxyUp -Cfg $Cfg)) {
        Write-AicInfo 'starting opencodex proxy (detached, legacy path) ...'
        Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', 'ocx start') -WindowStyle Hidden
    }
    for ($i = 0; $i -lt 30; $i++) {
        if (Get-OpencodexProxyUp -Cfg $Cfg) { break }
        Start-Sleep -Milliseconds 700
    }
    if (Get-OpencodexProxyUp -Cfg $Cfg) { Write-AicOk 'opencodex proxy healthy' } else { Write-AicWarn 'opencodex proxy did not come up' }
    if (Test-OpencodexCommand -Subcommand 'sync-cache') { Invoke-OpencodexSyncCache } else { Invoke-OpencodexSync }
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
    'init' { [void](Initialize-AicUserConfig) }
    'start' { Invoke-Start -Cfg $cfg }
    'status' { Invoke-Doctor -Cfg $cfg }
    'doctor' { Invoke-Doctor -Cfg $cfg }
    'restore' { Invoke-Restore -Cfg $cfg }
    'upstream' {
        switch ($Sub.ToLower()) {
            'check' { Invoke-AicUpstreamCheck -AsJson:($Rest -contains '--json') }
            'sync' { Invoke-AicUpstreamSync -AsJson:($Rest -contains '--json') }
            default { Write-AicErr 'usage: allincodex upstream <check|sync> [--json]' }
        }
    }
    'update' {
        switch ($Sub.ToLower()) {
            'opencodex' { Invoke-OpencodexUpdate }
            'kiro-gateway' { Invoke-AicKiroGatewayUpdate -Cfg $cfg }
            default { Write-AicErr 'usage: allincodex update <opencodex|kiro-gateway>' }
        }
    }
    'version' { Invoke-About }
    'about' { Invoke-About }
    'verify-author' {
        if (-not $Sub) { Write-AicErr 'usage: allincodex verify-author "<phrase>"'; break }
        if (Test-AicAuthor -Phrase $Sub) {
            Write-AicOk ('AUTHOR VERIFIED - ' + $script:AicAuthor + ' (' + $script:AicWatermark + ')')
        }
        else {
            Write-AicErr 'author verification FAILED (phrase does not match commitment)'
        }
    }
    'autostart' {
        switch ($Sub.ToLower()) {
            'install' { Install-GatewayAutostart -Cfg $cfg; if ($cfg.autostart.opencodexService) { Install-OpencodexAutostart } }
            'uninstall' { Uninstall-GatewayAutostart }
            default { Write-AicErr 'usage: allincodex autostart <install|uninstall>' }
        }
    }
    default { Show-Help }
}
