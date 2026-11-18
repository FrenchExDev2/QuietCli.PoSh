# GitHubWorkflowMap.psm1

<!-- script-source:begin -->
Source file: [`lib/GitHubWorkflowMap.psm1`](../../../scripts/lib/GitHubWorkflowMap.psm1)
<!-- script-source:end -->

## Usage

`New-QuietGitHubWorkflowMap -WorkspaceRoot <path> -OutputPath <path>` composes the Markdown and returns the text and counts. `-OutputPath` determines relative links. The caller owns filesystem writes.

## Dependencies and effects

Uses GitHubActionReferences to discover workflows and local actions and WorkflowDocumentation to obtain the verified parser and identify literal script paths. Reads YAML and checks whether link targets exist. When the checkout contains `CREDITS.md`, the map includes a standard credits block with a link relative to the output. [GitHubActionReferences](GitHubActionReferences.md) · [WorkflowDocumentation](WorkflowDocumentation.md) · [Sync-DocsCredits](Sync-DocsCredits.md)

## Findings

- `scripts/lib/GitHubWorkflowMap.psm1:142` builds a case-sensitive catalogue for local `uses` links. External reusable workflow nodes link to the calling job's section. The map does not inspect external implementations.
- Flowcharts name the `triggers`, `composed of`, `depends on` and `uses` relations. Mermaid node links use generated local fragments, with parallel Markdown navigation. Sequences label steps as `runs` or `uses` in declaration order. Conditions and matrices render as inline code.
- Property tests exercise repeated links and generated names. Fixture tests cover trigger syntax, job dependencies, filters, local calls, rendered section headings and complete Mermaid participant declarations. GitHub execution remains outside this validation.

## Verdict

The map represents the structure declared in the checkout and links readers to the underlying sources.

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves a source or documentation path relative to the generated report.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
