using System.Collections;
using System.Globalization;
using System.Reflection;
using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>Closed metadata operations; arbitrary caller objects are never accepted as engine requests.</summary>
public sealed class LocalMetadataRequest
{
    /// <summary>Supported metadata action.</summary>
    internal string Action { get; }
    /// <summary>Detached, validated native start options.</summary>
    internal InvocationRequest? Start { get; }
    /// <summary>Closed persistence record, with no business field.</summary>
    internal MeasurementRecord? Measurement { get; }
    /// <summary>Invocation or delivery storage kind.</summary>
    internal string? Kind { get; }
    /// <summary>Closed report selection.</summary>
    internal GainSelection? Selection { get; }
    /// <summary>Aggregate continuation identity.</summary>
    internal string? ReportId { get; }
    /// <summary>Aggregate group offset.</summary>
    internal int After { get; }
    /// <summary>Explicit privacy scrub confirmation.</summary>
    internal bool Confirmed { get; }
    /// <summary>Explicit high-cost precision opt-in for process diagnostics.</summary>
    internal bool Precise { get; }

    /// <summary>Maps only explicit action fields and closed nested telemetry records.</summary>
    /// <param name="header">Facade metadata header, never a result or business object.</param>
    /// <param name="adapt">Caller-thread adaptation of PowerShell metadata property bags.</param>
    internal LocalMetadataRequest(IDictionary header, Func<object, IDictionary> adapt)
    {
        if (header.Count > 32) throw new InvalidDataException("ControlFrameTooLarge");
        Action = (string)header["Action"]!;
        var fields = new Hashtable(StringComparer.Ordinal);
        foreach (DictionaryEntry item in header)
            if ((string)item.Key is not ("Action" or "Version" or "RequestId")) fields.Add(item.Key, item.Value);
        switch (Action)
        {
            case "hello": case "shutdown": ClosedRecord.Check(fields, []); break;
            case "allocations":
                ClosedRecord.Check(fields, ["Precise"]);
                if (fields["Precise"] is not bool) throw new InvalidDataException("InvalidAllocationPrecision");
                Precise = (bool)fields["Precise"]!; break;
            case "start":
                Start = ClosedRecord.Read<StartOptions>(fields, adapt).ToInvocation(); break;
            case "save":
                ClosedRecord.Check(fields, ["Kind", "Metadata"]);
                Kind = (string)fields["Kind"]!;
                Measurement = ClosedRecord.Read<MeasurementRecord>(fields["Metadata"]!, adapt); break;
            case "gain": Selection = ClosedRecord.Read<GainSelection>(fields, adapt); break;
            case "gain-poll": case "gain-next": case "gain-release":
                ClosedRecord.Check(fields, Action == "gain-next" ? ["ReportId", "After"] : ["ReportId"]);
                ReportId = (string)fields["ReportId"]!;
                if (string.IsNullOrEmpty(ReportId) || ReportId.Length > 128) throw new InvalidDataException("InvalidReportIdentity");
                After = fields.Contains("After") ? Convert.ToInt32(fields["After"], CultureInfo.InvariantCulture) : 0; break;
            case "scrub": ClosedRecord.Check(fields, ["Confirmed"]); Confirmed = fields["Confirmed"] is true; break;
            default: throw new InvalidDataException("UnknownMetadataAction");
        }
    }
}

/// <summary>Schema-driven constructor mapping; never reflects properties on arbitrary caller values.</summary>
internal static class ClosedRecord
{
    /// <summary>Constructor metadata is shared across records, never caller values.</summary>
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<Type, (ConstructorInfo Constructor, ParameterInfo[] Parameters, HashSet<string> Fields)> plans = new();
    /// <summary>Rejects unknown keys, including Data and diagnostic Message fields.</summary>
    /// <param name="map">Metadata field map.</param>
    /// <param name="names">Case-sensitive permitted fields.</param>
    internal static void Check(IDictionary map, string[] names)
    {
        var allowed = new HashSet<string>(names, StringComparer.Ordinal);
        foreach (var key in map.Keys) if (key is not string name || !allowed.Contains(name)) throw new InvalidDataException("MeasurementSchemaRejected");
    }

    /// <summary>Builds a schema record using its named constructor, recursively validating every nested field.</summary>
    /// <typeparam name="T">Closed metadata type.</typeparam>
    /// <param name="value">Dictionary or caller-adapted property bag.</param>
    /// <param name="adapt">Synchronous PowerShell adapter.</param>
    internal static T Read<T>(object value, Func<object, IDictionary> adapt) => (T)Read(typeof(T), value, adapt)!;

