param(
    [Parameter(Mandatory=$true)][string]$Benchmark,
    [string]$Directory,
    [int]$Repeats,
    [string[]]$Modes,
    [switch]$Small,
    [int]$PreparationYears,
    [int]$Seconds,
    [int]$PollMilliseconds
)
$ErrorActionPreference = 'Stop'
$benchmarkParameters = @{} + $PSBoundParameters
$benchmarkParameters.Remove('Benchmark')
function Start-Process {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [switch]$PassThru,
        [string]$WorkingDirectory,
        [string]$RedirectStandardOutput,
        [string]$RedirectStandardError,
        [Diagnostics.ProcessWindowStyle]$WindowStyle
    )
    # A console fixture has no swap chain for PresentMon to track for process-exit
    # termination. Bound only that profiler capture, after the fixture's 3.3 s life.
    # Keep real ETW, the pinned binary, preflight, identities and log checks intact.
    if ((Split-Path $FilePath -Leaf) -eq 'PresentMon.exe' -and $ArgumentList -contains '--terminate_on_proc_exit') {
        $PSBoundParameters['ArgumentList'] = $ArgumentList + @('--timed', '4', '--terminate_after_timed')
    }
    Microsoft.PowerShell.Management\Start-Process @PSBoundParameters
}
& $Benchmark @benchmarkParameters
