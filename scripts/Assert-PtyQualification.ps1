# Objective: Reject any missing or incomplete mandatory native validation phase.
function Assert-PtyQualification {
    <#
    .SYNOPSIS
    Requires unit/process properties, complete decoder fuzzing and every valid mutation to pass.
    .PARAMETER Summary
    Native worker summary read from its own report file.
    #>
    param([Parameter(Mandatory)]$Summary)
    if($Summary.State.State -cne 'Success' -or
        $Summary.Baseline.State -cne 'Success' -or $Summary.Baseline.Assertions -lt 43 -or $Summary.Baseline.PropertyGroups -lt 6 -or $Summary.Baseline.Failed -ne 0 -or
        $Summary.Fuzz.State -cne 'Success' -or $Summary.Fuzz.RequestedRuns -lt 20000 -or $Summary.Fuzz.ExecutedRuns -lt $Summary.Fuzz.RequestedRuns -or
        $Summary.Mutation.Selected -lt 31 -or $Summary.Mutation.Killed -ne $Summary.Mutation.Selected -or
        $Summary.Mutation.Survived -ne 0 -or $Summary.Mutation.Invalid -ne 0 -or $Summary.Mutation.Timeout -ne 0 -or $Summary.Mutation.Error -ne 0){
        throw 'NativeQualificationIncomplete: unit/process properties, fuzzing and mutation must all pass.'
    }
}
