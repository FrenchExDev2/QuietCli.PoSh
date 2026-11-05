using System.Buffers;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Decodes Git's double-quoted byte paths without assuming Unicode validity.</summary>
public static class GitQuotedPath
{
    /// <summary>Decodes an unquoted path or the documented C escapes used by Git.</summary>
    /// <param name="record">Exact filename field excluding its record delimiter.</param>
    public static object Decode(byte[] record)
    {
        if (record.Length == 0 || record.Contains((byte)0)) throw new InvalidDataException("InvalidGitPath");
        if (record[0] != 34) return GitRecords.Decode(record);
        if (record.Length < 3 || record[^1] != 34) throw new InvalidDataException("UnterminatedGitPath");
        var bytes = new ArrayBufferWriter<byte>();
        for (int index = 1; index < record.Length - 1; index++)
        {
            byte item = record[index];
            if (item == 34) throw new InvalidDataException("UnexpectedGitPathQuote");
            if (item == 92)
            {
                if (++index >= record.Length - 1) throw new InvalidDataException("IncompleteGitPathEscape");
                item = record[index];
                if (item is >= (byte)'0' and <= (byte)'3')
                {
                    if (index + 2 >= record.Length - 1 || record[index + 1] is < (byte)'0' or > (byte)'7' || record[index + 2] is < (byte)'0' or > (byte)'7')
                        throw new InvalidDataException("InvalidGitPathOctal");
                    item = (byte)((item - '0') * 64 + (record[index + 1] - '0') * 8 + record[index + 2] - '0');
                    index += 2;
                }
                else item = item switch
                {
                    (byte)'a' => 7, (byte)'b' => 8, (byte)'f' => 12, (byte)'n' => 10,
                    (byte)'r' => 13, (byte)'t' => 9, (byte)'v' => 11, 92 => 92, 34 => 34,
                    _ => throw new InvalidDataException("UnknownGitPathEscape")
                };
            }
            if (item == 0) throw new InvalidDataException("NullGitPathByte");
            bytes.GetSpan(1)[0] = item; bytes.Advance(1);
        }
        return GitRecords.Decode(bytes.WrittenSpan.ToArray());
    }
}
