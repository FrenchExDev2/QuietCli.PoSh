using System.Text;
using System.Text.Json;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Storage;

/// <summary>Independent bounded YAML and transactional delivery-counter regressions.</summary>
internal static class ConfigurationDeliveryCases
{
    /// <summary>Runs generated parser inputs and independent SQLite expectations.</summary>
    /// <param name="run">Shared structured case runner.</param>
    /// <param name="yamlLibrary">Verified dependency used by the product parser.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, string yamlLibrary)
    {
        string root = Path.Combine(Path.GetTempPath(), "quiet-config-cases-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        string input = Path.Combine(root, "config.yaml");
        await run("YAML generated scalars preserve Unicode, types and diagnostic marks", async () => {
            var random = new Random(47291);
            for (int i = 0; i < 64; i++) {
                long value = random.Next(256, 100000);
                await File.WriteAllTextAsync(input, $"schemaVersion: 1\ndelivery:\n  maxOutputBytes: {value}\ntelemetry:\n  database: \"é-漢字-{i}.sqlite\"\n", new UTF8Encoding(false));
                var parsed = await ConfigurationYaml.ReadAsync(input, yamlLibrary);
                var section = (Dictionary<string, ConfigurationValue>)parsed["delivery"].Value!;
                Check(section["maxOutputBytes"].Value is long number && number == value, "YamlIntegerChanged");
                Check(section["maxOutputBytes"].Line > 0 && section["maxOutputBytes"].Column > 0, "YamlLocationMissing");
                var telemetry = (Dictionary<string, ConfigurationValue>)parsed["telemetry"].Value!;
                Check((string)telemetry["database"].Value! == $"é-漢字-{i}.sqlite", "YamlUnicodeChanged");
            }
        });
        await run("YAML malformed corpus rejects aliases, duplicates, tags, nesting and oversized UTF8", async () => {
            string[] corpus = ["schemaVersion: 1\nschemaVersion: 1\n", "a: &x 1\nb: *x\n", "a: !!str value\n", "a: [1,2]\n", "a: {x: 1, x: 2}\n", "---\na: 1\n---\nb: 2\n", "a: [", "schemaVersion: 1\n#" + new string('x', 65537), string.Concat(Enumerable.Range(0, 12).Select(i => new string(' ', i * 2) + "a:\n"))];
            foreach (string text in corpus) {
                await File.WriteAllTextAsync(input, text, new UTF8Encoding(false));
                bool rejected = false;
                try { await ConfigurationYaml.ReadAsync(input, yamlLibrary); } catch (ConfigurationYamlException) { rejected = true; }
                Check(rejected, "MalformedYamlAccepted");
            }
            await File.WriteAllBytesAsync(input, [0xff, 0xfe, 0xff]);
            bool utf8Rejected = false;
            try { await ConfigurationYaml.ReadAsync(input, yamlLibrary); } catch (DecoderFallbackException) { utf8Rejected = true; }
            Check(utf8Rejected, "InvalidUtf8Accepted");
        });
        await run("SQLite keeps one delivery, its initial profile and separate encoding measurements", async () => {
            string databasePath = Path.Combine(root, "unique.sqlite");
            await using var store = new MeasurementStore(databasePath);
            var delivery = new MeasurementRecord("root", Role: "Business", DeliveryId: "delivery", OutputBytes: 64, OutputTokens: 9, TokenProfile: "o200k_base", TokenVersion: "test-v1", Format: "json", TokenMeasurements: [new("o200k_base", "test-v1", 9)]);
            await store.SaveAsync(delivery, "delivery");
            await store.SaveAsync(delivery with { OutputTokens = 11, TokenProfile = "cl100k_base", TokenMeasurements = [new("cl100k_base", "test-v1", 11)] }, "delivery");
            await store.SaveAsync(delivery with { OutputTokens = 11, TokenProfile = "cl100k_base", TokenMeasurements = [new("cl100k_base", "test-v1", 11)] }, "delivery");
            using var database = new Database(databasePath, false);
            Check((long)database.Query("SELECT COUNT(*) AS n FROM quiet2_events", [])[0]["n"] == 1, "DeliveryDuplicated");
            Check((long)database.Query("SELECT COUNT(*) AS n FROM quiet2_delivery_tokens", [])[0]["n"] == 2, "TokenProfileLostOrDuplicated");
            var initial = JsonSerializer.Deserialize<MeasurementRecord>((string)database.Query("SELECT payload FROM quiet2_events", [])[0]["payload"])!;
            Check(initial.TokenProfile == "o200k_base" && initial.OutputTokens == 9, "InitialMeasurementRewritten");
            var report = await store.GainAsync(new GainSelection(0, long.MaxValue));
            var json = JsonSerializer.SerializeToElement(report.Summary);
            Check(json.GetProperty("RootDeliveries").GetInt32() == 1 && json.GetProperty("RootDeliveryBytes").GetInt64() == 64, "UniqueDeliveryCountersChanged");
            var profiles = json.GetProperty("DeliveredTokensByProfile").EnumerateArray().ToArray();
            Check(profiles.Length == 2 && profiles.All(p => p.GetProperty("MeasuredDeliveries").GetInt32() == 1 && p.GetProperty("CoverageComplete").GetBoolean()), "TokenCoverageChanged");
        });
        await run("token conflicts roll back the entire SQLite measurement transaction", async () => {
            string databasePath = Path.Combine(root, "atomic.sqlite");
            await using var store = new MeasurementStore(databasePath);
            var delivery = new MeasurementRecord("root", DeliveryId: "delivery", OutputBytes: 3, Format: "yaml", TokenMeasurements: [new("o200k_base", "v1", 1)]);
            await store.SaveAsync(delivery, "delivery");
            bool rejected = false;
            try { await store.SaveAsync(delivery with { TokenMeasurements = [new("cl100k_base", "v1", 2), new("o200k_base", "v1", 99)] }, "delivery"); }
            catch (InvalidDataException error) when (error.Message == "TokenMeasurementConflict") { rejected = true; }
            Check(rejected, "ConflictingTokensAccepted");
            using var database = new Database(databasePath, false);
            Check((long)database.Query("SELECT COUNT(*) AS n FROM quiet2_delivery_tokens", [])[0]["n"] == 1, "PartialTokenTransactionCommitted");
        });
        await run("historical deliveries retain incomplete token coverage without rewriting history", async () => {
            string databasePath = Path.Combine(root, "historical.sqlite");
            using (var database = new Database(databasePath, true)) {
                var metadata = JsonSerializer.Serialize(new MeasurementRecord("legacy", DeliveryId: "legacy-delivery", OutputBytes: 8));
                database.Execute("INSERT INTO quiet2_events(id,kind,timestamp_ms,payload) VALUES(?,?,?,?)", ["legacy-delivery", "delivery", 1L, metadata]);
            }
            await using var store = new MeasurementStore(databasePath);
            var before = JsonSerializer.SerializeToElement((await store.GainAsync(new GainSelection(0, long.MaxValue))).Summary);
            Check(before.GetProperty("DeliveredTokensByProfile").GetArrayLength() == 0, "UnknownHistoricalTokensInvented");
            using (var database = new Database(databasePath, false)) Check(database.Query("SELECT name FROM sqlite_master WHERE name='quiet2_delivery_tokens'", []).Count == 0, "HistoricalReadMigratedDatabase");
            await store.SaveAsync(new MeasurementRecord("new", DeliveryId: "new-delivery", OutputBytes: 4, TokenMeasurements: [new("o200k_base", "v1", 2)]), "delivery");
            var report = JsonSerializer.SerializeToElement((await store.GainAsync(new GainSelection(0, long.MaxValue))).Summary);
            var profile = report.GetProperty("DeliveredTokensByProfile")[0];
            Check(report.GetProperty("RootDeliveries").GetInt32() == 2 && profile.GetProperty("UnmeasuredDeliveries").GetInt32() == 1 && !profile.GetProperty("CoverageComplete").GetBoolean(), "HistoricalCoverageInvented");
        });
    }
    /// <summary>Raises an independently named business invariant failure.</summary>
    /// <param name="condition">Independent expected behavior.</param>
    /// <param name="message">Regression identity.</param>
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
}
