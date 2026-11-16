using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

/// <summary>Independent byte producer/consumer for transport assertions; never part of the business package.</summary>
internal static class Program
{
    /// <summary>Exercises documented byte counts, argument identity, cancellation and terminal behavior.</summary>
    /// <param name="args">args for this native operation.</param>
    private static async Task<int> Main(string[] args)
    {
        Stream output = Console.OpenStandardOutput(), error = Console.OpenStandardError();
        switch (args[0])
        {
            case "emit":
                await EmitAsync(output, long.Parse(args[1]), (byte)'x'); return 0;
            case "mixed":
                await Task.WhenAll(EmitAsync(output, long.Parse(args[1]), 0x61), EmitAsync(error, long.Parse(args[2]), 0x62)); return 0;
            case "copy": await Console.OpenStandardInput().CopyToAsync(output); return 0;
            case "hash":
                byte[] digest = await SHA256.HashDataAsync(Console.OpenStandardInput());
                await output.WriteAsync(Encoding.UTF8.GetBytes(Convert.ToHexString(digest))); return 0;
            case "args": await output.WriteAsync(JsonSerializer.SerializeToUtf8Bytes(args.Skip(1).ToArray())); return 0;
            case "unicode":
                foreach (byte value in Encoding.UTF8.GetBytes("é漢🙂\0fin\0")) { await output.WriteAsync(new byte[] { value }); await output.FlushAsync(); await Task.Delay(2); }
                return 0;
            case "invalid": await output.WriteAsync(new byte[] { 0xc3 }); return 0;
            case "fail": await EmitAsync(error, 17, 0x65); return 7;
            case "hang": await Task.Delay(300000); return 0;
            case "terminal":
                await output.WriteAsync(Encoding.UTF8.GetBytes("out\n")); await error.WriteAsync(Encoding.UTF8.GetBytes("err\n")); return 0;
            case "chunks":
                await EmitChunksAsync(output, int.Parse(args[1]), args[2]); return 0;
            default: return 64;
        }
    }

    /// <summary>Writes <paramref name="text"/> as a seeded sequence of arbitrarily small writes, so chunk
    /// boundaries never align with line endings -- used to prove downstream line parsing (e.g. Vagrant's
    /// --machine-readable reader) tolerates fragmentation at any byte boundary.</summary>
    /// <param name="stream">Requested output pipe.</param>
    /// <param name="seed">Explicit seed; reproducible across runs.</param>
    /// <param name="text">Exact text to emit, UTF-8 encoded.</param>
    private static async Task EmitChunksAsync(Stream stream, int seed, string text)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        var random = new Random(seed);
        int offset = 0;
        while (offset < bytes.Length)
        {
            int size = Math.Min(bytes.Length - offset, random.Next(1, 8));
            await stream.WriteAsync(bytes.AsMemory(offset, size));
            await stream.FlushAsync();
            offset += size;
        }
    }

    /// <summary>Produces an independently known byte volume without allocating the whole output.</summary>
    /// <param name="stream">Requested output pipe.</param>
    /// <param name="length">Exact output length.</param>
    /// <param name="value">Repeated byte.</param>
    private static async Task EmitAsync(Stream stream, long length, byte value)
    {
        byte[] buffer = new byte[8192]; Array.Fill(buffer, value);
        while (length > 0) { int count = (int)Math.Min(length, buffer.Length); await stream.WriteAsync(buffer.AsMemory(0, count)); length -= count; }
    }
}
