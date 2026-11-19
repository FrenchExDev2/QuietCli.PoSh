BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-QuietTestLibrary -Name SqliteDocumentation
}

Describe 'Get-QuietSqliteSourceStatement' {
    It 'preserves SQL value text, source lines, and statement kinds' {
        $source = @'
class Store {
    // "SELECT masked FROM comments";
    const string Mode = "release";
    const string Create = "CREATE TABLE cafés(id INTEGER)";
    const string Insert = @"INSERT OR IGNORE INTO cafés VALUES (""a"")";
    const string Read = """
        SELECT id
        FROM cafés
        """;
    void Select() {
        string sql = "SELECT id FROM cafés";
        sql += " AND id=?";
        sql += " ORDER BY id LIMIT ?";
        sql = "not a statement";
        string message = "application";
        message += " log";
    }
}
'@
        $path = [IO.Path]::Combine($TestDrive, 'Store.cs')
        $actual = @(Get-QuietSqliteSourceStatement -Source $source -Path $path)
        $expected = @(
            '4|DDL|CREATE TABLE cafés(id INTEGER)'
            '5|Statement|INSERT OR IGNORE INTO cafés VALUES ("a")'
            "6|Statement|SELECT id`nFROM cafés"
            '11|Statement|SELECT id FROM cafés'
            '12|Appended clause| AND id=?'
            '13|Appended clause| ORDER BY id LIMIT ?'
        )
        ($actual.ForEach({ "$($_.Line)|$($_.Kind)|$($_.Sql)" }) -join "`n") | Should -BeExactly ($expected -join "`n")
        ($actual.Path | Select-Object -Unique) | Should -BeExactly $path
    }

    It 'extracts a literal unchanged and ignores keyword decoys across reproducible inputs' {
        Invoke-QuietProperty -Name 'SQL literal provenance' -Seed (Get-QuietTestSeed) -Count 64 -Generator {
            param($random)
            $payload = New-QuietRandomString -Random $random -Alphabet 'é*&[]<>"''~` @' -MinLength 0 -MaxLength 32
            @{
                LeadingLines = $random.Next(0, 16)
                Sql = 'SELECT ''' + $payload.Replace("'", "''") + ';--'' FROM events'
            }
        } -Property {
            param($case)
            $source = ("`n" * $case.LeadingLines) + 'class C { string a = "release"; string b = @"' + $case.Sql.Replace('"', '""') + '"; }'
            $actual = @(Get-QuietSqliteSourceStatement -Source $source -Path 'Generated.cs')
            return $actual.Count -eq 1 -and $actual[0].Line -eq $case.LeadingLines + 1 -and
                $actual[0].Kind -ceq 'Statement' -and $actual[0].Path -ceq 'Generated.cs' -and $actual[0].Sql -ceq $case.Sql
        }
    }
}

Describe 'Get-QuietSqliteSchema' {
    It 'binds table names and reads catalog entries, columns and declared references' {
        $database = [pscustomobject]@{ Calls = [Collections.Generic.List[object]]::new() }
        $database | Add-Member -MemberType ScriptMethod -Name Query -Value {
            param($sql, $arguments)
            $this.Calls.Add(@{ Sql = $sql; Arguments = $arguments })
            switch -Wildcard ($sql) {
                '*sqlite_master*' {
                    @(
                        @{ type = 'index'; name = 'some_index'; sql = 'CREATE INDEX some_index ON "étrange ?)"""(code)' }
                        @{
                            type = 'table'
                            name = 'étrange ?)"'
                            sql = @'
CREATE TABLE "étrange ?)"""(
    code TEXT DEFAULT 'CHECK(ignored)',
    "CHECK" INTEGER,
    /* CHECK(ignored) */ CHECK /* retained */ (length(trim(code, ')')) > 0),
    CHECK ([CHECK] >= 0)
)
'@
                        }
                    )
                }
                '*pragma_table_xinfo*' { @{ name = 'code'; type = 'TEXT'; pk = 2; notnull = 1; dflt_value = "'CHECK(ignored)'"; hidden = 0 } }
                '*pragma_foreign_key_list*' { @{ id = 0; target = 'parent'; source_column = 'code'; target_column = 'id' } }
                '*pragma_index_list*' { @{ index_name = 'unique_code'; name = 'code' } }
                default { throw "Unexpected query: $sql" }
            }
        }
        $schema = Get-QuietSqliteSchema -Database $database
        $schema.Objects.Count | Should -Be 2
        $schema.Tables.Count | Should -Be 1
        $schema.Tables[0].Name | Should -BeExactly 'étrange ?)"'
        $schema.Tables[0].Columns[0].pk | Should -Be 2
        $schema.Tables[0].Columns[0].dflt_value | Should -BeExactly "'CHECK(ignored)'"
        $schema.Tables[0].References[0].target | Should -BeExactly 'parent'
        $schema.Tables[0].UniqueColumns[0].name | Should -BeExactly 'code'
        ($schema.Tables[0].Checks -join '|') | Should -BeExactly "CHECK /* retained */ (length(trim(code, ')')) > 0)|CHECK ([CHECK] >= 0)"
        $database.Calls[0].Arguments.Count | Should -Be 0
        $database.Calls[1].Arguments[0] | Should -BeExactly 'étrange ?)"'
        $database.Calls[2].Arguments[0] | Should -BeExactly 'étrange ?)"'
        $database.Calls[3].Arguments[0] | Should -BeExactly 'étrange ?)"'
    }
}

