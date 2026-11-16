using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Atomically replaces the session's YAML snapshot; never restarts an active engine.</summary>
[Cmdlet(VerbsData.Import, "QuietCliConfiguration")]
public sealed class ImportQuietCliConfigurationCommand : QuietCmdlet
{
    /// <summary>YAML path, default ~/.quietcli/config.yaml.</summary>
    [Parameter(Position = 0)]
    public string? Path { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try {
            string resolved = ConfigurationSchema.ResolvePath(Path ?? ConfigurationService.DefaultPath(CurrentDirectory), CurrentDirectory);
            ConfigurationSnapshot candidate = ConfigurationService.ValidateAsync(resolved, QuietSession.Root).GetAwaiter().GetResult();
            if (!candidate.IsValid) throw new InvalidDataException(ConfigurationService.InvalidMessage(candidate.Errors));
            string? running = QuietSession.ActiveDatabase;
            // PowerShell coerces $null to "" when assigning a string property, so treat both as "no engine".
            if (!string.IsNullOrEmpty(running)) {
                ConfigurationSnapshot current = ConfigurationService.Snapshot(CurrentDirectory);
                bool databaseChanged = !string.Equals((string?)candidate.Values["telemetry.database"], running, StringComparison.OrdinalIgnoreCase);
                bool hostingChanged = !string.Equals((string?)candidate.Values["engine.hosting"], (string?)current.Values["engine.hosting"], StringComparison.OrdinalIgnoreCase);
                if (databaseChanged || hostingChanged) throw new InvalidOperationException("ConfigurationEngineChangeRequiresStop-QuietEngine");
            }
            QuietSession.Configuration = candidate;
            WriteObject(GetQuietCliConfigurationCommand.Describe(candidate));
        } catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}
