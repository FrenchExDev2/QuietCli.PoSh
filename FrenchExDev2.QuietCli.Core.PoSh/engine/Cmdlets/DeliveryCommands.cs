using System.Collections;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Serializes projected values (dictionaries, sequences, scalars) to compressed JSON without the ConvertTo-Json pipeline.</summary>
internal static class JsonText
{
    /// <summary>Writer options: relaxed escaping keeps non-ASCII text readable, like ConvertTo-Json.</summary>
    private static readonly System.Text.Json.JsonWriterOptions Options = new() { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping, Indented = false };

    /// <summary>Converts a value to compressed JSON.</summary>
    /// <param name="value">Value to serialize.</param>
    /// <param name="depth">Maximum depth; deeper values are rendered as their string form.</param>
    public static string Compress(object? value, int depth)
    {
        using var stream = new MemoryStream();
        using (var writer = new System.Text.Json.Utf8JsonWriter(stream, Options)) Write(writer, value, depth);
        return Encoding.UTF8.GetString(stream.GetBuffer(), 0, (int)stream.Length);
    }

    /// <summary>Writes one value recursively.</summary>
    /// <param name="writer">Target writer.</param>
    /// <param name="value">Value to write.</param>
    /// <param name="depth">Remaining depth.</param>
    private static void Write(System.Text.Json.Utf8JsonWriter writer, object? value, int depth)
    {
        if (value is PSObject wrapped && wrapped.BaseObject is not PSCustomObject) value = wrapped.BaseObject;
        switch (value)
        {
            case null: writer.WriteNullValue(); return;
            case string text: writer.WriteStringValue(text); return;
            case bool flag: writer.WriteBooleanValue(flag); return;
            case char character: writer.WriteStringValue(character.ToString()); return;
            case byte or sbyte or short or ushort or int or uint or long: writer.WriteNumberValue(Convert.ToInt64(value, CultureInfo.InvariantCulture)); return;
            case ulong big: writer.WriteNumberValue(big); return;
            case float or double: { double number = Convert.ToDouble(value, CultureInfo.InvariantCulture); if (double.IsFinite(number)) writer.WriteNumberValue(number); else writer.WriteStringValue(number.ToString(CultureInfo.InvariantCulture)); return; }
            case decimal money: writer.WriteNumberValue(money); return;
            case DateTime moment: writer.WriteStringValue(moment.ToString("o", CultureInfo.InvariantCulture)); return;
            case DateTimeOffset offset: writer.WriteStringValue(offset.ToString("o", CultureInfo.InvariantCulture)); return;
            case Enum member: writer.WriteStringValue(member.ToString()); return;
        }
        if (depth <= 0) { writer.WriteStringValue(Convert.ToString(value, CultureInfo.InvariantCulture)); return; }
        if (value is IDictionary map)
        {
            writer.WriteStartObject();
            foreach (DictionaryEntry entry in map) { writer.WritePropertyName(Convert.ToString(entry.Key, CultureInfo.InvariantCulture) ?? ""); Write(writer, entry.Value, depth - 1); }
            writer.WriteEndObject();
        }
        else if (value is IEnumerable sequence)
        {
            writer.WriteStartArray();
            foreach (object? item in sequence) Write(writer, item, depth - 1);
            writer.WriteEndArray();
        }
        else
        {
            writer.WriteStartObject();
            foreach (PSPropertyInfo property in PSObject.AsPSObject(value).Properties) { writer.WritePropertyName(property.Name); Write(writer, property.Value, depth - 1); }
            writer.WriteEndObject();
        }
    }
}
/// <summary>Loads each tokenizer once, after verifying the pinned library hashes.</summary>
internal static class DeliveryTokenizers
{
    /// <summary>Tokenizer libraries in dependency order.</summary>
    private static readonly string[] Libraries = ["Microsoft.Bcl.Memory", "Microsoft.ML.Tokenizers", "Microsoft.ML.Tokenizers.Data.O200kBase", "Microsoft.ML.Tokenizers.Data.Cl100kBase"];
    /// <summary>Loaded tokenizers by encoding name.</summary>
    private static readonly Dictionary<string, (Func<string, int> Count, string Version)> Cache = new(StringComparer.Ordinal);
    /// <summary>Serializes first loads.</summary>
    private static readonly object Sync = new();

