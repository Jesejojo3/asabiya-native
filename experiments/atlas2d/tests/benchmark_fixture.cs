// Native stand-ins for Godot and its Go child. Only the harness is under test.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

public static class BenchmarkFixture {
    static JavaScriptSerializer json = new JavaScriptSerializer();
    static void Row(StreamWriter writer, string kind, object fields) {
        var row = json.Deserialize<Dictionary<string, object>>(json.Serialize(fields));
        row["kind"] = kind;
        row["ticks_us"] = Stopwatch.GetTimestamp() * (1000000.0 / Stopwatch.Frequency);
        row["utc_unix_ms"] = (DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalMilliseconds;
        writer.WriteLine(json.Serialize(row));
        writer.Flush();
    }
    public static int Main(string[] args) {
        if (args.Length > 0 && args[0] == "--parent-pid") {
            Process.GetProcessById(int.Parse(args[1])).WaitForExit();
            return 0;
        }
        var options = new Dictionary<string, string>();
        foreach (string arg in args) {
            int separator = arg.IndexOf('=');
            if (separator > 0) options[arg.Substring(0, separator)] = arg.Substring(separator + 1);
        }
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        string endpoint = Path.Combine(directory, "endpoint.json");
        int pid = Process.GetCurrentProcess().Id;
        var child = Process.Start(new ProcessStartInfo(Path.Combine(directory, "asabiya-server.exe"),
            "--parent-pid " + pid + " --endpoint-file \"" + endpoint + "\"") { UseShellExecute = false, CreateNoWindow = true });
        try {
            using (var writer = new StreamWriter(options["--bench-out"], false, new UTF8Encoding(false))) {
                Row(writer, "environment", new { schema = "asabiya/atlas2d-measure-v2", pid = pid,
                    gpu = "Harness fixture", cpu = "Harness fixture", headless = true,
                    instrumentation = options["--instrumentation"], active = Array.IndexOf(args, "--active") >= 0 });
                Row(writer, "processes", new { godot_pid = pid, go_pid = child.Id, endpoint_file = endpoint });
                int[] size = { int.Parse(options["--width"]), int.Parse(options["--height"]) };
                Row(writer, "ready", new { framebuffer_size = size, window_size = size, state_sha256 = "fixture" });
                Row(writer, "sample_begin", new { year = 0 });
                // Allow native identity discovery, multiple polls and real PresentMon startup.
                Thread.Sleep(3000);
                Row(writer, "end", new { year = 0, post_draw_callbacks = 1, post_draw_interval_max_ms = 3000 });
                Row(writer, "verified_pause", new { exact = true, state_sha256 = "fixture" });
                string stream = Environment.GetEnvironmentVariable("ATLAS_FIXTURE_ERROR_STREAM");
                string marker = Environment.GetEnvironmentVariable("ATLAS_FIXTURE_ERROR_MARKER");
                if (stream == "stdout") Console.Out.WriteLine(marker);
                if (stream == "stderr") Console.Error.WriteLine(marker);
                Console.Out.Flush(); Console.Error.Flush();
                // Keep final rows visible for a poll before the process exits.
                Thread.Sleep(300);
            }
        } finally {
            if (!child.HasExited) child.Kill();
            child.WaitForExit(); child.Dispose();
        }
        return 0;
    }
}
