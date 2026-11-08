using System.Collections;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Runspaces;
using System.Text;
using FrenchExDev2.QuietCli;
using FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Property, fuzz and contract cases for script generation (literal encoder and Export-QuietCallScript).</summary>
internal static class ScriptCmdletCases
{
    /// <summary>Fixed seed retained so any failing generated value can be replayed deterministically.</summary>
    private const int Seed = 73619;

    /// <summary>Runs every script generation case.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    /// <param name="runspace">Runspace that exposes the compiled cmdlets under test.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, Runspace runspace)
    {
        await run("script literals round-trip nested data, Unicode and hostile strings (seeded property)", () =>
        {
            var random = new Random(Seed);
            var corpus = new List<string> { "", "'", "\r\n", "é漢😀", "$([IO.File]::WriteAllText(\"bad\",\"bad\"))", "'; throw 'injected'; #", "`\"$;{}[]" };
            // Typographic quotes U+2018..U+201B delimit PowerShell strings exactly like the ASCII apostrophe; they must never end a literal.
            string[] typographic = Enumerable.Range(0x2018, 4).Select(code => ((char)code).ToString()).ToArray();
            corpus.AddRange(typographic);
            corpus.AddRange(typographic.Select(quote => quote + "; throw 'injected'; #" + quote + quote));
            corpus.Add(string.Concat(typographic));
            for (int index = 0; index < 128; index++)
            {
                string text = corpus[index % corpus.Count] + (char)random.Next(1, 0xd7ff) + random.Next();
                Require(Equals(Literal(runspace, ScriptLiteralEncoder.Encode(text, new())), text), "ScriptScalarPropertyFailed: seed " + Seed);
                var value = new OrderedDictionary { ["Text"] = text, ["Nested"] = new object?[] { new Hashtable { ["Flag"] = true, ["Nil"] = null }, (long)index }, ["Bytes"] = new byte[] { 0, 128, 255 } };
                var restored = (IDictionary)Literal(runspace, ScriptLiteralEncoder.Encode(value, new()))!;
                var nested = (object?[])U(restored["Nested"])!;
                var flags = (IDictionary)U(nested[0])!;
                Require(Equals(restored["Text"], text) && Equals(U(nested[1]), (long)index) && U(restored["Bytes"]) is byte[] { Length: 3 } bytes && bytes[2] == 255
                    && Equals(flags["Flag"], true) && flags["Nil"] is null, "ScriptLiteralPropertyFailed: seed " + Seed);
            }
            return Task.CompletedTask;
        });

        await run("script literals reject cycles, depth, unsupported values and budget overflow", () =>
        {
            var cycle = new Hashtable(); cycle["Self"] = cycle;
            object deep = new Hashtable();
            for (int i = 0; i < 35; i++) deep = new Hashtable { ["Next"] = deep };
            ExpectRejected(cycle, "QuietScriptCyclicValue");
            ExpectRejected(deep, "QuietScriptLiteralLimit");
            ExpectRejected(new Version(1, 2), "QuietScriptUnsupportedValue");
            ExpectRejected(new object(), "QuietScriptUnsupportedValue");
            ExpectRejected(new Hashtable { [1] = new List<int>() }, "QuietScriptUnsupportedValue");
            ExpectRejected(double.NaN, "QuietScriptNonFiniteNumber");
            ExpectRejected(float.PositiveInfinity, "QuietScriptNonFiniteNumber");
            ExpectRejected(new int[2, 2], "QuietScriptMultidimensionalArray");
            ExpectRejected(new int[][] { [1] }, "QuietScriptUnsupportedArrayType");
            ExpectRejected(new Hashtable { ["Text"] = new string('x', ScriptLiteralEncoder.MaximumCharacters + 1) }, "QuietScriptLiteralLimit");
            ExpectRejected(new object?[ScriptLiteralEncoder.MaximumNodes + 1], "QuietScriptLiteralLimit");
            // Boundaries accepted exactly at the limits.
            _ = ScriptLiteralEncoder.Encode(new string('x', ScriptLiteralEncoder.MaximumCharacters), new());
            _ = ScriptLiteralEncoder.Encode(new object?[ScriptLiteralEncoder.MaximumNodes - 1], new());
            return Task.CompletedTask;
        });

        await run("script literals keep primitive and array types through evaluation", () =>
        {
            foreach (object value in new object[] { (byte)255, (sbyte)-128, (short)-32768, (ushort)65535, int.MinValue, uint.MaxValue, long.MinValue, ulong.MaxValue, 0.1f, 1e-100, 12.34m, 'é', false, Array.Empty<string>(), new[] { 1 }, new[] { "a", "b'" } })
            {
                object? restored = Literal(runspace, ScriptLiteralEncoder.Encode(value, new()));
                Require(restored is not null && restored.GetType() == value.GetType(), "Type changed for " + value.GetType().Name);
                Require(value is Array expected ? ((Array)restored!).Length == expected.Length && expected.Cast<object>().SequenceEqual(((Array)restored).Cast<object>()) : Equals(restored, value), "Value changed for " + value.GetType().Name);
            }
            return Task.CompletedTask;
        });

        await run("factories give each call fresh values and reject missing, multiple and invalid returns", () =>
        {
            Runspace? previous = Runspace.DefaultRunspace;
            Runspace.DefaultRunspace = runspace;
            try
            {
                var request = new Hashtable
                {
                    ["DataFactory"] = ScriptBlock.Create("@{ Count = 0 }"),
                    ["StateFactory"] = ScriptBlock.Create("@{ Seen = [Collections.Generic.List[string]]::new() }"),
                };
                for (int round = 0; round < 3; round++)
                {
                    Hashtable copy = InvokeQuietCallCommand.ApplyFactories(request);
                    var data = (Hashtable)U(copy["Data"])!;
                    var seen = (System.Collections.Generic.List<string>)U(((Hashtable)U(copy["State"])!)["Seen"])!;
                    Require(Equals(U(data["Count"]), 0) && seen.Count == 0 && request.ContainsKey("DataFactory") && request.ContainsKey("StateFactory") && !copy.ContainsKey("DataFactory"), "Factory state leaked between calls");
                    data["Count"] = 99; seen.Add("old");
                }
                Require(U(InvokeQuietCallCommand.ApplyFactories(new Hashtable { ["DataFactory"] = ScriptBlock.Create(",@(1, 2)") })["Data"]) is Array { Length: 2 }, "A factory array was enumerated");
                Hashtable nil = InvokeQuietCallCommand.ApplyFactories(new Hashtable { ["DataFactory"] = ScriptBlock.Create("$null") });
                Require(nil.ContainsKey("Data") && nil["Data"] is null, "A null factory value was rejected");
                foreach ((string name, string body, string code) in new[] { ("DataFactory", "", "QuietFactoryMustReturnOneValue"), ("DataFactory", "1; 2", "QuietFactoryMustReturnOneValue"), ("StateFactory", "'text'", "QuietStateFactoryMustReturnHashtable") })
                {
                    try { _ = InvokeQuietCallCommand.ApplyFactories(new Hashtable { [name] = ScriptBlock.Create(body) }); }
                    catch (InvalidOperationException error) when (error.Message.StartsWith(code, StringComparison.Ordinal)) { continue; }
                    throw new InvalidOperationException("Factory returning '" + body + "' was accepted");
                }
            }
            finally { Runspace.DefaultRunspace = previous; }
            return Task.CompletedTask;
        });

        await run("Export-QuietCallScript writes an exclusive, parseable, LF definition and never replaces files", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "quiet-script-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            try
            {
                string target = Path.Combine(directory, "definition.ps1");
                var file = (FileInfo)Call(runspace, "param($r) Export-QuietCallScript $r", Request(target))!;
                byte[] bytes = File.ReadAllBytes(target);
                string source = new UTF8Encoding(false, true).GetString(bytes);
                Require(file.FullName == target && !(bytes.Length > 2 && bytes[0] == 0xef) && !source.Contains('\r') && source.EndsWith('\n'), "Definition bytes or result changed");
                Parser.ParseInput(source, out _, out ParseError[] errors);
                Require(errors.Length == 0 && source.Contains("-Complete") && source.Contains("'‘''‘'") == false, "Definition is not valid source");
                byte[] hash = bytes;
                ExpectFailure(runspace, "QuietScriptAlreadyExists", Request(target));
                Require(File.ReadAllBytes(target).SequenceEqual(hash), "Existing definition was replaced");
                ExpectFailure(runspace, "QuietScriptExtensionRequired", Request(Path.Combine(directory, "bad.txt")));
                ExpectFailure(runspace, "QuietScriptParentMissing", Request(Path.Combine(directory, "missing", "child.ps1")));
                var withoutCallback = Request(Path.Combine(directory, "none.ps1")); withoutCallback.Remove("Complete");
                ExpectFailure(runspace, "QuietScriptCallbackRequired", withoutCallback);
                foreach (string key in new[] { "Recall", "RecallId", "SaveRecall", "Zip", "Compress", "AllowPartial", "CancellationToken", "recallmaxbytes" })
                {
                    var request = Request(Path.Combine(directory, "unsupported.ps1")); request[key] = true;
                    ExpectFailure(runspace, "QuietScriptUnsupportedOption", request);
                }
                var notBlock = Request(Path.Combine(directory, "callback.ps1")); notBlock["Output"] = "not a callback";
                ExpectFailure(runspace, "QuietScriptCallbackMustBeScriptBlock", notBlock);
                Require(Directory.GetFiles(directory).Select(path => Path.GetFileName(path)).SequenceEqual(new[] { "definition.ps1" }), "A rejected export left a file behind");
            }
            finally { Directory.Delete(directory, true); }
            return Task.CompletedTask;
        });