    /// <summary>Forgets loaded tokenizers; used when the session is re-initialized.</summary>
    internal static void Reset() { lock (Sync) Cache.Clear(); }

    /// <summary>Returns the token counter and version label of an encoding.</summary>
    /// <param name="encoding">o200k_base or cl100k_base.</param>
    public static (Func<string, int> Count, string Version) Get(string encoding)
    {
        lock (Sync)
        {
            if (Cache.TryGetValue(encoding, out var loaded)) return loaded;
            Assembly? tokenizers = null;
            foreach (string name in Libraries)
            {
                ResourceVerifier.Verify(QuietSession.Root, "resources/tokenizers/" + name + ".dll");
                Assembly assembly = Assembly.LoadFrom(Path.Combine(QuietSession.Root, "resources", "tokenizers", name + ".dll"));
                if (name == "Microsoft.ML.Tokenizers") tokenizers = assembly;
            }
            Type tiktoken = tokenizers!.GetType("Microsoft.ML.Tokenizers.TiktokenTokenizer", true)!;
            MethodInfo create = tiktoken.GetMethods(BindingFlags.Public | BindingFlags.Static).First(m => m.Name == "CreateForEncoding" && m.GetParameters().Length == 3 && m.GetParameters()[0].ParameterType == typeof(string));
            object tokenizer = create.Invoke(null, [encoding, null, null])!;
            MethodInfo count = tiktoken.GetMethods(BindingFlags.Public | BindingFlags.Instance).First(m => m.Name == "CountTokens" && m.GetParameters().Length > 0 && m.GetParameters()[0].ParameterType == typeof(string));
            int extra = count.GetParameters().Length - 1;
            Func<string, int> counter = text =>
            {
                var arguments = new object?[extra + 1];
                arguments[0] = text;
                for (int index = 1; index <= extra; index++) arguments[index] = true;
                return (int)count.Invoke(tokenizer, arguments)!;
            };
            return Cache[encoding] = (counter, "Microsoft.ML.Tokenizers/" + tokenizers.GetName().Version);
        }
    }
}

/// <summary>Projects execution counters of a result, never its business Data.</summary>
internal static class ResultMetadata
{
    /// <summary>Builds the closed telemetry metadata of a completed result.</summary>
    /// <param name="result">Local result.</param>
    public static IDictionary Get(object result)
    {
        object? internals = Members.Get(result, "Internal");
        object? request = Members.Get(internals, "Request");
        object? sources = Members.Get(internals, "Sources");
        var fields = new Hashtable(StringComparer.OrdinalIgnoreCase)
        {
            ["InvocationId"] = Members.Get(result, "InvocationId"),
            ["ParentId"] = Members.Get(result, "ParentId"),
            ["RootId"] = Members.Get(result, "RootId"),
            ["SessionId"] = Members.Get(result, "SessionId"),
            ["Context"] = Members.Get(result, "Context"),
            ["Command"] = Path.GetFileName(Convert.ToString(Members.Get(request, "FilePath"), CultureInfo.InvariantCulture) ?? ""),
            ["Role"] = Members.Get(request, "Role"),
            ["Outcome"] = Members.Get(result, "Outcome"),
            ["Completeness"] = Members.Get(result, "Completeness"),
            ["Sources"] = sources is IDictionary map ? map.Values : sources,
            ["Execution"] = Members.Get(result, "Execution"),
            ["Error"] = Members.Get(result, "Error"),
            ["Allocation"] = Members.Get(Members.Get(result, "Measurement"), "Allocation"),
            ["CompleteAllocation"] = Members.Get(Members.Get(result, "Measurement"), "CompleteAllocation"),
        };
        object? handler = Members.Get(internals, "Handler");
        if (handler is not null && LanguagePrimitives.IsTrue(handler))
        {
            fields["HandlerId"] = Members.Get(handler, "Id");
            fields["ModuleVersion"] = Members.Get(handler, "ModuleVersion");
        }
        return MeasurementTelemetry.Project(fields, MetadataAdapter.Instance);
    }
}

/// <summary>Shared delivery pipeline: bounded projection, envelope, measurement and telemetry for JSON or YAML.</summary>
public abstract class ResultDeliveryCmdlet : EngineCmdlet
{
    /// <summary>Strict UTF-8 used for byte accounting.</summary>
    private static readonly UTF8Encoding Utf8 = new(false, true);

