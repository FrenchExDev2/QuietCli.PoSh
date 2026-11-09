# Every script has a doc

Why every file under `scripts/` must have a matching Markdown doc under `docs/scripts/`, how
[`scripts/Sync-ScriptsReadme.ps1`](../scripts/Sync-ScriptsReadme.ps1) gates that and generates the
navigable index at [`docs/scripts/README.md`](scripts/README.md), and how its two companion GitHub
workflows keep that index correct.

## Why

`scripts/` has grown into dozens of orchestration scripts and `lib/` modules (CI image builds,
cold-start profiling, workstation provisioning, release packaging, test monitors, ...). A script with
no documentation is a script nobody can safely change or retire: its parameters, side effects,
dependencies and known gaps live only in its author's head. The rule is simple and absolute:

- Every `scripts/*.ps1`, `scripts/*.psm1`, and every file under a `scripts/` subdirectory (`lib/`,
  `RunProfiles/`, and any future one), must have a Markdown doc under `docs/scripts/`, mirroring its
  subdirectory: `scripts/lib/Foo.psm1` is documented at `docs/scripts/lib/Foo.md`,
  `scripts/RunProfiles/bar.profile.ps1` at `docs/scripts/RunProfiles/bar.profile.md`, and a root
  `scripts/Baz.ps1` at `docs/scripts/Baz.md`.
- That doc must be reachable from [`docs/scripts/README.md`](scripts/README.md) - the single table of
  contents a reader starts from. A doc nobody can find from the index does not count as documented.
- Each doc documents the script's purpose, usage/parameters, dependencies, side effects, and - this is
  the part that actually earns its keep - a critical **Findings** review: bugs, convention violations
  (against this repository's [`AGENTS.md`](../AGENTS.md)), design smells, missing validation, and
  test-coverage gaps, each with concrete file:line references. A doc that only restates what the code
  already says is not a review.

This is enforced the same way the [credits sync system](README-credits-and-syncing.md) is: a script
that recomputes the expected index from what is actually on disk (every script under `scripts/`, every
doc under `docs/scripts/`) and only writes when told to. It never trusts the existing
`docs/scripts/README.md` as a source of truth, so staleness cannot silently compound across reruns.

## How: the script

### [`scripts/Sync-ScriptsReadme.ps1`](../scripts/Sync-ScriptsReadme.ps1)

Scans every `*.ps1`/`*.psm1` under `scripts/` recursively (excluding itself), computes each one's
mirrored doc path under `docs/scripts/`, and renders `docs/scripts/README.md` as a table of contents
grouped by subdirectory (`Root scripts`, `` scripts/lib/ ``, `` scripts/RunProfiles/ ``, and any future
subdirectory - the grouping is generic, not hardcoded to today's two), each entry linking the script
and its doc.

- No arguments: reports compliance and writes nothing.
  - Throws `ScriptsDocsMissing` the moment any script has no doc - this is the actual gate, and it
    fires whether or not `-Apply` is passed. A missing doc is never silently tolerated.
  - Otherwise throws `ScriptsReadmeNonCompliant` if `docs/scripts/README.md` is missing or stale
    (a script was added, removed, or moved to a different subdirectory since it was last generated).
  - This is what the check workflow runs.
- `-Apply`: writes the regenerated `docs/scripts/README.md` when it is missing or stale. Still throws
  `ScriptsDocsMissing` first - `-Apply` can fix a stale index, it cannot invent a missing review.
- `-Apply -WhatIf`: previews exactly what `-Apply` would write, without writing it.
- The generated file already carries the mandatory [`CREDITS.md`](../CREDITS.md) footer (see
  [credits and syncing](README-credits-and-syncing.md)), computed with the same regex-identifiable
  block `Sync-DocsCredits.ps1` expects, so the two systems never fight over this one file.

## How: running it locally

From the workspace root (`PoSh/FrenchExDev/QuietCliEcosystem/FrenchExDev2.QuietCli.PoSh`):

```powershell
# Report only - what the check workflow runs, safe to run anytime.
./scripts/Sync-ScriptsReadme.ps1

# Preview exactly what applying would write, without writing it.
./scripts/Sync-ScriptsReadme.ps1 -Apply -WhatIf

# Write the fix.
./scripts/Sync-ScriptsReadme.ps1 -Apply
```

When the check throws `ScriptsDocsMissing`, the fix is to write the missing script's doc under
`docs/scripts/` (mirroring its subdirectory) - covering purpose, usage, dependencies, side effects, a
critical **Findings** review and a **Verdict** - then rerun `-Apply`. `-Apply` alone never resolves
that failure; it only resolves `ScriptsReadmeNonCompliant` once every doc already exists.

A new script, a renamed script, or a script moved to a different `scripts/` subdirectory must pass
`-Apply` before being committed.

## The two workflows

### [`scripts-docs-check.yml`](../.github/workflows/scripts-docs-check.yml)

Report-only, read-only (`permissions: contents: read`). Runs `Sync-ScriptsReadme.ps1` without
`-Apply`, so it fails the run if any script has no doc or the index is stale. Triggers on
`pull_request` and on `push` to `main`, both path-filtered to `scripts/**`, `docs/scripts/**` and the
two workflow files; also available on `workflow_dispatch` for an ad hoc check. This is the gate: it
never writes, so it is safe to run automatically on every pull request.

### [`scripts-docs-apply.yml`](../.github/workflows/scripts-docs-apply.yml)

`workflow_dispatch` only - it never runs on `pull_request` or `push`. Running it is the explicit,
human-triggered approval to write and push, consistent with this repository's rule that no commit or
push is implicit in an automated run. It runs `Sync-ScriptsReadme.ps1 -Apply`, then, only if that
produced an actual diff, commits (`github-actions[bot]` identity) and pushes straight to the branch
the run was dispatched on (`HEAD:${{ github.ref }}`) - never to a hardcoded branch, and never with
`--force`. If there is nothing to commit, the step says so and the run ends cleanly without pushing.

It cannot fix a missing doc - only the index's own staleness. Use it from the Actions tab, on the
branch that needs fixing, once every script already has its doc and the only remaining failure is
`ScriptsReadmeNonCompliant`.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
