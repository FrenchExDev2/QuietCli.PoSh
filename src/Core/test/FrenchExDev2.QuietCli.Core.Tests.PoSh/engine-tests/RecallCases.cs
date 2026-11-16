using FrenchExDev2.QuietCli;
using System.IO.Compression;
using System.Text;
using System.Text.Json;

/// <summary>Independent byte-oracle properties and malformed archive regression cases.</summary>
internal static class RecallCases
{
    /// <summary>Registers deterministic unit, property and bounded fuzz cases.</summary>
    /// <param name="test">Existing independent assertion runner.</param>
    public static async Task RunAsync(Func<string, Func<Task>, Task> test)
    {
        var settings = new RecallAnalysisSettings("Bytes", "Bytes", null, 1024);
        await test("Recall sizes use checked IEC arithmetic", () =>
        {
            Check(RecallOptions.ParseSize("90KiB") == 92160 && RecallOptions.ParseSize("92160") == 92160 && RecallOptions.ParseSize("2mib") == 2097152 && RecallOptions.ParseSize("All") == null, "size conversion");
            foreach (string value in new[] { "0", "-1", "1.5KiB", "1KB", "1e3", "9223372036854775807GiB", "All ", "" }) Reject(() => RecallOptions.ParseSize(value));
            Reject(() => new RecallOptions("All", "Tail")); Reject(() => new RecallOptions("1", "unknown")); Reject(() => new RecallOptions("1", "0"));
            return Task.CompletedTask;
        });
        await test("Recall generated retention matches independent flattened byte oracle seed 620611", () =>
        {
            var random = new Random(620611);
            for (int trial = 0; trial < 1000; trial++)
            {
                int size = random.Next(1, 150), total = random.Next(0, 500);
                byte[] expected = new byte[total]; random.NextBytes(expected);
                foreach (string policy in new[] { "Head", "Tail", "HeadAndTail" })
                {
                    var collector = new RecallCollector(new(size.ToString(), policy));
                    int at = 0;
                    while (at < total)
                    {
                        int count = Math.Min(random.Next(1, 60), total - at);
                        byte[] block = expected.AsSpan(at, count).ToArray(); collector.Append(at % 2 == 0 ? "stdout" : "stderr", block); Array.Fill(block, (byte)0); at += count;
                    }
                    var capture = collector.Snapshot(true, settings);
                    byte[] observed = capture.Events.SelectMany(e => e.Bytes).ToArray();
                    int head = (size + 1) / 2, tail = size / 2;
                    byte[] oracle = total <= size ? expected : policy == "Head" ? expected[..size] : policy == "Tail" ? expected[(total - size)..] : expected[..head].Concat(expected[(total - tail)..]).ToArray();
                    Check(observed.SequenceEqual(oracle), $"retained bytes {trial}/{policy}");
                    Check(capture.ReceivedBytes == total && capture.RetainedBytes == oracle.Length && capture.OmittedBytes == total - oracle.Length, "byte counts");
                    Check(capture.Gaps.Sum(g => g.ByteCount) == capture.OmittedBytes && capture.CaptureComplete == (total <= size), "gap completeness");
                    Check(capture.Events.Zip(capture.Events.Skip(1)).All(p => p.First.Sequence <= p.Second.Sequence && p.First.ObservedOffset + p.First.ByteCount <= p.Second.ObservedOffset), "order");
                    if (capture.Events.Count > 0) { byte old = capture.Events[0].Bytes[0]; capture.Events[0].Bytes[0] ^= 255; Check(capture.Events[0].Bytes[0] == old, "immutable bytes"); }
                }
            }
            return Task.CompletedTask;
        });
        await test("Recall All and source completeness are independent", () =>
        {
            var a = new RecallCollector(new("All", "Head")); a.Append("terminal", [0, 255, 195, 169]);
            var capture = a.Snapshot(false, settings);
            Check(capture.CaptureComplete && !capture.SourceComplete && capture.ReceivedBytes == 4 && capture.Events[0].Stream == "terminal", "unlimited incomplete source");
            var b = new RecallCollector(new("1", "Head")); Check(b.Snapshot(true, settings).ReceivedBytes == 0, "invocation isolation");
            return Task.CompletedTask;
        });
        await test("Recall references and queries preserve exact byte ranges", () =>
        {
            var collector = new RecallCollector(new("5", "HeadAndTail")); collector.Append("stdout", [0, 1, 2, 3, 4, 5, 6, 7]);
            var c = collector.Snapshot(true, settings);
            Check(RecallReader.Reference(c, "stdout", 0, 3).ByteCount == 3, "head reference");
            Check(RecallReader.Reference(c, "stdout", 6, 2).Offset == 6, "tail reference");
            Reject(() => RecallReader.Reference(c, "stdout", 2, 5));
            Check(RecallReader.Read(c, 1, "stdout", 1, 2, 0, 20, 4096).SelectMany(e => e.Bytes).SequenceEqual(new byte[] { 1, 2 }), "exact selection");
            Reject(() => new RecallCapture(Guid.NewGuid().ToString("N"), c.Events.Reverse(), 8, true, settings));
            Check(RecallDevelopment.EquivalentJson("{\"a\":1,\"b\":2}", "{\"b\":2,\"a\":1}"), "object key order is not a semantic difference");
            Check(!RecallDevelopment.EquivalentJson("[1,2]", "[2,1]"), "array order is semantic");
            return Task.CompletedTask;
        });
        await test("Recall Unicode records are invariant under generated block splits seed 19271", () =>
        {
            byte[] input = Encoding.UTF8.GetBytes("été\0漢字\0🙂\0fin");
            foreach (int seed in Enumerable.Range(19271, 150))
            {
                using var state = new TextStreamState("\0", 1024); var records = new List<string>();
                foreach (byte[] block in RecallDevelopment.Fragment(input, seed, 7)) records.AddRange(state.Frame(state.Decode(block)));
                records.Add(state.Finish());
                Check(records.SequenceEqual(new[] { "été", "漢字", "🙂", "fin" }), "fragmentation changed semantic records");
            }
            return Task.CompletedTask;
        });
        await RecallDurableCases.RunAsync(test, settings);
        await test("Recall reducer preserves explicit failure within attempt budget", async () =>
        {
            var collector = new RecallCollector(new("All", "Head"));
            collector.Append("stdout", [1, 2]); collector.Append("stderr", [99]); collector.Append("stdout", [3]);
            var reduced = await RecallDevelopment.ReduceAsync(collector.Snapshot(true, settings), c => c.Events.Any(e => e.Bytes.Contains((byte)99)), 50, 5);
            Check(reduced.Capture.Events.SelectMany(e => e.Bytes).Contains((byte)99) && reduced.Capture.RetainedBytes == 1 && reduced.Attempts <= 50 && !reduced.ProvenMinimal, "reducer");
        });
    }

    /// <summary>Throws when an independently stated invariant is false.</summary>
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    /// <summary>Requires a validation failure without swallowing its own assertion.</summary>
    private static void Reject(Action operation) { bool rejected = false; try { operation(); } catch (Exception e) when (e is ArgumentException or InvalidOperationException or InvalidDataException or OverflowException) { rejected = true; } Check(rejected, "invalid input accepted"); }
    /// <summary>Requires archive or budget rejection.</summary>
    private static async Task RejectAsync(Func<Task> operation) { bool rejected = false; try { await operation(); } catch (Exception e) when (e is IOException or InvalidDataException or ArgumentException or System.Text.Json.JsonException or OverflowException) { rejected = true; } Check(rejected, "invalid archive accepted"); }
}
