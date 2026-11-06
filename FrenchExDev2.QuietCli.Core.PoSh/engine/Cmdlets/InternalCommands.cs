using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Resolves one effective setting using the shared precedence rules; internal to the module.</summary>
[Cmdlet(VerbsCommon.Get, "QuietSetting")]
public sealed class GetQuietSettingCommand : QuietCmdlet
{
    /// <summary>Closed section.key setting name.</summary>
    [Parameter(Position = 0, Mandatory = true)]
    public string Name { get; set; } = "";

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(ConfigurationService.Snapshot(CurrentDirectory).Values[Name]); }
        catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}

/// <summary>Returns the live session snapshot, whose values callers may adjust for the session; internal to the module.</summary>
[Cmdlet(VerbsCommon.Get, "QuietConfigurationSnapshot")]
[OutputType(typeof(ConfigurationSnapshot))]
public sealed class GetQuietConfigurationSnapshotCommand : QuietCmdlet
{
    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(ConfigurationService.Snapshot(CurrentDirectory)); }
        catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}

/// <summary>Checks pinned resources before they are loaded; hashes do not authenticate the distributor. Internal to the module.</summary>
[Cmdlet(VerbsLifecycle.Assert, "QuietResources")]
public sealed class AssertQuietResourcesCommand : QuietCmdlet
{
    /// <summary>Optional single managed resource for an explicit load.</summary>
    [Parameter(Position = 0)]
    public string? RelativePath { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { ResourceVerifier.Verify(QuietSession.Root, RelativePath); }
        catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}
