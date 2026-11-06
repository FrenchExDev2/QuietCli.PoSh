namespace FrenchExDev2.QuietCli;

/// <summary>Accumulates safe telemetry only; never receives caller business objects or native output.</summary>
internal sealed class GainAccumulator
{
    /// <summary>Last observation of each native source, matching caller identity comparisons.</summary>
    private readonly Dictionary<string, SourceMeasurement> sources = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Case-sensitive business grouping, ordered in the host culture.</summary>
    private readonly SortedDictionary<string, int[]> groups = new(StringComparer.CurrentCulture);
    /// <summary>Native sources associated with actual root business deliveries only.</summary>
    private readonly Dictionary<string, SourceMeasurement> deliveredSources = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Selected business root identities, including calls without serialization.</summary>
    private readonly HashSet<string> rootIds = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Roots with actual deliveries.</summary>
    private readonly HashSet<string> deliveryIds = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Validated grouping dimension.</summary>
    private readonly string groupBy;
    /// <summary>Selected invocation and root counts.</summary>
    private int invocations, roots, deliveries;
    /// <summary>Total actual root delivery bytes.</summary>
    private long delivered;
    /// <summary>Whether all actual business deliveries have complete source snapshots and known sizes.</summary>
    private bool deliveriesComplete = true, deliverySizesKnown = true;
    /// <summary>Root-only allocation totals avoid counting a nested invocation twice.</summary>
    private long allocated, completeAllocated;
    /// <summary>Allocation coverage; missing historical samples remain unknown.</summary>
    private int measuredRoots, completeSamples, measuredCompleteSamples;
    /// <summary>Explicit thread-change counts explain unknown allocation totals.</summary>
    private int allocationThreadChanges, completeThreadChanges;
    /// <summary>Measured delivery counts and totals separated by encoding and implementation version.</summary>
    private readonly Dictionary<(string Profile, string Version), (long Tokens, int Deliveries)> tokenTotals = new();

    /// <summary>Validates grouping before scanning any database.</summary>
    /// <param name="groupBy">Context, Command, Session, Module, Role or Outcome.</param>
    internal GainAccumulator(string groupBy)
    {
        this.groupBy = groupBy.ToUpperInvariant();
        if (this.groupBy is not ("CONTEXT" or "COMMAND" or "SESSION" or "MODULE" or "ROLE" or "OUTCOME")) throw new InvalidDataException("InvalidGainGrouping");
    }

    /// <summary>Consumes a projected invocation or delivery, without keeping the original event.</summary>
    /// <param name="row">Closed telemetry DTO.</param>
    /// <param name="tokenMeasurements">Additional persisted encoding measurements for this delivery.</param>
    internal void Add(MeasurementRecord row, TokenMeasurement[]? tokenMeasurements = null)
    {
        bool root = string.IsNullOrEmpty(row.ParentId);
        bool businessRole = row.Role == null || string.Equals(row.Role, "Business", StringComparison.OrdinalIgnoreCase);
        if (row.DeliveryId != null)
        {
            if (root && businessRole)
            {
                deliveries++; deliveryIds.Add(row.InvocationId);
                var measured = new Dictionary<(string, string), long>();
                if (row.OutputTokens.HasValue && row.TokenProfile is "o200k_base" or "cl100k_base" && !string.IsNullOrEmpty(row.TokenVersion))
                    measured[(row.TokenProfile, row.TokenVersion)] = row.OutputTokens.Value;
                foreach (var token in tokenMeasurements ?? row.TokenMeasurements ?? []) measured[(token.TokenProfile, token.TokenVersion)] = token.OutputTokens;
                foreach (var entry in measured) {
                    tokenTotals.TryGetValue(entry.Key, out var total);
                    tokenTotals[entry.Key] = (checked(total.Tokens + entry.Value), total.Deliveries + 1);
                }
                deliverySizesKnown &= row.OutputBytes.HasValue;
                delivered = checked(delivered + (row.OutputBytes ?? 0));
                deliveriesComplete &= row.Completeness is { Source: true, Analysis: true } && row.Sources != null;
                foreach (var source in row.Sources ?? [])
                {
                    if (string.Equals(source.Role, "Business", StringComparison.OrdinalIgnoreCase)) deliveriesComplete &= source.Complete && MeasurementTelemetry.SourceBytes(source).HasValue;
                    deliveredSources[source.InvocationId] = source;
                }
            }
            return;
        }
        invocations++;
        if (root)
        {
            roots++; if (businessRole) rootIds.Add(row.InvocationId);
            if (row.Allocation?.AllocatedBytes is { } bytes) { measuredRoots++; allocated = checked(allocated + bytes); }
            if (row.Allocation?.Status == "ThreadChanged") allocationThreadChanges++;
            if (row.CompleteAllocation is { } sample)
            {
                completeSamples++;
                if (sample.Status == "ThreadChanged") completeThreadChanges++;
                if (sample.AllocatedBytes is { } completeBytes) { measuredCompleteSamples++; completeAllocated = checked(completeAllocated + completeBytes); }
            }
        }
        foreach (var source in row.Sources ?? []) sources[source.InvocationId] = source;
        string key = groupBy switch {
            "CONTEXT" => row.Context ?? "(generic)", "COMMAND" => row.Command ?? "", "SESSION" => row.SessionId ?? "",
            "MODULE" => string.IsNullOrEmpty(row.HandlerId) ? "(direct)" : row.HandlerId, "ROLE" => row.Role ?? "", _ => row.Outcome ?? ""
        };
        if (!groups.TryGetValue(key, out var counts)) groups.Add(key, counts = new int[3]);
        counts[0]++; if (root) counts[1]++;
        if (!string.Equals(row.Outcome, "Success", StringComparison.OrdinalIgnoreCase)) counts[2]++;
    }

