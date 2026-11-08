using System.Collections;
using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Contract, property and fuzz cases for the compiled invocation lifecycle, driven through a real PowerShell runspace.</summary>
internal static class InvocationCmdletCases
{
    /// <summary>Fixed seed retained so any failing generated value can be replayed deterministically.</summary>
    private const int Seed = 20261112;

    /// <summary>Runs every invocation case; telemetry must already be disabled for the shared configuration snapshot.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="runspace">Runspace exposing the invocation and handler cmdlets.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, Runspace runspace)
    {
        shared = runspace;
        string binary = Path.GetFileNameWithoutExtension(Environment.ProcessPath)!;
        string path = Environment.ProcessPath!;

        await run("invocation of a registered handler returns an immutable finalized local result", () =>
        {
            Register(runspace, "probe-ok", binary, "42");
            try
            {
                var result = Call(runspace, path, "@{}");
                Require(Text(result, "Outcome") == "Success" && Member(result, "Data") is 42, "Handler outcome or data lost");
                Require(Member(result, "ParentId") is null && Text(result, "RootId") == Text(result, "InvocationId"), "Root identity wrong");
                Require(Text(Member(result, "Execution")!, "State") == "Finalized", "Execution snapshot not finalized: " + Dump(result));
                Require((bool)Member(Member(result, "Completeness")!, "Source")! && (bool)Member(Member(result, "Completeness")!, "Analysis")!, "Completeness lost");
                Require(PSObject.AsPSObject(result).TypeNames[0] == "QuietCli2.Result", "Result type name lost");
                foreach (string name in new[] { "Execution", "Completeness" })
                    ExpectFailure(() => DeliveryCmdletCases.Script(runspace, "param($r) $r." + name + " = 1", result), "Final property " + name + " is writable");
                Require(QuietCallState.Depth == 0, "Call stack leaked");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-ok"); }
            return Task.CompletedTask;
        });

        await run("invocation without a handler is unsupported and a missing executable fails with stable diagnostics", () =>
        {
            var unsupported = Call(runspace, path, "@{}");
            Require(Text(unsupported, "Outcome") == "Unsupported" && Text(((IEnumerable)Member(unsupported, "Error")!).Cast<object>().Single(), "Code") == "HandlerNotFound", "Unsupported call mis-reported: " + Dump(unsupported));
            var missing = Call(runspace, Path.Combine(Path.GetTempPath(), "quiet-missing-" + Guid.NewGuid().ToString("N")), "@{}");
            Require(Text(missing, "Outcome") == "Failed" && Text(((IEnumerable)Member(missing, "Error")!).Cast<object>().First(), "Code") == "InvocationFailed", "Missing executable mis-reported");
            Require(!(bool)Member(Member(missing, "Completeness")!, "Analysis")!, "Failed call claimed a complete analysis");
            Require(QuietCallState.Depth == 0, "Call stack leaked after failures");
            return Task.CompletedTask;
        });

        await run("nested invocations inherit identity, context and aggregate children", () =>
        {
            Register(runspace, "probe-inner", binary, "'inner'");
            Register(runspace, "probe-nested", binary, "Invoke-QuietCall @{FilePath=$rt.Request['FilePath'];Environment=@{};AsObject=$true;HandlerId='probe-inner'}");
            try
            {
                var outer = Call(runspace, path, "@{Context='ctx';HandlerId='probe-nested'}");
                var inner = Member(outer, "Data");
                Require(Text(outer, "Outcome") == "Success" && inner is not null, "Outer outcome wrong: " + Dump(outer));
                Require(Text(inner, "ParentId") == Text(outer, "InvocationId") && Text(inner, "RootId") == Text(outer, "RootId") && Text(inner, "Context") == "ctx", $"Nested identity not inherited: parent={Text(inner, "ParentId")}/{Text(outer, "InvocationId")} root={Text(inner, "RootId")}/{Text(outer, "RootId")} ctx={Text(inner, "Context")}");
                Require(Text(inner, "Outcome") == "Success" && Member(inner, "Data") as string == "inner", "Child outcome lost: " + Dump(inner!));
                Require(Convert.ToInt32(Member(Member(outer, "Execution"), "Children")) == 1, "Child not aggregated");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-nested; Unregister-QuietHandler probe-inner"); }
            return Task.CompletedTask;
        });

        await run("data and state factories run once per call and must return exactly one value", () =>
        {
            Register(runspace, "probe-factory", binary, "$rt.Data");
            try
            {
                var random = new Random(Seed);
                var seen = new HashSet<object>(ReferenceEqualityComparer.Instance);
                for (int round = 0; round < 25; round++)
                {
                    int size = random.Next(0, 4);
                    var result = Call(runspace, path, $"@{{DataFactory={{,(@(1..{size}) | % {{ $_ }})}}}}");
                    var data = Member(result, "Data");
                    Require(data is not null && seen.Add(data), "Factory value was shared between calls");
                }
                foreach (string bad in new[] { "@{DataFactory={}}", "@{DataFactory={1;2}}", "@{StateFactory={1}}", "@{StateFactory={@{};@{}}}" })
                    ExpectFailure(() => Call(runspace, path, bad), "Invalid factory accepted: " + bad);
                Require(QuietCallState.Depth == 0, "Call stack leaked after factory failures");
            }
            finally { DeliveryCmdletCases.Script(runspace, "Unregister-QuietHandler probe-factory"); }
            return Task.CompletedTask;
        });

        await run("invocation rejects an input path redirected through a linked ancestor", () =>
        {
            string link = Path.Combine(Path.GetTempPath(), "quiet-input-link-" + Guid.NewGuid().ToString("N"));
            string real = Path.Combine(Path.GetTempPath(), "quiet-input-real-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(real);
            File.WriteAllText(Path.Combine(real, "input.txt"), "x");
            try
            {
                if (!TryLink(link, real)) return Task.CompletedTask; // platform or privileges forbid linking; nothing to verify here
                string throughLink = Path.Combine(link, "input.txt");
                // The guard runs before the native process starts; -Output/-Complete are never invoked.
                // Supply the facade's complete native request, including working directory and terminal defaults.
                var result = DeliveryCmdletCases.Script(runspace,
                    "param($path,$inputPath) $o = Read-QuietArguments -Arguments @('-AsObject','-InputPath',$inputPath,'-Output',{},'-Complete',{},$path); Invoke-QuietCall $o",
                    path, throughLink).Single();
                string message = Text(((IEnumerable)Member(result, "Error")!).Cast<object>().First(), "Message");
                Require(Text(result, "Outcome") == "Failed" && message.Contains("QuietInputPathLinkRejected"), "Linked InputPath was not rejected: " + Dump(result));
            }
            finally
            {
                try { Directory.Delete(link, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                try { Directory.Delete(real, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
            return Task.CompletedTask;
        });
    }

    /// <summary>Creates a directory link, returning false when the platform or privileges forbid it.</summary>
    /// <param name="link">Path of the link to create.</param>
    /// <param name="target">Existing directory the link points to.</param>
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

    /// <summary>Registers an inert handler whose Execute script block receives the runtime as $rt.</summary>
    private static void Register(Runspace runspace, string id, string binary, string execute) =>
        DeliveryCmdletCases.Script(runspace, $"Register-QuietHandler '{id}' @{{Binary='{binary}';VersionRange='*';TestVersion={{param($v) $true}};Probe={{'1.0'}};Execute={{param($rt) {execute}}}}}");

    /// <summary>Invokes the compiled call with an options hashtable merged over the required defaults.</summary>
    private static object Call(Runspace runspace, string filePath, string options) =>
        DeliveryCmdletCases.Script(runspace, "param($path) $o = " + options + "; $o.FilePath = $path; if(!$o.ContainsKey('Environment')){$o.Environment=@{}}; if(!$o.ContainsKey('AsObject')){$o.AsObject=$true}; Invoke-QuietCall $o", filePath).Single();

    private static Runspace? shared;

    private static string Dump(object result)
    {
        var errors = Member(result, "Error") is IEnumerable list ? string.Join(";", list.Cast<object>().Select(e => Text(e, "Code") + ":" + Text(e, "Message"))) : "";
        var execution = Member(result, "Execution");
        return $"Outcome={Text(result, "Outcome")} Data={Text(result, "Data")} Errors=[{errors}] Execution={(execution is null ? "null" : Text(execution, "State"))}";
    }

    /// <summary>Unwraps scalars but keeps property-bearing objects (results, snapshots) intact.</summary>
    private static object? Plain(object? value) => value is PSObject { BaseObject: PSCustomObject } ? value : QuietRuntime.Unwrap(value);

    private static object? Member(object? container, string name)
    {
        if (container is null) return null;
        object baseObject = container is PSObject wrapped ? wrapped.BaseObject : container;
        if (baseObject is IDictionary dictionary) return Plain(dictionary.Contains(name) ? dictionary[name] : null);
        return Plain(PSObject.AsPSObject(container).Properties[name]?.Value ?? PropertyReader.Get(container, name));
    }

    private static string Text(object? container, string name) => Convert.ToString(Member(container, name), System.Globalization.CultureInfo.InvariantCulture) ?? "";

    private static void ExpectFailure(Action action, string message)
    {
        try { action(); }
        catch (Exception) { return; }
        throw new InvalidOperationException(message);
    }

    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
