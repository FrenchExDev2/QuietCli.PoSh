#Objective: Selects the script test files and mutation targets that a change under scripts/ or test/scripts/ can affect.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptMutation.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptMutationCache.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietScriptsTestFiles {
    <#
    .SYNOPSIS
    Lists the *.Tests.ps1 files under unit/ and integration/ of a tests root, relative to it with '/', in ordinal order.
    .PARAMETER TestsRoot
    Tests root.
    #>
    param([Parameter(Mandatory)][string]$TestsRoot)
    $TestsRoot=[IO.Path]::GetFullPath($TestsRoot)
    $files=[string[]]@(foreach($kind in 'unit','integration'){
        foreach($path in @(Get-QuietScriptMutationTreeFiles ([IO.Path]::Combine($TestsRoot,$kind)))){
            if($path.EndsWith('.Tests.ps1',[StringComparison]::Ordinal)){[IO.Path]::GetRelativePath($TestsRoot,$path).Replace([IO.Path]::DirectorySeparatorChar,[char]'/')}
        }
    })
    [Array]::Sort($files,[StringComparer]::Ordinal)
    $files
}

function Compare-QuietScriptMutationCatalogue {
    <#
    .SYNOPSIS
    Finds added or edited targets using the literal baseline and the validated current catalogue.
    .PARAMETER Previous
    The catalogue text read from the baseline commit.
    .PARAMETER CurrentPath
    Path of the current catalogue, already validated by the mutation loader.
    #>
    param([string]$Previous,[string]$CurrentPath)
    if(!$Previous){return}
    $tokens=$null
    $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Previous,[ref]$tokens,[ref]$errors)
    $statements=$ast.EndBlock.Statements
    if($errors.Count -or $statements.Count -ne 1 -or $statements[0] -isnot [Management.Automation.Language.PipelineAst]){return}
    $elements=$statements[0].PipelineElements
    if($elements.Count -ne 1 -or $elements[0].Expression -isnot [Management.Automation.Language.HashtableAst]){return}
    try{$baseline=$elements[0].Expression.SafeGetValue()}catch{return}
    if($baseline.Count -ne 1 -or !$baseline.ContainsKey('Targets') -or !@($baseline.Targets).Count){return}

    $before=[Collections.Generic.Dictionary[string,hashtable]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($target in $baseline.Targets){
        if($target -isnot [hashtable] -or $target.Name -isnot [string] -or !$target.Name -or !$before.TryAdd($target.Name,$target)){return}
    }
    $current=Import-PowerShellDataFile -LiteralPath $CurrentPath
    $names=@($current.Targets | ForEach-Object Name)
    if(@($before.Keys | Where-Object {$_ -cnotin $names}).Count){return}

    $changed=@(foreach($target in $current.Targets){
        $old=$null
        if(!$before.TryGetValue($target.Name,[ref]$old)){
            $target.Name
            continue
        }
        $oldJson=[Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json -InputObject $old -Depth 20 -Compress -WarningAction Stop))
        $newJson=[Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json -InputObject $target -Depth 20 -Compress -WarningAction Stop))
        if(![Text.Json.Nodes.JsonNode]::DeepEquals($oldJson,$newJson)){$target.Name}
    })
    [pscustomobject]@{ChangedNames=[string[]]$changed}
}

