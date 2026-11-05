using System.Collections;
using System.Globalization;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Summary counts with exact opaque author/trailer/group labels.</summary>
public static class GitShortlogRecords
{
    /// <summary>Consumes a summary count and tab-delimited native group label.</summary>
    /// <param name="record">Exact summary record excluding LF.</param>
    /// <param name="data">Invocation-owned Groups list.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        int tab = Array.IndexOf(record, (byte)9);
        if (tab < 1 || tab == record.Length - 1 || !long.TryParse(Encoding.ASCII.GetString(record, 0, tab).Trim(' '), NumberStyles.None, CultureInfo.InvariantCulture, out long count) || count < 1)
            throw new InvalidDataException("MalformedShortlogSummary");
        var group = GitRecords.Map("Count", count, "Label", GitRecords.Decode(record[(tab + 1)..]));
        ((IList)GitRecords.Unwrap(data["Groups"])!).Add(group);
    }
}
