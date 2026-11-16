namespace FrenchExDev2.QuietCli;

/// <summary>Measures caller-thread managed allocations without walking or retaining business objects.</summary>
public sealed class AllocationMeter
{
    /// <summary>Thread owning the initial allocation counter.</summary>
    private readonly int threadId;
    /// <summary>Initial cumulative allocation counter, sampled after constructing the meter.</summary>
    private readonly long started;
    /// <summary>Stable terminal sample; repeated stops do not measure again.</summary>
    private AllocationMeasurement? measurement;

    /// <summary>Starts a thread-local interval without forcing garbage collection.</summary>
    public AllocationMeter()
    {
        threadId = Environment.CurrentManagedThreadId;
        started = GC.GetAllocatedBytesForCurrentThread();
    }

    /// <summary>Closes the interval before allocating its result; thread changes produce an unknown size.</summary>
    public AllocationMeasurement Stop()
    {
        if (measurement != null) return measurement;
        long ended = GC.GetAllocatedBytesForCurrentThread();
        int endThread = Environment.CurrentManagedThreadId;
        return measurement = new(endThread == threadId ? checked(ended - started) : null, threadId, endThread,
            endThread == threadId ? "Measured" : "ThreadChanged");
    }
}

/// <summary>Managed allocation interval, not retained object size or serialized output size.</summary>
/// <param name="AllocatedBytes">Cumulative thread allocations during the interval, or null after a thread change.</param>
/// <param name="StartThreadId">Managed thread at interval entry.</param>
/// <param name="EndThreadId">Managed thread at interval exit.</param>
/// <param name="Status">Measured or ThreadChanged.</param>
public sealed record AllocationMeasurement(long? AllocatedBytes, int StartThreadId, int EndThreadId, string Status);
