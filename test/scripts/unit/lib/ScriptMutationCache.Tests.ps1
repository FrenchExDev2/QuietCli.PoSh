#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptMutation
    $null=Import-QuietTestLibrary -Name ScriptMutationCache
    $seed=Get-QuietTestSeed
    $source=@'
function Get-A {
    param([int]$Value)
    if($Value -gt 0){return 'positive'}
    'other'
}

function Get-B { $true -and $false }
'@
    $engine='Pester=6.2.0;PowerShell=7.6.0;Platform=test'
    # A fixture repository: scripts/ (the closure), test/ (the tests root) and repository inputs.
    $newFixture={
        $root=[IO.Path]::Combine($TestDrive,'repo-'+[guid]::NewGuid().ToString('N'))
        $files=[ordered]@{
            'scripts/lib/A.psm1'="Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'B.psm1'))`nImport-Module ""`$PSScriptRoot/Pathed.psm1""`nfunction Get-A { 1 }"
            'scripts/lib/B.psm1'="Import-Module ([IO.Path]::Combine(`$PSScriptRoot,`"Transitive.psm1`"))`nfunction Get-B { 2 }"
            # Refers back to A: the closure walk must terminate on a cycle.
            'scripts/lib/Transitive.psm1'="# uses 'A.psm1'`nfunction Get-T { 3 }"
            'scripts/lib/Helper.psm1'='function Get-H { 4 }'
            'scripts/lib/Pathed.psm1'='function Get-P { & ([IO.Path]::Combine($PSScriptRoot,''../Up.ps1'')); Import-Module "$PSScriptRoot\Slashed.psm1" }'
            'scripts/Up.ps1'='param() 7'
            'scripts/lib/Slashed.psm1'='function Get-S { 8 }'
            'scripts/lib/Unrelated.psm1'='function Get-U { 5 }'
            'scripts/Entry.ps1'='param() 6'
            'test/unit/A.Tests.ps1'="Import-QuietTestLibrary -Name A`n& ([IO.Path]::Combine(`$root,'Entry.ps1'))`nDescribe a { It b { } }"
            'test/unit/Other.Tests.ps1'="`$null=Import-QuietTestLibrary 'Unrelated'`nDescribe o { }"
            'test/integration/A.Tests.ps1'="Import-QuietTestLibrary -Name Unrelated`nDescribe i { }"
            'test/support/Helper.psm1'="function H { Import-QuietTestLibrary -Name Helper }`nfunction L { Import-QuietTestLibrary -Name `$Name }"
            'test/analyzer/Rules.psm1'='function R { }'
            'test/ScriptAnalyzerSettings.psd1'='@{}'
            'test/README.md'='# tests'
            'test/mutation.targets.psd1'='@{}'
            'test/coverage.inventory.json'='{}'
            'test/ScriptAnalyzer.baseline.json'='[]'
            'build/companions.yml'='companions: []'
            'build/other.yml'='x: 1'
            '.github/containers/base/Dockerfile'='FROM scratch'
            '.github/containers/base/deep/layer.sh'='true'
            '.github/workflows/ci.yml'='on: push'
            'src/Git/ci/Get-CiImageArguments.ps1'='param() 1'
            'src/Git/other/Get-CiImageArguments.ps1'='param() 2'
            'src/Git/x/ci/nested.ps1'='param() 3'
            'README.md'='# root'
            'docs/README.md'='# docs'
        }
        foreach($entry in $files.GetEnumerator()){$null=New-QuietTestFile ([IO.Path]::Combine([string[]](@($root)+$entry.Key.Split('/')))) $entry.Value}
        [pscustomobject]@{Root=$root;Scripts=[IO.Path]::Combine($root,'scripts');Tests=[IO.Path]::Combine($root,'test')}
    }
    $pathOf={param($Fixture,[string]$Relative)[IO.Path]::Combine([string[]](@($Fixture.Root)+$Relative.Split('/')))}
    $edit={param($Fixture,[string]$Relative)
        $path=& $pathOf $Fixture $Relative
        if([IO.File]::Exists($path)){[IO.File]::AppendAllText($path,"`n# edited")}else{$null=New-QuietTestFile $path 'new'}
    }
    $sourceOf={param($Fixture,[string[]]$Files=@('unit/A.Tests.ps1'),[string]$Module='lib/A.psm1')
        Get-QuietScriptMutationSourceFingerprint -ScriptsRoot $Fixture.Scripts -Module $Module -TestsRoot $Fixture.Tests -UnitTestFiles $Files
    }
    $testsOf={param($Fixture,[string[]]$Files=@('unit/A.Tests.ps1'))
        Get-QuietScriptMutationTestFingerprint -TestsRoot $Fixture.Tests -UnitTestFiles $Files
    }
    $inputsOf={param($Fixture,[string[]]$Inputs)
        Get-QuietScriptMutationInputsFingerprint -WorkspaceRoot $Fixture.Root -Inputs $Inputs
    }
    $keysOf={param([string]$Target='t',[string]$Engine=$engine,[string]$Module='lib/A.psm1',[string]$Header='')
        $Text=$Header+$source
        $mutants=@(Get-QuietScriptMutants -Text $Text -Functions @('Get-A','Get-B') -Module $Module)
        $keys=Get-QuietScriptMutantCacheKeys -Mutants $mutants -TargetFingerprint $Target -EngineFingerprint $Engine
        [pscustomobject]@{Mutants=$mutants;Keys=$keys;Values=[string[]]@($mutants|ForEach-Object {$keys[$_.Id]})}
    }
    $key='ab'+('c'*62)
    $newCache={[IO.Path]::Combine($TestDrive,'cache-'+[guid]::NewGuid().ToString('N'))}
    $writeDocument={param([string]$Cache,[string]$Text)
        $path=Get-QuietScriptMutantCachePath -Directory $Cache -Key $key
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path,$Text)
    }
}

