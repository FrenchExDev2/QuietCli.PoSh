using System.Collections;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Git-owned machine-format parsers running locally, without engine IPC or native execution.</summary>
public static class GitRecords
{
    /// <summary>Stateless strict field decoder, shared without incremental state.</summary>
    private static readonly Encoding utf8 = new UTF8Encoding(false, true);
    /// <summary>Local branch divergence format.</summary>
    private static readonly Regex divergence = new(@"^\+(\d+) -(\d+)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    /// <summary>Porcelain tracked status pair.</summary>
    private static readonly Regex status = new(@"^[.MADRCUT]{2}$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    /// <summary>Patch file marker, including combined patches.</summary>
    private static readonly Regex fileHeader = new(@"^diff --(git|cc|combined) (.*)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    /// <summary>Patch commit marker.</summary>
    private static readonly Regex commitHeader = new(@"^commit ([0-9a-f]+)", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    /// <summary>Patch hunk marker with matching delimiter width.</summary>
    private static readonly Regex hunkHeader = new(@"^(@@+)(.*)\1(.*)$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    /// <summary>Individual hunk range.</summary>
    private static readonly Regex ranges = new(@"[-+]\d+(?:,\d+)?", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    /// <summary>Tree machine header.</summary>
    private static readonly Regex tree = new(@"^(\d+) (blob|tree|commit) ([0-9a-f]+)\s+(\d+|-)\s*$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    /// <summary>History object identity, supporting SHA-1 and SHA-256.</summary>
    private static readonly Regex oid = new(@"^[0-9a-f]{40}(?:[0-9a-f]{24})?$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    /// <summary>Preserves malformed UTF-8 as an explicit business byte representation.</summary>
    /// <param name="record">One transient field or record.</param>
    public static object Decode(byte[] record) => Decode(record.AsSpan());
    /// <summary>Decodes a slice without copying it first.</summary>
    /// <param name="bytes">Field bytes.</param>
    private static object Decode(ReadOnlySpan<byte> bytes)
    {
        try { return utf8.GetString(bytes); }
        catch (DecoderFallbackException) { return Map("Encoding", "RawBytes", "Base64", Convert.ToBase64String(bytes), "Bytes", bytes.Length); }
    }

    /// <summary>Unwraps known PowerShell scalar wrappers while retaining custom property bags.</summary>
    /// <param name="value">Caller value or scalar wrapper.</param>
    internal static object? Unwrap(object? value)
    {
        while (value?.GetType().FullName == "System.Management.Automation.PSObject")
        {
            var item = value.GetType().GetProperty("BaseObject")!.GetValue(value);
            if (item?.GetType().FullName == "System.Management.Automation.PSCustomObject" || ReferenceEquals(item, value)) return value;
            value = item;
        }
        return value;
    }
    /// <summary>Creates the same case-insensitive mutable business maps as PowerShell hashtable literals.</summary>
    /// <param name="pairs">Alternating keys and values.</param>
    internal static Hashtable Map(params object?[] pairs)
    {
        var map = new Hashtable(StringComparer.OrdinalIgnoreCase);
        for (int index = 0; index < pairs.Length; index += 2) map.Add((string)pairs[index]!, pairs[index + 1]);
        return map;
    }
    /// <summary>Reads a state map without reflecting arbitrary business properties.</summary>
    /// <param name="value">Explicit parser map.</param>
    internal static IDictionary Dict(object? value) => (IDictionary)Unwrap(value)!;
    /// <summary>Reads an explicitly retained business sequence.</summary>
    /// <param name="map">Owner.</param>
    /// <param name="key">Sequence field.</param>
    private static IList List(IDictionary map, string key) => (IList)Unwrap(map[key])!;
    /// <summary>Increments one observed status count.</summary>
    /// <param name="counts">Count map.</param>
    /// <param name="key">Count name.</param>
    private static void Increment(IDictionary counts, string key) => counts[key] = Convert.ToInt64(Unwrap(counts[key]), CultureInfo.InvariantCulture) + 1;

    /// <summary>Parses one porcelain-v2 NUL record, including the separate rename source record.</summary>
    /// <param name="record">Exact bytes excluding NUL.</param>
    /// <param name="data">Caller-owned status state.</param>
    public static void Status(byte[] record, IDictionary data)
    {
        if (Unwrap(data["Pending"]) is IDictionary pending) { pending["OriginalPath"] = Decode(record); data["Pending"] = null; return; }
        if (record.Length == 0) return;
        if (record[0] == 35)
        {
            if (record.Length < 2) throw new InvalidDataException("MalformedStatusHeader");
            int space = Array.IndexOf(record, (byte)32, 2);
            if (space < 0) return;
            string key = Encoding.ASCII.GetString(record.AsSpan(2, space - 2)); object value = Decode(record.AsSpan(space + 1));
            switch (key)
            {
                case "branch.head": bool detached = value is string head && head == "(detached)"; data["Detached"] = detached; data["Branch"] = detached ? null : value; break;
                case "branch.oid": bool unborn = value is string objectId && objectId == "(initial)"; data["Unborn"] = unborn; data["HeadOid"] = unborn ? null : value; break;
                case "branch.upstream": data["Upstream"] = value; break;
                case "branch.ab":
                    var match = value is string text ? divergence.Match(text) : Match.Empty;
                    if (!match.Success) throw new InvalidDataException("MalformedBranchDivergence");
                    data["Ahead"] = long.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture); data["Behind"] = long.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture); break;
                case "stash": data["StashCount"] = long.Parse(Convert.ToString(value, CultureInfo.InvariantCulture)!, CultureInfo.InvariantCulture); break;
            }
            return;
        }
        char kind = (char)record[0]; var counts = Dict(data["Counts"]); Hashtable entry;
        if (kind is '?' or '!')
        {
            if (record.Length < 3 || record[1] != 32) throw new InvalidDataException("MalformedStatusPath");
            entry = Map("Kind", kind == '?' ? "Untracked" : "Ignored", "Status", kind == '?' ? "??" : "!!", "Path", Decode(record.AsSpan(2)), "OriginalPath", null, "Submodule", null);
            if (kind == '?') { Increment(counts, "Untracked"); Increment(counts, "Changed"); } else Increment(counts, "Ignored");
        }
        else if (kind is '1' or '2' or 'u')
        {
            int limit = kind == '1' ? 8 : kind == '2' ? 9 : 10; var fields = new List<string>(); int start = 0;
            for (int index = 0; index < record.Length && fields.Count < limit; index++)
                if (record[index] == 32) { fields.Add(Encoding.ASCII.GetString(record.AsSpan(start, index - start))); start = index + 1; }
            if (fields.Count != limit || start >= record.Length || !status.IsMatch(fields[1])) throw new InvalidDataException("MalformedPorcelainStatusRecord");
            entry = Map("Kind", kind == 'u' ? "Conflicted" : kind == '2' ? "RenamedOrCopied" : "Tracked", "Status", fields[1], "Path", Decode(record.AsSpan(start)), "OriginalPath", null, "Submodule", fields[2]);
            Increment(counts, "Changed");
            if (kind == 'u') Increment(counts, "Conflicted");
            else { if (fields[1][0] != '.') Increment(counts, "Staged"); if (fields[1][1] != '.') Increment(counts, "Unstaged"); }
            if (kind == '2') { data["Pending"] = entry; if (fields[8].StartsWith('R')) Increment(counts, "Renamed"); }
        }
        else throw new InvalidDataException("UnknownPorcelainStatusRecord");
        List(data, "Entries").Add(entry);
    }

    /// <summary>Parses one patch line without changing its display labels or binary representation.</summary>
    /// <param name="record">Exact bytes excluding LF.</param>
    /// <param name="data">Caller-owned patch state.</param>
    public static void Patch(byte[] record, IDictionary data)
    {
        object decoded = Decode(record);
        var currentHunk = Unwrap(data["CurrentHunk"]) as IDictionary; var currentFile = Unwrap(data["CurrentFile"]) as IDictionary;
        if (decoded is not string line)
        {
            var row = Map("Kind", "ByteContent", "Content", decoded);
            if (currentHunk != null) List(currentHunk, "Lines").Add(row); else if (currentFile != null) List(currentFile, "Metadata").Add(row); else List(data, "Preamble").Add(row);
            return;
        }
        var match = fileHeader.Match(line);
        if (match.Success)
        {
            var file = Map("Header", line, "CommitId", data["CurrentCommit"], "Combined", match.Groups[1].Value != "git", "Labels", match.Groups[2].Value, "OldLabel", null, "NewLabel", null, "OldMode", null, "NewMode", null, "Binary", false, "Metadata", new List<object>(), "Hunks", new List<object>());
            List(data, "Files").Add(file); data["CurrentFile"] = file; data["CurrentHunk"] = null; return;
        }
        match = commitHeader.Match(line);
        if (match.Success) { data["CurrentCommit"] = match.Groups[1].Value; List(data, "Commits").Add(Map("ObjectId", match.Groups[1].Value)); data["CurrentFile"] = null; data["CurrentHunk"] = null; List(data, "Preamble").Add(Map("Text", line)); return; }
        if (currentFile == null) { List(data, "Preamble").Add(Map("Text", line)); return; }
        match = hunkHeader.Match(line);
        if (match.Success)
        {
            var hunk = Map("Header", line, "Combined", match.Groups[1].Value.Length > 2, "Ranges", ranges.Matches(match.Groups[2].Value).Select(item => item.Value).ToArray(), "Lines", new List<object>());
            List(currentFile, "Hunks").Add(hunk); data["CurrentHunk"] = hunk; return;
        }
        if (currentHunk != null)
        {
            string kind = line.StartsWith("\\ No newline", StringComparison.Ordinal) ? "NoFinalNewline" : Unwrap(currentHunk["Combined"]) is true ? "CombinedContent" : line.StartsWith('+') ? "Addition" : line.StartsWith('-') ? "Deletion" : "Context";
            List(currentHunk, "Lines").Add(Map("Kind", kind, "Text", line)); return;
        }
        if (line.StartsWith("--- ", StringComparison.Ordinal)) currentFile["OldLabel"] = line[4..];
        if (line.StartsWith("+++ ", StringComparison.Ordinal)) currentFile["NewLabel"] = line[4..];
        match = Regex.Match(line, @"^(?:old mode|deleted file mode) (\d+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant); if (match.Success) currentFile["OldMode"] = match.Groups[1].Value;
        match = Regex.Match(line, @"^(?:new mode|new file mode) (\d+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant); if (match.Success) currentFile["NewMode"] = match.Groups[1].Value;
        if (line.StartsWith("Binary files ", StringComparison.OrdinalIgnoreCase) || line.StartsWith("GIT binary patch", StringComparison.OrdinalIgnoreCase)) currentFile["Binary"] = true;
        List(currentFile, "Metadata").Add(Map("Text", line));
    }

    /// <summary>Decodes and appends a NUL field; PowerShell retains caller-local group callback dispatch.</summary>
    /// <param name="record">One NUL-delimited field.</param>
    /// <param name="state">Fields, FieldCount and caller business state.</param>
    public static bool Field(byte[] record, IDictionary state)
    {
        object value = Decode(record); var fields = List(state, "Fields");
        if (fields.Count == 0 && value is string text) { value = text.TrimStart('\r', '\n'); if (((string)value).Length == 0) return false; }
        fields.Add(value);
        return fields.Count == Convert.ToInt32(Unwrap(state["FieldCount"]), CultureInfo.InvariantCulture);
    }
    /// <summary>Maps the ten-field history protocol into explicit commit objects.</summary>
    /// <param name="fields">Complete NUL field group.</param>
    /// <param name="data">Caller-owned commits.</param>
    public static void Commit(IList fields, IDictionary data)
    {
        object? id = Unwrap(fields[0]);
        if (id is not string text || !oid.IsMatch(text)) throw new InvalidDataException("MalformedLogObjectId");
        string parents = Convert.ToString(Unwrap(fields[1]), CultureInfo.InvariantCulture) ?? "";
        List(data, "Commits").Add(Map("ObjectId", id, "Parents", parents.Split(' ', StringSplitOptions.RemoveEmptyEntries), "Author", Map("Name", fields[2], "Email", fields[3], "Date", fields[4]), "Committer", Map("Name", fields[5], "Email", fields[6], "Date", fields[7]), "Subject", fields[8], "Body", fields[9]));
    }
    /// <summary>Maps one long ls-tree record, preserving path bytes after its first tab.</summary>
    /// <param name="record">Exact NUL-delimited bytes.</param>
    /// <param name="data">Caller-owned tree entries.</param>
    public static void Tree(byte[] record, IDictionary data)
    {
        if (record.Length == 0) return;
        int tab = Array.IndexOf(record, (byte)9); if (tab < 0) throw new InvalidDataException("MalformedTreeRecord");
        var match = tree.Match(Encoding.ASCII.GetString(record.AsSpan(0, tab))); if (!match.Success) throw new InvalidDataException("MalformedTreeHeader");
        List(data, "Entries").Add(Map("Mode", match.Groups[1].Value, "Type", match.Groups[2].Value, "ObjectId", match.Groups[3].Value, "Size", match.Groups[4].Value == "-" ? null : long.Parse(match.Groups[4].Value, CultureInfo.InvariantCulture), "Path", Decode(record.AsSpan(tab + 1))));
    }
    /// <summary>Parses one worktree porcelain record with explicit entry boundaries.</summary>
    /// <param name="record">Exact NUL-delimited bytes.</param>
    /// <param name="data">Caller-owned worktree state.</param>
    public static void Worktree(byte[] record, IDictionary data)
    {
        var current = Unwrap(data["Current"]) as IDictionary;
        if (record.Length == 0) { if (current != null) { List(data, "Worktrees").Add(current); data["Current"] = null; } return; }
        int space = Array.IndexOf(record, (byte)32); string key = Encoding.ASCII.GetString(record.AsSpan(0, space < 0 ? record.Length : space));
        object value = space >= 0 ? Decode(record.AsSpan(space + 1)) : true;
        if (key == "worktree") { if (current != null) List(data, "Worktrees").Add(current); data["Current"] = Map("Path", value, "HeadOid", null, "Branch", null, "Bare", false, "Detached", false, "Locked", null, "Prunable", null); return; }
        if (current == null) throw new InvalidDataException("WorktreeFieldWithoutEntry");
        switch (key) { case "HEAD": current["HeadOid"] = value; break; case "branch": current["Branch"] = value; break; case "bare": current["Bare"] = true; break; case "detached": current["Detached"] = true; break; case "locked": current["Locked"] = value; break; case "prunable": current["Prunable"] = value; break; default: current[key] = value; break; }
    }
    /// <summary>Compares local refs using ordinal names and independently observed object IDs.</summary>
    /// <param name="before">Before observation.</param>
    /// <param name="after">After observation.</param>
    public static object[] RefChanges(object[]? before, object[]? after)
    {
        Dictionary<string, IDictionary> Index(object[] records)
        {
            var map = new Dictionary<string, IDictionary>(StringComparer.Ordinal);
            foreach (var item in records) { var row = Dict(item); object? name = Unwrap(row["Name"]); string key = name as string ?? (string)Unwrap(Dict(name)["Base64"])!; map[key] = row; }
            return map;
        }
        var old = Index(before ?? []); var current = Index(after ?? []); var names = new SortedSet<string>(old.Keys, StringComparer.Ordinal); names.UnionWith(current.Keys);
        var changes = new List<object>();
        foreach (string name in names)
        {
            old.TryGetValue(name, out var a); current.TryGetValue(name, out var b);
            object? oldId = a == null ? null : Unwrap(a["ObjectId"]); object? newId = b == null ? null : Unwrap(b["ObjectId"]);
            if (a == null || b == null || !Equals(oldId, newId)) changes.Add(Map("Kind", a == null ? "Added" : b == null ? "Removed" : "Updated", "Name", name, "Before", oldId, "After", newId));
        }
        return changes.ToArray();
    }
}
