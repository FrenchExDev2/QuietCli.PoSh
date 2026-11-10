# DevelopmentWorkstation.psm1

## Purpose

Detect native hosts, resolve reviewed toolchain artifacts, inspect component readiness and provision
approved changes. The public entry point is
[Install-DevelopmentWorkstation.ps1](../Install-DevelopmentWorkstation.md). The module also supplies
shared Git/artifact operations to `ModuleWorkstation.psm1` and stays independent of QuietCli's engine.

## Usage and contracts

Use the public installer for normal setup. Its helpers separate host policy, artifact identity,
inventory, action selection, execution and activation:

- `Get-DevelopmentHost` validates Windows/Linux x64/ARM64 and supported distribution versions.
- `Get-DevelopmentSpecification` reads the SDK/Git/Zig locks and the workstation lock. Its `Wrkflw`
  property contains `Version`, `Source` and the selected `Artifact`, or a null artifact for a missing
  native release. All four reviewed wrkflw artifact identities must be valid before selection.
- `New-DevelopmentPlan` requires an absolute install root, validates the Podman machine name and
  accepts `Editor`, `Containers`, `Native`, `Profilers`, `Workflows` exclusions.
- `Get-DevelopmentInventory` returns component states. `Workflows` accepts only the exact pinned
  `wrkflw --version` banner; missing upstream architecture support is `Unsupported`, not `Ready`.
- `Get-DevelopmentActions` selects every component that is neither ready nor explicitly excluded.
- `Invoke-DevelopmentProvisioning` accepts a `ShouldApply` callback and `-CheckOnly`. Approved work
  re-probes actual tools before reporting `Ready`; unverifiable installation is `Failed`.
- `Write-DevelopmentActivation` writes session activation without changing a profile. The activated
  PATH includes the discovered wrkflw directory and deduplicates it when activated again.

Internal wrkflw helpers are `Get-DevelopmentWrkflwSpecification`, `Test-DevelopmentWrkflwVersion`
and `Install-DevelopmentWrkflw`; they are not new public module APIs. Installation reuses the shared
checksum/download/extraction helpers. No Cargo or fallback runtime is involved.

## Dependencies

- `../Ci.Process.ps1`: engine-independent process execution with explicit argument vectors.
- `global.json`, `build/development-workstation.lock.json`, `build/ci-images.lock.json`,
  `build/zig.lock.json` and Git metadata locks.
- `RunToolCache.psm1`, `Initialize-Profilers.ps1`, and editor-extension synchronization.
- Host-specific native tools: package managers, Git, tar, Podman and Windows WSL/WinGet as selected.
- wrkflw 0.8.0 official release archives: `win-x64`, `linux-x64`, `linux-arm64`, `linux-musl-x64`.
  Windows ARM64 and musl ARM64 have no reviewed native artifact; their workflow component must
  be excluded explicitly. Binary availability is not product/workflow qualification.

## Side effects

The inventory phase only probes local state. Approved provisioning can download/extract tools,
install system packages, prepare Podman/WSL and write `Activate-DevelopmentEnvironment.ps1`.
`Get-DevelopmentArchive` verifies cached and downloaded content before extraction; official wrkflw
URLs are constrained to versioned release asset paths. The archive lock records SHA-256 from GitHub's
release metadata; a checksum establishes content identity, not publisher trust or absence of flaws.

wrkflw installation writes only beneath the selected tool root, preserves system copies and does not
run a workflow, start its TUI, fetch actions, dispatch a remote run, register MCP, or install hooks.
`CheckOnly` / rejected ShouldProcess return before mutations. An unsupported wrkflw artifact blocks
approved provisioning before the first component effect, avoiding a partially prepared workstation.

## Findings

- **Artifact policy:** `scripts/lib/DevelopmentWorkstation.psm1:110` rejects malformed versions,
  provenance URLs, duplicate/unknown RIDs, incomplete sets, wrong asset URLs and malformed digests.
  This fixed release matrix must be deliberately extended when new native artifacts are reviewed.
- **Reuse boundary:** `scripts/lib/DevelopmentWorkstation.psm1:298` probes only supported native
  wrkflw artifacts, and `:530` reuses verified archive handling. Existing exact-version executables
  are retained by their banner; their content hash is not independently attested by that probe.
- **Qualification gap:** `scripts/lib/DevelopmentWorkstation.psm1:310` establishes tool version only.
  It does not prove runner OS fidelity, event semantics, secret/permission behavior or any repository
  workflow. The [helper backlog](../README-wrkflw-plan.md) records the remaining contracts.
- **Maintainability:** provisioning still combines host/package policy and infrastructure in one
  module. wrkflw reuses existing download/process/activation primitives; further tools should not
  introduce duplicated installers or executable-specific parsing in Core.
- **Diagnostics:** `scripts/lib/DevelopmentWorkstation.psm1:717` retains the exception message in
  a failed report, but not its stack. Detailed installation stack diagnostics remain a follow-up.
- **Coverage:** `FrenchExDev2.QuietCli.Core.Tests.PoSh/DevelopmentWorkstation.Tests.ps1:1` covers
  installer properties, hostile inputs and targeted mutations. Native architecture/platform runs,
  real package-manager installation and local workflow execution are distinct evidence.

## Verdict

wrkflw follows the existing toolchain pattern: reviewed native artifacts, bounded version probes,
explicit exclusions and ShouldProcess-aware provisioning followed by independent verification.
The missing native ARM64 artifacts and workflow-semantic qualification remain explicit gaps.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Detects a native Windows/Linux target without evaluating os-release as executable code.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
