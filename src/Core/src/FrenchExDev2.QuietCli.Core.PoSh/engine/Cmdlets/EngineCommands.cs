using System.Collections;
using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Shared engine access for the cmdlets that talk to the private engine.</summary>
public abstract class EngineCmdlet : QuietCmdlet
{
    /// <summary>Per-exchange deadline from engine.ipcTimeoutSeconds.</summary>
    protected double IpcTimeout => EngineLifecycle.Seconds(Setting("engine.ipcTimeoutSeconds"));

    /// <summary>Returns the running engine, starting it lazily when needed.</summary>
    protected EngineConnection EnsureEngine()
    {
        EngineConnection? engine = QuietSession.Engine;
        if (EngineLifecycle.IsRunning(engine)) return engine!;
        return EngineLifecycle.Start(Convert.ToString(Setting("engine.hosting"), System.Globalization.CultureInfo.InvariantCulture) ?? "", Convert.ToString(Setting("telemetry.database"), System.Globalization.CultureInfo.InvariantCulture) ?? "", IpcTimeout);
    }
}

/// <summary>Starts the private engine lazily, without transferring business objects; internal to the module.</summary>
[Cmdlet(VerbsLifecycle.Start, "QuietEngine")]
public sealed class StartQuietEngineCommand : EngineCmdlet
{
    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { EnsureEngine(); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}

/// <summary>Exchanges one bounded metadata frame and an optional transient byte block; internal to the module.</summary>
[Cmdlet(VerbsCommunications.Send, "QuietRequest")]
[OutputType(typeof(PSObject))]
public sealed class SendQuietRequestCommand : EngineCmdlet
{
    /// <summary>Control metadata, never a business object.</summary>
    [Parameter(Position = 0, Mandatory = true)]
    public IDictionary Header { get; set; } = new Hashtable();

    /// <summary>Native input bytes, at most one protocol block.</summary>
    [Parameter(Position = 1)]
    public byte[] Payload { get; set; } = [];

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try
        {
            // An existing engine is used as is, even when broken, so the caller sees EngineDisconnected rather than a silent restart.
            EngineConnection engine = QuietSession.Engine ?? EnsureEngine();
            EngineReply reply = EngineClient.Send(engine, Header, Payload ?? [], IpcTimeout);
            var result = new PSObject();
            result.Properties.Add(new PSNoteProperty("Header", reply.Header));
            result.Properties.Add(new PSNoteProperty("Payload", reply.Payload));
            WriteObject(result);
        }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}

/// <summary>Closes the owned engine normally and flushes accepted measurement writes.</summary>
[Cmdlet(VerbsLifecycle.Stop, "QuietEngine")]
public sealed class StopQuietEngineCommand : EngineCmdlet
{
    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try { EngineLifecycle.Stop(QuietSession.Engine is null ? 1 : IpcTimeout); }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }
}

/// <summary>Returns engine identity and optional process-wide allocation diagnostics, without native output.</summary>
[Cmdlet(VerbsCommon.Get, "QuietEngine")]
[OutputType(typeof(PSObject))]
public sealed class GetQuietEngineCommand : EngineCmdlet
{
    /// <summary>Samples caller and engine process counters explicitly, including background workers and concurrent work.</summary>
    [Parameter]
    public SwitchParameter IncludeAllocations { get; set; }

    /// <summary>Opts into the higher-cost precise process counter; requires IncludeAllocations.</summary>
    [Parameter]
    public SwitchParameter Precise { get; set; }

    /// <inheritdoc />
    protected override void EndProcessing()
    {
        try
        {
            if (Precise && !IncludeAllocations) { Fail("AllocationPrecisionRequiresIncludeAllocations"); return; }
            EngineConnection engine = EnsureEngine();
            PSObject? allocations = null;
            if (IncludeAllocations)
            {
                ProcessAllocationSnapshot caller = ProcessAllocationSnapshot.Capture(Precise);
                object? other = engine.Mode == "InProcess" ? caller : PropertyReader.Get(EngineClient.Send(engine, new Hashtable { ["Action"] = "allocations", ["Precise"] = (bool)Precise }, [], IpcTimeout).Header, "Data");
                allocations = Build(("Caller", caller), ("Engine", other),
                    ("SharedProcess", Convert.ToInt32(PropertyReader.Get(caller, "ProcessId")) == Convert.ToInt32(PropertyReader.Get(other, "ProcessId"))),
                    ("Attribution", "All managed threads and concurrent work; diagnostics only. Shared caller/engine samples must not be added."));
            }
            PSObject identity = Build(("SessionId", QuietSession.SessionId), ("Mode", engine.Mode), ("Engine", engine.Info), ("Requests", engine.Requests),
                ("DirectRequests", engine.DirectRequests), ("MetadataJsonRequests", engine.MetadataJsonRequests), ("ProtocolInputBytes", engine.InputBytes),
                ("ProtocolOutputBytes", engine.OutputBytes), ("Database", engine.Database));
            if (allocations is not null) identity.Properties.Add(new PSNoteProperty("Allocations", allocations));
            WriteObject(identity);
        }
        catch (Exception error) when (error is not PipelineStoppedException) { FailWith(error); }
    }

    /// <summary>Builds an ordered custom object.</summary>
    private static PSObject Build(params (string Name, object? Value)[] fields)
    {
        var result = new PSObject();
        foreach ((string name, object? value) in fields) result.Properties.Add(new PSNoteProperty(name, value));
        return result;
    }
}
