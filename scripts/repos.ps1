<#
.SYNOPSIS
    Manage the homeBuddy service repositories listed in repos.txt.
.DESCRIPTION
    clone   clone every missing repository (default)
    pull    fast-forward every repository whose working tree is clean
    status  show branch, local changes, and ahead/behind counts
.EXAMPLE
    ./scripts/repos.ps1 status
#>
param(
    [ValidateSet('clone', 'pull', 'status')]
    [string]$Command = 'clone'
)

$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'repos.txt'
$failures = 0

$repos = Get-Content $manifest |
    Where-Object { $_ -notmatch '^\s*(#|$)' } |
    ForEach-Object {
        $name, $url, $branch = $_ -split '\s+', 3
        [pscustomobject]@{ Name = $name; Url = $url; Branch = $branch.Trim() }
    }

foreach ($repo in $repos) {
    $dir = Join-Path $root $repo.Name
    $isRepo = Test-Path (Join-Path $dir '.git')

    switch ($Command) {
        'clone' {
            if ($isRepo) {
                Write-Host "= $($repo.Name): already present"
            }
            elseif ((Test-Path $dir) -and (Get-ChildItem $dir -Force | Select-Object -First 1)) {
                Write-Warning "$($repo.Name): $dir exists but is not a Git repository; skipped"
                $failures++
            }
            else {
                Write-Host "+ $($repo.Name): cloning $($repo.Url) ($($repo.Branch))"
                git clone --branch $repo.Branch $repo.Url $dir
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "$($repo.Name): clone failed (does the remote exist and do you have access?)"
                    $failures++
                }
            }
        }
        'pull' {
            if (-not $isRepo) {
                Write-Warning "$($repo.Name): missing, run './scripts/repos.ps1 clone'"
                $failures++
            }
            elseif (git -C $dir status --porcelain) {
                Write-Host "~ $($repo.Name): local changes, skipped"
            }
            elseif (-not (git -C $dir remote 2>$null | Select-String -Pattern '^origin$' -Quiet)) {
                Write-Host "~ $($repo.Name): no origin remote, skipped"
            }
            else {
                Write-Host "> $($repo.Name): pulling"
                git -C $dir pull --ff-only
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "$($repo.Name): pull failed"
                    $failures++
                }
            }
        }
        'status' {
            if (-not $isRepo) {
                '{0,-15} missing' -f $repo.Name
                continue
            }
            $branch = git -C $dir branch --show-current
            $changes = @(git -C $dir status --porcelain).Count
            $tracking = 'no upstream'
            git -C $dir rev-parse --abbrev-ref '@{upstream}' 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $ahead, $behind = (git -C $dir rev-list --left-right --count 'HEAD...@{upstream}') -split '\s+'
                $tracking = "ahead $ahead, behind $behind"
            }
            if (-not $branch) { $branch = 'detached' }
            '{0,-15} {1,-20} {2,3} changed  {3}' -f $repo.Name, $branch, $changes, $tracking
        }
    }
}

if ($failures -gt 0) { exit 1 }
