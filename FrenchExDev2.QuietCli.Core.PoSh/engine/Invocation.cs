using System.Collections;
using System.Diagnostics;
using System.Text.Json;
using System.Threading.Channels;

namespace FrenchExDev2.QuietCli;

/// <summary>One transient observed native block.</summary>
/// <param name="Stream">stdout, stderr or terminal.</param>
/// <param name="Bytes">Exact bytes consumed from the process.</param>
internal sealed record OutputBlock(string Stream, byte[] Bytes);

/// <summary>A native invocation with bounded queues; no capture, spool, or business data.</summary>
internal sealed class Invocation : IAsyncDisposable
{
    /// <summary>Native output contract used by the isolated runtime.</summary>
    private readonly Channel<OutputBlock> output = Channel.CreateBounded<OutputBlock>(new BoundedChannelOptions(ProtocolSpecification.QueueBlocks) { FullMode = BoundedChannelFullMode.Wait });
    /// <summary>Native input contract used by the isolated runtime.</summary>
    private readonly Channel<byte[]> input = Channel.CreateBounded<byte[]>(new BoundedChannelOptions(ProtocolSpecification.QueueBlocks) { FullMode = BoundedChannelFullMode.Wait });
    /// <summary>Native disconnected contract used by the isolated runtime.</summary>
    private readonly CancellationTokenSource disconnected = new();
    /// <summary>Native deadline contract used by the isolated runtime.</summary>
    private readonly CancellationTokenSource deadline;
    /// <summary>Native process contract used by the isolated runtime.</summary>
    private readonly IProcessChannel process;
    /// <summary>Native completion contract used by the isolated runtime.</summary>
    private readonly Task completion;
    /// <summary>Native writer contract used by the isolated runtime.</summary>
    private readonly Task writer;
    /// <summary>Native watch contract used by the isolated runtime.</summary>
    private readonly Stopwatch watch = Stopwatch.StartNew();
    /// <summary>Native stdin bytes, stdout bytes, stderr bytes contract used by the isolated runtime.</summary>
    private long stdinBytes, stdoutBytes, stderrBytes;
    /// <summary>Native cancelled, timed out contract used by the isolated runtime.</summary>
    private bool cancelled, timedOut;
    /// <summary>Native error contract used by the isolated runtime.</summary>
    private string? error;
    /// <summary>Native exit code contract used by the isolated runtime.</summary>
    private int? exitCode;
    /// <summary>Native success codes contract used by the isolated runtime.</summary>
    private readonly int[] successCodes;
    /// <summary>Configured reader block size, bounded by the protocol maximum.</summary>
    private readonly int readBlockBytes;
    /// <summary>Post-exit drain deadline; EOF and interruption are distinct outcomes.</summary>
    private readonly double drainTimeoutSeconds;
    /// <summary>Identity of the owned native process.</summary>
    internal string Id { get; }
    /// <summary>Native transport contract used by the isolated runtime.</summary>
    internal string Transport { get; }
    /// <summary>Native started contract used by the isolated runtime.</summary>
    internal bool Started { get; } = true;
    /// <summary>Native is completed contract used by the isolated runtime.</summary>
    internal bool IsCompleted => completion.IsCompleted;
    /// <summary>Native process id contract used by the isolated runtime.</summary>
    internal int ProcessId => process.Id;

    /// <summary>Starts one command using an argument vector and launches bounded asynchronous readers.</summary>
    /// <param name="request">Validated execution metadata, never the business object.</param>
    /// <param name="factory">Creates an owned transport once, with startup cancellation.</param>
    internal static async Task<Invocation> StartAsync(InvocationRequest request, IProcessChannelFactory factory)
    {
        using var startup = new CancellationTokenSource(TimeSpan.FromSeconds(request.TimeoutSeconds));
        var elapsed = Stopwatch.StartNew();
        var owned = await factory.CreateAsync(request, startup.Token);
        try {
            startup.Token.ThrowIfCancellationRequested();
            return new Invocation(request with { TimeoutSeconds = Math.Max(0.001, request.TimeoutSeconds - elapsed.Elapsed.TotalSeconds) }, owned);
        } catch { owned.Kill(); owned.Dispose(); throw; }
    }

