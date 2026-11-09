using System.Collections;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Spectre.Console;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Caller-local state of one invocation; owns the native event loop, stream decoding and callback dispatch.</summary>
public sealed class QuietRuntime
{
    /// <summary>Allowed lifecycle transitions; the lifecycle only moves forward.</summary>
    private static readonly Dictionary<string, string> Transitions = new(StringComparer.Ordinal) { ["Created"] = "Running", ["Running"] = "Draining", ["Draining"] = "Completing", ["Completing"] = "Finalized" };

    /// <summary>Sends one bounded exchange to the engine; replaceable by a session-level Send-QuietRequest function in tests.</summary>
    internal Func<Hashtable, byte[], EngineReply>? Exchange { get; set; }

    /// <summary>Unique identity of this invocation.</summary>
    public string InvocationId { get; internal set; } = "";
    /// <summary>Identity of the enclosing invocation, if any.</summary>
    public string? ParentId { get; internal set; }
    /// <summary>Identity of the outermost invocation.</summary>
    public string RootId { get; internal set; } = "";
    /// <summary>Identity of the PowerShell session.</summary>
    public object? SessionId { get; internal set; }
    /// <summary>Caller-chosen or inherited context label.</summary>
    public object? Context { get; internal set; }
    /// <summary>Validated facade options.</summary>
    public Hashtable Request { get; internal set; } = new();
    /// <summary>Caller-owned business value.</summary>
    public object? Data { get; set; }
    /// <summary>Caller-owned auxiliary state.</summary>
    public object? State { get; set; }
    /// <summary>Current lifecycle state.</summary>
    public string Lifecycle { get; set; } = "Created";
    /// <summary>Last execution snapshot reported by the engine.</summary>
    public object? Execution { get; set; }
    /// <summary>Results of nested invocations.</summary>
    public List<object> Children { get; } = [];
    /// <summary>Measured native sources by invocation id.</summary>
    public OrderedDictionary Sources { get; } = new();
    /// <summary>False once a callback or decoder failed.</summary>
    public bool AnalysisComplete { get; set; } = true;
    /// <summary>Diagnostics accumulated during the call.</summary>
    public List<object> Errors { get; } = [];
    /// <summary>Time spent in caller callbacks, in milliseconds.</summary>
    public double CallbackMs { get; set; }
    /// <summary>Allocation measured around the completion callback.</summary>
    public object? CompleteAllocation { get; set; }
    /// <summary>True once the engine acknowledged the start.</summary>
    public bool NativeStarted { get; set; }
    /// <summary>NotStarted, StartRequested or StartAcknowledged.</summary>
    public string StartState { get; set; } = "NotStarted";
    /// <summary>True once the completion callback ran.</summary>
    public bool CompleteInvoked { get; set; }
    /// <summary>True once input was closed.</summary>
    public bool InputClosed { get; set; }
    /// <summary>True once the engine reported the end of the native process.</summary>
    public bool Completed { get; set; }
    /// <summary>Registered handler that serves this call, if any.</summary>
    public object? Handler { get; set; }
    /// <summary>Per-stream decoders and framers.</summary>
    public Dictionary<string, TextStreamState> TextStreams { get; } = new(StringComparer.Ordinal);
    /// <summary>In-memory recall collector.</summary>
    public RecallCollector? RecallCollector { get; set; }
    /// <summary>Durable recall writer.</summary>
    public RecallJournalWriter? RecallWriter { get; set; }
    /// <summary>True once a durable recall write failed.</summary>
    public bool RecallSaveFailed { get; set; }
    /// <summary>True when the runtime replays retained bytes instead of running a process.</summary>
    public bool IsRecall { get; set; }
    /// <summary>Retained event being replayed.</summary>
    public object? CurrentRecallEvent { get; set; }
    /// <summary>Gap preceding the replayed event.</summary>
    public object? CurrentRecallGap { get; set; }
    /// <summary>Capture being replayed.</summary>
    public object? Recall { get; set; }
    /// <summary>Sequences the analysis declared ignored.</summary>
    public HashSet<long> IgnoredSequences { get; } = [];
    /// <summary>Observers invoked synchronously by <see cref="Emit"/>, in order; empty unless the caller passed -Listeners.</summary>
    public ScriptBlock[] Listeners { get; internal set; } = [];
    /// <summary>Every value passed to <see cref="Emit"/>, collected in order regardless of whether any listener is attached.</summary>
    public List<object?> Events { get; } = [];
    /// <summary>Indexes into <see cref="Listeners"/> that failed and are skipped for the remainder of this call.</summary>
    private HashSet<int>? disabledListeners;
    /// <summary>Live presentation frame for -UI; null (zero cost) unless the caller requested it.</summary>
    public QuietUiRenderer? Ui { get; internal set; }

