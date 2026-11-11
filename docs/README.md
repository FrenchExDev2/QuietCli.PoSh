# QuietCli documentation

Start with the [product README](../README.md) for installation, requirements and a first command. This index links the usage guides, technical contracts, CI instructions and dated evidence available in this repository.

## Usage guides

- [.NET SDK installation and global.json updates](../README-dotnet-and-global-dot-json.md): release checks, verified portable SDKs, optional images and backed-up SDK pins.

- [Streaming, callbacks and results](../README-streaming.md): build business projections and interpret outcome, execution and completeness.
- [Recall](../README-recall.md): capture native evidence explicitly and analyze it again without rerunning the command.
- [Hosting and native transports](../README-hosting.md): choose engine hosting and understand pipes and PTY.
- [Configuration](../README-configuration.md): configure QuietCli through YAML and the supported environment override.
- [Measurements and privacy](../README-measurements.md): interpret measured volumes, delivery budgets and retention boundaries.
- [QuietCli with AI agents](../README-agents.md): install production instructions for an agent.
- [Companion modules](../README-modules.md): register reusable executable handlers and define their support boundaries.
- [PowerShell Gallery installation](README-PSGallery.md): install packages and check runtime and platform requirements.

## Agent instructions and examples

The [agent documentation index](agents/README.md) identifies distributed instructions, generated files and repository-only guides, including their editing rules.

- [Production instructions](agents/AGENTS.md) and [generated skill form](agents/SKILL.md).
- [Codex](agents/codex.md) and [Claude Code](agents/claude.md) integration guides.
- [Extended examples](agents/examples.md): projections, measured gains, Recall and evidence transfer.
- [Non-Git example](agents/non-git-example.md): analyze installed .NET SDKs with explicit callbacks.
- [Persistent PowerShell process](agents/persistent-shell.md): retain a session across agent tool calls.
- [Troubleshooting](agents/troubleshooting.md): investigate loading errors, failed results and incomplete evidence.

## Technical contracts and boundaries

