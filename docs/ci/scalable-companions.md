# Scalable companion qualification

Existing FrenchExDev PowerShell modules are applications. Each can consume QuietCli Core plus an independently generated and tested companion for its native executable. They are not automatically QuietCli companions.

Localhost supports Podman (discovered first when no explicit adapter or dotenv selection exists) and Docker. GitHub CI explicitly selects Docker. The new BuildKit intermediate-cache path applies only to Docker CI jobs; it changes no local Podman behavior and starts no local daemon automatically.

Core.Tests requires Core only. Its scaffolding regression generates a scripted git-status companion and asserts clean/untracked Unicode fixtures without importing the real Git module. Git remains an executable test tool. Git reference-case and private artifact security regressions belong to Git.Tests. Tooling.Tests owns repository build, commit, packaging and source checks.

PR CI plans from the complete no-rename diff and transitive build/companions.yml requirements. A companion-only change qualifies that suite across supported environments; Core/shared/unknown changes conservatively select All. Several impacted companions share one matrix. Core runs first in All, then independent companions use bounded processes on the same image. Private test metadata remains owned by each test .psm1/manifest. Tests sharing engine state and timing samples keep ordered/exclusive barriers.

Build-Workspace -Suite selects test modules and transitive RequiredModules, then builds a scoped solution once. Undeclared cross-project references fail before compilation. Portable publication uses --no-build; matrix rows publish only their tested RID. The tooling job builds all required IL distributions once. Private Distribution.Tests owns the three architecture, Gallery installation and packaged Recall cases; the tooling job reuses verified Core/Core.Tests outputs in a Git-absent checkout without another build. Native Core qualification no longer packages all RIDs in every environment.

Docker caches verified final GHCR images by input fingerprint. On misses, GitHub also restores/exports BuildKit intermediate stages with mode=max, separate image/architecture scopes and stable recipe keys with fallback to earlier recipes. The builder for the active Docker context uses the containerd image store so a locally built Core parent remains available to companion overlays. Intermediate caches are saved immediately after image preparation, before tests. Rotation avoids accumulating obsolete blobs. Podman behavior and PR nonpublication remain intact. The cache contains toolchains, never workspace sources or credentials. See [Docker cache backends](https://docs.docker.com/build/cache/backends/).

Tooling runs once outside the ten product environments. RunProfiles functional checks and mutation run on separate runners from product profiling. Mutation requires its green baseline, then runs at most two isolated worker/sandbox pairs; only Killed is accepted. Per-environment PowerShell/CLR reports remain mandatory for Core qualification. The manual ReadyToRun A/A and A/B workflow keeps its existing explicit dispatch.

After a develop merge, successful PR evidence may replace matrix replay only when its Git tree exactly matches the merged commit and its authoritative workflow attempt succeeded. Missing, expired, old-format or mismatched evidence requires full All validation. Reuse still runs merged source-lock/Core integration smoke and resolves or updates native image caches. No Gallery publication occurs on develop.

Configure branch protection or a ruleset separately to require **QuietCli required CI**, the documentation checks, an up-to-date branch, and no direct develop pushes. The workflow does not change repository settings. Full module-tag release qualification and current-run exact-SHA publication receipts remain separate from develop reuse.

## Evidence limits

Local focused tests are partial evidence. The complete Windows/ARM64/Linux matrix, hosted intermediate-cache transfers and same-tree GitHub reuse are established only by their resulting workflow artifacts. No download reduction or elapsed-time percentage is asserted before those runs.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
