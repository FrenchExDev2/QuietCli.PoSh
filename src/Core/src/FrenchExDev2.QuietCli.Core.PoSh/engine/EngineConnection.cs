using System.Collections;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>State of the one engine the module owns: direct host or isolated child process, plus protocol counters.</summary>
public sealed class EngineConnection
{
    /// <summary>InProcess or Process.</summary>
    public string Mode { get; set; } = "";
    /// <summary>Direct host, set only in InProcess mode.</summary>
    public InProcessEngine? Host { get; set; }
    /// <summary>Isolated engine process, set only in Process mode.</summary>
    public Process? Process { get; set; }
    /// <summary>Engine standard input, Process mode only.</summary>
    public Stream? Input { get; set; }
    /// <summary>Engine standard output, Process mode only.</summary>
    public Stream? Output { get; set; }
    /// <summary>Absolute telemetry database path.</summary>
    public string Database { get; set; } = "";
    /// <summary>Total requests exchanged.</summary>
    public long Requests { get; set; }
    /// <summary>Requests that avoided control JSON.</summary>
    public long DirectRequests { get; set; }
    /// <summary>Requests that used control JSON.</summary>
    public long MetadataJsonRequests { get; set; }
    /// <summary>Wire bytes written to the isolated engine.</summary>
    public long InputBytes { get; set; }
    /// <summary>Wire bytes read from the isolated engine.</summary>
    public long OutputBytes { get; set; }
    /// <summary>Engine identity reported by the hello exchange.</summary>
    public object? Info { get; set; }
    /// <summary>True once a transport failure made the session unusable.</summary>
    public bool Broken { get; set; }
    /// <summary>Bounded copy of the isolated engine diagnostics stream.</summary>
    public Task? DiagnosticDrain { get; set; }
}

/// <summary>One decoded engine reply: the metadata object (CLR or PowerShell shaped) and the transient native block.</summary>
/// <param name="Header">Reply metadata with Version, RequestId, Ok and Data or Error.</param>
/// <param name="Payload">Transient output bytes, possibly empty.</param>
public sealed record EngineReply(object Header, byte[] Payload);

/// <summary>Adapts metadata property bags on the calling PowerShell thread.</summary>
public static class MetadataAdapter
{
    /// <summary>Shared adapter instance; it only copies property names and values.</summary>
    public static readonly Func<object, IDictionary> Instance = Adapt;

    /// <summary>Copies the properties of a PowerShell object into an ordered dictionary.</summary>
    /// <param name="value">Metadata property bag.</param>
    private static IDictionary Adapt(object value)
    {
        var fields = new System.Collections.Specialized.OrderedDictionary();
        foreach (PSPropertyInfo property in PSObject.AsPSObject(value).Properties) fields.Add(property.Name, property.Value);
        return fields;
    }
}

/// <summary>Reads a property from a CLR or PowerShell object; absent properties yield null.</summary>
public static class PropertyReader
{
    /// <summary>Returns the value of a named property.</summary>
    /// <param name="value">CLR object, anonymous type or PSObject.</param>
    /// <param name="name">Property name.</param>
    public static object? Get(object? value, string name) => value is null ? null : PSObject.AsPSObject(value).Properties[name]?.Value;
}

/// <summary>Converts between PowerShell values and the bounded JSON control headers.</summary>
public static class HeaderJson
{
    /// <summary>Maximum structural depth, equal to the original ConvertTo-Json depth.</summary>
    private const int MaxDepth = 32;

