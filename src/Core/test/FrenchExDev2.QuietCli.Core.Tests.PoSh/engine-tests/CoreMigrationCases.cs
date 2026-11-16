using System.Collections;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.Json;
using FrenchExDev2.QuietCli;

/// <summary>Independent invariants for caller-local snapshots, standard YAML and closed direct metadata.</summary>
internal static class CoreMigrationCases
{
    /// <summary>Executes additional cases without creating operating-system processes.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="directory">Private test database directory.</param>
    /// <param name="moduleRoot">Core resource root.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, string directory, string moduleRoot)
    {
        await run("compiled metadata snapshots detach mutable descendants and reject cycles", () =>
        {
            var child = new Hashtable { ["Code"] = "Before" };
            var map = new Hashtable { ["Issues"] = new object[] { child }, ["Source"] = true, ["Native"] = new NativeExecutionSnapshot { ProcessId = 17, Transport = "Pipe" } };
            var frozen = (IDictionary)CallerMetadata.Freeze(map, _ => throw new Exception("Unexpected property adaptation"))!;
            child["Code"] = "After"; map["Source"] = false;
            var issues = (IList)frozen["Issues"]!;
            Require((string)((IDictionary)issues[0]!)["Code"]! == "Before" && (bool)frozen["Source"]!, "Snapshot shares mutable input");
            Require((int)((IDictionary)frozen["Native"]!)["ProcessId"]! == 17, "Native metadata lost");
            bool rejected = false; try { frozen["Source"] = false; } catch (NotSupportedException) { rejected = true; }
            Require(rejected, "Snapshot map is writable");
            map["Cycle"] = map;
            rejected = false; try { CallerMetadata.Freeze(map, _ => throw new Exception()); } catch (InvalidDataException error) when (error.Message == "MetadataSnapshotCycle") { rejected = true; }
            Require(rejected, "Metadata cycle accepted");
            return Task.CompletedTask;
        });
        await run("YamlDotNet preserves quoted strings Unicode scalar types and nested collections", () =>
        {
            var graph = new Hashtable { ["truth"] = true, ["zero"] = 0, ["empty"] = Array.Empty<object>(), ["none"] = null, ["values"] = new object[] { "true", "001", "null", "yes", "é漢🙂\ntext", new Hashtable { ["key: value"] = "# text" } } };
            string yaml = BoundedYaml.Render(graph, moduleRoot, 0, value => JsonSerializer.Serialize(value));
            var parsed = (IDictionary)Load(moduleRoot, yaml)!;
            var values = (IList)parsed["values"]!;
            Require(values.Cast<object>().Take(5).SequenceEqual(new object[] { "true", "001", "null", "yes", "é漢🙂\ntext" }), "YAML string identity changed");
            Require((string)((IDictionary)values[5]!)["key: value"]! == "# text" && parsed["none"] == null && (bool)parsed["truth"]!, "YAML nested/null/bool identity changed");
            Require(((IList)parsed["empty"]!).Count == 0 && Convert.ToInt64(parsed["zero"]) == 0, "YAML empty collection or integer changed");
            Require(!AssemblyLoadContext.Default.Assemblies.Any(item => item.GetName().Name == "YamlDotNet"), "YAML dependency escaped its private context");
            return Task.CompletedTask;
        });
        await run("compact YAML keeps typed-looking and indicator strings in block and flow contexts", () =>
        {
            string[] tricky =
            [
                "true", "False", "YES", "no", "On", "off", "y", "N", "null", "Null", "~", "<<", "=", ".inf", "-.Inf", "+.INF", ".NaN", "NaN", "Infinity",
                "0", "001", "-1", "+1", "1_000", "0x1F", "0o17", "0b101", "1e3", "-1.5e-3", ".5", "1.", "2.56.0", "12:30", "190:20:30", "2026-11-14", "2026-11-14T03:04:05Z",
                "a: b", "a:b", "C:\\code\\x", "- x", "-x", "? q", "?q", ": v", "#c", "x #c", "x# c", "it's", "\"q\"", "[1]", "{a}", "a,b", "a]b", "*ref", "&a", "!t", "%d", "@x", "`x", "|", ">",
                " lead", "trail ", "", " ", "\t", "l1\nl2", "\r", "é漢🙂", "\u0085", "\u2028", "\uFEFFbom", "---", "...", "-", "--- x",
            ];
            var block = new System.Collections.Specialized.OrderedDictionary();
            for (int index = 0; index < tricky.Length; index++) block["k" + index] = tricky[index];
            foreach (string key in tricky) block[key.Length == 0 ? "empty-key" : key] = key;
            // A container child keeps "Block" in block style; the scalar-only "Map" and "List" are emitted in flow style.
            var blockMap = new System.Collections.Specialized.OrderedDictionary();
            foreach (DictionaryEntry entry in block) blockMap[entry.Key] = entry.Value;
            blockMap["nested"] = new object[] { new System.Collections.Specialized.OrderedDictionary() };
            var graph = new System.Collections.Specialized.OrderedDictionary { ["Block"] = blockMap, ["Flow"] = new System.Collections.Specialized.OrderedDictionary { ["Map"] = block, ["List"] = tricky.Cast<object>().ToArray() } };
            string yaml = BoundedYaml.Render(graph, moduleRoot, 0, value => JsonSerializer.Serialize(value));
            Require(!yaml.Contains('\r'), "YAML emitted a raw carriage return");
            Require(yaml.StartsWith("Block:\n", StringComparison.Ordinal) && !yaml.EndsWith("...", StringComparison.Ordinal), "YAML document framing changed: " + yaml[..Math.Min(80, yaml.Length)]);
            var parsed = (IDictionary)Load(moduleRoot, yaml)!;
            foreach (var (name, map) in new[] { ("Block", (IDictionary)parsed["Block"]!), ("Map", (IDictionary)((IDictionary)parsed["Flow"]!)["Map"]!) })
                foreach (DictionaryEntry entry in block)
                    Require(map[entry.Key] is string text && text == (string)entry.Value!, $"{name} string changed for key {JsonSerializer.Serialize(entry.Key)}: {JsonSerializer.Serialize(map[entry.Key])}");
            var list = (IList)((IDictionary)parsed["Flow"]!)["List"]!;
            for (int index = 0; index < tricky.Length; index++)
                Require(list[index] is string text && text == tricky[index], $"Flow sequence string changed: {JsonSerializer.Serialize(tricky[index])} -> {JsonSerializer.Serialize(list[index])}");
            Require(yaml.Contains("\n  k18: Infinity\n") && yaml.Contains("\n  k38: C:\\code\\x\n"), "Safe strings were not emitted plain: " + yaml);
            Require(yaml.Contains("\n  k0: \"true\"\n") && yaml.Contains("\n  k1: \"False\"\n") && yaml.Contains("\n  k34: \"2026-11-14\"\n"), "Typed-looking strings were emitted plain: " + yaml);
            return Task.CompletedTask;
        });
        await run("compact YAML round-trips generated graphs with their scalar types (fuzz)", () =>
        {
            const string alphabet = "aZ09 :#-?,[]{}&*!|>'\"%@`.+_~=\\/\té\n";
            var random = new Random(52817);
            for (int round = 0; round < 300; round++)
            {
                string Text() { var chars = new char[random.Next(0, 9)]; for (int i = 0; i < chars.Length; i++) chars[i] = alphabet[random.Next(alphabet.Length)]; return new string(chars); }
                object? Scalar() => random.Next(6) switch { 0 => null, 1 => random.Next(2) == 0, 2 => random.Next(-1000, 1000), 3 => random.NextDouble() * 100, _ => Text() };
                object? Value(int depth)
                {
                    int kind = depth > 2 ? 0 : random.Next(4);
                    if (kind == 1) { var map = new System.Collections.Specialized.OrderedDictionary(); for (int i = random.Next(0, 5); i > 0; i--) map["k" + map.Count + Text()] = Value(depth + 1); return map; }
                    if (kind == 2) return Enumerable.Range(0, random.Next(0, 5)).Select(_ => Value(depth + 1)).ToArray();
                    return Scalar();
                }
                var graph = new System.Collections.Specialized.OrderedDictionary { ["Root"] = Value(0), ["Leaf"] = new object?[] { Scalar(), Scalar(), Scalar() } };
                string yaml = BoundedYaml.Render(graph, moduleRoot, 0, value => JsonSerializer.Serialize(value));
                string expected = JsonSerializer.Serialize(Canonical(graph));
                string actual = JsonSerializer.Serialize(Canonical(Load(moduleRoot, yaml)));
                Require(expected == actual, $"Round {round}: YAML changed values\n{yaml}\nexpected {expected}\nactual   {actual}");
            }
            return Task.CompletedTask;
        });
        await run("probe identities are canonical collision-safe and sensitive to executable changes", async () =>
        {
            string executable = Path.Combine(directory, "identity-only.bin");
            await File.WriteAllBytesAsync(executable, [1, 2, 3]);
            var first = new System.Collections.Specialized.OrderedDictionary { ["A"] = "1", ["B"] = null };
            var reverse = new System.Collections.Specialized.OrderedDictionary { ["B"] = null, ["A"] = "1" };
            string identity = ProbeIdentity.Build("handler", executable, first);
            Require(identity == ProbeIdentity.Build("handler", executable, reverse), "Environment ordering changed effective identity");
            reverse["B"] = "";
            Require(identity != ProbeIdentity.Build("handler", executable, reverse), "Null override collided with empty text");
            await File.WriteAllBytesAsync(executable, [1, 2, 3, 4]);
            Require(identity != ProbeIdentity.Build("handler", executable, first), "Executable change reused a stale probe");
        });
        await run("direct metadata rejects business fields and recovers without a broken session", async () =>
        {
            await using var engine = await InProcessEngine.CreateAsync(Path.Combine(directory, "direct-metadata.sqlite"), moduleRoot);
            Func<object, IDictionary> noAdapt = _ => throw new Exception("Unexpected caller adaptation");
            var hello = await engine.MetadataAsync(new Hashtable { ["Version"] = 1, ["RequestId"] = "hello", ["Action"] = "hello" }, noAdapt);
            Require(hello.Header != null && hello.HeaderJson == null && hello.Payload.Length == 0, "Hello retained transport JSON");
            foreach (var bad in new object[] { new Hashtable { ["InvocationId"] = "bad", ["Completeness"] = new Hashtable { ["Source"] = 1, ["Analysis"] = true } }, new Hashtable { ["InvocationId"] = "bad", ["Completeness"] = new Hashtable { ["Source"] = null, ["Analysis"] = true } }, new Hashtable { ["InvocationId"] = "bad", ["Data"] = new Hashtable { ["Secret"] = "must-not-be-stored" } }, new Hashtable { ["InvocationId"] = "bad", ["Error"] = new object[] { new Hashtable { ["Code"] = "Known", ["Message"] = "must-not-be-stored" } } } })
            {
                var rejected = await engine.MetadataAsync(new Hashtable { ["Version"] = 1, ["RequestId"] = "reject", ["Action"] = "save", ["Kind"] = "invocation", ["Metadata"] = bad }, noAdapt);
                Require(rejected.Header == null && rejected.HeaderJson!.Contains("\"Ok\":false"), "Closed metadata admitted a business or message field");
            }
            var saved = await engine.MetadataAsync(new Hashtable { ["Version"] = 1, ["RequestId"] = "save", ["Action"] = "save", ["Kind"] = "invocation", ["Metadata"] = new Hashtable { ["InvocationId"] = "direct-safe", ["Context"] = "direct-context", ["Outcome"] = "Success" } }, noAdapt);
            Require(saved.Header != null && saved.HeaderJson == null, "Valid typed save failed after rejection");
            using var query = JsonDocument.Parse(JsonSerializer.Serialize(new { Version = 1, RequestId = "query", Action = "query", From = 0, To = DateTimeOffset.UtcNow.AddDays(1).ToUnixTimeMilliseconds(), Context = "direct-context" }));
            var result = await engine.RequestAsync(JsonSerializer.SerializeToUtf8Bytes(query.RootElement), []);
            using var reply = JsonDocument.Parse(result.HeaderJson!);
            Require(reply.RootElement.GetProperty("Data").GetProperty("Rows").GetArrayLength() == 1, "Typed save/query counter identity changed");
        });
    }

