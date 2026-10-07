# Exercise orchestration without downloads, exports, or opening a game window.
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dorbit launcher ' + [guid]::NewGuid())
$previousFixture = $env:DORBIT_LAUNCHER_TEST_FIXTURE
$previousFailure = $env:DORBIT_LAUNCHER_TEST_FAILURE

function Start-Process {
    param($FilePath, $WorkingDirectory, $ArgumentList)
    if ($FilePath -ne (Join-Path $fixture 'build/windows/Dorbit.exe') -or
        $WorkingDirectory -ne $fixture -or ($ArgumentList -join ' ') -ne '-- --offline') {
        throw 'Incorrect game path, working directory, or offline arguments.'
    }
    Add-Content -LiteralPath (Join-Path $fixture 'trace') -Value 'launch offline'
}

try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'tools') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'play.ps1') -Destination $fixture
    @'
param([string]$Task)
$ErrorActionPreference = 'Stop'
$root = $env:DORBIT_LAUNCHER_TEST_FIXTURE
Add-Content -LiteralPath (Join-Path $root 'trace') -Value $Task
if ($env:DORBIT_LAUNCHER_TEST_FAILURE -eq $Task) { exit 7 }
if ($Task -eq 'setup') {
    $cache = Join-Path $root 'engine-installed'
    if (-not (Test-Path -LiteralPath $cache)) {
        Set-Content -LiteralPath $cache -Value 'installed'
        Add-Content -LiteralPath (Join-Path $root 'trace') -Value 'install'
    }
} elseif ($env:DORBIT_LAUNCHER_TEST_FAILURE -ne 'missing-output') {
    New-Item -ItemType Directory -Path (Join-Path $root 'build/windows') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'build/windows/Dorbit.exe') -Value 'fixture'
}
'@ | Set-Content -LiteralPath (Join-Path $fixture 'tools/dev.ps1')
    $env:DORBIT_LAUNCHER_TEST_FIXTURE = $fixture
    $env:DORBIT_LAUNCHER_TEST_FAILURE = ''
    $launcher = Join-Path $fixture 'play.ps1'
    $trace = Join-Path $fixture 'trace'

    & $launcher
    & $launcher
    if ((Get-Content -LiteralPath $trace) -join ',' -ne
        'setup,install,build,launch offline,setup,build,launch offline') {
        throw 'Fresh/cached worktree sequence failed.'
    }
    foreach ($failure in @('setup', 'build', 'missing-output')) {
        Remove-Item -LiteralPath $trace
        if ($failure -eq 'missing-output') {
            Remove-Item -LiteralPath (Join-Path $fixture 'build/windows/Dorbit.exe')
        }
        $env:DORBIT_LAUNCHER_TEST_FAILURE = $failure
        $caught = $false
        try { & $launcher } catch { $caught = $true }
        if (-not $caught -or 'launch offline' -in (Get-Content -LiteralPath $trace)) {
            throw "Launcher did not stop for $failure."
        }
    }
    Write-Host 'PASS: fresh/cached setup, paths with spaces, offline launch, setup/build failure, missing output.'
} finally {
    $env:DORBIT_LAUNCHER_TEST_FIXTURE = $previousFixture
    $env:DORBIT_LAUNCHER_TEST_FAILURE = $previousFailure
    # Delete only the uniquely named fixture inside the system temporary directory.
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedFixture -Leaf) -like 'dorbit launcher *') {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
