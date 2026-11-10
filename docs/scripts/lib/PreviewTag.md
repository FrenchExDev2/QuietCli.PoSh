# PreviewTag.psm1 (lib)

## Purpose

A tiny, single-function utility module that deterministically generates a preview release tag name (e.g. `v2.45.0-preview20261109T153045123456789Z`) from a numeric semantic-style version and a UTC timestamp. It solves the need for a consistent, sortable, collision-resistant tag naming scheme for preview releases, separate from stable version tags. It is consumed by `New-QuietPreviewTag.ps1` (the end-user-facing script that actually creates the tag in Git) and is the logic tested directly by `PreviewTag.Tests.ps1`.

## Usage

Exported function (`Export-ModuleMember`, line 19): `New-QuietPreviewTagName`.

Signature:
- `New-QuietPreviewTagName -Version <string> -Timestamp <DateTimeOffset>` (both mandatory) — `Version` must match `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z` (three-component numeric, no leading zeros except a lone `0`) or it throws `PreviewTagInvalidVersion`. `Timestamp` is converted to UTC and formatted with all seven fractional-second digits.

Example:
```powershell
Import-Module ./scripts/lib/PreviewTag.psm1
New-QuietPreviewTagName -Version '2.45.0' -Timestamp ([DateTimeOffset]::UtcNow)
# -> 'v2.45.0-preview20261109T174512345678900Z' (exact digits vary)
```

## Dependencies

- None — no dot-sourcing, no `Import-Module`, no external tool. Pure, self-contained logic using only `[Globalization.CultureInfo]::InvariantCulture` for formatting (line 16).

## Side effects

None. The function is pure: given the same `Version` and `Timestamp`, it always returns the same string, with no filesystem, process, network, or environment interaction.

## Findings

- Genuine scrutiny found no bug, no convention violation, and no missing input validation: the version regex is anchored at both ends (`^...\z`), correctly rejects leading zeros (e.g. `'01.2.3'` would fail since `[1-9][0-9]*` disallows a leading `0` except for the literal `0` alternative), and the timestamp formatting explicitly uses `InvariantCulture` (line 16), matching the repository's culture-safety expectations for machine-readable text. No native process, no file I/O, no network — nothing async to "prefer" per AGENTS.md's async guidance, since there is nothing blocking to make async.
- Testability: `PreviewTag.Tests.ps1` exists under `FrenchExDev2.QuietCli.Core.Tests.PoSh/` and directly targets this function; being pure logic with a narrow contract, it is also trivially amenable to property-based testing (e.g. "for any valid three-component version and any UTC instant, the output always starts with `v<version>-preview` and parses back to the same instant") — whether that specific property is actually implemented in the existing test file was not verified line-by-line here, but the shape of the function makes such a property easy to add if missing.
- DESIGN: No design smell found — this is exactly the kind of small, single-responsibility, pure function the repository's SOLID/DRY/modular guidance asks for.

## Verdict

This module is fit for purpose as-is: a minimal, pure, well-validated function with existing dedicated test coverage and no findings worth flagging as issues.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates a deterministic preview tag from a numeric module version and a UTC instant.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
