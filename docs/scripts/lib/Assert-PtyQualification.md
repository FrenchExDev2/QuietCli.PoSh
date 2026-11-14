# Assert-PtyQualification.psm1

## Library boundary

Located at `scripts/lib/Assert-PtyQualification.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/Assert-PtyQualification.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Assert-PtyQualification'
```


## Purpose

Fails closed a native PTY-bridge qualification run that lacks a complete unit/process-property pass, a full decoder-fuzzing run (at least 20,000 executed iterations), and a 100%-killed mutation campaign. It rejects any native validation phase that is missing or incomplete, per the file's own objective comment (line 1). It is invoked by `scripts/Invoke-ContainerWorker.ps1` (imported and called at lines 126-127) and by `FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Probe-Independent.ps1` (lines 39-40), which is itself packaged and re-run from several `artifacts/pty-independent/*/workspace/...` snapshot copies.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `Summary` | untyped object | Yes | none |

```powershell
. ./scripts/Assert-PtyQualification.psm1
Assert-PtyQualification $summary
```

## Dependencies

- No imported of other scripts; no external tool calls.
- Pure assertions over `$Summary.State`/`.Baseline`/`.Fuzz`/`.Mutation`.

## Side effects

None beyond throwing on failure.

## Findings

- DESIGN: same magic-number smell as `Assert-CoreIntegrationEvidence.ps1` — the thresholds `$Summary.Baseline.Assertions -lt 43`, `.PropertyGroups -lt 6` (line 11), and `$Summary.Fuzz.RequestedRuns -lt 20000` (line 12) are hardcoded with no comment explaining their provenance.
- All conditions are combined into one giant `-or` chain (lines 10-14) feeding a single generic throw (line 15: `'NativeQualificationIncomplete: unit/process properties, fuzzing and mutation must all pass.'`). This is more descriptive than a bare sentinel, but it still does not say *which* of the five ANDed sub-conditions (state, baseline pass/count, fuzz completeness, mutation selection, mutation outcome) actually failed — a caller must re-inspect `$Summary` by hand to localize the real problem.
- Unlike `Assert-CoreIntegrationEvidence.ps1`, this file sets neither `$ErrorActionPreference` nor `Set-StrictMode` itself — it relies entirely on the caller's environment. Under default (non-strict) mode, a missing property on `$Summary` (e.g. an absent `.State`) silently evaluates to `$null`, and `$null -cne 'Success'` is still `$true`, so the throw still fires — this is accidental safety from how the comparisons happen to be written, not a deliberate StrictMode guard.
- Testability: exercised directly from `Probe-Independent.ps1:40` in both the live test tree and multiple packaged `artifacts/` snapshots, giving it reasonable functional coverage, though no isolated unit test asserts the behavior of each individual threshold in this file on its own.

## Verdict

Small and functionally adequate, but the single, generic throw message covering five ANDed magic-number conditions (lines 10-15) is the highest-priority fix — splitting it into a few named checks would let a failing caller see immediately whether the baseline, fuzz, or mutation requirement was the one not met.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Requires unit/process properties, complete decoder fuzzing and every valid mutation to pass.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
