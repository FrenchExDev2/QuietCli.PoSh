using System.Buffers.Binary;
using System.Security.Cryptography;

namespace FrenchExDev2.QuietCli;

/// <summary>One bounded asynchronous cursor validating record metadata, payload and ordering.</summary>
public sealed class RecallJournalReader : IDisposable
{
    internal const int PreambleLength = 24;
    internal const int HeaderLength = 36;
    internal const int HashLength = 32;
    internal const int MaximumBlock = 1048576;
    internal static ReadOnlySpan<byte> Magic => "QRECALL2"u8;
    private readonly FileStream file;
    private readonly string id;
    private readonly long limit;
    private readonly bool recoverTail;
    private readonly long durableLength;
    private readonly Dictionary<string, long> streamEnds = new(StringComparer.Ordinal);
    private long sequence, observedEnd;
    private string? priorStream;
    private bool initialized;
    /// <summary>Bytes in complete validated records.</summary>
    public long StoredBytes { get; private set; }
    /// <summary>Complete validated record count.</summary>
    public long EventCount { get; private set; }
    /// <summary>Missing intervals preceding validated records.</summary>
    public long GapCount { get; private set; }
    /// <summary>Last complete record boundary.</summary>
    public long ValidLength { get; private set; } = PreambleLength;
    /// <summary>Observed position immediately after the last record.</summary>
    public long ObservedEnd => observedEnd;
    /// <summary>Whether an incomplete final record was discarded explicitly.</summary>
    public bool TruncatedTail { get; private set; }

    /// <summary>Opens a bounded prefix without reading the document into memory.</summary>
    /// <param name="directory">Validated capture directory.</param>
    /// <param name="id">Expected identity encoded in the preamble.</param>
    /// <param name="length">Immutable readable prefix length.</param>
    /// <param name="recoverTail">Allows an incomplete final record, a zero-filled suffix or a torn last record after the durable prefix, never earlier corruption.</param>
    /// <param name="durableLength">Checkpointed record boundary; records before it must always validate, so corruption there is rejected.</param>
    public RecallJournalReader(string directory, string id, long length, bool recoverTail, long durableLength = long.MaxValue)
    {
        RecallStore.AssertPlainFile(Path.Combine(directory, "events.bin"));
        file = new(Path.Combine(directory, "events.bin"), FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 65536, true);
        this.id = id; limit = length; this.recoverTail = recoverTail; this.durableLength = durableLength;
        if (length < PreambleLength || length > file.Length) { file.Dispose(); throw new InvalidDataException("RecallJournalLengthInvalid"); }
    }

    /// <summary>Reads one authenticated frame with at most one MiB of native payload.</summary>
    public async Task<RecallEvent?> ReadNextAsync()
    {
        if (!initialized)
        {
            byte[] preamble = new byte[PreambleLength]; await file.ReadExactlyAsync(preamble);
            if (!preamble.AsSpan(0, 8).SequenceEqual(Magic) || new Guid(preamble.AsSpan(8, 16)).ToString("N") != id) throw new InvalidDataException("RecallJournalIdentityMismatch");
            initialized = true;
        }
        if (file.Position == limit) return null;
        long start = file.Position;
        try { return await ReadRecordAsync(); }
        catch (InvalidDataException failure) when (recoverTail && start >= durableLength)
        {
            if (!await IsDiscardableTailAsync(start, failure.Message)) throw;
            return Incomplete();
        }
    }

    /// <summary>Reads and validates one complete record starting at the current position.</summary>
    private async Task<RecallEvent?> ReadRecordAsync()
    {
        if (limit - file.Position < HeaderLength) return Incomplete();
        byte[] header = new byte[HeaderLength]; await file.ReadExactlyAsync(header);
        int count = BinaryPrimitives.ReadInt32LittleEndian(header.AsSpan(32));
        if (BinaryPrimitives.ReadUInt32LittleEndian(header) != 0x32564551 || header[5] != 0 || header[6] != 0 || header[7] != 0 || count < 1 || count > MaximumBlock) throw new InvalidDataException("RecallJournalHeaderInvalid");
        string stream = header[4] switch { 1 => "stdout", 2 => "stderr", 3 => "terminal", _ => throw new InvalidDataException("RecallJournalStreamInvalid") };
        if (limit - file.Position < (long)count + HashLength) return Incomplete();
        byte[] bytes = new byte[count], hash = new byte[HashLength];
        await file.ReadExactlyAsync(bytes); await file.ReadExactlyAsync(hash);
        using var checksum = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        checksum.AppendData(header); checksum.AppendData(bytes);
        if (!CryptographicOperations.FixedTimeEquals(checksum.GetHashAndReset(), hash)) throw new InvalidDataException("RecallJournalIntegrityFailed");
        long nextSequence = BinaryPrimitives.ReadInt64LittleEndian(header.AsSpan(8));
        long offset = BinaryPrimitives.ReadInt64LittleEndian(header.AsSpan(16));
        long observed = BinaryPrimitives.ReadInt64LittleEndian(header.AsSpan(24));
        streamEnds.TryGetValue(stream, out long streamEnd);
        if (nextSequence < 1 || nextSequence < sequence || nextSequence == sequence && stream != priorStream || offset < streamEnd || observed < observedEnd || offset - streamEnd > observed - StoredBytes || nextSequence > observed + 1) throw new InvalidDataException("RecallJournalOrderInvalid");
        if (observed > observedEnd) GapCount++;
        observedEnd = checked(observed + count); streamEnds[stream] = checked(offset + count); sequence = nextSequence; priorStream = stream;
        StoredBytes = checked(StoredBytes + count); EventCount = checked(EventCount + 1); ValidLength = file.Position;
        return new(nextSequence, stream, offset, observed, bytes);
    }

    /// <summary>
    /// Decides whether a failure after the durable prefix is crash residue: a suffix made only of zero bytes (preallocated or
    /// zero-filled by the file system) or a final record whose checksum fails because its payload was torn. A failure followed by
    /// further non-zero data is corruption and stays an error.
    /// </summary>
    /// <param name="start">Offset of the failing record.</param>
    /// <param name="code">Stable failure code raised while validating it.</param>
    private async Task<bool> IsDiscardableTailAsync(long start, string code)
    {
        file.Position = start;
        byte[] buffer = new byte[65536]; bool zero = true;
        for (long remaining = limit - start; remaining > 0 && zero;)
        {
            int read = await file.ReadAsync(buffer.AsMemory(0, (int)Math.Min(buffer.Length, remaining)));
            if (read == 0) break;
            zero = !buffer.AsSpan(0, read).ContainsAnyExcept((byte)0); remaining -= read;
        }
        if (zero) return true;
        if (code != "RecallJournalIntegrityFailed" || limit - start < HeaderLength) return false;
        file.Position = start; byte[] header = new byte[HeaderLength]; await file.ReadExactlyAsync(header);
        long count = BinaryPrimitives.ReadInt32LittleEndian(header.AsSpan(32));
        return start + HeaderLength + count + HashLength == limit;
    }

    /// <summary>Marks an incomplete suffix only in explicit crash recovery mode.</summary>
    private RecallEvent? Incomplete()
    {
        if (!recoverTail) throw new EndOfStreamException("RecallJournalTruncated");
        TruncatedTail = true; file.Position = limit; return null;
    }
    /// <summary>Closes this cursor without affecting any writer or other reader.</summary>
    public void Dispose() => file.Dispose();
}
