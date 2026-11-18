# Export-GitHubWorkflowMap.ps1

<!-- script-source:begin -->
Source file: [`Export-GitHubWorkflowMap.ps1`](../../scripts/Export-GitHubWorkflowMap.ps1)
<!-- script-source:end -->

## Usage

Generate a navigable Markdown document from `.github/workflows` and `.github/actions`.

```powershell
./scripts/Export-GitHubWorkflowMap.ps1
./scripts/Export-GitHubWorkflowMap.ps1 -OutputPath ./artifacts/ci-map.md -WhatIf
```

The default output is `artifacts/github-workflows.md` under the selected `-WorkspaceRoot`. An explicit relative `-OutputPath` is resolved from the current PowerShell location. Open the report in a Markdown renderer with Mermaid support. Use the table of contents to open a workflow, then follow the links to the YAML, reusable workflows, local actions and script documentation.

## Dependencies and effects

Requires PowerShell 7.6 and the repository's checksum-pinned YAML parser. The shared resource helper prepares a missing parser on an approved run. `-WhatIf` exits before loading the parser, scanning the checkout or creating files. A successful run replaces the selected `.md` in UTF-8/LF after rendering the complete report in memory. Keeping the report in the checkout preserves relative links when moving the checkout as a unit.

## Findings

- `scripts/Export-GitHubWorkflowMap.ps1:28` guards report generation and prerequisite preparation. Missing workflows or YAML parsing failures leave any previous report in place.
- Step tables link literal `scripts/` paths found in `run` blocks. They cannot infer dynamically assembled commands or paths, or distinguish every shell comment from a command.
- The overview shows declared event and reusable-workflow links. Per-workflow diagrams add `needs` and local action calls. Vector rendering depends on the selected Markdown viewer.

## Verdict

Use the map to trace a declared CI entry point through its jobs and source files. Consult the source and hosted run to establish which conditional branches actually executed.

<!-- script-contract:begin -->
## Execution contract

Purpose: Exports a navigable Markdown map of GitHub Actions triggers, jobs and local calls.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
