using System.Collections;
using System.Text;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent generated invariants for streamed query records.</summary>
internal static class QueryCases
{
    /// <summary>Registers deterministic properties and bounded malformed-record campaigns.</summary>
    /// <param name="test">Existing compiled runner.</param>
    internal static void Run(Action<string, Action> test)
    {
        test("query object identities preserve complete SHA1 SHA256 and parents (seed 73051)", () =>
        {
            var random = new Random(73051);
            foreach (int length in new[] { 40, 64 })
                for (int index = 0; index < 500; index++)
                {
                    string id = new(Enumerable.Range(0, length).Select(_ => "0123456789abcdef"[random.Next(16)]).ToArray());
                    var data = State("Objects"); data["WithParents"] = true;
                    GitObjectRecords.Receive(Bytes(id + " " + new string('b', length)), data);
                    var row = (IDictionary)((IList)data["Objects"]!)[0]!;
                    Require((string)row["ObjectId"]! == id && (string)row["Algorithm"]! == (length == 40 ? "sha1" : "sha256") && ((string[])row["Parents"]!).Single() == new string('b', length), "Object or parent changed");
                }
        });
        test("query refs preserve symbolic peeled and lossless names", () =>
        {
            var data = State("References"); string id = new('a', 64);
            GitReferenceRecords.Receive(Bytes(id + "\trefs/tags/é^{}"), data);
            GitReferenceRecords.Receive(Bytes("ref: refs/heads/main\tHEAD"), data);
            GitReferenceRecords.Receive(Bytes(id + " ").Concat(new byte[] { 255 }).ToArray(), data);
            var rows = (IList)data["References"]!;
            var peeled = (IDictionary)rows[0]!; var symbolic = (IDictionary)rows[1]!;
            Require((bool)peeled["Peeled"]! && (string)peeled["Name"]! == "refs/tags/é^{}" && (string)peeled["ObjectId"]! == id, "Peeled ref changed");
            Require(symbolic["ObjectId"] == null && (string)symbolic["SymbolicTarget"]! == "refs/heads/main" && (string)symbolic["Name"]! == "HEAD", "Symbolic ref changed");
            Require((string)((IDictionary)((IDictionary)rows[2]!)["Name"]!)["Base64"]! == "/w==", "Raw ref changed");
        });
        test("query index generated metadata preserves every conflict stage and path boundary (seed 73052)", () =>
        {
            var random = new Random(73052);
            for (int index = 0; index < 1000; index++)
            {
                int stage = index % 4; string path = $"é {random.Next()}\ttab\nline"; string id = new('a', index % 2 == 0 ? 40 : 64);
                var data = State("Files"); data["WithStage"] = true;
                GitIndexRecords.Receive(Bytes($"100755 {id} {stage}\t{path}"), data);
                var row = (IDictionary)((IList)data["Files"]!)[0]!;
                Require((string)row["Mode"]! == "100755" && (string)row["ObjectId"]! == id && (int)row["Stage"]! == stage && (string)row["Path"]! == path, "Index field boundary changed");
            }
            var raw = State("Files"); GitIndexRecords.Receive([255, 9, 10], raw);
            Require((string)((IDictionary)((IDictionary)((IList)raw["Files"]!)[0]!)["Path"]!)["Base64"]! == "/wkK", "Raw index path changed");
        });
        test("query object counters preserve exact values alternates and reject malformed counters", () =>
        {
            var data = State("Alternates"); data["Counts"] = new Hashtable();
            GitObjectCounts.Receive(Bytes("count: 123"), data); GitObjectCounts.Receive(Bytes("size-pack: 456"), data);
            GitObjectCounts.Receive(Bytes("alternate: /é path:alternate"), data);
            var counts = (IDictionary)data["Counts"]!;
            Require((long)counts["count"]! == 123 && (long)counts["size-pack"]! == 456 && (string)((IList)data["Alternates"]!)[0]! == "/é path:alternate", "Count values changed");
            foreach (string line in new[] { "count: -1", "count: +1", "count: 9223372036854775808", "count: nope", "bad_header: 2" })
            {
                var malformed = State("Alternates"); malformed["Counts"] = new Hashtable();
                Reject(() => GitObjectCounts.Receive(Bytes(line), malformed));
                Require(((IDictionary)malformed["Counts"]!).Count == 0, "Rejected counter modified state");
            }
            Reject(() => GitObjectCounts.Receive(Bytes("count: 123"), data));
            Require(counts.Count == 2 && (long)counts["count"]! == 123, "Rejected counter modified state");
        });
        test("query version identity and explicitly requested build records remain separate", () =>
        {
            var data = State("BuildInformation");
            Reject(() => GitVersionRecords.Receive(Bytes("help"), data));
            GitVersionRecords.Receive(Bytes("git version 2.56.0.windows.1"), data);
            GitVersionRecords.Receive(Bytes("cpu: x86_64"), data);
            Require((string)data["Version"]! == "2.56.0.windows.1" && (string)((IList)data["BuildInformation"]!)[0]! == "cpu: x86_64", "Version fields changed");
        });
        test("query malformed records fuzz without partial business rows (seed 73053, 20000 inputs)", () =>
        {
            var random = new Random(73053);
            for (int index = 0; index < 20000; index++)
            {
                byte[] bytes = new byte[random.Next(1, 257)]; random.NextBytes(bytes); bytes[0] = (byte)'!';
                var objects = State("Objects"); Reject(() => GitObjectRecords.Receive(bytes, objects));
                var refs = State("References"); Reject(() => GitReferenceRecords.Receive(bytes, refs));
                var files = State("Files"); files["WithStage"] = true; Reject(() => GitIndexRecords.Receive(bytes, files));
                var counts = State("Alternates"); counts["Counts"] = new Hashtable(); Reject(() => GitObjectCounts.Receive(bytes, counts));
                Require(((IList)objects["Objects"]!).Count == 0 && ((IList)refs["References"]!).Count == 0 && ((IList)files["Files"]!).Count == 0 && ((IDictionary)counts["Counts"]!).Count == 0, $"Partial row at seed 73053 index {index}");
            }
        });
    }
    /// <summary>Creates independently owned business list state.</summary>
    /// <param name="key">Explicit list name.</param>
    private static Hashtable State(string key) => new() { [key] = new List<object>() };
    /// <summary>Encodes an authored protocol fixture.</summary>
    /// <param name="text">Authored UTF-8 data.</param>
    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);
    /// <summary>Requires explicit protocol rejection.</summary>
    /// <param name="action">Malformed record operation.</param>
    private static void Reject(Action action) { bool rejected = false; try { action(); } catch (InvalidDataException) { rejected = true; } Require(rejected, "Malformed query record accepted"); }
    /// <summary>Checks an independent business property.</summary>
    /// <param name="condition">Expected invariant.</param>
    /// <param name="message">Bounded diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
