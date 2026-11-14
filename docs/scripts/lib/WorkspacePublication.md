# WorkspacePublication.psm1

## Purpose and usage

`Invoke-WorkspacePublication -Arguments $publishArguments -WorkspaceRoot $root` prepares
one compiled distribution with the engine-independent `Invoke-WorkspaceNative` helper.
Arguments must start with `publish` and contain exactly one `-o` directory inside the
checkout. `-WhatIf` starts no native process and creates no directories.

The helper imports `Common.psm1` explicitly without forced reload or import-time effects.
`Build-Workspace.ps1` uses it for portable, RID and ReadyToRun publications. Compilation
options and `--no-build` remain unchanged; only the output directory passed to dotnet
is replaced with a unique staging directory under the destination.

## Effects and failure behavior

After successful publication, files are promoted in deterministic path order. Existing
files are renamed into a unique backup directory before their replacements are moved
into place. Windows permits this for assemblies loaded with delete sharing, avoiding
MSB3026/MSB3027/MSB3021 overwrite failures. Existing sessions retain their old mapped
assemblies; new sessions load the new files. Restart a session to use the new build.
Unrelated files and nested RID slots remain in place. Nested published dependencies
are promoted with their relative paths.

A failed native command leaves distribution files untouched. A promotion failure
restores replaced files in reverse order. If restoration itself fails, the error
identifies the backup directory and preserves it. After success or completed rollback,
temporary files are removed where possible. A locked old assembly remains under
`.quiet-previous-<id>` with an explicit warning; close its owning sessions before
removing that directory. This helper never terminates user processes or retries.
Integrity manifests remain the build caller's responsibility after successful promotion.

## Findings and qualification limits

- `scripts/lib/WorkspacePublication.psm1`: the argument and path guards reject missing
  or repeated output options, workspace-root/parent destinations and existing directory
  links. This is an internal build helper, not a general dotnet option parser.
- Publication is a sequence of file renames, not a filesystem transaction. Concurrent
  builds/imports into the same output are unsupported. A destination that denies rename
  also fails explicitly; backups are retained if rollback cannot complete.
- `FrenchExDev2.QuietCli.Core.Tests.PoSh/WorkspacePublication.Tests.ps1` checks a
  renameable Windows lock, reader continuity, nested files, unrelated slots, failed
  native publication, promotion rollback, no-effect preview, 24 seeded Unicode payloads,
  five malformed argument vectors and three targeted mutants. The existing Tooling
  ReadyToRun case owns this campaign and its saved `publication-campaign.json` report.
  Windows handle semantics require a Windows execution; other platforms exercise the
  portable rollback fixture. Cross-platform qualification remains the hosted matrix.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Publishes into a fresh directory before replacing distribution files, including loaded Windows assemblies.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
