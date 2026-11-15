using System.Collections;
using System.Text;
using FrenchExDev2.QuietCli.Git;

/// <summary>Independent assertions for status classification, finalization, index headers and the hot-path digest.</summary>
internal static class StatusCases
{
    /// <summary>Registers authored vectors and seeded generated properties.</summary>
    /// <param name="test">Existing compiled runner.</param>
    internal static void Run(Action<string, Action> test)
    {
        test("status diagnostics classify authored Git messages in rule order", () =>
        {
            var vectors = new (string Stderr, int Exit, string Code, string? Path)[]
            {
                ("fatal: not a git repository (or any of the parent directories): .git\n", 128, "NotARepository", null),
                ("fatal: not a git repository (or any parent up to mount point /mnt)\nStopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).\n", 128, "NotARepository", "/mnt"),
                ("fatal: detected dubious ownership in repository at 'C:/work/repo'\nTo add an exception for this directory, call:\n", 128, "GitDubiousOwnership", "C:/work/repo"),
                ("fatal: not a git repository: /work/repo/.git/worktrees/missing\n", 128, "GitBrokenGitFile", "/work/repo/.git/worktrees/missing"),
                ("fatal: gitfile does not point to a valid repository: /work/repo/.git\n", 128, "GitBrokenGitFile", "/work/repo/.git"),
                ("fatal: invalid gitfile format: /work/repo/.git\n", 128, "GitBrokenGitFile", null),
                ("fatal: Expected git repo version <= 1, found 99\n", 128, "GitUnsupportedRepositoryFormat", null),
                ("fatal: unknown repository extension found:\n\tfuture\n", 128, "GitUnsupportedRepositoryFormat", null),
                ("fatal: cannot use bare repository '/srv/x.git' (safe.bareRepository is 'explicit')\n", 128, "GitBareRepositoryForbidden", "/srv/x.git"),
                ("error: bad signature 0x00000000\nfatal: index file corrupt\n", 128, "GitCorruptIndex", null),
                ("fatal: ../elsewhere: '../elsewhere' is outside repository at '/work/repo'\n", 128, "GitPathspecOutsideRepository", "../elsewhere"),
                ("fatal: Invalid untracked files mode 'sometimes'\n", 128, "GitInvalidArgument", "sometimes"),
                ("usage: git status [<options>] [--] [<pathspec>...]\n", 129, "GitInvalidArgument", null),
                ("fatal: something entirely new\n", 128, "GitUnclassified", null),
                ("", 128, "GitUnclassified", null),
            };
            foreach (var vector in vectors)
            {
                var result = GitDiagnostics.Classify(vector.Stderr, vector.Exit);
                Require((string)result["Code"]! == vector.Code, "Classified " + vector.Stderr.Split('\n')[0] + " as " + result["Code"]);
                Require(Equals(result["Path"], vector.Path), "Path of " + vector.Code + " was " + result["Path"]);
                Require(((string?)result["Excerpt"] ?? string.Empty).Length <= GitDiagnostics.MaxExcerptCharacters, "Excerpt unbounded");
            }
            var bounded = GitDiagnostics.Classify(new string('x', 10_000), 128);
            Require(((string)bounded["Excerpt"]!).Length <= GitDiagnostics.MaxExcerptCharacters, "Long excerpt unbounded");
        });
        test("status warnings separate unreadable directories from other warnings", () =>
        {
            var warnings = GitDiagnostics.Warnings("warning: could not open directory 'secret/': Permission denied\nhint: ignored\nwarning: something else\n");
            Require(warnings.Count == 2, "Warning count changed");
            Require((string)warnings[0]["Code"]! == "UnreadableDirectory" && (string)warnings[0]["Path"]! == "secret/", "Unreadable directory not classified");
            Require((string)warnings[1]["Code"]! == "GitWarning", "Generic warning not retained");
            Require(GitDiagnostics.MakesAnswerIncomplete("UnreadableDirectory") && !GitDiagnostics.MakesAnswerIncomplete("GitWarning"), "Completeness rule changed");
            Require(GitDiagnostics.Warnings(null).Count == 0 && GitDiagnostics.Warnings("").Count == 0, "Empty stderr produced warnings");
        });
        test("status finalization distinguishes uncomputed divergence gone upstreams and no upstream", () =>
        {
            var quick = Status();
            foreach (string line in new[] { "# branch.head main", "# branch.upstream origin/main", "# branch.ab +? -?" }) GitRecords.Status(Bytes(line), quick);
            GitRecords.FinalizeStatus(quick);
            Require(quick["Ahead"] == null && quick["Behind"] == null && (bool)quick["AheadBehindComputed"]! == false && (bool)quick["UpstreamGone"]! == false, "Uncomputed divergence changed");
            Require((bool)quick["Clean"]! && !quick.ContainsKey("Pending") && !quick.ContainsKey("AheadBehindSeen"), "Finalization left parser state");
            var gone = Status();
            foreach (string line in new[] { "# branch.head main", "# branch.upstream origin/main" }) GitRecords.Status(Bytes(line), gone);
            GitRecords.FinalizeStatus(gone);
            Require((bool)gone["UpstreamGone"]! && gone["AheadBehindComputed"] == null, "Gone upstream not reported");
            var local = Status(); GitRecords.Status(Bytes("# branch.head main"), local); GitRecords.FinalizeStatus(local);
            Require(!(bool)local["UpstreamGone"]! && local["AheadBehindComputed"] == null, "Local branch reported an upstream state");
            var pending = Status(); string id = new('a', 40);
            GitRecords.Status(Bytes($"2 R. N... 100644 100644 100644 {id} {id} R100 new"), pending);
            bool rejected = false; try { GitRecords.FinalizeStatus(pending); } catch (InvalidDataException) { rejected = true; }
            Require(rejected, "Incomplete rename finalized");
            foreach (string line in new[] { "# branch.ab +1 -?", "# branch.ab +? -2", "# branch.ab ? ?" })
            {
                bool malformed = false; try { GitRecords.Status(Bytes(line), Status()); } catch (InvalidDataException) { malformed = true; }
                Require(malformed, "Mixed divergence accepted: " + line);
            }
        });
        test("status submodule fields decode commit tracked and untracked changes", () =>
        {
            var data = Status(); string id = new('a', 40);
            GitRecords.Status(Bytes($"1 .M SC.U 160000 160000 160000 {id} {id} sub"), data);
            GitRecords.Status(Bytes($"1 .M N... 100644 100644 100644 {id} {id} file"), data);
            var entries = (IList)data["Entries"]!;
            var state = (IDictionary)((IDictionary)entries[0]!)["Submodule"]!;
            Require((bool)state["CommitChanged"]! && !(bool)state["TrackedChanges"]! && (bool)state["UntrackedChanges"]!, "Submodule state changed");
            Require(((IDictionary)entries[1]!)["Submodule"] == null, "Ordinary entry reported a submodule");
            Require((long)((IDictionary)data["Counts"]!)["Submodules"]! == 1, "Submodule count changed");
            foreach (string field in new[] { "S...X", "X...", "SC.", "SCMX", "N.M." })
            {
                bool malformed = false; try { GitRecords.Status(Bytes($"1 .M {field} 160000 160000 160000 {id} {id} sub"), Status()); } catch (InvalidDataException) { malformed = true; }
                Require(malformed, "Malformed submodule field accepted: " + field);
            }
        });
        test("status index headers report versions entries and explicit unknown reasons", () =>
        {
            foreach (uint version in new uint[] { 2, 3, 4 })
            {
                var header = Header("DIRC", version, 123_456);
                var parsed = GitRepositoryProfile.ParseIndexHeader(header);
                Require((bool)parsed["Available"]! && (long)parsed["Version"]! == version && (long)parsed["Entries"]! == 123_456, "Index header v" + version + " changed");
            }
            Require((string)GitRepositoryProfile.ParseIndexHeader(Header("DIRC", 2, 1)[..11])["Reason"]! == "Truncated", "Truncated header accepted");
            Require((string)GitRepositoryProfile.ParseIndexHeader(Header("CRID", 2, 1))["Reason"]! == "BadSignature", "Bad signature accepted");
            Require((string)GitRepositoryProfile.ParseIndexHeader(Header("DIRC", 9, 1))["Reason"]! == "UnknownVersion", "Unknown version accepted");
            Require((string)GitRepositoryProfile.ReadIndexHeader(null)["Reason"]! == "NoIndex", "Missing index not reported");
        });
        test("status object counts read pack index fan-outs and loose names without launching Git", () =>
        {
            Require(GitRepositoryProfile.ParsePackIndexCount(PackIndex(2, 4321)) == 4321, "Pack index v2 count changed");
            Require(GitRepositoryProfile.ParsePackIndexCount(PackIndex(1, 77)) == 77, "Pack index v1 count changed");
            Require(GitRepositoryProfile.ParsePackIndexCount(PackIndex(2, 5)[..1031]) is null, "Truncated v2 index accepted");
            Require(GitRepositoryProfile.ParsePackIndexCount(PackIndex(1, 5)[..1023]) is null, "Truncated v1 index accepted");
            var future = PackIndex(2, 5); future[7] = 3;
            Require(GitRepositoryProfile.ParsePackIndexCount(future) is null, "Unknown pack index version accepted");
            string root = Path.Combine(Path.GetTempPath(), "quietcli-objects-" + Guid.NewGuid().ToString("N"));
            try
            {
                Require(!(bool)GitRepositoryProfile.CountObjects(root)["Available"]!, "Missing object directory reported available");
                Directory.CreateDirectory(Path.Combine(root, "pack"));
                Directory.CreateDirectory(Path.Combine(root, "info"));
                File.WriteAllBytes(Path.Combine(root, "pack", "pack-a.idx"), PackIndex(2, 1000));
                File.WriteAllBytes(Path.Combine(root, "pack", "pack-a.pack"), new byte[300]);
                File.WriteAllBytes(Path.Combine(root, "pack", "pack-b.idx"), PackIndex(1, 20));
                File.WriteAllBytes(Path.Combine(root, "pack", "pack-b.pack"), new byte[50]);
                File.WriteAllBytes(Path.Combine(root, "pack", "pack-orphan.idx"), PackIndex(2, 999));
                File.WriteAllText(Path.Combine(root, "info", "alternates"), "# comment\n/srv/shared/objects\n\n../other/objects\n");
                foreach (var (fan, name) in new[] { ("ab", new string('c', 38)), ("ab", new string('d', 38)), ("0f", new string('e', 38)), ("0f", "tmp_obj_123456"), ("0f", new string('E', 38)), ("0f", new string('f', 62)) })
                {
                    Directory.CreateDirectory(Path.Combine(root, fan));
                    File.WriteAllBytes(Path.Combine(root, fan, name), []);
                }
                var counted = GitRepositoryProfile.CountObjects(root);
                Require((bool)counted["Available"]! && !(bool)counted["Approximate"]!, "Exact count reported approximate");
                Require((long)counted["Loose"]! == 3 && (long)counted["Packed"]! == 1020 && (long)counted["Packs"]! == 2 && (long)counted["PackBytes"]! == 350, "SHA-1 object counts changed: " + counted["Loose"] + "/" + counted["Packed"] + "/" + counted["Packs"] + "/" + counted["PackBytes"]);
                Require((long)counted["Alternates"]! == 2, "Alternates miscounted");
                Require((long)GitRepositoryProfile.CountObjects(root, 64)["Loose"]! == 1, "SHA-256 loose names miscounted");
                // Limit 0 stops after fan-out 0f (16 directories scanned, one valid name): 1 * 256 / 16.
                var bounded = GitRepositoryProfile.CountObjects(root, 40, 0);
                Require((bool)bounded["Approximate"]! && (long)bounded["Loose"]! == 16, "Loose extrapolation changed: " + bounded["Loose"]);
                File.WriteAllBytes(Path.Combine(root, "pack", "pack-c.idx"), PackIndex(2, 7)[..100]);
                File.WriteAllBytes(Path.Combine(root, "pack", "pack-c.pack"), new byte[1]);
                var partial = GitRepositoryProfile.CountObjects(root);
                Require((bool)partial["Approximate"]! && (long)partial["Packs"]! == 2, "Truncated pack index not reported approximate");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        });
        test("status profile classes thresholds and archetypes stay ordered", () =>
        {
            Require(GitRepositoryProfile.SizeClass(999, GitRepositoryProfile.CheckoutThresholds) == "Small" && GitRepositoryProfile.SizeClass(1_000, GitRepositoryProfile.CheckoutThresholds) == "Medium", "Checkout boundary changed");
            Require(GitRepositoryProfile.SizeClass(200_000, GitRepositoryProfile.CheckoutThresholds) == "Huge" && GitRepositoryProfile.SizeClass(null, GitRepositoryProfile.CheckoutThresholds) == "Unknown", "Checkout extremes changed");
            Require(GitRepositoryProfile.ChangeClass(0) == "Clean" && GitRepositoryProfile.ChangeClass(20) == "Few" && GitRepositoryProfile.ChangeClass(21) == "Many" && GitRepositoryProfile.ChangeClass(1_001) == "Massive", "Change classes changed");
            Require(GitRepositoryProfile.Archetype("Small", "Small") == "Small" && GitRepositoryProfile.Archetype("Medium", "Large") == "DeepHistory" && GitRepositoryProfile.Archetype("Large", "Medium") == "WideCheckout" && GitRepositoryProfile.Archetype("Huge", "Large") == "Monorepo", "Archetypes changed");
        });
        test("status hot paths keep the dominant split within the budget at its exact boundary", () =>
        {
            // Frontier {a(6), b/z(1)} leaves room for 2 items while a/ has 3 children: a/ must be partially split
            // (largest child kept, two folded) instead of fully expanded to K+1 items.
            var entries = new List<IDictionary>();
            foreach (var (path, count) in new[] { ("a/1/f", 3), ("a/2/f", 2), ("a/3/f", 1), ("b/z", 1) })
                for (int index = 0; index < count; index++) entries.Add(Map("Kind", "Changed", "Status", ".M", "Path", path + index));
            var hot = GitStatusDigest.HotPaths(entries, 3);
            string shape = string.Join('|', hot.Select(h => h["Path"] + ":" + h["Kind"] + ":" + h["Changed"] + ":" + h["Groups"]));
            Require(shape == "a/1/:Directory:3:1|a/:Rest:3:2|b/z0:File:1:1", "Boundary split changed: " + shape);
            Require(GitStatusDigest.HotPaths(entries, 4).Count == 4, "Exact-fit expansion refused");
        });
        test("status hot paths cover every change with at most K disjoint deterministic items (seed 41017)", () =>
        {
            var random = new Random(41017);
            string[] names = ["apps", "libs", "tools", "docs", "vendor", "infra"];
            for (int round = 0; round < 200; round++)
            {
                var entries = new List<IDictionary>();
                int count = random.Next(1, 3_000), fanOut = random.Next(1, 7), width = random.Next(1, 6);
                for (int index = 0; index < count; index++)
                {
                    // Root-level files stay rare so the frontier is refined below the root.
                    int depth = random.Next(50) == 0 ? 0 : random.Next(1, 5);
                    var segments = new List<string>();
                    if (depth > 0) segments.Add(names[random.Next(fanOut)]);
                    for (int level = 1; level < depth; level++) segments.Add("d" + random.Next(0, width));
                    segments.Add("f" + index + ".txt");
                    string kind = random.Next(10) switch { 0 => "Conflicted", < 5 => "Untracked", _ => "Changed" };
                    entries.Add(Map("Kind", kind, "Status", kind == "Untracked" ? "??" : ".M", "Path", string.Join('/', segments)));
                }
                int limit = random.Next(1, 15);
                var hot = GitStatusDigest.HotPaths(entries, limit);
                Require(hot.Count >= 1 && hot.Count <= limit, "Hot path count " + hot.Count + " exceeds " + limit);
                Require(hot.Sum(h => (long)h["Changed"]!) == count, "Hot paths do not cover every change");
                var plain = hot.Where(h => (string)h["Kind"]! != "Rest").Select(h => (string)h["Path"]!).ToList();
                foreach (string a in plain)
                    foreach (string b in plain)
                        Require(a == b || !(a.EndsWith('/') && b.StartsWith(a, StringComparison.Ordinal)) && !(a == "./" && b != "./"), "Overlapping hot paths " + a + " " + b);
                Require(plain.Distinct(StringComparer.Ordinal).Count() == plain.Count, "Duplicate hot path");
                for (int index = 1; index < hot.Count; index++) Require((long)hot[index - 1]["Changed"]! >= (long)hot[index]["Changed"]!, "Hot paths not ordered");
                var shuffled = entries.OrderBy(_ => random.Next()).ToList();
                var again = GitStatusDigest.HotPaths(shuffled, limit);
                Require(string.Join('|', again.Select(h => h["Path"] + ":" + h["Changed"])) == string.Join('|', hot.Select(h => h["Path"] + ":" + h["Changed"])), "Hot paths depend on input order");
            }
        });
        test("status digest modes list few changes and cap conflicts in hot-path mode", () =>
        {
            Require((string)GitStatusDigest.Build(new List<object>())["Mode"]! == "Clean", "Empty digest not clean");
            var ignored = new List<object> { Map("Kind", "Ignored", "Status", "!!", "Path", "build/") };
            Require((string)GitStatusDigest.Build(ignored)["Mode"]! == "Clean", "Ignored entries counted as changes");
            var few = new List<object> { Map("Kind", "Untracked", "Status", "??", "Path", "b"), Map("Kind", "Conflicted", "Status", "UU", "Path", "z"), Map("Kind", "Changed", "Status", "M.", "Path", "a") };
            var list = GitStatusDigest.Build(few);
            var listed = ((IList)list["Listed"]!).Cast<IDictionary>().Select(e => (string)e["Path"]!).ToArray();
            Require((string)list["Mode"]! == "List" && string.Join(',', listed) == "z,a,b" && (long)list["Omitted"]! == 0, "List mode order changed");
            var many = new List<object>();
            for (int index = 0; index < 100; index++) many.Add(Map("Kind", "Conflicted", "Status", "UU", "Path", "c/" + index.ToString("D3", System.Globalization.CultureInfo.InvariantCulture)));
            var hot = GitStatusDigest.Build(many, listLimit: 20, hotPaths: 10, conflictCap: 50);
            Require((string)hot["Mode"]! == "HotPaths" && ((IList)hot["Listed"]!).Count == 50 && (long)hot["Omitted"]! == 50, "Conflict cap changed");
            Require(((IList)hot["HotPaths"]!).Count <= 10, "Hot path limit ignored");
        });
    }

    /// <summary>Creates parser-owned mutable status state.</summary>
    private static Hashtable Status() => Map("Pending", null, "Entries", new List<object>(), "Counts", Map("Changed", 0L, "Staged", 0L, "Unstaged", 0L, "Untracked", 0L, "Conflicted", 0L, "Renamed", 0L, "Ignored", 0L, "Submodules", 0L));
    /// <summary>Builds an authored 12-byte index header.</summary>
    /// <param name="signature">Four ASCII signature bytes.</param>
    /// <param name="version">Big-endian version.</param>
    /// <param name="entries">Big-endian entry count.</param>
    private static byte[] Header(string signature, uint version, uint entries)
    {
        var header = new byte[12];
        Encoding.ASCII.GetBytes(signature).CopyTo(header, 0);
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(4), version);
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(8), entries);
        return header;
    }
    /// <summary>Builds a pack index prefix (version 1 or 2) whose cumulative fan-out ends at the given count.</summary>
    private static byte[] PackIndex(uint version, uint count)
    {
        int offset = version == 2 ? 8 : 0;
        var index = new byte[offset + 256 * 4 + 20];
        if (version == 2)
        {
            new byte[] { 0xFF, (byte)'t', (byte)'O', (byte)'c' }.CopyTo(index, 0);
            System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(index.AsSpan(4), 2);
        }
        for (int fan = 0; fan < 256; fan++)
            System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(index.AsSpan(offset + fan * 4), (uint)((long)count * (fan + 1) / 256));
        return index;
    }
    /// <summary>Creates fixture maps independently of production helpers.</summary>
    /// <param name="pairs">Alternating keys and values.</param>
    private static Hashtable Map(params object?[] pairs) { var result = new Hashtable(StringComparer.Ordinal); for (int index = 0; index < pairs.Length; index += 2) result.Add((string)pairs[index]!, pairs[index + 1]); return result; }
    /// <summary>Encodes an authored UTF-8 record.</summary>
    /// <param name="text">Authored record.</param>
    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);
    /// <summary>Asserts a business invariant.</summary>
    /// <param name="condition">Expected condition.</param>
    /// <param name="message">Bounded failure diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
