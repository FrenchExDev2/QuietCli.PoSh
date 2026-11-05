using System.Collections;
using System.Globalization;
using System.Numerics;
using System.Reflection;
using System.Runtime.Loader;

namespace FrenchExDev2.QuietCli;

/// <summary>YamlDotNet emission of an already normalized bounded graph, isolated from user module dependencies.</summary>
public static class BoundedYaml
{
    /// <summary>Private library contexts, containing types only and no caller data.</summary>
    private static readonly Dictionary<string, Runtime> runtimes = new(StringComparer.Ordinal);
    /// <summary>Serializes private-context creation.</summary>
    private static readonly object sync = new();

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
        int count = 0;
        object root = runtime.Node(value, scalarJson, 0, ref count);
        object stream = Activator.CreateInstance(runtime.Stream)!;
        ((IList)runtime.Stream.GetProperty("Documents")!.GetValue(stream)!).Add(Activator.CreateInstance(runtime.Document, root)!);
        using var writer = new StringWriter(CultureInfo.InvariantCulture);
        runtime.Stream.GetMethod("Save", [typeof(TextWriter), typeof(bool)])!.Invoke(stream, [writer, false]);
        string result = writer.ToString().TrimEnd('\r', '\n');
        if (indent == 0) return result;
        string pad = new(' ', indent);
        return pad + result.Replace("\n", "\n" + pad);
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

    /// <summary>Cached low-level YAML node factories; no reflection of caller object properties.</summary>
    private sealed class Runtime
    {
        /// <summary>YAML scalar representation.</summary>
        private readonly Type scalar;
        /// <summary>YAML mapping representation.</summary>
        private readonly Type mapping;
        /// <summary>YAML sequence representation.</summary>
        private readonly Type sequence;
        /// <summary>Scalar style property from the private library.</summary>
        private readonly PropertyInfo style;
        /// <summary>Explicit string quoting prevents implicit boolean/date/number conversion.</summary>
        private readonly object quoted;
        /// <summary>Plain scalar style for null, booleans and numbers.</summary>
        private readonly object plain;
        /// <summary>Private YAML stream representation.</summary>
        internal Type Stream { get; }
        /// <summary>Private YAML document representation.</summary>
        internal Type Document { get; }

        /// <summary>Loads only the resource whose integrity was verified by the caller.</summary>
        /// <param name="path">Pinned YamlDotNet assembly path.</param>
        internal Runtime(string path)
        {
            var library = new LibraryContext().LoadFromAssemblyPath(Path.GetFullPath(path));
            Type Get(string name) => library.GetType("YamlDotNet.RepresentationModel." + name, throwOnError: true)!;
            scalar = Get("YamlScalarNode"); mapping = Get("YamlMappingNode"); sequence = Get("YamlSequenceNode");
            Stream = Get("YamlStream"); Document = Get("YamlDocument");
            style = scalar.GetProperty("Style")!;
            quoted = Enum.Parse(style.PropertyType, "DoubleQuoted"); plain = Enum.Parse(style.PropertyType, "Plain");
        }

        /// <summary>Creates one explicit scalar without implicit string typing.</summary>
        /// <param name="text">Scalar characters.</param>
        /// <param name="isString">Whether quoting must preserve string identity.</param>
        private object Scalar(string text, bool isString)
        {
            object node = Activator.CreateInstance(scalar, text)!;
            style.SetValue(node, isString ? quoted : plain);
            return node;
        }

        /// <summary>Builds only supported normalized containers; limits defend direct helper callers too.</summary>
        /// <param name="value">Normalized value.</param>
        /// <param name="fallback">Compatibility conversion for uncommon scalar value types.</param>
        /// <param name="depth">Current structural depth.</param>
        /// <param name="count">Total emitted nodes.</param>
        internal object Node(object? value, Func<object, string> fallback, int depth, ref int count)
        {
            value = CallerMetadata.Unwrap(value);
            if (++count > 4096 || depth > 48) throw new InvalidDataException("YamlStructureLimit");
            if (value == null) return Scalar("null", false);
            if (value is string text) return Scalar(text, true);
            if (value is char character) return Scalar(character.ToString(), true);
            if (value is bool boolean) return Scalar(boolean ? "true" : "false", false);
            if (value is IDictionary map)
            {
                object node = Activator.CreateInstance(mapping)!;
                var add = mapping.GetMethod("Add", [scalar.BaseType!, scalar.BaseType!])!;
                foreach (DictionaryEntry item in map) add.Invoke(node, [Scalar((string)item.Key, true), Node(item.Value, fallback, depth + 1, ref count)]);
                return node;
            }
            if (value is Array array)
            {
                object node = Activator.CreateInstance(sequence)!;
                var children = (IList)sequence.GetProperty("Children")!.GetValue(node)!;
                foreach (var item in array) children.Add(Node(item, fallback, depth + 1, ref count));
                return node;
            }
            if (value is Enum enumeration) return Scalar(Convert.ToString(Convert.ChangeType(enumeration, Enum.GetUnderlyingType(value.GetType()), CultureInfo.InvariantCulture), CultureInfo.InvariantCulture)!, false);
            if (value is BigInteger integer) return Scalar(integer.ToString(CultureInfo.InvariantCulture), false);
            if (value is byte or sbyte or short or ushort or int or uint or long or ulong or decimal) return Scalar(Convert.ToString(value, CultureInfo.InvariantCulture)!, false);
            if (value is float or double)
            {
                double number = Convert.ToDouble(value, CultureInfo.InvariantCulture);
                string literal = Convert.ToString(value, CultureInfo.InvariantCulture)!;
                if (!double.IsFinite(number)) return Scalar(literal, true);
                if (!literal.Contains('.') && !literal.Contains('E') && !literal.Contains('e')) literal += ".0";
                return Scalar(literal, false);
            }
            if (value is ValueType)
            {
                // PowerShell owns the uncommon scalar conversion; JSON is a YAML-compatible flow input.
                object stream = Activator.CreateInstance(Stream)!;
                using var input = new StringReader(fallback(value));
                Stream.GetMethod("Load", [typeof(TextReader)])!.Invoke(stream, [input]);
                object document = ((IList)Stream.GetProperty("Documents")!.GetValue(stream)!)[0]!;
                return Document.GetProperty("RootNode")!.GetValue(document)!;
            }
            throw new InvalidDataException("UnsupportedYamlValue");
        }
    }
}
