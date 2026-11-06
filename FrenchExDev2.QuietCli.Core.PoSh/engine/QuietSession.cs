namespace FrenchExDev2.QuietCli;

/// <summary>Per-process module state shared by the compiled cmdlets; one module instance is loaded at a time.</summary>
public static class QuietSession
{
    /// <summary>Guards snapshot replacement so a reader never observes a half-published value.</summary>
    private static readonly object gate = new();

    /// <summary>Module root directory that holds <c>resources</c>, <c>lib</c> and the manifest.</summary>
    public static string Root { get; private set; } = "";

    /// <summary>Session configuration snapshot, read lazily from the YAML file.</summary>
    public static ConfigurationSnapshot? Configuration { get; set; }

    /// <summary>Identity of this module session, reported by engine diagnostics.</summary>
    public static string SessionId { get; private set; } = Guid.NewGuid().ToString("N");

    /// <summary>The engine this session owns, or null while none is started.</summary>
    public static EngineConnection? Engine { get; set; }

    /// <summary>Database path of the engine currently running, or null while no engine is started.</summary>
    public static string? ActiveDatabase => Engine?.Database;

    /// <summary>Starts a fresh session for the module being imported.</summary>
    /// <param name="root">Module root directory.</param>
    public static void Initialize(string root)
    {
        lock (gate) {
            Root = root;
            Configuration = null;
            Engine = null;
            SessionId = Guid.NewGuid().ToString("N");
            ResourceVerifier.Reset();
        }
    }
}
