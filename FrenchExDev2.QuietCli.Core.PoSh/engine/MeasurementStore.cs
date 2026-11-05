using System.Text.Json;
using System.Threading.Channels;
using FrenchExDev2.QuietCli.Storage;

namespace FrenchExDev2.QuietCli;

/// <summary>Serializes SQLite access on a private worker; records counters, never business objects.</summary>
internal sealed class MeasurementStore : IAsyncDisposable
{
    /// <summary>Native work contract used by the isolated runtime.</summary>
    private readonly Channel<Func<Task>> work = Channel.CreateBounded<Func<Task>>(64);
    /// <summary>Native worker contract used by the isolated runtime.</summary>
    private readonly Task worker;
    /// <summary>Native path contract used by the isolated runtime.</summary>
    private readonly string path;

    /// <summary>Initializes the worker without creating a database until an operation requests it.</summary>
    /// <param name="path">Explicit filesystem location.</param>
    internal MeasurementStore(string path)
    {
        this.path = path;
        worker = Task.Run(async () => { await foreach (var item in work.Reader.ReadAllAsync()) await item(); });
    }

    /// <summary>Executes one database operation without concurrent connection use.</summary>
    /// <param name="operation">One serialized database operation.</param>
    private async Task<T> ExecuteAsync<T>(Func<T> operation)
    {
        var result = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        await work.Writer.WriteAsync(() => { try { result.SetResult(operation()); } catch (Exception error) { result.SetException(error); } return Task.CompletedTask; });
        return await result.Task;
    }

    /// <summary>Persists whitelisted metadata. Payloads, callback text and business values are forbidden.</summary>
    /// <param name="metadata">Control or counter metadata, never business data.</param>
/// <param name="kind">Metadata record kind.</param>
    internal Task SaveAsync(JsonElement metadata, string kind) => SaveValidatedAsync(() => MeasurementModels.Validate(metadata, kind), kind);

    /// <summary>Persists typed telemetry without transport serialization; storage JSON remains explicit.</summary>
    /// <param name="metadata">Closed counter record.</param>
    /// <param name="kind">Invocation or delivery.</param>
    internal Task SaveAsync(MeasurementRecord metadata, string kind) => SaveValidatedAsync(() => MeasurementModels.Validate(metadata, kind), kind);

