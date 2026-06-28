# allincodex - shared helpers
# No secrets are ever written to disk by allincodex or printed to the console.
# authorship watermark: AIC✦SH✦2026 — original work by AgenticLab-SH

# --- Authorship / provenance (do not remove) ----------------------------------
# AicAuthorCommitment is sha256(secret authorship phrase). The phrase itself is
# NOT stored anywhere in this repo. Only the original author knows the phrase and
# can prove authorship via:  allincodex verify-author "<phrase>"
$script:AicWatermark        = 'AIC' + [char]0x2726 + 'SH' + [char]0x2726 + '2026'
$script:AicAuthor          = 'AgenticLab-SH'
$script:AicAuthorCommitment = '8249db103d4b5972a6c5a488f51f9b93203b8b8405f4619bde7b20bb8e8032a7'

function Get-AicSha256Hex {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([BitConverter]::ToString($sha) -replace '-', '').ToLower()
}

function Test-AicAuthor {
    param([Parameter(Mandatory)][string]$Phrase)
    return ((Get-AicSha256Hex -Text $Phrase) -eq $script:AicAuthorCommitment)
}
# ------------------------------------------------------------------------------

$script:AicRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

function Get-AicUserConfigPath { return (Join-Path $env:USERPROFILE '.allincodex\config.json') }

function Get-AicConfig {
    $user = Get-AicUserConfigPath
    $local = Join-Path $script:AicRoot 'config\allincodex.config.json'
    $example = Join-Path $script:AicRoot 'config\allincodex.config.example.json'
    # precedence: user-home config (global installs) -> repo-local -> shipped example
    $path = if (Test-Path $user) { $user } elseif (Test-Path $local) { $local } else { $example }
    $cfg = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $cfg | Add-Member -NotePropertyName '_source' -NotePropertyValue $path -Force
    return $cfg
}

# Scaffold ~/.allincodex/config.json from the shipped example (does not overwrite).
function Initialize-AicUserConfig {
    $user = Get-AicUserConfigPath
    if (Test-Path $user) { Write-AicInfo ("user config already exists: " + $user); return $user }
    $example = Join-Path $script:AicRoot 'config\allincodex.config.example.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $user) | Out-Null
    Copy-Item -LiteralPath $example -Destination $user -Force
    Write-AicOk ("created " + $user + " — edit gateway.* and defaultModel, then run: allincodex setup")
    return $user
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
