using System.Collections;
using System.Globalization;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Unambiguous long describe records and explicit --always identity fallbacks.</summary>
public static class GitDescribeRecords
{
    /// <summary>Consumes one long description without assuming a full algorithm from its abbreviation.</summary>
    /// <param name="record">One exact native line.</param>
    /// <param name="data">Invocation-owned Descriptions list.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        int final = Array.LastIndexOf(record, (byte)45);
        Hashtable entry;
        if (GitObjectRecords.IsHexadecimal(record) && record.Length <= 64)
            entry = GitRecords.Map("Tag", null, "Distance", null, "ObjectAbbreviation", Encoding.ASCII.GetString(record), "ObjectOnly", true);
        else
        {
            if (final < 1 || final + 2 >= record.Length || record[final + 1] != 'g') throw new InvalidDataException("MalformedDescribeRecord");
            int previous = Array.LastIndexOf(record, (byte)45, final - 1);
            if (previous < 1 || !long.TryParse(Encoding.ASCII.GetString(record, previous + 1, final - previous - 1), NumberStyles.None, CultureInfo.InvariantCulture, out long distance) ||
                !GitObjectRecords.IsHexadecimal(record.AsSpan(final + 2)) || record.Length - final - 2 > 64)
                throw new InvalidDataException("InvalidDescribeFields");
            entry = GitRecords.Map("Tag", GitRecords.Decode(record[..previous]), "Distance", distance, "ObjectAbbreviation", Encoding.ASCII.GetString(record.AsSpan(final + 2)), "ObjectOnly", false);
        }
        entry["Description"] = GitRecords.Decode(record);
        ((IList)GitRecords.Unwrap(data["Descriptions"])!).Add(entry);
    }
}