    /// <summary>Lazily loaded independent deserializer, with implicit typing of unquoted scalars enabled.</summary>
    private static (object Parser, MethodInfo Deserialize)? deserializer;

    /// <summary>Reads YAML with the shipped codec in an independent context; unquoted scalars resolve to typed values.</summary>
    /// <param name="moduleRoot">Core resource root.</param>
    /// <param name="yaml">Rendered text.</param>
    private static object? Load(string moduleRoot, string yaml)
    {
        if (deserializer is null)
        {
            var assembly = new YamlTestContext().LoadFromAssemblyPath(Path.Combine(moduleRoot, "resources", "yaml", "YamlDotNet.dll"));
            object builder = Activator.CreateInstance(assembly.GetType("YamlDotNet.Serialization.DeserializerBuilder", true)!)!;
            builder = builder.GetType().GetMethod("WithAttemptingUnquotedStringTypeDeserialization")!.Invoke(builder, null)!;
            object parser = builder.GetType().GetMethod("Build")!.Invoke(builder, null)!;
            var method = parser.GetType().GetMethods().Single(method => method.Name == "Deserialize" && method.IsGenericMethodDefinition && method.GetParameters().Length == 1 && method.GetParameters()[0].ParameterType == typeof(TextReader));
            deserializer = (parser, method.MakeGenericMethod(typeof(object)));
        }
        using var reader = new StringReader(yaml);
        return deserializer.Value.Deserialize.Invoke(deserializer.Value.Parser, [reader]);
    }

