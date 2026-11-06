using System.Buffers.Binary;
using System.Text;
using FrenchExDev2.QuietCli;

/// <summary>Independent wire-level assertions for the caller-side protocol client.</summary>
internal static class ProtocolClientCases
{
    /// <summary>Fixed seed retained so a failing generated frame can be replayed.</summary>
    private const int Seed = 20261107;

    /// <summary>Runs the framing cases on in-memory streams, without any operating-system process.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run)
    {
        await run("protocol client frames requests that the server reader decodes byte for byte", async () =>
        {
            var random = new Random(Seed);
            for (int iteration = 0; iteration < 300; iteration++)
            {
                byte[] payload = new byte[random.Next(0, 16385)]; random.NextBytes(payload);
                byte[] header = Encoding.UTF8.GetBytes("{\"Version\":1,\"Action\":\"input\",\"Pad\":\"" + new string('x', random.Next(0, 5000)) + "\"}");
                var sent = new MemoryStream();
                var reply = await Client(sent, ReplyFrame([], []), random, header, payload);
                Require(reply.InputBytes == sent.Length && reply.InputBytes == 8 + header.Length + payload.Length, $"Input counter differs from the wire: seed={Seed} iteration={iteration}");
                sent.Position = 0;
                var packet = await new Protocol(sent, Stream.Null).ReadAsync(CancellationToken.None);
                Require(packet != null && packet.Payload.SequenceEqual(payload) && packet.Header.GetProperty("Action").GetString() == "input", $"Server decoded a different request: seed={Seed} iteration={iteration}");
            }
        });
        await run("protocol client returns replies unchanged under arbitrary read fragmentation", async () =>
        {
            var random = new Random(Seed + 1);
            for (int iteration = 0; iteration < 300; iteration++)
            {
                byte[] payload = new byte[random.Next(0, 16385)]; random.NextBytes(payload);
                byte[] header = Encoding.UTF8.GetBytes("{\"Version\":1,\"Ok\":true,\"Note\":\"" + new string('é', random.Next(0, 800)) + "\"}");
                byte[] frame = ReplyFrame(header, payload);
                var reply = await Client(new MemoryStream(), frame, random, Encoding.UTF8.GetBytes("{\"Version\":1}"), []);
                Require(reply.Header.SequenceEqual(header) && reply.Payload.SequenceEqual(payload) && reply.OutputBytes == frame.Length, $"Reply changed: seed={Seed + 1} iteration={iteration}");
            }
        });
        await run("protocol client rejects oversized requests before writing anything", async () =>
        {
            var sent = new MemoryStream();
            await Rejected("InputBlockTooLarge", () => Client(sent, ReplyFrame([], []), new Random(1), "{\"Version\":1}"u8.ToArray(), new byte[16385]));
            await Rejected("ControlFrameTooLarge", () => Client(sent, ReplyFrame([], []), new Random(1), new byte[1048577], []));
            Require(sent.Length == 0, "Rejected request still wrote bytes");
        });
        await run("protocol client rejects every invalid reply length before allocating", async () =>
        {
            foreach (var (header, payload) in new[] { (0, 0), (1, 0), (-1, 0), (2, -1), (1048577, 0), (2, 16385), (int.MaxValue, 0), (int.MinValue, 5) })
            {
                byte[] lengths = new byte[8];
                BinaryPrimitives.WriteInt32LittleEndian(lengths, header); BinaryPrimitives.WriteInt32LittleEndian(lengths.AsSpan(4), payload);
                await Rejected("InvalidFrameLength", () => Client(new MemoryStream(), lengths, new Random(1), "{\"Version\":1}"u8.ToArray(), []));
            }
        });
        await run("protocol client fails on a truncated reply and honors cancellation", async () =>
        {
            byte[] full = ReplyFrame("{\"Version\":1}"u8.ToArray(), new byte[100]);
            for (int cut = 0; cut < full.Length; cut += 7)
            {
                bool failed = false;
                try { await Client(new MemoryStream(), full[..cut], new Random(1), "{\"Version\":1}"u8.ToArray(), []); }
                catch (EndOfStreamException) { failed = true; }
                Require(failed, $"Truncated reply of {cut} bytes was accepted");
            }
            using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
            bool cancellation = false;
            try { await ProtocolClient.ExchangeAsync(new MemoryStream(), new MemoryStream(full), "{\"Version\":1}"u8.ToArray(), [], cancelled.Token); }
            catch (OperationCanceledException) { cancellation = true; }
            Require(cancellation, "Cancelled exchange completed");
        });
    }

    /// <summary>Builds a reply frame with independent little-endian length prefixes.</summary>
    private static byte[] ReplyFrame(byte[] header, byte[] payload)
    {
        if (header.Length == 0) header = "{\"Version\":1}"u8.ToArray();
        byte[] frame = new byte[8 + header.Length + payload.Length];
        BinaryPrimitives.WriteInt32LittleEndian(frame, header.Length); BinaryPrimitives.WriteInt32LittleEndian(frame.AsSpan(4), payload.Length);
        header.CopyTo(frame, 8); payload.CopyTo(frame, 8 + header.Length);
        return frame;
    }

    /// <summary>Runs one exchange against a reply source that returns random short reads.</summary>
    private static Task<ProtocolClientReply> Client(Stream sent, byte[] reply, Random random, byte[] header, byte[] payload)
        => ProtocolClient.ExchangeAsync(sent, new FragmentedStream(reply, random), header, payload, CancellationToken.None);

    private static async Task Rejected(string message, Func<Task> action)
    {
        try { await action(); }
        catch (InvalidDataException error) when (error.Message == message) { return; }
        throw new Exception("Expected " + message);
    }

    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }

    /// <summary>Read-only stream returning at most a few bytes per read.</summary>
    private sealed class FragmentedStream(byte[] data, Random random) : Stream
    {
        private int position;
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => data.Length;
        public override long Position { get => position; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) => Read(buffer.AsSpan(offset, count));
        public override int Read(Span<byte> buffer)
        {
            int count = Math.Min(Math.Min(buffer.Length, data.Length - position), random.Next(1, 40));
            data.AsSpan(position, count).CopyTo(buffer); position += count; return count;
        }
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default) => token.IsCancellationRequested ? ValueTask.FromCanceled<int>(token) : new(Read(buffer.Span));
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
