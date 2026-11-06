using System.Collections;
using System.Collections.Specialized;
using System.Globalization;
using System.Management.Automation;

namespace FrenchExDev2.QuietCli;

/// <summary>Omission counters shared by every projection of one delivery.</summary>
public sealed class ProjectionState
{
    /// <summary>Entries or characters dropped to honor the bounds.</summary>
    public long Omitted { get; set; }
    /// <summary>True once an omission could not be counted exactly.</summary>
    public bool UnknownOmissions { get; set; }
    /// <summary>Nodes visited so far.</summary>
    public int Nodes { get; set; }
}

/// <summary>Builds the bounded delivery view of a business value; never used by AsObject.</summary>
public static class QuietProjection
{
    /// <summary>Maximum nodes visited in one delivery.</summary>
    private const int MaxNodes = 512;
    /// <summary>Default structural depth.</summary>
    public const int DefaultDepth = 24;

    /// <summary>Projects a value into ordered dictionaries, arrays and bounded scalars.</summary>
    /// <param name="value">Business value to present.</param>
    /// <param name="state">Omission counters shared by the delivery.</param>
    /// <param name="maxItems">Maximum collection entries per container.</param>
    /// <param name="maxCharacters">Maximum characters per string.</param>
    /// <param name="depth">Remaining structural depth.</param>
    public static object? Project(object? value, ProjectionState state, int maxItems, int maxCharacters, int depth = DefaultDepth)
    {
        if (value is PSObject wrapped && wrapped.BaseObject is not PSCustomObject) value = wrapped.BaseObject;
        if (value is null) return null;
        state.Nodes++;
        if (depth <= 0 || state.Nodes > MaxNodes) { state.Omitted++; state.UnknownOmissions = true; return "[StructureLimit]"; }
        if (value is string text)
        {
            if (text.Length <= maxCharacters) return text;
            state.Omitted++;
            int limit = maxCharacters;
            if (limit > 0 && char.IsHighSurrogate(text[limit - 1])) limit--;
            return text.Substring(0, limit) + "…";
        }
        if (value is ValueType) return value;
        if (value is IDictionary map)
        {
            var copy = new OrderedDictionary();
            int count = 0;
            foreach (object key in map.Keys)
            {
                if (count++ >= maxItems) { state.Omitted += map.Count - maxItems; break; }
                copy[Convert.ToString(key, CultureInfo.InvariantCulture) ?? ""] = Project(map[key], state, maxItems, maxCharacters, depth - 1);
            }
            return copy;
        }
        if (value is IEnumerable items)
        {
            var copy = new List<object?>();
            int count = 0;
            foreach (object? item in items)
            {
                if (count++ >= maxItems)
                {
                    if (value is ICollection collection) state.Omitted += collection.Count - maxItems;
                    else { state.Omitted++; state.UnknownOmissions = true; }
                    break;
                }
                copy.Add(Project(item, state, maxItems, maxCharacters, depth - 1));
            }
            return copy.ToArray();
        }
        var bag = new OrderedDictionary();
        int seen = 0;
        foreach (PSPropertyInfo property in PSObject.AsPSObject(value).Properties)
        {
            if (seen++ >= maxItems) { state.Omitted++; continue; }
            bag[property.Name] = Project(property.Value, state, maxItems, maxCharacters, depth - 1);
        }
        return bag;
    }
}

/// <summary>Reads members of PowerShell results, hashtables and CLR objects uniformly.</summary>
public static class Members
{
    /// <summary>Returns a named member; absent members and null containers yield null.</summary>
    /// <param name="container">Dictionary, PSObject or CLR object.</param>
    /// <param name="name">Member or key name.</param>
    public static object? Get(object? container, string name)
    {
        if (container is PSObject wrapped && wrapped.BaseObject is not PSCustomObject) container = wrapped.BaseObject;
        if (container is null) return null;
        if (container is IDictionary map) return map.Contains(name) ? map[name] : null;
        return PSObject.AsPSObject(container).Properties[name]?.Value;
    }

    /// <summary>Sets or adds a note property, replacing an existing value.</summary>
    /// <param name="target">PowerShell object to update.</param>
    /// <param name="name">Property name.</param>
    /// <param name="value">New value.</param>
    public static void SetNote(object target, string name, object? value)
    {
        PSObject bag = PSObject.AsPSObject(target);
        PSPropertyInfo? existing = bag.Properties[name];
        if (existing is not null) existing.Value = value;
        else bag.Properties.Add(new PSNoteProperty(name, value));
    }
}