    /// <summary>Starts a validated request using an injected process factory.</summary>
    /// <param name="request">Transport-independent native request.</param>
    /// <param name="owned">Already created process whose lifetime is transferred to this invocation.</param>
    private Invocation(InvocationRequest request, IProcessChannel owned)
    {
        Id = request.Id; readBlockBytes = request.ReadBlockBytes; Transport = request.Transport;
        successCodes = request.SuccessCodes; drainTimeoutSeconds = request.DrainTimeoutSeconds;
        deadline = new CancellationTokenSource(TimeSpan.FromSeconds(request.TimeoutSeconds));
        process = owned;
        deadline.Token.Register(() => { timedOut = true; process.Kill(); });
        if (request.InputPath != null)
        {
            input.Writer.TryComplete();
            writer = FeedFileAsync(request.InputPath);
        }
        else
        {
            writer = WriteInputAsync();
            if (!request.KeepInputOpen) input.Writer.TryComplete();
        }
        completion = RunAsync();
    }

    /// <summary>Reads bytes once and transfers ownership to the bounded consumer queue.</summary>
    /// <param name="source">Native source stream, consumed without capture.</param>
/// <param name="name">name for this native operation.</param>
    private async Task DrainAsync(Stream source, string name)
    {
        byte[] buffer = new byte[readBlockBytes];
        try
        {
            int count;
            while ((count = await source.ReadAsync(buffer, disconnected.Token).AsTask().WaitAsync(disconnected.Token)) != 0)
            {
                if (name == "stderr") Interlocked.Add(ref stderrBytes, count); else Interlocked.Add(ref stdoutBytes, count);
                await output.Writer.WriteAsync(new(name, buffer.AsSpan(0, count).ToArray()), disconnected.Token);
            }
        }
        catch (Exception exception) when (exception is IOException or OperationCanceledException or ObjectDisposedException)
        { Interlocked.CompareExchange(ref error, disconnected.IsCancellationRequested ? "OutputDrainInterrupted" : exception.GetType().Name, null); }
    }

    /// <summary>Writes accepted input in order and counts completed writes only.</summary>
    private async Task WriteInputAsync()
    {
        try
        {
            await foreach (byte[] bytes in input.Reader.ReadAllAsync(disconnected.Token))
            {
                await WriteCountedAsync(bytes);
            }
            process.CloseInput();
        }
        catch (Exception exception) when (exception is IOException or OperationCanceledException or ObjectDisposedException)
        { if (!disconnected.IsCancellationRequested) error = "InputWriteFailed"; }
    }

