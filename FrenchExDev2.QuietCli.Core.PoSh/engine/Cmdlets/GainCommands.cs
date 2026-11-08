using System.Collections;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Sends one administrative metadata request and returns the reply data, honoring the Send-QuietRequest test seam.</summary>
public abstract class AdminRequestCmdlet : EngineCmdlet
{
    /// <summary>Exchanges one control header with the engine.</summary>
    /// <param name="header">Control metadata, never a business object.</param>
    /// <returns>The Data member of the reply header.</returns>
    internal object? Ask(Hashtable header)
    {
        if (FindFunction("Send-QuietRequest") is { } seam)
        {
            PSObject reply = seam.ScriptBlock.Invoke(header).FirstOrDefault() ?? throw new InvalidOperationException("EmptyEngineReply");
            return Members.Get(Members.Get(reply, "Header"), "Data");
        }
        return PropertyReader.Get(EngineClient.Send(QuietSession.Engine ?? EnsureEngine(), header, [], IpcTimeout).Header, "Data");
    }
}

/// <summary>Reports measured counters across contexts, without creating a missing database and without recording a delivery.</summary>
[Cmdlet(VerbsCommon.Get, "QuietCliGain")]
[OutputType(typeof(PSObject), typeof(string))]
public sealed class GetQuietCliGainCommand : AdminRequestCmdlet
{
    /// <summary>Unix milliseconds of the lowest representable instant, used when there is no lower boundary.</summary>
    private static readonly long MinimumMilliseconds = DateTimeOffset.MinValue.ToUnixTimeMilliseconds();

    /// <summary>Unix milliseconds of the highest representable instant, used when there is no upper boundary.</summary>
    private static readonly long MaximumMilliseconds = DateTimeOffset.MaxValue.ToUnixTimeMilliseconds();

    /// <summary>Optional named context.</summary>
    [Parameter]
    [Alias("C")]
    public string? Context { get; set; }

    /// <summary>Selects only invocations without a context; exclusive with Context.</summary>
    [Parameter]
    public SwitchParameter Generic { get; set; }

    /// <summary>Optional caller session identity.</summary>
    [Parameter]
    public string? SessionId { get; set; }

    /// <summary>Optional registered business module identity.</summary>
    [Parameter]
    public string? ModuleId { get; set; }

    /// <summary>Optional trailing window ending at To or now; ignored when From is supplied.</summary>
    [Parameter]
    [ValidateRange(1, 3650000)]
    public int Days { get; set; }

    /// <summary>Optional inclusive lower time boundary; overrides Days.</summary>
    [Parameter]
    public DateTimeOffset? From { get; set; }

    /// <summary>Optional exclusive upper time boundary.</summary>
    [Parameter]
    public DateTimeOffset? To { get; set; }

    /// <summary>Context, Command, Session, Module, Role or Outcome.</summary>
    [Parameter]
    [ValidateSet("Context", "Command", "Session", "Module", "Role", "Outcome")]
    public string GroupBy { get; set; } = "Context";

    /// <summary>Explicitly selects the default object output.</summary>
    [Parameter]
    public SwitchParameter AsObject { get; set; }

    /// <summary>Serializes the report directly as YAML.</summary>
    [Parameter]
    public SwitchParameter AsYaml { get; set; }

    /// <summary>Serializes the report as indented JSON.</summary>
    [Parameter]
    public SwitchParameter AsJson { get; set; }

    /// <summary>Removes JSON formatting whitespace; requires AsJson.</summary>
    [Parameter]
    public SwitchParameter Compress { get; set; }

    /// <summary>Maximum telemetry events scanned by this report.</summary>
    [Parameter]
    [ValidateRange(1, 1000000)]
    public int MaxEvents { get; set; } = 10000;

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { Report(); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }

    /// <summary>Validates the options, collects every group page and renders the requested format.</summary>
    private void Report()
    {
        var bound = MyInvocation.BoundParameters;
        if ((AsObject ? 1 : 0) + (AsYaml ? 1 : 0) + (AsJson ? 1 : 0) > 1) { Fail("OutputFormatsAreExclusive"); return; }
        if (bound.ContainsKey("Compress") && !AsJson) { Fail("CompressRequiresAsJson"); return; }
        if (Generic && bound.ContainsKey("Context")) { Fail("ContextAndGenericAreExclusive"); return; }
        int maxEvents = bound.ContainsKey("MaxEvents") ? MaxEvents : Convert.ToInt32(QuietRuntime.Unwrap(Setting("gain.maxEvents")), CultureInfo.InvariantCulture);
        (DateTimeOffset? lower, DateTimeOffset? upper) = Window(bound.ContainsKey("Days") ? Days : (int?)null, From, To, DateTimeOffset.UtcNow);
        if (lower is { } low && upper is { } high && low >= high) { Fail("InvalidTimeRange"); return; }
        var query = new Hashtable
        {
            ["Action"] = "gain", ["From"] = lower?.ToUnixTimeMilliseconds() ?? MinimumMilliseconds, ["To"] = upper?.ToUnixTimeMilliseconds() ?? MaximumMilliseconds,
            ["Generic"] = (bool)Generic, ["GroupBy"] = GroupBy, ["MaxEvents"] = maxEvents,
        };
        if (bound.ContainsKey("Context")) query["Context"] = Context;
        if (!string.IsNullOrEmpty(SessionId)) query["SessionId"] = SessionId;
        if (!string.IsNullOrEmpty(ModuleId)) query["ModuleId"] = ModuleId;
        (object? report, List<object?> groups) = Collect(query);
        PSObject result = Build(report, lower, upper, groups);
        if (AsYaml)
        {
            ResourceVerifier.Verify(QuietSession.Root, "resources/yaml/YamlDotNet.dll");
            WriteObject(BoundedYaml.Render(YamlGraph(result), QuietSession.Root, 0, scalar => JsonText.Compress(scalar, 4)));
        }
        else if (AsJson)
            WriteObject(ScriptBlock.Create("param($report,$compress) ConvertTo-Json -InputObject $report -Depth 20 -Compress:$compress").Invoke(result, (bool)Compress).FirstOrDefault()?.BaseObject);
        else WriteObject(result);
    }

