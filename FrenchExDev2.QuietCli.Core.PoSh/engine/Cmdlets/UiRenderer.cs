using System.Collections;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using Spectre.Console;
using Spectre.Console.Rendering;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Where a <see cref="QuietUiRenderer"/> draws. Swappable so tests and redirected output never touch
/// the real console (Strategy + Dependency Inversion — the seam that makes the renderer unit-testable).</summary>
public interface IUiSurface : IDisposable
{
    /// <summary>Renders one frame.</summary>
    /// <param name="spinnerGlyph">Current frame of the shared animated glyph.</param>
    /// <param name="header">Static lines set via <see cref="QuietUiRenderer.SetHeader"/>; empty when unset.</param>
    /// <param name="lanes">One entry per lane, insertion order; <see cref="LaneSnapshot.Key"/> is empty for the
    /// unnamed default lane (rendered without a key prefix) and the machine name otherwise.</param>
    void Draw(string spinnerGlyph, IReadOnlyList<string> header, IReadOnlyList<LaneSnapshot> lanes);
}

/// <summary>One lane's rendered state for a single <see cref="IUiSurface.Draw"/> call: its key (empty for the
/// unnamed default lane) and its most recent formatted line(s), most recent last.</summary>
public readonly record struct LaneSnapshot(string Key, IReadOnlyList<string> Lines);

/// <summary>Interactive surface: a thin render target wrapping one AnsiConsole <c>Live</c> session, running on
/// its own background thread (the blocking <c>Start</c> callback has to stay entered for the session's whole
/// lifetime). <see cref="Draw"/> rebuilds the Spectre renderable and calls <c>LiveDisplayContext.Refresh()</c>
/// from whichever thread calls it (the owning <see cref="QuietUiRenderer"/>'s timer thread).</summary>
public sealed class SpectreLiveSurface : IUiSurface
{
    private readonly object sync = new();
    private readonly ManualResetEventSlim started = new(false);
    private readonly ManualResetEventSlim stop = new(false);
    private readonly Thread thread;
    private LiveDisplayContext? context;
    private Exception? startupError;

    /// <summary>Starts the background Live session and waits for it to attach. Rethrows synchronously if Spectre
    /// refuses a nested Live/Status/Progress session in this process.</summary>
    public SpectreLiveSurface()
    {
        thread = new Thread(Run) { IsBackground = true, Name = "QuietUiLive" };
        thread.Start();
        started.Wait();
        if (startupError is { } error) throw error;
    }

    private void Run()
    {
        try
        {
            AnsiConsole.Live(new Markup("")).Start(ctx =>
            {
                lock (sync) context = ctx;
                started.Set();
                stop.Wait();
            });
        }
        catch (Exception error)
        {
            startupError = error;
            started.Set();
        }
    }

    /// <inheritdoc />
    public void Draw(string spinnerGlyph, IReadOnlyList<string> header, IReadOnlyList<LaneSnapshot> lanes)
    {
        lock (sync)
        {
            if (context is null) return;
            context.UpdateTarget(Compose(spinnerGlyph, header, lanes));
            context.Refresh();
        }
    }

    private static IRenderable Compose(string spinnerGlyph, IReadOnlyList<string> header, IReadOnlyList<LaneSnapshot> lanes)
    {
        int width = Math.Max(1, AnsiConsole.Profile.Width - 1);
        int height = Math.Max(1, AnsiConsole.Profile.Height - 1);
        return new Rows(UiFrameLayout.Create(spinnerGlyph, header, lanes, width, height).Select(line => new Text(line)));
    }

    /// <inheritdoc />
    public void Dispose()
    {
        stop.Set();
        thread.Join(TimeSpan.FromSeconds(2));
    }
}

