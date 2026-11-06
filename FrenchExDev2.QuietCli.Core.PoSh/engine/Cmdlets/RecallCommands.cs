using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Shared Recall command rules: capture resolution and store-root selection.</summary>
public static class RecallCommandSupport
{
    /// <summary>Accepts an immutable capture or a native result that carries one.</summary>
    /// <param name="input">Capture or native result, possibly wrapped in a <see cref="PSObject"/>.</param>
    /// <returns>The retained capture.</returns>
    /// <exception cref="InvalidOperationException"><c>RecallCaptureRequired</c> when no capture is present.</exception>
    public static RecallCapture ResolveCapture(object? input)
    {
        object? value = input is PSObject wrapped ? wrapped.BaseObject : input;
        if (value is RecallCapture direct) return direct;
        object? nested = PSObject.AsPSObject(input ?? new object()).Properties["Recall"]?.Value;
        if (nested is PSObject nestedWrapped) nested = nestedWrapped.BaseObject;
        return nested as RecallCapture ?? throw new InvalidOperationException("RecallCaptureRequired");
    }

    /// <summary>Resolves an explicit store root, otherwise the configured or default durable location.</summary>
    /// <param name="path">Optional explicit store root, relative to <paramref name="currentDirectory"/>.</param>
    /// <param name="currentDirectory">Caller's filesystem location.</param>
    /// <returns>An absolute store root.</returns>
    public static string ResolveRoot(string? path, string currentDirectory)
    {
        if (!string.IsNullOrEmpty(path)) return Path.GetFullPath(path, currentDirectory);
        string? configured = ConfigurationService.Snapshot(currentDirectory).Values["recall.root"] as string;
        return string.IsNullOrEmpty(configured) ? RecallStore.DefaultRoot : configured;
    }
}

/// <summary>Base for Recall cmdlets: capture and root resolution on the caller's location.</summary>
public abstract class RecallCmdlet : QuietCmdlet
{
    /// <summary>Resolves the capture carried by <paramref name="input"/>.</summary>
    protected static RecallCapture Capture(object? input) => RecallCommandSupport.ResolveCapture(input);

    /// <summary>Resolves the effective store root.</summary>
    protected string Root(string? path) => RecallCommandSupport.ResolveRoot(path, CurrentDirectory);

    /// <summary>Resolves a user path to an absolute provider path without requiring it to exist.</summary>
    protected string Unresolved(string path) => SessionState.Path.GetUnresolvedProviderPathFromPSPath(path);

    /// <summary>True when the named parameter was supplied explicitly.</summary>
    protected bool Bound(string name) => MyInvocation.BoundParameters.ContainsKey(name);
}

