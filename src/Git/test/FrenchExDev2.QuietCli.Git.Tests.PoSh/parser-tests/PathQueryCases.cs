using System.Collections;
using System.Text;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent path-check, canonical contact and raw-diff format properties.</summary>
internal static class PathQueryCases
{
    /// <summary>Registers generated business invariants and malformed-record campaigns.</summary>
    /// <param name="test">Existing compiled runner.</param>
    internal static void Run(Action<string, Action> test)
    {
        test("pathquery generated raw diff records preserve modes IDs rename paths and scores (seed 75051)", () =>
        {
            var random = new Random(75051);
            foreach (char status in "MRCDATUXB")
                for (int i = 0; i < 100; i++)
                {
                    var data = Raw(); string id = new('a', i % 2 == 0 ? 40 : 64), newer = new('b', id.Length);
                    bool pair = status is 'R' or 'C'; string code = status + (pair ? "100" : "");
                    string path = $"é {random.Next()}\tpath\n", old = "old " + path;
                    GitRawDiffRecords.Receive(Bytes($":100644 100755 {id} {newer} {code}"), data);
                    if (pair) GitRawDiffRecords.Receive(Bytes(old), data);
                    GitRawDiffRecords.Receive(Bytes(path), data); GitRawDiffRecords.Finish(data);
                    var row = (IDictionary)((IList)data["Files"]!)[0]!;
                    Require((string)row["OldMode"]! == "100644" && (string)row["NewMode"]! == "100755" && (string)row["OldObjectId"]! == id && (string)row["NewObjectId"]! == newer && (string)row["Status"]! == status.ToString() && (string)row["Path"]! == path && (string)row["OldPath"]! == (pair ? old : path), "Raw diff fields changed");
                    Require(pair ? (int)row["Score"]! == 100 : row["Score"] == null, "Raw diff score changed");
                }
        });
        test("pathquery raw diff commit prefixes incomplete paths and invalid scores stay explicit", () =>
        {
            string id = new('a', 40); var data = Raw();
            GitRawDiffRecords.Receive(Bytes(id), data);
            GitRawDiffRecords.Receive(Bytes($":100644 100644 {id} {id} M"), data);
            Reject(() => GitRawDiffRecords.Finish(data));
            GitRawDiffRecords.Receive([255], data); GitRawDiffRecords.Finish(data);
            Require(((IList)data["Commits"]!).Count == 1 && (string)((IDictionary)((IDictionary)((IList)data["Files"]!)[0]!)["Path"]!)["Base64"]! == "/w==", "Commit or raw path changed");
            foreach (string status in new[] { "R101", "R", "Q", "A50", "M-1" }) Reject(() => GitRawDiffRecords.Receive(Bytes($":100644 100755 {id} {id} {status}"), Raw()));
        });
        test("pathquery attributes and ignore rules preserve values empty prefixes and negation (seed 75052)", () =>
        {
            var random = new Random(75052);
            for (int i = 0; i < 500; i++)
            {
                string path = $"é {random.Next()}\tfile\n", value = "value=" + random.Next();
                var attributes = Check("Attribute"); Feed(attributes, path, "custom", value); GitPathCheckRecords.Finish(attributes);
                var row = (IDictionary)((IList)attributes["Entries"]!)[0]!;
                Require((string)row["Path"]! == path && (string)row["Attribute"]! == "custom" && (string)row["Value"]! == value, "Attribute fields changed");
                foreach (string pattern in new[] { "*.log", "!keep.log" })
                {
                    var ignore = Check("Ignore"); Feed(ignore, ".gitignore", "2", pattern, path); GitPathCheckRecords.Finish(ignore);
                    var rule = (IDictionary)((IList)ignore["Entries"]!)[0]!;
                    Require((bool)rule["Ignored"]! == !pattern.StartsWith('!') && (bool)rule["Negated"]! == pattern.StartsWith('!') && (long)rule["Line"]! == 2, "Ignore negation changed");
                }
                var unmatched = Check("Ignore"); Feed(unmatched, "", "", "", path); GitPathCheckRecords.Finish(unmatched);
                var absent = (IDictionary)((IList)unmatched["Entries"]!)[0]!;
                Require(absent["Line"] == null && !(bool)absent["Ignored"]! && (string)absent["Path"]! == path, "Empty first field was dropped");
            }
        });
        test("pathquery canonical contacts preserve names mail and byte representations (seed 75053)", () =>
        {
            var random = new Random(75053);
            for (int i = 0; i < 500; i++)
            {
                string name = "é name " + random.Next(), mail = $"user{random.Next()}@example.invalid";
                var data = List("Contacts"); GitMailmapRecords.Receive(Bytes($"{name} <{mail}>"), data);
                var contact = (IDictionary)((IList)data["Contacts"]!)[0]!;
                Require((string)contact["Name"]! == name && (string)contact["Email"]! == mail, "Canonical identity changed");
            }
            var raw = List("Contacts"); GitMailmapRecords.Receive([255, 32, 60, 97, 62], raw);
            Require((string)((IDictionary)((IDictionary)((IList)raw["Contacts"]!)[0]!)["Name"]!)["Base64"]! == "/w==", "Canonical raw name changed");
        });
        test("pathquery stdin path encoding preserves literal separators and embedded newlines", () =>
        {
            string[] paths = ["-option-looking", "é\nfile", "tab\tpath"];
            byte[] actual = GitPathCheckRecords.EncodePaths(paths);
            byte[] expected = paths.SelectMany(path => Bytes(path).Append((byte)0)).ToArray();
            Require(actual.SequenceEqual(expected), "Logical argv paths changed in stdin framing");
            Reject(() => GitPathCheckRecords.EncodePaths(["bad\0path"]));
            var partial = Check("Attribute"); GitPathCheckRecords.Receive(Bytes("path"), partial); Reject(() => GitPathCheckRecords.Finish(partial));
        });
        test("pathquery malformed headers groups and contacts fuzz without rows (seed 75054, 20000 inputs)", () =>
        {
            var random = new Random(75054);
            for (int i = 0; i < 20000; i++)
            {
                byte[] bytes = new byte[random.Next(1, 129)]; random.NextBytes(bytes); bytes[0] = (byte)'!'; bytes[^1] = (byte)'!';
                var raw = Raw(); Reject(() => GitRawDiffRecords.Receive(bytes, raw));
                var contacts = List("Contacts"); Reject(() => GitMailmapRecords.Receive(bytes, contacts));
                var attributes = Check("Attribute"); GitPathCheckRecords.Receive([], attributes); GitPathCheckRecords.Receive(Bytes("custom"), attributes); Reject(() => GitPathCheckRecords.Receive(bytes, attributes));
                var ignore = Check("Ignore"); GitPathCheckRecords.Receive(Bytes("source"), ignore); GitPathCheckRecords.Receive(Bytes("not-a-line"), ignore); GitPathCheckRecords.Receive(bytes, ignore); Reject(() => GitPathCheckRecords.Receive(Bytes("path"), ignore));
                Require(((IList)raw["Files"]!).Count == 0 && ((IList)contacts["Contacts"]!).Count == 0 && ((IList)attributes["Entries"]!).Count == 0 && ((IList)ignore["Entries"]!).Count == 0, $"Malformed row at seed 75054 index {i}");
            }
        });
    }
    /// <summary>Creates owned raw-diff state.</summary>
    private static Hashtable Raw() { var state = List("Files"); state["Commits"] = new List<object>(); return state; }
    /// <summary>Creates owned path-check state.</summary>
    /// <param name="kind">Attribute or Ignore protocol.</param>
    private static Hashtable Check(string kind) { var state = List("Entries"); state["Kind"] = kind; return state; }
    /// <summary>Creates independent list state.</summary>
    /// <param name="name">Business field name.</param>
    private static Hashtable List(string name) => new() { [name] = new List<object>() };
    /// <summary>Feeds independently authored NUL field contents.</summary>
    /// <param name="data">Owned protocol state.</param>
    /// <param name="fields">Exact fixture fields.</param>
    private static void Feed(IDictionary data, params string[] fields) { foreach (string field in fields) GitPathCheckRecords.Receive(Bytes(field), data); }
    /// <summary>Encodes a fixture field.</summary>
    /// <param name="text">Exact UTF-8 fixture text.</param>
    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);
    /// <summary>Requires explicit malformed-input rejection.</summary>
    /// <param name="action">Malformed operation.</param>
    private static void Reject(Action action) { bool rejected = false; try { action(); } catch (InvalidDataException) { rejected = true; } Require(rejected, "Malformed path query accepted"); }
    /// <summary>Checks an independent expected business value.</summary>
    /// <param name="condition">Expected invariant.</param>
    /// <param name="message">Bounded diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
