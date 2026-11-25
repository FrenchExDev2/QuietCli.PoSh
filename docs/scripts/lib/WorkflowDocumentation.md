# WorkflowDocumentation.psm1

<!-- script-source:begin -->
Source file: [`lib/WorkflowDocumentation.psm1`](../../../scripts/lib/WorkflowDocumentation.psm1)
<!-- script-source:end -->

## Library boundary

Located at `scripts/lib/WorkflowDocumentation.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/WorkflowDocumentation.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Get-QuietWorkflowDocumentation','Get-QuietWorkflowReadme','Get-QuietWorkflowYamlParser','Get-QuietWorkflowScriptPaths','Format-QuietWorkflowLiteral'
```


## Purpose and usage

`Get-QuietWorkflowDocumentation -WorkspaceRoot <root>` parses workflow jobs and triggers, validates dependency targets and renders Mermaid with source links and script documentation. `Get-QuietWorkflowReadme -Entries <catalogue>` renders the index. The workflow map shares `Get-QuietWorkflowYamlParser`, `Get-QuietWorkflowScriptPaths` and `Format-QuietWorkflowLiteral`.

## Parser prerequisite

WorkflowDocumentation calls Ensure-QuietResource to verify and, if necessary, selectively restore the pinned YamlDotNet payload through ShouldProcess. No preceding GitHub step is required. WhatIf performs no restoration and cannot parse with a missing dependency. An incompatible loaded assembly requires a fresh process.

## Dependencies and side effects

Requires the checksum-verified YamlDotNet assembly, prepared on demand through Resources.ps1 rather than tracked in Git. No workflow files means no parser dependency. Reads UTF-8 workflow files and SHA-256 digests; never executes workflow expressions, run blocks or native tools. Missing payload preparation can write the selected resource/cache and download its package through ShouldProcess. Documentation and Git metadata are not modified.

## Critical review

- `scripts/lib/WorkflowDocumentation.psm1:93` derives job IDs and `needs` edges from parsed YAML. Basename and diagram ID collisions and missing dependencies fail explicitly.
- Workflow conditions and dynamic runners render as literal inline code. Encoding `$` prevents Markdown math parsing, while encoding `|` keeps logical OR within its table cell.
- Generated edges describe declared needs, not unconditional runtime execution: job conditions may skip nodes. Matrix expansion, expressions and scripts require their own semantic review and actual GitHub qualification.
- AutomationContracts.Tests.ps1 verifies a literal build-to-verify edge and rejects graph drift. Source receipts bind the reviewed prose to the YAML bytes; a hash is not proof of prose accuracy.

## Verdict

One structural source of truth for workflow diagrams and the index; authored purpose, trigger/effect descriptions and limits remain review obligations.

<!-- script-contract:begin -->
## Execution contract

Purpose: Renders a literal workflow value as inline code in Markdown prose or a table cell.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Preview is explicit across module boundaries: Get-QuietWorkflowDocumentation -WhatIf forwards standard preview options to Ensure-QuietResource. A missing parser remains unprepared in preview and cannot produce a successful documentation result.

Read-only property projections use script blocks, so the ForEach-Object member-access ShouldProcess behavior cannot suppress workflow metadata during WhatIf. The complete Commit-Workspace preview is exercised in a clean process.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
