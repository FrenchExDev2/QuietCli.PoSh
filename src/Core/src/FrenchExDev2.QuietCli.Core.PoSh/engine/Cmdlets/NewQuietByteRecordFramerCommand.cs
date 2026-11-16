using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Creates a compiled local framer without IPC or per-byte PowerShell dispatch.</summary>
[Cmdlet(VerbsCommon.New, "QuietByteRecordFramer")]
[OutputType(typeof(ByteRecordFramer))]
public sealed class NewQuietByteRecordFramerCommand : PSCmdlet
{
    /// <summary>Exact record delimiter byte.</summary>
    [Parameter] public byte Delimiter { get; set; } = 10;

    /// <summary>Maximum retained unfinished record size.</summary>
    [Parameter] [ValidateRange(1, int.MaxValue)] public int MaxRecordBytes { get; set; } = 1048576;

    /// <inheritdoc />
    protected override void EndProcessing() => WriteObject(new ByteRecordFramer(Delimiter, MaxRecordBytes));
}
