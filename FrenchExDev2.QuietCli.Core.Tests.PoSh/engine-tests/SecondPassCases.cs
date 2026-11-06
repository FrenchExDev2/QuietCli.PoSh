using System.Text;
using System.Text.Json;
using FrenchExDev2.QuietCli;

/// <summary>Independent invariants for compiled text framing and metadata aggregation.</summary>
internal static class SecondPassCases
{
    /// <summary>Runs six domain assertions through the existing companion case runner.</summary>
    /// <param name="run">Existing case runner.</param>
    /// <param name="store">Isolated test measurement store.</param>
    /// <param name="directory">Owned fixture directory.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, MeasurementStore store, string directory)
    {
        await run("text framing preserves UTF8 at every byte split and empty records", () =>
        {
            byte[] bytes = Encoding.UTF8.GetBytes("é漢🙂<END><END>fin");
            for (int split = 0; split <= bytes.Length; split++)
            {
                using var state = new TextStreamState("<END>", 1024);
                var records = state.Frame(state.Decode(bytes[..split])).ToList();
                records.AddRange(state.Frame(state.Decode(bytes[split..])));
                Check(records.SequenceEqual(new[] { "é漢🙂", "" }) && state.Finish() == "fin", "Fragmented text or final record changed");
            }
            return Task.CompletedTask;
        });
        await run("text framing handles overlapping and split delimiters", () =>
        {
            using var state = new TextStreamState("aba", 32); var records = new List<string>();
            foreach (byte value in Encoding.UTF8.GetBytes("ababaXabaY")) records.AddRange(state.Frame(state.Decode([value])));
            Check(records.SequenceEqual(new[] { "", "baX" }) && state.Finish() == "Y", "Delimiter overlap changed record boundaries");
            using var chunks = new TextStreamState(null, 1);
            Check(chunks.Decode(Encoding.UTF8.GetBytes("é漢🙂")) == "é漢🙂" && chunks.Finish() == "", "Chunk mode duplicated text or applied a record limit");
            return Task.CompletedTask;
        });
        await run("text record limits count UTF8 bytes and exclude only complete delimiters", () =>
        {
            using var exact = new TextStreamState("|", 4);
            Check(exact.Frame(exact.Decode(Encoding.UTF8.GetBytes("🙂|"))).Single() == "🙂", "Exact Unicode byte limit rejected");
            using var fullDelimiter = new TextStreamState("abc", 1);
            Check(fullDelimiter.Frame("xabc").Single() == "x", "A complete delimiter counted as record bytes");
            foreach (var test in new[] { (Text: "é", Delimiter: "|", Maximum: 1), (Text: "xab", Delimiter: "abc", Maximum: 1), (Text: "xxabc", Delimiter: "abc", Maximum: 1) })
            {
                using var state = new TextStreamState(test.Delimiter, test.Maximum);
                bool rejected = false;
                try { _ = state.Frame(test.Text).ToArray(); } catch (InvalidDataException error) when (error.Message == "RecordTooLarge") { rejected = true; }
                Check(rejected, "Oversized record or unfinished delimiter fragment accepted");
            }
            return Task.CompletedTask;
        });
        await run("strict text decoding rejects invalid bytes and incomplete EOF", () =>
        {
            using var invalid = new TextStreamState(null, 32);
            bool rejected = false; try { invalid.Decode([255]); } catch (DecoderFallbackException) { rejected = true; }
            Check(rejected, "Invalid UTF8 accepted");
            using var incomplete = new TextStreamState("\n", 32);
            Check(incomplete.Decode([226, 130]) == "", "Incomplete code point was replaced");
            rejected = false; try { incomplete.Finish(); } catch (DecoderFallbackException) { rejected = true; }
            Check(rejected, "Incomplete EOF accepted");
            return Task.CompletedTask;
        });
        await run("gain deduplicates sources and requires matching known root deliveries", () =>
        {
            var complete = new CompletenessMeasurement(true, true);
            var native = new SourceMeasurement("native", "Business", 1, 100, 10, Complete: true);
            var accumulator = new GainAccumulator("Context");
            accumulator.Add(new MeasurementRecord("root-a", Context: "Alpha", Outcome: "Success", Completeness: complete, Sources: [native, new("probe", "Probe", 3, 5, 0, Complete: true)]));
            accumulator.Add(new MeasurementRecord("child", ParentId: "root-a", Context: "Alpha", Outcome: "Failed", Sources: [native]));
            accumulator.Add(new MeasurementRecord("root-b", Context: "alpha", Outcome: "Success", Completeness: complete, Sources: [new("terminal", "Business", 2, TerminalBytesRead: 50, Complete: true)]));
            accumulator.Add(new MeasurementRecord("root-a", DeliveryId: "delivery-a", OutputBytes: 40, Completeness: complete, Sources: [native]));
            accumulator.Add(new MeasurementRecord("root-b", DeliveryId: "delivery-b", OutputBytes: 10, Completeness: complete, Sources: [new("terminal", "Business", 2, TerminalBytesRead: 50, Complete: true)]));
            var report = accumulator.Build(true); var summary = JsonSerializer.SerializeToElement(report.Summary);
            Check(summary.GetProperty("Invocations").GetInt32() == 3 && summary.GetProperty("Roots").GetInt32() == 2, "Invocation classification changed");
            Check(summary.GetProperty("UniqueNativeSources").GetInt32() == 3 && summary.GetProperty("BusinessBytesObserved").GetInt64() == 160 && summary.GetProperty("AuxiliaryBytesObserved").GetInt64() == 5 && summary.GetProperty("StdinBytesWritten").GetInt64() == 6, "Native source de-duplication or PTY counts changed");
            Check(summary.GetProperty("ReductionBytes").GetInt64() == 110 && report.Groups.Length == 2 && report.Groups.Sum(group => group.Failures) == 1, "Reduction or case-sensitive grouping changed");
            Check(JsonSerializer.SerializeToElement(accumulator.Build(false).Summary).GetProperty("ReductionBytes").ValueKind == JsonValueKind.Null, "Limited report invented a reduction");
            foreach (bool unknownSize in new[] { false, true })
            {
                var partial = new GainAccumulator("Context");
                partial.Add(new MeasurementRecord("selected-root", Completeness: complete, Sources: [native]));
                partial.Add(new MeasurementRecord(unknownSize ? "selected-root" : "unselected-root", DeliveryId: "delivery", OutputBytes: unknownSize ? null : 10));
                var view = JsonSerializer.SerializeToElement(partial.Build(true).Summary);
                Check(view.GetProperty("ReductionBytes").ValueKind == JsonValueKind.Null, "Unrelated delivery or unknown size proved a reduction");
                if (unknownSize) Check(view.GetProperty("RootDeliveryBytes").ValueKind == JsonValueKind.Null, "Unknown delivery size became zero");
            }
            return Task.CompletedTask;
        });
        await run("gain uses exact event budgets filters and read-only missing database behavior", async () =>
        {
            for (int index = 0; index < 130; index++)
            {
                var metadata = JsonSerializer.SerializeToElement(new MeasurementRecord("gain-" + index, SessionId: "gain-session", Context: "gain-selection", Command: "fixture", Role: "Business", Outcome: "Success", Completeness: new(true, true), Sources: [new("gain-native-" + index, "Business", StdoutBytesRead: 64, Complete: true)]));
                await store.SaveAsync(metadata, "invocation");
            }
            foreach (int maximum in new[] { 129, 130 })
            {
                var request = JsonSerializer.SerializeToElement(new { From = 0L, To = DateTimeOffset.UtcNow.AddDays(1).ToUnixTimeMilliseconds(), Context = "gain-selection", SessionId = "gain-session", GroupBy = "Command", MaxEvents = maximum });
                var report = await store.GainAsync(request); var summary = JsonSerializer.SerializeToElement(report.Summary);
                Check(summary.GetProperty("Complete").GetBoolean() == (maximum == 130) && summary.GetProperty("Invocations").GetInt32() == maximum && report.Groups.Single().Key == "fixture", "Event budget or exact-boundary completeness changed");
            }
            string missing = Path.Combine(directory, "missing-gain.sqlite");
            await using var absent = new MeasurementStore(missing);
            var empty = await absent.GainAsync(JsonSerializer.SerializeToElement(new { From = 0L, To = 1L, GroupBy = "Context", MaxEvents = 1 }));
            Check(!File.Exists(missing) && JsonSerializer.SerializeToElement(empty.Summary).GetProperty("Invocations").GetInt32() == 0, "Gain created a missing database");
        });
    }

    /// <summary>Checks an independently expected invariant.</summary>
    /// <param name="condition">Required true condition.</param>
    /// <param name="message">Failure context.</param>
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
