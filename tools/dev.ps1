param(
    [ValidateSet('setup', 'check', 'build', 'run', 'editor')]
    [string]$Task = 'run'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $projectRoot '.tools'
$version = '4.7.2-stable'
$engineDir = Join-Path $toolRoot 'godot'
$engine = Join-Path $engineDir "Godot_v${version}_win64_console.exe"
$releaseUrl = "https://github.com/godotengine/godot-builds/releases/download/$version"

function Get-VerifiedAsset([string]$Name, [string]$Sha256) {
    $archivePath = Join-Path $toolRoot $Name
    New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null
    if (-not (Test-Path -LiteralPath $archivePath)) {
        Write-Host "Downloading $Name"
        Invoke-WebRequest "$releaseUrl/$Name" -OutFile $archivePath -UseBasicParsing
    }
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Checksum mismatch for $archivePath. Remove the invalid download and retry."
    }
    return $archivePath
}

function Invoke-Godot([string[]]$EngineArgs) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $engine @EngineArgs 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    $output | ForEach-Object { Write-Host $_ }
    if ($code -ne 0 -or ($output -match 'SCRIPT ERROR:|Parse Error:|ERROR:')) {
        throw "Godot validation failed with exit code $code."
    }
}

if ($Task -eq 'setup') {
    if (-not (Test-Path -LiteralPath $engine)) {
        $archive = Get-VerifiedAsset "Godot_v${version}_win64.exe.zip" '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'
        Expand-Archive -LiteralPath $archive -DestinationPath $engineDir -Force
    }
    Invoke-Godot @('--version')
    exit 0
}

if (-not (Test-Path -LiteralPath $engine)) {
    throw 'Run tools/dev.ps1 setup first to download the pinned Godot editor.'
}

switch ($Task) {
    'check' {
        Invoke-Godot @('--headless', '--path', $projectRoot, '--editor', '--import')
        Invoke-Godot @('--headless', '--path', $projectRoot, '--script', 'res://tests/encounter_test.gd')
        Invoke-Godot @('--headless', '--path', $projectRoot, '--script', 'res://tests/network_test.gd')
        Invoke-Godot @('--headless', '--path', $projectRoot, '--script', 'res://tests/network_combat_test.gd')
        Invoke-Godot @('--headless', '--path', $projectRoot, '--script', 'res://tests/dedicated_server_test.gd')
        Invoke-Godot @('--headless', '--path', $projectRoot, '--script', 'res://tests/pilot_persistence_test.gd')
        Invoke-Godot @('--headless', '--path', $projectRoot, '--script', 'res://tests/flight_playthrough.gd')
    }
    'build' {
        $templateDir = Join-Path $toolRoot 'templates'
        if (-not (Test-Path -LiteralPath (Join-Path $templateDir 'windows_release_x86_64.exe'))) {
            $archive = Get-VerifiedAsset "Godot_v${version}_export_templates.tpz" 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
            New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
            try {
                foreach ($entry in $zip.Entries) {
                    if ($entry.Name -match '^windows_(release|debug)_x86_64.exe$') {
                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $templateDir $entry.Name), $true)
                    }
                }
            } finally { $zip.Dispose() }
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'build/windows') | Out-Null
        Invoke-Godot @('--headless', '--path', $projectRoot, '--editor', '--import')
        Invoke-Godot @('--headless', '--path', $projectRoot, '--export-release', 'Windows Desktop')
        Invoke-Godot @('--headless', '--path', $projectRoot, '--script', 'res://tools/export_notices.gd')
    }
    'run' { & $engine --path $projectRoot }
    'editor' { & $engine --path $projectRoot --editor }
}
