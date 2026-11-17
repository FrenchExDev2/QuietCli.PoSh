#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Assert-ScriptMutationShards.ps1')
    # A fixture workspace: two targets over one library, each with its unit test, as the CI shards would run them.
    $workspace=[IO.Path]::Combine($TestDrive,'workspace')
    $null=New-QuietTestFile ([IO.Path]::Combine($workspace,'scripts','lib','Sign.psm1')) "function Get-Sign { 'zero' }`nfunction Get-Size { 'small' }`n"
    $null=New-QuietTestFile ([IO.Path]::Combine($workspace,'test','scripts','unit','Sign.Tests.ps1')) "Describe a { It b { } }`n"
    $null=New-QuietTestFile ([IO.Path]::Combine($workspace,'test','scripts','mutation.targets.psd1')) "@{Targets=@(@{Name='Sign';Module='lib/Sign.psm1';Functions=@('Get-Sign');UnitTestFiles=@('unit/Sign.Tests.ps1');Break=80};@{Name='Size';Module='lib/Sign.psm1';Functions=@('Get-Size');UnitTestFiles=@('unit/Sign.Tests.ps1');Break=90})}`n"
    $entryOf={param([string]$Name,[int]$Break,[double]$Score=100,[int]$Mutants=4,[int]$Cached=0)
        [ordered]@{Name=$Name;Module='lib/Sign.psm1';Functions=1;Mutants=$Mutants;Killed=$Mutants;Survived=0;Timeout=0;CompileError=0;Cached=$Cached;Score=$Score;Break=$Break;Passed=($Score -ge $Break);Survivors=@()}
    }
    # Each row is @{Shard; Name; Break; Score?}; rows sharing a shard number land in the same report.json.
    $download={param([object[]]$Rows=@())
        $root=[IO.Path]::Combine($TestDrive,'download-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($root)
        foreach($group in @($Rows|Group-Object {$_.Shard})){
            $targets=@($group.Group|ForEach-Object {& $entryOf $_.Name $_.Break $(if($_.ContainsKey('Score')){$_.Score}else{100}) 4 $(if($_.ContainsKey('Cached')){$_.Cached}else{0})})
            $report=[ordered]@{SchemaVersion=1;Seed=7;Passed=(@($targets|Where-Object {!$_.Passed}).Count -eq 0);Targets=$targets}
            $null=New-QuietTestFile ([IO.Path]::Combine($root,'quietcli-script-mutation-shard'+$group.Name,'report.json')) ($report|ConvertTo-Json -Depth 6)
        }
        $root
    }
    $assert={param([string]$ReportRoot,[string]$OutputPath,[string[]]$Extra=@())
        Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-ReportRoot',$ReportRoot,'-OutputPath',$OutputPath,'-WorkspaceRoot',$workspace)+$Extra) -TimeoutSeconds 120
    }
}

