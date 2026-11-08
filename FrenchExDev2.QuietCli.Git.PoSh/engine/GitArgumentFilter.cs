namespace FrenchExDev2.QuietCli.Git;

/// <summary>Rebuilds a native vector from a binding while dropping selected option units.</summary>
public static class GitArgumentFilter
{
    /// <summary>Removes only bound option units, preserving operands that look like flags and literal separators.</summary>
    /// <param name="binding">Git-owned argument binding.</param>
    /// <param name="remove">Exact, case-sensitive option names to drop.</param>
    /// <returns>The emitted arguments of every remaining unit, in order.</returns>
    public static string[] Without(GitBinding binding, IReadOnlyCollection<string> remove)
    {
        var result = new List<string>();
        foreach (GitArgumentUnit token in binding.Tokens)
        {
            if (token.Kind == "Option" && token.Name is not null && remove.Contains(token.Name, StringComparer.Ordinal)) continue;
            foreach (string? argument in token.EmitArguments) result.Add(argument ?? "");
        }
        return result.ToArray();
    }
}
