using System.Text;
using FrenchExDev2.QuietCli.Git;

/// <summary>Invariants of option removal from a bound native vector.</summary>
internal static class ArgumentFilterCases
{
    /// <summary>Registers deterministic, generated and malformed campaigns.</summary>
    /// <param name="test">Existing compiled runner.</param>
    /// <param name="schemaPath">Path of the module grammar under test.</param>
    internal static void Run(Action<string, Action> test, string? schemaPath)
    {
        test("argument filter keeps operands that look like flags, literal separators and case-distinct options", () =>
        {
            var schema = Schema(schemaPath);
            var binding = GitArguments.Bind("status", ["-s", "--", "-z", "-S"], null, schema);
            Require(binding.Complete, "Fixture binding incomplete");
            var kept = GitArgumentFilter.Without(binding, ["-s"]);
            Require(kept.SequenceEqual(["--", "-z", "-S"]), $"Unexpected vector: {string.Join(' ', kept)}");
            Require(GitArgumentFilter.Without(binding, ["-S"]).SequenceEqual(["-s", "--", "-z", "-S"]), "Removal ignored case or touched an operand");
            var nested = GitArguments.Bind("remote", ["add", "origin", "url"], null, schema);
            Require(nested.Tokens.Any(unit => unit.Kind == "Subcommand" && unit.Name == "add"), "Fixture has no named subcommand unit");
            Require(GitArgumentFilter.Without(nested, ["add"]).SequenceEqual(["add", "origin", "url"]), "A named non-option unit was removed");
        });
        test("argument filter properties: identity on empty set, subsequence, operands never removed (seed 77201, 2000 vectors)", () =>
        {
            var schema = Schema(schemaPath);
            var commands = ((System.Collections.IDictionary)schema["Commands"]!).Keys.Cast<string>().OrderBy(name => name, StringComparer.Ordinal).ToArray();
            var random = new Random(77201); string[] alphabet = ["-a", "-n", "-z", "--all", "--", "-", "--format=x", "path", "", "é", "-C", "--null", "-v"]; string[] removable = ["-z", "--null", "-v", "-a", "-n"];
            for (int i = 0; i < 2000; i++)
            {
                string command = commands[random.Next(commands.Length)];
                string?[] argv = Enumerable.Range(0, random.Next(0, 7)).Select(_ => alphabet[random.Next(alphabet.Length)]).ToArray();
                var binding = GitArguments.Bind(command, argv, "2.56.0", schema);
                var all = binding.Tokens.SelectMany(unit => unit.EmitArguments).Select(item => item ?? "").ToArray();
                Require(GitArgumentFilter.Without(binding, []).SequenceEqual(all), $"Empty removal changed the vector ({command}, index {i})");
                string[] remove = removable.Where(_ => random.Next(2) == 0).ToArray();
                var result = GitArgumentFilter.Without(binding, remove);
                Require(IsSubsequence(result, all), $"Result is not a subsequence ({command}, index {i})");
                var operandTokens = binding.Tokens.Where(unit => unit.Kind != "Option").SelectMany(unit => unit.EmitArguments).Select(item => item ?? "").ToArray();
                Require(IsSubsequence(operandTokens, result), $"A non-option unit was removed ({command}, index {i})");
                var removedAll = GitArgumentFilter.Without(binding, binding.Tokens.Where(unit => unit.Kind == "Option" && unit.Name is not null).Select(unit => unit.Name!).ToArray());
                Require(removedAll.SequenceEqual(operandTokens), $"Removing every option name left something other than non-option units ({command}, index {i})");
            }
        });
    }

    /// <summary>Tells whether <paramref name="small"/> appears in order inside <paramref name="large"/>.</summary>
    /// <param name="small">Candidate subsequence.</param>
    /// <param name="large">Reference sequence.</param>
    private static bool IsSubsequence(string[] small, string[] large)
    {
        int at = 0;
        foreach (string item in large) if (at < small.Length && small[at] == item) at++;
        return at == small.Length;
    }

    /// <summary>Reads the module grammar through the production store.</summary>
    /// <param name="schemaPath">Path supplied by the runner.</param>
    private static System.Collections.Hashtable Schema(string? schemaPath) =>
        GitArgumentSchemaStore.Parse(File.ReadAllText(schemaPath ?? throw new Exception("Module schema path required"), Encoding.UTF8));

    /// <summary>Asserts an independently stated observable property.</summary>
    /// <param name="condition">Expected property.</param>
    /// <param name="message">Bounded diagnostic.</param>
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
