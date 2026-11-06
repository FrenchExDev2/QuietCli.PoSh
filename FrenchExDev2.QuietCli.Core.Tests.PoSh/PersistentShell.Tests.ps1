function Test-QuietPersistentContracts {
    <# .SYNOPSIS
    Exercises generated session/result properties, malformed states and source-checked mutants.
    #>
    $verify={
        $random=[Random]::new(73606);$oracle=Get-QuietPersistentOracle
        foreach($iteration in 1..32){
            $index=$random.Next(1,101);$processId=$random.Next(1,100000);$token=[guid]::NewGuid().ToString('N')
            $frame=@{Kind='Sample';Index=$index;Token=$token;ProcessId=$processId;SameReference=$true;NativeExecutions=$index;CommandMs=$random.NextDouble()*1000;DeliveryBytes=500;WorkingSetBytes=10000;PrivateBytes=20000;Bytes=$oracle.Bytes;Records=2;SHA256=$oracle.SHA256}
            Assert-QuietPersistentFrame $frame $index $token $processId Execute
            $frame.NativeExecutions=1;Assert-QuietPersistentFrame $frame $index $token $processId Retain
            foreach($damage in @(
                {param($f)$f.Kind='Other'}, {param($f)$f.Index++}, {param($f)$f.Token='foreign'},
                {param($f)$f.ProcessId++}, {param($f)$f.SameReference=$false}, {param($f)$f.NativeExecutions=0},
                {param($f)$f.CommandMs=-1}, {param($f)$f.CommandMs=[double]::NaN},
                {param($f)$f.DeliveryBytes=$null}, {param($f)$f.PrivateBytes=[double]::PositiveInfinity},
                {param($f)$f.Bytes++}, {param($f)$f.Records++}, {param($f)$f.SHA256='bad'},
                {param($f)$f.Remove('Token')}, {param($f)$f.Remove('WorkingSetBytes')}
            )){
                $candidate=$frame.Clone();$null=& $damage $candidate
                $rejected=$false;try{Assert-QuietPersistentFrame $candidate $index $token $processId Retain}catch{$rejected=$true}
                if(!$rejected){throw 'PersistentDamagedFrameAccepted: seed 73606'}
            }
            $good=@{Outcome='Success';Error=@();Execution=@{Native=@{ExitCode=0;StdoutBytesRead=$oracle.Bytes;StderrBytesRead=0}};Completeness=@{Source=$true;Analysis=$true};Data=@{Bytes=$oracle.Bytes;Records=2;SHA256=$oracle.SHA256;CompleteCalls=1}}
            Assert-QuietPersistentResult $good $oracle
            foreach($damage in @(
                {param($r)$r.Outcome='Failed'}, {param($r)$r.Execution.Native.ExitCode=1},
                {param($r)$r.Error=@('failure')}, {param($r)$r.Completeness.Source=$false},
                {param($r)$r.Completeness.Analysis=$false}, {param($r)$r.Data.Bytes++},
                {param($r)$r.Data.Records++}, {param($r)$r.Data.SHA256='bad'},
                {param($r)$r.Data.CompleteCalls=2}, {param($r)$r.Execution.Native.StdoutBytesRead++},
                {param($r)$r.Execution.Native.StderrBytesRead=1}, {param($r)$r.Remove('Data')}
            )){
                $candidate=$good|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
                $null=& $damage $candidate
                $rejected=$false;try{Assert-QuietPersistentResult $candidate $oracle}catch{$rejected=$true}
                if(!$rejected){throw 'PersistentDamagedResultAccepted: seed 73606'}
            }
        }
    }
    & $verify
    $mutations=@(
        @('Assert-QuietPersistentFrame','$Frame.Token -cne $Token','$false'),
        @('Assert-QuietPersistentFrame','!$Frame.SameReference','$false'),
        @('Assert-QuietPersistentFrame','$Frame.NativeExecutions -ne $expected','$false'),
        @('Assert-QuietPersistentFrame','[double]$Frame.$field -lt 0','$false'),
        @('Assert-QuietPersistentResult','!$Result.Completeness.Source','$false'),
        @('Assert-QuietPersistentResult','$Result.Data.SHA256 -cne $Oracle.SHA256','$false')
    )
    $outcomes=@(foreach($mutation in $mutations){
        $definition=(Get-Command $mutation[0]).Definition
        if(!$definition.Contains($mutation[1])){throw 'PersistentMutantInvalid'}
        $detected=& {
            param($name,$body,$verify)
            . ([scriptblock]::Create('function '+$name+' {'+$body+'}'))
            try{& $verify;$false}catch{$true}
        } $mutation[0] $definition.Replace($mutation[1],$mutation[2]) $verify
        if(!$detected){throw 'PersistentMutantSurvived'}
        @{Function=$mutation[0];Original=$mutation[1];Replacement=$mutation[2];State='Killed'}
    })
    [pscustomobject]@{Seed=73606;PropertyCases=96;MalformedCases=864;MutantsKilled=$outcomes.Count;MutantsTotal=$mutations.Count;Mutations=$outcomes}
}
