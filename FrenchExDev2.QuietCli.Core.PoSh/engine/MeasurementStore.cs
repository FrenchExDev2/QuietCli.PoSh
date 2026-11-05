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
    internal Task SaveAsync(JsonElement metadata, string kind) => ExecuteAsync(() =>
    {
        metadata = MeasurementModels.Validate(metadata, kind);
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
        string sql = "SELECT id,timestamp_ms,payload FROM quiet2_events WHERE timestamp_ms>=? AND timestamp_ms<?";
        var values = new List<object> { request.GetProperty("From").GetInt64(), request.GetProperty("To").GetInt64() };
        if (request.TryGetProperty("Context", out var context) && context.ValueKind == JsonValueKind.String) { sql += " AND context=?"; values.Add(context.GetString()!); }
        if (request.TryGetProperty("Generic", out var generic) && generic.GetBoolean()) sql += " AND context IS NULL";
        if (request.TryGetProperty("SessionId", out var session) && session.ValueKind == JsonValueKind.String) { sql += " AND session_id=?"; values.Add(session.GetString()!); }
        if (request.TryGetProperty("ModuleId", out var module) && module.ValueKind == JsonValueKind.String) { sql += " AND json_extract(payload,'$.HandlerId')=?"; values.Add(module.GetString()!); }
        if (request.TryGetProperty("After", out var cursor) && cursor.ValueKind == JsonValueKind.Object) {
            sql += " AND (timestamp_ms>? OR (timestamp_ms=? AND id>?))";
            values.Add(cursor.GetProperty("Timestamp").GetInt64()); values.Add(cursor.GetProperty("Timestamp").GetInt64()); values.Add(cursor.GetProperty("Id").GetString()!);
        }
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
