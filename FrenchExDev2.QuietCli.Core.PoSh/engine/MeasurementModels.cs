using System.Text.Json;
using System.Text.Json.Serialization;

namespace FrenchExDev2.QuietCli;

/// <summary>Strict telemetry boundary: rejects unknown fields at every nesting level.</summary>
internal static class MeasurementModels
{
    /// <summary>Case-sensitive schema with no extension data or business-value escape hatch.</summary>
    private static readonly JsonSerializerOptions Options = new() { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 16 };

    /// <summary>Validates a telemetry record before opening SQLite. Error messages are never permitted.</summary>
    /// <param name="metadata">Invocation or delivery metadata only.</param>
    /// <param name="kind">Supported record kind.</param>
    internal static JsonElement Validate(JsonElement metadata, string kind)
    {
        if (kind is not ("invocation" or "delivery")) throw new InvalidDataException("InvalidMeasurementKind");
        MeasurementRecord record;
        try { record = JsonSerializer.Deserialize<MeasurementRecord>(metadata, Options) ?? throw new JsonException(); }
        catch (JsonException error) { throw new InvalidDataException("MeasurementSchemaRejected", error); }
        return Validate(record, kind);
    }

    /// <summary>Validates typed telemetry before producing its persisted JSON representation.</summary>
    /// <param name="record">Closed counter record.</param>
    /// <param name="kind">Invocation or delivery.</param>
    internal static JsonElement Validate(MeasurementRecord record, string kind)
    {
        if (kind is not ("invocation" or "delivery")) throw new InvalidDataException("InvalidMeasurementKind");
        Text(record.InvocationId, 128, true); Text(record.RootId, 128); Text(record.ParentId, 128); Text(record.SessionId, 128);
        Text(record.Context, 256); Text(record.Command, 256); Text(record.HandlerId, 256); Text(record.ModuleVersion, 64);
        Text(record.ModuleHash, 128); Text(record.DeliveryId, 128); Text(record.TokenVersion, 128); Text(record.TokenProfile, 64);
        if (kind == "delivery") Text(record.DeliveryId, 128, true);
        if (record.Role is not (null or "Business" or "Probe" or "Observation" or "Infrastructure")) throw new InvalidDataException("InvalidMeasurementRole");
        if (record.Outcome is not (null or "Success" or "Failed" or "Timeout" or "Cancelled" or "Unsupported")) throw new InvalidDataException("InvalidMeasurementOutcome");
        if (record.Format is not (null or "json" or "yaml")) throw new InvalidDataException("InvalidDeliveryFormat");
        if (record.Sources is { Length: > 4096 } || record.Error is { Length: > 128 } || record.Execution?.Issues is { Length: > 128 }) throw new InvalidDataException("MeasurementCardinalityLimit");
        foreach (var source in record.Sources ?? []) { Text(source.InvocationId, 128, true); Text(source.Role, 32, true); Nonnegative(source.StdinBytesWritten); Nonnegative(source.StdoutBytesRead); Nonnegative(source.StderrBytesRead); Nonnegative(source.TerminalBytesRead); }
        foreach (var error in record.Error ?? []) { Code(error.Code); Code(error.Phase); }
        foreach (var issue in record.Execution?.Issues ?? []) { Text(issue.InvocationId, 128, true); Text(issue.Outcome, 32); Text(issue.EffectStatus, 32); foreach (var error in issue.Error ?? []) { Code(error.Code); Code(error.Phase); } }
        Nonnegative(record.OutputBytes); Nonnegative(record.OutputTokens);
        Number(record.CallbackMs); Number(record.SerializationMs);
        if (record.Execution is { } execution) {
            Text(execution.State, 32); Text(execution.EffectStatus, 32); Number(execution.ElapsedMs); Number(execution.CallbackMs);
            if (execution.Native is { } native) { Text(native.State, 32); Text(native.Transport, 16); Text(native.Outcome, 32); Text(native.EffectStatus, 32); Code(native.Error); Nonnegative(native.StdinBytesWritten); Nonnegative(native.StdoutBytesRead); Nonnegative(native.StderrBytesRead); Nonnegative(native.TerminalBytesRead); Number(native.ElapsedMs); }
        }
        return JsonSerializer.SerializeToElement(record, Options);
    }

