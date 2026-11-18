# GitHubWorkflowMap.psm1

<!-- script-source:begin -->
Source file: [`lib/GitHubWorkflowMap.psm1`](../../../scripts/lib/GitHubWorkflowMap.psm1)
<!-- script-source:end -->

## Usage

`New-QuietGitHubWorkflowMap -WorkspaceRoot <path> -OutputPath <path>` composes the Markdown and returns the text and counts. `-OutputPath` determines relative links. The caller owns filesystem writes.

## Dependencies and effects

Uses [GitHubActionReferences](GitHubActionReferences.md) to discover workflows and local actions and [WorkflowDocumentation](WorkflowDocumentation.md) to obtain the verified parser and identify literal script paths. Reads YAML and checks whether link targets exist. The same resource preparation rules apply as for the workflow documentation generator.

## Findings

- `scripts/lib/GitHubWorkflowMap.psm1:132` builds a case-sensitive catalogue for local `uses` links. Local references outside `.github/actions`, remote actions and remote workflows remain references without inspecting their implementation.
- A job flowchart links dependencies and local calls. A composite action sequence diagram reads steps in declaration order. Conditions and matrices render as inline code to preserve GitHub Actions expressions in Markdown previews.
- Property tests exercise repeated links and generated names. Fixture tests cover trigger syntax, job dependencies, filters, local calls and links. GitHub execution remains outside this validation.

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

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
