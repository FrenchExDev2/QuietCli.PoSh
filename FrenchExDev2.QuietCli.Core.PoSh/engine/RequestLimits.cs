namespace FrenchExDev2.QuietCli;

/// <summary>Single source of truth for native-request limits shared by the facade and the engine.</summary>
public static class RequestLimits
{
    /// <summary>Smallest accepted drain timeout, in seconds.</summary>
    public const double MinDrainTimeoutSeconds = 0.05;

    /// <summary>Largest accepted drain timeout, in seconds.</summary>
    public const double MaxDrainTimeoutSeconds = 300;

    /// <summary>Smallest accepted native read block, in bytes.</summary>
    public const int MinReadBlockBytes = 1024;

    /// <summary>Largest accepted terminal width or height.</summary>
    public const int MaxTerminalDimension = 1000;

    /// <summary>Smallest accepted delivered-output budget, in bytes.</summary>
    public const double MinOutputBytes = 256;

    /// <summary>Largest timeout whose millisecond value fits an unsigned 32-bit timer.</summary>
    public const double MaxTimeoutSeconds = (uint.MaxValue - 1L) / 1000.0;

    /// <summary>Checks the native execution deadline.</summary>
    /// <param name="seconds">Deadline in seconds.</param>
    public static bool IsValidTimeout(double seconds) => double.IsFinite(seconds) && seconds > 0 && seconds <= MaxTimeoutSeconds;

    /// <summary>Checks the post-exit drain deadline.</summary>
    /// <param name="seconds">Drain deadline in seconds.</param>
    public static bool IsValidDrainTimeout(double seconds) => double.IsFinite(seconds) && seconds >= MinDrainTimeoutSeconds && seconds <= MaxDrainTimeoutSeconds;

    /// <summary>Checks a native read-block size against the negotiated protocol block size.</summary>
    /// <param name="bytes">Requested block size.</param>
    public static bool IsValidReadBlock(double bytes) => bytes >= MinReadBlockBytes && bytes <= ProtocolSpecification.BlockSize;

    /// <summary>Checks one terminal dimension, used for initial sizes and interactive resizes.</summary>
    /// <param name="value">Columns or rows.</param>
    public static bool IsValidDimension(double value) => value >= 1 && value <= MaxTerminalDimension;

    /// <summary>Checks a transport name.</summary>
    /// <param name="transport">Candidate transport.</param>
    public static bool IsValidTransport(string? transport) => transport is "Pipe" or "Pty";
}
