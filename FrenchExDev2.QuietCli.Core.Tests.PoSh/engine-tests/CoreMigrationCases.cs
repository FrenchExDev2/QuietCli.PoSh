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
            var assembly = new YamlTestContext().LoadFromAssemblyPath(Path.Combine(moduleRoot, "resources", "yaml", "YamlDotNet.dll"));
            object builder = Activator.CreateInstance(assembly.GetType("YamlDotNet.Serialization.DeserializerBuilder", true)!)!;
            builder = builder.GetType().GetMethod("WithAttemptingUnquotedStringTypeDeserialization")!.Invoke(builder, null)!;
            object parser = builder.GetType().GetMethod("Build")!.Invoke(builder, null)!;
            var deserialize = parser.GetType().GetMethods().Single(method => method.Name == "Deserialize" && method.IsGenericMethodDefinition && method.GetParameters().Length == 1 && method.GetParameters()[0].ParameterType == typeof(TextReader));
            using var reader = new StringReader(yaml);
            var parsed = (IDictionary)deserialize.MakeGenericMethod(typeof(object)).Invoke(parser, [reader])!;
            var values = (IList)parsed["values"]!;
            Require(values.Cast<object>().Take(5).SequenceEqual(new object[] { "true", "001", "null", "yes", "é漢🙂\ntext" }), "YAML string identity changed");
            Require((string)((IDictionary)values[5]!)["key: value"]! == "# text" && parsed["none"] == null && (bool)parsed["truth"]!, "YAML nested/null/bool identity changed");
            Require(((IList)parsed["empty"]!).Count == 0 && Convert.ToInt64(parsed["zero"]) == 0, "YAML empty collection or integer changed");
            Require(!AssemblyLoadContext.Default.Assemblies.Any(item => item.GetName().Name == "YamlDotNet"), "YAML dependency escaped its private context");
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
