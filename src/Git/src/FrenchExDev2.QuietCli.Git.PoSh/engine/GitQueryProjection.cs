using System.Collections;
using System.Collections.Specialized;
using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Projects the textual records of simple Git queries into typed business results.</summary>
public static class GitQueryProjection
{
    /// <summary>A SHA-1 or SHA-256 object identity alone on its line.</summary>
    private static readonly Regex ObjectLine = new(@"^[0-9a-f]{40}(?:[0-9a-f]{24})?\z", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    /// <summary>An object identity followed by a reference name.</summary>
    private static readonly Regex ReferenceLine = new(@"^([0-9a-f]{40}(?:[0-9a-f]{24})?)\s+(.+)\z", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    /// <summary>One <c>count-objects -v</c> counter.</summary>
    private static readonly Regex CountLine = new(@"^([a-z-]+): ([0-9]+)\z", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    /// <summary>Queries whose lines are object identities.</summary>
    private static readonly HashSet<string> ObjectQueries = new(StringComparer.Ordinal) { "hash-object", "write-tree", "commit-tree", "mktree", "mktag", "merge-base", "rev-list" };

    /// <summary>Queries whose lines are an identity and a reference name.</summary>
    private static readonly HashSet<string> ReferenceQueries = new(StringComparer.Ordinal) { "show-ref", "ls-remote" };

    /// <summary>Projects streamed query records where a typed shape is implemented, and keeps the native text otherwise.</summary>
    /// <param name="name">Git query name.</param>
    /// <param name="lines">Explicit business records collected by the query handler.</param>
    /// <param name="exitCode">Native exit condition.</param>
    /// <param name="version">Observed Git version.</param>
    /// <returns>An ordered business record whose first keys are Command, GitVersion and ExitCode.</returns>
    public static OrderedDictionary Project(string name, IReadOnlyList<string> lines, int exitCode, string? version)
    {
        var data = new OrderedDictionary { ["Command"] = name, ["GitVersion"] = version, ["ExitCode"] = exitCode };
        if (ObjectQueries.Contains(name))
        {
            data["Objects"] = lines.Where(line => ObjectLine.IsMatch(line)).Select(line => new Hashtable { ["ObjectId"] = line, ["Algorithm"] = line.Length == 40 ? "sha1" : "sha256" }).ToArray();
        }
        else if (name == "count-objects")
        {
            var counts = new OrderedDictionary();
            foreach (string line in lines)
            {
                Match match = CountLine.Match(line);
                if (!match.Success) continue;
                if (!long.TryParse(match.Groups[2].Value, out long value)) throw new InvalidDataException("GitCountObjectsValueOutOfRange");
                counts[match.Groups[1].Value] = value;
            }
            data["Counts"] = counts;
            data["SizeUnit"] = "KiB";
        }
        else if (ReferenceQueries.Contains(name))
        {
            data["References"] = lines.Select(line => ReferenceLine.Match(line)).Where(match => match.Success).Select(match => new Hashtable { ["ObjectId"] = match.Groups[1].Value, ["Name"] = match.Groups[2].Value }).ToArray();
        }
        else if (name == "check-ref-format")
        {
            data["Valid"] = exitCode == 0;
            data["NormalizedName"] = lines.Count > 0 ? lines[0] : null;
        }
        else if (name == "symbolic-ref")
        {
            data["Exists"] = exitCode == 0;
            data["Reference"] = lines.Count > 0 ? lines[0] : null;
        }
        else
        {
            data["Records"] = lines.ToArray();
            data["Semantics"] = "Native textual records; advanced variants remain unqualified.";
        }
        return data;
    }
}
