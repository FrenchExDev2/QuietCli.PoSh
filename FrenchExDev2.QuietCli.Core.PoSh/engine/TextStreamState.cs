using System.Text;

namespace FrenchExDev2.QuietCli;

/// <summary>Caller-local strict UTF-8 decoding and linear delimiter framing, without IPC or callbacks.</summary>
public sealed class TextStreamState : IDisposable
{
    /// <summary>Incremental strict decoder for exactly one native stream.</summary>
    private readonly Decoder decoder = new UTF8Encoding(false, true).GetDecoder();
    /// <summary>Optional exact UTF-16 delimiter.</summary>
    private readonly string? delimiter;
    /// <summary>KMP fallback positions for overlapping delimiters.</summary>
    private readonly int[] prefixes;
    /// <summary>Maximum UTF-8 bytes in a record or unfinished fragment.</summary>
    private readonly int maximum;
    /// <summary>Maximum extra bytes temporarily needed to recognize a delimiter.</summary>
    private readonly long delimiterBytes;
    /// <summary>Only the current unfinished record, never the complete native document.</summary>
    private StringBuilder pending = new();
    /// <summary>Matched delimiter prefix length.</summary>
    private int matched;
    /// <summary>UTF-8 replacement-compatible byte count of the unfinished record.</summary>
    private long pendingBytes;
    /// <summary>Whether the last pending UTF-16 character is a high surrogate.</summary>
    private bool highSurrogate;
    /// <summary>Rejects reuse after completion or disposal.</summary>
    private bool finished;

    /// <summary>Creates state without retaining any native input.</summary>
    /// <param name="delimiter">Null for chunk text, otherwise the exact record delimiter.</param>
    /// <param name="maximum">Maximum UTF-8 record bytes, excluding a complete delimiter.</param>
    public TextStreamState(string? delimiter, int maximum)
    {
        if (maximum < 1 || delimiter?.Length == 0) throw new ArgumentOutOfRangeException(nameof(maximum));
        this.delimiter = delimiter; this.maximum = maximum;
        prefixes = new int[delimiter?.Length ?? 0];
        if (delimiter == null) return;
        delimiterBytes = Encoding.UTF8.GetByteCount(delimiter);
        for (int i = 1, prefix = 0; i < delimiter.Length; i++)
        {
            while (prefix > 0 && delimiter[i] != delimiter[prefix]) prefix = prefixes[prefix - 1];
            if (delimiter[i] == delimiter[prefix]) prefix++;
            prefixes[i] = prefix;
        }
    }

    /// <summary>Decodes one transient block; incomplete code points remain in the strict decoder.</summary>
    /// <param name="bytes">One native block, not retained.</param>
    public string Decode(byte[] bytes)
    {
        ObjectDisposedException.ThrowIf(finished, this);
        var characters = new char[bytes.Length + 2];
        int count = decoder.GetChars(bytes, 0, bytes.Length, characters, 0, false);
        return new string(characters, 0, count);
    }

    /// <summary>Yields each complete record lazily, retaining only its unfinished suffix.</summary>
    /// <param name="text">Decoded chunk; caller still owns callback dispatch.</param>
    public IEnumerable<string> Frame(string text)
    {
        ObjectDisposedException.ThrowIf(finished, this);
        if (delimiter == null) throw new InvalidOperationException("RecordDelimiterMissing");
        foreach (char character in text)
        {
            pending.Append(character);
            pendingBytes += char.IsLowSurrogate(character) ? (highSurrogate ? 1 : 3) : character <= 0x7f ? 1 : character <= 0x7ff ? 2 : 3;
            highSurrogate = char.IsHighSurrogate(character);
            while (matched > 0 && character != delimiter[matched]) matched = prefixes[matched - 1];
            if (character == delimiter[matched]) matched++;
            if (matched == delimiter.Length)
            {
                string record = pending.ToString(0, pending.Length - delimiter.Length);
                if (Encoding.UTF8.GetByteCount(record) > maximum) throw new InvalidDataException("RecordTooLarge");
                pending.Clear(); pendingBytes = 0; matched = 0; highSurrogate = false;
                yield return record;
            }
            // A complete delimiter is excluded from the record limit. The three-byte margin
            // also preserves the old replacement-byte semantics for unusual UTF-16 delimiters.
            else if (pendingBytes > (long)maximum + delimiterBytes + 3) throw new InvalidDataException("RecordTooLarge");
        }
        // A partial delimiter at a chunk boundary is still an unfinished fragment, as before.
        if (pendingBytes > maximum) throw new InvalidDataException("RecordTooLarge");
    }

    /// <summary>Validates EOF and returns an unterminated final record once.</summary>
    public string Finish()
    {
        ObjectDisposedException.ThrowIf(finished, this);
        try
        {
            var characters = new char[2];
            int count = decoder.GetChars([], 0, 0, characters, 0, true);
            return pending.ToString() + new string(characters, 0, count);
        }
        finally { Dispose(); }
    }

    /// <summary>Releases the unfinished buffer, including after analysis failure.</summary>
    public void Dispose() { finished = true; pending = new StringBuilder(); decoder.Reset(); }
}
