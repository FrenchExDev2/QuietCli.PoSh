using System.Collections;
using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Pure Git-owned option binding, not command availability or business-value validation.</summary>
public static class GitArguments
{
    /// <summary>Reads an unwrapped schema field.</summary>
    /// <param name="map">Curated map.</param>
    /// <param name="key">Field name.</param>
    private static object? Get(IDictionary? map, string key) => GitRecords.Unwrap(map?[key]);
    /// <summary>Reads an optional nested schema map.</summary>
    /// <param name="value">Schema value.</param>
    private static IDictionary? Map(object? value) => GitRecords.Unwrap(value) as IDictionary;
    /// <summary>Enumerates declared strings without interpreting command tokens.</summary>
    /// <param name="value">Schema sequence.</param>
    private static IEnumerable<string> Strings(object? value)
    {
        value = GitRecords.Unwrap(value);
        if (value is string text) { yield return text; yield break; }
        if (value is IEnumerable sequence)
            foreach (var item in sequence) yield return (string)GitRecords.Unwrap(item)!;
    }
    /// <summary>Case-insensitive schema labels match the original PowerShell predicate behavior.</summary>
    /// <param name="left">Schema label.</param>
    /// <param name="right">Expected label.</param>
    private static bool Equal(string? left, string? right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
    /// <summary>Tests one accepted spelling form.</summary>
    /// <param name="definition">Curated option.</param>
    /// <param name="form">Bare, Separate, Equals or Attached.</param>
    private static bool Form(Definition definition, string form) => definition.Forms.Contains(form, StringComparer.OrdinalIgnoreCase);

    /// <summary>Detached option arity and forms, owned by the Git grammar.</summary>
    /// <param name="ValueKind">None, Required or Optional.</param>
    /// <param name="Forms">Accepted binding forms.</param>
    /// <param name="Profile">Declaring profile.</param>
    /// <param name="Syntax">Optional special value layout.</param>
    private sealed record Definition(string ValueKind, string[] Forms, string Profile, string? Syntax = null);
    /// <summary>One resolved command/subcommand policy.</summary>
    /// <param name="Definitions">Ordinal option table.</param>
    /// <param name="StopAtOperand">Stop option parsing after an operand.</param>
    /// <param name="ShortGrouping">Allow clustered short flags.</param>
    /// <param name="NumericShortOption">Canonical numeric shorthand.</param>
    /// <param name="OpaqueTail">Subcommand tail is literal.</param>
    /// <param name="Raw">Command-level policy, including native selector rules.</param>
    private sealed record Policy(Dictionary<string, Definition> Definitions, bool StopAtOperand, bool ShortGrouping, string? NumericShortOption, bool OpaqueTail, IDictionary Raw);

    /// <summary>Resolves the same module-owned profiles and subcommand overrides without native probes.</summary>
    /// <param name="command">Git command.</param>
    /// <param name="schema">Curated module grammar.</param>
    /// <param name="subcommand">Optional selector.</param>
    private static Policy? Resolve(string command, IDictionary? schema, string? subcommand = null)
    {
        var raw = Map(Get(Map(Get(schema, "Commands")), command));
        if (raw == null) return null;
        var nested = subcommand == null ? null : Map(Get(Map(Get(raw, "Subcommands")), subcommand));
        var profiles = Strings(Get(raw, "Profiles")).Concat(Strings(Get(nested, "Profiles")));
        var definitions = new Dictionary<string, Definition>(StringComparer.Ordinal);
        foreach (string profileName in profiles)
        {
            var profile = Map(Get(Map(Get(schema, "Profiles")), profileName));
            if (profile == null) return null;
            foreach (string kind in new[] { "None", "Required", "Optional", "EqualsRequired", "AttachedRequired" })
                foreach (string name in Strings(Get(profile, kind)))
                {
                    string valueKind = kind == "None" ? "None" : kind == "Optional" ? "Optional" : "Required";
                    string[] forms = kind switch { "None" => ["Bare"], "Required" => name.StartsWith("--", StringComparison.Ordinal) ? ["Separate", "Equals"] : ["Separate", "Attached"], "Optional" => name.StartsWith("--", StringComparison.Ordinal) ? ["Bare", "Equals"] : ["Bare", "Attached"], "EqualsRequired" => ["Equals"], _ => ["Attached"] };
                    definitions[name] = new Definition(valueKind, forms, profileName);
                }
            foreach (string name in Strings(Get(profile, "Negatable")))
            {
                if (!name.StartsWith("--", StringComparison.Ordinal) || !definitions.ContainsKey(name)) return null;
                definitions["--no-" + name[2..]] = new Definition("None", ["Bare"], profileName);
            }
            if (Get(profile, "Custom") is IEnumerable custom)
                foreach (var value in custom)
                {
                    var item = Map(value)!;
                    definitions[(string)Get(item, "Name")!] = new Definition((string)Get(item, "ValueKind")!, Strings(Get(item, "Forms")).ToArray(), profileName, Get(item, "Syntax") as string);
                }
        }
        object? Setting(string key) => nested?.Contains(key) == true ? Get(nested, key) : Get(raw, key);
        return new Policy(definitions, Setting("StopAtOperand") is true, Setting("ShortGrouping") is true, Setting("NumericShortOption") as string, Setting("OpaqueTail") is true, raw);
    }

    /// <summary>Creates a unit with the same default/empty-value distinctions as the original facade.</summary>
    /// <param name="kind">Unit kind.</param>
    /// <param name="raw">Original spelling.</param>
    /// <param name="position">Original argv position.</param>
    /// <param name="emit">Represented native arguments.</param>
    /// <param name="name">Canonical option or subcommand.</param>
    /// <param name="valueKind">Arity.</param>
    /// <param name="value">Bound value.</param>
    /// <param name="hasValue">Explicit value presence.</param>
    /// <param name="binding">Binding spelling.</param>
    /// <param name="span">Original argv span.</param>
    /// <param name="valuePosition">Value argv index.</param>
    /// <param name="offset">Short cluster offset.</param>
    /// <param name="profile">Declaring profile.</param>
    /// <param name="values">Optional multi-value layout.</param>
    private static GitArgumentUnit Unit(string kind, string? raw, int position, string?[] emit, string? name = null, string valueKind = "None", string? value = null, bool hasValue = false, string binding = "None", int span = 1, int valuePosition = -1, int offset = 0, string? profile = null, string?[]? values = null)
        => new(kind, name ?? "", raw ?? "", valueKind, value ?? "", hasValue, binding, values ?? (hasValue ? [value] : []), position, span, valuePosition, offset, emit, profile ?? "");

    /// <summary>Binds exact argv; unknown arity retains the original vector without speculative rewrites.</summary>
    /// <param name="command">Command without Git globals.</param>
    /// <param name="arguments">Exact native arguments, including empty strings.</param>
    /// <param name="version">Observed version retained as evidence, not inferred qualification.</param>
    /// <param name="schema">Explicit Git-owned grammar.</param>
    public static GitBinding Bind(string command, string?[] arguments, string? version, IDictionary? schema)
    {
        var original = (string?[])arguments.Clone(); var tokens = new List<GitArgumentUnit>(); var unknown = new List<GitUnknown>();
        var policy = Resolve(command, schema); string? subcommand = null; bool selectorSeen = false, literal = false, stop = false;
        int index = 0, unknownIndex = -1, nativeSelector = -1; string? reason = null;
        if (policy == null) { unknownIndex = 0; reason = "No curated argument policy is available for this command."; }
        if (policy != null && Get(policy.Raw, "LiteralAllArguments") is true) stop = true;
        if (policy != null && Get(policy.Raw, "NativeSubcommandScan") is true)
            for (int candidate = 0; candidate < original.Length; candidate++)
                if (original[candidate] != null && Map(Get(policy.Raw, "Subcommands")) is IDictionary commands && commands.Keys.Cast<object>().Cast<string>().Contains(original[candidate], StringComparer.Ordinal))
                { nativeSelector = candidate; subcommand = original[candidate]; policy = Resolve(command, schema, subcommand); break; }
        while (unknownIndex < 0 && index < original.Length)
        {
            string? raw = original[index];
            if (raw == null) { unknownIndex = index; reason = "A native argv item cannot be null; use an explicit empty string when intended."; break; }
            if (index == nativeSelector) { tokens.Add(Unit("Subcommand", raw, index, [raw], raw)); selectorSeen = true; index++; continue; }
            if (literal || stop) { tokens.Add(Unit("Operand", raw, index, [raw])); index++; continue; }
            if (raw == "--") { tokens.Add(Unit("Separator", raw, index, [raw])); literal = true; index++; continue; }
            if (raw == "-" || !raw.StartsWith('-'))
            {
                bool eligible = !selectorSeen; selectorSeen = true;
                if (eligible && Map(Get(policy!.Raw, "Subcommands")) is IDictionary commands && commands.Keys.Cast<object>().Cast<string>().Contains(raw, StringComparer.Ordinal))
                {
                    subcommand = raw; tokens.Add(Unit("Subcommand", raw, index, [raw], raw)); policy = Resolve(command, schema, subcommand);
                    if (policy == null) { unknownIndex = index + 1; reason = "The subcommand argument policy could not be loaded."; break; }
                    if (policy.OpaqueTail) stop = true;
                }
                else { tokens.Add(Unit("Operand", raw, index, [raw])); if (policy!.StopAtOperand) stop = true; }
                index++; continue;
            }
            if (!string.IsNullOrEmpty(policy!.NumericShortOption) && Regex.Match(raw, @"^-(\d+)$") is { Success: true } numeric)
            { tokens.Add(Unit("Option", raw, index, [raw], policy.NumericShortOption, "Required", numeric.Groups[1].Value, true, "NumericShort", valuePosition: index, profile: "Revision")); index++; continue; }
            if (raw.StartsWith("--", StringComparison.Ordinal))
            {
                int equals = raw.IndexOf('='); string name = equals < 0 ? raw : raw[..equals];
                if (!policy.Definitions.TryGetValue(name, out var definition)) { unknownIndex = index; reason = "The arity of option " + name + " is not curated for this command."; break; }
                string? value = null; bool hasValue = false; int span = 1, valuePosition = -1; string binding = "Bare";
                if (equals >= 0)
                {
                    if (!Form(definition, "Equals")) { unknownIndex = index; reason = "This option does not declare an equals-bound value: " + name; break; }
                    value = raw[(equals + 1)..]; hasValue = true; valuePosition = index; binding = "Equals";
                }
                else if (Equal(definition.ValueKind, "Required"))
                {
                    if (!Form(definition, "Separate")) { unknownIndex = index; reason = "This option requires an attached value: " + name; break; }
                    if (index + 1 >= original.Length || original[index + 1] == null) { unknownIndex = index; reason = "A required option value is missing: " + name; break; }
                    if (index + 1 == nativeSelector) { unknownIndex = index; reason = "The native preliminary command selector occurs between an option and its value; this layout requires a dedicated binding."; break; }
                    value = original[index + 1]; hasValue = true; span = 2; valuePosition = index + 1; binding = "Separate";
                    if (Equal(definition.Syntax, "Cacheinfo"))
                    {
                        if (Regex.IsMatch(value!, @"^[0-7]+,[0-9a-f]{40}(?:[0-9a-f]{24})?,.*$", RegexOptions.IgnoreCase)) span = 2;
                        else if (Regex.IsMatch(value!, @"^[0-7]+$")) { span = 4; binding = "SeparateTuple"; }
                        else { unknownIndex = index; reason = "The cacheinfo payload is neither its comma tuple nor its legacy three-value form."; break; }
                        if (index + span > original.Length) { unknownIndex = index; reason = "The legacy cacheinfo mode/object/path tuple is incomplete."; break; }
                        if (original[(index + 1)..(index + span)].Any(item => item == null)) { unknownIndex = index; reason = "A cacheinfo payload value cannot be null."; break; }
                    }
                }
                else if (definition.Syntax is "PerlOptionalString" or "PerlOptionalInteger" && index + 1 < original.Length && original[index + 1] != null)
                {
                    string next = original[index + 1]!;
                    if (!next.StartsWith('-') || definition.Syntax == "PerlOptionalInteger" && Regex.IsMatch(next, @"^-\d+$"))
                    {
                        if (index + 1 == nativeSelector) { unknownIndex = index; reason = "The native preliminary command selector intersects an optional value layout not yet curated."; break; }
                        value = next; hasValue = true; span = 2; valuePosition = index + 1; binding = "SeparateOptional";
                    }
                }
                else if (!Form(definition, "Bare")) { unknownIndex = index; reason = "A bare spelling is not curated for " + name; break; }
                string?[] values = hasValue ? span > 1 ? original[(index + 1)..(index + span)] : [value] : [];
                tokens.Add(Unit("Option", raw, index, original[index..(index + span)], name, definition.ValueKind, value, hasValue, binding, span, valuePosition, profile: definition.Profile, values: values));
                if (name == "--end-of-options" || Strings(Get(policy.Raw, "StopAfterOptions")).Contains(name, StringComparer.Ordinal)) stop = true;
                index += span; continue;
            }
            var pending = new List<GitArgumentUnit>(); int consumed = 1;
            for (int offset = 1; offset < raw.Length; offset++)
            {
                string name = "-" + raw[offset];
                if (!policy.Definitions.TryGetValue(name, out var definition)) { unknownIndex = index; reason = "The arity of short option " + name + " is not curated for this command."; break; }
                string? value = null; bool hasValue = false; int valuePosition = -1; string binding = "Bare"; string?[] emit = [name];
                if (!Equal(definition.ValueKind, "None"))
                {
                    if (offset + 1 < raw.Length)
                    {
                        if (!Form(definition, "Attached")) { unknownIndex = index; reason = "This short option does not declare an attached value: " + name; break; }
                        value = raw[(offset + 1)..]; hasValue = true; valuePosition = index; binding = "Attached"; emit = [name + value];
                    }
                    else if (Equal(definition.ValueKind, "Required"))
                    {
                        if (!Form(definition, "Separate")) { unknownIndex = index; reason = "This short option requires an attached value: " + name; break; }
                        if (index + 1 >= original.Length || original[index + 1] == null) { unknownIndex = index; reason = "A required short-option value is missing: " + name; break; }
                        if (index + 1 == nativeSelector) { unknownIndex = index; reason = "The native preliminary command selector occurs between a short option and its value; this layout requires a dedicated binding."; break; }
                        value = original[index + 1]; hasValue = true; consumed = 2; valuePosition = index + 1; binding = "Separate"; emit = [name, value];
                    }
                }
                pending.Add(Unit("Option", emit[0], index, emit, name, definition.ValueKind, value, hasValue, binding, consumed, valuePosition, offset, definition.Profile));
                if (hasValue) break;
                if (!policy.ShortGrouping && offset + 1 < raw.Length) { unknownIndex = index; reason = "Grouped short flags are not curated for this command parser."; break; }
            }
            if (unknownIndex >= 0) break;
            tokens.AddRange(pending); index += consumed;
        }
        if (unknownIndex >= 0)
        {
            unknown.Add(new GitUnknown(unknownIndex, unknownIndex < original.Length ? original[unknownIndex] : null, reason));
            for (int tail = unknownIndex; tail < original.Length; tail++) tokens.Add(Unit("Unparsed", original[tail], tail, [original[tail]]));
        }
        bool complete = unknown.Count == 0;
        var options = tokens.Where(item => item.Kind == "Option").ToArray(); var operands = tokens.Where(item => item.Kind == "Operand").ToArray();
        return new GitBinding(1, command, version, complete, tokens.ToArray(), options, operands.Select(item => item.Raw).ToArray(), operands, subcommand, unknown.ToArray(), original, complete ? tokens.SelectMany(item => item.EmitArguments).ToArray() : original, "Curated token binding; not exhaustive argument or value validation");
    }
}

/// <summary>Bound Git argument, preserving exact native spelling and value presence.</summary>
/// <param name="Kind">Option, Operand, Separator, Subcommand or Unparsed.</param>
/// <param name="Name">Canonical option/selector.</param>
/// <param name="Raw">Original or cluster-unit spelling.</param>
/// <param name="ValueKind">Declared arity.</param>
/// <param name="Value">Bound scalar.</param>
/// <param name="HasValue">Explicit empty differs from absent.</param>
/// <param name="Binding">Spelling form.</param>
/// <param name="Values">Possibly multi-value layout.</param>
/// <param name="Position">Original argv index.</param>
/// <param name="Span">Consumed argv items.</param>
/// <param name="ValuePosition">Original value index.</param>
/// <param name="ClusterOffset">Short flag offset.</param>
/// <param name="EmitArguments">Exact represented arguments.</param>
/// <param name="Profile">Declaring grammar profile.</param>
public sealed record GitArgumentUnit(string Kind, string? Name, string? Raw, string ValueKind, string? Value, bool HasValue, string Binding, string?[] Values, int Position, int Span, int ValuePosition, int ClusterOffset, string?[] EmitArguments, string? Profile);
/// <summary>Explicit unknown-arity position and diagnostic.</summary>
/// <param name="Position">First unparsed index.</param>
/// <param name="Raw">Original token or null.</param>
/// <param name="Reason">Why interpretation stopped.</param>
public sealed record GitUnknown(int Position, string? Raw, string? Reason);
/// <summary>Complete token binding evidence; never claims full Git semantic support.</summary>
/// <param name="SchemaVersion">Binding schema.</param>
/// <param name="Command">Git command.</param>
/// <param name="Version">Observed version.</param>
/// <param name="Complete">Only the arity binding completed.</param>
/// <param name="Tokens">Ordered units.</param>
/// <param name="Options">Bound options.</param>
/// <param name="Operands">Operand strings.</param>
/// <param name="OperandTokens">Operand units.</param>
/// <param name="Subcommand">Selected nested command.</param>
/// <param name="Unknowns">Incomplete interpretation evidence.</param>
/// <param name="OriginalArguments">Detached original argv.</param>
/// <param name="EmitArguments">Safe forwarding vector.</param>
/// <param name="PolicyScope">Explicit support boundary.</param>
public sealed record GitBinding(int SchemaVersion, string Command, string? Version, bool Complete, GitArgumentUnit[] Tokens, GitArgumentUnit[] Options, string?[] Operands, GitArgumentUnit[] OperandTokens, string? Subcommand, GitUnknown[] Unknowns, string?[] OriginalArguments, string?[] EmitArguments, string PolicyScope);
