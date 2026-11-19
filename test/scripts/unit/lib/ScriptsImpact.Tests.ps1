#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptsImpact
    $seed=Get-QuietTestSeed
    # A fixture repository: a test runner and a mutation engine with their own libraries, two targets (A reads C as an
    # input), an entry point, a script data file, and tests that reach them directly, through imports, or by header.
    $files=[ordered]@{
        'scripts/Invoke-ScriptsTests.ps1'="Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'lib/Runner.psm1'))"
        'scripts/Invoke-ScriptsMutation.ps1'="Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'lib/Engine.psm1'))"
        'scripts/Entry.ps1'="Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'lib','C.psm1'))"
        'scripts/data.json'='{}'
        'scripts/lib/Runner.psm1'='function Invoke-R { }'
        'scripts/lib/Engine.psm1'='function Invoke-E { }'
        'scripts/lib/A.psm1'="Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'B.psm1'))`nfunction Get-A { }"
        'scripts/lib/B.psm1'='function Get-B { }'
        'scripts/lib/C.psm1'='function Get-C { }'
        'scripts/lib/Unused.psm1'='function Get-U { }'
        'scripts/lib/README.md'='# libs'
        'test/scripts/mutation.targets.psd1'="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/A.Tests.ps1');Break=80;Inputs=@('scripts/lib/C.psm1')};@{Name='C';Module='lib/C.psm1';Functions=@('Get-C');UnitTestFiles=@('unit/C.Tests.ps1');Break=80})}"
        'test/scripts/README.md'='# tests'
        'test/scripts/support/Helper.psm1'='function Get-H { }'
        'test/scripts/unit/A.Tests.ps1'="Import-QuietTestLibrary -Name A`nDescribe a { }"
        # D is reached only through C's unit test, not through C's module.
        'scripts/lib/D.psm1'='function Get-D { }'
        'test/scripts/unit/C.Tests.ps1'="`$null=Import-QuietTestLibrary 'C'`n`$null=Import-QuietTestLibrary 'D'`nDescribe c { }"
        'test/scripts/unit/All.Tests.ps1'="#requires -Version 7.6`n#ScriptsImpact: AllScripts`nDescribe all { }"
        'test/scripts/unit/Helper.ps1'='function Get-L { }'
        'test/scripts/unit/Quoted.Tests.ps1'="Describe q { It r { '#ScriptsImpact: AllScripts' } }"
        'test/scripts/integration/Entry.Tests.ps1'="#ScriptsImpact: RequiresBuild`nDescribe e { It r { & ([IO.Path]::Combine(`$root,'Entry.ps1')) } }"
    }
    $newFixture={
        $root=[IO.Path]::Combine($TestDrive,'repo-'+[guid]::NewGuid().ToString('N'))
        foreach($entry in $files.GetEnumerator()){$null=New-QuietTestFile ([IO.Path]::Combine([string[]](@($root)+$entry.Key.Split('/')))) $entry.Value}
        $root
    }
    # Runs a script in a new runspace with no enclosing try, optionally while a file is held without sharing. A .NET read
    # failure then ends the library call only when the library itself stops on errors; otherwise the call goes on and
    # returns a result built without that file. Returns the call's output.
    $withoutTry={param([string]$Locked,[string]$Script,[string]$Root)
        $lock=if($Locked){[IO.File]::Open($Locked,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)}
        $shell=[powershell]::Create()
        try{
            $null=$shell.AddScript($Script).AddArgument((Get-Module ScriptsImpact).Path).AddArgument($Root)
            $output=try{@($shell.Invoke())}catch{@()}
            ,[object[]]$output
        }finally{$shell.Dispose();if($lock){$lock.Dispose()}}
    }
    $allTests=@('integration/Entry.Tests.ps1','unit/A.Tests.ps1','unit/All.Tests.ps1','unit/C.Tests.ps1','unit/Quoted.Tests.ps1')
    # Paths whose change is decided by what reaches them, so the selection grows with the changed set.
    $selective=@('scripts/Entry.ps1','scripts/lib/A.psm1','scripts/lib/B.psm1','scripts/lib/C.psm1','scripts/lib/Unused.psm1','scripts/lib/README.md','test/scripts/unit/A.Tests.ps1','test/scripts/unit/C.Tests.ps1','test/scripts/integration/Entry.Tests.ps1','test/scripts/README.md')
}

