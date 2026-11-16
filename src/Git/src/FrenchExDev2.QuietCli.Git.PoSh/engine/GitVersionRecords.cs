using System.Collections;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Version identity and explicitly requested build information.</summary>
public static class GitVersionRecords
{
    /// <summary>Consumes a version header or one build-information record.</summary>
    /// <param name="record">One LF-framed native record.</param>
    /// <param name="data">Invocation-owned Version and BuildInformation.</param>
    public static void Receive(byte[] record, IDictionary data)
    {
        object decoded = GitRecords.Decode(record);
        if (GitRecords.Unwrap(data["Version"]) is null)
        {
            if (decoded is not string text || !text.StartsWith("git version ", StringComparison.Ordinal) || text.Length <= 12)
                throw new InvalidDataException("MalformedGitVersion");
            data["Version"] = text[12..].TrimEnd('\r');
        }
        else ((IList)GitRecords.Unwrap(data["BuildInformation"])!).Add(decoded);
    }
}
