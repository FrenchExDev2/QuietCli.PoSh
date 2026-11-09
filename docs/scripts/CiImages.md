# CiImages.ps1

## Purpose

Declares the reproducible-build recipe and GHCR cache identity for the native Linux Podman test images the CI matrix runs against — both Core's own base image and every Core-consumer module's derived image — so a content-addressed fingerprint (a hash of input files, rendered Containerfile text, and optionally a parent fingerprint) decides whether an already-published image can be reused instead of rebuilt. It is invoked by `scripts/Get-CiImageForDevelopment.ps1` (dot-sourced at line 39) and by the CI image-build scripts (`New-CiImage.ps1`/`New-CiModuleImage.ps1`, per the `.github/workflows/ci.yml` linux-images job), and tested directly by `FrenchExDev2.QuietCli.Core.Tests.PoSh/CiImageRecipe.Tests.ps1` and `FrenchExDev2.QuietCli.Git.Tests.PoSh/CiImages.Tests.ps1`.

## Usage

A function library; no script-level params.

| Function | Key parameters |
|---|---|
| `Get-QuietCiFingerprint` | `WorkspaceRoot` (Mandatory), `InputPaths` (Mandatory), `ContainerfileText` (Mandatory), `ParentFingerprint` (optional) |
| `Get-QuietCiImagePlan` | `WorkspaceRoot`, `RuntimeIdentifier` (`ValidateSet` of 4 Linux RIDs) |
| `Get-QuietModuleContainerfile` | `Platform` (Mandatory, `ValidateSet('debian','alpine')`), `Objective` (Mandatory), `Stages` (Mandatory) |
| `Get-QuietCiModuleImagePlan` | `WorkspaceRoot`, `RuntimeIdentifier`, `Module` (Mandatory), `ContainerfileFragment` (Mandatory), `ModuleArguments` (Mandatory), `ModuleInputPaths` (Mandatory) |
| `Get-QuietCiLocalImageArchitecture` | `Reference` (Mandatory) |
| `Get-QuietCiRegistryDigest` | `Plan`, `Token`, `Actor` |
| `Invoke-QuietCiImageBuild` | `Plan`, `ContextDirectory` (Mandatory), `WorkspaceRoot` (Mandatory), `ArtifactPrefix` (Mandatory), `RegistryCache` (switch), `PublishCache` (switch) |

```powershell
. ./scripts/CiImages.ps1
$plan = Get-QuietCiImagePlan -WorkspaceRoot $root -RuntimeIdentifier linux-x64
$digest = Get-QuietCiRegistryDigest $plan $env:QUIETCLI_REGISTRY_TOKEN $env:GITHUB_ACTOR
```

## Dependencies

- Does not dot-source anything itself, but calls `Invoke-CiProcess`/`Invoke-WorkspaceNative`/`Write-WorkspaceJson` (lines 172, 241, etc.) without declaring that dependency — these must already be loaded by the caller (typically via `Common.ps1`).
- Shells out to `podman` directly for image inspect, pull, build, push, and login (lines 172, 241, 267, 271, 282, 285, 301, 305, 313).
- Uses `System.Net.Http.HttpClient` to talk to the GHCR token and manifest APIs (lines 188-207).
- Reads `FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1` as a required, fixed-path contract script (lines 44-47).

## Side effects

- `Invoke-QuietCiImageBuild` creates a fresh GUID-named receipt directory under `artifacts/ci-images/` (line 251), writes `Containerfile`/`podman.log`/`image.json`/`registry.digest` into it.
- Logs into and out of the registry via a temporary authfile directory it creates and deletes (lines 264-266, 322).
- Unconditionally removes `Env:QUIETCLI_REGISTRY_TOKEN` from the current process environment (line 258) to scrub the credential before any child process is spawned.
- Pulls/builds/pushes real Podman images and can force-remove a locally cached base image on an architecture mismatch (line 285).

## Findings

- Good, security-relevant: credential handling is careful throughout — the GHCR token is scrubbed from the environment immediately (line 258) before any child process starts, held only in a local variable, written only into a short-lived authfile under a fresh temp directory with restrictive Unix file-mode flags (line 265), and the `finally` block (lines 321-324) deletes both the authfile and its directory and nulls the in-memory token. The token is passed to `podman login` via stdin (`-InputText`, line 267), never as a literal argument or log line. This is the strongest credential-handling code reviewed in this set.
- DESIGN: the file calls `Invoke-CiProcess`/`Invoke-WorkspaceNative`/`Write-WorkspaceJson` throughout with no dot-source of `Common.ps1` anywhere in this file — it only works today because every current caller happens to dot-source `Common.ps1` before this file. This is an implicit, unenforced load-order contract rather than a declared dependency; a future caller that dot-sources `CiImages.ps1` on its own would get a runtime "command not found" instead of a clear static error.
- Reviewed but not a bug: `Get-QuietCiRegistryDigest` (lines 176-208) appears fragile at a glance because it can `return $null` from inside a nested `try` (lines 193, 201) with both an inner `finally` (line 196/206) and an outer `finally` disposing `$client` (line 207) — tracing the control flow confirms both `finally` blocks correctly execute before the function returns; no leak.
- DESIGN: this one 326-line file carries four fairly distinct responsibilities — fingerprinting/identity (`Get-QuietCiFingerprint`), Containerfile template rendering (`Get-QuietModuleContainerfile`, lines 53-126, a ~70-line micro-templating engine), registry HTTP communication, and Podman build orchestration. Each function is independently testable and is in fact tested, so this is not a severe SOLID violation, but splitting the Containerfile renderer into its own file would make the single-responsibility boundary clearer.
- Testability: two dedicated test files exist (`CiImageRecipe.Tests.ps1`, `CiImages.Tests.ps1`) — among the better-covered files in this set.

## Verdict

Functionally strong, with notably careful credential handling and real test coverage. The highest-priority fix is making the `Common.ps1` dependency explicit (dot-source it, or document the required load order at the top of the file) so a new caller does not hit a runtime "command not found" instead of a clear static error.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
