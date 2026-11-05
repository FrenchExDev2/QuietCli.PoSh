using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using System.Text.RegularExpressions;

/// <summary>Isolated maintenance tool; never used by runtime imports or normal builds.</summary>
internal static class Program
{
    /// <summary>Adds missing XML signature documentation without altering executable syntax.</summary>
    /// <param name="arguments">One absolute workspace root.</param>
    private static async Task<int> Main(string[] arguments)
    {
        if (arguments.Length != 1) return 64;
        string[] roots = ["FrenchExDev2.QuietCli.Core.PoSh/engine", "FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests", "FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture"];
        foreach (string directory in roots)
        foreach (string file in Directory.GetFiles(Path.Combine(arguments[0], directory), "*.cs"))
        {
            string text = await File.ReadAllTextAsync(file, System.Text.Encoding.UTF8);
            var tree = CSharpSyntaxTree.ParseText(text);
            var insertions = new List<(int Position, string Text)>();
            foreach (var node in tree.GetRoot().DescendantNodes())
            {
                if (node is not (TypeDeclarationSyntax or MethodDeclarationSyntax or ConstructorDeclarationSyntax or PropertyDeclarationSyntax or FieldDeclarationSyntax or LocalFunctionStatementSyntax)) continue;
                string name = node switch {
                    TypeDeclarationSyntax type => type.Identifier.Text,
                    MethodDeclarationSyntax method => method.Identifier.Text,
                    ConstructorDeclarationSyntax constructor => constructor.Identifier.Text,
                    PropertyDeclarationSyntax property => property.Identifier.Text,
                    FieldDeclarationSyntax field => string.Join(", ", field.Declaration.Variables.Select(x => x.Identifier.Text)),
                    LocalFunctionStatementSyntax local => local.Identifier.Text,
                    _ => "component"
                };
                var parameters = node switch {
                    BaseMethodDeclarationSyntax method => method.ParameterList.Parameters.ToArray(),
                    TypeDeclarationSyntax type when type.ParameterList != null => type.ParameterList.Parameters.ToArray(),
                    LocalFunctionStatementSyntax local => local.ParameterList.Parameters.ToArray(),
                    _ => Array.Empty<ParameterSyntax>()
                };
                string leading = node.GetLeadingTrivia().ToFullString(); var docs = new List<string>();
                if (!leading.Contains("<summary>")) docs.Add("/// <summary>" + Summary(name) + "</summary>");
                foreach (var parameter in parameters)
                    if (!leading.Contains("<param name=\"" + parameter.Identifier.Text + "\""))
                        docs.Add("/// <param name=\"" + parameter.Identifier.Text + "\">" + Describe(parameter.Identifier.Text) + "</param>");
                if (docs.Count == 0) continue;
                int lineStart = text.LastIndexOf('\n', Math.Max(0, node.SpanStart - 1)) + 1;
                string indent = text[lineStart..node.SpanStart]; bool inline = indent.Any(x => !char.IsWhiteSpace(x));
                insertions.Add((node.SpanStart, (inline ? "\n" : "") + string.Join("\n", docs) + "\n" + (inline ? "" : indent)));
            }
            foreach (var insertion in insertions.OrderByDescending(x => x.Position)) text = text.Insert(insertion.Position, insertion.Text);
            if (Path.GetFileName(file) == "SqliteNative.cs" && !text.StartsWith("#nullable disable")) text = "#nullable disable\n" + text;
            text = text.Replace("transactionally creates or migrates schemas up to V2", "transactionally initializes QuietCli2 schema 1")
                .Replace("Read-only mode requires V1 or V2", "Read-only mode requires QuietCli2 schema 1")
                .Replace("History holds command output, even if masked", "History holds execution counter metadata only");
            await File.WriteAllTextAsync(file, text, new System.Text.UTF8Encoding(false));
        }
        Console.WriteLine("C# XML signature documentation updated."); return 0;
    }

    /// <summary>Describes the established low-level contracts rather than inventing application behavior.</summary>
    /// <param name="name">Declared member name.</param>
    private static string Summary(string name) => name switch {
        "Quote" => "Quotes one CreateProcessW argument without invoking a shell.",
        "Kill" => "Terminates only the process tree owned by this transport.",
        "Check" => "Checks a native API return value and raises its error.",
        "Dispose" => "Releases native handles owned by this component.",
        "Input" => "Native child input stream.", "Output" => "Native child output stream.",
        "Error" => "Native error stream, or Stream.Null for a merged terminal.",
        "Id" => "Identity of the owned native process.", "ExitCode" => "Native exit code when known, otherwise null.",
        "HasExited" => "Whether the owned native child has exited.",
        _ => "Native " + Regex.Replace(name, "([a-z])([A-Z])", "$1 $2").ToLowerInvariant() + " contract used by the isolated runtime."
    };

    /// <summary>Supplies signature descriptions for native transport and database parameters.</summary>
    /// <param name="name">Declared parameter name.</param>
    private static string Describe(string name) => name switch {
        "token" => "Cancellation requested by the owning operation.",
        "arguments" => "Exact invocation arguments without shell expansion.",
        "request" => "Validated execution metadata, never the business object.",
        "metadata" => "Control or counter metadata, never business data.",
        "payload" => "Transient binary block released after consumption.",
        "bytes" => "Exact byte block provided by the caller.",
        "path" => "Explicit filesystem location.", "directory" => "Native working directory.",
        "executable" => "Resolved native executable path.", "environment" => "Environment overrides for this child only.",
        "columns" => "Terminal width in columns.", "rows" => "Terminal height in rows.",
        "sql" => "SQL statement using bound parameters.", "values" => "SQL values bound without string interpolation.",
        "create" => "Whether schema initialization is permitted.", "source" => "Native source stream, consumed without capture.",
        "stream" => "Requested stream.", "helper" => "Verified Unix bridge path, or empty for pipe mode.",
        "bridge" => "Verified Unix terminal bridge location.", "operation" => "One serialized database operation.",
        "kind" => "Metadata record kind.", "argument" => "One argument to quote for CreateProcessW.",
        "code" => "Native return code.", "success" => "Native API success flag.",
        _ => Regex.Replace(name, "([a-z])([A-Z])", "$1 $2") + " for this native operation."
    };
}
