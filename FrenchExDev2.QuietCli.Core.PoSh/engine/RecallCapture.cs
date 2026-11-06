using System.Collections.ObjectModel;

namespace FrenchExDev2.QuietCli;

/// <summary>Immutable retained slice of one observed native block.</summary>
public sealed class RecallEvent
{
    private readonly byte[] bytes;
    /// <summary>Original block sequence, starting at one.</summary>
    public long Sequence { get; }
    /// <summary>stdout, stderr or terminal.</summary>
    public string Stream { get; }
    /// <summary>Absolute byte position within this stream.</summary>
    public long Offset { get; }
    /// <summary>Absolute position in the observed combined byte sequence.</summary>
    public long ObservedOffset { get; }
    /// <summary>Number of retained bytes.</summary>
    public int ByteCount => bytes.Length;
    /// <summary>Detached bytes; modifying this copy cannot change the capture.</summary>
    public byte[] Bytes => (byte[])bytes.Clone();
    internal ReadOnlyMemory<byte> Content => bytes;

    /// <summary>Creates a detached event.</summary>
    /// <param name="sequence">Original sequence.</param>
    /// <param name="stream">Native stream.</param>
    /// <param name="offset">Stream byte offset.</param>
    /// <param name="observedOffset">Combined byte offset.</param>
    /// <param name="bytes">Content copied into owned storage.</param>
    public RecallEvent(long sequence, string stream, long offset, long observedOffset, byte[] bytes)
    {
        if (sequence < 1 || offset < 0 || observedOffset < 0 || bytes.Length == 0 || stream is not ("stdout" or "stderr" or "terminal")) throw new ArgumentException("InvalidRecallEvent");
        Sequence = sequence; Stream = stream; Offset = offset; ObservedOffset = observedOffset; this.bytes = (byte[])bytes.Clone();
    }

    internal RecallEvent Slice(int start, int count) => new(Sequence, Stream, checked(Offset + start), checked(ObservedOffset + start), bytes.AsSpan(start, count).ToArray());
}

/// <summary>A missing interval in the observed combined sequence.</summary>
public sealed record RecallGap(long Offset, long ByteCount);

/// <summary>Persistable inert analysis settings without callbacks, arguments or environment.</summary>
public sealed record RecallAnalysisSettings(string StdoutMode, string StderrMode, string? RecordDelimiter, int MaxRecordBytes);

/// <summary>Inert original execution status, without commands, environment or diagnostics.</summary>
public sealed record RecallSourceStatus(string Outcome, int? ExitCode, string EffectStatus);

/// <summary>Read-only capture with separate retention and native completeness.</summary>
public sealed class RecallCapture
{
    /// <summary>Stable capture identity.</summary>
    public string CaptureId { get; }
    /// <summary>Canonical identity used by durable lookup; alias of CaptureId.</summary>
    public string RecallId => CaptureId;
    /// <summary>Optional nonunique human label.</summary>
    public string? RecallName { get; }
    /// <summary>Durable directory, or null for a memory-only capture.</summary>
    public string? StoragePath { get; }
    /// <summary>Whether replay uses a bounded disk cursor.</summary>
    public bool IsSaved => StoragePath != null;
    /// <summary>Memory, Recording, Completed, Failed or Interrupted.</summary>
    public string State { get; } = "Memory";
    /// <summary>Whether complete records were recovered from an interrupted journal.</summary>
    public bool Recovered { get; }
    /// <summary>Native bytes covered by a synchronized filesystem checkpoint.</summary>
    public long DurableBytes { get; }
    /// <summary>Record count without an Int32 collection-size restriction.</summary>
    public long EventCount { get; }
    /// <summary>Optional explicit ZIP transport measurement.</summary>
    public RecallTransportResult? Transport { get; internal set; }
    /// <summary>Optional separately bounded memory view when disk and memory recording were both requested.</summary>
    public RecallCapture? MemoryCapture { get; private set; }
    internal RecallJournalMetadata? JournalMetadata { get; }
    /// <summary>Attaches the independently bounded in-memory view of this same native observation.</summary>
    /// <param name="memory">Memory-only snapshot with the identical identity.</param>
    public void AttachMemorySnapshot(RecallCapture memory)
    {
        if (!IsSaved || memory.IsSaved || memory.RecallId != RecallId) throw new ArgumentException("RecallMemoryIdentityMismatch");
        MemoryCapture = memory;
    }
    /// <summary>Events in observed order.</summary>
    public IReadOnlyList<RecallEvent> Events { get; }
    /// <summary>Missing combined byte intervals.</summary>
    public IReadOnlyList<RecallGap> Gaps { get; }
    /// <summary>Total received bytes, including omitted bytes.</summary>
    public long ReceivedBytes { get; }
    /// <summary>Total retained bytes.</summary>
    public long RetainedBytes { get; }
    /// <summary>Total omitted bytes.</summary>
    public long OmittedBytes => ReceivedBytes - RetainedBytes;
    /// <summary>Whether every received byte was retained.</summary>
    public bool CaptureComplete => OmittedBytes == 0;
    /// <summary>Whether native drainage reached a complete source.</summary>
    public bool SourceComplete { get; }
    /// <summary>Original inert decoding settings.</summary>
    public RecallAnalysisSettings Settings { get; }
    /// <summary>Original capture identity when this artifact was explicitly transformed.</summary>
    public string? ParentCaptureId { get; }
    /// <summary>Explicit transformation label; null for original observations.</summary>
    public string? Transformation { get; }
    /// <summary>Original native execution status when available.</summary>
    public RecallSourceStatus? SourceStatus { get; }