    /// <summary>Type-preserving comparable form: strings stay strings, numbers become invariant decimal text.</summary>
    /// <param name="value">Source graph or parsed graph.</param>
    private static object? Canonical(object? value) => value switch
    {
        null => null,
        string text => "s:" + text,
        bool boolean => boolean,
        // Keys, then the indexer: generic dictionaries enumerate KeyValuePair through IEnumerable.
        IDictionary map => map.Keys.Cast<object>().Select(key => new object?[] { Canonical(key), Canonical(map[key]) }).ToArray(),
        IEnumerable sequence => sequence.Cast<object?>().Select(Canonical).ToArray(),
        // The oracle's unquoted-scalar typing reads fractions as single precision; compare at that precision.
        double or float => "f:" + ((float)Convert.ToDouble(value, System.Globalization.CultureInfo.InvariantCulture)).ToString("R", System.Globalization.CultureInfo.InvariantCulture),
        _ => "n:" + Convert.ToDouble(value, System.Globalization.CultureInfo.InvariantCulture).ToString("R", System.Globalization.CultureInfo.InvariantCulture),
    };

    /// <summary>Provides an independent parser context for semantic YAML assertions.</summary>
    private sealed class YamlTestContext : AssemblyLoadContext
    {
        /// <summary>Uses only framework dependency fallback.</summary>
        /// <param name="name">Requested dependency.</param>
        protected override Assembly? Load(AssemblyName name) => null;
    }
    /// <summary>Fails a case on an independently specified invariant.</summary>
    /// <param name="condition">Expected condition.</param>
    /// <param name="message">Bounded diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
