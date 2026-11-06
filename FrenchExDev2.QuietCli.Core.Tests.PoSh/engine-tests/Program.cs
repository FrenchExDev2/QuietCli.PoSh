using System.Buffers.Binary;
using System.Text.Json;
using FrenchExDev2.QuietCli;

/// <summary>Independent protocol and SQLite assertions, distributed with the companion only.</summary>
internal static class Program
{
    /// <summary>Verifies framing, error boundaries and concurrent metadata persistence.</summary>
    /// <param name="arguments">Exact invocation arguments without shell expansion.</param>
    private static async Task<int> Main(string[] arguments)
    {
        if (arguments.Length != 0) FrenchExDev2.QuietCli.Storage.Database.NativeDirectory = arguments[0];
        var results = new List<object>(); int passed = 0, failed = 0;
        // Each assertion is independent; a fixture failure remains a failing case.
        async Task Case(string name, Func<Task> assertion)
        {
            try { await assertion(); passed++; results.Add(new { Name = name, State = "Passed" }); }
            catch (Exception error) { failed++; results.Add(new { Name = name, State = "Failed", Error = error.Message }); }
        }
        if (arguments.Contains("--configuration-delivery-only"))
        {
            await ConfigurationDeliveryCases.RunAsync(Case, arguments[2]);
            Console.WriteLine(JsonSerializer.Serialize(new { Passed = passed, Failed = failed, Cases = results }));
            return failed == 0 ? 0 : 1;
        }
        if (arguments.Contains("--recall-only"))
        {
            await RecallCases.RunAsync(Case);
            Console.WriteLine(JsonSerializer.Serialize(new { Passed = passed, Failed = failed, Cases = results }));
            return failed == 0 ? 0 : 1;
        }
        await Case("compiled records preserve every byte at every fragment boundary", () =>
        {
            byte[] bytes = [0, 195, 169, 255, 0, 0, 120];
            for (int split = 0; split <= bytes.Length; split++)
            {
                using var framer = new ByteRecordFramer(0, 3);
                var records = framer.Push(bytes[..split]).Concat(framer.Push(bytes[split..])).ToArray();
                Require(records.Length == 3 && records[0].Length == 0 && records[1].SequenceEqual(new byte[] { 195, 169, 255 }) && records[2].Length == 0, "Empty or fragmented binary record changed");
                Require(framer.Finish()!.SequenceEqual(new byte[] { 120 }) && framer.Finish() == null, "Final record repeated or lost");
            }
            return Task.CompletedTask;
        });
        await Case("compiled framing bounds terminated and unfinished records", () =>
        {
            foreach (byte[] block in new byte[][] { [1, 2, 3, 4], [1, 2, 3, 4, 0] })
            {
                using var framer = new ByteRecordFramer(0, 3);
                try { _ = framer.Push(block).ToArray(); throw new Exception("Oversized record accepted"); }
                catch (InvalidDataException error) when (error.Message == "GitRecordTooLarge") { }
            }
            using var fragmented = new ByteRecordFramer(0, 3);
            _ = fragmented.Push([1, 2]).ToArray();
            try { _ = fragmented.Push([3, 4]).ToArray(); throw new Exception("Oversized fragmented record accepted"); }
            catch (InvalidDataException error) when (error.Message == "GitRecordTooLarge") { }
            return Task.CompletedTask;
        });
        await Case("binary frame identity", async () =>
        {
            var memory = new MemoryStream(); var writer = new Protocol(Stream.Null, memory);
            byte[] bytes = Enumerable.Range(0, 256).Select(x => (byte)x).ToArray();
            await writer.WriteAsync(new { Version = 1, RequestId = "known", Action = "input" }, bytes, CancellationToken.None);
            memory.Position = 0; var packet = await new Protocol(memory, Stream.Null).ReadAsync(CancellationToken.None);
            Require(packet != null && packet.Payload.SequenceEqual(bytes), "Binary frame changed bytes");
        });
        await Case("oversized header rejected before allocation", async () =>
        {
            byte[] lengths = new byte[8]; BinaryPrimitives.WriteInt32LittleEndian(lengths, Protocol.HeaderLimit + 1);
            try { await new Protocol(new MemoryStream(lengths), Stream.Null).ReadAsync(CancellationToken.None); throw new Exception("Oversized header accepted"); }
            catch (InvalidDataException) { }
        });
        await Case("truncated frame rejected", async () =>
        {
            byte[] lengths = new byte[8]; BinaryPrimitives.WriteInt32LittleEndian(lengths, 12);
            try { await new Protocol(new MemoryStream(lengths), Stream.Null).ReadAsync(CancellationToken.None); throw new Exception("Truncated frame accepted"); }
            catch (EndOfStreamException) { }
        });
        await Case("clean EOF distinguished from corruption", async () => Require(await new Protocol(Stream.Null, Stream.Null).ReadAsync(CancellationToken.None) == null, "EOF was not clean"));
        await Case("invalid timeout rejected before native launch", () =>
        {
            using var document = JsonDocument.Parse(JsonSerializer.Serialize(new { InvocationId = "invalid", FilePath = Path.Combine(Path.GetTempPath(), "must-not-launch-" + Guid.NewGuid().ToString("N")), ArgumentList = Array.Empty<string>(), WorkingDirectory = Path.GetTempPath(), Environment = new Dictionary<string, string>(), SuccessExitCodes = new[] { 0 }, Columns = 120, Rows = 40, Transport = "Pipe", TimeoutSeconds = 1e20, KeepInputOpen = false }));
            try { _ = InvocationRequest.Parse(document.RootElement); throw new Exception("Invalid timeout accepted"); }
            catch (ArgumentOutOfRangeException error) when (error.ParamName == "TimeoutSeconds") { }
            return Task.CompletedTask;
        });
        string directory = Path.Combine(Path.GetTempPath(), "quietcli2-store-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        await using var store = new MeasurementStore(Path.Combine(directory, "gains.sqlite"));
        if (arguments.Contains("--telemetry-only"))
        {
            await TelemetryCases.RunAsync(Case, store);
            Console.WriteLine(JsonSerializer.Serialize(new { Passed = passed, Failed = failed, Cases = results }));
            return failed == 0 ? 0 : 1;
        }
        await SecondPassCases.RunAsync(Case, store, directory);
        await RecallCases.RunAsync(Case);
        await TelemetryCases.RunAsync(Case, store);
        await CoreMigrationCases.RunAsync(Case, directory, Path.GetFullPath(Path.Combine(arguments[0], "../../../../..")));
        await Case("available stdin wakes a backpressured caller without stdout", InputBackpressureCases.ReadyInputDoesNotWaitForOutputAsync);
        await Case("business data forbidden in SQLite metadata", async () =>
        {
            using var document = JsonDocument.Parse("{\"InvocationId\":\"forbidden\",\"Data\":{\"Secret\":\"must-not-be-stored\"}}");
            try { await store.SaveAsync(document.RootElement, "invocation"); throw new Exception("Business data accepted"); }
            catch (InvalidDataException) { }
        });
        await Case("concurrent writes are retained exactly once", async () =>
        {
            await Task.WhenAll(Enumerable.Range(0, 40).Select(async index =>
            {
                using var document = JsonDocument.Parse(JsonSerializer.Serialize(new { InvocationId = index.ToString(), RootId = index.ToString(), SessionId = "test", Context = "concurrent", Role = "Business", Command = "fixture", Outcome = "Success" }));
                await store.SaveAsync(document.RootElement, "invocation");
            }));
            using var query = JsonDocument.Parse(JsonSerializer.Serialize(new { From = 0L, To = DateTimeOffset.UtcNow.AddDays(1).ToUnixTimeMilliseconds(), Context = "concurrent" }));
            var actual = JsonSerializer.SerializeToElement(await store.QueryAsync(query.RootElement));
            Require(actual.GetProperty("Rows").GetArrayLength() == 40, "Concurrent row count mismatch");
        });
        await Case("nested business metadata and exception messages rejected", async () =>
        {
            foreach (string text in new[] { "{\"InvocationId\":\"nested\",\"Execution\":{\"Data\":{\"Secret\":\"synthetic\"}}}", "{\"InvocationId\":\"message\",\"Error\":[{\"Code\":\"Synthetic\",\"Message\":\"not-permitted\"}]}" }) {
                using var document = JsonDocument.Parse(text);
                try { await store.SaveAsync(document.RootElement, "invocation"); throw new Exception("Unsafe nested field accepted"); }
                catch (InvalidDataException) { }
            }
        });
        await Case("query pagination respects the protocol byte budget", async () =>
        {
            for (int index = 0; index < 180; index++) {
                using var document = JsonDocument.Parse(JsonSerializer.Serialize(new { InvocationId = "page-" + index, Context = "page-budget", Error = Enumerable.Range(0, 128).Select(n => new { Code = "SyntheticLongDiagnosticIdentifier_" + n, Phase = "Running" }).ToArray() }));
                await store.SaveAsync(document.RootElement, "invocation");
            }
            object? after = null; var ids = new HashSet<string>(); int pages = 0;
            while (true) {
                var request = JsonSerializer.SerializeToElement(new { From = 0L, To = DateTimeOffset.UtcNow.AddDays(1).ToUnixTimeMilliseconds(), Context = "page-budget", After = after });
                var response = JsonSerializer.SerializeToElement(await store.QueryAsync(request)); pages++;
                Require(JsonSerializer.SerializeToUtf8Bytes(response).Length < Protocol.HeaderLimit - 1024, "Page exceeds the wire budget");
                foreach (var row in response.GetProperty("Rows").EnumerateArray()) Require(ids.Add(row.GetProperty("InvocationId").GetString()!), "Pagination duplicated a row");
                if (response.GetProperty("Complete").GetBoolean()) break;
                after = response.GetProperty("After").Clone();
            }
            Require(ids.Count == 180 && pages > 1, "Pagination omitted events");
        });
        await Case("legacy privacy projection is read only and scrubbing requires explicit confirmation", async () =>
        {
            string legacyPath = Path.Combine(directory, "legacy.sqlite");
            const string original = "{\"InvocationId\":\"legacy\",\"Error\":{\"Code\":\"CallbackFailed\",\"Message\":\"synthetic-private-value\"},\"Execution\":{\"Data\":{\"Secret\":\"synthetic-private-value\"}}}";
            using (var database = new FrenchExDev2.QuietCli.Storage.Database(legacyPath, true))
                database.Execute("INSERT INTO quiet2_events(id,kind,timestamp_ms,payload) VALUES(?,?,?,?)", ["legacy", "invocation", 1L, original]);
            await using var legacyStore = new MeasurementStore(legacyPath);
            var query = JsonSerializer.SerializeToElement(new { From = 0L, To = 2L });
            string safe = JsonSerializer.Serialize(await legacyStore.QueryAsync(query));
            Require(!safe.Contains("synthetic-private-value") && safe.Contains("CallbackFailed"), "Projection leaked content or lost error identity");
            try { await legacyStore.ScrubAsync(false); throw new Exception("Unconfirmed scrub accepted"); }
            catch (InvalidOperationException error) when (error.Message == "ExplicitPrivacyScrubConfirmationRequired") { }
            using (var database = new FrenchExDev2.QuietCli.Storage.Database(legacyPath, false))
                Require((string)database.Query("SELECT payload FROM quiet2_events WHERE id=?", ["legacy"])[0]["payload"] == original, "Read or rejected scrub changed history");
            Require(await legacyStore.ScrubAsync(true) == 1, "Explicit scrub omitted the legacy row");
            using (var database = new FrenchExDev2.QuietCli.Storage.Database(legacyPath, false))
                Require(!((string)database.Query("SELECT payload FROM quiet2_events WHERE id=?", ["legacy"])[0]["payload"]).Contains("synthetic-private-value"), "Explicit scrub retained private content");
        });
        await Case("terminal bridge preserves a read-only installed module", async () =>
        {
            await using var bridge = new TerminalBridge();
            if (OperatingSystem.IsWindows()) {
                try { await bridge.GetAsync(directory); throw new Exception("Unix bridge accepted on Windows"); }
                catch (PlatformNotSupportedException) { }
                return;
            }
            string module = Path.Combine(directory, "read-only-module");
            string bundle = Path.Combine(module, "resources", "transport", System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier);
            Directory.CreateDirectory(bundle);
            string original = Path.Combine(bundle, "quietcli-pty");
            byte[] known = [1, 2, 3, 4];
            await File.WriteAllBytesAsync(original, known);
            await File.WriteAllTextAsync(original + ".sha256", Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(known)), System.Text.Encoding.UTF8);
            File.SetUnixFileMode(original, UnixFileMode.UserRead);
            File.SetUnixFileMode(bundle, UnixFileMode.UserRead | UnixFileMode.UserExecute);
            string copy = await bridge.GetAsync(module);
            Require(copy != original && (await File.ReadAllBytesAsync(copy)).SequenceEqual(known), "Bridge copy changed executable bytes");
            Require(File.GetUnixFileMode(original) == UnixFileMode.UserRead, "Installed module permissions were changed");
            Require(File.GetUnixFileMode(copy) == (UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute), "Executable copy was not private");
            await bridge.DisposeAsync();
            Require(!File.Exists(copy), "Owned executable copy was retained");
        });
        foreach (bool hold in new[] { false, true }) await Case(hold ? "drain cancellation cannot claim EOF" : "finite process source is counted once", async () =>
        {
            var factory = new AuditProcessFactory { HoldOutput = hold };
            var request = new InvocationRequest("owned-fixture", "not-executed", [], Path.GetTempPath(), new System.Collections.Hashtable(), "Pipe", 120, 40, 5, 0.05, 1024, [0], false, null);
            await using var invocation = await Invocation.StartAsync(request, factory);
            var deadline = DateTimeOffset.UtcNow.AddSeconds(2);
            while (!invocation.IsCompleted) { await invocation.NextAsync(); Require(DateTimeOffset.UtcNow < deadline, "Drain deadline was not enforced"); }
            var snapshot = JsonSerializer.SerializeToElement(invocation.Snapshot());
            Require(factory.Creations == 1, "Process was retried");
            Require(snapshot.GetProperty("SourceComplete").GetBoolean() == !hold, "EOF certainty mismatch");
            Require(snapshot.GetProperty("StdoutBytesRead").GetInt64() == (hold ? 0 : 3), "Source byte count changed");
            if (hold) Require(snapshot.GetProperty("Error").GetString() == "OutputDrainInterrupted", "Interrupted drain lost its diagnostic code");
        });
        Console.WriteLine(JsonSerializer.Serialize(new { Passed = passed, Failed = failed, Cases = results }));
        return failed == 0 ? 0 : 1;
    }

    /// <summary>Throws when an independently known invariant fails.</summary>
    /// <param name="condition">Expected true condition.</param>
    /// <param name="message">Failure description.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
