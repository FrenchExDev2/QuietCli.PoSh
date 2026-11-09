# Install-ModuleWorkstation.ps1

## Purpose

Runs the per-module workstation installer (its own `scripts/Install-Workstation.ps1`) for each selected
sibling QuietCli ecosystem module — today only `'Git'` and `'Vagrant'` — without replacing or changing
`Install-DevelopmentWorkstation.ps1`. It exists because module-specific workstation setup (e.g. Git
tooling, Vagrant) is scoped to its own ecosystem folder rather than centralized, and this script is the
dispatcher that lets a caller install several modules' workstation prerequisites in one command. No
caller inside `scripts/` was found referencing this script by name via grep, other than the
`DevelopmentWorkstation.Tests.ps1` test file (lines 216, 220, 281), which references
`scripts/Install-ModuleWorkstation.ps1` as a selector path/tool name — suggesting it is exercised by
tests but not chained from other orchestration scripts. It is intended as a developer-run entry point,
parallel to (not called by) `Install-DevelopmentWorkstation.ps1`.

## Usage

Parameters:
- `-Modules` (string[], **mandatory**, `[ValidateSet('Git','Vagrant')]`) — module names to install, in the given order; no `'All'` default, so the caller must choose explicitly.
- `-CheckOnly` (switch, optional) — forwarded to each module's own script: probe only.
- `-Download` (switch, optional) — forwarded to each module's own script: best-effort pre-fetch, never installs.

Mutually exclusive: `-CheckOnly` and `-Download` together throw `'CheckOnlyAndDownloadAreMutuallyExclusive'` (line 24).

Example:
```powershell
./scripts/Install-ModuleWorkstation.ps1 -Modules Git, Vagrant -CheckOnly
```

## Dependencies

- Dynamically invokes `../FrenchExDev2.QuietCli.<Module>.PoSh/scripts/Install-Workstation.ps1` for each selected module (line 27) — i.e. it depends on each named ecosystem folder existing as a sibling of this module's root (`$root = Split-Path $PSScriptRoot -Parent`, line 25) and on each exposing that exact script path.
- No explicit `$ErrorActionPreference='Stop'` is set in this file (unlike most siblings in this folder) — see Findings.
- No dot-sourcing of `Common.ps1` or any other shared helper; the script is fully self-contained logic-wise (actual work delegated to the per-module scripts).

## Side effects

- Whatever each `Install-Workstation.ps1` does (not reviewed; out of scope) — installs module-specific tooling, subject to `-CheckOnly`/`-Download`/`-WhatIf`.
- `-WhatIf`/`-Confirm` support declared (`[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]`, line 18) and forwarded via `-WhatIf:$WhatIfPreference` (line 27), but this script itself calls no state-mutating cmdlet directly — it is pure forwarding.

## Findings

- CONVENTION/BUG risk: `$ErrorActionPreference='Stop'` is **not set** in this script, unlike every sibling script reviewed in this batch (`Initialize-Workspace.ps1` line 12, `Install-DevelopmentWorkstation.ps1` line 49, etc.). Without it, a non-terminating error from the `&` call-operator invocation at line 27 (e.g. a module script that writes a non-terminating error instead of throwing) would not stop the `foreach` loop over `-Modules`, silently continuing to the next module. This is an inconsistency with the rest of the codebase's defensive error-handling convention and should be fixed.
- DESIGN: There is no validation that the target script actually exists before invocation (line 27's `&` call) — if a sibling ecosystem folder is missing or restructured, the error surfaced is PowerShell's generic "command not found" rather than a descriptive `ModuleWorkstationScriptMissing`-style exception consistent with this codebase's naming convention for thrown error strings (e.g. `'CheckOnlyAndDownloadAreMutuallyExclusive'` at line 24).
- The `.DESCRIPTION` comment (lines 5–8) explicitly documents that extending to another module requires adding both a `ValidateSet` value here and that module's own `scripts/Install-Workstation.ps1` — this is good, deliberate scope documentation (not a finding, a positive).
- No companion Pester test asserting this script's own dispatch behavior was found; `DevelopmentWorkstation.Tests.ps1` references the *path* to this script (as a selector/tool name) but that reference alone does not confirm this script's `foreach`/error-handling logic is actually exercised — would need to read that test file's body to confirm, which was out of this review's explicit script list.
- No UTF-8 or encoding concerns apply — the script performs no text I/O itself.

## Verdict

Mostly fit for purpose and intentionally minimal, but the missing `$ErrorActionPreference='Stop'` is a real inconsistency with the rest of this folder's convention and should be the first fix, since it changes failure-propagation behavior when installing multiple modules in one call.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
