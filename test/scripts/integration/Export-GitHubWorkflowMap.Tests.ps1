#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null = Import-QuietTestLibrary -Name WorkflowDocumentation
    $null = Import-QuietTestLibrary -Name GitHubWorkflowMap
    $scriptPath = [IO.Path]::Combine((Get-QuietTestScriptsRoot),'Export-GitHubWorkflowMap.ps1')
    $root = [IO.Path]::Combine($TestDrive,'checkout')
    $null = New-QuietTestFile ([IO.Path]::Combine($root,'.github/workflows/entry.yml')) @'
name: Entrée
on:
  push: {branches: [develop]}
  pull_request:
jobs:
  prepare:
    runs-on: ubuntu-latest
    steps:
      - name: Préparer | vérifier
        run: ./scripts/Run-Thing.ps1
      - uses: ./.github/actions/setup
      - uses: actions/checkout@v4
  verify:
    needs: prepare
    if: ${{ always() }}
    uses: ./.github/workflows/verify.yaml
'@
    $null = New-QuietTestFile ([IO.Path]::Combine($root,'.github/workflows/verify.yaml')) @'
on: workflow_call
jobs:
  first:
    runs-on: ubuntu-latest
  second:
    runs-on: ubuntu-latest
    needs: [first]
    strategy:
      matrix: {os: [linux, windows]}
'@
    $null = New-QuietTestFile ([IO.Path]::Combine($root,'.github/actions/setup/action.yml')) @'
name: Setup
runs:
  using: composite
  steps:
    - name: Commencer
      run: ./scripts/Run-Thing.ps1
      shell: pwsh
    - uses: actions/checkout@v4
'@
    $null = New-QuietTestFile ([IO.Path]::Combine($root,'docs/scripts/Run-Thing.md')) '# Run thing'
    $null = New-QuietTestFile ([IO.Path]::Combine($root,'docs/ci/github/script-entry.md')) '# Entry'
}

Describe 'Export-GitHubWorkflowMap.ps1' {
    It 'uses the pinned repository YAML parser' {
        (Get-QuietWorkflowYamlParser).GetType().FullName | Should -BeExactly 'YamlDotNet.Serialization.Deserializer'
    }

    It 'generates declared trigger, job and action diagrams with working navigation' {
        $path = [IO.Path]::Combine($root,'docs/maps/CI map.md')
        $run = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-WorkspaceRoot',$root,'-OutputPath',$path)
        $run.ExitCode | Should -Be 0 -Because $run.Error
        $report = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
        (New-QuietGitHubWorkflowMap -WorkspaceRoot $root -OutputPath $path).Markdown | Should -BeExactly $report
        $report | Should -Match 'flowchart LR[\s\S]*?\["push"\][\s\S]*?e0 --> n1[\s\S]*?n1 -\.-> n2'
        $report | Should -Match 'flowchart TD[\s\S]*?j0 --> j1[\s\S]*?j1 -\.-> cj1\["\./\.github/workflows/verify\.yaml"\]'
        $report | Should -Match 'j0 -\.-> n0'
        $report | Should -Match 'sequenceDiagram[\s\S]*?A->>A: Commencer[\s\S]*?A->>A: actions/checkout@v4'
        $report | Should -Match '\[scripts/Run-Thing\.ps1\]\(\.\./scripts/Run-Thing\.md\)'
        $report | Should -Match '\[Documentation du workflow\]\(\.\./ci/github/script-entry\.md\)'
        $report | Should -Match '\[YAML source\]\(\.\./\.\./\.github/workflows/entry\.yml\)'
        $report | Should -Match 'Préparer &#124; vérifier'
        $report | Should -Match 'Matrice déclarée.*windows'
        $report | Should -Match '"branches".*"develop"'
        $report | Should -Not -Match "`r|(?m)^    e\d+\(\[.workflow_call"
        foreach ($link in [regex]::Matches($report,'\]\(#([^\)]+)\)')) {
            $report.Contains('<a name="'+$link.Groups[1].Value+'"></a>') | Should -BeTrue
        }
    }

    It 'previews an absent report and preserves an existing report on input failure' {
        $path = [IO.Path]::Combine($TestDrive,'preview','map.md')
        $missingRoot = [IO.Path]::Combine($TestDrive,'missing')
        $preview = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-WorkspaceRoot',$missingRoot,'-OutputPath',$path,'-WhatIf')
        $preview.ExitCode | Should -Be 0 -Because $preview.Error
        [IO.Directory]::Exists([IO.Path]::GetDirectoryName($path)) | Should -BeFalse
        $null = New-QuietTestFile $path 'Existing report'
        $failed = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-WorkspaceRoot',$missingRoot,'-OutputPath',$path)
        $failed.ExitCode | Should -Not -Be 0
        $failed.Error | Should -Match 'WorkflowMapNoWorkflows'
        [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) | Should -BeExactly 'Existing report'
    }
}