function Get-QuietScriptsImpact {
    <#
    .SYNOPSIS
    Selects the script test files and mutation targets that changed scripts or script tests can affect.
    .DESCRIPTION
    A test file is selected when it changed, when the scripts closure of its references (Get-QuietScriptMutationSourceFiles
    from the file and the support modules) contains a changed script, or, for any script change, when it declares
    '#ScriptsImpact: AllScripts' on a line of its own because it reads every script (inventories, analyzers). A mutation
    target is selected when a changed path is its module closure, one of its unit test files or one of its Inputs.
    A comparable mutation catalogue change selects the added or edited targets and their unit tests.
    Every test and every target is selected, with the reason, when a changed path is deleted, is a script data file (not
    .ps1 or .psm1), is a test-root file other than a unit or integration *.Tests.ps1 (support, analyzer, settings,
    targets, inventories), or lies in the closure of Invoke-ScriptsTests.ps1; every target, when it lies in the closure of
    Invoke-ScriptsMutation.ps1. Markdown paths select nothing. Errors: ScriptsImpactPathInvalid for an unsafe path and
    ScriptsImpactPathOutsideScripts for a path outside scripts/ and test/scripts/.
    .PARAMETER WorkspaceRoot
    Checkout whose scripts/ and test/scripts/ are inspected.
    .PARAMETER ChangedPaths
    Repository-relative changed paths, '/'-separated, under scripts/ or test/scripts/.
    .PARAMETER PreviousMutationCatalogue
    Literal mutation catalogue from the baseline. A missing or uncomparable baseline keeps the shared-input fallback.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$ChangedPaths,[string]$PreviousMutationCatalogue)
    $ErrorActionPreference='Stop'
    foreach($path in $ChangedPaths){if(!$path -or $path.Contains([char]0) -or $path.Contains('\') -or $path.StartsWith('/') -or $path.Split('/') -contains '..'){throw 'ScriptsImpactPathInvalid'}}
    foreach($path in $ChangedPaths){if(!$path.StartsWith('scripts/',[StringComparison]::Ordinal) -and !$path.StartsWith('test/scripts/',[StringComparison]::Ordinal)){throw ('ScriptsImpactPathOutsideScripts: '+$path)}}
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $scriptsRoot=[IO.Path]::Combine($root,'scripts');$testsRoot=[IO.Path]::Combine($root,'test','scripts')
    $cataloguePath='test/scripts/mutation.targets.psd1'
    $catalogueFile=[IO.Path]::Combine($root,$cataloguePath)
    $targets=@(Read-QuietScriptMutationTargets -Path $catalogueFile -ScriptsRoot $scriptsRoot -TestsRoot $testsRoot)
    $testFiles=@(Get-QuietScriptsTestFiles $testsRoot)
    $reasons=[Collections.Generic.List[object]]::new()
    $changed=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $allTests=$null;$allTargets=$null
    $catalogueTests=@()
    $catalogueTargets=@()
    foreach($path in $ChangedPaths){
        if($path.EndsWith('.md',[StringComparison]::Ordinal)){continue}
        if($path -ceq $cataloguePath){
            $comparison=Compare-QuietScriptMutationCatalogue -Previous $PreviousMutationCatalogue -CurrentPath $catalogueFile
            if($comparison){
                $catalogueTargets=$comparison.ChangedNames
                $catalogueTests=@($targets | Where-Object {$_.Name -cin $catalogueTargets} | ForEach-Object UnitTestFiles)
                continue
            }
        }
        $full=[IO.Path]::GetFullPath([IO.Path]::Combine($root,$path))
        $reason=if(![IO.File]::Exists($full)){'DeletedScriptInput'}
            elseif($path.StartsWith('test/',[StringComparison]::Ordinal)){if($path -cnotmatch '^test/scripts/(unit|integration)/.+\.Tests\.ps1$'){'SharedTestInput'}}
            elseif($path -cnotmatch '\.(ps1|psm1)$'){'ScriptData'}
        if($reason){
            if(!$allTests){$allTests=$path+': '+$reason}
            if(!$allTargets){$allTargets=$path+': '+$reason}
        }else{$changed[$full]=$path}
    }
    $closure={param([string]$Module,[string[]]$Tests)@(Get-QuietScriptMutationSourceFiles -ScriptsRoot $scriptsRoot -Module $Module -TestsRoot $testsRoot -UnitTestFiles $Tests)}
    $hit={param([string[]]$Paths)foreach($candidate in $Paths){if($changed.ContainsKey($candidate)){return $changed[$candidate]}}}
    if($changed.Count){
        $runner=& $hit (& $closure 'Invoke-ScriptsTests.ps1' @())
        if($runner){
            if(!$allTests){$allTests=$runner+': TestRunnerChanged'}
            if(!$allTargets){$allTargets=$runner+': TestRunnerChanged'}
        }
        $engine=& $hit (& $closure 'Invoke-ScriptsMutation.ps1' @())
        if($engine -and !$allTargets){$allTargets=$engine+': MutationEngineChanged'}
    }
    $selectedTests=[Collections.Generic.List[string]]::new()
    foreach($file in $testFiles){
        $full=[IO.Path]::GetFullPath([IO.Path]::Combine($testsRoot,$file))
        $why=if($allTests){$allTests}
            elseif($changed.ContainsKey($full)){$changed[$full]+': TestChanged'}
            elseif($file -cin $catalogueTests){$cataloguePath+': MutationTargetChanged'}
            elseif($changed.Count){
                $reached=& $hit (& $closure '' @($file))
                if($reached){$reached+': ReachesScript'}
                elseif([IO.File]::ReadAllText($full) -cmatch '(?m)^#ScriptsImpact: AllScripts\s*$'){@($changed.Values)[0]+': ReadsEveryScript'}
            }
        if($why){$selectedTests.Add($file);$reasons.Add([pscustomobject]@{Selection='script-test';Name=$file;Reason=$why})}
    }
    $selectedTargets=[Collections.Generic.List[string]]::new()
    foreach($target in $targets){
        $why=if($allTargets){$allTargets}
            elseif($target.Name -cin $catalogueTargets){$cataloguePath+': MutationTargetChanged'}
            elseif($changed.Count){
                $observed=@(& $closure ([string]$target.Module) @($target.UnitTestFiles))+@(foreach($file in @($target.UnitTestFiles)){[IO.Path]::GetFullPath([IO.Path]::Combine($testsRoot,$file))})+@(Get-QuietScriptMutationInputFiles -WorkspaceRoot $root -Inputs @($target.Inputs|Where-Object {$_}))
                $reached=& $hit $observed
                if($reached){$reached+': ReachesTarget'}
            }
        if($why){$selectedTargets.Add([string]$target.Name);$reasons.Add([pscustomobject]@{Selection='script-mutation';Name=[string]$target.Name;Reason=$why})}
    }
    [pscustomobject]@{SchemaVersion=1;AllTests=[bool]$allTests;AllTargets=[bool]$allTargets;TestFiles=[string[]]$selectedTests.ToArray();MutationTargets=[string[]]$selectedTargets.ToArray();Reasons=$reasons.ToArray()}
}
function Resolve-QuietScriptsCiSelection {
    <#
    .SYNOPSIS
    Expands and validates the script-test and mutation selections a caller hands to the tooling workflow.
    .DESCRIPTION
    Scope full runs every campaign and accepts only 'all' selections; scope scripts runs only the selected ones. Each
    selection is 'all' or a JSON array of names. Tests stay 'all' (one qualifying run with coverage) or become the
    validated test files; targets always become the validated target names, 'all' expanding to the whole catalogue in
    its order. RequiresBuild is true when the tests include one declaring '#ScriptsImpact: RequiresBuild' on a line of
    its own (an entry point that drives the built quiet engine). Errors: ToolingScopeInvalid, ToolingFullScopeSelectsAll,
    ScriptsCiSelectionInvalid for a value that is neither, ScriptsCiTestUnknown and ScriptsCiTargetUnknown for a name
    outside the catalogue.
    .PARAMETER WorkspaceRoot
    Checkout whose test/scripts/ supplies the test files and the targets file.
    .PARAMETER Scope
    full or scripts.
    .PARAMETER Tests
    'all' or a JSON array of test files relative to test/scripts.
    .PARAMETER Targets
    'all' or a JSON array of mutation target names.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$Scope,[Parameter(Mandatory)][string]$Tests,[Parameter(Mandatory)][string]$Targets)
    $ErrorActionPreference='Stop'
    if($Scope -cnotin @('full','scripts')){throw 'ToolingScopeInvalid'}
    if($Scope -ceq 'full' -and ($Tests -cne 'all' -or $Targets -cne 'all')){throw 'ToolingFullScopeSelectsAll'}
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $testsRoot=[IO.Path]::Combine($root,'test','scripts')
    $read={param([string]$Value)
        if($Value -ceq 'all'){return}
        if(!(Test-Json -Json $Value -ErrorAction Ignore)){throw 'ScriptsCiSelectionInvalid'}
        $items=ConvertFrom-Json -InputObject $Value -NoEnumerate
        if($items -isnot [array] -or @($items|Where-Object {$_ -isnot [string] -or !$_}).Count){throw 'ScriptsCiSelectionInvalid'}
        ,[string[]]@($items)
    }
    $testNames=& $read $Tests
    $targetNames=& $read $Targets
    $knownTests=@(Get-QuietScriptsTestFiles $testsRoot)
    foreach($name in $testNames){if($name -cnotin $knownTests){throw ('ScriptsCiTestUnknown: '+$name)}}
    $catalogue=@((Read-QuietScriptMutationTargets -Path ([IO.Path]::Combine($testsRoot,'mutation.targets.psd1')) -ScriptsRoot ([IO.Path]::Combine($root,'scripts')) -TestsRoot $testsRoot).Name)
    foreach($name in $targetNames){if($name -cnotin $catalogue){throw ('ScriptsCiTargetUnknown: '+$name)}}
    $selectedTests=if($null -eq $testNames){$knownTests}else{@($knownTests|Where-Object {$_ -cin $testNames})}
    $selectedTargets=if($null -eq $targetNames){$catalogue}else{@($catalogue|Where-Object {$_ -cin $targetNames})}
    $build=@($selectedTests|Where-Object {[IO.File]::ReadAllText([IO.Path]::Combine($testsRoot,$_)) -cmatch '(?m)^#ScriptsImpact: RequiresBuild\s*$'}).Count -gt 0
    [pscustomobject]@{
        AllTests=$null -eq $testNames
        TestFiles=[string[]]@($selectedTests)
        MutationTargets=[string[]]@($selectedTargets)
        RequiresBuild=$build
    }
}
Export-ModuleMember -Function Get-QuietScriptsTestFiles,Get-QuietScriptsImpact,Resolve-QuietScriptsCiSelection
