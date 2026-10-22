param(
    [string]$Directory = $PSScriptRoot,
    [int]$Seconds = 30,
    [int]$PreparationYears = 10000,
    [int]$Repeats = 1,
    [switch]$Full
)
$ErrorActionPreference = 'Stop'
$Directory = (Resolve-Path $Directory).Path
$exe = Join-Path $Directory 'AsabiyaAtlas2D.exe'
if (!(Test-Path $exe)) { throw "No se encuentra $exe. Extrae todo el paquete antes de medir." }
$out = Join-Path $Directory ('mediciones-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $out | Out-Null
@{
    system = @(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber)
    cpu = @(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfLogicalProcessors)
    gpu = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion)
    computer = @(Get-CimInstance Win32_ComputerSystem | Select-Object Model,TotalPhysicalMemory)
    capturedUtc = (Get-Date).ToUniversalTime().ToString('o')
    targetHardwareVerified = $false
} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out 'equipo.json') -Encoding UTF8
$files = @()
$failures = @()
$zooms = if ($Full) { @(1,4,24) } else { @(24) }
if ($Full -and !$PSBoundParameters.ContainsKey("Repeats")) { $Repeats = 3 }
foreach ($repeat in 1..$Repeats) {
    foreach ($resolution in @(@(1920,1080),@(1280,720))) {
        foreach ($zoom in $zooms) {
            foreach ($active in @($false,$true)) {
                $name = "$($resolution[0])x$($resolution[1])-zoom$zoom-active$active-r$repeat"
                Write-Host "Midiendo $name. No uses otras aplicaciones durante la captura."
                $raw = Join-Path $out ($name + '.jsonl')
                $memory = Join-Path $out ($name + '.memory.jsonl')
                $arguments = @('--',"--bench-out=$raw","--seconds=$Seconds","--year=$PreparationYears","--width=$($resolution[0])","--height=$($resolution[1])","--zoom=$zoom")
                if ($active) { $arguments += '--active' }
                $quoted = ($arguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }) -join ' '
                $process = $null
                $goPid = 0
                try {
                $process = Start-Process -FilePath $exe -ArgumentList $quoted -PassThru -WorkingDirectory $Directory -RedirectStandardError (Join-Path $out ($name+'.stderr.log')) -RedirectStandardOutput (Join-Path $out ($name+'.stdout.log'))
                $null = $process.Handle
                $deadline = (Get-Date).AddMinutes(20)
                $goPid = 0
                $godotPid = $process.Id
                while (!$process.HasExited) {
                    if ((Get-Date) -gt $deadline) {
                        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
                        if ($goPid -gt 0) { Stop-Process -Id $goPid -ErrorAction SilentlyContinue }
                        throw "Tiempo agotado: $name; se conserva la captura incompleta."
                    }
                    if (Test-Path $raw) {
                        foreach ($line in @(Get-Content $raw -ErrorAction SilentlyContinue)) {
                            try { $row = $line | ConvertFrom-Json } catch { continue }
                            if ($row.kind -eq 'environment') { $godotPid = [int]$row.pid }
                            if ($row.kind -eq 'ready') { $goPid = [int]$row.go_pid }
                        }
                    }
                    $gd = Get-Process -Id $godotPid -ErrorAction SilentlyContinue
                    $goProcess = if ($goPid -gt 0) { Get-Process -Id $goPid -ErrorAction SilentlyContinue } else { $null }
                    if ($gd) {
                        $goBytes = if ($goProcess) { [long]$goProcess.WorkingSet64 } else { 0 }
                        $goCpu = if ($goProcess) { $goProcess.TotalProcessorTime.TotalMilliseconds } else { 0 }
                        @{utc=(Get-Date).ToUniversalTime().ToString('o');godot_pid=$godotPid;go_pid=$goPid;godot_bytes=[long]$gd.WorkingSet64;go_bytes=$goBytes;combined_bytes=([long]$gd.WorkingSet64+$goBytes);godot_private_bytes=[long]$gd.PrivateMemorySize64;godot_cpu_ms=$gd.TotalProcessorTime.TotalMilliseconds;go_cpu_ms=$goCpu} | ConvertTo-Json -Compress | Add-Content $memory -Encoding UTF8
                    }
                    Start-Sleep -Milliseconds 500
                    $process.Refresh()
                }
                $process.WaitForExit()
                if ($process.ExitCode -ne 0) { throw "El atlas terminó con error en $name. Revisa los logs." }
                $text = Get-Content -Raw $raw
                if ($text -notmatch 'verified_pause' -or $text -match '"kind":"error"') { throw "Captura incompleta: $name" }
                $logs = (Get-Content -Raw (Join-Path $out ($name+'.stderr.log')))
                if ($logs -match 'SCRIPT ERROR|SHADER ERROR') { throw "Error de ejecución: $name" }
                $files += $raw
                } catch {
                    # Recoverable: record this case and continue with the next one.
                    $failures += [pscustomobject]@{case=$name; error=$_.Exception.Message}
                    $_.Exception.Message | Set-Content (Join-Path $out ($name + '.error.txt')) -Encoding UTF8
                    Write-Host "  FALLO en ${name}: $($_.Exception.Message)" -ForegroundColor Yellow
                    if ($process -and !$process.HasExited) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
                    if ($goPid -gt 0) { Stop-Process -Id $goPid -ErrorAction SilentlyContinue }
                }
            }
        }
    }
}
$failures | ConvertTo-Json | Set-Content (Join-Path $out 'fallos.json') -Encoding UTF8
Write-Host "Capturas terminadas: $out ($($files.Count) validas, $($failures.Count) fallidas)"
Write-Host 'Comparte esta carpeta completa. Incluye datos crudos y memoria de ambos procesos.'
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python -and $python.Source -notlike "*WindowsApps*") { & $python.Source (Join-Path $Directory 'summarize.py') @files --out (Join-Path $out 'resumen.json') }
