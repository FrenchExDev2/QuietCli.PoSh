#requires -Version 7.6
# Contracts between the workflows that run ScriptAnalyzer and the caches its pinned tools and findings live in.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-QuietTestLibrary -Name CiCompanions
    $root=Get-QuietTestWorkspaceRoot
    # Reading the catalogue loads the pinned YAML parser shipped with Core.
    $null=Read-QuietCiCompanions -WorkspaceRoot $root
    $read={param([string[]]$Segments)[YamlDotNet.Serialization.DeserializerBuilder]::new().Build().Deserialize([IO.File]::ReadAllText([IO.Path]::Combine([string[]](@($root)+$Segments)),[Text.Encoding]::UTF8))}
    $action=& $read @('.github','actions','cache-test-tools','action.yml')
    $workflow=& $read @('.github','workflows','scripts-docs-check.yml')
    $check=$workflow['jobs']['check']
    $diagrams=$workflow['jobs']['diagrams']
    $indexOf={param($Job,$Step)[Array]::IndexOf(@($Job['steps']),$Step)}
    $checks=@($check['steps']|Where-Object {([string]$_['run']).Contains('./scripts/Invoke-WorkspaceChecks.ps1')})
}

Describe 'scripts-docs-check.yml workflow diagrams' {
    It 'runs the diagrams job for script and test changes and uploads the canonical map before checking freshness' {
        foreach ($eventName in @('pull_request','push')) {
            $workflow['on'][$eventName]['paths'] | Should -Contain 'scripts/**'
            $workflow['on'][$eventName]['paths'] | Should -Contain 'test/scripts/**'
            $workflow['on'][$eventName]['paths'] | Should -Contain '.github/workflows/**'
            $workflow['on'][$eventName]['paths'] | Should -Contain 'docs/README-github-workflows-diagrams.md'
        }
        @($workflow['on']['push']['branches']) | Should -Be @('develop')
        [string]$workflow['permissions']['contents'] | Should -BeExactly 'read'
        $steps = @($diagrams['steps'])
        $generate = $steps | Where-Object { $_['id'] -ceq 'generate' }
        $upload = $steps | Where-Object { $_['uses'] -like 'actions/upload-artifact@*' }
        $freshness = $steps | Where-Object { $_['if'] -ceq "steps.generate.outputs.matches != 'true'" }
        [string]$upload['with']['name'] | Should -BeExactly 'github-workflows-diagrams'
        [string]$upload['with']['path'] | Should -BeExactly 'docs/README-github-workflows-diagrams.md'
        [string]$upload['with']['if-no-files-found'] | Should -BeExactly 'error'
        (& $indexOf $diagrams $generate) | Should -BeLessThan (& $indexOf $diagrams $upload)
        (& $indexOf $diagrams $upload) | Should -BeLessThan (& $indexOf $diagrams $freshness)
    }

    It 'executes the real generation step on missing, matching and stale fixtures' {
        $fixture = [IO.Path]::Combine($TestDrive,'workflow-map-checkout')
        $null = New-QuietTestFile ([IO.Path]::Combine($fixture,'.github/workflows/fixture.yml')) @'
on: workflow_dispatch
jobs:
  demo:
    runs-on: ubuntu-latest
'@
        $null = New-QuietTestFile ([IO.Path]::Combine($fixture,'CREDITS.md')) '# Credits'
        $null = New-QuietTestFile ([IO.Path]::Combine($fixture,'scripts/Export-GitHubWorkflowMap.ps1')) @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$OutputPath)
& $env:QUIETCLI_TEST_WORKFLOW_MAP_EXPORTER -WorkspaceRoot (Get-Location).Path -OutputPath $OutputPath -Confirm:$false
'@
        $generate = $diagrams['steps'] | Where-Object { $_['id'] -ceq 'generate' }
        $prologue = '$ErrorActionPreference = ''Stop''', 'Set-Location -LiteralPath $env:QUIETCLI_TEST_MAP_CHECKOUT'
        $step = New-QuietTestFile ([IO.Path]::Combine($TestDrive,'Generate-WorkflowMapFixture.ps1')) (($prologue + $generate['run']) -join "`n")
        $mapPath = [IO.Path]::Combine($fixture,'docs/README-github-workflows-diagrams.md')
        foreach ($scenario in @('missing','matching','stale')) {
            if ($scenario -ceq 'stale') { $null = New-QuietTestFile $mapPath '# Stale' }
            $output = [IO.Path]::Combine($TestDrive,"$scenario-output")
            $result = Invoke-QuietTestScript -ScriptPath $step -Environment @{
                GITHUB_OUTPUT = $output
                QUIETCLI_TEST_MAP_CHECKOUT = $fixture
                QUIETCLI_TEST_WORKFLOW_MAP_EXPORTER = [IO.Path]::Combine((Get-QuietTestScriptsRoot),'Export-GitHubWorkflowMap.ps1')
            }
            $result.ExitCode | Should -Be 0 -Because $result.Error
            $expected = ($scenario -ceq 'matching').ToString().ToLowerInvariant()
            [IO.File]::ReadAllText($output,[Text.Encoding]::UTF8) | Should -BeExactly "matches=$expected`n"
            [IO.File]::ReadAllText($mapPath,[Text.Encoding]::UTF8) | Should -Match '\[CREDITS\.md\]\(\.\./CREDITS\.md\)'
        }
    }
}

