#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Sync-DocsCredits.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietSqliteSourceStatement {
    <#
    .SYNOPSIS
    Inventories SQL string literals and appended clauses in a C# source file.
    .PARAMETER Source
    C# source text, parsed without executing the source.
    .PARAMETER Path
    Absolute provenance path for each literal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Source,
        [Parameter(Mandatory)][string]$Path
    )

    $tree = [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText($Source)
    foreach ($node in $tree.GetRoot().DescendantNodes()) {
        if ($node -isnot [Microsoft.CodeAnalysis.CSharp.Syntax.LiteralExpressionSyntax]) { continue }
        $sql = $node.Token.ValueText
        if ($node.Parent -is [Microsoft.CodeAnalysis.CSharp.Syntax.AssignmentExpressionSyntax] -and
            $node.Parent.OperatorToken.Text -ceq '+=' -and $node.Parent.Left.ToString() -ceq 'sql') {
            $kind = 'Appended clause'
        }
        elseif ($sql -match '^\s*(CREATE\s+(?:(?:TEMP(?:ORARY)?|UNIQUE|VIRTUAL)\s+)?(?:TABLE|INDEX|VIEW|TRIGGER)|ALTER\s+TABLE|DROP\s+(?:TABLE|INDEX|VIEW|TRIGGER))\b') {
            $kind = 'DDL'
        }
        elseif ($sql -match '^\s*(?:(?:SELECT|WITH|INSERT\s+(?:OR\s+\w+\s+)?INTO|REPLACE\s+INTO|UPDATE|DELETE\s+FROM|PRAGMA|SAVEPOINT|RELEASE|ROLLBACK\s+TO)\s+\S|(?:BEGIN|COMMIT|ROLLBACK)(?:\s+(?:DEFERRED|IMMEDIATE|EXCLUSIVE|TRANSACTION))*\s*;?\s*$)') {
            $kind = 'Statement'
        }
        else { continue }
        [pscustomobject]@{
            Path = $Path
            Line = $node.GetLocation().GetLineSpan().StartLinePosition.Line + 1
            Kind = $kind
            Sql  = $sql
        }
    }
}

function Get-QuietSqliteCheckConstraint {
    <#
    .SYNOPSIS
    Reads CHECK clauses from a catalogued CREATE TABLE statement.
    .PARAMETER Sql
    SQLite-validated table definition from the catalog.
    #>
    param([string]$Sql)

    # Skip SQL comments and recognize quoted identifiers and literals before counting parentheses.
    $pattern = @'
(?:--[^\r\n]*|/\*[\s\S]*?\*/|\s+)|(?<token>'(?:''|[^'])*'|"(?:""|[^"])*"|`(?:``|[^`])*`|\[[^\]]*\]|[\p{L}\p{M}\p{N}_$]+|.)
'@
    $tokens = [regex]::Matches($Sql, $pattern).Groups | Where-Object { $_.Name -ceq 'token' -and $_.Success }
    $start = 0
    $depth = 0
    for ($index = 0; $index -lt $tokens.Count; $index++) {
        $token = $tokens[$index]
        if ($depth -gt 0) {
            switch ($token.Value) {
                '(' { $depth++ }
                ')' {
                    $depth--
                    if ($depth -eq 0) { $Sql.Substring($start, $token.Index + $token.Length - $start) }
                }
            }
        }
        elseif ($token.Value -ieq 'CHECK' -and $tokens[$index + 1].Value -ceq '(') {
            $start = $token.Index
            $depth = 1
            $index++
        }
    }
}

function Get-QuietSqliteSchema {
    <#
    .SYNOPSIS
    Reads objects, columns and declared constraints from a SQLite connection.
    .PARAMETER Database
    Open QuietCli SQLite adapter exposing Query.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Database)

    $objects = @($Database.Query("SELECT type, name, sql FROM main.sqlite_master WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY type, name COLLATE BINARY", @()))
    $tables = @(foreach ($entry in $objects) {
        if ($entry.type -cne 'table') { continue }
        $columns = @($Database.Query('SELECT name, type, "notnull", pk, dflt_value, hidden FROM pragma_table_xinfo(?) ORDER BY cid', @($entry.name)))
        $references = @($Database.Query('SELECT id, "table" AS target, "from" AS source_column, "to" AS target_column FROM pragma_foreign_key_list(?) ORDER BY id, seq', @($entry.name)))
        $uniqueColumns = @($Database.Query("SELECT idx.name AS index_name, col.name FROM pragma_index_list(?) AS idx JOIN pragma_index_info(idx.name) AS col WHERE idx.origin = 'u' ORDER BY idx.seq, col.seqno", @($entry.name)))
        $checks = @(Get-QuietSqliteCheckConstraint -Sql $entry.sql)
        [pscustomobject]@{
            Name = $entry.name
            Columns = $columns
            References = $references
            UniqueColumns = $uniqueColumns
            Checks = $checks
        }
    })
    [pscustomobject]@{ Objects = $objects; Tables = $tables }
}