/// <summary>Non-interactive fallback (redirected output): one plain line per committed line (`"[key] line"`,
/// or bare `"line"` for the default lane), no spinner, no cursor repositioning — chosen once at construction
/// via <c>AnsiConsole.Profile.Capabilities.Interactive</c>. Only emits a line when a lane's most recent text
/// actually changed since the previous Draw, so a silent lane never floods append-only output.</summary>
public sealed class AppendOnlySurface : IUiSurface
{
    private readonly Dictionary<string, string> last = new(StringComparer.Ordinal);
    private string[] lastHeader = [];
    private readonly Action<string> writeLine;

    /// <summary>Creates an append-only surface with an optional output sink for independent tests.</summary>
    /// <param name="writeLine">Plain-text sink, or the current Spectre console when omitted.</param>
    public AppendOnlySurface(Action<string>? writeLine = null) => this.writeLine = writeLine ?? AnsiConsole.WriteLine;

    /// <inheritdoc />
    public void Draw(string spinnerGlyph, IReadOnlyList<string> header, IReadOnlyList<LaneSnapshot> lanes)
    {
        if (!lastHeader.SequenceEqual(header))
        {
            foreach (string line in header) writeLine(line);
            lastHeader = header.ToArray();
        }
        foreach (LaneSnapshot lane in lanes)
        {
            if (lane.Lines.Count == 0) continue;
            string current = lane.Lines[^1];
            if (last.TryGetValue(lane.Key, out string? previous) && previous == current) continue;
            last[lane.Key] = current;
            writeLine(lane.Key.Length == 0 ? current : $"[{lane.Key}] {current}");
        }
    }

    /// <inheritdoc />
    public void Dispose() { }
}

/// <summary>
/// Owns the live frame for `-UI`: a shared spinner plus an ordered set of named "lanes", each holding its own
/// in-progress <c>current</c> line and its own <c>MaxLines</c>-deep scrolling <c>tail</c>. <see cref="Write"/>/
/// <see cref="NewLine"/> are the synchronous proxy a caller (PowerShell `-Output`/`Execute`) invokes — they only
/// ever mutate the lanes dictionary under <see cref="sync"/> (Monitor Object) and return immediately.
/// <b>Who ticks</b>: this class owns a <see cref="System.Threading.Timer"/> (started in the constructor, 10/s,
/// stopped in <see cref="Dispose"/>) that is the ONLY thing that calls <see cref="IUiSurface.Draw"/> — on every
/// tick it takes <see cref="sync"/>, builds an immutable snapshot (next spinner frame, header, one
/// <see cref="LaneSnapshot"/> per lane) and releases the lock BEFORE calling <c>surface.Draw(...)</c>, so a slow
/// render never blocks a concurrent <see cref="Write"/>/<see cref="NewLine"/> call. This is the Active Object /
/// Half-Sync-Half-Async split: the synchronous layer (callback thread) only ever touches the guarded state; the
/// asynchronous layer (this timer) is the sole reader that turns it into frames, so <see cref="IUiSurface"/>
/// implementations (<see cref="SpectreLiveSurface"/>/<see cref="AppendOnlySurface"/>) need no loop of their own
/// — they just render whatever snapshot they are handed, synchronously, on the timer's thread. Never throws
/// back into the caller: a drawing failure is reported via the constructor's <c>logFailure</c> callback and
/// disables further rendering, exactly like a failing <c>-Listeners</c> entry — Ui is an observation channel,
/// never part of the business outcome.
/// </summary>
public sealed class QuietUiRenderer : IDisposable
{
    private const string DefaultLaneKey = "";
    private static readonly Spinner AnimatedGlyph = Spinner.Known.Dots;
    private readonly object sync = new();
    private readonly int maxLines;
    private readonly object renderSync = new();
    private readonly List<string> laneOrder = [];
    private readonly Dictionary<string, Lane> lanes = [];
    private readonly IUiSurface surface;
    private readonly Action<string, string, string> logFailure;
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly System.Threading.Timer tickTimer;
    private string[] header = [];
    private volatile bool failed;
    private volatile bool disposed;

