using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Language;

namespace FrenchExDev2.QuietCli.Cmdlets;

internal enum InvocationDelivery { Object, Json, Yaml }

/// <summary>Resolves presentation and delivery once, independently of native execution.</summary>
internal sealed record InvocationPolicy(string Mode, int? UiMaxLines, InvocationDelivery Delivery)
{
    private static readonly Dictionary<string, (string Mode, bool Ui, InvocationDelivery Delivery)> Defaults = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Agent"] = ("Agent", false, InvocationDelivery.Json),
        ["User"] = ("User", true, InvocationDelivery.Yaml),
        ["Script"] = ("Script", false, InvocationDelivery.Object),
    };

    /// <summary>Returns the parsed facade policy or resolves an internal request as a script call.</summary>
    internal static InvocationPolicy ForRequest(Hashtable request) =>
        request["InvocationPolicy"] as InvocationPolicy ?? Resolve(request, false);

    /// <summary>Validates explicit overrides and supplies the defaults for the selected mode.</summary>
    internal static InvocationPolicy Resolve(Hashtable request, bool interactivePrompt)
    {
        string mode = request.ContainsKey("Mode")
            ? LanguagePrimitives.ConvertTo<string>(request["Mode"]) ?? ""
            : interactivePrompt ? "User" : "Script";
        if (!Defaults.TryGetValue(mode, out var defaults)) throw new InvalidOperationException("InvalidQuietMode");

        InvocationDelivery delivery = ExplicitDelivery(request) ?? defaults.Delivery;
        if (defaults.Mode == "Agent" && delivery == InvocationDelivery.Object)
            throw new InvalidOperationException("AgentModeRequiresJsonOrYaml");

        bool ui = request.ContainsKey("UI") ? Flag(request, "UI") : defaults.Ui;
        if (request.ContainsKey("MaxLines") && !ui) throw new InvalidOperationException("MaxLinesRequiresUI");
        int? maxLines = null;
        if (ui)
        {
            maxLines = request.ContainsKey("MaxLines")
                ? Convert.ToInt32(QuietRuntime.Unwrap(request["MaxLines"]), CultureInfo.InvariantCulture) : 1;
            if (maxLines <= 0) throw new InvalidOperationException("MaxLinesMustBePositive");
        }
        return new(defaults.Mode, maxLines, delivery);
    }

    /// <summary>Reads a selected format, rejecting simultaneous truthy switches.</summary>
    internal static InvocationDelivery? ExplicitDelivery(Hashtable request)
    {
        bool asObject = Flag(request, "AsObject"), asJson = Flag(request, "AsJson"), asYaml = Flag(request, "AsYaml");
        if ((asObject && (asJson || asYaml)) || (asJson && asYaml)) throw new InvalidOperationException("OutputFormatsAreExclusive");
        if (asObject) return InvocationDelivery.Object;
        if (asJson) return InvocationDelivery.Json;
        return asYaml ? InvocationDelivery.Yaml : null;
    }

    private static bool Flag(Hashtable request, string name) => LanguagePrimitives.IsTrue(request[name]);
}

/// <summary>Converts native arguments consistently for display, reusable definitions and launch.</summary>
internal static class NativeCommandLine
{
    /// <summary>Converts the exact vector, preserving empty arguments and order.</summary>
    internal static string[] Arguments(object? value) => QuietRuntime.Unwrap(value) switch
    {
        null => [],
        string[] strings => strings,
        string single => [single],
        IEnumerable items => items.Cast<object?>().Select(Text).ToArray(),
        { } single => [Text(single)],
    };

    /// <summary>Formats the original executable token and its arguments for inspection.</summary>
    internal static string? Display(Hashtable request)
    {
        if (!request.ContainsKey("FilePath")) return null;
        return string.Join(" ", Arguments(request["ArgumentList"]).Prepend(Text(request["FilePath"])).Select(Quote));
    }

    private static string Text(object? value) => Convert.ToString(QuietRuntime.Unwrap(value), CultureInfo.InvariantCulture) ?? "";

    private static string Quote(string value) =>
        value.Length > 0 && value.All(character => char.IsLetterOrDigit(character) || "_./:\\-".Contains(character))
            ? value : "'" + CodeGeneration.EscapeSingleQuotedStringContent(value) + "'";
}