    /// <summary>Checks bounded nullable text; no arbitrary diagnostic content is accepted as a code.</summary>
    /// <param name="value">Metadata scalar.</param>
    /// <param name="limit">Maximum UTF-16 length.</param>
    /// <param name="required">Whether an empty or absent identity is invalid.</param>
    private static void Text(string? value, int limit, bool required = false) { if (value?.Length > limit || required && string.IsNullOrEmpty(value)) throw new InvalidDataException("MeasurementTextLimit"); }
    /// <summary>Checks a structured diagnostic identifier.</summary>
    /// <param name="value">A code or phase, never exception text.</param>
    private static void Code(string? value) { Text(value, 64); if (value != null && value.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('_' or '-' or '.'))) throw new InvalidDataException("InvalidDiagnosticCode"); }
    /// <summary>Checks a measured byte or token count.</summary>
    /// <param name="value">Unknown stays null.</param>
    private static void Nonnegative(long? value) { if (value < 0) throw new InvalidDataException("NegativeMeasurement"); }
    /// <summary>Checks an elapsed duration.</summary>
    /// <param name="value">Finite nonnegative milliseconds.</param>
    private static void Number(double? value) { if (value.HasValue && (!double.IsFinite(value.Value) || value < 0)) throw new InvalidDataException("InvalidMeasurementDuration"); }
}

/// <summary>Typed invocation/delivery telemetry. Contains no business payload.</summary>
/// <param name="InvocationId">Caller invocation identity.</param>
/// <param name="RootId">Root identity.</param>
/// <param name="ParentId">Optional parent identity.</param>
/// <param name="SessionId">Caller PowerShell session.</param>
/// <param name="Context">Optional caller label.</param>
/// <param name="Role">Native source role.</param>
/// <param name="Command">Executable identity, without arguments.</param>
/// <param name="Outcome">Terminal outcome.</param>
/// <param name="Execution">Numeric execution summary.</param>
/// <param name="Error">Diagnostic codes only.</param>
/// <param name="Completeness">Source and analysis completeness.</param>
/// <param name="Sources">Unique native counters.</param>
/// <param name="DeliveryId">Actual delivery identity.</param>
/// <param name="OutputBytes">Delivered bytes or null.</param>
/// <param name="OutputTokens">Actual delivery tokens or null.</param>
/// <param name="TokenProfile">Selected encoding.</param>
/// <param name="TokenVersion">Actual tokenizer assembly version.</param>
/// <param name="Format">JSON or YAML delivery.</param>
/// <param name="Truncated">Delivery omitted content.</param>
/// <param name="HandlerId">Selected module.</param>
/// <param name="ModuleVersion">Module version.</param>
/// <param name="ModuleHash">Optional module digest.</param>
/// <param name="CallbackMs">Callback elapsed milliseconds.</param>
/// <param name="SerializationMs">Delivery serialization milliseconds.</param>
internal sealed record MeasurementRecord(string InvocationId, string? RootId = null, string? ParentId = null, string? SessionId = null, string? Context = null, string? Role = null, string? Command = null, string? Outcome = null, ExecutionMeasurement? Execution = null, DiagnosticCode[]? Error = null, CompletenessMeasurement? Completeness = null, SourceMeasurement[]? Sources = null, string? DeliveryId = null, long? OutputBytes = null, long? OutputTokens = null, string? TokenProfile = null, string? TokenVersion = null, string? Format = null, bool? Truncated = null, string? HandlerId = null, string? ModuleVersion = null, string? ModuleHash = null, double? CallbackMs = null, double? SerializationMs = null);

