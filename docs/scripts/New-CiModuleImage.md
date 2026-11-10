# New-CiModuleImage.ps1

`-ContainerRuntime podman|docker` is optional; empty discovers Docker then Podman and forwards the resolved engine consistently to Core image
preparation, the local Core tag and the derived build. GitHub selects `docker` explicitly. The
ephemeral registry credential is retained in memory across the Core call, which removes it from
the process environment, then restored for the derived builder and cleared from the temporary
variable. This prevents a missing derived image from losing its publication credential between
the two builds. No credential value is logged or placed in a build argument.

## Purpose

Builds a Core-consumer module's own derived Docker/Podman CI test image (for example, the `Git` module's image) layered on top of Core's already-verified, fingerprinted base image, without ever reading Core's internals beyond its resolved plan. This lets each consumer module (currently `Git`; more could follow the same contract) own its own `Containerfile` fragment, locks, and fetch script while still building `FROM` a trusted, reproducible Core image. It is invoked directly from `.github/workflows/ci.yml` (lines 256, 314) with `-Module Git`, and is the second half of the two-stage image pipeline whose first half is `New-CiImage.ps1` (called internally at line 40).

## Usage

Parameters:
- `-Module [string]` (Mandatory) — Core-consumer module name, matching the `FrenchExDev2.QuietCli.<Module>.PoSh` directory (e.g. `'Git'`).
- `-RuntimeIdentifier [string]` (Mandatory, `ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')`).
- `-WorkspaceRoot [string]` (default: parent of `$PSScriptRoot`).
- `-RegistryCache [switch]` — read the GHCR cache (for both Core and the module) with the optional `QUIETCLI_REGISTRY_TOKEN`.
- `-PublishCache [switch]` — publish a missing *module* cache entry only; Core's own cache publication is explicitly stated to remain the exclusive responsibility of the `linux-images` job calling `New-CiImage.ps1` directly (doc comment, lines 24-25).
- `-PlanOnly [switch]` — resolve inputs offline; returns the plan object before Core is built/pulled or engine discovery/invocation occurs.

Example (from `ci.yml`):
```powershell
./scripts/New-CiModuleImage.ps1 -Module Git -RuntimeIdentifier $env:EXPECTED_RID -RegistryCache -PublishCache
```

## Dependencies

- Dot-sources `Common.ps1` and `CiImages.ps1` (line 30).
- Requires the module's own contract script to exist at the exact relative path `<moduleRoot>/ci/Get-CiImageArguments.ps1` (line 32-34; throws `CiModuleContractMissing` otherwise) — this script is *invoked directly*, not dot-sourced (per the `.DESCRIPTION`, lines 11-12), and must return an object with `.InputPaths`, `.Containerfile`, `.Arguments`.
- Internally calls `New-CiImage.ps1` (line 40) to resolve/build Core's own image first — a script-to-script dependency within the same `scripts/` folder.
- Shells out to the selected engine tag command via `Invoke-WorkspaceNative` (line 44) to create a local `FROM`-able tag keyed by Core's verified content fingerprint (`$core.Fingerprint`, line 43) — necessary because, per the inline comment (lines 41-42), "a bare image ID cannot be a Dockerfile FROM target."
- Transitively depends on whatever `Invoke-QuietCiImageBuild` shells out to (Docker/Podman build/pull, GHCR network access when caching flags are set).
- Filesystem assumption: `<WorkspaceRoot>/<moduleRoot>/.github/containers` exists as the build context for the module's own image (line 46).

## Side effects

- Builds/pulls Core's image as a side effect of calling `New-CiImage.ps1` (line 40) — i.e. this script can trigger a full Core image build even if the caller only wanted the module image, whenever Core's own image isn't already cached/present.
- Tags a local image (selected engine tag command) under `localhost/quietcli2-ci-core-<platform>-<arch>:<fingerprint>` — a selected engine image-store mutation.
- Invokes the module's own `ci/Get-CiImageArguments.ps1` script (line 36), which runs arbitrary PowerShell from the module's own repository tree — this is an intentional per-module extensibility point, not sandboxed.
- Builds/pulls the module's own derived image, and with `-PublishCache`, pushes a module cache entry to GHCR.

## Findings

- No bug found in the Core-fingerprint-to-tag flow: keying the local `FROM` tag on `$core.Fingerprint` (line 43) rather than a mutable tag like `:latest` is the right call for reproducibility — it guarantees the module's Containerfile builds against the exact Core image content it resolved, whether that arrived via a fresh local build or a GHCR pull-by-digest (per the inline comment).
- DESIGN: `$moduleScript=Join-Path $WorkspaceRoot $moduleContractPath` (line 33) is invoked with `& $moduleScript -WorkspaceRoot $WorkspaceRoot -Platform $core.Platform` (line 36) — this executes a script that lives inside the *consumer module's own directory tree* with no integrity check (no hash pinning, no signature) before execution, unlike the Profiler/dotnet-trace packages in `RunToolCache.psm1` which are checksum-verified before use. Since `ci/Get-CiImageArguments.ps1` is part of the same monorepo (not a third-party download), this is a reasonable trust boundary for this specific codebase, but it is worth noting as a difference in trust model from the rest of the `scripts/lib/` tooling, which is otherwise careful about verifying anything executed.
- CONVENTION: line 1's comment ("Objectif : Construire l'image CI d'un module consommateur de Core, par-dessus l'image Core deja verifiee.") is in French — same recurring violation of the English-only code/comments rule seen in `New-CiImage.ps1` and `Monitor.Time.ps1`.
- No input-validation gap found: `-Module` has no `ValidateSet`/pattern restriction (unlike `-RuntimeIdentifier`), so a typo'd module name produces a late, clear `CiModuleContractMissing` throw (line 34) rather than a cryptic failure deeper in the build — acceptable, though a `ValidatePattern` matching the `FrenchExDev2.QuietCli.<Module>.PoSh` directory-name convention would surface a bad `-Module` value slightly earlier with a more specific message.
- Testability: like `New-CiImage.ps1`, no dedicated invoke-and-assert Pester test for this script was found; `CiImages.Tests.ps1` references file paths including this script's module-specific counterparts (the Git module's own `ci/Get-CiImageArguments.ps1` and lock files) but does not appear to execute `New-CiModuleImage.ps1` end-to-end in the portion reviewed.

## Verdict

Architecturally sound (the fingerprint-keyed local tag is exactly the right trick for a reproducible two-stage container build), with the same minor English-comment fix needed as its sibling `New-CiImage.ps1`; the highest-priority improvement would be additional end-to-end execution beyond the existing mocked Docker/Podman adapter and credential-lifecycle tests asserting that a missing `ci/Get-CiImageArguments.ps1` fails with `CiModuleContractMissing` and that the Core tag is correctly keyed by fingerprint.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Builds a Core-consumer module's own derived Podman image, from the module's own Containerfile and locks.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
