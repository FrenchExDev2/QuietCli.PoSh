using System.Collections;
using System.Text;
using System.Text.Json;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent grammar loading, caching and binding-equivalence invariants.</summary>
internal static class SchemaCases
{
    /// <summary>Registers generated, boundary and malformed campaigns.</summary>
    /// <param name="test">Existing compiled runner.</param>
    /// <param name="schemaPath">Path of the module grammar under test.</param>
    internal static void Run(Action<string, Action> test, string? schemaPath)
    {
        test("schema store loads the module grammar once and keeps keys case-insensitive", () =>
        {
            using var root = Root(schemaPath);
            GitArgumentSchemaStore.Root = root.Path;
            var first = GitArgumentSchemaStore.Load();
            Require(first is not null && ReferenceEquals(first, GitArgumentSchemaStore.Load()), "Grammar not cached");
            Require(first!["Commands"] is IDictionary && first["Profiles"] is IDictionary && first["commands"] is null && first["PROFILES"] is null, "Top-level keys are not case-sensitive");
            using var other = Root(schemaPath);
            GitArgumentSchemaStore.Root = other.Path;
            Require(!ReferenceEquals(first, GitArgumentSchemaStore.Load()), "Cache survived a root change");
            GitArgumentSchemaStore.Root = null;
            Require(GitArgumentSchemaStore.Load() is null, "Unset root produced a grammar");
        });
        test("schema store reports a missing or oversized file explicitly", () =>
        {
            string empty = Directory.CreateTempSubdirectory("git-schema-").FullName;
            try
            {
                GitArgumentSchemaStore.Root = empty;
                Require(GitArgumentSchemaStore.Load() is null, "Missing file produced a grammar");
                Directory.CreateDirectory(Path.Combine(empty, "metadata"));
                using (var big = File.Create(Path.Combine(empty, GitArgumentSchemaStore.RelativePath))) big.SetLength(4 * 1024 * 1024 + 1);
                bool rejected = false; try { GitArgumentSchemaStore.Load(); } catch (InvalidDataException error) { rejected = error.Message == "GitArgumentSchemaTooLarge"; }
                Require(rejected, "Oversized grammar accepted");
            }
            finally { GitArgumentSchemaStore.Root = null; Directory.Delete(empty, true); }
        });
        test("schema parsing rejects duplicate keys, non-objects and excessive nesting, yet keeps keys that differ by case", () =>
        {
            var cased = GitArgumentSchemaStore.Parse("{\"-C\":1,\"-c\":2}");
            Require(cased.Count == 2 && cased["-C"] is 1L && cased["-c"] is 2L, "Keys differing only by case were merged");
            foreach (string bad in new[] { "{\"a\":1,\"a\":2}", "[]", "1", "null", "\"x\"" })
            {
                bool rejected = false; try { GitArgumentSchemaStore.Parse(bad); } catch (Exception error) when (error is InvalidDataException or JsonException) { rejected = true; }
                Require(rejected, $"Malformed grammar accepted: {bad}");
            }
            string deep = string.Concat(Enumerable.Repeat("{\"a\":", 41)) + "1" + new string('}', 41);
            bool tooDeep = false; try { GitArgumentSchemaStore.Parse(deep); } catch (JsonException) { tooDeep = true; }
            Require(tooDeep, "Nesting beyond 40 accepted");
            var scalars = GitArgumentSchemaStore.Parse("{\"n\":3,\"f\":1.5,\"t\":true,\"z\":null,\"l\":[\"a\",2]}");
            Require(scalars["n"] is 3L && scalars["f"] is 1.5 && scalars["t"] is true && scalars["z"] is null && scalars["l"] is object?[] { Length: 2 }, "Scalar conversion changed");
        });
        test("schema fuzz: mutated grammar text never throws anything but a declared parse failure (seed 77101, 3000 inputs)", () =>
        {
            string text = File.ReadAllText(Require(schemaPath), Encoding.UTF8); var random = new Random(77101);
            for (int i = 0; i < 3000; i++)
            {
                var chars = text.ToCharArray(); string candidate;
                switch (random.Next(3))
                {
                    case 0: candidate = text[..random.Next(text.Length)]; break;
                    case 1: chars[random.Next(chars.Length)] = "{}[]\",:\\0é"[random.Next(10)]; candidate = new string(chars); break;
                    default: int at = random.Next(text.Length); candidate = text.Remove(at, Math.Min(random.Next(1, 20), text.Length - at)); break;
                }
                try { GitArgumentSchemaStore.Parse(candidate); }
                catch (Exception error) when (error is InvalidDataException or JsonException) { }
            }
        });
        test("schema binding through the store equals binding through an independently read grammar (seed 77102, 2000 vectors)", () =>
        {
            string text = File.ReadAllText(Require(schemaPath), Encoding.UTF8);
            using var document = JsonDocument.Parse(text);
            var independent = (IDictionary)Read(document.RootElement)!;
            var loaded = GitArgumentSchemaStore.Parse(text);
            var commands = ((IDictionary)independent["Commands"]!).Keys.Cast<string>().OrderBy(name => name, StringComparer.Ordinal).ToArray();
            Require(commands.Length > 0, "Grammar declares no command");
            foreach (string command in commands) Require(GitArguments.Bind(command, [], null, independent).Complete == GitArguments.Bind(command, [], null, loaded).Complete, $"Policy resolution diverged: {command}");
            Require(commands.Count(command => GitArguments.Bind(command, [], null, loaded).Complete) > 0, "No declared command resolves a policy");
            var random = new Random(77102); string[] alphabet = ["-a", "-n", "-n2", "--all", "--", "-", "--author", "--format=x", "--no-all", "path", "", "é", "-C", "--unknown", "-3"];
            for (int i = 0; i < 2000; i++)
            {
                string command = commands[random.Next(commands.Length)];
                string?[] argv = Enumerable.Range(0, random.Next(0, 7)).Select(_ => alphabet[random.Next(alphabet.Length)]).ToArray();
                var expected = GitArguments.Bind(command, argv, "2.56.0", independent); var actual = GitArguments.Bind(command, argv, "2.56.0", loaded);
                Require(expected.Complete == actual.Complete && expected.EmitArguments.SequenceEqual(actual.EmitArguments) && expected.Tokens.Select(Key).SequenceEqual(actual.Tokens.Select(Key)), $"Binding diverged for {command} at seed 77102 index {i}");
            }
        });
    }

