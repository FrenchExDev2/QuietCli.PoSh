using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FrenchExDev2.QuietCli.Storage;

namespace FrenchExDev2.QuietCli;

/// <summary>Shared engine dispatcher for the isolated server and the compatible in-process host.</summary>
internal sealed class EngineSession : IAsyncDisposable
{
    /// <summary>Serialized metadata store, independent of caller business values.</summary>
    private readonly MeasurementStore store;
    /// <summary>Session-owned terminal bridge.</summary>
    private readonly TerminalBridge terminalBridge = new();
    /// <summary>Owned native invocations, never raw captures.</summary>
    private readonly Dictionary<string, Invocation> invocations = new();
    /// <summary>Bounded number of unfinished aggregate group deliveries; no original events.</summary>
    private readonly Dictionary<string, GainJob> gainReports = new();
    /// <summary>Verified module resource directory.</summary>
    private readonly string moduleRoot;
    /// <summary>Actual assembly digest.</summary>
    private readonly string assemblyHash;
    /// <summary>Source digest bound to this build.</summary>
    private readonly string sourceHash;
    /// <summary>Actual publication target.</summary>
    private readonly string buildRuntime;

    /// <summary>Initializes resources without starting a native command or creating a database.</summary>
    /// <param name="database">Explicit telemetry path.</param>
    /// <param name="moduleRoot">Verified module root.</param>
    /// <param name="assemblyHash">Digest of the loaded assembly.</param>
    /// <param name="sourceHash">Digest of its source inputs.</param>
    /// <param name="buildRuntime">Actual build target.</param>
    private EngineSession(string database, string moduleRoot, string assemblyHash, string sourceHash, string buildRuntime)
    {
        this.moduleRoot = moduleRoot; this.assemblyHash = assemblyHash; this.sourceHash = sourceHash; this.buildRuntime = buildRuntime;
        Database.NativeDirectory = Path.Combine(moduleRoot, "resources", "runtime", "runtimes", System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier, "native");
        store = new MeasurementStore(database);
    }

