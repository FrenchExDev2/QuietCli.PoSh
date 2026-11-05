using System.Security.Cryptography;

namespace FrenchExDev2.QuietCli;

/// <summary>Owns a verified executable copy without modifying an installed, possibly read-only module.</summary>
internal sealed class TerminalBridge : IAsyncDisposable
{
    /// <summary>Private directory owned by this engine alone; contains executable code, never native output.</summary>
    private string? directory;
    /// <summary>Verified path reused for this engine session.</summary>
    private string? executable;

    /// <summary>Copies the bundled bridge to an owner-only executable location after verifying its bytes.</summary>
    /// <param name="moduleRoot">Installed Core module directory, which remains unchanged.</param>
    internal async Task<string> GetAsync(string moduleRoot)
    {
        if (OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("UnixBridgeOnly");
        if (executable != null) return executable;
        string bundled = Path.Combine(moduleRoot, "resources", "transport", System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier, "quietcli-pty");
        if (!File.Exists(bundled)) throw new PlatformNotSupportedException("TransportUnavailable");
        string expected = (await File.ReadAllTextAsync(bundled + ".sha256", System.Text.Encoding.UTF8)).Trim();
        await using var source = File.OpenRead(bundled);
        if (!Convert.ToHexString(await SHA256.HashDataAsync(source)).Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("TransportIntegrityFailed");
        directory ??= PrivateDirectory.Create("quietcli2-code-");
        string destination = Path.Combine(directory, "quietcli-pty");
        var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None, Options = FileOptions.Asynchronous, UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite };
        source.Position = 0;
        await using (var output = new FileStream(destination, options)) await source.CopyToAsync(output);
        await using (var copied = File.OpenRead(destination))
            if (!Convert.ToHexString(await SHA256.HashDataAsync(copied)).Equals(expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("TransportCopyIntegrityFailed");
        File.SetUnixFileMode(destination, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        executable = destination;
        return executable;
    }

    /// <summary>Removes only this engine's private executable directory after its invocations have stopped.</summary>
    public ValueTask DisposeAsync()
    {
        if (directory != null && Directory.Exists(directory)) Directory.Delete(directory, true);
        executable = null; directory = null;
        return ValueTask.CompletedTask;
    }
}
