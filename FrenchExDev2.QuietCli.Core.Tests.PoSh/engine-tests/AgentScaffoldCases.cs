using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using FrenchExDev2.QuietCli.Agents;
using FrenchExDev2.QuietCli.Scaffolding;

/// <summary>Property, fuzz and contract cases for the instruction installer, its reference block and the module scaffold.</summary>
internal static class AgentScaffoldCases
{
    /// <summary>Fixed seed retained so any failing generated value can be replayed deterministically.</summary>
    private const int Seed = 73607;

    private const string Begin = "<!-- quietcli:instructions:begin -->";
    private const string End = "<!-- quietcli:instructions:end -->";

    /// <summary>Runs every agent instruction and scaffold case.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="runspace">Runspace that registers the compiled cmdlets.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, Runspace runspace)
    {
        string root = Path.Combine(Path.GetTempPath(), "quiet-agent-cases-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await run("agent reference block preserves text, escaping, LF and idempotence; malformed markers fail (generated)", () =>
            {
                var random = new Random(Seed);
                for (int index = 1; index <= 96; index++)
                {
                    string newline = index % 2 == 1 ? "\n" : "\r\n";
                    string prefix = $"# Project é漢 {random.Next()}{newline}", suffix = $"{newline}## Existing footer {index}{newline}";
                    string original = prefix + Begin + newline + "old" + newline + End + suffix;
                    const string reference = "./instructions é漢/#percent%/AGENTS.md";
                    string updated = AgentReferenceBlock.Apply(original, reference, false);
                    Require(updated.StartsWith(prefix, StringComparison.Ordinal) && updated.EndsWith(suffix, StringComparison.Ordinal) && updated.Contains("./instructions é漢/%23percent%25/AGENTS.md"), "Surrounding text or escaping lost");
                    Require(AgentReferenceBlock.Apply(updated, reference, false) == updated, "Not idempotent");
                    Require(Count(updated, Begin) == 1, "Block duplicated");
                    Require(!AgentReferenceBlock.Apply("", reference, true).Contains('\r'), "A new file is not LF");
                    foreach (string bad in new[] { Begin, End, End + Begin, Begin + Begin + End, Begin + End + End })
                        RequireFailure("AgentInstructionMalformedBlock", () => AgentReferenceBlock.Apply(prefix + bad + suffix, reference, index % 3 == 0));
                    // A text without any trailing newline gets one separator, in its own newline style.
                    string bare = "# bare" + (index % 2 == 1 ? "" : "\r\nsecond");
                    string appended = AgentReferenceBlock.Apply(bare, reference, false);
                    Require(appended.StartsWith(bare + newline + Begin, StringComparison.Ordinal) && appended.EndsWith(End + newline, StringComparison.Ordinal), "Appended block separator wrong");
                }
                return Task.CompletedTask;
            });

            await run("agent reference block rejects line breaks and control characters and encodes backslashes", () =>
            {
                foreach (string bad in new[] { "a\nb", "a\rb", "a\r\n## Injected", "a\u0085b", "a\u2028b", "a\u2029b", "a\0b", "a\tb", "a\u007fb" })
                    foreach (bool claude in new[] { false, true })
                        RequireFailure("AgentInstructionReferenceInvalid", () => AgentReferenceBlock.Apply("", bad, claude));
                Require(AgentReferenceBlock.Apply("", "dir\\x\\", false).Contains("<dir%5Cx%5C>"), "Backslashes not encoded");
                Require(AgentReferenceBlock.Apply("", "a b<c>?d", false).Contains("<a b%3Cc%3E%3Fd>"), "Link specials not encoded");
                Require(AgentReferenceBlock.Apply("", "a b", true).Contains("@a\\ b"), "Claude import not escaped");
                return Task.CompletedTask;
            });

            await run("agent installation preserves BOM and rules, is idempotent and honours WhatIf (generated)", () =>
            {
                string sources = Path.Combine(root, "sources");
                Directory.CreateDirectory(sources);
                File.WriteAllText(Path.Combine(sources, "AGENTS.md"), "# agents é\n");
                File.WriteAllText(Path.Combine(sources, "SKILL.md"), "# skill 漢\n");
                for (int index = 1; index <= 24; index++)
                {
                    string project = Path.Combine(root, $"project-{index}-é漢 # space");
                    Directory.CreateDirectory(project);
                    string newline = index % 2 == 1 ? "\n" : "\r\n";
                    byte[] original = [0xef, 0xbb, 0xbf, .. Encoding.UTF8.GetBytes($"# Existing rules {index}{newline}")];
                    File.WriteAllBytes(Path.Combine(project, "AGENTS.md"), original);
                    InstallPlan plan = AgentInstaller.Plan(project, true, true, true, "instructions é漢 #percent%", "Auto", () => sources);
                    var (documents, files) = AgentInstaller.Apply(plan, (_, _) => true, false);
                    Require(files.Count == 3 && documents.Count == 2, "Targets missing");
                    string claude = File.ReadAllText(Path.Combine(project, "CLAUDE.md")), skill = File.ReadAllText(Path.Combine(project, "SKILL.md"));
                    Require(claude.Contains("@./instructions\\ é漢\\ #percent%/AGENTS.md"), "Claude import missing");
                    Require(skill.Contains("instructions é漢 %23percent%25/SKILL.md") && !File.Exists(Path.Combine(project, "SKILLS.md")), "Skill target wrong");
                    byte[] rules = File.ReadAllBytes(Path.Combine(project, "AGENTS.md"));
                    Require(rules.AsSpan(0, 3).SequenceEqual(new byte[] { 0xef, 0xbb, 0xbf }) && rules.AsSpan(3, original.Length - 3).SequenceEqual(original.AsSpan(3)), "BOM or existing rules lost");
                    Require(File.ReadAllBytes(Path.Combine(project, "instructions é漢 #percent%", "AGENTS.md")).AsSpan().SequenceEqual(File.ReadAllBytes(Path.Combine(sources, "AGENTS.md"))), "Copy changed bytes");
                    DateTime before = File.GetLastWriteTimeUtc(Path.Combine(project, "AGENTS.md"));
                    var (againDocuments, againFiles) = AgentInstaller.Apply(AgentInstaller.Plan(project, true, true, true, "instructions é漢 #percent%", "Auto", () => sources), (_, _) => true, false);
                    Require(againDocuments.Concat(againFiles).All(item => item.Status == "Unchanged") && File.GetLastWriteTimeUtc(Path.Combine(project, "AGENTS.md")) == before, "Repeated installation rewrote files");
                }
                string preview = Path.Combine(root, "preview");
                Directory.CreateDirectory(preview);
                var (simulatedDocuments, simulatedFiles) = AgentInstaller.Apply(AgentInstaller.Plan(preview, true, false, false, ".skills", "Auto", () => sources), (_, _) => false, true);
                Require(simulatedFiles[0].Status == "Simulated" && simulatedDocuments.All(item => item.Status == "Simulated") && Directory.GetFileSystemEntries(preview).Length == 0, "WhatIf wrote files");
                var (declinedDocuments, declinedFiles) = AgentInstaller.Apply(AgentInstaller.Plan(preview, true, false, false, ".skills", "Auto", () => sources), (_, _) => false, false);
                Require(declinedDocuments.All(item => item.Status == "Skipped") && declinedFiles[0].Status == "Skipped" && Directory.GetFileSystemEntries(preview).Length == 0, "Declined run wrote files");
                // A declined copy must also skip the references, even when the references themselves would be approved.
                var (partialDocuments, partialFiles) = AgentInstaller.Apply(AgentInstaller.Plan(preview, true, false, false, ".skills", "Auto", () => sources), (_, action) => !action.StartsWith("Copy"), false);
                Require(partialDocuments.All(item => item.Status == "Skipped") && partialFiles[0].Status == "Skipped" && Directory.GetFileSystemEntries(preview).Length == 0, "A declined copy still wrote references");
                return Task.CompletedTask;
            });

            await run("agent installation rejects malformed targets, directories and links before any write", () =>
            {
                string sources = Path.Combine(root, "sources");
                string project = Path.Combine(root, "preflight");
                Directory.CreateDirectory(project);
                string agents = Path.Combine(project, "AGENTS.md");
                foreach (string bad in new[] { Begin, End })
                {
                    File.WriteAllText(agents, bad);
                    RequireFailure("AgentInstructionMalformedBlock", () => AgentInstaller.Plan(project, true, false, false, ".skills", "Auto", () => sources));
                }
                File.WriteAllBytes(agents, [0xff, 0xfe]);
                try { AgentInstaller.Plan(project, true, false, false, ".skills", "Auto", () => sources); throw new InvalidOperationException("Invalid UTF-8 accepted"); }
                catch (DecoderFallbackException) { }
                File.Delete(agents);
                RequireFailure("AgentInstructionPathConflict", () => AgentInstaller.Plan(project, true, false, false, ".", "Auto", () => sources));
                RequireFailure("AgentInstructionNonportableDirectory", () => AgentInstaller.Plan(project, true, false, false, "bad\nname", "Auto", () => sources));
                RequireFailure("AgentInstructionTargetRequired", () => AgentInstaller.Plan(project, false, false, false, ".skills", "Auto", () => sources));
                RequireFailure("AgentInstructionProjectMustBeDirectory", () => AgentInstaller.Plan(Path.Combine(sources, "AGENTS.md"), true, false, false, ".skills", "Auto", () => sources));
                RequireFailure("AgentInstructionTargetIsDirectory", () => { Directory.CreateDirectory(agents); AgentInstaller.Plan(project, true, false, false, ".skills", "Auto", () => sources); });
                Directory.Delete(agents);
                File.WriteAllText(Path.Combine(project, "blocker"), "x");
                RequireFailure("AgentInstructionAncestorIsFile", () => AgentInstaller.Plan(project, true, false, false, "blocker/inside", "Auto", () => sources));
                string outside = Path.Combine(root, "outside"), linked = Path.Combine(root, "linked-project");
                Directory.CreateDirectory(outside);
                Directory.CreateDirectory(linked);
                if (TryLink(Path.Combine(linked, ".skills"), outside))
                {
                    RequireFailure("AgentInstructionLinkedPath", () => AgentInstaller.Plan(linked, true, false, false, ".skills", "Auto", () => sources));
                    Require(Directory.GetFileSystemEntries(outside).Length == 0, "A link redirected a write");
                }
                return Task.CompletedTask;
            });

            await run("agent documents prefer packaged resources, never fall back from an incomplete package, and fail when absent", () =>
            {
                string module = Path.Combine(root, "module", "Core");
                Directory.CreateDirectory(Path.Combine(module, "resources", "agents"));
                Require(AgentDocuments.Directory(module) == Path.Combine(module, "resources", "agents"), "Packaged directory not selected");
                try { AgentDocuments.ReadInstructions(module); throw new InvalidOperationException("Empty package fell back"); }
                catch (FileNotFoundException) { }
                File.WriteAllText(Path.Combine(module, "resources", "agents", "AGENTS.md"), "é漢\n");
                Require(AgentDocuments.ReadInstructions(module) == "é漢\n", "Packaged instructions not read");
                string bare = Path.Combine(root, "bare", "Core");
                Directory.CreateDirectory(bare);
                RequireFailure("AgentInstructionResourcesMissing", () => AgentDocuments.Directory(bare));
                string repository = Path.Combine(root, "repository");
                Directory.CreateDirectory(Path.Combine(repository, "Core"));
                Directory.CreateDirectory(Path.Combine(repository, "scripts"));
                File.WriteAllText(Path.Combine(repository, "scripts", "New-WorkspacePackage.ps1"), "");
                Require(AgentDocuments.Directory(Path.Combine(repository, "Core")) == Path.Combine(repository, "docs", "agents"), "Repository source not selected");
                return Task.CompletedTask;
            });

            await run("module scaffold writes inert modules, parseable manifests and never overwrites (generated)", () =>
            {
                var random = new Random(Seed + 1);
                foreach (var (name, expected) in new[] { ("Sample.QuietTool.PoSh", "Sample.QuietTool.Tests.PoSh"), ("Sample.Tool", "Sample.Tool.Tests"), ("X.poSH", "X.Tests.PoSh") })
                    Require(ModuleScaffold.TestModuleName(name) == expected, $"Companion name of {name}");
                for (int round = 0; round < 12; round++)
                {
                    string name = "Gen" + random.Next(1000, 9999) + (round % 2 == 0 ? ".Thing.PoSh" : ".Thing"), binary = "bin-" + random.Next(100) + "_x.y";
                    (string module, string tests) = ModuleScaffold.Generate(name, binary, root);
                    string testName = ModuleScaffold.TestModuleName(name);
                    Require(module == Path.Combine(root, name) && tests == Path.Combine(root, testName), "Destinations wrong");
                    var manifest = Manifest(runspace, Path.Combine(module, name + ".psd1"));
                    var required = ((object[])manifest["RequiredModules"]!).Cast<System.Collections.Hashtable>().ToArray();
                    var data = (System.Collections.Hashtable)((System.Collections.Hashtable)manifest["PrivateData"]!)["QuietCli"]!;
                    Require(required.Length == 1 && (string)required[0]["ModuleName"]! == "QuietCli" && (string)required[0]["ModuleVersion"]! == "0.2.0" && (string)manifest["RootModule"]! == name + ".psm1" && (string)data["Binary"]! == binary && (string)data["TestsModule"]! == testName && (string)data["Qualification"]! == "NotImplemented", "Business manifest wrong");
                    var testManifest = Manifest(runspace, Path.Combine(tests, testName + ".psd1"));
                    var testRequired = ((object[])testManifest["RequiredModules"]!).Cast<System.Collections.Hashtable>().Select(item => (string)item["ModuleName"]!).ToArray();
                    Require(testRequired.SequenceEqual([name, "FrenchExDev2.QuietCli.Core.Tests.PoSh"]) && Guid.TryParse((string)testManifest["GUID"]!, out _), "Test manifest wrong");
                    string handler = File.ReadAllText(Path.Combine(module, "src", "Handler.ps1"));
                    Require(handler.Contains($"-Id '{name}'") && handler.Contains($"Binary='{binary}'") && !handler.Contains("__"), "Handler placeholders not replaced");
                    Require(File.ReadAllText(Path.Combine(module, name + ".psm1")).Contains($"Unregister-QuietHandler -Id '{name}'"), "Module cleanup missing");
                    foreach (string file in Directory.EnumerateFiles(module, "*", SearchOption.AllDirectories).Concat(Directory.EnumerateFiles(tests, "*", SearchOption.AllDirectories)))
                    {
                        byte[] bytes = File.ReadAllBytes(file);
                        Require(!(bytes.Length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb) && !bytes.Contains((byte)'\r'), "Generated file is not UTF-8 LF without BOM: " + file);
                    }
                    RequireFailure("ModuleDestinationExists", () => ModuleScaffold.Generate(name, binary, root));
                    Directory.Delete(tests, true);
                    RequireFailure("ModuleDestinationExists", () => ModuleScaffold.Generate(name, binary, root));
                }
                return Task.CompletedTask;
            });

            await run("module and agent cmdlets surface stable codes and validate parameters", () =>
            {
                DeliveryCmdletCases.Expect(runspace, "AgentInstructionTargetRequired", "param($p) Add-QuietAgentInstruction -Path $p", root);
                DeliveryCmdletCases.Expect(runspace, "ModuleDestinationExists", "param($p) New-QuietModule -Name 'Dup.Mod' -Binary b -OutputPath $p; New-QuietModule -Name 'Dup.Mod' -Binary b -OutputPath $p", root);
                foreach (string bad in new[] { "1bad", "a", "bad name", "bad\n" })
                    try { DeliveryCmdletCases.Script(runspace, "param($n,$p) New-QuietModule -Name $n -Binary b -OutputPath $p", bad, root); throw new InvalidOperationException("Name accepted: " + bad); }
                    catch (InvalidOperationException error) when (error.Message.StartsWith("Name accepted")) { throw; }
                    catch (Exception) { }
                return Task.CompletedTask;
            });
        }
        finally { try { Directory.Delete(root, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }

    /// <summary>Evaluates a generated manifest literal in the test runspace.</summary>
    private static System.Collections.Hashtable Manifest(Runspace runspace, string path) =>
        (System.Collections.Hashtable)DeliveryCmdletCases.Script(runspace, "param($text) & ([scriptblock]::Create($text))", File.ReadAllText(path)).Single().BaseObject;

    /// <summary>Creates a directory link, returning false when the platform or privileges forbid it.</summary>
    private static bool TryLink(string link, string target)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                using Process? process = Process.Start(new ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{target}\"") { CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
                process?.WaitForExit();
                return Directory.Exists(link);
            }
            Directory.CreateSymbolicLink(link, target);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException) { return false; }
    }

    /// <summary>Counts non-overlapping ordinal occurrences.</summary>
    private static int Count(string text, string marker) => text.Split(marker, StringSplitOptions.None).Length - 1;

    /// <summary>Requires an action to fail with exactly the stable code.</summary>
    private static void RequireFailure(string code, Action action)
    {
        try { action(); }
        catch (InvalidOperationException error) when (error.Message == code) { return; }
        throw new InvalidOperationException($"Expected failure {code}");
    }

    /// <summary>Throws when an independently known invariant fails.</summary>
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
