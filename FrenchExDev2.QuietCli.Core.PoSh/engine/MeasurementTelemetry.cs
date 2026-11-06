using System.Collections;

namespace FrenchExDev2.QuietCli;

/// <summary>Caller-local telemetry projection and comparison, with no access to business Data.</summary>
public static class MeasurementTelemetry
{
    /// <summary>Projects only closed execution and diagnostic fields, without PowerShell field loops.</summary>
    /// <param name="fields">Explicit identity, execution, completeness, source and diagnostic metadata; never a result.</param>
    /// <param name="adapt">Caller-thread adapter for PowerShell metadata property bags.</param>
    public static IDictionary Project(IDictionary fields, Func<object, IDictionary> adapt)
    {
        var result = new Hashtable(StringComparer.Ordinal);
        foreach (DictionaryEntry field in fields) result.Add(field.Key, field.Value);
        var execution = Map(fields["Execution"]!, adapt);
        var projected = Select(execution, ["State", "ElapsedMs", "CallbackMs", "Children", "EffectStatus"]);
        projected["Native"] = execution["Native"] is { } native
            ? Select(Map(native, adapt), ["ProcessId", "Transport", "ReadBlockBytes", "ExitCode", "Outcome", "StdinBytesWritten", "StdoutBytesRead", "StderrBytesRead", "TerminalBytesRead", "ElapsedMs", "SourceComplete", "Error", "State", "EffectStatus"])
            : null;
        var issues = new List<object>();
        foreach (var item in (IEnumerable)execution["Issues"]!)
        {
            var issue = Map(item, adapt);
            var copy = Select(issue, ["InvocationId", "Outcome", "EffectStatus"]);
            copy["Error"] = Errors(issue["Error"], adapt);
            issues.Add(copy);
        }
        projected["Issues"] = issues.ToArray();
        result["Execution"] = projected;
        result["CallbackMs"] = execution["CallbackMs"];
        result["Error"] = Errors(fields["Error"], adapt);
        return result;
    }

    /// <summary>Compares actual serialized bytes with unique native business sources, never object memory.</summary>
    /// <param name="sources">Caller-local source metadata only.</param>
    /// <param name="completeness">Source and analysis flags.</param>
    /// <param name="outputBytes">UTF-8 bytes of the actual delivery, including its envelope.</param>
    /// <param name="adapt">Caller-thread metadata adapter.</param>
    public static long? Reduction(IEnumerable sources, object completeness, long outputBytes, Func<object, IDictionary> adapt)
    {
        if (outputBytes < 0) throw new ArgumentOutOfRangeException(nameof(outputBytes));
        var flags = ClosedRecord.Read<CompletenessMeasurement>(completeness, adapt);
        if (!flags.Source || !flags.Analysis) return null;
        var unique = new Dictionary<string, SourceMeasurement>(StringComparer.OrdinalIgnoreCase);
        foreach (var source in sources) { var item = ClosedRecord.Read<SourceMeasurement>(source, adapt); unique[item.InvocationId] = item; }
        long bytes = 0;
        foreach (var source in unique.Values)
        {
            if (!string.Equals(source.Role, "Business", StringComparison.OrdinalIgnoreCase)) continue;
            if (!source.Complete || SourceBytes(source) is not { } size) return null;
            bytes = checked(bytes + size);
        }
        return checked(bytes - outputBytes);
    }

    /// <summary>Counts a merged terminal or both pipe streams; missing counters remain unknown.</summary>
    /// <param name="source">Closed source metadata.</param>
    internal static long? SourceBytes(SourceMeasurement source) => source.TerminalBytesRead
        ?? (source.StdoutBytesRead.HasValue && source.StderrBytesRead.HasValue ? checked(source.StdoutBytesRead.Value + source.StderrBytesRead.Value) : null);

    /// <summary>Adapts metadata on the caller thread, never arbitrary business objects.</summary>
    /// <param name="value">Known metadata container.</param>
    /// <param name="adapt">PowerShell property-bag adapter.</param>
    private static IDictionary Map(object value, Func<object, IDictionary> adapt) => CallerMetadata.Unwrap(value) is IDictionary map ? map : adapt(value);

    /// <summary>Copies named scalar fields only, ignoring local diagnostic messages.</summary>
    /// <param name="source">Owned metadata map.</param>
    /// <param name="names">Closed field names.</param>
    private static Hashtable Select(IDictionary source, string[] names)
    {
        var result = new Hashtable(StringComparer.Ordinal);
        foreach (string name in names) if (source.Contains(name)) result[name] = source[name];
        return result;
    }

    /// <summary>Removes exception messages before persistence without changing local errors.</summary>
    /// <param name="errors">Local diagnostic sequence.</param>
    /// <param name="adapt">Caller-thread metadata adapter.</param>
    private static object[] Errors(object? errors, Func<object, IDictionary> adapt)
    {
        var result = new List<object>();
        if (errors is IEnumerable sequence)
            foreach (var error in sequence) result.Add(Select(Map(error, adapt), ["Code", "Phase"]));
        return result.ToArray();
    }
}
