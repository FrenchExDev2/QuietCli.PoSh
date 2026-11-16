using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Normalizes observed Git version strings.</summary>
public static class GitVersions
{
    /// <summary>Stable Git 2.x, optionally followed by a Windows package suffix.</summary>
    private static readonly Regex Stable = new(@"^(2\.[0-9]+\.[0-9]+)(?:\.windows\.[0-9]+)?\z", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    /// <summary>Normalizes a stable Git version, including Windows package suffixes.</summary>
    /// <param name="version">Observed version text.</param>
    /// <returns>The numeric version, or null for an unsupported format.</returns>
    public static Version? Numeric(string? version)
    {
        if (version is null) return null;
        Match match = Stable.Match(version);
        return match.Success && Version.TryParse(match.Groups[1].Value, out Version? parsed) ? parsed : null;
    }
}