Describe 'Assert-ScriptMutationShards.ps1' {
    It 'writes a completion receipt when the shards cover every target above its break, reused cached outcomes included' {
        $root=& $download @(@{Shard=0;Name='Sign';Break=80;Score=85},@{Shard=1;Name='Size';Break=90;Cached=4})
        $output=[IO.Path]::Combine($TestDrive,'complete','receipt.json')
        $run=& $assert $root $output
        $run.ExitCode|Should -Be 0 -Because ($run.Output+$run.Error)
        $receipt=[IO.File]::ReadAllText($output)|ConvertFrom-Json
        $receipt.Passed|Should -BeTrue
        (@($receipt.Targets.Name) -join ',')|Should -BeExactly 'Sign,Size'
        (@($receipt.Targets.Break) -join ',')|Should -BeExactly '80,90'
    }

    It 'fails without a receipt when a shard is missing or below its break' -ForEach @(
        @{Case='missing shard';Rows=@(@{Shard=0;Name='Sign';Break=80});Issue='ScriptMutationShardMissing: Size'}
        @{Case='below break';Rows=@(@{Shard=0;Name='Sign';Break=80},@{Shard=1;Name='Size';Break=90;Score=89});Issue='ScriptMutationShardFailed: Size'}
        @{Case='lowered break';Rows=@(@{Shard=0;Name='Sign';Break=80},@{Shard=1;Name='Size';Break=80});Issue='ScriptMutationShardBreakLowered: Size'}
        @{Case='duplicate shard';Rows=@(@{Shard=0;Name='Sign';Break=80},@{Shard=1;Name='Size';Break=90},@{Shard=2;Name='Sign';Break=80});Issue='ScriptMutationShardDuplicate: Sign'}
        @{Case='no report';Rows=@();Issue='ScriptMutationShardReportsMissing'}
    ) {
        $root=& $download $Rows
        $output=[IO.Path]::Combine($TestDrive,'failed-'+[guid]::NewGuid().ToString('N'),'receipt.json')
        $run=& $assert $root $output
        $run.ExitCode|Should -Not -Be 0 -Because $Case
        ($run.Output+$run.Error)|Should -Match ([regex]::Escape($Issue))
        [IO.File]::Exists($output)|Should -BeFalse
    }

    It 'requires only the selected target when -Target narrows the campaign' {
        $root=& $download @(@{Shard=0;Name='Size';Break=90})
        $output=[IO.Path]::Combine($TestDrive,'selected','receipt.json')
        $run=& $assert $root $output @('-Target','Size')
        $run.ExitCode|Should -Be 0 -Because ($run.Output+$run.Error)
        $receipt=[IO.File]::ReadAllText($output)|ConvertFrom-Json
        (@($receipt.Targets.Name) -join ',')|Should -BeExactly 'Size'
    }

    It 'fails without a receipt for a selected <Case>' -ForEach @(
        @{Case='unknown target';Rows=@(@{Shard=0;Name='Sign';Break=80});Target='Nope';Issue='ScriptMutationTargetUnknown: Nope'}
        @{Case='target in another case';Rows=@(@{Shard=0;Name='Sign';Break=80});Target='sign';Issue='ScriptMutationTargetUnknown: sign'}
        @{Case='missing shard';Rows=@(@{Shard=0;Name='Sign';Break=80});Target='Size';Issue='ScriptMutationShardMissing: Size'}
        @{Case='unselected shard';Rows=@(@{Shard=0;Name='Sign';Break=80},@{Shard=1;Name='Size';Break=90});Target='Size';Issue='ScriptMutationShardUnknown: Sign'}
    ) {
        $root=& $download $Rows
        $output=[IO.Path]::Combine($TestDrive,'selected-'+[guid]::NewGuid().ToString('N'),'receipt.json')
        $run=& $assert $root $output @('-Target',$Target)
        $run.ExitCode|Should -Not -Be 0 -Because $Case
        ($run.Output+$run.Error)|Should -Match ([regex]::Escape($Issue))
        [IO.File]::Exists($output)|Should -BeFalse
    }

    It 'refuses to overwrite an existing receipt' {
        $root=& $download @(@{Shard=0;Name='Sign';Break=80},@{Shard=1;Name='Size';Break=90})
        $output=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'existing','receipt.json')) 'previous'
        $run=& $assert $root $output
        $run.ExitCode|Should -Not -Be 0
        ($run.Output+$run.Error)|Should -Match 'ScriptMutationCompletionReceiptExists'
        [IO.File]::ReadAllText($output)|Should -BeExactly 'previous'
    }

    It 'reads nothing and writes nothing under -WhatIf' {
        $output=[IO.Path]::Combine($TestDrive,'whatif','receipt.json')
        $run=& $assert ([IO.Path]::Combine($TestDrive,'absent')) $output @('-WhatIf')
        $run.ExitCode|Should -Be 0 -Because ($run.Output+$run.Error)
        [IO.Directory]::Exists([IO.Path]::GetDirectoryName($output))|Should -BeFalse
    }
}
