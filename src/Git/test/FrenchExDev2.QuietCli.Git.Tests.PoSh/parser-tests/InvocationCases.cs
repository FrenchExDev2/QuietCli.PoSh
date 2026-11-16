using System.Collections;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent global-option binding, version normalization and query projection invariants.</summary>
internal static class InvocationCases
{
    /// <summary>Flags that never take a value, restated here independently of the production tables.</summary>
    private static readonly string[] Flags = ["-p", "-P", "--paginate", "--no-pager", "--bare", "--no-replace-objects", "--no-lazy-fetch", "--no-optional-locks", "--no-advice", "--literal-pathspecs", "--no-literal-pathspecs", "--glob-pathspecs", "--noglob-pathspecs", "--icase-pathspecs"];

    /// <summary>Options whose value is the next argument.</summary>
    private static readonly string[] Valued = ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--super-prefix", "--attr-source", "--shallow-file"];

    /// <summary>Registers generated, boundary and malformed campaigns.</summary>
    /// <param name="test">Existing compiled runner.</param>
    internal static void Run(Action<string, Action> test)
    {
        test("invocation generated global options keep order, values and the verbatim command tail (seed 77001)", () =>
        {
            var random = new Random(77001);
            for (int i = 0; i < 2000; i++)
            {
                var expectedGlobal = new List<string>(); var vector = new List<string>(); var names = new List<string>();
                for (int count = random.Next(0, 6); count > 0; count--)
                {
                    switch (random.Next(0, 4))
                    {
                        case 0: string flag = Flags[random.Next(Flags.Length)]; expectedGlobal.Add(flag); names.Add(flag); break;
                        case 1: string valued = Valued[random.Next(Valued.Length)], argument = $"é {random.Next()}-x"; expectedGlobal.AddRange([valued, argument]); names.Add(valued); break;
                        case 2: string glued = (random.Next(2) == 0 ? "-C" : "-c") + $"v{random.Next()}"; expectedGlobal.Add(glued); names.Add(glued[..2]); break;
                        default: string equal = $"--git-dir=/p {random.Next()}"; expectedGlobal.Add(equal); names.Add("--git-dir="); break;
                    }
                }
                vector.AddRange(expectedGlobal);
                string command = $"cmd{random.Next(1, 99)}"; vector.Add(command);
                var tail = Enumerable.Range(0, random.Next(0, 5)).Select(_ => random.Next(3) == 0 ? "-C" : $"--opt{random.Next()}").ToList(); vector.AddRange(tail);
                var bound = GitInvocationBinder.Bind(vector);
                Require(bound.Error is null && bound.Name == command && bound.Global.SequenceEqual(expectedGlobal) && bound.GlobalNames.SequenceEqual(names) && bound.Arguments.SequenceEqual(tail) && bound.Original.SequenceEqual(vector), $"Binding changed at seed 77001 index {i}");
            }
        });
        test("invocation informational options select the command without consuming following arguments", () =>
        {
            foreach (string info in new[] { "--html-path", "--man-path", "--info-path", "--exec-path", "--list-cmds=main" })
            {
                var bound = GitInvocationBinder.Bind([info, "-x"]);
                Require(bound.Name == "$root" && bound.Arguments.SequenceEqual(new[] { info, "-x" }) && bound.Global.Length == 0, $"Informational option bound wrongly: {info}");
            }
            var path = GitInvocationBinder.Bind(["--exec-path=/x", "status"]);
            Require(path.Name == "status" && path.Global.Single() == "--exec-path=/x" && path.GlobalNames.Single() == "--exec-path=", "Exec path assignment changed");
            foreach (string version in new[] { "--version", "-v" }) Require(GitInvocationBinder.Bind([version, "--build-options"]) is { Name: "version" } v && v.Arguments.SequenceEqual(new[] { "--build-options" }), "Version selector changed");
            foreach (string help in new[] { "--help", "-h" }) Require(GitInvocationBinder.Bind([help, "log"]) is { Name: "help" } h && h.Arguments.SequenceEqual(new[] { "log" }), "Help selector changed");
            Require(GitInvocationBinder.Bind([]).Name == "$root" && GitInvocationBinder.Bind([""]).Name == "$root" && GitInvocationBinder.Bind(["--bare"]).Name == "$root", "Missing command did not select the root");
        });
        test("invocation missing values and unknown globals are unsupported while nothing throws (seed 77002, 20000 inputs)", () =>
        {
            foreach (string valued in Valued)
            {
                var missing = GitInvocationBinder.Bind([valued]);
                Require(missing.Error == "ArgumentsUnsupported" && missing.Reason!.Contains(valued), $"Missing value accepted for {valued}");
            }
            Require(GitInvocationBinder.Bind(["--bogus", "status"]).Error == "ArgumentsUnsupported" && GitInvocationBinder.Bind(["-Z"]).Error == "ArgumentsUnsupported" && GitInvocationBinder.Bind(["-C"]).Error == "ArgumentsUnsupported", "Unknown global accepted");
            Require(GitInvocationBinder.Bind(["-C", "dir", "status"]).Name == "status" && GitInvocationBinder.Bind(["-Cdir", "status"]).Name == "status", "Valued or glued short option rejected");
            var random = new Random(77002); string[] alphabet = ["-", "--", "-C", "-c", "--git-dir", "=", "a", "status", "", "é", "-p", "--version", "--exec-path="];
            for (int i = 0; i < 20000; i++)
            {
                var vector = Enumerable.Range(0, random.Next(0, 7)).Select(_ => alphabet[random.Next(alphabet.Length)] + (random.Next(3) == 0 ? alphabet[random.Next(alphabet.Length)] : "")).ToArray();
                var bound = GitInvocationBinder.Bind(vector);
                Require(bound.Original.SequenceEqual(vector) && (bound.Error is null ? bound.Name.Length > 0 : bound.Error == "ArgumentsUnsupported" && bound.Name.Length == 0), $"Fuzz invariant broken at seed 77002 index {i}");
            }
        });
        test("invocation versions accept only stable 2.x and a Windows suffix (seed 77003)", () =>
        {
            var random = new Random(77003);
            for (int i = 0; i < 1000; i++)
            {
                int minor = random.Next(0, 100), patch = random.Next(0, 100), suffix = random.Next(1, 9);
                Require(GitVersions.Numeric($"2.{minor}.{patch}") == new Version(2, minor, patch) && GitVersions.Numeric($"2.{minor}.{patch}.windows.{suffix}") == new Version(2, minor, patch), "Stable version rejected");
                Require(GitVersions.Numeric($"2.{minor}.{patch}.{suffix}") is null && GitVersions.Numeric($"3.{minor}.{patch}") is null && GitVersions.Numeric($"2.{minor}") is null, "Unsupported version accepted");
            }
            foreach (string bad in new[] { "", " 2.1.2", "2.1.2 ", "2.1.2\n", "v2.1.2", "2.1.2-rc1", "2.1.2.windows", "2.1.2.windows.", "٢.١.٢", "2.1.2.mac.1" })
                Require(GitVersions.Numeric(bad) is null, $"Malformed version accepted: {bad}");
            Require(GitVersions.Numeric(null) is null && GitVersions.Numeric("2.1.2.WINDOWS.3") == new Version(2, 1, 2), "Null or case handling changed");
        });
        test("invocation query projection keeps object identities, references and flags distinct (seed 77004)", () =>
        {
            var random = new Random(77004);
            foreach (string name in new[] { "hash-object", "write-tree", "commit-tree", "mktree", "mktag", "merge-base", "rev-list" })
            {
                string sha1 = Hex(random, 40), sha256 = Hex(random, 64).ToUpperInvariant();
                var data = GitQueryProjection.Project(name, [sha1, "garbage", sha256, sha1 + "0"], 0, "2.50.0");
                var objects = (Hashtable[])data["Objects"]!;
                Require(objects.Length == 2 && (string)objects[0]["Algorithm"]! == "sha1" && (string)objects[1]["Algorithm"]! == "sha256" && (string)objects[1]["ObjectId"]! == sha256, $"Object records changed for {name}");
                Require((string)data["Command"]! == name && (string)data["GitVersion"]! == "2.50.0" && (int)data["ExitCode"]! == 0, "Common fields changed");
            }
            foreach (string name in new[] { "show-ref", "ls-remote" })
            {
                string id = Hex(random, 40);
                var references = (Hashtable[])GitQueryProjection.Project(name, [$"{id}\trefs/heads/é main", "nothing"], 0, null)["References"]!;
                Require(references.Length == 1 && (string)references[0]["Name"]! == "refs/heads/é main" && (string)references[0]["ObjectId"]! == id, $"References changed for {name}");
            }
            var counts = (IDictionary)GitQueryProjection.Project("count-objects", ["count: 12", "size-garbage: 3", "bad line", "In-Pack: 9999999999"], 0, null)["Counts"]!;
            Require(counts.Count == 3 && (long)counts["count"]! == 12 && (long)counts["size-garbage"]! == 3 && (long)counts["In-Pack"]! == 9999999999 && (string)GitQueryProjection.Project("count-objects", [], 0, null)["SizeUnit"]! == "KiB", "Counters changed");
            var valid = GitQueryProjection.Project("check-ref-format", ["refs/heads/x"], 0, null); var invalid = GitQueryProjection.Project("check-ref-format", [], 1, null);
            Require((bool)valid["Valid"]! && (string)valid["NormalizedName"]! == "refs/heads/x" && !(bool)invalid["Valid"]! && invalid["NormalizedName"] == null, "Reference format result changed");
            var present = GitQueryProjection.Project("symbolic-ref", ["refs/heads/main"], 0, null); var absent = GitQueryProjection.Project("symbolic-ref", [], 1, null);
            Require((bool)present["Exists"]! && (string)present["Reference"]! == "refs/heads/main" && !(bool)absent["Exists"]! && absent["Reference"] == null, "Symbolic reference result changed");
            var other = GitQueryProjection.Project("log", ["a", "b"], 0, null);
            Require(((string[])other["Records"]!).SequenceEqual(new[] { "a", "b" }) && !other.Contains("Objects") && other.Contains("Semantics"), "Native records not preserved");
        });
        test("invocation counters beyond 64 bits fail explicitly", () =>
        {
            bool rejected = false; try { GitQueryProjection.Project("count-objects", ["count: 99999999999999999999"], 0, null); } catch (InvalidDataException) { rejected = true; }
            Require(rejected, "Overflowing counter accepted");
        });
    }

    /// <summary>Generates a lowercase hexadecimal identity.</summary>
    /// <param name="random">Seeded source.</param>
    /// <param name="length">Digit count.</param>
    private static string Hex(Random random, int length) => string.Concat(Enumerable.Range(0, length).Select(_ => "0123456789abcdef"[random.Next(16)]));

    /// <summary>Asserts an independently stated observable property.</summary>
    /// <param name="condition">Expected property.</param>
    /// <param name="message">Bounded diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
