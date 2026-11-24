# ModuleVersion.psm1

<!-- script-source:begin -->
Source file: [`lib/ModuleVersion.psm1`](../../../scripts/lib/ModuleVersion.psm1)
<!-- script-source:end -->

## Purpose and usage

`Invoke-QuietScriptNewVersion` implements [New-Version.ps1](../New-Version.md).
It accepts an exact version or a per-module bump, a business module selection and a
workspace root. It returns a summary row per module for both applied and previewed edits.

## Dependencies and effects

[WorkspaceProjects](WorkspaceProjects.md) discovers manifest paths and module aliases.
[ReleaseTags](ReleaseTags.md) supplies the literal manifest editor. The library import
only declares functions and loads its dependencies. The exported command plans the
whole batch before requesting approval for writes. Unchanged manifests are skipped.

## Findings

- The [bump calculation](../../../scripts/lib/ModuleVersion.psm1#L15) requires a
  three-part numeric version and checks overflow for the component or preview counter.
- The [replacement routine](../../../scripts/lib/ModuleVersion.psm1#L42) stages UTF-8
  files beside their manifests and checks that the original text still matches before
  each replacement. These checks do not lock out concurrent external writers.
- The [rollback routine](../../../scripts/lib/ModuleVersion.psm1#L71) preserves original
  backups if a file cannot be restored. A failed restoration reports their paths.

## Verdict

Use through the script entry point for local manifest edits. The focused tests cover
version arithmetic, malformed versions, scope, dry runs and the full child-process
sequence from setting a preview to bumping its counter and patch.

<!-- script-contract:begin -->
## Execution contract

Purpose: Increments a three-part module version or its numeric preview counter.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
