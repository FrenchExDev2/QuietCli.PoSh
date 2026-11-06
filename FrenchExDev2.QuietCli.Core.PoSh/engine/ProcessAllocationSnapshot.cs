namespace FrenchExDev2.QuietCli;

/// <summary>Explicit process-wide diagnostic snapshot, never an invocation or business-object size.</summary>
/// <param name="ProcessId">Process whose managed allocation counter was sampled.</param>
/// <param name="AllocatedBytes">Cumulative managed allocations since process startup.</param>
/// <param name="Precise">Whether the expensive precise GC counter was requested explicitly.</param>
/// <param name="SampledAtUnixMs">UTC sample time for correlating independent processes.</param>
public sealed record ProcessAllocationSnapshot(int ProcessId, long AllocatedBytes, bool Precise, long SampledAtUnixMs)
{
    /// <summary>All managed threads are included; concurrent unrelated work cannot be attributed to an invocation.</summary>
    public string Scope => "ProcessWideManagedAllocations";
    /// <summary>Native allocations are excluded by the GC counter.</summary>
    public bool IncludesNativeAllocations => false;
    /// <summary>Captures only counters; never enumerates caller objects or forces garbage collection.</summary>
    /// <param name="precise">Explicit opt-in to the higher-cost exact process counter.</param>
    public static ProcessAllocationSnapshot Capture(bool precise = false) => new(Environment.ProcessId, GC.GetTotalAllocatedBytes(precise), precise, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
}
