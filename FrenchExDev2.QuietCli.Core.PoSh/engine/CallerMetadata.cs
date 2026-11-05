using System.Collections;
using System.Collections.ObjectModel;

namespace FrenchExDev2.QuietCli;

/// <summary>Caller-local detached metadata copies; never receives Result.Data or crosses the engine pipe.</summary>
public static class CallerMetadata
{
    /// <summary>Copies dictionaries, sequences and the closed native snapshot into read-only containers.</summary>
    /// <param name="value">Execution, completeness or diagnostic metadata only.</param>
    /// <param name="adapt">Caller-thread adapter for PowerShell property bags, without a background runspace.</param>
    public static object? Freeze(object? value, Func<object, IDictionary> adapt) => Copy(value, adapt, new HashSet<object>(ReferenceEqualityComparer.Instance));

    /// <summary>Removes only the known PowerShell wrapper, preserving custom property bags for the caller adapter.</summary>
    /// <param name="value">Possibly wrapped metadata or normalized scalar.</param>
    internal static object? Unwrap(object? value)
    {
        while (value?.GetType().FullName == "System.Management.Automation.PSObject")
        {
            var item = value.GetType().GetProperty("BaseObject")!.GetValue(value);
            if (item?.GetType().FullName == "System.Management.Automation.PSCustomObject") return value;
            if (ReferenceEquals(item, value)) break;
            value = item;
        }
        return value;
    }

    /// <summary>Recurses through owned metadata containers and rejects cycles explicitly.</summary>
    /// <param name="value">Metadata node.</param>
    /// <param name="adapt">Synchronous property-bag adapter.</param>
    /// <param name="active">Ancestors used only for cycle detection.</param>
    private static object? Copy(object? value, Func<object, IDictionary> adapt, HashSet<object> active)
    {
        value = Unwrap(value);
        if (value is null or string or ValueType) return value;
        if (!active.Add(value)) throw new InvalidDataException("MetadataSnapshotCycle");
        try
        {
            if (value is IDictionary map) return Map(map, adapt, active);
            if (value is IEnumerable sequence)
            {
                var items = new List<object?>();
                foreach (var item in sequence) items.Add(Copy(item, adapt, active));
                return items.AsReadOnly();
            }
            if (value is NativeExecutionSnapshot native)
            {
                var fields = new Hashtable(StringComparer.Ordinal);
                foreach (var property in typeof(NativeExecutionSnapshot).GetProperties()) fields.Add(property.Name, property.GetValue(native));
                return Map(fields, adapt, active);
            }
            return Map(adapt(value), adapt, active);
        }
        finally { active.Remove(value); }
    }

    /// <summary>Copies an ordinal dictionary without sharing its mutable descendants.</summary>
    /// <param name="source">Source metadata map.</param>
    /// <param name="adapt">Property-bag adapter.</param>
    /// <param name="active">Active ancestors.</param>
    private static ReadOnlyDictionary<string, object?> Map(IDictionary source, Func<object, IDictionary> adapt, HashSet<object> active)
    {
        var result = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (DictionaryEntry entry in source) result.Add((string)entry.Key, Copy(entry.Value, adapt, active));
        return new ReadOnlyDictionary<string, object?>(result);
    }
}