    /// <summary>Reads the identity beside the loaded assembly rather than the PowerShell executable.</summary>
    /// <param name="database">Explicit telemetry path.</param>
    /// <param name="moduleRoot">Verified module root.</param>
    internal static async Task<EngineSession> CreateAsync(string database, string moduleRoot)
    {
        string assembly = typeof(EngineSession).Assembly.Location;
        await using var input = File.OpenRead(assembly);
        string hash = Convert.ToHexString(await SHA256.HashDataAsync(input));
        using var build = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(Path.GetDirectoryName(assembly)!, "build-manifest.json"), Encoding.UTF8));
        var root = build.RootElement;
        return new EngineSession(database, moduleRoot, hash, root.GetProperty("SourceSHA256").GetString()!, root.TryGetProperty("RuntimeIdentifier", out var rid) ? rid.GetString()! : "portable");
    }

    /// <summary>Dispatches metadata and transient bytes; business objects never cross this boundary.</summary>
    /// <param name="request">Control metadata.</param>
    /// <param name="input">Transient native input.</param>
    internal async Task<(object? Data, byte[]? Payload)> ExecuteAsync(JsonElement request, byte[] input)
    {
        object? data = null; byte[]? payload = null;
        string action = request.GetProperty("Action").GetString()!;
        string invocationId = request.TryGetProperty("InvocationId", out var identifier) ? identifier.GetString()! : "";
        switch (action)
        {
            case "hello": data = Information(); break;
            case "allocations": data = ProcessAllocationSnapshot.Capture(request.GetProperty("Precise").GetBoolean()); break;
            case "start": data = await StartAsync(InvocationRequest.Parse(request)); break;
            case "next":
                (data, payload) = await ReadAsync(invocationId); break;
            case "input": data = await ControlAsync(LocalControl.Input, invocationId, input); break;
            case "eof": data = await ControlAsync(LocalControl.Eof, invocationId, input); break;
            case "cancel": data = await ControlAsync(LocalControl.Cancel, invocationId, input); break;
            case "resize": data = await ControlAsync(LocalControl.Resize, invocationId, input, request.GetProperty("Columns").GetInt32(), request.GetProperty("Rows").GetInt32()); break;
            case "release": data = await ControlAsync(LocalControl.Release, invocationId, input); break;
            case "save": await store.SaveAsync(request.GetProperty("Metadata"), request.GetProperty("Kind").GetString()!); break;
            case "query": data = await store.QueryAsync(request); break;
            case "gain": data = await StartGainAsync(GainSelection.Parse(request)); break;
            case "gain-poll": data = await ReadGainAsync(request.GetProperty("ReportId").GetString()!, 0); break;
            case "gain-next": data = await ReadGainAsync(request.GetProperty("ReportId").GetString()!, request.GetProperty("After").GetInt32()); break;
            case "gain-release": ReleaseGain(request.GetProperty("ReportId").GetString()!); break;
            case "scrub": data = new { ChangedEvents = await store.ScrubAsync(request.TryGetProperty("Confirmed", out var confirmation) && confirmation.GetBoolean()) }; break;
            case "shutdown": break;
            default: throw new InvalidDataException("UnknownAction");
        }

        return (data, payload);
    }

    /// <summary>Returns fixed engine identity without transport serialization.</summary>
    private object Information() => new { ProtocolVersion = ProtocolSpecification.Version, Runtime = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription, TargetFramework = typeof(EngineSession).Assembly.GetCustomAttributes(typeof(System.Runtime.Versioning.TargetFrameworkAttribute), false).Cast<System.Runtime.Versioning.TargetFrameworkAttribute>().Single().FrameworkName, ProcessId = Environment.ProcessId, RuntimeIdentifier = System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier, BuildRuntimeIdentifier = buildRuntime, BlockSize = Protocol.BlockSize, QueueBlocks = ProtocolSpecification.QueueBlocks, AssemblySHA256 = assemblyHash, SourceSHA256 = sourceHash, Capture = false };

    /// <summary>Validates and starts exactly one owned native operation in either host.</summary>
    /// <param name="request">Detached start options.</param>
    private async Task<object> StartAsync(InvocationRequest request)
    {
        request.Validated();
        if (invocations.ContainsKey(request.Id)) throw new InvalidOperationException("DuplicateInvocation");
        string bridge = request.Transport == "Pty" && !OperatingSystem.IsWindows() ? await terminalBridge.GetAsync(moduleRoot) : "";
        var invocation = await Invocation.StartAsync(request, new ProcessChannelFactory(bridge));
        invocations.Add(request.Id, invocation);
        return new { invocation.ProcessId };
    }

    /// <summary>Starts a bounded aggregate job using detached typed filters.</summary>
    /// <param name="selection">Closed report selection.</param>
    private async Task<object> StartGainAsync(GainSelection selection)
    {
        if (gainReports.Count >= 8) throw new InvalidOperationException("GainReportCapacityExceeded");
        string id = Guid.NewGuid().ToString("N");
        gainReports.Add(id, new GainJob(store, selection));
        return await ReadGainAsync(id, 0);
    }

    /// <summary>Dispatches closed integrated metadata using the same operations as the wire server.</summary>
    /// <param name="request">Detached metadata, never caller business values.</param>
    internal async Task<object?> MetadataAsync(LocalMetadataRequest request)
    {
        switch (request.Action)
        {
            case "hello": return Information();
            case "allocations": return ProcessAllocationSnapshot.Capture(request.Precise);
            case "start": return await StartAsync(request.Start!);
            case "save": await store.SaveAsync(request.Measurement!, request.Kind!); return null;
            case "gain": return await StartGainAsync(request.Selection!);
            case "gain-poll": return await ReadGainAsync(request.ReportId!, 0);
            case "gain-next": return await ReadGainAsync(request.ReportId!, request.After);
            case "gain-release": ReleaseGain(request.ReportId!); return null;
            case "scrub": return new { ChangedEvents = await store.ScrubAsync(request.Confirmed) };
            case "shutdown": return null;
            default: throw new InvalidDataException("UnknownMetadataAction");
        }
    }

    /// <summary>Applies the same bounded input and lifecycle transition in either host.</summary>
    /// <param name="control">Closed lifecycle operation, excluding startup and telemetry.</param>
    /// <param name="invocationId">Owned invocation identity.</param>
    /// <param name="input">One transient input block; accepted blocks remain owned by the writer.</param>
    /// <param name="columns">Terminal width for Resize.</param>
    /// <param name="rows">Terminal height for Resize.</param>
    internal async Task<object?> ControlAsync(LocalControl control, string invocationId, byte[] input, int columns = 0, int rows = 0)
    {
        var native = invocations[invocationId];
        switch (control)
        {
            case LocalControl.Input: return new { Accepted = native.TryWrite(input) };
            case LocalControl.Eof: native.CompleteInput(); break;
            case LocalControl.Cancel: native.Cancel(); break;
            case LocalControl.Resize: native.Resize(columns, rows); break;
            case LocalControl.Release: await native.DisposeAsync(); invocations.Remove(invocationId); break;
            default: throw new ArgumentOutOfRangeException(nameof(control));
        }
        return null;
    }

    /// <summary>Reads one native block using the same state transition for both hosts.</summary>
    /// <param name="invocationId">Owned invocation identity.</param>
    internal async Task<(object Data, byte[]? Payload)> ReadAsync(string invocationId)
    {
        var native = invocations[invocationId];
        var block = await native.NextAsync();
        return (new { Stream = block?.Stream, Completed = native.IsCompleted && block == null, Execution = native.Snapshot() }, block?.Bytes);
    }

    /// <summary>Returns a progress heartbeat or a bounded aggregate page within one short exchange.</summary>
    /// <param name="id">Owned aggregate job identity.</param>
    /// <param name="offset">Next group offset after aggregation completes.</param>
    private async Task<object> ReadGainAsync(string id, int offset)
    {
        var job = gainReports[id];
        try
        {
            if (!job.Task.IsCompleted && await Task.WhenAny(job.Task, Task.Delay(20)) != job.Task)
                return new { Pending = true, ReportId = id };
            var report = await job.Task;
            object page = GainPage(report, id, offset, out bool complete);
            if (complete) ReleaseGain(id);
            return page;
        }
        catch { ReleaseGain(id); throw; }
    }

    /// <summary>Releases completed reports and cooperatively cancels abandoned database scans.</summary>
    /// <param name="id">Session-local report identity.</param>
    private void ReleaseGain(string id) { if (gainReports.Remove(id, out var job)) job.Dispose(); }

    /// <summary>Owns one background metadata scan without retaining event payloads.</summary>
    private sealed class GainJob : IDisposable
    {
        /// <summary>Cancellation for an abandoned scan.</summary>
        private readonly CancellationTokenSource cancellation = new();
        /// <summary>Final aggregate, with no original telemetry rows.</summary>
        internal Task<GainReport> Task { get; }
        /// <summary>Starts a scan on the existing SQLite worker.</summary>
        /// <param name="store">Session measurement store.</param>
        /// <param name="request">Detached filters whose lifetime is independent of any transport packet.</param>
        internal GainJob(MeasurementStore store, GainSelection request) => Task = store.GainAsync(request, cancellation.Token);
        /// <summary>Cancels the scan and observes faults even when the caller has disconnected.</summary>
        public void Dispose()
        {
            cancellation.Cancel(); cancellation.Dispose();
            _ = Task.ContinueWith(static task => { _ = task.Exception; }, TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously);
        }
    }
    /// <summary>Bounds aggregate groups by row count and encoded bytes, without truncating the report.</summary>
    /// <param name="report">Completed safe counters and groups.</param>
    /// <param name="id">Session-local report identity.</param>
    /// <param name="offset">Next group offset, not a database event cursor.</param>
    /// <param name="complete">Whether no additional group page remains.</param>
    private static object GainPage(GainReport report, string id, int offset, out bool complete)
    {
        if (offset < 0 || offset > report.Groups.Length) throw new InvalidDataException("InvalidGainGroupCursor");
        var groups = new List<GainGroup>(); int bytes = 4096;
        for (int i = offset; i < report.Groups.Length && groups.Count < 128; i++)
        {
            int size = JsonSerializer.SerializeToUtf8Bytes(report.Groups[i]).Length + 1;
            if (size > Protocol.HeaderLimit / 2 - 4096) throw new InvalidDataException("GainGroupTooLarge");
            if (bytes + size > Protocol.HeaderLimit / 2) break;
            groups.Add(report.Groups[i]); bytes += size;
        }
        int after = offset + groups.Count; complete = after == report.Groups.Length;
        return new { Report = report.Summary, Groups = groups.ToArray(), GroupsComplete = complete, ReportId = complete ? null : id, After = complete ? (int?)null : after };
    }
    /// <summary>Cancels owned children and flushes all accepted telemetry writes.</summary>
    public async ValueTask DisposeAsync()
    {
        try { foreach (var invocation in invocations.Values) await invocation.DisposeAsync(); }
        finally { invocations.Clear(); foreach (var job in gainReports.Values) job.Dispose(); gainReports.Clear(); await terminalBridge.DisposeAsync(); await store.DisposeAsync(); }
    }
}
