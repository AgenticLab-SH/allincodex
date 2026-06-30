# allincodex - opencodex (@bitkyc08/opencodex, CLI `ocx`) orchestration
# allincodex does NOT reimplement opencodex; it installs and configures it.
# authorship watermark: AIC✦SH✦2026 — original work by AgenticLab-SH

function Test-OpencodexInstalled { return (Test-Command -Name 'ocx') }

function Get-OpencodexVersion {
    if (-not (Test-OpencodexInstalled)) { return '(not installed)' }
    $raw = (& ocx --version 2>$null | Select-Object -First 1)
    if (-not $raw) { return '(unknown)' }
    return $raw
}

function Test-OpencodexCommand {
    param([Parameter(Mandatory)][string]$Subcommand)
    if (-not (Test-OpencodexInstalled)) { return $false }
    $help = (& ocx --help 2>$null) -join "`n"
    return ($help -match ('(?m)^\s*ocx\s+' + [regex]::Escape($Subcommand) + '\b'))
}

function Install-Opencodex {
    if (Test-OpencodexInstalled) { Write-AicInfo 'opencodex already installed'; return $true }
    if (-not (Test-Command -Name 'npm')) { Write-AicErr 'npm not found (install Node 18+ first)'; return $false }
    Write-AicInfo 'installing @bitkyc08/opencodex globally ...'
    npm install -g '@bitkyc08/opencodex' 2>&1 | Out-Null
    return (Test-OpencodexInstalled)
}

# Writes ~/.opencodex/config.json with the gateway as an openai-chat provider.
# The API key is referenced via apiKeyEnv (env var) so it is NEVER stored in the file.
function Set-OpencodexProvider {
    param([Parameter(Mandatory)]$Cfg)

    $envVar = $Cfg.gateway.apiKeyEnvVar
    if (-not $envVar) { $envVar = 'ALLINCODEX_KIRO_KEY' }

    # Ensure the env var is populated for this and future sessions if we can resolve it.
    if (-not [Environment]::GetEnvironmentVariable($envVar)) {
        $key = Resolve-GatewayKey -Gateway $Cfg.gateway
        if ($key) {
            [Environment]::SetEnvironmentVariable($envVar, $key, 'User')
            [Environment]::SetEnvironmentVariable($envVar, $key, 'Process')
            Write-AicInfo ("set user env var " + $envVar + " from gateway env (value not shown)")
        }
        else {
            Write-AicWarn ("could not resolve gateway key; set " + $envVar + " manually before starting")
        }
    }

    $provider = [ordered]@{
        adapter      = 'openai-chat'
        baseUrl      = $Cfg.gateway.baseUrl
        authMode     = 'key'
        apiKeyEnv    = $envVar
        defaultModel = $Cfg.defaultModel
    }
    if ($Cfg.modelContextWindows) {
        $mcw = @{}
        foreach ($p in $Cfg.modelContextWindows.PSObject.Properties) { $mcw[$p.Name] = $p.Value }
        $provider['modelContextWindows'] = $mcw
    }

    $ocxCfgPath = Join-Path $env:USERPROFILE '.opencodex\config.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $ocxCfgPath) | Out-Null

    $cfgObj = [ordered]@{
        port            = $Cfg.opencodexPort
        defaultProvider = $Cfg.gateway.name
        providers       = [ordered]@{ }
    }
    $cfgObj.providers[$Cfg.gateway.name] = $provider

    $cfgObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ocxCfgPath -Encoding utf8
    Write-AicOk ("wrote opencodex config (no secrets): " + $ocxCfgPath)
    return $true
}

function Invoke-OpencodexSync {
    Write-AicInfo 'syncing models into Codex (ocx sync) ...'
    ocx sync 2>&1 | Select-Object -Last 4 | ForEach-Object { Write-Host ("  " + $_) }
}

function Invoke-OpencodexSyncCache {
    Write-AicInfo 'refreshing Codex model cache (ocx sync-cache) ...'
    ocx sync-cache 2>&1 | Select-Object -Last 4 | ForEach-Object { Write-Host ("  " + $_) }
}

function Invoke-OpencodexUpdate {
    if (-not (Test-OpencodexInstalled)) {
        Write-AicErr 'opencodex not installed. Run: allincodex setup'
        return
    }
    $currentRaw = Get-OpencodexVersion
    $current = if ($currentRaw -match '(\d+\.\d+\.\d+(?:[-+][^\s]+)?)') { $Matches[1] } else { $null }
    $latest = $null
    if (Test-Command -Name 'npm') {
        $latest = (& npm view '@bitkyc08/opencodex' version 2>$null | Select-Object -First 1)
    }
    if ($current -and $latest -and $current -eq $latest) {
        Write-AicOk ("opencodex already latest: " + $currentRaw)
        return
    }
    $updated = $false
    if (Test-OpencodexCommand -Subcommand 'update') {
        Write-AicInfo 'updating opencodex with ocx update ...'
        ocx update 2>&1 | Select-Object -Last 12 | ForEach-Object { Write-Host ("  " + $_) }
        $updated = ($LASTEXITCODE -eq 0)
        if (-not $updated) { Write-AicWarn 'ocx update failed; falling back to npm install -g' }
    }
    if (-not $updated) {
        Write-AicInfo 'updating opencodex with npm install -g @bitkyc08/opencodex@latest ...'
        npm install -g '@bitkyc08/opencodex@latest' 2>&1 | Select-Object -Last 12 | ForEach-Object { Write-Host ("  " + $_) }
        if ($LASTEXITCODE -ne 0) {
            Write-AicErr 'npm fallback update failed; stop opencodex/bun processes or retry after reboot if files are locked'
            return
        }
    }
    Write-AicInfo ("opencodex version now: " + (Get-OpencodexVersion))
}

function Get-OpencodexProxyUp {
    param([Parameter(Mandatory)]$Cfg)
    return (Test-HttpOk -Uri ("http://127.0.0.1:" + $Cfg.opencodexPort + "/healthz"))
}
