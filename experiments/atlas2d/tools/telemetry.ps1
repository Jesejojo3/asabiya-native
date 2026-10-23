# Shared by Windows PowerShell 5.1 and pwsh. No process-name discovery.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class AtlasNative {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public class MemoryStatus {
        public uint length=(uint)Marshal.SizeOf(typeof(MemoryStatus)); public uint load;
        public ulong totalPhysical, availablePhysical, totalPage, availablePage, totalVirtual, availableVirtual, extended;
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx([In,Out] MemoryStatus status);
    public static object AvailableMemory() { var m=new MemoryStatus(); return GlobalMemoryStatusEx(m) ? (object)m.availablePhysical : null; }
}
public sealed class AtlasTail : IDisposable {
    FileStream stream; byte[] bytes = new byte[65536]; StringBuilder pending = new StringBuilder();
    public long BytesRead;
    public AtlasTail(string path) { stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite); }
    public string[] ReadLines() {
        var lines = new System.Collections.Generic.List<string>(); int n;
        // Read only bytes appended since last poll; preserve incomplete UTF-8 JSON lines as bytes.
        while ((n = stream.Read(bytes, 0, bytes.Length)) > 0) {
            BytesRead += n;
            for (int i=0; i<n; i++) {
                if (bytes[i] == 10) {
                    byte[] raw = new byte[pending.Length];
                    for (int j=0; j<raw.Length; j++) raw[j]=(byte)pending[j];
                    lines.Add(Encoding.UTF8.GetString(raw).TrimEnd('\r')); pending.Clear();
                } else pending.Append((char)bytes[i]);
            }
            if (pending.Length > 1048576) throw new IOException("Unterminated JSONL line exceeds 1 MiB");
        }
        return lines.ToArray();
    }
    public void Dispose() { stream.Dispose(); }
}
'@
function Write-AtlasJson($Writer, $Value) {
    $Writer.WriteLine(($Value | ConvertTo-Json -Depth 12 -Compress))
}
function Get-AtlasIdentity([int]$ProcessId, [string]$ExpectedPath, [int]$ParentId = 0) {
    $p = Get-Process -Id $ProcessId -ErrorAction Stop
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
    if ([IO.Path]::GetFullPath($p.Path) -ine [IO.Path]::GetFullPath($ExpectedPath)) { throw "Executable mismatch for PID $ProcessId" }
    if ($ParentId -gt 0 -and $cim.ParentProcessId -ne $ParentId) { throw "Parent mismatch for PID $ProcessId" }
    [pscustomobject]@{ process=$p; id=$ProcessId; start=$p.StartTime.ToUniversalTime().Ticks; path=$p.Path; parent=$cim.ParentProcessId; command=$cim.CommandLine; lastCpu=$null; lastTime=$null }
}
function Get-AtlasSample($Identity, [double]$Now, [int]$LogicalCpus) {
    if ($null -eq $Identity) { return @{status='undiscovered';working_set_bytes=$null;private_bytes=$null;cpu_seconds=$null;cpu_one_core_percent=$null;cpu_machine_percent=$null} }
    try {
        $p=$Identity.process; $p.Refresh()
        if ($p.HasExited) { throw 'exited' }
        if ($p.StartTime.ToUniversalTime().Ticks -ne $Identity.start) { throw 'PID reused' }
        $cpu=$p.TotalProcessorTime.TotalSeconds; $percent=$null
        if ($null -ne $Identity.lastCpu -and $Now -gt $Identity.lastTime) { $percent=100*($cpu-$Identity.lastCpu)/($Now-$Identity.lastTime) }
        $Identity.lastCpu=$cpu; $Identity.lastTime=$Now
        return @{status='ok';pid=$Identity.id;start_utc_ticks=$Identity.start;working_set_bytes=[long]$p.WorkingSet64;private_bytes=[long]$p.PrivateMemorySize64;cpu_seconds=$cpu;cpu_one_core_percent=$percent;cpu_machine_percent=$(if ($null -ne $percent) {$percent/$LogicalCpus} else {$null})}
    } catch { return @{status='unavailable';pid=$Identity.id;reason=$_.Exception.Message;working_set_bytes=$null;private_bytes=$null;cpu_seconds=$null;cpu_one_core_percent=$null;cpu_machine_percent=$null} }
}
function Stop-AtlasOwned($Identity) {
    if ($null -eq $Identity) { return }
    $sample=Get-AtlasSample $Identity 0 1
    if ($sample.status -eq 'ok') { Stop-Process -Id $Identity.id -ErrorAction SilentlyContinue }
}

function Get-AtlasWindow([int]$ProcessId) {
    $foreground=[AtlasNative]::GetForegroundWindow();$owner=[uint32]0
    $null=[AtlasNative]::GetWindowThreadProcessId($foreground,[ref]$owner)
    $p=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) {return @{status='unavailable'}}
    @{status='ok';foreground_pid=$owner;focused=($owner -eq $ProcessId);minimized=[AtlasNative]::IsIconic($p.MainWindowHandle)}
}
