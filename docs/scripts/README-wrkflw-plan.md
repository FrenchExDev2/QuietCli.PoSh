# Local workflows with wrkflw: scripts to create

## Delivered integration

[`Install-DevelopmentWorkstation.ps1`](Install-DevelopmentWorkstation.md) includes the `Workflows`
component. It installs **wrkflw 0.8.0** from checksum-pinned official archives and adds the verified
executable directory to its generated activation script. `-CheckOnly` and `-WhatIf` remain offline,
read-only controls; `-SkipWorkflows` explicitly excludes this component. No Rust/Cargo installation,
profile modification or workflow execution is part of workstation setup.

[`Invoke-LocalWorkflow.ps1`](Invoke-LocalWorkflow.md) provides a focused, monitored local
validation/execution entry point with explicit job/runtime selection and `-WhatIf`. The real
`companions-ci.yml` reaches the reusable `ci.yml`, where wrkflw 0.8.0 rejects expression-valued matrices
before executing jobs. This is an explicit local-run qualification gap, not a GitHub YAML error.

The other helpers below remain **planned, not implemented**. They are not entries in the generated
[implemented scripts index](README.md). Their eventual implementation must include the mirrored
script documentation, companion tests and documentation-sync gates in the same change.

## Verified upstream contract

Reference: [release v0.8.0](https://github.com/bahdotsh/wrkflw/releases/tag/v0.8.0),
[tagged CLI source](https://github.com/bahdotsh/wrkflw/blob/v0.8.0/crates/wrkflw/src/main.rs),
[tagged README](https://github.com/bahdotsh/wrkflw/blob/v0.8.0/README.md).
The official Windows x64 archive's SHA-256, version and installed command help were checked on
9 November 2026. This is tool-interface evidence, not workflow or cross-platform qualification.

- `list --jobs` lists workflows and jobs; `validate [paths...]` checks workflow definitions.
- `run --runtime podman --job <id> <path>` executes a selected workflow/job. Docker is the upstream
  default; the repository wrapper accepts explicit Docker, Podman or emulation selection.
- `run --event pull_request --base-branch develop --diff <path>` supplies a trigger context.
  Keep strict filtering enabled. An event requires changed-file context, and pull requests require
  the target/base branch. Activity types must be explicit when a workflow filters `types:`.
- `watch` reruns workflows; `tui` opens the interactive terminal UI.
- **0.8.0 has no `plan`, general `--format json`, MCP, or `run --jobs` option.** Use `list --jobs`.
  The moving `main` README describes additional capabilities; do not expose them as released APIs.
- Emulation executes host commands; it is not a dry run. `validate` is not a full event/job plan.
  A wrapper's `-WhatIf` previews the selected native argument vector without executing it; it must
  not claim that conditions, outputs or all trigger decisions have been evaluated.

## Implementation backlog

| Priority | Planned script | Contract and parameters | Native operation / reusable surface |
| --- | --- | --- | --- |
| 1 | `Get-LocalWorkflow.ps1` | `-WorkspaceRoot`, `-Jobs`; return the inspected scope, executable version and bounded listing without running workflow steps | `list` or `list --jobs` |
| 1 | `Test-LocalWorkflow.ps1` | `-WorkspaceRoot`, `-Path`; validate selected definitions; preserve exit code 1 for invalid definitions and 2 for usage errors | `validate [paths...]`; never use `--no-exit-code` |
| 1, partial | [`Invoke-LocalWorkflow.ps1`](Invoke-LocalWorkflow.md) | Implemented: `-WrkflwPath`, `-Workflow`, `-Mode Validate\|Run`, explicit `-Job` for execution, `-Runtime docker\|podman\|emulation`, `-TimeoutSeconds`, `-RunDirectory`, `-WhatIf`/`-Confirm`. Trigger/diff options remain backlog. | Exact validation/selected-job vectors, saved exit state and shared visible monitor; no implicit installation or publication |
| 2 | `Watch-LocalWorkflow.ps1` | `-Path`, runtime and trigger options; debounce and concurrency limits; explicit cancellation and saved terminal outcomes | `watch`; extend shared run/monitor primitives rather than writing another monitor |
| 2 | `Show-LocalWorkflow.ps1` | Open the selected checkout's interactive UI with an explicit runtime; keep project/task/workspace identity visible | `tui --runtime podman`; requires an interactive terminal, not a line-output parser |

Implement the first three as one coherent slice, then add watch/TUI only after execution and
cancellation are independently tested. Extend [`Invoke-RemoteWorkflow.ps1`](Invoke-RemoteWorkflow.md)
and [`Watch-GitHubRun.ps1`](Watch-GitHubRun.md) for remote GitHub work; do not duplicate them with new
`wrkflw trigger` wrappers. Installing `act`, actionlint or zizmor is a separate toolchain decision;
this integration selects wrkflw only.

## Shared implementation requirements

1. Resolve the activated/owned native executable and verify its exact supported version before
   interpreting tool-specific output. No install, download, update or runtime fallback during use.
2. These scripts are repository CI orchestration: use engine-independent `scripts/lib/Ci.Process.psm1`,
   `Common.ps1`, `ReportPaths.ps1` and the existing run/monitor helpers. Do not introduce an engine
   dependency into bootstrap or CI. Agent-native analysis still uses `quiet` with explicit callbacks.
   A later reusable QuietCli business handler belongs in its own companion module with independent
   assertions, not in Core or a collection of ad hoc executable branches.
3. Keep selection, process execution and output interpretation separate. 0.8.0 has text output;
   do not invent JSON schemas or derive success solely from a human-readable word. Preserve the
   real exit state, output completeness and unknown counters. Test any parser against fixtures.
4. Put the ShouldProcess boundary before every executable launch that can run workflow steps.
   `-WhatIf` starts no workflow process, creates no run directories and pulls no image. It returns
   the intended tool, path, arguments, runtime and qualification limitations.
5. An execution that runs tests requires a background worker and a dedicated visible PowerShell
   monitor for its whole lifetime, including terminal success, failure, crash, timeout and cancellation.
   Reuse shared monitoring with project/task/workspace headings, dynamic framing and automatic closure.
   Save reports under `Get-QuietReportRoot`, outside the checkout. The upstream TUI alone is not the
   repository's required test monitor.
6. Treat `run` and `watch` as real workflow execution: do not implicitly select release/publication
   workflows, supply credentials, dispatch remotely, install hooks or change profiles. Pass a specific
   workflow/job and surface required secrets as missing, never as a successful skipped qualification.

## Platform and qualification boundaries

The reviewed binary set covers `win-x64`, `linux-x64`, `linux-arm64` and `linux-musl-x64`.
Windows ARM64 and Alpine ARM64 have no native 0.8.0 release artifact in this lock. The installer
reports `Unsupported`; a mutating run fails before provisioning other components. Use
`-SkipWorkflows` to prepare those hosts without wrkflw. No x64 substitution or source build occurs.

Installing a native wrkflw binary does not establish the OS/architecture of jobs it launches.
Windows/macOS runner fidelity, reusable workflows, permissions, secrets, service containers and
repository-specific CI images must each be qualified before any local result is used as evidence.
The existing GitHub release matrix and `Assert-QualificationGate.ps1` remain authoritative.

Acceptance tests belong in `FrenchExDev2.QuietCli.Core.Tests.PoSh`: generated argument/path/Unicode
properties; malformed trigger contexts and workflow corpus; deterministic reproduction seeds;
targeted mutations of selection, ShouldProcess, exit/completeness handling and cancellation.
Add an owned minimal Linux workflow for a Podman smoke, then independently exercise Windows-specific
jobs. Report properties, fuzzing, mutants, real workflow execution and platform gaps separately.

## Findings and verdict

- **Version gap:** `scripts/lib/DevelopmentWorkstation.psm1:110` selects reviewed released artifacts;
  the tagged CLI has no planner. A wrapper must not implement `-WhatIf` by executing emulation.
- **Platform gap:** `scripts/lib/DevelopmentWorkstation.psm1:298` reports missing native artifacts;
  `:693` blocks mutating setup before other component effects. Missing platforms are not passes.
- **Coverage boundary:** `FrenchExDev2.QuietCli.Core.Tests.PoSh/DevelopmentWorkstation.Tests.ps1:1`
  covers installer properties, malformed identities and targeted mutations. It does not qualify the
  planned helpers or actual repository workflow execution.

Verdict: workstation provisioning is implemented; the five usage helpers remain an explicit backlog.
Start with listing, validation and bounded execution. Add a semantic plan only after a reviewed
released tool version actually provides that contract.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
