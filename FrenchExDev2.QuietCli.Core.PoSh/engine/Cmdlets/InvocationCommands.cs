using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Runtime.CompilerServices;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Process-wide call stack and offline-analysis depth shared by live invocations and recall replays.</summary>
public static class QuietCallState
{
    /// <summary>Invocations currently in progress, innermost on top.</summary>
    private static readonly Stack<QuietRuntime> Calls = new();

    /// <summary>Greater than zero while a recall replay runs; native execution is refused meanwhile.</summary>
    public static int RecallDepth;

    /// <summary>Innermost invocation in progress, or null at the root.</summary>
    public static QuietRuntime? Current => Calls.Count > 0 ? Calls.Peek() : null;

    /// <summary>Number of invocations in progress.</summary>
    public static int Depth => Calls.Count;

    /// <summary>Registers an invocation as the innermost one.</summary>
    /// <param name="runtime">Invocation being started.</param>
    internal static void Push(QuietRuntime runtime) => Calls.Push(runtime);

    /// <summary>Removes the innermost invocation.</summary>
    internal static void Pop() => Calls.Pop();
}

/// <summary>Getter-only result properties that do not retain the invocation runtime.</summary>
public static class FinalProperties
{
    /// <summary>Values stored per result object.</summary>
    private static readonly ConditionalWeakTable<PSObject, Dictionary<string, object?>> Values = new();

    /// <summary>Installs a read-only metadata property on a result, replacing any earlier member of that name.</summary>
    /// <param name="target">Local result envelope.</param>
    /// <param name="name">Execution, Completeness or Recall.</param>
    /// <param name="value">Detached snapshot, never business Data.</param>
    internal static void Set(PSObject target, string name, object? value)
    {
        Values.GetOrCreateValue(target)[name] = value;
        target.Properties.Remove(name);
        string method = "Get" + name;
        target.Properties.Add(new PSCodeProperty(name, typeof(FinalProperties).GetMethod(method)!));
    }

    private static object? Read(PSObject target, string name) => Values.TryGetValue(target, out var map) && map.TryGetValue(name, out var value) ? value : null;

    /// <summary>Getter of the Execution snapshot.</summary>
    /// <param name="target">Result.</param>
    public static object? GetExecution(PSObject target) => Read(target, "Execution");

    /// <summary>Getter of the Completeness snapshot.</summary>
    /// <param name="target">Result.</param>
    public static object? GetCompleteness(PSObject target) => Read(target, "Completeness");

    /// <summary>Getter of the Recall capture.</summary>
    /// <param name="target">Result.</param>
    public static object? GetRecall(PSObject target) => Read(target, "Recall");
}

/// <summary>Resolves an executable the way command discovery does for applications, without scanning modules.</summary>
internal static class ApplicationResolver
{
    /// <summary>Finds the full path of an executable.</summary>
    /// <param name="name">Bare command name or path.</param>
    /// <param name="directory">Directory that anchors relative paths.</param>
    internal static string Resolve(string name, string directory)
    {
        if (name.Length > 0)
        {
            bool hasDirectory = name.Contains('/') || name.Contains(Path.DirectorySeparatorChar) || Path.IsPathRooted(name);
            IEnumerable<string> roots = hasDirectory ? [Path.GetDirectoryName(Path.GetFullPath(name, directory)) ?? directory] : (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
            string leaf = hasDirectory ? Path.GetFileName(name) : name;
            foreach (string root in roots)
            {
                foreach (string candidate in Candidates(root, leaf))
                    if (File.Exists(candidate) && IsExecutable(candidate)) return Path.GetFullPath(candidate);
            }
        }
        throw new CommandNotFoundException($"The term '{name}' is not recognized as a name of a cmdlet, function, script file, or executable program.");
    }

    private static IEnumerable<string> Candidates(string root, string leaf)
    {
        if (!OperatingSystem.IsWindows()) { yield return Path.Combine(root, leaf); yield break; }
        string[] extensions = (Environment.GetEnvironmentVariable("PATHEXT") ?? ".COM;.EXE;.BAT;.CMD").Split(';', StringSplitOptions.RemoveEmptyEntries);
        string extension = Path.GetExtension(leaf);
        if (extension.Length > 0 && extensions.Contains(extension, StringComparer.OrdinalIgnoreCase)) yield return Path.Combine(root, leaf);
        foreach (string suffix in extensions) yield return Path.Combine(root, leaf + suffix);
    }

    private static bool IsExecutable(string path) =>
        OperatingSystem.IsWindows() || (File.GetUnixFileMode(path) & (UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute)) != 0;
}

/// <summary>Owns one caller-local invocation lifecycle: native execution or handler, result envelope, telemetry and delivery.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "QuietCall")]
public sealed class InvokeQuietCallCommand : DeliveryCmdlet
{
    /// <summary>Validated facade options.</summary>
    [Parameter(Position = 0, Mandatory = true)]
    public Hashtable Request { get; set; } = new();

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { if (Run(Request) is { } output) WriteObject(output); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }

