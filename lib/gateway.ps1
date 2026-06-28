# allincodex - local OpenAI-compatible gateway lifecycle (reference: kiro-gateway)
# authorship watermark: AIC✦SH✦2026 — original work by AgenticLab-SH

function Test-GatewayUp {
    param([Parameter(Mandatory)]$Cfg)
    return (Test-HttpOk -Uri $Cfg.gateway.healthUrl)
}

function Start-Gateway {
    param([Parameter(Mandatory)]$Cfg)
    if (Test-GatewayUp -Cfg $Cfg) { Write-AicInfo 'gateway already healthy'; return $true }
    $wrapper = $Cfg.gateway.wrapperScript
    if (-not (Test-Path -LiteralPath $wrapper)) {
        Write-AicErr ("gateway wrapper not found: " + $wrapper)
        return $false
    }
    Write-AicInfo ("starting gateway on port " + $Cfg.gateway.port + " ...")
    pwsh -NoProfile -File $wrapper -Action start -Port $Cfg.gateway.port | Out-Null
    for ($i = 0; $i -lt 20; $i++) {
        if (Test-GatewayUp -Cfg $Cfg) { Write-AicOk 'gateway healthy'; return $true }
        Start-Sleep -Milliseconds 600
    }
    Write-AicWarn 'gateway did not become healthy within timeout'
    return $false
}
