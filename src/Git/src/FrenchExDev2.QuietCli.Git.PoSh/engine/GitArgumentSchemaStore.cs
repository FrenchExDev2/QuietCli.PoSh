using System.Collections;
using System.Text.Json;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Locates and caches the module-owned argument grammar; never executes a binary.</summary>
public static class GitArgumentSchemaStore
{
    /// <summary>Relative path of the curated grammar inside the module root.</summary>
    public const string RelativePath = "metadata/Git.ArgumentSchema.json";

    /// <summary>Largest grammar file accepted, bounding memory before parsing.</summary>
    private const int MaxBytes = 4 * 1024 * 1024;

    /// <summary>Deepest JSON nesting accepted.</summary>
    private const int MaxDepth = 40;

    /// <summary>Guards the cached grammar.</summary>
    private static readonly object Gate = new();

    /// <summary>Root directory whose metadata folder holds the grammar; set once by the module loader.</summary>
    public static string? Root { get; set; }

    /// <summary>Grammar parsed for <see cref="cachedRoot"/>.</summary>
    private static Hashtable? cached;

    /// <summary>Root the cached grammar was read from.</summary>
    private static string? cachedRoot;

    /// <summary>Reads the grammar of <see cref="Root"/> once and returns the cached copy afterwards.</summary>
    /// <returns>The curated grammar, or null when the file is absent.</returns>
    public static Hashtable? Load()
    {
        string? root = Root;
        if (string.IsNullOrEmpty(root)) return null;
        lock (Gate)
        {
            if (cached is not null && string.Equals(cachedRoot, root, StringComparison.Ordinal)) return cached;
            string path = Path.Combine(root, RelativePath);
            if (!File.Exists(path)) return null;
            var info = new FileInfo(path);
            if (info.Length > MaxBytes) throw new InvalidDataException("GitArgumentSchemaTooLarge");
            using JsonDocument document = JsonDocument.Parse(File.ReadAllBytes(path), new JsonDocumentOptions { MaxDepth = MaxDepth });
            if (document.RootElement.ValueKind != JsonValueKind.Object) throw new InvalidDataException("GitArgumentSchemaNotAnObject");
            cached = Map(document.RootElement);
            cachedRoot = root;
            return cached;
        }
    }

    /// <summary>Parses grammar text, for deterministic tests with an explicit schema.</summary>
    /// <param name="json">Strict JSON document.</param>
    /// <returns>The grammar as case-insensitive maps, arrays and scalars.</returns>
    public static Hashtable Parse(string json)
    {
        using JsonDocument document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = MaxDepth });
        if (document.RootElement.ValueKind != JsonValueKind.Object) throw new InvalidDataException("GitArgumentSchemaNotAnObject");
        return Map(document.RootElement);
    }

    /// <summary>Converts a JSON element the way a PowerShell 7 hashtable conversion does: case-sensitive keys (<c>-C</c> and <c>-c</c> differ), object arrays.</summary>
    /// <param name="element">JSON value.</param>
    private static object? Convert(JsonElement element) => element.ValueKind switch
    {
        JsonValueKind.Object => Map(element),
        JsonValueKind.Array => element.EnumerateArray().Select(Convert).ToArray(),
        JsonValueKind.String => element.GetString(),
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.Number => element.TryGetInt64(out long whole) ? (object)whole : element.GetDouble(),
        _ => null,
    };

    /// <summary>Builds one case-sensitive map, rejecting exact duplicate keys.</summary>
    /// <param name="element">JSON object.</param>
    private static Hashtable Map(JsonElement element)
    {
        var table = new Hashtable(StringComparer.Ordinal);
        foreach (JsonProperty property in element.EnumerateObject())
        {
            if (table.ContainsKey(property.Name)) throw new InvalidDataException("GitArgumentSchemaDuplicateKey");
            table[property.Name] = Convert(property.Value);
        }
        return table;
    }
}
