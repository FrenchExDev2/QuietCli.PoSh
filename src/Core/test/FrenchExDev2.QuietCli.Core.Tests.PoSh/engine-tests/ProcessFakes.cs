using FrenchExDev2.QuietCli;

/// <summary>Independent process fixture with either a known finite output or a stream that never reaches EOF.</summary>
internal sealed class AuditProcessFactory : IProcessChannelFactory
{
    /// <summary>Number of process creations, used to reject hidden retries.</summary>
    internal int Creations { get; private set; }
    /// <summary>Whether the output source withholds EOF until cancelled.</summary>
    internal bool HoldOutput { get; init; }
    /// <summary>Produces a local stream fixture, never an operating-system process.</summary>
    /// <param name="request">Prevalidated invocation request.</param>
    /// <param name="token">Startup deadline.</param>
    public ValueTask<IProcessChannel> CreateAsync(InvocationRequest request, CancellationToken token) { token.ThrowIfCancellationRequested(); Creations++; return ValueTask.FromResult<IProcessChannel>(new AuditProcess(HoldOutput)); }
}

/// <summary>Owned in-memory process-channel fixture with an independently known byte count.</summary>
/// <param name="holdOutput">If true, stdout cannot complete normally.</param>
internal sealed class AuditProcess(bool holdOutput) : IProcessChannel
{
    /// <summary>Private input sink.</summary>
    public Stream Input { get; } = new MemoryStream();
    /// <summary>Three known bytes or a deliberately unterminated source.</summary>
    public Stream Output { get; } = holdOutput ? new AwaitCancellationStream() : new MemoryStream(new byte[] { 1, 2, 3 });
    /// <summary>No stderr data.</summary>
    public Stream Error => Stream.Null;
    /// <summary>No operating-system process is created.</summary>
    public int Id => 0;
    /// <summary>The synthetic principal process has already exited successfully.</summary>
    public int? ExitCode => 0;
    /// <summary>The output stream can remain open after principal exit.</summary>
    public bool HasExited => true;
    /// <summary>Waits for an already completed fixture.</summary>
    /// <param name="token">Cancellation is irrelevant for the completed principal.</param>
    public Task WaitAsync(CancellationToken token) => Task.CompletedTask;
    /// <summary>Closes the private input sink.</summary>
    public void CloseInput() => Input.Dispose();
    /// <summary>The fixture has no terminal capability.</summary>
    /// <param name="columns">Requested width.</param>
    /// <param name="rows">Requested height.</param>
    public void Resize(int columns, int rows) => throw new NotSupportedException();
    /// <summary>No operating-system tree exists to terminate.</summary>
    public void Kill() { }
    /// <summary>Releases fixture streams.</summary>
    public void Dispose() { Input.Dispose(); Output.Dispose(); }
}

/// <summary>Stream whose async read ends only by cancellation, never by EOF.</summary>
internal sealed class AwaitCancellationStream : Stream
{
    /// <summary>Asynchronous reading is supported.</summary>
    public override bool CanRead => true;
    /// <summary>Seeking is unsupported.</summary>
    public override bool CanSeek => false;
    /// <summary>Writing is unsupported.</summary>
    public override bool CanWrite => false;
    /// <summary>No finite length exists.</summary>
    public override long Length => throw new NotSupportedException();
    /// <summary>No position exists.</summary>
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
    /// <summary>Waits for the caller's cancellation token.</summary>
    /// <param name="buffer">Unused destination.</param>
    /// <param name="cancellationToken">Required bounded drain cancellation.</param>
    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default) { await Task.Delay(Timeout.Infinite, cancellationToken); return 0; }
    /// <summary>Synchronous reads are forbidden by this fixture.</summary>
    /// <param name="buffer">Unused destination.</param>
    /// <param name="offset">Unused offset.</param>
    /// <param name="count">Unused length.</param>
    public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    /// <summary>No buffered writes exist.</summary>
    public override void Flush() { }
    /// <summary>Seeking is unsupported.</summary>
    /// <param name="offset">Unused position.</param>
    /// <param name="origin">Unused origin.</param>
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    /// <summary>Resizing is unsupported.</summary>
    /// <param name="value">Unused length.</param>
    public override void SetLength(long value) => throw new NotSupportedException();
    /// <summary>Writing is unsupported.</summary>
    /// <param name="buffer">Unused source.</param>
    /// <param name="offset">Unused offset.</param>
    /// <param name="count">Unused length.</param>
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
