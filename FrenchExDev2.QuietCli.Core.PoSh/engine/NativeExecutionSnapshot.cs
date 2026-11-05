namespace FrenchExDev2.QuietCli;

/// <summary>Detached, mutable runtime view; the facade freezes a separate copy in the final result.</summary>
internal sealed class NativeExecutionSnapshot
{
    /// <summary>Owned native process identity.</summary>
    public int ProcessId { get; set; }
    /// <summary>Pipe or terminal transport.</summary>
    public string Transport { get; set; } = "";
    /// <summary>Maximum transient read block.</summary>
    public int ReadBlockBytes { get; set; }
    /// <summary>Observed exit status, if available.</summary>
    public int? ExitCode { get; set; }
    /// <summary>Observed execution outcome.</summary>
    public string Outcome { get; set; } = "";
    /// <summary>Completed native input writes.</summary>
    public long StdinBytesWritten { get; set; }
    /// <summary>Stdout bytes, unknown for a merged terminal.</summary>
    public long? StdoutBytesRead { get; set; }
    /// <summary>Stderr bytes, unknown for a merged terminal.</summary>
    public long? StderrBytesRead { get; set; }
    /// <summary>Merged terminal bytes, absent for pipes.</summary>
    public long? TerminalBytesRead { get; set; }
    /// <summary>Elapsed native execution and drainage time.</summary>
    public double ElapsedMs { get; set; }
    /// <summary>Whether all native sources reached EOF.</summary>
    public bool SourceComplete { get; set; }
    /// <summary>Structured native error identifier.</summary>
    public string? Error { get; set; }
    /// <summary>Native lifecycle state.</summary>
    public string State { get; set; } = "";
    /// <summary>Observed or uncertain native effects.</summary>
    public string EffectStatus { get; set; } = "";
}
