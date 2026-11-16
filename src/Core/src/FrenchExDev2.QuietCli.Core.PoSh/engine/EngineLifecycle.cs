using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>Starts and stops the module's private engine; hosting policy is supplied by the caller.</summary>
public static class EngineLifecycle
{
    /// <summary>Deadline for a clean shutdown before the child is killed.</summary>
    private static readonly TimeSpan ShutdownTimeout = TimeSpan.FromSeconds(5);

    /// <summary>True while a started engine can still serve requests.</summary>
    /// <param name="engine">Current engine or null.</param>
    public static bool IsRunning(EngineConnection? engine) => engine is not null && (engine.Mode == "InProcess" || engine.Process is { HasExited: false });

    /// <summary>Resolves the configured hosting mode into a concrete one.</summary>
    /// <param name="configured">Auto, Process or InProcess.</param>
    public static string ResolveMode(string configured)
    {
        if (configured is not ("Auto" or "Process" or "InProcess")) throw new InvalidOperationException("InvalidEngineMode");
        return configured != "Auto" ? configured : Environment.Version.Major >= 10 ? "InProcess" : "Process";
    }

    /// <summary>Starts the configured engine and records it as the session engine; business objects never cross.</summary>
    /// <param name="configuredMode">Value of engine.hosting.</param>
    /// <param name="database">Value of telemetry.database.</param>
    /// <param name="timeoutSeconds">Value of engine.ipcTimeoutSeconds for the hello exchange.</param>
    public static EngineConnection Start(string configuredMode, string database, double timeoutSeconds)
    {
        ResourceVerifier.Verify(QuietSession.Root, null);
        string mode = ResolveMode(configuredMode);
        EngineConnection engine = mode == "InProcess" ? StartInProcess(database) : StartProcess(database);
        QuietSession.Engine = engine;
        engine.Info = PropertyReader.Get(EngineClient.Send(engine, new System.Collections.Hashtable { ["Action"] = "hello" }, [], timeoutSeconds).Header, "Data");
        return engine;
    }

    /// <summary>Creates the direct host without a child process.</summary>
    private static EngineConnection StartInProcess(string database)
    {
        InProcessEngine host = InProcessEngine.CreateAsync(Path.GetFullPath(database), QuietSession.Root).GetAwaiter().GetResult();
        return new EngineConnection { Mode = "InProcess", Host = host, Database = database };
    }

