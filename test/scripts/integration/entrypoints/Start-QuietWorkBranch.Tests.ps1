#requires -Version 7.6
#ScriptsImpact: RequiresBuild
# Runs the real entry point in a child pwsh against fixture repositories: a bare origin, a seed clone that moves
# develop forward, and the work clone the script operates on.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name WorkBranch
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Start-QuietWorkBranch.ps1')
    $seed=Get-QuietTestSeed
    $identity=@('-c','user.name=quiet-test','-c','user.email=quiet-test@invalid','-c','commit.gpgsign=false','-c','core.autocrlf=false')
    $git={param([string]$Repository,[string[]]$Arguments,[switch]$AllowFailure)
        $output=& git -C $Repository @identity @Arguments 2>&1
        if($LASTEXITCODE -and !$AllowFailure){throw ('git '+($Arguments -join ' ')+': '+($output -join "`n"))}
        ($output -join "`n").Trim()
    }
    $write={param([string]$Repository,[string]$Path,[string]$Text)$null=New-QuietTestFile ([IO.Path]::Combine($Repository,$Path)) $Text}
    $read={param([string]$Repository,[string]$Path)[IO.File]::ReadAllText([IO.Path]::Combine($Repository,$Path))}
    $commit={param([string]$Repository,[string]$Path,[string]$Text)
        & $write $Repository $Path $Text
        $null=& $git $Repository @('add','--',$Path)
        $null=& $git $Repository @('commit','-q','-m',('write '+$Path))
    }
    $newFixture={param([string]$Label)
        $root=[IO.Path]::Combine($TestDrive,$Label)
        $fixture=@{Origin=[IO.Path]::Combine($root,'origin.git');Seed=[IO.Path]::Combine($root,'seed');Work=[IO.Path]::Combine($root,'work')}
        [void][IO.Directory]::CreateDirectory($root)
        $null=& $git $root @('init','-q','--bare','-b','develop',$fixture.Origin)
        $null=& $git $root @('init','-q','-b','develop',$fixture.Seed)
        & $commit $fixture.Seed 'README.md' "base`n"
        $null=& $git $fixture.Seed @('remote','add','origin',$fixture.Origin)
        $null=& $git $fixture.Seed @('push','-q','origin','develop')
        $null=& $git $root @('clone','-q','--branch','develop',$fixture.Origin,$fixture.Work)
        # The child script shelves with git stash, which needs an identity of its own.
        foreach($setting in @(@('user.name','quiet-test'),@('user.email','quiet-test@invalid'),@('commit.gpgsign','false'),@('core.autocrlf','false'))){
            $null=& $git $fixture.Work (@('config')+$setting)
        }
        $fixture
    }
    $advance={param($Fixture,[string]$Path)
        & $commit $Fixture.Seed $Path "upstream`n"
        $null=& $git $Fixture.Seed @('push','-q','origin','develop')
        & $git $Fixture.Seed @('rev-parse','HEAD')
    }
    $start={param($Fixture,[string[]]$Arguments)
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$Fixture.Work)+$Arguments) -TimeoutSeconds 300
        $run.TimedOut|Should -BeFalse
        # pwsh wraps an error message at the console width and colors each wrapped line, which differs per host:
        # compare without ANSI sequences and with whitespace collapsed.
        $text=($run.Output+"`n"+$run.Error) -replace '\x1B\[[0-?]*[ -/]*[@-~]','' -replace '\s+',' '
        $run|Add-Member -NotePropertyName Text -NotePropertyValue $text -PassThru
    }
    $snapshot={param($Fixture)
        [pscustomobject]@{
            Branch=& $git $Fixture.Work @('branch','--show-current')
            Head=& $git $Fixture.Work @('rev-parse','HEAD')
            Status=& $git $Fixture.Work @('status','--porcelain=v1','--untracked-files=all')
            Readme=& $read $Fixture.Work 'README.md'
            Stashes=& $git $Fixture.Work @('stash','list')
            Branches=& $git $Fixture.Work @('branch','--list','--format=%(refname:short)')
        }
    }
}

