using System.Management.Automation;
using FrenchExDev2.QuietCli.Agents;
using FrenchExDev2.QuietCli.Scaffolding;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Reads the distributed production AGENTS.md without starting an engine or changing configuration.</summary>
[Cmdlet(VerbsCommon.Get, "QuietAgentInstruction")]
[OutputType(typeof(string))]
public sealed class GetQuietAgentInstructionCommand : QuietCmdlet
{
    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(AgentDocuments.ReadInstructions(QuietSession.Root)); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}

/// <summary>Copies production instructions and adds portable references to selected project Markdown files.</summary>
[Cmdlet(VerbsCommon.Add, "QuietAgentInstruction", SupportsShouldProcess = true)]
[OutputType(typeof(PSObject))]
public sealed class AddQuietAgentInstructionCommand : QuietCmdlet
{
    /// <summary>Existing project directory; defaults to the current directory.</summary>
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty]
    public string? Path { get; set; }

    /// <summary>Creates or updates the project's AGENTS.md.</summary>
    [Parameter]
    public SwitchParameter Agents { get; set; }

    /// <summary>Creates or updates CLAUDE.md with a relative import.</summary>
    [Parameter]
    public SwitchParameter Claude { get; set; }

    /// <summary>Creates or updates the project SKILL.md reference; does not register a native agent skill.</summary>
    [Parameter]
    public SwitchParameter Skill { get; set; }

    /// <summary>Managed copy directory, relative to Path or an explicit absolute path.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string DocumentDirectory { get; set; } = ".skills";

    /// <summary>Auto selects AGENTS.md for Agents/Claude and SKILL.md for Skill; Agents or Skill overrides all targets.</summary>
    [Parameter]
    [ValidateSet("Auto", "Agents", "Skill")]
    public string Document { get; set; } = "Auto";

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try
        {
            string project = System.IO.Path.GetFullPath(Path ?? CurrentDirectory, CurrentDirectory);
            InstallPlan plan = AgentInstaller.Plan(project, Agents, Claude, Skill, DocumentDirectory, Document, () => AgentDocuments.Directory(QuietSession.Root));
            // The common -WhatIf switch is only visible through the bound parameters; the preference variable covers $WhatIfPreference.
            bool whatIf = (MyInvocation.BoundParameters.TryGetValue("WhatIf", out object? bound) && bound is SwitchParameter { IsPresent: true })
                || (GetVariableValue("WhatIfPreference") is bool preference && preference);
            var (documents, files) = AgentInstaller.Apply(plan, ShouldProcess, whatIf);
            var result = new PSObject();
            result.Properties.Add(new PSNoteProperty("Files", files.Select(File).ToArray()));
            result.Properties.Add(new PSNoteProperty("Documents", documents.Select(Entry).ToArray()));
            WriteObject(result);
        }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }

    /// <summary>Describes a managed document copy.</summary>
    private static PSObject Entry(InstallResult item)
    {
        var entry = new PSObject();
        entry.Properties.Add(new PSNoteProperty("Path", item.Path));
        entry.Properties.Add(new PSNoteProperty("Status", item.Status));
        return entry;
    }

    /// <summary>Describes a project file that received a reference.</summary>
    private static PSObject File(InstallResult item)
    {
        var entry = new PSObject();
        entry.Properties.Add(new PSNoteProperty("Path", item.Path));
        entry.Properties.Add(new PSNoteProperty("Document", item.Update!.Document));
        entry.Properties.Add(new PSNoteProperty("SourcePath", item.Update.SourcePath));
        entry.Properties.Add(new PSNoteProperty("ReferencePath", item.Update.ReferencePath));
        entry.Properties.Add(new PSNoteProperty("Status", item.Status));
        return entry;
    }
}

/// <summary>Generates a business module and an independent companion test module.</summary>
[Cmdlet(VerbsCommon.New, "QuietModule")]
[OutputType(typeof(PSObject))]
public sealed class NewQuietModuleCommand : QuietCmdlet
{
    /// <summary>Full module name without the Tests component.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidatePattern(@"^[A-Za-z][A-Za-z0-9.]+\z")]
    public string Name { get; set; } = "";

    /// <summary>Executable name handled by the module.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidatePattern(@"^[A-Za-z0-9_][A-Za-z0-9_.-]*\z")]
    public string Binary { get; set; } = "";

    /// <summary>Parent workspace directory; existing destinations are never overwritten.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public string OutputPath { get; set; } = "";

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try
        {
            (string module, string tests) = ModuleScaffold.Generate(Name, Binary, System.IO.Path.GetFullPath(OutputPath, CurrentDirectory));
            var result = new PSObject();
            result.Properties.Add(new PSNoteProperty("Module", module));
            result.Properties.Add(new PSNoteProperty("Tests", tests));
            result.Properties.Add(new PSNoteProperty("Qualification", "NotImplemented"));
            WriteObject(result);
        }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}