Describe 'ConvertTo-QuietSqliteMarkdown' {
    It 'renders one overview diagram and Markdown tables with escaped details and original SQL' {
        $schema = @{
            Objects = @(@{ sql = "CREATE TABLE parent(code TEXT DEFAULT '~~~')`r`n-- définition" })
            Tables = @(
                @{
                    Name = 'child "é📚"'
                    Columns = @(
                        @{ name = 'parent_id'; type = ''; pk = 0; notnull = 0; dflt_value = $null; hidden = 0 }
                        @{ name = 'other'; type = 'TEXT'; pk = 0; notnull = 0; dflt_value = "('x' || '````' || '``'`r`n)"; hidden = 0 }
                        @{ name = 'virt'; type = 'TEXT'; pk = 0; notnull = 0; dflt_value = $null; hidden = 2 }
                        @{ name = 'stored'; type = 'TEXT'; pk = 0; notnull = 0; dflt_value = $null; hidden = 3 }
                        @{ name = 'internal'; type = 'TEXT'; pk = 0; notnull = 0; dflt_value = $null; hidden = 1 }
                    )
                    References = @(
                        @{ id = 0; target = 'parent'; source_column = 'parent_id'; target_column = 'code' }
                        @{ id = 0; target = 'parent'; source_column = 'other'; target_column = 'name' }
                        @{ id = 1; target = 'missing []'; source_column = 'other'; target_column = $null }
                    )
                    UniqueColumns = @(@{ index_name = 'unique_pair'; name = 'parent_id' }, @{ index_name = 'unique_pair'; name = 'other' })
                    Checks = @('CHECK (parent_id >= 0)', "CHECK (other <> 'a|b')")
                }
                @{
                    Name = 'parent'
                    Columns = @(@{ name = 'code'; type = 'TEXT'; pk = 1; notnull = 1; dflt_value = $null; hidden = 0 })
                    References = @()
                    UniqueColumns = @()
                    Checks = @()
                }
            )
        }
        $source = [IO.Path]::Combine($TestDrive, 'folder with space', 'Store.cs')
        $parameters = @{
            Schema = $schema
            Statements = @(
                @{ Path = $source; Line = 9; Kind = 'Statement'; Sql = 'SELECT ?' }
                @{ Path = $source; Line = 10; Kind = 'Appended clause'; Sql = ' AND code=?' }
            )
            OutputPath = [IO.Path]::Combine($TestDrive, 'docs', 'schema.md')
            NoticePath = [IO.Path]::Combine($TestDrive, 'CREDITS.md')
            FromDatabase = $true
        }
        $expected = @'
# QuietCli SQLite schema and queries

<!-- Generated by scripts/Export-SqliteDocumentation.ps1. -->

SQLite catalog read from a QuietCli database opened read-only.

## Schema

```mermaid
flowchart LR
    table0["child #34;é#128218;#34;"]
    table1["parent"]
```

## Tables

### ` child "é📚" `

| Column | Type | Constraints |
| --- | --- | --- |
| ` parent_id ` | — | — |
| ` other ` | ` TEXT ` | ``` DEFAULT ('x' \|\| '``' \|\| '`' ) ``` |
| ` virt ` | ` TEXT ` | ` GENERATED VIRTUAL ` |
| ` stored ` | ` TEXT ` | ` GENERATED STORED ` |
| ` internal ` | ` TEXT ` | ` HIDDEN ` |

**Table constraints**

- ` UNIQUE (parent_id, other) `
- ` FK (parent_id, other) → parent (code, name) `
- ` FK (other) → missing [] `
- ` CHECK (parent_id >= 0) `
- ` CHECK (other <> 'a|b') `

### ` parent `

| Column | Type | Constraints |
| --- | --- | --- |
| ` code ` | ` TEXT ` | ` PK 1 · NOT NULL ` |

## Schema definitions

~~~~sql
CREATE TABLE parent(code TEXT DEFAULT '~~~')
-- définition
~~~~

## Source statements

The inventory includes DDL, prepared statements, transaction commands and appended SQL clauses as they appear in C#.

### Store.cs

- [Store.cs:9](../folder%20with%20space/Store.cs#L9) · Statement

~~~sql
SELECT ?
~~~

- [Store.cs:10](../folder%20with%20space/Store.cs#L10) · Appended clause

~~~sql
 AND code=?
~~~

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
'@ + "`n"
        ConvertTo-QuietSqliteMarkdown @parameters | Should -BeExactly $expected
        $parameters.FromDatabase = $false
        ConvertTo-QuietSqliteMarkdown @parameters | Should -BeExactly ($expected.Replace('a QuietCli database opened read-only', 'a disposable database initialized from the source checkout'))
    }
}

Describe 'Export-QuietSqliteDocumentation' {
    It 'previews without opening a database or writing the report' {
        $target = [IO.Path]::Combine($TestDrive, 'preview.md')
        $missing = [IO.Path]::Combine($TestDrive, 'missing.sqlite')
        Export-QuietSqliteDocumentation -WorkspaceRoot $TestDrive -OutputPath $target -DatabasePath $missing -WhatIf
        [IO.File]::Exists($target) | Should -BeFalse
        [IO.File]::Exists($missing) | Should -BeFalse
    }

    It 'rejects a missing database before changing any existing report' {
        $target = New-QuietTestFile -Path ([IO.Path]::Combine($TestDrive, 'previous.md')) -Text 'previous report'
        $missing = [IO.Path]::Combine($TestDrive, 'missing.sqlite')
        { Export-QuietSqliteDocumentation -WorkspaceRoot $TestDrive -OutputPath $target -DatabasePath $missing } |
            Should -Throw -ExpectedMessage 'SqliteDocumentationDatabaseMissing*'
        [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8) | Should -BeExactly 'previous report'
    }
}
