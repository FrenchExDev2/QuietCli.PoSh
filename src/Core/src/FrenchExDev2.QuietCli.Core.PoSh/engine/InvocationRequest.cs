using System.Collections;
using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>Validated native request, independent from the JSON transport and caller business data.</summary>
/// <param name="Id">Caller-generated invocation identity.</param>
/// <param name="FilePath">Resolved executable path.</param>
/// <param name="Arguments">Exact native argument vector.</param>
/// <param name="Directory">Native working directory.</param>
/// <param name="Environment">Child-only environment overrides.</param>
/// <param name="Transport">Pipe or Pty.</param>
/// <param name="Columns">Terminal width.</param>
/// <param name="Rows">Terminal height.</param>
/// <param name="TimeoutSeconds">Native execution deadline.</param>
/// <param name="DrainTimeoutSeconds">Maximum time to reach EOF after process exit.</param>
/// <param name="ReadBlockBytes">Bounded native block size.</param>
/// <param name="SuccessCodes">Accepted native exit codes.</param>
/// <param name="KeepInputOpen">Caller will feed input interactively.</param>
/// <param name="InputPath">Optional explicit input file.</param>
internal sealed record InvocationRequest(string Id, string FilePath, string[] Arguments, string Directory, IDictionary Environment, string Transport, int Columns, int Rows, double TimeoutSeconds, double DrainTimeoutSeconds, int ReadBlockBytes, int[] SuccessCodes, bool KeepInputOpen, string? InputPath)
{
    /// <summary>Validates the whole start request before any native process is created.</summary>
    /// <param name="request">Control header; contains no caller business object.</param>
    internal static InvocationRequest Parse(JsonElement request)
    {
        double timeout = request.GetProperty("TimeoutSeconds").GetDouble();
        if (!RequestLimits.IsValidTimeout(timeout)) throw new ArgumentOutOfRangeException("TimeoutSeconds");
        double drain = request.TryGetProperty("DrainTimeoutSeconds", out var drainValue) ? drainValue.GetDouble() : 30;
        if (!RequestLimits.IsValidDrainTimeout(drain)) throw new ArgumentOutOfRangeException("DrainTimeoutSeconds");
        int size = request.TryGetProperty("ReadBlockBytes", out var block) ? block.GetInt32() : Protocol.BlockSize;
        if (!RequestLimits.IsValidReadBlock(size)) throw new ArgumentOutOfRangeException("ReadBlockBytes");
        int columns = request.GetProperty("Columns").GetInt32(), rows = request.GetProperty("Rows").GetInt32();
        ValidateDimensions(columns, rows);
        string transport = request.GetProperty("Transport").GetString()!;
        if (!RequestLimits.IsValidTransport(transport)) throw new ArgumentException("InvalidTransport");
        string id = request.GetProperty("InvocationId").GetString()!;
        if (string.IsNullOrEmpty(id) || id.Length > 128) throw new ArgumentException("InvalidInvocationId");
        var environment = new Hashtable();
        foreach (var entry in request.GetProperty("Environment").EnumerateObject()) environment[entry.Name] = entry.Value.ValueKind == JsonValueKind.Null ? null : entry.Value.GetString();
        string? input = request.TryGetProperty("InputPath", out var inputValue) && inputValue.ValueKind == JsonValueKind.String ? inputValue.GetString() : null;
        return new(id, request.GetProperty("FilePath").GetString()!, request.GetProperty("ArgumentList").EnumerateArray().Select(x => x.GetString()!).ToArray(), request.GetProperty("WorkingDirectory").GetString()!, environment, transport, columns, rows, timeout, drain, size, request.GetProperty("SuccessExitCodes").EnumerateArray().Select(x => x.GetInt32()).ToArray(), request.GetProperty("KeepInputOpen").GetBoolean(), input);
    }

    /// <summary>Validates direct and isolated launch options before any side effect.</summary>
    internal InvocationRequest Validated()
    {
        if (!RequestLimits.IsValidTimeout(TimeoutSeconds)) throw new ArgumentOutOfRangeException(nameof(TimeoutSeconds));
        if (!RequestLimits.IsValidDrainTimeout(DrainTimeoutSeconds)) throw new ArgumentOutOfRangeException(nameof(DrainTimeoutSeconds));
        if (!RequestLimits.IsValidReadBlock(ReadBlockBytes)) throw new ArgumentOutOfRangeException(nameof(ReadBlockBytes));
        ValidateDimensions(Columns, Rows);
        if (!RequestLimits.IsValidTransport(Transport)) throw new ArgumentException("InvalidTransport");
        if (string.IsNullOrEmpty(Id) || Id.Length > 128) throw new ArgumentException("InvalidInvocationId");
        if (string.IsNullOrEmpty(FilePath) || string.IsNullOrEmpty(Directory) || Arguments == null || Environment == null || SuccessCodes == null) throw new ArgumentException("InvalidNativeRequest");
        return this;
    }

    /// <summary>Uses the same limits for initial dimensions and interactive resizes.</summary>
    /// <param name="columns">Terminal width.</param>
    /// <param name="rows">Terminal height.</param>
    internal static void ValidateDimensions(int columns, int rows) { if (!RequestLimits.IsValidDimension(columns) || !RequestLimits.IsValidDimension(rows)) throw new ArgumentOutOfRangeException("TerminalSize"); }
}

/// <summary>Process-creation port, injectable for independent lifecycle tests.</summary>
internal interface IProcessChannelFactory
{
    /// <summary>Creates exactly one owned native process, without retries.</summary>
    /// <param name="request">Prevalidated execution request.</param>
    /// <param name="token">Startup deadline.</param>
    ValueTask<IProcessChannel> CreateAsync(InvocationRequest request, CancellationToken token);
}

/// <summary>Composition-root adapter selecting platform transports.</summary>
/// <param name="bridge">Verified Unix bridge path for explicit PTY requests.</param>
internal sealed class ProcessChannelFactory(string bridge) : IProcessChannelFactory
{
    /// <summary>Constructs a transport once; caller owns disposal even when later setup fails.</summary>
    /// <param name="request">Prevalidated execution request.</param>
    /// <param name="token">Startup deadline.</param>
    public async ValueTask<IProcessChannel> CreateAsync(InvocationRequest request, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (request.Transport == "Pty" && OperatingSystem.IsWindows()) return new ConPtyChannel(request.FilePath, request.Arguments, request.Directory, request.Environment, request.Columns, request.Rows);
        return await PipeChannel.StartAsync(request.FilePath, request.Arguments, request.Directory, request.Environment, true, request.Transport == "Pty" ? bridge : "", request.Columns, request.Rows, token);
    }
}
