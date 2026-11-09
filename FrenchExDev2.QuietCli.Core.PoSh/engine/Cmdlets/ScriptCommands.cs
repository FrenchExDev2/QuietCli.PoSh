using System.Collections;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text;
using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Emits bounded PowerShell literals for plain data without ever evaluating arbitrary objects.</summary>
internal static class ScriptLiteralEncoder
{
    /// <summary>Maximum nesting depth of a literal.</summary>
    internal const int MaximumDepth = 32;

    /// <summary>Maximum number of values (including null) in one script.</summary>
    internal const int MaximumNodes = 10000;

    /// <summary>Maximum number of string characters in one script.</summary>
    internal const int MaximumCharacters = 1048576;

    /// <summary>Numeric types that round-trip through <c>[Type]::Parse</c> with the invariant culture.</summary>
    private static readonly HashSet<Type> Numbers =
    [
        typeof(byte), typeof(sbyte), typeof(short), typeof(ushort), typeof(int), typeof(uint),
        typeof(long), typeof(ulong), typeof(float), typeof(double), typeof(decimal),
    ];

    /// <summary>Array element types that can be restored from a literal.</summary>
    private static readonly HashSet<Type> ElementTypes = [.. Numbers, typeof(object), typeof(string), typeof(char), typeof(bool)];

    /// <summary>Shared limits and ancestor references of one script, so limits apply to the whole definition.</summary>
    internal sealed class Budget
    {
        /// <summary>Values emitted so far.</summary>
        internal int Nodes;

        /// <summary>String characters emitted so far.</summary>
        internal int Characters;

        /// <summary>Containers currently being emitted, used to reject cycles.</summary>
        internal readonly List<object> Ancestors = [];
    }

    /// <summary>Encodes one value as a PowerShell expression.</summary>
    /// <param name="value">A primitive, array of primitives, hashtable or ordered dictionary.</param>
    /// <param name="budget">Shared limits.</param>
    /// <param name="depth">Current nesting depth.</param>
    internal static string Encode(object? value, Budget budget, int depth = 0)
    {
        value = QuietRuntime.Unwrap(value);
        budget.Nodes++;
        if (depth > MaximumDepth || budget.Nodes > MaximumNodes) throw new InvalidOperationException("QuietScriptLiteralLimit");
        if (value is null) return "$null";
        Type type = value.GetType();
        if (type == typeof(string) || type == typeof(char))
        {
            string text = value.ToString()!;
            budget.Characters += text.Length;
            if (budget.Characters > MaximumCharacters) throw new InvalidOperationException("QuietScriptLiteralLimit");
            // PowerShell also accepts U+2018..U+201B as single-quote delimiters; the engine helper doubles every one of them.
            string literal = "'" + CodeGeneration.EscapeSingleQuotedStringContent(text).Replace("\r", "' + [char]13 + '").Replace("\n", "' + [char]10 + '") + "'";
            return type == typeof(char) ? $"[char]({literal})" : $"({literal})";
        }
        if (type == typeof(bool)) return (bool)value ? "$true" : "$false";
        if (Numbers.Contains(type))
        {
            if (value is double d && !double.IsFinite(d) || value is float f && !float.IsFinite(f)) throw new InvalidOperationException("QuietScriptNonFiniteNumber");
            string? format = type == typeof(float) || type == typeof(double) ? "R" : null;
            string text = ((IFormattable)value).ToString(format, CultureInfo.InvariantCulture);
            return $"[{type.FullName}]::Parse('{text}', [Globalization.CultureInfo]::InvariantCulture)";
        }
        if (value is not Array && type != typeof(Hashtable) && type != typeof(OrderedDictionary))
            throw new InvalidOperationException($"QuietScriptUnsupportedValue: {type.FullName}. Use DataFactory or StateFactory for complex business values.");
        foreach (object ancestor in budget.Ancestors)
            if (ReferenceEquals(ancestor, value)) throw new InvalidOperationException("QuietScriptCyclicValue");
        budget.Ancestors.Add(value);
        try
        {
            var parts = new List<string>();
            if (value is Array array)
            {
                if (array.Rank != 1) throw new InvalidOperationException("QuietScriptMultidimensionalArray");
                Type element = type.GetElementType()!;
                if (!ElementTypes.Contains(element)) throw new InvalidOperationException("QuietScriptUnsupportedArrayType");
                foreach (object? item in array) parts.Add(Encode(item, budget, depth + 1));
                return $"[{element.FullName}[]]@(" + string.Join(", ", parts) + ")";
            }
            var dictionary = (IDictionary)value;
            foreach (object key in dictionary.Keys)
                parts.Add(Encode(key, budget, depth + 1) + " = " + Encode(dictionary[key], budget, depth + 1));
            return (type == typeof(Hashtable) ? "@{" : "[ordered]@{") + string.Join("; ", parts) + "}";
        }
        finally { budget.Ancestors.RemoveAt(budget.Ancestors.Count - 1); }
    }
}

