using System.Buffers.Binary;
using System.IO.Compression;
using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>Explicit directory export and optional ZIP64 transport, independent of native execution.</summary>
public static class RecallArchive
{
    /// <summary>Exports exact evidence to a new directory or an explicit compressed transport.</summary>
    /// <param name="capture">Memory or lazy disk evidence.</param>
    /// <param name="path">New directory or ZIP path.</param>
    /// <param name="zip">Selects portable ZIP64 transport.</param>
    /// <param name="compression">Exact zlib level, zero for stored entries.</param>
    public static async Task<RecallTransportResult> ExportAsync(RecallCapture capture, string path, bool zip = false, int compression = 6)
    {
        path = Path.GetFullPath(path);
        if (compression is < 0 or > 9) throw new ArgumentOutOfRangeException(nameof(compression));
        if (!zip)
        {
            var saved = await RecallStore.SaveDirectoryAsync(capture, path);
            long length = new FileInfo(Path.Combine(path, "manifest.json")).Length + saved.JournalMetadata!.JournalLength;
            return new(path, length, length, 0);
        }
        if (capture.StoragePath != null && capture.State == "Completed")
        {
            var report = await RecallZipWriter.WriteAsync(capture.StoragePath, path, compression); capture.Transport = report; return report;
        }
        string temporary = Path.Combine(Path.GetTempPath(), "QuietCli2-transport-" + Guid.NewGuid().ToString("N"));
        try { await RecallStore.SaveDirectoryAsync(capture, temporary); var report = await RecallZipWriter.WriteAsync(temporary, path, compression); capture.Transport = report; return report; }
        finally
        {
            // Only fixed files in this uniquely owned directory are removed; never recurse.
            if (Directory.Exists(temporary)) { foreach (string name in new[] { "manifest.json", "events.bin", "writer.lock" }) File.Delete(Path.Combine(temporary, name)); if (!Directory.EnumerateFileSystemEntries(temporary).Any()) Directory.Delete(temporary); }
        }
    }

