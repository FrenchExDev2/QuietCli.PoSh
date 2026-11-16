using System.Collections;
using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Returns detached effective values and their origins without starting an engine.</summary>
[Cmdlet(VerbsCommon.Get, "QuietCliConfiguration")]
public sealed class GetQuietCliConfigurationCommand : QuietCmdlet
{
    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(Describe(ConfigurationService.Snapshot(CurrentDirectory))); }
        catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }

    /// <summary>Builds the public report object for a snapshot.</summary>
    /// <param name="snapshot">Validated session snapshot.</param>
    internal static PSObject Describe(ConfigurationSnapshot snapshot)
    {
        var origins = new PSObject();
        foreach (DictionaryEntry entry in snapshot.Origins) origins.Properties.Add(new PSNoteProperty((string)entry.Key, entry.Value));
        var report = new PSObject();
        report.Properties.Add(new PSNoteProperty("Path", snapshot.Path));
        report.Properties.Add(new PSNoteProperty("Configuration", ConfigurationService.BuildView(snapshot.Values)));
        report.Properties.Add(new PSNoteProperty("Origins", origins));
        return report;
    }
}
