using System.Buffers.Binary;
using System.Collections;
using System.Globalization;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>
/// Cheap, read-only repository observations used by the status handler: index header, in-progress
/// operations and size classes. Nothing here launches Git or walks history; every read is bounded.
/// </summary>
public static class GitRepositoryProfile
{
    /// <summary>Maximum bytes read from one small state file under the git directory.</summary>
    public const int MaxStateFileBytes = 4096;
    /// <summary>Checkout size thresholds (index entries): Small, Medium, Large lower bounds of the next class.</summary>
    public static readonly long[] CheckoutThresholds = [1_000, 20_000, 200_000];
    /// <summary>History size thresholds (loose plus packed objects).</summary>
    public static readonly long[] HistoryThresholds = [10_000, 500_000, 5_000_000];
    /// <summary>Change-volume thresholds: at most Few entries are listed, at most Many before Massive.</summary>
    public static readonly long[] ChangeThresholds = [20, 1_000];
    /// <summary>Untracked enumeration delay above which Git itself advises a cheaper mode (milliseconds).</summary>
    public const long SlowStatusMilliseconds = 2_000;
    /// <summary>Ordered size class names.</summary>
    private static readonly string[] sizeClasses = ["Small", "Medium", "Large", "Huge"];

    /// <summary>Reads the 12-byte index header (signature, version, entry count) without reading entries.</summary>
    /// <param name="path">Absolute index path as resolved by <c>rev-parse --git-path index</c>.</param>
    /// <returns>Map with Available, Version, Entries and Reason; never throws for missing or malformed files.</returns>
    public static Hashtable ReadIndexHeader(string? path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return GitRecords.Map("Available", false, "Version", null, "Entries", 0L, "Reason", "NoIndex");
        try
        {
            using var handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            Span<byte> header = stackalloc byte[12];
            int read = RandomAccess.Read(handle, header, 0);
            return ParseIndexHeader(header[..read]);
        }
        catch (IOException) { return GitRecords.Map("Available", false, "Version", null, "Entries", null, "Reason", "Unreadable"); }
        catch (UnauthorizedAccessException) { return GitRecords.Map("Available", false, "Version", null, "Entries", null, "Reason", "Unreadable"); }
    }

    /// <summary>Default number of loose object names enumerated before the remainder is extrapolated.</summary>
    public const long DefaultLooseObjectLimit = 200_000;

