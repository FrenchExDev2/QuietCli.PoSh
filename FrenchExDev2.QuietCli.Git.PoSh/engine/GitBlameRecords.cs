using System.Collections;
using System.Globalization;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Incremental line-porcelain blame parsing with one unfinished business row.</summary>
public static class GitBlameRecords
{
    /// <summary>Consumes a header, metadata field or exact TAB-prefixed content line.</summary>
    /// <param name="record">One LF-framed byte record.</param>
    /// <param name="data">Invocation-owned Lines list and Pending cursor.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        var pending = GitRecords.Unwrap(data["Pending"]) as IDictionary;
        if (record.Length > 0 && record[0] == 9)
        {
            if (pending is null || !pending.Contains("Path")) throw new InvalidDataException("IncompleteBlameMetadata");
            pending["Content"] = GitRecords.Decode(record[1..]);
            ((IList)GitRecords.Unwrap(data["Lines"])!).Add(pending); data["Pending"] = null;
            data["GroupRemaining"] = Remaining(data) - 1;
            return;
        }
        if (pending is null)
        {
            string[] fields = Encoding.ASCII.GetString(record).Split(' ');
            if (fields.Length is < 3 or > 4 || !GitObjectRecords.IsObjectId(Encoding.ASCII.GetBytes(fields[0])))
                throw new InvalidDataException("MalformedBlameHeader");
            long original = Positive(fields[1]), final = Positive(fields[2]);
            long? count = fields.Length == 4 ? Positive(fields[3]) : null;
            long remaining = Remaining(data);
            if (remaining > 0)
            {
                if (count is not null || !Equals(GitRecords.Unwrap(data["GroupId"]), fields[0]) ||
                    Convert.ToInt64(GitRecords.Unwrap(data["LastOriginal"]), CultureInfo.InvariantCulture) + 1 != original ||
                    Convert.ToInt64(GitRecords.Unwrap(data["LastFinal"]), CultureInfo.InvariantCulture) + 1 != final)
                    throw new InvalidDataException("DiscontinuousBlameGroup");
            }
            else
            {
                if (count is null) throw new InvalidDataException("MissingBlameGroupLength");
                data["GroupRemaining"] = count.Value;
            }
            data["GroupId"] = fields[0]; data["LastOriginal"] = original; data["LastFinal"] = final;
            data["Pending"] = GitRecords.Map("ObjectId", fields[0], "OriginalLine", original, "FinalLine", final,
                "GroupLength", count, "Uncommitted", fields[0].All(c => c == '0'), "Metadata", GitRecords.Map());
            return;
        }
        int space = Array.IndexOf(record, (byte)32);
        if (space > 0 && GitObjectRecords.IsObjectId(record.AsSpan(0, space))) throw new InvalidDataException("IncompleteBlameEntry");
        int keyLength = space < 0 ? record.Length : space;
        string key = Encoding.ASCII.GetString(record, 0, keyLength);
        if (key.Length == 0 || key.Any(c => c is not (>= 'a' and <= 'z') && c is not (>= '0' and <= '9') && c != '-'))
            throw new InvalidDataException("MalformedBlameMetadata");
        var metadata = GitRecords.Dict(pending["Metadata"]);
        if (metadata.Contains(key)) throw new InvalidDataException("DuplicateBlameMetadata");
        object value = space < 0 ? true : GitRecords.Decode(record[(space + 1)..]);
        if (key == "filename")
        {
            if (space < 0) throw new InvalidDataException("MissingBlamePath");
            pending["Path"] = GitQuotedPath.Decode(record[(space + 1)..]);
        }
        metadata[key] = value;
    }
    /// <summary>Rejects a partial entry at EOF without inventing source lines.</summary>
    /// <param name="data">Invocation-owned blame state.</param>
    public static void Finish(IDictionary data)
    {
        if (GitRecords.Unwrap(data["Pending"]) is not null || Remaining(data) != 0) throw new InvalidDataException("IncompleteBlameEntry");
        foreach (string key in new[] { "Pending", "GroupRemaining", "GroupId", "LastOriginal", "LastFinal" }) data.Remove(key);
    }
    /// <summary>Reads only the parser-owned remaining group count.</summary>
    /// <param name="data">Invocation-owned state.</param>
    private static long Remaining(IDictionary data) => Convert.ToInt64(GitRecords.Unwrap(data["GroupRemaining"]), CultureInfo.InvariantCulture);
    /// <summary>Parses a positive invariant line/count field.</summary>
    /// <param name="value">ASCII decimal token.</param>
    private static long Positive(string value) => long.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out long result) && result > 0
        ? result : throw new InvalidDataException("InvalidBlameLineNumber");
}
