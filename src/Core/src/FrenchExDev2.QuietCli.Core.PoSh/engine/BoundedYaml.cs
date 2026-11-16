using System.Collections;
using System.Globalization;
using System.Numerics;
using System.Reflection;
using System.Runtime.Loader;

namespace FrenchExDev2.QuietCli;

/// <summary>YamlDotNet emission of an already normalized bounded graph, isolated from user module dependencies.</summary>
/// <remarks>
/// Output is compact: LF line breaks, implicit document markers, plain scalars whenever they still resolve
/// to the same string, and flow style for nested containers holding only scalars. The root stays a block mapping.
/// </remarks>
public static class BoundedYaml
{
    /// <summary>Private library contexts, containing types only and no caller data.</summary>
    private static readonly Dictionary<string, Runtime> runtimes = new(StringComparer.Ordinal);
    /// <summary>Serializes private-context creation.</summary>
    private static readonly object sync = new();
    /// <summary>YAML 1.1 and 1.2 words that resolve to booleans, null, special floats or merge/value keys.</summary>
    private static readonly HashSet<string> reserved = new(StringComparer.OrdinalIgnoreCase)
    {
        "true", "false", "yes", "no", "on", "off", "y", "n", "null", "~", "<<", "=",
        ".inf", "+.inf", "-.inf", ".nan",
    };

    /// <summary>Emits projected values; never projects or enumerates an arbitrary business object.</summary>
    /// <param name="value">Already bounded dictionaries, arrays and scalar values.</param>
    /// <param name="moduleRoot">Verified Core resource root.</param>
    /// <param name="indent">Optional leading indentation.</param>
    /// <param name="scalarJson">Caller-thread compatibility conversion for uncommon value types only.</param>
    public static string Render(object? value, string moduleRoot, int indent, Func<object, string> scalarJson)
    {
        if (indent < 0 || indent > 64) throw new ArgumentOutOfRangeException(nameof(indent));
        string path = Path.Combine(moduleRoot, "resources", "yaml", "YamlDotNet.dll");
        Runtime runtime;
        lock (sync) { if (!runtimes.TryGetValue(path, out runtime!)) runtimes.Add(path, runtime = new Runtime(path)); }
        using var writer = new StringWriter(CultureInfo.InvariantCulture);
        runtime.Write(writer, value, scalarJson);
        string result = writer.ToString().TrimEnd('\r', '\n');
        if (indent == 0) return result;
        string pad = new(' ', indent);
        return pad + result.Replace("\n", "\n" + pad);
    }

    /// <summary>
    /// True when a plain scalar would be read back as this same string by YAML 1.1 and 1.2 core resolvers.
    /// Syntactic validity (indicators, comments, flow punctuation) is decided afterwards by the emitter itself,
    /// which falls back to a quoted style when plain is not allowed in the current context.
    /// </summary>
    /// <param name="text">Candidate string scalar.</param>
    internal static bool PlainKeepsString(string text)
    {
        if (text.Length == 0 || reserved.Contains(text)) return false;
        foreach (char character in text)
            if (character < 0x20 || character is '\x7F' or '\x85' or '\u2028' or '\u2029' or '\uFEFF') return false;
        // Anything that starts like a number may resolve to an integer, float, base-60 value or timestamp.
        int index = text[0] is '+' or '-' ? 1 : 0;
        if (index < text.Length && char.IsAsciiDigit(text[index])) return false;
        if (index + 1 < text.Length && text[index] == '.' && char.IsAsciiDigit(text[index + 1])) return false;
        return true;
    }

    /// <summary>Private load context avoids binding to a different YamlDotNet loaded by a user module.</summary>
    private sealed class LibraryContext : AssemblyLoadContext
    {
        /// <summary>Creates a reusable dependency-only context.</summary>
        internal LibraryContext() : base(isCollectible: false) { }
        /// <summary>Shares only normal framework resolution; YamlDotNet has no package dependencies.</summary>
        /// <param name="assemblyName">Requested framework identity.</param>
        protected override Assembly? Load(AssemblyName assemblyName) => null;
    }