    /// <summary>
    /// Counts the objects of a local object directory without launching Git: packed objects come from the last
    /// fan-out entry of each pack index (1 KiB read per pack), pack bytes from the <c>.pack</c> sizes, and loose objects
    /// from file names under the 256 fan-out directories (names only, never stat'ed). Like
    /// <c>git count-objects -v</c>, alternates are not included and duplicate objects across packs are counted
    /// once per pack.
    /// </summary>
    /// <param name="objectsDirectory">Absolute objects directory as resolved by <c>rev-parse --git-path objects</c>.</param>
    /// <param name="hashHexLength">Object name length in hex digits (40 for SHA-1, 64 for SHA-256).</param>
    /// <param name="looseLimit">Loose names enumerated before extrapolating from the fan-out directories already read.</param>
    /// <returns>Map with Available, Loose, Packed, Packs, PackBytes, Alternates, Approximate and Reason; never throws for I/O.</returns>
    public static Hashtable CountObjects(string? objectsDirectory, int hashHexLength = 40, long looseLimit = DefaultLooseObjectLimit)
    {
        if (string.IsNullOrEmpty(objectsDirectory) || !Directory.Exists(objectsDirectory))
            return GitRecords.Map("Available", false, "Loose", null, "Packed", null, "Packs", 0L, "PackBytes", null, "Alternates", 0L, "Approximate", false, "Reason", "NoObjectDirectory");
        try
        {
            long packed = 0, packs = 0, packBytes = 0; bool approximate = false;
            string packDirectory = System.IO.Path.Combine(objectsDirectory, "pack");
            if (Directory.Exists(packDirectory))
            {
                foreach (string index in Directory.EnumerateFiles(packDirectory, "*.idx"))
                {
                    string pack = System.IO.Path.ChangeExtension(index, ".pack");
                    if (!File.Exists(pack)) continue;
                    // A concurrent repack may delete a pack between enumeration and read: count it as missing.
                    long? count; long bytes;
                    try { count = ReadPackIndexCount(index); bytes = new FileInfo(pack).Length; }
                    catch (IOException) { approximate = true; continue; }
                    if (count is null) { approximate = true; continue; }
                    packed += count.Value; packs++; packBytes += bytes;
                }
            }
            long loose = 0; int scanned = 0; int nameLength = hashHexLength - 2;
            for (int fan = 0; fan < 256; fan++)
            {
                string directory = System.IO.Path.Combine(objectsDirectory, fan.ToString("x2", CultureInfo.InvariantCulture));
                scanned++;
                if (!Directory.Exists(directory)) continue;
                foreach (string file in Directory.EnumerateFiles(directory))
                {
                    string name = System.IO.Path.GetFileName(file);
                    if (name.Length == nameLength && name.All(char.IsAsciiHexDigitLower)) loose++;
                }
                if (loose > looseLimit && fan < 255) { loose = loose * 256 / scanned; approximate = true; break; }
            }
            return GitRecords.Map("Available", true, "Loose", loose, "Packed", packed, "Packs", packs, "PackBytes", packBytes,
                "Alternates", CountAlternates(System.IO.Path.Combine(objectsDirectory, "info", "alternates")), "Approximate", approximate, "Reason", null);
        }
        catch (IOException) { return GitRecords.Map("Available", false, "Loose", null, "Packed", null, "Packs", 0L, "PackBytes", null, "Alternates", 0L, "Approximate", false, "Reason", "Unreadable"); }
        catch (UnauthorizedAccessException) { return GitRecords.Map("Available", false, "Loose", null, "Packed", null, "Packs", 0L, "PackBytes", null, "Alternates", 0L, "Approximate", false, "Reason", "Unreadable"); }
    }

    /// <summary>Reads the object count of one pack index (version 1 or 2) from its last fan-out entry.</summary>
    /// <param name="path">Pack index path.</param>
    /// <returns>The object count, or null for an unknown or truncated index.</returns>
    public static long? ReadPackIndexCount(string path)
    {
        using var handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        Span<byte> header = stackalloc byte[8 + 256 * 4];
        int read = RandomAccess.Read(handle, header, 0);
        return ParsePackIndexCount(header[..read]);
    }

    /// <summary>Parses the object count from a pack index prefix.</summary>
    /// <param name="prefix">At least the first 1 032 bytes (version 2) or 1 024 bytes (version 1) of the index.</param>
    /// <returns>The object count, or null when the prefix is truncated or of an unknown version.</returns>
    public static long? ParsePackIndexCount(ReadOnlySpan<byte> prefix)
    {
        int fanout = 0;
        if (prefix.Length >= 8 && prefix[..4].SequenceEqual((ReadOnlySpan<byte>)[0xFF, (byte)'t', (byte)'O', (byte)'c']))
        {
            if (BinaryPrimitives.ReadUInt32BigEndian(prefix[4..8]) != 2) return null;
            fanout = 8;
        }
        int last = fanout + 255 * 4;
        if (prefix.Length < last + 4) return null;
        return BinaryPrimitives.ReadUInt32BigEndian(prefix[last..(last + 4)]);
    }

    /// <summary>Counts the configured alternate object directories (non-empty, non-comment lines).</summary>
    /// <param name="path">objects/info/alternates path.</param>
    private static long CountAlternates(string path)
    {
        if (!File.Exists(path) || new FileInfo(path).Length > 64 * 1024) return 0;
        return File.ReadLines(path).LongCount(line => line.Trim().Length > 0 && !line.TrimStart().StartsWith('#'));
    }

