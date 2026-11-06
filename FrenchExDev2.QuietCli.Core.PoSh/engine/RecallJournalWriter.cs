using System.Buffers.Binary;
using System.Diagnostics;
using System.Security.Cryptography;

namespace FrenchExDev2.QuietCli;

/// <summary>Explicit append-only disk recording, with constant metadata and synchronized checkpoints.</summary>
public sealed class RecallJournalWriter : IAsyncDisposable
{
    private readonly FileStream journal;
    private readonly FileStream ownership;
    private readonly Dictionary<string, long> streamEnds = new(StringComparer.Ordinal);
    private readonly Stopwatch checkpointWatch = Stopwatch.StartNew();
    private RecallJournalMetadata metadata;
    private long sequence, observedEnd, checkpointBytes;
    private bool finished, failed;
    /// <summary>Owned capture directory.</summary>
    public string DirectoryPath { get; }
    /// <summary>Stable identity assigned before native execution.</summary>
    public string RecallId => metadata.RecallId;
    /// <summary>Retains identity and confirmed record boundaries when persistence finalization fails.</summary>
    public RecallCapture FailedSnapshot() => new(DirectoryPath, metadata with { State = "Failed", SourceComplete = false }, false);

    /// <summary>Owns initialized file handles after the initial checkpoint has succeeded.</summary>
    /// <param name="directory">New recording directory.</param>
    /// <param name="metadata">Initial durable metadata.</param>
    /// <param name="journal">Append-only payload stream.</param>
    /// <param name="ownership">Exclusive recording lease.</param>
    private RecallJournalWriter(string directory, RecallJournalMetadata metadata, FileStream journal, FileStream ownership)
    { DirectoryPath = directory; this.metadata = metadata; this.journal = journal; this.ownership = ownership; }

    /// <summary>Creates a new directory and initial durable manifest; never overwrites an artifact.</summary>
    /// <param name="directory">New explicit directory.</param>
    /// <param name="id">Canonical identity.</param>
    /// <param name="name">Optional label.</param>
    /// <param name="settings">Inert decoding settings.</param>
    public static async Task<RecallJournalWriter> CreateAsync(string directory, string id, string? name, RecallAnalysisSettings settings)
    {
        directory = Path.GetFullPath(directory);
        if (System.IO.Directory.Exists(directory) || File.Exists(directory)) throw new IOException("RecallDestinationExists");
        var metadata = new RecallJournalMetadata { RecallId = RecallStore.NormalizeId(id), RecallName = name, Settings = settings };
        RecallStore.Validate(metadata);
        RecallPrivateFiles.CreateDirectory(directory);
        var ownership = RecallPrivateFiles.CreateNew(Path.Combine(directory, "writer.lock"), FileAccess.ReadWrite, FileShare.None, 4096, FileOptions.None);
        FileStream? journal = null;
        try
        {
            journal = RecallPrivateFiles.CreateNew(Path.Combine(directory, "events.bin"), FileAccess.ReadWrite, FileShare.Read, 65536, FileOptions.Asynchronous);
            byte[] preamble = new byte[RecallJournalReader.PreambleLength];
            RecallJournalReader.Magic.CopyTo(preamble); Guid.ParseExact(metadata.RecallId, "N").TryWriteBytes(preamble.AsSpan(8));
            await journal.WriteAsync(preamble); await journal.FlushAsync(); journal.Flush(true);
            await RecallStore.WriteManifestAsync(directory, metadata);
            return new(directory, metadata, journal, ownership);
        }
        catch { if (journal != null) await journal.DisposeAsync(); await ownership.DisposeAsync(); throw; }
    }

    /// <summary>Appends a native block in its caller-observed order without retaining prior content.</summary>
    /// <param name="stream">Native stream.</param>
    /// <param name="bytes">Transient native bytes.</param>
    public async Task AppendAsync(string stream, byte[] bytes)
    {
        if (bytes.Length == 0) return;
        streamEnds.TryGetValue(stream, out long offset);
        await AppendEventAsync(new(checked(sequence + 1), stream, offset, observedEnd, bytes));
    }

