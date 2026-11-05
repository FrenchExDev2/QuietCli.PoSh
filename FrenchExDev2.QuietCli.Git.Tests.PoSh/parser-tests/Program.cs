using System.Collections;
using System.Text;
using System.Text.Json;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent client-only format and binding assertions; never launches Git.</summary>
internal static class Program
{
    /// <summary>Runs authored fixtures and writes only the bounded assertion report.</summary>
    /// <param name="arguments">Optional module argument-schema path.</param>
    private static async Task<int> Main(string[] arguments)
    {
        var results = new List<object>(); int passed = 0, failed = 0;
        void Case(string name, Action assertion)
        {
            try { assertion(); passed++; results.Add(new { Name = name, State = "Passed" }); }
            catch (Exception error) { failed++; results.Add(new { Name = name, State = "Failed", Error = error.Message }); }
        }
        Case("UTF8 business fields preserve invalid bytes explicitly", () => {
            Check((string)GitRecords.Decode(Encoding.UTF8.GetBytes("é漢🙂")) == "é漢🙂", "Unicode changed");
            var raw = (IDictionary)GitRecords.Decode([255, 10]); Check((string)raw["Base64"]! == "/wo=" && (int)raw["Bytes"]! == 2, "Raw bytes changed");
        });
        Case("status branch completeness and divergence remain separate", () => {
            var data = Status();
            foreach (string line in new[] { "# branch.head (detached)", "# branch.oid (initial)", "# branch.ab +12 -3" }) GitRecords.Status(Bytes(line), data);
            Check((bool)data["Detached"]! && (bool)data["Unborn"]! && data["Branch"] == null && data["HeadOid"] == null && (long)data["Ahead"]! == 12 && (long)data["Behind"]! == 3, "Branch state changed");
        });
        Case("status independently counts tracked untracked and ignored entries", () => {
            var data = Status(); string id = new('a', 40);
            GitRecords.Status(Bytes($"1 M. N... 100644 100644 100644 {id} {id} file name"), data);
            GitRecords.Status(Bytes("? é file"), data); GitRecords.Status(Bytes("! ignored"), data);
            var counts = (IDictionary)data["Counts"]!;
            Check((long)counts["Changed"]! == 2 && (long)counts["Staged"]! == 1 && (long)counts["Unstaged"]! == 0 && (long)counts["Untracked"]! == 1 && (long)counts["Ignored"]! == 1, "Status counts changed");
        });
        Case("rename source remains a separate lossless record", () => {
            var data = Status(); string id = new('a', 40);
            GitRecords.Status(Bytes($"2 R. N... 100644 100644 100644 {id} {id} R100 new name"), data);
            Check(data["Pending"] != null, "Rename source not pending"); GitRecords.Status([255], data);
            var row = (IDictionary)((IList)data["Entries"]!)[0]!;
            Check(data["Pending"] == null && (string)row["Path"]! == "new name" && (string)((IDictionary)row["OriginalPath"]!)["Base64"]! == "/w==", "Rename path boundaries changed");
        });
        Case("malformed status input fails explicitly", () => {
            foreach (string line in new[] { "?", "1 M. incomplete", "x unknown", "# branch.ab nonsense" }) {
                bool rejected = false; try { GitRecords.Status(Bytes(line), Status()); } catch (InvalidDataException) { rejected = true; }
                Check(rejected, "Malformed status accepted");
            }
        });
        Case("patch labels hunks and final newline markers stay explicit", () => {
            var data = Patch();
            foreach (string line in new[] { "diff --git a/f b/f", "--- a/f", "+++ b/f", "@@ -1 +1 @@ title", "-old", "+new", "\\ No newline at end of file" }) GitRecords.Patch(Bytes(line), data);
            var file = (IDictionary)((IList)data["Files"]!)[0]!; var hunk = (IDictionary)((IList)file["Hunks"]!)[0]!; var lines = (IList)hunk["Lines"]!;
            Check((string)file["OldLabel"]! == "a/f" && (string)file["NewLabel"]! == "b/f" && (string)((IDictionary)lines[0]!)["Kind"]! == "Deletion" && (string)((IDictionary)lines[1]!)["Kind"]! == "Addition" && (string)((IDictionary)lines[2]!)["Kind"]! == "NoFinalNewline", "Patch structure changed");
        });
        Case("combined and byte-content patch records preserve their representation", () => {
            var data = Patch(); GitRecords.Patch(Bytes("diff --cc f"), data); GitRecords.Patch(Bytes("@@@ -1 -1 +1 @@@"), data); GitRecords.Patch(Bytes("++content"), data); GitRecords.Patch([255], data);
            var file = (IDictionary)((IList)data["Files"]!)[0]!; var hunk = (IDictionary)((IList)file["Hunks"]!)[0]!; var lines = (IList)hunk["Lines"]!;
            Check((bool)file["Combined"]! && (bool)hunk["Combined"]! && (string)((IDictionary)lines[0]!)["Kind"]! == "CombinedContent" && (string)((IDictionary)lines[1]!)["Kind"]! == "ByteContent", "Combined/raw patch changed");
        });
        Case("field grouping strips record separators only before a first field", () => {
            var fields = new List<object>(); var state = Map("Fields", fields, "FieldCount", 2);
            Check(!GitRecords.Field([], state) && !GitRecords.Field(Bytes("\nfirst"), state) && GitRecords.Field(Bytes("\nbody"), state), "Field boundaries changed");
            Check((string)fields[0] == "first" && (string)fields[1] == "\nbody", "Body whitespace changed");
        });
        Case("history preserves SHA256 identities parents and full multiline body", () => {
            var data = Map("Commits", new List<object>()); string id = new('a', 64), parent = new('b', 40);
            GitRecords.Commit(new object[] { id, parent, "é author", "a@example.invalid", "date-a", "committer", "c@example.invalid", "date-c", "subject", "body\nsecond\n" }, data);
            var commit = (IDictionary)((IList)data["Commits"]!)[0]!;
            Check((string)commit["ObjectId"]! == id && ((string[])commit["Parents"]!).Single() == parent && (string)commit["Body"]! == "body\nsecond\n", "History data changed");
        });
        Case("tree names preserve tabs newlines and non-UTF8 bytes", () => {
            var data = Map("Entries", new List<object>()); string id = new('a', 40);
            GitRecords.Tree(Bytes($"100644 blob {id} 12\té\tname\n"), data);
            GitRecords.Tree(Bytes($"040000 tree {id} -\t").Concat(new byte[] { 255 }).ToArray(), data);
            var entries = (IList)data["Entries"]!; var first = (IDictionary)entries[0]!; var second = (IDictionary)entries[1]!;
            Check((string)first["Path"]! == "é\tname\n" && (long)first["Size"]! == 12 && second["Size"] == null && (string)((IDictionary)second["Path"]!)["Base64"]! == "/w==", "Tree path or size changed");
        });
        Case("worktree entry boundaries flags and extension fields remain visible", () => {
            var data = Map("Worktrees", new List<object>(), "Current", null);
            foreach (string line in new[] { "worktree /a path", "HEAD abc", "detached", "locked reason", "extension value", "" }) GitRecords.Worktree(Bytes(line), data);
            var row = (IDictionary)((IList)data["Worktrees"]!)[0]!;
            Check((string)row["Path"]! == "/a path" && (bool)row["Detached"]! && (string)row["Locked"]! == "reason" && (string)row["extension"]! == "value" && data["Current"] == null, "Worktree fields changed");
        });
        Case("reference differences use ordinal names and sorted observed identities", () => {
            var changes = GitRecords.RefChanges([Map("Name", "refs/heads/A", "ObjectId", "1"), Map("Name", "refs/heads/a", "ObjectId", "2")], [Map("Name", "refs/heads/a", "ObjectId", "3"), Map("Name", "refs/heads/b", "ObjectId", "4")]);
            Check(changes.Length == 3 && (string)((IDictionary)changes[0])["Kind"]! == "Removed" && (string)((IDictionary)changes[1])["Kind"]! == "Updated" && (string)((IDictionary)changes[2])["Kind"]! == "Added", "Reference identities changed");
        });
        GitPushCases.Run(Case);
        RepositoryCommandCases.Run(Case);
        QueryCases.Run(Case);
        AttributionCases.Run(Case);
        var schema = Grammar();
        Case("required values empty equals values and literal separators bind independently", () => {
            var bound = GitArguments.Bind("fixture", ["-m", "--all", "--author=", "--", "--flag"], "fixture-version", schema);
            Check(bound.Complete && bound.Options.Length == 2 && bound.Options[0].Value == "--all" && bound.Options[1].HasValue && bound.Options[1].Value == "" && bound.Operands.Single() == "--flag" && bound.Version == "fixture-version", "Value/separator roles changed");
        });
        Case("short clusters optional values and unknown tails preserve forwarding", () => {
            var complete = GitArguments.Bind("fixture", ["-ab", "--maybe", "operand"], null, schema);
            Check(complete.Complete && complete.Options.Length == 3 && !complete.Options[2].HasValue && complete.Operands.Single() == "operand" && complete.EmitArguments.SequenceEqual(new[] { "-a", "-b", "--maybe", "operand" }), "Short/optional binding changed");
            string[] original = ["--unknown", "--", "-a"];
            var unknown = GitArguments.Bind("fixture", original, null, schema);
            Check(!unknown.Complete && unknown.EmitArguments.SequenceEqual(original) && unknown.Tokens.All(item => item.Kind == "Unparsed"), "Unknown arity rewrote native argv");
        });
        Case("module schema drives existing log binding without claiming broader support", () => {
            if (arguments.Length == 0) throw new Exception("Module schema path required");
            using var document = JsonDocument.Parse(File.ReadAllText(arguments[0], Encoding.UTF8));
            var moduleSchema = (IDictionary)Read(document.RootElement)!;
            var bound = GitArguments.Bind("log", ["--author", "--all", "-n", "2", "--", "-path"], "2.56.0", moduleSchema);
            Check(bound.Complete && bound.Options[0].Value == "--all" && bound.Options[1].Value == "2" && bound.Operands.Single() == "-path", "Module-driven arity changed");
        });
        await Console.Out.WriteLineAsync(JsonSerializer.Serialize(new { Passed = passed, Failed = failed, Cases = results }));
        return failed == 0 ? 0 : 1;
    }

