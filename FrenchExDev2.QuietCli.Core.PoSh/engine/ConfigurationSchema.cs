using System.Globalization;
using System.Text;

namespace FrenchExDev2.QuietCli;

/// <summary>One closed configuration setting: its type, default and accepted range.</summary>
/// <param name="Key">Section-qualified name such as <c>delivery.maxItems</c>.</param>
/// <param name="Type">enum, boolean, integer, number, path, optionalPath or recallSize.</param>
/// <param name="Default">Built-in value used when the YAML file omits the key.</param>
/// <param name="Min">Inclusive lower bound for numeric types.</param>
/// <param name="Max">Inclusive upper bound for numeric types.</param>
/// <param name="Values">Case-sensitive accepted names for enum types.</param>
public sealed record ConfigurationRule(string Key, string Type, object? Default, double Min = 0, double Max = 0, string[]? Values = null);

/// <summary>Single definition of configuration defaults, validation and the generated template.</summary>
public static class ConfigurationSchema
{
    /// <summary>Sections accepted at the top level of the YAML document, in template order.</summary>
    public static IReadOnlyList<string> Sections { get; } = ["tokenization", "delivery", "execution", "telemetry", "engine", "streams", "recall", "gain"];

    /// <summary>Builds the ordered rule list; the database default follows the current user profile.</summary>
    public static IReadOnlyList<ConfigurationRule> Rules()
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return
        [
            new("tokenization.tokenizer", "enum", "o200k_base", Values: ["off", "o200k_base", "cl100k_base"]),
            new("delivery.maxOutputBytes", "integer", 4096, RequestLimits.MinOutputBytes, int.MaxValue),
            new("delivery.maxItems", "integer", 20, 0, int.MaxValue),
            new("delivery.maxTrackedRepresentations", "integer", 256, 1, 65536),
            new("execution.timeoutSeconds", "number", 600.0, 0.001, RequestLimits.MaxTimeoutSeconds),
            new("execution.drainTimeoutSeconds", "number", 30.0, RequestLimits.MinDrainTimeoutSeconds, RequestLimits.MaxDrainTimeoutSeconds),
            new("telemetry.enabled", "boolean", true),
            new("telemetry.database", "path", Path.Combine(home, ".quietcli2", "gains.sqlite")),
            new("engine.hosting", "enum", "Auto", Values: ["Auto", "Process", "InProcess"]),
            new("engine.ipcTimeoutSeconds", "number", 30.0, RequestLimits.MinDrainTimeoutSeconds, RequestLimits.MaxDrainTimeoutSeconds),
            new("streams.transport", "enum", "Pipe", Values: ["Pipe", "Pty"]),
            new("streams.stdoutMode", "enum", "Text", Values: ["Text", "Bytes"]),
            new("streams.stderrMode", "enum", "Text", Values: ["Text", "Bytes"]),
            new("streams.maxRecordBytes", "integer", 1048576, 1, int.MaxValue),
            new("streams.readBlockBytes", "integer", 16384, RequestLimits.MinReadBlockBytes, ProtocolSpecification.BlockSize),
            new("recall.maxBytes", "recallSize", "16MiB"),
            new("recall.policy", "enum", "Head", Values: ["Head", "Tail", "HeadAndTail"]),
            new("recall.root", "optionalPath", null),
            new("gain.maxEvents", "integer", 10000, 1, 1000000),
        ];
    }

    /// <summary>Finds a rule by its exact, case-sensitive key.</summary>
    /// <param name="key">Section-qualified setting name.</param>
    public static ConfigurationRule? Find(string key) => Rules().FirstOrDefault(rule => string.Equals(rule.Key, key, StringComparison.Ordinal));

    /// <summary>Resolves a literal path, expanding only a leading user-home marker.</summary>
    /// <param name="path">Literal path; no environment or expression interpolation.</param>
    /// <param name="baseDirectory">Absolute directory for relative paths.</param>
    public static string ResolvePath(string path, string baseDirectory)
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (path == "~") path = home;
        else if (path.StartsWith("~/", StringComparison.Ordinal) || path.StartsWith("~\\", StringComparison.Ordinal)) path = Path.Combine(home, path[2..]);
        return Path.GetFullPath(path, baseDirectory);
    }

    /// <summary>Validates one YAML scalar and returns its normalized value, or throws a stable code.</summary>
    /// <param name="rule">Closed rule of the setting.</param>
    /// <param name="value">Typed YAML scalar or nested mapping.</param>
    /// <param name="baseDirectory">Source directory used for relative paths.</param>
    /// <exception cref="InvalidDataException">The message is the stable validation code.</exception>
    public static object? Convert(ConfigurationRule rule, object? value, string baseDirectory)
    {
        switch (rule.Type)
        {
            case "enum":
                if (value is not string name || Array.IndexOf(rule.Values!, name) < 0) throw new InvalidDataException("InvalidConfigurationEnum");
                return value;
            case "boolean":
                if (value is not bool) throw new InvalidDataException("InvalidConfigurationBoolean");
                return value;
            case "integer":
            case "number":
                if (value is bool || !TryNumber(value, out double number) || !double.IsFinite(number) || number < rule.Min || number > rule.Max) throw new InvalidDataException("InvalidConfigurationNumber");
                if (rule.Type == "integer")
                {
                    if (value is not (long or int)) throw new InvalidDataException("InvalidConfigurationInteger");
                    return System.Convert.ToInt32(value, CultureInfo.InvariantCulture);
                }
                return number;
            case "path":
            case "optionalPath":
                if (value is null && rule.Type == "optionalPath") return null;
                if (value is not string path || string.IsNullOrWhiteSpace(path)) throw new InvalidDataException("InvalidConfigurationPath");
                return ResolvePath(path, baseDirectory);
            case "recallSize":
                if (value is not (string or long or int)) throw new InvalidDataException("InvalidConfigurationRecallSize");
                string text = System.Convert.ToString(value, CultureInfo.InvariantCulture)!;
                RecallOptions.ParseSize(text);
                return text;
            default:
                return value;
        }
    }

    /// <summary>Renders the complete UTF-8/LF configuration template with every default value.</summary>
    public static string RenderTemplate()
    {
        var text = new StringBuilder("schemaVersion: 1\n");
        string section = "";
        foreach (var rule in Rules())
        {
            int dot = rule.Key.IndexOf('.');
            if (rule.Key[..dot] != section) { section = rule.Key[..dot]; text.Append(section).Append(":\n"); }
            text.Append("  ").Append(rule.Key[(dot + 1)..]).Append(": ").Append(Scalar(rule.Default)).Append('\n');
        }
        return text.ToString();
    }

    /// <summary>Accepts only numeric CLR types; booleans and other value types are not numbers.</summary>
    private static bool TryNumber(object? value, out double number)
    {
        switch (value)
        {
            case sbyte or byte or short or ushort or int or uint or long or ulong or float or double or decimal:
                number = System.Convert.ToDouble(value, CultureInfo.InvariantCulture); return true;
            default:
                number = 0; return false;
        }
    }

    /// <summary>Renders a default as a compact JSON scalar, which is also a valid YAML flow scalar.</summary>
    private static string Scalar(object? value) => value switch
    {
        null => "null",
        bool flag => flag ? "true" : "false",
        string text => Quote(text),
        double number => Number(number),
        _ => System.Convert.ToString(value, CultureInfo.InvariantCulture)!,
    };

    private static string Number(double number)
    {
        string text = number.ToString("R", CultureInfo.InvariantCulture);
        return text.Contains('.') || text.Contains('E') ? text : text + ".0";
    }

    private static string Quote(string text)
    {
        var quoted = new StringBuilder("\"");
        foreach (char c in text)
        {
            switch (c)
            {
                case '"': quoted.Append("\\\""); break;
                case '\\': quoted.Append("\\\\"); break;
                case '\b': quoted.Append("\\b"); break;
                case '\f': quoted.Append("\\f"); break;
                case '\n': quoted.Append("\\n"); break;
                case '\r': quoted.Append("\\r"); break;
                case '\t': quoted.Append("\\t"); break;
                case < ' ': quoted.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture)); break;
                default: quoted.Append(c); break;
            }
        }
        return quoted.Append('"').ToString();
    }
}
