#requires -Version 7.6
function Get-QuietCiImpact {
    <#
    .SYNOPSIS
    Selects product qualification from changed paths and transitive declared companion dependencies.
    .PARAMETER WorkspaceRoot
    Checkout owning the inert suite catalogue.
    .PARAMETER ChangedPaths
    Complete old/new path set; callers must disable rename collapsing.
    #>
    [CmdletBinding()]
    param([string]$WorkspaceRoot,[AllowEmptyCollection()][string[]]$ChangedPaths)
    Import-Module (Join-Path $PSScriptRoot 'CiCompanions.psm1') -ErrorAction Stop
    $configuration=Read-QuietCiCompanions $WorkspaceRoot
    $selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $full=$false;$tooling=$false
    foreach($path in $ChangedPaths){
        if(!$path -or $path.Contains([char]0) -or $path.StartsWith('/') -or $path.Split('/') -contains '..'){throw 'CiImpactPathInvalid'}
        if($path -match '\A(?:docs/|README[^/]*\.md\z|CREDITS\.md\z|icons/)'){continue}
        if($path.StartsWith('FrenchExDev2.QuietCli.Tooling.Tests.PoSh/',[StringComparison]::Ordinal)){$tooling=$true;continue}
        $matched=$false
        foreach($name in $configuration.Companions.Keys){
            $product='FrenchExDev2.QuietCli.'+$name+'.PoSh/'
            $tests=if($configuration.Suites.Contains($name)){$configuration.Suites[$name].TestsModule+'/'}else{$null}
            if(!$path.StartsWith($product,[StringComparison]::Ordinal) -and (!$tests -or !$path.StartsWith($tests,[StringComparison]::Ordinal))){continue}
            $matched=$true
            foreach($suite in $configuration.Suites.Keys){
                $closure=Resolve-QuietCiCompanions $configuration -Suite $suite
                if($name -cin $closure.Dependencies){[void]$selected.Add($suite)}
            }
            # Core.Tests also owns shared assertions and automation helpers used by the tooling campaign.
            if($name -ceq 'Core'){$full=$true;$tooling=$true}
        }
        if(!$matched){$full=$true;$tooling=$true}
    }
    $names=@($configuration.Suites.Keys|Where-Object {$selected.Contains($_)})
    # Multiple independent scopes conservatively share one All matrix, never one matrix per companion.
    $suite=if($full -or $names.Count -gt 1){'All'}elseif($names.Count){$names[0]}else{'All'}
    [pscustomobject]@{Suite=$suite;RunProducts=($full -or $names.Count -gt 0);RunTooling=$tooling;ChangedPaths=@($ChangedPaths);SelectedSuites=$(if($full -or $names.Count -gt 1){@($configuration.Suites.Keys)}else{$names});ConservativeFull=$full}
}
function Test-QuietDevelopReceipt {
    <#
    .SYNOPSIS
    Accepts successful PR evidence only for the exact merged source tree and originating workflow attempt.
    .PARAMETER Receipt
    Parsed bounded artifact document.
    .PARAMETER Tree
    Actual merged commit tree.
    .PARAMETER RunId
    Authoritative successful PR workflow run.
    .PARAMETER RunAttempt
    Authoritative workflow attempt.
    #>
    param($Receipt,[string]$Tree,[string]$RunId,[string]$RunAttempt)
    if($Tree -cnotmatch '\A[a-f0-9]{40}\z' -or $Receipt.Tree -cne $Tree -or
        $Receipt.Ready -isnot [bool] -or !$Receipt.Ready -or [string]$Receipt.RunId -cne $RunId -or [string]$Receipt.RunAttempt -cne $RunAttempt -or
        $Receipt.Windows -cne 'success' -or $Receipt.Linux -cne 'success' -or
        $Receipt.PerformanceRequired -isnot [bool] -or $Receipt.Performance -cne $(if($Receipt.PerformanceRequired){'success'}else{'skipped'}) -or
        $Receipt.ToolingRequired -isnot [bool] -or $Receipt.Tooling -cne $(if($Receipt.ToolingRequired){'success'}else{'skipped'}) -or
        $Receipt.ToolingMutation -cne $(if($Receipt.ToolingRequired){'success'}else{'skipped'}) -or
        $Receipt.MutationRequired -isnot [bool] -or $Receipt.Mutation -cne $(if($Receipt.MutationRequired){'success'}else{'skipped'})){return $false}
    return $true
}
Export-ModuleMember -Function Get-QuietCiImpact,Test-QuietDevelopReceipt
