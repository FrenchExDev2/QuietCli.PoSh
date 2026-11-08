namespace FrenchExDev2.QuietCli;

/// <summary>One decoded engine reply, with the exact wire sizes needed for protocol counters.</summary>
/// <param name="Header">Reply control metadata as UTF-8 JSON bytes.</param>
/// <param name="Payload">Transient native byte block, possibly empty.</param>
/// <param name="InputBytes">Bytes written to the engine, including the length prefix.</param>
/// <param name="OutputBytes">Bytes read from the engine, including the length prefix.</param>
public sealed record ProtocolClientReply(byte[] Header, byte[] Payload, int InputBytes, int OutputBytes);

/// <summary>Caller-side framing for the isolated engine, the counterpart of <see cref="Protocol"/>.</summary>
public static class ProtocolClient
{
    /// <summary>Writes one length-prefixed request and reads exactly one length-prefixed reply.</summary>
    /// <param name="toEngine">Engine standard input.</param>
    /// <param name="fromEngine">Engine standard output.</param>
    /// <param name="header">Encoded control metadata, never a business object.</param>
    /// <param name="payload">Transient native input block; may be empty.</param>
    /// <param name="token">Per-exchange deadline.</param>
    public static async Task<ProtocolClientReply> ExchangeAsync(Stream toEngine, Stream fromEngine, byte[] header, byte[] payload, CancellationToken token)
    {
        if (payload.Length > ProtocolSpecification.BlockSize) throw new InvalidDataException("InputBlockTooLarge");
        if (header.Length > ProtocolSpecification.HeaderLimit) throw new InvalidDataException("ControlFrameTooLarge");
        int written = await FrameCodec.WriteAsync(toEngine, header, payload, token);
        await toEngine.FlushAsync(token).WaitAsync(token);
        byte[] replyLengths = new byte[FrameCodec.PrefixSize];
        await fromEngine.ReadExactlyAsync(replyLengths, token).AsTask().WaitAsync(token);
        (int headerSize, int payloadSize) = FrameCodec.ParseLengths(replyLengths);
        (byte[] replyHeader, byte[] replyPayload) = await FrameCodec.ReadBodyAsync(fromEngine, headerSize, payloadSize, token);
        return new(replyHeader, replyPayload, written, FrameCodec.PrefixSize + headerSize + payloadSize);
    }
}
