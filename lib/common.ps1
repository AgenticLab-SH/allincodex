# allincodex - shared helpers
# No secrets are ever written to disk by allincodex or printed to the console.
# authorship watermark: AIC✦SH✦2026 — original work by AgenticLab-SH

$script:AicRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

function Get-AicConfig {
    $local = Join-Path $script:AicRoot 'config\allincodex.config.json'
    $example = Join-Path $script:AicRoot 'config\allincodex.config.example.json'
    $path = if (Test-Path $local) { $local } else { $example }
    $cfg = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $cfg | Add-Member -NotePropertyName '_source' -NotePropertyValue $path -Force
    return $cfg
}

function Test-HttpOk {
    param([Parameter(Mandatory)][string]$Uri, [int]$TimeoutSec = 3)
    try { Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSec | Out-Null; return $true }
    catch { return $false }
}

function Write-AicInfo { param([string]$Msg) Write-Host ("[allincodex] " + $Msg) }
function Write-AicWarn { param([string]$Msg) Write-Host ("[allincodex] WARN " + $Msg) -ForegroundColor Yellow }
function Write-AicErr  { param([string]$Msg) Write-Host ("[allincodex] ERROR " + $Msg) -ForegroundColor Red }
function Write-AicOk   { param([string]$Msg) Write-Host ("[allincodex] OK " + $Msg) -ForegroundColor Green }

# Resolve the gateway API key WITHOUT printing it. Order:
# 1) environment variable named by gateway.apiKeyEnvVar
# 2) PROXY_API_KEY in gateway.kiroGatewayEnvFile
# Returns $null if not found. Callers must never echo the value.
function Resolve-GatewayKey {
    param([Parameter(Mandatory)]$Gateway)
    if ($Gateway.apiKeyEnvVar) {
        $v = [Environment]::GetEnvironmentVariable($Gateway.apiKeyEnvVar)
        if ($v) { return $v }
    }
    if ($Gateway.kiroGatewayEnvFile -and (Test-Path -LiteralPath $Gateway.kiroGatewayEnvFile)) {
        $m = Select-String -LiteralPath $Gateway.kiroGatewayEnvFile -Pattern '^\s*PROXY_API_KEY\s*=\s*"?([^"]+)"?\s*$' | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return $null
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}
