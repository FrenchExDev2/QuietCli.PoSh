using System.Security.Cryptography;
using System.Text.Json;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Storage;

/// <summary>Private protocol server. It never imports a handler or receives a business object.</summary>
internal static class Program
{
    /// <summary>Runs the session until EOF, then cancels owned processes and flushes measurements.</summary>
    /// <param name="arguments">Exact invocation arguments without shell expansion.</param>
    private static async Task<int> Main(string[] arguments)
    {
        if (arguments.Length != 4 || arguments[0] != "--database" || arguments[2] != "--module-root" || !Path.IsPathFullyQualified(arguments[3])) return 2;
        string moduleRoot = Path.GetFullPath(arguments[3]);
        Database.NativeDirectory = Path.Combine(moduleRoot, "resources", "runtime", "runtimes", System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier, "native");
        await using var store = new MeasurementStore(arguments[1]);
        await using var terminalBridge = new TerminalBridge();
        var protocol = new Protocol(Console.OpenStandardInput(), Console.OpenStandardOutput());
        var invocations = new Dictionary<string, Invocation>();
        string assemblyHash;
        await using (var engineFile = File.OpenRead(typeof(Program).Assembly.Location)) assemblyHash = Convert.ToHexString(await SHA256.HashDataAsync(engineFile));
        using var build = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "build-manifest.json"), System.Text.Encoding.UTF8));
        string sourceHash = build.RootElement.GetProperty("SourceSHA256").GetString()!;
        string buildRuntime = build.RootElement.TryGetProperty("RuntimeIdentifier", out var targetRuntime) ? targetRuntime.GetString()! : "portable";
        try
        {
            Packet? packet;
            while ((packet = await protocol.ReadAsync(CancellationToken.None)) != null)
            {
                var request = packet.Header;
                string id = request.GetProperty("RequestId").GetString()!;
                try
                {
                    object? data = null; byte[]? payload = null;
                    string action = request.GetProperty("Action").GetString()!;
                    string invocationId = request.TryGetProperty("InvocationId", out var identifier) ? identifier.GetString()! : "";
                    switch (action)
                    {
                        case "hello": data = new { ProtocolVersion = ProtocolSpecification.Version, Runtime = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription, ProcessId = Environment.ProcessId, RuntimeIdentifier = System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier, BuildRuntimeIdentifier = buildRuntime, BlockSize = Protocol.BlockSize, QueueBlocks = ProtocolSpecification.QueueBlocks, AssemblySHA256 = assemblyHash, SourceSHA256 = sourceHash, Capture = false }; break;
                        case "start":
                            if (invocations.ContainsKey(invocationId)) throw new InvalidOperationException("DuplicateInvocation");
                            var nativeRequest = InvocationRequest.Parse(request);
                            string bridge = nativeRequest.Transport == "Pty" && !OperatingSystem.IsWindows() ? await terminalBridge.GetAsync(moduleRoot) : "";
                            var invocation = await Invocation.StartAsync(nativeRequest, new ProcessChannelFactory(bridge)); invocations.Add(invocationId, invocation);
                            data = new { invocation.ProcessId }; break;
                        case "next":
                            var native = invocations[invocationId];
                            var block = await native.NextAsync(); payload = block?.Bytes;
                            data = new { Stream = block?.Stream, Completed = native.IsCompleted && block == null, Execution = native.Snapshot() }; break;
                        case "input": data = new { Accepted = invocations[invocationId].TryWrite(packet.Payload) }; break;
                        case "eof": invocations[invocationId].CompleteInput(); break;
                        case "cancel": invocations[invocationId].Cancel(); break;
                        case "resize": invocations[invocationId].Resize(request.GetProperty("Columns").GetInt32(), request.GetProperty("Rows").GetInt32()); break;
                        case "release":
                            await invocations[invocationId].DisposeAsync(); invocations.Remove(invocationId); break;
                        case "save": await store.SaveAsync(request.GetProperty("Metadata"), request.GetProperty("Kind").GetString()!); break;
                        case "query": data = await store.QueryAsync(request); break;
                        case "scrub": data = new { ChangedEvents = await store.ScrubAsync(request.TryGetProperty("Confirmed", out var confirmation) && confirmation.GetBoolean()) }; break;
                        case "shutdown": await protocol.WriteAsync(new { Version = 1, RequestId = id, Ok = true }, null, CancellationToken.None); return 0;
                        default: throw new InvalidDataException("UnknownAction");
                    }
                    await protocol.WriteAsync(new { Version = 1, RequestId = id, Ok = true, Data = data }, payload, CancellationToken.None);
                }
                catch (Exception error)
                {
                    if (error is OperationCanceledException or TimeoutException) throw;
                    await protocol.WriteAsync(new { Version = 1, RequestId = id, Ok = false, Error = new { Code = error.GetType().Name, Message = error.Message } }, null, CancellationToken.None);
                }
            }
        }
        catch (Exception error) { await Console.Error.WriteLineAsync("QuietCli2 protocol stopped: " + error.GetType().Name); return 3; }
        finally { foreach (var invocation in invocations.Values) await invocation.DisposeAsync(); }
        return 0;
    }

}