    /// <summary>Encodes a control header as compact UTF-8 JSON.</summary>
    /// <param name="header">Control metadata, never a business object.</param>
    public static byte[] Encode(IDictionary header)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream)) Write(writer, header, 0);
        return stream.ToArray();
    }

    /// <summary>Writes one PowerShell value.</summary>
    private static void Write(Utf8JsonWriter writer, object? value, int depth)
    {
        if (depth > MaxDepth) throw new InvalidOperationException("HeaderTooDeep");
        if (value is PSObject wrapped && wrapped.BaseObject is not PSCustomObject) value = wrapped.BaseObject;
        switch (value)
        {
            case null: writer.WriteNullValue(); return;
            case string text: writer.WriteStringValue(text); return;
            case bool flag: writer.WriteBooleanValue(flag); return;
            case int or long or short or byte or sbyte or ushort or uint: writer.WriteNumberValue(Convert.ToInt64(value, CultureInfo.InvariantCulture)); return;
            case ulong big: writer.WriteNumberValue(big); return;
            case double or float or decimal: writer.WriteNumberValue(Convert.ToDouble(value, CultureInfo.InvariantCulture)); return;
            case IDictionary map:
                writer.WriteStartObject();
                foreach (DictionaryEntry entry in map) { writer.WritePropertyName(Convert.ToString(entry.Key, CultureInfo.InvariantCulture) ?? ""); Write(writer, entry.Value, depth + 1); }
                writer.WriteEndObject(); return;
            case IEnumerable items:
                writer.WriteStartArray();
                foreach (object? item in items) Write(writer, item, depth + 1);
                writer.WriteEndArray(); return;
            case Enum or Guid or DateTime or DateTimeOffset or TimeSpan: writer.WriteStringValue(Convert.ToString(value, CultureInfo.InvariantCulture)); return;
        }
        writer.WriteStartObject();
        foreach (PSPropertyInfo property in PSObject.AsPSObject(value).Properties) { writer.WritePropertyName(property.Name); Write(writer, property.Value, depth + 1); }
        writer.WriteEndObject();
    }

    /// <summary>Decodes JSON into the PSCustomObject, array and scalar shapes that ConvertFrom-Json produced.</summary>
    /// <param name="json">UTF-8 text of one reply header.</param>
    public static object? Decode(string json)
    {
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 48 });
        return ToPs(document.RootElement);
    }

    /// <summary>Converts one element.</summary>
    private static object? ToPs(JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                var result = new PSObject();
                foreach (JsonProperty property in element.EnumerateObject()) result.Properties.Add(new PSNoteProperty(property.Name, ToPs(property.Value)));
                return result;
            case JsonValueKind.Array:
                var items = new List<object?>();
                foreach (JsonElement item in element.EnumerateArray()) items.Add(ToPs(item));
                return items.ToArray();
            case JsonValueKind.String: return element.GetString();
            case JsonValueKind.True: return true;
            case JsonValueKind.False: return false;
            case JsonValueKind.Number:
                if (element.TryGetInt32(out int small)) return small;
                if (element.TryGetInt64(out long large)) return large;
                return element.GetDouble();
            default: return null;
        }
    }
}

/// <summary>Sends one bounded exchange to the owned engine and validates the reply.</summary>
public static class EngineClient
{
    /// <summary>Actions that read a block directly in the InProcess host.</summary>
    private static readonly HashSet<string> ControlActions = new(StringComparer.Ordinal) { "input", "eof", "cancel", "resize", "release" };
    /// <summary>Actions dispatched as metadata without JSON in the InProcess host.</summary>
    private static readonly HashSet<string> MetadataActions = new(StringComparer.Ordinal) { "hello", "allocations", "start", "save", "gain", "gain-poll", "gain-next", "gain-release", "scrub", "shutdown" };

