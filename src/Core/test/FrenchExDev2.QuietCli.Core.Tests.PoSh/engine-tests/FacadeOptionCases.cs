using System.Collections;
using FrenchExDev2.QuietCli;

/// <summary>Independent boundary, ordering and consistency assertions for the shared native-request limits.</summary>
internal static class FacadeOptionCases
{
    /// <summary>Fixed seed retained so any failing generated input can be replayed deterministically.</summary>
    private const int Seed = 20261106;

    // Oracle constants are written literally here on purpose: they must not be read from the implementation.
    private const double MaxTimeout = 4294967.294;

    /// <summary>Runs the facade-limit cases without creating operating-system processes.</summary>
    /// <param name="run">Existing companion assertion runner.</param>
    internal static async Task RunAsync(Func<string, Func<Task>, Task> run)
    {
        await run("facade limits accept the documented inclusive boundaries", () =>
        {
            foreach (double timeout in new[] { 0.001, 1, MaxTimeout })
                foreach (double drain in new[] { 0.05, 30, 300 })
                    foreach (double block in new[] { 1024d, 4096, 16384 })
                        foreach (double dimension in new[] { 1d, 120, 1000 })
                            Require(Valid(timeout: timeout, drain: drain, block: block, size: [dimension, dimension]) == null, $"Valid boundary rejected: {timeout}/{drain}/{block}/{dimension}");
            Require(Valid(maxOutput: 256, maxRecord: 1, maxItems: 0) == null, "Minimum delivery limits rejected");
            return Task.CompletedTask;
        });
        await run("facade limits reject each value just outside its boundary with a stable code", () =>
        {
            Expect("InvalidLimits", Valid(timeout: 0));
            Expect("InvalidLimits", Valid(timeout: -1));
            Expect("InvalidLimits", Valid(maxRecord: 0));
            Expect("InvalidLimits", Valid(maxOutput: 255));
            Expect("InvalidLimits", Valid(maxItems: -1));
            foreach (double unusable in new[] { double.NaN, double.PositiveInfinity, double.NegativeInfinity })
            {
                Expect("InvalidLimits", Valid(maxRecord: unusable));
                Expect("InvalidLimits", Valid(maxOutput: unusable));
                Expect("InvalidLimits", Valid(maxItems: unusable));
            }
            Expect("InvalidTimeout", Valid(timeout: MaxTimeout + 0.001));
            Expect("InvalidTimeout", Valid(timeout: double.NaN));
            Expect("InvalidTimeout", Valid(timeout: double.PositiveInfinity));
            Expect("InvalidDrainTimeout", Valid(drain: 0.049));
            Expect("InvalidDrainTimeout", Valid(drain: 300.001));
            Expect("InvalidDrainTimeout", Valid(drain: double.NaN));
            Expect("InvalidReadBlockBytes", Valid(block: 1023));
            Expect("InvalidReadBlockBytes", Valid(block: 16385));
            Expect("InvalidTerminalSize", Valid(size: [0, 10]));
            Expect("InvalidTerminalSize", Valid(size: [10, 1001]));
            Expect("InvalidTerminalSize", Valid(size: [10]));
            Expect("InvalidTerminalSize", Valid(size: [1, 2, 3]));
            Expect("InvalidTerminalSize", FacadeOptionValidator.FirstError("off", "Pipe", "Text", "Text", "Business", 60, 1048576, 65536, 1000, 30, 16384, null));
            Expect("InvalidTokenizer", Valid(tokenizer: "gpt2"));
            Expect("InvalidTokenizer", Valid(tokenizer: null));
            Expect("InvalidTransportOrStreamMode", Valid(transport: "Socket"));
            Expect("InvalidTransportOrStreamMode", Valid(stdout: "Binary"));
            Expect("InvalidTransportOrStreamMode", Valid(stderr: ""));
            Expect("InvalidSourceRole", Valid(role: "Admin"));
            return Task.CompletedTask;
        });
        await run("facade limits keep the historical precedence when several options are invalid", () =>
        {
            Expect("InvalidTokenizer", Valid(tokenizer: "x", transport: "x", role: "x", timeout: 0, drain: 0, block: 0, size: []));
            Expect("InvalidTransportOrStreamMode", Valid(transport: "x", role: "x", timeout: 0, drain: 0, block: 0, size: []));
            Expect("InvalidSourceRole", Valid(role: "x", timeout: 0, drain: 0, block: 0, size: []));
            Expect("InvalidLimits", Valid(timeout: 0, drain: 0, block: 0, size: []));
            Expect("InvalidTimeout", Valid(timeout: double.NaN, drain: 0, block: 0, size: []));
            Expect("InvalidDrainTimeout", Valid(drain: 0, block: 0, size: []));
            Expect("InvalidReadBlockBytes", Valid(block: 0, size: []));
            return Task.CompletedTask;
        });
        await run("facade names keep the case-insensitive acceptance of the former PowerShell membership test", () =>
        {
            Require(Valid(tokenizer: "O200K_BASE", transport: "pipe", stdout: "text", stderr: "BYTES", role: "probe") == null, "Case-insensitive names rejected");
            return Task.CompletedTask;
        });
        await run("generated valid options are accepted and each single corruption maps to exactly its code", () =>
        {
            var random = new Random(Seed);
            for (int iteration = 0; iteration < 2000; iteration++)
            {
                double timeout = 0.001 + random.NextDouble() * (MaxTimeout - 0.001), drain = 0.05 + random.NextDouble() * 299.95, block = random.Next(1024, 16385);
                double[] size = [random.Next(1, 1001), random.Next(1, 1001)];
                string where = $"seed={Seed} iteration={iteration}";
                Require(Valid(timeout: timeout, drain: drain, block: block, size: size) == null, "Valid generated options rejected: " + where);
                Expect("InvalidTimeout", Valid(timeout: MaxTimeout + 1 + random.NextDouble() * 1e6, drain: drain, block: block, size: size), where);
                Expect("InvalidDrainTimeout", Valid(timeout: timeout, drain: random.Next(2) == 0 ? random.NextDouble() * 0.049 : 300.01 + random.NextDouble() * 1e3, block: block, size: size), where);
                Expect("InvalidReadBlockBytes", Valid(timeout: timeout, drain: drain, block: random.Next(2) == 0 ? random.Next(0, 1024) : random.Next(16385, 100000), size: size), where);
                Expect("InvalidTerminalSize", Valid(timeout: timeout, drain: drain, block: block, size: [random.Next(2) == 0 ? random.Next(-5, 1) : random.Next(1001, 5000), size[1]]), where);
            }
            return Task.CompletedTask;
        });
        await run("native launch validation and facade validation agree on every generated limit", () =>
        {
            var random = new Random(Seed + 1);
            double[] specials = [double.NaN, double.PositiveInfinity, double.NegativeInfinity, 0, -0.0, MaxTimeout, MaxTimeout + 0.001, 0.05, 0.049999, 300, 300.000001];
            for (int iteration = 0; iteration < 3000; iteration++)
            {
                double timeout = random.Next(3) == 0 ? specials[random.Next(specials.Length)] : (random.NextDouble() - 0.1) * MaxTimeout * 1.1;
                double drain = random.Next(3) == 0 ? specials[random.Next(specials.Length)] : (random.NextDouble() - 0.1) * 330;
                int block = random.Next(-10, 20000), columns = random.Next(-10, 1100), rows = random.Next(-10, 1100);
                bool facadeAccepts = Valid(timeout: timeout, drain: drain, block: block, size: [columns, rows]) == null;
                var request = new InvocationRequest("id", "tool", [], ".", new Hashtable(), "Pipe", columns, rows, timeout, drain, block, [0], false, null);
                bool engineAccepts = true;
                try { _ = request.Validated(); } catch (ArgumentException) { engineAccepts = false; }
                Require(facadeAccepts == engineAccepts, $"Facade and engine disagree: seed={Seed + 1} iteration={iteration} timeout={timeout} drain={drain} block={block} size={columns}x{rows}");
            }
            return Task.CompletedTask;
        });
    }

    /// <summary>Builds a fully valid option set, overriding only the requested fields.</summary>
    private static string? Valid(string? tokenizer = "off", string? transport = "Pipe", string? stdout = "Text", string? stderr = "Text", string? role = "Business", double timeout = 60, double maxRecord = 1048576, double maxOutput = 65536, double maxItems = 1000, double drain = 30, double block = 16384, double[]? size = null)
        => FacadeOptionValidator.FirstError(tokenizer, transport, stdout, stderr, role, timeout, maxRecord, maxOutput, maxItems, drain, block, size ?? [120, 40]);

    private static void Expect(string code, string? actual, string context = "") => Require(actual == code, $"Expected {code} but got {actual ?? "<valid>"} {context}");

    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
