# Core, then Git, with PTY integration — 5 November 2026

Core was implemented and qualified first; see [the Core-only audit](2026-11-05-core-before-git.md). Git-owned parsing and argument binding were migrated afterwards. Neither phase introduces Git grammar into Core.

## Delivered boundaries

Core now performs detached metadata snapshots, closed integrated metadata dispatch, normalized YAML emission through private YamlDotNet, and canonical probe-cache identity in C#. Business Data never crosses the metadata boundary. PowerShell retains caller callbacks, command orchestration, generic business projection and authoring templates. Persistence JSON and bounded diagnostic/internal-query JSON are separate from ordinary integrated dispatch.

Git owns a BCL-only compiled companion for both net10.0 and net11.0. Its loader chooses the actual CLR and verifies assembly framework and digest. UTF-8/status/patch framing, commit/tree/worktree/ref mapping and argument binding run locally in the caller, without per-record engine IPC. Command selection, version qualification and invocation ownership remain in the Git module. This migration does not qualify previously unsupported Git commands or variants.

## Functional qualification

| Environment | Integrated target | Top-level scenarios | Nested Core C# cases | Nested Git C# cases |
| --- | --- | ---: | ---: | ---: |
| Windows x64, PowerShell 7.6.7 / .NET 10.0.13 | net10.0 | 78 / 78 | 26 | 15 |
| Windows x64, PowerShell 7.7.0-preview.5 / .NET 11 RC1 | net11.0 | 78 / 78 | 26 | 15 |
| Debian x64, PowerShell 7.7.0-preview.5 / .NET 11 RC3 | net11.0 | 78 / 78 | 26 | 15 |

Each run reported zero failures, engine PID equal to worker PID, and zero protocol input/output bytes. Dedicated visible monitoring windows closed after terminal reports were saved. All six engine runtime publications, both portable engine targets and both Git companion targets compiled. The full ARM64 functional and musl functional runtime matrix was not executed locally.

Evidence is retained under `artifacts/tests/core-then-git-20261105`: stable, preview and linux reports, metrics.json, identities.json, source-check.json and pty-integration.json. Functional source and shipped libraries were checked against the validated frozen checkout before delivery. Documentation and agent-policy edits afterwards do not change those functional inputs.

The Windows frozen source SHA-256 is `12B98C1FAF3BAFC3724F85F3BAE25CAD65EAB8C6E87C002EB0D68970E7C16039`; the Linux staged subset is `90AF4B4D9862EBB5FF50F24F7642A00411BDF03FBFCAA1452E44A09ABE55B67D`. Different staging scopes explain the source digests. Engine DLL SHA-256 values are `742A95A84171D20175AFBF1E8EF165138FBDAD823DBD08B23E7E5F4A756659F5` (net10.0) and `8B85C476C35355928F4021DE94BA62F371B6E60FB5B13A43CCCB464F5D9F794F` (net11.0). Windows Preview and Debian used the same net11.0 DLL.

## Mechanism measurements

Windows stable medians in milliseconds from three alternating samples, with independently checked result counts:

| Workload | PowerShell baseline | Caller-local C# |
| --- | ---: | ---: |
| 100 Git argument bindings | 145.04 | 12.88 |
| 2,000 Git patch lines | 112.68 | 21.21 |
| 2,000 Git status records | 518.42 | 24.93 |

These synthetic samples isolate parsing/binding mechanisms. They do not establish end-to-end Git speedups or timing guarantees. Core measurements and their limitations are recorded in the earlier audit. No timing threshold is used as a functional assertion.

## PTY integration

The user-authorized fixed `quietcli-pty.c`, ten native test source files, four shipped PTY binaries, dependency lock and build/worker scripts already matched the final validated checkout exactly (18 checked files). No additional C edit or redundant functional rerun was required. Native C SHA-256: `85291462D03DBD76ECBE23E03D2504B0AF2D3EE6B33793A51F9A0832E02C4EF3`.

All three native campaign bootstrap receipts name that same C digest. Their summaries pass the mandatory qualification guard: 43 assertions, six property groups, at least 20,000 executed fuzz inputs, and 31/31 killed targeted mutants per campaign. Independence receipts contain zero product build files, loaded product modules and forbidden AI command calls. These campaigns cover Alpine/musl with LLVM-main runtimes, Alpine/musl with packaged runtimes, and Debian/glibc with Clang 14 compatibility. See [the native stream audit](2026-11-05-pty-streams.md) for provenance, sanitizer constraints, retained reports and limitations. ARM64 native qualification remains unexecuted locally; the mutation catalogue is not exhaustive coverage.

The new language-independent property/fuzz/mutation policy is recorded in both workspace and repository AGENTS.md. The native results above do not establish those campaigns for the migrated PowerShell/C# components; their listed functional and comparative tests must not be presented as equivalent evidence. Any missing language/component campaign remains an explicit qualification gap under that policy.

No commit, push or publication was performed.