Describe 'Get-QuietScriptMutationSha256' {
    It 'returns the lowercase hex SHA-256 of the UTF-8 bytes' {
        Get-QuietScriptMutationSha256 ''|Should -BeExactly 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        Get-QuietScriptMutationSha256 'abc'|Should -BeExactly 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        Get-QuietScriptMutationSha256 'é'|Should -Not -Be (Get-QuietScriptMutationSha256 'e')
    }
}

Describe 'Get-QuietScriptMutationFilesDigest' {
    It 'hashes the sorted relative paths with forward slashes and the SHA-256 of each file, one line per file' {
        $root=[IO.Path]::Combine($TestDrive,'digest-'+[guid]::NewGuid().ToString('N'))
        $nested=New-QuietTestFile ([IO.Path]::Combine($root,'a','b.txt')) 'x'
        $top=New-QuietTestFile ([IO.Path]::Combine($root,'c.txt')) 'y'
        $hash={param([string]$Path)(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
        $expected=Get-QuietScriptMutationSha256 ('a/b.txt'+[char]0x1F+(& $hash $nested)+"`n"+'c.txt'+[char]0x1F+(& $hash $top))
        InModuleScope ScriptMutationCache -Parameters @{Root=$root;Paths=@($top,$nested,$top)} {param($Root,$Paths)Get-QuietScriptMutationFilesDigest -Root $Root -Paths $Paths}|Should -BeExactly $expected
    }
}

Describe 'Get-QuietScriptMutationTreeFiles' {
    It 'lists the files of every subdirectory and skips a linked directory' {
        $root=[IO.Path]::Combine($TestDrive,'tree-'+[guid]::NewGuid().ToString('N'))
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'in','top.txt')) 'a'
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'in','deep','down.txt')) 'b'
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'outside','linked.txt')) 'c'
        $link=[IO.Path]::Combine($root,'in','link')
        try{
            if($IsWindows){$null=New-Item -ItemType Junction -Path $link -Target ([IO.Path]::Combine($root,'outside')) -ErrorAction Stop}
            else{$null=[IO.Directory]::CreateSymbolicLink($link,[IO.Path]::Combine($root,'outside'))}
        }catch{Set-ItResult -Skipped -Because "a directory link cannot be created here: $($_.Exception.Message)";return}
        @(InModuleScope ScriptMutationCache -Parameters @{Directory=[IO.Path]::Combine($root,'in')} {param($Directory)Get-QuietScriptMutationTreeFiles $Directory}|ForEach-Object {[IO.Path]::GetRelativePath($root,$_).Replace('\','/')}|Sort-Object -CaseSensitive) -join ','|
            Should -BeExactly 'in/deep/down.txt,in/top.txt'
    }

    It 'returns nothing for a missing directory' {
        @(InModuleScope ScriptMutationCache -Parameters @{Directory=[IO.Path]::Combine($TestDrive,'missing-tree')} {param($Directory)Get-QuietScriptMutationTreeFiles $Directory}).Count|Should -Be 0
    }
}

Describe 'Get-QuietScriptMutationSourceFingerprint' {
    It 'is a stable hex digest' {
        $fixture=& $newFixture
        $first=& $sourceOf $fixture
        $first|Should -Match '^[0-9a-f]{64}$'
        & $sourceOf $fixture|Should -BeExactly $first
        & $sourceOf $fixture @('unit/A.Tests.ps1','unit/A.Tests.ps1')|Should -BeExactly $first
    }

    It 'changes when <Relative> is <Case>' -ForEach @(
        @{Case='edited, as the target module';Relative='scripts/lib/A.psm1'}
        @{Case='edited, as a library the module imports';Relative='scripts/lib/B.psm1'}
        @{Case='edited, as a transitive import';Relative='scripts/lib/Transitive.psm1'}
        @{Case='edited, as a script the unit test runs';Relative='scripts/Entry.ps1'}
        @{Case='edited, as a library a support module imports';Relative='scripts/lib/Helper.psm1'}
        @{Case='edited, as a library imported through a path';Relative='scripts/lib/Pathed.psm1'}
        @{Case='edited, as a script named after ../';Relative='scripts/Up.ps1'}
        @{Case='edited, as a library named after a backslash';Relative='scripts/lib/Slashed.psm1'}
    ) {
        $fixture=& $newFixture
        $before=& $sourceOf $fixture
        & $edit $fixture $Relative
        & $sourceOf $fixture|Should -Not -Be $before
    }

    It 'changes when a referenced library that did not exist is created' {
        $fixture=& $newFixture
        [IO.File]::AppendAllText((& $pathOf $fixture 'scripts/lib/A.psm1'),"`n# later 'Later.psm1'")
        $before=& $sourceOf $fixture
        & $edit $fixture 'scripts/lib/Later.psm1'
        & $sourceOf $fixture|Should -Not -Be $before
    }

    It 'ignores <Relative>, which no included file names' -ForEach @(
        @{Relative='scripts/lib/Unrelated.psm1'}
        @{Relative='scripts/lib/Added.psm1'}
        @{Relative='scripts/Other.ps1'}
    ) {
        $fixture=& $newFixture
        $before=& $sourceOf $fixture
        & $edit $fixture $Relative
        & $sourceOf $fixture|Should -BeExactly $before
    }

    It 'follows the libraries of every named unit test file' {
        $fixture=& $newFixture
        $before=& $sourceOf $fixture @('unit/A.Tests.ps1','unit/Other.Tests.ps1')
        $before|Should -Not -Be (& $sourceOf $fixture)
        & $edit $fixture 'scripts/lib/Unrelated.psm1'
        & $sourceOf $fixture @('unit/A.Tests.ps1','unit/Other.Tests.ps1')|Should -Not -Be $before
    }

    It 'follows the imports of a library that only a unit test file names' {
        $fixture=& $newFixture
        [IO.File]::AppendAllText((& $pathOf $fixture 'scripts/lib/Unrelated.psm1'),"`nImport-Module ([IO.Path]::Combine(`$PSScriptRoot,'Deep.psm1'))")
        $null=New-QuietTestFile (& $pathOf $fixture 'scripts/lib/Deep.psm1') 'function Get-D { 9 }'
        $before=& $sourceOf $fixture @('unit/A.Tests.ps1','unit/Other.Tests.ps1')
        & $edit $fixture 'scripts/lib/Deep.psm1'
        & $sourceOf $fixture @('unit/A.Tests.ps1','unit/Other.Tests.ps1')|Should -Not -Be $before
    }

    It 'works without a support directory' {
        $fixture=& $newFixture
        [IO.Directory]::Delete([IO.Path]::Combine($fixture.Tests,'support'),$true)
        $before=& $sourceOf $fixture
        & $edit $fixture 'scripts/lib/Helper.psm1'
        & $sourceOf $fixture|Should -BeExactly $before
    }

    It 'rejects <Case>' -ForEach @(
        @{Case='a missing module';Module='lib/Gone.psm1';Files=@('unit/A.Tests.ps1');Expected='ScriptMutationCacheModuleMissing: lib/Gone.psm1'}
        @{Case='a missing unit test file';Module='lib/A.psm1';Files=@('unit/Gone.Tests.ps1');Expected='ScriptMutationCacheTestMissing: unit/Gone.Tests.ps1'}
    ) {
        $fixture=& $newFixture
        {& $sourceOf $fixture $Files $Module}|Should -Throw -ExpectedMessage $Expected
    }
}

Describe 'Get-QuietScriptMutationTestFingerprint' {
    It 'is stable and ignores what the target cannot observe: <Relative>' -ForEach @(
        @{Relative='test/unit/Other.Tests.ps1'}
        @{Relative='test/integration/A.Tests.ps1'}
        @{Relative='test/integration/New.Tests.ps1'}
        @{Relative='test/README.md'}
        @{Relative='test/mutation.targets.psd1'}
        @{Relative='test/coverage.inventory.json'}
        @{Relative='test/ScriptAnalyzer.baseline.json'}
        @{Relative='scripts/lib/A.psm1'}
    ) {
        $fixture=& $newFixture
        $first=& $testsOf $fixture
        $first|Should -Match '^[0-9a-f]{64}$'
        & $edit $fixture $Relative
        & $testsOf $fixture|Should -BeExactly $first
        & $testsOf $fixture @('unit/A.Tests.ps1','unit/A.Tests.ps1')|Should -BeExactly $first
    }

    It 'changes when <Case>' -ForEach @(
        @{Case='a named test file is edited';Change={param($fixture)& $edit $fixture 'test/unit/A.Tests.ps1'}}
        @{Case='a support file is edited';Change={param($fixture)& $edit $fixture 'test/support/Helper.psm1'}}
        @{Case='a support file is added';Change={param($fixture)& $edit $fixture 'test/support/deep/New.psm1'}}
        @{Case='a support file is removed';Change={param($fixture)[IO.File]::Delete((& $pathOf $fixture 'test/support/Helper.psm1'))}}
        @{Case='a support file is renamed';Change={param($fixture)[IO.File]::Move((& $pathOf $fixture 'test/support/Helper.psm1'),(& $pathOf $fixture 'test/support/Renamed.psm1'))}}
        @{Case='an analyzer rule is edited';Change={param($fixture)& $edit $fixture 'test/analyzer/Rules.psm1'}}
        @{Case='the analyzer settings are edited';Change={param($fixture)& $edit $fixture 'test/ScriptAnalyzerSettings.psd1'}}
        @{Case='a nested README is edited';Change={param($fixture)& $edit $fixture 'test/support/README.md'}}
    ) {
        $fixture=& $newFixture
        $before=& $testsOf $fixture
        & $Change $fixture
        & $testsOf $fixture|Should -Not -Be $before
    }

    It 'changes when another unit test file is named' {
        $fixture=& $newFixture
        & $testsOf $fixture @('unit/A.Tests.ps1','unit/Other.Tests.ps1')|Should -Not -Be (& $testsOf $fixture)
    }

    It 'rejects a missing unit test file' {
        $fixture=& $newFixture
        {& $testsOf $fixture @('unit/Gone.Tests.ps1')}|Should -Throw -ExpectedMessage 'ScriptMutationCacheTestMissing: unit/Gone.Tests.ps1'
    }
}

Describe 'Get-QuietScriptMutationInputsFingerprint' {
    It 'is the same for no input and an empty list, and stable' {
        $fixture=& $newFixture
        $none=Get-QuietScriptMutationInputsFingerprint -WorkspaceRoot $fixture.Root
        $none|Should -Match '^[0-9a-f]{64}$'
        & $inputsOf $fixture @()|Should -BeExactly $none
        & $edit $fixture 'build/companions.yml'
        Get-QuietScriptMutationInputsFingerprint -WorkspaceRoot $fixture.Root|Should -BeExactly $none
    }

    It 'with <Pattern>, changes for <Changed> and ignores <Ignored>' -ForEach @(
        @{Pattern='build/companions.yml';Changed='build/companions.yml';Ignored='build/other.yml'}
        @{Pattern='build/*.yml';Changed='build/other.yml';Ignored='build/sub/deep.yml'}
        @{Pattern='.github/containers/**';Changed='.github/containers/base/deep/layer.sh';Ignored='.github/workflows/ci.yml'}
        @{Pattern='.github/containers/**';Changed='.github/containers/top.txt';Ignored='.github/containers.txt'}
        @{Pattern='src/*/ci/**';Changed='src/Git/ci/Get-CiImageArguments.ps1';Ignored='src/Git/other/Get-CiImageArguments.ps1'}
        @{Pattern='src/*/ci/**';Changed='src/Vagrant/ci/new.ps1';Ignored='src/Git/x/ci/nested.ps1'}
        @{Pattern='src/**/ci/*.ps1';Changed='src/Git/x/ci/nested.ps1';Ignored='src/Git/x/ci/deep/nested.ps1'}
        @{Pattern='src/**/ci/*.ps1';Changed='src/ci/top.ps1';Ignored='src/Gitci/top.ps1'}
        @{Pattern='build/*.yml';Changed='build/companions.yml';Ignored='build/other.yml.bak'}
        @{Pattern='*.md';Changed='README.md';Ignored='docs/README.md'}
        @{Pattern='**';Changed='docs/README.md';Ignored='../outside.md'}
    ) {
        $fixture=& $newFixture
        $before=& $inputsOf $fixture @($Pattern)
        & $edit $fixture $Ignored
        & $inputsOf $fixture @($Pattern)|Should -BeExactly $before -Because "$Ignored is outside $Pattern"
        & $edit $fixture $Changed
        & $inputsOf $fixture @($Pattern)|Should -Not -Be $before -Because "$Changed is under $Pattern"
    }

    It 'changes when a file is removed or renamed under a pattern' {
        $fixture=& $newFixture
        $before=& $inputsOf $fixture @('.github/containers/**')
        [IO.File]::Move((& $pathOf $fixture '.github/containers/base/Dockerfile'),(& $pathOf $fixture '.github/containers/base/Dockerfile.old'))
        $renamed=& $inputsOf $fixture @('.github/containers/**')
        $renamed|Should -Not -Be $before
        [IO.File]::Delete((& $pathOf $fixture '.github/containers/base/Dockerfile.old'))
        & $inputsOf $fixture @('.github/containers/**')|Should -Not -BeIn @($before,$renamed)
    }

    It 'counts a pattern without a match, so the first matching file changes the fingerprint' {
        $fixture=& $newFixture
        $none=& $inputsOf $fixture @()
        $empty=& $inputsOf $fixture @('missing/**')
        $empty|Should -Not -Be $none
        & $inputsOf $fixture @('missing/file.txt')|Should -Not -BeIn @($none,$empty)
        & $edit $fixture 'missing/deep/file.txt'
        & $inputsOf $fixture @('missing/**')|Should -Not -Be $empty
    }

    It 'separates the patterns it records: <Left> and <Right> differ' -ForEach @(
        @{Left=@('a','bc');Right=@('ab','c')}
    ) {
        $fixture=& $newFixture
        & $inputsOf $fixture $Left|Should -Not -Be (& $inputsOf $fixture $Right)
    }

    It 'walks only the directory before the first wildcard of <Pattern>' -ForEach @(
        @{Pattern='src/*/ci/**';Walked='src'}
        @{Pattern='.github/containers/**';Walked='.github/containers'}
        @{Pattern='build/*.yml';Walked='build'}
        @{Pattern='**';Walked=''}
    ) {
        $fixture=& $newFixture
        Mock -ModuleName ScriptMutationCache Get-QuietScriptMutationTreeFiles {}
        $null=& $inputsOf $fixture @($Pattern)
        $expected=[IO.Path]::Combine([string[]](@($fixture.Root)+@($Walked.Split('/')|Where-Object {$_})))
        Should -Invoke -ModuleName ScriptMutationCache Get-QuietScriptMutationTreeFiles -Times 1 -Exactly
        Should -Invoke -ModuleName ScriptMutationCache Get-QuietScriptMutationTreeFiles -Times 1 -Exactly -ParameterFilter {$Directory -ceq $expected}
    }

    It 'reads a pattern without wildcard as one file, without walking' {
        $fixture=& $newFixture
        Mock -ModuleName ScriptMutationCache Get-QuietScriptMutationTreeFiles {}
        $before=& $inputsOf $fixture @('build/companions.yml')
        & $edit $fixture 'build/companions.yml'
        & $inputsOf $fixture @('build/companions.yml')|Should -Not -Be $before
        Should -Invoke -ModuleName ScriptMutationCache Get-QuietScriptMutationTreeFiles -Times 0 -Exactly
    }

    It 'escapes the regex characters of a pattern: a dot only matches a dot' {
        $fixture=& $newFixture
        $before=& $inputsOf $fixture @('build/companions.yml')
        & $edit $fixture 'build/companionsXyml'
        & $inputsOf $fixture @('build/companions.yml')|Should -BeExactly $before
    }

    It 'does not depend on the order of the patterns or on files matched twice' {
        $fixture=& $newFixture
        $patterns=@('build/companions.yml','.github/containers/**','src/*/ci/**','*.md','build/*.yml')
        $expected=& $inputsOf $fixture $patterns
        $null=Invoke-QuietProperty -Name 'inputs pattern order' -Seed $seed -Count 25 -Generator {param($random)
            [pscustomobject]@{Patterns=[string[]]@($patterns|Sort-Object {$random.Next()})}
        } -Property {param($case)(& $inputsOf $fixture $case.Patterns) -ceq $expected}
    }
}

Describe 'Get-QuietScriptMutationTargetFingerprint' {
    It 'reads a dictionary and an object target alike, with absent and empty inputs alike' {
        $fixture=& $newFixture
        $arguments=@{ScriptsRoot=$fixture.Scripts;TestsRoot=$fixture.Tests;WorkspaceRoot=$fixture.Root}
        $dictionary=Get-QuietScriptMutationTargetFingerprint @arguments -Target @{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1')}
        $dictionary|Should -Match '^[0-9a-f]{64}$'
        Get-QuietScriptMutationTargetFingerprint @arguments -Target ([pscustomobject]@{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1')})|Should -BeExactly $dictionary
        Get-QuietScriptMutationTargetFingerprint @arguments -Target ([pscustomobject]@{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1');Inputs=@()})|Should -BeExactly $dictionary
        Get-QuietScriptMutationTargetFingerprint @arguments -Target @{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1');Inputs=$null}|Should -BeExactly $dictionary
        $withInputs=Get-QuietScriptMutationTargetFingerprint @arguments -Target @{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1');Inputs=@('build/companions.yml')}
        $withInputs|Should -Not -Be $dictionary
        Get-QuietScriptMutationTargetFingerprint @arguments -Target ([pscustomobject]@{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1');Inputs=@('build/companions.yml')})|Should -BeExactly $withInputs
    }

    It 'changes when <Relative> changes' -ForEach @(
        @{Relative='scripts/lib/B.psm1'};@{Relative='test/support/Helper.psm1'};@{Relative='build/companions.yml'}
    ) {
        $fixture=& $newFixture
        $arguments=@{ScriptsRoot=$fixture.Scripts;TestsRoot=$fixture.Tests;WorkspaceRoot=$fixture.Root}
        $target=@{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1');Inputs=@('build/companions.yml')}
        $before=Get-QuietScriptMutationTargetFingerprint @arguments -Target $target
        & $edit $fixture $Relative
        Get-QuietScriptMutationTargetFingerprint @arguments -Target $target|Should -Not -Be $before
    }

    It 'changes with the declared inputs and the module' {
        $fixture=& $newFixture
        $arguments=@{ScriptsRoot=$fixture.Scripts;TestsRoot=$fixture.Tests;WorkspaceRoot=$fixture.Root}
        $plain=Get-QuietScriptMutationTargetFingerprint @arguments -Target @{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1')}
        Get-QuietScriptMutationTargetFingerprint @arguments -Target @{Module='lib/A.psm1';UnitTestFiles=@('unit/A.Tests.ps1');Inputs=@('build/companions.yml')}|Should -Not -Be $plain
        Get-QuietScriptMutationTargetFingerprint @arguments -Target @{Module='lib/Unrelated.psm1';UnitTestFiles=@('unit/A.Tests.ps1')}|Should -Not -Be $plain
    }
}

Describe 'Get-QuietScriptMutantCacheKeys' {
    It 'gives every mutant a distinct key and is deterministic' {
        $first=& $keysOf
        $first.Mutants.Count|Should -BeGreaterThan 3
        $first.Keys.Count|Should -Be $first.Mutants.Count
        @($first.Values|Sort-Object -Unique).Count|Should -Be $first.Values.Count
        foreach($value in $first.Values){$value|Should -Match '^[0-9a-f]{64}$'}
        (& $keysOf).Values|Should -Be $first.Values
    }

    It 'changes every key when <Case>' -ForEach @(
        @{Case='the target fingerprint changes';Change=@{Target='u'}}
        @{Case='the engine changes';Change=@{Engine='Pester=6.2.1;PowerShell=7.6.0;Platform=test'}}
        @{Case='the module path changes';Change=@{Module='lib/B.psm1'}}
        @{Case='the offsets move';Change=@{Header="# header`n"}}
    ) {
        $before=& $keysOf
        $after=& $keysOf @Change
        foreach($value in $after.Values){$before.Values|Should -Not -Contain $value}
    }

    It 'changes a key with each mutant field: <Field>' -ForEach @(
        @{Field='Function';Value='Get-Z'};@{Field='Mutator';Value='Other'};@{Field='StartOffset';Value=1};@{Field='EndOffset';Value=99};@{Field='Replacement';Value='x'}
    ) {
        $mutant=[pscustomobject]@{Id='m';Module='lib/A.psm1';Function='Get-A';Mutator='StringLiteral';StartOffset=0;EndOffset=5;Replacement='""'}
        $before=(Get-QuietScriptMutantCacheKeys -Mutants @($mutant) -TargetFingerprint 't' -EngineFingerprint 'e')['m']
        $mutant.$Field=$Value
        (Get-QuietScriptMutantCacheKeys -Mutants @($mutant) -TargetFingerprint 't' -EngineFingerprint 'e')['m']|Should -Not -Be $before
    }

    It 'hashes the schema, engine, target and mutant fields in order' {
        $keys=Get-QuietScriptMutantCacheKeys -Mutants @([pscustomobject]@{Id='m';Module='lib/A.psm1';Function='Get-A';Mutator='M';StartOffset=0;EndOffset=5;Replacement='x'}) -TargetFingerprint 't' -EngineFingerprint 'e'
        $keys['m']|Should -BeExactly (Get-QuietScriptMutationSha256 (@('2','e','t','lib/A.psm1','Get-A','M','0','5','x') -join [char]0x1F))
    }

    It 'ignores the mutant id itself' {
        $one=Get-QuietScriptMutantCacheKeys -Mutants @([pscustomobject]@{Id='m1';Module='lib/A.psm1';Function='Get-A';Mutator='M';StartOffset=0;EndOffset=5;Replacement='x'}) -TargetFingerprint 't' -EngineFingerprint 'e'
        $two=Get-QuietScriptMutantCacheKeys -Mutants @([pscustomobject]@{Id='m2';Module='lib/A.psm1';Function='Get-A';Mutator='M';StartOffset=0;EndOffset=5;Replacement='x'}) -TargetFingerprint 't' -EngineFingerprint 'e'
        $two['m2']|Should -BeExactly $one['m1']
    }

    It 'returns an empty dictionary for no mutant' {
        (Get-QuietScriptMutantCacheKeys -Mutants @() -TargetFingerprint 't' -EngineFingerprint 'e').Count|Should -Be 0
    }
}

Describe 'Get-QuietScriptMutantCachePath' {
    It 'shards the documents by the first two key characters' {
        Get-QuietScriptMutantCachePath -Directory 'root' -Key $key|Should -BeExactly ([IO.Path]::Combine('root','ab',$key+'.json'))
    }

    It 'rejects the key <Value>' -ForEach @(
        @{Value='abc'};@{Value=('A'*64)};@{Value=('g'*64)};@{Value=('a'*65)};@{Value=('../'+('a'*61))};@{Value=(('a'*63)+"`n")}
    ) {
        {Get-QuietScriptMutantCachePath -Directory 'root' -Key $Value}|Should -Throw -ExpectedMessage 'ScriptMutationCacheKeyInvalid'
    }
}

Describe 'Read-QuietScriptMutantCache and Write-QuietScriptMutantCache' {
    It 'round-trips <Status>' -ForEach @(@{Status='Killed'},@{Status='Survived'}) {
        $cache=& $newCache
        Write-QuietScriptMutantCache -Directory $cache -Key $key -Status $Status -Seconds 1.26 -Seed 77|Should -BeTrue
        $hit=Read-QuietScriptMutantCache -Directory $cache -Key $key
        $hit.Status|Should -BeExactly $Status
        $hit.Seconds|Should -Be 1.3
        $hit.Seed|Should -Be 77
    }

    It 'clamps a negative duration to zero' {
        $cache=& $newCache
        $null=Write-QuietScriptMutantCache -Directory $cache -Key $key -Status Killed -Seconds -4 -Seed 1
        (Read-QuietScriptMutantCache -Directory $cache -Key $key).Seconds|Should -Be 0
    }

    It 'never writes <Status>' -ForEach @(@{Status='Timeout'},@{Status='CompileError'},@{Status='killed'},@{Status=''}) {
        $cache=& $newCache
        $written=Write-QuietScriptMutantCache -Directory $cache -Key $key -Status $Status -Seconds 1 -Seed 1
        $written -is [bool]|Should -BeTrue -Because 'the caller counts the writes'
        $written|Should -BeFalse
        [IO.Directory]::Exists($cache)|Should -BeFalse
    }

    It 'misses when nothing is cached' {
        Read-QuietScriptMutantCache -Directory (& $newCache) -Key $key|Should -BeNullOrEmpty
    }

    It 'treats <Case> as a miss' -ForEach @(
        @{Case='invalid JSON';Text='{'}
        @{Case='an array';Text='[1]'}
        @{Case='a scalar';Text='3'}
        @{Case='another schema';Text=('{"SchemaVersion":2,"Key":"KEY","Status":"Killed","Seconds":1,"Seed":1}')}
        @{Case='a missing schema';Text=('{"Key":"KEY","Status":"Killed","Seconds":1,"Seed":1}')}
        @{Case='another key';Text=('{"SchemaVersion":1,"Key":"'+('d'*64)+'","Status":"Killed","Seconds":1,"Seed":1}')}
        @{Case='a Timeout status';Text=('{"SchemaVersion":1,"Key":"KEY","Status":"Timeout","Seconds":1,"Seed":1}')}
        @{Case='a lowercase status';Text=('{"SchemaVersion":1,"Key":"KEY","Status":"killed","Seconds":1,"Seed":1}')}
        @{Case='a negative duration';Text=('{"SchemaVersion":1,"Key":"KEY","Status":"Killed","Seconds":-1,"Seed":1}')}
        @{Case='a text duration';Text=('{"SchemaVersion":1,"Key":"KEY","Status":"Killed","Seconds":"slow","Seed":1}')}
        @{Case='invalid UTF-8';Text=$null}
        @{Case='invalid UTF-8 inside an otherwise valid document';Text=$null;Bytes='{"SchemaVersion":1,"Key":"KEY","Status":"Killed","Seconds":1,"Seed":1,"Note":"#"}'}
    ) {
        $cache=& $newCache
        if($null -eq $Text){
            $path=Get-QuietScriptMutantCachePath -Directory $cache -Key $key
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
            if($Bytes){$parts=$Bytes.Replace('KEY',$key).Split('#');[IO.File]::WriteAllBytes($path,[byte[]]@([Text.Encoding]::UTF8.GetBytes($parts[0])+[byte]0xFF+[Text.Encoding]::UTF8.GetBytes($parts[1])))}
            else{[IO.File]::WriteAllBytes($path,[byte[]](0x7B,0xFF,0xFE,0x7D))}
        }else{& $writeDocument $cache $Text.Replace('KEY',$key)}
        Read-QuietScriptMutantCache -Directory $cache -Key $key|Should -BeNullOrEmpty
    }

    It 'overwrites an unusable document with the next outcome' {
        $cache=& $newCache
        & $writeDocument $cache '{'
        Write-QuietScriptMutantCache -Directory $cache -Key $key -Status Survived -Seconds 2 -Seed 3|Should -BeTrue
        (Read-QuietScriptMutantCache -Directory $cache -Key $key).Status|Should -BeExactly 'Survived'
    }

    It 'never throws and returns only valid hits on fuzzed documents' {
        $null=Invoke-QuietProperty -Name 'fuzzed cache documents' -Seed $seed -Count 200 -Generator {param($random)
            $values=@('null','""','1','-1','0.5','"1"','"Killed"','"Survived"','"Timeout"','true','[]','{}',('"'+$key+'"'),'"x"')
            $pairs=foreach($name in Get-QuietRandomSubset $random @('SchemaVersion','Key','Status','Seconds','Seed','Other') 0.8){'"'+$name+'":'+(Get-QuietRandomItem $random $values)}
            $text='{'+(@($pairs) -join ',')+'}'
            if($random.Next(6) -eq 0){$text=$text.Substring(0,$random.Next(0,$text.Length))}
            [pscustomobject]@{Text=$text}
        } -Property {param($case)
            $cache=& $newCache
            & $writeDocument $cache $case.Text
            $hit=Read-QuietScriptMutantCache -Directory $cache -Key $key
            $null -eq $hit -or ($hit.Status -cin @('Killed','Survived') -and $hit.Seconds -ge 0)
        }
    }
}

Describe 'Read-QuietScriptMutationCacheDocument' {
    It 'returns <Case> as <Expected>' -ForEach @(
        @{Case='an object';Text='{"a":1}';Expected='an object'}
        @{Case='a scalar';Text='3';Expected='nothing'}
        @{Case='a string';Text='"x"';Expected='nothing'}
        @{Case='invalid JSON';Text='{';Expected='nothing'}
        @{Case='a missing file';Text=$null;Expected='nothing'}
    ) {
        $path=[IO.Path]::Combine($TestDrive,'document-'+[guid]::NewGuid().ToString('N')+'.json')
        if($null -ne $Text){[IO.File]::WriteAllText($path,$Text)}
        $document=InModuleScope ScriptMutationCache -Parameters @{Path=$path} {param($Path)Read-QuietScriptMutationCacheDocument -Path $Path}
        if($Expected -ceq 'an object'){$document|Should -BeOfType [pscustomobject];$document.a|Should -Be 1}
        else{$document|Should -BeNullOrEmpty}
    }
}

Describe 'Get-QuietScriptMutationBaselineKey' {
    It 'hashes the kind, schema, engine, target and machine in order' {
        Get-QuietScriptMutationBaselineKey -TargetFingerprint 't' -EngineFingerprint 'e' -Machine 'm'|Should -BeExactly (Get-QuietScriptMutationSha256 (@('baseline','1','e','t','m') -join [char]0x1F))
    }

    It 'changes with the <Field>' -ForEach @(@{Field='TargetFingerprint'},@{Field='EngineFingerprint'},@{Field='Machine'}) {
        $arguments=@{TargetFingerprint='t';EngineFingerprint='e';Machine='m'}
        $before=Get-QuietScriptMutationBaselineKey @arguments
        $arguments[$Field]='x'
        Get-QuietScriptMutationBaselineKey @arguments|Should -Not -BeExactly $before
    }
}

Describe 'Read-QuietScriptMutationBaseline and Write-QuietScriptMutationBaseline' {
    It 'round-trips a baseline' {
        $cache=& $newCache
        Write-QuietScriptMutationBaseline -Directory $cache -Key $key -Passed 12 -Seconds 3.26|Should -BeTrue
        $baseline=Read-QuietScriptMutationBaseline -Directory $cache -Key $key
        $baseline.Passed|Should -BeExactly 12
        $baseline.Seconds|Should -Be 3.3
    }

    It 'records the smallest valid baseline: one test in no time' {
        $cache=& $newCache
        Write-QuietScriptMutationBaseline -Directory $cache -Key $key -Passed 1 -Seconds 0|Should -BeTrue
        $baseline=Read-QuietScriptMutationBaseline -Directory $cache -Key $key
        $baseline.Passed|Should -Be 1
        $baseline.Seconds|Should -Be 0
    }

    It 'never writes <Case>' -ForEach @(
        @{Case='no passed test';Passed=0;Seconds=1}
        @{Case='a negative duration';Passed=1;Seconds=-0.1}
        @{Case='an infinite duration';Passed=1;Seconds=[double]::PositiveInfinity}
        @{Case='a NaN duration';Passed=1;Seconds=[double]::NaN}
    ) {
        $cache=& $newCache
        $written=Write-QuietScriptMutationBaseline -Directory $cache -Key $key -Passed $Passed -Seconds $Seconds
        $written -is [bool]|Should -BeTrue
        $written|Should -BeFalse
        [IO.Directory]::Exists($cache)|Should -BeFalse
    }

    It 'never reads a baseline as a mutant outcome, nor an outcome as a baseline' {
        $cache=& $newCache
        $null=Write-QuietScriptMutationBaseline -Directory $cache -Key $key -Passed 2 -Seconds 1
        Read-QuietScriptMutantCache -Directory $cache -Key $key|Should -BeNullOrEmpty
        $null=Write-QuietScriptMutantCache -Directory $cache -Key $key -Status Killed -Seconds 1 -Seed 1
        Read-QuietScriptMutationBaseline -Directory $cache -Key $key|Should -BeNullOrEmpty
    }

    It 'reads a hand-written document with an integer duration' {
        $cache=& $newCache
        & $writeDocument $cache ('{"SchemaVersion":1,"Kind":"Baseline","Key":"'+$key+'","Passed":3,"Seconds":2}')
        $baseline=Read-QuietScriptMutationBaseline -Directory $cache -Key $key
        $baseline.Passed|Should -Be 3
        $baseline.Seconds|Should -Be 2
    }

    It 'treats <Case> as a miss' -ForEach @(
        @{Case='nothing cached';Text=$null}
        @{Case='invalid JSON';Text='{'}
        @{Case='a scalar';Text='3'}
        @{Case='another schema';Text='{"SchemaVersion":2,"Kind":"Baseline","Key":"KEY","Passed":1,"Seconds":1}'}
        @{Case='a lowercase kind';Text='{"SchemaVersion":1,"Kind":"baseline","Key":"KEY","Passed":1,"Seconds":1}'}
        @{Case='a missing kind';Text='{"SchemaVersion":1,"Key":"KEY","Passed":1,"Seconds":1}'}
        @{Case='another key';Text=('{"SchemaVersion":1,"Kind":"Baseline","Key":"'+('d'*64)+'","Passed":1,"Seconds":1}')}
        @{Case='no passed test';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Passed":0,"Seconds":1}'}
        @{Case='a fractional count';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Passed":1.5,"Seconds":1}'}
        @{Case='a signed count';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Passed":"+1","Seconds":1}'}
        @{Case='a missing count';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Seconds":1}'}
        @{Case='a negative duration';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Passed":1,"Seconds":-1}'}
        @{Case='a NaN duration';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Passed":1,"Seconds":"NaN"}'}
        @{Case='an infinite duration';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Passed":1,"Seconds":"Infinity"}'}
        @{Case='a text duration';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Passed":1,"Seconds":"slow"}'}
        @{Case='a missing duration';Text='{"SchemaVersion":1,"Kind":"Baseline","Key":"KEY","Passed":1}'}
    ) {
        $cache=& $newCache
        if($null -ne $Text){& $writeDocument $cache $Text.Replace('KEY',$key)}
        Read-QuietScriptMutationBaseline -Directory $cache -Key $key|Should -BeNullOrEmpty
    }
}

Describe 'Remove-QuietScriptMutantCacheUnused' {
    BeforeAll {
        $keyOf={param([int]$Index)(Get-QuietScriptMutationSha256 ([string]$Index))}
        $fill={param([string]$Cache,[int]$Count)
            foreach($index in 1..$Count){$null=Write-QuietScriptMutantCache -Directory $Cache -Key (& $keyOf $index) -Status Killed -Seconds 1 -Seed 1}
        }
        $listed={param([string]$Cache)@(if([IO.Directory]::Exists($Cache)){[IO.Directory]::EnumerateFiles($Cache,'*',[IO.SearchOption]::AllDirectories)|ForEach-Object {[IO.Path]::GetRelativePath($Cache,$_).Replace('\','/')}|Sort-Object -CaseSensitive})}
    }

    It 'keeps exactly the given keys and removes empty shard directories' {
        $cache=& $newCache
        & $fill $cache 40
        $keep=@(1..10|ForEach-Object {& $keyOf $_})
        Remove-QuietScriptMutantCacheUnused -Directory $cache -Keys $keep|Should -Be 30
        & $listed $cache|Should -Be @($keep|ForEach-Object {$_.Substring(0,2)+'/'+$_+'.json'}|Sort-Object -CaseSensitive)
        foreach($directory in [IO.Directory]::EnumerateDirectories($cache)){@([IO.Directory]::EnumerateFileSystemEntries($directory)).Count|Should -BeGreaterThan 0}
        foreach($key in $keep){Read-QuietScriptMutantCache -Directory $cache -Key $key|Should -Not -BeNullOrEmpty}
    }

    It 'removes everything for no key and is idempotent' {
        $cache=& $newCache
        & $fill $cache 5
        Remove-QuietScriptMutantCacheUnused -Directory $cache -Keys @()|Should -Be 5
        @([IO.Directory]::EnumerateFileSystemEntries($cache)).Count|Should -Be 0
        Remove-QuietScriptMutantCacheUnused -Directory $cache -Keys @()|Should -Be 0
    }

    It 'returns 0 for a missing directory' {
        Remove-QuietScriptMutantCacheUnused -Directory (& $newCache) -Keys @($key)|Should -Be 0
    }

    It 'leaves alone every file that is not a cache document: <Relative>' -ForEach @(
        @{Relative='README.md'};@{Relative='ab/notes.txt'};@{Relative='ab/ABCD.json'};@{Relative='ab/short.json'}
        @{Relative=('ab/'+('ab'+('c'*62))+'.txt')};@{Relative='ab/abnotes.json'};@{Relative=('abc/'+('abc'+('c'*61))+'.json')};@{Relative=('a/'+('a'+('c'*63))+'.json')}
        @{Relative=('cd/'+('ab'+('c'*62))+'.json')};@{Relative=('xyz/'+('a'*64)+'.json')};@{Relative=('AB/'+('ab'+('c'*62))+'.json')}
    ) {
        $cache=& $newCache
        $null=New-QuietTestFile ([IO.Path]::Combine([string[]](@($cache)+$Relative.Split('/')))) 'kept'
        Remove-QuietScriptMutantCacheUnused -Directory $cache -Keys @()|Should -Be 0
        & $listed $cache|Should -Be @($Relative)
    }
}
