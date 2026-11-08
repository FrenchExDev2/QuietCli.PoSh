using System.Text;

namespace FrenchExDev2.QuietCli.Agents;

/// <summary>Locates the distributed instruction documents and guards the paths written for them.</summary>
internal static class AgentDocuments
{
    /// <summary>Strict UTF-8: invalid bytes fail instead of being replaced.</summary>
    internal static readonly UTF8Encoding StrictUtf8 = new(false, true);

    /// <summary>Selects packaged production documents, or their canonical source when running from the repository.</summary>
    /// <param name="moduleRoot">Directory of the imported module.</param>
    /// <returns>Directory that holds AGENTS.md and SKILL.md.</returns>
    internal static string Directory(string moduleRoot)
    {
        string packaged = Path.Combine(moduleRoot, "resources", "agents");
        if (System.IO.Directory.Exists(packaged)) return packaged;
        string? repository = Path.GetDirectoryName(moduleRoot);
        if (repository is not null && File.Exists(Path.Combine(repository, "scripts", "New-WorkspacePackage.ps1")))
            return Path.Combine(repository, "docs", "agents");
        throw new InvalidOperationException("AgentInstructionResourcesMissing");
    }

    /// <summary>Reads the distributed AGENTS.md as strict UTF-8.</summary>
    /// <param name="moduleRoot">Directory of the imported module.</param>
    internal static string ReadInstructions(string moduleRoot) =>
        StrictUtf8.GetString(File.ReadAllBytesAsync(Path.Combine(Directory(moduleRoot), "AGENTS.md")).GetAwaiter().GetResult());

    /// <summary>Rejects linked ancestors and managed document/target collisions before a write.</summary>
    /// <param name="path">Absolute write destination.</param>
    /// <param name="protectedPaths">Distributed sources and selected project instruction files that must not be overwritten.</param>
    internal static void AssertWritable(string path, IEnumerable<string> protectedPaths)
    {
        StringComparison comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        foreach (string guarded in protectedPaths)
            if (string.Equals(path, guarded, comparison)) throw new InvalidOperationException("AgentInstructionPathConflict");
        for (string? current = path; current is not null; current = Path.GetDirectoryName(current))
        {
            FileAttributes? attributes = TryAttributes(current);
            if (attributes is { } found)
            {
                if ((found & FileAttributes.ReparsePoint) != 0) throw new InvalidOperationException("AgentInstructionLinkedPath");
                if ((found & FileAttributes.Directory) == 0 && current != path) throw new InvalidOperationException("AgentInstructionAncestorIsFile");
            }
        }
        if (System.IO.Directory.Exists(path)) throw new InvalidOperationException("AgentInstructionTargetIsDirectory");
    }

    /// <summary>Reads attributes without following a missing path into an exception.</summary>
    private static FileAttributes? TryAttributes(string path)
    {
        try { return File.GetAttributes(path); }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException) { return null; }
    }
}