    /// <summary>Evaluates zero-argument factories on a copy so each real call gets fresh business values.</summary>
    internal static Hashtable ApplyFactories(Hashtable request)
    {
        var copy = (Hashtable)request.Clone();
        foreach (string name in new[] { "Data", "State" })
        {
            string factory = name + "Factory";
            if (!copy.ContainsKey(factory)) continue;
            if (QuietRuntime.Unwrap(copy[factory]) is not ScriptBlock block) throw new InvalidOperationException("CallbackMustBeScriptBlock");
            var values = block.Invoke();
            if (values.Count != 1) throw new InvalidOperationException("QuietFactoryMustReturnOneValue: " + factory);
            PSObject first = values[0];
            if (name == "State" && first?.BaseObject is not Hashtable) throw new InvalidOperationException("QuietStateFactoryMustReturnHashtable");
            copy[name] = first?.BaseObject is PSCustomObject ? first : first?.BaseObject;
            copy.Remove(factory);
        }
        return copy;
    }

    private static string Text(object? value) => Convert.ToString(QuietRuntime.Unwrap(value), CultureInfo.InvariantCulture) ?? "";

    private static bool Flag(object? execution, string name) => execution is not null && LanguagePrimitives.IsTrue(PropertyReader.Get(execution, name));

    private static RecallSourceStatus? StatusOf(object? execution) => execution is null ? null : new RecallSourceStatus(
        Text(PropertyReader.Get(execution, "Outcome")),
        PropertyReader.Get(execution, "ExitCode") is { } code ? Convert.ToInt32(QuietRuntime.Unwrap(code), CultureInfo.InvariantCulture) : null,
        Text(PropertyReader.Get(execution, "EffectStatus")));

    private static PSObject Execution(string outcome, bool? complete, string effect, string? state = null, string? error = null)
    {
        var value = new PSObject();
        value.Properties.Add(new PSNoteProperty("Outcome", outcome));
        value.Properties.Add(new PSNoteProperty("ExitCode", null));
        value.Properties.Add(new PSNoteProperty("SourceComplete", complete));
        value.Properties.Add(new PSNoteProperty("EffectStatus", effect));
        if (state is not null) value.Properties.Add(new PSNoteProperty("State", state));
        if (error is not null) value.Properties.Add(new PSNoteProperty("Error", error));
        return value;
    }

    private static bool Rejected(Exception error)
    {
        for (Exception? current = error; current is not null; current = current.InnerException)
            if (current.Data.Contains("QuietCliRequestRejected")) return true;
        return false;
    }

    private static string StorageMessage(Exception error) => error is RuntimeException { InnerException: { } inner } ? inner.Message : error.Message;

