using System.Collections;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Property, fuzz and contract cases for the compiled invocation runtime (lifecycle, offline guards, text streaming).</summary>
internal static class RuntimeCases
{
    /// <summary>Fixed seed retained so any failing generated value can be replayed deterministically.</summary>
    private const int Seed = 20261111;

    /// <summary>Lifecycle states in their only legal order.</summary>
    private static readonly string[] Order = ["Created", "Running", "Draining", "Completing", "Finalized"];

    /// <summary>Runs every runtime case.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run)
    {
        using Runspace runspace = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault2());
        runspace.Open();

        await run("runtime lifecycle accepts only the next state", () =>
        {
            for (int from = 0; from < Order.Length; from++)
                for (int to = 0; to < Order.Length; to++)
                {
                    var runtime = new QuietRuntime { Lifecycle = Order[from] };
                    bool accepted;
                    try { runtime.Transition(Order[to]); accepted = true; }
                    catch (InvalidOperationException error) { accepted = false; Require(error.Message.StartsWith("InvalidLifecycleTransition", StringComparison.Ordinal), "Unstable lifecycle error"); }
                    Require(accepted == (to == from + 1), $"Transition {Order[from]} -> {Order[to]} accepted={accepted}");
                    Require(runtime.Lifecycle == (accepted ? Order[to] : Order[from]), "Lifecycle changed by a rejected transition");
                }
            return Task.CompletedTask;
        });

        await run("recall compression level accepts exactly the integers 0 to 9", () =>
        {
            for (int level = -50; level <= 50; level++)
                Require(ReadQuietArgumentsCommand.TryParseCompression(level.ToString(System.Globalization.CultureInfo.InvariantCulture), out int parsed) == (level is >= 0 and <= 9)
                    && (level is < 0 or > 9 || parsed == level), $"Compression level {level}");
            var random = new Random(Seed);
            foreach (string text in new[] { "", " ", "1.5", "1e1", "abc", "٣", "10", "-1", "99999999999999999999" })
                Require(!ReadQuietArgumentsCommand.TryParseCompression(text, out _), $"Garbage compression '{text}' accepted");
            for (int i = 0; i < 500; i++)
            {
                string noise = new(Enumerable.Range(0, random.Next(1, 8)).Select(_ => (char)random.Next(32, 127)).ToArray());
                if (!int.TryParse(noise, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out int expected) || expected is < 0 or > 9)
                    Require(!ReadQuietArgumentsCommand.TryParseCompression(noise, out _), $"Noise '{noise}' accepted");
            }
            return Task.CompletedTask;
        });

        await run("runtime of a replay refuses process input and control", () =>
        {
            var runtime = new QuietRuntime { IsRecall = true, NativeStarted = true };
            ExpectCode("ProcessInputUnavailableDuringRecall", () => runtime.WriteBytes([]));
            ExpectCode("ProcessControlUnavailableDuringRecall", () => runtime.Cancel());
            ExpectCode("ProcessControlUnavailableDuringRecall", () => runtime.ReadEvent());
            ExpectCode("NativeSessionNotRunning", () => new QuietRuntime().Cancel());
            return Task.CompletedTask;
        });