    /// <summary>Exchanges one metadata frame and an optional transient byte block.</summary>
    /// <param name="engine">Owned engine.</param>
    /// <param name="header">Control fields; Version and RequestId are added.</param>
    /// <param name="payload">Native input bytes, at most the protocol block size.</param>
    /// <param name="timeoutSeconds">Per-exchange deadline.</param>
    public static EngineReply Send(EngineConnection engine, IDictionary header, byte[] payload, double timeoutSeconds)
    {
        if (engine.Broken) throw new InvalidOperationException("EngineDisconnected");
        if (payload.Length > ProtocolSpecification.BlockSize) throw new InvalidOperationException("InputBlockTooLarge");
        string requestId = Guid.NewGuid().ToString("N");
        header["Version"] = ProtocolSpecification.Version;
        header["RequestId"] = requestId;
        string action = System.Convert.ToString(header["Action"], CultureInfo.InvariantCulture) ?? "";
        bool inProcess = engine.Mode == "InProcess";
        bool directRead = inProcess && action == "next";
        bool directControl = inProcess && ControlActions.Contains(action);
        bool directMetadata = inProcess && MetadataActions.Contains(action);
        bool direct = directRead || directControl || directMetadata;
        byte[]? encoded = direct ? null : HeaderJson.Encode(header);
        if (!double.IsFinite(timeoutSeconds) || timeoutSeconds < 0.05 || timeoutSeconds > 300) throw new InvalidOperationException("InvalidIpcTimeout");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
        object response;
        byte[] payloadBytes;
        ProtocolClientReply? packet = null;
        try
        {
            if (inProcess)
            {
                string invocation = System.Convert.ToString(header["InvocationId"], CultureInfo.InvariantCulture) ?? "";
                Task<LocalEngineReply> pending;
                if (directRead) pending = engine.Host!.ReadAsync(invocation, requestId);
                else if (directControl) pending = engine.Host!.ControlAsync(Enum.Parse<LocalControl>(action, true), invocation, requestId, payload, ToInt(header["Columns"]), ToInt(header["Rows"]));
                else if (directMetadata) pending = engine.Host!.MetadataAsync(header, MetadataAdapter.Instance);
                else pending = engine.Host!.RequestAsync(encoded!, payload);
                LocalEngineReply reply = pending.WaitAsync(deadline.Token).GetAwaiter().GetResult();
                response = reply.Header ?? HeaderJson.Decode(reply.HeaderJson!)!;
                payloadBytes = reply.Payload;
            }
            else
            {
                packet = ProtocolClient.ExchangeAsync(engine.Input!, engine.Output!, encoded!, payload, deadline.Token).GetAwaiter().GetResult();
                payloadBytes = packet.Payload;
                response = HeaderJson.Decode(Encoding.UTF8.GetString(packet.Header))!;
            }
            if (ToInt(PropertyReader.Get(response, "Version")) != ProtocolSpecification.Version || !string.Equals(PropertyReader.Get(response, "RequestId") as string, requestId, StringComparison.Ordinal))
                throw new InvalidDataException("ProtocolMismatch");
            engine.Requests++;
            if (direct) engine.DirectRequests++; else engine.MetadataJsonRequests++;
            if (!inProcess && packet is not null) { engine.InputBytes += packet.InputBytes; engine.OutputBytes += packet.OutputBytes; }
        }
        catch (Exception error)
        {
            engine.Broken = true;
            try
            {
                if (inProcess) _ = engine.Host!.DisposeAsync().AsTask();
                else if (engine.Process is { HasExited: false }) engine.Process.Kill(true);
            }
            catch (Exception) { /* the transport is already unusable; the original failure is reported */ }
            throw new IOException("EngineCommunicationFailed: " + error.GetType().Name, error);
        }
        if (PropertyReader.Get(response, "Ok") is not true)
        {
            object? failure = PropertyReader.Get(response, "Error");
            var rejected = new InvalidOperationException("EngineRequestRejected: " + PropertyReader.Get(failure, "Message"));
            rejected.Data["QuietCliRequestRejected"] = true;
            rejected.Data["Code"] = PropertyReader.Get(failure, "Code");
            throw rejected;
        }
        return new EngineReply(response, payloadBytes);
    }

    /// <summary>Converts an optional numeric header value; absent means zero.</summary>
    private static int ToInt(object? value) => value is null ? 0 : System.Convert.ToInt32(value is PSObject wrapped ? wrapped.BaseObject : value, CultureInfo.InvariantCulture);
}
