using System.Collections;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Caller-local lossless parser for Git configuration records.</summary>
public static class GitConfigRecords
{
    /// <summary>Parses one config --null --list field, preserving repeated keys and multiline values.</summary>
    /// <param name="record">Exact record excluding NUL.</param>
    /// <param name="data">Invocation-owned Entries list.</param>
    public static void Config(byte[] record, IDictionary data)
    {
        int split = Array.IndexOf(record, (byte)10);
        if (record.Length == 0) throw new InvalidDataException("EmptyConfigKey");
        byte[] key = split < 0 ? record : record[..split];
        if (key.Length == 0) throw new InvalidDataException("EmptyConfigKey");
        var item = new Hashtable(StringComparer.OrdinalIgnoreCase)
        {
            ["Name"] = GitRecords.Decode(key),
            ["Value"] = split < 0 ? null : GitRecords.Decode(record[(split + 1)..]),
            ["HasValue"] = split >= 0
        };
        ((IList)GitRecords.Unwrap(data["Entries"])!).Add(item);
    }
}
