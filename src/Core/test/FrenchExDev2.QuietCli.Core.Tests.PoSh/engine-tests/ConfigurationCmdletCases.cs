using System.Collections;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Property, fuzz and contract cases for the compiled configuration cmdlets, driven through a real PowerShell runspace.</summary>
internal static class ConfigurationCmdletCases
{
    /// <summary>Fixed seed retained so any failing generated file can be replayed deterministically.</summary>
    private const int Seed = 20261109;

    /// <summary>Runs every configuration cmdlet case.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="root">Module root containing the pinned resources.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, string root)
    {
        string work = Path.Combine(Path.GetTempPath(), "quiet-config-cmdlet-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        QuietSession.Initialize(root);
        using Runspace runspace = RunspaceFactory.CreateRunspace(Session());
        runspace.Open();

        await run("configuration cmdlet reports defaults for a missing file without creating anything", () =>
        {
            Reset();
            string path = Path.Combine(work, "missing", "config.yaml");
            var result = Invoke(runspace, "Test-QuietCliConfiguration", ("Path", path)).Single();
            var snapshot = (ConfigurationSnapshot)result.BaseObject;
            Require(snapshot.IsValid && !snapshot.Exists && snapshot.Errors.Length == 0, "Missing file was not a valid default configuration");
            Require(snapshot.Values.Count == 19 && snapshot.Origins.Values.Cast<string>().All(origin => origin == "Default"), "Defaults or origins changed");
            Require(!Directory.Exists(Path.GetDirectoryName(path)), "Validation created a directory");
            return Task.CompletedTask;
        });

        await run("configuration cmdlet marks YAML origins and resolves relative paths against the file", () =>
        {
            Reset();
            string path = Write(work, "origins", "schemaVersion: 1\ndelivery:\n  maxItems: 7\ntelemetry:\n  database: local.sqlite\n  enabled: false\n");
            var snapshot = (ConfigurationSnapshot)Invoke(runspace, "Test-QuietCliConfiguration", ("Path", path)).Single().BaseObject;
            Require(snapshot.IsValid, "Valid file rejected");
            Require((int)snapshot.Values["delivery.maxItems"]! == 7 && (bool)snapshot.Values["telemetry.enabled"]! == false, "Override lost");
            Require((string)snapshot.Values["telemetry.database"]! == Path.Combine(Path.GetDirectoryName(path)!, "local.sqlite"), "Relative path not resolved against the file");
            Require((string)snapshot.Origins["delivery.maxItems"]! == "Yaml" && (string)snapshot.Origins["gain.maxEvents"]! == "Default", "Origins wrong");
            Require((int)((PSObject)snapshot.Configuration.Properties["delivery"].Value).Properties["maxItems"].Value == 7, "Sectioned view lost the override");
            return Task.CompletedTask;
        });

        await run("configuration cmdlet reports stable codes with source locations", () =>
        {
            // Oracle written literally: (file body, expected code, key, line, column).
            (string Body, string Code, string Key, int Line, int Column)[] cases =
            [
                ("schemaVersion: 99\n", "UnsupportedConfigurationVersion", "schemaVersion", 1, 1),
                ("delivery:\n  maxItems: 3\n", "UnsupportedConfigurationVersion", "schemaVersion", 0, 0),
                ("schemaVersion: 1\nbogus:\n  a: 1\n", "UnknownOrInvalidConfigurationSection", "bogus", 2, 1),
                ("schemaVersion: 1\ndelivery:\n  nope: 1\n", "UnknownConfigurationKey", "delivery.nope", 3, 3),
                ("schemaVersion: 1\ndelivery:\n  maxItems: -1\n", "InvalidConfigurationNumber", "delivery.maxItems", 3, 3),
                ("schemaVersion: 1\ndelivery:\n  maxItems: 1.5\n", "InvalidConfigurationInteger", "delivery.maxItems", 3, 3),
                ("schemaVersion: 1\nengine:\n  hosting: Bad\n", "InvalidConfigurationEnum", "engine.hosting", 3, 3),
                ("schemaVersion: 1\ntelemetry:\n  enabled: maybe\n", "InvalidConfigurationBoolean", "telemetry.enabled", 3, 3),
                ("schemaVersion: &a 1\n", "YamlTagsAndAnchorsForbidden", "", 1, 16),
            ];
            foreach (var (body, code, key, line, column) in cases) {
                Reset();
                var snapshot = (ConfigurationSnapshot)Invoke(runspace, "Test-QuietCliConfiguration", ("Path", Write(work, "codes", body))).Single().BaseObject;
                var error = snapshot.Errors.FirstOrDefault();
                Require(!snapshot.IsValid && error != null && error.Code == code && error.Key == key && error.Line == line && error.Column == column,
                    $"Expected {code} {key} {line}:{column} but got {(error == null ? "none" : $"{error.Code} {error.Key} {error.Line}:{error.Column}")} for: {body.Replace("\n", "\\n")}");
            }
            string directory = Path.Combine(work, "a-directory.yaml"); Directory.CreateDirectory(directory);
            var folder = (ConfigurationSnapshot)Invoke(runspace, "Test-QuietCliConfiguration", ("Path", directory)).Single().BaseObject;
            Require(folder.Errors.Single().Code == "ConfigurationPathIsDirectory", "Directory path code changed");
            return Task.CompletedTask;
        });

        await run("generated numeric settings are accepted exactly when inside their range", () =>
        {
            // Oracle table written literally on purpose.
            (string Section, string Name, double Min, double Max)[] ranges =
            [
                ("delivery", "maxItems", 0, 1000), ("delivery", "maxTrackedRepresentations", 1, 65536), ("gain", "maxEvents", 1, 1000000),
                ("streams", "readBlockBytes", 1024, 16384), ("streams", "maxRecordBytes", 1, 100000),
            ];
            var random = new Random(Seed);
            for (int iteration = 0; iteration < 400; iteration++) {
                var (section, name, min, max) = ranges[random.Next(ranges.Length)];
                long candidate = (long)Math.Floor(min - 3 + random.NextDouble() * (max - min + 6));
                bool inside = candidate >= min && candidate <= max;
                Reset();
                var snapshot = (ConfigurationSnapshot)Invoke(runspace, "Test-QuietCliConfiguration", ("Path", Write(work, "numeric", $"schemaVersion: 1\n{section}:\n  {name}: {candidate}\n"))).Single().BaseObject;
                Require(snapshot.IsValid == inside, $"{section}.{name}={candidate} validity should be {inside}");
                if (!inside) Require(snapshot.Errors.Single().Code == "InvalidConfigurationNumber", "Out-of-range code changed");
            }
            return Task.CompletedTask;
        });

        await run("malformed and random configuration files never escape as exceptions", () =>
        {
            var random = new Random(Seed + 1);
            string alphabet = "schemaVersion:delivery maxItems\n\t -~#&*!{}[]|>'\",.%@`0123456789é";
            for (int iteration = 0; iteration < 300; iteration++) {
                var text = new StringBuilder(random.Next(0, 200));
                for (int index = 0, length = random.Next(0, 200); index < length; index++) text.Append(alphabet[random.Next(alphabet.Length)]);
                Reset();
                string path = Path.Combine(work, "fuzz.yaml");
                File.WriteAllText(path, text.ToString(), new UTF8Encoding(false));
                var snapshot = (ConfigurationSnapshot)Invoke(runspace, "Test-QuietCliConfiguration", ("Path", path)).Single().BaseObject;
                Require(snapshot.IsValid || snapshot.Errors.All(error => error.Code.Length > 0), "Invalid result without a stable code");
            }
            File.WriteAllBytes(Path.Combine(work, "binary.yaml"), [0xFF, 0xFE, 0x00, 0x80, 0xC3, 0x28]);
            Reset();
            Require(!((ConfigurationSnapshot)Invoke(runspace, "Test-QuietCliConfiguration", ("Path", Path.Combine(work, "binary.yaml"))).Single().BaseObject).IsValid, "Invalid UTF-8 accepted");
            File.WriteAllText(Path.Combine(work, "large.yaml"), "schemaVersion: 1\n# " + new string('x', 70000), new UTF8Encoding(false));
            Reset();
            Require(((ConfigurationSnapshot)Invoke(runspace, "Test-QuietCliConfiguration", ("Path", Path.Combine(work, "large.yaml"))).Single().BaseObject).Errors.Single().Code == "ConfigurationSizeLimit", "Size limit lost");
            return Task.CompletedTask;
        });

        await run("New-QuietCliConfiguration never overwrites without Force and honors WhatIf", () =>
        {
            Reset();
            string path = Path.Combine(work, "new", "config.yaml");
            Invoke(runspace, "New-QuietCliConfiguration", ("Path", path), ("WhatIf", true));
            Require(!File.Exists(path), "WhatIf wrote the file");
            var created = Invoke(runspace, "New-QuietCliConfiguration", ("Path", path)).Single();
            Require(created.BaseObject is FileInfo info && info.FullName == path && File.ReadAllText(path) == ConfigurationSchema.RenderTemplate(), "Template not written");
            Require(!File.ReadAllText(path).Contains('\r') && File.ReadAllBytes(path)[0] != 0xEF, "Template is not LF without BOM");
            ExpectFailure(runspace, "ConfigurationFileExists", "New-QuietCliConfiguration", ("Path", path));
            File.WriteAllText(path, "changed");
            Invoke(runspace, "New-QuietCliConfiguration", ("Path", path), ("Force", true));
            Require(File.ReadAllText(path) == ConfigurationSchema.RenderTemplate(), "Force did not replace the file");
            var round = (ConfigurationSnapshot)Invoke(runspace, "Test-QuietCliConfiguration", ("Path", path)).Single().BaseObject;
            Require(round.IsValid && round.Origins.Values.Cast<string>().All(origin => origin == "Yaml"), "Generated template is not a valid full configuration");
            return Task.CompletedTask;
        });

        await run("Import-QuietCliConfiguration replaces the snapshot only when valid and refuses engine-changing reloads", () =>
        {
            Reset();
            string good = Write(work, "import", "schemaVersion: 1\ndelivery:\n  maxItems: 3\n");
            Invoke(runspace, "Import-QuietCliConfiguration", ("Path", good));
            Require(Setting(runspace, "delivery.maxItems") is 3, "Import did not publish the snapshot");
            File.WriteAllText(good, "schemaVersion: 1\ndelivery:\n  maxItems: 5\n");
            Require(Setting(runspace, "delivery.maxItems") is 3, "Snapshot reloaded implicitly");
            ExpectFailure(runspace, "InvalidQuietConfiguration", "Import-QuietCliConfiguration", ("Path", Write(work, "import-bad", "schemaVersion: 99\n")));
            Require(Setting(runspace, "delivery.maxItems") is 3, "Invalid import replaced the snapshot");
            Invoke(runspace, "Import-QuietCliConfiguration", ("Path", good));
            Require(Setting(runspace, "delivery.maxItems") is 5, "Explicit reload ignored");
            QuietSession.Engine = new EngineConnection { Mode = "InProcess", Database = (string)QuietSession.Configuration!.Values["telemetry.database"]! };
            try {
                Invoke(runspace, "Import-QuietCliConfiguration", ("Path", good));
                ExpectFailure(runspace, "ConfigurationEngineChangeRequiresStop-QuietEngine", "Import-QuietCliConfiguration", ("Path", Write(work, "import-db", "schemaVersion: 1\ntelemetry:\n  database: other.sqlite\n")));
                ExpectFailure(runspace, "ConfigurationEngineChangeRequiresStop-QuietEngine", "Import-QuietCliConfiguration", ("Path", Write(work, "import-host", "schemaVersion: 1\nengine:\n  hosting: Process\n")));
            } finally { QuietSession.Engine = null; }
            return Task.CompletedTask;
        });

        await run("Get-QuietCliConfiguration returns a detached view", () =>
        {
            Reset();
            Invoke(runspace, "Import-QuietCliConfiguration", ("Path", Write(work, "detached", "schemaVersion: 1\ndelivery:\n  maxItems: 4\n")));
            var first = Invoke(runspace, "Get-QuietCliConfiguration").Single();
            ((PSObject)first.Properties["Configuration"].Value).Properties["delivery"].Value = null;
            var second = Invoke(runspace, "Get-QuietCliConfiguration").Single();
            var delivery = (PSObject)((PSObject)second.Properties["Configuration"].Value).Properties["delivery"].Value;
            Require((int)delivery.Properties["maxItems"].Value == 4, "Public view mutated the snapshot");
            return Task.CompletedTask;
        });

        await run("resource verification memoizes successes, rejects unknown paths and detects tampering", async () =>
        {
            await ResourceVerifier.VerifyAsync(root, "resources/yaml/YamlDotNet.dll");
            await ResourceVerifier.VerifyAsync(root, "resources/yaml/YamlDotNet.dll");
            foreach (string unknown in new[] { "resources/yaml/Missing.dll", "../outside.dll" }) {
                try { await ResourceVerifier.VerifyAsync(root, unknown); throw new Exception("Unknown resource accepted: " + unknown); }
                catch (InvalidDataException error) when (error.Message == "DependencyNotInventoried") { }
            }
            // Tamper with a staged copy of the module resources, never the product tree.
            string staged = Path.Combine(work, "tamper");
            foreach (string name in new[] { "resources/dependencies.lock.json", "resources/yaml/YamlDotNet.dll" }) {
                Directory.CreateDirectory(Path.GetDirectoryName(Path.Combine(staged, name))!);
                File.Copy(Path.Combine(root, name), Path.Combine(staged, name));
            }
            await ResourceVerifier.VerifyAsync(staged, "resources/yaml/YamlDotNet.dll");
            using (var stream = new FileStream(Path.Combine(staged, "resources/yaml/YamlDotNet.dll"), FileMode.Open, FileAccess.Write)) { stream.Seek(100, SeekOrigin.Begin); stream.WriteByte(0x7F); }
            File.SetLastWriteTimeUtc(Path.Combine(staged, "resources/yaml/YamlDotNet.dll"), DateTime.UtcNow.AddMinutes(5));
            try { await ResourceVerifier.VerifyAsync(staged, "resources/yaml/YamlDotNet.dll"); throw new Exception("Tampered resource accepted"); }
            catch (InvalidDataException error) when (error.Message == "DependencyIntegrityFailed: resources/yaml/YamlDotNet.dll") { }
        });

        QuietSession.Initialize(root);
        try { Directory.Delete(work, true); } catch (IOException) { }
    }

    /// <summary>Builds a session that exposes only the configuration cmdlets under test.</summary>
    private static InitialSessionState Session()
    {
        var state = InitialSessionState.CreateDefault2();
        foreach (var (name, type) in new (string, Type)[] {
            ("Test-QuietCliConfiguration", typeof(TestQuietCliConfigurationCommand)), ("Import-QuietCliConfiguration", typeof(ImportQuietCliConfigurationCommand)),
            ("Get-QuietCliConfiguration", typeof(GetQuietCliConfigurationCommand)), ("New-QuietCliConfiguration", typeof(NewQuietCliConfigurationCommand)),
            ("Get-QuietSetting", typeof(GetQuietSettingCommand)) })
            state.Commands.Add(new SessionStateCmdletEntry(name, type, null));
        return state;
    }

    /// <summary>Forgets the session snapshot so each case starts from the file system.</summary>
    private static void Reset() => QuietSession.Configuration = null;

    /// <summary>Writes a configuration body to a fresh directory and returns its path.</summary>
    private static string Write(string work, string name, string body)
    {
        string directory = Path.Combine(work, name + "-" + Guid.NewGuid().ToString("N")[..8]); Directory.CreateDirectory(directory);
        string path = Path.Combine(directory, "config.yaml");
        File.WriteAllText(path, body, new UTF8Encoding(false));
        return path;
    }

    /// <summary>Reads a setting through the internal cmdlet.</summary>
    private static object? Setting(Runspace runspace, string name) => Invoke(runspace, "Get-QuietSetting", ("Name", name)).Single().BaseObject;

    /// <summary>Runs one cmdlet with named parameters and returns its output.</summary>
    private static List<PSObject> Invoke(Runspace runspace, string command, params (string Name, object Value)[] parameters)
    {
        using var shell = PowerShell.Create(runspace);
        shell.AddCommand(command);
        foreach (var (name, value) in parameters) { if (value is true) shell.AddParameter(name); else shell.AddParameter(name, value); }
        return shell.Invoke().ToList();
    }

    /// <summary>Requires a terminating error whose innermost message starts with the code.</summary>
    private static void ExpectFailure(Runspace runspace, string code, string command, params (string Name, object Value)[] parameters)
    {
        try { Invoke(runspace, command, parameters); }
        catch (Exception error) when (ConfigurationService.Innermost(error).Message.StartsWith(code, StringComparison.Ordinal)) { return; }
        throw new Exception($"{command} did not fail with {code}");
    }

    /// <summary>Throws when an independently known invariant fails.</summary>
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
