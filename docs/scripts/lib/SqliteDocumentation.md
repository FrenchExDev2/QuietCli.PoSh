# SqliteDocumentation.psm1

<!-- script-source:begin -->
Source file: [`lib/SqliteDocumentation.psm1`](../../../scripts/lib/SqliteDocumentation.psm1)
<!-- script-source:end -->

Reads SQLite metadata, inventories SQL in Core source and renders a deterministic Markdown reference. The [entry point](../Export-SqliteDocumentation.md) owns parameter handling and interactive approval.

## Usage

```powershell
Import-Module ./scripts/lib/SqliteDocumentation.psm1 -DisableNameChecking -ErrorAction Stop
Export-QuietSqliteDocumentation -WorkspaceRoot $workspace -OutputPath $absoluteMarkdownPath
```

`Get-QuietSqliteSourceStatement` returns the SQL value, file path, line and statement kind. `Get-QuietSqliteSchema` reads the catalog and table pragmas using an open storage adapter. `ConvertTo-QuietSqliteMarkdown` renders these two inputs without writing a file.

## Dependencies and effects

The library uses Roslyn from PowerShell 7.6+, the checkout's `SqliteNative.cs` and the system SQLite library with table-valued `table_xinfo`, `foreign_key_list`, `index_list` and `index_info` pragmas. It reuses the workspace layout and credits helpers. The export compiles the adapter in memory and creates a disposable SQLite file unless a database is supplied. The provided database uses the adapter's read-only mode and only its metadata is queried. The export writes UTF-8 with LF endings through a temporary file beside the destination.

## Findings

- The source inventory recognizes SQL string literals and additions to the `sql` variable. The report shows those additions where they appear in source. Runtime combinations, interpolation, and SQL built outside these patterns require an extension to the reader. [Source reader](../../../scripts/lib/SqliteDocumentation.psm1#L6)
- The disposable schema uses the adapter's bootstrap and applies the remaining literal DDL in file and line order. Conditional migrations that cannot be reproduced this way can be inspected through `-DatabasePath`. [Export implementation](../../../scripts/lib/SqliteDocumentation.psm1#L314)
- The Mermaid overview contains the table names. Each Markdown table shows column names, declared types, primary key positions, `NOT NULL`, defaults and generated or hidden columns. The list below each table groups the columns in each `UNIQUE` and foreign key constraint and lists the `CHECK` expressions from the stored table definition. The full DDL includes details such as index definitions and foreign key actions. [Table renderer](../../../scripts/lib/SqliteDocumentation.psm1#L159)

## Verdict

The reference covers the current telemetry schema and its source statements, with direct links for auditing. It is a documentation tool for trusted QuietCli checkouts and databases.

<!-- script-contract:begin -->
## Execution contract

Purpose: Inventories SQL string literals and appended clauses in a C# source file.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
