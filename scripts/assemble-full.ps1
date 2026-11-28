# XnX full assemble — checkout/build all source repos into one bundle.
# Runs in GitHub Actions (build repo XnX). Locally it only stages sources.
# Requires repos: XnX_core, XnX_ui, XnX_providers, XnX_shell (private, same org).
$ErrorActionPreference = 'Stop'
$Org = $env:BUILD_ORG
if (-not $Org) { $Org = '9thChasingWindGirl' }
$Root = Get-Location
# Fast path: the workflow already downloaded built artifacts, so only the
# providers source tree needs staging here.
$StageOnly = $env:XNX_STAGE_ONLY -eq '1'

# Configure git auth for the private repos. GH_TOKEN alone is NOT picked up by
# bare `git clone` — we must install an Authorization extraheader. GitHub
# Actions masks the token in logs automatically.
$token = $env:GH_TOKEN
if ($token) {
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
    git config --global "http.https://github.com/.extraheader" "AUTHORIZATION: basic $basic"
    Write-Host 'git auth configured for github.com'
} else {
    Write-Host 'WARNING: GH_TOKEN empty; private repos may fail to clone'
}
$Repos = @(
    @{ Name = 'core';      Repo = 'XnX_core' },
    @{ Name = 'ui';        Repo = 'XnX_ui' },
    @{ Name = 'providers'; Repo = 'XnX_providers' },
    @{ Name = 'shell';     Repo = 'XnX_shell' }
)

foreach ($r in $Repos) {
    if ($StageOnly -and $r.Name -ne 'providers') {
        Write-Host "=== stage-only: skip $($r.Repo) ==="
        continue
    }
    $dest = Join-Path $Root $r.Name
    # XnX: pin the exact ref per repo so a build is reproducible. Set
    # BUILD_REF_CORE / BUILD_REF_UI / BUILD_REF_SHELL / BUILD_REF_PROVIDERS
    # to a tag (or branch) to override; defaults to main.
    $refVar = "BUILD_REF_$($r.Name.ToUpper())"
    $ref = [Environment]::GetEnvironmentVariable($refVar)
    if (-not $ref) { $ref = 'main' }
    Write-Host "=== checkout $($r.Repo)@$ref -> $($r.Name) ==="
    # XnX: the providers repo is meant to be public (people may write their own
    # XnX addons), and a scoped PAT header makes GitHub reject a public clone
    # with HTTP 400. Drop the header for that one clone and restore it after.
    $restoreAuth = $false
    if ($r.Name -eq 'providers' -and $token) {
        git config --global --unset-all "http.https://github.com/.extraheader" 2>$null
        $restoreAuth = $true
    }
    git clone --depth 1 --branch $ref "https://github.com/$Org/$($r.Repo).git" $dest
    $cloneExit = $LASTEXITCODE
    if ($restoreAuth) {
        git config --global "http.https://github.com/.extraheader" "AUTHORIZATION: basic $basic"
    }
    if ($cloneExit -ne 0) { throw "clone failed: $($r.Repo)@$ref" }
    git -C $dest rev-parse HEAD | ForEach-Object { Write-Host "$($r.Name) HEAD $_" }
}

# providers is pure Node.js — no build, BUT stage only runtime files.
# Never copy the whole source tree: that leaks .git/ history, docs, tests and
# tools into the shipped bundle.
$src = Join-Path $Root 'providers'
$dst = Join-Path $Root 'bundle\providers'
New-Item -ItemType Directory -Force $dst | Out-Null
# top-level runtime entrypoints
foreach ($f in @('server.js', 'core.js', 'theme.json', 'index.html')) {
    Copy-Item (Join-Path $src $f) $dst -Force
}
# runtime modules, addons, assets, optional extra bridge
foreach ($dir in @('core', 'addons', 'assets', 'extra')) {
    Copy-Item (Join-Path $src $dir) $dst -Recurse -Force
}
# strip any dev-only files that may hide inside the staged dirs
Get-ChildItem $dst -Recurse -File | Where-Object {
    $_.Name -match '\.(md|log)$' -or $_.FullName -match '[\\/](tests?|tools|\.github)[\\/]'
} | Remove-Item -Force
Write-Host "providers staged: $((Get-ChildItem $dst -Recurse -File).Count) runtime files (no .git/docs/tests)"

