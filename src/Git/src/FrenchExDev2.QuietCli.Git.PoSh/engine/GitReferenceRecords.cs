using System.Collections;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Local and advertised reference records, including symbolic and peeled references.</summary>
public static class GitReferenceRecords
{
    /// <summary>Consumes one show-ref or ls-remote protocol record.</summary>
    /// <param name="record">Exact line bytes without LF.</param>
    /// <param name="data">Invocation-owned References list.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        ReadOnlySpan<byte> line = record;
        if (line.EndsWith("\r"u8)) line = line[..^1];
        bool symbolic = line.StartsWith("ref: "u8);
        int separator = symbolic ? line.IndexOf((byte)9) : line.IndexOfAny((byte)32, (byte)9);
        if (separator < 1 || separator == line.Length - 1) throw new InvalidDataException("MalformedReferenceRecord");
        int start = separator + 1;
        while (start < line.Length && line[start] is 32 or 9) start++;
        if (start == line.Length) throw new InvalidDataException("EmptyReferenceName");
        if (symbolic && separator <= 5) throw new InvalidDataException("EmptySymbolicTarget");
        if (!symbolic && !GitObjectRecords.IsObjectId(line[..separator])) throw new InvalidDataException("MalformedReferenceIdentity");
        object name = GitRecords.Decode(line[start..].ToArray());
        var item = GitRecords.Map("Name", name, "ObjectId", symbolic ? null : Encoding.ASCII.GetString(line[..separator]),
            "SymbolicTarget", symbolic ? GitRecords.Decode(line[5..separator].ToArray()) : null,
            "Peeled", line[start..].EndsWith("^{}"u8));
        ((IList)GitRecords.Unwrap(data["References"])!).Add(item);
    }
}
