param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repository 'bin' }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$expectedVersion = (Get-Content -Raw -LiteralPath (Join-Path $repository '.go-version')).Trim()
$actualVersion = & go version
if ($LASTEXITCODE -ne 0 -or $actualVersion.Trim() -cne "go version go$expectedVersion windows/amd64") {
    throw "Build requires Go $expectedVersion on Windows amd64; got $actualVersion"
}
$env:GOTOOLCHAIN = 'local'
$env:GOOS = 'windows'
$env:GOARCH = 'amd64'
$env:GOAMD64 = 'v1'
$env:CGO_ENABLED = '0'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
foreach ($name in @('asabiya-headless', 'asabiya')) {
    & go -C $repository build -trimpath -buildvcs=false -o (Join-Path $OutputDirectory "$name.exe") "./cmd/$name"
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $name" }
}
Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $OutputDirectory 'asabiya-headless.exe'), (Join-Path $OutputDirectory 'asabiya.exe')
