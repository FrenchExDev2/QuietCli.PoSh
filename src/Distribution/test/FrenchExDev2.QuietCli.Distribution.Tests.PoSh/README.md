# QuietCli distribution tests

This private test companion owns its literal case metadata and ordered execution policy. It requires Core.Tests only and is never published to PowerShell Gallery.

`Invoke-WorkspaceCi.ps1 -Suite Distribution -SkipBuild` checks all six embedded architectures, installs the public Core nupkg without sources or Git, and verifies packaged Recall development tools including damaged-binary rejection. Every case runs; filtered local runs remain partial.

The Recall regression recreates `artifacts/component/recall-packages` inside an owned source-lookalike
directory with throwing helper sentinels. It checks 33 source-location properties, 32 malformed paths,
kills a workspace-guard mutant, and verifies that
the package rejects its own altered DLL. Reports include `packaged-recall-integrity.json`; a nearby
checkout must never substitute its intact binary receipt for the package's receipt.

The package probe explicitly initializes UTF-8 before imports and emits a structured JSON result
on both success and failure, preserving a nonzero exit for rejection. The parent requires complete
source and analysis, the same CLR, UTF-8 output, and the exact `RecallToolsBinaryIntegrityFailed`
message. A decoder failure, unrelated child error or console formatting change cannot pass as
successful damaged-binary rejection. The integrity report retains the structured rejection.

GitHub executes these checks once in the tooling job through `Test-CoreIndependence.ps1 -Suite Distribution -SkipBuild`. That owned checkout excludes Git and reuses integrity-checked Core/Core.Tests binaries from the single complete tooling build. Each product environment retains only its tested RID. A failed distribution step fails the required tooling qualification.

Package validation imports the extracted Common and Gallery modules from scripts/lib with -DisableNameChecking and terminating import errors. The Core-only installation case runs in the same owned source copy without Git as the complete distribution campaign.