    /// <summary>Cached low-level YAML event factories; no reflection of caller object properties.</summary>
    private sealed class Runtime
    {
        /// <summary>Emitter settings: two-space indent, no folding, LF line breaks.</summary>
        private readonly object settings;
        /// <summary>Emitter over a text writer and settings.</summary>
        private readonly ConstructorInfo emitter;
        /// <summary>IEmitter.Emit(ParsingEvent).</summary>
        private readonly MethodInfo emit;
        /// <summary>Scalar(anchor, tag, value, style, plainImplicit, quotedImplicit).</summary>
        private readonly ConstructorInfo scalar;
        /// <summary>MappingStart(anchor, tag, implicit, style).</summary>
        private readonly ConstructorInfo mappingStart;
        /// <summary>SequenceStart(anchor, tag, implicit, style).</summary>
        private readonly ConstructorInfo sequenceStart;
        /// <summary>Stateless closing and framing events, shared by all renders.</summary>
        private readonly object mappingEnd, sequenceEnd, streamStart, streamEnd, documentStart, documentEnd;
        /// <summary>Empty anchor and tag values.</summary>
        private readonly object anchor, tag;
        /// <summary>Scalar styles.</summary>
        private readonly object plain, quoted;
        /// <summary>Container styles.</summary>
        private readonly object blockMapping, flowMapping, blockSequence, flowSequence;
        /// <summary>Parser over JSON-compatible flow text, for uncommon value types.</summary>
        private readonly ConstructorInfo parser;
        /// <summary>IParser.MoveNext and Current.</summary>
        private readonly MethodInfo moveNext, current;
        /// <summary>Stream and document framing types skipped when forwarding parsed fallback events.</summary>
        private readonly Type[] framing;

        /// <summary>Loads only the resource whose integrity was verified by the caller.</summary>
        /// <param name="path">Pinned YamlDotNet assembly path.</param>
        internal Runtime(string path)
        {
            var library = new LibraryContext().LoadFromAssemblyPath(Path.GetFullPath(path));
            Type Core(string name) => library.GetType("YamlDotNet.Core." + name, throwOnError: true)!;
            Type Event(string name) => Core("Events." + name);
            object Style(string type, string name) => Enum.Parse(Core(type), name);
            object Create(Type type, params object?[] arguments) => Activator.CreateInstance(type, arguments)!;

            Type settingsType = Core("EmitterSettings");
            settings = settingsType.GetConstructor([typeof(int), typeof(int), typeof(bool), typeof(int), typeof(bool), typeof(bool), typeof(string), typeof(bool)])!
                .Invoke([2, int.MaxValue, false, 1024, false, false, "\n", false]);
            emitter = Core("Emitter").GetConstructor([typeof(TextWriter), settingsType])!;
            emit = Core("IEmitter").GetMethod("Emit")!;

            Type anchorType = Core("AnchorName"), tagType = Core("TagName");
            anchor = anchorType.GetField("Empty")!.GetValue(null)!;
            tag = tagType.GetField("Empty")!.GetValue(null)!;
            Type scalarStyle = Core("ScalarStyle"), mappingStyle = Core("Events.MappingStyle"), sequenceStyle = Core("Events.SequenceStyle");
            plain = Style("ScalarStyle", "Plain"); quoted = Style("ScalarStyle", "DoubleQuoted");
            blockMapping = Style("Events.MappingStyle", "Block"); flowMapping = Style("Events.MappingStyle", "Flow");
            blockSequence = Style("Events.SequenceStyle", "Block"); flowSequence = Style("Events.SequenceStyle", "Flow");
            scalar = Event("Scalar").GetConstructor([anchorType, tagType, typeof(string), scalarStyle, typeof(bool), typeof(bool)])!;
            mappingStart = Event("MappingStart").GetConstructor([anchorType, tagType, typeof(bool), mappingStyle])!;
            sequenceStart = Event("SequenceStart").GetConstructor([anchorType, tagType, typeof(bool), sequenceStyle])!;

            mappingEnd = Create(Event("MappingEnd")); sequenceEnd = Create(Event("SequenceEnd"));
            streamStart = Create(Event("StreamStart")); streamEnd = Create(Event("StreamEnd"));
            // Implicit markers: no leading "---" and no trailing "...".
            documentStart = Event("DocumentStart").GetConstructor([Core("Tokens.VersionDirective"), Core("TagDirectiveCollection"), typeof(bool)])!.Invoke([null, null, true]);
            documentEnd = Create(Event("DocumentEnd"), true);

            parser = Core("Parser").GetConstructor([typeof(TextReader)])!;
            moveNext = Core("IParser").GetMethod("MoveNext")!;
            current = Core("IParser").GetProperty("Current")!.GetMethod!;
            framing = [Event("StreamStart"), Event("StreamEnd"), Event("DocumentStart"), Event("DocumentEnd")];
        }

