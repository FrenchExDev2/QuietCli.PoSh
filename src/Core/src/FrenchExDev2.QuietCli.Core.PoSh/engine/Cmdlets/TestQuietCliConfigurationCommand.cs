using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Validates inert YAML without starting an engine or creating any file or database.</summary>
[Cmdlet(VerbsDiagnostic.Test, "QuietCliConfiguration")]
[OutputType(typeof(ConfigurationSnapshot))]
public sealed class TestQuietCliConfigurationCommand : QuietCmdlet
{
    /// <summary>Configuration path, default ~/.quietcli/config.yaml.</summary>
    [Parameter(Position = 0)]
    public string? Path { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try {
            string resolved = ConfigurationSchema.ResolvePath(Path ?? ConfigurationService.DefaultPath(CurrentDirectory), CurrentDirectory);
            WriteObject(ConfigurationService.ValidateAsync(resolved, QuietSession.Root).GetAwaiter().GetResult());
        } catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }
}
