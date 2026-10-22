# Phase 2.3 Windows graphical diagnosis and acceptance campaign.
# Windows PowerShell 5.1 compatible. Does not install tools, change the
# project, the user's settings or any production data. Every session writes a
# new folder; a failing session is recorded and the campaign continues.
param(
 [string]$KitDirectory = (Split-Path -Parent $PSScriptRoot),
 [ValidateSet('full','quick','diagnosis','mobile','ab','exported','candidate-diagnosis')][string]$Campaign = 'full',
 [ValidateRange(5,300)][int]$Seconds = 15,
 [ValidateRange(10,300)][int]$ActiveSeconds = 60,
 [ValidateRange(0,10000)][int]$HistoryYears = 10000,
 [ValidateRange(60,7200)][int]$PrepareTimeout = 1800,
 [ValidateRange(0,50)][int]$Rate = 0,
 [ValidateRange(640,3840)][int]$Width = 1920,
 [ValidateRange(360,2160)][int]$Height = 1080,
 # Empty keeps the project driver (Vulkan). CI smoke uses d3d12 on WARP.
 [ValidateSet('','vulkan','d3d12')][string]$RenderingDriver = '',
 [ValidateSet('','smoke')][string]$Plan = '',
 [switch]$NoGpuTiming,
 [switch]$SkipImport,
 [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This campaign requires Windows and the target physical GPU.' }
$kit = (Resolve-Path -LiteralPath $KitDirectory).Path
$manifest = Get-Content -Raw -LiteralPath (Join-Path $kit 'RENDER-KIT.json') | ConvertFrom-Json
foreach ($entry in $manifest.files) {
 $actual = (Get-FileHash -LiteralPath (Join-Path $kit $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant()
 if ($actual -ne $entry.sha256) { throw "Kit file changed: $($entry.path). Extract the ZIP again into a new folder." }
}
$editor = Join-Path $kit $manifest.editor
$server = Join-Path $kit 'asabiya-server.exe'
$runner = Join-Path $kit 'tools/render_diagnosis_runner.gd'
$harness = Join-Path $kit 'tools/render_diagnosis.gd'
$trees = @{ base = (Join-Path $kit 'source-base/client/godot'); candidate = (Join-Path $kit 'source-candidate/client/godot') }
$exported = Join-Path $kit 'exported/AsabiyaNative.exe'
$version = & $editor --version
if ($LASTEXITCODE -ne 0 -or "$version" -notmatch '^4\.7\.2\.stable\.official\.') { throw "Unexpected Godot: $version" }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $kit ('results-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
$out = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $out) { throw 'Use a new output directory; measurements are never overwritten.' }
New-Item -ItemType Directory -Path $out | Out-Null
Add-Type -AssemblyName System.Windows.Forms
$screens = @([Windows.Forms.Screen]::AllScreens | ForEach-Object { @{ primary=$_.Primary; bounds="$($_.Bounds.Width)x$($_.Bounds.Height)"; bitsPerPixel=$_.BitsPerPixel } })
$machine = @{
 os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,TotalVisibleMemorySize,FreePhysicalMemory
 computer = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory
 cpu = @(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed)
 gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,DriverDate,VideoProcessor,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate)
 screens = $screens
 power = (& powercfg /getactivescheme | Out-String).Trim()
 powerLineStatus = [Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus.ToString()
 kit = $manifest
 campaign = $Campaign
}
if ($machine.powerLineStatus -eq 'Offline' -and !$env:ASABIYA_CI_SMOKE) { throw 'Conecta el portatil a corriente antes de medir.' }
$machine | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $out 'machine.json') -Encoding UTF8

$expected = $manifest.expectedSHA256."$HistoryYears"
$diagSeconds = $Seconds
$sessions = New-Object System.Collections.Generic.List[object]
function Add-Session($id, $target, $renderer, $plan, [bool]$active, [bool]$productSync) {
 $sessions.Add(@{ id=$id; target=$target; renderer=$renderer; plan=$plan; active=$active; productSync=$productSync })
}
switch ($Campaign) {
 'quick' {
  Add-Session 'diag-forward-base' 'base' 'forward_plus' 'diagnosis' $false $false
  Add-Session 'ab-base-1' 'base' 'forward_plus' 'acceptance' $true $false
  Add-Session 'ab-candidate-1' 'candidate' 'forward_plus' 'acceptance' $true $false
  Add-Session 'ab-inprocess-candidate' 'candidate' 'forward_plus' 'ab-candidate' $false $false
  Add-Session 'exported-capacity-1' 'exported' 'forward_plus' 'acceptance' $true $false
 }
 'diagnosis' { Add-Session 'diag-forward-base' 'base' 'forward_plus' 'diagnosis' $false $false }
 'mobile' {
  Add-Session 'diag-mobile-base' 'base' 'mobile' 'mobile' $false $false
  Add-Session 'diag-forward-base-mobileplan' 'base' 'forward_plus' 'mobile' $false $false
 }
 'candidate-diagnosis' { Add-Session 'diag-forward-candidate' 'candidate' 'forward_plus' 'diagnosis' $false $false }
 'ab' {
  # ABBA-AB order exposes thermal drift; every session prepares its own history.
  foreach ($pair in @(@('base',1),@('candidate',1),@('candidate',2),@('base',2),@('base',3),@('candidate',3))) {
   Add-Session ("ab-{0}-{1}" -f $pair[0],$pair[1]) $pair[0] 'forward_plus' 'acceptance' $true $false
  }
 }
 'exported' {
  foreach ($r in 1..3) { Add-Session "exported-capacity-$r" 'exported' 'forward_plus' 'acceptance' $true $false }
  Add-Session 'exported-product-sync-1' 'exported' 'forward_plus' 'acceptance' $true $true
 }
 'full' {
  Add-Session 'diag-forward-base' 'base' 'forward_plus' 'diagnosis' $false $false
  Add-Session 'diag-mobile-base' 'base' 'mobile' 'mobile' $false $false
  foreach ($pair in @(@('base',1),@('candidate',1),@('candidate',2),@('base',2),@('base',3),@('candidate',3))) {
   Add-Session ("ab-{0}-{1}" -f $pair[0],$pair[1]) $pair[0] 'forward_plus' 'acceptance' $true $false
  }
  foreach ($r in 1..3) { Add-Session "exported-capacity-$r" 'exported' 'forward_plus' 'acceptance' $true $false }
  Add-Session 'exported-product-sync-1' 'exported' 'forward_plus' 'acceptance' $true $true
  Add-Session 'ab-inprocess-candidate' 'candidate' 'forward_plus' 'ab-candidate' $false $false
  Add-Session 'diag-forward-candidate' 'candidate' 'forward_plus' 'diagnosis' $false $false
 }
}

Write-Host "Campana '$Campaign': $($sessions.Count) sesiones. Resultados en $out"
Write-Host 'Mantiene el equipo conectado a corriente y cierra aplicaciones pesadas.'
Write-Host 'No minimices, redimensiones, uses teclado/raton ni cambies de ventana durante la captura.'
Write-Host 'Cada sesion calcula su historia una vez (avance rapido del motor) y verifica su SHA.'

function Get-Children([int]$parentId) {
 try { return @(Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $parentId) -ErrorAction Stop) } catch { return @() }
}

function Read-Json([string]$path) {
 if (!(Test-Path -LiteralPath $path)) { return $null }
 try { return (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json) } catch { return $null }
}

function Get-GpuCounters([int[]]$ids) {
 # WDDM per-process counters through CIM (class names are not localized).
 # Dedicated/Shared usage is GPU memory the driver attributes to the process;
 # it is reported as such, never relabelled as VRAM.
 $result = @{}
 try {
  $engines = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop)
  $memory = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -ErrorAction Stop)
 } catch { return $null }
 foreach ($id in $ids) {
  $prefix = "pid_$($id)_"
  $three = 0.0; $any = 0.0
  foreach ($e in $engines) {
   if ($e.Name.StartsWith($prefix)) {
    $any = [Math]::Max($any, [double]$e.UtilizationPercentage)
    if ($e.Name -like '*engtype_3D') { $three += [double]$e.UtilizationPercentage }
   }
  }
  $dedicated = $null; $shared = $null
  foreach ($m in $memory) {
   if ($m.Name.StartsWith($prefix)) { $dedicated += [int64]$m.DedicatedUsage; $shared += [int64]$m.SharedUsage }
  }
  $result[$id] = @{ gpu3dPercent=$three; gpuMaxEnginePercent=$any; gpuDedicatedBytes=$dedicated; gpuSharedBytes=$shared }
 }
 return $result
}

