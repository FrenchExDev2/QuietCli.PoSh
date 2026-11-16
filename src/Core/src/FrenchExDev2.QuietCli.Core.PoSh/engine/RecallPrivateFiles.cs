namespace FrenchExDev2.QuietCli;

/// <summary>Creates Recall capture files and directories readable only by their owner; captures hold native output.</summary>
internal static class RecallPrivateFiles
{
    private const UnixFileMode OwnerFile = UnixFileMode.UserRead | UnixFileMode.UserWrite;
    private const UnixFileMode OwnerDirectory = OwnerFile | UnixFileMode.UserExecute;

    /// <summary>Creates a directory with owner-only access on Unix; Windows keeps its inherited ACL.</summary>
    /// <param name="path">Directory to create, including missing parents.</param>
    internal static void CreateDirectory(string path)
    {
        if (OperatingSystem.IsWindows()) Directory.CreateDirectory(path);
        else Directory.CreateDirectory(path, OwnerDirectory);
    }

    /// <summary>Creates a new file with owner-only access on Unix; fails if the file already exists.</summary>
    /// <param name="path">New file path.</param>
    /// <param name="access">Requested access.</param>
    /// <param name="share">Sharing allowed to other handles.</param>
    /// <param name="bufferSize">Stream buffer size.</param>
    /// <param name="options">Additional file options.</param>
    internal static FileStream CreateNew(string path, FileAccess access, FileShare share, int bufferSize, FileOptions options)
    {
        var settings = new FileStreamOptions { Mode = FileMode.CreateNew, Access = access, Share = share, BufferSize = bufferSize, Options = options };
        if (!OperatingSystem.IsWindows()) settings.UnixCreateMode = OwnerFile;
        return new(path, settings);
    }
}
