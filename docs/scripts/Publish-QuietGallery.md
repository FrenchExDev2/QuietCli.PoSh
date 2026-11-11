# Publish-QuietGallery.ps1

## Purpose

Publishes the single validated, public `FrenchExDev2.QuietCli.Core.PoSh` PowerShell module to the PowerShell Gallery (PSGallery), solving the "last mile" problem of the release pipeline: turning a verified, hashed, locally-built package into a world-reachable release, exactly once, with no silent retry on partial failure. It is invoked by the GitHub Actions workflow `.github/workflows/publish-psgallery.yml` — first in `-ValidateOnly` mode as a pre-flight gate (lines 90, 141 of that workflow) and then for real (line 167) — and is also used in `-ValidateOnly` mode by `New-QuietPreviewPackage.ps1` (line 46) as a packaging-time sanity check, and directly exercised (both success and rejection paths) by `GalleryPreview.Tests.ps1` (lines 165, 183).

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `PackageDirectory` | `string` | Yes | — |
| `Version` | `string` (`ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z][A-Za-z0-9-]*)?\z|$')` — see Findings) | Yes | — |
| `ValidateOnly` | `switch` | No | off |

Supports `-WhatIf`/`-Confirm` (`SupportsShouldProcess`, `ConfirmImpact='Medium'`).

```powershell
# Pre-flight validation only — no key required, no network call to PSGallery for publishing
./scripts/Publish-QuietGallery.ps1 -PackageDirectory ./artifacts/gallery -Version 0.2.0-preview -ValidateOnly

# Real publish (requires $env:PSGALLERY_API_KEY)
./scripts/Publish-QuietGallery.ps1 -PackageDirectory ./artifacts/gallery -Version 1.2.0
```

## Dependencies

- Dot-sources `Common.ps1` and `Gallery.ps1` (line 14) — the latter supplies `Test-QuietGalleryPackageSet` (line 16) and `Get-QuietGalleryRemoteIdentity` (line 22), both of which perform substantial validation (nupkg integrity, nuspec parsing with XXE-safe `XmlReaderSettings`, dependency/architecture-payload checks) before anything is published.
- Calls `Get-PSResourceRepository -Name PSGallery` and `Publish-PSResource` (lines 20, 31) from the `Microsoft.PowerShell.PSResourceGet` module — an implicit dependency not explicitly imported in this file (presumably available via the host's module auto-loading).
- Reads `$env:PSGALLERY_API_KEY` (line 19) — the API key must be supplied via environment variable; the script explicitly refuses to accept it as a parameter ("never pass it on the command line" per its own `.SYNOPSIS`/line 19 error message), which matches the repo's secrets-handling expectations.
- Makes an outbound network call to validate the configured PSGallery repository URI (`$repository.Uri.AbsoluteUri`, line 21) and, for each module, an HTTP preflight check against `powershellgallery.com` (`Get-QuietGalleryRemoteIdentity`, defined in `Gallery.ps1` lines 211-233, using a raw `HttpClient` with a 30s timeout) to detect whether the version already exists before attempting to publish.

## Side effects

- Writes/overwrites a `publication.json` receipt file in `-PackageDirectory` at every state transition (`Prepared` → `Publishing` → `Published`/`NotPublished`/`Failed`, lines 23, 29, 34, 40, 42) — this receipt is the authoritative record of "what was actually published" if the process is interrupted mid-release, which is good crash-forensics design for a non-retryable operation.
- Calls `Publish-PSResource` (line 31) — the one truly destructive, non-idempotent side effect: it uploads a nupkg to PSGallery and cannot be undone once it succeeds.
- `-ValidateOnly` and `-WhatIf` paths: no network publish call and no receipt file write — purely read-only validation against the local package set, `return`ing early (lines 17-18) before any state-mutating logic runs.
- `$WhatIfPreference` short-circuit (line 18) iterates `$plan.Packages.Module` calling `$PSCmdlet.ShouldProcess` purely to produce `-WhatIf` output, then returns without using the result in a condition — functionally harmless but slightly unusual control flow (see Findings).

## Findings

- The version `ValidatePattern` at line 13 reads `'^\d+\.\d+\.\d+(?:-[A-Za-z][A-Za-z0-9-]*)?$'` — a standard semver-like regex that is **not** anchored with `\z` (uses `$` instead), meaning (in .NET regex semantics under `ValidatePattern`, which uses `Regex.IsMatch` without `Singleline`) a trailing newline after a valid version would technically still match, since `$` matches before a trailing `\n`. This is an extremely low-severity edge case (CI/parameter binding is unlikely to ever pass an embedded newline), but it is inconsistent with `Gallery.ps1`'s own `Get-QuietGalleryVersion` (used internally, e.g. `Gallery.ps1` line 63) which uses the stricter, explicitly end-anchored `^...$` form consistently with other validations in that file (e.g. line 97 uses `\z`). Minor regex-hygiene inconsistency, not exploitable in practice since the value is also independently re-validated by `[semver]$Version` casts downstream.
- DESIGN: on line 18, `$WhatIfPreference` is checked and a loop calls `$PSCmdlet.ShouldProcess(...)` purely for its side-effect of emitting the "What if:" message, discarding the boolean return value (`$null=$PSCmdlet.ShouldProcess(...)` is not used; it's just `$null=...`). This works but is an unusual, slightly indirect way to drive `-WhatIf` output compared to gating the real `Publish-PSResource` call itself with `ShouldProcess` (which the script *also* does, correctly, at line 28). The short-circuit at line 18 is redundant with the `ShouldProcess` gate at line 28 and adds a second code path to reason about for the same behavior — a minor DRY/simplicity concern, not a bug.
- The partial-failure handling (`catch` block, lines 38-41) is a notable strength: it records `$receipt.EffectStatus` as `'Unknown'` when a publish was in-flight (`$receipt.PendingModule` was set) versus `'Known'` otherwise (line 39), explicitly acknowledging that PSGallery publish failures can leave an ambiguous server-side state — and the thrown message explicitly warns "Do not retry a partial release blindly" (line 41). This is exactly the kind of honest failure-mode documentation the task's "no automatic retry" convention calls for.
- No issues found with secrets handling: the API key is read only from the environment (line 19), never logged, and never passed via `-ArgumentList` to any native process (it's handed directly to the `Publish-PSResource` cmdlet in-process, line 30-31).
- Testability: good — `GalleryPreview.Tests.ps1` exercises both the success path (line 165, with `-Confirm:$false`) and an explicit rejection path (line 183, asserting the thrown error is one of `GalleryPackageSetInvalid`/`GalleryPackageIdentityInvalid`). The underlying `Test-QuietGalleryPackageSet` validation logic in `Gallery.ps1` is extensive and defensively written (XXE-safe XML parsing, zip-entry-count/size caps, path-traversal checks at `Gallery.ps1` line 172).

## Verdict

Fit for purpose; the partial-failure receipt design and secrets handling meet the bar this repository expects for a non-retryable, one-shot publish operation. The only worthwhile improvement is cosmetic: tighten the `Version` parameter's regex anchor to `\z` (line 13) for consistency with `Gallery.ps1`'s own stricter patterns, and consider removing the redundant `$WhatIfPreference` short-circuit (line 18) in favor of relying solely on the `ShouldProcess` gate already present at line 28.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Publishes a prepared release once, with version and destination checks and no automatic retry.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
