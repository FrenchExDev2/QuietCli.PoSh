using System.Collections;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>
/// Builds the adaptive status view: the complete list for few changes, otherwise the K hottest paths.
/// Pure and deterministic; it reads parsed status entries and never touches the file system.
/// </summary>
public static class GitStatusDigest
{
    /// <summary>Default number of hot paths.</summary>
    public const int DefaultHotPaths = 10;
    /// <summary>Default maximum number of conflicted entries listed individually in HotPaths mode.</summary>
    public const int DefaultConflictCap = 50;

    /// <summary>Change counters of one path-trie node.</summary>
    /// <param name="path">Repository-relative path without a trailing slash (empty for the root).</param>
    private sealed class Node(string path)
    {
        /// <summary>Repository-relative path without a trailing slash (empty for the root).</summary>
        public readonly string Path = path;
        /// <summary>True when the node holds children or was reported as a directory entry.</summary>
        public bool Directory;
        /// <summary>Children ordered ordinally by segment.</summary>
        public readonly SortedDictionary<string, Node> Children = new(StringComparer.Ordinal);
        /// <summary>Counters of entries whose path ends exactly at this node.</summary>
        public readonly Counters Self = new();
        /// <summary>Counters of entries at or below this node.</summary>
        public readonly Counters All = new();
    }

    /// <summary>Mutable change counters.</summary>
    private sealed class Counters
    {
        /// <summary>Covered entries.</summary>
        public long Total;
        /// <summary>Entries with an index-side change.</summary>
        public long Staged;
        /// <summary>Entries with a worktree-side change.</summary>
        public long Unstaged;
        /// <summary>Untracked entries.</summary>
        public long Untracked;
        /// <summary>Unmerged entries.</summary>
        public long Conflicted;
    }

    /// <summary>One frontier item: a whole subtree, an exact file, or the remainder of a partially split directory.</summary>
    /// <param name="Node">Trie node the item stands for.</param>
    /// <param name="Kind">Directory, File or Rest.</param>
    /// <param name="Counts">Covered entries.</param>
    /// <param name="Groups">Number of sibling items folded into a Rest item, otherwise 1.</param>
    private sealed record Item(Node Node, string Kind, Counters Counts, int Groups)
    {
        /// <summary>Display path: directories and remainders end with a slash; the root is <c>./</c>.</summary>
        public string Display => Node.Path.Length == 0 ? "./" : Kind == "File" && !Node.Directory ? Node.Path : Node.Path + "/";
    }

    /// <summary>Builds the digest of parsed status data.</summary>
    /// <param name="entries">Status entries (Kind, Status, Path).</param>
    /// <param name="listLimit">Maximum change count still listed in full.</param>
    /// <param name="hotPaths">Number of hot paths in HotPaths mode.</param>
    /// <param name="conflictCap">Maximum conflicted entries listed in HotPaths mode.</param>
    /// <returns>Map with Mode, Changed, HotPaths, Listed, Omitted and the limits used.</returns>
    public static Hashtable Build(IList entries, int listLimit = 20, int hotPaths = DefaultHotPaths, int conflictCap = DefaultConflictCap)
    {
        var changed = entries.Cast<object?>().Select(GitRecords.Dict).Where(e => GitRecords.Unwrap(e["Kind"]) as string != "Ignored").ToList();
        string mode = changed.Count == 0 ? "Clean" : changed.Count <= listLimit ? "List" : "HotPaths";
        var listed = new List<IDictionary>();
        List<Hashtable> hot = [];
        if (mode == "List") listed.AddRange(changed.OrderBy(Group).ThenBy(PathKey, StringComparer.Ordinal));
        else if (mode == "HotPaths")
        {
            listed.AddRange(changed.Where(e => Group(e) == 0).OrderBy(PathKey, StringComparer.Ordinal).Take(conflictCap));
            hot = HotPaths(changed, hotPaths);
        }
        return GitRecords.Map("Mode", mode, "Changed", (long)changed.Count, "HotPaths", hot, "Listed", listed, "Omitted", (long)(changed.Count - listed.Count),
            "ListLimit", listLimit, "HotPathLimit", hotPaths, "ConflictCap", conflictCap);
    }

