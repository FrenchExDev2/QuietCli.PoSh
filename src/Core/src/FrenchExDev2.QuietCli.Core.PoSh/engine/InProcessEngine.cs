using System.Text;
using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>Direct .NET host with no child engine process or pipe; control JSON remains explicit.</summary>
public sealed class InProcessEngine : IAsyncDisposable
{
    /// <summary>The same dispatcher used by the isolated server.</summary>
    private readonly EngineSession session;
    /// <summary>Serializes dispatch and disposal without holding a PowerShell runspace.</summary>
    private readonly SemaphoreSlim gate = new(1, 1);
    /// <summary>Rejects requests once disposal starts.</summary>
    private bool disposed;

    /// <summary>Owns one private session.</summary>
    /// <param name="session">Initialized engine session.</param>
    private InProcessEngine(EngineSession session) => this.session = session;

    /// <summary>Creates a direct engine without creating a database or running a command.</summary>
    /// <param name="database">Explicit database path.</param>
    /// <param name="moduleRoot">Verified module root.</param>
    public static async Task<InProcessEngine> CreateAsync(string database, string moduleRoot) => new(await EngineSession.CreateAsync(database, moduleRoot));

    /// <summary>Reads a transient block directly, avoiding control JSON on the hot path.</summary>
    /// <param name="invocationId">Owned invocation identity.</param>
    /// <param name="requestId">Caller request identity.</param>
    public async Task<LocalEngineReply> ReadAsync(string invocationId, string requestId)
    {
        if (invocationId.Length > 128 || requestId.Length > 128) throw new InvalidDataException("ControlIdentityTooLarge");
        await gate.WaitAsync();
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            try
            {
                var reply = await session.ReadAsync(invocationId);
                // The fixed snapshot has bounded scalar fields; no caller values or business Data.
                return new LocalEngineReply(null, reply.Payload ?? [], new { Version = ProtocolSpecification.Version, RequestId = requestId, Ok = true, Data = reply.Data });
            }
            catch (Exception error) when (error is not (OperationCanceledException or TimeoutException))
            {
                return Reply(new { Version = ProtocolSpecification.Version, RequestId = requestId, Ok = false, Error = new { Code = error.GetType().Name, Message = error.Message } }, null);
            }
        }
        finally { gate.Release(); }
    }

    /// <summary>Dispatches bounded native controls without JSON or a pipe exchange.</summary>
    /// <param name="control">Closed input or lifecycle operation.</param>
    /// <param name="invocationId">Owned invocation identity.</param>
    /// <param name="requestId">Caller request identity.</param>
    /// <param name="payload">One input block; callers must not mutate an accepted block.</param>
    /// <param name="columns">Terminal width for Resize.</param>
    /// <param name="rows">Terminal height for Resize.</param>
    public async Task<LocalEngineReply> ControlAsync(LocalControl control, string invocationId, string requestId, byte[] payload, int columns = 0, int rows = 0)
    {
        if (invocationId.Length > 128 || requestId.Length > 128) throw new InvalidDataException("ControlIdentityTooLarge");
        if (payload.Length > Protocol.BlockSize) throw new InvalidDataException("InputBlockTooLarge");
        await gate.WaitAsync();
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            try
            {
                var data = await session.ControlAsync(control, invocationId, payload, columns, rows);
                return new LocalEngineReply(null, [], new { Version = ProtocolSpecification.Version, RequestId = requestId, Ok = true, Data = data });
            }
            catch (Exception error) when (error is not (OperationCanceledException or TimeoutException))
            {
                return Reply(new { Version = ProtocolSpecification.Version, RequestId = requestId, Ok = false, Error = new { Code = error.GetType().Name, Message = error.Message } }, null);
            }
        }
        finally { gate.Release(); }
    }

    /// <summary>Adapts closed metadata on the caller thread, then dispatches without transport JSON.</summary>
    /// <param name="header">Explicit control fields; unknown fields are rejected recursively.</param>
    /// <param name="adapt">Synchronous PowerShell metadata property-bag adapter.</param>
    public async Task<LocalEngineReply> MetadataAsync(System.Collections.IDictionary header, Func<object, System.Collections.IDictionary> adapt)
    {
        string id = header["RequestId"] as string ?? "";
        LocalMetadataRequest request;
        // All PowerShell adaptation precedes the first await, including a contended session gate.
        try
        {
            if (id.Length > 128 || Convert.ToInt32(header["Version"]) != ProtocolSpecification.Version) throw new InvalidDataException("ProtocolMismatch");
            request = new LocalMetadataRequest(header, adapt);
        }
        catch (Exception error) when (error is not (OperationCanceledException or TimeoutException))
        {
            return Reply(new { Version = ProtocolSpecification.Version, RequestId = id, Ok = false, Error = new { Code = error.GetType().Name, Message = error.Message } }, null);
        }
        await gate.WaitAsync();
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            try
            {
                var data = await session.MetadataAsync(request);
                return new LocalEngineReply(null, [], new { Version = ProtocolSpecification.Version, RequestId = id, Ok = true, Data = data });
            }
            catch (Exception error) when (error is not (OperationCanceledException or TimeoutException))
            {
                return Reply(new { Version = ProtocolSpecification.Version, RequestId = id, Ok = false, Error = new { Code = error.GetType().Name, Message = error.Message } }, null);
            }
        }
        finally { gate.Release(); }
    }

    /// <summary>Dispatches bounded metadata and bytes directly; never accepts a business object.</summary>
    /// <param name="header">UTF-8 JSON control header.</param>
    /// <param name="payload">Transient native input bytes.</param>
    public async Task<LocalEngineReply> RequestAsync(byte[] header, byte[] payload)
    {
        if (header.Length < 2 || header.Length > Protocol.HeaderLimit || payload.Length > Protocol.BlockSize) throw new InvalidDataException("InvalidFrameLength");
        using var document = JsonDocument.Parse(header);
        var request = document.RootElement;
        if (request.GetProperty("Version").GetInt32() != ProtocolSpecification.Version) throw new InvalidDataException("ProtocolMismatch");
        string id = request.GetProperty("RequestId").GetString()!;
        await gate.WaitAsync();
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            try
            {
                var reply = await session.ExecuteAsync(request, payload);
                return Reply(new { Version = ProtocolSpecification.Version, RequestId = id, Ok = true, Data = reply.Data }, reply.Payload);
            }
            catch (Exception error) when (error is not (OperationCanceledException or TimeoutException))
            {
                return Reply(new { Version = ProtocolSpecification.Version, RequestId = id, Ok = false, Error = new { Code = error.GetType().Name, Message = error.Message } }, null);
            }
        }
        finally { gate.Release(); }
    }

    /// <summary>Enforces the same response bounds as the pipe protocol.</summary>
    /// <param name="metadata">Response metadata only.</param>
    /// <param name="payload">One transient native output block.</param>
    private static LocalEngineReply Reply(object metadata, byte[]? payload)
    {
        string json = JsonSerializer.Serialize(metadata);
        if (Encoding.UTF8.GetByteCount(json) > Protocol.HeaderLimit || (payload?.Length ?? 0) > Protocol.BlockSize) throw new InvalidDataException("ResponseTooLarge");
        return new LocalEngineReply(json, payload ?? []);
    }

    /// <summary>Closes owned children and telemetry; cannot unload the host CLR or loaded assembly.</summary>
    public async ValueTask DisposeAsync()
    {
        await gate.WaitAsync();
        try { if (!disposed) { disposed = true; await session.DisposeAsync(); } }
        finally { gate.Release(); }
    }
}

/// <summary>A direct reply; binary payload is never encoded as JSON or base64.</summary>
/// <param name="HeaderJson">Bounded JSON for remaining metadata requests or failures; null for direct reads and controls.</param>
/// <param name="Payload">Transient output bytes.</param>
/// <param name="Header">Direct fixed-shape read/control metadata, without serialization.</param>
public sealed record LocalEngineReply(string? HeaderJson, byte[] Payload, object? Header = null);

/// <summary>Closed native controls available through direct hosting; no business values.</summary>
public enum LocalControl
{
    /// <summary>Attempt one bounded write; false means the caller must drain before retrying.</summary>
    Input,
    /// <summary>Queue EOF after all accepted writes.</summary>
    Eof,
    /// <summary>Cancel only the owned native process.</summary>
    Cancel,
    /// <summary>Resize the owned terminal.</summary>
    Resize,
    /// <summary>Dispose and remove the owned invocation.</summary>
    Release
}