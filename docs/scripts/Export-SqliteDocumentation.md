# Export-SqliteDocumentation.ps1

<!-- script-source:begin -->
Source file: [`Export-SqliteDocumentation.ps1`](../../scripts/Export-SqliteDocumentation.ps1)
<!-- script-source:end -->

Regenerates the [SQLite schema and SQL inventory](../README-sqlite-schema-and-queries.md) from a source checkout, with a Mermaid overview of table names and a Markdown table of columns and constraints for each table.

## Usage

```powershell
./scripts/Export-SqliteDocumentation.ps1 -WhatIf
./scripts/Export-SqliteDocumentation.ps1
./scripts/Export-SqliteDocumentation.ps1 -DatabasePath ./history.sqlite -OutputPath ./schema.md
```

- `-DatabasePath` opens an existing QuietCli SQLite database read-only. Omit it to document the schema that the checkout initializes for a new store.
- `-OutputPath` defaults to `docs/README-sqlite-schema-and-queries.md`. Specify an existing parent directory and an `.md` filename.
- `-WhatIf` previews the destination without opening SQLite or writing a file. `-Confirm` prompts once.

## Dependencies and effects

PowerShell 7.6 or later runs the [documentation library](lib/SqliteDocumentation.md), which uses the SQLite storage adapter source and system SQLite. The command returns the output path, table count, source-statement count and change status. It replaces the report only when the content differs.

## Findings

The entry point resolves relative paths in the caller's PowerShell location and delegates after a single guard. The default path follows the script checkout. Links in a custom report resolve from its destination, so moving the report can break them. [Entry point](../../scripts/Export-SqliteDocumentation.ps1#L20)

## Verdict

Use the default destination for the checked-in reference and an explicit destination when inspecting a database from another installation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Exports the QuietCli SQLite schema and source SQL to a Markdown document.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
