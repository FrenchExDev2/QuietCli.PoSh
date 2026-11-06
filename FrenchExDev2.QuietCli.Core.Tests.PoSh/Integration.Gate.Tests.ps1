function Test-QuietCoreIntegrationGate {
    <#
    .SYNOPSIS
    Checks independent complete/malformed CI receipts and meaningful gate mutants.
    .PARAMETER WorkspaceRoot
    Monorepo containing the actual required-evidence gate.
    #>
    param([string]$WorkspaceRoot)
    $gate=[IO.File]::ReadAllTextAsync((Join-Path $WorkspaceRoot 'scripts/Assert-CoreIntegrationEvidence.ps1'),[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    $verify={
        param([scriptblock]$Candidate)
        $random=[Random]::new(73596)
        foreach($iteration in 1..8){
            $scenarios=@(foreach($name in @('unborn','clean','mixed','conflict','detached','linked-worktree','submodule','bulk')){
                $bytes=$random.Next(0,65536);$records=$random.Next(0,1024)
                $samples=@(foreach($mode in @('Bytes','Text')){foreach($size in @(1024,16384)){
                    @{Mode=$mode;ReadBlockBytes=$size;Outcome='Success';SourceComplete=$true;AnalysisComplete=$true;Business=@{CompleteCalls=1;SHA256=('A'*64);Bytes=$bytes;Records=$records}}
                }})
                @{Name=$name;GitModuleLoaded=$false;RegisteredHandlers=0;Samples=$samples;Human=@{Samples=@(1,2,3,4)};EngineRid='linux-x64';Oracle=@{SHA256=('A'*64);Bytes=$bytes;Records=$records}}
            })
            $good=@{Failed=0;Performance=@(
                @{Kind='FreshSessionImport';Samples=@(1..14);Iterations=7;Validation=@{MutantsKilled=4}},
                @{Kind='ImportDiagnostics';Count=10;Samples=@(@{Mode='Import'},@{Mode='Import'},@{Mode='Import'},@{Mode='CmdletOperations'},@{Mode='PreloadManagement'},@{Mode='PreloadUtility'},@{Mode='PreloadBoth'},@{Mode='Read'},@{Mode='Parse'},@{Mode='DotSource'})}
            );Integration=@(@{Kind='ControlledGitStatus';Passed=8;Failed=0;GitModuleLoaded=$false;RegisteredHandlers=0;RuntimeIdentifier='linux-x64';Scenarios=$scenarios;Validation=@{ValidCases=32;DamagedCases=448;Mutations=@(1..5|ForEach-Object {@{State='Killed'}})}})}
            $valid=$good|ConvertTo-Json -Depth 20|ConvertFrom-Json
            & $Candidate -Summary $valid
            foreach($damage in @(
                {param($r)$r.Failed=1}, {param($r)$r.Performance=@()},
                {param($r)$r.Performance[0].Samples=@(1)}, {param($r)$r.Performance[1].Count=9},
                {param($r)$r.Performance[1].Samples[9].Mode='Unknown'}, {param($r)$r.Integration=@()},
                {param($r)$r.Integration[0].GitModuleLoaded=$true}, {param($r)$r.Integration[0].Passed=9},
                {param($r)$r.Integration[0].Scenarios[0].GitModuleLoaded=$true},
                {param($r)$r.Integration[0].Scenarios[0].EngineRid='wrong'},
                {param($r)$r.Integration[0].Scenarios[0].Samples[0].SourceComplete=$false},
                {param($r)$r.Integration[0].Scenarios[0].Samples[0].AnalysisComplete=$false},
                {param($r)$r.Integration[0].Scenarios[0].Samples[0].Business.SHA256=('B'*64)},
                {param($r)$r.Integration[0].Scenarios[0].Samples[0].Business.CompleteCalls=2},
                {param($r)$r.Integration[0].Scenarios[0].Samples[0].ReadBlockBytes=2048},
                {param($r)$r.Integration[0].Validation.Mutations[0].State='Survived'}
            )){
                $damaged=$valid|ConvertTo-Json -Depth 20|ConvertFrom-Json
                & $damage $damaged
                $rejected=$false;try{& $Candidate -Summary $damaged}catch{$rejected=$true}
                if(!$rejected){throw 'CoreIntegrationDamagedReceiptAccepted: seed 73596'}
            }
        }
    }
    & $verify ([scriptblock]::Create($gate))
    $mutations=@(@('-or $evidence.GitModuleLoaded','-or $false'),@('$evidence.Passed -ne 8','$evidence.Passed -lt 8'),@('!$sample.SourceComplete','$false'),@('$sample.Business.SHA256 -cne $row.Oracle.SHA256','$false'))
    $outcomes=@(foreach($mutation in $mutations){
        if(!$gate.Contains($mutation[0])){throw 'CoreIntegrationGateMutantInvalid'}
        $mutant=[scriptblock]::Create($gate.Replace($mutation[0],$mutation[1]))
        $detected=$false;try{& $verify $mutant}catch{$detected=$true}
        if(!$detected){throw 'CoreIntegrationGateMutantSurvived'}
        @{Original=$mutation[0];Replacement=$mutation[1];State='Killed'}
    })
    [pscustomobject]@{Seed=73596;ValidCases=8;DamagedCases=128;Mutations=$outcomes}
}
