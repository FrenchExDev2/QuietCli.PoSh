using System.Collections;
using System.Globalization;
using System.Text;

namespace FrenchExDev2.QuietCli;

/// <summary>Caller-local probe cache identity without JSON, content capture or extra version executions.</summary>
public static class ProbeIdentity
{
    /// <summary>Combines exact handler/file metadata and canonical child environment overrides.</summary>
    /// <param name="handlerId">Registered handler identity.</param>
    /// <param name="path">Resolved executable path.</param>
    /// <param name="environment">Explicit string/null child overrides.</param>
    public static string Build(string handlerId, string path, IDictionary environment)
    {
        var file = new FileInfo(path);
        if (!file.Exists) throw new FileNotFoundException("ProbeExecutableUnavailable", path);
        var key = new StringBuilder();
        void Add(string? value) { if (value == null) key.Append("-1:"); else key.Append(value.Length).Append(':').Append(value); }
        Add(handlerId); Add(file.FullName); Add(file.Length.ToString(CultureInfo.InvariantCulture)); Add(file.LastWriteTimeUtc.Ticks.ToString(CultureInfo.InvariantCulture));
        var entries = new SortedDictionary<string, string?>(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        foreach (DictionaryEntry entry in environment)
        {
            object? value = CallerMetadata.Unwrap(entry.Value);
            if (entry.Key is not string name || value is not (null or string)) throw new InvalidDataException("InvalidEnvironment");
            entries[name] = (string?)value;
        }
        foreach (var entry in entries) { Add(entry.Key); Add(entry.Value); }
        return key.ToString();
    }
}
