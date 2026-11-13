# QuietCli repository tooling tests

Performance aggregation scope is checked as a restricted boolean condition over cache-only mode, explicit profiling and the selected Core scope. Sixteen combinations and four removed-guard mutants replace an exact-text assertion, retaining profiling for Core qualification and `always()` for failure diagnostics while rejecting cache warm-up as qualification evidence. No workflow expression is evaluated before token validation.

This private test companion owns repository automation qualification, independently of the Core product matrix.
It is never published to PowerShell Gallery. Its own manifest declares its runner, complete test metadata and execution policy.

Distribution.Tests separately owns the three complete Core distribution cases. The same tooling job runs them once in an owned Git-absent checkout with verified reused binaries; product matrix rows keep their native RID.

`./scripts/Invoke-WorkspaceCi.ps1 -Suite Tooling -SkipBuild` runs the complete tooling catalogue with the visible local monitor.
Use `-Case '<wildcard>'` for an explicitly partial development run.
The `GitHub CI separates native containers, Docker fallback and workstation launchers` case includes an offline publication regression derived from the shared Docker setup action. Eight scenarios cover the four Linux RIDs with and without BuildKit caching, checking daemon identity across private registry credentials, exact image tags, digest receipts and credential cleanup. Omitting `set-host: true` reproduces `DockerPublicationChangedDaemon`. This evidence does not execute a Docker daemon or publish an image.
Product `All` discovers Core, Git and Vagrant; the CI gate separately requires the tooling workflow when shared sources change.
Private assertion helpers remain in Core.Tests and are invoked in that module's scope; ownership of the literal catalogue belongs here.

The `GitHub CI excludes native TTY campaigns and has no dangling job dependencies` case checks profiler prerequisites separately for the two workflows: product preparation requires Core and explicit profiling; Tooling always prepares both pinned tools before its functional RunProfiles step. Equivalent boolean expressions and reordered literal tool lists are accepted. The `CI failure regressions reject empty Docker parents and skipped profiling uploads` case retains seed 20261112, generated scope properties, malformed-condition rejection and damaged-workflow mutations for this contract. Select these exact case names for a focused local regression; `CI *` does not include the first name.

Each existing FrenchExDev PowerShell module is an application consumer. It can use Core and the separately generated companion for its executable.
An application module does not become a QuietCli companion merely because it uses QuietCli.
