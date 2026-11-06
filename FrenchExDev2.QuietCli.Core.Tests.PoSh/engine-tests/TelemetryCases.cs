using System.Text.Json;
using FrenchExDev2.QuietCli;

/// <summary>Independent allocation, serialization-scope properties and malformed metadata regressions.</summary>
internal static class TelemetryCases
{
    /// <summary>Runs deterministic generated cases through the existing companion runner.</summary>
    /// <param name="run">Companion case runner.</param>
    /// <param name="store">Private companion SQLite store.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run, MeasurementStore store)
    {
        await run("allocation samples include generated payloads and stop exactly once", () =>
        {
            var random = new Random(87499);
            for (int index = 0; index < 256; index++)
            {
                int length = random.Next(1, 131073);
                var outer = new AllocationMeter();
                var inner = new AllocationMeter();
                byte[] payload = new byte[length];
                var sample = inner.Stop();
                var enclosing = outer.Stop();
                Check(sample.Status == "Measured" && sample.AllocatedBytes >= length, "Payload allocations were not counted");
                Check(sample.StartThreadId == sample.EndThreadId && enclosing.AllocatedBytes >= sample.AllocatedBytes, "Nested allocation intervals changed scope");
                Check(ReferenceEquals(sample, inner.Stop()), "Stopping again remeasured the interval");
                GC.KeepAlive(payload);
            }
            return Task.CompletedTask;
        });
        await run("allocation thread changes never subtract unrelated counters", async () =>
        {
            var meter = new AllocationMeter();
            var completion = new TaskCompletionSource<AllocationMeasurement>(TaskCreationOptions.RunContinuationsAsynchronously);
            new Thread(() => completion.SetResult(meter.Stop())).Start();
            var sample = await completion.Task;
            Check(sample.Status == "ThreadChanged" && sample.AllocatedBytes == null && sample.StartThreadId != sample.EndThreadId, "Cross-thread sample invented a size");
        });
        await run("process snapshots include background allocations with explicit precision and process scope", () =>
        {
            var before = ProcessAllocationSnapshot.Capture(true);
            byte[]? payload = null;
            var completion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            new Thread(() => { payload = new byte[1048576]; completion.SetResult(true); }).Start();
            // Keep both samples on this thread so a thread-only counter cannot impersonate a process counter.
            completion.Task.GetAwaiter().GetResult();
            var after = ProcessAllocationSnapshot.Capture(true);
            Check(after.AllocatedBytes - before.AllocatedBytes >= 1048576, "Background managed allocations were not counted");
            Check(before.ProcessId == Environment.ProcessId && after.ProcessId == before.ProcessId && after.Precise && after.Scope == "ProcessWideManagedAllocations" && !after.IncludesNativeAllocations, "Process allocation scope was misrepresented");
            Check(!ProcessAllocationSnapshot.Capture().Precise, "Expensive precise counter became implicit");
            GC.KeepAlive(payload);
            return Task.CompletedTask;
        });
        await run("gain generated mixed scopes exclude object-only work and count every delivery", () =>
        {
            var random = new Random(56841);
            for (int iteration = 0; iteration < 256; iteration++)
            {
                var accumulator = new GainAccumulator("Context");
                long nativeBytes = 0, deliveredBytes = 0; int serialized = 0, deliveryCount = 0;
                int roots = random.Next(2, 32);
                for (int index = 0; index < roots; index++)
                {
                    int bytes = random.Next(1, 65536); string id = "source-" + index;
                    var source = new SourceMeasurement(id, "Business", 0, bytes, 0, Complete: true);
                    var invocation = new MeasurementRecord(id, Role: "Business", Outcome: "Success", Completeness: new(true, true), Sources: [source], Allocation: new(100, 1, 1, "Measured"), CompleteAllocation: new(20, 1, 1, "Measured"));
                    accumulator.Add(invocation);
                    // The first root is always object-only and the second always serialized.
                    int count = index == 0 ? 0 : index == 1 ? 1 : random.Next(0, 4);
                    if (count > 0) { serialized++; nativeBytes += bytes; }
                    for (int delivery = 0; delivery < count; delivery++)
                    {
                        int output = random.Next(1, 4096); deliveredBytes += output; deliveryCount++;
                        accumulator.Add(invocation with { DeliveryId = $"delivery-{index}-{delivery}", OutputBytes = output });
                    }
                }
                var view = JsonSerializer.SerializeToElement(accumulator.Build(true).Summary);
                Check(view.GetProperty("ReductionBytes").GetInt64() == nativeBytes - deliveredBytes, "Object-only work inflated or blocked a serialization gain");
                Check(view.GetProperty("RootDeliveries").GetInt32() == deliveryCount && view.GetProperty("SerializedRoots").GetInt32() == serialized && view.GetProperty("UnserializedRoots").GetInt32() == roots - serialized, "Serialization coverage changed");
                Check(view.GetProperty("RootInvocationAllocatedBytes").GetInt64() == roots * 100 && view.GetProperty("RootCompleteAllocatedBytes").GetInt64() == roots * 20, "Deliveries duplicated allocation samples");
            }
            return Task.CompletedTask;
        });
        await run("gain snapshots support delayed deliveries and reject missing evidence", () =>
        {
            var source = new SourceMeasurement("shared", "Business", 0, 1024, 0, Complete: true);
            var delivery = new MeasurementRecord("root", Role: "Business", Completeness: new(true, true), Sources: [source], DeliveryId: "one", OutputBytes: 100);
            var accumulator = new GainAccumulator("Context");
            accumulator.Add(delivery); // The invocation may predate the selected report window.
            accumulator.Add(delivery with { DeliveryId = "two", OutputBytes = 200 });
            accumulator.Add(delivery with { InvocationId = "child", ParentId = "root", DeliveryId = "child", OutputBytes = 9000 });
            accumulator.Add(delivery with { InvocationId = "probe", Role = "Probe", DeliveryId = "probe", OutputBytes = 9000 });
            var view = JsonSerializer.SerializeToElement(accumulator.Build(true).Summary);
            Check(view.GetProperty("ReductionBytes").GetInt64() == 724 && view.GetProperty("Invocations").GetInt32() == 0, "Delayed, repeated or auxiliary deliveries changed the comparison");
            foreach (var invalid in new[] {
                delivery with { Sources = null }, delivery with { OutputBytes = null }, delivery with { Completeness = new(true, false) },
                delivery with { Sources = [source with { Complete = false }] }, delivery with { Sources = [source with { StderrBytesRead = null }] }
            })
            {
                var partial = new GainAccumulator("Context"); partial.Add(invalid);
                Check(JsonSerializer.SerializeToElement(partial.Build(true).Summary).GetProperty("ReductionBytes").ValueKind == JsonValueKind.Null, "Missing evidence proved a gain");
            }
            var noDelivery = new GainAccumulator("Context");
            noDelivery.Add(delivery with { DeliveryId = null, OutputBytes = null });
            Check(JsonSerializer.SerializeToElement(noDelivery.Build(true).Summary).GetProperty("ReductionBytes").ValueKind == JsonValueKind.Null, "AsObject invented an output reduction");
            var chronology = new GainAccumulator("Context");
            chronology.Add(delivery with { Sources = [source with { Complete = false }] });
            chronology.Add(delivery with { DeliveryId = "later-complete" });
            Check(JsonSerializer.SerializeToElement(chronology.Build(true).Summary).GetProperty("ReductionBytes").ValueKind == JsonValueKind.Null, "A later snapshot hid an earlier incomplete delivery");
            return Task.CompletedTask;
        });
        await run("allocation metadata fuzz rejects invalid counters status and thread combinations", () =>
        {
            var random = new Random(9874);
            for (int iteration = 0; iteration < 512; iteration++)
            {
                long? bytes = iteration % 3 == 0 ? null : random.Next(-128, 129);
                int start = random.Next(-1, 4), end = random.Next(-1, 4);
                string status = new[] { "Measured", "ThreadChanged", "Unknown", "" }[random.Next(4)];
                bool valid = start > 0 && end > 0 && (status == "Measured" && start == end && bytes.HasValue && bytes >= 0 || status == "ThreadChanged" && start != end && bytes == null);
                bool accepted = true;
                try { MeasurementModels.Validate(new MeasurementRecord("fuzz", Allocation: new(bytes, start, end, status)), "invocation"); }
                catch (InvalidDataException) { accepted = false; }
                Check(accepted == valid, $"Allocation schema mismatch at seed 9874 iteration {iteration}");
            }
            return Task.CompletedTask;
        });
        await run("root allocations exclude nested copies and preserve historical unknown sizes", () =>
        {
            var accumulator = new GainAccumulator("Role");
            accumulator.Add(new("root", Allocation: new(4096, 1, 1, "Measured"), CompleteAllocation: new(1024, 1, 1, "Measured")));
            accumulator.Add(new("child", ParentId: "root", Allocation: new(2048, 1, 1, "Measured"), CompleteAllocation: new(512, 1, 1, "Measured")));
            var view = JsonSerializer.SerializeToElement(accumulator.Build(true).Summary);
            Check(view.GetProperty("RootInvocationAllocatedBytes").GetInt64() == 4096 && view.GetProperty("RootCompleteAllocatedBytes").GetInt64() == 1024, "Nested allocations counted twice");
            accumulator.Add(new("historical"));
            view = JsonSerializer.SerializeToElement(accumulator.Build(true).Summary);
            Check(view.GetProperty("RootInvocationAllocatedBytes").ValueKind == JsonValueKind.Null && view.GetProperty("AllocationMeasuredRoots").GetInt32() == 1, "Historical missing allocation was treated as zero");
            return Task.CompletedTask;
        });
        await run("SQLite allocation rows and reports explicitly identify changed threads", async () =>
        {
            var changed = new AllocationMeasurement(null, 11, 12, "ThreadChanged");
            var record = new MeasurementRecord("thread-change", Context: "thread-change", Allocation: changed, CompleteAllocation: changed);
            await store.SaveAsync(record, "invocation");
            var query = JsonSerializer.SerializeToElement(new { From = 0L, To = DateTimeOffset.UtcNow.AddDays(1).ToUnixTimeMilliseconds(), Context = "thread-change" });
            var response = JsonSerializer.SerializeToElement(await store.QueryAsync(query));
            var row = response.GetProperty("Rows")[0];
            foreach (string field in new[] { "Allocation", "CompleteAllocation" })
            {
                var value = row.GetProperty(field);
                Check(value.GetProperty("Status").GetString() == "ThreadChanged" && value.GetProperty("AllocatedBytes").ValueKind == JsonValueKind.Null && value.GetProperty("StartThreadId").GetInt32() == 11 && value.GetProperty("EndThreadId").GetInt32() == 12, "SQLite hid the thread-change explanation");
            }
            var summary = JsonSerializer.SerializeToElement((await store.GainAsync(query)).Summary);
            Check(summary.GetProperty("AllocationThreadChangedRoots").GetInt32() == 1 && summary.GetProperty("RootCompleteAllocationThreadChanges").GetInt32() == 1 && summary.GetProperty("RootInvocationAllocatedBytes").ValueKind == JsonValueKind.Null, "Aggregate report hid thread changes");
        });
    }

    /// <summary>Checks an independent invariant with a retained deterministic seed on failure.</summary>
    /// <param name="condition">Expected true condition.</param>
    /// <param name="message">Failure context.</param>
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
