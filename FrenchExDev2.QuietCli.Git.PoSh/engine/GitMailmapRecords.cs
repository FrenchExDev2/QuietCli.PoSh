using System.Collections;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Canonical contact lines emitted by check-mailmap.</summary>
public static class GitMailmapRecords
{
    /// <summary>Splits the final mail bracket pair without assuming ASCII names or addresses.</summary>
    /// <param name="record">One LF-framed canonical contact.</param>
    /// <param name="data">Invocation-owned Contacts list.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        int length = record.Length;
        if (length > 0 && record[length - 1] == 13) length--;
        if (length < 3) throw new InvalidDataException("MalformedCanonicalContact");
        int angle = Array.LastIndexOf(record, (byte)60, length - 1, length);
        if (length < 3 || angle < 0 || angle + 1 >= length - 1 || record[length - 1] != 62) throw new InvalidDataException("MalformedCanonicalContact");
        int nameEnd = angle;
        while (nameEnd > 0 && record[nameEnd - 1] is 32 or 9) nameEnd--;
        var contact = GitRecords.Map("Name", GitRecords.Decode(record[..nameEnd]), "Email", GitRecords.Decode(record[(angle + 1)..(length - 1)]));
        ((IList)GitRecords.Unwrap(data["Contacts"])!).Add(contact);
    }
}