        /// <summary>Writes one implicit document for a normalized value.</summary>
        /// <param name="writer">Destination text.</param>
        /// <param name="value">Normalized value.</param>
        /// <param name="fallback">Compatibility conversion for uncommon scalar value types.</param>
        internal void Write(TextWriter writer, object? value, Func<object, string> fallback)
        {
            object target = emitter.Invoke([writer, settings]);
            void Emit(object parsingEvent) => emit.Invoke(target, [parsingEvent]);
            int count = 0;
            Emit(streamStart);
            Emit(documentStart);
            Node(Emit, value, fallback, 0, ref count);
            Emit(documentEnd);
            Emit(streamEnd);
        }

        /// <summary>Emits one explicit scalar; strings are plain only when that cannot change their type.</summary>
        /// <param name="emit">Event sink.</param>
        /// <param name="text">Scalar characters.</param>
        /// <param name="isString">Whether the scalar must keep string identity.</param>
        private void Scalar(Action<object> emit, string text, bool isString) =>
            emit(scalar.Invoke([anchor, tag, text, isString && !PlainKeepsString(text) ? quoted : plain, true, isString]));

        /// <summary>Whether a value is emitted as a YAML scalar rather than a container.</summary>
        /// <param name="value">Normalized value.</param>
        private static bool IsScalar(object? value)
        {
            value = CallerMetadata.Unwrap(value);
            return value is not IDictionary and not Array;
        }

        /// <summary>Nested containers holding only scalars use flow style; the root stays block.</summary>
        /// <param name="items">Container entries.</param>
        /// <param name="depth">Container depth.</param>
        private static bool Flow(IEnumerable items, int depth)
        {
            if (depth == 0) return false;
            foreach (object? item in items) if (!IsScalar(item)) return false;
            return true;
        }

        /// <summary>Emits only supported normalized containers; limits defend direct helper callers too.</summary>
        /// <param name="emit">Event sink.</param>
        /// <param name="value">Normalized value.</param>
        /// <param name="fallback">Compatibility conversion for uncommon scalar value types.</param>
        /// <param name="depth">Current structural depth.</param>
        /// <param name="count">Total emitted nodes.</param>
        private void Node(Action<object> emit, object? value, Func<object, string> fallback, int depth, ref int count)
        {
            value = CallerMetadata.Unwrap(value);
            if (++count > 4096 || depth > 48) throw new InvalidDataException("YamlStructureLimit");
            if (value == null) { Scalar(emit, "null", false); return; }
            if (value is string text) { Scalar(emit, text, true); return; }
            if (value is char character) { Scalar(emit, character.ToString(), true); return; }
            if (value is bool boolean) { Scalar(emit, boolean ? "true" : "false", false); return; }
            if (value is IDictionary map)
            {
                emit(mappingStart.Invoke([anchor, tag, true, Flow(map.Values, depth) ? flowMapping : blockMapping]));
                foreach (DictionaryEntry item in map)
                {
                    Scalar(emit, (string)item.Key, true);
                    Node(emit, item.Value, fallback, depth + 1, ref count);
                }
                emit(mappingEnd);
                return;
            }
            if (value is Array array)
            {
                emit(sequenceStart.Invoke([anchor, tag, true, Flow(array, depth) ? flowSequence : blockSequence]));
                foreach (var item in array) Node(emit, item, fallback, depth + 1, ref count);
                emit(sequenceEnd);
                return;
            }
            if (value is Enum enumeration) { Scalar(emit, Convert.ToString(Convert.ChangeType(enumeration, Enum.GetUnderlyingType(value.GetType()), CultureInfo.InvariantCulture), CultureInfo.InvariantCulture)!, false); return; }
            if (value is BigInteger integer) { Scalar(emit, integer.ToString(CultureInfo.InvariantCulture), false); return; }
            if (value is byte or sbyte or short or ushort or int or uint or long or ulong or decimal) { Scalar(emit, Convert.ToString(value, CultureInfo.InvariantCulture)!, false); return; }
            if (value is float or double)
            {
                double number = Convert.ToDouble(value, CultureInfo.InvariantCulture);
                string literal = Convert.ToString(value, CultureInfo.InvariantCulture)!;
                if (!double.IsFinite(number)) { Scalar(emit, literal, true); return; }
                if (!literal.Contains('.') && !literal.Contains('E') && !literal.Contains('e')) literal += ".0";
                Scalar(emit, literal, false);
                return;
            }
            if (value is ValueType)
            {
                // PowerShell owns the uncommon scalar conversion; JSON is a YAML-compatible flow input.
                using var input = new StringReader(fallback(value));
                object source = parser.Invoke([input]);
                while ((bool)moveNext.Invoke(source, null)!)
                {
                    object parsed = current.Invoke(source, null)!;
                    if (Array.IndexOf(framing, parsed.GetType()) < 0) emit(parsed);
                }
                return;
            }
            throw new InvalidDataException("UnsupportedYamlValue");
        }
    }
}