    /// <summary>Validates once on the worker, then stores only the approved representation.</summary>
    /// <param name="validate">Closed validation operation, not caller business code.</param>
    /// <param name="kind">Storage kind.</param>
    private Task SaveValidatedAsync(Func<JsonElement> validate, string kind) => ExecuteAsync(() =>
    {
        var metadata = validate();
        if (System.Text.Encoding.UTF8.GetByteCount(metadata.GetRawText()) > Protocol.HeaderLimit - 4096) throw new InvalidDataException("MeasurementRowTooLarge");
        // Reads one nullable scalar metadata field, never business Data.
        string? Value(string name) => metadata.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null ? value.GetString() : null;
        string id = kind == "delivery" ? Value("DeliveryId")! : Value("InvocationId")!;
        using var database = new Database(path, true);
        database.Execute("INSERT INTO quiet2_events(id,kind,timestamp_ms,parent_id,root_id,session_id,context,role,command,outcome,payload) VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,outcome=excluded.outcome",
            [id, kind, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), Value("ParentId")!, Value("RootId")!, Value("SessionId")!, Value("Context")!, Value("Role")!, Value("Command")!, Value("Outcome")!, metadata.GetRawText()]);
        return true;
    });

    /// <summary>Reads bounded metadata by context/session/time without creating missing databases.</summary>
    /// <param name="request">Validated execution metadata, never the business object.</param>
    internal Task<object> QueryAsync(JsonElement request) => ExecuteAsync<object>(() =>
    {
        if (!File.Exists(path)) return new { Rows = Array.Empty<JsonElement>(), Complete = true };
        using var database = new Database(path, false);
        var (sql, values) = Select(request);
        const int pageRows = 128;
        int pageBytes = Protocol.HeaderLimit / 2;
        sql += " ORDER BY timestamp_ms,id LIMIT 129";
        var rows = database.Query(sql, values.ToArray());
        var selected = new List<JsonElement>(); int bytes = 1024; object? after = null;
        foreach (var row in rows) {
            string payload = (string)row["payload"]; int size = System.Text.Encoding.UTF8.GetByteCount(payload) + 2;
            if (selected.Count >= pageRows || selected.Count > 0 && bytes + size > pageBytes) break;
            if (size > Protocol.HeaderLimit - 4096) throw new InvalidDataException("MeasurementRowTooLarge");
            selected.Add(MeasurementProjection.Read(payload)); bytes += size;
            after = new { Timestamp = (long)row["timestamp_ms"], Id = (string)row["id"] };
        }
        bool complete = selected.Count == rows.Count;
        return new { Rows = selected.ToArray(), Complete = complete, After = complete ? null : after };
    });

    /// <summary>Builds the parameterized time/context/session/module selection used by both reports and pages.</summary>
    /// <param name="request">Control filters only.</param>
    private static (string Sql, List<object> Values) Select(JsonElement request)
    {
        var (sql, values) = Select(GainSelection.Parse(request));
        if (request.TryGetProperty("After", out var cursor) && cursor.ValueKind == JsonValueKind.Object) {
            sql += " AND (timestamp_ms>? OR (timestamp_ms=? AND id>?))";
            values.Add(cursor.GetProperty("Timestamp").GetInt64()); values.Add(cursor.GetProperty("Timestamp").GetInt64()); values.Add(cursor.GetProperty("Id").GetString()!);
        }
        return (sql, values);
    }

    /// <summary>Builds the same parameterized selection from typed report filters.</summary>
    /// <param name="request">Closed selection.</param>
    private static (string Sql, List<object> Values) Select(GainSelection request)
    {
        string sql = "SELECT id,timestamp_ms,payload FROM quiet2_events WHERE timestamp_ms>=? AND timestamp_ms<?";
        var values = new List<object> { request.From, request.To };
        if (request.Context != null) { sql += " AND context=?"; values.Add(request.Context); }
        if (request.Generic) sql += " AND context IS NULL";
        if (request.SessionId != null) { sql += " AND session_id=?"; values.Add(request.SessionId); }
        if (request.ModuleId != null) { sql += " AND json_extract(payload,'$.HandlerId')=?"; values.Add(request.ModuleId); }
        return (sql, values);
    }

    /// <summary>Aggregates safe metadata on the SQLite worker without exporting original event rows.</summary>
    /// <param name="request">Validated filters, grouping dimension and event budget.</param>
    /// <param name="cancellation">Cancels abandoned scans between bounded pages and individual records.</param>
    internal Task<GainReport> GainAsync(JsonElement request, CancellationToken cancellation = default) => GainAsync(GainSelection.Parse(request), cancellation);

    /// <summary>Aggregates a closed selection without encoding transport filters.</summary>
    /// <param name="request">Detached filter values.</param>
    /// <param name="cancellation">Cancels abandoned scans.</param>
    internal Task<GainReport> GainAsync(GainSelection request, CancellationToken cancellation = default) => ExecuteAsync(() =>
    {
        int maximum = request.MaxEvents;
        if (maximum < 1 || maximum > 1000000) throw new InvalidDataException("InvalidGainEventBudget");
        var accumulator = new GainAccumulator(request.GroupBy);
        if (!File.Exists(path)) return accumulator.Build(true);
        using var database = new Database(path, false);
        var (selection, filters) = Select(request);
        long? timestamp = null; string? identifier = null; int consumed = 0;
        database.Execute("BEGIN", []);
        try
        {
            while (true)
            {
                cancellation.ThrowIfCancellationRequested();
                string sql = selection; var values = new List<object>(filters);
                if (timestamp.HasValue)
                {
                    sql += " AND (timestamp_ms>? OR (timestamp_ms=? AND id>?))";
                    values.Add(timestamp.Value); values.Add(timestamp.Value); values.Add(identifier!);
                }
                int count = Math.Min(128, maximum - consumed + 1);
                sql += " ORDER BY timestamp_ms,id LIMIT ?"; values.Add(count);
                var rows = database.Query(sql, values.ToArray());
                foreach (var row in rows)
                {
                    cancellation.ThrowIfCancellationRequested();
                    if (consumed == maximum) return accumulator.Build(false);
                    string payload = (string)row["payload"];
                    if (System.Text.Encoding.UTF8.GetByteCount(payload) > Protocol.HeaderLimit - 4096) throw new InvalidDataException("MeasurementRowTooLarge");
                    var safe = MeasurementProjection.Read(payload);
                    accumulator.Add(safe.Deserialize<MeasurementRecord>() ?? throw new InvalidDataException("InvalidMeasurementRecord"));
                    consumed++; timestamp = (long)row["timestamp_ms"]; identifier = (string)row["id"];
                }
                if (rows.Count < count) return accumulator.Build(true);
            }
        }
        finally { database.Execute("ROLLBACK", []); }
    });
    /// <summary>Scrubs legacy diagnostic content only following an explicit caller confirmation.</summary>
    /// <param name="confirmed">Required irreversible-operation confirmation.</param>
    internal Task<int> ScrubAsync(bool confirmed) => ExecuteAsync(() => {
        if (!confirmed) throw new InvalidOperationException("ExplicitPrivacyScrubConfirmationRequired");
        if (!File.Exists(path)) return 0;
        using var database = new Database(path, true);
        return MeasurementProjection.Scrub(database);
    });

    /// <summary>Flushes accepted writes and closes the worker normally.</summary>
    public async ValueTask DisposeAsync() { work.Writer.TryComplete(); await worker; }
}
