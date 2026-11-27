# XnX build gate — verify each source repo's latest commit passed its own CI.
# Called by xnx-full.yml BEFORE assembling sources. If any repo's checks are
# failing or missing, the build aborts — never package unverified source.
param(
    [string]$Org = $env:GITHUB_REPOSITORY_OWNER,
    [string]$Token = $env:GH_TOKEN,
    [string[]]$Repos = @('XnX_core', 'XnX_shell', 'XnX_ui', 'XnX_providers')
)

$ErrorActionPreference = 'Stop'
if (-not $Token) { throw 'GH_TOKEN required for build gate' }

$headers = @{
    'Authorization' = "Bearer $Token"
    'Accept'        = 'application/vnd.github+json'
    'User-Agent'    = 'xnx-build-gate'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$failed = @()
foreach ($repo in $Repos) {
    Write-Host "=== gate: $repo ==="
    try {
        $head = Invoke-RestMethod -Headers $headers `
            -Uri "https://api.github.com/repos/$Org/$repo/commits/main" -TimeoutSec 30
        $sha = $head.sha
        Write-Host "  HEAD $($sha.Substring(0,8))"

        $checks = Invoke-RestMethod -Headers $headers `
            -Uri "https://api.github.com/repos/$Org/$repo/commits/$sha/check-runs?per_page=100" -TimeoutSec 30
        $runs = @($checks.check_runs)
        if ($runs.Count -eq 0) {
            $failed += "$repo : no CI checks on HEAD $($sha.Substring(0,8))"
            Write-Output "::error::$repo has NO checks on HEAD $($sha.Substring(0,8))"
            continue
        }
        # Pending/in-progress is not a pass — fail closed.
        $notPass = @($runs | Where-Object { $_.conclusion -ne 'success' -and $_.conclusion -ne 'skipped' })
        foreach ($c in $runs) {
            Write-Host "  $($c.name): $($c.status)/$($c.conclusion)"
        }
        if ($notPass.Count -gt 0) {
            $names = ($notPass | ForEach-Object { "$($_.name)=$($_.conclusion)" }) -join ', '
            $failed += "$repo : $names"
            Write-Output "::error::$repo checks not passing: $names"
        } else {
            Write-Host "  PASS"
        }
    } catch {
        $failed += "$repo : API error $($_.Exception.Message)"
        Write-Output "::error::gate failed for $repo : $($_.Exception.Message)"
    }
}

if ($failed.Count -gt 0) {
    throw "BUILD GATE FAILED - source repos not verified:`n$($failed -join "`n")"
}
Write-Host 'BUILD GATE PASS — all source repos verified'