    /// <summary>Local QuietCli result.</summary>
    [Parameter(Position = 0, Mandatory = true, ValueFromPipeline = true)]
    public object InputObject { get; set; } = null!;

    /// <summary>Presented entries per container.</summary>
    [Parameter(Position = 1)]
    public int MaxItems { get; set; }

    /// <summary>Final UTF-8 byte budget.</summary>
    [Parameter(Position = 2)]
    public int MaxOutputBytes { get; set; }

    /// <summary>Encoding override; defaults to the effective configuration.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("off", "o200k_base", "cl100k_base")]
    public string Tokenizer { get; set; } = "";

    /// <summary>True when YAML is requested.</summary>
    protected abstract bool Yaml { get; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try { WriteObject(Deliver()); }
        catch (Exception error) when (error is not PipelineStoppedException and not PipelineClosedException) { FailWith(error); }
    }

    /// <summary>Produces and measures one actual bounded delivery.</summary>
    private string Deliver()
    {
        var values = ConfigurationService.Snapshot(CurrentDirectory).Values;
        int maxItems = MyInvocation.BoundParameters.ContainsKey(nameof(MaxItems)) ? MaxItems : Convert.ToInt32(values["delivery.maxItems"], CultureInfo.InvariantCulture);
        int maxBytes = MyInvocation.BoundParameters.ContainsKey(nameof(MaxOutputBytes)) ? MaxOutputBytes : Convert.ToInt32(values["delivery.maxOutputBytes"], CultureInfo.InvariantCulture);
        string tokenizer = MyInvocation.BoundParameters.ContainsKey(nameof(Tokenizer)) ? Tokenizer : Convert.ToString(values["tokenization.tokenizer"], CultureInfo.InvariantCulture) ?? "off";
        if (maxBytes < 256 || maxItems < 0) throw new InvalidOperationException("InvalidDeliveryBudget");
        var watch = Stopwatch.StartNew();
        var state = new ProjectionState();
        object result = InputObject;
        var internals = (IDictionary)Members.Get(result, "Internal")!;
        object? business = Members.Get(result, "Data");
        if (Members.Get(internals["Request"], "Projection") is ScriptBlock projection)
            business = Collapse(projection.Invoke(business, new Hashtable { ["MaxItems"] = maxItems, ["MaxOutputBytes"] = maxBytes }));
        object? view = QuietProjection.Project(business, state, maxItems, Math.Min(2048, maxBytes));
        object? safeError = QuietProjection.Project(Members.Get(result, "Error"), state, maxItems, 256);
        object? completeness = Members.Get(result, "Completeness");
        var document = new OrderedDictionary
        {
            ["SchemaVersion"] = 1, ["Outcome"] = Members.Get(result, "Outcome"), ["InvocationId"] = Members.Get(result, "InvocationId"), ["Context"] = Members.Get(result, "Context"),
            ["Data"] = view, ["Completeness"] = completeness, ["Error"] = safeError,
            ["Truncation"] = new OrderedDictionary { ["Applied"] = state.Omitted > 0, ["Omitted"] = state.Omitted, ["OmittedExact"] = !state.UnknownOmissions },
        };
        bool truncated = state.Omitted > 0;
        string text;
        if (Yaml) { document["Completeness"] = Flags(completeness); text = RenderYaml(document); }
        else text = JsonText.Compress(document, 48);
        int size = Utf8.GetByteCount(text);
        if (size > maxBytes)
        {
            var reduced = new OrderedDictionary
            {
                ["SchemaVersion"] = 1, ["Outcome"] = Members.Get(result, "Outcome"), ["Data"] = null, ["Completeness"] = Flags(completeness),
                ["Truncation"] = new OrderedDictionary { ["Applied"] = true, ["Reason"] = "OutputBudget" },
            };
            object? error = Members.Get(result, "Error");
            if (error is not null && LanguagePrimitives.IsTrue(error))
            {
                object? first = error is IEnumerable sequence and not string ? sequence.Cast<object?>().FirstOrDefault() : error;
                string code = Convert.ToString(Members.Get(first, "Code"), CultureInfo.InvariantCulture) ?? "";
                if (code.Length > 64) code = code.Substring(0, 64);
                reduced["Error"] = new OrderedDictionary { ["Code"] = code };
            }
            truncated = true;
            text = Yaml ? RenderYaml(reduced) : JsonText.Compress(reduced, 8);
            size = Utf8.GetByteCount(text);
        }
        if (size > maxBytes) throw new InvalidOperationException("OutputBudgetTooSmall");
        double serializationMs = watch.Elapsed.TotalMilliseconds;
        string format = Yaml ? "yaml" : "json";
        string fingerprint = format + ":" + Convert.ToHexString(SHA256.HashData(Utf8.GetBytes(text)));
        if (!internals.Contains("DeliveryReceipts")) internals["DeliveryReceipts"] = new Hashtable(StringComparer.OrdinalIgnoreCase);
        var receipts = (Hashtable)internals["DeliveryReceipts"]!;
        bool already = receipts.ContainsKey(fingerprint);
        Hashtable receipt;
        if (!already)
        {
            if (receipts.Count >= Convert.ToInt32(values["delivery.maxTrackedRepresentations"], CultureInfo.InvariantCulture)) throw new InvalidOperationException("DeliveryRepresentationLimit");
            receipt = new Hashtable(StringComparer.OrdinalIgnoreCase)
            {
                ["DeliveryId"] = Guid.NewGuid().ToString("N"), ["Tokens"] = new Hashtable(StringComparer.OrdinalIgnoreCase),
                ["Persisted"] = new Hashtable(StringComparer.OrdinalIgnoreCase), ["Metadata"] = null,
            };
        }
        else receipt = (Hashtable)receipts[fingerprint]!;
        string deliveryId = (string)receipt["DeliveryId"]!;
        var tokensByKey = (Hashtable)receipt["Tokens"]!;
        long? tokens = null;
        string? tokenVersion = null;
        string measurementKey = "off";
        if (tokenizer != "off")
        {
            var (count, version) = DeliveryTokenizers.Get(tokenizer);
            tokenVersion = version;
            measurementKey = tokenizer + ":" + version;
            if (!tokensByKey.ContainsKey(measurementKey))
                tokensByKey[measurementKey] = new Hashtable(StringComparer.OrdinalIgnoreCase) { ["TokenProfile"] = tokenizer, ["TokenVersion"] = version, ["OutputTokens"] = (long)count(text) };
            tokens = (long)((Hashtable)tokensByKey[measurementKey]!)["OutputTokens"]!;
        }
        receipts[fingerprint] = receipt;
        bool offline = internals.Contains("Offline") && LanguagePrimitives.IsTrue(internals["Offline"]);
        if (receipt["Metadata"] is null && !offline)
        {
            IDictionary metadata = ResultMetadata.Get(result);
            metadata["DeliveryId"] = deliveryId; metadata["OutputBytes"] = size; metadata["OutputTokens"] = tokens; metadata["TokenProfile"] = tokenizer;
            metadata["TokenVersion"] = tokenVersion; metadata["Format"] = format; metadata["Truncated"] = truncated; metadata["SerializationMs"] = serializationMs;
            receipt["Metadata"] = metadata;
        }
        var deliveries = (IList)Members.Get(result, "Deliveries")!;
        deliveries.Clear();
        var entry = new PSObject();
        foreach (var (name, value) in new (string, object?)[] { ("DeliveryId", deliveryId), ("AlreadyDelivered", already), ("Format", format), ("Text", text), ("Bytes", size), ("Tokens", tokens), ("TokenProfile", tokenizer), ("TokenVersion", tokenVersion) })
            entry.Properties.Add(new PSNoteProperty(name, value));
        deliveries.Add(entry);
        Members.SetNote(result, "DeliveryId", deliveryId);
        Members.SetNote(result, "AlreadyDelivered", already);
        object measurement = Members.Get(result, "Measurement")!;
        Members.SetNote(measurement, "DeliveryId", deliveryId);
        Members.SetNote(measurement, "AlreadyDelivered", already);
        Members.SetNote(measurement, "TokenProfile", tokenizer);
        Members.SetNote(measurement, "TokenVersion", tokenVersion);
        Members.SetNote(measurement, "OutputBytes", size);
        Members.SetNote(measurement, "OutputTokens", tokens);
        Members.SetNote(measurement, "Status", "Delivered");
        Members.SetNote(measurement, "StorageError", null);
        object? sources = Members.Get(internals, "Sources");
        Members.SetNote(measurement, "ReductionBytes", MeasurementTelemetry.Reduction(sources is IDictionary sourceMap ? sourceMap.Values : (IEnumerable)(sources ?? Array.Empty<object>()), completeness!, size, MetadataAdapter.Instance));
        if (Convert.ToBoolean(values["telemetry.enabled"], CultureInfo.InvariantCulture) && !offline)
        {
            string storeKey = Convert.ToString(values["telemetry.database"], CultureInfo.InvariantCulture) + ":" + measurementKey;
            try
            {
                var persisted = (Hashtable)receipt["Persisted"]!;
                if (!persisted.ContainsKey(storeKey))
                {
                    var metadata = (Hashtable)((Hashtable)receipt["Metadata"]!).Clone();
                    metadata["TokenMeasurements"] = tokensByKey.Values.Cast<object>().ToArray();
                    SaveMetadata(new Hashtable { ["Action"] = "save", ["Kind"] = "delivery", ["Metadata"] = metadata });
                    persisted[storeKey] = true;
                }
            }
            catch (Exception error) when (error is not PipelineStoppedException and not PipelineClosedException)
            {
                Members.SetNote(measurement, "StorageError", error is RuntimeException { InnerException: { } inner } ? inner.Message : error.Message);
                Members.SetNote(measurement, "Status", "StorageUnavailable");
            }
        }
        return text;
    }