Describe 'cache-test-tools action' {
    It 'caches only the pinned archives under a key that changes with the pinned versions' {
        [string]$action['runs']['using']|Should -BeExactly 'composite'
        $steps=@($action['runs']['steps'])
        $steps.Count|Should -Be 1
        [string]$steps[0]['uses']|Should -Match '^actions/cache@[0-9a-f]{40}$'
        [string]$steps[0]['with']['path']|Should -BeExactly '.cache/test-tools/*/*.nupkg' -Because 'extracted modules are rebuilt from bytes whose SHA-256 is verified on every run'
        [string]$steps[0]['with']['key']|Should -BeExactly '${{ runner.os }}-quietcli-test-tools-${{ hashFiles(''scripts/lib/RunToolCache.psm1'') }}'
        $steps[0]['with'].ContainsKey('restore-keys')|Should -BeFalse -Because 'an older version set would only miss the pinned archives'
    }

    It 'matches the archive layout of the pinned tool cache' {
        Import-QuietTestLibrary -Name RunToolCache
        $packages=@(Get-RunTestToolPackages)
        $packages.Count|Should -BeGreaterThan 0
        foreach($package in $packages){
            # A forged archive at the cached glob is read and rejected: the glob names the file the initializer reuses.
            $cache=[IO.Path]::Combine($TestDrive,'tools-'+$package.Name)
            $archive=[IO.Path]::Combine($cache,$package.Name,$package.Name+'.'+$package.Version+'.nupkg')
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($archive))
            [IO.File]::WriteAllBytes($archive,[byte[]](1,2,3))
            [Management.Automation.WildcardPattern]::new('*/*.nupkg').IsMatch([IO.Path]::GetRelativePath($cache,$archive).Replace('\','/'))|Should -BeTrue
            {Initialize-RunToolCache -OutputDirectory $cache -Packages @($package) -Offline}|Should -Throw -ExpectedMessage 'ProfilerCacheDigestMismatch'
        }
    }
}

Describe 'scripts-docs-check.yml ScriptAnalyzer caches' {
    It 'runs the workspace checks once, after both caches are restored' {
        $checks.Count|Should -Be 1
        $tools=@($check['steps']|Where-Object {[string]$_['uses'] -ceq './.github/actions/cache-test-tools'})
        $tools.Count|Should -Be 1
        (& $indexOf $check $tools[0])|Should -BeLessThan (& $indexOf $check $checks[0])
    }

    It 'restores the newest findings cache and stores a new one per run attempt' {
        $analysis=@($check['steps']|Where-Object {([string]$_['uses']).StartsWith('actions/cache@',[StringComparison]::Ordinal) -and [string]$_['with']['path'] -ceq '.cache/script-analysis/*.json'})
        $analysis.Count|Should -Be 1 -Because 'only the per-file documents are cached, never the runs/ scratch directory'
        [string]$analysis[0]['with']['key']|Should -BeExactly '${{ runner.os }}-quietcli-script-analysis-${{ github.run_id }}-${{ github.run_attempt }}'
        ([string]$analysis[0]['with']['restore-keys']).Trim()|Should -BeExactly '${{ runner.os }}-quietcli-script-analysis-' -Because 'documents are keyed by file and analyzer configuration content'
        (& $indexOf $check $analysis[0])|Should -BeLessThan (& $indexOf $check $checks[0])
    }
}