    /// <summary>Validates and freezes an ordered capture.</summary>
    /// <param name="id">Capture identity.</param>
    /// <param name="events">Retained ordered events.</param>
    /// <param name="received">Total received bytes.</param>
    /// <param name="sourceComplete">Native drainage completeness.</param>
    /// <param name="settings">Inert decoding settings.</param>
    /// <param name="parentCaptureId">Optional original artifact identity.</param>
    /// <param name="transformation">Optional explicit transformation label.</param>
    /// <param name="sourceStatus">Optional inert native execution status.</param>
    /// <param name="recallName">Optional nonunique label.</param>
    public RecallCapture(string id, IEnumerable<RecallEvent> events, long received, bool sourceComplete, RecallAnalysisSettings settings, string? parentCaptureId = null, string? transformation = null, RecallSourceStatus? sourceStatus = null, string? recallName = null)
    {
        if (recallName != null && (string.IsNullOrWhiteSpace(recallName) || recallName.Length > 256)) throw new ArgumentException("InvalidRecallName");
        if ((parentCaptureId == null) != (transformation == null) || parentCaptureId != null && (!Guid.TryParseExact(parentCaptureId, "N", out _) || parentCaptureId == id || string.IsNullOrWhiteSpace(transformation) || transformation.Length > 256)) throw new ArgumentException("InvalidRecallProvenance");
        if (!Guid.TryParseExact(id, "N", out _) || received < 0 || settings.MaxRecordBytes < 1 || settings.RecordDelimiter?.Length == 0 || settings.StdoutMode is not ("Text" or "Bytes") || settings.StderrMode is not ("Text" or "Bytes")) throw new ArgumentException("InvalidRecallCapture");
        if (sourceStatus != null && (string.IsNullOrWhiteSpace(sourceStatus.Outcome) || sourceStatus.Outcome.Length > 32 || string.IsNullOrWhiteSpace(sourceStatus.EffectStatus) || sourceStatus.EffectStatus.Length > 32)) throw new ArgumentException("InvalidRecallSourceStatus");
        var list = events.ToArray(); var gaps = new List<RecallGap>(); long end = 0, previousSequence = 0, retained = 0;
        var ends = new Dictionary<string, long>(StringComparer.Ordinal);
        foreach (var item in list)
        {
            long next = checked(item.ObservedOffset + item.ByteCount);
            if (item.Sequence < previousSequence || item.ObservedOffset < end || next > received || (ends.TryGetValue(item.Stream, out long streamEnd) && item.Offset < streamEnd)) throw new ArgumentException("InvalidRecallOrder");
            ends.TryGetValue(item.Stream, out long priorStreamEnd);
            if (item.Offset > item.ObservedOffset || item.Offset - priorStreamEnd > item.ObservedOffset - retained || item.Sequence > item.ObservedOffset + 1) throw new ArgumentException("InvalidRecallOffset");
            if (item.ObservedOffset > end) gaps.Add(new(end, item.ObservedOffset - end));
            ends[item.Stream] = checked(item.Offset + item.ByteCount);
            previousSequence = item.Sequence; end = next; retained = checked(retained + item.ByteCount);
        }
        if (end < received) gaps.Add(new(end, received - end));
        CaptureId = id; Events = Array.AsReadOnly(list); Gaps = gaps.AsReadOnly(); ReceivedBytes = received; RetainedBytes = retained; SourceComplete = sourceComplete; Settings = settings;
        ParentCaptureId = parentCaptureId; Transformation = transformation;
        SourceStatus = sourceStatus;
        RecallName = recallName; EventCount = list.LongLength;
    }