    /// <summary>Parses an index header prefix.</summary>
    /// <param name="header">At most the first 12 bytes of the index.</param>
    public static Hashtable ParseIndexHeader(ReadOnlySpan<byte> header)
    {
        if (header.Length < 12) return GitRecords.Map("Available", false, "Version", null, "Entries", null, "Reason", "Truncated");
        if (!header[..4].SequenceEqual("DIRC"u8)) return GitRecords.Map("Available", false, "Version", null, "Entries", null, "Reason", "BadSignature");
        uint version = BinaryPrimitives.ReadUInt32BigEndian(header[4..8]);
        if (version is < 2 or > 4) return GitRecords.Map("Available", false, "Version", (long)version, "Entries", null, "Reason", "UnknownVersion");
        return GitRecords.Map("Available", true, "Version", (long)version, "Entries", (long)BinaryPrimitives.ReadUInt32BigEndian(header[8..12]), "Reason", null);
    }

    /// <summary>
    /// Detects in-progress operations from per-worktree git-directory files, in the same order Git's long
    /// status reports them. Several operations can coexist (for example bisect during a rebase).
    /// </summary>
    /// <param name="paths">Absolute paths keyed MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD, rebase-merge, rebase-apply, BISECT_LOG, BISECT_START, sequencer.</param>
    /// <param name="pseudoRefs">Optional CHERRY_PICK_HEAD/REVERT_HEAD object IDs resolved through the ref backend (reftable); when a key is present it overrides the file check.</param>
    /// <param name="conflicted">Number of unmerged entries observed by status.</param>
    public static List<Hashtable> Operations(IDictionary paths, IDictionary? pseudoRefs, long conflicted)
    {
        var result = new List<Hashtable>();
        string? Path(string key) => GitRecords.Unwrap(paths[key]) as string;
        if (FirstLine(Path("MERGE_HEAD")) is { } merge)
            result.Add(GitRecords.Map("Kind", "Merge", "Head", merge, "Conflicts", conflicted, "ReadyToCommit", conflicted == 0));
        if (Path("rebase-apply") is { } apply && Directory.Exists(apply))
        {
            if (File.Exists(System.IO.Path.Combine(apply, "applying")))
            {
                var patch = new FileInfo(System.IO.Path.Combine(apply, "patch"));
                result.Add(GitRecords.Map("Kind", "Am", "Step", Number(System.IO.Path.Combine(apply, "next")), "Total", Number(System.IO.Path.Combine(apply, "last")), "EmptyPatch", patch.Exists && patch.Length == 0, "Conflicts", conflicted));
            }
            else
                result.Add(Rebase("RebaseApply", apply, "next", "last", false, conflicted));
        }
        else if (Path("rebase-merge") is { } merging && Directory.Exists(merging))
            result.Add(Rebase("Rebase", merging, "msgnum", "end", File.Exists(System.IO.Path.Combine(merging, "interactive")), conflicted));
        string? cherry = PseudoRef(pseudoRefs, "CHERRY_PICK_HEAD", Path("CHERRY_PICK_HEAD"));
        string? revert = PseudoRef(pseudoRefs, "REVERT_HEAD", Path("REVERT_HEAD"));
        if (cherry is not null) result.Add(GitRecords.Map("Kind", "CherryPick", "Head", cherry, "Conflicts", conflicted));
        if (revert is not null) result.Add(GitRecords.Map("Kind", "Revert", "Head", revert, "Conflicts", conflicted));
        if (cherry is null && revert is null && Path("sequencer") is { } sequencer && File.Exists(System.IO.Path.Combine(sequencer, "todo")))
            result.Add(GitRecords.Map("Kind", "Sequence", "Remaining", TodoLines(System.IO.Path.Combine(sequencer, "todo")), "Conflicts", conflicted));
        if (Path("BISECT_LOG") is { } bisect && File.Exists(bisect))
            result.Add(GitRecords.Map("Kind", "Bisect", "From", FirstLine(Path("BISECT_START"))));
        return result;
    }

    /// <summary>Classifies a measured size against ascending thresholds.</summary>
    /// <param name="value">Measured value, null when unknown.</param>
    /// <param name="thresholds">Ascending lower bounds of Medium, Large and Huge.</param>
    public static string SizeClass(long? value, long[] thresholds)
    {
        if (value is not long measured || measured < 0) return "Unknown";
        int index = 0;
        while (index < thresholds.Length && measured >= thresholds[index]) index++;
        return sizeClasses[index];
    }

