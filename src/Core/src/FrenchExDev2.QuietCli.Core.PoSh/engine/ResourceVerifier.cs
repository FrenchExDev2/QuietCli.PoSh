using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli;

/// <summary>Checks pinned resources before they are loaded; hashes do not authenticate the distributor.</summary>
public static partial class ResourceVerifier
{
    /// <summary>One pinned resource from the inventory.</summary>
    /// <param name="Path">Module-relative path under <c>resources/</c>.</param>
    /// <param name="Sha256">Expected upper-case hexadecimal digest.</param>
    private sealed record Entry(string Path, string Sha256);

    /// <summary>Files whose length, write time and digest already matched in this process.</summary>
    private static readonly Dictionary<string, string> verified = new(StringComparer.Ordinal);
    /// <summary>Guards the memo and the parsed inventory.</summary>
    private static readonly object gate = new();
    /// <summary>Parsed inventory and the stamp of the file it came from.</summary>
    private static Entry[]? inventory;
    private static string? inventoryStamp;

    /// <summary>Forgets every memoized result, for a new module session.</summary>
    public static void Reset()
    {
        lock (gate) { verified.Clear(); inventory = null; inventoryStamp = null; }
    }

    /// <summary>
    /// Without a path, verifies what the engine loads at startup: the native files built for this platform. Managed resources that
    /// carry no platform (YAML and tokenizers) are verified by the code that loads them. A file whose length and write time match an
    /// earlier successful check is not hashed again in this process.
    /// </summary>
    /// <param name="root">Module root directory.</param>
    /// <param name="relativePath">Optional single managed resource for an explicit load.</param>
    /// <param name="runtimeIdentifier">Platform used to filter native files; defaults to the current one.</param>
    /// <exception cref="InvalidDataException">The message is the stable error code.</exception>
    public static async Task VerifyAsync(string root, string? relativePath = null, string? runtimeIdentifier = null)
    {
        Entry[] files = Select(LoadInventory(root), relativePath, runtimeIdentifier ?? RuntimeInformation.RuntimeIdentifier);
        foreach (Entry file in files) {
            if (!SafePath().IsMatch(file.Path) || file.Path.Split('/').Contains("..")) throw new InvalidDataException("DependencyUnsafePath");
            var info = new FileInfo(Path.Combine(root, file.Path));
            if (!info.Exists) throw new InvalidDataException("DependencyIntegrityFailed: " + file.Path);
            string stamp = $"{info.Length}:{info.LastWriteTimeUtc.Ticks}:{file.Sha256}";
            lock (gate) { if (verified.TryGetValue(file.Path, out string? known) && known == stamp) continue; }
            string hash;
            await using (var stream = new FileStream(info.FullName, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, true))
                hash = Convert.ToHexString(await SHA256.HashDataAsync(stream));
            if (!string.Equals(hash, file.Sha256, StringComparison.Ordinal)) throw new InvalidDataException("DependencyIntegrityFailed: " + file.Path);
            lock (gate) verified[file.Path] = stamp;
        }
    }

    /// <summary>Blocking form for cmdlets, which run on the caller's pipeline thread.</summary>
    /// <param name="root">Module root directory.</param>
    /// <param name="relativePath">Optional single managed resource.</param>
    public static void Verify(string root, string? relativePath = null) => VerifyAsync(root, relativePath).GetAwaiter().GetResult();

    /// <summary>Applies the single-path filter or the platform filter to an inventory.</summary>
    /// <param name="all">Complete inventory.</param>
    /// <param name="relativePath">Optional exact path.</param>
    /// <param name="runtimeIdentifier">Current platform.</param>
    private static Entry[] Select(Entry[] all, string? relativePath, string runtimeIdentifier)
    {
        Entry[] files = string.IsNullOrEmpty(relativePath) ? all : all.Where(entry => entry.Path == relativePath).ToArray();
        if (files.Length == 0) throw new InvalidDataException("DependencyNotInventoried");
        if (!string.IsNullOrEmpty(relativePath)) return files;
        // An unknown platform keeps the complete check rather than silently verifying nothing.
        Entry[] platform = files.Where(entry => PlatformPath().Match(entry.Path) is { Success: true } match && match.Groups[1].Value == runtimeIdentifier).ToArray();
        return platform.Length > 0 ? platform : files;
    }

    /// <summary>Parses the inventory again only when the file changed.</summary>
    /// <param name="root">Module root directory.</param>
    private static Entry[] LoadInventory(string root)
    {
        var info = new FileInfo(Path.Combine(root, "resources", "dependencies.lock.json"));
        if (!info.Exists) throw new InvalidDataException("DependencyManifestMissing");
        string stamp = $"{info.Length}:{info.LastWriteTimeUtc.Ticks}";
        lock (gate) { if (inventory != null && inventoryStamp == stamp) return inventory; }
        using JsonDocument document = JsonDocument.Parse(File.ReadAllText(info.FullName, System.Text.Encoding.UTF8));
        Entry[] parsed = document.RootElement.GetProperty("Files").EnumerateArray()
            .Select(file => new Entry(file.GetProperty("Path").GetString()!, file.GetProperty("SHA256").GetString()!)).ToArray();
        lock (gate) { inventory = parsed; inventoryStamp = stamp; }
        return parsed;
    }

    [GeneratedRegex("^resources/[A-Za-z0-9_./-]+$")]
    private static partial Regex SafePath();

    [GeneratedRegex("^resources/(?:runtime/runtimes|transport)/([^/]+)/")]
    private static partial Regex PlatformPath();
}
