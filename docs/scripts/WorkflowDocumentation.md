# WorkflowDocumentation.ps1

## Purpose and usage

Read-only function library used by Sync-GitHubWorkflowsReadme.ps1. Get-QuietWorkflowDocumentation -WorkspaceRoot <root> enumerates every dotted file directly under .github/workflows, parses jobs/triggers with the checksum-pinned restored YamlDotNet resource, validates dependency targets and renders deterministic Mermaid plus the execution/condition/script table. Get-QuietWorkflowReadme -Entries <catalogue> renders the index body.

## Parser prerequisite

WorkflowDocumentation calls Ensure-QuietResource to verify and, if necessary, selectively restore the pinned YamlDotNet payload through ShouldProcess. No preceding GitHub step is required. WhatIf performs no restoration and cannot parse with a missing dependency. An incompatible loaded assembly requires a fresh process.

## Dependencies and side effects

Requires the checksum-verified YamlDotNet assembly, prepared on demand through Resources.ps1 rather than tracked in Git. No workflow files means no parser dependency. Reads UTF-8 workflow files and SHA-256 digests; never executes workflow expressions, run blocks or native tools. Missing payload preparation can write the selected resource/cache and download its package through ShouldProcess. Documentation and Git metadata are not modified.

## Critical review

- scripts/WorkflowDocumentation.ps1:2 derives job IDs and needs edges from parsed YAML, including reusable callers. Basename/diagram ID collisions and missing dependencies fail explicitly.
- Generated edges describe declared needs, not unconditional runtime execution: job conditions may skip nodes. Matrix expansion, expressions and scripts require their own semantic review and actual GitHub qualification.
- AutomationContracts.Tests.ps1 verifies a literal build-to-verify edge and rejects graph drift. Source receipts bind the reviewed prose to the YAML bytes; a hash is not proof of prose accuracy.

## Verdict

One structural source of truth for workflow diagrams and the index; authored purpose, trigger/effect descriptions and limits remain review obligations.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads workflow structure and renders its deterministic documentation contract without executing YAML.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
