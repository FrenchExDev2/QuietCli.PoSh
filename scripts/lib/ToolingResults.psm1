#requires -Version 7.6
function Get-QuietToolingResults {
    <#
    .SYNOPSIS
    Separates authoritative functional, mutation and completeness job results without accepting missing evidence.
    .PARAMETER NeedsJson
    Bounded GitHub needs object for the four tooling prerequisites.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$NeedsJson)
    if($NeedsJson.Length -gt 65536){throw 'ToolingNeedsTooLarge'}
    $needs=ConvertFrom-Json -InputObject $NeedsJson -AsHashtable -Depth 16 -ErrorAction Stop
    if($needs -isnot [Collections.IDictionary]){throw 'ToolingNeedsInvalid'}
    $results=@{}
    foreach($name in @('core-independence','tooling','run-profiles-mutation','mutation-complete')){
        $entry=$needs[$name]
        $value=if($entry -is [Collections.IDictionary]){$entry['result']}else{$null}
        $results[$name]=if($value -is [string] -and $value -cin @('success','failure','cancelled','skipped')){$value}else{'failure'}
    }
    $functional='success'
    foreach($state in @('skipped','cancelled','failure')){
        if($results['core-independence'] -ceq $state -or $results['tooling'] -ceq $state){$functional=$state}
    }
    [pscustomobject]@{
        FunctionalResult=$functional
        MutationResult=$results['run-profiles-mutation']
        CompletionResult=$results['mutation-complete']
    }
}
Export-ModuleMember -Function Get-QuietToolingResults