    /// <summary>Opens a directory lazily or imports two inert ZIP entries into a durable store.</summary>
    /// <param name="path">Capture directory or ZIP path.</param>
    /// <param name="maximumBytes">Optional native-byte ceiling; null allows all disk-backed bytes.</param>
    /// <param name="root">Destination root for imported ZIPs; null selects durable user storage.</param>
    public static async Task<RecallCapture> ImportAsync(string path, long? maximumBytes = null, string? root = null)
    {
        if (maximumBytes is < 1) throw new ArgumentOutOfRangeException(nameof(maximumBytes));
        if (Directory.Exists(path))
        {
            var capture = await RecallStore.OpenDirectoryAsync(path);
            if (maximumBytes != null && capture.RetainedBytes > maximumBytes) throw new InvalidDataException("RecallImportBudget");
            return capture;
        }
        RecallStore.AssertPlainFile(path);
        await using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, true);
        await ValidateDirectoryAsync(file);
        using var archive = new ZipArchive(file, ZipArchiveMode.Read, true);
        if (archive.Entries.Count != 2 || archive.Entries.Select(e => e.FullName).Distinct(StringComparer.Ordinal).Count() != 2 || archive.Entries.Any(e => e.FullName is not ("manifest.json" or "events.bin"))) throw new InvalidDataException("RecallArchiveEntries");
        var manifest = archive.GetEntry("manifest.json")!; var data = archive.GetEntry("events.bin")!;
        if (manifest.Length > RecallStore.ManifestLimit) throw new InvalidDataException("RecallManifestLimit");
        byte[] json = new byte[checked((int)manifest.Length)];
        await using (var input = manifest.Open()) await input.ReadExactlyAsync(json);
        var metadata = JsonSerializer.Deserialize<RecallJournalMetadata>(json, RecallStore.JsonOptions) ?? throw new InvalidDataException("RecallManifestInvalid");
        RecallStore.Validate(metadata);
        if (metadata.State != "Completed" || data.Length != metadata.JournalLength || maximumBytes != null && metadata.StoredBytes > maximumBytes) throw new InvalidDataException("RecallImportBudgetOrState");
        string destination = Path.Combine(Path.GetFullPath(root ?? RecallStore.DefaultRoot), metadata.RecallId);
        if (Directory.Exists(destination) || File.Exists(destination)) throw new IOException("RecallDestinationExists");
        // The capture is built in a hidden sibling and renamed once complete, so a failure never leaves a half-imported identity.
        string staging = destination + "." + Guid.NewGuid().ToString("N")[..8] + ".partial";
        try
        {
            RecallPrivateFiles.CreateDirectory(staging);
            await using (var output = RecallPrivateFiles.CreateNew(Path.Combine(staging, "events.bin"), FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous))
            await using (var input = data.Open())
            {
                byte[] buffer = new byte[65536]; long copied = 0; int count;
                while ((count = await input.ReadAsync(buffer)) != 0) { copied = checked(copied + count); if (copied > metadata.JournalLength) throw new InvalidDataException("RecallEntryLength"); await output.WriteAsync(buffer.AsMemory(0, count)); }
                if (copied != metadata.JournalLength) throw new EndOfStreamException("RecallEntryLength");
                await output.FlushAsync(); output.Flush(true);
            }
            // Verify bounded records before publishing a discoverable manifest.
            using (var reader = new RecallJournalReader(staging, metadata.RecallId, metadata.JournalLength, false))
            {
                while (await reader.ReadNextAsync() != null) { }
                if (reader.StoredBytes != metadata.StoredBytes || reader.EventCount != metadata.EventCount || reader.GapCount + (metadata.ReceivedBytes > reader.ObservedEnd ? 1 : 0) != metadata.GapCount || reader.ObservedEnd > metadata.ReceivedBytes) throw new InvalidDataException("RecallJournalCountersMismatch");
            }
            await RecallStore.WriteManifestAsync(staging, metadata);
            Directory.Move(staging, destination);
        }
        catch
        {
            // Only the fixed files of this uniquely named staging directory are removed; never recurse.
            if (Directory.Exists(staging)) { foreach (string name in new[] { "manifest.json", "events.bin" }) { try { File.Delete(Path.Combine(staging, name)); } catch (IOException) { } } try { Directory.Delete(staging); } catch (IOException) { } }
            throw;
        }
        return await RecallStore.OpenDirectoryAsync(destination);
    }

    /// <summary>Bounds metadata allocation before constructing ZipArchive, including ZIP64 directories.</summary>
    /// <param name="file">Owned seekable transport stream.</param>
    private static async Task ValidateDirectoryAsync(FileStream file)
    {
        int count = (int)Math.Min(file.Length, 65557); byte[] suffix = new byte[count]; file.Position = file.Length - count; await file.ReadExactlyAsync(suffix);
        for (int i = count - 22; i >= 0; i--)
        {
            if (BinaryPrimitives.ReadUInt32LittleEndian(suffix.AsSpan(i)) != 0x06054b50 || i + 22 + BinaryPrimitives.ReadUInt16LittleEndian(suffix.AsSpan(i + 20)) != count) continue;
            if (BinaryPrimitives.ReadUInt32LittleEndian(suffix.AsSpan(i + 4)) != 0) throw new InvalidDataException("RecallArchiveMultiDisk");
            ulong entries = BinaryPrimitives.ReadUInt16LittleEndian(suffix.AsSpan(i + 10));
            ulong size = BinaryPrimitives.ReadUInt32LittleEndian(suffix.AsSpan(i + 12)), offset = BinaryPrimitives.ReadUInt32LittleEndian(suffix.AsSpan(i + 16));
            if (entries == ushort.MaxValue || size == uint.MaxValue || offset == uint.MaxValue)
            {
                if (i < 20 || BinaryPrimitives.ReadUInt32LittleEndian(suffix.AsSpan(i - 20)) != 0x07064b50) throw new InvalidDataException("RecallZip64Locator");
                ulong position = BinaryPrimitives.ReadUInt64LittleEndian(suffix.AsSpan(i - 12));
                if (position > (ulong)Math.Max(0, file.Length - 56)) throw new InvalidDataException("RecallZip64Offset");
                file.Position = (long)position; byte[] record = new byte[56]; await file.ReadExactlyAsync(record);
                if (BinaryPrimitives.ReadUInt32LittleEndian(record) != 0x06064b50 || BinaryPrimitives.ReadUInt64LittleEndian(record.AsSpan(4)) != 44 || BinaryPrimitives.ReadUInt64LittleEndian(record.AsSpan(16)) != 0) throw new InvalidDataException("RecallZip64Header");
                entries = BinaryPrimitives.ReadUInt64LittleEndian(record.AsSpan(32)); size = BinaryPrimitives.ReadUInt64LittleEndian(record.AsSpan(40)); offset = BinaryPrimitives.ReadUInt64LittleEndian(record.AsSpan(48));
                if (BinaryPrimitives.ReadUInt64LittleEndian(record.AsSpan(24)) != entries) throw new InvalidDataException("RecallZip64Entries");
            }
            if (entries != 2 || size > 8192 || offset > (ulong)file.Length || size > (ulong)file.Length - offset) throw new InvalidDataException("RecallArchiveDirectoryBudget");
            file.Position = (long)offset;
            for (int entry = 0; entry < 2; entry++)
            {
                if ((ulong)file.Position + 46 > offset + size) throw new InvalidDataException("RecallArchiveDirectoryLength");
                byte[] header = new byte[46]; await file.ReadExactlyAsync(header);
                int name = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(28)), extra = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(30)), comment = BinaryPrimitives.ReadUInt16LittleEndian(header.AsSpan(32));
                if (BinaryPrimitives.ReadUInt32LittleEndian(header) != 0x02014b50 || name > 128 || extra > 1024 || comment > 1024 || (ulong)file.Position + (ulong)(name + extra + comment) > offset + size) throw new InvalidDataException("RecallArchiveDirectoryEntry");
                file.Position += name + extra + comment;
            }
            if ((ulong)file.Position != offset + size) throw new InvalidDataException("RecallArchiveDirectoryLength");
            file.Position = 0; return;
        }
        throw new InvalidDataException("RecallArchiveDirectoryMissing");
    }
}
