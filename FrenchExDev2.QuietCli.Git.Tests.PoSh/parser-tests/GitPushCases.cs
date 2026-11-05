using System.Collections;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent porcelain properties and deterministic malformed-input campaign.</summary>
internal static class GitPushCases
{
    /// <summary>Registers reusable cases in the existing client-only runner.</summary>
    /// <param name="test">Existing assertion runner.</param>
    internal static void Run(Action<string, Action> test)
    {
        test("push authored deletion rejection and remote records", () =>
        {
            var data = State();
            GitPush.Receive("To /local/é remote\r", data);
            GitPush.Receive("-\t:refs/heads/old\t[deleted]\r", data);
            GitPush.Receive("!\trefs/heads/main:refs/heads/main\t[rejected] (non-fast-forward)", data);
            GitPush.Receive("Done", data);
            var rows = (IList)data["References"]!;
            Require((string)data["Remote"]! == "/local/é remote" && rows.Count == 2, "Remote or row count changed");
            var removed = (IDictionary)rows[0]!; var rejected = (IDictionary)rows[1]!;
            Require((string)removed["From"]! == "" && (string)removed["To"]! == "refs/heads/old" && (bool)removed["Accepted"]!, "Deletion changed");
            Require(!(bool)rejected["Accepted"]! && (string)rejected["Summary"]! == "[rejected] (non-fast-forward)", "Rejection changed");
        });
        test("push generated properties preserve every flag and independent state (seed 71051)", () =>
        {
            var random = new Random(71051);
            foreach (char flag in " =*+!-")
                for (int index = 0; index < 200; index++)
                {
                    string from = $"refs/heads/é-{random.Next()}";
                    string to = $"refs/tags/漢-{random.Next()}";
                    string summary = $"summary {random.Next()}\textra: detail";
                    var data = State(); var untouched = State();
                    GitPush.Receive($"{flag}\t{from}:{to}\t{summary}\r", data);
                    var rows = (IList)data["References"]!;
                    Require(rows.Count == 1 && ((IList)untouched["References"]!).Count == 0 && data["Remote"] == null, "State isolation changed");
                    var row = (IDictionary)rows[0]!;
                    Require((string)row["Flag"]! == flag.ToString() && (string)row["From"]! == from && (string)row["To"]! == to && (string)row["Summary"]! == summary && (bool)row["Accepted"]! == (flag != '!'), "Generated push invariant changed");
                }
        });
        test("push bounded malformed-input fuzzing rejects noise (seed 71052, 20000 inputs)", () =>
        {
            var random = new Random(71052);
            string alphabet = "abc XYZ\t:\r\0é漢!*+-=";
            for (int index = 0; index < 20000; index++)
            {
                string noise = new(Enumerable.Range(0, random.Next(0, 257)).Select(_ => alphabet[random.Next(alphabet.Length)]).ToArray());
                var data = State();
                // Every generated record violates one independently chosen framing requirement.
                string input = (index % 3) switch { 0 => "?" + noise, 1 => "! " + noise, _ => "!\t" + noise.Replace(":", "") };
                GitPush.Receive(input, data);
                Require(((IList)data["References"]!).Count == 0 && data["Remote"] == null, $"Noise accepted: seed 71052 index {index}");
            }
            foreach (string remote in new[] { "To local", "to local", "TO local" })
            {
                var data = State(); GitPush.Receive(remote, data);
                Require((string)data["Remote"]! == "local", "Remote prefix compatibility changed");
            }
        });
    }

    /// <summary>Creates independent invocation-owned state.</summary>
    private static Hashtable State() => new() { ["References"] = new List<object>(), ["Remote"] = null };
    /// <summary>Asserts a protocol property independently of production parsing.</summary>
    /// <param name="condition">Expected invariant.</param>
    /// <param name="message">Bounded diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
