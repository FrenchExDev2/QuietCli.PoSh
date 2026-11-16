using System.Collections;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Session-wide registry of inert handler definitions and cached version probes.</summary>
public static class HandlerRegistry
{
    /// <summary>Registered handlers in registration order, by identity.</summary>
    public static readonly OrderedDictionary Handlers = new(StringComparer.Ordinal);

    /// <summary>Successful version probes by binary identity.</summary>
    public static Dictionary<string, object?> ProbeCache { get; } = new(StringComparer.Ordinal);

    /// <summary>Fields every definition must provide.</summary>
    private static readonly string[] RequiredFields = ["Binary", "Execute", "VersionRange", "TestVersion"];

    /// <summary>Optional fields and their defaults.</summary>
    private static readonly (string Name, Func<object> Value)[] Defaults =
    [
        ("Summary", () => "Business command processed."), ("ModuleVersion", () => "0.1.0"), ("Documentation", () => Array.Empty<object>()),
        ("SupportedForms", () => Array.Empty<object>()), ("Qualification", () => "NotQualified"),
    ];

    /// <summary>Stores a validated copy of one definition.</summary>
    /// <param name="id">Stable module/handler identity.</param>
    /// <param name="definition">Binary, version policy, callbacks and documentation.</param>
    public static void Register(string id, Hashtable definition)
    {
        foreach (string field in RequiredFields) if (!definition.ContainsKey(field)) throw new InvalidOperationException("MissingHandlerField: " + field);
        if (Handlers.Contains(id)) throw new InvalidOperationException("HandlerAlreadyRegistered: " + id);
        var copy = (Hashtable)definition.Clone();
        copy["Id"] = id;
        foreach ((string name, Func<object> value) in Defaults) if (!copy.ContainsKey(name)) copy[name] = value();
        Handlers[id] = copy;
    }

    /// <summary>Selects the registered handler matching the call, probing versions once per binary identity.</summary>
    /// <param name="runtime">Invocation being resolved: exposes Request and State.</param>
    /// <returns>The single matching handler definition, or null.</returns>
    public static Hashtable? Resolve(object runtime)
    {
        var request = (IDictionary)QuietRuntime.Unwrap(PropertyReader.Get(runtime, "Request"))!;
        var state = (IDictionary)QuietRuntime.Unwrap(PropertyReader.Get(runtime, "State"))!;
        string filePath = Text(request["FilePath"]);
        string binary = Path.GetFileName(filePath);
        if (OperatingSystem.IsWindows() && binary.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) binary = binary[..^4];
        bool specific = request.Contains("HandlerId");
        string? requested = specific ? Text(request["HandlerId"]) : null;
        var matches = new List<Hashtable>();
        foreach (Hashtable handler in Handlers.Values.Cast<Hashtable>().ToArray())
        {
            if (Text(handler["Binary"]) != binary || (specific && Text(handler["Id"]) != requested)) continue;
            string key = ProbeIdentity.Build(Text(handler["Id"]), filePath, (IDictionary)QuietRuntime.Unwrap(request["Environment"])!);
            if (!ProbeCache.TryGetValue(key, out object? version))
            {
                if (!handler.ContainsKey("Probe")) continue;
                var probed = Block(handler["Probe"]).Invoke(runtime);
                if (probed.Count != 1) throw new InvalidOperationException("VersionProbeMustReturnOneValue");
                version = ProbeCache[key] = probed[0];
            }
            if (!OneBoolean(Block(handler["TestVersion"]).Invoke(version), "VersionPredicateMustReturnOneBoolean")) continue;
            bool shape = !handler.ContainsKey("Match") || OneBoolean(Block(handler["Match"]).Invoke(request, version), "ShapePredicateMustReturnOneBoolean");
            if (!shape) continue;
            state["DetectedVersion"] = version;
            matches.Add(handler);
        }
        if (matches.Count > 1) throw new InvalidOperationException("AmbiguousHandler");
        return matches.Count == 1 ? matches[0] : null;
    }

    /// <summary>Requires exactly one Boolean emission.</summary>
    private static bool OneBoolean(System.Collections.ObjectModel.Collection<PSObject> values, string code)
    {
        if (values.Count != 1 || QuietRuntime.Unwrap(values[0]) is not bool flag) throw new InvalidOperationException(code);
        return flag;
    }

    /// <summary>Extracts a handler callback.</summary>
    private static ScriptBlock Block(object? value) => QuietRuntime.Unwrap(value) as ScriptBlock ?? throw new InvalidOperationException("HandlerCallbackMustBeScriptBlock");

    /// <summary>Converts a definition scalar to text.</summary>
    private static string Text(object? value) => Convert.ToString(QuietRuntime.Unwrap(value), CultureInfo.InvariantCulture) ?? "";
}

/// <summary>Registers inert handler metadata; import never launches a binary.</summary>
[Cmdlet(VerbsLifecycle.Register, "QuietHandler")]
public sealed class RegisterQuietHandlerCommand : QuietCmdlet
{
    /// <summary>Stable module/handler identity.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public string Id { get; set; } = "";

    /// <summary>Binary, version policy, Probe, Match, Execute, schemas and documentation.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    public Hashtable Definition { get; set; } = new();

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { HandlerRegistry.Register(Id, Definition); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}

/// <summary>Removes one session registration without process or filesystem changes.</summary>
[Cmdlet(VerbsLifecycle.Unregister, "QuietHandler")]
public sealed class UnregisterQuietHandlerCommand : QuietCmdlet
{
    /// <summary>Registered handler identity.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public string Id { get; set; } = "";

    /// <inheritdoc />
    protected override void EndProcessing() => HandlerRegistry.Handlers.Remove(Id);
}

/// <summary>Inspects inert handler metadata without probing a binary.</summary>
[Cmdlet(VerbsCommon.Get, "QuietHandler")]
[OutputType(typeof(PSObject))]
public sealed class GetQuietHandlerCommand : QuietCmdlet
{
    /// <summary>Optional executable name.</summary>
    [Parameter(Position = 0)]
    public string? Binary { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        foreach (Hashtable handler in HandlerRegistry.Handlers.Values.Cast<Hashtable>().ToArray())
        {
            if (!string.IsNullOrEmpty(Binary) && !Equals(handler["Binary"], Binary)) continue;
            var view = new PSObject();
            foreach (string name in new[] { "Id", "Binary", "VersionRange", "ModuleVersion", "Documentation", "SupportedForms", "Qualification" })
                view.Properties.Add(new PSNoteProperty(name, handler[name]));
            WriteObject(view);
        }
    }
}

/// <summary>Resolves a versioned handler for one runtime, caching successful probes; internal to the module.</summary>
[Cmdlet(VerbsDiagnostic.Resolve, "QuietHandler")]
public sealed class ResolveQuietHandlerCommand : QuietCmdlet
{
    /// <summary>Invocation being resolved; probes become its measured children.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public object Runtime { get; set; } = null!;

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { if (HandlerRegistry.Resolve(Runtime) is { } handler) WriteObject(handler); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}
