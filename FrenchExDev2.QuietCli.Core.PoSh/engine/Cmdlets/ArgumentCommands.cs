using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Separates exact facade options from the uninterpreted native argument vector; internal to the module.</summary>
[Cmdlet(VerbsCommunications.Read, "QuietArguments")]
[OutputType(typeof(Hashtable))]
public sealed class ReadQuietArgumentsCommand : QuietCmdlet
{
    /// <summary>Boolean facade switches; a trailing colon form carries an explicit value.</summary>
    private static readonly string[] Switches = ["AsObject", "AsJson", "AsYaml", "Recall", "SaveRecall", "Zip", "AllowPartial"];

    /// <summary>Facade options that consume the following argument.</summary>
    private static readonly string[] Values =
    [
        "Output", "Complete", "Context", "Data", "State", "WorkingDirectory", "TimeoutSeconds", "DrainTimeoutSeconds", "Environment", "Transport",
        "StdoutMode", "StderrMode", "InputText", "InputBytes", "InputPath", "Interaction", "RecordDelimiter", "MaxRecordBytes", "MaxOutputBytes",
        "MaxItems", "Role", "HandlerId", "CancellationFile", "CancellationToken", "Projection", "Tokenizer", "FilePath", "ArgumentList", "TerminalSize",
        "SuccessExitCodes", "ReadBlockBytes", "RecallMaxBytes", "RecallPolicy", "RecallId", "RecallName", "RecallRoot", "Compress", "Script",
        "DataFactory", "StateFactory",
    ];

    /// <summary>Options a saved-capture replay may combine with its identifier.</summary>
    private static readonly string[] ReplayAllowed =
    [
        "RecallId", "RecallRoot", "AsObject", "AsJson", "AsYaml", "Output", "Complete", "Data", "State", "StdoutMode", "StderrMode",
        "RecordDelimiter", "MaxRecordBytes", "Projection", "AllowPartial", "MaxItems", "MaxOutputBytes", "Tokenizer",
    ];

    /// <summary>Options forwarded to the offline replay.</summary>
    private static readonly string[] ReplayForwarded =
        ["Output", "Complete", "Data", "State", "StdoutMode", "StderrMode", "RecordDelimiter", "MaxRecordBytes", "Projection", "AllowPartial"];

    /// <summary>Matches the colon form of a switch such as -AsObject:$false.</summary>
    private static readonly Regex Colon = new("^([^:]+):(.*)$", RegexOptions.Compiled | RegexOptions.Singleline);

