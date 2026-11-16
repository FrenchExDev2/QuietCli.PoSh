using System.Collections;
using System.Globalization;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>NUL-framed non-combined raw diffs without changing native recursion semantics.</summary>
public static class GitRawDiffRecords
{
    /// <summary>Consumes one raw header or exact source/destination path.</summary>
    /// <param name="record">One NUL-framed field.</param>
    /// <param name="data">Invocation-owned Files/Commits and unfinished path state.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        if (GitRecords.Unwrap(data["Pending"]) is IDictionary pending)
        {
            if (record.Length == 0) throw new InvalidDataException("EmptyRawDiffPath");
            int remaining = Convert.ToInt32(GitRecords.Unwrap(data["PendingPaths"]), CultureInfo.InvariantCulture);
            if (remaining == 2) { pending["OldPath"] = GitRecords.Decode(record); data["PendingPaths"] = 1; return; }
            pending["Path"] = GitRecords.Decode(record);
            if (!pending.Contains("OldPath")) pending["OldPath"] = pending["Path"];
            ((IList)GitRecords.Unwrap(data["Files"])!).Add(pending); data["Pending"] = null; data["PendingPaths"] = 0;
            return;
        }
        if (GitObjectRecords.IsObjectId(record)) { ((IList)GitRecords.Unwrap(data["Commits"])!).Add(Encoding.ASCII.GetString(record)); return; }
        int newline = Array.IndexOf(record, (byte)10);
        if (newline > 0 && GitObjectRecords.IsObjectId(record.AsSpan(0, newline)))
        {
            ((IList)GitRecords.Unwrap(data["Commits"])!).Add(Encoding.ASCII.GetString(record, 0, newline));
            record = record[(newline + 1)..];
            if (record.Length == 0) return;
        }
        string[] fields = Encoding.ASCII.GetString(record).Split(' ');
        if (fields.Length != 5 || fields[0].Length != 7 || fields[0][0] != ':' || !Mode(fields[0][1..]) || !Mode(fields[1]) ||
            !GitObjectRecords.IsObjectId(Encoding.ASCII.GetBytes(fields[2])) || !GitObjectRecords.IsObjectId(Encoding.ASCII.GetBytes(fields[3])))
            throw new InvalidDataException("MalformedRawDiffHeader");
        string status = fields[4];
        if (status.Length == 0 || "ACDMRTUXB".IndexOf(status[0]) < 0) throw new InvalidDataException("InvalidRawDiffStatus");
        int? score = null;
        if (status.Length > 1)
        {
            if (status[0] is not ('R' or 'C' or 'M') || !int.TryParse(status[1..], NumberStyles.None, CultureInfo.InvariantCulture, out int parsed) || parsed > 100)
                throw new InvalidDataException("InvalidRawDiffScore");
            score = parsed;
        }
        else if (status[0] is 'R' or 'C') throw new InvalidDataException("MissingRawDiffScore");
        data["Pending"] = GitRecords.Map("OldMode", fields[0][1..], "NewMode", fields[1], "OldObjectId", fields[2], "NewObjectId", fields[3], "Status", status[..1], "Score", score);
        data["PendingPaths"] = status[0] is 'R' or 'C' ? 2 : 1;
    }
    /// <summary>Rejects a header whose path fields have not arrived.</summary>
    /// <param name="data">Invocation-owned raw-diff state.</param>
    public static void Finish(IDictionary data)
    {
        if (GitRecords.Unwrap(data["Pending"]) is not null) throw new InvalidDataException("IncompleteRawDiffPaths");
        data.Remove("Pending"); data.Remove("PendingPaths");
    }
    /// <summary>Validates a six-digit octal mode.</summary>
    /// <param name="text">Native mode token.</param>
    private static bool Mode(string text) => text.Length == 6 && text.All(c => c is >= '0' and <= '7');
}
