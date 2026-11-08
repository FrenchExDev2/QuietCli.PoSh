using System.Collections;
using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Base of the Git module cmdlets: stable error codes, no compile-time dependency on the Core engine.</summary>
public abstract class GitCmdlet : PSCmdlet
{
    /// <summary>Raises a terminating error whose exception message is the stable code.</summary>
    /// <param name="code">Stable error code or code-and-detail text.</param>
    protected void Fail(string code) =>
        ThrowTerminatingError(new ErrorRecord(new InvalidOperationException(code), code.Split(':')[0], ErrorCategory.InvalidOperation, null));

    /// <summary>Converts a PowerShell value to the string a native command would receive.</summary>
    /// <param name="value">Argument value, possibly wrapped in a PSObject.</param>
    protected static string Text(object? value) => value switch
    {
        null => "",
        PSObject wrapped => Text(wrapped.BaseObject),
        string text => text,
        _ => LanguagePrimitives.ConvertTo<string>(value),
    };
}

/// <summary>Binds Git global options and the command name without executing a binary.</summary>
[Cmdlet(VerbsCommon.Get, "GitInvocation")]
[OutputType(typeof(Hashtable))]
public sealed class GetGitInvocationCommand : GitCmdlet
{
    /// <summary>Caller request whose ArgumentList is the original native argument vector.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public Hashtable Invocation { get; set; } = new();

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        object? list = Invocation["ArgumentList"] is PSObject wrapped ? wrapped.BaseObject : Invocation["ArgumentList"];
        IEnumerable<object?> items = list switch { null => [], string single => [single], IEnumerable many => many.Cast<object?>(), _ => [list] };
        GitInvocation bound = GitInvocationBinder.Bind(items.Select(Text).ToArray());
        var result = new Hashtable();
        if (bound.Error is not null) { result["Error"] = bound.Error; result["Reason"] = bound.Reason; }
        else
        {
            result["Name"] = bound.Name;
            result["Global"] = bound.Global;
            result["GlobalNames"] = bound.GlobalNames;
            result["Arguments"] = bound.Arguments;
            result["Original"] = bound.Original;
        }
        WriteObject(result);
    }
}

/// <summary>Reads and caches the module-owned argument grammar without native execution.</summary>
[Cmdlet(VerbsCommon.Get, "GitArgumentSchema")]
[OutputType(typeof(Hashtable))]
public sealed class GetGitArgumentSchemaCommand : GitCmdlet
{
    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { if (GitArgumentSchemaStore.Load() is { } schema) WriteObject(schema); }
        catch (Exception error) when (error is InvalidDataException or System.Text.Json.JsonException or IOException) { Fail(error.Message); }
    }
}

/// <summary>Binds options, values, operands and literal separators without executing Git.</summary>
[Cmdlet(VerbsCommon.Get, "GitArgumentToken", DefaultParameterSetName = "Command")]
[OutputType(typeof(GitBinding))]
public sealed class GetGitArgumentTokenCommand : GitCmdlet
{
    /// <summary>Git command name, without the executable or its global options.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Command")]
    [Alias("CommandName")]
    public string Command { get; set; } = "";

    /// <summary>The exact argv following the command; empty strings are preserved.</summary>
    [Parameter(ParameterSetName = "Command")]
    [AllowEmptyCollection, AllowEmptyString, AllowNull]
    public string?[]? ArgumentList { get; set; }

    /// <summary>Existing request whose Name and Arguments select the command and its argv.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Request")]
    public Hashtable Request { get; set; } = new();

    /// <summary>Observed or supplied version, retained in the result as evidence only.</summary>
    [Parameter]
    [AllowNull, AllowEmptyString]
    public string? Version { get; set; }

    /// <summary>Explicit curated grammar, for deterministic tests.</summary>
    [Parameter]
    public Hashtable? Schema { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        string command = Command;
        string?[] arguments = ArgumentList ?? [];
        if (ParameterSetName == "Request")
        {
            command = Text(Request["Name"]);
            object? list = Request["Arguments"] is PSObject wrapped ? wrapped.BaseObject : Request["Arguments"];
            IEnumerable<object?> items = list switch { null => [], string single => [single], IEnumerable many => many.Cast<object?>(), _ => [list] };
            arguments = items.Select(Text).ToArray();
        }
        try { WriteObject(GitArguments.Bind(command, arguments, Version, Schema ?? GitArgumentSchemaStore.Load())); }
        catch (Exception error) when (error is InvalidDataException or System.Text.Json.JsonException or IOException) { Fail(error.Message); }
    }
}

/// <summary>Removes only bound option units from a binding, preserving operands and literal separators.</summary>
[Cmdlet(VerbsCommon.Get, "QuietGitArguments")]
[OutputType(typeof(string[]))]
public sealed class GetQuietGitArgumentsCommand : GitCmdlet
{
    /// <summary>Git-owned argument binding.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public GitBinding Binding { get; set; } = null!;

    /// <summary>Exact option names to normalize away.</summary>
    [Parameter(Position = 1)]
    [AllowNull, AllowEmptyCollection]
    public string[]? Remove { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing() => WriteObject(GitArgumentFilter.Without(Binding, Remove ?? []), false);
}

/// <summary>Decodes a business field losslessly; invalid UTF-8 stays an explicit byte representation.</summary>
[Cmdlet(VerbsData.ConvertFrom, "QuietGitBytes")]
[OutputType(typeof(object))]
public sealed class ConvertFromQuietGitBytesCommand : GitCmdlet
{
    /// <summary>Exact bytes of one Git field or record.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [AllowEmptyCollection]
    public byte[] Bytes { get; set; } = [];

    /// <inheritdoc />
    protected override void EndProcessing() => WriteObject(GitRecords.Decode(Bytes));
}

/// <summary>Normalizes a stable Git version, including Windows package suffixes.</summary>
[Cmdlet(VerbsCommon.Get, "GitNumericVersion")]
[OutputType(typeof(Version))]
public sealed class GetGitNumericVersionCommand : GitCmdlet
{
    /// <summary>Observed version string; unsupported formats produce no value.</summary>
    [Parameter(Position = 0)]
    [AllowNull, AllowEmptyString]
    public string? Version { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        if (GitVersions.Numeric(Version) is { } numeric) WriteObject(numeric);
    }
}

/// <summary>Projects streamed query records into a typed business result where implemented.</summary>
[Cmdlet(VerbsData.ConvertFrom, "QuietGitQuery")]
[OutputType(typeof(IDictionary))]
public sealed class ConvertFromQuietGitQueryCommand : GitCmdlet
{
    /// <summary>Git query name.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public string Name { get; set; } = "";

    /// <summary>Explicit business records collected by the query handler.</summary>
    [Parameter(Position = 1)]
    [AllowNull, AllowEmptyCollection]
    public string[]? Lines { get; set; }

    /// <summary>Native exit condition.</summary>
    [Parameter(Position = 2)]
    public int ExitCode { get; set; }

    /// <summary>Observed Git version.</summary>
    [Parameter(Position = 3)]
    [AllowNull, AllowEmptyString]
    public string? Version { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { WriteObject(GitQueryProjection.Project(Name, Lines ?? [], ExitCode, Version)); }
        catch (InvalidDataException error) { Fail(error.Message); }
    }
}