    /// <summary>Classifies the number of changed entries.</summary>
    /// <param name="changed">Changed entry count (tracked changes plus untracked).</param>
    public static string ChangeClass(long changed) => changed <= 0 ? "Clean" : changed <= ChangeThresholds[0] ? "Few" : changed <= ChangeThresholds[1] ? "Many" : "Massive";

    /// <summary>Names the repository shape from its checkout and history classes.</summary>
    /// <param name="checkout">Checkout size class.</param>
    /// <param name="history">History size class.</param>
    public static string Archetype(string checkout, string history)
    {
        bool wide = checkout is "Large" or "Huge", deep = history is "Large" or "Huge";
        if (wide && deep) return "Monorepo";
        if (deep && checkout is "Small" or "Medium") return "DeepHistory";
        if (wide && history is "Small" or "Medium") return "WideCheckout";
        if (checkout == "Small" && history == "Small") return "Small";
        return checkout == "Unknown" || history == "Unknown" ? "Unknown" : "Standard";
    }

    /// <summary>Builds the profile map from cheap measurements.</summary>
    /// <param name="indexEntries">Index entry count, null when unknown.</param>
    /// <param name="objects">Loose plus packed object count, null when unknown.</param>
    /// <param name="packBytes">Pack size in bytes, null when unknown.</param>
    /// <param name="changed">Changed entries.</param>
    /// <param name="approximateCheckout">True when a sparse index makes the entry count include sparse directories.</param>
    public static Hashtable Build(long? indexEntries, long? objects, long? packBytes, long changed, bool approximateCheckout)
    {
        string checkout = SizeClass(indexEntries, CheckoutThresholds), history = SizeClass(objects, HistoryThresholds);
        return GitRecords.Map(
            "Checkout", GitRecords.Map("Class", checkout, "IndexEntries", indexEntries, "Approximate", approximateCheckout),
            "History", GitRecords.Map("Class", history, "Objects", objects, "PackBytes", packBytes),
            "Changes", GitRecords.Map("Class", ChangeClass(changed), "Entries", changed),
            "Archetype", Archetype(checkout, history),
            "Thresholds", GitRecords.Map("Checkout", CheckoutThresholds, "History", HistoryThresholds, "Changes", ChangeThresholds, "SlowStatusMilliseconds", SlowStatusMilliseconds));
    }

    /// <summary>Derives non-blocking performance and accuracy hints from the profile and repository settings.</summary>
    /// <param name="profile">Map built by <see cref="Build"/>.</param>
    /// <param name="settings">Map with Fsmonitor, UntrackedCache (strings or null), Shallow (bool), HasUpstream (bool), UntrackedFiles (string).</param>
    /// <param name="elapsedMilliseconds">Measured status duration.</param>
    public static List<Hashtable> Hints(IDictionary profile, IDictionary settings, long elapsedMilliseconds)
    {
        var hints = new List<Hashtable>();
        string checkout = (string)GitRecords.Dict(profile["Checkout"])["Class"]!;
        bool wide = checkout is "Large" or "Huge";
        if (wide && !Enabled(settings["Fsmonitor"]))
            hints.Add(Hint("FsmonitorDisabled", "Large checkout without core.fsmonitor: status rescans every file. Consider git config core.fsmonitor true."));
        if (wide && !Enabled(settings["UntrackedCache"]))
            hints.Add(Hint("UntrackedCacheDisabled", "Large checkout without core.untrackedCache: untracked enumeration rescans directories. Consider git config core.untrackedCache true."));
        if (elapsedMilliseconds > SlowStatusMilliseconds && string.Equals(GitRecords.Unwrap(settings["UntrackedFiles"]) as string, "all", StringComparison.Ordinal))
            hints.Add(Hint("SlowUntrackedEnumeration", string.Create(CultureInfo.InvariantCulture, $"Status took {elapsedMilliseconds} ms with --untracked-files=all; -unormal or -uno are cheaper.")));
        if (GitRecords.Unwrap(settings["Shallow"]) is true && GitRecords.Unwrap(settings["HasUpstream"]) is true)
            hints.Add(Hint("ShallowDivergence", "Shallow history: ahead/behind counts can be wrong when the merge base lies beyond the shallow boundary."));
        return hints;
    }

