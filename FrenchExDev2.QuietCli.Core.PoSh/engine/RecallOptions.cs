using System.Globalization;
using System.Text.RegularExpressions;

namespace FrenchExDev2.QuietCli;

/// <summary>Retention policy over observed native bytes.</summary>
public enum RecallPolicy
{
    /// <summary>Retains the earliest observed bytes.</summary>
    Head,
    /// <summary>Retains the most recently observed bytes.</summary>
    Tail,
    /// <summary>Splits the budget between the earliest and latest bytes.</summary>
    HeadAndTail
}

/// <summary>Validated caller-local retention settings, independent of process execution.</summary>
public sealed class RecallOptions
{
    /// <summary>Default retained native byte budget.</summary>
    public const long DefaultMaximum = 16 * 1024 * 1024;
    /// <summary>Null denotes explicitly unlimited retention.</summary>
    public long? MaximumBytes { get; }
    /// <summary>Selected retention policy.</summary>
    public RecallPolicy Policy { get; }

    /// <summary>Validates a size and policy before execution.</summary>
    /// <param name="size">Positive integer byte count, integral IEC size, or All.</param>
    /// <param name="policy">Head, Tail or HeadAndTail.</param>
    public RecallOptions(string size, string policy)
    {
        if (!Enum.TryParse(policy, true, out RecallPolicy parsed) || !Enum.IsDefined(parsed) || !string.Equals(parsed.ToString(), policy, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("InvalidRecallPolicy");
        Policy = parsed;
        MaximumBytes = ParseSize(size);
        if (MaximumBytes == null && Policy != RecallPolicy.Head) throw new ArgumentException("UnlimitedRecallRequiresHead");
    }

    /// <summary>Parses a culture-independent integral byte budget with checked arithmetic.</summary>
    /// <param name="value">Positive bytes, IEC size, or All.</param>
    public static long? ParseSize(string value)
    {
        if (string.Equals(value, "All", StringComparison.OrdinalIgnoreCase)) return null;
        var match = Regex.Match(value ?? "", @"\A([0-9]+)\s*(B|KiB|MiB|GiB)?\z", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1));
        if (!match.Success || !long.TryParse(match.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out long count) || count < 1)
            throw new ArgumentException("InvalidRecallSize");
        long factor = match.Groups[2].Value.ToUpperInvariant() switch { "KIB" => 1024L, "MIB" => 1048576L, "GIB" => 1073741824L, _ => 1L };
        return checked(count * factor);
    }
}
