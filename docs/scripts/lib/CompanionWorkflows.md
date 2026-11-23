# CompanionWorkflows.psm1

<!-- script-source:begin -->
Source file: [`lib/CompanionWorkflows.psm1`](../../../scripts/lib/CompanionWorkflows.psm1)
<!-- script-source:end -->

## Purpose and usage

Derives explicit companion profiles, renders workflow wrappers and validates caller paths.

```powershell
Get-QuietCompanionProfiles -WorkspaceRoot $checkout
```

## Dependencies and side effects

Grouped workspaces require build/companions.yaml. Isolated legacy flat manifest fixtures without that catalogue declare no workflow profiles.

Before generating workflows, the full-checkout gate verifies that declared source and test directories exist. It then checks companion images with `Assert-QuietCiCompanionImages`. A companion either has no CI image (`image: none`, without `ci/Get-CiImageArguments.ps1`) or is an `overlay` of its parent image, with that contract. The generated workflows warm only overlay images, so any other combination fails before a profile is rendered. [CiCompanions.psm1](CiCompanions.md)

Product qualification remains in ci.yml; workspace-only components use workspace-component-ci.yml. Tooling keeps its existing full qualification workflow. Profile parameters are identical for individual callers and the automatic matrix. New product groups require catalogue registration.

## Critical review

- The implementation in scripts/lib/CompanionWorkflows.psm1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Derives explicit workflow parameters from discovered groups and the qualification catalogue.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
