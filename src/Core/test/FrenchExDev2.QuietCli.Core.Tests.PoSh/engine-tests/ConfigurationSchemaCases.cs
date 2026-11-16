using System.Text;
using FrenchExDev2.QuietCli;

/// <summary>Independent boundary, property and template assertions for the shared configuration schema.</summary>
internal static class ConfigurationSchemaCases
{
    /// <summary>Fixed seed retained so any failing generated value can be replayed deterministically.</summary>
    private const int Seed = 20261108;

    // Oracle table written literally on purpose: it must not be read from the implementation.
    private static readonly (string Key, double Min, double Max, bool Integer)[] Numeric =
    [
        ("delivery.maxOutputBytes", 256, int.MaxValue, true),
        ("delivery.maxItems", 0, int.MaxValue, true),
        ("delivery.maxTrackedRepresentations", 1, 65536, true),
        ("execution.timeoutSeconds", 0.001, 4294967.294, false),
        ("execution.drainTimeoutSeconds", 0.05, 300, false),
        ("engine.ipcTimeoutSeconds", 0.05, 300, false),
        ("streams.maxRecordBytes", 1, int.MaxValue, true),
        ("streams.readBlockBytes", 1024, 16384, true),
        ("gain.maxEvents", 1, 1000000, true),
    ];

