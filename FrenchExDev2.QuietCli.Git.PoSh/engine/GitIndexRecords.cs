using System.Collections;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Lossless NUL-framed index paths and optional mode/object/stage metadata.</summary>
public static class GitIndexRecords
{
    /// <summary>Consumes one ls-files record, preserving tabs and newlines in its path.</summary>
    /// <param name="record">Exact bytes excluding NUL.</param>
    /// <param name="data">Invocation-owned Files list and WithStage flag.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        if (record.Length == 0) throw new InvalidDataException("EmptyIndexPath");
        var item = GitRecords.Map();
        if (GitRecords.Unwrap(data["WithStage"]) is true)
        {
            int tab = Array.IndexOf(record, (byte)9);
            if (tab < 0 || tab == record.Length - 1) throw new InvalidDataException("MalformedIndexRecord");
            string[] header = Encoding.ASCII.GetString(record.AsSpan(0, tab)).Split(' ');
            if (header.Length != 3 || header[0].Length != 6 || header[0].Any(c => c is < '0' or > '7') ||
                !GitObjectRecords.IsObjectId(Encoding.ASCII.GetBytes(header[1])) || header[2].Length != 1 || header[2][0] is < '0' or > '3')
                throw new InvalidDataException("MalformedIndexHeader");
            item["Mode"] = header[0]; item["ObjectId"] = header[1]; item["Stage"] = header[2][0] - '0';
            item["Path"] = GitRecords.Decode(record[(tab + 1)..]);
        }
        else item["Path"] = GitRecords.Decode(record);
        ((IList)GitRecords.Unwrap(data["Files"])!).Add(item);
    }
}
