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

Default mode checks documentation coverage, source links and index freshness without writing.
-Apply synchronizes the index and the managed link from each document to its source file.
Both modes reject missing documents. Apply supports -WhatIf and -Confirm.
.PARAMETER ScriptsPath
Directory scanned for *.ps1, *.psm1 and *.profile.psd1 files, recursively. Defaults to this script's own directory
(scripts/). Includes this script, which has its own mirrored documentation.
.PARAMETER DocsPath
Directory the table of contents (README.md) is read from/written to, and under which each script's
mirrored doc is expected. Defaults to docs/scripts under this repository root.
.PARAMETER Apply
Updates docs/scripts/README.md and the source links in existing mirrored documents.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1
Reports documentation-coverage gaps and whether docs/scripts/README.md is up to date; writes nothing.
This is what the check workflow runs.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1 -Apply -WhatIf
Previews exactly what -Apply would write, without writing it.
.EXAMPLE
./scripts/Sync-ScriptsReadme.ps1 -Apply
Synchronizes docs/scripts/README.md and links from the documents to their source files.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ScriptsPath = $PSScriptRoot,
    [string]$DocsPath = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'docs/scripts')),
    [switch]$Apply
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Sync-ScriptsReadme.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptSyncScriptsReadme @PSBoundParameters