function ConvertTo-QuietSqliteMermaidLabel {
    <#
    .SYNOPSIS
    Encodes punctuation and control characters in a Mermaid HTML label.
    .PARAMETER Value
    SQLite label text.
    #>
    param([AllowEmptyString()][string]$Value)

    [regex]::Replace($Value, '[\uD800-\uDBFF][\uDC00-\uDFFF]|[^\p{L}\p{M}\p{N}_ .·-]', {
        param($match)
        '#' + [char]::ConvertToUtf32($match.Value, 0) + ';'
    })
}

function ConvertTo-QuietSqliteMermaid {
    <#
    .SYNOPSIS
    Renders a schema overview using table names alone.
    .PARAMETER Schema
    Catalog with table names.
    #>
    param([Parameter(Mandatory)][object]$Schema)

    'flowchart LR'
    for ($index = 0; $index -lt $Schema.Tables.Count; $index++) {
        '    table{0}["{1}"]' -f $index, (ConvertTo-QuietSqliteMermaidLabel $Schema.Tables[$index].Name)
    }
}

function Format-QuietSqliteMarkdownCode {
    <#
    .SYNOPSIS
    Formats literal schema text for a Markdown heading, table cell or list.
    .PARAMETER Value
    Identifier, type or constraint text.
    .PARAMETER InTable
    Escapes pipes so they stay inside the cell.
    #>
    param([AllowEmptyString()][string]$Value, [switch]$InTable)

    if (!$Value) { return '—' }
    $body = $Value -creplace '\r\n?|\n', ' '
    if ($InTable) { $body = $body.Replace('|', '\|') }
    $fenceLength = 1
    foreach ($run in [regex]::Matches($body, '`+')) {
        $fenceLength = [Math]::Max($fenceLength, $run.Length + 1)
    }
    $fence = '`' * $fenceLength
    '{0} {1} {0}' -f $fence, $body
}

function ConvertTo-QuietSqliteMarkdownTable {
    <#
    .SYNOPSIS
    Renders column details as a Markdown table followed by table-level constraints.
    .PARAMETER Table
    Table metadata from the SQLite catalog.
    #>
    param([Parameter(Mandatory)][object]$Table)

    '### {0}' -f (Format-QuietSqliteMarkdownCode $Table.Name)
    ''
    '| Column | Type | Constraints |'
    '| --- | --- | --- |'
    foreach ($column in $Table.Columns) {
        $constraints = @(
            if ($column.pk) { "PK $($column.pk)" }
            if ($column.notnull) { 'NOT NULL' }
            if ($null -ne $column.dflt_value) { "DEFAULT $($column.dflt_value)" }
            switch ($column.hidden) {
                1 { 'HIDDEN' }
                2 { 'GENERATED VIRTUAL' }
                3 { 'GENERATED STORED' }
            }
        )
        $name = Format-QuietSqliteMarkdownCode $column.name -InTable
        $type = Format-QuietSqliteMarkdownCode $column.type -InTable
        $summary = Format-QuietSqliteMarkdownCode ($constraints -join ' · ') -InTable
        '| {0} | {1} | {2} |' -f $name, $type, $summary
    }
    $tableConstraints = @(
        foreach ($key in ($Table.UniqueColumns | Group-Object -Property index_name -CaseSensitive)) {
            'UNIQUE ({0})' -f ($key.Group.name -join ', ')
        }
        foreach ($key in ($Table.References | Group-Object -Property id)) {
            $target = $key.Group[0].target
            $targetColumns = $key.Group.target_column -join ', '
            if ($targetColumns) { $target += " ($targetColumns)" }
            'FK ({0}) → {1}' -f ($key.Group.source_column -join ', '), $target
        }
        $Table.Checks
    )
    if ($tableConstraints.Count) {
        ''
        '**Table constraints**'
        ''
        foreach ($constraint in $tableConstraints) {
            '- {0}' -f (Format-QuietSqliteMarkdownCode $constraint)
        }
    }
}

