using System.Collections;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Caller-chosen options of one offline replay; every value is validated by <see cref="Parse"/> or by cmdlet binding.</summary>
internal sealed class RecallReplayOptions
{
    /// <summary>Streaming callback receiving each event and the fresh runtime.</summary>
    public ScriptBlock? Output { get; init; }
    /// <summary>Completion callback.</summary>
    public ScriptBlock? Complete { get; init; }
    /// <summary>Caller-local delivery projection.</summary>
    public ScriptBlock? Projection { get; init; }
    /// <summary>Caller-owned business value.</summary>
    public object? Data { get; init; }
    /// <summary>Caller-owned auxiliary state.</summary>
    public Hashtable State { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Text or Bytes override, or null to keep the captured setting.</summary>
    public string? StdoutMode { get; init; }
    /// <summary>Text or Bytes override, or null to keep the captured setting.</summary>
    public string? StderrMode { get; init; }
    /// <summary>True when a delimiter override was supplied, even a null or empty one (which clears framing).</summary>
    public bool RecordDelimiterBound { get; init; }
    /// <summary>Delimiter override; null or empty clears framing.</summary>
    public string? RecordDelimiter { get; init; }
    /// <summary>Positive framing budget override, or null.</summary>
    public int? MaxRecordBytes { get; init; }
    /// <summary>Explicitly accepts missing intervals.</summary>
    public bool AllowPartial { get; init; }

    private static readonly string[] Modes = ["Text", "Bytes"];

    /// <summary>Builds options from the validated facade replay hashtable.</summary>
    /// <param name="values">Subset of Output, Complete, Data, State, StdoutMode, StderrMode, RecordDelimiter, MaxRecordBytes, Projection, AllowPartial.</param>
    /// <exception cref="InvalidOperationException">A stable code when a value has the wrong type or range.</exception>
    public static RecallReplayOptions Parse(Hashtable values)
    {
        object? Raw(string name) => values.ContainsKey(name) ? QuietRuntime.Unwrap(values[name]) : null;
        ScriptBlock? Block(string name) => Raw(name) switch { null => null, ScriptBlock block => block, _ => throw new InvalidOperationException("CallbackMustBeScriptBlock") };
        string? Mode(string name)
        {
            if (Raw(name) is not { } value) return null;
            string text = Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
            return Modes.FirstOrDefault(mode => string.Equals(mode, text, StringComparison.OrdinalIgnoreCase)) ?? throw new InvalidOperationException("RecallModeInvalid: " + name);
        }
        int? budget = null;
        if (Raw("MaxRecordBytes") is { } size)
        {
            long parsed;
            try { parsed = Convert.ToInt64(size, CultureInfo.InvariantCulture); } catch (Exception) { throw new InvalidOperationException("RecallMaxRecordBytesInvalid"); }
            if (parsed < 1 || parsed > int.MaxValue) throw new InvalidOperationException("RecallMaxRecordBytesInvalid");
            budget = (int)parsed;
        }
        return new RecallReplayOptions
        {
            Output = Block("Output"), Complete = Block("Complete"), Projection = Block("Projection"),
            Data = values.ContainsKey("Data") ? values["Data"] : null,
            State = Raw("State") switch { null => new Hashtable(StringComparer.OrdinalIgnoreCase), Hashtable table => table, _ => throw new InvalidOperationException("RecallStateMustBeHashtable") },
            StdoutMode = Mode("StdoutMode"), StderrMode = Mode("StderrMode"),
            RecordDelimiterBound = values.ContainsKey("RecordDelimiter"),
            RecordDelimiter = Raw("RecordDelimiter") is { } delimiter ? Convert.ToString(delimiter, CultureInfo.InvariantCulture) : null,
            MaxRecordBytes = budget,
            AllowPartial = values.ContainsKey("AllowPartial") && LanguagePrimitives.IsTrue(values["AllowPartial"]),
        };
    }
}

/// <summary>Reanalyzes retained bytes locally through the same stream pipeline as live calls, without executing anything.</summary>
internal static class RecallReplayer
{
    /// <summary>Replays a capture and builds the local result envelope.</summary>
    /// <param name="host">Cmdlet that owns the runtime factory and the caller's location.</param>
    /// <param name="capture">Immutable retained evidence.</param>
    /// <param name="native">Original native execution snapshot when known, otherwise the capture's source status is used.</param>
    /// <param name="options">Validated replay options.</param>
    /// <exception cref="InvalidOperationException"><c>PartialRecallRequiresAllowPartial</c> or <c>RecallAnalysisCallbackRequired</c>.</exception>
    public static PSObject Replay(RuntimeCmdlet host, RecallCapture capture, object? native, RecallReplayOptions options)
    {
        if (!capture.CaptureComplete && !options.AllowPartial) throw new InvalidOperationException("PartialRecallRequiresAllowPartial");
        if (options.Output is null && options.Complete is null) throw new InvalidOperationException("RecallAnalysisCallbackRequired");
        Hashtable request = BuildRequest(capture, options);
        QuietRuntime runtime = host.CreateRuntime(request, QuietCallState.Current, QuietSession.SessionId);
        runtime.IsRecall = true;
        runtime.Recall = capture;
        var watch = Stopwatch.StartNew();
        var allocation = new AllocationMeter();
        long cursor = 0, consumed = 0, count = 0;
        bool readComplete = true;
        QuietCallState.RecallDepth++;
        try
        {
            foreach (RecallEvent evt in capture.Events)
            {
                runtime.CurrentRecallGap = null;
                if (evt.ObservedOffset != cursor)
                {
                    runtime.CurrentRecallGap = new RecallGap(cursor, evt.ObservedOffset - cursor);
                    DisposeStreams(runtime);
                }
                runtime.CurrentRecallEvent = evt;
                runtime.StreamBlock(evt.Stream, evt.Bytes);
                cursor = evt.ObservedOffset + evt.ByteCount;
                consumed += evt.ByteCount;
                count++;
            }
            runtime.CurrentRecallEvent = null;
            if (cursor == capture.ReceivedBytes) runtime.CompleteStreams(); else DisposeStreams(runtime);
            runtime.CompleteAnalysis();
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            readComplete = false;
            runtime.AnalysisComplete = false;
            runtime.Errors.Add(new Hashtable(StringComparer.OrdinalIgnoreCase) { ["Code"] = "RecallReadFailed", ["Phase"] = "Recall", ["Message"] = error.Message });
            if (!runtime.CompleteInvoked) runtime.CompleteAnalysis();
        }
        finally
        {
            foreach (TextStreamState processor in runtime.TextStreams.Values) processor.Dispose();
            QuietCallState.RecallDepth--;
        }
        bool analysisComplete = runtime.AnalysisComplete && capture.CaptureComplete && capture.SourceComplete && readComplete;
        object? original = native is not null && PSObject.AsPSObject(native).Properties["Execution"] is { } property ? property.Value : capture.SourceStatus;
        object? execution = CallerMetadata.Freeze(new Hashtable { ["State"] = "Finalized", ["Kind"] = "Recall", ["ElapsedMs"] = watch.Elapsed.TotalMilliseconds, ["Native"] = null, ["Original"] = original }, MetadataAdapter.Instance);
        object? completeness = CallerMetadata.Freeze(new Hashtable { ["Source"] = capture.SourceComplete && capture.CaptureComplete && readComplete, ["Analysis"] = analysisComplete }, MetadataAdapter.Instance);
        return Envelope(runtime, request, capture, execution, completeness, count, consumed, allocation.Stop());
    }