/// <summary>Safe diagnostic information without persisted exception text.</summary>
/// <param name="Code">Stable error identifier.</param>
/// <param name="Phase">Lifecycle phase.</param>
internal sealed record DiagnosticCode(string? Code = null, string? Phase = null);
/// <summary>Completeness flags, independent from exit success.</summary>
/// <param name="Source">EOF was observed for all sources.</param>
/// <param name="Analysis">Business analysis completed.</param>
internal sealed record CompletenessMeasurement(bool Source, bool Analysis);
/// <summary>Own native source counters; unknown terminal separation stays null.</summary>
/// <param name="InvocationId">Unique source identity.</param>
/// <param name="Role">Business or auxiliary role.</param>
/// <param name="StdinBytesWritten">Completed input writes.</param>
/// <param name="StdoutBytesRead">Stdout bytes or null for PTY.</param>
/// <param name="StderrBytesRead">Stderr bytes or null for PTY.</param>
/// <param name="TerminalBytesRead">Merged terminal bytes or null for pipes.</param>
/// <param name="Complete">Source completion flag.</param>
internal sealed record SourceMeasurement(string InvocationId, string Role, long? StdinBytesWritten = null, long? StdoutBytesRead = null, long? StderrBytesRead = null, long? TerminalBytesRead = null, bool Complete = false);
/// <summary>Metadata describing a failed child without its object or exception text.</summary>
/// <param name="InvocationId">Child identity.</param>
/// <param name="Outcome">Child outcome.</param>
/// <param name="EffectStatus">Known or uncertain effect.</param>
/// <param name="Error">Safe diagnostic codes.</param>
internal sealed record ChildIssue(string InvocationId, string? Outcome = null, string? EffectStatus = null, DiagnosticCode[]? Error = null);
/// <summary>Caller execution metadata. Native is strictly typed.</summary>
/// <param name="State">Finalized lifecycle state.</param>
/// <param name="Native">Native counters when a process was requested.</param>
/// <param name="ElapsedMs">Total elapsed time.</param>
/// <param name="CallbackMs">Time spent in callbacks.</param>
/// <param name="Children">Child invocation count.</param>
/// <param name="Issues">Failed child codes.</param>
/// <param name="EffectStatus">Aggregate effect certainty.</param>
internal sealed record ExecutionMeasurement(string? State = null, NativeMeasurement? Native = null, double? ElapsedMs = null, double? CallbackMs = null, int? Children = null, ChildIssue[]? Issues = null, string? EffectStatus = null);
/// <summary>Closed schema for native state and byte counters, with no output strings.</summary>
/// <param name="ProcessId">Owned native PID.</param>
/// <param name="Transport">Pipe or PTY.</param>
/// <param name="ReadBlockBytes">Configured transient block size.</param>
/// <param name="ExitCode">Observed native exit code.</param>
/// <param name="Outcome">Execution outcome.</param>
/// <param name="StdinBytesWritten">Bytes written.</param>
/// <param name="StdoutBytesRead">Bytes read.</param>
/// <param name="StderrBytesRead">Bytes read.</param>
/// <param name="TerminalBytesRead">Merged bytes read.</param>
/// <param name="ElapsedMs">Process and drainage elapsed time.</param>
/// <param name="SourceComplete">All native streams reached EOF.</param>
/// <param name="Error">Structured code only.</param>
/// <param name="State">Lifecycle snapshot.</param>
/// <param name="EffectStatus">Execution effect certainty.</param>
internal sealed record NativeMeasurement(int? ProcessId = null, string? Transport = null, int? ReadBlockBytes = null, int? ExitCode = null, string? Outcome = null, long? StdinBytesWritten = null, long? StdoutBytesRead = null, long? StderrBytesRead = null, long? TerminalBytesRead = null, double? ElapsedMs = null, bool? SourceComplete = null, string? Error = null, string? State = null, string? EffectStatus = null);
