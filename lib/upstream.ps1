# allincodex - upstream watcher helpers for opencodex and local gateways
# authorship watermark: AIC-SH-2026 - original work by AgenticLab-SH

function Get-AicUpstreamConfigPath {
    return (Join-Path $script:AicRoot 'config\upstreams.json')
}

function Resolve-AicProjectPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $script:AicRoot $Path)
}

function Get-AicUpstreamConfig {
    $path = Get-AicUpstreamConfigPath
    if (-not (Test-Path -LiteralPath $path)) { throw "missing upstream config: $path" }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Get-AicGitRemoteHead {
    param([Parameter(Mandatory)][string]$Repo)
    if (-not (Test-Command -Name 'git')) { return $null }
    $line = (& git ls-remote $Repo HEAD 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $line) { return $null }
    return (($line -split '\s+')[0])
}

function Get-AicGitLocalState {
    param([string]$Path)
    if (-not $Path) { return $null }
    $dir = Resolve-AicProjectPath -Path $Path
    if (-not (Test-Path -LiteralPath (Join-Path $dir '.git'))) {
        return [pscustomobject]@{ path = $dir; exists = $false; head = $null; dirty = $null; dirtyFiles = @(); branch = $null }
    }
    $head = (& git -C $dir rev-parse HEAD 2>$null)
    $branch = (& git -C $dir rev-parse --abbrev-ref HEAD 2>$null)
    $dirtyFiles = @(& git -C $dir status --short 2>$null)
    $dirty = [bool]($dirtyFiles)
    return [pscustomobject]@{ path = $dir; exists = $true; head = $head; dirty = $dirty; dirtyFiles = $dirtyFiles; branch = $branch }
}

function Get-AicNpmPackageState {
    param([Parameter(Mandatory)][string]$Package)
    if (-not (Test-Command -Name 'npm')) { return $null }
    $raw = (& npm view $Package version time repository.url dist-tags --json 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function Get-AicOpencodexLocalVersion {
    if (-not (Test-Command -Name 'ocx')) { return $null }
    $raw = (& ocx --version 2>$null | Select-Object -First 1)
    if ($raw -match '(\d+\.\d+\.\d+(?:[-+][^\s]+)?)') { return $Matches[1] }
    return $raw
}

function Compare-AicVersionText {
    param([string]$Left, [string]$Right)
    try {
        $l = [version](($Left -split '[-+]')[0])
        $r = [version](($Right -split '[-+]')[0])
        return $l.CompareTo($r)
    } catch {
        return [string]::Compare($Left, $Right, $true)
    }
}

function Get-AicUpstreamStatus {
    $cfg = Get-AicUpstreamConfig
    $items = @()
    foreach ($u in @($cfg.upstreams)) {
        $npm = $null
        if ($u.package) { $npm = Get-AicNpmPackageState -Package $u.package }
        $remoteHead = if ($u.repo) { Get-AicGitRemoteHead -Repo $u.repo } else { $null }
        $localClone = Get-AicGitLocalState -Path $u.localClone
        $cacheClone = Get-AicGitLocalState -Path $u.cacheClone
        $localVersion = if ($u.id -eq 'opencodex') { Get-AicOpencodexLocalVersion } else { $null }
        $latestVersion = if ($npm) { $npm.version } else { $null }
        $versionDrift = $false
        if ($localVersion -and $latestVersion) {
            $versionDrift = ((Compare-AicVersionText -Left $localVersion -Right $latestVersion) -lt 0)
        }
        $gitDrift = $false
        if ($remoteHead -and $localClone -and $localClone.exists -and $localClone.head) {
            $gitDrift = ($remoteHead -ne $localClone.head)
        }
        $items += [pscustomobject]@{
            id             = $u.id
            package        = $u.package
            repo           = $u.repo
            latestVersion  = $latestVersion
            localVersion   = $localVersion
            npmModifiedUtc = if ($npm -and $npm.time) { $npm.time.modified } else { $null }
            remoteHead     = $remoteHead
            localClone     = $localClone
            cacheClone     = $cacheClone
            versionDrift   = $versionDrift
            gitDrift       = $gitDrift
            dirtyLocal     = if ($localClone) { $localClone.dirty } else { $null }
            notes          = $u.notes
        }
    }
    return [pscustomobject]@{
        checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        upstreams    = $items
    }
}

function Update-AicTodoFromUpstreamStatus {
    param([Parameter(Mandatory)]$Status)
    $cfg = Get-AicUpstreamConfig
    $todo = Resolve-AicProjectPath -Path $cfg.todoFile
    $start = '<!-- allincodex-upstream-status:start -->'
    $end = '<!-- allincodex-upstream-status:end -->'
    $lines = @(
        $start,
        '',
        '## Upstream Watch',
        '',
        ('Last checked: ' + $Status.checkedAtUtc),
        ''
    )
    foreach ($u in @($Status.upstreams)) {
        $actions = @()
        if ($u.versionDrift) { $actions += ('update opencodex local ' + $u.localVersion + ' -> ' + $u.latestVersion) }
        if ($u.gitDrift) { $actions += 'fetch/review git upstream delta' }
        if ($u.dirtyLocal) {
            $files = @($u.localClone.dirtyFiles) -join ', '
            if ($files) { $actions += ('preserve and review local dirty changes before pulling (' + $files + ')') }
            else { $actions += 'preserve and review local dirty changes before pulling' }
        }
        if (-not $u.cacheClone.exists) { $actions += 'download source cache with allincodex upstream sync' }
        if ($actions.Count -eq 0) { $actions += 'watch' }
        $lines += ('- [' + $u.id + '] ' + ($actions -join '; '))
    }
    $lines += @('', $end, '')
    $block = ($lines -join "`r`n")
    if (Test-Path -LiteralPath $todo) {
        $raw = Get-Content -LiteralPath $todo -Raw
        $pattern = [regex]::Escape($start) + '(?s).*?' + [regex]::Escape($end)
        if ($raw -match $pattern) {
            $raw = [regex]::Replace($raw, $pattern, $block)
        }
        else {
            $raw = $raw.TrimEnd() + "`r`n`r`n" + $block
        }
    }
    else {
        $raw = "# TODO`r`n`r`nThis file is intentionally project-local so future agents can see upstream follow-up work.`r`n`r`n" + $block
    }
    Set-Content -LiteralPath $todo -Value ($raw.TrimEnd() + "`r`n") -Encoding utf8
    return $todo
}

function Invoke-AicUpstreamCheck {
    param([switch]$AsJson)
    $status = Get-AicUpstreamStatus
    [void](Update-AicTodoFromUpstreamStatus -Status $status)
    if ($AsJson) { $status | ConvertTo-Json -Depth 8; return }
    $status.upstreams | Select-Object id, localVersion, latestVersion, versionDrift, gitDrift, dirtyLocal, remoteHead |
        Format-Table -AutoSize
    Write-AicInfo ("updated TODO from upstream status")
}

function Invoke-AicUpstreamSync {
    param([switch]$AsJson)
    $cfg = Get-AicUpstreamConfig
    $results = @()
    foreach ($u in @($cfg.upstreams)) {
        if (-not $u.repo -or -not $u.cacheClone) { continue }
        $dir = Resolve-AicProjectPath -Path $u.cacheClone
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
            if ($AsJson) { & git -C $dir fetch --tags --prune origin 2>&1 | Out-Null }
            else { & git -C $dir fetch --tags --prune origin 2>&1 | Select-Object -Last 4 | ForEach-Object { Write-Host "  $_" } }
            $head = (& git -C $dir rev-parse HEAD 2>$null)
            $results += [pscustomobject]@{ id = $u.id; action = 'fetch'; path = $dir; head = $head }
        }
        else {
            New-Item -ItemType Directory -Force -Path (Split-Path $dir) | Out-Null
            if ($AsJson) { & git clone --depth 1 $u.repo $dir 2>&1 | Out-Null }
            else { & git clone --depth 1 $u.repo $dir 2>&1 | Select-Object -Last 4 | ForEach-Object { Write-Host "  $_" } }
            $head = (& git -C $dir rev-parse HEAD 2>$null)
            $results += [pscustomobject]@{ id = $u.id; action = 'clone'; path = $dir; head = $head }
        }
    }
    $status = Get-AicUpstreamStatus
    [void](Update-AicTodoFromUpstreamStatus -Status $status)
    $out = [pscustomobject]@{ syncedAtUtc = (Get-Date).ToUniversalTime().ToString('o'); results = $results; status = $status }
    if ($AsJson) { $out | ConvertTo-Json -Depth 8; return }
    $results | Format-Table -AutoSize
    Write-AicInfo ("updated TODO from synced upstream status")
}

function Invoke-AicKiroGatewayUpdate {
    param([Parameter(Mandatory)]$Cfg)
    $watch = (Get-AicUpstreamConfig).upstreams | Where-Object { $_.id -eq 'kiro-gateway' } | Select-Object -First 1
    if (-not $watch -or -not $watch.localClone) {
        Write-AicErr 'kiro-gateway localClone is not configured in config/upstreams.json'
        return
    }
    $dir = Resolve-AicProjectPath -Path $watch.localClone
    if (-not (Test-Path -LiteralPath (Join-Path $dir '.git'))) {
        Write-AicErr ("kiro-gateway clone missing: " + $dir)
        return
    }
    $dirty = [bool]((& git -C $dir status --short 2>$null))
    if ($dirty) {
        Write-AicWarn ("kiro-gateway has local changes; refusing to pull: " + $dir)
        Write-AicInfo 'review/commit/stash those changes first, then retry allincodex update kiro-gateway'
        return
    }
    Write-AicInfo 'fetching kiro-gateway upstream ...'
    & git -C $dir fetch --tags --prune origin 2>&1 | Select-Object -Last 4 | ForEach-Object { Write-Host ("  " + $_) }
    $before = (& git -C $dir rev-parse HEAD 2>$null)
    $remote = (& git -C $dir rev-parse origin/main 2>$null)
    if ($before -eq $remote) {
        Write-AicOk ("kiro-gateway already at origin/main: " + $before)
    }
    else {
        Write-AicInfo 'pulling kiro-gateway with --ff-only ...'
        & git -C $dir pull --ff-only 2>&1 | Select-Object -Last 8 | ForEach-Object { Write-Host ("  " + $_) }
        if ($LASTEXITCODE -ne 0) { Write-AicErr 'git pull --ff-only failed'; return }
        $after = (& git -C $dir rev-parse HEAD 2>$null)
        Write-AicOk ("kiro-gateway updated: " + $before + " -> " + $after)
        if ($Cfg.gateway.wrapperScript -and (Test-Path -LiteralPath $Cfg.gateway.wrapperScript)) {
            Write-AicInfo 'reinstalling gateway dependencies via configured wrapper ...'
            pwsh -NoProfile -File $Cfg.gateway.wrapperScript -Action install | Select-Object -Last 8 | ForEach-Object { Write-Host ("  " + $_) }
            if (Test-GatewayUp -Cfg $Cfg) {
                Write-AicInfo 'gateway was running; restarting on configured port ...'
                pwsh -NoProfile -File $Cfg.gateway.wrapperScript -Action restart -Port $Cfg.gateway.port | Select-Object -Last 8 | ForEach-Object { Write-Host ("  " + $_) }
            }
        }
    }
    $status = Get-AicUpstreamStatus
    [void](Update-AicTodoFromUpstreamStatus -Status $status)
}
