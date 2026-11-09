# Get-CiImageForDevelopment.ps1

## Purpose

Lets a developer on any host OS (Windows, macOS, or a non-matching Linux architecture) pull an already-published, digest-pinned CI test image from GHCR by exact source fingerprint, without ever building one locally — enforcing that only a native Linux CI runner is trusted to produce the image this repository treats as a qualification input, per its own `.DESCRIPTION` (lines 7-15). It is referenced throughout `scripts/Invoke-ColdStartMatrix.ps1` (lines 11, 49, 54) as the documented "never build, only pull" partner script, and actually invoked at that file's line 159 when assembling a cold-start matrix run on a non-native host.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `RuntimeIdentifier` | `string` (`ValidateSet` of 4 Linux RIDs) | Yes | none |
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `RegistryToken` | `string` (`AllowEmptyString`) | No | `$env:QUIETCLI_REGISTRY_TOKEN` |

```powershell
$image = ./scripts/Get-CiImageForDevelopment.ps1 -RuntimeIdentifier linux-x64
```

## Dependencies

- Dot-sources `Common.ps1` (line 38) and `CiImages.ps1` (line 39, for `Get-QuietCiImagePlan`/`Get-QuietCiRegistryDigest`).
- Shells out to `podman pull` (line 46, via `Invoke-WorkspaceNative`) and `podman image inspect` (line 49, via `Invoke-CiProcess`).
- Assumes a working Podman engine is reachable from the current host (Podman itself must still be installed even though no build happens) and that GHCR is reachable (anonymous pull is attempted when `RegistryToken` is empty).

## Side effects

Pulls a real container image from GHCR into local Podman storage (line 46) — network and disk I/O. No mutation of the workspace tree itself.

## Findings

- Good: the identity-verification check (line 53: `$info.Architecture -cne $expected -or $info.Os -cne 'linux' -or $info.Labels... -cne $plan.Fingerprint -or $info.Labels... -cne $plan.Source`) refuses to return a receipt for an image that doesn't match the expected architecture, OS, or declared fingerprint/source labels. This mirrors the same wrong-architecture-image-reused-from-cache defense `CiImages.ps1`'s `Invoke-QuietCiImageBuild` implements proactively (that file's lines 276-281) — though this script only detects the mismatch after the fact and throws `CiImageIdentityMismatch`, rather than re-pulling to recover, which `Invoke-QuietCiImageBuild` does.
- DESIGN (positive): the error message at line 43 is genuinely good UX — it names the exact fingerprint and RID, and gives two concrete next steps (run the CI workflow's image job, run `New-CiImage.ps1` on native Linux, or wait for `main` to publish). Clear, actionable error text is relatively rare across this set and is worth calling out.
- No sanitization of `RegistryToken` beyond `[AllowEmptyString]` — it is passed straight into `Get-QuietCiRegistryDigest`'s Basic-auth header construction with no trimming or format check. Low risk in practice since this normally comes from a CI secret, but there is no defensive validation before it is used for authentication.
- Testability: no Pester test was found referencing `Get-CiImageForDevelopment` directly. Its correctness depends almost entirely on `CiImages.ps1`'s own tested functions, so the orchestration logic unique to this file — the identity-verification check (line 53) and the "fail with an actionable error if nothing is cached" path (line 43) — has no direct test of its own.

## Verdict

Fit for purpose: correctly narrow in scope ("pull only, never build"), with good identity verification and an unusually clear error message. The main gap is the absence of a direct test for this file's own orchestration logic (lines 41-56), which currently relies entirely on its tested building blocks being composed correctly by eye.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
