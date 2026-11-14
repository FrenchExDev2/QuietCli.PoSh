# New-CoreEvidenceBundle.ps1

## Purpose and usage

Copies allowed report types into an integrity-checked evidence tree, records exact revision/run identity and exposes missing required profiles as gaps.

```powershell
./scripts/New-CoreEvidenceBundle.ps1 -ReportRoot ./artifacts/tests -OutputDirectory ./artifacts/evidence -Revision $env:GITHUB_SHA -RequireProfiling
```

ReportRoot is the owned test/container report tree. OutputDirectory must be outside it. Revision is the workflow source identity. RequireProfiling rejects absent, incomplete or modified mandatory PowerShell/CLR evidence. Workflows select this from declared Core scope, not from a Git-only string comparison.

## Dependencies and side effects

Loads Common; uses filesystem streams, literal-path byte/hash checks and JSON, without network/native processes. Copies JSON, traces, logs, text, XML and CSV while excluding staged workspace, Git internals, tool/build/library trees and reparse points. Hidden evidence files remain included and hash-checked. WhatIf returns before directories or copies.

The manifest records file paths, bytes, SHA-256, revision, repository, run/attempt, runner identity and gaps. Profiling validation checks pinned collector versions, line/speedscope files and trace hashes. Process hosting requires both owned target collectors; integrated hosting requires one. Copy/link/read failures remain explicit and fail collection. Required profiling gaps fail after saving the manifest.

Only the prepared evidence tree is uploaded, with hidden files explicitly enabled there. This is distinct from the bounded redacted failure exporter and tooling's separate failed-fixture artifact.

## Critical review and verdict

`scripts/New-CoreEvidenceBundle.ps1:18` enforces a separate output tree; `:28` rejects links and prunes staged/build inputs. Evidence.Tests includes Unicode, bracketed Gallery XML and hidden-file byte/hash fixtures, missing/modified profiles and no-write previews. SHA-256 detects changes but does not authenticate the manifest author; exact GitHub artifact/run identity remains a separate requirement. See [performance rendering](New-CorePerformanceReport.md).



<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Copies bounded report types into a CI evidence artifact with revision/run identity and SHA-256 checksums.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