Describe 'Get-QuietScriptsTestFiles' {
    It 'lists the unit and integration test files relative to the tests root, in ordinal order' {
        $root=& $newFixture
        Get-QuietScriptsTestFiles ([IO.Path]::Combine($root,'test','scripts'))|Should -Be $allTests
    }

    It 'returns nothing for a tests root without unit or integration directory' {
        @(Get-QuietScriptsTestFiles ([IO.Path]::Combine($TestDrive,'missing-'+[guid]::NewGuid().ToString('N')))).Count|Should -Be 0
    }
}

Describe 'Get-QuietScriptsImpact' {
    BeforeAll {$root=& $newFixture}

    It 'for <Path>, selects tests <Tests> and targets <Targets>' -ForEach @(
        @{Path='scripts/lib/B.psm1';Tests='unit/A.Tests.ps1,unit/All.Tests.ps1';Targets='A'}
        @{Path='scripts/lib/C.psm1';Tests='integration/Entry.Tests.ps1,unit/All.Tests.ps1,unit/C.Tests.ps1';Targets='A,C'}
        @{Path='scripts/lib/A.psm1';Tests='unit/A.Tests.ps1,unit/All.Tests.ps1';Targets='A'}
        @{Path='scripts/Entry.ps1';Tests='integration/Entry.Tests.ps1,unit/All.Tests.ps1';Targets=''}
        @{Path='scripts/lib/Unused.psm1';Tests='unit/All.Tests.ps1';Targets=''}
        @{Path='scripts/lib/D.psm1';Tests='unit/All.Tests.ps1,unit/C.Tests.ps1';Targets='C'}
        @{Path='test/scripts/unit/A.Tests.ps1';Tests='unit/A.Tests.ps1,unit/All.Tests.ps1';Targets='A'}
        @{Path='test/scripts/integration/Entry.Tests.ps1';Tests='integration/Entry.Tests.ps1,unit/All.Tests.ps1';Targets=''}
        @{Path='scripts/lib/README.md';Tests='';Targets=''}
        @{Path='test/scripts/README.md';Tests='';Targets=''}
    ) {
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($Path)
        $impact.SchemaVersion|Should -Be 1
        $impact.AllTests|Should -BeFalse
        $impact.AllTargets|Should -BeFalse
        $impact.TestFiles -join ','|Should -BeExactly $Tests
        $impact.MutationTargets -join ','|Should -BeExactly $Targets
        ,$impact.TestFiles|Should -BeOfType [string[]]
        ,$impact.MutationTargets|Should -BeOfType [string[]]
    }

    It 'names one reason per selection, each starting with the changed path: <Path> is <Why>' -ForEach @(
        @{Path='scripts/lib/B.psm1';Name='unit/A.Tests.ps1';Selection='script-test';Why='ReachesScript'}
        @{Path='scripts/lib/B.psm1';Name='unit/All.Tests.ps1';Selection='script-test';Why='ReadsEveryScript'}
        @{Path='test/scripts/unit/C.Tests.ps1';Name='unit/C.Tests.ps1';Selection='script-test';Why='TestChanged'}
        @{Path='scripts/lib/C.psm1';Name='A';Selection='script-mutation';Why='ReachesTarget'}
    ) {
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($Path)
        @($impact.Reasons).Count|Should -Be ($impact.TestFiles.Count+$impact.MutationTargets.Count)
        $rows=@($impact.Reasons|Where-Object {$_.Name -ceq $Name})
        $rows.Count|Should -Be 1
        $rows[0].Selection|Should -BeExactly $Selection
        $rows[0].Reason|Should -BeExactly ($Path+': '+$Why)
    }

    It 'does not take a quoted header for a declaration of its own' {
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @('scripts/lib/Unused.psm1')
        $impact.TestFiles|Should -Not -Contain 'unit/Quoted.Tests.ps1'
    }

    It 'selects every test and every target when <Path> changes (<Why>)' -ForEach @(
        @{Path='scripts/data.json';Why='ScriptData'}
        @{Path='scripts/lib/Gone.psm1';Why='DeletedScriptInput'}
        @{Path='test/scripts/unit/Gone.Tests.ps1';Why='DeletedScriptInput'}
        @{Path='test/scripts/support/Helper.psm1';Why='SharedTestInput'}
        @{Path='test/scripts/mutation.targets.psd1';Why='SharedTestInput'}
        @{Path='test/scripts/unit/Helper.ps1';Why='SharedTestInput'}
        @{Path='scripts/lib/Runner.psm1';Why='TestRunnerChanged'}
        @{Path='scripts/Invoke-ScriptsTests.ps1';Why='TestRunnerChanged'}
    ) {
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @('scripts/lib/B.psm1',$Path)
        $impact.AllTests|Should -BeTrue
        $impact.AllTargets|Should -BeTrue
        $impact.TestFiles|Should -Be $allTests
        $impact.MutationTargets -join ','|Should -BeExactly 'A,C'
        @($impact.Reasons|Where-Object {$_.Reason -cne ($Path+': '+$Why)}).Count|Should -Be 0 -Because 'the first reason that selects everything explains every selection'
    }

    It 'selects every target, and only the tests that reach it, when <Path> changes the mutation engine' -ForEach @(
        @{Path='scripts/lib/Engine.psm1'}
        @{Path='scripts/Invoke-ScriptsMutation.ps1'}
    ) {
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($Path)
        $impact.AllTests|Should -BeFalse
        $impact.AllTargets|Should -BeTrue
        $impact.TestFiles -join ','|Should -BeExactly 'unit/All.Tests.ps1'
        $impact.MutationTargets -join ','|Should -BeExactly 'A,C'
        @($impact.Reasons|Where-Object Selection -CEQ 'script-mutation'|ForEach-Object Reason|Sort-Object -Unique)|Should -Be @($Path+': MutationEngineChanged')
    }

    It 'selects only the added or edited catalogue entries and their tests (<Action>)' -ForEach @(
        @{Action='addition';Expected='C'}
        @{Action='threshold';Expected='A'}
        @{Action='formatting';Expected=''}
    ) {
        $path='test/scripts/mutation.targets.psd1'
        $current=$files[$path]
        $baseline=switch($Action){
            'addition' {"@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/A.Tests.ps1');Break=80;Inputs=@('scripts/lib/C.psm1')})}"}
            'threshold' {$current.Replace("Break=80;Inputs","Break=79;Inputs")}
            'formatting' {$current.Replace("Name='C';Module='lib/C.psm1'","Module='lib/C.psm1'; Name='C'")}
        }
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($path) -PreviousMutationCatalogue $baseline
        $impact.AllTests | Should -BeFalse
        $impact.AllTargets | Should -BeFalse
        ($impact.MutationTargets -join ',') | Should -BeExactly $Expected
        $expectedTest=if($Expected){"unit/$Expected.Tests.ps1"}else{''}
        ($impact.TestFiles -join ',') | Should -BeExactly $expectedTest
        foreach($reason in $impact.Reasons){$reason.Reason | Should -BeExactly "${path}: MutationTargetChanged"}
    }

    It 'keeps the shared-input fallback for a removed target or malformed baseline' {
        $path='test/scripts/mutation.targets.psd1'
        $withRemovedTarget=$files[$path].Replace("Name='A'","Name='Removed'").Replace("Name='C'","Name='A'")
        foreach($baseline in $withRemovedTarget,'throw "not a literal catalogue"'){
            $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($path) -PreviousMutationCatalogue $baseline
            $impact.AllTests | Should -BeTrue
            $impact.AllTargets | Should -BeTrue
        }
    }

    It 'combines catalogue targets with the tests and targets reached by changed scripts' {
        $path='test/scripts/mutation.targets.psd1'
        $baseline=$files[$path].Replace("Break=80;Inputs","Break=79;Inputs")
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($path,'scripts/lib/D.psm1') -PreviousMutationCatalogue $baseline
        ($impact.TestFiles -join ',') | Should -BeExactly 'unit/A.Tests.ps1,unit/All.Tests.ps1,unit/C.Tests.ps1'
        ($impact.MutationTargets -join ',') | Should -BeExactly 'A,C'
    }

    It 'selects nothing for no change' {
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @()
        $impact.TestFiles.Count+$impact.MutationTargets.Count+@($impact.Reasons).Count|Should -Be 0
        $impact.AllTests -or $impact.AllTargets|Should -BeFalse
    }

    It 'keeps the first reason that selects everything when <Later> follows it' -ForEach @(
        @{Later='test/scripts/support/Helper.psm1'}
        @{Later='scripts/lib/Runner.psm1'}
    ) {
        $impact=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @('scripts/data.json',$Later)
        $impact.TestFiles|Should -Be $allTests
        $impact.MutationTargets -join ','|Should -BeExactly 'A,C'
        @($impact.Reasons|ForEach-Object Reason|Sort-Object -Unique)|Should -Be @('scripts/data.json: ScriptData')
    }

    It 'reads no closure when no script changed' {
        Mock -ModuleName ScriptsImpact Get-QuietScriptMutationSourceFiles {throw 'ClosureRead'}
        Mock -ModuleName ScriptsImpact Get-QuietScriptMutationInputFiles {throw 'InputsRead'}
        $none=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @()
        $docs=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @('scripts/lib/README.md','test/scripts/README.md')
        $none.TestFiles.Count+$none.MutationTargets.Count+$docs.TestFiles.Count+$docs.MutationTargets.Count|Should -Be 0
        Should -Invoke -ModuleName ScriptsImpact Get-QuietScriptMutationSourceFiles -Times 0 -Exactly
        Should -Invoke -ModuleName ScriptsImpact Get-QuietScriptMutationInputFiles -Times 0 -Exactly
    }

    It 'stops at an unreadable test file instead of returning a partial selection' {
        $script='param($Module,$Root) Import-Module $Module -DisableNameChecking; Get-QuietScriptsImpact -WorkspaceRoot $Root -ChangedPaths @(''scripts/lib/Unused.psm1'')'
        $readable=& $withoutTry '' $script $root
        $readable.Count|Should -Be 1
        $readable[0].TestFiles -join ','|Should -BeExactly 'unit/All.Tests.ps1'
        (& $withoutTry ([IO.Path]::Combine($root,'test','scripts','unit','Quoted.Tests.ps1')) $script $root).Count|Should -Be 0
    }

    It 'rejects the unsafe path <Case>' -ForEach @(
        @{Case='empty';Path=''}
        @{Case='rooted';Path='/scripts/lib/A.psm1'}
        @{Case='backslash';Path='scripts\lib\A.psm1'}
        @{Case='parent';Path='scripts/../src/x.ps1'}
        @{Case='NUL';Path="scripts/lib/A.psm1$([char]0)"}
    ) {
        {Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @('scripts/lib/B.psm1',$Path)}|Should -Throw -ExpectedMessage 'ScriptsImpactPathInvalid'
    }

    It 'rejects <Path>, outside scripts/ and test/scripts/' -ForEach @(
        @{Path='src/Core/x.ps1'}
        @{Path='test/other/x.Tests.ps1'}
        @{Path='Scripts/lib/A.psm1'}
        @{Path='scriptsx/A.psm1'}
    ) {
        {Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($Path)}|Should -Throw -ExpectedMessage ('ScriptsImpactPathOutsideScripts: '+$Path)
    }

    It 'only grows when a change is added, whatever the order of the changes' {
        Invoke-QuietProperty -Name 'scripts impact is monotonic and order invariant' -Seed $seed -Count 25 -Generator {
            param([Random]$Random)
            $first=[string[]](Get-QuietRandomSubset -Random $Random -Items $selective)
            [pscustomobject]@{First=$first;Added=(Get-QuietRandomItem -Random $Random -Items $selective);Shuffled=[string[]](Get-QuietShuffle -Random $Random -Items (@($first)+@('scripts/lib/B.psm1')))}
        } -Property {
            param($Case)
            $before=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($Case.First)
            $after=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths (@($Case.First)+@($Case.Added))
            foreach($name in $before.TestFiles){if($name -cnotin $after.TestFiles){throw "test $name lost"}}
            foreach($name in $before.MutationTargets){if($name -cnotin $after.MutationTargets){throw "target $name lost"}}
            $ordered=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths (@($Case.First)+@('scripts/lib/B.psm1'))
            $shuffled=Get-QuietScriptsImpact -WorkspaceRoot $root -ChangedPaths @($Case.Shuffled)
            ($ordered.TestFiles -join ',') -ceq ($shuffled.TestFiles -join ',') -and ($ordered.MutationTargets -join ',') -ceq ($shuffled.MutationTargets -join ',')
        }|Should -Be 25
    }
}

