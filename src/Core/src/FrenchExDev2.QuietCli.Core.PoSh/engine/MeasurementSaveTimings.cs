namespace FrenchExDev2.QuietCli;

/// <summary>Opt-in wall timings of one metadata save. No business values or persisted schema fields.</summary>
/// <param name="QueueWaitMs">Admission and worker queue wait; may include earlier background preparation.</param>
/// <param name="WriteGateWaitMs">Wait for other writers targeting the same database in this process.</param>
/// <param name="ValidationMs">Closed-schema validation and metadata JSON encoding.</param>
/// <param name="WriterPreparationMs">Writer lookup, or opening, schema initialization and statement preparation.</param>
/// <param name="SqliteWriteMs">Bindings, SQLite execution and reset; includes transaction/commit for deliveries.</param>
/// <param name="WriterAlreadyPrepared">Whether this save reused the existing writer.</param>
internal sealed record MeasurementSaveTimings(double QueueWaitMs, double WriteGateWaitMs, double ValidationMs,
    double WriterPreparationMs, double SqliteWriteMs, bool WriterAlreadyPrepared);

/// <summary>Worker-owned mutable timer state, allocated only for an explicitly measured save.</summary>
internal sealed class MeasurementSaveTimer
{
    internal long Enqueued = System.Diagnostics.Stopwatch.GetTimestamp();
    internal double QueueWaitMs, WriteGateWaitMs, ValidationMs, WriterPreparationMs, SqliteWriteMs;
    internal bool WriterAlreadyPrepared;
    /// <summary>Detaches the completed counters without retaining the writer or metadata.</summary>
    internal MeasurementSaveTimings Snapshot() => new(QueueWaitMs, WriteGateWaitMs, ValidationMs,
        WriterPreparationMs, SqliteWriteMs, WriterAlreadyPrepared);
}
