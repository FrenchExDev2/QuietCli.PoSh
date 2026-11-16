namespace FrenchExDev2.QuietCli;

/// <summary>Validates the resolved facade options of one call and reports the first stable error code.</summary>
public static class FacadeOptionValidator
{
    private static readonly string[] Tokenizers = ["off", "o200k_base", "cl100k_base"];
    private static readonly string[] Transports = ["Pipe", "Pty"];
    private static readonly string[] StreamModes = ["Text", "Bytes"];
    private static readonly string[] Roles = ["Business", "Probe", "Observation", "Infrastructure"];

    // PowerShell -in/-notin comparisons were case-insensitive; keep that facade behavior unchanged.
    private static bool Contains(string[] allowed, string? value) => value is not null && Array.Exists(allowed, x => string.Equals(x, value, StringComparison.OrdinalIgnoreCase));

    /// <summary>Returns the first violated rule, in the historical facade order, or null when every option is valid.</summary>
    /// <param name="tokenizer">Token-counting encoding name.</param>
    /// <param name="transport">Pipe or Pty.</param>
    /// <param name="stdoutMode">Text or Bytes.</param>
    /// <param name="stderrMode">Text or Bytes.</param>
    /// <param name="role">Source role.</param>
    /// <param name="timeoutSeconds">Execution deadline.</param>
    /// <param name="maxRecordBytes">Largest retained record.</param>
    /// <param name="maxOutputBytes">Delivery budget.</param>
    /// <param name="maxItems">Maximum delivered items.</param>
    /// <param name="drainTimeoutSeconds">Post-exit drain deadline.</param>
    /// <param name="readBlockBytes">Native read block size.</param>
    /// <param name="terminalSize">Columns followed by rows.</param>
    public static string? FirstError(string? tokenizer, string? transport, string? stdoutMode, string? stderrMode, string? role, double timeoutSeconds, double maxRecordBytes, double maxOutputBytes, double maxItems, double drainTimeoutSeconds, double readBlockBytes, double[]? terminalSize)
    {
        if (!Contains(Tokenizers, tokenizer)) return "InvalidTokenizer";
        if (!Contains(Transports, transport) || !Contains(StreamModes, stdoutMode) || !Contains(StreamModes, stderrMode)) return "InvalidTransportOrStreamMode";
        if (!Contains(Roles, role)) return "InvalidSourceRole";
        // Negated comparisons also reject NaN; a non-finite budget is never a usable limit.
        if (timeoutSeconds <= 0 || !(maxRecordBytes >= 1) || !(maxOutputBytes >= RequestLimits.MinOutputBytes) || !(maxItems >= 0) || !double.IsFinite(maxRecordBytes) || !double.IsFinite(maxOutputBytes) || !double.IsFinite(maxItems)) return "InvalidLimits";
        if (!RequestLimits.IsValidTimeout(timeoutSeconds)) return "InvalidTimeout";
        if (!RequestLimits.IsValidDrainTimeout(drainTimeoutSeconds)) return "InvalidDrainTimeout";
        if (!RequestLimits.IsValidReadBlock(readBlockBytes)) return "InvalidReadBlockBytes";
        if (terminalSize is not { Length: 2 } || !RequestLimits.IsValidDimension(terminalSize[0]) || !RequestLimits.IsValidDimension(terminalSize[1])) return "InvalidTerminalSize";
        return null;
    }
}
