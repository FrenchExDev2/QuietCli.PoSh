namespace FrenchExDev2.QuietCli;

/// <summary>Stable byte evidence reference; contains no duplicated content.</summary>
public sealed record RecallReference(string CaptureId, string Stream, long Offset, long ByteCount);

/// <summary>Bounded local selection exposing delivery and source completeness separately.</summary>
public sealed class RecallSelection : IReadOnlyList<RecallEvent>
{
    private readonly IReadOnlyList<RecallEvent> events;
    /// <summary>Whether every selected event and byte fits the query budgets.</summary>
    public bool SelectionComplete { get; }
    /// <summary>Whether the original capture retained every received byte.</summary>
    public bool CaptureComplete { get; }
    /// <summary>Whether original native drainage was complete.</summary>
    public bool SourceComplete { get; }
    /// <summary>Delivered event count.</summary>
    public int Count => events.Count;
    /// <summary>Delivered native byte count, excluding object metadata.</summary>
    public long ReturnedBytes => events.Sum(e => (long)e.ByteCount);
    /// <summary>Selected immutable event.</summary>
    public RecallEvent this[int index] => events[index];
    internal RecallSelection(IReadOnlyList<RecallEvent> events, bool complete, RecallCapture capture) { this.events = events; SelectionComplete = complete; CaptureComplete = capture.CaptureComplete; SourceComplete = capture.SourceComplete; }
    /// <summary>Enumerates only the bounded selected events.</summary>
    public IEnumerator<RecallEvent> GetEnumerator() => events.GetEnumerator();
    System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();
}

/// <summary>Validated bounded access to retained native evidence.</summary>
public static class RecallReader
{
    /// <summary>Selects retained events with bounded byte and event budgets.</summary>
    /// <param name="capture">Immutable capture.</param>
    /// <param name="sequence">First selected original sequence.</param>
    /// <param name="stream">Optional native stream.</param>
    /// <param name="offset">First selected stream byte offset.</param>
    /// <param name="length">Selected stream range length.</param>
    /// <param name="context">Neighbor event count on either side.</param>
    /// <param name="maximumEvents">Maximum delivered events.</param>
    /// <param name="maximumBytes">Maximum delivered native bytes.</param>
    public static RecallSelection Read(RecallCapture capture, long sequence, string? stream, long offset, long length, int context, int maximumEvents, long maximumBytes)
    {
        if (sequence < 1 || offset < 0 || length < 1 || context < 0 || maximumEvents < 0 || maximumBytes < 1 || (stream != null && stream is not ("stdout" or "stderr" or "terminal"))) throw new ArgumentException("InvalidRecallQuery");
        long rangeEnd = length > long.MaxValue - offset ? long.MaxValue : offset + length;
        var result = new List<RecallEvent>();
        var preceding = new LinkedList<RecallEvent>();
        long budget = maximumBytes, precedingBytes = 0;
        int following = 0; bool complete = true;
        void Add(RecallEvent item, bool matches)
        {
            int start = matches ? (int)Math.Max(0, offset - item.Offset) : 0;
            int count = matches ? (int)Math.Min(item.ByteCount - start, rangeEnd - item.Offset - start) : item.ByteCount;
            if (count > budget) complete = false;
            count = (int)Math.Min(count, budget);
            if (count > 0 && result.Count < maximumEvents) { result.Add(item.Slice(start, count)); budget -= count; }
            else complete = false;
        }
        foreach (var item in capture.Events)
        {
            bool matches = item.Sequence >= sequence && (stream == null || item.Stream == stream) && item.Offset < rangeEnd && item.Offset + item.ByteCount > offset;
            if (matches)
            {
                foreach (var previous in preceding) { Add(previous, false); if (budget == 0 || result.Count >= maximumEvents) break; }
                preceding.Clear(); precedingBytes = 0;
                if (budget > 0 && result.Count < maximumEvents) Add(item, true); else complete = false;
                following = context;
            }
            else if (following > 0) { Add(item, false); following--; }
            else if (context > 0)
            {
                int count = (int)Math.Min(item.ByteCount, maximumBytes);
                var retained = item.Slice(item.ByteCount - count, count);
                preceding.AddLast(retained); precedingBytes += count;
                while (preceding.Count > Math.Min(context, maximumEvents) || precedingBytes > maximumBytes) { precedingBytes -= preceding.First!.Value.ByteCount; preceding.RemoveFirst(); }
            }
            if (budget == 0 || result.Count >= maximumEvents) { complete = false; break; }
        }
        return new(result.AsReadOnly(), complete, capture);
    }
    /// <summary>Creates a reference only when every requested byte is retained.</summary>
    /// <param name="capture">Capture containing the evidence.</param>
    /// <param name="stream">Native stream.</param>
    /// <param name="offset">First stream byte.</param>
    /// <param name="length">Positive byte length.</param>
    public static RecallReference Reference(RecallCapture capture, string stream, long offset, long length)
    {
        if (offset < 0 || length < 1 || stream is not ("stdout" or "stderr" or "terminal")) throw new ArgumentException("InvalidRecallReference");
        long end = checked(offset + length), cursor = offset;
        foreach (var e in capture.Events)
        {
            if (e.Stream != stream || e.Offset + e.ByteCount <= cursor) continue;
            if (e.Offset > cursor) break;
            cursor = Math.Min(end, e.Offset + e.ByteCount);
            if (cursor == end) return new(capture.CaptureId, stream, offset, length);
        }
        throw new InvalidOperationException("RecallEvidenceNotRetained");
    }
}
