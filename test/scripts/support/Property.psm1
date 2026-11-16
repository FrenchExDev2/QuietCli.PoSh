#Objective: Minimal seeded property runner with replayable counterexamples and greedy shrinking.
#requires -Version 7.6

function Invoke-QuietProperty {
    <#
    .SYNOPSIS
    Checks a property over Count generated cases; on failure shrinks and throws a replayable counterexample.
    .DESCRIPTION
    Case i uses its own System.Random seeded from the run seed, so a failure is replayed with the same
    -Seed. The property fails when it throws or returns $false. Shrink returns smaller candidate cases;
    the first candidate that still fails replaces the counterexample, up to MaxShrinks steps.
    .PARAMETER Name
    Property name used in the failure message.
    .PARAMETER Seed
    Run seed (Get-QuietTestSeed).
    .PARAMETER Count
    Number of generated cases.
    .PARAMETER Generator
    Scriptblock receiving a seeded [Random] and returning one case.
    .PARAMETER Property
    Scriptblock receiving one case; throws or returns $false on violation.
    .PARAMETER Shrink
    Optional scriptblock receiving one case and returning smaller candidates.
    .PARAMETER MaxShrinks
    Maximum accepted shrinking steps.
    #>
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][int]$Seed,[ValidateRange(1,100000)][int]$Count=100,[Parameter(Mandatory)][scriptblock]$Generator,[Parameter(Mandatory)][scriptblock]$Property,[scriptblock]$Shrink,[ValidateRange(0,10000)][int]$MaxShrinks=200)
    $check={param($case)
        try{$value=& $Property $case;if($value -is [bool] -and !$value){return 'property returned false'};return $null}catch{return $_.Exception.Message}
    }
    $master=[Random]::new($Seed)
    for($index=1;$index -le $Count;$index++){
        $caseSeed=$master.Next()
        $case=& $Generator ([Random]::new($caseSeed))
        $failure=& $check $case
        if($null -eq $failure){continue}
        $steps=0
        if($Shrink){
            $improved=$true
            while($improved -and $steps -lt $MaxShrinks){
                $improved=$false
                foreach($candidate in @(& $Shrink $case)){
                    $candidateFailure=& $check $candidate
                    if($null -ne $candidateFailure){$case=$candidate;$failure=$candidateFailure;$steps++;$improved=$true;break}
                }
            }
        }
        $shown=try{ConvertTo-Json -InputObject $case -Depth 6 -Compress}catch{[string]$case}
        throw ("PropertyFailed: {0} seed={1} case={2} caseSeed={3} shrinks={4} counterexample={5}: {6}" -f $Name,$Seed,$index,$caseSeed,$steps,$shown,$failure)
    }
    return $Count
}

Export-ModuleMember -Function Invoke-QuietProperty
