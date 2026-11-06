using FrenchExDev2.QuietCli;
using System.IO.Compression;
using System.Text.Json;

/// <summary>Independent durable-storage, corruption, recovery and ZIP64 properties.</summary>
internal static class RecallDurableCases
{
    /// <summary>Registers bounded deterministic cases with the existing companion runner.</summary>
    /// <param name="test">Independent test registrar.</param>
    /// <param name="settings">Known byte-only settings.</param>
    public static async Task RunAsync(Func<string, Func<Task>, Task> test, RecallAnalysisSettings settings)
    {
        await test("Recall durable directory keeps identity names and exact mixed bytes", async () =>
        {
            string root = Root();
            await using var writer = await RecallStore.CreateAsync(root, "développement", settings);
            await writer.AppendAsync("stdout", [0, 255, 195, 169]); await writer.AppendAsync("stderr", [7, 8]);
            await writer.CheckpointAsync();
            var live = await RecallStore.OpenAsync(root, writer.RecallId);
            Require(live.State == "Recording" && !live.Recovered && !live.SourceComplete && live.Events.Sum(e => (long)e.ByteCount) == 6, "live checkpoint prefix");
            var capture = await writer.CompleteAsync(true, new("Success", 0, "Executed"));
            Require(capture.IsSaved && capture.CaptureId == capture.RecallId && capture.RecallName == "développement" && capture.DurableBytes == 6, "identity or durability");
            Require(capture.Events.SelectMany(e => e.Bytes).SequenceEqual(new byte[] { 0, 255, 195, 169, 7, 8 }), "byte identity");
            Require(capture.Events[1].Stream == "stderr" && capture.Events[1].Offset == 0 && capture.Events[1].ObservedOffset == 4, "mixed ordering");
            var rows = await RecallStore.ListAsync(root); Require(rows.Count == 1 && rows[0].RecallId == capture.RecallId, "catalog");
            var reopened = await RecallStore.OpenAsync(root, capture.RecallId); Require(reopened.EventCount == 2 && reopened.SourceComplete, "restart");
            await RejectAsync(() => RecallStore.OpenAsync(root, "../escape"));
            await RejectAsync(() => RecallStore.SaveDirectoryAsync(capture, capture.StoragePath!));
            await RejectAsync(() => RecallArchive.ImportAsync(capture.StoragePath!, 5));
            string wrongId = Guid.NewGuid().ToString("N"), wrongDirectory = Path.Combine(root, wrongId);
            Directory.CreateDirectory(wrongDirectory);
            File.Copy(Path.Combine(capture.StoragePath!, "manifest.json"), Path.Combine(wrongDirectory, "manifest.json"));
            File.Copy(Path.Combine(capture.StoragePath!, "events.bin"), Path.Combine(wrongDirectory, "events.bin"));
            await RejectAsync(() => RecallStore.OpenAsync(root, wrongId));
        });
        await test("Recall interrupted journals recover only complete records and reject corruption", async () =>
        {
            string root = Root(); var writer = await RecallStore.CreateAsync(root, "crash", settings);
            await writer.AppendAsync("stdout", [1, 2, 3]); await writer.AppendAsync("stderr", [4]);
            string id = writer.RecallId, path = writer.DirectoryPath;
            await writer.DisposeAsync();
            await using (var tail = new FileStream(Path.Combine(path, "events.bin"), FileMode.Append)) await tail.WriteAsync(new byte[] { 1, 2, 3 });
            var recovered = await RecallStore.OpenAsync(root, id);
            Require(recovered.Recovered && recovered.State == "Interrupted" && !recovered.SourceComplete && recovered.RetainedBytes == 4 && recovered.DurableBytes == 0, "recovery completeness");
            Require(recovered.Events.SelectMany(e => e.Bytes).SequenceEqual(new byte[] { 1, 2, 3, 4 }), "partial tail leaked");
            await using (var corrupt = new FileStream(Path.Combine(path, "events.bin"), FileMode.Open, FileAccess.Write)) { corrupt.Position = RecallJournalReader.PreambleLength + RecallJournalReader.HeaderLength; await corrupt.WriteAsync(new byte[] { 99 }); }
            await RejectAsync(() => RecallStore.OpenAsync(root, id));
        });
        await test("Recall ZIP64 levels zero through nine interoperate and import lazily", async () =>
        {
            string root = Root(); var collector = new RecallCollector(new("All", "Head")); collector.Append("stdout", Enumerable.Repeat((byte)42, 65536).ToArray()); collector.Append("stderr", [1, 2]);
            var capture = collector.Snapshot(false, settings, new("Timeout", null, "Executed"));
            for (int level = 0; level <= 9; level++)
            {
                string zipPath = Path.Combine(root, "level-" + level + ".zip");
                var report = await RecallArchive.ExportAsync(capture, zipPath, true, level);
                Require(report.OutputBytes == new FileInfo(zipPath).Length && report.CompressionLevel == level && report.Ratio > 0, "transport measurements");
                if (level > 0) Require(report.OutputBytes < report.InputBytes, "compressible fixture not compressed");
                using (var zip = ZipFile.OpenRead(zipPath)) { Require(zip.Entries.Count == 2 && zip.GetEntry("events.bin")!.Length > 65536, "independent ZIP reader"); }
                var imported = await RecallArchive.ImportAsync(zipPath, null, Path.Combine(root, "imports-" + level));
                Require(imported.IsSaved && imported.RecallId == capture.RecallId && !imported.SourceComplete && imported.SourceStatus?.Outcome == "Timeout", "import metadata");
                Require(imported.Events.Sum(e => (long)e.ByteCount) == 65538, "streamed imported bytes");
                await RejectAsync(() => RecallArchive.ImportAsync(zipPath, 10, Path.Combine(root, "budget-" + level)));
            }
            await RejectAsync(() => RecallArchive.ExportAsync(capture, Path.Combine(root, "invalid.zip"), true, 10));
        });
        await test("Recall journal generated mixed streams preserve independent oracle seed 610611", async () =>
        {
            var random = new Random(610611);
            for (int trial = 0; trial < 40; trial++)
            {
                string root = Root(); await using var writer = await RecallStore.CreateAsync(root, "same name", settings);
                var expected = new List<byte>(); var expectedStreams = new List<string>();
                for (int i = 0; i < 25; i++)
                {
                    var bytes = new byte[random.Next(1, 300)]; random.NextBytes(bytes); string stream = random.Next(2) == 0 ? "stdout" : "stderr";
                    expected.AddRange(bytes); expectedStreams.Add(stream); await writer.AppendAsync(stream, bytes); Array.Fill(bytes, (byte)0);
                }
                var capture = await writer.CompleteAsync(true, new("Success", 0, "Executed"));
                Require(capture.Events.SelectMany(e => e.Bytes).SequenceEqual(expected), "generated bytes");
                Require(capture.Events.Select(e => e.Stream).SequenceEqual(expectedStreams), "generated stream order");
                Require(capture.Events.Select(e => e.Sequence).SequenceEqual(Enumerable.Range(1, 25).Select(i => (long)i)), "generated sequences");
            }
        });
        await test("Recall has no twenty-thousand-event or 32-bit stream offset ceiling", async () =>
        {
            string root = Root(); await using var writer = await RecallStore.CreateAsync(root, null, settings);
            for (int i = 0; i < 20001; i++) await writer.AppendAsync("stdout", [17]);
            var capture = await writer.CompleteAsync(true, new("Success", 0, "Executed"));
            Require(capture.EventCount == 20001 && capture.Events.Sum(e => (long)e.ByteCount) == 20001, "old event ceiling");
            long offset = (long)uint.MaxValue + 17;
            var large = new RecallCapture(Guid.NewGuid().ToString("N"), [new RecallEvent(1, "stdout", offset, offset, [99])], offset + 1, false, settings);
            var saved = await RecallStore.SaveDirectoryAsync(large, Path.Combine(root, "large-offset"));
            Require(saved.Events[0].Offset == offset && saved.ReceivedBytes == offset + 1 && saved.Gaps[0].ByteCount == offset, "64-bit offsets");
            var view = RecallReader.Read(saved, 1, "stdout", offset, 1, 0, 1, 1); Require(view.Count == 1 && view[0].Bytes[0] == 99, "bounded large-offset query");
        });
        await test("Recall manifest and archive fuzz reject malformed inert input seed 1906", async () =>
        {
            string root = Root(); await using var writer = await RecallStore.CreateAsync(root, null, settings); await writer.AppendAsync("stdout", [1]);
            var capture = await writer.CompleteAsync(true, new("Success", 0, "Executed")); string manifest = Path.Combine(capture.StoragePath!, "manifest.json");
            var valid = JsonSerializer.Deserialize<RecallJournalMetadata>(await File.ReadAllTextAsync(manifest))!;
            foreach (var invalid in new[] { valid with { Version = 99 }, valid with { StoredBytes = -1 }, valid with { EventCount = long.MaxValue }, valid with { JournalLength = 1 }, valid with { RecallId = "../outside" }, valid with { Settings = settings with { RecordDelimiter = "" } } })
            {
                await File.WriteAllBytesAsync(manifest, JsonSerializer.SerializeToUtf8Bytes(invalid));
                await RejectAsync(() => RecallStore.OpenDirectoryAsync(capture.StoragePath!));
            }
            await File.WriteAllBytesAsync(manifest, JsonSerializer.SerializeToUtf8Bytes(valid));
            string malformed = Path.Combine(root, "malformed.zip"); var random = new Random(1906);
            for (int i = 0; i < 100; i++) { byte[] bytes = new byte[random.Next(1, 1024)]; random.NextBytes(bytes); await File.WriteAllBytesAsync(malformed, bytes); await RejectAsync(() => RecallArchive.ImportAsync(malformed, 1024, root)); }
            string traversal = Path.Combine(root, "traversal.zip"); using (var zip = ZipFile.Open(traversal, ZipArchiveMode.Create)) { zip.CreateEntry("../manifest.json"); zip.CreateEntry("events.bin"); }
            await RejectAsync(() => RecallArchive.ImportAsync(traversal, null, root));
        });
    }

    /// <summary>Creates a case-owned report directory, retaining all failing evidence.</summary>
    private static string Root()
    {
        string root = Environment.GetEnvironmentVariable("QUIETCLI_RECALL_TEST_ROOT") ?? throw new InvalidOperationException("RecallTestRootRequired");
        string directory = Path.Combine(root, Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory); return directory;
    }
    /// <summary>Asserts an independent expected property.</summary>
    private static void Require(bool condition, string reason) { if (!condition) throw new InvalidOperationException(reason); }
    /// <summary>Requires validation or integrity rejection; does not treat assertion failures as success.</summary>
    private static async Task RejectAsync(Func<Task> operation)
    {
        bool rejected = false;
        try { await operation(); } catch (Exception e) when (e is IOException or InvalidDataException or ArgumentException or OverflowException or JsonException) { rejected = true; }
        Require(rejected, "malformed evidence accepted");
    }
}