    /// <summary>Launches the verified isolated engine for the current runtime identifier.</summary>
    private static EngineConnection StartProcess(string database)
    {
        string root = QuietSession.Root;
        string rid = RuntimeInformation.RuntimeIdentifier;
        using (JsonDocument targets = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "runtime-targets.json"))))
        {
            bool known = false;
            foreach (JsonElement target in targets.RootElement.GetProperty("Targets").EnumerateArray())
                if (string.Equals(target.GetProperty("Rid").GetString(), rid, StringComparison.Ordinal)) known = true;
            if (!known) throw new InvalidOperationException("RuntimeNotDistributed: " + rid);
        }
        string directory = Path.Combine(root, "lib", "engine", rid);
        string assembly = Path.Combine(directory, "QuietCli.Engine.dll");
        if (!File.Exists(assembly)) throw new InvalidOperationException("EngineNotBuilt: run scripts/Build-Workspace.ps1.");
        string buildPath = Path.Combine(directory, "build-manifest.json");
        if (!File.Exists(buildPath)) throw new InvalidOperationException("EngineBuildIdentityMissing");
        VerifyBuild(directory, buildPath, rid);
        string? dotnet = FindOnPath("dotnet");
        string executable = OperatingSystem.IsWindows() ? Path.Combine(directory, "QuietCli.Engine.exe") : dotnet ?? throw new InvalidOperationException("dotnet was not found on PATH.");
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
        if (OperatingSystem.IsWindows())
        {
            string dotnetDirectory = Path.GetDirectoryName(dotnet ?? throw new InvalidOperationException("dotnet was not found on PATH."))!;
            start.Environment["DOTNET_ROOT_" + RuntimeInformation.ProcessArchitecture.ToString().ToUpperInvariant()] = dotnetDirectory;
        }
        else start.ArgumentList.Add(assembly);
        foreach (string argument in new[] { "--database", Path.GetFullPath(database), "--module-root", root }) start.ArgumentList.Add(argument);
        var process = new Process { StartInfo = start };
        if (!process.Start()) throw new InvalidOperationException("EngineStartFailed");
        // Diagnostics are discarded through a bounded copy, keeping this pipe separate from native output.
        return new EngineConnection { Mode = "Process", Process = process, Input = process.StandardInput.BaseStream, Output = process.StandardOutput.BaseStream, Database = database, DiagnosticDrain = process.StandardError.BaseStream.CopyToAsync(Stream.Null) };
    }

    /// <summary>Checks the manifest identity and every binary hash of the isolated build.</summary>
    private static void VerifyBuild(string directory, string buildPath, string rid)
    {
        using JsonDocument build = JsonDocument.Parse(File.ReadAllText(buildPath));
        JsonElement manifest = build.RootElement;
        if (!string.Equals(manifest.GetProperty("RuntimeIdentifier").GetString(), rid, StringComparison.Ordinal)) throw new InvalidOperationException("EngineBuildRuntimeMismatch");
        int dll = 0, exe = 0;
        foreach (JsonElement file in manifest.GetProperty("Binaries").EnumerateArray())
        {
            string name = file.GetProperty("Path").GetString()!;
            if (name == "QuietCli.Engine.dll") dll++;
            if (name == "QuietCli.Engine.exe") exe++;
        }
        if (dll != 1) throw new InvalidOperationException("EngineBuildIdentityInvalid");
        if (OperatingSystem.IsWindows() && exe != 1) throw new InvalidOperationException("EngineApphostIdentityInvalid");
        foreach (JsonElement file in manifest.GetProperty("Binaries").EnumerateArray())
        {
            string name = file.GetProperty("Path").GetString()!;
            if (!string.Equals(Path.GetFileName(name), name, StringComparison.Ordinal)) throw new InvalidOperationException("EngineBuildIdentityUnsafePath");
            string binary = Path.Combine(directory, name);
            if (!File.Exists(binary)) throw new InvalidOperationException("EngineBinaryIntegrityFailed");
            using FileStream stream = File.OpenRead(binary);
            string actual = Convert.ToHexString(SHA256.HashDataAsync(stream).GetAwaiter().GetResult());
            if (!string.Equals(actual, file.GetProperty("SHA256").GetString(), StringComparison.Ordinal)) throw new InvalidOperationException("EngineBinaryIntegrityFailed");
        }
    }

    /// <summary>Finds an executable on PATH the way command resolution does for applications.</summary>
    /// <param name="name">Command name without extension.</param>
    public static string? FindOnPath(string name)
    {
        string[] extensions = OperatingSystem.IsWindows() ? (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.CMD;.BAT").Split(';', StringSplitOptions.RemoveEmptyEntries) : [""];
        foreach (string directory in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            foreach (string extension in extensions)
            {
                string candidate = Path.Combine(directory.Trim('"'), name + extension);
                if (File.Exists(candidate)) return candidate;
            }
        return null;
    }

    /// <summary>Closes the owned engine normally and flushes accepted measurement writes.</summary>
    /// <param name="timeoutSeconds">Value of engine.ipcTimeoutSeconds for the shutdown exchange.</param>
    public static void Stop(double timeoutSeconds)
    {
        EngineConnection? engine = QuietSession.Engine;
        if (engine is null) return;
        if (engine.Mode == "InProcess")
        {
            try { engine.Host!.DisposeAsync().AsTask().WaitAsync(ShutdownTimeout).GetAwaiter().GetResult(); }
            finally { QuietSession.Engine = null; }
            return;
        }
        try
        {
            if (engine.Process is { HasExited: false } && !engine.Broken)
            {
                _ = EngineClient.Send(engine, new System.Collections.Hashtable { ["Action"] = "shutdown" }, [], timeoutSeconds);
                engine.Input!.Close();
                engine.Process.WaitForExitAsync().WaitAsync(ShutdownTimeout).GetAwaiter().GetResult();
            }
        }
        finally
        {
            try { if (engine.Process is { HasExited: false }) engine.Process.Kill(true); } catch (Exception) { /* already gone */ }
            engine.Process?.Dispose();
            QuietSession.Engine = null;
        }
    }

    /// <summary>Parses a configured seconds value that may be a number or its text form.</summary>
    /// <param name="value">Configuration value.</param>
    public static double Seconds(object? value) => Convert.ToDouble(value is System.Management.Automation.PSObject wrapped ? wrapped.BaseObject : value, CultureInfo.InvariantCulture);
}
