using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Property, fuzz and contract cases for the compiled delivery cmdlets, driven through a real PowerShell runspace.</summary>
internal static class DeliveryCmdletCases
{
    /// <summary>Fixed seed retained so any failing generated value can be replayed deterministically.</summary>
    private const int Seed = 20261110;

    /// <summary>Script that builds a minimal offline local result around the supplied data.</summary>
    private const string NewResult = "param($data) [pscustomobject][ordered]@{SchemaVersion=1;Outcome='Success';Data=$data;InvocationId='t';Context='c';Error=@();"
        + "Completeness=[pscustomobject]@{Source=$true;Analysis=$true};Measurement=[pscustomobject]@{Status='CountersOnly';OutputBytes=$null;OutputTokens=$null;ReductionBytes=$null;StorageError=$null};"
        + "Deliveries=[Collections.Generic.List[object]]::new();Internal=@{Sources=[ordered]@{};Request=@{};Offline=$true}}";

    /// <summary>Runs every delivery cmdlet case.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="root">Module root containing the pinned resources.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, string root)
    {
        QuietSession.Initialize(root);
        var state = InitialSessionState.CreateDefault2();
        foreach (var (name, type) in new (string, Type)[] {
            ("Out-QuietResult", typeof(OutQuietResultCommand)), ("ConvertTo-QuietJson", typeof(ConvertToQuietJsonCommand)),
            ("ConvertTo-QuietYaml", typeof(ConvertToQuietYamlCommand)), ("Get-QuietSetting", typeof(GetQuietSettingCommand)) })
            state.Commands.Add(new SessionStateCmdletEntry(name, type, null));
        using Runspace runspace = RunspaceFactory.CreateRunspace(state);
        runspace.Open();
        ConfigurationService.Snapshot(Directory.GetCurrentDirectory()).Values["telemetry.enabled"] = false;

        await run("delivery counts the exact tokens of the delivered text and deduplicates receipts", () =>
        {
            object result = Result(runspace, new Dictionary<string, object> { ["Label"] = "é漢字😀" });
            string text = (string)Script(runspace, "param($r) Out-QuietResult $r -Tokenizer o200k_base", result).Single().BaseObject;
            long expected = Convert.ToInt64(Script(runspace, "param($t) [Microsoft.ML.Tokenizers.TiktokenTokenizer]::CreateForEncoding('o200k_base',$null,$null).CountTokens($t)", text).Single().BaseObject);
            var measurement = (PSObject)Member(result, "Measurement");
            Require(Convert.ToInt64(measurement.Properties["OutputTokens"].Value) == expected && expected > 0, "Delivered token count differs from the independent count");
            Require(Convert.ToInt32(measurement.Properties["OutputBytes"].Value) == Encoding.UTF8.GetByteCount(text), "Delivered byte count differs from the UTF-8 size");
            // No native business sources: the reduction is exactly the negated delivery size.
            Require(Convert.ToInt64(measurement.Properties["ReductionBytes"].Value) == -Encoding.UTF8.GetByteCount(text), "Reduction is not the negated delivery size");
            string id = (string)Script(runspace, "param($r) $r.Deliveries[0].DeliveryId", result).Single().BaseObject;
            Script(runspace, "param($r) $null=Out-QuietResult $r -Tokenizer o200k_base", result);
            Require((bool)Script(runspace, "param($r) $r.Deliveries[0].AlreadyDelivered", result).Single().BaseObject, "Second identical delivery was not recognized");
            Require((string)Script(runspace, "param($r) $r.Deliveries[0].DeliveryId", result).Single().BaseObject == id, "Receipt identity changed");
            return Task.CompletedTask;
        });

        await run("delivery tokenizer off leaves tokens unknown", () =>
        {
            object result = Result(runspace, new Dictionary<string, object> { ["a"] = 1 });
            Script(runspace, "param($r) $null=Out-QuietResult $r -Tokenizer off", result);
            Require(Member(Member(result, "Measurement"), "OutputTokens") is null, "Tokens reported although the tokenizer is off");
            return Task.CompletedTask;
        });

        await run("delivery projection bounds collections for generated sizes and keeps valid JSON", () =>
        {
            var random = new Random(Seed);
            for (int round = 0; round < 40; round++)
            {
                int count = random.Next(0, 30), limit = random.Next(0, 12);
                object[] items = Enumerable.Range(0, count).Select(index => (object)index).ToArray();
                object result = Result(runspace, new Dictionary<string, object> { ["Items"] = items });
                string text = (string)Script(runspace, "param($r,$m) Out-QuietResult $r -MaxItems $m -MaxOutputBytes 65536 -Tokenizer off", result, limit).Single().BaseObject;
                using var parsed = System.Text.Json.JsonDocument.Parse(text);
                var truncation = parsed.RootElement.GetProperty("Truncation");
                // Independent oracle: a dictionary of one key and a list of `count` entries.
                bool dictionaryCut = limit < 1;
                bool listCut = count > limit;
                Require(truncation.GetProperty("Applied").GetBoolean() == (dictionaryCut || listCut), $"Truncation flag wrong for count={count} limit={limit}");
                if (!dictionaryCut)
                {
                    var data = parsed.RootElement.GetProperty("Data");
                    int length = data.GetProperty("Items").GetArrayLength();
                    Require(length == Math.Min(count, limit), $"Projected length {length} for count={count} limit={limit}");
                }
            }
            return Task.CompletedTask;
        });

        await run("delivery never splits a surrogate pair when shortening a string", () =>
        {
            string value = new string('a', 2047) + "😀" + "b";
            object result = Result(runspace, new Dictionary<string, object> { ["S"] = value });
            string text = (string)Script(runspace, "param($r) Out-QuietResult $r -MaxOutputBytes 4096 -Tokenizer off", result).Single().BaseObject;
            using var parsed = System.Text.Json.JsonDocument.Parse(text);
            string shortened = parsed.RootElement.GetProperty("Data").GetProperty("S").GetString()!;
            Require(shortened == new string('a', 2047) + "…", "Shortened string kept half of a surrogate pair");
            return Task.CompletedTask;
        });

        await run("delivery falls back to a minimal envelope when the budget is exceeded", () =>
        {
            object result = Result(runspace, new Dictionary<string, object> { ["S"] = new string('x', 900) });
            string text = (string)Script(runspace, "param($r) Out-QuietResult $r -MaxOutputBytes 300 -Tokenizer off", result).Single().BaseObject;
            using var parsed = System.Text.Json.JsonDocument.Parse(text);
            Require(parsed.RootElement.GetProperty("Data").ValueKind == System.Text.Json.JsonValueKind.Null && parsed.RootElement.GetProperty("Truncation").GetProperty("Reason").GetString() == "OutputBudget", "Budget fallback envelope missing");
            Require(Encoding.UTF8.GetByteCount(text) <= 300, "Fallback exceeded the budget");
            return Task.CompletedTask;
        });

        await run("delivery rejects exclusive formats and invalid budgets with stable codes", () =>
        {
            object result = Result(runspace, new Dictionary<string, object>());
            Expect(runspace, "OutputFormatsAreExclusive", "param($r) Out-QuietResult $r -AsJson -AsYaml", result);
            Expect(runspace, "InvalidDeliveryBudget", "param($r) Out-QuietResult $r -MaxOutputBytes 255", result);
            Expect(runspace, "InvalidDeliveryBudget", "param($r) Out-QuietResult $r -MaxItems -1", result);
            return Task.CompletedTask;
        });

        await run("delivery emits YAML with the same identity and flags only", () =>
        {
            object result = Result(runspace, new Dictionary<string, object> { ["Name"] = "value" });
            string text = (string)Script(runspace, "param($r) ConvertTo-QuietYaml $r -Tokenizer off", result).Single().BaseObject;
            // Keys are JSON-quoted by the renderer.
            Require(text.StartsWith("\"SchemaVersion\": 1", StringComparison.Ordinal) && text.Contains("\"Name\":") && text.Contains("\"Analysis\": true"), "YAML delivery shape changed: " + text.Replace("\n", "\\n"));
            Require((string)Script(runspace, "param($r) $r.Deliveries[0].Format", result).Single().BaseObject == "yaml", "YAML format not recorded");
            return Task.CompletedTask;
        });
    }