    /// <summary>Moves the lifecycle forward; any other transition is rejected.</summary>
    /// <param name="next">Running, Draining, Completing or Finalized.</param>
    public void Transition(string next)
    {
        if (!Transitions.TryGetValue(Lifecycle, out string? allowed) || !string.Equals(allowed, next, StringComparison.Ordinal))
            throw new InvalidOperationException("InvalidLifecycleTransition: " + Lifecycle + " -> " + next);
        Lifecycle = next;
    }

    /// <summary>Writes bytes to the native input in bounded blocks.</summary>
    /// <param name="bytes">Explicit input bytes.</param>
    public void WriteBytes(byte[] bytes)
    {
        if (IsRecall) throw new InvalidOperationException("ProcessInputUnavailableDuringRecall");
        if (InputClosed) throw new InvalidOperationException("InputAlreadyClosed");
        for (int offset = 0; offset < bytes.Length;)
        {
            int count = Math.Min(ProtocolSpecification.BlockSize, bytes.Length - offset);
            byte[] block = new byte[count];
            Array.Copy(bytes, offset, block, 0, count);
            while (true)
            {
                object? data = PropertyReader.Get(Send(new Hashtable { ["Action"] = "input", ["InvocationId"] = InvocationId }, block).Header, "Data");
                if (LanguagePrimitives.IsTrue(PropertyReader.Get(data, "Accepted"))) break;
                // A closed input can never accept the block; waiting for output events would only delay the error.
                if (LanguagePrimitives.IsTrue(PropertyReader.Get(data, "Closed"))) throw new InvalidOperationException("InputAlreadyClosed");
                ReadEvent();
                if (Completed) throw new InvalidOperationException("InputProcessExited");
            }
            offset += count;
        }
    }

    /// <summary>Writes UTF-8 text to the native input.</summary>
    /// <param name="text">Text to encode and write.</param>
    public void WriteText(string text) => WriteBytes(Encoding.UTF8.GetBytes(text));

    /// <summary>Closes the native input.</summary>
    public void CompleteInput() { Control("eof", null); InputClosed = true; }

    /// <summary>Requests cancellation of the native process.</summary>
    public void Cancel() => Control("cancel", null);

    /// <summary>Resizes the pseudo terminal.</summary>
    /// <param name="columns">Column count.</param>
    /// <param name="rows">Row count.</param>
    public void Resize(int columns, int rows) => Control("resize", new Hashtable { ["Columns"] = columns, ["Rows"] = rows });

    /// <summary>Declares the replayed event ignored by the analysis.</summary>
    public void MarkIgnored()
    {
        if (CurrentRecallEvent is null) throw new InvalidOperationException("RecallCursorUnavailable");
        IgnoredSequences.Add(Convert.ToInt64(Unwrap(PropertyReader.Get(CurrentRecallEvent, "Sequence")), CultureInfo.InvariantCulture));
    }

    /// <summary>Sends a lifecycle control for the owned native child.</summary>
    /// <param name="action">eof, cancel or resize.</param>
    /// <param name="options">Additional control fields.</param>
    private void Control(string action, IDictionary? options)
    {
        if (IsRecall) throw new InvalidOperationException("ProcessControlUnavailableDuringRecall");
        if (!NativeStarted || Completed) throw new InvalidOperationException("NativeSessionNotRunning");
        var header = new Hashtable { ["Action"] = action, ["InvocationId"] = InvocationId };
        if (options is not null) foreach (DictionaryEntry entry in options) header[entry.Key] = entry.Value;
        Send(header, []);
    }