    /// <summary>Sends one save request; a session-level Send-QuietRequest function (test seam) takes precedence over the cmdlet.</summary>
    /// <param name="header">Save request header.</param>
    private void SaveMetadata(Hashtable header)
    {
        if (FindFunction("Send-QuietRequest") is { } seam) { seam.ScriptBlock.Invoke(header); return; }
        EngineClient.Send(QuietSession.Engine ?? EnsureEngine(), header, [], IpcTimeout);
    }

    /// <summary>Mirrors the value of a script block invocation: nothing, one value or an array.</summary>
    private static object? Collapse(IList<PSObject> output) => output.Count switch
    {
        0 => null,
        1 => output[0]?.BaseObject is PSCustomObject ? output[0] : output[0]?.BaseObject,
        _ => output.Select(item => item?.BaseObject is PSCustomObject ? item : item?.BaseObject).ToArray(),
    };

    /// <summary>Keeps only the closed completeness flags.</summary>
    private static OrderedDictionary Flags(object? completeness) =>
        new() { ["Source"] = Members.Get(completeness, "Source"), ["Analysis"] = Members.Get(completeness, "Analysis") };

    /// <summary>Emits YAML for a normalized bounded document.</summary>
    private string RenderYaml(object document)
    {
        ResourceVerifier.Verify(QuietSession.Root, "resources/yaml/YamlDotNet.dll");
        return BoundedYaml.Render(document, QuietSession.Root, 0, scalar => JsonText.Compress(scalar, 4));
    }
}

