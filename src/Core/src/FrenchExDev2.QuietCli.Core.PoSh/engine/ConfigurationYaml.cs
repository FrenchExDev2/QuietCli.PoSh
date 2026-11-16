using System.Collections;
using System.Globalization;
using System.Reflection;
using System.Runtime.Loader;

namespace FrenchExDev2.QuietCli;

/// <summary>Bounded inert configuration parsing using the verified private YAML dependency.</summary>
public static class ConfigurationYaml
{
    /// <summary>Dependency-only load contexts, never configuration content.</summary>
    private static readonly Dictionary<string, Assembly> libraries = new(StringComparer.Ordinal);

    /// <summary>Reads at most 64 KiB as strict UTF-8 and parses one mapping document.</summary>
    /// <param name="path">Existing configuration file.</param>
    /// <param name="libraryPath">Integrity-verified YamlDotNet resource.</param>
    public static async Task<Dictionary<string, ConfigurationValue>> ReadAsync(string path, string libraryPath)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, true);
        var bytes = new byte[65537]; int count = 0, read;
        while (count < bytes.Length && (read = await stream.ReadAsync(bytes.AsMemory(count))) != 0) count += read;
        if (count > 65536) throw new ConfigurationYamlException("ConfigurationSizeLimit", "", 0, 0);
        string text = new System.Text.UTF8Encoding(false, true).GetString(bytes, 0, count).TrimStart('\uFEFF');
        Assembly library;
        lock (libraries) {
            if (!libraries.TryGetValue(libraryPath, out library!)) {
                library = new AssemblyLoadContext("QuietConfigurationYaml", false).LoadFromAssemblyPath(Path.GetFullPath(libraryPath));
                libraries.Add(libraryPath, library);
            }
        }
        return new Reader(library, text).Read();
    }

    /// <summary>Event parser rejects aliases, anchors, tags and sequences before building a small mapping.</summary>
    private sealed class Reader
    {
        /// <summary>Private dependency parser instance.</summary>
        private readonly object parser;
        /// <summary>Parser advance method.</summary>
        private readonly MethodInfo move;
        /// <summary>Current event property.</summary>
        private readonly PropertyInfo current;
        /// <summary>Bounded event count.</summary>
        private int count;
        /// <summary>Current event, never retained after parsing.</summary>
        private object Event => current.GetValue(parser)!;
        /// <summary>Current event kind.</summary>
        private string Kind => Event.GetType().Name;
        /// <summary>Creates a parser without object deserialization.</summary>
        /// <param name="library">Verified dependency.</param>
        /// <param name="text">Bounded configuration input.</param>
        internal Reader(Assembly library, string text)
        {
            Type type = library.GetType("YamlDotNet.Core.Parser", true)!;
            parser = Activator.CreateInstance(type, new StringReader(text))!;
            move = type.GetMethod("MoveNext")!; current = type.GetProperty("Current")!;
        }
        /// <summary>Advances once while enforcing the resource and inert-input limits.</summary>
        private void Next()
        {
            try {
                if (!(bool)move.Invoke(parser, null)! || ++count > 256) Fail("ConfigurationStructureLimit", "");
            } catch (TargetInvocationException error) {
                var start = error.InnerException?.GetType().GetProperty("Start")?.GetValue(error.InnerException);
                throw new ConfigurationYamlException("InvalidYaml", "", Coordinate(start, "Line"), Coordinate(start, "Column"));
            }
            foreach (string property in new[] { "Tag", "Anchor" }) {
                var value = Event.GetType().GetProperty(property)?.GetValue(Event);
                if (value != null && value.GetType().GetProperty("IsEmpty")?.GetValue(value) is false) Fail("YamlTagsAndAnchorsForbidden", "");
            }
            if (Kind == "AnchorAlias") Fail("YamlAliasesForbidden", "");
        }
        /// <summary>Parses exactly one document rooted in a mapping.</summary>
        internal Dictionary<string, ConfigurationValue> Read()
        {
            Next(); Expect("StreamStart"); Next(); Expect("DocumentStart"); Next();
            var result = Map("", 0); Expect("DocumentEnd"); Next(); Expect("StreamEnd");
            return result;
        }
        /// <summary>Reads unique string keys and mapping/scalar values only.</summary>
        /// <param name="prefix">Diagnostic key path.</param>
        /// <param name="depth">Current mapping depth.</param>
        private Dictionary<string, ConfigurationValue> Map(string prefix, int depth)
        {
            if (depth > 8) Fail("ConfigurationDepthLimit", prefix);
            Expect("MappingStart"); Next();
            var result = new Dictionary<string, ConfigurationValue>(StringComparer.Ordinal);
            while (Kind != "MappingEnd") {
                Expect("Scalar"); string key = (string)Event.GetType().GetProperty("Value")!.GetValue(Event)!;
                string path = prefix.Length == 0 ? key : prefix + "." + key;
                var mark = Event.GetType().GetProperty("Start")!.GetValue(Event);
                if (key.Length == 0 || key == "<<" || result.ContainsKey(key)) Fail("DuplicateOrInvalidConfigurationKey", path);
                Next(); object? value;
                if (Kind == "MappingStart") value = Map(path, depth + 1);
                else {
                    Expect("Scalar");
                    string raw = (string)Event.GetType().GetProperty("Value")!.GetValue(Event)!;
                    bool plain = Event.GetType().GetProperty("Style")!.GetValue(Event)!.ToString() == "Plain";
                    value = raw;
                    if (plain) {
                        if (raw is "null" or "~" or "") value = null;
                        else if (raw is "true" or "false") value = raw == "true";
                        else if (long.TryParse(raw, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long integer)) value = integer;
                        else if (double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out double number)) value = number;
                    }
                    Next();
                }
                result.Add(key, new ConfigurationValue(value, Coordinate(mark, "Line"), Coordinate(mark, "Column")));
            }
            Next(); return result;
        }
        /// <summary>Checks an event kind without accepting alternate document structures.</summary>
        /// <param name="kind">Required event kind.</param>
        private void Expect(string kind) { if (Kind != kind) Fail("UnexpectedYamlStructure", ""); }
        /// <summary>Raises a structured diagnostic at the current event.</summary>
        /// <param name="code">Stable diagnostic code.</param>
        /// <param name="key">Configuration key path.</param>
        private void Fail(string code, string key)
        {
            var start = Event.GetType().GetProperty("Start")?.GetValue(Event);
            throw new ConfigurationYamlException(code, key, Coordinate(start, "Line"), Coordinate(start, "Column"));
        }
        /// <summary>Reads a one-based YAML mark coordinate.</summary>
        /// <param name="mark">Optional parser mark.</param>
        /// <param name="name">Line or Column.</param>
        private static int Coordinate(object? mark, string name) => mark == null ? 0 : Convert.ToInt32(mark.GetType().GetProperty(name)!.GetValue(mark), CultureInfo.InvariantCulture);
    }
}

/// <summary>Inert mapping value and its diagnostic location.</summary>
/// <param name="Value">Primitive scalar or nested configuration mapping.</param>
/// <param name="Line">Source line.</param>
/// <param name="Column">Source column.</param>
public sealed record ConfigurationValue(object? Value, int Line, int Column);

/// <summary>Structured parser failure without arbitrary type construction.</summary>
public sealed class ConfigurationYamlException : IOException
{
    /// <summary>Stable validation code.</summary>
    public string Code { get; }
    /// <summary>Configuration key path.</summary>
    public string Key { get; }
    /// <summary>Source line, or zero when unavailable.</summary>
    public int Line { get; }
    /// <summary>Source column, or zero when unavailable.</summary>
    public int Column { get; }
    /// <summary>Creates a structured parser error.</summary>
    /// <param name="code">Stable code.</param>
    /// <param name="key">Key path.</param>
    /// <param name="line">Source line.</param>
    /// <param name="column">Source column.</param>
    public ConfigurationYamlException(string code, string key, int line, int column) : base($"{code}: {key} ({line}:{column})")
    { Code = code; Key = key; Line = line; Column = column; }
}