    /// <summary>Performs one engine exchange.</summary>
    /// <param name="header">Control fields.</param>
    /// <param name="payload">Transient input block.</param>
    internal EngineReply Send(Hashtable header, byte[] payload) => (Exchange ?? throw new InvalidOperationException("EngineUnavailable"))(header, payload);

    /// <summary>Consumes one bounded native frame and dispatches its decoded text; returns the event or null.</summary>
    public object? ReadEvent()
    {
        if (IsRecall) throw new InvalidOperationException("ProcessControlUnavailableDuringRecall");
        if (Completed) return null;
        EngineReply packet = Send(new Hashtable { ["Action"] = "next", ["InvocationId"] = InvocationId }, []);
        object? data = PropertyReader.Get(packet.Header, "Data");
        Execution = PropertyReader.Get(data, "Execution");
        if (LanguagePrimitives.IsTrue(PropertyReader.Get(data, "Completed"))) { Completed = true; Transition("Draining"); return null; }
        if (packet.Payload.Length == 0) return null;
        string stream = Convert.ToString(Unwrap(PropertyReader.Get(data, "Stream")), CultureInfo.InvariantCulture) ?? "";
        if (RecallWriter is not null && !RecallSaveFailed)
        {
            try { RecallWriter.AppendAsync(stream, packet.Payload).GetAwaiter().GetResult(); }
            catch (Exception error) { RecallSaveFailed = true; AddError("RecallWriteFailed", "SaveRecall", error.Message); }
        }
        RecallCollector?.Append(stream, packet.Payload);
        return StreamBlock(stream, packet.Payload);
    }

    /// <summary>Shares strict decoding, framing and callback dispatch between live and offline analysis.</summary>
    /// <param name="stream">Native stream name.</param>
    /// <param name="bytes">One transient native block.</param>
    public object? StreamBlock(string stream, byte[] bytes)
    {
        string mode = Convert.ToString(Unwrap(Request[stream == "stderr" ? "StderrMode" : "StdoutMode"]), CultureInfo.InvariantCulture) ?? "";
        PSObject evt = NewEvent(stream, mode, bytes, null, bytes.Length);
        if (mode == "Text" && AnalysisComplete)
        {
            try
            {
                if (!TextStreams.TryGetValue(stream, out TextStreamState? processor))
                {
                    string? delimiter = Request.ContainsKey("RecordDelimiter") ? Convert.ToString(QuietRuntime.Unwrap(Request["RecordDelimiter"]), CultureInfo.InvariantCulture) : null;
                    processor = TextStreams[stream] = new TextStreamState(delimiter, Convert.ToInt32(QuietRuntime.Unwrap(Request["MaxRecordBytes"]), CultureInfo.InvariantCulture));
                }
                string text = processor.Decode(bytes);
                evt.Properties["Text"].Value = text;
                if (Request.ContainsKey("RecordDelimiter"))
                {
                    foreach (string record in processor.Frame(text)) OutputCallback(NewEvent(stream, "Text", null, record, null));
                    return evt;
                }
            }
            catch (Exception error) { AnalysisComplete = false; AddError("DecodeOrFramingFailed", "Output", error.Message); return null; }
        }
        OutputCallback(evt);
        return evt;
    }

    /// <summary>Flushes and disposes the shared text decoders after live or offline input.</summary>
    public void CompleteStreams()
    {
        foreach (string stream in new[] { "stdout", "stderr", "terminal" })
        {
            if (!AnalysisComplete) break;
            if (!TextStreams.TryGetValue(stream, out TextStreamState? processor)) continue;
            try
            {
                string tail = processor.Finish();
                if (tail.Length > 0) OutputCallback(NewEvent(stream, "Text", null, tail, null));
            }
            catch (Exception error) { AnalysisComplete = false; AddError("DecodeIncomplete", "Drain", error.Message); }
        }
        foreach (TextStreamState processor in TextStreams.Values) processor.Dispose();
    }

