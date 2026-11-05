. (Join-Path $PSScriptRoot 'IndexOperations.Tests.ps1')
. (Join-Path $PSScriptRoot 'Revisions.Tests.ps1')
. (Join-Path $PSScriptRoot 'PathQueries.Tests.ps1')
. (Join-Path $PSScriptRoot 'Attribution.Tests.ps1')
. (Join-Path $PSScriptRoot 'Queries.Tests.ps1')
. (Join-Path $PSScriptRoot 'RepositoryCommands.Tests.ps1')
. (Join-Path $PSScriptRoot 'Parser.Mutation.ps1')
. (Join-Path $PSScriptRoot 'Migration.Tests.ps1')
#requires -Version 7.6
. (Join-Path $PSScriptRoot 'Semantic.Tests.ps1')
function Invoke-GitFixture {
    <#
.SYNOPSIS
Prepares independent disposable Git fixtures through explicit direct analysis.
    .PARAMETER Directory
    Disposable working directory.
    .PARAMETER Arguments
    Native fixture preparation vector.
    .PARAMETER Environment
    Isolated test Git configuration.
    #>
    param([string]$Directory,[string[]]$Arguments,[hashtable]$Environment)
    $r=quiet -AsObject -Role Infrastructure -WorkingDirectory $Directory -Environment $Environment -Output {param($e,$r)} -FilePath git -ArgumentList $Arguments
    if($r.Outcome -ne 'Success'){throw ('FixtureGitFailed: '+($Arguments -join ' ')+' '+($r.Error|ConvertTo-Json -Depth 6 -Compress))}
}
function Invoke-QuietGitTests {
    <#
.SYNOPSIS
Tests independently prepared repositories, hook counts and local bare push targets.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace root.
    .PARAMETER OnProgress
    Receives name, state, passed and failed counters.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[scriptblock]$OnProgress)
    $root=Join-Path $WorkspaceRoot ('artifacts/git-fixtures/'+[guid]::NewGuid().ToString('N'))
    $repo=Join-Path $root 'working';$bare=Join-Path $root 'remote.git'
    [void][IO.Directory]::CreateDirectory($repo)
    $environment=@{GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_GLOBAL=(Join-Path $root 'empty.gitconfig');GIT_AUTHOR_NAME='QuietCli2 Test';GIT_AUTHOR_EMAIL='quietcli2@example.invalid';GIT_COMMITTER_NAME='QuietCli2 Test';GIT_COMMITTER_EMAIL='quietcli2@example.invalid';GIT_TERMINAL_PROMPT='0';GIT_EDITOR='false';GIT_SEQUENCE_EDITOR='false'}
    Invoke-GitFixture $repo @('init','--initial-branch=main') $environment
    Invoke-GitFixture $repo @('config','commit.gpgsign','false') $environment
    $performance=[Collections.Generic.List[object]]::new()
    $cases=[ordered]@{}
    $cases['compiled Git parsers preserve migration vectors and measure local costs']={foreach($sample in Measure-QuietGitMigration){$performance.Add($sample)}}
    $cases['compiled Git formats and argument bindings satisfy independent assertions']={
        $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
        $assembly=Join-Path $PSScriptRoot 'lib/parser-tests/QuietCli.Git.Parser.Tests.dll'
        $schema=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/metadata/Git.ArgumentSchema.json'
        $r=quiet -AsObject -Data ([Text.StringBuilder]::new()) -Output {param($event,$runtime)if($event.Stream -eq 'stdout'){[void]$runtime.Data.Append($event.Text)}} -Complete {param($runtime)$runtime.Data.ToString()|ConvertFrom-Json} $dotnet $assembly $schema
        Assert-QuietEqual $r.Outcome Success 'Compiled Git suite process'
        Assert-QuietEqual $r.Data.Passed 44 'Compiled Git independent cases'
        Assert-QuietEqual $r.Data.Failed 0 'Compiled Git independent failures'
    }
    $cases['status distinguishes unborn state and Unicode untracked paths']={
        [void][IO.File]::WriteAllTextAsync((Join-Path $repo 'é test.txt'),'first',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -C git-status -WorkingDirectory $repo -Environment $environment git status
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Data.Unborn $true
        Assert-QuietEqual $r.Data.Counts.Untracked 1
        Assert-QuietEqual $r.Data.Entries[0].Path 'é test.txt'
        Invoke-QuietConformance $r
    }
    $cases['commit mutates once and exposes independently observed HEAD']={
        Invoke-GitFixture $repo @('add','--','é test.txt') $environment
        $hook=Join-Path $repo '.git/hooks/pre-commit'
        [void][IO.File]::WriteAllTextAsync($hook,"#!/bin/sh`nprintf x >> hook-count.txt`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        if(!$IsWindows){[IO.File]::SetUnixFileMode($hook,[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)}
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $environment git commit -m 'Independent first commit'
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Data.Before $null
        Assert-QuietEqual $r.Data.Changed $true
        Assert-QuietEqual ([IO.File]::ReadAllTextAsync((Join-Path $repo 'hook-count.txt'),[Text.Encoding]::UTF8).GetAwaiter().GetResult()) 'x'
        if($r.Data.After -notmatch '^[0-9a-f]{40}$'){throw 'Missing observed commit identity'}
    }
    $cases['status preserves staged and unstaged observation scope']={
        [void][IO.File]::WriteAllTextAsync((Join-Path $repo 'é test.txt'),'second',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $environment -- git status -- 'é test.txt'
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Data.Counts.Unstaged 1
        Assert-QuietEqual $r.Data.Scope.RemoteState 'local refs only'
    }
    $cases['push observes porcelain references against a local bare target']={
        Invoke-GitFixture $root @('init','--bare',$bare) $environment
        Invoke-GitFixture $repo @('remote','add','origin',$bare) $environment
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $environment git push -u origin main
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Data.References.Count 1
        Assert-QuietEqual $r.Data.References[0].Accepted $true
        Assert-QuietEqual $r.Data.References[0].To 'refs/heads/main'
        $verify=quiet -AsObject -WorkingDirectory $repo -Environment $environment git ls-remote origin refs/heads/main
        Assert-QuietEqual $verify.Data.References.Count 1
    }
    $cases['probe cache avoids repeated version subprocesses']={
        $a=quiet -AsObject -WorkingDirectory $repo -Environment $environment git status
        $b=quiet -AsObject -WorkingDirectory $repo -Environment $environment git status
        Assert-QuietEqual $a.Outcome Success ('Git handler: '+($a.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $b.Outcome Success ('Git handler: '+($b.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual @($b.Internal.Sources.Values|Where-Object Role -EQ Probe).Count 0
    }
    $cases['generic context flag and native Git -C remain distinct']={
        $r=quiet -AsObject -C project-context -Environment $environment git -C $repo status
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Context project-context
    }
    $cases['official inventory is not certified by enumeration']={
        $coverage=@(Get-QuietGitCoverage)
        Assert-QuietEqual $coverage.Count 183
        Assert-QuietEqual @($coverage|Where-Object EntireInventoryQualified).Count 0
    }
    if($env:QUIETCLI2_GIT_PUSH_MUTATION -eq '1'){$cases['push targeted mutations are detected by independent assertions']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot}}
    if($env:QUIETCLI2_GIT_COMMAND_MUTATION -eq '1'){$cases['repository command C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Repository}}
    $repositoryCases=Get-QuietRepositoryCommandCases -RootDirectory $root -Environment $environment -WorkspaceRoot $WorkspaceRoot
    foreach($entry in $repositoryCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    if($env:QUIETCLI2_GIT_QUERY_MUTATION -eq '1'){$cases['query parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Query}}
    $queryCases=Get-QuietGitQueryCases -RootDirectory $root -Environment $environment
    foreach($entry in $queryCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    if($env:QUIETCLI2_GIT_ATTRIBUTION_MUTATION -eq '1'){$cases['attribution parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Attribution}}
    $attributionCases=Get-QuietGitAttributionCases -RootDirectory $root -Environment $environment
    foreach($entry in $attributionCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    if($env:QUIETCLI2_GIT_PATH_QUERY_MUTATION -eq '1'){$cases['pathquery parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue PathQuery}}
    $pathCases=Get-QuietGitPathQueryCases -RootDirectory $root -Environment $environment -WorkspaceRoot $WorkspaceRoot
    foreach($entry in $pathCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    if($env:QUIETCLI2_GIT_REVISION_MUTATION -eq '1'){$cases['revision parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Revision}}
    $revisionCases=Get-QuietGitRevisionCases -RootDirectory $root -Environment $environment
    foreach($entry in $revisionCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    $indexCases=Get-QuietGitIndexOperationCases -RootDirectory $root -Environment $environment -WorkspaceRoot $WorkspaceRoot
    foreach($entry in $indexCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    $semanticCases=Get-QuietGitSemanticCases -RootDirectory $root -Environment $environment
    foreach($entry in $semanticCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    $passed=0;$failed=0;$results=[Collections.Generic.List[object]]::new()
    foreach($entry in $cases.GetEnumerator()){
        $failure=$null
        try{& $entry.Value;$passed++;$state='Passed'}catch{$failed++;$state='Failed';$failure=$_.Exception.Message}
        $results.Add([pscustomobject]@{Name=$entry.Key;State=$state;Error=$failure})
        if($OnProgress){& $OnProgress $entry.Key $state $passed $failed}
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Git.PoSh';Passed=$passed;Failed=$failed;Cases=$results.ToArray();Performance=$performance.ToArray();FixtureDirectory=$root;EntireInventoryQualified=$false}
}
Export-ModuleMember -Function Invoke-QuietGitTests
