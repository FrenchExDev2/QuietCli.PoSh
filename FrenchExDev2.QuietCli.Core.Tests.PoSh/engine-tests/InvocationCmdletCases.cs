using System.Collections;
using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Contract, property and fuzz cases for the compiled invocation lifecycle, driven through a real PowerShell runspace.</summary>
internal static class InvocationCmdletCases
{
    /// <summary>Fixed seed retained so any failing generated value can be replayed deterministically.</summary>
    private const int Seed = 20261112;

    /// <summary>Runs every invocation case; telemetry must already be disabled for the shared configuration snapshot.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="runspace">Runspace exposing the invocation and handler cmdlets.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, Runspace runspace)
    {
        shared = runspace;
        string binary = Path.GetFileNameWithoutExtension(Environment.ProcessPath)!;
        string path = Environment.ProcessPath!;

        await run("invocation of a registered handler returns an immutable finalized local result", () =>
        {
            Register(runspace, "probe-ok", binary, "42");
            try
            {
                var result = Call(runspace, path, "@{}");
                Require(Text(result, "Outcome") == "Success" && Member(result, "Data") is 42, "Handler outcome or data lost");
                Require(Member(result, "ParentId") is null && Text(result, "RootId") == Text(result, "InvocationId"), "Root identity wrong");
                Require(Text(Member(result, "Execution")!, "State") == "Finalized", "Execution snapshot not finalized: " + Dump(result));
                Require((bool)Member(Member(result, "Completeness")!, "Source")! && (bool)Member(Member(result, "Completeness")!, "Analysis")!, "Completeness lost");
                Require(PSObject.AsPSObject(result).TypeNames[0] == "QuietCli2.Result", "Result type name lost");
                foreach (string name in new[] { "Execution", "Completeness" })
                    ExpectFailure(() => DeliveryCmdletCases.Script(runspace, "param($r) $r." + name + " = 1", result), "Final property " + name + " is writable");
                Require(QuietCallState.Depth == 0, "Call stack leaked");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-ok"); }
            return Task.CompletedTask;
        });

        await run("invocation without a handler is unsupported and a missing executable fails with stable diagnostics", () =>
        {
            var unsupported = Call(runspace, path, "@{}");
            Require(Text(unsupported, "Outcome") == "Unsupported" && Text(((IEnumerable)Member(unsupported, "Error")!).Cast<object>().Single(), "Code") == "HandlerNotFound", "Unsupported call mis-reported: " + Dump(unsupported));
            var missing = Call(runspace, Path.Combine(Path.GetTempPath(), "quiet-missing-" + Guid.NewGuid().ToString("N")), "@{}");
            Require(Text(missing, "Outcome") == "Failed" && Text(((IEnumerable)Member(missing, "Error")!).Cast<object>().First(), "Code") == "InvocationFailed", "Missing executable mis-reported");
            Require(!(bool)Member(Member(missing, "Completeness")!, "Analysis")!, "Failed call claimed a complete analysis");
            Require(QuietCallState.Depth == 0, "Call stack leaked after failures");
            return Task.CompletedTask;
        });

        await run("nested invocations inherit identity, context and aggregate children", () =>
        {
            Register(runspace, "probe-inner", binary, "'inner'");
            Register(runspace, "probe-nested", binary, "Invoke-QuietCall @{FilePath=$rt.Request['FilePath'];Environment=@{};AsObject=$true;HandlerId='probe-inner'}");
            try
            {
                var outer = Call(runspace, path, "@{Context='ctx';HandlerId='probe-nested'}");
                var inner = Member(outer, "Data");
                Require(Text(outer, "Outcome") == "Success" && inner is not null, "Outer outcome wrong: " + Dump(outer));
                Require(Text(inner, "ParentId") == Text(outer, "InvocationId") && Text(inner, "RootId") == Text(outer, "RootId") && Text(inner, "Context") == "ctx", $"Nested identity not inherited: parent={Text(inner, "ParentId")}/{Text(outer, "InvocationId")} root={Text(inner, "RootId")}/{Text(outer, "RootId")} ctx={Text(inner, "Context")}");
                Require(Text(inner, "Outcome") == "Success" && Member(inner, "Data") as string == "inner", "Child outcome lost: " + Dump(inner!));
                Require(Convert.ToInt32(Member(Member(outer, "Execution"), "Children")) == 1, "Child not aggregated");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-nested; Unregister-QuietHandler probe-inner"); }
            return Task.CompletedTask;
        });

        await run("data and state factories run once per call and must return exactly one value", () =>
        {
            Register(runspace, "probe-factory", binary, "$rt.Data");
            try
            {
                var random = new Random(Seed);
                var seen = new HashSet<object>(ReferenceEqualityComparer.Instance);
                for (int round = 0; round < 25; round++)
                {
                    int size = random.Next(0, 4);
                    var result = Call(runspace, path, $"@{{DataFactory={{,(@(1..{size}) | % {{ $_ }})}}}}");
                    var data = Member(result, "Data");
                    Require(data is not null && seen.Add(data), "Factory value was shared between calls");
                }
                foreach (string bad in new[] { "@{DataFactory={}}", "@{DataFactory={1;2}}", "@{StateFactory={1}}", "@{StateFactory={@{};@{}}}" })
                    ExpectFailure(() => Call(runspace, path, bad), "Invalid factory accepted: " + bad);
                Require(QuietCallState.Depth == 0, "Call stack leaked after factory failures");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-factory"); }
            return Task.CompletedTask;
        });

        await run("invocation rejects an input path redirected through a linked ancestor", () =>
        {
            string link = Path.Combine(Path.GetTempPath(), "quiet-input-link-" + Guid.NewGuid().ToString("N"));
            string real = Path.Combine(Path.GetTempPath(), "quiet-input-real-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(real);
            File.WriteAllText(Path.Combine(real, "input.txt"), "x");
            try
            {
                if (!TryLink(link, real)) return Task.CompletedTask; // platform or privileges forbid linking; nothing to verify here
                string throughLink = Path.Combine(link, "input.txt");
                // The guard runs before the native process starts; -Output/-Complete are never invoked.
                // Supply the facade's complete native request, including working directory and terminal defaults.
                var result = DeliveryCmdletCases.Script(runspace,
                    "param($path,$inputPath) $o = Read-QuietArguments -Arguments @('-AsObject','-InputPath',$inputPath,'-Output',{},'-Complete',{},$path); Invoke-QuietCall $o",
                    path, throughLink).Single();
                string message = Text(((IEnumerable)Member(result, "Error")!).Cast<object>().First(), "Message");
                Require(Text(result, "Outcome") == "Failed" && message.Contains("QuietInputPathLinkRejected"), "Linked InputPath was not rejected: " + Dump(result));
            }
            finally
            {
                try { Directory.Delete(link, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                try { Directory.Delete(real, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
            return Task.CompletedTask;
        });

        await run("Emit distributes to every listener in registration order and CollectEvents explicitly records emitted values independently from listeners", () =>
        {
            Register(runspace, "probe-emit-order", binary, "$rt.Emit('a'); $rt.Emit('b'); $rt.Emit('c'); 'ok'");
            var order = new List<string>();
            runspace.SessionStateProxy.SetVariable("quietEmitOrder", order);
            try
            {
                var result = Call(runspace, path, "@{HandlerId='probe-emit-order';CollectEvents=$true;Listeners=@({param($e,$rt) $global:quietEmitOrder.Add('L1:'+$e)},{param($e,$rt) $global:quietEmitOrder.Add('L2:'+$e)})}");
                Require(Text(result, "Outcome") == "Success", "Emit with listeners changed Outcome: " + Dump(result));
                string[] events = ((IEnumerable)Member(result, "Events")!).Cast<object?>().Select(e => Convert.ToString(e)!).ToArray();
                Require(events.SequenceEqual(["a", "b", "c"]), "Events did not record every emitted value in order: " + string.Join(",", events));
                Require(order.SequenceEqual(["L1:a", "L2:a", "L1:b", "L2:b", "L1:c", "L2:c"]), "Listener distribution order wrong: " + string.Join(",", order));
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-emit-order; $global:quietEmitOrder=$null"); }
            return Task.CompletedTask;
        });

        await run("property: Emit retains nothing and omits Events unless this call explicitly enables collection", () =>
        {
            var random = new Random(Seed);
            for (int round = 0; round < 32; round++)
            {
                int count = random.Next(0, 20);
                Register(runspace, "probe-emit-opt-in", binary, $"for($i=0;$i -lt {count};$i++){{$rt.Emit($i)}}; $rt.Events.Count");
                try
                {
                    foreach (bool collect in new[] { false, true })
                    {
                        var result = Call(runspace, path, "@{HandlerId='probe-emit-opt-in';CollectEvents=$" + collect.ToString().ToLowerInvariant() + "}");
                        Require(Convert.ToInt32(Member(result, "Data")) == (collect ? count : 0), "Unrequested event history retained");
                        Require((PSObject.AsPSObject(result).Properties["Events"] is not null) == collect, "Events field presence is not opt-in");
                    }
                    var ordinary = Call(runspace, path, "@{HandlerId='probe-emit-opt-in'}");
                    Require(Convert.ToInt32(Member(ordinary, "Data")) == 0 && PSObject.AsPSObject(ordinary).Properties["Events"] is null, "Omitted switch enabled collection");
                }
                finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-emit-opt-in"); }
            }
            return Task.CompletedTask;
        });

        await run("a throwing listener is disabled after its first failure, without affecting other listeners, the Outcome or AnalysisComplete", () =>
        {
            Register(runspace, "probe-emit-fail", binary, "$rt.Emit('a'); $rt.Emit('b'); $rt.Emit('c'); 'ok'");
            var survivorCalls = new List<string>();
            runspace.SessionStateProxy.SetVariable("quietEmitSurvivor", survivorCalls);
            try
            {
                var result = Call(runspace, path, "@{HandlerId='probe-emit-fail';Listeners=@({param($e,$rt) throw 'boom'},{param($e,$rt) $global:quietEmitSurvivor.Add($e)})}");
                Require(Text(result, "Outcome") == "Success", "A listener failure changed Outcome: " + Dump(result));
                Require((bool)Member(Member(result, "Completeness")!, "Analysis")!, "A listener failure marked the analysis incomplete: " + Dump(result));
                Require(survivorCalls.Count == 3, "Surviving listener was not called for every emitted event: " + survivorCalls.Count);
                var errors = ((IEnumerable)Member(result, "Error")!).Cast<object>().ToArray();
                Require(errors.Length == 1 && Text(errors[0], "Code") == "ListenerFailed", "Failing listener was retried after its first failure, or its failure was lost: " + Dump(result));
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-emit-fail; $global:quietEmitSurvivor=$null"); }
            return Task.CompletedTask;
        });

        await run("-Listeners accepts a lone ScriptBlock or a sequence of ScriptBlocks and rejects every other generated shape", () =>
        {
            Register(runspace, "probe-emit-shape", binary, "$rt.Emit('x'); 'ok'");
            try
            {
                var lone = Call(runspace, path, "@{HandlerId='probe-emit-shape';Listeners={param($e,$rt) $null}}");
                Require(Text(lone, "Outcome") == "Success", "A lone ScriptBlock listener was rejected: " + Dump(lone));
                var array = Call(runspace, path, "@{HandlerId='probe-emit-shape';Listeners=@({param($e,$rt) $null},{param($e,$rt) $null})}");
                Require(Text(array, "Outcome") == "Success", "An array of ScriptBlock listeners was rejected: " + Dump(array));
                var random = new Random(Seed);
                for (int round = 0; round < 20; round++)
                {
                    var items = new List<string>();
                    for (int i = 0; i < random.Next(0, 3); i++) items.Add("{param($e,$rt) $null}");
                    for (int i = 0; i < random.Next(1, 3); i++)
                        items.Add(random.Next(0, 3) switch { 0 => random.Next(-1000, 1000).ToString(), 1 => "'invalid-" + round + "-" + i + "'", _ => "@{}" });
                    for (int i = items.Count - 1; i > 0; i--) { int j = random.Next(0, i + 1); (items[i], items[j]) = (items[j], items[i]); }
                    string listeners = "Listeners=@(" + string.Join(",", items) + ")";
                    ExpectFailure(() => Call(runspace, path, "@{HandlerId='probe-emit-shape';" + listeners + "}"), "Invalid -Listeners shape accepted at round " + round + ": " + listeners);
                }
                Require(QuietCallState.Depth == 0, "Call stack leaked after -Listeners rejections");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-emit-shape"); }
            return Task.CompletedTask;
        });

        await run("a nested invocation does not inherit the parent's -Listeners unless explicitly re-passed", () =>
        {
            Register(runspace, "probe-emit-inner", binary, "$rt.Emit('inner'); 'okInner'");
            Register(runspace, "probe-emit-outer", binary, "$rt.Emit('outer'); Invoke-QuietCall @{FilePath=$rt.Request['FilePath'];Environment=@{};AsObject=$true;HandlerId='probe-emit-inner'}");
            var outerHits = new List<string>();
            runspace.SessionStateProxy.SetVariable("quietEmitOuterHits", outerHits);
            try
            {
                var outer = Call(runspace, path, "@{HandlerId='probe-emit-outer';Listeners={param($e,$rt) $global:quietEmitOuterHits.Add($e)}}");
                var inner = Member(outer, "Data");
                Require(Text(outer, "Outcome") == "Success" && inner is not null, "Outer invocation with a nested call failed: " + Dump(outer));
                Require(PSObject.AsPSObject(outer).Properties["Events"] is null && PSObject.AsPSObject(inner!).Properties["Events"] is null, "Nested calls collected events without opting in");
                Require(outerHits.SequenceEqual(["outer"]), "The nested call's Emit reached the parent's listener although -Listeners was not re-passed: " + string.Join(",", outerHits));
                Register(runspace, "probe-emit-outer-forwarded", binary, "$rt.Emit('outer'); Invoke-QuietCall @{FilePath=$rt.Request['FilePath'];Environment=@{};AsObject=$true;HandlerId='probe-emit-inner';Listeners=$rt.Listeners}");
                outerHits.Clear();
                var forwarded = Call(runspace, path, "@{HandlerId='probe-emit-outer-forwarded';Listeners={param($e,$rt) $global:quietEmitOuterHits.Add($e)}}");
                Require(Text(forwarded, "Outcome") == "Success" && outerHits.SequenceEqual(["outer", "inner"]), "Explicitly forwarded listeners were not attached to the nested call");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-emit-outer; Unregister-QuietHandler probe-emit-outer-forwarded; Unregister-QuietHandler probe-emit-inner; $global:quietEmitOuterHits=$null"); }
            return Task.CompletedTask;
        });

        await run("property: every listener is called exactly once per emitted event, for generated emit and listener counts, with an independently generated expectation", () =>
        {
            var random = new Random(Seed);
            for (int round = 0; round < 25; round++)
            {
                int emitCount = random.Next(1, 7);
                int listenerCount = random.Next(1, 4);
                string id = "probe-emit-property-" + round;
                string execute = string.Join("; ", Enumerable.Range(0, emitCount).Select(i => $"$rt.Emit({i})")) + "; 'ok'";
                Register(runspace, id, binary, execute);
                var counts = new int[listenerCount];
                runspace.SessionStateProxy.SetVariable("quietEmitCounts", counts);
                try
                {
                    string listeners = string.Join(",", Enumerable.Range(0, listenerCount).Select(j => $"{{param($e,$rt) $global:quietEmitCounts[{j}]++}}"));
                    var result = Call(runspace, path, $"@{{HandlerId='{id}';CollectEvents=$true;Listeners=@({listeners})}}");
                    Require(Text(result, "Outcome") == "Success", $"Round {round}: Outcome changed: " + Dump(result));
                    int observedEvents = ((IEnumerable)Member(result, "Events")!).Cast<object?>().Count();
                    Require(observedEvents == emitCount, $"Round {round}: Events count {observedEvents} != generated {emitCount}");
                    for (int j = 0; j < listenerCount; j++)
                        Require(counts[j] == emitCount, $"Round {round}: listener {j} was called {counts[j]} times, expected {emitCount}");
                }
                finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler " + id + "; $global:quietEmitCounts=$null"); }
            }
            return Task.CompletedTask;
        });

        await run("property: generated observer failures disable only that observer at its first failing event", () =>
        {
            var random = new Random(Seed);
            for (int round = 0; round < 40; round++)
            {
                int emitCount = random.Next(1, 8), listenerCount = random.Next(1, 5);
                int[] failureAt = Enumerable.Range(0, listenerCount).Select(_ => random.Next(0, emitCount + 1)).ToArray();
                int[] calls = new int[listenerCount];
                runspace.SessionStateProxy.SetVariable("quietFailureCounts", calls);
                string id = "probe-emit-failure-property";
                Register(runspace, id, binary, string.Join(";", Enumerable.Range(0, emitCount).Select(i => $"$rt.Emit({i})")) + ";'ok'");
                try
                {
                    string listeners = string.Join(",", Enumerable.Range(0, listenerCount).Select(i => $"{{param($e,$rt) $global:quietFailureCounts[{i}]++; if($e -eq {failureAt[i]}){{throw 'generated'}}}}"));
                    var result = Call(runspace, path, $"@{{HandlerId='{id}';CollectEvents=$true;Listeners=@({listeners})}}");
                    Require(Text(result, "Outcome") == "Success" && (bool)Member(Member(result, "Completeness"), "Analysis")!, $"Round {round}: an observer changed analysis");
                    for (int i = 0; i < listenerCount; i++) Require(calls[i] == Math.Min(emitCount, failureAt[i] + 1), $"Seed {Seed}, round {round}, listener {i}: failure boundary changed");
                    Require(((IEnumerable)Member(result, "Error")!).Cast<object>().Count() == failureAt.Count(at => at < emitCount), $"Round {round}: observer errors were duplicated/lost");
                }
                finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler " + id + "; $global:quietFailureCounts=$null"); }
            }
            return Task.CompletedTask;
        });

        await run("splat value options keep their arrays, dictionaries and callbacks without switch coercion", () =>
        {
            var random = new Random(Seed);
            for (int round = 0; round < 30; round++)
            {
                runspace.SessionStateProxy.SetVariable("quietSplatPath", path);
                runspace.SessionStateProxy.SetVariable("quietSplatCount", random.Next(0, 6));
                var observed = DeliveryCmdletCases.Script(runspace, "function Test-SplatArguments { $r=Read-QuietArguments $args; if($r.Listeners.Count -ne 2 -or $r.Listeners[0] -isnot [scriptblock] -or $r.Data.Value -ne 42 -or $r.ArgumentList.Count -ne $global:quietSplatCount -or $r.FilePath -cne $global:quietSplatPath -or $r.Complete -isnot [scriptblock] -or !$r.AsObject){throw 'SplatValuesCoerced'} }; $o=@{Listeners=@({param($e,$r)},{param($e,$r)});Data=@{Value=42};Complete={param($r)$r.Data};ArgumentList=@(for($i=0;$i -lt $global:quietSplatCount;$i++){'item-'+$i});FilePath=$global:quietSplatPath;AsObject=$true}; Test-SplatArguments @o");
                Require(observed.Count == 0, $"Round {round}: argument parsing emitted incidental output");
            }
            return Task.CompletedTask;
        });

        await run("event delivery applies item budgets without altering the local event sequence", () =>
        {
            Register(runspace, "probe-emit-delivery", binary, "$rt.Emit('a'); $rt.Emit('b'); $rt.Emit('c'); 'ok'");
            try
            {
                var result = Call(runspace, path, "@{HandlerId='probe-emit-delivery';CollectEvents=$true}");
                runspace.SessionStateProxy.SetVariable("quietEventDelivery", result);
                string json = Convert.ToString(DeliveryCmdletCases.Script(runspace, "ConvertTo-QuietJson $quietEventDelivery -MaxItems 2 -MaxOutputBytes 16384 -Tokenizer off").Single())!;
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                var events = doc.RootElement.GetProperty("Events");
                Require(events.GetArrayLength() == 2 && events[0].GetString() == "a" && events[1].GetString() == "b", "Delivered event prefix changed: " + json);
                Require(doc.RootElement.GetProperty("Truncation").GetProperty("Applied").GetBoolean(), "Event omissions were hidden");
                Require(((IEnumerable)Member(result, "Events")!).Cast<object>().Count() == 3, "Delivery mutated the local events");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-emit-delivery; $global:quietEventDelivery=$null"); }
            return Task.CompletedTask;
        });

        await run("-MaxLines without -UI and a non-positive -MaxLines are both rejected before any Ui surface is constructed", () =>
        {
            ExpectFailure(() => DeliveryCmdletCases.Script(runspace, "param($path) $o=Read-QuietArguments @('-AsObject','-MaxLines',3,$path); Invoke-QuietCall $o", path), "-MaxLines without -UI was accepted");
            foreach (int bad in new[] { 0, -1, -1000 })
                ExpectFailure(() => DeliveryCmdletCases.Script(runspace, "param($path,$depth) $o=Read-QuietArguments @('-AsObject','-UI','-MaxLines',$depth,$path); Invoke-QuietCall $o", path, bad), "Non-positive -MaxLines " + bad + " was accepted");
            Require(QuietCallState.Depth == 0, "Call stack leaked after -MaxLines rejections");
            return Task.CompletedTask;
        });
    }

    /// <summary>Creates a directory link, returning false when the platform or privileges forbid it.</summary>
    /// <param name="link">Path of the link to create.</param>
    /// <param name="target">Existing directory the link points to.</param>
    private static bool TryLink(string link, string target)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                using Process? process = Process.Start(new ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{target}\"") { CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
                process?.WaitForExit();
                return Directory.Exists(link);
            }
            Directory.CreateSymbolicLink(link, target);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException) { return false; }
    }

    /// <summary>Registers an inert handler whose Execute script block receives the runtime as $rt.</summary>
    private static void Register(Runspace runspace, string id, string binary, string execute) =>
        DeliveryCmdletCases.Script(runspace, $"Register-QuietHandler '{id}' @{{Binary='{binary}';VersionRange='*';TestVersion={{param($v) $true}};Probe={{'1.0'}};Execute={{param($rt) {execute}}}}}");

    /// <summary>Invokes the compiled call with an options hashtable merged over the required defaults.</summary>
    private static object Call(Runspace runspace, string filePath, string options) =>
        DeliveryCmdletCases.Script(runspace, "param($path) $o = " + options + "; $o.FilePath = $path; if(!$o.ContainsKey('Environment')){$o.Environment=@{}}; if(!$o.ContainsKey('AsObject')){$o.AsObject=$true}; Invoke-QuietCall $o", filePath).Single();

    private static Runspace? shared;

    private static string Dump(object result)
    {
        var errors = Member(result, "Error") is IEnumerable list ? string.Join(";", list.Cast<object>().Select(e => Text(e, "Code") + ":" + Text(e, "Message"))) : "";
        var execution = Member(result, "Execution");
        return $"Outcome={Text(result, "Outcome")} Data={Text(result, "Data")} Errors=[{errors}] Execution={(execution is null ? "null" : Text(execution, "State"))}";
    }

    /// <summary>Unwraps scalars but keeps property-bearing objects (results, snapshots) intact.</summary>
    private static object? Plain(object? value) => value is PSObject { BaseObject: PSCustomObject } ? value : QuietRuntime.Unwrap(value);

    private static object? Member(object? container, string name)
    {
        if (container is null) return null;
        object baseObject = container is PSObject wrapped ? wrapped.BaseObject : container;
        if (baseObject is IDictionary dictionary) return Plain(dictionary.Contains(name) ? dictionary[name] : null);
        return Plain(PSObject.AsPSObject(container).Properties[name]?.Value ?? PropertyReader.Get(container, name));
    }

    private static string Text(object? container, string name) => Convert.ToString(Member(container, name), System.Globalization.CultureInfo.InvariantCulture) ?? "";

    private static void ExpectFailure(Action action, string message)
    {
        try { action(); }
        catch (Exception) { return; }
        throw new InvalidOperationException(message);
    }

    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
