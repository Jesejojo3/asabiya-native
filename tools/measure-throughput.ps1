param(
 [string]$ClientPath = (Join-Path $PSScriptRoot 'AsabiyaNative.exe'),
 [ValidateRange(10,300)][int]$Seconds = 60,
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
 Write-Host 'Inicia el mundo y selecciona Observacion/Maxima o Simulacion rapida.'
 Write-Host "Se mediran $Seconds segundos. La aplicacion quedara abierta."
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
 Write-Host "Resultados: $destination"
 Write-Host 'Al terminar tu prueba, cierra Asabiya normalmente para vaciar todos los logs.'
 Write-Host 'frames.jsonl contiene FPS/frametimes; la memoria de render es una estimacion, no VRAM fisica.'
} finally {
 [Environment]::SetEnvironmentVariable('ASABIYA_THROUGHPUT_DIR',$previousAnnual,'Process')
 [Environment]::SetEnvironmentVariable('ASABIYA_PROFILE_PATH',$previousFrames,'Process')
}
