function Assert-QuietControlledStatus {
    <#
    .SYNOPSIS
    Requires complete native execution and exact independently predicted status bytes and records.
    .PARAMETER Result
    Core result envelope with callback-owned digest/counters.
    .PARAMETER Oracle
    Literal fixture expectation, not a second parse of actual output.
    #>
    param($Result,$Oracle)
    Set-StrictMode -Version Latest
    if($Result.Outcome -cne 'Success' -or $Result.Execution.Native.ExitCode -ne 0 -or $Result.Error.Count){throw 'ControlledStatusExecution'}
    if(!$Result.Completeness.Source -or !$Result.Completeness.Analysis){throw 'ControlledStatusIncomplete'}
    if($Result.Data.CompleteCalls -ne 1 -or $Result.Execution.Children -ne 0){throw 'ControlledStatusLifecycle'}
    if($Result.Data.SHA256 -cne $Oracle.SHA256){throw 'ControlledStatusDigest'}
    if($Result.Data.Bytes -ne $Oracle.Bytes -or $Result.Execution.Native.StdoutBytesRead -ne $Oracle.Bytes -or $Result.Execution.Native.StderrBytesRead -ne 0){throw 'ControlledStatusBytes'}
    if($Result.Data.Records -ne $Oracle.Records){throw 'ControlledStatusRecords'}
}

function Test-QuietControlledStatusAssertions {
    <#
    .SYNOPSIS
    Checks varied valid envelopes and damaged/missing states, then targeted assertion mutants.
    #>
    $verify={
        $random=[Random]::new(73595)
        foreach($iteration in 0..31){
            $count=$random.Next(0,10000);$bytes=$random.Next(0,1048576)
            $oracle=@{Bytes=$bytes;Records=$count;SHA256=('A'*64)}
            $good=@{Outcome='Success';Error=@();Completeness=@{Source=$true;Analysis=$true};Execution=@{Children=0;Native=@{ExitCode=0;StdoutBytesRead=$bytes;StderrBytesRead=0}};Data=@{SHA256=('A'*64);Bytes=$bytes;Records=$count;CompleteCalls=1}}
            Assert-QuietControlledStatus $good $oracle
            foreach($damage in @(
                {param($r)$r.Outcome='Failed'}, {param($r)$r.Execution.Native.ExitCode=1},
                {param($r)$r.Error=@('error')}, {param($r)$r.Completeness.Source=$false},
                {param($r)$r.Completeness.Analysis=$false}, {param($r)$r.Data.CompleteCalls=0},
                {param($r)$r.Data.CompleteCalls=2}, {param($r)$r.Execution.Children=1},
                {param($r)$r.Data.SHA256=('B'*64)}, {param($r)$r.Data.Bytes++},
                {param($r)$r.Execution.Native.StdoutBytesRead++}, {param($r)$r.Execution.Native.StderrBytesRead=1},
                {param($r)$r.Data.Records++}, {param($r)$r.Data=$null}
            )){
                $candidate=$good|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
                & $damage $candidate
                $rejected=$false;try{Assert-QuietControlledStatus $candidate $oracle}catch{$rejected=$true}
                if(!$rejected){throw 'ControlledStatusDamagedEnvelopeAccepted: seed 73595'}
            }
        }
    }
    & $verify
    $definition=(Get-Command Assert-QuietControlledStatus).Definition
    $mutations=@(
        @('$Result.Data.SHA256 -cne $Oracle.SHA256','$false'),
        @('$Result.Execution.Native.StdoutBytesRead -ne $Oracle.Bytes','$false'),
        @('!$Result.Completeness.Source','$false'),
        @('$Result.Data.CompleteCalls -ne 1','$false'),
        @('$Result.Data.Records -ne $Oracle.Records','$false')
    )
    $outcomes=@(foreach($mutation in $mutations){
        if(!$definition.Contains($mutation[0])){throw 'ControlledStatusMutantInvalid'}
        $detected=& {
            param($body,$verify)
            . ([scriptblock]::Create('function Assert-QuietControlledStatus {'+$body+'}'))
            try{& $verify;$false}catch{$true}
        } $definition.Replace($mutation[0],$mutation[1]) $verify
        if(!$detected){throw 'ControlledStatusMutantSurvived'}
        @{Original=$mutation[0];Replacement=$mutation[1];State='Killed'}
    })
    [pscustomobject]@{Seed=73595;ValidCases=32;DamagedCases=448;Mutations=$outcomes}
}
