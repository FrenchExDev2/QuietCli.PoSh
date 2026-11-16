using System.Text;

namespace FrenchExDev2.QuietCli.Agents;

/// <summary>One managed document copy, fully validated before any write.</summary>
/// <param name="Path">Destination under the managed directory.</param>
/// <param name="Bytes">Distributed bytes, copied verbatim.</param>
/// <param name="Exists">Whether the destination already exists.</param>
/// <param name="Same">Whether the destination already holds exactly these bytes.</param>
internal sealed record DocumentCopy(string Path, byte[] Bytes, bool Exists, bool Same);

/// <summary>One project instruction file that receives the managed reference block.</summary>
/// <param name="Path">Project file.</param>
/// <param name="SourcePath">Managed copy the block points to.</param>
/// <param name="ReferencePath">Portable project-relative reference.</param>
/// <param name="Document">Agents or Skill.</param>
/// <param name="Exists">Whether the file already exists.</param>
/// <param name="Same">Whether the file already holds the final content.</param>
/// <param name="Content">Final file text.</param>
internal sealed record ReferenceUpdate(string Path, string SourcePath, string ReferencePath, string Document, bool Exists, bool Same, string Content);

/// <summary>Complete preflight of an installation.</summary>
/// <param name="CopyRoot">Managed copy directory.</param>
/// <param name="Copies">Distributed documents to copy.</param>
/// <param name="References">Project files to update.</param>
internal sealed record InstallPlan(string CopyRoot, IReadOnlyList<DocumentCopy> Copies, IReadOnlyList<ReferenceUpdate> References);

/// <summary>Outcome of one installed item.</summary>
/// <param name="Update">Reference update, or null for a document copy.</param>
/// <param name="Path">Written path.</param>
/// <param name="Status">Created, Updated, Unchanged, Simulated or Skipped.</param>
internal sealed record InstallResult(ReferenceUpdate? Update, string Path, string Status);

/// <summary>Plans and applies the copy of production instructions plus the managed references in project Markdown.</summary>
internal static class AgentInstaller
{
    /// <summary>Preflights every source, path and managed block; nothing is written.</summary>
    /// <param name="project">Existing project directory (absolute).</param>
    /// <param name="agents">Targets the project AGENTS.md.</param>
    /// <param name="claude">Targets CLAUDE.md.</param>
    /// <param name="skill">Targets SKILL.md.</param>
    /// <param name="documentDirectory">Managed copy directory, relative to the project or absolute.</param>
    /// <param name="document">Auto, Agents or Skill.</param>
    /// <param name="sourceRoot">Resolves the directory of the distributed documents, only after the project and targets are validated.</param>
    internal static InstallPlan Plan(string project, bool agents, bool claude, bool skill, string documentDirectory, string document, Func<string> sourceRoot)
    {
        if (!agents && !claude && !skill) throw new InvalidOperationException("AgentInstructionTargetRequired");
        if (!Directory.Exists(project))
        {
            if (File.Exists(project)) throw new InvalidOperationException("AgentInstructionProjectMustBeDirectory");
            throw new DirectoryNotFoundException(project);
        }
        string copyRoot = Path.GetFullPath(documentDirectory.Replace('\\', Path.DirectorySeparatorChar), project);
        string relative = Path.GetRelativePath(project, copyRoot);
        if (Path.IsPathRooted(relative) || relative.Contains('\r') || relative.Contains('\n')) throw new InvalidOperationException("AgentInstructionNonportableDirectory");
        string[] sources = ["AGENTS.md", "SKILL.md"];
        string[] sourcePaths = sources.Select(name => Path.Combine(sourceRoot(), name)).ToArray();
        (bool Enabled, string Name, string Choice)[] selected = [(agents, "AGENTS.md", "Agents"), (claude, "CLAUDE.md", "Agents"), (skill, "SKILL.md", "Skill")];
        string[] targets = selected.Where(item => item.Enabled).Select(item => Path.Combine(project, item.Name)).ToArray();
        var copies = new List<DocumentCopy>();
        foreach (string source in sourcePaths)
        {
            byte[] bytes = File.ReadAllBytesAsync(source).GetAwaiter().GetResult();
            _ = AgentDocuments.StrictUtf8.GetString(bytes);
            string destination = Path.Combine(copyRoot, Path.GetFileName(source));
            AgentDocuments.AssertWritable(destination, sourcePaths.Concat(targets));
            bool exists = File.Exists(destination);
            copies.Add(new DocumentCopy(destination, bytes, exists, exists && bytes.AsSpan().SequenceEqual(File.ReadAllBytesAsync(destination).GetAwaiter().GetResult())));
        }
        var references = new List<ReferenceUpdate>();
        foreach ((bool enabled, string name, string choice) in selected)
        {
            if (!enabled) continue;
            string destination = Path.Combine(project, name);
            AgentDocuments.AssertWritable(destination, sourcePaths.Concat(copies.Select(copy => copy.Path)));
            string chosen = document == "Auto" ? choice : document;
            string managed = Path.Combine(copyRoot, chosen == "Agents" ? "AGENTS.md" : "SKILL.md");
            string reference = "./" + Path.GetRelativePath(project, managed).Replace('\\', '/');
            bool exists = File.Exists(destination);
            string text = exists ? AgentDocuments.StrictUtf8.GetString(File.ReadAllBytesAsync(destination).GetAwaiter().GetResult()) : "";
            string content = AgentReferenceBlock.Apply(text, reference, name == "CLAUDE.md");
            references.Add(new ReferenceUpdate(destination, managed, reference, chosen, exists, exists && content == text, content));
        }
        return new InstallPlan(copyRoot, copies, references);
    }

    /// <summary>Writes the planned copies, then the references; a declined copy skips every reference.</summary>
    /// <param name="plan">Validated plan.</param>
    /// <param name="approve">Receives the target and the action text; returns whether the change may be made.</param>
    /// <param name="whatIf">Whether declined changes are reported as simulated.</param>
    /// <returns>Document and file outcomes, in plan order.</returns>
    internal static (IReadOnlyList<InstallResult> Documents, IReadOnlyList<InstallResult> Files) Apply(InstallPlan plan, Func<string, string, bool> approve, bool whatIf)
    {
        var documents = new List<InstallResult>();
        foreach (DocumentCopy item in plan.Copies)
        {
            string status;
            if (item.Same) status = "Unchanged";
            else if (approve(item.Path, "Copy production QuietCli instructions"))
            {
                Directory.CreateDirectory(plan.CopyRoot);
                File.WriteAllBytesAsync(item.Path, item.Bytes).GetAwaiter().GetResult();
                status = item.Exists ? "Updated" : "Created";
            }
            else status = whatIf ? "Simulated" : "Skipped";
            documents.Add(new InstallResult(null, item.Path, status));
        }
        bool declined = documents.Any(item => item.Status == "Skipped");
        var files = new List<InstallResult>();
        foreach (ReferenceUpdate item in plan.References)
        {
            string status;
            if (item.Same) status = "Unchanged";
            else if (declined) status = "Skipped";
            else if (approve(item.Path, "Add production QuietCli instruction reference"))
            {
                File.WriteAllTextAsync(item.Path, item.Content, AgentDocuments.StrictUtf8).GetAwaiter().GetResult();
                status = item.Exists ? "Updated" : "Created";
            }
            else status = whatIf ? "Simulated" : "Skipped";
            files.Add(new InstallResult(item, item.Path, status));
        }
        return (documents, files);
    }
}