    /// <summary>Runs the shared completion callback once with allocation accounting.</summary>
    public void CompleteAnalysis()
    {
        if (!Request.ContainsKey("Complete")) return;
        var watch = Stopwatch.StartNew();
        var allocation = new AllocationMeter();
        try
        {
            if (CompleteInvoked) throw new InvalidOperationException("CompleteAlreadyInvoked");
            CompleteInvoked = true;
            (bool has, object? value) = Callback(Request["Complete"], [this], false);
            if (has) Data = value;
        }
        catch (Exception error) { AnalysisComplete = false; AddError("CompleteCallbackFailed", "Complete", error.Message); }
        finally { CompleteAllocation = allocation.Stop(); CallbackMs += watch.Elapsed.TotalMilliseconds; }
    }

    /// <summary>Drives the separate native process without retaining its streams.</summary>
    internal void RunNative()
    {
        Hashtable request = Request;
        string workingDirectory = Path.GetFullPath(Convert.ToString(QuietRuntime.Unwrap(request["WorkingDirectory"]), CultureInfo.InvariantCulture)!);
        object[] size = ((IEnumerable)request["TerminalSize"]!).Cast<object>().ToArray();
        var start = new Hashtable
        {
            ["Action"] = "start", ["InvocationId"] = InvocationId, ["FilePath"] = request["FilePath"],
            ["ArgumentList"] = ((IEnumerable)request["ArgumentList"]!).Cast<object?>().Select(item => Convert.ToString(Unwrap(item), CultureInfo.InvariantCulture) ?? "").ToArray(),
            ["WorkingDirectory"] = workingDirectory, ["Environment"] = request["Environment"], ["Transport"] = request["Transport"],
            ["Columns"] = Convert.ToInt32(Unwrap(size[0]), CultureInfo.InvariantCulture), ["Rows"] = Convert.ToInt32(Unwrap(size[1]), CultureInfo.InvariantCulture),
            ["TimeoutSeconds"] = Convert.ToDouble(QuietRuntime.Unwrap(request["TimeoutSeconds"]), CultureInfo.InvariantCulture),
            ["SuccessExitCodes"] = ((IEnumerable)request["SuccessExitCodes"]!).Cast<object>().ToArray(),
            ["KeepInputOpen"] = request.ContainsKey("InputBytes") || request.ContainsKey("InputText") || request.ContainsKey("Interaction"),
        };
        if (request.ContainsKey("InputPath"))
        {
            string inputPath = Path.GetFullPath(Convert.ToString(QuietRuntime.Unwrap(request["InputPath"]), CultureInfo.InvariantCulture)!, workingDirectory);
            if (PathGuard.HasLinkedAncestor(inputPath)) throw new InvalidOperationException("QuietInputPathLinkRejected");
            start["InputPath"] = inputPath;
        }
        start["ReadBlockBytes"] = Convert.ToInt32(QuietRuntime.Unwrap(request["ReadBlockBytes"]), CultureInfo.InvariantCulture);
        start["DrainTimeoutSeconds"] = Convert.ToDouble(QuietRuntime.Unwrap(request["DrainTimeoutSeconds"]), CultureInfo.InvariantCulture);
        StartState = "StartRequested";
        Send(start, []);
        NativeStarted = true;
        StartState = "StartAcknowledged";
        if (request.ContainsKey("InputBytes")) { WriteBytes(LanguagePrimitives.ConvertTo<byte[]>(request["InputBytes"])); CompleteInput(); }
        else if (request.ContainsKey("InputText")) { WriteText(Convert.ToString(QuietRuntime.Unwrap(request["InputText"]), CultureInfo.InvariantCulture) ?? ""); CompleteInput(); }
        else if (request.ContainsKey("Interaction"))
        {
            try
            {
                if (Unwrap(request["Interaction"]) is not ScriptBlock interaction) throw new InvalidOperationException("InteractionMustBeScriptBlock");
                if (interaction.Invoke(this).Count > 0) throw new InvalidOperationException("InteractionUnexpectedOutput");
            }
            catch (Exception error)
            {
                AnalysisComplete = false;
                AddError("InteractionFailed", "Interaction", error.Message);
                Cancel();
            }
        }
        while (!Completed)
        {
            if ((request.ContainsKey("CancellationFile") && PathExists(Convert.ToString(QuietRuntime.Unwrap(request["CancellationFile"]), CultureInfo.InvariantCulture)!)) || (request.ContainsKey("CancellationToken") && IsCancelled(request["CancellationToken"]))) Cancel();
            ReadEvent();
        }
        CompleteStreams();
        object? execution = Execution;
        Sources[InvocationId] = new OrderedDictionary
        {
            ["InvocationId"] = InvocationId, ["Role"] = request["Role"],
            ["StdoutBytesRead"] = PropertyReader.Get(execution, "StdoutBytesRead"), ["StderrBytesRead"] = PropertyReader.Get(execution, "StderrBytesRead"),
            ["TerminalBytesRead"] = PropertyReader.Get(execution, "TerminalBytesRead"), ["StdinBytesWritten"] = PropertyReader.Get(execution, "StdinBytesWritten"),
            ["Complete"] = PropertyReader.Get(execution, "SourceComplete"),
        };
        Transition("Completing");
        CompleteAnalysis();
    }

