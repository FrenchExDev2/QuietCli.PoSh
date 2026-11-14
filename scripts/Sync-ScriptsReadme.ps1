#requires -Version 7.6
<#
.SYNOPSIS
Documentation gate: checks or writes docs/scripts/README.md, the table of contents that links every
script under scripts/ to its documentation file.
.DESCRIPTION
Every script or profile file under scripts/ (*.ps1, *.psm1, *.profile.psd1, recursively) must have a matching Markdown doc
under docs/scripts/, mirroring its subdirectory - scripts/lib/Foo.psm1 is documented at
docs/scripts/lib/Foo.md, scripts/RunProfiles/bar.profile.psd1 at docs/scripts/RunProfiles/bar.profile.md,
and a root scripts/Baz.ps1 at docs/scripts/Baz.md. This script never authors that content itself -
each doc is written by whoever reviews the script - but it is both the gate that fails the moment one
is missing and the generator of docs/scripts/README.md, the navigable index grouping every documented
script by its subdirectory.

Default (no -Apply) mode only reports: it throws ScriptsDocsMissing the moment any script has no doc,
and otherwise throws ScriptsReadmeNonCompliant if docs/scripts/README.md is missing or stale. It never
writes. -Apply regenerates docs/scripts/README.md when stale, honoring -WhatIf/-Confirm through
SupportsShouldProcess - but it still throws ScriptsDocsMissing first: a missing doc is never silently
tolerated, Apply or not, because the index cannot claim full coverage while it is false.
.PARAMETER ScriptsPath
Directory scanned for *.ps1/*.psm1 files, recursively. Defaults to this script's own directory
(scripts/). Includes this script, which has its own mirrored documentation.
.PARAMETER DocsPath
Directory the table of contents (README.md) is read from/written to, and under which each script's
mirrored doc is expected. Defaults to docs/scripts under this repository root.
.PARAMETER Apply
Writes docs/scripts/README.md when it is missing or stale. Without this switch the script only
reports and writes nothing.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1
Reports documentation-coverage gaps and whether docs/scripts/README.md is up to date; writes nothing.
This is what the check workflow runs.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1 -Apply -WhatIf
Previews exactly what -Apply would write, without writing it.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1 -Apply
Writes docs/scripts/README.md when it is missing or stale.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ScriptsPath = $PSScriptRoot,
    [string]$DocsPath = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'docs/scripts')),
    [switch]$Apply
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Sync-ScriptsReadme.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptSyncScriptsReadme @PSBoundParameters
