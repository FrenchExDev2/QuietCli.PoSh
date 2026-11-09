# Credits and syncing

Why QuietCli2 ships a generated [`CREDITS.md`](../CREDITS.md), how the two sync scripts and their
two companion GitHub workflows keep it and every document's credits footer correct, and how to run
the sync locally.

## Why

QuietCli2 drives native third-party executables (`git`, `vagrant`, the .NET/PowerShell host) from
business modules that each have their own lifecycle. Two separate obligations follow from that:

- **The license itself must stay attributed.** Each business module (`Core`, `Git`, `Vagrant` -
  never a `.Tests` companion) ships a `LICENSE_CREDITS.md` declaring the license of the native
  dependency it drives, with reference links. This is part of the module contract, alongside its
  manifest and declared test companion - see [AGENTS.md](../AGENTS.md)'s
  `module-license-credits` block.
- **Every document must point back to it.** Every `docs/*.md` file and every root
  `README.md`/`README-*.md` file must end with a paragraph linking the mandatory
  [`CREDITS.md`](../CREDITS.md) - see [AGENTS.md](../AGENTS.md)'s `docs-credits` block.

Both obligations are enforced the same way: a script that recomputes the expected content, compares
it against what is on disk, and only writes when told to. Neither script ever reads `CREDITS.md` (or
a document's existing footer) as a source of truth - the business modules and the docs/README files
on disk are the only inputs, so staleness cannot silently compound across reruns.

## How: the two scripts

### [`scripts/Sync-Credits.ps1`](../scripts/Sync-Credits.ps1)

Discovers every business module via `Get-QuietWorkspaceProjects` (from
[`scripts/WorkspaceProjects.ps1`](../scripts/WorkspaceProjects.ps1)), reads each one's
`LICENSE_CREDITS.md`, and rebuilds the root `CREDITS.md`: a short mandatory preamble, a
table of contents (so the file stays navigable as more modules ship their own credits), then each
module's content wrapped in its own regex-identifiable marker:

```markdown
<!-- module-credits:Git:begin -->
## Git
...
<!-- module-credits:Git:end -->
```

- No arguments: reports each module's and the root file's compliance (`Missing` / `Stale` /
  `UpToDate`) and writes nothing. Throws (non-zero exit) if anything is non-compliant - this is what
  the check workflow runs.
- `-Apply`: writes the regenerated `CREDITS.md` when it is missing or stale.
- `-Apply -WhatIf`: previews exactly what `-Apply` would write, without writing it.
- A module missing its `LICENSE_CREDITS.md` is a hard failure (`ModuleLicenseCreditsMissing`), not a
  silently skipped entry.

### [`scripts/Sync-DocsCredits.ps1`](../scripts/Sync-DocsCredits.ps1)

Scans every `docs/**/*.md` file by default, including the `agents`, `audits` and `ci` subfolders
(pass `-NoRecurse` to check only `docs/*.md`'s direct children), and every root
`README.md`/`README-*.md`, and checks each one for a regex-identifiable footer:

```markdown
<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
```

The two distributed files `docs/agents/AGENTS.md` and `SKILL.md` use an absolute public GitHub
credits URL so their links survive copying into consumer projects. Other documents use a link
computed per file with `[System.IO.Path]::GetRelativePath`, so it stays correct
regardless of how deep the document lives under `docs/`.

- No arguments: reports each file's compliance and writes nothing. Throws if anything is
  non-compliant.
- `-Apply`: writes the missing or stale block into every non-compliant file.
- `-Apply -WhatIf`: previews that write without touching any file.

## How: running it locally

From the workspace root (`PoSh/FrenchExDev/QuietCliEcosystem/FrenchExDev2.QuietCli.PoSh`):

```powershell
# Report only - what the check workflow runs, safe to run anytime.
./scripts/Sync-Credits.ps1
./scripts/Sync-DocsCredits.ps1

# Preview exactly what applying would write, without writing it.
./scripts/Sync-Credits.ps1 -Apply -WhatIf
./scripts/Sync-DocsCredits.ps1 -Apply -WhatIf

# Write the fix.
./scripts/Sync-Credits.ps1 -Apply
./scripts/Sync-DocsCredits.ps1 -Apply
```

Run `Sync-Credits.ps1` first: if a document's relative path to `CREDITS.md` changes (for example a
module is renamed), `Sync-DocsCredits.ps1` needs the new `CREDITS.md` location in place to compute
correct links. Both scripts are idempotent - rerunning either after it reports `UpToDate` writes
nothing and changes nothing.

A new or renamed `docs/*.md` or root `README*.md` file, and a new or changed business module's
`LICENSE_CREDITS.md`, must pass both scripts' `-Apply` before being committed.

## The two workflows

### [`sync-credits-check.yml`](../.github/workflows/sync-credits-check.yml)

Report-only, read-only (`permissions: contents: read`). Runs both scripts without `-Apply`, so it
fails the run if anything is missing or stale. Triggers on `pull_request` and on `push` to `main`,
both path-filtered to `docs/**`, `README*.md`, `**/LICENSE_CREDITS.md`, `CREDITS.md`, the two sync
scripts and `WorkspaceProjects.ps1`; also available on `workflow_dispatch` for an ad hoc check. This
is the gate: it never writes, so it is safe to run automatically on every pull request.

### [`sync-credits-apply.yml`](../.github/workflows/sync-credits-apply.yml)

`workflow_dispatch` only - it never runs on `pull_request` or `push`. Running it is the explicit,
human-triggered approval to write and push, consistent with this repository's rule that no commit or
push is implicit in an automated run. It runs both scripts with `-Apply`, then, only if that produced
an actual diff, commits (`github-actions[bot]` identity) and pushes straight to the branch the run
was dispatched on (`HEAD:${{ github.ref }}`) - never to a hardcoded branch, and never with `--force`.
If there is nothing to commit, the step says so and the run ends cleanly without pushing.

Use it from the Actions tab, on the branch that needs fixing, whenever the check workflow has failed
and the fix is exactly "regenerate what these scripts generate" - never for a change to the credits
system's own templates or wording, which belongs in the scripts themselves.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
