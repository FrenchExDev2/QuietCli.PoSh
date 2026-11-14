function Invoke-RunProfileQualification {
    <#
    .SYNOPSIS
    Runs the complete tooling suite or mutation catalogue through the independent CI process helper.
    .PARAMETER WorkspaceRoot
    Selected QuietCli2 checkout.
    .PARAMETER RunDirectory
    This run's private report directory.
    .PARAMETER Mutation
    Runs every registered mutation, requiring a green baseline and no invalid outcomes.
    .PARAMETER OnProgress
    Receives observable case or mutant progress and independent counters.
    .PARAMETER MaxConcurrency
    Maximum isolated mutation workers; measurements in the functional campaign remain ordered.
    #>
    param([string]$WorkspaceRoot, [string]$RunDirectory, [switch]$Mutation, [scriptblock]$OnProgress,[ValidateRange(1,32)][int]$MaxConcurrency=2)
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Ci.Process.psm1') -DisableNameChecking -ErrorAction Stop
    $tests = Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh'
    $report = Join-Path $RunDirectory 'run-profiles-mutation.json'
    $scriptName = if ($Mutation) { 'RunProfiles.Mutation.ps1' } else { 'RunProfiles.Tests.ps1' }
    $arguments = @('-File', (Join-Path $tests $scriptName))
    if ($Mutation) { $arguments += @('-OutputPath', $report,'-MaxConcurrency',"$MaxConcurrency") }
    if($Mutation -and ($env:QUIETCLI_MUTATION_SHARD_INDEX -or $env:QUIETCLI_MUTATION_SHARD_COUNT)){
        $index=0;$count=0
        if(![int]::TryParse($env:QUIETCLI_MUTATION_SHARD_INDEX,[ref]$index) -or ![int]::TryParse($env:QUIETCLI_MUTATION_SHARD_COUNT,[ref]$count) -or $count -lt 1 -or $count -gt 32 -or $index -lt 0 -or $index -ge $count){throw 'MutationShardEnvironmentInvalid'}
        $arguments+=@('-ShardIndex',"$index",'-ShardCount',"$count")
    }
    $capture = @{ Passed = 0; Failed = 0; Skipped = 0; Summary = $false; Lines = 0; Diagnostics = [Collections.Generic.Queue[string]]::new() }
    $process = Invoke-CiProcess -FilePath (Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })) -ArgumentList $arguments -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 5400 -State $capture -OnOutput {
        param($record, $capture)
        $capture.Lines++
        if ($capture.Diagnostics.Count -ge 8) { $null = $capture.Diagnostics.Dequeue() }
        $capture.Diagnostics.Enqueue($record.Text)
        if ($record.Text -match '^SUMMARY Passed=(\d+) Failed=(\d+) Skipped=(\d+)$') {
            $capture.Passed = [int]$Matches[1]; $capture.Failed = [int]$Matches[2]; $capture.Skipped = [int]$Matches[3]; $capture.Summary = $true
        }
        elseif ($record.Text -match '^.+\s+(passed|FAILED:.*)$') { if ($Matches[1] -ceq 'passed') { $capture.Passed++ } else { $capture.Failed++ } }
        elseif ($record.Text -match '\[\d+/\d+\]\s+\S+\s+(Killed|Survived|Crashed|Timeout|Invalid)\s') { if ($Matches[1] -ceq 'Killed') { $capture.Passed++ } else { $capture.Failed++ } }
        if ($OnProgress) { $null = & $OnProgress $record.Text $capture.Passed $capture.Failed }
        [Console]::Out.WriteLine($record.Text)
    }
    $data=$null
    if ($Mutation -and [IO.File]::Exists($report)) {
        $data = Get-Content -LiteralPath $report -Raw -Encoding utf8 | ConvertFrom-Json
        $capture.Passed = @($data.Results | Where-Object Outcome -CEQ Killed).Count
        $capture.Failed = @($data.Results | Where-Object Outcome -CNE Killed).Count
        $capture.Summary = $data.Results.Count -gt 0
    }
    if (-not $capture.Summary -or $process.Outcome -ne 'Success' -or (-not $Mutation -and $capture.Skipped -gt 0)) { $capture.Failed = [Math]::Max(1, $capture.Failed) }
    $partial=$Mutation -and $null -ne $data -and $data.Partial
    $summary = [pscustomobject]@{ Project = 'RunProfiles'; Mutation = [bool]$Mutation; Partial=[bool]$partial; Incomplete=$false; Passed = $capture.Passed; Failed = $capture.Failed; Skipped = $capture.Skipped; Process = $process; Diagnostics = $capture.Diagnostics.ToArray() }
    if (-not $Mutation) { Write-WorkspaceJson (Join-Path $RunDirectory 'run-profiles-suite.json') $summary }
    return $summary
}