    /// <summary>Appends one diagnostic record.</summary>
    internal void AddError(string code, string phase, string message) => Errors.Add(new Hashtable { ["Code"] = code, ["Phase"] = phase, ["Message"] = message });

    /// <summary>Builds the transient event object handed to output callbacks.</summary>
    private static PSObject NewEvent(string stream, string kind, byte[]? bytes, string? text, int? byteCount)
    {
        var evt = new PSObject();
        evt.Properties.Add(new PSNoteProperty("Stream", stream));
        evt.Properties.Add(new PSNoteProperty("Kind", kind));
        evt.Properties.Add(new PSNoteProperty("Bytes", bytes));
        evt.Properties.Add(new PSNoteProperty("ByteCount", byteCount));
        evt.Properties.Add(new PSNoteProperty("Text", text));
        return evt;
    }

    /// <summary>Dispatches a transient event without retaining it in the runtime.</summary>
    private void OutputCallback(PSObject evt)
    {
        if (!AnalysisComplete || !Request.ContainsKey("Output")) return;
        var watch = Stopwatch.StartNew();
        try { Callback(Request["Output"], [evt, this], true); }
        catch (Exception error) { AnalysisComplete = false; AddError("OutputCallbackFailed", "Output", error.Message); }
        finally { CallbackMs += watch.Elapsed.TotalMilliseconds; }
    }

    /// <summary>Records one event and pushes it to every attached listener, in order; never affects <see cref="AnalysisComplete"/> or the invocation's <c>Outcome</c>.</summary>
    /// <param name="evt">Caller-owned event value; normalized the same way as a callback return value.</param>
    public void Emit(object? evt)
    {
        object? value = Normalize(evt);
        Events.Add(value);
        if (Listeners.Length == 0) return;
        for (int i = 0; i < Listeners.Length; i++)
        {
            if (disabledListeners?.Contains(i) == true) continue;
            var watch = Stopwatch.StartNew();
            try { Callback(Listeners[i], [value!, this], true); }
            catch (Exception error) { (disabledListeners ??= []).Add(i); AddError("ListenerFailed", "Emit", $"Listener[{i}]: {error.Message}"); }
            finally { CallbackMs += watch.Elapsed.TotalMilliseconds; }
        }
    }

    /// <summary>Applies the same PSObject-unwrapping rule used for a callback's return value, so <see cref="Events"/> and listener payloads follow the same convention as -Complete.</summary>
    private static object? Normalize(object? evt) => evt is PSObject wrapped ? (wrapped.BaseObject is PSCustomObject ? wrapped : wrapped.BaseObject) : evt;

    /// <summary>Enforces zero/one callback emissions and preserves a single array as one business value.</summary>
    /// <param name="callback">Caller-owned script block, including its lexical scope.</param>
    /// <param name="arguments">Callback arguments.</param>
    /// <param name="noOutput">Requires zero emissions for streaming consumers.</param>
    internal static (bool HasValue, object? Value) Callback(object? callback, object[] arguments, bool noOutput)
    {
        if (Unwrap(callback) is not ScriptBlock block) throw new InvalidOperationException("CallbackMustBeScriptBlock");
        var values = block.Invoke(arguments);
        if (values.Count > 1 || (noOutput && values.Count > 0)) throw new InvalidOperationException("CallbackUnexpectedOutput");
        if (values.Count == 0) return (false, null);
        PSObject first = values[0];
        return (true, first?.BaseObject is PSCustomObject ? first : first?.BaseObject);
    }

