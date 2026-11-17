#requires -Version 7.6
function Get-QuietToolingResults {
    <#
    .SYNOPSIS
    Separates authoritative functional, mutation and completeness job results without accepting missing evidence.
    .DESCRIPTION
    Functional aggregates core-independence, tooling and script-tests; mutation aggregates run-profiles-mutation and
    script-mutation; completion aggregates mutation-complete and script-mutation-complete. Each aggregate is the worst
    member result (failure, then cancelled, then skipped, then success); a missing or malformed member is a failure.
    .PARAMETER NeedsJson
    Bounded GitHub needs object for the tooling prerequisites.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$NeedsJson)
    if($NeedsJson.Length -gt 65536){throw 'ToolingNeedsTooLarge'}
    $needs=ConvertFrom-Json -InputObject $NeedsJson -AsHashtable -Depth 16 -ErrorAction Stop
    if($needs -isnot [Collections.IDictionary]){throw 'ToolingNeedsInvalid'}
    $results=@{}
    foreach($name in @('core-independence','tooling','script-tests','run-profiles-mutation','script-mutation','mutation-complete','script-mutation-complete')){
        $entry=$needs[$name]
        $value=if($entry -is [Collections.IDictionary]){$entry['result']}else{$null}
        $results[$name]=if($value -is [string] -and $value -cin @('success','failure','cancelled','skipped')){$value}else{'failure'}
    }
    $worst={param([string[]]$Members)
        $aggregate='success'
        foreach($state in @('skipped','cancelled','failure')){foreach($member in $Members){if($results[$member] -ceq $state){$aggregate=$state}}}
        $aggregate
    }
    [pscustomobject]@{
        FunctionalResult=(& $worst @('core-independence','tooling','script-tests'))
        MutationResult=(& $worst @('run-profiles-mutation','script-mutation'))
        CompletionResult=(& $worst @('mutation-complete','script-mutation-complete'))
    }
}
Export-ModuleMember -Function Get-QuietToolingResults
