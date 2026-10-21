# Windows capture only. Does not install tools, modify the project, or optimize it.
# The CI kit supplies the pinned editor, server and immutable baseline sources.
param(
 [string]$KitDirectory = (Split-Path -Parent $PSScriptRoot),
 [ValidateRange(10,300)][int]$Seconds = 60,
 [ValidateRange(1,5)][int]$Repeats = 3,
 [ValidateRange(0,10000)][int]$HistoryYears = 10000,
 [ValidateRange(0,50)][int]$Rate = 0,
 [int]$Cell = -1,
 [ValidateRange(3.5,100)][double]$Distance = 18,
 [switch]$Diagnostics,
 [switch]$CpuScopes,
 [switch]$NoGpuTiming,
 [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This capture requires Windows and the target physical GPU.' }
$kit = (Resolve-Path -LiteralPath $KitDirectory).Path
$manifest = Get-Content -Raw -LiteralPath (Join-Path $kit 'PROFILE-KIT.json') | ConvertFrom-Json
$project = Join-Path $kit 'source/client/godot'
$godot = Join-Path $kit $manifest.editor
$server = Join-Path $kit 'asabiya-server.exe'
$harness = Join-Path $kit 'tools/close_zoom_capture.gd'
foreach ($required in @($project,$godot,$server,$harness)) {
 if (!(Test-Path -LiteralPath $required)) { throw "Incomplete kit: $required" }
}
foreach ($entry in $manifest.files) {
 $actual = (Get-FileHash -LiteralPath (Join-Path $kit $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant()
 if ($actual -ne $entry.sha256) { throw "Kit file changed: $($entry.path). Use a new extraction." }
}
$version = & $godot --version
if ($LASTEXITCODE -ne 0 -or "$version" -notmatch '^4\.7\.2\.stable\.official\.') { throw "Unexpected Godot: $version" }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $kit ('results-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
$out = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $out) { throw 'Use a new output directory; measurements are never overwritten.' }
New-Item -ItemType Directory -Path $out | Out-Null
$hardware = @{
 os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,TotalVisibleMemorySize,FreePhysicalMemory
 computer = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory
 cpu = @(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors)
 gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,DriverDate,VideoProcessor)
 power = (& powercfg /getactivescheme | Out-String).Trim()
 kit = $manifest
}
Add-Type -AssemblyName System.Windows.Forms
$hardware.powerLineStatus = [Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus.ToString()
if ($hardware.powerLineStatus -eq 'Offline') { throw 'Conecta el portatil a corriente antes de medir.' }
$hardware | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $out 'machine.json') -Encoding UTF8
Write-Host 'Mantiene el equipo conectado a corriente. Cierra otras aplicaciones pesadas.'
Write-Host 'No minimices, redimensiones, uses teclado/raton ni cambies de ventana durante la captura.'
Write-Host 'Se medira 1080p/720p, pausado/activo; 720p es diagnostico, no aceptacion de 1080p.'
Write-Host 'La preparacion de historia y el calentamiento quedan fuera de las muestras.'
Write-Host 'Si la pantalla no admite 1920x1080 reales, esa condicion fallara explicitamente.'
$oldProfile = $env:ASABIYA_PROFILE_PATH
$oldAnnual = $env:ASABIYA_THROUGHPUT_DIR
$process = $null
try {
 $env:ASABIYA_PROFILE_PATH = ''
 $env:ASABIYA_THROUGHPUT_DIR = ''
 & $godot --headless --editor --path $project --import *> (Join-Path $out 'import.log')
 if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $out 'import.log') -Pattern 'SCRIPT ERROR|Parse Error|Compilation failed' -Quiet)) { throw 'Import failed; see import.log.' }
 $cases = @(
  @{width=1920;height=1080;mode='paused';diagnostic='none'},
  @{width=1920;height=1080;mode='active';diagnostic='none'},
  @{width=1280;height=720;mode='paused';diagnostic='none'},
  @{width=1280;height=720;mode='active';diagnostic='none'}
 )
 if ($Diagnostics) {
  foreach ($variant in @('shadows-off','ssao-off','terrain-hidden','vegetation-hidden','lod-coarse')) {
   $cases += @{width=1920;height=1080;mode='paused';diagnostic=$variant}
  }
 }
 $records = [Collections.Generic.List[object]]::new()
 $initialProof = $null
 for ($repeat=1; $repeat -le $Repeats; $repeat++) {
  # Reverse condition order on alternate repeats to expose warm/thermal drift.
  $ordered = @($cases)
  if ($repeat % 2 -eq 0) { [array]::Reverse($ordered) }
  foreach ($case in $ordered) {
   $tag = '{0}x{1}-{2}-{3}-r{4}' -f $case.width,$case.height,$case.mode,$case.diagnostic,$repeat
   $directory = Join-Path $out $tag
   New-Item -ItemType Directory -Path $directory | Out-Null
   if ($CpuScopes) { $env:ASABIYA_PROFILE_PATH = Join-Path $directory 'cpu-scopes.jsonl' }
   $arguments = @('--path',('"'+$project+'"'),'--script',('"'+$harness+'"'),'--rendering-method','forward_plus','--windowed',
    '--','--server',('"'+$server+'"'),'--output',('"'+$directory+'"'),'--revision',$manifest.sourceRevision,
    '--width',$case.width,'--height',$case.height,'--mode',$case.mode,'--diagnostic',$case.diagnostic,
    '--seconds',$Seconds,'--warmup-seconds',20,'--history-years',$HistoryYears,'--rate',$Rate,'--cell',$Cell,
    '--distance',$Distance.ToString([Globalization.CultureInfo]::InvariantCulture),'--ui-scale',1,'--seed','Asabiya','--history-seed',1)
   if ($NoGpuTiming) { $arguments += '--no-gpu-timing' }
   Write-Host "Capturando $tag"
   $process = Start-Process -FilePath $godot -ArgumentList $arguments -WorkingDirectory $kit -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
   $samples = [Collections.Generic.List[object]]::new()
   $clock = [Diagnostics.Stopwatch]::StartNew()
   $previous = @{}
   $ready = $null
   while (!$process.HasExited) {
    if ($clock.Elapsed.TotalSeconds -gt 1800+$Seconds) { throw "Timeout in $tag" }
    $readyPath = Join-Path $directory 'ready.json'
    if (!$ready -and (Test-Path -LiteralPath $readyPath)) {
     # The writer may still be flushing its ready record; retry on the next poll.
     try { $ready = Get-Content -Raw -LiteralPath $readyPath | ConvertFrom-Json } catch {}
    }
    $ids = @($process.Id)
    if ($ready) { $ids += [int]$ready.serverPid }
    foreach ($sampleId in $ids) {
     try {
      $sample = Get-Process -Id $sampleId -ErrorAction Stop
      $now = $clock.Elapsed.TotalMilliseconds
      $cpu = $sample.TotalProcessorTime.TotalMilliseconds
      $cores = $null
      if ($previous.ContainsKey($sampleId) -and $now -gt $previous[$sampleId].wall) { $cores = ($cpu-$previous[$sampleId].cpu)/($now-$previous[$sampleId].wall) }
      $previous[$sampleId] = @{wall=$now;cpu=$cpu}
      $samples.Add([pscustomobject]@{utc=(Get-Date).ToUniversalTime().ToString('o');pid=$sampleId;name=$sample.ProcessName;cpuCores=$cores;workingSetBytes=$sample.WorkingSet64;privateBytes=$sample.PrivateMemorySize64})
     } catch {}
    }
    Start-Sleep -Milliseconds 1000
    $process.Refresh()
   }
   $process.WaitForExit()
   $samples | Export-Csv -LiteralPath (Join-Path $directory 'processes.csv') -NoTypeInformation -Encoding UTF8
   $runPath = Join-Path $directory 'run.json'
   if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $runPath) -or (Select-String -LiteralPath (Join-Path $directory 'stderr.log') -Pattern 'SCRIPT ERROR|Parse Error|CLOSE_ZOOM_ERROR' -Quiet)) { throw "Invalid run $tag; see logs. No result is accepted." }
   $run = Get-Content -Raw -LiteralPath $runPath | ConvertFrom-Json
   if ([Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus.ToString() -eq 'Offline') { throw "Power disconnected during $tag; repeat this campaign on AC." }
   if (!$run.valid) { throw "Invalid run $tag : $($run.invalidReason)" }
   if (!$initialProof) { $initialProof = $run.initialSHA256 }
   if ($initialProof -ne $run.initialSHA256) { throw "Initial state mismatch in $tag" }
   $records.Add([pscustomobject]@{condition=$tag;summary=$run.summary;initialSHA256=$run.initialSHA256;initialYear=$run.initialYear;finalYear=$run.finalYear})
   ConvertTo-Json -InputObject @($records.ToArray()) -Depth 15 | Set-Content -LiteralPath (Join-Path $out 'summaries.json') -Encoding UTF8
   $process = $null
  }
 }
 Write-Host "Captura completa: $out"
 Write-Host 'Comparte la carpeta completa (JSON, JSONL, CSV, PNG y logs). Un resumen no permite auditar colas ni picos.'
} finally {
 if ($process -and !$process.HasExited) {
  # Only this harness owns this Go child; never stop unrelated game sessions.
  $readyPath = Join-Path $directory 'ready.json'
  if (Test-Path -LiteralPath $readyPath) {
   try {
    $owned = Get-Content -Raw -LiteralPath $readyPath | ConvertFrom-Json
    $child = Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$owned.serverPid)
    if ($child -and $child.ParentProcessId -eq $process.Id) { Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue }
   } catch {}
  }
  Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
 }
 $env:ASABIYA_PROFILE_PATH = $oldProfile
 $env:ASABIYA_THROUGHPUT_DIR = $oldAnnual
}
