# QuietCli repository tooling tests

Performance aggregation scope is checked as a restricted boolean condition over cache-only mode, explicit profiling and the selected Core scope. Sixteen combinations and four removed-guard mutants replace an exact-text assertion, retaining profiling for Core qualification and `always()` for failure diagnostics while rejecting cache warm-up as qualification evidence. No workflow expression is evaluated before token validation.

This private test companion owns repository automation qualification, independently of the Core product matrix.
It is never published to PowerShell Gallery. Its own manifest declares its runner, complete test metadata and execution policy.

Distribution.Tests separately owns the three complete Core distribution cases. The same tooling job runs them once in an owned Git-absent checkout with verified reused binaries; product matrix rows keep their native RID.

`./scripts/Invoke-WorkspaceCi.ps1 -Suite Tooling -SkipBuild` runs the complete tooling catalogue with the visible local monitor.
Use `-Case '<wildcard>'` for an explicitly partial development run.
The `CI scales by affected suites with verified merge reuse and intermediate caches` case also exercises GitHub release publication offline: preview/stable versions and varied binary sizes, tag/asset identity, draft-before-upload-before-publish, six policy mutants, foreign workflow contexts, failed/mismatching Gallery receipts and ordered batches. GalleryPreview retains the same lifecycle case. No fixture uses credentials or publishes remotely.
The `CI scales by affected suites with verified merge reuse and intermediate caches` case also checks the Linux NuGet cache lifecycle. Restore-only resolves the OS/architecture/dependency key before build/tests; a final save-only action reuses `cache-primary-key` after success and without an exact hit. Thirty-two decision properties accept equivalent boolean forms. Eleven damaged workflows cover the historical combined post-job action, late hash recomputation, matched-key reuse, changed paths/order/inputs/pins and unsafe or weakened save conditions. This is a workflow contract regression; it does not execute GitHub's container cleanup phase.
The `GitHub CI separates native containers, Docker fallback and workstation launchers` case includes an offline publication regression derived from the shared Docker setup action. Eight scenarios cover the four Linux RIDs with and without BuildKit caching, checking daemon identity across private registry credentials, exact image tags, digest receipts and credential cleanup. Omitting `set-host: true` reproduces `DockerPublicationChangedDaemon`. This evidence does not execute a Docker daemon or publish an image.

The same case exercises registry HTTP processing for single-image manifests, OCI indexes, Docker manifest lists and nested indexes. Seed `20261113` varies platform/descriptor order and leaf format across 128 valid properties. The malformed corpus checks altered root/configuration bytes, missing/ambiguous platforms and references, server errors, digest syntax, JSON, schema and media types. Targeted mutants remove index negotiation, force the wrong architecture, replace the root digest with a child digest and bypass content verification. Requests use an in-memory HTTP handler; no image layers, credentials or live registry are needed.

Product `All` discovers Core, Git and Vagrant; the CI gate separately requires the tooling workflow when shared sources change.
Private assertion helpers remain in Core.Tests and are invoked in that module's scope; ownership of the literal catalogue belongs here.

The `GitHub CI excludes native TTY campaigns and has no dangling job dependencies` case checks profiler prerequisites separately for the two workflows: product preparation requires Core and explicit profiling; Tooling always prepares both pinned tools before its functional RunProfiles step. Equivalent boolean expressions and reordered literal tool lists are accepted. The `CI failure regressions reject empty Docker parents and skipped profiling uploads` case retains seed 20261112, generated scope properties, malformed-condition rejection and damaged-workflow mutations for this contract. Select these exact case names for a focused local regression; `CI *` does not include the first name.

Each existing FrenchExDev PowerShell module is an application consumer. It can use Core and the separately generated companion for its executable.
An application module does not become a QuietCli companion merely because it uses QuietCli.
