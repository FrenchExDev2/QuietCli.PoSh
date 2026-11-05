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
            default: return 64;
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