    /// <summary>Summarizes a bound unit independently of reference identity.</summary>
    /// <param name="unit">Bound unit.</param>
    private static string Key(GitArgumentUnit unit) => $"{unit.Kind}|{unit.Name}|{unit.Value}|{unit.HasValue}|{unit.Binding}|{unit.Position}|{unit.Span}|{string.Join('\u0001', unit.EmitArguments)}";

    /// <summary>Copies the grammar under a temporary module root.</summary>
    /// <param name="schemaPath">Source grammar.</param>
    private static TempRoot Root(string? schemaPath)
    {
        var root = new TempRoot();
        Directory.CreateDirectory(Path.Combine(root.Path, "metadata"));
        File.Copy(Require(schemaPath), Path.Combine(root.Path, GitArgumentSchemaStore.RelativePath));
        return root;
    }

    /// <summary>Reads fixture JSON into ordinary ordinal containers, outside the production loader.</summary>
    /// <param name="element">Fixture value.</param>
    private static object? Read(JsonElement element) => element.ValueKind switch
    {
        JsonValueKind.Object => Map(element),
        JsonValueKind.Array => element.EnumerateArray().Select(Read).ToArray(),
        JsonValueKind.String => element.GetString(),
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.Number => element.GetInt64(),
        _ => null,
    };

    /// <summary>Reads a fixture map with ordinal keys.</summary>
    /// <param name="element">Fixture map.</param>
    private static IDictionary Map(JsonElement element) { var result = new Hashtable(StringComparer.Ordinal); foreach (var item in element.EnumerateObject()) result[item.Name] = Read(item.Value); return result; }

    /// <summary>Requires the grammar path supplied by the runner.</summary>
    /// <param name="path">Optional argument.</param>
    private static string Require(string? path) => path ?? throw new Exception("Module schema path required");

    /// <summary>Asserts an independently stated observable property.</summary>
    /// <param name="condition">Expected property.</param>
    /// <param name="message">Bounded diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }

    /// <summary>Temporary module root removed on dispose.</summary>
    private sealed class TempRoot : IDisposable
    {
        /// <summary>Absolute directory path.</summary>
        public string Path { get; } = Directory.CreateTempSubdirectory("git-schema-").FullName;

        /// <inheritdoc />
        public void Dispose() { try { Directory.Delete(Path, true); } catch (IOException) { } }
    }
}
