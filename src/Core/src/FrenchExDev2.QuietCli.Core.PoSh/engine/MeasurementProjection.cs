using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using FrenchExDev2.QuietCli.Storage;

namespace FrenchExDev2.QuietCli;

/// <summary>Projects legacy telemetry to safe fields on read; permanent scrubbing is a separate explicit operation.</summary>
internal static class MeasurementProjection
{
    /// <summary>Copies only metadata DTO properties, without inspecting arbitrary nested business properties.</summary>
    /// <param name="payload">Stored event JSON.</param>
    internal static JsonElement Read(string payload)
    {
        var node = JsonNode.Parse(payload, documentOptions: new JsonDocumentOptions { MaxDepth = 64 });
        return JsonSerializer.SerializeToElement(Project(node, typeof(MeasurementRecord)));
    }

    /// <summary>Explicitly removes legacy exception messages and unknown shapes, preserving known counters.</summary>
    /// <param name="database">Existing verified QuietCli2 database.</param>
    internal static int Scrub(Database database)
    {
        int changed = 0; string after = "";
        database.Execute("PRAGMA secure_delete=ON", []);
        database.Execute("BEGIN IMMEDIATE", []);
        try {
            while (true) {
                var page = database.Query("SELECT id,payload FROM quiet2_events WHERE id>? ORDER BY id LIMIT 16", [after]);
                if (page.Count == 0) break;
                foreach (var row in page) {
                    string original = (string)row["payload"], id = (string)row["id"];
                    string safe = Read(original).GetRawText();
                    if (!JsonElement.DeepEquals(JsonSerializer.Deserialize<JsonElement>(original), JsonSerializer.Deserialize<JsonElement>(safe))) {
                        database.Execute("UPDATE quiet2_events SET payload=? WHERE id=?", [safe, id]); changed++;
                    }
                    after = id;
                }
            }
            database.Execute("COMMIT", []);
        } catch { database.TryRollback(); throw; }
        return changed;
    }

    /// <summary>Projects a single typed metadata node. Unknown properties such as Data and Message are skipped.</summary>
    /// <param name="node">Legacy node, never a caller business object.</param>
    /// <param name="type">Declared safe metadata type.</param>
    private static JsonNode? Project(JsonNode? node, Type type)
    {
        if (node == null) return null;
        type = Nullable.GetUnderlyingType(type) ?? type;
        if (type.IsArray) {
            var result = new JsonArray();
            IEnumerable<JsonNode?> items = node is JsonArray array ? array : new[] { node };
            foreach (var item in items) result.Add(Project(item, type.GetElementType()!));
            return result;
        }
        if (type == typeof(string) || type.IsValueType) return node is JsonValue ? node.DeepClone() : null;
        if (node is not JsonObject map) return null;
        var output = new JsonObject();
        foreach (var property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance)) {
            if (!map.TryGetPropertyValue(property.Name, out var value)) continue;
            if (value != null && property.PropertyType == typeof(string) && property.Name is "Code" or "Phase" or "Error") {
                string? code = value is JsonValue scalar && scalar.TryGetValue<string>(out var text) ? text : null;
                output[property.Name] = code != null && code.Length <= 64 && code.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-' or '.') ? code : "LegacyDiagnostic";
            } else output[property.Name] = Project(value, property.PropertyType);
        }
        return output;
    }
}
