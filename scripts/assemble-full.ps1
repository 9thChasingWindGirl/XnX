# XnX full assemble — checkout/build all source repos into one bundle.
# Runs in GitHub Actions (build repo XnX). Locally it only stages sources.
# Requires repos: XnX_core, XnX_ui, XnX_providers, XnX_shell (private, same org).
$ErrorActionPreference = 'Stop'
$Org = $env:BUILD_ORG
if (-not $Org) { $Org = '9thChasingWindGirl' }
$Root = Get-Location
$Repos = @(
    @{ Name = 'core';      Repo = 'XnX_core' },
    @{ Name = 'ui';        Repo = 'XnX_ui' },
    @{ Name = 'providers'; Repo = 'XnX_providers' },
    @{ Name = 'shell';     Repo = 'XnX_shell' }
)

foreach ($r in $Repos) {
    $dest = Join-Path $Root $r.Name
    Write-Host "=== checkout $($r.Repo) -> $($r.Name) ==="
    git clone --depth 1 "https://github.com/$Org/$($r.Repo).git" $dest
    if ($LASTEXITCODE -ne 0) { throw "clone failed: $($r.Repo)" }
}

# providers is pure Node.js — no build; stage as-is.
$dst = Join-Path $Root 'bundle\providers'
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item (Join-Path $Root 'providers\*') $dst -Recurse -Force
Write-Host 'providers staged (no build needed)'

# core WASM: requires Rust + wasm-pack (GitHub runner installs these).
# Build stremio-core-web to produce the npm package our UI depends on.
Write-Host '=== build core-web WASM ==='
Push-Location (Join-Path $Root 'core')
& rustup target add wasm32-unknown-unknown
& cargo build --target wasm32-unknown-unknown --release -p stremio-core-web
if ($LASTEXITCODE -ne 0) { throw 'core build failed' }
Pop-Location

# UI: pnpm build -> build/ (static files). Depends on core-web npm package.
Write-Host '=== build UI ==='
Push-Location (Join-Path $Root 'ui')
& corepack enable
& pnpm install --frozen-lockfile
& pnpm run build
if ($LASTEXITCODE -ne 0) { throw 'UI build failed' }
Pop-Location
Copy-Item (Join-Path $Root 'ui\build\*') (Join-Path $Root 'bundle\ui') -Recurse -Force

Write-Host "bundle staged: $((Get-ChildItem (Join-Path $Root 'bundle') -Recurse -File).Count) files"
