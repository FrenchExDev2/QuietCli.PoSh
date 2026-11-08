using System.Collections.Specialized;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Property, fuzz and contract cases for the compiled gain report and privacy repair cmdlets.</summary>
internal static class GainCmdletCases
{
    /// <summary>Fixed seed retained so any failing generated value can be replayed deterministically.</summary>
    private const int Seed = 68131;

    /// <summary>Fake engine: records every request in $GainLog and answers from the $Plan queue.</summary>
    private const string FakeEngine = "$global:GainLog=[Collections.Generic.List[object]]::new();"
        + "function global:Send-QuietRequest { param($Request) $GainLog.Add($Request.Clone()); $r=$Plan.Dequeue(); [pscustomobject]@{Header=[pscustomobject]@{Data=$r};Payload=[byte[]]@()} }";

    /// <summary>Runs every gain cmdlet case.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="runspace">Runspace that registers the compiled cmdlets.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, Runspace runspace)
    {
        DeliveryCmdletCases.Script(runspace, FakeEngine);
        try
        {
            await run("gain time window: From wins over Days, Days ends at To or now (generated)", () =>
            {
                var random = new Random(Seed);
                DateTimeOffset now = new(2026, 11, 6, 12, 0, 0, TimeSpan.Zero);
                for (int round = 0; round < 200; round++)
                {
                    int? days = random.Next(3) == 0 ? null : random.Next(1, 4000);
                    DateTimeOffset? start = random.Next(3) == 0 ? now.AddMinutes(-random.Next(1, 100000)) : null;
                    DateTimeOffset? end = random.Next(2) == 0 ? now.AddMinutes(-random.Next(0, 100000)) : null;
                    var (low, high) = GetQuietCliGainCommand.Window(days, start, end, now);
                    DateTimeOffset? expectedLow = start ?? (days is { } d ? (end ?? now) - TimeSpan.FromDays(d) : (DateTimeOffset?)null);
                    DateTimeOffset? expectedHigh = start is null && days is not null ? end ?? now : end;
                    Require(low == expectedLow && high == expectedHigh, $"Window wrong for days={days} start={start} end={end}");
                }
                return Task.CompletedTask;
            });

            await run("gain paginates every group page in order and never releases a completed report (generated)", () =>
            {
                var random = new Random(Seed + 1);
                for (int round = 0; round < 64; round++)
                {
                    int pages = random.Next(1, 6), polls = random.Next(0, 3), counter = 0;
                    var plan = new Queue<object>();
                    for (int poll = 0; poll < polls; poll++) plan.Enqueue(Obj(("Pending", true), ("ReportId", "rid")));
                    for (int page = 0; page < pages; page++)
                    {
                        object[] groups = Enumerable.Range(0, random.Next(0, 5)).Select(_ => (object)Obj(("Name", "g" + counter++))).ToArray();
                        plan.Enqueue(Obj(("Report", page == 0 ? Obj(("Invocations", 7), ("Complete", true)) : null), ("Groups", groups), ("GroupsComplete", page == pages - 1), ("ReportId", "rid"), ("After", page)));
                    }
                    Reset(runspace, plan);
                    var report = DeliveryCmdletCases.Script(runspace, "Get-QuietCliGain -AsObject").Single();
                    object[] names = ((IEnumerable<object>)DeliveryCmdletCases.Member(report, "Groups")!).ToArray();
                    Require(names.Length == counter, $"Round {round}: {names.Length} groups for {counter} produced");
                    for (int index = 0; index < names.Length; index++) Require((string)DeliveryCmdletCases.Member(names[index], "Name")! == "g" + index, "Group order changed");
                    Require(Convert.ToInt32(DeliveryCmdletCases.Member(report, "Invocations")) == 7, "Report of the first page lost");
                    string expected = "gain" + string.Concat(Enumerable.Repeat(",gain-poll", polls)) + string.Concat(Enumerable.Repeat(",gain-next", pages - 1));
                    Require(Actions(runspace) == expected, $"Request sequence {Actions(runspace)} differs from {expected}");
                }
                return Task.CompletedTask;
            });

            await run("gain releases an unfinished report once and rejects missing cursors", () =>
            {
                // A pending reply without an identity is rejected before any release.
                Reset(runspace, new Queue<object>([Obj(("Pending", true))]));
                DeliveryCmdletCases.Expect(runspace, "MeasurementPaginationMissingCursor", "Get-QuietCliGain");
                Require(Actions(runspace) == "gain", "Pending reply without identity triggered a release");
                // An incomplete page without a continuation keeps the identity learned from the poll, which is then released.
                Reset(runspace, new Queue<object>([Obj(("Pending", true), ("ReportId", "rid")), Obj(("Report", Obj(("Invocations", 1))), ("Groups", Array.Empty<object>()), ("GroupsComplete", false), ("ReportId", "rid"))]));
                DeliveryCmdletCases.Expect(runspace, "MeasurementPaginationMissingCursor", "Get-QuietCliGain");
                Require(Actions(runspace) == "gain,gain-poll,gain-release", "Unfinished report was not released: " + Actions(runspace));
                // A failing exchange mid-pagination still releases the learned identity, and the release failure is swallowed.
                Reset(runspace, new Queue<object>([Obj(("Report", Obj(("Invocations", 1))), ("Groups", Array.Empty<object>()), ("GroupsComplete", false), ("ReportId", "rid"), ("After", 0))]));
                try { DeliveryCmdletCases.Script(runspace, "Get-QuietCliGain"); throw new InvalidOperationException("Exhausted engine did not fail"); }
                catch (InvalidOperationException error) when (error.Message == "Exhausted engine did not fail") { throw; }
                catch (Exception) { }
                Require(Actions(runspace) == "gain,gain-next,gain-release" && (string)DeliveryCmdletCases.Script(runspace, "$GainLog[2].ReportId").Single().BaseObject == "rid", "Failure did not release the report: " + Actions(runspace));
                return Task.CompletedTask;
            });

            await run("gain sends closed query fields: unbounded constants, optional filters and Days arithmetic", () =>
            {
                var random = new Random(Seed + 2);
                Reset(runspace, OnePage());
                DeliveryCmdletCases.Script(runspace, "$null=Get-QuietCliGain");
                Require(Query(runspace, "From") == "-62135596800000" && Query(runspace, "To") == "253402300799999", "Unbounded time constants changed");
                Require(Query(runspace, "Generic") == "False" && Query(runspace, "GroupBy") == "Context", "Default Generic/GroupBy changed");
                Require(Query(runspace, "MaxEvents") == Convert.ToString(DeliveryCmdletCases.Script(runspace, "Get-QuietSetting 'gain.maxEvents'").Single().BaseObject), "Default MaxEvents differs from the setting");
                Require(Query(runspace, "$GainLog[0].ContainsKey('Context')") == "False" && Query(runspace, "$GainLog[0].ContainsKey('SessionId')") == "False" && Query(runspace, "$GainLog[0].ContainsKey('ModuleId')") == "False", "Absent filters were sent");
                Reset(runspace, OnePage());
                DeliveryCmdletCases.Script(runspace, "$null=Get-QuietCliGain -C 'é' -SessionId '' -ModuleId 'm' -GroupBy Role -MaxEvents 5");
                Require(Query(runspace, "Context") == "é" && Query(runspace, "Generic") == "False" && Query(runspace, "ModuleId") == "m" && Query(runspace, "GroupBy") == "Role" && Query(runspace, "MaxEvents") == "5", "Filters were not forwarded");
                Require(Query(runspace, "$GainLog[0].ContainsKey('SessionId')") == "False", "Empty SessionId was sent");
                Reset(runspace, OnePage());
                DeliveryCmdletCases.Script(runspace, "$null=Get-QuietCliGain -Generic");
                Require(Query(runspace, "Generic") == "True" && Query(runspace, "$GainLog[0].ContainsKey('Context')") == "False", "Generic selection not forwarded");
                for (int round = 0; round < 40; round++)
                {
                    int days = random.Next(1, 400);
                    long toMilliseconds = 1_700_000_000_000L + random.NextInt64(0, 100_000_000_000L);
                    DateTimeOffset to = DateTimeOffset.FromUnixTimeMilliseconds(toMilliseconds);
                    Reset(runspace, OnePage());
                    var report = DeliveryCmdletCases.Script(runspace, "param($to,$days) Get-QuietCliGain -Days $days -To $to", to, days).Single();
                    Require(Query(runspace, "To") == toMilliseconds.ToString() && Query(runspace, "From") == (toMilliseconds - days * 86_400_000L).ToString(), $"Days={days} To={toMilliseconds} produced the wrong window");
                    Require((DateTimeOffset)DeliveryCmdletCases.Member(report, "To")! == to && (DateTimeOffset)DeliveryCmdletCases.Member(report, "From")! == to.AddDays(-days), "Report window differs from the request");
                }
                return Task.CompletedTask;
            });

            await run("gain rejects exclusive options and empty windows before any request", () =>
            {
                Reset(runspace, OnePage());
                DeliveryCmdletCases.Expect(runspace, "OutputFormatsAreExclusive", "Get-QuietCliGain -AsJson -AsYaml");
                DeliveryCmdletCases.Expect(runspace, "OutputFormatsAreExclusive", "Get-QuietCliGain -AsObject -AsJson");
                DeliveryCmdletCases.Expect(runspace, "OutputFormatsAreExclusive", "Get-QuietCliGain -AsObject -AsYaml");
                DeliveryCmdletCases.Expect(runspace, "CompressRequiresAsJson", "Get-QuietCliGain -Compress");
                DeliveryCmdletCases.Expect(runspace, "CompressRequiresAsJson", "Get-QuietCliGain -AsYaml -Compress");
                DeliveryCmdletCases.Expect(runspace, "CompressRequiresAsJson", "Get-QuietCliGain -Compress:$false");
                DeliveryCmdletCases.Expect(runspace, "ContextAndGenericAreExclusive", "Get-QuietCliGain -Generic -Context x");
                var now = DateTimeOffset.UtcNow;
                DeliveryCmdletCases.Expect(runspace, "InvalidTimeRange", "param($a,$b) Get-QuietCliGain -From $a -To $b", now, now.AddMinutes(-1));
                DeliveryCmdletCases.Expect(runspace, "InvalidTimeRange", "param($a) Get-QuietCliGain -From $a -To $a", now);
                foreach (string invalid in new[] { "-Days 0", "-Days 3650001", "-MaxEvents 0", "-MaxEvents 1000001", "-GroupBy Nothing" })
                {
                    try { DeliveryCmdletCases.Script(runspace, "Get-QuietCliGain " + invalid); }
                    catch (Exception error) when (error.Message.Contains(invalid.Split(' ')[0].TrimStart('-'), StringComparison.Ordinal)) { continue; }
                    throw new InvalidOperationException(invalid + " was accepted");
                }
                Require(Actions(runspace) == "", "Invalid options reached the engine: " + Actions(runspace));
                return Task.CompletedTask;
            });

            await run("gain report is a PSCustomObject and renders compact, indented JSON and YAML without recording", () =>
            {
                Reset(runspace, OnePage());
                var report = DeliveryCmdletCases.Script(runspace, "Get-QuietCliGain").Single();
                Require(report.BaseObject is PSCustomObject, "Default output is not a PSCustomObject");
                string[] names = report.Properties.Select(property => property.Name).ToArray();
                Require(names.SequenceEqual(["Invocations", "Complete", "From", "To", "Groups"]), "Report members differ: " + string.Join(",", names));
                Require(DeliveryCmdletCases.Member(report, "From") is null && DeliveryCmdletCases.Member(report, "To") is null, "Unbounded window exposed a boundary");
                // JSON output delegates to ConvertTo-Json, which this minimal runspace lacks; Gain.Output.Tests.ps1 covers it in the real module.
                Reset(runspace, OnePage());
                string yaml = (string)DeliveryCmdletCases.Script(runspace, "param($from) Get-QuietCliGain -AsYaml -From $from", DateTimeOffset.Parse("2026-01-02T03:04:05Z")).Single().BaseObject;
                Require(yaml.Contains("\"Invocations\": 7") && yaml.Contains("\"Groups\":") && yaml.Contains("2026-01-02T03:04:05") && !yaml.TrimStart().StartsWith('{'), "YAML report shape changed: " + yaml.Replace("\n", "\\n"));
                Require(Actions(runspace) == "gain", "Formatting a report sent extra requests");
                return Task.CompletedTask;
            });

            await run("gain YAML graph normalizes nested objects and arrays like an independent serializer (fuzz)", () =>
            {
                var random = new Random(Seed + 3);
                for (int round = 0; round < 200; round++)
                {
                    (object? input, string json) = Generate(random, 4);
                    object? graph = GetQuietCliGainCommand.YamlGraph(input);
                    Require(JsonText.Compress(graph, 20) == json, $"Round {round}: graph JSON {JsonText.Compress(graph, 20)} differs from {json}");
                    Require(!ContainsCustomObject(graph), "A custom object survived normalization");
                }
                object?[] nested = (object?[])GetQuietCliGainCommand.YamlGraph(new object[] { Obj(("a", 1)) })!;
                Require(nested[0] is OrderedDictionary, "Array element was not normalized to a mapping");
                return Task.CompletedTask;
            });

            await run("privacy repair honors -WhatIf and sends a confirmed scrub otherwise", () =>
            {
                Reset(runspace, new Queue<object>([Obj(("Scrubbed", 3))]));
                DeliveryCmdletCases.Script(runspace, "Repair-QuietCliMeasurementPrivacy -WhatIf");
                Require(Actions(runspace) == "", "-WhatIf reached the engine");
                var result = DeliveryCmdletCases.Script(runspace, "Repair-QuietCliMeasurementPrivacy -Confirm:$false").Single();
                Require(Actions(runspace) == "scrub" && Query(runspace, "Confirmed") == "True", "Scrub request wrong: " + Actions(runspace));
                Require(Convert.ToInt32(DeliveryCmdletCases.Member(result, "Scrubbed")) == 3, "Scrub reply was not returned");
                return Task.CompletedTask;
            });
        }
        finally { runspace.SessionStateProxy.InvokeProvider.Item.Remove("function:Send-QuietRequest", false); }
    }

