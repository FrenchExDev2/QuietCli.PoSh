# Assert-QualificationGate.ps1

Receipts include GitHub RunId and RunAttempt when available. Publication reuse requires All, the exact current SHA/run/attempt and successful Windows/Linux with the explicit TTY exclusion, through `Assert-QualificationReceipt.ps1`; local receipts remain usable locally but cannot substitute for a GitHub checkpoint.

`WorkspaceRoot` selects build/companions.yml. The declared suites determine whether native Core
evidence is required; the gate has no Git-specific condition. Unknown suites fail before a receipt
or qualified_sha is written. SkipTty still records an explicit exclusion.

## Purpose

Emits (or rejects) the final, revision-bound "ready to ship" qualification receipt for CI by combining the Windows and Linux test-matrix results with the native mutation-campaign result, and appends `qualified_sha=<Revision>` to the GitHub Actions step output only when every required job succeeded. It is the terminal gate that decides whether a given commit SHA may be trusted downstream (e.g. for publication). It is invoked directly from `.github/workflows/ci.yml` (line 41): `./scripts/Assert-QualificationGate.ps1 -Suite $env:QUIETCLI_SUITE -Revision $env:GITHUB_SHA -WindowsResult $env:WINDOWS_RESULT -LinuxResult $env:LINUX_RESULT -MutationResult skipped -SkipTty -ReceiptPath ./artifacts/qualification-gate/receipt.json -OutputPath $env:GITHUB_OUTPUT`.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `Suite` | `string` (declared suite or All) | No | `'All'` |
| `SkipTty` | `switch` | No | off |
| `Revision` | `string` (`ValidatePattern` 40-hex-char SHA) | Yes | none |
| `WindowsResult` | `string` | Yes | none |
| `LinuxResult` | `string` | Yes | none |
| `MutationResult` | `string` | Yes | none |
| `ReceiptPath` | `string` | Yes | none |
| `OutputPath` | `string` | Yes | none |

```powershell
./scripts/Assert-QualificationGate.ps1 -Suite All -Revision $env:GITHUB_SHA -WindowsResult success -LinuxResult success -MutationResult success -ReceiptPath ./artifacts/qualification-gate/receipt.json -OutputPath $env:GITHUB_OUTPUT
```

## Dependencies

- Dot-sources `Common.ps1` (line 34) for `Write-WorkspaceJson`.
- Writes to `$OutputPath` directly via `[IO.File]::AppendAllTextAsync` (line 40) rather than through a Common.ps1 helper.
- No external process is shelled out to.

## Side effects

- Creates the receipt directory if missing (line 37).
- Always writes the qualification receipt JSON (line 38), on both success and failure — "including unsuccessful decisions," per its own `.PARAMETER ReceiptPath` doc comment.
- Appends `qualified_sha=<Revision>\n` to `$OutputPath` only on success (line 40); throws `'QualificationRejected'` otherwise (line 39).

## Findings

- Good: the receipt is recorded even on a failed qualification (line 38 runs before the `if(!$ready){throw ...}` check at line 39) — this is a deliberately good auditability property, not a gap.
- Good: `Revision` is validated with `[ValidatePattern('^[a-fA-F0-9]{40}$')]` (line 26), rejecting abbreviated or malformed SHAs before they are ever persisted or recorded — explicit input validation.
- CONVENTION (minor): `$mutationExpected=if($SkipTty -or $Suite -eq 'Git')` (line 35) uses case-insensitive `-eq` for `$Suite -eq 'Git'`, while the readiness check two lines later (line 36) uses case-sensitive `-ceq` throughout for `$WindowsResult`/`$LinuxResult`/`$MutationResult`. Harmless in practice since `Suite` is constrained by `[ValidateSet('All','Core','Git')]` to exact casing anyway, but it is an inconsistency in an otherwise deliberately case-sensitive file.
- Testability: no Pester test was found anywhere under `*Tests*.ps1` referencing `Assert-QualificationGate`. This is the one script that decides whether a revision may be treated as qualified for release, and per the repository's own test-strategy policy ("Missing tooling or an unexecuted required campaign is an explicit qualification gap, never an implicit pass") it is notable that the gate enforcing that policy has no automated test of its own.

## Verdict

The logic is small, readable, and already does the right thing (always records a receipt, validates the SHA format, appends output only on success). The complete absence of any Pester test for the single script that decides whether a revision may ship is the highest-priority fix.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Emits a revision-bound qualification receipt only after every required job succeeds.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