    /// <summary>Removes a PowerShell wrapper from a plain value.</summary>
    internal static object? Unwrap(object? value) => value is PSObject wrapped ? wrapped.BaseObject : value;

    /// <summary>Accepts a single ScriptBlock or a sequence of ScriptBlock values for -Listeners; rejects anything else.</summary>
    /// <param name="value">Raw -Listeners argument.</param>
    internal static ScriptBlock[] NormalizeListeners(object? value)
    {
        object? unwrapped = Unwrap(value);
        if (unwrapped is ScriptBlock single) return [single];
        if (unwrapped is IEnumerable sequence and not string)
            return sequence.Cast<object?>().Select(item => Unwrap(item) as ScriptBlock ?? throw new InvalidOperationException("ListenerMustBeScriptBlock")).ToArray();
        throw new InvalidOperationException("ListenerMustBeScriptBlock");
    }

    /// <summary>Equivalent of Test-Path -LiteralPath for files and directories.</summary>
    private static bool PathExists(string path) => File.Exists(path) || Directory.Exists(path);

    /// <summary>Reads IsCancellationRequested from a token or a token-like object.</summary>
    private static bool IsCancelled(object? token) => Unwrap(token) is CancellationToken real ? real.IsCancellationRequested : LanguagePrimitives.IsTrue(PropertyReader.Get(token, "IsCancellationRequested"));
}

/// <summary>Builds caller-local runtimes bound to the engine exchange; shared by the cmdlets that start invocations.</summary>
public abstract class RuntimeCmdlet : EngineCmdlet
{
    /// <summary>Creates one fresh runtime for a validated request.</summary>
    /// <param name="request">Explicit call options and native argument vector.</param>
    /// <param name="parent">Enclosing runtime, if the call is nested.</param>
    /// <param name="sessionId">Identity of the PowerShell session.</param>
    internal QuietRuntime CreateRuntime(Hashtable request, QuietRuntime? parent, object? sessionId)
    {
        string id = Guid.NewGuid().ToString("N");
        var runtime = new QuietRuntime
        {
            InvocationId = id, ParentId = parent?.InvocationId, RootId = parent?.RootId ?? id, SessionId = sessionId, Request = request,
            Context = request.ContainsKey("Context") ? request["Context"] : parent?.Context,
            State = request.ContainsKey("State") ? request["State"] : new Hashtable(),
        };
        if (request.ContainsKey("Data")) runtime.Data = request["Data"];
        runtime.Listeners = request.ContainsKey("Listeners") ? QuietRuntime.NormalizeListeners(request["Listeners"]) : [];
        if (request.ContainsKey("UI") && LanguagePrimitives.IsTrue(request["UI"]))
        {
            int maxLines = 1;
            if (request.ContainsKey("MaxLines"))
            {
                maxLines = Convert.ToInt32(QuietRuntime.Unwrap(request["MaxLines"]), CultureInfo.InvariantCulture);
                if (maxLines <= 0) throw new InvalidOperationException("MaxLinesMustBePositive");
            }
            IUiSurface surface;
            try { surface = AnsiConsole.Profile.Capabilities.Interactive ? new SpectreLiveSurface() : new AppendOnlySurface(); }
            catch (Exception error)
            {
                // A second -UI call concurrently Live in this same process (Spectre forbids nested Live/Status/Progress
                // sessions) falls back to the append-only surface rather than failing the whole invocation.
                runtime.AddError("UiRenderUnavailable", "Ui", error.Message);
                surface = new AppendOnlySurface();
            }
            runtime.Ui = new QuietUiRenderer(maxLines, surface, runtime.AddError);
            string directory = Convert.ToString(QuietRuntime.Unwrap(request["WorkingDirectory"]), CultureInfo.InvariantCulture) ?? CurrentDirectory;
            string tool = Path.GetFileName(Convert.ToString(QuietRuntime.Unwrap(request["FilePath"]), CultureInfo.InvariantCulture) ?? "native");
            runtime.Ui.SetHeader([$"Project: {Path.GetFileName(directory)} | Task: {tool}", directory]);
        }
        string? name = request.ContainsKey("RecallName") ? Convert.ToString(QuietRuntime.Unwrap(request["RecallName"]), CultureInfo.InvariantCulture) : null;
        if (request.ContainsKey("SaveRecall") && LanguagePrimitives.IsTrue(request["SaveRecall"]))
        {
            string root = RecallCommandSupport.ResolveRoot(request.ContainsKey("RecallRoot") ? Convert.ToString(QuietRuntime.Unwrap(request["RecallRoot"]), CultureInfo.InvariantCulture) : "", CurrentDirectory);
            runtime.RecallWriter = RecallStore.CreateAsync(root, name, RecallSettings(request)).GetAwaiter().GetResult();
        }
        if (request.ContainsKey("RecallOptions"))
            runtime.RecallCollector = new RecallCollector((RecallOptions)LanguagePrimitives.ConvertTo(request["RecallOptions"], typeof(RecallOptions)), runtime.RecallWriter?.RecallId, name);
        runtime.Exchange = BuildExchange();
        return runtime;
    }

