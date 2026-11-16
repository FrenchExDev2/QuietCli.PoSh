namespace FrenchExDev2.QuietCli;

/// <summary>Detects reparse points among a path and its ancestors, shared by callers that must not trust a redirected filesystem entry before reading or writing it.</summary>
internal static class PathGuard
{
    /// <summary>Reads attributes without turning a missing path into an exception.</summary>
    /// <param name="path">Path to inspect.</param>
    internal static FileAttributes? TryAttributes(string path)
    {
        try { return File.GetAttributes(path); }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException) { return null; }
    }

    /// <summary>True when the entry at <paramref name="path"/> exists and is a reparse point (symlink or junction), including a dangling one whose target is missing.</summary>
    /// <param name="path">Path to inspect.</param>
    internal static bool IsReparsePoint(string path) => TryAttributes(path) is { } found && (found & FileAttributes.ReparsePoint) != 0;

    /// <summary>True when <paramref name="path"/> or any of its ancestor directories up to the root is a reparse point.</summary>
    /// <param name="path">Absolute path already resolved against a known base directory.</param>
    internal static bool HasLinkedAncestor(string path)
    {
        for (string? current = path; current is not null; current = Path.GetDirectoryName(current))
            if (IsReparsePoint(current)) return true;
        return false;
    }
}
