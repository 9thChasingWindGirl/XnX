# XnX: fetch the artifacts published by each source repo's CI.
#
# Each repo builds its own output on main and uploads it as an artifact named
# `<prefix><commit-sha>`. The build repo only downloads and packages, so it no
# longer recompiles wasm, the UI bundle or the shell.
#
# Provenance is recorded in bundle/build-manifest.json so a release can be
# traced back to the exact commits that produced it.
$ErrorActionPreference = 'Stop'

$Org = if ($env:BUILD_ORG) { $env:BUILD_ORG } else { '9thChasingWindGirl' }
$Root = Split-Path -Parent $PSScriptRoot

$Specs = @(
    @{ Repo = 'XnX_ui'; Prefix = 'ui-build-'; Dest = 'bundle\ui' },
    @{ Repo = 'XnX_shell'; Prefix = 'shell-exe-'; Dest = 'shell\target\x86_64-pc-windows-msvc\release' }
)

$manifest = [ordered]@{ builtAt = (Get-Date).ToUniversalTime().ToString('o'); artifacts = @() }

foreach ($spec in $Specs) {
    $artifacts = gh api "repos/$Org/$($spec.Repo)/actions/artifacts?per_page=100" | ConvertFrom-Json
    $artifact = $artifacts.artifacts |
        Where-Object { -not $_.expired -and $_.name.StartsWith($spec.Prefix) } |
        Sort-Object created_at -Descending |
        Select-Object -First 1

    if (-not $artifact) { throw "no artifact '$($spec.Prefix)*' in $($spec.Repo)" }

    $sha = $artifact.name.Substring($spec.Prefix.Length)
    Write-Host "== $($spec.Repo): $($artifact.name) (run $($artifact.workflow_run.id))"

    $tmp = Join-Path $Root '.artifact-tmp'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    gh run download $artifact.workflow_run.id -R "$Org/$($spec.Repo)" -n $artifact.name -D $tmp
    if ($LASTEXITCODE -ne 0) { throw "download failed: $($artifact.name)" }

    $dest = Join-Path $Root $spec.Dest
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item (Join-Path $tmp '*') $dest -Recurse -Force
    Remove-Item $tmp -Recurse -Force

    $manifest.artifacts += [ordered]@{
        repo = $spec.Repo
        artifact = $artifact.name
        commit = $sha
        runId = $artifact.workflow_run.id
        dest = $spec.Dest
    }
}

# Guard rails: the bundle must contain a real UI and the wasm next to index.html.
if (-not (Test-Path (Join-Path $Root 'bundle\ui\index.html'))) { throw 'artifact bundle missing ui/index.html' }
if (-not (Test-Path (Join-Path $Root 'bundle\ui\stremio_core_web_bg.wasm'))) { throw 'artifact bundle missing core wasm' }
if (-not (Test-Path (Join-Path $Root 'shell\target\x86_64-pc-windows-msvc\release\stremio-shell-ng.exe'))) {
    throw 'artifact bundle missing shell exe'
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Root 'bundle\build-manifest.json') -Encoding utf8
Write-Host "artifacts staged: $($manifest.artifacts.Count)"
foreach ($entry in $manifest.artifacts) { Write-Host "  $($entry.repo) @ $($entry.commit)" }
