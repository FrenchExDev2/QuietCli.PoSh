using System.Buffers;
using System.Buffers.Binary;

namespace FrenchExDev2.QuietCli;

/// <summary>
/// Single implementation of the wire layout shared by the engine side (<see cref="Protocol"/>) and the caller side
/// (<see cref="ProtocolClient"/>): two little-endian Int32 lengths, then the UTF-8 header, then the binary payload.
/// </summary>
internal static class FrameCodec
{
    /// <summary>Size in bytes of the two length prefixes.</summary>
    internal const int PrefixSize = 8;

    /// <summary>Writes a complete frame with one write call, so a frame is never interleaved or split across syscalls by this layer.</summary>
    /// <param name="stream">Destination pipe; the caller flushes it.</param>
    /// <param name="header">Encoded control metadata.</param>
    /// <param name="payload">Binary block, possibly empty.</param>
    /// <param name="token">Per-exchange deadline.</param>
    /// <returns>Total bytes written, including the prefixes.</returns>
    internal static async Task<int> WriteAsync(Stream stream, ReadOnlyMemory<byte> header, ReadOnlyMemory<byte> payload, CancellationToken token)
    {
        int total = PrefixSize + header.Length + payload.Length;
        byte[] buffer = ArrayPool<byte>.Shared.Rent(total);
        try
        {
            BinaryPrimitives.WriteInt32LittleEndian(buffer, header.Length);
            BinaryPrimitives.WriteInt32LittleEndian(buffer.AsSpan(4), payload.Length);
            header.CopyTo(buffer.AsMemory(PrefixSize));
            payload.CopyTo(buffer.AsMemory(PrefixSize + header.Length));
            await stream.WriteAsync(buffer.AsMemory(0, total), token).AsTask().WaitAsync(token);
            return total;
        }
        finally { ArrayPool<byte>.Shared.Return(buffer); }
    }

    /// <summary>Decodes and validates the two length prefixes before any allocation depends on them.</summary>
    /// <param name="prefix">Exactly <see cref="PrefixSize"/> bytes.</param>
    /// <exception cref="InvalidDataException"><c>InvalidFrameLength</c> when a length is outside the protocol bounds.</exception>
    internal static (int HeaderSize, int PayloadSize) ParseLengths(ReadOnlySpan<byte> prefix)
    {
        int headerSize = BinaryPrimitives.ReadInt32LittleEndian(prefix);
        int payloadSize = BinaryPrimitives.ReadInt32LittleEndian(prefix[4..]);
        if (headerSize < 2 || headerSize > ProtocolSpecification.HeaderLimit || payloadSize < 0 || payloadSize > ProtocolSpecification.BlockSize)
            throw new InvalidDataException("InvalidFrameLength");
        return (headerSize, payloadSize);
    }

    /// <summary>Reads the header and payload announced by validated lengths.</summary>
    /// <param name="stream">Source pipe positioned after the prefixes.</param>
    /// <param name="headerSize">Validated header length.</param>
    /// <param name="payloadSize">Validated payload length.</param>
    /// <param name="token">Deadline covering the rest of the frame.</param>
    /// <exception cref="EndOfStreamException">The stream ended inside the frame.</exception>
    internal static async Task<(byte[] Header, byte[] Payload)> ReadBodyAsync(Stream stream, int headerSize, int payloadSize, CancellationToken token)
    {
        byte[] header = new byte[headerSize], payload = new byte[payloadSize];
        await stream.ReadExactlyAsync(header, token).AsTask().WaitAsync(token);
        await stream.ReadExactlyAsync(payload, token).AsTask().WaitAsync(token);
        return (header, payload);
    }
}