    /// <summary>Feeds an explicitly requested file without reading it into memory or creating a copy.</summary>
    /// <param name="path">Explicit filesystem location.</param>
    private async Task FeedFileAsync(string path)
    {
        try
        {
            await using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, Protocol.BlockSize, true);
            byte[] buffer = new byte[Protocol.BlockSize]; int count;
            while ((count = await file.ReadAsync(buffer, disconnected.Token)) != 0)
            {
                await WriteCountedAsync(buffer.AsMemory(0, count));
            }
            process.CloseInput();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or OperationCanceledException)
        { if (!disconnected.IsCancellationRequested) { error = "InputReadFailed"; process.Kill(); } }
    }

    /// <summary>Counts successful stream writes once; flush does not retroactively erase written bytes.</summary>
    /// <param name="bytes">Transient input block.</param>
    private async Task WriteCountedAsync(ReadOnlyMemory<byte> bytes)
    {
        await process.Input.WriteAsync(bytes, disconnected.Token);
        Interlocked.Add(ref stdinBytes, bytes.Length);
        await process.Input.FlushAsync(disconnected.Token);
    }

    /// <summary>Waits for exit and both stream readers, including blocks pending consumption.</summary>
    private async Task RunAsync()
    {
        var readers = new[] { DrainAsync(process.Output, Transport == "Pty" ? "terminal" : "stdout"), DrainAsync(process.Error, "stderr") };
        try { await process.WaitAsync(disconnected.Token); exitCode = process.ExitCode; }
        catch (OperationCanceledException) { process.Kill(); }
        finally
        {
            deadline.CancelAfter(Timeout.InfiniteTimeSpan);
            disconnected.CancelAfter(TimeSpan.FromSeconds(drainTimeoutSeconds));
            await Task.WhenAll(readers);
            disconnected.Cancel();
            input.Writer.TryComplete();
            try { await writer; } catch (Exception exception) { error ??= exception.GetType().Name; }
            watch.Stop(); output.Writer.TryComplete();
        }
    }

    /// <summary>Returns at most one block without an unbounded event backlog.</summary>
    internal async Task<OutputBlock?> NextAsync()
    {
        if (output.Reader.TryRead(out var block)) return block;
        using var timeout = new CancellationTokenSource(100);
        try { if (await output.Reader.WaitToReadAsync(timeout.Token) && output.Reader.TryRead(out block)) return block; }
        catch (OperationCanceledException) { }
        return null;
    }

    /// <summary>Accepts one input block, returning false when the bounded writer is full.</summary>
    /// <param name="bytes">Exact byte block provided by the caller.</param>
    internal bool TryWrite(byte[] bytes) => input.Writer.TryWrite(bytes);
    /// <summary>Queues EOF after previously accepted writes.</summary>
    internal void CompleteInput() => input.Writer.TryComplete();
    /// <summary>Cancels only this owned process tree.</summary>
    internal void Cancel() { cancelled = true; process.Kill(); }
    /// <summary>Resizes an explicitly requested terminal.</summary>
    /// <param name="columns">Terminal width in columns.</param>
/// <param name="rows">Terminal height in rows.</param>
    internal void Resize(int columns, int rows) {
        InvocationRequest.ValidateDimensions(columns, rows);
        if (process is not ITerminalChannel { SupportsResize: true } terminal) throw new InvalidOperationException("TerminalResizeUnavailable");
        terminal.Resize(columns, rows);
    }
    /// <summary>Reports counters and native state without retaining native content.</summary>
    internal object Snapshot() => new {
        ProcessId, Transport, ReadBlockBytes = readBlockBytes, ExitCode = exitCode,
        Outcome = timedOut ? "Timeout" : cancelled ? "Cancelled" : error != null || !successCodes.Contains(exitCode ?? -1) ? "Failed" : "Success",
        StdinBytesWritten = Interlocked.Read(ref stdinBytes),
        StdoutBytesRead = Transport == "Pty" ? (long?)null : Interlocked.Read(ref stdoutBytes),
        StderrBytesRead = Transport == "Pty" ? (long?)null : Interlocked.Read(ref stderrBytes),
        TerminalBytesRead = Transport == "Pty" ? (long?)Interlocked.Read(ref stdoutBytes) : null,
        ElapsedMs = watch.Elapsed.TotalMilliseconds,
        SourceComplete = IsCompleted && !timedOut && !cancelled && error == null,
        Error = error, State = IsCompleted ? "Finalized" : "Running",
        EffectStatus = exitCode.HasValue && !timedOut && !cancelled ? "Executed" : "Unknown"
    };
    /// <summary>Disconnects readers and terminates the owned child without replay.</summary>
    public async ValueTask DisposeAsync()
    {
        process.Kill(); disconnected.Cancel();
        try { await completion; } catch (OperationCanceledException) { }
        deadline.Dispose(); disconnected.Dispose(); process.Dispose();
    }
}
