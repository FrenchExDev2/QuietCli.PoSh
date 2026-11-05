using System.Buffers.Binary;
using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>A bounded protocol frame. Business objects never enter this protocol.</summary>
/// <param name="Header">Control metadata.</param>
/// <param name="Payload">A transient native byte block, not retained after consumption.</param>
internal sealed record Packet(JsonElement Header, byte[] Payload);

/// <summary>Length-prefixed UTF-8 headers and binary payloads on private standard pipes.</summary>
/// <param name="input">input for this native operation.</param>
/// <param name="output">output for this native operation.</param>
internal sealed class Protocol(Stream input, Stream output)
{
    /// <summary>Native writer contract used by the isolated runtime.</summary>
    private readonly SemaphoreSlim writer = new(1);
    /// <summary>Native block size contract used by the isolated runtime.</summary>
    internal static int BlockSize => ProtocolSpecification.BlockSize;
    /// <summary>Native header limit contract used by the isolated runtime.</summary>
    internal static int HeaderLimit => ProtocolSpecification.HeaderLimit;

    /// <summary>Reads a single validated frame, or null at a clean end of connection.</summary>
    /// <param name="token">Cancellation requested by the owning operation.</param>
    internal async Task<Packet?> ReadAsync(CancellationToken token)
    {
        byte[] lengths = new byte[8];
        int first = await input.ReadAsync(lengths.AsMemory(0, 1), token);
        if (first == 0) return null;
        using var frame = CancellationTokenSource.CreateLinkedTokenSource(token);
        frame.CancelAfter(TimeSpan.FromSeconds(ProtocolSpecification.ReadFrameTimeoutSeconds));
        await input.ReadExactlyAsync(lengths.AsMemory(1), frame.Token).AsTask().WaitAsync(frame.Token);
        int headerSize = BinaryPrimitives.ReadInt32LittleEndian(lengths);
        int payloadSize = BinaryPrimitives.ReadInt32LittleEndian(lengths.AsSpan(4));
        if (headerSize < 2 || headerSize > HeaderLimit || payloadSize < 0 || payloadSize > BlockSize)
            throw new InvalidDataException("InvalidFrameLength");
        byte[] header = new byte[headerSize], payload = new byte[payloadSize];
        await input.ReadExactlyAsync(header, frame.Token).AsTask().WaitAsync(frame.Token);
        await input.ReadExactlyAsync(payload, frame.Token).AsTask().WaitAsync(frame.Token);
        using var document = JsonDocument.Parse(header);
        if (document.RootElement.GetProperty("Version").GetInt32() != ProtocolSpecification.Version)
            throw new InvalidDataException("ProtocolVersionMismatch");
        return new(document.RootElement.Clone(), payload);
    }

    /// <summary>Writes one complete frame atomically relative to other responses.</summary>
    /// <param name="metadata">Control or counter metadata, never business data.</param>
/// <param name="payload">Transient binary block released after consumption.</param>
/// <param name="token">Cancellation requested by the owning operation.</param>
    internal async Task WriteAsync(object metadata, byte[]? payload, CancellationToken token)
    {
        using var response = CancellationTokenSource.CreateLinkedTokenSource(token);
        response.CancelAfter(TimeSpan.FromSeconds(ProtocolSpecification.WriteFrameTimeoutSeconds));
        token = response.Token;
        byte[] header = JsonSerializer.SerializeToUtf8Bytes(metadata);
        payload ??= [];
        if (header.Length > HeaderLimit || payload.Length > BlockSize) throw new InvalidDataException("ResponseTooLarge");
        byte[] lengths = new byte[8];
        BinaryPrimitives.WriteInt32LittleEndian(lengths, header.Length);
        BinaryPrimitives.WriteInt32LittleEndian(lengths.AsSpan(4), payload.Length);
        await writer.WaitAsync(token);
        try
        {
            await output.WriteAsync(lengths, token).AsTask().WaitAsync(token);
            await output.WriteAsync(header, token).AsTask().WaitAsync(token);
            await output.WriteAsync(payload, token).AsTask().WaitAsync(token);
            await output.FlushAsync(token).WaitAsync(token);
        }
        finally { writer.Release(); }
    }
}