    /// <summary>Original arguments received by Invoke-QuietCli.</summary>
    [Parameter(Position = 0)]
    public object?[] Arguments { get; set; } = [];

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(Parse()); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }

    /// <summary>Case-insensitive membership, matching PowerShell -in.</summary>
    private static string? Canonical(string[] names, string name) => names.FirstOrDefault(n => string.Equals(n, name, StringComparison.OrdinalIgnoreCase));

    /// <summary>Converts with PowerShell string-cast semantics.</summary>
    private static string Text(object? value) => LanguagePrimitives.ConvertTo<string>(value) ?? "";

    /// <summary>Parses, validates and completes the request.</summary>
    private Hashtable Parse()
    {
        object?[] args = Arguments ?? [];
        var request = new Hashtable(StringComparer.OrdinalIgnoreCase);
        int index = 0;
        while (index < args.Length)
        {
            if (QuietRuntime.Unwrap(args[index]) is not string argument || !argument.StartsWith('-') || argument == "--") break;
            string name = argument.TrimStart('-');
            bool switchValue = true;
            Match match = Colon.Match(name);
            if (match.Success)
            {
                name = match.Groups[1].Value;
                string suffix = match.Groups[2].Value;
                if (suffix.Length > 0) switchValue = bool.Parse(suffix);
                else if (index + 1 < args.Length) { index++; switchValue = LanguagePrimitives.IsTrue(args[index]); }
            }
            if (string.Equals(name, "C", StringComparison.OrdinalIgnoreCase)) name = "Context";
            if (Canonical(Switches, name) is { } flag) { request[flag] = switchValue; index++; continue; }
            if (Canonical(Values, name) is not { } option) throw new InvalidOperationException("UnknownQuietOption: " + argument);
            index++;
            if (index >= args.Length) throw new InvalidOperationException("MissingQuietOptionValue: " + option);
            request[option] = args[index];
            index++;
        }
        if (index < args.Length && QuietRuntime.Unwrap(args[index]) is string separator && separator == "--") index++;
        if (request.ContainsKey("RecallId"))
        {
            if (index != args.Length || request.Keys.Cast<string>().Any(key => Canonical(ReplayAllowed, key) is null)) throw new InvalidOperationException("RecallReplayCannotExecute");
            if (!request.ContainsKey("Output") && !request.ContainsKey("Complete")) throw new InvalidOperationException("RecallAnalysisCallbackRequired");
            var replay = new Hashtable(StringComparer.OrdinalIgnoreCase);
            foreach (string key in ReplayForwarded) if (request.ContainsKey(key)) replay[key] = request[key];
            request["ReplayOptions"] = replay;
        }
        else if (!request.ContainsKey("FilePath"))
        {
            if (index >= args.Length) throw new InvalidOperationException("MissingExecutable");
            request["FilePath"] = Text(args[index]);
            index++;
        }
        if (!request.ContainsKey("ArgumentList")) request["ArgumentList"] = ReadNativeArguments(args, ref index);
        else if (index != args.Length) throw new InvalidOperationException("UnexpectedArgumentsAfterArgumentList");
        foreach (string name in new[] { "Data", "State" })
        {
            string factory = name + "Factory";
            if (!request.ContainsKey(factory)) continue;
            if (request.ContainsKey(name)) throw new InvalidOperationException("QuietFactoryConflict: " + name);
            if (QuietRuntime.Unwrap(request[factory]) is not ScriptBlock) throw new InvalidOperationException("QuietFactoryMustBeScriptBlock: " + factory);
        }
        Hashtable? exportRequest = null;
        if (request.ContainsKey("Script"))
        {
            foreach (string key in request.Keys)
                if (key.Contains("Recall", StringComparison.OrdinalIgnoreCase) || Canonical(["Zip", "Compress", "AllowPartial", "CancellationToken"], key) is not null)
                    throw new InvalidOperationException("QuietScriptUnsupportedOption: " + key);
            exportRequest = (Hashtable)request.Clone();
        }
        IDictionary configuration = ConfigurationService.Snapshot(CurrentDirectory).Values;
        string location = SessionState.Path.CurrentLocation.Path;
        var defaults = new Hashtable
        {
            ["WorkingDirectory"] = location, ["TimeoutSeconds"] = configuration["execution.timeoutSeconds"], ["DrainTimeoutSeconds"] = configuration["execution.drainTimeoutSeconds"],
            ["Environment"] = new Hashtable(), ["Transport"] = configuration["streams.transport"], ["StdoutMode"] = configuration["streams.stdoutMode"],
            ["StderrMode"] = configuration["streams.stderrMode"], ["MaxRecordBytes"] = configuration["streams.maxRecordBytes"],
            ["MaxOutputBytes"] = configuration["delivery.maxOutputBytes"], ["MaxItems"] = configuration["delivery.maxItems"], ["Role"] = "Business",
            ["Tokenizer"] = configuration["tokenization.tokenizer"], ["TerminalSize"] = new object[] { 120, 40 }, ["SuccessExitCodes"] = new object[] { 0 },
            ["ReadBlockBytes"] = configuration["streams.readBlockBytes"],
        };
        foreach (DictionaryEntry entry in defaults) if (!request.ContainsKey(entry.Key)) request[entry.Key] = entry.Value;
        if (new[] { "AsObject", "AsJson", "AsYaml" }.Count(key => Flag(request, key)) > 1) throw new InvalidOperationException("OutputFormatsAreExclusive");
        bool saving = Flag(request, "SaveRecall");
        if (request.ContainsKey("AllowPartial") && !request.ContainsKey("RecallId")) throw new InvalidOperationException("AllowPartialRequiresReplay");
        if (saving && !Flag(request, "AsObject")) throw new InvalidOperationException("SaveRecallRequiresExplicitAsObject");
        if (request.ContainsKey("RecallName"))
        {
            string recallName = Text(request["RecallName"]);
            if ((!saving && !Flag(request, "Recall")) || string.IsNullOrWhiteSpace(recallName) || recallName.Length > 256) throw new InvalidOperationException("InvalidRecallName");
        }
        if (request.ContainsKey("RecallRoot") && !saving && !request.ContainsKey("RecallId")) throw new InvalidOperationException("RecallRootRequiresSaveOrReplay");
        if (Flag(request, "Zip") && !saving) throw new InvalidOperationException("ZipRequiresSaveRecall");
        if (request.ContainsKey("Compress"))
        {
            if (!Flag(request, "Zip") || !TryParseCompression(Text(request["Compress"]), out int level))
                throw new InvalidOperationException("InvalidRecallCompression");
            request["Compress"] = level;
        }
        if (Flag(request, "Recall") || request.ContainsKey("RecallMaxBytes") || request.ContainsKey("RecallPolicy"))
        {
            if (!Flag(request, "Recall") || !Flag(request, "AsObject")) throw new InvalidOperationException("RecallRequiresExplicitAsObject");
            string size = request.ContainsKey("RecallMaxBytes") ? Text(request["RecallMaxBytes"]) : Text(configuration["recall.maxBytes"]);
            string policy = request.ContainsKey("RecallPolicy") ? Text(request["RecallPolicy"]) : Text(configuration["recall.policy"]);
            request["RecallOptions"] = new RecallOptions(size, policy);
        }
        if (new[] { "InputText", "InputBytes", "InputPath", "Interaction" }.Count(request.ContainsKey) > 1) throw new InvalidOperationException("InputOptionsAreExclusive");
        string? limitError = FacadeOptionValidator.FirstError(
            Text(request["Tokenizer"]), Text(request["Transport"]), Text(request["StdoutMode"]), Text(request["StderrMode"]), Text(request["Role"]),
            Number(request["TimeoutSeconds"]), Number(request["MaxRecordBytes"]), Number(request["MaxOutputBytes"]), Number(request["MaxItems"]),
            Number(request["DrainTimeoutSeconds"]), Number(request["ReadBlockBytes"]), LanguagePrimitives.ConvertTo<double[]>(request["TerminalSize"]));
        if (!string.IsNullOrEmpty(limitError)) throw new InvalidOperationException(limitError);
        request["WorkingDirectory"] = Path.GetFullPath(Text(request["WorkingDirectory"]), CurrentDirectory);
        if (request.ContainsKey("Context") && string.IsNullOrWhiteSpace(Text(request["Context"]))) throw new InvalidOperationException("EmptyExplicitContext");
        if (request.ContainsKey("RecordDelimiter") && Text(request["RecordDelimiter"]).Length == 0) throw new InvalidOperationException("EmptyRecordDelimiter");
        return exportRequest ?? request;
    }

    /// <summary>Collects the verbatim native argument vector that follows the executable.</summary>
    /// <param name="args">Original arguments.</param>
    /// <param name="index">Position of the first native argument; advanced to the end.</param>
    private static string[] ReadNativeArguments(object?[] args, ref int index)
    {
        var native = new List<string>();
        while (index < args.Length)
        {
            object? raw = args[index];
            object? argument = QuietRuntime.Unwrap(raw);
            index++;
            if (argument is ScriptBlock or IDictionary) throw new InvalidOperationException("QuietOptionsMustPrecedeExecutable");
            if (argument is string text && text.EndsWith(':') && raw is PSObject wrapped && wrapped.Properties["<CommandParameterName>"] is not null && index < args.Length)
            {
                native.Add(text + Text(args[index]));
                index++;
                continue;
            }
            if (argument is IEnumerable sequence && argument is not string)
            {
                foreach (object? value in sequence) if (value is not null) native.Add(Text(value));
            }
            else if (argument is not null) native.Add(Text(argument));
        }
        return native.ToArray();
    }

    /// <summary>Parses a ZIP compression level; only the integers 0 through 9 are valid.</summary>
    /// <param name="text">Invariant-culture integer text.</param>
    /// <param name="level">Parsed level when valid.</param>
    public static bool TryParseCompression(string text, out int level) =>
        int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out level) && level >= 0 && level <= 9;

    /// <summary>True when the switch is present and truthy.</summary>
    private static bool Flag(Hashtable request, string key) => request.ContainsKey(key) && LanguagePrimitives.IsTrue(request[key]);

    /// <summary>Converts with PowerShell [double] semantics.</summary>
    private static double Number(object? value) => LanguagePrimitives.ConvertTo<double>(value);
}
