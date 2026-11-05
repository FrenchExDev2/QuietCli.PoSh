using System.Collections;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Strict object-identity records for object-producing Git queries.</summary>
public static class GitObjectRecords
{
    /// <summary>Accepts complete SHA-1 or SHA-256 object identifiers without truncation.</summary>
    /// <param name="value">ASCII identifier bytes.</param>
    public static bool IsObjectId(ReadOnlySpan<byte> value)
    {
        if (value.Length != 40 && value.Length != 64) return false;
        return IsHexadecimal(value);
    }
    /// <summary>Tests nonempty ASCII hex without inferring a hash algorithm from abbreviations.</summary>
    /// <param name="value">Complete or abbreviated identifier bytes.</param>
    public static bool IsHexadecimal(ReadOnlySpan<byte> value)
    {
        if (value.IsEmpty) return false;
        foreach (byte item in value)
            if (!(item is >= (byte)'0' and <= (byte)'9' or >= (byte)'a' and <= (byte)'f' or >= (byte)'A' and <= (byte)'F')) return false;
        return true;
    }

    /// <summary>Consumes an identity or an identity followed by parent identities.</summary>
    /// <param name="record">One LF-framed native line.</param>
    /// <param name="data">Invocation-owned Objects list and optional WithParents flag.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        ReadOnlySpan<byte> line = record;
        if (line.EndsWith("\r"u8)) line = line[..^1];
        if (line.IsEmpty) throw new InvalidDataException("EmptyObjectRecord");
        string[] fields = Encoding.ASCII.GetString(line).Split(' ');
        bool parents = GitRecords.Unwrap(data["WithParents"]) is true;
        if (!parents && fields.Length != 1) throw new InvalidDataException("UnexpectedObjectFields");
        foreach (string field in fields)
            if (!IsObjectId(Encoding.ASCII.GetBytes(field))) throw new InvalidDataException("MalformedObjectIdentity");
        var item = GitRecords.Map("ObjectId", fields[0], "Algorithm", fields[0].Length == 40 ? "sha1" : "sha256");
        if (parents) item["Parents"] = fields.Skip(1).ToArray();
        ((IList)GitRecords.Unwrap(data["Objects"])!).Add(item);
    }
}
