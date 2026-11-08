namespace FrenchExDev2.QuietCli.Git;

/// <summary>Result of binding Git global options and the command name; never executes a binary.</summary>
/// <param name="Error">Stable error code, or null when binding succeeded.</param>
/// <param name="Reason">Human-readable cause when <paramref name="Error"/> is set.</param>
/// <param name="Name">Git command name, or the <c>$root</c> pseudo-command when none was given.</param>
/// <param name="Global">Global options exactly as written, with their separate values.</param>
/// <param name="GlobalNames">Normalized global option names, without their values.</param>
/// <param name="Arguments">Arguments after the command name, forwarded verbatim.</param>
/// <param name="Original">The complete original argument vector.</param>
public sealed record GitInvocation(string? Error, string? Reason, string Name, string[] Global, string[] GlobalNames, string[] Arguments, string[] Original);

/// <summary>Binds Git global options and the command; Git syntax belongs exclusively to this module.</summary>
public static class GitInvocationBinder
{
    /// <summary>Pseudo-command used when Git is run without a command or with an informational option.</summary>
    public const string RootCommand = "$root";

    /// <summary>Global options that consume the next argument when written without <c>=</c>.</summary>
    private static readonly HashSet<string> TakesValue = new(StringComparer.Ordinal) { "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--super-prefix", "--attr-source", "--shallow-file" };

    /// <summary>Global options that never take a value.</summary>
    private static readonly HashSet<string> Flags = new(StringComparer.Ordinal) { "-p", "-P", "--paginate", "--no-pager", "--bare", "--no-replace-objects", "--no-lazy-fetch", "--no-optional-locks", "--no-advice", "--literal-pathspecs", "--no-literal-pathspecs", "--glob-pathspecs", "--noglob-pathspecs", "--icase-pathspecs" };

    /// <summary>Informational options that select the <c>$root</c> pseudo-command without consuming anything.</summary>
    private static readonly HashSet<string> InformationalPaths = new(StringComparer.Ordinal) { "--html-path", "--man-path", "--info-path", "--exec-path" };

    /// <summary>Binds the global options and the command name of one Git invocation.</summary>
    /// <param name="arguments">The exact native argument vector.</param>
    /// <returns>The binding, or an <c>ArgumentsUnsupported</c> result for an unknown or incomplete global option.</returns>
    public static GitInvocation Bind(IReadOnlyList<string> arguments)
    {
        var global = new List<string>();
        var globalNames = new List<string>();
        int position = 0;
        string? name = null;
        while (position < arguments.Count)
        {
            string value = arguments[position];
            if (value is "--version" or "-v") { name = "version"; position++; break; }
            if (value is "--help" or "-h") { name = "help"; position++; break; }
            if (InformationalPaths.Contains(value) || value.StartsWith("--list-cmds=", StringComparison.Ordinal)) { name = RootCommand; break; }
            if (value.StartsWith("--exec-path=", StringComparison.Ordinal)) { global.Add(value); globalNames.Add("--exec-path="); position++; continue; }
            if (!value.StartsWith('-')) { name = value; position++; break; }
            global.Add(value);
            int equals = value.IndexOf('=');
            string key = equals < 0 ? value : value[..equals];
            // -Cdir and -cname=value: the value is glued to the short option; a bare -C or -c is handled by the valued-option table.
            bool attachedValue = value.Length > 1 && value[1] is 'C' or 'c';
            globalNames.Add(equals >= 0 ? key + "=" : attachedValue ? value[..2] : key);
            if (TakesValue.Contains(key) && equals < 0)
            {
                position++;
                if (position >= arguments.Count) return Failure(arguments, $"Global option {key} requires a value.");
                global.Add(arguments[position]);
            }
            else if (!TakesValue.Contains(key) && !Flags.Contains(key) && !attachedValue) return Failure(arguments, $"Unknown Git global option: {value}");
            position++;
        }
        if (string.IsNullOrEmpty(name)) name = RootCommand;
        return new GitInvocation(null, null, name, [.. global], [.. globalNames], [.. arguments.Skip(position)], [.. arguments]);
    }

    /// <summary>Builds the unsupported-arguments result.</summary>
    /// <param name="arguments">The original vector.</param>
    /// <param name="reason">Why the vector cannot be bound.</param>
    private static GitInvocation Failure(IReadOnlyList<string> arguments, string reason) => new("ArgumentsUnsupported", reason, "", [], [], [], [.. arguments]);
}