        await run("Export-QuietCallScript stores hostile arguments as inert literals", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "quiet-script-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            try
            {
                string[] hostile = ["'; throw 'x'; #", "‘; throw 'x'; #’", "a\r\nb", "$(throw 'x')", "‛‚"];
                var request = Request(Path.Combine(directory, "hostile.ps1"));
                request["ArgumentList"] = hostile;
                request["FilePath"] = hostile[1];
                _ = Call(runspace, "param($r) Export-QuietCallScript $r", request);
                string source = File.ReadAllText(Path.Combine(directory, "hostile.ps1"));
                // Evaluate only the generated parameter block: its defaults must restore the exact original values.
                ScriptBlockAst ast = Parser.ParseInput(source, out _, out _);
                string parameters = ast.ParamBlock!.Extent.Text + "; ,@($FilePath, $ArgumentList)";
                var restored = (object?[])Call(runspace, parameters)!;
                Require(Equals(U(restored[0]), hostile[1]) && ((IEnumerable)U(restored[1])!).Cast<object?>().Select(U).Cast<string>().SequenceEqual(hostile), "Hostile arguments were not restored exactly");
            }
            finally { Directory.Delete(directory, true); }
            return Task.CompletedTask;
        });

        await run("Export-QuietCallScript rejects a definition path redirected through a linked ancestor", () =>
        {
            string link = Path.Combine(Path.GetTempPath(), "quiet-script-link-" + Guid.NewGuid().ToString("N"));
            string real = Path.Combine(Path.GetTempPath(), "quiet-script-real-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(real);
            try
            {
                if (!TryLink(link, real)) return Task.CompletedTask; // platform or privileges forbid linking; nothing to verify here
                ExpectFailure(runspace, "QuietScriptLinkRejected", Request(Path.Combine(link, "definition.ps1")));
                Require(!Directory.EnumerateFileSystemEntries(real).Any(), "A rejected export wrote through the linked ancestor");
            }
            finally
            {
                try { Directory.Delete(link, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                try { Directory.Delete(real, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
            return Task.CompletedTask;
        });

        await run("PathGuard rejects a path or any ancestor that is a reparse point, and nothing else", () =>
        {
            string root = Path.Combine(Path.GetTempPath(), "quiet-pathguard-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                string plainDirectory = Path.Combine(root, "plain");
                Directory.CreateDirectory(plainDirectory);
                string plainFile = Path.Combine(plainDirectory, "file.txt");
                File.WriteAllText(plainFile, "x");
                string missing = Path.Combine(plainDirectory, "missing.txt");
                Require(!PathGuard.IsReparsePoint(plainDirectory) && !PathGuard.IsReparsePoint(plainFile) && !PathGuard.IsReparsePoint(missing)
                    && !PathGuard.HasLinkedAncestor(plainFile) && !PathGuard.HasLinkedAncestor(missing), "An ordinary path was flagged as linked");

                string linked = Path.Combine(root, "linked-" + Guid.NewGuid().ToString("N"));
                string target = Path.Combine(root, "target-" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(target);
                if (TryLink(linked, target))
                {
                    Require(PathGuard.IsReparsePoint(linked) && PathGuard.HasLinkedAncestor(linked), "A linked directory itself was not detected");
                    string throughLink = Path.Combine(linked, "deep", "child.txt");
                    Require(PathGuard.HasLinkedAncestor(throughLink), "A descendant of a linked ancestor was not detected");
                }
            }
            finally { Directory.Delete(root, true); }
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

    /// <summary>Minimal valid export request.</summary>
    private static Hashtable Request(string script) => new()
    {
        ["Script"] = script, ["FilePath"] = "absent", ["ArgumentList"] = Array.Empty<string>(), ["AsObject"] = true,
        ["Complete"] = ScriptBlock.Create("param($r) $r.Data"),
    };

    /// <summary>Evaluates one literal; the leading comma keeps arrays from being enumerated into the pipeline.</summary>
    private static object? Literal(Runspace runspace, string literal) => Call(runspace, ",(" + literal + ")");

    /// <summary>Runs a script and returns its single output unwrapped.</summary>
    private static object? Call(Runspace runspace, string script, params object[] arguments) =>
        U(DeliveryCmdletCases.Script(runspace, script, arguments).Single());

    /// <summary>Removes the PowerShell wrapper from a value read out of a collection.</summary>
    private static object? U(object? value) => QuietRuntime.Unwrap(value);

    /// <summary>Requires the encoder to refuse a value with a stable code.</summary>
    private static void ExpectRejected(object? value, string code)
    {
        try { _ = ScriptLiteralEncoder.Encode(value, new()); }
        catch (InvalidOperationException error) when (error.Message.StartsWith(code, StringComparison.Ordinal)) { return; }
        throw new InvalidOperationException("Encoder did not reject " + (value?.GetType().Name ?? "null") + " with " + code);
    }

    /// <summary>Requires the cmdlet to fail with a stable code.</summary>
    private static void ExpectFailure(Runspace runspace, string code, Hashtable request) =>
        DeliveryCmdletCases.Expect(runspace, code, "param($r) Export-QuietCallScript $r", request);

    /// <summary>Throws when an independently known invariant fails.</summary>
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