    /// <summary>Separates all observed work, actual serialization gains and root allocation costs.</summary>
    /// <param name="complete">Whether the event budget included the entire selected range.</param>
    internal GainReport Build(bool complete)
    {
        long business = 0, auxiliary = 0, stdin = 0; int incomplete = 0;
        foreach (var source in sources.Values)
        {
            long bytes = source.TerminalBytesRead ?? checked((source.StdoutBytesRead ?? 0) + (source.StderrBytesRead ?? 0));
            stdin = checked(stdin + (source.StdinBytesWritten ?? 0));
            if (string.Equals(source.Role, "Business", StringComparison.OrdinalIgnoreCase)) business = checked(business + bytes); else auxiliary = checked(auxiliary + bytes);
            if (!source.Complete) incomplete++;
        }
        long comparedBusiness = 0; bool comparedSourcesKnown = true;
        foreach (var source in deliveredSources.Values)
        {
            if (!string.Equals(source.Role, "Business", StringComparison.OrdinalIgnoreCase)) continue;
            long? bytes = MeasurementTelemetry.SourceBytes(source);
            comparedSourcesKnown &= source.Complete && bytes.HasValue;
            comparedBusiness = checked(comparedBusiness + (bytes ?? 0));
        }
        long? deliveryBytes = deliveries > 0 && deliverySizesKnown ? delivered : null;
        long? reduction = complete && deliveries > 0 && deliveriesComplete && deliverySizesKnown && comparedSourcesKnown ? checked(comparedBusiness - delivered) : null;
        var summary = new {
            Complete = complete, Invocations = invocations, Roots = roots, UniqueNativeSources = sources.Count,
            StdinBytesWritten = stdin, BusinessBytesObserved = business, AuxiliaryBytesObserved = auxiliary, IncompleteSources = incomplete,
            RootDeliveries = deliveries, SerializedRoots = deliveryIds.Count, UnserializedRoots = rootIds.Count(id => !deliveryIds.Contains(id)),
            SerializedBusinessBytesObserved = comparedBusiness, RootDeliveryBytes = deliveryBytes, ReductionBytes = reduction,
            AllocationMeasuredRoots = measuredRoots, RootInvocationAllocatedBytes = complete && roots > 0 && measuredRoots == roots ? (long?)allocated : null,
            AllocationThreadChangedRoots = allocationThreadChanges,
            RootCompleteAllocationSamples = completeSamples, RootCompleteAllocationMeasuredSamples = measuredCompleteSamples,
            RootCompleteAllocationThreadChanges = completeThreadChanges,
            RootCompleteAllocatedBytes = complete && completeSamples > 0 && completeSamples == measuredCompleteSamples ? (long?)completeAllocated : null,
            AllocationScope = "CallerThread; Complete is included in invocation allocations; nested invocations are not added again. Not retained object size.",
            NativeTokens = (long?)null,
            DeliveredTokensByProfile = tokenTotals.OrderBy(item => item.Key.Profile, StringComparer.Ordinal).ThenBy(item => item.Key.Version, StringComparer.Ordinal).Select(item => new {
                TokenProfile = item.Key.Profile, TokenVersion = item.Key.Version, OutputTokens = item.Value.Tokens,
                MeasuredDeliveries = item.Value.Deliveries, UnmeasuredDeliveries = deliveries - item.Value.Deliveries,
                CoverageComplete = complete && item.Value.Deliveries == deliveries
            }).ToArray(),
            Comparability = "Root business delivery records only; associated native sources deduplicated once. Identical representations reuse their delivery identity; historical records are not retroactively deduplicated. Object-only work is observed separately. Context subtotals are not additive."
        };
        return new GainReport(summary, groups.Select(group => new GainGroup(group.Key, group.Value[0], group.Value[1], group.Value[2])).ToArray());
    }
}

/// <summary>Small grouped counter record, never an event payload.</summary>
/// <param name="Key">Business group key.</param>
/// <param name="Invocations">Selected invocations.</param>
/// <param name="Roots">Selected roots.</param>
/// <param name="Failures">Selected non-success outcomes.</param>
internal sealed record GainGroup(string Key, int Invocations, int Roots, int Failures);
/// <summary>Completed aggregation, temporarily retained only while its group pages are delivered.</summary>
/// <param name="Summary">Aggregate counters.</param>
/// <param name="Groups">Aggregate groups, not original telemetry rows.</param>
internal sealed record GainReport(object Summary, GainGroup[] Groups);
