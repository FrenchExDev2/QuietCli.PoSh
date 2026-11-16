using System.Text;

namespace FrenchExDev2.QuietCli.Scaffolding;

/// <summary>Generates an inert business module and its independent failing test companion.</summary>
internal static class ModuleScaffold
{
    /// <summary>UTF-8 without BOM, LF line endings, as every generated text file.</summary>
    private static readonly UTF8Encoding Utf8 = new(false, true);

    /// <summary>Companion module name: the PoSh suffix becomes Tests.PoSh, anything else gets a Tests suffix.</summary>
    /// <param name="name">Business module name.</param>
    internal static string TestModuleName(string name) =>
        name.EndsWith(".PoSh", StringComparison.OrdinalIgnoreCase) ? name[..^".PoSh".Length] + ".Tests.PoSh" : name + ".Tests";

    /// <summary>Writes both modules; existing destinations are never overwritten.</summary>
    /// <param name="name">Full module name without the Tests component.</param>
    /// <param name="binary">Executable name handled by the module.</param>
    /// <param name="outputPath">Absolute parent directory.</param>
    /// <returns>The business and test module directories.</returns>
    internal static (string Module, string Tests) Generate(string name, string binary, string outputPath)
    {
        string testName = TestModuleName(name);
        string target = Path.Combine(outputPath, name), tests = Path.Combine(outputPath, testName);
        if (Path.Exists(target) || Path.Exists(tests)) throw new InvalidOperationException("ModuleDestinationExists");
        foreach (string directory in new[] { target, tests, Path.Combine(target, "src") }) Directory.CreateDirectory(directory);
        Write(Path.Combine(target, name + ".psm1"), ModuleSource.Replace("__MODULE__", name));
        Write(Path.Combine(target, "src", "Handler.ps1"), HandlerSource.Replace("__MODULE__", name).Replace("__BINARY__", binary));
        Write(Path.Combine(target, name + ".psd1"), Manifest(name, [(QuietSession.ModuleName, "0.2.0")], "@()",
            $"@{{QuietCli=@{{Binary='{binary}';TestsModule='{testName}';Qualification='NotImplemented'}}}}"));
        Write(Path.Combine(tests, testName + ".psm1"), TestSource);
        Write(Path.Combine(tests, testName + ".psd1"), Manifest(testName, [(name, "0.1.0"), ("FrenchExDev2.QuietCli.Core.Tests.PoSh", "0.1.0")], "'Invoke-ModuleTests'", null));
        Write(Path.Combine(target, "README.md"), $"# {name}\n\nHandler for {binary}. Qualification: not implemented. Import registers an inert catalogue. Edit src/Handler.ps1: document the official sources, implement Probe and TestVersion, declare supported forms in Match, then implement Execute with explicit quiet callbacks. Keep business data local; never gather raw output for accounting. Add schemas, examples and qualification limits before general use.");
        Write(Path.Combine(tests, "README.md"), $"# {testName}\n\nIndependent tests for {name}. An empty generated suite fails explicitly. Keep fixtures and assertions in this repository. Use Invoke-QuietConformance for shared envelope invariants and independently authored assertions for business effects. The business module must never depend on this companion.");
        return (target, tests);
    }

    /// <summary>Writes one text file.</summary>
    private static void Write(string path, string text) => File.WriteAllTextAsync(path, text, Utf8).GetAwaiter().GetResult();

    /// <summary>Renders a module manifest restricted to the keys the companion tooling reads.</summary>
    /// <param name="name">Module name; the root module is name.psm1.</param>
    /// <param name="required">Required modules with their minimum version.</param>
    /// <param name="functions">PowerShell literal for FunctionsToExport.</param>
    /// <param name="privateData">PowerShell hashtable literal, or null.</param>
    private static string Manifest(string name, (string Module, string Version)[] required, string functions, string? privateData)
    {
        string modules = string.Join(",", required.Select(item => $"@{{ModuleName='{item.Module}';ModuleVersion='{item.Version}'}}"));
        var text = new StringBuilder();
        text.Append("@{\n")
            .Append($"RootModule='{name}.psm1'\n")
            .Append("ModuleVersion='0.1.0'\n")
            .Append($"GUID='{Guid.NewGuid():D}'\n")
            .Append("PowerShellVersion='7.6'\n")
            .Append($"RequiredModules=@({modules})\n")
            .Append($"FunctionsToExport={functions}\n")
            .Append("CmdletsToExport=@()\n")
            .Append("VariablesToExport=@()\n")
            .Append("AliasesToExport=@()\n");
        if (privateData is not null) text.Append($"PrivateData={privateData}\n");
        return text.Append("}\n").ToString();
    }

    private const string ModuleSource = """
        #requires -Version 7.6
        . (Join-Path $PSScriptRoot 'src/Handler.ps1')
        $ExecutionContext.SessionState.Module.OnRemove={Unregister-QuietHandler -Id '__MODULE__'}
        Export-ModuleMember -Function @()
        """;

    private const string HandlerSource = """
        # Registering this catalogue never executes a binary. Configure the four callbacks before use.
        Register-QuietHandler -Id '__MODULE__' -Definition @{
            Binary='__BINARY__'
            ModuleVersion='0.1.0'
            VersionRange='Unconfigured'
            Qualification='NotImplemented'
            Documentation=@()
            SupportedForms=@()
            Probe={
                param($runtime)
                # Use quiet -AsObject -Role Probe with explicit Output/Complete callbacks.
                # Return exactly one observed version. Keep native version rules in this module.
                throw 'ConfigureDocumentedVersionProbe'
            }
            TestVersion={param($version) $false}
            Match={param($request,$version) $false}
            Execute={
                param($runtime)
                # Use quiet -AsObject with explicit Output/Complete callbacks for native work.
                # Preserve request arguments, environment, input and cancellation deliberately.
                # Retain only business data; return that data to the enclosing invocation.
                throw 'ImplementBusinessHandler'
            }
        }
        """;

    private const string TestSource = """
        function Invoke-ModuleTests {
            <#
            .SYNOPSIS
            Rejects an unimplemented module instead of certifying an empty test set.
            #>
            [CmdletBinding()]param()
            throw 'Write independent business assertions and enable the shared conformance suite.'
        }
        Export-ModuleMember -Function Invoke-ModuleTests
        """;
}
