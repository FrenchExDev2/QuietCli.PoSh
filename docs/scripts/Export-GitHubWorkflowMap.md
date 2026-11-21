# Export-GitHubWorkflowMap.ps1

<!-- script-source:begin -->
Source file: [`Export-GitHubWorkflowMap.ps1`](../../scripts/Export-GitHubWorkflowMap.ps1)
<!-- script-source:end -->

## Usage

Generate a navigable Markdown document from `.github/workflows` and `.github/actions`.

```powershell
./scripts/Export-GitHubWorkflowMap.ps1
./scripts/Export-GitHubWorkflowMap.ps1 -OutputPath ./docs/README-github-workflows-diagrams.md
./scripts/Export-GitHubWorkflowMap.ps1 -OutputPath ./artifacts/ci-map.md -WhatIf
```

The default output is `artifacts/github-workflows.md` under the selected `-WorkspaceRoot`. An explicit relative `-OutputPath` is resolved from the current PowerShell location. The tracked map uses the second command. Open it in a Markdown renderer with Mermaid support and follow the table of contents to YAML, reusable workflows, local actions and script documentation. [GitHub workflow map](../README-github-workflows-diagrams.md)

## Dependencies and effects

Requires PowerShell 7.6 and the repository's checksum-pinned YAML parser. The shared resource helper prepares a missing parser on an approved run. `-WhatIf` exits before loading the parser, scanning the checkout or creating files. A successful run replaces the selected `.md` in UTF-8/LF after rendering the complete report in memory. Keeping the report in the checkout preserves relative links when moving the checkout as a unit.

## Findings

- `scripts/Export-GitHubWorkflowMap.ps1:28` guards report generation and prerequisite preparation. Missing workflows or YAML parsing failures leave any previous report in place.
- Step tables link literal `scripts/` paths found in `run` blocks. They cannot infer dynamically assembled commands or paths, or distinguish every shell comment from a command.
- The overview shows declared event and reusable-workflow links. Per-workflow diagrams add `needs` and local action calls. Vector rendering depends on the selected Markdown viewer.
- Flowchart nodes carry same-document links and the arrows name their relations. The `depends on` arrow points from the dependent job to the prerequisite. The diagram links depend on the viewer's Mermaid configuration. The adjacent Markdown links and table of contents support navigation independently. [Mermaid flowchart links](https://mermaid.js.org/syntax/flowchart.html#interaction)

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

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