    /// <summary>Resets the request log and installs the scripted replies.</summary>
    private static void Reset(Runspace runspace, Queue<object> plan)
    {
        runspace.SessionStateProxy.SetVariable("Plan", plan);
        DeliveryCmdletCases.Script(runspace, "$GainLog.Clear()");
    }

    /// <summary>A complete single-page report with two groups.</summary>
    private static Queue<object> OnePage() => new([Obj(("Report", Obj(("Invocations", 7), ("Complete", true))), ("Groups", new object[] { Obj(("Name", "a")), Obj(("Name", "b")) }), ("GroupsComplete", true), ("ReportId", "rid"))]);

    /// <summary>Comma-joined actions sent to the fake engine.</summary>
    private static string Actions(Runspace runspace) => string.Join(",", DeliveryCmdletCases.Script(runspace, "foreach($r in $GainLog){$r.Action}").Select(item => (string)item.BaseObject));

    /// <summary>Reads a field of the first logged request as text; a field name or a full expression.</summary>
    private static string Query(Runspace runspace, string field) =>
        Convert.ToString(DeliveryCmdletCases.Script(runspace, field.StartsWith('$') ? field : "$GainLog[0]." + field).Single().BaseObject) ?? "";

    /// <summary>Builds a custom object.</summary>
    private static PSObject Obj(params (string Name, object? Value)[] fields)
    {
        var result = new PSObject();
        foreach ((string name, object? value) in fields) result.Properties.Add(new PSNoteProperty(name, value));
        return result;
    }

