using System.Collections;

namespace FrenchExDev2.QuietCli.Git;

/// <summary>Native operation outcomes annotated with independently observed conflicts.</summary>
public static class GitOperationOutcome
{
    /// <summary>Reports observed conflicts separately from the command's native success.</summary>
    /// <param name="exitCode">Actual native exit code.</param>
    /// <param name="conflicts">After-observation unmerged-entry count, or null if unavailable.</param>
    public static string Outcome(int exitCode, long? conflicts) => exitCode == 0
        ? "Completed"
        : conflicts > 0 ? "FailedWithConflicts" : "Failed";
}
