$ErrorActionPreference='Stop'
. "$PSScriptRoot/../tools/telemetry.ps1"
function Assert($Condition,[string]$Message) {if (!$Condition) {throw $Message}}
$path=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N')+'.jsonl')
$writer=[IO.FileStream]::new($path,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
$tail=[AtlasTail]::new($path)
try {
    $first=[Text.Encoding]::UTF8.GetBytes('{"kind":"a","text":"año 日本"}')
    # Split inside UTF-8, then poll twice before completing the line.
    $writer.Write($first,0,$first.Length-2);$writer.Flush()
    Assert (@($tail.ReadLines()).Count -eq 0) 'Partial line was returned'
    Assert (@($tail.ReadLines()).Count -eq 0) 'Old bytes were replayed'
    $writer.Write($first,$first.Length-2,2);$writer.WriteByte(10);$writer.Flush()
    $row=@($tail.ReadLines())
    Assert ($row.Count -eq 1 -and ($row[0] | ConvertFrom-Json).text -eq 'año 日本') 'UTF-8 partial row lost'
    for ($n=0;$n -lt 10000;$n++) {
        $bytes=[Text.Encoding]::UTF8.GetBytes("{`"n`":$n}`n")
        $writer.Write($bytes,0,$bytes.Length)
    }
    $writer.Flush();$lines=@($tail.ReadLines())
    Assert ($lines.Count -eq 10000) 'Appended rows lost'
    Assert ($tail.BytesRead -eq $writer.Length) 'Reader did not consume exactly one pass'
    Assert (@($tail.ReadLines()).Count -eq 0) 'Rows replayed'
    $missing=Get-AtlasSample $null 1 1
    Assert ($missing.status -eq 'undiscovered' -and $null -eq $missing.working_set_bytes) 'Missing process became zero'
    $self=Get-Process -Id $PID
    $identity=[pscustomobject]@{process=$self;id=$PID;start=$self.StartTime.ToUniversalTime().Ticks;lastCpu=$null;lastTime=$null}
    $sample=Get-AtlasSample $identity 1 1
    Assert ($sample.status -eq 'ok' -and $null -eq $sample.cpu_machine_percent) 'First CPU sample must be null'
    $identity.start+=1
    $sample=Get-AtlasSample $identity 2 1
    Assert ($sample.status -eq 'unavailable' -and $null -eq $sample.working_set_bytes) 'PID reuse was accepted'
    $parseErrors=$null;$tokens=$null
    $null=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../tools/benchmark.ps1'),[ref]$tokens,[ref]$parseErrors)
    Assert ($parseErrors.Count -eq 0) 'Benchmark PowerShell parse failed'
    if ($env:OS -eq 'Windows_NT') {
        Assert ([AtlasNative]::AvailableMemory() -gt 0) 'Windows available memory unavailable'
        Assert ((Get-AtlasWindow $PID).status -eq 'ok') 'Windows window telemetry failed'
        $bound=Get-AtlasIdentity $PID $self.Path
        Assert ($bound.id -eq $PID) 'Identity did not bind to PID'
        $failed=$false
        try {$null=Get-AtlasIdentity $PID 'C:\wrong.exe'} catch {$failed=$true}
        Assert $failed 'Wrong executable accepted'
        $child=Start-Process $self.Path -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 10') -PassThru
        try {
            $bound=Get-AtlasIdentity $child.Id $self.Path $PID
            Stop-AtlasOwned $bound;$child.WaitForExit()
            $dead=Get-AtlasSample $bound 2 1
            Assert ($dead.status -eq 'unavailable' -and $null -eq $dead.working_set_bytes) 'Exited child became zero'
        } finally {if (!$child.HasExited) {$child.Kill()}}
    }
    Write-Host 'ATLAS TELEMETRY TESTS: 0 failures'
} finally {$tail.Dispose();$writer.Dispose();Remove-Item $path -ErrorAction SilentlyContinue}