/// <summary>Produces and measures one actual bounded delivery; no whole-result serialization.</summary>
[Cmdlet(VerbsData.Out, "QuietResult")]
[OutputType(typeof(string))]
public sealed class OutQuietResultCommand : ResultDeliveryCmdlet
{
    /// <summary>Selects JSON, the default.</summary>
    [Parameter]
    public SwitchParameter AsJson { get; set; }

    /// <summary>Selects YAML directly.</summary>
    [Parameter]
    public SwitchParameter AsYaml { get; set; }

    /// <inheritdoc />
    protected override bool Yaml => AsYaml;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (AsJson && AsYaml) { Fail("OutputFormatsAreExclusive"); return; }
        base.ProcessRecord();
    }
}

/// <summary>Produces a JSON delivery from a local result, measuring only the produced text.</summary>
[Cmdlet(VerbsData.ConvertTo, "QuietJson")]
[OutputType(typeof(string))]
public sealed class ConvertToQuietJsonCommand : ResultDeliveryCmdlet
{
    /// <inheritdoc />
    protected override bool Yaml => false;
}

/// <summary>Produces a YAML delivery with the same measurement and identity rules as JSON.</summary>
[Cmdlet(VerbsData.ConvertTo, "QuietYaml")]
[OutputType(typeof(string))]
public sealed class ConvertToQuietYamlCommand : ResultDeliveryCmdlet
{
    /// <inheritdoc />
    protected override bool Yaml => true;
}
