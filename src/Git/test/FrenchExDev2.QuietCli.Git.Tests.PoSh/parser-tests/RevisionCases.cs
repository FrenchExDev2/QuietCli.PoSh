using System.Collections;
using System.Text;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent bounded scalar, description, symbolic-name and summary invariants.</summary>
internal static class RevisionCases
{
    /// <summary>Registers generated values and malformed protocol campaigns.</summary>
    /// <param name="test">Existing compiled runner.</param>
    internal static void Run(Action<string, Action> test)
    {
        test("revision scalar fragments preserve embedded newlines and strict boolean values (seed 76051)", () =>
        {
            var random = new Random(76051);
            for (int i = 0; i < 1000; i++)
            {
                string path = $"/é/{random.Next()}\nname\r\n";
                byte[] output = Bytes(path + "\n"); var scalar = new GitScalarOutput();
                for (int at = 0; at < output.Length;)
                {
                    int size = Math.Min(random.Next(1, 18), output.Length - at);
                    scalar.Append(output[at..(at + size)]); at += size;
                }
                Require((string)scalar.Finish() == path, "Scalar path bytes changed");
                Require(GitScalarOutput.ParseBoolean("true") && !GitScalarOutput.ParseBoolean("false"), "Boolean meaning changed");
            }
            var raw = new GitScalarOutput(); raw.Append([255, 10]);
            Require((string)((IDictionary)raw.Finish())["Base64"]! == "/w==", "Raw scalar changed");
        });
        test("revision scalar byte bounds and terminal state fail explicitly", () =>
        {
            var scalar = new GitScalarOutput(16); scalar.Append(Bytes(new string('x', 16)));
            Reject(() => scalar.Append([1])); Require((string)scalar.Finish() == new string('x', 16), "Bound failure changed retained scalar");
            bool terminal = false; try { scalar.Append([1]); } catch (InvalidOperationException) { terminal = true; }
            Require(terminal, "Completed scalar reused");
            Reject(() => GitScalarOutput.ParseBoolean("TRUE")); Reject(() => GitScalarOutput.ParseBoolean("false\nextra"));
        });
        test("revision generated describe counts and opaque abbreviations remain distinct (seed 76052)", () =>
        {
            var random = new Random(76052);
            for (int i = 0; i < 1000; i++)
            {
                string tag = $"réf-{random.Next()}-gabc", abbreviation = "0123abcde"; long distance = random.Next(0, 1000000);
                var data = State("Descriptions"); GitDescribeRecords.Receive(Bytes($"{tag}-{distance}-g{abbreviation}"), data);
                var row = (IDictionary)((IList)data["Descriptions"]!)[0]!;
                Require((string)row["Tag"]! == tag && (long)row["Distance"]! == distance && (string)row["ObjectAbbreviation"]! == abbreviation && !(bool)row["ObjectOnly"]!, "Long description changed");
            }
            var fallback = State("Descriptions"); GitDescribeRecords.Receive(Bytes("abc1234"), fallback);
            var only = (IDictionary)((IList)fallback["Descriptions"]!)[0]!;
            Require((bool)only["ObjectOnly"]! && only["Tag"] == null && only["Distance"] == null, "Always fallback invented a tag");
        });
        test("revision symbolic labels and summary groups preserve native labels and counts", () =>
        {
            var names = State("Names"); GitRevisionNames.Receive(Bytes("HEAD main~2"), names); GitRevisionNames.Receive(Bytes("missing undefined"), names);
            var first = (IDictionary)((IList)names["Names"]!)[0]!; var second = (IDictionary)((IList)names["Names"]!)[1]!;
            Require((string)first["Input"]! == "HEAD" && (string)first["Name"]! == "main~2" && (bool)second["Undefined"]!, "Symbolic name changed");
            var groups = State("Groups"); GitShortlogRecords.Receive(Bytes("    42\té person <mail@example.invalid>"), groups);
            var group = (IDictionary)((IList)groups["Groups"]!)[0]!;
            Require((long)group["Count"]! == 42 && (string)group["Label"]! == "é person <mail@example.invalid>", "Summary group changed");
        });
        test("revision malformed outputs fuzz without invented fields (seed 76053, 20000 inputs)", () =>
        {
            var random = new Random(76053);
            for (int i = 0; i < 20000; i++)
            {
                byte[] bytes = new byte[random.Next(1, 257)]; random.NextBytes(bytes);
                for (int j = 0; j < bytes.Length; j++) if (bytes[j] == 32) bytes[j] = 33;
                bytes[0] = 33; bytes[^1] = 33;
                var descriptions = State("Descriptions"); Reject(() => GitDescribeRecords.Receive(bytes, descriptions));
                var names = State("Names"); Reject(() => GitRevisionNames.Receive(bytes, names));
                var groups = State("Groups"); Reject(() => GitShortlogRecords.Receive(bytes, groups));
                Reject(() => GitScalarOutput.ParseBoolean("!" + i));
                Require(((IList)descriptions["Descriptions"]!).Count == 0 && ((IList)names["Names"]!).Count == 0 && ((IList)groups["Groups"]!).Count == 0, $"Malformed revision at seed 76053 index {i}");
            }
        });
    }
    /// <summary>Creates an independent result list.</summary>
    /// <param name="name">Business list name.</param>
    private static Hashtable State(string name) => new() { [name] = new List<object>() };
    /// <summary>Encodes authored protocol bytes.</summary>
    /// <param name="text">Exact UTF-8 fixture.</param>
    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);
    /// <summary>Requires a documented malformed-output failure.</summary>
    /// <param name="action">Invalid operation.</param>
    private static void Reject(Action action) { bool rejected = false; try { action(); } catch (InvalidDataException) { rejected = true; } Require(rejected, "Invalid revision output accepted"); }
    /// <summary>Asserts an independently stated observable property.</summary>
    /// <param name="condition">Expected property.</param>
    /// <param name="message">Bounded diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