/// <summary>Builds the source of a reusable call definition from explicit facade options.</summary>
internal static class ScriptDefinitionBuilder
{
    /// <summary>Largest generated definition, in characters.</summary>
    internal const int MaximumSourceCharacters = 2097152;

    /// <summary>Options that cannot be replayed from a script.</summary>
    private static readonly Regex Unsupported = new("Recall|^(SaveRecall|Zip|Compress|AllowPartial|CancellationToken)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>Options emitted as switches.</summary>
    private static readonly string[] Switches = ["AsObject", "AsJson", "AsYaml"];

    /// <summary>Options holding callbacks whose source is copied verbatim.</summary>
    private static readonly string[] Callbacks = ["Output", "Complete", "DataFactory", "StateFactory", "Interaction"];

    /// <summary>Options derived from the generated parameters rather than stored.</summary>
    private static readonly string[] Derived = ["Script", "FilePath", "ArgumentList", "WorkingDirectory"];

    private const string Header = """
        #requires -Version 7.6
        #requires -PSEdition Core
        <#
        .SYNOPSIS
        Executes a reusable QuietCli call with fresh business initialization.
        .DESCRIPTION
        External variables, functions and modules used by callbacks must be supplied explicitly.
        Closures are not captured. Explicit option values, including environment values, are stored here.
        Unspecified options use the active QuietCli configuration when this script executes.
        .PARAMETER FilePath
        Native executable, resolved only when executing this script.
        .PARAMETER ArgumentList
        Exact native arguments.
        .PARAMETER WorkingDirectory
        Native working directory; defaults to the directory selected during generation.
        #>
        """;

    private const string Prologue = """
        if (!(Get-Module -Name __QUIET_MODULE__)) {
            Import-Module __QUIET_MODULE__ -MinimumVersion 0.2.0 -ErrorAction Stop
        }
        $quietArguments = [Collections.Generic.List[object]]::new()
        """;

    private const string Epilogue = """
        $quietArguments.Add('-WorkingDirectory')
        $quietArguments.Add($WorkingDirectory)
        $quietArguments.Add('-FilePath')
        $quietArguments.Add($FilePath)
        $quietArguments.Add('-ArgumentList')
        $quietArguments.Add($ArgumentList)
        $callArguments = $quietArguments.ToArray()
        __QUIET_MODULE__\Invoke-QuietCli @callArguments
        """;

    /// <summary>Validates the options and renders the definition; nothing is executed or written.</summary>
    /// <param name="request">Explicit facade options before configuration defaults are applied.</param>
    /// <param name="currentDirectory">Directory anchoring relative paths.</param>
    /// <param name="path">Absolute, validated destination of the definition.</param>
    internal static string Build(Hashtable request, string currentDirectory, out string path)
    {
        if (!request.ContainsKey("Output") && !request.ContainsKey("Complete")) throw new InvalidOperationException("QuietScriptCallbackRequired");
        foreach (object key in request.Keys)
            if (Unsupported.IsMatch(Convert.ToString(key, CultureInfo.InvariantCulture) ?? "")) throw new InvalidOperationException($"QuietScriptUnsupportedOption: {key}");
        path = Path.GetFullPath(Text(request["Script"]), currentDirectory);
        if (!string.Equals(Path.GetExtension(path), ".ps1", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("QuietScriptExtensionRequired");
        if (!Directory.Exists(Path.GetDirectoryName(path))) throw new InvalidOperationException("QuietScriptParentMissing");
        if (PathGuard.HasLinkedAncestor(path)) throw new InvalidOperationException("QuietScriptLinkRejected");
        if (File.Exists(path) || Directory.Exists(path)) throw new InvalidOperationException("QuietScriptAlreadyExists");
        var budget = new ScriptLiteralEncoder.Budget();
        string binary = ScriptLiteralEncoder.Encode(request["FilePath"], budget);
        string arguments = ScriptLiteralEncoder.Encode(AsStringArray(request["ArgumentList"]), budget);
        string directory = request.ContainsKey("WorkingDirectory") ? Path.GetFullPath(Text(request["WorkingDirectory"]), currentDirectory) : currentDirectory;
        string working = ScriptLiteralEncoder.Encode(directory, budget);
        var lines = new List<string>
        {
            Header,
            $"param([string]$FilePath = {binary}, [string[]]$ArgumentList = {arguments}, [string]$WorkingDirectory = {working})",
            Prologue.Replace("__QUIET_MODULE__", QuietSession.ModuleName, StringComparison.Ordinal),
        };
        foreach (string key in request.Keys.Cast<object>().Select(k => Convert.ToString(k, CultureInfo.InvariantCulture) ?? "").OrderBy(k => k, StringComparer.OrdinalIgnoreCase))
        {
            if (Derived.Contains(key, StringComparer.OrdinalIgnoreCase)) continue;
            object? value = QuietRuntime.Unwrap(request[key]);
            string literal;
            if (Callbacks.Contains(key, StringComparer.OrdinalIgnoreCase))
            {
                if (value is not ScriptBlock block) throw new InvalidOperationException($"QuietScriptCallbackMustBeScriptBlock: {key}");
                literal = "{\n" + block + "\n}";
            }
            else literal = ScriptLiteralEncoder.Encode(value, budget);
            if (Switches.Contains(key, StringComparer.OrdinalIgnoreCase))
                lines.Add($"$quietArguments.Add('-{key}:{(LanguagePrimitives.IsTrue(value) ? "True" : "False")}')");
            else
            {
                lines.Add($"$quietArguments.Add('-{key}')");
                lines.Add($"$quietArguments.Add(({literal}))");
            }
        }
        lines.Add(Epilogue.Replace("__QUIET_MODULE__", QuietSession.ModuleName, StringComparison.Ordinal));
        string source = string.Join("\n", lines).Replace("\r\n", "\n").Replace("\r", "\n") + "\n";
        if (source.Length > MaximumSourceCharacters) throw new InvalidOperationException("QuietScriptSourceLimit");
        Parser.ParseInput(source, out _, out ParseError[] errors);
        if (errors.Length > 0) throw new InvalidOperationException("QuietScriptInvalidSource: " + errors[0].Message);
        return source;
    }

    private static string Text(object? value) => Convert.ToString(QuietRuntime.Unwrap(value), CultureInfo.InvariantCulture) ?? "";

    /// <summary>Mirrors the PowerShell <c>[string[]]</c> cast: null stays null and a scalar becomes one element.</summary>
    private static string[]? AsStringArray(object? value) => QuietRuntime.Unwrap(value) switch
    {
        null => null,
        string[] strings => strings,
        string single => [single],
        IEnumerable items => items.Cast<object?>().Select(Text).ToArray(),
        { } other => [Text(other)],
    };
}

/// <summary>Writes an explicit call definition without executing callbacks or native code.</summary>
[Cmdlet(VerbsData.Export, "QuietCallScript")]
public sealed class ExportQuietCallScriptCommand : QuietCmdlet
{
    /// <summary>Explicit facade options, including the destination <c>Script</c>.</summary>
    [Parameter(Position = 0, Mandatory = true)]
    public Hashtable Request { get; set; } = new();

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(Write(Request, CurrentDirectory)); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }

    /// <summary>Renders the definition and creates the file exclusively, removing it again if the write fails.</summary>
    /// <param name="request">Explicit facade options.</param>
    /// <param name="currentDirectory">Directory anchoring relative paths.</param>
    internal static FileInfo Write(Hashtable request, string currentDirectory)
    {
        string source = ScriptDefinitionBuilder.Build(request, currentDirectory, out string path);
        byte[] bytes = new UTF8Encoding(false, true).GetBytes(source);
        FileStream? stream = null;
        try
        {
            stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, true);
            stream.WriteAsync(bytes, 0, bytes.Length).GetAwaiter().GetResult();
            stream.Dispose();
            stream = null;
        }
        catch
        {
            if (stream is not null) { stream.Dispose(); File.Delete(path); }
            throw;
        }
        return new FileInfo(path);
    }
}
