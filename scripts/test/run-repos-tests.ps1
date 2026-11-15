<#
.SYNOPSIS
    Test scripts/repos.ps1 against the fixture workspace and compare the normalized
    output and exit code of every step with scripts/test/expected/.
.DESCRIPTION
    Runs the same steps as run-repos-tests.sh and compares with the same expected
    results, so repos.sh and repos.ps1 cannot drift apart. The script under test runs
    in the interpreter that runs this file (Windows PowerShell 5.1 or PowerShell 7);
    run this file once per interpreter.
.PARAMETER Update
    Rewrite the expected results instead of comparing them (review the diff).
.EXAMPLE
    pwsh -NoProfile -File scripts/test/run-repos-tests.ps1
#>
param(
    [switch]$Update
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$expectedDir = Join-Path $here 'expected'

# Prefer the bash that ships with Git: on Windows, 'bash' may resolve to WSL.
function Find-Bash {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $execPath = (& git --exec-path) -replace '/', [IO.Path]::DirectorySeparatorChar
        foreach ($candidate in @(
                (Join-Path $execPath '..\..\..\bin\bash.exe'),
                (Join-Path $execPath '..\..\..\usr\bin\bash.exe'))) {
            if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
        }
    }
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) { return $bash.Source }
    throw 'bash not found; it is needed to build the fixture.'
}

$workspace = Join-Path ([IO.Path]::GetTempPath()) ('repos-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
$failed = $false

try {
    $workspace = (Resolve-Path $workspace).Path
    $builder = (Join-Path $here 'build-fixture.sh') -replace '\\', '/'
    & (Find-Bash) $builder ($workspace -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw 'building the fixture failed' }

    $root = Join-Path $workspace 'root'
    $results = Join-Path $workspace 'results'
    New-Item -ItemType Directory -Path $results | Out-Null
    $script = Join-Path $root 'scripts\repos.ps1'

    # Forms of the workspace path that can appear in output.
    $wsForms = @($workspace, ($workspace -replace '\\', '/')) | Select-Object -Unique |
        ForEach-Object { [regex]::Escape(($_ -replace '\\', '/')) } | Select-Object -Unique

    function Convert-Line([string]$Line) {
        $text = $Line.TrimEnd("`r").Replace('\', '/')
        foreach ($form in $wsForms) { $text = $text -replace $form, '<ws>' }
        $text = $text -replace '\b[0-9a-f]{7,40}\b', '<sha>'
        $text -replace '(\./)*scripts/repos\.(sh|ps1)', 'scripts/repos.<ext>'
    }

    # Run the script in this process with every stream merged in order. Warnings become
    # '! message' lines like in repos.sh, which also avoids localized prefixes and
    # console-width wrapping.
    function Invoke-Step([string]$Name, [string]$Command) {
        $global:LASTEXITCODE = 0
        # The script under test inherits this preference; Git writes progress to stderr.
        $ErrorActionPreference = 'Continue'
        $records = & $script $Command *>&1
        $succeeded = $?
        $ErrorActionPreference = 'Stop'
        $code = if ($succeeded) { 0 } else { $global:LASTEXITCODE }
        $lines = foreach ($record in $records) {
            $text = switch ($record) {
                { $_ -is [System.Management.Automation.WarningRecord] } { '! ' + $_.Message; break }
                { $_ -is [System.Management.Automation.InformationRecord] } { [string]$_.MessageData; break }
                { $_ -is [System.Management.Automation.ErrorRecord] } { $_.Exception.Message; break }
                default { [string]$record }
            }
            foreach ($line in ($text -split "`r?`n")) { Convert-Line $line }
        }
        # Lines printed by Git itself differ between Git versions.
        $body = @($lines | Where-Object {
                $_ -notmatch '^(Cloning into |done\.$|fatal: |Please make sure|and the repository exists|Already up.to.date|$)'
            })
        $text = ((@($body) + "exit: $code") -join "`n") + "`n"
        [IO.File]::WriteAllText((Join-Path $results "$Name.txt"), $text, (New-Object Text.UTF8Encoding $false))
    }

    Invoke-Step '01-status-before' 'status'
    Invoke-Step '02-clone' 'clone'
    Invoke-Step '03-clone-again' 'clone'
    Set-Content -Path (Join-Path $root 'bravo\local.txt') -Value 'local change'
    Invoke-Step '04-status-after-clone' 'status'
    Invoke-Step '05-pull' 'pull'

    foreach ($result in Get-ChildItem $results -Filter '*.txt' | Sort-Object Name) {
        $expected = Join-Path $expectedDir $result.Name
        if ($Update) {
            Copy-Item $result.FullName $expected -Force
            Write-Host "updated $($result.Name)"
            continue
        }
        $want = (Get-Content -Raw $expected) -replace "`r`n", "`n"
        $got = (Get-Content -Raw $result.FullName) -replace "`r`n", "`n"
        if ($want -ceq $got) {
            Write-Host "ok      $($result.Name)"
        }
        else {
            Write-Host "FAILED  $($result.Name)"
            Write-Host '--- expected'
            Write-Host $want
            Write-Host '--- actual'
            Write-Host $got
            $failed = $true
        }
    }
}
finally {
    Remove-Item -Recurse -Force $workspace -ErrorAction SilentlyContinue
}

# Exit explicitly: $LASTEXITCODE still holds the code of the last failing step of the
# script under test, and CI shells exit with it.
if ($failed) { exit 1 }
exit 0
