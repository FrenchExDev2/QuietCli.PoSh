using System.Collections;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using Spectre.Console;

namespace FrenchExDev2.QuietCli.Cmdlets;

public sealed partial class InvokeQuietCallCommand
{
    /// <summary>Schedules the shared invocation closure and owns the optional Spectre session.</summary>
    /// <param name="request">Validated facade options.</param>
    /// <param name="maxLines">Number of lines per dashboard lane, or null for pipeline output.</param>
    /// <param name="execute">One completed invocation and its delivery. Returns false to stop watching.</param>
    private void RunWatch(Hashtable request, int? maxLines, Func<QuietUiRenderer?, Func<bool>?, bool> execute)
    {
        if (QuietCallState.Depth > 0 || QuietCallState.RecallDepth > 0)
            throw new InvalidOperationException("WatchRequiresTopLevelInvocation");
        bool onKeypress = LanguagePrimitives.IsTrue(request["WatchOnKeypress"]);
        if (onKeypress && Console.IsInputRedirected)
            throw new InvalidOperationException("WatchOnKeypressRequiresConsoleInput");

        bool Cancelled() => stopping || QuietRuntime.CancellationRequested(request);
        if (Cancelled()) return;

        TimeSpan? interval = request["Watch"] as TimeSpan?;
        QuietUiRenderer? ui = null;
        string? renderError = null;
        try
        {
            if (maxLines is { } lines && !Console.IsInputRedirected && !Console.IsOutputRedirected)
            {
                try
                {
                    if (AnsiConsole.Profile.Capabilities.Interactive)
                    {
                        string trigger = interval is { } delay
                            ? "every " + delay.TotalMilliseconds.ToString("0", CultureInfo.InvariantCulture) + " ms" : "press any key";
                        if (interval is not null && onKeypress) trigger += " or press any key";
                        ui = new QuietUiRenderer(lines, new SpectreLiveSurface(minimumHeaderLines: 4),
                            (_, _, message) => Interlocked.Exchange(ref renderError, message),
                            [$"Watch {NativeCommandLine.Display(request)} | {trigger} | Ctrl+C to stop"]);
                    }
                }
                catch (Exception error) when (error is not PipelineStoppedException)
                {
                    WriteWarning("Watch UI unavailable: " + error.Message);
                }
            }
            while (!Cancelled())
            {
                if (ui is not null && Volatile.Read(ref renderError) is { } message)
                {
                    ui.Dispose();
                    ui = null;
                    WriteWarning("Watch UI stopped: " + message);
                }
                if (!execute(ui, Cancelled) || !WaitForWatchTrigger(interval, onKeypress, Cancelled)) break;
            }
        }
        finally { ui?.Dispose(); }
    }

    /// <summary>Waits after a completed cycle until the first enabled trigger or cancellation.</summary>
    /// <param name="interval">Optional delay before the next execution.</param>
    /// <param name="onKeypress">Whether to consume console keys while waiting.</param>
    /// <param name="cancelled">Tests for pipeline or caller cancellation.</param>
    private static bool WaitForWatchTrigger(TimeSpan? interval, bool onKeypress, Func<bool> cancelled)
    {
        var delay = Stopwatch.StartNew();
        TimeSpan poll = TimeSpan.FromMilliseconds(25);
        while (!cancelled())
        {
            if (onKeypress && Console.KeyAvailable)
            {
                Console.ReadKey(intercept: true);
                return true;
            }
            TimeSpan remaining = interval is { } timeout ? timeout - delay.Elapsed : poll;
            if (remaining <= TimeSpan.Zero) return true;
            Thread.Sleep(remaining < poll ? remaining : poll);
        }
        return false;
    }

    /// <summary>Formats a bounded snapshot when a callback or handler supplied no dashboard lanes.</summary>
    /// <param name="result">Latest cycle result.</param>
    /// <param name="request">Caller delivery limits and projection.</param>
    private string[] WatchPreview(PSObject result, Hashtable request)
    {
        try
        {
            return Deliver(result, Convert.ToInt32(QuietRuntime.Unwrap(request["MaxItems"]), CultureInfo.InvariantCulture),
                Convert.ToInt32(QuietRuntime.Unwrap(request["MaxOutputBytes"]), CultureInfo.InvariantCulture), "off",
                yaml: true, measureDelivery: false).TrimEnd().Split('\n');
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            return ["Watch preview unavailable: " + error.Message];
        }
    }
}