Describe 'Start-QuietWorkBranch.ps1' {
    It 'starts the new branch from the pulled remote develop, not from the current work branch, and carries pending work over' {
        $fixture=& $newFixture 'carry'
        $null=& $git $fixture.Work @('switch','-q','-c','fix/old')
        & $commit $fixture.Work 'old.txt' "old`n"
        & $write $fixture.Work 'README.md' "edited`n"
        & $write $fixture.Work 'staged.txt' "staged`n"
        $null=& $git $fixture.Work @('add','--','staged.txt')
        & $write $fixture.Work 'notes/untracked.txt' "untracked`n"
        $tip=& $advance $fixture 'upstream.txt'

        $run=& $start $fixture @('-Kind','companion','-Name','demo')

        $run.ExitCode|Should -Be 0 -Because $run.Text
        & $git $fixture.Work @('branch','--show-current')|Should -BeExactly 'companion/demo'
        & $git $fixture.Work @('rev-parse','HEAD')|Should -BeExactly $tip
        & $git $fixture.Work @('rev-parse','develop')|Should -BeExactly $tip -Because 'develop is fast-forwarded, never rewritten'
        & $git $fixture.Work @('ls-tree','--name-only','HEAD')|Should -Not -Match 'old\.txt' -Because 'the commit of the previous work branch must not leak into the new one'
        & $git $fixture.Work @('config','--get','branch.companion/demo.merge') -AllowFailure|Should -BeNullOrEmpty -Because 'a work branch never tracks develop'
        & $read $fixture.Work 'README.md'|Should -BeExactly "edited`n"
        & $git $fixture.Work @('diff','--cached','--name-only')|Should -BeExactly 'staged.txt' -Because 'the index is restored with --index'
        & $read $fixture.Work 'notes/untracked.txt'|Should -BeExactly "untracked`n"
        @((& $git $fixture.Work @('stash','list')).Split("`n")).Count|Should -Be 1 -Because 'the shelf is retained'
        & $git $fixture.Work @('rev-parse','fix/old')|Should -Not -BeExactly $tip
        $run.Text|Should -Match 'Shelf retained: [0-9a-f]{40}'
    }

    It 'accepts the whole branch name and does not shelve a clean checkout' {
        $fixture=& $newFixture 'clean'
        $run=& $start $fixture @('-Branch','chore/tidy')
        $run.ExitCode|Should -Be 0 -Because $run.Text
        & $git $fixture.Work @('branch','--show-current')|Should -BeExactly 'chore/tidy'
        & $git $fixture.Work @('stash','list')|Should -BeNullOrEmpty
        $run.Text|Should -Not -Match 'Shelf retained'
    }

    It 'refuses <Case> and leaves the checkout untouched' -ForEach @(
        @{Case='an unknown kind';Arguments=@('-Branch','hotfix/x');Expected='WorkBranchKindInvalid'}
        @{Case='an invalid name';Arguments=@('-Kind','feature','-Name','a..b');Expected='WorkBranchNameInvalid'}
        @{Case='a work branch as base';Arguments=@('-Kind','feature','-Name','x','-BaseBranch','fix/old');Expected='WorkBranchBaseIsWorkBranch'}
        @{Case='a branch that exists locally';Arguments=@('-Kind','feature','-Name','x');Expected='WorkBranchAlreadyExists: feature/x';Prepare='Local'}
        @{Case='a branch that exists on the remote';Arguments=@('-Kind','feature','-Name','x');Expected='WorkBranchAlreadyExistsOnRemote: origin/feature/x';Prepare='Remote'}
        @{Case='a missing local base';Arguments=@('-Kind','feature','-Name','x','-BaseBranch','main');Expected='WorkBranchLocalBaseMissing: main'}
        @{Case='a detached checkout';Arguments=@('-Kind','feature','-Name','x');Expected='WorkBranchInitialStateInvalid: Detached';Prepare='Detached'}
    ) {
        $fixture=& $newFixture ('refuse-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        $null=& $git $fixture.Work @('switch','-q','-c','fix/old')
        switch($Prepare){
            'Local'{$null=& $git $fixture.Work @('branch','feature/x','develop')}
            'Remote'{$null=& $git $fixture.Seed @('push','-q','origin','develop:refs/heads/feature/x')}
            'Detached'{$null=& $git $fixture.Work @('switch','-q','--detach','develop')}
        }
        & $write $fixture.Work 'README.md' "pending`n"
        & $write $fixture.Work 'new.txt' "new`n"
        $before=& $snapshot $fixture

        $run=& $start $fixture $Arguments

        $run.ExitCode|Should -Not -Be 0
        $run.Text|Should -Match ([regex]::Escape($Expected))
        $after=& $snapshot $fixture
        foreach($property in 'Branch','Head','Status','Readme','Stashes','Branches'){$after.$property|Should -BeExactly $before.$property -Because ($property+' must not change')}
    }

    It 'refuses a checkout with a merge in progress' {
        $fixture=& $newFixture 'merge'
        $null=& $git $fixture.Work @('switch','-q','-c','fix/old')
        & $commit $fixture.Work 'README.md' "fix side`n"
        $null=& $git $fixture.Work @('switch','-q','develop')
        $null=& $git $fixture.Work @('switch','-q','-c','fix/other')
        & $commit $fixture.Work 'README.md' "other side`n"
        $null=& $git $fixture.Work @('merge','fix/old') -AllowFailure
        $before=& $snapshot $fixture

        $run=& $start $fixture @('-Kind','feature','-Name','x')

        $run.ExitCode|Should -Not -Be 0
        $run.Text|Should -Match 'WorkBranchInitialStateInvalid: Conflicted, Operation:Merge\b'
        (& $snapshot $fixture).Status|Should -BeExactly $before.Status
        & $git $fixture.Work @('branch','--list','feature/x')|Should -BeNullOrEmpty
    }

    It 'previews with WhatIf without shelving, pulling or creating anything' {
        $fixture=& $newFixture 'whatif'
        & $write $fixture.Work 'README.md' "pending`n"
        $null=& $advance $fixture 'upstream.txt'
        $before=& $snapshot $fixture

        $run=& $start $fixture @('-Kind','feature','-Name','x','-WhatIf')

        $run.ExitCode|Should -Be 0 -Because $run.Text
        # The WhatIf prefix is localized; the operation text is ours.
        $run.Text|Should -Match ([regex]::Escape('Shelve pending work, pull origin/develop and create feature/x'))
        $after=& $snapshot $fixture
        foreach($property in 'Branch','Head','Status','Readme','Stashes','Branches'){$after.$property|Should -BeExactly $before.$property}
    }

    It 'validates the name under WhatIf' {
        $fixture=& $newFixture 'whatif-invalid'
        $run=& $start $fixture @('-Kind','feature','-Name','x.lock','-WhatIf')
        $run.ExitCode|Should -Not -Be 0
        $run.Text|Should -Match 'WorkBranchNameInvalid'
    }

    It 'puts the pending work back on the original branch when develop cannot be fast-forwarded' {
        $fixture=& $newFixture 'diverged'
        & $commit $fixture.Work 'local.txt' "local only`n"
        $null=& $advance $fixture 'upstream.txt'
        $null=& $git $fixture.Work @('switch','-q','-c','fix/old')
        & $write $fixture.Work 'README.md' "pending`n"
        & $write $fixture.Work 'new.txt' "new`n"
        $before=& $snapshot $fixture

        $run=& $start $fixture @('-Kind','feature','-Name','x')

        $run.ExitCode|Should -Not -Be 0
        $run.Text|Should -Match 'WorkBranchGitFailed: pull'
        $run.Text|Should -Match 'pending work restored on fix/old; shelf [0-9a-f]{40} retained'
        $after=& $snapshot $fixture
        $after.Branch|Should -BeExactly 'fix/old'
        $after.Status|Should -BeExactly $before.Status
        $after.Readme|Should -BeExactly "pending`n"
        & $git $fixture.Work @('branch','--list','feature/x')|Should -BeNullOrEmpty
    }

    It 'only accepts names that git also accepts' {
        $alphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/'
        $null=Invoke-QuietProperty -Name 'work-branch-git-ref' -Seed $seed -Count 150 -Generator {param($random)
            (Get-QuietRandomItem $random (Get-QuietWorkBranchKinds))+'/'+(New-QuietRandomString $random -Alphabet $alphabet -MinLength 1 -MaxLength 12)
        } -Property {param($case)
            try{$null=Resolve-QuietWorkBranchName -Branch $case}catch{return $true}
            $null=& git check-ref-format --branch $case 2>&1
            $LASTEXITCODE -eq 0
        }
    }
}

Describe 'New-QuietCompanion.ps1' {
    BeforeAll {
        $source = Get-QuietTestWorkspaceRoot
        $scripts = Get-QuietTestScriptsRoot
        $generator = [IO.Path]::Combine($scripts, 'New-QuietCompanion.ps1')
        $newCompanionFixture = {
            param([string]$Label)
            $fixture = & $newFixture $Label
            $core = 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh'
            $coreTests = 'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh'
            foreach ($relative in @(
                'LICENSE',
                '.github/workflows/core-ci.yml',
                'docs/ci/github/script-core-ci.md',
                "$core/resources/yaml/YamlDotNet.dll",
                "$core/resources/dependencies.lock.json",
                'scripts/Invoke-Quiet.ps1',
                'scripts/lib/WorkspaceLayout.psm1',
                'scripts/lib/WorkspaceProjects.psm1',
                'scripts/lib/CompanionWorkflows.psm1',
                'scripts/lib/CiCompanions.psm1',
                'scripts/lib/Resources.psm1'
            )) {
                $destination = [IO.Path]::Combine($fixture.Work, $relative)
                $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                [IO.File]::Copy([IO.Path]::Combine($source, $relative), $destination)
            }
            & $write $fixture.Work "$core/FrenchExDev2.QuietCli.Core.PoSh.psd1" @'
@{
    RootModule='FrenchExDev2.QuietCli.Core.PoSh.psm1'
    ModuleVersion='0.2.0'
    PrivateData=@{QuietCli=@{
        SolutionGroup='Core'
        Binary='dotnet'
        TestsModule='FrenchExDev2.QuietCli.Core.Tests.PoSh'
        Publishable=$false
    }}
}
'@
            & $write $fixture.Work "$core/FrenchExDev2.QuietCli.Core.PoSh.psm1" '# local Core import fixture'
            & $write $fixture.Work "$core/LICENSE_CREDITS.md" '## Core fixture'
            & $write $fixture.Work "$coreTests/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1" @'
@{
    RootModule='FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1'
    ModuleVersion='0.1.0'
    RequiredModules=@('FrenchExDev2.QuietCli.Core.PoSh')
    FunctionsToExport=@('Invoke-QuietCoreTests')
    PrivateData=@{QuietCli=@{SolutionGroup='Core'}}
}
'@
            & $write $fixture.Work 'Quietly.slnx' '<Solution />'
            & $write $fixture.Work 'CREDITS.md' '# Credits fixture'
            & $write $fixture.Work 'docs/ci/github/README.md' '# Workflow fixture'
            & $write $fixture.Work 'build/companions.yml' @'
schema: 1
companions:
  Core:
    requires: []
    image: base
suites:
  Core:
    test_project: FrenchExDev2.QuietCli.Core.Tests.PoSh
    command: Invoke-QuietCoreTests
    requires: [Core]
    core_evidence: true
'@
            $null = & $git $fixture.Work @('add','-f','--','src','scripts','build','.github','docs','Quietly.slnx','LICENSE','CREDITS.md')
            $null = & $git $fixture.Work @('commit','-q','-m','Add companion generation fixture')
            $null = & $git $fixture.Work @('push','-q','origin','develop')
            $fixture.Credits = New-QuietTestFile ([IO.Path]::Combine([IO.Path]::GetDirectoryName($fixture.Work), 'credits.md')) "## Packer fixture`n`n- License: https://example.test/license`n"
            $fixture
        }
        $generate = {
            param($Fixture, [string[]]$Options)
            $arguments = @('-WorkspaceRoot',$Fixture.Work,'-Name','Packer','-LicenseCreditsPath',$Fixture.Credits)
            Invoke-QuietTestScript -ScriptPath $generator -ArgumentList ($arguments + $Options) -TimeoutSeconds 120
        }
    }

    It 'previews the branch and writes nothing with WhatIf' {
        $fixture = & $newCompanionFixture 'companion-preview'
        $before = & $snapshot $fixture
        $result = & $generate $fixture @('-GitBranch','packer-parser','-WhatIf')
        $result.ExitCode | Should -Be 0 -Because $result.Error
        $result.Output | Should -Match 'companion/packer-parser'
        $result.Output | Should -Match 'src/Packer'
        $after = & $snapshot $fixture
        ($after | ConvertTo-Json -Compress) | Should -BeExactly ($before | ConvertTo-Json -Compress)
    }

    It 'generates and imports the <Variant> scaffold on <Branch>' -ForEach @(
        @{Variant='PowerShell'; Branch='companion/packer'; Options=@(); Compiled=$false}
        @{Variant='CSharp'; Branch='companion/packer-parser'; Options=@('-WithCSharp','-GitBranch','companion/packer-parser'); Compiled=$true}
        @{Variant='existing branch'; Branch='companion/existing'; Options=@('-NoGitBranch'); Compiled=$false}
    ) {
        $fixture = & $newCompanionFixture ('companion-'+$Variant.Replace(' ','-'))
        if ($Options -contains '-NoGitBranch') {
            $null = & $git $fixture.Work @('switch','-q','--no-track','-c',$Branch)
            $null = & $git $fixture.Work @('remote','remove','origin')
        }
        $result = & $generate $fixture $Options
        $result.ExitCode | Should -Be 0 -Because $result.Error
        $result.Output | Should -Not -Match 'VoidTaskResult'
        & $git $fixture.Work @('branch','--show-current') | Should -BeExactly $Branch
        $product = 'src/Packer/src/FrenchExDev2.QuietCli.Packer.PoSh'
        $tests = 'src/Packer/test/FrenchExDev2.QuietCli.Packer.Tests.PoSh'
        $manifest = Import-PowerShellDataFile -LiteralPath ([IO.Path]::Combine($fixture.Work, $product, 'FrenchExDev2.QuietCli.Packer.PoSh.psd1'))
        $testManifest = Import-PowerShellDataFile -LiteralPath ([IO.Path]::Combine($fixture.Work, $tests, 'FrenchExDev2.QuietCli.Packer.Tests.PoSh.psd1'))
        $testManifest.GUID | Should -Not -Be $manifest.GUID
        $manifest.PrivateData.QuietCli.Binary | Should -BeExactly 'packer'
        $manifest.PrivateData.QuietCli.Publishable | Should -BeFalse
        $manifest.PrivateData.QuietCli.ContainsKey('BuildProjects') | Should -Be $Compiled
        [IO.File]::Exists([IO.Path]::Combine($fixture.Work, $product, 'engine/QuietCli.Packer.Parser.csproj')) | Should -Be $Compiled
        & $read $fixture.Work 'Quietly.slnx' | Should -Match 'src/Packer/'
        & $read $fixture.Work 'src/Packer/Packer.slnx' | Should -Match 'Invoke|Tests.PoSh'
        & $read $fixture.Work 'CREDITS.md' | Should -Match 'Packer fixture'
        $workflow = [IO.Path]::Combine($fixture.Work, '.github/workflows/packer-ci.yml')
        $hash = (Get-FileHash -LiteralPath $workflow).Hash
        & $read $fixture.Work 'docs/ci/github/script-packer-ci.md' | Should -Match $hash
        & $read $fixture.Work 'docs/ci/github/README.md' | Should -Match 'packer-ci.yml'

        $check = New-QuietTestFile ([IO.Path]::Combine([IO.Path]::GetDirectoryName($fixture.Work), 'check.ps1')) @'
param([string]$Root, [string]$SmokeModule)
$ErrorActionPreference = 'Stop'
& ([IO.Path]::Combine($Root, 'scripts/Invoke-Quiet.ps1')) -Companion Packer -Runtime $Root -Code {
    param($checkout)
    $manifest = [IO.Path]::Combine($checkout, 'src/Packer/test/FrenchExDev2.QuietCli.Packer.Tests.PoSh/FrenchExDev2.QuietCli.Packer.Tests.PoSh.psd1')
    Import-Module $manifest -ErrorAction Stop
    $result = Invoke-QuietPackerTests -WorkspaceRoot $checkout
    if ($result.Passed -ne 1 -or $result.Failed -ne 0) { throw ($result.Cases.Error -join ', ') }
}
Import-Module $SmokeModule -DisableNameChecking -ErrorAction Stop
$smoke = Invoke-QuietCompanionSmokeTests -WorkspaceRoot $Root -Suites Packer
if ($smoke.Passed -ne 1 -or $smoke.Failed -ne 0 -or $smoke.Cases[0].Name -cne 'Packer module-loading smoke') {
    throw ($smoke.Cases.Error -join ', ')
}
'@
        $smokeModule = [IO.Path]::Combine($source, 'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/CompanionSmoke.Tests.psm1')
        $importResult = Invoke-QuietTestScript -ScriptPath $check -ArgumentList @($fixture.Work, $smokeModule)
        $importResult.ExitCode | Should -Be 0 -Because $importResult.Error

        $repeat = & $generate $fixture @('-WhatIf')
        $repeat.ExitCode | Should -Not -Be 0
        $repeat.Error | Should -Match 'CompanionDestinationExists'
    }

    It 'rejects NoGitBranch on develop and rejects the two branch options together' {
        $fixture = & $newCompanionFixture 'companion-rejections'
        $result = & $generate $fixture @('-NoGitBranch')
        $result.ExitCode | Should -Not -Be 0
        $result.Error | Should -Match 'CompanionActiveBranchRequired'
        $result = & $generate $fixture @('-NoGitBranch', '-GitBranch', 'different')
        $result.ExitCode | Should -Not -Be 0
        [IO.Directory]::Exists([IO.Path]::Combine($fixture.Work, 'src/Packer')) | Should -BeFalse
        & $git $fixture.Work @('branch','--show-current') | Should -BeExactly 'develop'
    }
}
