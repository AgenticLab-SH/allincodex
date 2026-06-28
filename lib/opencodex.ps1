# allincodex - opencodex (@bitkyc08/opencodex, CLI `ocx`) orchestration
# allincodex does NOT reimplement opencodex; it installs and configures it.

function Test-OpencodexInstalled { return (Test-Command -Name 'ocx') }

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

function Get-OpencodexProxyUp {
    param([Parameter(Mandatory)]$Cfg)
    return (Test-HttpOk -Uri ("http://127.0.0.1:" + $Cfg.opencodexPort + "/healthz"))
}
