using System.Collections;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Caller-local parser for configured Git remotes.</summary>
public static class GitRemoteRecords
{
    /// <summary>Parses remote -v output without splitting URLs on spaces or colons.</summary>
    /// <param name="record">Exact line excluding LF.</param>
    /// <param name="data">Invocation-owned Remotes list.</param>
    public static void Remote(byte[] record, IDictionary data)
    {
        int length = record.Length;
        if (length > 0 && record[length - 1] == 13) length--;
        if (length == 0) return;
        int tab = Array.IndexOf(record, (byte)9, 0, length);
        if (tab < 1) throw new InvalidDataException("MalformedRemoteRecord");
        ReadOnlySpan<byte> tail = record.AsSpan(tab + 1, length - tab - 1);
        string direction;
        int suffix;
        if (tail.EndsWith(" (fetch)"u8)) { direction = "fetch"; suffix = 8; }
        else if (tail.EndsWith(" (push)"u8)) { direction = "push"; suffix = 7; }
        else throw new InvalidDataException("MalformedRemoteDirection");
        var item = new Hashtable(StringComparer.OrdinalIgnoreCase)
        {
            ["Name"] = GitRecords.Decode(record[..tab]),
            ["Url"] = GitRecords.Decode(tail[..^suffix].ToArray()),
            ["Direction"] = direction
        };
        ((IList)GitRecords.Unwrap(data["Remotes"])!).Add(item);
    }
}