    /// <summary>Accumulated time spent inside <see cref="IUiSurface.Draw"/>, in milliseconds.</summary>
    public double RenderMs { get; private set; }

    private sealed class Lane
    {
        public PSObject? Current;
        public readonly string[] Tail;
        public int Count;
        public int Head;
        public Lane(int maxLines) => Tail = new string[maxLines];
    }

    /// <param name="maxLines">Scrolling-history depth per lane; 1 reproduces the single always-latest-line dashboard.</param>
    /// <param name="surface">Render target; swappable for testing.</param>
    /// <param name="logFailure">Reports a non-fatal rendering failure (code, phase, message) without throwing.</param>
    public QuietUiRenderer(int maxLines, IUiSurface surface, Action<string, string, string> logFailure)
    {
        if (maxLines <= 0) throw new ArgumentOutOfRangeException(nameof(maxLines), "MaxLinesMustBePositive");
        this.maxLines = maxLines;
        this.surface = surface;
        this.logFailure = logFailure;
        tickTimer = new System.Threading.Timer(_ => Tick(), null, TimeSpan.Zero, TimeSpan.FromMilliseconds(100));
    }

    /// <summary>Sets the static lines drawn above the lanes (e.g. Vagrantfile path, provider mode); replaces any previous header.</summary>
    public void SetHeader(IEnumerable<string> lines) { lock (sync) { header = lines.ToArray(); } }

    /// <summary>Updates the line currently being composed for a lane (default lane when <paramref name="key"/> is
    /// omitted); creates the lane in arrival order if unseen. Picked up by the next redraw.</summary>
    public void Write(object? evt, string key = DefaultLaneKey) { lock (sync) { LaneFor(key).Current = AsPSObject(evt); } }

    /// <summary>Commits the given lane's current line into ITS OWN scrolling tail (oldest entry dropped past
    /// MaxLines) and starts a fresh blank current line — only that lane is affected.</summary>
    public void NewLine(string key = DefaultLaneKey)
    {
        lock (sync)
        {
            Lane lane = LaneFor(key);
            Push(lane, Format(lane.Current, key));
            lane.Current = null;
        }
    }

    private Lane LaneFor(string key)
    {
        if (!lanes.TryGetValue(key, out Lane? lane))
        {
            lane = new Lane(maxLines);
            lanes[key] = lane;
            laneOrder.Add(key);
        }
        return lane;
    }

    private static void Push(Lane lane, string line)
    {
        lane.Tail[lane.Head] = line;
        lane.Head = (lane.Head + 1) % lane.Tail.Length;
        if (lane.Count < lane.Tail.Length) lane.Count++;
    }

    private static IEnumerable<string> ReadTail(Lane lane)
    {
        int start = lane.Count < lane.Tail.Length ? 0 : lane.Head;
        for (int i = 0; i < lane.Count; i++) yield return lane.Tail[(start + i) % lane.Tail.Length];
    }

    private void Tick()
    {
        lock (renderSync)
        {
            if (failed || disposed) return;
            DrawFrame();
        }
    }

    /// <summary>Draws one serialized snapshot, including the final frame after the timer has drained.</summary>
    private void DrawFrame()
    {
        string glyph;
        string[] snapshotHeader;
        var snapshotLanes = new List<LaneSnapshot>();
        lock (sync)
        {
            int frame = (int)(clock.ElapsedMilliseconds / Math.Max(1, (long)AnimatedGlyph.Interval.TotalMilliseconds)) % AnimatedGlyph.Frames.Count;
            glyph = AnimatedGlyph.Frames[frame];
            snapshotHeader = header;
            foreach (string key in laneOrder)
            {
                Lane lane = lanes[key];
                var lines = new List<string>(ReadTail(lane));
                if (lane.Current is not null) lines.Add(Format(lane.Current, key));
                if (lines.Count > maxLines) lines = lines.GetRange(lines.Count - maxLines, maxLines);
                snapshotLanes.Add(new LaneSnapshot(key, lines));
            }
        }
        var watch = Stopwatch.StartNew();
        try { surface.Draw(glyph, snapshotHeader, snapshotLanes); }
        catch (Exception error) { failed = true; logFailure("UiRenderFailed", "Ui", error.Message); }
        finally { RenderMs += watch.Elapsed.TotalMilliseconds; }
    }