    /// <summary>
    /// Selects at most <paramref name="limit"/> disjoint paths covering every changed entry. Starting from the
    /// root, the largest splittable item is replaced by its children while the frontier fits; when the dominant
    /// item cannot be split within the limit, its biggest children are kept and the rest is folded into one
    /// remainder item. Single-child chains are compressed, so results point at the deepest common directory.
    /// </summary>
    /// <param name="entries">Changed entries (Ignored excluded by the caller).</param>
    /// <param name="limit">Maximum number of returned items, at least 1.</param>
    public static List<Hashtable> HotPaths(IEnumerable<IDictionary> entries, int limit = DefaultHotPaths)
    {
        if (limit < 1) throw new ArgumentOutOfRangeException(nameof(limit));
        var root = new Node(string.Empty);
        foreach (var entry in entries) Add(root, entry);
        if (root.All.Total == 0) return [];
        var frontier = new List<Item> { Whole(Compress(root)) };
        var blocked = new HashSet<Node>();
        while (true)
        {
            var ordered = Order(frontier).ToList();
            var candidate = ordered.FirstOrDefault(i => i.Kind == "Directory" && i.Node.Children.Count > 0 && !blocked.Contains(i.Node));
            if (candidate is null) break;
            var expansion = Expand(candidate.Node);
            int room = limit - (frontier.Count - 1);
            if (expansion.Count <= room) { frontier.Remove(candidate); frontier.AddRange(expansion); continue; }
            // Only the dominant item is partially split; folding its tail ends the refinement.
            if (room >= 2 && ReferenceEquals(candidate, ordered[0]))
            {
                var kept = Order(expansion).Take(room - 1).ToList();
                var rest = expansion.Except(kept).ToList();
                var folded = new Counters
                {
                    Total = rest.Sum(i => i.Counts.Total), Staged = rest.Sum(i => i.Counts.Staged), Unstaged = rest.Sum(i => i.Counts.Unstaged),
                    Untracked = rest.Sum(i => i.Counts.Untracked), Conflicted = rest.Sum(i => i.Counts.Conflicted),
                };
                frontier.Remove(candidate); frontier.AddRange(kept); frontier.Add(new Item(candidate.Node, "Rest", folded, rest.Count));
                break;
            }
            blocked.Add(candidate.Node);
        }
        return Order(frontier).Select(i => GitRecords.Map("Path", i.Display, "Kind", i.Kind, "Changed", i.Counts.Total, "Staged", i.Counts.Staged, "Unstaged", i.Counts.Unstaged,
                "Untracked", i.Counts.Untracked, "Conflicted", i.Counts.Conflicted, "Groups", (long)i.Groups, "Share", Math.Round(100.0 * i.Counts.Total / root.All.Total, 1)))
            .ToList();
    }

    /// <summary>Deterministic order: largest first, remainders after equal-sized items, then ordinal path.</summary>
    /// <param name="items">Frontier items.</param>
    private static IEnumerable<Item> Order(IEnumerable<Item> items) =>
        items.OrderByDescending(i => i.Counts.Total).ThenBy(i => i.Kind == "Rest" ? 1 : 0).ThenBy(i => i.Display, StringComparer.Ordinal);

    /// <summary>Adds one entry to the path trie, updating counters along its path.</summary>
    /// <param name="root">Trie root.</param>
    /// <param name="entry">Status entry.</param>
    private static void Add(Node root, IDictionary entry)
    {
        string path = PathKey(entry);
        bool directoryEntry = path.EndsWith('/');
        string[] segments = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        int group = Group(entry);
        string status = GitRecords.Unwrap(entry["Status"]) as string ?? "..";
        var node = root; Count(node.All, group, status);
        foreach (string segment in segments)
        {
            node.Directory = true;
            if (!node.Children.TryGetValue(segment, out var child)) node.Children[segment] = child = new Node(node.Path.Length == 0 ? segment : node.Path + "/" + segment);
            node = child; Count(node.All, group, status);
        }
        if (directoryEntry) node.Directory = true;
        Count(node.Self, group, status);
    }

    /// <summary>Increments counters for one entry.</summary>
    /// <param name="counters">Counters to update.</param>
    /// <param name="group">Entry group (0 conflict, 1 tracked, 2 untracked).</param>
    /// <param name="status">Porcelain XY pair.</param>
    private static void Count(Counters counters, int group, string status)
    {
        counters.Total++;
        if (group == 0) counters.Conflicted++;
        else if (group == 2) counters.Untracked++;
        else { if (status.Length > 0 && status[0] != '.') counters.Staged++; if (status.Length > 1 && status[1] != '.') counters.Unstaged++; }
    }

    /// <summary>Descends single-child chains that hold no entry of their own.</summary>
    /// <param name="node">Start node.</param>
    private static Node Compress(Node node)
    {
        while (node.Self.Total == 0 && node.Children.Count == 1) node = node.Children.Values.First();
        return node;
    }

    /// <summary>Replaces a directory by its compressed children plus, when present, its own exact entries.</summary>
    /// <param name="node">Directory node.</param>
    private static List<Item> Expand(Node node)
    {
        var items = node.Children.Values.Select(child => Whole(Compress(child))).ToList();
        // Exact entries of a directory node are a leaf item ("File" kind is never expanded again).
        if (node.Self.Total > 0) items.Add(new Item(node, "File", node.Self, 1));
        return items;
    }

    /// <summary>Wraps a whole subtree as a frontier item.</summary>
    /// <param name="node">Subtree root.</param>
    private static Item Whole(Node node) => new(node, node.Directory || node.Path.Length == 0 ? "Directory" : "File", node.All, 1);

    /// <summary>Orders entries: conflicts first, then tracked changes, then untracked files.</summary>
    /// <param name="entry">Status entry.</param>
    private static int Group(IDictionary entry) => (GitRecords.Unwrap(entry["Kind"]) as string) switch { "Conflicted" => 0, "Untracked" => 2, _ => 1 };

    /// <summary>Returns the comparable path of an entry; non-UTF-8 paths use their explicit Base64 representation.</summary>
    /// <param name="entry">Status entry.</param>
    private static string PathKey(IDictionary entry) => GitRecords.Unwrap(entry["Path"]) switch
    {
        string text => text,
        IDictionary raw => "<bytes:" + GitRecords.Unwrap(raw["Base64"]) + ">",
        _ => string.Empty,
    };
}