- [Configuration and unique tokenized deliveries](README-configuration.md): configuration schema, delivery identity and token measurements.
- [Recall contract](README-recall.md): memory capture, durable journals, recovery, offline analysis and optional ZIP64 transport.
- [Compiled framing and direct engine hosting](README-performance-and-hosting.md): compatible hosts, framing boundaries and measurement reproduction.
- [PowerShell and C# boundaries](README-powershell-csharp-boundaries.md): responsibilities retained in PowerShell and moved into compiled components.
- [Allocation costs and actual delivery gains](README-allocation-and-delivery-metrics.md): allocation intervals, serialization measurements and unknown values.
- [Privacy and integrity internals](README-privacy-and-integrity-internals.md): what timeouts, closed-DTO projection, the explicit scrub and resource verification concretely do, and how a companion module could plug into them.
- [Native PTY bridge and LLVM fuzzing findings](README-native-pty-and-llvm-fuzzing.md): resize protocol, qualification layers and recorded sanitizer findings.
- [Why `quiet` stays a PowerShell module, not a native binary](README-why-not-native.md): ScriptBlock callbacks, native tab-completion glue and the `InProcess` zero-serialization contract.

## Development, CI and distribution

- [CI companions and independent integration suites](scripts/lib/CiCompanions.md): YAML declarations,
  dependency expansion, image composition and shared script entry points.
- [Add a companion](../README-add-companion.md): product/test projects, Vagrant, dedicated integration
  runners, image tooling, checks and qualification boundaries.

Repository development follows the root [AGENTS.md](../AGENTS.md). Consumer-project agent instructions are documented separately in the [agent index](agents/README.md).

- [Development](../README-development.md): source checkout, prerequisites and builds.
- [Local scriptblock launcher](scripts/Invoke-Quiet.md): load checkout Core and run `-Code { param($runtime) ... }` in the current process.
- [Resources](../README-resources.md): pinned payload preparation, optional archive caches and the [generated inventory and code dependencies](resources/README.md).
- [Automation requirements as code](README-automation-contracts.md): workflow receipts, shared commit checks, script logging policy and the [complete preview review](scripts/preview-support.md).
- [Projects, suites and package eligibility](README-workspace-projects.md): reusable manifest discovery, dynamic suite parameters and explicit public-package policy.
- [Development workstation](../README-development-workstation.md): platform-specific installations and the host-aware prerequisite installer, including VS Code Stable/Insiders.
- [Local workflows with wrkflw](scripts/README-wrkflw-plan.md): pinned workstation integration, released capabilities and the explicit backlog of PowerShell usage helpers.
- [CI execution model](ci/execution-model.md): direct and indirect Podman dependencies, GitHub/local boundaries, image identity and known adaptation gaps.
- [Deterministic local/GitHub environment](ci/environment.md): dotenv editing, runtime precedence, generated presets and the RAC-ENV-001 contract.
- [Editor extensions](README-development-editor-extensions.md): export the installed inventory and install/update the saved set in Stable or Insiders with `-WhatIf` and `-Update`.
- [Tests and qualification](../README-qualification.md): companion suites, property testing, fuzzing, mutation campaigns and qualification limits.
- [Qualification: when, where and how](../README-qualification-when-where-how.md): PR path filters, Windows hosts, Linux job containers/Docker fallback, actual test execution, local entry points and excluded scopes.
- [Commit-suite boundaries and PSDrive feasibility](testing/commit-workspace.md): optional local campaigns, integration labels, physical Git fixtures and pure logic separation.
- [Repository and distribution](../README-distribution.md): monorepo layout, packaging and publication gates.
- [Credits and syncing](README-credits-and-syncing.md): why `CREDITS.md` is generated, the two sync scripts, their check/apply workflows and how to run the sync locally.
- [Every script has a doc](README-scripts-have-docs.md): the `docs/scripts/` documentation gate, the generated [index](scripts/README.md), and its check/apply workflows.
- [Linux CI images](ci/linux-images.md): native architecture builds, GHCR cache, toolchain integrity and permissions.
- [Container runtime diagnosis](README-container-runtime-diagnosis.md): distinguish image startup configuration from raw-RID native-resource selection using isolated, monitored controls.
- [Module-specific CI containers](README-module-specific-ci-container.md): the reusable contract a Core-consumer module (for example Git) uses to build its own derived CI image on top of Core's.
- [Windows ARM64 CI](ci/windows-arm64.md): runner identity, engine publications and architecture checks.
- [Preview versions and GitHub publication](README-preview-releases.md): version identities, local tags, artifact preparation and publication receipts.

## Performance and profiling

- [Core performance evidence](../FrenchExDev2.QuietCli.Core.PoSh/PERFORMANCES.md): measurement definitions, controlled workloads and reproduction.
- [Run profiles](README-run-profiles.md): named measurement campaigns, profiling tools and tooling qualification.
- [Cold-start A/B testing](README-ab_testing.md): paired measurements, A/A controls and interpretation of statistical verdicts.
- [ReadyToRun cold-start profiling](README-readytorun_profiling.md): prepare a separate candidate and compare it with the baseline.

## Dated audits and evidence

These reports describe their recorded revisions, environments and executed scopes. They do not qualify a later revision or replace the current qualification requirements.

- 4 November 2026: [security and software design audit](audits/2026-11-04-securite-logiciel.md), [remediation report](audits/2026-11-04-remediation.md) and [evidence JSON](audits/2026-11-04-evidence.json).
- 5 November 2026, Core: [extraction before Git](audits/2026-11-05-core-before-git.md), [Core then Git with PTY](audits/2026-11-05-core-then-git.md), [second C# pass](audits/2026-11-05-csharp-second-pass.md), [integrated hosting](audits/2026-11-05-integrated-hosting.md), [typed controls](audits/2026-11-05-typed-controls.md), [PTY streams](audits/2026-11-05-pty-streams.md) and [remediation evidence JSON](audits/2026-11-05-remediation-evidence.json).
- 5 November 2026, Git: [principal commands](audits/2026-11-05-git-principal-commands.md), [object, ref and file queries](audits/2026-11-05-git-queries.md), [revision queries](audits/2026-11-05-git-revisions.md), [path queries](audits/2026-11-05-git-path-queries.md), [reflog, blame and annotate](audits/2026-11-05-git-attribution.md), and [push extraction and apphost staging](audits/2026-11-05-git-push-csharp.md).
- 7 November 2026: [run-profile tests and mutation audit](audits/2026-11-07-run-profiles.md).
- 8 November 2026: [Core frame codec](audits/2026-11-08-core-frame-codec.md), [ecosystem usage and gap review](audits/2026-11-08-ecosystem-usage-review.md), and [run-profile tooling qualification](audits/2026-11-08-run-profile-qualification.md).
- 8 November 2026, execution continuation: [Emit/listeners, Vagrant and dynamic workspace/package catalogues](audits/2026-11-08-emit-listeners-and-vagrant.md).
- 9 November 2026: [real Vagrant provider, interactive UI and stable/preview qualification](audits/2026-11-09-provider-ui-qualification.md).
- 9 November 2026: [container runtime/bootstrap and RID resource diagnosis](audits/2026-11-09-container-runtime-diagnosis.md).
- 9 November 2026: [Alpine recipe correction, rebuilt image and default-host/SDK smoke](audits/2026-11-09-alpine-image-recipe.md).

## Automation contracts

- [Workflow documentation and preview-safety requirements](README-automation-contracts.md)
- [GitHub workflow index and generated Mermaid graphs](ci/github/README.md)

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
