# Builds the Asabiya Native 3D client for Windows x64.
#   ./client/tools/build-client.ps1            -> build/client/AsabiyaNative.exe (+ exporter, default world)
# Downloads the pinned Godot 4.7.2-stable editor and export templates into
# build/godot (hash-checked) unless -GodotPath is given. Requires Go from .go-version.
param(
    [string]$GodotPath = '',
    [string]$Seed = 'Asabiya',
    [switch]$SkipWorld
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$build = Join-Path $repo 'build'
$out = Join-Path $build 'client'
$version = (Get-Content -Raw (Join-Path $PSScriptRoot 'godot-version.txt')).Trim()   # 4.7.2-stable
$pins = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot 'godot-pins.txt')) {
    if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
    $p = $line -split '\s+'
    $pins[$p[0]] = $p[1]
}
$base = "https://github.com/godotengine/godot-builds/releases/download/$version"

function Get-Pinned([string]$name) {
    $dest = Join-Path $build "godot\$name"
    if (!(Test-Path $dest)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Write-Host "Descargando $name"
        Invoke-WebRequest -Uri "$base/$name" -OutFile $dest
    }
    $h = (Get-FileHash -Algorithm SHA256 $dest).Hash.ToLower()
    if ($h -ne $pins[$name]) { Remove-Item $dest; throw "SHA-256 inesperado para $name ($h)" }
    return $dest
}

if (!$GodotPath) {
    $zip = Get-Pinned "Godot_v${version}_win64.exe.zip"
    $dir = Join-Path $build 'godot\editor'
    if (!(Test-Path $dir)) { Expand-Archive -Path $zip -DestinationPath $dir }
    $GodotPath = (Get-ChildItem $dir -Filter '*_console.exe' -Recurse | Select-Object -First 1).FullName
    if (!$GodotPath) { $GodotPath = (Get-ChildItem $dir -Filter '*.exe' -Recurse | Select-Object -First 1).FullName }
}
$tplDir = Join-Path $env:APPDATA ("Godot\export_templates\" + ($version -replace '-', '.'))
if (!(Test-Path (Join-Path $tplDir 'windows_release_x86_64.exe'))) {
    $tpz = Get-Pinned "Godot_v${version}_export_templates.tpz"
    $tmp = Join-Path $build 'godot\templates'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -Path $tpz -DestinationPath $tmp -Force   # .tpz is a zip
    New-Item -ItemType Directory -Force -Path $tplDir | Out-Null
    Copy-Item (Join-Path $tmp 'templates\*') $tplDir -Force
}

# Go exporter (reads the public sim API only)
$env:GOTOOLCHAIN = 'local'; $env:GOOS = 'windows'; $env:GOARCH = 'amd64'; $env:GOAMD64 = 'v1'; $env:CGO_ENABLED = '0'
New-Item -ItemType Directory -Force -Path (Join-Path $build 'bin'), $out | Out-Null
& go -C $repo build -trimpath -buildvcs=false -o (Join-Path $build 'bin\asabiya-snapshot.exe') ./client/exporter
if ($LASTEXITCODE -ne 0) { throw 'go build del exportador falló' }

if (!$SkipWorld) {
    & (Join-Path $build 'bin\asabiya-snapshot.exe') --seed $Seed --out (Join-Path $build "worlds\$Seed.asw")
    if ($LASTEXITCODE -ne 0) { throw 'la exportación del mundo falló' }
}

$project = Join-Path $repo 'client\godot'
& $GodotPath --headless --path $project --import
& $GodotPath --headless --path $project --export-release 'Windows x64' (Join-Path $out 'AsabiyaNative.exe')
if (!(Test-Path (Join-Path $out 'AsabiyaNative.exe'))) { throw 'la exportación de Godot falló' }
Copy-Item (Join-Path $build 'bin\asabiya-snapshot.exe') $out -Force
if (Test-Path (Join-Path $build 'worlds')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $out 'worlds') | Out-Null
    Copy-Item (Join-Path $build 'worlds\*.asw') (Join-Path $out 'worlds') -Force
}
Get-FileHash -Algorithm SHA256 (Join-Path $out 'AsabiyaNative.exe'), (Join-Path $out 'asabiya-snapshot.exe')
Write-Host "Listo: $out\AsabiyaNative.exe"