    /// <summary>Resolves the effective time window: From wins over Days, and Days ends at To or at the supplied instant.</summary>
    /// <param name="days">Optional trailing window length in days.</param>
    /// <param name="lower">Optional explicit lower boundary.</param>
    /// <param name="upper">Optional explicit upper boundary.</param>
    /// <param name="now">Instant used when Days has no upper boundary.</param>
    internal static (DateTimeOffset? Lower, DateTimeOffset? Upper) Window(int? days, DateTimeOffset? lower, DateTimeOffset? upper, DateTimeOffset now)
    {
        if (lower is null && days is { } length)
        {
            upper ??= now;
            lower = upper.Value.AddDays(-length);
        }
        return (lower, upper);
    }

    /// <summary>Follows the pagination cursor until every group has been read; a completed report is already released by the engine.</summary>
    /// <param name="first">First gain request.</param>
    private (object? Report, List<object?> Groups) Collect(Hashtable first)
    {
        var groups = new List<object?>();
        object? report = null;
        string? reportId = null;
        Hashtable query = first;
        try
        {
            while (true)
            {
                object? response = Ask(query);
                if (LanguagePrimitives.IsTrue(Members.Get(response, "Pending")))
                {
                    string? pending = Text(Members.Get(response, "ReportId"));
                    if (string.IsNullOrEmpty(pending)) throw new InvalidOperationException("MeasurementPaginationMissingCursor");
                    reportId = pending;
                    query = new Hashtable { ["Action"] = "gain-poll", ["ReportId"] = reportId };
                    continue;
                }
                report ??= Members.Get(response, "Report");
                if (Members.Get(response, "Groups") is { } page)
                    foreach (object? group in page is IEnumerable and not string ? (IEnumerable)page : new[] { page }) groups.Add(group);
                if (LanguagePrimitives.IsTrue(Members.Get(response, "GroupsComplete"))) { reportId = null; break; }
                object? after = Members.Get(response, "After");
                string? next = Text(Members.Get(response, "ReportId"));
                if (string.IsNullOrEmpty(next) || after is null) throw new InvalidOperationException("MeasurementPaginationMissingCursor");
                reportId = next;
                query = new Hashtable { ["Action"] = "gain-next", ["ReportId"] = reportId, ["After"] = after };
            }
        }
        finally
        {
            if (!string.IsNullOrEmpty(reportId))
                try { Ask(new Hashtable { ["Action"] = "gain-release", ["ReportId"] = reportId }); } catch (Exception release) when (release is not PipelineStoppedException) { }
        }
        return (report, groups);
    }

    /// <summary>Copies the report into a custom object, which unifies the CLR DTO and JSON hosting shapes, and appends the window and groups.</summary>
    private static PSObject Build(object? report, DateTimeOffset? lower, DateTimeOffset? upper, List<object?> groups)
    {
        var result = new PSObject();
        if (report is not null)
            foreach (PSPropertyInfo property in PSObject.AsPSObject(report).Properties) result.Properties.Add(new PSNoteProperty(property.Name, property.Value));
        result.Properties.Add(new PSNoteProperty("From", lower));
        result.Properties.Add(new PSNoteProperty("To", upper));
        result.Properties.Add(new PSNoteProperty("Groups", groups.ToArray()));
        return result;
    }

    /// <summary>Normalizes the closed telemetry report for the YAML renderer without truncating groups.</summary>
    /// <param name="value">Report property, group, array or scalar received from the metadata engine.</param>
    internal static object? YamlGraph(object? value)
    {
        if (value is PSObject wrapped && wrapped.BaseObject is not PSCustomObject) value = wrapped.BaseObject;
        if (value is null or string or ValueType) return value;
        if (value is Array array)
        {
            var items = new object?[array.Length];
            for (int index = 0; index < items.Length; index++) items[index] = YamlGraph(array.GetValue(index));
            return items;
        }
        var map = new OrderedDictionary();
        foreach (PSPropertyInfo property in PSObject.AsPSObject(value).Properties) map[property.Name] = YamlGraph(property.Value);
        return map;
    }

    /// <summary>Converts an identifier to text.</summary>
    private static string? Text(object? value) => value is null ? null : Convert.ToString(QuietRuntime.Unwrap(value), CultureInfo.InvariantCulture);
}

/// <summary>Explicitly expunges legacy persisted diagnostic text; irreversible for the selected engine database.</summary>
[Cmdlet(VerbsDiagnostic.Repair, "QuietCliMeasurementPrivacy", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RepairQuietCliMeasurementPrivacyCommand : AdminRequestCmdlet
{
    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try
        {
            // The engine database is the telemetry.database setting it was started with, so -WhatIf never starts an engine.
            string database = QuietSession.Engine?.Database ?? Convert.ToString(QuietRuntime.Unwrap(Setting("telemetry.database")), CultureInfo.InvariantCulture) ?? "";
            if (ShouldProcess(database, "Expurger définitivement les diagnostics historiques non conformes"))
                WriteObject(Ask(new Hashtable { ["Action"] = "scrub", ["Confirmed"] = true }));
        }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}
