using System.Collections;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Property, fuzz and contract cases for the compiled offline replay (Invoke-QuietRecall and the quiet -RecallId route).</summary>
internal static class RecallReplayCases
{
    /// <summary>Fixed seed retained so any failing generated capture can be replayed deterministically.</summary>
    private const int Seed = 52817;

    private static readonly RecallAnalysisSettings BytesSettings = new("Bytes", "Bytes", null, 1024);

    /// <summary>Runspace of the current run; set once by <see cref="RunAsync"/>.</summary>
    private static Runspace Shell = null!;

    /// <summary>Runs every replay case.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="runspace">Runspace exposing the compiled cmdlets under test.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, Runspace runspace)
    {
        Shell = runspace;
        await run("replay conserves every retained byte, event and stream (seeded property)", () =>
        {
            var random = new Random(Seed);
            string[] streams = ["stdout", "stderr", "terminal"];
            for (int round = 0; round < 64; round++)
            {
                var collector = new RecallCollector(new("All", "Head"));
                long total = 0;
                var perStream = streams.ToDictionary(stream => stream, _ => 0L);
                for (int chunk = random.Next(1, 12); chunk > 0; chunk--)
                {
                    string stream = streams[random.Next(streams.Length)];
                    byte[] bytes = new byte[random.Next(1, 40)];
                    random.NextBytes(bytes);
                    collector.Append(stream, bytes);
                    total += bytes.Length;
                    perStream[stream] += bytes.Length;
                }
                RecallCapture capture = collector.Snapshot(true, BytesSettings);
                object result = Replay(runspace, "param($c) Invoke-QuietRecall $c -Data @{stdout=0L;stderr=0L;terminal=0L} -Output {param($e,$r) $r.Data[$e.Stream]+=$e.ByteCount}", capture);
                var data = (IDictionary)QuietRuntime.Unwrap(Member(result, "Data"))!;
                Require(streams.All(stream => Convert.ToInt64(data[stream]) == perStream[stream]), "ReplayStreamBytesLost: seed " + Seed + " round " + round);
                object? cursor = Member(result, "Cursor");
                Require(Convert.ToInt64(Member(cursor!, "Bytes")) == total && total == capture.ReceivedBytes, "ReplayCursorBytes: seed " + Seed + " round " + round);
                Require(Convert.ToInt64(Member(cursor!, "Events")) == capture.Events.Count, "ReplayCursorEvents: seed " + Seed + " round " + round);
                Require((string?)Member(result, "Outcome") == "Success" && Script("param($r) $r.Execution.Kind", result) == "Recall", "ReplayEnvelope");
                Require(Script("param($r) $r.Completeness.Source -and $r.Completeness.Analysis", result) == "True", "ReplayCompleteness");
            }
            return Task.CompletedTask;
        });

        await run("replay refuses partial evidence and missing callbacks, and reports omissions when allowed", () =>
        {
            var collector = new RecallCollector(new("1", "Head"));
            collector.Append("stdout", [1, 2]);
            RecallCapture partial = collector.Snapshot(true, BytesSettings);
            Expect("PartialRecallRequiresAllowPartial", "param($c) $null=Invoke-QuietRecall $c -Output {}", partial);
            Expect("RecallAnalysisCallbackRequired", "param($c) $null=Invoke-QuietRecall $c", Capture(("stdout", [1])));
            object result = Replay(runspace, "param($c) Invoke-QuietRecall $c -AllowPartial -Output {}", partial);
            Require(Script("param($r) $r.Truncation.Applied", result) == "True" && Script("param($r) $r.Truncation.Reasons[0]", result) == "RecallRangesOmitted", "ReplayTruncationMissing");
            Require(Script("param($r) $r.Completeness.Source", result) == "False", "ReplayPartialSourceComplete");
            Require(Script("param($r) $r.Truncation.Applied", Replay(runspace, "param($c) Invoke-QuietRecall $c -Output {}", Capture(("stdout", [1])))) == "False", "ReplayCompleteTruncated");
            return Task.CompletedTask;
        });

        await run("replay resets framing at a gap and exposes the gap to the analysis", () =>
        {
            var collector = new RecallCollector(new("5", "HeadAndTail"));
            collector.Append("stdout", Encoding.UTF8.GetBytes("abXXcd" + (char)0));
            RecallCapture capture = collector.Snapshot(true, new("Text", "Text", ((char)0).ToString(), 100));
            Require(capture.OmittedBytes > 0, "ReplayFixtureHasNoGap");
            object result = Replay(runspace, "param($c) Invoke-QuietRecall $c -AllowPartial -Data ([Collections.Generic.List[string]]::new()) -Output {param($e,$r) if($r.CurrentRecallGap){$r.Data.Add('gap:'+$r.CurrentRecallGap.ByteCount)}}", capture);
            string joined = string.Join("|", ((IEnumerable)QuietRuntime.Unwrap(Member(result, "Data"))!).Cast<object>().Select(item => QuietRuntime.Unwrap(item)));
            Require(joined.Contains("gap:" + capture.OmittedBytes, StringComparison.Ordinal), "ReplayGapNotExposed: " + joined);
            object framed = Replay(runspace, "param($c) Invoke-QuietRecall $c -AllowPartial -Data ([Collections.Generic.List[string]]::new()) -Output {param($e,$r)$r.Data.Add($e.Text)}", capture);
            string records = string.Join("|", ((IEnumerable)QuietRuntime.Unwrap(Member(framed, "Data"))!).Cast<object>().Select(item => QuietRuntime.Unwrap(item)));
            Require(records == "d", "Separated fragments became a fabricated record: " + records);
            // A missing tail must never flush the unterminated fragment as if it were a complete record.
            var head = new RecallCollector(new("6", "Head"));
            head.Append("stdout", Encoding.UTF8.GetBytes("one\ntwo\n"));
            object truncated = Replay(runspace, "param($c) Invoke-QuietRecall $c -AllowPartial -Data ([Collections.Generic.List[string]]::new()) -Output {param($e,$r)$r.Data.Add($e.Text)}", head.Snapshot(true, new("Text", "Text", "\n", 100)));
            string kept = string.Join("|", ((IEnumerable)QuietRuntime.Unwrap(Member(truncated, "Data"))!).Cast<object>().Select(item => QuietRuntime.Unwrap(item)));
            Require(kept == "one", "Unterminated tail fragment was flushed as a record: " + kept);
            return Task.CompletedTask;
        });

        await run("replay overrides modes, delimiter and framing budget independently of the captured settings", () =>
        {
            RecallCapture text = Capture(new RecallAnalysisSettings("Text", "Text", "\n", 100), ("stdout", Encoding.UTF8.GetBytes("one\ntwo\n")));
            string Records(string options) => string.Join("|", ((IEnumerable)QuietRuntime.Unwrap(Member(Replay(runspace, "param($c) Invoke-QuietRecall $c " + options + " -Data ([Collections.Generic.List[string]]::new()) -Output {param($e,$r)$r.Data.Add([string]$e.Text)}", text), "Data"))!).Cast<object>().Select(item => QuietRuntime.Unwrap(item)));
            Require(Records("") == "one|two", "ReplayCapturedDelimiter");
            Require(Records("-RecordDelimiter $null") == "one\ntwo\n", "ReplayDelimiterNotCleared");
            Require(Records("-RecordDelimiter ''") == "one\ntwo\n", "ReplayEmptyDelimiterNotCleared");
            Require(Script("param($c) $r=Invoke-QuietRecall $c -StdoutMode Bytes -Data @{N=0L} -Output {param($e,$r)$r.Data.N+=$e.ByteCount}; $r.Data.N", Capture(("stdout", [1, 2, 3]))) == "3", "ReplayModeOverride");
            object failed = Replay(runspace, "param($c) Invoke-QuietRecall $c -MaxRecordBytes 3 -Output {}", Capture(new RecallAnalysisSettings("Text", "Text", "\n", 100), ("stdout", Encoding.UTF8.GetBytes("aaaaaaaa\n"))));
            Require((string?)Member(failed, "Outcome") == "Failed" && Script("param($r) $r.Error[0].Code", failed) == "DecodeOrFramingFailed", "ReplayFramingBudgetIgnored");
            ExpectBinding("MaxRecordBytes", "param($c) $null=Invoke-QuietRecall $c -MaxRecordBytes 0 -Output {}", Capture(("stdout", [1])));
            ExpectBinding("StdoutMode", "param($c) $null=Invoke-QuietRecall $c -StdoutMode Other -Output {}", Capture(("stdout", [1])));
            return Task.CompletedTask;
        });

        await run("replay forbids native effects and always restores the recall depth", () =>
        {
            RecallCapture capture = Capture(("stdout", [1, 2]));
            object blocked = Replay(runspace, "param($c) Invoke-QuietRecall $c -Output {param($e,$r) $r.WriteText('must not execute')}", capture);
            Require((string?)Member(blocked, "Outcome") == "Failed" && Script("param($r) $r.Error[0].Code + ':' + $r.Error[0].Message", blocked).Contains("ProcessInputUnavailableDuringRecall", StringComparison.Ordinal), "ReplayInputAllowed");
            Require(QuietCallState.RecallDepth == 0, "ReplayDepthLeaked after callback failure");
            object nested = Replay(runspace, "param($c) Invoke-QuietRecall $c -Output {param($e,$r) $null=Invoke-QuietCall @{FilePath='x';ArgumentList=@()}}", capture);
            Require(Script("param($r) $r.Error[0].Message", nested).Contains("NativeExecutionUnavailableDuringRecall", StringComparison.Ordinal), "ReplayNativeAllowed");
            Require(QuietCallState.RecallDepth == 0, "ReplayDepthLeaked after nested call");
            Expect("RecallCaptureRequired", "$null=Invoke-QuietRecall 42 -Output {}");
            Require(QuietCallState.RecallDepth == 0, "ReplayDepthLeaked after rejection");
            return Task.CompletedTask;
        });

        await run("replay reports declared ignored sequences sorted and keeps the projection for delivery", () =>
        {
            RecallCapture capture = Capture(("stdout", [1]), ("stderr", [2]), ("stdout", [3]));
            object ignored = Replay(runspace, "param($c) Invoke-QuietRecall $c -Output {param($e,$r) $r.MarkIgnored()}", capture);
            Require(Script("param($r) ($r.Cursor.DeclaredIgnoredSequences -join ',')", ignored) == "1,2,3", "ReplayIgnoredSequences");
            object projected = Replay(runspace, "param($c) Invoke-QuietRecall $c -Complete {2} -Projection {param($data,$budget)@{Value=$data+7}}", capture);
            string json = Script("param($r) Out-QuietResult $r", projected);
            using var document = System.Text.Json.JsonDocument.Parse(json);
            Require(document.RootElement.GetProperty("Data").GetProperty("Value").GetInt32() == 9, "Replay projection was discarded");
            return Task.CompletedTask;
        });

        await run("saved replay opens durable identities and routes quiet -RecallId offline", async () =>
        {
            string root = Path.Combine(Path.GetTempPath(), "quietcli-replay-" + Guid.NewGuid().ToString("N"));
            try
            {
                var writer = await RecallStore.CreateAsync(root, null, BytesSettings);
                await writer.AppendAsync("stdout", [1, 2, 3]);
                RecallCapture saved = await writer.CompleteAsync(true, new RecallSourceStatus("Success", 0, "Observed"));
                await writer.DisposeAsync();
                object direct = Replay(runspace, "param($i,$r) Invoke-QuietRecall -RecallId $i -RecallRoot $r -Data @{N=0L} -Output {param($e,$x)$x.Data.N+=$e.ByteCount}", saved.RecallId, root);
                Require(Script("param($r) $r.Data.N", direct) == "3" && Script("param($r) $r.Execution.Original.Outcome", direct) == "Success", "ReplayDurableId");
                var request = new Hashtable(StringComparer.OrdinalIgnoreCase)
                {
                    ["RecallId"] = saved.RecallId, ["RecallRoot"] = root, ["AsObject"] = true,
                    ["ReplayOptions"] = new Hashtable(StringComparer.OrdinalIgnoreCase) { ["Complete"] = ScriptBlock.Create("42") },
                };
                object routed = Replay(runspace, "param($q) Invoke-QuietCall $q", request);
                Require(Script("param($r) $r.Data", routed) == "42" && Script("param($r) $null -eq $r.Execution.Native", routed) == "True" &&Script("param($r) $r.Internal.Offline", routed) == "True","Replay did not use the offline route");
                request["AsObject"] = false;
                request["MaxItems"] = 20; request["MaxOutputBytes"] = 4096; request["Tokenizer"] = "off";
                string delivered = Script("param($q) Invoke-QuietCall $q", request);
                using (var document = System.Text.Json.JsonDocument.Parse(delivered)) Require(document.RootElement.GetProperty("Data").GetInt32() == 42, "Replay delivery lost the data");
                Expect("InvalidRecallId", "param($r) $null=Invoke-QuietRecall -RecallId 'not-an-id' -RecallRoot $r -Output {}", root);
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        });

        await run("replay option parsing rejects malformed values with stable codes (fuzz)", () =>
        {
            foreach (object? size in new object?[] { 0, -1, 2147483648L, "x", "1.5", long.MinValue })
                ExpectRejected(new Hashtable { ["MaxRecordBytes"] = size }, "RecallMaxRecordBytesInvalid");
            foreach (string name in new[] { "Output", "Complete", "Projection" }) ExpectRejected(new Hashtable { [name] = "not a block" }, "CallbackMustBeScriptBlock");
            foreach (string name in new[] { "StdoutMode", "StderrMode" }) ExpectRejected(new Hashtable { [name] = "Binary" }, "RecallModeInvalid");
            ExpectRejected(new Hashtable { ["State"] = new object[] { 1 } }, "RecallStateMustBeHashtable");
            RecallReplayOptions parsed = RecallReplayOptions.Parse(new Hashtable { ["StdoutMode"] = "bytes", ["RecordDelimiter"] = null, ["MaxRecordBytes"] = 7L, ["AllowPartial"] = true });
            Require(parsed.StdoutMode == "Bytes" && parsed.RecordDelimiterBound && parsed.RecordDelimiter is null && parsed.MaxRecordBytes == 7 && parsed.AllowPartial, "ReplayOptionsParsed");
            Require(!RecallReplayOptions.Parse(new Hashtable()).RecordDelimiterBound && !RecallReplayOptions.Parse(new Hashtable()).AllowPartial, "ReplayDefaultsBound");
            return Task.CompletedTask;
        });
    }

    /// <summary>Builds a complete capture from (stream, bytes) chunks.</summary>
    private static RecallCapture Capture(params (string Stream, byte[] Bytes)[] chunks) => Capture(BytesSettings, chunks);

    private static RecallCapture Capture(RecallAnalysisSettings settings, params (string Stream, byte[] Bytes)[] chunks)
    {
        var collector = new RecallCollector(new("All", "Head"));
        foreach (var (stream, bytes) in chunks) collector.Append(stream, bytes);
        return collector.Snapshot(true, settings);
    }

    /// <summary>Runs a script and returns its single output object.</summary>
    private static object Replay(Runspace runspace, string script, params object[] arguments) => DeliveryCmdletCases.Script(runspace, script, arguments).Single();

    /// <summary>Runs a script and returns the string form of its single output.</summary>
    private static string Script(string script, params object[] arguments) =>
        Convert.ToString(QuietRuntime.Unwrap(DeliveryCmdletCases.Script(Shell, script, arguments).Single()), System.Globalization.CultureInfo.InvariantCulture) ?? "";

    /// <summary>Requires a parameter binding failure that names the parameter.</summary>
    private static void ExpectBinding(string parameter, string script, params object[] arguments)
    {
        try { DeliveryCmdletCases.Script(Shell, script, arguments); }
        catch (Exception error) when (error.ToString().Contains(parameter, StringComparison.Ordinal)) { return; }
        throw new InvalidOperationException(script + " was accepted although " + parameter + " is invalid");
    }

    /// <summary>Requires a terminating error whose innermost message starts with the code.</summary>
    private static void Expect(string code, string script, params object[] arguments) => DeliveryCmdletCases.Expect(Shell, code, script, arguments);

    private static object Member(object container, string name) => DeliveryCmdletCases.Member(container, name)!;

    private static void ExpectRejected(Hashtable values, string code)
    {
        try { RecallReplayOptions.Parse(values); }
        catch (InvalidOperationException error) when (error.Message.StartsWith(code, StringComparison.Ordinal)) { return; }
        throw new InvalidOperationException("Replay option was accepted instead of " + code);
    }

    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
