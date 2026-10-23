param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
Assert ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) 'Run this regression with Windows PowerShell 5.1'
$PackageDirectory = (Resolve-Path -LiteralPath $PackageDirectory).Path
$null = New-Item -ItemType Directory -Force -Path $EvidenceDirectory
$EvidenceDirectory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$testPackage = Join-Path $EvidenceDirectory 'package with spaces [ps51]'
$null = New-Item -ItemType Directory -Path $testPackage
Get-ChildItem -LiteralPath $PackageDirectory | Copy-Item -Destination $testPackage -Recurse
# Keep the actual packaged harness, profiler, Python summarizer and integrity checks.
# Replace only its two producer executables with native test fixtures, never the source engine.
$fixtureExe = Join-Path $EvidenceDirectory 'benchmark-fixture.exe'
Add-Type -Path (Join-Path $PSScriptRoot 'benchmark_fixture.cs') -ReferencedAssemblies 'System.Web.Extensions' -OutputAssembly $fixtureExe -OutputType ConsoleApplication
foreach ($leaf in @('AsabiyaAtlas2D.exe', 'asabiya-server.exe')) {
    Copy-Item -LiteralPath $fixtureExe -Destination (Join-Path $testPackage $leaf) -Force
}
$manifestPath = Join-Path $testPackage 'build-manifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
foreach ($property in $manifest.files.PSObject.Properties) {
    $property.Value = (Get-FileHash -LiteralPath (Join-Path $testPackage $property.Name) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$powershell = Join-Path $PSHOME 'powershell.exe'
$benchmark = Join-Path $testPackage 'benchmark.ps1'
$script:invocation = 0
function Invoke-Benchmark([string[]]$ExtraArguments, [bool]$ExpectSuccess) {
    $script:invocation++
    $before = @(Get-ChildItem -LiteralPath $testPackage -Directory -Filter 'mediciones-*' | ForEach-Object Name)
    $log = Join-Path $EvidenceDirectory ("invocation-$script:invocation.log")
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $benchmark, '-Directory', $testPackage,
        '-Small', '-PreparationYears', '0', '-Seconds', '3', '-PollMilliseconds', '100') + $ExtraArguments
    $quoted = ($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
    $process = Start-Process $powershell -ArgumentList $quoted -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + '.stderr')
    $null = $process.Handle
    try {
        if (!$process.WaitForExit(240000)) { throw "Benchmark regression timed out; see $log" }
        $process.WaitForExit()
        $code = $process.ExitCode
    } finally {
        if (!$process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
    if (($code -eq 0) -ne $ExpectSuccess) {
        Get-Content -LiteralPath $log | Write-Host
        Get-Content -LiteralPath ($log + '.stderr') | Write-Host
    }
    Assert (($code -eq 0) -eq $ExpectSuccess) "Unexpected benchmark exit $code; see $log"
    $created = @(Get-ChildItem -LiteralPath $testPackage -Directory -Filter 'mediciones-*' | Where-Object { $_.Name -notin $before })
    Assert ($created.Count -eq 1) 'Expected one capture directory'
    return $created[0].FullName
}
function Read-Rows([string]$Path) {
    Get-Content -LiteralPath $Path | ForEach-Object { $_ | ConvertFrom-Json }
}
function Assert-Captures([string]$Directory, [int]$Expected, [string[]]$ExpectedModes) {
    $suite = @(Read-Rows (Join-Path $Directory 'suite.jsonl'))
    $begins = @($suite | Where-Object kind -eq 'case_begin')
    $ends = @($suite | Where-Object kind -eq 'case_end')
    Assert ($begins.Count -eq $Expected -and $ends.Count -eq $Expected) 'Suite stopped before all cases completed'
    Assert (@($ends | Where-Object status -ne 'captured').Count -eq 0) 'A scenario failed'
    $scenarios = @($begins | ForEach-Object { "$($_.case.width)x$($_.case.height)-$($_.case.active)" } | Sort-Object -Unique)
    Assert (($scenarios -join ',') -eq '1280x720-False,1280x720-True,1920x1080-False,1920x1080-True') 'Four scenario coverage missing'
    foreach ($begin in $begins) {
        $prefix = Join-Path $Directory $begin.name
        foreach ($suffix in @('.stdout.log', '.stderr.log', '.jsonl', '.telemetry.jsonl')) {
            Assert (Test-Path -LiteralPath ($prefix + $suffix)) "Missing independent output: $prefix$suffix"
        }
        $telemetry = @(Read-Rows ($prefix + '.telemetry.jsonl'))
        foreach ($role in @('godot', 'go')) {
            Assert (@($telemetry | Where-Object { $_.kind -eq 'identity' -and $_.role -eq $role }).Count -eq 1) "Missing native $role identity"
        }
        if ($begin.mode -ne 'baseline') {
            Assert (@($telemetry | Where-Object { $_.kind -eq 'sample' -and $_.presentmon.status -eq 'ok' }).Count -gt 0) 'PresentMon branch was not exercised'
        }
    }
    $summary = Get-Content -Raw -LiteralPath (Join-Path $Directory 'resumen.json') | ConvertFrom-Json
    Assert ($summary.captures.Count -eq $Expected) 'Offline summary did not consume every capture'
    $modes = @($begins | ForEach-Object mode | Sort-Object -Unique)
    Assert (($modes -join ',') -eq (($ExpectedModes | Sort-Object) -join ',')) 'Mode coverage missing'
}
try {
    $env:ATLAS_FIXTURE_ERROR_STREAM = $null
    $env:ATLAS_FIXTURE_ERROR_MARKER = $null
    # Default three modes: ETW preflight, capture, post-exit logs, cleanup and Python summary.
    $allModes = Invoke-Benchmark @('-Repeats', '1') $true
    Assert-Captures $allModes 12 @('baseline', 'minimal', 'detailed')
    # Single-element Modes plus alternating repeat/scenario order in PS 5.1.
    $baseline = Invoke-Benchmark @('-Repeats', '2', '-Modes', 'baseline') $true
    Assert-Captures $baseline 8 @('baseline')
    $begins = @(Read-Rows (Join-Path $baseline 'suite.jsonl') | Where-Object kind -eq 'case_begin')
    Assert ($begins[0].name -eq '1920x1080-zoom24-activeFalse-baseline-r1') 'Original failing first case changed'
    Assert ($begins[4].name -eq '1280x720-zoom24-activeTrue-baseline-r2') 'Alternate repetition order failed'
    foreach ($stream in @('stdout', 'stderr')) {
        foreach ($marker in @('SCRIPT ERROR', 'SHADER ERROR', 'Parse Error')) {
            $env:ATLAS_FIXTURE_ERROR_STREAM = $stream
            $env:ATLAS_FIXTURE_ERROR_MARKER = $marker
            $failed = Invoke-Benchmark @('-Repeats', '1', '-Modes', 'baseline') $false
            $ends = @(Read-Rows (Join-Path $failed 'suite.jsonl') | Where-Object kind -eq 'case_end')
            Assert ($ends.Count -eq 1 -and $ends[0].status -eq 'failed') 'Runtime log error did not stop the suite'
            Assert ($ends[0].reason.Contains('Error de ejecuci') -and $ends[0].reason.EndsWith(".$stream.log")) "Did not inspect independent $stream log"
            Assert (!(Test-Path -LiteralPath (Join-Path $failed 'resumen.json'))) 'Failed capture received a summary'
        }
    }
    $env:ATLAS_FIXTURE_ERROR_STREAM = $null
    $env:ATLAS_FIXTURE_ERROR_MARKER = $null
    # Prove this end-to-end regression reaches the original bug after a successful capture.
    $fixedScript = [IO.File]::ReadAllText($benchmark)
    $brokenScript = $fixedScript.Replace('$runtimeLogs = @($stdoutLog, $stderrLog)', '$runtimeLogs = @($prefix+''.stdout.log'',$prefix+''.stderr.log'')')
    Assert ($brokenScript -ne $fixedScript) 'Could not restore original regression expression'
    try {
        [IO.File]::WriteAllText($benchmark, $brokenScript, [Text.UTF8Encoding]::new($true))
        $manifest.files.'benchmark.ps1' = (Get-FileHash -LiteralPath $benchmark -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        $broken = Invoke-Benchmark @('-Repeats', '1', '-Modes', 'baseline') $false
        $ends = @(Read-Rows (Join-Path $broken 'suite.jsonl') | Where-Object kind -eq 'case_end')
        Assert ($ends.Count -eq 1 -and $ends[0].status -eq 'failed') 'Original expression did not fail on the first scenario'
        Assert ($ends[0].reason.Contains('.stdout.log') -and $ends[0].reason.Contains('.stderr.log')) 'Original failure did not concatenate both log paths'
    } finally {
        [IO.File]::WriteAllText($benchmark, $fixedScript, [Text.UTF8Encoding]::new($true))
    }
    Write-Host 'ATLAS BENCHMARK FLOW TESTS: 0 failures (20 captures; 6 log-error rejections; original bug reproduced)'
} finally {
    $env:ATLAS_FIXTURE_ERROR_STREAM = $null
    $env:ATLAS_FIXTURE_ERROR_MARKER = $null
    # Leave compact capture/log evidence, rather than duplicate the release binaries.
    Get-ChildItem -LiteralPath $testPackage | Where-Object { $_.Name -notlike 'mediciones-*' } | Remove-Item -Recurse -Force
}
