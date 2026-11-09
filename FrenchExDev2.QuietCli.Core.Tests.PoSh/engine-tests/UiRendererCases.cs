using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Contract, property and fuzz cases for <see cref="QuietUiRenderer"/>, driven directly against the real
/// class with a <see cref="RecordingSurface"/> test double standing in for <see cref="IUiSurface"/> -- no
/// PowerShell runspace, no real console or Spectre.Console session is ever touched by this file.</summary>
internal static class UiRendererCases
{
    /// <summary>Fixed seed retained so any failing generated sequence can be replayed deterministically.</summary>
    private const int Seed = 20261108;

    /// <summary>Runs every renderer case.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run)
    {
        await run("live viewport layout bounds Unicode rows and retains identity across resize and malformed text", () =>
        {
            var method = typeof(QuietUiRenderer).Assembly.GetType("FrenchExDev2.QuietCli.Cmdlets.UiFrameLayout")!
                .GetMethod("Create", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic)!;
            string[] header = ["Project: QuietCli Core | Task: smoke", "C:/workspace/" + new string('x', 150), "C:/module"];
            var random = new Random(20261109);
            for (int iteration = 0; iteration < 200; iteration++)
            {
                int width = random.Next(12, 140), height = random.Next(4, 35);
                string payload = new string('x', random.Next(1, 200)) + "été 漢🙂 e\u0301\u001b[31m\n\r\0\ud800";
                LaneSnapshot[] lanes = Enumerable.Range(0, random.Next(1, 12)).Select(i => new LaneSnapshot("m" + i, [payload, payload])).ToArray();
                var rows = (string[])method.Invoke(null, ["*", header, lanes, width, height])!;
                Require(rows.Length <= height && rows.Length > 0, $"Height exceeded: seed=20261109 iteration={iteration}");
                Require(rows[0].StartsWith("Project:", StringComparison.Ordinal) || rows[0].StartsWith("P:", StringComparison.Ordinal), "Project identity disappeared");
                Require(rows[0].Contains("Task:", StringComparison.Ordinal) || rows[0].Contains(" T:", StringComparison.Ordinal), "Task identity disappeared");
                foreach (string row in rows)
                {
                    int cells = row.EnumerateRunes().Sum(rune => System.Text.Rune.GetUnicodeCategory(rune) is System.Globalization.UnicodeCategory.NonSpacingMark or System.Globalization.UnicodeCategory.Format ? 0 : rune.Value is >= 0x1100 and <= 0x115f or >= 0x2e80 and <= 0xa4cf or >= 0x1f300 and <= 0x1faff ? 2 : 1);
                    Require(cells <= width, $"Width exceeded: seed=20261109 iteration={iteration} width={width} row={row}");
                    Require(!row.Any(char.IsControl) && !row.Contains('\ud800'), "Terminal controls or malformed UTF-16 survived");
                }
            }
            return Task.CompletedTask;
        });
        await run("append-only output retains a late header and emits changed lane text without escape sequences", () =>
        {
            var lines = new List<string>();
            using var surface = new AppendOnlySurface(lines.Add);
            surface.Draw("*", [], []);
            surface.Draw("*", ["project", "workspace"], [new LaneSnapshot("web", ["ready"])]);
            surface.Draw("*", ["project", "workspace"], [new LaneSnapshot("web", ["ready"])]);
            surface.Draw("*", ["replacement"], [new LaneSnapshot("web", ["done"])]);
            Require(lines.SequenceEqual(["project", "workspace", "[web] ready", "replacement", "[web] done"]), "Late header, deduplication or plain output changed");
            Require(lines.All(line => !line.Contains('\u001b')), "Append-only output contains cursor controls");
            return Task.CompletedTask;
        });
        await run("Format never throws and produces the documented [date]... shape for every known event kind", () =>
        {
            foreach (var (evt, key, pattern, description) in new (object Evt, string Key, string Pattern, string Description)[]
            {
                (new { Timestamp = DateTimeOffset.FromUnixTimeSeconds(1700000000), Machine = "web", Type = "ui", Fields = new object[] { "detail", "some output" } },
                    "", @"^\[\d{2}:\d{2}:\d{2}\]\[ui\]\[detail\]\[web\] some output$", "generic Vagrant event"),
                (new { Kind = "ProvisionerStarted", Machine = "web", Provisioner = "shell", Timestamp = DateTimeOffset.FromUnixTimeSeconds(1700000001) },
                    "", @"^\[\d{2}:\d{2}:\d{2}\]\[provision\]\[web\] Running provisioner: shell$", "ProvisionerStarted synthetic event"),
                (new { Stream = "stdout", Text = "raw native text" },
                    "", @"^\[\d{2}:\d{2}:\d{2}\]\[stdout\] raw native text$", "raw -Output {Stream;Text} shape"),
                (42, "", @"^\[\d{2}:\d{2}:\d{2}\] 42$", "totally unexpected scalar"),
            })
            {
                var (surface, renderer) = NewRenderer(1);
                renderer.Write(evt, key);
                renderer.NewLine(key);
                renderer.Dispose();
                string line = Last(surface.DrawCalls).Lanes.Single(l => l.Key == key).Lines.Single();
                Require(System.Text.RegularExpressions.Regex.IsMatch(line, pattern), $"{description}: expected pattern {pattern}, observed '{line}'");
            }
            return Task.CompletedTask;
        });

        await run("Format swallows an event whose own ToString throws, returning an empty line rather than propagating", () =>
        {
            var (surface, renderer) = NewRenderer(1);
            renderer.Write(new ThrowingToString());
            renderer.NewLine();
            renderer.Dispose();
            string line = Last(surface.DrawCalls).Lanes.Single(l => l.Key == "").Lines.Single();
            Require(line == "", "A throwing event's ToString leaked into the formatted line instead of yielding an empty one: '" + line + "'");
            return Task.CompletedTask;
        });

        await run("the default lane's tail is a correct MaxLines-deep FIFO, including the MaxLines=1 default", () =>
        {
            foreach (int maxLines in new[] { 1, 3 })
            {
                var (surface, renderer) = NewRenderer(maxLines);
                for (int i = 0; i < 5; i++) { renderer.Write(Marker(i)); renderer.NewLine(); }
                renderer.Dispose();
                string[] lines = Last(surface.DrawCalls).Lanes.Single(l => l.Key == "").Lines.Select(MarkerSuffix).ToArray();
                string[] expected = Enumerable.Range(Math.Max(0, 5 - maxLines), Math.Min(5, maxLines)).Select(i => "m" + i).ToArray();
                Require(lines.Length == expected.Length && lines.SequenceEqual(expected), $"MaxLines={maxLines}: expected tail [{string.Join(",", expected)}], observed [{string.Join(",", lines)}]");
            }
            return Task.CompletedTask;
        });

        await run("lanes (multi-machine dashboard): a write to one lane never disturbs another lane, and lane order follows first-write arrival order", () =>
        {
            var (surface, renderer) = NewRenderer(1);
            renderer.Write(Marker(1), "machine-00");
            renderer.Write(Marker(2), "machine-01");
            renderer.Write(Marker(3), "machine-00"); // overwrites machine-00's still-uncommitted Current; machine-01 untouched
            renderer.Dispose();
            var lanes = Last(surface.DrawCalls).Lanes.ToArray();
            Require(lanes.Length == 2 && lanes[0].Key == "machine-00" && lanes[1].Key == "machine-01",
                "Lane order did not follow first-write arrival order: " + string.Join(",", lanes.Select(l => l.Key)));
            Require(MarkerSuffix(lanes[0].Lines.Single()) == "m3", "machine-00's lane was not overwritten by its own later write: " + lanes[0].Lines.Single());
            Require(MarkerSuffix(lanes[1].Lines.Single()) == "m2", "machine-01's lane was disturbed by a write to a different lane: " + lanes[1].Lines.Single());
            return Task.CompletedTask;
        });

        await run("a lane that is never NewLine-d always shows its latest Current line, never a blank one (the dashboard-without-NewLine usage)", () =>
        {
            var (surface, renderer) = NewRenderer(1);
            renderer.Write(Marker(7), "machine-00");
            renderer.Dispose();
            Require(MarkerSuffix(Last(surface.DrawCalls).Lanes.Single().Lines.Single()) == "m7", "A lane with only a pending Current (never committed via NewLine) rendered blank instead of its latest line");
            return Task.CompletedTask;
        });

        await run("the default lane renders without a [key] prefix in its own formatted content", () =>
        {
            var (surface, renderer) = NewRenderer(1);
            renderer.Write(new { Stream = "stdout", Text = "x" });
            renderer.NewLine();
            renderer.Dispose();
            var lane = Last(surface.DrawCalls).Lanes.Single();
            Require(lane.Key == "", "Default lane key was not empty: '" + lane.Key + "'");
            Require(!lane.Lines.Single().Contains("[]"), "Default lane line unexpectedly carried an empty machine bracket");
            return Task.CompletedTask;
        });

        await run("Format omits a redundant [Machine] bracket exactly when the event's Machine matches the lane's own key", () =>
        {
            var (surface, renderer) = NewRenderer(1);
            var evt = new { Timestamp = DateTimeOffset.FromUnixTimeSeconds(1700000000), Machine = "web", Type = "ui", Fields = new object[] { "detail", "x" } };
            renderer.Write(evt, "web");
            renderer.NewLine("web");
            renderer.Write(evt, "other-lane");
            renderer.NewLine("other-lane");
            renderer.Dispose();
            var lanes = Last(surface.DrawCalls).Lanes.ToArray();
            string sameKeyLine = lanes.Single(l => l.Key == "web").Lines.Single();
            string differentKeyLine = lanes.Single(l => l.Key == "other-lane").Lines.Single();
            Require(!sameKeyLine.Contains("[web]"), "Redundant [Machine] bracket was shown although the lane key already names the same machine: " + sameKeyLine);
            Require(differentKeyLine.Contains("[web]"), "Machine bracket was omitted although the lane key differs from the event's Machine: " + differentKeyLine);
            return Task.CompletedTask;
        });

        await run("SetHeader replaces the previous header and the replacement persists across later draws without being re-set", () =>
        {
            var surface = new RecordingSurface();
            using var renderer = new QuietUiRenderer(1, surface, (_, _, _) => { });
            renderer.SetHeader(["first"]);
            Require(WaitForHeader(surface, ["first"]), "Header 'first' was never drawn");
            renderer.SetHeader(["second", "line"]);
            Require(WaitForHeader(surface, ["second", "line"]), "Replaced header 'second/line' was never drawn");
            int countAfterReplace = surface.DrawCalls.Count;
            // No further SetHeader call: the next draw(s) must still show the replaced header, never reverting to 'first'.
            Require(WaitForDrawCountAbove(surface, countAfterReplace) > countAfterReplace, "No further draw observed to confirm header persistence");
            Require(surface.DrawCalls[^1].Header.SequenceEqual(["second", "line"]), "Header did not persist to a later draw without being re-set: " + string.Join(",", surface.DrawCalls[^1].Header));
            return Task.CompletedTask;
        });

        await run("Dispose calls IUiSurface.Dispose exactly once, is idempotent, and a Draw failure is caught, logged and stops further rendering without ever propagating", () =>
        {
            var surface = new RecordingSurface { ThrowOnDraw = true };
            var failures = new List<(string Code, string Component, string Message)>();
            var renderer = new QuietUiRenderer(1, surface, (code, component, message) => failures.Add((code, component, message)));
            renderer.Write(Marker(1));
            renderer.Dispose();
            renderer.Dispose(); // idempotent: must not throw, must not draw or dispose the surface again
            Require(surface.DrawCalls.Count == 0, "A throwing Draw call was still recorded as a successful draw");
            Require(surface.DisposeCount == 1, "IUiSurface.Dispose was not called exactly once: " + surface.DisposeCount);
            // At least one failure is guaranteed (Dispose's own final Tick, if nothing else); the background timer
            // racing a near-simultaneous explicit Tick is a narrow, benign window, not asserted away here.
            Require(failures.Count >= 1 && failures.All(f => f.Code == "UiRenderFailed" && f.Component == "Ui"), "Draw failure was not reported via logFailure with the expected code/component: " + failures.Count);
            return Task.CompletedTask;
        });

        await run("property: for randomly interleaved writes across randomly named lanes, every lane's final line reflects only its own latest write, independent of write order on other lanes", () =>
        {
            var random = new Random(Seed);
            for (int round = 0; round < 50; round++)
            {
                int laneCount = random.Next(1, 6);
                string[] keys = Enumerable.Range(0, laneCount).Select(i => "lane-" + i).ToArray();
                var expected = new Dictionary<string, string>();
                var (surface, renderer) = NewRenderer(1);
                int writeCount = random.Next(laneCount, laneCount * 5);
                var firstSeen = new List<string>();
                for (int i = 0; i < writeCount; i++)
                {
                    string key = keys[random.Next(0, laneCount)];
                    if (!firstSeen.Contains(key)) firstSeen.Add(key);
                    string marker = "r" + round + "-w" + i;
                    renderer.Write(Marker(marker), key);
                    expected[key] = marker;
                }
                renderer.Dispose();
                var lanes = Last(surface.DrawCalls).Lanes.ToArray();
                Require(lanes.Select(l => l.Key).SequenceEqual(firstSeen), $"Round {round}: lane order did not follow first-write arrival order");
                foreach (var lane in lanes)
                    Require(MarkerSuffix(lane.Lines.Single()) == "m" + expected[lane.Key], $"Round {round}: lane {lane.Key} did not reflect its own latest write");
            }
            return Task.CompletedTask;
        });
    }

