param(
    [string]$Directory = $PSScriptRoot,
    [ValidateRange(3,600)][int]$Seconds = 30,
    [ValidateRange(0,10000)][int]$PreparationYears = 10000,
    [ValidateRange(1,10)][int]$Repeats = 3,
    [ValidateSet('baseline','minimal','detailed')][string[]]$Modes = @('baseline','minimal','detailed'),
    [ValidateRange(100,5000)][int]$PollMilliseconds = 500,
    [switch]$Full,
    [switch]$StaticCamera,
    [switch]$NoSelection,
    [switch]$Small
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'telemetry.ps1')
$Directory = (Resolve-Path $Directory).Path
$exe = Join-Path $Directory 'AsabiyaAtlas2D.exe'
$server = Join-Path $Directory 'asabiya-server.exe'
$presentmon = Join-Path $Directory 'PresentMon.exe'
foreach ($file in @($exe,$server)) { if (!(Test-Path $file)) { throw "Extrae todo el paquete: falta $file" } }
if (@($Modes | Where-Object {$_ -ne 'baseline'}).Count -gt 0) {
    if (!(Test-Path $presentmon)) { throw 'Falta PresentMon.exe; extrae el paquete completo.' }
    if ((Get-FileHash $presentmon -Algorithm SHA256).Hash.ToLowerInvariant() -ne '690533cf5c2591ef571a3037aa4c205c8e75860ef3f56927bf3a98acf7198485') { throw 'PresentMon SHA256 incorrecto' }
}
# Refuse changed package files; the manifest itself is retained with every result.
$manifestPath=Join-Path $Directory 'build-manifest.json'
$manifest=Get-Content -Raw $manifestPath | ConvertFrom-Json
foreach ($property in $manifest.files.PSObject.Properties) {
    $path=Join-Path $Directory $property.Name
    if ((Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $property.Value) { throw "Paquete modificado: $($property.Name)" }
}
$out = Join-Path $Directory ('mediciones-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $out | Out-Null
Copy-Item $manifestPath $out
# Check ETW permission before spending minutes on historical preparation.
if (@($Modes | Where-Object {$_ -ne 'baseline'}).Count -gt 0) {
    $preflight=Start-Process $presentmon -ArgumentList @('--process_id',[string]$PID,'--no_csv','--no_console_stats','--timed','1','--terminate_after_timed','--session_name',('AtlasPreflight-'+[guid]::NewGuid().ToString('N'))) -PassThru -RedirectStandardOutput (Join-Path $out 'presentmon-preflight.stdout.log') -RedirectStandardError (Join-Path $out 'presentmon-preflight.stderr.log')
    $null=$preflight.Handle
    try {
        if (!$preflight.WaitForExit(15000)) {throw 'PresentMon preflight agotado; revisa los logs ETW.'}
        if ($preflight.ExitCode -ne 0) {throw "PresentMon preflight exit $($preflight.ExitCode). Consulta BENCHMARK.md para permisos ETW."}
    } finally {if (!$preflight.HasExited) {$preflight.Kill()}}
}

$logicalCpus=[Environment]::ProcessorCount
$equipment=@{
    system = @(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber)
    cpu = @(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfLogicalProcessors)
    gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,PNPDeviceID,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate)
    computer = @(Get-CimInstance Win32_ComputerSystem | Select-Object Model,TotalPhysicalMemory)
    battery = @(Get-CimInstance Win32_Battery | Select-Object BatteryStatus,EstimatedChargeRemaining)
    powerScheme = @(& powercfg /getactivescheme)
    capturedUtc = [DateTime]::UtcNow.ToString('o'); powershell=$PSVersionTable.PSVersion.ToString()
    targetHardwareVerified = $null; verificationStatus='pending renderer evidence'
    parameters=@{seconds=$Seconds;preparationYears=$PreparationYears;repeats=$Repeats;modes=$Modes;pollMilliseconds=$PollMilliseconds;full=[bool]$Full;small=[bool]$Small;staticCamera=[bool]$StaticCamera;noSelection=[bool]$NoSelection}
}
$equipment | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $out 'equipo.json') -Encoding UTF8
$files = @(); $zooms = if ($Full) { @(1,4,24) } else { @(24) }
$suite=[IO.StreamWriter]::new((Join-Path $out 'suite.jsonl'),$false,[Text.UTF8Encoding]::new($false)); $suite.AutoFlush=$true
try {
foreach ($repeat in 1..$Repeats) {
    $cases=@()
    foreach ($resolution in @(@(1920,1080),@(1280,720))) {
        foreach ($zoom in $zooms) { foreach ($active in @($false,$true)) {
            $cases+=,@{width=$resolution[0];height=$resolution[1];zoom=$zoom;active=$active}
        } }
    }
    # Reverse scenarios on alternate repetitions and rotate profiler order deterministically.
    if ($repeat % 2 -eq 0) { [array]::Reverse($cases) }
    foreach ($case in $cases) {
        for ($m=0;$m -lt $Modes.Count;$m++) {
            $mode=$Modes[($m+$repeat-1)%$Modes.Count]
            $name="$($case.width)x$($case.height)-zoom$($case.zoom)-active$($case.active)-$mode-r$repeat"
            Write-Host "Midiendo $name. Mantén la ventana visible y el equipo conectado a corriente."
            $raw=Join-Path $out ($name+'.jsonl'); $prefix=Join-Path $out $name
            $arguments=@('--',"--bench-out=$raw","--seconds=$Seconds","--year=$PreparationYears","--width=$($case.width)","--height=$($case.height)","--zoom=$($case.zoom)","--instrumentation=$mode")
            if ($StaticCamera) {$arguments+='--no-pan'};if ($NoSelection) {$arguments+='--no-selection'}
            if ($case.active) {$arguments+='--active'}; if ($Small) {$arguments+='--small'}
            $quoted=($arguments | ForEach-Object {'"'+$_.Replace('"','\"')+'"'}) -join ' '
            Write-AtlasJson $suite @{kind='case_begin';name=$name;repeat=$repeat;mode=$mode;case=$case;arguments=$arguments;utc=[DateTime]::UtcNow.ToString('o')}
            $gd=$null;$goIdentity=$null;$pmIdentity=$null;$tail=$null;$process=$null;$pm=$null;$endpoint=$null;$seenEnd=$false;$verified=$false;$hasError=$false
            $writer=[IO.StreamWriter]::new(($prefix+'.telemetry.jsonl'),$false,[Text.UTF8Encoding]::new($false));$writer.AutoFlush=$true
            $lastPollMs=$null
            $watch=[Diagnostics.Stopwatch]::StartNew();$harness=Get-Process -Id $PID
            $collector= [pscustomobject]@{process=$harness;id=$PID;start=$harness.StartTime.ToUniversalTime().Ticks;lastCpu=$null;lastTime=$null}
            try {
                $process=Start-Process -FilePath $exe -ArgumentList $quoted -PassThru -WorkingDirectory $Directory -RedirectStandardError ($prefix+'.stderr.log') -RedirectStandardOutput ($prefix+'.stdout.log')
                $null=$process.Handle
                $gd=Get-AtlasIdentity $process.Id $exe
                Write-AtlasJson $writer @{kind='identity';role='godot';pid=$gd.id;start_utc_ticks=$gd.start;path=$gd.path;parent=$gd.parent;command=$gd.command}
                while ($true) {
                    $pollStart=$watch.Elapsed.TotalSeconds
                    if ($pollStart -gt 1200) {throw "Tiempo agotado: $name"}
                    if ($null -eq $tail -and (Test-Path $raw)) {$tail=[AtlasTail]::new($raw)}
                    if ($null -ne $tail) {
                        foreach ($line in $tail.ReadLines()) {
                            if (!$line.Trim()) {continue}
                            $row=$line | ConvertFrom-Json
                            if ($row.kind -eq 'environment') {
                                if ($row.pid -ne $gd.id) {throw 'Godot PID mismatch'}
                                $renderMatch=([string]$row.gpu -match 'Intel.*Iris.*Xe' -and !$row.headless)
                                $inventoryMatch=@($equipment.gpu | Where-Object {$_.Name -match 'Intel.*Iris.*Xe'}).Count -gt 0
                                $cpuMatch=([string]$row.cpu -match 'i5-1340P')
                                $equipment.targetHardwareVerified=($renderMatch -and $inventoryMatch -and $cpuMatch)
                                $equipment.verificationStatus='Godot active adapter + Windows inventory + CPU; does not certify performance'
                                $equipment | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $out 'equipo.json') -Encoding UTF8
                            }
                            if ($row.kind -eq 'processes' -and $null -eq $goIdentity) {
                                if ($row.godot_pid -ne $gd.id) {throw 'Owner mismatch'}
                                $goIdentity=Get-AtlasIdentity ([int]$row.go_pid) $server $gd.id
                                if (!$goIdentity.command.Contains([string]$row.endpoint_file) -or $goIdentity.command -notmatch "--parent-pid\s+$($gd.id)(\s|$)") {throw 'Go session command mismatch'}
                                $endpoint=[string]$row.endpoint_file
                                Write-AtlasJson $writer @{kind='identity';role='go';pid=$goIdentity.id;start_utc_ticks=$goIdentity.start;path=$goIdentity.path;parent=$goIdentity.parent;command=$goIdentity.command;endpoint_file=$endpoint}
                                if ($mode -ne 'baseline') {
                                    $session='Atlas-'+[guid]::NewGuid().ToString('N')
                                    $pmArgs=@('--process_id',[string]$gd.id,'--output_file',('"'+$prefix+'.presentmon.csv"'),'--qpc_time','--no_console_stats','--session_name',$session,'--terminate_on_proc_exit')
                                    $pm=Start-Process $presentmon -ArgumentList $pmArgs -PassThru -RedirectStandardOutput ($prefix+'.presentmon.stdout.log') -RedirectStandardError ($prefix+'.presentmon.stderr.log')
                                    $null=$pm.Handle;$pmIdentity=Get-AtlasIdentity $pm.Id $presentmon
                                }
                            }
                            if ($row.kind -eq 'end') {$seenEnd=$true}
                            if ($row.kind -eq 'verified_pause' -and $row.exact) {$verified=$true}
                            if ($row.kind -eq 'error') {$hasError=$true}
                        }
                    }
                    if ($null -ne $pm) { $pm.Refresh(); if ($pm.HasExited -and !$process.HasExited) {throw "PresentMon terminó antes del Atlas ($($pm.ExitCode)). Revisa permisos ETW/logs."} }
                    $now=$watch.Elapsed.TotalSeconds
                    $qpc=[Diagnostics.Stopwatch]::GetTimestamp();$utc=[DateTime]::UtcNow;$qpcAfter=[Diagnostics.Stopwatch]::GetTimestamp()
                    $gdSample=Get-AtlasSample $gd $now $logicalCpus;$goSample=Get-AtlasSample $goIdentity $now $logicalCpus
                    Write-AtlasJson $writer @{kind='sample';elapsed_s=$now;utc=$utc.ToString('o');qpc=$qpc;qpc_after_utc=$qpcAfter;qpc_frequency=[Diagnostics.Stopwatch]::Frequency;godot=$gdSample;go=$goSample;collector=(Get-AtlasSample $collector $now $logicalCpus);presentmon=(Get-AtlasSample $pmIdentity $now $logicalCpus);window=(Get-AtlasWindow $gd.id);available_memory_bytes=[AtlasNative]::AvailableMemory();combined_working_set_bytes=$(if ($gdSample.status -eq 'ok' -and $goSample.status -eq 'ok') {$gdSample.working_set_bytes+$goSample.working_set_bytes} else {$null});jsonl_bytes_read=$(if ($null -ne $tail) {$tail.BytesRead} else {0});poll_work_ms=$lastPollMs}
                    $lastPollMs=1000*($watch.Elapsed.TotalSeconds-$pollStart)
                    if ($process.HasExited) {break}
                    $remaining=$PollMilliseconds-1000*($watch.Elapsed.TotalSeconds-$pollStart)
                    if ($remaining -gt 0) {Start-Sleep -Milliseconds ([int]$remaining)}
                    $process.Refresh()
                }
                $process.WaitForExit()
                if ($process.ExitCode -ne 0 -or !$seenEnd -or !$verified -or $hasError -or $null -eq $goIdentity) {throw "Captura incompleta: $name"}
                if ($null -ne $pm) {
                    if (!$pm.WaitForExit(10000)) {throw 'PresentMon no terminó; se conserva la captura incompleta'}
                    if ($pm.ExitCode -ne 0) {throw "PresentMon exit $($pm.ExitCode)"}
                }
                foreach ($log in @($prefix+'.stdout.log',$prefix+'.stderr.log')) {if (Select-String -Path $log -Pattern 'SCRIPT ERROR|SHADER ERROR|Parse Error') {throw "Error de ejecución en $log"}}
                $files+=$raw
                Write-AtlasJson $suite @{kind='case_end';name=$name;status='captured';utc=[DateTime]::UtcNow.ToString('o')}
            } catch {
                Write-AtlasJson $suite @{kind='case_end';name=$name;status='failed';reason=$_.Exception.Message;utc=[DateTime]::UtcNow.ToString('o')}
                throw
            } finally {
                Stop-AtlasOwned $pmIdentity;Stop-AtlasOwned $goIdentity;Stop-AtlasOwned $gd
                # A launch handle remains bound to its original process even if identity lookup failed.
                if ($null -ne $pm -and $null -eq $pmIdentity -and !$pm.HasExited) {$pm.Kill()}
                if ($null -ne $process -and $null -eq $gd -and !$process.HasExited) {$process.Kill()}
                if ($null -ne $endpoint) {
                    foreach ($leaf in @('engine.log','endpoint.json')) {
                        $source=Join-Path (Split-Path $endpoint) $leaf
                        if (Test-Path $source) {Copy-Item $source ($prefix+'.go-'+$leaf) -ErrorAction SilentlyContinue}
                    }
                }
                if ($null -ne $tail) {$tail.Dispose()};$writer.Dispose()
            }
        }
    }
}
} finally {$suite.Dispose()}
Write-Host "Capturas terminadas: $out. Comparte la carpeta completa."
$python=Get-Command python -ErrorAction SilentlyContinue
if ($python -and $python.Source -notlike '*WindowsApps*') {
    & $python.Source (Join-Path $Directory 'summarize.py') @files --out (Join-Path $out 'resumen.json')
    if ($LASTEXITCODE -ne 0) {throw 'Resumen fallido; se conservan todos los crudos'}
} else {Write-Host 'Sin Python: captura conservada; el resumen se puede generar en otro equipo.'}
