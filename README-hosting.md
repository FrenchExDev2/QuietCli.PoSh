# Hosting and native transports

[Back to the QuietCli overview](README.md)

How the engine is hosted and how it talks to native processes. Related: [performance and hosting](docs/performance-and-hosting.md), [PowerShell/C# responsibilities](docs/powershell-csharp-boundaries.md), [package installation](docs/PSGallery.md).

`Auto` hosting selects the compatible integrated C# build from the actual PowerShell CLR: `net10.0` on .NET 10 and `net11.0` on .NET 11 or later. Business callbacks, data, decoding and framing stay caller-local. Integrated native reads and lifecycle controls use direct C# calls rather than pipe IPC.

Set YAML `engine.hosting: Process` explicitly for the isolated engine, which requires the pinned .NET 11 RC runtime. `InProcess` explicitly selects direct hosting. Set the mode before the first engine call, or use `Stop-QuietEngine` before changing it. `Get-QuietEngine` reports the actual mode, runtime, process identity and transport counters.

Distributions target Windows x64/ARM64 and Linux glibc/musl x64/ARM64. The facade selects the actual host RID and verifies packaged resources. Pipes preserve separate stdout/stderr; PTY merges output into `TerminalBytesRead`, leaving separate stream counts unknown. Windows uses ConPTY; Linux uses verified native bridges.

Integrated hosting shares PowerShell's failure boundary. Process isolation provides a separate engine boundary. A timeout stops the owned native process, but cannot forcibly interrupt an arbitrary blocked PowerShell callback. Callbacks must cooperate with cancellation. `-DrainTimeoutSeconds` bounds waiting for EOF after native exit; interrupted drainage is explicitly incomplete. Communication failures never trigger automatic command retries and can leave a mutation's effect unknown.

See [hosting and performance](docs/performance-and-hosting.md) and [PowerShell/C# responsibilities](docs/powershell-csharp-boundaries.md).
