using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli.Agents;

/// <summary>Builds the managed instruction reference block that Add-QuietAgentInstruction places in project Markdown.</summary>
public static class AgentReferenceBlock
{
    /// <summary>First line of the managed block.</summary>
    internal const string Begin = "<!-- quietcli:instructions:begin -->";

    /// <summary>Last line of the managed block.</summary>
    internal const string End = "<!-- quietcli:instructions:end -->";

    /// <summary>A reference lands in a file read by agents: a line break or control character would inject instruction lines.</summary>
    private static readonly Regex UnsafeReference = new(@"[\x00-\x1f\x7f\u0085  ]", RegexOptions.CultureInvariant);

    /// <summary>Detects the newline style of the existing text.</summary>
    private static readonly Regex Newline = new(@"\r\n|\n|\r", RegexOptions.CultureInvariant);

    /// <summary>Replaces one well-formed managed block, or appends it, preserving all surrounding text and its newline style.</summary>
    /// <param name="text">Strictly decoded existing project Markdown, including any BOM.</param>
    /// <param name="reference">Project-relative document path.</param>
    /// <param name="claude">Uses a Claude import reference instead of a Markdown link.</param>
    /// <returns>The complete updated text.</returns>
    public static string Apply(string text, string reference, bool claude)
    {
        if (UnsafeReference.IsMatch(reference)) throw new InvalidOperationException("AgentInstructionReferenceInvalid");
        int startCount = Count(text, Begin), endCount = Count(text, End);
        int start = text.IndexOf(Begin, StringComparison.Ordinal), end = text.IndexOf(End, StringComparison.Ordinal);
        if ((startCount > 0 || endCount > 0) && (startCount != 1 || endCount != 1 || start >= end)) throw new InvalidOperationException("AgentInstructionMalformedBlock");
        Match first = Newline.Match(text);
        string newline = first.Success ? first.Value : "\n";
        var lines = new List<string> { Begin, "## QuietCli" };
        if (claude)
        {
            lines.Add("Before running commands, read and apply the QuietCli instructions at the following path:");
            lines.Add("@" + reference.Replace(" ", "\\ "));
        }
        else
        {
            string link = reference.Replace("%", "%25").Replace("\\", "%5C").Replace("<", "%3C").Replace(">", "%3E").Replace("#", "%23").Replace("?", "%3F");
            lines.Add($"Before running commands, read and apply the [QuietCli instructions](<{link}>).");
        }
        lines.Add(End);
        string block = string.Join(newline, lines);
        if (startCount == 1) return string.Concat(text.AsSpan(0, start), block, text.AsSpan(end + End.Length));
        string separator = text.Length > 0 && text[^1] is not ('\r' or '\n') ? newline : "";
        return text + separator + block + newline;
    }

    /// <summary>Counts non-overlapping ordinal occurrences.</summary>
    private static int Count(string text, string marker)
    {
        int count = 0;
        for (int index = text.IndexOf(marker, StringComparison.Ordinal); index >= 0; index = text.IndexOf(marker, index + marker.Length, StringComparison.Ordinal)) count++;
        return count;
    }
}
