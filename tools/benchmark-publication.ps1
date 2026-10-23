# Equal worlds, seeds and consecutive years; exact SHA in both layouts.
param(
 [Parameter(Mandatory=$true)][string]$Editor,
 [Parameter(Mandatory=$true)][string]$Server,
 [ValidateRange(1,10000)][int]$Samples=50,
 [ValidateRange(1,10)][int]$Repeats=3,
 [string]$OutputDirectory=(Join-Path $PSScriptRoot '../artifacts/publication-comparison'),
 [string[]]$Layers=@('terrain','peoples')
)
$ErrorActionPreference='Stop'
$repository=Split-Path -Parent $PSScriptRoot
$editorPath=(Resolve-Path -LiteralPath $Editor).Path
$serverPath=(Resolve-Path -LiteralPath $Server).Path
$destination=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$previous=[Environment]::GetEnvironmentVariable('ASABIYA_THROUGHPUT_DIR','Process')
$results=[Collections.Generic.List[object]]::new()
$expectedDigest=''
try {
 foreach ($layer in $Layers) {
  foreach ($repeat in 1..$Repeats) {
   foreach ($layout in @('columns','fields')) {
    $tag="$layer-$layout-$repeat"
    $trace=Join-Path $destination $tag
    [Environment]::SetEnvironmentVariable('ASABIYA_THROUGHPUT_DIR',$trace,'Process')
    $arguments=@('--headless','--path',(Join-Path $repository 'client/godot'),'--script','res://tests/annual_pipeline_benchmark.gd','--','--server',$serverPath,'--samples',"$Samples",'--exact','--app','--layer',$layer)
    if ($layout -eq 'columns') { $arguments+='--columns' }
    $log=Join-Path $destination "$tag.txt"
    & $editorPath @arguments 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|PIPELINE ERROR|TIMEOUT|(?m)^FAIL(?:\s|$)' -Quiet)) { throw "Pipeline failed: $tag" }
    $line=@(Get-Content -LiteralPath $log | Where-Object { $_ -match '^PIPELINE ' })
    if ($line.Count -ne 1) { throw "Expected one measurement: $tag" }
    $row=($line[0] -replace '^PIPELINE ','') | ConvertFrom-Json
    if (!$expectedDigest) { $expectedDigest=$row.digest }
    if ($row.digest -cne $expectedDigest -or $row.publicationDigest -cne $expectedDigest -or $row.years -ne $Samples) { throw "Integrity/window mismatch: $tag" }
    $row | Add-Member -NotePropertyName layout -NotePropertyValue $layout
    $row | Add-Member -NotePropertyName repeat -NotePropertyValue $repeat
    $results.Add($row)
   }
  }
 }
 $results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $destination 'results.json') -Encoding utf8
} finally {
 [Environment]::SetEnvironmentVariable('ASABIYA_THROUGHPUT_DIR',$previous,'Process')
}