    /// <summary>Constructs an isolated renderer/surface pair for one case.</summary>
    private static (RecordingSurface Surface, QuietUiRenderer Renderer) NewRenderer(int maxLines)
    {
        var surface = new RecordingSurface();
        return (surface, new QuietUiRenderer(maxLines, surface, (_, _, _) => { }));
    }

    /// <summary>A minimal event with no recognized shape, so Format's final fallback branch renders it as
    /// `"[date] m&lt;value&gt;"` -- the marker text is always the formatted line's exact suffix (after the one
    /// space following the closing bracket), independent of the non-deterministic date/machine prefix.</summary>
    private static object Marker(object value) => "m" + value;

    /// <summary>The marker text carried by a line Write(Marker(value)) produced, i.e. everything after the last `"] "`.</summary>
    private static string MarkerSuffix(string line) => line[(line.LastIndexOf("] ", StringComparison.Ordinal) + 2)..];

    /// <summary>Returns the last recorded Draw call -- the one Dispose's own final, synchronous Tick deterministically
    /// produces after every prior Write/NewLine, regardless of whether the background timer (period 100ms, due
    /// time Zero) also happened to fire one or more earlier draws of a now-stale, still-valid-but-superseded state.</summary>
    private static (string Glyph, string[] Header, LaneSnapshot[] Lanes) Last(List<(string Glyph, string[] Header, LaneSnapshot[] Lanes)> calls)
    {
        Require(calls.Count >= 1, "Expected at least one Draw call, observed none");
        return calls[^1];
    }

