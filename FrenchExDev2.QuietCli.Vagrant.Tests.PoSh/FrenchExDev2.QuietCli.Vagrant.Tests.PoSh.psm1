. (Join-Path $PSScriptRoot 'VagrantLine.Tests.ps1')
. (Join-Path $PSScriptRoot 'VagrantFuzz.Tests.ps1')
. (Join-Path $PSScriptRoot 'VagrantParser.Mutation.ps1')
. (Join-Path $PSScriptRoot '../FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1')
function Invoke-QuietVagrantTests {
    <#
    .SYNOPSIS
    Runs the Vagrant --machine-readable parser/engine suite: deterministic line cases, the shared
    up/provision engine against the fixture process, and the seeded fuzz campaign.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace root.
    .PARAMETER OnProgress
    Receives name, state, passed and failed counters.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[scriptblock]$OnProgress,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot 'scripts/ReportPaths.ps1')
    if (!$RunDirectory) { $RunDirectory = Join-Path (Get-QuietReportRoot $WorkspaceRoot 'tests') ([guid]::NewGuid().ToString('N')) }
    $root = Join-Path $RunDirectory 'vagrant-fixtures'
    [void][IO.Directory]::CreateDirectory($root)
    $RootDirectory = $root
    $dotnet = (Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $fixture = Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $cases = [ordered]@{}
    $lineCases = Get-QuietVagrantLineCases -RootDirectory $root -WorkspaceRoot $WorkspaceRoot
    foreach ($entry in $lineCases.GetEnumerator()) { $cases[$entry.Key] = $entry.Value }
    $fuzzCases = Get-QuietVagrantFuzzCases -RootDirectory $root -WorkspaceRoot $WorkspaceRoot
    foreach ($entry in $fuzzCases.GetEnumerator()) { $cases[$entry.Key] = $entry.Value }
    if ($env:QUIETCLI_VAGRANT_PARSER_MUTATION -eq '1') {
        $cases['Vagrant parser PowerShell-source mutants are detected'] = {
            $mutationRoot = Join-Path $root 'mutation-run'
            [void][IO.Directory]::CreateDirectory($mutationRoot)
            $summary = Invoke-QuietVagrantParserMutation -WorkspaceRoot $WorkspaceRoot -RunDirectory $mutationRoot
            Write-WorkspaceJson (Join-Path $mutationRoot 'summary.json') $summary
            if ($summary.Failed -gt 0) {
                $offenders = ($summary.Cases | Where-Object { $_.Outcome -ne 'Killed' } | ForEach-Object { $_.Name + '=' + $_.Outcome }) -join ', '
                throw "Vagrant parser mutation campaign had survivors/infrastructure failures: $offenders"
            }
        }
    }
    $passed = 0; $failed = 0; $results = [Collections.Generic.List[object]]::new()
    foreach ($entry in $cases.GetEnumerator()) {
        if ($OnProgress) { & $OnProgress $entry.Key 'Running' $passed $failed }
        $failure = $null
        try { $null = & $entry.Value; $passed++; $state = 'Passed' } catch { $failed++; $state = 'Failed'; $failure = $_.Exception.Message }
        $results.Add([pscustomobject]@{ Name = $entry.Key; State = $state; Error = $failure })
        if ($OnProgress) { & $OnProgress $entry.Key $state $passed $failed }
    }
    [pscustomobject]@{ Project = 'FrenchExDev2.QuietCli.Vagrant.PoSh'; Passed = $passed; Failed = $failed; TtyExcluded = 0; Cases = $results.ToArray(); FixtureDirectory = $root; Seed=20261108; FragmentedTranscripts=200; MalformedInputs=800 }
}
Export-ModuleMember -Function Invoke-QuietVagrantTests
