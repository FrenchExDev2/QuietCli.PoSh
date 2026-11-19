BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $scriptPath = [IO.Path]::Combine((Get-QuietTestScriptsRoot), 'Export-SqliteDocumentation.ps1')
}

Describe 'Export-SqliteDocumentation.ps1' {
    It 'writes the schema and SQL inventory and reproduces identical bytes' {
        $target = [IO.Path]::Combine($TestDrive, 'actual.md')
        $arguments = @('-OutputPath', $target)
        $run = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList $arguments
        $run.ExitCode | Should -Be 0 -Because $run.Error
        $report = [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8)
        $report | Should -Match 'CREATE TABLE quiet2_events'
        $report | Should -Match 'CREATE TABLE quiet2_delivery_tokens'
        $report | Should -Match 'MeasurementStore\.cs#L\d+'
        $report | Should -Match 'MeasurementProjection\.cs#L\d+'
        $report | Should -Match 'SqliteNative\.cs#L\d+'
        $report | Should -Match 'ORDER BY timestamp_ms,id LIMIT \?'
        $report | Should -Not -Match 'EngineConnection\.cs#'
        $diagrams = [regex]::Matches($report, '(?ms)^```mermaid\n(.*?)^```$')
        $diagrams.Count | Should -Be 1
        $diagrams[0].Groups[1].Value | Should -BeExactly "flowchart LR`n    table0[`"quiet2_delivery_tokens`"]`n    table1[`"quiet2_events`"]`n"
        [regex]::Matches($report, '(?m)^\| Column \| Type \| Constraints \|$').Count | Should -Be 2
        $report | Should -Match ([regex]::Escape('- ` CHECK(output_tokens>=0) `'))
        $report | Should -Match ([regex]::Escape('### ` quiet2_events `'))
        $originalTime = [IO.File]::GetLastWriteTimeUtc($target)
        $repeat = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList $arguments
        $repeat.ExitCode | Should -Be 0 -Because $repeat.Error
        [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8) | Should -BeExactly $report
        [IO.File]::GetLastWriteTimeUtc($target) | Should -Be $originalTime
    }

    It 'does not create or overwrite Markdown in preview' {
        $existing = [IO.Path]::Combine($TestDrive, 'previous.md')
        $missing = [IO.Path]::Combine($TestDrive, 'preview.md')
        [IO.File]::WriteAllText($existing, 'previous report', [Text.UTF8Encoding]::new($false))
        foreach ($target in $existing, $missing) {
            $run = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-OutputPath', $target, '-WhatIf')
            $run.ExitCode | Should -Be 0 -Because $run.Error
        }
        [IO.File]::ReadAllText($existing, [Text.Encoding]::UTF8) | Should -BeExactly 'previous report'
        [IO.File]::Exists($missing) | Should -BeFalse
    }

    It 'inspects the declared constraints of a historical database read-only' {
        $workspace = Get-QuietTestWorkspaceRoot
        $source = [IO.Path]::Combine($workspace, 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/SqliteNative.cs')
        $adapter = Add-Type -TypeDefinition ([IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)) -PassThru |
            Where-Object FullName -CEQ 'FrenchExDev2.QuietCli.Storage.Database'
        $dbPath = [IO.Path]::Combine($TestDrive, 'historical.sqlite')
        $db = $adapter::new($dbPath, $true)
        try {
            $db.Execute('CREATE TABLE "historical café"(event_id TEXT REFERENCES quiet2_events(id), secret TEXT DEFAULT NULL, UNIQUE(event_id, secret))', @())
            $db.Execute('INSERT INTO "historical café" VALUES (NULL, ?)', @('private-test-marker'))
        }
        finally { $db.Dispose() }
        $hash = (Get-FileHash -LiteralPath $dbPath -Algorithm SHA256).Hash
        $target = [IO.Path]::Combine($TestDrive, 'historical.md')
        $run = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-DatabasePath', $dbPath, '-OutputPath', $target)
        $run.ExitCode | Should -Be 0 -Because $run.Error
        $report = [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8)
        ($report -split '## Source statements')[0] | Should -Not -Match 'quiet2_delivery_tokens'
        $report | Should -Match ([regex]::Escape('- ` FK (event_id) → quiet2_events (id) `'))
        $report | Should -Match ([regex]::Escape('- ` UNIQUE (event_id, secret) `'))
        $report | Should -Match ([regex]::Escape('| ` secret ` | ` TEXT ` | ` DEFAULT NULL ` |'))
        $report | Should -Match ([regex]::Escape('### ` historical café `'))
        $report | Should -Not -Match 'private-test-marker'
        (Get-FileHash -LiteralPath $dbPath -Algorithm SHA256).Hash | Should -BeExactly $hash
    }
}