function Format-QuietSqliteMarkdownLink {
    <#
    .SYNOPSIS
    Formats a relative Markdown link destination using URI-escaped path segments.
    .PARAMETER Directory
    Directory containing the document.
    .PARAMETER Path
    Target file path.
    #>
    param([string]$Directory, [string]$Path)

    $relative = [IO.Path]::GetRelativePath($Directory, $Path)
    ($relative.Split([IO.Path]::DirectorySeparatorChar).ForEach({ [uri]::EscapeDataString($_) })) -join '/'
}

function Format-QuietSqliteCodeBlock {
    <#
    .SYNOPSIS
    Emits a fenced SQL block that preserves the original text.
    .PARAMETER Sql
    SQL body, possibly multiline.
    #>
    param([string]$Sql)

    $body = $Sql -creplace '\r\n?', "`n"
    $fenceLength = 3
    foreach ($run in [regex]::Matches($body, '~{3,}')) {
        $fenceLength = [Math]::Max($fenceLength, $run.Length + 1)
    }
    $fence = '~' * $fenceLength
    "${fence}sql`n$body`n$fence"
}

function ConvertTo-QuietSqliteMarkdown {
    <#
    .SYNOPSIS
    Renders the schema and source SQL as a deterministic UTF-8 Markdown document.
    .PARAMETER Schema
    SQLite schema catalog and tables.
    .PARAMETER Statements
    Literal SQL records with source paths and line numbers.
    .PARAMETER OutputPath
    Destination used to resolve relative links.
    .PARAMETER NoticePath
    Repository credits file.
    .PARAMETER FromDatabase
    Indicates that the catalog comes from a caller-selected database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Schema,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Statements,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$NoticePath,
        [switch]$FromDatabase
    )

    $directory = [IO.Path]::GetDirectoryName($OutputPath)
    $origin = if ($FromDatabase) { 'a QuietCli database opened read-only' } else { 'a disposable database initialized from the source checkout' }
    $lines = @(
        '# QuietCli SQLite schema and queries'
        ''
        '<!-- Generated by scripts/Export-SqliteDocumentation.ps1. -->'
        ''
        "SQLite catalog read from $origin."
        ''
        '## Schema'
        ''
        '```mermaid'
        ConvertTo-QuietSqliteMermaid -Schema $Schema
        '```'
        ''
        '## Tables'
        ''
        foreach ($table in $Schema.Tables) {
            ConvertTo-QuietSqliteMarkdownTable -Table $table
            ''
        }
        '## Schema definitions'
        ''
        foreach ($entry in $Schema.Objects) {
            Format-QuietSqliteCodeBlock $entry.sql
            ''
        }
        '## Source statements'
        ''
        'The inventory includes DDL, prepared statements, transaction commands and appended SQL clauses as they appear in C#.'
        ''
        foreach ($group in ($Statements | Group-Object -Property Path -CaseSensitive)) {
            $link = Format-QuietSqliteMarkdownLink $directory $group.Name
            '### ' + [IO.Path]::GetFileName($group.Name)
            ''
            foreach ($statement in $group.Group) {
                '- [{0}:{1}]({2}#L{1}) · {3}' -f [IO.Path]::GetFileName($statement.Path), $statement.Line, $link, $statement.Kind
                ''
                Format-QuietSqliteCodeBlock $statement.Sql
                ''
            }
        }
        Format-QuietDocsCreditsBlock -Link (Format-QuietSqliteMarkdownLink $directory $NoticePath)
    )
    ($lines -join "`n") + "`n"
}

