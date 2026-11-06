using System.Management.Automation;
using System.Text;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Explicitly creates a complete UTF-8/LF template; never overwrites without Force.</summary>
[Cmdlet(VerbsCommon.New, "QuietCliConfiguration", SupportsShouldProcess = true)]
[OutputType(typeof(FileInfo))]
public sealed class NewQuietCliConfigurationCommand : QuietCmdlet
{
    /// <summary>Destination YAML path.</summary>
    [Parameter(Position = 0)]
    public string? Path { get; set; }

    /// <summary>Explicitly permits replacement of an existing file.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try {
            string resolved = ConfigurationSchema.ResolvePath(Path ?? ConfigurationService.DefaultPath(CurrentDirectory), CurrentDirectory);
            if (File.Exists(resolved) && !Force) throw new InvalidOperationException("ConfigurationFileExists");
            string template = ConfigurationSchema.RenderTemplate();
            if (!ShouldProcess(resolved, "Write QuietCli configuration")) return;
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(resolved)!);
            WriteTemplateAsync(resolved, template, Force).GetAwaiter().GetResult();
            WriteObject(new FileInfo(resolved));
        } catch (Exception error) when (error is not PipelineStoppedException) { Fail(error); }
    }

    /// <summary>Writes the template as BOM-less UTF-8 with exclusive access.</summary>
    /// <param name="path">Absolute destination.</param>
    /// <param name="template">Rendered LF template.</param>
    /// <param name="replace">True to replace an existing file.</param>
    private static async Task WriteTemplateAsync(string path, string template, bool replace)
    {
        await using var stream = new FileStream(path, replace ? FileMode.Create : FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, true);
        await stream.WriteAsync(new UTF8Encoding(false, true).GetBytes(template));
    }
}