    /// <summary>Reads only schema-declared containers and primitive values.</summary>
    /// <param name="type">Expected closed type.</param>
    /// <param name="value">Source field.</param>
    /// <param name="adapt">Caller property-bag adapter.</param>
    private static object? Read(Type type, object? value, Func<object, IDictionary> adapt)
    {
        value = CallerMetadata.Unwrap(value);
        Type? nullable = Nullable.GetUnderlyingType(type);
        if (value == null) return type.IsValueType && nullable == null ? throw new InvalidDataException("MeasurementSchemaRejected") : null;
        if (nullable != null) return Read(nullable, value, adapt);
        if (type == typeof(AllocationMeasurement) && value is AllocationMeasurement allocation) return allocation;
        if (type == typeof(string)) return value is string text ? text : throw new InvalidDataException("MeasurementSchemaRejected");
        if (type.IsPrimitive || type == typeof(decimal))
        {
            if (type == typeof(bool) && value is not bool || type != typeof(bool) && value is bool) throw new InvalidDataException("MeasurementSchemaRejected");
            if ((type == typeof(int) || type == typeof(long)) && value is not (byte or sbyte or short or ushort or int or uint or long or ulong)) throw new InvalidDataException("MeasurementSchemaRejected");
            if (value is not ValueType) throw new InvalidDataException("MeasurementSchemaRejected");
            return Convert.ChangeType(value, type, CultureInfo.InvariantCulture);
        }
        if (type.IsArray)
        {
            if (value is string || value is not IEnumerable sequence) throw new InvalidDataException("MeasurementSchemaRejected");
            var items = new List<object?>();
            foreach (var item in sequence) { if (items.Count == (type.GetElementType() == typeof(string) || type.GetElementType() == typeof(int) ? Protocol.HeaderLimit / 2 : 4096)) throw new InvalidDataException("MeasurementCardinalityLimit"); items.Add(Read(type.GetElementType()!, item, adapt)); }
            var result = Array.CreateInstance(type.GetElementType()!, items.Count);
            for (int index = 0; index < items.Count; index++) result.SetValue(items[index], index);
            return result;
        }
        if (type == typeof(IDictionary))
        {
            if (value is not IDictionary environment) throw new InvalidDataException("InvalidEnvironment");
            var result = new Hashtable(StringComparer.Ordinal);
            foreach (DictionaryEntry entry in environment)
            {
                if (entry.Key is not string || CallerMetadata.Unwrap(entry.Value) is not (null or string)) throw new InvalidDataException("InvalidEnvironment");
                result.Add(entry.Key, CallerMetadata.Unwrap(entry.Value));
            }
            return result;
        }
        var map = value as IDictionary ?? adapt(value);
        var plan = plans.GetOrAdd(type, expected => {
            var constructor = expected.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).OrderByDescending(item => item.GetParameters().Length).First();
            var parameters = constructor.GetParameters();
            return (constructor, parameters, new HashSet<string>(parameters.Select(item => item.Name!), StringComparer.Ordinal));
        });
        foreach (var key in map.Keys) if (key is not string name || !plan.Fields.Contains(name)) throw new InvalidDataException("MeasurementSchemaRejected");
        var arguments = plan.Parameters.Select(item => map.Contains(item.Name!) ? Read(item.ParameterType, map[item.Name!], adapt) : item.HasDefaultValue ? item.DefaultValue : item.ParameterType.IsValueType ? Activator.CreateInstance(item.ParameterType) : null).ToArray();
        return plan.Constructor.Invoke(arguments);
    }
}

/// <summary>Closed start header schema independent of the native request's internal field names.</summary>
/// <param name="InvocationId">Caller invocation identity.</param>
/// <param name="FilePath">Executable.</param>
/// <param name="ArgumentList">Exact argument vector.</param>
/// <param name="WorkingDirectory">Native directory.</param>
/// <param name="Environment">String/null environment overrides.</param>
/// <param name="Transport">Pipe or Pty.</param>
/// <param name="Columns">Terminal width.</param>
/// <param name="Rows">Terminal height.</param>
/// <param name="TimeoutSeconds">Execution deadline.</param>
/// <param name="SuccessExitCodes">Accepted exits.</param>
/// <param name="KeepInputOpen">Interactive input.</param>
/// <param name="InputPath">Optional input file.</param>
/// <param name="ReadBlockBytes">Native block size.</param>
/// <param name="DrainTimeoutSeconds">Drain deadline.</param>
internal sealed record StartOptions(string InvocationId, string FilePath, string[] ArgumentList, string WorkingDirectory, IDictionary Environment, string Transport, int Columns, int Rows, double TimeoutSeconds, int[] SuccessExitCodes, bool KeepInputOpen, string? InputPath = null, int? ReadBlockBytes = null, double DrainTimeoutSeconds = 30)
{
    /// <summary>Applies the same validation as the isolated JSON transport before any process exists.</summary>
    internal InvocationRequest ToInvocation() => new InvocationRequest(InvocationId, FilePath, ArgumentList, WorkingDirectory, Environment, Transport, Columns, Rows, TimeoutSeconds, DrainTimeoutSeconds, ReadBlockBytes ?? Protocol.BlockSize, SuccessExitCodes, KeepInputOpen, InputPath).Validated();
}

/// <summary>Closed aggregate filters, independent of JSON request lifetime.</summary>
/// <param name="From">Inclusive Unix milliseconds.</param>
/// <param name="To">Exclusive Unix milliseconds.</param>
/// <param name="Context">Named context or null.</param>
/// <param name="Generic">Only context-free events.</param>
/// <param name="SessionId">Optional session.</param>
/// <param name="ModuleId">Optional business module.</param>
/// <param name="GroupBy">Aggregate dimension.</param>
/// <param name="MaxEvents">Explicit event budget.</param>
internal sealed record GainSelection(long From, long To, string? Context = null, bool Generic = false, string? SessionId = null, string? ModuleId = null, string GroupBy = "Context", int MaxEvents = 10000)
{
    /// <summary>Reads the same schema from an isolated control packet.</summary>
    /// <param name="request">Transport metadata.</param>
    internal static GainSelection Parse(JsonElement request) => request.Deserialize<GainSelection>() ?? throw new InvalidDataException("InvalidGainSelection");
}
