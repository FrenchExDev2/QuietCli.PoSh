using System.Collections;
using System.Text;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent properties and bounded fuzzing for repository command formats.</summary>
internal static class RepositoryCommandCases
{
    /// <summary>Registers cases in the existing compiled runner.</summary>
    /// <param name="test">Existing assertion runner.</param>
    internal static void Run(Action<string, Action> test)
    {
        test("repository native success and observed conflicts remain independent", () =>
        {
            Require(GitOperationOutcome.Outcome(0, 3) == "Completed", "Native success changed");
            Require(GitOperationOutcome.Outcome(1, 3) == "FailedWithConflicts", "Conflicts hidden");
            Require(GitOperationOutcome.Outcome(128, 0) == "Failed" && GitOperationOutcome.Outcome(128, null) == "Failed", "Failure hidden");
        });
        test("repository config generated values preserve duplicates null empty and raw bytes (seed 72051)", () =>
        {
            var data = State("Entries"); var random = new Random(72051);
            GitConfigRecords.Config(Encoding.UTF8.GetBytes("test.boolean"), data);
            GitConfigRecords.Config(Encoding.UTF8.GetBytes("test.empty\n"), data);
            var items = (IList)data["Entries"]!;
            Require(!((bool)((IDictionary)items[0]!)["HasValue"]!) && ((IDictionary)items[0]!)["Value"] == null, "Valueless key changed");
            Require((bool)((IDictionary)items[1]!)["HasValue"]! && (string)((IDictionary)items[1]!)["Value"]! == "", "Empty value changed");
            for (int i = 0; i < 1000; i++)
            {
                string value = $"é {random.Next()}\nsecond\t=漢\r";
                GitConfigRecords.Config(Encoding.UTF8.GetBytes("test.repeat\n" + value), data);
                var item = (IDictionary)items[i + 2]!;
                Require((string)item["Name"]! == "test.repeat" && (string)item["Value"]! == value, "Repeated or multiline value changed");
            }
            GitConfigRecords.Config([97, 10, 255], data);
            Require((string)((IDictionary)((IDictionary)items[^1]!)["Value"]!)["Base64"]! == "/w==", "Invalid bytes changed");
        });
        test("repository remote generated URLs preserve spaces colons directions and bytes (seed 72052)", () =>
        {
            var random = new Random(72052);
            foreach (string direction in new[] { "fetch", "push" })
                for (int i = 0; i < 500; i++)
                {
                    var data = State("Remotes");
                    string url = $"/é space/{random.Next()}:漢 (push)";
                    GitRemoteRecords.Remote(Encoding.UTF8.GetBytes($"origin\t{url} ({direction})\r"), data);
                    var rows = (IList)data["Remotes"]!;
                    var item = (IDictionary)rows[0]!;
                    Require(rows.Count == 1 && (string)item["Name"]! == "origin" && (string)item["Url"]! == url && (string)item["Direction"]! == direction, "Remote field boundary changed");
                }
            var raw = State("Remotes");
            GitRemoteRecords.Remote(new byte[] { 97, 9, 255 }.Concat(Encoding.ASCII.GetBytes(" (push)")).ToArray(), raw);
            Require((string)((IDictionary)((IDictionary)((IList)raw["Remotes"]!)[0]!)["Url"]!)["Base64"]! == "/w==", "Raw remote URL changed");
        });
        test("repository malformed formats fuzz without partial rows (seed 72053, 20000 inputs)", () =>
        {
            var random = new Random(72053);
            for (int i = 0; i < 20000; i++)
            {
                byte[] bytes = new byte[random.Next(1, 257)]; random.NextBytes(bytes);
                // Excluding the mandatory separator makes every generated remote invalid.
                for (int j = 0; j < bytes.Length; j++) if (bytes[j] == 9) bytes[j] = 32;
                bytes[0] = 97;
                var data = State("Remotes"); bool rejected = false;
                try { GitRemoteRecords.Remote(bytes, data); } catch (InvalidDataException) { rejected = true; }
                Require(rejected && ((IList)data["Remotes"]!).Count == 0, $"Malformed remote: seed 72053 index {i}");
            }
            foreach (byte[] bytes in new byte[][] { [], [10], [10, 97] })
            {
                bool rejected = false;
                try { GitConfigRecords.Config(bytes, State("Entries")); } catch (InvalidDataException) { rejected = true; }
                Require(rejected, "Empty config key accepted");
            }
        });
    }
    /// <summary>Creates an independent invocation-owned list.</summary>
    /// <param name="key">Business list name.</param>
    private static Hashtable State(string key) => new() { [key] = new List<object>() };
    /// <summary>Checks an independently stated business property.</summary>
    /// <param name="condition">Expected property.</param>
    /// <param name="message">Bounded failure detail.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
