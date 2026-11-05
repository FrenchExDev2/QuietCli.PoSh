using System.Collections;
using System.Globalization;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Machine-oriented count-objects verbose counters and local alternate paths.</summary>
public static class GitObjectCounts
{
    /// <summary>Consumes one verbose count line without retaining a native output document.</summary>
    /// <param name="record">One exact LF-framed line.</param>
    /// <param name="data">Invocation-owned Counts map and Alternates list.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        int colon = Array.IndexOf(record, (byte)58);
        if (colon < 1 || colon + 2 > record.Length || record[colon + 1] != 32) throw new InvalidDataException("MalformedObjectCount");
        string key = System.Text.Encoding.ASCII.GetString(record, 0, colon);
        object value = GitRecords.Decode(record[(colon + 2)..]);
        if (key == "alternate") { ((IList)GitRecords.Unwrap(data["Alternates"])!).Add(value); return; }
        if (key.Any(c => c is not (>= 'a' and <= 'z') && c != '-') || value is not string text ||
            !long.TryParse(text.TrimEnd('\r'), NumberStyles.None, CultureInfo.InvariantCulture, out long count))
            throw new InvalidDataException("InvalidObjectCount");
        var counts = GitRecords.Dict(data["Counts"]);
        if (counts.Contains(key)) throw new InvalidDataException("DuplicateObjectCount");
        counts[key] = count;
    }
}