    /// <summary>Builds a validated lazy snapshot of an immutable journal prefix.</summary>
    /// <param name="directory">Working directory containing the journal.</param>
    /// <param name="metadata">Validated prefix metadata.</param>
    /// <param name="recovered">Whether abandoned recording data was recovered.</param>
    internal RecallCapture(string directory, RecallJournalMetadata metadata, bool recovered)
    {
        CaptureId = metadata.RecallId; RecallName = metadata.RecallName; StoragePath = directory; State = metadata.State; Recovered = recovered; DurableBytes = metadata.DurableBytes; EventCount = metadata.EventCount;
        ReceivedBytes = metadata.ReceivedBytes; RetainedBytes = metadata.StoredBytes; SourceComplete = metadata.SourceComplete; Settings = metadata.Settings;
        ParentCaptureId = metadata.ParentCaptureId; Transformation = metadata.Transformation; SourceStatus = metadata.SourceStatus; JournalMetadata = metadata;
        Events = new RecallJournalEvents(directory, metadata); Gaps = metadata.GapCount == 0 ? Array.Empty<RecallGap>() : new RecallJournalGaps(metadata, Events);
    }
}

/// <summary>Caller-local collector retaining a bounded head, tail, or both.</summary>
public sealed class RecallCollector
{
    private readonly RecallOptions options;
    private readonly List<RecallEvent> head = new();
    private readonly LinkedList<RecallEvent> tail = new();
    private readonly Dictionary<string, long> offsets = new(StringComparer.Ordinal);
    private long received, sequence, headBytes, tailBytes;
    private readonly string id;
    private readonly string? name;

    /// <summary>Creates an empty collector; no process dependency.</summary>
    /// <param name="options">Validated retention policy.</param>
    /// <param name="id">Optional identity shared with an explicit disk writer.</param>
    /// <param name="name">Optional display label.</param>
    public RecallCollector(RecallOptions options, string? id = null, string? name = null) { this.options = options; this.id = id == null ? Guid.NewGuid().ToString("N") : RecallStore.NormalizeId(id); this.name = name; }

    /// <summary>Retains owned bytes before user callbacks can mutate the original buffer.</summary>
    /// <param name="stream">Native stream name.</param>
    /// <param name="bytes">One transient observed block.</param>
    public void Append(string stream, byte[] bytes)
    {
        if (stream is not ("stdout" or "stderr" or "terminal")) throw new ArgumentException("InvalidRecallStream");
        if (bytes.Length == 0) return;
        offsets.TryGetValue(stream, out long offset);
        long start = received; received = checked(received + bytes.Length); offsets[stream] = checked(offset + bytes.Length); sequence = checked(sequence + 1);
        long headLimit = options.Policy == RecallPolicy.Tail ? 0 : options.MaximumBytes ?? long.MaxValue;
        if (options.Policy == RecallPolicy.HeadAndTail) headLimit = headLimit / 2 + headLimit % 2;
        int prefix = (int)Math.Min(bytes.Length, Math.Max(0, headLimit - headBytes));
        if (prefix > 0) { head.Add(new(sequence, stream, offset, start, bytes.AsSpan(0, prefix).ToArray())); headBytes += prefix; }
        long tailLimit = options.Policy switch { RecallPolicy.Tail => options.MaximumBytes!.Value, RecallPolicy.HeadAndTail => options.MaximumBytes!.Value / 2, _ => 0 };
        int suffix = (int)Math.Min(bytes.Length - prefix, tailLimit);
        if (suffix == 0) return;
        int from = bytes.Length - suffix;
        tail.AddLast(new RecallEvent(sequence, stream, offset + from, start + from, bytes.AsSpan(from, suffix).ToArray())); tailBytes += suffix;
        while (tailBytes > tailLimit)
        {
            var first = tail.First!.Value; int remove = (int)Math.Min(first.ByteCount, tailBytes - tailLimit);
            tail.RemoveFirst(); tailBytes -= remove;
            if (remove < first.ByteCount) tail.AddFirst(first.Slice(remove, first.ByteCount - remove));
        }
    }

    /// <summary>Creates an immutable snapshot without copying owned buffers again.</summary>
    /// <param name="sourceComplete">Whether native drainage completed.</param>
    /// <param name="settings">Original decoding settings.</param>
    /// <param name="sourceStatus">Optional inert native execution status.</param>
    public RecallCapture Snapshot(bool sourceComplete, RecallAnalysisSettings settings, RecallSourceStatus? sourceStatus = null) => new(id, head.Concat(tail), received, sourceComplete, settings, sourceStatus: sourceStatus, recallName: name);
}
