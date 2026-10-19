# Compilation/export only. Does not run tests, simulations, or the game.
param([string]$GodotPath='', [string]$OutputDirectory='', [string]$Seed='Asabiya', [string]$SourceRevision='working-copy')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$build=Join-Path $repo 'build'
if (!$OutputDirectory) { $OutputDirectory=Join-Path $build 'client' }
$out=[System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $out,(Join-Path $build 'bin') | Out-Null
$version=(Get-Content -Raw -LiteralPath (Join-Path $repo 'client/tools/godot-version.txt')).Trim()
$pins=@{}
foreach ($line in Get-Content -LiteralPath (Join-Path $repo 'client/tools/godot-pins.txt')) {
    if ($line -match '^\s*#' -or !$line.Trim()) { continue }
    $parts=$line -split '\s+'; $pins[$parts[0]]=$parts[1]
}
$assetDirectory=Join-Path $build "godot/$version"
New-Item -ItemType Directory -Force -Path $assetDirectory | Out-Null
function Get-Pinned([string]$name) {
    $path=Join-Path $assetDirectory $name
    if (!(Test-Path -LiteralPath $path)) {
        $temporary=$path+'.download'
        Invoke-WebRequest -Uri "https://github.com/godotengine/godot-builds/releases/download/$version/$name" -OutFile $temporary
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pins[$name]) { throw "Unexpected download hash: $temporary" }
        Move-Item -LiteralPath $temporary -Destination $path
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pins[$name]) { throw "Unexpected cached archive hash: $path" }
    return $path
}
if (!$GodotPath) {
    $archive=Get-Pinned "Godot_v${version}_win64.exe.zip"
    $editorDirectory=Join-Path $assetDirectory 'editor'
    $GodotPath=Join-Path $editorDirectory "Godot_v${version}_win64_console.exe"
    if (!(Test-Path -LiteralPath $GodotPath)) { Expand-Archive -LiteralPath $archive -DestinationPath $editorDirectory -Force }
}
$actualGodot=& $GodotPath --version
if ($LASTEXITCODE -ne 0 -or "$actualGodot" -notmatch '^4\.7\.2\.stable\.official\.') { throw "Expected pinned Godot editor; got $actualGodot" }
$templatesDirectory=Join-Path $env:APPDATA ("Godot/export_templates/"+($version -replace '-', '.'))
if (!(Test-Path -LiteralPath (Join-Path $templatesDirectory 'windows_release_x86_64.exe'))) {
    $archive=Get-Pinned "Godot_v${version}_export_templates.tpz"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[System.IO.Compression.ZipFile]::OpenRead($archive)
    try {
        New-Item -ItemType Directory -Force -Path $templatesDirectory | Out-Null
        foreach ($name in @('windows_release_x86_64.exe','windows_release_x86_64_console.exe','version.txt')) {
            $entry=$zip.GetEntry("templates/$name")
            if (!$entry) { throw "Official archive is missing $name" }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $templatesDirectory $name),$true)
        }
    } finally { $zip.Dispose() }
}
& (Join-Path $repo 'tools/build-native.ps1') -OutputDirectory (Join-Path $build 'bin')
if ($LASTEXITCODE -ne 0) { throw 'Native compilation failed' }
& go -C $repo build -trimpath -buildvcs=false -o (Join-Path $build 'bin/asabiya-snapshot.exe') ./client/exporter
if ($LASTEXITCODE -ne 0) { throw 'Legacy snapshot exporter compilation failed' }
$project=Join-Path $repo 'client/godot'
$importLog=Join-Path $build 'godot-import.log'
& $GodotPath --headless --editor --path $project --import *> $importLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR|Parse Error|Compilation failed' -Quiet)) { throw "Godot import/compilation failed: $importLog" }
$exportLog=Join-Path $build 'godot-export.log'
& $GodotPath --headless --path $project --export-release 'Windows x64' (Join-Path $out 'AsabiyaNative.exe') *> $exportLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $exportLog -Pattern 'SCRIPT ERROR|Parse Error|Compilation failed|Export failed' -Quiet)) { throw "Godot export failed: $exportLog" }
if (!(Test-Path -LiteralPath (Join-Path $out 'AsabiyaNative.exe'))) { throw 'Godot did not produce the executable' }
foreach ($name in @('asabiya-server.exe','asabiya-headless.exe','asabiya-snapshot.exe')) { Copy-Item -LiteralPath (Join-Path $build "bin/$name") -Destination (Join-Path $out $name) -Force }
$defaults=@{world=@{seed=$Seed;width=400;height=200;detail=4;landFraction=0.33};historySeed='1'}
$defaults | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'asabiya.json') -Encoding utf8
$resources=Join-Path $out 'resources'
New-Item -ItemType Directory -Force -Path $resources | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'reference/v0.6/Asabiya History Engine (Copy).html') -Destination (Join-Path $resources 'legacy-v0.6.html') -Force
$earth=@{world=@{seed='Earth';width=400;height=200;detail=4;landFraction=0.33};historySeed='1';source=@{kind='earth';fitClimate=$true;assets=@(@{role='earth-html';path='resources/legacy-v0.6.html'})}}
$earth | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $out 'asabiya-earth.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $repo 'docs/integration/LEEME.txt') -Destination (Join-Path $out 'LEEME.txt') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $out 'licenses') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'client/licenses/GODOT_LICENSE.txt'),(Join-Path $repo 'client/licenses/GODOT_COPYRIGHT.txt'),(Join-Path $repo 'client/licenses/GO_LICENSE.txt') -Destination (Join-Path $out 'licenses') -Force
$manifest=@{schema='asabiya/windows-build-v1';sourceRevision=$SourceRevision;godot="$actualGodot";go=((& go version)-join '');target='windows/amd64';goamd64='v1';cgo=$false;finalTests='not executed; user-owned';files=@()}
foreach ($item in Get-ChildItem -LiteralPath $out -File -Recurse) {
    if ($item.Name -eq 'BUILD-MANIFEST.json') { continue }
    $manifest.files+=@{path=[System.IO.Path]::GetRelativePath($out,$item.FullName).Replace('\','/');bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $out 'BUILD-MANIFEST.json') -Encoding utf8
Write-Output "Windows package prepared: $out"