    /// <summary>Builds an offline local result around CLR data.</summary>
    private static object Result(Runspace runspace, object data) => Script(runspace, NewResult, data).Single();

    /// <summary>Reads a member of a PowerShell object.</summary>
    private static object? Member(object container, string name) => PSObject.AsPSObject(container).Properties[name]?.Value;

    /// <summary>Runs a script block with positional arguments and returns its output.</summary>
    private static List<PSObject> Script(Runspace runspace, string script, params object[] arguments)
    {
        using var shell = PowerShell.Create(runspace);
        shell.AddScript(script);
        foreach (object argument in arguments) shell.AddArgument(argument);
        List<PSObject> output = shell.Invoke().ToList();
        // A statement-terminating cmdlet error inside a script is recorded, not thrown.
        if (shell.Streams.Error.Count > 0) throw shell.Streams.Error[0].Exception ?? new InvalidOperationException(shell.Streams.Error[0].ToString());
        return output;
    }

    /// <summary>Requires a terminating error whose innermost message is the code.</summary>
    private static void Expect(Runspace runspace, string code, string script, params object[] arguments)
    {
        try { Script(runspace, script, arguments); }
        catch (Exception error) when (ConfigurationService.Innermost(error).Message.StartsWith(code, StringComparison.Ordinal)) { return; }
        throw new InvalidOperationException(script + " did not fail with " + code);
    }

    /// <summary>Throws when an independently known invariant fails.</summary>
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