    /// <summary>Runs one invocation and returns its result, or the delivered text.</summary>
    /// <param name="original">Validated facade options.</param>
    private object? Run(Hashtable original)
    {
        if (original.ContainsKey("RecallId")) return RunSavedRecall(original);
        if (QuietCallState.RecallDepth > 0) throw new InvalidOperationException("NativeExecutionUnavailableDuringRecall");
        Hashtable request = ApplyFactories(original);
        var allocation = new AllocationMeter();
        // A new root request may establish a fresh engine; no outstanding invocation is retried.
        if (QuietCallState.Depth == 0 && QuietSession.Engine is { Broken: true }) EngineLifecycle.Stop(IpcTimeout);
        QuietRuntime runtime = CreateRuntime(request, QuietCallState.Current, QuietSession.SessionId);
        var watch = System.Diagnostics.Stopwatch.StartNew();
        string outcome = "Success";
        PSObject result;
        QuietCallState.Push(runtime);
        try
        {
            try
            {
                runtime.Transition("Running");
                request["FilePath"] = ApplicationResolver.Resolve(Text(request["FilePath"]), CurrentDirectory);
                if (request.ContainsKey("Output") || request.ContainsKey("Complete")) runtime.RunNative();
                else
                {
                    Hashtable? handler = HandlerRegistry.Resolve(runtime);
                    if (handler is null && request.ContainsKey("SaveRecall") && LanguagePrimitives.IsTrue(request["SaveRecall"])) runtime.RunNative();
                    else if (handler is null)
                    {
                        outcome = "Unsupported";
                        runtime.Errors.Add(new Hashtable { ["Code"] = "HandlerNotFound", ["Phase"] = "Resolve", ["Message"] = "No compatible handler is registered. Supply -Output/-Complete for direct execution." });
                    }
                    else
                    {
                        runtime.Handler = handler;
                        (bool has, object? value) = QuietRuntime.Callback(handler["Execute"], [runtime], false);
                        if (has) runtime.Data = value;
                    }
                }
            }
            catch (Exception error) when (error is not PipelineStoppedException)
            {
                outcome = "Failed";
                runtime.AnalysisComplete = false;
                runtime.Errors.Add(new Hashtable { ["Code"] = "InvocationFailed", ["Phase"] = runtime.Lifecycle, ["Message"] = error.Message });
                if (!runtime.NativeStarted && runtime.StartState == "StartRequested")
                {
                    runtime.Execution = Execution("Failed", false, Rejected(error) ? "NotStarted" : "Unknown", "Finalized", "NativeStartUnconfirmed");
                    try { runtime.Send(new Hashtable { ["Action"] = "cancel", ["InvocationId"] = runtime.InvocationId }, []); } catch (Exception) { }
                }
                if (runtime.NativeStarted && !runtime.Completed)
                {
                    try
                    {
                        runtime.Send(new Hashtable { ["Action"] = "cancel", ["InvocationId"] = runtime.InvocationId }, []);
                        while (!runtime.Completed) runtime.ReadEvent();
                    }
                    catch (Exception) { runtime.Execution = Execution("Failed", false, "Unknown"); }
                }
            }
            if (runtime.Execution is not null && Text(PropertyReader.Get(runtime.Execution, "Outcome")) != "Success") outcome = Text(PropertyReader.Get(runtime.Execution, "Outcome"));
            RecallCapture? diskRecall = null;
            if (runtime.RecallWriter is { } writer)
            {
                try
                {
                    diskRecall = writer.CompleteAsync(Flag(runtime.Execution, "SourceComplete"), StatusOf(runtime.Execution)).GetAwaiter().GetResult();
                    if (request.ContainsKey("Zip") && LanguagePrimitives.IsTrue(request["Zip"]))
                    {
                        int level = request.ContainsKey("Compress") ? Convert.ToInt32(QuietRuntime.Unwrap(request["Compress"]), CultureInfo.InvariantCulture) : 6;
                        RecallArchive.ExportAsync(diskRecall, diskRecall.StoragePath + ".zip", true, level).GetAwaiter().GetResult();
                    }
                }
                catch (Exception error) when (error is not PipelineStoppedException)
                {
                    runtime.RecallSaveFailed = true;
                    diskRecall ??= writer.FailedSnapshot();
                    runtime.Errors.Add(new Hashtable { ["Code"] = "RecallSaveFailed", ["Phase"] = "SaveRecall", ["Message"] = error.Message });
                }
            }
            if (runtime.RecallSaveFailed && outcome == "Success") outcome = "Failed";
            if (!runtime.AnalysisComplete && outcome == "Success") outcome = "Failed";
            var issues = runtime.Children.Where(child => !string.Equals(Text(Members.Get(child, "Outcome")), "Success", StringComparison.OrdinalIgnoreCase)).ToList();
            if (issues.Count > 0 && outcome == "Success") outcome = Text(Members.Get(issues[0], "Outcome"));
            foreach (object child in runtime.Children)
                if (Members.Get(Members.Get(child, "Internal"), "Sources") is IDictionary sources)
                    foreach (object key in sources.Keys) runtime.Sources[key] = sources[key];
            bool sourceComplete = (runtime.Execution is null || Flag(runtime.Execution, "SourceComplete")) && runtime.Children.All(child => LanguagePrimitives.IsTrue(Members.Get(Members.Get(child, "Completeness"), "Source")));
            bool analysisComplete = runtime.AnalysisComplete && runtime.Children.All(child => LanguagePrimitives.IsTrue(Members.Get(Members.Get(child, "Completeness"), "Analysis")));
            if (runtime.Lifecycle == "Running") runtime.Transition("Draining");
            if (runtime.Lifecycle == "Draining") runtime.Transition("Completing");
            runtime.Transition("Finalized");
            string effect = runtime.Execution is not null && PSObject.AsPSObject(runtime.Execution).Properties["EffectStatus"] is { } property ? Text(property.Value)
                : runtime.Children.Any(child => Text(Members.Get(Members.Get(child, "Execution"), "EffectStatus")) == "Unknown") ? "Unknown" : "Observed";
            object? execution = CallerMetadata.Freeze(new Hashtable
            {
                ["State"] = "Finalized", ["Native"] = runtime.Execution, ["ElapsedMs"] = watch.Elapsed.TotalMilliseconds, ["CallbackMs"] = runtime.CallbackMs,
                ["Children"] = runtime.Children.Count, ["EffectStatus"] = effect,
                ["Issues"] = issues.Select(issue => new Hashtable
                {
                    ["InvocationId"] = Members.Get(issue, "InvocationId"), ["Outcome"] = Members.Get(issue, "Outcome"),
                    ["EffectStatus"] = Members.Get(Members.Get(issue, "Execution"), "EffectStatus"), ["Error"] = Members.Get(issue, "Error"),
                }).ToArray(),
            }, MetadataAdapter.Instance);
            object? completeness = CallerMetadata.Freeze(new Hashtable { ["Source"] = sourceComplete, ["Analysis"] = analysisComplete }, MetadataAdapter.Instance);
            Hashtable? handlerUsed = runtime.Handler as Hashtable;
            var measurement = new PSObject();
            foreach ((string name, object? value) in new (string, object?)[] { ("Status", "CountersOnly"), ("OutputBytes", null), ("OutputTokens", null), ("NativeTokens", null), ("ReductionBytes", null), ("StorageError", null), ("Allocation", null), ("CompleteAllocation", runtime.CompleteAllocation) })
                measurement.Properties.Add(new PSNoteProperty(name, value));
            var truncation = new PSObject();
            truncation.Properties.Add(new PSNoteProperty("Applied", false));
            truncation.Properties.Add(new PSNoteProperty("Reasons", Array.Empty<object>()));
            result = new PSObject();
            foreach ((string name, object? value) in new (string, object?)[]
            {
                ("SchemaVersion", 1), ("Summary", handlerUsed is not null ? handlerUsed["Summary"] : "Native command processed."), ("Outcome", outcome), ("Data", runtime.Data),
                ("InvocationId", runtime.InvocationId), ("ParentId", runtime.ParentId), ("RootId", runtime.RootId), ("SessionId", runtime.SessionId), ("Context", runtime.Context),
                ("Error", runtime.Errors.ToArray()), ("Truncation", truncation), ("Measurement", measurement), ("Deliveries", new List<object>()),
                ("Internal", new Hashtable(StringComparer.OrdinalIgnoreCase) { ["Sources"] = runtime.Sources, ["Request"] = request, ["Handler"] = runtime.Handler, ["Administrative"] = false }),
            })
                result.Properties.Add(new PSNoteProperty(name, value));
            result.TypeNames.Insert(0, "QuietCli2.Result");
            FinalProperties.Set(result, "Execution", execution);
            FinalProperties.Set(result, "Completeness", completeness);
            if (diskRecall is not null)
            {
                if (runtime.RecallCollector is { } collector) diskRecall.AttachMemorySnapshot(collector.Snapshot(Flag(runtime.Execution, "SourceComplete"), RecallSettings(request), diskRecall.SourceStatus));
                FinalProperties.Set(result, "Recall", diskRecall);
            }
            else if (runtime.RecallCollector is { } memory)
                FinalProperties.Set(result, "Recall", memory.Snapshot(Flag(runtime.Execution, "SourceComplete"), RecallSettings(request), StatusOf(runtime.Execution)));
            Members.SetNote(measurement, "Allocation", allocation.Stop());
            SaveInvocationMetadata(result, measurement);
        }
        finally
        {
            if (runtime.RecallWriter is { } disposable) disposable.DisposeAsync().AsTask().GetAwaiter().GetResult();
            QuietCallState.Pop();
            if (runtime.StartState != "NotStarted")
            {
                try { runtime.Send(new Hashtable { ["Action"] = "release", ["InvocationId"] = runtime.InvocationId }, []); } catch (Exception) { }
            }
        }
        QuietCallState.Current?.Children.Add(result);
        bool asObject = request.ContainsKey("AsObject") && LanguagePrimitives.IsTrue(request["AsObject"]);
        if (!request.ContainsKey("AsJson") && !request.ContainsKey("AsYaml") && QuietCallState.Depth > 0) asObject = true;
        if (asObject) return result;
        return Deliver(result, Convert.ToInt32(QuietRuntime.Unwrap(request["MaxItems"]), CultureInfo.InvariantCulture), Convert.ToInt32(QuietRuntime.Unwrap(request["MaxOutputBytes"]), CultureInfo.InvariantCulture),
            Text(request["Tokenizer"]), request.ContainsKey("AsYaml") && LanguagePrimitives.IsTrue(request["AsYaml"]));
    }

