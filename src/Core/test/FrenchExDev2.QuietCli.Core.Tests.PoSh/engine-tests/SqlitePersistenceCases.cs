using System.Collections;
using System.Reflection;
using System.Text.Json;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Storage;

/// <summary>Independent persistence, resource ownership and prepared-binding invariants over real SQLite.</summary>
internal static class SqlitePersistenceCases
{
    /// <summary>Runs deterministic lifecycle regressions, seeded value properties and malformed-binding cases.</summary>
    /// <param name="run">Owning companion assertion runner.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run)
    {
        string directory = Path.Combine(Path.GetTempPath(), "quietcli-sqlite-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            await run("SQLite lazy store and rejected metadata create no database", async () =>
            {
                string file = Path.Combine(directory, "lazy.sqlite");
                await using var store = new MeasurementStore(file);
                var result = JsonSerializer.SerializeToElement(await store.QueryAsync(Query()));
                Require(result.GetProperty("Rows").GetArrayLength() == 0 && !File.Exists(file), "An empty read created storage");
                try { await store.SaveAsync(JsonSerializer.SerializeToElement(new { InvocationId = "unsafe", Data = "private" }), "invocation"); throw new Exception("Unsafe metadata accepted"); }
                catch (InvalidDataException) { }
                Require(!File.Exists(file), "Rejected metadata created storage");
            });
            await run("SQLite preparation is nonblocking serialized once and drained before disposal", async () =>
            {
                string file = Path.Combine(directory, "prepared.sqlite");
                using var release = new ManualResetEventSlim();
                var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                int opens = 0;
                Database? connection = null;
                var connections = new List<Database>();
                var store = new MeasurementStore(file, value => {
                    Interlocked.Increment(ref opens); entered.SetResult();
                    if (!release.Wait(TimeSpan.FromSeconds(15))) throw new TimeoutException("Fixture preparation gate was not released");
                    connection = new Database(value, true, cacheStatements: true);
                    connections.Add(connection);
                    return connection;
                });
                try
                {
                    store.BeginPreparation();
                    await entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
                    for (int i = 0; i < 32; i++) store.BeginPreparation();
                    var saves = Enumerable.Range(0, 40).Select(i => store.SaveAsync(new MeasurementRecord("prepared-" + i, Context: "prepared"), "invocation")).ToArray();
                    Require(saves.All(task => !task.IsCompleted), "Save bypassed pending initialization");
                    var disposal = store.DisposeAsync().AsTask();
                    Require(!disposal.IsCompleted, "Disposal abandoned accepted writes");
                    release.Set();
                    await Task.WhenAll(saves).WaitAsync(TimeSpan.FromSeconds(15));
                    await disposal.WaitAsync(TimeSpan.FromSeconds(15));
                    Require(opens == 1, "Preparation or later writes opened another connection");
                    using var independent = new Database(file, false);
                    Require((long)independent.Query("SELECT COUNT(*) AS n FROM quiet2_events", [])[0]["n"] == 40, "Accepted writes were lost");
                    try { connection!.Execute("SELECT 1", []); throw new Exception("Writer survived disposal"); }
                    catch (ObjectDisposedException) { }
                }
                finally { release.Set(); await store.DisposeAsync(); foreach (var owned in connections) owned.Dispose(); }
            });
            await run("SQLite preparation failure is observed by saves without reopening or killing reads", async () =>
            {
                string file = Path.Combine(directory, "failure.sqlite");
                int opens = 0;
                await using var store = new MeasurementStore(file, _ => { Interlocked.Increment(ref opens); throw new IOException("ExpectedStorageFailure"); });
                store.BeginPreparation();
                for (int i = 0; i < 3; i++)
                {
                    try { await store.SaveAsync(new MeasurementRecord("failure-" + i), "invocation"); throw new Exception("Storage failure was hidden"); }
                    catch (IOException error) when (error.Message == "ExpectedStorageFailure") { }
                    store.BeginPreparation();
                }
                Require(opens == 1 && !File.Exists(file), "Failed initialization retried or created storage");
                _ = await store.QueryAsync(Query());
            });
            await run("SQLite cached statements reuse handles and release generated Unicode and null bindings", () =>
            {
                using var database = new Database(Path.Combine(directory, "bindings.sqlite"), true, cacheStatements: true);
                const string sql = "SELECT ? AS text, ? AS number";
                IntPtr statement = database.PrepareCached(sql);
                var random = new Random(186203);
                for (int i = 0; i < 256; i++)
                {
                    string? text = i % 3 == 0 ? null : "é漢🙂'" + random.NextInt64();
                    long number = random.NextInt64();
                    var row = database.Query(sql, [text!, number])[0];
                    Require((text is null ? row["text"] is null : (string)row["text"] == text) && (long)row["number"] == number, "Rebinding changed a typed value");
                    Require(database.PrepareCached(sql) == statement, "The compiled statement was replaced");
                    Require(Sqlite.sqlite3_step(statement) == 100 && Sqlite.sqlite3_column_type(statement, 0) == 5 && Sqlite.sqlite3_column_type(statement, 1) == 5, "A completed statement retained bound values");
                    Require(Sqlite.sqlite3_reset(statement) == 0, "Independent binding observation could not reset");
                }
                return Task.CompletedTask;
            });
            await run("SQLite failed bindings and constraints leave reusable statements and transactions clean", () =>
            {
                using var database = new Database(Path.Combine(directory, "recovery.sqlite"), true, cacheStatements: true);
                database.Execute("CREATE TABLE sample(id INTEGER PRIMARY KEY,value TEXT)", []);
                const string insert = "INSERT INTO sample(id,value) VALUES(?,?)";
                database.Execute(insert, [1L, "initial"]);
                try { database.Execute(insert, [1L, "must-not-replace"]); throw new Exception("Duplicate primary key accepted"); }
                catch (InvalidOperationException error) when (error.Message.StartsWith("SQLite ", StringComparison.Ordinal)) { }
                foreach (object[] malformed in new object[][] { [], [2L], [2L, "extra", 3L], [2L, new object()] })
                {
                    bool rejected = false;
                    try { database.Execute(insert, malformed); }
                    catch (Exception error) when (error is ArgumentException or InvalidCastException) { rejected = true; }
                    Require(rejected, "Malformed parameter vector was accepted");
                }
                database.Execute(insert, [2L, null!]);
                var rows = database.Query("SELECT id,value FROM sample ORDER BY id", []);
                Require(rows.Count == 2 && (string)rows[0]["value"] == "initial" && rows[1]["value"] is null, "Failed reuse changed committed rows");
                return Task.CompletedTask;
            });
            await run("SQLite statement cache is bounded and connection disposal releases every handle", () =>
            {
                var database = new Database(Path.Combine(directory, "bounded.sqlite"), true, cacheStatements: true);
                try
                {
                    for (int i = 0; i < 64; i++) Require((long)database.Query("SELECT " + i + " AS value", [])[0]["value"] == i, "Uncached SQL changed result");
                    var cache = (IDictionary)typeof(Database).GetField("statements", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(database)!;
                    Require(cache.Count is > 0 and <= 16, "Statement cache grew beyond its bound");
                    database.Dispose(); database.Dispose();
                    Require(cache.Count == 0, "Disposal retained prepared statement handles");
                    try { database.Query("SELECT 1", []); throw new Exception("Disposed connection accepted a query"); }
                    catch (ObjectDisposedException) { }
                }
                finally { database.Dispose(); }
                return Task.CompletedTask;
            });
            await run("SQLite independent persistent writers preserve committed rows without holding idle locks", async () =>
            {
                string file = Path.Combine(directory, "writers.sqlite");
                await using var first = new MeasurementStore(file);
                await using var second = new MeasurementStore(file);
                first.BeginPreparation(); second.BeginPreparation();
                await Task.WhenAll(Enumerable.Range(0, 64).Select(i => (i % 2 == 0 ? first : second).SaveAsync(new MeasurementRecord("writer-" + i), "invocation")));
                using var independent = new Database(file, false);
                Require((long)independent.Query("SELECT COUNT(*) AS n FROM quiet2_events", [])[0]["n"] == 64, "Independent writers lost or duplicated committed rows");
            });
            await run("SQLite preparation flag has identical direct and wire defaults and rejects malformed types", () =>
            {
                foreach (bool? enabled in new bool?[] { null, false, true })
                {
                    var header = Start();
                    if (enabled.HasValue) header["PrepareMeasurements"] = enabled.Value;
                    var direct = new LocalMetadataRequest(header, _ => throw new Exception("Unexpected adapter"));
                    var wire = InvocationRequest.Parse(JsonSerializer.SerializeToElement(header));
                    Require(direct.Start!.PrepareMeasurements == (enabled ?? false) && wire.PrepareMeasurements == (enabled ?? false), "Preparation defaults or host mapping diverged");
                }
                var malformed = new List<object?> { null, "true", 1, new object[] { true }, new Hashtable() };
                var random = new Random(284901);
                for (int i = 0; i < 128; i++) malformed.Add((i % 3) switch { 0 => (object)random.NextInt64(), 1 => "flag-" + random.NextInt64(), _ => new object[] { random.NextDouble() } });
                foreach (object? value in malformed)
                {
                    var header = Start(); header["PrepareMeasurements"] = value;
                    bool directRejected = false, wireRejected = false;
                    try { _ = new LocalMetadataRequest(header, _ => throw new Exception()); } catch (Exception error) when (error is InvalidDataException or InvalidCastException) { directRejected = true; }
                    try { _ = InvocationRequest.Parse(JsonSerializer.SerializeToElement(header)); } catch (InvalidOperationException) { wireRejected = true; }
                    Require(directRejected && wireRejected, "Malformed preparation flag crossed a host boundary");
                }
                return Task.CompletedTask;
            });
        }
        finally
        {
            // A disposal mutant may deliberately leak a native file handle. Keep its fixture as
            // evidence instead of replacing the already recorded assertion failure with a crash.
            try { Directory.Delete(directory, recursive: true); }
            catch (IOException) { Console.Error.WriteLine("SQLite fixture retained: " + directory); }
        }
    }

    /// <summary>Builds valid native metadata without creating a process.</summary>
    private static Hashtable Start() => new() {
        ["Action"] = "start", ["InvocationId"] = "sqlite-start", ["FilePath"] = "not-launched", ["ArgumentList"] = Array.Empty<string>(),
        ["WorkingDirectory"] = Path.GetTempPath(), ["Environment"] = new Hashtable(), ["Transport"] = "Pipe", ["Columns"] = 120, ["Rows"] = 40,
        ["TimeoutSeconds"] = 5.0, ["SuccessExitCodes"] = new[] { 0 }, ["KeepInputOpen"] = false,
    };

    /// <summary>Reads the complete owned fixture interval.</summary>
    private static JsonElement Query() => JsonSerializer.SerializeToElement(new { From = 0L, To = long.MaxValue });

    /// <summary>Checks an independently known persistence or lifecycle invariant.</summary>
    /// <param name="condition">Required condition.</param>
    /// <param name="message">Diagnostic on failure.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