    /// <summary>Interprets a Git boolean-ish setting (true/yes/on/1, or a hook path for fsmonitor).</summary>
    /// <param name="value">Raw configuration value, null when unset.</param>
    private static bool Enabled(object? value)
    {
        if (GitRecords.Unwrap(value) is not string text || text.Length == 0) return false;
        return text.ToLowerInvariant() is not ("false" or "no" or "off" or "0");
    }

    /// <summary>Builds one hint map.</summary>
    /// <param name="code">Stable hint code.</param>
    /// <param name="message">Human explanation.</param>
    private static Hashtable Hint(string code, string message) => GitRecords.Map("Code", code, "Severity", "Hint", "Message", message);

    /// <summary>Describes a rebase backend state directory.</summary>
    /// <param name="kind">Rebase or RebaseApply.</param>
    /// <param name="directory">State directory.</param>
    /// <param name="stepFile">File holding the current step number.</param>
    /// <param name="totalFile">File holding the total step count.</param>
    /// <param name="interactive">True for an interactive rebase.</param>
    /// <param name="conflicted">Unmerged entries.</param>
    private static Hashtable Rebase(string kind, string directory, string stepFile, string totalFile, bool interactive, long conflicted)
    {
        string? head = FirstLine(System.IO.Path.Combine(directory, "head-name"));
        if (head is not null && head.StartsWith("refs/heads/", StringComparison.Ordinal)) head = head["refs/heads/".Length..];
        return GitRecords.Map("Kind", kind, "Interactive", interactive, "Branch", head == "detached HEAD" ? null : head, "Onto", FirstLine(System.IO.Path.Combine(directory, "onto")),
            "Step", Number(System.IO.Path.Combine(directory, stepFile)), "Total", Number(System.IO.Path.Combine(directory, totalFile)), "Conflicts", conflicted);
    }

    /// <summary>Returns a pseudo-ref value from the ref backend when supplied, otherwise from its file.</summary>
    /// <param name="pseudoRefs">Backend-resolved values.</param>
    /// <param name="name">Pseudo-ref name.</param>
    /// <param name="path">File path for the files backend.</param>
    private static string? PseudoRef(IDictionary? pseudoRefs, string name, string? path)
    {
        if (pseudoRefs is not null && pseudoRefs.Contains(name)) return GitRecords.Unwrap(pseudoRefs[name]) as string is { Length: > 0 } value ? value : null;
        return FirstLine(path);
    }

    /// <summary>Reads the first line of a small state file, or null when missing or unreadable.</summary>
    /// <param name="path">Absolute file path.</param>
    public static string? FirstLine(string? path)
    {
        string? text = ReadSmall(path);
        if (text is null) return null;
        int end = text.IndexOfAny(['\r', '\n']);
        string line = (end < 0 ? text : text[..end]).Trim();
        return line.Length == 0 ? string.Empty : line;
    }

    /// <summary>Reads a bounded state file as UTF-8 text.</summary>
    /// <param name="path">Absolute file path.</param>
    private static string? ReadSmall(string? path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return null;
        try
        {
            using var handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            byte[] buffer = new byte[MaxStateFileBytes];
            int read = RandomAccess.Read(handle, buffer, 0);
            return Encoding.UTF8.GetString(buffer, 0, read);
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// <summary>Reads a small integer state file.</summary>
    /// <param name="path">Absolute file path.</param>
    private static long? Number(string path) => long.TryParse(FirstLine(path), NumberStyles.None, CultureInfo.InvariantCulture, out long value) ? value : null;

    /// <summary>Counts remaining instructions in a bounded todo file, ignoring comments and blank lines.</summary>
    /// <param name="path">Todo file path.</param>
    private static long? TodoLines(string path)
    {
        string? text = ReadSmall(path);
        if (text is null) return null;
        return text.Split('\n').Count(line => line.Trim() is { Length: > 0 } trimmed && trimmed[0] != '#');
    }
}