    /// <summary>Creates an independently authored small grammar for lexical assertions.</summary>
    private static IDictionary Grammar() => Map("Profiles", Map("Test", Map("None", new[] { "-a", "-b", "--flag" }, "Required", new[] { "-m", "--author" }, "Optional", new[] { "--maybe" })), "Commands", Map("fixture", Map("Profiles", new[] { "Test" }, "ShortGrouping", true, "StopAtOperand", false)));
    /// <summary>Reads JSON fixture data into ordinary BCL containers, outside the production binder.</summary>
    /// <param name="element">Fixture JSON value.</param>
    private static object? Read(JsonElement element) => element.ValueKind switch { JsonValueKind.Object => Object(element), JsonValueKind.Array => element.EnumerateArray().Select(Read).ToArray(), JsonValueKind.String => element.GetString(), JsonValueKind.True => true, JsonValueKind.False => false, JsonValueKind.Number => element.GetInt64(), _ => null };
    /// <summary>Reads fixture map keys without applying production grammar logic.</summary>
    /// <param name="element">Fixture map.</param>
    private static IDictionary Object(JsonElement element) { var result = new Hashtable(StringComparer.Ordinal); foreach (var item in element.EnumerateObject()) result[item.Name] = Read(item.Value); return result; }
    /// <summary>Creates parser-owned mutable status state.</summary>
    private static Hashtable Status() => Map("Pending", null, "Entries", new List<object>(), "Counts", Map("Changed", 0L, "Staged", 0L, "Unstaged", 0L, "Untracked", 0L, "Conflicted", 0L, "Renamed", 0L, "Ignored", 0L));
    /// <summary>Creates parser-owned patch cursors and lists.</summary>
    private static Hashtable Patch() => Map("Files", new List<object>(), "Preamble", new List<object>(), "Commits", new List<object>(), "CurrentFile", null, "CurrentHunk", null, "CurrentCommit", null);
    /// <summary>Creates expected fixture containers independently of production helpers.</summary>
    /// <param name="pairs">Alternating fixture keys and values.</param>
    private static Hashtable Map(params object?[] pairs) { var result = new Hashtable(StringComparer.Ordinal); for (int index = 0; index < pairs.Length; index += 2) result.Add((string)pairs[index]!, pairs[index + 1]); return result; }
    /// <summary>Encodes an authored UTF-8 record.</summary>
    /// <param name="text">Authored field or line.</param>
    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);
    /// <summary>Asserts a business invariant.</summary>
    /// <param name="condition">Expected condition.</param>
    /// <param name="message">Bounded failure diagnostic.</param>
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
}