    /// <summary>Starts from the captured settings and applies only the explicit overrides.</summary>
    private static Hashtable BuildRequest(RecallCapture capture, RecallReplayOptions options)
    {
        var request = new Hashtable(StringComparer.OrdinalIgnoreCase)
        {
            ["AsObject"] = true, ["Data"] = options.Data, ["State"] = options.State,
            ["StdoutMode"] = capture.Settings.StdoutMode, ["StderrMode"] = capture.Settings.StderrMode,
            ["MaxRecordBytes"] = capture.Settings.MaxRecordBytes, ["MaxItems"] = 20, ["MaxOutputBytes"] = 4096,
        };
        if (capture.Settings.RecordDelimiter is not null) request["RecordDelimiter"] = capture.Settings.RecordDelimiter;
        if (options.StdoutMode is not null) request["StdoutMode"] = options.StdoutMode;
        if (options.StderrMode is not null) request["StderrMode"] = options.StderrMode;
        if (options.MaxRecordBytes is { } budget) request["MaxRecordBytes"] = budget;
        if (options.RecordDelimiterBound)
        {
            if (string.IsNullOrEmpty(options.RecordDelimiter)) request.Remove("RecordDelimiter"); else request["RecordDelimiter"] = options.RecordDelimiter;
        }
        if (options.Output is not null) request["Output"] = options.Output;
        if (options.Complete is not null) request["Complete"] = options.Complete;
        if (options.Projection is not null) request["Projection"] = options.Projection;
        return request;
    }

    /// <summary>Drops every partial decoder so framing restarts after a gap or an incomplete read.</summary>
    private static void DisposeStreams(QuietRuntime runtime)
    {
        foreach (TextStreamState processor in runtime.TextStreams.Values) processor.Dispose();
        runtime.TextStreams.Clear();
    }