        await run("runtime text streaming reassembles records for any block split", () =>
        {
            var random = new Random(Seed);
            string[] alphabet = ["a", "b", "é", "漢", "😀", " ", "x"];
            for (int round = 0; round < 60; round++)
            {
                List<string> words = Enumerable.Range(0, random.Next(0, 8)).Select(_ => string.Concat(Enumerable.Range(0, random.Next(1, 6)).Select(_ => alphabet[random.Next(alphabet.Length)]))).Where(w => w.Trim().Length > 0).ToList();
                bool trailingDelimiter = random.Next(2) == 0;
                byte[] bytes = Encoding.UTF8.GetBytes(string.Concat(words.Select((w, i) => w + (i < words.Count - 1 || trailingDelimiter ? "\n" : ""))));
                var records = new List<string>();
                var runtime = TextRuntime(records);
                Script(runspace, "param($rt,$bytes,$cuts) $start=0; foreach($cut in $cuts){ $null=$rt.StreamBlock('stdout',[byte[]]$bytes[$start..($cut-1)]); $start=$cut }; if($start -lt $bytes.Length){ $null=$rt.StreamBlock('stdout',[byte[]]$bytes[$start..($bytes.Length-1)]) }; $rt.CompleteStreams()",
                    runtime, bytes, Cuts(random, bytes.Length));
                Require(runtime.AnalysisComplete, $"Analysis failed in round {round}: " + string.Join("|", runtime.Errors.Select(e => ((Hashtable)e)["Message"])));
                Require(records.SequenceEqual(words), $"Round {round}: expected [{string.Join("|", words)}] got [{string.Join("|", records)}]");
            }
            return Task.CompletedTask;
        });

        await run("runtime output callback emitting a value fails the analysis once", () =>
        {
            var runtime = TextRuntime(null);
            runtime.Request.Remove("RecordDelimiter");
            runtime.Request["Output"] = ScriptBlock.Create("param($e,$r) 42");
            Script(runspace, "param($rt) $null=$rt.StreamBlock('stdout',[byte[]](104,105)); $null=$rt.StreamBlock('stdout',[byte[]](106))", runtime);
            Require(!runtime.AnalysisComplete && runtime.Errors.Count == 1 && (string)((Hashtable)runtime.Errors[0])["Code"] == "OutputCallbackFailed" && (string)((Hashtable)runtime.Errors[0])["Message"] == "CallbackUnexpectedOutput", "Unexpected callback output was not rejected exactly once");
            return Task.CompletedTask;
        });

        await run("runtime rejects malformed UTF-8 instead of replacing it", () =>
        {
            var runtime = TextRuntime(new List<string>());
            runtime.Request.Remove("RecordDelimiter");
            Script(runspace, "param($rt) $null=$rt.StreamBlock('stdout',[byte[]](255,254)); $rt.CompleteStreams()", runtime);
            Require(!runtime.AnalysisComplete && runtime.Errors.Count > 0, "Malformed bytes were accepted");
            return Task.CompletedTask;
        });
    }

    /// <summary>Builds a text-mode runtime whose output callback appends every record to a list.</summary>
    /// <param name="records">Destination list; may be null when the callback is replaced.</param>
    private static QuietRuntime TextRuntime(List<string>? records)
    {
        var runtime = new QuietRuntime { Data = records };
        runtime.Request["StdoutMode"] = "Text";
        runtime.Request["StderrMode"] = "Text";
        runtime.Request["MaxRecordBytes"] = 1024;
        runtime.Request["RecordDelimiter"] = "\n";
        runtime.Request["Output"] = ScriptBlock.Create("param($e,$r) $r.Data.Add($e.Text)");
        return runtime;
    }

    /// <summary>Generates strictly increasing cut offsets inside the buffer.</summary>
    private static int[] Cuts(Random random, int length) =>
        length < 2 ? [] : Enumerable.Range(0, random.Next(0, 6)).Select(_ => random.Next(1, length)).Distinct().OrderBy(cut => cut).ToArray();

    /// <summary>Runs a script with positional arguments and rethrows the first recorded error.</summary>
    private static void Script(Runspace runspace, string script, params object[] arguments)
    {
        using var shell = PowerShell.Create(runspace);
        shell.AddScript(script);
        foreach (object argument in arguments) shell.AddArgument(argument);
        shell.Invoke();
        if (shell.Streams.Error.Count > 0) throw shell.Streams.Error[0].Exception ?? new InvalidOperationException(shell.Streams.Error[0].ToString());
    }

    /// <summary>Requires the action to fail with a stable code.</summary>
    private static void ExpectCode(string code, Action action)
    {
        try { action(); }
        catch (InvalidOperationException error) when (error.Message == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }

    /// <summary>Throws when an independently known invariant fails.</summary>
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
