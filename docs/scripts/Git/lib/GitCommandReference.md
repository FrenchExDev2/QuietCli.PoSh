# GitCommandReference.psm1

Source: [Git companion renderer](../../../../src/Git/scripts/lib/GitCommandReference.psm1).

`Get-QuietGitCommandReference -ModuleDirectory <path> -GuidancePath <path>` returns one Markdown string. It reads the inert Git inventory, handler catalogue and contract schemas. It parses PowerShell source for handler locations and fingerprints the implementation inputs. No product import, filesystem write or native command runs in the renderer.

The [guidance JSON](../../../../src/Git/scripts/GitCommandReference.json) lists one or more records per specialized command. A record names the native `Form`, the `Data` fields or shared projection, and its `Limits`. Add or remove entries in the same change as the corresponding catalogue entry. Resolve missing schemas and handler links before rendering. Source SHA-256 changes prompt a review of the hand-authored routes when Git implementation inputs change.

The argument schema describes versioned grammar. The guide describes the actual result route and its observable fields. Test qualification comes from the companion evidence and `Get-QuietGitCoverage`.

See [the entry point](../Export-GitCommandReference.md) for checking and writing the document.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
