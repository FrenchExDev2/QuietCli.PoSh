using System.Collections;
using System.Globalization;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Fixed NUL attribute/ignore protocols, including leading empty nonmatching fields.</summary>
public static class GitPathCheckRecords
{
    /// <summary>Encodes logical argv paths as the equivalent documented NUL stdin list.</summary>
    /// <param name="paths">Already bound path operands.</param>
    public static byte[] EncodePaths(string[] paths)
    {
        if (paths.Any(path => path.Contains('\0'))) throw new InvalidDataException("NullPathOperand");
        return Encoding.UTF8.GetBytes(string.Join('\0', paths) + "\0");
    }
    /// <summary>Consumes exactly three attribute fields or four verbose ignore fields.</summary>
    /// <param name="record">One NUL-delimited field, including empty fields.</param>
    /// <param name="data">Invocation-owned Fields list, Kind and Entries list.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        if (GitRecords.Unwrap(data["Fields"]) is not List<byte[]> fields) { fields = []; data["Fields"] = fields; }
        bool attribute = Equals(GitRecords.Unwrap(data["Kind"]), "Attribute");
        fields.Add(record);
        int count = attribute ? 3 : 4;
        if (fields.Count < count) return;
        Hashtable entry;
        if (attribute)
        {
            if (fields[0].Length == 0 || fields[1].Length == 0) throw new InvalidDataException("MissingAttributeField");
            entry = GitRecords.Map("Path", GitRecords.Decode(fields[0]), "Attribute", GitRecords.Decode(fields[1]), "Value", GitRecords.Decode(fields[2]));
        }
        else
        {
            if (fields[3].Length == 0) throw new InvalidDataException("MissingIgnorePath");
            long? line = null;
            if (fields[1].Length > 0)
            {
                if (!long.TryParse(Encoding.ASCII.GetString(fields[1]), NumberStyles.None, CultureInfo.InvariantCulture, out long parsed) || parsed < 1)
                    throw new InvalidDataException("InvalidIgnoreLine");
                line = parsed;
            }
            else if (fields[0].Length > 0 || fields[2].Length > 0) throw new InvalidDataException("IncompleteIgnoreRule");
            bool negated = fields[2].Length > 0 && fields[2][0] == 33;
            entry = GitRecords.Map("Source", GitRecords.Decode(fields[0]), "Line", line, "Pattern", GitRecords.Decode(fields[2]), "Path", GitRecords.Decode(fields[3]), "Ignored", line is not null && !negated, "Negated", negated);
        }
        ((IList)GitRecords.Unwrap(data["Entries"])!).Add(entry); fields.Clear();
    }
    /// <summary>Rejects partial groups at EOF.</summary>
    /// <param name="data">Invocation-owned check state.</param>
    public static void Finish(IDictionary data)
    {
        if (GitRecords.Unwrap(data["Fields"]) is List<byte[]> fields && fields.Count != 0) throw new InvalidDataException("IncompletePathCheckGroup");
        data.Remove("Fields");
    }
}