Describe 'Resolve-QuietScriptsCiSelection' {
    BeforeAll {$root=& $newFixture}

    It 'expands the full scope to every test, kept as all, and every target in catalogue order' {
        $selection=Resolve-QuietScriptsCiSelection -WorkspaceRoot $root -Scope full -Tests all -Targets all
        $selection.AllTests|Should -BeTrue
        $selection.TestFiles|Should -Be $allTests
        $selection.MutationTargets -join ','|Should -BeExactly 'A,C'
        $selection.RequiresBuild|Should -BeTrue -Because 'integration/Entry.Tests.ps1 declares the build'
    }

    It 'keeps the scripts selection <Tests> / <Targets> in catalogue order, building only for a test that declares it' -ForEach @(
        @{Tests='["unit/C.Tests.ps1","unit/A.Tests.ps1"]';Targets='["C","A"]';Files='unit/A.Tests.ps1,unit/C.Tests.ps1';Names='A,C';Build=$false}
        @{Tests='["integration/Entry.Tests.ps1"]';Targets='[]';Files='integration/Entry.Tests.ps1';Names='';Build=$true}
        @{Tests='[]';Targets='["C"]';Files='';Names='C';Build=$false}
        @{Tests='[]';Targets='all';Files='';Names='A,C';Build=$false}
    ) {
        $selection=Resolve-QuietScriptsCiSelection -WorkspaceRoot $root -Scope scripts -Tests $Tests -Targets $Targets
        $selection.AllTests|Should -BeFalse
        $selection.TestFiles -join ','|Should -BeExactly $Files
        $selection.MutationTargets -join ','|Should -BeExactly $Names
        $selection.RequiresBuild|Should -Be $Build
        ,$selection.TestFiles|Should -BeOfType [string[]]
        ,$selection.MutationTargets|Should -BeOfType [string[]]
    }

    It 'rejects <Case>' -ForEach @(
        @{Case='an unknown scope';Scope='Full';Tests='all';Targets='all';Message='ToolingScopeInvalid'}
        @{Case='a full scope with selected tests';Scope='full';Tests='[]';Targets='all';Message='ToolingFullScopeSelectsAll'}
        @{Case='a full scope with selected targets';Scope='full';Tests='all';Targets='["A"]';Message='ToolingFullScopeSelectsAll'}
        @{Case='a value that is not JSON';Scope='scripts';Tests='All';Targets='all';Message='ScriptsCiSelectionInvalid'}
        @{Case='a JSON string';Scope='scripts';Tests='"unit/A.Tests.ps1"';Targets='all';Message='ScriptsCiSelectionInvalid'}
        @{Case='a JSON object';Scope='scripts';Tests='all';Targets='{"A":1}';Message='ScriptsCiSelectionInvalid'}
        @{Case='a number in the list';Scope='scripts';Tests='[1]';Targets='all';Message='ScriptsCiSelectionInvalid'}
        @{Case='an empty name';Scope='scripts';Tests='all';Targets='[""]';Message='ScriptsCiSelectionInvalid'}
        @{Case='an unknown test file';Scope='scripts';Tests='["unit/Helper.ps1"]';Targets='all';Message='ScriptsCiTestUnknown: unit/Helper.ps1'}
        @{Case='a test name of another case';Scope='scripts';Tests='["unit/a.Tests.ps1"]';Targets='all';Message='ScriptsCiTestUnknown: unit/a.Tests.ps1'}
        @{Case='an unknown target';Scope='scripts';Tests='all';Targets='["A","B"]';Message='ScriptsCiTargetUnknown: B'}
    ) {
        {Resolve-QuietScriptsCiSelection -WorkspaceRoot $root -Scope $Scope -Tests $Tests -Targets $Targets}|Should -Throw -ExpectedMessage $Message
    }

    It 'stops at an unreadable selected test file instead of guessing the build' {
        $script='param($Module,$Root) Import-Module $Module -DisableNameChecking; Resolve-QuietScriptsCiSelection -WorkspaceRoot $Root -Scope scripts -Tests ''["integration/Entry.Tests.ps1"]'' -Targets ''[]'''
        $readable=& $withoutTry '' $script $root
        $readable.Count|Should -Be 1
        $readable[0].RequiresBuild|Should -BeTrue
        (& $withoutTry ([IO.Path]::Combine($root,'test','scripts','integration','Entry.Tests.ps1')) $script $root).Count|Should -Be 0
    }

    It 'fails only with a typed error on fuzzed selections' {
        Invoke-QuietProperty -Name 'fuzzed CI selections fail typed' -Seed $seed -Count 60 -Generator {
            param([Random]$Random)
            $pieces=@('[',']','"','unit/A.Tests.ps1','A',',','{','}','null','1','all',' ',"`n",'\u0000','..')
            -join @(1..($Random.Next(1,8))|ForEach-Object {Get-QuietRandomItem -Random $Random -Items $pieces})
        } -Property {
            param([string]$Case)
            foreach($pair in @(@($Case,'all'),@('all',$Case))){
                try{$null=Resolve-QuietScriptsCiSelection -WorkspaceRoot $root -Scope scripts -Tests $pair[0] -Targets $pair[1]}
                catch{if($_.Exception.Message -cnotmatch '^(ScriptsCiSelectionInvalid|ScriptsCiTestUnknown: |ScriptsCiTargetUnknown: )'){throw $_}}
            }
            $true
        }|Should -Be 60
    }
}
