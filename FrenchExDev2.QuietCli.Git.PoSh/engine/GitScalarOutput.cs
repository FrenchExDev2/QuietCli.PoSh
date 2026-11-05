using System.Buffers;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Bounded caller-owned output for one explicitly requested scalar value.</summary>
public sealed class GitScalarOutput
{
    /// <summary>Retained scalar bytes, never a general native transcript.</summary>
    private readonly ArrayBufferWriter<byte> buffer = new();
    /// <summary>Explicit scalar allocation bound.</summary>
    private readonly int maximum;
    /// <summary>Terminal state forbids accidental reuse across requests.</summary>
    private bool complete;
    /// <summary>Creates a bounded scalar collector.</summary>
    /// <param name="maximumBytes">Maximum scalar size before an explicit failure.</param>
    public GitScalarOutput(int maximumBytes = 1048576)
    {
        if (maximumBytes < 1) throw new ArgumentOutOfRangeException(nameof(maximumBytes));
        maximum = maximumBytes;
    }
    /// <summary>Copies one transient stdout block into the explicit scalar.</summary>
    /// <param name="block">Transient native bytes.</param>
    public void Append(byte[] block)
    {
        if (complete) throw new InvalidOperationException("ScalarAlreadyCompleted");
        if (block.Length > maximum - buffer.WrittenCount) throw new InvalidDataException("ScalarOutputTooLarge");
        block.CopyTo(buffer.GetSpan(block.Length)); buffer.Advance(block.Length);
    }
    /// <summary>Removes only the scalar's final LF, retaining embedded newlines and raw bytes.</summary>
    public object Finish()
    {
        if (complete) throw new InvalidOperationException("ScalarAlreadyCompleted");
        complete = true;
        ReadOnlySpan<byte> value = buffer.WrittenSpan;
        if (value.EndsWith("\n"u8)) value = value[..^1];
        return GitRecords.Decode(value.ToArray());
    }
    /// <summary>Reads an exact native boolean, never coercing unrelated output to false.</summary>
    /// <param name="value">Decoded scalar or known PowerShell scalar wrapper.</param>
    public static bool ParseBoolean(object value) => GitRecords.Unwrap(value) switch
    {
        "true" => true, "false" => false, _ => throw new InvalidDataException("InvalidGitBoolean")
    };
}
