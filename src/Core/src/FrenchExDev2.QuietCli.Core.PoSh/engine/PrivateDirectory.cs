namespace FrenchExDev2.QuietCli;

/// <summary>Creates private terminal-control directories; never stores native output.</summary>
internal static class PrivateDirectory
{
    /// <summary>Creates a new owner-only temporary directory for a terminal control socket.</summary>
    /// <param name="prefix">prefix for this native operation.</param>
    internal static string Create(string prefix)
    {
        string path = Path.Combine(Path.GetTempPath(), prefix + Guid.NewGuid().ToString("N"));
        if (OperatingSystem.IsWindows()) Directory.CreateDirectory(path);
        else Directory.CreateDirectory(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        return path;
    }
}