    /// <summary>Projects only inert analysis settings, without native arguments or callbacks.</summary>
    /// <param name="request">Original request.</param>
    internal static RecallAnalysisSettings RecallSettings(Hashtable request) => new(
        Convert.ToString(QuietRuntime.Unwrap(request["StdoutMode"]), CultureInfo.InvariantCulture) == "Bytes" ? "Bytes" : "Text",
        Convert.ToString(QuietRuntime.Unwrap(request["StderrMode"]), CultureInfo.InvariantCulture) == "Bytes" ? "Bytes" : "Text",
        request.ContainsKey("RecordDelimiter") ? Convert.ToString(QuietRuntime.Unwrap(request["RecordDelimiter"]), CultureInfo.InvariantCulture) : null,
        Convert.ToInt32(QuietRuntime.Unwrap(request["MaxRecordBytes"]), CultureInfo.InvariantCulture));

    /// <summary>Binds the exchange to the engine, honoring a session-level Send-QuietRequest function (test seam).</summary>
    private Func<Hashtable, byte[], EngineReply> BuildExchange()
    {
        if (FindFunction("Send-QuietRequest") is { } seam)
            return (header, payload) =>
            {
                var output = seam.ScriptBlock.Invoke(header, payload);
                PSObject reply = output.FirstOrDefault() ?? throw new InvalidOperationException("EmptyEngineReply");
                return new EngineReply(PropertyReader.Get(reply, "Header")!, LanguagePrimitives.ConvertTo<byte[]>(PropertyReader.Get(reply, "Payload") ?? Array.Empty<byte>()));
            };
        double timeout = IpcTimeout;
        string hosting = Convert.ToString(QuietRuntime.Unwrap(Setting("engine.hosting")), CultureInfo.InvariantCulture) ?? "";
        string database = Convert.ToString(QuietRuntime.Unwrap(Setting("telemetry.database")), CultureInfo.InvariantCulture) ?? "";
        return (header, payload) => EngineClient.Send(QuietSession.Engine ?? EngineLifecycle.Start(hosting, database, timeout), header, payload, timeout);
    }
}

/// <summary>Creates one fresh caller-local runtime and attaches the engine exchange; internal to the module.</summary>
[Cmdlet(VerbsCommon.New, "QuietRuntime")]
[OutputType(typeof(QuietRuntime))]
public sealed class NewQuietRuntimeCommand : RuntimeCmdlet
{
    /// <summary>Explicit call options and native argument vector.</summary>
    [Parameter(Position = 0, Mandatory = true)]
    public Hashtable Request { get; set; } = new();

    /// <summary>Enclosing runtime, if the call is nested.</summary>
    [Parameter(Position = 1)]
    public QuietRuntime? Parent { get; set; }

    /// <summary>Identity of the PowerShell session.</summary>
    [Parameter(Position = 2)]
    public object? SessionId { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(CreateRuntime(Request, Parent, SessionId)); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}
/// <summary>Runs the native event loop of a prepared runtime; internal to the module.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "QuietNative")]
public sealed class InvokeQuietNativeCommand : QuietCmdlet
{
    /// <summary>Runtime created by New-QuietRuntime.</summary>
    [Parameter(Position = 0, Mandatory = true)]
    public QuietRuntime Runtime { get; set; } = null!;

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { Runtime.RunNative(); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}