$sessionRecords = New-Object System.Collections.Generic.List[object]
$imported = @{}
foreach ($session in $sessions) {
 $directory = Join-Path $out $session.id
 New-Item -ItemType Directory -Path $directory | Out-Null
 $record = [ordered]@{ id=$session.id; target=$session.target; renderer=$session.renderer; plan=$session.plan; active=$session.active; productSync=$session.productSync; status='started'; error=$null }
 $process = $null
 $roles = @{}
 try {
  # Acceptance captures a full minute paused; diagnosis variants use -Seconds each.
  $planName = $session.plan
  if ($Plan) { $planName = $Plan }
  $captureSeconds = $diagSeconds
  if ($planName -eq 'acceptance') { $captureSeconds = 60 }
  $common = @('--output',('"'+$directory+'"'),'--server',('"'+$server+'"'),'--width',$Width,'--height',$Height,'--plan',$planName,
   '--seconds',$captureSeconds,'--settle-seconds',4,'--warmup-seconds',20,'--history-years',$HistoryYears,'--prepare-timeout',$PrepareTimeout,
   '--rate',$Rate,'--active-seconds',$ActiveSeconds,'--label',$session.id)
  if ($expected) { $common += @('--expected-sha',$expected) }
  if ($session.active) { $common += '--active' }
  if ($session.productSync) { $common += '--product-sync' }
  if ($session.plan -eq 'ab-candidate') { $common += '--equivalence' }
  if ($NoGpuTiming) { $common += '--no-gpu-timing' }
  $driver = @()
  if ($RenderingDriver) { $driver = @('--rendering-driver',$RenderingDriver) }
  if ($session.target -eq 'exported') {
   if (!(Test-Path -LiteralPath $exported)) { throw 'Exported executable missing from the kit.' }
   $common += @('--revision',$manifest.candidateRevision)
   # Same executable the user runs; the opt-in flag hands control to the harness.
   $arguments = $driver + @('--rendering-method',$session.renderer,'--windowed','--audio-driver','Dummy','--log-file',('"'+(Join-Path $directory 'godot.log')+'"'),'--','--render-diagnosis') + $common
   $exe = $exported
  } else {
   $project = $trees[$session.target]
   if (!$SkipImport -and !$imported.ContainsKey($session.target)) {
    Write-Host "Importando recursos ($($session.target))..."
    $importLog = Join-Path $out ("import-" + $session.target + ".log")
    & $editor --headless --editor --path $project --import *> $importLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR|Parse Error|Compilation failed' -Quiet)) { throw "Import failed; see $importLog" }
    $imported[$session.target] = $true
   }
   $revision = $manifest.baseRevision
   if ($session.target -eq 'candidate') { $revision = $manifest.candidateRevision }
   $common += @('--revision',$revision,'--harness',('"'+$harness+'"'))
   $arguments = $driver + @('--path',('"'+$project+'"'),'--script',('"'+$runner+'"'),'--rendering-method',$session.renderer,'--windowed','--audio-driver','Dummy','--') + $common
   $exe = $editor
  }
  Write-Host ("[{0}] {1} {2} {3}" -f (Get-Date -Format 'HH:mm:ss'),$session.id,$session.renderer,$session.plan)
  $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $kit -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
  $samples = New-Object System.Collections.Generic.List[object]
  $notes = New-Object System.Collections.Generic.List[string]
  $clock = [Diagnostics.Stopwatch]::StartNew()
  $previous = @{}
  $roles[$process.Id] = 'launcher'
  $lastGpu = -10.0
  $gpu = $null
  $budget = $PrepareTimeout + 2400
  while (!$process.HasExited) {
   if ($clock.Elapsed.TotalSeconds -gt $budget) { throw "Session exceeded $budget s; last phase recorded in phase.json" }
   # Console wrapper -> graphical Godot -> Go server. Resolve by parentage,
   # then cross-check with the PIDs the harness itself reports.
   foreach ($known in @($roles.Keys)) {
    foreach ($child in (Get-Children $known)) {
     if (!$roles.ContainsKey([int]$child.ProcessId)) {
      $role = 'other'
      if ($child.Name -like 'asabiya-server*') { $role = 'go-server' }
      elseif ($child.Name -like 'Godot*' -or $child.Name -like 'AsabiyaNative*') { $role = 'godot-graphical' }
      $roles[[int]$child.ProcessId] = $role
     }
    }
   }
   if (!($roles.Values -contains 'godot-graphical') -and $exe -eq $exported) { $roles[$process.Id] = 'godot-graphical' }
   $ready = Read-Json (Join-Path $directory 'ready.json')
   if ($ready) {
    foreach ($pair in @(@([int]$ready.clientPid,'godot-graphical'),@([int]$ready.serverPid,'go-server'))) {
     if ($roles.ContainsKey($pair[0]) -and $roles[$pair[0]] -ne $pair[1]) { $notes.Add("PID $($pair[0]) resolved as $($roles[$pair[0]]) but harness reports $($pair[1])") }
     $roles[$pair[0]] = $pair[1]
    }
   }
   $phase = Read-Json (Join-Path $directory 'phase.json')
   $phaseName = ''
   if ($phase) { $phaseName = $phase.phase }
   if ($clock.Elapsed.TotalSeconds - $lastGpu -ge 2.0) {
    $lastGpu = $clock.Elapsed.TotalSeconds
    $gpu = Get-GpuCounters @($roles.Keys)
    if ($gpu -eq $null -and !($notes -contains 'GPU counters unavailable')) { $notes.Add('GPU counters unavailable') }
   } else { $gpu = $null }
   foreach ($sampleId in @($roles.Keys)) {
    try {
     $p = Get-Process -Id $sampleId -ErrorAction Stop
     $now = $clock.Elapsed.TotalMilliseconds
     $cpu = $p.TotalProcessorTime.TotalMilliseconds
     $cores = $null
     if ($previous.ContainsKey($sampleId) -and $now -gt $previous[$sampleId].wall) { $cores = ($cpu-$previous[$sampleId].cpu)/($now-$previous[$sampleId].wall) }
     $previous[$sampleId] = @{wall=$now;cpu=$cpu}
     $row = [ordered]@{utc=(Get-Date).ToUniversalTime().ToString('o');elapsedS=[Math]::Round($now/1000.0,3);phase=$phaseName;role=$roles[$sampleId];pid=$sampleId;name=$p.ProcessName;
      cpuCores=$cores;workingSetBytes=$p.WorkingSet64;privateBytes=$p.PrivateMemorySize64;gpu3dPercent=$null;gpuMaxEnginePercent=$null;gpuDedicatedBytes=$null;gpuSharedBytes=$null}
     if ($gpu -and $gpu.ContainsKey($sampleId)) { foreach ($k in $gpu[$sampleId].Keys) { $row[$k] = $gpu[$sampleId][$k] } }
     $samples.Add([pscustomobject]$row)
    } catch {}
   }
   Start-Sleep -Milliseconds 1000
   $process.Refresh()
  }
  $process.WaitForExit()
  $samples | Export-Csv -LiteralPath (Join-Path $directory 'processes.csv') -NoTypeInformation -Encoding UTF8
  if ($notes.Count -gt 0) { $notes | Set-Content -LiteralPath (Join-Path $directory 'process-notes.txt') -Encoding UTF8 }
  $run = Read-Json (Join-Path $directory 'run.json')
  if ([Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus.ToString() -eq 'Offline' -and !$env:ASABIYA_CI_SMOKE) { throw 'Power disconnected during the session; repeat on AC.' }
  if ($process.ExitCode -ne 0 -or !$run) {
   $reason = 'see stderr.log'
   if (Test-Path -LiteralPath (Join-Path $directory 'error.txt')) { $reason = (Get-Content -Raw -LiteralPath (Join-Path $directory 'error.txt')).Trim() }
   throw "Invalid session (exit $($process.ExitCode)): $reason"
  }
  if (!$run.valid) { throw "Invalid session: $($run.invalidReason)" }
  $record.status = 'valid'
  $record.initialSHA256 = $run.initialSHA256
  $record.prepareSeconds = $run.prepareSeconds
  $record.renderer = $run.renderer
 } catch {
  $record.status = 'failed'
  $record.error = $_.Exception.Message
  Write-Host "  FALLO: $($record.error)" -ForegroundColor Yellow
  if ($process -and !$process.HasExited) {
   # Stop only processes this session started (by recorded parentage).
   foreach ($id in @($roles.Keys)) { if ($id -ne $process.Id) { Stop-Process -Id $id -ErrorAction SilentlyContinue } }
   Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
  }
  $record.error | Set-Content -LiteralPath (Join-Path $directory 'session-error.txt') -Encoding UTF8
 }
 $sessionRecords.Add([pscustomobject]$record)
 ConvertTo-Json -InputObject @($sessionRecords.ToArray()) -Depth 10 | Set-Content -LiteralPath (Join-Path $out 'campaign.json') -Encoding UTF8
}

# Human summary: one row per captured experiment, without averaging across sessions.
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('session,index,experiment,valid,samples,fpsP50,frameP50,frameP95,frameP99,gpuP50,gpuP95,gpuP99,renderCpuP50,processP50,drawCalls,shadowDrawCalls,primitives,shadowPrimitives,over33msPercent,minFullSecondFrames')
foreach ($record in $sessionRecords) {
 $experiments = Read-Json (Join-Path (Join-Path $out $record.id) 'experiments.json')
 if (!$experiments) { continue }
 foreach ($e in $experiments.experiments) {
  $s = $e.summary
  if (!$s -or !$s.frameMs) { $lines.Add(("{0},{1},{2},false,0" -f $record.id,$e.index,$e.name)); continue }
  $lines.Add((@($record.id,$e.index,$e.name,$e.valid,$e.samples,$s.fpsP50,$s.frameMs.p50,$s.frameMs.p95,$s.frameMs.p99,$s.renderGpuMs.p50,$s.renderGpuMs.p95,$s.renderGpuMs.p99,$s.renderCpuMs.p50,$s.processMs.p50,$s.drawCalls.p50,$s.shadowDrawCalls.p50,$s.primitives.p50,$s.shadowPrimitives.p50,$s.over33msPercent,$s.minFullSecondFrames) | ForEach-Object { if ($_ -is [double]) { $_.ToString('0.###',[Globalization.CultureInfo]::InvariantCulture) } else { "$_" } }) -join ',')
 }
}
$lines | Set-Content -LiteralPath (Join-Path $out 'summary.csv') -Encoding UTF8
$proofs = @($sessionRecords | Where-Object { $_.status -eq 'valid' } | ForEach-Object { $_.initialSHA256 } | Sort-Object -Unique)
if ($proofs.Count -gt 1) { Write-Host 'ATENCION: las sesiones no partieron del mismo estado historico; no son comparables.' -ForegroundColor Red }
$failed = @($sessionRecords | Where-Object { $_.status -ne 'valid' }).Count
Write-Host "Campana terminada: $($sessionRecords.Count - $failed) sesiones validas, $failed fallidas."
Write-Host "Comprime y entrega la carpeta completa: $out"
