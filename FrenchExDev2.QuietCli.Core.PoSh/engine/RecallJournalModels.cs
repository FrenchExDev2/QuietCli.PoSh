using System.Collections;

namespace FrenchExDev2.QuietCli;

/// <summary>Closed, constant-size durable journal metadata; never contains executable callbacks.</summary>
public sealed record RecallJournalMetadata
{
    /// <summary>Journal format version.</summary>
    public int Version { get; init; } = 2;
    /// <summary>Canonical immutable artifact identity.</summary>
    public string RecallId { get; init; } = "";
    /// <summary>Optional human label, not a path or unique key.</summary>
    public string? RecallName { get; init; }
    /// <summary>UTC creation instant.</summary>
    public DateTimeOffset CreatedUtc { get; init; } = DateTimeOffset.UtcNow;
    /// <summary>UTC last confirmed checkpoint instant.</summary>
    public DateTimeOffset UpdatedUtc { get; init; } = DateTimeOffset.UtcNow;
    /// <summary>Recording, Completed, Failed or Interrupted.</summary>
    public string State { get; init; } = "Recording";
    /// <summary>Original inert decoding settings.</summary>
    public RecallAnalysisSettings Settings { get; init; } = new("Bytes", "Bytes", null, 1048576);
    /// <summary>Original execution outcome, when observed.</summary>
    public RecallSourceStatus? SourceStatus { get; init; }
    /// <summary>Whether the native source reached complete drainage.</summary>
    public bool SourceComplete { get; init; }
    /// <summary>Observed native bytes, including deliberately omitted ranges.</summary>
    public long ReceivedBytes { get; init; }
    /// <summary>Native bytes represented by complete journal records.</summary>
    public long StoredBytes { get; init; }
    /// <summary>Native bytes covered by the last synchronized checkpoint.</summary>
    public long DurableBytes { get; init; }
    /// <summary>Number of complete journal records; not bounded by Int32.</summary>
    public long EventCount { get; init; }
    /// <summary>Number of missing observed byte intervals.</summary>
    public long GapCount { get; init; }
    /// <summary>Exact confirmed journal file length, including framing.</summary>
    public long JournalLength { get; init; } = RecallJournalReader.PreambleLength;
    /// <summary>Original identity for an explicitly transformed artifact.</summary>
    public string? ParentCaptureId { get; init; }
    /// <summary>Explicit transformation label.</summary>
    public string? Transformation { get; init; }
}

/// <summary>Portable transport measurements, distinct from native or model token metrics.</summary>
public sealed record RecallTransportResult(string Path, long InputBytes, long OutputBytes, int CompressionLevel)
{
    /// <summary>Actual archive bytes divided by input bytes; can exceed one.</summary>
    public double? Ratio => InputBytes == 0 ? null : (double)OutputBytes / InputBytes;
}

/// <summary>Metadata-only listing entry, without enumerating journal contents.</summary>
public sealed record RecallSavedInfo(string RecallId, string? RecallName, string State, DateTimeOffset CreatedUtc, DateTimeOffset UpdatedUtc, long StoredBytes, long DurableBytes, bool SourceComplete, string Directory);

/// <summary>Lazy event list retaining no cumulative output; indexed access intentionally scans.</summary>
internal sealed class RecallJournalEvents(string directory, RecallJournalMetadata metadata) : IReadOnlyList<RecallEvent>
{
    public int Count => checked((int)metadata.EventCount);
    public RecallEvent this[int index] => index < 0 ? throw new ArgumentOutOfRangeException(nameof(index)) : this.Skip(index).First();
    public IEnumerator<RecallEvent> GetEnumerator()
    {
        using var reader = new RecallJournalReader(directory, metadata.RecallId, metadata.JournalLength, false);
        RecallEvent? next;
        while ((next = reader.ReadNextAsync().GetAwaiter().GetResult()) != null) yield return next;
        if (reader.StoredBytes != metadata.StoredBytes || reader.EventCount != metadata.EventCount) throw new InvalidDataException("RecallJournalCountersMismatch");
    }
    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}

/// <summary>Lazy missing-interval view over the same immutable journal prefix.</summary>
internal sealed class RecallJournalGaps(RecallJournalMetadata metadata, IReadOnlyList<RecallEvent> events) : IReadOnlyList<RecallGap>
{
    public int Count => checked((int)metadata.GapCount);
    public RecallGap this[int index] => index < 0 ? throw new ArgumentOutOfRangeException(nameof(index)) : this.Skip(index).First();
    public IEnumerator<RecallGap> GetEnumerator()
    {
        long end = 0;
        foreach (var e in events)
        {
            if (e.ObservedOffset > end) yield return new(end, e.ObservedOffset - end);
            end = checked(e.ObservedOffset + e.ByteCount);
        }
        if (end < metadata.ReceivedBytes) yield return new(end, metadata.ReceivedBytes - end);
    }
    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}
