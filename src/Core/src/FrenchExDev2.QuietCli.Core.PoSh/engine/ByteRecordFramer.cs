namespace FrenchExDev2.QuietCli;

/// <summary>Splits transient blocks in compiled code, retaining only one bounded unfinished record.</summary>
public sealed class ByteRecordFramer : IDisposable
{
    /// <summary>Unfinished record, never a cumulative capture.</summary>
    private readonly MemoryStream pending = new();
    /// <summary>Exact delimiter byte.</summary>
    private readonly byte delimiter;
    /// <summary>Maximum unfinished or completed record size.</summary>
    private readonly int maximum;

    /// <summary>Creates a session-local byte framer without decoding business fields.</summary>
    /// <param name="delimiter">Delimiter excluded from each returned record.</param>
    /// <param name="maximum">Maximum record bytes.</param>
    public ByteRecordFramer(byte delimiter, int maximum)
    {
        if (maximum < 1) throw new ArgumentOutOfRangeException(nameof(maximum));
        this.delimiter = delimiter; this.maximum = maximum;
    }

    /// <summary>Produces records lazily, with no callback or IPC per byte.</summary>
    /// <param name="bytes">One transient block, not retained after enumeration.</param>
    public IEnumerable<byte[]> Push(byte[] bytes)
    {
        int start = 0;
        while (start < bytes.Length)
        {
            int end = Array.IndexOf(bytes, delimiter, start);
            int count = (end < 0 ? bytes.Length : end) - start;
            if (pending.Length + count > maximum) throw new InvalidDataException("GitRecordTooLarge");
            pending.Write(bytes, start, count);
            if (end < 0) yield break;
            byte[] record = pending.ToArray(); pending.SetLength(0);
            yield return record;
            start = end + 1;
        }
    }

    /// <summary>Returns and releases an unterminated final record; null means no remainder.</summary>
    public byte[]? Finish()
    {
        if (pending.Length == 0) return null;
        byte[] record = pending.ToArray(); pending.SetLength(0); return record;
    }

    /// <summary>Releases the session's unfinished buffer.</summary>
    public void Dispose() => pending.Dispose();
}