    /// <summary>Polls the live background timer for a draw whose header exactly matches, bounded so a stalled
    /// timer fails fast instead of hanging. Checks every recorded draw, not just the latest, since an earlier
    /// (pre-SetHeader) draw may already have landed in the list without invalidating a later matching one.</summary>
    private static bool WaitForHeader(RecordingSurface surface, string[] header)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(2);
        while (!surface.DrawCalls.Any(c => c.Header.SequenceEqual(header)) && DateTimeOffset.UtcNow < deadline) Thread.Sleep(10);
        return surface.DrawCalls.Any(c => c.Header.SequenceEqual(header));
    }

    private static int WaitForDrawCountAbove(RecordingSurface surface, int previousCount)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(2);
        while (surface.DrawCalls.Count <= previousCount && DateTimeOffset.UtcNow < deadline) Thread.Sleep(10);
        return surface.DrawCalls.Count;
    }

    private sealed class ThrowingToString { public override string ToString() => throw new InvalidOperationException("SyntheticToStringFailure"); }

    /// <summary>Test double for <see cref="IUiSurface"/>: records every Draw call instead of rendering, and never touches a real console.</summary>
    private sealed class RecordingSurface : IUiSurface
    {
        private readonly object sync = new();
        private readonly List<(string Glyph, string[] Header, LaneSnapshot[] Lanes)> calls = [];
        public List<(string Glyph, string[] Header, LaneSnapshot[] Lanes)> DrawCalls { get { lock (sync) return calls.ToList(); } }
        public int DisposeCount;
        public bool ThrowOnDraw;

        public void Draw(string spinnerGlyph, IReadOnlyList<string> header, IReadOnlyList<LaneSnapshot> lanes)
        {
            if (ThrowOnDraw) throw new InvalidOperationException("SyntheticDrawFailure");
            lock (sync) calls.Add((spinnerGlyph, header.ToArray(), lanes.ToArray()));
        }

        public void Dispose() => DisposeCount++;
    }

    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
