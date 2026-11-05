namespace FrenchExDev2.QuietCli;

/// <summary>Accumulates safe telemetry only; never receives caller business objects or native output.</summary>
internal sealed class GainAccumulator
{
    /// <summary>Last observation of each native source, matching caller identity comparisons.</summary>
    private readonly Dictionary<string, SourceMeasurement> sources = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Case-sensitive business grouping, ordered in the host culture.</summary>
    private readonly SortedDictionary<string, int[]> groups = new(StringComparer.CurrentCulture);
    /// <summary>Selected root invocation identities.</summary>
    private readonly HashSet<string> rootIds = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Roots with actual deliveries.</summary>
    private readonly HashSet<string> deliveryIds = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Validated grouping dimension.</summary>
    private readonly string groupBy;
    /// <summary>Selected invocation and root counts.</summary>
    private int invocations, roots, deliveries;
    /// <summary>Total actual root delivery bytes.</summary>
    private long delivered;
    /// <summary>Whether every selected root analysis and delivery size is known.</summary>
    private bool analysesComplete = true, deliverySizesKnown = true;

    /// <summary>Validates grouping before scanning any database.</summary>
    /// <param name="groupBy">Context, Command, Session, Module, Role or Outcome.</param>
    internal GainAccumulator(string groupBy)
    {
        this.groupBy = groupBy.ToUpperInvariant();
        if (this.groupBy is not ("CONTEXT" or "COMMAND" or "SESSION" or "MODULE" or "ROLE" or "OUTCOME")) throw new InvalidDataException("InvalidGainGrouping");
    }

    /// <summary>Consumes a projected invocation or delivery, without keeping the original event.</summary>
    /// <param name="row">Closed telemetry DTO.</param>
    internal void Add(MeasurementRecord row)
    {
        bool root = string.IsNullOrEmpty(row.ParentId);
        if (row.DeliveryId != null)
        {
            if (root) { deliveries++; deliveryIds.Add(row.InvocationId); deliverySizesKnown &= row.OutputBytes.HasValue; delivered = checked(delivered + (row.OutputBytes ?? 0)); }
            return;
        }
        invocations++;
        if (root) { roots++; rootIds.Add(row.InvocationId); analysesComplete &= row.Completeness?.Analysis == true; }
        foreach (var source in row.Sources ?? []) sources[source.InvocationId] = source;
        string key = groupBy switch {
            "CONTEXT" => row.Context ?? "(generic)", "COMMAND" => row.Command ?? "", "SESSION" => row.SessionId ?? "",
            "MODULE" => string.IsNullOrEmpty(row.HandlerId) ? "(direct)" : row.HandlerId, "ROLE" => row.Role ?? "", _ => row.Outcome ?? ""
        };
        if (!groups.TryGetValue(key, out var counts)) groups.Add(key, counts = new int[3]);
        counts[0]++; if (root) counts[1]++;
        if (!string.Equals(row.Outcome, "Success", StringComparison.OrdinalIgnoreCase)) counts[2]++;
    }

    /// <summary>Builds the same report counters without retaining or transferring source events.</summary>
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
        long? deliveryBytes = deliveries > 0 && deliverySizesKnown ? delivered : null;
        long? reduction = incomplete == 0 && complete && roots > 0 && analysesComplete && deliverySizesKnown && deliveries == roots && deliveryIds.SetEquals(rootIds) ? checked(business - delivered) : null;
        var summary = new { Complete = complete, Invocations = invocations, Roots = roots, UniqueNativeSources = sources.Count, StdinBytesWritten = stdin, BusinessBytesObserved = business, AuxiliaryBytesObserved = auxiliary, IncompleteSources = incomplete, RootDeliveryBytes = deliveryBytes, ReductionBytes = reduction, NativeTokens = (long?)null, Comparability = "Observed effective native business output; source and delivered object may be projected. Context subtotals are not additive." };
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