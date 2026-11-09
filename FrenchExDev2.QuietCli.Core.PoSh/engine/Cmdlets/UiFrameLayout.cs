using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Spectre.Console;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Fits a live frame to the current viewport without wrapping or hiding its project/task heading.</summary>
internal static class UiFrameLayout
{
    private static readonly Regex Ansi = new(@"\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))", RegexOptions.CultureInvariant);

    /// <summary>Creates bounded plain-text rows; callers remeasure the viewport for every draw.</summary>
    /// <param name="glyph">Current animation frame.</param><param name="header">Project/task and path lines.</param>
    /// <param name="lanes">Ordered lane histories.</param><param name="width">Available display cells.</param>
    /// <param name="height">Available rows.</param>
    internal static string[] Create(string glyph, IReadOnlyList<string> header, IReadOnlyList<LaneSnapshot> lanes, int width, int height)
    {
        width = Math.Max(1, width); height = Math.Max(1, height);
        var rows = new List<string>();
        int headerCount = Math.Min(header.Count, Math.Max(1, height - Math.Min(lanes.Count, height - 1)));
        for (int i = 0; i < headerCount; i++) rows.Add(i == 0 ? Heading(header[i], width) : Fit(header[i], width));
        int available = height - rows.Count;
        int visible = Math.Min(lanes.Count, available);
        bool hidden = visible < lanes.Count;
        if (hidden && visible > 1) visible--;
        for (int i = 0; i < visible; i++)
        {
            LaneSnapshot lane = lanes[i];
            int budget = Math.Max(1, (available - (hidden && available > 1 ? 1 : 0)) / visible);
            int take = Math.Min(Math.Max(1, lane.Lines.Count), budget);
            for (int line = take; line > 0; line--)
            {
                string label = lane.Key.Length == 0 ? glyph : $"{glyph} [{lane.Key}]";
                string prefix = Fit(label, Math.Max(1, width / 3));
                string content = lane.Lines.Count == 0 ? "" : lane.Lines[lane.Lines.Count - line];
                rows.Add(Fit(prefix + " " + content, width));
            }
        }
        if (hidden && rows.Count < height) rows.Add(Fit($"… {lanes.Count - visible} more lanes", width));
        if (rows.Count == 0) rows.Add(Fit(glyph, width));
        return rows.ToArray();
    }

    /// <summary>Compacts both parts of the identity before clipping a narrow heading.</summary>
    private static string Heading(string value, int width)
    {
        if (Clean(value).GetCellWidth() <= width) return Fit(value, width);
        int separator = value.IndexOf(" | Task: ", StringComparison.Ordinal);
        if (separator < 0 || width < 12) return Fit(value, width);
        string project = value[..separator].Replace("Project: ", "", StringComparison.Ordinal).Replace("QuietCli ", "QC ", StringComparison.Ordinal);
        string task = value[(separator + " | Task: ".Length)..];
        int projectWidth = (width - 5) / 2;
        return Fit($"P:{Fit(project, projectWidth)} T:{Fit(task, width - 5 - projectWidth)}", width);
    }

    /// <summary>Clips by display cells without cutting Unicode text elements or preserving terminal controls.</summary>
    private static string Fit(string value, int width)
    {
        string clean = Clean(value);
        if (clean.GetCellWidth() <= width) return clean;
        var text = new StringBuilder();
        var elements = StringInfo.GetTextElementEnumerator(clean);
        while (elements.MoveNext())
        {
            string element = elements.GetTextElement();
            if ((text.ToString() + element).GetCellWidth() > width - 1) break;
            text.Append(element);
        }
        return text + "…";
    }

    /// <summary>Removes ANSI commands and converts control characters or malformed UTF-16 into inert text.</summary>
    private static string Clean(string value)
    {
        var text = new StringBuilder();
        foreach (Rune rune in Ansi.Replace(value, "").EnumerateRunes())
            text.Append(Rune.GetUnicodeCategory(rune) == UnicodeCategory.Control ? " " : rune.ToString());
        return text.ToString();
    }
}