    private static PSObject? AsPSObject(object? value) => value is null ? null : value as PSObject ?? PSObject.AsPSObject(value);

    private static object? Unwrap(object? value) => value is PSObject wrapped ? wrapped.BaseObject : value;

    private static string? FormatTimestamp(object? value) => Unwrap(value) switch
    {
        DateTimeOffset dto => dto.ToLocalTime().ToString("HH:mm:ss", CultureInfo.InvariantCulture),
        DateTime dt => dt.ToString("HH:mm:ss", CultureInfo.InvariantCulture),
        _ => null,
    };

    /// <summary>Tolerant `[date][level][stage] content` mapping; never throws on an unexpected shape. Omits a
    /// redundant leading `[Machine]` bracket when the event's Machine matches the lane's own key, since the lane
    /// prefix already shows it.</summary>
    private static string Format(PSObject? evt, string laneKey)
    {
        if (evt is null) return "";
        try
        {
            string date = FormatTimestamp(evt.Properties["Timestamp"]?.Value) ?? DateTime.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture);
            string? machine = Unwrap(evt.Properties["Machine"]?.Value) as string;
            string machinePart = machine is { Length: > 0 } && !string.Equals(machine, laneKey, StringComparison.Ordinal) ? $"[{machine}]" : "";
            if (evt.Properties["Provisioner"]?.Value is { } provisionerValue)
            {
                string provisioner = Convert.ToString(Unwrap(provisionerValue), CultureInfo.InvariantCulture) ?? "";
                return $"[{date}][provision]{machinePart} Running provisioner: {provisioner}".TrimEnd();
            }
            if (evt.Properties["Type"]?.Value is { } typeValue && evt.Properties["Fields"]?.Value is { } fieldsValue)
            {
                string type = Convert.ToString(Unwrap(typeValue), CultureInfo.InvariantCulture) ?? "";
                object?[] values = Unwrap(fieldsValue) is IEnumerable sequence and not string ? sequence.Cast<object?>().ToArray() : [];
                string stage = values.Length > 0 ? Convert.ToString(Unwrap(values[0]), CultureInfo.InvariantCulture) ?? "" : "";
                string content = values.Length > 1 ? string.Join(" ", values.Skip(1).Select(v => Convert.ToString(Unwrap(v), CultureInfo.InvariantCulture))) : "";
                return $"[{date}][{type}][{stage}]{machinePart} {content}".TrimEnd();
            }
            if (evt.Properties["Stream"]?.Value is { } streamValue && evt.Properties["Text"]?.Value is { } textValue)
            {
                string stream = Convert.ToString(Unwrap(streamValue), CultureInfo.InvariantCulture) ?? "";
                string text = Convert.ToString(Unwrap(textValue), CultureInfo.InvariantCulture) ?? "";
                return $"[{date}][{stream}]{machinePart} {text}".TrimEnd();
            }
            return $"[{date}]{machinePart} {Convert.ToString(evt.BaseObject, CultureInfo.InvariantCulture)}".TrimEnd();
        }
        catch { return ""; }
    }

    /// <inheritdoc />
    public void Dispose()
    {
        lock (sync)
        {
            if (disposed) return;
            disposed = true;
        }
        tickTimer.DisposeAsync().AsTask().GetAwaiter().GetResult();
        lock (renderSync)
        {
            if (!failed) DrawFrame();
            try { surface.Dispose(); }
            catch (Exception error) { logFailure("UiRenderFailed", "Ui", error.Message); }
        }
    }
}