if ($StageOnly) {
    # Fast path: core-web wasm and the UI bundle are produced by each repo's
    # own CI and downloaded by the workflow; only source staging happens here.
    Write-Host '=== stage-only mode: skipping core-web wasm + UI build ==='
} else {
    # core-web WASM -> npm package. Our fork's endpoint-free streaming_server
    # model MUST reach the UI, so UI must consume OUR core-web, not the npm one.
    Write-Host '=== build core-web WASM (wasm-pack) ==='
    Push-Location (Join-Path $Root 'core\stremio-core-web')
    # babel CLI + presets are devDependencies; without npm ci, `npx babel`
    # silently fetches ancient babel@5 which cannot read .babelrc presets.
    & npm ci
    if ($LASTEXITCODE -ne 0) { throw 'core-web npm ci failed' }
    & rustup target add wasm32-unknown-unknown
    & wasm-pack build --no-typescript --no-pack --out-dir wasm_build --release --target web
    if ($LASTEXITCODE -ne 0) { throw 'core-web wasm-pack build failed' }
    # match upstream build.sh: relocate wasm + babel the JS glue
    Move-Item .\wasm_build\stremio_core_web_bg.wasm .\stremio_core_web_bg.wasm -Force
    & npx babel .\wasm_build\stremio_core_web.js --config-file .\.babelrc --out-file .\stremio_core_web.js
    & npx babel .\src\bridge.js --config-file .\.babelrc --out-file .\bridge.js
    & npx babel .\src\worker.js --config-file .\.babelrc --out-file .\worker.js
    if ($LASTEXITCODE -ne 0) { throw 'core-web babel failed' }
    Pop-Location

    # UI: @stremio/stremio-core-web is declared as `file:./vendor/core-web`, so our
    # freshly built package is staged there before the UI installs anything.
    Write-Host '=== stage our core-web into ui/vendor/core-web ==='
    $coreWebSrc = Join-Path $Root 'core\stremio-core-web'
    $coreWebDst = Join-Path $Root 'ui\vendor\core-web'
    if (Test-Path $coreWebDst) { Remove-Item $coreWebDst -Recurse -Force }
    New-Item -ItemType Directory -Force $coreWebDst | Out-Null
    Copy-Item (Join-Path $coreWebSrc 'package.json') $coreWebDst -Force
    Copy-Item (Join-Path $coreWebSrc '*.js') $coreWebDst -Force
    Copy-Item (Join-Path $coreWebSrc '*.wasm') $coreWebDst -Force
    Copy-Item (Join-Path $coreWebSrc '*.d.ts') $coreWebDst -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path (Join-Path $coreWebDst 'stremio_core_web_bg.wasm'))) { throw 'core-web staging failed' }

    Write-Host '=== build UI (with our core-web) ==='
    Push-Location (Join-Path $Root 'ui')
    & corepack enable
    & pnpm install --no-frozen-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'UI install failed' }
    & pnpm run build
    if ($LASTEXITCODE -ne 0) { throw 'UI build failed' }
    Pop-Location
    New-Item -ItemType Directory -Force (Join-Path $Root 'bundle\ui') | Out-Null
    Copy-Item (Join-Path $Root 'ui\build\*') (Join-Path $Root 'bundle\ui') -Recurse -Force
    # XnX: the UI now runs core on the main thread and reads the wasm straight from
    # disk (no worker, no fetch), so the wasm must ship next to index.html. webpack
    # no longer emits it as an asset once the worker entry is gone.
    Copy-Item (Join-Path $Root 'core\stremio-core-web\stremio_core_web_bg.wasm') (Join-Path $Root 'bundle\ui\stremio_core_web_bg.wasm') -Force
}

# XnX: prove the shipped core is OUR fork, not the npm package. `@stremio/stremio-core-web`
# in ui/package.json is only a placeholder — the UI is built against
# core/stremio-core-web via `pnpm add file:` above. This marker exists only in
# our fork, so a mismatch means the placeholder leaked into the bundle.
$shippedWasm = Join-Path $Root 'bundle\ui\stremio_core_web_bg.wasm'
$wasmText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($shippedWasm))
if (-not $wasmText.Contains('invalid addon url')) {
    throw 'bundle core-web is not the XnX fork (marker "invalid addon url" missing)'
}
Write-Host "core-web verified: XnX fork in bundle ($((Get-Item $shippedWasm).Length) bytes)"
Write-Host "ui wasm staged: $((Get-Item (Join-Path $Root 'bundle\ui\stremio_core_web_bg.wasm')).Length) bytes"

Write-Host "bundle staged: $((Get-ChildItem (Join-Path $Root 'bundle') -Recurse -File).Count) files"
