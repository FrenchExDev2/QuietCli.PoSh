# Scalable companion qualification

[Source-change landmarks](README.md#source-change-landmarks) identify the changes through 12 November 2026. The design reduces repeated preparation while retaining declared suites, targets and acceptance criteria. Elapsed-time and cache-transfer gains require hosted measurements.

## Select only the required work

[New-CiImpactPlan](../scripts/New-CiImpactPlan.md) uses the complete no-rename diff and transitive `build/companions.yml` requirements. A companion change qualifies its owning group; Core changes qualify Core plus dependent smokes. ProjectReference edges select dependent builds. PackageReference consumers and inherited props/targets select the projects affected by central XML changes. Unknown shared paths use an explained conservative fallback. Several affected groups share one matrix. Reviewed run-profile command/store/definition paths select tooling only; shared profiler, encoding, report and build changes still require All. Mixed paths union requirements.

Core.Tests depends only on Core. Its scaffolding fixture generates a scripted Git-status companion; Git remains an executable tool without importing the real Git module. Tooling.Tests owns repository automation. Distribution.Tests owns the architecture, installed-package and packaged-Recall checks executed once in tooling. Existing FrenchExDev application modules are consumers; membership does not qualify their CLI semantics.

[Build-Workspace](../scripts/Build-Workspace.md) compiles the selected dependency closure once, rejects undeclared project references and publishes portable outputs with `--no-build`. Product rows publish their tested RID. Tooling prepares all required IL distributions once and reuses verified Core/Core.Tests outputs for Distribution in an owned Git-absent checkout. Release packaging retains its separate all-RID ReadyToRun build.

```mermaid
flowchart TD
    S[Selected product scope] --> B[One dependency-closure build per target]
    B --> C{All selected?}
    C -- Yes --> CORE[Complete Core suite]
    CORE --> FAN[Bounded independent companion workers]
    C -- No --> ONE[Selected companion runner]
    TOOL[Separate tooling workflow] --> TB[Full IL build and automation tests]
    TB --> DIST[Distribution once using verified outputs]
    IND[Separate Git-absent checkout] --> CT[Core build and full suite]
```

## Bound mutation concurrency

Tooling functional checks and mutation run on different runners from product measurements. The run-profile catalogue contains 92 mutants. Two matrix shards select entries by ordinal modulo two, with a green baseline and at most two isolated worker/sandbox pairs **per shard**. Thus this campaign can have four mutation workers across its two runners. Local defaults retain one full-catalogue campaign.

```mermaid
flowchart TD
    CAT[Inert source-controlled catalogue] --> A[Shard 0: 46 mutants]
    CAT --> B[Shard 1: 46 mutants]
    A --> BA[Green baseline then at most two workers]
    B --> BB[Green baseline then at most two workers]
    BA --> RA[Partial shard report]
    BB --> RB[Partial shard report]
    RA --> JOIN[Same SHA and attempt artifact download]
    RB --> JOIN
    JOIN --> V[Verify source hashes, settings and exact disjoint union]
    V --> OK[Complete: all 92 Killed]
```

[Assert-RunProfileMutationShards](../scripts/Assert-RunProfileMutationShards.md) rejects missing/duplicate names, stale revisions, different inputs/settings, failed baselines and every outcome other than Killed. Shard success alone does not satisfy the tooling workflow. Fixed qualification settings remain seed 61207 and 120 iterations.

The [GitHub entry boundary](../scripts/Invoke-GitHubCi.md#shard-execution-and-completion) validates each partition and retains Partial=true. It rejects incomplete/filtered product runs and cannot replace the completion job. Source-bound local entry regressions use synthetic worker reports; actual hosted scheduling remains separate evidence.

Git's nine opt-in compiled mutation catalogues use independent processes, capped at two concurrent catalogues. Each owns a build tree, restores dependencies once, resets pristine sources for every mutant and forces compilation with `--no-incremental --no-restore` after its baseline restore. Each mutant executes the full assertion runner. Shared-repository cases and timing samples retain their ordered/exclusive barriers. See [classification and concurrency](../README-test-classification-and-concurrency.md).

## Reuse images and qualification evidence

Docker first probes the verified final GHCR fingerprint. A final-image hit avoids intermediate-cache transfer; a miss restores BuildKit `mode=max` cache by image/RID/fingerprint and prepares required parents in the same producer job. Cache save precedes tests. GitHub uses Docker; local resolution keeps explicit selection, checkout `.env`, then Podman-first discovery. See [Linux images](linux-images.md).

PR and develop events recompute their selective plans from the complete diff. Build reuse verifies source/payload hashes, configuration and RID slots; it never authorizes omitted qualification. Dedicated group YAML files declare their solution/source/test paths and delegate through uses/with. Cache-only manual dispatch emits no qualification receipt. Develop never publishes Gallery modules.

## Artifacts and acceptance

Ordinary tooling/independence artifacts contain reports, receipts and diagnostic logs, including isolated case reports. They exclude nested workspaces, binaries and packages. A failed functional tooling run additionally uploads its existing fixture trees in a separate seven-day artifact. Mutation artifacts carry the SHA, shard and attempt; the completion job downloads only the current set.

Core qualification still requires per-environment PowerShell/CLR evidence and a successful combined report. The manual ReadyToRun A/A–A/B workflow remains informational. Configure **QuietCli required CI**, documentation checks and branch restrictions separately in repository rules; workflow files do not modify those settings. Release/publication requires its own exact-revision, current-run evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
