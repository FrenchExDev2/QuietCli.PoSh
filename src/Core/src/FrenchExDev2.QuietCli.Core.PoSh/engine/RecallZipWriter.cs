using System.IO.Compression;
using System.Text;

namespace FrenchExDev2.QuietCli;

/// <summary>Two-entry streaming ZIP64 transport with exact zlib levels zero through nine.</summary>
internal static class RecallZipWriter
{
    /// <summary>One fixed ZIP member's finalized directory fields.</summary>
    private sealed record Entry(string Name, long Offset, long RawLength, long CompressedLength, uint Crc, ushort Method);
    private static readonly uint[] CrcTable = BuildCrcTable();

    /// <summary>Packages only fixed manifest and journal names, using bounded memory.</summary>
    /// <param name="directory">Completed working capture directory.</param>
    /// <param name="destination">New transport file.</param>
    /// <param name="compression">Zero for stored members, otherwise exact zlib level one through nine.</param>
    internal static async Task<RecallTransportResult> WriteAsync(string directory, string destination, int compression)
    {
        if (compression is < 0 or > 9) throw new ArgumentOutOfRangeException(nameof(compression));
        if (File.Exists(destination) || Directory.Exists(destination)) throw new IOException("RecallDestinationExists");
        // The final name appears only once the transport is complete; a failure leaves no truncated archive behind.
        string partial = destination + "." + Guid.NewGuid().ToString("N")[..8] + ".partial";
        try
        {
            var report = await WriteCoreAsync(directory, partial, destination, compression);
            File.Move(partial, destination, false);
            return report;
        }
        catch { try { File.Delete(partial); } catch (IOException) { } catch (UnauthorizedAccessException) { } throw; }
    }

    /// <summary>Writes the complete transport to a private file and reports it under its final name.</summary>
    /// <param name="directory">Completed working capture directory.</param>
    /// <param name="partialPath">Private file receiving the bytes.</param>
    /// <param name="destination">Final transport path reported to the caller.</param>
    /// <param name="compression">Zero for stored members, otherwise exact zlib level one through nine.</param>
    private static async Task<RecallTransportResult> WriteCoreAsync(string directory, string partialPath, string destination, int compression)
    {
        await using var output = RecallPrivateFiles.CreateNew(partialPath, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous);
        var entries = new List<Entry>(); long inputBytes = 0;
        foreach (string name in new[] { "manifest.json", "events.bin" })
        {
            string path = Path.Combine(directory, name); RecallStore.AssertPlainFile(path);
            await using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, true);
            long offset = output.Position; ushort method = (ushort)(compression == 0 ? 0 : 8);
            await HeaderAsync(output, writer =>
            {
                writer.Write(0x04034b50u); writer.Write((ushort)45); writer.Write((ushort)0x0808); writer.Write(method);
                writer.Write((ushort)0); writer.Write((ushort)0x2821); writer.Write(0u); writer.Write(uint.MaxValue); writer.Write(uint.MaxValue);
                byte[] filename = Encoding.UTF8.GetBytes(name); writer.Write((ushort)filename.Length); writer.Write((ushort)20); writer.Write(filename);
                writer.Write((ushort)1); writer.Write((ushort)16); writer.Write(0UL); writer.Write(0UL);
            });
            long dataStart = output.Position, raw = 0; uint crc = uint.MaxValue;
            DeflateStream? deflater = compression == 0 ? null : new(output, new ZLibCompressionOptions { CompressionLevel = compression }, true);
            try
            {
                Stream target = deflater ?? (Stream)output; byte[] buffer = new byte[65536]; int count;
                while ((count = await input.ReadAsync(buffer)) != 0)
                {
                    for (int i = 0; i < count; i++) crc = CrcTable[(crc ^ buffer[i]) & 255] ^ (crc >> 8);
                    await target.WriteAsync(buffer.AsMemory(0, count)); raw = checked(raw + count);
                }
            }
            finally { if (deflater != null) await deflater.DisposeAsync(); }
            long compressed = output.Position - dataStart; crc ^= uint.MaxValue;
            await HeaderAsync(output, writer => { writer.Write(0x08074b50u); writer.Write(crc); writer.Write((ulong)compressed); writer.Write((ulong)raw); });
            entries.Add(new(name, offset, raw, compressed, crc, method)); inputBytes = checked(inputBytes + raw);
        }
        long centralStart = output.Position;
        foreach (var entry in entries)
        {
            await HeaderAsync(output, writer =>
            {
                byte[] name = Encoding.UTF8.GetBytes(entry.Name);
                writer.Write(0x02014b50u); writer.Write((ushort)45); writer.Write((ushort)45); writer.Write((ushort)0x0808); writer.Write(entry.Method);
                writer.Write((ushort)0); writer.Write((ushort)0x2821); writer.Write(entry.Crc); writer.Write(uint.MaxValue); writer.Write(uint.MaxValue);
                writer.Write((ushort)name.Length); writer.Write((ushort)28); writer.Write((ushort)0); writer.Write((ushort)0); writer.Write((ushort)0); writer.Write(0u); writer.Write(uint.MaxValue);
                writer.Write(name); writer.Write((ushort)1); writer.Write((ushort)24); writer.Write((ulong)entry.RawLength); writer.Write((ulong)entry.CompressedLength); writer.Write((ulong)entry.Offset);
            });
        }
        long centralLength = output.Position - centralStart, zip64Position = output.Position;
        await HeaderAsync(output, writer =>
        {
            writer.Write(0x06064b50u); writer.Write(44UL); writer.Write((ushort)45); writer.Write((ushort)45); writer.Write(0u); writer.Write(0u);
            writer.Write(2UL); writer.Write(2UL); writer.Write((ulong)centralLength); writer.Write((ulong)centralStart);
            writer.Write(0x07064b50u); writer.Write(0u); writer.Write((ulong)zip64Position); writer.Write(1u);
            writer.Write(0x06054b50u); writer.Write((ushort)0); writer.Write((ushort)0); writer.Write((ushort)2); writer.Write((ushort)2);
            writer.Write(uint.MaxValue); writer.Write(uint.MaxValue); writer.Write((ushort)0);
        });
        await output.FlushAsync();
        return new(destination, inputBytes, output.Length, compression);
    }

    /// <summary>Builds small ZIP metadata in memory; payload streams separately.</summary>
    /// <param name="output">Owned transport stream.</param>
    /// <param name="write">CPU-only binary metadata encoder.</param>
    private static async Task HeaderAsync(Stream output, Action<BinaryWriter> write)
    {
        using var memory = new MemoryStream(); using (var writer = new BinaryWriter(memory, Encoding.UTF8, true)) write(writer);
        await output.WriteAsync(memory.ToArray());
    }
    /// <summary>Builds the standard reflected CRC-32 table for ZIP interoperability.</summary>
    private static uint[] BuildCrcTable()
    {
        var table = new uint[256];
        for (uint i = 0; i < 256; i++) { uint value = i; for (int bit = 0; bit < 8; bit++) value = (value & 1) != 0 ? 0xedb88320u ^ (value >> 1) : value >> 1; table[i] = value; }
        return table;
    }
}
