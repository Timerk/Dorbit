# Build this checkout and launch the exported game in offline development mode.
$ErrorActionPreference = 'Stop'
$devScript = Join-Path $PSScriptRoot 'tools/dev.ps1'

# Setup checks for the pinned engine in this worktree and only downloads if missing.
# Separate processes preserve dev.ps1's exit codes and stop us launching a stale build.
foreach ($task in @('setup', 'build')) {
    Write-Host "Dorbit: $task"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $devScript $task
    if ($LASTEXITCODE -ne 0) {
        throw "Dorbit $task failed (exit code $LASTEXITCODE)."
    }
}

$game = Join-Path $PSScriptRoot 'build/windows/Dorbit.exe'
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) {
    throw "Build did not produce $game."
}

Write-Host 'Dorbit: launching offline'
Start-Process -FilePath $game -WorkingDirectory $PSScriptRoot -ArgumentList @('--', '--offline') | Out-Null
