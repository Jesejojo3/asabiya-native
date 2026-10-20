param(
 [string]$ClientPath = (Join-Path $PSScriptRoot 'AsabiyaNative.exe'),
 [ValidateRange(10,300)][int]$Seconds = 60,
 [switch]$StartImmediately,
 [string]$OutputDirectory = (Join-Path $PSScriptRoot ("throughput-" + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')))
)
$ErrorActionPreference='Stop'
$client=Get-Item -LiteralPath $ClientPath
$destination=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$previousAnnual=[Environment]::GetEnvironmentVariable('ASABIYA_THROUGHPUT_DIR','Process')
$previousFrames=[Environment]::GetEnvironmentVariable('ASABIYA_PROFILE_PATH','Process')
try {
 [Environment]::SetEnvironmentVariable('ASABIYA_THROUGHPUT_DIR',$destination,'Process')
 [Environment]::SetEnvironmentVariable('ASABIYA_PROFILE_PATH',(Join-Path $destination 'frames.jsonl'),'Process')
 $process=Start-Process -FilePath $client.FullName -WorkingDirectory $client.DirectoryName -PassThru -WindowStyle Normal
 Write-Host 'Carga el mundo y activa Observacion/Maxima o Simulacion rapida antes de medir.'
 if (-not $StartImmediately) {
  [void](Read-Host 'Cuando la simulacion este avanzando, pulsa ENTER para iniciar la medicion')
  $process.Refresh()
  if ($process.HasExited) { throw 'Asabiya se cerro antes de empezar la medicion.' }
 }
 $startedUtc=(Get-Date).ToUniversalTime().ToString('o')
 Write-Host "Midiendo $Seconds segundos a partir de ahora. Deja la simulacion avanzando."
 $rows=[Collections.Generic.List[object]]::new()
 $clock=[Diagnostics.Stopwatch]::StartNew()
 $previous=@{}
 while ($clock.Elapsed.TotalSeconds -lt $Seconds -and -not $process.HasExited) {
  $ids=@($process.Id)
  try { $ids+=@(Get-CimInstance Win32_Process -Filter ("ParentProcessId="+$process.Id+" AND Name='asabiya-server.exe'") | ForEach-Object { [int]$_.ProcessId }) } catch {}
  foreach ($processId in $ids) {
   try {
    $sample=Get-Process -Id $processId -ErrorAction Stop
    $now=$clock.Elapsed.TotalMilliseconds
    $cpu=$sample.TotalProcessorTime.TotalMilliseconds
    $cores=0.0
    if ($previous.ContainsKey($processId)) {
      $wall=$now-$previous[$processId].wall
      if ($wall -gt 0) { $cores=($cpu-$previous[$processId].cpu)/$wall }
    }
    $previous[$processId]=@{wall=$now;cpu=$cpu}
    $rows.Add([pscustomobject]@{elapsedSeconds=$now/1000;pid=$processId;name=$sample.ProcessName;cpuCores=$cores;cpuPercentMachine=100*$cores/[Environment]::ProcessorCount;workingSetBytes=$sample.WorkingSet64;privateBytes=$sample.PrivateMemorySize64})
   } catch {}
  }
  Start-Sleep -Milliseconds 500
  $process.Refresh()
 }
 $rows | Export-Csv -LiteralPath (Join-Path $destination 'processes.csv') -NoTypeInformation -Encoding UTF8
 @{startedUtc=$startedUtc;finishedUtc=(Get-Date).ToUniversalTime().ToString('o');requestedSeconds=$Seconds;actualSeconds=$clock.Elapsed.TotalSeconds;sampleCount=$rows.Count;clientPid=$process.Id} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'measurement.json') -Encoding utf8
 Write-Host "Resultados: $destination"
 Write-Host 'Al terminar tu prueba, cierra Asabiya normalmente para vaciar todos los logs.'
 Write-Host 'frames.jsonl contiene FPS/frametimes; la memoria de render es una estimacion, no VRAM fisica.'
} finally {
 [Environment]::SetEnvironmentVariable('ASABIYA_THROUGHPUT_DIR',$previousAnnual,'Process')
 [Environment]::SetEnvironmentVariable('ASABIYA_PROFILE_PATH',$previousFrames,'Process')
}
