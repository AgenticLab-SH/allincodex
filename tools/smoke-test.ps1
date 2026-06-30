param(
    [switch]$Network
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$cli = Join-Path $root 'bin\allincodex.ps1'

$help = & pwsh -NoProfile -ExecutionPolicy Bypass -File $cli help
if ($LASTEXITCODE -ne 0) { throw 'help command failed' }
if (($help -join "`n") -match 'param\(') { throw 'help output leaked script source' }
if (($help -join "`n") -notmatch 'upstream check') { throw 'help output missing upstream command' }
if (($help -join "`n") -notmatch 'update kiro-gateway') { throw 'help output missing kiro-gateway update command' }

$about = & pwsh -NoProfile -ExecutionPolicy Bypass -File $cli about
if ($LASTEXITCODE -ne 0) { throw 'about command failed' }
if (($about -join "`n") -notmatch 'commitment') { throw 'about output missing commitment' }

if ($Network) {
    $json = & pwsh -NoProfile -ExecutionPolicy Bypass -File $cli upstream check --json
    if ($LASTEXITCODE -ne 0) { throw 'upstream check failed' }
    $parsed = ($json -join "`n") | ConvertFrom-Json
    if (-not $parsed.upstreams -or $parsed.upstreams.Count -lt 2) { throw 'upstream check returned too few entries' }
}

Write-Host 'smoke ok'
