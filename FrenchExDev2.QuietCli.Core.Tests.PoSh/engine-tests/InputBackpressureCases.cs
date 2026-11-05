using FrenchExDev2.QuietCli;

/// <summary>Controlled input readiness without a native process, output data or timing threshold.</summary>
internal static class InputBackpressureCases
{
    /// <summary>Proves that an already writable input queue does not wait for unrelated output.</summary>
    internal static async Task ReadyInputDoesNotWaitForOutputAsync()
    {
        var factory = new ControlledInputFactory();
        var request = new InvocationRequest("input-readiness", "not-executed", [], Path.GetTempPath(), new System.Collections.Hashtable(), "Pipe", 120, 40, 10, 0.05, 1024, [0], true, null);
        await using var invocation = await Invocation.StartAsync(request, factory);
        if (!invocation.TryWrite([1])) throw new Exception("First input block refused");
        await factory.Process.Sink.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        for (int index = 0; index < ProtocolSpecification.QueueBlocks; index++)
            if (!invocation.TryWrite([2])) throw new Exception("Input queue capacity changed");
        if (invocation.TryWrite([3])) throw new Exception("Full input queue accepted another block");
        factory.Process.Sink.Release.TrySetResult();
        await factory.Process.Sink.Consumed.Task.WaitAsync(TimeSpan.FromSeconds(2));
        // No stdout is ever produced. The input sink has consumed every queued block.
        // Synchronous readiness is the assertion; the deadline only bounds a defective implementation.
        var next = invocation.NextAsync();
        bool alreadyReady = next.IsCompleted;
        var block = await next.WaitAsync(TimeSpan.FromSeconds(2));
        if (!alreadyReady || block != null) throw new Exception("Available stdin waited for unrelated stdout");
        invocation.CompleteInput();
    }
}

/// <summary>Creates exactly one controlled stream process without launching an executable.</summary>
internal sealed class ControlledInputFactory : IProcessChannelFactory
{
    /// <summary>Fixture whose stream gates are controlled by the assertion.</summary>
    internal ControlledInputProcess Process { get; } = new();
    /// <summary>Transfers ownership of the synthetic process.</summary>
    /// <param name="request">Validated request; no executable is launched.</param>
    /// <param name="token">Startup deadline.</param>
    public ValueTask<IProcessChannel> CreateAsync(InvocationRequest request, CancellationToken token)
    { token.ThrowIfCancellationRequested(); return ValueTask.FromResult<IProcessChannel>(Process); }
}

/// <summary>Input-only synthetic process which exits after queued EOF or cancellation.</summary>
internal sealed class ControlledInputProcess : IProcessChannel
{
    /// <summary>Principal completion, independent of native processes.</summary>
    private readonly TaskCompletionSource exited = new(TaskCreationOptions.RunContinuationsAsynchronously);
    /// <summary>Controlled input sink.</summary>
    internal ControlledInputStream Sink { get; } = new();
    /// <summary>Input stream that initially blocks its first write.</summary>
    public Stream Input => Sink;
    /// <summary>Output never produces bytes or EOF before drain cancellation.</summary>
    public Stream Output { get; } = new AwaitCancellationStream();
    /// <summary>No error output.</summary>
    public Stream Error => Stream.Null;
    /// <summary>No actual native process.</summary>
    public int Id => 0;
    /// <summary>Successful synthetic exit.</summary>
    public int? ExitCode => HasExited ? 0 : null;
    /// <summary>Whether EOF or cancellation reached the fixture.</summary>
    public bool HasExited => exited.Task.IsCompleted;
    /// <summary>Waits for controlled EOF.</summary>
    /// <param name="token">Owned cancellation token.</param>
    public Task WaitAsync(CancellationToken token) => exited.Task.WaitAsync(token);
    /// <summary>Ends the synthetic principal after all accepted writes.</summary>
    public void CloseInput() => exited.TrySetResult();
    /// <summary>Allows cleanup after any assertion failure.</summary>
    public void Kill() { Sink.Release.TrySetResult(); exited.TrySetResult(); }
    /// <summary>Releases the two owned streams.</summary>
    public void Dispose() { Sink.Dispose(); Output.Dispose(); }
}

/// <summary>Input sink with explicit first-write and fully-consumed synchronization gates.</summary>
internal sealed class ControlledInputStream : MemoryStream
{
    /// <summary>Number of accepted blocks observed by the sink.</summary>
    private int count;
    /// <summary>Signals that the first block left the bounded input queue.</summary>
    internal TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    /// <summary>Allows the writer to consume the remaining queue.</summary>
    internal TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    /// <summary>Signals consumption of the first block plus every queue slot.</summary>
    internal TaskCompletionSource Consumed { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    /// <summary>Counts known blocks without retaining their contents.</summary>
    /// <param name="buffer">Transient input block, deliberately not saved.</param>
    /// <param name="cancellationToken">Owned writer cancellation.</param>
    public override async ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken cancellationToken = default)
    {
        Entered.TrySetResult();
        await Release.Task.WaitAsync(cancellationToken);
        if (Interlocked.Increment(ref count) == ProtocolSpecification.QueueBlocks + 1) Consumed.TrySetResult();
    }
}
