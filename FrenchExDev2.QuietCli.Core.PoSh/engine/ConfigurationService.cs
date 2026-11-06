using System.Collections;
using System.Collections.Specialized;
using System.Management.Automation;
using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>One validation finding with its source location.</summary>
/// <param name="Code">Stable error code.</param>
/// <param name="Key">Configuration key path, or empty.</param>
/// <param name="Line">Source line, or zero.</param>
/// <param name="Column">Source column, or zero.</param>
public sealed record ConfigurationIssue(string Code, string Key, int Line, int Column);

/// <summary>Validated configuration: effective values, their origins and any findings. Values stay mutable for the session.</summary>
public sealed class ConfigurationSnapshot
{
    /// <summary>True when no finding was recorded.</summary>
    public bool IsValid { get; init; }
    /// <summary>Resolved absolute file path.</summary>
    public string Path { get; init; } = "";
    /// <summary>True when the file exists.</summary>
    public bool Exists { get; init; }
    /// <summary>Validation findings.</summary>
    public ConfigurationIssue[] Errors { get; init; } = [];
    /// <summary>Reserved for non-fatal findings; always empty today.</summary>
    public object[] Warnings { get; init; } = [];
    /// <summary>Detached sectioned public view.</summary>
    public PSObject Configuration { get; init; } = new();
    /// <summary>Flat key-to-value map in schema order, case-insensitive like a PowerShell ordered map.</summary>
    public OrderedDictionary Values { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Flat key-to-origin map (Default or Yaml).</summary>
    public OrderedDictionary Origins { get; init; } = new(StringComparer.OrdinalIgnoreCase);
}

/// <summary>Reads, validates and publishes the session configuration; PowerShell cmdlets only bind parameters to it.</summary>
public static class ConfigurationService
{
    /// <summary>Selects the automatic config.yaml location using the sole configuration environment override.</summary>
    /// <param name="baseDirectory">Directory for relative overrides.</param>
    public static string DefaultPath(string baseDirectory)
    {
        string? directory = Environment.GetEnvironmentVariable("QUIETCLI_CONFIG_DIRECTORY");
        if (string.IsNullOrWhiteSpace(directory)) directory = "~/.quietcli";
        return Path.Combine(ConfigurationSchema.ResolvePath(directory, baseDirectory), "config.yaml");
    }

    /// <summary>Validates inert YAML without starting an engine or creating any file or database.</summary>
    /// <param name="resolvedPath">Absolute configuration path.</param>
    /// <param name="root">Module root directory.</param>
    public static async Task<ConfigurationSnapshot> ValidateAsync(string resolvedPath, string root)
    {
        var values = new OrderedDictionary(StringComparer.OrdinalIgnoreCase);
        var origins = new OrderedDictionary(StringComparer.OrdinalIgnoreCase);
        foreach (ConfigurationRule rule in ConfigurationSchema.Rules()) { values[rule.Key] = rule.Default; origins[rule.Key] = "Default"; }
        var errors = new List<ConfigurationIssue>();
        bool exists = File.Exists(resolvedPath);
        if (exists) {
            try {
                await ResourceVerifier.VerifyAsync(root, "resources/yaml/YamlDotNet.dll");
                var document = await ConfigurationYaml.ReadAsync(resolvedPath, Path.Combine(root, "resources/yaml/YamlDotNet.dll"));
                CheckVersion(document, errors);
                string directory = Path.GetDirectoryName(resolvedPath)!;
                foreach ((string section, ConfigurationValue node) in document) {
                    if (section == "schemaVersion") continue;
                    if (!ConfigurationSchema.Sections.Contains(section) || node.Value is not IDictionary children) {
                        errors.Add(new("UnknownOrInvalidConfigurationSection", section, node.Line, node.Column)); continue;
                    }
                    foreach (DictionaryEntry child in children) {
                        string key = section + "." + child.Key; var leaf = (ConfigurationValue)child.Value!;
                        try {
                            ConfigurationRule rule = ConfigurationSchema.Find(key) ?? throw new InvalidDataException("UnknownConfigurationKey");
                            values[key] = ConfigurationSchema.Convert(rule, leaf.Value, directory);
                            origins[key] = "Yaml";
                        } catch (Exception error) { errors.Add(new(Innermost(error).Message, key, leaf.Line, leaf.Column)); }
                    }
                }
            } catch (Exception error) {
                Exception inner = Innermost(error);
                errors.Add(inner is ConfigurationYamlException yaml ? new(yaml.Code, yaml.Key, yaml.Line, yaml.Column) : new(inner.Message, "", 0, 0));
            }
        } else if (Directory.Exists(resolvedPath)) errors.Add(new("ConfigurationPathIsDirectory", "", 0, 0));
        return new ConfigurationSnapshot {
            IsValid = errors.Count == 0, Path = resolvedPath, Exists = exists, Errors = [.. errors],
            Configuration = BuildView(values), Values = values, Origins = origins,
        };
    }

    /// <summary>Flags a missing or unsupported schema version at the location of its node.</summary>
    /// <param name="document">Parsed top-level mapping.</param>
    /// <param name="errors">Findings sink.</param>
    private static void CheckVersion(Dictionary<string, ConfigurationValue> document, List<ConfigurationIssue> errors)
    {
        document.TryGetValue("schemaVersion", out ConfigurationValue? node);
        if (node?.Value is long and 1) return;
        errors.Add(new("UnsupportedConfigurationVersion", "schemaVersion", node?.Line ?? 0, node?.Column ?? 0));
    }

    /// <summary>Builds the detached public sectioned view from flat values.</summary>
    /// <param name="values">Flattened closed configuration map.</param>
    public static PSObject BuildView(IDictionary values)
    {
        var sections = new OrderedDictionary(StringComparer.OrdinalIgnoreCase);
        foreach (DictionaryEntry entry in values) {
            string[] parts = ((string)entry.Key).Split('.', 2);
            if (!sections.Contains(parts[0])) sections[parts[0]] = new PSObject();
            ((PSObject)sections[parts[0]]!).Properties.Add(new PSNoteProperty(parts[1], entry.Value));
        }
        var view = new PSObject();
        view.Properties.Add(new PSNoteProperty("schemaVersion", 1));
        foreach (DictionaryEntry section in sections) if ((string)section.Key != "schemaVersion") view.Properties.Add(new PSNoteProperty((string)section.Key, section.Value));
        return view;
    }

    /// <summary>Formats findings for the stable <c>InvalidQuietConfiguration</c> error text.</summary>
    /// <param name="errors">Validation findings.</param>
    public static string InvalidMessage(IEnumerable<ConfigurationIssue> errors) => "InvalidQuietConfiguration: " + JsonSerializer.Serialize(errors);

    /// <summary>Returns the session snapshot, reading the default file the first time.</summary>
    /// <param name="baseDirectory">Directory for relative overrides.</param>
    public static ConfigurationSnapshot Snapshot(string baseDirectory)
    {
        ConfigurationSnapshot? current = QuietSession.Configuration;
        if (current != null) return current;
        ConfigurationSnapshot candidate = ValidateAsync(DefaultPath(baseDirectory), QuietSession.Root).GetAwaiter().GetResult();
        if (!candidate.IsValid) throw new InvalidDataException(InvalidMessage(candidate.Errors));
        return QuietSession.Configuration ??= candidate;
    }

    /// <summary>Walks to the innermost exception, whose message is the stable code.</summary>
    /// <param name="error">Outer exception.</param>
    public static Exception Innermost(Exception error)
    {
        while (error.InnerException != null) error = error.InnerException;
        return error;
    }
}
