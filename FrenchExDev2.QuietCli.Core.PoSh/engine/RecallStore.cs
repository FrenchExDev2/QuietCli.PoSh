using System.Text.Json;
using System.Text.Json.Serialization;

namespace FrenchExDev2.QuietCli;

/// <summary>Explicit durable catalog and directory storage, independent of execution and SQLite telemetry.</summary>
public static class RecallStore
{
    internal const int ManifestLimit = 65536;
    /// <summary>Attempts to publish a checkpoint manifest before reporting the failure.</summary>
    private const int ManifestPublishAttempts = 4;
    internal static readonly JsonSerializerOptions JsonOptions = new() { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 16 };
    /// <summary>Durable user data location; the facade passes any configured root explicitly.</summary>
    public static string DefaultRoot
    {
        get
        {
            string data = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrEmpty(data))
            {
                string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                if (string.IsNullOrEmpty(home)) throw new IOException("RecallUserDataDirectoryUnavailable");
                data = Path.Combine(home, ".local", "share");
            }
            return Path.Combine(data, "QuietCli2", "recalls");
        }
    }

    /// <summary>Normalizes an identifier without permitting path traversal or name-based ambiguity.</summary>
    /// <param name="id">GUID in N or D form.</param>
    public static string NormalizeId(string id) => Guid.TryParseExact(id, "N", out var parsed) || Guid.TryParseExact(id, "D", out parsed) ? parsed.ToString("N") : throw new ArgumentException("InvalidRecallId");

    /// <summary>Creates a writer in an explicitly selected durable root.</summary>
    /// <param name="root">Store root; null selects the user data location.</param>
    /// <param name="name">Optional label.</param>
    /// <param name="settings">Inert analysis settings.</param>
    public static Task<RecallJournalWriter> CreateAsync(string? root, string? name, RecallAnalysisSettings settings)
    {
        string id = Guid.NewGuid().ToString("N");
        return RecallJournalWriter.CreateAsync(Path.Combine(Path.GetFullPath(root ?? DefaultRoot), id), id, name, settings);
    }

    /// <summary>Opens a stored identity without executing a native process.</summary>
    /// <param name="root">Store root or null.</param>
    /// <param name="id">Canonical identity, never a display name.</param>
    public static async Task<RecallCapture> OpenAsync(string? root, string id)
    {
        string expected = NormalizeId(id);
        var capture = await OpenDirectoryAsync(Path.Combine(Path.GetFullPath(root ?? DefaultRoot), expected));
        if (capture.RecallId != expected) throw new InvalidDataException("RecallStoreIdentityMismatch");
        return capture;
    }

    /// <summary>Opens a stable prefix; interrupted journals are scanned with bounded memory to recover complete records.</summary>
    /// <param name="directory">Explicit capture directory.</param>
    public static async Task<RecallCapture> OpenDirectoryAsync(string directory)
    {
        directory = Path.GetFullPath(directory); AssertPlainFile(directory);
        var metadata = await ReadManifestAsync(directory);
        string data = Path.Combine(directory, "events.bin"); AssertPlainFile(data);
        long length = new FileInfo(data).Length;
        if (metadata.State == "Completed")
        {
            if (length != metadata.JournalLength) throw new InvalidDataException("RecallJournalLengthMismatch");
            return new RecallCapture(directory, metadata, false);
        }
        bool active = IsRecording(directory);
        using var reader = new RecallJournalReader(directory, metadata.RecallId, active ? metadata.JournalLength : length, !active, metadata.JournalLength);
        while (await reader.ReadNextAsync() != null) { }
        long received = Math.Max(metadata.ReceivedBytes, reader.ObservedEnd);
        metadata = metadata with { State = active ? "Recording" : metadata.State == "Failed" ? "Failed" : "Interrupted", SourceComplete = false, ReceivedBytes = received, StoredBytes = reader.StoredBytes, EventCount = reader.EventCount, JournalLength = reader.ValidLength, GapCount = reader.GapCount + (received > reader.ObservedEnd ? 1 : 0), DurableBytes = Math.Min(metadata.DurableBytes, reader.StoredBytes) };
        return new RecallCapture(directory, metadata, !active);
    }

    /// <summary>Lists metadata only, never replays or scans business output.</summary>
    /// <param name="root">Explicit root or null.</param>
    public static async Task<IReadOnlyList<RecallSavedInfo>> ListAsync(string? root)
    {
        string path = Path.GetFullPath(root ?? DefaultRoot);
        if (!Directory.Exists(path)) return Array.Empty<RecallSavedInfo>();
        var result = new List<RecallSavedInfo>();
        foreach (string directory in Directory.EnumerateDirectories(path))
        {
            if (!Guid.TryParseExact(Path.GetFileName(directory), "N", out _)) continue;
            AssertPlainFile(directory);
            if (!File.Exists(Path.Combine(directory, "manifest.json"))) continue;
            var m = await ReadManifestAsync(directory);
            if (m.RecallId != Path.GetFileName(directory)) throw new InvalidDataException("RecallStoreIdentityMismatch");
            result.Add(new(m.RecallId, m.RecallName, m.State == "Recording" && !IsRecording(directory) ? "Interrupted" : m.State, m.CreatedUtc, m.UpdatedUtc, m.StoredBytes, m.DurableBytes, m.SourceComplete, directory));
        }
        return result.OrderByDescending(r => r.CreatedUtc).ToArray();
    }

    /// <summary>Saves a local or disk-backed capture as a new directory, retaining original identity and bytes.</summary>
    /// <param name="capture">Source evidence.</param>
    /// <param name="directory">New destination directory.</param>
    /// <param name="name">Optional label override.</param>
    public static async Task<RecallCapture> SaveDirectoryAsync(RecallCapture capture, string directory, string? name = null)
    {
        await using var writer = await RecallJournalWriter.CreateAsync(directory, capture.RecallId, name ?? capture.RecallName, capture.Settings);
        foreach (var item in capture.Events) await writer.AppendEventAsync(item);
        return await writer.CompleteAsync(capture.SourceComplete, capture.SourceStatus, capture.ReceivedBytes, capture.ParentCaptureId, capture.Transformation);
    }

    /// <summary>Reads only bounded, closed inert metadata from a plain file.</summary>
    /// <param name="directory">Capture directory whose manifest is read.</param>
    internal static async Task<RecallJournalMetadata> ReadManifestAsync(string directory)
    {
        string path = Path.Combine(directory, "manifest.json"); AssertPlainFile(path);
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete, 4096, true);
        if (stream.Length > ManifestLimit) throw new InvalidDataException("RecallManifestLimit");
        byte[] bytes = new byte[(int)stream.Length]; await stream.ReadExactlyAsync(bytes);
        var metadata = JsonSerializer.Deserialize<RecallJournalMetadata>(bytes, JsonOptions) ?? throw new InvalidDataException("RecallManifestInvalid");
        Validate(metadata); return metadata;
    }

    /// <summary>Synchronizes metadata to a unique temporary file and atomically publishes it.</summary>
    /// <param name="directory">Owned recording directory.</param>
    /// <param name="metadata">Closed checkpoint metadata.</param>
    internal static async Task WriteManifestAsync(string directory, RecallJournalMetadata metadata)
    {
        Validate(metadata);
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(metadata, JsonOptions);
        if (bytes.Length > ManifestLimit) throw new InvalidDataException("RecallManifestLimit");
        string temporary = Path.Combine(directory, "manifest-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            await using (var file = RecallPrivateFiles.CreateNew(temporary, FileAccess.Write, FileShare.None, 4096, FileOptions.Asynchronous | FileOptions.WriteThrough)) { await file.WriteAsync(bytes); await file.FlushAsync(); }
            // A concurrent reader, scanner or indexer can briefly hold the destination; retry a few times before failing.
            for (int attempt = 1; ; attempt++)
            {
                try { File.Move(temporary, Path.Combine(directory, "manifest.json"), true); return; }
                catch (Exception failure) when (failure is IOException or UnauthorizedAccessException && attempt < ManifestPublishAttempts) { await Task.Delay(25 * attempt); }
            }
        }
        catch
        {
            // The unique temporary file is never reused, so a failed checkpoint must not leave it behind.
            try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            throw;
        }
    }

    /// <summary>Validates checked counter relationships, identity and inert analysis settings.</summary>
    /// <param name="m">Untrusted or writer-produced metadata.</param>
    internal static void Validate(RecallJournalMetadata m)
    {
        if (m.Version != 2 || NormalizeId(m.RecallId) != m.RecallId || m.RecallName != null && (string.IsNullOrWhiteSpace(m.RecallName) || m.RecallName.Length > 256) || m.State is not ("Recording" or "Completed" or "Failed" or "Interrupted") || m.ReceivedBytes < m.StoredBytes || m.StoredBytes < 0 || m.DurableBytes < 0 || m.DurableBytes > m.StoredBytes || m.EventCount < 0 || m.EventCount > m.StoredBytes || m.GapCount < 0 || m.GapCount > m.EventCount + 1 || m.JournalLength != checked(RecallJournalReader.PreambleLength + m.StoredBytes + m.EventCount * (RecallJournalReader.HeaderLength + RecallJournalReader.HashLength))) throw new InvalidDataException("RecallManifestInvalid");
        _ = new RecallCapture(m.RecallId, [], m.ReceivedBytes, m.SourceComplete, m.Settings, m.ParentCaptureId, m.Transformation, m.SourceStatus, m.RecallName);
    }

    /// <summary>Rejects redirected capture files or child directories before opening them.</summary>
    /// <param name="path">Expected plain filesystem entry.</param>
    internal static void AssertPlainFile(string path)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("RecallStorageLinkRejected");
    }
    /// <summary>Tests actual lock ownership without creating or deleting a lock file.</summary>
    /// <param name="directory">Existing capture directory.</param>
    private static bool IsRecording(string directory)
    {
        try { using var file = new FileStream(Path.Combine(directory, "writer.lock"), FileMode.Open, FileAccess.Read, FileShare.None); return false; }
        catch (FileNotFoundException) { return false; }
        catch (IOException) { return true; }
    }
}
