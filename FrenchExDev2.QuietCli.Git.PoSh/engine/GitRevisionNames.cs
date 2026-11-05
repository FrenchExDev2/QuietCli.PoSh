using System.Collections;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Native name-rev input labels and symbolic descriptions without guessing object IDs.</summary>
public static class GitRevisionNames
{
    /// <summary>Consumes one default label/name pair.</summary>
    /// <param name="record">Exact line without LF.</param>
    /// <param name="data">Invocation-owned Names list.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        int space = Array.IndexOf(record, (byte)32);
        if (space < 1 || space == record.Length - 1) throw new InvalidDataException("MalformedRevisionName");
        object name = GitRecords.Decode(record[(space + 1)..]);
        var entry = GitRecords.Map("Input", GitRecords.Decode(record[..space]), "Name", name, "Undefined", Equals(name, "undefined"));
        ((IList)GitRecords.Unwrap(data["Names"])!).Add(entry);
    }
}
