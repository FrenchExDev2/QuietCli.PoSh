using System.Collections;
using System.Text;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent path, attribution-group and reflog properties.</summary>
internal static class AttributionCases
{
    /// <summary>Registers authored/generated format checks and malformed input campaigns.</summary>
    /// <param name="test">Existing compiled runner.</param>
    internal static void Run(Action<string, Action> test)
    {
        test("attribution quoted byte paths round-trip without Unicode loss (seed 74051)", () =>
        {
            var random = new Random(74051);
            for (int i = 0; i < 1000; i++)
            {
                byte[] original = new byte[random.Next(1, 65)]; random.NextBytes(original);
                for (int j = 0; j < original.Length; j++) if (original[j] == 0) original[j] = 1;
                object decoded = GitQuotedPath.Decode(Quote(original));
                byte[] actual = decoded is string text ? Encoding.UTF8.GetBytes(text) : Convert.FromBase64String((string)((IDictionary)decoded)["Base64"]!);
                Require(actual.SequenceEqual(original), $"Quoted path changed at seed 74051 index {i}");
            }
            Require((string)GitQuotedPath.Decode(Bytes("\"a\\t\\n\\r\\\\\\\"\"")) == "a\t\n\r\\\"", "Named path escapes changed");
        });
        test("attribution generated line groups preserve metadata path content and line numbers (seed 74052)", () =>
        {
            var random = new Random(74052);
            for (int iteration = 0; iteration < 250; iteration++)
            {
                var data = State("Lines"); string id = new('a', iteration % 2 == 0 ? 40 : 64); int count = random.Next(1, 5);
                for (int line = 1; line <= count; line++)
                {
                    GitBlameRecords.Receive(Bytes($"{id} {line + 10} {line + 20}" + (line == 1 ? $" {count}" : "")), data);
                    GitBlameRecords.Receive(Bytes("author é author"), data);
                    GitBlameRecords.Receive(Bytes("author-time -200"), data);
                    GitBlameRecords.Receive(Bytes("boundary"), data);
                    GitBlameRecords.Receive(Bytes("extension value"), data);
                    GitBlameRecords.Receive(Bytes("filename ").Concat(Quote(Bytes("é\tpath\n"))).ToArray(), data);
                    GitBlameRecords.Receive(Bytes($"\tcontent {line}\r"), data);
                }
                GitBlameRecords.Finish(data);
                var rows = (IList)data["Lines"]!;
                Require(rows.Count == count && !data.Contains("Pending"), "Group count or finalization changed");
                for (int i = 0; i < count; i++)
                {
                    var row = (IDictionary)rows[i]!; var metadata = (IDictionary)row["Metadata"]!;
                    Require((long)row["OriginalLine"]! == i + 11 && (long)row["FinalLine"]! == i + 21 && (string)row["Path"]! == "é\tpath\n" && (string)row["Content"]! == $"content {i + 1}\r" && (string)metadata["author"]! == "é author" && (bool)metadata["boundary"]! && (string)metadata["extension"]! == "value", "Attribution field changed");
                }
            }
        });
        test("attribution raw content uncommitted IDs and incomplete entries remain explicit", () =>
        {
            var data = State("Lines"); string id = new('0', 40);
            GitBlameRecords.Receive(Bytes(id + " 1 1 1"), data);
            GitBlameRecords.Receive(Bytes("filename f"), data);
            GitBlameRecords.Receive([9, 255, 0, 13], data); GitBlameRecords.Finish(data);
            var row = (IDictionary)((IList)data["Lines"]!)[0]!;
            Require((bool)row["Uncommitted"]! && (string)((IDictionary)row["Content"]!)["Base64"]! == Convert.ToBase64String([255, 0, 13]), "Raw content changed");
            var partial = State("Lines"); GitBlameRecords.Receive(Bytes(new string('a', 40) + " 1 1 2"), partial);
            GitBlameRecords.Receive(Bytes("filename f"), partial); GitBlameRecords.Receive(Bytes("\tx"), partial);
            Reject(() => GitBlameRecords.Finish(partial));
            Reject(() => GitBlameRecords.Receive(Bytes(new string('a', 40) + " 4 4"), partial));
            var missing = State("Lines"); GitBlameRecords.Receive(Bytes(id + " 1 1 1"), missing);
            Reject(() => GitBlameRecords.Receive(Bytes("\tx"), missing));
        });
        test("attribution reflog fields preserve complete IDs selectors identities and messages", () =>
        {
            var data = State("Entries"); string id = new('b', 64);
            GitReflogRecords.Append(new object[] { id, "HEAD@{2}", "é name", "mail@example.invalid", "reset: message\ncontinued" }, data);
            var row = (IDictionary)((IList)data["Entries"]!)[0]!;
            Require((string)row["ObjectId"]! == id && (string)row["Selector"]! == "HEAD@{2}" && (string)row["Name"]! == "é name" && (string)row["Message"]! == "reset: message\ncontinued", "Reflog mapping changed");
        });
        test("attribution malformed paths headers and reflog fields fuzz without rows (seed 74053, 20000 inputs)", () =>
        {
            var random = new Random(74053);
            for (int i = 0; i < 20000; i++)
            {
                byte[] bytes = new byte[random.Next(1, 257)]; random.NextBytes(bytes); bytes[0] = (byte)'!';
                var data = State("Lines"); Reject(() => GitBlameRecords.Receive(bytes, data));
                Reject(() => GitQuotedPath.Decode(new byte[] { 34, 92, (byte)'q' }.Concat(bytes).Append((byte)34).ToArray()));
                var reflog = State("Entries"); Reject(() => GitReflogRecords.Append(new object[] { "!", i, "name", "mail", bytes }, reflog));
                Require(((IList)data["Lines"]!).Count == 0 && ((IList)reflog["Entries"]!).Count == 0, $"Malformed attribution appended a row at seed 74053 index {i}");
            }
            foreach (string value in new[] { "\"\\400\"", "\"\\1\"", "\"unterminated", "\"a\"b\"", "\"\\000\"" }) Reject(() => GitQuotedPath.Decode(Bytes(value)));
        });
    }
    /// <summary>Creates independently authored octal-quoted bytes.</summary>
    /// <param name="bytes">Fixture filename bytes.</param>
    private static byte[] Quote(byte[] bytes) => Bytes("\"" + string.Concat(bytes.Select(b => "\\" + Convert.ToString(b, 8).PadLeft(3, '0'))) + "\"");
    /// <summary>Creates an invocation-owned test list.</summary>
    /// <param name="name">Business list name.</param>
    private static Hashtable State(string name) => new() { [name] = new List<object>() };
    /// <summary>Encodes an authored protocol fixture.</summary>
    /// <param name="value">Exact UTF-8 text.</param>
    private static byte[] Bytes(string value) => Encoding.UTF8.GetBytes(value);
    /// <summary>Requires explicit rejection of malformed protocol input.</summary>
    /// <param name="action">Malformed operation.</param>
    private static void Reject(Action action) { bool rejected = false; try { action(); } catch (InvalidDataException) { rejected = true; } Require(rejected, "Malformed attribution accepted"); }
    /// <summary>Checks a business invariant independently of implementation.</summary>
    /// <param name="condition">Expected property.</param>
    /// <param name="message">Bounded failure detail.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
