# Typed native controls and input readiness - 5 November 2026

Integrated hosting now uses closed C# controls for input, EOF, cancellation, resize and release. Successful replies contain fixed local objects, without JSON encoding or decoding. Both hosts share EngineSession.ControlAsync and the same native state transitions. The isolated protocol and its limits remain compatible. Startup and telemetry retain bounded metadata JSON; rejected requests retain bounded JSON diagnostics. Caller business objects and scriptblocks never cross this API.

PowerShell continues splitting input into bounded blocks and consuming output during back-pressure. Direct hosting adds no engine pipe IPC. Get-QuietEngine now exposes DirectRequests and MetadataJsonRequests; their sum equals Requests for completed exchanges, including valid rejection replies. These are request-path counters, not serialization byte estimates. A direct rejection may still serialize its diagnostic response.

## Input readiness correction

The initial typed implementation exposed a pre-existing scheduling cost: when the input queue filled, the facade polled output for up to 100 ms even if input capacity became available. A stdin/hash process emits output only after EOF, so faster enqueueing could make the complete workload slower. The first stable typed median was 263.02 ms versus 170.78 ms for local JSON. Those samples remain in the pre-readiness evidence; removing JSON alone did not establish acceleration.

After a rejected write, NextAsync now wakes on either input capacity or available output. Already writable input returns immediately. A closed writer retains the normal bounded output/exit wait. Both pending channel waits are canceled and observed; no unbounded waiter backlog is created. The native PTY transports were not changed.

InputBackpressureCases.cs supplies a synchronized input-only fake: the first write is blocked, every queue slot is filled, a further write is rejected, then the sink consumes all accepted blocks. With stdin already writable and no stdout, the next poll must complete immediately. This is an observable readiness assertion without a timing speed threshold; deadlines only bound defective execution.

## Executed validation

Both full Core/Git suites passed 75 scenarios with zero failures on Windows x64. Each includes 22 successful nested C# cases. Dedicated visible monitors owned both runs and closed after saving their terminal states.

- Stable: PowerShell 7.6.7, .NET 10.0.13, integrated net10.0, engine PID equal to worker PID.
- Preview: PowerShell 7.7.0-preview.5, .NET 11.0.0-rc.1.26425.128, integrated net11.0, engine PID equal to worker PID.
- Both integrated identities report zero protocol input/output bytes.
- Both hosting modes verify an exact 1 MiB + 7 byte duplex copy by independent SHA-256, input byte counts, resize rejection on a pipe, writes after EOF, missing-invocation rejection followed by a usable session, and request-path accounting. Direct bounds reject oversized input blocks and identities.
- Existing suites cover native cancellation, nested calls, failure propagation, framing, timeout, packaged imports and Git behavior.
- The two portable targets and all six native publications built successfully. This local evidence does not establish Linux/ARM64 execution or remote release qualification.

The final frozen source SHA-256 is D581B3406E52BDFAB577619138659386A184EA9EC576D6E96432E6F2211985F8. Integrated assembly digests:

- net10.0: 616B48722E57B5F9AFAF00F1E1D93FDBD7665AB48F42500F1CF7EEA8FD226A2F.
- net11.0: A8F63498B00420AA2A879B875C3FDDAF6580B96E02484D3BC0908345144C0776.

Eight functional implementation/test files match the validated snapshot by SHA-256. All 207 input comparisons across ten build manifests matched the live checkout before copying the 85 built files into its ignored lib directories. Documentation was completed afterward. An initial StrictMode regression in optional dimension access was fixed before these final runs. No package was published and no commit or push was created.

## Comparative samples

Three alternating samples per implementation pass identical 1 MiB input through the existing native hash fixture. Independent byte counts and SHA-256 must match. Medians include native startup, hashing, input acceptance, back-pressure and output drainage; assembly/session startup is excluded. The samples compare local JSON controls with typed controls on the same final engine, not integrated IPC against isolated IPC.

| Host | Local JSON ms | Typed ms | JSON control bytes, before/after |
| --- | ---: | ---: | ---: |
| Stable / .NET 10 | 150.66 | 137.98 | 14,638 / 0 |
| Preview / .NET 11 | 174.55 | 129.24 | 14,638 / 0 |

Control counts vary from 66 to 68 because a full queue requires retrying; both implementations retain back-pressure. Actual protocol pipe bytes are zero in every sample. The JSON-byte count covers control headers/replies only, excluding the explicit 1 MiB input and remaining startup/telemetry metadata. These small workload samples do not establish universal speedups; scheduling, JIT and concurrent machine load affect timings. There is no timing threshold in the suite.

## Retained evidence

artifacts/tests/typed-controls-20261105 contains final/stable and final/preview summaries, logs and before/after source identities. pre-readiness retains the earlier successful runs before the queue wakeup correction. medians.json, identities.json and functional-source-check.json retain the comparisons.

The frozen run tree remains at C:\Users\serard\AppData\Local\Temp\quietcli-controls-98111fe4. The final run directories are artifacts/tests/host-stable-ready and artifacts/tests/host-preview-ready. To reopen saved monitoring output:

```powershell
# Objective: Reopen the saved stable result using the existing read-only monitor.
pwsh -File C:\Users\serard\AppData\Local\Temp\quietcli-controls-98111fe4\scripts\Watch-Tests.ps1 -RunDirectory C:\Users\serard\AppData\Local\Temp\quietcli-controls-98111fe4\artifacts\tests\host-stable-ready
```

For a new run, build with scripts/Build-Workspace.ps1 and use scripts/Invoke-WorkspaceCi.ps1 -SkipBuild -Suite All under each pinned PowerShell host. The launcher opens the required monitor. Restart PowerShell after rebuilding an assembly already loaded into it. Remaining migration candidates are listed in [the boundary review](../powershell-csharp-boundaries.md).