    /// <summary>Routes quiet -RecallId before native resolution, probing or lifecycle orchestration; replays offline and delivers.</summary>
    /// <param name="request">Validated replay-only facade options.</param>
    private object? RunSavedRecall(Hashtable request)
    {
        var replay = request["ReplayOptions"] as Hashtable ?? new Hashtable(StringComparer.OrdinalIgnoreCase);
        string root = request.ContainsKey("RecallRoot") ? Text(request["RecallRoot"]) : "";
        RecallCapture capture = RecallStore.OpenAsync(RecallCommandSupport.ResolveRoot(root, CurrentDirectory), Text(request["RecallId"])).GetAwaiter().GetResult();
        PSObject result = RecallReplayer.Replay(this, capture, null, RecallReplayOptions.Parse(replay));
        if (request.ContainsKey("AsObject") && LanguagePrimitives.IsTrue(request["AsObject"])) return result;
        return Deliver(result, Convert.ToInt32(QuietRuntime.Unwrap(request["MaxItems"]), CultureInfo.InvariantCulture), Convert.ToInt32(QuietRuntime.Unwrap(request["MaxOutputBytes"]), CultureInfo.InvariantCulture),
            Text(request["Tokenizer"]), request.ContainsKey("AsYaml") && LanguagePrimitives.IsTrue(request["AsYaml"]));
    }

    /// <summary>Saves counters without serializing or enumerating Result.Data.</summary>
    private void SaveInvocationMetadata(PSObject result, PSObject measurement)
    {
        if (!LanguagePrimitives.IsTrue(Setting("telemetry.enabled"))) return;
        try { SaveMetadata(new Hashtable { ["Action"] = "save", ["Kind"] = "invocation", ["Metadata"] = ResultMetadata.Get(result) }); }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            Members.SetNote(measurement, "StorageError", StorageMessage(error));
            Members.SetNote(measurement, "Status", "StorageUnavailable");
        }
    }
}
