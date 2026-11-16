#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Test-ScriptAnalysis.ps1')
    $repository=Get-QuietTestWorkspaceRoot
    $available=[IO.File]::Exists([IO.Path]::Combine($repository,'.cache','test-tools','PSScriptAnalyzer','PSScriptAnalyzer.psd1'))
    $newWorkspace={param([hashtable]$Files)
        $root=[IO.Path]::Combine($TestDrive,'ws-'+[guid]::NewGuid().ToString('N'))
        foreach($relative in @('test/scripts/ScriptAnalyzerSettings.psd1','test/scripts/analyzer/QuietCliRules.psm1')){
            $null=New-QuietTestFile ([IO.Path]::Combine($root,$relative)) ([IO.File]::ReadAllText([IO.Path]::Combine($repository,$relative)))
        }
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'test/scripts/ScriptAnalyzer.baseline.json')) '{"SchemaVersion":1,"Analyzer":"PSScriptAnalyzer 1.25.0","Entries":[]}'
        foreach($file in $Files.GetEnumerator()){$null=New-QuietTestFile ([IO.Path]::Combine($root,$file.Key)) $file.Value}
        $root
    }
    $clean="#requires -Version 7.6`n[CmdletBinding()]param()`n[IO.Path]::Combine('a','b')`n"
    $run={param([string]$Workspace,[string[]]$Arguments=@())
        Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$Workspace,'-CacheDirectory',[IO.Path]::Combine($Workspace,'.analysis-cache'),'-Offline')+$Arguments) -TimeoutSeconds 300
    }
    $baselinePath={param([string]$Workspace)[IO.Path]::Combine($Workspace,'test/scripts/ScriptAnalyzer.baseline.json')}
}

Describe 'Test-ScriptAnalysis.ps1' {
    BeforeEach {
        if(!$available){Set-ItResult -Skipped -Because 'the pinned PSScriptAnalyzer is not cached (run Initialize-TestTools.ps1)'}
    }

    It 'passes a clean workspace and reuses its cache on the next run' {
        $workspace=& $newWorkspace @{'scripts/Clean.ps1'=$clean}
        $first=& $run $workspace
        $first.ExitCode|Should -Be 0 -Because ($first.Output+$first.Error)
        $first.Output|Should -Match 'to analyze=2'
        $second=& $run $workspace
        $second.ExitCode|Should -Be 0 -Because ($second.Output+$second.Error)
        $second.Output|Should -Match 'cached=2 to analyze=0'
    }

    It 'fails on a new violation of a repository rule and names it' {
        $workspace=& $newWorkspace @{'scripts/lib/Bad.psm1'="function Get-Thing { Join-Path 'a' 'b' }`nExport-ModuleMember -Function Get-Thing`n"}
        $outcome=& $run $workspace
        $outcome.ExitCode|Should -Be 1
        $outcome.Output|Should -Match 'New finding: scripts/lib/Bad\.psm1:1 QuietJoinPath'
        ($outcome.Output+$outcome.Error)|Should -Match 'ScriptAnalysisNewViolations: 1'
    }

    It 'fails on a stale baseline entry and prunes it with -UpdateBaseline, without accepting new findings' {
        $workspace=& $newWorkspace @{'scripts/Clean.ps1'=$clean}
        $stale='{"SchemaVersion":1,"Analyzer":"PSScriptAnalyzer 1.25.0","Entries":[{"Rule":"QuietJoinPath","Path":"scripts/Gone.ps1","Function":"","ExtentSHA256":"'+('A'*64)+'","Count":1}]}'
        [IO.File]::WriteAllText((& $baselinePath $workspace),$stale)
        $outcome=& $run $workspace
        $outcome.ExitCode|Should -Be 1
        ($outcome.Output+$outcome.Error)|Should -Match 'ScriptAnalysisBaselineStale: 1'
        $pruned=& $run $workspace @('-UpdateBaseline')
        $pruned.ExitCode|Should -Be 0 -Because ($pruned.Output+$pruned.Error)
        @((Get-Content -LiteralPath (& $baselinePath $workspace) -Raw|ConvertFrom-Json).Entries).Count|Should -Be 0
        $null=New-QuietTestFile ([IO.Path]::Combine($workspace,'scripts/Entry.ps1')) "function Helper { 1 }`n"
        $grown=& $run $workspace @('-UpdateBaseline')
        $grown.ExitCode|Should -Be 1
        $grown.Output|Should -Match 'QuietEntryPointFunction'
        @((Get-Content -LiteralPath (& $baselinePath $workspace) -Raw|ConvertFrom-Json).Entries).Count|Should -Be 0
    }

    It 'applies the test-only exclusions to Pester containers only' {
        $body="BeforeAll { `$unused=1 }`nDescribe 'd' { It 'i' { 1 } }`n"
        $workspace=& $newWorkspace @{'test/scripts/unit/A.Tests.ps1'=$body;'scripts/lib/Lib.psm1'="function Get-Value { `$unused=1 }`nExport-ModuleMember -Function Get-Value`n"}
        $outcome=& $run $workspace
        $outcome.ExitCode|Should -Be 1
        $outcome.Output|Should -Match 'New finding: scripts/lib/Lib\.psm1:1 PSUseDeclaredVarsMoreThanAssignments'
        $outcome.Output|Should -Not -Match 'A\.Tests\.ps1'
    }

    It 'rejects an invalid baseline before analyzing' {
        $workspace=& $newWorkspace @{'scripts/Clean.ps1'=$clean}
        [IO.File]::WriteAllText((& $baselinePath $workspace),'{"SchemaVersion":7}')
        $outcome=& $run $workspace
        $outcome.ExitCode|Should -Be 1
        ($outcome.Output+$outcome.Error)|Should -Match 'ScriptAnalysisBaselineInvalid: schema'
        [IO.Directory]::Exists([IO.Path]::Combine($workspace,'.analysis-cache'))|Should -BeFalse
    }

    It 'writes nothing with -WhatIf' {
        $workspace=& $newWorkspace @{'scripts/Clean.ps1'=$clean}
        $outcome=& $run $workspace @('-WhatIf')
        $outcome.ExitCode|Should -Be 0
        [IO.Directory]::Exists([IO.Path]::Combine($workspace,'.analysis-cache'))|Should -BeFalse
    }
}
