using System.Collections;
using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>
/// Classifies bounded Git diagnostics (stderr) into stable business codes.
/// Patterns follow the messages emitted by Git's repository discovery and status code paths under
/// <c>LC_ALL=C</c>; they describe observed behavior and are not derived from copied source.
/// </summary>
public static class GitDiagnostics
{
    /// <summary>Maximum characters of native diagnostic text retained in a business excerpt.</summary>
    public const int MaxExcerptCharacters = 512;
    /// <summary>First single-quoted path in a diagnostic.</summary>
    private static readonly Regex quoted = new(@"'([^']*)'", RegexOptions.CultureInvariant);
    /// <summary>Unquoted path following <c>not a git repository: </c> or the newer gitfile wording.</summary>
    private static readonly Regex gitFilePath = new(@"(?:not a git repository|gitfile does not point to a valid repository): (?!\()'?([^'\r\n]+?)'?\s*$", RegexOptions.CultureInvariant | RegexOptions.Multiline);
    /// <summary>Mount-point boundary reported by discovery.</summary>
    private static readonly Regex mountPoint = new(@"or any parent up to mount point ([^)\r\n]+)\)", RegexOptions.CultureInvariant);

    /// <summary>Ordered fatal rules: the first matching rule wins, so more specific messages precede generic ones.</summary>
    private static readonly (string Code, string Pattern, string? Hint)[] fatalRules =
    [
        ("GitDubiousOwnership", "detected dubious ownership in repository", "Trust the repository explicitly with git config --global --add safe.directory <path>."),
        ("GitUnsupportedRepositoryFormat", "Expected git repo version", "Upgrade Git or inspect core.repositoryformatversion."),
        ("GitUnsupportedRepositoryFormat", "unknown repository extension", "Upgrade Git or inspect extensions.* in the repository configuration."),
        ("GitUnsupportedRepositoryFormat", "repo version is 0, but v1-only extension", "Inspect core.repositoryformatversion and extensions.*."),
        ("GitBareRepositoryForbidden", "cannot use bare repository", "safe.bareRepository forbids implicit bare repositories; pass --git-dir explicitly."),
        ("GitBrokenGitFile", "invalid gitfile format", "The .git file does not contain a valid gitdir: line."),
        ("GitBrokenGitFile", "no path in gitfile", "The .git file has an empty gitdir: line."),
        ("GitBrokenGitFile", "too large to be a .git file", "The .git entry is not a gitdir link."),
        ("GitBrokenGitFile", "gitfile does not point to a valid repository", "The .git link (worktree or submodule) points to a missing or invalid git directory."),
        ("NotARepository", "not a git repository (or any", null),
        ("GitBrokenGitFile", "not a git repository: ", "The .git link (worktree or submodule) points to a missing or invalid git directory."),
        ("NotAWorkTree", "this operation must be run in a work tree", null),
        ("GitCorruptIndex", "index file corrupt", "Rebuild the index (for example: remove .git/index then git reset)."),
        ("GitCorruptIndex", "bad signature", "Rebuild the index (for example: remove .git/index then git reset)."),
        ("GitCorruptIndex", "index file smaller than expected", "Rebuild the index (for example: remove .git/index then git reset)."),
        ("GitCorruptIndex", "unknown index entry format", "Rebuild the index with a compatible Git version."),
        ("GitPathspecOutsideRepository", "is outside repository", "Pathspecs must stay inside the working tree."),
        ("GitInvalidArgument", "Invalid untracked files mode", null),
        ("GitInvalidArgument", "Invalid ignored mode", null),
        ("GitInvalidArgument", "unsupported porcelain version", null),
        ("GitInvalidArgument", "unknown option", null),
        ("GitInvalidArgument", "unknown switch", null),
    ];

    /// <summary>Classifies the diagnostic of a failed native Git invocation.</summary>
    /// <param name="stderr">Bounded stderr text, possibly null or empty.</param>
    /// <param name="exitCode">Native exit code, when known.</param>
    /// <returns>A map with Code, Severity, Path, Hint and Excerpt.</returns>
    public static Hashtable Classify(string? stderr, int? exitCode)
    {
        string text = stderr ?? string.Empty;
        foreach (var (code, pattern, hint) in fatalRules)
        {
            if (text.Contains(pattern, StringComparison.Ordinal)) return Result(code, "Error", PathOf(code, text), hint, text);
        }
        if (exitCode == 129) return Result("GitInvalidArgument", "Error", null, null, text);
        return Result("GitUnclassified", "Error", null, null, text);
    }

    /// <summary>Extracts non-fatal warnings from the stderr of a successful invocation.</summary>
    /// <param name="stderr">Bounded stderr text.</param>
    /// <returns>Ordered warning maps; <c>UnreadableDirectory</c> marks an incomplete enumeration.</returns>
    public static List<Hashtable> Warnings(string? stderr)
    {
        var result = new List<Hashtable>();
        if (string.IsNullOrEmpty(stderr)) return result;
        foreach (string raw in stderr.Split('\n'))
        {
            string line = raw.TrimEnd('\r');
            if (!line.StartsWith("warning: ", StringComparison.Ordinal)) continue;
            if (line.Contains("could not open directory", StringComparison.Ordinal))
                result.Add(Result("UnreadableDirectory", "Warning", quoted.Match(line) is { Success: true } m ? m.Groups[1].Value : null, "Untracked enumeration skipped an unreadable directory; the answer is incomplete.", line));
            else
                result.Add(Result("GitWarning", "Warning", null, null, line));
        }
        return result;
    }

    /// <summary>True when a warning code means that the status answer does not cover the whole working tree.</summary>
    /// <param name="code">Diagnostic code.</param>
    public static bool MakesAnswerIncomplete(string? code) => code == "UnreadableDirectory";

    /// <summary>Finds the path a diagnostic refers to, according to its code.</summary>
    /// <param name="code">Classified code.</param>
    /// <param name="text">Diagnostic text.</param>
    private static string? PathOf(string code, string text)
    {
        if (code == "NotARepository") return mountPoint.Match(text) is { Success: true } mount ? mount.Groups[1].Value.Trim() : null;
        if (code == "GitBrokenGitFile" && gitFilePath.Match(text) is { Success: true } link) return link.Groups[1].Value.Trim();
        return quoted.Match(text) is { Success: true } match ? match.Groups[1].Value : null;
    }

    /// <summary>Builds one bounded diagnostic map.</summary>
    /// <param name="code">Stable business code.</param>
    /// <param name="severity">Error or Warning.</param>
    /// <param name="path">Referenced path, if any.</param>
    /// <param name="hint">Remediation hint, if any.</param>
    /// <param name="text">Native diagnostic text.</param>
    private static Hashtable Result(string code, string severity, string? path, string? hint, string text)
    {
        string excerpt = text.Trim();
        // The truncation marker counts toward the bound.
        if (excerpt.Length > MaxExcerptCharacters) excerpt = excerpt[..(MaxExcerptCharacters - 1)] + "…";
        return GitRecords.Map("Code", code, "Severity", severity, "Path", path, "Hint", hint, "Excerpt", excerpt);
    }
}
