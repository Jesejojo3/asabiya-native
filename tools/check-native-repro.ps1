param(
    [string]$Binary = '',
    [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
if (!$Binary) { $Binary = Join-Path $repository 'bin/asabiya-headless.exe' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repository 'artifacts/native' }
$Binary = [System.IO.Path]::GetFullPath($Binary)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$firstPath = Join-Path $OutputDirectory 'world-first.json'
$secondPath = Join-Path $OutputDirectory 'world-second.json'
& $Binary --seed Asabiya --history-seed 1 --cell 200,100 --out $firstPath --png (Join-Path $OutputDirectory 'world.png') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'First headless process failed' }
& $Binary --seed Asabiya --history-seed 1 --cell 200,100 --out $secondPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Second headless process failed' }
if ((Get-FileHash -LiteralPath $firstPath).Hash -ne (Get-FileHash -LiteralPath $secondPath).Hash) {
    throw 'Independent processes produced different reports'
}
$first = Get-Content -Raw -LiteralPath $firstPath | ConvertFrom-Json
$golden = Get-Content -Raw -LiteralPath (Join-Path $repository 'tests/native/world-v1.windows-go1.27.2.json') | ConvertFrom-Json
if ($first.environment.go -ne 'go1.27.2' -or $first.environment.os -ne 'windows' -or $first.environment.arch -ne 'amd64' -or $first.environment.goamd64 -ne 'v1') {
    throw 'Unexpected target/toolchain; this golden is only for Windows amd64 Go 1.27.2 GOAMD64=v1'
}
$actualWorld = $first.world | ConvertTo-Json -Depth 8 -Compress
$expectedWorld = $golden | ConvertTo-Json -Depth 8 -Compress
if ($actualWorld -cne $expectedWorld) {
    throw 'Native golden mismatch: investigate CPU/toolchain/source changes; do not regenerate to hide divergence'
}
Write-Output "Native reproducibility and golden OK: $($first.world.sha256)"
