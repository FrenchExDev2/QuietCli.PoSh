using System.Text.Json;

namespace FrenchExDev2.QuietCli;

/// <summary>Shared C#/PowerShell wire specification, copied beside compiled assemblies.</summary>
internal static class ProtocolSpecification
{
    /// <summary>Supported wire version.</summary>
    internal static readonly int Version;
    /// <summary>Maximum encoded control header bytes.</summary>
    internal static readonly int HeaderLimit;
    /// <summary>Maximum transient binary payload bytes.</summary>
    internal static readonly int BlockSize;
    /// <summary>Maximum queued blocks per stream direction.</summary>
    internal static readonly int QueueBlocks;
    /// <summary>Deadline for a frame after its first byte arrives; idle sessions remain reusable.</summary>
    internal static readonly double ReadFrameTimeoutSeconds;
    /// <summary>Deadline for a response write to its private pipe.</summary>
    internal static readonly double WriteFrameTimeoutSeconds;
    /// <summary>Loads the versioned manifest and enforces hard safety ceilings.</summary>
    static ProtocolSpecification()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(Path.GetDirectoryName(typeof(ProtocolSpecification).Assembly.Location)!, "protocol.json"), System.Text.Encoding.UTF8));
        var root = document.RootElement;
        Version = root.GetProperty("Version").GetInt32(); HeaderLimit = root.GetProperty("HeaderLimit").GetInt32(); BlockSize = root.GetProperty("BlockSize").GetInt32(); QueueBlocks = root.GetProperty("QueueBlocks").GetInt32();
        ReadFrameTimeoutSeconds = root.GetProperty("ReadFrameTimeoutSeconds").GetDouble(); WriteFrameTimeoutSeconds = root.GetProperty("WriteFrameTimeoutSeconds").GetDouble();
        if (Version != 1 || HeaderLimit < 65536 || HeaderLimit > 1048576 || BlockSize < 1024 || BlockSize > 16384 || QueueBlocks < 1 || QueueBlocks > 16 || ReadFrameTimeoutSeconds <= 0 || ReadFrameTimeoutSeconds > 30 || WriteFrameTimeoutSeconds <= 0 || WriteFrameTimeoutSeconds > 60) throw new InvalidDataException("UnsafeProtocolSpecification");
    }
}