    /// <summary>Generates a random nested value together with its expected compact JSON.</summary>
    private static (object? Value, string Json) Generate(Random random, int depth)
    {
        switch (depth <= 0 ? random.Next(4) : random.Next(6))
        {
            case 0: return (null, "null");
            case 1: { int number = random.Next(-1000, 1000); return (number, number.ToString()); }
            case 2: { bool flag = random.Next(2) == 0; return (flag, flag ? "true" : "false"); }
            case 3: { string text = new string(Enumerable.Range(0, random.Next(0, 6)).Select(_ => "abcé漢"[random.Next(5)]).ToArray()); return (text, "\"" + text + "\""); }
            case 4:
            {
                var items = Enumerable.Range(0, random.Next(0, 4)).Select(_ => Generate(random, depth - 1)).ToArray();
                return (items.Select(item => item.Value).ToArray(), "[" + string.Join(",", items.Select(item => item.Json)) + "]");
            }
            default:
            {
                var members = Enumerable.Range(0, random.Next(0, 4)).Select(index => (Name: "k" + index, Child: Generate(random, depth - 1))).ToArray();
                return (Obj(members.Select(member => (member.Name, member.Child.Value)).ToArray()), "{" + string.Join(",", members.Select(member => "\"" + member.Name + "\":" + member.Child.Json)) + "}");
            }
        }
    }

    /// <summary>True when a custom object remains anywhere in the graph.</summary>
    private static bool ContainsCustomObject(object? value) => value switch
    {
        PSObject => true,
        OrderedDictionary map => map.Values.Cast<object?>().Any(ContainsCustomObject),
        object?[] array => array.Any(ContainsCustomObject),
        _ => false,
    };

    /// <summary>Throws when an independently known invariant fails.</summary>
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
