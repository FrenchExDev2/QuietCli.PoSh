# GitHub workflows

QuietCli uses GitHub Actions for automation and Mermaid to document the workflow YAML. The map shows which events start each workflow, which jobs depend on one another, and where steps call reusable workflows, local actions or repository scripts. [Open the workflow diagrams](docs/README-github-workflows-diagrams.md)

Each arrow names its relation. An event `triggers` a workflow, a workflow is `composed of` its declared jobs, a dependent job points to its prerequisite with `depends on`, and an invocation is labelled `uses`. Flowchart nodes link to their sections in Mermaid viewers that support clicks. The table of contents, event lists and job links provide the same navigation in viewers that restrict diagram interaction. [Mermaid flowchart links](https://mermaid.js.org/syntax/flowchart.html#interaction)

The `diagrams` job in **QuietCli2 Scripts docs check** regenerates the map for pull requests and pushes to `develop` when a path in `scripts/` or `test/scripts/` changes. Changes to the workflow and action definitions also trigger the job. Each run uploads `github-workflows-diagrams` and checks that its contents match the version in the checkout. The checked-in map keeps its links to YAML and script documentation when browsed on GitHub. [Workflow source](.github/workflows/scripts-docs-check.yml)

To refresh the tracked map locally, run this from the repository root and include the generated file in the change.

```powershell
./scripts/Export-GitHubWorkflowMap.ps1 -OutputPath ./docs/README-github-workflows-diagrams.md
```

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