function Export-QuietSqliteDocumentation {
    <#
    .SYNOPSIS
    Builds the QuietCli SQLite schema and query reference from the checkout.
    .PARAMETER WorkspaceRoot
    Checkout providing Core storage and SQL source.
    .PARAMETER OutputPath
    Absolute Markdown destination.
    .PARAMETER DatabasePath
    Absolute path of an optional existing QuietCli database to open read-only.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$DatabasePath
    )
    $ErrorActionPreference = 'Stop'
    if ([IO.Path]::GetExtension($OutputPath) -ine '.md' -or ($DatabasePath -and $OutputPath -ieq $DatabasePath)) {
        throw 'SqliteDocumentationOutputInvalid: Select a separate Markdown destination.'
    }
    if (!$PSCmdlet.ShouldProcess($OutputPath, 'Write SQLite schema and source queries')) { return }
    if ($DatabasePath -and ![IO.File]::Exists($DatabasePath)) { throw "SqliteDocumentationDatabaseMissing: $DatabasePath" }
    if (![IO.Directory]::Exists([IO.Path]::GetDirectoryName($OutputPath))) { throw "SqliteDocumentationOutputDirectoryMissing: $OutputPath" }

    $core = Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath 'FrenchExDev2.QuietCli.Core.PoSh'
    $engine = [IO.Path]::Combine($core, 'engine')
    $adapterPath = [IO.Path]::Combine($engine, 'SqliteNative.cs')
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $adapterSource = [IO.File]::ReadAllTextAsync($adapterPath, $utf8).GetAwaiter().GetResult()
    $paths = [string[]]@(Get-ChildItem -LiteralPath $engine -Recurse -File -Filter '*.cs' |
        Where-Object { [IO.Path]::GetRelativePath($engine, $_.FullName) -notmatch '(?:^|[/\\])(?:bin|obj)(?:[/\\]|$)' } |
        ForEach-Object FullName)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    $statements = @(foreach ($path in $paths) {
        $source = if ($path -ceq $adapterPath) { $adapterSource } else { [IO.File]::ReadAllTextAsync($path, $utf8).GetAwaiter().GetResult() }
        Get-QuietSqliteSourceStatement -Source $source -Path $path
    })
    if (!$statements.Count) { throw 'SqliteDocumentationStatementsMissing' }

    # Give the checkout adapter its own identity even when a product assembly is already loaded.
    $fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($adapterSource)))
    $adapterNamespace = "QuietCliDocumentation.Storage_$fingerprint"
    $adapter = Add-Type -TypeDefinition ($adapterSource.Replace('namespace FrenchExDev2.QuietCli.Storage {', "namespace $adapterNamespace {")) -PassThru |
        Where-Object FullName -CEQ "$adapterNamespace.Database"
    if (!$adapter) { throw 'SqliteDocumentationAdapterMissing: The checkout storage adapter could not be located.' }

    $scratch = $null
    $database = $null
    $fromDatabase = [bool]$DatabasePath
    try {
        if (!$fromDatabase) {
            $scratch = [IO.Directory]::CreateTempSubdirectory('quietcli-sqlite-docs-')
            $DatabasePath = [IO.Path]::Combine($scratch.FullName, 'schema.db')
        }
        $database = $adapter::new($DatabasePath, !$fromDatabase)
        if (!$fromDatabase) {
            # The adapter initializes its own schema. Apply the additional writer DDL from source.
            foreach ($statement in $statements) {
                if ($statement.Kind -ceq 'DDL' -and $statement.Path -cne $adapterPath) {
                    $database.Execute($statement.Sql, @())
                }
            }
        }
        $schema = Get-QuietSqliteSchema -Database $database
    }
    finally {
        if ($database) { $database.Dispose() }
        if ($scratch) {
            foreach ($file in $scratch.EnumerateFiles()) { $file.Delete() }
            $scratch.Delete()
        }
    }

    $markdown = ConvertTo-QuietSqliteMarkdown -Schema $schema -Statements $statements -OutputPath $OutputPath `
        -NoticePath ([IO.Path]::Combine($WorkspaceRoot, 'CREDITS.md')) -FromDatabase:$fromDatabase
    $changed = ![IO.File]::Exists($OutputPath) -or [IO.File]::ReadAllTextAsync($OutputPath, $utf8).GetAwaiter().GetResult() -cne $markdown
    if ($changed) {
        $temporary = "$OutputPath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            [void][IO.File]::WriteAllTextAsync($temporary, $markdown, $utf8).GetAwaiter().GetResult()
            [IO.File]::Move($temporary, $OutputPath, $true)
        }
        finally {
            [IO.File]::Delete($temporary)
        }
    }
    [pscustomobject]@{ Path = $OutputPath; Tables = $schema.Tables.Count; Statements = $statements.Count; Changed = $changed }
}

Export-ModuleMember -Function 'Get-QuietSqliteSourceStatement', 'Get-QuietSqliteSchema', 'ConvertTo-QuietSqliteMarkdown', 'Export-QuietSqliteDocumentation'