    private static PSObject Envelope(QuietRuntime runtime, Hashtable request, RecallCapture capture, object? execution, object? completeness, long count, long consumed, object? allocation)
    {
        var truncation = new PSObject();
        truncation.Properties.Add(new PSNoteProperty("Applied", !capture.CaptureComplete));
        truncation.Properties.Add(new PSNoteProperty("Reasons", capture.CaptureComplete ? Array.Empty<object>() : new object[] { "RecallRangesOmitted" }));
        var cursor = new PSObject();
        cursor.Properties.Add(new PSNoteProperty("Events", count));
        cursor.Properties.Add(new PSNoteProperty("Bytes", consumed));
        cursor.Properties.Add(new PSNoteProperty("DeclaredIgnoredSequences", runtime.IgnoredSequences.OrderBy(sequence => sequence).Cast<object>().ToArray()));
        var measurement = new PSObject();
        foreach ((string name, object? value) in new (string, object?)[] { ("Status", "LocalAnalysis"), ("OutputBytes", null), ("OutputTokens", null), ("ReductionBytes", null), ("StorageError", null), ("Allocation", allocation) })
            measurement.Properties.Add(new PSNoteProperty(name, value));
        var result = new PSObject();
        foreach ((string name, object? value) in new (string, object?)[]
        {
            ("SchemaVersion", 1), ("Summary", "Retained native output reanalyzed locally."), ("Outcome", runtime.AnalysisComplete ? "Success" : "Failed"), ("Data", runtime.Data),
            ("InvocationId", runtime.InvocationId), ("Context", runtime.Context), ("Error", runtime.Errors.ToArray()), ("Truncation", truncation),
            ("Cursor", cursor), ("Measurement", measurement), ("Deliveries", new List<object>()),
            ("Internal", new Hashtable(StringComparer.OrdinalIgnoreCase) { ["Sources"] = new System.Collections.Specialized.OrderedDictionary(), ["Request"] = request, ["Administrative"] = true, ["Offline"] = true }),
        })
            result.Properties.Add(new PSNoteProperty(name, value));
        result.TypeNames.Insert(0, "QuietCli2.Result");
        FinalProperties.Set(result, "Execution", execution);
        FinalProperties.Set(result, "Completeness", completeness);
        FinalProperties.Set(result, "Recall", capture);
        return result;
    }
}

/// <summary>Reanalyzes retained bytes locally without native execution or telemetry writes.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "QuietRecall", DefaultParameterSetName = "Input")]
public sealed class InvokeQuietRecallCommand : DeliveryCmdlet
{
    /// <summary>Native result or capture.</summary>
    [Parameter(Mandatory = true, Position = 0, ParameterSetName = "Input")]
    public object? InputObject { get; set; }
    /// <summary>Opens a durable identity instead of an in-memory object.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Id")]
    public string RecallId { get; set; } = "";
    /// <summary>Explicit durable store root.</summary>
    [Parameter(ParameterSetName = "Id")]
    public string? RecallRoot { get; set; }
    /// <summary>Streaming callback receiving event and fresh runtime.</summary>
    [Parameter] public ScriptBlock? Output { get; set; }
    /// <summary>Optional completion callback.</summary>
    [Parameter] public ScriptBlock? Complete { get; set; }
    /// <summary>Caller-owned fresh business state.</summary>
    [Parameter] public object? Data { get; set; }
    /// <summary>Caller-owned fresh auxiliary state.</summary>
    [Parameter] public Hashtable State { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Optional Text or Bytes override.</summary>
    [Parameter] [ValidateSet("Text", "Bytes")] public string? StdoutMode { get; set; }
    /// <summary>Optional Text or Bytes override.</summary>
    [Parameter] [ValidateSet("Text", "Bytes")] public string? StderrMode { get; set; }
    /// <summary>Optional record delimiter override; null or empty clears framing.</summary>
    [Parameter] [AllowNull] public string? RecordDelimiter { get; set; }
    /// <summary>Optional positive framing budget override.</summary>
    [Parameter] [ValidateRange(1, int.MaxValue)] public int MaxRecordBytes { get; set; }
    /// <summary>Explicitly accepts missing intervals; resets framing at each gap.</summary>
    [Parameter] public SwitchParameter AllowPartial { get; set; }
    /// <summary>Caller-local delivery projection; never persisted or executed during loading.</summary>
    [Parameter] public ScriptBlock? Projection { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try
        {
            bool byId = ParameterSetName == "Id";
            RecallCapture capture = byId
                ? RecallStore.OpenAsync(RecallCommandSupport.ResolveRoot(RecallRoot, CurrentDirectory), RecallId).GetAwaiter().GetResult()
                : RecallCommandSupport.ResolveCapture(InputObject);
            var options = new RecallReplayOptions
            {
                Output = Output, Complete = Complete, Projection = Projection, Data = Data, State = State,
                StdoutMode = StdoutMode, StderrMode = StderrMode, RecordDelimiterBound = MyInvocation.BoundParameters.ContainsKey(nameof(RecordDelimiter)),
                RecordDelimiter = RecordDelimiter, MaxRecordBytes = MyInvocation.BoundParameters.ContainsKey(nameof(MaxRecordBytes)) ? MaxRecordBytes : null,
                AllowPartial = AllowPartial,
            };
            WriteObject(RecallReplayer.Replay(this, capture, byId ? null : InputObject, options));
        }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}
