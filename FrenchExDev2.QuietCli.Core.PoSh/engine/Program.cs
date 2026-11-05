using System.Text.Json;
using FrenchExDev2.QuietCli;

/// <summary>Private protocol server for the isolated .NET engine.</summary>
internal static class Program
{
    /// <summary>Runs until EOF, then cancels owned processes and flushes measurements.</summary>
    /// <param name="arguments">Exact arguments without shell expansion.</param>
    private static async Task<int> Main(string[] arguments)
    {
        if (arguments.Length != 4 || arguments[0] != "--database" || arguments[2] != "--module-root" || !Path.IsPathFullyQualified(arguments[3])) return 2;
        await using var session = await EngineSession.CreateAsync(arguments[1], Path.GetFullPath(arguments[3]));
        var protocol = new Protocol(Console.OpenStandardInput(), Console.OpenStandardOutput());
        try
        {
            Packet? packet;
            while ((packet = await protocol.ReadAsync(CancellationToken.None)) != null)
            {
                var request = packet.Header;
                string id = request.GetProperty("RequestId").GetString()!;
                try
                {
                    var reply = await session.ExecuteAsync(request, packet.Payload);
                    await protocol.WriteAsync(new { Version = 1, RequestId = id, Ok = true, Data = reply.Data }, reply.Payload, CancellationToken.None);
                    if (request.GetProperty("Action").GetString() == "shutdown") return 0;
                }
                catch (Exception error)
                {
                    if (error is OperationCanceledException or TimeoutException) throw;
                    await protocol.WriteAsync(new { Version = 1, RequestId = id, Ok = false, Error = new { Code = error.GetType().Name, Message = error.Message } }, null, CancellationToken.None);
                }
            }
        }
        catch (Exception error) { await Console.Error.WriteLineAsync("QuietCli2 protocol stopped: " + error.GetType().Name); return 3; }
        return 0;
    }
}