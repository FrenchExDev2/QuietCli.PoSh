# Core extraction before the Git client - 5 November 2026

This phase was implemented and qualified before changing Git parser code. Both actual Windows hosts and the existing Debian x64 container passed 76 scenarios with zero failures, including 26 nested Core C# cases. No remote ARM64 run or package publication is claimed.

## Implemented boundaries

- CallerMetadata performs recursive detached read-only copies of execution/completeness/diagnostic containers. A synchronous PowerShell adapter handles its own property bags on the caller thread. Known PSObject scalar wrappers are unwrapped without reflecting arbitrary business getters. Cycles fail explicitly. Result.Data never enters this helper.
- LocalMetadataRequest maps only closed startup, telemetry, aggregate-continuation, identity and maintenance fields. Nested schemas reject Data, diagnostic Message fields and invalid primitive types. Integrated requests/replies avoid transport JSON on the ordinary path. Internal raw queries retain their diagnostic wire-compatible interface; error replies stay bounded JSON. SQLite's validated JSON persistence is a separate representation.
- Native launch and aggregate selections share validation/state transitions between direct and isolated hosts. Adaptation occurs before the first asynchronous gate wait so a queued request cannot invoke PowerShell from a worker thread.
- BoundedYaml uses pinned YamlDotNet 18.1.0 on the already normalized graph. It never projects arbitrary Data. Explicit string quoting preserves strings that look like numbers, booleans or null. Output text formatting/escape spelling belongs to the YAML emitter; independent parsing verifies decoded Unicode, scalar identities and nested/empty collections. Actual emitted UTF-8 bytes still determine delivery budgets and measurements.
- YamlDotNet is loaded in a private AssemblyLoadContext so user modules can own other versions independently. The DLL, package provenance, pinned repository commit and both upstream license files are recorded under resources/dependencies.lock.json and third_party/yamldotnet. There is no dependency on an installed PowerShell YAML module.
- ProbeIdentity builds a collision-safe, canonical executable/environment cache key without JSON. It keeps file path, length and modification time as the existing file identity policy; it does not invent a content-integrity guarantee. Windows environment names follow effective case-insensitive overwrite behavior. Version and shape predicates remain caller-owned handler scriptblocks. Repeated resolution requires one probe per 200 calls.

PowerShell retains parameter binding, callbacks, nested invocation coordination, generic business projection and scaffold/file orchestration. Scaffolding is infrequent authoring work; no measured hot loop justifies moving its PowerShell templates into the execution engine. CI/native bootstrap remains independent of product assemblies.

## Reproducible local evidence

artifacts/tests/core-migration-20261105 retains stable-final, preview-final and linux-final summaries, before/after source identities and raw measurement samples. The frozen tree is C:\Users\serard\AppData\Local\Temp\quietcli-core-migration-d42a9cbf. Final Windows runs are artifacts/tests/core-stable-final and core-preview-final. The final Linux run is artifacts/containers/debian-20261105-073544-f95627.

- Windows stable: PowerShell 7.6.7 / .NET 10.0.13, integrated net10.0.
- Windows preview: PowerShell 7.7.0-preview.5 / .NET 11.0.0-rc.1.26425.128, integrated net11.0.
- Debian x64 image: PowerShell 7.7.0-preview.5 / .NET 11.0.0-rc.3.26522.148, integrated net11.0.

Dedicated visible monitors tracked every local run and closed after saved terminal reports. Container execution used an existing image with --pull=never and --network none. Its product staging now includes .github/workflows because the matrix assertion reads those files; native-mutation source-only staging was unchanged.

All six native publications and both portable targets compiled. Runtime execution on ARM64 and musl remains the independent CI/release matrix's responsibility. The separate native PTY work was not changed.

## Mechanism samples

Medians in milliseconds from three alternating samples. Each sample has independently checked counts; timing thresholds are not test assertions.

| Workload | Calls | Windows stable PowerShell/JSON | Windows stable C#/typed |
| --- | ---: | ---: | ---: |
| Metadata snapshots | 20 | 180.33 | 5.11 |
| Normalized YAML emission | 20 | 293.99 | 134.76 |
| Local hello metadata dispatch | 128 | 46.91 | 11.75 |
| Cached registry resolution | 200 | 201.58 | 61.98 |

Snapshots/YAML use synthetic graphs and exclude native execution, callbacks and IPC. Metadata dispatch compares identical engine identity calls; it is not native-process throughput. Registry resolution includes file stat, cache identity and predicates but uses a synthetic version probe. Each implementation performs exactly one such probe per sample. Host scheduling, JIT and concurrent machine load affect timings. These samples do not establish universal CLI speedups.

The old functions are retained only in Core.Tests/CoreMigration.Baseline.ps1. C# cases independently verify snapshot detachment/read-only behavior/cycles, standard YAML semantics and dependency isolation, safe typed persistence/rejection recovery, and canonical cache identity/file invalidation.

Official dependency sources: [YamlDotNet](https://github.com/aaubry/YamlDotNet), [NuGet 18.1.0](https://www.nuget.org/packages/YamlDotNet/18.1.0), [pinned upstream license](https://github.com/aaubry/YamlDotNet/blob/748334a8fa7c227740018b284b71ad95cc6b7fc7/LICENSE.txt).
