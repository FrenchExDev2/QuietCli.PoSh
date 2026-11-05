using System.Collections;
using System.Text;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Maps fixed NUL reflog fields without parsing localized display summaries.</summary>
public static class GitReflogRecords
{
    /// <summary>Appends one independently framed reflog entry.</summary>
    /// <param name="fields">Object ID, selector, identity name/mail and complete message.</param>
    /// <param name="data">Invocation-owned Entries list.</param>
    public static void Append(IList fields, IDictionary data)
    {
        if (fields.Count != 5 || GitRecords.Unwrap(fields[0]) is not string id || !GitObjectRecords.IsObjectId(Encoding.ASCII.GetBytes(id)))
            throw new InvalidDataException("MalformedReflogEntry");
        var entry = GitRecords.Map("ObjectId", id, "Selector", GitRecords.Unwrap(fields[1]), "Name", GitRecords.Unwrap(fields[2]),
            "Email", GitRecords.Unwrap(fields[3]), "Message", GitRecords.Unwrap(fields[4]));
        ((IList)GitRecords.Unwrap(data["Entries"])!).Add(entry);
    }
}