/// <summary>Reads bounded native evidence with explicit event and byte budgets.</summary>
[Cmdlet(VerbsCommon.Get, "QuietRecall")]
public sealed class GetQuietRecallCommand : RecallCmdlet
{
    /// <summary>Native result or capture.</summary>
    [Parameter(Mandatory = true, Position = 0)] public object? InputObject { get; set; }
    /// <summary>First original block sequence.</summary>
    [Parameter(Position = 1)] public long Sequence { get; set; } = 1;
    /// <summary>Optional native stream filter.</summary>
    [Parameter(Position = 2)] [ValidateSet("stdout", "stderr", "terminal")] public string? Stream { get; set; }
    /// <summary>First stream byte offset.</summary>
    [Parameter(Position = 3)] public long Offset { get; set; }
    /// <summary>Selected stream byte range.</summary>
    [Parameter(Position = 4)] public long ByteCount { get; set; } = long.MaxValue;
    /// <summary>Neighbor events on each side.</summary>
    [Parameter(Position = 5)] public int Context { get; set; }
    /// <summary>Delivered event budget.</summary>
    [Parameter(Position = 6)] public int MaxItems { get; set; } = 20;
    /// <summary>Delivered native byte budget; object metadata is additional.</summary>
    [Parameter(Position = 7)] public long MaxOutputBytes { get; set; } = 4096;
    /// <summary>Optional validated evidence reference to resolve against this capture.</summary>
    [Parameter(Position = 8)] public object? Reference { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try {
            RecallCapture capture = Capture(InputObject);
            string? stream = string.IsNullOrEmpty(Stream) ? null : Stream;
            long offset = Offset, count = ByteCount;
            if (Reference != null) {
                PSObject reference = PSObject.AsPSObject(Reference);
                if (!string.Equals((string?)reference.Properties["CaptureId"]?.Value, capture.CaptureId, StringComparison.Ordinal)) throw new InvalidOperationException("RecallReferenceCaptureMismatch");
                stream = (string?)reference.Properties["Stream"]?.Value;
                offset = Convert.ToInt64(reference.Properties["Offset"]?.Value);
                count = Convert.ToInt64(reference.Properties["ByteCount"]?.Value);
                RecallReader.Reference(capture, stream!, offset, count);
            }
            WriteObject(RecallReader.Read(capture, Sequence, stream, offset, count, Context, MaxItems, MaxOutputBytes), false);
        } catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}

/// <summary>Creates a content-free reference only for a completely retained byte range.</summary>
[Cmdlet(VerbsCommon.New, "QuietRecallReference")]
public sealed class NewQuietRecallReferenceCommand : RecallCmdlet
{
    /// <summary>Native result or capture.</summary>
    [Parameter(Mandatory = true, Position = 0)] public object? InputObject { get; set; }
    /// <summary>Native stream.</summary>
    [Parameter(Mandatory = true, Position = 1)] [ValidateSet("stdout", "stderr", "terminal")] public string Stream { get; set; } = "";
    /// <summary>First evidence byte offset.</summary>
    [Parameter(Mandatory = true, Position = 2)] public long Offset { get; set; }
    /// <summary>Positive evidence byte length.</summary>
    [Parameter(Mandatory = true, Position = 3)] public long ByteCount { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(RecallReader.Reference(Capture(InputObject), Stream, Offset, ByteCount), false); }
        catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}

/// <summary>Explicitly exports inert capture bytes and a versioned integrity manifest.</summary>
[Cmdlet(VerbsData.Export, "QuietRecall")]
public sealed class ExportQuietRecallCommand : RecallCmdlet
{
    /// <summary>Native result or immutable capture.</summary>
    [Parameter(Mandatory = true, Position = 0)] public object? InputObject { get; set; }
    /// <summary>New directory or explicit ZIP path; existing files are never overwritten.</summary>
    [Parameter(Mandatory = true, Position = 1)] public string Path { get; set; } = "";
    /// <summary>Writes a ZIP64 transport instead of a working directory.</summary>
    [Parameter] public SwitchParameter Zip { get; set; }
    /// <summary>Exact zlib level from zero to nine; requires Zip.</summary>
    [Parameter(Position = 2)] [ValidateRange(0, 9)] public int Compress { get; set; } = 6;
    /// <summary>Returns measured transport bytes and actual compression ratio.</summary>
    [Parameter] public SwitchParameter PassThru { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try {
            if (Bound(nameof(Compress)) && !Zip) throw new InvalidOperationException("CompressRequiresZip");
            RecallTransportResult transport = RecallArchive.ExportAsync(Capture(InputObject), Unresolved(Path), Zip, Compress).GetAwaiter().GetResult();
            if (PassThru) WriteObject(transport, false);
        } catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}

/// <summary>Imports verified inert capture data within an explicit retained-byte budget.</summary>
[Cmdlet(VerbsData.Import, "QuietRecall")]
public sealed class ImportQuietRecallCommand : RecallCmdlet
{
    /// <summary>Archive path.</summary>
    [Parameter(Mandatory = true, Position = 0)] public string Path { get; set; } = "";
    /// <summary>Optional native-byte ceiling; All uses bounded-memory disk streaming.</summary>
    [Parameter(Position = 1)] public object MaxBytes { get; set; } = "All";
    /// <summary>Destination store for a ZIP import; a directory is opened in place.</summary>
    [Parameter(Position = 2)] public string? RecallRoot { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try {
            long? budget = RecallOptions.ParseSize(Convert.ToString(MaxBytes is PSObject wrapped ? wrapped.BaseObject : MaxBytes, System.Globalization.CultureInfo.InvariantCulture) ?? "All");
            WriteObject(RecallArchive.ImportAsync(Unresolved(Path), budget, Root(RecallRoot)).GetAwaiter().GetResult(), false);
        } catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}

/// <summary>Explicitly saves existing evidence into the durable catalog, optionally producing ZIP transport.</summary>
[Cmdlet(VerbsData.Save, "QuietRecall")]
public sealed class SaveQuietRecallCommand : RecallCmdlet
{
    /// <summary>Local result or capture; only retained bytes can be saved after execution.</summary>
    [Parameter(Mandatory = true, Position = 0)] public object? InputObject { get; set; }
    /// <summary>Optional nonunique display name.</summary>
    [Parameter(Position = 1)] public string? RecallName { get; set; }
    /// <summary>Explicit store root; defaults to durable user data.</summary>
    [Parameter(Position = 2)] public string? RecallRoot { get; set; }
    /// <summary>Also produces an adjacent ZIP64 transport.</summary>
    [Parameter] public SwitchParameter Zip { get; set; }
    /// <summary>Exact zlib level zero through nine; requires Zip.</summary>
    [Parameter(Position = 3)] [ValidateRange(0, 9)] public int Compress { get; set; } = 6;

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try {
            if (Bound(nameof(Compress)) && !Zip) throw new InvalidOperationException("CompressRequiresZip");
            RecallCapture capture = Capture(InputObject);
            string root = Root(RecallRoot);
            string? name = Bound(nameof(RecallName)) ? RecallName : capture.RecallName;
            RecallCapture saved = RecallStore.SaveDirectoryAsync(capture, System.IO.Path.Combine(root, capture.RecallId), name).GetAwaiter().GetResult();
            if (Zip) RecallArchive.ExportAsync(saved, saved.StoragePath + ".zip", true, Compress).GetAwaiter().GetResult();
            WriteObject(saved, false);
        } catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}

/// <summary>Finds durable recalls using metadata only, without reading native content.</summary>
[Cmdlet(VerbsCommon.Get, "QuietSavedRecall")]
public sealed class GetQuietSavedRecallCommand : RecallCmdlet
{
    /// <summary>Optional exact identity.</summary>
    [Parameter(Position = 0)] public string? RecallId { get; set; }
    /// <summary>Optional wildcard display-name filter.</summary>
    [Parameter(Position = 1)] public string? RecallName { get; set; }
    /// <summary>Explicit store root.</summary>
    [Parameter(Position = 2)] public string? RecallRoot { get; set; }
    /// <summary>Maximum returned metadata rows.</summary>
    [Parameter(Position = 3)] [ValidateRange(1, 10000)] public int MaxItems { get; set; } = 20;

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try {
            string root = Root(RecallRoot);
            string? id = string.IsNullOrEmpty(RecallId) ? null : RecallStore.NormalizeId(RecallId);
            var pattern = string.IsNullOrEmpty(RecallName) ? null : new WildcardPattern(RecallName, WildcardOptions.IgnoreCase | WildcardOptions.CultureInvariant);
            int emitted = 0;
            foreach (RecallSavedInfo info in RecallStore.ListAsync(root).GetAwaiter().GetResult()) {
                if (emitted >= MaxItems) break;
                if (id != null && !string.Equals(info.RecallId, id, StringComparison.OrdinalIgnoreCase)) continue;
                if (pattern != null && (info.RecallName == null || !pattern.IsMatch(info.RecallName))) continue;
                WriteObject(info);
                emitted++;
            }
        } catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}
