using System.Collections;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Caller-local parsing of Git push porcelain text; never executes Git.</summary>
public static class GitPush
{
    /// <summary>Consumes one stdout line while preserving the existing business shape.</summary>
    /// <param name="text">One framed native text record, excluding LF.</param>
    /// <param name="data">Invocation-owned remote and reference state.</param>
    public static void Receive(string text, IDictionary data)
    {
        string line = text.TrimEnd('\r');
        if (line.StartsWith("To ", StringComparison.OrdinalIgnoreCase) && line.Length > 3)
        {
            data["Remote"] = line[3..];
            return;
        }
        if (line.Length < 4 || line[1] != '\t' || " =*+!-".IndexOf(line[0]) < 0) return;
        int colon = line.IndexOf(':', 2);
        int tab = line.IndexOf('\t', 2);
        if (colon < 0 || tab < colon) return;
        var reference = new Hashtable(StringComparer.OrdinalIgnoreCase)
        {
            ["Flag"] = line[..1],
            ["From"] = line[2..colon],
            ["To"] = line[(colon + 1)..tab],
            ["Summary"] = line[(tab + 1)..],
            ["Accepted"] = line[0] != '!'
        };
        ((IList)GitRecords.Unwrap(data["References"])!).Add(reference);
    }
}
