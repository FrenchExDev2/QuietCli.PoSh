# ScriptShouldProcess.psm1

## Library boundary

Located at `scripts/lib/ScriptShouldProcess.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/ScriptShouldProcess.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Get-QuietScriptShouldProcess','Test-QuietScriptShouldProcessPolicy'
```


## Purpose and usage

Read-only AST/policy library. Get-QuietScriptShouldProcess -Path <file> classifies standard ShouldProcess support, a function-only/empty library or an unclassified entry point. Test-QuietScriptShouldProcessPolicy -WorkspaceRoot <root> checks new PowerShell scripts against build/script-shouldprocess.json.

## Dependencies and side effects

Uses the host PowerShell parser and UTF-8 JSON policy. Scans .ps1/.psm1 sources without executing them, excluding generated .git/bin/obj/lib/artifacts/.profilers/.cache/.vs trees and rejecting links. Authored scripts/lib sources are included, unlike generated lib outputs; a dedicated unsafe-module regression checks that boundary. No native command, build, network or file mutation.

## Critical review

- scripts/ScriptShouldProcess.psm1:2 requires CmdletBinding(SupportsShouldProcess) and an actual top-level $PSCmdlet.ShouldProcess invocation. A custom WhatIf switch or attribute without a guard is rejected.
- scripts/ScriptShouldProcess.psm1:32 applies the frozen pre-rule inventory separately: legacy files are reported as unqualified, never implicitly claimed safe. Function-only libraries delegate effects to public entry points.
- A new read-only entry point needs a meaningful policy justification and exact SHA-256. Changing its code invalidates that exception until reviewed. The gate cannot infer all external effects or prove that a guard dominates every mutation; runtime WhatIf regressions remain required.
- AutomationContracts.Tests.ps1 covers generated guarded scripts, actual no-write previews, malformed contracts, stale exceptions and a guard-removal mutant.

## Verdict

Enforces the standard preview API for new executable scripts, with explicit legacy scope and reviewed read-only exceptions.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

## .NET tooling review

The RAC-PS-003 placement guard at scripts/ScriptShouldProcess.psm1:80 rejects every scripts/**/*.psm1 outside scripts/lib before consulting the frozen legacy inventory. Declarative module initialization is limited to function definitions, strict mode, exports and an exact sibling-module import; executable initializer statements remain unclassified. The .NET Layout suite independently generates accepted/rejected initializer corpora and removes the placement guard in a targeted mutant. AST classification is not execution qualification.

<!-- script-contract:begin -->
## Execution contract

Purpose: Classifies a PowerShell file without executing it; mutation previews require the standard API and a guard.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 2.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Read-only property projections use script blocks so metadata remains available during WhatIf; mutating operations retain their existing operation guards.
