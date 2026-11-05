# Second C# extraction validation - 5 November 2026

Strict incremental UTF-8 decoding/text framing and telemetry aggregation now run in C#. Text framing stays in the caller process in both engine modes. Gain aggregation consumes safe SQLite metadata and returns only summary counters and aggregate group pages. See [the boundary review](../powershell-csharp-boundaries.md) for remaining candidates and behavior constraints.

## Executed validation

Both complete Core/Git runs used a frozen source copy on Windows x64 with the normal profile and dedicated visible monitors. Each run passed 73 scenarios with zero failures, including the nested C# suite's 21 cases. The suite verifies both engine modes, packaged imports outside sources, UTF-8 fragmentation, record limits, EOF, nested callbacks, stdin drainage, cancellation, aggregate paging, exact event budgets and report cleanup.

- Stable: PowerShell 7.6.7, .NET 10.0.13, integrated target .NETCoreApp,Version=v10.0.
- Preview: PowerShell 7.7.0-preview.5, .NET 11.0.0-rc.1.26425.128, integrated target .NETCoreApp,Version=v11.0.
- Both integrated identities share the worker PID and report zero protocol input/output bytes.
- Frozen repository source SHA-256: 5A3BEB6B841CE583C8A829BC68133F71F06A4C22F10BE9B6793282E10A2F3A52.
- Integrated net10 assembly SHA-256: 8F301973A9768CC24FF5C2E550C5FE3790E55994AD22D2B1EC4B2ADCA49CE964.
- Portable net11 assembly SHA-256: F377D16FBCE6792F78C32780B19E7E934B27499054AEED22A1CF8D2A9967B258.

All six runtime publications and the two portable targets built successfully before validation. Building these publications does not establish execution on Linux or ARM64. The separate PTY task was not modified; later changes in that task are outside this frozen evidence. The twelve functional implementation/test files in this pass were compared by SHA-256 with the validated snapshot and matched. Documentation was completed afterward.

## Comparative samples

Medians in milliseconds, three alternating samples per implementation/workload. Each implementation must satisfy independently specified counts. The PowerShell aggregation baseline is the former implementation retained only in the test project.

| Host | Workload | PowerShell ms | C# ms |
| --- | --- | ---: | ---: |
| Stable / .NET 10 | Gain, integrated | 109.36 | 52.91 |
| Stable / .NET 10 | Gain, isolated | 127.44 | 43.20 |
| Stable / .NET 10 | 4,096 short records | 107.75 | 7.58 |
| Stable / .NET 10 | One long fragmented record | 431.21 | 9.70 |
| Preview / .NET 11 | Gain, integrated | 114.90 | 27.79 |
| Preview / .NET 11 | Gain, isolated | 132.44 | 36.47 |
| Preview / .NET 11 | 4,096 short records | 123.09 | 7.94 |
| Preview / .NET 11 | One long fragmented record | 414.03 | 10.31 |

Gain samples cover 512 synthetic closed telemetry events grouped into two groups, including database projection and report delivery. Isolated traffic was exactly 345,432 bytes per baseline sample versus 1,408-1,691 bytes per compiled sample, depending on progress continuations. Integrated traffic is zero for both implementations; its gain concerns local processing and allocations, not IPC elimination.

Text samples process 262,144 decoded characters, either 4,096 short records or a 256 KiB unfinished record delivered in 1 KiB pieces. They exclude decoder time, business callbacks, native producer startup and IPC. The change avoids repeated suffix copies and growing-fragment scans. These small synthetic samples demonstrate mechanisms on this machine, not universal CLI acceleration. Scheduling, JIT and concurrent machine load affect timings; the tests do not impose unstable timing thresholds.

Unknown root delivery sizes remain null. Reduction requires delivery/root identities to match as well as complete source/analysis evidence. Exact MaxEvents completeness uses a lookahead event. A PowerShell null-to-empty-string binding regression found during validation was corrected with Language.NullString.Value; the complete suites above passed after that correction.

## Retained evidence and reproduction

Durable local evidence lives under artifacts/tests/csharp-pass2-20261105: stable/summary.json and preview/summary.json retain every scenario and raw timing sample; source-identity*.json retain before/after fingerprints; medians.json and functional-source-check.json retain the comparison. No package was published.

The frozen run tree remains at C:\Users\serard\AppData\Local\Temp\quietcli-csharp-pass2-20443dd0. Run directories are artifacts/tests/host-stable-fixed and artifacts/tests/host-preview-fixed. The existing read-only monitor can reopen saved results:

```powershell
# Objective: Reopen the saved stable test summary using the existing monitor.
pwsh -File C:\Users\serard\AppData\Local\Temp\quietcli-csharp-pass2-20443dd0\scripts\Watch-Tests.ps1 -RunDirectory C:\Users\serard\AppData\Local\Temp\quietcli-csharp-pass2-20443dd0\artifacts\tests\host-stable-fixed
```

To reproduce against a new checkout, build with scripts/Build-Workspace.ps1 and use the normal scripts/Invoke-WorkspaceCi.ps1 -SkipBuild -Suite All launcher under each pinned host. The launcher owns the required visible monitor. Do not reuse a running PowerShell process after rebuilding an assembly it has loaded. Remote matrix/release qualification remains separate.
