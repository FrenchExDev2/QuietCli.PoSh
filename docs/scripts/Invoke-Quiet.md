# Invoke-Quiet.ps1

Runs a PowerShell scriptblock in the current process after importing the exact local
Core manifest and optional selected companion manifests relative to `$PSScriptRoot`. Run from a built source checkout:

```powershell
$result = ./scripts/Invoke-Quiet.ps1 -Code {
    param($runtime)
    $runtime.Data.Result = quiet -AsObject -RecordDelimiter "`n" `
        -Data @{ Version = $null; Records = 0 } `
        -Output {
            param($event, $native)
            if ($event.Stream -eq 'stdout') {
                $native.Data.Version = $event.Text.Trim()
                $native.Data.Records++
            }
        } `
        -Complete {
            param($native)
            if ($native.Data.Records -ne 1) { throw 'ExpectedOneSdkVersion' }
            $native.Data
        } dotnet --version
    $runtime.Data.Result
}
if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or
    !$result.Completeness.Analysis -or $result.Error.Count) { throw 'IncompleteSdkVersion' }
# The runner imports Core into its own scope. Import it in the caller for delivery commands.
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1
Out-QuietResult $result -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

## Parameters and context

- `Code` is mandatory and runs once as `& $Code $Runtime`. Use `param($runtime)` at
  the start of the block. PowerShell comments use `#`, not `//`.
- `Runtime` optionally supplies a non-null caller-owned object. By default every
  invocation creates a context containing fresh `Data` and `State` hashtables.
- `Companion` accepts one or more values from the explicit `Git`, `Vagrant` set. Core
  is always imported first; selected companions are deduplicated and imported from
  their exact local manifests before `Code` runs. For companion dependency resolution,
  Core is temporarily exposed in the process-global scope. Modules newly introduced by
  this invocation are removed in reverse order after `Code`; matching modules that were
  already loaded by the caller are retained.
- `WhatIf` skips import and execution entirely; `Confirm` uses the standard
  PowerShell confirmation before either operation.

```powershell
$context = [pscustomobject]@{ Data = @{ Count = 0 }; State = @{} }
./scripts/Invoke-Quiet.ps1 -Runtime $context -Code {
    param($runtime)
    $runtime.Data.Count++
}
./scripts/Invoke-Quiet.ps1 -WhatIf -Code { throw 'This block must not run' }
```

The orchestration context is separate from each native call's callback runtime. It
does not implement native runtime methods such as `Emit` or `Cancel`, and the runner
does not synthesize an envelope, parent invocation, measurement context or native
process. `quiet` retains its normal callback/registered-handler requirements.
Select a companion explicitly when registered executable semantics are required:

```powershell
./scripts/Invoke-Quiet.ps1 -Companion Git -Code {
    param($runtime)
    $runtime.Data.Status = quiet -AsObject -C work git status
}
```

The fixed set is intentional: arbitrary names never become import paths. Add a new
reviewed companion to the set when it joins this source workspace. Dynamic parameter
discovery is unnecessary for the current two companions and would make help and static
automation analysis less predictable.

## Dependencies and effects

Requires PowerShell Core 7.6+ and the checkout's existing verified Core/selected companion binaries and
resources. Imports each `.psd1` rather than globbing `.psm1` files. A different loaded
source path for any selected module is rejected with a fresh-session instruction.
The launcher never builds, downloads dependencies, changes the profile or overrides
engine hosting. Normal module integrity checks and automatic hosting still apply.

Code executes with the current session's permissions, variables and working
directory. Its effects are caller-defined. Pipeline objects and terminating errors
propagate; results are not automatically enumerated, formatted or serialized by the
launcher beyond ordinary PowerShell pipeline semantics. Retain `-AsObject` results
locally and explicitly deliver a bounded view. Child native failures remain ordinary
QuietCli result envelopes and must be checked by Code or its caller.

Imports use `-DisableNameChecking` to suppress unapproved-verb naming warnings while preserving other warnings and terminating import errors. This launcher imports production modules only; test-companion imports belong to `Invoke-TestWorker.ps1`.

## Findings

- `scripts/Invoke-Quiet.ps1:31` guards import and arbitrary Code together, so preview
  cannot trigger either. It cannot preview the contents of arbitrary user code.
- `scripts/Invoke-Quiet.ps1:38` rejects a conflicting Core path before import; no
  forced reload or assembly replacement is attempted.
- `scripts/Invoke-Quiet.ps1:44` preserves the original block and context, including
  caller variables. Blocks explicitly bound to another module retain that module's
  command-resolution scope and must import Core into that scope when necessary.
- The companion's Script suite covers preview, identity, repeated contexts,
  Unicode/input corpora, error propagation, local imports and actual native calls.
  These checks qualify the launcher on the executed host, not a release matrix.

## Verdict

A source-development convenience entry point. It delegates native execution to
Core and leaves business analysis and bounded delivery explicit.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs a PowerShell block with the checkout's local QuietCli Core and selected companion modules.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