    /// <summary>Preserves original sequence and offsets when explicitly saving an existing capture.</summary>
    /// <param name="item">Immutable original slice.</param>
    public async Task AppendEventAsync(RecallEvent item)
    {
        if (finished || failed) throw new InvalidOperationException("RecallWriterNotRecording");
        try
        {
            streamEnds.TryGetValue(item.Stream, out long end);
            if (item.Sequence < sequence || item.Offset < end || item.ObservedOffset < observedEnd) throw new InvalidDataException("RecallJournalOrderInvalid");
            if (item.ObservedOffset > observedEnd) metadata = metadata with { GapCount = checked(metadata.GapCount + 1) };
            for (int at = 0; at < item.ByteCount;)
            {
                int count = Math.Min(RecallJournalReader.MaximumBlock, item.ByteCount - at);
                byte[] frame = new byte[RecallJournalReader.HeaderLength + count + RecallJournalReader.HashLength];
                BinaryPrimitives.WriteUInt32LittleEndian(frame, 0x32564551);
                frame[4] = item.Stream switch { "stdout" => 1, "stderr" => 2, "terminal" => 3, _ => throw new InvalidDataException("RecallJournalStreamInvalid") };
                BinaryPrimitives.WriteInt64LittleEndian(frame.AsSpan(8), item.Sequence);
                BinaryPrimitives.WriteInt64LittleEndian(frame.AsSpan(16), checked(item.Offset + at));
                BinaryPrimitives.WriteInt64LittleEndian(frame.AsSpan(24), checked(item.ObservedOffset + at));
                BinaryPrimitives.WriteInt32LittleEndian(frame.AsSpan(32), count);
                item.Content.Span.Slice(at, count).CopyTo(frame.AsSpan(RecallJournalReader.HeaderLength));
                SHA256.HashData(frame.AsSpan(0, RecallJournalReader.HeaderLength + count), frame.AsSpan(RecallJournalReader.HeaderLength + count));
                await journal.WriteAsync(frame);
                metadata = metadata with { StoredBytes = checked(metadata.StoredBytes + count), EventCount = checked(metadata.EventCount + 1), JournalLength = journal.Position };
                at += count;
            }
            sequence = item.Sequence; observedEnd = checked(item.ObservedOffset + item.ByteCount); streamEnds[item.Stream] = checked(item.Offset + item.ByteCount);
            metadata = metadata with { ReceivedBytes = observedEnd };
            await journal.FlushAsync();
            if (metadata.StoredBytes - checkpointBytes >= 4 * 1024 * 1024 || checkpointWatch.Elapsed.TotalSeconds >= 2) await CheckpointAsync();
        }
        catch { failed = true; throw; }
    }

    /// <summary>Confirms a synchronized filesystem checkpoint without claiming physical device guarantees.</summary>
    public async Task CheckpointAsync()
    {
        if (finished) throw new InvalidOperationException("RecallWriterFinished");
        await journal.FlushAsync();
        // Flush(true) has no asynchronous equivalent; it is used only at explicit durability checkpoints.
        journal.Flush(true);
        metadata = metadata with { DurableBytes = metadata.StoredBytes, UpdatedUtc = DateTimeOffset.UtcNow };
        await RecallStore.WriteManifestAsync(DirectoryPath, metadata);
        checkpointBytes = metadata.StoredBytes; checkpointWatch.Restart();
    }

    /// <summary>Finalizes source metadata and releases ownership before returning a lazy disk snapshot.</summary>
    /// <param name="sourceComplete">Native drainage result.</param>
    /// <param name="status">Original native execution status.</param>
    /// <param name="receivedBytes">Optional original observed count for a partial memory capture.</param>
    /// <param name="parentId">Optional transformed-artifact provenance.</param>
    /// <param name="transformation">Optional transformation label.</param>
    public async Task<RecallCapture> CompleteAsync(bool sourceComplete, RecallSourceStatus? status, long? receivedBytes = null, string? parentId = null, string? transformation = null)
    {
        if (finished) throw new InvalidOperationException("RecallWriterFinished");
        long received = receivedBytes ?? observedEnd;
        if (received < observedEnd) throw new InvalidDataException("RecallReceivedCountInvalid");
        metadata = metadata with { State = failed ? "Failed" : "Completed", SourceComplete = sourceComplete && !failed, SourceStatus = status, ReceivedBytes = received, GapCount = metadata.GapCount + (received > observedEnd ? 1 : 0), ParentCaptureId = parentId, Transformation = transformation };
        try { await CheckpointAsync(); }
        finally { finished = true; await journal.DisposeAsync(); await ownership.DisposeAsync(); }
        return await RecallStore.OpenDirectoryAsync(DirectoryPath);
    }

    /// <summary>Closes a recording without falsely marking it complete; recoverable records remain on disk.</summary>
    public async ValueTask DisposeAsync()
    {
        if (finished) return;
        finished = true;
        try { await journal.DisposeAsync(); } finally { await ownership.DisposeAsync(); }
    }
}