    /// <summary>Runs the schema cases that need no external library.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run)
    {
        await run("configuration schema keeps the closed key set, sections and numeric ranges", () =>
        {
            var keys = ConfigurationSchema.Rules().Select(rule => rule.Key).ToArray();
            Require(keys.Length == 19 && keys.Distinct().Count() == 19, "Schema key count changed");
            Require(string.Join(",", ConfigurationSchema.Sections) == "tokenization,delivery,execution,telemetry,engine,streams,recall,gain", "Section list changed");
            Require(keys.All(key => ConfigurationSchema.Sections.Contains(key[..key.IndexOf('.')])), "A key lies outside the sections");
            foreach (var (key, min, max, integer) in Numeric)
            {
                var rule = ConfigurationSchema.Find(key)!;
                Require(rule.Min == min && rule.Max == max && rule.Type == (integer ? "integer" : "number"), $"Range or type changed: {key}");
            }
            Require(ConfigurationSchema.Find("Delivery.maxItems") == null && ConfigurationSchema.Find("delivery.unknown") == null, "Lookup is not exact");
            return Task.CompletedTask;
        });
        await run("configuration numbers accept inclusive bounds and reject just-outside values with stable codes", () =>
        {
            foreach (var (key, min, max, integer) in Numeric)
            {
                var rule = ConfigurationSchema.Find(key)!;
                foreach (double inside in new[] { min, max })
                    Require(Convert(rule, integer ? (object)(long)inside : inside) is not null, $"Boundary rejected: {key} {inside}");
                double below = integer ? min - 1 : min - Math.Max(min, 1) / 1000, above = integer ? max + 1 : max + max / 1000;
                foreach (double outside in new[] { below, above })
                    Expect("InvalidConfigurationNumber", rule, integer ? (object)(long)outside : outside);
                foreach (object? bad in new object?[] { double.NaN, double.PositiveInfinity, double.NegativeInfinity, true, "10", null })
                    Expect("InvalidConfigurationNumber", rule, bad);
            }
            Expect("InvalidConfigurationInteger", ConfigurationSchema.Find("delivery.maxItems")!, 5.0);
            Expect("InvalidConfigurationInteger", ConfigurationSchema.Find("gain.maxEvents")!, 5.5m);
            Require(Convert(ConfigurationSchema.Find("delivery.maxItems")!, 7L) is int, "Integer result is not Int32");
            Require(Convert(ConfigurationSchema.Find("execution.timeoutSeconds")!, 7L) is double, "Number result is not Double");
            return Task.CompletedTask;
        });
        await run("generated configuration numbers are accepted exactly when they lie inside their range", () =>
        {
            var random = new Random(Seed);
            for (int iteration = 0; iteration < 3000; iteration++)
            {
                var (key, min, max, integer) = Numeric[random.Next(Numeric.Length)];
                var rule = ConfigurationSchema.Find(key)!;
                double span = Math.Min(max - min, 1e7);
                double candidate = integer ? Math.Floor(min - 5 + random.NextDouble() * (span + 10)) : min - 1 + random.NextDouble() * (span + 2);
                object value = integer ? (object)(long)candidate : candidate;
                bool inside = candidate >= min && candidate <= max;
                string where = $"seed={Seed} iteration={iteration} key={key} value={candidate}";
                if (inside) Require(Convert(rule, value) is not null, "Inside value rejected: " + where);
                else Expect("InvalidConfigurationNumber", rule, value, where);
            }
            return Task.CompletedTask;
        });
        await run("configuration enums, booleans, paths and recall sizes keep their stable codes", () =>
        {
            var tokenizer = ConfigurationSchema.Find("tokenization.tokenizer")!;
            Require((string)Convert(tokenizer, "cl100k_base")! == "cl100k_base", "Valid enum rejected");
            foreach (object? bad in new object?[] { "O200K_BASE", "gpt2", "", 1L, true, null }) Expect("InvalidConfigurationEnum", tokenizer, bad);
            var flag = ConfigurationSchema.Find("telemetry.enabled")!;
            Require(Convert(flag, false) is false, "False rejected");
            foreach (object? bad in new object?[] { "true", 1L, null }) Expect("InvalidConfigurationBoolean", flag, bad);
            var database = ConfigurationSchema.Find("telemetry.database")!;
            foreach (object? bad in new object?[] { "", "  ", 3L, null }) Expect("InvalidConfigurationPath", database, bad);
            var root = ConfigurationSchema.Find("recall.root")!;
            Require(Convert(root, null) == null, "Null optional path rejected");
            Expect("InvalidConfigurationPath", root, " ");
            var size = ConfigurationSchema.Find("recall.maxBytes")!;
            foreach (object good in new object[] { "16MiB", "All", "1", 4096L, 8 }) Require(Convert(size, good) is string, "Valid recall size rejected");
            Require((string)Convert(size, 4096L)! == "4096", "Numeric recall size not rendered as invariant text");
            foreach (object? bad in new object?[] { 1.5, true, null }) Expect("InvalidConfigurationRecallSize", size, bad);
            bool invalid = false;
            try { Convert(size, "0MiB"); } catch (ArgumentException error) when (error.Message == "InvalidRecallSize") { invalid = true; }
            Require(invalid, "Malformed recall size accepted");
            return Task.CompletedTask;
        });
        await run("configuration paths expand only the home prefix and resolve against the source directory", () =>
        {
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), baseDirectory = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "quiet-schema-base"));
            Require(ConfigurationSchema.ResolvePath("~", baseDirectory) == Path.GetFullPath(home), "Bare home marker not expanded");
            Require(ConfigurationSchema.ResolvePath("~/a/b", baseDirectory) == Path.GetFullPath(Path.Combine(home, "a", "b")), "Slash home prefix not expanded");
            Require(ConfigurationSchema.ResolvePath("~\\a", baseDirectory) == Path.GetFullPath(Path.Combine(home, "a")), "Backslash home prefix not expanded");
            Require(ConfigurationSchema.ResolvePath("~user/x", baseDirectory) == Path.GetFullPath(Path.Combine(baseDirectory, "~user", "x")), "Other-user form must stay literal");
            Require(ConfigurationSchema.ResolvePath("sub/é漢字.sqlite", baseDirectory) == Path.GetFullPath(Path.Combine(baseDirectory, "sub", "é漢字.sqlite")), "Relative path not resolved");
            Require(ConfigurationSchema.ResolvePath("$HOME/x", baseDirectory) == Path.GetFullPath(Path.Combine(baseDirectory, "$HOME", "x")), "Environment text must stay literal");
            return Task.CompletedTask;
        });
        await run("configuration template is complete, LF-only and lists every default in schema order", () =>
        {
            string template = ConfigurationSchema.RenderTemplate();
            Require(template.StartsWith("schemaVersion: 1\ntokenization:\n  tokenizer: \"o200k_base\"\n", StringComparison.Ordinal) && template.EndsWith("\n") && !template.Contains('\r'), "Template header or line endings changed");
            string[] lines = template[..^1].Split('\n');
            Require(lines.Length == 1 + ConfigurationSchema.Sections.Count + 19, "Template line count changed");
            Require(lines.Where(line => !line.StartsWith(' ') && line.EndsWith(':')).Select(line => line[..^1]).SequenceEqual(ConfigurationSchema.Sections), "Template sections out of order");
            foreach (string expected in new[] { "  maxOutputBytes: 4096", "  timeoutSeconds: 600.0", "  drainTimeoutSeconds: 30.0", "  enabled: true", "  hosting: \"Auto\"", "  maxBytes: \"16MiB\"", "  root: null", "  maxEvents: 10000", "  ipcTimeoutSeconds: 30.0" })
                Require(lines.Contains(expected), "Template line missing: " + expected);
            Require(lines.Any(line => line.StartsWith("  database: \"", StringComparison.Ordinal) && line.EndsWith("gains.sqlite\"", StringComparison.Ordinal)), "Database default missing");
            return Task.CompletedTask;
        });
    }

    /// <summary>Parses the generated template with the product YAML reader and validates every value as a configuration file.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="yamlLibrary">Verified YAML dependency path.</param>
    internal static async Task RunRoundTripAsync(Func<string, Func<Task>, Task> run, string yamlLibrary)
    {
        await run("configuration template round-trips through the YAML reader to the schema defaults", async () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "quiet-schema-roundtrip-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            string file = Path.Combine(directory, "config.yaml");
            await File.WriteAllTextAsync(file, ConfigurationSchema.RenderTemplate(), new UTF8Encoding(false));
            var document = await ConfigurationYaml.ReadAsync(file, yamlLibrary);
            Require(document["schemaVersion"].Value is long version && version == 1, "Template schema version lost");
            foreach (var rule in ConfigurationSchema.Rules())
            {
                int dot = rule.Key.IndexOf('.');
                var section = (Dictionary<string, ConfigurationValue>)document[rule.Key[..dot]].Value!;
                object? actual = ConfigurationSchema.Convert(rule, section[rule.Key[(dot + 1)..]].Value, directory);
                object? expected = rule.Type is "path" ? ConfigurationSchema.ResolvePath((string)rule.Default!, directory) : rule.Type is "integer" ? System.Convert.ToInt32(rule.Default) : rule.Default;
                Require(Equals(actual, expected), $"Template value differs from the default: {rule.Key} actual={actual} expected={expected}");
            }
            Directory.Delete(directory, true);
        });
    }

    private static object? Convert(ConfigurationRule rule, object? value) => ConfigurationSchema.Convert(rule, value, Path.GetTempPath());

    private static void Expect(string code, ConfigurationRule rule, object? value, string context = "")
    {
        try { Convert(rule, value); }
        catch (InvalidDataException error) when (error.Message == code) { return; }
        catch (Exception error) { throw new Exception($"Expected {code} but got {error.Message} for {rule.Key} {value} {context}"); }
        throw new Exception($"Expected {code} but value was accepted for {rule.Key} {value} {context}");
    }

    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
