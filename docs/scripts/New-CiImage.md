# New-CiImage.ps1

## Purpose

Builds (or reuses from a GHCR cache) the native multi-stage test container image for QuietCli Core, for one specific Linux runtime identifier, and governs when that cache may be published — only from the upstream `main` push/manual workflow, never from pull requests, to prevent an untrusted PR from poisoning the shared build cache. This is the entry point the CI pipeline uses to get a verified, content-fingerprinted base image before running Core's own Linux test matrix; it is called directly from `.github/workflows/ci.yml` (lines 226, 312) and `.github/workflows/quietcli2-readytorun.yml` (line 121), and is the dependency `New-CiModuleImage.ps1` resolves first before layering a module-specific image on top (line 35 of that script).

## Usage

Parameters:
- `-RuntimeIdentifier [string]` (Mandatory, `ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')`) — native Linux RID selected by the GitHub runner matrix.
- `-WorkspaceRoot [string]` (default: parent of `$PSScriptRoot`, i.e. the module root) — QuietCli2 monorepo root.
- `-RegistryCache [switch]` — read the GHCR cache, optionally using the ephemeral `QUIETCLI_REGISTRY_TOKEN` credential.
- `-PublishCache [switch]` — publish a missing cache entry; restricted (per the script's own doc comment) to the upstream main push/manual workflow.
- `-PlanOnly [switch]` — resolve inputs offline without executing a binary or reading credentials; returns the plan object and exits before any build/pull.

Example (from `ci.yml`):
```powershell
./scripts/New-CiImage.ps1 -RuntimeIdentifier $env:EXPECTED_RID -RegistryCache -PublishCache
```
Plan-only / offline dry run:
```powershell
$plan = ./scripts/New-CiImage.ps1 -RuntimeIdentifier linux-musl-arm64 -PlanOnly
```

## Dependencies

- Dot-sources `Common.ps1` and `CiImages.ps1` (both in `scripts/`, line 18) — all the real logic (`Get-QuietCiImagePlan`, `Invoke-QuietCiImageBuild`) lives in `CiImages.ps1`; this file is a thin CLI parameter-binding wrapper.
- Transitively depends on whatever `Invoke-QuietCiImageBuild` shells out to — almost certainly `podman build`/`podman pull` given the rest of the `scripts/` ecosystem's exclusive use of Podman, plus GHCR network access when `-RegistryCache`/`-PublishCache` is set.
- Filesystem assumption: a `.github/containers` directory exists at `$WorkspaceRoot` (passed as `-ContextDirectory`, line 21) containing the actual Containerfile/build context.
- Environment: implicitly reads `QUIETCLI_REGISTRY_TOKEN` (mentioned in the doc comment, not visible in this 22-line file itself — presumably read inside `CiImages.ps1`).

## Side effects

- With `-PlanOnly`, none beyond whatever `Get-QuietCiImagePlan` itself touches (stated to be offline, no binary execution, no credential read).
- Without `-PlanOnly`: builds or pulls a container image (local Podman image store mutation), and with `-PublishCache` set, pushes a new cache entry to GHCR (network write, authenticated).
- No direct filesystem writes visible in this file itself (delegated to `Invoke-QuietCiImageBuild`).

## Findings

- No bug found in this file's own ~22 lines — it is almost entirely parameter declaration and two function calls, which is appropriate for a thin CLI entry point; any defects would live in `CiImages.ps1` (`Get-QuietCiImagePlan`/`Invoke-QuietCiImageBuild`), which is outside this review's assigned file list.
- DESIGN: the `-PublishCache` restriction ("restricted to the upstream main push/manual workflow, never pull requests") is documented only in the `.PARAMETER PublishCache` comment (line 13) — there is no enforcement *inside this script* (no check of `$env:GITHUB_EVENT_NAME` or similar) to prevent a misconfigured workflow from passing `-PublishCache` on a pull-request trigger. The safety boundary is entirely external (workflow YAML conditionals), which is a single point of trust rather than a defense-in-depth check; a future workflow edit that forgets the guard would silently violate the stated security property with no error from this script.
- CONVENTION: line 1's comment ("Objectif : Réutiliser le cache GHCR ou construire une image native et la publier uniquement depuis main.") is written in French, violating the repo's English-only code/comments rule — the same pattern seen in `Monitor.Time.ps1`. The structured `.SYNOPSIS`/`.PARAMETER` comment-based help block below it (lines 3-16) is correctly in English, so only the top-of-file French summary line is the issue.
- No input-validation gap found beyond what's delegated: `-RuntimeIdentifier`'s `ValidateSet` is a strong, correct guard against typos/unsupported RIDs reaching the Podman layer.
- Testability: no dedicated test for `New-CiImage.ps1` itself was found; `FrenchExDev2.QuietCli.Git.Tests.PoSh/CiImages.Tests.ps1` references `scripts/New-CiImage.ps1` only as a file-existence/path entry in a list (line 28), not as an invoked-and-asserted script. The underlying `CiImages.ps1` plan-building logic may be tested elsewhere, but this orchestrating script's own parameter binding and the `-PlanOnly` early-return path have no direct Pester assertion found in this review.

## Verdict

This is a minimal, appropriately thin CLI wrapper with no internal logic defects found; the one worth fixing is translating the French top-of-file comment to English, and the one worth considering is whether `-PublishCache`'s "main-only" restriction should be asserted inside the script (e.g., failing fast if `$env:GITHUB_REF` doesn't look like main) rather than relying solely on the calling workflow's own conditional logic.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
