# allincodex - logon autostart management (no admin needed for the gateway part)

function Get-StartupDir { return [Environment]::GetFolderPath('Startup') }
function Get-GatewayEnsureScript { return (Join-Path $script:AicRoot 'lib\ensure-gateway.ps1') }
function Get-GatewayVbsPath { return (Join-Path (Get-StartupDir) 'allincodex-gateway-autostart.vbs') }

# Generate a standalone ensure script (so the Startup launcher does not depend on repo internals being on PATH).
function Write-GatewayEnsureScript {
    param([Parameter(Mandatory)]$Cfg)
    $p = Get-GatewayEnsureScript
    $content = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$healthUrl = '$($Cfg.gateway.healthUrl)'
`$wrapper   = '$($Cfg.gateway.wrapperScript)'
`$port      = $($Cfg.gateway.port)
try { Invoke-RestMethod -Uri `$healthUrl -TimeoutSec 3 | Out-Null; exit 0 } catch { }
if (Test-Path -LiteralPath `$wrapper) { pwsh -NoProfile -File `$wrapper -Action start -Port `$port | Out-Null }
"@
    Set-Content -LiteralPath $p -Value $content -Encoding utf8
    return $p
}

function Install-GatewayAutostart {
    param([Parameter(Mandatory)]$Cfg)
    $ensure = Write-GatewayEnsureScript -Cfg $Cfg
    $vbs = Get-GatewayVbsPath
    $vbsContent = @"
' allincodex: ensure local gateway is running at logon (hidden, no console window)
Set sh = CreateObject("WScript.Shell")
sh.Run "pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$ensure""", 0, False
"@
    Set-Content -LiteralPath $vbs -Value $vbsContent -Encoding ascii
    Write-AicOk ("gateway logon autostart installed: " + $vbs)
}

function Uninstall-GatewayAutostart {
    $vbs = Get-GatewayVbsPath
    if (Test-Path $vbs) { Remove-Item -LiteralPath $vbs -Force; Write-AicOk 'gateway logon autostart removed' }
    else { Write-AicInfo 'gateway logon autostart was not installed' }
}

# opencodex provides its own service installer (Task Scheduler on Windows). It may require admin.
function Install-OpencodexAutostart {
    Write-AicInfo 'installing opencodex service (may require an elevated shell): ocx service install'
    ocx service install 2>&1 | Select-Object -Last 4 | ForEach-Object { Write-Host ("  " + $_) }
}
